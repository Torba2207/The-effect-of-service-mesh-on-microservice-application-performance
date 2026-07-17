#!/usr/bin/env python3
"""Phase B metrics collector.

For one steady-state run it (a) reads the k6 per-scenario summary JSON and
(b) queries Prometheus for per-service CPU/RAM over the [start,end] window,
then appends long-format rows to the master CSV.

Two row types are emitted:
  - resource : one per in-cluster service + _controlplane + _ingress
               (CPU millicores / RAM MiB for app and sidecar containers)
  - latency  : one per k6 scenario (p50/p90/p95/p99/avg/max, reqs, fail_rate)

Resources and latency are decoupled because, under aggregate load, one service
(e.g. permutation) serves several scenarios — so they do not map 1:1.
"""
import argparse
import csv
import json
import os
import urllib.parse
import urllib.request

SIDECAR = {"istio": "istio-proxy", "linkerd": "linkerd-proxy", "baseline": None}
CONTROL_NS = {"istio": "istio-system", "linkerd": "linkerd"}

# csv service -> (pod regex, app container name)
SERVICES = {
    "permutation":      ("permutation-service-.*",            "permutation-service"),
    "fibonacci":        ("fibonacci-service-.*",              "fibonacci-service"),
    "integration":      ("integration-service-.*",            "integration-service"),
    "differential":     ("differential-equations-service-.*", "differential-equations-service"),
    "digital-filters":  ("digital-filters-service-.*",        "digital-filters-service"),
    "video":            ("video-service-.*",                  "video-service"),
}

# k6 scenario -> host service (for latency rows; "ai-external" is off-cluster)
SCENARIO_HOST = {
    "permutation_generate":  "permutation",
    "permutation_from_ai":   "permutation",
    "fibonacci_calculate":   "fibonacci",
    "integration_calculate": "integration",
    "differential_solve":    "differential",
    "filters_apply_image":   "digital-filters",
    "filters_ai_matrix":     "digital-filters",
    "video_compress":        "video",
    "ai_generate":           "ai-external",
}

FIELDS = [
    "run_id", "config", "mesh", "mtls", "level", "rep",
    "steady_start_utc", "steady_end_utc", "row_type", "service", "scenario",
    "rps_target", "reqs", "fail_rate",
    "lat_avg_ms", "lat_p50_ms", "lat_p90_ms", "lat_p95_ms", "lat_p99_ms", "lat_max_ms",
    "app_cpu_milli_mean", "app_cpu_milli_p95",
    "sidecar_cpu_milli_mean", "sidecar_cpu_milli_p95",
    "app_mem_mib_mean", "app_mem_mib_max",
    "sidecar_mem_mib_mean", "sidecar_mem_mib_max",
]


def prom_query(prom, expr, t):
    url = prom.rstrip("/") + "/api/v1/query?" + urllib.parse.urlencode({"query": expr, "time": str(t)})
    try:
        with urllib.request.urlopen(url, timeout=25) as r:
            d = json.load(r)
    except Exception as e:  # noqa: BLE001
        print("  ! prom query failed:", e)
        return None
    if d.get("status") != "success" or not d["data"]["result"]:
        return None
    try:
        return float(d["data"]["result"][0]["value"][1])
    except (KeyError, IndexError, ValueError):
        return None


def cpu_milli(prom, ns, pod_re, container, start, end, stat):
    dur = max(int(end - start), 15)
    inner = ('sum(rate(container_cpu_usage_seconds_total{namespace="%s",pod=~"%s",container="%s"}[30s]))'
             % (ns, pod_re, container))
    if stat == "mean":
        expr = "1000 * avg_over_time((%s)[%ds:5s])" % (inner, dur)
    else:
        expr = "1000 * quantile_over_time(0.95, (%s)[%ds:5s])" % (inner, dur)
    return prom_query(prom, expr, end)


def mem_mib(prom, ns, pod_re, container, start, end, stat):
    dur = max(int(end - start), 15)
    inner = ('sum(container_memory_working_set_bytes{namespace="%s",pod=~"%s",container="%s"})/1048576'
             % (ns, pod_re, container))
    fn = "avg_over_time" if stat == "mean" else "max_over_time"
    return prom_query(prom, "%s((%s)[%ds:5s])" % (fn, inner, dur), end)


def ns_total_cpu(prom, ns, start, end):
    dur = max(int(end - start), 15)
    inner = ('sum(rate(container_cpu_usage_seconds_total{namespace="%s",container!="",container!="POD"}[30s]))' % ns)
    return prom_query(prom, "1000 * avg_over_time((%s)[%ds:5s])" % (inner, dur), end)


def ns_total_mem(prom, ns, start, end):
    dur = max(int(end - start), 15)
    inner = ('sum(container_memory_working_set_bytes{namespace="%s",container!="",container!="POD"})/1048576' % ns)
    return prom_query(prom, "avg_over_time((%s)[%ds:5s])" % (inner, dur), end)


def resource_row(base, prom, mesh, service, pod_re, app, start, end):
    sc = SIDECAR.get(mesh)
    row = dict(base)
    row.update({
        "row_type": "resource", "service": service, "scenario": "",
        "app_cpu_milli_mean": cpu_milli(prom, base["ns"], pod_re, app, start, end, "mean"),
        "app_cpu_milli_p95":  cpu_milli(prom, base["ns"], pod_re, app, start, end, "p95"),
        "app_mem_mib_mean":   mem_mib(prom, base["ns"], pod_re, app, start, end, "mean"),
        "app_mem_mib_max":    mem_mib(prom, base["ns"], pod_re, app, start, end, "max"),
    })
    if sc:
        row.update({
            "sidecar_cpu_milli_mean": cpu_milli(prom, base["ns"], pod_re, sc, start, end, "mean"),
            "sidecar_cpu_milli_p95":  cpu_milli(prom, base["ns"], pod_re, sc, start, end, "p95"),
            "sidecar_mem_mib_mean":   mem_mib(prom, base["ns"], pod_re, sc, start, end, "mean"),
            "sidecar_mem_mib_max":    mem_mib(prom, base["ns"], pod_re, sc, start, end, "max"),
        })
    return row


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--prom", default="http://localhost:9090")
    ap.add_argument("--config", required=True)
    ap.add_argument("--mesh", required=True, choices=["baseline", "istio", "linkerd"])
    ap.add_argument("--mtls", required=True)
    ap.add_argument("--level", required=True)
    ap.add_argument("--rep", required=True)
    ap.add_argument("--run-id", required=True)
    ap.add_argument("--start", type=float, required=True)
    ap.add_argument("--end", type=float, required=True)
    ap.add_argument("--summary", required=True, help="k6 per-scenario JSON")
    ap.add_argument("--csv", required=True)
    ap.add_argument("--ns", default="thesis-test")
    args = ap.parse_args()

    base = {
        "run_id": args.run_id, "config": args.config, "mesh": args.mesh, "mtls": args.mtls,
        "level": args.level, "rep": args.rep,
        "steady_start_utc": int(args.start), "steady_end_utc": int(args.end), "ns": args.ns,
    }

    rows = []

    # --- resource rows: services + control plane + meshed ingress ---
    for svc, (pod_re, app) in SERVICES.items():
        rows.append(resource_row(base, args.prom, args.mesh, svc, pod_re, app, args.start, args.end))

    if args.mesh in CONTROL_NS:
        cp = dict(base)
        cp.update({"row_type": "resource", "service": "_controlplane", "scenario": "",
                   "app_cpu_milli_mean": ns_total_cpu(args.prom, CONTROL_NS[args.mesh], args.start, args.end),
                   "app_mem_mib_mean":   ns_total_mem(args.prom, CONTROL_NS[args.mesh], args.start, args.end)})
        rows.append(cp)

    # meshed nginx ingress controller (+ its sidecar in the linkerd phase)
    ing = resource_row(base, args.prom, args.mesh, "_ingress",
                       "ingress-nginx-controller-.*", "controller", args.start, args.end)
    ing["ns"] = "ingress-nginx"
    ing2 = dict(ing)
    ing2["app_cpu_milli_mean"] = cpu_milli(args.prom, "ingress-nginx", "ingress-nginx-controller-.*",
                                           "controller", args.start, args.end, "mean")
    ing2["app_mem_mib_mean"] = mem_mib(args.prom, "ingress-nginx", "ingress-nginx-controller-.*",
                                       "controller", args.start, args.end, "mean")
    if SIDECAR.get(args.mesh):
        ing2["sidecar_cpu_milli_mean"] = cpu_milli(args.prom, "ingress-nginx", "ingress-nginx-controller-.*",
                                                   SIDECAR[args.mesh], args.start, args.end, "mean")
        ing2["sidecar_mem_mib_mean"] = mem_mib(args.prom, "ingress-nginx", "ingress-nginx-controller-.*",
                                               SIDECAR[args.mesh], args.start, args.end, "mean")
    rows.append(ing2)

    # --- latency rows: one per k6 scenario ---
    try:
        with open(args.summary) as f:
            summ = json.load(f)
    except Exception as e:  # noqa: BLE001
        print("  ! could not read k6 summary:", e)
        summ = {"scenarios": {}}

    for scen, m in summ.get("scenarios", {}).items():
        row = dict(base)
        row.update({
            "row_type": "latency", "service": SCENARIO_HOST.get(scen, "?"), "scenario": scen,
            "rps_target": m.get("rps_target"), "reqs": m.get("reqs"), "fail_rate": m.get("fail_rate"),
            "lat_avg_ms": m.get("lat_avg_ms"), "lat_p50_ms": m.get("lat_p50_ms"),
            "lat_p90_ms": m.get("lat_p90_ms"), "lat_p95_ms": m.get("lat_p95_ms"),
            "lat_p99_ms": m.get("lat_p99_ms"), "lat_max_ms": m.get("lat_max_ms"),
        })
        rows.append(row)

    # --- write ---
    new = not os.path.exists(args.csv)
    with open(args.csv, "a", newline="") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS, extrasaction="ignore")
        if new:
            w.writeheader()
        w.writerows(rows)

    nres = sum(1 for r in rows if r["row_type"] == "resource")
    nlat = sum(1 for r in rows if r["row_type"] == "latency")
    print("  + %s: wrote %d rows (%d resource, %d latency) -> %s"
          % (args.run_id, len(rows), nres, nlat, args.csv))


if __name__ == "__main__":
    main()

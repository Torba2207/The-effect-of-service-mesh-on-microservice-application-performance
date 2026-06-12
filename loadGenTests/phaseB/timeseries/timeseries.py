#!/usr/bin/env python3
"""Build time-series CSVs (and optional PNG plots) for one run, no kernel access.

CPU/RAM come from the Prometheus HTTP range API (resolution ~ the scrape interval,
~15 s by default; lower the kubelet ServiceMonitor interval to densify). Latency
comes from k6's own CSV output (true per-second).

Outputs (in --outdir):
  <run>_cpu_ram.csv : t_rel_s, kind(cpu_cores|mem_mib), service, container, value
  <run>_latency.csv : t_rel_s, scenario, count, avg_ms, p50_ms, p95_ms, max_ms
  <run>.png         : 3-panel plot (with --plot)
"""
import argparse
import csv
import gzip
import json
import math
import os
import statistics
import urllib.parse
import urllib.request

SIDE = {"istio": "istio-proxy", "linkerd": "linkerd-proxy", "baseline": None}
SERVICES = {
    "permutation":     ("permutation-service-.*",            "permutation-service"),
    "fibonacci":       ("fibonacci-service-.*",              "fibonacci-service"),
    "integration":     ("integration-service-.*",            "integration-service"),
    "differential":    ("differential-equations-service-.*", "differential-equations-service"),
    "digital-filters": ("digital-filters-service-.*",        "digital-filters-service"),
    "video":           ("video-service-.*",                  "video-service"),
}


def query_range(prom, expr, start, end, step):
    q = urllib.parse.urlencode({"query": expr, "start": str(start), "end": str(end), "step": str(step)})
    with urllib.request.urlopen(prom.rstrip("/") + "/api/v1/query_range?" + q, timeout=30) as r:
        d = json.load(r)
    if d.get("status") != "success" or not d["data"]["result"]:
        return []
    return [(float(t), float(v)) for t, v in d["data"]["result"][0]["values"] if v not in ("NaN",)]


def cpu_expr(ns, pod, cont):
    return ('sum(rate(container_cpu_usage_seconds_total{namespace="%s",pod=~"%s",container="%s"}[1m]))'
            % (ns, pod, cont))


def mem_expr(ns, pod, cont):
    return ('sum(container_memory_working_set_bytes{namespace="%s",pod=~"%s",container="%s"})/1048576'
            % (ns, pod, cont))


def pull_cpu_ram(prom, mesh, start, end, step, ns):
    rows = []
    side = SIDE.get(mesh)
    items = [(svc, pod, app, "app") for svc, (pod, app) in SERVICES.items()]
    if side:
        items += [(svc, pod, side, "sidecar") for svc, (pod, _) in SERVICES.items()]
    for svc, pod, cont, role in items:
        for t, v in query_range(prom, cpu_expr(ns, pod, cont), start, end, step):
            rows.append((round(t - start, 1), "cpu_cores", svc, role, round(v, 4)))
        for t, v in query_range(prom, mem_expr(ns, pod, cont), start, end, step):
            rows.append((round(t - start, 1), "mem_mib", svc, role, round(v, 2)))
    return rows


def pct(xs, p):
    if not xs:
        return None
    xs = sorted(xs)
    k = (len(xs) - 1) * p
    f = math.floor(k)
    return xs[f] if f == len(xs) - 1 else xs[f] + (xs[f + 1] - xs[f]) * (k - f)


def parse_k6_latency(path, start):
    """Bucket http_req_duration samples per second per scenario."""
    op = gzip.open if path.endswith(".gz") else open
    buckets = {}  # (sec, scenario) -> [durations]
    with op(path, "rt") as f:
        rd = csv.DictReader(f)
        for row in rd:
            if row.get("metric_name") != "http_req_duration":
                continue
            try:
                ts = float(row["timestamp"]); val = float(row["metric_value"])
            except (KeyError, ValueError):
                continue
            sec = int(ts - start)
            key = (sec, row.get("scenario", "?"))
            buckets.setdefault(key, []).append(val)
    out = []
    for (sec, scen), ds in sorted(buckets.items()):
        out.append((sec, scen, len(ds), round(statistics.mean(ds), 3),
                    round(pct(ds, 0.50), 3), round(pct(ds, 0.95), 3), round(max(ds), 3)))
    return out


def write_csv(path, header, rows):
    with open(path, "w", newline="") as f:
        w = csv.writer(f); w.writerow(header); w.writerows(rows)


def plot(outdir, run_id, cpu_ram, latency):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from collections import defaultdict

    fig, ax = plt.subplots(3, 1, figsize=(12, 11), sharex=False)

    # CPU per service (app+sidecar summed)
    cpu = defaultdict(lambda: defaultdict(float))
    mem = defaultdict(lambda: defaultdict(float))
    for t, kind, svc, role, v in cpu_ram:
        (cpu if kind == "cpu_cores" else mem)[svc][t] += v
    for svc, series in sorted(cpu.items()):
        ts = sorted(series); ax[0].plot(ts, [series[t] for t in ts], label=svc, marker=".")
    ax[0].set_title("CPU (cores) — app + sidecar, per service"); ax[0].set_ylabel("cores")
    ax[0].legend(fontsize=7, ncol=4); ax[0].grid(alpha=0.3)
    for svc, series in sorted(mem.items()):
        ts = sorted(series); ax[1].plot(ts, [series[t] for t in ts], label=svc, marker=".")
    ax[1].set_title("Memory working-set (MiB) — app + sidecar, per service"); ax[1].set_ylabel("MiB")
    ax[1].legend(fontsize=7, ncol=4); ax[1].grid(alpha=0.3)

    lat = defaultdict(lambda: ([], []))
    for sec, scen, cnt, avg, p50, p95, mx in latency:
        lat[scen][0].append(sec); lat[scen][1].append(p95)
    for scen, (xs, ys) in sorted(lat.items()):
        ax[2].plot(xs, ys, label=scen)
    ax[2].set_title("Latency p95 (ms) per second — k6 client-side"); ax[2].set_ylabel("ms")
    ax[2].set_xlabel("t since steady start (s)"); ax[2].legend(fontsize=7, ncol=3); ax[2].grid(alpha=0.3)

    fig.suptitle("Phase B time-series :: %s" % run_id)
    fig.tight_layout()
    p = os.path.join(outdir, run_id + ".png")
    fig.savefig(p, dpi=110); print("  plot -> %s" % p)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--prom", default="http://localhost:9090")
    ap.add_argument("--mesh", required=True, choices=["baseline", "istio", "linkerd"])
    ap.add_argument("--start", type=float, required=True)
    ap.add_argument("--end", type=float, required=True)
    ap.add_argument("--step", default="5", help="CPU/RAM query step seconds (>= scrape interval)")
    ap.add_argument("--ns", default="thesis-test")
    ap.add_argument("--k6csv", default=None, help="k6 --out csv file (.csv or .csv.gz)")
    ap.add_argument("--run-id", required=True)
    ap.add_argument("--outdir", required=True)
    ap.add_argument("--plot", action="store_true")
    args = ap.parse_args()
    os.makedirs(args.outdir, exist_ok=True)

    cpu_ram = pull_cpu_ram(args.prom, args.mesh, args.start, args.end, args.step, args.ns)
    write_csv(os.path.join(args.outdir, args.run_id + "_cpu_ram.csv"),
              ["t_rel_s", "kind", "service", "container", "value"], cpu_ram)
    print("  cpu/ram points: %d (step=%ss)" % (len(cpu_ram), args.step))

    latency = []
    if args.k6csv and os.path.exists(args.k6csv):
        latency = parse_k6_latency(args.k6csv, args.start)
        write_csv(os.path.join(args.outdir, args.run_id + "_latency.csv"),
                  ["t_rel_s", "scenario", "count", "avg_ms", "p50_ms", "p95_ms", "max_ms"], latency)
        print("  latency seconds: %d" % len(latency))

    if args.plot:
        plot(args.outdir, args.run_id, cpu_ram, latency)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Back-fill per-run CPU/RAM time-series for runs already in master.csv.

The campaign stores summarized scalars (mean/p95/max) per run, but the raw series is
still in Prometheus. This reads each run's recorded steady window from master.csv and
pulls the CPU/RAM curves via query_range -> one long CSV you can plot. Works for past
runs (within Prometheus retention) and any future config. No re-running needed.

Output (default results/timeseries_cpu_ram.csv):
  run_id, config, mesh, level, rep, t_rel_s, kind(cpu_cores|mem_mib|gpu_util_pct), service, container, value

The bare-metal AI host is included when Prometheus scrapes it (ai_host_metrics.py): service
_ai_host (container app = AI containers, sidecar = the host's mesh proxy), _ai_host_meshinfra
(Consul agent / SPIRE) and _ai_host_total (whole host CPU/RAM, container gpu = GPU utilisation).

Optional: --plot-run <run_id> renders a CPU+RAM PNG for one run.
"""
import argparse
import csv
import json
import os
import sys
import urllib.parse
import urllib.request

sys.dont_write_bytecode = True   # no __pycache__ in the clone (lg_campaign.sh needs a clean tree)
import ai_host_metrics as aihost  # noqa: E402

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
    try:
        with urllib.request.urlopen(prom.rstrip("/") + "/api/v1/query_range?" + q, timeout=30) as r:
            d = json.load(r)
    except Exception as e:  # noqa: BLE001
        print("  ! query failed:", e); return []
    if d.get("status") != "success" or not d["data"]["result"]:
        return []
    return [(float(t), float(v)) for t, v in d["data"]["result"][0]["values"] if v != "NaN"]


def series_for_run(prom, mesh, start, end, step, ns):
    side = SIDE.get(mesh)
    items = [(svc, pod, app, "app") for svc, (pod, app) in SERVICES.items()]
    if side:
        items += [(svc, pod, side, "sidecar") for svc, (pod, _) in SERVICES.items()]
    # meshed ingress controller (+ proxy) and mesh control plane
    items += [("_ingress", "ingress-nginx-controller-.*", "controller", "app")]
    if side:
        items += [("_ingress", "ingress-nginx-controller-.*", side, "sidecar")]
    # (service, role, kind, expression)
    exprs = []
    for svc, pod, cont, role in items:
        ns_ = "ingress-nginx" if svc == "_ingress" else ns
        sel = 'namespace="%s",pod=~"%s",container="%s"' % (ns_, pod, cont)
        exprs += [(svc, role, "cpu_cores", aihost.cpu_expr(sel, "1m")),
                  (svc, role, "mem_mib", aihost.mem_expr(sel))]
    # bare-metal AI host (empty series when Prometheus does not scrape it)
    for svc, role, sel in aihost.groups(mesh):
        exprs += [(svc, role, "cpu_cores", aihost.cpu_expr(sel, "1m")),
                  (svc, role, "mem_mib", aihost.mem_expr(sel))]
    exprs += [("_ai_host_total", "app", "cpu_cores", aihost.node_cpu_expr("1m")),
              ("_ai_host_total", "app", "mem_mib", aihost.node_mem_expr()),
              ("_ai_host_total", "gpu", "gpu_util_pct", aihost.gpu_util_expr())]
    rows = []
    for svc, role, kind, expr in exprs:
        for t, v in query_range(prom, expr, start, end, step):
            rows.append((round(t - start, 1), kind, svc, role, round(v, 4 if kind == "cpu_cores" else 2)))
    return rows


def load_runs(master):
    runs = {}
    for r in csv.DictReader(open(master)):
        rid = r["run_id"]
        if rid not in runs:
            runs[rid] = {"config": r["config"], "mesh": r["mesh"], "level": r["level"],
                         "rep": r["rep"], "start": float(r["steady_start_utc"]), "end": float(r["steady_end_utc"])}
    return runs


def plot_run(rows, run_id, path):
    import matplotlib; matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from collections import defaultdict
    cpu = defaultdict(lambda: defaultdict(float)); mem = defaultdict(lambda: defaultdict(float))
    for t, kind, svc, role, v in rows:
        if kind in ("cpu_cores", "mem_mib") and svc != "_ai_host_total":   # host total would dwarf the rest
            (cpu if kind == "cpu_cores" else mem)[svc][t] += v
    fig, ax = plt.subplots(2, 1, figsize=(12, 8))
    for svc, s in sorted(cpu.items()):
        ts = sorted(s); ax[0].plot(ts, [s[t] for t in ts], marker=".", label=svc)
    ax[0].set_title("CPU (cores) over time — %s" % run_id); ax[0].set_ylabel("cores"); ax[0].legend(fontsize=7, ncol=4); ax[0].grid(alpha=0.3)
    for svc, s in sorted(mem.items()):
        ts = sorted(s); ax[1].plot(ts, [s[t] for t in ts], marker=".", label=svc)
    ax[1].set_title("RAM working-set (MiB) over time"); ax[1].set_ylabel("MiB"); ax[1].set_xlabel("t since steady start (s)")
    ax[1].legend(fontsize=7, ncol=4); ax[1].grid(alpha=0.3)
    fig.tight_layout(); fig.savefig(path, dpi=110); print("  plot -> %s" % path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--prom", default="http://localhost:9090")
    ap.add_argument("--master", default="results/master.csv")
    ap.add_argument("--out", default="results/timeseries_cpu_ram.csv")
    ap.add_argument("--step", default="10", help="seconds (>= ~15s cadvisor resolution)")
    ap.add_argument("--ns", default="thesis-test")
    ap.add_argument("--config", default=None, help="only extract runs with this config label")
    ap.add_argument("--run-id", default=None, help="only extract this one run (for per-run, fresh extraction)")
    ap.add_argument("--append", action="store_true", help="append instead of overwrite (per-run use)")
    ap.add_argument("--plot-run", default=None)
    args = ap.parse_args()

    runs = load_runs(args.master)
    if args.config:
        runs = {k: v for k, v in runs.items() if v["config"] == args.config}
    if args.run_id:
        runs = {k: v for k, v in runs.items() if k == args.run_id}
    header_needed = not (args.append and os.path.exists(args.out) and os.path.getsize(args.out) > 0)
    with open(args.out, "a" if args.append else "w", newline="") as f:
        w = csv.writer(f)
        if header_needed:
            w.writerow(["run_id", "config", "mesh", "level", "rep", "t_rel_s", "kind", "service", "container", "value"])
        total = 0
        for rid, meta in runs.items():
            rows = series_for_run(args.prom, meta["mesh"], meta["start"], meta["end"], args.step, args.ns)
            for t, kind, svc, role, v in rows:
                w.writerow([rid, meta["config"], meta["mesh"], meta["level"], meta["rep"], t, kind, svc, role, v])
            total += len(rows)
            if args.plot_run and rid == args.plot_run:
                plot_run(rows, rid, os.path.join(os.path.dirname(args.out) or ".", rid + "_cpuram.png"))
        print("wrote %d time-series points -> %s" % (total, args.out))


if __name__ == "__main__":
    main()

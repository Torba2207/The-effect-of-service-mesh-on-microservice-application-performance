#!/usr/bin/env python3
"""Comparison plots across configs (baseline=green, linkerd=blue, istio=red).

Overall (3 figures): mean over all 6 services (app+sidecar) of CPU, RAM (time-scale,
from timeseries_<config>.csv at the chosen load level) and Latency (histogram of p95
by load level, from master.csv — no per-request time-series for campaign runs).

Per-service (one 1x3 figure each): CPU & RAM time-scale + Latency histogram.

Usage: python3 make_plots.py [--level high] [--out results/plots]
"""
import argparse
import csv
import os
import statistics
from collections import defaultdict

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

CONFIGS = [("baseline", "green", "baseline"),
           ("linkerd_mtls", "blue", "linkerd+mTLS"),
           ("istio_mtls", "red", "istio+mTLS")]
SERVICES = ["permutation", "fibonacci", "integration", "differential", "digital-filters", "video"]
SCEN = {"permutation": "permutation_generate", "fibonacci": "fibonacci_calculate",
        "integration": "integration_calculate", "differential": "differential_solve",
        "digital-filters": "filters_apply_image", "video": "video_compress"}
LEVELS = ["low", "med", "high"]


def fnum(x):
    try: return float(x)
    except (TypeError, ValueError): return None


def load_ts(cfg, level):
    path = "results/timeseries_%s.csv" % cfg
    if not os.path.exists(path):
        return []
    return [r for r in csv.DictReader(open(path)) if r["level"] == level]


def curve(rows, kind, services, scale):
    """mean over `services` of (app+sidecar), averaged over reps, per t_rel_s."""
    persvc = defaultdict(float)            # (run, t, service) -> app+sidecar
    for r in rows:
        if r["kind"] != kind or r["service"] not in services:
            continue
        persvc[(r["run_id"], float(r["t_rel_s"]), r["service"])] += float(r["value"])
    permeanrun = defaultdict(list)         # (run, t) -> [per-service values]
    for (run, t, _svc), v in persvc.items():
        permeanrun[(run, t)].append(v)
    runmean = {k: sum(v) / len(v) for k, v in permeanrun.items()}  # mean across services
    byt = defaultdict(list)
    for (run, t), v in runmean.items():
        byt[t].append(v)
    ts = sorted(byt)
    return ts, [statistics.mean(byt[t]) * scale for t in ts]


def lat_p95(master, cfg, scenarios, level):
    vals = []
    for s in scenarios:
        v = [fnum(r["lat_p95_ms"]) for r in master
             if r["row_type"] == "latency" and r["config"] == cfg and r["scenario"] == s
             and r["level"] == level and fnum(r["lat_p95_ms"]) is not None]
        if v:
            vals.append(statistics.mean(v))
    return statistics.mean(vals) if vals else 0


def bars(ax, master, scenarios, title):
    x = np.arange(len(LEVELS)); w = 0.26
    for i, (cfg, color, label) in enumerate(CONFIGS):
        vals = [lat_p95(master, cfg, scenarios, lv) for lv in LEVELS]
        ax.bar(x + (i - 1) * w, vals, w, label=label, color=color, alpha=0.85)
    ax.set_xticks(x); ax.set_xticklabels([l + " RPS" for l in LEVELS])
    ax.set_ylabel("latency p95 (ms)"); ax.set_title(title); ax.grid(axis="y", alpha=0.3); ax.legend(fontsize=8)


def lineplot(ax, kind, services, scale, ylabel, title, level):
    for cfg, color, label in CONFIGS:
        ts, ys = curve(load_ts(cfg, level), kind, services, scale)
        if ts:
            ax.plot(ts, ys, color=color, marker=".", label=label)
    ax.set_xlabel("t since steady start (s)"); ax.set_ylabel(ylabel)
    ax.set_title(title); ax.grid(alpha=0.3); ax.legend(fontsize=8)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--level", default="high")
    ap.add_argument("--out", default="results/plots")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    master = list(csv.DictReader(open("results/master.csv")))
    lv = args.level

    # ---- OVERALL (3 figures) ----
    fig, ax = plt.subplots(figsize=(10, 5))
    lineplot(ax, "cpu_cores", SERVICES, 1000, "CPU (millicores)",
             "Overall CPU — mean of all services (app+sidecar) @ %s load" % lv, lv)
    fig.tight_layout(); fig.savefig(os.path.join(args.out, "overall_cpu.png"), dpi=120); plt.close(fig)

    fig, ax = plt.subplots(figsize=(10, 5))
    lineplot(ax, "mem_mib", SERVICES, 1, "RAM working-set (MiB)",
             "Overall RAM — mean of all services (app+sidecar) @ %s load" % lv, lv)
    fig.tight_layout(); fig.savefig(os.path.join(args.out, "overall_ram.png"), dpi=120); plt.close(fig)

    fig, ax = plt.subplots(figsize=(8, 5))
    bars(ax, master, list(SCEN.values()), "Overall Latency — mean p95 across all services")
    fig.tight_layout(); fig.savefig(os.path.join(args.out, "overall_latency.png"), dpi=120); plt.close(fig)

    # ---- PER-SERVICE (1x3 each) ----
    for svc in SERVICES:
        fig, ax = plt.subplots(1, 3, figsize=(18, 4.5))
        lineplot(ax[0], "cpu_cores", [svc], 1000, "CPU (millicores)",
                 "%s — CPU @ %s" % (svc, lv), lv)
        lineplot(ax[1], "mem_mib", [svc], 1, "RAM (MiB)",
                 "%s — RAM @ %s" % (svc, lv), lv)
        bars(ax[2], master, [SCEN[svc]], "%s — Latency p95" % svc)
        fig.tight_layout()
        fig.savefig(os.path.join(args.out, "service_%s.png" % svc), dpi=120); plt.close(fig)

    print("wrote: overall_{cpu,ram,latency}.png + service_<6>.png -> %s" % args.out)
    print("configs:", [c[0] for c in CONFIGS], "| time-scale level:", lv)


if __name__ == "__main__":
    main()

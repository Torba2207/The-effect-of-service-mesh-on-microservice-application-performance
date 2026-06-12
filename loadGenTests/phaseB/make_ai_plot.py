#!/usr/bin/env python3
"""AI / S2-ext chain-latency comparison across configs (closed-loop probe).

The AI service is external (no in-cluster CPU/RAM) and measured closed-loop, so this is
latency-only: grouped bars of p50 with a whisker up to p95, per AI scenario, per config.
Reads results/ai_probe.csv -> results/plots/ai_probe_latency.png
"""
import csv
import os

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

CONFIGS = [("baseline", "green", "baseline"),
           ("linkerd_mtls", "blue", "linkerd+mTLS"),
           ("istio_mtls", "red", "istio+mTLS"),
           ("istio_nomtls", "orange", "istio (no mTLS)"),
           ("linkerd_nomtls", "purple", "linkerd (no mTLS)")]
SCEN = [("ai_generate", "ai_generate\n(direct)"),
        ("permutation_from_ai", "permutation->ai\n(S2-ext)"),
        ("filters_ai_matrix", "filters->ai\n(S2-ext)")]


def main():
    rows = list(csv.DictReader(open("results/ai_probe.csv")))
    present = [c for c in CONFIGS if any(r["config"] == c[0] for r in rows)]

    def val(cfg, scen, col):
        for r in rows:
            if r["config"] == cfg and r["scenario"] == scen:
                try: return float(r[col])
                except (TypeError, ValueError): return 0.0
        return 0.0

    os.makedirs("results/plots", exist_ok=True)
    fig, ax = plt.subplots(figsize=(12, 6))
    x = np.arange(len(SCEN))
    n = len(present)
    w = 0.8 / n
    for i, (cfg, color, label) in enumerate(present):
        p50 = [val(cfg, s[0], "lat_p50_ms") for s in SCEN]
        p95 = [val(cfg, s[0], "lat_p95_ms") for s in SCEN]
        upper = [max(0.0, b - a) for a, b in zip(p50, p95)]
        off = (i - (n - 1) / 2) * w
        ax.bar(x + off, p50, w, color=color, label=label, alpha=0.85,
               yerr=[[0] * len(p50), upper], capsize=3, ecolor="black")
    ax.set_xticks(x); ax.set_xticklabels([s[1] for s in SCEN])
    ax.set_ylabel("chain latency (ms)   [bar = p50, whisker -> p95]")
    ax.set_title("AI / S2-ext chain latency by config (closed-loop probe, 30 samples each)")
    ax.grid(axis="y", alpha=0.3); ax.legend()
    fig.tight_layout()
    fig.savefig("results/plots/ai_probe_latency.png", dpi=120)
    print("wrote results/plots/ai_probe_latency.png  | configs:", [c[0] for c in present])


if __name__ == "__main__":
    main()

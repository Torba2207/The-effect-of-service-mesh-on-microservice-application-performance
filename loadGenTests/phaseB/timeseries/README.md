# Phase B — time-series capture (no kernel, no Grafana)

Captures CPU/RAM/latency **over time** for a single run and writes CSVs + a PNG plot.
Use for detailed inspection of a representative run; use `../run_phaseB.sh` for the
150-run summary campaign.

```bash
./capture_run.sh -c linkerd_mtls -m linkerd -t on -l high
# opts: -l low|med|high  -S 120s steady  -W 30s warmup  -p 5 (cpu/ram step s)  -u URL  -I (AI)
```

Outputs in `../results/ts/`:
- `<run>_latency.csv` — `t_rel_s, scenario, count, avg_ms, p50_ms, p95_ms, max_ms`
- `<run>_cpu_ram.csv` — `t_rel_s, kind(cpu_cores|mem_mib), service, container(app|sidecar), value`
- `<run>.png` — 3 panels: CPU/service, RAM/service, latency p95/scenario over time.

## Resolution (important)
| Metric | Source | Real resolution |
|--------|--------|-----------------|
| **Latency** | k6 `--out csv` (per request) | **true 1 s** (or finer) |
| **CPU / RAM** | Prometheus `query_range` | **≈ scrape interval ~15 s** (cadvisor refresh) |

`-p` only sets the query grid; it cannot beat the underlying ~15 s cadvisor resolution.
NOTE (tested): lowering the Prometheus scrape interval does **not** help — the kubelet
`/metrics/cadvisor` endpoint has `honorTimestamps=true` and cadvisor stamps metrics with its
own ~15 s housekeeping clock, so faster scraping just re-reads identically-stamped data.
Beating ~15 s requires a node-level change (kubelet `--housekeeping-interval`) or reading
cgroups on the nodes — both outside this Prometheus-only tool. So CPU/RAM stays ~15 s;
latency stays true 1 s.

## Plotting elsewhere
The CSVs are tidy/long — load into pandas, Excel, gnuplot, etc. `timeseries.py` can be run
standalone against any recorded `--start/--end` window (CPU/RAM is in Prometheus regardless;
pass `--k6csv` for latency). Grafana is optional, not required.

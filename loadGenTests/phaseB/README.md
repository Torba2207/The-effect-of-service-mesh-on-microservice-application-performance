# Phase B — Aggregate full-system benchmark

Drives **all services concurrently** at a per-level rate and records CPU, RAM and latency for
each mesh configuration. See `thesis-metrics/test-scenario.typ` (§8 Phase B) for the
methodology. One `run_phaseB.sh` invocation covers one configuration = 3 load levels × 10
repetitions = 30 runs (~1.6 h).

Configurations to cover: `baseline`, `linkerd_mtls`, `linkerd_nomtls`, `istio_mtls`,
`istio_nomtls`. Switch the cluster deployment between them, then invoke once per config.

---

## Files
| File | Runs on | Purpose |
|------|---------|---------|
| `aggregate.js` | lg (k6) | One k6 scenario per service, all concurrent; writes a per-scenario latency JSON. |
| `run_phaseB.sh` | workstation | Orchestrates one config: warmup→steady→cooldown × levels × reps; pulls Prometheus; writes CSVs. |
| `collect_metrics.py` | workstation | Queries Prometheus for per-service CPU/RAM over the steady window; merges k6 latency → `results/master.csv`. |
| `extract_timeseries.py` | workstation | Per run, pulls CPU/RAM **curves** (`query_range`) → `results/timeseries_<config>.csv`. |
| `ai_probe/` | workstation + lg | Closed-loop (1 VU) probe for the AI / S2-ext chains → `results/ai_probe.csv`. |
| `timeseries/` | workstation + lg | Single-run capture with true per-second latency (`capture_run.sh`). |
| `make_plots.py`, `make_ai_plot.py` | workstation | Comparison figures → `results/plots/`. |
| `../common/assets/` | — | Fixed work-unit inputs (`filter_input_128.png`, `sample_360p_1s.mp4`) + `make_assets.sh`, shared across phases. |

## Prerequisites
- Workstation: `kubectl` (context `projekt-badawchy-cluster`), `python3` (+ matplotlib for plots),
  `ssh`/`scp`, the SSH key `~/Documents/PG/Projects/.sshkeys/pgPB`.
- Load generator `lg` (10.29.20.130): `k6` installed. The script + assets are synced automatically.
- The target config must already be **deployed** (`make baseline|istio|linkerd` + mTLS state set),
  and for Istio the gateway NodePort resolved for `-u`.

## Quick start
```bash
# Linkerd + mTLS (URL defaults to http://10.29.20.113:30080)
./run_phaseB.sh -c linkerd_mtls -m linkerd -t on

# Baseline (no mesh)
./run_phaseB.sh -c baseline -m baseline -t na

# Istio — resolve the dynamic Envoy gateway NodePort for -u
GWPORT=$(kubectl --context projekt-badawchy-cluster -n istio-system get svc istio-ingressgateway \
  -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')
./run_phaseB.sh -c istio_mtls -m istio -t on -u http://10.29.20.113:$GWPORT
```
**Validate first:** `-r 1 -l high` per config and confirm `fail_rate < 0.01` before the full run.

---

## `aggregate.js` — the k6 load model (runs on lg)

A single k6 script that drives **every benchmarked service at once**, each as an independent k6
*scenario*, so the whole system is under realistic mixed contention (not one service at a time).

### Scenarios and the open-loop model
Nine functions are defined, one per benchmarked endpoint. Each is wired to its own
`constant-arrival-rate` scenario — an **open-loop** executor: k6 fires requests at a fixed target
rate regardless of how fast responses come back. This is deliberate: if a mesh slows a service,
latency rises and errors appear, rather than throughput silently dropping (a closed-loop model
would mask the overhead). Per-scenario VU pools (`preAllocatedVUs`/`maxVUs`) are sized so k6 can
always sustain the target rate; heavy `video_compress` and the AI scenarios get smaller pools.

### Per-level rates (`RATES`)
Rate is chosen by the `LEVEL` env (`low`/`med`/`high`):

| Scenario | Endpoint | Class | low / med / high |
|----------|----------|-------|------------------|
| `permutation_generate` | `POST /api/permutation/generate` | S1 STD | 25 / 50 / 100 rps |
| `fibonacci_calculate` | `POST /api/fibonacci/calculate` | S1 STD | 25 / 50 / 100 |
| `integration_calculate` | `POST /api/integration/calculate` | S1 STD | 25 / 50 / 100 |
| `filters_apply_image` | `POST /api/filters/apply-image` (multipart) | S1 STD | 25 / 50 / 100 |
| `differential_solve` | `POST /api/differential/solve` | S2-int | 25 / 50 / 100 |
| `video_compress` | `POST /api/video/compress` (multipart) | S1 HVY | 1 / 1 / 2 |
| `ai_generate` | `POST /api/Ai/generate` | S1 HVY | 0.1 rps* |
| `permutation_from_ai` | `POST /api/permutation/generate-from-ai` | S2-ext | 0.1 rps* |
| `filters_ai_matrix` | `POST /api/filters/apply-ai-matrix` | S2-ext | 0.1 rps* |

\* The three **AI scenarios are OFF by default** (`INCLUDE_AI=false`). The AI service is CPU LLM
inference (~6–7 s/req, ~0.3 req/s hard ceiling), so it cannot take a rate-based load. When opted
in (`-I`), they run at a trickle via a **10 s `timeUnit`** (rate 1 / 10 s = 0.1 req/s each). For
real AI numbers use the closed-loop `ai_probe/` instead.

### Fixed work units (reproducibility)
Every scenario uses one immutable payload so per-request work is constant across runs and configs:
permutation `[1..7]`, fibonacci `n=3000`, integration `steps=20000`, differential `x^2` (`steps:5`
→ exactly one downstream Integration call), filters = the fixed **128×128** PNG (`blur`), video =
the fixed **360p/1 s** clip. The two binary assets are `open()`-ed once at init and posted with
`http.file(...)`. AI payloads are seed-pinned. Payloads are intentionally *light* so a service can
sustain 100 rps within its 500m×3 CPU budget — i.e. we measure mesh overhead, not app queueing.

### Metrics and output
For each response `record()` adds the duration to a per-scenario `Trend` (`lat_<scenario>`) and
success to a `Rate` (`ok_<scenario>`), plus a `check` for status 200. `discardResponseBodies` keeps
the generator light. At the end, `handleSummary()` writes a compact JSON to `K6_SUMMARY_OUT`:
```json
{ "level": "...", "duration": "...", "scenarios": {
    "permutation_generate": { "rps_target", "reqs", "fail_rate",
      "lat_avg_ms","lat_p50_ms","lat_p90_ms","lat_p95_ms","lat_p99_ms","lat_max_ms" }, ... } }
```
This per-scenario summary is what `collect_metrics.py` reads for the latency rows.

### Environment variables
`BASE_URL` (required), `LEVEL` (low/med/high), `DURATION` (steady/warmup length), `INCLUDE_AI`
(true/false), `IMG_PATH`, `VID_PATH`, `K6_SUMMARY_OUT`. `run_phaseB.sh` sets all of these.

---

## `run_phaseB.sh` — the orchestrator (runs on the workstation)

Coordinates one full configuration end to end: syncs the load script to `lg`, holds a Prometheus
port-forward, and for each (level × rep) runs the warmup/steady/cooldown lifecycle, then collects
scalars and time-series. It does **not** switch the cluster — deploy the target mesh first.

### Options
| Flag | Meaning | Default |
|------|---------|---------|
| `-c LABEL` | config label written to the CSV `config` column (e.g. `linkerd_mtls`) | **required** |
| `-m MESH` | `baseline` \| `istio` \| `linkerd` (selects sidecar container name for metrics) | **required** |
| `-t MTLS` | mTLS state label: `on` \| `off` \| `na` | **required** |
| `-u URL` | `TARGET_URL` base | `http://<node>:30080` |
| `-n NODE_IP` | worker node IP for the default NodePort URL | `10.29.20.113` |
| `-l "LEVELS"` | space-separated load levels | `"low med high"` |
| `-r REPS` | repetitions per level | `10` |
| `-W WARMUP` | warm-up duration (discarded) | `30s` |
| `-S STEADY` | steady (measured) duration | `120s` |
| `-C COOLDOWN` | cooldown seconds between runs | `30` |
| `-I` | include the AI scenarios (opt-in trickle) | off |

### What it does, in order
1. **Preflight** — checks k6 on `lg`, the kube context reachable, and the ingress URL answers 200.
2. **Sync** — `scp`s `aggregate.js` + the two fixed assets to `lg:/root/thesis-tests/phaseB/`.
3. **Prometheus port-forward** — opens `svc/cluster-monitor-kube-prome-prometheus 9090:9090`
   in the background. `ensure_pf()` health-checks `/-/ready` and restarts it if it dies; a `trap`
   kills it on exit.
4. **Run loop** — for every `level` in `-l`, every `rep` 1..`-r`, calls `run_one`:
   - **Warm-up:** run `aggregate.js` for `-W` (30 s), output discarded — warms JIT, fills HTTP
     connection pools, lets sidecars reach steady CPU.
   - **Steady (measured):** record UTC `start`, run `aggregate.js` for `-S` (120 s) writing the
     per-scenario JSON, record UTC `end`. The k6 stdout log is saved to `results/k6_<run_id>.log`.
   - **Retrieve** the per-scenario summary JSON from `lg` → `results/k6_<run_id>.json`.
   - **Cooldown:** `sleep -C` (30 s), then `ensure_pf`.
   - **Collect scalars:** `collect_metrics.py` queries Prometheus for the `[start,end]` window
     (per-service app + sidecar + control-plane CPU/RAM) and merges the k6 latency → appends rows
     to `results/master.csv`.
   - **Extract curves (per-run!):** `extract_timeseries.py --run-id <id> --append` pulls the CPU/RAM
     time-series for this run into `results/timeseries_<config>.csv` **immediately**. This is
     per-run on purpose: Prometheus retention here is only **1 h on tmpfs**, so an end-of-campaign
     extraction would already have lost the first runs.
5. **Done** — prints the CSV paths. `run_id` format is `<config>_<level>_r<rep>`.

### Fixed environment (top of the script)
SSH key + opts, `LG_IP=10.29.20.130`, `LG_DIR=/root/thesis-tests/phaseB`,
`CTX=projekt-badawchy-cluster`, Prometheus service name, and `HERE` (the script's own dir, so it
resolves the Python helpers and `results/` regardless of cwd).

### Resilience notes
- Each k6 invocation is `|| true` so a transient failure doesn't abort the whole campaign; the
  affected run's rows are simply empty/partial.
- The Prometheus port-forward is auto-restarted between runs. A **VPN drop** still breaks in-flight
  runs (the SSH + port-forward ride the VPN) — keep the VPN/laptop stable for the ~1.6 h.
- `-m` selects the sidecar container name in `collect_metrics.py` (`istio-proxy` / `linkerd-proxy`
  / none), so it **must** match the deployed mesh or sidecar columns come out empty.

---

## Output

### `results/master.csv` (long format, one file for all configs)
Two `row_type`s per run, joined on `run_id`:
- `resource` — one per service + `_controlplane` + `_ingress`: `app_*` / `sidecar_*` CPU
  (millicores) and RAM (MiB), mean & p95/max over the steady window. Baseline has empty sidecar
  columns and no `_controlplane` row.
- `latency` — one per k6 scenario: `lat_p50/p90/p95/p99/avg/max_ms`, `reqs`, `fail_rate`.

Deltas vs `baseline` and the mTLS deltas are derived downstream.

### `results/timeseries_<config>.csv` — CPU/RAM behaviour over time
Long format `run_id,config,mesh,level,rep,t_rel_s,kind(cpu_cores|mem_mib),service,container,value`.
Written per-run during the campaign. To (re)generate/back-fill from recorded windows (within
Prometheus retention):
```bash
python3 extract_timeseries.py --master results/master.csv --config <label> \
  --out results/timeseries_<label>.csv --step 10 [--plot-run <run_id>]
```
Resolution is ~15 s (bounded by cadvisor's housekeeping — not improvable from Prometheus). For
finer **latency**-over-time (true 1 s) use `timeseries/capture_run.sh` on a single run.

### `results/ai_probe.csv` — AI / S2-ext chain latency
From the closed-loop probe (`ai_probe/run_ai_probe.sh`), per config + scenario.

---

## AI / S2-ext: use the closed-loop probe, not the aggregate
The AI service can't take open-loop rate-based load. Measure it separately:
```bash
./ai_probe/run_ai_probe.sh -c <label> -m <mesh> -t <mtls> -i 90 [-u ...]
```
1 VU, sequential — AI never sees more than one request at a time, so the VM cannot be overloaded.
Chain latency is dominated by ~1.4 s AI inference, so it does not discriminate strongly between
configs (see `make_ai_plot.py`).

## Plots
```bash
python3 make_plots.py --level high    # + low, med  → results/plots/<level>/
python3 make_ai_plot.py               # → results/plots/ai_probe_latency.png
```
Overall (CPU/RAM time-scale + latency histogram) and per-service (1×3 panel) comparisons.
Colors: baseline=green, linkerd=blue, istio=red (nomtls variants: orange/purple when present).

## Per-config workflow summary
```
make baseline|istio|linkerd (+ mTLS)  →  ./ai_probe/run_ai_probe.sh ...  →  ./run_phaseB.sh ...
```
Done: baseline · linkerd_mtls · istio_mtls. Remaining: istio_nomtls, linkerd_nomtls
(planned: Consul ±mTLS, Istio Ambient).

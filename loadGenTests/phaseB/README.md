# Phase B — Aggregate full-system benchmark

Drives **all services concurrently** — the six in-cluster services *and* the three AI scenarios —
at a per-level rate and records CPU, RAM and latency for each mesh configuration. See
`docs/test-scenario.typ` (Phase B) for the methodology. One `run_phaseB.sh` invocation covers one
configuration = 3 load levels × 10 repetitions = 30 runs (~1.6 h).

Configurations to cover: `baseline`, `linkerd_mtls`, `linkerd_nomtls` (proxy bypass),
`istio_mtls`, `istio_nomtls`. Switch the cluster deployment between them, then invoke once per config.

> **Status (Sept 2026): no valid Phase B data exists yet.** Everything collected in June
> (`baseline`, `linkerd_mtls`, `istio_mtls`) predates the VideoService resource change and the new
> load profile below, and must be discarded. The June `results/master.csv` was deleted on 22.09.2026, so the next run starts
> a fresh one.

---

## Files
| File | Runs on | Purpose |
|------|---------|---------|
| `aggregate.js` | lg (k6) | One k6 scenario per service, all concurrent; writes a per-scenario latency JSON. |
| `run_phaseB.sh` | workstation | Orchestrates one config: warmup→steady→cooldown × levels × reps; pulls Prometheus; writes CSVs. |
| `collect_metrics.py` | workstation | Queries Prometheus for per-service CPU/RAM over the steady window; merges k6 latency → `results/master.csv`. |
| `extract_timeseries.py` | workstation | Per run, pulls CPU/RAM **curves** (`query_range`) → `results/timeseries_<config>.csv`. |
| `ai_probe/` | workstation + lg | **Legacy.** Closed-loop (1 VU) probe built for the old CPU AI VM; superseded now that AI runs inside the aggregate. |
| `timeseries/` | workstation + lg | Single-run capture with true per-second latency (`capture_run.sh`). |
| `make_plots.py`, `make_ai_plot.py` | workstation | Comparison figures → `results/plots/`. |
| `../common/assets/` | — | Fixed work-unit inputs (`filter_input_128.png`, `sample_360p_1s.mp4`) + `make_assets.sh`, shared across phases. |

## Prerequisites
- **VPN connected** — the cluster, `lg`, Prometheus and the AI host are all reached through it.
- Workstation: `kubectl` (context `projekt-badawchy-cluster`), `python3` (+ matplotlib for plots),
  `ssh`/`scp`. SSH key for `root@lg` from `$SSH_PRIVATE_KEY` or the `SSH_PRIVATE_KEY=` line of the
  repo-root `.env` (override the file with `ENV_FILE=`).
- Load generator `lg` (10.29.20.130): `k6` installed. The script + assets are synced automatically.
- **AI host (10.29.20.121) up**, and the `ai-service` Service in `thesis-test` pointing at it —
  the preflight refuses to start otherwise.
- The target config must already be **deployed** with the matching `make` target from
  `deployments/` (see the setup table in `../phaseA/README.md`), and for Istio the gateway NodePort
  resolved for `-u`.

## Quick start
```bash
# Linkerd + mTLS (URL defaults to http://10.29.20.113:30080)
./run_phaseB.sh -c linkerd_mtls -m linkerd -t on

# Linkerd, proxy bypass (make linkerd-nomtls) — not an encryption-off variant, see ../phaseA/README.md
./run_phaseB.sh -c linkerd_nomtls -m linkerd -t off

# Baseline (no mesh)
./run_phaseB.sh -c baseline -m baseline -t na

# Istio — resolve the dynamic Envoy gateway NodePort for -u
GWPORT=$(kubectl --context projekt-badawchy-cluster -n istio-system get svc istio-ingressgateway \
  -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')
./run_phaseB.sh -c istio_mtls   -m istio -t on  -u http://10.29.20.113:$GWPORT   # make istio + STRICT
./run_phaseB.sh -c istio_nomtls -m istio -t off -u http://10.29.20.113:$GWPORT   # make istio-nomtls
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
always sustain the target rate; heavy `video_compress` and the AI scenarios get smaller pools. All
scenarios use a 1 s `timeUnit`.

### Per-level rates (`RATES`)
Rate is chosen by the `LEVEL` env (`low`/`med`/`high`):

| Scenario | Endpoint | Class | low / med / high |
|----------|----------|-------|------------------|
| `permutation_generate` | `POST /api/permutation/generate` | S1 STD | 25 / 50 / 100 rps |
| `fibonacci_calculate` | `POST /api/fibonacci/calculate` | S1 STD | 25 / 50 / 100 |
| `integration_calculate` | `POST /api/integration/calculate` | S1 STD | 25 / 50 / 100 |
| `filters_apply_image` | `POST /api/filters/apply-image` (multipart) | S1 STD | 25 / 50 / 100 |
| `differential_solve` | `POST /api/differential/solve` | S2-int | 25 / 50 / 100 |
| `video_compress` | `POST /api/video/compress` (multipart) | S1 HVY | 6 / 12 / 18 |
| `ai_generate` | `POST /api/Ai/generate` | S1 HVY | 1 / 2 / 3 |
| `permutation_from_ai` | `POST /api/permutation/generate-from-ai` | S2-ext | 1 / 2 / 3 |
| `filters_ai_matrix` | `POST /api/filters/apply-ai-matrix` | S2-ext | 1 / 2 / 3 |

- **STD, S2-int and video rates are identical to Phase A**, so every service carries the same load
  it had in isolation and the only new variable is contention.
- **The three AI scenarios are part of every run.** They share one GPU AI host that sustains about
  12–13 req/s in total, so each runs at 1/2/3 req/s — 3/6/9 req/s combined, below that ceiling even
  at high. (Phase A drives each AI scenario alone at 3/6/12.) `-X` / `INCLUDE_AI=false` drops them
  for debugging only; such a run is not a valid Phase B measurement.
- At high the cluster carries roughly 8–9 cores of application CPU (video alone ~6.5) out of the
  24 worker vCPUs, before sidecars. Validate each configuration with `-r 1 -l high` first.

### Fixed work units (reproducibility)
Every scenario uses one immutable payload so per-request work is constant across runs and configs:
permutation `[1..7]`, fibonacci `n=20000` (`-N`, the same as Phase A), integration `steps=20000`,
differential `x^2` (`steps:5` → exactly one downstream Integration call), filters = the fixed
**128×128** PNG (`blur`), video = the fixed **360p/1 s** clip. The two binary assets are `open()`-ed
once at init and posted with `http.file(...)`. AI payloads are seed-pinned. Work units match Phase A
one for one, so per-request cost is the same in both phases and results can be compared directly.

### Metrics and output
For each response `record()` adds the duration to a per-scenario `Trend` (`lat_<scenario>`) and
success to a `Rate` (`ok_<scenario>`), plus a `check` for status 200. `discardResponseBodies` keeps
the generator light. At the end, `handleSummary()` writes a compact JSON to `K6_SUMMARY_OUT`:
```json
{ "level": "...", "duration": "...", "include_ai": true, "fib_n": 20000, "scenarios": {
    "permutation_generate": { "rps_target", "reqs", "fail_rate",
      "lat_avg_ms","lat_p50_ms","lat_p90_ms","lat_p95_ms","lat_p99_ms","lat_max_ms" }, ... } }
```
This per-scenario summary is what `collect_metrics.py` reads for the latency rows.

### Environment variables
`BASE_URL` (required), `LEVEL` (low/med/high), `DURATION` (steady/warmup length), `INCLUDE_AI`
(default `true`), `FIB_N` (default `20000`), `IMG_PATH`, `VID_PATH`, `K6_SUMMARY_OUT`.
`run_phaseB.sh` sets all of these.

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
| `-N N` | Fibonacci work unit `n` (positive integer) | `20000` |
| `-X` | exclude the three AI scenarios — debugging only, **not** a valid Phase B run | AI included |

### What it does, in order
1. **Preflight** — checks k6 on `lg`, the kube context reachable, and the ingress URL answers 200.
   Unless `-X` is given, it also refuses to start if `ai-service` has no endpoints, and prints the
   AI health status through the ingress.
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

### `results/ai_probe.csv` — legacy
Output of the old closed-loop AI probe (June, CPU AI VM). Not produced by current runs.

---

## AI / S2-ext inside the aggregate
AI used to be measured separately with the closed-loop `ai_probe/`, because the old CPU AI VM
capped out at ~0.3 req/s. The GPU host sustains ~12–13 req/s, so the three AI scenarios now run
open-loop inside `aggregate.js` like every other scenario, and their latency rows land in
`master.csv` with the rest (`ai_generate` under service `ai-external`). `ai_probe/` is kept only
for reference.

## Plots
```bash
python3 make_plots.py --level high    # + low, med  → results/plots/<level>/
python3 make_ai_plot.py               # → results/plots/ai_probe_latency.png
```
Overall (CPU/RAM time-scale + latency histogram) and per-service (1×3 panel) comparisons.
Colors: baseline=green, linkerd=blue, istio=red (nomtls variants: orange/purple when present).

## Per-config workflow summary
```
cd deployments && make <target>   →   verify the setup   →   ./run_phaseB.sh -r 1 -l high ...   →   ./run_phaseB.sh ...
```
Done: none (all June data void). Remaining: baseline, linkerd_mtls, linkerd_nomtls, istio_mtls,
istio_nomtls (planned: Consul ±mTLS, Istio Ambient).

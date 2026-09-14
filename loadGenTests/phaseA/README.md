# Phase A — per-endpoint isolation benchmark

Drives **one scenario at a time** against whatever configuration is currently deployed and records
CPU, RAM and latency for it. Isolating a single endpoint attributes mesh overhead to a specific
workload type, which is the core of the study; Phase B (`../phaseB/`) measures all services under
contention instead. The methodology is in `docs/test-scenario.typ` (§3–§9).

One invocation of `run_phaseA_Core.sh` = one scenario × the chosen load levels × repetitions.
With the defaults (3 levels × 10 reps) that is 30 runs, about **1.75 h**.

---

## Files

| File | Runs on | Purpose |
|------|---------|---------|
| `run_phaseA_Core.sh` | workstation | The orchestrator. Validates flags, runs preflight checks, drives k6 on the load generator, pulls Prometheus metrics, writes CSVs. |
| `phaseA_Data.sh` | workstation (sourced) | Per-scenario settings: k6 script, assets, default rates, result label, smoke request. Never run on its own. |
| `<Service>/<name>-test.js` | lg (k6) | One k6 script per scenario. |
| `<Service>/results/` | — | Output of every run (see [Output](#output)). |
| `<Service>/run_phaseA_S1.sh` | workstation | **Legacy**, baseline-only per-service scripts. Superseded by the Core; kept only because the banked baseline S1 data was produced with them. |
| `../common/collect_metrics.py` | workstation | Queries Prometheus for the steady window and merges k6 latency into the master CSV. |
| `../common/extract_timeseries.py` | workstation | Pulls the CPU/RAM curves of one run into the time-series CSV. |
| `../common/assets/` | — | Fixed binary work units (`filter_input_128.png`, `sample_360p_1s.mp4`). |

---

## Prerequisites

- **VPN connected.** The cluster, the load generator and Prometheus are all reached through it.
- **kubectl context `projekt-badawchy-cluster`** configured on the workstation (see `docs/SETUP_GUIDE.md` §7).
- **SSH key** for `root` on the load generator, given either as
  - the environment variable `SSH_PRIVATE_KEY=/path/to/key`, or
  - a line `SSH_PRIVATE_KEY=/path/to/key` in the repo-root `.env` (use `ENV_FILE=/other/.env` to point elsewhere).

  Windows paths (`C:\...`) are converted for WSL automatically, and the key is copied to a temp file
  with `chmod 600`, so a key on a `/mnt/c` mount works. The temp copy is removed on exit.
- **Locally:** `bash`, `python3`, `curl`, `ssh`, `scp`.
- **Load generator `lg` (10.29.20.130):** `k6` installed. Scripts and assets are synced automatically.
- **The target configuration is already deployed** (`make baseline|istio|linkerd`, plus the mTLS
  state you intend to measure). The Core does not deploy or switch anything.

---

## Quick start

```bash
cd loadGenTests/phaseA

# Validate first: one repetition at the highest level, then check fail_rate in the output.
./run_phaseA_Core.sh -s fibonacci -r 1 -l high

# Full campaign for one scenario on baseline
./run_phaseA_Core.sh -s fibonacci

# Linkerd with mTLS
./run_phaseA_Core.sh -s video -m linkerd -t on

# Istio — the gateway NodePort changes on every install, so resolve it and pass -u
GWPORT=$(kubectl --context projekt-badawchy-cluster -n istio-system get svc istio-ingressgateway \
  -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')
./run_phaseA_Core.sh -s integration -m istio -t on -u http://10.29.20.113:$GWPORT
```

---

## Scenarios (`-s`)

| `-s` key | Endpoint | Type | k6 script | Work unit | Rates low / med / high (req/s) | `-R` |
|----------|----------|------|-----------|-----------|-------------------------------|------|
| `permutation` | `POST /api/permutation/generate` | S1 | `PermutationService/permutation-test.js` | set `[1..7]` (5040 permutations) | 25 / 50 / 100 | — |
| `fibonacci` | `POST /api/fibonacci/calculate` | S1 | `FibonacciService/fibonacci-test.js` | `n` from `-N` (default 20000) | 25 / 50 / 100 | — |
| `integration` | `POST /api/integration/calculate` | S1 | `IntegrationService/integration-test.js` | `x^2` on [0,1], 20000 steps | 25 / 50 / 100 | — |
| `digital` | `POST /api/filters/apply-image` | S1 | `DigitalFiltersService/filters-test.js` | fixed 128×128 PNG, `blur` | 25 / 50 / 100 | — |
| `video` | `POST /api/video/compress` | S1 | `VideoService/video-test.js` | fixed 360p / 1 s MP4 | 6 / 12 / 18 | yes |
| `ai` | `POST /api/Ai/generate` | S1 | `AiService/ai-test.js` | seeded prompt: 10 numbers, seed 42 | 3 / 6 / 12 | yes |
| `permutation_ai` | `POST /api/permutation/generate-from-ai` | S2-ext | `PermutationService/permutation-ai-test.js` | AI returns a 7-element set (seed 42), then permuted | 3 / 6 / 12 | yes |
| `digital_ai` | `POST /api/filters/apply-ai-matrix` | S2-ext | `DigitalFiltersService/filters-ai-test.js` | AI returns a 3×3 matrix, `blur` applied | 3 / 6 / 12 | yes |
| `differential` | `POST /api/differential/solve` | S2-int | `DifferentialEquationsService/differential-test.js` | `x^2`, `initialConditionY` 1, `steps` 5 → exactly one call to integration | 25 / 50 / 100 | yes |

**S2-int** is the in-cluster chain differential → integration. Both services are meshed and the call
goes to `http://integration-service/` directly, not back through the ingress, so under a mesh **both
hops carry mTLS**: this is the study's sidecar-to-sidecar encryption benchmark, and the cleanest mTLS
cost is its Istio `on` vs `off` delta. A function without `y` makes exactly one downstream call, so at
R req/s the integration service receives R req/s as well; its CPU/RAM rows belong to the scenario.

**S1** is a single hop: ingress → one service. **S2-ext** is a chain from a meshed service to the
external AI host (10.29.20.121). Only the ingress→service hop is inside the mesh; the service→AI
leg is plaintext in every configuration, because the AI host has no sidecar. S2-ext therefore
measures sidecar *egress* cost, not east–west encryption cost.

**AI scenarios reach the host through the cluster**, never directly: ingress → `Service ai-service`
→ its manually defined Endpoints (`deployments/k8s/ai-service/ai-service-external.yaml`). The AI host
sustains roughly **12–13 req/s** in total (measured with `../ai_capacity/run_ai_capacity.sh`), so
the 3/6/12 defaults are close to its ceiling at `high`. **Never run two AI-using scenarios at the same
time** — their rates add up on the same host.

Not yet available: `differential/solve` as S2-amp (a `y` function, fan-out N = 5/10/20), and the
idle-overhead capture.

---

## Arguments

Every flag is optional except `-s`. The flags that decide *what the data means* — `-s`, `-m`, `-t`,
`-c`, `-N`, `-R`, and `-u` for Istio — are validated before anything touches the cluster or the load
generator, so a typo fails immediately instead of producing mislabelled data. `-l`, `-r`, `-W`, `-S`,
`-C` and `-n` are passed through as given: a bad value there shows up as failed or missing runs,
not as an early error, so double-check them.

### What to run

#### `-s SERVICE` — scenario key *(required)*
One of the keys in the [Scenarios](#scenarios--s) table. An unknown key fails with the list of
valid ones.

#### `-l "LEVELS"` — load levels
Space-separated, in the order they run. Default `"low med high"`.
Names must be exactly `low`, `med` or `high`; they select the per-level rate inside the k6 script,
and an unknown name makes k6 fail for every run of that level.

```bash
-l high            # only the high level
-l "low high"      # skip med
```

#### `-r REPS` — repetitions per level
Positive integer. Default `10`. Runs are ordered level by level: all repetitions of the first
level, then all of the next. A non-number is not rejected — the loop simply runs nothing and the
script still prints `DONE`.

#### `-N N` — Fibonacci work-unit size
Positive integer. Default `20000`. Only affects `-s fibonacci`; accepted and ignored for the others.
The computation is O(n²), so `n` sets per-request CPU cost. 20000 was calibrated to sustain 100 req/s
within the pods' 1.5-core budget; `n ≥ 30000` saturates the CPU limit and masks mesh overhead. The
value is expanded on the workstation and sent to k6 as a literal.

```bash
./run_phaseA_Core.sh -s fibonacci -N 30000 -r 1 -l high    # calibration run at another size
```

#### `-R "LOW MED HIGH"` — per-level request rates
Exactly three positive integers, in req/s, quoted as one argument. Only for scenarios whose rates
are configurable (`video`, `differential`, `ai`, `permutation_ai`, `digital_ai`); rejected for the others, whose
rates are fixed in their k6 script. Without `-R` the defaults from the table above apply.

```bash
./run_phaseA_Core.sh -s digital_ai -R "2 4 8"
```

Rates must be integers because k6's `constant-arrival-rate` executor accepts no fractional rate.
**Changing rates changes the experiment** — every configuration of a comparison must use the same
values.

### How rows are labelled

The Core never detects the configuration on its own. These three flags **label** the rows it writes;
they must describe what is actually deployed.

#### `-m MESH` — deployed mesh
`baseline`, `istio` or `linkerd`. Default `baseline`.

Besides labelling, it selects the sidecar container whose CPU/RAM is collected (`istio-proxy`,
`linkerd-proxy`, none for baseline) and the control-plane namespace. A preflight check compares it
with the sidecars actually present in `thesis-test` and **refuses to start on a mismatch** — for
example `-m baseline` while pods carry `linkerd-proxy`.

#### `-t MTLS` — mTLS state
- `-m baseline`: must be `na`, or omitted (it defaults to `na`).
- `-m istio` / `-m linkerd`: required, `on` or `off`.

The flag is a label: it does not switch mTLS. Set the state first — Istio `PeerAuthentication`
`STRICT` or `DISABLE`; for Linkerd, `off` means the proxy-bypass deployment, see
`docs/test-scenario.typ` §2 — and verify it before running.

#### `-c LABEL` — configuration label
Letters, digits, `_` and `-`. Defaults to the same labels Phase B uses:

| `-m` | `-t` | default label |
|------|------|---------------|
| `baseline` | `na` | `baseline` |
| `istio` / `linkerd` | `on` | `<mesh>_mtls` |
| `istio` / `linkerd` | `off` | `<mesh>_nomtls` |

Pass `-c` only when the defaults cannot distinguish two configurations, e.g. `-c linkerd_bypass`.

From the label the Core builds **`CONFIG`**, the run label written to the `config` column, to every
`run_id` and to the time-series filename:

```
CONFIG = <label>_<service slug>_<S1|S2ext>
run_id = <CONFIG>_<level>_r<rep>

baseline_fibonacci_S1                 # -s fibonacci
linkerd_mtls_video_S1                 # -s video -m linkerd -t on
istio_nomtls_permutation_S2ext        # -s permutation_ai -m istio -t off -u ...
istio_mtls_differential_S2int         # -s differential -m istio -t on -u ...
baseline_fibonacci_S1_high_r3         # one run
```

### Where to send load

#### `-u URL` — ingress base URL
Full base URL, without a trailing path, e.g. `http://10.29.20.113:31245`. Overrides `-n`.
**Required with `-m istio`**: the Istio ingress gateway's NodePort is dynamic and changes on every
`make istio`, so re-resolve it each time (command in [Quick start](#quick-start)).

#### `-n NODE_IP` — worker node
Used only to build the default URL `http://<NODE_IP>:30080` (the NGINX ingress NodePort for baseline
and Linkerd). Default `10.29.20.113`; any worker node works.

### Timing of each run

#### `-W WARMUP` — warm-up duration
k6 duration string. Default `30s`. Drives the target rate with all data discarded, so JIT, connection
pools and sidecars reach steady state before measuring.

#### `-S STEADY` — measured duration
k6 duration string. Default `120s`. The only window used for analysis: its UTC start/end are recorded
and scope every Prometheus query. `60s` is the protocol's "express" setting; like rates, it must
be the same across every configuration being compared.

#### `-C SECONDS` — cooldown
Integer seconds. Default `30`. Idle time after each measured window, before metrics are collected.

---

## What one invocation does

1. **Validates flags** and builds `CONFIG`, the rates and the CSV path. Prints a banner with all of them.
2. **Preflight:**
   - `k6` present on `lg`;
   - kube context reachable;
   - deployed sidecars match `-m`;
   - for AI scenarios: prints the IP behind `ai-service` and fails if it has no endpoints;
   - one smoke request to the target endpoint (printed; a non-200 does not stop the run).
3. **Syncs** the k6 script, plus its asset if any, to `lg:/root/thesis-tests/phaseA/`.
4. **Opens a Prometheus port-forward** to `svc/cluster-monitor-kube-prome-prometheus`; it is
   health-checked and restarted between runs if it dies.
5. **For every level, for every repetition:**
   1. warm-up (discarded);
   2. steady window, recording UTC start and end; k6 stdout goes to `k6_<run_id>.log`;
   3. fetch the per-scenario k6 summary to `k6_<run_id>.json`;
   4. cooldown;
   5. `collect_metrics.py` appends this run's rows to the master CSV;
   6. `extract_timeseries.py` appends this run's CPU/RAM curves **immediately** — Prometheus keeps
      only 1 h of data on tmpfs, so extracting at the end of a 1.75 h campaign would lose the first runs.
6. **Exits**, killing the port-forward and deleting the temp SSH key (also on Ctrl+C or error).

A failing k6 run does not stop the campaign: that run's rows come out empty or partial, and the loop
continues. Check the output before moving to the next configuration.

---

## Output

Everything lands in `<ServiceDir>/results/`.

| File | Content |
|------|---------|
| `master.csv` | S1 rows (every configuration of that service's S1 scenario). |
| `master_S2int.csv` | S2-int rows (`DifferentialEquationsService`). |
| `master_S2ext.csv` | S2-ext rows, so a service's two scenarios never share a CSV. |
| `timeseries_<CONFIG>.csv` | CPU/RAM curves of every run of one configuration. |
| `k6_<run_id>.json` | Per-scenario k6 summary of one run. |
| `k6_<run_id>.log` | k6 stdout of one run. |

### Master CSV (long format)

Every run appends two kinds of rows, joined on `run_id`:

- **`row_type=resource`** — one row per in-cluster service, plus `_controlplane` (meshes only) and
  `_ingress`. Columns `app_cpu_milli_mean/p95`, `app_mem_mib_mean/max`, and the same for `sidecar_*`
  (empty on baseline). All services are recorded on every run, not only the one under test, so
  spill-over onto neighbours is visible.

  `_ingress` is always the **NGINX** ingress controller. Under Istio traffic enters through the
  Envoy ingress gateway instead, which lives in `istio-system` and is therefore counted inside
  `_controlplane`; the `_ingress` row is then near idle. Split the gateway out before comparing
  ingress cost between Istio and the other configurations.
- **`row_type=latency`** — one row per k6 scenario: `rps_target`, `reqs`, `fail_rate`,
  `lat_avg/p50/p90/p95/p99/max_ms`.

Identity columns on both: `run_id, config, mesh, mtls, level, rep, steady_start_utc, steady_end_utc,
service, scenario`.

`ai_generate` additionally reports `wrong_answer_rate` in its k6 JSON — a 200 whose numbers differ
from the known seeded answer. It is not written to the master CSV.

### Time-series CSV

`run_id, config, mesh, level, rep, t_rel_s, kind (cpu_cores|mem_mib), service, container, value`.
Resolution is ~15 s, bounded by cAdvisor's housekeeping interval, not by the query step.

---

## Running a whole configuration

Deploy once, verify the mTLS state, then run every scenario back to back. Scenarios run
sequentially, so AI scenarios never overlap:

```bash
cd loadGenTests/phaseA
for s in permutation fibonacci integration digital video differential ai permutation_ai digital_ai; do
  ./run_phaseA_Core.sh -s "$s" -m linkerd -t on
done
```

For Istio, resolve `GWPORT` once after `make istio` and add `-u http://10.29.20.113:$GWPORT` to the
loop. With the defaults this is about 16 h for nine scenarios, so run it from a stable machine —
a VPN drop breaks the SSH sessions and the port-forward mid-run.

---

## Troubleshooting

| Symptom | Cause and fix |
|---------|---------------|
| `ERROR: -m baseline, but thesis-test pods carry a mesh sidecar` | A mesh is still deployed. Pass the real `-m/-t`, or finish the teardown. |
| `ERROR: -m istio requires -u` | Resolve the gateway NodePort (see Quick start) and pass `-u`. |
| `ERROR: -R is not supported for -s …` | That scenario's rates are fixed in its k6 script. |
| `ERROR: SSH key not found` | Set `SSH_PRIVATE_KEY` or add it to the repo-root `.env`. |
| `k6 missing on lg` / SSH hangs | VPN down, or `k6` not installed on the load generator. |
| `kube context unreachable` | VPN down, or context `projekt-badawchy-cluster` not configured. |
| `service thesis-test/ai-service has no endpoints` | `kubectl apply -f deployments/k8s/ai-service/ai-service-external.yaml`. |
| Preflight smoke shows `http=000` or `502/503` | Target endpoint unhealthy; the campaign would produce failed runs. Stop and fix before running. |
| Empty sidecar columns under a mesh | Sidecar not injected into the pods, or wrong `-m`. |
| `[prom] port-forward down, restarting…` repeating | Prometheus pod restarting, which also wipes its tmpfs data — check `kubectl -n monitoring get pods`. |
| Duplicate `run_id`s in a master CSV | The same configuration was run twice; rows are always appended. Move the old CSV aside before re-running a configuration, or deduplicate by `run_id`. |

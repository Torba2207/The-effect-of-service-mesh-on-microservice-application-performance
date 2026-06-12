# Phase B — Aggregate full-system benchmark

Drives **all services concurrently** at a per-level rate and records CPU, RAM and
latency for each of the 5 configurations. See `thesis-metrics/test-scenario.typ`
(§8 Phase B) for the methodology. This is the *shortest* phase: 5 configs × 3
levels × 10 reps = 150 runs.

## Files
| File | Runs on | Purpose |
|------|---------|---------|
| `aggregate.js` | lg (k6) | One k6 scenario per service, concurrent; writes per-scenario latency JSON. |
| `run_phaseB.sh` | workstation | Orchestrates one config: warmup→steady→cooldown × levels × reps; pulls Prometheus; writes CSV. |
| `collect_metrics.py` | workstation | Queries Prometheus for per-service CPU/RAM over the steady window; merges k6 latency → `results/master.csv`. |
| `assets/` | — | Fixed work-unit inputs (`filter_input_512.png`, `sample_720p_10s.mp4`) + `make_assets.sh`. |

## Prerequisites
- Workstation: `kubectl` (context `projekt-badawchy-cluster`), `python3`, `ssh`/`scp`, the SSH key.
- Load generator `lg` (10.29.20.130): `k6` installed. Assets + script are synced automatically.
- The target config must already be **deployed** (`make baseline|istio|linkerd` + mTLS state set).

## Run one configuration
```bash
# Linkerd, mTLS on (current cluster state)
./run_phaseB.sh -c linkerd_mtls -m linkerd -t on

# Baseline (no mesh)
./run_phaseB.sh -c baseline -m baseline -t na

# Istio without mTLS — resolve the gateway NodePort for -u
GWPORT=$(kubectl --context projekt-badawchy-cluster -n istio-system get svc istio-ingressgateway \
  -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')
./run_phaseB.sh -c istio_nomtls -m istio -t off -u http://10.29.20.113:$GWPORT
```

The 5 configurations to cover: `baseline`, `istio_mtls`, `istio_nomtls`,
`linkerd_mtls`, `linkerd_nomtls`. Switch the deployment between runs, then invoke
once per config.

### Useful flags
- `-S 60s` shorter steady window (faster; ~halves wall-clock).
- `-r 3` fewer reps for a quick pass.
- `-l low` single level.
- `-I` opt-in the AI scenarios (default OFF — see note).

## Output: `results/master.csv` (long format)
Two `row_type`s per run:
- `resource` — one per service + `_controlplane` + `_ingress`: `app_*`/`sidecar_*`
  CPU (millicores) and RAM (MiB), mean & p95/max over the steady window.
- `latency` — one per k6 scenario: `lat_p50/p90/p95/p99/avg/max_ms`, `reqs`, `fail_rate`.

Join on `run_id`. Deltas vs `baseline` and the mTLS deltas are computed downstream.

## Payloads (Phase B) and the AI exception
Phase B uses **light** work units so each request is ~5-15 ms and a service can sustain
100 req/s within its 500m×3 CPU budget (validated: at HIGH, fail=0, p95 single-digit ms):
permutation `[1..7]`, fibonacci `n=3000`, integration `steps=20000`, filters
`128×128` blur, differential `x^2`, video = a 360p/1s clip. (Phase A will use the heavier
work units from `test-scenario.typ` §4.)

**AI is OFF by default.** The AI service does CPU LLM inference at ~6-7 s/request with only
2 backends → a hard ceiling of ~0.3 req/s. It cannot take a rate-based load (requests pile
up and the VM melts — load avg hit 48 during testing). `-I` enables it as an opt-in trickle
(0.1 req/s per AI scenario via a 10 s timeUnit); expect only a handful of samples per run.
For real AI numbers, measure it separately at very low concurrency (Phase A).

## Notes / caveats
- **Validate first:** before a full campaign, run `-r 1 -l high` per config and check
  `fail_rate < 0.01` in the latency rows.
- **Latency is end-to-end (k6 client-side)** — the only source comparable across all 5
  configs. Mesh telemetry (Istio/Linkerd histograms) needs the PodMonitors from
  `test-scenario.typ` §9.3 and is optional.
- The Prometheus port-forward is auto-started and health-checked between runs.

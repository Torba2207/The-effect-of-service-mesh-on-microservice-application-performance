#set page(
  paper: "a4",
  margin: (x: 2cm, y: 2cm),
  numbering: "1",
)
#set text(font: "Linux Libertine", size: 11pt)
#set heading(numbering: "1.")
#set par(justify: true)
#show raw.where(block: true): it => block(
  fill: rgb("#f5f5f5"),
  inset: 8pt,
  radius: 4pt,
  width: 100%,
  it,
)

#let note(body) = block(
  fill: rgb("#fff8e1"),
  stroke: 0.5pt + rgb("#e0c060"),
  radius: 4pt,
  inset: 9pt,
  width: 100%,
)[*Note.* #body]

#let warn(body) = block(
  fill: rgb("#fdecea"),
  stroke: 0.5pt + rgb("#e0a0a0"),
  radius: 4pt,
  inset: 9pt,
  width: 100%,
)[*Caveat.* #body]

#align(center)[
  #text(size: 20pt, weight: "bold")[Service Mesh Performance Benchmark] \
  #v(0.4em)
  #text(size: 14pt)[Detailed Test Scenarios — Baseline vs. Istio vs. Linkerd] \
  #v(0.3em)
  #text(size: 11pt, style: "italic")[CPU · RAM · Latency overhead under controlled load]
  #v(1.5em)
]

#outline(indent: auto, depth: 2)
#pagebreak()

= Objectives and Research Questions

This document defines a repeatable measurement protocol for quantifying the runtime
overhead introduced by service-mesh data planes on a .NET 8 microservice application.
The application, cluster topology, and mesh-switching automation are described in the
repository (`README.md`, `architecture/`, `deployments/`). This document only defines
*how the application is exercised and how data is collected*.

We measure three primary metrics:

- *CPU usage* — millicores consumed, split between the application container, the
  sidecar proxy, and the mesh control plane.
- *RAM usage* — working-set bytes, split the same way.
- *Latency* — end-to-end request latency observed at the load generator, reported as a
  distribution (p50/p90/p95/p99/max).

The experiment answers four research questions:

+ *RQ1 — Steady-state overhead:* How much additional CPU/RAM does each mesh consume per
  request, per service, relative to the no-mesh baseline?
+ *RQ2 — Latency tax:* What latency percentile increase does each mesh add, and how does
  it scale with load (low → medium → high)?
+ *RQ3 — Cost of mTLS:* What is the marginal cost of mutual-TLS encryption, isolated by
  comparing each mesh with and without mTLS?
+ *RQ4 — Workload sensitivity:* Do CPU-bound, memory-bound, and I/O-bound services
  experience different mesh overhead profiles?

= Experimental Configurations

Five configurations ("setups") are compared. Each is deployed via the Ansible/Make
workflow (`deployments/Makefile`) and measured independently.

#figure(
  table(
    columns: (auto, auto, auto, 1fr),
    fill: (x, y) => if y == 0 { luma(230) } else { none },
    inset: 8pt,
    align: (center + horizon, center + horizon, center + horizon, left + horizon),
    [*ID*], [*Mesh*], [*mTLS*], [*Description / how it is enforced*],
    [B],  [None],    [n/a],  [Baseline. Pods run with no injected proxy. Traffic enters via the application `NodePort` Service. Reference point for all deltas.],
    [I-S],[Istio],   [STRICT],[Envoy sidecar injected. A namespace-wide `PeerAuthentication` with `mtls.mode: STRICT` forces mTLS on all in-mesh traffic.],
    [I-P],[Istio],   [OFF],  [Envoy sidecar injected, identical to I-S, but `PeerAuthentication` set to `mtls.mode: DISABLE`. Proxy stays in the data path; only encryption is removed. Isolates the cost of mTLS.],
    [L-S],[Linkerd], [on],   [Linkerd micro-proxy injected (`linkerd.io/inject: enabled`). mTLS is automatic for all meshed TCP traffic (default, cannot be selectively disabled per connection).],
    [L-P],[Linkerd], [off#super[\*]], [Linkerd injected, but application ports are excluded from proxy interception via `config.linkerd.io/skip-inbound-ports` / `skip-outbound-ports`. See caveat below.],
  ),
  caption: [The five measured configurations.],
)

#warn[
  *Istio* gives a clean mTLS on/off contrast: with `PeerAuthentication` STRICT vs.
  DISABLE the Envoy proxy remains in the request path both times, so the *only*
  variable is encryption. This is a true measurement of the mTLS tax.

  *Linkerd* does not support disabling mTLS on meshed traffic — encryption is an
  intrinsic, always-on property of its data plane. There is therefore no way to keep
  the Linkerd proxy in the path *and* turn off encryption. The L-P configuration
  approximates "Linkerd without mTLS" by using `skip-inbound-ports`/`skip-outbound-ports`
  to bypass the proxy for the application's ports. Consequently *L-P measures
  proxy-bypass, not encryption-only*: its delta versus L-S conflates "no proxy" with
  "no mTLS". Report L-P as such and do not claim it isolates encryption cost for
  Linkerd. (For Linkerd, the meaningful encryption-cost comparison is L-S vs. baseline B.)
]

#note[
  Linkerd's mTLS state must be *verified*, not assumed, for both L-S and L-P:
  `linkerd viz edges deployment -n thesis-test` shows a green check (✓) in the `SECURED`
  column for mTLS connections. L-S must show secured edges; L-P's skipped ports must
  show plaintext.
]

= Services Under Test and Fixed Workloads

All seven backend services are exercised. Each service exposes several endpoints; they are
*all* listed below for completeness. Benchmarked endpoints are marked in the *Bench* column
with a *scenario type*:

#block(inset: (left: 6pt))[
  - *✓ S1 — single-hop (north–south):* ingress → one meshed service → response. Isolates the
    cost of a single sidecar on the request path.
  - *✓ S2 — chained / heterogeneous (multi-hop):* ingress → meshed service → a *second*
    service, then response. Exercises the sidecar *egress* path and multi-hop latency — this
    is where a mesh's cost concentrates. Two sub-types exist, and they differ crucially for
    mTLS (§3.1):
    - *S2-int (in-cluster, meshed→meshed):* `differential/solve` calls the meshed
      Integration service. *Both* hops carry mTLS — this is the true sidecar-to-sidecar
      encryption path.
    - *S2-ext (egress to an unmeshed service):* `permutation/generate-from-ai` and
      `filters/apply-ai-matrix` call the *external* AI VM. Only the ingress→service hop is
      in-mesh; the egress leg is plaintext.
]

Driving the per-request work identically across every configuration requires that each
benchmarked endpoint always use a single fixed request payload (a "work unit"); load is
varied only by changing the request rate (§5). Payloads are sized so that the service stays
*below saturation at baseline* — required so that we measure mesh overhead and not
application queueing. Each payload must be validated to keep the baseline error rate below
1% at the High load level before measurement runs begin. The call graph and an important
mTLS caveat for S2 are given in §3.1.

#let ep-table(..rows) = table(
  columns: (auto, auto, 1.6fr, 1fr, auto),
  fill: (x, y) => if y == 0 { luma(235) } else { none },
  inset: 6pt,
  align: (center + horizon, center + horizon, left + horizon, left + horizon, center + horizon),
  [*Verb*], [*Class*], [*Path*], [*Purpose*], [*Bench*],
  ..rows.pos()
)

All paths share the prefix shown in each heading; the health endpoints live at the service
root (`/health`), not under the API prefix. Routes are reached through the active ingress
for the configuration under test (§6).

== Call Graph and the S2 mTLS Caveat <call-graph>

Four benchmarked scenarios make a downstream call (across three distinct endpoints —
`differential/solve` is benched twice). They fall into sub-types that behave very differently
under mTLS:

```text
S2-int  ingress ─▶ differential-service ─▶ integration-service        (solve, x^2  → 1 call)
S2-amp  ingress ─▶ differential-service ─▶ integration-service ×N     (solve, y-fn → N calls)
S2-ext  ingress ─▶ permutation-service  ─▶ AI service (external VM)   (generate-from-ai)
S2-ext  ingress ─▶ digital-filters       ─▶ AI service (external VM)   (apply-ai-matrix)
```

*S2-int / S2-amp — Differential → Integration (in-cluster, meshed→meshed).* Confirmed in code:
`DifferentialCalculator` always invokes `IntegrationServiceClient`, whose base address is
`http://integration-service/` (the in-cluster ClusterIP, *not* the gateway). Both pods are
sidecar-injected, so *every* differential→integration hop carries mTLS — the genuine
sidecar-to-sidecar encryption path. The number of downstream calls is set by the request:

#note[
  *S2-int (single hop):* a function *without* `y` (e.g. `x^2`) triggers *exactly one*
  downstream `antiderivative` call. Fan-out is a constant *1*, so per-request work is fixed
  and directly comparable to the other scenarios.

  *S2-amp (amplified fan-out):* a function *containing* `y` makes the solver loop and issue
  *one downstream call per step* — `N = Steps` sequential meshed→meshed calls per single
  ingress request. This multiplies the east-west sidecar traversals per request and is the
  sharpest probe of cumulative mesh overhead. For S2-amp the load knob is the *fan-out N*
  itself (swept 5 / 10 / 20, §5) at a fixed low ingress rate, so the experiment isolates how
  overhead scales with the number of encrypted hops. The accumulating integrand grows per
  step, so each N must be validated to keep the baseline error below 1% (reduce N if the
  symbolic expression starts to fail).
]

*S2-ext — Permutation / Filters → AI (egress to an unmeshed service).* The AI service runs
on a *dedicated VM outside the cluster* and is *not meshed* (reached via the external Service
in `ai-service-external.yaml`).

#warn[
  *For S2-ext, mTLS covers only the ingress→service hop.* Because the AI service has no
  proxy, the service→AI egress leg is plaintext in every configuration; the mTLS variable
  (STRICT vs. DISABLE) does not touch it. S2-ext is the right scenario for "heterogeneous
  chaining / sidecar egress overhead", but it does *not* isolate east-west encryption cost —
  use *S2-int* / *S2-amp* (Differential→Integration) for that.

  Separately, `VideoService` registers a `DigitalFiltersClient` in DI that no controller ever
  invokes (dead code), so Video→Filters does *not* fire and is not benchmarked. A
  meshed→meshed path is already covered by S2-int/S2-amp, so wiring it up is optional.
]

*Rate ceilings (§5).* S2-int keeps STD rates (25/50/100) — its single downstream call is fast.
S2-amp holds a *fixed low ingress rate* and varies N instead, sized so the amplified
downstream load (`rate × N`) stays well under Integration's baseline. The two S2-ext endpoints
are gated by AI inference latency and inherit the AI service's *CHN* ceiling (1/2/5).

== Permutation Service — `api/permutation` (port 5001, class STD)
#ep-table(
  [POST], [STD], [`/api/permutation/generate`], [All permutations of a set — $O(n!)$ CPU.], [✓ S1],
  [POST], [CHN], [`/api/permutation/generate-from-ai`], [Fetches a set from the AI service, then permutes it (chained, heterogeneous → external AI).], [✓ S2-ext],
  [GET],  [—], [`/health`], [Liveness probe.], [],
)
*S1 work unit* (`generate`) — 5040 permutations:
```json
{ "set": [1, 2, 3, 4, 5, 6, 7] }
```
*S2 work unit* (`generate-from-ai`) — AI returns the set (seed-pinned), then it is permuted:
```json
{ "count": 7, "minVal": 1, "maxVal": 10, "seed": 42 }
```

== Fibonacci Service — `api/fibonacci` (port 5002, class STD)
#ep-table(
  [POST], [STD], [`/api/fibonacci/calculate`], [n-th Fibonacci number with `BigInteger` arithmetic.], [✓ S1],
  [GET],  [—], [`/health`], [Liveness probe.], [],
)
*Work unit* (`calculate`) — the optimal, representative size is *`n = 20000`*:
```json
{ "n": 20000 }
```
The iterative `BigInteger` computation is #box[$O(n^2)$] (the operands grow to #box[$approx 0.69 n$] bits),
so `n` sets the per-request CPU cost. `n = 20000` was calibrated against the pods'
CPU ceiling (500m × 3 replicas = 1.5 cores): it sustains the full High rate (100 RPS) at
#box[$approx 10$] ms/request with #box[$approx 50%$] headroom and a 0% error rate, yielding a clean,
monotonic CPU-vs-load curve (measured baseline: #box[$approx 231 -> 424 -> 750$] m across Low/Med/High).
Larger sizes overshoot: #box[$n gt.eq 30000$] hits the CPU limit and throttles at 100 RPS
(latency jumps to #box[$approx 1.1$] s and the offered rate can no longer be met), which would
mask the mesh overhead the study targets.

== Integration Service — `api/integration` (port 5004, class STD)
#ep-table(
  [POST], [STD], [`/api/integration/calculate`], [Numerical definite integral over a step grid.], [✓ S1],
  [POST], [—], [`/api/integration/antiderivative`], [Symbolic antiderivative of an expression.], [],
  [GET],  [—], [`/health`], [Liveness probe.], [],
)
*Work unit* (`calculate`) — one million sub-intervals:
```json
{ "function": "x^2", "lowerBound": 0, "upperBound": 1, "steps": 1000000 }
```

== Differential Equations Service — `api/differential` (port 5003, class STD)
#ep-table(
  [POST], [STD], [`/api/differential/solve`], [Numerical ODE solver. *Always chains* to the in-cluster Integration service (meshed→meshed) — see §3.1. Benched twice.], [✓ S2-int / S2-amp],
  [GET],  [—], [`/health`], [Liveness probe.], [],
)
This is the project's *sidecar-to-sidecar mTLS* benchmark: both the ingress→differential and
differential→integration hops are encrypted under I-S / L-S. Two work units share the
endpoint but differ in downstream fan-out:

*S2-int work unit* — `x^2` has no `y`, so exactly *one* downstream Integration call:
```json
{ "function": "x^2", "initialConditionY": 1, "steps": 5 }
```

*S2-amp work unit* — a `y`-bearing function loops, making *N = steps* sequential downstream
calls. `steps` is the swept fan-out N (§5); the value below shows the Medium level (N = 10):
```json
{ "function": "y+x", "initialConditionY": 1, "steps": 10 }
```

== Digital Filters Service — `api/filters` (port 5007, class STD)
#ep-table(
  [POST], [STD], [`/api/filters/apply-image`], [Applies a convolution filter to an uploaded image (multipart).], [✓ S1],
  [POST], [CHN], [`/api/filters/apply-ai-matrix`], [AI generates an N×N matrix, then the filter is applied locally (chained, heterogeneous → external AI).], [✓ S2-ext],
  [POST], [—], [`/api/filters/apply`], [Applies a filter to a raw matrix passed in the body.], [],
  [GET],  [—], [`/api/filters/available`], [Lists supported filters (also used as a liveness check).], [],
)
*S1 work unit* (`apply-image`) — fixed multipart form:
```text
image      = assets/filter_input_512.png   (fixed 512x512 PNG)
filterType = blur
```
*S2 work unit* (`apply-ai-matrix`) — AI generates the matrix, filter applied locally:
```json
{ "filterName": "blur", "kernelSize": 3 }
```

== Video Service — `api/video` (port 5006, class HVY)
#ep-table(
  [POST], [HVY], [`/api/video/compress`], [Compresses an uploaded video clip (multipart, heavy I/O + RAM).], [✓ S1],
  [POST], [—], [`/api/video/split-frames`], [Splits an uploaded video into individual frames.], [],
  [GET],  [—], [`/health`], [Liveness probe.], [],
)
*Work unit* (`compress`) — fixed multipart form:
```text
file = assets/sample_720p_10s.mp4   (fixed 10 s 720p H.264 clip, ~5 MB)
```

== AI Service — `api/Ai` (port 5005, dedicated VM, class HVY)
#ep-table(
  [POST], [HVY], [`/api/Ai/generate`], [Agentic generation: random numbers *or* a procedural image, driven by `user_input`.], [✓ S1],
  [GET],  [—], [`/api/Ai/image/{filename}`], [Returns a previously generated image (base64) and deletes it server-side.], [],
  [GET],  [—], [`/api/Ai/health`], [Deep health of Ollama, API, and MCP server components.], [],
)
*Work unit* (`generate`) — deterministic via fixed seed:
```json
{ "user_input": "Give me 10 random numbers between 1 and 100 with seed 42" }
```

#note[
  The fixed binary assets (`filter_input_512.png` and `sample_720p_10s.mp4`) must live on the
  load generator and be checked into the repository (e.g. `loadGenTests/assets/`) so the
  exact same bytes are used for every run, every configuration, and by every team member.
  Seeded/deterministic inputs (AI seed 42, fixed payloads) keep per-request work constant.
]

= Load Levels

For most scenarios, load is a target *requests-per-second (RPS)* sustained by the load
generator using k6's `constant-arrival-rate` executor (open model — request rate is
independent of response time, so a slow mesh cannot artificially reduce offered load). Three
levels are used. Because the benchmarked endpoints span very different per-request costs, four
load *classes* are defined: *STD* (compute endpoints that tolerate tens of RPS), *HVY*
(resource-extreme single-hop endpoints capped at low RPS per the sizing report in
`architecture/estimated_resource_calc.typ`), *CHN* (the S2-ext endpoints, gated by AI
inference latency), and *AMP* (the S2-amp scenario, whose load knob is the *fan-out N*, not
RPS — see below).

#figure(
  table(
    columns: (auto, auto, auto, auto, auto),
    fill: (x, y) => if y == 0 { luma(230) } else { none },
    inset: 8pt,
    align: (left + horizon, center, center, center, center),
    [*Class*], [*Scenario*], [*Low*], [*Medium*], [*High*],
    [STD — Permutation·generate, Fibonacci, Integration·calculate, DigitalFilters·apply-image], [S1], [25 RPS], [50 RPS], [100 RPS],
    [STD — Differential·solve, `x^2` (1 downstream call)], [S2-int], [25 RPS], [50 RPS], [100 RPS],
    [HVY — Video·compress, AI·generate], [S1], [1 RPS], [2 RPS], [5 RPS],
    [CHN — Permutation·generate-from-ai, DigitalFilters·apply-ai-matrix], [S2-ext], [1 RPS], [2 RPS], [5 RPS],
    [AMP — Differential·solve, `y`-fn @ fixed 2 RPS], [S2-amp], [N = 5], [N = 10], [N = 20],
  ),
  caption: [Target load per level and scenario type. STD levels match the existing pilot data (25/50/100). *S2-amp differs:* it holds a fixed low ingress rate (2 RPS) and varies the downstream *fan-out N* (= `steps`) instead, so the level directly measures how mesh overhead scales with the number of encrypted east-west hops; the amplified downstream load on Integration is `2 × N` RPS (10/20/40 — safely under its 100 RPS baseline). At $R$ RPS, `differential/solve` also imposes `R × calls` RPS on Integration. Levels are tunable: if baseline saturates (error ≥ 1% or p99 runaway), reduce the High tier / N and document the change.],
)

= Ingress and Endpoint Resolution

Every configuration is entered through a *single, path-routed ingress* exposed on a fixed
NodePort, so one base URL serves all services: `http://<node-ip>/api/<service>/...`. The
ingress controller is *meshed in both mesh phases* (Envoy gateway for Istio, an
injected-`linkerd-proxy` NGINX controller for Linkerd) so that north–south
(ingress→service) traffic carries mTLS symmetrically — see the note below.

#figure(
  table(
    columns: (auto, 1fr),
    fill: (x, y) => if y == 0 { luma(230) } else { none },
    inset: 8pt,
    align: (left + horizon, left + horizon),
    [*Config*], [*`TARGET_URL` base (verified on the cluster, Linkerd phase 2026-06-12)*],
    [B (baseline)], [NGINX ingress (unmeshed): `http://<node-ip>:30080/api/<service>/...`. Per-service NodePorts also exist as a fallback.],
    [I-S / I-P (Istio)], [Istio ingress gateway (meshed Envoy): `http://<node-ip>:$(kubectl -n istio-system get svc istio-ingressgateway -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')/api/<service>/...`.],
    [L-S / L-P (Linkerd)], [NGINX ingress (meshed: controller injected with `linkerd-proxy` + `service-upstream: "true"`): `http://<node-ip>:30080/api/<service>/...`. Per-service NodePorts: permutation 30101, fibonacci 30102, differential 30103, integration 30104, video 30106, filters 30107.],
  ),
  caption: [Ingress resolution per configuration. `<node-ip>` is any worker node, e.g. `10.29.20.113`. The NGINX NodePort is pinned to `30080` (HTTP) / `30443` (HTTPS) by the Linkerd phase playbook; the Istio gateway NodePort is dynamic and must be re-resolved after every `make istio`.],
)

#note[
  *North–south mTLS is symmetric by design.* Istio routes ingress through its Envoy gateway
  (always meshed). For Linkerd, the NGINX controller is *injected with `linkerd-proxy`* and
  the ingress carries `nginx.ingress.kubernetes.io/service-upstream: "true"` (so NGINX targets
  the Service ClusterIP, letting the proxy do discovery + mTLS). *Verified live:* a request
  through `:30080` reaches the backend with `tls="true"` and
  `client_id="ingress-nginx.ingress-nginx.serviceaccount.identity.linkerd…"`. Without this,
  the unmeshed controller would send plaintext to backends and S1 north–south would *not* be
  encrypted under Linkerd — breaking comparability with Istio. The meshing is wired into
  `deployments/ansible/phase_linkerd.yml` so every `make linkerd` reproduces it.
]

= Test Execution Lifecycle

Every individual run (one cell of the test matrix) follows the same four-phase lifecycle.
Only the *steady-state* window is used for analysis; warm-up and cooldown samples are
discarded.

#figure(
  table(
    columns: (auto, auto, 1fr),
    fill: (x, y) => if y == 0 { luma(230) } else { none },
    inset: 8pt,
    align: (left + horizon, center + horizon, left + horizon),
    [*Phase*], [*Duration*], [*Purpose / handling*],
    [Warm-up],  [30 s], [Drive target RPS but *discard* all data. Warms .NET JIT, fills HTTP connection pools, lets the sidecar reach steady CPU, and stabilises the autoscaler-free pod set.],
    [Steady-state], [120 s], [*Measurement window.* Record the precise UTC start/end timestamps; all Prometheus range queries and the k6 summary are scoped to this interval.],
    [Cooldown], [30 s], [Stop load, keep scraping. Confirms the system returns to idle and that no work is queued/backlogged.],
    [Rest], [30 s], [Idle gap before the next run so CPU/RAM return to the idle floor and runs do not contaminate each other.],
  ),
  caption: [Per-run lifecycle. Total #sym.tilde 3.5 min/run. The 120 s steady window is configurable; 60 s is an acceptable "express" setting that roughly halves total wall-clock time.],
)

== Repetitions and ordering

Each unique cell is repeated *N = 10* times to enable mean, standard deviation, and
confidence intervals. To control temporal/thermal drift:

- *Block by configuration.* Switching mesh requires a full `make <mesh>` redeploy
  (slow), so a configuration is deployed once and its entire sub-matrix is run before
  tearing down. This is the only practical blocking.
- *Randomise run order within a block* (service × load × repetition) so that any drift
  during a block is spread across cells rather than aliasing onto one service.
- *Interleave repetitions* — do not run all 10 reps of a cell back-to-back; cycle through
  cells so repetitions are temporally separated.
- *Idle-overhead capture.* For every configuration, record one 120 s window with *zero
  load*. This quantifies the static "tax just for being injected" (sidecar + control-plane
  CPU/RAM at rest), which is subtracted to isolate per-request cost.

= Test Matrix and Time Budget

#figure(
  table(
    columns: (1fr, auto),
    fill: (x, y) => if y == 0 { luma(230) } else { none },
    inset: 8pt,
    align: (left + horizon, center + horizon),
    [*Phase A — Per-endpoint isolation (primary)*], [*Runs*],
    [5 configs × 4 STD S1 endpoints × 3 loads × 10 reps], [600],
    [5 configs × 1 STD S2-int scenario (Differential, `x^2`) × 3 loads × 10 reps], [150],
    [5 configs × 1 AMP S2-amp scenario (Differential, `y`-fn) × 3 N-levels × 10 reps], [150],
    [5 configs × 2 HVY S1 endpoints × 3 loads × 10 reps], [300],
    [5 configs × 2 CHN S2-ext endpoints × 3 loads × 10 reps], [300],
    [5 configs × 1 idle-overhead capture], [5],
    [*Phase A subtotal*], [*1505*],
    [*Phase B — Aggregate full-system (complementary)*], [],
    [5 configs × 3 loads × 10 reps (all services driven simultaneously at the §5 profile)], [150],
    [*Total*], [*1655*],
  ),
  caption: [Run count. Ten benchmarked scenarios (6 S1 + S2-int + S2-amp + 2 S2-ext); `differential/solve` is benched twice. At #sym.tilde 3.5 min/run, Phase A is #sym.tilde 88 h and Phase B #sym.tilde 9 h of unattended test time. Reduce by using the 60 s steady window, trimming reps, or dropping Phase B if wall-clock is constrained.],
)

#note[
  *Phase A (isolation)* loads one scenario at a time — this cleanly attributes overhead to
  a specific workload type (RQ4) and is the core of the thesis. The *S2 (chained)* scenarios
  are the service-chaining cases (§3.1): `differential/solve` is the *sidecar-to-sidecar mTLS*
  path, benched both as a single hop (S2-int) and as an *N-way amplified fan-out* (S2-amp)
  that multiplies encrypted east-west hops per request; the two AI endpoints are *egress*
  cases (S2-ext). For RQ3, the cleanest east-west encryption delta is `differential/solve`
  under I-S vs. I-P, and S2-amp shows how that delta compounds with hop count. *Phase B
  (aggregate)* drives all services together at the target profile to validate findings under
  realistic contention. Phase B is optional; start with Phase A.
]

= Data Collection

Two independent data sources are combined per run. CPU/RAM come from Prometheus
(kube-prometheus-stack, namespace `monitoring`); latency comes from the k6 client-side
summary (the only latency source available in *all* configurations, including baseline).

== Latency (k6, client-side — primary)

k6 reports `http_req_duration` (time from first request byte sent to last response byte
received — includes ingress, mesh, and application). Export the full summary as JSON:

```bash
k6 run --summary-export=summary.json \
  -e TARGET_RPS=$RPS -e TARGET_URL="$URL" <service>-test.js
```

Extract `metrics.http_req_duration.values`: `med` (p50), `p(90)`, `p(95)`, `p(99)`, `avg`,
`max`, plus `http_req_failed.value` (error rate) and `http_reqs.count`. The latency
*delta* of any mesh config versus baseline B, at the same service+load, is the latency tax.

== CPU and RAM (Prometheus / cAdvisor)

cAdvisor metrics are scraped out-of-the-box for *every* container — application, sidecar,
and control plane — so no extra scrape config is needed for CPU/RAM. Scope every query to
the steady-state window with `start`/`end` (or the Grafana time picker).

#note[
  *Verified on the cluster (Linkerd phase, 2026-06-12):* Prometheus already returns
  `container_cpu_usage_seconds_total` and `container_memory_working_set_bytes` for the
  `linkerd-proxy` container (18 series = 6 services × 3 replicas), so the CPU/RAM pipeline
  needs no setup. Measured idle cost was #sym.tilde 1–2 m CPU / 2–3 MiB per sidecar and
  #sym.tilde 7 m CPU / 77 MiB for the whole Linkerd control plane — useful as the zero-load
  reference (§7.1). The kube-prometheus-stack release is confirmed `cluster-monitor`.
]

*CPU (millicores)* — rate of CPU-seconds, ×1000:

```promql
# Application container CPU (millicores), per pod
1000 * sum by (pod) (
  rate(container_cpu_usage_seconds_total{
    namespace="thesis-test", container="permutation-service"}[30s]))

# Sidecar CPU — Istio
1000 * sum by (pod) (
  rate(container_cpu_usage_seconds_total{
    namespace="thesis-test", container="istio-proxy"}[30s]))

# Sidecar CPU — Linkerd
1000 * sum by (pod) (
  rate(container_cpu_usage_seconds_total{
    namespace="thesis-test", container="linkerd-proxy"}[30s]))
```

*RAM (MiB)* — working set (the figure the kubelet uses for OOM decisions):

```promql
# Per container working set in MiB (app | istio-proxy | linkerd-proxy)
sum by (pod, container) (
  container_memory_working_set_bytes{
    namespace="thesis-test", container!="", container!="POD"}) / 1024 / 1024
```

*Control-plane overhead* — measured in the mesh's own namespace, not `thesis-test`:

```promql
# Istio control plane (istiod + ingress gateway)
1000 * sum(rate(container_cpu_usage_seconds_total{namespace="istio-system"}[30s]))
sum(container_memory_working_set_bytes{namespace="istio-system"}) / 1024 / 1024

# Linkerd control plane
1000 * sum(rate(container_cpu_usage_seconds_total{namespace="linkerd"}[30s]))
sum(container_memory_working_set_bytes{namespace="linkerd"}) / 1024 / 1024
```

For each metric, summarise the steady window by *mean* and *p95* (use
`quantile_over_time(0.95, (<query>)[120s:5s])` or aggregate the raw samples offline). Report
per-container and the app+sidecar *sum* (the true per-pod cost of running meshed).

== Latency from mesh telemetry (secondary, validation only)

Mesh-reported server-side latency is *not* comparable to baseline (baseline emits none),
so it is used only to cross-check k6 and to attribute latency to ingress vs. sidecar.
This requires Prometheus to scrape the proxies, which is *not* on by default in
kube-prometheus-stack. Add a `PodMonitor` labelled for this Prometheus release:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: istio-proxies
  namespace: thesis-test
  labels:
    release: cluster-monitor          # MUST match the kube-prometheus-stack release
spec:
  selector:
    matchExpressions:
      - { key: security.istio.io/tlsMode, operator: Exists }
  podMetricsEndpoints:
    - path: /stats/prometheus
      targetPort: 15020
      interval: 15s
```

Then `histogram_quantile(0.95, sum by (le) (rate(istio_request_duration_milliseconds_bucket{...}[1m])))`.
For Linkerd, scrape the proxy admin port `4191` `/metrics` (container port name
`linkerd-admin`) and query `response_latency_ms_bucket`:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: linkerd-proxies
  namespace: thesis-test
  labels:
    release: cluster-monitor          # MUST match the kube-prometheus-stack release
spec:
  selector:
    matchExpressions:
      - { key: linkerd.io/control-plane-ns, operator: Exists }
  podMetricsEndpoints:
    - path: /metrics
      port: linkerd-admin
      interval: 15s
```

The kube-prometheus-stack release name is confirmed `cluster-monitor`; PodMonitors without
the matching `release` label are silently ignored.

#warn[
  *Verified on the cluster (2026-06-12):* there are currently *no* PodMonitors/ServiceMonitors
  and no `linkerd-viz`, so `request_total` / `response_latency_ms_bucket` return *empty* —
  mesh latency telemetry is not yet collected. Apply the PodMonitor above (per active mesh)
  *before* the campaign if the secondary latency source is wanted. The primary latency source
  (k6, §9.1) needs none of this and works today.
]

= Finding the Plots in Grafana

Open Grafana (namespace `monitoring`). Get credentials with
`monitoring/prom-credentials.sh`, then port-forward:

```bash
kubectl -n monitoring port-forward svc/cluster-monitor-grafana 3000:80
# browse http://localhost:3000
```

== CPU and RAM — built-in dashboards (work for all 5 configs)

The kube-prometheus-stack ships these under the *Dashboards → Kubernetes* folder:

- *Kubernetes / Compute Resources / Namespace (Pods)* — set the `namespace` variable to
  `thesis-test`. Panels *CPU Usage* and *Memory Usage (WSS)* show every pod; this is the
  fastest per-service view.
- *Kubernetes / Compute Resources / Pod* — set `namespace=thesis-test` and pick the pod.
  Critically, this dashboard *breaks usage down per container*, so you can read the
  application container and the `istio-proxy`/`linkerd-proxy` container side by side — the
  core sidecar-overhead view.
- *Kubernetes / Compute Resources / Node (Pods)* — set `node` to a worker to see
  whole-node pressure during High load.

For the control-plane tax, reuse *Namespace (Pods)* with `namespace=istio-system` or
`namespace=linkerd`.

== Latency — dashboards

Baseline has no latency dashboard; use the k6 summary. For the mesh configs, after the
`PodMonitor` above is scraping, import the community dashboards via *Dashboards → New →
Import*:

- Istio: IDs *7639* (Mesh), *7636* (Service), *7630* (Workload) from grafana.com.
- Linkerd: install `linkerd-viz` (`linkerd viz install | kubectl apply -f -`) and use
  `linkerd viz dashboard`, or import the Linkerd Grafana dashboards.

== Pinning the time window

For each run, use Grafana's *absolute* time range set to the steady-state UTC
start/end you logged (§7). Reading "last 5 minutes" will smear warm-up and cooldown into
the measurement — always pin to the recorded window.

= Output Data Schema

Every run produces one row in a master CSV (`thesis-metrics/results/master.csv`),
joining the k6 summary and the Prometheus aggregates on `run_id`. One row = one cell ×
one repetition.

#figure(
  table(
    columns: (auto, 1fr),
    fill: (x, y) => if y == 0 { luma(230) } else { none },
    inset: 6pt,
    align: (left + horizon, left + horizon),
    [*Column group*], [*Fields*],
    [Identity], [`run_id`, `config` (B/I-S/I-P/L-S/L-P), `mesh`, `mtls`, `service`, `endpoint`, `scenario` (S1/S2-int/S2-amp/S2-ext), `load_class` (STD/HVY/CHN/AMP), `load_level`, `rps`, `fanout_n` (S2-amp only), `repetition`, `steady_start_utc`, `steady_end_utc`],
    [Latency (k6)], [`lat_avg_ms`, `lat_p50_ms`, `lat_p90_ms`, `lat_p95_ms`, `lat_p99_ms`, `lat_max_ms`, `reqs_total`, `req_failed_rate`],
    [CPU (Prom, millicores)], [`app_cpu_mean`, `app_cpu_p95`, `sidecar_cpu_mean`, `sidecar_cpu_p95`, `pod_cpu_sum_mean`, `ctrlplane_cpu_mean`],
    [RAM (Prom, MiB)], [`app_mem_mean`, `app_mem_max`, `sidecar_mem_mean`, `sidecar_mem_max`, `pod_mem_sum_mean`, `ctrlplane_mem_mean`],
  ),
  caption: [Master results schema. Deltas (mesh − baseline) and mTLS deltas are derived downstream from this table, not stored.],
)

= Repeatability Controls

To make results reproducible across operators and time:

- *Pin image digests.* The deployment manifests use `:latest` with
  `imagePullPolicy: Always` — a reproducibility hazard. For the measurement campaign, pin
  every service image to an immutable digest (`@sha256:...`) and freeze it for the
  duration.
- *Pin tool/mesh versions.* Record and fix: k6 version, Istio version (`istioctl version`),
  Linkerd version (`linkerd version`), Kubernetes (v1.34.3), kernel, and node CPU model.
- *Fix replica count.* Keep `replicas` constant (3) across all configs; no HPA. Mesh
  overhead must not be confounded by a changing pod count.
- *Pin resource requests/limits.* Identical `resources` blocks across B/Istio/Linkerd
  manifests so the application has the same headroom in every config.
- *Dedicated load generator.* Always drive load from the `lg` VM (10.29.20.130), never
  from inside the cluster, so the generator does not skew cluster CPU metrics.
- *Quiescent cluster.* No other workloads in `thesis-test`; confirm the idle floor with
  the zero-load capture before each block.
- *Clock sync.* k6 (on `lg`) and the cluster must share NTP-synced time, otherwise the
  Prometheus window and the k6 window will not align.
- *Verify mTLS state* every block (§3) — never assume STRICT/DISABLE/secured took effect.

= Assumptions and Limitations

- *Open-loop load.* `constant-arrival-rate` decouples offered load from latency; if a
  mesh saturates the service, latency rises and errors appear rather than throughput
  silently dropping. High-tier rates must be validated to keep baseline error < 1%.
- *Client-side latency includes ingress.* k6 latency is end-to-end through the ingress
  path, which differs structurally between Istio (Envoy ingress gateway) and Linkerd
  (NodePort, no gateway pod). This is part of the real cost of each mesh and is reported
  as such; mesh telemetry (§9.3) is used to attribute the ingress vs. sidecar split.
- *Linkerd "no-mTLS" is approximate* — see the caveat in §2. Treat L-P as a
  proxy-bypass data point, not an encryption-isolation data point.
- *AI service isolation.* The AI service runs on a dedicated VM outside the meshed worker
  pool; its sidecar/overhead semantics differ and are reported separately.

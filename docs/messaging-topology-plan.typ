#set page(paper: "a4", margin: (x: 2.2cm, y: 2.2cm), numbering: "1")
#set text(font: "Linux Libertine", size: 11pt)
#set heading(numbering: "1.1")
#set par(justify: true)

#align(center)[
  #text(size: 17pt, weight: "bold")[Phase C: Pure Messaging Topologies] \
  #v(0.3em)
  #text(size: 11pt)[Many services that only pass messages to each other] \
  #v(0.3em)
  #text(size: 10pt, style: "italic")[Draft plan for supervisor review — nothing here is implemented yet]
]
#v(1em)

= Goal

Phases A and B measure the mesh on real services, where application work (permutations,
video compression, LLM inference) dominates and the mesh cost is a small share of the total.
Phase C removes the application work entirely: every service only receives a message and
forwards it, so whatever latency and loss remain are caused by the network path, the sidecars
and the mesh control plane. Two quantities are measured:

- *Latency* — end-to-end and, derived from it, the cost of a single hop.
- *Loss* — requests that do not complete successfully, and where along the path they are lost.

Research questions:

+ How much latency does each mesh add *per hop*, and does it grow linearly with the length of
  the call chain?
+ How does fan-out (one request triggering many parallel calls) amplify the tail latency?
+ At what offered load does each mesh start losing requests, and does loss appear earlier than
  in the baseline?
+ Does the number of services in the mesh matter by itself, even when most of them are idle
  (control-plane and proxy-configuration size)?

= Workload

A single, minimal *relay service* image deployed many times. On each request it calls its
configured downstream services (sequentially or in parallel), waits for their responses and
replies; a leaf service replies immediately. No computation, no storage.

- Parameters per deployment: list of downstream services, sequential vs. parallel calls,
  response payload size.
- Each service exports *per-hop counters* — requests received, downstream calls sent,
  downstream failures — so a lost request can be located on a specific hop.
- Protocol: HTTP/1.1 with keep-alive, as in Phases A and B. gRPC (HTTP/2) is a possible later
  extension.
- Candidate tooling: *isotope* (from the Istio project's tools), which generates such service
  graphs from a topology file and is mesh-agnostic; alternatively a small custom relay
  service (a few dozen lines). To be decided after a pilot, including whether isotope exposes
  the per-hop counters above.

= Topologies

#figure(
  table(
    columns: (auto, 1fr, auto),
    fill: (x, y) => if y == 0 { luma(235) } else { none },
    inset: 7pt, align: (left + horizon, left + horizon, left + horizon),
    [*Id*], [*Shape*], [*Variants*],
    [T1 chain], [Entry → s1 → s2 → … → s#sub[d] (sequential). The slope of latency vs. depth
      is the per-hop cost.], [d = 1, 2, 4, 8, 16],
    [T2 fan-out], [Entry calls k leaf services in parallel and waits for all of them. Shows
      tail amplification: the slowest of k calls decides the response time.], [k = 2, 8, 32],
    [T3 scale], [A fixed T1 chain (d = 4) carries the traffic while N other services sit idle
      in the mesh.], [N = 10, 50, 100],
  ),
  caption: [Proposed topologies (11 variants). The values are a starting point for the pilot.],
)

Placement is fixed: one replica per service, and service #emph[i] is pinned to worker
#emph[i] mod 3, so every hop crosses nodes and the share of cross-node hops is the same in
every configuration. Resource requests and limits are identical for all relay services.

= Configurations and load

- *Configurations:* the same five as Phases A and B — B, L-P, L-S, I-P, I-S — plus C-S if the
  Consul setup is approved. L-P remains a proxy-bypass configuration, not encryption-off.
- *Entry point:* the same ingress per configuration as in Phase A.
- *Load:* open-loop k6 `constant-arrival-rate`, three rate tiers (low / medium / high) set
  from a baseline pilot as fixed fractions of the baseline saturation rate (e.g. 25 / 50 /
  75 %), and two payload sizes (small ≈ 100 B, large ≈ 10 KB).
- *Saturation run:* a stepped rate per configuration and topology, to find the highest rate
  at which loss stays below 1 %.
- *Repetitions:* n = 10 for every cell, as in Phases A and B.

= Metrics

== Latency

- k6 client-side p50 / p90 / p99 / p99.9 per run (primary).
- *Per-hop cost* = slope of a linear fit of latency vs. depth in T1, per configuration and
  rate; the mesh's per-hop tax is that slope minus the baseline slope.
- Fan-out amplification = p99 in T2 relative to the p99 of a single hop.

== Loss

Loss must be defined precisely, because three different things look like it:

- *Mesh/service loss* — non-2xx responses, connection resets and request timeouts (fixed k6
  timeout, e.g. 10 s). This is the quantity of interest.
- *Load-generator loss* — k6 `dropped_iterations` (the client could not start a request on
  time). It says nothing about the mesh; a run with non-zero dropped iterations is invalid and
  is repeated.
- *Hidden loss* — failures that a mesh retries and turns into success. Istio retries some
  failures by default, Linkerd does not unless configured. Retries hide loss but add latency,
  so the mesh retry counters are recorded for every run (see open questions).

Per-hop counters from the relay services locate the hop where requests are lost; the totals
must reconcile with the k6 request count.

== Secondary

CPU and memory of sidecars and control planes (cAdvisor, as in Phase B) are recorded but are
not the focus. They matter mainly for T3 and to confirm the relay services themselves never
become the bottleneck.

= Effort and time budget

Matrix: 5 configurations × 11 topology variants × 3 rates × n = 10 = 1650 runs per payload
size. At 60 s per run plus a 30 s pause that is ≈ 41 h of load per payload size, before
deployments, warm-up and saturation runs — comparable to the Phase A campaign. The pilot will
show whether some variants (e.g. d = 16, k = 32) can be measured at one rate only.

Preparation: relay service or isotope setup, topology manifests and their generation,
k6 scripts, collector support for the new topologies, then a baseline pilot to set the rate
tiers. Roughly one to two weeks before the campaign itself.

= Open questions for the supervisor

+ Tooling: isotope or a custom relay service?
+ Retries: keep each mesh's defaults (what users get) and report retry counters, or disable
  retries everywhere so that loss is directly comparable — or measure both?
+ Scale of T3: with 3 worker nodes and a sidecar in every pod, is N = 100 feasible, or is
  N = 50 the realistic maximum? To be checked in the pilot.
+ Include C-S (Consul) in this phase?
+ Is HTTP/1.1 enough, or should gRPC be part of the matrix?

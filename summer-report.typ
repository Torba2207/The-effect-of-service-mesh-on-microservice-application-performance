#set page(paper: "a4", margin: (x: 2.2cm, y: 2.2cm), numbering: "1")
#set text(font: "Linux Libertine", size: 11pt)
#set heading(numbering: "1.1")
#set par(justify: true)
#show raw.where(block: true): it => block(fill: rgb("#f5f5f5"), inset: 8pt, radius: 4pt, width: 100%, it)
#show link: set text(fill: rgb("#1a4f8a"))

#let note(body) = block(fill: rgb("#fff8e1"), stroke: 0.5pt + rgb("#e0c060"), radius: 4pt, inset: 9pt, width: 100%)[#body]

// ---------------- Title page ----------------
#align(center)[
  #image("images/Logo_pg_eti.png", width: 55%)
  #v(1.5em)
  #text(size: 22pt, weight: "bold")[The Effect of Service Mesh on Microservice Application Performance]
  #v(0.6em)
  #text(size: 14pt)[Research Project — Progress Report (Summer Semester)]
  #v(2em)
  #text(size: 12pt)[
    Alla Krylova 196722 · Oleksandr Nychyporchuk 196659 \
    Kiryl Pashkevich 196687 · Pavel Khmialeuski 197055
  ]
  #v(1em)
  #text(size: 11pt)[Supervisor: Krzysztof Gierłowski (KTI)]
  #v(2em)
  #text(size: 10pt, style: "italic")[Gdańsk University of Technology · Faculty of ETI]
]

#v(1fr)
#pagebreak()

#outline(indent: auto, depth: 2)
#pagebreak()

= Introduction

A large share of modern cloud applications is built on a *microservice architecture*: application
functionality is decomposed into small, independently deployable services that communicate over the
network, typically orchestrated by Kubernetes. Securing and controlling this inter-service
communication is increasingly delegated to a *service mesh* — an infrastructure layer (usually a set
of sidecar proxies) that transparently adds mutual TLS, traffic management, and observability.

These benefits are not free: every request now traverses additional proxies, and mutual TLS adds
cryptographic cost. *The goal of this project is to measure, experimentally and under controlled
conditions, how service-mesh solutions affect the performance of a microservice application* —
specifically CPU usage, RAM usage and latency — relative to a no-mesh baseline.

This report follows the chronological path of the work:

#block(inset: (left: 8pt))[
  *(1)* design of a microservice test application →
  *(2)* analytical sizing of system requirements →
  *(3)* a systematic literature review →
  *(4)* building the Kubernetes environment →
  *(5)* first service deployment →
  *(6)* an initial research design and *(7–8)* a pilot study →
  *(9)* deployment of the remaining services →
  *(10)* a revised research design →
  *(11)* automation of the measurement process →
  *(12)* the first full study (baseline, Istio + mTLS, Linkerd + mTLS) and its results →
  followed by the problems encountered and the planned next steps.
]

This document is an *interim progress report*. It summarises the work carried out during the
  summer semester: from the design of the test application through to the first complete
  cross-configuration performance study. It is not the final thesis; open problems and the
  planned continuation are described in §11–§12.

= The Microservice Test Application

A purpose-built *.NET 8* microservice application was implemented to serve as a controllable,
compute-heavy workload. Rather than a generic web shop, each service deliberately stresses a
different resource axis, so that the mesh overhead can be observed against distinct workload types.

#figure(
  image("images/SM_Project_App_Arch.drawio.png", width: 92%),
  caption: [Architecture of the microservice test application.],
)

#figure(
  table(
    columns: (auto, auto, 1fr),
    fill: (x, y) => if y == 0 { luma(230) } else { none },
    inset: 7pt,
    align: (left + horizon, center + horizon, left + horizon),
    [*Service*], [*Port*], [*Workload / stress axis*],
    [Permutation], [5001], [All permutations of a set, $O(n!)$ — CPU monopolisation],
    [Fibonacci], [5002], [n-th Fibonacci via `BigInteger` — CPU clock scaling],
    [Differential Equations], [5003], [Numerical ODE solver; *chains* to Integration (east–west)],
    [Integration], [5004], [Numerical definite integral — heavy CPU],
    [AI], [5005], [CPU LLM inference (Ollama); isolated on a dedicated VM],
    [Video], [5006], [Video compression (ffmpeg) — heavy I/O and RAM],
    [Digital Filters], [5007], [Image convolution filters — matrix maths],
  ),
  caption: [The seven backend services and the resource axis each is designed to stress.],
)

Services are independent ASP.NET Web APIs; an API gateway (YARP for local development, replaced by a
Kubernetes ingress in the cluster) routes incoming traffic. Several services make *cross-service
calls*: `differential/solve` always calls the in-cluster Integration service (a meshed→meshed,
east–west hop), while `permutation/generate-from-ai` and `filters/apply-ai-matrix` call the external
AI service. This heterogeneity is exploited later to study chained-request behaviour.

= System Requirements and Sizing

Because the application is a research benchmark rather than a user-facing product, traditional
rate-limit sizing does not apply. Instead, analytical *target capacities* were derived for each
service from an assumed aggregate load of 100 requests/second, an estimated per-request processing
time, an OS context-switching factor, and a fixed allowance for the mesh sidecar
($approx 150$ MB RAM, $approx 100$m CPU). The resulting per-instance provisioning targets and the
final cluster topology are summarised below.

#figure(
  table(
    columns: (auto, auto, auto, auto, 1fr),
    fill: (x, y) => if y == 0 { luma(230) } else { none },
    inset: 7pt,
    align: horizon,
    [*Node pool*], [*Count*], [*vCPU*], [*RAM*], [*Purpose*],
    [Control plane], [3], [4], [8 GB], [HA Kubernetes control plane + etcd quorum],
    [Data plane], [3], [8], [8 GB], [Hosts the microservices and mesh sidecars],
    [AI dedicated], [1], [24], [64 GB], [Isolated CPU-bound LLM inference (no GPU)],
    [Load generator], [1], [4], [8 GB], [External k6 load driver (keeps load off the cluster)],
  ),
  caption: [Final hardware provisioning derived from the analytical sizing model.],
)

The full derivation (per-service CPU/RAM formulas and redundancy assumptions) is documented in
`architecture/estimated_resource_calc.typ`.

= Systematic Literature Review

A systematic literature review (SLR) was conducted to ground the project in existing work and to
confirm the research gap. The protocol defined five research questions (covering mesh
implementations, performance metrics, the cost of security mechanisms, deployment/migration
patterns, and observability), a Boolean search string over service-mesh and microservice terms, and
explicit inclusion/exclusion and quality criteria.

Five databases were searched (Scopus, SpringerLink, arXiv, IEEE Xplore, ACM Digital Library),
returning *322 articles before deduplication*. After deduplication, two-round screening and quality
assessment, *12 articles* were retained for data extraction.

#grid(
  columns: (1fr, 1fr),
  gutter: 10pt,
  figure(image("SLR/database_counts_pre_dedup.png", width: 100%),
    caption: [Articles per database (pre-deduplication).]),
  figure(image("SLR/publications_by_year.png", width: 100%),
    caption: [Unique publications by year.]),
)
#figure(image("SLR/top_sources.png", width: 78%), caption: [Top publication sources.])

*Key findings from the literature.* (i) Sidecar architectures and mutual TLS introduce measurable
latency and CPU/RAM overhead, driven by cryptography and the Linux network stack. (ii) Direct
comparisons report Linkerd as lighter and lower-latency than Istio, while Istio offers richer traffic
control. (iii) The field is moving toward eBPF/sidecar-less data planes to cut proxy overhead.
(iv) Despite the performance penalty, meshes substantially improve resilience and observability.
These findings directly motivate our controlled, quantitative measurement of the
performance/security trade-off.

= Kubernetes Environment

The experimental environment is a *6-node Highly-Available Kubernetes cluster* provisioned with
*Kubespray v2.30.0* (Ansible), using the *Calico* CNI, on Ubuntu 24.04 nodes (kernel 6.8),
Kubernetes *v1.34.3*, containerd runtime. Nodes 1–3 are the HA control plane + etcd; nodes 4–6 are
the data-plane workers. A separate *AI VM* (Docker, two CPU-inference backends behind an nginx load
balancer) and a dedicated *load-generator VM* (k6) complete the topology. Passwordless SSH (a custom
`pgPB` key) and a project-local inventory drive all automation.

#figure(
  table(
    columns: (auto, 1fr),
    fill: (x, y) => if y == 0 { luma(230) } else { none },
    inset: 7pt, align: (left + horizon, left + horizon),
    [*Component*], [*Configuration*],
    [Cluster], [6 nodes (node1–3 control plane 10.29.20.101–103; node4–6 workers .111–.113), Calico, k8s v1.34.3. Worker disks were expanded to 22 GB to host monitoring (`deployments/docs/worker-prep.typ`).],
    [Provisioning], [Kubespray v2.30.0 via Ansible; inventory in `infrastructure/k8s/mycluster`],
    [AI VM], [10.29.20.120 — 24 vCPU / 64 GB, Docker, 2× `procedural-ai-server` + nginx LB :5005],
    [Load generator], [10.29.20.130 — k6],
    [Monitoring], [kube-prometheus-stack (Prometheus + Grafana), release `cluster-monitor`],
  ),
  caption: [Environment summary. ],
)

= First Service Deployment

The Permutation service was containerised first and used to validate the whole delivery path:
build → push to the GitHub Container Registry (GHCR) → deploy to Kubernetes. A `Dockerfile` per
service produces an image tagged `<container-registry>/<service>:latest`; Kubernetes `Deployment` and
`Service` manifests (3 replicas, NodePort) bring it online. This established the pattern later
generalised to all services and to the mesh-injected variants.

= Initial Research Design and Pilot Study

The first research design used a *single service (Permutation)* exercised through the ingress at
three offered loads — *25, 50 and 100 requests/second* — under three configurations: *baseline*,
*Istio* and *Linkerd*. Load was generated with *k6* (`constant-arrival-rate`) from the dedicated
generator VM; resource usage was sampled with `kubectl top pods` once per second; each cell was
repeated 10 times. The orchestration scripts (`thesis-metrics/run_100_tests.sh`,
`record_metrics.sh`) and raw results are archived in `thesis-metrics/`.

The pilot confirmed that the end-to-end pipeline worked and produced sensible latency/throughput
figures, but it also exposed the limits of the first design: `kubectl top` resolution is coarse
($approx 15$ s), it cannot separate the application container from the sidecar, and a single service
does not exercise the east–west, multi-hop traffic where a mesh's cost concentrates. These lessons
drove the revised design (§10).

= Deployment of the Remaining Services

All seven services were then containerised and deployed, together with an Ansible/Make automation
layer that switches the entire cluster between configurations: `make baseline | istio | linkerd`
runs a teardown → deep-clean → phase-deploy sequence. Each service carries three manifest variants
(plain, Istio, Linkerd); the playbooks install the chosen control plane, label/annotate the
`thesis-test` namespace for injection, and apply the matching manifests plus ingress routing.

#pagebreak()
= Revised Research Design

The revised design (full specification in `thesis-metrics/test-scenario.typ`) broadens the study
along every axis that the pilot found lacking. Its main elements:

#block(inset: (left: 8pt))[
  - *Five configurations:* baseline (B), Istio STRICT mTLS (I-S), Istio mTLS disabled (I-P),
    Linkerd with mTLS (L-S), Linkerd without mTLS (L-P). The Istio STRICT-vs-DISABLE pair isolates
    the *pure cost of mTLS* with the proxy held constant.
  - *All seven services*, each driven with a fixed "work unit" so per-request work is constant.
  - *Two scenario types:* 
    + *S1* single-hop (ingress → one service) 
    + *S2* chained (ingress → service → downstream). S2 splits into *S2-int* (`differential→integration`, in-cluster meshed→meshed mTLS), *S2-amp* (an amplified N-way fan-out variant) and *S2-ext* (`*→ai`, egress to the external AI VM).
  - *Three load levels* (low - 25 requests/second, med - 50 requests/second, high - 100 requests/second) and *N = 10 repetitions* per cell, with *warm-up / steady /
    cooldown* windows; only the steady window is measured.
  - *Metrics from Prometheus* (CPU millicores and RAM working-set, split application vs. sidecar vs.
    control plane) and *latency from the k6 client* (the only source comparable across all configs).
]

#note[
  *Methodological honesty baked into the design.* North–south mTLS is made symmetric by *meshing the
  nginx ingress* in the Linkerd phase (so it matches Istio's meshed Envoy gateway). For Linkerd, mTLS
  is always-on, so "Linkerd without mTLS" is approximated by proxy-bypass and reported as such. The
  AI chains terminate at the *unmeshed* external AI, so they measure egress + heterogeneous latency,
  not east–west encryption.
]

= Automation of the Study Process

To make a campaign of hundreds of runs repeatable, a self-contained harness was built in
`loadGenTests/phaseB/`:

#figure(
  table(
    columns: (auto, 1fr),
    fill: (x, y) => if y == 0 { luma(230) } else { none },
    inset: 7pt, align: (left + horizon, left + horizon),
    [*Component*], [*Role*],
    [`aggregate.js` (k6)], [Drives every service concurrently, one scenario each, at its per-level rate; records per-scenario latency.],
    [`run_phaseB.sh`], [Orchestrates one configuration: warm-up → steady → cooldown × levels × reps; pulls Prometheus; writes results.],
    [`collect_metrics.py`], [Per run, queries Prometheus for per-service app/sidecar/control-plane CPU & RAM and merges k6 latency → `master.csv`.],
    [`extract_timeseries.py`], [Per run, pulls the CPU/RAM *curves* (`query_range`) → `timeseries_<config>.csv`.],
    [`ai_probe/`], [Closed-loop (1 VU) probe for the AI/S2-ext chains, so the AI VM is never overloaded.],
    [`make_plots.py`, `make_ai_plot.py`], [Generate the comparison figures.],
  ),
  caption: [The Phase B automation harness.],
)

Two layers of data are produced per run: compact *scalars* (mean / p95 / max over the steady window)
for cross-config statistics, and full *time-series* for behaviour curves. Latency is captured
client-side by k6 at true per-second resolution; CPU/RAM resolution is bounded by the cAdvisor scrape
($approx 15$ s).

= First Full Study and Results

The first complete study covers *three configurations — baseline, Istio + mTLS (STRICT), and
Linkerd + mTLS* — each with 30 aggregate runs (3 load levels × 10 reps) plus a closed-loop AI probe.
All 90 aggregate runs completed with a 0% request-failure rate on the in-cluster services.

== Overall resource usage over time

#figure(image("loadGenTests/phaseB/results/plots/high/overall_ram.png", width: 95%),
  caption: [Overall RAM (mean of all services, app + sidecar) over the steady window at high load.])

#figure(image("loadGenTests/phaseB/results/plots/high/overall_cpu.png", width: 95%),
  caption: [Overall CPU (mean of all services, app + sidecar) over time at high load.])

The single clearest result is *memory*: the per-pod data-plane footprint of *Istio's Envoy sidecar
is roughly 7–9× that of Linkerd's Rust micro-proxy*.

#figure(
  table(
    columns: (auto, auto, auto),
    fill: (x, y) => if y == 0 { luma(230) } else { none },
    inset: 7pt, align: (left + horizon, center, center),
    [*Service*], [*Linkerd sidecar RAM (MiB)*], [*Istio sidecar RAM (MiB)*],
    [permutation], [11], [95],
    [fibonacci], [10], [96],
    [integration], [15], [98],
    [differential], [14], [97],
    [digital-filters], [15], [99],
    [video], [13], [99],
  ),
  caption: [Per-pod sidecar RAM working-set at high load. Linkerd-proxy ($approx 12$ MiB) vs. Envoy ($approx 95$ MiB).],
)

CPU per sidecar is comparable between the two meshes (Linkerd 31–67 m, Istio 37–67 m at high load);
the *control plane* differs ($approx 3$ m / 80 MiB for Linkerd vs. $approx 177$ m / 166 MiB for
Istio), though the Istio figure also includes the Envoy ingress gateway (handling all north–south
traffic) and is therefore not directly comparable.

== Latency

#figure(
  table(
    columns: (auto, auto, auto, auto),
    fill: (x, y) => if y == 0 { luma(230) } else { none },
    inset: 7pt, align: (left + horizon, center, center, center),
    [*Service*], [*baseline*], [*Linkerd*], [*Istio*],
    [permutation], [4.8 ms], [5.7 ms], [5.5 ms],
    [fibonacci], [1.8 ms], [2.9 ms], [2.5 ms],
    [integration], [1.7 ms], [2.8 ms], [2.4 ms],
    [differential (S2-int)], [2.2 ms], [3.7 ms], [3.7 ms],
    [digital-filters], [8.4 ms], [9.1 ms], [8.9 ms],
    [video], [467 ms], [474 ms], [450 ms],
  ),
  caption: [Latency p95 at high load. Both meshes add $approx 1$ ms to the light services; Linkerd and Istio are within noise of each other.],
)

Both meshes add only about *1 ms of p95 latency* to the light compute services; on the heavy,
app-dominated services (video) the mesh contribution is negligible. In *relative CPU* terms the mesh
tax is large for cheap services (fibonacci $approx +40%$, integration $approx +51%$) and negligible
for expensive ones — the sidecar's fixed cost simply dominates a cheap request.

== Per-service behaviour

#figure(image("loadGenTests/phaseB/results/plots/high/service_integration.png", width: 100%),
  caption: [Integration service: CPU and RAM over time, and latency p95 across loads.
  The mesh sidecars raise CPU from $approx 135$ m (baseline) to $approx 200$ m, and Istio's RAM
  ($approx 268$ MiB) stands well above Linkerd's ($approx 187$ MiB) and baseline's ($approx 178$ MiB).])

Equivalent figures for every service (and for low/medium load) are generated into
`loadGenTests/phaseB/results/plots/`.

== AI / chained (S2-ext) latency

#figure(image("loadGenTests/phaseB/results/plots/ai_probe_latency.png", width: 95%),
  caption: [AI / S2-ext chain latency (closed-loop probe, 30 samples each). Bars = p50, whiskers → p95.])

For the AI-bound chains the picture is the opposite of the compute services: latency
($approx 1.4$–$1.8$ s) is *entirely dominated by the CPU LLM inference*, and the differences between
baseline, Linkerd and Istio fall within the measurement spread. The mesh tax is real but invisible
here — confirming that mesh overhead must be read from the *S1 compute services*, not from chains
gated by an external bottleneck.

== Summary of findings

#block(inset: (left: 8pt))[
  + *Memory is the headline:* Istio's Envoy sidecars cost $approx 95$ MiB each vs. Linkerd's
    $approx 12$ MiB — a $7$–$9$× difference in data-plane RAM.
  + *Latency tax is small and similar* for both meshes ($approx 1$ ms p95 on light services).
  + *CPU overhead is similar* between meshes; large in % terms for cheap services, negligible for
    heavy ones.
  + *Chained AI latency is bottleneck-dominated* and does not discriminate between configurations.
]

= Problems Encountered

#block(inset: (left: 8pt))[
  - *AI service capacity (the main blocker).* The AI service performs CPU-only LLM inference
    ($approx 6$–$7$ s per request); each request uses $approx 10$ of the VM's 24 cores, so only
    $approx 2$ run in parallel — a hard ceiling of $approx 0.3$ req/s. Driving it with the
    rate-based aggregate at any sustained rate caused a runaway server-side backlog and overload
    (the VM became unresponsive). The fix was a *closed-loop probe* (concurrency 1) that
    self-throttles to the AI's true throughput; the underlying cause is simply *a lack of vCPUs / no
    GPU*, which caps achievable AI throughput.
  - *Prometheus retention.* The monitoring Prometheus uses a *1 h retention on tmpfs* (RAM-backed,
    ephemeral). A campaign is longer than 1 h, so post-hoc back-fill silently lost the earliest runs.
    Fixed by extracting each run's time-series *immediately* (per-run), within the retention window.
]

= Next Steps

#block(inset: (left: 8pt))[
  + *Resolve the AI bottleneck* — provision more vCPUs (or a GPU) for the AI node so the heterogeneous
    AI chains can be studied under real load rather than a closed-loop trickle.
  + *Complete the mTLS matrix* — run the remaining planned configurations: *Istio with and without
    mTLS*, *Linkerd with and without mTLS*, isolating the pure cost of encryption.
  + *Add a third mesh* — extend the comparison to *Consul* (with and without mTLS) alongside Istio
    and Linkerd.
  + *Study Istio Ambient (sidecar-less data plane).* The single largest cost we measured is the
    per-pod Envoy sidecar ($approx 95$ MiB RAM each, §11.1). Istio's *Ambient* mode removes the
    per-pod sidecar entirely, replacing it with a shared per-node L4 proxy (*ztunnel*) that provides
    mTLS, plus an optional per-namespace L7 *waypoint* proxy only where richer routing is needed. This
    directly tests the SLR's central trend — that the field is moving toward sidecar-less / eBPF data
    planes to cut proxy overhead (§4) — by measuring whether Ambient retains Istio's mTLS and traffic
    features while collapsing the data-plane RAM footprint that dominates the sidecar mode. We plan to
    run Ambient (with and without L7 waypoints, and with/without mTLS where applicable) through the
    same automated harness, so its CPU/RAM/latency are directly comparable to the sidecar-based Istio,
    Linkerd and Consul results.
  + *Latency-focused study* — investigate the behaviour of microservices in the regime the meshes are
    actually built for: *many small services exchanging frequent, near-empty requests*, with
    *simulated inter-node latency*, to characterise how each data plane behaves when proxy/encryption
    overhead dominates the payload rather than the computation.
]

= Conclusions

During the summer semester the project advanced from a paper design to a *fully automated,
reproducible measurement pipeline* and a first complete three-way performance study. The results
already provide a clear, quantitative answer to part of the research question: at these loads the
*latency tax of a service mesh is small ($approx 1$ ms) and similar for Istio and Linkerd*, while the
*memory footprint differs sharply* — Envoy sidecars cost roughly 7–9× the RAM of Linkerd's
micro-proxy. The chained, AI-bound scenarios are dominated by an external CPU bottleneck and do not
yet discriminate between meshes; removing that bottleneck, completing the mTLS / multi-mesh matrix,
and extending it to *sidecar-less data planes (Istio Ambient)* are the immediate next steps — the
latter directly targeting the large per-pod sidecar memory cost identified above. The literature's
central message — that mesh overhead is real but highly contextual — is borne out by these first
measurements and motivates the continued study.

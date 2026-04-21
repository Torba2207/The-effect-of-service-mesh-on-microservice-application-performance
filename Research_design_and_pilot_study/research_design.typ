#set page(paper: "a4", margin: 1in)
#set text(size: 11pt)
#set heading(numbering: "1.1")

#align(center)[
  #text(size: 17pt, weight: "bold")[Research Design and Pilot Study Report]
]

#align(center)[
  Alla Krylova 196722 \
  Oleksandr Nychyporchuk 196659 \
  Kiryl Pahkevich 196687 \
  Pavel Khmialeuski 197055
]
#v(1em)

= Research project

== Title
The impact of service-mesh solutions on the efficiency of microservice applications

== Supervisor
Krzysztof Gierłowski (KT)

== Goals and short description
Currently, a significant portion of applications deployed in cloud environments utilize microservices architecture. This type of architecture requires decomposing application functionality into component elements, implemented by individual microservices, and then deploying them in an environment that allows the microservices to communicate efficiently and reliably. This task is most often accomplished by orchestration platforms such as Kubernetes. Maintaining the separation and security of applications sharing the same deployment platform is also a key aspect of this type of deployment. Service mesh solutions are often used for this purpose, as they can automatically create secure communication environments for specific applications.

The aim of this project is to analyze and experimentally test the impact of using service mesh solutions on the efficiency (and particularly performance) of an application composed of multiple microservices.

= Research design

== Research goal
The goal of this research is to empirically evaluate and compare the performance overhead introduced by different service mesh implementations (specifically Istio and Linkerd) in a custom microservices application running on Kubernetes, compared to a baseline deployment without any service mesh. The custom application includes heterogeneous services: AI agent service, media processing (video, digital filters), and mathematical computation modules (differential equations, integration, permutations, Fibonacci). The research aims to quantify the trade-offs between security features (mTLS) and performance metrics (latency, throughput, CPU/memory consumption, CPU clock scaling) across these implementations.

== Research gap
The systematic literature review identified 12 core articles on service mesh performance. Key findings from the SLR indicate:

+ Service meshes introduce measurable latency and resource overhead, primarily due to sidecar proxies and mTLS @barr_technical_2024 @ganguli_challenges_2021.
+ Linkerd generally exhibits lower overhead than Istio under high load @bosquez_comparative_2025, but Istio remains the standard for complex traffic management.
+ Newer eBPF-based architectures show promise in reducing overhead @yang_network_2024 @barr_technical_2024.
+ Most studies focus on either single service mesh implementations or compare different meshes using standard benchmarks. However, there is a lack of controlled, reproducible experiments that compare multiple service meshes against a common baseline using a custom, heterogeneous microservice application that stresses different resource types (CPU‑intensive math, I/O‑oriented media). Furthermore, few studies systematically vary security feature activation (mTLS on/off) to quantify the security-performance trade-off across meshes.

Our research will fill this gap by conducting a controlled experiment that measures the performance impact of adding different service meshes (Istio, Linkerd) to a purpose‑built microservice application (designed to isolate throughput, CPU clock scaling, RAM usage, and latency), with and without security features enabled, and compares them against a no‑mesh baseline.

== Research questions

#set enum(numbering: "RQ1)")
+ How do different service mesh implementations (Istio vs. Linkerd) compare in terms of average latency and throughput relative to a baseline deployment without any service mesh, when running a heterogeneous microservice application?
+ What is the CPU and memory consumption overhead of Istio and Linkerd (including sidecar proxies and control planes) under increasing request loads, and how do they compare across different service types (math, media, AI)?
+ What is the additional performance overhead specifically attributable to mTLS when enabled versus disabled within each service mesh, and how does this overhead differ between Istio and Linkerd?

== Research hypotheses

#table(
  columns: (auto, auto, auto),
  inset: 6pt,
  align: horizon,
  [*RQ*], [*Hypothesis ($H$)*], [*Null Hypothesis ($H_0$)*],
  [RQ1], [$H_1$: Both Istio and Linkerd increase latency and reduce throughput compared to baseline, but Linkerd has lower latency and higher throughput than Istio under high load across all service types.], [$H_01$: There is no statistically significant difference in latency or throughput between any pair of configurations (baseline, Istio, Linkerd).],
  [RQ2], [$H_2$: Linkerd consumes fewer CPU and memory resources than Istio, and both consume significantly more than the baseline (≥20% additional) - with the largest overhead observed on mathematical services (CPU‑bound) and media services (memory‑bound).], [$H_02$: CPU and memory usage do not differ significantly between Istio, Linkerd, and baseline for any service type.],
  [RQ3], [$H_3$: Enabling mTLS adds measurable overhead in both meshes, but the relative overhead (percentage increase) is similar for Istio and Linkerd.], [$H_03$: mTLS does not introduce significant additional performance overhead beyond the base sidecar in either mesh, or the overhead differs substantially between meshes.],
)

*All hypotheses are falsifiable and will be tested with statistical significance ($#sym.alpha = 0.05$).*

== Research subjects and sample
In the context of this performance experiment, the subjects are the experimental configurations of the custom microservice application under test. Each configuration is a combination of:

- Service mesh presence: None (baseline) vs. Istio vs. Linkerd
- mTLS setting (if mesh): Disabled vs. Enabled
- Load level: Low (25 req/s), Medium (50 req/s), High (100 req/s)
- Service type: AI Service, Media (Video + Filters), Mathematical (Differential Equations, Integration, Permutations, Fibonacci)

*Sample:* We will use a full factorial design: 1 (baseline) + 2 (meshes: Istio, Linkerd) × 2 (mTLS on/off) × 3 load levels = 13 configurations. Each configuration will be tested 10 times across 3 service types → total experimental runs = 13 × 10 × 3 = 390. This accounts for service‑type heterogeneity.

*Qualification criteria for inclusion:* The custom application must be deployed as a set of containerized microservices, each exposing a REST endpoint. The infrastructure must be a dedicated Kubernetes cluster. The application is designed to stress different system resources:
- *AI Service*: heavy compute, requires load caps, strict isolation.
- *Media Services*: video compression, frame splitting, matrix filters (memory and I/O).
- *Mathematical Modules*: CPU‑intensive (differential equations, integration, permutations $O(n!)$, Fibonacci for clock scaling).

*Sampling method:* Non-probabilistic - we select the services that represent typical microservice communication patterns (request‑response, chain calls, parallel fan‑out).

== Operationalization - variables

#table(
  columns: (auto, auto, auto),
  inset: 6pt,
  align: horizon,
  [*Variable type*], [*Name*], [*Operational definition / Measurement*],
  [Independent], [Service mesh type], [Categorical: `baseline` (no mesh), `Istio`, `Linkerd`],
  [Independent], [mTLS setting], [Categorical: `disabled` vs. `enabled` (only applied to mesh conditions)],
  [Independent], [Request load], [Continuous: offered load in requests per second (req/s), varied at 25, 50, 100 req/s],
  [Dependent], [Average latency], [Mean request-response time (ms) per service endpoint over a 60-second steady-state window, reported as p50, p95, p99 percentiles],
  [Dependent], [Throughput], [Maximum sustained requests per second achieved per service before error rate exceeds 1%],
  [Dependent], [CPU usage], [Average CPU millicores consumed by mesh sidecars + application containers, separated per service],
  [Dependent], [Memory usage], [Average resident memory (MiB) consumed, separated per service],
  [Dependent], [CPU clock scaling], [Observed CPU frequency scaling (GHz) on math nodes under Fibonacci load],
  [Confounding], [Network conditions], [Controlled by running all tests in the same isolated cluster on identical hardware; monitor for external interference],
  [Confounding], [Application version], [Fixed version of the custom application across all runs],
  [Confounding], [Kubernetes version], [Fixed version across all runs],
  [Hidden], [Garbage collection cycles], [Minimized by running each test for a sufficient duration (warm-up + measurement) and averaging over repetitions],
  [Hidden], [Node heterogeneity], [Use identical instances for all worker nodes],
)

== Research methods
This research will employ a controlled real-life experiment conducted in a cloud-based Kubernetes environment. The experiment is reproducible and quantitative. No human subjects are involved; only system performance metrics are collected.

*Primary method:* Laboratory experiment with repeated measures (each configuration is tested multiple times) and blocking on service type to account for heterogeneity.  

== Research tools

*Experimental setup:*
- *Cloud provider:* Local Kubernetes cluster
- *Orchestration:* Kubernetes (version 1.28+)
- *Service meshes:* 
  - Istio (latest stable, e.g., 1.22) with default sidecar injection
  - Linkerd (latest stable, e.g., 2.15) with default sidecar injection
- *Custom microservice application:* Built by the team, consisting of:
  - *AI Service*: service with AI agent logic used for test data generation 
  - *Media Service*: service for video splitting and digital filters
  - *Math Services*: C\# implementations of differential equations, integration, permutations, Fibonacci (with configurable $n$)
- *Load generator:* A separate virtual machine (VM) running a custom Python script that sends HTTP requests to the ingress of the Kubernetes cluster. The script controls the request rate (25, 50, 100 req/s) and targets each service endpoint. The VM is isolated from the cluster to avoid affecting resource measurements.
- *Metrics collection:*
  - Prometheus (for system metrics)
  - Mesh-specific telemetry (Istio's built-in, Linkerd's viz extension)
  - Kubernetes metrics-server (for container CPU/memory)
  - Custom metrics for CPU clock scaling

*Experiment design (detailed):*
1. Deploy baseline (no service mesh) - measure performance for each service type under three load levels (10 repetitions each).
2. Deploy Istio with mTLS disabled - repeat measurements.
3. Deploy Istio with mTLS enabled - repeat measurements.
4. Deploy Linkerd with mTLS disabled - repeat measurements.
5. Deploy Linkerd with mTLS enabled - repeat measurements.
6. Each test run consists of:
   - 60s warm-up
   - 120s steady-state measurement
   - Cooldown
7. Record aggregated metrics per service type and configuration.

== Expected results

*Quantitative:*
- Latency distributions (p50, p95, p99) per service type for each configuration and load level.
- Throughput saturation curves.
- CPU and memory overhead percentages relative to baseline, broken down by service type.
- CPU clock scaling behavior on math services (Fibonacci) under mesh vs. baseline.

*Qualitative:*
- Identification of bottlenecks specific to each mesh.
- Insights into whether overhead is constant or scales with load and service type.
- Recommendations for practitioners: which mesh to choose based on workload characteristics (CPU‑intensive math, I/O media, or mixed).

== Validity threats

#table(
  columns: (auto, auto, auto),
  inset: 6pt,
  align: horizon,
  [*Threat type*], [*Description*], [*Mitigation*],
  [Construct validity], [Measured metrics may not fully represent “efficiency” (e.g., latency alone ignores user experience).], [Use multiple metrics (latency, throughput, resource usage, clock scaling). Relate to SLR definitions.],
  [Internal validity], [Uncontrolled variables (e.g., network jitter, node scheduling) affect results.], [Run all tests on isolated, dedicated cluster; repeat each condition 10 times; randomize order.],
  [External validity], [Results may not generalize to other applications, cloud providers, or service meshes.], [Use a custom application that covers diverse workload types; test two representative meshes (Istio, Linkerd); discuss limitations.],
  [Conclusion validity], [Random chance may produce false significance.], [Use appropriate statistical tests, set $#sym.alpha = 0.05$, and report effect sizes and confidence intervals.],
)

== Research plan

#table(
  columns: (auto, auto, auto, auto),
  inset: 6pt,
  align: horizon,
  [*Phase*], [*Tasks*], [*Responsible*], [*Duration*],
  [1. Application development], [Build and containerize AI, Media, Math services; create Kubernetes deployment manifests], [All team members], [5 days],
  [2. Environment setup], [Provision Kubernetes cluster, install Istio and Linkerd, deploy custom app, validate baseline], [Oleksandr Nychyporchuk, Kiryl Pashkevich], [3 days],
  [3. Load generator & monitoring], [Develop custom load script on separate VM, configure Prometheus, create measurement scripts targeting each service], [Pavel Khmialeuski, Alla Krylova], [2 days],
  [4. Pilot study], [Run 1 repetition of each configuration (13 runs) for one service type (Math) to validate toolchain], [Alla Krylova (execution), Oleksandr Nychyporchuk (verification)], [1 day],
  [5. Full experiment], [Execute 10 repetitions per configuration × 3 service types (390 runs), collect raw data], [All team members (divided runs)], [7-10 days],
  [6. Data analysis], [Statistical tests, visualization, hypothesis testing], [Oleksandr Nychyporchuk, Kiryl Pashkevich], [4 days],
  [7. Reporting], [Write research paper / report sections], [Alla Krylova (draft), Oleksandr Nychyporchuk (final)], [4 days],
)

== Publication goals
The results of this research are suitable for publication in:

- *Conference:* IEEE International Conference on Cloud Computing (CLOUD), IEEE International Conference on Edge Computing (EDGE), or International Conference on Software Engineering (ICSE) - SEIP track.
- *Journal:* Journal of Systems and Software, IEEE Transactions on Network and Service Management, or Cluster Computing.

The pilot study results alone may serve as a short paper or a technical report. The full experiment, if significant, can be submitted as a full conference paper.

= Pilot study

== Research subjects
For the pilot study, we used a subset of the experimental configurations to verify that all tools work and produce plausible data. The pilot focused on the Mathematical Modules (specifically the Permutations service $O(n!)$) as the most CPU‑intensive. The pilot included 7 configurations (single repetition each):

1. Baseline - low, medium, high load (25, 50, 100 req/s) – 3 runs
2. Istio (mTLS off) - low, medium, high load – 3 runs
3. Linkerd (mTLS off) - high load only (100 req/s) – 1 run

*We omitted mTLS-on conditions and other service types in the pilot due to time constraints but will include them in the full experiment.*

*Qualification:* The pilot used the same hardware and software versions as planned for the full experiment.

== Study execution
- *Executed by:*
- *Verified by:* 
- *Date:* 
- *Environment:* 
- *Tools:* 
- *Procedure:*
  1. Deploy baseline (no service mesh) application.
  2. From the load VM, run the script for each load level (25, 50, 100 req/s) - each test includes 30s warm-up, 60s measurement.
  3. Record latency (p95), CPU usage of the permutations container, and total memory.
  4. Install Istio with default sidecar injection, disable mTLS, redeploy application.
  5. Repeat step 2-3.
  6. Install Linkerd with default sidecar injection, disable mTLS, redeploy application.
  7. Repeat high-load test only (100 req/s).
  8. Aggregate metrics.

== Results

== Conclusions

= Conclusions

== Design


== Pilot study


= Literature

#bibliography("research_design.bib", style: "ieee", full: true)
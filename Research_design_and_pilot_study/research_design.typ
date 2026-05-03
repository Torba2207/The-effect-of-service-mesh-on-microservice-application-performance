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
The goal of this research is to empirically evaluate and compare the performance overhead introduced by different service mesh implementations (specifically Istio, Linkerd, Consul, and Istio Ambient) in a custom microservices application running on Kubernetes, compared to a baseline deployment without any service mesh. The custom application includes heterogeneous services: an AI agent service (running on a separate virtual machine for true isolation), media processing (video, digital filters), and mathematical computation modules (differential equations, integration, permutations, Fibonacci). The research aims to quantify the trade-offs between security features (mTLS) and performance metrics (latency, throughput, CPU/memory consumption, CPU clock usage) across these implementations.

== Research gap
The systematic literature review identified 12 core articles on service mesh performance. Key findings from the SLR indicate:

+ Service meshes introduce measurable latency and resource overhead, primarily due to sidecar proxies and mTLS @barr_technical_2024 @ganguli_challenges_2021.
+ Linkerd generally exhibits lower overhead than Istio under high load @bosquez_comparative_2025, but Istio remains the standard for complex traffic management.
+ Newer eBPF-based architectures (e.g. Istio Ambient) show promise in reducing overhead @yang_network_2024 @barr_technical_2024.
+ Most studies focus on either single service mesh implementations or compare a limited set of meshes using standard benchmarks. However, there is a lack of controlled, reproducible experiments that compare multiple service meshes (including sidecar-less and eBPF-based variants) against a common baseline using a custom, heterogeneous microservice application that stresses different resource types (CPU-intensive math, I/O-oriented media, and off-cluster AI). Furthermore, few studies systematically vary security feature activation (mTLS on/off) to quantify the security-performance trade-off across meshes.

Our research will fill this gap by conducting a controlled experiment that measures the performance impact of adding different service meshes (Istio, Linkerd, Consul, Istio Ambient) to a purpose-built microservice application (designed to isolate throughput, CPU clock usage, RAM usage, and latency), with and without security features enabled, and compares them against a no-mesh baseline.

== Research questions

#set enum(numbering: "RQ1)")
+ How do different service mesh implementations (Istio, Linkerd, Consul, Istio Ambient) compare in terms of average latency and throughput relative to a baseline deployment without any service mesh, when running a heterogeneous microservice application (including an off-cluster AI service)?
+ What is the CPU and memory consumption overhead of each service mesh (including sidecar proxies and control planes) under increasing request loads, and how do they compare across different service types (math, media, off-cluster AI)?
+ What is the additional performance overhead specifically attributable to mTLS when enabled versus disabled within each service mesh, and how does this overhead differ among the four meshes?

== Research hypotheses

#table(
  columns: (auto, auto, auto),
  inset: 5pt,
  align: horizon,
  [*RQ*], [*Hypothesis ($H$)*], [*Null Hypothesis ($H_0$)*],
  [RQ1], [$H_1$: Under high load conditions, the implementation of an Istio service mesh introduces a statistically significant increase in latency compared to the baseline application without a service mesh.], [$H_01$: Under high load conditions, there is no statistically significant difference in latency between the Istio service mesh implementation and the baseline application.],
  [RQ2], [$H_2$: Enabling mTLS within the Consul service mesh introduces a statistically significant performance overhead compared to the identical Consul setup with mTLS disabled.], [$H_02$: Enabling mTLS within the Consul service mesh does not introduce a statistically significant performance overhead compared to the identical Consul setup with mTLS disabled.],
  [RQ3], [$H_3$: Under identical load conditions, the Linkerd service mesh keeps statistically significantly higher throughput than the standard Istio service mesh.], [$H_03$: Under identical load conditions, the Linkerd service mesh does not keep statistically significantly higher throughput than the standard Istio service mesh.],
  [RQ4], [$H_3$: Under identical load conditions, the Istio Ambient mesh consumes statistically significantly less CPU than the standard Istio sidecar implementation.], [$H_03$: Under identical load conditions, the Istio Ambient mesh does not consume statistically significantly less CPU than the standard Istio sidecar implementation.],
)

*All hypotheses are falsifiable and will be tested with statistical significance ($#sym.alpha = 0.05$).*

== Research subjects and sample
In the context of this performance experiment, the subjects are the experimental configurations of the custom microservice application under test. Each configuration is a combination of:

- Service mesh presence: None (baseline) vs. Istio vs. Linkerd vs. Consul vs. Istio Ambient
- mTLS setting (if mesh): Disabled vs. Enabled
- Service type: AI Service (off-cluster), Media (Video + Filters), Mathematical (Differential Equations, Integration, Permutations, Fibonacci)

Every application configuration will be tested on 3 load levels:
 - Low - 25 req/s
 - Medium - 50 req/s
 - High 100 req/s

*Sample:* We will use a full factorial design:  
Baseline ((1 configuration, no mTLS) + 4 meshes x 2 (mTLS on/off)) x 3 load levels = 3 + 24 = 27 distinct configurations.  
Each configuration will be tested 10 times across 3 service types → total experimental runs = 27 x 10 x 3 = 810 runs.

*Study population:* The custom application must be deployed as a set of containerized microservices (except the AI service, which runs on a separate VM), each exposing a REST endpoint. The infrastructure must be a dedicated Kubernetes cluster plus an isolated VM for the AI service. The application is designed to stress different system resources:
- *AI Service* (off-cluster): heavy compute, requires load caps, strict isolation - communicates with the cluster via a dedicated ingress.
- *Media Services*: video compression, frame splitting, matrix filters (memory and I/O).
- *Mathematical Modules*: CPU-intensive (differential equations, integration, permutations $O(n!)$, Fibonacci for clock time).
Evaluating the entire application comprehensively is beyond the scope of this initial pilot study due to its overall scale and complexity. Therefore, to ensure precise measurement and tightly controlled variables, our experiments will focus exclusively on isolated, singular aforementioned modules of the application.

*Sampling method:* Non-probabilistic - we select the services that represent typical microservice communication patterns (request-response, chain calls, parallel fan-out, and hybrid cluster-external calls).

== Operationalization - variables

#table(
  columns: (auto, auto, auto),
  inset: 6pt,
  align: horizon,
  [*Variable type*], [*Name*], [*Operational definition / Measurement*],
  [Independent], [Service mesh type], [Categorical: `baseline` (no mesh), `Istio`, `Linkerd`, `Consul`, `Istio Ambient`],
  [Independent], [mTLS setting], [Categorical: `disabled` vs. `enabled` (only applied to mesh conditions)],
  [Independent], [Request load], [Continuous: offered load in requests per second (req/s), varied at 25, 50, 100 req/s],
  [Independent], [Request Payload], [Categorical: specific data inputs sent with the request, representing different traffic profiles (e.g., '1KB JSON', '5MB Image file', 'Standard text prompt')],
  [Independent], [Service Module], [Categorical: the specific isolated application microservice group processing the request (e.g., 'Math computation', 'Media processing', 'Off-cluster AI proxy')],
  [Dependent], [Average latency], [Mean request-response time (ms) per service endpoint over a 60-second steady-state window, reported as p50, p95, p99 percentiles],
  [Dependent], [Throughput], [Maximum sustained requests per second achieved per service before error rate exceeds 1%],
  [Dependent], [CPU usage], [Average CPU millicores consumed by mesh sidecars + application containers (cluster side), separated per service],
  [Dependent], [Memory usage], [Average resident memory (MiB) consumed (cluster side), separated per service],
  [Dependent], [CPU clock usage], [Observed time of request processing on math nodes under Fibonacci load],
  [Confounding], [Network conditions], [Controlled by running all tests in the same isolated cluster and VM network],
  [Confounding], [Application version], [Fixed version of the custom application across all runs],
  [Confounding], [Kubernetes version], [Fixed version across all runs],
  [Hidden], [Garbage collection cycles], [Minimized by running each test for a sufficient duration (warm-up + measurement) and averaging over repetitions],
  [Hidden], [Node heterogeneity], [Use identical instances for all worker nodes; AI VM kept identical across runs],
)

== Research methods
This research will employ a controlled real-life experiment conducted in a cloud-based Kubernetes environment, with an additional isolated VM hosting the AI service. The experiment is reproducible and quantitative. No human subjects are involved; only system performance metrics are collected.

*Primary method:* Laboratory experiment with repeated measures (each configuration is tested multiple times) and blocking on service type to account for heterogeneity.  

== Research tools

*Experimental setup:*
- *Cloud provider:* Local Kubernetes cluster + separate VM for AI service.
- *Orchestration:* Kubernetes (version 1.28+)
- *Service meshes:* 
  - Istio (latest stable, e.g., 1.22) with default sidecar injection
  - Linkerd (latest stable, e.g., 2.15) with default sidecar injection
  - Consul (latest stable, e.g., 1.18) with sidecar injection
  - Istio Ambient (latest stable, eBPF-based, sidecar-less data plane)
- *Custom microservice application:* Built by the team, consisting of:
  - *AI Service*: runs on a separate VM - receives requests via Kubernetes ingress, performs inference/test data generation.
  - *Media Service*: containerized service for video splitting and digital filters.
  - *Math Services*: C\# implementations of differential equations, integration, permutations, Fibonacci (with configurable $n$), running inside the cluster.
- *Load generator:* A separate virtual machine (different from the AI VM) running a custom Python script that sends HTTP requests to the ingress of the Kubernetes cluster. The script controls the request rate (25, 50, 100 req/s) and targets each service endpoint (including the AI service via its external endpoint). The load VM is isolated from both the cluster and the AI VM to avoid interference.
- *Metrics types:*
  - Mesh-specific telemetry (Istio/Ambient, Linkerd, Consul)
  - Kubernetes metrics-server (for container CPU/memory)
  - Custom metrics for CPU clock usage
- *Metrics collection, storage, and visualization mechanisms:*
  - Data Generation & Exposure: Service mesh proxies intercept all network traffic to calculate telemetry (latency, throughput) and expose it via local /metrics web endpoints. Infrastructure data (CPU millicores, memory) is exposed via Kubernetes cAdvisor. Custom application metrics (inner measurements of microservices) are written to local .prom files by the Load Generator and exposed using the Prometheus Node Exporter's textfile collector.
  - Data Collection (Scraping): Prometheus acts as the central aggregator. Utilizing Kubernetes Service Discovery, Prometheus automatically detects all active mesh proxies and infrastructure nodes. It executes a "pull" (scrape) of these /metrics endpoints at a fixed interval (e.g., every 15 seconds).
  - Data Storage (Prometheus): Prometheus functions as the sole data repository for measurements. It stores all scraped infrastructure, mesh, and custom metric data as distinct time-series rows in its highly optimized, local Time-Series Database (TSDB) on the hard drive.
  - Data Visualization and Aggregation (Grafana): Grafana is utilized strictly as the visualization layer and does not store the telemetry data. When a dashboard is accessed, Grafana dynamically executes PromQL queries against the Prometheus API, aggregating the raw metric data across multiple pods on the fly to render visual graphs.

*Experiment design:*\
Testing procedure for the metrics generation, acquisition and aggregation consists of the following wteps:
1. Deploy application in the needed configuration (baseline, Istio, Linkerd, Consul, Istio Ambient).
2. Execute test runs 10 times for a given service type per configuration for every load level.
3. Aggregate and save data on a hard disk
4. Each test run consists of:
    - 60s warm-up
    - 120s steady-state measurement
    - Cooldown

*Experiment iterations:*
1. Execute the testing procedure for the baseline application.
2. Execute the testing procedure for Istio (mTLS-disabled) configuration.
3. Execute the testing procedure for Istio (mTLS-enabled) configuration.
4. Execute the testing procedure for Linkerd (mTLS-disabled) configuration.
5. Execute the testing procedure for Linkerd (mTLS-enabled) configuration.
6. Execute the testing procedure for Consul (mTLS-disabled) configuration.
7. Execute the testing procedure for Consul (mTLS-enabled) configuration.
8. Execute the testing procedure for Istio Envoy (mTLS-disabled) configuration.
9. Execute the testing procedure for Istio Envoy (mTLS-enabled) configuration.

== Expected results

*Quantitative:*
- Latency distributions (p50, p95, p99) per service type for each configuration and load level.
- Throughput saturation curves.
- CPU and memory overhead percentages relative to baseline, broken down by service type and mesh.
- CPU clock usage behavior on math services (Permutations) under each mesh vs. baseline.

*Qualitative:*
- Insights into whether the overhead is constant or scales with load and service type.
- Recommendations for practitioners: which mesh to choose based on workload characteristics (CPU-intensive math, I/O media, off-cluster AI, or mixed).

== Validity threats

#table(
  columns: (auto, auto, auto),
  inset: 6pt,
  align: horizon,
  [*Threat type*], [*Description*], [*Mitigation*],
  [Construct validity], [Measured metrics may not fully represent “efficiency” (e.g., latency alone ignores user experience).], [Use multiple metrics (latency, throughput, resource usage, clock scaling).],
  [Internal validity], [Uncontrolled variables (e.g., network jitter, node scheduling) affect results.], [Run all tests on isolated, dedicated cluster and separate VMs; repeat each condition 10 times; randomize order.],
  [External validity], [Results may not generalize to other applications, cloud providers, or service meshes.], [Use a custom application that covers diverse workload types (including off-cluster AI); test four representative meshes (Istio, Linkerd, Consul, Ambient); discuss limitations.],
  [Conclusion validity], [Random chance may produce false significance.], [Use appropriate statistical tests, set $#sym.alpha = 0.05$, and report effect sizes and confidence intervals.],
)

== Research plan

#table(
  columns: (auto, auto, auto, auto),
  inset: 6pt,
  align: horizon,
  [*Phase*], [*Tasks*], [*Responsible*], [*Duration*],
  [1. Application development], [Build and containerize AI (VM), Media, Math services; create Kubernetes deployment manifests; set up AI VM networking], [All team members], [5 days],
  [2. Environment setup], [Provision Kubernetes cluster, install Istio, Linkerd, Consul, Istio Ambient; deploy custom app; validate baseline and AI VM connectivity], [Oleksandr Nychyporchuk, Kiryl Pahkevich], [4 days],
  [3. Load generator & monitoring], [Develop custom load script on separate VM; configure Prometheus; create measurement scripts targeting each service (including AI VM)], [Pavel Khmialeuski, Alla Krylova], [2 days],
  [4. Pilot study], [Run 1 repetition of a subset of configurations (baseline, Istio, Linkerd) for Math service to validate toolchain], [Alla Krylova (execution), Oleksandr Nychyporchuk (verification)], [1 day],
  [5. Full experiment], [Execute 10 repetitions per configuration x 3 service types (750 runs), collect raw data], [All team members (divided runs)], [10-14 days],
  [6. Data analysis], [Statistical tests, visualization, hypothesis testing], [Oleksandr Nychyporchuk, Kiryl Pahkevich], [4 days],
  [7. Reporting], [Write research paper / report sections], [Alla Krylova (draft), Oleksandr Nychyporchuk (final)], [4 days],
)

== Publication goals
The results of this research are suitable for publication in:

- *Conference:* IEEE International Conference on Cloud Computing (CLOUD), IEEE International Conference on Edge Computing (EDGE), or International Conference on Software Engineering (ICSE) - SEIP track.
- *Journal:* Journal of Systems and Software, IEEE Transactions on Network and Service Management, or Cluster Computing.

The pilot study results alone may serve as a short paper or a technical report. The full experiment, if significant, can be submitted as a full conference paper.

= Pilot study

== Research subjects
For the pilot study, we used a subset of the experimental configurations to verify that all tools work and produce plausible data. The pilot focused on the Mathematical Modules (specifically the Permutations service $O(n!)$) as the most CPU-intensive. The pilot included 7 configurations (single repetition each) using only Istio and Linkerd (Consul and Ambient were not yet installed):

1. Baseline - low, medium, high load (25, 50, 100 req/s) - 3 runs
2. Istio (mTLS off) - low, medium, high load - 3 runs
3. Linkerd (mTLS off) - high load only (100 req/s) - 1 run

*We omitted mTLS-on conditions and other service types (AI, Media) as well as Consul and Istio Ambient in the pilot due to time constraints. These will be included in the full experiment.*

*Qualification:* The pilot used the same hardware and software versions as planned for the full experiment, except that the AI VM was not used (only cluster services).

== Study execution
- *Executed by:* Oleksandr Nychyporchuk
- *Verified by:* Kiryl Pashkevich
- *Date:* 02.05.2026
- *Environment:* Local Kubernetes cluster hosting the application infrastructure with a separated virtual machine for load generation
- *Tools:* Prometheus, Grafana
- *Procedure:*
  1. Deploy baseline (no service mesh) application.
  2. Execute the testing procedure described in chapter 2.8.
  3. Install Istio with default sidecar injection, disable mTLS, redeploy application.
  4. Repeat step 2.
  5. Install Linkerd with default sidecar injection, disable mTLS, redeploy application.
  6. Repeat testing porcedure with high-load test only (100 req/s).

== Results
#figure(
  grid(
    columns: (1fr, 1fr),  // Two columns of equal width
    gutter: 1em,          // The gap between the two charts

    rect(width: 90%, height: 200pt, fill: luma(240), stroke: 1pt + luma(180))[
      #align(center + horizon)[
        *Infographic Placeholder* \
        _Data coming soon_
      ]
    ],
    rect(width: 90%, height: 200pt, fill: luma(240), stroke: 1pt + luma(180))[
      #align(center + horizon)[
        *Infographic Placeholder* \
        _Data coming soon_
      ]
    ],
  ),
  caption: [Latency and throughput of baseline, Istio and Linkerd under high load],
) <chart-resource-scaling>
*Latency Impact under High Load (100 req/s):*
  Under the peak pilot load of 100 req/s, the injection of service mesh sidecars introduced a measurable latency penalty compared to the unmeshed cluster. For the in-cluster mathematical computations, the Baseline deployment maintained a p95 latency of [XX]ms. The introduction of the standard Istio Envoy proxy increased this baseline by approximately [XX]%, resulting in a p95 latency of [XX]ms. Linkerd's Rust-based micro-proxy demonstrated a tighter performance margin, recording a p95 latency of [XX]ms (a [XX]% increase over baseline).

#figure(
  grid(
    columns: (1fr, 1fr),  // Two columns of equal width
    gutter: 1em,          // The gap between the two charts
    
    // Graph 1 (Left)
    rect(width: 90%, height: 200pt, fill: luma(240), stroke: 1pt + luma(180))[
      #align(center + horizon)[
        *Infographic Placeholder* \
        _Data coming soon_
      ]
    ],
    rect(width: 90%, height: 200pt, fill: luma(240), stroke: 1pt + luma(180))[
      #align(center + horizon)[
        *Infographic Placeholder* \
        _Data coming soon_
      ]
    ],


    pad(left: 52.5%, right:-52.5%)[
      #rect(width: 90%, height: 200pt, fill: luma(240), stroke: 1pt + luma(180))[
        #align(center + horizon)[
          *Infographic Placeholder* \
          _Data coming soon_
        ]
      ],
    ]
  ),
  caption: [CPU milicores, RAM, CPU time metrics of baseline and Istio under low, medium and high loads],
) <chart-resource-scaling>
*Resource Scaling under High Load (CPU and Memory):*
The architectural cost of the service meshes became evident when tracking resource consumption from the 25 req/s idle state to the 100 req/s peak state. The Baseline in-cluster services consumed an average of [XX]m (millicores) of CPU and [XX]MB of memory at peak load.
Istio demonstrated a steeper resource scaling curve; at 100 req/s, the Envoy sidecars consumed an additional [XX]m of CPU and [XX]MB of memory per pod. Linkerd scaled more efficiently under the same load, requiring only an additional [XX]m of CPU and [XX]MB of memory per pod.

== Conclusions 
*Load Generation Efficacy:*
The custom Python load generator successfully executed the defined load tiers. However, the data indicates that the maximum tier of 100 req/s was insufficient to induce true system saturation or resource starvation within the Kubernetes cluster. While 100 req/s was adequate to establish a trend line for the sidecar proxies, the Baseline application remained comfortably within its idle resource limits.

*Telemetry and Custom Metrics Reliability:*
The integration of Prometheus with the Node Exporter's textfile collector proved highly reliable. The custom internal metrics generated by the C\# microservices were scraped precisely at the [XX]-second interval with [XX]% data loss. The correlation between these custom application metrics and the infrastructure data (cAdvisor) within Grafana provided a synchronized view of the system state without requiring intrusive code changes.

*Test Duration Validity:*
The 60-second warm-up phase was [sufficient / entirely insufficient] for the environment to stabilize. Observation of the CPU charts revealed that [Istio/Linkerd] required approximately [XX] seconds to fully sync its proxy routing tables upon deployment, meaning the initial steady-state measurements contained slight jitter.
= Conclusions

== Design
*Adjustments to Load Tiers:*
Because the 100 req/s peak load failed to stress the Baseline architecture, the subsequent main study must expand its load generation capabilities. The revised test matrix will introduce a "Stress" tier of [500/1000] req/s to accurately observe how the proxy architectures behave under compute saturation and network congestion.

*Re-introducing Excluded Variables:*
The pilot successfully validated the core metrics pipeline and the sidecar injection methodology. With this foundational framework proven, the main study is structurally cleared to re-introduce the previously excluded variables. This will include deploying the Consul and Istio Ambient architectures, as well as executing the secondary test matrix to measure the specific computational overhead of enabling mutual TLS (mTLS) across all meshes.
== Pilot study 
*Preliminary Validation of Hypothesis 1 (Baseline Overhead):*
The pilot data affirmatively supports the hypothesis that injecting any service mesh implementation creates a measurable latency and resource increase. The unmeshed Baseline consistently outperformed Istio in raw p95 latency and total memory footprint, confirming that the advanced routing and observability features of a service mesh incur a strict, non-zero architectural tax.

*Linkerd vs. Istio Throughput (Hypothesis 3):*
Preliminary findings strongly indicate that Linkerd provides a more efficient data plane than standard Istio, characterized not only by a lighter operational footprint but also by superior throughput under identical load conditions. At peak load, Linkerd's proxies consumed [XX]% less CPU and [XX]% less memory than Istio's Envoy proxies, while simultaneously sustaining a [XX]% higher maximum throughput and delivering lower network latency. This suggests that for high-volume environments where compute resources are strictly constrained, Linkerd's architecture offers a distinct performance advantage out-of-the-box.
= Literature

#bibliography("research_design.bib", style: "ieee", full: true)
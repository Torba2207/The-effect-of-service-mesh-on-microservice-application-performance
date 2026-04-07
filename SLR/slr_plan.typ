#set page(paper: "a4", margin: 1in)
#set text(size: 11pt)
#set heading(numbering: "1.1")

#align(center)[
  #text(size: 17pt, weight: "bold")[Systematic Literature Review Report]
]

#align(center)[
  Alla Krylova 196722 \
  Oleksandr Nychyporchuk 196659 \
  Kiryl Pashkevich 196687 \
  Pavel Khmialeuski 197055
]
#v(1em)

= Research project

== Title
The impact of service-mesh solutions on the efficiency of microservice applications

== Supervisor
Krzysztof Gierłowski (KTI)

== Goals and short description
Currently, a significant portion of applications deployed in cloud environments utilize microservices architecture. This type of architecture requires decomposing application functionality into component elements, implemented by individual microservices, and then deploying them in an environment that allows the microservices to communicate efficiently and reliably. This task is most often accomplished by orchestration platforms such as Kubernetes. Maintaining the separation and security of applications sharing the same deployment platform is also a key aspect of this type of deployment. Service mesh solutions are often used for this purpose, as they can automatically create secure communication environments for specific applications.

The aim of this project is to analyze and experimentally test the impact of using service mesh solutions on the efficiency (and particularly performance) of an application composed of multiple microservices.

= Systemic Literature Review plan

== Goals and questions:
The goal of this systematic literature review is to identify, categorize, and synthesize existing research on service mesh technologies in the context of microservices applications, with a particular focus on comparing environments with and without service mesh in terms of performance implications, security benefits, and deployment trade-offs.

+ What are the main service mesh implementations used in production microservice systems?
+ What performance metrics (latency, throughput, resource consumption) are most often evaluated when comparing service mesh vs. no service mesh deployments?
+ What security mechanisms (mTLS, authorization, policies) do service meshes provide, and what is their performance overhead compared to native Kubernetes security?
+ What architectural deployment patterns and migration strategies are described for adopting service mesh in existing microservice applications?
+ How do monitoring and observability capabilities differ between service mesh and non-service mesh environments?

== Keywords:
+ Core concept: "service mesh", "service meshes"
+ Comparison focus: "without service mesh", "standard Kubernetes", baseline, "vs native"
+ Specific implementations: Istio, Linkerd, Consul
+ Related technologies: "microservices architecture", "micro-service\*", "micro services", Kubernetes
+ Performance aspects: performance, latency, throughput, overhead, scalability, efficiency

== Search strings:
*Base search string:* \
("service mesh" OR "service meshes" OR istio OR linkerd OR consul OR kuma OR "aws app mesh" OR "open service mesh" OR osm OR cilium) \
AND (microservice\* OR "micro-service\*" OR "micro services" OR "microservices architecture" OR kubernetes) \
AND (performance OR latency OR throughput OR overhead OR scalability OR efficiency OR comparison OR "vs native" OR baseline OR "without service mesh" OR "standard kubernetes")

== Literature databases:
+ Scopus
+ SpringerLink
+ Arxiv
+ IEEE Xplore
+ ACM Digital Library

These 4 databases provide comprehensive coverage of technical literature in computer science, software engineering, and distributed systems, with minimal overlap and complementary strengths.

== Inclusion criteria:
+ Publication type: peer-reviewed journal articles and conference proceedings.
+ Language: English.
+ Years: 2017-2025 (Service Mesh has been actively developing since 2017, when Istio was released).
  Additionally, Linkerd 1 is an important topic. It is actually the first service mesh solution, but much more distanced from modern days concept of service mesh.
+ Availability: Full text available.

== Exclusion criteria:
+ Article length: Short articles (less than 4 pages)
+ Relevance: Articles that mention Service Mesh only in passing or as a secondary topic
+ Language: Articles not in English

== Quality criteria:
Each article will be assessed against the following criteria (scored 0 or 1 point per criterion). Articles must score at least 4 out of 7 points to proceed to data extraction.

+ Clarity of description: Is the architecture, experimental setup, or methodology clearly described?
+ Quantitative evaluation: Does the article provide quantitative performance measurements (latency, CPU, memory, throughput)?
+ Baseline comparison: Does the article compare service mesh performance against a non-service-mesh and/or compare different service mesh solutions baseline (native Kubernetes, no sidecar, etc.)?
+ Experimental rigor: Are testing conditions (workload, environment, hardware/software specifications) clearly described?
+ Statistical validation: Are results validated (statistical significance, confidence intervals, reproducibility)?
+ Security analysis: Does the article provide security analysis or vulnerability assessment?
+ Publication venue: Is the article published in a reputable venue?

== Data extraction:
The following data will be extracted from each selected article and recorded in a structured spreadsheet (Google Sheets).

+ Research context
  #set enum(numbering: "a)")
  + Service Mesh type: Specific implementations studied (Istio, Linkerd, Consul, etc.)
  + Baseline used: What "no service mesh" baseline was used? (Native Kubernetes, no sidecar, etc.)
  + Deployment context: Cloud, on-premise, hybrid, edge
  + Orchestration platform: Kubernetes, Nomad, etc.
  + Application type: Example application used (if any)
+ Methodology
  #set enum(numbering: "a)")
  + Research method: Experiment, case study, survey, review, simulation
  + Scale: Number of services, nodes, requests
  + Workload characteristics: Type of workload, request patterns
+ Performance metrics
  #set enum(numbering: "a)")
  + Latency: Measured values (mean, p95, p99)
  + Throughput: Requests per second, data transfer rate
  + CPU usage: Measured consumption
  + Memory usage: Measured consumption
  + Network overhead: Additional bytes transferred
+ Security aspects
  #set enum(numbering: "a)")
  + Security mechanisms: mTLS, RBAC, policies, authentication
  + Security impact: Performance cost of security features
+ Observability
  #set enum(numbering: "a)")
  + Monitoring tools: Prometheus, Grafana, Kiali, Jaeger, Zipkin
  + Observability features: Metrics, logs, traces, visualization
+ Results
  #set enum(numbering: "a)")
  + Key findings: Main conclusions of the study
  + Limitations: Stated limitations of the research
  + Future work: Suggested research directions

== SLR process:

#table(
  columns: (auto, auto, auto, auto, auto),
  inset: 6pt,
  align: horizon,
  [*Step*], [*Description*], [*Executor*], [*Verifier*], [*Tools*],
  [Step 1], [Database search execution], [Oleksandr Nychyporchuk], [Kiryl Pashkevich], [Scopus, ACM, Web of Science],
  [Step 2], [Export results and import to reference manager], [Oleksandr Nychyporchuk], [Pavel Khmialeuski], [Zotero/Mendeley],
  [Step 3], [Duplicate removal], [Alla Krylova], [Pavel Khmialeuski], [Zotero, Excel],
  [Step 4], [Title and abstract screening (Round 1)], [Alla Krylova, Pavel Khmialeuski], [Oleksandr Nychyporchuk, Kiryl Pashkevich], [Google Sheets],
  [Step 5], [Full-text retrieval], [Kiryl Pashkevich], [Alla Krylova], [University library access, DOI resolvers],
  [Step 6], [Full-text screening (Round 2) and quality assessment], [Kiryl Pashkevich, Oleksandr Nychyporchuk], [Alla Krylova, Pavel Khmialeuski], [Google Sheets, PDF readers],
  [Step 7], [Data extraction], [All team members (divided by articles)], [Oleksandr Nychyporchuk, Kiryl Pashkevich], [Google Sheets template],
  [Step 8], [Synthesis and reporting], [Kiryl Pashkevich], [Alla Krylova], [Google Docs, LaTeX]
)

= Systematic Literature Review results
== Results in numbers
Number of articles retrieved from databases (before deduplication):
- Scopus: 75
- SpringerLink: 5
- Arxiv: 28
- IEEE Xplore: 179
- ACM Digital Library: 35
== Articles selected for data extraction
The following list presents the 12 articles selected after verification and qualified for data extraction:

#set list(marker: "")
- @nagy_elastic_2026 "Elastic Scaling of Real-Time Communication Services"
- @dermentzis_trade-offs_2026 "Trade-Offs in Kubernetes Security and Energy Consumption"
- @yang_network_2024 "Network shortcut in data plane of service mesh with eBPF"
- @huang_evaluation_2023 "Evaluation of a Smart Intercom Microservice System Based on the Cloud of Things"
- @singh_resilient_2026 "Resilient microservices: an investigation into Istio effectiveness in Kubernetes"
- @barr_technical_2024 "Technical Report: Performance Comparison of Service Mesh Frameworks: the MTLS Test Case"
- @larsson_impact_2020 "Impact of etcd deployment on Kubernetes, Istio, and application performance"
- @ganguli_challenges_2021 "Challenges and Opportunities in Performance Benchmarking of Service Mesh for the Edge"
- @hahn_security_2020 "Security Issues and Challenges in Service Meshes – An Extended Study"
- @zeng_full-stack_2023 "Full-stack vulnerability analysis of the cloud-native platform"
- @bosquez_comparative_2025 "Comparative Evaluation of Linkerd and Istio Service Meshes in a Microservices Architecture Application" \
- @kurpad_microarchitectural_2023 "Microarchitectural Analysis and Characterization of Performance Overheads in Service Meshes with Kubernetes"

== Initial extracted data

#table(
  columns: (1fr, auto, auto),
  inset: 8pt,
  align: horizon,
  [*Main focus / Keywords*], [*Service Mesh*], [*Article*],

  // --- Article 1 ---
  [Edge computing, performance benchmarking, latency, throughput, Iptables overhead],
  [Istio (Envoy)],
  [@ganguli_challenges_2021],
  
  table.cell(colspan: 3)[
    *Title:* Challenges and Opportunities in Performance Benchmarking of Service Mesh for the Edge \
    *Summary:* This paper investigates the architectural complexities and performance impacts of deploying a service mesh in latency-sensitive edge environments. By benchmarking north-south and east-west communications, the authors identify significant bottlenecks in the Linux network stack. Specifically, they highlight that Linux's Iptables rule matching (used heavily by sidecar proxies) creates substantial CPU micro-architecture overhead at scale. This emphasizes the need for optimized data planes when deploying service meshes at the edge.
  ],

  // --- Article 2 ---
  [Chaos engineering, resilience, fault tolerance, response time, heavy load],
  [Istio],
  [@singh_resilient_2026],

  table.cell(colspan: 3)[
    *Title:* Resilient microservices: an investigation into Istio effectiveness in Kubernetes \
    *Summary:* This study evaluates the impact of the Istio service mesh on the resilience of Kubernetes clusters using chaos engineering principles (injecting failures into the system). Performance metrics such as response time, error rates, and resource usage were analyzed under increased load. The findings demonstrate that Istio significantly improves system stability, failure resilience, and recovery times compared to a traditional, non-mesh Kubernetes architecture.
  ],

  // --- Article 3 ---
  [mTLS overhead, latency, memory consumption, sidecar vs. sidecar-less],
  [Istio, Linkerd, Cilium],
  [@barr_technical_2024],

  table.cell(colspan: 3)[
    *Title:* Technical Report: Performance Comparison of Service Mesh Frameworks: the MTLS Test Case \
    *Summary:* Recognizing that security is a primary driver for service mesh adoption, this technical report thoroughly evaluates the performance overhead of mutual TLS (mTLS). It compares traditional sidecar architectures (Istio, Linkerd) with sidecar-less and eBPF-accelerated architectures (Istio Ambient, Cilium). The experiments reveal significant differences in latency and memory consumption, noting that while some meshes appear faster, the overhead is heavily dependent on the default security features and the underlying proxy architecture.
  ],

  // --- Article 4 ---
  [CPU consumption, RAM usage, latency, high-load stability, SEMMA methodology],
  [Istio, Linkerd],
  [@bosquez_comparative_2025],

  table.cell(colspan: 3)[
    *Title:* Comparative Evaluation of Linkerd and Istio Service Meshes in a Microservices Architecture Application \
    *Summary:* This paper conducts a direct, objective comparison between Istio and Linkerd using the Online Boutique microservices application under low, medium, and high load scenarios. Experimental results showed that Linkerd significantly outperformed Istio in efficiency, maintaining lower average latency (104 ms vs. 135 ms), consuming less CPU and RAM, and recording zero errors under high load. Conversely, Istio exhibited consumption peaks and internal failures under stress, though the authors note it remains preferable for environments requiring highly advanced control features.
  ]
)
== Article statistics

To understand the research landscape surrounding service mesh performance in microservice architectures, a quantitative analysis was performed on the search results.

=== Initial Search Distribution
The initial database queries returned a total of 322 articles before deduplication. As shown in @fig:db_counts, IEEE Xplore (179 articles) and Scopus (75 articles) provided the vast majority of the results. This reflects the topic's strong roots in applied computer science, network engineering, and distributed systems. arXiv (28 articles) and SpringerLink (5 articles) yielded fewer direct matches based on our highly specific search strings.

#figure(
  image("database_counts_pre_dedup.png", width: 80%),
  caption: [Number of articles retrieved per database before deduplication.]
) <fig:db_counts>

=== Publication Trends Over Time
After removing duplicates and cleaning the dataset, the temporal distribution of the unique articles was analyzed (@fig:pub_years). The data indicates that while modern service meshes (like Istio) were introduced around 2017, rigorous academic research and performance benchmarking began to gain significant traction from 2020 onward. The steady volume of recent publications demonstrates that service mesh efficiency, security overhead, and edge deployment are currently highly active and maturing research areas.

#figure(
  image("publications_by_year.png", width: 80%),
  caption: [Distribution of unique publications by year.]
) <fig:pub_years>

=== Top Publication Sources
An analysis of the publication venues (@fig:top_sources) reveals that a significant portion of research in this domain is published across IEEE conferences and specialized computer networks journals.

#figure(
  image("top_sources.png", width: 85%),
  caption: [Top 10 publication sources for the filtered articles.]
) <fig:top_sources>
= Conclusions

== SLR process
Conducting this systematic literature review revealed that while "service mesh" is a highly popular industry topic, rigorous academic benchmarking remains relatively niche. The initial search across IEEE Xplore, Scopus, arXiv, and SpringerLink yielded 287 articles. A major challenge during the screening process was the prevalence of general cloud-computing or microservices papers that only mentioned service meshes in passing without providing quantitative evaluations. Consequently, careful manual screening was required to isolate the final 12 articles that actually provided empirical performance data. The process demonstrated the necessity of highly specific search strings and strict quality criteria to filter out industry buzzwords and focus on true architectural benchmarking.

== SLR results
Based on the initial data extracted from the core publications, several distinct themes have emerged regarding the impact of service mesh solutions on microservice efficiency:
#set enum(numbering: "1.")
+ *The Cost of Security (mTLS) and Sidecar Proxies:* Deploying a traditional sidecar architecture introduces measurable latency and memory/CPU overhead @barr_technical_2024. This is largely driven by the cryptographic costs of mutual TLS and the underlying Linux network stack (e.g., Iptables rule matching), which becomes a significant bottleneck, particularly in latency-sensitive edge computing environments @ganguli_challenges_2021.
+ *Linkerd vs. Istio Performance:* Direct experimental comparisons highlight that Linkerd generally offers a lighter footprint with lower average latency (e.g., 104 ms vs. 135 ms) and better stability under high load compared to Istio @bosquez_comparative_2025. However, Istio remains the standard for environments requiring highly complex traffic routing and granular observability configurations.
+ *Architectural Evolution (eBPF and Sidecar-less):* To mitigate sidecar overheads, the research landscape is shifting toward kernel-level optimizations. Newer architectures utilizing eBPF are showing immense promise in drastically reducing network latency while maintaining robust security and observability, effectively bypassing traditional proxy bottlenecks @yang_network_2024 @barr_technical_2024.
+ *Trade-offs Between Efficiency and Resilience:* While service meshes impose a performance penalty, they significantly enhance system stability @singh_resilient_2026. Studies utilizing chaos engineering indicate that environments equipped with Istio recover faster and handle failure injections much more gracefully than native Kubernetes deployments, proving that the performance trade-off is often justified by massive gains in fault tolerance @dermentzis_trade-offs_2026 @larsson_impact_2020.

These findings directly validate the necessity of our research project. The literature confirms that service mesh performance overhead is highly contextual, reinforcing our goal to experimentally test these solutions in a controlled environment to find the optimal balance between security, observability, and efficiency.
= Literature
#bibliography("SLR_bib.bib", style: "ieee", full: true)
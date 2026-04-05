#set page(paper: "a4", margin: 1in)
#set text(font: "Linux Libertine", size: 11pt)
#set heading(numbering: "1.1")

#align(center)[
  #text(size: 17pt, weight: "bold")[Systemic Literature Review Report]
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
Krzysztof Gierłowski (KT)

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

+ Article metadata:
  #enum(numbering: "a)")[Article ID: Unique identifier][Authors: Full list of authors][Year: Publication year][Title: Full article title][Source: Journal/conference name][DOI: Digital Object Identifier]
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
  [Step 7], [Snowballing (forward and backward)], [Pavel Khmialeuski], [Alla Krylova], [Google Scholar, reference lists],
  [Step 8], [Data extraction], [All team members (divided by articles)], [Oleksandr Nychyporchuk, Kiryl Pashkevich], [Google Sheets template],
  [Step 9], [Synthesis and reporting], [Kiryl Pashkevich], [Alla Krylova], [Google Docs, LaTeX]
)

= Systematic Literature Review results
== Results in numbers
Number of articles retrieved from databases (before deduplication):
- Scopus: 75
- SpringerLink: 12
- Arxiv: 30
- IEEE Xplore: 179
== Articles selected for data extraction
The following list presents the 8 articles selected after verification and qualified for data extraction:

#set enum(numbering: "[1]")
+ ("Elastic Scaling of Real-Time Communication Services")
+ ("Trade-Offs in Kubernetes Security and Energy Consumption")
+ ("Network shortcut in data plane of service mesh with eBPF")
+ ("Evaluation of a Smart Intercom Microservice System Based on the Cloud of Things")
+ ("Resilient microservices: an investigation into Istio effectiveness in Kubernetes")
+ ("Technical Report: Performance Comparison of Service Mesh Frameworks: the MTLS Test Case")
+ ("Impact of etcd deployment on Kubernetes, Istio, and application performance")
+ ("Challenges and Opportunities in Performance Benchmarking of Service Mesh for the Edge")
== Initial extacted data
== Article statistics
= Conclusions

== SLR process
The systematic literature review process revealed that defining the correct scope of search queries was a significant challenge. The main obstacle was the massive volume of general publications regarding cloud computing, Kubernetes, and microservices that only briefly mentioned service meshes without providing quantitative evaluations. This required rigorous manual filtering of abstracts and full texts to focus strictly on studies that practically evaluated the performance, efficiency, and security overhead of service mesh deployments (such as Istio or Linkerd).

== SLR results
The results of the literature review for the 8 selected publications indicate that research on service mesh efficiency in microservice environments is currently focused on three practical directions:

+ *Performance Benchmarking and Overhead Analysis* -- extensive evaluation of the latency, CPU, and memory overhead introduced by service mesh components (specifically proxy sidecars and mTLS encryption), particularly in latency-sensitive, edge, or high-load environments [6], [8].
+ *Architectural Optimizations (e.g., eBPF)* -- a growing trend toward mitigating performance penalties by optimizing the data plane. Researchers are increasingly exploring kernel-level technologies like eBPF to create network shortcuts and bypass traditional sidecar bottlenecks [3], [6].
+ *Trade-offs Between Security, Resilience, and Efficiency* -- analyzing how the implementation of advanced service mesh features (such as mutual TLS, traffic routing, and chaotic testing) impacts overall system stability, energy consumption, and underlying infrastructure like `etcd` [2], [5], [7].

Simultaneously, the literature confirms that while service meshes provide essential security and observability abstractions, their performance cost is highly dependent on the architecture and configuration. This conclusion directly reinforces the primary goal of our project: to experimentally test and quantify these efficiency trade-offs in a real-world microservices deployment.
= Literature
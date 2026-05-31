#set page(paper: "a4", margin: 1in)
#set text(size: 11pt)
#set heading(numbering: "1.1.")

#align(center)[
  #text(size: 17pt, weight: "bold")[Article Review]
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
Currently, a significant portion of applications deployed in cloud environments utilize microservices architecture. This type of architecture requires decomposing application functionality into component elements, implemented by individual microservices, and then deploying them in an environment that allows the microservices to communicate efficiently and reliably. This task is most often accomplished by orchestration platforms such as Kubernetes. Maintaining the separation and security of applications sharing the same deployment platform is also a key aspect of this type of deployment. Service mesh solutions are often used for this purpose, as they can automatically create secure communication environments for specific applications. The aim of this project is to analyze and experimentally test the impact of using service mesh solutions on the efficiency (and particularly performance) of an application composed of multiple microservices.

= Research article review

== Title
Comparative Evaluation of Linkerd and Istio Service Meshes in a Microservices Architecture Application.

== Authors
Kevin Bosquez, Ximena Caiza, Lucía Núñez and Joffre Monar.

== Reference
2025 IEEE Colombian Caribbean Conference (C3), Santa Marta, Colombia, 2025, pp. 1-6, doi: 10.1109/C366505.2025.11340184.

#outline(
  title: [Contents]
)

== Positioning of each element of research design and execution
#table(
  columns: (auto, auto),
  inset: 6pt,
  align: horizon,
  [*Chapter*], [*What's included*],
  [Abstract], [Summarizes the overarching *research goal* to compare Linkerd and Istio, addressing the *research gap* regarding a lack of practical performance evidence. It briefly outlines the *research methodology* and *experiment structure*, including generalized results at the end of the chapter.],
  [I. Introduction], [Provides the context needed for sufficient understanding of the following chapters. Defines the general *research goal* of comparing Istio and Linkerd, and poses the main *research question* regarding latency and RAM usage. It also identifies the *research gap* concerning the lack of practical comparative evidence and introduces the mixed research methods (PRISMA, DSR, SEMMA).],
  [II. Background], [Elaborates on the *research gap* (Sections C and D) by explaining the current problem of lacking objective performance data under realistic load conditions. It reviews existing literature (Section E) to contextualize the study and justify the need for empirical testing.],
  [III. Methodology], [Details the *research methods* and *research plan* through the DSR framework and SEMMA phases. Here the research subject is clearly defined (Online Boutique application), and *research tools* (metrics-server, Kubernetes) and the operationalization of *dependent variables* (measuring CPU, RAM, and latency under controlled loads) are clearly described.],
  [IV. Results], [Presents the quantitative data gathered from the real-life experiments across low, medium, and high load scenarios. Here are reported in detail the measurements for the operationalized *dependent variables* (new variable mentioned - errors during test execution).],
  [V. Discussion], [Interprets the *experimental findings* and cross-references them with existing literature to address the overall *research goal*. It clearly contrasts the resource efficiency of Linkerd against the complex, feature-rich nature of Istio to establish optimal application contexts.],
  [VI. Conclusions], [Provides a final summary that answers the primary *research questions* based on the empirical evidence gathered. It highlights the definitive advantages of each service mesh and proposes avenues for future study.],
  [Acknowledgement], [Recognizes the institutional support, acknowledges the backing necessary to successfully conduct this research.],
  [References], [Lists the bibliographic references utilized to establish the theoretical framework and conduct the *systematic literature review* (PRISMA). These scholarly sources form the basis for identifying the initial *research gap*.]
)

== Strengths
- Employs a comprehensive mixed-method framework, combining systematic literature review with structured experimental design.
- Evaluates performance against internationally recognized software quality standards (ISO/IEC 25010).
- Utilizes a standardized, recognizable reference application (Online Boutique) for its load testing.
- Includes a well-defined abstract with a sufficiently detailed description of the research goal, research gap and research conclusions.

== Weaknesses
Despite its structured approach, the execution and reporting of the experiments contain significant methodological flaws:
- *Inconsistent Test Parameters:* The duration of the load tests is inconsistent (15 minutes for medium load vs. 30 minutes for high load), introducing an uncontrolled variable that complicates direct comparisons.
- *Ambiguous Scenarios:* The "Low Load" scenario is poorly defined; the authors do not specify the number of concurrent users (unlike the explicit 150 and 300 users in subsequent tests), nor do they clarify if this represents an "idle" state.
- *Asymmetric Analysis:* The authors provide a detailed, microservice-level breakdown of resource consumption for `istio-proxy`, but fail to provide a comparable analysis for Linkerd's proxy, resulting in an unbalanced comparison.
- *Omission of Time-Series Data:* The results rely entirely on aggregated averages and histograms. The absence of time-series graphs obscures transient resource spikes, stabilization periods, and dynamic behavior during the tests.
- *Unreported Test Iterations:* The paper does not state how many times the load tests were executed, making it impossible to determine the statistical significance or variance of the reported averages.
- *Inconsistent Data Presentation:* Table IV (Medium load) omits the "Errors" metric entirely, despite it being tracked in the low and high load tables. Furthermore, while "No mesh" baseline data is plotted in the histograms, it is inexplicably excluded from the comparative tables, limiting the reader's ability to assess absolute overhead.
- *Hardware Bottlenecks:* The testing infrastructure reached up to 90% CPU utilization during high-load tests with Istio, suggesting that hardware constraints, rather than the software alone, may have skewed the latency and error rate metrics.
- *Fragmented Variable Operationalization:* The document lacks a centralized section that explicitly defines and aggregates all independent, dependent, confounding, and hidden variables. This scattershot approach forces the reader to piece together the experimental parameters, reducing the overall clarity of the research design.
- *Omission of Key Methodological Elements:* The study skips critical structural components of a rigorous formal experiment, specifically the formulation of falsifiable research hypotheses and a dedicated analysis of validity threats. Without identifying construct, internal, and conclusion validity threats (and how to mitigate them), the study's methodological rigor is significantly weakened.
- *Unquantified Overhead of Advanced Features:* Although the authors repeatedly use Istio's robust feature set to justify its higher resource consumption, they do not explicitly test or measure the performance cost of these specific capabilities. As a result, the analysis is incomplete, leaving potential implementers without the empirical data needed to decide if those advanced features are worth the computational overhead.
- *Ambiguous Hardware Configuration:* The study provides only minimum hardware requirements instead of the precise specifications used in the test environment. This omission creates a significant obstacle for independent researchers attempting to replicate the experiment and accurately compare future performance results.


== Evaluation
While the paper addresses an important practical problem, its execution suffers from severe methodological inconsistencies. The failure to standardize test durations, the asymmetric breakdown of proxy resource consumption, and the reliance on opaque averages without time-series data or stated iteration counts severely undermine the reliability of the conclusions. It serves as a useful preliminary indicator of Linkerd's lightweight nature, but the data lacks the rigor required for definitive architectural decision-making.

= Conclusions

== Article review
Critiquing this article provided highly relevant lessons for executing performance benchmarks on distributed architectures. It highlighted critical pitfalls to avoid in our own research: test parameters (like duration and user count) must be strictly controlled across all scenarios, baselines must be consistently reported, and time-series data is essential to capture the true behavior of service meshes under load, rather than relying solely on potentially misleading averages.

== Final course conclusions


= Literature
+ K. Bosquez, X. Caiza, L. Núñez and J. Monar, "Comparative Evaluation of Linkerd and Istio Service Meshes in a Microservices Architecture Application," 2025 IEEE Colombian Caribbean Conference (C3), Santa Marta, Colombia, 2025, pp. 1-6, doi: 10.1109/C366505.2025.11340184.
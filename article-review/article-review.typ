#set page(paper: "a4", margin: 1in)
#set text(size: 11pt)
#set heading(numbering: "1.1")

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
Currently, a significant portion of applications deployed in cloud environments utilize microservices architecture. [cite: 362] This type of architecture requires decomposing application functionality into component elements, implemented by individual microservices, and then deploying them in an environment that allows the microservices to communicate efficiently and reliably. [cite: 363] This task is most often accomplished by orchestration platforms such as Kubernetes. [cite: 364] Maintaining the separation and security of applications sharing the same deployment platform is also a key aspect of this type of deployment. [cite: 365] Service mesh solutions are often used for this purpose, as they can automatically create secure communication environments for specific applications. [cite: 366] The aim of this project is to analyze and experimentally test the impact of using service mesh solutions on the efficiency (and particularly performance) of an application composed of multiple microservices.

= Research article review

== Title
Comparative Evaluation of Linkerd and Istio Service Meshes in a Microservices Architecture Application.

== Authors
Kevin Bosquez, Joffre Monar, Ximena Caiza, and Lucía Núñez.

== Reference
2025 IEEE Colombian Caribbean Conference (C3).

#outline(
  title: [Table of Contents]
)

== Positioning of each element of research design and execution
- *Research problem & objectives:* Mapped in Introduction and Background.
- *Methodological framework:* Mapped in Section III (PRISMA, SEMMA, and DSR frameworks used).
- *Execution & metrics:* Mapped in Section IV (Kubernetes setup, CPU/RAM/latency data collection).
- *Missing elements:* No explicit "Threats to Validity" or limitations section (which is typically standard for Design Science Research).

== Strengths
- Methodologically robust, successfully combining PRISMA literature review with DSR and SEMMA.
- Grounded in international software quality standards (ISO/IEC 25010).
- Employs progressive and realistic load testing (low, medium, high concurrent users) using the Online Boutique reference application.

== Weaknesses
- Scope of metrics is highly restricted, analyzing only CPU, RAM, and latency.
- Tests rely on a single reference application, which limits how well findings generalize to other microservice architectures.

== Evaluation
A highly effective empirical paper. It directly addresses the lack of objective evidence regarding Istio and Linkerd's operational efficiency, making it a valuable reference for environments requiring high demand or operating under resource constraints.

= Conclusions

== Article design or review
The paper's mixed-method approach—specifically using SEMMA to structure the collection of metrics in a Kubernetes cluster—is an excellent methodological template that can be directly adapted for our own service mesh performance research.

== Final course conclusions


= Literature
+ Bosquez, K., Monar, J., Caiza, X., & Núñez, L. (2025). Comparative Evaluation of Linkerd and Istio Service Meshes in a Microservices Architecture Application. *2025 IEEE Colombian Caribbean Conference (C3)*. DOI: 10.1109/C366505.2025.11340184.
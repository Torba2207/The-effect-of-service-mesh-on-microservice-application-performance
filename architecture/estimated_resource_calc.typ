#set page(paper: "a4", margin: 2cm)
#set text(font: "Linux Libertine", size: 11pt)
#set heading(numbering: "1.")
#set par(justify: true)

#align(center)[
  #text(size: 18pt, weight: "bold")[Microservices Benchmark Sizing Report] \
  #v(1em)
  #text(size: 12pt)[Analytical Baseline for Load Generation & Infrastructure Sizing]
]

#v(2em)

= Benchmark Assumptions & Load Profile

Since this application is designed as a research benchmark to evaluate Service Mesh overhead, traditional user-centric rate limits do not apply. Instead, we establish "Target Capacities" (Expected Throughput) for each service. The external load generator will be calibrated to these targets to measure system behavior under sustained, predictable stress without causing immediate cascading failures (OOM/CPU starvation).

We assume a baseline aggregate test load of *100 Requests Per Second (RPS)* generated synthetically.

*Target Load Profile per Instance ($lambda$):*
- *Gateway:* 100 RPS (Benchmark entry point, routing all synthetic traffic).
- *Filter Service:* 10 RPS (Target capacity for testing image manipulation overhead).
- *Video Service:* 1 RPS (Target capacity for testing heavy I/O and media buffering).
- *Math Services:* 10 RPS (Controlled load specifically to monitor CPU clock scaling).
- *AI & Permutation Services:* 1 to 2 RPS. (Extreme complexity nodes. The load generator must be capped at this target per instance to accurately measure $O(n!)$ and inference overhead without crashing the node).

*Infrastructure Overhead:*
Based on standard Service Mesh benchmarks, we allocate a static overhead per instance to ensure the mesh proxies do not compete with the application for baseline resources: $approx 150$ MB RAM and $approx 100m$ CPU.

= Analytical Formulas

*1. Expected CPU Capacity (Millicores):*
$ "CPU"_m = ((lambda times W_"app") times K_"overhead") + "CPU"_"mesh" $
Where $W_"app"$ is the assumed processing time in milliseconds, $K_"overhead" = 1.2$ (OS context switching), and $"CPU"_"mesh" = 100m$.

*2. Expected RAM Footprint (Megabytes):*
$ M_"total" = M_"base" + (M_"req" times lambda) + M_"cache" + M_"mesh" $
Where base .NET footprint ($M_"base"$) is 100 MB, and mesh sidecar ($M_"mesh"$) is 150 MB.

= Service Target Capacities (Per Instance)

== Gateway
- *Benchmark Target:* $lambda = 100$ RPS, $W_"app" = 5$ ms.
- *CPU:* 
$ (100 times 5 times 1.2) + 100m = 600m + 100m = 700m $
- *RAM:* 
#align(center)[ $100$ MB + In-flight Requests ($100 times 1$ MB) + $150$ MB = $350$ MB. ] \
- *Provisioning Target:* 1000m CPU / 512Mi RAM.

== Video Service
- *Benchmark Target:* $lambda = 1$ RPS, $W_"app" = 500$ ms.
- *CPU:* 
$ (1 times 500 times 1.2) + 100m = 600m + 100m = 700m $
- *RAM:* 
#align(center)[ $100$ MB + Media Buffer ($500$ MB) + $150$ MB = $750$ MB. ] \
- *Provisioning Target:* 1000m CPU / 1024Mi RAM.

== Filter Service (Digital Filters)
- *Benchmark Target:* $lambda = 10$ RPS, $W_"app" = 50$ ms.
- *CPU:* 
$ (10 times 50 times 1.2) + 100m = 600m + 100m = 700m $
- *RAM:* 
#align(center)[ $100$ MB + Pixel Matrices ($10 times 30$ MB) + $150$ MB = $550$ MB. ] \
- *Provisioning Target:* 1000m CPU / 768Mi RAM.

== AI Service (Neural Network)
- *Benchmark Target:* $lambda = 2$ RPS.
- *System Requirements:* Fixed baseline of 24 GB RAM per instance (CPU-bound inference).
- *CPU:* 
$ (2 times 3000 times 1.2) + 100m = 7200m + 100m = 7300m $
- *Provisioning Target:* 8000m CPU / 24Gi RAM.

== Math Services (Integration / Differential)
- *Benchmark Target:* $lambda = 10$ RPS, $W_"app" = 80$ ms.
- *CPU:* 
$ (10 times 80 times 1.2) + 100m = 960m + 100m = 1060m $
- *RAM:* 
#align(center)[ $100$ MB + Math State/Cache ($300$ MB) + $150$ MB = $550$ MB. ] \
- *Provisioning Target:* 1000m CPU / 768Mi RAM.

== Permutation Service
- *Benchmark Target:* $lambda = 1$ RPS, $W_"app" = 800$ ms (Monopolizes core).
- *CPU:* 
$ (1 times 800 times 1.2) + 100m = 960m + 100m = 1060m $
- *RAM:* 
#align(center)[ $100$ MB + $O(n!)$ Object Graph ($800$ MB) + $150$ MB = $1050$ MB. ] \
- *Provisioning Target:* 1000m CPU / 1024Mi RAM.

= Provisioning Summary

The following table dictates the infrastructure limits required to support one instance of each microservice based on our analytical benchmark projection.

#v(1em)

#figure(
  table(
    columns: (auto, auto, auto, 1fr),
    fill: (x, y) => if y == 0 { luma(230) } else { none },
    inset: 8pt,
    align: horizon,
    
    [ *Microservice* ], [ *CPU Target* ], [ *RAM Target* ], [ *Benchmark Notes* ],
    [ Gateway ], [ 1000m ], [ 512Mi ], [ Sized to process 100 RPS aggregate test traffic + Mesh overhead. ],
    [ Neural Network ], [ 8000m ], [ 24Gi ], [ Target test load: 2 RPS. High system requirements for CPU-bound inference (No GPU). ],
    [ Video Service ], [ 1000m ], [ 1024Mi ], [ Target test load: 1 RPS. Evaluates heavy RAM buffering overhead. ],
    [ Filter Service ], [ 1000m ], [ 768Mi ], [ Target test load: 10 RPS. Evaluates matrix math + sidecar efficiency. ],
    [ Math Services ], [ 1000m ], [ 768Mi ], [ CPU bounded. RAM increased to support inter-service test state caching. ],
    [ Permutation ], [ 1000m ], [ 1024Mi ], [ Target test load: 1 RPS. Sized to evaluate $O(n!)$ CPU monopolization without OOM. ]
  ),
  caption: [Recommended Sizing Requirements per Instance (Benchmark Phase)]
)

= Final Cluster Infrastructure Requirements

To ensure stable test conditions and proper redundancy, the research environment requires multiple instances of each service. Based on the abstract sizing above, we calculate the total hardware footprint.

*Redundancy Assumptions:*
- *Standard Microservices:* 3 instances each (Gateway, Video, Filter, Math, Permutation).
- *AI Service:* 2 instances (Strictly isolated on a dedicated VM).

== Workload Aggregation (Total Pod Requirements)

*Data Plane Services (3x Multiplier):*
- *Gateway:* 3000m CPU / 1536Mi RAM
- *Video Service:* 3000m CPU / 3072Mi RAM
- *Filter Service:* 3000m CPU / 2304Mi RAM
- *Math Services:* 3000m CPU / 2304Mi RAM
- *Permutation:* 3000m CPU / 3072Mi RAM
*Data Plane Total:* ~15 vCPUs / ~12 GB RAM (Net application requirements).

*AI Service (2x Multiplier):*
- *Neural Network:* 16000m CPU / 48 GB RAM (Net application requirements).

== Hardware Sizing & Node Topology

To accommodate the aggregated workloads along with OS overhead, Kubernetes daemons (Kubelet, Kube-Proxy), and Service Mesh agents, we distribute the load across the following Virtual Machines (VMs).

#v(1em)

#figure(
  table(
    columns: (auto, auto, auto, auto, 1fr),
    fill: (x, y) => if y == 0 { luma(230) } else { none },
    inset: 8pt,
    align: horizon,
    
    [ *Node Pool* ], [ *Count* ], [ *vCPU (Per Node)* ], [ *RAM (Per Node)* ], [ *Purpose & Justification* ],
    [ *Control Plane* ], [ 3 ], [ 4 ], [ 8 GB ], [ Manages the cluster. 3 nodes ensure High Availability (etcd quorum). 4 vCPUs easily handle API scheduling and Service Mesh control planes (e.g., Istiod). ],
    [ *Data Plane* ], [ 3 ], [ 8 ], [ 8 GB ], [ Hosts the standard microservices. 3 nodes provide resilience. 8 vCPUs per node provide 5 vCPUs for test apps + 3 vCPUs for OS/Mesh overhead. ],
    [ *AI Dedicated* ], [ 1 ], [ 24 ], [ 64 GB ], [ Isolated VM hosting the 2 CPU-bound AI instances (16 cores, 48 GB RAM total). 64 GB system RAM provides safety overhead. ],
    [ *Load Gen* ], [ 1 ], [ 4 ], [ 8 GB ], [ Dedicated external node running the load testing tool (e.g., Fortio, k6) to simulate target RPS precisely without skewing internal cluster metrics. ]
  ),
  caption: [Final Hardware Provisioning Summary for Benchmark Environment]
)

#v(1em)
*Total Infrastructure Required:* 8 Virtual Machines (Totaling 64 vCPUs and 120 GB RAM).
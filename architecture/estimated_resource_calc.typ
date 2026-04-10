#set page(paper: "a4", margin: 2cm)
#set text(font: "Linux Libertine", size: 11pt)
#set heading(numbering: "1.")
#set par(justify: true)

#align(center)[
  #text(size: 18pt, weight: "bold")[Microservices Pre-Development Sizing Report] \
  #v(1em)
  #text(size: 12pt)[Analytical Baseline Based on Architectural Abstractions]
]

#v(2em)

= Engineering Assumptions & Traffic Modeling

Since the microservices are currently in the abstract design phase, this report establishes a baseline using "educated guesses" for traffic distribution. We assume a moderate peak system load of *100 Requests Per Second (RPS)* entering the system.

*Traffic Distribution Model ($lambda$):*
- *Gateway:* 100 RPS (Handles 100% of incoming traffic).
- *Filter Service:* 10 RPS (Assuming 10% of requests involve image manipulation).
- *Video Service:* 1 RPS (Assuming 1% of requests involve heavy video processing).
- *Math Services:* 10 RPS (Controlled load for inter-service stress testing).
- *AI & Permutation Services:* 1 to 2 RPS. (Strictly rate-limited at the Gateway level to prevent node monopolization due to extreme algorithmic complexity).

*Infrastructure Overhead:*
Based on standard Service Mesh (e.g., Istio/Linkerd) and mTLS benchmarks, we allocate a static overhead per instance: $approx 150$ MB RAM and $approx 100m$ CPU.

= Analytical Formulas

*1. CPU Estimation (Millicores):*
$ "CPU"_m = ((lambda times W_"app") times K_"overhead") + "CPU"_"mesh" $
Where $W_"app"$ is the assumed processing time in milliseconds, $K_"overhead" = 1.2$ (OS context switching), and $"CPU"_"mesh" = 100m$.

*2. RAM Estimation (Megabytes):*
$ M_"total" = M_"base" + (M_"req" times lambda) + M_"cache" + M_"mesh" $
Where base .NET footprint ($M_"base"$) is 100 MB, and mesh sidecar ($M_"mesh"$) is 150 MB.

= Service Calculations (Per Instance)

== 1. Gateway
- *Inputs:* $lambda = 100$ RPS, $W_"app" = 5$ ms.
- *CPU:* 
$ (100 times 5 times 1.2) + 100m = 600m + 100m = 700m $
- *RAM:* 
#align(center)[ $100$ MB + In-flight Requests ($100 times 1$ MB) + $150$ MB = $350$ MB. ] \
- *Provisioning Target:* 1000m CPU / 512Mi RAM.

== 2. Video Service
- *Inputs:* $lambda = 1$ RPS, $W_"app" = 500$ ms.
- *CPU:* 
$ (1 times 500 times 1.2) + 100m = 600m + 100m = 700m $
- *RAM:* 
#align(center)[ $100$ MB + Media Buffer ($500$ MB) + $150$ MB = $750$ MB. ] \
- *Provisioning Target:* 1000m CPU / 1024Mi RAM.

== 3. Filter Service (Digital Filters)
- *Inputs:* $lambda = 10$ RPS, $W_"app" = 50$ ms.
- *CPU:* 
$ (10 times 50 times 1.2) + 100m = 600m + 100m = 700m $
- *RAM:* 
#align(center)[ $100$ MB + Pixel Matrices ($10 times 30$ MB) + $150$ MB = $550$ MB. ] \
- *Provisioning Target:* 1000m CPU / 768Mi RAM.

== 4. AI Service (Neural Network)
- *Inputs:* $lambda = 2$ RPS (Strict Rate Limit), $W_"app" = 400$ ms.
- *CPU:* 
$ (2 times 400 times 1.2) + 100m = 960m + 100m = 1060m $
- *RAM:* 
#align(center)[ $100$ MB + In-flight Tensors ($2 times 50$ MB) + Model Cache ($1500$ MB) + $150$ MB = $1850$ MB. ] \
- *Provisioning Target:* 2000m CPU / 2048Mi RAM.

== 5. Math Services (Integration / Differential)
- *Inputs:* $lambda = 10$ RPS, $W_"app" = 80$ ms.
- *CPU:* 
$ (10 times 80 times 1.2) + 100m = 960m + 100m = 1060m $
- *RAM:* 
#align(center)[ $100$ MB + Math State/Cache ($300$ MB) + $150$ MB = $550$ MB. ] \
- *Provisioning Target:* 1000m CPU / 768Mi RAM.

== 6. Permutation Service
- *Inputs:* $lambda = 1$ RPS (Strict Rate Limit), $W_"app" = 800$ ms (Monopolizes core).
- *CPU:* 
$ (1 times 800 times 1.2) + 100m = 960m + 100m = 1060m $ \
- *RAM:* \ 
#align(center)[ $100$ MB + $O(n!)$ Object Graph ($800$ MB) + $150$ MB = $1050$ MB. ] \
- *Provisioning Target:* 1000m CPU / 1024Mi RAM.

= Provisioning Summary

The following table dictates the infrastructure limits required to support one instance of each microservice based on our analytical projection. 

#v(1em)

#figure(
  table(
    columns: (auto, auto, auto, 1fr),
    fill: (x, y) => if y == 0 { luma(230) } else { none },
    inset: 8pt,
    align: horizon,
    
    [ *Microservice* ], [ *CPU Target* ], [ *RAM Target* ], [ *Design Notes* ],
    [ Gateway ], [ 1000m ], [ 512Mi ], [ Sized for 100 RPS peak traffic with Service Mesh overhead. ],
    [ Neural Network ], [ 2000m ], [ 2048Mi ], [ Rate-limited to 2 RPS. High RAM requirement for model weights. ],
    [ Video Service ], [ 1000m ], [ 1024Mi ], [ Provisioned for 1 heavy request/sec. RAM intensive (frame buffering). ],
    [ Filter Service ], [ 1000m ], [ 768Mi ], [ Handles 10% of total traffic. CPU optimized for matrix operations. ],
    [ Math Services ], [ 1000m ], [ 768Mi ], [ CPU bounded. RAM increased to support test state caching. ],
    [ Permutation ], [ 1000m ], [ 1024Mi ], [ Rate-limited to 1 RPS. Strict limits required to prevent OOM errors. ]
  ),
  caption: [Recommended Sizing Requirements per Instance (Abstract Phase)]
)
= Final Cluster Infrastructure Requirements

To ensure High Availability (HA) and proper redundancy, the production environment requires multiple instances of each service. Based on the abstract sizing above, we calculate the total hardware footprint.

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
- *Neural Network:* 4000m CPU / 4096Mi RAM (Net application requirements).

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
    [ *Data Plane* ], [ 3 ], [ 8 ], [ 8 GB ], [ Hosts the standard microservices. 3 nodes provide resilience. 8 vCPUs per node provide 5 vCPUs for apps + 3 vCPUs for OS/Mesh overhead. ],
    [ *AI Dedicated* ], [ 1 ], [ 8 ], [ 8 - 16 GB ], [ Isolated VM hosting the 2 AI instances (4 cores total). 8 vCPUs provide safety from CPU throttling. Expand RAM if the ML model grows. ],
    [ *Load Gen* ], [ 1 ], [ 4 ], [ 8 GB ], [ External node running the load testing tool (e.g., Fortio, k6) to simulate 100+ RPS without skewing cluster internal metrics. ]
  ),
  caption: [Final Hardware Provisioning Summary]
)

#v(1em)
*Total Infrastructure Required:* 8 Virtual Machines (Totaling 52 vCPUs and 64-72 GB RAM).
#set page(paper: "a4", margin: 2cm)
#set text(font: "Linux Libertine", size: 11pt)
#set heading(numbering: "1.")
#set par(justify: true)

#align(center)[
  #text(size: 18pt, weight: "bold")[Microservices Resource Estimation Report] \
  #v(1em)
  #text(size: 12pt)[Baseline Analytical Sizing for .NET Architecture]
]

#v(2em)

= Assumptions & Baseline Variables

To establish a theoretical baseline without empirical load testing, the following variables and architectural constraints are assumed:

- *Framework:* .NET (e.g., .NET 8/9 with Kestrel). High performance, but requires memory headroom for the Garbage Collector (GC).
- *Base RAM ($M_"base"$):* 100 MB. The minimum footprint of a "cold" .NET web service.
- *Overhead Multiplier ($K_"overhead"$):* 1.2. Adds a 20% margin to CPU calculations to account for OS context switching, containerization overhead, and GC cycles.
- *Unit of CPU:* "m" denotes millicores (Kubernetes standard), where $1000m = 1$ vCPU (Virtual Core).
- *Synthetic Traffic ($lambda$):* The Requests Per Second (RPS) values used below are *synthetic placeholders* intended to model a moderate, controlled load. In production, these should align with actual business metrics or hard rate-limits enforced at the Gateway.

= Mathematical Models

We utilize two primary formulas to estimate the required limits for a single instance of each service:

*1. Memory (RAM) Estimation:*
$ M_"total" = M_"base" + (M_"req" times C_"concurrent") + M_"cache" + M_"buffer" $
Where:
- $M_"req"$: Memory allocated per single request (DTOs, JSON serialization, etc.).
- $C_"concurrent"$: Number of requests processed simultaneously (for synchronous flows, often equals $lambda$).
- $M_"cache"$: In-memory application caches or loaded ML models.
- $M_"buffer"$: Memory reserved for I/O buffers (e.g., streaming media).

*2. CPU Estimation (based on Little's Law):*
$ "CPU"_m = (lambda times W) times K_"overhead" $
Where:
- $lambda$: Requests Per Second (RPS).
- $W$: Average processing time per request in milliseconds (ms).

= Service Calculations

== Gateway
Infrastructure node handling basic file routing and proxying.
- *Inputs:* $lambda = 50$ RPS, $W = 5$ ms.
- *CPU:* 
$ "CPU"_m=(50 times 5) times 1.2 = 250 times 1.2 = 300m $
- *RAM:* Minimal request footprint ($M_"req" = 1$ MB), routing table cache ($M_"cache" = 50$ MB).
$ M_"total" = 100 + (1 times 50) + 50 + 0 = 200 " MB" $
- *Conclusion:* ~300m CPU / 256Mi RAM.

== Video Service
Handles media compression and frame-by-frame splitting (CPU & RAM heavy).
- *Inputs:* $lambda = 2$ RPS, $W = 400$ ms.
- *CPU:* 
$ "CPU"_m=(2 times 400) times 1.2 = 800 times 1.2 = 960m $ (Rounds to 1000m / 1 Core).
- *RAM:* Heavy frame buffering ($M_"buffer" = 500$ MB), processing memory ($M_"req" = 100$ MB).
$ M_"total" = 100 + (100 times 2) + 0 + 500 = 800 " MB" $
- *Conclusion:* 1000m CPU / 1024Mi RAM.

== Filter Service (Digital Filters)
Executes complex matrix manipulations for visual filters.
- *Inputs:* $lambda = 10$ RPS, $W = 40$ ms.
- *CPU:* 
$ "CPU"_m=(10 times 40) times 1.2 = 400 times 1.2 = 480m $
- *RAM:* Loading pixel matrices ($M_"req" = 30$ MB per image).
$ M_"total" = 100 + (30 times 10) + 0 + 0 = 400 " MB" $
- *Conclusion:* 500m CPU / 512Mi RAM.

== AI Service (Neural Network)
Isolated, extreme resource intensity. Assumes CPU-only inference.
- *Inputs:* $lambda = 4$ RPS, $W = 400$ ms.
- *CPU:* $ "CPU"_m=(4 times 400) times 1.2 = 1600 times 1.2 = 1920m $ (Rounds to 2000m / 2 Cores).
- *RAM:* The ML model weights reside in memory ($M_"cache" = 1500$ MB), tensor operations ($M_"req" = 50$ MB).
  $ M_"total" = 100 + (50 times 4) + 1500 + 0 = 1800 " MB" $
- *Conclusion:* 2000m CPU / 2048Mi RAM.

== Math Services (Integration / Differential Eq.)
State/Cache heavy math operations.
- *Inputs:* $lambda = 5$ RPS, $W = 80$ ms.
- *CPU:* 
$ "CPU"_m=(5 times 80) times 1.2 = 400 times 1.2 = 480m $
- *RAM:* Caching intermediate computation states ($M_"cache" = 300$ MB).
$ M_"total" = 100 + (5 times 5) + 300 + 0 = 425 " MB" $
- *Conclusion:* 500m CPU / 512Mi RAM.

== Permutation Service
Computes $O(n!)$ complexity. Designed to strictly load a single node.
- *Inputs:* $lambda = 1$ RPS, $W = 800$ ms (Monopolizes the core).
- *CPU:* $ "CPU"_m=(1 times 800) times 1.2 = 960m $ (Rounds to 1000m / 1 Core).
- *RAM:* Exponential object graph growth if permutations are collected before yielding ($M_"req" = 800$ MB).
$ M_"total" = 100 + (800 times 1) + 0 + 0 = 900 " MB" $
- *Conclusion:* 1000m CPU / 1024Mi RAM. (Requires strict limits to prevent OOM errors).

= Final Baseline Recommendations

The following table summarizes the recommended starting limits for a single instance of each service within a containerized environment (e.g., Kubernetes).

#v(1em)

#figure(
  table(
    columns: (auto, auto, auto, 1fr),
    fill: (x, y) => if y == 0 { luma(230) } else { none },
    inset: 8pt,
    align: horizon,
    
    [ *Microservice* ], [ *CPU Target* ], [ *RAM Target* ], [ *Architectural Notes* ],
    [ Gateway ], [ 300m ], [ 256Mi ], [ I/O bound; async proxy operations. ],
    [ Neural Network ], [ 2000m ], [ 2048Mi ], [ Heavy ML model cache; 2+ cores required to prevent queueing. ],
    [ Video Service ], [ 1000m ], [ 1024Mi ], [ Parallel thread utilization; high I/O buffer required. ],
    [ Filter Service ], [ 500m ], [ 512Mi ], [ Matrix math; utilizes SIMD CPU caches efficiently. ],
    [ Math Services ], [ 500m ], [ 512Mi ], [ Intermediary caching required for specific state-heavy nodes. ],
    [ Permutation ], [ 1000m ], [ 1024Mi ], [ High risk of Out-Of-Memory (OOM). Requires strict caps. ]
  ),
  caption: [Recommended Baseline Resource Allocations per Instance]
)

#v(2em)
_Note: These calculations provide a theoretical baseline. Real-world implementation requires load-testing (e.g., with k6 or JMeter) and monitoring via a Vertical Pod Autoscaler (VPA) to refine these values under actual network conditions._
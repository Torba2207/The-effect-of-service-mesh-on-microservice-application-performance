#set page(paper: "a4", margin: (x: 2.2cm, y: 2.2cm), numbering: "1")
#set text(font: "Linux Libertine", size: 11pt)
#set heading(numbering: "1.1")
#set par(justify: true)

#align(center)[
  #text(size: 17pt, weight: "bold")[Scaling the AI Service: Options and Estimates] \
  #v(0.3em)
  #text(size: 11pt)[GPU+CPU+RAM vs. CPU+RAM vs. Request Queue] \
  #v(0.3em)
  #text(size: 10pt, style: "italic")[Estimations and calculations for supervisor review]
]
#v(1em)

= Problem statement

The AI service is the only component of the test application that cannot sustain a rate-based
load. When it is driven above its capacity in the open-loop aggregate test, the request backlog
grows without bound and the virtual machine becomes unresponsive. This note presents three possible
solutions — adding a GPU, scaling CPU and RAM only, or adding a request queue — together with the
underlying measurements, the derived estimates, and the advantages and disadvantages of each. It
does not select a solution; it is intended as input for the supervisor's recommendation.

= Measured baseline

The following figures were measured directly on the running AI VM (24 vCPU, 62 GB RAM, two Docker
backends behind an nginx load balancer, model Llama 3.2 3B, Q4, 2.0 GB, served by Ollama).

#figure(
  table(
    columns: (1fr, auto),
    fill: (x, y) => if y == 0 { luma(235) } else { none },
    inset: 7pt, align: (left + horizon, left + horizon),
    [Quantity], [Measured value],
    [Warm request — wall time], [≈ 1.4 s],
    [Warm request — total CPU time], [≈ 23.9 CPU-seconds (≈ 17 cores busy)],
    [ — of which LLM inference (`llama-server`)], [23.1 CPU-s (96.7 %)],
    [ — of which orchestration (agent + MCP + ollama)], [≈ 0.8 CPU-s (3.3 %)],
    [Cold request — wall time], [≈ 6.6 s (≈ 5 s one-time model load + 1.4 s inference)],
    [Generation (decode) rate on CPU], [37.6 tokens/s],
    [Prompt (prefill) rate on CPU], [291.8 tokens/s],
    [Sustained capacity], [≈ 1 req/s warm; ≈ 0.3 req/s if cold starts occur],
  ),
  caption: [Measured per-request cost of the AI service.],
)

The request is approximately 97 % LLM inference, and a single inference occupies about 17 of the 24
cores. One request therefore costs roughly 24 core-seconds. Two concurrent inferences require about
34 cores on a 24-core machine, which leads to contention: each inference slows down, the open-loop
backlog grows, and the machine collapses. The three options below all follow from this measured cost.

= Option A — GPU + CPU + RAM

Add a GPU to the AI VM and serve the model on it. The 23.1 CPU-seconds of inference move off the
CPU; only the ≈ 0.8 CPU-s of orchestration remain on the host.

Estimates derived from the measurements:
- Throughput ceiling: $24 "cores" \/ (approx 0.9 "CPU-s per req") approx 25 "–" 30$ req/s, now
  limited by host-CPU orchestration rather than by the GPU.
- Latency: ≈ 0.2–0.3 s per warm request (GPU inference ≈ 0.075 s plus orchestration).
- VRAM: 2 GB weights + KV-cache (≈ 0.11 MB/token) + buffers → 8 GB minimum, 16 GB comfortable.
- GPU memory bandwidth required: ≈ 120–240 GB/s. A 2 GB model is small, so any discrete GPU exceeds
  this; e.g. NVIDIA L4 (24 GB, 300 GB/s) or A10 (24 GB, 600 GB/s). An A100/H100 would be largely
  unused.

Advantages:
- Throughput increases by roughly 80–100× (≈ 0.3 → ≈ 25–30 req/s), sufficient to run the AI/S2-ext
  scenarios under a real rate-based load.
- Warm latency drops to ≈ 0.25 s.
- Frees ≈ 17 cores per request, so the existing 24-core VM can orchestrate the higher rate.
- Modest hardware is sufficient (the model is 2 GB).
- No application changes; Ollama uses the GPU transparently.

Disadvantages:
- GPU virtualisation / passthrough on a VM is non-trivial (PCIe passthrough, vGPU licensing, or a
  bare-metal host). This is the main practical obstacle.
- Additional procurement and driver/CUDA setup effort.
- Throughput is still capped at ≈ 25–30 req/s by host-CPU orchestration; exceeding it requires more
  CPU cores as well.
- The cold-start model load remains (can be avoided with `OLLAMA_KEEP_ALIVE=-1`).

= Option B — CPU + RAM only

Keep CPU inference and scale out by adding cores and machines. Because each request costs ≈ 24
core-seconds, throughput follows a linear rule:
$ "req/s" approx "total cores" \/ (23.9 "CPU-s per req") quad => quad approx 24 "cores per 1 req/s". $

#figure(
  table(
    columns: (auto, auto, auto, auto),
    fill: (x, y) => if y == 0 { luma(235) } else { none },
    inset: 7pt, align: (center, center, center, center),
    [Target req/s], [CPU cores (× 23.9)], [≈ 24-core VMs], [RAM total],
    [1 (≈ today)], [24], [1], [≈ 16 GB],
    [2], [≈ 48], [2], [≈ 32 GB],
    [5], [≈ 120], [5], [≈ 80 GB],
    [10], [≈ 240], [10], [≈ 160 GB],
    [25], [≈ 600], [≈ 25], [≈ 400 GB],
  ),
  caption: [CPU-only sizing estimate.],
)

RAM capacity is small and inexpensive (≈ 8–16 GB per machine; the model is only 2 GB). The binding
co-limit is memory bandwidth: token generation re-reads the whole 2 GB model from RAM per token, and
the measured decode rate of 37.6 tokens/s reflects that bandwidth limit. Adding cores to a single
machine does not lift it, so CPU scaling must be horizontal — more machines, each with its own memory
bandwidth. A single 64-core server yields only about 2.7 req/s, not 25.

Advantages:
- No GPU dependency; uses the existing VM/Ansible provisioning pattern.
- RAM requirement per machine is small and cheap.
- Operationally simple and well understood.

Disadvantages:
- Low efficiency: ≈ 24 cores per 1 req/s. Reaching ≈ 25 req/s requires ≈ 600 cores (≈ 25 machines).
- Bounded by memory bandwidth, so a single machine cannot be scaled up; scale-out only.
- Latency remains high (≈ 1.4 s warm, ≈ 6.6 s cold).
- Substantial infrastructure and power footprint for a modest rate.

= Option C — Request queue

Place a queue with bounded concurrency in front of the AI service: only a fixed number of requests
(for example 2, matching capacity) are admitted to the backends at once, and the rest wait in RAM.
A maximum queue depth with a `429` rejection when full can be added.

The RAM cost is negligible: a waiting request is on the order of 1 KB, so
$1 "KB" times 1000000 approx 1$ GB — millions of requests fit in a few GB.

A queue does not increase throughput; the service rate remains ≈ 1 req/s. It only decouples the
arrival rate from the service rate. For an M/M/1 model the mean waiting time is
$ W approx 1 \/ (mu - lambda) quad (mu = "service rate", space lambda = "arrival rate"). $

#figure(
  table(
    columns: (auto, 1fr),
    fill: (x, y) => if y == 0 { luma(235) } else { none },
    inset: 7pt, align: (center, left),
    [Offered rate λ (μ = 1 req/s)], [Result],
    [0.9 req/s], [each request waits ≈ 10 s],
    [0.99 req/s], [each request waits ≈ 100 s],
    [1.5 req/s (> μ)], [queue grows 0.5/s without bound; waiting time → ∞],
    [25 req/s], [queue grows 24/s; after 1 min ≈ 1440 queued, ≈ 24 min wait and rising],
  ),
  caption: [Queue behaviour. It is stable only while the arrival rate is below the service rate.],
)

Advantages:
- Removes the collapse: bounded concurrency means only ≈ 2 inferences run at once, without core
  contention, so the machine stays responsive at any offered rate.
- Very low cost (RAM for queuing is negligible).
- Graceful degradation with a maximum depth and rejection, which also provides a clear capacity
  signal.
- Allows the AI scenarios to coexist in the aggregate test without crashing it.
- Absorbs bursts when the average load is below capacity.

Disadvantages:
- Does not increase throughput; the served rate stays ≈ 1 req/s.
- Under sustained overload the queue grows without bound and waiting time increases to minutes or
  hours.
- For measurement, the served latency becomes dominated by queue waiting time rather than by the
  service mesh, so it obscures the mesh overhead we intend to measure.
- Requires a small implementation (worker pool / message queue and admission control).

= Additional levers (applicable to any option)

- Keeping the model warm. Setting `OLLAMA_KEEP_ALIVE=-1` avoids the ≈ 5 s cold-load penalty, giving a
  consistent ≈ 1.4 s (CPU) or ≈ 0.25 s (GPU) per request.

= Summary

#figure(
  table(
    columns: (auto, auto, auto, auto),
    fill: (x, y) => if y == 0 { luma(235) } else { none },
    inset: 7pt, align: (left + horizon, center, center, center),
    [], [A — GPU+CPU+RAM], [B — CPU+RAM only], [C — Queue],
    [Throughput (req/s)], [≈ 25–30], [≈ 24 cores per req/s], [≈ 1 (unchanged)],
    [Warm latency per request], [≈ 0.25 s], [≈ 1.4 s], [1.4 s + waiting],
    [Hardware for ≈ 25 req/s], [1 GPU + current VM], [≈ 600 cores / ≈ 25 VMs], [n/a],
    [Prevents the collapse], [yes], [yes, if sized], [yes],
    [Cost / effort], [GPU passthrough], [high (many nodes)], [low (software)],
    [Raises capacity], [yes], [yes (linear, costly)], [no],
  ),
  caption: [Side-by-side comparison of the three options.],
)

The three options address different aspects of the problem. A queue makes the service robust and
prevents the collapse, but does not raise capacity. A GPU is, by our estimates, the most efficient
way to raise capacity — one GPU is equivalent to roughly 600 CPU cores for the same target rate — but
depends on GPU virtualisation being feasible on the available infrastructure. Scaling CPU and RAM
only is straightforward operationally but requires a large number of machines to reach a comparable
rate. A queue and a capacity increase are complementary rather than mutually exclusive.

We would appreciate the supervisor's recommendation on which direction to pursue, in particular
whether GPU virtualisation is available for the AI node, and whether the target request rate for the
AI scenarios justifies the associated cost.

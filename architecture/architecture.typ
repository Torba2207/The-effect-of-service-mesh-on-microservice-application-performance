= Service Specifications

// Custom function to draw nice looking cards
#let card(title, body) = block(
  fill: rgb("#ffffff"),
  stroke: 1pt + rgb("#eaeaea"),
  radius: 6pt,
  width: 100%,
  inset: 14pt,
  spacing: 1em,
)[
  *#text(fill: rgb("#1a1a1a"), size: 12pt, title)* \
  #v(0.3em)
  #body
]

#card("AI Service (Heterogenous System Test)")[
  Isolated service for direct output requests and inter-service data passing. 
  - *Constraint:* Requires maximum load caps per request and strict isolation due to extreme resource intensity.
  - *Use Case:* May be utilized for test data generation post-normalization.
  - *Dependencies:*
    - *Filter Service:* If generating identical pictures.
    - *Permutation Service:* Computes $n!$ complexity without affecting execution time dependencies.
]

#card("Media Services")[

  - *Video Service:* Handles media compression and frame-by-frame splitting. Communicates downstream with the *Digital Filters Service* to apply digital visual filters.
  - *Digital Filters Service:* Executes complex matrix manipulations. Can be separated into specific standalone filters if needed.
]

#card("Mathematical Modules")[
  Abstract modules used for controlled load testing and stressing system communications:
  - *Differential Equations Service:* Solves differential equations with varying complexity to test inter-service communication and load handling.
  - *Integration Service:* Heavy computing of integrals.
  - *Permutations Service:* Finds all permutations of a given set ($O(n!)$). Designed to severely load a single node.
  - *Fibonacci Service:* Used specifically to investigate CPU clock scaling based on request complexity.
 
]

= System Observability & Metrics

#grid(
  columns: (1fr, 1fr),
  gutter: 14pt,
  card("Performance Targets")[
    - *Throughput:* Media files routing
    - *CPU Clock:* Complex math calculations (Math Node 1)
    - *RAM Usage:* State/Cache heavy math (Math Node 2)
    - *Latency:* Monitored globally across all services
  ],
  card("Infrastructure Focus")[
    - *Observability:* Analyzing the performance delta between native implementations and Service Mesh architectures.
  ]
)

#image("images/SM_Project_App_Arch.drawio.png", width: 100%)
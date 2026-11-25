# Measurements 12.11–25.11.2026 (overlay network)

Every result that was still loose in a `results/` directory when the cluster network was made
flat (25.11.2026), moved here so that new runs start with fresh CSVs and never share a file or a
`run_id` with overlay data. The layout mirrors `loadGenTests/`.

**Network of this snapshot:** Calico `vxlan` backend, `vxlanMode: Always`, pod MTU 1450, pod
traffic leaving the cluster (pod → AI host) NATed to the node IP. Everything measured from
25.11.2026 on runs on the flat network (BGP without encapsulation, MTU 1500, no NAT towards the
AI host); see `docs/test-scenario.typ`, *Network facts*. The older overlay data is in
`../measurements_11_11_26/`.

| Directory | Contents |
|-----------|----------|
| `phaseA/FibonacciService/results` | I-S (`istio_mtls`) fibonacci S1, level `low`, r1–r5, run from lg on 23.11.2026 with `-r 5 -W 10s -S 60s -C 10`: shorter than the campaign protocol (r10, 120 s), i.e. a trial of the lg campaign scheduler rather than a campaign cell. `master.csv`, `timeseries_istio_mtls_fibonacci_S1.csv`, k6 summaries. |

Not moved, still in their original places (as for the 11.11 snapshot): the `aborted_*` folders in
`phaseA/*/results`, `phaseB/results/archive_v1_withAI`, `phaseB/results/archive_v2_vpndrop` and
`phaseB/results/plots`. All of them are overlay data as well.

The k6 logs (`*.log`) are gitignored and exist only on lg, where the run took place.

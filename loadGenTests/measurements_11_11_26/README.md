# Measurements up to 11.11.2026

Every result that was still loose in a `results/` directory on 11.11.2026, moved here before the
lg-based studies (branch `studies_lg_based`) start, so new runs begin with fresh CSVs. The layout
mirrors `loadGenTests/`: `phaseA/<ServiceDir>/results`, `phaseB/results`, `ai_capacity/results`.

| Directory | Contents |
|-----------|----------|
| `phaseA/*/results` | Phase A, 5 configurations (`baseline`, `linkerd_mtls`, `linkerd_nomtls`, `istio_mtls`, `istio_nomtls`) for every scenario: S1 (`master.csv`), S2-int (`master_S2int.csv`), S2-ext (`master_S2ext.csv`), plus `timeseries_<config>.csv` and the k6 summaries `k6_<run_id>.json`. |
| `phaseB/results` | Phase B, the same 5 configurations: `master.csv`, `timeseries_<config>.csv`, k6 summaries, and the legacy AI probe run (`k6_linkerd_mtls_aiprobe.*`). |
| `ai_capacity/results` | AI host capacity ladder of 13.09.2026 (ai_rtx, 3/6/12 req/s). |

Not moved, still in their original places: the already separated archives
(`phaseB/results/archive_v1_withAI`, `phaseB/results/archive_v2_vpndrop`, the `aborted_*` folders
in `phaseA/*/results`) and `phaseB/results/plots` (used by `docs/summer-report.typ`).

The k6 logs (`*.log`, including `campaign_*.log`) are gitignored: they were moved here too, but
only exist in the working copy where the campaigns ran.

The plotting scripts read paths relative to the working directory, so they work on this snapshot
from its own phase directory, e.g.:

```bash
cd loadGenTests/measurements_11_11_26/phaseB
python3 ../../phaseB/make_plots.py --level high    # -> results/plots/ inside this snapshot
```

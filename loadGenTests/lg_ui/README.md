# lg_ui — campaign scheduler on the load generator

A web page on `lg` to queue Phase A and Phase B campaigns, follow their logs and stop them, instead
of `ssh` + `tmux` + typing the commands. It is a thin layer over
[`../common/lg_campaign.sh`](../common/lg_campaign.sh): every job is one `lg_campaign.sh` call,
so results are committed and pushed to `studies_lg_based` exactly as from the command line.

Open **http://10.29.20.130:8080** (VPN), enter the token once (the browser keeps it). The token is
in `/etc/lg-ui.env` on `lg`:

```bash
ssh root@10.29.20.130 grep TOKEN /etc/lg-ui.env
```

## What a job does

The form only sends parameters; the server checks them and builds the command, shown in the
preview before anything is queued:

```
loadGenTests/common/lg_campaign.sh -d istio-mtls -G -- loadGenTests/phaseA/run_phaseA_Core.sh -s video -m istio -t on
```

| Form | Becomes |
|------|---------|
| Configuration | the runner's `-m`/`-t` (and the Phase B `-c` label); with *Deploy first*, `lg_campaign.sh -d <make target>` |
| `istio_*`, `consul_mtls` | `lg_campaign.sh -G`: the gateway NodePort (Istio ingress gateway / Consul API Gateway) is read after the deploy and passed as `-u` |
| Phase A scenario, rates, n, levels, reps, durations, label | the runner's flags; only values that differ from the runner defaults are passed |
| *AI host in the mesh* (`istio_*`, `linkerd_*`, `consul_mtls`) | with *Deploy first*, `lg_campaign.sh -A` = `make <target> AI_MESH=1` (`deployments/ansible/ai_mesh.yml`); AI runs get the label suffix `_aimesh` (Phase B: `-c <config>_aimesh`; Phase A AI scenarios: the runner adds it). Without deploy it only sets the labels, for a cluster already deployed that way. The runners check the label against the deployed state (`common/ai_state.sh`) and refuse a mismatch. |
| *Push the results* off | `lg_campaign.sh -n` |
| Self-test | a one-minute counter: touches neither the cluster nor git, checks the scheduler itself |

| Configuration | `make` target | Runner labels |
|---------------|---------------|---------------|
| `baseline` | `baseline` | `-m baseline -t na` |
| `linkerd_mtls` | `linkerd` | `-m linkerd -t on` |
| `linkerd_nomtls` | `linkerd-nomtls` | `-m linkerd -t off` (proxy bypass, see `../phaseA/README.md`) |
| `istio_mtls` | `istio-mtls` | `-m istio -t on` |
| `istio_nomtls` | `istio-nomtls` | `-m istio -t off` |
| `consul_mtls` | `consul` | `-m consul -t on` (C-S, provisional; mTLS cannot be switched off) |

`consul_mtls` needs *AI host in the mesh* for Phase B and for the Phase A scenario `ai`: Consul's
API Gateway routes only to services in the Consul catalog, so `/api/Ai` exists only with the AI host
in the mesh. The page refuses those jobs otherwise; the S2-ext scenarios (`permutation_ai`,
`digital_ai`) and the in-cluster ones work either way.

The duration shown is an estimate: levels × reps × (warm-up + steady + cooldown), plus ~10 min for
a deploy.

## Queue and states

Jobs run **one at a time, oldest first**. Queue as many as you like (e.g. a night of
configurations, each with *Deploy first*).

| State | Meaning |
|-------|---------|
| queued | waiting; can be cancelled |
| running | in its tmux session `job-<id>`; can be stopped |
| done | finished; `failed (rc N)` when the exit code is not 0 |
| interrupted | stopped (Stop, Ctrl-C, reboot of `lg`) or could not be started |
| cancelled | cancelled while queued |

**Stop** is Ctrl-C in the job's session: `lg_campaign.sh` does not commit a stopped campaign. Its
partial results stay in the clone, and `lg_campaign.sh` refuses to start on a clone with changes,
so **queued campaigns wait** (the page says *the clone has local changes*; hover it for the list)
until you commit or remove them on `lg` (`cd /root/thesis && git status`). A finished job is
committed even when the runner failed.

**One campaign at a time, also by hand.** `lg_campaign.sh` holds the lock
`/run/lock/thesis-campaign.lock` for the whole run, deploy included. A campaign started by hand
over `ssh` makes the queue wait (the page shows it); one started by hand while a queued job runs
refuses to start. A bare `make <config>` typed by hand does not take the lock: do not deploy by
hand while anything runs.

You can still watch or stop a job from a terminal: `tmux attach -t job-<id>`.

## How it works

```
browser ──HTTP──▶ server.py ──writes──▶ /root/lg_ui_jobs/<id>/run.sh, params.json
                     │
                     └─ keeps the tmux session lg-worker alive
                                         │
               worker.py (lg-worker) ── every 5 s: nothing running, lock free?
                                         └─▶ tmux session job-<id>: bash run.sh
                                               └─ lg_campaign.sh ... | tee log; exit code > rc
```

- `server.py` — HTTP + JSON API, token check, builds commands (`campaign.py`), stores jobs. It
  keeps no state in memory and can be restarted at any time.
- `worker.py` — starts queued jobs one by one. Each job runs in its own tmux session, so neither a
  restart of the server nor of the worker touches a running campaign.
- `jobs.py` — the job store and the state rules, shared by both.
- `campaign.py` — the form's options and validation, and the command a job runs.

A job is a directory in `LG_JOBS_DIR` (`/root/lg_ui_jobs`, outside the clone: `lg_campaign.sh`
refuses to run on a tree with untracked files):

| File | Written by | Meaning |
|------|------------|---------|
| `run.sh` | server | the command, its output to `log` |
| `params.json` | server | the request, the command, the title |
| `started` | worker | taken from the queue (written before tmux starts) |
| `cancelled` | server | cancelled while queued |
| `log` | the job | everything it printed |
| `rc` | the job | exit code, written when it ends |

State, in this order: `rc` → done; session `job-<id>` → running; `cancelled` → cancelled; no
`started` → queued; otherwise interrupted. The worker's own log is `LG_JOBS_DIR/worker.log`.

## API

All `/api/` requests need `Authorization: Bearer <token>`.

| Request | Does |
|---------|------|
| `GET /api/options` | configurations, scenarios, defaults |
| `GET /api/jobs` | all jobs (newest first), whether the worker runs, whether the lock is held |
| `GET /api/jobs/<id>/log?offset=N` | the log from byte N (max 256 KiB), the new offset, the state |
| `POST /api/jobs` | queue a job (JSON body as the form sends it) |
| `POST /api/jobs/preview` | the command and estimate for a body, without queueing |
| `POST /api/jobs/<id>/stop` | Ctrl-C a running job |
| `POST /api/jobs/<id>/cancel` | cancel a queued job |

## On lg

Installed by `cd deployments && make lg-bootstrap`: the systemd unit `lg-ui`, and
`/etc/lg-ui.env` with a random token (generated once, kept on re-runs). Nothing to install:
standard library only.

```bash
systemctl status lg-ui
journalctl -u lg-ui -f                    # server log
tail -f /root/lg_ui_jobs/worker.log       # worker log
tmux ls                                   # lg-worker and job-<id> sessions
```

- **After a `git pull` that changes `lg_ui`:** `systemctl restart lg-ui` for the server. The worker
  keeps running its old code until its session is killed: `tmux kill-session -t lg-worker` (safe
  at any time; the server starts a new one within 15 s).
- **New token:** edit `/etc/lg-ui.env`, then `systemctl restart lg-ui`.
- The unit uses `KillMode=process`, so stopping or restarting it never kills the tmux server with
  the worker and the running campaign.
- After a reboot of `lg` the running job is `interrupted` and the queue continues with the next one.

## Running it locally

On a workstation the page and the queue work, campaigns do not (`lg_campaign.sh` runs on `lg`
only); use *Self-test*. Needs `tmux`.

```bash
env LG_UI_TOKEN=test LG_JOBS_DIR=/tmp/lg_ui_jobs LG_CAMPAIGN_LOCK=/tmp/thesis-campaign.lock \
    LG_UI_ADDR=127.0.0.1 python3 loadGenTests/lg_ui/server.py
# http://127.0.0.1:8080, token: test
```

#!/usr/bin/env python3
"""Runs the queued jobs one at a time. server.py starts it in the tmux session lg-worker:

    worker.py <JOBS_DIR> <LOCK>

Every few seconds:
  1. a job session (job-*) exists          -> a job is running, wait;
  2. the campaign lock is held             -> a campaign started by hand (lg_campaign.sh), wait;
  3. otherwise take the oldest queued job: write its 'started' marker, then start its run.sh in
     its own tmux session job-<id>.

Each job runs in its own session, so Ctrl-C in a job stops only that job, and the worker can be
restarted at any time (it keeps no state; a running job is seen by its session). Paths come as
arguments, not from the environment: a new tmux session gets the tmux server's environment,
not the one of the process that created it.
"""
import sys
import time
import traceback
from datetime import datetime
from pathlib import Path

sys.dont_write_bytecode = True   # no __pycache__ in the clone (lg_campaign.sh needs a clean tree)
import jobs  # noqa: E402

POLL_S = 5
REPO = Path(__file__).resolve().parent.parent.parent


def log(jobs_dir, msg):
    line = f"{datetime.now().isoformat(timespec='seconds')} {msg}"
    print(line, flush=True)
    with open(jobs_dir / "worker.log", "a") as f:
        f.write(line + "\n")


def report(jobs_dir, state, reason, msg):
    """Log why the queue waits, once per reason (not every 5 s)."""
    if state.get("waiting") != reason:
        log(jobs_dir, msg)
        state["waiting"] = reason


def tick(jobs_dir, lock_path, state):
    sessions = jobs.tmux_sessions()
    if any(s.startswith(jobs.JOB_SESSION_PREFIX) for s in sessions):
        return
    queued = [j for j in jobs.list_jobs(jobs_dir, sessions) if j["state"] == jobs.QUEUED]
    if not queued:
        return
    if jobs.lock_busy(lock_path):
        report(jobs_dir, state, "lock", f"campaign lock {lock_path} is held (a campaign started by hand?); waiting")
        return
    job_id = queued[0]["id"]
    job_dir = jobs_dir / job_id
    if jobs.is_campaign(job_dir):
        changes = jobs.repo_changes(REPO)
        if changes:
            report(jobs_dir, state, "dirty", "the clone has local changes (results of a stopped "
                   "campaign?); campaigns wait until they are committed or removed:\n" + changes)
            return
    state.clear()
    try:
        (job_dir / jobs.STARTED).touch(exist_ok=False)
    except FileExistsError:
        return                        # taken by another worker
    if (job_dir / jobs.CANCELLED).exists():
        log(jobs_dir, f"{job_id}: cancelled, skipped")
        return
    try:
        jobs.tmux_new_session(jobs.session_name(job_id), ["bash", str(job_dir / "run.sh")])
    except (OSError, RuntimeError) as e:
        # 'started' stays, so the job shows as interrupted and is not retried in a loop.
        with open(job_dir / "log", "a") as f:
            f.write(f"[worker] could not start the job: {e}\n")
        log(jobs_dir, f"{job_id}: could not start: {e}")
        return
    log(jobs_dir, f"{job_id}: started ({queued[0]['title']})")


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: worker.py <JOBS_DIR> <LOCK>")
    jobs_dir = Path(sys.argv[1]).resolve()
    lock_path = sys.argv[2]
    log(jobs_dir, f"worker started (jobs in {jobs_dir}, lock {lock_path})")
    state = {}
    while True:
        try:
            tick(jobs_dir, lock_path, state)
        except Exception:
            log(jobs_dir, "error:\n" + traceback.format_exc())
        time.sleep(POLL_S)


if __name__ == "__main__":
    main()

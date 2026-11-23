"""Job store shared by server.py and worker.py.

A job is a directory in JOBS_DIR named by its id (creation time, e.g. 2026-11-23_14-05-09):

    run.sh        what runs (written once, never changed)
    params.json   the request it was built from: params, command, title
    started       marker: the worker took the job (written before tmux is launched)
    cancelled     marker: cancelled while still queued
    log           everything the job printed
    rc            exit code, written when the job ends

The state is derived from these files and from the tmux sessions on every call; nothing is kept
in memory, so the server and the worker can restart at any time.
"""
import fcntl
import json
import os
import re
import secrets
import shlex
import subprocess
from datetime import datetime
from pathlib import Path

STARTED = "started"
CANCELLED = "cancelled"

DONE = "done"
RUNNING = "running"
CANCELLED_STATE = "cancelled"
QUEUED = "queued"
INTERRUPTED = "interrupted"

WORKER_SESSION = "lg-worker"
JOB_SESSION_PREFIX = "job-"

# Shared with loadGenTests/common/lg_campaign.sh: one campaign at a time on lg, whoever starts it.
DEFAULT_LOCK = "/run/lock/thesis-campaign.lock"

JOB_ID_RE = re.compile(r"\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}(-\d+)?")


def is_job_id(name):
    return JOB_ID_RE.fullmatch(name) is not None


def _sort_key(job_id):
    # "2026-11-23_14-05-09" and, for a second job in the same second, "2026-11-23_14-05-09-2"
    return (job_id[:19], int(job_id[20:] or 0))


def session_name(job_id):
    return JOB_SESSION_PREFIX + job_id


# --- tmux ---

def tmux_sessions():
    """Names of all tmux sessions. No tmux server running means no sessions, not an error;
    tmux not installed raises FileNotFoundError."""
    result = subprocess.run(["tmux", "list-sessions", "-F", "#{session_name}"],
                            capture_output=True, text=True)
    return set(result.stdout.splitlines())


def tmux_new_session(name, argv):
    """Start argv in a detached tmux session. Raises RuntimeError with tmux's own message."""
    result = subprocess.run(["tmux", "new-session", "-d", "-s", name, *argv],
                            capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or f"tmux exited with {result.returncode}")


# --- campaign lock ---

def lock_busy(lock_path):
    """True if a campaign holds the lock (lg_campaign.sh keeps it for the whole run)."""
    try:
        fd = os.open(lock_path, os.O_RDWR | os.O_CREAT, 0o666)
    except OSError:
        return False          # no lock directory (e.g. on a workstation): nothing to respect
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        return True
    else:
        fcntl.flock(fd, fcntl.LOCK_UN)
        return False
    finally:
        os.close(fd)


# --- the clone ---

def repo_changes(repo):
    """`git status --porcelain` of the clone: empty when clean. lg_campaign.sh refuses to start on
    a clone with changes - typically the partial results of a stopped campaign - so the worker
    holds campaign jobs instead of letting each of them fail at once."""
    try:
        result = subprocess.run(["git", "-C", str(repo), "status", "--porcelain"],
                                capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        return ""
    return result.stdout.strip() if result.returncode == 0 else ""


def is_campaign(job_dir):
    return read_params(job_dir).get("params", {}).get("phase") in ("A", "B")


# --- state ---

def _mtime(path):
    try:
        return datetime.fromtimestamp(path.stat().st_mtime).isoformat(timespec="seconds")
    except FileNotFoundError:
        return None


def read_rc(job_dir):
    try:
        return int((job_dir / "rc").read_text().strip())
    except (FileNotFoundError, ValueError):
        return None


def job_state(job_dir, sessions):
    """The rules, in this order:
    rc -> done; tmux session -> running; cancelled -> cancelled; no started -> queued;
    anything else (started, but no rc and no session) -> interrupted."""
    if (job_dir / "rc").exists():
        return DONE
    if session_name(job_dir.name) in sessions:
        return RUNNING
    if (job_dir / CANCELLED).exists():
        return CANCELLED_STATE
    if not (job_dir / STARTED).exists():
        return QUEUED
    return INTERRUPTED


def read_params(job_dir):
    try:
        return json.loads((job_dir / "params.json").read_text())
    except (FileNotFoundError, ValueError):
        return {}


def job_info(job_dir, sessions):
    meta = read_params(job_dir)
    return {
        "id": job_dir.name,
        "state": job_state(job_dir, sessions),
        "rc": read_rc(job_dir),
        "title": meta.get("title", ""),
        "command": meta.get("command", ""),
        "started_at": _mtime(job_dir / STARTED),
        "finished_at": _mtime(job_dir / "rc"),
    }


def job_dirs(jobs_dir):
    """Job directories, oldest first. Anything else in JOBS_DIR (temporary .tmp-* directories,
    worker.log) is skipped."""
    dirs = [p for p in jobs_dir.iterdir() if p.is_dir() and is_job_id(p.name)]
    return sorted(dirs, key=lambda p: _sort_key(p.name))


def list_jobs(jobs_dir, sessions=None):
    if sessions is None:
        sessions = tmux_sessions()
    return [job_info(d, sessions) for d in job_dirs(jobs_dir)]


def find_job(jobs_dir, job_id):
    """The job's directory, or None for anything that is not an existing job id."""
    if not is_job_id(job_id):
        return None
    d = jobs_dir / job_id
    return d if d.is_dir() else None


# --- creating a job ---

def run_script(job_dir, repo, command):
    """run.sh: the command from the repository root, its output to the terminal and to log,
    then its exit code to rc (via rc.tmp + mv, so rc never exists half-written)."""
    jd = shlex.quote(str(job_dir))
    return (
        "#!/usr/bin/env bash\n"
        f"cd {jd} || exit 1\n"
        f"{{ cd {shlex.quote(str(repo))} && {command}; }} 2>&1 | tee -a {jd}/log\n"
        f'echo "${{PIPESTATUS[0]}}" > {jd}/rc.tmp && mv {jd}/rc.tmp {jd}/rc\n'
    )


def create_job(jobs_dir, repo, command, meta):
    """Build the job in a temporary directory, then rename it into place: the worker sees either
    a complete job or nothing. Returns the new job id."""
    tmp = jobs_dir / f".tmp-{secrets.token_hex(4)}"
    tmp.mkdir()
    base = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    for n in range(1, 100):
        job_id = base if n == 1 else f"{base}-{n}"
        final = jobs_dir / job_id
        (tmp / "run.sh").write_text(run_script(final, repo, command))
        (tmp / "params.json").write_text(json.dumps(
            {**meta, "command": command, "created": datetime.now().isoformat(timespec="seconds")},
            ensure_ascii=False, indent=2) + "\n")
        try:
            os.rename(tmp, final)   # fails when that id already exists (its directory is not empty)
            return job_id
        except OSError:
            continue
    tmp_cleanup(tmp)
    raise RuntimeError("could not allocate a job id")


def tmp_cleanup(path):
    for p in path.iterdir():
        p.unlink()
    path.rmdir()

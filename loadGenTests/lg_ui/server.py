#!/usr/bin/env python3
"""Campaign scheduler for lg: a page to queue Phase A / Phase B campaigns, follow their logs and
stop them. Standard library only.

    LG_UI_TOKEN=... LG_JOBS_DIR=/root/lg_ui_jobs python3 loadGenTests/lg_ui/server.py

Environment:
    LG_UI_TOKEN        bearer token the page must send on every /api/ request   (required)
    LG_JOBS_DIR        where jobs are kept; must be OUTSIDE the clone          (required)
    LG_UI_ADDR         listen address                                (default 0.0.0.0)
    LG_UI_PORT         listen port                                   (default 8080)
    LG_CAMPAIGN_LOCK   lock shared with lg_campaign.sh   (default /run/lock/thesis-campaign.lock)

The server only stores jobs and reads their state. worker.py (tmux session lg-worker, started and
watched by this server) runs them one at a time, each in its own tmux session job-<id>.
"""
import hmac
import json
import os
import socket
import subprocess
import sys
import threading
import time
import traceback
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

# No __pycache__ in the clone: lg_campaign.sh refuses to run on a tree with untracked files.
sys.dont_write_bytecode = True
import campaign  # noqa: E402
import jobs  # noqa: E402

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent

TOKEN = os.environ.get("LG_UI_TOKEN", "")
if not TOKEN:
    sys.exit("LG_UI_TOKEN is not set, e.g.: env LG_UI_TOKEN=$(openssl rand -hex 16) LG_JOBS_DIR=... python3 server.py")
if not os.environ.get("LG_JOBS_DIR"):
    sys.exit("LG_JOBS_DIR is not set (a directory outside the repository, e.g. /root/lg_ui_jobs)")
JOBS_DIR = Path(os.environ["LG_JOBS_DIR"]).resolve()
if JOBS_DIR == REPO or REPO in JOBS_DIR.parents:
    sys.exit(f"LG_JOBS_DIR={JOBS_DIR} is inside the repository: lg_campaign.sh would refuse to run "
             "(untracked files) or commit the job logs. Use a directory outside it.")
JOBS_DIR.mkdir(parents=True, exist_ok=True)
LOCK = os.environ.get("LG_CAMPAIGN_LOCK", jobs.DEFAULT_LOCK)

LOG_CHUNK = 256 * 1024
WORKER_CHECK_S = 15


# --- worker supervision ---

def ensure_worker():
    """Start the worker's tmux session unless it exists. Two callers at once are fine: the
    second one gets 'duplicate session', which means it is running."""
    if jobs.WORKER_SESSION in jobs.tmux_sessions():
        return
    try:
        jobs.tmux_new_session(jobs.WORKER_SESSION,
                              [sys.executable, str(HERE / "worker.py"), str(JOBS_DIR), LOCK])
        print(f"started the worker (tmux session {jobs.WORKER_SESSION})", flush=True)
    except RuntimeError as e:
        if "duplicate session" not in str(e):
            raise


def watch_worker():
    while True:
        try:
            ensure_worker()
        except Exception as e:
            print(f"cannot start the worker: {e}", file=sys.stderr, flush=True)
        time.sleep(WORKER_CHECK_S)


# --- request handling ---

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def send_json(self, code, obj):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.handle_req(code, body, "application/json; charset=utf-8")

    def handle_req(self, code, body, type_of_demanded_resp):
        self.send_response(code)
        self.send_header("Content-Type", type_of_demanded_resp)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def error(self, code, message):
        self.send_json(code, {"ok": False, "message": message})

    def authorized(self):
        auth_token = self.headers.get("Authorization", "")
        return hmac.compare_digest(auth_token.encode(), ("Bearer " + TOKEN).encode())

    def dispatch(self, method):
        url = urlparse(self.path)
        parts = url.path.strip("/").split("/")
        body = b""
        if method == "POST":
            # Always read the body first: with keep-alive, unread bytes would become the start
            # of the next request on this connection.
            body = self.rfile.read(int(self.headers.get("Content-Length") or 0))
        if parts[0] == "api" and not self.authorized():
            return self.error(HTTPStatus.UNAUTHORIZED, "wrong or missing token")
        try:
            route = getattr(self, f"{method.lower()}_routes")
            route(parts, parse_qs(url.query), body)
        except campaign.BadRequest as e:
            self.error(HTTPStatus.BAD_REQUEST, str(e))
        except FileNotFoundError as e:
            if e.filename == "tmux":
                self.error(HTTPStatus.INTERNAL_SERVER_ERROR, "tmux is not installed on this host")
            else:
                raise
        except Exception as e:
            traceback.print_exc()
            self.error(HTTPStatus.INTERNAL_SERVER_ERROR, f"{type(e).__name__}: {e}")

    def do_GET(self):
        self.dispatch("GET")

    def do_POST(self):
        self.dispatch("POST")

    def get_routes(self, parts, query, body):
        match parts:
            case [""]:
                self.handle_req(HTTPStatus.OK, (HERE / "index.html").read_bytes(),
                                "text/html; charset=utf-8")
            case ["api", "ping"]:
                self.send_json(HTTPStatus.OK, {"ok": True})
            case ["api", "options"]:
                self.send_json(HTTPStatus.OK, {"ok": True, **campaign.options(),
                                               "host": socket.gethostname()})
            case ["api", "jobs"]:
                sessions = jobs.tmux_sessions()
                job_list = jobs.list_jobs(JOBS_DIR, sessions)
                job_list.reverse()                                  # newest first
                self.send_json(HTTPStatus.OK, {
                    "ok": True,
                    "jobs": job_list,
                    "worker": jobs.WORKER_SESSION in sessions,
                    "lock_busy": jobs.lock_busy(LOCK),
                    "repo_changes": jobs.repo_changes(REPO),
                })
            case ["api", "jobs", job_id, "log"]:
                self.send_log(job_id, query)
            case _:
                self.error(HTTPStatus.NOT_FOUND, "not found")

    def post_routes(self, parts, query, body):
        match parts:
            case ["api", "jobs"]:
                command, title, estimate, params = campaign.build(self.parse_body(body))
                job_id = jobs.create_job(JOBS_DIR, REPO, command,
                                         {"title": title, "params": params, "estimate_s": estimate})
                try:
                    ensure_worker()
                except Exception as e:
                    print(f"cannot start the worker: {e}", file=sys.stderr, flush=True)
                self.send_json(HTTPStatus.CREATED, {"ok": True, "id": job_id, "title": title})
            case ["api", "jobs", "preview"]:
                command, title, estimate, _ = campaign.build(self.parse_body(body))
                self.send_json(HTTPStatus.OK, {"ok": True, "command": command, "title": title,
                                               "estimate_s": estimate})
            case ["api", "jobs", job_id, "stop"]:
                self.stop_job(job_id)
            case ["api", "jobs", job_id, "cancel"]:
                self.cancel_job(job_id)
            case _:
                self.error(HTTPStatus.NOT_FOUND, "not found")

    @staticmethod
    def parse_body(body):
        try:
            return json.loads(body or b"{}")
        except json.JSONDecodeError as e:
            raise campaign.BadRequest(f"the body is not valid JSON: {e}")

    # --- job actions ---

    def send_log(self, job_id, query):
        job_dir = jobs.find_job(JOBS_DIR, job_id)
        if job_dir is None:
            return self.error(HTTPStatus.NOT_FOUND, "no such job")
        try:
            offset = int(query.get("offset", ["0"])[0])
        except ValueError:
            return self.error(HTTPStatus.BAD_REQUEST, "offset must be an integer")
        if offset < 0:
            return self.error(HTTPStatus.BAD_REQUEST, "offset must be >= 0")
        # Byte offsets: the client keeps the returned offset and asks for what came after it.
        chunk = b""
        try:
            with open(job_dir / "log", "rb") as f:
                f.seek(offset)
                chunk = f.read(LOG_CHUNK)
        except FileNotFoundError:
            pass
        sessions = jobs.tmux_sessions()
        self.send_json(HTTPStatus.OK, {
            "ok": True,
            "data": chunk.decode("utf-8", errors="replace"),
            "offset": offset + len(chunk),
            "more": len(chunk) == LOG_CHUNK,
            "state": jobs.job_state(job_dir, sessions),
        })

    def stop_job(self, job_id):
        """Ctrl-C in the job's session, as if typed after tmux attach. lg_campaign.sh does not
        commit a campaign stopped this way."""
        job_dir = jobs.find_job(JOBS_DIR, job_id)
        if job_dir is None:
            return self.error(HTTPStatus.NOT_FOUND, "no such job")
        if jobs.job_state(job_dir, jobs.tmux_sessions()) != jobs.RUNNING:
            return self.error(HTTPStatus.CONFLICT, "the job is not running")
        result = subprocess.run(["tmux", "send-keys", "-t", f"={jobs.session_name(job_id)}:", "C-c"],
                                capture_output=True, text=True)
        if result.returncode != 0:
            return self.error(HTTPStatus.INTERNAL_SERVER_ERROR, result.stderr.strip())
        self.send_json(HTTPStatus.OK, {"ok": True})

    def cancel_job(self, job_id):
        """Mark a queued job cancelled. The worker writes 'started' and then checks 'cancelled';
        this writes 'cancelled' and then checks 'started' - so at least one of them sees the
        other, and a job is never both reported cancelled and started unnoticed."""
        job_dir = jobs.find_job(JOBS_DIR, job_id)
        if job_dir is None:
            return self.error(HTTPStatus.NOT_FOUND, "no such job")
        if jobs.job_state(job_dir, jobs.tmux_sessions()) != jobs.QUEUED:
            return self.error(HTTPStatus.CONFLICT, "only a queued job can be cancelled")
        (job_dir / jobs.CANCELLED).touch()
        if (job_dir / jobs.STARTED).exists():
            return self.error(HTTPStatus.CONFLICT, "the worker has just started the job; stop it instead")
        self.send_json(HTTPStatus.OK, {"ok": True})


if __name__ == "__main__":
    addr = os.environ.get("LG_UI_ADDR", "0.0.0.0")
    port = int(os.environ.get("LG_UI_PORT", "8080"))
    threading.Thread(target=watch_worker, daemon=True).start()
    print(f"lg_ui on http://{addr}:{port}, jobs in {JOBS_DIR}, lock {LOCK}", flush=True)
    try:
        ThreadingHTTPServer((addr, port), Handler).serve_forever()
    except KeyboardInterrupt:
        pass

import hmac, json, os
from  http.server  import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from urllib.parse import urlparse, parse_qs
from http import HTTPStatus
from datetime import datetime
import shlex
import subprocess


HERE = Path (__file__).resolve().parent
TOKEN = os.environ["LG_UI_TOKEN"]
JOBS_DIR = Path(os.environ["LG_JOBS_DIR"]).resolve()
JOBS_DIR.mkdir(parents=True, exist_ok=True)
TEST_CMD = 'for i in 1 2 3 4 5; do echo "$i"; sleep 2; done'
STARTED = "started"
DONE = "done" 
RUNNING = "running"
QUEUED = "queued"
INTERRUPTED = "interrupted"

class Handler(BaseHTTPRequestHandler):
    protocol_version="HTTP/1.1"

    def send_json(self,code, obj):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.handle_req(code,body, "application/json; charset=utf-8")

    
    def handle_req(self,code,body,type_of_demanded_resp):
        self.send_response(code)
        self.send_header("Content-Type", type_of_demanded_resp)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    
    
    def authorized(self):
        auth_token = self.headers.get("Authorization", "")
        return hmac.compare_digest(auth_token.encode(), ("Bearer "+TOKEN).encode())
    
   
    def do_GET(self):
        url = urlparse(self.path)
        if url.path.startswith("/api/") and not self.authorized():
            self.send_json(HTTPStatus.UNAUTHORIZED, {"ok": False})
            return

        if url.path == "/":
            self.handle_req(HTTPStatus.OK, (HERE/"index.html").read_bytes(),"text/html; charset=utf-8")
            return
 
        if url.path == "/api/ping":
            self.send_json(HTTPStatus.OK, {"ok":True})
            return
        self.send_json(HTTPStatus.NOT_FOUND, {"ok":False})

   
    def do_POST(self):
        url = urlparse(self.path)
        parts = url.path.strip("/").split("/")
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length)
        if url.path.startswith("/api/") and not self.authorized():
            self.send_json(HTTPStatus.UNAUTHORIZED, {"ok": False})
            return
        if parts==["api","jobs"]:
            job_id=datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
            job_dir=JOBS_DIR/job_id
            try:
                job_dir.mkdir(exist_ok=False)
                
                script = f"""cd {shlex.quote(str(job_dir))}
                {{ {TEST_CMD}; }} 2>&1 | tee log
                echo "${{PIPESTATUS[0]}}" > rc
                """
                (job_dir / "run.sh").write_text(script)
                Path(job_dir/"started").touch(exist_ok=False)
                subprocess.run(["tmux","new-session", "-d","-s",f"job-{job_id}","bash",str(job_dir/"run.sh")], check=True)
                self.send_json(HTTPStatus.CREATED, {"id": job_id})
            except FileExistsError:
                self.send_json(HTTPStatus.CONFLICT, {"ok":False, "message":"File already exist"})
            except (OSError, subprocess.CalledProcessError) as e:
                self.send_json(HTTPStatus.INTERNAL_SERVER_ERROR, {"ok": False, "message": str(e)})
            return
        self.send_json(HTTPStatus.NOT_FOUND, {"ok":False})
        
    def get_job_sessions(self):
        try:
            result = subprocess.run(["tmux", "ls", "-f", "#{m:job-*,#{session_name}}", "-F", "#{session_name}"], capture_output=True, text=True)
        except FileNotFoundError as e:
            self.send_json(HTTPStatus.INTERNAL_SERVER_ERROR, {"ok": False, "message": str(e)})
        return set(result.stdout.splitlines())

    def job_state(self, job_dir, sessions):
        files_list = os.listdir(JOBS_DIR/job_dir)
        if "rc" in files_list:
            return DONE
        
        if job_dir in sessions:
            return RUNNING
        if STARTED not in files_list:
            return QUEUED
        return INTERRUPTED

    def list_jobs(self):
        sessions = self.get_job_sessions()
        jobs_ids = os.listdir(JOBS_DIR)
        jobs=[]
        for job_id in jobs_ids:
            state = self.job_state(job_id, sessions)
            job = [job_id,state]
            if state == "done":
                job.append(Path(JOBS_DIR/job_id/"rc").read_text())
            jobs.append(job)
        return jobs
            




if __name__ == "__main__":
    addr = os.environ.get("LG_UI_ADDR", "0.0.0.0")
    port = int(os.environ.get("LG_UI_PORT", "8080"))
    ThreadingHTTPServer((addr, port), Handler).serve_forever()
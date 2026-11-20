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
                subprocess.run(["tmux","new-session", "-d","-s",f"job-{job_id}","bash",f"{job_dir}/run.sh"], check=True)
                self.send_json(HTTPStatus.CREATED, {"id": job_id})
            except FileExistsError:
                self.send_json(HTTPStatus.CONFLICT, {"ok":False, "message":"File already exist"})
            except (OSError, subprocess.CalledProcessError) as e:
                self.send_json(HTTPStatus.INTERNAL_SERVER_ERROR, {"ok": False, "message": str(e)})
            return
        self.send_json(HTTPStatus.NOT_FOUND, {"ok":False})
        

if __name__ == "__main__":
    addr = os.environ.get("LG_UI_ADDR", "0.0.0.0")
    port = int(os.environ.get("LG_UI_PORT", "8080"))
    ThreadingHTTPServer((addr, port), Handler).serve_forever()
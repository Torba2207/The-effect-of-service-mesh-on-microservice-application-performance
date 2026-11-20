import hmac, json, os
from  http.server  import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from urllib.parse import urlparse, parse_qs
from http import HTTPStatus


HERE = Path (__file__).resolve().parent
TOKEN = os.environ["LG_UI_TOKEN"]

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
        if url.path.startswith("/api/") and not self.authorized():
            self.send_json(HTTPStatus.UNAUTHORIZED, {"ok": False})
            return
        self.send_json(HTTPStatus.NOT_FOUND, {"ok":False})
        

if __name__ == "__main__":
    addr = os.environ.get("LG_UI_ADDR", "0.0.0.0")
    port = int(os.environ.get("LG_UI_PORT", "8080"))
    ThreadingHTTPServer((addr, port), Handler).serve_forever()
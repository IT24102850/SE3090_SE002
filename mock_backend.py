from http.server import BaseHTTPRequestHandler, HTTPServer
import json
class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/api/agents/create-po':
            length = int(self.headers.get('Content-Length',0))
            body = self.rfile.read(length).decode('utf-8') if length>0 else ''
            try:
                data = json.loads(body) if body else {}
            except Exception:
                data = {}
            resp = { 'number': 'MOCK-PO-' + str(12345), 'id': 999, 'items': data.get('Items', []), 'status': 'Placed' }
            self.send_response(201)
            self.send_header('Content-Type','application/json')
            self.end_headers()
            self.wfile.write(json.dumps(resp).encode('utf-8'))
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 5200), Handler)
    print('Mock backend listening on 5200')
    server.serve_forever()

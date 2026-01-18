#!/usr/bin/env python3
import http.server
import os
import socketserver
import subprocess


class NodeInfoHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        try:
            output = subprocess.check_output(
                ["/bin/bash", "/app/managedocker.sh", "list"],
                stderr=subprocess.STDOUT,
                text=True,
            )
            body = output
            status = 200
        except subprocess.CalledProcessError as exc:
            body = exc.output or str(exc)
            status = 500

        body_bytes = body.encode("utf-8", errors="replace")
        self.send_response(status)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body_bytes)))
        self.end_headers()
        self.wfile.write(body_bytes)

    def log_message(self, format, *args):
        return


class DualStackTCPServer(socketserver.TCPServer):
    allow_reuse_address = True
    address_family = socketserver.socket.AF_INET6


class IPv4TCPServer(socketserver.TCPServer):
    allow_reuse_address = True


def main():
    port = int(os.getenv("PORT0", "18080"))
    try:
        with DualStackTCPServer(("::", port), NodeInfoHandler) as httpd:
            httpd.serve_forever()
    except OSError:
        with IPv4TCPServer(("0.0.0.0", port), NodeInfoHandler) as httpd:
            httpd.serve_forever()


if __name__ == "__main__":
    main()

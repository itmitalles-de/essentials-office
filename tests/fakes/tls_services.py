#!/usr/bin/env python3
"""Loopback-only TLS fixtures for Mail and Essentials+ Calls contract tests."""

from __future__ import annotations

import http.server
import json
import os
import socketserver
import ssl
import threading
import time


CERT = os.environ["FAKE_TLS_CERT"]
KEY = os.environ["FAKE_TLS_KEY"]
PORT_FILE = os.environ["FAKE_TLS_PORT_FILE"]


class ThreadingServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = False
    daemon_threads = True


class GreetingHandler(socketserver.BaseRequestHandler):
    greeting = b""

    def handle(self) -> None:
        self.request.sendall(self.greeting)
        self.request.settimeout(1)
        try:
            self.request.recv(1024)
        except (TimeoutError, OSError):
            pass


class ImapHandler(GreetingHandler):
    greeting = b"* OK Essentials+ Office synthetic IMAP ready\r\n"


class SmtpHandler(GreetingHandler):
    greeting = b"220 mail.test.invalid ESMTP synthetic\r\n"


class HealthHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self) -> None:  # noqa: N802
        if self.path != "/health":
            self.send_error(404)
            return
        body = json.dumps({"status": "ok", "product": "Essentials+ Calls", "version": "0.0.0-test"}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_args: object) -> None:
        return


def wrap(server: ThreadingServer) -> None:
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(CERT, KEY)
    server.socket = context.wrap_socket(server.socket, server_side=True)


servers = [
    ThreadingServer(("127.0.0.1", 0), ImapHandler),
    ThreadingServer(("127.0.0.1", 0), SmtpHandler),
    ThreadingServer(("127.0.0.1", 0), HealthHandler),
]
for server in servers:
    wrap(server)
    threading.Thread(target=server.serve_forever, daemon=True).start()
with open(PORT_FILE, "x", encoding="utf-8") as destination:
    json.dump({"imap": servers[0].server_address[1], "smtp": servers[1].server_address[1], "health": servers[2].server_address[1]}, destination)
while True:
    time.sleep(60)

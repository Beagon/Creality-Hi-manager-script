#!/usr/bin/python3
# -*- coding: utf-8 -*-

import http.server
import socketserver
import http.client
import urllib.parse
import json

# =========================
# USER CONFIGURATION
# =========================
MOONRAKER_HOST = "127.0.0.1"
MOONRAKER_PORT = 7125

CONNECT_TIMEOUT = 5      # seconds for TCP connect
CHUNK_TIMEOUT   = 15     # seconds per chunk send/recv
CHUNK_SIZE      = 65536  # bytes per forwarded chunk

LISTEN_HOST = "127.0.0.1"
LISTEN_PORT = 8090
# =========================


class UploadHandler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_POST(self):
        if not self.path.startswith("/upload/"):
            self.send_error(404, "Not Found")
            return

        filename = urllib.parse.unquote(self.path.split("/upload/", 1)[1])
        if not filename:
            self.send_error(400, "Missing filename")
            return

        content_length = int(self.headers.get("Content-Length", 0))
        if content_length <= 0:
            self.send_error(400, "Missing or invalid Content-Length")
            return

        # Prepare Moonraker request
        target = f"/server/files/upload?filename={urllib.parse.quote(filename)}"
        try:
            conn = http.client.HTTPConnection(
                MOONRAKER_HOST, MOONRAKER_PORT, timeout=CONNECT_TIMEOUT
            )
            conn.connect()
            conn.sock.settimeout(CHUNK_TIMEOUT)

            # Send request headers
            conn.putrequest("POST", target)
            conn.putheader("Content-Type", self.headers.get("Content-Type"))
            conn.putheader("Content-Length", str(content_length))
            conn.endheaders()

            # Stream body in chunks
            remaining = content_length
            while remaining > 0:
                chunk = self.rfile.read(min(CHUNK_SIZE, remaining))
                if not chunk:
                    break
                conn.send(chunk)
                remaining -= len(chunk)

            # Get Moonraker response
            moon_resp = conn.getresponse()
            moon_status = moon_resp.status
            moon_resp.read()  # drain body

            # ---- always respond in Creality Print's expected JSON format ----
            if  moon_status == 201: # success
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(b'{"code":200,"message":"OK"}')
            else:
                self.send_response(502)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                error_msg = {
                    "code": 502,
                    "message": f"Moonraker error {moon_status}",
                }
                self.wfile.write(json.dumps(error_msg).encode())

        except Exception as e:
            self.send_response(502)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            error_msg = {"code": 502, "message": f"Forward failed: {str(e)}"}
            self.wfile.write(json.dumps(error_msg).encode())
        finally:
            try:
                conn.close()
            except Exception:
                pass


class ThreadedTCPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True

if __name__ == "__main__":
    with ThreadedTCPServer((LISTEN_HOST, LISTEN_PORT), UploadHandler) as httpd:
        print(f"cp_upload_shim running on {LISTEN_HOST}:{LISTEN_PORT}")
        httpd.serve_forever()

#!/usr/bin/env python3
"""Run a local BlackHole microphone and WebRTC round-trip check in Safari."""
import json
import secrets
import shutil
import subprocess
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    cli = shutil.which("microphun")
    if not cli:
        raise SystemExit("Open Microphun and add its bundled CLI to your PATH.")
    state = json.loads(subprocess.check_output([cli, "status"], text=True))
    if not state["live"] or state["send"] != "BlackHole2ch_UID":
        raise SystemExit("Start Microphun and select BlackHole 2ch under Send to calls.")

    prefix = "/" + secrets.token_urlsafe(24) + "/"

    class Page(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def reply(self, status, mime, data):
            self.send_response(status)
            self.send_header("Content-Type", mime)
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Frame-Options", "DENY")
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            if self.headers.get("Host") != host:
                return self.send_error(403)
            if self.path == prefix:
                return self.reply(200, "text/html; charset=utf-8", (ROOT / "Tests/SafariCapture.html").read_bytes())
            if self.path == prefix + "reference":
                return self.reply(200, "audio/wav", (ROOT / "Resources/Sounds/Bonk.wav").read_bytes())
            self.send_error(404)

        def do_POST(self):
            if self.headers.get("Host") != host or self.headers.get("Origin") != origin:
                return self.send_error(403)
            try:
                size = int(self.headers.get("Content-Length", 0))
                if not 0 < size <= 4096:
                    return self.send_error(400)
                data = json.loads(self.rfile.read(size))
            except (ValueError, UnicodeDecodeError):
                return self.send_error(400)
            if self.path == prefix + "play":
                # The user may have changed the route while granting browser permission.
                current = json.loads(subprocess.check_output([cli, "status"], text=True))
                if not current["live"] or current["send"] != "BlackHole2ch_UID":
                    return self.reply(409, "text/plain", b"Microphun needs a live BlackHole send.")
                try:
                    subprocess.run([cli, "play", "Bonk"], capture_output=True, check=True, timeout=10)
                except (subprocess.SubprocessError, OSError):
                    return self.reply(500, "text/plain", b"Microphun could not play the Bonk.")
            elif self.path == prefix + "result":
                print(json.dumps(data, indent=2), flush=True)
            else:
                return self.send_error(404)
            self.reply(200, "application/json", b"{}")

    with ThreadingHTTPServer(("127.0.0.1", 0), Page) as server:
        host = f"127.0.0.1:{server.server_port}"
        origin = "http://" + host
        url = origin + prefix
        print(f"Safari audio check is ready at {url}\nPress Control-C to close it.", flush=True)
        subprocess.run(["open", "-a", "Safari", url], check=True)
        server.timeout = 1
        end = time.monotonic() + 1200
        while time.monotonic() < end:
            server.handle_request()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass

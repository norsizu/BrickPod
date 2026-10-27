#!/usr/bin/env python3
"""Local server for the offline Apple Music 404 iPod mirror.

- SPA fallback: any unknown path serves the app shell (like the real site),
  so every "not found" URL shows the iPod.
- HTTP Range support: audio files can seek/pause properly (matters once you
  point previewUrl at your own local music).
"""
import http.server
import os
import re
import socketserver
import sys
from urllib.parse import unquote

ROOT = os.path.dirname(os.path.abspath(__file__))
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
SHELL_PATH = "/us/new/1122/index.html"


class RangeFile:
    """File wrapper that limits reads to a byte range, then closes cleanly."""

    def __init__(self, f, remaining):
        self.f = f
        self.remaining = remaining

    def read(self, n=-1):
        if self.remaining <= 0:
            return b""
        if n < 0 or n > self.remaining:
            n = self.remaining
        data = self.f.read(n)
        self.remaining -= len(data)
        return data

    def close(self):
        self.f.close()


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def send_head(self):
        path = unquote(self.path.split("?")[0])
        if path == "/":  # 根路径直接给播放器 widget
            self.path = "/widget.html"
            return super().send_head()
        fs_path = os.path.normpath(os.path.join(ROOT, path.lstrip("/")))
        if os.path.isfile(fs_path) and fs_path.startswith(ROOT):
            size = os.path.getsize(fs_path)
            f = open(fs_path, "rb")
            m = re.match(r"bytes=(\d*)-(\d*)", self.headers.get("Range") or "")
            if m and (m.group(1) or m.group(2)):
                start = int(m.group(1) or 0)
                end = min(int(m.group(2)) if m.group(2) else size - 1, size - 1)
                if start > end:
                    f.close()
                    self.send_error(416)
                    return None
                f.seek(start)
                self.send_response(206)
                self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
                self.send_header("Content-Length", str(end - start + 1))
                self.send_header("Accept-Ranges", "bytes")
                self.send_header("Content-Type", self.guess_type(fs_path))
                self.end_headers()
                return RangeFile(f, end - start + 1)
            self.send_response(200)
            self.send_header("Content-Length", str(size))
            self.send_header("Accept-Ranges", "bytes")
            self.send_header("Content-Type", self.guess_type(fs_path))
            self.end_headers()
            return f

        last = path.rstrip("/").rsplit("/", 1)[-1]
        asset_like = ("." in last or path.startswith(
            ("/assets/", "/includes/", "/static-commerce/", "/music/")))
        if asset_like:
            self.send_error(404)  # 资源缺失要真 404，别用 HTML 兜底掩盖
            return None
        # SPA fallback: unknown route -> app shell (renders the iPod 404)
        self.path = SHELL_PATH
        return super().send_head()


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


if __name__ == "__main__":
    print(f"Serving iPod mirror at http://localhost:{PORT}{SHELL_PATH}")
    try:
        with Server(("127.0.0.1", PORT), Handler) as httpd:
            httpd.serve_forever()
    except KeyboardInterrupt:
        pass

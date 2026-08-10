"""Web 静态服务（Godot 导出产物）：
1) gzip 预压缩支持：请求 .wasm/.pck/.js 时若存在同名 .gz 文件且客户端 Accept-Encoding 含 gzip，
   直接返回 .gz 内容并带 Content-Encoding: gzip（浏览器自动解压，无需改 Godot 产物）。
2) 缓存策略（2026-08-10 修正）：此前大文件设 immutable 导致浏览器缓存旧 pck/wasm 不更新——
   改为 ETag 校验 + no-cache：每次请求带 If-None-Match，内容没变返回 304（秒开），
   内容变了（重新导出）立即拿到新版。不再用固定 max-age。
3) 用法：python tools/scripts/web_serve.py [port]  （默认 8125，仅绑定 127.0.0.1）
"""

import gzip
import hashlib
import http.server
import mimetypes
import os
import socketserver
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "export", "web"))

LARGE_EXTS = {".wasm", ".pck", ".worklet.js", ".audio.worklet.js"}
GZIP_EXTS = {".wasm", ".pck", ".js"}


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def end_headers(self) -> None:
        # 统一 no-cache + ETag：强缓存曾导致导出后浏览器继续用旧 pck/wasm
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def translate_path(self, path: str) -> str:
        # 保留 SimpleHTTPRequestHandler 的路径解析（含 URL 解码、防穿越）
        return super().translate_path(path)

    def _serve_gzip(self, fs_path: str) -> bool:
        """若存在 fs_path + '.gz' 且客户端支持 gzip，则返回压缩内容。"""
        gz_path = fs_path + ".gz"
        if not os.path.isfile(gz_path):
            return False
        accept = self.headers.get("Accept-Encoding", "")
        if "gzip" not in accept:
            return False
        try:
            with open(gz_path, "rb") as f:
                data = f.read()
        except OSError:
            return False
        # ETag：基于文件 mtime+size，重新导出后立即变化
        st = os.stat(gz_path)
        etag = '"%x-%x"' % (st.st_mtime_ns, st.st_size)
        inm = self.headers.get("If-None-Match", "")
        if inm == etag:
            self.send_response(304)
            self.end_headers()
            return True
        ctype = mimetypes.guess_type(fs_path)[0] or "application/octet-stream"
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Encoding", "gzip")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("ETag", etag)
        self.end_headers()
        self.wfile.write(data)
        return True

    def do_GET(self) -> None:
        fs_path = self.translate_path(self.path.split("?")[0])
        if os.path.isfile(fs_path) and self._serve_gzip(fs_path):
            return
        # 非 gzip 路径：统一 ETag（If-None-Match → 304），防止缓存旧版
        if os.path.isfile(fs_path):
            st = os.stat(fs_path)
            etag = '"%x-%x"' % (st.st_mtime_ns, st.st_size)
            if self.headers.get("If-None-Match", "") == etag:
                self.send_response(304)
                self.end_headers()
                return
            # 先经由 SimpleHTTPRequestHandler 发送 200 头，再补 ETag 头
            class _Wrap:
                pass
            original_end = self.end_headers

            def _end_with_etag() -> None:
                self.send_header("ETag", etag)
                original_end()

            self.end_headers = _end_with_etag  # type: ignore[method-assign]
            super().do_GET()
            return
        super().do_GET()


class ThreadingServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def main() -> None:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8125
    os.makedirs(ROOT, exist_ok=True)
    with ThreadingServer(("127.0.0.1", port), Handler) as httpd:
        print(f"[web_serve] http://127.0.0.1:{port}/  (root={ROOT})")
        httpd.serve_forever()


if __name__ == "__main__":
    main()

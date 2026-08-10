"""no-cache 静态服务：Godot Web 导出测试用（pck/wasm 更新后浏览器强刷才有效）。

python http.server 不发送 Cache-Control，浏览器会启发式缓存 index.pck，
导致 ?v=N 只刷新 html、pck 仍命中旧缓存（表现为字体/资源还是旧版）。
本服务对所有响应附加 Cache-Control: no-cache。

用法：python tools/scripts/serve_web.py [port] [directory]
"""

import functools
import http.server
import os
import sys


class NoCacheHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        super().end_headers()

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8125
    directory = sys.argv[2] if len(sys.argv) > 2 else "export/web"
    directory = os.path.abspath(directory)
    handler = functools.partial(NoCacheHandler, directory=directory)
    with http.server.ThreadingHTTPServer(("127.0.0.1", port), handler) as httpd:
        print(f"serving {directory} on http://127.0.0.1:{port} (no-cache)", flush=True)
        httpd.serve_forever()


if __name__ == "__main__":
    main()

"""Resume-capable HTTP downloader (for large GitHub release files).

Usage:
    python tools/scripts/download_resume.py <url> <dest> [--proxy http://127.0.0.1:7890]
"""

import argparse
import os
import ssl
import sys
import time
import urllib.request


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("url")
    ap.add_argument("dest")
    ap.add_argument("--proxy", default="")
    args = ap.parse_args()

    ctx = ssl.create_default_context()
    if args.proxy:
        ph = urllib.request.ProxyHandler({"http": args.proxy, "https": args.proxy})
    else:
        ph = urllib.request.ProxyHandler({})
    op = urllib.request.build_opener(ph, urllib.request.HTTPSHandler(context=ctx))

    os.makedirs(os.path.dirname(os.path.abspath(args.dest)), exist_ok=True)
    existing = os.path.getsize(args.dest) if os.path.exists(args.dest) else 0
    max_retries = 8

    for attempt in range(1, max_retries + 1):
        headers = {"User-Agent": "codex"}
        if existing:
            headers["Range"] = f"bytes={existing}-"
        req = urllib.request.Request(args.url, headers=headers)
        try:
            with op.open(req, timeout=120) as r:
                total = int(r.headers.get("Content-Length", 0)) + existing
                status = getattr(r, "status", 200)
                if status == 206 or existing:
                    mode = "ab"
                else:
                    mode = "wb"
                    existing = 0
                with open(args.dest, mode) as f:
                    done = existing
                    while True:
                        chunk = r.read(1 << 20)
                        if not chunk:
                            break
                        f.write(chunk)
                        done += len(chunk)
                        if done % (100 << 20) < (1 << 20):
                            print(f"  {done/1e6:.0f}/{total/1e6:.0f} MB", flush=True)
                print(f"[ok] {args.dest}: {done/1e6:.1f} MB")
                return 0
        except Exception as e:
            existing = os.path.getsize(args.dest)
            print(f"[retry {attempt}/{max_retries}] {type(e).__name__}: {e} (saved {existing/1e6:.0f} MB)", flush=True)
            time.sleep(3)
    print("download failed after retries")
    return 1


if __name__ == "__main__":
    sys.exit(main())

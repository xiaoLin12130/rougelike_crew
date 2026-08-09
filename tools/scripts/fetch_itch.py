"""itch.io asset downloader (slow, cookie-session, cached).

Usage:
    python tools/scripts/fetch_itch.py https://cupnooble.itch.io/sprout-lands-asset-pack

Mechanism: game page -> csrf + upload_id -> POST /download_url/{id} -> JSON url -> download.
Rate-limited: ~25s between requests (itch.io 429s aggressively).
"""

import http.cookiejar
import json
import os
import re
import ssl
import sys
import time
import urllib.parse
import urllib.request

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CACHE = os.path.join(ROOT, ".tools", "research_cache")
OUT = os.path.join(ROOT, ".tools", "itch_downloads")
os.makedirs(CACHE, exist_ok=True)
os.makedirs(OUT, exist_ok=True)

CTX = ssl.create_default_context()
PH = urllib.request.ProxyHandler(
    {"http": "http://127.0.0.1:7890", "https": "http://127.0.0.1:7890"})
CJ = http.cookiejar.CookieJar()
OP = urllib.request.build_opener(PH, urllib.request.HTTPCookieProcessor(CJ),
                                 urllib.request.HTTPSHandler(context=CTX))
HDRS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                  "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
    "Referer": "https://itch.io/",
}
LAST = 0.0


def _throttle(seconds: float = 25.0):
    global LAST
    wait = seconds - (time.time() - LAST)
    if wait > 0:
        print(f"  [throttle] {wait:.0f}s", flush=True)
        time.sleep(wait)
    LAST = time.time()


def _req(url: str, data: bytes = None, retries: int = 4):
    for attempt in range(retries):
        _throttle(30.0 if attempt > 0 else 20.0)
        headers = dict(HDRS)
        if data:
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        req = urllib.request.Request(url, headers=headers, data=data)
        try:
            r = OP.open(req, timeout=40)
            return r, r.read()
        except urllib.error.HTTPError as e:
            if e.code == 429:
                print(f"  [429] retry {attempt + 1}/{retries}", flush=True)
                time.sleep(45)
                continue
            raise
    raise RuntimeError("rate limited out")


def download_game(game_url: str) -> None:
    slug = game_url.rstrip("/").split("/")[-1]
    print(f"[1/4] fetch page {game_url}")
    _, page = _req(game_url)
    text = page.decode("utf-8", "replace")
    with open(os.path.join(CACHE, f"itch_{slug}.html"), "w", encoding="utf-8") as f:
        f.write(text)

    csrf_m = re.search(r'name="csrf_token" value="([^"]+)"', text)
    csrf = csrf_m.group(1) if csrf_m else None
    if not csrf:
        print("[FAIL] no csrf token on page")
        return
    print(f"  csrf: {csrf[:30]}...")

    # upload id: 常见于 data-upload-id 或 window.itch.uploads
    upload_id = None
    m = re.search(r'data-upload-id="(\d+)"', text)
    if m:
        upload_id = m.group(1)
    if not upload_id:
        m = re.search(r"upload_list_(\d+)", text)
        if m:
            upload_id = m.group(1)
    if not upload_id:
        m = re.search(r'"id"\s*:\s*(\d+)[^}]{0,120}"filename"', text)
        if m:
            upload_id = m.group(1)
    if not upload_id:
        print("[FAIL] no upload_id found (page may need JS/login)")
        return
    print(f"  upload_id: {upload_id}")

    # POST download_url
    base = urllib.parse.urlparse(game_url)
    post_url = f"{base.scheme}://{base.netloc}/download_url/{upload_id}"
    body = urllib.parse.urlencode({"csrf_token": csrf}).encode()
    print(f"[2/4] POST {post_url}")
    _, resp = _req(post_url, body)
    try:
        data = json.loads(resp.decode("utf-8", "replace"))
        dl_url = data.get("url")
        if not dl_url:
            print("[FAIL] response:", str(data)[:300])
            return
    except Exception as e:
        print("[FAIL] json:", resp[:300], e)
        return
    print(f"[3/4] download {dl_url[:100]}")
    _, blob = _req(dl_url)
    fname = data.get("filename") or (slug + ".zip")
    fname = os.path.basename(fname)
    dst = os.path.join(OUT, fname)
    with open(dst, "wb") as f:
        f.write(blob)
    print(f"[4/4] saved {dst} ({len(blob)/1e6:.1f} MB)")
    print("  -> move to .tools/user_assets/ then run: python tools/scripts/fetch_assets.py scan_user_assets")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return
    download_game(sys.argv[1])


if __name__ == "__main__":
    main()

"""Asset acquisition tools:
1) fetch_kenney <slug>: auto-download a Kenney.nl CC0 pack (direct link parsing).
2) scan_user_assets: inventory zips dropped in .tools/user_assets/ (PIL stats).
3) list_kenney <query>: search available Kenney packs (page crawl, no download).

Usage:
    python tools/scripts/fetch_assets.py fetch_kenney rpg-urban-pack
    python tools/scripts/fetch_assets.py scan_user_assets
"""

import os
import re
import shutil
import ssl
import sys
import urllib.parse
import urllib.request
import zipfile
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
TOOLS = os.path.join(ROOT, ".tools")
USER_ASSETS = os.path.join(TOOLS, "user_assets")

CTX = ssl.create_default_context()
PROXY = urllib.request.ProxyHandler(
    {"http": "http://127.0.0.1:7890", "https": "http://127.0.0.1:7890"})
OP = urllib.request.build_opener(PROXY, urllib.request.HTTPSHandler(context=CTX))
HDRS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                  "(KHTML, like Gecko) Chrome/126.0 Safari/537.36",
}


def _get(url: str, binary: bool = False):
    req = urllib.request.Request(url, headers=HDRS)
    r = OP.open(req, timeout=60)
    data = r.read()
    return data if binary else data.decode("utf-8", "replace")


def fetch_kenney(slug: str) -> None:
    """Download a Kenney pack (CC0) via its page's direct zip link."""
    page = _get(f"https://kenney.nl/assets/{slug}")
    m = re.search(r"href='(https://kenney\.nl/media/pages/assets/[^']+\.zip)'", page)
    if not m:
        print(f"[FAIL] no download link for {slug}")
        return
    url = m.group(1)
    dst = os.path.join(TOOLS, f"kenney_{slug}.zip")
    if not os.path.exists(dst):
        print(f"[down] {url}")
        data = _get(url, binary=True)
        with open(dst, "wb") as f:
            f.write(data)
    out = os.path.join(TOOLS, f"kenney_{slug}")
    os.makedirs(out, exist_ok=True)
    with zipfile.ZipFile(dst) as z:
        z.extractall(out)
    n = sum(len(files) for _, _, files in os.walk(out))
    print(f"[ok] {slug}: {n} files -> {out}")
    print("      license: CC0 (verify License.txt in pack)")


def scan_user_assets() -> None:
    """Inventory user-dropped zips (PIL stats) and print a usage report."""
    os.makedirs(USER_ASSETS, exist_ok=True)
    zips = [f for f in os.listdir(USER_ASSETS) if f.lower().endswith(".zip")]
    if not zips:
        print(f"[info] no zips in {USER_ASSETS}. Drop asset zips here and rerun.")
        return
    for zp in zips:
        print(f"\n=== {zp} ===")
        out = os.path.join(USER_ASSETS, os.path.splitext(zp)[0])
        with zipfile.ZipFile(os.path.join(USER_ASSETS, zp)) as z:
            z.extractall(out)
        pngs = []
        for dp, _, fns in os.walk(out):
            for fn in fns:
                if fn.lower().endswith(".png"):
                    pngs.append(os.path.join(dp, fn))
        sizes = {}
        for p in pngs[:200]:
            try:
                with Image.open(p) as im:
                    sizes[im.size] = sizes.get(im.size, 0) + 1
            except Exception:
                pass
        print(f"  files: {sum(len(f) for _, _, f in os.walk(out))}, png: {len(pngs)}")
        print("  common sizes:", sorted(sizes.items(), key=lambda x: -x[1])[:8])
        lic = [os.path.join(dp, f) for dp, _, fns in os.walk(out)
               for f in fns if "license" in f.lower() or "readme" in f.lower()]
        for p in lic[:3]:
            try:
                head = " ".join(open(p, encoding="utf-8", errors="replace").read().split())[:200]
                print(f"  license: {os.path.relpath(p, out)}: {head}")
            except Exception:
                pass
        if not lic:
            print("  [warn] no license file - verify before commercial use!")


def list_kenney(query: str = "") -> None:
    """List Kenney packs matching query (crawl index page)."""
    page = _get("https://kenney.nl/assets")
    links = re.findall(r'href="/assets/([a-z0-9-]+)"', page)
    packs = sorted(set(links))
    if query:
        packs = [p for p in packs if query.lower() in p]
    print(f"Kenney packs ({len(packs)}):")
    for p in packs:
        print("  ", p)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return
    cmd = sys.argv[1]
    if cmd == "fetch_kenney" and len(sys.argv) > 2:
        fetch_kenney(sys.argv[2])
    elif cmd == "scan_user_assets":
        scan_user_assets()
    elif cmd == "list_kenney":
        list_kenney(sys.argv[2] if len(sys.argv) > 2 else "")
    else:
        print(__doc__)


if __name__ == "__main__":
    main()

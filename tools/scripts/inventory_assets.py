"""Inventory the free asset packs under H:\\job_prep (sizes, counts, licenses).

Usage:
    python tools/scripts/inventory_assets.py
"""

import os
from PIL import Image

BASE = r"H:\job_prep"
ASSET_DIR = os.path.join(BASE, "\u514d\u8d39\u7d20\u6750")  # 免费素材


def summarize(pack: str, max_list: int = 14):
    root = os.path.join(ASSET_DIR, pack)
    if not os.path.isdir(root):
        print(f"[{pack}] MISSING ({root})")
        return
    files = []
    for dp, _, fns in os.walk(root):
        for fn in fns:
            if fn.lower().endswith((".png", ".svg", ".ogg", ".wav", ".mp3", ".ttf", ".xml")):
                files.append(os.path.join(dp, fn))
    pngs = [f for f in files if f.lower().endswith(".png")]
    svgs = [f for f in files if f.lower().endswith(".svg")]
    sfx = [f for f in files if f.lower().endswith((".ogg", ".wav", ".mp3"))]
    sizes = {}
    for f in pngs[:120]:
        try:
            with Image.open(f) as im:
                sizes[im.size] = sizes.get(im.size, 0) + 1
        except Exception:
            pass
    total_bytes = sum(os.path.getsize(f) for f in files)
    print(f"\n=== {pack} ===")
    print(
        f"files: {len(files)} | png: {len(pngs)} | svg: {len(svgs)} "
        f"| sfx: {len(sfx)} | total: {total_bytes/1e6:.1f} MB"
    )
    print("common png sizes:", sorted(sizes.items(), key=lambda x: -x[1])[:8])
    subs = sorted({os.path.relpath(os.path.dirname(f), root) for f in files})
    print("dirs:", subs[:max_list])


def licenses():
    for pack in os.listdir(ASSET_DIR):
        root = os.path.join(ASSET_DIR, pack)
        if not os.path.isdir(root):
            continue
        for dp, _, fns in os.walk(root):
            for fn in fns:
                if "license" in fn.lower() or "readme" in fn.lower():
                    fp = os.path.join(dp, fn)
                    try:
                        txt = open(fp, encoding="utf-8", errors="replace").read()
                        head = " ".join(txt.split())[:280]
                        print(f"\n[license] {pack}/{os.path.relpath(fp, root)}: {head}")
                    except Exception as e:
                        print(f"[license] {fp}: ERR {e}")


if __name__ == "__main__":
    print("ASSET_DIR exists:", os.path.isdir(ASSET_DIR))
    for p in os.listdir(ASSET_DIR):
        print(" pack dir:", p)
    for p in [
        "Ninja Adventure",
        "Sunny Land",
        "Space Shooter Redux",
        "Platformer Art Complete Pack",
        "Platformer Art Deluxe",
        "Game Icons",
    ]:
        summarize(p)
    licenses()

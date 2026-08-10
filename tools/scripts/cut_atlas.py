#!/usr/bin/env python3
"""cut_atlas.py - auto-detect a sprite-sheet grid and cut it into PNGs.

Grid detection is based on the non-transparent pixel distribution:

  1. Compute row/column content profiles (opaque pixel counts per line).
  2. Candidate cell pitches are the divisors of the axis size within
     [MIN_PITCH, MAX_PITCH]; they are ranked by normalized autocorrelation
     confidence.  When the other axis found a confident pitch, it is tried
     first (uniform sheets share the cell pitch on both axes).
  3. For each candidate, the grid origin is scored by summing the minimum
     profile near each grid line, then every grid line is snapped to the
     local profile minimum within +/-4 px ("waist" refinement) so cuts land
     in the thin parts between touching icons.
  4. A candidate is accepted when most content segments are ~k*pitch long
     (>= 80%) or most refined cut lines sit in empty rows/columns
     (>= 50%).  Otherwise the axis falls back to plain content-segment
     boundaries (small sparse segments are merged into their neighbours).

Cells whose opaque-pixel ratio is <= --min-content are skipped.

The script is deterministic and idempotent: rerunning it on the same inputs
reproduces identical files, and stale outputs matching the naming pattern
are removed.

Usage:
  python tools/scripts/cut_atlas.py atlas.png [...] --out DIR \
      [--name grid|seq] [--prefix NAME] [--min-content 0.05] [--pitch N]

  --name grid  -> {prefix}_r{row}_c{col}.png   (row/col over all grid cells)
  --name seq   -> {stem}_{n}.png               (n = 0-based row-major order
                  over kept cells; a single kept cell is saved as {stem}.png)
"""

import argparse
import glob
import os
import sys

import numpy as np
from PIL import Image

MIN_PITCH = 12
MAX_PITCH = 96
PITCH_TOL = 8          # allowed deviation of a segment size from k*pitch
CONF_MIN = 0.65        # autocorrelation confidence for cross-axis pitch use


def load_rgba(path):
    im = Image.open(path)
    if im.mode != "RGBA":
        im = im.convert("RGBA")
    return im, np.asarray(im)


def runs(mask):
    """Contiguous True runs as (start, end) inclusive."""
    segs = []
    start = None
    for i, v in enumerate(mask):
        if v and start is None:
            start = i
        elif not v and start is not None:
            segs.append((start, i - 1))
            start = None
    if start is not None:
        segs.append((start, len(mask) - 1))
    return segs


def merge_strays(segs, prof, size):
    """Merge tiny, sparse segments into their nearest neighbour."""
    merged = list(segs)
    changed = True
    while changed:
        changed = False
        i = 0
        while i < len(merged):
            s, e = merged[i]
            if e - s + 1 <= 3 and int(prof[s : e + 1].max()) < 0.05 * size:
                best_j, best_d = None, None
                for j in range(len(merged)):
                    if j == i:
                        continue
                    sj, ej = merged[j]
                    d = abs(s - ej - 1) if sj > s else abs(sj - e - 1)
                    if best_d is None or d < best_d:
                        best_d, best_j = d, j
                ns = min(s, merged[best_j][0])
                ne = max(e, merged[best_j][1])
                merged[best_j] = (ns, ne)
                del merged[i]
                changed = True
            else:
                i += 1
    return merged


def autocorr_conf(prof, size, k):
    """Normalized autocorrelation of the profile at lag k."""
    p = prof - prof.mean()
    n = size - k
    a = p[:n]
    b = p[k:]
    denom = float(np.sqrt((a * a).sum() * (b * b).sum()))
    if denom <= 0:
        return 0.0
    return float((a * b).sum()) / denom


def pitch_align_frac(segs, pitch):
    """Fraction of content segments roughly k*pitch long."""
    if not segs:
        return 0.0
    ok = 0
    for s, e in segs:
        ln = e - s + 1
        r = ln % pitch
        if min(r, pitch - r) <= PITCH_TOL:
            ok += 1
    return ok / len(segs)


def build_grid(prof, size, pitch, refine=4):
    """Score origins, then snap every grid line to a local profile minimum."""
    best_o, best_score = 0, None
    for o in range(pitch):
        score = 0
        for k in range(o, size, pitch):
            lo, hi = max(0, k - 2), min(size - 1, k + 2)
            score += int(prof[lo : hi + 1].min())
        if best_score is None or score < best_score:
            best_score, best_o = score, o
    lines = []
    for k in range(best_o, size, pitch):
        lo, hi = max(0, k - refine), min(size - 1, k + refine)
        lines.append(int(lo + np.argmin(prof[lo : hi + 1])))
    return lines


def segment_cuts(merged):
    cuts = []
    for (s1, e1), (s2, e2) in zip(merged, merged[1:]):
        gap = s2 - e1 - 1
        if gap >= 2:
            cuts.append((e1 + 1 + s2) // 2)
        else:
            cuts.append(s2)
    return cuts


def detect_axis(prof, size, cross_pitch=None, cross_conf=0.0):
    """Return (boundaries list incl. 0 and size, pitch, mode label)."""
    segs = runs(prof > 0)
    merged = merge_strays(segs, prof, size)
    divisors = [
        d
        for d in range(MIN_PITCH, min(MAX_PITCH, size // 2) + 1)
        if size % d == 0
    ]
    ranked = []  # (pitch, autocorr confidence)
    for d in divisors:
        ranked.append((d, autocorr_conf(prof, size, d)))
    ranked.sort(key=lambda t: (-t[1], t[0]))

    candidates = []
    if cross_pitch and cross_conf >= CONF_MIN:
        best_own = ranked[0][1] if ranked else 0.0
        if cross_conf >= max(CONF_MIN, best_own - 0.1):
            candidates.append(cross_pitch)
    for d, _c in ranked:
        candidates.append(d)

    for pitch in candidates:
        lines = build_grid(prof, size, pitch)
        if len(lines) < 2:
            continue
        zf = sum(1 for c in lines if int(prof[c]) == 0) / len(lines)
        if pitch_align_frac(merged, pitch) >= 0.8 or zf >= 0.5:
            bounds = sorted(set([0] + lines + [size]))
            return bounds, pitch, "grid"
    cuts = segment_cuts(merged)
    bounds = sorted(set([0] + cuts + [size]))
    return bounds, None, "segments"


def sanitize_stem(name):
    stem = os.path.splitext(os.path.basename(name))[0]
    return "".join(ch if ch.isalnum() or ch in "-_" else "_" for ch in stem)


def cut_image(path, out_dir, name_mode, prefix, min_content):
    img, arr = load_rgba(path)
    alpha = arr[:, :, 3]
    h, w = alpha.shape
    rp = alpha.sum(axis=1)
    cp = alpha.sum(axis=0)

    # X axis first (its periodicity is usually cleanest), then Y using X's
    # pitch as a cross-axis hint (uniform sheets share the cell pitch).
    xb, xpitch, xmode = detect_axis(cp, w)
    xconf = autocorr_conf(cp, w, xpitch) if xpitch else 0.0
    yb, ypitch, ymode = detect_axis(rp, h, cross_pitch=xpitch, cross_conf=xconf)

    rows = [(yb[i], yb[i + 1]) for i in range(len(yb) - 1)]
    cols = [(xb[i], xb[i + 1]) for i in range(len(xb) - 1)]

    kept = []  # (row_idx, col_idx, bbox)
    for ri, (y0, y1) in enumerate(rows):
        if y1 <= y0:
            continue
        for ci, (x0, x1) in enumerate(cols):
            if x1 <= x0:
                continue
            block = alpha[y0:y1, x0:x1]
            ratio = float((block > 0).mean())
            if ratio > min_content:
                kept.append((ri, ci, (x0, y0, x1, y1)))

    stem = sanitize_stem(path)
    written = []
    for n, (ri, ci, box) in enumerate(kept):
        if name_mode == "grid":
            fname = "%s_r%d_c%d.png" % (prefix, ri, ci)
        elif len(kept) == 1:
            fname = stem + ".png"
        else:
            fname = "%s_%d.png" % (stem, n)
        crop = img.crop((box[0], box[1], box[2], box[3]))
        crop.save(os.path.join(out_dir, fname))
        written.append(fname)

    return {
        "file": os.path.basename(path),
        "size": "%dx%d" % (w, h),
        "cells": "%dx%d" % (len(cols), len(rows)),
        "y_mode": ymode,
        "y_pitch": ypitch,
        "x_mode": xmode,
        "x_pitch": xpitch,
        "kept": len(kept),
        "written": written,
    }


def cleanup_stale(out_dir, pattern):
    for pat in (pattern, pattern + ".import"):
        for f in glob.glob(os.path.join(out_dir, pat)):
            try:
                os.remove(f)
            except OSError:
                pass


def main():
    ap = argparse.ArgumentParser(description="Cut sprite-sheet atlas into PNGs.")
    ap.add_argument("inputs", nargs="+", help="atlas image(s)")
    ap.add_argument("--out", required=True, help="output directory")
    ap.add_argument(
        "--name",
        choices=("grid", "seq"),
        default="seq",
        help="naming mode (default: seq)",
    )
    ap.add_argument("--prefix", default=None, help="name prefix for grid mode")
    ap.add_argument("--min-content", type=float, default=0.05)
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    for path in args.inputs:
        prefix = args.prefix or sanitize_stem(path)
        stem = sanitize_stem(path)
        if args.name == "seq":
            cleanup_stale(args.out, stem + "_*.png")
            cleanup_stale(args.out, stem + ".png")
        else:
            cleanup_stale(args.out, prefix + "_r*_c*.png")
        info = cut_image(path, args.out, args.name, prefix, args.min_content)
        print(
            "%s: %s -> %d icons [cells %s, y:%s%s x:%s%s]"
            % (
                info["file"],
                info["size"],
                info["kept"],
                info["cells"],
                info["y_mode"],
                (" p%d" % info["y_pitch"]) if info["y_pitch"] else "",
                info["x_mode"],
                (" p%d" % info["x_pitch"]) if info["x_pitch"] else "",
            )
        )


if __name__ == "__main__":
    sys.exit(main())

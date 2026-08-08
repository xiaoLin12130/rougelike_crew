"""Query the local RAG index (BM25).

Usage:
    python tools/rag/query.py "tilemap pixel snap 2d" [--top 8] [--all]
"""

import argparse
import json
import math
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
INDEX_DIR = os.path.join(ROOT, ".tools", "rag_index")

CJK_RE = re.compile(r"[\u4e00-\u9fff]")
WORD_RE = re.compile(r"[a-zA-Z0-9_\-\.\+\#]+")


def tokenize(text: str) -> list[str]:
    toks = []
    for m in WORD_RE.finditer(text):
        w = m.group(0).lower()
        if len(w) > 1:
            toks.append(w)
    cjk = "".join(CJK_RE.findall(text))
    for i in range(len(cjk) - 1):
        toks.append(cjk[i : i + 2])
    return toks


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    ap = argparse.ArgumentParser()
    ap.add_argument("query", help="search keywords (can be Chinese or English)")
    ap.add_argument("--top", type=int, default=8)
    ap.add_argument("--all", action="store_true", help="print full chunk text")
    ap.add_argument("--src", default="", help="only match src containing this substring (e.g. books, godot-docs/tutorials/2d, docs)")
    args = ap.parse_args()

    chunks_path = os.path.join(INDEX_DIR, "chunks.jsonl")
    index_path = os.path.join(INDEX_DIR, "index.json")
    if not (os.path.exists(chunks_path) and os.path.exists(index_path)):
        print(f"index missing. Run: python {os.path.join('tools', 'rag', 'build_index.py')}")
        sys.exit(1)

    with open(index_path, encoding="utf-8") as f:
        meta = json.load(f)
    idf = meta["idf"]
    k1, b = meta["k1"], meta["b"]
    avgdl = meta["avgdl"]
    n_docs = meta["n_docs"]

    q_toks = tokenize(args.query)
    if not q_toks:
        print("empty query")
        sys.exit(1)

    hits = []
    with open(chunks_path, encoding="utf-8") as f:
        for line in f:
            c = json.loads(line)
            if args.src and args.src not in c["src"]:
                continue
            tf: dict[str, int] = {}
            for t in tokenize(c["text"]):
                tf[t] = tf.get(t, 0) + 1
            score = 0.0
            dl = c["len"]
            for t in set(q_toks):
                if t not in idf:
                    continue
                f_t = tf.get(t, 0)
                if f_t == 0:
                    continue
                denom = f_t + k1 * (1 - b + b * dl / max(avgdl, 1))
                score += idf[t] * (f_t * (k1 + 1)) / denom
            if score > 0:
                hits.append((score, c))

    hits.sort(key=lambda x: -x[0])
    print(f"query: {args.query}  (top {args.top} of {len(hits)} hits)\n")
    for score, c in hits[: args.top]:
        print(f"[{score:.2f}] {c['src']}  :: {c['title']}")
        if args.all:
            print("---")
            print(c["text"][:1400])
            print("---\n")


if __name__ == "__main__":
    sys.exit(main())

"""Build a local BM25 search index over Godot official docs + project docs.

Usage:
    python tools/rag/build_index.py

Output:
    .tools/rag_index/chunks.jsonl   (chunk text + metadata)
    .tools/rag_index/index.json     (BM25 stats: df, avgdl, idf, doc meta)
"""

import json
import math
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
TOOLS = os.path.join(ROOT, ".tools")
CORPUS = [
    os.path.join(TOOLS, "godot-docs"),
    os.path.join(TOOLS, "books"),
    os.path.join(ROOT, "docs"),
]
OUT_DIR = os.path.join(TOOLS, "rag_index")

K1 = 1.5
B = 0.75
MIN_CHUNK = 300
MAX_CHUNK = 1200

CJK_RE = re.compile(r"[\u4e00-\u9fff]")
WORD_RE = re.compile(r"[a-zA-Z0-9_\-\.\+\#]+")


def tokenize(text: str) -> list[str]:
    """English words (lowercased) + CJK bigrams."""
    toks = []
    for m in WORD_RE.finditer(text):
        w = m.group(0).lower()
        if len(w) > 1:
            toks.append(w)
    # CJK: char bigrams for better matching
    cjk = "".join(CJK_RE.findall(text))
    for i in range(len(cjk) - 1):
        toks.append(cjk[i : i + 2])
    return toks


def rst_to_text(path: str) -> str:
    with open(path, encoding="utf-8", errors="replace") as f:
        text = f.read()
    # strip RST markup roughly but keep headings
    text = re.sub(r"``([^`]+)``", r"\1", text)
    text = re.sub(r"`([^`<]+)<[^>]+>`_", r"\1", text)
    text = re.sub(r"\.\. (note|warning|tip|important)::", r"NOTE:", text)
    return text


def chunk_text(text: str, src: str, title: str) -> list[dict]:
    """Split by headings first; merge small sections; split oversized."""
    lines = text.splitlines()
    sections = []
    cur = []
    cur_head = title
    heading_re = re.compile(r"^([=\-~^\"']{3,})\s*$")
    for i, ln in enumerate(lines):
        is_heading_underline = heading_re.match(ln.strip()) and i > 0
        if is_heading_underline:
            if cur:
                sections.append((cur_head, "\n".join(cur)))
            cur_head = lines[i - 1].strip()
            cur = []
            continue
        if re.match(r"^#{1,6}\s", ln):
            if cur:
                sections.append((cur_head, "\n".join(cur)))
            cur_head = re.sub(r"^#{1,6}\s*", "", ln).strip()
            cur = []
            continue
        if ln.strip():
            cur.append(ln)
    if cur:
        sections.append((cur_head, "\n".join(cur)))

    chunks = []
    for head, body in sections:
        body = body.strip()
        if len(body) < MIN_CHUNK:
            continue
        if not head:
            head = os.path.splitext(os.path.basename(src))[0]
        if len(body) <= MAX_CHUNK:
            chunks.append({"src": src, "title": head, "text": body})
            continue
        # split long section into ~MAX_CHUNK pieces at paragraph boundary
        paras = re.split(r"\n\s*\n", body)
        buf = ""
        for p in paras:
            if len(buf) + len(p) > MAX_CHUNK and buf:
                chunks.append({"src": src, "title": head, "text": buf.strip()})
                buf = p
            else:
                buf += "\n\n" + p
        if buf.strip():
            chunks.append({"src": src, "title": head, "text": buf.strip()})
    return chunks


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    chunks = []
    n_files = 0
    for base in CORPUS:
        if not os.path.isdir(base):
            print(f"[skip] missing corpus: {base}")
            continue
        for dirpath, _dirs, files in os.walk(base):
            for fn in sorted(files):
                if not fn.endswith((".rst", ".md")):
                    continue
                full = os.path.join(dirpath, fn)
                rel = os.path.relpath(full, ROOT).replace("\\", "/")
                try:
                    text = rst_to_text(full) if fn.endswith(".rst") else open(
                        full, encoding="utf-8", errors="replace"
                    ).read()
                except Exception as e:
                    print(f"[warn] {rel}: {e}")
                    continue
                title = os.path.splitext(fn)[0]
                m = re.search(r"^#+\s+(.+)$", text, re.M)
                if m:
                    title = m.group(1).strip()
                chunks.extend(chunk_text(text, rel, title))
                n_files += 1

    # BM25 index
    doc_freq: dict[str, int] = {}
    doc_len = []
    for c in chunks:
        toks = tokenize(c["text"])
        c["tokens"] = toks
        doc_len.append(len(toks))
        for t in set(toks):
            doc_freq[t] = doc_freq.get(t, 0) + 1
    n_docs = len(chunks)
    avgdl = sum(doc_len) / max(n_docs, 1)
    idf = {
        t: math.log(1 + (n_docs - df + 0.5) / (df + 0.5))
        for t, df in doc_freq.items()
    }

    # keep only token list for scoring in query; drop from stored text
    for c in chunks:
        c["len"] = len(c["tokens"])
        del c["tokens"]

    with open(os.path.join(OUT_DIR, "chunks.jsonl"), "w", encoding="utf-8") as f:
        for c in chunks:
            f.write(json.dumps(c, ensure_ascii=False) + "\n")
    meta = {
        "n_docs": n_docs,
        "n_files": n_files,
        "avgdl": avgdl,
        "idf": idf,
        "k1": K1,
        "b": B,
    }
    with open(os.path.join(OUT_DIR, "index.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False)
    print(f"indexed {n_docs} chunks from {n_files} files -> {OUT_DIR}")
    print(f"vocab size: {len(idf)}")


if __name__ == "__main__":
    sys.exit(main())

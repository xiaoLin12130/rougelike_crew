# -*- coding: utf-8 -*-
"""E-batch audit helpers: read data & docs with correct encodings."""
import os, re, json, io, sys

def find_doc(name_part):
    files = os.listdir('docs/design')
    hits = [f for f in files if name_part in f]
    if not hits:
        raise FileNotFoundError(name_part)
    return os.path.join('docs/design', hits[0])

def read_doc(name_part):
    path = find_doc(name_part)
    raw = open(path, 'rb').read()
    for enc in ('utf-8', 'gbk', 'utf-16'):
        try:
            return raw.decode(enc)
        except Exception:
            pass
    return raw.decode('utf-8', errors='replace')

def read_json(path):
    with open(path, encoding='utf-8') as fh:
        return json.load(fh)

if __name__ == '__main__':
    t = read_doc('去重分配方案')
    print('decoded len', len(t))
    for m in re.finditer(r'^#{1,3} .*$', t, re.M):
        print(m.group(0))

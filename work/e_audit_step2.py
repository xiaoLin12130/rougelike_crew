# -*- coding: utf-8 -*-
import os, json, io, sys
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

tmp = '.tmp'
for fn in os.listdir(tmp):
    if 'icon' in fn.lower() or 'map' in fn.lower():
        p = os.path.join(tmp, fn)
        print('----', fn, os.path.getsize(p))
        try:
            d = json.load(open(p, encoding='utf-8'))
            if isinstance(d, dict):
                items = list(d.items())[:8]
                for k, v in items:
                    print('  ', repr(k)[:100], '->', repr(v)[:140])
                print('   total keys:', len(d))
        except Exception as e:
            print('   not json:', e)

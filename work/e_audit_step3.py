# -*- coding: utf-8 -*-
import io, sys, os
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

for fn in ['icon_map_lib.py', 'parse_icon_map.py', 'gen_icon_audit_doc.py']:
    p = os.path.join('.tmp', fn)
    print('=' * 30, fn)
    print(open(p, encoding='utf-8').read()[:6000])

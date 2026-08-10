# -*- coding: utf-8 -*-
import io, sys, os
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
p = os.path.join('.tmp', 'icon_map_lib.py')
t = open(p, encoding='utf-8').read()
print(t[5800:])

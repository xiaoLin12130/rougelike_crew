# -*- coding: utf-8 -*-
import io, sys
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

def has_in(txt, words):
    return any(w in txt for w in words)

tests = [
    ('blessing', '圣光', '圣光庇护，恢复生命并对周围敌人造成光属性伤害。', ['light']),
    ('poison_m8', '解毒反哺', '毒伤 5% 回复生命（反哺血清每层 +1%，上限 20%）', ['poison', 'mechanic:poison_m8']),
    ('summon_9', '亡者低语', '召唤物死亡时玩家回复 1% 最大生命（每层）', []),
    ('drain', '吸血', '', []),
    ('pierce', '穿透', '', []),
]
for ident, name, desc, tags in tests:
    txt = (ident + ' ' + name + ' ' + desc + ' ' + ' '.join(tags)).lower()
    print(ident, ('恢复' in txt), ('回复' in txt), ('吸血' in txt), ('穿透' in txt))
    print('   txt=', repr(txt[:60]))
    if ident == 'blessing':
        print('   direct test:', '恢复' in '恢复生命', repr('恢复'))
        print('   txt hex:', [hex(ord(c)) for c in txt])

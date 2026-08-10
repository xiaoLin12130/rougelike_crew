# -*- coding: utf-8 -*-
"""E-batch icon/description semantic audit (read-only). Outputs work/e_audit_result.json"""
import os, re, json, io, sys, zlib, struct
from collections import Counter

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

ICONS = 'assets/icons'

# ---------------- shikashi legend (from .tmp/icon_map_lib.py, anchors verified) ----------------
LEGEND = []
def _add(items):
    LEGEND.extend(items)
_add(["skull_and_bones", "poison", "sleeping_eye", "silenced", "cursed", "dizzy",
      "charmed", "sleeping", "paralysis", "burned", "sweat_drop"])
_add(["heart", "lungs", "stomach", "brain", "strong_arm"])
_add(["buff_arrow1", "buff_arrow2", "buff_arrow3",
      "debuff_arrow1", "debuff_arrow2", "debuff_arrow3", "repeat_arrow"])
_add(["dripping_blade", "saber_slash", "lightning_attack", "headshot",
      "raining_arrows", "healing", "heal_injury", "battle_gear", "guard",
      "ring_of_fire", "disintegrate", "fist_hit", "gust_of_air", "tremor",
      "psychic_waves", "sunrays"])
_add(["square_speech_bubble", "round_speech_bubble", "campfire", "camping_tent",
      "blacksmith_forging", "mining", "woodcutting", "spellbook", "steal"])
_add(["wooden_waster", "longsword", "enchanted_sword", "katana", "gladius", "saber",
      "dagger", "broad_dagger", "sai", "crossed_dual_swords", "war_axe", "battle_axe",
      "flail", "spiked_club", "whip", "fist", "buckler_shield", "wooden_shield",
      "checkered_shield", "bow_and_arrow", "crossbow", "slingshot", "boomerang",
      "wizard_staff", "magic_gem_staff1", "magic_gem_staff2", "magic_gem_staff3",
      "magic_gem_staff4"])
_add(["robin_hood_hat", "barbute_helm", "leather_helm", "cross_helm", "iron_armour",
      "steel_armour", "leather_armour", "layered_plate_armour", "blue_tunic",
      "green_tunic", "trousers", "shorts", "heart_boxers", "dress", "cloak", "belt",
      "leather_gauntlet", "metal_gauntlet", "leather_boots", "steeltoe_boots",
      "ring", "diamond_ring", "gold_necklace", "prayer_beads", "tribal_necklace",
      "leather_pouch"])
_add(["normal_potion1", "normal_potion2", "normal_potion3", "normal_potion4",
      "upgraded_potion1", "upgraded_potion2", "upgraded_potion3", "upgraded_potion4",
      "rare_potion1", "rare_potion2", "rare_potion3", "rare_potion4",
      "special_brew1", "special_brew2", "special_brew3", "bandage"])
_add(["knapsack", "axe", "pickaxe", "shovel", "hammer", "grappling_hook",
      "hookshot", "telescope", "magnifying_glass", "lantern", "torch", "candle",
      "bomb", "rope", "bear_trap", "hourglass", "runestone", "mirror", "shackles",
      "lyre", "violin", "ocarina", "flute", "panpipes", "hunting_horn",
      "brass_key", "silver_keyring", "treasure_chest", "mortar_and_pestle",
      "herb1", "herb2", "herb3", "mushrooms", "flower_bulb", "root_tip",
      "plant_pot_seedling", "plant_pot_growing", "plant_pot_fully_grown",
      "money_purse", "crown_coin", "bronze_coin_stack", "silver_coin_stack",
      "gold_coin_stack", "large_gold_coin_stack", "receive_money", "pay_money",
      "gems", "rupee", "book1", "book2", "book3", "book4", "book5", "book6",
      "book7", "book8", "open_book", "letter", "tied_scroll", "open_scroll",
      "old_map", "dice", "card", "bottle_of_wine"])
_add(["apple", "banana", "pear", "lemon", "strawberry", "grapes", "carrot",
      "sweetcorn", "garlic", "tomato", "eggplant", "red_chili", "mushroom",
      "loaf_of_bread", "baguette", "whole_chicken", "chicken_leg", "sirloin_steak",
      "ham", "morsel", "cooked_fish", "eggs", "big_egg", "cheese", "milk",
      "honey", "salt", "spices", "candy", "cake", "drink"])
_add(["fishing_rod", "fishing_hook", "worm_bait", "lake_trout", "brown_trout",
      "eel", "tropical_fish", "clownfish", "jellyfish", "octopus", "turtle",
      "fish_bone", "old_boot", "fossil", "sunken_chest"])
_add(["wood", "stone", "ore", "gold", "gems_resource", "cotton", "yarn", "cloth",
      "pelts", "monster_claw", "feathers"])
_add(["orb1", "orb2", "orb3", "orb4", "orb5", "orb6"])
assert len(LEGEND) == 245

_SECTIONS = [11, 5, 7, 16, 9, 28, 26, 16, 64, 31, 15, 11, 6]
COORD = {}
_idx = 0
_row = 0
for _sec_len in _SECTIONS:
    for _off in range(_sec_len):
        COORD[LEGEND[_idx]] = (_row + _off // 16, _off % 16)
        _idx += 1
    _row += (_sec_len + 15) // 16
NAME_BY_COORD = {v: k for k, v in COORD.items()}

# ---------------- icon semantic categories ----------------
SHIK_CAT = {
    "skull_and_bones": {"death", "curse", "poison"}, "poison": {"poison"}, "sleeping_eye": {"curse"},
    "silenced": {"curse"}, "cursed": {"curse"}, "dizzy": {"curse"}, "charmed": {"curse"},
    "sleeping": {"curse"}, "paralysis": {"lightning"}, "burned": {"fire"},
    "sweat_drop": {"water"},
    "heart": {"body"}, "lungs": {"body"}, "stomach": {"body"}, "brain": {"body"},
    "strong_arm": {"body"},
    "buff_arrow1": {"generic"}, "buff_arrow2": {"generic"}, "buff_arrow3": {"generic"},
    "debuff_arrow1": {"debuff", "generic", "slow"}, "debuff_arrow2": {"debuff", "generic", "slow"},
    "debuff_arrow3": {"debuff", "generic", "slow"}, "repeat_arrow": {"cooldown"},
    "dripping_blade": {"blade", "fighter"}, "saber_slash": {"blade", "fighter"}, "lightning_attack": {"lightning"},
    "headshot": {"crit"}, "raining_arrows": {"water", "bow"}, "healing": {"heal"},
    "heal_injury": {"heal"}, "battle_gear": {"blade", "melee", "fighter"}, "guard": {"defense"},
    "ring_of_fire": {"fire"}, "disintegrate": {"magic"}, "fist_hit": {"melee", "fighter"},
    "gust_of_air": {"wind"}, "tremor": {"defense"}, "psychic_waves": {"magic"},
    "sunrays": {"light"},
    "square_speech_bubble": {"generic"}, "round_speech_bubble": {"generic"},
    "campfire": {"fire"}, "camping_tent": {"generic"}, "blacksmith_forging": {"forge"},
    "mining": {"mine"}, "woodcutting": {"wood"}, "spellbook": {"book", "summon"},
    "steal": {"generic"},
    "wooden_waster": {"blade"}, "longsword": {"blade"}, "enchanted_sword": {"blade"},
    "katana": {"blade"}, "gladius": {"blade"}, "saber": {"blade"}, "dagger": {"blade", "dagger", "spike"},
    "broad_dagger": {"blade", "dagger", "spike"}, "sai": {"blade", "dagger", "spike"},
    "crossed_dual_swords": {"blade"}, "war_axe": {"blade", "axe"}, "battle_axe": {"blade", "axe"},
    "flail": {"blade", "mace"}, "spiked_club": {"blade", "mace", "thorn"}, "whip": {"blade", "thorn"},
    "fist": {"melee"}, "buckler_shield": {"shield"}, "wooden_shield": {"shield"},
    "checkered_shield": {"shield"}, "bow_and_arrow": {"bow", "hunter"}, "crossbow": {"bow", "hunter"},
    "slingshot": {"bow"}, "boomerang": {"generic"},
    "wizard_staff": {"staff"}, "magic_gem_staff1": {"staff"}, "magic_gem_staff2": {"staff"},
    "magic_gem_staff3": {"staff"}, "magic_gem_staff4": {"staff"},
    "robin_hood_hat": {"clothing"}, "barbute_helm": {"helmet"}, "leather_helm": {"helmet"},
    "cross_helm": {"helmet"}, "iron_armour": {"armor"}, "steel_armour": {"armor"},
    "leather_armour": {"armor"}, "layered_plate_armour": {"armor"},
    "blue_tunic": {"clothing"}, "green_tunic": {"clothing"}, "trousers": {"clothing"},
    "shorts": {"clothing"}, "heart_boxers": {"clothing"}, "dress": {"clothing"},
    "cloak": {"clothing"}, "belt": {"belt"}, "leather_gauntlet": {"gauntlet"},
    "metal_gauntlet": {"gauntlet"}, "leather_boots": {"boots"}, "steeltoe_boots": {"boots"},
    "ring": {"ring"}, "diamond_ring": {"ring"}, "gold_necklace": {"gold"},
    "prayer_beads": {"beads"}, "tribal_necklace": {"necklace"}, "leather_pouch": {"pouch"},
    "normal_potion1": {"potion"}, "normal_potion2": {"potion"}, "normal_potion3": {"potion"},
    "normal_potion4": {"potion"}, "upgraded_potion1": {"potion"}, "upgraded_potion2": {"potion"},
    "upgraded_potion3": {"potion"}, "upgraded_potion4": {"potion"}, "rare_potion1": {"potion"},
    "rare_potion2": {"potion"}, "rare_potion3": {"potion"}, "rare_potion4": {"potion"},
    "special_brew1": {"potion"}, "special_brew2": {"potion"}, "special_brew3": {"potion"},
    "bandage": {"heal"},
    "knapsack": {"bag"}, "axe": {"blade", "axe"}, "pickaxe": {"mine"}, "shovel": {"mine"},
    "hammer": {"mace", "forge"}, "grappling_hook": {"hook"}, "hookshot": {"hook"},
    "telescope": {"view"}, "magnifying_glass": {"crit", "view"}, "lantern": {"light"},
    "torch": {"fire"}, "candle": {"fire"}, "bomb": {"explosion"}, "rope": {"generic"},
    "bear_trap": {"trap"}, "hourglass": {"time"}, "runestone": {"rune", "summon"},
    "mirror": {"reflect"}, "shackles": {"curse"}, "lyre": {"music"}, "violin": {"music"},
    "ocarina": {"music"}, "flute": {"music"}, "panpipes": {"music"},
    "hunting_horn": {"horn", "hunter"}, "brass_key": {"key"}, "silver_keyring": {"key"},
    "treasure_chest": {"chest"}, "mortar_and_pestle": {"potion", "alchemy"},
    "herb1": {"herb"}, "herb2": {"herb"}, "herb3": {"herb"}, "mushrooms": {"herb"},
    "flower_bulb": {"plant"}, "root_tip": {"plant"},
    "plant_pot_seedling": {"plant"}, "plant_pot_growing": {"plant"},
    "plant_pot_fully_grown": {"plant"},
    "money_purse": {"gold"}, "crown_coin": {"gold", "crown"}, "bronze_coin_stack": {"gold"},
    "silver_coin_stack": {"gold"}, "gold_coin_stack": {"gold"},
    "large_gold_coin_stack": {"gold"}, "receive_money": {"gold"}, "pay_money": {"gold"},
    "gems": {"gem"}, "rupee": {"gem"}, "book1": {"book"}, "book2": {"book"},
    "book3": {"book"}, "book4": {"book"}, "book5": {"book"}, "book6": {"book"},
    "book7": {"book"}, "book8": {"book"}, "open_book": {"book"}, "letter": {"letter"},
    "tied_scroll": {"scroll"}, "open_scroll": {"scroll"}, "old_map": {"map"},
    "dice": {"lucky", "crit"}, "card": {"card"}, "bottle_of_wine": {"drink"},
}
for _f in ["apple", "banana", "pear", "lemon", "strawberry", "grapes", "carrot",
           "sweetcorn", "garlic", "tomato", "eggplant", "red_chili", "mushroom",
           "loaf_of_bread", "baguette", "whole_chicken", "chicken_leg", "sirloin_steak",
           "ham", "morsel", "cooked_fish", "eggs", "big_egg", "cheese", "milk",
           "honey", "salt", "spices", "candy", "cake", "drink"]:
    SHIK_CAT[_f] = {"food"}
SHIK_CAT["big_egg"] = {"food", "egg"}
for _f in ["fishing_rod", "fishing_hook", "worm_bait", "lake_trout", "brown_trout",
           "eel", "tropical_fish", "clownfish", "jellyfish", "octopus", "turtle",
           "fish_bone", "old_boot", "fossil", "sunken_chest"]:
    SHIK_CAT[_f] = {"water", "fish"}
SHIK_CAT["worm_bait"] = {"water", "fish", "poison"}
RES_CAT = {"wood": {"wood"}, "stone": {"stone"}, "ore": {"ore"}, "gold": {"gold"},
           "gems_resource": {"gem"}, "cotton": {"cloth"}, "yarn": {"cloth"},
           "cloth": {"cloth"}, "pelts": {"cloth"}, "monster_claw": {"claw"},
           "feathers": {"wind", "feather"}}
for _r, _c in RES_CAT.items():
    SHIK_CAT[_r] = _c
for i in range(1, 7):
    SHIK_CAT[f"orb{i}"] = {"orb"}

VERARC_CAT = {
    "attack_boost": {"generic", "atk"}, "attack_down": {"curse", "debuff"},
    "attack_speed_boost": {"generic", "speed"}, "bleeding": {"lifesteal", "blade"},
    "blinded": {"curse"}, "blinding_light_spell": {"light"},
    "confused": {"curse"}, "counterspell": {"magic"}, "critical_boost": {"crit"},
    "cursed_(disarmed+silenced)": {"curse"}, "defense_boost": {"defense"},
    "defense_down": {"curse", "debuff"}, "divine_protection_spell": {"defense", "shield"},
    "element_boost": {"generic"}, "exp_boost": {"generic", "xp"},
    "fire_spell": {"fire"}, "fire_spell_2": {"fire"},
    "fortify_spell": {"defense"}, "frenzy_spell_(critical_booster)": {"crit", "buff"},
    "frozen": {"ice"}, "ghost_form_(physical_damage_immunity)": {"curse", "wind", "summon"},
    "glow": {"generic"}, "healing_spell": {"heal"}, "ice_spell": {"ice"},
    "knockback_boost": {"generic", "knockback"}, "knockback_resistance": {"generic"},
    "lightning_spell": {"lightning"}, "lucky_boost": {"crit", "lucky"},
    "magic_amplification": {"generic", "magic"}, "mana_replenish": {"mana", "cooldown"},
    "negative_status_resistance": {"generic", "debuff"}, "on_fire_(burning)": {"fire"},
    "paralyzed": {"lightning"}, "poison_dagger": {"poison", "blade"},
    "poisoned": {"poison"}, "regeneration": {"heal", "regeneration", "lifesteal"},
    "sleeping": {"curse"}, "slowed": {"ice", "slow"}, "summoning_spell": {"summon"},
    "swiftness": {"wind", "speed"}, "teleportation_spell": {"teleport"},
    "thorn_vine_spell": {"water", "plant"}, "water_spell": {"water"},
}

def icon_semantics(short):
    m = re.fullmatch(r"(SWORDS|SWORDS_COLOR_VARIANTS|STAFFS|AXES|MACES|DAGGERS|SPEARS|ALL)_(\d+)", short)
    if m:
        pref = m.group(1)
        n = int(m.group(2))
        if pref == "SWORDS":
            return {"blade", "fighter"}, f"willibab 剑 SWORDS_{n}"
        if pref == "SWORDS_COLOR_VARIANTS":
            return {"blade", "fighter"}, f"willibab 剑(变色) SWORDS_COLOR_VARIANTS_{n}"
        if pref == "STAFFS":
            return {"staff"}, f"willibab 法杖 STAFFS_{n}"
        if pref == "AXES":
            return {"blade", "axe", "fighter"}, f"willibab 斧 AXES_{n}"
        if pref == "MACES":
            return {"blade", "mace", "fighter"}, f"willibab 锤 MACES_{n}"
        if pref == "DAGGERS":
            return {"blade", "dagger", "spike", "fighter"}, f"willibab 匕首 DAGGERS_{n}"
        if pref == "SPEARS":
            return {"spear", "pierce", "fighter"}, f"willibab 矛 SPEARS_{n}"
        if pref == "ALL":
            return {"misc"}, f"willibab 杂项 ALL_{n}(内容未解析)"
    if short in VERARC_CAT:
        return VERARC_CAT[short], f"verarc {short}"
    m2 = re.fullmatch(r"shikashi_r(\d+)_c(\d+)", short)
    if m2:
        r, c = int(m2.group(1)), int(m2.group(2))
        name = NAME_BY_COORD.get((r, c))
        if name is None:
            return {"unknown"}, f"shikashi r{r}_c{c}(图例未收录)"
        cats = SHIK_CAT.get(name, {"unknown"})
        return cats, f"shikashi r{r}_c{c}={name}"
    if short.startswith("summon_"):
        return {"summon", "creature"}, f"召唤物贴图 {short}"
    return {"unknown"}, f"未知 {short}"

# ---------------- PNG hue analysis (pure python, RGBA + indexed) ----------------
def png_rgba(path):
    with open(path, 'rb') as fh:
        data = fh.read()
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        return None
    pos = 8
    idat = b''
    w = h = bitd = ctype = None
    plte = trns = None
    while pos < len(data):
        ln = struct.unpack('>I', data[pos:pos+4])[0]
        typ = data[pos+4:pos+8]
        chunk = data[pos+8:pos+8+ln]
        if typ == b'IHDR':
            w, h, bitd, ctype = struct.unpack('>IIBB', chunk[:10])
        elif typ == b'IDAT':
            idat += chunk
        elif typ == b'PLTE':
            plte = chunk
        elif typ == b'tRNS':
            trns = chunk
        elif typ == b'IEND':
            break
        pos += 12 + ln
    if ctype not in (2, 3, 6):
        return None
    raw = zlib.decompress(idat)
    if ctype == 3:
        if bitd == 8:
            stride = w
        elif bitd == 4:
            stride = (w + 1) // 2
        elif bitd == 2:
            stride = (w + 3) // 4
        else:
            stride = (w + 7) // 8
    else:
        bpp = 4 if ctype == 6 else 3
        stride = w * bpp
    rows = []
    off = 0
    prev = bytearray(stride)
    for _ in range(h):
        ft = raw[off]
        off += 1
        line = bytearray(raw[off:off+stride])
        off += stride
        if ft == 1:
            for i in range(1, stride):
                line[i] = (line[i] + line[i-1]) & 255
        elif ft == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 255
        elif ft == 3:
            for i in range(stride):
                a = line[i-1] if i >= 1 else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 255
        elif ft == 4:
            for i in range(stride):
                a = line[i-1] if i >= 1 else 0
                b = prev[i]
                c = prev[i-1] if i >= 1 else 0
                p = a + b - c
                pa, pb, pc = abs(p-a), abs(p-b), abs(p-c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 255
        rows.append(bytes(line))
        prev = line
    rs = gs = bs = cnt = 0
    if ctype == 3:
        if not plte:
            return None
        pal = [tuple(plte[i:i+3]) for i in range(0, len(plte), 3)]
        pal_alpha = [255] * len(pal)
        if trns:
            for i, a in enumerate(trns):
                pal_alpha[i] = a
        for row in rows:
            if bitd == 8:
                for byte in row:
                    if byte >= len(pal):
                        continue
                    r, g, b = pal[byte]
                    if pal_alpha[byte] < 40 or r+g+b < 24:
                        continue
                    rs += r; gs += g; bs += b; cnt += 1
            else:
                for byte in row:
                    for shift in ((4, 0) if bitd == 4 else (6, 4, 2, 0) if bitd == 2 else (7, 6, 5, 4, 3, 2, 1, 0)):
                        idx = (byte >> shift) & (0xF if bitd == 4 else 0x3 if bitd == 2 else 0x1)
                        if idx >= len(pal):
                            continue
                        r, g, b = pal[idx]
                        if pal_alpha[idx] < 40 or r+g+b < 24:
                            continue
                        rs += r; gs += g; bs += b; cnt += 1
    else:
        for row in rows:
            for i in range(0, stride, bpp):
                r, g, b = row[i], row[i+1], row[i+2]
                if ctype == 6 and row[i+3] < 40:
                    continue
                if r+g+b < 24:
                    continue
                rs += r; gs += g; bs += b; cnt += 1
    if not cnt:
        return None
    r, g, b = rs/cnt, gs/cnt, bs/cnt
    mx, mn = max(r, g, b), min(r, g, b)
    sat = (mx - mn) / mx if mx else 0
    if mx == mn:
        hue = -1
    else:
        if mx == r:
            hue = ((g - b) / (mx - mn)) % 6
        elif mx == g:
            hue = (b - r) / (mx - mn) + 2
        else:
            hue = (r - g) / (mx - mn) + 4
        hue *= 60
        if hue < 0:
            hue += 360
    if sat < 0.10 or mx < 40:
        col = "灰"
    elif hue < 20 or hue >= 340:
        col = "红/橙(火)"
    elif hue < 65:
        col = "黄(雷)"
    elif hue < 165:
        col = "绿(毒)"
    elif hue < 200:
        col = "青(水/风)"
    elif hue < 265:
        col = "蓝(冰)"
    else:
        col = "紫/粉"
    return {"rgb": (round(r), round(g), round(b)), "sat": round(sat, 2), "color": col}

# ---------------- school + form detection ----------------
def detect_schools(entry):
    s = set()
    ident = entry.get('id', '')
    name = entry.get('name', '')
    desc = entry.get('desc', '')
    tags = entry.get('tags') or []
    primary = (ident + ' ' + name + ' ' + ' '.join(tags)).lower()
    txt = (primary + ' ' + desc).lower()
    def has(*words):
        return any(w in txt for w in words)
    def has_p(*words):
        return any(w in primary for w in words)
    if has('fire', 'flame', 'burn', 'ember', 'inferno', '火山', '熔', '灼', '灰烬', '硫磺', '薪火', '引燃', '龙息', '火雨', '火柱', '燃烧'):
        s.add('fire')
    if has('ice', 'frost', 'frozen', 'freeze', 'glacier', '冰霜', '冰系', '冻结', '冰伤', '冰弹', '冰刃', '寒', '雪', '零度', '深寒', '永冻'):
        s.add('ice')
    if has('lightning', 'thunder', 'electric', 'chain', '雷', '电', '麻痹', '静电', '过载', '电荷', '闪电', '雷云', '线圈', '电弧'):
        s.add('lightning')
    if has('poison', 'venom', 'plague', 'toxin', '毒', '疫', '腐', '瘟', '瘴', '蛇', '虫'):
        s.add('poison')
    if has('water', 'tide', 'torrent', 'marsh', 'swamp', 'ocean', '水系', '水弹', '水球', '水元素', '水幕', '水泽', '水龙卷', '潮', '浪', '海', '洋', '雨', '泽', '湿', '藤', '沼', '涡', '泉', '滴', '龙卷', '洋流', '激流', '深水', '暴雨'):
        s.add('water')
    if has('wind', 'gust', 'swift', 'feather', '风系', '风刃', '风切', '疾风', '追风', '迅捷', '踏浪', '踏风', '暴走'):
        s.add('wind')
    if has_p('blade', 'sword', 'axe', 'melee', 'slash', '砍', '剑', '刀', '斩', '刃', '斧', '锤', '矛', '近战', '战斧', '战吼', '战意', '战刃', '破甲', '铁壁', '钢体', '巨力', '嗜血', '旋风', '磨刀', '处决', '处刑', '屠', '血怒', '血之狂暴', '狂化', '切', '终结', '致命一击'):
        s.add('blade')
    if has_p('defense', 'shield', 'armor', 'thorn', 'guard', 'block', '护甲', '护盾', '防御', '荆棘', '磐石', '格挡', '不屈', '无敌', '吸收', '反震', '减伤', '护体', '反弹', '守御', '铁壁'):
        s.add('defense')
    if has_p('summon', 'summoning', 'spirit', 'totem', 'legion', '召唤', '契约', '图腾', '军团', '灵魂', '共鸣', '兽群', '献祭', '替身', '法阵', '冲锋', '首领', '狂热', '集火', '共生', '蝙蝠', '骷髅', '低语', '战旗', '骑士', '墓园', '召唤物'):
        s.add('summon')
    if has_p('curse', 'cursed', 'doom', 'hex', '恐惧', '虚弱', '禁疗', '咒', '诅', '厄运', '折磨', '失衡', '痛苦', 'debuff'):
        s.add('curse')
    if has('crit', 'critical', 'lucky', '暴击', '致命', '弱点', '猎', '敏锐', '幸运', '完美', '爆头', '标记'):
        s.add('crit')
    if has('heal', 'healing', '回复', '治疗', '回血', '恢复', '再生'):
        s.add('heal')
    if has('gold', '金币', '钱袋', '金身'):
        s.add('gold')
    if has('orb', 'crystal', 'gem', '水晶', '晶石', '宝珠', '宝石', '钻石'):
        s.add('orb')
    if has('lifesteal', '吸血', '生命回复'):
        s.add('lifesteal')
    if has('攻击力'):
        s.add('atk')
    if has('speed', '攻速', '移速', '移动速度', '攻击速度'):
        s.add('speed')
    if has('cooldown', '冷却', '充能', '回能'):
        s.add('cooldown')
    if has('mana', '法力', '回蓝', '蓝量'):
        s.add('mana')
    if has('xp', 'exp', '经验'):
        s.add('xp')
    if has('area', '范围'):
        s.add('area')
    if has_p('光属性', '圣光', '闪光', '致盲', '强光', '日光', '光环'):
        s.add('light')
    if has('teleport', '传送', '瞬移'):
        s.add('teleport')
    if has_p('反制', '魔法'):
        s.add('magic')
    if has('knockback', '击退'):
        s.add('knockback')
    if has('bounce', '弹射'):
        s.add('bounce')
    if has_p('狂暴', '狂化'):
        s.add('buff')
    if has_p('连发'):
        s.add('speed')
    if has_p('齐射'):
        s.add('area')
    if has('减速', '缓蚀', '迟缓'):
        s.add('slow')
    if has('穿透'):
        s.add('pierce')
    tag_school = {'fire': 'fire', 'ice': 'ice', 'lightning': 'lightning', 'thunder': 'lightning',
                  'poison': 'poison', 'water': 'water', 'wind': 'wind', 'blade': 'blade',
                  'defense': 'defense', 'summon': 'summon', 'curse': 'curse', 'crit': 'crit',
                  'crit_dmg': 'crit', 'crit_luck': 'crit', 'lucky': 'crit', 'atk': 'atk',
                  'attack_speed': 'speed', 'cooldown': 'cooldown', 'area': 'area',
                  'speed': 'speed', 'gold': 'gold', 'xp': 'xp', 'lifesteal': 'lifesteal',
                  'skill_dmg': 'atk', 'skill_cd': 'cooldown', 'pickup': 'area'}
    for t in tags:
        if t in tag_school:
            s.add(tag_school[t])
    return s

def detect_form(entry):
    f = set()
    txt = (entry['id'] + ' ' + entry['name'] + ' ' + entry['desc']).lower()
    def has(*words):
        return any(w in txt for w in words)
    if has('药水', '药剂', '血清', '药瓶', '药', '精粹', '精华', '酸', '混合', '液'):
        f.add('potion')
    if has('书', '卷轴', '法术书', '图鉴', '典籍', '精通'):
        f.add('book')
    if has('戒指', '指环'):
        f.add('ring')
    if has('靴', '鞋', '行者', '踏'):
        f.add('boots')
    if has('腰带'):
        f.add('belt')
    if has('护符', '坠饰', '项链', '吊坠'):
        f.add('necklace')
    if has('甲', '护甲'):
        f.add('armor')
    if has('盾'):
        f.add('shield')
    if has('法杖', '术架', '杖'):
        f.add('staff')
    if has('水晶', '晶石', '核心', '宝珠', '宝石', '钻石', '结晶'):
        f.add('crystal')
    if has('金币', '钱袋', '钱'):
        f.add('coin')
    if has('号角'):
        f.add('horn')
    if has('图腾'):
        f.add('totem')
    if has('战旗'):
        f.add('banner')
    if has('符'):
        f.add('scroll')
    if has('蛋', '卵'):
        f.add('egg')
    if has('荆棘', '棘'):
        f.add('thorn')
    if has('王座', '王冠'):
        f.add('crown')
    if has('棱', '针', '刺', '锥'):
        f.add('spike')
    if has('猎手', '猎头', '猎人', '狩猎'):
        f.add('hunter')
    if has('熔炉', '锻造'):
        f.add('forge')
    if has('爆炸', '爆'):
        f.add('explosion')
    if has('骑士'):
        f.add('fighter')
    return f

# ---------------- suggestion pools ----------------
SUGGEST_POOL = {
    'fire': ['candle', 'campfire', 'ring_of_fire', 'burned', 'torch', 'red_chili', 'bomb', 'fire_spell_2', 'on_fire_(burning)'],
    'ice': ['orb3', 'orb4', 'frozen', 'ice_spell', 'slowed', 'SWORDS_51', 'SWORDS_59'],
    'lightning': ['lightning_attack', 'lightning_spell', 'paralyzed', 'orb4', 'orb3', 'SWORDS_88', 'SWORDS_50'],
    'poison': ['poison', 'poisoned', 'mushrooms', 'herb3', 'big_egg', 'worm_bait', 'poison_dagger', 'skull_and_bones'],
    'water': ['water_spell', 'raining_arrows', 'sweat_drop', 'lake_trout', 'brown_trout', 'tropical_fish', 'sunken_chest', 'old_boot', 'octopus'],
    'wind': ['gust_of_air', 'swiftness', 'feathers', 'bow_and_arrow', 'crossbow', 'steeltoe_boots', 'leather_boots'],
    'blade': ['longsword', 'enchanted_sword', 'gladius', 'saber', 'battle_axe', 'dagger', 'broad_dagger', 'katana', 'whip', 'fist_hit', 'dripping_blade', 'battle_gear', 'saber_slash'],
    'defense': ['guard', 'buckler_shield', 'wooden_shield', 'checkered_shield', 'iron_armour', 'steel_armour', 'layered_plate_armour', 'tremor', 'defense_boost', 'fortify_spell'],
    'summon': ['summoning_spell', 'spellbook', 'runestone', 'open_book', 'tied_scroll', 'prayer_beads', 'open_scroll', 'tribal_necklace'],
    'curse': ['cursed', 'dizzy', 'silenced', 'charmed', 'shackles', 'attack_down', 'defense_down', 'confused', 'sleeping_eye', 'paralysis'],
    'crit': ['critical_boost', 'lucky_boost', 'headshot', 'dice', 'card', 'magnifying_glass', 'saber_slash'],
    'gold': ['gold_coin_stack', 'money_purse', 'large_gold_coin_stack', 'gold_necklace', 'crown_coin'],
    'lifesteal': ['bleeding', 'regeneration', 'heal_injury'],
    'orb': ['orb1', 'orb2', 'orb3', 'orb4', 'orb5', 'orb6', 'gems', 'rupee'],
    'heal': ['healing', 'heal_injury', 'bandage', 'regeneration'],
    'speed': ['swiftness', 'attack_speed_boost', 'steeltoe_boots', 'leather_boots'],
    'cooldown': ['repeat_arrow', 'hourglass', 'mana_replenish'],
    'atk': ['attack_boost', 'battle_gear', 'strong_arm'],
    'xp': ['exp_boost', 'open_book', 'book3'],
    'area': ['magic_amplification', 'element_boost', 'tremor', 'raining_arrows'],
    'slow': ['slowed', 'debuff_arrow1', 'sweat_drop'],
    'pierce': ['SPEARS_1', 'SPEARS_20', 'SPEARS_9'],
    'light': ['blinding_light_spell', 'sunrays', 'lantern'],
    'magic': ['counterspell', 'disintegrate', 'psychic_waves'],
    'bounce': ['knockback_boost', 'boomerang', 'mirror'],
    'knockback': ['knockback_boost', 'SPEARS_9'],
}

def short_to_path(short):
    if re.fullmatch(r"(SWORDS|SWORDS_COLOR_VARIANTS|STAFFS|AXES|MACES|DAGGERS|SPEARS|ALL)_\d+", short):
        p = os.path.join(ICONS, 'willibab', short + '.png')
        return 'res://assets/icons/willibab/' + short + '.png', os.path.exists(p)
    if short in VERARC_CAT:
        p = os.path.join(ICONS, 'verarc', short + '.png')
        return 'res://assets/icons/verarc/' + short + '.png', os.path.exists(p)
    if short in COORD:
        r, c = COORD[short]
        p = os.path.join(ICONS, 'shikashi', f'shikashi_r{r}_c{c}.png')
        return f'res://assets/icons/shikashi/shikashi_r{r}_c{c}.png', os.path.exists(p)
    return None, False

# ---------------- overrides (verdict, reason) ----------------
OVERRIDES = {
    'thunder_7': ('suspicious', '十手形似避雷针尖杆（方案超限分发）'),
    'ice_8': ('suspicious', '阵风=寒风意象，风达意但冰不达意（方案超限分发）'),
    'fire_ash_bringer': ('suspicious', '分解=湮灭意象，火感弱（方案超限分发）'),
    'summon_m8': ('suspicious', '守护盾=替身保护意象（方案保留）'),
    'summon_3': ('suspicious', '防御图标=图腾守护意象（方案保留）'),
    'summon_7': ('suspicious', '幸运图标=共鸣增幅意象（方案保留）'),
    'wind_tail_shot': ('suspicious', '弹弓=弹丸意象（方案超限分发）'),
    'wind_berserk': ('suspicious', '拳击=暴走攻击意象（方案超限分发）'),
    'orbit': ('suspicious', 'shell 无专属素材：法杖同款=环绕意象弱（方案已知）'),
    'burst': ('suspicious', 'shell 无专属素材：燃烧=爆发近似（方案已知）'),
    'delay': ('suspicious', 'shell 无专属素材：睡眠=延时近似（方案已知）'),
    'split': ('suspicious', 'shell 无专属素材：召唤阵=分身近似（方案已知）'),
    'crit_weak_mark': ('suspicious', '剑斩=弱点打击意象（方案超限分发）'),
    'summon_m10': ('suspicious', '战斧=军团武器意象（方案超限分发）'),
    'summon_m9': ('suspicious', '宝珠法杖=法阵意象弱（方案超限分发）'),
    'summon_m7': ('suspicious', '滴血刃=狂热嗜血意象（方案超限分发）'),
    'summon_m3': ('suspicious', '睡眠=死亡安眠意象（方案超限分发）'),
    'curse_omen': ('suspicious', '麻痹=厄运意象弱（方案超限分发）'),
    'curse_doom': ('suspicious', '麻痹=厄运意象弱（方案超限分发）'),
    'curse_all_as_one': ('suspicious', '念力波=万咒意象弱（方案超限分发）'),
    'defense_vengeance': ('suspicious', '链枷=复仇武器意象（方案超限分发）'),
    'thunder_m8': ('suspicious', '毛线=线圈形状意象（方案超限分发）'),
    'ice_glacial_haste': ('suspicious', '法杖=术架弱关联（新增条目，未入方案）'),
    'summon_4': ('suspicious', '部落项链=驯兽部落意象弱（方案超限分发）'),
    'summon_m6': ('suspicious', '宝箱=首领宝藏意象弱（方案超限分发）'),
    'summon_m5': ('suspicious', '成株盆栽=共生自然意象弱（方案超限分发）'),
    'summon_m2': ('suspicious', '念珠=献祭仪式意象（方案超限分发）'),
    'poison_m7': ('suspicious', '沙漏=慢性死亡时间意象（方案超限分发）'),
    'poison_m9': ('suspicious', '符文石=疫病之源意象弱（方案超限分发）'),
    'crit_m8': ('suspicious', '钻戒=完美珍贵意象（方案超限分发）'),
    'crit_deadly_rhythm': ('suspicious', '竖琴=节奏意象（方案超限分发）'),
    'curse_ink': ('suspicious', '信=书写墨水意象（方案超限分发）'),
    'curse_no_heal_word': ('suspicious', '绷带=禁疗意象（方案超限分发）'),
    'curse_no_heal_zone': ('suspicious', '绷带=禁疗意象（方案超限分发）'),
    'curse_agony': ('suspicious', '大脑=痛苦意象（方案超限分发）'),
    'curse_plague': ('suspicious', '草药=瘟疫毒草意象弱（方案超限分发）'),
    'curse_agony_loop': ('suspicious', '减益箭=折磨循环意象（方案超限分发）'),
    'defense_absorb': ('suspicious', '收钱=吸收意象弱（方案超限分发）'),
    'summon_war_banner': ('suspicious', 'ALL_* 内容未解析，无法确认是否为战旗'),
    'summon_graveyard_keep': ('suspicious', 'ALL_* 内容未解析，无法确认是否契合墓园守望'),
    'summon_overlord_edict': ('suspicious', 'ALL_* 内容未解析，无法确认是否契合军令'),
}

# ---------------- load data ----------------
def load():
    items = json.load(open('data/items.json', encoding='utf-8'))['items']
    spells = json.load(open('data/spells.json', encoding='utf-8'))
    wands = json.load(open('data/wands.json', encoding='utf-8'))['wands']
    summons = json.load(open('data/summons.json', encoding='utf-8'))['summons']
    entries = []
    for it in items:
        entries.append({'file': 'items', 'id': it['id'], 'name': it['name'],
                        'desc': it['description'], 'tags': it.get('tags') or [],
                        'icon': it['icon']})
    for grp, gname in (('cores', 'spells-cores'), ('shells', 'spells-shells')):
        for it in spells[grp]:
            entries.append({'file': gname, 'id': it['id'], 'name': it['name'],
                            'desc': it.get('description', ''), 'tags': [it.get('element', '')] if it.get('element') else [],
                            'icon': it['icon']})
    for it in wands:
        entries.append({'file': 'wands', 'id': it['id'], 'name': it['name'],
                        'desc': it.get('description', ''), 'tags': [it.get('school', '')] if it.get('school') else [],
                        'icon': it['icon']})
    for it in summons:
        entries.append({'file': 'summons', 'id': it['id'], 'name': it['name'],
                        'desc': it.get('description', ''), 'tags': [it.get('type', '')],
                        'icon': it['icon']})
    return entries

def bernoulli_map():
    try:
        raw = json.load(open('.tmp/icon_mapping_raw.json', encoding='utf-8'))
        return raw['mapping']
    except Exception:
        return {}

def main():
    entries = load()
    bmap = bernoulli_map()
    for e in entries:
        p = e['icon'].replace('res://', '')
        ok = os.path.exists(p)
        e['icon_path_ok'] = ok
        e['icon_short'] = os.path.splitext(os.path.basename(p))[0]
        e['icon_cats'], e['icon_desc'] = icon_semantics(e['icon_short'])
        e['hue'] = png_rgba(p) if ok and p.endswith('.png') else None
        e['schools'] = detect_schools(e)
        e['forms'] = detect_form(e)
    SCHOOL_COLOR = {'fire': '火', 'ice': '蓝', 'lightning': '黄', 'poison': '绿',
                    'water': '青', 'wind': '青'}
    for e in entries:
        sch = set(e['schools'])
        cats = set(e['icon_cats'])
        forms = set(e['forms'])
        hue = e['hue']
        e['hue_note'] = ''
        if hue and hue['sat'] > 0.15:
            for s in sch:
                if s in SCHOOL_COLOR and SCHOOL_COLOR[s] in hue['color']:
                    e['hue_note'] = f"主色{hue['color']}与{s}流派相符(偏色缓解)"
                    break
        overlap = sch & cats
        form_overlap = forms & cats
        if not e['icon_path_ok']:
            e['verdict'] = 'missing'
            e['reason'] = '路径不存在'
        elif overlap or form_overlap:
            e['verdict'] = 'match'
            e['reason'] = '语义重叠: ' + ','.join(sorted(overlap | form_overlap))
        elif not sch and not forms:
            e['verdict'] = 'suspicious'
            e['reason'] = '无法判定（无描述/标签）: ' + e['icon_desc']
        elif cats & {'blade', 'dagger', 'spike', 'spear', 'pierce', 'staff', 'axe', 'mace',
                     'bow', 'food', 'coin', 'gold', 'letter', 'map', 'key', 'chest',
                     'drink', 'card', 'hook', 'trap', 'ore',
                     'bag', 'helmet', 'gauntlet', 'ring', 'necklace', 'belt', 'pouch', 'boots',
                     'egg', 'banner', 'creature'}:
            e['verdict'] = 'mismatch'
            e['reason'] = '图标类别冲突: ' + e['icon_desc'] + ' (期望: ' + ','.join(sorted(sch)) + ')'
            if e['hue_note']:
                e['reason'] += '；' + e['hue_note']
        else:
            e['verdict'] = 'suspicious'
            e['reason'] = '泛用/中性图标: ' + e['icon_desc']
        ov = OVERRIDES.get(e['id'])
        if ov:
            e['verdict'], e['reason'] = ov
    # global usage counts (for suggestions)
    usage = Counter(e['icon_short'] for e in entries)
    # suggestions for non-match entries
    for e in entries:
        e['suggestion'] = None
        if e['verdict'] == 'match':
            continue
        SCH_PRIORITY = ['fire', 'ice', 'lightning', 'poison', 'water', 'wind', 'blade',
                        'defense', 'summon', 'curse', 'crit', 'lifesteal', 'light', 'magic',
                        'pierce', 'slow', 'heal', 'gold', 'orb', 'speed', 'cooldown', 'atk',
                        'xp', 'area', 'bounce', 'knockback']
        pool_keys = [s for s in SCH_PRIORITY if s in e['schools'] or s in e['forms']]
        pool_keys += [s for s in sorted(set(e['schools']) | set(e['forms'])) if s not in SCH_PRIORITY]
        for s in pool_keys:
            pool = SUGGEST_POOL.get(s)
            if not pool:
                continue
            best = None
            for cand in pool:
                if cand == e['icon_short']:
                    continue
                path, exists = short_to_path(cand)
                if not exists:
                    continue
                cur = usage.get(cand, 0)
                if cur >= 3:
                    continue
                if best is None or cur < best[1]:
                    best = (cand, cur)
            if best:
                path, _ = short_to_path(best[0])
                e['suggestion'] = {'short': best[0], 'path': path, 'current_uses': usage.get(best[0], 0)}
                break
    # sharing stats
    school_sharing = {}
    for e in entries:
        for s in e['schools']:
            school_sharing.setdefault(s, {}).setdefault(e['icon_short'], []).append(e['id'])
    global_share = {}
    for e in entries:
        global_share.setdefault(e['icon_short'], []).append(e['id'])
    # bernoulli overlap
    for e in entries:
        b = bmap.get(e['id'])
        if b is None:
            e['bernoulli'] = 'not_covered'
        else:
            planned = b['new']
            cur = e['icon_short']
            if planned == '保留':
                e['bernoulli'] = 'keep'
            elif cur == planned:
                e['bernoulli'] = 'implemented'
            else:
                e['bernoulli'] = f'drifted(方案:{planned})'
    for e in entries:
        e['icon_cats'] = sorted(e['icon_cats'])
        e['schools'] = sorted(e['schools'])
        e['forms'] = sorted(e['forms'])
    result = {'entries': entries, 'school_sharing': school_sharing, 'global_share': global_share}
    with open('work/e_audit_result.json', 'w', encoding='utf-8') as fh:
        json.dump(result, fh, ensure_ascii=False, indent=1)
    v = Counter(e['verdict'] for e in entries)
    print('total:', len(entries), dict(v))
    print('--- >3 global sharing (violations) ---')
    for k, vv in global_share.items():
        if len(vv) > 3:
            print(' ', k, len(vv), vv)
    print('--- mismatches ---')
    for e in entries:
        if e['verdict'] == 'mismatch':
            sug = e['suggestion']['path'] if e['suggestion'] else '-'
            print(e['file'], e['id'], e['name'], '->', e['icon_short'], '|', e['reason'][:70], '| 建议:', sug.split('/')[-1] if sug else '-')

if __name__ == '__main__':
    main()

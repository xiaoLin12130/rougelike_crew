#!/usr/bin/env python3
"""gen_enemy_anims.py - 怪物多帧动画贴图生成（怪物帧动画落地任务）

产出（全部写入 assets/sprites/enemy/，命名 <id>_idle_N.png / <id>_run_N.png）：
  1. boar（野猪，P0）：Legacy-Fantasy High Forest 2.3 Mob/Boar
     - Run-Sheet-Black.png 288x48 pitch=48 -> boar_run_0..5.png
     - Idle-Sheet-export-Back.png 192x48 pitch=48 -> boar_idle_0..3.png
  2. wolf（灰狼，P1）：复用野猪帧，按现有 wolf_1.png 调色板换银灰
  3. bat / rat：sunny-land eagle-attack-1..4 / opossum-1..6
  4. Retro-Lines Enemies.png 16x16 格帧串（2x NEAREST + 调色板映射）：
     ghost/mummy (2,5..8) imp (7,5..8) bomber (18,5..8) spider (20,0..3)
     mushroom/treant_sapling (19,10..12) lava_lizard (15,5..8)
     fire_wisp (6,7..10) scarab (13,5..8) charger (10,5..7)
  5. Pixel Crawler Free Pack 2.11 Mobs：Idle 4 帧(32x32 原生) + Run 6 帧
     (64x64 BOX 降采样到 32x32)，按现有贴图调色板映射：
     goblin=Orc cultist=Orc-Shaman specter=Skeleton-Mage
     bone_arbalest=Skeleton-Warrior gravedigger=Skeleton-Base
     temple_guardian=Orc-Warrior shadow_stalker=Skeleton-Rogue

调色板映射：以现有 <id>_1.png 的颜色集为目标调色板，源帧每个不透明像素
映射到最近的调色板色（RGB 欧氏距离），保留 alpha 与像素轮廓。
每怪先做掩膜 IoU 校验（源锚格 vs 现有贴图），不合格则跳过并告警。
"""

import os
import numpy as np
from PIL import Image

OUT = "assets/sprites/enemy"
RETRO = r".tools/user_assets/Retro-Lines-v3.4.3/Retro-Lines-16x16/Enemies.png"
SUNNY = r".tools/user_assets/sunny-land/Sunny-land-assets-files/PNG/sprites"
PC = r".tools/user_assets/Pixel Crawler - Free Pack 2.11/Pixel Crawler - Free Pack/Entities/Mobs"
BOAR_DIR = r".tools/user_assets/Legacy-Fantasy - High Forest 2.0/Legacy-Fantasy - High Forest 2.3/Mob/Boar"

os.makedirs(OUT, exist_ok=True)
results = []


def load(path):
    im = Image.open(path)
    return im.convert("RGBA") if im.mode != "RGBA" else im


def existing_path(eid):
    for d in (OUT, "assets/sprites/retro"):
        p = os.path.join(d, eid + "_1.png")
        if os.path.exists(p):
            return p
    return None


def mask(im):
    return np.asarray(im)[:, :, 3] > 0


def iou(a, b):
    a, b = mask(a), mask(b)
    inter = (a & b).sum()
    union = (a | b).sum()
    return inter / union if union else 0.0


def learn_mapping(src, target):
    """按像素位置对应学习源->目标颜色映射（同画布尺寸）。
    源色在重叠区出现的像素取目标处众数色；无对应的源色回退最近邻。"""
    sa = np.asarray(src)
    ta = np.asarray(target)
    assert sa.shape == ta.shape, (sa.shape, ta.shape)
    sm = sa[:, :, 3] > 0
    tm = ta[:, :, 3] > 0
    overlap = sm & tm
    mapping = {}
    for c in np.unique(sa[overlap][:, :3], axis=0):
        key = tuple(c)
        sel = overlap & (sa[:, :, :3] == c).all(axis=2)
        cols, counts = np.unique(ta[sel][:, :3], axis=0, return_counts=True)
        mapping[key] = tuple(cols[int(counts.argmax())])
    tpal = np.unique(ta[tm][:, :3], axis=0)
    for c in np.unique(sa[sm][:, :3], axis=0):
        key = tuple(c)
        if key in mapping:
            continue
        d = ((tpal.astype(int) - np.array(key, dtype=int)) ** 2).sum(axis=1)
        mapping[key] = tuple(tpal[int(d.argmin())])
    return mapping


def recolor(im, mapping):
    """按 mapping 重着色（不透明像素 RGB -> 最近调色板色）。"""
    arr = np.asarray(im).copy()
    a = arr[:, :, 3] > 0
    flat = arr[a]
    cols = np.unique(flat[:, :3], axis=0)
    lut = {}
    for c in cols:
        key = tuple(c)
        if key not in lut:
            m = mapping.get(key)
            if m is None:
                best, bd = None, None
                for t, _v in mapping.items():
                    d = (int(t[0]) - int(key[0])) ** 2 + (int(t[1]) - int(key[1])) ** 2 + (int(t[2]) - int(key[2])) ** 2
                    if bd is None or d < bd:
                        bd, best = d, t
                m = mapping[best]
            lut[key] = m
    for key, val in lut.items():
        sel = (flat[:, :3] == np.array(key, dtype=np.uint8)).all(axis=1)
        flat[sel, :3] = np.array(val, dtype=np.uint8)
    arr[a] = flat
    return Image.fromarray(arr)


def save(im, name):
    p = os.path.join(OUT, name)
    im.save(p)
    return p


def check_anchor(existing_path, anchor_im, label, thr=0.85):
    """掩膜 IoU 校验：现有贴图与源锚帧是否同形。"""
    ex = load(existing_path)
    ex2 = ex
    a2 = anchor_im
    if ex.size != a2.size:
        # 画布不同：尝试把锚帧缩放到现有画布（NEAREST）再比
        a2 = a2.resize(ex.size, Image.NEAREST)
    v = iou(ex2, a2)
    ok = v >= thr
    results.append((label, "anchor_iou=%.2f %s" % (v, "OK" if ok else "SKIP")))
    return ok, v


def color_agreement(mapped, existing):
    """映射结果与现有贴图的不透明像素颜色一致率（0..1）。"""
    m = np.asarray(mapped)
    e = np.asarray(existing)
    em = e[:, :, 3] > 0
    n = int(em.sum())
    if n == 0:
        return 0.0
    same = (m[em][:, :3] == e[em][:, :3]).all(axis=1).sum()
    return float(same) / n


def cut_boar():
    run = load(os.path.join(BOAR_DIR, "Run", "Run-Sheet-Black.png"))
    idle = load(os.path.join(BOAR_DIR, "Idle", "Idle-Sheet-export-Back.png"))
    assert run.size == (288, 32), run.size
    assert idle.size == (192, 32), idle.size
    for i in range(6):
        save(run.crop((i * 48, 0, i * 48 + 48, 32)), "boar_run_%d.png" % i)
    for i in range(4):
        save(idle.crop((i * 48, 0, i * 48 + 48, 32)), "boar_idle_%d.png" % i)
    results.append(("boar", "run 6f + idle 4f (48x32) OK"))


def make_wolf():
    idle_f0 = load(os.path.join(OUT, "boar_idle_0.png"))
    target = load(os.path.join(OUT, "wolf_1.png"))
    # 画布不同（48x32 vs 32x32）：缩到 32x32 学映射，再应用到全尺寸帧
    mapping = learn_mapping(idle_f0.resize((32, 32), Image.NEAREST), target)
    for i in range(4):
        f = load(os.path.join(OUT, "boar_idle_%d.png" % i))
        save(recolor(f, mapping), "wolf_idle_%d.png" % i)
    for i in range(6):
        f = load(os.path.join(OUT, "boar_run_%d.png" % i))
        save(recolor(f, mapping), "wolf_run_%d.png" % i)
    results.append(("wolf", "idle 4f + run 6f silver OK"))


def make_sunny(eid, files, frames):
    """bat/rat：sunny-land 独立帧文件，缩放到 32x32 画布 + 调色板映射。"""
    existing = existing_path(eid)
    src0 = load(os.path.join(SUNNY, files[0]))
    target = load(existing)
    # 缩放策略多选一（整帧 / 内容 bbox 不同目标尺寸居中），取掩膜 IoU 最高的
    m = mask(src0)
    ys, xs = np.where(m)
    box = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)
    cands = [("full", src0.resize((32, 32), Image.NEAREST))]
    crop = src0.crop(box)
    for s in (32, 30, 28, 26, 24):
        c = crop.resize((s, s), Image.NEAREST)
        canvas = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
        canvas.paste(c, ((32 - s) // 2, (32 - s) // 2))
        cands.append(("bbox%d" % s, canvas))
    best, best_v, best_label = None, 0.0, None
    for label, c in cands:
        v = iou(c, target)
        if v > best_v:
            best, best_v, best_label = c, v, label
    if best_v < 0.3:
        results.append((eid, "SKIP sunny iou=%.2f" % best_v))
        return
    mapping = learn_mapping(best, target)
    for i in range(frames):
        f = load(os.path.join(SUNNY, files[i]))
        if best_label == "bbox":
            m = mask(f)
            ys, xs = np.where(m)
            box = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)
            s = int(best_label[4:])
            c = f.crop(box).resize((s, s), Image.NEAREST)
            canvas = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
            canvas.paste(c, ((32 - s) // 2, (32 - s) // 2))
            f = canvas
        else:
            f = f.resize((32, 32), Image.NEAREST)
        save(recolor(f, mapping), "%s_idle_%d.png" % (eid, i))
    results.append((eid, "idle %df OK (iou=%.2f %s)" % (frames, best_v, best_label)))


RETRO_STRIPS = {
    "ghost": [(2, 5), (2, 6), (2, 7), (2, 8)],
    "mummy": [(2, 5), (2, 6), (2, 7), (2, 8)],
    "imp": [(7, 5), (7, 6), (7, 7), (7, 8)],
    "bomber": [(18, 5), (18, 6), (18, 7), (18, 8)],
    "spider": [(20, 0), (20, 1), (20, 2), (20, 3)],
    "lava_lizard": [(15, 5), (15, 6), (15, 7), (15, 8)],
    "fire_wisp": [(6, 7), (6, 8), (6, 9), (6, 10)],
    "scarab": [(13, 5), (13, 6), (13, 7), (13, 8)],
    "charger": [(10, 5), (10, 6), (10, 7)],
}


def make_retro():
    sheet = load(RETRO)
    for eid, strip in RETRO_STRIPS.items():
        existing = existing_path(eid)
        anchor = sheet.crop((strip[0][1] * 16, strip[0][0] * 16, strip[0][1] * 16 + 16, strip[0][0] * 16 + 16))
        anchor2 = anchor.resize((32, 32), Image.NEAREST)
        ok, v = check_anchor(existing, anchor2, eid)
        if not ok:
            continue
        target = load(existing)
        mapping = learn_mapping(anchor2, target)
        for i, (r, c) in enumerate(strip):
            cell = sheet.crop((c * 16, r * 16, c * 16 + 16, r * 16 + 16))
            cell = cell.resize((32, 32), Image.NEAREST)
            save(recolor(cell, mapping), "%s_idle_%d.png" % (eid, i))
        agree = color_agreement(recolor(anchor2, mapping), target)
        results.append((eid, "idle %df OK (agree=%.2f)" % (len(strip), agree)))


PC_MOBS = {
    "goblin": ("Orc Crew/Orc", "Idle/Idle-Sheet.png", "Run/Run-Sheet.png"),
    "cultist": ("Orc Crew/Orc - Shaman", "Idle/Idle-Sheet.png", "Run/Run-Sheet.png"),
    "specter": ("Skeleton Crew/Skeleton - Mage", "Idle/Idle-Sheet.png", "Run/Run-Sheet.png"),
    "bone_arbalest": ("Skeleton Crew/Skeleton - Warrior", "Idle/Idle-Sheet.png", "Run/Run-Sheet.png"),
    "gravedigger": ("Skeleton Crew/Skeleton - Base", "Idle/Idle-Sheet.png", "Run/Run-Sheet.png"),
    "temple_guardian": ("Orc Crew/Orc - Warrior", "Idle/Idle-Sheet.png", "Run/Run-Sheet.png"),
    "shadow_stalker": ("Skeleton Crew/Skeleton - Rogue", "Idle/Idle-Sheet.png", "Run/Run-Sheet.png"),
}


def make_pixel_crawler():
    for eid, (sub, idle_rel, run_rel) in PC_MOBS.items():
        base = os.path.join(PC, sub)
        idle_sheet = load(os.path.join(base, idle_rel))
        run_sheet = load(os.path.join(base, run_rel))
        assert idle_sheet.size == (128, 32), (eid, idle_sheet.size)
        assert run_sheet.size == (384, 64), (eid, run_sheet.size)
        idle_frames = [idle_sheet.crop((i * 32, 0, i * 32 + 32, 32)) for i in range(4)]
        run_frames = [run_sheet.crop((i * 64, 0, i * 64 + 64, 64)) for i in range(6)]
        existing = existing_path(eid)
        target = load(existing)
        mv = iou(idle_frames[0], target)
        if mv < 0.6:
            results.append((eid, "SKIP pc mv=%.2f" % mv))
            continue
        mapping = learn_mapping(idle_frames[0], target)
        agree = color_agreement(recolor(idle_frames[0], mapping), target)
        for i, f in enumerate(idle_frames):
            save(recolor(f, mapping), "%s_idle_%d.png" % (eid, i))
        for i, f in enumerate(run_frames):
            f32 = f.resize((32, 32), Image.BOX)
            save(recolor(f32, mapping), "%s_run_%d.png" % (eid, i))
        results.append((eid, "idle 4f + run 6f OK (mv=%.2f agree=%.2f)" % (mv, agree)))


def make_procedural_bounce(eid, anchor_cell, frames=3):
    """程序化弹跳帧：原帧 / 上移 1px / 压缩 0.9（单帧怪蘑菇/树苗用）。"""
    existing = existing_path(eid)
    target = load(existing)
    anchor2 = anchor_cell.resize((32, 32), Image.NEAREST)
    mapping = learn_mapping(anchor2, target)
    base = recolor(anchor2, mapping)
    w, h = base.size
    arr = np.asarray(base)
    a = arr[:, :, 3] > 0
    ys, xs = np.where(a)
    out = [base]
    if frames >= 2:
        up = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        up.paste(base, (0, -1))
        out.append(up)
    if frames >= 3:
        content = arr[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
        sq = Image.fromarray(content).resize(
            (content.shape[1], max(1, int(content.shape[0] * 0.9))), Image.NEAREST)
        flat = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        flat.paste(sq, (xs.min(), ys.max() + 1 - sq.size[1]))
        out.append(flat)
    for i, f in enumerate(out[:frames]):
        save(f, "%s_idle_%d.png" % (eid, i))
    results.append((eid, "idle %df procedural bounce OK" % len(out[:frames])))


def make_void_slime():
    """void_slime 补第 3 帧：slime_3 按现有 void_slime_1 调色板重着色。"""
    src = load(os.path.join(OUT, "slime_3.png"))
    target = load(os.path.join(OUT, "void_slime_1.png"))
    if src.size != target.size:
        return
    mapping = learn_mapping(load(os.path.join(OUT, "slime_1.png")), target)
    save(recolor(src, mapping), "void_slime_3.png")
    results.append(("void_slime", "idle 3f (added frame 3) OK"))


def main():
    cut_boar()
    make_wolf()
    make_sunny("bat", ["eagle/eagle-attack-%d.png" % i for i in range(1, 5)], 4)
    make_sunny("rat", ["opossum/opossum-%d.png" % i for i in range(1, 7)], 6)
    make_retro()
    make_pixel_crawler()
    sheet = load(RETRO)
    make_procedural_bounce("mushroom", sheet.crop((11 * 16, 19 * 16, 12 * 16, 20 * 16)))
    make_procedural_bounce("treant_sapling", sheet.crop((12 * 16, 19 * 16, 13 * 16, 20 * 16)))
    make_void_slime()
    print("== SUMMARY ==")
    for label, msg in results:
        print("%-16s %s" % (label, msg))


if __name__ == "__main__":
    main()

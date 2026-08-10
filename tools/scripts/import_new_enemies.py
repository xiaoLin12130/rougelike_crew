"""导入 Retro-Lines 新敌人 + Kenney pixel-platformer 蓝色生物（slime 替换）+ Pixel Crawler 巫师。

依据 docs/research/assets-user-characters.md §6 与 docs/research/assets-kenney-char.md §5：
- slime: kenney_pixel-platformer Tiles/Characters/tile_0018..0020（蓝色生物 3 帧，24x24 -> 32x32 画布贴底）
- crystal_sentry: Retro-Lines Enemies.png 列 10-12（菱形，32x32 格 -> 2x 64x64）
- spider: Retro-Lines Enemies.png 底部行 32x16（2 帧 -> 2x 64x32）
- mimic_block: Retro-Lines Enemies.png 列 5-8 行 6（方块脸弹跳 4 帧，16x16 -> 2x 32x32）
- specter: Retro-Lines Enemies.png 列 7-8 行 1（幽灵 2 帧，16x16 -> 2x 32x32）
- bat: Retro-Lines Enemies.png 列 5-6 行 7（黄身蓝翼飞行怪 2 帧，16x16 -> 2x 32x32）
- ghost: Retro-Lines Enemies.png 列 5-6 行 5（奶白圆脸幽灵 2 帧，16x16 -> 2x 32x32）
- goblin: Retro-Lines Enemies.png 列 5-6 行 4（黄头小人形怪 2 帧，16x16 -> 2x 32x32）
- wizard: Pixel Crawler Wizzard Idle-Sheet.png 帧 0/1（紫袍巫师，32x32 原生 2 帧待机）
- Bosses.png 4 个大精灵按内容 bbox 收紧保存（备用，供中 Boss/换皮）

幂等：重复运行会覆盖同名输出。
"""

import os
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RETRO = os.path.join(ROOT, ".tools", "user_assets", "Retro-Lines-v3.4.3", "Retro-Lines-16x16")
KENNEY_CHARS = os.path.join(ROOT, ".tools", "kenney_pixel-platformer", "Tiles", "Characters")
PIXEL_CRAWLER = os.path.join(ROOT, ".tools", "user_assets", "Pixel Crawler - Free Pack 2.11", "Pixel Crawler - Free Pack")
PIXEL_CRAWLER_MOBS = os.path.join(PIXEL_CRAWLER, "Entities", "Mobs")
OUT_KENNEY = os.path.join(ROOT, "assets", "sprites", "kenney")
OUT_RETRO = os.path.join(ROOT, "assets", "sprites", "retro")


def save(im: Image.Image, name: str) -> None:
    os.makedirs(os.path.dirname(name), exist_ok=True)
    im.save(name)
    print("saved", os.path.relpath(name, ROOT), im.size)


def paste_centered(canvas: Image.Image, content: Image.Image, bottom: bool = False) -> None:
    x = (canvas.width - content.width) // 2
    y = (canvas.height - content.height) if bottom else (canvas.height - content.height) // 2
    canvas.paste(content, (x, max(y, 0)), content)


def crop_content(src: Image.Image, box) -> Image.Image:
    """box = (x0,y0,x1,y1) 像素框；按 alpha bbox 收紧。"""
    reg = src.crop(box)
    b = reg.split()[3].getbbox()
    if b is None:
        return reg
    return reg.crop(b)


def up2(im: Image.Image) -> Image.Image:
    return im.resize((im.width * 2, im.height * 2), Image.NEAREST)


def import_slime() -> None:
    for i, t in enumerate([18, 19, 20]):
        src = Image.open(os.path.join(KENNEY_CHARS, "tile_%04d.png" % t)).convert("RGBA")
        content = crop_content(src, (0, 0, 24, 24))
        canvas = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
        paste_centered(canvas, content, bottom=True)
        save(canvas, os.path.join(OUT_KENNEY, "slime_%d.png" % (i + 1)))


def import_retro_enemies() -> None:
    en = Image.open(os.path.join(RETRO, "Enemies.png")).convert("RGBA")
    # 水晶哨兵：列 10-12，行 1-3 的菱形（32x32 格）
    box = (10 * 16, 1 * 16, 12 * 16, 3 * 16)
    canvas = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    paste_centered(canvas, up2(crop_content(en, box)))
    save(canvas, os.path.join(OUT_RETRO, "crystal_1.png"))
    # 蜘蛛：底部行 20，列 0-1 / 2-3（32x16 格，2 帧）
    for i, cx in enumerate([0, 2]):
        box = (cx * 16, 20 * 16, (cx + 2) * 16, 21 * 16)
        canvas = Image.new("RGBA", (64, 32), (0, 0, 0, 0))
        paste_centered(canvas, up2(crop_content(en, box)))
        save(canvas, os.path.join(OUT_RETRO, "spider_%d.png" % (i + 1)))
    # 魔像方块：列 5-8 行 6（弹跳 4 帧）。整格 2x 保留格内相对位置（弹跳轨迹），不按 bbox 收紧。
    for i, cx in enumerate(range(5, 9)):
        box = (cx * 16, 6 * 16, (cx + 1) * 16, 7 * 16)
        save(up2(en.crop(box)), os.path.join(OUT_RETRO, "mimic_%d.png" % (i + 1)))
    # 幽灵：列 7-8 行 1（2 帧微动），同样保留格内位置
    for i, cx in enumerate([7, 8]):
        box = (cx * 16, 1 * 16, (cx + 1) * 16, 2 * 16)
        save(up2(en.crop(box)), os.path.join(OUT_RETRO, "specter_%d.png" % (i + 1)))


def import_bosses() -> None:
    bs = Image.open(os.path.join(RETRO, "Bosses.png")).convert("RGBA")
    regions = [(0, 6), (7, 13), (14, 20), (21, 27)]
    for i, (c0, c1) in enumerate(regions):
        content = crop_content(bs, (c0 * 16, 0, c1 * 16, 64))
        save(content, os.path.join(OUT_RETRO, "boss_%d.png" % (i + 1)))


def import_bat_ghost_goblin() -> None:
    """bat / ghost / goblin：Retro-Lines Enemies.png 16x16 双帧 -> 2x 32x32 画布。

    选型依据（与既有 crystal/spider/mimic/specter 同表，风格统一）：
    - bat:   行 7 列 5-6，黄身蓝翼飞行怪（展翼拍翅 2 帧）
    - ghost: 行 5 列 5-6，奶白圆脸幽灵 blob（2 帧微动）
    - goblin:行 4 列 5-6，黄头小人形怪（2 帧交替步）
    整格 2x 保留格内相对位置（与 specter/mimic 一致），不按 bbox 收紧。
    """
    en = Image.open(os.path.join(RETRO, "Enemies.png")).convert("RGBA")
    plan = {
        "bat": [(7, 5), (7, 6)],
        "ghost": [(5, 5), (5, 6)],
        "goblin": [(4, 5), (4, 6)],
    }
    for name, cells in plan.items():
        for i, (r, c) in enumerate(cells):
            box = (c * 16, r * 16, (c + 1) * 16, (r + 1) * 16)
            save(up2(en.crop(box)), os.path.join(OUT_RETRO, "%s_%d.png" % (name, i + 1)))


def import_wizard() -> None:
    """wizard：Pixel Crawler 包 Wizzard NPC Idle-Sheet.png 帧 0/3（紫袍巫师 2 帧待机）。

    帧为 32x32 原生像素（游戏画布同尺寸），按 alpha bbox 收紧后居中贴到 32x32 画布，
    保持 1x 原生细节（不放大）；底部对齐（脚落地），两帧帽尖 1px 高低差构成待机浮动。
    """
    sheet = Image.open(
        os.path.join(PIXEL_CRAWLER, "Entities", "Npc's", "Wizzard", "Idle", "Idle-Sheet.png")
    ).convert("RGBA")
    for out_i, i in enumerate([0, 3]):
        cell = sheet.crop((i * 32, 0, (i + 1) * 32, 32))
        content = crop_content(cell, (0, 0, 32, 32))
        canvas = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
        paste_centered(canvas, content, bottom=True)
        save(canvas, os.path.join(OUT_RETRO, "wizard_%d.png" % (out_i + 1)))


def import_legacy_six() -> None:
    """Second batch: imp / skeleton / goblin_archer / charger / healer / bomber.

    Matching old gen sprites (assets/sprites/gen/):
    - imp:    Retro-Lines Enemies.png row3 col5-6 (orange horned imp w/ tail,
              2-frame bob; matches gen enemy_imp orange horned shape)
    - charger: Retro-Lines Enemies.png row10 col5-6 (orange round charging
              beast, 2-frame bound; matches gen enemy_charger beast shape)
    - bomber: Retro-Lines Enemies.png row12 col0-1 (red round-headed creature
              w/ 4 legs, 2-frame step; red = explosive, matches gen bomber)
    - skeleton: Pixel Crawler Mobs/Skeleton Crew/Skeleton - Base/Idle frame 0/3
    - goblin_archer: Pixel Crawler Mobs/Orc Crew/Orc - Rogue/Idle frame 0/3
              (green orc holding bow, native 32x32 like wizard)
    - healer: Pixel Crawler Mobs/Orc Crew/Orc - Shaman/Idle frame 0/3
              (red-robed witch doctor w/ staff, native 32x32 like wizard)
    Retro-Lines cells are 2x upscaled full 16x16 grid (same as bat/ghost/goblin);
    Pixel Crawler frames keep native 1x with alpha-bbox crop, bottom aligned
    (same as wizard).
    """
    en = Image.open(os.path.join(RETRO, "Enemies.png")).convert("RGBA")
    retro_plan = {
        "imp": [(3, 5), (3, 6)],
        "charger": [(10, 5), (10, 6)],
        "bomber": [(12, 0), (12, 1)],
    }
    for name, cells in retro_plan.items():
        for i, (r, c) in enumerate(cells):
            box = (c * 16, r * 16, (c + 1) * 16, (r + 1) * 16)
            save(up2(en.crop(box)), os.path.join(OUT_RETRO, "%s_%d.png" % (name, i + 1)))
    pc_plan = {
        "skeleton": (os.path.join(PIXEL_CRAWLER_MOBS, "Skeleton Crew", "Skeleton - Base", "Idle", "Idle-Sheet.png"), [0, 3]),
        "goblin_archer": (os.path.join(PIXEL_CRAWLER_MOBS, "Orc Crew", "Orc - Rogue", "Idle", "Idle-Sheet.png"), [0, 3]),
        "healer": (os.path.join(PIXEL_CRAWLER_MOBS, "Orc Crew", "Orc - Shaman", "Idle", "Idle-Sheet.png"), [0, 3]),
    }
    for name, (sheet_path, frames) in pc_plan.items():
        sheet = Image.open(sheet_path).convert("RGBA")
        for out_i, i in enumerate(frames):
            cell = sheet.crop((i * 32, 0, (i + 1) * 32, 32))
            content = crop_content(cell, (0, 0, 32, 32))
            canvas = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
            paste_centered(canvas, content, bottom=True)
            save(canvas, os.path.join(OUT_RETRO, "%s_%d.png" % (name, out_i + 1)))


def main() -> None:
    import_slime()
    import_retro_enemies()
    import_bosses()
    import_bat_ghost_goblin()
    import_wizard()
    import_legacy_six()
    print("done")


if __name__ == "__main__":
    main()

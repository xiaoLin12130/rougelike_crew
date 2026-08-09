"""导入 Retro-Lines 4 种新敌人 + Kenney pixel-platformer 蓝色生物（slime 替换）。

依据 docs/research/assets-user-characters.md §6 与 docs/research/assets-kenney-char.md §5：
- slime: kenney_pixel-platformer Tiles/Characters/tile_0018..0020（蓝色生物 3 帧，24x24 -> 32x32 画布贴底）
- crystal_sentry: Retro-Lines Enemies.png 列 10-12（菱形，32x32 格 -> 2x 64x64）
- spider: Retro-Lines Enemies.png 底部行 32x16（2 帧 -> 2x 64x32）
- mimic_block: Retro-Lines Enemies.png 列 5-8 行 6（方块脸弹跳 4 帧，16x16 -> 2x 32x32）
- specter: Retro-Lines Enemies.png 列 7-8 行 1（幽灵 2 帧，16x16 -> 2x 32x32）
- Bosses.png 4 个大精灵按内容 bbox 收紧保存（备用，供中 Boss/换皮）

幂等：重复运行会覆盖同名输出。
"""

import os
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RETRO = os.path.join(ROOT, ".tools", "user_assets", "Retro-Lines-v3.4.3", "Retro-Lines-16x16")
KENNEY_CHARS = os.path.join(ROOT, ".tools", "kenney_pixel-platformer", "Tiles", "Characters")
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


def main() -> None:
    import_slime()
    import_retro_enemies()
    import_bosses()
    print("done")


if __name__ == "__main__":
    main()

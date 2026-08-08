"""Procedurally generate consistent 32x32 pixel-art sprites (player/enemies/projectiles/tiles).

All sprites are original (no license issues). 16px base grid, sprites at 2x scale.
Usage:
    python tools/scripts/gen_sprites.py
"""

import os
import random

from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "sprites", "gen")
SZ = 32

# palette (name -> (r,g,b,a))
PAL = {
    "outline": (24, 20, 32, 255),
    "skin": (240, 214, 170, 255),
    "robe": (124, 76, 200, 255),
    "robe_dark": (88, 52, 150, 255),
    "hat": (96, 58, 170, 255),
    "hat_band": (230, 180, 60, 255),
    "eye": (24, 20, 32, 255),
    "white": (235, 235, 235, 255),
    "slime": (86, 200, 92, 255),
    "slime_dark": (58, 148, 66, 255),
    "slime_king": (58, 160, 220, 255),
    "slime_king_dark": (36, 110, 160, 255),
    "bat": (120, 78, 170, 255),
    "bat_dark": (84, 52, 124, 255),
    "ghost": (215, 225, 240, 235),
    "ghost_dark": (150, 165, 195, 200),
    "goblin": (110, 170, 80, 255),
    "goblin_dark": (74, 122, 54, 255),
    "bone": (226, 222, 208, 255),
    "bone_dark": (160, 155, 140, 255),
    "gold": (240, 200, 70, 255),
    "fire": (240, 120, 40, 255),
    "fire_hi": (255, 210, 90, 255),
    "ice": (120, 200, 240, 255),
    "ice_hi": (220, 245, 255, 255),
    "lightning": (255, 230, 90, 255),
    "poison": (150, 210, 90, 255),
    "poison_dark": (90, 150, 60, 255),
    "blade": (210, 215, 230, 255),
    "blade_dark": (120, 128, 150, 255),
    "grass1": (88, 158, 74, 255),
    "grass2": (76, 142, 64, 255),
    "grass3": (104, 176, 88, 255),
    "dirt1": (126, 92, 62, 255),
    "dirt2": (110, 80, 54, 255),
    "stone1": (116, 116, 128, 255),
    "stone2": (100, 100, 112, 255),
    "water1": (56, 110, 180, 255),
    "water2": (72, 128, 200, 255),
}


class Canvas:
    def __init__(self, w=SZ, h=SZ):
        self.w = w
        self.h = h
        self.px = [[None] * w for _ in range(h)]

    def set(self, x, y, color):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y][x] = color

    def rect(self, x, y, w, h, color):
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                self.set(xx, yy, color)

    def ellipse(self, cx, cy, rx, ry, color):
        for yy in range(int(cy - ry), int(cy + ry) + 1):
            for xx in range(int(cx - rx), int(cx + rx) + 1):
                dx = (xx - cx) / max(rx, 0.5)
                dy = (yy - cy) / max(ry, 0.5)
                if dx * dx + dy * dy <= 1.0:
                    self.set(xx, yy, color)

    def circle(self, cx, cy, r, color):
        self.ellipse(cx, cy, r, r, color)

    def image(self):
        img = Image.new("RGBA", (self.w, self.h))
        d = img.load()
        for y in range(self.h):
            for x in range(self.w):
                c = self.px[y][x]
                if c:
                    d[x, y] = c
        return img


def outline_canvas(c: Canvas, keep_color=None):
    """Add dark outline around non-empty pixels (pixel-art look)."""
    src = [[c.px[y][x] for x in range(c.w)] for y in range(c.h)]
    for y in range(c.h):
        for x in range(c.w):
            if src[y][x] is None:
                continue
            for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                ny, nx = y + dy, x + dx
                if 0 <= ny < c.h and 0 <= nx < c.w and src[ny][nx] is None:
                    c.set(nx, ny, PAL["outline"])


def save(c: Canvas, name):
    outline_canvas(c)
    img = c.image()
    img.save(os.path.join(OUT, name + ".png"))


def player(dir_key, frame):
    c = Canvas()
    # body/robe
    c.rect(10, 14, 12, 13, PAL["robe"])
    c.rect(10, 18, 12, 3, PAL["robe_dark"])
    # head
    c.rect(11, 6, 10, 9, PAL["skin"])
    # hat
    c.rect(9, 3, 14, 5, PAL["hat"])
    c.rect(9, 3, 14, 2, PAL["hat_band"])
    c.rect(9, 1, 4, 3, PAL["hat"])
    # eyes per direction
    if dir_key == "up":
        c.rect(13, 9, 2, 2, PAL["eye"])
        c.rect(18, 9, 2, 2, PAL["eye"])
    elif dir_key == "down":
        c.rect(13, 10, 2, 2, PAL["eye"])
        c.rect(18, 10, 2, 2, PAL["eye"])
    elif dir_key == "left":
        c.rect(12, 10, 2, 2, PAL["eye"])
    else:
        c.rect(19, 10, 2, 2, PAL["eye"])
    # feet bob
    bob = 1 if frame == 2 else 0
    c.rect(10, 27 + bob, 4, 3, PAL["robe_dark"])
    c.rect(18, 27 + bob, 4, 3, PAL["robe_dark"])
    # staff
    c.rect(24, 12, 2, 18, PAL["bone_dark"])
    c.circle(25, 11, 3, PAL["fire_hi"])
    return c


def slime(frame):
    c = Canvas()
    h = 12 - frame  # squash
    c.ellipse(16, 22, 10, 8 + h, PAL["slime"])
    c.ellipse(11, 16, 6, 5 + h, PAL["slime"])
    c.ellipse(21, 16, 6, 5 + h, PAL["slime"])
    c.rect(13, 17, 2, 3, PAL["eye"])
    c.rect(19, 17, 2, 3, PAL["eye"])
    c.rect(15, 21, 3, 2, PAL["slime_dark"])
    return c


def slime_king():
    c = Canvas()
    c.ellipse(16, 22, 14, 10, PAL["slime_king"])
    c.ellipse(9, 15, 8, 7, PAL["slime_king"])
    c.ellipse(23, 15, 8, 7, PAL["slime_king"])
    c.rect(13, 16, 2, 4, PAL["eye"])
    c.rect(20, 16, 2, 4, PAL["eye"])
    c.rect(14, 22, 5, 2, PAL["slime_king_dark"])
    # crown
    c.rect(11, 8, 12, 3, PAL["gold"])
    c.rect(12, 5, 2, 4, PAL["gold"])
    c.rect(16, 5, 2, 4, PAL["gold"])
    c.rect(20, 5, 2, 4, PAL["gold"])
    return c


def bat(frame):
    c = Canvas()
    up = frame == 1
    # wings
    if up:
        c.rect(2, 12, 10, 3, PAL["bat"])
        c.rect(2, 9, 4, 3, PAL["bat_dark"])
        c.rect(20, 12, 10, 3, PAL["bat"])
        c.rect(26, 9, 4, 3, PAL["bat_dark"])
    else:
        c.rect(2, 16, 12, 3, PAL["bat"])
        c.rect(2, 19, 4, 3, PAL["bat_dark"])
        c.rect(18, 16, 12, 3, PAL["bat"])
        c.rect(26, 19, 4, 3, PAL["bat_dark"])
    # body
    c.ellipse(16, 17, 6, 7, PAL["bat"])
    # ears
    c.rect(12, 9, 2, 4, PAL["bat_dark"])
    c.rect(18, 9, 2, 4, PAL["bat_dark"])
    # eyes
    c.rect(13, 15, 2, 2, PAL["eye"])
    c.rect(18, 15, 2, 2, PAL["eye"])
    return c


def ghost(frame):
    c = Canvas()
    wave = 2 if frame == 2 else 0
    c.ellipse(16, 14, 8, 9, PAL["ghost"])
    c.rect(8, 14, 16, 9, PAL["ghost"])
    # wavy bottom
    c.rect(8, 23, 4, 3, PAL["ghost"])
    c.rect(16, 23, 4, 3, PAL["ghost"])
    c.rect(24, 23, 2, 3, PAL["ghost"])
    c.rect(12, 26, 4, 2, PAL["ghost_dark"])
    c.rect(20, 26, 4, 2, PAL["ghost_dark"])
    # eyes
    c.rect(12, 13, 3, 4, PAL["ghost_dark"])
    c.rect(18, 13, 3, 4, PAL["ghost_dark"])
    # mouth
    c.rect(14, 19, 5, 2, PAL["ghost_dark"])
    return c


def humanoid(body, body_dark, frame, archer=False):
    c = Canvas()
    bob = 1 if frame == 2 else 0
    # legs
    c.rect(12, 24 + bob, 4, 5, body_dark)
    c.rect(18, 24 + bob, 4, 5, body_dark)
    # body
    c.rect(11, 15, 11, 10, body)
    # arms
    if archer:
        c.rect(6, 16, 6, 3, body_dark)
        c.rect(22, 16, 5, 3, body_dark)
    else:
        c.rect(7, 16, 5, 3, body_dark)
        c.rect(22, 16, 5, 3, body_dark)
    # head
    c.rect(12, 7, 9, 9, body)
    # eyes
    c.rect(14, 10, 2, 2, PAL["eye"])
    c.rect(19, 10, 2, 2, PAL["eye"])
    return c


def goblin(frame):
    return humanoid(PAL["goblin"], PAL["goblin_dark"], frame)


def goblin_archer(frame):
    return humanoid(PAL["goblin"], PAL["goblin_dark"], frame, archer=True)


def skeleton(frame):
    return humanoid(PAL["bone"], PAL["bone_dark"], frame)


def skeleton_king():
    c = humanoid(PAL["bone"], PAL["bone_dark"], 1)
    c.rect(11, 3, 11, 3, PAL["gold"])
    c.rect(12, 1, 3, 3, PAL["gold"])
    c.rect(18, 1, 3, 3, PAL["gold"])
    return c


def golem():
    c = Canvas()
    c.rect(8, 10, 17, 18, PAL["stone2"])
    c.rect(8, 10, 17, 4, PAL["stone1"])
    c.rect(12, 6, 9, 6, PAL["stone2"])
    c.rect(13, 8, 2, 2, PAL["fire_hi"])
    c.rect(19, 8, 2, 2, PAL["fire_hi"])
    c.rect(12, 28, 4, 4, PAL["stone1"])
    c.rect(18, 28, 4, 4, PAL["stone1"])
    c.rect(7, 16, 4, 3, PAL["stone1"])
    c.rect(22, 16, 4, 3, PAL["stone1"])
    return c


def imp(frame):
    c = humanoid(PAL["fire"], PAL["fire_hi"], frame)
    # horns
    c.rect(11, 4, 3, 3, PAL["bone"])
    c.rect(19, 4, 3, 3, PAL["bone"])
    # tail
    c.rect(24, 22, 5, 2, PAL["fire_hi"])
    return c


def projectile(kind):
    c = Canvas(12, 12)
    if kind == "fireball":
        c.circle(6, 6, 4, PAL["fire"])
        c.circle(6, 6, 2, PAL["fire_hi"])
    elif kind == "ice":
        c.rect(4, 1, 2, 4, PAL["ice_hi"])
        c.rect(5, 3, 3, 6, PAL["ice"])
        c.rect(6, 1, 2, 9, PAL["ice_hi"])
        c.rect(5, 7, 3, 3, PAL["ice"])
    elif kind == "lightning":
        c.rect(5, 1, 2, 3, PAL["lightning"])
        c.rect(4, 3, 2, 3, PAL["lightning"])
        c.rect(6, 5, 2, 4, PAL["lightning"])
        c.rect(5, 8, 2, 3, PAL["lightning"])
    elif kind == "poison":
        c.ellipse(6, 7, 5, 4, PAL["poison"])
        c.rect(5, 2, 2, 4, PAL["poison_dark"])
        c.circle(5, 5, 1, PAL["poison_dark"])
    elif kind == "blade":
        c.rect(4, 2, 3, 8, PAL["blade"])
        c.rect(5, 1, 1, 2, PAL["blade_dark"])
    return c


def tile(kind, seed):
    rng = random.Random(seed)
    c = Canvas(16, 16)
    if kind == "grass":
        base = PAL["grass1"]
        alt = [PAL["grass2"], PAL["grass3"]]
    elif kind == "dirt":
        base = PAL["dirt1"]
        alt = [PAL["dirt2"]]
    elif kind == "stone":
        base = PAL["stone1"]
        alt = [PAL["stone2"]]
    else:
        base = PAL["water1"]
        alt = [PAL["water2"]]
    for y in range(16):
        for x in range(16):
            c.set(x, y, base)
    for _ in range(24):
        x, y = rng.randrange(16), rng.randrange(16)
        col = rng.choice(alt)
        c.set(x, y, col)
        c.set(x, (y + 1) % 16, col)
    return c


def main():
    os.makedirs(OUT, exist_ok=True)
    n = 0
    for d in ["up", "down", "left", "right"]:
        for f in [1, 2]:
            save(player(d, f), f"player_{d}_{f}")
            n += 1
    save(slime(1), "enemy_slime_1")
    save(slime(2), "enemy_slime_2")
    save(bat(1), "enemy_bat_1")
    save(bat(2), "enemy_bat_2")
    save(ghost(1), "enemy_ghost_1")
    save(ghost(2), "enemy_ghost_2")
    save(goblin(1), "enemy_goblin_1")
    save(goblin(2), "enemy_goblin_2")
    save(goblin_archer(1), "enemy_archer_1")
    save(goblin_archer(2), "enemy_archer_2")
    save(skeleton(1), "enemy_skeleton_1")
    save(skeleton(2), "enemy_skeleton_2")
    save(imp(1), "enemy_imp_1")
    save(imp(2), "enemy_imp_2")
    save(slime_king(), "boss_slime_king")
    save(skeleton_king(), "boss_skeleton_king")
    save(golem(), "boss_tree_golem")
    save(golem(), "boss_lava_golem")
    save(golem(), "boss_ancient_guardian")
    save(imp(1), "boss_imp_king")
    n += 18
    for k in ["fireball", "ice", "lightning", "poison", "blade"]:
        save(projectile(k), f"proj_{k}")
        n += 1
    for k, s in [("grass", 7), ("dirt", 13), ("stone", 29), ("water", 55)]:
        save(tile(k, s), f"tile_{k}")
        n += 1
    print(f"generated {n} sprites -> {OUT}")


if __name__ == "__main__":
    main()

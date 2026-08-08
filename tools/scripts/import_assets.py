"""Copy curated free assets from H:\\job_prep into the project, record credits.

Usage:
    python tools/scripts/import_assets.py
"""

import os
import shutil

SRC = os.path.join(r"H:\job_prep", "\u514d\u8d39\u7d20\u6750")  # 免费素材
DEST = os.path.join(os.path.dirname(__file__), "..", "..", "assets")

# (source relative path, dest relative path)
COPIES = [
    # Sunny Land: 背景/道具/拾取物/死亡特效帧/反馈帧/音效
    (r"Sunny Land\Sunny-land-assets-files\PNG\environment\layers\back.png", r"env\back_forest.png"),
    (r"Sunny Land\Sunny-land-assets-files\PNG\environment\layers\middle.png", r"env\mid_forest.png"),
    (r"Sunny Land\Sunny-land-assets-files\PNG\environment\layers\tileset.png", r"env\tileset_grass.png"),
    (r"Sunny Land\Sunny-land-assets-files\PNG\environment\props\tree.png", r"env\prop_tree.png"),
    (r"Sunny Land\Sunny-land-assets-files\PNG\environment\props\rock.png", r"env\prop_rock.png"),
    (r"Sunny Land\Sunny-land-assets-files\PNG\environment\props\bush.png", r"env\prop_bush.png"),
    (r"Sunny Land\Sunny-land-assets-files\PNG\environment\props\sign.png", r"env\prop_sign.png"),
    (r"Sunny Land\Sunny-land-assets-files\PNG\sprites\gem", r"pickups\gem"),
    (r"Sunny Land\Sunny-land-assets-files\PNG\sprites\cherry", r"pickups\cherry"),
    (r"Sunny Land\Sunny-land-assets-files\PNG\sprites\item-feedback", r"fx\item_feedback"),
    (r"Sunny Land\Sunny-land-assets-files\PNG\sprites\enemy-death", r"fx\enemy_death"),
    # Space Shooter Redux: 激光/特效/能量道具/UI/音效/字体
    (r"Space Shooter Redux\PNG\Lasers", r"projectiles\lasers"),
    (r"Space Shooter Redux\PNG\Effects", r"fx\shooter"),
    (r"Space Shooter Redux\PNG\Meteors", r"fx\meteors"),
    (r"Space Shooter Redux\PNG\Power-ups", r"pickups\powerups"),
    (r"Space Shooter Redux\PNG\UI", r"ui\shooter"),
    (r"Space Shooter Redux\PNG\Damage", r"fx\damage"),
    (r"Space Shooter Redux\Bonus\kenvector_future.ttf", r"fonts\kenvector_future.ttf"),
    (r"Space Shooter Redux\Bonus\sfx_laser1.ogg", r"audio\sfx_laser1.ogg"),
    (r"Space Shooter Redux\Bonus\sfx_laser2.ogg", r"audio\sfx_laser2.ogg"),
    (r"Space Shooter Redux\Bonus\sfx_shieldUp.ogg", r"audio\sfx_shield_up.ogg"),
    (r"Space Shooter Redux\Bonus\sfx_shieldDown.ogg", r"audio\sfx_shield_down.ogg"),
    (r"Space Shooter Redux\Bonus\sfx_twoTone.ogg", r"audio\sfx_two_tone.ogg"),
    (r"Space Shooter Redux\Bonus\sfx_zap.ogg", r"audio\sfx_zap.ogg"),
    (r"Space Shooter Redux\Bonus\sfx_lose.ogg", r"audio\sfx_lose.ogg"),
]

# Game Icons SVG（按主题挑选，来源作者）
ICONS = {
    "fire": r"delapouite\fire-gem.svg",
    "ice": r"lorc\snowflake-2.svg",
    "lightning": r"lorc\heavy-lightning.svg",
    "poison": r"lorc\poison-bottle.svg",
    "sword": r"delapouite\rusty-sword.svg",
    "shield": r"delapouite\cross-shield.svg",
    "potion": r"lorc\potion-ball.svg",
    "boots": r"delapouite\metal-boot.svg",
    "clover": r"lorc\clover.svg",
    "book": r"delapouite\book-cover.svg",
    "skull": r"lorc\animal-skull.svg",
    "gem": r"lorc\gem-chain.svg",
    "star": r"delapouite\falling-star.svg",
    "coin": r"delapouite\coins.svg",
    "dagger": r"lorc\broad-dagger.svg",
    "bow": r"delapouite\bow-arrow.svg",
    "staff": r"lorc\wizard-staff.svg",
    "ring": r"lorc\engagement-ring.svg",
    "crown": r"delapouite\imperial-crown.svg",
    "heart": r"delapouite\heart-battery.svg",
    "eye": r"delapouite\all-seeing-eye.svg",
    "wing": r"delapouite\arrow-wings.svg",
    "scroll": r"lorc\scroll-unfurled.svg",
    "flask": r"lorc\bubbling-flask.svg",
    "snowflake": r"lorc\snowflake-1.svg",
    "tornado": r"lorc\tornado-discs.svg",
    "spider": r"lorc\angular-spider.svg",
    "bat": r"delapouite\bat.svg",
    "ghost": r"lorc\ghost.svg",
    "slime": r"delapouite\slime.svg",
    "magic": r"delapouite\magic-hat.svg",
    "axe": r"delapouite\magic-axe.svg",
    "hammer": r"delapouite\warhammer.svg",
    "crystal": r"lorc\crystal-bars.svg",
    "magnet": r"lorc\magnet.svg",
    "hourglass": r"lorc\hourglass.svg",
    "dragon": r"lorc\dragon-head.svg",
    "monster": r"lorc\monster-grasp.svg",
}

CREDITS = """# 素材来源与许可（assets/CREDITS.md）

## Sunny Land（环境/拾取物/特效帧/音效）
- 作者：Luis Zuno (@ansimuz)，来源：H:\\job_prep\\免费素材\\Sunny Land
- 许可：Public domain（署名非必需）

## Space Shooter Redux（激光/爆炸/UI/音效/字体）
- 作者：Kenney Vleugels (kenney.nl)，来源：H:\\job_prep\\免费素材\\Space Shooter Redux
- 许可：CC0

## Game Icons（道具/技能图标 SVG）
- 来源：https://game-icons.net（本地镜像 H:\\job_prep\\免费素材\\Game Icons）
- 许可：CC BY 3.0（需署名）
- 使用作者：Lorc、Delapouite 等，完整名单见 game-icons.net/credits

## 程序化精灵
- 玩家/敌人精灵由 tools/scripts/gen_sprites.py 程序化生成（原创，无版权问题）

## 字体
- kenvector_future.ttf：Kenney（CC0）
- NotoSansSC：Google（SIL OFL 1.1，免费商用）
"""


def main():
    copied = 0
    skipped = 0
    for src_rel, dst_rel in COPIES:
        src = os.path.join(SRC, src_rel)
        dst = os.path.join(DEST, dst_rel)
        if not os.path.exists(src):
            print(f"[missing] {src_rel}")
            skipped += 1
            continue
        if os.path.isdir(src):
            os.makedirs(dst, exist_ok=True)
            for fn in os.listdir(src):
                s = os.path.join(src, fn)
                d = os.path.join(dst, fn)
                if os.path.isfile(s) and not os.path.exists(d):
                    shutil.copy2(s, d)
                    copied += 1
        else:
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            if not os.path.exists(dst):
                shutil.copy2(src, dst)
                copied += 1
    for name, rel in ICONS.items():
        src = os.path.join(SRC, "Game Icons", rel.replace("\\", os.sep))
        dst = os.path.join(DEST, "icons", name + ".svg")
        if os.path.exists(src) and not os.path.exists(dst):
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy2(src, dst)
            copied += 1
        elif not os.path.exists(src):
            print(f"[icon missing] {rel}")
    with open(os.path.join(DEST, "CREDITS.md"), "w", encoding="utf-8") as f:
        f.write(CREDITS)
    print(f"copied={copied} skipped={skipped}")


if __name__ == "__main__":
    main()

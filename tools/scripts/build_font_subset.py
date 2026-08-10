"""重建中文字体子集：收集项目源码全部中文字符 → pyftsubset 重新子集化 → 验证覆盖。

用法（新增中文文案后运行，防字体缺字显示成码点如 "610F"）：
    python tools/scripts/build_font_subset.py
随后需要重新导入/导出：
    godot --headless --path . --import
    godot --headless --path . --export-release "Web" export/web/index.html

背景：子集字体缺失字形时 Godot 会显示 Unicode 码点十六进制（"意"→610F）。
"""

import io
import os
import subprocess
import sys

from fontTools.ttLib import TTFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FULL_FONT = os.path.join(ROOT, ".tools", "lxgw_wenkai.ttf")
OUT_FONT = os.path.join(ROOT, "assets", "fonts", "LXGWWenKai_subset.ttf")
CHARS_FILE = os.path.join(ROOT, ".tools", "chars_all.txt")

# HUD/战斗动态文案的额外常用字（不在源码但可能被运行时拼接）
EXTRA = (
    # ASCII ????????GB2312 ?????????????+50% ? +/% ??
    "".join(chr(i) for i in range(32, 127))
    + # ?????????
    "×÷·→←↑↓「」『』、。！？，；：—…‘’“”【】～◆★☆♪￥"

    "攻击防御速度暴击冷却范围吸血回复生命恢复金币经验等级波次精英首领关卡轮回暂停继续开始退出"
    "确认取消返回构筑法术召唤装备道具获得拾取掉落合成进化升级强化觉醒稀有传说史诗普通特殊元素"
    "火焰冰霜雷电毒素刀刃风暴腐蚀神圣诅咒传送治疗恢复体力护盾反弹荆棘反伤造成伤害最大当前每次"
    "每层叠加上限增加减少几率概率时间秒分钟小时天"
)


def gb2312_chars() -> set:
    """GB2312 全部 6763 个汉字：游戏文案几乎全部属于常用字，收录后基本杜绝缺字码点问题。"""
    chars = set()
    for hi in range(0xB0, 0xF8):
        for lo in range(0xA1, 0xFF):
            try:
                chars.add(bytes([hi, lo]).decode("gb2312"))
            except Exception:
                continue
    return chars


def collect_chars() -> set:
    chars = set()
    for dirpath, dirs, files in os.walk(ROOT):
        if any(x in dirpath for x in (".git", ".godot", ".tmp", "export", ".tools", "docs", ".agents")):
            continue
        for fn in files:
            if not fn.endswith((".gd", ".json", ".tscn", ".cfg", ".md")):
                continue
            try:
                s = io.open(os.path.join(dirpath, fn), encoding="utf-8").read()
            except Exception:
                continue
            for ch in s:
                if "\u4e00" <= ch <= "\u9fff" or ch in "，。！？：；、（）《》【】—…·×％＋－＝·":
                    chars.add(ch)
    chars |= set(EXTRA) | gb2312_chars()
    return chars


def main() -> int:
    if not os.path.exists(FULL_FONT):
        print(f"FULL font missing: {FULL_FONT}")
        return 1
    chars = collect_chars()
    with io.open(CHARS_FILE, "w", encoding="utf-8") as f:
        f.write("".join(sorted(chars)))
    print(f"chars: {len(chars)} -> {CHARS_FILE}")

    subprocess.check_call([
        sys.executable, "-m", "fontTools.subset", FULL_FONT,
        "--text-file=" + CHARS_FILE,
        "--output-file=" + OUT_FONT,
        "--notdef-glyph", "--notdef-outline", "--recommended-glyphs",
        "--layout-features=*",
    ])

    cmap = TTFont(OUT_FONT).getBestCmap()
    missing = [ch for ch in chars if ord(ch) not in cmap]
    if missing:
        print(f"FAIL: {len(missing)} chars missing: {''.join(missing)[:200]}")
        return 1
    size = os.path.getsize(OUT_FONT)
    print(f"OK: {len(cmap)} glyphs, {size} bytes -> {OUT_FONT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

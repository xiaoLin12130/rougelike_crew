#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
check_ui_fonts.py — 静态扫描 scripts/ui 下直接 new 的 Button/Label 控件。

背景：UiTheme.button()/label() 已统一设置中文字体 override；但部分控件直接
Button.new()/Label.new() 创建，显式默认字体下 ThemeDB.fallback_font 不生效，
设置了 text（含 text="" 但有 tooltip）而缺少字体 override 时中文会显示码点。
本脚本扫描并输出警告，退出码 0 = 干净，1 = 存在警告。

用法: python tools/scripts/check_ui_fonts.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2] / "scripts" / "ui"

# var slot := Button.new() | var slot: Button = Button.new() | var l: Label = Label.new()
VAR_NEW_RE = re.compile(
    r"^\s*var\s+([A-Za-z_]\w*)\s*(?::\s*(Button|Label))?\s*(?::=|=)\s*(Button|Label)\.new\(\)"
)
TEXT_SET_RE = r"^\s*{name}\.text\s*="
FONT_OK_RE = (
    r"^\s*{name}\.add_theme_font_override\(|"
    r"^\s*{name}\.add_theme_font_size_override\(|"
    r"^\s*UiTheme\.apply_font\(\s*{name}\s*,"
)


def indent_of(line: str) -> int:
    return len(line) - len(line.lstrip(" \t"))


def strip_strings(line: str) -> str:
    """去掉单行字符串字面量，避免括号计数被字符串内容干扰。"""
    out = []
    i = 0
    quote = None
    while i < len(line):
        ch = line[i]
        if quote is not None:
            if ch == "\\":
                i += 2
                continue
            if ch == quote:
                quote = None
        else:
            if ch in ('"', "'"):
                quote = ch
            else:
                out.append(ch)
        i += 1
    return "".join(out)


def bracket_depth(line: str, base: int = 0) -> int:
    s = strip_strings(line)
    depth = base
    for ch in s:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
    return max(depth, 0)


def is_blank_or_comment(line: str) -> bool:
    s = line.strip()
    return s == "" or s.startswith("#")


def scan_file(path: pathlib.Path, warnings: list) -> None:
    lines = path.read_text(encoding="utf-8").splitlines()
    n = len(lines)
    i = 0
    while i < n:
        m = VAR_NEW_RE.match(lines[i])
        if not m:
            i += 1
            continue
        name, ctrl_type = m.group(1), m.group(3)
        start_indent = indent_of(lines[i])
        # 收集同块作用域：直到缩进回退（且括号闭合）或文件结束
        j = i + 1
        depth = 0
        has_text = False
        has_font = False
        while j < n:
            line = lines[j]
            if not is_blank_or_comment(line):
                depth = bracket_depth(line, depth)
                if depth == 0 and indent_of(line) < start_indent:
                    break
                if re.search(TEXT_SET_RE.format(name=re.escape(name)), line):
                    has_text = True
                if re.search(FONT_OK_RE.format(name=re.escape(name)), line):
                    has_font = True
            j += 1
        if has_text and not has_font:
            rel = path.relative_to(pathlib.Path(__file__).resolve().parents[2]).as_posix()
            warnings.append(
                f"{rel}:{i + 1}: {name} ({ctrl_type}.new()) 设置了 text 但未 override 字体"
                f"（中文会显示码点，请调用 UiTheme.apply_font({name}, size)）"
            )
        i = j


def main() -> int:
    warnings: list = []
    for p in sorted(ROOT.rglob("*.gd")):
        scan_file(p, warnings)
    for w in warnings:
        print("WARN " + w)
    total = len(warnings)
    print(f"[check_ui_fonts] scanned {ROOT} -> {total} warning(s)")
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())

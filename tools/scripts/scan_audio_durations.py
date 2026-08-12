# -*- coding: utf-8 -*-
"""OGG Vorbis 时长扫描器（纯 stdlib，无第三方依赖）。

用途：音效素材选型评估——输出每个 .ogg 的时长/采样率/声道数，
供高频战斗命中音选型（>0.5s 算长音不适合高频命中；<0.05s 基本听不到）。

用法：
    python tools/scripts/scan_audio_durations.py [目录...]
    缺省扫描：assets/audio/ 与 .tmp/audio_scan/（kenney 包解压目录）
"""
import os
import struct
import sys
import io

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")


def ogg_info(path):
    """返回 (duration_s, sample_rate, channels) 或 None。"""
    try:
        with open(path, "rb") as f:
            data = f.read()
    except OSError:
        return None
    if data[:4] != b"OggS":
        return None
    pos = 0
    n = len(data)
    sample_rate = None
    channels = None
    max_granule = -1
    while pos + 27 <= n:
        if data[pos:pos + 4] != b"OggS":
            break
        granule = struct.unpack_from("<q", data, pos + 6)[0]
        seg_count = data[pos + 26]
        table_end = pos + 27 + seg_count
        if table_end > n:
            break
        segs = data[pos + 27:table_end]
        body_len = sum(segs)
        body_start = table_end
        if granule >= 0:
            max_granule = max(max_granule, granule)
        # 首包 = Vorbis 识别头：channels 在包内偏移 11，采样率在 12..15
        if sample_rate is None and body_start < n and data[body_start:body_start + 1] == b"\x01" \
                and data[body_start + 1:body_start + 7] == b"vorbis" and body_len >= 30:
            channels = data[body_start + 11]
            sample_rate = struct.unpack_from("<I", data, body_start + 12)[0]
        # 包完整时推进；不完整也尝试按表长推进
        pos = body_start + body_len
    if sample_rate is None or max_granule < 0:
        return None
    return (max_granule / float(sample_rate), sample_rate, channels)


def main():
    roots = sys.argv[1:] if len(sys.argv) > 1 else [
        r"H:\rougelike_crew\assets\audio",
        r"H:\rougelike_crew\.tmp\audio_scan",
    ]
    rows = []
    for root in roots:
        if not os.path.isdir(root):
            continue
        for dirpath, _dirs, files in os.walk(root):
            for fn in sorted(files):
                if not fn.lower().endswith(".ogg"):
                    continue
                p = os.path.join(dirpath, fn)
                info = ogg_info(p)
                if info is None:
                    rows.append((p, -1.0, 0, 0, "PARSE_FAIL"))
                    continue
                dur, sr, ch = info
                flag = ""
                if dur < 0.05:
                    flag = "TOO_SHORT"
                elif dur > 0.5:
                    flag = "LONG"
                rows.append((p, dur, sr, ch, flag))
    print("%-78s %9s %8s %5s %s" % ("FILE", "SEC", "RATE", "CH", "FLAG"))
    for p, dur, sr, ch, flag in sorted(rows, key=lambda r: (r[0].lower(), r[1])):
        print("%-78s %9.3f %8d %5d %s" % (p, dur, sr, ch, flag))


if __name__ == "__main__":
    main()

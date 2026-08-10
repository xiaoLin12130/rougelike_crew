# 交付报告：图标去重实施（icon_dedup_impl）

> 日期：2026-08-10 ｜ 依据：docs/design/图标去重分配方案.md（只读参考，未修改）
> 范围：data/items.json、data/spells.json、data/wands.json、data/summons.json 的 icon 字段（其他字段一律未动）

## 一、改动统计

| 文件 | 改图 | 保留 | 说明 |
|---|---|---|---|
| data/items.json | 212 | 54 | 266 条全覆盖；110 条 glow 占位全部消除 |
| data/spells.json | 5 | 20 | 核心 2：whirl_blade→willibab/SWORDS_141.png、poison_cloud→verarc/poisoned.png；外壳 3：homing→verarc/magic_amplification.png、pierce→willibab/SPEARS_20.png、orbit→willibab/STAFFS_3.png |
| data/wands.json | 0 | 55 | STAFFS_0..54 一一对应、无重复引用，按方案保留 |
| data/summons.json | 0 | 10 | 未覆盖清单第 6 类（16px 图标风格待统一），保持原 icon |
| 合计 | 217 | 139 | 映射表 217 条全部落地，无遗漏 |

## 二、跳过清单（保持原 icon 未改）

1. wands.json 55 把法杖：方案 5.3 节明确「一一对应、无重复引用，全部保留」。
2. summons.json 10 种召唤物：方案第八节「未覆盖清单」第 6 类（用角色贴图做 16px 图标，风格不统一，等待统一生成）。
3. 方案文档「未覆盖清单」7 类（毒云专属、齐射/弹射/追踪/环绕专属图标、willibab ALL_*）——均无更贴切素材，保持原 icon。
4. items.json 54 条「保留」项（现 icon 合规：≤3 次共用且语义正确）。

## 三、校验结果（全绿）

| 检查项 | 结果 |
|---|---|
| ① 四文件全部 icon 路径存在（文件系统：PNG + .import） | 356 处引用 / 274 个唯一素材，缺文件 0、缺 .import 0 |
| ①b ResourceLoader.exists() 双重核实（Godot headless） | RESOURCE LOADER ICON CHECK OK (icons=356) |
| ② glow.png 引用数 | 0（目标 0） |
| ③ 任一素材被引用 ≤3 | 超限素材 0 个 |
| ④ 与方案文档映射表抽查 20 条 | 全部一致 |
| 冒烟测试 | Godot_v4.7.1-stable_win64_console.exe --headless --path . -s res://scripts/tests/smoke_test.gd → SMOKE OK |
| hud 回归（升级三选一/构筑面板） | hud_layout_test.gd 图标相关 0 报错；1 项「资源条高度」断言失败为既有问题（用备份原始数据对照结果相同，与图标无关）；panel_diag_test.gd → DIAG DONE 无图标报错 |

## 四、素材解析说明

- willibab 路径：res://assets/icons/willibab/<短名>.png（SWORDS_/STAFFS_/AXES_/MACES_/DAGGERS_/SPEARS_ 前缀）。
- verarc 路径：res://assets/icons/verarc/<短名>.png。
- shikashi 路径：中文名按包内官方图例（Shikashi's Fantasy Icons Pack.txt）逐段映射到 shikashi_rX_cY.png，两个锚点与方案文档一致：r0_c5=眩晕(dizzy)、r12_c10=金币堆(gold_coin_stack)。

## 五、备份与可回滚

- 原始文件备份：.tmp/backup_icon_dedup/{items,spells,wands,summons}.json.bak（改动前完整副本）。
- 校验脚本：tools/tests/icon_check.py（文件系统 + 文档抽查）、tools/tests/icon_check.gd（ResourceLoader）。
- 解析中间产物：.tmp/icon_mapping_raw.json、.tmp/icon_path_map.json、.tmp/apply_report.json。

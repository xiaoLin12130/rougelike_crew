# 交付报告：图鉴面板手机端适配（collection_mobile）

日期：2026-08-10 · 状态：done

## 改动文件

| 文件 | 改动 |
| --- | --- |
| scripts/ui/game/collection_panel.gd | is_mobile() 分支（同 wand_shop 风格）：tab 两行缩略、网格 3 列 72x72、字号略小；详情弹窗 autowrap min-size 修复 |
| scripts/tests/test_collection.gd | 新增手机端 5 项断言 + PC 列数断言 + 主菜单手机复核；headless 平台判定显式固定 |
| work/status.json | 新增 collection_mobile: done，updated 更新 |

## 手机端适配内容（PC 保持 4 列 64x64 不变）

1. **tab 按钮**：两行缩略文案（短名 + 进度），短名表：法杖/法术/外壳/装备/召唤；
   字号 9（PC 13），按钮 60x44 触控目标不变；总宽 = 5x60 + 4x4 间距 = 316 ≤ 340 ✓
   （长名"装备饰品 274/276"在手机端不再溢出）。
2. **条目网格**：3 列（GRID_COLUMNS_MOBILE=3），格 72x72（CELL_SIZE_MOBILE），
   图标 56x56（ICON_SIZE_MOBILE），名称字号 9（PC 10）；refresh() 重设 columns 保持平台列数。
3. **详情弹窗**：宽 320 ≤ 320 且在屏内（修复前 min-size 计算时 autowrap Label 按窄宽换行，
   弹窗高达 692px 越屏——body/title min 宽 0 → 260，同 wand_shop 卡片描述坑）。
4. **主菜单图鉴按钮**：200x44（代码建锚点），手机端同样 ≥44px，复核通过（无需改动 main_menu.gd）。

## 验收结果（Godot 4.7.1 console + --headless，TEMP/APPDATA 重定向项目 .tmp）

- `test_collection.gd` → **ALL PASS**（真实退出码 0）：
  - 手机端：tab 总宽 ≤340 ✓ / 网格 3 列（含切 tab 后）✓ / 格 ≥64px（72x72）✓ /
    详情弹窗 ≤320 且在屏内 ✓ / 主菜单按钮 ≥44 ✓
  - PC 断言不破坏：4 列 ✓ / 55/15/10/274+/10 条目 ✓ / 收集/持久化/主菜单全绿 ✓
- `smoke_test.gd` → **SMOKE OK**（真实退出码 0）
- 无 Godot 残留进程；仅 smoke 扫描到 `_probe_engine.gd`（79a5f15 已提交的遗留探测脚本，
  使用 Godot 4.7 不存在的 Engine.get_error_messages）报解析错误——属既有噪音，不在本次可写范围。

## 备注

- 未触碰 data/*.json、wand_shop.gd、hud.gd、build_panel.gd、main_menu.gd、scenes/。
- 无端口分配；无 GUI Godot 运行。

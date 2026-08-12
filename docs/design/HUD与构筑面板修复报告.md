# HUD 与构筑面板修复报告（2026-08-12）

## 一、三项修复说明

### 1. HUD 底部武器/法术栏整体移除（scripts/ui/game/hud.gd）

用户反馈不需要底部格子，按要求整体移除：

- 删除创建与刷新链路：`_build_weapon_bar`（_ready 调用点）、`_refresh_weapon_bar`、`_refresh_weapon_bar_if_changed`、`_grid_signature`、`_make_weapon_slot`、`_pulse_weapon_slot`，以及仅被它们使用的 `_find_core` / `_find_shell`。
- 删除状态：`_weapon_bar`、`_weapon_slots`、`_grid_sig` 变量与 `WEAPON_BAND_LEFT/RIGHT`、`WEAPON_BOTTOM_GAP` 常量。
- 删除调用点：`_refresh()` 中的 `_refresh_weapon_bar_if_changed()`；`_on_item_picked` 中 spell_part 脉冲分支；`_dump_layout`（F8 自检）的 WEAPON 条目。
- 依赖检查：全局搜索确认除已删代码与测试外，无任何地方依赖 `_weapon_bar`。武器栏原本是构筑面板入口之一（点格开面板），移除后入口仅剩左下"构筑"按钮与 TAB 键，`_toggle_build` / `focus_grid` 链路不变。
- 测试同步：hud_layout_test.gd 删除 `_assert_weapon_bar` 及 expand 阶段武器栏断言；test_brotato_hud.gd 删除 PC 武器栏断言与整个移动端 3+2 两行 HUD 阶段（该阶段只测武器栏）。

### 2. 构筑面板错位：装备盖住法术序列（scripts/ui/game/build_panel.gd）

根因：`_grid_section` 是一层裸 `Control`（`custom_minimum_size = Vector2(0, 0)`）。Godot 中普通 Control 不会自动把尺寸包住子节点，`_grid_box`（GridContainer，54px 高）从零尺寸容器原点向下溢出，直接压进紧随其后的"装备"分区；装备区后绘制，视觉上盖住法术序列。

修复：

- 删除 `_grid_section` 包装层，`_grid_box` 直接挂入 `main` VBoxContainer（保持 5 列单行、`SIZE_SHRINK_CENTER` 水平居中），VBox 正确计算法术区高度，装备/饰品区自然下移。
- `focus_grid()` 滚动定位改用 `_grid_box`（原指向已删除的 `_grid_section`）。
- 修复法术网格定义行右侧的历史乱码注释（GBK 丢失写入留下的 "?" 字节），改写为准确中文注释。

修复后实测区域 rect：法术区 y162..216 → 装备区 y246..300 → 饰品区 y330..384，自上而下顺序正确、边界不相交（360x640 视口）。

### 3. 法术序列格右侧 "???" 码点（scripts/ui/ui_theme.gd + build_panel.gd）

排查结论：build_panel.gd / hud.gd 中所有 Label 均已走 `UiTheme.label()`，无裸 `Label.new()`。码点有两个来源：

- 运行时：`UiTheme.badge()` 强制 `num=true`（kenvector 像素数字字体，仅覆盖 ASCII），而法术格角标文本含 "×" 与外壳名中文首字（如"迅"）。headless 字体探测确认：kenvector 对全部测试 CJK 字符 `has_char=false`，LXGWWenKai 子集均为 true → 中文首字角标渲染成 "?"。
  - 修复：`badge()` 按文本内容选字体——含非 ASCII 字符自动改用中文字体（`font_cn`），纯数字仍保留像素数字字体风格。
- 源码：build_panel.gd 法术网格定义行右侧注释为历史损坏字节（"2026-08-10?PC/?????..."），已重写。

## 二、改动文件

| 文件 | 改动 |
| --- | --- |
| scripts/ui/game/hud.gd | 移除底部武器栏全部代码（约 170 行）及调用点/变量/常量 |
| scripts/ui/game/build_panel.gd | 修复法术网格溢出重叠、重写损坏注释、focus_grid 适配 |
| scripts/ui/ui_theme.gd | badge 按内容选择字体（非 ASCII → 中文字体） |
| scripts/tests/hud_layout_test.gd | 删除 WEAPON 底部栏断言（含 expand 阶段） |
| scripts/tests/test_brotato_hud.gd | 删除武器栏断言与移动端 HUD 阶段 |
| scripts/tests/test_build_panel_layout.gd | 新增布局回归测试（区域无重叠 / 5 格完整 / 无码点 / badge 字体） |

未触碰：scripts/ui/game/wand_shop.gd、scripts/enemies/、scripts/fx/、scripts/combat/、scripts/core/；未动 .git、未提交。

## 三、测试结果（headless，360x640 逻辑视口）

| 测试 | 结果 |
| --- | --- |
| smoke_test.gd | SMOKE OK |
| hud_layout_test.gd | PORTRAIT UI OK / EXPAND UI OK |
| test_brotato_hud.gd | BROTATO HUD ALL PASS |
| test_build_panel_layout.gd（新增） | BUILD PANEL LAYOUT OK |

全部按铁律以 `Godot_v4.7.1-stable_win64_console.exe --headless` 运行，并设置 TEMP/APPDATA 至 .tmp。

## 四、发现的其他问题（超出本次文件边界，未修改，建议另行处理）

1. data/items.json：`wand_expander` 的 name/description 为损坏字符（"??????"），构筑面板/商店会显示乱码。
2. data/enemies.json：37 处 Boss 技能名损坏（`bosses[i].skills[j].name` 为 "?" 串）。
3. docs/design/土豆兄弟UI适配方案.md 等部分文档整体为损坏字符（历史写入编码丢失）。

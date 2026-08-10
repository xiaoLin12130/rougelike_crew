# 图鉴系统交付报告（P3）

> 日期：2026-08-10 · 阶段：demo-polish · 验收：test_collection.gd ALL PASS + smoke SMOKE OK + hud_layout PORTRAIT/EXPAND OK

## 一、交付内容

| 文件 | 类型 | 说明 |
|---|---|---|
| scripts/ui/game/collection_panel.gd | 新增 | 图鉴面板：五分类 tab + 网格条目 + 详情弹窗 |
| scripts/ui/collection_panel.tscn | 新增 | 图鉴面板场景（CanvasLayer，process_mode=3） |
| scripts/tests/test_collection.gd | 新增 | 图鉴系统测试（①收集记录 ②面板渲染 ③持久化 ④主菜单按钮） |
| scripts/ui/main_menu.gd | 修改 | 新增图鉴按钮（代码建节点）+ 打开面板 |
| scripts/core/game_state.gd | 只增 | collection 字段 + mark_collected/collection_of/is_collected/load_collection + 六处触发点 |
| scripts/core/save_store.gd | 只增 | save_collection/load_collection/clear_collection（user://collection.json） |
| work/status.json | 修改 | collection_system: done |

只读契约遵守：data/*.json、scenes/game/*、scripts/combat/*、scripts/synergies/*、tools/ 均未改动；scenes/main_menu.tscn 未改动（按钮在脚本中构建）。

## 二、功能实现

1. **主菜单图鉴按钮**：位于"继续"下方（锚点 0.675，200x44，与开始/继续/退出同风格），按下打开全屏图鉴面板，Esc 或"返回主菜单"按钮关闭回主菜单。
2. **五分类浏览**：法杖 55 / 法术核心 15 / 法术外壳 10 / 装备饰品 274+ / 召唤物 10，tab 文案带收集进度（如"法杖 3/55"），顶部进度行显示当前分类已收集数；网格 4 列（格 64x64 = 图标 48 + 名称 12px），ScrollContainer 兜底。
3. **已收集条目**：原色图标 + 真实名称 + 稀有度描边（common/rare/legendary），点击弹详情弹窗（名称/稀有度/完整描述）。
4. **未收集条目**：图标 modulate 压黑 Color(0,0,0,0.6) 黑色剪影 + 名称"？？？" + 不显示描述，点击无详情；图标缺失时用纯色占位保持剪影语义。
5. **跨局持久化**：user://collection.json（{version, categories:{items,wands,cores,shells,summons}}），mark_collected 去重并即时落盘；GameState._ready 启动时加载；new_run 不重置收集（图鉴进度与局内存档分离）；Web 端由 Godot user://（IndexedDB）自动处理。
6. **收集触发点**（GameState 内只增）：add_item / add_trinket（装备饰品）、add_wand / replace_wand（法杖）、add_spell_part / replace_spell（法术核心×外壳，召唤核心联动记录召唤物）。

## 三、验收结果

```
test_collection.gd  → ALL PASS（EXIT=0）
smoke_test.gd       → SMOKE OK（EXIT=0）
hud_layout_test.gd  → PORTRAIT UI OK / EXPAND UI OK（EXIT=0）
```

test_collection.gd 覆盖：
- ① mark_collected 后 collection_of/is_collected 生效；重复标记去重；非法分类/空 id 不写入；六处触发点联动（含召唤核心→召唤物 bat）；
- ② 面板渲染：已收集条目名称+稀有度描边+点击详情含描述；未收集"？？？"+压黑图标+无描述+点击无详情；五分类网格数量与数据表一致（55/15/10/274+/10）；tab 进度文案；
- ③ 持久化：落盘→清内存→load_collection 恢复完整；SaveStore 直接 round-trip（version/categories 结构）；new_run 不重置；二次重载仍完整；
- ④ 主菜单：图鉴按钮存在、文字"图鉴"、触控区>=44、与其余三按钮不重叠、按下打开面板。

## 四、注意点

- 图鉴条目数据只读 data/*.json（GameState.tables），未复制数据；cores/shells/summons 无 rarity 字段，用分类兜底（法术中档 rare / 召唤 common）。
- main_menu.gd 的图鉴按钮为代码构建（不动 tscn），hud_layout 对 Start/Continue/Quit 三按钮的既有断言不受影响。
- 测试运行命令（强制规则）：$env:TEMP/TMP→项目 .tmp，$env:APPDATA→.tmp\appdata；.tools\godot\Godot_v4.7.1-stable_win64_console.exe --headless --path . -s ...

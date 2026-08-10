# 交付报告：商店改造 1/2（先选强化或购买 + 手机端适配）

日期：2026-08-10 · 分支：当前工作树（未提交）· 修改文件：2 个 + 新增测试 1 个

## 一、改动内容

### 1. 入口选择页（新）
- Boss 战后 `show_shop()` 默认展示选择页：两个大按钮「强化法杖 / 购买法杖」（220x64，手机 260x64）+「恢复药水」「刷新」「离开」（44 高）。
- 点击进入对应子页，两页均有「← 返回选择页」按钮（返回时取消替换模式残留）。

### 2. 强化页 / 购买页
- 强化页：已持有法杖强化卡（名称 + 售出 50% 返还按钮 + 强化按钮），强化 +8%/级、250 起每级 +100（对齐当前平衡表），每次进店限 1 次。
- 购买页：3 把随机法杖（稀有度加权 + lucky 联动，`_roll_offers` 内部逻辑零改动），图标 + 名称 + 描述 + 价格按钮内联，tooltip 悬浮详情保留；满 3 把购买进入替换模式（选槽替换后扣款关店）。

### 3. 手机端适配（`UiLayout.is_mobile()` 分支）
- 商品卡 296→280 宽、图标 56→44、字号 12/9→11/8；强化槽改为 2 列 GridContainer（135 宽，按钮字号 12 保证文案不溢出）。
- 全部按钮触控区 ≥44px；PC 布局保持原样。

### 4. autoplay_handle 兼容
- 新决策顺序：优先强化最便宜可负担的 → 否则购买（最贵可负担，满 3 把进替换）→ 替换模式选槽 0 → 否则离开。与 auto_play.gd 调用契约兼容。

## 二、关键实现说明（布局坑）
- Godot 4.7 中隐藏容器**不会**对其子节点执行排序（子节点停留在 (0,0) 且不参与父容器 min-size 计算）。若用 visible 切换子页，hud_layout_test 在 show_shop 后一帧断言卡片时会拿到未排序 rect。方案：选择/强化/购买三区块**常驻同一滚动区**（始终可见、始终排序），页面切换 = `scroll_vertical` 滚动定位；选择页按钮改为 EXPAND_FILL（原 320 定宽会撑出 8px 滚动条宽度使面板 348>340）。
- autowrap Label 的 min-size 按 1px 宽计算换行高度（描述最长可达 582px，卡片被撑到 500+px）；修复：描述 `custom_minimum_size = Vector2(180, 26)` 约束最小宽度。
- 顺手修复既有 bug：`up_lv>0` 分支「强化 Lv.%d（%d金）」双占位符配单参数会在强化过 1 级的法杖上运行时崩溃（原代码用三元表达式，测试从未覆盖该分支）。

## 三、测试结果（均 headless，环境变量 TEMP/TMP/APPDATA 已重定向至 .tmp）

| 测试 | 结果 |
| --- | --- |
| test_wand_shop_flow.gd（新增，PC+手机+autoplay） | WAND SHOP FLOW ALL PASS |
| test_wand_shop.gd（旧加权抽取断言，未改动） | WAND SHOP TEST OK |
| hud_layout_test.gd（商店面板 ≤340 / 卡片断言，只读未改） | PORTRAIT UI OK / EXPAND UI OK |
| smoke_test.gd | SMOKE OK |

test_wand_shop_flow.gd 覆盖：① 默认选择页（三按钮存在且在可视区）；② 点购买→3 把+返回按钮（卡片不重叠不超屏）；③ 点强化→3 张强化卡+返回；④ force_mobile(true) 全按钮 ≥44px、激活页卡片不超屏；另含 autoplay 断言（300 金优先强化 basic_wand→替换模式→替换扣款关店）。

## 四、说明与遗留
- `fullscreen_mobile_test.gd` 的 zoom/BackdropLayer 失败为基线既有问题：将 wand_shop.gd 还原为 git HEAD 版本复跑结果一致（与本次改动无关）。
- 未触碰 data/*.json、scripts/combat/*、scenes/、hud.gd、build_panel.gd（其他代理在用）。
- 测试后已确认无 Godot 进程残留。

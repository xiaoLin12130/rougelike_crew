# 土豆兄弟 UI 素材清单（现有盘点 + 缺口 + 免费来源）

> 产出：2026-08-11 ｜ 类型：只读盘点 + 缺口清单（未下载任何素材、未改任何文件）
> 配套文档：docs/design/土豆兄弟UI适配方案.md（逐界面适配细节）
> 盘点方式：Python 遍历 assets/ 与 .tools/user_assets/，PIL 实测图标尺寸/调色板，rg 核实素材引用情况。

## 1. 现有素材盘点（2026-08-11 实测）

### 1.1 图标（可支撑 Brotato 风格"重描边像素图标"）

| 素材包 | 数量 | 尺寸 | 内容 | 状态 |
|---|---|---|---|---|
| assets/icons/shikashi | 245 | 约 30-35px | 奇幻图标（武器/药水/资源/状态/杂物），官方图例可查 | 已导入，项目中大量引用 |
| assets/icons/willibab | 1223 | 约 28-38px | 武器图标（SWORDS 144/AXES 44/MACES 36/SPEARS 21/DAGGERS 13/STAFFS 58/ALL 261 + 646 变体） | 已导入，图标分配方案引用 |
| assets/icons/verarc | 48 | 16x16 | 技能/增益/减益（文件名即语义） | 已导入 |
| 合计 | 1516 | — | — | — |

> 风格比对：Brotato 属性图标实测为 96px 导出（原生约 32px）、单图标 7-27 色、重暗色描边、两段明暗。本项目 shikashi/willibab（约 32px、暗描边、有限调色板）风格同源，**图标本体无缺口**。

### 1.2 UI 纹理（assets/ui/）

| 文件 | 尺寸 | 用途 | 引用状态 |
|---|---|---|---|
| hpbar_blue.png | 49x6 | 玩家血条 fill（hud.gd） | 已用 |
| hpbar_yellow.png | 32x4 | 经验条 fill（hud.gd） | 已用 |
| hpbar_red.png | 56x54 | Boss 条 fill（hud.gd） | 已用 |
| hpbar_frame.png | 116x64 | 血条外框 | **未引用（rg 核实）** |
| theme.tres | — | Tooltip 主题 | 已用 |
| icon.svg | — | 应用图标 | 已用 |

### 1.3 Kenney shooter UI 包（assets/ui/shooter/，未引用）

| 文件 | 内容 | 可复用场景 |
|---|---|---|
| buttonBlue/Green/Red/Yellow.png | 像素按钮 | 商店"开始下一波"大按钮、主菜单按钮底纹 |
| numeral0-9 + X.png | 像素数字贴图 | 计时/计数（当前用 kenvector 字体，贴图可选） |
| playerLife1/2/3 ×4 色.png | 生命图标 | HP 图标装饰 |
| cursor.png | 光标 | 桌面端光标 |

> **全部 28 个文件已导入但零引用**——Brotato 化按钮/装饰可零成本启用。

### 1.4 字体

| 字体 | 用途 | 状态 |
|---|---|---|
| assets/fonts/LXGWWenKai_subset.ttf（3.3MB） | 中文正文 | 已用（霞鹜文楷，可读性优先，**建议保留不换**） |
| assets/fonts/kenvector_future.ttf | 数字/计时 | 已用，与 Brotato 像素数字同类型 |

### 1.5 其他（已导入）

- fx/（damage 9、enemy_death 6、item_feedback 4、kenney 80、meteors 20、shooter 27）
- pickups/（cherry 7、gem 5、powerups 32）、projectiles/lasers 48
- env/kenney_tiles 37、sprites/（gen 51、kenney 3、retro 33、summons 17）

### 1.6 .tools/user_assets/ 未导入包（可作后备资源）

Shikashi v2、[VerArc Stash] Basic_Skills_and_Buffs、Pixel Crawler、sunny-land、Legacy Fantasy x2、GandalfHardcore x3（含 Hp bar）、Retro-Lines-16x16、Mana Seed 角色 Demo。其中 **Shikashi v2 与 Retro-Lines-16x16 对 UI 装饰有潜在价值**，其余为角色/地图素材，与本任务无关。

---

## 2. 素材缺口清单

> 结论先行：**必需下载 = 0 项**。全部缺口均可程序化（StyleBoxFlat/代码绘制）或由现有素材零成本启用；仅 2 项"质感增强"可选下载。

| # | 缺口 | 用途（对应方案章节） | 可否程序化 | 免费来源 | 是否需用户下载 |
|---|---|---|---|---|---|
| 1 | 面板九宫格纹理（深色底+浅灰蓝边框） | 商店/构筑/图鉴面板（5.3/5.5/5.6） | ✅ StyleBoxFlat 圆角+描边已满足；纹理质感仅锦上添花 | Kenney UI Pack（CC0，含面板/按钮/滑块九宫格）；OpenGameArt 搜 "dark panel 9-slice" | 否（可选增强才下） |
| 2 | 槽位底板 / 图标框（slot frame） | 武器栏/法术格/构筑格（5.2.4/5.5） | ✅ StyleBoxFlat panel_slot #171c28 + 1px 边框 + 圆角 3 | 同上；或 Kenney "UI Pack: space/kenney" | 否 |
| 3 | 锁图标（商店锁定钮） | 商店商品卡右上角（5.3） | ✅ 代码绘制 16x16（3-4 色像素锁，约 20 行 GDScript） | Kenney Game Icons 2（CC0，含 lock）；OpenGameArt "padlock icon 16x16" | **可选：是**（要精致质感时，Kenney 包约 1-2MB） |
| 4 | 材料/金币图标 | HUD 材料计数、商店价格（5.2.2-2/5.3） | ✅ 已有 shikashi_r12_c10 金币堆（图例"gold_coin_stack"，需目检确认）；无则程序化 16px | 现有素材内解决 | 否 |
| 5 | 波次计时图标（沙漏/钟） | 波次横幅（5.2.3） | ✅ 已有 shikashi 沙漏（图例有 hourglass） | 现有素材内解决 | 否 |
| 6 | 属性统计图标（16 项） | 统计面板/构筑属性区（5.2.6/5.5） | ⚠️ 部分 | verarc 48 个 16x16（语义命名）覆盖生命/攻速/暴击等；缺口（Engineering/Harvesting 等）程序化 16px 占位 | 否 |
| 7 | 稀有度边框贴图 | 卡片/格子五档稀有度（4.1） | ✅ StyleBoxFlat 按 RARITY 色 2-3px | 程序化 | 否 |
| 8 | Boss 血条外框 | Boss 条样式（5.2.5） | ✅ **已有 hpbar_frame.png 未启用** | 现有素材内解决 | 否 |
| 9 | 按钮纹理 | 主菜单/商店大按钮（5.1/5.3） | ✅ **已有 ui/shooter buttonBlue/Green/Red/Yellow 未启用** | 现有素材内解决 | 否 |
| 10 | 像素数字 | 计时/价格/堆叠数 | ✅ kenvector_future 已有 | 现有素材内解决 | 否 |
| 11 | 木牌/横幅/分隔装饰 | 波次横幅、主菜单分隔线（P2 装饰） | ✅ 程序化（半透明底+边框，现状风格） | 可选：Kenney "Board Game Icons" 或 itch.io "pixel banner" | 否 |
| 12 | "开始下一波"大按钮 | 商店底部（5.3） | ✅ 程序化按钮（gold 底+深棕字） | 程序化 | 否 |

### 2.1 可选增强包（仅当追求 Brotato 质感边框/图标时）

| 包 | 内容 | 许可 | 下载方式 | 大小 |
|---|---|---|---|---|
| Kenney UI Pack（kenney.nl/assets/ui-pack） | 面板/按钮/滑块/输入框九宫格 + 图标 | CC0 | 官网直接下载 zip，无需登录 | 约 2-4MB |
| Kenney Game Icons 2（kenney.nl/assets/game-icons-2） | 100+ 通用图标（锁/金币/箭头/计时等） | CC0 | 官网直接下载 zip | 约 1-2MB |

**下载流程**（沿用 docs/design/素材下载指南.md）：用户打开 kenney.nl 对应页面 → Download → 把 zip 放进 `H:\rougelike_crew\.tools\user_assets\` → 告知文件名，由实施代理解压/盘点/导入。Kenney 无需登录、无 CSRF 限制，也可尝试由 AI 提权 curl 直下（网络环境允许时）。

---

## 3. 许可铁律（沿用项目既有规定）

1. 只收 CC0 / CC-BY（记录署名）/ 公有领域 / 明确免费商用。
2. 每包来源与许可登记到 assets/CREDITS.md。
3. CC-BY-SA 包默认不收（传染性许可）。
4. 来源不明/许可不明的包商用前必须向作者确认。

---

## 4. 结论

- **必需用户下载：0 个**。Brotato 化所需的"面板/按钮/槽位/稀有度边框/材料图标/血条框"全部可程序化或由现有未启用素材（hpbar_frame、ui/shooter 28 个文件）零成本解决。
- **可选下载：2 个**（Kenney UI Pack、Kenney Game Icons 2），仅在需要"九宫格贴图质感 + 精致锁图标"时让用户手动下载。
- 实施顺序建议：先启用现有未用素材（0 成本）→ 程序化补齐缺口 → 最后按需引入 Kenney 包。

# 用户场景素材包分析报告（itch.io 下载包）

> 对象：`H:\rougelike_crew\.tools\user_assets\` 下 5 个已解压素材包（另含 FREE Mana Seed / Retro-Lines 两个包，不在本次范围）
> 目标游戏：Godot 4.7 像素俯视角肉鸽，视口/地图 1280x720，16px 瓦片基准，玩家/敌人 32x32
> 分析方法：Python 3 + Pillow 12.3 + numpy 2.5 逐张读取（尺寸/模式/alpha 覆盖/包围盒/平均色/透明间隙网格检测/边缘无缝检测/瓦片去重统计），全程本地离线
> 分析日期：2026-08-09；未修改任何项目文件（预览图仅生成于 Codex 可视化临时目录）

## 0. 结论速览

- **背景可换**：Legacy High Forest 的 `Trees\Green-Tree.png`（1344x1200）是左右无缝的俯视树冠平铺纹理，1344 宽原生覆盖 1280 视口，是当前 `back_forest.png`（384x240，被非等比拉伸且溢出）的直接替代品；同包 `Background\Background.png`（480x272 天空渐变，左右无缝）可作其下层天空。
- **HUD 可换**：Gandalf Hp bar 的 4 张素材可直接替换 `hud.gd` 的 StyleBoxFlat 血条——填充条（49x6 / 32x4 纯色、56x54 带框红条）拉伸无变形，槽（116x64）适合做 Boss 条九宫格；改造量约 15~40 行。
- **Pixel Crawler 的 384x64 / 512x64 是角色/怪物动画表**（64px 帧，帧边界 alpha=0 完全干净），不是瓦片；瓦片在 `Environment\Tilesets\*.png`（16px 网格）。同包 `Props\Static\Vegetation.png`、`Rocks.png`、`Trees\Model_02` 系列是现成的俯视装饰素材，可补 `prop_*`（目前 prop_* 无任何代码引用，只有导入记录）。
- **GandalfHardcore Platformer 包整体是横版侧视素材**：瓦片表、树、背景层均为侧视视角，不适合俯视地面，仅个别装饰可借用。

---

## 1. 各包内容结构（PIL 实测）

### 1.1 GandalfHardcore FREE Platformer Assets（72 PNG）

| 类别 | 文件（尺寸） | 判定 |
|---|---|---|
| 背景层 | `Background layers\{Autumn,Normal,Winter}\` 各 6 张（layer 1~5 + 合成图），1024x346 RGBA | 平台横版远景（含城堡），5 层由远及近，layer5 为天空 |
| 大树 | Tree1~4 256x208、Birch1~3 80x112、Weeping Willow1~3 224x192、Flowering Tree 96x112、Large Pine Tree 128x176、Pine forest sheet 320x208、Pine Trees 672x192 | 侧视树冠+树干，单帧无动画 |
| 瓦片表 | Floor Tiles1/2 288x576、Other Tiles1/2 288x224、House Tiles 448x224、BG Dirt1/2 192x128 | 32px 块平台砖（Floor Tiles1 实测 9x18=162 格仅 83 唯一），侧视视角 |
| 装饰 | Alchemy Decor 160x64、Angel Statue 64x64、Boat 800x32、Cooking area 768x64、Decor 416x544、Garden Decorations 224x128、Ores 128x128、Furnace and Sawmill 384x128、Pixel Art Wheat 256x32、Tall Grass 96x32、Torch 192x128、大小帐篷、Bonsai、Christmas tree 32x64 | 平台场景道具，俯视角下大多违和（侧视透视） |
| 动画 | Campfire sheet 160x256、Campfire with food 160x256、Portal 640x64、Water Tiles 160x192（P 模式无 alpha）、Animated Water 640x352 | 横版动画帧；Animated Water 640x352=4 帧 x 160x352，16px 网格，若做水面主题可借用 |
| 天气/天空 | cloud1~6（25x10~165x101）、sun 32x32、birds1~4（7x7~20x20）、hot air balloon 20x35、Snow blizzard 2420x1644（5x6 帧，484x274） | 横版装饰粒子，不适用 |

**许可**：README 允许商用/非商用游戏使用与修改；禁止再分发/转售、AI 训练、NFT、游戏工具、印刷材料。无署名要求。

### 1.2 GandalfHardcore Hp bar（5 PNG）

| 文件 | 尺寸 | PIL 实测 | 判定 |
|---|---|---|---|
| Hp bar.png | 116x64 | RGBA，透明 70%；内部（10..54, 8..108）仅 27% 不透明、17 色，最亮横带在 y=45..52 | **槽/边框**：深色装饰框 + 内部空腔 |
| red bar.png | 56x54 | 边缘暗红 (42~56,13,13)，中心亮红 (127~157,1,9) | **红色填充段**（带框） |
| Blue bar.png | 49x6 | 全不透明，纯蓝 (37,121,210) | **蓝色填充条**（纯色，拉伸/平铺无变形） |
| yellow bar.png | 32x4 | 全不透明，(209,160,72) | **黄色填充条** |
| HP bar preview.png | 696x384 | RGBA 透明 41% | 展示图（含完整条的拼装用法） |

**许可**：与 1.1 相同（GandalfHardcore 系列）。

### 1.3 Legacy Fantasy - Debug Map（4 PNG）

| 文件 | 尺寸 | PIL 实测 | 判定 |
|---|---|---|---|
| MockUp\Cover.png | 1920x1088 | RGB 无 alpha，平均色 (98,124,98) 绿 | **完整森林地图画面**，宽高比 1.765≈16:9（1920/1088），与 1280x720 几乎同比例 |
| MockUp\MockUp_01.png | 672x384 | RGB 无 alpha，(123,167,169) | 小场景拼图 |
| MockUp\Tiles.png | 1664x1856 | RGBA 透明 68%，半透明像素 37887 | 瓦片拼装调试图 |
| Assets\Tiles.png | 416x464 | RGBA 透明 63%；16px 网格 26x29 格，325 非空块/421 占用，35 块重复 | **正式瓦片库**（俯视） |

**许可**：Anokolisa 标准许可——商用/非商用可用，可任意修改，免署名（署名可选），禁止将素材本身作为商品转售。

### 1.4 Legacy-Fantasy - High Forest 2.3（40 PNG）

| 类别 | 文件（尺寸） | PIL 实测 | 判定 |
|---|---|---|---|
| 背景 | Background\Background.png 480x272 | **无 alpha**；上→下天空渐变 (221,246,247)→(147,227,228)；左右边缘差 0.4（几乎无缝）、上下 31.0 | **可平铺天空层**（含云色渐变） |
| 树冠 | Trees\Green/Dark/Golden/Red/Yellow-Tree.png 各 1344x1200 | RGBA 透明 77%；左右边缘差 0.4、上下 17.4；非 16/32px 网格对齐；行自相关无短周期 | **无缝平铺树冠纹理**，5 色 = 5 种关卡主题 |
| 树带 | Trees\Background.png 896x256 | 透明 32%，边缘差 114 | 单幅树冠带（装饰） |
| HUD | HUD\Base-01.png 432x304 | 透明 75% | HUD 底框（面板/背景） |
| 角色 | Character\ 8 张动画表（Idle 256x80、Run 640x80、Jump 系 192~960x64 等） | 64px 帧；Run 表 64px 边界偶有出血（alpha 3~41） | 横版动作集（Jump/Dead 等），与俯视移动不匹配 |
| 怪物 | Mob\Boar（192x32/288x32，32px 帧）、Bee（256x64）、Snail（384x32 与 all.png 384x160） | 帧边界基本干净 | 侧视怪物动画 |
| 瓦片/物件 | Assets\Tiles.png 400x400（16px 网格 24x25，231 非空）、Tree-Assets 336x400、Buildings 400x400、Hive 400x400、Interior-01 400x400、Props-Rocks 288x336 | 16px 基准、俯视 | 瓦片与装饰表 |

**许可**：Anokolisa 标准许可（同 1.3）。

### 1.5 Pixel Crawler - Free Pack 2.11（181 PNG）

| 类别 | 文件（尺寸） | PIL 实测 | 判定 |
|---|---|---|---|
| 角色 | Entities\Characters\Body_A\Animations\：36 张表（12 动作 x Down/Side/Up），256x64=4 帧、384x64=6 帧、512x64=8 帧 | **帧宽 64px，帧边界 alpha=0（完全干净）**；角色实体约 30px 高（bbox y 16..47） | **四方向俯视角色动画表** |
| 怪物 | Entities\Mobs\Orc Crew / Skeleton Crew 各 4 变体；Idle 128x32（4 帧 x 32px）、Run 384x64（6 帧 x 64px）、Death 384x64~768x64 | 帧边界干净 | 俯视怪物表（战斗/城镇向） |
| NPC | Npc's：Knight/Rogue/Wizzard/Citizen_F 等，128x32 / 256x64 / 384x64 | 同角色规格 | 俯视 NPC |
| 瓦片 | Environment\Tilesets\：Dungeon_Tiles 400x400（16px 网格 25x25，251 非空块、294 占用、27 块跨格复用）、Floors_Tiles 400x416、Wall_Tiles 400x400、Water_tiles 400x400（10/24 行边界空=矮水面） | 16px 网格标准瓦片表 | **俯视瓦片库**（地牢石板/地板/墙/水） |
| 装饰 | Props\Static\：Vegetation 400x432、Rocks 208x304、Farm 400x400、Furniture 800x864、Tools/Resources/Dungeon_Props/Esoteric 各 400x400、Meat 192x144、Pan 160x176、Shadows 400x400 | 多格物品表 | **俯视地图装饰**（可逐格裁切） |
| 树 | Props\Static\Trees\Model_01/02/03 x Size_02~05（128x96 ~ 384x512，单图） | 俯视树，尺寸档齐全 | 可直接挂为 prop_tree |
| 建筑/工坊 | Structures\Stations\：Alchemy/Anvil/Bonfire/Furnace/Sawmill/Workbench/Cooking（含 *-Sheet 动画帧）、Buildings\（Walls 672x800、Roofs、Props、Shadows） | 俯视 | 建造玩法素材（当前游戏无基地建造） |
| 其他 | Weapons\Bone/Wood/Hands、Icons\Resources.png、MockUps\Tavern.png 1280x1280 | — | 武器/图标 |

**许可**：Anokolisa 标准许可（同 1.3）。

---

## 2. 背景替换方案

### 2.1 现状诊断

`level.gd::_build_background`（第 69~78 行）用 Sprite2D 加载 `back_forest.png` 并 `scale = (1280/288, 720/160) = (4.444, 4.5)`——**代码按 288x160 假设，而实际图片是 384x240**（PIL 实测，RGB 无 alpha）。后果：

- 实际显示尺寸 1706x1080，视口 1280x720 内只看到原图左上 ~75% x ~67% 区域；
- 高度溢出 50%，背景构图（地平线/树线）位置不可控；
- 横向 4.44x、纵向 4.5x 的非等比拉伸差 1.3%，肉眼可辨；
- `modulate = (0.5, 0.5, 0.6, 0.55)` 压到半透明，整体发灰发暗（与既往 `assets-rpg-urban.md` 的诊断一致）。
- `mid_forest.png`（176x368 RGBA）存在于 assets/env 但**无代码引用**。

### 2.2 方案 A（推荐）：High Forest 树冠纹理平铺/切片

`Trees\Green-Tree.png` 1344x1200（同族 5 色：Green/Dark/Golden/Red/Yellow）：

- **水平方向**：1344px 原生宽度 > 1280px 视口——取 x∈[0,1280] 直接切片即可覆盖，无需放大；
- **垂直方向**：1200 → 720 缩放 0.6（或裁上部 720px 区域保持 1:1 像素）；
- 左右边缘像素差 0.4（近乎无缝），即便换用平铺也不会出现接缝；非 16px 网格对齐、无短周期，是自由纹理而非瓦片表；
- alpha 77%：树冠之间有透明空洞，叠在天空/暗色层上可透出下层，正好形成"俯视森林 canopy"层次，无需额外抠图；
- 主题映射：grass→Green-Tree、desert→Yellow/Golden-Tree、lava→Red-Tree、stone/temple→Dark-Tree，与 `_build_floor` 的 theme 分支一一对应。

**适配方式（Sprite2D 直接缩放，不改架构）**：在 `_build_background` 中加一个天空层 + 树冠层：

```
天空层：Background\Background.png 480x272（无 alpha、左右无缝 0.4）
  水平平铺 3 张 = 1440px > 1280，垂直拉伸 272→720（2.65x，天空渐变拉伸视觉可接受）
树冠层：Green-Tree.png，scale=(1280/1344, 720/1200)=(0.952, 0.6) 或切片
```

实现仅需把 `_build_background` 的单个 Sprite2D 换成两个（或一个 Parallax2D），约 10~15 行改动；`modulate` 可从 0.55 提到 0.8~0.9（新背景本身较暗，无需再压暗）。

**注意**：树冠图是"从上方看树冠"的纹理化大图，不是带树干/阴影的独立树——适合做整体背景层；若要近景树，用本包 `Trees\Background.png`（896x256）或 Pixel Crawler 的独立树。

### 2.3 方案 B（备选）：Debug Map 整图

`MockUp\Cover.png` 1920x1088（RGB 无 alpha，完整森林地图画面）：

- 宽高比 1920/1088 = 1.765，目标 1280/720 = 1.778——**缩放 0.667 后为 1280x725，只差 5px 高度**，近乎零裁切、近等比；
- 1920x1088 分辨率高于视口，放大比 <1，锐度无损；
- 局限：画面含完整地面/场景，叠在 TileMap 地面之上会视觉冲突（地面纹路与瓦片对不上），更适合：主菜单/结算/关卡预览背景（`main_menu.gd`、`game_over.gd`），或加暗化蒙层后作关卡背景。

### 2.4 方案 C（不推荐）：Gandalf 背景层

`Background layers\Normal BG\layer 1~5`（1024x346）是平台横版远景（城堡+山峦），346px 高放大到 720 需 2.08x，严重模糊；且侧视地平线构图与俯视角格格不入。仅 `Background Castle .png`（1024x346，城堡剪影）可考虑作主菜单点缀，优先级低。

### 2.5 结论

| 方案 | 素材 | 适配方式 | 效果 | 工作量 |
|---|---|---|---|---|
| **A（推荐）** | High Forest Background.png + Green-Tree.png | 平铺 + 切片/缩放 | 俯视森林 canopy，5 主题色 | ~10~15 行 |
| B | Debug Map Cover.png | 直接缩放 0.667 | 完整场景图，适合菜单/结算 | ~5 行 |
| C | Gandalf layer 1~5 | 直接缩放 | 模糊+视角违和 | — |

---

## 3. HUD/血条方案

### 3.1 现状

`hud.gd` 全部血条为代码绘制：`_style_bar()`（第 25~33 行）用 `StyleBoxFlat`（实色填充 + 2px 圆角）叠在深色 `StyleBoxFlat` 底上；玩家 HP 条 140x10、XP 条 140x6、Boss 条 320x14（`_build_boss_bar`，红色 StyleBoxFlat）。无任何贴图。

### 3.2 纹理改造方案

**方案 1（推荐，工作量最小）：ProgressBar 保留，StyleBox 换 StyleBoxTexture**

- `background`：`Hp bar.png`（116x64 深色装饰槽）作 StyleBoxTexture，设 `texture_margin_left/right = 12`（九宫格保住两端装饰），中间拉伸；
- `fill`：`Blue bar.png`（49x6 全不透明纯蓝）或 `red bar.png`（56x54 带框红段），StyleBoxTexture 直接拉伸到 140x10 / 320x14——纯色条拉伸无变形；`red bar.png` 建议 margin 12 保两端；
- XP 条（140x6）用 `yellow bar.png`（32x4）拉伸，高 6px 与 4px 原图接近，几乎无拉伸感；
- 进度表现：ProgressBar 的 fill stylebox 由引擎按 value 裁剪，行为与现状一致，**hud.gd 其余代码零改动**；
- 工作量：`_style_bar` 内两处 stylebox 创建替换 + 按 bar 类型传纹理，约 15~25 行。

**方案 2（效果更精细）：TextureProgressBar**

Godot 4 的 `TextureProgressBar` 支持 `under_texture`（槽）/`over_texture`（填充），进度按 value 像素级裁切，适合"条内渐变/分段"的素材；需把 `_hp_bar` 等 4 处节点类型替换，并处理 theme 常量，约 30~40 行。

**注意点**：

- `Hp bar.png` 是 116x64 的"大方框"（内部仅 27% 不透明、17 色、亮带在 y45~52），直接压到 10px 高会糊成一条灰线——必须配九宫格 margin 或用其只做 Boss 条（320x14 也偏扁，建议 margin 12+ 或改用 `red bar.png` 当 fill、现有暗色底当槽）；
- 填充条均无半透明（semi=0），拉伸安全；
- 若想像素级锐利，可在 `_style_bar` 里对 49x6 用平铺代替拉伸（StyleBoxTexture 无 repeat，TextureProgressBar 方案下可用 `texture_repeat = TextureRepeat.ENABLED` + region 平铺）。

**许可**：GandalfHardcore 许可允许商用+修改（禁 AI 训练/NFT/再分发），可直接导入 `assets/ui/`。

---

## 4. Pixel Crawler 的 384x64 / 512x64 判定与装饰补充

### 4.1 判定：是角色，不是瓦片

- `Entities\Characters\Body_A\Animations\` 下 36 张表：256x64 = 4 帧、384x64 = 6 帧、512x64 = 8 帧，**帧宽 64px，所有帧边界列 alpha 和 = 0**（PIL 逐列验证），是标准的俯视四方向（Down/Side/Up）角色动画表；
- `Entities\Mobs\Orc Crew\Orc\Idle\Idle-Sheet.png`（128x32）= 4 帧 x 32px 怪物 idle，`Run\Run-Sheet.png`（384x64）= 6 帧 x 64px 奔跑；
- 瓦片在 `Environment\Tilesets\`：Dungeon_Tiles / Floors_Tiles / Wall_Tiles / Water_tiles，均为 400x400（或 416 高）16px 网格表（Dungeon_Tiles 实测 251 非空块、27 块被复用、最大复用 10 次 → 可随机混铺的标准地面/墙库）。

### 4.2 装饰补充（对应 prop_*）

现状：`assets\env\prop_bush / prop_rock / prop_sign / prop_tree.png` 是 Sunny Land 横版侧视素材（105x93 / 28x15 / 18x20 / 46x28 等），且**全项目仅 `tools\scripts\import_assets.py` 有导入记录，无任何 .gd/.tscn 引用**——即目前场景里根本没有摆放装饰。Crawler 包可直接填补：

| 用途 | 素材（实测尺寸） | 说明 |
|---|---|---|
| prop_tree 替换/新增 | `Props\Static\Trees\Model_02\Size_02~05`（128x96 / 144x160 / 192x224 / 288x320，绿色俯视树）或 Model_03（棕叶） | 俯视、自带树冠+树影感，4 档尺寸适配疏密 |
| prop_rock 替换 | `Props\Static\Rocks.png`（208x304，多格岩石表） | 俯视岩石，逐格裁切 |
| prop_bush 替换 | `Props\Static\Vegetation.png`（400x432，植物/灌木表） | 俯视植物，含多品种 |
| 新增地面杂物 | `Props\Static\` 的 Farm / Tools / Resources / Meat / Pan / Dungeon_Props | 骨堆/工具/食物等场景点缀 |

树/植物均为 16px 基准对齐的单图（非动画），可直接 `Sprite2D + 随机位置/缩放` 摆入；与现有 32x32 玩家基准同风格（Crawler 与玩家 32px 角色同规格）。**若要让装饰真正出现在关卡里，还需在 `level.gd` 加一个 prop 摆放步骤**（约 20~30 行：随机位置、避开出生点、可选碰撞），这不属于素材导入工作。

### 4.3 瓦片层面的补充（可选）

- `Dungeon_Tiles`（地牢石板/砖）可作 `stone`/`temple` 主题的 kenney_tiles 补充（当前 stone 主题只有 8 块 kenney 瓦片随机混铺）；
- `Wall_Tiles` / `Wall_Variations` 可补"墙体瓦片"——当前游戏墙体是纯碰撞盒（`_build_walls` 无贴图），若要可见墙需 TileMap + 遮挡逻辑，属于玩法扩展；
- `Water_tiles` 是 16px 水面（含矮帧），可补 lava 主题的岩浆水面（当前 lava 用 brick 瓦片凑数）。

---

## 5. 结论清单

### 立即采用

| # | 素材 | 应用点 | 理由与具体文件 |
|---|---|---|---|
| 1 | High Forest 树冠层 | 关卡背景 | `Trees\Green-Tree.png`（1344x1200）左右无缝、原生宽度覆盖 1280 视口；配套 `Background\Background.png`（480x272 天空，左右无缝 0.4）作下层；5 色对应 5 个关卡 theme（§2.2 方案 A） |
| 2 | Gandalf Hp bar | HUD 血条纹理 | `Blue bar.png`（49x6）/`yellow bar.png`（32x4）纯色填充条拉伸无变形、`red bar.png`（56x54）Boss 条填充、`Hp bar.png`（116x64）九宫格槽；替换 `hud.gd` `_style_bar` 的 StyleBoxFlat 为 StyleBoxTexture，15~25 行（§3.2 方案 1） |
| 3 | Pixel Crawler 装饰 | prop_* 补充素材 | `Props\Static\Trees\Model_02\Size_02~05`（俯视树，128x96~288x320）、`Vegetation.png`（400x432 植物表）、`Rocks.png`（208x304 岩石表）——16px 基准、与现有 32x32 玩家同规格，替换 Sunny Land 侧视 prop（§4.2） |

### 可选

| # | 素材 | 应用点 | 说明 |
|---|---|---|---|
| 4 | Debug Map `MockUp\Cover.png`（1920x1088） | 主菜单/结算背景 | 宽高比 1.765 与 16:9 几乎一致，缩放 0.667 即可；含完整场景不适合做关卡背景（与地面瓦片冲突） |
| 5 | Pixel Crawler `Environment\Tilesets\Dungeon_Tiles.png` 等 4 张 | 地面/墙/水瓦片扩充 | 16px 网格、251~325 非空块；补 stone/temple 主题、水体主题 |
| 6 | High Forest `HUD\Base-01.png`（432x304） | 面板/对话框底框 | 俯视 HUD 风格底框，可替换部分 StyleBoxFlat 面板 |
| 7 | Gandalf 动画水 `Animated Sprites\GandalfHardcore Animated Water Tiles.png`（640x352，4 帧） | 水面/岩浆动画瓦片 | 若做可通行水面或岩浆主题时启用 |
| 8 | Gandalf 单棵装饰树 Tree1~4 / Birch / Weeping Willow | 横版风关卡点缀 | 侧视树，仅作装饰遮挡可用；俯视场景中违和度中等 |

### 不适用

| # | 素材 | 理由 |
|---|---|---|
| 9 | Gandalf `Floor Tiles1/2`、`Other Tiles1/2`、`House Tiles`、`BG Dirt1/2` | 32px 块侧视平台砖（草顶+泥体），俯视地面用不了（§1.1） |
| 10 | Gandalf `Background layers`（1024x346 x3 季） | 平台横版远景，放大 2x 模糊 + 侧视构图（§2.4） |
| 11 | High Forest `Character\`、`Mob\` 动画表 | 横版动作集（含 Jump/Dead），与俯视四向移动系统不匹配；64px 帧与 32px 基准需整体重建 |
| 12 | Pixel Crawler `Body_A` 36 张角色表 / NPC / Mobs | 是优质俯视素材，但替换玩家/敌人需重建动画树与敌人表（当前敌人用生成式 32x32 精灵），成本高，建议后续独立立项 |
| 13 | Debug Map `MockUp\Tiles.png`（1664x1856） | 调试拼图，无直接用途 |
| 14 | Gandalf `Snow blizzard sheet`（2420x1644）、cloud/birds/hot air balloon/Boat | 横版天气与道具 |
| 15 | Pixel Crawler `Structures\Stations\`（Alchemy/Anvil/Furnace/Sawmill 等） | 依赖基地建造玩法（当前 build_panel 是法术格+道具，无建造），素材先入库 |

---

## 6. 导入与许可汇总

| 包 | 许可 | 商用 | 修改 | 备注 |
|---|---|---|---|---|
| GandalfHardcore Platformer / Hp bar | READ ME.txt（GandalfHardcore 许可） | ✔ | ✔ | 禁再分发/AI 训练/NFT/游戏工具/印刷材料 |
| Legacy Fantasy - Debug Map | Terms.txt（Anokolisa） | ✔ | ✔ | 免署名（可选署名）；禁转售素材本身 |
| Legacy-Fantasy High Forest 2.3 | Terms.txt（Anokolisa） | ✔ | ✔ | 同上 |
| Pixel Crawler 2.11 | Terms.txt（Anokolisa 简版） | ✔ | ✔ | 同上 |

全部 4 家许可均允许商用游戏集成与修改，无署名义务（GandalfHardcore 无署名要求、Anokolisa 署名可选）。导入时建议在 `assets/CREDITS.md` 追加 4 项来源记录（与现有 Sunny Land / Kenney 条目并列），并注明 GandalfHardcore 的 AI 训练禁止条款。

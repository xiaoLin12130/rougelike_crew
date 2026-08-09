# Kenney 素材包本地分析报告（top-down-shooter × pixel-platformer）

> 分析日期：2026-08-09 ｜ 分析方法：PIL 像素级实测 + 包内 XML/Tiled 元数据 + 代码接入点核对（离线，未修改任何文件）
> 目标项目：PixelRogue（Godot 4.7，640x360 视口整数缩放，GL Compatibility）
>
> 素材包：`H:\rougelike_crew\.tools\kenney_top-down-shooter\`、`H:\rougelike_crew\.tools\kenney_pixel-platformer\`（均含 License.txt，CC0，可商用免署名）

---

## 1. top-down-shooter 角色 PNG 结构分析

### 1.1 包内容清单（实测）

| 内容 | 位置 | 说明 |
|---|---|---|
| 9 个角色 × 6 动作 = 54 张 PNG | `PNG\<角色名>\` | 全部单帧静态姿态（见 1.2 证据） |
| 3 个独立武器图 | `PNG\weapon_gun/machine/silencer.png` | 19x10 / 33x10 / 25x10，与角色手中的枪同款 |
| 地形瓦片 ~500 张 | `PNG\Tiles\tile_01..538.png` | 全部 64x64，多为 RGB（无透明通道） |
| 角色图集 | `Spritesheet\spritesheet_characters.png` + `.xml` | 512x256，54 个子纹理，XML 含精确矩形 |
| 瓦片图集 | `Spritesheet\spritesheet_tiles.png`、`Tilesheet\tilesheet_complete(_2X).png` | 1988x1470 / 1728x1280 |
| 矢量源 | `Vector\vector_characters.svg/.swf` | 可用于改色重导出 |
| 用法示例 | `Sample.png`、`Preview.png` | 918x515，展示拼装用法 |

⚠️ **本副本不含 Effects、Vehicles 目录**（全盘检索 effect/explos/vehicle/car/tank/fire/laser 均无命中）。Kenney 官网该包附带的爆炸/枪口火光/车辆素材不在本地，投射物与爆炸无法从本包取材。

### 1.2 角色图尺寸与帧结构

所有角色动作图高度统一为 **43px**，宽度随动作变化（33~57px），全部**单帧**：

| 动作 | 角色尺寸范围（宽 x 高） | 内容 |
|---|---|---|
| stand 站立 | 33x43 ~ 36x43 | 双手自然下垂（空手） |
| hold 持枪待机 | 35x43 ~ 38x43 | 双手握枪于胸前（手枪，枪口朝上） |
| gun 手枪射击 | 49x43 ~ 52x43 | 双手平举手枪 |
| machine 冲锋枪 | 49x43 ~ 52x43 | 双手持冲锋枪 |
| silencer 消音器 | 54x43 ~ 57x43 | 双手持长枪管武器 |
| reload 换弹 | 39x43 ~ 42x43 | 低头换弹匣姿态（体态最像"施法"） |

每个角色 6 个动作齐全（Hitman/Man Blue/Man Brown/Man Old/Robot/Soldier/Survivor/Woman Green/Zombie），命名统一 `{name}_{action}.png`。

**单帧证据（三重验证）：**
1. `spritesheet_characters.xml` 共 54 个 `<SubTexture>`，每动作恰好 1 个，矩形尺寸与独立 PNG 完全一致（如 `manBlue_stand` x=426 y=132 w=33 h=43）；
2. 逐列 alpha 扫描无任何全透明分隔列（若有横向多帧拼图必然出现）；
3. 图集矩形与独立 PNG 在不透明像素区逐像素一致（差异仅存在于半透明描边像素，平均 0.41/255，为图集打包边缘 bleed）——**导入用独立 PNG 更干净**。

### 1.3 角色替换玩家评估

**合适点**

- 视角正确：3/4 俯视（顶视）角色，与俯视角肉鸽的镜头关系完全匹配；
- 姿态齐全：6 个动作可直接映射游戏状态：stand=待机、hold=蓄力/移动、gun/machine=攻击、reload=施法、silencer=特殊技；
- 9 个角色 = 现成的换皮/变体池；CC0 无授权负担；
- 单帧可直接用：现有敌人系统本就支持 `frames: 1`（Boss 即单帧，见 `enemies.json` + `enemy.gd:_build_sprite()`），零代码改动。

**不合适点（决定性）**

- **完全没有行走动画**：本包角色是静态姿势，玩家当前是 4 方向 × 2 帧行走（`player.gd` ANIM_FPS=8）。替换后行走要么静止滑行，要么用代码合成上下浮动（`offset.y = sin()`），观感打折；
- **题材冲突**：西装杀手/现代军人/市民/机器人/僵尸 vs 本作法师题材。玩家是"程序化像素法师"，换成一个穿西装的枪手违和；
- **风格不统一**：矢量渲染平滑风，单张 118~209 种颜色（实测），而现有程序化精灵仅 3~8 色、硬边像素风。在 2x 整数缩放下风格割裂肉眼可见；
- **尺寸不规整**：33~57x43 随动作变宽，换动作时锚点/居中需逐张处理（当前玩家 32x32 居中锚点、碰撞半径 8）。43px 高度比 32px 大 34%，遮挡排序需复查；
- 无独立地面阴影（底部行即脚部像素），俯视投影感弱于多数顶视素材。

**结论：不推荐替换玩家；推荐用作敌人/NPC 素材池**（见第 5 节）。

---

## 2. pixel-platformer 角色精灵表分析

### 2.1 布局（实测 + Tiled 元数据）

| 项 | 实测值 |
|---|---|
| 角色单元 | **24x24**（不是 64x64） |
| 表结构 | `Tilemap\tilemap-characters.png` = 224x74 = **9 列 × 3 行 = 27 格**（1px 间隔） |
| 紧凑版 | `tilemap-characters_packed.png` = 216x72（无间隔，可直接切 9x3） |
| Tiled 定义 | `Tiled\tileset-characters.tsx`：tilewidth=24、tilecount=27、columns=9、**tileoffset x=-3**（角色绘制比格子偏左 3px） |
| 独立文件 | `Tiles\Characters\tile_0000..0026.png` 27 张，与表内单元逐像素一致（已核验 tile_0000） |
| 同包地形瓦片 | `Tiles\tile_0000..0179.png` 180 张，**18x18**；背景 `Tiles\Backgrounds\` 24 张，24x24 |

### 2.2 27 格内容分类（几何 + 调色板实测）

| 格子 | 内容 | 判定依据 |
|---|---|---|
| r0c0~c7 | **英雄 × 4 配色**（绿/蓝/粉/黄），每色 2 帧 | 不透明像素 399/400 成对出现；偶数/奇数帧质心 y=11.4/10.5 → 1px 上下摆动 = 2 帧走/待机动画；成对差异小 |
| r0c8 | 灰色岩石/石块 | 356px，灰色系 (67,74,95) |
| r1c0~c1 | 英雄第 5 配色（棕褐），2 帧 | 与 r0 相同结构 |
| r1c2~c3 | 小型黄棕生物 A，2 帧 | 320px，居中央心 |
| r1c4~c5 | 更小黄棕生物 B，2 帧 | 143/136px，小而居中 |
| r1c6~c8 | 红灰生物，**3 帧** | 201/213/193px，内容贴底部（质心 y≈16），红 (252,104,59) |
| r2c0~c2 | 蓝色生物，**3 帧** | 182/194/174px，内容贴底部（质心 y≈17） |
| r2c3~c5 | 大型蓝色生物，**3 帧** | 472~500px 几乎占满格子（史莱姆类团块） |
| r2c6~c8 | 棕褐生物，**3 帧** | 189~212px，内容中下 |

合计：**1 个英雄（5 配色 × 2 帧）+ 1 块岩石 + 5 类生物动画**。全部朝右的侧视图、平坦色块风（单格 10~20 色，与游戏程序化精灵 3~8 色的观感最接近）。

### 2.3 俯视应用评估：**能用，但有三个前提**

1. **单方向视图**：只有朝右帧。俯视角游戏处理方式：
   - left：`flip_h = true` 镜像即可；
   - up/down：复用侧向帧（英雄是圆胖胶囊体，方向歧义小，可接受；有朝向感的生物（如红色爬行生物）上/下行走略有违和）。
2. **尺寸 24x24 → 32x32**：游戏玩家/敌人均为 32x32、碰撞半径 8。方案（按推荐序）：
   - **补边**：24x24 内容贴底/居中补到 32x32 画布（内容约 20x24，四周各补 4px 余量），保持像素原样，最干净；
   - 原生 24x24 使用：在引擎内 scale=4/3（非整数，2x 视口下像素块大小不均）——不推荐；
   - 最近邻重采样 24→32（1.333 非整数倍，产生不等宽像素）——不推荐。
3. **切片方式**：无需切片——直接用 `Tiles\Characters\tile_0000..0026.png` 独立文件（与表单元一致）；若用整表，导入时按 24px 网格切 9x3 即可（packed 版无间隔）。

---

## 3. 武器 / 特效目录评估

### 武器（3 张，可用但主题不符）

- `weapon_gun.png` 19x10、`weapon_machine.png` 33x10、`weapon_silencer.png` 25x10，均为侧向枪械俯视图，与角色手持的同款；
- 尺寸太小，不适合做投射物本体（本作投射物 12x12 程序化 `proj_*.png`，且魔法主题不需要枪弹）；
- 可作：拾取物/图标/角色副手挂件。本作已有成套 SVG 图标（`assets\icons\`），收益低。

### 特效（本地副本**没有**）

- 本包无 Effects 目录，**没有**爆炸/火光/弹道素材可用；
- 现有方案（CPUParticles 程序化粒子 + Space Shooter 包的 fire00~19、laser、meteor、shield、star）继续保留，无需改动；
- 若日后拿到完整版 top-down-shooter，其 Effects（枪口火光、爆炸序列）可平替 Space Shooter 火光，届时再评估。

---

## 4. 与现有程序化精灵对比

### 4.1 风格统一性

| 维度 | 现有 gen 精灵 | top-down 角色 | pixel-platformer 角色 |
|---|---|---|---|
| 画风 | 硬边像素 | 矢量平滑（118~209 色） | 平坦像素（10~20 色） |
| 分辨率 | 32x32 | 33~57x43 | 24x24 |
| 视角 | 俯视 | 俯视 ✅ | 侧视 ⚠️ |
| 动画 | 2 帧/方向（玩家），2 帧 idle（敌人） | **无动画** | 2 帧（英雄）/ 3 帧（生物） |
| 与现风格融合 | — | ✗ 明显割裂 | ✅ 最接近 |

### 4.2 接入工作量

**接入点（现状，已核对代码）：**
- 玩家：`player.gd:_build_frames()` 运行时构建 SpriteFrames（4 方向 × 2 帧，路径常量数组）+ `player.tscn` 的 AnimatedSprite2D；改路径即可，加 flip_h 需小改；
- 敌人：`enemies.json` 每项 `sprite`（基础路径）+ `frames`（普通怪 2、Boss 1）→ `enemy.gd:_build_sprite()` 自动拼 `_1.png.._N.png`；**纯数据驱动**，单帧/三帧都支持；
- 地板：`level.gd:_build_floor()`，TileMapLayer + TileSet，TILE_SIZE=16，按主题选 atlas（grass/stone/dirt）；
- 召唤物：`summon.gd` 单张 Sprite2D。

| 方案 | 工作量 | 说明 |
|---|---|---|
| top-down 角色 → 敌人变体 | 每只约 5 分钟 | 复制 PNG + json 改 `sprite`/`frames: 1`；9 角色 × 6 姿态 = 54 个现成变体 |
| pixel 英雄 → 玩家 | 30~60 分钟 | 补边到 32x32 + 改路径 + left 加 flip_h、up/down 复用侧帧 |
| pixel 生物 → 对应敌人 | 每只约 10 分钟 | 3 帧可直接用（json frames:3），风格统一 |
| pixel 瓦片 → 地板 | 1~2 小时 | 18x18 ≠ 16x16：需重采样/补边重建 atlas，或改 TILE_SIZE 与铺地逻辑；平台风瓦片俯视观感打折 |
| top-down 瓦片 → 地板 | 不推荐 | 64x64 矢量风，与 16x16 像素地板尺度/风格双重不匹配 |

---

## 5. 结论清单

### ✅ 推荐应用

| # | 文件 | 用途 | 实现方式 |
|---|---|---|---|
| 1 | `PNG\Zombie 1\zoimbie1_*.png`（6 姿态） | 僵尸类敌人（含精英变体） | 拷贝到 `assets\sprites\`，`enemies.json` 加条目 `sprite` + `frames: 1`；换姿态即换变体 |
| 2 | `PNG\Robot 1\robot1_*.png` | 构装体/机械类敌人、召唤物 | 同上；或 `summon.gd` 换纹理 |
| 3 | `PNG\Survivor 1\`、`Man Blue/Brown/Old`、`Woman Green`、`Soldier 1`、`Hitman 1` | 匪徒/民兵类敌人与 NPC，姿态池 | 同上；reload 姿态可当"施法"用 |
| 4 | `Tiles\Characters\tile_0000~0007.png`（英雄 4 色 × 2 帧） | **玩家替换首选**或玩家可选皮肤 | 24→32 补边；`player.gd` 路径替换 + left `flip_h`，up/down 复用侧帧 |
| 5 | `Tiles\Characters\tile_0018~0020.png`（蓝色大生物 3 帧） | 直接替换 slime 敌人（题材/风格吻合） | json `frames: 3`；enemy.gd 已支持 |
| 6 | `Tiles\Characters\tile_0008.png`（岩石）、`tile_0015~0017`（红生物）、`tile_0024~0026`（棕生物）、`tile_0009~0010`（英雄第 5 色） | 障碍物/新敌人/友军换皮 | 同 4/5 方式 |
| 7 | `Spritesheet\spritesheet_characters.xml` | 若用整表图集导入的矩形参考 | Godot 用 AtlasTexture 按 XML 矩形取值，或直接独立 PNG |

### ⚠️ 谨慎项

- `PNG\weapon_*.png`（3 张 10px 高小枪）：仅作拾取物/图标，魔法题材下收益低；
- `Tiles\tile_*.png`（18x18，180 张）：平台侧视风瓦片用于俯视地板观感打折，且 18≠16 需重建 atlas（改 `level.gd` 或重采样），仅值得为"换地板美术"整体做一次；
- top-down 角色替换**玩家**：无行走帧 + 现代题材 + 高色数风格三连不符，除非接受程序化浮动动画并做整包美术统一（不推荐现在做）；
- `Tiles\Backgrounds\`（24x24 × 24 张）：可做关卡装饰/背景层，先目检内容再定。

### ❌ 不适用项

- **Effects / Vehicles**：本副本不存在，爆炸/投射物继续用 CPUParticles + Space Shooter 包；
- `Tilesheet\tilesheet_complete.png`、`Spritesheet\spritesheet_tiles.png`、top-down `PNG\Tiles\`（64x64 矢量瓦片）：与 16x16 像素地板尺度/风格双重不匹配；
- `Vector\*.swf`：Godot 无 SWF 导入路径，SVG 改色只适合美术工具环节；
- top-down 角色"动画帧"：不存在（54 张全为单帧），任何动画需求都必须代码合成；
- `Construct 3\Pixel Platformer.c3p`：演示工程（player-walk 2 帧等小图），与 27 格角色表无关，无直接价值。

---

## 附录：关键路径索引

- 角色独立 PNG：`.tools\kenney_top-down-shooter\PNG\{Hitman 1,Man Blue,Man Brown,Man Old,Robot 1,Soldier 1,Survivor 1,Woman Green,Zombie 1}\{name}_{stand,hold,gun,machine,silencer,reload}.png`
- 角色图集+XML：`.tools\kenney_top-down-shooter\Spritesheet\spritesheet_characters.{png,xml}`
- 武器：`.tools\kenney_top-down-shooter\PNG\weapon_{gun,machine,silencer}.png`
- 像素角色表：`.tools\kenney_pixel-platformer\Tilemap\tilemap-characters.png`（224x74，1px 间隔）/ `_packed.png`（216x72）
- 像素角色独立文件：`.tools\kenney_pixel-platformer\Tiles\Characters\tile_0000..0026.png`
- 像素瓦片：`.tools\kenney_pixel-platformer\Tiles\tile_0000..0179.png`、`Tiles\Backgrounds\tile_0000..0023.png`
- Tiled 元数据：`.tools\kenney_pixel-platformer\Tiled\tileset-characters.tsx`（24px、27 格、tileoffset -3）
- 游戏接入点：`scripts\player\player.gd:_build_frames()`、`scripts\enemies\enemy.gd:_build_sprite()`、`data\enemies.json`、`scripts\enemies\level.gd:_build_floor()`（TILE_SIZE=16）

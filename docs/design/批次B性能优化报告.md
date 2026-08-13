# 批次B性能优化报告

- 日期：2026-08-13
- 范围：`scripts/enemies/level.gd`（背景生成）、`scripts/core/game_state.gd`（estimate_dps / apply_item_effects_to_stats 建索引）
- 运行环境：Godot 4.7.1 headless（`.tools/godot/Godot_v4.7.1-stable_win64_console.exe --headless`）

## 一、三项优化说明

### 1. level.gd 背景生成：164 万次 set_pixel → 1280 次 blit_rect

`_build_scene_background()` 原先用双层 for 循环对 1280×1280 目标图逐像素 `set_pixel`
（1280×1280 = 约 164 万次 GDScript 逐像素调用），每次切关都执行，明显卡顿。

改动：

- 按任务指定方案，用 `Image.blit_rect()` 重写：把源图（scene_grass.png 等，1280×720）的
  "草地段"（y 201..720，高度 519 行）纵向无缝拼接复制到 1280×1280 目标图。
- 每行一次 `blit_rect`（`Rect2i(0, src_y, 1280, 1)` 拷贝一行），共 1280 次批量拷贝，
  替代 164 万次逐像素调用；`src_y = 201 + (y % 519)` 的拼接公式与旧实现完全一致。
- 补充 `src_img.convert(Image.FORMAT_RGBA8)`：`blit_rect` 要求源/目标图格式一致
  （PNG 解码格式可能与 RGBA8 不同），旧 `set_pixel` 会自动转色、新接口必须显式统一；
  转换后像素值与旧实现逐点一致（已由测试抽样验证）。
- 保持现有架构不变：仍然是"世界空间一张 1280×1280 大图 + 相机 limit"，未改场景结构。

### 2. estimate_dps：core/shell 线性查找 → 字典索引

原先 `for slot in run.grid` 循环内，对每个格子都 `for c in spells.cores` / `for s in spells.shells`
线性扫描查找（15 核心 × 10 外壳，每格最坏 25 次遍历）。改动：

- 函数开头一次遍历建立 `core_by_id` / `shell_by_id` 字典（id → 定义）。
- 网格循环内改为 O(1) 字典查找。
- 语义保持：建索引时"仅首次写入"（等价旧代码 `break` 取第一个匹配 id 的行为）；
  找不到时返回空字典 `{}` 的分支与原逻辑一致（核心缺失 continue、外壳缺失走空 mods）。

### 3. apply_item_effects_to_stats：全表扫 tag → items_by_tag 索引

原先每次刷新都遍历全部 293 条道具查 `hp`/`max_hp` tag。改动：

- 新增惰性缓存索引 `items_by_tag`（tag → 道具列表），以 items 源数组引用为失效哨兵
  （`tables` 被替换时自动重建，不依赖 `load_tables` 调用点）。
- max_hp 聚合只遍历命中 `hp`/`max_hp` tag 的道具列表；双 tag 道具按 id 去重只累计一次
  （当前数据无双 tag 道具，去重为防御性写法）。
- 其余面板属性（attack_bonus / speed_bonus / attack_speed_bonus / lifesteal / crit /
  detect_synergies 等）逻辑不动，仅改查找方式，不改变行为语义。

## 二、性能对比（headless benchmark）

`test_perf_batch_b.gd` 内置 benchmark：同一源图、同一拼接公式，分别计时
"旧实现（双层 set_pixel 循环）" vs "新实现（blit_rect 按行拷贝）"：

| 指标 | 旧实现 | 新实现 | 加速比 |
| --- | --- | --- | --- |
| 纯图像生成（第 1 次运行） | 78.5 ms | 1.6 ms | ≈ 49.5x |
| 纯图像生成（第 2 次运行） | 64.9 ms | 1.4 ms | ≈ 46.3x |
| `_build_scene_background` 完整调用（含加载/解码/Sprite2D 创建） | — | ≈ 203–207 ms | — |

说明：

- 完整调用剩余的 ~200ms 大头是纹理解码 `get_image()` / ImageTexture 创建等原有成本，
  本次任务按要求只重写逐像素循环（"保持现有架构最稳妥"），未动资源加载路径。
- headless 下计时有噪声（无垂直同步、CPU 调度抖动），故跑两轮取参考值；
  核心结论是"164 万次 set_pixel 已不存在"（静态源码检查 + 运行时验证双保险）。
- estimate_dps / apply_item_effects_to_stats 属小规模线性查找（15/10/293 条），
  未单独做毫秒级 benchmark，以"改造前后结果一致"的行为测试覆盖。

## 三、测试结果

| 测试 | 结果 | 说明 |
| --- | --- | --- |
| smoke_test.gd | ✅ OK（exit 0） | 全部 autoload/数据表/场景/脚本编译检查通过 |
| test_perf_batch_b.gd（新增） | ✅ OK | 见下方断言明细 |
| test_core_mechanics | ✅ OK（exit 0） | 状态/分裂/回血/连锁等核心机制无回归 |
| test_sync_hooks | ⚠️ 3 个历史遗留失败 | 与本批次无关，见下方说明 |

`test_perf_batch_b.gd` 断言明细：

1. 背景生成后 `SceneBackground.texture` 尺寸 = 1280×1280；
2. 抽样 265 点（关键边界行 0/200/201/518/519/719/720/1000/1279 + 40 随机点）
   像素与旧算法公式 `src_y = 201 + (y % 519)` 逐点一致；
3. 静态检查：`_build_scene_background` 函数体内不再出现 `.set_pixel(`；
4. `estimate_dps` 与改造前线性查找算法在 4 个抽样网格（空网格 / 双技能 / 混合含召唤 /
   含未知 id 与空外壳的边界网格）下结果完全一致；
5. `apply_item_effects_to_stats` 的 max_hp 与改造前语义一致
   （life_crystal×2 + defense_crystal×1 + synergy_bonus.max_hp，结果 455），
   并重复调用验证索引缓存路径结果不变。

test_sync_hooks 3 个失败说明（与本次改动无关）：

- 失败项均为 `_test_player_speed` 的移速聚合期望（want 343.2/440/550，got 312/400/500）。
- 实测 got 值与已提交的 `data/balance.json`（`player.speed = 200`）完全吻合
  （200×1.3×1.2=312、200×2.0=400、200×2.5=500），而测试期望按旧值 220 书写
  （data/balance.json 工作区无改动，speed=200 为 HEAD 提交值），属历史遗留的
  测试/数据不同步，与批次B的 estimate_dps / max_hp 改动无交集（移速聚合走
  `aggregate_bonus("speed")`，未被本批次触碰）。
- 同文件内调用 `apply_item_effects_to_stats` 的攻速聚合用例（`_test_attack_speed`）全部通过，
  证明本批次对 `apply_item_effects_to_stats` 的改动无回归。

## 四、改动文件清单

| 文件 | 类型 | 说明 |
| --- | --- | --- |
| `scripts/enemies/level.gd` | 修改 | `_build_scene_background`：set_pixel 双层循环 → blit_rect 按行拷贝 + 格式统一 |
| `scripts/core/game_state.gd` | 修改 | `estimate_dps` 建 core_by_id/shell_by_id 索引；`apply_item_effects_to_stats` 建 items_by_tag 缓存索引 |
| `scripts/tests/test_perf_batch_b.gd` | 新增 | 断言 + 新旧背景生成 benchmark |
| `docs/design/批次B性能优化报告.md` | 新增 | 本报告 |

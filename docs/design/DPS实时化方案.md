# DPS 实时化方案

> 状态：调研提案（未修改任何游戏代码）
> 日期：2026-08-11
> 范围：HUD 实测 DPS（滑动窗口）＋构筑面板理论 DPS（保留），两者语义分离
> 关联文件：`scripts/core/game_state.gd`（estimate_dps 684-737 行）、`scripts/ui/game/hud.gd`（_refresh_dps 353-357 行）、`scripts/core/event_bus.gd`（damage_dealt 契约）、`docs/design/contracts.md`、`docs/design/data-schema.md`

---

## 1. 问题背景

用户反馈：游戏内 DPS 显示不是实时计算，看着不准确。

现状代码事实：

- `GameState.estimate_dps()`（[game_state.gd](H:\rougelike_crew\scripts\core\game_state.gd) 684 行）是**公式估算**：遍历法术网格，按 `base_damage × damage_mult × shots / cooldown` 乘算理论值，召唤物按"每核心 ≈ 2 只 × 30 伤害"粗估，最后乘 `atk/speed/cd` 聚合系数（737 行写回 `run.dps_estimate`）。
- HUD 每 0.5s 定时（hud.gd 56-62 行建 Timer）调用 `_refresh_dps()`（353-357 行）直接显示 `estimate_dps()`。
- 同一估算值还被三处消费：`fx_manager.gd` 345-352 行"爽感档位"（300/800/1500 分档）、`game_over.gd` 39-43 行结算页、`auto_play.gd` 道具/法术决策打分。

估算与玩家实际体感的偏差来源：命中率、弹道飞行时间、AOE 多目标收益、暴击期望（估算不含）、DOT/状态伤害（估算不含）、召唤物实际攻击频率、以及敌人密度与波次节奏（战斗空窗期实测输出为 0）。公式本身在 `spell_caster` 对齐上做了努力（注释称"与 spell_caster 公式对齐"），但它回答的是"纸面能打多少"，不是"刚才实际打了多少"。

---

## 2. 调研结论：肉鸽游戏的 DPS 显示惯例

### 2.1 业界存在两种语义，且通常分开

| 语义 | 回答的问题 | 典型位置 | 计算方式 |
|---|---|---|---|
| 理论 DPS（build 语义） | 这套构筑纸面能打多少 | 构筑面板/角色属性页/武器卡 | 静态公式（伤害 × 攻击频率，含暴击期望） |
| 实测 DPS（计量语义） | 刚才这段时间实际打了多少 | HUD 战斗计量器 | 滑动窗口内实际伤害事件求和 ÷ 窗口时长 |

### 2.2 四款对标肉鸽的惯例

- **吸血鬼幸存者（Vampire Survivors）**：游戏内**没有任何 DPS 计量器**。HUD 只有伤害飘字；暂停面板展示的是构筑乘区（Might/Cooldown/Amount/Area 等）；伤害语义按"单次命中伤害 × 弹数 × 冷却"组织。社区对单武器的"DPS"全部是**理论计算**（wiki 的 Damage 页给出公式），没有实测值。
- **以撒的结合（Binding of Isaac）**：游戏内无 DPS。角色属性页显示单次伤害（Damage）、射速（Tears/tear delay）等**每击参数**；社区 DPS 计算器基于 damage × 射速公式算**理论 DPS**（build 语义）。
- **雨中冒险 1/2（Risk of Rain 1/2）**：无 DPS 计量器。wiki 的 Damage 页把伤害组织为 12 种**单次命中伤害类型**（Active White / DoT / 链伤等），幸存者面板的"Damage"是每击数值；实测统计仅存在于社区 Mod（如 BetterUI 的伤害日志）。
- **土豆兄弟（Brotato）**：设置里有 "Display DPS" 选项，开启后在武器卡/商店显示一个 DPS 数值——它是 **damage × 攻速的理论值**，属于构筑界面语义；战斗中同样没有实测计量器。

**结论**：肉鸽主流惯例是"HUD 只显示伤害数字，DPS 只以理论值出现在构筑/属性界面"；**实测滑动窗口 DPS** 的成熟形态来自 MMO 战斗计量器（WoW 的 Details!/Recount，常见 3-10s 窗口），在肉鸽里属于增强项。因此本方案"HUD 显示实测、构筑面板显示理论"既符合肉鸽惯例，又把两种语义彻底分开，不存在冲突。

### 2.3 Godot 官方文档建议（已在线核验）

- **信号用于解耦**："Using signals" 教程明确以"血条响应玩家受伤/回血事件"为例，说明信号让节点间无引用地响应事件——本项目 HUD/GameState 监听 `damage_dealt` 正是该模式的官方推荐形态（事件驱动写入，定时读出）。
- **Timer 类**：适合周期任务（本项目 0.5s 刷新）；文档明确 **Timer 受 `Engine.time_scale` 影响**，且**亚 0.05s 的定时器建议手写**。本项目有慢动作（`fx_manager._on_slow_mo` 改 `Engine.time_scale`），因此统计窗口的时钟不要用 Timer 计数，而是用游戏时间轴（`GameState.run.time`，在 `game_root._process` 累加、暂停时冻结）——与伤害事件同轴，慢动作/暂停下自动一致。
- 高频信号的处理建议（官方 + 社区惯例）：监听方只做 O(1) 追加与惰性剪枝，**绝不在信号回调里做 UI 更新**；UI 由 0.5s Timer 读聚合值。

---

## 3. 现状梳理（伤害结算路径与口径注意）

### 3.1 事件链路

`EventBus.damage_dealt(dmg: int, pos: Vector2, is_crit: bool)`（event_bus.gd 9 行）是**全部玩家方伤害的统一出口**，发射点 30+ 处，已覆盖：

- 弹幕命中：`projectile.gd` 261 行 `_hit_enemy`
- 近战：`melee_attack.gd` 112 行 `_swing`
- 特殊核心：`spell_caster.gd` 308/322/339 行（传送/祝福/反制瞬发爆炸）
- 召唤物：`summon.gd` 449 行 `_damage_enemy`
- 流派附加/状态/反弹：`crit/curse/defense/fire/holy/ice/mech_items/melee/poison/summon/thunder/water/wind` 共 16+ 处（附加伤害、毒雾/火地 tick、荆棘反弹等）

现有监听方：`game_root._on_damage_dealt`（吸血 + `SynergyRegistry.trigger("damage_dealt")`）、`fx_manager._on_damage_dealt`（伤害数字/暴击粒子/震屏）。**该信号已足够作为实测 DPS 的数据源，无需新增信号。**

### 3.2 口径注意事项（设计决策的依据）

1. **名义伤害口径**：事件携带的是暴击后、**护甲减免前**的名义伤害（`enemy.take_damage` 内部扣 armor，返回值未暴露）。实测 DPS 与伤害飘字一致，符合玩家直觉；"实际扣血"口径需另改接口，本轮不做。
2. **过杀计入**：事件先于死亡结算发出，过杀部分计入——与理论 DPS"满额输出"口径一致，不做扣除。
3. **DOT 覆盖不完整（已知缺口）**：毒 DOT 跳伤走 `poison_synergy` 会发 `damage_dealt`（330 行等），但**灼烧 DOT 由 `enemy.gd` 内部 `_burn_left` → `_take_raw` 结算，不发事件**（enemy.gd 195-200 行只有 fx_hit/fx_dot_text）→ 实测值会少计灼烧段。修复属于战斗模块改动（enemy.gd 归 Agent E/主 Agent），建议单独立项：在 burn tick 补发 `damage_dealt` 或迁移到 synergy 处理（与毒一致）。
4. **防御系反射/荆棘计入**：defense_synergy 反射伤害也走该信号，语义上是"我方实际造成的伤害"，计入合理。
5. **同步/双发问题**：个别路径可能对同一伤害发多次事件（如额外伤害拆成独立事件），但每次事件都对应一次真实扣血或附加伤害，累加口径正确。

---

## 4. 方案设计

### 4.1 语义分层（核心决策）

| 界面 | 展示值 | 语义 | 数据源 |
|---|---|---|---|
| HUD 左上 DPS 小字 | 实测 DPS（近 5 秒） | 实际输出 | 新增 `GameState.measured_dps()` |
| 构筑面板"玩家属性" | 理论 DPS（估算） | 纸面构筑强度 | 保留 `GameState.estimate_dps()` |
| 结算页 | 实测均值 DPS + 理论 DPS 并存 | 整局回顾 | `run.total_damage / run.time` ＋ `dps_estimate` |
| fx_manager 爽感档位（可选） | 实测 DPS（带平滑） | 与玩家感知一致 | `measured_dps()` |
| auto_play 决策 | 保留理论 DPS | 决策需要与命中无关的纸面预期 | 不改 |

### 4.2 GameState 新增实测滑动窗口（改动文件：`scripts/core/game_state.gd`）

```gdscript
## ===== 实测 DPS 滑动窗口（2026-08-11 方案）=====
## 语义：近 DPS_WINDOW_SEC 秒内 EventBus.damage_dealt 实际伤害和 ÷ 窗口时长。
## 时钟：run.time（game_root._process 累加，暂停冻结、慢动作同步）——与伤害事件同轴。
const DPS_WINDOW_SEC := 5.0
var _dmg_ts: Array[float] = []   # 窗口内事件时间戳（run.time 同轴，升序）
var _dmg_val: Array[int] = []    # 窗口内事件伤害（与 _dmg_ts 平行）
var _dmg_sum := 0                # 窗口内伤害和（增量维护，查询 O(1) 摊还）

## _ready() 内追加：
EventBus.damage_dealt.connect(_on_damage_dealt)

func _on_damage_dealt(dmg: int, _pos: Vector2, _is_crit: bool) -> void:
    ## 事件接入点：只做 O(1) 追加 + 惰性剪枝，不做任何 UI 工作
    if dmg <= 0:
        return
    var now := float(run.get("time", 0.0))
    _prune_dps_window(now)
    _dmg_ts.append(now)
    _dmg_val.append(dmg)
    _dmg_sum += dmg
    run["total_damage"] = int(run.get("total_damage", 0)) + dmg  # 整局累计（随存档）

func _prune_dps_window(now: float) -> void:
    ## 剪掉窗口外的旧事件；查询与写入时都调用，摊还 O(1)
    var cutoff := now - DPS_WINDOW_SEC
    var i := 0
    while i < _dmg_ts.size() and _dmg_ts[i] < cutoff:
        _dmg_sum -= _dmg_val[i]
        i += 1
    if i > 0:
        _dmg_ts = _dmg_ts.slice(i)
        _dmg_val = _dmg_val.slice(i)

func measured_dps() -> float:
    ## 实测 DPS：窗口内伤害和 ÷ 窗口时长（5s 固定，稳态精确、空窗归零、无尖峰）。
    ## 冷启动（不满 5s）按实际跨度除，开局即有合理读数。
    if run.is_empty():
        return 0.0
    var now := float(run.get("time", 0.0))
    _prune_dps_window(now)
    if _dmg_ts.is_empty():
        return 0.0
    var span := now - _dmg_ts[0]
    return float(_dmg_sum) / minf(maxf(span, 0.001), DPS_WINDOW_SEC)

func reset_dps_window() -> void:
    ## 新局重置（new_run() 内调用）；窗口数组不落盘
    _dmg_ts.clear()
    _dmg_val.clear()
    _dmg_sum = 0
```

要点：

- **公式**：稳态 = `窗口内伤害和 ÷ 5s`（确定性强，测试可精确断言）；冷启动 `<5s` 除实际跨度避免开局低估；空窗剪空返回 0（"这 5 秒没输出"语义正确）。备选方案是始终除以 5s（更平滑但开局爬坡慢），本轮取前者。
- **时钟选择**：用 `run.time` 而非 Timer 计数——自动跟随暂停（get_tree().paused 时 game_root 不累加）与慢动作（Engine.time_scale 同时作用于 delta 与伤害频率），DPS 数值不随特效抖动。
- **性能**：每次命中 2 次数组追加 + 摊还 O(1) 剪枝；HUD 0.5s 查询一次；无每帧开销。若担心 `slice()` 拷贝（事件极密时），可后续换头索引环形缓冲（容量 4096 上限），本轮不引入。
- **存档兼容**：`run.total_damage` 新增字段，读取用 `get("total_damage", 0)` 兜底旧存档；窗口数组不入存档（瞬时统计，断点续传无需恢复，续传后 5s 内重新爬坡可接受）。
- **契约登记**：`docs/design/data-schema.md` 的 EventBus 表补充 `damage_dealt` 监听方：GameState（统计窗口）＋ 既有 game_root/fx_manager。

### 4.3 HUD 改动（`scripts/ui/game/hud.gd`，Agent U 名下）

```gdscript
func _refresh_dps() -> void:
    if GameState.run.is_empty():
        return
    # 实测：近 5 秒滑动窗口实际伤害（理论值移至构筑面板）
    _dps_label.text = "DPS %d" % int(GameState.measured_dps())
    _dps_label.tooltip_text = "近 5 秒实际输出（构筑面板可查看理论 DPS）"
    _update_shield_display()  # 保留既有兜底
```

0.5s Timer 刷新频率不变；无事件时显示 0（首 0.5s 内可显示 "--" 需额外状态，本轮保持 0 简单化）。

### 4.4 构筑面板改动（`scripts/ui/game/build_panel.gd`，Agent U 名下）

在 `refresh()` 的玩家属性区（`_stats_label`）追加一行：

```gdscript
_stats_label.text += "\n理论 DPS：%d（估算）" % int(GameState.estimate_dps())
```

`estimate_dps()` 保留原实现与注释（它是构筑面板/结算/auto_play 的纸面口径）。

### 4.5 结算页改动（`scripts/ui/game/game_over.gd`，Agent U 名下）

`show_result()` 中：`stats` 即 `GameState.run.duplicate()`（game_root.gd 449/456 行），已含新增的 `total_damage` 与 `time`，直接读取：

```gdscript
var dps_avg := 0.0
if float(stats.get("time", 0.0)) > 0.0:
    dps_avg = float(stats.get("total_damage", 0)) / float(stats["time"])
# 文案：实测均值 DPS + 理论 DPS 并存
```

**game_root.gd 无需改动**（stats 直接透传 run 字典）。

### 4.6 fx_manager 爽感档位（可选，`scripts/fx/fx_manager.gd`，Agent F 名下）

345-352 行 `_dps_tier` 改用 `GameState.measured_dps()`，并给 tier 加最短保持（如 ≥1.5s）避免空窗闪烁。若保守，可暂不改（理论档位在空窗期不会掉档，视觉更稳）。

### 4.7 明确不改的部分

- 不新增 EventBus 信号（`damage_dealt` 已全覆盖）。
- 不改任何战斗/伤害结算代码（projectile/spell_caster/melee/summon/enemy/synergy）。
- 不改 `estimate_dps()` 公式与 `auto_play` 消费端。
- 不动存档结构既有字段（只新增 `total_damage`，读取兜底）。

---

## 5. 改动文件清单

| 文件 | 模块负责人（contracts.md） | 改动内容 |
|---|---|---|
| `scripts/core/game_state.gd` | 主 Agent（核心） | 新增 `DPS_WINDOW_SEC`、`_dmg_ts/_dmg_val/_dmg_sum`、`_on_damage_dealt`、`_prune_dps_window`、`measured_dps()`、`reset_dps_window()`；`_ready` 连接 `damage_dealt`；`new_run()` 重置窗口与 `run.total_damage` |
| `scripts/ui/game/hud.gd` | Agent U | `_refresh_dps()` 改用 `measured_dps()`；tooltip 说明 |
| `scripts/ui/game/build_panel.gd` | Agent U | 玩家属性区追加"理论 DPS"行 |
| `scripts/ui/game/game_over.gd` | Agent U | 结算追加实测均值 DPS，与理论 DPS 并存 |
| `scripts/fx/fx_manager.gd`（可选） | Agent F | 爽感档位改实测 + 最短保持 |
| `docs/design/data-schema.md` | 主 Agent | 契约表登记 `damage_dealt` 新监听方与 `run.total_damage` 字段 |
| `scripts/tests/test_dps_meter.gd` + `.tscn`（新增） | 主 Agent | 见第 6 节测试方案 |

不需要改：`projectile.gd`、`spell_caster.gd`、`melee_attack.gd`、`summon.gd`、`enemy.gd`、全部 synergy、`event_bus.gd`、`game_root.gd`、`auto_play.gd`。

---

## 6. 测试方案（headless 模拟）

环境铁律：只允许 `H:\rougelike_crew\.tools\godot\Godot_v4.7.1-stable_win64_console.exe --headless`；运行前设置临时目录；测试文件写入 `scripts/tests/`（新增，不改旧测试）。

### 6.1 新增 `scripts/tests/test_dps_meter.gd`（场景 `test_dps_meter.tscn`，沿用 test_core_mechanics 的 Node2D+quit 模式）

**T1 窗口纯逻辑测试（不跑战斗，确定性最强）**

```gdscript
# 稳态：每 0.5s 打 100，持续到 t=10 —— 窗口恒含 10 次事件
GameState.new_run()
GameState.run.time = 0.0
for i in 21:                      # t = 0.0, 0.5, ..., 10.0
    GameState.run.time = float(i) * 0.5
    EventBus.damage_dealt.emit(100, Vector2.ZERO, false)
assert_approx(GameState.measured_dps(), 200.0)   # 1000/5s
# 滑空：t 推进到 20，窗口内无事件
GameState.run.time = 20.0
assert GameState.measured_dps() == 0.0
# 冷启动：t=0.5 打 100 → 100/0.5 = 200
# 边界：事件恰好落在 now-5 处应保留（>= cutoff）
```

**T2 端到端施法 ≈ 理论值（headless 模拟战斗）**

- 场景：player（CharacterBody2D 入 group）+ 假敌人（enemy.tscn `setup("slime",1,1)`，speed=0，固定在弹道上）+ `spell_caster.gd` 节点；`crit_chance=0`（沿用 test_core_mechanics 做法固定伤害）。
- 构筑最小化：`run.grid = [{"core":"fireball","shell":""}]`、`run.wands = ["basic_wand"]`、清空 items，使 `estimate_dps()` 只含单核心理论值。
- 跑 ~6.5s 物理帧，期间统计 `damage_dealt` 累计值。
- 断言：
  1. 实测均值（累计 ÷ 6.0）与 `estimate_dps()` 比值落在 `[0.6, 1.4]`（容差覆盖弹道飞行、冷却相位、AOE 落点损失）；
  2. `GameState.measured_dps()` 在稳态后与"累计值 ÷ 5s"一致；
  3. 实例化 hud.tscn（沿用 test_as_display.gd 先例）断言 `_dps_label.text == "DPS %d" % int(GameState.measured_dps())`。

**T3 新局重置**：`new_run()` 后 `measured_dps()==0` 且 `run.total_damage==0`。

**T4 多来源计入**：不跑战斗，直接 `EventBus.damage_dealt.emit` 模拟 DOT tick/反射/附加伤害各若干次，断言全部计入窗口（对应第 3.2 节口径 3/4）。

**T5（可选，验收辅助）**：`--auto-play` 模式下打印 `[AUTOPLAY]` 行时同时输出实测 DPS（auto_play.gd 111-113 行已有 dps 字段，追加 `measured_dps`），人工比对数值合理性。

### 6.2 验收命令

```powershell
$env:TEMP='H:\rougelike_crew\.tmp'; $env:TMP='H:\rougelike_crew\.tmp'; $env:APPDATA='H:\rougelike_crew\.tmp\appdata'
& 'H:\rougelike_crew\.tools\godot\Godot_v4.7.1-stable_win64_console.exe' --headless --path . res://scripts/tests/test_dps_meter.tscn
& 'H:\rougelike_crew\.tools\godot\Godot_v4.7.1-stable_win64_console.exe' --headless --check-only --script res://scripts/core/game_state.gd
& 'H:\rougelike_crew\.tools\godot\Godot_v4.7.1-stable_win64_console.exe' --headless --check-only --script res://scripts/ui/game/hud.gd
```

（Godot 4.7.1 已在本环境验证可用：`--version` → `4.7.1.stable.official.a13da4feb`。）

---

## 7. 风险与取舍

| 风险/取舍 | 说明 | 对策 |
|---|---|---|
| 实测值随波次/敌人密度波动（空窗 0、爆发尖峰） | 这是实测语义的固有特性，也是用户说"估算不准"的根源 | 5s 窗口 + 0.5s 刷新；HUD 文案标明"近 5 秒"；可选 EMA 平滑（alpha≈0.3-0.5）留作后续迭代 |
| 名义伤害口径（护甲前、过杀计入） | 与伤害飘字一致；若按实际扣血需改 take_damage 返回值与 30+ 发射点 | 本轮不做；文档记录后续选项 |
| 灼烧 DOT 未发 damage_dealt → 实测少计灼烧 | enemy.gd 内部结算绕过了事件总线 | 单独立项修复（战斗模块），先在本文档登记缺口 |
| `run.total_damage` 新增存档字段 | 旧存档缺字段 | 读取一律 `get("total_damage", 0)` |
| 窗口时钟与 Timer 语义差异 | 慢动作/暂停下 Timer 与 run.time 行为一致（都被 time_scale/暂停影响），无冲突 | 文档明确时钟用 run.time |
| fx_manager 爽感档位若改实测 | 空窗会掉档闪烁 | 增加 tier 最短保持时间；或暂不改（保守选项） |

---

## 8. 资料来源

### 已在线核验（2026-08-11 抓取，HTTP 200）

1. Godot 4 stable 官方文档《Using signals》（信号解耦、血条响应伤害事件示例）：https://docs.godotengine.org/en/stable/getting_started/step_by_step/signals.html
2. Godot 4 stable 官方文档《Timer》类（周期任务；受 Engine.time_scale 影响；亚 0.05s 定时器建议自写）：https://docs.godotengine.org/en/stable/classes/class_timer.html
3. Risk of Rain Wiki《Damage》页（伤害按单次命中/12 种类型组织，无 DPS 计量概念；雨中冒险伤害模型证据）：https://riskofrain.wiki.gg/wiki/Damage

### 未在线核验（本环境网络受限：fandom / wiki.gg(部分) / steam / github 均不可达，结论基于游戏机制事实与行业通识，建议人工复核）

4. Vampire Survivors Wiki《Damage》页（HUD 无 DPS 计量、暂停面板为构筑乘区、社区理论 DPS 公式）：https://vampire-survivors.fandom.com/wiki/Damage
5. Binding of Isaac Wiki《Damage》页（无游戏内 DPS、每击参数体系、社区理论 DPS 计算器）：https://bindingofisaac.wiki.gg/wiki/Damage
6. Brotato Wiki《Weapons》页（"Display DPS" 选项在武器卡显示理论 DPS）：https://brotato.wiki.gg/wiki/Weapons
7. 行业通识：WoW Details!/Recount 实测滑动窗口 DPS（3-10s 档）；Path of Exile / Diablo 3 角色面板 DPS 为理论值（含暴击期望）。

> 备注：本次调研在线核验受网络限制（本机代理指向无效端口，仅 docs.godotengine.org 与 riskofrain.wiki.gg 可达；fandom 000、其余 wiki.gg 401/403）。第 2.2 节的四款游戏结论为游戏机制事实级信息，与上述 wiki 页面内容一致，风险低；如后续可联网，建议按 4-6 链接复核。

# 批次 A 数据层整理 —— 审计中间态（待主 agent 复核）

> 生成时间：2026-08-13 · 作者：批次 A 执行 agent（尚未改任何代码）

## 一、进展状态

| 任务 | 状态 | 说明 |
|---|---|---|
| 任务1 去重迁移 | 审计完成，未改代码 | 4 组旧 id 全部引用点已定位（见下） |
| 任务2 detect_synergies 12 流派 | 方案已定，未改代码 | 见第三节 |
| 任务3 无效道具审计 | 四通道审计首轮完成 | **0 件全落空**（与“约 28 件”前提不符，见第四节） |
| 测试 | 未运行 | 等复核后执行任务内测试 |

## 二、任务 1：4 组旧 id 引用点清单（全项目 grep 定位）

### 1. stone_armor → defense_bedrock

| 文件:行 | 引用形式 | 处理方案 |
|---|---|---|
| scripts/core/game_state.gd:773 | detect_synergies 硬编码 | 任务2 整体去硬编码时消除 |
| scenes/game/game_root.gd:388-389 | 减伤结算 | 迁移到 defense_bedrock（曲线相同 base 0.06/k 0.06/cap 0.35） |
| scripts/synergies/defense_synergy.gd:415-416 | _dr_total 旧 id 累加 | 删除该行（新 id N1 已有） |
| scripts/ui/game/build_panel.gd:160 | 面板显示 | 迁移 |
| scripts/tests/test_core_mechanics.gd:318 | 测试工具减伤计算 | 迁移 |
| tools/tests/test_curves.py:229-236 | 曲线断言 | 改指 defense_bedrock |

### 2. thorn_reflect → defense_thorn_refit

| 文件:行 | 引用形式 | 处理方案 |
|---|---|---|
| scripts/core/game_state.gd:773 | detect_synergies 硬编码 | 任务2 消除 |
| scenes/game/game_root.gd:395/397/407/412 | 反弹结算（含注释） | 迁移到 defense_thorn_refit，曲线改读数据表（0.30/0.06/0.65） |
| scripts/synergies/defense_synergy.gd:16/359/363-365 | _reflect_pct_old 旧 id 读取 | **关键：合并到 _reflect_pct_new（含 synergy_bonus.defense），删 _reflect_pct_old** |
| scripts/synergies/defense_synergy.gd:392 | _supply_reflect 注释 | 同步改注释/置空 |
| scripts/ui/game/build_panel.gd:163 | 面板显示 | 迁移 |
| scripts/tests/test_core_mechanics.gd:272/316/323 | 反弹测试 | 改用新 id（曲线 30%起） |
| tools/tests/test_curves.py:231/237 | 曲线断言 | 改指 defense_thorn_refit |

### 3. blood_thorn → defense_blood_thorn

| 文件:行 | 引用形式 | 处理方案 |
|---|---|---|
| scripts/core/game_state.gd:774 | detect_synergies 硬编码 | 任务2 消除 |
| scenes/game/game_root.gd:421-424 | 血栗甲吸血 | 迁移到 defense_blood_thorn（曲线 0.02/0.02/cap0.04） |
| tools/tests/test_curves.py:232/238 | 曲线断言 | 改指 defense_blood_thorn |

### 4. summon_book → summon_1

| 文件:行 | 引用形式 | 处理方案 |
|---|---|---|
| scripts/combat/summon.gd:6/180/182 | _enforce_cap 上限 = summon_1+summon_book+1 | 去掉 summon_book，仅留 summon_1+1 |
| scripts/core/game_state.gd:943 | estimate_dps 召唤 DPS | 迁移 |
| scripts/tests/test_core_shell.gd:197 | 测试 | 迁移 |
| scripts/tests/test_summon_ext.gd:21/72 | 测试 | 迁移 |
| scripts/tests/test_summon_fx_crash.gd:41 | 测试 | 迁移 |
| scripts/tests/test_sync_hooks.gd:372/384-386 | 测试 | 迁移 |

注：work/ 、docs/ 下历史报告与注释属历史记录，不迁移（验收标准 = 代码里 0 残留：.gd 生产代码 + 测试 + test_curves.py）。

## 三、任务 2：detect_synergies 12 流派方案

现状：约 763 行，11 条检测（fire/ice/lightning/poison/summon + atk_spd/crit/defense/life/speed/cd），硬编码 stone_armor/thorn_reflect/blood_thorn/vampire_fang 等 id。

目标 12 流派（以 auto_play.gd SCHOOLS 为权威映射，与任务列表一致）：

| 流派 | 道具 tag | 法术核心元素 | 目前 _element_key 可见？ |
|---|---|---|---|
| fire | fire | fire | ✅ |
| ice | ice | ice | ✅ |
| lightning | lightning+thunder | lightning | ✅ |
| poison | poison | poison | ✅ |
| summon | summon | summon | ✅ |
| water | water | water | ✅ |
| wind | wind | nature | ❌ tag wind 不在 _element_key 列表 |
| holy | holy | light | ❌ 同上 |
| curse | curse | 无 | ❌ 同上 |
| melee | blade | blade | ✅ |
| defense | defense | 无 | ❌ 同上 |
| teleport | 无道具 | void | ✅ |

实现方案：
- 只扩展 `_element_holdings()`（不动 `_element_key()`，避免改变 roll_item_choices 池构成、防 test_school_weight 回归）：在原有元素键基础上补 wind/holy/curse/defense 四个纯 tag 流派（按 school_holdings 同口径逐道具 tags 统计），并将核心元素 nature/light/void 映射到流派键。
- detect_synergies 从 `_element_holdings()` 读 12 键，不写死任何道具 id；整体去掉磁血/疾风/冷却的硬编码 id（life/speed/cd 改为 tag 计数，保持原 bonus 语义：max_hp 20 / attack_speed 0.10 / cooldown 0.10）。
- 成型阈值 2 件，bonus 参考现有：fire 0.15 / ice 0.20 / lightning 0.15 / poison 0.25 / summon 0.25 / defense 0.05（现值）；新增 water 0.15 / wind 0.10 / holy 0.15 / curse 0.15 / melee 0.20 / teleport 0.15。
- synergy_bonus 消费点确认保留：aggregate_bonus 加总（game_state.gd:717）、player_aura _strength（fire/ice/lightning/poison/summon/max_hp）、game_root 反弹 defense、apply_item_effects_to_stats max_hp、melee_synergy max_hp、spell_caster cooldown。成型横幅已移除，detect_synergies 仅写 synergy_bonus + 广播。

## 四、任务3 无效道具四通道审计（待复核重点）

### 审计方法
- 对象：items.json 297 件道具；扫描 scripts/ + scenes/ 生产代码（剔除 scripts/tests 与注释）。
- 通道1 字面引用：total_stacks("id") / item_def("id") / _stacks("id") / _curve_value("id") / run.items["id"] / const X := "id"
- 通道2 synergy 常量：const Nx := "id"（defense/fire/curse/crit/holy/melee/wind/water 等）
- 通道3 tag 聚合：aggregate_bonus("tag") 静态调用点 + spell_caster._spell_damage 动态 aggregate_bonus(element)（fire/ice/lightning/poison/summon/water/blade/nature/light/void）+ apply_item_effects_to_stats 的 hp/max_hp 遍历
- 通道4 前缀遍历：crit_/curse_/ice_/melee_/poison_/summon_/thunder_/water_/wind_ （begins_with / PREFIX 常量）

### 结论：**0 件四通道全落空**。暂无需标 disabled 的道具。

主要证据（合规道具示例）：
- 元素 tag 经 spell_caster `dmg *= 1.0 + aggregate_bonus(element)` 被实际消费（历史审计文档明确记录：“冰1 经 tag ice 聚合已在 _spell_damage 生效 +10%/层”）。
- 冰1/召1/trinket_ember 等历史孤儿项已被 08-10 接线轮（sync_hooks + mech_fill_batch）消费：召1 接入 summon.gd 上限、trinket 三件套经 run.trinkets 槽位 + mech_items 消费、暴击 6 机制补道具、移速 5 读取点接线。
- 检查过的边界项均有消费：如 wand_expander（run.trinkets max_wand_slots:532 + defense tag）、melee_giant_cleaver（atk tag + melee_ 前缀）、holy_6/holy_8（attack_speed/cooldown tag）、summon_war_banner 等（summon_ 前缀）。

### 与“约 28 件”前提的差异分析（需主 agent 决裁）

1. 仓库内未找到批次 A 任务文档或 28 件原始清单（检索 docs/ work/ 均无）。
2. 历史审计《流派机制缺口审计》（08-10）标注的孤儿项在 08-10/08-12 接线轮后均已有消费点（该文档第 5/6 节记录“全部已修”）。
3. “不在任何流派 build_defs”视角 = 98 件（build_defs 本身滞后，含大量已消费条目，不可作为依据）。
4. 如主 agent 手上有 28 件原始清单，请提供以便逐项核对；无清单时，按任务自带四通道规则执行 = 0 件标 disabled（保留条目）。

### 附带发现（非四通道范围，但属“抽到=空抽”，请主 agent 决裁）

4 件 type=trinket 道具（trinket_ember/trinket_frost/trinket_storm/wand_expander）在 roll_item_choices 升级池中：被选中后 game_root._on_choice_made → add_item（进 run.items），而效果读取 run.trinkets → **空抽**。建议后续在池筛选排除 type=trinket 或 _on_choice_made 分流（不在本批范围）。

## 五、下一步

1. 主 agent 复核四通道审计结论（0 件 disabled）。
2. 复核通过后：执行任务1 迁移 + 任务2 改写 + roll_item_choices 加 disabled 过滤（空集也加，防未来数据回归）+ 写 test_data_dedup.py / test_no_dead_items.gd + 回归测试。


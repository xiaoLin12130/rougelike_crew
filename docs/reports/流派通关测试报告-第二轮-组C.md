# 流派通关测试报告-第二轮-组C（melee / summon / defense / teleport）

> 生成时间：2026-08-12 22:20
> 测试方式：Godot 4.7.1 console + `--headless`（H:\rougelike_crew\.tools\godot\Godot_v4.7.1-stable_win64_console.exe），`auto_play.gd` 驱动，`--school <name>` 指定流派倾向
> 执行命令：`python tools/tests/run_school_tests.py --school melee,summon,defense,teleport --runs 2 --csv school_test_results_c.csv --max-minutes 25`
> 数据文件：`tools/tests/school_test_results_c.csv`；逐局日志：`tools/tests/logs/<school>_0N.log`（第一轮同名日志已备份至 `tools/tests/logs/round1_backup/`）
> 环境：TEMP/TMP/APPDATA 均指向 `H:\rougelike_crew\.tmp`；每局前脚本自动 taskkill GUI 版 Godot（保留）

## 一、本轮结果总览（组C：每流派 2 局）

| 流派 | 局数 | 通关 | 通关率 | 用时(游戏s) | 击杀 | 等级 | 剩余HP | 金币 | 最大波次 | DPS峰值 | 道具数 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| melee(近战) | 2 | 0 | 0% | 137 / 156 | 697 / 293 | 12 / 8 | 0 | 223 / 184 | 3 | 52 / 34 | 7 / 3 |
| summon(召唤) | 2 | 0 | 0% | 449 / 430 | 2646 / 2971 | 25 / 27 | 0 | 222 / 114 | 3 | 335 / 553 | 18 / 17 |
| defense(防御) | 2 | 0 | 0% | 133 / 126 | 647 / 596 | 11 / 11 | 0 | 62 / 166 | 3 | 27 / 107 | 7 / 3 |
| teleport(传送) | 2 | 0 | 0% | 145 / 166 | 802 / 809 | 12 / 12 | 0 | 134 / 86 | 3 | 45 / 20 | 6 / 7 |

### 逐局明细

| 流派 | 局 | 结果 | 游戏s | 墙钟s | 击杀 | 等级 | HP | 金币 | 波次 | DPS | 道具 | 终局法术网格 | 终局道具(节选) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| melee | 1 | DEFEAT | 137 | 30 | 697 | 12 | 0/215 | 223 | 3 | 52 | 7 | poison_cloud×3, ice_shard+spread | poison_m5/m9/m8/m10, poison_bug_egg, crit_weak_mark |
| melee | 2 | DEFEAT | 156 | 19 | 293 | 8 | 0/175 | 184 | 3 | 34 | 3 | whirl_blade×2, counterspell×3 | crit_executioner, bounce_mirror, defense_shield_counter |
| summon | 1 | DEFEAT | 449 | 135 | 2646 | 25 | 0/345 | 222 | 3 | 335 | 18 | lightning×5 | thunder_m2/m5, summon_8, trinket_storm, curse_rack |
| summon | 2 | DEFEAT | 430 | 407 | 2971 | 27 | 0/365 | 114 | 3 | 553 | 17 | inferno×2, fireball×3 | summon_9/7/3, fire_volcano_core, fire_forge_heart |
| defense | 1 | DEFEAT | 133 | 40 | 647 | 11 | 0/205 | 62 | 3 | 27 | 7 | thorn_vine×4, teleport+burst | stone_armor, defense_blood_thorn, crit_crit_storm |
| defense | 2 | DEFEAT | 126 | 14 | 596 | 11 | 0/205 | 166 | 3 | 107 | 3 | inferno×2, fireball×3 | trinket_ember×2, defense_shield_counter |
| teleport | 1 | DEFEAT | 145 | 49 | 802 | 12 | 0/215 | 134 | 3 | 45 | 6 | thorn_vine×5 | holy_8, crit_m3, life_crystal, curse_weak_strike, ice_3, strength_badge |
| teleport | 2 | DEFEAT | 166 | 25 | 809 | 12 | 0/215 | 86 | 3 | 20 | 7 | teleport×2, poison_cloud×2, counterspell | wind_hunter, summon_m2, poison_ramp/pierce/cd/plague_touch/spore |

说明：8 局全部在最终波次（wave 3）阵亡（hp=0），无超时、无卡死、无脚本解析错误（tainted=0）；全部 exit_code=1（DEFEAT）。

## 二、与第一轮对比

第一轮基线（`tools/tests/school_test_results.csv`，每组 3 局）：melee 33%、summon 100%、defense 100%、teleport 33%。

| 流派 | 第一轮 | 第二轮(组C) | 变化 | 结论 |
| --- | --- | --- | --- | --- |
| melee(近战) | 33%（1/3，另含 1 局 1500s 超时） | 0%（0/2） | 33% → 0% | 未改善，反而更差（样本小，趋势恶化） |
| summon(召唤) | 100%（3/3） | 0%（0/2） | 100% → 0% | 未保持，明显退化 |
| defense(防御) | 100%（3/3） | 0%（0/2） | 100% → 0% | 明显退化 |
| teleport(传送) | 33%（1/3） | 0%（0/2） | 33% → 0% | 未改善；0 道具问题仍存在 |

### 逐项分析

1. **melee 33% 是否改善**：否。两局均在 137/156 游戏秒（wall 30/19s）速败，DPS 峰值仅 52/34（第一轮 DPS 130~187 区间内也是垫底），道具 7/3 个。第 2 局仅 3 件道具、等级 8。近战依赖的 blade 法术两局只出现在 melee_02 的 whirl_blade，终局构筑里 melee 系道具比例低（crit/bounce 为主），输出不足问题依旧。
2. **summon 100% 是否保持**：否。虽然两局都撑到 430/449 秒、击杀 2646/2971、等级 25/27、DPS 335/553，与第一轮获胜局（424/419/961s，DPS 96~1170）数据相当甚至更好，但都在最终波次倒下。注意两局终局网格均为其他系（lightning×5 / inferno+fireball×5），召唤元素法术未成型；召唤道具虽有（summon_8/9/7/3、summon_m2），但未能转化为召唤法术网格，与第一轮"召唤成型即通关"的形态不符。
3. **defense 100% 变化**：大幅下滑。两局 126/133 秒速败，是组内最短的两局；DPS 27/107 组内垫底，道具仅 7/3 件，金币 62/166 也低。防御系"拖时间成型"路线在当前强度下失效（血线 205，第一轮获胜局剩余 HP 305~365、金币 742~852，差距悬殊）。第 1 局拿到 stone_armor/defense_blood_thorn 仍未能撑住。
4. **teleport 33% + 0 道具问题是否仍存在**：是，且更差。两局 145/166 秒速败（第一轮至少撑到 470~504s），道具 6/7 件中 **0 件 teleport 系道具**（teleport_01 全为 holy/crit/life/curse/ice/strength 杂项；teleport_02 全为 wind/summon/poison 系）——`items.json` 中 teleport tag/前缀道具为 0 的问题原样保留。teleport_02 的 void 法术（teleport+drain/teleport+burst）是仅有的流派倾向生效痕迹，但 2 个 void 法术不足以支撑输出（DPS 20 组内最低）。

## 三、游玩体验反馈

- **整体难度明显高于第一轮**：组内 4 个流派 8 局 0 胜，且此前 100% 的 summon/defense 也全灭，提示测试间隔期间游戏数值/敌人强度有全局性调整（或 auto_play 决策权重变化），并非单一流派问题。所有局都死在最终波次，说明中后期强度门槛提高。
- **流派倾向生效不稳定**：summon 两局 18/17 件道具中召唤道具占比不高（约 4~5 件），终局网格 0 召唤法术；defense_02/teleport_01 的终局网格完全被其他系（fire/nature）占据，`--school` 加权未能稳定引导成型。
- **道具获取量波动大**：同流派两局道具数 3 vs 7（melee）、3 vs 7（defense），低道具局（3 件）全部速败，道具数量与存活时长强相关。
- **teleport 体验最差**：无流派道具支撑 + 0~2 个 void 法术 + DPS 20~45 组内垫底，玩法上"传送流"实际仍是"随机杂牌流"。

## 四、建议（承接第一轮报告，问题均未解决）

1. `items.json` 补 melee/teleport（及 ice/summon 部分）流派 tag/前缀道具，尤其 teleport 系为 0。
2. `--school` 倾向需要保证对应元素法术进入 offer 池/开局核心（第一轮已提，未见改动迹象）。
3. 全局强度回归：summon/defense 从 100% 跌至 0%，需核对本轮与上轮之间的数值改动。

## 五、备注

- 本轮无 STUCK/TIMEOUT/tainted 局，数据完整（8/8）。
- 第一轮同名日志（melee_01~02、summon_01~02、defense_01~02、teleport_01~02）已复制到 `tools/tests/logs/round1_backup/` 以免被本轮覆盖。

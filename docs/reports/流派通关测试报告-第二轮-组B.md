# 流派通关测试报告-第二轮-组B

> 生成时间：2026-08-12
> 测试方式：Godot 4.7.1 console + `--headless --fixed-fps 60`，`auto_play.gd --school <name>` 驱动（流派道具 +150 / 法术核心 +120 加权）
> 执行命令：`run_school_tests.py --school water,wind,holy,curse --runs 2 --csv school_test_results_b.csv --max-minutes 25`
> 数据文件：`tools/tests/school_test_results_b.csv`；日志：`tools/tests/logs/{water,wind,holy,curse}_{01,02}.log`
> 说明：`--report` 生成器硬编码读共享 CSV，故本报告由组 B 直接汇总本轮 CSV 生成。

## 一、测试概况

本轮（第二轮）组 B 覆盖 4 流派 × 2 局 = 8 局，脚本连续执行，无 STUCK/TIMEOUT，8 局全部正常出结果（2 胜 6 负）。
headless 全速下每局墙钟仅 19~237 秒（游戏内时长 98~594 秒），整批约 8.5 分钟跑完；单局未触发 25 分钟上限。

## 二、每流派数据（第二轮，每流派 2 局）

### 流水 (water)：1/2 胜

| 局 | 结果 | 游戏用时 | 击杀 | 等级 | 剩余HP | 金币 | 最大波次 | DPS峰值 | 道具数 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | DEFEAT | 141s | 790 | 12 | 0 | 221 | 3 | 120 | 4 |
| 2 | VICTORY | 594s | 1109 | 20 | 285 | 770 | 3 | 88 | 11 |

- **第 1 局（DEFEAT）** 构筑：法术网格 `[flash+spread, summon_bat+burst, whirl_blade+rapid, whirl_blade+spread, whirl_blade+burst]`；道具 `melee_m7x1, melee_2x2, melee_m6x2, melee_m9x1`；法杖 `["basic_wand"]`
- **第 2 局（VICTORY）** 构筑：法术网格 `[thorn_vine+spread, whirl_blade+drain, whirl_blade+burst, whirl_blade+spread, whirl_blade+burst]`；道具 `melee_3x1, melee_m6x3, melee_m9x1, crit_m9x1, melee_giant_cleaverx1, crit_weak_markx1, melee_2x1, melee_9x1, wind_typhoon_eyex1, summon_m5x1, melee_10x1`；法杖 `["basic_wand", "fire_staff", "shield_staff"]`

### 疾风 (wind)：0/2 胜

| 局 | 结果 | 游戏用时 | 击杀 | 等级 | 剩余HP | 金币 | 最大波次 | DPS峰值 | 道具数 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | DEFEAT | 178s | 899 | 14 | 0 | 495 | 3 | 75 | 8 |
| 2 | DEFEAT | 98s | 2945 | 19 | 0 | 451 | 3 | 140 | 15 |

- **第 1 局（DEFEAT）** 构筑：法术网格 `[lightning+split, inferno+drain, lightning+burst, fireball+pierce, inferno+spread]`；道具 `thunder_m5x1, water_conductx1, crit_m9x1, wind_domainx1, thunder_m3x1, thunder_7x1, crit_m7x2, thunder_m4x1`；法杖 `["basic_wand"]`
- **第 2 局（DEFEAT）** 构筑：法术网格 `[whirl_blade+spread, fireball+burst, fireball+bounce, fireball+pierce, fireball+split]`；道具 `fire_dragon_breathx1, ice_m2x1, fire_source_crystalx1, melee_m1x1, crit_m4x1, wind_featherx1, trinket_emberx1, wind_grimoirex1, attack_speed_potionx1, curse_agony_loopx1, iron_ringx1, curse_ringx1, crit_staffx1, fire_ash_bringerx1, fire_pyromaniacx1`；法杖 `["basic_wand", "thorn_staff"]`

### 圣光 (holy)：0/2 胜

| 局 | 结果 | 游戏用时 | 击杀 | 等级 | 剩余HP | 金币 | 最大波次 | DPS峰值 | 道具数 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | DEFEAT | 491s | 1734 | 22 | 0 | 20 | 3 | 145 | 14 |
| 2 | DEFEAT | 181s | 831 | 12 | 0 | 168 | 3 | 430 | 6 |

- **第 1 局（DEFEAT）** 构筑：法术网格 `[lightning+burst, lightning+rapid, lightning+rapid, lightning+drain, lightning+spread]`；道具 `holy_10x1, ice_m1x1, crit_m3x1, holy_6x1, crit_m9x1, thunder_m4x1, storm_cloudx1, thunder_8x2, trinket_stormx1, thunder_1x1, holy_m6x1, thunder_m1x1, thunder_m8x1, thunder_m10x1`；法杖 `["basic_wand"]`
- **第 2 局（DEFEAT）** 构筑：法术网格 `[summon_bat+rapid, summon_bat+rapid, summon_bat+burst, whirl_blade+rapid, whirl_blade+spread]`；道具 `holy_3x1, crit_m4x1, summon_bookx1, stone_armorx1, summon_war_bannerx1, summon_2x1`；法杖 `["basic_wand"]`

### 诅咒 (curse)：0/2 胜

| 局 | 结果 | 游戏用时 | 击杀 | 等级 | 剩余HP | 金币 | 最大波次 | DPS峰值 | 道具数 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | DEFEAT | 136s | 698 | 12 | 0 | 283 | 3 | 79 | 5 |
| 2 | DEFEAT | 118s | 628 | 11 | 0 | 180 | 3 | 94 | 5 |

- **第 1 局（DEFEAT）** 构筑：法术网格 `[fireball+rapid, fireball+bounce, fireball+pierce, inferno+spread, fireball+burst]`；道具 `curse_fearx1, fire_heat_corex2, water_boilx1, fire_prismx1, curse_no_heal_zonex1`；法杖 `["basic_wand"]`
- **第 2 局（DEFEAT）** 构筑：法术网格 `[fireball+spread, fireball+pierce, fireball+pierce, fireball+pierce, inferno+rapid]`；道具 `crit_m9x1, curse_no_heal_zonex2, crit_crit_stormx1, curse_rackx1, fire_attack_potionx1`；法杖 `["basic_wand"]`

## 三、与第一轮对比

第一轮数据源：`tools/tests/school_test_results.csv`（每流派 3 局）与《流派通关测试报告.md》。

| 流派 | 第一轮通关率(3局) | 第二轮通关率(2局) | 变化 | 关键观察 |
| --- | --- | --- | --- | --- |
| water(流水) | 0% (0/3) | 50% (1/2) | 上升 | 首胜！第2局长局成型(594s)险胜，第1局仍是4道具速死 |
| wind(疾风) | 100% (3/3) | 0% (0/2) | 大幅下滑 | 两局均败：178s/98s 崩盘，未保持第一轮全胜 |
| holy(圣光) | 67% (2/3) | 0% (0/2) | 下滑 | 第1局撑满491s但金币仅20（经济崩）；第2局181s速死 |
| curse(诅咒) | 33% (1/3) | 0% (0/2) | 下滑 | 两局118~136s早死，与第一轮前两局(108/140s)同模式，仅靠天胡局可赢 |

四流派合计：第一轮 6/12 = 50% → 第二轮 2/8 = 25%（组 B 样本）。两局样本量小、波动大，wind 从 3 连胜跌到 0 胜即为典型波动，需结合组 A/C 数据与更多局数综合判断。

## 四、构筑组成分析

按 items.json 的 tag 统计本流派道具占比（id 前缀不含 tag 的不计）：

| 流派 | 本流派道具占比 | 主要实际构成 | 法术网格核心元素 |
| --- | --- | --- | --- |
| water(流水) | 0/15 (0%) | melee 9、crit 2、wind 1、summon 1、water 0 | 旋风刃×6、藤蔓×1、闪身×1、蝙蝠×1 —— 0 个水核心 |
| wind(疾风) | 3/23 (13%) | fire 6、thunder 5、crit 4、wind 3、ice 1、curse 2、melee 1 | 火球×6、闪电×3、旋风刃×2、地狱火×3、火雨×2 —— 0 个风核心 |
| holy(圣光) | 4/20 (20%) | thunder 8、holy 4、crit 3、summon 2、ice 1 | 闪电×5、蝙蝠×3、旋风刃×2 —— 0 个光核心 |
| curse(诅咒) | 4/10 (40%) | curse 4、fire 3、crit 3 | 火球×8、地狱火×2 —— 0 个暗核心 |

结论与第一轮一致：**元素门控问题依旧**。8 局里没有任何一局在法术网格上拿到本流派核心（水/风/光/暗核心全部缺失），
非火系流派成型的法术完全依赖 fireball/whirl_blade/lightning 等通用核心。胜局（water #2）靠的是 11 道具 + 3 法杖的装备厚度而非流派法术。

## 五、游玩体验反馈（升级节奏 / 成型体感 / 难度）

### 升级节奏（来自日志心跳）

| 流派局 | t=60s 等级 | t=120s 等级 | 波次节奏 | 终局等级 |
| --- | --- | --- | --- | --- |
| water#1 | 9 | 11 | 波2@25s、波3@45s | 12（败于141s） |
| water#2 | 4 | 8 | 波2@25s、波3@45s | 20（胜，594s） |
| wind#1 | 9 | 12 | 波2@25s、波3@45s | 14（败于178s） |
| wind#2 | 17 | 19 | 波2@25s、波3@45s | 19（败于98s） |
| holy#1 | 8 | 11 | 波2@25s、波3@45s | 22（败于491s） |
| holy#2 | 7 | 10 | 波2@25s、波3@45s | 12（败于181s） |
| curse#1 | 9 | 12 | 波2@25s、波3@45s | 12（败于136s） |
| curse#2 | 8 | 11 | 波2@25s、波3@45s | 11（败于118s） |

前期升级极快（前 25 秒过波 2 时普遍 lv4~8），中后期变缓：能活过 400s 的局（water#2、holy#1）等级继续涨到 19~22，
而 100~180s 崩盘的局都停在 lv11~14。升级快慢不决定胜负，**决定胜负的是装备/法杖有没有跟上波次强度**。

### 成型体感

- 胜局 water#2：约 600s 内完成 5 法术网格 + 11 道具 + 3 法杖（basic/fire/shield），成型后剩余 285/285 HP 通关，体感「拖得住就能赢」。
- 败局普遍 4~8 道具、仅 1 根 basic_wand，DPS 峰值 75~430 不等；wind#2 击杀 2945 但 98s 暴毙——伤害足、生存不足（0 回复、0 护甲类道具）。
- 本流派法术核心 8 局零出现，流派倾向（+150/+120 加权）只影响了道具拾取偏好（holy/curse 有少量本系道具），无法解决元素门控。

### 难度

- 8 局全部打到最终波次 3，内容本身可通；但「非火系无本系核心 + 道具池偏向 melee/fire/thunder」下，多数局在波 3 中段被数值压死。
- 金币波动大（20~770）：holy#1 打满 491s 却只剩 20 金币，说明死亡局后期经济崩坏（反复死亡扣钱/无法买装）；胜局金币 770 形成正循环。
- 相对第一轮：wind 的 3 连胜未能复现，大概率是随机性主导（元素门控下 wind 和其他非火系一样看通用法术脸色）；curse 依旧稳定弱势（两次 110~140s 早死）。

## 六、备注

- 无 STUCK/TIMEOUT/脚本报错；日志中的 `Failed to read the root certificate store` 与 RID leak 为 headless 退出时的无害噪音。
- 本轮与组 A（fire,ice,lightning,poison）、组 C（melee,summon,defense,teleport）并行执行；组 B 使用独立 CSV `school_test_results_b.csv`，未写入共享 CSV。
- 改动：未修改任何游戏代码/数据；`run_school_tests.py` 的 `--csv` 参数由并行代理添加，组 B 直接复用（默认值行为不变）。

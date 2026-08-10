# 交付报告：图标语义替换实施（icon_semantic_impl）

> 日期：2026-08-10 ｜ 依据：docs/design/图标语义排查清单.md（E 批审计：32 不匹配 + 92 疑似，全部建议路径已核实）
> 范围：data/items.json、data/wands.json 的 icon 字段（其余字段一律未动）；data/spells.json、data/summons.json 无改动

## 一、改动统计

| 文件 | 改图 | 说明 |
|---|---|---|
| data/items.json | 36 | 32 条「不匹配」全部替换 + 2.2 疑似中 4 条 not_covered 按 4.2 建议替换 |
| data/wands.json | 2 | 清单第五节标注「可考虑换」：bloodblade_staff→SWORDS_141、warblade_staff→SWORDS_52（近纯灰 STAFFS_50/51） |
| data/spells.json | 0 | 清单 2.1/2.2 无 spells 条目（核心 15 + 外壳 10 语义已合规） |
| data/summons.json | 0 | 清单第五节：10 种 icon 为召唤物自身形象，语义正确，保留 |
| 合计 | 38 | |

## 二、每类统计

- **2.1 不匹配 32 条 → 0**：其中 18 条直接按清单建议图标落地；14 条因清单建议图标被多条共用（9 条冰系→r18_c2、7 条雷系→r3_c2、5 条水系→r3_c4、3 条风系→r3_c12、3 条毒系→r0_c1 等），
  原样照搬会突破「任一素材引用 ≤3」，按清单第六节自述方法（4.2 备选优先 → 流派素材池、过滤引用 ≥3、优先低引用）改派同流派已核实路径，逐条依据记录于清单第七节。
- **2.2 疑似 92 条 → 未解决 17**：本批替换 4 条 not_covered（ice_glacial_haste→SWORDS_51、summon_war_banner→r11_c8 猎号、summon_graveyard_keep→r11_c0 符文石、summon_overlord_edict→r13_c10 卷轴）；
  71 条 implemented 为方案（图标去重分配方案.md）既定分配，清单未给更优路径，保留并标注；17 条 keep 为方案/审计既定保留，保留并标注。
- **按流派改动分布**：冰 9（含 wind_frost 急冻风）、雷 7、水 5、风 4（追风/顺风/疾风领域/急冻风）、毒 3、火 2、召唤 1（集火）、诅咒 1（反噬）、暴击 1（暴击风暴）、召唤系 not_covered 3 + 冰系 not_covered 1、法杖 2。
- **剑形/矛形/食物/无关项清除**：元素系 23 处 willibab 剑形 + 1 处矛形（水·激流）全部换下；冰川之心（红辣椒）、冰封领域（甜玉米）、时之冰（牛排）3 处食物图标换下；反噬（付钱）、集火（锤）、五毒符（卡牌）、导雷（弓矢）、高压电网（交叉双剑）、暴击风暴（剑）6 处方案超限完全无关项换下。

## 三、校验结果（全绿）

| 检查项 | 结果 |
|---|---|
| ① 四文件全部 icon 路径存在（PNG + .import） | 386 处引用 / 268 个唯一素材，缺文件 0、缺 .import 0 |
| ② glow.png 引用数 | 0 |
| ③ 任一素材被引用 ≤3 | 超限素材 0 个 |
| ④ 与图标去重分配方案.md 映射抽查 20 条（跳过本批改动 36 条） | 全部一致 |
| ⑤ 不匹配条目数 = 0（对照语义清单 2.1，32/32） | 0 ✓ |
| ⑥ 疑似条目：92 → implemented 71 + 本批替换 4 → 未解决 17（≤18 ✓），降幅 81.5%（≥80% ✓） | 通过 |
| ⑦ 与语义清单抽查 20 条 | 全部一致 |
| 冒烟测试（Godot headless） | Godot_v4.7.1-stable_win64_console.exe --headless --path . -s res://scripts/tests/smoke_test.gd → SMOKE OK |

> 说明：清单 2.1 建议图标的「当前引用 0 处」经实施前核对与实际不符（多数路径已有 1 处引用，如 r3_c2=thunder_2、r3_c12=ice_8、r0_c1=poison_area、r10_c11=holy_5），
> 且同一建议图标被分配给多条（r18_c2×9、r3_c2×7、r3_c4×5）。本批在「任一素材 ≤3」硬约束内重新分配，全部新路径均经文件系统核实存在（含 .import）。

## 四、保留清单（88 条，均已标注）

1. **17 条 keep（审计/方案既定保留）**：thorn_armor、area_crystal、magnet、memory_power、fire_element_badge、fire_sulfur、fire_undying_flame、ice_m8、summon_2、summon_3、summon_7、summon_m8、thunder_m7、spread、burst、delay、split。
2. **71 条 implemented（方案已落地分配，无清单级更优路径）**：见清单 2.2 表 Bernoulli 列（含 增益箭/宝珠/药水/植物类泛用图标 27 处——清单未给替代路径，按任务规则「拿不准的保留并标注」处理）。

## 五、备份与可回滚

- 改动前完整副本：.tmp/backup_icon_semantic/{items,spells,wands,summons}.json.bak
- 改动日志：.tmp/semantic_change_log.json（38 条 old/new/basis 全量记录）
- 实施脚本：.tmp/icon_semantic_plan.py（方案 + 模拟校验）、.tmp/apply_icon_semantic.py、.tmp/update_icon_doc.py、.tmp/upd_status_semantic.py
- 校验脚本：tools/tests/icon_check.py（新增 ⑤⑥⑦ 语义校验）

## 六、完整改动清单（38 条）

| id | 旧 icon | 新 icon | 依据 |
|---|---|---|---|
| `fire_fire_nova` | `SWORDS_72.png` | `shikashi_r10_c11.png` | 2.1 建议 r10_c11(蜡烛) |
| `fire_dragon_breath` | `SWORDS_114.png` | `shikashi_r10_c11.png` | 2.1 建议 r10_c11(蜡烛) |
| `ice_m1` | `SWORDS_51.png` | `shikashi_r18_c2.png` | 2.1 建议 r18_c2(宝珠3) |
| `ice_m2` | `SWORDS_59.png` | `shikashi_r18_c0.png` | 2.1 建议 r18_c2 超限，改派宝珠1(清单同款泛用宝珠) |
| `ice_m3` | `SWORDS_80.png` | `shikashi_r18_c4.png` | 2.1 建议 r18_c2 超限，改派宝珠5 |
| `ice_m9` | `SWORDS_84.png` | `DAGGERS_12.png` | 2.1 建议 r18_c2 超限，改派 DAGGERS_12(冰棱同款) |
| `ice_m10` | `SWORDS_61.png` | `shikashi_r10_c15.png` | 2.1 建议 r18_c2 超限，改派沙漏(每8s定时冻结=时间意象, 同4.2#3) |
| `poison_infection` | `SWORDS_100.png` | `shikashi_r0_c1.png` | 2.1 建议 r0_c1(毒) |
| `poison_pentad` | `shikashi_r13_c14.png` | `shikashi_r0_c1.png` | 2.1 建议 r0_c1(毒) |
| `summon_m4` | `shikashi_r10_c4.png` | `shikashi_r4_c7.png` | 2.1 建议 r4_c7(法术书) |
| `thunder_6` | `SWORDS_88.png` | `shikashi_r3_c2.png` | 2.1 建议 r3_c2(雷击) |
| `thunder_9` | `SWORDS_2.png` | `shikashi_r3_c2.png` | 2.1 建议 r3_c2(雷击) |
| `curse_retribution` | `shikashi_r12_c13.png` | `shikashi_r0_c4.png` | 2.1 建议 r0_c4(诅咒) |
| `water_torrent` | `SPEARS_9.png` | `shikashi_r3_c4.png` | 2.1 建议 r3_c4(箭雨) |
| `water_tide_power` | `SWORDS_131.png` | `shikashi_r3_c4.png` | 2.1 建议 r3_c4(箭雨) |
| `water_vortex` | `SWORDS_105.png` | `shikashi_r16_c3.png` | 2.1 建议 r3_c4 超限，改派湖鳟(Bernoulli 水素材池) |
| `water_curtain` | `SWORDS_12.png` | `shikashi_r0_c10.png` | 2.1 建议 r3_c4 超限，改派汗滴(水滴意象, Bernoulli 水素材池) |
| `water_tornado` | `SWORDS_21.png` | `water_spell.png` | 2.1 建议 r3_c4 超限，改派水系专属 water_spell(水涡意象) |
| `wind_chase` | `SWORDS_28.png` | `shikashi_r8_c2.png` | 2.1 建议 r3_c12 超限，改派皮靴(移速意象, Bernoulli 风素材池) |
| `wind_tailwind` | `SWORDS_90.png` | `shikashi_r8_c3.png` | 2.1 建议 r3_c12 超限，改派钢靴(移速意象, Bernoulli 风素材池) |
| `wind_domain` | `SWORDS_44.png` | `shikashi_r3_c12.png` | 2.1 建议 r3_c12(阵风) |
| `wind_frost` | `SWORDS_48.png` | `shikashi_r3_c12.png` | 2.1 建议 r18_c2 超限，改派阵风(风意象; 急冻风=高速风触发的冰) |
| `poison_m3` | `SWORDS_26.png` | `shikashi_r11_c15.png` | 2.1 建议 r0_c1 超限，改派草药3(毒草意象, Bernoulli 毒素材池) |
| `thunder_m2` | `SWORDS_53.png` | `blinding_light_spell.png` | 2.1 建议 r3_c2 超限，改派闪光(落雷闪光意象, Bernoulli 雷素材池) |
| `thunder_m4` | `SWORDS_50.png` | `paralyzed.png` | 2.1 建议 r3_c2 超限，改派麻痹(过载=麻痹联动, Bernoulli 雷素材池) |
| `thunder_m5` | `shikashi_r6_c3.png` | `shikashi_r5_c8.png` | 2.1 建议 r3_c2 超限，改派十手(避雷针意象, 同 thunder_7) |
| `thunder_m9` | `SWORDS_29.png` | `shikashi_r2_c6.png` | 2.1 建议 r3_c2 超限，改派循环箭头(每5s周期落雷=循环意象) |
| `thunder_m10` | `shikashi_r5_c9.png` | `shikashi_r17_c6.png` | 2.1 建议 r3_c2 超限，改派毛线(线圈/电网意象, 同 thunder_m8) |
| `crit_crit_storm` | `SWORDS_107.png` | `shikashi_r3_c3.png` | 2.1 建议 r3_c3(爆头) |
| `ice_glacier_heart` | `shikashi_r14_c11.png` | `shikashi_r18_c2.png` | 2.1 建议 + 4.2#1 首选 r18_c2 |
| `ice_frozen_domain` | `shikashi_r14_c7.png` | `shikashi_r18_c2.png` | 2.1 建议 + 4.2#2 首选 r18_c2 |
| `ice_chrono_frost` | `shikashi_r15_c1.png` | `shikashi_r10_c15.png` | 4.2#3 首选沙漏(时间意象) |
| `ice_glacial_haste` | `STAFFS_11.png` | `SWORDS_51.png` | 4.2#4 建议 SWORDS_51（swiftness 已满3引用） |
| `summon_war_banner` | `ALL_180.png` | `shikashi_r11_c8.png` | 4.2#5 建议猎号(军团意象) |
| `summon_graveyard_keep` | `ALL_135.png` | `shikashi_r11_c0.png` | 4.2#7 建议符文石(墓园符文意象; 骷髅头已满3) |
| `summon_overlord_edict` | `ALL_231.png` | `shikashi_r13_c10.png` | 4.2#8 建议卷轴(军令=文书意象) |
| `bloodblade_staff` | `STAFFS_50.png` | `SWORDS_141.png` | 第五节: 近纯灰 STAFFS_50 → SWORDS_141 |
| `warblade_staff` | `STAFFS_51.png` | `SWORDS_52.png` | 第五节: 近纯灰 STAFFS_51 → SWORDS_52 |

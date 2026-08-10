# 交付报告：地面效果视觉实体化（ground_fx_visual）

日期：2026-08-10　状态：done　验收：test_ground_fx ALL PASS + smoke SMOKE OK

## 背景

用户反馈"火系、水系留下的火地、水地视觉上完全没有体现"。排查确认：
火M10 龙息火地只是纯数值字典（`_zones`，无任何可见节点）；水 M1 水泽虽然有
`WaterZone` 节点但只有伤害/减速逻辑、没有 _draw 视觉；毒 M3 毒雾弥漫只有状态
扩散；冰 M7 雪迹 SlowZone 无视觉；雷 M9 雷云风暴只有一次性落雷爆点；boss
GroundZone 只有一个淡红色圆。全部地面/区域持续效果都"看不见"。

## 每种地面效果的视觉方案（改动前后对比）

| 效果 | 改动前 | 改动后（可见视觉） |
| --- | --- | --- |
| 火地（火M10 龙息） | 无任何节点，纯数值伤害圈 | GroundFire 节点：暗色焦痕圆+放射裂纹（地面焦痕三件套之一）、4~6 簇程序化火焰舌（sin 摆动三色分层）、余烬粒子（kenney spark/flame 贴图、上飘、加法混合）、橙色光晕环呼吸脉动；随区域创建/提前引爆/到期三种路径同步释放 |
| 水泽（水M1 marsh） | WaterZone 只有减速扫描 | WaterZone 自带 _draw：半透明水面（暗蓝底+亮蓝内芯）+ 三圈呼吸涟漪环 + 边缘亮线；持有水M2 旋涡构筑时叠加旋转涡流线；节点名 GroundWater |
| 水龙卷（水M10 tornado） | 同上，不可见 | 同节点按 kind 分派：三圈青色旋转螺旋+底部水眼，节点名 GroundTornado |
| 毒雾（毒M3 弥漫） | 只有毒层扩散 tick | 每次扩散落点生成 GroundPoison：三层波浪绿雾团（sin 扰动多边形、缓慢旋转）+ 上飘毒沫粒子（smoke_05 贴图）；毒M2 毒爆时也在爆点生成一团长寿命毒雾 |
| 雪迹（冰M7 冰雪风暴） | SlowZone 无视觉 | SlowZone 自带 _draw：淡蓝霜地 + 6 条冰晶折线（分支+闪烁微光）+ 霜环；节点名 GroundIce |
| 雷区（雷M9 雷云风暴 / N2 雷云） | 只有一次性落雷爆点 | 每次落雷额外生成 GroundThunder：每帧随机 4~6 条锯齿电弧（高频闪烁）+ 电光圆斑 + spark 粒子，加法混合，寿命 0.55s；节点名 GroundThunder |
| 藤蔓（水M3 定身释放） | 只有 fx_explosion nature 一瞬 | GroundVine 节点：6 条曲线卷须（curl 缠绕+摆动）+ 叶片亮点 + 绿色粒子，短寿命 1.2s |
| boss GroundZone | 淡红圆 | 保留红色伤害圈语义，补充岩浆质感：焦灼底+岩浆锯齿裂纹+余烬亮点呼吸脉动+红色外圈脉动；伤害逻辑未动 |
| summon 法阵 | fx_manager 召唤光环（_build_aura_rings）已存在 | 无需新增，报告中注明已覆盖 |

## 实现要点

- 节点类集中在 `scripts/fx/fx_manager.gd`（GroundBase 基类 + GroundFire/GroundPoison/
  GroundThunder/GroundVine + GroundTex 贴图/粒子工具 + `spawn_ground_fx` 静态工厂），
  与现有 `spawn_status_particles`/LightningBolt 同一体系；water/ice/boss 的区域节点
  自带同风格 _draw（文件所有权约束内）。
- 纯视觉：不参与碰撞/伤害，伤害/范围/时长参数全部未动。
- 生命周期：节点自计时到期 queue_free，调用方（fire zone 删除/引爆、场景退出）也会
  提前释放，双保险不泄漏；全局限量 30 个（GROUND_FX_MAX），超限淘汰场景中最旧节点。
- 程序化 _draw 优先（火焰/毒雾/电弧/藤蔓/水面/冰晶/岩浆），kenney 贴图仅作粒子点缀，
  无静态贴图冒充动态效果。
- 防御性修复：`bool(null)` 在 Godot 4.7 会抛 "Nonexistent 'bool' constructor" 并使
  当前函数中止。修复 ice_synergy._b、thunder_synergy._alive_enemy/_nearest_enemy、
  water_synergy.WaterZone._valid 共 3 处（4 个函数），仅补判空，行为不变。

## 测试

- 新增 `scripts/tests/test_ground_fx.gd` + `.tscn`：依次触发 fire 火地 / water 水泽 /
  poison 毒雾 / ice 雪迹 / thunder 雷云风暴 各一次，断言对应 Ground* 节点 2 秒内出现、
  效果结束后消失，最后 3.5s 无 Ground* 残留 → `GROUND_FX ALL PASS`（5/5 + 泄漏检查通过）。
- `tools/tests/ground_fx_check.py`：一键跑两项验收命令并核对标记。
- 回归：`test_sync_hooks` SYNC HOOKS OK、`test_summon_ext` SUMMON_EXT OK、
  `smoke_test` SMOKE OK。

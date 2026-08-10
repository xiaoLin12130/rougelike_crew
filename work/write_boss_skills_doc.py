# -*- coding: utf-8 -*-
"""生成 docs/design/Boss技能扩展方案.md（任务：Boss 技能扩展 v2）"""

DOC = """# Boss 技能扩展方案 v2

> 任务：Boss 技能扩展 v2 —— 为 6 个 Boss 扩展新技能机制，重点后面的 Boss。
> 日期：2026-08-10 · 状态：已实施

## 一、参考游戏 Boss 技能类型（带出处）

| 参考游戏 | 代表 Boss / 技能 | 技能类型 | 本项目对应新类型 |
| --- | --- | --- | --- |
| 以撒的结合：重生 | Mom 脚踩（红圈落点预告）、Hush 连续弹幕环（continuum ring）、Delirium 闪现 | 落点预告圈 / 多圈弹幕 / 瞬移 | blink 闪现、spiral 旋转弹幕环（原型：Hush 的环状弹幕每圈错相） |
| 吸血鬼幸存者 | Death / 精英 Boss 弹幕墙（sweeping wall）、追踪弹（seeker） | 弹幕墙 / 追踪弹 | wall 弹幕墙、homing_shot 追踪弹 |
| 雨中冒险 2 | 各阶段 Boss（Wandering Vagrant 的 Nova 弹幕环、Stone Titan 激光扫射） | 阶段机制 / 环形弹幕 / 激光 | enrage 狂暴（阶段 3 触发）、spiral、sweep 扇形激光扫（原型：Stone Titan 激光） |
| 枪火重生 | 精英词缀弹幕（追踪、扇形、地刺） | 追踪弹 / 扇形弹幕 / 地面延迟爆炸 | homing_shot、sweep、spike_trail 地刺轨迹 |
| 元气骑士 | 各关 Boss 弹幕（地刺、环形弹幕、位移突进） | 地面延迟伤害 / 环形弹幕 | spike_trail、spiral、blink |
| 以撒 / 元气骑士通用 | 预警（telegraph）——攻击前给出与伤害区一致的视觉提示 | 预告系统 | 复用本项目 circle/line/dot 预告，新增 dot 大半径语义（伤害点） |

## 二、本项目可落地新类型（难度评估）

| 新类型 | 机制 | 复用点 | 难度 | 预告方式 |
| --- | --- | --- | --- | --- |
| spiral 旋转弹幕环 | cast 期间按 tick 发射多圈弹幕，每圈角度偏移递进 | `_fire_bullet`、dot 预告 | 低 | 发射点小圈（与 ring_barrage 一致） |
| homing_shot 追踪弹 | 弹幕带转向玩家标志，弹速慢、转向率 3rad/s、寿命 4s | enemy_bullet 增加转向（只增不改） | 低 | 发射点小圈 |
| sweep 扇形激光扫 | beam 角度从 -60° 扫到 +60°，cast 期间角度插值 | `_player_in_ray` 射线检测、line 预告 | 中 | 起始角 + 结束角两条边界线 |
| spike_trail 地刺轨迹 | 沿玩家移动方向画连续点，延迟 0.6s 后逐点爆炸 | dot 预告（伤害点语义）、eruption 队列 | 中 | 连续伤害点（红圈） |
| blink 闪现 | 起点淡圈 + 落点红圈，cast 瞬间瞬移 + 落点范围爆炸 | leap 落点逻辑、circle 预告 | 中 | 双圈（淡圈起点 + 红圈落点） |
| wall 弹幕墙 | 竞技场内横向/纵向一排延迟爆炸点，逐点喷发 | eruption 队列、circle 预告 | 中 | 一排红圈 |
| enrage 狂暴 | 阶段 3 触发：移速 +30%、弹幕冷却 -30% | `_check_phase` | 低 | 无（被动触发，转阶段演出） |
| split 分裂 | 原地分裂出小怪（弹开出生） | 召唤逻辑、fx | 低 | 无 |

## 三、每 Boss 分配表

| Boss | 新技能 | 类型 | 机制描述 | 预告方式 | 关键参数 |
| --- | --- | --- | --- | --- | --- |
| 史莱姆王 | 分裂本体 | split | 原地分裂出 2 只小史莱姆（弹开出生），本体不损失血量 | 无 | count=2, min_phase=2, cd=10s |
| 树精守卫 | 根须地刺 | spike_trail | 沿玩家移动方向生成 6 个地刺点，0.6s 后逐点爆刺 | 连续伤害点（dot 半径=伤害半径） | count=6, spacing=64, radius=34, delay=0.6, interval=0.12, cd=9s |
| 骷髅王 | 骨刃扫射 | sweep | 激光从 -60° 扫到 +60° | 起止两条边界线 | duration=1.6s, sweep_angle=120°, cd=10s, min_phase=2 |
| 熔岩魔王 | 烈焰螺旋 | spiral | 1.4s 内连发 8 圈火弹，每圈偏移 18° | 发射点小圈 | shots=10, bullet_speed=160, ring_interval=0.14, offset=18°, cd=10s |
| 熔岩魔王 | 火墙 | wall | 玩家所在行/列生成一排火墙点，0.4s 后逐点喷发 | 一排红圈 | count=8, radius=46, interval=0.12, cd=11s, min_phase=2 |
| 远古守卫 | 圣光追踪弹 | homing_shot | 4 发追踪光弹（转向率 3rad/s、寿命 4s、弹速 135） | 发射点小圈 | count=4, bullet_speed=135, turn_rate=3.0, cd=9s, min_phase=2 |
| 远古守卫 | 圣光闪现 | blink | 双圈预告后瞬移到玩家位置并范围爆炸 | 淡圈（起点）+ 红圈（落点） | radius=110, damage_mult=1.6, cd=10s |
| 古神 | 虚空螺旋 | spiral | 1.8s 内连发 12 圈虚空弹，每圈偏移 15° | 发射点小圈 | shots=12, bullet_speed=170, ring_interval=0.12, offset=15°, cd=10s, min_phase=2 |
| 古神 | 虚空追踪 | homing_shot | 3 发追踪弹（弹速 140） | 发射点小圈 | count=3, bullet_speed=140, cd=12s, min_phase=3 |
| 古神 | 远古狂暴 | enrage | 阶段 3 触发：移速 +30%、弹幕冷却 -30% | 无（被动） | speed_mult=1.3, cd_mult=0.7, min_phase=3 |

## 四、实现约束

- 预告一致性铁律：新技能 telegraph 必须与实际伤害区一致（红圈/线/点）；伤害走 skill dict 参数。
- 技能 CD 8-12s，避免弹幕地狱；不动旧技能参数（红圈审计已验收）。
- 新类型复用状态机（WINDUP→CAST→RECOVER）与 telegraph 系统（circle/line/dot）。
- homing_shot：enemy_bullet.gd 只增转向逻辑（弹速 120-150、转向率 3rad/s、寿命 4s），不改现有行为。
- enrage 由 `_check_phase` 在进入阶段 3 时自动触发（幂等，不重复触发）。

## 五、验收

- test_boss_skills.gd：每个新类型 debug_cast→telegraph 生成→cast 完成→状态恢复，全绿输出 `BOSS SKILL TESTS OK`。
- enemies.json：6 个 Boss 均确认新技能已配置。
- smoke_test.gd：`SMOKE OK`。
"""

def main() -> None:
    path = r"docs/design/Boss技能扩展方案.md"
    with open(path, "w", encoding="utf-8") as f:
        f.write(DOC)
    print("written:", path, len(DOC), "chars")


if __name__ == "__main__":
    main()

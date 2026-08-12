extends Node
## 全局事件总线：模块间唯一通信通道（契约见 docs/design/data-schema.md）
## 禁止模块间直接互扒字段；新信号必须先登记在契约文档。

signal player_hit(dmg: int, pos: Vector2)
signal player_died
signal player_stats_changed
signal enemy_died(enemy_id: String, pos: Vector2, xp: int, gold: int, is_elite: bool)
signal damage_dealt(dmg: int, pos: Vector2, is_crit: bool)
signal apply_status(target: Node, kind: String, stacks: int)
signal item_picked(item_id: String, stacks: int)
signal spell_arranged(grid: Array)
signal level_cleared(level_id: String)
signal loop_choice(choice: String)
signal fx_explosion(pos: Vector2, kind: String)
signal fx_explosion_scaled(pos: Vector2, kind: String, radius: float)
signal fx_cast(pos: Vector2, kind: String, dir: Vector2)
signal fx_hit(pos: Vector2, kind: String)
signal fx_hit_flash(target: Node)
signal fx_hit_slow(target: Node, crit: bool)  # crit 必传：Godot 4.7.1 不支持信号参数默认值（解析错误），全部发射点已显式传参
signal fx_heal_text(pos: Vector2, amount: int)
signal fx_dot_text(pos: Vector2, amount: int, kind: String)
signal screen_shake(power: float)
signal slow_mo(factor: float, duration: float)
signal wave_state_changed(state: String)
signal run_ended(victory: bool, stats: Dictionary)
signal boss_spawned(boss_name: String, max_hp: int)
signal boss_hp_changed(hp: int, max_hp: int)
signal boss_died(pos: Vector2)
signal synergy_formed(synergy_name: String)

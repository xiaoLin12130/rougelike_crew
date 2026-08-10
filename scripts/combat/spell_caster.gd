extends Node
## 法术施放器：每帧按 GameState.run.grid 槽位顺序检查冷却，就绪即施放。
## 冷却 = core.cooldown × shell.mods.cooldown_mult × 法杖充能系数（item_value 曲线）。
## 施放方向 = InputRouter.aim_vector；鼠标与玩家距离 > 20px 时改瞄鼠标。

const PROJECTILE_SCENE := preload("res://scenes/game/projectile.tscn")
const SUMMON_SCRIPT := preload("res://scripts/combat/summon.gd")
const WAND_CHARGE_CURVE := {"curve": {"type": "multiplicative", "base": 0.9, "cap": 0.5}}
const MIN_CD := 0.05

## 攻速全局接线（G1/G2 收敛）：各 synergy 脚本只写自己的 run.xxx_bonus 读取点，
## run.attack_speed_bonus 仅由 game_state.apply_item_effects_to_stats 写入基础聚合
## （解决 fire/melee/wind 三脚本自校正互踩同一字段的问题）；
## 消费端（本脚本 + melee_attack）统一读"基础聚合 + 各流派贡献"之和，与近战同公式。
const _SYNERGY_AS_KEYS := [
	"fire_m2_atk_speed",   ## 火M2 薪火相传
	"melee_m3_as_bonus",   ## 近M3 血之狂暴
	"melee_m9_as_bonus",   ## 近M9 狂化
	"wind_as_bonus",       ## 移2/移5 移速→攻速联动
	"wind_m2_atk_speed",   ## 移M2 踏风
	"wind_m10_as_bonus",   ## 移M10 暴走
]

var _cds: Array[float] = []
var _frenzy_left := 0.0


func _ready() -> void:
	EventBus.spell_arranged.connect(_on_grid_changed)


func _physics_process(delta: float) -> void:
	_frenzy_left = maxf(_frenzy_left - delta, 0.0)
	var player := _player()
	if player == null:
		return
	var grid: Array = GameState.run.get("grid", [])
	_sync_cds(grid.size())
	for i in grid.size():
		if _cds[i] > 0.0:
			_cds[i] -= delta
			continue
		var slot: Dictionary = grid[i]
		var core := _find_core(str(slot.get("core", "")))
		if core.is_empty():
			continue
		var shell := _find_shell(str(slot.get("shell", "")))
		_cast(player, core, shell.get("mods", {}))
		_cds[i] = _cooldown_of(core, shell.get("mods", {}))


func _player() -> Node2D:
	var p: Node = get_tree().get_first_node_in_group("player")
	if p != null:
		return p as Node2D
	var parent := get_parent()
	if parent is Node2D:
		return parent as Node2D
	return null


func _sync_cds(size: int) -> void:
	while _cds.size() < size:
		_cds.append(0.0)  # 新槽位 0 → 就绪即施放
	while _cds.size() > size:
		_cds.pop_back()


func _on_grid_changed(_grid: Array) -> void:
	_sync_cds(_grid.size())


func _find_core(core_id: String) -> Dictionary:
	for c in GameState.tables.get("spells", {}).get("cores", []):
		if str(c.get("id", "")) == core_id:
			return c
	return {}


func _find_shell(shell_id: String) -> Dictionary:
	for s in GameState.tables.get("spells", {}).get("shells", []):
		if str(s.get("id", "")) == shell_id:
			return s
	return {}


func _cooldown_of(core: Dictionary, mods: Dictionary) -> float:
	var cd: float = float(core.get("cooldown", 1.0)) * float(mods.get("cooldown_mult", 1.0))
	var wand: float = GameState.item_value(WAND_CHARGE_CURVE, GameState.total_stacks("wand_charge"))
	var cd_mult: float = 1.0
	# 冷却缩减聚合：cooldown/skill_cd tag（记忆·疾风、闪电核心、冰水混合、火元素徽章、
	# 诅咒精通等 + 冷却流 synergy_bonus.cooldown），上限 80%
	var cd_reduce := clampf(
		GameState.aggregate_bonus("cooldown") + GameState.aggregate_bonus("skill_cd"),
		0.0, 0.8)
	for wid in GameState.current_wands():
		var wand_def := GameState.wand_def(str(wid))
		if wand_def.is_empty():
			continue
		cd_mult *= float(wand_def.get("cd_mult", 1.0))
	if _frenzy_left > 0.0:
		cd_mult *= 0.5  # 狂暴：冷却减半
	# 攻速全局接线（G1）：施法冷却接入攻速聚合，与近战 melee_attack._interval 同公式
	cd_mult *= 1.0 / (1.0 + _total_attack_speed())
	# 移9 迅捷：技能冷却 -5%/层（run.wind_cd_mult 读取点接线）
	cd_mult *= maxf(float(GameState.run.get("wind_cd_mult", 1.0)), 0.0)
	return maxf(cd * wand * cd_mult * (1.0 - cd_reduce), MIN_CD)


## 攻速聚合：基础（run.attack_speed_bonus，game_state 写入的 aggregate_bonus("attack_speed")）
## + 各流派贡献读取点之和。同步维护在 melee_attack.gd。
func _total_attack_speed() -> float:
	if GameState == null or not (GameState.run is Dictionary):
		return 0.0
	var total := maxf(float(GameState.run.get("attack_speed_bonus", 0.0)), 0.0)
	for key in _SYNERGY_AS_KEYS:
		total += maxf(float(GameState.run.get(key, 0.0)), 0.0)
	return total


func _cast(player: Node2D, core: Dictionary, mods: Dictionary) -> void:
	SynergyRegistry.trigger("cast", {"player": player, "core": core, "mods": mods})
	# 法杖形态合并（shell mods 之后追加法杖 shape mods；数值倍率在伤害/冷却计算中生效）
	# 多法杖形态合并（最多 3 把，后购买的覆盖冲突字段）
	for wid in GameState.current_wands():
		var wand_def := GameState.wand_def(str(wid))
		if wand_def.is_empty():
			continue
		var shape_mods: Dictionary = wand_def.get("shape_mods", {})
		if not shape_mods.is_empty():
			var merged := mods.duplicate()
			for k in shape_mods:
				merged[k] = shape_mods[k]
			mods = merged
	# 特殊核心：不发射弹幕的法术
	if core.get("teleport", false):
		_cast_teleport(player, core, mods)
		return
	if core.get("frenzy", false):
		_frenzy_left = 3.0
		EventBus.fx_explosion.emit(player.global_position, "lightning")
		return
	if core.get("mana_echo", false):
		for i in _cds.size():
			_cds[i] = 0.0
		EventBus.fx_explosion.emit(player.global_position, "ice")
		return
	if core.get("bless", false):
		_cast_blessing(player, core, mods)
		return
	if core.get("counter", false):
		_cast_counter(player, core, mods)
		return
	var element: String = str(core.get("element", "fire"))
	var aim := _aim_dir(player)
	# 特效分级：普通施法走轻量 muzzle（fx_cast），不再触发复合大爆炸
	EventBus.fx_cast.emit(player.global_position + aim * 10.0, element, aim)
	if core.has("summon") or str(core.get("id", "")) == "summon_bat":
		_spawn_summon(player, core, mods)
		return
	if str(core.get("id", "")) == "whirl_blade":
		_cast_whirl_blade(player, core, mods)
		return
	var dmg := _spell_damage(core, mods, element)
	var aoe: float = float(core.get("aoe", 0.0)) * float(mods.get("aoe_mult", 1.0)) * (1.0 + GameState.aggregate_bonus("area"))
	var speed: float = float(core.get("speed", 0.0)) * float(mods.get("speed_mult", 1.0))
	var shots: int = maxi(int(mods.get("shots", 1)), 1)
	# 移M4 追风猎手：弹数读取点接线（wind_synergy 按移速阈值写入 run.wind_m4_shots）
	shots += maxi(int(GameState.run.get("wind_m4_shots", 0)), 0)
	shots = maxi(shots, 1)
	var spread: float = float(mods.get("spread_angle", 0.0))
	# 瞬发核×连发（问题7）：落点扇形分散（spread=0 时给默认扇角），避免同点堆叠；
	# 毒雾×连发=扇形 3 团、闪电/火柱/闪光×连发=多点分散
	if speed <= 0.0 and shots > 1 and spread <= 0.0:
		spread = 24.0
	var base_angle := aim.angle()
	for i in shots:
		var dir := aim
		if shots > 1 and spread > 0.0:
			var t := float(i) / float(shots - 1) - 0.5
			dir = Vector2.from_angle(base_angle + deg_to_rad(spread) * t)
		_spawn_projectile(player, dir, core, mods, dmg, aoe, speed)


func _cast_whirl_blade(player: Node2D, core: Dictionary, mods: Dictionary) -> void:
	## 旋风刃：N 把刀刃围绕玩家旋转（持续 4s），接触敌人造成斩击伤害
	## 描述与效果一致：剑围绕自身转，而非瞬爆
	## 连发/齐射（问题15）：刃数 = shots（默认 2 把；连发 3 刃、齐射 5 刃）
	var dmg := _spell_damage(core, mods, "blade")
	var aoe: float = float(core.get("aoe", 40.0)) * float(mods.get("aoe_mult", 1.0)) * (1.0 + GameState.aggregate_bonus("area"))
	var orbit_mods: Dictionary = mods.duplicate()
	orbit_mods["orbit"] = 4.0
	orbit_mods["_whirl"] = true  # 标记旋风刃：基础刀刃不触发轨道接触爆炸（问题2/14 区分）
	var blades := maxi(int(mods.get("shots", 0)), 2)
	var base_angle := _aim_dir(player).angle()
	for i in blades:
		var dir := Vector2.from_angle(base_angle + TAU * float(i) / float(blades))
		_spawn_projectile(player, dir, core, orbit_mods, dmg, aoe, 1.0)
	EventBus.fx_cast.emit(player.global_position, "blade", Vector2.RIGHT)


## 伤害 = core.base_damage × mods.damage_mult × (1+atk 加成) × (1+元素加成)。
func _spell_damage(core: Dictionary, mods: Dictionary, element: String) -> float:
	var dmg: float = float(core.get("base_damage", 0.0)) * float(mods.get("damage_mult", 1.0))
	dmg *= 1.0 + GameState.aggregate_bonus("atk")
	dmg *= 1.0 + GameState.aggregate_bonus("skill_dmg")  # 记忆·破军等：技能伤害加成
	dmg *= 1.0 + GameState.aggregate_bonus(element)
	for wid in GameState.current_wands():
		var wand_def := GameState.wand_def(str(wid))
		if wand_def.is_empty():
			continue
		dmg *= float(wand_def.get("damage_mult", 1.0))
		dmg *= 1.0 + float(wand_def.get("element_bonus", {}).get(element, 0.0))
		dmg *= 1.0 + GameState.WAND_UPGRADE_BONUS * float(GameState.wand_upgrade_level(str(wid)))
	if _frenzy_left > 0.0:
		dmg *= 1.3
	return dmg

func _cast_teleport(player: Node2D, core: Dictionary, mods: Dictionary) -> void:
	## 传送：向瞄准方向闪现 + 落点爆炸
	## 爆发外壳（问题19）：爆炸半径乘 aoe_mult（与普通核心一致）；吸血外壳：爆炸伤害按比例回血
	var aim := _aim_dir(player)
	var new_pos: Vector2 = player.global_position + aim * float(core.get("range", 160.0))
	var m := GameState.MAP_SIZE
	new_pos = new_pos.clamp(Vector2(40, 40), m - Vector2(40, 40))
	player.global_position = new_pos
	var dmg := _spell_damage(core, mods, "void")
	var r := float(core.get("aoe", 48.0)) * float(mods.get("aoe_mult", 1.0)) * (1.0 + GameState.aggregate_bonus("area"))
	EventBus.fx_explosion_scaled.emit(new_pos, "void", r)
	var dealt := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and new_pos.distance_to(e.global_position) <= r + e.scale.x * 8.0:
			if e.has_method("take_damage"):
				e.take_damage(int(dmg), "void", false)
				EventBus.damage_dealt.emit(int(dmg), e.global_position, false)
				dealt += int(dmg)
	_drain_heal(mods, dealt)

func _cast_blessing(player: Node2D, core: Dictionary, mods: Dictionary) -> void:
	## 圣光：回复生命 + 周围敌人光属性伤害（爆发外壳：半径乘 aoe_mult；吸血：伤害回血）
	GameState.heal(15.0)
	var dmg := _spell_damage(core, mods, "light")
	var r := float(core.get("aoe", 90.0)) * float(mods.get("aoe_mult", 1.0)) * (1.0 + GameState.aggregate_bonus("area"))
	var dealt := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and player.global_position.distance_to(e.global_position) <= r + e.scale.x * 8.0:
			if e.has_method("take_damage"):
				e.take_damage(int(dmg), "light", false)
				EventBus.damage_dealt.emit(int(dmg), e.global_position, false)
				dealt += int(dmg)
	_drain_heal(mods, dealt)
	EventBus.fx_explosion_scaled.emit(player.global_position, "light", r)

func _cast_counter(player: Node2D, core: Dictionary, mods: Dictionary) -> void:
	## 反制（简版）：销毁半径内敌方弹幕 + 对周围敌人造成伤害（爆发外壳：半径乘 aoe_mult；吸血：伤害回血）
	var r := float(core.get("aoe", 60.0)) * float(mods.get("aoe_mult", 1.0)) * (1.0 + GameState.aggregate_bonus("area"))
	var dmg := _spell_damage(core, mods, "void")
	var dealt := 0
	for e in get_tree().get_nodes_in_group("enemy_bullet"):
		if is_instance_valid(e) and player.global_position.distance_to(e.global_position) <= r:
			e.queue_free()
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and player.global_position.distance_to(e.global_position) <= r + e.scale.x * 8.0:
			if e.has_method("take_damage"):
				e.take_damage(int(dmg), "void", false)
				EventBus.damage_dealt.emit(int(dmg), e.global_position, false)
				dealt += int(dmg)
	_drain_heal(mods, dealt)
	EventBus.fx_explosion_scaled.emit(player.global_position, "ice", r)


## 吸血外壳（问题19）：特殊核心爆炸命中按 总伤害×drain 回血（与弹幕 _hit_enemy 同口径）
func _drain_heal(mods: Dictionary, dealt: int) -> void:
	var d := float(mods.get("drain", 0.0))
	if d > 0.0 and dealt > 0:
		GameState.heal(float(dealt) * d)


func _spawn_projectile(player: Node2D, dir: Vector2, core: Dictionary, mods: Dictionary, dmg: float, aoe: float, speed: float) -> void:
	var proj := PROJECTILE_SCENE.instantiate()
	# 核心状态参数（burn/slow/root/poison/blind）与闪电链跳数透传
	var status: Dictionary = {}
	for k in ["burn", "slow", "root", "poison", "blind"]:
		if core.has(k):
			status[k] = float(core.get(k, 0.0))
	proj.setup({
		"position": player.global_position + dir * 12.0,
		"direction": dir,
		"speed": speed,
		"range": float(core.get("range", 360.0)),
		"damage": dmg,
		"element": str(core.get("element", "fire")),
		"aoe": aoe,
		"mods": mods,
		"status": status,
		"chain": int(core.get("chain", 0)),
	})
	get_tree().current_scene.add_child(proj)


func _spawn_summon(player: Node2D, core: Dictionary, mods: Dictionary) -> void:
	## 把核心期望的召唤类型 id 传给 summon.gd：按指定类型创建；
	## 该类型已达 max_count 时由 summon.gd 静默中止（不随机换种类）。
	## 连发外壳（问题18）：按 shots 召唤多只（受 summon.gd 类型 max_count / 总上限约束，超限静默中止）
	var type_id := str(core.get("summon", ""))
	if type_id == "" or type_id == "true":
		# 兼容：核心未写明类型时按核心 id 推导（summon_bat -> bat）
		type_id = str(core.get("id", "")).trim_prefix("summon_")
	var count := maxi(int(mods.get("shots", 1)), 1)
	for i in count:
		var summon := SUMMON_SCRIPT.new()
		summon.setup(player, _spell_damage(core, mods, "summon"), str(core.get("element", "summon")), type_id)
		get_tree().current_scene.add_child(summon)
		summon.global_position = player.global_position + Vector2(randf_range(-12.0, 12.0), randf_range(-12.0, 12.0))


func _aim_dir(player: Node2D) -> Vector2:
	## 自动索敌：攻击自动瞄准最近的敌人（不再跟随玩家鼠标）
	var nearest := _nearest_enemy(player)
	if nearest != null:
		return (nearest.global_position - player.global_position).normalized()
	if InputRouter.aim_vector.length_squared() > 0.0:
		return InputRouter.aim_vector.normalized()
	return Vector2.RIGHT

func _nearest_enemy(player: Node2D) -> Node:
	var best: Node = null
	var best_d := INF
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		var d: float = player.global_position.distance_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best

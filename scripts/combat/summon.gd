extends Node2D
## 召唤物系统：召唤核心施放时按核心指定的类型 id（如 summon_bat -> bat）创建对应召唤物；
## 若该类型已达 max_count（data/summons.json）则不重复创建（静默销毁）；
## 未指定类型时保留按权重随机选择（兼容路径：排除已达 max_count 的类型；全部满员时召唤已存在类型中最弱的一个）。
## 10 种类型各有技能（bite/follow_shot/charge/taunt/triple_shot/backstab/pierce/orbit/block/self_destruct）。
## 同类型实例数 <= max_count；总数量 <= 1 + summon_book 层数（超限销毁最旧召唤物）。
## 攻击目标：group "enemy"；外观为友军蓝（与 gen/summon_bat_1.png 同配色方案）。

const PROJECTILE_SCENE := preload("res://scenes/game/projectile.tscn")
const LIFETIME := 30.0
const FOLLOW_RANGE := 64.0            # 无目标时跟随玩家的距离
const MELEE_RADIUS := 18.0            # 近战接触判定半径（另加敌人体型）
const MELEE_LUNGE := 8.0              # 近战咬合容差
const KEEP_RANGE := 150.0             # 远程型与玩家保持的距离
const ORBIT_RADIUS := 38.0
const ORBIT_SPEED := 2.6
const TAUNT_RADIUS := 150.0
const SWORD_RANGE := 320.0
const SWORD_HIT_RADIUS := 16.0
const BOMB_RADIUS := 48.0
const ARENA_MARGIN := 24.0

static var _spawn_counter := 0

var _player: Node2D = null
var _damage := 6.0                    # 施放时传入的基础伤害
var _element := "summon"
var _requested_type := ""             # 施法核心指定的召唤类型 id（如 "bat"）；空 = 未指定，走权重随机兼容路径

var _type_id := ""                    # bat/spirit/skeleton/knight/mage/rogue/flying_sword/orb/shieldbearer/fire_spirit
var _def: Dictionary = {}
var _dmg := 6.0                       # = 基础伤害 × damage_mult
var _hp := 20.0
var _max_hp := 20.0
var _speed := 120.0
var _skill := ""
var _skill_cd := 1.0
var _life := LIFETIME
var _spawn_order := 0

# 技能状态
var _skill_timer := 0.0               # 技能冷却倒计时
var _atk_timer := 0.0                 # 近战攻击冷却倒计时
var _dashing := false
var _dash_dir := Vector2.ZERO
var _dash_left := 0.0
var _dash_hits := {}                  # 冲锋/背刺已命中 enemy instance_id
var _sword_phase := 0                 # 飞剑：0 待机 / 1 飞出 / 2 返回
var _sword_dir := Vector2.RIGHT
var _sword_travelled := 0.0
var _sword_hit := {}                  # 飞出阶段已穿透的 enemy instance_id
var _hover_angle := 0.0
var _orbit_angle := 0.0
var _orbit_cd := {}                   # 法球 per-enemy 伤害间隔
var _block_left := 0.0                # 盾卫格挡恢复倒计时


## setup 签名保持兼容（spell_caster 传 3 参）；force_id 仅测试用。
## setup：spell_caster 施法时把期望的召唤类型 id 传入（type_id 为空时走权重随机兼容路径）。
func setup(player: Node2D, damage: float, element: String, type_id: String = "") -> void:
	_player = player
	_damage = damage
	_element = element
	_requested_type = type_id


func _ready() -> void:
	add_to_group("summons")
	_spawn_order = _spawn_counter
	_spawn_counter += 1
	if not _pick_type():
		return  # 指定类型已达上限 / 类型缺失 / 无可选类型，本次召唤中止
	_apply_stats()
	_build_sprite()
	_enforce_cap()
	if _skill == "taunt":
		_taunt()  # 生成即嘲讽一次
	elif _skill == "block":
		EventBus.player_hit.connect(_on_player_hit_block)


## 选类型：指定类型（_requested_type）时按指定类型创建，已达 max_count 则不重复创建（静默销毁）；
## 未指定类型时按权重随机（排除已达 max_count 者；全满则选已存在类型中 damage_mult 最低者）。
## 返回 false 表示本次召唤中止（类型缺失或已达该类型上限）。
func _pick_type() -> bool:
	var rows: Array = GameState.tables.get("summons", {}).get("summons", [])
	if _requested_type != "":
		for r in rows:
			if str(r.get("id", "")) == _requested_type:
				_def = r
				_type_id = _requested_type
				if int(_counts_by_type().get(_type_id, 0)) >= int(r.get("max_count", 1)):
					# 该类型已达 max_count：不重复创建（静默）
					queue_free()
					return false
				return true
		push_warning("summon type not found in data/summons.json: " + _requested_type)
		queue_free()
		return false
	# ---- 未指定类型：权重随机兼容路径 ----
	var counts := _counts_by_type()
	var pool: Array = []
	for r in rows:
		var tid: String = str(r.get("id", ""))
		if int(counts.get(tid, 0)) < int(r.get("max_count", 1)):
			pool.append(r)
	if pool.is_empty():
		# 全部类型已满：召唤已存在类型中最弱的一个（damage_mult 最低）
		var weakest: Dictionary = {}
		for tid in counts:
			if int(counts[tid]) <= 0:
				continue
			for r in rows:
				if str(r.get("id", "")) == tid:
					if weakest.is_empty() or float(r.get("damage_mult", 1.0)) < float(weakest.get("damage_mult", 1.0)):
						weakest = r
					break
		if weakest.is_empty():
			queue_free()
			return false
		_def = weakest
		_type_id = str(weakest.get("id", ""))
		return true
	var total := 0.0
	for r in pool:
		total += maxf(float(r.get("weight", 1.0)), 0.0)
	var roll := randf() * total
	var acc := 0.0
	for r in pool:
		acc += maxf(float(r.get("weight", 1.0)), 0.0)
		if roll <= acc:
			_def = r
			_type_id = str(r.get("id", ""))
			return true
	_def = pool[-1]
	_type_id = str(pool[-1].get("id", ""))
	return true


func _counts_by_type() -> Dictionary:
	var counts := {}
	for s in get_tree().get_nodes_in_group("summons"):
		if s == self or not is_instance_valid(s) or s.is_queued_for_deletion():
			continue
		var tid: String = str(s.get("_type_id"))
		if tid != "":
			counts[tid] = int(counts.get(tid, 0)) + 1
	return counts


func _apply_stats() -> void:
	_dmg = maxf(_damage * float(_def.get("damage_mult", 1.0)), 0.0)
	_speed = float(_def.get("speed", 120.0))
	_skill = str(_def.get("skill", ""))
	_skill_cd = maxf(float(_def.get("skill_cd", 1.0)), 0.05)
	var base_hp: float = float(GameState.run.get("max_hp", 100))
	_max_hp = maxf(base_hp * float(_def.get("hp_mult", 1.0)), 10.0)
	_hp = _max_hp


func _build_sprite() -> void:
	var frames: int = int(_def.get("frames", 1))
	var base_path: String = str(_def.get("sprite", ""))
	if base_path == "" or not ResourceLoader.exists(base_path):
		push_warning("summon sprite missing: " + base_path)
		return
	var anim := AnimatedSprite2D.new()
	anim.name = "AnimatedSprite2D"
	var sf := SpriteFrames.new()
	sf.add_animation("idle")
	sf.set_animation_speed("idle", 6.0)
	for i in frames:
		var p := base_path.replace("_1.png", "_%d.png" % (i + 1)) if frames > 1 else base_path
		sf.add_frame("idle", load(p))
	anim.sprite_frames = sf
	anim.play("idle")
	add_child(anim)


## 总数量上限 = 召1 召唤之书层数 + 旧召唤之书层数 + 1；超限销毁最旧召唤物。
func _enforce_cap() -> void:
	var cap: int = GameState.total_stacks("summon_1") + GameState.total_stacks("summon_book") + 1
	var group: Array = get_tree().get_nodes_in_group("summons")
	if group.size() <= cap:
		return
	var oldest: Node = null
	var oldest_order := 1 << 30
	for s in group:
		if s == self or not is_instance_valid(s) or s.is_queued_for_deletion():
			continue
		var order: int = int(s.get("_spawn_order"))
		if order < oldest_order:
			oldest_order = order
			oldest = s
	if oldest != null:
		oldest.queue_free()


func _physics_process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	if _player == null or not is_instance_valid(_player):
		queue_free()
		return
	_skill_timer = maxf(_skill_timer - delta, 0.0)
	_atk_timer = maxf(_atk_timer - delta, 0.0)
	if _block_left > 0.0:
		_block_left = maxf(_block_left - delta, 0.0)
	match _skill:
		"bite": _skill_bite(delta)
		"follow_shot": _skill_follow_shot(delta)
		"charge": _skill_charge(delta)
		"taunt": _skill_taunt(delta)
		"triple_shot": _skill_triple_shot(delta)
		"backstab": _skill_backstab(delta)
		"pierce": _skill_pierce(delta)
		"orbit": _skill_orbit(delta)
		"block": _skill_block(delta)
		"self_destruct": _skill_self_destruct(delta)
		_: _skill_bite(delta)


## bite：追踪近战撕咬（蝙蝠）。
func _skill_bite(delta: float) -> void:
	var target := _nearest_enemy(220.0)
	var to_player := _player.global_position - global_position
	if target != null:
		var to_t: Vector2 = target.global_position - global_position
		if to_t.length() > _hit_range(target):
			global_position += to_t.normalized() * _speed * delta
		elif _atk_timer <= 0.0:
			_atk_timer = maxf(_skill_cd, 0.5)
			_melee_hit(target)
	elif to_player.length() > FOLLOW_RANGE:
		global_position += to_player.normalized() * _speed * delta


## follow_shot：跟随发射追踪弹幕（元素精灵）。
func _skill_follow_shot(delta: float) -> void:
	_keep_player_distance(delta)
	var target := _nearest_enemy(420.0)
	if target != null and _skill_timer <= 0.0:
		_skill_timer = _skill_cd
		_fire_projectile((target.global_position - global_position).normalized(), 300.0, 460.0, {"homing": true})


## charge：接近后冲锋碾过敌人（骷髅兵）。
func _skill_charge(delta: float) -> void:
	var target := _nearest_enemy(260.0)
	var to_player := _player.global_position - global_position
	if _dashing:
		_dash_left -= delta
		global_position += _dash_dir * _speed * 3.2 * delta
		for e in _enemies_near(global_position, MELEE_RADIUS):
			var id: int = e.get_instance_id()
			if not _dash_hits.has(id):
				_dash_hits[id] = true
				_damage_enemy(e, 1.0)
		if _dash_left <= 0.0:
			_dashing = false
		return
	if target != null:
		var to_t: Vector2 = target.global_position - global_position
		if to_t.length() > 70.0:
			global_position += to_t.normalized() * _speed * delta
		elif _skill_timer <= 0.0:
			_start_dash(target, 0.5)
	elif to_player.length() > FOLLOW_RANGE:
		global_position += to_player.normalized() * _speed * delta


## taunt：嘲讽（简化版：周期性减速周围敌人）+ 近战（骑士守卫）。
func _skill_taunt(delta: float) -> void:
	var target := _nearest_enemy(220.0)
	var to_player := _player.global_position - global_position
	if target != null:
		var to_t: Vector2 = target.global_position - global_position
		if to_t.length() > _hit_range(target):
			global_position += to_t.normalized() * _speed * delta
		elif _atk_timer <= 0.0:
			_atk_timer = 1.0
			_melee_hit(target)
	elif to_player.length() > FOLLOW_RANGE:
		global_position += to_player.normalized() * _speed * delta
	if _skill_timer <= 0.0:
		_skill_timer = _skill_cd
		_taunt()


## triple_shot：三连扇形弹幕（法师学徒）。
func _skill_triple_shot(delta: float) -> void:
	_keep_player_distance(delta)
	var target := _nearest_enemy(460.0)
	if target != null and _skill_timer <= 0.0:
		_skill_timer = _skill_cd
		var base_angle: float = (target.global_position - global_position).angle()
		for i in 3:
			_fire_projectile(Vector2.from_angle(base_angle + deg_to_rad((i - 1) * 10.0)), 320.0, 500.0, {})


## backstab：突进背刺暴击（盗贼刺客）。
func _skill_backstab(delta: float) -> void:
	var target := _nearest_enemy(300.0)
	var to_player := _player.global_position - global_position
	if _dashing:
		_dash_left -= delta
		global_position += _dash_dir * _speed * 2.2 * delta
		if target != null and global_position.distance_to(target.global_position) <= _hit_range(target):
			if not _dash_hits.has(target.get_instance_id()):
				_dash_hits[target.get_instance_id()] = true
				_damage_enemy(target, 2.0, true)  # 背刺：2 倍暴击
		if _dash_left <= 0.0:
			_dashing = false
		return
	if target != null:
		var to_t: Vector2 = target.global_position - global_position
		if to_t.length() > 60.0:
			global_position += to_t.normalized() * _speed * delta
		elif _skill_timer <= 0.0:
			_start_dash(target, 0.4)
			_skill_timer = _skill_cd
	elif to_player.length() > FOLLOW_RANGE:
		global_position += to_player.normalized() * _speed * delta


## pierce：穿透飞剑直线往返（飞剑）。
func _skill_pierce(delta: float) -> void:
	if _sword_phase == 1:
		_sword_travelled += _speed * delta
		global_position += _sword_dir * _speed * delta
		for e in _enemies_near(global_position, SWORD_HIT_RADIUS):
			var id: int = e.get_instance_id()
			if not _sword_hit.has(id):
				_sword_hit[id] = true
				_damage_enemy(e, 1.0)
		if _sword_travelled >= SWORD_RANGE:
			_sword_phase = 2
		return
	if _sword_phase == 2:
		var to_p := _player.global_position - global_position
		if to_p.length() > 20.0:
			global_position += to_p.normalized() * _speed * 1.4 * delta
		else:
			_sword_phase = 0
		return
	# 待机：绕玩家悬停，冷却结束向最近敌人飞出
	_hover_angle += 2.0 * delta
	global_position = _player.global_position + Vector2.from_angle(_hover_angle) * 30.0
	var target := _nearest_enemy(420.0)
	if target != null and _skill_timer <= 0.0:
		_skill_timer = _skill_cd
		_sword_dir = (target.global_position - global_position).normalized()
		_sword_travelled = 0.0
		_sword_hit.clear()
		_sword_phase = 1


## orbit：环绕玩家持续伤害（浮游法球）。
func _skill_orbit(delta: float) -> void:
	_orbit_angle += ORBIT_SPEED * delta
	global_position = _player.global_position + Vector2.from_angle(_orbit_angle) * ORBIT_RADIUS
	for e in _enemies_near(global_position, 20.0):
		var id: int = e.get_instance_id()
		var left: float = float(_orbit_cd.get(id, 0.0)) - delta
		if left <= 0.0:
			_orbit_cd[id] = _skill_cd
			_damage_enemy(e, 1.0)
		else:
			_orbit_cd[id] = left


## block：格挡——替玩家承受一次伤害（订阅 player_hit 抵消，盾卫）。
func _skill_block(delta: float) -> void:
	var target := _nearest_enemy(220.0)
	var to_player := _player.global_position - global_position
	if target != null:
		var to_t: Vector2 = target.global_position - global_position
		if to_t.length() > _hit_range(target):
			global_position += to_t.normalized() * _speed * delta
		elif _atk_timer <= 0.0:
			_atk_timer = 1.2
			_melee_hit(target)
	elif to_player.length() > FOLLOW_RANGE:
		global_position += to_player.normalized() * _speed * delta


func _on_player_hit_block(dmg: int, pos: Vector2) -> void:
	if _block_left > 0.0 or dmg <= 0:
		return
	_block_left = _skill_cd
	GameState.heal(dmg)  # 抵消本次伤害（恢复被扣血量）
	EventBus.fx_explosion.emit(pos, "ice")


## self_destruct：接触敌人自爆 AoE（火焰精灵）。
func _skill_self_destruct(delta: float) -> void:
	var target := _nearest_enemy(INF)
	if target == null:
		var to_player := _player.global_position - global_position
		if to_player.length() > FOLLOW_RANGE:
			global_position += to_player.normalized() * _speed * delta
		return
	var to_t: Vector2 = target.global_position - global_position
	if to_t.length() <= _hit_range(target):
		_explode()
		return
	global_position += to_t.normalized() * _speed * delta


func _explode() -> void:
	EventBus.fx_explosion.emit(global_position, "fire")
	EventBus.screen_shake.emit(4.0)
	for e in _enemies_near(global_position, BOMB_RADIUS):
		_damage_enemy(e, 1.0)
	queue_free()


func _start_dash(target: Node, duration: float) -> void:
	_dashing = true
	_dash_hits.clear()
	_dash_dir = (target.global_position - global_position).normalized()
	_dash_left = duration


func _keep_player_distance(delta: float) -> void:
	var to_player := _player.global_position - global_position
	var d := to_player.length()
	if d > KEEP_RANGE:
		global_position += to_player.normalized() * _speed * delta
	elif d < KEEP_RANGE * 0.55:
		global_position -= to_player.normalized() * _speed * delta


func _melee_hit(target: Node) -> void:
	if not is_instance_valid(target):
		return
	if global_position.distance_to(target.global_position) <= _hit_range(target) + MELEE_LUNGE:
		_damage_enemy(target, 1.0)


func _damage_enemy(enemy: Node, mult: float, is_crit: bool = false) -> void:
	if not is_instance_valid(enemy):
		return
	var dmg := roundi(_dmg * mult)
	if enemy.has_method("take_damage"):
		enemy.take_damage(dmg, _element, is_crit)
	EventBus.damage_dealt.emit(dmg, enemy.global_position, is_crit)
	EventBus.fx_hit_flash.emit(enemy)


func _fire_projectile(dir: Vector2, speed: float, range: float, mods: Dictionary) -> void:
	var proj := PROJECTILE_SCENE.instantiate()
	proj.setup({
		"position": global_position + dir * 12.0,
		"direction": dir,
		"speed": speed,
		"range": range,
		"damage": _dmg,
		"element": _element,
		"aoe": 0.0,
		"mods": mods,
	})
	get_tree().current_scene.add_child(proj)


func _taunt() -> void:
	EventBus.fx_explosion.emit(global_position, "ice")
	for e in GameState.get_enemies():
		if not is_instance_valid(e):
			continue
		if global_position.distance_to(e.global_position) <= TAUNT_RADIUS + e.scale.x * 8.0:
			EventBus.apply_status.emit(e, "slow", 1)
			EventBus.fx_hit_slow.emit(e)


func _hit_range(target: Node) -> float:
	return MELEE_RADIUS + target.scale.x * 8.0


func _nearest_enemy(max_range: float) -> Node:
	var best: Node = null
	var best_d := max_range
	for e in GameState.get_enemies():
		if not is_instance_valid(e):
			continue
		var d: float = global_position.distance_to(e.global_position) - e.scale.x * 8.0
		if d <= best_d:
			best_d = d
			best = e
	return best


func _enemies_near(center: Vector2, radius: float) -> Array:
	var result: Array = []
	for e in GameState.get_enemies():
		if not is_instance_valid(e):
			continue
		if center.distance_to(e.global_position) <= radius + e.scale.x * 8.0:
			result.append(e)
	return result


func _clamp_to_arena() -> void:
	global_position = global_position.clamp(
		Vector2(ARENA_MARGIN, ARENA_MARGIN),
		GameState.MAP_SIZE - Vector2(ARENA_MARGIN, ARENA_MARGIN)
	)

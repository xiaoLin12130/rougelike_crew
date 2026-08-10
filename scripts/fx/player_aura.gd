extends Node2D
## 玩家构筑光环（Agent C 新建）：让构筑"肉眼可见"。
## 挂载方式：player.gd _ready() 挂到玩家下，位置自动跟随（z 在玩家脚底）。
## 数据只读 GameState：run.synergy_bonus（fire/ice/lightning/poison/summon/
## attack_speed/crit_dmg/defense/max_hp/cooldown 等）、aggregate_bonus(
## "attack_speed"/"speed"/"atk"/"defense"/"cooldown")、run.crit_chance、
## run.crit_dmg_bonus、run.lifesteal。
## 视觉全部程序化：CPUParticles2D + Line2D + 运行时 ImageTexture 径向渐变，
## 禁止新增静态贴图文件。
## 档位 0-3（阈值参考 fx_manager 的 DPS 档位思路）：数值越高，
## 粒子数量/环半径/亮度/转速越高。

## ===== 统计流颜色（元素流颜色走 UiTheme.ELEMENT，见 _element_color）=====
const FLOW_COLORS := {
	"attack_speed": Color(1.0, 0.76, 0.2),    # 攻速流：金色残影/流线
	"crit": Color(1.0, 0.28, 0.24),           # 暴击流：红色星点
	"defense": Color(0.36, 0.62, 1.0),        # 防御流：蓝色盾圈
	"lifesteal": Color(0.35, 1.0, 0.55),      # 吸血流：绿色粒子飞入
	"speed": Color(0.30, 0.92, 0.92),         # 移速流：青色拖尾
	"cooldown": Color(0.68, 0.44, 1.0),       # 冷却流：紫色符文环
	"max_hp": Color(0.55, 0.93, 0.38),        # 生命流：绿色生命环
}
## UiTheme.ELEMENT 不可用时兜底（正常会命中 UiTheme.ELEMENT）
const ELEMENT_FALLBACK := {
	"fire": Color(1.0, 0.48, 0.24),
	"ice": Color(0.50, 0.83, 1.0),
	"lightning": Color(1.0, 0.90, 0.36),
	"poison": Color(0.50, 0.85, 0.34),
	"summon": Color(0.75, 0.52, 0.99),
}

## ===== 档位参数（tier 0 = 关闭）=====
const TIER_AMOUNT: Array[int] = [0, 10, 20, 34]              # CPUParticles2D.amount
const TIER_RADIUS: Array[float] = [0.0, 22.0, 34.0, 48.0]    # 环半径（防御圈/符文环/元素环）
const TIER_ALPHA: Array[float] = [0.0, 0.15, 0.24, 0.34]     # 脚下光晕不透明度
const TIER_GLOW_SCALE: Array[float] = [0.0, 0.85, 1.2, 1.55] # 光晕缩放（64px 渐变图放大）
const TIER_ROT_SPEED: Array[float] = [0.0, 24.0, 40.0, 60.0] # 符文/元素环转速（deg/s）
const TIER_STREAM_SPEED: Array[float] = [0.0, 34.0, 56.0, 88.0]  # 拖尾粒子速度

## ===== 强度阈值（0/1/2/3 档；强度定义见 _strength）=====
const FLOW_THRESHOLDS := {
	"fire": [10.0, 30.0, 60.0],
	"ice": [10.0, 30.0, 60.0],
	"lightning": [10.0, 30.0, 60.0],
	"poison": [10.0, 30.0, 60.0],
	"summon": [10.0, 30.0, 60.0],
	"attack_speed": [30.0, 70.0, 150.0],
	"speed": [30.0, 70.0, 150.0],
	"crit": [8.0, 18.0, 35.0],
	"defense": [10.0, 30.0, 60.0],
	"lifesteal": [1.5, 3.0, 5.0],
	"cooldown": [8.0, 25.0, 60.0],
	"max_hp": [20.0, 60.0, 120.0],
}
## 同档位时主色优先级（元素流在前）
const FLOW_ORDER: Array[String] = [
	"fire", "ice", "lightning", "poison", "summon",
	"attack_speed", "crit", "defense", "lifesteal", "speed", "cooldown", "max_hp",
]

const REFRESH_INTERVAL := 0.25
const GLOW_SIZE := 64
const DOT_SIZE := 8
## 雷云/冰霜专属层配色（程序化，无贴图）
const CLOUD_COLOR := Color(0.30, 0.33, 0.40, 0.80)
const BOLT_COLOR := Color(1.0, 0.96, 0.72)
const FOG_ALPHA := 0.42
const ICE_SHARD_COLOR := Color(0.82, 0.94, 1.0, 0.95)
const ICE_CRYSTAL_COLOR := Color(0.72, 0.90, 1.0, 0.90)

var _glow: Sprite2D
var _defense_ring: Line2D
var _ice_crystals: Node2D
var _ice_shards: CPUParticles2D
var _layers: Dictionary = {}       # flow_key -> CPUParticles2D
var _flow_state: Dictionary = {}   # flow_key -> {tier, strength, color}
var _dominant_key := ""
var _dominant_tier := 0
var _refresh_timer := 0.0
var _ring_angle := 0.0
var _trail_dir := Vector2.DOWN
var _bolt_timer := 0.6

static var _dot_tex: Texture2D
static var _glow_tex: Texture2D


func _ready() -> void:
	# 玩家本体 z=1，地面背景 z=-5：光环放 0 层（脚下），低于玩家、高于地面
	z_index = -1
	position = Vector2(0, 8)  # 脚底偏移
	_glow = Sprite2D.new()
	_glow.name = "Glow"
	_glow.texture = _get_glow_texture()
	_glow.visible = false
	_glow.z_index = -1
	add_child(_glow)
	for key in FLOW_ORDER:
		var p := _make_emitter(_emitter_kind(key), _flow_color(key))
		p.name = "Em_" + key
		p.emitting = false
		if _emitter_kind(key) == "cloud":
			p.position = Vector2(0, -26)  # 雷云悬浮头顶
		add_child(p)
		_layers[key] = p
	# 冰霜专属层：结晶折线（5 簇）+ 碎片飞溅
	_ice_crystals = Node2D.new()
	_ice_crystals.name = "IceCrystals"
	_ice_crystals.visible = false
	_ice_crystals.z_index = -1
	add_child(_ice_crystals)
	for i in 5:
		_ice_crystals.add_child(_build_crystal())
	_ice_shards = _make_emitter("shards", ICE_SHARD_COLOR)
	_ice_shards.name = "IceShards"
	_ice_shards.emitting = false
	_ice_shards.visible = false
	add_child(_ice_shards)
	_defense_ring = Line2D.new()
	_defense_ring.name = "DefenseRing"
	_defense_ring.width = 2.5
	_defense_ring.closed = true
	_defense_ring.default_color = FLOW_COLORS["defense"]
	_defense_ring.visible = false
	_defense_ring.z_index = -1
	add_child(_defense_ring)
	refresh()


func _process(delta: float) -> void:
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = REFRESH_INTERVAL
		refresh()
	_update_trail()
	_update_rings(delta)
	# 雷云：按档位频率劈闪电
	var ltier := int(_flow_state.get("lightning", {}).get("tier", 0))
	if ltier > 0:
		_bolt_timer -= delta
		if _bolt_timer <= 0.0:
			_bolt_timer = maxf(1.5 - 0.3 * float(ltier), 0.45)
			_spawn_bolt()
	# 冰晶缓慢旋转
	if _ice_crystals.visible:
		_ice_crystals.rotation += delta * 0.10


## 重新读取 GameState 并刷新全部视觉（测试可直接调用）。
func refresh() -> void:
	if GameState == null or not is_instance_valid(GameState) or not (GameState.run is Dictionary):
		return
	var run: Dictionary = GameState.run
	if run.is_empty():
		return
	var atk := 0.0
	if GameState.has_method("aggregate_bonus"):
		atk = float(GameState.aggregate_bonus("atk"))
	var intensity := 1.0 + atk * 0.5  # 攻击加成整体提亮
	_flow_state.clear()
	_dominant_key = ""
	_dominant_tier = 0
	for key in FLOW_ORDER:
		var strength := _strength(key)
		var tier := 0
		if strength > 0.0:
			tier = _tier_for(strength, FLOW_THRESHOLDS[key])
		_flow_state[key] = {"tier": tier, "strength": strength, "color": _flow_color(key)}
		if tier > _dominant_tier:
			_dominant_tier = tier
			_dominant_key = key
	_apply_visuals(intensity)


## 测试/调试接口：某流派当前档位/强度/颜色。
func flow_info(key: String) -> Dictionary:
	return _flow_state.get(key, {"tier": 0, "strength": 0.0, "color": Color.WHITE})


## 测试/调试接口：某流派的粒子发射器。
func emitter_for(key: String) -> CPUParticles2D:
	return _layers.get(key)


func _apply_visuals(intensity: float) -> void:
	var t := _dominant_tier
	# 脚下光晕：主色跟随当前最高档位流派
	if t > 0 and _dominant_key != "":
		var c: Color = _flow_state[_dominant_key]["color"]
		_glow.visible = true
		_glow.modulate = Color(c.r, c.g, c.b, minf(TIER_ALPHA[t] * intensity, 0.5))
		_glow.scale = Vector2.ONE * (TIER_GLOW_SCALE[t] * (1.0 + 0.06 * intensity))
	else:
		_glow.visible = false
	# 防御盾圈
	var dtier := int(_flow_state.get("defense", {}).get("tier", 0))
	_defense_ring.visible = dtier > 0
	if dtier > 0:
		_defense_ring.default_color = Color(0.36, 0.62, 1.0, 0.28 + 0.15 * float(dtier))
		_defense_ring.points = _circle_points(TIER_RADIUS[dtier] + 6.0, 33)
	# 各流派粒子发射器
	for key in FLOW_ORDER:
		var st: Dictionary = _flow_state[key]
		var tier := int(st["tier"])
		var p: CPUParticles2D = _layers[key]
		var kind := _emitter_kind(key)
		if kind == "cloud":
			p.color = CLOUD_COLOR
		elif kind == "fog":
			var fc: Color = st["color"]
			p.color = Color(fc.r, fc.g, fc.b, FOG_ALPHA)
		else:
			p.color = st["color"]
		if tier <= 0:
			p.visible = false
			p.emitting = false
			continue
		p.visible = true
		p.emitting = true
		p.amount = int(float(TIER_AMOUNT[tier]) * intensity)
		match kind:
			"orbit":
				p.emission_sphere_radius = TIER_RADIUS[tier]
			"cloud":
				p.emission_sphere_radius = 10.0 + TIER_RADIUS[tier] * 0.25
			"fog":
				p.emission_sphere_radius = 22.0 + TIER_RADIUS[tier] * 0.5
			"spark":
				p.emission_sphere_radius = 10.0 + TIER_RADIUS[tier] * 0.4
				p.initial_velocity_min = 15.0 + 5.0 * float(tier)
				p.initial_velocity_max = 50.0 + 14.0 * float(tier)
			"stream":
				p.initial_velocity_min = TIER_STREAM_SPEED[tier] * 0.5
				p.initial_velocity_max = TIER_STREAM_SPEED[tier]
			"flyin":
				p.emission_sphere_radius = TIER_RADIUS[tier] + 34.0
				p.initial_velocity_min = -(28.0 + 14.0 * float(tier))
				p.initial_velocity_max = -(12.0 + 8.0 * float(tier))
	# 冰霜专属层：结晶可见度 + 碎片
	var itier := int(_flow_state.get("ice", {}).get("tier", 0))
	_ice_crystals.visible = itier > 0
	if itier > 0:
		_ice_crystals.modulate = Color(1.0, 1.0, 1.0, 0.30 + 0.18 * float(itier))
	_ice_shards.visible = itier > 0
	_ice_shards.emitting = itier > 0
	if itier > 0:
		_ice_shards.amount = int(float(TIER_AMOUNT[itier]) * 0.8)
		_ice_shards.emission_sphere_radius = TIER_RADIUS[itier] + 16.0


## 拖尾：粒子方向 = 玩家移动反方向
func _update_trail() -> void:
	var player := get_parent()
	if player == null or not (player is Node2D):
		return
	var vel: Variant = player.get("velocity")
	if vel is Vector2 and (vel as Vector2).length_squared() > 1.0:
		_trail_dir = (vel as Vector2).normalized()
	for key in ["attack_speed", "speed"]:
		var p: CPUParticles2D = _layers.get(key)
		if p != null and p.visible:
			p.direction = -_trail_dir
			p.position = -_trail_dir * 6.0


## 符文/元素环缓慢旋转
func _update_rings(delta: float) -> void:
	_ring_angle += delta * 60.0
	for key in FLOW_ORDER:
		if _emitter_kind(key) != "orbit":
			continue
		var st: Dictionary = _flow_state.get(key, {})
		var tier := int(st.get("tier", 0))
		if tier <= 0:
			continue
		var p: CPUParticles2D = _layers.get(key)
		if p != null:
			p.rotation = deg_to_rad(_ring_angle) * TIER_ROT_SPEED[tier] / 60.0


func _strength(key: String) -> float:
	if GameState == null or not (GameState.run is Dictionary):
		return 0.0
	var run: Dictionary = GameState.run
	var bonus: Dictionary = run.get("synergy_bonus", {})
	match key:
		"fire", "ice", "lightning", "poison", "summon":
			return float(bonus.get(key, 0.0)) * 100.0
		"attack_speed":
			return float(GameState.aggregate_bonus("attack_speed")) * 100.0
		"speed":
			return float(GameState.aggregate_bonus("speed")) * 100.0
		"crit":
			var chance := float(run.get("crit_chance", 0.03))
			var dmg_bonus := float(run.get("crit_dmg_bonus", 1.5))
			return (chance - 0.03) * 100.0 + (dmg_bonus - 1.5) * 50.0
		"defense":
			return float(GameState.aggregate_bonus("defense")) * 100.0
		"lifesteal":
			return float(run.get("lifesteal", 0.0)) * 100.0 \
				+ float(bonus.get("lifesteal", 0.0)) * 100.0
		"cooldown":
			return float(GameState.aggregate_bonus("cooldown")) * 100.0
		"max_hp":
			return float(bonus.get("max_hp", 0.0))
	return 0.0


func _tier_for(strength: float, thresholds: Array) -> int:
	var tier := 0
	for i in thresholds.size():
		if strength >= float(thresholds[i]):
			tier = i + 1
	return tier


func _emitter_kind(key: String) -> String:
	match key:
		"attack_speed", "speed":
			return "stream"
		"crit":
			return "spark"
		"lifesteal":
			return "flyin"
		"lightning":
			return "cloud"
		"ice":
			return "fog"
		_:
			return "orbit"


func _flow_color(key: String) -> Color:
	if key in FLOW_COLORS:
		return FLOW_COLORS[key]
	return _element_color(key)


## 元素流颜色：优先 UiTheme.ELEMENT（只读契约），兜底本地表
static func _element_color(key: String) -> Color:
	var el = UiTheme.ELEMENT.get(key)
	if el != null and el is Color:
		return el
	return ELEMENT_FALLBACK.get(key, Color.WHITE)


func _make_emitter(kind: String, color: Color) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = _get_dot_texture()
	p.color = color
	p.emitting = false
	p.gravity = Vector2.ZERO
	p.direction = Vector2.UP
	p.spread = 180.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.5
	p.amount = 1  # 4.7 要求 amount >= 1；未 emitting 时不产生粒子
	match kind:
		"orbit":  # 符文/元素环：球面发射、零速度 → 静止点环，节点旋转模拟环绕
			p.lifetime = 2.2
			p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE_SURFACE
			p.emission_sphere_radius = 30.0
			p.initial_velocity_min = 0.0
			p.initial_velocity_max = 0.0
		"spark":  # 暴击星点：玩家周围小范围浮动
			p.lifetime = 0.7
			p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
			p.emission_sphere_radius = 12.0
			p.initial_velocity_min = 20.0
			p.initial_velocity_max = 60.0
		"stream":  # 拖尾流线：移动反方向喷射
			p.lifetime = 0.5
			p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
			p.emission_rect_extents = Vector2(3.0, 10.0)
			p.spread = 22.0
			p.initial_velocity_min = 30.0
			p.initial_velocity_max = 60.0
		"flyin":  # 吸血飞入：环上生成、负速度 → 向玩家中心汇聚
			p.lifetime = 1.1
			p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE_SURFACE
			p.emission_sphere_radius = 60.0
			p.initial_velocity_min = -40.0
			p.initial_velocity_max = -20.0
		"cloud":  # 雷云：暗灰云团粒子悬浮头顶
			p.lifetime = 2.5
			p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
			p.emission_sphere_radius = 13.0
			p.initial_velocity_min = 3.0
			p.initial_velocity_max = 10.0
			p.scale_amount_min = 2.8
			p.scale_amount_max = 4.2
			p.color = CLOUD_COLOR
		"fog":  # 冰雾：轻柔漂移
			p.lifetime = 1.6
			p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
			p.emission_sphere_radius = 26.0
			p.initial_velocity_min = 6.0
			p.initial_velocity_max = 18.0
			p.spread = 120.0
			p.scale_amount_min = 2.2
			p.scale_amount_max = 3.6
		"shards":  # 冰晶碎片飞溅
			p.lifetime = 0.8
			p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE_SURFACE
			p.emission_sphere_radius = 30.0
			p.initial_velocity_min = 30.0
			p.initial_velocity_max = 100.0
			p.scale_amount_min = 0.7
			p.scale_amount_max = 1.7
			p.color = ICE_SHARD_COLOR
	return p


## 程序化分叉闪电折线（Line2D 锯齿 + 随机抖动）
func _spawn_bolt() -> void:
	var tier := int(_flow_state.get("lightning", {}).get("tier", 0))
	if tier <= 0:
		return
	var from := Vector2(randf_range(-8.0, 8.0), -26.0)  # 云下
	var angle := randf() * TAU
	var reach := TIER_RADIUS[tier] * randf_range(0.9, 1.25)
	var to := Vector2.from_angle(angle) * reach
	var bolt := Line2D.new()
	bolt.name = "Bolt"
	bolt.width = 2.0 + 0.5 * float(tier)
	bolt.default_color = BOLT_COLOR
	bolt.z_index = -1
	bolt.points = _fork_points(from, to, tier)
	add_child(bolt)
	var tw := create_tween()
	tw.tween_property(bolt, "modulate:a", 0.0, 0.30)
	tw.tween_callback(bolt.queue_free)
	# 分叉支线（档位 >= 2）
	if tier >= 2:
		for i in tier - 1:
			var mid: Vector2 = bolt.points[randi_range(1, bolt.points.size() - 2)]
			var fork_to := mid + Vector2.from_angle(randf() * TAU) * randf_range(8.0, 18.0)
			var fork := Line2D.new()
			fork.name = "BoltFork"
			fork.width = 1.3
			fork.default_color = Color(1.0, 0.90, 0.55, 1.0)
			fork.z_index = -1
			fork.points = PackedVector2Array([mid, fork_to])
			add_child(fork)
			var ftw := create_tween()
			ftw.tween_property(fork, "modulate:a", 0.0, 0.26)
			ftw.tween_callback(fork.queue_free)
	# 电光脉冲环（档位 >= 2）
	if tier >= 2:
		var pulse := Line2D.new()
		pulse.name = "BoltPulse"
		pulse.width = 1.6
		pulse.default_color = Color(1.0, 0.92, 0.60, 0.90)
		pulse.closed = true
		pulse.points = _circle_points(10.0, 24)
		pulse.z_index = -1
		add_child(pulse)
		var pt := create_tween()
		pt.set_parallel(true)
		pt.tween_property(pulse, "scale", Vector2.ONE * (TIER_RADIUS[tier] / 10.0), 0.26)
		pt.tween_property(pulse, "modulate:a", 0.0, 0.26)
		pt.chain().tween_callback(pulse.queue_free)


func _fork_points(from: Vector2, to: Vector2, tier: int) -> PackedVector2Array:
	var pts := PackedVector2Array([from])
	var dir := (to - from).normalized()
	var perp := dir.orthogonal()
	var n := 3 + tier  # 4-6 段锯齿
	for i in n:
		var t := float(i + 1) / float(n)
		var base := from.lerp(to, t)
		var wob := sin(float(i) * 1.7) * perp * (1.0 + float(tier)) * (1.0 - t * 0.5)
		pts.append(base + wob * randf_range(0.6, 1.4) + perp * randf_range(-1.5, 1.5))
	return pts


## 程序化冰晶折线：随机角度/长度的小晶簇（Line2D 闭合多边形）
func _build_crystal() -> Line2D:
	var shard := Line2D.new()
	shard.width = 1.6
	shard.closed = true
	shard.default_color = ICE_CRYSTAL_COLOR
	var a := randf() * TAU
	var dir := Vector2.from_angle(a)
	var perp := dir.orthogonal()
	var len := randf_range(9.0, 16.0)
	var pts := PackedVector2Array()
	pts.append(dir * -len * 0.4 + perp * randf_range(-2.0, 2.0))
	pts.append(dir * len * 0.25 + perp * randf_range(-2.5, 2.5))
	pts.append(dir * len * 0.75 + perp * randf_range(-1.0, 1.0))
	pts.append(dir * len)
	pts.append(dir * len * 0.55 + perp * randf_range(3.0, 6.0))  # 小分叉
	shard.points = pts
	shard.position = Vector2.from_angle(randf() * TAU) * randf_range(18.0, 34.0)
	return shard


func _circle_points(radius: float, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments + 1:
		var a := TAU * float(i) / float(segments)
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts


static func _get_dot_texture() -> Texture2D:
	if _dot_tex == null:
		_dot_tex = _make_radial(DOT_SIZE, 1.6)
	return _dot_tex


static func _get_glow_texture() -> Texture2D:
	if _glow_tex == null:
		_glow_tex = _make_radial(GLOW_SIZE, 2.2)
	return _glow_tex


## 运行时生成柔和径向渐变（白色 alpha 衰减，粒子/光晕用 modulate 着色）
static func _make_radial(size: int, falloff: float) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half := float(size) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(float(x) + 0.5 - half, float(y) + 0.5 - half).length() / half
			var a := pow(clampf(1.0 - d, 0.0, 1.0), falloff)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)

extends Node
## 复合特效总控（Agent F）：由 GameRoot 实例化并挂载，统一监听 EventBus 信号。
## 产出：按 kind 分发的多层复合特效（贴图粒子主爆点 + 扩散环 + 烟雾/碎屑 + 闪光）/
## 伤害飘字 / 受击白闪 / 震屏 / 慢动作。
## 素材：assets/fx/kenney/（Kenney Particle Pack, CC0）512x512 透明贴图，
## 经 CPUParticles2D.texture 加载，scale_amount 调至 0.03~0.35 使用。
## 契约：特效一律由本节点产出，其他模块禁止自行 new 粒子。

const ParticleBurstScene: PackedScene = preload("res://scenes/fx/particle_burst.tscn")
const ExplosionScene: PackedScene = preload("res://scenes/fx/explosion.tscn")
const DamageNumberScene: PackedScene = preload("res://scenes/fx/damage_number.tscn")

const KIND_COLORS := {
	"fire": Color(1.0, 0.45, 0.15),
	"ice": Color(0.45, 0.78, 1.0),
	"lightning": Color(1.0, 0.86, 0.25),
	"poison": Color(0.45, 0.9, 0.3),
	"blade": Color(0.92, 0.94, 1.0),
	"heal": Color(0.45, 1.0, 0.55),
	"water": Color(0.35, 0.62, 1.0),
	"nature": Color(0.5, 0.95, 0.4),
	"light": Color(1.0, 0.95, 0.6),
	"void": Color(0.72, 0.45, 1.0),
	"buff": Color(1.0, 0.55, 0.8),
	"gold": Color(1.0, 0.84, 0.2),
}
const DEFAULT_KIND := "fire"
const CRIT_GOLD := Color(1.0, 0.84, 0.2)

const BURST_AMOUNT_MIN := 16
const BURST_AMOUNT_MAX := 32
const RING_SCALE := 2.6
const RING_DURATION := 0.3
const SHAKE_SMALL := 3.0
const SHAKE_PLAYER_HIT := 2.5
const FLASH_COLOR := Color(3.0, 3.0, 3.0, 1.0)
const SLOW_MO_MIN_FACTOR := 0.05

const FX_DIR := "res://assets/fx/kenney/"

## 每 kind 配方：flash=闪光贴图；ring=[扩散环目标缩放, 持续时间, 线宽]；
## layers=贴图粒子层（tex=候选贴图、amount=[min,max] 总粒子数、scale=[min,max] 512 贴图缩放、
## vel=[min,max] 初速、grav=重力、life=[min,max] 寿命、color=覆盖色（缺省用 kind 色）、
## 每 kind 配方：flash=闪光贴图；ring=[扩散环目标缩放, 持续时间, 线宽]；ring_color=可选环色（缺省 kind 色）。
## shape=程序化形态组件（type 分发：lightning/ice/ripples/beam/void/arc/cross/coins），用 Line2D/Sprite2D + Tween 勾勒形状。
## layers=贴图粒子层（tex=候选贴图、amount=[min,max] 总粒子数、scale=[min,max] 512 贴图缩放、
## vel=[min,max] 初速、grav=重力、life=[min,max] 寿命、color=覆盖色（缺省用 kind 色）、
## add=加法混合、grow=粒子随时间放大（缺省收缩））。
## 层扩展字段（向后兼容，缺省不影响旧配方）：dir=定向发射方向（缺省 360° 全向）、
## spread=绕 dir 的角度（缺省 30°）、spin=[min,max] 自旋角速度（度/秒）、angle=[min,max] 初始随机角度、
## inward=内向加速度（负 radial_accel，粒子被拉向中心）、swirl=切向加速度（螺旋）、offset=发射点相对落点偏移。
const KIND_RECIPES := {
	"lightning": {
		"flash": "light_03",
		"ring": [2.2, 0.22, 2.5],
		"shape": {
			"type": "lightning",
			"cloud": {"tex": ["smoke_08", "smoke_09", "smoke_10"], "amount": [3, 5], "scale": [0.28, 0.35], "vel": [6, 16], "grav": Vector2(0, -10), "life": [1.5, 2.0], "color": Color(0.2, 0.2, 0.27, 0.9), "grow": true, "offset": Vector2(0, -72)},
			"bolt": {"height": 72.0, "width": 3.0, "jitter": 12.0, "segments": 14, "branches": 2},
			"impact": {"tex": ["spark_01", "spark_03", "spark_05"], "amount": [10, 16], "scale": [0.04, 0.09], "vel": [180, 380], "grav": Vector2(0, 140), "life": [0.25, 0.45], "add": true},
		},
		"layers": [],
	},
	"fire": {
		"flash": "fire_01",
		"ring": [2.0, 0.2, 2.0],
		"layers": [
			{"tex": ["fire_01", "flame_03", "flame_04"], "amount": [10, 16], "scale": [0.08, 0.16], "vel": [90, 190], "dir": Vector2(0, -1), "spread": 18, "grav": Vector2(0, -140), "life": [0.4, 0.65], "add": true},
			{"tex": ["spark_01", "spark_02"], "amount": [8, 13], "scale": [0.04, 0.08], "vel": [160, 300], "dir": Vector2(0, -1), "spread": 25, "grav": Vector2(0, -80), "life": [0.5, 0.85], "add": true},
			{"tex": ["smoke_01", "smoke_02", "smoke_03"], "amount": [5, 8], "scale": [0.22, 0.32], "vel": [25, 60], "dir": Vector2(0, -1), "spread": 40, "grav": Vector2(0, -30), "life": [0.9, 1.3], "color": Color(0.3, 0.26, 0.28, 0.85), "grow": true},
		],
	},
	"ice": {
		"flash": "circle_02",
		"ring": [2.2, 0.35, 2.0],
		"shape": {"type": "ice", "clusters": 2, "size": 20.0},
		"layers": [
			{"tex": ["smoke_06", "smoke_07"], "amount": [4, 7], "scale": [0.24, 0.34], "vel": [18, 45], "grav": Vector2(0, -20), "life": [0.9, 1.4], "color": Color(0.62, 0.85, 1.0, 0.8), "grow": true},
			{"tex": ["spark_04", "spark_05", "star_03"], "amount": [9, 14], "scale": [0.04, 0.08], "vel": [150, 300], "grav": Vector2(0, 260), "life": [0.35, 0.6], "add": true},
		],
	},
	"poison": {
		"flash": "circle_05",
		"ring": [2.8, 0.5, 1.8],
		"layers": [
			{"tex": ["smoke_05", "smoke_06", "smoke_07"], "amount": [6, 10], "scale": [0.28, 0.35], "vel": [12, 34], "grav": Vector2(0, -15), "life": [1.3, 1.8], "color": Color(0.42, 0.75, 0.28, 0.75), "grow": true},
			{"tex": ["circle_04", "circle_05"], "amount": [5, 9], "scale": [0.04, 0.07], "vel": [30, 85], "dir": Vector2(0, -1), "spread": 35, "grav": Vector2(0, -40), "life": [0.8, 1.2], "add": true},
			{"tex": ["dirt_01", "dirt_02", "dirt_03"], "amount": [6, 10], "scale": [0.05, 0.09], "vel": [40, 110], "grav": Vector2(0, 260), "life": [0.5, 0.8], "color": Color(0.55, 0.85, 0.4, 1.0)},
		],
	},
	"blade": {
		"flash": "light_02",
		"ring": [1.8, 0.2, 2.5],
		"shape": {"type": "arc", "radius": 30.0},
		"layers": [
			{"tex": ["slash_01", "slash_02", "slash_03", "slash_04"], "amount": [6, 10], "scale": [0.1, 0.18], "vel": [160, 270], "dir": Vector2(1, 0), "spread": 55, "grav": Vector2.ZERO, "life": [0.22, 0.35], "add": true, "spin": [260, 520], "angle": [0, 360]},
			{"tex": ["spark_01", "spark_02"], "amount": [8, 13], "scale": [0.03, 0.06], "vel": [220, 420], "dir": Vector2(1, 0), "spread": 40, "grav": Vector2(0, 300), "life": [0.3, 0.5], "add": true},
		],
	},
	"heal": {
		"flash": "light_01",
		"ring": [2.4, 0.45, 1.8],
		"shape": {"type": "cross", "arm": 26.0},
		"layers": [
			{"tex": ["star_01", "star_03", "star_05"], "amount": [7, 11], "scale": [0.05, 0.09], "vel": [30, 90], "dir": Vector2(0, -1), "spread": 35, "grav": Vector2(0, -30), "life": [0.7, 1.1], "add": true},
			{"tex": ["circle_02", "circle_03"], "amount": [4, 7], "scale": [0.08, 0.13], "vel": [25, 65], "grav": Vector2.ZERO, "life": [0.5, 0.8], "add": true},
		],
	},
	"water": {
		"flash": "circle_02",
		"ring": [2.4, 0.35, 2.0],
		"shape": {"type": "ripples", "count": 3, "width": 2.0, "max_scale": 2.4, "stagger": 0.12},
		"layers": [
			{"tex": ["circle_04", "trace_03"], "amount": [10, 16], "scale": [0.05, 0.09], "vel": [140, 300], "dir": Vector2(1, 0.45), "spread": 130, "grav": Vector2(0, 420), "life": [0.5, 0.8], "add": true},
			{"tex": ["circle_03", "circle_02"], "amount": [5, 9], "scale": [0.05, 0.09], "vel": [50, 120], "dir": Vector2(0, -1), "spread": 70, "grav": Vector2(0, 240), "life": [0.35, 0.55], "add": true},
		],
	},
	"nature": {
		"flash": "light_01",
		"ring": [2.2, 0.4, 1.8],
		"layers": [
			{"tex": ["star_01", "star_02", "star_03"], "amount": [8, 13], "scale": [0.05, 0.1], "vel": [25, 75], "grav": Vector2(0, 150), "life": [0.8, 1.2], "spin": [120, 300], "color": Color(0.5, 0.95, 0.4, 1.0)},
			{"tex": ["dirt_01", "dirt_02"], "amount": [5, 9], "scale": [0.05, 0.08], "vel": [90, 200], "grav": Vector2(0, 340), "life": [0.4, 0.65], "color": Color(0.52, 0.38, 0.26, 1.0)},
			{"tex": ["smoke_03", "smoke_04"], "amount": [4, 7], "scale": [0.22, 0.32], "vel": [12, 35], "grav": Vector2(0, -15), "life": [1.0, 1.5], "color": Color(0.62, 0.95, 0.5, 0.75), "grow": true},
		],
	},
	"light": {
		"flash": "light_03",
		"ring": [2.2, 0.3, 2.0],
		"shape": {"type": "beam", "height": 118.0, "bars": [[16.0, 0.35], [7.0, 1.0]]},
		"layers": [
			{"tex": ["light_01", "light_02"], "amount": [6, 10], "scale": [0.09, 0.16], "vel": [40, 110], "dir": Vector2(0, 1), "spread": 20, "grav": Vector2(0, 40), "life": [0.5, 0.8], "add": true},
			{"tex": ["star_01", "star_02"], "amount": [7, 11], "scale": [0.04, 0.07], "vel": [50, 120], "dir": Vector2(0, -1), "spread": 30, "grav": Vector2(0, -25), "life": [0.6, 0.9], "add": true},
		],
	},
	"void": {
		"flash": "circle_03",
		"ring": [2.6, 0.5, 2.5],
		"shape": {"type": "void", "orbs": 4, "radius": 46.0},
		"layers": [
			{"tex": ["twirl_01", "twirl_02", "twirl_03"], "amount": [5, 8], "scale": [0.1, 0.16], "vel": [25, 70], "grav": Vector2.ZERO, "life": [0.6, 0.9], "add": true, "inward": true, "swirl": 110.0, "spin": [120, 260]},
			{"tex": ["spark_05", "spark_06", "spark_07"], "amount": [9, 14], "scale": [0.04, 0.08], "vel": [60, 160], "grav": Vector2.ZERO, "life": [0.4, 0.7], "add": true, "inward": true, "swirl": 150.0},
		],
	},
	"buff": {
		"flash": "light_02",
		"ring": [2.6, 0.4, 2.6],
		"ring_color": Color(1.0, 0.85, 0.4),
		"layers": [
			{"tex": ["star_06", "star_07"], "amount": [8, 13], "scale": [0.05, 0.09], "vel": [40, 110], "dir": Vector2(0, -1), "spread": 35, "grav": Vector2(0, -50), "life": [0.8, 1.2], "add": true},
			{"tex": ["spark_01", "spark_02", "spark_03"], "amount": [7, 11], "scale": [0.03, 0.06], "vel": [70, 170], "grav": Vector2(0, 40), "life": [0.45, 0.7], "add": true},
		],
	},
	"gold": {
		"flash": "light_01",
		"ring": [2.4, 0.3, 2.2],
		"ring_color": Color(1.0, 0.85, 0.4),
		"shape": {"type": "coins", "coins": 3, "texs": ["star_01", "circle_01"]},
		"layers": [
			{"tex": ["star_01", "star_02", "circle_01"], "amount": [10, 15], "scale": [0.05, 0.09], "vel": [120, 260], "dir": Vector2(0, -1), "spread": 100, "grav": Vector2(0, 420), "life": [0.7, 1.0], "add": true, "spin": [240, 480]},
			{"tex": ["smoke_09", "smoke_10"], "amount": [3, 6], "scale": [0.22, 0.3], "vel": [15, 40], "grav": Vector2(0, -20), "life": [0.9, 1.3], "color": Color(0.9, 0.75, 0.35, 0.7), "grow": true},
		],
	},
}

## 施法瞬间配方（fx_cast）：1 个闪光贴图 + 2~4 粒元素小粒子沿施法方向喷出。
## 寿命 0.15~0.3s，无扩散环无烟雾；texture 512 需 scale 调小。
const CAST_RECIPES := {
	"fire": {"flash": "muzzle_01", "tex": ["fire_02", "flame_03"], "amount": [2, 4], "scale": [0.06, 0.12], "vel": [140, 280], "life": [0.15, 0.25], "add": true},
	"ice": {"flash": "muzzle_02", "tex": ["star_01", "spark_04"], "amount": [2, 4], "scale": [0.05, 0.1], "vel": [150, 300], "life": [0.16, 0.28], "add": true},
	"lightning": {"flash": "muzzle_05", "tex": ["spark_01", "spark_03"], "amount": [2, 4], "scale": [0.04, 0.09], "vel": [200, 380], "life": [0.12, 0.22], "add": true},
	"poison": {"flash": "muzzle_04", "tex": ["dirt_01", "circle_04"], "amount": [2, 4], "scale": [0.04, 0.08], "vel": [110, 240], "life": [0.18, 0.3]},
	"blade": {"flash": "muzzle_03", "tex": ["slash_01", "spark_01"], "amount": [2, 4], "scale": [0.05, 0.11], "vel": [160, 320], "life": [0.12, 0.22], "add": true},
	"water": {"flash": "muzzle_02", "tex": ["circle_04", "trace_03"], "amount": [2, 4], "scale": [0.04, 0.09], "vel": [130, 270], "life": [0.15, 0.26], "add": true},
	"nature": {"flash": "muzzle_04", "tex": ["star_02", "dirt_01"], "amount": [2, 4], "scale": [0.04, 0.09], "vel": [110, 240], "life": [0.16, 0.28]},
	"light": {"flash": "muzzle_01", "tex": ["star_01", "light_02"], "amount": [2, 4], "scale": [0.05, 0.1], "vel": [120, 250], "life": [0.14, 0.24], "add": true},
	"void": {"flash": "muzzle_05", "tex": ["spark_05", "twirl_02"], "amount": [2, 4], "scale": [0.04, 0.09], "vel": [120, 260], "life": [0.14, 0.26], "add": true},
	"heal": {"flash": "muzzle_01", "tex": ["star_03", "circle_02"], "amount": [2, 4], "scale": [0.04, 0.09], "vel": [90, 200], "life": [0.16, 0.28], "add": true},
	"buff": {"flash": "muzzle_03", "tex": ["star_06", "spark_02"], "amount": [2, 4], "scale": [0.04, 0.09], "vel": [90, 190], "life": [0.18, 0.3], "add": true},
	"gold": {"flash": "muzzle_01", "tex": ["star_01", "spark_02"], "amount": [2, 4], "scale": [0.04, 0.09], "vel": [110, 230], "life": [0.15, 0.26], "add": true},
}

## 弹道命中配方（fx_hit）：单层 3~6 粒小粒子按元素特征迸溅，寿命 0.2~0.4s。
## 无扩散环无烟雾；DOT tick 复用本表（节流 0.35s）。
const HIT_RECIPES := {
	"fire": [
		{"tex": ["fire_02", "spark_01"], "amount": [3, 6], "scale": [0.05, 0.1], "vel": [90, 220], "grav": Vector2(0, 160), "life": [0.2, 0.35], "add": true},
	],
	"ice": [
		{"tex": ["star_01", "spark_04"], "amount": [3, 6], "scale": [0.04, 0.09], "vel": [110, 240], "grav": Vector2(0, 180), "life": [0.22, 0.4], "add": true},
	],
	"lightning": [
		{"tex": ["spark_01", "spark_03"], "amount": [4, 8], "scale": [0.04, 0.08], "vel": [160, 320], "grav": Vector2(0, 60), "life": [0.18, 0.3], "add": true},
	],
	"poison": [
		{"tex": ["dirt_01", "circle_04"], "amount": [3, 5], "scale": [0.04, 0.08], "vel": [70, 180], "grav": Vector2(0, 220), "life": [0.25, 0.4]},
	],
	"blade": [
		{"tex": ["slash_01", "spark_01"], "amount": [3, 6], "scale": [0.05, 0.11], "vel": [130, 280], "grav": Vector2.ZERO, "life": [0.18, 0.32], "add": true},
	],
	"water": [
		{"tex": ["circle_04", "trace_03"], "amount": [3, 6], "scale": [0.04, 0.09], "vel": [100, 240], "grav": Vector2(0, 280), "life": [0.22, 0.38], "add": true},
	],
	"nature": [
		{"tex": ["star_02", "dirt_01"], "amount": [3, 6], "scale": [0.04, 0.08], "vel": [80, 200], "grav": Vector2(0, 260), "life": [0.22, 0.36]},
	],
	"light": [
		{"tex": ["star_01", "light_02"], "amount": [3, 6], "scale": [0.05, 0.1], "vel": [80, 200], "grav": Vector2.ZERO, "life": [0.2, 0.34], "add": true},
	],
	"void": [
		{"tex": ["spark_05", "twirl_02"], "amount": [3, 6], "scale": [0.04, 0.09], "vel": [90, 210], "grav": Vector2.ZERO, "life": [0.2, 0.35], "add": true},
	],
	"heal": [
		{"tex": ["star_03", "circle_02"], "amount": [3, 6], "scale": [0.04, 0.09], "vel": [60, 160], "grav": Vector2(0, -120), "life": [0.25, 0.4], "add": true},
	],
	"buff": [
		{"tex": ["star_06", "spark_02"], "amount": [3, 6], "scale": [0.04, 0.09], "vel": [60, 150], "grav": Vector2(0, -100), "life": [0.25, 0.4], "add": true},
	],
	"gold": [
		{"tex": ["star_01", "spark_02"], "amount": [3, 6], "scale": [0.04, 0.09], "vel": [80, 190], "grav": Vector2(0, 200), "life": [0.2, 0.35], "add": true},
	],
}

## 状态附着持续粒子配方（I-怪物状态附着特效）：
## 持续发射（one_shot=false, emitting=true），作为敌人子节点跟随移动；
## amount <= 12、每怪物 <= 3 个粒子节点，避免 30 怪同屏爆量。
const STATUS_ATTACH_RECIPES := {
	"burn": {
		"tex": ["flame_01", "flame_03"], "amount": 10, "scale": [0.06, 0.11],
		"vel": [16, 42], "dir": Vector2(0, -1), "spread": 20.0, "grav": Vector2(0, -70),
		"life": [0.35, 0.55], "add": true, "offset": Vector2(0, -5),
	},
	"water": {
		"tex": ["circle_04", "trace_03"], "amount": 8, "scale": [0.04, 0.08],
		"vel": [10, 30], "dir": Vector2(0, 1), "spread": 12.0, "grav": Vector2(0, 170),
		"life": [0.5, 0.75], "add": true, "offset": Vector2(0, -9),
	},
	"poison": {
		"tex": ["circle_04", "circle_05"], "amount": 6, "scale": [0.035, 0.06],
		"vel": [12, 30], "dir": Vector2(0, -1), "spread": 24.0, "grav": Vector2(0, -35),
		"life": [0.7, 1.05], "add": true,
	},
	"slow": {
		"tex": ["smoke_06", "smoke_07"], "amount": 5, "scale": [0.14, 0.22],
		"vel": [6, 16], "dir": Vector2(0, -1), "spread": 45.0, "grav": Vector2(0, -12),
		"life": [0.8, 1.2], "grow": true, "color": Color(0.55, 0.78, 1.0, 0.9), "offset": Vector2(0, 11),
	},
	"lightning": {
		"tex": ["spark_01", "spark_03"], "amount": 5, "scale": [0.03, 0.06],
		"vel": [45, 130], "spread": 360.0, "grav": Vector2(0, 30),
		"life": [0.18, 0.32], "add": true,
	},
	"ice": {
		"tex": ["star_01", "spark_04"], "amount": 6, "scale": [0.035, 0.065],
		"vel": [12, 42], "dir": Vector2(0, 1), "spread": 30.0, "grav": Vector2(0, 130),
		"life": [0.5, 0.9], "add": true,
	},
}

## 状态附着持续粒子（仅新增入口，不改动既有 _on_fx_* / KIND_RECIPES 逻辑）：
## 创建为 parent 的子节点（随 parent 移动），持续发射、循环；返回粒子节点供调用方命名/销毁。
static func spawn_status_particles(parent: Node, kind: String) -> CPUParticles2D:
	var recipe: Dictionary = STATUS_ATTACH_RECIPES.get(kind, STATUS_ATTACH_RECIPES["burn"])
	var tex_names: Array = recipe.get("tex", ["circle_04"])
	var tex: Texture2D = _get_tex(str(tex_names[randi() % tex_names.size()]))
	if tex == null:
		return null
	var p := CPUParticles2D.new()
	p.texture = tex
	p.position = recipe.get("offset", Vector2.ZERO)
	p.amount = mini(int(recipe.get("amount", 8)), 12)
	p.lifetime = randf_range(float(recipe.get("life", [0.4, 0.6])[0]), float(recipe.get("life", [0.4, 0.6])[1]))
	p.one_shot = false
	p.emitting = true
	p.explosiveness = 1.0
	p.spread = float(recipe.get("spread", 180.0))
	p.gravity = recipe.get("grav", Vector2.ZERO)
	var dir: Vector2 = recipe.get("dir", Vector2.ZERO)
	if dir != Vector2.ZERO:
		p.direction = dir.normalized()
	p.initial_velocity_min = float(recipe.get("vel", [20, 60])[0])
	p.initial_velocity_max = float(recipe.get("vel", [20, 60])[1])
	p.scale_amount_min = float(recipe.get("scale", [0.05, 0.1])[0])
	p.scale_amount_max = float(recipe.get("scale", [0.05, 0.1])[1])
	var curve := Curve.new()
	curve.clear_points()
	if recipe.get("grow", false):
		curve.add_point(Vector2(0.0, 0.6))
		curve.add_point(Vector2(1.0, 1.35))
	else:
		curve.add_point(Vector2(0.0, 1.0))
		curve.add_point(Vector2(1.0, 0.25))
	p.scale_amount_curve = curve
	if recipe.get("add", false):
		# 4.7 起 CPUParticles2D 无 blend_mode，加法混合用 CanvasItemMaterial
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		p.material = mat
	var base_color: Color = recipe.get("color", KIND_COLORS.get(kind, KIND_COLORS[DEFAULT_KIND]))
	var grad := Gradient.new()
	grad.set_color(0, Color(base_color, 0.95))
	grad.set_color(1, Color(base_color, 0.0))
	p.color_ramp = grad
	p.color = Color.WHITE
	parent.add_child(p)
	return p

static var _tex_cache: Dictionary = {}
static var _white_particle_texture: Texture2D

var _slow_mo_tween: Tween
var _dps_tier := 0
var _tier_timer := 0.0
var _kill_times: Array[float] = []
var _firework_timer := 0.0
var _aura_timer := 0.0
var _summon_auras: Dictionary = {}  # summon instance_id -> aura Node2D

func _ready() -> void:
	EventBus.fx_explosion.connect(_on_fx_explosion)
	EventBus.fx_explosion_scaled.connect(_on_fx_explosion_scaled)
	EventBus.fx_cast.connect(_on_fx_cast)
	EventBus.fx_hit.connect(_on_fx_hit)
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.fx_hit_flash.connect(_on_fx_hit_flash)
	EventBus.fx_heal_text.connect(_on_fx_heal_text)
	EventBus.fx_dot_text.connect(_on_fx_dot_text)
	EventBus.screen_shake.connect(_on_screen_shake)
	EventBus.slow_mo.connect(_on_slow_mo)
	EventBus.enemy_died.connect(_on_enemy_died)
	# 契约：player_hit 的监听方包含特效（受击反馈）
	EventBus.player_hit.connect(_on_player_hit)

func _process(delta: float) -> void:
	# 爽感档位（F11）：按 DPS 分档，档位越高特效越足
	_tier_timer -= delta
	if _tier_timer <= 0.0:
		_tier_timer = 0.5
		var dps: float = GameState.estimate_dps()
		_dps_tier = 0
		if dps >= 300.0:
			_dps_tier = 1
		if dps >= 800.0:
			_dps_tier = 2
		if dps >= 1500.0:
			_dps_tier = 3
	# 高火力金色粒子雨（档位 >= 2，每 2.5s 一次，随机位置）
	if _dps_tier >= 2:
		_firework_timer -= delta
		if _firework_timer <= 0.0:
			_firework_timer = 2.5
			EventBus.fx_explosion.emit(Vector2(randf_range(100, 1180), randf_range(80, 640)), "gold")
			if _dps_tier >= 3:
				EventBus.fx_explosion.emit(Vector2(randf_range(100, 1180), randf_range(80, 640)), "lightning")
	# A2 summon aura: refresh tier every 0.5s by summon school holdings (3/6/9)
	_aura_timer -= delta
	if _aura_timer <= 0.0:
		_aura_timer = 0.5
		_refresh_summon_auras()

## 施法瞬间（fx_cast）：1 个小型 muzzle 闪光 + 2~4 粒元素小粒子沿施法方向喷出；
## 无扩散环无烟雾，寿命 0.15~0.3s。
func _on_fx_cast(pos: Vector2, kind: String, dir: Vector2) -> void:
	var color: Color = KIND_COLORS.get(kind, KIND_COLORS[DEFAULT_KIND])
	var recipe: Dictionary = CAST_RECIPES.get(kind, CAST_RECIPES[DEFAULT_KIND])
	_spawn_flash(pos, color, str(recipe.get("flash", "muzzle_01")), 0.1, 0.16)
	for tex_name in recipe.get("tex", ["spark_01"]):
		_spawn_cast_particles(pos, dir.normalized(), color, str(tex_name), recipe)

## 弹道命中（fx_hit）：1 层 3~6 粒小粒子按元素特征迸溅，寿命 0.2~0.4s；无扩散环。
## DOT tick（中毒/燃烧）也复用本入口，由调用方节流。
func _on_fx_hit(pos: Vector2, kind: String) -> void:
	var color: Color = KIND_COLORS.get(kind, KIND_COLORS[DEFAULT_KIND])
	var layers: Array = HIT_RECIPES.get(kind, HIT_RECIPES[DEFAULT_KIND])
	for layer in layers:
		_spawn_tex_layer(pos, color, layer)

func _on_fx_explosion(pos: Vector2, kind: String) -> void:
	_play_explosion(pos, kind, 1.0)

func _on_fx_explosion_scaled(pos: Vector2, kind: String, radius: float) -> void:
	# 范围可视化：按实际 AOE 半径缩放粒子飞散与扩散环（范围变大肉眼可见）
	var scale_mult := 1.0
	if radius > 0.0:
		scale_mult = clampf(radius / 24.0, 0.45, 4.0)
	_play_explosion(pos, kind, scale_mult)

func _play_explosion(pos: Vector2, kind: String, scale_mult: float) -> void:
	var color: Color = KIND_COLORS.get(kind, KIND_COLORS[DEFAULT_KIND])
	var recipe: Dictionary = KIND_RECIPES.get(kind, KIND_RECIPES[DEFAULT_KIND])
	# 1. 中心闪光（单粒加法混合贴图粒子，快速扩张淡出）
	_spawn_flash(pos, color, str(recipe.get("flash", "light_01")), 0.22 * scale_mult, 0.32 * scale_mult)
	# 2. 贴图粒子层：主爆点 / 烟雾 / 碎屑，按 kind 配方逐层生成
	var layers: Array = recipe.get("layers", [])
	for layer in layers:
		_spawn_tex_layer(pos, color, layer, scale_mult)
	# 3. 形态化组件：按 kind 生成程序化折线/精灵（雷云闪电/冰晶/涟漪/光柱/吞噬/弧斩/十字/钱币）
	_spawn_shape(pos, color, recipe.get("shape", {}))
	# 4. 扩散环（程序化 Line2D，tween 缩放 + 淡出；可用 ring_color 覆盖环色）
	_spawn_ring(pos, recipe.get("ring_color", color), recipe.get("ring", [RING_SCALE, RING_DURATION, 2.0]), scale_mult)
	# 爆炸 0.1s 后触发小威力震屏
	var shake_power := SHAKE_SMALL
	if kind == "lightning":
		shake_power = SHAKE_SMALL + 1.2 * float(_school_holdings_of("lightning"))
	get_tree().create_timer(0.1).timeout.connect(_emit_shake.bind(shake_power))
	match kind:
		"poison":
			_spawn_poison_diffusion(pos, color, scale_mult)
		"ice":
			_spawn_ice_shards(pos, color, scale_mult)

## 中心闪光：单粒 CPUParticles2D，加法混合，scale 曲线扩张 + color_ramp 淡出。
func _spawn_flash(pos: Vector2, color: Color, tex_name: String, scale_min: float = 0.22, scale_max: float = 0.32) -> void:
	var tex: Texture2D = _get_tex(tex_name)
	if tex == null:
		return
	var p := CPUParticles2D.new()
	p.position = pos
	p.texture = tex
	p.amount = 1
	p.lifetime = 0.14
	p.one_shot = true
	p.explosiveness = 1.0
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 0.0
	p.scale_amount_min = scale_min
	p.scale_amount_max = scale_max
	var grow := Curve.new()
	grow.clear_points()
	grow.add_point(Vector2(0.0, 0.55))
	grow.add_point(Vector2(0.5, 1.25))
	grow.add_point(Vector2(1.0, 1.8))
	p.scale_amount_curve = grow
	# 4.7 起 CPUParticles2D 无 blend_mode，用 CanvasItemMaterial 加法混合实现发光
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = mat
	var grad := Gradient.new()
	grad.set_color(0, Color(color, 0.95))
	grad.set_color(1, Color(color, 0.0))
	p.color_ramp = grad
	p.color = Color.WHITE
	p.finished.connect(p.queue_free)
	add_child(p)

## 施法飞屑：单贴图 CPUParticles2D，沿 dir 方向喷出（spread 30°），寿命 0.15~0.3s。
func _spawn_cast_particles(pos: Vector2, dir: Vector2, base_color: Color, tex_name: String, recipe: Dictionary) -> void:
	var tex: Texture2D = _get_tex(tex_name)
	if tex == null:
		return
	var tex_names: Array = recipe.get("tex", ["spark_01"])
	var amount_range: Array = recipe.get("amount", [2, 4])
	var total_amount: int = randi_range(int(amount_range[0]), int(amount_range[1]))
	var per := maxi(1, int(ceil(float(total_amount) / float(tex_names.size()))))
	var vel_range: Array = recipe.get("vel", [120, 260])
	var scale_range: Array = recipe.get("scale", [0.05, 0.1])
	var life_range: Array = recipe.get("life", [0.15, 0.3])
	var p := CPUParticles2D.new()
	p.position = pos
	p.texture = tex
	p.amount = per
	p.lifetime = randf_range(float(life_range[0]), float(life_range[1]))
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = dir
	p.spread = 30.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = float(vel_range[0])
	p.initial_velocity_max = float(vel_range[1])
	p.scale_amount_min = float(scale_range[0])
	p.scale_amount_max = float(scale_range[1])
	var curve := Curve.new()
	curve.clear_points()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.25))
	p.scale_amount_curve = curve
	if recipe.get("add", false):
		# 4.7 起 CPUParticles2D 无 blend_mode，用 CanvasItemMaterial 加法混合实现发光
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		p.material = mat
	var grad := Gradient.new()
	grad.set_color(0, Color(base_color, 1.0))
	grad.set_color(1, Color(base_color, 0.0))
	p.color_ramp = grad
	p.color = Color.WHITE
	p.finished.connect(p.queue_free)
	add_child(p)

## 贴图粒子层：按 recipe 逐贴图拆分为独立 CPUParticles2D（同层贴图混合出层次感），
## 512 贴图以 scale_amount 0.03~0.35 渲染，one_shot 由 finished 自毁。
func _spawn_tex_layer(pos: Vector2, base_color: Color, recipe: Dictionary, scale_mult: float = 1.0) -> void:
	var tex_names: Array = recipe.get("tex", [])
	if tex_names.is_empty():
		return
	var amount_range: Array = recipe.get("amount", [8, 12])
	var total_amount: int = randi_range(int(amount_range[0]), int(amount_range[1]))
	var per := maxi(2, int(ceil(float(total_amount) / float(tex_names.size()))))
	var vel_range: Array = recipe.get("vel", [60, 180])
	var vel_mult: float = scale_mult
	var scale_range: Array = recipe.get("scale", [0.06, 0.12])
	var life_range: Array = recipe.get("life", [0.5, 0.7])
	var layer_color: Color = recipe.get("color", base_color)
	var additive: bool = recipe.get("add", false)
	var grow: bool = recipe.get("grow", false)
	var offset: Vector2 = recipe.get("offset", Vector2.ZERO)
	var emit_dir: Vector2 = recipe.get("dir", Vector2.ZERO)
	var spread_deg: float = 180.0 if emit_dir == Vector2.ZERO else float(recipe.get("spread", 30.0))
	var spin_range: Array = recipe.get("spin", [])
	var angle_range: Array = recipe.get("angle", [])
	var inward: bool = recipe.get("inward", false)
	var swirl: float = float(recipe.get("swirl", 0.0))
	for tex_name in tex_names:
		var tex: Texture2D = _get_tex(str(tex_name))
		if tex == null:
			continue
		var p := CPUParticles2D.new()
		p.position = pos + offset
		p.texture = tex
		p.amount = per
		p.lifetime = randf_range(float(life_range[0]), float(life_range[1]))
		p.one_shot = true
		p.explosiveness = 1.0
		p.spread = spread_deg
		p.gravity = recipe.get("grav", Vector2.ZERO)
		if emit_dir != Vector2.ZERO:
			p.direction = emit_dir.normalized()
		if not spin_range.is_empty():
			p.angular_velocity_min = float(spin_range[0])
			p.angular_velocity_max = float(spin_range[1])
		if not angle_range.is_empty():
			p.angle_min = float(angle_range[0])
			p.angle_max = float(angle_range[1])
		if inward:
			p.radial_accel_min = -150.0
			p.radial_accel_max = -70.0
		if swirl > 0.0:
			p.tangential_accel_min = swirl * 0.5
			p.tangential_accel_max = swirl
		p.initial_velocity_min = float(vel_range[0]) * vel_mult
		p.initial_velocity_max = float(vel_range[1]) * vel_mult
		p.scale_amount_min = float(scale_range[0])
		p.scale_amount_max = float(scale_range[1])
		var curve := Curve.new()
		curve.clear_points()
		if grow:
			curve.add_point(Vector2(0.0, 0.55))
			curve.add_point(Vector2(1.0, 1.45))
		else:
			curve.add_point(Vector2(0.0, 1.0))
			curve.add_point(Vector2(1.0, 0.3))
		p.scale_amount_curve = curve
		if additive:
			# 4.7 起 CPUParticles2D 无 blend_mode，用 CanvasItemMaterial 加法混合实现发光
			var mat := CanvasItemMaterial.new()
			mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			p.material = mat
		var grad := Gradient.new()
		grad.set_color(0, Color(layer_color, 1.0))
		grad.set_color(1, Color(layer_color, 0.0))
		p.color_ramp = grad
		p.color = Color.WHITE
		p.finished.connect(p.queue_free)
		add_child(p)

## 扩散环：实例化 scenes/fx/explosion.tscn（程序化 Line2D 圆），tween 缩放 + 淡出。
## 形态分发：按 KIND_RECIPES.shape.type 生成程序化组件（每种形态独立形状/运动方向，非"中心向四周爆开"）。
func _spawn_shape(pos: Vector2, color: Color, shape: Dictionary) -> void:
	if shape.is_empty():
		return
	match str(shape.get("type", "")):
		"lightning":
			_spawn_lightning_bolt(pos, color, shape)
		"ice":
			_spawn_ice_crystal(pos, color, shape)
		"ripples":
			_spawn_ripple_rings(pos, color, int(shape.get("count", 3)), shape)
		"beam":
			_spawn_light_beam(pos, color, shape)
		"void":
			_spawn_void_swirl(pos, color, shape)
		"arc":
			_spawn_arc_slash(pos, color, shape)
		"cross":
			_spawn_cross_flash(pos, color, shape)
		"coins":
			_spawn_bounce_coins(pos, color, shape)

## 程序化圆环点列（涟漪环 / 结晶 / 弧斩共用）。
static func _ring_points(radius: float, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var a := TAU * float(i) / float(segments)
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts

## 两点间锯齿折线（闪电主路径 / 分叉共用）。
static func _zigzag(from: Vector2, to: Vector2, steps: int, jitter: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.append(from)
	var seg_dir := to - from
	var perp := Vector2(-seg_dir.y, seg_dir.x).normalized()
	for i in steps:
		var t := float(i + 1) / float(steps)
		pts.append(from + seg_dir * t + perp * randf_range(-jitter, jitter))
	pts[pts.size() - 1] = to
	return pts

## 构造闪电折线节点。
static func _make_bolt_line(pts: PackedVector2Array, color: Color, width: float) -> Line2D:
	var line := Line2D.new()
	line.width = width
	line.default_color = color
	line.antialiased = true
	line.points = pts
	line.modulate = Color(color, 0.0)
	return line

## 闪电闪烁 + 淡出（前摇期间云团蓄能）。
func _bolt_fade(line: Line2D) -> void:
	var tween: Tween = line.create_tween()
	tween.tween_interval(0.12)
	tween.tween_property(line, "modulate:a", 1.0, 0.05)
	tween.tween_property(line, "modulate:a", 0.25, 0.04)
	tween.tween_property(line, "modulate:a", 1.0, 0.05)
	tween.tween_property(line, "modulate:a", 0.0, 0.3)
	tween.tween_callback(line.queue_free)

## 雷云闪电：落点上方深灰云团（多层 smoke 缓慢飘动蓄能）→ 分叉闪电折线从云劈向落点 → 落点电光脉冲。
func _spawn_lightning_bolt(pos: Vector2, color: Color, shape: Dictionary) -> void:
	var cloud: Dictionary = shape.get("cloud", {})
	if not cloud.is_empty():
		_spawn_tex_layer(pos, color, cloud)
	var bolt: Dictionary = shape.get("bolt", {})
	var height: float = float(bolt.get("height", 72.0))
	var jitter: float = float(bolt.get("jitter", 12.0))
	var segments: int = int(bolt.get("segments", 14))
	var branches: int = int(bolt.get("branches", 2))
	var width: float = float(bolt.get("width", 3.0))
	var pts := PackedVector2Array()
	pts.append(pos + Vector2(0.0, -height))
	var x := pos.x
	var y := pos.y - height
	var step_y := height / float(segments)
	for i in segments:
		if i < segments - 1:
			x += randf_range(-jitter, jitter)
		else:
			x = pos.x
		y += step_y
		pts.append(Vector2(x, y))
	var main := _make_bolt_line(pts, color, width)
	add_child(main)
	_bolt_fade(main)
	for b in branches:
		var idx: int = randi_range(2, maxi(2, segments - 3))
		var from: Vector2 = pts[idx]
		var fork_dir := Vector2(randf_range(0.3, 0.8) * (1.0 if b % 2 == 0 else -1.0), 1.0).normalized()
		var tip := from + fork_dir * randf_range(20.0, 34.0)
		var fork := _make_bolt_line(_zigzag(from, tip, 5, jitter * 0.7), color, width * 0.7)
		add_child(fork)
		_bolt_fade(fork)
	_spawn_flash(pos, color, "light_03", 0.16, 0.26)
	var impact: Dictionary = shape.get("impact", {})
	if not impact.is_empty():
		_spawn_tex_layer(pos, color, impact)

## 冰晶生长：多簇闭合结晶折线（六臂星形，从中心向外生长 + 旋转），配合霜雾与碎晶。
func _spawn_ice_crystal(pos: Vector2, color: Color, shape: Dictionary) -> void:
	var clusters: int = int(shape.get("clusters", 2))
	var size: float = float(shape.get("size", 20.0))
	for i in clusters:
		var crystal := Line2D.new()
		crystal.closed = true
		crystal.width = 1.8
		crystal.default_color = color
		crystal.antialiased = true
		var pts := PackedVector2Array()
		var arms: int = 6
		var radius := size * randf_range(0.8, 1.15)
		for a in arms:
			var ang := TAU * float(a) / float(arms) + randf_range(-0.12, 0.12)
			pts.append(Vector2(cos(ang), sin(ang)) * radius * randf_range(0.85, 1.0))
			pts.append(Vector2(cos(ang + TAU / float(arms) * 0.5), sin(ang + TAU / float(arms) * 0.5)) * radius * randf_range(0.35, 0.5))
		crystal.points = pts
		crystal.position = pos + Vector2(randf_range(-28.0, 28.0), randf_range(-16.0, 12.0))
		crystal.scale = Vector2.ONE * 0.3
		crystal.modulate = Color(color, 0.0)
		add_child(crystal)
		var tween: Tween = crystal.create_tween()
		tween.tween_property(crystal, "modulate:a", 1.0, 0.1)
		tween.tween_property(crystal, "scale", Vector2.ONE * randf_range(0.95, 1.2), 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(crystal, "rotation", randf_range(-0.7, 0.7), 0.55)
		tween.tween_property(crystal, "modulate:a", 0.0, 0.35)
		tween.tween_callback(crystal.queue_free)

## 水花涟漪：多环 Line2D 依次扩散（错峰放大 + 淡出，非单一环）。
func _spawn_ripple_rings(pos: Vector2, color: Color, count: int, shape: Dictionary) -> void:
	var width: float = float(shape.get("width", 2.0))
	var max_scale: float = float(shape.get("max_scale", 2.4))
	var stagger: float = float(shape.get("stagger", 0.12))
	for i in count:
		var ring := Line2D.new()
		ring.closed = true
		ring.width = width
		ring.default_color = color
		ring.antialiased = true
		ring.points = _ring_points(10.0, 28)
		ring.position = pos
		ring.scale = Vector2.ONE * 0.35
		ring.modulate = Color(color, 0.0 if i > 0 else 1.0)
		add_child(ring)
		var tween: Tween = ring.create_tween()
		if i > 0:
			tween.tween_interval(stagger * float(i))
			tween.tween_property(ring, "modulate:a", 1.0, 0.08)
		tween.tween_property(ring, "scale", Vector2.ONE * (max_scale + float(i) * 0.45), 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(ring, "modulate:a", 0.0, 0.55)
		tween.tween_callback(ring.queue_free)

## 光柱：竖直渐变光束 Line2D（宽柔层 + 窄亮层）从天而降，星尘上扬由粒子层补充。
func _spawn_light_beam(pos: Vector2, color: Color, shape: Dictionary) -> void:
	var height: float = float(shape.get("height", 118.0))
	var top := Vector2(0.0, -height)
	var bottom := Vector2(0.0, 8.0)
	for spec in shape.get("bars", [[16.0, 0.35], [7.0, 1.0]]):
		var line := Line2D.new()
		line.width = float(spec[0])
		line.default_color = Color(color, float(spec[1]))
		line.antialiased = true
		line.points = PackedVector2Array([top, bottom])
		line.position = pos
		line.scale = Vector2(0.7, 1.0)
		line.modulate = Color(color, 0.0)
		add_child(line)
		var tween: Tween = line.create_tween()
		tween.tween_property(line, "modulate:a", float(spec[1]), 0.12)
		tween.tween_property(line, "scale:x", 1.2, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(line, "modulate:a", 0.0, 0.35)
		tween.tween_callback(line.queue_free)

## 黑洞吞噬：twirl 精灵从外环向中心收缩（位置向心 + 旋转 + scale 放大 + 淡出）；
## 粒子层用 inward（负 radial_accel）+ swirl（切向）形成螺旋内向。
func _spawn_void_swirl(pos: Vector2, color: Color, shape: Dictionary) -> void:
	var orbs: int = int(shape.get("orbs", 4))
	var radius: float = float(shape.get("radius", 46.0))
	for i in orbs:
		var orb := Sprite2D.new()
		orb.texture = _get_tex("twirl_02")
		orb.scale = Vector2.ONE * randf_range(0.05, 0.08)
		var ang := TAU * float(i) / float(orbs) + randf_range(-0.4, 0.4)
		orb.position = pos + Vector2(cos(ang), sin(ang)) * radius
		orb.rotation = randf_range(-3.2, 3.2)
		orb.modulate = Color(color, 0.35)
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		orb.material = mat
		add_child(orb)
		var tween: Tween = orb.create_tween()
		tween.tween_property(orb, "position", pos, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.parallel().tween_property(orb, "rotation", orb.rotation + randf_range(-4.5, 4.5), 0.55)
		tween.parallel().tween_property(orb, "scale", Vector2.ONE * randf_range(0.11, 0.15), 0.55)
		tween.parallel().tween_property(orb, "modulate:a", 0.0, 0.55)
		tween.tween_callback(orb.queue_free)

## 弧斩：程序化圆弧折线勾勒斩击轨迹（旋转 + 放大淡出），slash 粒子带旋转沿弧飞出。
func _spawn_arc_slash(pos: Vector2, color: Color, shape: Dictionary) -> void:
	var radius: float = float(shape.get("radius", 30.0))
	var arc := Line2D.new()
	arc.width = 3.0
	arc.default_color = color
	arc.antialiased = true
	var pts := PackedVector2Array()
	var steps: int = 16
	for i in steps + 1:
		var a := -PI * 0.82 + PI * 1.64 * float(i) / float(steps)
		pts.append(Vector2(cos(a), sin(a)) * radius)
	arc.points = pts
	arc.position = pos
	arc.rotation = randf_range(-0.9, 0.9)
	arc.scale = Vector2.ONE * 0.5
	arc.modulate = Color(color, 0.0)
	add_child(arc)
	var tween: Tween = arc.create_tween()
	tween.tween_property(arc, "modulate:a", 1.0, 0.06)
	tween.tween_property(arc, "scale", Vector2.ONE * 1.35, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(arc, "modulate:a", 0.0, 0.3)
	tween.tween_callback(arc.queue_free)

## 愈光十字：竖直 + 水平光条组成十字形闪光，放大 + 淡出。
func _spawn_cross_flash(pos: Vector2, color: Color, shape: Dictionary) -> void:
	var cross := Node2D.new()
	cross.position = pos
	var arm: float = float(shape.get("arm", 26.0))
	for spec in [Vector2(0.0, 1.0), Vector2(1.0, 0.0)]:
		var bar := Line2D.new()
		bar.width = 4.0
		bar.default_color = Color(color, 0.9)
		bar.antialiased = true
		bar.points = PackedVector2Array([-spec * arm, spec * arm])
		cross.add_child(bar)
	cross.scale = Vector2.ONE * 0.4
	cross.modulate = Color(color, 0.0)
	add_child(cross)
	var tween: Tween = cross.create_tween()
	tween.tween_property(cross, "modulate:a", 1.0, 0.08)
	tween.tween_property(cross, "scale", Vector2.ONE * 1.25, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(cross, "modulate:a", 0.0, 0.5)
	tween.tween_callback(cross.queue_free)

## 钱雨：金币精灵上抛后 TRANS_BOUNCE 落地（反弹感）+ 旋转，粒子层高重力抛物线补足。
func _spawn_bounce_coins(pos: Vector2, color: Color, shape: Dictionary) -> void:
	var coins: int = int(shape.get("coins", 3))
	var texs: Array = shape.get("texs", ["star_01", "circle_01"])
	for i in coins:
		var coin := Sprite2D.new()
		coin.texture = _get_tex(str(texs[i % texs.size()]))
		coin.scale = Vector2.ONE * randf_range(0.05, 0.07)
		var dx := randf_range(-14.0, 14.0)
		coin.position = pos + Vector2(dx, 0.0)
		coin.modulate = Color(color, 1.0)
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		coin.material = mat
		add_child(coin)
		var tween: Tween = coin.create_tween()
		tween.tween_property(coin, "position", pos + Vector2(dx * 0.7, -54.0), 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(coin, "position", pos + Vector2(dx * 1.4, 6.0), 0.34).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_IN)
		tween.parallel().tween_property(coin, "rotation", randf_range(-4.0, 4.0), 0.34)
		tween.tween_property(coin, "modulate:a", 0.0, 0.2)
		tween.tween_callback(coin.queue_free)

func _spawn_ring(pos: Vector2, color: Color, params: Array, scale_mult: float = 1.0) -> void:
	var ring: Node2D = ExplosionScene.instantiate()
	ring.position = pos
	ring.modulate = color
	var line := ring.get_node_or_null("Ring") as Line2D
	if line != null and params.size() >= 3:
		line.width = float(params[2])
	add_child(ring)
	var ring_tween: Tween = ring.create_tween()
	var scale_target := RING_SCALE
	var duration := RING_DURATION
	if params.size() >= 2:
		scale_target = float(params[0]) * scale_mult
		duration = float(params[1])
	ring_tween.tween_property(ring, "scale", Vector2(scale_target, scale_target), duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	ring_tween.parallel().tween_property(ring, "modulate:a", 0.0, duration)
	ring_tween.tween_callback(ring.queue_free)

func _emit_small_shake() -> void:
	EventBus.screen_shake.emit(SHAKE_SMALL)

func _emit_shake(power: float) -> void:
	EventBus.screen_shake.emit(power)

func _school_holdings_of(school: String) -> int:
	## A2：查某流派当前持有件数（GameState 提供计数，档位判定在 FX 侧）
	if GameState == null or GameState.run.is_empty():
		return 0
	return int(GameState.school_holdings().get(school, 0))

static func _tier_of(n: int) -> int:
	if n >= 9:
		return 3
	if n >= 6:
		return 2
	if n >= 3:
		return 1
	return 0

func _spawn_poison_diffusion(pos: Vector2, color: Color, scale_mult: float) -> void:
	## A2 毒爆扩散波：主环之后延迟弹出的第二圈扩散环 + 外圈毒沫粒子（加法混合）。
	## 档位（3/6/9 件）越高，环越大、毒沫越多。
	var tiers: int = _tier_of(_school_holdings_of("poison"))
	var ring: Node2D = ExplosionScene.instantiate()
	ring.position = pos
	ring.modulate = color
	var line := ring.get_node_or_null("Ring") as Line2D
	if line != null:
		line.width = 2.4
	add_child(ring)
	var ring_tween: Tween = ring.create_tween()
	ring_tween.tween_interval(0.18)
	ring_tween.tween_property(ring, "scale", Vector2.ONE * (3.4 + float(tiers) * 0.7) * scale_mult, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	ring_tween.parallel().tween_property(ring, "modulate:a", 0.0, 0.5)
	ring_tween.tween_callback(ring.queue_free)
	var tex: Texture2D = _get_tex("circle_04")
	if tex == null:
		return
	var p := CPUParticles2D.new()
	p.position = pos
	p.texture = tex
	p.amount = 14 + 7 * tiers
	p.lifetime = randf_range(0.5, 0.75)
	p.one_shot = true
	p.explosiveness = 1.0
	p.spread = 180.0
	p.gravity = Vector2(0, -25)
	p.initial_velocity_min = 95.0 * scale_mult
	p.initial_velocity_max = 210.0 * scale_mult
	p.scale_amount_min = 0.045
	p.scale_amount_max = 0.085
	var curve := Curve.new()
	curve.clear_points()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.25))
	p.scale_amount_curve = curve
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = mat
	var grad := Gradient.new()
	grad.set_color(0, Color(color, 1.0))
	grad.set_color(1, Color(color, 0.0))
	p.color_ramp = grad
	p.color = Color.WHITE
	p.finished.connect(p.queue_free)
	add_child(p)

func _spawn_ice_shards(pos: Vector2, color: Color, scale_mult: float) -> void:
	## A2 碎冰冰屑：短时多粒子向四周迸射（高初速 + 重力下落），件数越多冰屑越多；
	## 高阶（>=6 件）追加一簇冰晶。
	var tiers: int = _tier_of(_school_holdings_of("ice"))
	var tex: Texture2D = _get_tex("spark_04")
	if tex == null:
		return
	var p := CPUParticles2D.new()
	p.position = pos
	p.texture = tex
	p.amount = 16 + 8 * tiers
	p.lifetime = randf_range(0.3, 0.5)
	p.one_shot = true
	p.explosiveness = 1.0
	p.spread = 180.0
	p.gravity = Vector2(0, 430)
	p.initial_velocity_min = 170.0 * scale_mult
	p.initial_velocity_max = 330.0 * scale_mult
	p.scale_amount_min = 0.04
	p.scale_amount_max = 0.09
	var curve := Curve.new()
	curve.clear_points()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.25))
	p.scale_amount_curve = curve
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = mat
	var grad := Gradient.new()
	grad.set_color(0, Color(color, 1.0))
	grad.set_color(1, Color(color, 0.0))
	p.color_ramp = grad
	p.color = Color.WHITE
	p.finished.connect(p.queue_free)
	add_child(p)
	if tiers >= 2:
		_spawn_ice_crystal(pos, color, {"clusters": 3, "size": 22.0})

func _refresh_summon_auras() -> void:
	## A2 召唤流派光环：按召唤流派持有件数（3/6/9）渲染召唤物脚下光环；
	## 档位随件数升级，召唤物消失后光环自动释放。
	var tier: int = _tier_of(_school_holdings_of("summon"))
	var summons := get_tree().get_nodes_in_group("summons")
	var alive: Dictionary = {}
	for s in summons:
		if not is_instance_valid(s):
			continue
		var sid := s.get_instance_id()
		alive[sid] = true
		var aura: Node2D = _summon_auras.get(sid)
		if aura != null and not is_instance_valid(aura):
			_summon_auras.erase(sid)
			aura = null
		if tier == 0:
			if aura != null:
				_summon_auras.erase(sid)
				aura.queue_free()
			continue
		if aura == null:
			aura = Node2D.new()
			aura.position = Vector2(0, 10)
			s.add_child(aura)
			_summon_auras[sid] = aura
		_build_aura_rings(aura, tier)
	for sid in _summon_auras.keys():
		if alive.has(sid):
			continue
		var aura: Node2D = _summon_auras[sid]
		_summon_auras.erase(sid)
		if is_instance_valid(aura):
			aura.queue_free()

func _build_aura_rings(aura: Node2D, tier: int) -> void:
	## 光环环数 = 档位（tier 1/2/3 = 1/2/3 圈，半径与亮度递增），反向旋转增加层次。
	if int(aura.get_meta("tier", 0)) == tier:
		return
	for c in aura.get_children():
		if c is Line2D:
			c.queue_free()
	aura.set_meta("tier", tier)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	aura.material = mat
	for i in tier:
		var ring := Line2D.new()
		ring.closed = true
		ring.width = 2.2 + 0.4 * float(i)
		ring.default_color = Color(0.45, 0.85, 1.0, 0.55 + 0.15 * float(i))
		ring.antialiased = true
		ring.points = _ring_points(13.0 + 6.0 * float(i), 26)
		ring.rotation = float(i) * 0.7
		aura.add_child(ring)
		var tw: Tween = ring.create_tween().set_loops()
		tw.tween_property(ring, "rotation", ring.rotation + TAU * (0.35 if i % 2 == 0 else -0.35), 2.6 + 0.5 * float(i))

func _on_damage_dealt(dmg: int, pos: Vector2, is_crit: bool) -> void:
	var number: DamageNumber = DamageNumberScene.instantiate()
	number.position = pos
	add_child(number)
	# 爽感：DPS 档位越高伤害数字越大（tier 1: 1.25x / tier 2: 1.6x / tier 3: 2x）
	var tier_size := 1.0
	match _dps_tier:
		1:
			tier_size = 1.25
		2:
			tier_size = 1.6
		3:
			tier_size = 2.0
	number.play(dmg, is_crit)
	if tier_size > 1.0:
		number.scale = Vector2.ONE * tier_size
	# 暴击反馈（Agent C）：金色粒子爆点 + 2 级轻微震屏
	if is_crit:
		_spawn_burst(pos, CRIT_GOLD, 14, 22)
		EventBus.screen_shake.emit(2.0)


## 可复用粒子爆散封装：一次性 CPUParticles2D，自毁由 finished 驱动。
## 升级：贴图粒子（火焰贴图 + 512 适配缩放），不再用白色 2x2 点染色。
func _spawn_burst(pos: Vector2, color: Color, amount_min: int, amount_max: int) -> void:
	var burst: CPUParticles2D = ParticleBurstScene.instantiate()
	burst.position = pos
	burst.amount = randi_range(amount_min, amount_max)
	burst.color = color
	var tex: Texture2D = _get_tex("flame_03")
	if tex != null:
		burst.texture = tex
		burst.scale_amount_min = 0.06
		burst.scale_amount_max = 0.12
	else:
		burst.texture = _get_white_texture()
		burst.scale_amount_min = 1.0
		burst.scale_amount_max = 2.5
	burst.finished.connect(burst.queue_free)
	add_child(burst)

func _on_enemy_died(_id: String, pos: Vector2, _xp: int, _gold: int, _elite: bool) -> void:
	# 连杀反馈：2 秒内击杀 >= 6 触发小慢动作（0.8x 0.15s）
	var now := Time.get_ticks_msec() / 1000.0
	_kill_times.append(now)
	while _kill_times.size() > 0 and _kill_times[0] < now - 2.0:
		_kill_times.pop_front()
	if _kill_times.size() >= 6:
		_kill_times.clear()
		EventBus.slow_mo.emit(0.8, 0.15)
		EventBus.fx_explosion.emit(pos, "lightning")

func _on_fx_heal_text(pos: Vector2, amount: int) -> void:
	var number: DamageNumber = DamageNumberScene.instantiate()
	number.position = pos
	add_child(number)
	number.play(amount, false, true)

const DOT_COLORS := {
	"poison": Color(0.45, 0.9, 0.3),
	"burn": Color(1.0, 0.55, 0.2),
	"ice": Color(0.45, 0.78, 1.0),
	"lightning": Color(1.0, 0.86, 0.25),
}

func _on_fx_dot_text(pos: Vector2, amount: int, kind: String) -> void:
	## DOT 伤害飘字：毒绿/火橙/冰蓝/雷黄（小数持续伤害，飘字更小更淡避免刷屏）
	if amount <= 0:
		return
	var number: DamageNumber = DamageNumberScene.instantiate()
	number.position = pos
	add_child(number)
	number.play(amount, false, false, DOT_COLORS.get(kind, Color.WHITE))
	number.scale = Vector2.ONE * 0.8

func _on_fx_hit_flash(target: Node) -> void:
	if not is_instance_valid(target) or not (target is CanvasItem):
		return
	var item := target as CanvasItem
	var original: Color = item.modulate
	var tween: Tween = item.create_tween()
	tween.tween_property(item, "modulate", FLASH_COLOR, 0.04)
	tween.tween_property(item, "modulate", original, 0.04)

func _on_slow_mo(factor: float, duration: float) -> void:
	var f: float = clampf(factor, SLOW_MO_MIN_FACTOR, 1.0)
	var d: float = maxf(duration, 0.01)
	if _slow_mo_tween != null and _slow_mo_tween.is_valid():
		_slow_mo_tween.kill()
	Engine.time_scale = f
	# 4.7 文档：create_tween() 默认按 TWEEN_PROCESS_IDLE，
	# 配合 set_ignore_time_scale(true) 让恢复按真实时间走，不被慢动作本身拖慢。
	_slow_mo_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	_slow_mo_tween.set_ignore_time_scale(true)
	_slow_mo_tween.tween_property(Engine, "time_scale", 1.0, d)

func _on_screen_shake(power: float) -> void:
	var camera := get_tree().get_first_node_in_group("camera")
	if is_instance_valid(camera) and camera.has_method("shake"):
		camera.shake(power)

func _on_player_hit(_dmg: int, _pos: Vector2) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if is_instance_valid(player):
		_on_fx_hit_flash(player)
	EventBus.screen_shake.emit(SHAKE_PLAYER_HIT)

static func _get_white_texture() -> Texture2D:
	if _white_particle_texture == null:
		var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		_white_particle_texture = ImageTexture.create_from_image(image)
	return _white_particle_texture

## Kenney 贴图缓存：load 返回 Resource（Variant），必须显式类型标注后再入表。
static func _get_tex(tex_name: String) -> Texture2D:
	if _tex_cache.has(tex_name):
		return _tex_cache[tex_name]
	var tex: Texture2D = load(FX_DIR + tex_name + ".png")
	if tex != null:
		_tex_cache[tex_name] = tex
	return tex

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
## 特效柔化（2026-08-13，docs/design/特效柔化报告.md）：
## 震屏幅度整体下调（3.0→1.5 / 2.5→1.2），所有 screen_shake 事件在
## _on_screen_shake 收口做幂衰减压缩（power 越大衰减越多），
## 外部硬编码调用点（boss 12/10、enemy 6、summon 4、synergy 3/0.8）无需改动即整体降幅。
const SHAKE_SMALL := 1.5
const SHAKE_PLAYER_HIT := 1.2
var _shake_cd := 0.0
var _shake_pending := 0.0
const SHAKE_COOLDOWN := 0.25  ## 用户需求：震屏节流，防高频晃动不适
const FLASH_COLOR := Color(3.0, 3.0, 3.0, 1.0)
const SLOW_MO_MIN_FACTOR := 0.05
## 护盾视觉（2026-08-12，docs/design/藤蔓护盾音效修复报告.md）：
## 护盾池在 defense_synergy._shield（synergy 内部状态），本节点只读查询
const SHIELD_SCRIPT_PATH := "res://scripts/synergies/defense_synergy.gd"
const SHIELD_RIPPLE_COLOR := Color(0.55, 0.78, 1.0)
const SHIELD_RIPPLE_BRIGHT := Color(0.85, 0.95, 1.0)

## =====================================================================
## 打击感强化第二轮（S 级，docs/design/打击感强化方案-第二轮.md G-1~G-4）
## G-1 音效（SfxBus 池化，见 scripts/core/sfx_bus.gd）｜G-2 死亡碎块｜
## G-3 伤害数字聚合+上限+弹出｜G-4 hitstop 接入普通攻击
## =====================================================================
const HITSTOP_COOLDOWN := 0.15     # 顿帧全局冷却（防高攻速连发卡手）
const HITSTOP_FACTOR := 0.05       # 顿帧时间因子（>0）
const HITSTOP_DUR_CRIT := 0.06     # 暴击顿帧时长（s）
const HITSTOP_DUR_NORMAL := 0.03   # 普通命中顿帧时长（s）
const HITSTOP_DUR_BOSS := 0.08     # Boss 命中顿帧时长（s）
const DMG_NUM_MAX_ALIVE := 24      # 伤害数字存活上限（超出挤掉最旧）
const DMG_NUM_PER_FRAME := 8       # 单帧新建上限（超出并入最近数字）
const DMG_NUM_MERGE_DIST := 14.0   # 同帧聚合距离（px）
const DMG_NUM_DISMISS := 0.15      # 被淘汰数字加速淡出时长（s）
const DEBRIS_NORMAL_MIN := 4       # 普通怪死亡碎屑数（档位保持：回归 test_hit_feel 硬断言）
const DEBRIS_NORMAL_MAX := 6
const DEBRIS_ELITE_MIN := 8        # 精英
const DEBRIS_ELITE_MAX := 10
const DEBRIS_BOSS_MIN := 14        # Boss：更多柔点
const DEBRIS_BOSS_MAX := 18
## 特效柔化（2026-08-13）：尺寸缩小 / 寿命缩短（快速淡出）/ 重力加大（下落更快）
const DEBRIS_SIZE_MIN := 1.4       # 柔点半径下限（旧硬方块半宽 2.4）
const DEBRIS_SIZE_MAX := 2.2       # 柔点半径上限（旧 4.8；上限仍低于旧下限 2.4）
const DEBRIS_LIFE_MIN := 0.26      # 普通寿命（旧 0.3）
const DEBRIS_LIFE_MAX := 0.38      # 旧 0.5
const DEBRIS_BOSS_LIFE_MIN := 0.42 # Boss 寿命（旧 0.55）
const DEBRIS_BOSS_LIFE_MAX := 0.6  # 旧 0.8
const DEBRIS_GRAV := 1050.0        # 重力（旧 620）
const DEBRIS_FALLBACK := Color(0.75, 0.28, 0.2)  # 提取贴图主色失败时的暗红

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
	"paralyze": {
		"tex": ["spark_01", "spark_03"], "amount": 6, "scale": [0.03, 0.06],
		"vel": [30, 90], "spread": 360.0, "grav": Vector2(0, -25),
		"life": [0.25, 0.4], "add": true, "color": Color(0.62, 0.82, 1.0),
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
var _chain_bolts: Array = []  # 链跳闪电连线池（LightningBolt，上限 CHAIN_BOLT_MAX）
var _hitstop_cd := 0.0  ## 打击感 P1：顿帧冷却（150ms 防高攻速连发卡手）
var _hitstop_last_target := 0  ## G-4：顿帧去重——同一帧同一目标只触发一次
var _hitstop_last_frame := -1
var _shield_source: Node = null       # defense_synergy 节点缓存（只读查询 _shield）
var _shield_prev := -1.0              # 上一帧护盾值（-1 = 未初始化基线）
var _shield_broke_played := false     # 本段"破碎→归零"已播过破碎反馈（防多帧重复）
var _dmg_numbers: Array = []  ## G-3：存活伤害数字（上限淘汰）
var _fx_frame := 0            ## 自维护 process 帧计数（headless 下 get_frame() 不可靠）
var _dmg_frame := -1          ## G-3：当前聚合帧（_fx_frame）
var _dmg_frame_count := 0     ## G-3：本帧已建数字数（DMG_NUM_PER_FRAME 上限）
var _dmg_frame_nums: Array = []  ## G-3：本帧已建数字（同帧聚合搜索）
var _boss_ids: Array = []     ## G-2：boss id 缓存（碎块分级）
static var _death_color_cache: Dictionary = {}  ## G-2：enemy_id -> 贴图主色

## =====================================================================
## 一次性粒子对象池（P1 性能优化，docs/design/性能优化方案.md 热点 2）
## 池化范围：_spawn_flash / _spawn_cast_particles / _spawn_tex_layer /
## _spawn_poison_diffusion / _spawn_ice_shards（one_shot=true + finished 自毁的一次性爆发型）。
## 不池化：spawn_status_particles / GroundTex.loop_particles（持续 Loop 型，
## 生命周期跟随宿主节点销毁，池化反而引入重置风险）。
## 视觉安全：每次借用全量重配所有渲染属性（纹理/颜色/曲线/材质/速度/加速度/方向），
## 回收时 _reset_particle 全字段清零，杜绝"复用残留旧特效"。
## =====================================================================
const PARTICLE_POOL_MAX := 64  # 每类空闲上限（超限直接释放，防常驻膨胀）

var _particle_pools: Dictionary = {}  # pool_key -> Array[CPUParticles2D]（空闲，已出树）
var _pool_created := 0  # 池新建粒子总数（测试/监控用）
var _pool_reused := 0   # 池复用次数（测试/监控用）

## 从池取一次性粒子：空闲可用则复用，否则新建并挂 finished 回收。
## 调用方随后必须全量配置属性并 add_child + restart()。
func _pool_get(key: String) -> CPUParticles2D:
	var pool = _particle_pools.get(key)  # Variant：key 未建池时为 null
	while pool != null and not pool.is_empty():
		var p: CPUParticles2D = pool.pop_back()
		if is_instance_valid(p):
			_pool_reused += 1
			return p
	# 无空闲或池中引用已失效：新建
	var fresh := CPUParticles2D.new()
	fresh.set_meta("pool_key", key)
	fresh.finished.connect(_on_pool_particle_finished.bind(fresh))
	_pool_created += 1
	return fresh

## finished 信号驱动回收：复用"结束的粒子"节点，出树 + 全量重置 + 入池。
func _on_pool_particle_finished(p: CPUParticles2D) -> void:
	if not is_instance_valid(p):
		return
	var key: String = str(p.get_meta("pool_key", ""))
	if key.is_empty():
		p.queue_free()
		return
	_reset_particle(p)
	if p.is_inside_tree():
		remove_child(p)
	var pool = _particle_pools.get(key)  # Variant：key 未建池时为 null
	if pool == null:
		pool = []
		_particle_pools[key] = pool
	if pool.size() < PARTICLE_POOL_MAX:
		pool.append(p)
	else:
		p.queue_free()

## 池化粒子全量重置：位置/纹理/材质/颜色/曲线/速度/加速度/方向/发射状态，
## 保证复用时不会残留上一轮的视觉参数。
func _reset_particle(p: CPUParticles2D) -> void:
	p.emitting = false
	p.one_shot = true
	p.position = Vector2.ZERO
	p.rotation = 0.0
	p.scale = Vector2.ONE
	p.modulate = Color.WHITE
	p.visible = true
	p.z_index = 0
	p.texture = null
	p.amount = 1
	p.lifetime = 1.0
	p.explosiveness = 0.0
	p.spread = 0.0
	p.direction = Vector2.RIGHT
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 0.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 1.0
	p.scale_amount_curve = null
	p.angular_velocity_min = 0.0
	p.angular_velocity_max = 0.0
	p.angle_min = 0.0
	p.angle_max = 0.0
	p.radial_accel_min = 0.0
	p.radial_accel_max = 0.0
	p.tangential_accel_min = 0.0
	p.tangential_accel_max = 0.0
	p.material = null
	p.color_ramp = null
	p.color = Color.WHITE
	# 时间轴（time）由借用侧 restart() 重置，此处无需（且 time 只读）

## 池统计（测试/监控）：created/reused + 每类空闲数。
func particle_pool_stats() -> Dictionary:
	var idle: Dictionary = {}
	for key in _particle_pools:
		idle[key] = _particle_pools[key].size()
	return {"created": _pool_created, "reused": _pool_reused, "idle": idle}

func _ready() -> void:
	EventBus.fx_explosion.connect(_on_fx_explosion)
	EventBus.fx_explosion_scaled.connect(_on_fx_explosion_scaled)
	EventBus.fx_cast.connect(_on_fx_cast)
	EventBus.fx_hit.connect(_on_fx_hit)
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.fx_hit_flash.connect(_on_fx_hit_flash)
	EventBus.fx_hit_slow.connect(_on_fx_hit_slow)
	EventBus.fx_heal_text.connect(_on_fx_heal_text)
	EventBus.fx_dot_text.connect(_on_fx_dot_text)
	EventBus.screen_shake.connect(_on_screen_shake)
	EventBus.slow_mo.connect(_on_slow_mo)
	EventBus.enemy_died.connect(_on_enemy_died)
	# 契约：player_hit 的监听方包含特效（受击反馈）
	EventBus.player_hit.connect(_on_player_hit)

func _exit_tree() -> void:
	## 场景卸载：释放池中空闲粒子（已出树，树销毁不会自动清理它们）
	for key in _particle_pools:
		var pool: Array = _particle_pools[key]
		for p in pool:
			if is_instance_valid(p):
				p.free()
		pool.clear()
	_particle_pools.clear()

func _process(delta: float) -> void:
	_fx_frame += 1
	_hitstop_cd = maxf(_hitstop_cd - delta, 0.0)
	_process_shake_throttle(delta)
	_track_shield_state()
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
				## 落雷误触发修复（Beauvoir 报告 P0-1）：无雷系构筑时高 DPS 不再随机落雷
				if _school_holdings_of("lightning") > 0:
					EventBus.fx_explosion.emit(Vector2(randf_range(100, 1180), randf_range(80, 640)), "lightning")
	# A2 summon aura: refresh tier every 0.5s by summon school holdings (3/6/9)
	_aura_timer -= delta
	if _aura_timer <= 0.0:
		_aura_timer = 0.5
		_refresh_summon_auras()

## 护盾状态跟踪（每帧）：值 0→>0 播放"护盾升起"涟漪；>0→0 播放"护盾破碎"
## 涟漪 + 破碎音效（护盾在 _on_player_hit 同步回调时尚未结算，必须帧末判定）。
func _track_shield_state() -> void:
	var shield := _shield_value()
	if is_equal_approx(_shield_prev, -1.0):
		_shield_prev = shield  # 基线：首帧只记录
		return
	if _shield_prev <= 0.0 and shield > 0.0:
		_shield_broke_played = false
		var player := get_tree().get_first_node_in_group("player")
		if is_instance_valid(player):
			spawn_shield_hit_fx((player as Node2D).global_position, false)
			SfxBus.play("res://assets/audio/sfx_shield_up.ogg", -11.0, 1.05)
	elif _shield_prev > 0.0 and shield <= 0.0 and not _shield_broke_played:
		_shield_broke_played = true
		var player := get_tree().get_first_node_in_group("player")
		if is_instance_valid(player):
			spawn_shield_hit_fx((player as Node2D).global_position, true)
			SfxBus.play_hit("shield_break")
	_shield_prev = shield

## 只读查询防御流护盾池（与 hud.gd 同款路径定位，未挂载返回 0）。
func _shield_value() -> float:
	var src := _shield_source_node()
	if src == null:
		return 0.0
	var v = src.get("_shield")
	return 0.0 if v == null else float(v)

func _shield_source_node() -> Node:
	if _shield_source != null and is_instance_valid(_shield_source):
		return _shield_source
	_shield_source = _find_synergy_node(get_tree().root)
	return _shield_source

func _find_synergy_node(node: Node) -> Node:
	var script: Script = node.get_script()
	if script != null and script.resource_path == SHIELD_SCRIPT_PATH:
		return node
	for child in node.get_children():
		var hit := _find_synergy_node(child)
		if hit != null:
			return hit
	return null

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
	var p := _pool_get("flash")
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
	# 池化：显式清空 layer 可能设置的旋转/加速度字段，防复用残留
	p.direction = Vector2.RIGHT
	p.angular_velocity_min = 0.0
	p.angular_velocity_max = 0.0
	p.angle_min = 0.0
	p.angle_max = 0.0
	p.radial_accel_min = 0.0
	p.radial_accel_max = 0.0
	p.tangential_accel_min = 0.0
	p.tangential_accel_max = 0.0
	add_child(p)
	p.restart()

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
	var p := _pool_get("cast")
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
	else:
		p.material = null  # 池化：非加法配方必须清掉上一轮残留材质
	var grad := Gradient.new()
	grad.set_color(0, Color(base_color, 1.0))
	grad.set_color(1, Color(base_color, 0.0))
	p.color_ramp = grad
	p.color = Color.WHITE
	# 池化：显式清空 layer 可能设置的旋转/加速度字段
	p.angular_velocity_min = 0.0
	p.angular_velocity_max = 0.0
	p.angle_min = 0.0
	p.angle_max = 0.0
	p.radial_accel_min = 0.0
	p.radial_accel_max = 0.0
	p.tangential_accel_min = 0.0
	p.tangential_accel_max = 0.0
	add_child(p)
	p.restart()

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
		var p := _pool_get("layer")
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
		else:
			p.direction = Vector2.RIGHT  # 池化：无条件设置，防复用残留方向
		p.angular_velocity_min = float(spin_range[0]) if not spin_range.is_empty() else 0.0
		p.angular_velocity_max = float(spin_range[1]) if not spin_range.is_empty() else 0.0
		p.angle_min = float(angle_range[0]) if not angle_range.is_empty() else 0.0
		p.angle_max = float(angle_range[1]) if not angle_range.is_empty() else 0.0
		p.radial_accel_min = -150.0 if inward else 0.0
		p.radial_accel_max = -70.0 if inward else 0.0
		p.tangential_accel_min = swirl * 0.5 if swirl > 0.0 else 0.0
		p.tangential_accel_max = swirl if swirl > 0.0 else 0.0
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
		else:
			p.material = null  # 池化：非加法配方必须清掉上一轮残留材质
		var grad := Gradient.new()
		grad.set_color(0, Color(layer_color, 1.0))
		grad.set_color(1, Color(layer_color, 0.0))
		p.color_ramp = grad
		p.color = Color.WHITE
		add_child(p)
		p.restart()

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

## 近战挥砍弧光：固定朝向 dir 的弧形刀光（范围可视化，半径=近战攻击范围）。
## 双层绘制：外层淡色弧 + 内层亮芯弧，快速展开 + 渐隐，寿命 ~0.18s。
func spawn_melee_arc(pos: Vector2, dir: Vector2, radius: float) -> void:
	var arc := Node2D.new()
	arc.position = pos
	arc.z_index = 10
	add_child(arc)
	var color := Color(0.92, 0.94, 1.0)
	for spec in [{"w": 5.0, "c": Color(color, 0.45), "r": radius * 1.02},
	             {"w": 2.2, "c": Color(1.0, 1.0, 1.0, 0.95), "r": radius}]:
		var line := Line2D.new()
		line.width = float(spec["w"])
		line.default_color = spec["c"]
		line.antialiased = true
		var pts := PackedVector2Array()
		var steps: int = 12
		for i in steps + 1:
			var t := float(i) / float(steps)
			# 弧：从 -70° 扫到 +70°，开口朝向 dir
			var a := -deg_to_rad(70.0) + deg_to_rad(140.0) * t
			pts.append(Vector2(cos(a), sin(a)) * float(spec["r"]))
		line.points = pts
		line.position = Vector2.ZERO
		arc.add_child(line)
	arc.rotation = dir.angle()
	arc.modulate = Color(1, 1, 1, 0.0)
	var tween: Tween = arc.create_tween()
	tween.tween_property(arc, "modulate:a", 1.0, 0.045)
	tween.parallel().tween_property(arc, "scale", Vector2.ONE * 1.18, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(arc, "modulate:a", 0.0, 0.18).set_delay(0.06)
	tween.tween_callback(arc.queue_free)

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

## ===================== LightningBolt：链跳闪电连线渲染节点 =====================
## 程序化 _draw：起点→终点 3~5 段随机抖动折线，双层绘制（粗 glow + 细亮芯），
## 主色淡蓝白 Color(0.6, 0.8, 1.0)；生命周期 0.22s（前段电流闪烁 + 尾段渐隐）后 queue_free。
## 纯视觉节点：不参与碰撞；由 fx_manager 统一限量（同时最多 CHAIN_BOLT_MAX 条，超出降频跳过）。
const CHAIN_BOLT_MAX := 12
const CHAIN_BOLT_LIFETIME := 0.22

class LightningBolt:
	extends Node2D
	## 内嵌类注意：常量/静态与本类内自包含，不依赖外层作用域（GDScript 内嵌类作用域隔离）。

	const BOLT_COLOR := Color(0.6, 0.8, 1.0)
	const CORE_COLOR := Color(1.0, 1.0, 1.0)
	const LIFETIME := 0.22
	const FADE_TAIL := 0.08

	var _points := PackedVector2Array()
	var _life := 0.0
	var is_lightning_bolt := true  # 测试/外部识别标记（另附 meta 双保险）

	func setup(from: Vector2, to: Vector2, jitter: float) -> void:
		# 节点挂 fx_manager（场景原点），折线坐标直接用全局坐标绘制
		position = Vector2.ZERO
		_points = _bolt_points(from, to, jitter)
		_life = LIFETIME
		z_index = 12
		queue_redraw()

	func _process(delta: float) -> void:
		_life -= delta
		if _life <= 0.0:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		if _points.size() < 2:
			return
		var t := LIFETIME - _life
		var fade := 1.0
		if _life < FADE_TAIL:
			fade = clampf(_life / FADE_TAIL, 0.0, 1.0)
		var flicker := 1.0 if int(t * 70.0) % 2 == 0 else 0.72  # 前段高频闪烁（电流感）
		var glow := Color(BOLT_COLOR, 0.5 * fade * flicker)
		var core := Color(CORE_COLOR, 0.95 * fade * flicker)
		draw_polyline(_points, glow, 5.0, true)  # 粗 glow 层
		draw_polyline(_points, core, 2.0, true)  # 细亮芯层
		draw_circle(_points[0], 2.0, Color(BOLT_COLOR, 0.7 * fade))  # 起点电光
		draw_circle(_points[_points.size() - 1], 2.6, Color(BOLT_COLOR, 0.85 * fade))  # 终点电光

	static func _bolt_points(from: Vector2, to: Vector2, jitter: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		pts.append(from)
		var seg := to - from
		var perp := Vector2(-seg.y, seg.x).normalized()
		var steps := randi_range(3, 5)  # 3~5 段随机抖动
		for i in steps:
			var t := float(i + 1) / float(steps)
			pts.append(from + seg * t + perp * randf_range(-jitter, jitter))
		pts[pts.size() - 1] = to
		return pts

func spawn_chain_bolt(from: Vector2, to: Vector2) -> void:
	## 链跳闪电连线：projectile._try_chain / thunder_synergy._chain_burst 每跳调用一次。
	## 性能：同时最多 CHAIN_BOLT_MAX 条；满额时降频跳过（不排队、不积压）。
	_prune_chain_bolts()
	if _chain_bolts.size() >= CHAIN_BOLT_MAX:
		return
	var bolt := LightningBolt.new()
	bolt.name = "LightningBolt"
	bolt.set_meta("is_lightning_bolt", true)
	var jitter := clampf(from.distance_to(to) * 0.07, 5.0, 16.0)
	bolt.setup(from, to, jitter)
	add_child(bolt)
	_chain_bolts.append(bolt)

func lightning_bolt_count() -> int:
	## 当前存活链跳连线数（测试/诊断用）。
	_prune_chain_bolts()
	return _chain_bolts.size()

func _prune_chain_bolts() -> void:
	var i := 0
	while i < _chain_bolts.size():
		if not is_instance_valid(_chain_bolts[i]):
			_chain_bolts.remove_at(i)
		else:
			i += 1

## 落雷视觉强化（thunder_synergy._fx_lightning 挂接）：闪电柱（竖直双层粗亮柱）+ 底部地面电弧溅射 4~6 条。
func spawn_strike_arcs(pos: Vector2) -> void:
	var color: Color = KIND_COLORS["lightning"]
	var height := 86.0
	var pts := PackedVector2Array()
	pts.append(pos + Vector2(0.0, -height))
	var y := pos.y - height
	var step_y := height / 12.0
	for i in 12:
		var x := pos.x + (randf_range(-7.0, 7.0) if i < 11 else 0.0)
		y += step_y
		pts.append(Vector2(x, y))
	var glow := _make_bolt_line(pts, Color(color, 0.30), 11.0)
	add_child(glow)
	_bolt_fade(glow)
	var core := _make_bolt_line(pts, Color(1.0, 1.0, 1.0, 0.95), 3.4)
	add_child(core)
	_bolt_fade(core)
	var arcs := randi_range(4, 6)
	for i in arcs:
		var ang := randf() * TAU
		var dir := Vector2(cos(ang), sin(ang))
		var tip := pos + dir * randf_range(20.0, 42.0) + Vector2(0.0, randf_range(-2.0, 8.0))
		var arc := _make_bolt_line(_zigzag(pos + dir * 5.0, tip, 4, 9.0), Color(color, 0.9), 2.2)
		add_child(arc)
		_bolt_fade(arc)
	_spawn_flash(pos, color, "light_03", 0.18, 0.3)

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
		## 用户需求：爆炸圈柔和化——线宽减半
		line.width = float(params[2]) * 0.55
	add_child(ring)
	ring.modulate.a = 0.72  ## 用户需求：起点半透明，更柔和
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
		line.width = 1.3  ## 用户需求：毒爆圈柔和化（线宽减半）
	add_child(ring)
	ring.modulate.a = 0.7
	var ring_tween: Tween = ring.create_tween()
	ring_tween.tween_interval(0.18)
	ring_tween.tween_property(ring, "scale", Vector2.ONE * (3.4 + float(tiers) * 0.7) * scale_mult, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	ring_tween.parallel().tween_property(ring, "modulate:a", 0.0, 0.5)
	ring_tween.tween_callback(ring.queue_free)
	var tex: Texture2D = _get_tex("circle_04")
	if tex == null:
		return
	var p := _pool_get("poison")
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
	# 池化：显式清空 layer 可能设置的旋转/加速度字段，防复用残留
	p.direction = Vector2.RIGHT
	p.angular_velocity_min = 0.0
	p.angular_velocity_max = 0.0
	p.angle_min = 0.0
	p.angle_max = 0.0
	p.radial_accel_min = 0.0
	p.radial_accel_max = 0.0
	p.tangential_accel_min = 0.0
	p.tangential_accel_max = 0.0
	add_child(p)
	p.restart()

func _spawn_ice_shards(pos: Vector2, color: Color, scale_mult: float) -> void:
	## A2 碎冰冰屑：短时多粒子向四周迸射（高初速 + 重力下落），件数越多冰屑越多；
	## 高阶（>=6 件）追加一簇冰晶。
	var tiers: int = _tier_of(_school_holdings_of("ice"))
	var tex: Texture2D = _get_tex("spark_04")
	if tex == null:
		return
	var p := _pool_get("ice")
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
	# 池化：显式清空方向/旋转/加速度字段
	p.direction = Vector2.RIGHT
	p.angular_velocity_min = 0.0
	p.angular_velocity_max = 0.0
	p.angle_min = 0.0
	p.angle_max = 0.0
	p.radial_accel_min = 0.0
	p.radial_accel_max = 0.0
	p.tangential_accel_min = 0.0
	p.tangential_accel_max = 0.0
	add_child(p)
	p.restart()
	if tiers >= 2:
		_spawn_ice_crystal(pos, color, {"clusters": 3, "size": 22.0})

func _refresh_summon_auras() -> void:
	## A2 召唤流派光环：按召唤流派持有件数（3/6/9）渲染召唤物脚下光环；
	## 档位随件数升级，召唤物消失后光环自动释放。
	## P0-1 修复（全流程体验报告-第2轮）：_summon_auras 中的值可能是已释放实例
	## （召唤物死亡连带光环销毁 / 光环被外部释放）。旧代码把字典值直接赋给
	## Node2D 类型化变量会触发 "Trying to assign invalid previously freed instance"
	## 并中止函数（erase 未执行 → 条目每帧残留报错直至进程退出）。
	## 现在：一律先用无类型 Variant 取值 + is_instance_valid() 判活后再使用；
	## 光环创建时挂 tree_exiting 清理钩子（召唤物销毁帧即擦除条目，不留窗口期）。
	var tier: int = _tier_of(_school_holdings_of("summon"))
	var summons := get_tree().get_nodes_in_group("summons")
	var alive: Dictionary = {}
	for s in summons:
		if not is_instance_valid(s):
			continue
		var sid := s.get_instance_id()
		alive[sid] = true
		var aura = _summon_auras.get(sid)
		if aura != null and not is_instance_valid(aura):
			## 光环已被释放但召唤物存活：清残留条目，下一分支重建
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
			_connect_aura_cleanup(aura, sid)
		_build_aura_rings(aura, tier)
	for sid in _summon_auras.keys():
		if alive.has(sid):
			continue
		var aura = _summon_auras[sid]
		_summon_auras.erase(sid)
		if aura != null and is_instance_valid(aura):
			aura.queue_free()


func _connect_aura_cleanup(aura: Node2D, sid: int) -> void:
	## 光环随召唤物销毁（queue_free 同帧触发 tree_exiting）时同步擦除字典条目，
	## 杜绝下一轮刷新读到 freed-instance。
	if aura.tree_exiting.is_connected(_on_aura_tree_exiting.bind(sid)):
		return
	aura.tree_exiting.connect(_on_aura_tree_exiting.bind(sid))


func _on_aura_tree_exiting(sid: int) -> void:
	if _summon_auras.has(sid):
		_summon_auras.erase(sid)


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
	if dmg <= 0:
		return
	var frame := _fx_frame
	if frame != _dmg_frame:
		_dmg_frame = frame
		_dmg_frame_count = 0
		_dmg_frame_nums.clear()
	# 聚合（G-3）：同帧同位置（距离 < 14px）命中合并到最近数字（RoR2 同款降噪）
	var best: DamageNumber = null
	var best_d := DMG_NUM_MERGE_DIST
	for n in _dmg_frame_nums:
		if not is_instance_valid(n):
			continue
		var d: float = n.position.distance_to(pos)
		if d <= best_d:
			best_d = d
			best = n
	if best != null:
		best.add_value(dmg, is_crit)
		return
	# 单帧新建上限：超出 8 个并入最近数字（任意距离），防极端刷屏
	if _dmg_frame_count >= DMG_NUM_PER_FRAME and not _dmg_frame_nums.is_empty():
		var nearest: DamageNumber = _dmg_frame_nums[0]
		var nd := INF
		for n in _dmg_frame_nums:
			if not is_instance_valid(n):
				continue
			var d2: float = n.position.distance_to(pos)
			if d2 < nd:
				nd = d2
				nearest = n
		if is_instance_valid(nearest):
			nearest.add_value(dmg, is_crit)
		return
	# 存活上限：超出 24 个挤掉最旧（加速淡出 0.15s）
	if _dmg_numbers.size() >= DMG_NUM_MAX_ALIVE:
		var oldest: DamageNumber = _dmg_numbers[0]
		_dmg_numbers.pop_front()
		if is_instance_valid(oldest):
			oldest.dismiss(DMG_NUM_DISMISS)
	var number: DamageNumber = DamageNumberScene.instantiate()
	number.z_index = 100  # 数字永远渲染在敌人/Boss 大贴图之上（Boss 无数字的根因：层级被盖）
	number.position = pos
	add_child(number)
	_dmg_numbers.append(number)
	_dmg_frame_nums.append(number)
	_dmg_frame_count += 1
	number.tree_exited.connect(_on_dmg_number_freed.bind(number))
	# 爽感：DPS 档位越高伤害数字越大（tier 1: 1.25x / tier 2: 1.6x / tier 3: 2x）
	var tier_size := 1.0
	match _dps_tier:
		1:
			tier_size = 1.25
		2:
			tier_size = 1.6
		3:
			tier_size = 2.0
	number.base_scale = tier_size
	number.play(dmg, is_crit)
	# 暴击反馈（Agent C）：金色粒子爆点 + 2 级轻微震屏
	if is_crit:
		_spawn_burst(pos, CRIT_GOLD, 14, 22)
		EventBus.screen_shake.emit(2.0)

func _on_dmg_number_freed(number: DamageNumber) -> void:
	## 数字自毁后从存活表摘除（dismiss/自然寿命共用）
	var idx := _dmg_numbers.find(number)
	if idx >= 0:
		_dmg_numbers.remove_at(idx)

## 当前被跟踪的伤害数字数（测试/监控：验证 DMG_NUM_MAX_ALIVE 上限）。
func dmg_number_tracked() -> int:
	return _dmg_numbers.size()

## 死亡碎屑爆散（G-2 柔化版，2026-08-13）：不再生成硬方块——
## 小圆柔点粒子（抗锯齿圆 + 亮芯），尺寸缩小、下落更快、渐隐更早、
## 颜色降饱和提亮融入背景；数量档位保持 4-6/8-10/14-18（回归测试约束）。
func _spawn_death_debris(pos: Vector2, enemy_id: String, elite: bool) -> void:
	var boss := _is_boss_id(enemy_id)
	var color: Color = _death_color(enemy_id)
	if elite:
		color = color.lerp(CRIT_GOLD, 0.25)  # 掺金减半，弱化跳色
	var n := randi_range(DEBRIS_NORMAL_MIN, DEBRIS_NORMAL_MAX)
	var life_min := DEBRIS_LIFE_MIN
	var life_max := DEBRIS_LIFE_MAX
	var size_mult := 1.0
	if elite:
		n = randi_range(DEBRIS_ELITE_MIN, DEBRIS_ELITE_MAX)
		size_mult = 1.05
	if boss:
		n = randi_range(DEBRIS_BOSS_MIN, DEBRIS_BOSS_MAX)
		life_min = DEBRIS_BOSS_LIFE_MIN
		life_max = DEBRIS_BOSS_LIFE_MAX
		size_mult = 1.2
	for i in n:
		var d := DeathDebris.new()
		var ang := randf() * TAU
		d.setup(pos, color, randf_range(DEBRIS_SIZE_MIN, DEBRIS_SIZE_MAX) * size_mult,
			Vector2(cos(ang), sin(ang)) * randf_range(80.0, 220.0),
			randf_range(life_min, life_max))
		add_child(d)

func _is_boss_id(enemy_id: String) -> bool:
	## boss 表 id 缓存（enemies.json bosses 数组）
	if _boss_ids.is_empty() and GameState != null:
		for b in GameState.tables.get("enemies", {}).get("bosses", []):
			_boss_ids.append(str(b.get("id", "")))
	return _boss_ids.has(enemy_id)

func _death_color(enemy_id: String) -> Color:
	## 从敌人贴图提取主体颜色（alpha > 0.5 像素平均色，提亮保证可见），按 enemy_id 缓存。
	if _death_color_cache.has(enemy_id):
		return _death_color_cache[enemy_id]
	_death_color_cache[enemy_id] = DEBRIS_FALLBACK
	var path := ""
	if GameState != null:
		for e in GameState.tables.get("enemies", {}).get("enemies", []):
			if str(e.get("id", "")) == enemy_id:
				path = str(e.get("sprite", ""))
				break
		if path.is_empty():
			for b in GameState.tables.get("enemies", {}).get("bosses", []):
				if str(b.get("id", "")) == enemy_id:
					path = str(b.get("sprite", ""))
					break
	if path.is_empty():
		return DEBRIS_FALLBACK
	var tex: Texture2D = load(path)
	if tex == null:
		return DEBRIS_FALLBACK
	var img := tex.get_image()
	if img == null:
		return DEBRIS_FALLBACK
	img.convert(Image.FORMAT_RGBA8)
	var r := 0.0
	var g := 0.0
	var b := 0.0
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.5:
				r += c.r
				g += c.g
				b += c.b
				n += 1
	if n == 0:
		return DEBRIS_FALLBACK
	var col := Color(clampf(r / n * 1.5 + 0.06, 0.0, 1.0),
		clampf(g / n * 1.5 + 0.06, 0.0, 1.0),
		clampf(b / n * 1.5 + 0.06, 0.0, 1.0))
	col = _soften_death_color(col)
	_death_color_cache[enemy_id] = col
	return col

## 死亡碎屑颜色柔化：降饱和（×0.55）+ 提亮，让碎屑融入背景而非与场景对比过强。
static func _soften_death_color(col: Color) -> Color:
	return Color.from_hsv(col.h, clampf(col.s * 0.55, 0.0, 1.0),
		clampf(col.v * 1.1 + 0.06, 0.0, 1.0), col.a)

## 柔化死亡碎屑（G-2 柔化版，2026-08-13）：小圆柔点——抗锯齿圆 + 亮芯，
## 无硬方块（draw_rect 已废弃）；重力大（下落更快）、渐隐窗口更早（70% 寿命）、
## 起始透明度 90% 更柔和。
class DeathDebris:
	extends Node2D

	## 内嵌类作用域隔离：常量需在本类内自包含（不能引用外层 fx_manager 常量）
	const GRAV := 1050.0
	const FADE_WINDOW := 0.7  ## 尾段 70% 寿命内线性渐隐（旧 45%，淡出更早）
	const FALLBACK := Color(0.75, 0.28, 0.2)

	var _vel := Vector2.ZERO
	var _grav := GRAV
	var _life := 0.4
	var _age := 0.0
	var _size := 3.0
	var _color := FALLBACK

	func setup(pos: Vector2, color: Color, size: float, vel: Vector2, life: float) -> void:
		position = pos
		_color = color
		_size = size
		_vel = vel
		_life = maxf(life, 0.12)
		modulate.a = 0.9  # 起始略透明，整体更柔和
		z_index = 5

	func _process(delta: float) -> void:
		_age += delta
		_vel.y += _grav * delta
		_vel *= maxf(1.0 - 2.2 * delta, 0.0)  # 空气阻力
		position += _vel * delta
		# 渐隐窗口更早：尾段 70% 寿命线性淡出
		modulate.a = 0.9 * clampf((_life - _age) / maxf(_life * FADE_WINDOW, 0.01), 0.0, 1.0)
		if _age >= _life:
			queue_free()

	func _draw() -> void:
		# 柔边圆点：外圈抗锯齿柔边 + 内圈亮芯（替代旧 draw_rect 硬方块）
		var r := maxf(_size, 0.8)
		draw_circle(Vector2.ZERO, r, _color, true, -1.0, true)
		draw_circle(Vector2.ZERO, r * 0.55, _color.lightened(0.3), true, -1.0, true)


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

func _on_enemy_died(enemy_id: String, pos: Vector2, _xp: int, _gold: int, elite: bool) -> void:
	# 击杀反馈（G-1/G-2）：独特击杀音 + 柔化碎屑爆散（柔点，普通 4-6 / 精英 8-10 / Boss 14-18）
	SfxBus.play_hit("kill")
	_spawn_death_debris(pos, enemy_id, elite)
	# 连杀反馈：2 秒内击杀 >= 6 触发小慢动作（0.8x 0.15s）
	var now := Time.get_ticks_msec() / 1000.0
	_kill_times.append(now)
	while _kill_times.size() > 0 and _kill_times[0] < now - 2.0:
		_kill_times.pop_front()
	if _kill_times.size() >= 6:
		_kill_times.clear()
		EventBus.slow_mo.emit(0.8, 0.15)
		## 连杀反馈落雷门控（2026-08-12 二次修复 P0-4）：2 秒 6 连杀庆祝特效
		## 不再无条件发 lightning——无雷系构筑改发金色粒子雨（庆祝语义不变，无雷语义泄漏）
		if _school_holdings_of("lightning") > 0:
			EventBus.fx_explosion.emit(pos, "lightning")
		else:
			EventBus.fx_explosion.emit(pos, "gold")

func _on_fx_heal_text(pos: Vector2, amount: int) -> void:
	var number: DamageNumber = DamageNumberScene.instantiate()
	number.z_index = 100
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
	number.z_index = 100
	number.position = pos
	add_child(number)
	number.base_scale = 0.8
	number.play(amount, false, false, DOT_COLORS.get(kind, Color.WHITE))

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


func _on_fx_hit_slow(target: Node, crit: bool = false) -> void:
	## 打击感 P1+G-4：顿帧 hitstop——projectile/melee/summon 命中与 synergy 触发共用，
	## 暴击 60ms / 普通 30ms / Boss 80ms，因子 0.05、全局冷却 150ms；
	## 去重：同一帧同一目标只触发一次（与 synergy 触发不冲突）。
	if _hitstop_cd > 0.0:
		return
	var frame := _fx_frame
	var tid := target.get_instance_id() if is_instance_valid(target) else 0
	if frame == _hitstop_last_frame and tid == _hitstop_last_target:
		return
	_hitstop_last_frame = frame
	_hitstop_last_target = tid
	_hitstop_cd = HITSTOP_COOLDOWN
	var dur := HITSTOP_DUR_NORMAL
	if is_instance_valid(target) and bool(target.get("is_boss")) == true:
		dur = HITSTOP_DUR_BOSS
	elif crit:
		dur = HITSTOP_DUR_CRIT
	EventBus.slow_mo.emit(HITSTOP_FACTOR, dur)

## 震屏幅度压缩（特效柔化 2026-08-13）：power 越大衰减越快（双曲线衰减），
## 收口在唯一入口 _on_screen_shake——等价于 camera_shake 偏移公式加衰减，
## 但按铁律只改本文件：外部硬编码调用点（boss.gd 12/10、enemy.gd 6、
## summon.gd 4、synergy 3/0.8 等）无需改动即整体降幅。
## 数值：12→≈6.1（Boss 死亡 12→6 目标），10→≈5.6，6→≈4.0，3→≈2.4，1.5→≈1.3。
static func compress_shake_power(power: float) -> float:
	var p := maxf(power, 0.0)
	return p / (1.0 + p * 0.08)

func _on_screen_shake(power: float) -> void:
	## 节流 + 幅度压缩：先压缩再进 0.25s 合并窗口（冷却期内只保留最强一次）
	var p := compress_shake_power(power)
	if _shake_cd > 0.0:
		_shake_pending = maxf(_shake_pending, p)
		return
	_shake_cd = SHAKE_COOLDOWN
	_shake_pending = 0.0
	_apply_camera_shake(p)

func _apply_camera_shake(power: float) -> void:
	var camera := get_tree().get_first_node_in_group("camera")
	if is_instance_valid(camera) and camera.has_method("shake"):
		camera.shake(power)

func _process_shake_throttle(delta: float) -> void:
	if _shake_cd > 0.0:
		_shake_cd -= delta
		if _shake_cd <= 0.0 and _shake_pending > 0.0:
			_apply_camera_shake(_shake_pending)
			_shake_pending = 0.0

func _on_player_hit(_dmg: int, _pos: Vector2) -> void:
	# 护盾在场时受击反馈替换：玻璃/能量叮（护盾受击音），无护盾才播闷响 hurt
	var shielded := _shield_value() > 0.0
	SfxBus.play_hit("shield_hit" if shielded else "hurt")
	var player := get_tree().get_first_node_in_group("player")
	if is_instance_valid(player):
		_on_fx_hit_flash(player)
		if shielded:
			spawn_shield_hit_fx((player as Node2D).global_position, false)
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

## =====================================================================
## 地面持续效果视觉（Ground FX）：火地/水泽/毒雾/冰地/雷区/藤蔓
## 契约：
## - 纯视觉节点：不参与碰撞/伤害判定（伤害逻辑留在各 synergy 的数值区），
##   挂当前场景（current_scene，headless 测试回退 root），随效果结束自动
##   queue_free（节点自计时 + 调用方提前释放双保险），不泄漏；
## - 程序化 _draw 优先（火焰/毒雾/电弧/藤蔓），kenney 贴图粒子点缀余烬/毒沫，
##   不用静态贴图冒充动态效果（项目铁律）；
## - 全局限量 GROUND_FX_MAX（30）：超限淘汰场景中最旧的 Ground* 节点；
## - 接入方：fire/poison/thunder 等 synergy 通过 preload 静态工厂调用；
##   water/ice 的区域节点与 boss GroundZone 自带同风格 _draw 视觉。
## =====================================================================
const GROUND_FX_MAX := 30

## 地面视觉工厂：kind ∈ fire/poison/thunder/vine；返回节点（失败返回 null）。
## 节点名固定 "GroundFire" 等（测试按名字断言），自计时销毁。
static func spawn_ground_fx(kind: String, pos: Vector2, radius: float, life: float) -> Node2D:
	var node: Node2D
	match kind:
		"fire":
			node = GroundFire.new()
		"poison":
			node = GroundPoison.new()
		"thunder":
			node = GroundThunder.new()
		"vine":
			node = GroundVine.new()
		_:
			return null
	node.setup(pos, radius, life)
	node.name = "Ground" + kind.capitalize()
	var tree := Engine.get_main_loop() as SceneTree
	var parent: Node = null
	if tree != null:
		parent = tree.current_scene if tree.current_scene != null else tree.root
	if parent == null:
		return null
	_ground_cap(parent)
	parent.add_child(node)
	return node

## 上限淘汰：场景中 Ground* 子节点达到 GROUND_FX_MAX 时释放最早加入的。
static func _ground_cap(parent: Node) -> void:
	var live: Array = []
	for c in parent.get_children():
		if c is Node2D and str(c.name).begins_with("Ground"):
			live.append(c)
	while live.size() >= GROUND_FX_MAX:
		var oldest: Node = live.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()

## 护盾受击涟漪工厂：浅蓝扩散环 + 白光闪（broken=true 时双环+全白闪）。
## 纯程序化 _draw，自计时销毁；返回节点（测试按名字断言 "ShieldRipple"）。
static func spawn_shield_hit_fx(pos: Vector2, broken: bool) -> Node2D:
	var ripple := ShieldRipple.new()
	ripple.setup(pos, broken)
	ripple.name = "ShieldRipple"
	var tree := Engine.get_main_loop() as SceneTree
	var parent: Node = null
	if tree != null:
		parent = tree.current_scene if tree.current_scene != null else tree.root
	if parent == null:
		return null
	parent.add_child(ripple)
	return ripple

## 地面视觉共享工具：贴图缓存 + 循环粒子构造（内嵌类作用域隔离，自包含）。
class GroundTex:
	const FX_DIR := "res://assets/fx/kenney/"
	static var _cache: Dictionary = {}

	static func fetch(name: String) -> Texture2D:
		if _cache.has(name):
			return _cache[name]
		var tex: Texture2D = load(FX_DIR + name + ".png")
		if tex != null:
			_cache[name] = tex
		return tex

	## 循环发射贴图粒子（作为宿主子节点，随宿主销毁；加法混合可选）。
	static func loop_particles(parent: Node2D, tex_name: String, pos: Vector2,
			vel: Vector2, grav: Vector2, life: float, scale_min: float, scale_max: float,
			color: Color, additive: bool, amount: int = 8, spread: float = 28.0) -> CPUParticles2D:
		var tex := fetch(tex_name)
		if tex == null:
			return null
		var p := CPUParticles2D.new()
		p.position = pos
		p.texture = tex
		p.amount = amount
		p.lifetime = life
		p.one_shot = false
		p.emitting = true
		p.explosiveness = 1.0
		p.spread = spread
		p.gravity = grav
		if vel != Vector2.ZERO:
			p.direction = vel.normalized()
		p.initial_velocity_min = vel.length() * 0.65
		p.initial_velocity_max = vel.length() * 1.35
		p.scale_amount_min = scale_min
		p.scale_amount_max = scale_max
		var curve := Curve.new()
		curve.add_point(Vector2(0.0, 1.0))
		curve.add_point(Vector2(1.0, 0.18))
		p.scale_amount_curve = curve
		if additive:
			var mat := CanvasItemMaterial.new()
			mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			p.material = mat
		var grad := Gradient.new()
		grad.set_color(0, Color(color, 1.0))
		grad.set_color(1, Color(color, 0.0))
		p.color_ramp = grad
		p.color = Color.WHITE
		parent.add_child(p)
		return p

## 地面视觉基类：计时销毁 + 尾段淡出 + 逐帧刷新（子类覆写 _draw/_anim）。
class GroundBase:
	extends Node2D

	var radius := 60.0
	var life := 2.0
	var _age := 0.0
	var _fade := 0.0
	var _phase := 0.0

	func setup(pos: Vector2, r: float, l: float) -> void:
		global_position = pos
		radius = maxf(r, 10.0)
		life = maxf(l, 0.15)
		_fade = minf(0.4, life * 0.45)
		_phase = randf() * TAU
		z_index = -11

	func _process(delta: float) -> void:
		_age += delta
		_phase += delta
		if _age >= life:
			queue_free()
			return
		_anim(delta)
		modulate.a = _alpha()
		queue_redraw()

	func _anim(_delta: float) -> void:
		pass

	func _alpha() -> float:
		if _fade <= 0.0:
			return 1.0
		return clampf((life - _age) / _fade, 0.0, 1.0)

	func _ring(rad: float, n: int) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in n:
			pts.append(Vector2.from_angle(TAU * float(i) / float(n)) * rad)
		return pts

	func _jagged(from: Vector2, to: Vector2, steps: int, jitter: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		pts.append(from)
		var seg := to - from
		var perp := Vector2(-seg.y, seg.x).normalized()
		for i in steps:
			var t := float(i + 1) / float(steps)
			pts.append(from + seg * t + perp * randf_range(-jitter, jitter))
		pts[pts.size() - 1] = to
		return pts

## 火地：地面焦痕（暗色灼烧圆 + 放射裂纹）+ 4~6 簇程序化火焰舌（sin 摆动）+ 余烬粒子。
class GroundFire:
	extends GroundBase

	const SCORCH := Color(0.07, 0.045, 0.03)
	const FLAME_OUT := Color(1.0, 0.42, 0.12)
	const FLAME_MID := Color(1.0, 0.72, 0.22)
	const FLAME_CORE := Color(1.0, 0.95, 0.6)

	var _cracks: Array = []
	var _flames: Array = []

	func setup(pos: Vector2, r: float, l: float) -> void:
		super.setup(pos, r, l)
		var n := randi_range(7, 10)
		for i in n:
			_cracks.append([randf() * TAU, randf_range(0.45, 0.95)])
		var f := randi_range(4, 6)
		for i in f:
			_flames.append([TAU * float(i) / float(f) + randf_range(-0.3, 0.3),
				randf_range(0.65, 1.0), randf() * TAU])
		GroundTex.loop_particles(self, "spark_01", Vector2.ZERO, Vector2(0, -36),
			Vector2(0, -60), 0.8, 0.03, 0.07, Color(1.0, 0.62, 0.25), true, 12, 40.0)

	func _draw() -> void:
		# 地面焦痕（灼烧圆 + 暗芯）
		draw_circle(Vector2.ZERO, radius, Color(SCORCH, 0.62))
		draw_circle(Vector2.ZERO, radius * 0.72, Color(0.03, 0.02, 0.015, 0.8))
		# 放射裂纹
		for c in _cracks:
			var a: float = c[0]
			var len: float = radius * c[1]
			var tip := Vector2.from_angle(a) * len
			var pts := _jagged(Vector2.from_angle(a) * radius * 0.25, tip, 3, 3.0)
			draw_polyline(pts, Color(0.0, 0.0, 0.0, 0.55), 1.6, true)
		# 火焰舌（外焰/内焰分层 + 亮芯）
		for fl in _flames:
			var a: float = fl[0]
			var len: float = radius * fl[1]
			var wob := sin(_phase * 9.0 + fl[2]) * 0.22
			var base_a := a + wob
			var base_r := radius * 0.55
			var tip_r := base_r + len * (0.9 + 0.18 * sin(_phase * 7.0 + fl[2]))
			var tip_a := base_a + sin(_phase * 11.0 + fl[2]) * 0.16
			var base0 := Vector2.from_angle(base_a - 0.22) * base_r
			var base1 := Vector2.from_angle(base_a + 0.22) * base_r
			var tip := Vector2.from_angle(tip_a) * tip_r
			# 三角形分层（保证凸性，避免摆动自交导致三角剖分失败）
			draw_colored_polygon(PackedVector2Array([base0, tip, base1]),
				Color(FLAME_OUT, 0.85))
			var tip2 := Vector2.from_angle(tip_a) * (tip_r * 0.62)
			var mid0 := base0.lerp(tip, 0.45)
			var mid1 := base1.lerp(tip, 0.45)
			draw_colored_polygon(PackedVector2Array([mid0, tip2, mid1]),
				Color(FLAME_MID, 0.9))
			draw_circle(Vector2.ZERO.lerp(tip2, 0.7), 2.2, Color(FLAME_CORE, 0.9))
		# 橙色光晕环（呼吸脉动）
		draw_arc(Vector2.ZERO, radius * 1.08, 0.0, TAU, 32,
			Color(FLAME_OUT, 0.28 + 0.14 * sin(_phase * 6.0)), 2.0)

## 毒雾：多层波浪绿雾团（sin 扰动多边形，缓慢旋转）+ 上飘毒沫粒子。
class GroundPoison:
	extends GroundBase

	const MIST := Color(0.32, 0.72, 0.22)
	const MIST_BRIGHT := Color(0.55, 0.9, 0.35)

	func setup(pos: Vector2, r: float, l: float) -> void:
		super.setup(pos, r, l)
		GroundTex.loop_particles(self, "smoke_05", Vector2.ZERO, Vector2(0, -18),
			Vector2(0, -14), 1.15, 0.16, 0.26, Color(0.42, 0.8, 0.3), false, 9, 35.0)

	func _draw() -> void:
		for k in 3:
			var base_r := radius * (0.45 + 0.2 * float(k))
			var pts := PackedVector2Array()
			var n := 20
			for i in n:
				var a := TAU * float(i) / float(n)
				var wob := sin(a * 3.0 + _phase * (1.6 + 0.5 * float(k)) + float(k) * 2.1) * 8.0
				wob += sin(a * 5.0 - _phase * 1.1) * 4.0
				pts.append(Vector2.from_angle(a) * (base_r + wob))
			var col := Color(MIST, 0.13 + 0.05 * float(k)) if k < 2 else Color(MIST_BRIGHT, 0.10)
			draw_colored_polygon(pts, col)
			draw_polyline(pts, Color(MIST_BRIGHT, 0.22), 1.4, true)
		draw_circle(Vector2.ZERO, radius * 0.3, Color(MIST, 0.12))

## 雷区：地面电弧闪烁（每帧重随机锯齿线 + 高频抖动）+ 电光圆斑；加法混合。
class GroundThunder:
	extends GroundBase

	const ARC := Color(1.0, 0.88, 0.4)
	const ARC_BRIGHT := Color(1.0, 1.0, 0.75)

	func setup(pos: Vector2, r: float, l: float) -> void:
		super.setup(pos, r, l)
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = mat
		GroundTex.loop_particles(self, "spark_01", Vector2.ZERO, Vector2.ZERO,
			Vector2(0, 60), 0.3, 0.03, 0.06, Color(1.0, 0.9, 0.5), true, 10, 60.0)

	func _draw() -> void:
		draw_circle(Vector2.ZERO, radius, Color(ARC, 0.08))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 26, Color(ARC, 0.35), 1.5)
		var bolts := randi_range(4, 6)
		for i in bolts:
			var a := randf() * TAU
			var from := Vector2.from_angle(a) * radius * randf_range(0.2, 0.55)
			var to := Vector2.from_angle(a + randf_range(-0.8, 0.8)) * radius * randf_range(0.75, 1.05)
			var pts := _jagged(from, to, 5, radius * 0.08)
			draw_polyline(pts, Color(ARC, 0.45), 4.0, true)
			draw_polyline(pts, Color(ARC_BRIGHT, 0.9), 1.8, true)
		var sparks := randi_range(2, 4)
		for i in sparks:
			draw_circle(Vector2.from_angle(randf() * TAU) * radius * randf_range(0.3, 0.9),
				1.5, Color(ARC_BRIGHT, 0.8))

## 藤蔓：缠绕藤条（曲线卷须 + 叶片），随水 M3 定身释放；短寿命。
class GroundVine:
	extends GroundBase

	const VINE := Color(0.24, 0.55, 0.18)
	const VINE_LIGHT := Color(0.42, 0.78, 0.28)
	const LEAF := Color(0.5, 0.9, 0.32)

	var _grow := 0.0  # 生长进度 0→1（前 30% 寿命内卷须从中心长出）

	func setup(pos: Vector2, r: float, l: float) -> void:
		super.setup(pos, r, l)
		_grow = 0.0
		GroundTex.loop_particles(self, "circle_04", Vector2.ZERO, Vector2(0, -10),
			Vector2.ZERO, 0.9, 0.03, 0.05, Color(0.5, 0.9, 0.35), false, 6, 60.0)

	func _draw() -> void:
		# 生长动画（2026-08-12）：前 30% 寿命卷须从中心伸展到全长，命中点"藤蔓长出来"
		_grow = clampf(_age / maxf(life * 0.3, 0.12), 0.0, 1.0)
		var grow_r := 0.2 + 0.8 * _grow
		for k in 6:
			var a0 := TAU * float(k) / 6.0 + _phase * 0.3
			var curl := 2.4 if k % 2 == 0 else -2.4
			var pts := PackedVector2Array()
			var steps := 12
			for i in steps + 1:
				var t := float(i) / float(steps)
				var a := a0 + curl * t + sin(_phase * 2.0 + float(k) + t * 4.0) * 0.35
				pts.append(Vector2.from_angle(a) * radius * (0.25 + 0.75 * t) * grow_r)
			var vine_a := 0.45 + 0.5 * _grow
			draw_polyline(pts, Color(VINE, vine_a), 2.4, true)
			draw_polyline(pts, Color(VINE_LIGHT, 0.18 + 0.2 * _grow), 5.0, true)
			var tip := pts[pts.size() - 1]
			draw_circle(tip, 2.4, Color(LEAF, 0.95 * _grow))
			draw_circle(tip + Vector2.from_angle(a0 + curl + 0.9) * 4.0, 1.8, Color(LEAF, 0.75 * _grow))

## 护盾受击涟漪：浅蓝扩散环（加法感淡蓝）＋中心白闪；broken 时双环 + 全白闪更强烈。
## 自计时 0.45s 销毁，无粒子对象池依赖（低频事件型特效）。
class ShieldRipple:
	extends Node2D

	const LIFE := 0.45

	var broken := false
	var _age := 0.0

	func setup(pos: Vector2, is_broken: bool) -> void:
		global_position = pos
		broken = is_broken
		z_index = 3

	func _process(delta: float) -> void:
		_age += delta
		if _age >= LIFE:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var t := _age / LIFE
		var ease := 1.0 - pow(1.0 - t, 2.0)
		var alpha := 0.75 * (1.0 - t)
		# 主环（半径 12 → 34/46，浅蓝）
		draw_arc(Vector2.ZERO, 12.0 + ease * (34.0 if not broken else 46.0),
			0.0, TAU, 28, Color(SHIELD_RIPPLE_COLOR, alpha), 2.2)
		# 内亮环（更细更快）
		draw_arc(Vector2.ZERO, 8.0 + ease * (26.0 if not broken else 34.0),
			0.0, TAU, 24, Color(SHIELD_RIPPLE_BRIGHT, alpha * 0.8), 1.2)
		# 中心白闪（前 30% 强烈）
		var flash_a := (1.0 - t / 0.3) if t < 0.3 else 0.0
		draw_circle(Vector2.ZERO, 10.0 * (1.0 - t * 0.5), Color(1.0, 1.0, 1.0, flash_a * 0.55))
		if broken and t > 0.35:
			# 破碎：外圈碎点（4 个短线沿环散布）
			for i in 6:
				var a := TAU * float(i) / 6.0 + 0.3
				var r := 30.0 + ease * 30.0
				draw_line(Vector2.from_angle(a) * r * 0.9, Vector2.from_angle(a + 0.18) * r,
					Color(SHIELD_RIPPLE_BRIGHT, alpha * 0.9), 1.6)

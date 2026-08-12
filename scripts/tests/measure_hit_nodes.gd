extends Node2D
## 实测：100 发弹幕命中 10 敌人 → FxManager 峰值存活节点数（含数字/粒子/碎块）
## Run: godot --headless --path . res://scripts/tests/measure_hit_nodes.tscn

const PROJECTILE_SCENE := preload("res://scenes/game/projectile.tscn")
const ENEMY_SCENE := preload("res://scenes/game/enemy.tscn")
const FX_MANAGER_SCRIPT := preload("res://scripts/fx/fx_manager.gd")

var _fx: Node
var _peak := 0
var _frame := 0

func _ready() -> void:
	GameState.run.crit_chance = 0.0
	_fx = FX_MANAGER_SCRIPT.new()
	_fx.name = "FxManager"
	add_child(_fx)
	# 10 敌人环形摆放（间距 > 命中半径，每弹只命中 1 只）
	for i in 10:
		var e = ENEMY_SCENE.instantiate()
		e.setup("bat", 1, 1)
		e.hp = 500.0
		e.max_hp = 500.0
		e.speed = 0.0
		e.global_position = Vector2(600, 360) + Vector2.from_angle(TAU * float(i) / 10.0) * 60.0
		add_child(e)
	# 100 发弹幕从中心向各方向射出
	for i in 100:
		var dir := Vector2.from_angle(TAU * float(i) / 100.0)
		var proj = PROJECTILE_SCENE.instantiate()
		proj.setup({
			"position": Vector2(600, 360),
			"direction": dir,
			"speed": 320.0,
			"range": 120.0,
			"damage": 5.0,
			"element": "fire",
			"aoe": 0.0,
			"mods": {},
		})
		add_child(proj)

func _process(_delta: float) -> void:
	_frame += 1
	_peak = maxi(_peak, _fx.get_child_count())
	if _frame == 90:
		print("[MEASURE] hits=100 peak_fx_nodes=%d final_fx_nodes=%d" % [_peak, _fx.get_child_count()])
		get_tree().quit(0)

extends Node2D
## 关卡：地面/背景/围墙/波次/Boss，通关发 level_cleared

const BOSS_SCENE := preload("res://scenes/game/boss.tscn")
const SPAWNER_SCRIPT := preload("res://scripts/enemies/spawner.gd")
const TILE_SIZE := 16
const VIEW := Vector2(1280, 720)

var level_id := ""
var _boss_id := ""
var _boss_spawned := false
var _clear_emitted := false

func init_level(id: String) -> void:
	level_id = id
	var lv: Dictionary = _find_level(id)
	_boss_id = str(lv.get("boss", ""))
	_build_scene_background(str(lv.get("theme", "grass")))
	_build_walls()
	## 问题18：决战古神模式跳过小怪波次，直接进入 Boss 战
	var is_final := bool(GameState.run.get("final_boss_mode", false))
	var spawner := SPAWNER_SCRIPT.new()
	spawner.name = "Spawner"
	spawner.setup([] if is_final else lv.get("waves", []))
	add_child(spawner)
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.wave_state_changed.connect(_on_wave_state)
	if is_final:
		# 决战：空波次 → 直接出 Boss（0.8s 演出延迟后降临）
		EventBus.wave_state_changed.emit("古神降临！")
		## 修复（2026-08-11）：init_level 在 add_child 前调用，get_tree() 为 null，
		## create_timer 直接崩溃 → 决战 Boss 永不生成。deferred 到入树后再启动。
		call_deferred("_start_final_boss_delayed")


func _start_final_boss_delayed() -> void:
	## 决战：入树后 0.8s 演出延迟再出 Boss
	if not is_inside_tree():
		return
	get_tree().create_timer(0.8).timeout.connect(_spawn_boss)

func _find_level(id: String) -> Dictionary:
	for l in GameState.tables.get("levels", {}).get("levels", []):
		if str(l.get("id", "")) == id:
			return l
	return {}

func _build_scene_background(theme: String) -> void:
	## 草地背景（2026-08-10 v5）：世界空间平铺——背景跟随世界滚动（与怪物/地形一致），
	## 玩家移动时草地滚动、怪物相对静止，视觉正常（同吸血鬼幸存者做法）。
	## 相机 limit 限制在地图 0..1280x720 内，1280x1280 草地图覆盖整个地图，任何位置都是草地。
	var path := "res://assets/env/scene_grass.png"
	match theme:
		"forest":
			path = "res://assets/env/scene_forest.png"
		"stone":
			path = "res://assets/env/scene_stone.png"
		"temple":
			path = "res://assets/env/scene_temple.png"
		"lava":
			path = "res://assets/env/scene_lava.png"
	if not ResourceLoader.exists(path):
		path = "res://assets/env/scene_grass.png"
	# 草地正方形纹理（草地段 y 201..720 垂直无缝拼接成 1280x1280，跳过 200 行分界线防黑线）
	var src_img := (load(path) as Texture2D).get_image()
	var square_tex: Texture2D = load(path)
	if src_img != null:
		## blit_rect 要求源/目标图格式一致：PNG 解码格式可能与 RGBA8 不同，先统一再拷贝
		src_img.convert(Image.FORMAT_RGBA8)
		var square := Image.create(1280, 1280, false, Image.FORMAT_RGBA8)
		## 性能优化（批次B）：草地段 y 201..720（519 行）纵向无缝拼接成 1280x1280。
		## 每行一次 blit_rect 批量拷贝（共 1280 次），替代原 1280x1280 次 set_pixel
		## （约 164 万次逐像素 GDScript 调用），避免每次切关的背景生成卡顿。
		for y in 1280:
			var src_y := 201 + (y % 519)
			square.blit_rect(src_img, Rect2i(0, src_y, 1280, 1), Vector2i(0, y))
		square_tex = ImageTexture.create_from_image(square)
	# 世界空间背景：覆盖整个地图（0,0 起 1280x1280），跟随世界滚动
	var bg := Sprite2D.new()
	bg.name = "SceneBackground"
	bg.texture = square_tex
	bg.centered = false
	bg.position = Vector2.ZERO
	bg.z_index = -5
	add_child(bg)

func _build_walls() -> void:
	var wall := StaticBody2D.new()
	wall.name = "Walls"
	wall.collision_layer = 4  # prop 层：玩家/敌人 mask 均含 4，撞墙不可穿出
	var thickness := 16.0
	# 草地铺满全屏后顶部不再设墙：整张地图可走（四边围墙贴地图边界）
	var rects := [
		Rect2(-thickness, -thickness, VIEW.x + thickness * 2, thickness),
		Rect2(-thickness, VIEW.y, VIEW.x + thickness * 2, thickness),
		Rect2(-thickness, -thickness, thickness, VIEW.y + thickness * 2),
		Rect2(VIEW.x, -thickness, thickness, VIEW.y + thickness * 2),
	]
	for r in rects:
		var shape := RectangleShape2D.new()
		shape.size = r.size
		var col := CollisionShape2D.new()
		col.shape = shape
		col.position = r.position + r.size / 2.0
		wall.add_child(col)
	add_child(wall)

func _on_wave_state(state: String) -> void:
	if state == "clear" and not _boss_spawned:
		_boss_spawned = true
		_spawn_boss()

func _spawn_boss() -> void:
	_boss_spawned = true
	var boss := BOSS_SCENE.instantiate()
	var final_boss: bool = GameState.run.get("final_boss_mode", false)
	var boss_id := _boss_id
	if final_boss:
		boss_id = str(GameState.tables.get("levels", {}).get("final_boss", "final_god"))
	boss.setup_boss(boss_id, GameState.run.level, GameState.run.loop, final_boss)
	boss.global_position = Vector2(VIEW.x / 2.0, 320.0)  # 地面区（顶部墙 y=200 之下）
	add_child(boss)
	var boss_name := _boss_name(boss_id)
	EventBus.wave_state_changed.emit("Boss：%s" % boss_name)

func _boss_name(boss_id: String) -> String:
	for b in GameState.tables.get("enemies", {}).get("bosses", []):
		if str(b.get("id", "")) == boss_id:
			return str(b.get("name", boss_id))
	return boss_id

func _on_enemy_died(enemy_id: String, _pos: Vector2, _xp: int, _gold: int, _is_elite: bool = false) -> void:
	if _clear_emitted or not _boss_spawned:
		return
	if enemy_id == _boss_id or (GameState.run.get("final_boss_mode", false) and enemy_id == "final_god"):
		_clear_emitted = true
		EventBus.level_cleared.emit(level_id)

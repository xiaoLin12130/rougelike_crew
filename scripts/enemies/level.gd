extends Node2D
## 关卡：地面/背景/围墙/波次/Boss，通关发 level_cleared

const BOSS_SCENE := preload("res://scenes/game/boss.tscn")
const SPAWNER_SCRIPT := preload("res://scripts/enemies/spawner.gd")
const TILE_SIZE := 16
const VIEW := Vector2(640, 360)

var level_id := ""
var _boss_id := ""
var _boss_spawned := false
var _clear_emitted := false

func init_level(id: String) -> void:
	level_id = id
	var lv: Dictionary = _find_level(id)
	_boss_id = str(lv.get("boss", ""))
	_build_floor(str(lv.get("tile", "res://assets/sprites/gen/tile_grass.png")))
	_build_background()
	_build_walls()
	var spawner := SPAWNER_SCRIPT.new()
	spawner.name = "Spawner"
	spawner.setup(lv.get("waves", []))
	add_child(spawner)
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.wave_state_changed.connect(_on_wave_state)

func _find_level(id: String) -> Dictionary:
	for l in GameState.tables.get("levels", {}).get("levels", []):
		if str(l.get("id", "")) == id:
			return l
	return {}

func _build_floor(tile_path: String) -> void:
	var tml := TileMapLayer.new()
	tml.name = "Floor"
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	var src := TileSetAtlasSource.new()
	src.texture = load(tile_path)
	src.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	ts.add_source(src, 0)
	src.create_tile(Vector2i(0, 0))
	tml.tile_set = ts
	for y in int(VIEW.y / TILE_SIZE):
		for x in int(VIEW.x / TILE_SIZE):
			tml.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))
	add_child(tml)

func _build_background() -> void:
	var bg := Sprite2D.new()
	bg.name = "Background"
	bg.texture = load("res://assets/env/back_forest.png")
	bg.centered = false
	bg.modulate = Color(0.5, 0.5, 0.6, 0.55)
	bg.position = Vector2.ZERO
	bg.scale = Vector2(VIEW.x / 288.0, VIEW.y / 160.0)
	bg.z_index = -10
	add_child(bg)

func _build_walls() -> void:
	var wall := StaticBody2D.new()
	wall.name = "Walls"
	var thickness := 16.0
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
	var boss := BOSS_SCENE.instantiate()
	var final_boss: bool = GameState.run.get("final_boss_mode", false)
	var boss_id := _boss_id
	if final_boss:
		boss_id = str(GameState.tables.get("levels", {}).get("final_boss", "final_god"))
	boss.setup_boss(boss_id, GameState.run.level, GameState.run.loop, final_boss)
	boss.global_position = Vector2(VIEW.x / 2.0, 60.0)
	add_child(boss)
	var boss_name := _boss_name(boss_id)
	EventBus.wave_state_changed.emit("Boss：%s" % boss_name)

func _boss_name(boss_id: String) -> String:
	for b in GameState.tables.get("enemies", {}).get("bosses", []):
		if str(b.get("id", "")) == boss_id:
			return str(b.get("name", boss_id))
	return boss_id

func _on_enemy_died(enemy_id: String, _pos: Vector2, _xp: int, _gold: int) -> void:
	if _clear_emitted or not _boss_spawned:
		return
	if enemy_id == _boss_id or (GameState.run.get("final_boss_mode", false) and enemy_id == "final_god"):
		_clear_emitted = true
		EventBus.level_cleared.emit(level_id)

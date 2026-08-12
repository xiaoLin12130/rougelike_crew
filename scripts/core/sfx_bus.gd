extends Node
## 音效总线：封装 AudioStreamPlayer 池（轮换复用，不再每次 new）；换端（微信）只改此文件。
## 打击感 G-1（S 级）：play_hit(kind) 战斗音效入口——
##   池化 12 实例轮换 / 随机变调 ±12% / 同 kind 全局节流 0.04s / 同帧预算 3 次。
## 音效素材：assets/audio/kenney_*（Kenney Impact/Interface Sounds，CC0，许可见 assets/audio/kenney_*_license.txt）。

const HIT_POOL_SIZE := 12
const HIT_SFX_MIN_INTERVAL := 0.04  # 同 kind 全局节流（秒）
const HIT_SFX_FRAME_BUDGET := 3     # 同帧最多实播数（高攻速多命中只播 2-3 个）
const PITCH_JITTER_MIN := 0.88      # 随机变调 ±12%
const PITCH_JITTER_MAX := 1.12

const HIT_SFX_DIR := "res://assets/audio/"

## kind -> {paths=候选池（每次随机取一，听感去重复）, vol=基础音量, pitch=基础音调}
const HIT_SFX := {
	"hit": {
		"paths": ["impactPunch_medium_000.ogg", "impactPunch_medium_001.ogg", "impactPunch_medium_002.ogg"],
		"vol": -10.0, "pitch": 1.0,
	},
	"crit": {
		"paths": ["impactPunch_heavy_000.ogg", "impactPunch_heavy_001.ogg", "impactPunch_heavy_002.ogg"],
		"vol": -6.0, "pitch": 1.12,  # 暴击：更响 + 更高
	},
	"elite": {
		"paths": ["impactMetal_heavy_000.ogg", "impactMetal_heavy_001.ogg", "impactMetal_heavy_002.ogg"],
		"vol": -6.0, "pitch": 0.92,  # 精英命中：金属重击 + 降调
	},
	"boss": {
		"paths": ["impactMetal_heavy_000.ogg", "impactMetal_heavy_001.ogg", "impactMetal_heavy_002.ogg"],
		"vol": -4.0, "pitch": 0.85,  # Boss 命中：更沉更低
	},
	"kill": {
		"paths": ["impactGlass_medium_000.ogg", "impactGlass_medium_001.ogg", "impactGlass_medium_002.ogg"],
		"vol": -8.0, "pitch": 1.0,   # 击杀：玻璃碎裂（独特）
	},
	"hurt": {
		"paths": ["impactSoft_medium_000.ogg", "impactSoft_medium_001.ogg", "impactSoft_medium_002.ogg"],
		"vol": -8.0, "pitch": 0.95,  # 玩家受击：闷响
	},
	"upgrade": {
		"paths": ["confirmation_001.ogg", "confirmation_002.ogg", "confirmation_003.ogg"],
		"vol": -8.0, "pitch": 1.0,   # 升级：确认音
	},
	"buy": {
		"paths": ["click_001.ogg", "click_002.ogg", "click_003.ogg"],
		"vol": -8.0, "pitch": 1.0,   # 购买：点击音
	},
}

var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _last_played: Dictionary = {}   # kind -> 上次实播时刻（秒）
var _frame_budget := 0              # 当前帧已实播数
var _hit_stats: Dictionary = {}     # kind -> 实播计数（测试/监控）
var _throttled_stats: Dictionary = {}  # kind -> 被节流吞掉的次数

func _ready() -> void:
	for i in HIT_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.name = "SfxPool%d" % i
		add_child(p)
		_pool.append(p)

func _process(_delta: float) -> void:
	## 帧预算按 process 帧重置（headless 下 Engine.get_process_frames() 不可靠，
	## 自维护计数器由主循环驱动）
	_frame_budget = 0

## 通用播放（保持旧接口）：走池复用，不再每次 new + queue_free。
func play(sfx_path: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	_play_stream(sfx_path, volume_db, pitch)

## 战斗/UI 音效入口：kind ∈ HIT_SFX 键。节流规则：
##   1) 同 kind 最小间隔 0.04s（全局）；2) 同帧实播预算 3 次（超出静默丢弃）。
## 返回是否实播（测试断言用）。
func play_hit(kind: String) -> bool:
	var spec: Dictionary = HIT_SFX.get(kind, {})
	if spec.is_empty():
		return false
	var now := Time.get_ticks_msec() / 1000.0
	if float(_last_played.get(kind, -1.0)) > now - HIT_SFX_MIN_INTERVAL:
		_throttled_stats[kind] = int(_throttled_stats.get(kind, 0)) + 1
		return false
	if _frame_budget >= HIT_SFX_FRAME_BUDGET:
		return false
	_frame_budget += 1
	_last_played[kind] = now
	_hit_stats[kind] = int(_hit_stats.get(kind, 0)) + 1
	var paths: Array = spec.get("paths", [])
	var path := HIT_SFX_DIR + str(paths[randi() % maxi(paths.size(), 1)])
	var pitch := float(spec.get("pitch", 1.0)) * randf_range(PITCH_JITTER_MIN, PITCH_JITTER_MAX)
	_play_stream(path, float(spec.get("vol", 0.0)), pitch)
	return true

func _play_stream(sfx_path: String, volume_db: float, pitch: float) -> void:
	if not ResourceLoader.exists(sfx_path):
		return
	var stream: AudioStream = load(sfx_path)
	if stream == null:
		return
	if _pool.is_empty():
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()

## 实播统计（测试/监控）：kind -> 次数。
func hit_stats() -> Dictionary:
	return _hit_stats.duplicate()

## 被节流吞掉的次数合计（测试：验证节流生效）。
func throttled_total() -> int:
	var n := 0
	for k in _throttled_stats:
		n += int(_throttled_stats[k])
	return n

## 池实例数（测试：验证池固定不膨胀）。
func pool_size() -> int:
	return _pool.size()

## 命中音效分级助手（调用方通用）：暴击 > Boss > 精英 > 普通。
static func hit_kind_for(target: Node, crit: bool) -> String:
	if crit:
		return "crit"
	if is_instance_valid(target):
		if bool(target.get("is_boss")) == true:
			return "boss"
		if bool(target.get("is_elite")) == true:
			return "elite"
	return "hit"

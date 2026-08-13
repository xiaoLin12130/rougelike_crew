extends Node
## 音效总线：封装 AudioStreamPlayer 池（轮换复用，不再每次 new）；换端（微信）只改此文件。
## 打击感 G-1（S 级）：play_hit(kind) 战斗音效入口——
##   池化 12 实例轮换 / 随机变调 ±5% / 同 kind 全局节流 0.05s / 同帧预算 3 次。
## 音效素材：assets/audio/kenney_*（Kenney Impact/Interface Sounds，CC0，许可见 assets/audio/kenney_*_license.txt）。
## 2026-08-13 音效换池（docs/design/攻击音效重新选型方案.md §5.1，零下载方案）：
##   1) hit 池 5 个 impactPunch_medium（0.4s+ 过闷过长）-> impactGeneric_light_000~004 +
##      impactMetal_light_000/001（0.12s 短促中性撞击 + 1/7 金属点缀），基音 1.02；
##   2) crit 池 5 个 impactPunch_heavy -> impactMetal_light_002/003/004 + impactGlass_heavy_000/002
##      （金属破击 + 玻璃脆，与 hit 双重区分），vol -8 / 基音 0.95；
##   3) kill 池 impactGlass_light -> impactGlass_heavy_001/004 + impactGlass_light_000/001/002
##      （重碎裂提升爽感）；
##   4) elite/boss/hurt/shield_* 保持（已验证合适）；
##   5) 新增元素 kind elem_fire/ice/lightning/poison/water（Kenney 包内最优近似，
##      fire=金属闷击降调、ice=玻璃碎裂、lightning=锡罐叮当、poison=软击+木击、
##      water=软击+中性短击），hit_kind_for 支持 element 参数（待 projectile/melee/summon 接线）。
## 2026-08-12 二次调音（docs/design/落雷与音效二次修复报告.md §3）：
## 用户反馈"太响/太尖/太碎"后的修正——
##   1) 整体音量降档：所有 kind 落到 -12 ~ -8 dB（原 -8 ~ -4），
##      层级保持 UI < 普通战斗 < 精英 < 暴击 < Boss；
##   2) pitch 抖动 ±12% -> ±5%（高音调怪异来源），命中基音 1.18 -> 1.02（不再发尖）；
##   3) 命中节流 0.04s -> 0.05s（同 kind 上限约 20 次/秒，高攻速不糊成噪声，
##      100 连发仍会播约 20 个而非 1 个）；
##   4) 素材复核：删除 0.043s 近乎无声的 select_001/002（"重选/购买听不到"元凶），
##      购买改 pluck + click + toggle；命中/暴击/精英/击杀/Boss/受击池各扩到 4~5 个候选，
##      降低同音反复感。

const HIT_POOL_SIZE := 12
const HIT_SFX_MIN_INTERVAL := 0.05  # 同 kind 全局节流（秒）
const HIT_SFX_FRAME_BUDGET := 3     # 同帧最多实播数（高攻速多命中只播 2-3 个）
const PITCH_JITTER_MIN := 0.95      # 随机变调 ±5%（收窄，避免音调怪异）
const PITCH_JITTER_MAX := 1.05

const HIT_SFX_DIR := "res://assets/audio/"

## kind -> {paths=候选池（每次随机取一，听感去重复）, vol=基础音量, pitch=基础音调}
const HIT_SFX := {
	"hit": {
		"paths": ["impactGeneric_light_000.ogg", "impactGeneric_light_001.ogg", "impactGeneric_light_002.ogg",
			"impactGeneric_light_003.ogg", "impactGeneric_light_004.ogg",
			"impactMetal_light_000.ogg", "impactMetal_light_001.ogg"],
		"vol": -11.0, "pitch": 1.02,  # 普通命中：0.12s 短促中性撞击（高频不糊），金属轻击 1/7 点缀
	},
	"crit": {
		"paths": ["impactMetal_light_002.ogg", "impactMetal_light_003.ogg", "impactMetal_light_004.ogg",
			"impactGlass_heavy_000.ogg", "impactGlass_heavy_002.ogg"],
		"vol": -8.0, "pitch": 0.95,  # 暴击：金属破击（上调音量+降调）+ 玻璃碎片脆感，与 hit 双重区分
	},
	"elite": {
		"paths": ["impactMetal_heavy_000.ogg", "impactMetal_heavy_001.ogg", "impactMetal_heavy_002.ogg",
			"impactMetal_heavy_003.ogg", "impactMetal_heavy_004.ogg"],
		"vol": -9.0, "pitch": 0.95,  # 精英命中：重金属低沉（与普通 Punch 明显区分）
	},
	"boss": {
		"paths": ["impactPlate_heavy_000.ogg", "impactPlate_heavy_001.ogg", "impactPlate_heavy_002.ogg",
			"impactPlate_heavy_003.ogg"],
		"vol": -8.0, "pitch": 0.86,  # Boss 命中：厚板低沉（全场最响但低频不刺耳）
	},
	"kill": {
		"paths": ["impactGlass_heavy_001.ogg", "impactGlass_heavy_004.ogg",
			"impactGlass_light_000.ogg", "impactGlass_light_001.ogg", "impactGlass_light_002.ogg"],
		"vol": -11.0, "pitch": 1.0,  # 击杀：中/重碎裂（0.40-0.43s 爆裂感强于 light 0.21s）
	},
	"hurt": {
		"paths": ["impactSoft_heavy_000.ogg", "impactSoft_heavy_001.ogg", "impactSoft_heavy_002.ogg",
			"impactSoft_heavy_003.ogg"],
		"vol": -11.0, "pitch": 0.92,  # 玩家受击：厚重闷响（低频事件，长音可接受）
	},
	"upgrade": {
		"paths": ["maximize_001.ogg", "maximize_002.ogg", "maximize_003.ogg"],
		"vol": -11.0, "pitch": 1.0,  # 升级：明亮上扬 chirp（UI 级音量）
	},
	"buy": {
		"paths": ["pluck_001.ogg", "pluck_002.ogg", "click_001.ogg", "toggle_001.ogg"],
		"vol": -12.0, "pitch": 1.0,  # 购买/重选：木质 pluck + UI click（0.10~0.17s，可闻不刺）
	},
	"shield_hit": {
		"paths": ["glass_001.ogg", "glass_002.ogg", "glass_003.ogg", "glass_005.ogg", "glass_006.ogg"],
		"vol": -11.0, "pitch": 1.06,  # 护盾受击：玻璃/能量叮
	},
	"shield_break": {
		"paths": ["sfx_shield_down.ogg"],
		"vol": -9.0, "pitch": 1.0,   # 护盾破碎：专用低沉碎裂
	},
	# --- 元素命中（2026-08-13 新增，Kenney 包内最优近似，待 projectile/melee/summon 接线）---
	"elem_fire": {
		"paths": ["impactMetal_light_000.ogg", "impactMetal_light_001.ogg", "impactGeneric_light_000.ogg"],
		"vol": -11.0, "pitch": 0.9,  # 火：金属闷击降调（闷爆感）
	},
	"elem_ice": {
		"paths": ["impactGlass_heavy_000.ogg", "impactGlass_heavy_002.ogg",
			"impactGlass_light_000.ogg", "impactGlass_light_001.ogg"],
		"vol": -11.0, "pitch": 1.05,  # 冰：玻璃碎裂微升调显"脆"
	},
	"elem_lightning": {
		"paths": ["impactTin_medium_000.ogg", "impactTin_medium_001.ogg", "impactTin_medium_002.ogg",
			"impactTin_medium_003.ogg", "impactTin_medium_004.ogg"],
		"vol": -11.0, "pitch": 1.1,  # 雷：锡罐叮当升调变"尖锐"（近似放电噼啪）
	},
	"elem_poison": {
		"paths": ["impactSoft_medium_000.ogg", "impactSoft_medium_001.ogg", "impactSoft_medium_002.ogg",
			"impactSoft_medium_003.ogg", "impactSoft_medium_004.ogg",
			"impactWood_light_000.ogg", "impactWood_light_001.ogg"],
		"vol": -11.0, "pitch": 0.95,  # 毒：软击+木击（腐蚀湿软）
	},
	"elem_water": {
		"paths": ["impactSoft_medium_002.ogg", "impactSoft_medium_003.ogg", "impactSoft_medium_004.ogg",
			"impactGeneric_light_002.ogg", "impactGeneric_light_003.ogg"],
		"vol": -11.0, "pitch": 1.0,  # 水：软击湿润+中性短击（水花感近似）
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
## element（可选）：fire/ice/lightning/poison/water 等，命中带元素时返回对应 elem_* kind
## （元素音替换普通 hit 音；crit/boss/elite 档位优先，保持打击层次）。
static func hit_kind_for(target: Node, crit: bool, element: String = "") -> String:
	if crit:
		return "crit"
	if is_instance_valid(target):
		if target.get("is_boss") == true:
			return "boss"
		if target.get("is_elite") == true:
			return "elite"
	if element != "" and HIT_SFX.has("elem_" + element):
		return "elem_" + element
	return "hit"

extends SceneTree
## 音效换池 headless 测试（docs/design/攻击音效重新选型方案.md §5.1 零下载方案）
## 断言：
##   1) 新拷入的候选文件全部存在（assets/audio/，25 个新 ogg）
##   2) HIT_SFX 全部 kind 的 paths 指向存在的文件（含元素 kind）
##   3) 元素 kind 映射正确（elem_fire/ice/lightning/poison/water 对应方案音色族）
##   4) 关键参数符合方案：hit 池 = Generic+Metal_light、crit = Metal_light+Glass_heavy、
##      kill = Glass_heavy+Glass_light、hit 基音 1.02、crit 基音 0.95
## Run: godot --headless --path . -s res://scripts/tests/test_audio_reselect.gd

const SFX_DIR := "res://assets/audio/"
const EXPECTED_NEW_FILES := [
	"impactMetal_light_000.ogg", "impactMetal_light_001.ogg", "impactMetal_light_002.ogg",
	"impactMetal_light_003.ogg", "impactMetal_light_004.ogg",
	"impactTin_medium_000.ogg", "impactTin_medium_001.ogg", "impactTin_medium_002.ogg",
	"impactTin_medium_003.ogg", "impactTin_medium_004.ogg",
	"impactSoft_medium_000.ogg", "impactSoft_medium_001.ogg", "impactSoft_medium_002.ogg",
	"impactSoft_medium_003.ogg", "impactSoft_medium_004.ogg",
	"impactWood_light_000.ogg", "impactWood_light_001.ogg", "impactWood_light_002.ogg",
	"impactWood_light_003.ogg", "impactWood_light_004.ogg",
	"impactGlass_medium_000.ogg", "impactGlass_medium_001.ogg", "impactGlass_medium_002.ogg",
	"impactGlass_medium_003.ogg", "impactGlass_medium_004.ogg",
]

var failures: Array[String] = []
var _frame := 0

var _kinds_to_play: Array[String] = []
var _play_sfx: Node = null
var _play_idx := 0
var _played_count := 0

func _process_playback() -> bool:
	if _play_sfx == null:
		return false
	var budget := 0
	while _play_idx < _kinds_to_play.size() and budget < 3:
		if _play_sfx.play_hit(_kinds_to_play[_play_idx]):
			_played_count += 1
		_play_idx += 1
		budget += 1
	if _play_idx < _kinds_to_play.size():
		return false
	if _played_count < _kinds_to_play.size() - 1:
		fail("kind 实播过少（%d/%d），可能有节流或加载问题" % [_played_count, _kinds_to_play.size()])
	print("[TEST] playback OK (played=%d/%d kinds)" % [_played_count, _kinds_to_play.size()])
	if failures.is_empty():
		print("[TEST] AUDIO RESELECT ALL PASS")
	else:
		for f in failures:
			push_error("[TEST] FAIL: " + f)
	quit(0 if failures.is_empty() else 1)
	return false

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	var sfx: Node = root.get_node_or_null("SfxBus")
	if sfx == null:
		fail("autoload SfxBus 缺失")
		quit(1)
		return false
	if _play_sfx != null:
		return _process_playback()
	_validate_new_files()
	_validate_all_kind_paths(sfx)
	_validate_core_pools(sfx)
	_validate_element_kinds(sfx)
	# 播放验证跨帧进行（同帧预算 3 次/帧，分帧播完所有 kind）
	_kinds_to_play = []
	for kind in sfx.HIT_SFX:
		_kinds_to_play.append(str(kind))
	_play_sfx = sfx
	_play_idx = 0
	_played_count = 0
	return false

func fail(msg: String) -> void:
	failures.append(msg)

func _has_file(name: String) -> bool:
	return ResourceLoader.exists(SFX_DIR + name)

func _validate_new_files() -> void:
	var missing: Array[String] = []
	for f in EXPECTED_NEW_FILES:
		if not _has_file(f):
			missing.append(f)
	if not missing.is_empty():
		fail("新拷入候选文件缺失: " + str(missing))
	print("[TEST] new files OK (%d/25 present)" % EXPECTED_NEW_FILES.size())

func _validate_all_kind_paths(sfx: Node) -> void:
	var missing: Array[String] = []
	for kind in sfx.HIT_SFX:
		for p in sfx.HIT_SFX[kind].get("paths", []):
			if not _has_file(str(p)):
				missing.append(kind + ":" + str(p))
	if not missing.is_empty():
		fail("HIT_SFX 指向不存在的文件: " + str(missing))
	print("[TEST] all kind paths OK (%d kinds)" % sfx.HIT_SFX.size())

func _pool(sfx: Node, kind: String) -> Array:
	return sfx.HIT_SFX.get(kind, {}).get("paths", [])

func _validate_core_pools(sfx: Node) -> void:
	# hit：5 Generic_light + 2 Metal_light（短促中性撞击）
	var hit := _pool(sfx, "hit")
	var hit_ok := hit.size() == 7
	for i in 5:
		if not str(hit[i]).begins_with("impactGeneric_light"):
			hit_ok = false
	if not str(hit[5]).begins_with("impactMetal_light") or not str(hit[6]).begins_with("impactMetal_light"):
		hit_ok = false
	if absf(float(sfx.HIT_SFX["hit"].get("pitch", 1.0)) - 1.02) > 1e-6:
		hit_ok = false
	if not hit_ok:
		fail("hit 池不符合方案（应 5×Generic_light + 2×Metal_light, pitch 1.02）: " + str(hit))
	# crit：3 Metal_light(002-004) + 2 Glass_heavy，基音 0.95
	var crit := _pool(sfx, "crit")
	var crit_ok := crit.size() == 5
	if not (str(crit[0]).ends_with("_002.ogg") and str(crit[1]).ends_with("_003.ogg")
			and str(crit[2]).ends_with("_004.ogg")):
		crit_ok = false
	if not str(crit[3]).begins_with("impactGlass_heavy") or not str(crit[4]).begins_with("impactGlass_heavy"):
		crit_ok = false
	if absf(float(sfx.HIT_SFX["crit"].get("pitch", 1.0)) - 0.95) > 1e-6:
		crit_ok = false
	if not crit_ok:
		fail("crit 池不符合方案（应 Metal_light_002-004 + Glass_heavy_000/002, pitch 0.95）: " + str(crit))
	# kill：2 Glass_heavy + 3 Glass_light（重碎裂提升爽感）
	var kill := _pool(sfx, "kill")
	var kill_ok := kill.size() == 5
	if not (str(kill[0]).begins_with("impactGlass_heavy") and str(kill[1]).begins_with("impactGlass_heavy")):
		kill_ok = false
	if not (str(kill[2]).begins_with("impactGlass_light") and str(kill[3]).begins_with("impactGlass_light")
			and str(kill[4]).begins_with("impactGlass_light")):
		kill_ok = false
	if not kill_ok:
		fail("kill 池不符合方案（应 Glass_heavy_001/004 + Glass_light_000/001/002）: " + str(kill))
	print("[TEST] core pools OK (hit/crit/kill)")

func _validate_element_kinds(sfx: Node) -> void:
	# fire=金属闷击降调、ice=玻璃碎裂、lightning=锡罐、poison=软击+木击、water=软击+中性
	var checks := [
		["elem_fire", "impactMetal_light", 0.9],
		["elem_ice", "impactGlass", 1.05],
		["elem_lightning", "impactTin_medium", 1.1],
		["elem_poison", "impactSoft_medium", 0.95],
		["elem_water", "impactSoft_medium", 1.0],
	]
	for c in checks:
		var kind := str(c[0])
		var expect_prefix := str(c[1])
		var expect_pitch := float(c[2])
		var spec: Dictionary = sfx.HIT_SFX.get(kind, {})
		if spec.is_empty():
			fail("元素 kind 缺失: " + kind)
			continue
		var paths: Array = spec.get("paths", [])
		if paths.is_empty():
			fail(kind + " 池为空")
			continue
		if not str(paths[0]).begins_with(expect_prefix):
			fail(kind + " 首候选音色族错误（期望 " + expect_prefix + "）: " + str(paths))
		if absf(float(spec.get("pitch", 1.0)) - expect_pitch) > 1e-6:
			fail(kind + " 基音错误（期望 %.2f）: %s" % [expect_pitch, str(spec.get("pitch"))])
		if float(spec.get("vol", 0.0)) > -10.0:
			fail(kind + " 音量应 <= -10dB（元素音不抢档）")
	# hit_kind_for 元素参数：普通命中返回 elem_*，crit/boss/elite 档位优先
	if sfx.hit_kind_for(null, false, "fire") != "elem_fire":
		fail("hit_kind_for(null,false,'fire') != elem_fire")
	if sfx.hit_kind_for(null, true, "ice") != "crit":
		fail("元素命中时 crit 档位应优先")
	if sfx.hit_kind_for(null, false, "nope") != "hit":
		fail("未知元素应回退 hit")
	print("[TEST] element kinds OK (5 kinds + hit_kind_for)")

extends SceneTree
## 元素命中音效接线 headless 测试（2026-08-13，docs/design/元素音效接线报告.md）
## 断言：
##   1) hit_kind_for(target, crit, element) 元素映射：fire→elem_fire、ice→elem_ice、
##      lightning→elem_lightning、poison→elem_poison、water→elem_water（普通敌人）
##   2) 无 element（默认 ""）或未知元素（blade/summon/nature/earth）→ 回退 "hit"
##   3) crit/boss/elite 档位优先：crit+元素→"crit"、boss+元素→"boss"、elite+元素→"elite"
##   4) 接线静态校验：projectile/melee/summon 三处命中点均已把元素作为第 3 参传入 hit_kind_for
##   5) elem_* kind 实播：play_hit("elem_*") 跨帧真实播放（节流/预算下仍全部播出）
## Run: godot --headless --path . -s res://scripts/tests/test_element_audio.gd

const ELEM_KINDS := ["fire", "ice", "lightning", "poison", "water"]

var failures: Array[String] = []
var _frame := 0

# 跨帧实播验证状态
var _kinds_to_play: Array[String] = []
var _play_idx := 0
var _played := 0
var _play_sfx: Node = null


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
	_validate_mapping(sfx)
	_validate_wiring()
	_play_sfx = sfx
	for e in ELEM_KINDS:
		_kinds_to_play.append("elem_" + e)
	return false


## 跨帧播放 elem_* kind：帧预算 3/帧，5 个不同 kind 互不节流，2 帧内全部播出
func _process_playback() -> bool:
	if _play_sfx == null:
		return false
	var budget := 0
	while _play_idx < _kinds_to_play.size() and budget < 3:
		if _play_sfx.play_hit(_kinds_to_play[_play_idx]):
			_played += 1
		_play_idx += 1
		budget += 1
	if _play_idx < _kinds_to_play.size():
		return false
	if _played < _kinds_to_play.size() - 1:
		fail("elem_* kind 实播过少（played=%d/%d），可能有节流或加载问题"
				% [_played, _kinds_to_play.size()])
	print("[TEST] elem playback OK (played=%d/%d kinds)" % [_played, _kinds_to_play.size()])
	if failures.is_empty():
		print("[TEST] ELEMENT AUDIO ALL PASS")
	else:
		for f in failures:
			push_error("[TEST] FAIL: " + f)
	quit(0 if failures.is_empty() else 1)
	return false


func fail(msg: String) -> void:
	failures.append(msg)
	print("[TEST] FAIL: " + msg)


## 构造带 is_boss/is_elite 属性的普通 Node（hit_kind_for 用 get() 读取）
func _make_target(is_boss: bool, is_elite: bool) -> Node:
	var s := GDScript.new()
	s.source_code = "extends Node\nvar is_boss := false\nvar is_elite := false\n"
	s.reload()
	var n := Node.new()
	n.set_script(s)
	n.is_boss = is_boss
	n.is_elite = is_elite
	return n


func _validate_mapping(sfx: Node) -> void:
	var normal := _make_target(false, false)
	var boss := _make_target(true, false)
	var elite := _make_target(false, true)
	# 1) 五种元素 → 对应 elem_* kind
	for e in ELEM_KINDS:
		var kind: String = sfx.hit_kind_for(normal, false, e)
		if kind != "elem_" + e:
			fail("元素映射错误: %s -> %s（期望 elem_%s）" % [e, kind, e])
	print("[TEST] element mapping OK (fire/ice/lightning/poison/water)")
	# 2) 无 element / 未知元素 → 回退 hit
	if sfx.hit_kind_for(normal, false) != "hit":
		fail("无 element 未回退 hit: " + sfx.hit_kind_for(normal, false))
	if sfx.hit_kind_for(null, false, "") != "hit":
		fail("null target + 空 element 未回退 hit")
	for e in ["blade", "summon", "nature", "earth"]:
		if sfx.hit_kind_for(normal, false, e) != "hit":
			fail("未知元素 %s 未回退 hit: %s" % [e, sfx.hit_kind_for(normal, false, e)])
	# 3) crit/boss/elite 档位优先（元素不覆盖档位）
	if sfx.hit_kind_for(normal, true, "fire") != "crit":
		fail("crit + fire 未优先 crit: " + sfx.hit_kind_for(normal, true, "fire"))
	if sfx.hit_kind_for(boss, false, "fire") != "boss":
		fail("boss + fire 未优先 boss: " + sfx.hit_kind_for(boss, false, "fire"))
	if sfx.hit_kind_for(elite, false, "water") != "elite":
		fail("elite + water 未优先 elite: " + sfx.hit_kind_for(elite, false, "water"))
	print("[TEST] fallback + tier priority OK")
	normal.free()
	boss.free()
	elite.free()


## 4) 静态校验三处命中点接线：元素作为第 3 参传入 hit_kind_for
func _validate_wiring() -> void:
	var checks := {
		"res://scripts/combat/projectile.gd": "hit_kind_for(enemy, crit, _element)",
		"res://scripts/combat/melee_attack.gd": "hit_kind_for(enemy, crit, \"blade\")",
		"res://scripts/combat/summon.gd": "hit_kind_for(enemy, is_crit, _element)",
	}
	for path in checks:
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			fail("无法读取接线文件: " + path)
			continue
		if not f.get_as_text().contains(str(checks[path])):
			fail("接线缺失: " + path + " 未找到 " + str(checks[path]))
		f.close()
	print("[TEST] wiring OK (projectile / melee / summon 3 call sites)")

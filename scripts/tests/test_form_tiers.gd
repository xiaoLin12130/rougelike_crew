extends SceneTree
## A2 流派成型反馈 headless 测试：
##  1) 持有 1 件同流派道具 -> 无成型横幅；3/6/9 件 -> 各档位横幅恰好触发一次（不重复）
##  2) GameState.school_holdings 按 items.json tags 统计持有层数（道具堆叠 + 法术网格核心）
##  3) 升级三选一卡片：同流派已持有>=1 件时显示"联动已激活"标签；未持有则不显示
##  4) 构建面板道具格：第 2+ 件同流派显示"联动"角标
## Run: godot --headless --path . -s res://scripts/tests/test_form_tiers.gd

var failures: Array[String] = []
var _frame := 0
var _phase := 0
var _hud: CanvasLayer
var _lv: CanvasLayer
var _bp: CanvasLayer
var _gs: Node

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false
	match _phase:
		0:
			_gs = root.get_node("GameState")
			_gs.new_run()
			_gs.run.grid = [{"core": "fireball", "shell": ""}]
			_gs.run.items = {"poison_essence": 1}
			_hud = load("res://scenes/ui/hud.tscn").instantiate()
			root.add_child(_hud)
			if _hud._form_banner_count != 0:
				fail("持有 1 件毒流派不应触发横幅（count=%d）" % _hud._form_banner_count)
			if not _hud._formed_tiers.is_empty():
				fail("持有 1 件不应记录成型档位: " + str(_hud._formed_tiers))
			_phase = 1
		1:
			_gs.run.items = {"poison_essence": 3}
			_hud._check_form_tiers()
			if _hud._form_banner_count != 1:
				fail("3 件毒流派应触发 1 次横幅（got %d）" % _hud._form_banner_count)
			if not _hud._formed_tiers.has("poison:3"):
				fail("未记录 poison:3 档位: " + str(_hud._formed_tiers))
			if not _hud._form_label.visible:
				fail("成型横幅未显示")
			elif _hud._form_label.text.find("毒") < 0 or _hud._form_label.text.find("3") < 0:
				fail("横幅文案缺流派名/档位: " + str(_hud._form_label.text))
			_hud._check_form_tiers()
			if _hud._form_banner_count != 1:
				fail("同一档位重复触发横幅")
			_phase = 2
		2:
			_gs.run.items = {"poison_essence": 6}
			_hud._check_form_tiers()
			if _hud._form_banner_count != 2 or not _hud._formed_tiers.has("poison:6"):
				fail("6 件应触发第 2 档（count=%d tiers=%s）" % [_hud._form_banner_count, str(_hud._formed_tiers)])
			_gs.run.items = {"poison_essence": 9}
			_hud._check_form_tiers()
			if _hud._form_banner_count != 3 or not _hud._formed_tiers.has("poison:9"):
				fail("9 件应触发第 3 档（count=%d tiers=%s）" % [_hud._form_banner_count, str(_hud._formed_tiers)])
			_hud._check_form_tiers()
			if _hud._form_banner_count != 3:
				fail("9 件重复检查不应再触发")
			_phase = 3
		3:
			_gs.run.items = {"poison_essence": 3, "fire_ember": 3}
			_hud._check_form_tiers()
			if not _hud._formed_tiers.has("fire:3"):
				fail("3 件火流派应独立触发: " + str(_hud._formed_tiers))
			_phase = 4
		4:
			_gs.run.items = {"poison_essence": 2, "poison_m1": 1}
			_gs.run.grid = [{"core": "poison_cloud", "shell": ""}]
			var holdings: Dictionary = _gs.school_holdings()
			if int(holdings.get("poison", 0)) != 4:
				fail("school_holdings poison 应=4（2+1 道具 +1 核心），got %s" % str(holdings))
			if int(holdings.get("fire", 0)) != 0:
				fail("school_holdings fire 应=0: " + str(holdings))
			_gs.run.items = {"water_boil": 1}
			var multi: Dictionary = _gs.school_holdings()
			if int(multi.get("water", 0)) != 1 or int(multi.get("fire", 0)) != 1:
				fail("多 tag 道具（water_boil）应同时计入 water/fire: " + str(multi))
			_gs.run.items = {"poison_essence": 1}
			_lv = load("res://scenes/ui/levelup_overlay.tscn").instantiate()
			root.add_child(_lv)
			_lv.show_choices([
				{"id": "venom_flask", "name": "剧毒瓶", "rarity": "common", "description": "毒性测试", "icon": "", "tags": ["poison"]},
			])
			_phase = 5
		5:
			if _label_count(_lv._box, "联动") != 1:
				fail("持有毒流派时毒流派卡片应显示联动标签")
			_gs.run.grid = []
			_gs.run.items = {}
			_lv.show_choices([
				{"id": "venom_flask", "name": "剧毒瓶", "rarity": "common", "description": "毒性测试", "icon": "", "tags": ["poison"]},
			])
			_phase = 6
		6:
			if _label_count(_lv._box, "联动") != 0:
				fail("未持有毒流派时不应显示联动标签")
			_gs.run.items = {"fire_ember": 1}
			_lv.show_choices([
				{"id": "spell_part:fireball:rapid", "name": "迅捷·火球", "rarity": "rare", "description": "测试", "icon": "", "tags": ["spell_part"]},
			])
			_phase = 7
		7:
			if _label_count(_lv._box, "联动") != 1:
				fail("spell_part 火球在持有火流派时应显示联动标签")
			_gs.run.grid = []
			_gs.run.items = {"poison_essence": 2, "fire_ember": 1}
			_bp = load("res://scenes/ui/build_panel.tscn").instantiate()
			root.add_child(_bp)
			_bp.refresh()
			_phase = 8
		8:
			if _label_count(_bp._items_box, "联动") < 1:
				fail("构建面板 2 件毒流派道具应显示联动角标")
			_phase = 9
		9:
			if failures.is_empty():
				print("FORM TIERS ALL PASS")
			else:
				for f in failures:
					push_error("FORM TIERS FAIL: " + f)
			quit(0 if failures.is_empty() else 1)
			return true
	return false

func fail(msg: String) -> void:
	failures.append(msg)

func _label_count(node: Node, needle: String) -> int:
	var n := 0
	if node is Label and str((node as Label).text).find(needle) >= 0:
		n += 1
	for ch in node.get_children():
		n += _label_count(ch, needle)
	return n

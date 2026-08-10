extends Node
## 自动通关脚本：headless 下驱动玩家（风筝走位 + 自动攻击 + 自动升级/抉择）
## 运行：godot --headless --path . res://scenes/game/game_root.tscn -- --auto-play
## 退出码：0=通关 1=失败 2=超时

var _dash_pressed := false
var _frames := 0
var _last_report := 0.0
var _log: FileAccess
var _last_heartbeat := 0.0
var _frames_total := 0
static var _instances := 0
var _pending_spell: Array = []  # [core_id, shell_id]：满格时选中法术的替换目标（SpellReplace 用）
var _boss_dash_cd := 0.0

const ELEMENT_TAGS := ["fire", "ice", "lightning", "poison", "summon", "water", "nature", "light", "void", "blade"]

func _log_line(msg: String) -> void:
	var exists := FileAccess.file_exists("H:/rougelike_crew/.tools/autoplay_run.log")
	var f := FileAccess.open("H:/rougelike_crew/.tools/autoplay_run.log",
		FileAccess.READ_WRITE if exists else FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line(msg)
		f.flush()
		f.close()
	print(msg)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # 树暂停（升级三选一）时驱动仍然存活
	_instances += 1
	print("[AUTOPLAY] started")
	_log_line("[AUTOPLAY] started instances=%d" % _instances)

func _process(_delta: float) -> void:
	_frames += 1
	_frames_total += 1
	_boss_dash_cd = maxf(_boss_dash_cd - _delta, 0.0)
	# 自愈：暂停但无任何覆盖层 → 强制恢复
	if get_tree().paused:
		var scene := get_tree().current_scene
		var any_ui := false
		if scene:
			for n in ["LevelUpOverlay", "LoopChoice", "GameOver", "PauseMenu"]:
				var node := scene.get_node_or_null(n)
				if node and node.visible:
					any_ui = true
					break
		if not any_ui:
			get_tree().paused = false
			_log_line("[AUTOPLAY] self-heal unpause")
	# 心跳：每 1 秒游戏时间写一次（含暂停/帧数）
	if GameState.run.time - _last_heartbeat >= 1.0:
		_last_heartbeat = GameState.run.time
		_log_line("[HB] t=%.1f paused=%s frames=%d fps_now=%d hp=%d kills=%d" % [
			GameState.run.time, get_tree().paused, _frames_total, _frames, GameState.run.hp, GameState.run.kills])
		_frames = 0
	var scene := get_tree().current_scene
	if scene == null:
		return
	if GameState.run.time > 1500.0:
		print("[AUTOPLAY] TIMEOUT kills=", GameState.run.kills, " level=", GameState.run.level)
		var p2 := get_tree().get_first_node_in_group("player") as Node2D
		var en := get_tree().get_nodes_in_group("enemy")
		var kinds2 := {}
		for e in en:
			if is_instance_valid(e) and e.has_method("get_enemy_id"):
				var kid: String = e.get_enemy_id()
				kinds2[kid] = kinds2.get(kid, 0) + 1
		_log_line("[AUTOPLAY] TIMEOUT kills=%d level=%d hp=%d player=%s enemies=%s" % [
			GameState.run.kills, GameState.run.level, GameState.run.hp,
			str(p2.global_position) if p2 else "?", kinds2])
		get_tree().quit(2)
		return
	if _handle_overlays(scene):
		return
	_drive_player()
	if GameState.run.time - _last_report > 5.0:
		_last_report = GameState.run.time
		var enemies := get_tree().get_nodes_in_group("enemy")
		var player := get_tree().get_first_node_in_group("player")
		var dist_info := "none"
		if player and not enemies.is_empty():
			var ne: Node2D = null
			var nd := INF
			for e in enemies:
				if is_instance_valid(e):
					var d: float = player.global_position.distance_to(e.global_position)
					if d < nd:
						nd = d
						ne = e
			if ne:
				dist_info = "dist=%.0f player=%s enemy=%s mv=%s aim=%s" % [
					nd, player.global_position, ne.global_position,
					InputRouter.move_vector, InputRouter.aim_vector]
		var kinds := {}
		for e in enemies:
			if is_instance_valid(e) and e.has_method("get_enemy_id"):
				var kid: String = e.get_enemy_id()
				kinds[kid] = kinds.get(kid, 0) + 1
				if _is_boss(e):
					kinds[kid + "_hp"] = "%d/%d" % [int(e.hp), int(e.max_hp)]
		var hud := scene.get_node_or_null("HUD")
		var item_slots := -1
		var grid_slots := -1
		if hud:
			if hud.get("_items_box") != null:
				item_slots = hud._items_box.get_child_count()
			if hud.get("_grid_box") != null:
				grid_slots = hud._grid_box.get_child_count()
		_log_line("[AUTOPLAY] t=%d hp=%d lv=%d kills=%d enemies=%d dps=%d grid=%d items=%d %s" % [
			int(GameState.run.time), GameState.run.hp, GameState.run.player_level,
			GameState.run.kills, enemies.size(), int(GameState.estimate_dps()),
			GameState.run.grid.size(), GameState.run.items.size(), dist_info])
		_log_line("[HUD] item_slots=%d grid_slots=%d" % [item_slots, grid_slots])
		_log_line("[KINDS] " + str(kinds))

func _handle_overlays(scene: Node) -> bool:
	var lv := scene.get_node_or_null("LevelUpOverlay")
	if lv and lv.visible and not lv.current_choices.is_empty():
		var best: Dictionary = lv.current_choices[0]
		var best_score := -999999
		for c in lv.current_choices:
			var sc := _choice_score(c)
			if sc > best_score:
				best_score = sc
				best = c
		var choices_log: Array = []
		for c in lv.current_choices:
			choices_log.append("%s=%d" % [str(c.get("name", "?")), _choice_score(c)])
		_log_line("[AUTOPLAY] choices: " + ", ".join(choices_log))
		var bid: String = str(best.get("id", ""))
		if bid.begins_with("spell_part:"):
			var bp: PackedStringArray = bid.split(":")
			_pending_spell = [bp[1], bp[2] if bp.size() > 2 else ""]
		else:
			_pending_spell = []
		lv.choice_made.emit(bid)
		print("[AUTOPLAY] levelup -> ", best.get("name", "?"), " score=", best_score)
		_log_line("[AUTOPLAY] levelup -> %s score=%d" % [best.get("name", "?"), best_score])
		return true
	var lc := scene.get_node_or_null("LoopChoice")
	if lc and lc.visible:
		# 验收时限内直取古神：跳过 loop2 农场（省 5 关波次时间）
		EventBus.loop_choice.emit("boss")
		print("[AUTOPLAY] final boss now")
		_log_line("[AUTOPLAY] final boss now")
		return true
	var ws := scene.get_node_or_null("WandShop")
	if ws and ws.visible:
		# 法杖商店：买最贵的可负担法杖（含 3 把上限替换），否则直接离开
		ws.call("autoplay_handle")
		# 商店已关闭（购买完成）后用剩余金币升级主力法杖（每级 +8% 伤害）；
		# 替换模式未结束前不花钱，避免金不足导致商店卡死
		if not ws.visible:
			var wids: Array = GameState.current_wands()
			if not wids.is_empty():
				for _i in 3:
					if not GameState.upgrade_wand(str(wids[0])):
						break
		_log_line("[AUTOPLAY] wand shop handled")
		return true
	var sr := scene.get_node_or_null("SpellReplace")
	if sr and sr.visible:
		# 法术栏满替换：替换最差槽位；新法术比最差槽位还差则放弃
		if _pending_spell.size() == 2:
			var new_score := _spell_parts_score(str(_pending_spell[0]), str(_pending_spell[1]))
			var wi := _worst_slot_idx()
			if wi >= 0 and new_score > _slot_score(GameState.run.grid[wi]):
				sr.choose_made.emit(wi)
				_log_line("[AUTOPLAY] spell replace -> slot %d score=%d" % [wi, new_score])
			else:
				sr.call("choose_skip")
				_log_line("[AUTOPLAY] spell replace -> skip score=%d" % new_score)
		else:
			sr.call("choose_first")
			_log_line("[AUTOPLAY] spell replace -> slot 0 (fallback)")
		_pending_spell = []
		return true
	var go := scene.get_node_or_null("GameOver")
	if go and go.visible:
		var win: bool = GameState.run.hp > 0
		print("[AUTOPLAY] RESULT=", "VICTORY" if win else "DEFEAT",
			" kills=", GameState.run.kills, " time=", int(GameState.run.time),
			" loop=", GameState.run.loop, " level=", GameState.run.level,
			" hp=", GameState.run.hp, " gold=", GameState.run.gold)
		_log_line("[AUTOPLAY] RESULT=%s kills=%d time=%d loop=%d level=%d hp=%d gold=%d" % [
			"VICTORY" if win else "DEFEAT", GameState.run.kills, int(GameState.run.time),
			GameState.run.loop, GameState.run.level, GameState.run.hp, GameState.run.gold])
		get_tree().quit(0 if win else 1)
		return true
	return false

func _find_wand_buttons(node: Node) -> Array:
	## 返回 [[Button, price], ...]：商店里的购买按钮（文本以"金"结尾）
	var out: Array = []
	for c in node.get_children():
		if c is Button and str(c.text).ends_with("金") and not c.disabled:
			out.append([c, int(str(c.text).trim_suffix("金"))])
		out.append_array(_find_wand_buttons(c))
	return out

func _rarity_score(c: Dictionary) -> int:
	match str(c.get("rarity", "common")):
		"legendary":
			return 3
		"rare":
			return 2
		_:
			return 1

func _choice_score(c: Dictionary) -> int:
	## 选道具策略：法术按核心×外壳直伤打分；道具按稀有度 + DPS 收益 + 流派匹配打分
	var tags: Array = c.get("tags", [])
	if "spell_part" in tags:
		return _spell_choice_score(c)
	return _item_choice_score(c)

func _is_boss(e: Node) -> bool:
	## 敌人 id 是否在 Boss 表（用于 Boss 战走位）
	if not e.has_method("get_enemy_id"):
		return false
	var eid: String = e.get_enemy_id()
	for b in GameState.tables.get("enemies", {}).get("bosses", []):
		if str(b.get("id", "")) == eid:
			return true
	return false

func _led_aim_at(target: Node2D, from: Vector2, proj_speed: float = 330.0) -> Vector2:
	## 预判提前量瞄准：Boss 追着玩家直线移动，直瞄会系统性落后（命中率暴跌）
	var to_t: Vector2 = target.global_position - from
	var lead := Vector2.ZERO
	var bv = target.get("velocity")
	if bv is Vector2:
		var flight := maxf(to_t.length() / proj_speed, 0.1)
		lead = bv * flight
	return (to_t + lead).normalized()

func _core_def(core_id: String) -> Dictionary:
	for c in GameState.tables.get("spells", {}).get("cores", []):
		if str(c.get("id", "")) == core_id:
			return c
	return {}

func _shell_def(shell_id: String) -> Dictionary:
	if shell_id == "":
		return {}
	for s in GameState.tables.get("spells", {}).get("shells", []):
		if str(s.get("id", "")) == shell_id:
			return s
	return {}

func _grid_has_element(el: String) -> bool:
	for slot in GameState.run.grid:
		if str(_core_def(str(slot.get("core", ""))).get("element", "")) == el:
			return true
	return false

func _item_element(item_id: String) -> String:
	var def := GameState.item_def(item_id)
	for el in ELEMENT_TAGS:
		if el in def.get("tags", []):
			return el
	return ""

func _main_element() -> String:
	## 当前构筑主元素：网格核心 + 道具 tag 计数
	var counts := {}
	for slot in GameState.run.grid:
		var el := str(_core_def(str(slot.get("core", ""))).get("element", ""))
		if el != "":
			counts[el] = int(counts.get(el, 0)) + 1
	for item_id in GameState.run.items:
		var el := _item_element(str(item_id))
		if el != "":
			counts[el] = int(counts.get(el, 0)) + int(GameState.run.items[item_id])
	var best := ""
	var best_n := 0
	for el in counts:
		if int(counts[el]) > best_n:
			best = el
			best_n = int(counts[el])
	return best

func _spell_dps(core: Dictionary, shell: Dictionary) -> float:
	## 法术单槽 DPS 估算（与 GameState.estimate_dps 同口径，含外壳修正）
	var mods: Dictionary = shell.get("mods", {})
	var dmg := float(core.get("base_damage", 0.0)) * float(mods.get("damage_mult", 1.0))
	var shots := maxi(int(mods.get("shots", 1)), 1)
	var cd := maxf(float(core.get("cooldown", 1.0)) * float(mods.get("cooldown_mult", 1.0)), 0.1)
	var dps := dmg * float(shots) / cd
	var el := str(core.get("element", ""))
	if el == "summon":
		# 召唤上限 1 只：已有召唤核时大幅贬值
		if _grid_has_element("summon"):
			dps = maxf(dps * 0.25, 10.0)
		else:
			dps = maxf(dps, 45.0)
	var sid := str(shell.get("id", ""))
	match sid:
		"orbit":
			dps *= 0.6  # 环绕=近身持续伤害，风筝打法打不满
		"delay":
			dps *= 0.8  # 延时命中率低
		"pierce":
			dps *= 1.5  # 多段命中
		"bounce":
			dps *= 1.4
		"split":
			dps *= 1.3
		"drain":
			dps *= 1.1
	return dps

func _spell_parts_score(core_id: String, shell_id: String) -> int:
	## 法术组合分（不含满格机会成本）
	var core := _core_def(core_id)
	if core.is_empty():
		return 0
	var shell := _shell_def(shell_id)
	var score := int(_spell_dps(core, shell) * 10.0)
	var el := str(core.get("element", ""))
	if el != "" and el == _main_element():
		score += 80  # 本流派元素核心
	if shell_id == "drain":
		score += 50  # 吸血外壳：保命
	var base_dmg := float(core.get("base_damage", 0.0))
	if base_dmg <= 0.0:
		score -= 100
	if str(core.get("id", "")) in ["flash", "counterspell", "blessing", "frenzy", "mana_echo"]:
		score -= 60  # 低伤/辅助核
	# 状态价值（燃烧/中毒/减速/缠绕）
	for k in ["burn", "dot", "slow", "root", "poison"]:
		if float(core.get(k, 0.0)) > 0.0:
			score += 20
			break
	# 网格补位：格子少时优先填满法术（早期 DPS 主要靠槽位）
	if GameState.run.grid.size() < 3:
		score += 90
	elif GameState.run.grid.size() < 4:
		score += 50
	elif GameState.run.grid.size() < 5:
		score += 20
	return score

func _spell_choice_score(c: Dictionary) -> int:
	## 升级三选一中的法术：净收益 = 组合分 - 满格时被替换的最差槽位分
	var parts: PackedStringArray = str(c.get("id", "")).split(":")
	if parts.size() < 3:
		return 0
	var score := _spell_parts_score(parts[1], parts[2])
	if GameState.grid_full():
		score -= _worst_slot_score()
	return score

func _slot_score(slot: Dictionary) -> int:
	## 现有槽位评分（用于替换决策）
	var core := _core_def(str(slot.get("core", "")))
	var shell := _shell_def(str(slot.get("shell", "")))
	if core.is_empty():
		return 0
	var score := int(_spell_dps(core, shell) * 10.0)
	var el := str(core.get("element", ""))
	if el != "" and el == _main_element():
		score += 90
	return score

func _worst_slot_idx() -> int:
	var worst := -1
	var worst_score := 999999
	for i in GameState.run.grid.size():
		var s := _slot_score(GameState.run.grid[i])
		if s < worst_score:
			worst_score = s
			worst = i
	return worst

func _worst_slot_score() -> int:
	var wi := _worst_slot_idx()
	if wi < 0:
		return 0
	return _slot_score(GameState.run.grid[wi])

func _item_choice_score(c: Dictionary) -> int:
	## 道具分：稀有度 + DPS 收益（随当前 DPS 缩放）+ 流派匹配 + 保命词条
	var score := _rarity_score(c) * 50
	var tags: Array = c.get("tags", [])
	var dps := GameState.estimate_dps()
	var hit := 0.0
	for t in ["atk", "attack_speed", "crit", "crit_dmg", "cooldown", "area"]:
		if t in tags:
			var v := GameState.item_value(c, 1)
			var gain := v
			if str(c.get("curve", {}).get("type", "")) == "multiplicative":
				if t == "cooldown":
					gain = 1.0 / maxf(v, 0.05) - 1.0
				else:
					gain = v - 1.0
			if t == "crit":
				gain *= 0.6
			elif t == "crit_dmg":
				gain *= 0.8
			elif t == "area":
				gain *= 0.5
			hit += gain
	score += int(dps * hit * 8.0)
	if "lifesteal" in tags and GameState.run.hp < GameState.run.max_hp * 0.65:
		score += 70
	if "summon" in tags:
		score += 30
	if "drawback" in tags and GameState.run.hp < GameState.run.max_hp * 0.5:
		score -= 80
	for t in tags:
		if str(t).begins_with("mechanic:"):
			score += 10
	var main_el := _main_element()
	if main_el != "" and _item_element(str(c.get("id", ""))) == main_el:
		score += 60  # 本流派道具
	return score

func _drive_player() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var enemies := get_tree().get_nodes_in_group("enemy")
	var nearest: Node2D = null
	var nearest_dist := INF
	var ranged_target: Node2D = null
	var ranged_dist := INF
	var near_count := 0
	for e in enemies:
		if not is_instance_valid(e):
			continue
		var d: float = player.global_position.distance_to(e.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = e
		if e.has_method("is_ranged") and e.is_ranged() and d < ranged_dist:
			ranged_dist = d
			ranged_target = e
		if d < 90.0:
			near_count += 1
	var mv := Vector2.ZERO
	var aim := Vector2.RIGHT
	var side := Vector2.ZERO  # 环绕切线方向（函数级声明：贴墙 fallback 需要）
	var aim_target := ranged_target if ranged_target != null else nearest
	var boss_present: Node2D = null
	for e in enemies:
		if is_instance_valid(e) and _is_boss(e):
			boss_present = e
			break
	# Boss 战（可带少量小怪）：近处小怪 ≤6 只时绕 Boss 转圈集火，小怪靠溅射/穿透顺带清
	var near_adds := 0
	if boss_present != null:
		for e in enemies:
			if is_instance_valid(e) and e != boss_present \
					and player.global_position.distance_to(e.global_position) < 100.0:
				near_adds += 1
	var boss_fight: bool = boss_present != null and near_adds <= 6
	if nearest == null:
		mv = (GameState.MAP_SIZE / 2.0 - player.global_position).normalized() * 0.5
	else:
		if aim_target != null:
			aim = (aim_target.global_position - player.global_position).normalized()
		# Boss 在场时优先集火 Boss（Boss 战拖沓的根因：伤害全被小怪分摊）；
		# 血量充足时无视贴脸小怪，靠闪避/溅射顺带清场；残血才转防御
		if boss_present != null and boss_present != nearest \
				and GameState.run.hp >= GameState.run.max_hp * 0.35:
			aim = _led_aim_at(boss_present, player.global_position)
		if boss_fight:
			# Boss 战：保持 150-210 距离绕 Boss 转圈（不贴墙角），光柱/弹幕靠走位与闪避
			var to_boss: Vector2 = boss_present.global_position - player.global_position
			var bd: float = to_boss.length()
			var tangent: Vector2 = Vector2(-to_boss.y, to_boss.x).normalized()
			side = tangent  # 供 mv 归零时兜底沿切线绕行
			if _frames % 300 < 150:
				tangent = -tangent  # 每 5s 换向，避免单侧绕圈
			var radial := 0.15
			var low_hp: bool = GameState.run.hp < GameState.run.max_hp * 0.5
			if low_hp:
				# 低血量：拉远到 280-340（出光柱射程，火球/冰锥仍能命中）
				if bd > 340.0:
					radial = 0.7
				elif bd < 280.0:
					radial = -0.9
				else:
					radial = 0.0
			else:
				if bd > 220.0:
					radial = 0.8
				elif bd < 150.0:
					radial = -0.9
			mv = tangent * 0.75 + to_boss.normalized() * radial
			aim = _led_aim_at(boss_present, player.global_position)
		else:
		# 敌群质心：从质心反方向逃跑，避免"逃离最近却被包围"
			var centroid := Vector2.ZERO
			var count := 0
			for e in enemies:
				if is_instance_valid(e) and player.global_position.distance_to(e.global_position) < 300.0:
					centroid += e.global_position
					count += 1
			var away: Vector2
			if count > 0:
				away = (player.global_position - centroid / count).normalized()
			else:
				away = (player.global_position - nearest.global_position).normalized()
			side = Vector2(-away.y, away.x)
			if _frames % 120 < 60:
				side = -side
			var flee := 0.0
			var danger := 170.0
			if GameState.run.hp < 40:
				danger = 260.0  # 低血量 → 更早拉开距离
			var many_ranged: bool = ranged_target != null and enemies.size() >= 4
			if many_ranged and nearest_dist > 140.0:
				# 远程怪多 → 主动压向最近的远程怪（近战怪跟着跑，逐个解决）
				mv = (ranged_target.global_position - player.global_position).normalized() * 0.85
			elif nearest_dist > 240.0:
				# 远处没有威胁 → 去安全角落（离敌群最远的角），避免开局被合围
				var corner := _safe_corner(player.global_position, centroid, count)
				mv = (corner - player.global_position).normalized() * 0.9
				if enemies.size() <= 3:
					mv = (nearest.global_position - player.global_position).normalized() * 0.9  # 收尾：追击
			elif nearest_dist < danger:
				flee = 1.0 - nearest_dist / danger
				mv = away * flee * 0.9 + side * 0.55
			elif enemies.size() <= 2:
				# 收尾阶段：绕圈压近，避免与最后一只远程怪僵持
				mv = (nearest.global_position - player.global_position).normalized() * 0.6 + side * 0.5
			else:
				mv = side * 0.55  # 安全距离 → 环绕
	# 血包拾取：低血量时优先冲向附近血包（配合 110px 磁吸半径）
	if GameState.run.hp < GameState.run.max_hp * 0.75:
		var packs := get_tree().get_nodes_in_group("health_pack")
		var pack: Node2D = null
		var pack_dist := INF
		for pk in packs:
			if not is_instance_valid(pk):
				continue
			var pd: float = player.global_position.distance_to(pk.global_position)
			if pd < pack_dist:
				pack_dist = pd
				pack = pk
		if pack != null and pack_dist <= 260.0 and pack_dist >= 30.0:
			mv = (pack.global_position - player.global_position).normalized()
			if nearest != null:
				aim = (nearest.global_position - player.global_position).normalized()
	# 地面预警躲避：root_zone/lava/meteor 圆圈落在附近 → 远离圆心
	var danger_dir := Vector2.ZERO
	var danger_any := false
	for e in enemies:
		if not is_instance_valid(e):
			continue
		var tgs = e.get("_telegraphs")
		if tgs is Array:
			for t in tgs:
				if str(t.get("kind", "")) == "circle":
					var cpos: Vector2 = t.get("pos", Vector2.ZERO)
					var dd: float = player.global_position.distance_to(cpos)
					if dd < 110.0:
						danger_any = true
						if dd > 20.0:
							danger_dir += (player.global_position - cpos).normalized() * (1.0 - dd / 110.0)
	if danger_any:
		if danger_dir.length_squared() > 0.01:
			mv = (danger_dir.normalized() * 0.9 + mv * 0.3).normalized()
		elif mv.length_squared() > 0.01:
			mv = mv.normalized()  # 圈压在脚下：保持原方向移动脱离
		else:
			mv = Vector2.from_angle(TAU * float(_frames % 360) / 360.0)  # 原地站桩：任意方向先跑
	# 贴墙处理：mv 指向墙外时削掉法线分量，改沿墙切向移动，避免顶墙被围殴卡死
	var m := GameState.MAP_SIZE
	var wall := 48.0
	if player.global_position.x < wall and mv.x < 0.0:
		mv.x = 0.0
	if player.global_position.x > m.x - wall and mv.x > 0.0:
		mv.x = 0.0
	if player.global_position.y < 210.0 and mv.y < 0.0:
		mv.y = 0.0
	if player.global_position.y > m.y - wall and mv.y > 0.0:
		mv.y = 0.0
	# 贴墙矫正：靠近任何一面墙时限制朝向墙的移动分量，避免整面墙站桩挨打（验证根因）
	if player.global_position.y > m.y - 80.0:
		mv.y = minf(mv.y, 0.35)
	if player.global_position.y < 80.0:
		mv.y = maxf(mv.y, -0.35)
	if player.global_position.x < 80.0:
		mv.x = minf(mv.x, 0.35)
	if player.global_position.x > m.x - 80.0:
		mv.x = maxf(mv.x, -0.35)
	# 低血量贴墙脱困：被堵墙角时强制向场内移动，避免贴墙被围殴致死
	if GameState.run.hp < GameState.run.max_hp * 0.5:
		var threat_count := 0
		var threat_dist := INF
		for e in enemies:
			if is_instance_valid(e):
				var d: float = player.global_position.distance_to(e.global_position)
				threat_dist = minf(threat_dist, d)
				if d < 220.0:
					threat_count += 1
		if threat_count >= 2 or threat_dist < 120.0:
			# 突围：向 120px 采样圈内怪最少的 8 方向之一跑（比朝中心更有效）
			var escape_dir := _escape_direction(player.global_position, enemies)
			if escape_dir != Vector2.ZERO:
				mv = escape_dir
			else:
				var to_center: Vector2 = (GameState.MAP_SIZE / 2.0 - player.global_position).normalized()
				mv = mv.lerp(to_center, 0.8).normalized()
			# 贴墙时强制加上离墙分量（escape 方向可能仍压墙）
			if player.global_position.y > m.y - 80.0:
				mv.y = -absf(mv.y)
			if player.global_position.y < 80.0:
				mv.y = absf(mv.y)
			if player.global_position.x < 80.0:
				mv.x = absf(mv.x)
			if player.global_position.x > m.x - 80.0:
				mv.x = -absf(mv.x)
	if mv.length_squared() < 0.01 and not enemies.is_empty():
		mv = side  # 贴墙且无有效方向 → 沿墙绕行
	InputRouter.move_vector = mv.normalized() if mv.length_squared() > 0.01 else Vector2.ZERO
	InputRouter.external_move = InputRouter.move_vector.length_squared() > 0.01
	InputRouter.aim_override = aim
	# 近身(≤70px)必闪；低血量时更积极
	var dash_now: bool = nearest_dist < 70.0 if nearest != null else false
	# Boss 战周期性短闪（无敌帧覆盖弹幕环/跳跃圈），光柱预警时立即闪
	if boss_fight and _boss_dash_cd <= 0.0:
		var tgs = boss_present.get("_telegraphs")
		var beam_now := false
		if tgs is Array:
			for t in tgs:
				if str(t.get("kind", "")) == "line":
					beam_now = true
					break
		dash_now = true
		_boss_dash_cd = 1.2 if beam_now else 1.8
	if GameState.run.hp < 40:
		dash_now = dash_now or near_count >= 1
	if dash_now and not _dash_pressed:
		Input.action_press("dash")
		_dash_pressed = true
	elif _dash_pressed:
		Input.action_release("dash")
		_dash_pressed = false

func _escape_direction(from: Vector2, enemies: Array) -> Vector2:
	## 低血量突围：8 方向采样，返回 140px 处敌人数最少的方向（避开墙）
	var best := Vector2.ZERO
	var best_count := 999
	var best_away := -INF
	var nearest_pos := Vector2.ZERO
	var nearest_d := INF
	for e in enemies:
		if is_instance_valid(e):
			var d: float = from.distance_to(e.global_position)
			if d < nearest_d:
				nearest_d = d
				nearest_pos = e.global_position
	for i in 8:
		var dir := Vector2.from_angle(TAU * i / 8.0)
		var sample: Vector2 = from + dir * 140.0
		var m := GameState.MAP_SIZE
		if sample.x < 40.0 or sample.x > m.x - 40.0 or sample.y < 40.0 or sample.y > m.y - 40.0:
			continue  # 采样点出墙则跳过
		var cnt := 0
		for e in enemies:
			if is_instance_valid(e) and sample.distance_to(e.global_position) < 120.0:
				cnt += 1
		var away := dir.dot(from - nearest_pos) if nearest_d < INF else 0.0
		if cnt < best_count or (cnt == best_count and away > best_away):
			best_count = cnt
			best_away = away
			best = dir
	return best

func _safe_corner(player_pos: Vector2, centroid: Vector2, count: int) -> Vector2:
	var m := GameState.MAP_SIZE
	var corners := [Vector2(40, 40), Vector2(m.x - 40, 40), Vector2(40, m.y - 40), Vector2(m.x - 40, m.y - 40)]
	var best := Vector2(30, 30)
	var best_d := -INF
	var ref := centroid / maxi(count, 1)
	for c in corners:
		var d: float = ref.distance_to(c) + player_pos.distance_to(c) * 0.1
		if d > best_d:
			best_d = d
			best = c
	return best

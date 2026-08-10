extends Node
## N2 通用道具机制（无效道具修复集中营，只新增不改既有语义）：
## - trinket_frost 霜之心：冰霜伤害 +25%/层，冻结时间 +0.3s/层
## - trinket_storm 雷核：雷电伤害 +25%/层（落雷翻倍在 thunder_synergy）
## - fire_lava_amulet 熔岩护符：火焰命中附带生命上限 0.5%/层 真伤（上限 5%）
## - defense_stone_skin 石肤：受到伤害 -10%/层（上限 35%），player_hit 钩子侧补结
## - curse_fear_word 恐惧咒：受到伤害 -8%/层，player_hit 钩子侧补结
## 防御约定：回调全部空值/存活检查，异常只影响本脚本、不扩散。

const TRINKET_FROST := "trinket_frost"
const TRINKET_STORM := "trinket_storm"
const TRINKET_DMG := 0.25      ## 饰品同系伤害 +25%/件
const FREEZE_EXTRA := 0.3      ## 霜之心冻结 +0.3s/件


func _ready() -> void:
	if SynergyRegistry == null:
		push_warning("[MechItems] SynergyRegistry 不可用，通用道具机制未注册")
		return
	SynergyRegistry.register("projectile_hit", _on_projectile_hit)
	SynergyRegistry.register("player_hit", _on_player_hit)
	EventBus.apply_status.connect(_on_apply_status)
	print("[SYNERGY] mech_items registered")


## 饰品持有件数（run.trinkets 槽位）
func _trinket_count(tid: String) -> int:
	if GameState == null or GameState.run == null:
		return 0
	var n := 0
	for t in GameState.run.get("trinkets", []):
		if str(t) == tid:
			n += 1
	return n


## 弹幕命中：饰品同系增伤 + 熔岩护符真伤
func _on_projectile_hit(ctx: Dictionary) -> void:
	if not is_inside_tree():
		return
	var enemy = ctx.get("enemy")
	if not is_instance_valid(enemy):
		return
	var dmg := int(ctx.get("dmg", 0))
	if dmg <= 0:
		return
	var element := str(ctx.get("element", ""))
	var tf := _trinket_count(TRINKET_FROST)
	if tf > 0 and element == "ice":
		_extra_damage(enemy, maxi(roundi(float(dmg) * TRINKET_DMG * float(tf)), 1), "ice")
	var ts := _trinket_count(TRINKET_STORM)
	if ts > 0 and element == "lightning":
		_extra_damage(enemy, maxi(roundi(float(dmg) * TRINKET_DMG * float(ts)), 1), "lightning")
	if element == "fire" and GameState != null:
		var lava := GameState.item_def("fire_lava_amulet")
		var lava_stacks := GameState.total_stacks("fire_lava_amulet")
		# 0 层不生效：item_value(linear) 在 0 层返回 base，不加层数守卫会白送真伤
		if not lava.is_empty() and lava_stacks > 0:
			var pct := float(GameState.item_value(lava, GameState.total_stacks("fire_lava_amulet")))
			if pct > 0.0:
				var max_hp := 0.0
				var v = enemy.get("max_hp")
				if v != null:
					max_hp = float(v)
				var bonus := maxi(roundi(max_hp * pct), 1)
				if enemy.has_method("_take_raw"):
					enemy.call("_take_raw", bonus)
					EventBus.damage_dealt.emit(bonus, _enemy_pos(enemy), false)


## 玩家受击（game_root 扣血后触发）：石肤/恐惧咒按曲线比例补结（退款已扣伤害）
func _on_player_hit(ctx: Dictionary) -> void:
	if not is_inside_tree() or GameState == null:
		return
	var taken := float(ctx.get("taken", 0.0))
	if taken <= 0.0:
		return
	var reduction := 0.0
	# 0 层不生效：item_value(linear) 在 0 层返回 base，不加守卫会白送减伤
	var ss_stacks := GameState.total_stacks("defense_stone_skin")
	if ss_stacks > 0:
		var ss := GameState.item_def("defense_stone_skin")
		if not ss.is_empty():
			reduction += float(GameState.item_value(ss, ss_stacks))
	var fw_stacks := GameState.total_stacks("curse_fear_word")
	if fw_stacks > 0:
		var fw := GameState.item_def("curse_fear_word")
		if not fw.is_empty():
			reduction += float(GameState.item_value(fw, fw_stacks))
	reduction = clampf(reduction, 0.0, 0.75)
	if reduction > 0.0:
		GameState.heal(taken * reduction)


## 冻结施加：霜之心延长冻结 +0.3s/件（call_deferred 保证晚于敌人 _on_status 覆盖）
func _on_apply_status(target: Node, kind: String, _stacks: int) -> void:
	if kind != "freeze" or not is_instance_valid(target):
		return
	var n := _trinket_count(TRINKET_FROST)
	if n <= 0 or target.get("_freeze_left") == null:
		return
	var cur := float(target.get("_freeze_left"))
	var extended := maxf(cur, 1.0 + FREEZE_EXTRA * float(n))
	target.call_deferred("set", "_freeze_left", extended)


func _extra_damage(enemy, dmg: int, element: String) -> void:
	if dmg <= 0 or not is_instance_valid(enemy):
		return
	if bool(enemy.get("_dead")):
		return
	if enemy.has_method("take_damage"):
		enemy.take_damage(dmg, element, false)
	EventBus.damage_dealt.emit(dmg, _enemy_pos(enemy), false)


func _enemy_pos(enemy) -> Vector2:
	if is_instance_valid(enemy) and enemy is Node2D:
		return (enemy as Node2D).global_position
	return Vector2.ZERO

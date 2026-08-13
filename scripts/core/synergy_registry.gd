extends Node
## 流派机制注册表（钩子总线）：各流派脚本把回调挂到固定触发点，
## 主代码在敌人状态/死亡/受击/施法/命中/移动时广播上下文。
## 钩子 kind：
##   enemy_status   {enemy, kind, stacks, delta}     敌人状态 tick（burn/poison 等）
##   enemy_died     {enemy, pos}                      敌人死亡
##   enemy_hit      {enemy, dmg, element, crit}       敌人受击
##   player_hit     {dmg, pos, taken, attacker}       玩家受击（taken=结算后伤害）
##   damage_dealt   {dmg, pos, crit}                  玩家造成伤害（含吸血结算前）
##   cast           {player, core, mods}              法术施放
##   projectile_hit {enemy, dmg, element, crit, pos}  弹幕命中
##   player_move    {player, velocity, delta}         玩家移动
## 回调必须防御性编写（任何异常只影响该流派，不崩游戏）。

var _hooks: Dictionary = {}  # kind -> Array[Callable]

func register(kind: String, cb: Callable) -> void:
	if not _hooks.has(kind):
		_hooks[kind] = []
	_hooks[kind].append(cb)

func trigger(kind: String, ctx: Dictionary) -> void:
	var list: Array = _hooks.get(kind, [])
	for cb in list:
		cb.call(ctx)

func load_synergy_scripts() -> void:
	## 启动时扫描 scripts/synergies/*.gd 并实例化注册（各流派机制自动生效）
	var dir := DirAccess.open("res://scripts/synergies")
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.ends_with(".gd") and not name.begins_with(".") and name != "synergy_base.gd":  ## ?????????C?
			var script: Script = load("res://scripts/synergies/" + name)
			if script != null:
				var inst: Node = script.new()
				add_child(inst)
				print("[SYNERGY] loaded: ", name)
		name = dir.get_next()
	dir.list_dir_end()

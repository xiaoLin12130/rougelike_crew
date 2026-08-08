# 数据表 Schema（模块契约，所有 Agent 必须遵守）

## items.json

```json
{
  "id": "attack_speed_potion",
  "name": "攻速药水",
  "rarity": "common | rare | legendary",
  "type": "item | trinket | memory",
  "slot": null,
  "curve": {
    "type": "linear | exp_proc | threshold | multiplicative",
    "base": 0.15, "k": 0.15, "p": null, "threshold": null, "step": null,
    "cap": null, "max_stacks": null
  },
  "description": "攻击速度 +15%（每层 +15%）",
  "icon": "res://assets/icons/sword.svg",
  "tags": ["attack_speed"]
}
```

## spells.json

```json
{
  "cores": [
    {"id": "fireball", "name": "火球", "element": "fire",
     "base_damage": 12, "cooldown": 1.2, "range": 360, "speed": 320,
     "icon": "res://assets/icons/fireball.svg"}
  ],
  "shells": [
    {"id": "rapid", "name": "连发", "mods": {"shots": 3, "cooldown_mult": 1.5, "damage_mult": 0.8}}
  ]
}
```

## enemies.json

```json
{
  "id": "slime",
  "name": "史莱姆",
  "hp": 45, "attack": 8, "speed": 55,
  "size": 1.0, "touch_damage": true,
  "xp": 8, "gold": 3,
  "elite": {"hp_mult": 4.0, "atk_mult": 1.5, "size_mult": 1.4},
  "affix_pool": ["flame", "lightning", "frost", "stone"]
}
```

## levels.json

```json
{
  "id": "level_1",
  "name": "风语草原",
  "theme": "grass",
  "waves": [
    {"time": 0, "spawn": {"slime": 3, "bat": 2}, "interval": 2.5, "duration": 20},
    {"time": 25, "spawn": {"slime": 4, "bat": 3}, "interval": 2.0, "duration": 25}
  ],
  "boss": "slime_king",
  "clear_condition": {"kill_all_waves": true, "boss_kill": true}
}
```

## drops.json

```json
{
  "kill_drops": [{"type": "gold", "prob": 0.80}, {"type": "item", "prob": 0.08},
                 {"type": "spell_part", "prob": 0.07}, {"type": "trinket", "prob": 0.05}],
  "pity_threshold": 8,
  "boss_drops": {"legendary": 1, "rare": 2, "gold_mult": 5}
}
```

## 模块间契约（EventBus 信号，全大写）

| 信号 | 负载 | 触发方 → 监听方 |
|---|---|---|
| `player_hit(dmg, pos)` | int, Vector2 | 敌人 → 玩家/特效/UI |
| `player_died()` | - | 玩家 → 流程 |
| `enemy_died(enemy_id, pos, xp, gold)` | String, Vector2, int, int | 敌人 → 掉落/经验/特效 |
| `damage_dealt(dmg, pos, is_crit)` | int, Vector2, bool | 战斗 → 伤害数字 |
| `item_picked(item_id, stacks)` | String, int | 掉落 → GameState/UI |
| `spell_arranged(grid)` | Array | 构筑 UI → 战斗 |
| `level_cleared(level_id)` | String | 关卡 → 流程 |
| `loop_choice(choice)` | String("boss"/"loop") | 抉择 UI → 流程 |
| `fx_explosion(pos, kind)` | Vector2, String | 战斗 → 特效系统 |
| `fx_hit_flash(node)` | Node | 战斗 → 特效系统 |
| `screen_shake(power)` | float | 战斗 → 相机 |
| `slow_mo(factor, duration)` | float, float | 战斗 → 时间管理 |

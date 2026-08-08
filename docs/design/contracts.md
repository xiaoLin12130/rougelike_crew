# 模块开发契约（v1，DEMO）

> 所有 Agent 只写自己名下的文件；只读：`data/`、`scripts/core/`、`docs/`、`assets/`。
> 通信只走 EventBus 信号（见 data-schema.md）。禁止直接改他人文件。

## 文件所有权表

| 模块 | 负责人 | 文件 |
|---|---|---|
| 核心 | 主 Agent | project.godot、scripts/core/*、data/*、scenes/main_menu.tscn、scenes/game/game_root.tscn、scenes/game/game_root.gd |
| 玩家与战斗 | Agent P | scripts/player/player.gd、scenes/game/player.tscn、scripts/combat/spell_caster.gd、scripts/combat/projectile.gd、scenes/game/projectile.tscn、scripts/combat/summon.gd |
| 敌人与关卡 | Agent E | scripts/enemies/enemy.gd、scenes/game/enemy.tscn、scripts/enemies/spawner.gd、scripts/enemies/boss.gd、scripts/enemies/level.gd、scenes/game/level.tscn |
| 特效与相机 | Agent F | scripts/fx/fx_manager.gd、scripts/fx/damage_number.gd、scripts/fx/camera_shake.gd、scenes/game/camera.tscn、scenes/fx/* |
| UI | Agent U | scripts/ui/game/hud.gd、scenes/ui/hud.tscn、scripts/ui/game/build_panel.gd、scenes/ui/build_panel.tscn、scripts/ui/game/levelup_overlay.gd、scenes/ui/levelup_overlay.tscn、scripts/ui/game/loop_choice.gd、scenes/ui/loop_choice.tscn、scripts/ui/game/game_over.gd、scenes/ui/game_over.tscn、scripts/ui/game/pause_menu.gd、scenes/ui/pause_menu.tscn |

## 场景结构（game_root.tscn，主 Agent 集成）

```
GameRoot (Node2D, game_root.gd)
├── Camera (Camera2D, scripts/fx/camera_shake.gd)   ← F 提供脚本
├── Level (instance level.tscn)                     ← E 提供
├── Player (instance player.tscn)                   ← P 提供
├── HUD (CanvasLayer, instance hud.tscn)            ← U 提供
├── BuildPanel (CanvasLayer, instance build_panel.tscn) ← U 提供
├── LevelUpOverlay (CanvasLayer)                    ← U 提供
├── LoopChoice (CanvasLayer)                        ← U 提供
├── GameOver (CanvasLayer)                          ← U 提供
└── PauseMenu (CanvasLayer)                         ← U 提供
```

## 关键调用约定

- 玩家：每帧读 `InputRouter.move_vector`；闪避用 `Input.is_action_just_pressed("dash")`；受击时 `EventBus.player_hit.emit(dmg, global_position)`，HP 由 GameState.run 管理；死亡 `EventBus.player_died.emit()`。
- 法术施放：`spell_caster.gd` 每帧按 `GameState.run.grid` 顺序检查冷却，就绪即生成 projectile；投射物命中敌人后：扣血、`EventBus.damage_dealt.emit(...)`、`EventBus.fx_explosion.emit(pos, element)`。
- 敌人：从 `GameState.tables["enemies"]` 读配置；死亡时 `EventBus.enemy_died.emit(id, pos, xp, gold)`（掉落/经验由 GameRoot 监听处理，敌人不直接改 GameState）。
- 关卡：spawner 按 `levels.json` 波次生成敌人；全部波次清完 + Boss 死 → `EventBus.level_cleared.emit(level_id)`；GameRoot 决定下一关/抉择。
- 特效：所有粒子/数字/震动/慢动作统一由 fx_manager 监听 EventBus 信号实现；模块内禁止各自 new 粒子。
- UI：HUD 每 0.2s 读 GameState.run 刷新；build_panel 显示 items/trinkets/grid，点击两个格子交换（`GameState.swap_grid(a,b)`）；levelup 用 `GameState.roll_item_choices(3)`；抉择/结算由 GameRoot 触发显示。

## 验收命令

```powershell
python tools/tests/test_curves.py
godot --headless --path . --import
godot --headless --path . -s res://scripts/tests/smoke_test.gd
```

> 每个 Agent 交付前必须保证自己名下的 .gd 文件语法正确（可用 `godot --headless --check-only --script <file>` 自检，4.7 支持 --check-only）。

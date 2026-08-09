# PROGRESS — 进度与负责人登记（2026-08-08 会话收尾快照）

> 下次会话请先读本文件 + docs/PLAYBOOK.md + work/status.json 续接。

## 已完成

| 日期 | 任务 | 状态 |
|---|---|---|
| 08-08 | 阶段0 需求定稿 v1.0（俯视角+五轨构筑+6流派+数值循环）+ 四款游戏分析 + Godot 踩坑手册 + RAG 系统（官方文档+数值书籍入库） | ✅ |
| 08-08 | Godot 4.7.1 工具链：编辑器/Web 导出模板/export_presets（for_desktop=false 纹理兼容）/中文字体（霞鹜文楷子集 0.4MB） | ✅ |
| 08-08 | 素材：免费包导入 239 文件 + 38 Game Icons + 37+8 程序化精灵 + 音效（CREDITS 落盘） | ✅ |
| 08-08 | 数据层：6 张 JSON 表 + 曲线公式 + test_curves.py 全绿（25 道具/6 核心/8 外壳/11 敌人/6 Boss/5 关） | ✅ |
| 08-08 | 核心架构：5 Autoload + EventBus 契约 + 模块解耦（微信移植预留） | ✅ |
| 08-08 | 玩法闭环：主菜单→5 关→抉择循环（Boss/继续刷）→最终 Boss 古神 | ✅ |
| 08-08 | **自动通关脚本 VICTORY**（旧配置 814s/2470 杀通关；后因难度调整需重验） | ✅（旧配置） |
| 08-08 | 修复轮：关卡初始化/暂停卡死/波次时间轴/切关清怪/Boss 继承签名/受击保护 0.6s/升级血量成长/治疗掉落/刷怪上限 32/墙碰撞层（玩家不可出屏） | ✅ |
| 08-08 | 存档系统：每 10s 自动存档 + 切关存档 + 返回主菜单保存 + 继续恢复 + 波次进度续接（level_elapsed） | ✅（headless 验证） |
| 08-08 | UI 重设计：UiTheme 像素主题、主菜单（星空+标题+按钮 z 顺序修复）、HUD（资源/波次/DPS/常驻构筑条文字化）、升级三选一卡片重构（PanelContainer+透明点击层）、Boss 大血条+头顶血条、获得提示飘字、卡片图标居中文字固定高度 | ✅ |
| 08-08 | 怪物多样性：新增 4 种怪（秘法巫师 cast/爆裂者 bomb/冲锋兽 charge/幽暗巫医 heal）+ 现有怪技能（分裂/俯冲/相位/狂暴/格挡/三连射）+ 防重叠 + 分裂防无限循环 + 波次清场 15s 兜底 | ✅（待平衡验证） |
| 08-08 | 测试体系：test_curves.py（数值）、smoke_test.gd（冒烟 16 场景）、test_boss.tscn（Boss 掉血/死亡）、auto_play.gd（自动通关）、web_e2e_test.py（浏览器控制台） | ✅ |

## 未完成 / 待验证（下次会话第一优先）

1. **自动通关平衡重验**：地图扩大+时间轴加长+新怪技能后，上一轮跑 DEFEAT at level4（远程海 21 imp+11 弓手）。已回调：imp/弓手攻击与射速下调、level4/5 远程怪数量减少、受击保护 0.5→0.6s。**待跑完整 autoplay 确认 VICTORY**（命令：`python tools/scripts/run_autoplay.py 30`，提权运行）。
2. **导出 v6 + 打开给用户**：HUD 物品栏文字化（名称+×N）+ 获得提示已改但未导出。命令：godot --export-release "Web" + Chrome http://127.0.0.1:8125/index.html
3. **git 提交推送**：本轮大量改动（地图/存档/血条/新怪/技能/UI）未提交。
4. 用户遗留反馈跟进："史莱姆王无敌"根因已定位为分裂小史莱姆卡场（已修：分裂产物 20s 自毁 + 清场 15s 兜底），需用户复测确认。
5. GitHub issues #1-#6 状态更新（M1-M3 已达成，M4/M5 未完成）。

## 下一步计划（优先级排序）

1. 跑完整 autoplay 验证平衡 → 若 DEFEAT 再回调数值（优先降 level4/5 远程密度）
2. 导出 v6 → 打开给用户复测（重点：物品栏展示、获得提示、Boss 血条、卡场、视角、存档继续）
3. git 提交 + 更新 issues
4. M4 流派成型（进化合成/成型检测/爽感档位）→ M5 Web 优化 + 微信移植评估

## 常用命令速查

```powershell
# 冒烟/导入/导出（需提权）
godot --headless --path . -s res://scripts/tests/smoke_test.gd
godot --headless --path . --export-release "Web" export/web/index.html
# 自动通关（提权）
python tools/scripts/run_autoplay.py 30
# 数值测试 / RAG 查询
python tools/tests/test_curves.py
python tools/rag/query.py "关键词" --src godot-docs
```

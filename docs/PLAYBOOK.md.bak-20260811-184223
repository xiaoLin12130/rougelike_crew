# PLAYBOOK — 项目踩坑与解法手册

> 所有 agent（Codex / 子 Agent）开工前必读。遇到环境、工具、权限、网络、引擎问题先查这里，解决后按文末模板追加新条目。

## 0. 高频重犯坑（先看这里）

1. **背景/装饰被地面覆盖不可见**（2026-08-09 重犯）：背景用世界空间 Sprite2D 贴在地图坐标，而地面瓦片铺满地图且层级更高 → 背景物理上不可见，相机跟随还露黑边。解法：背景用 **CanvasLayer（屏幕空间 layer=-100）**；远景要透出时地面瓦片半透明（modulate alpha<1）。
2. **新 PNG 未跑 --import**（2026-08-09 重犯）：手动加 assets/ 的 PNG 需要 Godot 生成 .import 才打包。解法：新增素材后必须 `godot --headless --path . --import` 再导出；用 pck 搜文件名验证。
3. **PowerShell 管道写中文变 ?**（2026-08-09 重犯 3 次）：heredoc 传 stdin 时中文按系统代码页转换。解法：含中文文件一律 apply_patch；脚本内中文路径用 \u 转义；**脚本写入数据文件后必须全量扫描 `??`（python 遍历 data/ 下 .json 计数）**。
4. **导出 pck 旧版疑云**：并行 Godot 进程锁 .godot 缓存；浏览器 Godot canvas 不自动重载（Ctrl+F5 无效）。解法：导出前清理残留 Godot；主菜单加构建版本指纹；新 URL 目录绕缓存。
5. **掉落保底(pity)强制掉道具**：掉落表只留金币但保底逻辑把 kind 强制改为 item。解法：保底奖励改金币，不触发构筑掉落。

## 1. 网络与代理（本机实测 2026-08-08）

| 问题 | 现象 | 原因 | 解决 |
|---|---|---|---|
| 环境变量坏代理 | curl/python 走 `https_proxy=http://127.0.0.1:9` 连接拒绝 | 系统残留坏代理变量 | python 用 `urllib.request.ProxyHandler({})` 绕过；curl 加 `--noproxy "*"` |
| GitHub API TLS 失败 | Invoke-RestMethod "基础连接已经关闭" | PS 受限语言模式/旧 TLS | 一律用 python（自带 OpenSSL）直连，实测 `api.github.com` 直连可用，也支持 `http://127.0.0.1:7890` 代理 |
| curl schannel 失败 | `SEC_E_NO_CREDENTIALS` | 沙箱下 curl 拿不到凭证 | 不用 curl 走 https，用 python requests/urllib |
| git push 直连不稳 | 443 超时 | 本机访问 github.com 不稳定 | `git -c http.proxy=http://127.0.0.1:7890 push` |
| 下载 GitHub releases | 大文件（Godot 84MB / docs 213MB / 模板 1.2GB） | — | python 分块下载直连成功；export templates 走代理保险 |

## 2. PowerShell 沙箱（constrained language mode）

| 问题 | 现象 | 解决 |
|---|---|---|
| Add-Type / System.Drawing 不可用 | `CannotDefineNewType` | 一律用 python（PIL 已装）做图像处理/尺寸读取 |
| 无法设置 SecurityProtocol | `PropertySetterNotSupportedInConstrainedLanguage` | 同 §1，走 python |
| 中文乱码 | PS 管道 GBK | 脚本纯 ASCII，或 `$env:PYTHONIOENCODING='utf-8'` |

## 3. git 与仓库

- `.git` 目录在沙箱只读：`git add/commit/push` 需 `require_escalated`（可申请 prefix `["git"]`）
- 仓库 `xiaoLin12130/rougelike_crew`（public，main）；issues 用 fine-grained PAT 走 `api.github.com`（python 直连可用）
- 禁止子 Agent 执行 git 操作；只允许主 Agent

## 4. 素材与版权

- `H:\job_prep\免费素材\`：Ninja Adventure（忍者角色，扁平 PNG 序列，帧尺寸待确认）、Sunny Land（完整平台跳跃包：环境/敌人/音效，public license）、Platformer Art Complete/Deluxe（Kenney 风格 tiles/角色）、Space Shooter Redux（激光/爆炸/流星/UI，kenney 风格 license）、Game Icons（CC BY 3.0，数千 SVG，**需署名**）
- 特效原则：**绝不用一张静态贴图冒充特效**；优先程序化（GPUParticles/CPUParticles、shader、tween）+ 素材包粒子帧
- 引用 Game Icons 需在 README/致谢中署名

## 5. 网络爬取（研究用）

| 目标 | 方法 |
|---|---|
| Fandom wiki（VS/RoR2） | 直连被墙/403 → 走代理 127.0.0.1:7890 + 浏览器 UA 头 + **MediaWiki API** `api.php?action=parse&page=...&prop=wikitext&format=json`（普通页面 403 但 API 可用） |
| Steam 商店信息 | `https://store.steampowered.com/api/appdetails?appids=<ID>&l=schinese` 与 `/api/storesearch/?term=...`（JSON，代理可通） |
| huijiwiki（魔法工艺中文 wiki） | 403，不可用 → 改用 Steam 官方描述 |
| 原始抓取缓存 | `.tools/research_cache/`（gitignored） |

## 6. 子 Agent（spawn_agent）注意

- 2026-08-08 实测：两个研究型子 Agent 运行 70 分钟无任何产出且不结束（疑似网络循环卡死）→ 主 Agent 亲自抓取资料完成研究。
- 教训：需要网络抓取的任务优先主 Agent 用已验证的 API 通道（见 §5）快速完成，或给子 Agent 更严格的任务边界与超时预期。

## 7. 导出模板安装

- `.tools/export_templates.tpz` 已下载（走代理），解压在 `.tools/export_templates_extracted/templates/`；
- 正式安装位置：`%APPDATA%\Godot\export_templates\4.7.1.stable\`（**写 AppData 需 require_escalated**）。

## 8. 新问题记录模板

## 5. 新问题记录模板

```markdown
## [YYYY-MM-DD] 问题一句话
- 现象：…
- 原因：…
- 解决：…
- 备注/复现：…
```

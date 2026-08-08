# rougelike_crew — 像素肉鸽小游戏

一款像素风 Roguelike 小游戏。Godot 4.7 开发，首发目标为 Web（HTML5）版本，后续改造为微信小游戏版本。

## 项目状态

- 阶段 0（需求分析）：进行中，见 `docs/requirements.md`
- 技术方案：Godot 4.7.1 + 免费像素素材（Ninja Adventure / Sunny Land / Space Shooter Redux / Game Icons）+ 程序化特效
- 知识库：`.tools/godot-docs`（官方文档）+ `tools/rag/`（本地检索），遇到问题先查库再问社区

## 目录结构

```
docs/              需求、设计、数值、进度、踩坑手册
work/              多 Agent 工作产物（status.json 等）
tools/             开发工具（RAG 检索、素材管线脚本）
assets/            游戏素材（从 H:\job_prep 精选导入）
scenes/            Godot 场景
scripts/           GDScript 源码
```

## 常用命令

```powershell
# RAG 检索（查 Godot 官方文档/项目知识库）
python tools/rag/query.py "tilemap pixel snap 2d"

# 重建检索索引（文档更新后执行）
python tools/rag/build_index.py
```

## 许可证说明

素材版权归原作者所有（见各素材包 license），本项目代码见仓库 LICENSE。

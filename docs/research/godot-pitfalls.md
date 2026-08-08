# Godot 4.x 开发踩坑手册（社区 + 官方文档核实版）

> 日期：2026-08-08　适用版本：Godot 4.7（4.3-4.7 通用）
> 验证方式：官方文档（.tools/godot-docs，可用 RAG 检索）+ 社区公认经验
> 本项目专属坑见 `docs/PLAYBOOK.md`

## 1. 2D 像素游戏设置

### 1.1 像素模糊（最经典）
- 现象：精灵放大后糊成一片。
- 原因：默认纹理过滤是 Linear。
- 解决：
  - 项目设置 `rendering/textures/canvas_textures/default_texture_filter = Nearest`；
  - 导入设置（Import dock）Texture → Filter = Nearest，关闭 Mipmaps；
  - 图集/Sheet 同理会生效。

### 1.2 像素抖动（移动时画面晃动）
- 现象：Camera2D 跟随角色时背景/瓦片肉眼可见抖动。
- 原因：相机平滑插值产生亚像素位置 + 纹理过滤。
- 解决：
  - 项目设置 `rendering/2d/snap/snap_2d_transforms_to_pixel = true`、`snap_2d_vertices_to_pixel = true`；
  - Camera2D `position_smoothing_enabled`（4.x 新 API，旧版是 `smoothing_enabled`）配合 `position_smoothing_speed` 调参；
  - 角色/瓦片坐标尽量取整（`round()`）。

### 1.3 精灵缝隙/白线
- 现象：瓦片地图相邻块之间出现细缝。
- 原因：浮点 UV 采样误差。
- 解决：TileSet 用 TexturePadding（图集留 1px 边距）；贴图尺寸必须与 tile 尺寸精确一致。

### 1.4 TileMap 已废弃 → TileMapLayer（4.3+）
- Godot 4.3 起推荐 **TileMapLayer 节点**（每个图层一个节点），4.7 新项目直接用 TileMapLayer。
- TileSet 配置要点：
  - Atlas Source 下逐 tile 设 Texture region；
  - 物理碰撞在 TileSet 的 Physics Layers 里画多边形（不是给节点加碰撞体）；
  - Terrains（自动地形）配置复杂，先用手动笔刷；
  - 导航网格在 TileSet 的 Navigation Layers 画。
- 坑：运行时用代码改瓦片（`set_cell`）时坐标是 TileMap 本地坐标，转全局要用 `map_to_local`，别手算。

## 2. Web（HTML5）导出

### 2.1 渲染器限制（最致命）
- **Web 只支持 Compatibility（GL Compatibility / WebGL 2.0）渲染器**；Forward+/Mobile 在 Web 不支持（官方文档明确）。
- 必须：项目设置 `rendering/renderer/rendering_method = gl_compatibility`。
- 后果：3D 体积光等高级效果不可用；2D 像素项目几乎无感，本项目完全够用。

### 2.2 线程与 SharedArrayBuffer
- `threads` 开启时 Web 需要 Cross-Origin-Isolation（COOP/COEP 响应头）才能用 SharedArrayBuffer；否则引擎直接报错/黑屏。
- **Godot 4.3+ 提供单线程导出**（nothreads 模板），无需特殊响应头，适合普通静态服务器。
- 建议：默认用 `web_nothreads_release`；需要多线程再上 `Cross-Origin-Opener-Policy: same-origin` + `Cross-Origin-Embedder-Policy: require-corp`。

### 2.3 不能直接双击 index.html（file://）
- 现象：白屏/加载失败。
- 原因：WASM/Worker 在 file:// 下受浏览器安全策略限制。
- 解决：本地起静态服务器（`python -m http.server 8080`）或 Godot 编辑器 Run in Browser。

### 2.4 音频自动播放策略
- 浏览器要求用户手势后才能播放音频 → 首次播放可能被拒。
- 解决：主菜单"开始游戏"按钮点击时解锁音频（播放一次空音效）。

### 2.5 输入差异
- 键盘：4.x 用 `Key` 枚举（`KEY_A` → `Key.A`）。
- 手柄：Web 需要 Gamepad API，Safari 兼容性差。
- 触屏：`InputEventScreenTouch/Drag` 需要自己做虚拟摇杆/按钮；Godot 4 无内置 UI 摇杆。
- 失去焦点浏览器会暂停输入，需处理焦点恢复。

### 2.6 体积与加载
- wasm+pck 通常 10-30MB，务必开 gzip/brotli（服务器端）；导出选项里可开纹理/PNG 压缩。
- 首次加载白屏：显示进度条，避免用户以为卡死。
- **C# 项目不能导出 Web（Godot 4，官方明确）→ 本项目必须 GDScript**。

### 2.7 浏览器控制台是救命稻草
- F12 查看 JS/WebGL 错误；引擎错误也在 console。

## 3. GDScript 与场景系统

### 3.1 @onready 时机
- `@onready var x = $Node` 在 `_ready()` 前赋值；在 `_init()` 里访问会炸（节点树未就绪）。
- 动态创建的节点要 `add_child()` 后才可 `get_node`。

### 3.2 资源（Resource）共享坑
- 场景/脚本中直接引用同一个 Resource（材质、Texture）时是**共享实例**，运行时修改影响所有使用处。
- 需要独立实例用 `.duplicate()`（深拷贝 `duplicate(true)`）。

### 3.3 Dictionary/Array 是引用类型
- 赋值、传参是引用；复制用 `.duplicate(true)`；遍历时不要改结构。

### 3.4 await/信号
- `await` 一个永不触发的信号 = 永久挂起（如 await 已停止的 Timer.timeout）。
- `connect`/`disconnect` 成对，重复连接用 `is_connected` 检查；传参用 `callable.bind()`。

### 3.5 静态类型与性能
- 热循环（每帧/大量实体）里用静态类型；`get_node` 缓存到 @onready，别在 _process 里反复 `$`。

### 3.6 _process 与 _physics_process
- 移动/碰撞逻辑放 `_physics_process`（固定步长），视觉/UI 放 `_process`。
- 慢动作（time_scale）会影响物理，注意设计。

## 4. 性能与渲染

### 4.1 2D 批处理（Batching）
- Godot 4 Canvas 自动合批，但每帧改 transform/材质属性会破坏批处理。
- 大量同种精灵：`MultiMesh2D` 或 `GPUParticles2D`，别用几百个 Sprite2D 节点。

### 4.2 粒子选择
- `GPUParticles2D`：GPU 算，量大高效；Web/低端机受限。
- `CPUParticles2D`：CPU 算，兼容性最好，几百个没问题；本项目特效主打 CPUParticles + 少量 GPUParticles。
- 爆炸类一次性粒子要 `one_shot=true`，结束 `queue_free()` 防泄漏。

### 4.3 物理层
- 项目设置里定义 Layer（玩家/敌人/地形/子弹），碰撞用 mask 精确过滤；
- 高频子弹用 Area2D 检测 + 手动移动，物理体数量控制在几百以内。

## 5. 微信小游戏移植（结论 + 已知坑）

### 5.1 可行性结论
- **可行但有工程代价**。Godot 官方不支持微信小游戏，社区方案基于 Web 导出（WASM）+ 微信适配层（小游戏本质是 Canvas + WASM 运行时），把 Godot web 平台 JS 桥接到 wx API。
- 已知社区项目（GitHub 搜 "godot wechat minigame"）：3.x 有较成熟移植；4.x 为实验性 fork，需自测。

### 5.2 硬约束

| 约束 | 说明 | 对策 |
|---|---|---|
| 包体 | 主包 ≤4MB，总包 ≤20MB | wasm 压缩 + pck 分包 + 素材压缩，特效全程序化 |
| SharedArrayBuffer | 微信基础库新版本 Android 支持；iOS 受限 | 导出**单线程**（nothreads）版本最稳 |
| 音频 | 需 wx 音频上下文适配 | 抽象 AudioBus 层 |
| 输入 | 无键盘/鼠标 | 本项目走虚拟摇杆 + 按钮方案 |
| 存档 | user:// 在 Web 是 IndexedDB，微信容器没有 | 抽象 SaveManager：本地文件 ↔ wx.setStorage |
| 渲染 | WebGL2 取决于 iOS 版本 | Compatibility 渲染器 + 真机测试 |

### 5.3 架构预留（现在就做）

1. 输入层：`InputRouter`（键盘/摇杆统一成输入向量）；
2. 存档层：`SaveStore` 接口（File / Web / Wx 三个实现）；
3. 音频层：`SfxBus`（封装 AudioStreamPlayer，换端只改一处）；
4. 分包意识：特效/音效用小文件，场景按关卡分包。

## 6. 命令行自动化（CI）

```powershell
# 首次导入（生成 .godot 缓存）
godot --headless --path . --import
# 导出 Web（需 export_presets.cfg + 已安装模板）
godot --headless --path . --export-release "Web" export/index.html
# 跑场景测试
godot --headless --path . --quit-after 120 res://scenes/test_main.tscn
```

### 6.1 常见坑

- `--export` 前必须 `--import` 一次（否则素材未导入报错）；
- 模板安装位置：`%APPDATA%\Godot\export_templates\<版本>.stable\`；CLI 与 GUI 共用；
- `.godot/` 目录是本地缓存，**加入 .gitignore**；
- `export_presets.cfg` 要提交（含 Web 导出配置），不要提交密钥类配置。

## 7. 其他高频坑

- 中文字体：默认字体无 CJK 字形，UI 中文必现豆腐块 → 项目带开源中文字体或 SystemFont 兜底；
- `TextureRect` 拉伸：`stretch_mode` + `expand_mode` 组合要一起设；
- 场景切换：`get_tree().change_scene_to_file()`（4.x 替代 change_scene）；
- 单例 Autoload：project.godot 注册，跨场景共享状态（本项目：GameState/数值/存档）；
- 资源路径引用：`preload()` 编译期 vs `load()` 运行时，热循环别用 load。

## 8. 官方文档检索入口

本仓库 RAG 已收录官方文档全文，任何 API 疑问先查：

```powershell
python tools/rag/query.py "tilemaplayer physics 2d" --src godot-docs
python tools/rag/query.py "export web compatibility" --src godot-docs/tutorials/export
```

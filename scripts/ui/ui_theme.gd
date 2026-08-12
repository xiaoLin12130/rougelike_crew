class_name UiTheme
## 像素 UI 主题工具：统一颜色/字体/组件样式（所有 UI 脚本调用）

# 2026-08-10：Web 上全量字体(24.7MB)加载不稳定导致主菜单码点，
# 改回子集字体(3.3MB，覆盖游戏常用字形)；若个别字缺形再扩子集
const FONT_CN := "res://assets/fonts/LXGWWenKai_subset.ttf"
const FONT_NUM := "res://assets/fonts/kenvector_future.ttf"

const BG := Color("#14111f")
const PANEL := Color("#201a30")
const PANEL_LIGHT := Color("#2a2340")
const BORDER := Color("#8b5cf6")
const BORDER_DIM := Color("#4c3a7a")
## Brotato 灰蓝面板系（2026-08-12 适配，见 docs/design/土豆兄弟UI适配方案.md §4.1）：
## 面板/卡片/槽位分层灰蓝 + 材料棕金 + 玩家血条红 + Boss 血条暗红 + 护盾灰蓝。
## 与既有紫金主题并存：紫色保留作稀有度/流派强调，灰蓝作为面板主调。
const PANEL_BLUE := Color("#1c2230")   # 面板底（替代纯紫面板底的 Brotato 灰蓝）
const PANEL_CARD := Color("#242c3c")   # 商品卡/槽位卡底
const PANEL_SLOT := Color("#171c28")   # 槽位底（武器/法术格）
const BORDER_GRAY := Color("#3a4557")  # 面板主边框（灰蓝）
const BORDER_LIGHT := Color("#5c6b82") # 交互态/hover 边框
const MAT := Color("#c9a24b")          # 材料图标色（Brotato 材料棕金）
const HP_RED := Color("#d24b4b")       # 玩家血条填充
const BOSS_RED := Color("#c0392b")     # Boss 条填充（与玩家血区分）
const SHIELD := Color(0.50, 0.61, 0.77, 0.55)  # 护盾叠层灰蓝（#7f9cc4 半透明）
const GOLD := Color("#f5b83d")
const WHITE := Color("#f2eef8")
const RED := Color("#e05252")
const GREEN := Color("#6fce6f")
const RARITY := {
	"common": Color("#b8b8c8"),
	"uncommon": Color("#6fce6f"),
	"rare": Color("#4a9eff"),
	"epic": Color("#b07cff"),
	"legendary": Color("#ffa726"),
}
const ELEMENT := {
	"fire": Color("#ff7b3d"),
	"ice": Color("#7fd4ff"),
	"lightning": Color("#ffe95c"),
	"poison": Color("#7ed957"),
	"blade": Color("#c8d0e8"),
	"summon": Color("#c084fc"),
}

static var _font_cn: Font
static var _font_num: Font
static var _fallback_set := false

static func font_cn() -> Font:
	if _font_cn == null:
		_font_cn = load(FONT_CN)
		print("[FONT] cn loaded=", _font_cn != null, " path=", FONT_CN)
	if not _fallback_set and _font_cn != null:
		# 全局 fallback 字体：tooltip/未显式设字体的控件默认无中文字形（会显示码点），
		# 统一回退到中文字体，解决悬停提示等位置的码点
		_fallback_set = true
		ThemeDB.fallback_font = _font_cn
		ThemeDB.fallback_font_size = 14
	return _font_cn

static func font_num() -> Font:
	if _font_num == null:
		_font_num = load(FONT_NUM)
	return _font_num

static func apply_font(control: Control, size: int) -> void:
	## 给直接 Button.new()/Label.new() 创建的控件显式设置中文字体：
	## 显式默认字体的控件不受 ThemeDB.fallback_font 影响，中文会显示码点，
	## 必须显式 add_theme_font_override（供 UiTheme.button() 之外的直建控件复用）
	control.add_theme_font_override("font", font_cn())
	control.add_theme_font_size_override("font_size", size)

static func style(bg: Color, border: Color = BORDER, width: int = 2, corner: int = 4) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(corner)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb

static func style_compact(bg: Color, border: Color = BORDER, width: int = 1, corner: int = 3, pad: int = 2) -> StyleBoxFlat:
	## 紧凑面板样式：小内边距，用于常驻 HUD 槽位/半透明条（不挤占战斗视野）
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(corner)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad
	sb.content_margin_bottom = pad
	return sb

static func style_card(bg: Color = PANEL_CARD, border: Color = BORDER_GRAY, width: int = 2, corner: int = 4) -> StyleBoxFlat:
	## 商品卡/槽位卡样式（Brotato 统一栅格卡）：小内边距 6，按稀有度传边框色
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(corner)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb

static func style_slot(bg: Color = PANEL_SLOT, border: Color = BORDER_GRAY, width: int = 1, corner: int = 3) -> StyleBoxFlat:
	## 槽位样式（武器/法术/装备格）：零内边距，图标直接居中占满
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(corner)
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	return sb

static func label(text: String, size: int = 12, color: Color = WHITE, num: bool = false) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font_num() if num else font_cn())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", maxi(size / 6, 1))
	l.text = text
	return l

static func button(text: String, min_size: Vector2 = Vector2(150, 36)) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE  # 防误触（Enter/Space 不会误点按钮）
	b.add_theme_font_override("font", font_cn())
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", GOLD)
	b.add_theme_color_override("font_hover_color", Color("#ffe9a8"))
	b.add_theme_color_override("font_pressed_color", WHITE)
	b.add_theme_stylebox_override("normal", style(PANEL, BORDER_DIM, 2, 4))
	b.add_theme_stylebox_override("hover", style(PANEL_LIGHT, BORDER, 2, 4))
	b.add_theme_stylebox_override("pressed", style(Color("#191527"), GOLD, 2, 4))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.custom_minimum_size = min_size
	return b

static func button_gold(text: String, min_size: Vector2 = Vector2(296, 48)) -> Button:
	## 金色大按钮（商店"开始下一波"）：gold 底 + 深棕字 + hover 提亮（Brotato 货币语义）
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font_cn())
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", Color("#3d2a00"))
	b.add_theme_color_override("font_hover_color", Color("#2a1c00"))
	b.add_theme_color_override("font_pressed_color", Color("#1f1500"))
	b.add_theme_stylebox_override("normal", style(GOLD, Color("#8a6a1e"), 2, 6))
	b.add_theme_stylebox_override("hover", style(Color("#ffc95c"), Color("#a87f24"), 3, 6))
	b.add_theme_stylebox_override("pressed", style(Color("#d9a02e"), Color("#5e470f"), 2, 6))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.custom_minimum_size = min_size
	return b

static func icon(icon_path: String, size: Vector2 = Vector2(16, 16)) -> TextureRect:
	## 统一图标节点：等比居中缩放，鼠标穿透
	var t := TextureRect.new()
	t.texture = icon_texture(icon_path)
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.custom_minimum_size = size
	t.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

static func badge(text: String, size: int = 9, color: Color = GOLD) -> Label:
	## ×N 堆叠角标：金色像素数字 + 重黑描边
	var l := label(text, size, color, true)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	l.add_theme_constant_override("outline_size", maxi(size / 3, 2))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static func panel_style() -> StyleBoxFlat:
	return style(PANEL, BORDER, 2, 6)

static func icon_texture(icon_path: String) -> Texture2D:
	if icon_path.is_empty() or not ResourceLoader.exists(icon_path):
		return null
	return load(icon_path)

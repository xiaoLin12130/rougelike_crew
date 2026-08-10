class_name UiTheme
## 像素 UI 主题工具：统一颜色/字体/组件样式（所有 UI 脚本调用）

const FONT_CN := "res://assets/fonts/LXGWWenKai_full.ttf"
const FONT_NUM := "res://assets/fonts/kenvector_future.ttf"

const BG := Color("#14111f")
const PANEL := Color("#201a30")
const PANEL_LIGHT := Color("#2a2340")
const BORDER := Color("#8b5cf6")
const BORDER_DIM := Color("#4c3a7a")
const GOLD := Color("#f5b83d")
const WHITE := Color("#f2eef8")
const RED := Color("#e05252")
const GREEN := Color("#6fce6f")
const RARITY := {
	"common": Color("#b8b8c8"),
	"rare": Color("#4a9eff"),
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

static func panel_style() -> StyleBoxFlat:
	return style(PANEL, BORDER, 2, 6)

static func icon_texture(icon_path: String) -> Texture2D:
	if icon_path.is_empty() or not ResourceLoader.exists(icon_path):
		return null
	return load(icon_path)

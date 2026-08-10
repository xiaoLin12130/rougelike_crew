extends SceneTree
## 临时探测：Godot 4.7 是否支持 Engine.print_error_messages / get_error_messages

func _init() -> void:
	Engine.print_error_messages = true
	push_error("PROBE_MARKER")
	var m: String = Engine.get_error_messages()
	print("CAPTURED_MESSAGES=[", m, "]")
	quit(0)

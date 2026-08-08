extends Node
## 音效总线：封装 AudioStreamPlayer；换端（微信）只改此文件

var _players: Array[AudioStreamPlayer] = []

func play(sfx_path: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not ResourceLoader.exists(sfx_path):
		return
	var stream: AudioStream = load(sfx_path)
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()

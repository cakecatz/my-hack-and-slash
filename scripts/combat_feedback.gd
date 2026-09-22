extends Node
## Original synthesized SFX, bounded voices, and presentation-only combat feedback.
const SETTINGS_PATH := "user://feedback.cfg"
const RATE := 22050
const VOICES := 8
var volume := 0.6
var shake_enabled := true
var hitstop_enabled := true
var flash_enabled := true
var settings_writable := true
var relic_time := 0.0
var clock := 0.0
var stop_left := 0.0
var shake_left := 0.0
var shake_strength := 0.0
var offset := Vector2.ZERO
var last_heavy := -10.0
var cooldowns: Dictionary = {}
var pending: Dictionary = {}
var streams: Dictionary = {}
var voices: Array[AudioStreamPlayer] = []
var rings: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.seed = 91827
	for kind in ["cleave", "nova", "lance", "hit", "kill", "heavy", "hurt", "burst", "loot", "relic"]:
		streams[kind] = synthesize(kind)
	for i in range(VOICES):
		var voice := AudioStreamPlayer.new()
		add_child(voice)
		voices.append(voice)

func synthesize(kind: String) -> AudioStreamWAV:
	var duration := 0.16
	var frequency := 180.0
	match kind:
		"cleave": frequency = 130
		"nova": frequency = 290; duration = 0.24
		"lance": frequency = 640
		"hit": frequency = 95; duration = 0.07
		"kill": frequency = 65; duration = 0.18
		"heavy": frequency = 48; duration = 0.36
		"hurt": frequency = 80; duration = 0.22
		"burst": frequency = 58; duration = 0.42
		"loot": frequency = 880; duration = 0.15
		"relic": frequency = 523.25; duration = 0.85
	var data := PackedByteArray()
	var count := int(RATE * duration)
	data.resize(count * 2)
	var phase := 0.0
	for i in range(count):
		var t := float(i) / RATE
		var progress := t / duration
		var envelope := minf(t / 0.006, 1.0) * pow(1.0 - progress, 2)
		phase += TAU * frequency * (1.0 if kind in ["loot", "relic"] else 1.0 - progress * 0.65) / RATE
		var sample := sin(phase) * 0.65 + rng.randf_range(-1, 1) * 0.35
		if kind in ["loot", "relic"]:
			sample = (sin(phase) + sin(phase * 1.25) + sin(phase * 1.5)) / 3.0
		data.encode_s16(i * 2, int(sample * envelope * 10000))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	return stream

func play(kind: String) -> bool:
	if kind == "relic":
		relic_time = 6.0
	if volume <= 0 or not streams.has(kind) or clock < float(cooldowns.get(kind, -1)):
		return false
	var important := kind in ["relic", "hurt", "heavy", "burst"]
	# Two reserved voices keep loot and danger audible through dense crowds.
	for i in range(6 if important else 0, VOICES if important else 6):
		if not voices[i].playing and not pending.has(i):
			pending[i] = kind
			cooldowns[kind] = clock + (0.12 if kind in ["hit", "kill"] else 0.08)
			return true
	# Relic rewards take priority over impact tails.
	if kind == "relic":
		pending[7] = kind
		cooldowns[kind] = clock + 0.5
		return true
	return false

func _process(_delta: float) -> void:
	# Flush once per frame: several kills can request the same priority voice.
	for index in pending:
		voices[index].stream = streams[pending[index]]
		voices[index].volume_db = linear_to_db(volume * 0.35)
		voices[index].play()
	pending.clear()

func heavy(pos: Vector2, color: Color, strength: float = 3.0) -> void:
	if clock - last_heavy < 0.16:
		return
	last_heavy = clock
	if hitstop_enabled:
		stop_left = 0.045
	if shake_enabled:
		shake_left = 0.18
		shake_strength = strength
	if rings.size() < 12:
		rings.append({"pos": pos, "color": color, "life": 0.25})

func advance(delta: float) -> float:
	clock += delta
	relic_time = maxf(0, relic_time - delta)
	var frozen := minf(stop_left, delta) if hitstop_enabled else 0.0
	stop_left = maxf(0, stop_left - delta) if hitstop_enabled else 0.0
	shake_left = maxf(0, shake_left - delta) if shake_enabled else 0.0
	offset = Vector2(sin(clock * 173), cos(clock * 137)) * shake_strength * shake_left / 0.18
	for i in range(rings.size() - 1, -1, -1):
		rings[i].life -= delta
		if rings[i].life <= 0:
			rings.remove_at(i)
	return delta - frozen

func reset() -> void:
	pending.clear()
	relic_time = 0
	stop_left = 0
	shake_left = 0
	offset = Vector2.ZERO
	rings.clear()
	last_heavy = -10
	cooldowns.clear()
	for voice in voices:
		voice.stop()
		voice.stream = null

func _exit_tree() -> void:
	reset()

func set_volume(value: float) -> void:
	volume = clampf(value, 0, 1)
	if volume == 0:
		pending.clear()
	for voice in voices:
		voice.volume_db = linear_to_db(maxf(volume * 0.35, 0.00001))
		if volume == 0:
			voice.stop()

func load_settings(path: String = SETTINGS_PATH) -> void:
	if not FileAccess.file_exists(path):
		return
	var config := ConfigFile.new()
	if config.load(path) != OK:
		settings_writable = false
		return
	var saved_volume: Variant = config.get_value("feedback", "volume", 0.6)
	if not (saved_volume is float or saved_volume is int) or not is_finite(float(saved_volume)):
		settings_writable = false
		return
	for key in ["shake_enabled", "hitstop_enabled", "flash_enabled"]:
		if not config.get_value("feedback", key, true) is bool:
			settings_writable = false
			return
	set_volume(float(saved_volume))
	for key in ["shake_enabled", "hitstop_enabled", "flash_enabled"]:
		set(key, config.get_value("feedback", key, true))

func save_settings(path: String = SETTINGS_PATH) -> Error:
	if not settings_writable:
		return ERR_FILE_CORRUPT
	var config := ConfigFile.new()
	for key in ["volume", "shake_enabled", "hitstop_enabled", "flash_enabled"]:
		config.set_value("feedback", key, get(key))
	var error := config.save(path + ".tmp")
	if error != OK:
		return error
	return DirAccess.rename_absolute(path + ".tmp", path)

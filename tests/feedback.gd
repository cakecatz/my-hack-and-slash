extends SceneTree
var failed := false
func _initialize() -> void:
	call_deferred("run")
func check(condition: bool, title: String) -> void:
	if not condition:
		failed = true
		push_error("FAIL: " + title)
func key(scene: Node, code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	scene._unhandled_input(event)
func run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	scene.save_enabled = false
	root.add_child(scene)
	scene.set_process(false)
	var f: Node = scene.feedback
	check(f.streams.size() == 10 and f.voices.size() == 8, "All sounds synthesized with bounded voice pool")
	for stream in f.streams.values():
		check(stream.get_length() > 0.05 and stream.get_length() < 1, "Short valid PCM stream")
		var peak := 0
		for i in range(0, stream.data.size(), 2):
			peak = maxi(peak, absi(stream.data.decode_s16(i)))
		check(peak > 1000 and peak <= 10000, "Non-silent PCM with mix headroom")
	check(f.play("hit") and not f.play("hit"), "Crowd impacts are rate limited")
	f._process(0)
	check(f.voices[0].playing, "Queued sound starts actual audio playback")
	await create_timer(0.12).timeout
	f.reset()
	for sound in ["cleave", "nova", "lance", "hit", "kill", "loot"]:
		check(f.play(sound), "Normal voices can be reserved")
	check(f.pending.size() == 6 and f.play("hurt") and f.play("heavy") and f.play("relic") and f.pending.size() == 8 and f.pending[7] == "relic", "Reward priority and eight-voice cap survive full crowd mix")
	f.set_volume(0)
	check(not f.play("heavy"), "Muted sounds do not spawn voices")
	f.play("relic")
	check(f.relic_time == 6, "Relic visual survives muted audio")
	for voice in f.voices:
		check(not voice.playing, "Mute stops existing voices")
	f.heavy(Vector2.ZERO, Color.WHITE)
	check(f.stop_left == 0.045 and f.advance(0.02) == 0, "Heavy hit briefly freezes simulation")
	f.heavy(Vector2.ZERO, Color.WHITE)
	check(is_equal_approx(f.stop_left, 0.025), "Crowd kills do not stack stop duration")
	check(is_equal_approx(f.advance(0.1), 0.075), "Remaining frame time preserved after stop")
	f.hitstop_enabled = false
	f.shake_enabled = false
	f.advance(0.2)
	f.heavy(Vector2.ZERO, Color.WHITE)
	check(f.advance(0.02) == 0.02 and f.offset == Vector2.ZERO, "Motion options disable pause and shake")
	scene.paused = true
	key(scene, KEY_F10)
	check(scene.panel == "settings" and not scene.paused, "Settings accessible from pause")
	key(scene, KEY_I)
	check(scene.panel == "settings", "Gameplay shortcuts cannot replace settings")
	key(scene, KEY_ESCAPE)
	check(scene.paused and scene.panel.is_empty(), "Closing restores pause state")
	scene.paused = false
	scene.panel = "build"
	key(scene, KEY_F10)
	key(scene, KEY_F10)
	check(scene.panel == "build" and scene.attack_blocked, "Return restores previous panel without held attack")
	scene.panel = ""
	scene.enter_map(0)
	key(scene, KEY_F10)
	var location: Vector2 = scene.player
	var enemy_pos: Vector2 = scene.enemies[0].pos
	scene._process(0.5)
	check(scene.player == location and scene.enemies[0].pos == enemy_pos, "Settings suspend combat")
	key(scene, KEY_ESCAPE)
	f.reset()
	scene.enemies.clear()
	scene.attack()
	check(f.stop_left == 0, "Empty normal swing causes no stop")
	scene.burst(scene.player, Color.WHITE, 1000)
	check(scene.particles.size() <= 320, "Particle budget bounded")
	f.hitstop_enabled = true
	f.shake_enabled = true
	scene.heat = 100
	scene.ember_burst()
	check(f.stop_left > 0, "Burst has heavy feedback")
	scene.return_to_hub()
	check(f.stop_left == 0 and f.offset == Vector2.ZERO and f.rings.is_empty(), "Travel clears transient feedback")
	var path := "/tmp/ember-feedback-test.cfg"
	f.set_volume(0.4)
	f.flash_enabled = false
	check(f.save_settings(path) == OK, "Preferences save independently")
	f.set_volume(1)
	f.flash_enabled = true
	f.load_settings(path)
	check(is_equal_approx(f.volume, 0.4) and not f.flash_enabled, "Preferences round trip")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("[feedback]\nvolume=\"invalid\"\n")
	file.close()
	f.load_settings(path)
	check(not f.settings_writable and f.save_settings(path) == ERR_FILE_CORRUPT, "Malformed preferences preserved")
	DirAccess.remove_absolute(path)
	f.reset()
	scene.queue_free()
	await create_timer(0.1).timeout
	if not failed:
		print("PASS: audio data, limits, mute, impact timing, settings UI, persistence and cleanup")
	quit(1 if failed else 0)

extends Node2D

const Mods = preload("res://scripts/item_mods.gd")
const Shrine = preload("res://scripts/expedition_shrine.gd")
const Layout = preload("res://scripts/expedition_layout.gd")
const Feedback = preload("res://scripts/combat_feedback.gd")
const Profile = preload("res://scripts/profile.gd")
const Skills = preload("res://scripts/skill_catalog.gd")
const BossFight = preload("res://scripts/boss_fight.gd")
const Effects = preload("res://scripts/item_effects.gd")
const ExpeditionEvent = preload("res://scripts/expedition_event.gd")
const VIEW := Rect2(24, 108, 1104, 540)
const WORLD := Rect2(0, 0, 2400, 1500)
const HUB_BOUNDS := Rect2(40, 40, 1024, 460)
const HUB_SPAWN := Vector2(552, 390)
const STASH_POS := Vector2(285, 230)
const GATE_POS := Vector2(830, 230)
const GRID_PAGE_SIZE := 24
const CLOSE_RECT := Rect2(982, 150, 40, 32)
const MINT := Color("70efd0")
const GOLD := Color("ffc478")
const RED := Color("f27386")
const PALE := Color("e0e9f4")
const MUTED := Color("8597ae")
const MAPS := [
	{"name": "ASHEN OUTSKIRTS", "boss": "Hollow Warden", "color": Color("182d2b"), "packs": 4},
	{"name": "BURIED SANCTUM", "boss": "Crypt Sentinel", "color": Color("252437"), "packs": 5},
	{"name": "CINDER CITADEL", "boss": "Cinder Tyrant", "color": Color("332423"), "packs": 6}
]
const CONTRACTS := ["CALM / STANDARD", "FRENZY / +35% SPEED", "DREAD / +40% LIFE & +20% DAMAGE"]
const JOURNEYS := [
	"The Fading Trail", "Ashbound Patrol", "The First Seal",
	"Voices Below", "The Silent Procession", "The Second Seal",
	"Road of Cinders", "The Broken Crown", "The Last Flame"
]
var feedback = Feedback.new()
var settings_previous_panel := ""
var settings_previous_paused := false
var settings_message := ""
var selected_depth := 0
var mission := 0
var abyss := false
var run_depth := 0
var contract := 0
var seal_required := 0 # Remaining defenders of the two main-route seals.
var seal_guards: Array[int] = [0, 0]
var layout = Layout.new()
var heat := 0.0
var cleave_chain := 0
var wave_flash := 0.0
var pull_flash := 0.0
var hazards: Array[Dictionary] = []
var boss_stones: Array[Dictionary] = []
var next_boss_id := 0
var celebration := ""
var trial = ExpeditionEvent.new()
var shrine = Shrine.new()
var scrapped := 0
var profile = Profile.new()
var save_enabled := true
var hub := true
var map_index := 0
var map_cleared := false
var player := HUB_SPAWN
var facing := Vector2.RIGHT
var camera := Vector2.ZERO
var hp := 100.0
var max_hp := 100.0
var damage := 18.0
var armor := 1.0
var attack_interval := 0.4
var attack_cooldown := 0.0
var slash := 0.0
var slash_angle := 0.0
var dash_time := 0.0
var dash_cooldown := 0.0
var dash_direction := Vector2.RIGHT
var invincible := 0.0
var return_time := 0.0
var potions := 3
var kills := 0
var found := 0
var paused := false
var ended := false
var page := 0
var stash_page := 0
# Empty, inventory, stash, or gate. Open panels suspend world simulation.
var panel := ""
var build_tab := 0
var craft_slot := "weapon"
var craft_index := 0
var craft_id := "might"
var craft_tier := 3
var craft_pending: Dictionary = {}
var mastery_message := ""
var mastery_time := 0.0
var attack_blocked := false
var town_clock := 0.0
var message := "The last flame is fading. B: choose your build. Walk to the gate and press E to begin."
var enemies: Array[Dictionary] = []
var drops: Array[Dictionary] = []
var particles: Array[Dictionary] = []
var notices: Array[Dictionary] = []
var font: Font = ThemeDB.fallback_font

func _ready() -> void:
	add_child(feedback)
	if save_enabled:
		feedback.load_settings()
	if save_enabled:
		if FileAccess.file_exists(Profile.SAVE_PATH) and not profile.load_from():
			# Preserve unreadable saves rather than overwriting them automatically.
			save_enabled = false
			message = "Save could not be loaded. Autosave disabled to preserve it."
	refresh_stats()
	hp = max_hp
	var bindings := {"left": [KEY_A, KEY_LEFT], "right": [KEY_D, KEY_RIGHT], "up": [KEY_W, KEY_UP], "down": [KEY_S, KEY_DOWN], "attack": [KEY_SPACE], "dash": [KEY_SHIFT]}
	for action in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in bindings[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			if not InputMap.action_has_event(action, event):
				InputMap.action_add_event(action, event)
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	if not InputMap.action_has_event("attack", mouse):
		InputMap.action_add_event("attack", mouse)

func persist() -> void:
	if save_enabled:
		profile.save_to()

func refresh_stats() -> void:
	var stats: Dictionary = profile.stats()
	max_hp = stats.health
	damage = stats.attack
	armor = stats.armor
	attack_interval = profile.combat_stats().interval

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if not celebration.is_empty():
			celebration = ""
			attack_blocked = true
			return
		if ended:
			if event.keycode == KEY_R:
				return_to_hub(true)
			return
		if event.keycode == KEY_ESCAPE:
			if not panel.is_empty():
				close_panel()
			else:
				paused = not paused
			return
		if event.keycode == KEY_F10:
			toggle_settings()
			return
		if panel == "settings":
			return
		if paused:
			return
		if event.keycode == KEY_L:
			cycle_loot_mode()
			return
		if event.keycode == KEY_F and panel in ["inventory", "stash"]:
			toggle_favorite(get_global_mouse_position())
			return
		if event.keycode == KEY_B and hub:
			if panel == "build":
				close_panel()
			else:
				panel = "build"
			return
		if event.keycode == KEY_I:
			craft_pending.clear()
			if panel == "inventory" or panel == "stash":
				close_panel()
			else:
				panel = "inventory"
				return_time = 0
			return
		if not panel.is_empty():
			if event.keycode == KEY_E:
				close_panel()
			elif panel == "shrine" and event.keycode >= KEY_1 and event.keycode <= KEY_3:
				choose_shrine(event.keycode - KEY_1)
			elif panel == "trial" and event.keycode >= KEY_1 and event.keycode <= KEY_3:
				start_trial(event.keycode - KEY_1)
			elif panel == "gate" and event.keycode == KEY_4:
				enter_abyss()
			elif panel == "gate" and event.keycode >= KEY_1 and event.keycode <= KEY_3:
				travel_from_gate(event.keycode - KEY_1)
			return
		if hub:
			if event.keycode == KEY_E:
				interact_hub()
			return
		if event.keycode == KEY_E:
			interact_field()
		elif event.keycode == KEY_T:
			return_time = 2.0
			message = "Opening town portal... Stand still for 2 seconds."
		elif event.keycode == KEY_F:
			ember_burst()
		elif event.keycode == KEY_Q:
			use_potion()
	if event is InputEventMouseButton and event.pressed and not paused and not ended and celebration.is_empty():
		panel_mouse(event.position, event.button_index, event.shift_pressed)

func close_panel() -> void:
	if panel == "settings":
		panel = settings_previous_panel
		paused = settings_previous_paused
		attack_blocked = true
		return
	craft_pending.clear()
	panel = ""
	attack_blocked = true

func toggle_settings() -> void:
	if panel == "settings":
		close_panel()
		return
	settings_previous_panel = panel
	settings_previous_paused = paused
	paused = false
	panel = "settings"
	return_time = 0
	feedback.reset()

func settings_rect(index: int) -> Rect2:
	return Rect2(640, 240 + index * 68, 310, 42)

func settings_click(mouse: Vector2) -> void:
	for i in range(4):
		if not settings_rect(i).has_point(mouse):
			continue
		match i:
			0:
				feedback.set_volume(0.0 if feedback.volume >= 0.99 else snappedf(feedback.volume + 0.2, 0.2))
			1: feedback.shake_enabled = not feedback.shake_enabled
			2: feedback.hitstop_enabled = not feedback.hitstop_enabled
			3: feedback.flash_enabled = not feedback.flash_enabled
		feedback.reset()
		feedback.play("loot")
		if save_enabled and feedback.save_settings() != OK:
			settings_message = "Could not save preferences. Applied for this session."

func draw_settings() -> void:
	label_at(Vector2(150, 190), "SOUND & COMBAT FEEDBACK", 24, MINT)
	label_at(Vector2(150, 218), "World paused. F10 / Esc: return. Click to change.", 16, MUTED)
	var titles := ["Effects volume", "Camera shake", "Heavy-hit pause (45 ms)", "Hit flashes"]
	var values := ["%d%% / CLICK +20%%" % roundi(feedback.volume * 100), "ON" if feedback.shake_enabled else "OFF", "ON" if feedback.hitstop_enabled else "OFF", "ON" if feedback.flash_enabled else "OFF"]
	for i in range(4):
		label_at(Vector2(160, 267 + i * 68), titles[i], 20, PALE)
		ui_button(settings_rect(i), values[i], true)
	label_at(Vector2(160, 550), "Heavy impacts only. Aim and HUD stay steady. No full-screen flashes.", 16, MUTED)
	label_at(Vector2(160, 584), settings_message if feedback.settings_writable else "Unreadable preferences preserved; changes apply for this session.", 14, GOLD)

func interact_hub() -> void:
	if not hub or not panel.is_empty():
		return
	if player.distance_to(STASH_POS) <= 110:
		panel = "stash"
	elif player.distance_to(GATE_POS) <= 110:
		panel = "gate"

func travel_from_gate(index: int) -> bool:
	if panel != "gate" or player.distance_to(GATE_POS) > 110:
		return false
	return enter_map(index)

func grid_rect(cell: int, storage: bool = false) -> Rect2:
	return Rect2(Vector2(612 if storage else 160, 314) + Vector2(cell % 6, cell / 6) * 54, Vector2(48, 48))

func equipment_rect(index: int) -> Rect2:
	return Rect2(160 + index * 115, 223, 48, 48)

func page_rect(storage: bool, next: bool) -> Rect2:
	return Rect2((612 if storage else 160) + (240 if next else 180), 542, 62, 26)

func change_page(storage: bool, change: int) -> void:
	var count: int = profile.stash.size() if storage else profile.inventory.size()
	var last := maxi(0, (count - 1) / GRID_PAGE_SIZE)
	if storage:
		stash_page = clampi(stash_page + change, 0, last)
	else:
		page = clampi(page + change, 0, last)

func transfer_item(index: int, to_stash: bool) -> void:
	if not hub or panel != "stash" or player.distance_to(STASH_POS) > 110:
		return
	if profile.transfer_item(index, to_stash):
		change_page(false, 0)
		change_page(true, 0)
		persist()

func panel_mouse(mouse: Vector2, button: int, shift: bool) -> void:
	if panel.is_empty():
		return
	if button == MOUSE_BUTTON_LEFT and CLOSE_RECT.has_point(mouse):
		close_panel()
		return
	if panel == "settings":
		if button == MOUSE_BUTTON_LEFT:
			settings_click(mouse)
		return
	if panel == "shrine":
		if button == MOUSE_BUTTON_LEFT:
			for i in range(3):
				if shrine_card(i).has_point(mouse):
					choose_shrine(i)
		return
	if panel == "trial":
		if button == MOUSE_BUTTON_LEFT:
			for i in range(3):
				if map_rect(i).has_point(mouse):
					start_trial(i)
		return
	if panel == "build":
		if button == MOUSE_BUTTON_LEFT:
			build_click(mouse)
		return
	if panel == "gate":
		if button == MOUSE_BUTTON_LEFT and Rect2(700, 234, 300, 34).has_point(mouse) and profile.campaign == 9:
			selected_depth = (profile.depth if selected_depth == 0 else selected_depth) % profile.depth + 1
			return
		if button == MOUSE_BUTTON_LEFT and Rect2(144, 473, 350, 48).has_point(mouse):
			enter_abyss()
			return
		if button == MOUSE_BUTTON_LEFT and Rect2(520, 473, 480, 48).has_point(mouse):
			contract = (contract + 1) % 3
			return
		if button == MOUSE_BUTTON_LEFT:
			for i in range(3):
				if map_rect(i).has_point(mouse):
					travel_from_gate(i)
					return
		return
	if button == MOUSE_BUTTON_MIDDLE:
		toggle_favorite(mouse)
		return
	if button == MOUSE_BUTTON_LEFT:
		for action in range(3):
			if inventory_action_rect(action).has_point(mouse):
				inventory_action(action)
				return
	if button == MOUSE_BUTTON_WHEEL_DOWN or button == MOUSE_BUTTON_WHEEL_UP:
		change_page(panel == "stash" and mouse.x >= 570, 1 if button == MOUSE_BUTTON_WHEEL_DOWN else -1)
		return
	if button == MOUSE_BUTTON_RIGHT and hub:
		for cell in range(GRID_PAGE_SIZE):
			if grid_rect(cell).has_point(mouse) and profile.salvage(page * GRID_PAGE_SIZE + cell):
				change_page(false, 0)
				persist()
				return
	if button != MOUSE_BUTTON_LEFT:
		return
	for storage in [false, true]:
		if storage and panel != "stash":
			continue
		for next in [false, true]:
			if page_rect(storage, next).has_point(mouse):
				change_page(storage, 1 if next else -1)
				return
		for cell in range(GRID_PAGE_SIZE):
			if grid_rect(cell, storage).has_point(mouse):
				var index := (stash_page if storage else page) * GRID_PAGE_SIZE + cell
				if storage:
					transfer_item(index, false)
				elif shift and panel == "stash":
					transfer_item(index, true)
				else:
					equip_item(index)
				change_page(false, 0)
				return

func equip_item(index: int) -> void:
	if not hub:
		return
	if profile.equip(index):
		refresh_stats()
		hp = max_hp
		message = "Equipment updated. Your new stats apply to the next expedition."
		persist()

func enter_map(index: int, as_abyss: bool = false) -> bool:
	if not hub or index < 0 or index >= MAPS.size() or index >= profile.unlocked:
		return false
	if as_abyss and profile.campaign < 9:
		return false
	abyss = as_abyss
	run_depth = (profile.depth if selected_depth == 0 else clampi(selected_depth, 1, profile.depth)) if abyss else 0
	mission = mini(profile.campaign, index * 3 + 2) if not abyss else 9
	heat = 0
	cleave_chain = 0
	wave_flash = 0
	pull_flash = 0
	mastery_time = 0
	hazards.clear()
	boss_stones.clear()
	celebration = ""
	feedback.reset()
	hub = false
	panel = ""
	attack_blocked = true
	map_index = index
	map_cleared = false
	ended = false
	paused = false
	kills = 0
	found = 0
	scrapped = 0
	trial.reset()
	shrine.reset()
	layout.build(index, mission % 3)
	trial.position = layout.cache
	seal_guards.assign([0, 0])
	potions = 3
	return_time = 0
	attack_cooldown = 0.25
	dash_time = 0
	dash_cooldown = 0
	invincible = 0
	slash = 0
	player = Vector2(180, 750)
	refresh_stats()
	hp = max_hp
	enemies.clear()
	drops.clear()
	particles.clear()
	notices.clear()
	var pack_count := 10 + (mission % 3) * 2 + (2 if abyss else 0)
	var centers := [Vector2(600, 760), Vector2(860, 520), Vector2(1060, 780), Vector2(1180, 540), Vector2(1400, 520), Vector2(1500, 780), Vector2(1620, 1000), Vector2(940, layout.cache.y), Vector2(1140, layout.cache.y), Vector2(1840, 1000)]
	for pack in range(pack_count):
		var group := pack % centers.size()
		var seal := 0 if group in [1, 2, 3] else (1 if group in [4, 5, 6] else -1)
		for unit in range(5 + index):
			spawn_enemy(centers[group] + Vector2(randf_range(-65, 65), randf_range(-65, 65)))
			enemies[-1].seal_guard = seal
			if seal >= 0:
				seal_guards[seal] += 1
	seal_required = seal_guards[0] + seal_guards[1]
	spawn_enemy(Vector2(2130, 750), true)
	update_camera()
	message = "MAIN ROUTE / Break two guarded seals, then hunt %s. Purple vault: optional loot." % MAPS[index].boss
	return true

func enter_abyss() -> bool:
	if not hub or panel != "gate" or player.distance_to(GATE_POS) > 110 or profile.campaign < 9:
		return false
	return enter_map(2, true)

func loot_tier() -> int:
	return 3 + run_depth + (1 if contract > 0 else 0) if abyss else map_index + 1

func spawn_enemy(pos: Vector2, boss: bool = false) -> void:
	var tier := map_index + 1
	var kind := 3 if boss else (2 if randf() < 0.12 else (1 if randf() < 0.28 else 0))
	var scale := 1.0 + (mission % 3) * 0.3 + (run_depth * 0.7 if abyss else 0.0)
	var health := (48.0 + tier * 24) * (12 if boss else (2 if kind == 2 else 1)) * scale
	if abyss and contract == 2:
		health *= 1.4
	health *= shrine.multiplier("health")
	var speed := 65.0 if boss else (72.0 if kind == 1 else 92.0)
	if abyss and contract == 1:
		speed *= 1.35
	var hit := (8.0 + tier * 4) * (2 if boss else 1) * (1 + run_depth * 0.13)
	if abyss and contract == 2:
		hit *= 1.2
	pos = layout.safe_position(pos, 32 if boss else 21)
	enemies.append({"pos": pos, "hp": health, "max_hp": health, "radius": 32.0 if boss else (21.0 if kind == 2 else 16.0), "speed": speed, "damage": hit, "flash": 0.0, "brute": boss, "aggro": false, "kind": kind, "skill_cd": randf_range(1.0, 2.8), "elite_mod": randi_range(0, 2) if kind == 2 else -1, "burn_time": 0.0, "burn_dps": 0.0, "slow_time": 0.0, "slow_factor": 1.0})
	if boss:
		next_boss_id += 1
		BossFight.setup(enemies[-1], next_boss_id)

func return_to_hub(defeated: bool = false) -> void:
	shrine.reset()
	feedback.reset()
	hub = true
	hazards.clear()
	boss_stones.clear()
	celebration = ""
	panel = ""
	player = HUB_SPAWN
	camera = Vector2.ZERO
	dash_time = 0
	invincible = 0
	slash = 0
	ended = false
	paused = false
	return_time = 0
	refresh_stats()
	hp = max_hp
	message = "%s / %d kills / %d items / %d auto-salvaged. I: inspect your loot." % ["Rescued: gear retained" if defeated else "Returned to town", kills, found, scrapped]
	enemies.clear()
	drops.clear()
	particles.clear()
	notices.clear()
	persist()

func pickup_nearby(automatic: bool = false) -> void:
	if automatic and profile.loot_mode == 0:
		return
	if hub or ended or paused or not panel.is_empty() or not celebration.is_empty():
		return
	var collected := 0
	var recycled := 0
	for i in range(drops.size() - 1, -1, -1):
		if player.distance_to(drops[i].pos) <= 90 and layout.segment_clear(player, drops[i].pos):
			if profile.collect_item(drops[i].item, automatic and profile.loot_mode == 2):
				feedback.play("relic" if drops[i].item.rarity == 3 else "loot")
				found += 1
				collected += 1
			else:
				scrapped += 1
				recycled += 1
			drops.remove_at(i)
	if collected + recycled > 0:
		message = "Loot: %d collected / %d Common salvaged. I: inspect. L: pickup mode." % [collected, recycled]
		persist()

func cycle_loot_mode() -> void:
	profile.loot_mode = (profile.loot_mode + 1) % Profile.LOOT_MODES.size()
	message = "Loot: " + Profile.LOOT_MODES[profile.loot_mode] + (" / Common drops become embers. Magic, Rare and favorites are kept." if profile.loot_mode == 2 else " / E always collects nearby gear manually.")
	persist()

func toggle_favorite(mouse: Vector2) -> void:
	if not panel in ["inventory", "stash"]:
		return
	var hovered := hovered_item(mouse)
	if hovered.is_empty():
		return
	var item: Dictionary = hovered.item
	item.favorite = not bool(item.get("favorite", false))
	message = "%s: %s" % ["Protected from salvage" if item.favorite else "Protection removed", item.name]
	persist()

func inventory_action_rect(action: int) -> Rect2:
	return [Rect2(520, 187, 160, 34), Rect2(688, 187, 100, 34), Rect2(796, 187, 208, 34)][action]

func inventory_action(action: int) -> void:
	if not panel in ["inventory", "stash"]:
		return
	match action:
		0:
			cycle_loot_mode()
		1:
			profile.sort_inventory()
			page = 0
			message = "Backpack sorted: favorites, slot, rarity, then tier."
			persist()
		2:
			if not hub:
				return
			var before: int = profile.embers
			var count: int = profile.salvage_common()
			change_page(false, 0)
			message = "Salvaged %d Common items / +%d embers. Favorites are protected." % [count, profile.embers - before]
			persist()

func interact_field() -> void:
	if hub or ended or paused or not panel.is_empty():
		return
	pickup_nearby()
	if shrine_available() and player.distance_to(shrine.position) <= 100 and layout.segment_clear(player, shrine.position):
		panel = "shrine"
		return_time = 0
		return
	if trial.state == ExpeditionEvent.State.SEALED and player.distance_to(trial.position) <= 100 and layout.segment_clear(player, trial.position):
		panel = "trial"
		return_time = 0

func start_trial(choice: int) -> bool:
	if hub or ended or paused or panel != "trial" or choice < 0 or choice >= Profile.SLOTS.size() or player.distance_to(trial.position) > 100 or not layout.segment_clear(player, trial.position):
		return false
	if not trial.start(Profile.SLOTS[choice]):
		return false
	close_panel()
	return_time = 0
	for i in range(ExpeditionEvent.GUARD_COUNT):
		spawn_enemy(trial.position + Vector2.RIGHT.rotated(TAU * i / ExpeditionEvent.GUARD_COUNT) * 155)
		var guard: Dictionary = enemies[-1]
		guard.trial_guard = true
		guard.hp *= 1.6
		guard.max_hp = guard.hp
		guard.damage *= 1.25
		guard.aggro = true
		if i == 0:
			guard.kind = 1
		guard.flash = 0.3
	message = "CURSED CACHE / Defeat four marked guards. You may retreat with T."
	return true

func finish_trial() -> void:
	feedback.play("loot")
	var reward: Dictionary = profile.roll_item(mini(9, loot_tier() + 1), true, trial.reward_slot)
	reward.name = "Cachebound " + {"weapon": "Cleaver", "armor": "Mail", "charm": "Charm"}[trial.reward_slot]
	reward.rune = profile.stance
	reward.favorite = true
	profile.inventory.append(reward)
	profile.embers += loot_tier() * 12
	found += 1
	mastery_message = "CURSED CACHE CLEARED / RARE %s DELIVERED" % trial.reward_slot.to_upper()
	mastery_time = 6.0
	burst(trial.position, GOLD, 60)
	message = "CACHE CLAIMED / %s + %d embers. Reward is in your bag, protected." % [reward.name, loot_tier() * 12]

func navigation_target() -> Dictionary:
	var nearest: Dictionary = {}
	var distance := INF
	for enemy in enemies:
		if enemy.brute:
			if seal_required == 0:
				return enemy
			continue
		if int(enemy.get("seal_guard", -1)) < 0:
			continue
		var candidate: float = player.distance_squared_to(enemy.pos)
		if candidate < distance:
			distance = candidate
			nearest = enemy
	return nearest

func _process(delta: float) -> void:
	var combat_delta: float = feedback.advance(delta)
	if not paused and not ended and panel.is_empty() and celebration.is_empty():
		profile.play_seconds += delta
		if hub:
			step_hub(delta)
		else:
			if combat_delta > 0:
				step(combat_delta)
	queue_redraw()

func step_hub(delta: float) -> void:
	town_clock += delta
	var movement := Input.get_vector("left", "right", "up", "down")
	var next := (player + movement * 245 * delta).clamp(HUB_BOUNDS.position + Vector2.ONE * 18, HUB_BOUNDS.end - Vector2.ONE * 18)
	# The chest and campfire are solid; slide around their edges.
	for obstacle in [STASH_POS, Vector2(552, 230)]:
		if next.distance_to(obstacle) < 55:
			next = obstacle + (next - obstacle).normalized() * 55
	player = next
	var aim := get_global_mouse_position() - VIEW.position - player
	if aim.length() > 4:
		facing = aim.normalized()

func update_camera() -> void:
	camera = (player - VIEW.size / 2).clamp(Vector2.ZERO, WORLD.size - VIEW.size)

func step(delta: float) -> void:
	wave_flash = maxf(0, wave_flash - delta)
	pull_flash = maxf(0, pull_flash - delta)
	mastery_time = maxf(0, mastery_time - delta)
	attack_cooldown = maxf(0, attack_cooldown - delta)
	slash = maxf(0, slash - delta)
	dash_time = maxf(0, dash_time - delta)
	dash_cooldown = maxf(0, dash_cooldown - delta)
	invincible = maxf(0, invincible - delta)
	var movement := Input.get_vector("left", "right", "up", "down")
	var aim := get_global_mouse_position() - VIEW.position + camera - player
	if aim.length() > 4:
		facing = aim.normalized()
	if Input.is_action_just_pressed("dash") and dash_cooldown <= 0:
		dash_direction = movement if movement.length() > 0 else facing
		dash_time = 0.17
		dash_cooldown = 1.1
		invincible = 0.23
	if dash_time > 0:
		player = layout.move_body(player, dash_direction * 820 * delta, 18)
		burst(player, MINT, 2)
	else:
		player = layout.move_body(player, movement * 245 * delta, 18)
	player = clamp_point(player, 18)
	update_camera()
	if not Input.is_action_pressed("attack"):
		attack_blocked = false
	var attacking := Input.is_action_pressed("attack") and not attack_blocked
	if attacking and attack_cooldown <= 0:
		attack()
		if not celebration.is_empty():
			return
	if return_time > 0:
		if movement.length() > 0 or attacking or dash_time > 0:
			return_time = 0
			message = "Portal cancelled. Stand still and press T to return."
		else:
			return_time -= delta
			if return_time <= 0:
				return_to_hub()
				return
	update_enemy_statuses(delta)
	if not celebration.is_empty():
		return
	for enemy in enemies:
		if enemy.brute and seal_required > 0:
			continue
		if enemy.brute:
			BossFight.step(self, enemy, delta)
			if ended:
				return
			continue
		var distance: float = enemy.pos.distance_to(player)
		var visible: bool = layout.segment_clear(enemy.pos, player)
		if distance < 370 and visible:
			enemy.aggro = true
		if enemy.aggro:
			if enemy.kind != 1 or distance > 240 or not visible:
				enemy.pos = layout.chase(enemy.pos, player, enemy.radius, enemy.speed * enemy.slow_factor * (1.45 if enemy.elite_mod == 2 else 1.0) * delta)
			enemy.skill_cd -= delta
			if enemy.skill_cd <= 0 and visible and distance <= 450 and (enemy.kind == 1 or enemy.elite_mod == 1):
				enemy.skill_cd = 3.5
				add_hazard(player, 82.0 if enemy.elite_mod == 1 else 62.0, enemy.damage * 1.5, 1.0)
		enemy.flash = maxf(0, enemy.flash - delta)
		if enemy.pos.distance_to(player) < enemy.radius + 16 and visible and invincible <= 0:
			take_hit(enemy.damage)
			if ended:
				return
	for i in range(hazards.size() - 1, -1, -1):
		hazards[i].time -= delta
		if hazards[i].time <= 0:
			var hazard: Dictionary = hazards[i]
			hazards.remove_at(i)
			if not hazard.get("preview_only", false):
				burst(hazard.pos, RED, 20)
			if BossFight.contains(hazard, player) and layout.segment_clear(hazard.pos, player):
				take_hit(hazard.damage)
				if ended:
					return
	for i in range(particles.size() - 1, -1, -1):
		particles[i].life -= delta
		particles[i].pos += particles[i].velocity * delta
		if particles[i].life <= 0:
			particles.remove_at(i)
	for i in range(notices.size() - 1, -1, -1):
		notices[i].life -= delta
		notices[i].pos.y -= 30 * delta
		if notices[i].life <= 0:
			notices.remove_at(i)
	if profile.loot_mode > 0:
		pickup_nearby(true)

func clamp_point(point: Vector2, margin: float) -> Vector2:
	return point.clamp(WORLD.position + Vector2.ONE * margin, WORLD.end - Vector2.ONE * margin)

func add_hazard(pos: Vector2, radius: float, hit: float, delay: float) -> void:
	hazards.append({"pos": pos, "radius": radius, "damage": hit, "time": delay, "duration": delay})

func take_hit(amount: float) -> void:
	if invincible > 0 or ended:
		return
	var hit := maxf(1, amount * shrine.multiplier("incoming") * 100.0 / (100.0 + armor * 5))
	hp = maxf(0, hp - hit)
	invincible = 0.65
	return_time = 0
	feedback.play("hurt")
	feedback.heavy(player, RED, 2.0)
	burst(player, RED, 14)
	notices.append({"pos": player - Vector2(0, 30), "text": "-%d" % hit, "life": 0.7, "color": RED})
	if hp <= 0:
		ended = true
		shrine.reset()
		persist()

func hit_enemy(index: int, amount: float) -> bool:
	var enemy: Dictionary = enemies[index]
	if enemy.brute and seal_required > 0:
		return false
	if enemy.brute:
		amount *= BossFight.multiplier(self, enemy)
	feedback.play("hit")
	if notices.size() >= 96:
		notices.pop_front()
	enemy.hp -= amount
	enemy.flash = 0.12
	enemy.aggro = true
	burst(enemy.pos, GOLD, 5)
	notices.append({"pos": enemy.pos - Vector2(0, 24), "text": str(int(amount)), "life": 0.6, "color": GOLD})
	if enemy.hp <= 0:
		defeat_enemy(index)
	return true

func update_enemy_statuses(delta: float) -> void:
	for i in range(enemies.size() - 1, -1, -1):
		var enemy: Dictionary = enemies[i]
		enemy.slow_time = maxf(0, enemy.slow_time - delta)
		if enemy.slow_time <= 0:
			enemy.slow_factor = 1.0
		if enemy.burn_time > 0:
			var elapsed := minf(delta, enemy.burn_time)
			enemy.burn_time = maxf(0, enemy.burn_time - delta)
			if not enemy.brute or seal_required == 0:
				enemy.hp -= enemy.burn_dps * elapsed * (BossFight.multiplier(self, enemy) if enemy.brute else 1.0)
				if enemy.hp <= 0:
					defeat_enemy(i)

func apply_attack_hit(index: int, amount: float, scorch: float, frost: float) -> bool:
	var enemy: Dictionary = enemies[index]
	if enemy.brute and seal_required > 0:
		return false
	if scorch > 0:
		var burning := amount * 0.2 * scorch
		enemy.burn_dps = maxf(enemy.burn_dps, burning) if enemy.burn_time > 0 else burning
		enemy.burn_time = 2.0
	if frost > 0:
		enemy.slow_time = 1.5
		enemy.slow_factor = pow(0.85, frost)
	return hit_enemy(index, amount)

func attack_damage_at(offset: Vector2, radius: float, combat: Dictionary, wave_ready: bool, fork: bool) -> float:
	if not layout.segment_clear(player, player + offset):
		return 0.0
	var hit := 0.0
	if offset.length() <= combat.reach + radius:
		if profile.stance == 1 or (profile.stance == 0 and (offset.length() <= 28 or facing.dot(offset.normalized()) >= 0.25)):
			hit = combat.damage
		elif profile.stance == 2:
			if facing.dot(offset) >= 0 and absf(facing.cross(offset)) <= 24 + radius:
				hit = combat.damage
			elif fork:
				for angle in [-22.0, 22.0]:
					var ray := facing.rotated(deg_to_rad(angle))
					if ray.dot(offset) >= 0 and absf(ray.cross(offset)) <= 24 + radius:
						hit = combat.damage * 0.6
	if wave_ready and offset.length() <= 300 + radius and facing.dot(offset) >= 0 and absf(facing.cross(offset)) <= 40 + radius:
		hit = maxf(hit, combat.damage * 0.75)
	return hit

func attack() -> void:
	feedback.play(["cleave", "nova", "lance"][profile.stance])
	var combat: Dictionary = expedition_combat()
	attack_cooldown = combat.interval
	slash = 0.16
	slash_angle = facing.angle()
	var landed := false
	var wave: bool = profile.stance == 0 and profile.has_relic("cleave_wave")
	var fork: bool = profile.stance == 2 and profile.has_relic("lance_fork")
	var pull: bool = profile.stance == 1 and profile.has_relic("nova_pull")
	if not wave:
		cleave_chain = 0
	var wave_ready := wave and cleave_chain == 2
	var scorch: float = profile.effect_count("scorch")
	var frost: float = profile.effect_count("frost")
	if pull:
		pull_flash = 0.18
		for enemy in enemies:
			if not enemy.brute and player.distance_to(enemy.pos) <= 250 and layout.segment_clear(player, enemy.pos):
				enemy.pos = layout.move_body(enemy.pos, enemy.pos.direction_to(player) * minf(90, enemy.pos.distance_to(player)), enemy.radius)
	for i in range(enemies.size() - 1, -1, -1):
		var enemy: Dictionary = enemies[i]
		var offset: Vector2 = enemy.pos - player
		var hit := attack_damage_at(offset, enemy.radius, combat, wave_ready, fork)
		if hit > 0:
			landed = apply_attack_hit(i, hit, scorch, frost) or landed
	for i in range(boss_stones.size() - 1, -1, -1):
		var hit := attack_damage_at(boss_stones[i].pos - player, 22, combat, wave_ready, fork)
		if hit > 0:
			hit_stone(i, hit)
			landed = true
	if landed:
		heat = minf(100, heat + heat_per_hit())
		if wave:
			cleave_chain = (cleave_chain + 1) % 3
			if wave_ready:
				wave_flash = 0.18
		if profile.support == 2:
			hp = minf(max_hp, hp + max_hp * combat.recovery)

func ember_burst() -> void:
	if hub or ended or paused or not panel.is_empty() or heat < 100:
		return
	heat = 0
	return_time = 0
	feedback.play("burst")
	feedback.heavy(player, MINT, 4.0)
	burst(player, MINT, 65)
	for i in range(enemies.size() - 1, -1, -1):
		if player.distance_to(enemies[i].pos) <= 250 and layout.segment_clear(player, enemies[i].pos):
			hit_enemy(i, damage * 4 * (1 + profile.rune_bonus()))
	for i in range(boss_stones.size() - 1, -1, -1):
		if player.distance_to(boss_stones[i].pos) <= 272 and layout.segment_clear(player, boss_stones[i].pos):
			hit_stone(i, damage * 4 * (1 + profile.rune_bonus()))
	invincible = maxf(invincible, 0.25)

func hit_stone(index: int, amount: float) -> void:
	var stone: Dictionary = boss_stones[index]
	stone.hp -= amount
	burst(stone.pos, MINT, 5)
	if stone.hp > 0:
		return
	feedback.play("heavy")
	feedback.heavy(stone.pos, MINT)
	var owner: int = stone.owner
	boss_stones.remove_at(index)
	for enemy in enemies:
		if enemy.brute and enemy.boss_id == owner and BossFight.stone_count(self, enemy) == 0:
			enemy.weak_time = 3.0
			BossFight.recover(enemy, 2.5)
			hazards = hazards.filter(func(h: Dictionary) -> bool: return h.get("owner", -1) != owner)
			message = "WARD BROKEN / Sentinel exposed: +35% damage for 3 seconds."
			break

func defeat_enemy(index: int) -> void:
	var enemy: Dictionary = enemies[index]
	feedback.play("heavy" if enemy.brute or enemy.kind == 2 else "kill")
	if enemy.brute or enemy.kind == 2:
		feedback.heavy(enemy.pos, GOLD, 4.0 if enemy.brute else 2.5)
	kills += 1
	var guard_seal: int = enemy.get("seal_guard", -1)
	if guard_seal >= 0:
		seal_guards[guard_seal] = maxi(0, seal_guards[guard_seal] - 1)
		seal_required = seal_guards[0] + seal_guards[1]
		if seal_guards[guard_seal] == 0:
			message = "SEAL %s BROKEN / Follow the main route." % ("I" if guard_seal == 0 else "II")
			feedback.play("loot")
	var old_level: int = profile.level
	var experience: int = (30 if enemy.brute else 8) * (map_index + 1)
	profile.gain_xp(experience)
	var trained: Array[String] = profile.gain_mastery(experience)
	if not trained.is_empty():
		mastery_message = "MASTERY UP / " + " + ".join(trained)
		mastery_time = 4.0
		burst(player, MINT, 24)
	refresh_stats()
	if profile.level > old_level:
		hp = minf(max_hp, hp + 20)
		message = "Level %d! Permanent base stats increased." % profile.level
	if enemy.brute or enemy.kind == 2 or kills == 1 or randf() < 0.45:
		var loot: Dictionary = profile.roll_item(loot_tier(), enemy.brute)
		if enemy.kind == 2 and loot.rarity == 0:
			loot = profile.roll_item(loot_tier(), true)
		drops.append({"pos": enemy.pos, "item": loot})
	if enemy.elite_mod == 0:
		add_hazard(enemy.pos, 105, enemy.damage * 1.8, 1.1)
	if enemy.brute and profile.record_relic_hunt(map_index, loot_tier()):
		feedback.play("relic")
		mastery_message = "RELIC FOUND / " + Effects.RELICS[map_index].name
		mastery_time = 6.0
	profile.embers += 1 + (run_depth if enemy.brute else 0)
	if enemy.brute:
		var owner: int = enemy.boss_id
		boss_stones = boss_stones.filter(func(stone: Dictionary) -> bool: return stone.owner != owner)
		hazards = hazards.filter(func(h: Dictionary) -> bool: return h.get("owner", -1) != owner)
		if shrine.claim_reward():
			var bonus: Dictionary = profile.roll_item(loot_tier(), true)
			bonus.favorite = true
			profile.inventory.append(bonus)
			found += 1
			feedback.play("loot")
			mastery_message = "GREED FULFILLED / BONUS RARE DELIVERED & PROTECTED"
			mastery_time = 6.0
		map_cleared = true
		if abyss:
			profile.embers += 20 * run_depth * (2 if contract > 0 else 1)
			if run_depth == 5:
				profile.abyss_complete = true
				celebration = "THE LAST EMBER ENDURES"
			profile.depth = mini(5, maxi(profile.depth, run_depth + 1))
		else:
			var advanced: bool = profile.complete_mission(mission)
			if advanced and profile.campaign % 3 == 0:
				feedback.play("relic")
			if advanced and profile.campaign == 9:
				celebration = "THE CINDER TYRANT HAS FALLEN"
			elif advanced and profile.campaign % 3 == 0:
				celebration = "A SEAL SHATTERS"
		message = "Guardian defeated! Rare loot: E. Return: T. Next journey is ready at the gate."
	elif guard_seal >= 0 and seal_required == 0:
		message = "The seal is broken. The guardian awaits at the eastern altar."
	if kills % 20 == 0:
		potions = mini(3, potions + 1)
	if enemy.get("trial_guard", false) and trial.guard_defeated():
		finish_trial()
	enemies.remove_at(index)
	persist()

func burst(pos: Vector2, color: Color, count: int) -> void:
	for i in range(mini(count, maxi(0, 320 - particles.size()))):
		particles.append({"pos": pos, "velocity": Vector2.RIGHT.rotated(randf() * TAU) * randf_range(30, 170), "life": randf_range(0.15, 0.4), "color": color})

func label_at(pos: Vector2, value: String, size: int, color: Color = PALE) -> void:
	draw_string(font, pos, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func bar(rect: Rect2, ratio: float, color: Color) -> void:
	draw_rect(rect, Color("263346"))
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * clampf(ratio, 0, 1), rect.size.y)), color)

func rarity_color(item: Dictionary) -> Color:
	return [PALE, Color("82b5ff"), GOLD, Color("ff9864")][int(item.rarity)]

func item_stats(item: Dictionary) -> String:
	if item.is_empty():
		return "Empty slot"
	var stats := Mods.totals(item)
	return "ATK %d   HP %d   DEF %d   SPD %d%%" % [stats.attack, stats.health, stats.armor, stats.haste]

func map_rect(index: int) -> Rect2:
	return Rect2(144 + index * 292, 280, 276, 170)

func _draw() -> void:
	draw_rect(Rect2(0, 0, 1152, 720), Color("0b101a"))
	if hub:
		draw_hub()
	else:
		draw_world()
	draw_hud()
	if feedback.relic_time > 0 and celebration.is_empty() and panel.is_empty():
		draw_relic_banner(236)
	if not panel.is_empty():
		draw_panel()
	if not profile.save_error.is_empty():
		label_at(Vector2(30, 715), profile.save_error, 13, RED)
	if not celebration.is_empty():
		draw_overlay(celebration, "Depth 5 conquered. The flame is safe." if profile.abyss_complete else ("The story is complete. The Abyss now opens at the town gate." if profile.campaign == 9 else "A skill-changing relic is in your bag. A new chapter awaits."))
		if feedback.relic_time > 0:
			draw_relic_banner(440)
		label_at(Vector2(340, 375), "Press any key, collect your loot, then T to return.", 18, MINT)
	elif ended:
		draw_overlay("RESCUED FROM THE DEPTHS", "Collected gear and character progress are retained.")
		label_at(Vector2(389, 397), "Press R to return to town", 24, MINT)
	elif paused:
		draw_overlay("PAUSED", "Esc to resume / F10 sound & feedback")

func draw_hub() -> void:
	draw_set_transform(VIEW.position)
	draw_rect(Rect2(Vector2.ZERO, VIEW.size), Color("14202b"))
	for x in range(40, 1064, 64):
		for y in range(40, 500, 64):
			draw_rect(Rect2(x + 2, y + 2, mini(60, 1062 - x), mini(60, 498 - y)), Color("1c2b36") if (x + y) % 3 else Color("202f39"))
	draw_rect(HUB_BOUNDS, Color("44515b"), false, 5)
	draw_line(Vector2(285, 310), Vector2(830, 310), Color("36424a"), 54)
	draw_line(Vector2(552, 310), Vector2(552, 480), Color("36424a"), 54)
	for x in [94, 1010]:
		for y in [90, 443]:
			draw_rect(Rect2(x - 12, y - 15, 24, 30), Color("46515b"))
			draw_circle(Vector2(x, y - 20), 22, Color(1, 0.6, 0.2, 0.08))
			draw_circle(Vector2(x, y - 20), 6, GOLD)
	# Campfire and stone ring.
	var fire := Vector2(552, 230)
	draw_circle(fire, 70, Color(1, 0.5, 0.2, 0.05))
	draw_arc(fire, 33, 0, TAU, 12, Color("69717b"), 10, true)
	draw_line(fire + Vector2(-19, 12), fire + Vector2(19, -8), Color("9a7250"), 8)
	draw_line(fire + Vector2(19, 12), fire + Vector2(-19, -8), Color("9a7250"), 8)
	draw_colored_polygon(PackedVector2Array([fire + Vector2(-14, 7), fire + Vector2(0, -34 - sin(town_clock * 4) * 4), fire + Vector2(15, 7)]), GOLD)
	# Stash chest, with lid, bands and lock.
	var chest := STASH_POS
	draw_circle(chest + Vector2(0, 18), 49, Color(0, 0, 0, 0.24))
	draw_rect(Rect2(chest - Vector2(37, 25), Vector2(74, 56)), Color("765438"))
	draw_rect(Rect2(chest - Vector2(37, 25), Vector2(74, 22)), Color("b38855"))
	draw_rect(Rect2(chest - Vector2(37, 25), Vector2(74, 56)), GOLD.darkened(0.3), false, 3)
	for offset in [-22, 22]:
		draw_line(chest + Vector2(offset, -25), chest + Vector2(offset, 31), GOLD.darkened(0.2), 5)
	draw_rect(Rect2(chest + Vector2(-6, -7), Vector2(12, 16)), GOLD)
	label_at(chest + Vector2(-29, -54), "STASH", 18, GOLD)
	# Animated warp gate and its stone pillars.
	var gate := GATE_POS
	draw_circle(gate, 78, Color(0.3, 0.7, 1, 0.06))
	draw_circle(gate, 51, Color("1b4056"))
	draw_arc(gate, 57, 0, TAU, 60, Color("82b5ff"), 5, true)
	draw_arc(gate, 43, town_clock, town_clock + PI * 1.6, 40, MINT, 2, true)
	for side in [-1, 1]:
		draw_rect(Rect2(gate + Vector2(side * 70 - 10, -48), Vector2(20, 96)), Color("526177"))
		draw_line(gate + Vector2(side * 70, -33), gate + Vector2(side * 70, 28), MINT, 3)
	label_at(gate + Vector2(-51, -82), "WARP GATE", 18, MINT)
	draw_player()
	if panel.is_empty():
		if player.distance_to(STASH_POS) <= 110:
			label_at(chest + Vector2(-66, 67), "[E] OPEN STASH", 16, GOLD)
		elif player.distance_to(GATE_POS) <= 110:
			label_at(gate + Vector2(-84, 92), "[E] CHOOSE A MAP", 16, MINT)
	draw_set_transform(Vector2.ZERO)
	label_at(Vector2(58, 142), "HUNTER'S REST", 20, PALE)
	label_at(Vector2(58, 167), "A quiet place between expeditions", 13, MUTED)

func draw_panel() -> void:
	draw_rect(Rect2(0, 108, 1152, 540), Color(0.015, 0.025, 0.045, 0.82))
	draw_rect(Rect2(115, 140, 922, 480), Color("121d2a"))
	draw_rect(Rect2(115, 140, 922, 480), Color("506172"), false, 2)
	draw_rect(CLOSE_RECT, Color("293746"))
	label_at(CLOSE_RECT.position + Vector2(13, 23), "X", 19, PALE)
	if panel == "settings":
		draw_settings()
		return
	if panel == "shrine":
		draw_shrine_panel()
		return
	if panel == "trial":
		draw_trial_panel()
		return
	if panel == "build":
		draw_build()
		return
	if panel == "gate":
		label_at(Vector2(144, 186), "WAYPOINT / SELECT A DESTINATION", 24, MINT)
		label_at(Vector2(144, 222), "Three expeditions per chapter. Break seals to reach the guardian.", 16, MUTED)
		if profile.campaign == 9:
			ui_button(Rect2(700, 234, 300, 34), "DEPTH %d / CLICK TO CHANGE" % (profile.depth if selected_depth == 0 else selected_depth), true)
		for i in range(3):
			var rect := map_rect(i)
			var available: bool = i < profile.unlocked
			draw_rect(rect, MAPS[i].color if available else Color("171c25"))
			draw_rect(rect, MINT if available and rect.has_point(get_global_mouse_position()) else Color("354355"), false, 2)
			label_at(rect.position + Vector2(16, 30), "CHAPTER %d / CLEARED %d OF 3" % [i + 1, clampi(profile.campaign - i * 3, 0, 3)], 13, MUTED)
			label_at(rect.position + Vector2(16, 64), MAPS[i].name, 18, PALE if available else MUTED)
			label_at(rect.position + Vector2(16, 98), MAPS[i].boss, 15, GOLD)
			label_at(rect.position + Vector2(16, 119), "RELIC %d/3: %s" % [profile.relic_hunts[i], ["CLEAVE WAVE", "NOVA PULL", "LANCE FORK"][i]] if profile.campaign >= (i + 1) * 3 else "FIRST CHAPTER CLEAR: RELIC", 11, Color("ff9864"))
			label_at(rect.position + Vector2(16, 143), "TRAVEL / CLICK OR %d" % (i + 1) if available else "LOCKED / CLEAR PREVIOUS MAP", 13, MINT if available else MUTED)
		ui_button(Rect2(144, 473, 350, 48), "[4] ABYSS / DEPTH %d" % (profile.depth if selected_depth == 0 else selected_depth) if profile.campaign == 9 else "ABYSS / COMPLETE CHAPTER 3", profile.campaign == 9)
		ui_button(Rect2(520, 473, 480, 48), CONTRACTS[contract], true)
		label_at(Vector2(144, 548), "Abyss contracts: extra item tier and double guardian embers. Click to cycle.", 14, MUTED)
		label_at(Vector2(144, 574), "Esc / E to close   |   B: build & forge in town", 15, MUTED)
		return
	label_at(Vector2(144, 179), "STASH & INVENTORY" if panel == "stash" else "INVENTORY", 23, GOLD)
	ui_button(inventory_action_rect(0), "[L] " + Profile.LOOT_MODES[profile.loot_mode], profile.loot_mode > 0)
	ui_button(inventory_action_rect(1), "SORT")
	ui_button(inventory_action_rect(2), "SCRAP COMMON (%d)" % profile.common_salvage_count() if hub else "SCRAP IN TOWN", hub and profile.common_salvage_count() > 0)
	label_at(Vector2(160, 208), "EQUIPPED", 12, MUTED)
	for i in range(3):
		var item: Dictionary = profile.equipment[Profile.SLOTS[i]]
		draw_item_cell(equipment_rect(i), item)
		label_at(equipment_rect(i).position + Vector2(0, 62), Profile.SLOTS[i].to_upper(), 11, MUTED)
	label_at(Vector2(160, 306), "BACKPACK", 14, MINT)
	draw_grid(false)
	if panel == "stash":
		label_at(Vector2(612, 306), "PERSONAL STASH", 14, GOLD)
		draw_grid(true)
		label_at(Vector2(612, 245), "Click stored gear to take it out.", 15, PALE)
		label_at(Vector2(612, 271), "Shift-click backpack gear to store it.", 14, MUTED)
	else:
		label_at(Vector2(612, 269), "CHARACTER / LEVEL %d" % profile.level, 20, MINT)
		label_at(Vector2(612, 316), "Skill hit           %.1f" % expedition_combat().damage, 18)
		label_at(Vector2(612, 350), "Maximum health      %d" % max_hp, 18)
		label_at(Vector2(612, 384), "Defense             %d" % armor, 18)
		label_at(Vector2(612, 418), "Attack interval     %.2fs" % attack_interval, 18)
		label_at(Vector2(612, 452), "BURN %.0f%%/s / SLOW %.1f%% / HEAT +%.0f" % [profile.effect_count("scorch") * 20, (1.0 - pow(0.85, profile.effect_count("frost"))) * 100, profile.effect_count("charge") * 4], 12, Color("ff9864"))
		if not hub and shrine.choice >= 0:
			label_at(Vector2(612, 514), Shrine.OFFERS[shrine.choice].name, 14, GOLD)
			label_at(Vector2(612, 540), Shrine.OFFERS[shrine.choice].benefit, 13, MINT)
			label_at(Vector2(612, 562), Shrine.OFFERS[shrine.choice].cost, 13, RED)
		label_at(Vector2(612, 480), "Embers: %d / B: build & forge" % profile.embers, 15, MUTED)
	label_at(Vector2(144, 598), "Hover: compare / Click: equip / Right-click: salvage / F or middle-click: protect / I: close" if hub else "Hover: compare / F or middle-click: protect / Equip & salvage in town / I: close", 14, MUTED)
	var hovered := hovered_item(get_global_mouse_position())
	if not hovered.is_empty():
		draw_item_tooltip(hovered.item, hovered.equipped, hovered.storage)

func draw_grid(storage: bool) -> void:
	var items: Array[Dictionary] = profile.stash if storage else profile.inventory
	var current_page := stash_page if storage else page
	for cell in range(GRID_PAGE_SIZE):
		var index := current_page * GRID_PAGE_SIZE + cell
		draw_item_cell(grid_rect(cell, storage), items[index] if index < items.size() else {})
	var origin := Vector2(612 if storage else 160, 559)
	label_at(origin, "%d ITEMS / %d" % [items.size(), current_page + 1], 12, MUTED)
	for next in [false, true]:
		var rect := page_rect(storage, next)
		draw_rect(rect, Color("293746"))
		label_at(rect.position + Vector2(8, 18), "NEXT >" if next else "< PREV", 11, MINT)

func draw_item_cell(rect: Rect2, item: Dictionary) -> void:
	var hover := rect.has_point(get_global_mouse_position())
	draw_rect(rect, Color("263f4b") if hover else Color("0c1420"))
	draw_rect(rect, rarity_color(item).darkened(0.35) if not item.is_empty() else Color("304052"), false, 1)
	if item.is_empty():
		return
	var c := rect.get_center()
	var color := rarity_color(item)
	match item.slot:
		"weapon":
			draw_line(c + Vector2(-10, 12), c + Vector2(13, -14), color, 5, true)
			draw_line(c + Vector2(-13, 2), c + Vector2(0, 14), GOLD, 3, true)
		"armor":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-9, -15), c + Vector2(-18, -5), c + Vector2(-11, 0), c + Vector2(-11, 14), c + Vector2(11, 14), c + Vector2(11, 0), c + Vector2(18, -5), c + Vector2(9, -15), c + Vector2(0, -9)]), color)
		"charm":
			draw_arc(c - Vector2(0, 5), 11, 0, TAU, 24, GOLD, 2, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -3), c + Vector2(8, 7), c + Vector2(0, 17), c + Vector2(-8, 7)]), color)
	label_at(rect.position + Vector2(3, 11), str(int(item.tier)), 10, color)
	if item.get("favorite", false):
		label_at(rect.position + Vector2(34, 14), "*", 19, GOLD)

func hovered_item(mouse: Vector2) -> Dictionary:
	for i in range(3):
		var item: Dictionary = profile.equipment[Profile.SLOTS[i]]
		if equipment_rect(i).has_point(mouse) and not item.is_empty():
			return {"item": item, "equipped": true, "storage": false}
	for storage in [false, true]:
		if storage and panel != "stash":
			continue
		var items: Array[Dictionary] = profile.stash if storage else profile.inventory
		for cell in range(GRID_PAGE_SIZE):
			var index := (stash_page if storage else page) * GRID_PAGE_SIZE + cell
			if grid_rect(cell, storage).has_point(mouse) and index < items.size():
				return {"item": items[index], "equipped": false, "storage": storage}
	return {}

func tooltip_rect(mouse: Vector2) -> Rect2:
	var origin := mouse + Vector2(20, 18)
	if origin.x + 410 > 1140:
		origin.x = mouse.x - 430
	origin.y = minf(origin.y, 704 - 340)
	return Rect2(origin.clamp(Vector2(12, 12), Vector2(730, 364)), Vector2(410, 340))

func draw_item_tooltip(item: Dictionary, equipped: bool, storage: bool) -> void:
	if item.has("mods"):
		draw_mod_tooltip(item)
		return
	var rect := tooltip_rect(get_global_mouse_position())
	draw_rect(Rect2(rect.position + Vector2(5, 5), rect.size), Color(0, 0, 0, 0.5))
	draw_rect(rect, Color("0c1420"))
	draw_rect(rect, rarity_color(item), false, 2)
	var p := rect.position + Vector2(16, 27)
	label_at(p, item.name, 19, rarity_color(item))
	label_at(p + Vector2(0, 26), "%s / %s / TIER %d" % [Profile.RARITIES[int(item.rarity)], item.slot.to_upper(), item.tier], 13, MUTED)
	draw_line(p + Vector2(0, 41), p + Vector2(316, 41), Color("304052"))
	var current: Dictionary = profile.equipment[item.slot]
	var keys := ["attack", "health", "armor", "haste"]
	var names := ["Attack damage", "Maximum health", "Defense", "Attack speed %"]
	for i in range(4):
		var key: String = keys[i]
		var delta := int(Mods.totals(item)[key]) - int(Mods.totals(current)[key])
		label_at(p + Vector2(0, 67 + i * 26), "%s: %d" % [names[i], item[key]], 16)
		if not equipped:
			label_at(p + Vector2(261, 67 + i * 26), "%+d" % delta, 16, MINT if delta > 0 else (RED if delta < 0 else MUTED))
	label_at(p + Vector2(0, 178), "Rune: %s / Forge +%d" % [Profile.STANCES[int(item.rune)] + " +12%" if int(item.get("rune", -1)) >= 0 else "None", int(item.get("upgrade", 0))], 12, MUTED)
	var effect_text := "No special effect"
	var detail_text := "Magic and Rare gear can carry combat effects."
	if item.has("relic"):
		var definition: Dictionary = Effects.RELICS[Effects.relic_index(item.relic)]
		effect_text = definition.effect
		detail_text = definition.detail
	elif item.has("affix"):
		effect_text = Effects.AFFIXES[item.affix].name + " / normal attacks"
		detail_text = Effects.AFFIXES[item.affix].text
	label_at(p + Vector2(0, 204), effect_text, 13, Color("ff9864"))
	label_at(p + Vector2(0, 228), detail_text, 12, PALE)
	label_at(p + Vector2(0, 252), "Boss source: chapter %d / first clear or every 3 repeat kills" % (Effects.relic_index(item.relic) + 1) if item.has("relic") else "Matching affixes stack across equipped slots.", 11, MUTED)
	label_at(p + Vector2(0, 278), "PROTECTED / Cannot be salvaged" if item.get("favorite", false) else "F / middle-click: protect from salvage", 12, MINT)
	var hint := "Equipped"
	if not equipped:
		hint = "Click to take out" if storage else ("Click to equip" if hub else "Equip after returning to town")
		if panel == "stash" and not storage:
			hint += " / Shift-click to store"
	label_at(p + Vector2(0, 300), hint, 13, GOLD)

func draw_world() -> void:
	draw_set_transform(VIEW.position - camera + feedback.offset)
	draw_rect(WORLD, Color("0d121b"))
	for floor_rect in layout.floors:
		draw_rect(floor_rect, MAPS[map_index].color)
		for x in range(int(floor_rect.position.x), int(floor_rect.end.x), 40):
			draw_line(Vector2(x, floor_rect.position.y), Vector2(x, floor_rect.end.y), Color(0.6, 0.7, 0.8, 0.045))
		for y in range(int(floor_rect.position.y), int(floor_rect.end.y), 40):
			draw_line(Vector2(floor_rect.position.x, y), Vector2(floor_rect.end.x, y), Color(0.6, 0.7, 0.8, 0.045))
	for wall in layout.walls:
		if Rect2(camera, VIEW.size).grow(40).intersects(wall):
			draw_rect(wall, Color("26323b"))
			draw_rect(wall.grow(-3), Color("1a242e"))
			draw_line(wall.position, wall.position + Vector2(wall.size.x, 0), Color("49535c"), 3)
	for room in layout.rooms:
		label_at(room.rect.position + Vector2(18, 30), room.name, 14, MUTED)
	for i in range(2):
		var seal_color := MINT if seal_guards[i] == 0 else GOLD
		draw_arc(layout.seals[i], 46, 0, TAU, 32, seal_color, 3, true)
		label_at(layout.seals[i] + Vector2(-65, 65), "SEAL %s / %s" % ["I" if i == 0 else "II", "BROKEN" if seal_guards[i] == 0 else "%d GUARDS" % seal_guards[i]], 13, seal_color)
	draw_arc(Vector2(180, 750), 48, 0, TAU, 40, MINT, 3, true)
	label_at(Vector2(116, 819), "T / TOWN PORTAL", 14, MINT)
	draw_arc(Vector2(2130, 750), 130, 0, TAU, 50, GOLD.darkened(0.5), 2, true)
	draw_trial_world()
	draw_shrine_world()
	draw_navigation()
	for hazard in hazards:
		BossFight.draw_warning(self, hazard)
	for stone in boss_stones:
		draw_colored_polygon(PackedVector2Array([stone.pos + Vector2(0, -23), stone.pos + Vector2(18, 0), stone.pos + Vector2(0, 23), stone.pos + Vector2(-18, 0)]), Color("a998f5"))
		bar(Rect2(stone.pos + Vector2(-24, -32), Vector2(48, 4)), stone.hp / stone.max_hp, MINT)
		label_at(stone.pos + Vector2(-38, 42), "WARD STONE", 11, MINT)
	for drop in drops:
		var color := rarity_color(drop.item)
		draw_line(drop.pos, drop.pos - Vector2(0, 40), Color(color, 0.4), 3)
		draw_circle(drop.pos, 7, color)
		label_at(drop.pos + Vector2(12, -8), drop.item.name, 14, color)
		if player.distance_to(drop.pos) <= 90 and layout.segment_clear(player, drop.pos):
			label_at(drop.pos + Vector2(12, 12), "E / PICK UP", 12, MINT)
	for enemy in enemies:
		draw_enemy(enemy)
		if enemy.brute:
			label_at(enemy.pos - Vector2(65, 49), MAPS[map_index].boss, 17, GOLD)
	for particle in particles:
		var color: Color = particle.color
		color.a = minf(1, particle.life * 4)
		draw_circle(particle.pos, 2.5, color)
	draw_player()
	if slash > 0:
		var color := Color(0.44, 0.94, 0.82, slash / 0.16)
		var reach: float = profile.combat_stats().reach
		if profile.stance == 2:
			draw_line(player, layout.move_body(player, Vector2.RIGHT.rotated(slash_angle) * reach, 1, false), color, 16, true)
		else:
			draw_visible_arc(reach, 0 if profile.stance == 1 else slash_angle - 1.2, TAU if profile.stance == 1 else slash_angle + 1.2, color, 7)
	for ring in feedback.rings:
		var ring_color: Color = ring.color
		ring_color.a = ring.life / 0.25 * 0.5
		draw_arc(ring.pos, 20 + (1.0 - ring.life / 0.25) * 65, 0, TAU, 32, ring_color, 2, true)
	if wave_flash > 0:
		draw_line(player, layout.move_body(player, Vector2.RIGHT.rotated(slash_angle) * 300, 1, false), Color("ff9864"), 18 * wave_flash / 0.18, true)
	if pull_flash > 0:
		draw_visible_arc(250 * pull_flash / 0.18, 0, TAU, Color("ad9cff"), 3)
	if slash > 0 and profile.stance == 2 and profile.has_relic("lance_fork"):
		for angle in [-22.0, 22.0]:
			draw_line(player, layout.move_body(player, Vector2.RIGHT.rotated(slash_angle + deg_to_rad(angle)) * profile.combat_stats().reach, 1, false), Color("ff9864"), 5, true)
	if return_time > 0:
		draw_arc(player, 40, -PI / 2, -PI / 2 + TAU * (1 - return_time / 2), 40, MINT, 4, true)
	for notice in notices:
		label_at(notice.pos, notice.text, 19, notice.color)
	draw_set_transform(Vector2.ZERO)
	# Cover world overflow so UI stays in viewport coordinates.
	draw_rect(Rect2(0, 0, 1152, 108), Color("0b101a"))
	draw_rect(Rect2(0, 648, 1152, 72), Color("0b101a"))
	draw_rect(Rect2(0, 108, 24, 540), Color("0b101a"))
	draw_rect(Rect2(1128, 108, 24, 540), Color("0b101a"))
	draw_rect(VIEW, Color("354355"), false)
	var mini_rect := Rect2(948, 122, 164, 103)
	draw_rect(mini_rect, Color(0.02, 0.04, 0.06, 0.85))
	for floor_rect in layout.floors:
		draw_rect(Rect2(mini_rect.position + floor_rect.position / WORLD.size * mini_rect.size, floor_rect.size / WORLD.size * mini_rect.size), Color("35464a"))
	for pillar in layout.pillars:
		draw_rect(Rect2(mini_rect.position + pillar.position / WORLD.size * mini_rect.size, pillar.size / WORLD.size * mini_rect.size), Color("0b101a"))
	for i in range(2):
		draw_arc(mini_rect.position + layout.seals[i] / WORLD.size * mini_rect.size, 4, 0, TAU, 12, MINT if seal_guards[i] == 0 else GOLD, 1.5)

	for enemy in enemies:
		draw_circle(mini_rect.position + enemy.pos / WORLD.size * mini_rect.size, 4 if enemy.brute else 2, GOLD if enemy.brute else RED)
	if trial.state != ExpeditionEvent.State.COMPLETE:
		draw_rect(Rect2(mini_rect.position + trial.position / WORLD.size * mini_rect.size - Vector2(3, 3), Vector2(6, 6)), Color("ad9cff"))
	var shrine_dot: Vector2 = mini_rect.position + shrine.position / WORLD.size * mini_rect.size
	draw_colored_polygon(PackedVector2Array([shrine_dot + Vector2(0, -4), shrine_dot + Vector2(4, 0), shrine_dot + Vector2(0, 4), shrine_dot + Vector2(-4, 0)]), GOLD if shrine_available() else MUTED)
	draw_circle(mini_rect.position + player / WORLD.size * mini_rect.size, 3, MINT)
	if trial.state == ExpeditionEvent.State.ACTIVE:
		label_at(Vector2(948, 244), "CACHE / %d GUARDS" % trial.remaining, 12, Color("ad9cff"))
	for enemy in enemies:
		if enemy.brute and enemy.aggro and seal_required == 0:
			label_at(Vector2(475, 133), "%s / %d%%" % [MAPS[map_index].boss, int(enemy.hp / enemy.max_hp * 100)], 14, GOLD)
			bar(Rect2(475, 142, 330, 6), enemy.hp / enemy.max_hp, RED)
			label_at(Vector2(475, 168), enemy.move_name, 12, MINT if enemy.state == "recovery" else GOLD)
			label_at(Vector2(475, 189), "WARD: 30% LESS DAMAGE" if BossFight.stone_count(self, enemy) > 0 else ("EXPOSED: +35% DAMAGE" if enemy.weak_time > 0 else "PHASE %d" % enemy.phase), 11, MUTED)
			break
	label_at(Vector2(34, 135), "BOSS DEFEATED / COLLECT LOOT & RETURN" if map_cleared else ("SEALS %d / 2 / %d GUARDS" % [int(seal_guards[0] == 0) + int(seal_guards[1] == 0), seal_required] if seal_required > 0 else "SEAL BROKEN / DEFEAT THE GUARDIAN"), 15, GOLD)

func draw_hud() -> void:
	label_at(Vector2(28, 41), "E M B E R", 29, GOLD)
	label_at(Vector2(30, 67), "TOWN / HUNTER'S REST" if hub else ("ABYSS / DEPTH %d" % run_depth if abyss else "%02d / %s" % [mission + 1, JOURNEYS[mission]]), 13, MUTED)
	label_at(Vector2(340, 29), "VITALITY %d / %d" % [hp, max_hp], 13)
	bar(Rect2(340, 41, 240, 9), hp / max_hp, RED)
	label_at(Vector2(624, 29), "LEVEL %d / XP %d OF %d" % [profile.level, profile.xp, profile.xp_needed()], 13, MINT)
	bar(Rect2(624, 41, 235, 5), float(profile.xp) / profile.xp_needed(), MINT)
	label_at(Vector2(920, 32), "BAG %d / STASH %d" % [profile.inventory.size(), profile.stash.size()], 14, GOLD)
	label_at(Vector2(920, 58), "MAPS %d / 3" % profile.unlocked if hub else "POTIONS %d / 3 [Q]" % potions, 13, MUTED)
	label_at(Vector2(30, 93), message, 14, MINT)
	label_at(Vector2(780, 74), "[L] %s / %s" % [Profile.LOOT_MODES[profile.loot_mode], "LOOT SETTINGS" if hub else ("DODGE READY" if dash_cooldown <= 0 else "DODGE %.1fs" % dash_cooldown)], 12, MINT)
	label_at(Vector2(340, 73), "%s Lv.%d + %s Lv.%d / %s" % [Profile.STANCES[profile.stance], profile.skill_levels[profile.stance], Profile.SUPPORTS[profile.support], profile.support_levels[profile.support], "[F] BURST READY" if heat >= 100 else "HEAT %d%%" % heat], 12, GOLD)
	if not hub and shrine.choice >= 0:
		label_at(Vector2(34, 155), "PACT / " + Shrine.OFFERS[shrine.choice].name, 12, GOLD)
		label_at(Vector2(34, 173), Shrine.OFFERS[shrine.choice].benefit + " / " + Shrine.OFFERS[shrine.choice].cost, 11, PALE)
	if not hub and profile.has_relic(Effects.RELICS[profile.stance].id):
		label_at(Vector2(34, 186), ["RELIC / WAVE %d OF 3" % cleave_chain, "RELIC / NOVA PULL", "RELIC / LANCE FORK"][profile.stance], 12, Color("ff9864"))
	if not hub and mastery_time > 0:
		label_at(Vector2(34, 214), mastery_message, 16, MINT)
	label_at(Vector2(30, 709), "JOURNEY %d / 9  |  EMBERS %d  |  TALENTS %d  |  %d MIN  |  %s" % [profile.campaign, profile.embers, profile.talent_points(), int(profile.play_seconds / 60), "ABYSS CONQUERED" if profile.abyss_complete else ("ABYSS DEPTH %d" % profile.depth if profile.campaign == 9 else "NEXT: CHAPTER %d - EXPEDITION %d" % [profile.campaign / 3 + 1, profile.campaign % 3 + 1])], 12, MUTED)
	label_at(Vector2(30, 683), "WASD Move  /  E Interact  /  I Inventory & Salvage  /  B Build & Forge  /  F10 Settings" if hub else "WASD Move / Mouse Aim / LMB-Space Attack / Shift Dodge / F Burst / E Loot / Q Heal / T Town / I Bag / F10 Settings", 13, MUTED)

func draw_overlay(title: String, subtitle: String) -> void:
	draw_rect(Rect2(0, 0, 1152, 720), Color(0.025, 0.04, 0.065, 0.93))
	var width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x
	label_at(Vector2((1152 - width) / 2, 260), title, 32, GOLD)
	width = font.get_string_size(subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	label_at(Vector2((1152 - width) / 2, 305), subtitle, 18, MUTED)
func draw_enemy(enemy: Dictionary) -> void:
	var pos: Vector2 = enemy.pos
	var radius: float = enemy.radius
	var color := GOLD if enemy.brute else (Color("ad9cff") if enemy.kind == 1 else (Color("fcb36b") if enemy.kind == 2 else RED))
	if enemy.brute and seal_required > 0:
		draw_arc(pos, radius + 14, 0, TAU, 40, MINT, 3, true)
	if int(enemy.get("seal_guard", -1)) >= 0:
		label_at(pos + Vector2(-5, radius + 15), "I" if enemy.seal_guard == 0 else "II", 11, GOLD)
	if enemy.get("trial_guard", false):
		draw_arc(pos, radius + 6, 0, TAU, 24, Color("ad9cff"), 2, true)
	if enemy.burn_time > 0:
		draw_arc(pos, radius + 3, 0, TAU, 20, Color("ff9864"), 3, true)
	if enemy.slow_time > 0:
		draw_arc(pos, radius + 9, 0, TAU, 20, Color("91caff"), 2, true)
	if enemy.elite_mod >= 0:
		label_at(pos + Vector2(-44, -radius - 32), Effects.ELITES[enemy.elite_mod], 11, GOLD)
		label_at(pos + Vector2(-44, -radius - 19), ["DEATH BLAST", "AVOID MARKS", "+45% SPEED"][enemy.elite_mod], 10, MUTED)
	if enemy.brute and enemy.state == "recovery":
		draw_arc(pos, radius + 12, 0, TAU, 32, MINT, 3, true)
	if enemy.flash > 0 and feedback.flash_enabled:
		color = Color.WHITE
	draw_circle(pos + Vector2(0, radius * 0.6), radius, Color(0, 0, 0, 0.25))
	var points := PackedVector2Array()
	for j in range(6):
		points.append(pos + Vector2.UP.rotated(j * TAU / 6) * radius)
	draw_colored_polygon(points, color.darkened(0.24))
	points.append(points[0])
	draw_polyline(points, color, 2, true)
	draw_line(pos + Vector2(-7, -2), pos + Vector2(-2, 1), PALE, 2)
	draw_line(pos + Vector2(2, 1), pos + Vector2(7, -2), PALE, 2)
	if enemy.hp < enemy.max_hp:
		bar(Rect2(pos + Vector2(-18, -radius - 9), Vector2(36, 3)), enemy.hp / enemy.max_hp, RED)

func draw_player() -> void:
	draw_circle(player + Vector2(0, 10), 19, Color(0, 0, 0, 0.3))
	var player_color := Color.WHITE if feedback.flash_enabled and invincible > 0 and int(invincible * 24) % 2 == 0 else MINT
	draw_colored_polygon(PackedVector2Array([player + Vector2(-14, 14), player + Vector2(-11, -9), player + Vector2(0, -18), player + Vector2(11, -9), player + Vector2(14, 14)]), player_color)
	draw_rect(Rect2(player + Vector2(-8, -7), Vector2(16, 8)), Color("101926"))
	draw_line(player + Vector2(-5, -3), player + Vector2(5, -3), GOLD, 2)
	var hand := player + facing * 21
	draw_line(hand - facing.orthogonal() * 6, hand + facing.orthogonal() * 6, GOLD, 3, true)
	draw_line(hand, player + facing * 47, PALE, 5, true)


func ui_button(rect: Rect2, title: String, active: bool = false) -> void:
	draw_rect(rect, Color("294047") if active else Color("1b2838"))
	draw_rect(rect, MINT if active else MUTED.darkened(0.5), false, 1)
	label_at(rect.position + Vector2(12, 26), title, 14, MINT if active else PALE)

func build_rect(row: int, column: int) -> Rect2:
	return Rect2(144 + column * 286, 225 + row * 78, 270, 40)

func mastery_rect(is_support: bool, index: int) -> Rect2:
	return Rect2(144 + index * 286, 393 if is_support else 236, 270, 149)

func build_tab_rect(index: int) -> Rect2:
	return Rect2(144 + index * 286, 188, 270, 34)

func draw_skill_icon(center: Vector2, index: int, is_support: bool, color: Color) -> void:
	var diamond := PackedVector2Array([center + Vector2(0, -17), center + Vector2(17, 0), center + Vector2(0, 17), center + Vector2(-17, 0), center + Vector2(0, -17)])
	draw_colored_polygon(diamond, color.darkened(0.8))
	draw_polyline(diamond, color.darkened(0.3), 1.5, true)
	if not is_support:
		match index:
			0:
				draw_arc(center, 9, -1.3, 1.3, 16, color, 3, true)
				draw_line(center + Vector2(-7, 7), center + Vector2(6, -6), color, 2, true)
			1:
				draw_arc(center, 9, 0, TAU, 20, color, 2, true)
				draw_circle(center, 3, color)
			2:
				draw_line(center + Vector2(-10, 7), center + Vector2(10, -7), color, 3, true)
				draw_line(center + Vector2(3, -7), center + Vector2(10, -7), color, 2, true)
	else:
		match index:
			0:
				draw_colored_polygon(PackedVector2Array([center + Vector2(1, -12), center + Vector2(-7, 2), center, center + Vector2(-1, 12), center + Vector2(8, -3), center + Vector2(2, -3)]), color)
			1:
				for x in [-6, 3]:
					draw_polyline(PackedVector2Array([center + Vector2(x - 3, -7), center + Vector2(x + 3, 0), center + Vector2(x - 3, 7)]), color, 2, true)
			2:
				draw_arc(center + Vector2(0, 3), 7, 0, PI, 14, color, 2, true)
				draw_polyline(PackedVector2Array([center + Vector2(-7, 3), center + Vector2(0, -10), center + Vector2(7, 3)]), color, 2, true)

func draw_mastery_card(is_support: bool, index: int) -> void:
	var rect := mastery_rect(is_support, index)
	var entry: Dictionary = Skills.SUPPORTS[index] if is_support else Skills.SKILLS[index]
	var selected: bool = (profile.support if is_support else profile.stance) == index
	var unlocked: bool = not is_support or profile.support_unlocked(index)
	var level: int = (profile.support_levels if is_support else profile.skill_levels)[index]
	var experience: int = (profile.support_xp if is_support else profile.skill_xp)[index]
	var color := ([GOLD, Color("a998f5"), MINT][index] if is_support else [Color("f5b27b"), MINT, Color("91bfff")][index]) as Color
	if not unlocked:
		color = MUTED
	var hover := rect.has_point(get_global_mouse_position())
	draw_rect(rect, Color("223342") if hover else (Color("1b2d38") if selected else Color("101b29")))
	draw_rect(rect, color if selected else Color("3a4b5f"), false, 2 if selected else 1)
	if selected:
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, 3)), color)
	var p := rect.position
	draw_skill_icon(p + Vector2(27, 29), index, is_support, color)
	label_at(p + Vector2(51, 28), entry.name, 20, color)
	label_at(p + Vector2(210, 27), "Lv.%d" % level if unlocked else "LOCK", 13, color)
	label_at(p + Vector2(12, 56), entry.tags, 11, MUTED)
	var combat: Dictionary = profile.combat_stats(-1 if is_support else index, index if is_support else -1)
	var effect := Skills.support_effect(index, level) if is_support else "%.1f DMG  /  %.2fs  /  %.0f RANGE" % [combat.damage, combat.interval, combat.reach]
	label_at(p + Vector2(12, 78), effect, 13, PALE)
	var role: String = entry.role
	if not is_support and profile.has_relic(Effects.RELICS[index].id):
		role = ["RELIC / Every third hit sends a wave", "RELIC / Pull enemies into your nova", "RELIC / Two extra piercing rays"][index]
	label_at(p + Vector2(12, 98), role, 12, Color("ff9864") if role.begins_with("RELIC") else MUTED)
	var status := "MAX MASTERY" if level == Skills.MAX_LEVEL else "%d / %d XP" % [experience, Skills.xp_needed(level)]
	if not unlocked:
		status = "UNLOCK / CLEAR CHAPTER 1"
	label_at(p + Vector2(12, 125), status, 11, color)
	if selected:
		label_at(p + Vector2(202, 125), "LINKED", 10, color)
	bar(Rect2(p + Vector2(12, 134), Vector2(246, 4)), 1.0 if level == Skills.MAX_LEVEL else float(experience) / Skills.xp_needed(level), color)

func draw_mastery_details(is_support: bool, index: int) -> void:
	var entry: Dictionary = Skills.SUPPORTS[index] if is_support else Skills.SKILLS[index]
	var level: int = (profile.support_levels if is_support else profile.skill_levels)[index]
	var mouse := get_global_mouse_position()
	var origin := mouse + Vector2(18, 18)
	if origin.x + 414 > 1140:
		origin.x = mouse.x - 432
	origin = origin.clamp(Vector2(12, 12), Vector2(726, 374))
	var rect := Rect2(origin, Vector2(414, 334))
	draw_rect(Rect2(origin + Vector2(5, 5), rect.size), Color(0, 0, 0, 0.6))
	draw_rect(rect, Color("0c1420"))
	draw_rect(rect, GOLD if is_support else MINT, false, 2)
	var p := origin + Vector2(16, 29)
	label_at(p, "%s / LEVEL %d OF %d" % [entry.name, level, Skills.MAX_LEVEL], 19, GOLD if is_support else MINT)
	label_at(p + Vector2(0, 27), entry.flavor, 13, MUTED)
	label_at(p + Vector2(0, 57), entry.detail, 12, PALE)
	var combat: Dictionary = profile.combat_stats(-1 if is_support else index, index if is_support else -1)
	var current: Dictionary = profile.combat_stats()
	label_at(p + Vector2(0, 88), "WITH %s / CURRENT GEAR & RUNES" % (Profile.STANCES[profile.stance] if is_support else Profile.SUPPORTS[profile.support]), 12, GOLD)
	label_at(p + Vector2(0, 115), "Hit %.1f  |  Interval %.3fs  |  DPS %.1f" % [combat.damage, combat.interval, combat.damage / combat.interval], 15)
	label_at(p + Vector2(0, 140), "DPS vs equipped: %+.1f  /  Range %.0f" % [combat.damage / combat.interval - current.damage / current.interval, combat.reach], 13, MINT)
	label_at(p + Vector2(0, 163), "Recovery %.2f%% life / landed attack" % (combat.recovery * 100), 13, PALE)
	if level < Skills.MAX_LEVEL:
		var next: Dictionary = profile.combat_stats(-1 if is_support else index, index if is_support else -1, not is_support, is_support)
		label_at(p + Vector2(0, 194), "NEXT / LEVEL %d" % (level + 1), 13, GOLD)
		if is_support:
			label_at(p + Vector2(0, 219), Skills.support_effect(index, level + 1), 14)
		else:
			label_at(p + Vector2(0, 219), "Hit %.1f -> %.1f / Range %.0f -> %.0f" % [combat.damage, next.damage, combat.reach, next.reach], 14)
	else:
		label_at(p + Vector2(0, 210), "MASTERED / Maximum level reached", 14, GOLD)
	label_at(p + Vector2(0, 254), "Kills train the equipped pair. Switching keeps progress.", 12, MUTED)
	label_at(p + Vector2(0, 278), "DPS excludes burn, relic waves and additional targets.", 12, MUTED)
	label_at(p + Vector2(0, 301), "Clear chapter 1 to unlock this support." if is_support and not profile.support_unlocked(index) else "Click the card to equip in town. No currency cost.", 12, MINT)

func draw_build() -> void:
	label_at(Vector2(144, 176), "THE EMBER GRIMOIRE", 23, GOLD)
	for tab in range(3):
		ui_button(build_tab_rect(tab), ["SKILLS & SUPPORTS", "TALENTS & FORGE", "MOD CRAFTING"][tab], build_tab == tab)
	label_at(Vector2(731, 176), "EMBERS %d / POINTS %d" % [profile.embers, profile.talent_points()], 12, MUTED)
	if build_tab == 2:
		draw_crafting()
		return
	if build_tab == 1:
		draw_forge_tab()
		return
	for is_support in [false, true]:
		for i in range(3):
			draw_mastery_card(is_support, i)
	var combat: Dictionary = profile.combat_stats()
	label_at(Vector2(144, 568), "%s Lv.%d  +  %s Lv.%d" % [Profile.STANCES[profile.stance], profile.skill_levels[profile.stance], Profile.SUPPORTS[profile.support], profile.support_levels[profile.support]], 17, MINT)
	label_at(Vector2(590, 568), "HIT %.1f / %.2fs / DPS %.1f" % [combat.damage, combat.interval, combat.damage / combat.interval], 15, GOLD)
	label_at(Vector2(144, 597), "Click: equip / Hover: lore, comparison & next level / Kills train your linked pair / B: close", 13, MUTED)
	for is_support in [false, true]:
		for i in range(3):
			if mastery_rect(is_support, i).has_point(get_global_mouse_position()):
				draw_mastery_details(is_support, i)

func draw_forge_tab() -> void:
	label_at(Vector2(144, 263), "TEMPER THE HUNTER", 23, MINT)
	label_at(Vector2(144, 295), "Spend earned talent points. Reclaim them freely to try a different path.", 16, PALE)
	label_at(Vector2(144, 324), "Salvage unwanted gear in your inventory; feed the embers into your equipment.", 14, MUTED)
	for i in range(3):
		ui_button(build_rect(2, i), "%s %d / 6 [+]" % [["MIGHT", "VITALITY", "TEMPO"][i], profile.talents[i]], profile.talent_points() > 0)
		label_at(build_rect(2, i).position + Vector2(0, 58), ["+5 attack per point", "+20 life / +1 defense per point", "+6% attack speed per point"][i], 13, MUTED)
		var slot: String = Profile.SLOTS[i]
		var gear: Dictionary = profile.equipment[slot]
		var rank := int(gear.get("upgrade", 0))
		ui_button(build_rect(3, i), "%s +%d / %s" % [slot.to_upper(), rank, "MAX" if rank >= 3 else "%d EMBERS" % profile.upgrade_cost(slot)], not gear.is_empty() and rank < 3 and profile.embers >= profile.upgrade_cost(slot))
		label_at(build_rect(3, i).position + Vector2(0, 58), "Empty slot" if gear.is_empty() else gear.name, 12, MUTED)
	ui_button(Rect2(144, 550, 270, 40), "RESET TALENTS / FREE")
	label_at(Vector2(440, 576), "I: inventory / right-click gear to salvage / B: close", 14, MUTED)

func build_click(mouse: Vector2) -> void:
	if not hub or panel != "build":
		return
	if not craft_pending.is_empty():
		craft_click(mouse)
		return
	for tab in range(3):
		if build_tab_rect(tab).has_point(mouse):
			build_tab = tab
			return
	if build_tab == 2:
		craft_click(mouse)
		return
	for i in range(3):
		if build_tab == 0:
			if mastery_rect(false, i).has_point(mouse):
				profile.stance = i
			if mastery_rect(true, i).has_point(mouse) and profile.support_unlocked(i):
				profile.support = i
		else:
			if build_rect(2, i).has_point(mouse):
				profile.spend_talent(i)
			if build_rect(3, i).has_point(mouse):
				profile.upgrade(Profile.SLOTS[i])
	if build_tab == 1 and Rect2(144, 550, 270, 40).has_point(mouse):
		profile.talents.assign([0, 0, 0])
	refresh_stats()
	hp = max_hp
	persist()


func draw_trial_panel() -> void:
	label_at(Vector2(144, 186), "CURSED CACHE / CHOOSE YOUR PRIZE", 24, Color("ad9cff"))
	label_at(Vector2(144, 220), "Four marked guards awaken: +60% life and +25% damage. Kill all four to claim.", 15, PALE)
	label_at(Vector2(144, 250), "Optional encounter. Retreat is allowed; an unfinished cache gives no bonus reward.", 14, MUTED)
	for i in range(3):
		var rect := map_rect(i)
		draw_rect(rect, Color("241f36"))
		draw_rect(rect, Color("ad9cff") if rect.has_point(get_global_mouse_position()) else Color("564668"), false, 2)
		label_at(rect.position + Vector2(16, 30), "GUARANTEED RARE / TIER %d" % mini(9, loot_tier() + 1), 13, GOLD)
		label_at(rect.position + Vector2(16, 65), Profile.SLOTS[i].to_upper(), 24, PALE)
		label_at(rect.position + Vector2(16, 98), "Rune: " + Profile.STANCES[profile.stance], 15, MINT)
		label_at(rect.position + Vector2(16, 143), "AWAKEN / CLICK OR %d" % (i + 1), 14, Color("ad9cff"))
	label_at(Vector2(144, 490), "+%d embers. Chosen gear goes directly to your bag and is protected from salvage." % (loot_tier() * 12), 15, GOLD)
	label_at(Vector2(144, 531), "Only the marked guards count toward this challenge. No time limit.", 15, MUTED)
	label_at(Vector2(144, 577), "Esc / E: leave the cache sealed", 15, MINT)

func draw_trial_world() -> void:
	var pos: Vector2 = trial.position
	var color := Color("ad9cff") if trial.state != ExpeditionEvent.State.COMPLETE else MUTED
	draw_arc(pos, 48, 0, TAU, 32, color, 2, true)
	draw_rect(Rect2(pos - Vector2(24, 17), Vector2(48, 34)), color.darkened(0.65))
	draw_rect(Rect2(pos - Vector2(24, 17), Vector2(48, 34)), color, false, 2)
	draw_line(pos + Vector2(-23, -5), pos + Vector2(23, -5), color, 3)
	draw_rect(Rect2(pos - Vector2(4, 8), Vector2(8, 14)), GOLD)
	var title := "CURSED CACHE"
	if trial.state == ExpeditionEvent.State.ACTIVE:
		title = "GUARDS REMAINING / %d" % trial.remaining
	elif trial.state == ExpeditionEvent.State.COMPLETE:
		title = "CACHE CLAIMED"
	label_at(pos + Vector2(-75, -62), title, 14, color)
	if trial.state == ExpeditionEvent.State.SEALED and player.distance_to(pos) <= 100:
		label_at(pos + Vector2(-86, 75), "[E] CHOOSE YOUR REWARD", 13, MINT)

func draw_navigation() -> void:
	var target := navigation_target()
	if target.is_empty() or (Rect2(camera, VIEW.size).grow(-25).has_point(target.pos) and layout.segment_clear(player, target.pos)):
		return
	var waypoint: Vector2 = layout.guide(player, target.pos)
	var direction: Vector2 = (waypoint - player).normalized()
	var center := player + direction * 76
	var side := direction.orthogonal()
	var color := GOLD if target.brute else MINT
	draw_colored_polygon(PackedVector2Array([center + direction * 13, center - direction * 8 + side * 7, center - direction * 8 - side * 7]), color)
	label_at(center + Vector2(-23, 27), "BOSS" if target.brute else "SEAL", 11, color)

func draw_relic_banner(y: float) -> void:
	draw_rect(Rect2(355, y, 442, 54), Color("271e24"))
	draw_rect(Rect2(355, y, 442, 54), Color("ff9864"), false, 2)
	label_at(Vector2(378, y + 23), "RELIC ACQUIRED / A NEW WAY TO FIGHT", 17, Color("ff9864"))
	label_at(Vector2(378, y + 43), "Protected in your bag. I: inspect and equip.", 14, PALE)

func draw_visible_arc(radius: float, start: float, end: float, color: Color, width: float) -> void:
	for i in range(48):
		var a := player + Vector2.RIGHT.rotated(lerpf(start, end, i / 48.0)) * radius
		var b := player + Vector2.RIGHT.rotated(lerpf(start, end, (i + 1) / 48.0)) * radius
		if layout.segment_clear(player, a) and layout.segment_clear(player, b):
			draw_line(a, b, color, width, true)

func expedition_combat() -> Dictionary:
	var combat: Dictionary = profile.combat_stats()
	combat.damage *= shrine.multiplier("attack")
	return combat

func heat_per_hit() -> float:
	return (12 + profile.effect_count("charge") * 4) * shrine.multiplier("heat")

func potion_healing() -> float:
	return max_hp * 0.5 * shrine.multiplier("potion")

func use_potion() -> bool:
	if hub or ended or paused or not panel.is_empty() or not celebration.is_empty() or potions <= 0 or hp >= max_hp:
		return false
	potions -= 1
	hp = minf(max_hp, hp + potion_healing())
	return true

func shrine_available() -> bool:
	if hub or ended or map_cleared or shrine.choice >= 0:
		return false
	# The bargain must precede the guardian fight, including a damaged but disengaged boss.
	for enemy in enemies:
		if enemy.brute and (enemy.aggro or enemy.hp < enemy.max_hp):
			return false
	return true

func choose_shrine(option: int) -> bool:
	if paused or panel != "shrine" or not celebration.is_empty() or not shrine_available() or player.distance_to(shrine.position) > 100 or not layout.segment_clear(player, shrine.position):
		return false
	if not shrine.choose(option):
		return false
	var factor: float = shrine.multiplier("health")
	for enemy in enemies:
		# Preserve damage already dealt as a percentage; never refill a wounded enemy.
		enemy.hp *= factor
		enemy.max_hp *= factor
	for stone in boss_stones:
		stone.hp *= factor
		stone.max_hp *= factor
	close_panel()
	feedback.play("heavy")
	burst(shrine.position, GOLD, 28)
	message = Shrine.OFFERS[option].name + " / " + Shrine.OFFERS[option].benefit + " / " + Shrine.OFFERS[option].cost + ". This expedition only."
	return true

func shrine_card(index: int) -> Rect2:
	return Rect2(144 + index * 292, 254, 276, 262)

func shrine_preview(option: int) -> Array[String]:
	match option:
		0:
			return ["Hit %.1f -> %.1f" % [profile.combat_stats().damage, profile.combat_stats().damage * shrine.multiplier("attack", option)], "Potion %.1f -> %.1f HP" % [max_hp * 0.5, max_hp * 0.5 * shrine.multiplier("potion", option)]]
		1:
			return ["Heat %.0f -> %.0f / hit" % [heat_per_hit(), heat_per_hit() * shrine.multiplier("heat", option)], "100 damage -> 115 before armor"]
		_:
			return ["Bonus Rare / Tier %d" % loot_tier(), "All living & future enemies"]

func draw_shrine_panel() -> void:
	label_at(Vector2(144, 186), "SHRINE OF BARGAINS / OPTIONAL", 24, GOLD)
	label_at(Vector2(144, 222), "Choose one pact for this expedition. Take a benefit and its cost together.", 16, PALE)
	for i in range(3):
		var rect := shrine_card(i)
		var offer: Dictionary = Shrine.OFFERS[i]
		draw_rect(rect, Color("282329"))
		draw_rect(rect, GOLD if rect.has_point(get_global_mouse_position()) else MUTED, false, 2)
		var p := rect.position + Vector2(14, 30)
		label_at(p, offer.name, 19, GOLD)
		label_at(p + Vector2(0, 38), offer.benefit, 16, MINT)
		label_at(p + Vector2(0, 68), offer.cost, 16, RED)
		label_at(p + Vector2(0, 106), offer.hint, 13, MUTED)
		var preview := shrine_preview(i)
		label_at(p + Vector2(0, 145), preview[0], 15, PALE)
		label_at(p + Vector2(0, 170), preview[1], 13, PALE)
		label_at(p + Vector2(0, 214), "ACCEPT / CLICK OR %d" % (i + 1), 15, GOLD)
	label_at(Vector2(144, 549), "One pact per expedition. No switching. Ends on death or return to town.", 15, MUTED)
	label_at(Vector2(144, 577), "Esc / E: leave without a pact. Available until the guardian fight begins.", 15, MINT)

func draw_shrine_world() -> void:
	var pos: Vector2 = shrine.position
	var color := GOLD if shrine_available() else MUTED
	draw_arc(pos, 34, 0, TAU, 32, color, 2, true)
	draw_colored_polygon(PackedVector2Array([pos + Vector2(0, -26), pos + Vector2(17, 0), pos + Vector2(0, 26), pos + Vector2(-17, 0)]), color.darkened(0.25))
	draw_circle(pos, 5, PALE)
	label_at(pos + Vector2(-82, -44), "SHRINE / OPTIONAL" if shrine_available() else ("PACT TAKEN" if shrine.choice >= 0 else "SHRINE DORMANT"), 13, color)
	if shrine_available() and player.distance_to(pos) <= 100 and layout.segment_clear(player, pos):
		label_at(pos + Vector2(-80, 58), "[E] WEIGH THE COST", 13, GOLD)

func craft_row(index: int) -> Rect2:
	return Rect2(144, 318 + index * 49, 394, 43)

func draw_crafting() -> void:
	for i in range(3):
		ui_button(Rect2(144 + i * 286, 250, 270, 40), Profile.SLOTS[i].to_upper(), craft_slot == Profile.SLOTS[i])
	var item: Dictionary = profile.equipment[craft_slot]
	if Mods.capacity(item) == 0:
		label_at(Vector2(144, 345), "Equip Magic or Rare gear to craft its Mods.", 22, GOLD)
		label_at(Vector2(144, 387), "Common gear and Relics keep their own identity. I: equip a crafting base.", 16, MUTED)
		return
	label_at(Vector2(144, 311), "%s / BASE TIER %d" % [item.name, item.tier], 15, GOLD)
	var mods := Mods.entries(item)
	for i in range(4):
		ui_button(craft_row(i), ("P%d  " % (i + 1) if i < 2 else "S%d  " % (i - 1)) + (Mods.describe(mods[i]) if i % 2 < Mods.capacity(item) else "Rare gear required"), craft_index == i)
	if not craft_pending.is_empty():
		label_at(Vector2(566, 318), "CRAFT RESULT / COST PAID", 20, GOLD)
		label_at(Vector2(566, 357), "OLD: " + Mods.describe(mods[craft_index]), 13, MUTED)
		label_at(Vector2(566, 387), "NEW: " + Mods.describe(craft_pending.item.mods[craft_index]), 13, MINT)
		var before := Mods.totals(item)
		var after := Mods.totals(craft_pending.item)
		label_at(Vector2(566, 422), "ATK %d -> %d / LIFE %d -> %d" % [before.attack, after.attack, before.health, after.health], 15)
		label_at(Vector2(566, 449), "DEF %d -> %d / SPD %d%% -> %d%%" % [before.armor, after.armor, before.haste, after.haste], 15)
		ui_button(Rect2(566, 478, 208, 40), "KEEP NEW", true)
		ui_button(Rect2(790, 478, 214, 40), "KEEP OLD")
		label_at(Vector2(144, 571), "Closing keeps the old Mod. Materials are spent for the attempt; no refunds.", 15, MUTED)
		return
	var pool := Mods.pool(craft_index / 2)
	if not craft_id in pool:
		craft_id = pool[0]
	for i in range(pool.size()):
		ui_button(Rect2(566 + i % 2 * 222, 306 + i / 2 * 45, 214, 38), Mods.DEFINITIONS[pool[i]].name, craft_id == pool[i])
	for i in range(3):
		ui_button(Rect2(566 + i * 146, 404, 138, 38), "T%d%s" % [3 - i, " LOCKED" if 3 - i < Mods.best_tier(item) else ""], craft_tier == 3 - i)
	var limits: Array = Mods.DEFINITIONS[craft_id].ranges[3 - craft_tier]
	label_at(Vector2(566, 469), "%d-%d %s / selected Mod: 100%%" % [limits[0], limits[1], Mods.DEFINITIONS[craft_id].unit], 14, PALE)
	var quote: Dictionary = profile.craft_quote(craft_slot, craft_index, craft_id, craft_tier)
	ui_button(Rect2(566, 487, 438, 40), "UNAVAILABLE / LOCK, TIER OR DUPLICATE" if quote.is_empty() else "CRAFT / %d EMBERS%s" % [quote.cost, " / NOT ENOUGH" if profile.embers < quote.cost else ""], not quote.is_empty() and profile.embers >= quote.cost)
	ui_button(Rect2(144, 526, 394, 38), "UNLOCK SELECTED MOD" if mods[craft_index].get("locked", false) else "LOCK SELECTED MOD / FREE", not mods[craft_index].is_empty())
	label_at(Vector2(566, 552), "Cost is spent on rolling. Keep new or old; no refund.", 12, MUTED)
	label_at(Vector2(144, 591), "Select slot -> Mod -> Tier. Only that slot changes. T1 is strongest; higher bases unlock it.", 14, MUTED)

func craft_click(mouse: Vector2) -> void:
	if not hub or panel != "build" or build_tab != 2:
		return
	if not craft_pending.is_empty():
		if Rect2(566, 478, 208, 40).has_point(mouse):
			message = "New Mod kept." if profile.accept_craft(craft_pending) else "Equipment changed; old item preserved."
		elif Rect2(790, 478, 214, 40).has_point(mouse):
			message = "Original Mod kept. Attempt cost consumed."
		else:
			return
		craft_pending.clear()
		refresh_stats()
		hp = max_hp
		persist()
		return
	for i in range(3):
		if Rect2(144 + i * 286, 250, 270, 40).has_point(mouse):
			craft_slot = Profile.SLOTS[i]
			craft_index = 0
			craft_id = "might"
			craft_tier = maxi(craft_tier, Mods.best_tier(profile.equipment[craft_slot]))
			return
	var item: Dictionary = profile.equipment[craft_slot]
	if Mods.capacity(item) == 0:
		return
	for i in range(4):
		if craft_row(i).has_point(mouse) and i % 2 < Mods.capacity(item):
			craft_index = i
			craft_id = Mods.pool(i / 2)[0]
			return
	var pool := Mods.pool(craft_index / 2)
	for i in range(pool.size()):
		if Rect2(566 + i % 2 * 222, 306 + i / 2 * 45, 214, 38).has_point(mouse):
			craft_id = pool[i]
			return
	for i in range(3):
		if Rect2(566 + i * 146, 404, 138, 38).has_point(mouse) and 3 - i >= Mods.best_tier(item):
			craft_tier = 3 - i
			return
	if Rect2(144, 526, 394, 38).has_point(mouse):
		profile.toggle_mod_lock(craft_slot, craft_index)
		persist()
	elif Rect2(566, 487, 438, 40).has_point(mouse):
		craft_pending = profile.begin_craft(profile.craft_quote(craft_slot, craft_index, craft_id, craft_tier))
		if not craft_pending.is_empty():
			persist() # Attempts cost materials even when rejected or the game is closed.

func draw_mod_tooltip(item: Dictionary) -> void:
	var rect := tooltip_rect(get_global_mouse_position())
	draw_rect(rect, Color("0c1420"))
	draw_rect(rect, rarity_color(item), false, 2)
	var p := rect.position + Vector2(14, 25)
	label_at(p, "%s / BASE T%d" % [item.name, item.tier], 17, rarity_color(item))
	label_at(p + Vector2(0, 26), "%s / %s / TEMPER +%d" % [Profile.RARITIES[item.rarity], item.slot.to_upper(), item.get("upgrade", 0)], 12, MUTED)
	label_at(p + Vector2(0, 52), "BASE: ATK %d / HP %d / DEF %d / SPD %d%%" % [item.attack, item.health, item.armor, item.haste], 12)
	var mods := Mods.entries(item)
	for i in range(4):
		label_at(p + Vector2(0, 80 + i * 24), ("PREFIX " if i < 2 else "SUFFIX ") + (Mods.describe(mods[i]) if i % 2 < Mods.capacity(item) else "--"), 12, MINT if i < 2 else GOLD)
	label_at(p + Vector2(0, 185), item_stats(item), 13, PALE)
	var actual := Mods.totals(item)
	var current := Mods.totals(profile.equipment[item.slot])
	label_at(p + Vector2(0, 209), "VS EQUIPPED: ATK %+d / HP %+d / DEF %+d / SPD %+d%%" % [actual.attack - current.attack, actual.health - current.health, actual.armor - current.armor, actual.haste - current.haste], 11, MINT)
	label_at(p + Vector2(0, 234), "Rune: " + (Profile.STANCES[item.rune] if item.get("rune", -1) >= 0 else "None"), 13, GOLD)
	label_at(p + Vector2(0, 260), "B > MOD CRAFTING / T3 -> T2 -> T1", 12, MUTED)
	label_at(p + Vector2(0, 285), "SALVAGE PROTECTED" if item.get("favorite", false) else "F / middle click: protect from salvage", 12, MINT)
	label_at(p + Vector2(0, 307), "Mod locks protect crafting slots, not the item from salvage.", 11, MUTED)

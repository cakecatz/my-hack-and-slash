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
const UiState = preload("res://scripts/ui_state.gd")
const Loc = preload("res://scripts/loc.gd")
const PassiveTree = preload("res://scripts/passive_tree.gd")
const FONT_REGULAR := preload("res://assets/fonts/NotoSansJP-Regular.otf")
const FONT_BOLD := preload("res://assets/fonts/NotoSansJP-Bold.otf")
const VIEW := Rect2(24, 108, 1104, 540)
const WORLD := Rect2(0, 0, 2400, 1500)
const HUB_BOUNDS := Rect2(40, 40, 1024, 460)
const HUB_SPAWN := Vector2(552, 390)
const STASH_POS := Vector2(285, 230)
const GATE_POS := Vector2(830, 230)
const TRAINING_POS := Vector2(150, 400)
const GRID_PAGE_SIZE := 24
const CLOSE_RECT := Rect2(982, 150, 40, 32)
const MINT := Color("70efd0")
const GOLD := Color("ffc478")
const RED := Color("f27386")
const PALE := Color("e0e9f4")
const MUTED := Color("8597ae")
const MANA := Color("82b5ff")
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
var ui_state = UiState.new()
var title := false
var title_choice := 0
var title_confirm := false
var has_save := false
var pause_choice := 0
var pause_view := "menu"
const PAUSE_ITEMS := ["resume", "settings", "controls", "title", "quit"]
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
# -1 means "pick at random for this expedition"; tests set them explicitly.
var layout_template := -1
var layout_flip := -1
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
var mana := 100.0
var max_mana := 100.0
var mana_regen := 6.0
var damage := 18.0
var armor := 1.0
var attack_interval := 0.4
var attack_cooldown := 0.0
var slash := 0.0
var slash_angle := 0.0
var slash_skill := 0
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
var slot_focus := 0
var support_focus := 0
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
var projectiles: Array[Dictionary] = []
var zones: Array[Dictionary] = []
var ability_cd: Array[float] = [0.0, 0.0, 0.0, 0.0]
var shield := 0.0
var shield_time := 0.0
var rush_time := 0.0
var rush_haste := 0.0
var rush_move := 0.0
var notices: Array[Dictionary] = []
var next_enemy_id := 0
var training := false
var training_time := 0.0
var training_total := 0.0
var training_burn := 0.0
var training_hits := 0
var last_message := ""
var message_time := 0.0
var area_banner := ""
var area_banner_time := 0.0
var font: Font = FONT_REGULAR

func _ready() -> void:
	add_child(feedback)
	if save_enabled:
		feedback.load_settings()
		ui_state.load_state()
		if FileAccess.file_exists(Profile.SAVE_PATH):
			if profile.load_from():
				has_save = true
			else:
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
	# Tests instantiate with save_enabled = false and expect to start in the hub.
	if save_enabled:
		title = true

func persist() -> void:
	if save_enabled:
		profile.save_to()

func refresh_stats() -> void:
	var stats: Dictionary = profile.stats()
	max_hp = stats.health
	damage = stats.attack
	armor = stats.armor
	attack_interval = profile.combat_stats().interval
	max_mana = stats.mana
	mana_regen = stats.regen
	mana = minf(mana, max_mana)

func _unhandled_input(event: InputEvent) -> void:
	if title:
		if not panel.is_empty():
			# Only the settings panel can open over the title screen.
			if event is InputEventKey and event.pressed and not event.echo:
				if event.keycode == KEY_ESCAPE or event.keycode == KEY_F10:
					close_panel()
					return
			if event is InputEventMouseButton and event.pressed:
				panel_mouse(event.position, event.button_index, event.shift_pressed)
			return
		title_input(event)
		return
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
			elif paused and pause_view == "controls":
				pause_view = "menu"
			else:
				paused = not paused
				pause_view = "menu"
			return
		if event.keycode == KEY_F10:
			toggle_settings()
			return
		if panel == "settings":
			return
		if paused:
			pause_key(event)
			return
		if event.keycode == KEY_L:
			cycle_loot_mode()
			return
		if event.keycode == KEY_F and panel in ["inventory", "stash"]:
			toggle_favorite(get_global_mouse_position())
			return
		if event.keycode == KEY_B and (hub or training):
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
		if training and event.keycode == KEY_R:
			training_time = 0.0
			training_total = 0.0
			training_burn = 0.0
			training_hits = 0
			return
		if event.keycode >= KEY_1 and event.keycode <= KEY_4:
			cast_ability(event.keycode - KEY_1)
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
	if event is InputEventMouseButton and event.pressed and paused and panel.is_empty() and celebration.is_empty():
		pause_mouse(event.position, event.button_index)
		return
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
	var values := [Loc.t("%d%% / CLICK +20%%") % roundi(feedback.volume * 100), Loc.t("ON") if feedback.shake_enabled else Loc.t("OFF"), Loc.t("ON") if feedback.hitstop_enabled else Loc.t("OFF"), Loc.t("ON") if feedback.flash_enabled else Loc.t("OFF")]
	for i in range(4):
		label_at(Vector2(160, 267 + i * 68), titles[i], 20, PALE)
		ui_button(settings_rect(i), values[i], true)
	label_at(Vector2(160, 550), "Heavy impacts only. Aim and HUD stay steady. No full-screen flashes.", 16, MUTED)
	label_at(Vector2(160, 584), settings_message if feedback.settings_writable else "Unreadable preferences preserved; changes apply for this session.", 14, GOLD)

func interact_hub() -> void:
	if not hub or not panel.is_empty():
		return
	if player.distance_to(TRAINING_POS) <= 110:
		enter_training()
	elif player.distance_to(STASH_POS) <= 110:
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
		if button == MOUSE_BUTTON_LEFT or button == MOUSE_BUTTON_RIGHT:
			build_click(mouse, button)
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
	if button == MOUSE_BUTTON_RIGHT and (hub or training):
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
	if not (hub or training):
		return
	if profile.equip(index):
		refresh_stats()
		hp = max_hp
		message = "Equipment updated. Your new stats apply immediately."
		persist()

func enter_map(index: int, as_abyss: bool = false) -> bool:
	if not hub or index < 0 or index >= MAPS.size() or index >= profile.unlocked:
		return false
	if as_abyss and profile.campaign < 9:
		return false
	training = false
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
	var template := layout_template if layout_template >= 0 else randi() % layout.template_count()
	var mirror := (layout_flip == 1) if layout_flip >= 0 else randf() < 0.5
	layout.build(index, mission % 3, template, mirror)
	trial.position = layout.cache
	shrine.position = layout.shrine_point
	seal_guards.assign([0, 0])
	potions = 3
	return_time = 0
	attack_cooldown = 0.25
	dash_time = 0
	dash_cooldown = 0
	invincible = 0
	slash = 0
	player = layout.arrival
	refresh_stats()
	hp = max_hp
	enemies.clear()
	drops.clear()
	particles.clear()
	projectiles.clear()
	notices.clear()
	reset_abilities()
	var pack_count := 10 + (mission % 3) * 2 + (2 if abyss else 0)
	for pack in range(pack_count):
		var seal := -1
		var base: Vector2
		if pack < 6:
			seal = pack % 2
			base = layout.seal_centers[seal]
		else:
			base = layout.optional_centers[pack % layout.optional_centers.size()]
		var offset := Vector2.RIGHT.rotated(TAU * (pack % 6) / 6.0) * randf_range(80, 150)
		for unit in range(5 + index):
			spawn_enemy(base + offset + Vector2(randf_range(-45, 45), randf_range(-45, 45)))
			enemies[-1].seal_guard = seal
			if seal >= 0:
				seal_guards[seal] += 1
	seal_required = seal_guards[0] + seal_guards[1]
	spawn_enemy(layout.boss_point, true)
	update_camera()
	message = Loc.t("MAIN ROUTE / Break two guarded seals, then hunt %s. Purple vault: optional loot.") % MAPS[index].boss
	area_banner = Loc.t(MAPS[index].name)
	area_banner_time = 3.0
	return true

func enter_abyss() -> bool:
	if not hub or panel != "gate" or player.distance_to(GATE_POS) > 110 or profile.campaign < 9:
		return false
	return enter_map(2, true)

func enter_training() -> bool:
	if not hub or not panel.is_empty():
		return false
	training = true
	hub = false
	abyss = false
	map_index = 0
	mission = 0
	heat = 0
	cleave_chain = 0
	wave_flash = 0
	pull_flash = 0
	hazards.clear()
	boss_stones.clear()
	celebration = ""
	feedback.reset()
	panel = ""
	attack_blocked = true
	ended = false
	paused = false
	map_cleared = false
	training_time = 0.0
	training_total = 0.0
	training_burn = 0.0
	training_hits = 0
	potions = 3
	return_time = 0
	attack_cooldown = 0.25
	dash_time = 0
	dash_cooldown = 0
	invincible = 0
	slash = 0
	refresh_stats()
	hp = max_hp
	enemies.clear()
	drops.clear()
	particles.clear()
	projectiles.clear()
	notices.clear()
	reset_abilities()
	layout.build(0, 0)
	player = layout.arrival
	if build_tab == 3:
		build_tab = 0
	spawn_dummy(Vector2(780, 750))
	for i in range(5):
		spawn_dummy(Vector2(1180 + (i % 3) * 74, 700 + (i / 3) * 96))
	update_camera()
	message = "TRAINING GROUND / Attack the posts. B: change your build. R: reset the meter. T: return to town."
	area_banner = Loc.t("TRAINING GROUND")
	area_banner_time = 3.0
	return true

func spawn_dummy(pos: Vector2) -> void:
	next_enemy_id += 1
	enemies.append({"pos": layout.safe_position(pos, 22), "eid": next_enemy_id, "hp": 1000000.0, "max_hp": 1000000.0, "radius": 22.0, "speed": 0.0, "damage": 0.0, "flash": 0.0, "brute": false, "aggro": false, "kind": 0, "skill_cd": 999.0, "elite_mod": -1, "burn_time": 0.0, "burn_dps": 0.0, "slow_time": 0.0, "slow_factor": 1.0, "dummy": true})

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
	next_enemy_id += 1
	enemies.append({"pos": pos, "eid": next_enemy_id, "hp": health, "max_hp": health, "radius": 32.0 if boss else (21.0 if kind == 2 else 16.0), "speed": speed, "damage": hit, "flash": 0.0, "brute": boss, "aggro": false, "kind": kind, "skill_cd": randf_range(1.0, 2.8), "elite_mod": randi_range(0, 2) if kind == 2 else -1, "burn_time": 0.0, "burn_dps": 0.0, "slow_time": 0.0, "slow_factor": 1.0})
	if boss:
		next_boss_id += 1
		BossFight.setup(enemies[-1], next_boss_id)

func return_to_hub(defeated: bool = false) -> void:
	shrine.reset()
	feedback.reset()
	training = false
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
	message = Loc.t("%s / %d kills / %d items / %d auto-salvaged. I: inspect your loot.") % [Loc.t("Rescued: gear retained") if defeated else Loc.t("Returned to town"), kills, found, scrapped]
	area_banner = Loc.t("HUNTER'S REST")
	area_banner_time = 3.0
	enemies.clear()
	drops.clear()
	particles.clear()
	projectiles.clear()
	notices.clear()
	reset_abilities()
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
		message = Loc.t("Loot: %d collected / %d Common salvaged. I: inspect. L: pickup mode.") % [collected, recycled]
		persist()

func cycle_loot_mode() -> void:
	profile.loot_mode = (profile.loot_mode + 1) % Profile.LOOT_MODES.size()
	message = Loc.t("Loot: %s%s") % [Loc.t(Profile.LOOT_MODES[profile.loot_mode]), Loc.t(" / Common drops become embers. Magic, Rare and favorites are kept.") if profile.loot_mode == 2 else Loc.t(" / E always collects nearby gear manually.")]
	persist()

func toggle_favorite(mouse: Vector2) -> void:
	if not panel in ["inventory", "stash"]:
		return
	var hovered := hovered_item(mouse)
	if hovered.is_empty():
		return
	var item: Dictionary = hovered.item
	item.favorite = not bool(item.get("favorite", false))
	message = Loc.t("%s: %s") % [Loc.t("Protected from salvage") if item.favorite else Loc.t("Protection removed"), item.name]
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
			if not (hub or training):
				return
			var before: int = profile.embers
			var count: int = profile.salvage_common()
			change_page(false, 0)
			message = Loc.t("Salvaged %d Common items / +%d embers. Favorites are protected.") % [count, profile.embers - before]
			persist()

func interact_field() -> void:
	if hub or ended or paused or not panel.is_empty():
		return
	pickup_nearby()
	if training:
		return
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
	mastery_message = Loc.t("CURSED CACHE CLEARED / RARE %s DELIVERED") % Loc.t(trial.reward_slot.to_upper())
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
	if title:
		# Keep the title backdrop alive without simulating the world. Advancing the
		# feedback clock lets menu clicks play more than once.
		town_clock += delta
		feedback.advance(delta)
		queue_redraw()
		return
	message_time = maxf(0, message_time - delta)
	area_banner_time = maxf(0, area_banner_time - delta)
	if message != last_message:
		# Any new status message becomes a short-lived toast instead of a permanent line.
		last_message = message
		message_time = 7.0
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
	var next := (player + movement * 245 * profile.move_speed_multiplier() * delta).clamp(HUB_BOUNDS.position + Vector2.ONE * 18, HUB_BOUNDS.end - Vector2.ONE * 18)
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
	if training:
		training_time += delta
	step_abilities(delta)
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
		dash_cooldown = 1.1 * profile.dash_cooldown_multiplier()
		invincible = 0.23
	if dash_time > 0:
		player = layout.move_body(player, dash_direction * 820 * delta, 18)
		burst(player, MINT, 2)
	else:
		player = layout.move_body(player, movement * 245 * action_move_multiplier() * delta, 18)
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
	step_projectiles(delta)
	if not celebration.is_empty():
		return
	for enemy in enemies:
		if enemy.get("dummy", false):
			enemy.flash = maxf(0, enemy.flash - delta)
			continue
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
	var hit := maxf(1, amount * shrine.multiplier("incoming") * profile.incoming_multiplier() * 100.0 / (100.0 + armor * 5))
	invincible = 0.65
	return_time = 0
	if shield > 0:
		var absorbed := minf(shield, hit)
		shield -= absorbed
		hit -= absorbed
		feedback.heavy(player, Color("91caff"), 1.5)
		burst(player, Color("91caff"), 8)
		notices.append({"pos": player - Vector2(0, 30), "text": "-%d" % int(absorbed), "life": 0.7, "color": Color("91caff")})
		if hit <= 0:
			return
	hp = maxf(0, hp - hit)
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
	if training and enemy.get("dummy", false):
		training_total += amount
		training_hits += 1
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
				var burn_amount: float = enemy.burn_dps * elapsed * (BossFight.multiplier(self, enemy) if enemy.brute else 1.0)
				enemy.hp -= burn_amount
				if training and enemy.get("dummy", false):
					training_burn += burn_amount
					training_total += burn_amount
				if enemy.hp <= 0:
					defeat_enemy(i)

func apply_attack_hit(index: int, amount: float, scorch: float, frost: float, burn: float = 0.0) -> bool:
	var enemy: Dictionary = enemies[index]
	if enemy.brute and seal_required > 0:
		return false
	var burn_factor := maxf(scorch, burn)
	if burn_factor > 0:
		var burning := amount * 0.2 * burn_factor
		enemy.burn_dps = maxf(enemy.burn_dps, burning) if enemy.burn_time > 0 else burning
		enemy.burn_time = 2.0
	if frost > 0:
		enemy.slow_time = 1.5
		enemy.slow_factor = pow(0.85, frost)
	return hit_enemy(index, amount)

func attack_damage_at(offset: Vector2, radius: float, combat: Dictionary, wave_ready: bool, fork: bool, skill_index: int) -> float:
	if not layout.segment_clear(player, player + offset):
		return 0.0
	var hit := 0.0
	if offset.length() <= combat.reach + radius:
		if skill_index == 1 or (skill_index == 0 and (offset.length() <= 28 or facing.dot(offset.normalized()) >= 0.25)):
			hit = combat.damage
		elif skill_index == 2:
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
	perform_attack(0, true)

func perform_attack(slot: int, lock_attack: bool) -> void:
	var skill_index := Skills.index_of(profile.slot_skill_id(slot))
	if skill_index < 0:
		return
	feedback.play(["cleave", "nova", "lance", "lance"][skill_index])
	var combat: Dictionary = slot_combat(slot)
	if lock_attack:
		attack_cooldown = action_interval(combat)
	slash = 0.16
	slash_skill = skill_index
	slash_angle = facing.angle()
	if skill_index == 3:
		fire_projectiles(combat)
		return
	var landed := false
	var wave: bool = skill_index == 0 and profile.has_relic("cleave_wave")
	var fork: bool = skill_index == 2 and profile.has_relic("lance_fork")
	var pull: bool = skill_index == 1 and profile.has_relic("nova_pull")
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
		var hit := attack_damage_at(offset, enemy.radius, combat, wave_ready, fork, skill_index)
		if hit > 0:
			landed = apply_attack_hit(i, hit, scorch, frost, combat.burn) or landed
	for i in range(boss_stones.size() - 1, -1, -1):
		var hit := attack_damage_at(boss_stones[i].pos - player, 22, combat, wave_ready, fork, skill_index)
		if hit > 0:
			hit_stone(i, hit)
			landed = true
	if landed:
		heat = minf(100, heat + heat_per_hit())
		if wave:
			cleave_chain = (cleave_chain + 1) % 3
			if wave_ready:
				wave_flash = 0.18
		if combat.leech > 0:
			hp = minf(max_hp, hp + max_hp * combat.leech)

func fire_projectiles(combat: Dictionary) -> void:
	cleave_chain = 0
	var count := 1 + int(combat.projectiles)
	for i in range(count):
		var offset := (i - (count - 1) / 2.0) * 9.0
		var direction := facing.rotated(deg_to_rad(offset))
		projectiles.append({
			"pos": player + direction * 22,
			"dir": direction,
			"speed": 640.0,
			"damage": combat.damage,
			"pierce": int(combat.pierce),
			"chain": int(combat.chain),
			"burn": combat.burn,
			"leech": combat.leech,
			"life": 0.75,
			"hit": []
		})

func enemy_index(eid: int) -> int:
	for i in range(enemies.size()):
		if enemies[i].eid == eid:
			return i
	return -1

func step_projectiles(delta: float) -> void:
	for i in range(projectiles.size() - 1, -1, -1):
		var bolt: Dictionary = projectiles[i]
		var next: Vector2 = bolt.pos + bolt.dir * bolt.speed * delta
		if not layout.segment_clear(bolt.pos, next):
			burst(next, Color("ff9864"), 6)
			projectiles.remove_at(i)
			continue
		bolt.pos = next
		bolt.life -= delta
		var struck := false
		for j in range(enemies.size() - 1, -1, -1):
			var enemy: Dictionary = enemies[j]
			if enemy.eid in bolt.hit:
				continue
			if bolt.pos.distance_to(enemy.pos) <= enemy.radius + 9 and layout.segment_clear(bolt.pos, enemy.pos):
				bolt.hit.append(enemy.eid)
				struck = true
				apply_bolt_hit(enemy, bolt)
				break
		if bolt.life <= 0 or (struck and int(bolt.pierce) <= 0):
			projectiles.remove_at(i)
		elif struck:
			bolt.pierce = int(bolt.pierce) - 1

func apply_bolt_hit(enemy: Dictionary, bolt: Dictionary) -> void:
	var scorch: float = profile.effect_count("scorch")
	var frost: float = profile.effect_count("frost")
	var burning: float = bolt.damage * 0.2 * maxf(scorch, float(bolt.burn))
	if burning > 0:
		enemy.burn_dps = maxf(enemy.burn_dps, burning) if enemy.burn_time > 0 else burning
		enemy.burn_time = 2.0
	if frost > 0:
		enemy.slow_time = 1.5
		enemy.slow_factor = pow(0.85, frost)
	var target: Vector2 = enemy.pos
	var index := enemy_index(int(enemy.eid))
	if index >= 0:
		hit_enemy(index, bolt.damage)
	if int(bolt.chain) > 0:
		chain_from(target, bolt)
	if bolt.leech > 0:
		hp = minf(max_hp, hp + max_hp * float(bolt.leech))
	heat = minf(100, heat + heat_per_hit())

func chain_from(origin: Vector2, bolt: Dictionary) -> void:
	var remaining := int(bolt.chain)
	var current := origin
	var hit_ids: Array = bolt.hit.duplicate()
	while remaining > 0:
		var best := -1
		var best_distance := 170.0
		for i in range(enemies.size()):
			var enemy: Dictionary = enemies[i]
			if enemy.eid in hit_ids:
				continue
			var distance: float = current.distance_to(enemy.pos)
			if distance < best_distance and layout.segment_clear(current, enemy.pos):
				best_distance = distance
				best = i
		if best < 0:
			return
		var target: Dictionary = enemies[best]
		hit_ids.append(target.eid)
		var target_pos: Vector2 = target.pos
		hit_enemy(best, bolt.damage * 0.75)
		current = target_pos
		remaining -= 1

func slot_combat(slot: int) -> Dictionary:
	var combat: Dictionary = profile.slot_combat(slot)
	combat.damage *= shrine.multiplier("attack")
	return combat

func cast_ability(key: int) -> bool:
	var id: String = profile.active_skill(key)
	if id.is_empty() or hub or ended or paused or not panel.is_empty() or not celebration.is_empty():
		return false
	if not profile.ability_unlocked(key) or ability_cd[key] > 0:
		return false
	var definition: Dictionary = Skills.def(id)
	var skill_index := Skills.index_of(id)
	if definition.is_empty() or skill_index < 0:
		return false
	var cost := float(definition.get("cost", 0))
	if mana < cost:
		message = Loc.t("Not enough mana.")
		return false
	ability_cd[key] = float(definition.cooldown)
	mana -= cost
	return_time = 0
	if Skills.is_attack(skill_index):
		perform_attack(key + 1, false)
		return true
	var combat: Dictionary = slot_combat(key + 1)
	match id:
		"ember_lance":
			feedback.play("lance")
			cast_lance(definition, combat)
		"cinder_field":
			feedback.play("nova")
			cast_field(definition, combat)
		"barrier":
			feedback.play("loot")
			shield = max_hp * float(definition.shield)
			shield_time = float(definition.duration)
			burst(player, MINT, 24)
		"rush":
			feedback.play("burst")
			rush_time = float(definition.duration)
			rush_haste = float(definition.haste)
			rush_move = float(definition.move)
			burst(player, GOLD, 20)
	return true

func cast_lance(definition: Dictionary, combat: Dictionary) -> void:
	var count := 1 + int(combat.projectiles)
	for i in range(count):
		var offset := (i - (count - 1) / 2.0) * 9.0
		var direction := facing.rotated(deg_to_rad(offset))
		projectiles.append({
			"pos": player + direction * 22,
			"dir": direction,
			"speed": float(definition.speed),
			"damage": float(combat.damage),
			"pierce": int(definition.pierce) + int(combat.pierce),
			"chain": int(combat.chain),
			"burn": maxf(float(definition.burn), float(combat.burn)),
			"leech": float(combat.leech),
			"life": float(definition.range) / float(definition.speed),
			"hit": [],
			"big": true
		})

func cast_field(definition: Dictionary, combat: Dictionary) -> void:
	var target: Vector2 = get_global_mouse_position() - VIEW.position + camera
	var offset: Vector2 = target - player
	if offset.length() > float(definition.range):
		target = player + offset.normalized() * float(definition.range)
	var center: Vector2 = layout.safe_position(target, 12)
	var radius := float(definition.radius) * float(combat.area)
	zones.append({
		"pos": center,
		"radius": radius,
		"life": float(definition.duration),
		"tick": 0.0,
		"interval": float(definition.tick),
		"damage": float(combat.damage),
		"burn": maxf(float(definition.burn), float(combat.burn)),
		"slow": float(definition.slow)
	})
	for i in range(enemies.size() - 1, -1, -1):
		if center.distance_to(enemies[i].pos) <= radius + enemies[i].radius and layout.segment_clear(center, enemies[i].pos):
			hit_enemy(i, float(combat.damage))

func step_abilities(delta: float) -> void:
	mana = minf(max_mana, mana + mana_regen * delta)
	shield_time = maxf(0, shield_time - delta)
	if shield_time <= 0:
		shield = 0.0
	rush_time = maxf(0, rush_time - delta)
	for i in range(ability_cd.size()):
		ability_cd[i] = maxf(0, ability_cd[i] - delta)
	step_zones(delta)

func step_zones(delta: float) -> void:
	for i in range(zones.size() - 1, -1, -1):
		var zone: Dictionary = zones[i]
		zone.life -= delta
		zone.tick -= delta
		if zone.tick <= 0:
			zone.tick = float(zone.interval)
			for j in range(enemies.size() - 1, -1, -1):
				var enemy: Dictionary = enemies[j]
				if enemy.brute and seal_required > 0:
					continue
				if zone.pos.distance_to(enemy.pos) <= float(zone.radius) + enemy.radius and layout.segment_clear(zone.pos, enemy.pos):
					enemy.slow_time = maxf(enemy.slow_time, 0.6)
					enemy.slow_factor = minf(enemy.slow_factor, 1.0 - float(zone.slow))
					if float(zone.burn) > 0:
						var burning: float = float(zone.damage) * 0.2 * float(zone.burn)
						enemy.burn_dps = maxf(enemy.burn_dps, burning) if enemy.burn_time > 0 else burning
						enemy.burn_time = 2.0
					hit_enemy(j, float(zone.damage))
		if zone.life <= 0:
			zones.remove_at(i)

func action_interval(combat: Dictionary) -> float:
	return float(combat.interval) / (1.0 + (rush_haste if rush_time > 0.0 else 0.0))

func action_move_multiplier() -> float:
	return profile.move_speed_multiplier() * (1.0 + (rush_move if rush_time > 0.0 else 0.0))

func reset_abilities() -> void:
	zones.clear()
	shield = 0.0
	shield_time = 0.0
	rush_time = 0.0
	rush_haste = 0.0
	rush_move = 0.0
	mana = max_mana
	for i in range(ability_cd.size()):
		ability_cd[i] = 0.0

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
			message = Loc.t("SEAL %s BROKEN / Follow the main route.") % ("I" if guard_seal == 0 else "II")
			feedback.play("loot")
	var old_level: int = profile.level
	var experience: int = (30 if enemy.brute else 8) * (map_index + 1)
	profile.gain_xp(experience)
	var trained: Array[String] = profile.gain_mastery(experience)
	if not trained.is_empty():
		mastery_message = Loc.t("MASTERY UP") + " / " + " + ".join(trained)
		mastery_time = 4.0
		burst(player, MINT, 24)
	refresh_stats()
	if profile.level > old_level:
		hp = minf(max_hp, hp + 20)
		message = Loc.t("Level %d! Permanent base stats increased.") % profile.level
	if enemy.brute or enemy.kind == 2 or kills == 1 or randf() < 0.45:
		var loot: Dictionary = profile.roll_item(loot_tier(), enemy.brute)
		if enemy.kind == 2 and loot.rarity == 0:
			loot = profile.roll_item(loot_tier(), true)
		drops.append({"pos": enemy.pos, "item": loot})
	if enemy.elite_mod == 0:
		add_hazard(enemy.pos, 105, enemy.damage * 1.8, 1.1)
	if enemy.brute and profile.record_relic_hunt(map_index, loot_tier()):
		feedback.play("relic")
		mastery_message = Loc.t("RELIC FOUND") + " / " + Effects.RELICS[map_index].name
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
	draw_string(font, pos, Loc.t(value), HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func centered_label(y: float, source: String, size: int, color: Color = PALE) -> void:
	var text := Loc.t(source)
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, Vector2((1152 - width) / 2, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func bar(rect: Rect2, ratio: float, color: Color) -> void:
	draw_rect(rect, Color("263346"))
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * clampf(ratio, 0, 1), rect.size.y)), color)

func rarity_color(item: Dictionary) -> Color:
	return [PALE, Color("82b5ff"), GOLD, Color("ff9864")][int(item.rarity)]

func item_stats(item: Dictionary) -> String:
	if item.is_empty():
		return "Empty slot"
	var stats := Mods.totals(item)
	return Loc.t("ATK %d   HP %d   DEF %d   SPD %d%%") % [stats.attack, stats.health, stats.armor, stats.haste]

func map_rect(index: int) -> Rect2:
	return Rect2(144 + index * 292, 280, 276, 170)

func _draw() -> void:
	draw_rect(Rect2(0, 0, 1152, 720), Color("0b101a"))
	if title:
		draw_title()
		if not panel.is_empty():
			draw_panel()
		return
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
		draw_pause()

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
	# Training post.
	var post := TRAINING_POS
	draw_circle(post + Vector2(0, 16), 26, Color(0, 0, 0, 0.24))
	draw_rect(Rect2(post - Vector2(12, 26), Vector2(24, 52)), Color("7a5a3a"))
	draw_rect(Rect2(post - Vector2(12, 26), Vector2(24, 52)), Color("b38855"), false, 3)
	draw_line(post + Vector2(-17, -26), post + Vector2(17, -26), Color("b38855"), 4)
	draw_line(post + Vector2(-17, -8), post + Vector2(17, -8), Color("b38855"), 4)
	label_at(post + Vector2(-42, -46), "TRAINING", 14, MINT)
	draw_player()
	if panel.is_empty():
		if player.distance_to(TRAINING_POS) <= 110:
			label_at(post + Vector2(-70, 62), "[E] TRAINING GROUND", 16, MINT)
		elif player.distance_to(STASH_POS) <= 110:
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
			label_at(rect.position + Vector2(16, 30), Loc.t("CHAPTER %d / CLEARED %d OF 3") % [i + 1, clampi(profile.campaign - i * 3, 0, 3)], 13, MUTED)
			label_at(rect.position + Vector2(16, 64), MAPS[i].name, 18, PALE if available else MUTED)
			label_at(rect.position + Vector2(16, 98), MAPS[i].boss, 15, GOLD)
			label_at(rect.position + Vector2(16, 119), Loc.t("RELIC %d/3: %s") % [profile.relic_hunts[i], ["CLEAVE WAVE", "NOVA PULL", "LANCE FORK"][i]] if profile.campaign >= (i + 1) * 3 else "FIRST CHAPTER CLEAR: RELIC", 11, Color("ff9864"))
			label_at(rect.position + Vector2(16, 143), Loc.t("TRAVEL / CLICK OR %d") % (i + 1) if available else "LOCKED / CLEAR PREVIOUS MAP", 13, MINT if available else MUTED)
		ui_button(Rect2(144, 473, 350, 48), "[4] ABYSS / DEPTH %d" % (profile.depth if selected_depth == 0 else selected_depth) if profile.campaign == 9 else "ABYSS / COMPLETE CHAPTER 3", profile.campaign == 9)
		ui_button(Rect2(520, 473, 480, 48), CONTRACTS[contract], true)
		label_at(Vector2(144, 548), "Abyss contracts: extra item tier and double guardian embers. Click to cycle.", 14, MUTED)
		label_at(Vector2(144, 574), "Esc / E to close   |   B: build & forge in town", 15, MUTED)
		return
	label_at(Vector2(144, 179), "STASH & INVENTORY" if panel == "stash" else "INVENTORY", 23, GOLD)
	ui_button(inventory_action_rect(0), Loc.t("[L] %s") % Loc.t(Profile.LOOT_MODES[profile.loot_mode]), profile.loot_mode > 0)
	ui_button(inventory_action_rect(1), "SORT")
	ui_button(inventory_action_rect(2), Loc.t("SCRAP COMMON (%d)") % profile.common_salvage_count() if (hub or training) else "SCRAP IN TOWN", (hub or training) and profile.common_salvage_count() > 0)
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
		label_at(Vector2(612, 269), Loc.t("CHARACTER / LEVEL %d") % profile.level, 20, MINT)
		label_at(Vector2(612, 316), Loc.t("Skill hit           %.1f") % expedition_combat().damage, 18)
		label_at(Vector2(612, 350), Loc.t("Maximum health      %d") % max_hp, 18)
		label_at(Vector2(612, 384), Loc.t("Defense             %d") % armor, 18)
		label_at(Vector2(612, 418), Loc.t("Attack interval     %.2fs") % attack_interval, 18)
		label_at(Vector2(612, 452), Loc.t("BURN %.0f%%/s / SLOW %.1f%% / HEAT +%.0f") % [profile.effect_count("scorch") * 20, (1.0 - pow(0.85, profile.effect_count("frost"))) * 100, profile.effect_count("charge") * 4], 12, Color("ff9864"))
		if not hub and shrine.choice >= 0:
			label_at(Vector2(612, 514), Shrine.OFFERS[shrine.choice].name, 14, GOLD)
			label_at(Vector2(612, 540), Shrine.OFFERS[shrine.choice].benefit, 13, MINT)
			label_at(Vector2(612, 562), Shrine.OFFERS[shrine.choice].cost, 13, RED)
		label_at(Vector2(612, 480), Loc.t("Embers: %d / B: build & forge") % profile.embers, 15, MUTED)
	label_at(Vector2(144, 598), "Hover: compare / Click: equip / Right-click: salvage / F or middle-click: protect / I: close" if (hub or training) else "Hover: compare / F or middle-click: protect / Equip & salvage in town / I: close", 14, MUTED)
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
	label_at(origin, Loc.t("%d ITEMS / %d") % [items.size(), current_page + 1], 12, MUTED)
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
	label_at(p + Vector2(0, 26), Loc.t("%s / %s / TIER %d") % [Profile.RARITIES[int(item.rarity)], item.slot.to_upper(), item.tier], 13, MUTED)
	draw_line(p + Vector2(0, 41), p + Vector2(316, 41), Color("304052"))
	var current: Dictionary = profile.equipment[item.slot]
	var keys := ["attack", "health", "armor", "haste"]
	var names := ["Attack damage", "Maximum health", "Defense", "Attack speed %"]
	for i in range(4):
		var key: String = keys[i]
		var delta := int(Mods.totals(item)[key]) - int(Mods.totals(current)[key])
		label_at(p + Vector2(0, 67 + i * 26), Loc.t("%s: %d") % [Loc.t(names[i]), item[key]], 16)
		if not equipped:
			label_at(p + Vector2(261, 67 + i * 26), "%+d" % delta, 16, MINT if delta > 0 else (RED if delta < 0 else MUTED))
	label_at(p + Vector2(0, 178), Loc.t("Rune: %s / Forge +%d") % [Profile.STANCES[int(item.rune)] + " +12%" if int(item.get("rune", -1)) >= 0 else Loc.t("None"), int(item.get("upgrade", 0))], 12, MUTED)
	var effect_text := "No special effect"
	var detail_text := "Magic and Rare gear can carry combat effects."
	if item.has("relic"):
		var definition: Dictionary = Effects.RELICS[Effects.relic_index(item.relic)]
		effect_text = definition.effect
		detail_text = definition.detail
	elif item.has("affix"):
		effect_text = Loc.t("%s / normal attacks") % Loc.t(Effects.AFFIXES[item.affix].name)
		detail_text = Effects.AFFIXES[item.affix].text
	label_at(p + Vector2(0, 204), effect_text, 13, Color("ff9864"))
	label_at(p + Vector2(0, 228), detail_text, 12, PALE)
	label_at(p + Vector2(0, 252), Loc.t("Boss source: chapter %d / first clear or every 3 repeat kills") % (Effects.relic_index(item.relic) + 1) if item.has("relic") else "Matching affixes stack across equipped slots.", 11, MUTED)
	label_at(p + Vector2(0, 278), "PROTECTED / Cannot be salvaged" if item.get("favorite", false) else "F / middle-click: protect from salvage", 12, MINT)
	var hint := "Equipped"
	if not equipped:
		hint = "Click to take out" if storage else ("Click to equip" if (hub or training) else "Equip after returning to town")
		if panel == "stash" and not storage:
			hint += Loc.t(" / Shift-click to store")
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
		if training:
			break
		var seal_color := MINT if seal_guards[i] == 0 else GOLD
		draw_arc(layout.seals[i], 46, 0, TAU, 32, seal_color, 3, true)
		var seal_state := Loc.t("BROKEN") if seal_guards[i] == 0 else Loc.t("%d GUARDS") % seal_guards[i]
		label_at(layout.seals[i] + Vector2(-65, 65), Loc.t("SEAL %s / %s") % ["I" if i == 0 else "II", seal_state], 13, seal_color)
	draw_arc(layout.arrival, 48, 0, TAU, 40, MINT, 3, true)
	label_at(layout.arrival + Vector2(-64, 69), "T / TOWN PORTAL", 14, MINT)
	draw_arc(layout.boss_point, 130, 0, TAU, 50, GOLD.darkened(0.5), 2, true)
	if not training:
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
		if enemy.get("dummy", false):
			draw_dummy(enemy.pos)
			continue
		draw_enemy(enemy)
		if enemy.brute:
			label_at(enemy.pos - Vector2(65, 49), MAPS[map_index].boss, 17, GOLD)
	for particle in particles:
		var color: Color = particle.color
		color.a = minf(1, particle.life * 4)
		draw_circle(particle.pos, 2.5, color)
	for zone in zones:
		draw_circle(zone.pos, float(zone.radius), Color(1.0, 0.45, 0.2, 0.13))
		draw_arc(zone.pos, float(zone.radius), 0, TAU, 48, Color("ff9864"), 2, true)
	for bolt in projectiles:
		var big: bool = bolt.get("big", false)
		draw_line(bolt.pos - bolt.dir * (34.0 if big else 16.0), bolt.pos, Color("ff9864"), 8 if big else 4, true)
		draw_circle(bolt.pos, 16.0 if big else 9.0, Color(1, 0.6, 0.3, 0.22))
		draw_circle(bolt.pos, 8.0 if big else 4.5, GOLD)
	draw_player()
	if shield_time > 0 and shield > 0:
		draw_arc(player, 26, 0, TAU, 40, Color("91caff"), 3, true)
	if slash > 0:
		var color := Color(0.44, 0.94, 0.82, slash / 0.16)
		var reach: float = profile.combat_stats(slash_skill).reach
		if slash_skill == 2:
			draw_line(player, layout.move_body(player, Vector2.RIGHT.rotated(slash_angle) * reach, 1, false), color, 16, true)
		elif slash_skill != 3:
			draw_visible_arc(reach, 0 if slash_skill == 1 else slash_angle - 1.2, TAU if slash_skill == 1 else slash_angle + 1.2, color, 7)
	for ring in feedback.rings:
		var ring_color: Color = ring.color
		ring_color.a = ring.life / 0.25 * 0.5
		draw_arc(ring.pos, 20 + (1.0 - ring.life / 0.25) * 65, 0, TAU, 32, ring_color, 2, true)
	if wave_flash > 0:
		draw_line(player, layout.move_body(player, Vector2.RIGHT.rotated(slash_angle) * 300, 1, false), Color("ff9864"), 18 * wave_flash / 0.18, true)
	if pull_flash > 0:
		draw_visible_arc(250 * pull_flash / 0.18, 0, TAU, Color("ad9cff"), 3)
	if slash > 0 and slash_skill == 2 and profile.has_relic("lance_fork"):
		for angle in [-22.0, 22.0]:
			draw_line(player, layout.move_body(player, Vector2.RIGHT.rotated(slash_angle + deg_to_rad(angle)) * profile.combat_stats(slash_skill).reach, 1, false), Color("ff9864"), 5, true)
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
	if not training:
		for i in range(2):
			draw_arc(mini_rect.position + layout.seals[i] / WORLD.size * mini_rect.size, 4, 0, TAU, 12, MINT if seal_guards[i] == 0 else GOLD, 1.5)
	for enemy in enemies:
		draw_circle(mini_rect.position + enemy.pos / WORLD.size * mini_rect.size, 4 if enemy.brute else 2, GOLD if enemy.brute else (MINT if enemy.get("dummy", false) else RED))
	if not training and trial.state != ExpeditionEvent.State.COMPLETE:
		draw_rect(Rect2(mini_rect.position + trial.position / WORLD.size * mini_rect.size - Vector2(3, 3), Vector2(6, 6)), Color("ad9cff"))
	var shrine_dot: Vector2 = mini_rect.position + shrine.position / WORLD.size * mini_rect.size
	draw_colored_polygon(PackedVector2Array([shrine_dot + Vector2(0, -4), shrine_dot + Vector2(4, 0), shrine_dot + Vector2(0, 4), shrine_dot + Vector2(-4, 0)]), GOLD if shrine_available() else MUTED)
	draw_circle(mini_rect.position + player / WORLD.size * mini_rect.size, 3, MINT)
	if not training and trial.state == ExpeditionEvent.State.ACTIVE:
		label_at(Vector2(948, 244), Loc.t("CACHE / %d GUARDS") % trial.remaining, 12, Color("ad9cff"))
	for enemy in enemies:
		if enemy.brute and enemy.aggro and seal_required == 0:
			label_at(Vector2(475, 133), "%s / %d%%" % [MAPS[map_index].boss, int(enemy.hp / enemy.max_hp * 100)], 14, GOLD)
			bar(Rect2(475, 142, 330, 6), enemy.hp / enemy.max_hp, RED)
			label_at(Vector2(475, 168), enemy.move_name, 12, MINT if enemy.state == "recovery" else GOLD)
			label_at(Vector2(475, 189), "WARD: 30% LESS DAMAGE" if BossFight.stone_count(self, enemy) > 0 else ("EXPOSED: +35% DAMAGE" if enemy.weak_time > 0 else Loc.t("PHASE %d") % enemy.phase), 11, MUTED)
			break

func objective_text() -> String:
	if hub:
		return Loc.t("GOAL: check your build with B, then travel at the gate")
	if training:
		return Loc.t("TRAINING GROUND / Attack the posts (R: reset)")
	if map_cleared:
		return Loc.t("GOAL: collect loot and return with T")
	if seal_required > 0:
		return Loc.t("GOAL: break the seals / %d guards left") % seal_required
	return Loc.t("GOAL: defeat the guardian")

func draw_hud() -> void:
	# Vitals (top-left): health, heat, level and active pacts only.
	label_at(Vector2(28, 28), Loc.t("VITALITY %d / %d") % [hp, max_hp], 13)
	bar(Rect2(28, 36, 300, 12), hp / max_hp, RED)
	bar(Rect2(28, 52, 300, 6), heat / 100.0, MINT if heat >= 100 else Color("ff9864"))
	bar(Rect2(28, 62, 300, 8), mana / max_mana, MANA)
	label_at(Vector2(336, 28), Loc.t("LEVEL %d") % profile.level, 13, MINT)
	label_at(Vector2(336, 56), Loc.t("[F] BURST READY") if heat >= 100 else Loc.t("HEAT %d%%") % heat, 11, GOLD)
	label_at(Vector2(336, 76), Loc.t("MANA %d / %d") % [int(mana), int(max_mana)], 11, MANA)
	draw_buff_icons(Vector2(28, 82))
	# Objective tracker (top-center). Location fades in after a transition.
	centered_label(30, objective_text(), 15, GOLD)
	if area_banner_time > 0:
		centered_label(52, area_banner, 13, Color(MUTED, clampf(area_banner_time, 0.0, 1.0)))
	# Training meter.
	if training:
		label_at(Vector2(28, 100), Loc.t("TOTAL %d  /  DPS %d  /  BURN %d  /  HITS %d") % [int(training_total), int(training_total / maxf(training_time, 0.1)), int(training_burn), training_hits], 12, GOLD)
	# Status message fades out instead of occupying a permanent line.
	if message_time > 0 and panel.is_empty():
		var text := Loc.t(message)
		var alpha := clampf(message_time / 1.5, 0.0, 1.0)
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_rect(Rect2((1152 - width) / 2 - 14, 82, width + 28, 24), Color(0.02, 0.03, 0.05, 0.6 * alpha))
		draw_string(font, Vector2((1152 - width) / 2, 99), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(MINT, alpha))
	if mastery_time > 0 and panel.is_empty():
		centered_label(124, mastery_message, 15, MINT)
	# Skill bar (bottom-center) and a thin experience strip along the bottom edge.
	draw_skill_bar()
	bar(Rect2(0, 714, 1152, 6), float(profile.xp) / profile.xp_needed(), MINT)

func draw_buff_icons(pos: Vector2) -> void:
	var x := pos.x
	if not hub and not training and shrine.choice >= 0:
		draw_rect(Rect2(x, pos.y, 22, 22), Color("2a2438"))
		draw_rect(Rect2(x, pos.y, 22, 22), GOLD, false, 1)
		label_at(Vector2(x + 5, pos.y + 16), "契", 12, GOLD)
		x += 28
	if not hub and not training and profile.stance < 3 and profile.has_relic(Effects.RELICS[profile.stance].id):
		draw_rect(Rect2(x, pos.y, 22, 22), Color("2a1f24"))
		draw_rect(Rect2(x, pos.y, 22, 22), Color("ff9864"), false, 1)
		label_at(Vector2(x + 5, pos.y + 16), "遺", 12, Color("ff9864"))
		x += 28
	if heat >= 100:
		draw_rect(Rect2(x, pos.y, 22, 22), Color("1d2a24"))
		draw_rect(Rect2(x, pos.y, 22, 22), MINT, false, 1)
		label_at(Vector2(x + 5, pos.y + 16), "熱", 12, MINT)
		x += 28
	if not profile.auras.is_empty():
		draw_rect(Rect2(x, pos.y, 22, 22), Color("16233a"))
		draw_rect(Rect2(x, pos.y, 22, 22), MANA, false, 1)
		label_at(Vector2(x + 5, pos.y + 16), "霊", 12, MANA)

func ability_color(index: int) -> Color:
	return [Color("ff9864"), Color("ffc478"), Color("91caff"), MINT][index]

func centered_text(center: Vector2, text: String, size: int, color: Color) -> void:
	var translated := Loc.t(text)
	var width := font.get_string_size(translated, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, Vector2(center.x - width / 2, center.y + size / 3.0), translated, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func draw_ability_icon(center: Vector2, index: int, color: Color) -> void:
	match index:
		0:
			draw_line(center + Vector2(-10, 9), center + Vector2(10, -9), color, 4, true)
			draw_line(center + Vector2(3, -9), center + Vector2(10, -9), color, 2, true)
		1:
			draw_arc(center, 10, 0, TAU, 24, color, 2, true)
			draw_arc(center, 5, 0, TAU, 18, color, 2, true)
			draw_circle(center, 2, color)
		2:
			draw_polyline(PackedVector2Array([center + Vector2(-9, -5), center + Vector2(0, -11), center + Vector2(9, -5), center + Vector2(9, 5), center + Vector2(0, 11), center + Vector2(-9, 5), center + Vector2(-9, -5)]), color, 2, true)
		_:
			for dy in [-6.0, 2.0]:
				draw_polyline(PackedVector2Array([center + Vector2(-8, dy + 5), center + Vector2(0, dy - 3), center + Vector2(8, dy + 5)]), color, 3, true)

func skill_glyph_color(index: int) -> Color:
	return skill_color(index) if index < 4 else ability_color(index - 4)

func draw_skill_glyph(center: Vector2, index: int, color: Color) -> void:
	if index < 4:
		draw_skill_icon(center, index, color)
	else:
		draw_ability_icon(center, index - 4, color)

func draw_skill_slot(rect: Rect2, index: int, fill: float) -> void:
	draw_rect(rect, Color("101b29"))
	draw_rect(rect, skill_glyph_color(index).darkened(0.4), false, 2)
	if fill < 1.0:
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, rect.size.y * (1.0 - fill))), Color(0, 0, 0, 0.55))
	draw_skill_glyph(rect.get_center(), index, skill_glyph_color(index))

func draw_active_skill_slot(rect: Rect2, slot: int) -> void:
	var key := "%d" % (slot + 1)
	if not profile.ability_unlocked(slot):
		draw_rect(rect, Color("0d141d"))
		draw_rect(rect, Color("2a3540"), false, 2)
		label_at(rect.position + Vector2(5, 13), key, 11, Color("4a5a6b"))
		centered_text(rect.get_center() + Vector2(0, 3), Loc.t("Lv.%d") % int(Skills.SLOT_LEVELS[slot]), 13, Color("4a5a6b"))
		return
	var id: String = profile.active_skill(slot)
	if id.is_empty():
		draw_rect(rect, Color("0d141d"))
		draw_rect(rect, Color("2a3540"), false, 2)
		label_at(rect.position + Vector2(5, 13), key, 11, Color("4a5a6b"))
		centered_text(rect.get_center() + Vector2(0, 4), "-", 15, Color("4a5a6b"))
		return
	var index := Skills.index_of(id)
	var definition: Dictionary = Skills.def(id)
	var cooldown: float = ability_cd[slot]
	var cost := int(definition.get("cost", 0))
	var affordable := mana >= cost
	draw_rect(rect, Color("101b29"))
	draw_rect(rect, skill_glyph_color(index) if affordable else Color("8a4a52"), false, 2 if cooldown <= 0 else 1)
	draw_skill_glyph(rect.get_center(), index, skill_glyph_color(index) if affordable else Color("6a5a60"))
	if cooldown > 0:
		var ratio := clampf(cooldown / float(definition.cooldown), 0, 1)
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, rect.size.y * ratio)), Color(0, 0, 0, 0.6))
		centered_text(rect.get_center() + Vector2(0, 1), "%.1f" % cooldown if cooldown >= 1.0 else "%d" % int(ceil(cooldown)), 17, PALE)
	label_at(rect.position + Vector2(5, 13), key, 11, skill_glyph_color(index))
	label_at(rect.position + Vector2(rect.size.x - 22, rect.size.y - 4), "%d" % cost, 10, MANA if affordable else RED)
	label_at(rect.position + Vector2(5, rect.size.y - 4), Loc.t("Lv.%d") % profile.skill_levels[index], 9, MUTED)

func draw_skill_bar() -> void:
	var size := 46.0
	var gap := 10.0
	var total := 8 * size + 7 * gap
	var x := (1152 - total) / 2
	var y := 660.0
	draw_skill_slot(Rect2(x, y, size, size), profile.stance, 1.0)
	for slot in range(4):
		draw_active_skill_slot(Rect2(x + (slot + 1) * (size + gap), y, size, size), slot)
	var col := x + 5 * (size + gap)
	draw_action_slot(Rect2(col, y, size, size), MINT, -1, "F", heat / 100.0)
	draw_action_slot(Rect2(col + size + gap, y, size, size), Color("91caff"), -1, "Shift", 1.0 - clampf(dash_cooldown / (1.1 * profile.dash_cooldown_multiplier()), 0, 1))
	draw_action_slot(Rect2(col + 2 * (size + gap), y, size, size), RED, -1, "%d" % potions, 1.0 if potions > 0 else 0.0)
	centered_label(654, Loc.t("SUPPORTS %d / %d") % [profile.links[0].size(), profile.slot_support_capacity(0)], 11, MUTED)

func draw_action_slot(rect: Rect2, color: Color, icon: int, key: String, fill: float) -> void:
	draw_rect(rect, Color("101b29"))
	draw_rect(rect, color.darkened(0.4), false, 2)
	if fill < 1.0:
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, rect.size.y * (1.0 - fill))), Color(0, 0, 0, 0.55))
	if icon >= 0:
		draw_skill_icon(rect.get_center() - Vector2(0, 4), icon, color)
	else:
		var width := font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		label_at(rect.position + Vector2((rect.size.x - width) / 2, 27), key, 15, color)

func draw_overlay(title: String, subtitle: String) -> void:
	draw_rect(Rect2(0, 0, 1152, 720), Color(0.025, 0.04, 0.065, 0.93))
	centered_label(260, title, 32, GOLD)
	centered_label(305, subtitle, 18, MUTED)

func title_items() -> Array:
	var items: Array = []
	if has_save:
		items.append({"id": "continue", "label": "CONTINUE"})
	items.append({"id": "new", "label": "NEW GAME"})
	items.append({"id": "settings", "label": "SETTINGS"})
	items.append({"id": "quit", "label": "QUIT"})
	return items

func title_menu_rect(index: int) -> Rect2:
	return Rect2(456, 398 + index * 54, 240, 44)

func title_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if title_confirm:
			if event.keycode in [KEY_Y, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
				start_new_game()
			elif event.keycode in [KEY_N, KEY_ESCAPE]:
				title_confirm = false
			return
		var items := title_items()
		match event.keycode:
			KEY_W, KEY_UP:
				title_choice = posmod(title_choice - 1, items.size())
				feedback.play("loot")
			KEY_S, KEY_DOWN:
				title_choice = posmod(title_choice + 1, items.size())
				feedback.play("loot")
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				activate_title(items[clampi(title_choice, 0, items.size() - 1)].id)
			KEY_F10:
				toggle_settings()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var items := title_items()
		for i in range(items.size()):
			if title_menu_rect(i).has_point(event.position):
				title_choice = i
				activate_title(items[i].id)
				return

func activate_title(id: String) -> void:
	match id:
		"continue":
			start_continue()
		"new":
			if has_save:
				title_confirm = true
			else:
				start_new_game()
		"settings":
			toggle_settings()
		"quit":
			get_tree().quit()

func start_continue() -> void:
	title = false
	title_confirm = false
	panel = ""
	hub = true
	refresh_stats()
	hp = max_hp
	message = "The last flame is fading. B: choose your build. Walk to the gate and press E to begin."

func start_new_game() -> void:
	profile.reset()
	ui_state.seen_intro = false
	ui_state.shown_hints.clear()
	if save_enabled:
		ui_state.save_state()
	persist()
	has_save = true
	title_confirm = false
	title = false
	panel = ""
	hub = true
	player = HUB_SPAWN
	camera = Vector2.ZERO
	refresh_stats()
	hp = max_hp
	message = "The last flame is fading. B: choose your build. Walk to the gate and press E to begin."

func draw_title() -> void:
	draw_rect(Rect2(0, 0, 1152, 720), Color("070b12"))
	# Drifting embers over the dying fire.
	for i in range(44):
		var phase := fmod(town_clock * (0.22 + i * 0.011) + i * 0.37, 1.0)
		var x := fmod(i * 97.0 + sin(town_clock * 0.6 + i) * 24.0, 1152.0)
		var y := 720.0 - phase * 640.0
		draw_circle(Vector2(x, y), 1.5 + (1.0 - phase) * 1.5, Color(1.0, 0.6, 0.25, (1.0 - phase) * 0.5))
	var fire := Vector2(576, 700)
	draw_circle(fire, 95, Color(1, 0.5, 0.2, 0.05))
	draw_arc(fire, 38, 0, TAU, 24, Color("69717b"), 11, true)
	draw_colored_polygon(PackedVector2Array([fire + Vector2(-22, 10), fire + Vector2(0, -50 - sin(town_clock * 4) * 7), fire + Vector2(24, 10)]), GOLD)
	var logo := "E M B E R"
	var logo_size := 72
	var logo_width := font.get_string_size(logo, HORIZONTAL_ALIGNMENT_LEFT, -1, logo_size).x
	label_at(Vector2((1152 - logo_width) / 2, 250), logo, logo_size, GOLD)
	var sub := "DEEP HUNTER"
	var sub_width := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	label_at(Vector2((1152 - sub_width) / 2, 292), sub, 20, MUTED)
	var items := title_items()
	title_choice = clampi(title_choice, 0, items.size() - 1)
	var mouse := get_global_mouse_position()
	for i in range(items.size()):
		var rect := title_menu_rect(i)
		var active: bool = i == title_choice or rect.has_point(mouse)
		draw_rect(rect, Color("294047") if active else Color("1b2838"))
		draw_rect(rect, MINT if active else Color("354355"), false, 2 if active else 1)
		var text: String = items[i].label
		var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		label_at(rect.position + Vector2((rect.size.x - text_width) / 2, 29), text, 18, MINT if active else PALE)
	if has_save:
		label_at(Vector2(456, 372), Loc.t("CHAPTER %d / LEVEL %d / %d MIN PLAYED") % [profile.campaign / 3 + 1, profile.level, int(profile.play_seconds / 60)], 13, MUTED)
	else:
		label_at(Vector2(456, 372), "NO SAVE DATA / START A NEW JOURNEY", 13, MUTED)
	label_at(Vector2(456, 168), "W / S or ARROWS: choose     ENTER: confirm", 12, MUTED)
	if title_confirm:
		draw_rect(Rect2(0, 0, 1152, 720), Color(0.02, 0.03, 0.05, 0.82))
		draw_rect(Rect2(376, 300, 400, 130), Color("121d2a"))
		draw_rect(Rect2(376, 300, 400, 130), RED, false, 2)
		label_at(Vector2(404, 344), "OVERWRITE EXISTING SAVE?", 20, RED)
		label_at(Vector2(404, 380), "This erases the current character.", 14, PALE)
		label_at(Vector2(404, 410), "Y / ENTER: erase     N / ESC: cancel", 14, MINT)

func pause_menu_rect(index: int) -> Rect2:
	return Rect2(456, 300 + index * 54, 240, 44)

func pause_key(event: InputEvent) -> void:
	if pause_view == "controls":
		if event.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_E, KEY_SPACE]:
			pause_view = "menu"
		return
	match event.keycode:
		KEY_W, KEY_UP:
			pause_choice = posmod(pause_choice - 1, PAUSE_ITEMS.size())
			feedback.play("loot")
		KEY_S, KEY_DOWN:
			pause_choice = posmod(pause_choice + 1, PAUSE_ITEMS.size())
			feedback.play("loot")
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_E:
			activate_pause(PAUSE_ITEMS[clampi(pause_choice, 0, PAUSE_ITEMS.size() - 1)])

func pause_mouse(mouse: Vector2, button: int) -> void:
	if button != MOUSE_BUTTON_LEFT:
		return
	if pause_view == "controls":
		pause_view = "menu"
		return
	for i in range(PAUSE_ITEMS.size()):
		if pause_menu_rect(i).has_point(mouse):
			pause_choice = i
			activate_pause(PAUSE_ITEMS[i])
			return

func activate_pause(id: String) -> void:
	match id:
		"resume":
			paused = false
			pause_view = "menu"
		"settings":
			toggle_settings()
		"controls":
			pause_view = "controls"
		"title":
			return_to_title()
		"quit":
			get_tree().quit()

func return_to_title() -> void:
	paused = false
	pause_view = "menu"
	panel = ""
	ended = false
	celebration = ""
	return_to_hub()
	title = true
	title_confirm = false
	has_save = save_enabled

func draw_pause() -> void:
	if pause_view == "controls":
		draw_controls_panel()
		return
	draw_rect(Rect2(0, 0, 1152, 720), Color(0.025, 0.04, 0.065, 0.93))
	centered_label(220, "PAUSED", 32, GOLD)
	centered_label(252, "Esc to resume / F10 settings", 15, MUTED)
	var mouse := get_global_mouse_position()
	pause_choice = clampi(pause_choice, 0, PAUSE_ITEMS.size() - 1)
	for i in range(PAUSE_ITEMS.size()):
		var rect := pause_menu_rect(i)
		var active: bool = i == pause_choice or rect.has_point(mouse)
		draw_rect(rect, Color("294047") if active else Color("1b2838"))
		draw_rect(rect, MINT if active else Color("354355"), false, 2 if active else 1)
		var text := Loc.t(["RESUME", "SETTINGS", "CONTROLS", "RETURN TO TITLE", "QUIT"][i])
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		label_at(rect.position + Vector2((rect.size.x - width) / 2, 29), text, 18, MINT if active else PALE)

func draw_controls_panel() -> void:
	draw_rect(Rect2(0, 0, 1152, 720), Color(0.025, 0.04, 0.065, 0.93))
	draw_rect(Rect2(176, 120, 800, 480), Color("121d2a"))
	draw_rect(Rect2(176, 120, 800, 480), Color("506172"), false, 2)
	centered_label(170, "CONTROLS", 26, MINT)
	var rows := [
		["移動 / 狙い", "WASD・矢印 / マウス"],
		["通常攻撃", "左クリック・Space長押し"],
		["無敵回避", "Shift"],
		["アクティブスキル", "1〜4（レベルで解放）"],
		["残火バースト", "F（熱量100%）"],
		["施設・宝箱利用 / 装備回収", "E"],
		["回収モード切替", "L"],
		["HP50%回復", "Q（最大3個）"],
		["拠点へ帰還", "T"],
		["持ち物", "I"],
		["ビルド・鍛冶", "B（拠点のみ）"],
		["設定", "F10"],
		["一時停止・パネルを閉じる", "Esc"],
	]
	for i in range(rows.size()):
		var y := 196 + i * 30
		label_at(Vector2(224, y), rows[i][0], 16, PALE)
		label_at(Vector2(620, y), rows[i][1], 16, MINT)
	centered_label(578, "Esc / Enter: back", 14, MUTED)

func draw_dummy(pos: Vector2) -> void:
	draw_circle(pos + Vector2(0, 14), 22, Color(0, 0, 0, 0.28))
	draw_rect(Rect2(pos - Vector2(11, 24), Vector2(22, 48)), Color("6b4f33"))
	draw_rect(Rect2(pos - Vector2(11, 24), Vector2(22, 48)), Color("b38855"), false, 3)
	draw_line(pos + Vector2(-16, -24), pos + Vector2(16, -24), Color("b38855"), 4)
	draw_line(pos + Vector2(-16, -6), pos + Vector2(16, -6), Color("b38855"), 4)
	draw_circle(pos + Vector2(0, -34), 5, GOLD)

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
	return Rect2(144 + column * 214, 225 + row * 78, 202, 40)

func skill_card_rect(index: int) -> Rect2:
	return Rect2(144 + index * 219, 232, 205, 92)

func support_slot_rect(index: int) -> Rect2:
	return Rect2(144, 350 + index * 38, 430, 34)

func support_pool_rect(index: int) -> Rect2:
	return Rect2(600 + (index % 2) * 212, 350 + (index / 2) * 38, 202, 34)

func preset_save_rect(slot: int) -> Rect2:
	return Rect2(144 + slot * 290, 592, 96, 22)

func preset_load_rect(slot: int) -> Rect2:
	return Rect2(144 + slot * 290 + 100, 592, 96, 22)

func build_tab_rect(index: int) -> Rect2:
	return Rect2(144 + index * 144, 188, 138, 34)

func aura_rect(index: int) -> Rect2:
	return Rect2(144, 260 + index * 60, 620, 52)

func slot_basic_rect() -> Rect2:
	return Rect2(144, 244, 300, 56)

func slot_active_rect(index: int) -> Rect2:
	return Rect2(144, 322 + index * 48, 300, 40)

func skill_pool_rect(index: int) -> Rect2:
	return Rect2(470 + (index % 2) * 268, 244 + (index / 2) * 48, 258, 40)

func skill_color(index: int) -> Color:
	return [Color("f5b27b"), MINT, Color("91bfff"), Color("ff9864")][index]

func slot_required_level(index: int) -> int:
	return [1, 1, 4, 7, 10][index]

func draw_skill_icon(center: Vector2, index: int, color: Color) -> void:
	var diamond := PackedVector2Array([center + Vector2(0, -15), center + Vector2(15, 0), center + Vector2(0, 15), center + Vector2(-15, 0), center + Vector2(0, -15)])
	draw_colored_polygon(diamond, color.darkened(0.8))
	draw_polyline(diamond, color.darkened(0.3), 1.5, true)
	match index:
		0:
			draw_arc(center, 8, -1.3, 1.3, 16, color, 3, true)
			draw_line(center + Vector2(-6, 6), center + Vector2(5, -5), color, 2, true)
		1:
			draw_arc(center, 8, 0, TAU, 20, color, 2, true)
			draw_circle(center, 3, color)
		2:
			draw_line(center + Vector2(-9, 6), center + Vector2(9, -6), color, 3, true)
			draw_line(center + Vector2(3, -6), center + Vector2(9, -6), color, 2, true)
		_:
			draw_circle(center, 5, color)
			draw_arc(center + Vector2(0, 3), 8, PI, TAU, 14, color, 2, true)

func draw_skill_card(index: int) -> void:
	var rect := skill_card_rect(index)
	var skill: Dictionary = Skills.SKILLS[index]
	var selected: bool = profile.stance == index
	var color := skill_color(index)
	var hover := rect.has_point(get_global_mouse_position())
	draw_rect(rect, Color("223342") if hover else (Color("1b2d38") if selected else Color("101b29")))
	draw_rect(rect, color if selected else Color("3a4b5f"), false, 2 if selected else 1)
	if selected:
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, 3)), color)
	var p := rect.position
	draw_skill_icon(p + Vector2(24, 26), index, color)
	label_at(p + Vector2(44, 25), skill.name, 18, color)
	label_at(p + Vector2(44, 43), skill.tag_text, 10, MUTED)
	var combat: Dictionary = profile.combat_stats(index)
	label_at(p + Vector2(12, 68), Loc.t("%.1f DMG / %.2fs / %.0f RANGE") % [combat.damage, combat.interval, combat.reach], 12, PALE)
	label_at(p + Vector2(12, 86), Loc.t("Lv.%d") % profile.skill_levels[index], 11, color if selected else MUTED)

func support_used_slot(id: String) -> int:
	for slot in range(profile.links.size()):
		for entry in profile.links[slot]:
			if str(entry.get("id", "")) == id:
				return slot
	return -1

func draw_support_slot(rect: Rect2, id: String, unlocked: bool, index: int, tier: int = 3) -> void:
	var hover := rect.has_point(get_global_mouse_position())
	if id.is_empty():
		draw_rect(rect, Color("141d29"))
		draw_rect(rect, Color("3a4b5f"), false, 1)
		if unlocked:
			label_at(rect.position + Vector2(12, 24), "EMPTY SLOT / CLICK A SUPPORT", 12, MUTED)
		else:
			label_at(rect.position + Vector2(12, 24), Loc.t("LOCKED / REACH SKILL LEVEL %d") % slot_required_level(index), 12, Color("4a5a6b"))
		return
	var support := Skills.support_def(id)
	var color := Color("a998f5") if hover else GOLD
	draw_rect(rect, Color("2a2438") if hover else Color("1d1a29"))
	draw_rect(rect, color, false, 1)
	label_at(rect.position + Vector2(12, 16), Loc.t("%s  T%d") % [support.name, tier], 14, color)
	label_at(rect.position + Vector2(12, 31), support.text, 11, MUTED)

func draw_support_option(rect: Rect2, id: String) -> void:
	var support := Skills.support_def(id)
	var index := Skills.index_of(profile.slot_skill_id(support_focus))
	var applicable: bool = Skills.support_applies(index, id)
	var used_slot := support_used_slot(id)
	var here := used_slot == support_focus
	var full: bool = profile.links[support_focus].size() >= profile.slot_support_capacity(support_focus)
	var hover := rect.has_point(get_global_mouse_position())
	var color := GOLD if here else (Color("4a5a6b") if used_slot >= 0 else (MINT if applicable else Color("4a5a6b")))
	draw_rect(rect, Color("2a2438") if here else (Color("1b2838") if hover and applicable and used_slot < 0 else Color("111823")))
	draw_rect(rect, color, false, 2 if here else 1)
	label_at(rect.position + Vector2(10, 15), support.name, 13, color)
	var state := Loc.t("LINKED HERE")
	if not here:
		if used_slot >= 0:
			state = Loc.t("USED IN %s") % (Loc.t("BASIC") if used_slot == 0 else Loc.t("KEY %d") % used_slot)
		elif not applicable:
			state = Loc.t("TAG: %s") % Loc.t(support.requires_text)
		elif full:
			state = Loc.t("SLOTS FULL")
		else:
			state = Loc.t("CLICK TO LINK")
	label_at(rect.position + Vector2(10, 30), state, 10, MUTED)

func draw_support_detail(id: String) -> void:
	var support := Skills.support_def(id)
	var index := Skills.index_of(profile.slot_skill_id(support_focus))
	var mouse := get_global_mouse_position()
	var origin := mouse + Vector2(18, 18)
	if origin.x + 420 > 1140:
		origin.x = mouse.x - 438
	origin = origin.clamp(Vector2(12, 12), Vector2(720, 360))
	var rect := Rect2(origin, Vector2(420, 300))
	draw_rect(Rect2(origin + Vector2(5, 5), rect.size), Color(0, 0, 0, 0.6))
	draw_rect(rect, Color("0c1420"))
	draw_rect(rect, MINT, false, 2)
	var p := origin + Vector2(16, 29)
	label_at(p, support.name, 19, MINT)
	label_at(p + Vector2(0, 27), Loc.t("SUPPORT / REQUIRES %s") % Loc.t(support.requires_text), 13, GOLD)
	label_at(p + Vector2(0, 57), support.text, 14, PALE)
	var applies := Skills.support_applies(index, id)
	label_at(p + Vector2(0, 92), Loc.t("APPLIES TO: %s") % Skills.def(profile.slot_skill_id(support_focus)).get("name", "?"), 13, MINT if applies else RED)
	var used_slot := support_used_slot(id)
	if used_slot >= 0:
		var tier := profile.support_tier(used_slot, id)
		label_at(p + Vector2(0, 124), Loc.t("LINKED AT %s / TIER %d") % [(Loc.t("BASIC") if used_slot == 0 else Loc.t("KEY %d") % used_slot), tier], 12, GOLD)
		var cost := profile.link_upgrade_cost(tier)
		label_at(p + Vector2(0, 150), (Loc.t("Right-click a link to upgrade (cost %d embers).") % cost) if cost > 0 else Loc.t("Already at the strongest tier."), 12, MUTED)
	else:
		label_at(p + Vector2(0, 124), "One copy of each support may be used per character.", 12, MUTED)
		label_at(p + Vector2(0, 150), "Click to link into the focused slot.", 12, MINT)
	label_at(p + Vector2(0, 186), Loc.t("SLOTS %d / %d") % [profile.links[support_focus].size(), profile.slot_support_capacity(support_focus)], 13, GOLD)

func draw_skill_detail(index: int) -> void:
	var skill: Dictionary = Skills.SKILLS[index]
	var level: int = profile.skill_levels[index]
	var mouse := get_global_mouse_position()
	var origin := mouse + Vector2(18, 18)
	if origin.x + 420 > 1140:
		origin.x = mouse.x - 438
	origin = origin.clamp(Vector2(12, 12), Vector2(720, 360))
	var rect := Rect2(origin, Vector2(420, 300))
	draw_rect(Rect2(origin + Vector2(5, 5), rect.size), Color(0, 0, 0, 0.6))
	draw_rect(rect, Color("0c1420"))
	draw_rect(rect, skill_color(index), false, 2)
	var p := origin + Vector2(16, 29)
	label_at(p, Loc.t("%s / LEVEL %d OF %d") % [skill.name, level, Skills.MAX_LEVEL], 19, skill_color(index))
	label_at(p + Vector2(0, 27), skill.flavor, 13, MUTED)
	label_at(p + Vector2(0, 57), skill.detail, 12, PALE)
	label_at(p + Vector2(0, 88), Loc.t("TAGS: %s") % skill.tag_text, 13, GOLD)
	var combat: Dictionary = profile.combat_stats(index)
	var current: Dictionary = profile.combat_stats()
	label_at(p + Vector2(0, 115), Loc.t("Hit %.1f  |  Interval %.3fs  |  DPS %.1f") % [combat.damage, combat.interval, combat.damage / combat.interval], 15)
	if index != profile.stance:
		label_at(p + Vector2(0, 140), Loc.t("DPS vs equipped: %+.1f  /  Range %.0f") % [combat.damage / combat.interval - current.damage / current.interval, combat.reach], 13, MINT)
	else:
		label_at(p + Vector2(0, 140), "Linked supports are included in these numbers.", 12, MUTED)
	if index < 3 and profile.has_relic(Effects.RELICS[index].id):
		label_at(p + Vector2(0, 168), ["RELIC / Every third hit sends a wave", "RELIC / Pull enemies into your nova", "RELIC / Two extra piercing rays"][index], 13, Color("ff9864"))
	label_at(p + Vector2(0, 200), "Kills train the equipped skill. Switching keeps progress.", 12, MUTED)
	label_at(p + Vector2(0, 226), "Click to equip in town. Supports are pruned if they no longer apply.", 12, MINT)

func assigned_slot_label(id: String) -> String:
	if id == profile.basic_id():
		return Loc.t("BASIC")
	var slot: int = profile.active_slots.find(id)
	if slot >= 0:
		return Loc.t("KEY %d") % (slot + 1)
	return ""

func draw_basic_slot_card(rect: Rect2, focused: bool) -> void:
	var index: int = profile.stance
	var skill: Dictionary = Skills.def(profile.basic_id())
	var color := skill_glyph_color(index)
	draw_rect(rect, Color("1b2d38"))
	draw_rect(rect, GOLD if focused else color, false, 2 if focused else 1)
	draw_skill_glyph(rect.position + Vector2(32, rect.size.y / 2), index, color)
	label_at(rect.position + Vector2(60, 24), skill.name, 18, color)
	label_at(rect.position + Vector2(60, 44), skill.tag_text, 11, MUTED)

func draw_active_slot_card(rect: Rect2, slot: int, focused: bool) -> void:
	var border := GOLD if focused else Color("3a4b5f")
	var id: String = profile.active_skill(slot)
	if not profile.ability_unlocked(slot):
		draw_rect(rect, Color("101822"))
		draw_rect(rect, border, false, 1)
		label_at(rect.position + Vector2(12, 25), Loc.t("SLOT %d / LOCKED UNTIL Lv.%d") % [slot + 1, int(Skills.SLOT_LEVELS[slot])], 12, Color("4a5a6b"))
		return
	if id.is_empty():
		draw_rect(rect, Color("101822"))
		draw_rect(rect, border, false, 1)
		label_at(rect.position + Vector2(12, 25), Loc.t("SLOT %d / EMPTY") % (slot + 1), 12, MUTED)
		return
	var index := Skills.index_of(id)
	var skill: Dictionary = Skills.def(id)
	var color := skill_glyph_color(index)
	draw_rect(rect, Color("1b2d38"))
	draw_rect(rect, border, false, 2 if focused else 1)
	draw_skill_glyph(rect.position + Vector2(22, rect.size.y / 2), index, color)
	label_at(rect.position + Vector2(42, 17), "%d  %s" % [slot + 1, skill.name], 14, color)
	label_at(rect.position + Vector2(42, 32), Loc.t("Lv.%d / COOLDOWN %.0fs / MANA %d") % [profile.skill_levels[index], float(skill.cooldown), int(skill.get("cost", 0))], 10, MUTED)

func draw_pool_card(rect: Rect2, index: int) -> void:
	var skill: Dictionary = Skills.SKILLS[index]
	var color := skill_glyph_color(index)
	var hover := rect.has_point(get_global_mouse_position())
	var badge := assigned_slot_label(skill.id)
	draw_rect(rect, Color("223342") if hover else Color("111823"))
	draw_rect(rect, color if not badge.is_empty() else Color("3a4b5f"), false, 2 if not badge.is_empty() else 1)
	draw_skill_glyph(rect.position + Vector2(20, rect.size.y / 2), index, color)
	label_at(rect.position + Vector2(38, 17), skill.name, 13, color)
	label_at(rect.position + Vector2(38, 31), skill.tag_text if skill.type == "attack" else skill.text, 10, MUTED)
	label_at(rect.position + Vector2(rect.size.x - 32, 31), Loc.t("Lv.%d") % profile.skill_levels[index], 10, MUTED)
	if not badge.is_empty():
		label_at(rect.position + Vector2(rect.size.x - 58, 17), badge, 10, GOLD)

func draw_slots_tab() -> void:
	var mouse := get_global_mouse_position()
	label_at(Vector2(144, 232), "BASIC ATTACK  (CLICK / SPACE)", 12, MUTED)
	draw_basic_slot_card(slot_basic_rect(), slot_focus == 0)
	label_at(Vector2(144, 312), "ACTIVE SLOTS  (1-4)", 12, MUTED)
	for i in range(4):
		draw_active_slot_card(slot_active_rect(i), i, slot_focus == i + 1)
	label_at(Vector2(470, 232), "SKILL POOL  /  PICK A SLOT, THEN A SKILL", 12, GOLD)
	for i in range(Skills.count()):
		draw_pool_card(skill_pool_rect(i), i)
	label_at(Vector2(144, 520), "Attack skills can also sit in active slots. Each skill fills only one slot.", 12, MUTED)
	label_at(Vector2(144, 542), "Supports follow the basic attack; active skills scale with your attack.", 12, MUTED)
	for slot in range(3):
		var summary := profile.build_summary(slot) if not profile.builds[slot].is_empty() else Loc.t("EMPTY")
		label_at(Vector2(144 + slot * 290, 586), "P%d  %s" % [slot + 1, summary], 10, MUTED)
		ui_button(preset_save_rect(slot), Loc.t("SAVE"), true)
		ui_button(preset_load_rect(slot), Loc.t("LOAD"), not profile.builds[slot].is_empty())
	for i in range(Skills.count()):
		if skill_pool_rect(i).has_point(mouse):
			if Skills.SKILLS[i].type == "attack":
				draw_skill_detail(i)
			else:
				draw_active_detail(i)

func support_selector_rect(index: int) -> Rect2:
	return Rect2(144 + index * 172, 284, 164, 36)

func draw_supports_tab() -> void:
	var skill: Dictionary = Skills.def(profile.slot_skill_id(support_focus))
	label_at(Vector2(144, 232), Loc.t("SUPPORTS / %s") % skill.get("name", "?"), 14, MINT)
	for i in range(5):
		var rect := support_selector_rect(i)
		var on := support_focus == i
		draw_rect(rect, Color("294047") if on else Color("1b2838"))
		draw_rect(rect, MINT if on else Color("354355"), false, 2 if on else 1)
		var label := "BASIC" if i == 0 else "%d" % i
		var slot_id := profile.slot_skill_id(i)
		label_at(rect.position + Vector2(10, 24), Loc.t("%s  %s") % [Loc.t(label), Skills.def(slot_id).get("name", "-")], 12, MINT if on else PALE)
	label_at(Vector2(144, 336), Loc.t("SUPPORT SLOTS %d / %d") % [profile.links[support_focus].size(), profile.slot_support_capacity(support_focus)], 13, MINT)
	var entries: Array = profile.links[support_focus]
	for i in range(Skills.MAX_SUPPORTS):
		var id := str(entries[i].get("id", "")) if i < entries.size() else ""
		var tier := int(entries[i].get("tier", 3)) if i < entries.size() else 3
		draw_support_slot(support_slot_rect(i), id, i < profile.slot_support_capacity(support_focus), i, tier)
	label_at(Vector2(600, 336), "SUPPORT POOL", 13, GOLD)
	for i in range(Skills.SUPPORTS.size()):
		draw_support_option(support_pool_rect(i), Skills.SUPPORTS[i].id)
	var combat: Dictionary = profile.slot_combat(support_focus)
	label_at(Vector2(144, 552), Loc.t("%s Lv.%d  |  HIT %.1f / %.2fs") % [skill.get("name", "?"), profile.skill_levels[Skills.index_of(profile.slot_skill_id(support_focus))], combat.damage, combat.interval], 15, MINT)
	var extras: Array[String] = []
	if combat.projectiles > 0:
		extras.append(Loc.t("PROJECTILES +%d") % combat.projectiles)
	if combat.pierce > 0:
		extras.append(Loc.t("PIERCE +%d") % combat.pierce)
	if combat.chain > 0:
		extras.append(Loc.t("CHAIN +%d") % combat.chain)
	if not is_equal_approx(combat.area, 1.0):
		extras.append(Loc.t("AREA %d%%") % roundi(combat.area * 100))
	if combat.burn > 0:
		extras.append(Loc.t("BURN"))
	if combat.leech > 0:
		extras.append(Loc.t("LEECH"))
	if combat.heat > 0:
		extras.append(Loc.t("HEAT +%d") % combat.heat)
	label_at(Vector2(144, 574), " / ".join(PackedStringArray(extras)) if not extras.is_empty() else "NO SUPPORTS LINKED", 13, PALE)
	var mouse := get_global_mouse_position()
	for i in range(Skills.MAX_SUPPORTS):
		var id := str(entries[i].get("id", "")) if i < entries.size() else ""
		if not id.is_empty() and support_slot_rect(i).has_point(mouse):
			draw_support_detail(id)
	for i in range(Skills.SUPPORTS.size()):
		if support_pool_rect(i).has_point(mouse):
			draw_support_detail(Skills.SUPPORTS[i].id)

func draw_active_detail(index: int) -> void:
	var skill: Dictionary = Skills.SKILLS[index]
	var mouse := get_global_mouse_position()
	var origin := mouse + Vector2(18, 18)
	if origin.x + 420 > 1140:
		origin.x = mouse.x - 438
	origin = origin.clamp(Vector2(12, 12), Vector2(720, 360))
	var rect := Rect2(origin, Vector2(420, 220))
	draw_rect(Rect2(origin + Vector2(5, 5), rect.size), Color(0, 0, 0, 0.6))
	draw_rect(rect, Color("0c1420"))
	draw_rect(rect, skill_glyph_color(index), false, 2)
	var p := origin + Vector2(16, 29)
	label_at(p, skill.name, 19, skill_glyph_color(index))
	label_at(p + Vector2(0, 27), Loc.t("ACTIVE / COOLDOWN %.1fs / MANA %d") % [float(skill.cooldown), int(skill.get("cost", 0))], 13, GOLD)
	label_at(p + Vector2(0, 57), skill.text, 14, PALE)
	label_at(p + Vector2(0, 92), "Damage scales with attack and untagged passives.", 12, MUTED)
	label_at(p + Vector2(0, 118), "Assign it to any active slot.", 12, MINT)

func draw_build() -> void:
	label_at(Vector2(144, 176), "THE EMBER GRIMOIRE", 23, GOLD)
	for tab in range(6):
		ui_button(build_tab_rect(tab), ["SLOTS", "SUPPORTS", "TALENTS & FORGE", "PASSIVES", "MOD CRAFTING", "AURAS"][tab], build_tab == tab)
	label_at(Vector2(700, 176), Loc.t("EMBERS %d / POINTS %d / PASSIVE %d") % [profile.embers, profile.talent_points(), profile.passive_points()], 12, MUTED)
	if build_tab == 5:
		draw_auras()
		return
	if build_tab == 4:
		draw_crafting()
		return
	if build_tab == 3:
		draw_passives()
		return
	if build_tab == 2:
		draw_forge_tab()
		return
	if build_tab == 1:
		draw_supports_tab()
		return
	draw_slots_tab()

func draw_auras() -> void:
	label_at(Vector2(144, 232), Loc.t("SPIRIT %d / %d") % [profile.reserved_spirit(), profile.spirit_max()], 15, MANA)
	label_at(Vector2(560, 232), "Reserved auras stay on while you fight.", 12, MUTED)
	var mouse := get_global_mouse_position()
	for i in range(Skills.AURAS.size()):
		var aura: Dictionary = Skills.AURAS[i]
		var rect := aura_rect(i)
		var on := profile.has_aura(aura.id)
		var hover := rect.has_point(mouse)
		draw_rect(rect, Color("223342") if hover else (Color("1b2d38") if on else Color("101b29")))
		draw_rect(rect, MANA if on else Color("3a4b5f"), false, 2 if on else 1)
		label_at(rect.position + Vector2(16, 22), aura.name, 18, MANA if on else PALE)
		label_at(rect.position + Vector2(16, 42), aura.text, 13, MUTED)
		label_at(rect.position + Vector2(430, 22), Loc.t("RESERVE %d") % int(aura.reserve), 14, MANA if on else MUTED)
		label_at(rect.position + Vector2(556, 22), Loc.t("ON") if on else Loc.t("OFF"), 15, MINT if on else MUTED)
	label_at(Vector2(144, 552), "Only reserved auras are active. Click to toggle; the spirit pool grows with level.", 13, MUTED)

func branch_color(node: Dictionary) -> Color:
	var id: String = node.id
	if id.begins_with("off"):
		return Color("ff9864")
	if id.begins_with("def"):
		return Color("91caff")
	if id.begins_with("util"):
		return MINT
	return GOLD

func passive_node_center(id: String) -> Vector2:
	return Vector2(576, 320) + PassiveTree.def(id).pos

func passive_node_rect(id: String) -> Rect2:
	var node := PassiveTree.def(id)
	var radius := 26.0 if node.get("notable", false) else 20.0
	return Rect2(passive_node_center(id) - Vector2(radius, radius), Vector2(radius * 2, radius * 2))

func draw_passives() -> void:
	var mouse := get_global_mouse_position()
	for id in PassiveTree.node_ids():
		var node := PassiveTree.def(id)
		if node.parent == "":
			continue
		var on := profile.has_passive(id)
		draw_line(passive_node_center(node.parent), passive_node_center(id), MINT if on else Color("354355"), 3 if on else 2, true)
	for id in PassiveTree.node_ids():
		var node := PassiveTree.def(id)
		var center := passive_node_center(id)
		var radius := 26.0 if node.get("notable", false) else 20.0
		var allocated := profile.has_passive(id)
		var color := branch_color(node)
		if not allocated and not profile.can_allocate_passive(id):
			color = Color("3a4b5f")
		draw_circle(center, radius, Color(color, 0.28 if allocated else (0.14 if profile.can_allocate_passive(id) else 0.06)))
		draw_arc(center, radius, 0, TAU, 28, color, 3 if allocated else 2, true)
		if allocated:
			draw_circle(center, radius - 9, Color(color, 0.5))
		if passive_node_rect(id).has_point(mouse):
			draw_arc(center, radius + 4, 0, TAU, 28, PALE, 2, true)
	label_at(Vector2(144, 232), Loc.t("PASSIVE POINTS %d / %d") % [profile.passive_points(), PassiveTree.MAX_POINTS], 14, MINT)
	ui_button(Rect2(144, 244, 240, 32), Loc.t("RESET PASSIVES / FREE"), not profile.passives.is_empty())
	label_at(Vector2(400, 266), Loc.t("Click to allocate / Right-click to refund / One point per level"), 13, MUTED)
	for id in PassiveTree.node_ids():
		if passive_node_rect(id).has_point(mouse):
			draw_passive_tooltip(id)

func draw_passive_tooltip(id: String) -> void:
	var node := PassiveTree.def(id)
	var mouse := get_global_mouse_position()
	var origin := mouse + Vector2(20, 18)
	if origin.x + 380 > 1140:
		origin.x = mouse.x - 398
	origin = origin.clamp(Vector2(12, 12), Vector2(760, 340))
	var rect := Rect2(origin, Vector2(380, 180))
	draw_rect(Rect2(origin + Vector2(5, 5), rect.size), Color(0, 0, 0, 0.6))
	draw_rect(rect, Color("0c1420"))
	draw_rect(rect, branch_color(node), false, 2)
	var p := origin + Vector2(16, 29)
	label_at(p, node.name, 18, branch_color(node))
	label_at(p + Vector2(0, 26), node.text, 14, PALE)
	var tags: Array = node.get("tags", [])
	if not tags.is_empty():
		label_at(p + Vector2(0, 52), Loc.t("ONLY HELPS SKILL TAGS: %s") % ", ".join(PackedStringArray(tags)), 12, GOLD)
	var status := Loc.t("START")
	if id != PassiveTree.ROOT:
		if profile.has_passive(id):
			status = Loc.t("ALLOCATED")
		elif profile.can_allocate_passive(id):
			status = Loc.t("CLICK TO ALLOCATE")
		elif not profile.has_passive(node.parent):
			status = Loc.t("NEEDS THE PREVIOUS NODE")
		else:
			status = Loc.t("NO POINTS LEFT")
	label_at(p + Vector2(0, 84), status, 13, MINT)
	if profile.has_passive(id) and id != PassiveTree.ROOT:
		label_at(p + Vector2(0, 110), Loc.t("Right-click to refund. Nodes further down must be refunded first."), 11, MUTED)

func draw_forge_tab() -> void:
	label_at(Vector2(144, 263), "TEMPER THE HUNTER", 23, MINT)
	label_at(Vector2(144, 295), "Spend earned talent points. Reclaim them freely to try a different path.", 16, PALE)
	label_at(Vector2(144, 324), "Salvage unwanted gear in your inventory; feed the embers into your equipment.", 14, MUTED)
	for i in range(4):
		ui_button(build_rect(2, i), Loc.t("%s %d / 6 [+]") % [Loc.t(["MIGHT", "VITALITY", "TEMPO", "SPIRIT"][i]), profile.talents[i]], profile.talent_points() > 0)
		label_at(build_rect(2, i).position + Vector2(0, 58), ["+5 attack per point", "+20 life / +1 defense per point", "+6% attack speed per point", "+15 mana / +1 regen per point"][i], 12, MUTED)
	for i in range(3):
		var slot: String = Profile.SLOTS[i]
		var gear: Dictionary = profile.equipment[slot]
		var rank := int(gear.get("upgrade", 0))
		ui_button(build_rect(3, i), Loc.t("%s +%d / %s") % [Loc.t(slot.to_upper()), rank, Loc.t("MAX") if rank >= 3 else Loc.t("%d EMBERS") % profile.upgrade_cost(slot)], not gear.is_empty() and rank < 3 and profile.embers >= profile.upgrade_cost(slot))
		label_at(build_rect(3, i).position + Vector2(0, 58), "Empty slot" if gear.is_empty() else gear.name, 12, MUTED)
	ui_button(Rect2(144, 550, 270, 40), "RESET TALENTS / FREE")
	label_at(Vector2(440, 576), "I: inventory / right-click gear to salvage / B: close", 14, MUTED)

func build_click(mouse: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	if not (hub or training) or panel != "build":
		return
	if not craft_pending.is_empty():
		craft_click(mouse)
		return
	for tab in range(6):
		if tab == 4 and not hub:
			if build_tab_rect(tab).has_point(mouse):
				message = Loc.t("Mod crafting is only available in town.")
			continue
		if build_tab_rect(tab).has_point(mouse):
			build_tab = tab
			return
	if build_tab == 5:
		for i in range(Skills.AURAS.size()):
			if aura_rect(i).has_point(mouse):
				if profile.toggle_aura(Skills.AURAS[i].id):
					message = Loc.t("Aura updated.") if profile.has_aura(Skills.AURAS[i].id) else Loc.t("Aura disabled.")
				else:
					message = Loc.t("Not enough spirit.")
				break
		refresh_stats()
		hp = max_hp
		persist()
		return
	if build_tab == 4:
		craft_click(mouse)
		return
	if build_tab == 3:
		if button == MOUSE_BUTTON_RIGHT:
			for id in PassiveTree.node_ids():
				if passive_node_rect(id).has_point(mouse):
					if profile.refund_passive(id):
						message = Loc.t("Passive refunded.")
					break
		elif Rect2(144, 244, 240, 32).has_point(mouse):
			profile.reset_passives()
			message = Loc.t("Passives reset.")
		else:
			for id in PassiveTree.node_ids():
				if passive_node_rect(id).has_point(mouse):
					if profile.allocate_passive(id):
						message = Loc.t("Passive allocated.")
					break
		refresh_stats()
		hp = max_hp
		persist()
		return
	if build_tab == 2:
		for i in range(4):
			if build_rect(2, i).has_point(mouse):
				profile.spend_talent(i)
		for i in range(3):
			if build_rect(3, i).has_point(mouse):
				profile.upgrade(Profile.SLOTS[i])
		if Rect2(144, 550, 270, 40).has_point(mouse):
			profile.talents.assign([0, 0, 0, 0])
	elif build_tab == 1:
		for i in range(5):
			if support_selector_rect(i).has_point(mouse):
				support_focus = i
				return
		var entries: Array = profile.links[support_focus]
		for i in range(Skills.MAX_SUPPORTS):
			if i < entries.size() and support_slot_rect(i).has_point(mouse):
				var id := str(entries[i].get("id", ""))
				if button == MOUSE_BUTTON_RIGHT:
					if profile.upgrade_support(support_focus, id):
						message = Loc.t("Support upgraded to the next tier.")
					else:
						message = Loc.t("Not enough embers or already upgraded.")
				else:
					profile.remove_support(support_focus, id)
					message = Loc.t("Support unlinked.")
				break
		for i in range(Skills.SUPPORTS.size()):
			if support_pool_rect(i).has_point(mouse):
				var support_id: String = Skills.SUPPORTS[i].id
				if support_used_slot(support_id) == support_focus:
					profile.remove_support(support_focus, support_id)
					message = Loc.t("Support unlinked.")
				elif profile.add_support(support_focus, support_id):
					message = Loc.t("Support linked.")
				else:
					message = Loc.t("Cannot link that support here.")
				break
	else:
		if slot_basic_rect().has_point(mouse):
			slot_focus = 0
		for i in range(4):
			if slot_active_rect(i).has_point(mouse):
				slot_focus = i + 1
		for i in range(Skills.count()):
			if skill_pool_rect(i).has_point(mouse):
				var skill_id: String = Skills.SKILLS[i].id
				if slot_focus == 0:
					if profile.assign_basic(skill_id):
						message = Loc.t("Basic attack set to %s.") % Skills.def(skill_id).name
					else:
						message = Loc.t("Only attack skills can fill the basic slot.")
				elif profile.assign_active(slot_focus - 1, skill_id):
					message = Loc.t("Slot %d set to %s.") % [slot_focus, Skills.def(skill_id).name]
				else:
					message = Loc.t("That skill is locked or already assigned.")
				break
		for slot in range(3):
			if preset_save_rect(slot).has_point(mouse):
				profile.save_build(slot)
				message = Loc.t("Preset %d saved.") % (slot + 1)
			elif preset_load_rect(slot).has_point(mouse) and not profile.builds[slot].is_empty():
				profile.load_build(slot)
				message = Loc.t("Preset %d loaded.") % (slot + 1)
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
		label_at(rect.position + Vector2(16, 30), Loc.t("GUARANTEED RARE / TIER %d") % mini(9, loot_tier() + 1), 13, GOLD)
		label_at(rect.position + Vector2(16, 65), Profile.SLOTS[i].to_upper(), 24, PALE)
		label_at(rect.position + Vector2(16, 98), Loc.t("Rune: %s") % Profile.STANCES[profile.stance], 15, MINT)
		label_at(rect.position + Vector2(16, 143), Loc.t("AWAKEN / CLICK OR %d") % (i + 1), 14, Color("ad9cff"))
	label_at(Vector2(144, 490), Loc.t("+%d embers. Chosen gear goes directly to your bag and is protected from salvage.") % (loot_tier() * 12), 15, GOLD)
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
		title = Loc.t("GUARDS REMAINING / %d") % trial.remaining
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

func expedition_combat(skill_index: int = -1) -> Dictionary:
	if skill_index < 0:
		return slot_combat(0)
	var combat: Dictionary = profile.combat_stats(skill_index)
	combat.damage *= shrine.multiplier("attack")
	return combat

func heat_per_hit() -> float:
	var combat: Dictionary = profile.combat_stats()
	return (12 + profile.effect_count("charge") * 4 + combat.heat) * combat.heat_mult * shrine.multiplier("heat")

func potion_healing() -> float:
	return max_hp * 0.5 * shrine.multiplier("potion")

func use_potion() -> bool:
	if hub or ended or paused or not panel.is_empty() or not celebration.is_empty() or potions <= 0 or hp >= max_hp:
		return false
	potions -= 1
	hp = minf(max_hp, hp + potion_healing())
	return true

func shrine_available() -> bool:
	if hub or training or ended or map_cleared or shrine.choice >= 0:
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
	message = Loc.t("%s / %s / %s. This expedition only.") % [Loc.t(Shrine.OFFERS[option].name), Loc.t(Shrine.OFFERS[option].benefit), Loc.t(Shrine.OFFERS[option].cost)]
	return true

func shrine_card(index: int) -> Rect2:
	return Rect2(144 + index * 292, 254, 276, 262)

func shrine_preview(option: int) -> Array[String]:
	match option:
		0:
			return [Loc.t("Hit %.1f -> %.1f") % [profile.combat_stats().damage, profile.combat_stats().damage * shrine.multiplier("attack", option)], Loc.t("Potion %.1f -> %.1f HP") % [max_hp * 0.5, max_hp * 0.5 * shrine.multiplier("potion", option)]]
		1:
			return [Loc.t("Heat %.0f -> %.0f / hit") % [heat_per_hit(), heat_per_hit() * shrine.multiplier("heat", option)], Loc.t("100 damage -> 115 before armor")]
		_:
			return [Loc.t("Bonus Rare / Tier %d") % loot_tier(), Loc.t("All living & future enemies")]

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
		label_at(p + Vector2(0, 214), Loc.t("ACCEPT / CLICK OR %d") % (i + 1), 15, GOLD)
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
	label_at(Vector2(144, 311), Loc.t("%s / BASE TIER %d") % [item.name, item.tier], 15, GOLD)
	var mods := Mods.entries(item)
	for i in range(4):
		ui_button(craft_row(i), (Loc.t("P%d  ") % (i + 1) if i < 2 else Loc.t("S%d  ") % (i - 1)) + (Mods.describe(mods[i]) if i % 2 < Mods.capacity(item) else Loc.t("Rare gear required")), craft_index == i)
	if not craft_pending.is_empty():
		label_at(Vector2(566, 318), "CRAFT RESULT / COST PAID", 20, GOLD)
		label_at(Vector2(566, 357), Loc.t("OLD: %s") % Mods.describe(mods[craft_index]), 13, MUTED)
		label_at(Vector2(566, 387), Loc.t("NEW: %s") % Mods.describe(craft_pending.item.mods[craft_index]), 13, MINT)
		var before := Mods.totals(item)
		var after := Mods.totals(craft_pending.item)
		label_at(Vector2(566, 422), Loc.t("ATK %d -> %d / LIFE %d -> %d") % [before.attack, after.attack, before.health, after.health], 15)
		label_at(Vector2(566, 449), Loc.t("DEF %d -> %d / SPD %d%% -> %d%%") % [before.armor, after.armor, before.haste, after.haste], 15)
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
		ui_button(Rect2(566 + i * 146, 404, 138, 38), Loc.t("T%d%s") % [3 - i, Loc.t(" LOCKED") if 3 - i < Mods.best_tier(item) else ""], craft_tier == 3 - i)
	var limits: Array = Mods.DEFINITIONS[craft_id].ranges[3 - craft_tier]
	label_at(Vector2(566, 469), Loc.t("%d-%d %s / selected Mod: 100%%") % [limits[0], limits[1], Loc.t(Mods.DEFINITIONS[craft_id].unit)], 14, PALE)
	var quote: Dictionary = profile.craft_quote(craft_slot, craft_index, craft_id, craft_tier)
	ui_button(Rect2(566, 487, 438, 40), "UNAVAILABLE / LOCK, TIER OR DUPLICATE" if quote.is_empty() else Loc.t("CRAFT / %d EMBERS%s") % [quote.cost, Loc.t(" / NOT ENOUGH") if profile.embers < quote.cost else ""], not quote.is_empty() and profile.embers >= quote.cost)
	ui_button(Rect2(144, 526, 394, 38), "UNLOCK SELECTED MOD" if mods[craft_index].get("locked", false) else "LOCK SELECTED MOD / FREE", not mods[craft_index].is_empty())
	label_at(Vector2(566, 552), "Cost is spent on rolling. Keep new or old; no refund.", 12, MUTED)
	label_at(Vector2(144, 591), "Select slot -> Mod -> Tier. Only that slot changes. T1 is strongest; higher bases unlock it.", 14, MUTED)

func craft_click(mouse: Vector2) -> void:
	if not hub or panel != "build" or build_tab != 4:
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
	label_at(p, Loc.t("%s / BASE T%d") % [item.name, item.tier], 17, rarity_color(item))
	label_at(p + Vector2(0, 26), Loc.t("%s / %s / TEMPER +%d") % [Profile.RARITIES[item.rarity], item.slot.to_upper(), item.get("upgrade", 0)], 12, MUTED)
	label_at(p + Vector2(0, 52), Loc.t("BASE: ATK %d / HP %d / DEF %d / SPD %d%%") % [item.attack, item.health, item.armor, item.haste], 12)
	var mods := Mods.entries(item)
	for i in range(4):
		var mod_line: String = Mods.describe(mods[i]) if i % 2 < Mods.capacity(item) else "--"
		label_at(p + Vector2(0, 80 + i * 24), (Loc.t("PREFIX %s") if i < 2 else Loc.t("SUFFIX %s")) % mod_line, 12, MINT if i < 2 else GOLD)
	label_at(p + Vector2(0, 185), item_stats(item), 13, PALE)
	var actual := Mods.totals(item)
	var current := Mods.totals(profile.equipment[item.slot])
	label_at(p + Vector2(0, 209), Loc.t("VS EQUIPPED: ATK %+d / HP %+d / DEF %+d / SPD %+d%%") % [actual.attack - current.attack, actual.health - current.health, actual.armor - current.armor, actual.haste - current.haste], 11, MINT)
	label_at(p + Vector2(0, 234), Loc.t("Rune: %s") % (Profile.STANCES[item.rune] if int(item.get("rune", -1)) >= 0 else Loc.t("None")), 13, GOLD)
	label_at(p + Vector2(0, 260), "B > MOD CRAFTING / T3 -> T2 -> T1", 12, MUTED)
	label_at(p + Vector2(0, 285), "SALVAGE PROTECTED" if item.get("favorite", false) else "F / middle click: protect from salvage", 12, MINT)
	label_at(p + Vector2(0, 307), "Mod locks protect crafting slots, not the item from salvage.", 11, MUTED)

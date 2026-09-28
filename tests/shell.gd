extends SceneTree

const Profile = preload("res://scripts/profile.gd")
var failed := false

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, title: String) -> void:
	if not condition:
		failed = true
		push_error("FAIL: " + title)

func run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	scene.save_enabled = false
	root.add_child(scene)
	scene.set_process(false)
	# Keep the navigation test from starting a synthesized voice that would outlive the
	# deferred free of the scene at exit.
	scene.feedback.set_volume(0.0)
	check(not scene.title and scene.hub, "Tests start in the hub without a title")

	# New Game resets a progressed character.
	scene.profile.level = 7
	scene.profile.campaign = 5
	scene.profile.embers = 999
	scene.profile.inventory.append(scene.profile.roll_item(3, true))
	scene.title = true
	scene.has_save = false
	scene.title_confirm = false
	scene.activate_title("new")
	check(not scene.title and scene.hub, "New Game leaves the title")
	check(scene.profile.level == 1 and scene.profile.campaign == 0 and scene.profile.embers == 0, "New Game resets progress")
	check(scene.profile.inventory.is_empty(), "New Game clears the backpack")
	check(scene.profile.equipment.weapon.name == "Worn sword" and scene.profile.equipment.charm.is_empty(), "New Game restores default gear")
	check(scene.has_save, "New Game marks a save as existing")

	# An existing save is protected by the overwrite confirmation.
	scene.title = true
	scene.has_save = true
	scene.profile.level = 4
	scene.title_confirm = false
	scene.activate_title("new")
	check(scene.title_confirm and scene.title and scene.profile.level == 4, "New Game asks before erasing a save")
	var no_key := InputEventKey.new()
	no_key.keycode = KEY_N
	no_key.pressed = true
	scene.title_input(no_key)
	check(not scene.title_confirm and scene.title and scene.profile.level == 4, "Cancel keeps the save")
	scene.activate_title("new")
	var yes_key := InputEventKey.new()
	yes_key.keycode = KEY_Y
	yes_key.pressed = true
	scene.title_input(yes_key)
	check(not scene.title and scene.profile.level == 1, "Confirm erases and starts a new character")

	# Continue keeps existing progress.
	scene.title = true
	scene.has_save = true
	scene.profile.level = 9
	scene.activate_title("continue")
	check(not scene.title and scene.hub and scene.profile.level == 9, "Continue keeps progress")

	# Keyboard navigation wraps around the available menu entries.
	scene.title = true
	scene.has_save = false
	scene.title_choice = 0
	var down := InputEventKey.new()
	down.keycode = KEY_DOWN
	down.pressed = true
	scene.title_input(down)
	check(scene.title_choice == 1, "Menu moves down")
	var up := InputEventKey.new()
	up.keycode = KEY_UP
	up.pressed = true
	scene.title_input(up)
	check(scene.title_choice == 0, "Menu moves up")
	scene.title_input(up)
	check(scene.title_choice == scene.title_items().size() - 1, "Menu wraps around")

	# Draw paths for the title and its confirmation must not error.
	scene.title = true
	scene.title_confirm = true
	scene.queue_redraw()
	await process_frame
	scene.title_confirm = false
	scene.queue_redraw()
	await process_frame

	# Pause menu navigation, views, and returning to the title.
	scene.title = false
	scene.paused = true
	scene.pause_view = "menu"
	scene.pause_choice = 0
	var pause_down := InputEventKey.new()
	pause_down.keycode = KEY_DOWN
	pause_down.pressed = true
	scene.pause_key(pause_down)
	check(scene.pause_choice == 1, "Pause menu moves down")
	scene.activate_pause("controls")
	check(scene.pause_view == "controls", "Controls view opens")
	var pause_back := InputEventKey.new()
	pause_back.keycode = KEY_ESCAPE
	pause_back.pressed = true
	scene.pause_key(pause_back)
	check(scene.pause_view == "menu", "Controls view closes with Esc")
	scene.activate_pause("resume")
	check(not scene.paused, "Resume leaves pause")

	scene.profile.level = 6
	scene.profile.campaign = 3
	scene.paused = true
	scene.activate_pause("title")
	check(scene.title and scene.hub and not scene.paused, "Return to title leaves the run")
	check(scene.profile.level == 6 and scene.profile.campaign == 3, "Return to title keeps progress")

	# Draw paths for the pause menu and its controls view.
	scene.title = false
	scene.paused = true
	scene.pause_view = "menu"
	scene.queue_redraw()
	await process_frame
	scene.pause_view = "controls"
	scene.queue_redraw()
	await process_frame
	scene.paused = false
	scene.pause_view = "menu"

	# A fresh profile is the documented default.
	var fresh = Profile.new()
	fresh.level = 5
	fresh.campaign = 4
	fresh.embers = 120
	fresh.inventory.append(fresh.roll_item(2, true))
	fresh.stash.append(fresh.roll_item(1))
	fresh.reset()
	check(fresh.level == 1 and fresh.campaign == 0 and fresh.unlocked == 1 and fresh.depth == 1, "Profile.reset restores defaults")
	check(fresh.embers == 0 and fresh.inventory.is_empty() and fresh.stash.is_empty(), "Profile.reset clears currency and gear")
	check(fresh.skill_levels[0] == 1 and fresh.skill_xp[0] == 0 and fresh.links[0].is_empty(), "Profile.reset restores growth")
	check(fresh.talents[0] == 0 and fresh.talents[1] == 0 and fresh.talents[2] == 0 and fresh.talents[3] == 0, "Profile.reset clears talents")
	check(fresh.equipment.weapon.name == "Worn sword" and fresh.equipment.armor.name == "Traveler coat" and fresh.equipment.charm.is_empty(), "Profile.reset restores starting gear")

	scene.queue_free()
	if not failed:
		print("PASS: title screen, pause menu, new game reset, overwrite guard, and profile defaults")
	quit(1 if failed else 0)

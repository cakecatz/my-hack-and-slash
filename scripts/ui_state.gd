extends RefCounted
## Presentation-only UI state: onboarding and one-shot tutorial hints.
## Kept separate from the validated character save so this format can change freely.

const STATE_PATH := "user://ui_state.cfg"
const SECTION := "ui"

var seen_intro := false
var shown_hints: Dictionary = {}

func load_state(path: String = STATE_PATH) -> void:
	if not FileAccess.file_exists(path):
		return
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return
	seen_intro = bool(config.get_value(SECTION, "seen_intro", false))
	var hints: Variant = config.get_value(SECTION, "shown_hints", {})
	if hints is Dictionary:
		for key in hints:
			if hints[key] is bool and hints[key]:
				shown_hints[str(key)] = true

func save_state(path: String = STATE_PATH) -> Error:
	var config := ConfigFile.new()
	config.set_value(SECTION, "seen_intro", seen_intro)
	config.set_value(SECTION, "shown_hints", shown_hints)
	var error := config.save(path + ".tmp")
	if error != OK:
		return error
	return DirAccess.rename_absolute(path + ".tmp", path)

func has_seen_hint(id: String) -> bool:
	return bool(shown_hints.get(id, false))

func mark_hint(id: String) -> void:
	if shown_hints.get(id, false):
		return
	shown_hints[id] = true

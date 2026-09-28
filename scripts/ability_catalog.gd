extends RefCounted
## Thin view over the active skills inside skill_catalog. Active slot `index`
## corresponds to ability key `index + 1` and to SKILLS entries of type "active".

const Skills = preload("res://scripts/skill_catalog.gd")

static func count() -> int:
	var total := 0
	for skill in Skills.SKILLS:
		if skill.type == "active":
			total += 1
	return total

static func def(index: int) -> Dictionary:
	var active := 0
	for skill in Skills.SKILLS:
		if skill.type != "active":
			continue
		if active == index:
			return skill
		active += 1
	return {}

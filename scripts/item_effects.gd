extends RefCounted
## Equipment identity: effects change combat, not just the character sheet.

const AFFIXES := {
	"scorch": {"name": "Scorching", "text": "Hits burn for 20% hit damage/sec, for 2s."},
	"frost": {"name": "Frostbound", "text": "Hits slow movement by 15% for 1.5s."},
	"charge": {"name": "Charged", "text": "+4 heat per landed attack; once per swing."}
}
const RELICS := [
	{"id": "cleave_wave", "name": "Warden's Oath", "slot": "weapon", "skill": 0,
	 "effect": "CLEAVE: every 3rd landed swing sends a wave.", "detail": "Wave: 300 range, 75% hit damage. No double hit."},
	{"id": "nova_pull", "name": "Sentinel's Memory", "slot": "armor", "skill": 1,
	 "effect": "NOVA: pull nearby enemies before striking.", "detail": "Pull: 250 range, 90 distance. Bosses resist."},
	{"id": "lance_fork", "name": "Tyrant's Last Ember", "slot": "charm", "skill": 2,
	 "effect": "LANCE: fire two additional piercing rays.", "detail": "Side rays: +/-22 degrees, 60% hit. No overlap."}
]
const ELITES := ["VOLATILE", "STORMCALLER", "SWIFT"]

static func relic_index(id: String) -> int:
	for i in range(RELICS.size()):
		if RELICS[i].id == id:
			return i
	return -1

extends RefCounted
## Pure combat and timing rules, independent of rendering and the audio device.

enum Weapon { SWORD, SHIELD, GREATSWORD }
enum Action { SWORD, GUARD, WINDUP, HEAVY_ATTACK }
enum Judgment { NONE, NORMAL, PERFECT, MISS }

const MAX_HEALTH := 7
const BPM := 130.0
const BEAT_SECONDS := 60.0 / BPM
const INPUT_BEATS := 8
# The first counted beat arrives after one beat of lead-in. Each visible
# cell lasts a full beat, including the yellow eighth (Perfect) cell.
const LEAD_IN_SECONDS := BEAT_SECONDS
const PERFECT_START_SECONDS := INPUT_BEATS * BEAT_SECONDS
const INPUT_SECONDS := (INPUT_BEATS + 1) * BEAT_SECONDS
const PLAYER_SEQUENCE := [Weapon.SWORD, Weapon.SHIELD, Weapon.GREATSWORD]
const BOSS_SEQUENCE := [Weapon.SHIELD, Weapon.SWORD]

class Fighter:
	var health := MAX_HEALTH
	var weapon: Weapon
	var charged := false
	var charged_perfect := false

	func _init(initial_weapon: Weapon = Weapon.SWORD) -> void:
		weapon = initial_weapon

	func switch_weapon(sequence: Array) -> void:
		weapon = sequence[(sequence.find(weapon) + 1) % sequence.size()]
		charged = false
		charged_perfect = false

	func resolve_action(perfect: bool = false) -> Dictionary:
		match weapon:
			Weapon.SHIELD:
				return {"action": Action.GUARD, "perfect": perfect}
			Weapon.GREATSWORD:
				if not charged:
					charged = true
					charged_perfect = perfect
					return {"action": Action.WINDUP, "perfect": false}
				charged = false
				var heavy_perfect := perfect or charged_perfect
				charged_perfect = false
				return {"action": Action.HEAVY_ATTACK, "perfect": heavy_perfect}
			_:
				return {"action": Action.SWORD, "perfect": perfect}

static func timeline_slot(now: float, round_start: float = 0.0) -> int:
	if now < round_start + LEAD_IN_SECONDS or now >= round_start + INPUT_SECONDS:
		return -1
	# Compare absolute beat boundaries to avoid cancellation at later rounds.
	for beat in range(INPUT_BEATS, 0, -1):
		if now >= round_start + beat * BEAT_SECONDS:
			return beat - 1
	return -1

static func judge_input(now: float, round_start: float = 0.0) -> Judgment:
	var slot := timeline_slot(now, round_start)
	if slot < 0:
		return Judgment.MISS
	return Judgment.PERFECT if slot == INPUT_BEATS - 1 else Judgment.NORMAL

static func damage_taken(own_action: Action, opponent_action: Action,
		own_perfect: bool = false, opponent_perfect: bool = false) -> int:
	if opponent_action == Action.HEAVY_ATTACK:
		return (3 if own_action == Action.GUARD else 5) + int(opponent_perfect)
	if opponent_action == Action.SWORD and own_action != Action.GUARD:
		return 2 + int(opponent_perfect)
	if own_action == Action.SWORD and opponent_action == Action.GUARD:
		# Perfect sword incurs extra recoil; Perfect shield adds reflection.
		return 1 + int(own_perfect) + int(opponent_perfect)
	return 0

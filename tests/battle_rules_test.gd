extends SceneTree

# Run from the project root:
# godot --headless --path . --script res://tests/battle_rules_test.gd
const Rules = preload("res://scripts/battle_rules.gd")

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	_test_input_windows()
	_test_base_damage()
	_test_perfect_damage()
	_test_weapon_sequences()
	_test_greatsword_charge()
	if failures.is_empty():
		print("PASS: %d battle rule checks" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: %d of %d battle rule checks" % [failures.size(), checks])
		quit(1)


func _expect_equal(actual: Variant, expected: Variant, description: String) -> void:
	checks += 1
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [description, str(expected), str(actual)])


func _test_input_windows() -> void:
	_expect_equal(is_equal_approx(Rules.LEAD_IN_SECONDS, Rules.BEAT_SECONDS), true, "One hidden lead-in beat")
	_expect_equal(is_equal_approx(Rules.PERFECT_START_SECONDS, 8.0 * 60.0 / 130.0), true, "Yellow cell begins on beat eight")
	_expect_equal(is_equal_approx(Rules.INPUT_SECONDS - Rules.PERFECT_START_SECONDS, Rules.BEAT_SECONDS), true, "Perfect occupies the entire yellow beat")
	for round_index in [0, 1, 9, 99]:
		var start: float = round_index * 11.0 * Rules.BEAT_SECONDS
		_expect_equal(Rules.timeline_slot(start, start), -1, "Cursor hidden before first beat, round %d" % round_index)
		_expect_equal(Rules.judge_input(start, start), Rules.Judgment.MISS, "No input slot during lead-in")
		_expect_equal(Rules.timeline_slot(start + Rules.LEAD_IN_SECONDS - 0.000001, start), -1, "Cursor hidden until first downbeat")
		for slot in range(8):
			var boundary: float = start + (slot + 1) * Rules.BEAT_SECONDS
			var expected: int = Rules.Judgment.PERFECT if slot == 7 else Rules.Judgment.NORMAL
			_expect_equal(Rules.timeline_slot(boundary, start), slot, "Exact downbeat selects cell %d round %d" % [slot, round_index])
			_expect_equal(Rules.judge_input(boundary, start), expected, "Downbeat judgment matches displayed cell")
			_expect_equal(Rules.timeline_slot(boundary + Rules.BEAT_SECONDS * 0.5, start), slot, "Cell remains for entire beat")
			_expect_equal(Rules.judge_input(boundary + Rules.BEAT_SECONDS * 0.5, start), expected, "Midbeat judgment matches displayed cell")
		_expect_equal(Rules.judge_input(start + Rules.PERFECT_START_SECONDS - 0.000001, start), Rules.Judgment.NORMAL, "Immediately before yellow remains Normal")
		_expect_equal(Rules.judge_input(start + Rules.INPUT_SECONDS - 0.000001, start), Rules.Judgment.PERFECT, "Last instant of yellow remains Perfect")
		_expect_equal(Rules.timeline_slot(start + Rules.INPUT_SECONDS, start), -1, "Cursor disappears at exact eighth-cell end")
		_expect_equal(Rules.judge_input(start + Rules.INPUT_SECONDS, start), Rules.Judgment.MISS, "Exact eighth-cell end is no longer Perfect")
		_expect_equal(Rules.judge_input(start + Rules.INPUT_SECONDS + 0.000001, start), Rules.Judgment.MISS, "Immediately after phase is Miss")
	_expect_equal(Rules.judge_input(-0.001), Rules.Judgment.MISS, "Input before phase")
	_expect_equal(Rules.judge_input(Rules.INPUT_SECONDS + 10.0), Rules.Judgment.MISS, "Very late input")


func _test_base_damage() -> void:
	var actions: Array = [Rules.Action.SWORD, Rules.Action.GUARD, Rules.Action.WINDUP, Rules.Action.HEAVY_ATTACK]
	# Rows are own action; columns are opponent action. Values are own HP loss.
	var expected: Array = [[2, 1, 0, 5], [0, 0, 0, 3], [2, 0, 0, 5], [2, 0, 0, 5]]
	for own in range(actions.size()):
		for opponent in range(actions.size()):
			_expect_equal(
				Rules.damage_taken(actions[own], actions[opponent]), expected[own][opponent],
				"Normal damage own=%d opponent=%d" % [own, opponent])


func _test_perfect_damage() -> void:
	for action in [Rules.Action.SWORD, Rules.Action.WINDUP, Rules.Action.HEAVY_ATTACK]:
		_expect_equal(Rules.damage_taken(action, Rules.Action.SWORD, false, true), 3, "Perfect sword deals 3 to unguarded action %d" % action)
		_expect_equal(Rules.damage_taken(action, Rules.Action.HEAVY_ATTACK, false, true), 6, "Perfect heavy deals 6 to unguarded action %d" % action)
	_expect_equal(Rules.damage_taken(Rules.Action.GUARD, Rules.Action.SWORD, false, true), 0, "Guard fully blocks Perfect sword")
	_expect_equal(Rules.damage_taken(Rules.Action.GUARD, Rules.Action.HEAVY_ATTACK, false, true), 4, "Guard takes 4 from Perfect heavy")
	_expect_equal(Rules.damage_taken(Rules.Action.SWORD, Rules.Action.GUARD, true, false), 2, "Perfect sword receives extra reflection")
	_expect_equal(Rules.damage_taken(Rules.Action.SWORD, Rules.Action.GUARD, false, true), 2, "Perfect shield adds reflection")
	_expect_equal(Rules.damage_taken(Rules.Action.SWORD, Rules.Action.GUARD, true, true), 3, "Both reflection bonuses stack")
	_expect_equal(Rules.damage_taken(Rules.Action.HEAVY_ATTACK, Rules.Action.GUARD, true, true), 0, "Shield does not reflect a heavy attack under existing rules")
	_expect_equal(Rules.damage_taken(Rules.Action.GUARD, Rules.Action.HEAVY_ATTACK, true, false), 3, "Perfect shield keeps base heavy mitigation")
	_expect_equal(Rules.damage_taken(Rules.Action.SWORD, Rules.Action.SWORD, true, false), 2, "Own Perfect attack grants no incoming-damage reduction")
	_expect_equal(Rules.damage_taken(Rules.Action.SWORD, Rules.Action.WINDUP, false, true), 0, "Perfect windup deals no premature damage")


func _test_weapon_sequences() -> void:
	var player = Rules.Fighter.new()
	var player_sequence: Array = [Rules.Weapon.SWORD, Rules.Weapon.SHIELD, Rules.Weapon.GREATSWORD]
	_expect_equal(player.health, 7, "Player starts with 7 HP")
	_expect_equal(player.weapon, Rules.Weapon.SWORD, "Player starts with sword")
	for expected in [Rules.Weapon.SHIELD, Rules.Weapon.GREATSWORD, Rules.Weapon.SWORD, Rules.Weapon.SHIELD]:
		player.switch_weapon(player_sequence)
		_expect_equal(player.weapon, expected, "Player advances exactly one weapon")
	var boss = Rules.Fighter.new(Rules.Weapon.SHIELD)
	var boss_sequence: Array = [Rules.Weapon.SHIELD, Rules.Weapon.SWORD]
	_expect_equal(boss.health, 7, "Boss starts with 7 HP")
	_expect_equal(boss.weapon, Rules.Weapon.SHIELD, "Boss starts with shield")
	for expected in [Rules.Weapon.SWORD, Rules.Weapon.SHIELD, Rules.Weapon.SWORD, Rules.Weapon.SHIELD]:
		boss.switch_weapon(boss_sequence)
		_expect_equal(boss.weapon, expected, "Boss alternates without a greatsword")
	var result: Dictionary = boss.resolve_action()
	_expect_equal(result.action, Rules.Action.GUARD, "Shield resolves as guard")
	_expect_equal(result.perfect, false, "Normal guard has no Perfect bonus")
	result = player.resolve_action(true)
	_expect_equal(result.action, Rules.Action.GUARD, "Perfect shield resolves as guard")
	_expect_equal(result.perfect, true, "Perfect guard carries its bonus")
	player.switch_weapon(player_sequence)
	player.switch_weapon(player_sequence)
	result = player.resolve_action(true)
	_expect_equal(result.action, Rules.Action.SWORD, "Sword resolves as sword")
	_expect_equal(result.perfect, true, "Perfect sword carries its bonus")
	result = player.resolve_action()
	_expect_equal(result.perfect, false, "Sword Perfect bonus does not leak to next round")


func _test_greatsword_charge() -> void:
	var fighter = Rules.Fighter.new(Rules.Weapon.GREATSWORD)
	var result: Dictionary = fighter.resolve_action(true)
	_expect_equal(result.action, Rules.Action.WINDUP, "New greatsword must charge first")
	_expect_equal(fighter.charged, true, "Windup leaves charge ready")
	_expect_equal(fighter.charged_perfect, true, "Perfect switch is retained through windup")
	result = fighter.resolve_action()
	_expect_equal(result.action, Rules.Action.HEAVY_ATTACK, "Second held round releases heavy attack")
	_expect_equal(result.perfect, true, "Saved Perfect strengthens the released attack")
	_expect_equal(fighter.charged, false, "Heavy attack consumes charge")
	_expect_equal(fighter.charged_perfect, false, "Heavy attack consumes saved Perfect")
	result = fighter.resolve_action()
	_expect_equal(result.action, Rules.Action.WINDUP, "Third held round charges again")
	result = fighter.resolve_action()
	_expect_equal(result.action, Rules.Action.HEAVY_ATTACK, "Fourth held round attacks again")
	_expect_equal(result.perfect, false, "Later heavy attack does not reuse old Perfect")
	fighter.resolve_action(true)
	fighter.switch_weapon([Rules.Weapon.SWORD, Rules.Weapon.SHIELD, Rules.Weapon.GREATSWORD])
	_expect_equal(fighter.weapon, Rules.Weapon.SWORD, "Switching out of greatsword goes to sword")
	_expect_equal(fighter.charged, false, "Switching cancels charge")
	_expect_equal(fighter.charged_perfect, false, "Switching cancels stored Perfect")
	fighter.switch_weapon([Rules.Weapon.SWORD, Rules.Weapon.SHIELD, Rules.Weapon.GREATSWORD])
	fighter.switch_weapon([Rules.Weapon.SWORD, Rules.Weapon.SHIELD, Rules.Weapon.GREATSWORD])
	result = fighter.resolve_action()
	_expect_equal(result.action, Rules.Action.WINDUP, "Re-entered greatsword charges from scratch")
	result = fighter.resolve_action()
	_expect_equal(result.perfect, false, "Canceled Perfect does not return after re-equipping")

extends SceneTree

const Rules = preload("res://scripts/battle_rules.gd")
const Scene = preload("res://scenes/battle.tscn")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)

func make_battle():
	var battle = Scene.instantiate()
	root.add_child(battle)
	battle.set_process(false)
	return battle

func dispose(battle) -> void:
	# Audio playback starts on the mixer thread; allow its first block to run
	# before stopping/freeing a scene in these accelerated boundary tests.
	await create_timer(0.04).timeout
	battle.music.stop()
	await create_timer(0.04).timeout
	battle.free()

func snapshot(label: String) -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(args[0].path_join(label + ".png"))

func _run() -> void:
	var b = make_battle()
	check(b.state == b.State.WAITING, "opens waiting")
	check(b.player_sprite.animation == &"unarmed_idle" and b.boss_sprite.animation == &"unarmed_idle", "intro animations")
	check(not b.music.playing and not b.timeline.visible and b.start_prompt.visible, "intro visibility and silence")
	await snapshot("intro")
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_SHIFT
	b._unhandled_key_input(key)
	check(b.music.playing and b.timeline.visible and not b.start_prompt.visible, "Shift starts music and battle")
	check(b.player.weapon == Rules.Weapon.SWORD and b.boss.weapon == Rules.Weapon.SHIELD, "initial loadout")
	check(b.player_sprite.animation == &"sword_idle" and b.boss_sprite.animation == &"shield_idle", "initial idle animations")
	check(not b.cursor.visible, "cursor hidden before first beat")
	key.echo = true
	b._unhandled_key_input(key)
	check(not b.input_consumed, "key repeat ignored")
	b._handle_shift(Rules.LEAD_IN_SECONDS - 0.000001)
	check(not b.input_consumed and b.player.weapon == Rules.Weapon.SWORD, "lead-in input ignored without consuming switch")
	await snapshot("battle")
	for i in range(8):
		b._advance_to_time((i + 1) * Rules.BEAT_SECONDS)
		check(b.cursor.visible and b.cursor.position.x == 1 + i * 2, "downbeat displays timeline cell %d" % i)
		if i == 0:
			await snapshot("first_beat")
		elif i == 6:
			await snapshot("seventh_beat")
	b._handle_shift(Rules.PERFECT_START_SECONDS)
	check(b.judgment == Rules.Judgment.PERFECT and b.player.weapon == Rules.Weapon.SHIELD, "yellow downbeat immediately accepts Perfect")
	await snapshot("perfect")
	b._handle_shift(Rules.PERFECT_START_SECONDS + 0.2)
	check(b.player.weapon == Rules.Weapon.SHIELD, "only one switch per round")
	b._advance_to_time(Rules.INPUT_SECONDS - 0.000001)
	check(b.turns_completed == 0 and b.cursor.visible, "yellow lasts through its whole beat")
	b._advance_to_time(Rules.INPUT_SECONDS)
	check(b.turns_completed == 1 and b.player.health == 7 and b.boss.health == 7, "shield versus shield settles once at yellow end")
	check(not b.cursor.visible, "cursor hides during settlement")
	b._advance_to_time(b.ROUND_SECONDS)
	check(b.state == b.State.INPUT and b.boss.weapon == Rules.Weapon.SWORD and b.judgment == Rules.Judgment.NONE, "next round resets and boss alternates")
	check(not b.cursor.visible, "new round begins with hidden lead-in")
	b._handle_shift(b.round_start + Rules.LEAD_IN_SECONDS)
	check(b.judgment == Rules.Judgment.NORMAL and b.player.weapon == Rules.Weapon.GREATSWORD, "first beat accepts Normal switch to heavy")
	b._advance_to_time(b.round_start + Rules.INPUT_SECONDS)
	check(b.player.charged and b.player_sprite.animation == &"greatsword_windup", "heavy winds up")
	b._advance_to_time(2 * b.ROUND_SECONDS)
	b._advance_to_time(b.round_start + Rules.INPUT_SECONDS)
	check(not b.player.charged and b.player_sprite.animation == &"greatsword_attack" and b.boss.health == 4, "held heavy attacks shield next round")
	await dispose(b)

	for round_index in [0, 1, 9, 99]:
		b = make_battle()
		b._start_battle()
		b.round_start = round_index * b.ROUND_SECONDS
		b._advance_to_time(b.round_start + Rules.LEAD_IN_SECONDS - 0.000001)
		check(not b.cursor.visible, "later-round lead-in hides cursor, round %d" % round_index)
		for slot in range(8):
			b._advance_to_time(b.round_start + (slot + 1) * Rules.BEAT_SECONDS)
			check(b.cursor.visible and b.cursor.position.x == 1 + slot * 2, "exact cell boundary round %d cell %d" % [round_index, slot])
		b._advance_to_time(b.round_start + Rules.INPUT_SECONDS)
		check(not b.cursor.visible and b.state == b.State.RESOLVING, "exact phase end hides cursor and resolves, round %d" % round_index)
		await dispose(b)
		for boundary in [Rules.PERFECT_START_SECONDS, Rules.PERFECT_START_SECONDS + Rules.BEAT_SECONDS * 0.5, Rules.INPUT_SECONDS - 0.000001]:
			b = make_battle()
			b._start_battle()
			b.round_start = round_index * b.ROUND_SECONDS
			b._handle_shift(b.round_start + boundary)
			check(b.judgment == Rules.Judgment.PERFECT and b.cursor.visible and b.cursor.position.x == 15, "every instant of yellow is Perfect, round %d offset %f" % [round_index, boundary])
			await dispose(b)
		b = make_battle()
		b._start_battle()
		b.round_start = round_index * b.ROUND_SECONDS
		b._handle_shift(b.round_start + Rules.INPUT_SECONDS)
		check(b.judgment == Rules.Judgment.MISS and not b.cursor.visible and b.player.weapon == Rules.Weapon.SWORD, "exact end is Miss with no cursor, round %d" % round_index)
		await dispose(b)

	b = make_battle()
	b._start_battle()
	b._handle_shift(Rules.INPUT_SECONDS + 0.001)
	check(b.judgment == Rules.Judgment.MISS and b.player.weapon == Rules.Weapon.SWORD, "late input misses and retains sword")
	check(b.turns_completed == 1 and b.player.health == 6, "late input cannot alter settled damage")
	await snapshot("miss")
	await dispose(b)

	b = make_battle()
	b._start_battle()
	for i in range(5):
		b._advance_to_time(i * b.ROUND_SECONDS)
		b._advance_to_time(i * b.ROUND_SECONDS + Rules.INPUT_SECONDS)
	check(b.player.weapon == Rules.Weapon.SWORD and b.judgment == Rules.Judgment.NONE, "no input retains weapon without Miss")
	check(b.player.health == 0 and b.boss.health == 3, "no input damage through five rounds")
	b._advance_to_time(b.result_time)
	check(b.state == b.State.FINISHED and b.battle_result == "Defeat" and not b.music.playing, "death ends battle and music")
	await snapshot("result")
	await dispose(b)

	for ending in ["Victory", "Draw"]:
		b = make_battle()
		b._start_battle()
		b.player.health = 2 if ending == "Draw" else 7
		b.boss.health = 2
		b.boss.weapon = Rules.Weapon.SWORD
		b._advance_to_time(Rules.INPUT_SECONDS)
		b._advance_to_time(b.result_time)
		check(b.battle_result == ending, "simultaneous damage ending " + ending)
		await dispose(b)

	# Let the audio mixer release streams from the rapidly freed test scenes.
	await create_timer(0.2).timeout
	if failures.is_empty():
		print("PASS: %d battle scene checks" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

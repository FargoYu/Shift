extends Node2D

const Rules = preload("res://scripts/battle_rules.gd")
enum State { WAITING, INPUT, RESOLVING, FINISHED }

# One beat of lead-in, eight displayed cells, then two beats for actions.
# Every round stays on the music grid; the yellow cell is the Perfect window.
const ROUND_BEATS := Rules.INPUT_BEATS + 3
const ROUND_SECONDS := ROUND_BEATS * Rules.BEAT_SECONDS
const SLOT_WIDTH := 2
const PERFECT_COLOR := Color("ffe08a")

## Track downbeat offset, measured from the beginning of the audio file.
@export var beat_offset_seconds := 0.0

var state := State.WAITING
var player := Rules.Fighter.new(Rules.Weapon.SWORD)
var boss := Rules.Fighter.new(Rules.Weapon.SHIELD)
var turns_completed := 0
var round_start := 0.0
var input_consumed := false
var judgment := Rules.Judgment.NONE
var battle_result := ""
var pending_result := ""
var result_time := 0.0
var _audio_latency := 0.0
var _audio_length := 0.0
var _audio_loop_offset := 0.0
var _last_playback := 0.0
var _last_music_time := 0.0

@onready var player_sprite: AnimatedSprite2D = $Player
@onready var boss_sprite: AnimatedSprite2D = $Boss
@onready var player_fill: Sprite2D = $PlayerHealth/Fill
@onready var boss_fill: Sprite2D = $BossHealth/Fill
@onready var timeline: Sprite2D = $Timeline
@onready var cursor: Sprite2D = $Timeline/Cursor
@onready var start_prompt: Label = $StartPrompt
@onready var feedback: Label = $Feedback
@onready var result_label: Label = $Result
@onready var music: AudioStreamPlayer = $Music

func _ready() -> void:
	$PlayerHealth.hide()
	$BossHealth.hide()
	timeline.hide()
	feedback.hide()
	result_label.hide()
	start_prompt.show()
	player_sprite.play(&"unarmed_idle")
	boss_sprite.play(&"unarmed_idle")
	player_sprite.animation_finished.connect(_on_action_finished.bind(player_sprite, player))
	boss_sprite.animation_finished.connect(_on_action_finished.bind(boss_sprite, boss))
	if music.stream is AudioStreamMP3:
		music.stream = music.stream.duplicate()
		music.stream.loop = true
	_audio_latency = AudioServer.get_output_latency()
	_audio_length = music.stream.get_length()
	_update_health()

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != KEY_SHIFT:
		return
	get_viewport().set_input_as_handled()
	if state == State.WAITING:
		_start_battle()
	elif state != State.FINISHED:
		_handle_shift(_music_time())

func _start_battle() -> void:
	start_prompt.hide()
	player_sprite.position = Vector2(42, 54)
	boss_sprite.position = Vector2(118, 54)
	$PlayerHealth.show()
	$BossHealth.show()
	timeline.show()
	feedback.show()
	round_start = beat_offset_seconds
	music.play()
	_begin_round()

func _process(_delta: float) -> void:
	if state == State.WAITING or state == State.FINISHED:
		return
	_advance_to_time(_music_time())

func _music_time() -> float:
	# Compensate the audio hardware clock for mix granularity and output latency.
	var playback := music.get_playback_position()
	if _audio_length > 0.0 and playback < _last_playback - _audio_length * 0.5:
		_audio_loop_offset += _audio_length
	_last_playback = playback
	var audible := _audio_loop_offset + playback + AudioServer.get_time_since_last_mix() - _audio_latency
	_last_music_time = maxf(_last_music_time, audible)
	return _last_music_time

func _advance_to_time(now: float) -> void:
	# Catch up using absolute timestamps, never by adding frame delta.
	while state != State.WAITING and state != State.FINISHED:
		if state == State.INPUT:
			_update_timeline(now)
			if now < round_start + Rules.INPUT_SECONDS:
				return
			_resolve_round(now)
		else:
			if not pending_result.is_empty():
				if now >= result_time:
					_end_battle(pending_result)
				return
			if now < round_start + ROUND_SECONDS:
				return
			round_start += ROUND_SECONDS
			boss.switch_weapon(Rules.BOSS_SEQUENCE)
			_begin_round()

func _handle_shift(now: float) -> void:
	# Check deadlines here too; input and rendering may run in either order.
	_advance_to_time(now)
	if state == State.FINISHED or input_consumed:
		return
	if now < round_start + Rules.LEAD_IN_SECONDS:
		return
	if state == State.RESOLVING:
		input_consumed = true
		_set_judgment(Rules.Judgment.MISS)
		return
	input_consumed = true
	# Rendering and input share the same cell calculation and absolute bounds.
	_set_judgment(Rules.judge_input(now, round_start))
	if judgment == Rules.Judgment.NORMAL or judgment == Rules.Judgment.PERFECT:
		player.switch_weapon(Rules.PLAYER_SEQUENCE)
		_play_idle(player_sprite, player)

func _begin_round() -> void:
	state = State.INPUT
	input_consumed = false
	judgment = Rules.Judgment.NONE
	feedback.text = ""
	cursor.hide()
	cursor.position.x = 1
	cursor.modulate = Color.WHITE
	_play_idle(player_sprite, player)
	_play_idle(boss_sprite, boss)

func _update_timeline(now: float) -> void:
	var slot := Rules.timeline_slot(now, round_start)
	cursor.visible = slot >= 0
	if slot < 0:
		return
	cursor.position.x = 1 + slot * SLOT_WIDTH
	cursor.modulate = PERFECT_COLOR if slot == Rules.INPUT_BEATS - 1 else Color.WHITE

func _set_judgment(value: Rules.Judgment) -> void:
	judgment = value
	match value:
		Rules.Judgment.NORMAL:
			feedback.text = "Normal"
			feedback.add_theme_color_override("font_color", Color("1f2930"))
		Rules.Judgment.PERFECT:
			feedback.text = "Perfect"
			feedback.add_theme_color_override("font_color", Color("694000"))
		Rules.Judgment.MISS:
			feedback.text = "Miss"
			feedback.add_theme_color_override("font_color", Color("852638"))

func _resolve_round(now: float) -> void:
	state = State.RESOLVING
	cursor.hide()
	var player_action := player.resolve_action(judgment == Rules.Judgment.PERFECT)
	var boss_action := boss.resolve_action()
	_play_action(player_sprite, player_action.action, false)
	_play_action(boss_sprite, boss_action.action, true)
	var player_damage := Rules.damage_taken(player_action.action, boss_action.action,
		player_action.perfect, boss_action.perfect)
	var boss_damage := Rules.damage_taken(boss_action.action, player_action.action,
		boss_action.perfect, player_action.perfect)
	player.health = maxi(0, player.health - player_damage)
	boss.health = maxi(0, boss.health - boss_damage)
	_update_health()
	turns_completed += 1
	if player.health == 0 and boss.health == 0:
		pending_result = "Draw"
	elif boss.health == 0:
		pending_result = "Victory"
	elif player.health == 0:
		pending_result = "Defeat"
	# Allow the final action to finish before displaying the result.
	result_time = now + 0.6

func _play_idle(sprite: AnimatedSprite2D, fighter: Rules.Fighter) -> void:
	match fighter.weapon:
		Rules.Weapon.SWORD:
			sprite.play(&"sword_idle")
		Rules.Weapon.SHIELD:
			sprite.play(&"shield_idle")
		Rules.Weapon.GREATSWORD:
			sprite.play(&"greatsword_idle")

func _play_action(sprite: AnimatedSprite2D, action: Rules.Action, is_boss: bool) -> void:
	match action:
		Rules.Action.SWORD:
			sprite.play(&"sword_attack")
		Rules.Action.GUARD:
			sprite.play(&"shield_block" if is_boss else &"shield_guard")
		Rules.Action.WINDUP:
			sprite.play(&"greatsword_windup")
		Rules.Action.HEAVY_ATTACK:
			sprite.play(&"greatsword_attack")

func _on_action_finished(sprite: AnimatedSprite2D, fighter: Rules.Fighter) -> void:
	if state != State.FINISHED and fighter.health > 0:
		_play_idle(sprite, fighter)

func _update_health() -> void:
	player_fill.visible = player.health > 0
	player_fill.region_rect.size.x = player.health * 2
	boss_fill.visible = boss.health > 0
	boss_fill.region_rect.size.x = boss.health * 2

func _end_battle(result: String) -> void:
	state = State.FINISHED
	battle_result = result
	music.stop()
	timeline.hide()
	feedback.hide()
	result_label.text = result
	result_label.show()
	print("SHIFT: ", result)

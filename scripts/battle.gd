extends Node2D

enum State { WAITING, RUNNING, FINISHED }
enum Weapon { SWORD, SHIELD, GREATSWORD }
enum Pose { SWORD, GUARD, WINDUP, HEAVY_ATTACK }

const SECONDS_PER_TURN := 3
const TURN_COUNT := 22
const SLOT_WIDTH := 2
const MAX_HEALTH := 7
const PLAYER_POSES: Array[Texture2D] = [
	preload("res://assets/character_related/player/sword_attack.png"),
	preload("res://assets/character_related/player/shield_guard.png"),
	preload("res://assets/character_related/player/greatsword_windup.png"),
	preload("res://assets/character_related/player/greatsword_attack.png"),
]
const BOSS_POSES: Array[Texture2D] = [
	preload("res://assets/character_related/boss/sword_attack.png"),
	preload("res://assets/character_related/boss/shield_guard.png"),
	preload("res://assets/character_related/boss/greatsword_windup.png"),
	preload("res://assets/character_related/boss/greatsword_attack.png"),
]


class Fighter:
	var health := MAX_HEALTH
	var weapon := Weapon.SWORD
	var charged := false

	func switch_weapon() -> void:
		weapon = ((weapon + 1) % Weapon.size()) as Weapon
		charged = false

	func held_pose() -> Pose:
		match weapon:
			Weapon.SHIELD:
				return Pose.GUARD
			Weapon.GREATSWORD:
				return Pose.WINDUP
			_:
				return Pose.SWORD

	func resolve_action() -> Pose:
		if weapon != Weapon.GREATSWORD:
			return held_pose()
		charged = not charged
		return Pose.WINDUP if charged else Pose.HEAVY_ATTACK


var state := State.WAITING
var player := Fighter.new()
var boss := Fighter.new()
var turns_completed := 0
var seconds_remaining := SECONDS_PER_TURN
var player_switched := false

@onready var player_sprite: Sprite2D = $Player
@onready var boss_sprite: Sprite2D = $Boss
@onready var player_fill: Sprite2D = $PlayerHealth/Fill
@onready var boss_fill: Sprite2D = $BossHealth/Fill
@onready var countdown: Sprite2D = $Countdown
@onready var cursor: Sprite2D = $Timeline/Cursor
@onready var second_timer: Timer = $SecondTimer


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != KEY_SHIFT:
		return

	if state == State.WAITING:
		state = State.RUNNING
		_begin_turn()
		second_timer.start()
	elif state == State.RUNNING and not player_switched:
		player.switch_weapon()
		player_sprite.texture = PLAYER_POSES[player.held_pose()]
		player_switched = true


func _begin_turn(show_boss_pose: bool = true) -> void:
	seconds_remaining = SECONDS_PER_TURN
	_update_countdown()
	player_switched = false
	if randf() < 0.5:
		boss.switch_weapon()
	if show_boss_pose:
		boss_sprite.texture = BOSS_POSES[boss.held_pose()]


func _on_second_elapsed() -> void:
	seconds_remaining -= 1
	if seconds_remaining == 0:
		_finish_turn()
		return

	_update_countdown()
	player_sprite.texture = PLAYER_POSES[player.held_pose()]
	boss_sprite.texture = BOSS_POSES[boss.held_pose()]


func _finish_turn() -> void:
	var player_action := player.resolve_action()
	var boss_action := boss.resolve_action()
	player_sprite.texture = PLAYER_POSES[player_action]
	boss_sprite.texture = BOSS_POSES[boss_action]

	player.health = maxi(0, player.health - _damage_taken(player_action, boss_action))
	boss.health = maxi(0, boss.health - _damage_taken(boss_action, player_action))
	_update_health_fill(player_fill, player.health)
	_update_health_fill(boss_fill, boss.health)

	turns_completed += 1
	if turns_completed < TURN_COUNT:
		cursor.position.x += SLOT_WIDTH

	if player.health == 0 and boss.health == 0:
		_end_battle("Draw")
	elif boss.health == 0:
		_end_battle("Victory")
	elif player.health == 0:
		_end_battle("Defeat")
	elif turns_completed == TURN_COUNT:
		_end_battle("Draw")
	else:
		_begin_turn(boss_action != Pose.HEAVY_ATTACK)


func _damage_taken(own_action: Pose, opponent_action: Pose) -> int:
	if opponent_action == Pose.HEAVY_ATTACK:
		return 3 if own_action == Pose.GUARD else 5
	if opponent_action == Pose.SWORD and own_action != Pose.GUARD:
		return 2
	if own_action == Pose.SWORD and opponent_action == Pose.GUARD:
		return 1
	return 0


func _update_health_fill(fill: Sprite2D, health: int) -> void:
	fill.visible = health > 0
	fill.region_rect.size.x = health * 2


func _update_countdown() -> void:
	countdown.region_rect.position.x = (SECONDS_PER_TURN - seconds_remaining) * 3


func _end_battle(result: String) -> void:
	state = State.FINISHED
	second_timer.stop()
	countdown.hide()
	print("SHIFT: ", result)

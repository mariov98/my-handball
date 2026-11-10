extends Node3D
class_name MatchController

## Routes input, possession, team switch, scoring, and reset for Phase 0.

enum AimMode { FACE, MOUSE_COURT }

const SHOOT_IMPULSE := 16.0
const RESET_DELAY := 1.6

@export var home_team_path: NodePath
@export var away_team_path: NodePath
@export var ball_path: NodePath
@export var camera_rig_path: NodePath
@export var hud_path: NodePath
@export var player_scene: PackedScene

var aim_mode: AimMode = AimMode.FACE
var controlled_player: Player = null
var controlled_team_id: int = 0
var score_home: int = 0
var score_away: int = 0
var _resetting: bool = false
var _home_players: Array[Player] = []
var _away_players: Array[Player] = []
## Last team that possessed the ball — camera stays behind them while the ball is free.
var _attack_team_id: int = 0

@onready var _home_root: Node = get_node(home_team_path)
@onready var _away_root: Node = get_node(away_team_path)
@onready var ball: Ball = get_node(ball_path)
@onready var camera_rig: CameraRig = get_node(camera_rig_path)
@onready var hud: CanvasLayer = get_node(hud_path)


func _ready() -> void:
	_spawn_roster()
	_collect_players()
	_wire_goals()
	var starter := _first_outfield(_home_players)
	if starter:
		_set_controlled(starter)
	elif not _home_players.is_empty():
		_set_controlled(_home_players[0])
	camera_rig.setup(ball, true)
	if hud and hud.has_method("set_score"):
		hud.set_score(score_home, score_away)
	if hud and hud.has_method("set_aim_mode"):
		hud.set_aim_mode(_aim_mode_label())
	print("MyHandball Phase 0 ready. Controls: WASD/stick camera-relative move, Space/A jump, LMB/RT/E shoot, Q/Tab/bumpers switch, T/Y aim mode.")
	var user_args := OS.get_cmdline_user_args()
	if "--screenshot-demo" in user_args:
		var demo := load("res://scripts/screenshot_demo.gd") as GDScript
		var dn := Node.new()
		dn.set_script(demo)
		add_child(dn)
	elif "--screenshot" in user_args:
		var shot := load("res://scripts/screenshot_once.gd") as GDScript
		var sn := Node.new()
		sn.set_script(shot)
		add_child(sn)
	if "--smoke" in user_args:
		var smoke := load("res://scripts/smoke_test.gd") as GDScript
		var node := Node.new()
		node.set_script(smoke)
		add_child(node)


func _spawn_roster() -> void:
	if player_scene == null:
		player_scene = load("res://scenes/actors/player.tscn") as PackedScene
	# Home attacks +Z (toward away goal). Layout: GK near own goal, 3 outfield.
	var home_color := Color(0.2, 0.45, 0.95)
	var away_color := Color(0.9, 0.25, 0.22)
	var home_spots: Array = [
		{"pos": Vector3(0, 0, -17.5), "yaw": 0.0, "gk": true, "idx": 0},
		{"pos": Vector3(-3.5, 0, -6.0), "yaw": 0.0, "gk": false, "idx": 1},
		{"pos": Vector3(0.0, 0, -4.0), "yaw": 0.0, "gk": false, "idx": 2},
		{"pos": Vector3(3.5, 0, -6.0), "yaw": 0.0, "gk": false, "idx": 3},
	]
	var away_spots: Array = [
		{"pos": Vector3(0, 0, 17.5), "yaw": PI, "gk": true, "idx": 0},
		{"pos": Vector3(3.5, 0, 6.0), "yaw": PI, "gk": false, "idx": 1},
		{"pos": Vector3(0.0, 0, 4.0), "yaw": PI, "gk": false, "idx": 2},
		{"pos": Vector3(-3.5, 0, 6.0), "yaw": PI, "gk": false, "idx": 3},
	]
	for spot in home_spots:
		_spawn_player(_home_root, 0, home_color, spot)
	for spot in away_spots:
		_spawn_player(_away_root, 1, away_color, spot)


func _spawn_player(parent: Node, team_id: int, color: Color, spot: Dictionary) -> void:
	var p := player_scene.instantiate() as Player
	p.team_id = team_id
	p.is_goalkeeper = spot["gk"]
	p.player_index = spot["idx"]
	p.body_color = color.darkened(0.15) if spot["gk"] else color
	p.name = "%s_%s%d" % [
		"Home" if team_id == 0 else "Away",
		"GK" if spot["gk"] else "OF",
		spot["idx"] + 1
	]
	parent.add_child(p)
	p.global_position = spot["pos"]
	p.rotation.y = spot["yaw"]
	p.start_position = spot["pos"]
	p.start_yaw = spot["yaw"]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_aim_mode"):
		aim_mode = AimMode.MOUSE_COURT if aim_mode == AimMode.FACE else AimMode.FACE
		if hud and hud.has_method("set_aim_mode"):
			hud.set_aim_mode(_aim_mode_label())
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("switch_player"):
		_cycle_teammate()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("shoot") and not _resetting:
		_try_shoot()
		get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
	_update_camera_attack_side()


func _collect_players() -> void:
	_home_players.clear()
	_away_players.clear()
	for child in _home_root.get_children():
		if child is Player:
			_home_players.append(child)
	for child in _away_root.get_children():
		if child is Player:
			_away_players.append(child)


func _wire_goals() -> void:
	for goal in get_tree().get_nodes_in_group("goals"):
		if goal is GoalArea:
			(goal as GoalArea).goal_scored.connect(_on_goal_scored)


func _set_controlled(player: Player) -> void:
	if controlled_player:
		controlled_player.controlled = false
	controlled_player = player
	controlled_team_id = player.team_id
	controlled_player.controlled = true
	if hud and hud.has_method("set_controlled"):
		var role := "GK" if player.is_goalkeeper else "OF"
		hud.set_controlled("Team %s #%d (%s)" % [
			"Home" if player.team_id == 0 else "Away",
			player.player_index + 1,
			role
		])


func _cycle_teammate() -> void:
	var roster := _home_players if controlled_team_id == 0 else _away_players
	if roster.size() < 2:
		return
	# Prefer nearest teammate to the ball (not current).
	var best: Player = null
	var best_d := INF
	for p in roster:
		if p == controlled_player:
			continue
		var d := p.global_position.distance_squared_to(ball.global_position)
		if d < best_d:
			best_d = d
			best = p
	if best:
		_set_controlled(best)


func _try_shoot() -> void:
	if controlled_player == null or not controlled_player.has_ball:
		return
	var aim := _compute_aim()
	controlled_player.try_shoot(aim, SHOOT_IMPULSE, ball)


func _compute_aim() -> Vector3:
	if aim_mode == AimMode.MOUSE_COURT:
		var hit: Variant = _mouse_on_court()
		if typeof(hit) == TYPE_VECTOR3:
			var target: Vector3 = hit
			var from: Vector3 = controlled_player.global_position + Vector3(0, 1.2, 0)
			var dir: Vector3 = target - from
			if dir.length_squared() > 0.01:
				return dir.normalized()
	# Face-direction fallback / default
	var face := controlled_player.face_direction()
	face.y = 0.15
	return face.normalized()


func _mouse_on_court() -> Variant:
	var cam := camera_rig.camera
	if cam == null:
		return null
	var mouse := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mouse)
	var ray_dir := cam.project_ray_normal(mouse)
	# Intersect y = 0 court plane
	if absf(ray_dir.y) < 0.0001:
		return null
	var t := -from.y / ray_dir.y
	if t < 0.0:
		return null
	var point: Vector3 = from + ray_dir * t
	return point


func _update_camera_attack_side() -> void:
	# Camera sits behind the team that has (or last had) the ball.
	if ball.carrier:
		_attack_team_id = ball.carrier.team_id
	camera_rig.set_attack_direction(_attack_team_id == 0)


func _on_goal_scored(scoring_team_id: int, _goal_owner_team_id: int) -> void:
	if _resetting:
		return
	_resetting = true
	if scoring_team_id == 0:
		score_home += 1
	else:
		score_away += 1
	print("GOAL! Home %d — Away %d" % [score_home, score_away])
	if hud and hud.has_method("set_score"):
		hud.set_score(score_home, score_away)
	if hud and hud.has_method("flash_goal"):
		hud.flash_goal()
	await get_tree().create_timer(RESET_DELAY).timeout
	_reset_play()
	_resetting = false


func _reset_play() -> void:
	for p in _home_players:
		p.reset_to_start()
	for p in _away_players:
		p.reset_to_start()
	ball.reset_to_start()
	# Keep control on first home outfield
	var starter := _first_outfield(_home_players)
	if starter:
		_set_controlled(starter)
	elif not _home_players.is_empty():
		_set_controlled(_home_players[0])
	_attack_team_id = 0
	camera_rig.set_attack_direction(true)


func _first_outfield(roster: Array[Player]) -> Player:
	for p in roster:
		if not p.is_goalkeeper:
			return p
	return null


func _aim_mode_label() -> String:
	return "Aim: Face" if aim_mode == AimMode.FACE else "Aim: Mouse"

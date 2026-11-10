extends Node3D
class_name MatchController

## Routes input, possession, team switch, scoring, clock, kickoff, AI, and Phase 2 rules.

enum AimMode { FACE, MOUSE_COURT }
enum MatchState { PRE_KICKOFF, LIVE, GOAL_PAUSE, PERIOD_BREAK, MATCH_OVER, RULE_RESTART }

const SHOOT_IMPULSE := 16.0
const GOAL_PAUSE_DELAY := 1.6
const KICKOFF_FREEZE := 0.85
const RESTART_FREEZE := 0.75
const PERIOD_BREAK_DELAY := 2.2

@export var home_team_path: NodePath
@export var away_team_path: NodePath
@export var ball_path: NodePath
@export var camera_rig_path: NodePath
@export var hud_path: NodePath
@export var player_scene: PackedScene
## Sandbox default: 2 minutes per half. Raise toward 1800 for full IHF halves later.
@export var period_length_seconds: float = 120.0
@export var periods_total: int = 2

var aim_mode: AimMode = AimMode.FACE
var controlled_player: Player = null
var controlled_team_id: int = 0
var score_home: int = 0
var score_away: int = 0
var current_period: int = 1
var clock_remaining: float = 120.0
var match_state: MatchState = MatchState.PRE_KICKOFF
var _home_players: Array[Player] = []
var _away_players: Array[Player] = []
## Last team that possessed the ball — camera stays behind them while the ball is free.
var _attack_team_id: int = 0
var _pending_kickoff_team: int = 0
var rules: HandballRules = HandballRules.new()
## Set when rules emit step_taken so the HUD can pulse once.
var _steps_hud_pulse: bool = false

@onready var _home_root: Node = get_node(home_team_path)
@onready var _away_root: Node = get_node(away_team_path)
@onready var ball: Ball = get_node(ball_path)
@onready var camera_rig: CameraRig = get_node(camera_rig_path)
@onready var hud: CanvasLayer = get_node(hud_path)


func _ready() -> void:
	clock_remaining = period_length_seconds
	_spawn_roster()
	_collect_players()
	_wire_goals()
	_wire_rules()
	_configure_ai()
	camera_rig.setup(ball, true)
	_refresh_hud()
	print(
		"MyHandball Phase 2 rules ready. Period=%ds x%d. Steps/passive/OOB/6m + throw-in/goal throw."
		% [int(period_length_seconds), periods_total]
	)
	var user_args := OS.get_cmdline_user_args()
	if "--smoke" in user_args:
		var smoke := load("res://scripts/smoke_test.gd") as GDScript
		var node := Node.new()
		node.set_script(smoke)
		add_child(node)
		return
	if "--screenshot-demo" in user_args:
		var demo := load("res://scripts/screenshot_demo.gd") as GDScript
		var dn := Node.new()
		dn.set_script(demo)
		add_child(dn)
		return
	if "--screenshot-steps" in user_args:
		# Kickoff first so roster / controlled player exist, then capture Steps HUD.
		await _run_kickoff(0, "Kickoff")
		var steps_shot := load("res://scripts/screenshot_steps_hud.gd") as GDScript
		var sn_steps := Node.new()
		sn_steps.set_script(steps_shot)
		add_child(sn_steps)
		return
	if "--screenshot" in user_args:
		# Kickoff first so the HUD clock/score are on screen, then capture.
		await _run_kickoff(0, "Kickoff")
		var shot := load("res://scripts/screenshot_once.gd") as GDScript
		var sn := Node.new()
		sn.set_script(shot)
		add_child(sn)
		return
	# Normal play: opening kickoff (home).
	await _run_kickoff(0, "Kickoff")


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


func _configure_ai() -> void:
	for p in _home_players:
		p.match_ball = ball
		# Human team: only the controlled player moves; teammates stay idle for Phase 1.
		p.ai_enabled = false
	for p in _away_players:
		p.match_ball = ball
		p.ai_enabled = true


func _wire_rules() -> void:
	ball.picked_up.connect(_on_ball_picked_up)
	ball.released.connect(_on_ball_released)
	rules.rule_warning.connect(_on_rule_warning)
	rules.rule_violation.connect(_on_rule_violation)
	rules.step_taken.connect(_on_step_taken)


func _unhandled_input(event: InputEvent) -> void:
	if match_state == MatchState.MATCH_OVER:
		return
	if event.is_action_pressed("toggle_aim_mode"):
		aim_mode = AimMode.MOUSE_COURT if aim_mode == AimMode.FACE else AimMode.FACE
		if hud and hud.has_method("set_aim_mode"):
			hud.set_aim_mode(_aim_mode_label())
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("switch_player"):
		if match_state == MatchState.LIVE:
			_cycle_teammate()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("shoot") and match_state == MatchState.LIVE:
		_try_shoot()
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	_update_camera_attack_side()
	if match_state != MatchState.LIVE:
		return
	clock_remaining = maxf(0.0, clock_remaining - delta)
	if hud and hud.has_method("set_clock"):
		hud.set_clock(clock_remaining)
	_update_rules_hud()
	if rules.tick(delta, ball, _all_players()):
		return
	if clock_remaining <= 0.0:
		_on_period_expired()


func _all_players() -> Array[Player]:
	var out: Array[Player] = []
	out.append_array(_home_players)
	out.append_array(_away_players)
	return out


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


func _on_ball_picked_up(player: Player) -> void:
	rules.on_pickup(player)
	_attack_team_id = player.team_id
	_update_rules_hud()


func _on_ball_released(player: Player) -> void:
	rules.on_release(player)
	_update_rules_hud()


func _on_step_taken(_steps: int) -> void:
	_steps_hud_pulse = true
	_update_rules_hud()


func _on_rule_warning(code: String, message: String) -> void:
	print("RULE WARN [%s]: %s" % [code, message])
	if hud and hud.has_method("flash_rule"):
		hud.flash_rule(message, code)
	_update_rules_hud()


func _on_rule_violation(code: String, message: String, awarding_team_id: int, spot: Vector3) -> void:
	if match_state != MatchState.LIVE:
		return
	print("RULE [%s]: %s → team %d @ %s" % [code, message, awarding_team_id, str(spot)])
	if hud and hud.has_method("flash_rule"):
		hud.flash_rule(message, code)
	# Fire-and-forget async restart (same pattern as goal kickoff).
	_run_rule_restart(code, message, awarding_team_id, spot)


func _run_rule_restart(code: String, _message: String, awarding_team_id: int, spot: Vector3) -> void:
	match_state = MatchState.RULE_RESTART
	rules.begin_lockout()
	_set_players_frozen(true)
	_clear_possession()

	var use_gk := code == "goal_throw"
	var taker: Player = null
	if use_gk:
		taker = _goalkeeper_for(awarding_team_id)
	if taker == null:
		taker = _nearest_outfield(awarding_team_id, spot)
	if taker == null:
		var roster := _home_players if awarding_team_id == 0 else _away_players
		taker = _first_outfield(roster)
		if taker == null and not roster.is_empty():
			taker = roster[0]

	if taker:
		var place := spot
		place.y = 0.0
		if use_gk:
			place = taker.start_position
			place.z = clampf(place.z, -17.5, 17.5)
		taker.global_position = place
		# Face midfield / attack.
		var face_yaw := 0.0 if awarding_team_id == 0 else PI
		if code == "throw_in":
			# Face inward from the sideline.
			face_yaw = -PI * 0.5 if spot.x > 0.0 else PI * 0.5
		taker.rotation.y = face_yaw
		taker.velocity = Vector3.ZERO
		ball.global_position = taker.ball_attach.global_position
		if ball.try_pickup(taker):
			taker.has_ball = true
		_attack_team_id = awarding_team_id
		camera_rig.set_attack_direction(awarding_team_id == 0)
		rules.on_pickup(taker)

	# Human always controls home.
	var home_starter := _first_outfield(_home_players)
	if home_starter:
		_set_controlled(home_starter)
	elif not _home_players.is_empty():
		_set_controlled(_home_players[0])

	_refresh_hud()
	_update_rules_hud()
	if hud and hud.has_method("flash_restart"):
		hud.flash_restart(code, awarding_team_id)

	await get_tree().create_timer(RESTART_FREEZE).timeout
	if match_state == MatchState.MATCH_OVER:
		return
	rules.end_lockout()
	_set_players_frozen(false)
	match_state = MatchState.LIVE
	_update_rules_hud()


func _clear_possession() -> void:
	if ball.carrier:
		ball.carrier.has_ball = false
	ball.carrier = null
	ball._last_carrier = null
	ball._ignore_carrier_until = 0.0
	ball.freeze = false
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	ball.collision_layer = 4
	ball.collision_mask = 1 | 2
	for p in _all_players():
		p.has_ball = false


func _goalkeeper_for(team_id: int) -> Player:
	var roster := _home_players if team_id == 0 else _away_players
	for p in roster:
		if p.is_goalkeeper:
			return p
	return null


func _nearest_outfield(team_id: int, spot: Vector3) -> Player:
	var roster := _home_players if team_id == 0 else _away_players
	var best: Player = null
	var best_d := INF
	for p in roster:
		if p.is_goalkeeper:
			continue
		var d := p.global_position.distance_squared_to(spot)
		if d < best_d:
			best_d = d
			best = p
	return best


func _update_rules_hud() -> void:
	if hud == null:
		return
	var carrying := match_state == MatchState.LIVE and ball.carrier != null and not ball.carrier.is_goalkeeper
	if hud.has_method("set_steps_status"):
		var pulse := _steps_hud_pulse
		_steps_hud_pulse = false
		hud.set_steps_status(
			rules.get_steps(),
			HandballRules.MAX_STEPS,
			rules.is_steps_warned(),
			carrying,
			pulse
		)
	if not hud.has_method("set_rules_status"):
		return
	if not carrying:
		hud.set_rules_status("")
		return
	var parts: PackedStringArray = []
	if rules.is_passive_warned():
		parts.append("PASSIVE")
	elif rules.get_passive_timer() > 3.0:
		parts.append("Passive %.0fs" % rules.get_passive_timer())
	hud.set_rules_status(" · ".join(parts))


func _on_goal_scored(scoring_team_id: int, goal_owner_team_id: int) -> void:
	if match_state != MatchState.LIVE:
		return
	match_state = MatchState.GOAL_PAUSE
	rules.begin_lockout()
	_set_players_frozen(true)
	if scoring_team_id == 0:
		score_home += 1
	else:
		score_away += 1
	print("GOAL! Home %d — Away %d (kickoff → team %d)" % [score_home, score_away, goal_owner_team_id])
	if hud and hud.has_method("set_score"):
		hud.set_score(score_home, score_away)
	if hud and hud.has_method("flash_goal"):
		hud.flash_goal()
	# Conceding team (goal owner) restarts from center.
	_pending_kickoff_team = goal_owner_team_id
	await get_tree().create_timer(GOAL_PAUSE_DELAY).timeout
	if match_state == MatchState.MATCH_OVER:
		return
	await _run_kickoff(_pending_kickoff_team, "Restart")


func _on_period_expired() -> void:
	if match_state != MatchState.LIVE:
		return
	match_state = MatchState.PERIOD_BREAK
	rules.begin_lockout()
	_set_players_frozen(true)
	print("Period %d ended. Score Home %d — Away %d" % [current_period, score_home, score_away])
	if current_period >= periods_total:
		match_state = MatchState.MATCH_OVER
		if hud and hud.has_method("flash_match_over"):
			hud.flash_match_over(score_home, score_away)
		print("MATCH OVER. Final Home %d — Away %d" % [score_home, score_away])
		_set_players_frozen(true)
		return
	if hud and hud.has_method("flash_period_end"):
		hud.flash_period_end(current_period)
	await get_tree().create_timer(PERIOD_BREAK_DELAY).timeout
	current_period += 1
	clock_remaining = period_length_seconds
	# Alternate kickoff each period: home starts P1, away starts P2, …
	var kick_team := 0 if (current_period % 2) == 1 else 1
	await _run_kickoff(kick_team, "Period %d kickoff" % current_period)


func _run_kickoff(kickoff_team_id: int, reason: String = "Kickoff") -> void:
	match_state = MatchState.PRE_KICKOFF
	rules.begin_lockout()
	_set_players_frozen(true)
	_reset_players_and_ball()
	var roster := _home_players if kickoff_team_id == 0 else _away_players
	var taker := _first_outfield(roster)
	if taker == null and not roster.is_empty():
		taker = roster[0]
	# Place taker near center facing the attack; give possession.
	if taker:
		var face_yaw := 0.0 if kickoff_team_id == 0 else PI
		taker.global_position = Vector3(0.0, 0.0, -1.2 if kickoff_team_id == 0 else 1.2)
		taker.rotation.y = face_yaw
		taker.velocity = Vector3.ZERO
		ball.global_position = taker.ball_attach.global_position
		if ball.try_pickup(taker):
			taker.has_ball = true
		_attack_team_id = kickoff_team_id
		camera_rig.set_attack_direction(kickoff_team_id == 0)
		rules.on_pickup(taker)
	# Human always controls home (Phase 1); keep control on a home outfield.
	var home_starter := _first_outfield(_home_players)
	if home_starter:
		_set_controlled(home_starter)
	elif not _home_players.is_empty():
		_set_controlled(_home_players[0])
	_refresh_hud()
	_update_rules_hud()
	if hud and hud.has_method("flash_kickoff"):
		hud.flash_kickoff(reason, kickoff_team_id)
	print("%s — team %d has the ball" % [reason, kickoff_team_id])
	await get_tree().create_timer(KICKOFF_FREEZE).timeout
	if match_state == MatchState.MATCH_OVER:
		return
	rules.end_lockout()
	_set_players_frozen(false)
	match_state = MatchState.LIVE
	_update_rules_hud()


func _reset_players_and_ball() -> void:
	for p in _home_players:
		p.reset_to_start()
	for p in _away_players:
		p.reset_to_start()
	ball.reset_to_start()
	rules.reset_possession_tracking()


func _set_players_frozen(frozen: bool) -> void:
	for p in _home_players:
		p.match_frozen = frozen
		if frozen:
			p.velocity = Vector3.ZERO
	for p in _away_players:
		p.match_frozen = frozen
		if frozen:
			p.velocity = Vector3.ZERO


func _refresh_hud() -> void:
	if hud and hud.has_method("set_score"):
		hud.set_score(score_home, score_away)
	if hud and hud.has_method("set_clock"):
		hud.set_clock(clock_remaining)
	if hud and hud.has_method("set_period"):
		hud.set_period(current_period, periods_total)
	if hud and hud.has_method("set_aim_mode"):
		hud.set_aim_mode(_aim_mode_label())


func _first_outfield(roster: Array[Player]) -> Player:
	for p in roster:
		if not p.is_goalkeeper:
			return p
	return null


func _aim_mode_label() -> String:
	return "Aim: Face" if aim_mode == AimMode.FACE else "Aim: Mouse"

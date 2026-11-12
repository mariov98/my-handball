extends Node3D
class_name MatchController

## Routes input, possession, team switch, scoring, clock, kickoff, AI, Phase 2–4
## rules/tactics, Phase 5 presentation, and Phase D contact / 7 m / exclusion lite.

enum AimMode { FACE, MOUSE_COURT }
enum MatchState { PRE_KICKOFF, LIVE, GOAL_PAUSE, PERIOD_BREAK, MATCH_OVER, RULE_RESTART }

const SHOOT_IMPULSE := 16.0 ## Fallback / legacy tap strength (charge system preferred).
const GOAL_PAUSE_DELAY := 1.25
const GOAL_SLOWMO_SCALE := 0.38
const KICKOFF_FREEZE := 0.55
const RESTART_FREEZE := 0.5
const PERIOD_BREAK_DELAY := 1.7
const BLOCK_TRACE_LEN := 9.5
## Soft-pass impulse band (kept in sync with PassCraft.IMPULSE_*).
const PASS_IMPULSE_MIN := 8.5
const PASS_IMPULSE_MAX := 13.0

@export var home_team_path: NodePath
@export var away_team_path: NodePath
@export var ball_path: NodePath
@export var camera_rig_path: NodePath
@export var hud_path: NodePath
@export var player_scene: PackedScene
## Sandbox default: 2 minutes per half. Raise toward 1800 for full IHF halves later.
@export var period_length_seconds: float = 120.0
@export var periods_total: int = 2
## Phase D: 2-min exclusion lite duration (match-clock seconds). Tunable.
@export var exclusion_seconds: float = 120.0
## When true, clear-chance → 7 m also benches the fouler for exclusion_seconds.
@export var exclusion_on_seven_m: bool = true

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
## Phase 3 charge-to-shoot.
var _charging: bool = false
var _charge_held_s: float = 0.0
## After a pass steals the hold, ignore shoot until the shoot action is released.
var _pass_suppress_shoot: bool = false
var _block_trace: BlockTrace

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
	_setup_block_trace()
	camera_rig.setup(ball, true)
	_refresh_hud()
	print(
		"MyHandball Phase D contact/7m ready. Period=%ds x%d. Dribble V/R3; Pass RMB/G/RB."
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
	if "--screenshot-phase3" in user_args:
		await _run_kickoff(0, "Kickoff")
		var p3_shot := load("res://scripts/screenshot_phase3.gd") as GDScript
		var sn_p3 := Node.new()
		sn_p3.set_script(p3_shot)
		add_child(sn_p3)
		return
	if "--screenshot-phase4" in user_args:
		await _run_kickoff(0, "Kickoff")
		var p4_shot := load("res://scripts/screenshot_phase4.gd") as GDScript
		var sn_p4 := Node.new()
		sn_p4.set_script(p4_shot)
		add_child(sn_p4)
		return
	if "--screenshot-phase5" in user_args:
		await _run_kickoff(0, "Kickoff")
		var p5_shot := load("res://scripts/screenshot_phase5.gd") as GDScript
		var sn_p5 := Node.new()
		sn_p5.set_script(p5_shot)
		add_child(sn_p5)
		return
	if "--screenshot-camera-feel" in user_args:
		await _run_kickoff(0, "Kickoff")
		var cam_shot := load("res://scripts/screenshot_camera_feel.gd") as GDScript
		var sn_cam := Node.new()
		sn_cam.set_script(cam_shot)
		add_child(sn_cam)
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
	# Punchier kit colors for Phase 5 readability.
	var home_color := Color(0.12, 0.42, 0.92)
	var away_color := Color(0.92, 0.16, 0.14)
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
		# Phase 4: uncontrolled home teammates hold formation slots (off-ball AI).
		p.ai_enabled = (not p.excluded) and p != controlled_player
	for p in _away_players:
		p.match_ball = ball
		p.ai_enabled = not p.excluded


func _refresh_home_ai() -> void:
	for p in _home_players:
		p.ai_enabled = (not p.excluded) and p != controlled_player
		p.match_ball = ball


func _wire_rules() -> void:
	ball.picked_up.connect(_on_ball_picked_up)
	ball.released.connect(_on_ball_released)
	rules.rule_warning.connect(_on_rule_warning)
	rules.rule_violation.connect(_on_rule_violation)
	rules.step_taken.connect(_on_step_taken)
	for p in _all_players():
		if not p.block_attempted.is_connected(_on_block_attempted):
			p.block_attempted.connect(_on_block_attempted)


func _setup_block_trace() -> void:
	_block_trace = BlockTrace.new()
	_block_trace.name = "BlockTrace"
	add_child(_block_trace)


func _unhandled_input(event: InputEvent) -> void:
	if match_state == MatchState.MATCH_OVER:
		return
	if event.is_action_pressed("toggle_aim_mode"):
		aim_mode = AimMode.MOUSE_COURT if aim_mode == AimMode.FACE else AimMode.FACE
		if hud and hud.has_method("set_aim_mode"):
			hud.set_aim_mode(_aim_mode_label())
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("switch_best"):
		if match_state == MatchState.LIVE:
			_switch_to_best()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("switch_player"):
		if match_state == MatchState.LIVE:
			_cycle_teammate()
		get_viewport().set_input_as_handled()
		return
	# Pass first so RMB/G/RB never starts or finishes a shoot-charge.
	if event.is_action_pressed("pass_ball") and match_state == MatchState.LIVE:
		_end_controlled_dribble()
		_try_pass()
		get_viewport().set_input_as_handled()
		return
	# Phase 3: hold shoot to charge, release to fire. Tap still works (min power).
	if event.is_action_pressed("shoot") and match_state == MatchState.LIVE:
		if _pass_suppress_shoot:
			get_viewport().set_input_as_handled()
			return
		if controlled_player and controlled_player.has_ball:
			_charging = true
			_charge_held_s = 0.0
			get_viewport().set_input_as_handled()
		return
	if event.is_action_released("shoot"):
		_pass_suppress_shoot = false
		if _charging:
			_release_charged_shot()
			get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	_update_camera_attack_side()
	_update_shot_charge(delta)
	_update_dribble_input()
	if match_state != MatchState.LIVE:
		return
	clock_remaining = maxf(0.0, clock_remaining - delta)
	if hud and hud.has_method("set_clock"):
		hud.set_clock(clock_remaining)
	_tick_exclusions(delta)
	_update_rules_hud()
	_update_shot_hud()
	# Phase D: shoot charge counts as windup for contact fouls near the arc.
	rules.set_windup(_charging and controlled_player != null and controlled_player.has_ball, true)
	if rules.tick(delta, ball, _all_players()):
		rules.set_windup(false)
		return
	if clock_remaining <= 0.0:
		_on_period_expired()


## Hold `dribble` (V / R3) while possessing to bounce; release gathers (new steps + 3 s).
func _update_dribble_input() -> void:
	if match_state != MatchState.LIVE:
		_end_controlled_dribble()
		return
	var p := controlled_player
	if p == null or not p.has_ball or p.is_goalkeeper or ball == null or ball.carrier != p:
		_end_controlled_dribble()
		return
	# Don't bounce while charging a shot — shoot owns the hands.
	if _charging:
		_end_controlled_dribble()
		return
	var want := Input.is_action_pressed("dribble")
	if want:
		if not p.dribbling:
			if rules.try_begin_dribble(p):
				p.dribbling = true
			# Double-dribble violation is handled by rules → restart.
	elif p.dribbling:
		_end_controlled_dribble()


func _end_controlled_dribble() -> void:
	var p := controlled_player
	if p == null or not p.dribbling:
		return
	p.dribbling = false
	rules.end_dribble(p)
	_update_rules_hud()


func _update_shot_charge(delta: float) -> void:
	# Clear pass→shoot latch once the shoot button is fully up.
	if _pass_suppress_shoot and not Input.is_action_pressed("shoot"):
		_pass_suppress_shoot = false
	if not _charging:
		return
	if match_state != MatchState.LIVE or controlled_player == null or not controlled_player.has_ball:
		_cancel_charge()
		return
	if _pass_suppress_shoot:
		_cancel_charge()
		return
	# Keep charging while the shoot action is held (mouse / E / RT).
	if Input.is_action_pressed("shoot"):
		_charge_held_s += delta
	else:
		# Released outside _unhandled_input (e.g. focus loss) — still fire.
		_release_charged_shot()


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
		if controlled_player.has_method("set_selection_highlight"):
			controlled_player.set_selection_highlight(false)
	controlled_player = player
	controlled_team_id = player.team_id
	controlled_player.controlled = true
	if controlled_player.has_method("set_selection_highlight"):
		controlled_player.set_selection_highlight(true)
	_refresh_home_ai()
	if hud and hud.has_method("set_controlled"):
		var role := "GK" if player.is_goalkeeper else Formations.role_label(Formations.role_for(player))
		hud.set_controlled("Team %s #%d (%s)" % [
			"Home" if player.team_id == 0 else "Away",
			player.player_index + 1,
			role
		])


func _cycle_teammate() -> void:
	var roster := _home_players if controlled_team_id == 0 else _away_players
	if roster.size() < 2:
		return
	# Cycle: next roster index (wrap), skipping excluded players.
	var start_i := 0
	for i in range(roster.size()):
		if roster[i] == controlled_player:
			start_i = i
			break
	for step in range(1, roster.size() + 1):
		var next_i := (start_i + step) % roster.size()
		if roster[next_i].excluded:
			continue
		_set_controlled(roster[next_i])
		return


## Switch-to-best: ball nearest / open receiver / best defender (Phase 4).
func _switch_to_best() -> void:
	var roster := _home_players if controlled_team_id == 0 else _away_players
	if roster.size() < 2:
		return
	var best: Player = null
	var best_score := -INF
	for p in roster:
		if p == controlled_player:
			continue
		var s := Formations.switch_score(p, controlled_player, ball, _attack_team_id)
		if s > best_score:
			best_score = s
			best = p
	if best:
		_set_controlled(best)


func _cancel_charge() -> void:
	_charging = false
	_charge_held_s = 0.0
	if hud and hud.has_method("set_shot_status"):
		hud.set_shot_status(0.0, false, "", false)


func _release_charged_shot() -> void:
	if not _charging:
		return
	if _pass_suppress_shoot:
		_cancel_charge()
		return
	var held := _charge_held_s
	_charging = false
	_charge_held_s = 0.0
	_try_shoot_charged(held)


func _try_shoot_charged(held_s: float) -> void:
	if controlled_player == null or not controlled_player.has_ball:
		if hud and hud.has_method("set_shot_status"):
			hud.set_shot_status(0.0, false, "", false)
		return
	var charge := ShotCraft.charge_01(held_s)
	var lob := Input.is_action_pressed("lob")
	var aim := _compute_aim(lob)
	var jump_q := ShotCraft.jump_shot_quality(controlled_player)
	var impulse := ShotCraft.impulse_for_charge(charge, lob)
	var timed := ShotCraft.apply_jump_timing(aim, impulse, jump_q)
	aim = timed["aim"]
	impulse = timed["impulse"]
	var up := ShotCraft.up_bias(lob)
	# Jump shots naturally loft a touch more.
	if jump_q >= 0:
		up += 0.08 if jump_q == 1 else 0.04
	var meta := {
		"charge": charge,
		"lob": lob,
		"jump_quality": jump_q,
		"impulse": impulse,
	}
	var from := controlled_player.global_position + Vector3(0, 1.2, 0)
	if controlled_player.try_shoot(aim, impulse, ball, up, meta):
		_spawn_shot_trace(from, aim, lob, jump_q)
		# Nearby defending outfield raise hands for the contest window.
		_nudge_defenders_to_block(controlled_player.team_id, from, aim)
	if hud and hud.has_method("set_shot_status"):
		hud.set_shot_status(0.0, false, "", false)


## Instant tap path used by smoke / scripts (full mid charge, flat).
func _try_shoot() -> void:
	_try_shoot_charged(ShotCraft.CHARGE_TIME_S * 0.55)


## Soft pass to best teammate in the aim cone (light lead assist). Never fires a shot.
func _try_pass() -> void:
	if controlled_player == null or not controlled_player.has_ball:
		return
	# Harden vs shoot-charge: cancel power hold and suppress shoot until release.
	if _charging:
		_cancel_charge()
	_pass_suppress_shoot = true
	# Phase D: pass act can still draw a contact foul near 6–9 m (FT, not 7 m).
	if rules.probe_pass_act_contact(ball, _all_players()):
		return
	var aim_hint := _compute_aim(false)
	aim_hint.y = 0.0
	if aim_hint.length_squared() < 0.01:
		aim_hint = controlled_player.face_direction()
		aim_hint.y = 0.0
	var target := _best_pass_target(controlled_player, aim_hint)
	if target:
		controlled_player.try_pass_to(target, ball, -1.0, aim_hint)
		return
	# No open mate in cone — soft toss along aim so the action never feels dead.
	var toss := aim_hint.normalized()
	toss.y = 0.1
	toss = toss.normalized()
	controlled_player.try_shoot(
		toss,
		PASS_IMPULSE_MIN + 0.5,
		ball,
		PassCraft.LOFT_MIN + 0.04,
		{"pass": true, "charge": 0.25}
	)


func _best_pass_target(passer: Player, aim_hint: Vector3 = Vector3.ZERO) -> Player:
	if passer == null:
		return null
	var roster := _home_players if passer.team_id == 0 else _away_players
	var aim := aim_hint
	if aim.length_squared() < 0.01:
		aim = passer.face_direction()
	var best := PassCraft.best_in_cone(passer, roster, aim, passer.team_id)
	return best as Player


func _compute_aim(lob: bool = false) -> Vector3:
	if aim_mode == AimMode.MOUSE_COURT:
		var hit: Variant = _mouse_on_court()
		if typeof(hit) == TYPE_VECTOR3:
			var target: Vector3 = hit
			# Lob aims a bit above the court plane hit so mouse mode can float it.
			if lob:
				target.y = 2.4
			var from: Vector3 = controlled_player.global_position + Vector3(0, 1.2, 0)
			var dir: Vector3 = target - from
			if dir.length_squared() > 0.01:
				return dir.normalized()
	# Face-direction fallback / default
	var face := controlled_player.face_direction()
	face.y = 0.42 if lob else 0.12
	return face.normalized()


func _spawn_shot_trace(from: Vector3, aim: Vector3, lob: bool, jump_q: int) -> void:
	if _block_trace == null:
		return
	var contested := _shot_path_contested(from, aim, controlled_player.team_id)
	var len := BLOCK_TRACE_LEN * (0.85 if lob else 1.0)
	if jump_q == 1:
		len *= 1.05
	_block_trace.show_shot(from, aim, len, contested)


func _shot_path_contested(from: Vector3, aim: Vector3, shooter_team: int) -> bool:
	var dir := aim.normalized()
	for p in _all_players():
		if p.team_id == shooter_team or p.is_goalkeeper:
			continue
		var to_p: Vector3 = p.global_position + Vector3(0, 1.2, 0) - from
		var along := to_p.dot(dir)
		if along < 0.4 or along > BLOCK_TRACE_LEN:
			continue
		var closest := from + dir * along
		if closest.distance_to(p.global_position + Vector3(0, 1.2, 0)) < 1.35:
			return true
	# GK in the lane also counts as contested.
	var gk := _goalkeeper_for(1 - shooter_team)
	if gk:
		var to_gk: Vector3 = gk.global_position + Vector3(0, 1.0, 0) - from
		var along_g := to_gk.dot(dir)
		if along_g > 0.5 and along_g < BLOCK_TRACE_LEN + 4.0:
			var closest_g := from + dir * along_g
			if closest_g.distance_to(gk.global_position + Vector3(0, 1.0, 0)) < 2.2:
				return true
	return false


func _nudge_defenders_to_block(shooter_team: int, from: Vector3, aim: Vector3) -> void:
	var dir := aim.normalized()
	for p in _all_players():
		if p.team_id == shooter_team or p.is_goalkeeper:
			continue
		var to_p: Vector3 = p.global_position + Vector3(0, 1.2, 0) - from
		var along := to_p.dot(dir)
		if along < 0.5 or along > 8.0:
			continue
		var closest := from + dir * along
		if closest.distance_to(p.global_position + Vector3(0, 1.2, 0)) < 1.6:
			p.raise_block(0.55)


func _on_block_attempted(blocker: Player, ball_ref: Ball, success: bool) -> void:
	if blocker:
		rules.last_touch_team_id = blocker.team_id
	if not success or _block_trace == null or ball_ref == null:
		return
	var n := ball_ref.linear_velocity
	if n.length_squared() < 0.01:
		n = Vector3.UP
	_block_trace.show_block_hit(ball_ref.global_position, n)


func _update_shot_hud() -> void:
	if hud == null or not hud.has_method("set_shot_status"):
		return
	if match_state != MatchState.LIVE or controlled_player == null or not controlled_player.has_ball:
		hud.set_shot_status(0.0, false, "", false)
		if hud.has_method("set_pass_hint"):
			hud.set_pass_hint(false)
		return
	var charge := ShotCraft.charge_01(_charge_held_s) if _charging else 0.0
	var lob := _charging and Input.is_action_pressed("lob")
	var jump_q := ShotCraft.jump_shot_quality(controlled_player)
	var jump_txt := ShotCraft.jump_label(jump_q)
	# While charging, shot HUD owns the line; otherwise surface a clear PASS prompt.
	hud.set_shot_status(charge, lob, jump_txt, _charging or jump_q >= 0)
	if hud.has_method("set_pass_hint"):
		hud.set_pass_hint(not _charging)


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
	if player == controlled_player:
		_cancel_charge()
	rules.on_release(player)
	# Phase C: non-pass shot attempt clears passive (clarification lite).
	var is_pass := bool(ball.last_shot_meta.get("pass", false))
	if not is_pass:
		rules.on_shot_attempt(player)
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
	# Phase D: optional 2-min exclusion on clear-chance 7 m.
	if (
		code == "seven_m"
		and exclusion_on_seven_m
		and rules.last_foul_warrants_exclusion
		and rules.last_fouler != null
		and is_instance_valid(rules.last_fouler)
	):
		_begin_exclusion(rules.last_fouler)
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

	# Phase 4/D: place both teams into set-piece shape (9 m wall / 7 m / throw-in).
	_place_set_piece(code, awarding_team_id, spot, taker)

	if taker:
		var face_yaw := 0.0 if awarding_team_id == 0 else PI
		if code == "throw_in":
			face_yaw = -PI * 0.5 if spot.x > 0.0 else PI * 0.5
		elif Formations.is_seven_meter_code(code):
			face_yaw = 0.0 if awarding_team_id == 0 else PI
		elif Formations.is_free_throw_code(code):
			face_yaw = Formations.free_throw_taker_yaw(awarding_team_id, spot)
		taker.rotation.y = face_yaw
		taker.velocity = Vector3.ZERO
		ball.global_position = taker.ball_attach.global_position
		if ball.try_pickup(taker):
			taker.has_ball = true
		_attack_team_id = awarding_team_id
		camera_rig.set_attack_direction(awarding_team_id == 0)
		rules.on_pickup(taker)

	# Prefer controlling the home taker on home awards; else first outfield.
	if awarding_team_id == 0 and taker and taker.team_id == 0:
		_set_controlled(taker)
	else:
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


func _place_set_piece(code: String, awarding_team_id: int, spot: Vector3, taker: Player) -> void:
	for p in _all_players():
		var place := Formations.set_piece_slot(p, code, awarding_team_id, spot, taker)
		if p.excluded:
			place = Court.bench_marker(p.team_id, maxi(0, p.player_index - 1))
		p.global_position = place
		p.velocity = Vector3.ZERO
		var face := 0.0 if p.team_id == 0 else PI
		if code == "throw_in":
			face = -PI * 0.5 if spot.x > 0.0 else PI * 0.5
		elif Formations.is_seven_meter_code(code):
			if p == taker or p.team_id == awarding_team_id:
				face = 0.0 if awarding_team_id == 0 else PI
			elif p.is_goalkeeper:
				face = PI if awarding_team_id == 0 else 0.0
			else:
				var to_spot := spot - p.global_position
				if to_spot.length_squared() > 0.01:
					face = atan2(to_spot.x, to_spot.z)
		elif Formations.is_free_throw_code(code):
			if p.team_id == awarding_team_id:
				face = Formations.free_throw_taker_yaw(awarding_team_id, spot)
			else:
				# Wall faces the taker / midfield.
				var to_spot2 := spot - p.global_position
				if to_spot2.length_squared() > 0.01:
					face = atan2(to_spot2.x, to_spot2.z)
		p.rotation.y = face
	# Teleports skip physics — nudge any stacked capsules apart.
	_resolve_player_overlaps(taker)


func _clear_possession() -> void:
	if ball.carrier:
		ball.carrier.has_ball = false
		ball.carrier.dribbling = false
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
		p.dribbling = false


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
		if p.is_goalkeeper or p.excluded:
			continue
		var d := p.global_position.distance_squared_to(spot)
		if d < best_d:
			best_d = d
			best = p
	return best


## Phase D: park fouler on the bench with AI off for exclusion_seconds of match clock.
func _begin_exclusion(fouler: Player) -> void:
	if fouler == null or fouler.is_goalkeeper:
		return
	fouler.excluded = true
	fouler.exclusion_remaining = exclusion_seconds
	fouler.ai_enabled = false
	fouler.controlled = false
	fouler.has_ball = false
	fouler.dribbling = false
	fouler.velocity = Vector3.ZERO
	fouler.global_position = Court.bench_marker(fouler.team_id, maxi(0, fouler.player_index - 1))
	if controlled_player == fouler:
		var fallback := _nearest_outfield(fouler.team_id, fouler.global_position)
		if fallback == null:
			fallback = _first_outfield(_home_players if fouler.team_id == 0 else _away_players)
		if fallback:
			_set_controlled(fallback)
	_configure_ai()
	print(
		"EXCLUSION lite: %s benched for %.0fs"
		% [fouler.name, exclusion_seconds]
	)
	if hud and hud.has_method("flash_rule"):
		hud.flash_rule("2 min exclusion", "exclusion")


func _tick_exclusions(delta: float) -> void:
	for p in _all_players():
		if not p.excluded:
			continue
		p.exclusion_remaining = maxf(0.0, p.exclusion_remaining - delta)
		# Keep parked on the bench while the clock runs.
		var bench := Court.bench_marker(p.team_id, maxi(0, p.player_index - 1))
		p.global_position = bench
		p.velocity = Vector3.ZERO
		p.ai_enabled = false
		if p.exclusion_remaining <= 0.0:
			_end_exclusion(p)


func _end_exclusion(player: Player) -> void:
	if player == null:
		return
	player.excluded = false
	player.exclusion_remaining = 0.0
	# Re-enter outside own crease near mid of own half.
	var face := 1.0 if player.team_id == 0 else -1.0
	var slot := Vector3(
		clampf(player.start_position.x, -6.0, 6.0),
		0.0,
		face * -4.0
	)
	slot = Court.clamp_to_court_xz(slot, 1.0)
	if Court.in_goal_area(slot, player.team_id):
		slot = Court.eject_from_goal_area(slot, player.team_id, 0.8)
	player.global_position = slot
	player.velocity = Vector3.ZERO
	_configure_ai()
	_refresh_home_ai()
	print("EXCLUSION ended: %s returns" % player.name)


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
	if hud.has_method("set_hold_status"):
		if carrying:
			hud.set_hold_status(
				rules.get_hold_remaining(),
				HandballRules.HOLD_MAX_S,
				true,
				rules.is_dribbling() or (ball.carrier != null and ball.carrier.dribbling),
				rules.is_hold_warned()
			)
		else:
			hud.set_hold_status(0.0, HandballRules.HOLD_MAX_S, false, false, false)
	if not hud.has_method("set_rules_status"):
		return
	# Passive (lite) stays readable during a pass flight after the warn.
	var parts: PackedStringArray = []
	if rules.is_passive_warned():
		parts.append(
			"Passive (lite) %d/%d"
			% [rules.get_passive_receives(), rules.get_passive_max_receives()]
		)
	elif carrying and rules.get_passive_timer() > 3.0:
		parts.append("Passive (lite) %.0fs" % rules.get_passive_timer())
	if parts.is_empty() and not carrying:
		hud.set_rules_status("")
		return
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
	# Phase 5 juice: slow-mo + punchy banner / screen flash (wall-clock pause).
	Engine.time_scale = GOAL_SLOWMO_SCALE
	if hud and hud.has_method("flash_goal"):
		hud.flash_goal(scoring_team_id)
	# Conceding team (goal owner) restarts from center.
	_pending_kickoff_team = goal_owner_team_id
	await get_tree().create_timer(GOAL_PAUSE_DELAY, true, true).timeout
	Engine.time_scale = 1.0
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
	# Phase 4: compact kickoff shape (wings + backcourt) instead of spawn freeze.
	_place_kickoff_shape(kickoff_team_id)
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
		_resolve_player_overlaps(taker)
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


func _place_kickoff_shape(kickoff_team_id: int) -> void:
	for p in _all_players():
		var slot := Formations.kickoff_slot(p, kickoff_team_id)
		p.global_position = slot
		p.rotation.y = 0.0 if p.team_id == 0 else PI
		p.velocity = Vector3.ZERO
	_resolve_player_overlaps()


## Nudge CharacterBody capsules apart after teleport placement (set piece / kickoff).
## Prefer keeping `anchor` (taker) near their intended spot when possible.
func _resolve_player_overlaps(anchor: Player = null) -> void:
	var players := _all_players()
	# Slightly above 2 * capsule radius so shapes clear without sticky lock.
	var min_sep := Player.BODY_RADIUS * 2.0 + 0.08
	for _pass in range(5):
		var moved := false
		for i in players.size():
			for j in range(i + 1, players.size()):
				var a: Player = players[i]
				var b: Player = players[j]
				if a == null or b == null:
					continue
				var delta := Vector3(
					b.global_position.x - a.global_position.x,
					0.0,
					b.global_position.z - a.global_position.z
				)
				var dist := delta.length()
				if dist >= min_sep:
					continue
				var dir := delta
				if dist < 0.001:
					dir = Vector3(1.0, 0.0, 0.0)
					dist = 0.001
				else:
					dir /= dist
				var push := (min_sep - dist) * 0.5
				var shift := dir * push
				if a == anchor:
					b.global_position += shift * 2.0
				elif b == anchor:
					a.global_position -= shift * 2.0
				else:
					a.global_position -= shift
					b.global_position += shift
				a.global_position.y = 0.0
				b.global_position.y = 0.0
				a.global_position = Court.clamp_to_court_xz(a.global_position, 0.9)
				b.global_position = Court.clamp_to_court_xz(b.global_position, 0.9)
				a.velocity = Vector3.ZERO
				b.velocity = Vector3.ZERO
				moved = true
		if not moved:
			break


func _reset_players_and_ball() -> void:
	for p in _home_players:
		p.reset_to_start()
	for p in _away_players:
		p.reset_to_start()
	ball.reset_to_start()
	rules.reset_possession_tracking()


func _set_players_frozen(frozen: bool) -> void:
	if frozen:
		_cancel_charge()
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
		if not p.is_goalkeeper and not p.excluded:
			return p
	return null


func _aim_mode_label() -> String:
	return "Aim: Face" if aim_mode == AimMode.FACE else "Aim: Mouse"

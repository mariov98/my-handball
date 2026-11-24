extends Node3D
class_name MatchController

## Routes input, possession, team switch, scoring, clock, kickoff, AI, Phase 2–5
## rules/tactics/presentation, Phase D contact / 7 m / exclusion, Phase E shapes,
## Phase G sim depth (7-man roster, stamina, dead-ball substitutions).

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
## Wave 4: soft auto-dribble near 3 s / last step when legal (never double-dribble).
@export var auto_dribble_assist: bool = true

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
## Phase E: Home shape presets (player toggles). Away AI picks by score/time.
## Int defaults match Formations.AttackShape.WIDE / DefenseShape.FLAT.
var home_attack_shape: int = 0
var home_defense_shape: int = 0
var away_attack_shape: int = 0
var away_defense_shape: int = 0
## Phase G: selected bench index into the team's bench list (for sub UI).
var _bench_select_i: int = 0
## Set when rules emit step_taken so the HUD can pulse once.
var _steps_hud_pulse: bool = false
## Phase 3 charge-to-shoot.
var _charging: bool = false
var _charge_held_s: float = 0.0
## After a pass steals the hold, ignore shoot until the shoot action is released.
var _pass_suppress_shoot: bool = false
var _block_trace: BlockTrace
## Wave 4: live 7 m ready window (taker must shoot before limit).
var _seven_m_live: bool = false
var _seven_m_timer: float = 0.0
var _seven_m_award_team: int = 0

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
	_sync_team_shapes()
	print(
		"MyHandball Phase G sim ready. Period=%ds x%d. Roster 7+2. Sprint Shift · Sub ,/. on whistle."
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
	# Home attacks +Z. Phase G: full 7 on court (GK+LW/LB/CB/RB/RW/P) + 2 bench.
	# Spawn mirrors kickoff feel: Home offense pre-mid; Away defense on own 6 m wall.
	var home_color := Color(0.12, 0.42, 0.92)
	var away_color := Color(0.92, 0.16, 0.14)
	var home_spots: Array = [
		{"pos": Vector3(0, 0, -17.5), "yaw": 0.0, "gk": true, "idx": 0},
		{"pos": Vector3(-6.8, 0, -5.8), "yaw": 0.0, "gk": false, "idx": 1}, # LW
		{"pos": Vector3(-3.6, 0, -4.2), "yaw": 0.0, "gk": false, "idx": 2}, # LB
		{"pos": Vector3(0.0, 0, -3.4), "yaw": 0.0, "gk": false, "idx": 3}, # CB
		{"pos": Vector3(3.6, 0, -4.2), "yaw": 0.0, "gk": false, "idx": 4}, # RB
		{"pos": Vector3(6.8, 0, -5.8), "yaw": 0.0, "gk": false, "idx": 5}, # RW
		{"pos": Vector3(0.0, 0, -6.6), "yaw": 0.0, "gk": false, "idx": 6}, # Pivot
		{"pos": Court.bench_marker(0, 0), "yaw": 0.0, "gk": false, "idx": 7, "bench": true, "slot": 0},
		{"pos": Court.bench_marker(0, 1), "yaw": 0.0, "gk": false, "idx": 8, "bench": true, "slot": 1},
	]
	# Away default spawn = defensive wall just outside own 6 m (z≈+12.4).
	# Lanes match Formations absolute X (LW negative, RW positive).
	var away_spots: Array = [
		{"pos": Vector3(0, 0, 17.5), "yaw": PI, "gk": true, "idx": 0},
		{"pos": Vector3(-6.2, 0, 12.4), "yaw": PI, "gk": false, "idx": 1}, # LW
		{"pos": Vector3(-3.6, 0, 12.4), "yaw": PI, "gk": false, "idx": 2}, # LB
		{"pos": Vector3(-1.1, 0, 12.4), "yaw": PI, "gk": false, "idx": 3}, # CB
		{"pos": Vector3(3.6, 0, 12.4), "yaw": PI, "gk": false, "idx": 4}, # RB
		{"pos": Vector3(6.2, 0, 12.4), "yaw": PI, "gk": false, "idx": 5}, # RW
		{"pos": Vector3(1.1, 0, 12.4), "yaw": PI, "gk": false, "idx": 6}, # Pivot
		{"pos": Court.bench_marker(1, 0), "yaw": PI, "gk": false, "idx": 7, "bench": true, "slot": 0},
		{"pos": Court.bench_marker(1, 1), "yaw": PI, "gk": false, "idx": 8, "bench": true, "slot": 1},
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
	p.on_bench = bool(spot.get("bench", false))
	p.bench_slot = int(spot.get("slot", maxi(0, int(spot["idx"]) - 7)))
	p.body_color = color.darkened(0.15) if spot["gk"] else color
	var kind := "GK" if spot["gk"] else ("BN" if p.on_bench else "OF")
	p.name = "%s_%s%d" % [
		"Home" if team_id == 0 else "Away",
		kind,
		spot["idx"] + 1
	]
	parent.add_child(p)
	p.global_position = spot["pos"]
	p.rotation.y = spot["yaw"]
	p.start_position = spot["pos"]
	p.start_yaw = spot["yaw"]
	if p.on_bench:
		p.rotation.y = Court.bench_yaw(team_id)
		p.start_yaw = p.rotation.y
		p.ai_enabled = false
		p.visible = true


func _configure_ai() -> void:
	for p in _home_players:
		p.match_ball = ball
		# Phase 4/G: uncontrolled on-court home teammates hold formation slots.
		p.ai_enabled = (not p.excluded) and (not p.on_bench) and p != controlled_player
	for p in _away_players:
		p.match_ball = ball
		p.ai_enabled = (not p.excluded) and (not p.on_bench)


func _refresh_home_ai() -> void:
	for p in _home_players:
		p.ai_enabled = (not p.excluded) and (not p.on_bench) and p != controlled_player
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
	# Phase E: Home shape toggles (1 / D-pad↑ attack, 2 / D-pad↓ defense).
	if event.is_action_pressed("toggle_attack_shape"):
		_toggle_home_attack_shape()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("toggle_defense_shape"):
		_toggle_home_defense_shape()
		get_viewport().set_input_as_handled()
		return
	# Wave 6 R5.2: reset camera nudge to elevated 3/4 defaults.
	if event.is_action_pressed("camera_reset"):
		if camera_rig:
			camera_rig.reset_nudge()
		if hud and hud.has_method("flash_rule"):
			hud.flash_rule("Camera reset", "shape")
		get_viewport().set_input_as_handled()
		return
	# Wave 6 R5.3: optional toggle for wing-shot cinematic.
	if event.is_action_pressed("toggle_wing_cine"):
		if camera_rig:
			camera_rig.wing_cinematic_enabled = not camera_rig.wing_cinematic_enabled
			if not camera_rig.wing_cinematic_enabled:
				camera_rig.end_wing_cinematic(true)
			if hud and hud.has_method("flash_rule"):
				hud.flash_rule(
					"Wing cam %s" % ("ON" if camera_rig.wing_cinematic_enabled else "OFF"),
					"shape"
				)
		get_viewport().set_input_as_handled()
		return
	# Phase G: dead-ball substitutions (, cycle bench / . confirm).
	# Wave 3: D-pad Right / , is pass-fake while LIVE with the ball (else bench cycle).
	if event.is_action_pressed("cycle_bench"):
		if (
			match_state == MatchState.LIVE
			and controlled_player
			and controlled_player.has_ball
			and not controlled_player.is_goalkeeper
		):
			_try_fake(FakeMotion.Kind.PASS)
		else:
			_cycle_bench_select()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("confirm_sub"):
		_try_substitution()
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
	# Wave 3 fakes — keep ball; cancel charge; never fire shot/pass.
	# Dive (C/B) on an outfielder with the ball = shot fake (GK still dives in player.gd).
	if (
		event.is_action_pressed("dive")
		and match_state == MatchState.LIVE
		and controlled_player
		and controlled_player.has_ball
		and not controlled_player.is_goalkeeper
	):
		_try_fake(FakeMotion.Kind.SHOT)
		get_viewport().set_input_as_handled()
		return
	if match_state == MatchState.LIVE and controlled_player and controlled_player.has_ball:
		if event.is_action_pressed("fake_shot"):
			_try_fake(FakeMotion.Kind.SHOT)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("fake_pass"):
			_try_fake(FakeMotion.Kind.PASS)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("fake_jab"):
			_try_fake(FakeMotion.Kind.JAB)
			get_viewport().set_input_as_handled()
			return
	# Pass first so RMB/G/RB never starts or finishes a shoot-charge.
	if event.is_action_pressed("pass_ball") and match_state == MatchState.LIVE:
		if controlled_player and controlled_player.is_faking():
			get_viewport().set_input_as_handled()
			return
		_end_controlled_dribble()
		_try_pass()
		get_viewport().set_input_as_handled()
		return
	# Phase 3: hold shoot to charge, release to fire. Tap still works (min power).
	if event.is_action_pressed("shoot") and match_state == MatchState.LIVE:
		if _pass_suppress_shoot:
			get_viewport().set_input_as_handled()
			return
		if controlled_player and controlled_player.is_faking():
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
			if controlled_player and controlled_player.is_faking():
				_cancel_charge()
			else:
				_release_charged_shot()
			get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	_update_camera_attack_side()
	_update_camera_nudge(delta)
	_update_shot_charge(delta)
	_update_dribble_input()
	_park_bench_players()
	_update_stamina_hud()
	_update_sub_hud()
	if match_state != MatchState.LIVE:
		return
	clock_remaining = maxf(0.0, clock_remaining - delta)
	if hud and hud.has_method("set_clock"):
		hud.set_clock(clock_remaining)
	_tick_exclusions(delta)
	_tick_seven_m_ready(delta)
	_update_away_shapes()
	_update_rules_hud()
	_update_shot_hud()
	_update_shapes_hud()
	# Phase D: shoot charge counts as windup for contact fouls near the arc.
	rules.set_windup(_charging and controlled_player != null and controlled_player.has_ball, true)
	if rules.tick(delta, ball, _all_players()):
		rules.set_windup(false)
		_clear_seven_m_ready()
		return
	if clock_remaining <= 0.0:
		_on_period_expired()


## Wave 3: trigger a fake; cancels shoot charge so release cannot fire.
func _try_fake(kind: int) -> void:
	var p := controlled_player
	if p == null or not p.has_ball or p.is_goalkeeper:
		return
	if ball == null or ball.carrier != p:
		return
	_end_controlled_dribble()
	if _charging:
		_cancel_charge()
	_pass_suppress_shoot = true
	var aim := _aim_direction_for(p)
	if kind == FakeMotion.Kind.PASS:
		var target := _best_pass_target(p, aim)
		if target:
			aim = target.global_position - p.global_position
	elif kind == FakeMotion.Kind.JAB:
		var wish := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if wish.length_squared() > 0.04:
			aim = p.camera_relative_wish(wish)
	p.try_fake(kind, aim)
	if hud and hud.has_method("flash_rule"):
		hud.flash_rule("Fake · %s" % FakeMotion.kind_name(kind), "fake")


func _aim_direction_for(p: Player) -> Vector3:
	if p == null:
		return Vector3.FORWARD
	# Reuse shot/pass aim so fakes match face vs mouse mode.
	if p == controlled_player:
		var aim := _compute_aim(false)
		if aim.length_squared() > 0.01:
			return aim
	return p.face_direction()


## Hold `dribble` (V / R3) while possessing to bounce; release gathers (new steps + 3 s).
## Wave 4: soft auto-start near 3 s / last step when legal (HUD still readable).
func _update_dribble_input() -> void:
	if match_state != MatchState.LIVE:
		_end_controlled_dribble()
		return
	_try_soft_auto_dribble()
	var p := controlled_player
	if p == null or not p.has_ball or p.is_goalkeeper or ball == null or ball.carrier != p:
		_end_controlled_dribble()
		return
	# Don't bounce while charging a shot — shoot owns the hands.
	if _charging or p.is_faking():
		_end_controlled_dribble()
		return
	var want := Input.is_action_pressed("dribble")
	if want:
		if not p.dribbling:
			if rules.try_begin_dribble(p):
				p.dribbling = true
			# Double-dribble violation is handled by rules → restart.
		elif rules.last_dribble_was_assist:
			# Player takes over the soft-assist stream; release will gather.
			rules.last_dribble_was_assist = false
	elif p.dribbling:
		if rules.last_dribble_was_assist:
			# Soft assist keeps bouncing until pass/shot or player takeover.
			pass
		else:
			_end_controlled_dribble()


## Soft assist for any live carrier (human or AI) near hold/step limits.
func _try_soft_auto_dribble() -> void:
	if not auto_dribble_assist or ball == null:
		return
	var carrier: Player = ball.carrier
	if carrier == null or carrier.is_goalkeeper or carrier.dribbling:
		return
	if _charging and carrier == controlled_player:
		return
	if carrier.has_method("is_faking") and carrier.is_faking():
		return
	if rules.try_auto_dribble_assist(carrier):
		carrier.dribbling = true
		_update_rules_hud()


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
	if _pass_suppress_shoot or controlled_player.is_faking():
		_cancel_charge()
		return
	# Keep charging while the shoot action is held (mouse / E / RT).
	if Input.is_action_pressed("shoot"):
		_charge_held_s += delta
		var lob_held := Input.is_action_pressed("lob")
		var charge_01 := ShotCraft.charge_01(_charge_held_s)
		var aim := _compute_aim(lob_held)
		controlled_player.set_shot_charge_motion(charge_01, lob_held, aim)
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
	_refresh_controlled_hud()


func _refresh_controlled_hud() -> void:
	if controlled_player == null or hud == null or not hud.has_method("set_controlled"):
		return
	var player := controlled_player
	var role := "GK"
	if not player.is_goalkeeper:
		var ball_x := ball.global_position.x if ball else 0.0
		role = Formations.role_label_hud(Formations.role_for(player), ball_x, false)
	hud.set_controlled("Team %s #%d (%s)" % [
		"Home" if player.team_id == 0 else "Away",
		player.player_index + 1,
		role
	])
	_update_stamina_hud()
	_update_sub_hud()


func _toggle_home_attack_shape() -> void:
	home_attack_shape = (
		Formations.AttackShape.CRASH
		if home_attack_shape == Formations.AttackShape.WIDE
		else Formations.AttackShape.WIDE
	)
	_sync_team_shapes()
	_update_shapes_hud()
	if hud and hud.has_method("flash_rule"):
		hud.flash_rule(
			"Attack %s" % Formations.attack_shape_label(home_attack_shape as Formations.AttackShape),
			"shape"
		)
	print("Home attack shape → %s" % Formations.attack_shape_label(home_attack_shape as Formations.AttackShape))


func _toggle_home_defense_shape() -> void:
	# Wave 6 R4.7: cycle 6-0 → 5-1 → 3-2-1 → Man → 6-0.
	home_defense_shape = Formations.next_defense_shape(home_defense_shape)
	_sync_team_shapes()
	_update_shapes_hud()
	if hud and hud.has_method("flash_rule"):
		hud.flash_rule(
			"Defense %s" % Formations.defense_shape_label(home_defense_shape as Formations.DefenseShape),
			"shape"
		)
	print("Home defense shape → %s" % Formations.defense_shape_label(home_defense_shape as Formations.DefenseShape))


## Push team shape enums onto each player so Formations slot helpers can read them.
func _sync_team_shapes() -> void:
	for p in _home_players:
		p.attack_shape = home_attack_shape
		p.defense_shape = home_defense_shape
		p.facing_defense_shape = away_defense_shape
	for p in _away_players:
		p.attack_shape = away_attack_shape
		p.defense_shape = away_defense_shape
		p.facing_defense_shape = home_defense_shape


## Away AI: score/time shape picks (Wave 6 adds 3-2-1 / Man lite).
## Losing late / down 2+ still picks 5-1 (OneUp) so Phase E smoke stays stable.
func _update_away_shapes() -> void:
	var score_diff := score_away - score_home
	var time_frac := clock_remaining / maxf(period_length_seconds, 1.0)
	var late := false
	if current_period >= periods_total:
		late = time_frac < 0.40
	else:
		late = time_frac < 0.20
	var next_atk := Formations.AttackShape.WIDE
	var next_def := Formations.DefenseShape.FLAT
	if score_diff < 0:
		# Losing: crash the line; press with 5-1 when late or down by 2+.
		# Down by 3+ late → man pressure (lite).
		next_atk = Formations.AttackShape.CRASH
		if score_diff <= -3 and late:
			next_def = Formations.DefenseShape.INDIVIDUAL
		elif late or score_diff <= -2:
			next_def = Formations.DefenseShape.ONE_UP
		else:
			next_def = Formations.DefenseShape.FLAT
	elif score_diff > 0:
		next_atk = Formations.AttackShape.WIDE
		next_def = Formations.DefenseShape.FLAT
	else:
		# Tied: late → Crash + 3-2-1; early → Wide + 6-0.
		next_atk = Formations.AttackShape.CRASH if late else Formations.AttackShape.WIDE
		next_def = (
			Formations.DefenseShape.THREE_TWO_ONE if late else Formations.DefenseShape.FLAT
		)
	if next_atk != away_attack_shape or next_def != away_defense_shape:
		away_attack_shape = next_atk
		away_defense_shape = next_def
		_sync_team_shapes()


func _update_shapes_hud() -> void:
	if hud == null:
		return
	_refresh_controlled_hud()
	if hud.has_method("set_shapes_status"):
		hud.set_shapes_status(
			Formations.attack_shape_label(home_attack_shape as Formations.AttackShape),
			Formations.defense_shape_label(home_defense_shape as Formations.DefenseShape)
		)


func _cycle_teammate() -> void:
	var roster := _on_court_players(controlled_team_id)
	if roster.size() < 2:
		return
	# Cycle: next on-court index (wrap), skipping excluded players.
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
	var roster := _on_court_players(controlled_team_id)
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


func _on_court_players(team_id: int) -> Array[Player]:
	var out: Array[Player] = []
	var roster := _home_players if team_id == 0 else _away_players
	for p in roster:
		if p.on_bench:
			continue
		out.append(p)
	return out


func _bench_players(team_id: int) -> Array[Player]:
	var out: Array[Player] = []
	var roster := _home_players if team_id == 0 else _away_players
	for p in roster:
		if p.on_bench and not p.excluded:
			out.append(p)
	return out


func _can_substitute_now() -> bool:
	# Dead ball / whistle windows only (Phase G first slice).
	return match_state in [
		MatchState.PRE_KICKOFF,
		MatchState.GOAL_PAUSE,
		MatchState.PERIOD_BREAK,
		MatchState.RULE_RESTART,
	]


func _cycle_bench_select() -> void:
	var bench := _bench_players(controlled_team_id)
	if bench.is_empty():
		_bench_select_i = 0
		_update_sub_hud()
		return
	_bench_select_i = (_bench_select_i + 1) % bench.size()
	_update_sub_hud()
	if hud and hud.has_method("flash_rule"):
		var pick := bench[_bench_select_i]
		hud.flash_rule("Bench → #%d" % (pick.player_index + 1), "sub")


func _selected_bench_player() -> Player:
	var bench := _bench_players(controlled_team_id)
	if bench.is_empty():
		return null
	_bench_select_i = clampi(_bench_select_i, 0, bench.size() - 1)
	return bench[_bench_select_i]


## Swap controlled on-court outfielder with selected bench player (dead ball only).
func _try_substitution() -> void:
	if not _can_substitute_now():
		if hud and hud.has_method("flash_rule"):
			hud.flash_rule("Subs only on whistle", "sub")
		return
	var outgoing := controlled_player
	if outgoing == null or outgoing.is_goalkeeper or outgoing.on_bench or outgoing.excluded:
		if hud and hud.has_method("flash_rule"):
			hud.flash_rule("Select an outfielder to sub out", "sub")
		return
	if outgoing.has_ball:
		if hud and hud.has_method("flash_rule"):
			hud.flash_rule("Can't sub the ball carrier", "sub")
		return
	var incoming := _selected_bench_player()
	if incoming == null:
		if hud and hud.has_method("flash_rule"):
			hud.flash_rule("No bench player", "sub")
		return
	_swap_players_for_sub(outgoing, incoming)
	if hud and hud.has_method("flash_rule"):
		hud.flash_rule(
			"SUB %s ↔ #%d"
			% [Formations.role_label(Formations.role_for(incoming)), incoming.player_index + 1],
			"sub"
		)
	print(
		"SUB: %s off, %s on (role idx %d)"
		% [outgoing.name, incoming.name, incoming.player_index]
	)


func _swap_players_for_sub(outgoing: Player, incoming: Player) -> void:
	var out_idx := outgoing.player_index
	var out_pos := outgoing.global_position
	var out_start := outgoing.start_position
	var out_yaw := outgoing.rotation.y
	var out_start_yaw := outgoing.start_yaw
	var in_slot := incoming.bench_slot
	var in_idx := incoming.player_index

	# Outgoing → bench (keeps a high bench index for identity; role rides with index swap).
	outgoing.on_bench = true
	outgoing.player_index = in_idx
	outgoing.bench_slot = in_slot
	outgoing.ai_enabled = false
	outgoing.controlled = false
	outgoing.velocity = Vector3.ZERO
	outgoing.global_position = Court.bench_marker(outgoing.team_id, in_slot)
	outgoing.rotation.y = Court.bench_yaw(outgoing.team_id)
	outgoing.start_position = outgoing.global_position
	outgoing.start_yaw = outgoing.rotation.y

	# Incoming inherits the court role / slot.
	incoming.on_bench = false
	incoming.player_index = out_idx
	incoming.bench_slot = 0
	incoming.global_position = out_pos
	incoming.start_position = out_start
	incoming.start_yaw = out_start_yaw
	incoming.rotation.y = out_yaw
	incoming.velocity = Vector3.ZERO
	incoming.attack_shape = outgoing.attack_shape
	incoming.defense_shape = outgoing.defense_shape
	incoming.facing_defense_shape = outgoing.facing_defense_shape
	_set_controlled(incoming)
	_configure_ai()
	_park_bench_players()
	_update_sub_hud()


func _park_bench_players() -> void:
	for p in _all_players():
		if not p.on_bench:
			continue
		if p.excluded:
			continue
		p.global_position = Court.bench_marker(p.team_id, maxi(0, p.bench_slot))
		p.rotation.y = Court.bench_yaw(p.team_id)
		p.velocity = Vector3.ZERO
		p.ai_enabled = false
		p.has_ball = false
		p.dribbling = false


func _update_stamina_hud() -> void:
	if hud == null or not hud.has_method("set_stamina"):
		return
	if controlled_player == null:
		hud.set_stamina(1.0, false)
		return
	hud.set_stamina(controlled_player.stamina_01(), controlled_player.sprinting)


func _update_sub_hud() -> void:
	if hud == null or not hud.has_method("set_sub_status"):
		return
	var can_sub := _can_substitute_now()
	var bench := _bench_players(controlled_team_id)
	var label := ""
	if not bench.is_empty():
		var pick := _selected_bench_player()
		if pick:
			label = "Bench #%d" % (pick.player_index + 1)
	hud.set_sub_status(can_sub, label, bench.size())


func _cancel_charge() -> void:
	_charging = false
	_charge_held_s = 0.0
	if controlled_player:
		controlled_player.clear_shot_charge_motion()
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
	var wing := ThrowMotion.is_wing_finish_context(controlled_player)
	if wing:
		aim = ThrowMotion.wing_aim_assist(controlled_player, aim)
	var jump_q := ShotCraft.jump_shot_quality(controlled_player)
	var impulse := ShotCraft.impulse_for_charge(charge, lob)
	var timed := ShotCraft.apply_jump_timing(aim, impulse, jump_q)
	aim = timed["aim"]
	impulse = timed["impulse"]
	# Phase F: timed sweet window stacks a small bonus on top of height sweet.
	if controlled_player.jump_shot_active:
		impulse = ShotCraft.apply_window_bonus(impulse, jump_q, controlled_player.jump_shot_air_s)
	# Phase G: low stamina softens accuracy (lateral scatter) and impulse slightly.
	var acc := controlled_player.stamina_accuracy_mul()
	if acc < 0.98:
		var scatter := (1.0 - acc) * 0.22
		aim += Vector3(randf_range(-scatter, scatter), randf_range(-scatter * 0.35, scatter * 0.2), randf_range(-scatter * 0.4, scatter * 0.4))
		aim = aim.normalized()
		impulse *= lerpf(0.88, 1.0, acc)
	var up := ShotCraft.up_bias(lob)
	# Jump shots naturally loft a touch more.
	if jump_q >= 0:
		up += 0.08 if jump_q == 1 else 0.04
	var meta := {
		"charge": charge,
		"lob": lob,
		"jump_quality": jump_q,
		"impulse": impulse,
		"jump_shot": controlled_player.jump_shot_active,
		"jump_air_s": controlled_player.jump_shot_air_s,
		"jump_phase": controlled_player.jump_shot_phase,
		"stamina": controlled_player.stamina_01(),
		"wing_shot": wing,
	}
	var from := controlled_player.global_position + Vector3(0, 1.2, 0)
	if controlled_player.try_shoot(aim, impulse, ball, up, meta):
		_spawn_shot_trace(from, aim, lob, jump_q)
		# Nearby defending outfield raise hands for the contest window.
		_nudge_defenders_to_block(controlled_player.team_id, from, aim)
		# Wave 6 R5.3: brief wing-corridor cinematic (zoom + slow-mo).
		if wing and camera_rig:
			camera_rig.trigger_wing_cinematic()
	if hud and hud.has_method("set_shot_status"):
		hud.set_shot_status(0.0, false, "", false)


## Instant tap path used by smoke / scripts (full mid charge, flat).
func _try_shoot() -> void:
	_try_shoot_charged(ShotCraft.CHARGE_TIME_S * 0.55)


## Soft pass to best teammate in the aim cone (light lead assist). Never fires a shot.
## Pass types: flat (default) · bounce (hold B / D-pad Left) · lob (hold F / LT).
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
	var lob_held := Input.is_action_pressed("lob")
	var bounce_held := Input.is_action_pressed("bounce_pass")
	var pass_type := PassCraft.resolve_pass_type(lob_held, bounce_held)
	var aim_hint := _compute_aim(pass_type == PassCraft.PassType.LOB)
	aim_hint.y = 0.0
	if aim_hint.length_squared() < 0.01:
		aim_hint = controlled_player.face_direction()
		aim_hint.y = 0.0
	var target := _best_pass_target(controlled_player, aim_hint)
	if target:
		controlled_player.try_pass_to(target, ball, -1.0, aim_hint, pass_type)
		return
	# No open mate in cone — soft toss along aim so the action never feels dead.
	var toss := aim_hint.normalized()
	var loft := PassCraft.LOFT_MIN + 0.04
	match pass_type:
		PassCraft.PassType.LOB:
			toss.y = 0.35
			loft = PassCraft.LOB_LOFT_MIN
		PassCraft.PassType.BOUNCE:
			toss.y = -0.35
			loft = 0.0
		_:
			toss.y = 0.1
	toss = toss.normalized()
	controlled_player.try_shoot(
		toss,
		PASS_IMPULSE_MIN + 0.5,
		ball,
		loft,
		{"pass": true, "charge": 0.25, "pass_type": pass_type}
	)


func _best_pass_target(passer: Player, aim_hint: Vector3 = Vector3.ZERO) -> Player:
	if passer == null:
		return null
	var roster := _on_court_players(passer.team_id)
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
		if p.team_id == shooter_team or p.is_goalkeeper or p.on_bench or p.excluded:
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
	if jump_txt.is_empty() and controlled_player.jump_shot_active:
		jump_txt = ShotCraft.jump_phase_label(controlled_player.jump_shot_phase)
	# While charging, shot HUD owns the line; otherwise surface a clear PASS prompt.
	hud.set_shot_status(charge, lob, jump_txt, _charging or jump_q >= 0 or controlled_player.jump_shot_active)
	if hud.has_method("set_pass_hint"):
		var pass_type := PassCraft.resolve_pass_type(
			Input.is_action_pressed("lob"),
			Input.is_action_pressed("bounce_pass")
		)
		hud.set_pass_hint(not _charging, pass_type)


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


## Wave 6 R5.2: nudge yaw / zoom / height from keys or right stick.
func _update_camera_nudge(delta: float) -> void:
	if camera_rig == null or match_state == MatchState.MATCH_OVER:
		return
	var yaw := Input.get_axis("camera_yaw_left", "camera_yaw_right")
	var zoom := Input.get_axis("camera_zoom_in", "camera_zoom_out")
	var height := Input.get_axis("camera_height_down", "camera_height_up")
	# Right stick (look_*): X = yaw, Y = zoom (up = closer).
	yaw += Input.get_axis("look_left", "look_right")
	var stick_y := Input.get_axis("look_up", "look_down")
	# Stick up (negative look_down axis in Godot often) → zoom in.
	zoom += -stick_y
	if absf(yaw) < 0.08:
		yaw = 0.0
	if absf(zoom) < 0.08:
		zoom = 0.0
	if absf(height) < 0.08:
		height = 0.0
	if absf(yaw) > 0.001 or absf(zoom) > 0.001 or absf(height) > 0.001:
		camera_rig.apply_nudge_input(yaw, zoom, height, delta)


func _on_ball_picked_up(player: Player) -> void:
	rules.on_pickup(player)
	_attack_team_id = player.team_id
	# Team control: while Home has the ball, always ride the carrier
	# (pickup, catch, GK gather, restart give). Never force Away control.
	if player != null and player.team_id == 0 and not player.on_bench and not player.excluded:
		if controlled_player != player:
			_set_controlled(player)
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
	_clear_seven_m_ready()
	# Wave 4 foul ladder: red → DQ; else 2-min exclusion on head touch / behind / 7 m.
	if (
		rules.last_foul_warrants_red
		and rules.last_fouler != null
		and is_instance_valid(rules.last_fouler)
	):
		_begin_red_card(rules.last_fouler)
	elif (
		rules.last_foul_warrants_exclusion
		and rules.last_fouler != null
		and is_instance_valid(rules.last_fouler)
	):
		# seven_m still gated by exclusion_on_seven_m; other codes always exclude.
		if code != "seven_m" or exclusion_on_seven_m:
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
		_give_ball_to(taker)
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
	# Soft-lock guard: never leave RULE_RESTART without a live ball + unfrozen roster.
	if taker != null and (ball.carrier != taker or not taker.has_ball):
		_give_ball_to(taker)
		rules.on_pickup(taker)
	rules.end_lockout()
	_set_players_frozen(false)
	match_state = MatchState.LIVE
	# Wave 4 / R3.11: arm 7 m ready window once the set piece goes live.
	if Formations.is_seven_meter_code(code):
		_seven_m_live = true
		_seven_m_timer = 0.0
		_seven_m_award_team = awarding_team_id
	else:
		_clear_seven_m_ready()
	_update_rules_hud()


func _place_set_piece(code: String, awarding_team_id: int, spot: Vector3, taker: Player) -> void:
	var seven := Formations.is_seven_meter_code(code)
	for p in _all_players():
		var place := Formations.set_piece_slot(p, code, awarding_team_id, spot, taker)
		if p.excluded:
			place = Court.bench_marker(p.team_id, 2 + maxi(0, p.player_index % 4))
		elif p.on_bench:
			place = Court.bench_marker(p.team_id, maxi(0, p.bench_slot))
		p.global_position = place
		p.velocity = Vector3.ZERO
		# Wave 3: defending GK locked to 4 m restraining line during 7 m.
		if p.is_goalkeeper:
			p.set_seven_meter_lock(seven and p.team_id != awarding_team_id)
		else:
			p.set_seven_meter_lock(false)
		var face := 0.0 if p.team_id == 0 else PI
		if code == "throw_in":
			face = -PI * 0.5 if spot.x > 0.0 else PI * 0.5
		elif seven:
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
		if p.on_bench or p.excluded:
			face = Court.bench_yaw(p.team_id)
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


## Reliable restart/kickoff possession — never leave a free ball after a whistle.
func _give_ball_to(taker: Player) -> void:
	if taker == null or ball == null:
		return
	if ball.carrier and ball.carrier != taker:
		ball.carrier.has_ball = false
		ball.carrier.dribbling = false
	ball.carrier = null
	ball._last_carrier = null
	ball._ignore_carrier_until = 0.0
	ball.freeze = false
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	ball.global_position = taker.ball_attach.global_position
	if not ball.try_pickup(taker):
		# Force attach if Area/ignore timing races under load.
		ball.carrier = taker
		ball.freeze = true
		ball.collision_layer = 0
		ball.collision_mask = 0
		ball.global_position = taker.ball_attach.global_position
		ball.picked_up.emit(taker)
	taker.has_ball = true
	taker.dribbling = false


func _goalkeeper_for(team_id: int) -> Player:
	var roster := _home_players if team_id == 0 else _away_players
	for p in roster:
		if p.is_goalkeeper:
			return p
	return null


func _nearest_outfield(team_id: int, spot: Vector3) -> Player:
	var roster := _on_court_players(team_id)
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
	if fouler == null or fouler.is_goalkeeper or fouler.disqualified:
		return
	fouler.excluded = true
	fouler.exclusion_remaining = exclusion_seconds
	fouler.ai_enabled = false
	fouler.controlled = false
	fouler.has_ball = false
	fouler.dribbling = false
	fouler.velocity = Vector3.ZERO
	# Park beyond voluntary bench slots so exclusion doesn't stack on subs.
	var excl_slot := 2 + maxi(0, fouler.player_index % 4)
	fouler.global_position = Court.bench_marker(fouler.team_id, excl_slot)
	if controlled_player == fouler:
		var fallback := _nearest_outfield(fouler.team_id, fouler.global_position)
		if fallback == null:
			fallback = _first_outfield(_on_court_players(fouler.team_id))
		if fallback:
			_set_controlled(fallback)
	_configure_ai()
	print(
		"EXCLUSION lite: %s benched for %.0fs"
		% [fouler.name, exclusion_seconds]
	)
	if hud and hud.has_method("flash_rule"):
		hud.flash_rule("2 min exclusion", "exclusion")


## Wave 4 / R3.6: violent head strike → red card (DQ for the match, roster hole).
func _begin_red_card(fouler: Player) -> void:
	if fouler == null or fouler.is_goalkeeper:
		return
	fouler.disqualified = true
	fouler.excluded = true
	fouler.exclusion_remaining = 9999.0
	fouler.ai_enabled = false
	fouler.controlled = false
	fouler.has_ball = false
	fouler.dribbling = false
	fouler.velocity = Vector3.ZERO
	var excl_slot := 2 + maxi(0, fouler.player_index % 4)
	fouler.global_position = Court.bench_marker(fouler.team_id, excl_slot)
	if controlled_player == fouler:
		var fallback := _nearest_outfield(fouler.team_id, fouler.global_position)
		if fallback == null:
			fallback = _first_outfield(_on_court_players(fouler.team_id))
		if fallback:
			_set_controlled(fallback)
	_configure_ai()
	print("RED CARD: %s disqualified (head contact)" % fouler.name)
	if hud and hud.has_method("flash_rule"):
		hud.flash_rule("RED — head contact", "red_card")


func _tick_exclusions(delta: float) -> void:
	for p in _all_players():
		if not p.excluded:
			continue
		# Keep parked on the sideline while the clock runs.
		var excl_slot := 2 + maxi(0, p.player_index % 4)
		p.global_position = Court.bench_marker(p.team_id, excl_slot)
		p.velocity = Vector3.ZERO
		p.ai_enabled = false
		if p.disqualified:
			continue
		p.exclusion_remaining = maxf(0.0, p.exclusion_remaining - delta)
		if p.exclusion_remaining <= 0.0:
			_end_exclusion(p)


func _end_exclusion(player: Player) -> void:
	if player == null or player.disqualified:
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


func _clear_seven_m_ready() -> void:
	_seven_m_live = false
	_seven_m_timer = 0.0


## Wave 4 / R3.11: approx ready limit on 7 m — stall → goal throw to defense.
func _tick_seven_m_ready(delta: float) -> void:
	if not _seven_m_live or match_state != MatchState.LIVE:
		return
	_seven_m_timer += delta
	# Shot / pass / lost ball clears the window.
	if ball == null or ball.carrier == null or ball.carrier.team_id != _seven_m_award_team:
		_clear_seven_m_ready()
		return
	if _charging:
		return
	if _seven_m_timer < HandballRules.SEVEN_M_READY_LIMIT_S:
		return
	_clear_seven_m_ready()
	var defend := 1 - _seven_m_award_team
	var spot := Vector3(0.0, 0.0, -16.8 if defend == 0 else 16.8)
	# Clear contact-foul warrants so the restart isn't treated as a personal foul.
	rules.last_fouler = null
	rules.last_foul_warrants_exclusion = false
	rules.last_foul_warrants_red = false
	rules.last_foul_kind = ""
	rules.rule_violation.emit(
		"goal_throw",
		"7 m — time expired",
		defend,
		spot
	)


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
			var drib := rules.is_dribbling() or (ball.carrier != null and ball.carrier.dribbling)
			# Wave 4: AUTO pip when soft assist started the bounce stream.
			hud.set_hold_status(
				rules.get_hold_remaining(),
				HandballRules.HOLD_MAX_S,
				true,
				drib,
				rules.is_hold_warned(),
				rules.last_dribble_was_assist and drib
			)
		else:
			hud.set_hold_status(0.0, HandballRules.HOLD_MAX_S, false, false, false, false)
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
	# Wave 4: exclusion / red clocks (R3.5–R3.7 HUD).
	for p in _all_players():
		if p.disqualified:
			parts.append("RED %s" % p.name)
		elif p.excluded and p.exclusion_remaining > 0.0 and p.exclusion_remaining < 9000.0:
			parts.append("2′ %s %.0fs" % [p.name, p.exclusion_remaining])
	if _seven_m_live:
		var left := maxf(0.0, HandballRules.SEVEN_M_READY_LIMIT_S - _seven_m_timer)
		parts.append("7m %.0fs" % left)
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
	var roster := _on_court_players(kickoff_team_id)
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
		_give_ball_to(taker)
		_attack_team_id = kickoff_team_id
		camera_rig.set_attack_direction(kickoff_team_id == 0)
		rules.on_pickup(taker)
	# Human always controls Home. When Home kicks off, ride the taker;
	# otherwise keep an on-court Home outfielder for defense.
	if kickoff_team_id == 0 and taker != null and taker.team_id == 0:
		_set_controlled(taker)
	else:
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
		p.set_seven_meter_lock(false)
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
				# Bench / exclusion sit on the sideline — don't shove them onto court.
				if a.on_bench or b.on_bench or a.excluded or b.excluded:
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
	_update_shapes_hud()


func _first_outfield(roster: Array[Player]) -> Player:
	for p in roster:
		if not p.is_goalkeeper and not p.excluded and not p.on_bench:
			return p
	return null


func _aim_mode_label() -> String:
	return "Aim: Face" if aim_mode == AimMode.FACE else "Aim: Mouse"

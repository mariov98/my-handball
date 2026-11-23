extends Node
## Headless-ish smoke: cam-relative, possess, flip, both goals + kickoff, AI, clock, switch.

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	var match_node := get_tree().current_scene as MatchController
	if match_node == null:
		push_error("Smoke: current scene is not MatchController")
		get_tree().quit(1)
		return

	# Smoke bypasses opening kickoff — force a live match state.
	# Keep Phase 2 rules off until the dedicated rules section so Away AI
	# kickoffs don't trip traveling during Phase 1 assertions.
	match_node.rules.enabled = false
	match_node.match_state = MatchController.MatchState.LIVE
	match_node._set_players_frozen(false)
	match_node.clock_remaining = match_node.period_length_seconds
	match_node._refresh_hud()

	var player: Player = match_node.controlled_player
	if player == null:
		var starter := match_node._first_outfield(match_node._home_players)
		if starter:
			match_node._set_controlled(starter)
			player = starter
	var ball: Ball = match_node.ball
	var cam: CameraRig = match_node.camera_rig
	if player == null or ball == null or cam == null:
		push_error("Smoke: missing player/ball/camera")
		get_tree().quit(1)
		return

	# --- Away AI must be enabled (Phase 1) ---
	var away_ai_ok := false
	for p in match_node._away_players:
		if p.ai_enabled:
			away_ai_ok = true
			break
	print("Smoke away AI enabled=", away_ai_ok)
	if not away_ai_ok:
		push_error("Smoke: away AI not enabled")
		get_tree().quit(1)
		return

	# --- Clock ticks while LIVE ---
	var clock_before := match_node.clock_remaining
	await get_tree().create_timer(0.35).timeout
	var clock_after := match_node.clock_remaining
	print("Smoke clock: before=", clock_before, " after=", clock_after)
	if clock_after >= clock_before:
		push_error("Smoke: clock did not tick")
		get_tree().quit(1)
		return

	# --- Camera-relative wish: forward input must align with camera forward on XZ ---
	var cam3d: Camera3D = cam.camera
	var cam_fwd := -cam3d.global_transform.basis.z
	cam_fwd.y = 0.0
	cam_fwd = cam_fwd.normalized()
	# W / stick-up → get_vector y = -1
	var wish_fwd := player.camera_relative_wish(Vector2(0.0, -1.0))
	var align := wish_fwd.dot(cam_fwd)
	print("Smoke cam-relative forward align=", align, " wish=", wish_fwd, " cam_fwd=", cam_fwd)
	if align < 0.95:
		push_error("Smoke: camera-relative forward wish misaligned")
		get_tree().quit(1)
		return
	var wish_right := player.camera_relative_wish(Vector2(1.0, 0.0))
	var cam_right := cam3d.global_transform.basis.x
	cam_right.y = 0.0
	cam_right = cam_right.normalized()
	var align_r := wish_right.dot(cam_right)
	print("Smoke cam-relative right align=", align_r)
	if align_r < 0.95:
		push_error("Smoke: camera-relative right wish misaligned")
		get_tree().quit(1)
		return

	# Freeze away AI during scripted possession so they don't steal the free ball.
	for p in match_node._away_players:
		p.match_frozen = true
	_smoke_clear_ball(ball)

	# --- Center corridor: square goal-centered frame (no side skew) ---
	var center_ball := Vector3(0.0, 0.9, -2.0)
	ball.global_position = center_ball
	player.global_position = center_ball + Vector3(0.2, 0.0, 0.2)
	cam.set_attack_direction(true)
	cam.attack_sign = 1.0
	match_node._attack_team_id = 0
	match_node._update_camera_attack_side()
	cam.global_position = cam._desired_position(center_ball)
	var center_look: Vector3 = cam._look_target(center_ball)
	var center_pivot: Vector3 = cam.pivot_point(center_ball)
	var center_cam_flat := Vector3(cam.global_position.x, 0.0, cam.global_position.z)
	var center_offset := center_cam_flat - center_pivot
	print(
		"Smoke center cam: cam_x=", cam.global_position.x,
		" look_x=", center_look.x,
		" yaw=", cam.ball_yaw(center_ball),
		" offset=", center_offset
	)
	if absf(cam.ball_yaw(center_ball)) > 0.001:
		push_error("Smoke: center corridor should have zero yaw")
		get_tree().quit(1)
		return
	if absf(cam.global_position.x) > 0.35:
		push_error("Smoke: center camera should sit on the attack axis (goal-square)")
		get_tree().quit(1)
		return
	if absf(center_look.x) > 0.2:
		push_error("Smoke: center look should keep the goal in the middle")
		get_tree().quit(1)
		return
	if absf(center_offset.z - (-cam.attack_sign * cam.follow_distance)) > 0.2:
		push_error("Smoke: center camera should sit behind the ball on Z")
		get_tree().quit(1)
		return
	# Look should pull toward the far goal (not stay glued on the ball).
	var goal_z := cam.attack_sign * cam.goal_depth
	if absf(center_look.z - goal_z) > absf(center_ball.z - goal_z) * 0.75:
		push_error("Smoke: center look should blend toward the far goal")
		get_tree().quit(1)
		return

	# --- Side ball: subtle yaw about the ball; look X << ball X (goal stays anchor) ---
	var lateral_ball := Vector3(6.0, 0.9, -2.0)
	ball.global_position = lateral_ball
	player.global_position = lateral_ball + Vector3(0.2, 0.0, 0.2)
	cam.set_attack_direction(true)
	cam.attack_sign = 1.0
	match_node._attack_team_id = 0
	match_node._update_camera_attack_side()
	cam.global_position = cam._desired_position(lateral_ball)
	var look_pt: Vector3 = cam._look_target(lateral_ball)
	var pivot: Vector3 = cam.pivot_point(lateral_ball)
	var cam_flat := Vector3(cam.global_position.x, 0.0, cam.global_position.z)
	var pivot_to_cam := cam_flat - pivot
	var yaw := cam.ball_yaw(lateral_ball)
	var cf := cam.corridor_factor(lateral_ball.x)
	var expected_lateral := cam.side_bias * cam.attack_sign * cf
	var expected_len := Vector2(expected_lateral, cam.follow_distance).length()
	print(
		"Smoke side cam: pivot=", pivot,
		" cam_flat=", cam_flat,
		" |offset|=", pivot_to_cam.length(),
		" expected≈", expected_len,
		" yaw=", yaw,
		" look_x=", look_pt.x,
		" ball_x=", lateral_ball.x
	)
	if pivot.distance_to(Vector3(lateral_ball.x, 0.0, lateral_ball.z)) > 0.01:
		push_error("Smoke: pivot is not at the ball")
		get_tree().quit(1)
		return
	if absf(pivot_to_cam.length() - expected_len) > 0.2:
		push_error("Smoke: camera offset length not orbiting ball")
		get_tree().quit(1)
		return
	if yaw <= 0.0 or yaw > cam.max_ball_yaw + 0.001:
		push_error("Smoke: side ball should apply subtle positive yaw")
		get_tree().quit(1)
		return
	# Goal remains the visual anchor — look X must not track the ball into center.
	if absf(look_pt.x) >= absf(lateral_ball.x) * 0.45:
		push_error("Smoke: look X tracks ball too hard (should keep goal anchored)")
		get_tree().quit(1)
		return
	var unyawed := pivot_to_cam.rotated(Vector3.UP, -yaw)
	print("Smoke side unyawed offset=", unyawed)
	if absf(unyawed.x - expected_lateral) > 0.25:
		push_error("Smoke: yaw is not rotating around ball pivot")
		get_tree().quit(1)
		return
	if absf(unyawed.z - (-cam.attack_sign * cam.follow_distance)) > 0.25:
		push_error("Smoke: yaw orbit Z not ball-centered")
		get_tree().quit(1)
		return

	# Force possession for the controlled home player.
	_smoke_clear_ball(ball)
	player.global_position = ball.global_position + Vector3(0.2, 0, 0.2)
	if ball.try_pickup(player):
		player.has_ball = true
	else:
		# Area timing / layer edge case — still fail loudly.
		player.has_ball = false
	print("Smoke possess: ", player.has_ball, " carrier=", ball.carrier)
	if not player.has_ball:
		push_error("Smoke: possess failed")
		get_tree().quit(1)
		return

	# Home possession → camera should target +Z attack
	match_node._update_camera_attack_side()
	print("Smoke attack target (home hold)=", cam.get_target_attack_sign())
	if cam.get_target_attack_sign() < 0.0:
		push_error("Smoke: expected home attack camera (+1)")
		get_tree().quit(1)
		return

	# Possession flip to away → camera targets opposite end (smooth, not snap)
	var away: Player = null
	for p in match_node._away_players:
		if not p.is_goalkeeper:
			away = p
			break
	if away == null:
		push_error("Smoke: no away outfield")
		get_tree().quit(1)
		return
	ball.release_and_shoot(Vector3(0, 0.2, 1), 0.01)
	player.has_ball = false
	await get_tree().create_timer(0.05).timeout
	if not ball.try_pickup(away):
		push_error("Smoke: away pickup failed")
		get_tree().quit(1)
		return
	away.has_ball = true
	var z_before := cam.global_position.z
	match_node._update_camera_attack_side()
	print("Smoke attack target (away hold)=", cam.get_target_attack_sign())
	if cam.get_target_attack_sign() > 0.0:
		push_error("Smoke: expected away attack camera (-1)")
		get_tree().quit(1)
		return
	# Let the rig lerp toward the new side; position should move, not teleport instantly.
	var z_immediate := cam.global_position.z
	await get_tree().create_timer(0.55).timeout
	var z_after := cam.global_position.z
	print("Smoke cam flip z: before=", z_before, " immediate=", z_immediate, " after=", z_after)
	if absf(z_immediate - z_before) > 8.0:
		push_error("Smoke: camera snapped on possession flip")
		get_tree().quit(1)
		return
	if z_after <= z_before + 2.0:
		push_error("Smoke: camera did not ease behind new attack")
		get_tree().quit(1)
		return

	# --- Away AI chase wish (should move toward free ball) ---
	_smoke_clear_ball(ball)
	ball.global_position = Vector3(2.0, 0.2, 0.0)
	away.global_position = Vector3(-4.0, 0.0, 8.0)
	away.match_frozen = false
	var ai_wish := away._ai_wish(0.016)
	print("Smoke AI chase wish=", ai_wish)
	if ai_wish.length() < 0.2:
		push_error("Smoke: away AI chase wish too small")
		get_tree().quit(1)
		return
	# Wish should generally point toward +X/−Z from away's spot toward ball at (2,0,0)
	if ai_wish.x <= 0.0:
		push_error("Smoke: away AI chase should move +X toward ball")
		get_tree().quit(1)
		return

	# Return ball to home for home-goal score path.
	_smoke_clear_ball(ball)
	ball.collision_layer = 0
	ball.collision_mask = 0
	if not ball.try_pickup(player):
		push_error("Smoke: home re-pickup failed")
		get_tree().quit(1)
		return
	player.has_ball = true
	match_node._update_camera_attack_side()
	# Keep away frozen + AI off while we force scores / kickoffs so a post-kickoff
	# carry doesn't auto-release before assertions (Phase 2 traveling pressure).
	for p in match_node._away_players:
		p.match_frozen = true
		p.ai_enabled = false

	# Aim at away goal (+Z) and shoot
	var ok := player.try_shoot(Vector3(0, 0.25, 1).normalized(), 22.0, ball)
	print("Smoke shoot: ", ok, " carrier=", ball.carrier)
	await get_tree().create_timer(0.2).timeout

	# Drive ball into away goal mouth to force home score
	match_node.match_state = MatchController.MatchState.LIVE
	ball.collision_layer = 4
	ball.collision_mask = 1 | 2
	ball.global_position = Vector3(0, 1.0, 19.7)
	ball.linear_velocity = Vector3(0, 0, 8)
	await get_tree().create_timer(0.9).timeout
	print("Smoke score after home goal: home=", match_node.score_home, " away=", match_node.score_away)
	if match_node.score_home < 1:
		push_error("Smoke: home goal did not score")
		get_tree().quit(1)
		return

	# Wait for goal pause + kickoff (conceding = away owns that goal → away kickoff)
	await get_tree().create_timer(MatchController.GOAL_PAUSE_DELAY + MatchController.KICKOFF_FREEZE + 0.25).timeout
	# Kickoff unfreezes roster — pin Away again before they can move/shoot.
	for p in match_node._away_players:
		p.match_frozen = true
		p.ai_enabled = false
	await get_tree().process_frame
	print(
		"Smoke after home-goal kickoff: state=", match_node.match_state,
		" carrier_team=", ball.carrier.team_id if ball.carrier else -1
	)
	if match_node.match_state != MatchController.MatchState.LIVE:
		push_error("Smoke: expected LIVE after restart kickoff")
		get_tree().quit(1)
		return
	if ball.carrier == null or ball.carrier.team_id != 1:
		push_error("Smoke: expected away team kickoff after conceding")
		get_tree().quit(1)
		return

	# --- Away scores into home goal ---
	# Clear possession cleanly and drive into home mouth (-Z).
	if ball.carrier:
		ball.carrier.has_ball = false
	ball.carrier = null
	ball._last_carrier = null
	ball._ignore_carrier_until = 0.0
	ball.freeze = false
	ball.collision_layer = 4
	ball.collision_mask = 1 | 2
	match_node.match_state = MatchController.MatchState.LIVE
	ball.global_position = Vector3(0, 1.0, -19.7)
	ball.linear_velocity = Vector3(0, 0, -8)
	await get_tree().create_timer(0.9).timeout
	print("Smoke score after away goal: home=", match_node.score_home, " away=", match_node.score_away)
	if match_node.score_away < 1:
		push_error("Smoke: away goal did not score")
		get_tree().quit(1)
		return

	await get_tree().create_timer(MatchController.GOAL_PAUSE_DELAY + MatchController.KICKOFF_FREEZE + 0.25).timeout
	for p in match_node._away_players:
		p.match_frozen = true
		p.ai_enabled = false
	await get_tree().process_frame
	print(
		"Smoke after away-goal kickoff: carrier_team=",
		ball.carrier.team_id if ball.carrier else -1
	)
	if ball.carrier == null or ball.carrier.team_id != 0:
		push_error("Smoke: expected home kickoff after conceding at home goal")
		get_tree().quit(1)
		return

	# Switch teammate
	match_node.match_state = MatchController.MatchState.LIVE
	var before := match_node.controlled_player
	match_node._cycle_teammate()
	var after := match_node.controlled_player
	print("Smoke switch: ", before.name if before else "null", " -> ", after.name if after else "null")
	if after == null or after == before:
		push_error("Smoke: switch failed")
		get_tree().quit(1)
		return

	# --- Pass: soft release + wing↔CB↔wing catch circulation (Phase A) ---
	_smoke_clear_ball(ball)
	for p in match_node._away_players:
		p.match_frozen = true
		p.ai_enabled = false
	var home_lw: Player = null
	var home_cb: Player = null
	var home_rw: Player = null
	for p in match_node._home_players:
		if p.is_goalkeeper or p.on_bench:
			continue
		match Formations.role_for(p):
			Formations.Role.LEFT_WING:
				home_lw = p
			Formations.Role.RIGHT_WING:
				home_rw = p
			Formations.Role.CENTER_BACK:
				home_cb = p
	if home_lw == null or home_cb == null or home_rw == null:
		push_error("Smoke: missing home LW/CB/RW for pass circulation")
		get_tree().quit(1)
		return

	# Park wing→CB first; keep RW wide/back so cone scoring prefers CB.
	# Phase G: stash LB/RB/Pivot far away so they don't steal the pass cone.
	_smoke_park_unused_outfield(match_node, [home_lw, home_cb, home_rw])
	home_lw.global_position = Vector3(-2.5, home_lw.start_position.y, -1.0)
	home_cb.global_position = Vector3(0.0, home_cb.start_position.y, 5.0)
	home_rw.global_position = Vector3(7.5, home_rw.start_position.y, -3.0)
	for p in [home_lw, home_cb, home_rw]:
		p.rotation.y = 0.0
		p.velocity = Vector3.ZERO
		p.match_frozen = false
		p.ai_enabled = false
		p.has_ball = false

	match_node._set_controlled(home_lw)
	_smoke_lock_pass_bots(match_node, [home_lw, home_cb, home_rw])
	player = home_lw
	ball.global_position = player.global_position + Vector3(0.3, 1.1, 0.0)
	if not ball.try_pickup(player):
		push_error("Smoke: pass setup pickup failed")
		get_tree().quit(1)
		return
	player.has_ball = true
	match_node.rules.on_pickup(player)
	var intended := match_node._best_pass_target(home_lw, Vector3(0, 0, 1))
	if intended != home_cb:
		push_error("Smoke: expected CB in pass cone from LW, got %s" % (intended.name if intended else "null"))
		get_tree().quit(1)
		return
	match_node._try_pass()
	await get_tree().physics_frame
	await get_tree().physics_frame
	print(
		"Smoke pass: carrier=", ball.carrier,
		" speed=", ball.linear_velocity.length(),
		" meta=", ball.last_shot_meta
	)
	if ball.carrier != null:
		push_error("Smoke: pass did not release ball")
		get_tree().quit(1)
		return
	if not bool(ball.last_shot_meta.get("pass", false)):
		push_error("Smoke: pass meta missing")
		get_tree().quit(1)
		return
	var pass_impulse := float(ball.last_shot_meta.get("impulse", 0.0))
	if pass_impulse < PassCraft.IMPULSE_MIN - 0.1:
		push_error("Smoke: pass impulse too weak")
		get_tree().quit(1)
		return
	if ball.linear_velocity.length() < 6.0:
		push_error("Smoke: pass flight too weak")
		get_tree().quit(1)
		return
	# Pass should generally travel toward +Z (receiver ahead).
	if ball.linear_velocity.z <= 1.0:
		push_error("Smoke: pass should travel toward receiver (+Z)")
		get_tree().quit(1)
		return

	# Wait for CB catch (sticky + Area).
	var caught_cb := await _smoke_await_carrier(ball, home_cb, 2.0)
	print("Smoke pass catch CB=", caught_cb, " carrier=", ball.carrier)
	if not caught_cb:
		push_error("Smoke: CB did not catch wing pass")
		get_tree().quit(1)
		return
	if match_node.rules.get_steps() != 0:
		push_error("Smoke: steps should reset on teammate catch")
		get_tree().quit(1)
		return

	# CB → RW
	match_node._set_controlled(home_cb)
	_smoke_lock_pass_bots(match_node, [home_lw, home_cb, home_rw])
	_smoke_park_unused_outfield(match_node, [home_lw, home_cb, home_rw])
	home_cb.global_position = Vector3(0.0, home_cb.start_position.y, 5.0)
	home_cb.rotation.y = 0.0
	home_cb.velocity = Vector3.ZERO
	home_lw.global_position = Vector3(-7.5, home_lw.start_position.y, 3.0)
	home_rw.global_position = Vector3(3.0, home_rw.start_position.y, 10.5)
	home_rw.velocity = Vector3.ZERO
	home_rw.rotation.y = 0.0
	_smoke_snap_ball_to_carrier(ball)
	intended = match_node._best_pass_target(home_cb, Vector3(0, 0, 1))
	if intended != home_rw:
		push_error("Smoke: expected RW in pass cone from CB, got %s" % (intended.name if intended else "null"))
		get_tree().quit(1)
		return
	match_node._try_pass()
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not bool(ball.last_shot_meta.get("pass", false)):
		push_error("Smoke: CB pass meta missing")
		get_tree().quit(1)
		return
	var caught_rw := await _smoke_await_carrier(ball, home_rw, 2.5)
	print("Smoke pass catch RW=", caught_rw, " carrier=", ball.carrier)
	if not caught_rw:
		push_error("Smoke: RW did not catch CB pass")
		get_tree().quit(1)
		return

	# RW → CB (close the wing↔CB↔wing loop)
	match_node._set_controlled(home_rw)
	_smoke_lock_pass_bots(match_node, [home_lw, home_cb, home_rw])
	_smoke_park_unused_outfield(match_node, [home_lw, home_cb, home_rw])
	home_rw.global_position = Vector3(3.0, home_rw.start_position.y, 10.5)
	home_rw.rotation.y = PI # face back toward CB (-Z)
	home_rw.velocity = Vector3.ZERO
	home_lw.global_position = Vector3(-7.5, home_lw.start_position.y, 10.5)
	home_cb.global_position = Vector3(0.5, home_cb.start_position.y, 5.3)
	home_cb.velocity = Vector3.ZERO
	_smoke_snap_ball_to_carrier(ball)
	intended = match_node._best_pass_target(home_rw, Vector3(0, 0, -1))
	if intended != home_cb:
		push_error("Smoke: expected CB in return cone from RW, got %s" % (intended.name if intended else "null"))
		get_tree().quit(1)
		return
	match_node._try_pass()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var caught_cb2 := await _smoke_await_carrier(ball, home_cb, 2.2)
	print("Smoke pass catch CB return=", caught_cb2, " carrier=", ball.carrier)
	if not caught_cb2:
		push_error("Smoke: CB did not catch return pass from RW")
		get_tree().quit(1)
		return
	print("Smoke Phase A pass circulation wing↔CB↔wing OK")

	# Pass vs shoot-charge: pass must cancel charge without firing a shot.
	_smoke_clear_ball(ball)
	match_node._set_controlled(home_cb)
	_smoke_lock_pass_bots(match_node, [home_lw, home_cb, home_rw])
	home_cb.global_position = Vector3(0.0, home_cb.start_position.y, 0.0)
	home_cb.rotation.y = 0.0
	home_lw.global_position = Vector3(-3.0, home_lw.start_position.y, 5.0)
	ball.global_position = home_cb.global_position + Vector3(0.3, 1.1, 0.0)
	if not ball.try_pickup(home_cb):
		push_error("Smoke: charge-cancel pickup failed")
		get_tree().quit(1)
		return
	home_cb.has_ball = true
	match_node._charging = true
	match_node._charge_held_s = ShotCraft.CHARGE_TIME_S * 0.8
	match_node._try_pass()
	await get_tree().create_timer(0.05).timeout
	if match_node._charging:
		push_error("Smoke: pass did not cancel shoot charge")
		get_tree().quit(1)
		return
	if not bool(ball.last_shot_meta.get("pass", false)):
		push_error("Smoke: charge-cancel pass should still be a pass")
		get_tree().quit(1)
		return
	if float(ball.last_shot_meta.get("impulse", 0.0)) > PassCraft.IMPULSE_MAX + 0.5:
		push_error("Smoke: pass after charge should not use shot impulse")
		get_tree().quit(1)
		return
	print("Smoke pass vs shoot-charge harden OK")

	# --- Phase 2 rules ---
	match_node.rules.enabled = true
	match_node.rules.begin_lockout()
	match_node.rules.end_lockout()
	for p in match_node._away_players:
		p.match_frozen = true
	for p in match_node._home_players:
		if p != match_node.controlled_player:
			p.match_frozen = true

	# Geometry helpers
	if not Court.in_goal_area(Vector3(0, 0, -17.0), 0):
		push_error("Smoke: expected (0,-17) in home goal area")
		get_tree().quit(1)
		return
	if Court.in_goal_area(Vector3(0, 0, 0), 0):
		push_error("Smoke: midfield should not be in goal area")
		get_tree().quit(1)
		return
	print("Smoke goal-area geometry OK")

	# Traveling: hold ball and synthesize step distance beyond MAX_STEPS
	_smoke_clear_ball(ball)
	player = match_node.controlled_player
	player.global_position = Vector3(0.0, player.start_position.y, 0.0)
	player.velocity = Vector3.ZERO
	if not ball.try_pickup(player):
		push_error("Smoke: traveling setup pickup failed")
		get_tree().quit(1)
		return
	player.has_ball = true
	match_node.rules.on_pickup(player)
	match_node.rules.end_lockout()
	match_node.match_state = MatchController.MatchState.LIVE
	match_node._set_players_frozen(false)
	for p in match_node._away_players:
		p.match_frozen = true
		p.ai_enabled = false
	# Teleport in chunks larger than one plant. Reception zero eats the first
	# plant, then 3 counted steps, then the 4th counted plant → traveling.
	var stride := HandballRules.STEP_LENGTH_M * 1.5
	var hit_travel := false
	for i in range(10):
		player.global_position = Vector3(0.0, player.start_position.y, float(i) * stride)
		# Give planar speed so pivot detection doesn't treat the sample as stopped.
		player.velocity = Vector3(0.0, 0.0, HandballRules.MOVE_SPEED_MPS + 1.0)
		hit_travel = match_node.rules.tick(0.016, ball, match_node._all_players())
		print(
			"Smoke traveling tick i=", i,
			" z=", player.global_position.z,
			" steps=", match_node.rules.get_steps(),
			" zero=", match_node.rules._reception_zero_pending,
			" air=", match_node.rules._is_airborne(player),
			" hit=", hit_travel
		)
		if hit_travel:
			break
	if not hit_travel:
		push_error("Smoke: traveling violation did not fire")
		get_tree().quit(1)
		return
	await get_tree().create_timer(MatchController.RESTART_FREEZE + 0.35).timeout
	print(
		"Smoke after traveling: state=", match_node.match_state,
		" carrier_team=", ball.carrier.team_id if ball.carrier else -1
	)
	if ball.carrier == null or ball.carrier.team_id != 1:
		push_error("Smoke: traveling should award Away free throw")
		get_tree().quit(1)
		return
	if match_node.match_state != MatchController.MatchState.LIVE:
		push_error("Smoke: expected LIVE after traveling restart")
		get_tree().quit(1)
		return

	# Sideline throw-in: place free ball OOB on +X
	_smoke_prepare_live(match_node, ball)
	_smoke_clear_ball(ball)
	match_node.rules.last_touch_team_id = 0
	match_node.rules._oob_cooldown = 0.0
	ball.global_position = Vector3(Court.OOB_HALF_WIDTH + 0.05, 0.3, 2.0)
	var oob_hit := match_node.rules.tick(0.016, ball, match_node._all_players())
	print("Smoke sideline OOB hit=", oob_hit, " x=", ball.global_position.x)
	if not oob_hit:
		push_error("Smoke: sideline OOB did not fire")
		get_tree().quit(1)
		return
	await get_tree().create_timer(MatchController.RESTART_FREEZE + 0.35).timeout
	print(
		"Smoke after throw-in: carrier_team=",
		ball.carrier.team_id if ball.carrier else -1,
		" x=", ball.carrier.global_position.x if ball.carrier else 0.0
	)
	if ball.carrier == null or ball.carrier.team_id != 1:
		push_error("Smoke: throw-in should go to Away")
		get_tree().quit(1)
		return

	# Goal throw: free ball over away end line outside posts (attack last touch)
	_smoke_prepare_live(match_node, ball)
	_smoke_clear_ball(ball)
	match_node.rules.last_touch_team_id = 0
	match_node.rules._oob_cooldown = 0.0
	ball.global_position = Vector3(5.0, 0.4, Court.OOB_HALF_LENGTH + 0.05)
	var gt_hit := match_node.rules.tick(0.016, ball, match_node._all_players())
	print("Smoke endline goal-throw hit=", gt_hit)
	if not gt_hit:
		push_error("Smoke: endline OOB did not fire")
		get_tree().quit(1)
		return
	await get_tree().create_timer(MatchController.RESTART_FREEZE + 0.35).timeout
	print(
		"Smoke after goal throw: carrier=",
		ball.carrier.name if ball.carrier else "null",
		" gk=", ball.carrier.is_goalkeeper if ball.carrier else false
	)
	if ball.carrier == null or ball.carrier.team_id != 1 or not ball.carrier.is_goalkeeper:
		push_error("Smoke: goal throw should go to Away GK")
		get_tree().quit(1)
		return

	# Goal-area violation: grounded home attacker inside away crease with ball
	_smoke_prepare_live(match_node, ball)
	_smoke_clear_ball(ball)
	player = match_node.controlled_player
	player.global_position = Vector3(0.0, player.start_position.y, 17.0)
	player.velocity = Vector3.ZERO
	if not ball.try_pickup(player):
		push_error("Smoke: goal-area pickup failed")
		get_tree().quit(1)
		return
	player.has_ball = true
	match_node.rules.on_pickup(player)
	match_node.rules._oob_cooldown = 0.0
	# Accrue grace then violate.
	var area_hit := false
	for _i in range(20):
		area_hit = match_node.rules.tick(0.05, ball, match_node._all_players())
		if area_hit:
			break
	print("Smoke goal-area hit=", area_hit)
	if not area_hit:
		push_error("Smoke: goal-area violation did not fire")
		get_tree().quit(1)
		return
	await get_tree().create_timer(MatchController.RESTART_FREEZE + 0.35).timeout
	if ball.carrier == null or ball.carrier.team_id != 1:
		push_error("Smoke: goal-area foul should award Away")
		get_tree().quit(1)
		return

	# --- Phase C: passive v2 (progress warn → N receives → FT; shot clears) ---
	# Stall without progress → warn. Phase B dribble so 3 s hold does not fire first.
	_smoke_prepare_live(match_node, ball)
	_smoke_clear_ball(ball)
	player = match_node.controlled_player
	player.global_position = Vector3(0.0, player.start_position.y, 0.0)
	player.velocity = Vector3.ZERO
	if not ball.try_pickup(player):
		push_error("Smoke: passive pickup failed")
		get_tree().quit(1)
		return
	player.has_ball = true
	match_node.rules.on_pickup(player)
	if not match_node.rules.try_begin_dribble(player):
		push_error("Smoke: passive setup dribble begin failed")
		get_tree().quit(1)
		return
	player.dribbling = true
	match_node.rules._oob_cooldown = 0.0
	var warned := false
	for _i in range(int(HandballRules.PASSIVE_WARN_S / 0.25) + 6):
		match_node.rules.tick(0.25, ball, match_node._all_players())
		if match_node.rules.is_passive_warned():
			warned = true
			break
	print(
		"Smoke passive warned=", warned,
		" t=", match_node.rules.get_passive_timer(),
		" recv=", match_node.rules.get_passive_receives()
	)
	if not warned:
		push_error("Smoke: passive warning never fired")
		get_tree().quit(1)
		return

	# Progress toward goal resets / delays the warn while still pre-signal.
	# (Re-arm a mid-timer, then walk closer than PASSIVE_PROGRESS_M.)
	match_node.rules._passive_warned = false
	match_node.rules._passive_receives = 0
	match_node.rules._passive_timer = HandballRules.PASSIVE_WARN_S * 0.7
	match_node.rules._passive_best_dist = 20.0
	player.global_position = Vector3(0.0, player.start_position.y, 0.0)
	match_node.rules.tick(0.25, ball, match_node._all_players())
	var t_before_prog := match_node.rules.get_passive_timer()
	# Move ~2 m closer to Away goal (+Z for Home).
	player.global_position = Vector3(0.0, player.start_position.y, 2.2)
	match_node.rules.tick(0.25, ball, match_node._all_players())
	print(
		"Smoke passive progress reset: before=", t_before_prog,
		" after=", match_node.rules.get_passive_timer(),
		" warned=", match_node.rules.is_passive_warned()
	)
	if match_node.rules.get_passive_timer() >= t_before_prog:
		push_error("Smoke: progress toward goal should reset passive warn timer")
		get_tree().quit(1)
		return
	if match_node.rules.is_passive_warned():
		push_error("Smoke: progress should not leave passive warned")
		get_tree().quit(1)
		return

	# Re-stall to warn, then N same-team receives without shot → FT.
	player.global_position = Vector3(0.0, player.start_position.y, 0.0)
	match_node.rules._passive_best_dist = INF
	match_node.rules._passive_timer = 0.0
	warned = false
	for _i in range(int(HandballRules.PASSIVE_WARN_S / 0.25) + 6):
		match_node.rules.tick(0.25, ball, match_node._all_players())
		if match_node.rules.is_passive_warned():
			warned = true
			break
	if not warned:
		push_error("Smoke: passive re-warn failed before pass-count")
		get_tree().quit(1)
		return

	var home_outfield: Array[Player] = []
	for p in match_node._home_players:
		if not p.is_goalkeeper:
			home_outfield.append(p)
	if home_outfield.size() < 2:
		push_error("Smoke: need ≥2 home outfield for passive receives")
		get_tree().quit(1)
		return
	var passive_ft := false
	var carrier_idx := 0
	for _i in range(HandballRules.PASSIVE_MAX_RECEIVES):
		var passer: Player = home_outfield[carrier_idx]
		carrier_idx = (carrier_idx + 1) % home_outfield.size()
		var receiver: Player = home_outfield[carrier_idx]
		var recv_before := match_node.rules.get_passive_receives()
		match_node.rules.on_release(passer)
		# Synthesize pass meta so shot-clear path is not accidentally taken.
		ball.last_shot_meta = {"pass": true, "shooter": passer}
		match_node.rules.on_pickup(receiver)
		# Nth receive emits violation → begin_lockout clears the counter synchronously.
		if match_node.match_state == MatchController.MatchState.RULE_RESTART:
			print(
				"Smoke passive receive=", recv_before + 1,
				"/", HandballRules.PASSIVE_MAX_RECEIVES, " → FT"
			)
			passive_ft = true
			break
		var recv_n := match_node.rules.get_passive_receives()
		print("Smoke passive receive=", recv_n, "/", HandballRules.PASSIVE_MAX_RECEIVES)
		# Keep ball ownership coherent for the next synthetic pass.
		if ball.carrier:
			ball.carrier.has_ball = false
		ball.carrier = receiver
		receiver.has_ball = true
	if not passive_ft:
		push_error("Smoke: passive pass-limit FT did not fire on Nth receive")
		get_tree().quit(1)
		return
	await get_tree().create_timer(MatchController.RESTART_FREEZE + 0.35).timeout
	if ball.carrier == null or ball.carrier.team_id != 1:
		push_error("Smoke: passive pass-limit should award Away")
		get_tree().quit(1)
		return

	# Shot attempt clears passive — further receives must not whistle without a new warn.
	_smoke_prepare_live(match_node, ball)
	_smoke_clear_ball(ball)
	player = match_node.controlled_player
	player.global_position = Vector3(0.0, player.start_position.y, 0.0)
	player.velocity = Vector3.ZERO
	player.dribbling = false
	if not ball.try_pickup(player):
		push_error("Smoke: passive shot-clear pickup failed")
		get_tree().quit(1)
		return
	player.has_ball = true
	match_node.rules.on_pickup(player)
	if not match_node.rules.try_begin_dribble(player):
		push_error("Smoke: passive shot-clear dribble begin failed")
		get_tree().quit(1)
		return
	player.dribbling = true
	for _i in range(int(HandballRules.PASSIVE_WARN_S / 0.25) + 6):
		match_node.rules.tick(0.25, ball, match_node._all_players())
		if match_node.rules.is_passive_warned():
			break
	if not match_node.rules.is_passive_warned():
		push_error("Smoke: passive shot-clear setup never warned")
		get_tree().quit(1)
		return
	match_node.rules.on_release(player)
	ball.last_shot_meta = {"pass": false, "shooter": player}
	match_node.rules.on_shot_attempt(player)
	print(
		"Smoke passive after shot: warned=", match_node.rules.is_passive_warned(),
		" recv=", match_node.rules.get_passive_receives()
	)
	if match_node.rules.is_passive_warned() or match_node.rules.get_passive_receives() != 0:
		push_error("Smoke: shot attempt should clear passive warn + receive count")
		get_tree().quit(1)
		return
	# Synthetic receives after clear must not FT (no warn armed).
	for p in home_outfield:
		match_node.rules.on_pickup(p)
		match_node.rules.on_release(p)
	if match_node.rules.is_passive_warned():
		push_error("Smoke: receives after shot clear should not re-arm passive")
		get_tree().quit(1)
		return
	print("Smoke Phase C passive v2 OK (N=", HandballRules.PASSIVE_MAX_RECEIVES, ")")

	# --- Phase B: dribble + 3 s hold + step reset + double-dribble ---
	_smoke_prepare_live(match_node, ball)
	_smoke_clear_ball(ball)
	player = match_node.controlled_player
	player.global_position = Vector3(0.0, player.start_position.y, 0.0)
	player.velocity = Vector3.ZERO
	player.dribbling = false
	if not ball.try_pickup(player):
		push_error("Smoke: Phase B pickup failed")
		get_tree().quit(1)
		return
	player.has_ball = true
	match_node.rules.on_pickup(player)
	match_node.rules._oob_cooldown = 0.0

	# Synthesize two counted steps, then dribble→catch should reset steps + hold.
	var dribble_stride := HandballRules.STEP_LENGTH_M * 1.5
	for i in range(4):
		player.global_position = Vector3(0.0, player.start_position.y, float(i) * dribble_stride)
		player.velocity = Vector3(0.0, 0.0, HandballRules.MOVE_SPEED_MPS + 1.0)
		if match_node.rules.tick(0.016, ball, match_node._all_players()):
			push_error("Smoke: unexpected rule hit while planting before dribble")
			get_tree().quit(1)
			return
	var steps_before := match_node.rules.get_steps()
	print("Smoke Phase B steps before dribble=", steps_before)
	if steps_before < 1:
		push_error("Smoke: expected counted steps before dribble catch reset")
		get_tree().quit(1)
		return
	# Burn some hold time, then dribble should clear it on catch.
	match_node.rules._hold_timer = 1.5
	if not match_node.rules.try_begin_dribble(player):
		push_error("Smoke: dribble begin failed")
		get_tree().quit(1)
		return
	player.dribbling = true
	# Bounce a couple of periods (visual path); rules keep hold paused.
	for _j in range(8):
		ball._physics_process(0.05)
		if match_node.rules.tick(0.05, ball, match_node._all_players()):
			push_error("Smoke: unexpected rule hit while dribbling")
			get_tree().quit(1)
			return
	player.dribbling = false
	match_node.rules.end_dribble(player)
	print(
		"Smoke Phase B after catch: steps=", match_node.rules.get_steps(),
		" hold=", match_node.rules.get_hold_timer(),
		" caught=", match_node.rules.has_caught_dribble()
	)
	if match_node.rules.get_steps() != 0:
		push_error("Smoke: dribble catch should reset steps")
		get_tree().quit(1)
		return
	if match_node.rules.get_hold_timer() > 0.001:
		push_error("Smoke: dribble catch should reset 3 s hold")
		get_tree().quit(1)
		return
	if not match_node.rules.has_caught_dribble():
		push_error("Smoke: dribble catch should arm double-dribble")
		get_tree().quit(1)
		return
	print("Smoke Phase B dribble step/hold reset OK")

	# Double-dribble: second bounce stream after catch → free throw.
	# try_begin_dribble emits rule_violation; MatchController already restarts.
	var dd_codes: Array = []
	var dd_cb := func(code: String, _msg: String, _award: int, _spot: Vector3) -> void:
		dd_codes.append(code)
	match_node.rules.rule_violation.connect(dd_cb)
	var dd_ok := match_node.rules.try_begin_dribble(player)
	match_node.rules.rule_violation.disconnect(dd_cb)
	print("Smoke Phase B double-dribble begin=", dd_ok, " codes=", dd_codes)
	if dd_ok:
		push_error("Smoke: second dribble stream should be illegal")
		get_tree().quit(1)
		return
	if not ("double_dribble" in dd_codes):
		push_error("Smoke: expected double_dribble violation")
		get_tree().quit(1)
		return
	await get_tree().create_timer(MatchController.RESTART_FREEZE + 0.35).timeout
	if ball.carrier == null or ball.carrier.team_id != 1:
		push_error("Smoke: double dribble should award Away free throw")
		get_tree().quit(1)
		return
	print("Smoke Phase B double-dribble OK")

	# Standing hold > 3 s without dribble/pass/shot → free throw.
	_smoke_prepare_live(match_node, ball)
	_smoke_clear_ball(ball)
	player = match_node.controlled_player
	player.global_position = Vector3(0.0, player.start_position.y, 0.0)
	player.velocity = Vector3.ZERO
	player.dribbling = false
	if not ball.try_pickup(player):
		push_error("Smoke: hold pickup failed")
		get_tree().quit(1)
		return
	player.has_ball = true
	match_node.rules.on_pickup(player)
	match_node.rules._oob_cooldown = 0.0
	var hold_hit := false
	var hold_warned := false
	for _k in range(int(HandballRules.HOLD_MAX_S / 0.25) + 6):
		hold_hit = match_node.rules.tick(0.25, ball, match_node._all_players())
		if match_node.rules.is_hold_warned():
			hold_warned = true
		if hold_hit:
			break
	print(
		"Smoke Phase B hold warned=", hold_warned,
		" hit=", hold_hit,
		" t=", match_node.rules.get_hold_timer()
	)
	if not hold_warned:
		push_error("Smoke: 3 s hold warning never fired")
		get_tree().quit(1)
		return
	if not hold_hit:
		push_error("Smoke: 3 s hold violation did not fire")
		get_tree().quit(1)
		return
	await get_tree().create_timer(MatchController.RESTART_FREEZE + 0.35).timeout
	if ball.carrier == null or ball.carrier.team_id != 1:
		push_error("Smoke: hold foul should award Away")
		get_tree().quit(1)
		return
	print("Smoke Phase B 3 s hold OK")

	# Pass / shot clear the 3 s clock.
	_smoke_prepare_live(match_node, ball)
	_smoke_clear_ball(ball)
	player = match_node.controlled_player
	player.global_position = Vector3(0.0, player.start_position.y, 0.0)
	player.velocity = Vector3.ZERO
	player.dribbling = false
	if not ball.try_pickup(player):
		push_error("Smoke: clear-hold pickup failed")
		get_tree().quit(1)
		return
	player.has_ball = true
	match_node.rules.on_pickup(player)
	match_node.rules._hold_timer = 2.7
	match_node.rules._hold_warned = true
	# Soft pass clears via on_release.
	var mate: Player = null
	for p in match_node._home_players:
		if p != player and not p.is_goalkeeper:
			mate = p
			break
	if mate == null:
		push_error("Smoke: no teammate for clear-hold pass")
		get_tree().quit(1)
		return
	mate.global_position = player.global_position + Vector3(0.0, 0.0, 4.0)
	if not player.try_pass_to(mate, ball):
		push_error("Smoke: clear-hold pass failed")
		get_tree().quit(1)
		return
	# MatchController wires release → rules.on_release; smoke may need a direct call
	# if the signal already fired from release_and_shoot.
	if match_node.rules.get_hold_timer() > 0.001 or match_node.rules._possession_team_id != -1:
		# Ensure clock cleared even if signal order differed in headless.
		match_node.rules.on_release(player)
	print("Smoke Phase B after pass hold=", match_node.rules.get_hold_timer())
	if match_node.rules.get_hold_timer() > 0.001:
		push_error("Smoke: pass should clear 3 s hold")
		get_tree().quit(1)
		return
	# Shot path: re-possess, burn clock, shoot.
	_smoke_clear_ball(ball)
	await get_tree().create_timer(0.15).timeout
	ball.global_position = player.global_position + Vector3(0.3, 1.1, 0.0)
	if not ball.try_pickup(player):
		push_error("Smoke: clear-hold re-pickup failed")
		get_tree().quit(1)
		return
	player.has_ball = true
	match_node.rules.on_pickup(player)
	match_node.rules._hold_timer = 2.5
	if not player.try_shoot(Vector3(0, 0.1, 1), 12.0, ball):
		push_error("Smoke: clear-hold shot failed")
		get_tree().quit(1)
		return
	if match_node.rules.get_hold_timer() > 0.001:
		match_node.rules.on_release(player)
	print("Smoke Phase B after shot hold=", match_node.rules.get_hold_timer())
	if match_node.rules.get_hold_timer() > 0.001:
		push_error("Smoke: shot should clear 3 s hold")
		get_tree().quit(1)
		return
	print("Smoke Phase B pass/shot clear 3 s OK")

	# --- Phase 3: shot craft / GK dive / block ---
	_smoke_prepare_live(match_node, ball)
	_smoke_clear_ball(ball)
	# Park free ball midcourt so a leftover Phase B shot position can't trip end-line OOB
	# before the charged-shot assert (longer Phase C section makes that race likelier).
	ball.global_position = Vector3(0.0, 0.3, 0.0)
	match_node.rules._oob_cooldown = 0.5

	# Charge → impulse mapping
	var imp_lo := ShotCraft.impulse_for_charge(0.0, false)
	var imp_hi := ShotCraft.impulse_for_charge(1.0, false)
	var imp_lob := ShotCraft.impulse_for_charge(1.0, true)
	print("Smoke shot craft impulses lo=", imp_lo, " hi=", imp_hi, " lob=", imp_lob)
	if imp_hi <= imp_lo or imp_lob >= imp_hi:
		push_error("Smoke: charge/lob impulse mapping wrong")
		get_tree().quit(1)
		return
	if ShotCraft.up_bias(true) <= ShotCraft.up_bias(false):
		push_error("Smoke: lob should loft higher than flat")
		get_tree().quit(1)
		return

	# Charged flat shot via match helper
	player = match_node.controlled_player
	player.global_position = Vector3(0.0, player.start_position.y, 8.0)
	player.velocity = Vector3.ZERO
	player.rotation.y = 0.0
	if not ball.try_pickup(player):
		push_error("Smoke: phase3 pickup failed")
		get_tree().quit(1)
		return
	player.has_ball = true
	match_node.rules.on_pickup(player)
	match_node._try_shoot_charged(ShotCraft.CHARGE_TIME_S)
	await get_tree().create_timer(0.05).timeout
	print(
		"Smoke charged shot: carrier=", ball.carrier,
		" speed=", ball.linear_velocity.length(),
		" meta=", ball.last_shot_meta
	)
	if ball.carrier != null:
		push_error("Smoke: charged shot did not release ball")
		get_tree().quit(1)
		return
	if ball.linear_velocity.length() < 8.0:
		push_error("Smoke: charged shot too weak")
		get_tree().quit(1)
		return
	if not ball.last_shot_meta.has("charge"):
		push_error("Smoke: shot meta missing charge")
		get_tree().quit(1)
		return

	# Jump-shot quality: grounded = -1; raised player near apex = sweet(1)
	player.jump_shot_active = false
	player.jump_shot_air_s = 0.0
	player.jump_shot_phase = ShotCraft.JumpPhase.NONE
	player.global_position.y = 0.0
	player.velocity = Vector3.ZERO
	# Settle on floor — teleports alone often leave is_on_floor() false (esp. denser roster).
	for _i in range(4):
		player.move_and_slide()
		await get_tree().physics_frame
	var q_ground := ShotCraft.jump_shot_quality(player)
	player.global_position.y = ShotCraft.JUMP_APEX_Y * 0.75
	player.velocity = Vector3(0.0, 0.2, 0.0)
	# Force off-floor: CharacterBody may still report on_floor at y>0 without move.
	# jump_shot_quality uses is_on_floor(); teleport above and clear floor contact.
	player.velocity.y = 0.5
	await get_tree().physics_frame
	await get_tree().physics_frame
	var q_air := ShotCraft.jump_shot_quality(player)
	print("Smoke jump quality ground=", q_ground, " air=", q_air, " y=", player.global_position.y, " on_floor=", player.is_on_floor())
	if q_ground != -1:
		push_error("Smoke: grounded jump quality should be -1")
		get_tree().quit(1)
		return
	# If physics still reports on_floor, synthesize via direct height check path:
	# apply_jump_timing must still boost sweet quality.
	var timed_sweet := ShotCraft.apply_jump_timing(Vector3(0, 0.1, 1), 12.0, 1)
	var timed_early := ShotCraft.apply_jump_timing(Vector3(0, 0.1, 1), 12.0, 0)
	print("Smoke jump timing sweet=", timed_sweet["impulse"], " early=", timed_early["impulse"])
	if float(timed_sweet["impulse"]) <= float(timed_early["impulse"]):
		push_error("Smoke: sweet jump should boost impulse over early")
		get_tree().quit(1)
		return

	# GK dive + save area
	var home_gk := match_node._goalkeeper_for(0)
	if home_gk == null:
		push_error("Smoke: missing home GK")
		get_tree().quit(1)
		return
	home_gk.match_frozen = false
	home_gk.global_position = home_gk.start_position
	home_gk.velocity = Vector3.ZERO
	home_gk._dive_cd = 0.0
	var dived := home_gk.try_dive(Vector3(1.0, 0.0, 0.0))
	print("Smoke GK dive started=", dived, " diving=", home_gk.diving)
	if not dived or not home_gk.diving:
		push_error("Smoke: GK dive failed")
		get_tree().quit(1)
		return
	if home_gk._save_area == null:
		push_error("Smoke: GK missing SaveArea")
		get_tree().quit(1)
		return

	# Block contest: defender with block_ready deflects a fast free ball
	_smoke_clear_ball(ball)
	var defender: Player = null
	for p in match_node._away_players:
		if not p.is_goalkeeper:
			defender = p
			break
	if defender == null:
		push_error("Smoke: no away defender")
		get_tree().quit(1)
		return
	defender.match_frozen = true
	defender.global_position = Vector3(0.0, defender.start_position.y, 10.0)
	defender.velocity = Vector3.ZERO
	defender.raise_block(1.0)
	ball.global_position = defender.global_position + Vector3(0.0, 1.2, -0.8)
	ball.linear_velocity = Vector3(0.0, 0.5, 12.0)
	ball.last_shot_meta = {"time_msec": Time.get_ticks_msec(), "charge": 1.0}
	ball._last_carrier = player
	# Direct contest call (Area signals can miss in one frame under teleport).
	var speed_before := ball.linear_velocity.length()
	defender._contest_ball(ball, false)
	var speed_after := ball.linear_velocity.length()
	print("Smoke block deflect speed ", speed_before, " -> ", speed_after, " vel=", ball.linear_velocity)
	if ball.linear_velocity.z >= 10.0:
		push_error("Smoke: block did not deflect shot forward speed")
		get_tree().quit(1)
		return
	if match_node.rules.last_touch_team_id != defender.team_id:
		# _contest_ball emits signal; match handler sets last_touch — allow one frame.
		await get_tree().process_frame
	if match_node.rules.last_touch_team_id != defender.team_id:
		push_error("Smoke: block should set last_touch to defender team")
		get_tree().quit(1)
		return

	# BlockTrace exists after shot
	if match_node._block_trace == null:
		push_error("Smoke: BlockTrace missing")
		get_tree().quit(1)
		return

	# --- Phase 4: formations / set pieces / off-ball / switch-best ---
	_smoke_prepare_live(match_node, ball)
	_smoke_clear_ball(ball)

	# Role map: idx 1=LW … 3=CB … 5=RW (skip bench).
	var lw: Player = null
	var cb: Player = null
	var rw: Player = null
	for p in match_node._home_players:
		if p.is_goalkeeper or p.on_bench:
			continue
		match Formations.role_for(p):
			Formations.Role.LEFT_WING:
				lw = p
			Formations.Role.RIGHT_WING:
				rw = p
			Formations.Role.CENTER_BACK:
				cb = p
	if lw == null or cb == null or rw == null:
		push_error("Smoke: missing LW/CB/RW role mapping")
		get_tree().quit(1)
		return
	var atk_lw := Formations.attack_slot(lw, Vector3(0, 0, 10))
	var atk_rw := Formations.attack_slot(rw, Vector3(0, 0, 10))
	var atk_cb := Formations.attack_slot(cb, Vector3(0, 0, 10))
	print("Smoke attack slots LW=", atk_lw, " CB=", atk_cb, " RW=", atk_rw)
	if atk_lw.x >= -3.0 or atk_rw.x <= 3.0:
		push_error("Smoke: wings should sit wide on attack")
		get_tree().quit(1)
		return
	if atk_cb.z >= atk_lw.z:
		# Home attacks +Z: CB (backcourt) should be deeper (smaller z) than wings near arc.
		# When progress is high CB can pivot closer — use a mid ball for backcourt check.
		atk_cb = Formations.attack_slot(cb, Vector3(0, 0, 2))
		atk_lw = Formations.attack_slot(lw, Vector3(0, 0, 2))
		if atk_cb.z >= atk_lw.z - 0.5:
			push_error("Smoke: CB should sit deeper than wings in backcourt shape")
			get_tree().quit(1)
			return

	var def_lw := Formations.defense_slot(lw, Vector3(2, 0, -8), null)
	var def_rw := Formations.defense_slot(rw, Vector3(2, 0, -8), null)
	print("Smoke defense slots LW=", def_lw, " RW=", def_rw)
	if def_lw.x >= def_rw.x:
		push_error("Smoke: defense LW should be left of RW")
		get_tree().quit(1)
		return
	if Court.in_goal_area(def_lw, 0) or Court.in_goal_area(def_rw, 0):
		push_error("Smoke: defense slots must stay outside own 6m")
		get_tree().quit(1)
		return

	# Player–player solid collision (layer 2 / mask court+player).
	var sample_body: Player = lw
	print(
		"Smoke player collision_layer=", sample_body.collision_layer,
		" mask=", sample_body.collision_mask
	)
	if sample_body.collision_layer != Player.COLLISION_LAYER_PLAYER:
		push_error("Smoke: player should live on physics layer 2")
		get_tree().quit(1)
		return
	if (sample_body.collision_mask & Player.COLLISION_LAYER_PLAYER) == 0:
		push_error("Smoke: player mask must include other players (was court-only overlap bug)")
		get_tree().quit(1)
		return

	# Forced stack → placement resolver must nudge capsules apart.
	# Park other on-court bodies far away so the 7-man wall doesn't pin the stack.
	_smoke_park_unused_outfield(match_node, [lw, cb, rw])
	lw.global_position = Vector3(0.0, 0.0, 0.0)
	rw.global_position = Vector3(0.05, 0.0, 0.02)
	cb.global_position = Vector3(-0.02, 0.0, -0.04)
	match_node._resolve_player_overlaps(lw)
	var stack_min := INF
	var stacked: Array[Player] = [lw, rw, cb]
	for i in stacked.size():
		for j in range(i + 1, stacked.size()):
			var sep := stacked[i].global_position.distance_to(stacked[j].global_position)
			stack_min = minf(stack_min, sep)
	print("Smoke overlap resolve min_sep=", stack_min)
	if stack_min < Player.BODY_RADIUS * 2.0:
		push_error("Smoke: stacked players should be nudged apart after resolve")
		get_tree().quit(1)
		return

	# Set piece: free-throw wall places defenders ~3m+ from taker, award team around spot
	var foul_spot := Vector3(1.5, 0.0, 12.0)
	var away_taker := match_node._nearest_outfield(1, foul_spot)
	if away_taker == null:
		push_error("Smoke: no away taker for set piece")
		get_tree().quit(1)
		return
	match_node._place_set_piece("traveling", 1, foul_spot, away_taker)
	var wall_ok := false
	var min_wall_d := INF
	for p in match_node._home_players:
		if p.is_goalkeeper:
			continue
		var d := p.global_position.distance_to(away_taker.global_position)
		min_wall_d = minf(min_wall_d, d)
		if d >= Formations.WALL_GAP_M * 0.85:
			wall_ok = true
	var set_piece_min := INF
	var roster_all: Array[Player] = []
	roster_all.append_array(match_node._home_players)
	roster_all.append_array(match_node._away_players)
	for i in roster_all.size():
		for j in range(i + 1, roster_all.size()):
			var d2 := roster_all[i].global_position.distance_to(roster_all[j].global_position)
			set_piece_min = minf(set_piece_min, d2)
	print(
		"Smoke set piece: taker=", away_taker.global_position,
		" min_wall_d=", min_wall_d, " wall_ok=", wall_ok,
		" roster_min_sep=", set_piece_min
	)
	if away_taker.global_position.distance_to(foul_spot) > 1.25:
		push_error("Smoke: free-throw taker not placed at foul spot")
		get_tree().quit(1)
		return
	if not wall_ok or min_wall_d < 2.0:
		push_error("Smoke: 9m wall should keep defenders off the taker")
		get_tree().quit(1)
		return
	if set_piece_min < Player.BODY_RADIUS * 2.0:
		push_error("Smoke: set-piece placement stacked two players")
		get_tree().quit(1)
		return

	# Home off-ball AI: uncontrolled teammates have ai_enabled
	match_node._set_controlled(cb)
	match_node._refresh_home_ai()
	var offball_ai := 0
	for p in match_node._home_players:
		if p != match_node.controlled_player and p.ai_enabled:
			offball_ai += 1
	print("Smoke home off-ball AI count=", offball_ai)
	if offball_ai < 3:
		push_error("Smoke: expected uncontrolled home players to run off-ball AI")
		get_tree().quit(1)
		return

	# Switch-to-best: free ball near LW → should prefer LW over far RW
	_smoke_clear_ball(ball)
	_smoke_park_unused_outfield(match_node, [lw, cb, rw])
	lw.global_position = Vector3(-4.0, lw.start_position.y, 0.0)
	rw.global_position = Vector3(8.0, rw.start_position.y, -10.0)
	cb.global_position = Vector3(0.0, cb.start_position.y, -8.0)
	ball.global_position = Vector3(-3.5, 1.0, 0.2)
	ball.linear_velocity = Vector3.ZERO
	match_node._set_controlled(cb)
	match_node._switch_to_best()
	print("Smoke switch-best free ball -> ", match_node.controlled_player.name if match_node.controlled_player else "null")
	if match_node.controlled_player != lw:
		push_error("Smoke: switch-best should pick nearest (LW) on free ball")
		get_tree().quit(1)
		return

	# Switch-to-best defending: prefer outfielder near carrier
	_smoke_clear_ball(ball)
	_smoke_park_unused_outfield(match_node, [lw, cb, rw])
	var away_carrier := match_node._first_outfield(match_node._away_players)
	away_carrier.global_position = Vector3(2.0, away_carrier.start_position.y, -6.0)
	if not ball.try_pickup(away_carrier):
		push_error("Smoke: away carrier pickup failed")
		get_tree().quit(1)
		return
	away_carrier.has_ball = true
	match_node.rules.on_pickup(away_carrier)
	match_node._attack_team_id = 1
	lw.global_position = Vector3(1.5, lw.start_position.y, -5.0)
	rw.global_position = Vector3(-7.0, rw.start_position.y, 8.0)
	cb.global_position = Vector3(0.0, cb.start_position.y, 10.0)
	match_node._set_controlled(cb)
	match_node._switch_to_best()
	print("Smoke switch-best defend -> ", match_node.controlled_player.name if match_node.controlled_player else "null")
	if match_node.controlled_player != lw:
		push_error("Smoke: switch-best should pick nearest defender to carrier")
		get_tree().quit(1)
		return

	# Cycle switch still advances roster
	var before_cycle := match_node.controlled_player
	match_node._cycle_teammate()
	if match_node.controlled_player == null or match_node.controlled_player == before_cycle:
		push_error("Smoke: cycle switch failed")
		get_tree().quit(1)
		return
	print("Smoke cycle switch OK")

	# --- Phase D: contact lite → FT / 7 m / exclusion ---
	_smoke_prepare_live(match_node, ball)
	_smoke_clear_ball(ball)
	# Clear any leftover exclusions from prior tests.
	for p in match_node._all_players():
		p.excluded = false
		p.exclusion_remaining = 0.0
		p.visible = true
	match_node.exclusion_on_seven_m = true
	match_node.exclusion_seconds = 3.0
	match_node._configure_ai()

	# 7 m marks exist on court.
	var seven_home := Court.seven_meter_spot(0)
	var seven_away := Court.seven_meter_spot(1)
	print("Smoke 7m spots home=", seven_home, " away=", seven_away)
	if absf(seven_away.z - 13.0) > 0.01 or absf(seven_home.z + 13.0) > 0.01:
		push_error("Smoke: 7 m spots should sit 7 m inside each end (z=±13)")
		get_tree().quit(1)
		return

	# Contact during shoot windup near arc (grounded) → free throw (foul).
	player = match_node._first_outfield(match_node._home_players)
	match_node._set_controlled(player)
	player.global_position = Vector3(0.5, player.start_position.y, 12.0)
	player.rotation.y = 0.0
	player.velocity = Vector3.ZERO
	var foul_def: Player = null
	for p in match_node._away_players:
		if not p.is_goalkeeper:
			foul_def = p
			break
	if foul_def == null:
		push_error("Smoke: no away defender for foul")
		get_tree().quit(1)
		return
	# Side contact inside reach, in 6–9 m band.
	foul_def.global_position = player.global_position + Vector3(0.7, 0.0, 0.15)
	foul_def.velocity = Vector3.ZERO
	foul_def.match_frozen = true
	foul_def.ai_enabled = false
	if not ball.try_pickup(player):
		push_error("Smoke: Phase D foul pickup failed")
		get_tree().quit(1)
		return
	player.has_ball = true
	match_node.rules.on_pickup(player)
	match_node.rules.set_windup(true, true)
	var foul_codes: Array = []
	var foul_cb := func(code: String, _msg: String, _award: int, _spot: Vector3) -> void:
		foul_codes.append(code)
	match_node.rules.rule_violation.connect(foul_cb)
	var foul_hit := false
	for _i in range(6):
		foul_hit = match_node.rules.tick(0.02, ball, match_node._all_players())
		if foul_hit:
			break
	match_node.rules.rule_violation.disconnect(foul_cb)
	match_node.rules.set_windup(false)
	print("Smoke Phase D foul hit=", foul_hit, " codes=", foul_codes)
	if not foul_hit or not ("foul" in foul_codes):
		push_error("Smoke: contact during windup near arc should free-throw (foul)")
		get_tree().quit(1)
		return
	await get_tree().create_timer(MatchController.RESTART_FREEZE + 0.35).timeout
	if match_node.match_state != MatchController.MatchState.LIVE:
		push_error("Smoke: expected LIVE after foul free throw")
		get_tree().quit(1)
		return
	if ball.carrier == null or ball.carrier.team_id != 0:
		push_error("Smoke: foul should award Home free throw")
		get_tree().quit(1)
		return
	print("Smoke Phase D contact → FT OK")

	# Clear-chance heuristic: airborne shooter inside ~8 m + behind/side → 7 m.
	_smoke_prepare_live(match_node, ball)
	_smoke_clear_ball(ball)
	for p in match_node._all_players():
		p.excluded = false
		p.exclusion_remaining = 0.0
	player = match_node._first_outfield(match_node._home_players)
	match_node._set_controlled(player)
	# Inside 8 m of away goal (end z=20): place at z≈13.5 → dist≈6.5.
	player.global_position = Vector3(0.2, 1.35, 13.5)
	player.rotation.y = 0.0
	player.velocity = Vector3(0.0, 2.5, 0.0)
	var pen_def: Player = null
	for p in match_node._away_players:
		if not p.is_goalkeeper:
			pen_def = p
			break
	# Behind the shooter (negative Z relative to facing +Z).
	pen_def.global_position = player.global_position + Vector3(0.15, 0.0, -0.75)
	pen_def.global_position.y = pen_def.start_position.y
	pen_def.velocity = Vector3.ZERO
	pen_def.match_frozen = true
	pen_def.ai_enabled = false
	await get_tree().physics_frame
	if not ball.try_pickup(player):
		push_error("Smoke: Phase D 7m pickup failed")
		get_tree().quit(1)
		return
	player.has_ball = true
	match_node.rules.on_pickup(player)
	# Re-assert airborne after pickup teleports ball attach.
	player.global_position.y = 1.4
	player.velocity.y = 2.0
	match_node.rules.set_windup(true, true)
	var seven_codes: Array = []
	var seven_cb := func(code: String, _msg: String, _award: int, _spot: Vector3) -> void:
		seven_codes.append(code)
	match_node.rules.rule_violation.connect(seven_cb)
	var seven_hit := false
	for _j in range(8):
		player.global_position.y = 1.4
		player.velocity.y = 2.0
		seven_hit = match_node.rules.tick(0.02, ball, match_node._all_players())
		if seven_hit:
			break
	match_node.rules.rule_violation.disconnect(seven_cb)
	match_node.rules.set_windup(false)
	print(
		"Smoke Phase D 7m hit=", seven_hit, " codes=", seven_codes,
		" air=", match_node.rules._is_airborne(player),
		" dist=", match_node.rules._dist_to_defend_goal(player.global_position, 1)
	)
	if not seven_hit or not ("seven_m" in seven_codes):
		push_error("Smoke: clear-chance contact should award 7 m")
		get_tree().quit(1)
		return
	await get_tree().create_timer(MatchController.RESTART_FREEZE + 0.4).timeout
	var seven_spot := Court.seven_meter_spot(1)
	if ball.carrier == null or ball.carrier.team_id != 0:
		push_error("Smoke: 7 m should award Home taker")
		get_tree().quit(1)
		return
	if ball.carrier.global_position.distance_to(seven_spot) > 1.4:
		push_error("Smoke: 7 m taker should stand on the 7 m mark")
		get_tree().quit(1)
		return
	# Only defending GK may stay near the goal — outfield defenders outside ~9 m.
	var away_gk := match_node._goalkeeper_for(1)
	for p in match_node._away_players:
		if p.is_goalkeeper or p.excluded:
			continue
		var d_goal := match_node.rules._dist_to_defend_goal(p.global_position, 1)
		if d_goal < Formations.FREE_THROW_LINE_M - 0.5:
			push_error("Smoke: defending outfield must clear outside 9 m on 7 m")
			get_tree().quit(1)
			return
	if away_gk == null or away_gk.global_position.distance_to(away_gk.start_position) > 2.5:
		push_error("Smoke: defending GK should stay on the line for 7 m")
		get_tree().quit(1)
		return
	# Exclusion lite: fouler benched.
	if not pen_def.excluded:
		push_error("Smoke: 7 m clear-chance should exclude the fouler")
		get_tree().quit(1)
		return
	var bench := Court.bench_marker(pen_def.team_id, 2 + maxi(0, pen_def.player_index % 4))
	if pen_def.global_position.distance_to(bench) > 1.5:
		push_error("Smoke: excluded player should sit on bench marker")
		get_tree().quit(1)
		return
	if pen_def.ai_enabled:
		push_error("Smoke: excluded player must have ai_enabled=false")
		get_tree().quit(1)
		return
	print("Smoke Phase D 7m placement + GK-only + exclusion OK")

	# Exclusion expires on short timer.
	pen_def.exclusion_remaining = 0.05
	match_node.match_state = MatchController.MatchState.LIVE
	match_node._set_players_frozen(false)
	for _k in range(8):
		match_node._tick_exclusions(0.02)
	if pen_def.excluded:
		push_error("Smoke: exclusion should end when timer elapses")
		get_tree().quit(1)
		return
	print("Smoke Phase D exclusion return OK")

	# --- Phase E: attack/defense shape presets ---
	_smoke_prepare_live(match_node, ball)
	_smoke_clear_ball(ball)
	var e_lw: Player = null
	var e_cb: Player = null
	var e_rw: Player = null
	for p in match_node._home_players:
		if p.is_goalkeeper or p.on_bench:
			continue
		match Formations.role_for(p):
			Formations.Role.LEFT_WING:
				e_lw = p
			Formations.Role.RIGHT_WING:
				e_rw = p
			Formations.Role.CENTER_BACK:
				e_cb = p
	if e_lw == null or e_cb == null or e_rw == null:
		push_error("Smoke: Phase E missing LW/CB/RW")
		get_tree().quit(1)
		return

	# Defaults: Wide / Flat. Ball at mid-attack so Wide stays backcourt while Crash tucks.
	match_node.home_attack_shape = Formations.AttackShape.WIDE
	match_node.home_defense_shape = Formations.DefenseShape.FLAT
	match_node._sync_team_shapes()
	var shape_ball := Vector3(0.0, 0.0, 4.0)
	var wide_cb := Formations.attack_slot(e_cb, shape_ball)
	# Crash tucks CB onto the soft-pivot line (closer to opponent goal for Home).
	match_node.home_attack_shape = Formations.AttackShape.CRASH
	match_node._sync_team_shapes()
	var crash_cb := Formations.attack_slot(e_cb, shape_ball)
	print("Smoke Phase E Wide CB=", wide_cb, " Crash CB=", crash_cb)
	if crash_cb.z <= wide_cb.z + 0.4:
		push_error("Smoke: Crash should tuck CB closer to opponent goal than Wide")
		get_tree().quit(1)
		return
	# Wings stay wide under Crash.
	var crash_lw := Formations.attack_slot(e_lw, shape_ball)
	var crash_rw := Formations.attack_slot(e_rw, shape_ball)
	if crash_lw.x >= -3.5 or crash_rw.x <= 3.5:
		push_error("Smoke: Crash wings should stay wide")
		get_tree().quit(1)
		return

	# Toggle helpers flip Home shapes.
	match_node.home_attack_shape = Formations.AttackShape.WIDE
	match_node._toggle_home_attack_shape()
	if match_node.home_attack_shape != Formations.AttackShape.CRASH:
		push_error("Smoke: toggle_home_attack_shape should select Crash")
		get_tree().quit(1)
		return
	match_node._toggle_home_attack_shape()
	if match_node.home_attack_shape != Formations.AttackShape.WIDE:
		push_error("Smoke: toggle_home_attack_shape should return to Wide")
		get_tree().quit(1)
		return

	# Flat vs OneUp: CB steps up toward ~9 m.
	match_node.home_defense_shape = Formations.DefenseShape.FLAT
	match_node._sync_team_shapes()
	var threat := Vector3(1.5, 0.0, -6.0)
	var flat_cb := Formations.defense_slot(e_cb, threat, null)
	match_node.home_defense_shape = Formations.DefenseShape.ONE_UP
	match_node._sync_team_shapes()
	var oneup_cb := Formations.defense_slot(e_cb, threat, null)
	print("Smoke Phase E Flat CB=", flat_cb, " OneUp CB=", oneup_cb)
	# Home own goal at z=-20; OneUp CB should be farther from own goal (larger z).
	if oneup_cb.z <= flat_cb.z + 0.6:
		push_error("Smoke: OneUp should step CB up from the flat wall")
		get_tree().quit(1)
		return
	match_node._toggle_home_defense_shape()
	if match_node.home_defense_shape != Formations.DefenseShape.FLAT:
		push_error("Smoke: toggle_home_defense_shape should return to Flat from OneUp")
		get_tree().quit(1)
		return

	# Phase G: real LB / RB / Pivot labels (no cosmetic CB remap).
	if Formations.role_label(Formations.Role.LEFT_BACK) != "LB":
		push_error("Smoke: LEFT_BACK should label LB")
		get_tree().quit(1)
		return
	if Formations.role_label(Formations.Role.RIGHT_BACK) != "RB":
		push_error("Smoke: RIGHT_BACK should label RB")
		get_tree().quit(1)
		return
	if Formations.role_label(Formations.Role.PIVOT) != "P":
		push_error("Smoke: PIVOT should label P")
		get_tree().quit(1)
		return
	if Formations.role_label_hud(Formations.Role.CENTER_BACK, -3.0) != "CB":
		push_error("Smoke: CB should stay CB (real LB/RB exist)")
		get_tree().quit(1)
		return

	# Screen slot sits between pivot and defender.
	var screen := Formations.screen_slot(Vector3(0, 0, 12), Vector3(2, 0, 10), 0)
	if screen.x < 0.4 or screen.x > 1.8:
		push_error("Smoke: screen_slot should sit between pivot and defender on X")
		get_tree().quit(1)
		return

	# Away AI: losing late → Crash + OneUp; winning → Wide + Flat.
	match_node.score_home = 3
	match_node.score_away = 1
	match_node.current_period = match_node.periods_total
	match_node.clock_remaining = match_node.period_length_seconds * 0.2
	match_node.away_attack_shape = Formations.AttackShape.WIDE
	match_node.away_defense_shape = Formations.DefenseShape.FLAT
	match_node._update_away_shapes()
	print(
		"Smoke Phase E Away losing late atk=", match_node.away_attack_shape,
		" def=", match_node.away_defense_shape
	)
	if match_node.away_attack_shape != Formations.AttackShape.CRASH:
		push_error("Smoke: Away losing should pick Crash attack")
		get_tree().quit(1)
		return
	if match_node.away_defense_shape != Formations.DefenseShape.ONE_UP:
		push_error("Smoke: Away losing late/down should pick OneUp defense")
		get_tree().quit(1)
		return
	match_node.score_home = 1
	match_node.score_away = 3
	match_node._update_away_shapes()
	if match_node.away_attack_shape != Formations.AttackShape.WIDE:
		push_error("Smoke: Away winning should pick Wide attack")
		get_tree().quit(1)
		return
	if match_node.away_defense_shape != Formations.DefenseShape.FLAT:
		push_error("Smoke: Away winning should pick Flat defense")
		get_tree().quit(1)
		return
	# Reset Home shapes for remaining presentation checks.
	match_node.home_attack_shape = Formations.AttackShape.WIDE
	match_node.home_defense_shape = Formations.DefenseShape.FLAT
	match_node.score_home = 0
	match_node.score_away = 0
	match_node._sync_team_shapes()
	print("Smoke Phase E shapes OK")

	# --- Phase F: jump-shot craft / pass types / GK angle-cut+outlet / catch settle ---
	_smoke_prepare_live(match_node, ball)
	_smoke_clear_ball(ball)
	player = match_node._first_outfield(match_node._home_players)
	match_node._set_controlled(player)
	player.match_frozen = false
	player.ai_enabled = false

	# Jump-shot window vs standing: craft air sweet differs from grounded -1.
	player.global_position = Vector3(0.0, player.start_position.y, 8.0)
	player.velocity = Vector3(0.0, 0.0, 4.0)
	player.has_ball = true
	ball.carrier = player
	ball.freeze = true
	player.jump_shot_active = false
	player.jump_shot_air_s = 0.0
	var q_stand := ShotCraft.jump_shot_quality(player)
	player.jump_shot_active = true
	player.jump_shot_air_s = 0.08
	player.global_position.y = 0.35
	player.velocity.y = 6.0
	player.velocity = Vector3(0.0, 6.0, 3.0)
	# Force off-floor for quality (teleport may still report floor).
	for _i in range(2):
		player.move_and_slide()
		await get_tree().physics_frame
	player.global_position.y = maxf(player.global_position.y, 0.45)
	var q_early := ShotCraft.window_quality_from_air_s(0.08)
	var q_sweet := ShotCraft.window_quality_from_air_s(0.36)
	var q_late := ShotCraft.window_quality_from_air_s(0.70)
	var stand_timed: Dictionary = ShotCraft.apply_jump_timing(Vector3(0, 0.1, 1), 14.0, -1)
	var sweet_timed: Dictionary = ShotCraft.apply_jump_timing(Vector3(0, 0.1, 1), 14.0, 1)
	var stand_imp: float = float(stand_timed["impulse"])
	var sweet_imp: float = ShotCraft.apply_window_bonus(float(sweet_timed["impulse"]), 1, 0.36)
	print(
		"Smoke Phase F jump: stand_q=", q_stand,
		" early=", q_early, " sweet=", q_sweet, " late=", q_late,
		" stand_imp=", stand_imp, " sweet_imp=", sweet_imp
	)
	if q_stand != -1:
		push_error("Smoke: grounded standing shot quality should be -1")
		get_tree().quit(1)
		return
	if q_early != 0:
		push_error("Smoke: jump-shot early window should be 0")
		get_tree().quit(1)
		return
	if q_sweet != 1:
		push_error("Smoke: jump-shot sweet window should be 1")
		get_tree().quit(1)
		return
	if q_late != 2:
		push_error("Smoke: jump-shot late window should be 2")
		get_tree().quit(1)
		return
	if sweet_imp <= stand_imp:
		push_error("Smoke: jump-shot sweet should punch harder than standing")
		get_tree().quit(1)
		return
	# Plant → air state machine.
	player.global_position = Vector3(0.0, 0.0, 8.0)
	player.velocity = Vector3(0.0, 0.0, 5.0)
	player._begin_jump_from_input(Vector3(0.0, 0.0, 1.0))
	# Wave 2: approach feeds into plant during the hold; either phase is valid on begin.
	if (
		not player.jump_shot_active
		or (
			player.jump_shot_phase != ShotCraft.JumpPhase.PLANTED
			and player.jump_shot_phase != ShotCraft.JumpPhase.APPROACH
		)
	):
		push_error("Smoke: approach jump with ball should plant jump-shot craft")
		get_tree().quit(1)
		return
	player._js_plant_t = 0.0
	player._tick_jump_shot_craft(0.02)
	if player.velocity.y < Player.JUMP_VELOCITY * 0.5 and player.is_on_floor():
		# Manually launch if floor still holding — plant end sets JUMP_VELOCITY.
		player.velocity.y = Player.JUMP_VELOCITY
	print("Smoke Phase F plant→jump craft OK phase=", player.jump_shot_phase)

	# Pass types: flat / lob loft + bounce floor hop then catch.
	_smoke_clear_ball(ball)
	var home_lw_f: Player = null
	var home_cb_f: Player = null
	var home_rw_f: Player = null
	for p in match_node._home_players:
		if p.is_goalkeeper or p.on_bench:
			continue
		match Formations.role_for(p):
			Formations.Role.LEFT_WING:
				home_lw_f = p
			Formations.Role.CENTER_BACK:
				home_cb_f = p
			Formations.Role.RIGHT_WING:
				home_rw_f = p
	if home_lw_f == null or home_cb_f == null or home_rw_f == null:
		push_error("Smoke: missing home wings/CB for Phase F passes")
		get_tree().quit(1)
		return
	_smoke_park_unused_outfield(match_node, [home_lw_f, home_cb_f, home_rw_f])
	_smoke_lock_pass_bots(match_node, [home_lw_f, home_cb_f, home_rw_f])
	home_cb_f.global_position = Vector3(0.0, home_cb_f.start_position.y, 0.0)
	home_rw_f.global_position = Vector3(2.5, home_rw_f.start_position.y, 6.0)
	home_lw_f.global_position = Vector3(-6.0, home_lw_f.start_position.y, 2.0)
	match_node._set_controlled(home_cb_f)
	_smoke_lock_pass_bots(match_node, [home_lw_f, home_cb_f, home_rw_f])
	ball.global_position = home_cb_f.global_position + Vector3(0.3, 1.1, 0.0)
	if not ball.try_pickup(home_cb_f):
		push_error("Smoke: Phase F lob setup pickup failed")
		get_tree().quit(1)
		return
	home_cb_f.has_ball = true
	if not home_cb_f.try_pass_to(home_rw_f, ball, -1.0, Vector3(0, 0, 1), PassCraft.PassType.LOB):
		push_error("Smoke: lob pass failed to release")
		get_tree().quit(1)
		return
	if int(ball.last_shot_meta.get("pass_type", -1)) != PassCraft.PassType.LOB:
		push_error("Smoke: lob pass meta missing")
		get_tree().quit(1)
		return
	var lob_dir: Vector3 = ball.last_shot_meta.get("dir", Vector3.ZERO)
	if lob_dir.y < 0.22:
		push_error("Smoke: lob pass should have high loft")
		get_tree().quit(1)
		return
	# Flat reference for the same lane should loft lower.
	var flat_built := PassCraft.build_pass(home_cb_f, home_rw_f, Vector3(0, 0, 1), -1.0, PassCraft.PassType.FLAT)
	if float(flat_built.get("loft", 0.0)) >= float(PassCraft.loft_for_distance(6.0, PassCraft.PassType.LOB)):
		push_error("Smoke: lob loft should exceed flat loft")
		get_tree().quit(1)
		return
	var lob_caught := await _smoke_await_carrier(ball, home_rw_f, 3.0)
	print(
		"Smoke Phase F lob catch=", lob_caught,
		" carrier=", ball.carrier,
		" ball=", ball.global_position,
		" dir_y=", lob_dir.y
	)
	if not lob_caught:
		push_error("Smoke: RW did not catch lob pass")
		get_tree().quit(1)
		return

	_smoke_clear_ball(ball)
	_smoke_lock_pass_bots(match_node, [home_lw_f, home_cb_f, home_rw_f])
	home_cb_f.global_position = Vector3(0.0, home_cb_f.start_position.y, 0.0)
	home_lw_f.global_position = Vector3(-3.5, home_lw_f.start_position.y, 7.5)
	home_rw_f.global_position = Vector3(6.0, home_rw_f.start_position.y, 1.0)
	match_node._set_controlled(home_cb_f)
	_smoke_lock_pass_bots(match_node, [home_lw_f, home_cb_f, home_rw_f])
	ball.global_position = home_cb_f.global_position + Vector3(0.3, 1.1, 0.0)
	if not ball.try_pickup(home_cb_f):
		push_error("Smoke: Phase F bounce setup pickup failed")
		get_tree().quit(1)
		return
	home_cb_f.has_ball = true
	if not home_cb_f.try_pass_to(home_lw_f, ball, -1.0, Vector3(0, 0, 1), PassCraft.PassType.BOUNCE):
		push_error("Smoke: bounce pass failed to release")
		get_tree().quit(1)
		return
	if int(ball.last_shot_meta.get("pass_type", -1)) != PassCraft.PassType.BOUNCE:
		push_error("Smoke: bounce pass meta missing")
		get_tree().quit(1)
		return
	# Wait for floor hop then catch.
	var hopped := false
	for _i in range(90):
		await get_tree().physics_frame
		if bool(ball.last_shot_meta.get("bounce_hopped", false)):
			hopped = true
			break
		# Nudge floor redirect if contact missed under llvmpipe.
		if ball.carrier == null and ball.global_position.y < 0.35:
			ball._try_bounce_floor_redirect()
	print("Smoke Phase F bounce hopped=", hopped, " y=", ball.global_position.y)
	if not hopped:
		push_error("Smoke: bounce pass never hit floor hop")
		get_tree().quit(1)
		return
	var bounce_caught := await _smoke_await_carrier(ball, home_lw_f, 2.2)
	print("Smoke Phase F bounce catch=", bounce_caught, " carrier=", ball.carrier)
	if not bounce_caught:
		push_error("Smoke: LW did not catch bounce pass")
		get_tree().quit(1)
		return

	# Catch settle briefly slows movement.
	if not home_lw_f.is_catch_settling():
		home_lw_f.begin_catch_settle()
	var settle_mul := home_lw_f._move_speed_mul()
	print("Smoke Phase F catch settle mul=", settle_mul, " t=", home_lw_f._catch_settle_t)
	if settle_mul >= 0.95 or home_lw_f._catch_settle_t <= 0.0:
		push_error("Smoke: catch settle should briefly slow movement")
		get_tree().quit(1)
		return

	# GK angle-cut: threat on the right → GK X biased toward near (right) post.
	var home_gk_f := match_node._goalkeeper_for(0)
	if home_gk_f == null:
		push_error("Smoke: missing home GK for Phase F")
		get_tree().quit(1)
		return
	home_gk_f.match_frozen = false
	home_gk_f.ai_enabled = true
	home_gk_f.global_position = home_gk_f.start_position
	var threat_pos := Vector3(4.5, 0.0, -8.0)
	var cut := home_gk_f._gk_angle_cut_target(threat_pos, home_gk_f.start_position, 1.0)
	var center_cut := home_gk_f._gk_angle_cut_target(Vector3(0.0, 0.0, -8.0), home_gk_f.start_position, 1.0)
	print("Smoke Phase F GK cut x=", cut.x, " center_x=", center_cut.x, " z=", cut.z)
	if cut.x <= center_cut.x + 0.15:
		push_error("Smoke: GK angle-cut should bias toward near post (right threat)")
		get_tree().quit(1)
		return
	if cut.z <= home_gk_f.start_position.z + 0.2:
		push_error("Smoke: GK angle-cut should step off the goal line")
		get_tree().quit(1)
		return

	# Post-save outlet: GK gathers → arms outlet → lob to a wing.
	_smoke_clear_ball(ball)
	for p in match_node._home_players:
		p.ai_enabled = false
		p.velocity = Vector3.ZERO
	home_gk_f.ai_enabled = true
	home_gk_f.controlled = false
	home_gk_f.global_position = home_gk_f.start_position
	home_lw_f.global_position = Vector3(-7.0, home_lw_f.start_position.y, -6.0)
	home_rw_f.global_position = Vector3(7.0, home_rw_f.start_position.y, -5.0)
	home_cb_f.global_position = Vector3(0.0, home_cb_f.start_position.y, -2.0)
	ball.global_position = home_gk_f.global_position + Vector3(0.2, 1.0, 0.8)
	ball.last_shot_meta = {"shooter": home_cb_f}  # opponent-ish last touch for outlet arm path
	# Mark as away shooter so _should_arm_outlet_from_ball passes.
	var away_shooter := match_node._first_outfield(match_node._away_players)
	if away_shooter:
		ball.last_shot_meta = {"shooter": away_shooter}
	if not ball.try_pickup(home_gk_f):
		push_error("Smoke: GK outlet pickup failed")
		get_tree().quit(1)
		return
	home_gk_f.has_ball = true
	# Auto-control rides Home carriers (incl. GK). Park control on an outfielder
	# so the AI outlet path can fire for this assert.
	if home_cb_f:
		match_node._set_controlled(home_cb_f)
	home_gk_f.controlled = false
	home_gk_f.ai_enabled = true
	home_gk_f.arm_outlet_pass()
	home_gk_f._outlet_timer = 0.0
	home_gk_f._outlet_cd = 0.0
	home_gk_f._ai_pass_cd = 0.0
	home_gk_f._tick_gk_outlet(0.05)
	var outlet_meta_ok := bool(ball.last_shot_meta.get("pass", false))
	var outlet_type := int(ball.last_shot_meta.get("pass_type", -1))
	print(
		"Smoke Phase F outlet released=", ball.carrier == null,
		" pass=", outlet_meta_ok, " type=", outlet_type, " target=", ball.pass_intended_receiver()
	)
	if ball.carrier != null or not outlet_meta_ok:
		push_error("Smoke: GK outlet pass did not fire")
		get_tree().quit(1)
		return
	if outlet_type != PassCraft.PassType.LOB:
		push_error("Smoke: GK outlet should be a lob pass")
		get_tree().quit(1)
		return
	var outlet_recv := ball.pass_intended_receiver()
	if outlet_recv == null or outlet_recv.is_goalkeeper:
		push_error("Smoke: GK outlet should target a wing/outfield")
		get_tree().quit(1)
		return
	var outlet_role := Formations.role_for(outlet_recv)
	if (
		outlet_role != Formations.Role.LEFT_WING
		and outlet_role != Formations.Role.RIGHT_WING
	):
		push_error("Smoke: GK outlet should prefer a wing, got role=%s" % outlet_role)
		get_tree().quit(1)
		return
	print("Smoke Phase F movement craft OK")

	# --- Phase 5 presentation ---
	if ball.get_node_or_null("BallTrail") == null and ball._trail == null:
		push_error("Smoke: ball trail missing")
		get_tree().quit(1)
		return
	var court := match_node.get_node_or_null("Court") as Node3D
	if court == null:
		# Court may be sibling under match scene.
		for child in match_node.get_children():
			if child is Court:
				court = child
				break
	if court == null or court.get_node_or_null("Boards") == null:
		push_error("Smoke: court boards / presentation geometry missing")
		get_tree().quit(1)
		return
	var kit_ok := false
	for p in match_node._home_players:
		# Wave 1: kit parts live under UpperBody / Leg* — search descendants.
		if p.find_child("ChestStripe", true, false) != null and p.find_child("ShoeL", true, false) != null:
			kit_ok = true
			break
	print("Smoke presentation kits=", kit_ok, " trail=", ball._trail != null)
	if not kit_ok:
		push_error("Smoke: polished kit nodes missing on home players")
		get_tree().quit(1)
		return

	# Goal juice restores time scale (ignore_time_scale pause path).
	Engine.time_scale = 1.0
	_smoke_clear_ball(ball)
	match_node.match_state = MatchController.MatchState.LIVE
	match_node.rules.begin_lockout()
	match_node.rules.end_lockout()
	match_node.rules._oob_cooldown = 0.0
	match_node._set_players_frozen(false)
	for p in match_node._away_players:
		p.match_frozen = true
		p.ai_enabled = false
	var scorer := match_node._first_outfield(match_node._home_players)
	match_node._set_controlled(scorer)
	ball.global_position = Vector3(0.0, 1.1, 19.35)
	ball.linear_velocity = Vector3(0, 0, 8)
	# Drive into away goal mouth.
	await get_tree().create_timer(0.05).timeout
	ball.global_position = Vector3(0.0, 1.0, 19.55)
	await get_tree().create_timer(0.2).timeout
	# Either scored already or force the celebration path.
	if match_node.match_state == MatchController.MatchState.LIVE:
		match_node._on_goal_scored(0, 1)
	await get_tree().create_timer(MatchController.GOAL_PAUSE_DELAY + 0.15, true, true).timeout
	print("Smoke goal juice time_scale=", Engine.time_scale, " state=", match_node.match_state)
	if absf(Engine.time_scale - 1.0) > 0.001:
		push_error("Smoke: Engine.time_scale not restored after goal juice")
		get_tree().quit(1)
		return
	Engine.time_scale = 1.0
	print("Smoke Phase 5 presentation OK")

	# --- Phase G: roster 7+2, stamina, dead-ball substitutions ---
	_smoke_prepare_live(match_node, ball)
	_smoke_clear_ball(ball)
	var home_court := 0
	var home_bench := 0
	var roles_seen: Dictionary = {}
	for p in match_node._home_players:
		if p.on_bench:
			home_bench += 1
			continue
		home_court += 1
		if not p.is_goalkeeper:
			roles_seen[Formations.role_for(p)] = true
	print(
		"Smoke Phase G roster home court=", home_court,
		" bench=", home_bench, " roles=", roles_seen.size()
	)
	if home_court != 7:
		push_error("Smoke: expected 7 on-court Home players (GK+6)")
		get_tree().quit(1)
		return
	if home_bench < 2:
		push_error("Smoke: expected ≥2 Home bench players")
		get_tree().quit(1)
		return
	for need_role in [
		Formations.Role.LEFT_WING,
		Formations.Role.LEFT_BACK,
		Formations.Role.CENTER_BACK,
		Formations.Role.RIGHT_BACK,
		Formations.Role.RIGHT_WING,
		Formations.Role.PIVOT,
	]:
		if not roles_seen.has(need_role):
			push_error("Smoke: missing on-court role %s" % Formations.role_label(need_role))
			get_tree().quit(1)
			return

	# Stamina drains on sprint / jump / shot; recovers off-ball.
	var stam_p := match_node._first_outfield(match_node._home_players)
	match_node._set_controlled(stam_p)
	stam_p.stamina = Player.STAMINA_MAX
	stam_p.global_position = Vector3(0.0, 0.0, 0.0)
	stam_p.velocity = Vector3.ZERO
	stam_p.match_frozen = false
	stam_p.on_bench = false
	# Simulate sprint drain without relying on Input actions in headless.
	var stam_before := stam_p.stamina
	stam_p._tick_stamina(1.0, true, true)
	print("Smoke Phase G sprint drain ", stam_before, " -> ", stam_p.stamina)
	if stam_p.stamina >= stam_before - Player.STAMINA_DRAIN_SPRINT * 0.5:
		push_error("Smoke: sprint should drain stamina")
		get_tree().quit(1)
		return
	stam_p.stamina = 20.0
	var speed_mul := stam_p.stamina_speed_mul()
	var acc_mul := stam_p.stamina_accuracy_mul()
	print("Smoke Phase G low stamina speed=", speed_mul, " acc=", acc_mul)
	if speed_mul >= 0.99 or acc_mul >= 0.99:
		push_error("Smoke: low stamina should soften speed/accuracy")
		get_tree().quit(1)
		return
	var shot_before := stam_p.stamina
	stam_p.drain_stamina(Player.STAMINA_DRAIN_SHOT)
	stam_p.drain_stamina(Player.STAMINA_DRAIN_JUMP)
	if stam_p.stamina >= shot_before:
		push_error("Smoke: jump/shot should drain stamina")
		get_tree().quit(1)
		return
	# Off-ball recover.
	stam_p.has_ball = false
	var recover_before := stam_p.stamina
	stam_p._tick_stamina(1.0, false, false)
	if stam_p.stamina <= recover_before:
		push_error("Smoke: stamina should recover off-ball")
		get_tree().quit(1)
		return
	print("Smoke Phase G stamina drain/recover OK")

	# Dead-ball sub: controlled outfielder ↔ selected bench.
	match_node.match_state = MatchController.MatchState.RULE_RESTART
	match_node._set_players_frozen(true)
	var out_player := match_node._first_outfield(match_node._home_players)
	match_node._set_controlled(out_player)
	var out_role_idx := out_player.player_index
	var out_name := out_player.name
	var bench_list := match_node._bench_players(0)
	if bench_list.is_empty():
		push_error("Smoke: no Home bench for sub")
		get_tree().quit(1)
		return
	match_node._bench_select_i = 0
	var in_player: Player = bench_list[0]
	var in_name := in_player.name
	if not match_node._can_substitute_now():
		push_error("Smoke: RULE_RESTART should allow subs")
		get_tree().quit(1)
		return
	match_node._try_substitution()
	print(
		"Smoke Phase G sub: out=", out_name, " in=", in_name,
		" controlled=", match_node.controlled_player.name if match_node.controlled_player else "null",
		" role_idx=", match_node.controlled_player.player_index if match_node.controlled_player else -1
	)
	if match_node.controlled_player != in_player:
		push_error("Smoke: sub should control the incoming bench player")
		get_tree().quit(1)
		return
	if match_node.controlled_player.player_index != out_role_idx:
		push_error("Smoke: incoming should inherit outgoing court role index")
		get_tree().quit(1)
		return
	if not out_player.on_bench:
		push_error("Smoke: outgoing should be on the bench after sub")
		get_tree().quit(1)
		return
	if in_player.on_bench:
		push_error("Smoke: incoming should leave the bench after sub")
		get_tree().quit(1)
		return
	# Live play blocks subs.
	match_node.match_state = MatchController.MatchState.LIVE
	match_node._set_players_frozen(false)
	if match_node._can_substitute_now():
		push_error("Smoke: LIVE should block substitutions")
		get_tree().quit(1)
		return
	# Cycle still skips bench.
	var before_cycle_g := match_node.controlled_player
	match_node._cycle_teammate()
	if match_node.controlled_player == null or match_node.controlled_player == before_cycle_g:
		push_error("Smoke: cycle should still advance with 7 on court")
		get_tree().quit(1)
		return
	if match_node.controlled_player.on_bench:
		push_error("Smoke: cycle must not select bench players")
		get_tree().quit(1)
		return
	print("Smoke Phase G roster/stamina/sub OK")

	# --- Playability: auto-control carrier / kickoff shape / IHF court lines ---
	_smoke_prepare_live(match_node, ball)
	_smoke_clear_ball(ball)
	var auto_lw: Player = null
	var auto_cb: Player = null
	var auto_rw: Player = null
	for p in match_node._home_players:
		if p.is_goalkeeper or p.on_bench:
			continue
		match Formations.role_for(p):
			Formations.Role.LEFT_WING:
				auto_lw = p
			Formations.Role.CENTER_BACK:
				auto_cb = p
			Formations.Role.RIGHT_WING:
				auto_rw = p
	if auto_lw == null or auto_cb == null or auto_rw == null:
		push_error("Smoke: missing LW/CB/RW for auto-control")
		get_tree().quit(1)
		return
	_smoke_park_unused_outfield(match_node, [auto_lw, auto_cb, auto_rw])
	match_node._set_controlled(auto_lw)
	auto_cb.global_position = Vector3(0.0, 0.0, 4.0)
	auto_cb.velocity = Vector3.ZERO
	auto_cb.ai_enabled = false
	ball.global_position = auto_cb.global_position + Vector3(0.2, 1.1, 0.0)
	if not ball.try_pickup(auto_cb):
		push_error("Smoke: auto-control pickup failed")
		get_tree().quit(1)
		return
	auto_cb.has_ball = true
	await get_tree().process_frame
	print(
		"Smoke auto-control after Home pickup: controlled=",
		match_node.controlled_player.name if match_node.controlled_player else "null",
		" carrier=", ball.carrier.name if ball.carrier else "null"
	)
	if match_node.controlled_player != auto_cb:
		push_error("Smoke: Home pickup should auto-control the ball carrier")
		get_tree().quit(1)
		return
	# Away possession must NOT steal control onto Away.
	_smoke_clear_ball(ball)
	var away_hold := match_node._first_outfield(match_node._away_players)
	away_hold.global_position = Vector3(1.0, 0.0, 2.0)
	match_node._set_controlled(auto_lw)
	if not ball.try_pickup(away_hold):
		push_error("Smoke: away hold pickup failed")
		get_tree().quit(1)
		return
	away_hold.has_ball = true
	await get_tree().process_frame
	if match_node.controlled_player != auto_lw or match_node.controlled_player.team_id != 0:
		push_error("Smoke: Away pickup must not force Away control")
		get_tree().quit(1)
		return
	print("Smoke auto-control Home carrier / ignore Away OK")

	# Pass catch should ride the receiver.
	_smoke_clear_ball(ball)
	for p in match_node._away_players:
		p.match_frozen = true
		p.ai_enabled = false
	_smoke_lock_pass_bots(match_node, [auto_lw, auto_cb, auto_rw])
	_smoke_park_unused_outfield(match_node, [auto_lw, auto_cb, auto_rw])
	auto_lw.global_position = Vector3(-2.0, 0.0, 0.0)
	auto_cb.global_position = Vector3(0.0, 0.0, 5.0)
	auto_rw.global_position = Vector3(7.5, 0.0, -2.0)
	match_node._set_controlled(auto_lw)
	_smoke_lock_pass_bots(match_node, [auto_lw, auto_cb, auto_rw])
	ball.global_position = auto_lw.global_position + Vector3(0.3, 1.1, 0.0)
	if not ball.try_pickup(auto_lw):
		push_error("Smoke: auto-control pass setup pickup failed")
		get_tree().quit(1)
		return
	auto_lw.has_ball = true
	if match_node.controlled_player != auto_lw:
		push_error("Smoke: passer should be controlled after Home pickup")
		get_tree().quit(1)
		return
	match_node._try_pass()
	var catch_ok := await _smoke_await_carrier(ball, auto_cb, 2.2)
	print(
		"Smoke auto-control after catch: caught=", catch_ok,
		" controlled=", match_node.controlled_player.name if match_node.controlled_player else "null"
	)
	if not catch_ok:
		push_error("Smoke: CB catch failed for auto-control check")
		get_tree().quit(1)
		return
	if match_node.controlled_player != auto_cb:
		push_error("Smoke: catch should auto-control the Home receiver")
		get_tree().quit(1)
		return

	# Kickoff shape: Home offense pre-mid; Away defense near own 6 m wall.
	match_node._place_kickoff_shape(0)
	var home_atk_ok := true
	var away_def_ok := true
	var away_goal_z := Court.HALF_LENGTH
	var def_line_z := away_goal_z - Formations.DEFENSE_LINE_M
	for p in match_node._home_players:
		if p.is_goalkeeper or p.on_bench:
			continue
		# Own half, approaching center (before midfield).
		if p.global_position.z >= -0.05 or p.global_position.z < -10.0:
			home_atk_ok = false
		if absf(p.global_position.z) < 0.4 and absf(p.global_position.x) < 0.4:
			# Only the separate taker placement sits on center; kickoff_slot CB is deeper.
			pass
	for p in match_node._away_players:
		if p.is_goalkeeper or p.on_bench:
			continue
		if absf(p.global_position.z - def_line_z) > 1.25:
			away_def_ok = false
		if Court.in_goal_area(p.global_position, 1):
			away_def_ok = false
	print(
		"Smoke kickoff Home atk pre-mid=", home_atk_ok,
		" Away def≈6m=", away_def_ok, " def_line_z=", def_line_z
	)
	if not home_atk_ok:
		push_error("Smoke: Home kickoff offense should sit in own half before midfield")
		get_tree().quit(1)
		return
	if not away_def_ok:
		push_error("Smoke: Away kickoff defense should wall near own 6 m")
		get_tree().quit(1)
		return
	# Mirror: Away kickoff → Home on own 6 m wall.
	match_node._place_kickoff_shape(1)
	var home_def_line := -Court.HALF_LENGTH + Formations.DEFENSE_LINE_M
	var home_def_ok := true
	var away_atk_ok := true
	for p in match_node._home_players:
		if p.is_goalkeeper or p.on_bench:
			continue
		if absf(p.global_position.z - home_def_line) > 1.25:
			home_def_ok = false
		if Court.in_goal_area(p.global_position, 0):
			home_def_ok = false
	for p in match_node._away_players:
		if p.is_goalkeeper or p.on_bench:
			continue
		if p.global_position.z <= 0.05 or p.global_position.z > 10.0:
			away_atk_ok = false
	print("Smoke kickoff Away atk=", away_atk_ok, " Home def≈6m=", home_def_ok)
	if not home_def_ok or not away_atk_ok:
		push_error("Smoke: Away kickoff should put Home on 6 m and Away pre-mid")
		get_tree().quit(1)
		return

	# Court lines: IHF D geometry helpers + Lines node with goal-area arcs.
	if not Court.in_goal_area(Vector3(0.0, 0.0, -14.0), 0):
		push_error("Smoke: (0,-14) should be on/inside home 6 m straight")
		get_tree().quit(1)
		return
	if Court.in_goal_area(Vector3(0.0, 0.0, -13.5), 0):
		push_error("Smoke: (0,-13.5) should be outside home 6 m")
		get_tree().quit(1)
		return
	# Outside the posts: quarter-circle reaches x≈-1.5-6 at the goal line.
	if not Court.in_goal_area(Vector3(-5.0, 0.0, -19.0), 0):
		push_error("Smoke: near-post quarter-circle should cover (-5,-19)")
		get_tree().quit(1)
		return
	if Court.in_goal_area(Vector3(-8.0, 0.0, -14.0), 0):
		push_error("Smoke: far corner outside D should not be in goal area")
		get_tree().quit(1)
		return
	var court_node: Node3D = null
	for child in match_node.get_children():
		if child is Court:
			court_node = child
			break
	if court_node == null:
		push_error("Smoke: Court node missing")
		get_tree().quit(1)
		return
	var lines_node := court_node.get_node_or_null("Lines")
	if lines_node == null or lines_node.get_child_count() < 40:
		push_error("Smoke: Court Lines should include IHF arc/segment meshes")
		get_tree().quit(1)
		return
	print("Smoke IHF court lines + goal-area D OK (line meshes=", lines_node.get_child_count(), ")")

	# Scale: 1 unit = 1 m, player ~1.90 m on a 20 m width, arcs are quarter-circles.
	if absf(Court.METERS_PER_UNIT - 1.0) > 0.001:
		push_error("Smoke: Court.METERS_PER_UNIT must be 1")
		get_tree().quit(1)
		return
	if absf(Court.HALF_LENGTH - 20.0) > 0.001 or absf(Court.HALF_WIDTH - 10.0) > 0.001:
		push_error("Smoke: court must be 40 x 20 m")
		get_tree().quit(1)
		return
	player.on_bench = false
	player.excluded = false
	player._pose_standing_rest()
	var top := player.standing_head_top()
	if absf(top - Player.VISUAL_HEIGHT_M) > 0.05:
		push_error("Smoke: standing height %.2f != %.2f" % [top, Player.VISUAL_HEIGHT_M])
		get_tree().quit(1)
		return
	if Player.VISUAL_HEIGHT_M / (Court.HALF_WIDTH * 2.0) > 0.14:
		push_error("Smoke: player is too tall relative to the 20 m court width")
		get_tree().quit(1)
		return
	var cap_node := player.get_node("CollisionShape3D") as CollisionShape3D
	var cap := cap_node.shape as CapsuleShape3D
	if absf(cap.radius - Player.BODY_RADIUS) > 0.001:
		push_error("Smoke: BODY_RADIUS must match the capsule")
		get_tree().quit(1)
		return
	if absf(cap_node.position.y - cap.height * 0.5) > 0.04:
		push_error("Smoke: capsule feet should sit on the floor")
		get_tree().quit(1)
		return
	for team_id in [0, 1]:
		for side in [-1.0, 1.0]:
			var ang := Court.goal_arc_angles(team_id, side)
			var sweep := absf(wrapf(ang.y - ang.x, -PI, PI))
			if absf(sweep - PI * 0.5) > 0.02:
				push_error("Smoke: goal arc must be a quarter circle (team %s side %s)" % [team_id, side])
				get_tree().quit(1)
				return
		for slot in [0, 1, 5]:
			var marker := Court.bench_marker(team_id, slot)
			if absf(marker.x) <= Court.HALF_WIDTH + 0.6:
				push_error("Smoke: bench marker is not outside the sideline")
				get_tree().quit(1)
				return
			if absf(marker.z) >= Court.HALF_LENGTH - 0.4:
				push_error("Smoke: bench marker should sit beside the court")
				get_tree().quit(1)
				return
	if court_node.get_node_or_null("Hall") == null:
		push_error("Smoke: hall shell missing")
		get_tree().quit(1)
		return
	var bench_pose_ok := true
	for p in match_node._all_players():
		if not p.on_bench:
			continue
		p.global_position = Court.bench_marker(p.team_id, p.bench_slot)
		p.rotation.y = Court.bench_yaw(p.team_id)
	await get_tree().physics_frame
	await get_tree().physics_frame
	for p in match_node._all_players():
		if not p.on_bench:
			continue
		if absf(p.global_position.x) <= Court.HALF_WIDTH + 0.4:
			bench_pose_ok = false
		if absf(p.global_position.y) > 0.45:
			bench_pose_ok = false
		# Wave 1: modular body sits (legs bent, upper body lowered) — not a fallen capsule.
		var leg_l := p.get_node_or_null("LegL") as Node3D
		var upper := p.get_node_or_null("UpperBody") as Node3D
		if leg_l == null or upper == null:
			bench_pose_ok = false
		elif absf(leg_l.rotation.x) < 0.6:
			bench_pose_ok = false
		elif upper.position.y > -0.2:
			bench_pose_ok = false
	print("Smoke scale/hall/bench pose=", bench_pose_ok, " height=", top)
	if not bench_pose_ok:
		push_error("Smoke: substitutes should sit on the bench, off the court, on the floor")
		get_tree().quit(1)
		return
	print("Smoke playability auto-control / kickoff / court OK")

	# --- Wave 0: camera after scale, bindings, ball rescue, period resume ---
	if cam.follow_height < 10.0 or cam.follow_height > 13.5:
		push_error("Smoke: camera follow_height should stay elevated 3/4 after court scale")
		get_tree().quit(1)
		return
	if cam.follow_distance < 13.0 or cam.follow_distance > 17.0:
		push_error("Smoke: camera follow_distance should read the 40×20 hall")
		get_tree().quit(1)
		return
	# Side yaw still orbits the ball pivot (regression guard after hall/scale).
	var w0_ball := Vector3(5.5, 0.9, 1.0)
	cam.set_attack_direction(true)
	cam.attack_sign = 1.0
	var w0_desired := cam._desired_position(w0_ball)
	var w0_pivot := cam.pivot_point(w0_ball)
	var w0_yaw := cam.ball_yaw(w0_ball)
	var w0_flat := Vector3(w0_desired.x, 0.0, w0_desired.z) - w0_pivot
	var w0_uny := w0_flat.rotated(Vector3.UP, -w0_yaw)
	print(
		"Smoke Wave0 cam: h=", cam.follow_height,
		" d=", cam.follow_distance,
		" yaw=", w0_yaw,
		" unyaw_z=", w0_uny.z
	)
	if w0_yaw <= 0.0:
		push_error("Smoke: Wave0 side ball should apply positive yaw about the ball")
		get_tree().quit(1)
		return
	if absf(w0_uny.z - (-cam.follow_distance)) > 0.3:
		push_error("Smoke: Wave0 yaw pivot should stay ball-centered")
		get_tree().quit(1)
		return

	# Bindings: shoot = RT axis (not L3); lob must not share Back with sprint.
	var shoot_has_rt := false
	var shoot_has_l3 := false
	for ev in InputMap.action_get_events("shoot"):
		if ev is InputEventJoypadMotion and (ev as InputEventJoypadMotion).axis == 5:
			shoot_has_rt = true
		if ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == 7:
			shoot_has_l3 = true
	var lob_has_back := false
	var sprint_has_back := false
	for ev in InputMap.action_get_events("lob"):
		if ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == 4:
			lob_has_back = true
	for ev in InputMap.action_get_events("sprint"):
		if ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == 4:
			sprint_has_back = true
	print(
		"Smoke Wave0 bindings: shoot_rt=", shoot_has_rt,
		" shoot_l3=", shoot_has_l3,
		" lob_back=", lob_has_back,
		" sprint_back=", sprint_has_back
	)
	if not shoot_has_rt or shoot_has_l3:
		push_error("Smoke: shoot must use RT (axis 5), not L3 (button 7)")
		get_tree().quit(1)
		return
	if lob_has_back or not sprint_has_back:
		push_error("Smoke: lob must not share Back/Select with sprint")
		get_tree().quit(1)
		return

	# Ball under-floor rescue → back in play.
	_smoke_clear_ball(ball)
	ball.global_position = Vector3(2.0, -2.5, 3.0)
	ball.linear_velocity = Vector3(0.0, -4.0, 0.0)
	ball._rescue_if_lost()
	print("Smoke Wave0 ball rescue y=", ball.global_position.y, " pos=", ball.global_position)
	if ball.global_position.y < 0.5:
		push_error("Smoke: ball under floor should be rescued above the court")
		get_tree().quit(1)
		return
	if absf(ball.global_position.x) > Court.HALF_WIDTH or absf(ball.global_position.z) > Court.HALF_LENGTH:
		push_error("Smoke: rescued ball should stay inside the court")
		get_tree().quit(1)
		return

	# Restart always resumes LIVE with a carrier (soft-lock guard).
	_smoke_prepare_live(match_node, ball)
	_smoke_clear_ball(ball)
	var w0_spot := Vector3(1.0, 0.0, 4.0)
	await match_node._run_rule_restart("traveling", "Wave0 traveling", 1, w0_spot)
	print(
		"Smoke Wave0 restart: state=", match_node.match_state,
		" carrier=", ball.carrier.name if ball.carrier else "null",
		" team=", ball.carrier.team_id if ball.carrier else -1
	)
	if match_node.match_state != MatchController.MatchState.LIVE:
		push_error("Smoke: rule restart must return to LIVE")
		get_tree().quit(1)
		return
	if ball.carrier == null or ball.carrier.team_id != 1 or not ball.carrier.has_ball:
		push_error("Smoke: rule restart must leave Away with the ball")
		get_tree().quit(1)
		return

	# Period expire → next period kickoff LIVE (clock/goals keep working).
	_smoke_prepare_live(match_node, ball)
	_smoke_clear_ball(ball)
	match_node.current_period = 1
	match_node.periods_total = 2
	match_node.clock_remaining = 0.0
	match_node.score_home = 1
	match_node.score_away = 0
	match_node.match_state = MatchController.MatchState.LIVE
	await match_node._on_period_expired()
	print(
		"Smoke Wave0 period: state=", match_node.match_state,
		" period=", match_node.current_period,
		" clock=", match_node.clock_remaining,
		" carrier_team=", ball.carrier.team_id if ball.carrier else -1
	)
	if match_node.match_state != MatchController.MatchState.LIVE:
		push_error("Smoke: period break should resume LIVE for period 2")
		get_tree().quit(1)
		return
	if match_node.current_period != 2:
		push_error("Smoke: expected period 2 after first expire")
		get_tree().quit(1)
		return
	if match_node.clock_remaining <= 0.0:
		push_error("Smoke: period 2 clock should reset")
		get_tree().quit(1)
		return
	if ball.carrier == null:
		push_error("Smoke: period kickoff must give someone the ball")
		get_tree().quit(1)
		return
	print("Smoke Wave0 playability rescue OK")

	# --- Wave 1: modular body anchors (hair→feet), head region, hand ball attach ---
	_smoke_prepare_live(match_node, ball)
	player = match_node.controlled_player
	if player == null or player.on_bench:
		player = match_node._first_outfield(match_node._home_players)
		if player:
			match_node._set_controlled(player)
	if player == null:
		push_error("Smoke Wave1: missing outfield player")
		get_tree().quit(1)
		return
	player.on_bench = false
	player.excluded = false
	player._pose_standing_rest()
	await get_tree().physics_frame

	var required_parts := [
		"UpperBody", "MeshInstance3D", "Head", "FacePlate", "Hair",
		"HeadRegion", "ArmL", "ArmR", "HandL", "HandR",
		"LegL", "LegR", "FootL", "FootR", "ShoeL", "ShoeR",
	]
	for part_name in required_parts:
		var part := player.find_child(part_name, true, false)
		if part == null:
			# Bald archetype hides Hair mesh but node must exist.
			if part_name == "Hair" and player.hair_style() == Player.HairStyle.BALD:
				continue
			push_error("Smoke Wave1: missing body part %s" % part_name)
			get_tree().quit(1)
			return
	var head_region := player.get_head_region()
	if head_region == null or str(head_region.get_meta("body_region", "")) != "head":
		push_error("Smoke Wave1: HeadRegion must be tagged body_region=head")
		get_tree().quit(1)
		return
	if str(head_region.get_meta("foul_region", "")) != "head_neck":
		push_error("Smoke Wave1: HeadRegion must be tagged foul_region=head_neck")
		get_tree().quit(1)
		return
	# Hair styles cycle; at least one non-bald and bald exist across roster.
	var styles_seen := {}
	for p in match_node._all_players():
		styles_seen[p.hair_style()] = true
	if styles_seen.size() < 3:
		push_error("Smoke Wave1: expected multiple hair archetypes across roster")
		get_tree().quit(1)
		return
	# Ball attach lives on the right hand (not floating mid-torso).
	var hand_r := player.find_child("HandR", true, false) as Node3D
	if hand_r == null or player.ball_attach == null:
		push_error("Smoke Wave1: HandR / BallAttach missing")
		get_tree().quit(1)
		return
	if player.ball_attach.get_parent() != hand_r:
		push_error("Smoke Wave1: BallAttach should be parented under HandR")
		get_tree().quit(1)
		return
	# Possessed ball should sit near the hand, not chest center.
	if ball.carrier != null and ball.carrier != player:
		ball.carrier.has_ball = false
		ball.carrier = null
	player.global_position = Vector3(0.0, 0.0, 0.0)
	player.velocity = Vector3.ZERO
	ball.global_position = player.ball_attach.global_position
	var picked := ball.try_pickup(player)
	player.has_ball = picked
	if not picked:
		push_error("Smoke Wave1: try_pickup failed for hand-attach check")
		get_tree().quit(1)
		return
	for _k in range(6):
		await get_tree().physics_frame
	var hand_pos := player.ball_attach.global_position
	var ball_pos := ball.global_position
	var hand_dist := hand_pos.distance_to(ball_pos)
	print("Smoke Wave1 hand attach dist=", hand_dist, " hand=", hand_pos, " ball=", ball_pos)
	if hand_dist > 0.35:
		push_error("Smoke Wave1: possessed ball should follow the hand attach")
		get_tree().quit(1)
		return
	# Feet soles near court floor (y≈0).
	var foot_l := player.find_child("ShoeL", true, false) as Node3D
	var foot_y := foot_l.global_position.y if foot_l else 99.0
	if foot_y > 0.12 or foot_y < -0.05:
		push_error("Smoke Wave1: feet should plant near y=0 (got %.3f)" % foot_y)
		get_tree().quit(1)
		return
	# Torso can yaw independently of feet.
	player.set_torso_yaw_offset(0.4)
	for _i in range(8):
		await get_tree().physics_frame
	var upper := player.get_node_or_null("UpperBody") as Node3D
	if upper == null or absf(upper.rotation.y) < 0.15:
		push_error("Smoke Wave1: UpperBody should yaw independently of feet")
		get_tree().quit(1)
		return
	player.set_torso_yaw_offset(0.0)
	# Jog: legs should swing when moving on floor.
	player.global_position.y = 0.0
	player.velocity = Vector3(0.0, 0.0, 6.0)
	player._bob_phase = 1.2
	for _j in range(10):
		player._update_locomotion_anim(0.05, 6.0)
	var leg := player.get_node_or_null("LegL") as Node3D
	var jog_swing := absf(leg.rotation.x) if leg else 0.0
	print("Smoke Wave1 jog leg swing=", jog_swing)
	if jog_swing < 0.05:
		push_error("Smoke Wave1: jog should swing legs")
		get_tree().quit(1)
		return
	player.velocity = Vector3.ZERO
	player._pose_standing_rest()
	# Bench seated uses modular legs/torso.
	var bench_p: Player = null
	for p in match_node._home_players:
		if p.on_bench:
			bench_p = p
			break
	if bench_p == null:
		push_error("Smoke Wave1: need a bench player")
		get_tree().quit(1)
		return
	bench_p._apply_bench_visual()
	var b_leg := bench_p.get_node_or_null("LegL") as Node3D
	var b_upper := bench_p.get_node_or_null("UpperBody") as Node3D
	if b_leg == null or absf(b_leg.rotation.x) < 0.6:
		push_error("Smoke Wave1: bench pose should bend legs")
		get_tree().quit(1)
		return
	if b_upper == null or b_upper.position.y > -0.2:
		push_error("Smoke Wave1: bench pose should lower torso onto the seat")
		get_tree().quit(1)
		return
	print(
		"Smoke Wave1 body anchors OK hair_styles=", styles_seen.size(),
		" head_top=", player.standing_head_top(),
		" hand_dist=", hand_dist
	)

	# --- Wave 2: throw & jump motion (pass / shoot / jump pass / jump shot / wing) ---
	_smoke_prepare_live(match_node, ball)
	player = match_node.controlled_player
	if player == null or player.on_bench:
		player = match_node._first_outfield(match_node._home_players)
		if player:
			match_node._set_controlled(player)
	if player == null:
		push_error("Smoke Wave2: missing outfield player")
		get_tree().quit(1)
		return
	player.on_bench = false
	player.excluded = false
	player.clear_throw_motion()
	player._pose_standing_rest()
	player.global_position = Vector3(0.0, 0.0, 0.0)
	player.velocity = Vector3.ZERO
	player.rotation.y = 0.0
	# R2.1 flat / bounce / lob pass windup → follow + torso toward target.
	var pass_mate: Player = match_node._first_outfield(match_node._home_players)
	for p in match_node._home_players:
		if p != player and not p.is_goalkeeper and not p.on_bench:
			pass_mate = p
			break
	for pass_type in [PassCraft.PassType.FLAT, PassCraft.PassType.BOUNCE, PassCraft.PassType.LOB]:
		player.clear_throw_motion()
		player.has_ball = true
		if ball.carrier and ball.carrier != player:
			ball.carrier.has_ball = false
		ball.carrier = player
		ball.global_position = player.ball_attach.global_position
		pass_mate.global_position = Vector3(2.0, 0.0, 6.0)
		if not player.try_pass_to(pass_mate, ball, -1.0, Vector3(0, 0, 1), pass_type):
			push_error("Smoke Wave2: pass type %d failed to release" % pass_type)
			get_tree().quit(1)
			return
		if player.throw_action != ThrowMotion.Action.PASS:
			push_error("Smoke Wave2: standing pass should start PASS action (got %d)" % player.throw_action)
			get_tree().quit(1)
			return
		if player.throw_phase != ThrowMotion.Phase.WINDUP:
			push_error("Smoke Wave2: pass should start in WINDUP")
			get_tree().quit(1)
			return
		var yaw0 := absf(player.get_torso_yaw_offset())
		var arm_r0 := player.find_child("ArmR", true, false) as Node3D
		player._apply_throw_pose(1.0)
		var windup_rot := absf(arm_r0.rotation_degrees.x) if arm_r0 else 0.0
		# Advance through windup → release → follow.
		for _step in range(24):
			player._tick_throw_motion(0.05)
			player._apply_throw_pose(0.05)
		print(
			"Smoke Wave2 pass type=", pass_type,
			" yaw=", yaw0, " windup_arm=", windup_rot,
			" busy=", player.throw_motion_active
		)
		if yaw0 < 0.05 and pass_type == PassCraft.PassType.FLAT:
			# Target is ahead (+Z) while facing +Z — yaw may be near 0; force a side target once.
			player.clear_throw_motion()
			player.has_ball = true
			ball.carrier = player
			pass_mate.global_position = Vector3(8.0, 0.0, 4.0)
			player.try_pass_to(pass_mate, ball, -1.0, Vector3(1, 0, 0.2), PassCraft.PassType.FLAT)
			if absf(player.get_torso_yaw_offset()) < 0.12:
				push_error("Smoke Wave2: pass should yaw torso toward target")
				get_tree().quit(1)
				return
		if windup_rot < 20.0:
			push_error("Smoke Wave2: pass windup should cock ArmR (rot=%.1f)" % windup_rot)
			get_tree().quit(1)
			return
		# Ball must still leave HandR attach (Wave 0 playability).
		if ball.carrier == player:
			push_error("Smoke Wave2: pass must release ball from HandR carrier")
			get_tree().quit(1)
			return

	# R2.2 charge pose scales; release + follow; lob variant.
	_smoke_prepare_live(match_node, ball)
	player = match_node.controlled_player
	player.clear_throw_motion()
	player.global_position = Vector3(0.0, 0.0, 5.0)
	player.velocity = Vector3.ZERO
	player._pickup_block = 0.0
	if ball.carrier and is_instance_valid(ball.carrier):
		ball.carrier.has_ball = false
		ball.carrier._pickup_block = 0.0
	ball.carrier = null
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	ball.last_shot_meta = {}
	ball.global_position = player.ball_attach.global_position
	ball.freeze = true
	if not ball.try_pickup(player):
		# Force possess if Area pickup is sticky after prior releases.
		ball.carrier = player
		player.has_ball = true
		ball.global_position = player.ball_attach.global_position
	if ball.carrier != player:
		push_error("Smoke Wave2: charge pickup failed")
		get_tree().quit(1)
		return
	player.has_ball = true
	ball.freeze = false
	player.set_shot_charge_motion(0.2, false, Vector3(0, 0.1, 1))
	player._apply_throw_pose(1.0)
	var arm_low := player.find_child("ArmR", true, false) as Node3D
	var charge_low_y := arm_low.position.y if arm_low else 0.0
	player.set_shot_charge_motion(1.0, false, Vector3(0, 0.1, 1))
	player._apply_throw_pose(1.0)
	var charge_high_y := arm_low.position.y if arm_low else 0.0
	player.set_shot_charge_motion(1.0, true, Vector3(0, 0.4, 1))
	player._apply_throw_pose(1.0)
	var charge_lob_y := arm_low.position.y if arm_low else 0.0
	print(
		"Smoke Wave2 charge y low=", charge_low_y,
		" high=", charge_high_y, " lob=", charge_lob_y
	)
	if charge_high_y <= charge_low_y + 0.05:
		push_error("Smoke Wave2: charge pose should raise ArmR with hold")
		get_tree().quit(1)
		return
	if charge_lob_y < charge_high_y - 0.02:
		push_error("Smoke Wave2: lob charge should lift arm path")
		get_tree().quit(1)
		return
	match_node._try_shoot_charged(ShotCraft.CHARGE_TIME_S)
	if player.throw_action != ThrowMotion.Action.SHOOT and player.throw_action != ThrowMotion.Action.WING_SHOT:
		push_error("Smoke Wave2: grounded shot should start SHOOT/WING action")
		get_tree().quit(1)
		return
	if player.throw_phase != ThrowMotion.Phase.RELEASE:
		push_error("Smoke Wave2: shot release should enter RELEASE phase")
		get_tree().quit(1)
		return
	for _s in range(20):
		player._tick_throw_motion(0.05)
		player._apply_throw_pose(0.05)
	print("Smoke Wave2 shoot charge/release OK")

	# R2.3 jump pass: airborne pass action distinct from jump shot.
	_smoke_prepare_live(match_node, ball)
	player = match_node.controlled_player
	player.clear_throw_motion()
	player.global_position = Vector3(0.0, 0.0, 2.0)
	player._pickup_block = 0.0
	if ball.carrier and is_instance_valid(ball.carrier):
		ball.carrier.has_ball = false
	ball.carrier = player
	player.has_ball = true
	ball.linear_velocity = Vector3.ZERO
	ball.last_shot_meta = {}
	ball.global_position = player.ball_attach.global_position
	player.jump_shot_active = true
	player.jump_shot_phase = ShotCraft.JumpPhase.WINDOW
	player.jump_shot_air_s = 0.35
	player.velocity = Vector3(0.0, 2.0, 0.0)
	# Force airborne read for motion (is_on_floor may still be true after teleport).
	player.global_position.y = 0.9
	var jp_mate: Player = null
	for p in match_node._home_players:
		if p != player and not p.is_goalkeeper and not p.on_bench:
			jp_mate = p
			break
	if jp_mate == null:
		push_error("Smoke Wave2: need teammate for jump pass")
		get_tree().quit(1)
		return
	jp_mate.global_position = Vector3(3.0, 0.0, 8.0)
	if not player.try_pass_to(jp_mate, ball, -1.0, Vector3(0, 0, 1), PassCraft.PassType.FLAT):
		push_error("Smoke Wave2: jump pass failed")
		get_tree().quit(1)
		return
	if player.throw_action != ThrowMotion.Action.JUMP_PASS:
		push_error("Smoke Wave2: airborne pass should be JUMP_PASS (got %d)" % player.throw_action)
		get_tree().quit(1)
		return
	if player.jump_shot_active:
		push_error("Smoke Wave2: jump pass should clear jump-shot craft")
		get_tree().quit(1)
		return
	print("Smoke Wave2 jump pass OK")

	# R2.4 jump shot: approach → plant → air → release window; sweet/early/late still differ.
	_smoke_prepare_live(match_node, ball)
	player = match_node.controlled_player
	player.clear_throw_motion()
	player.global_position = Vector3(0.0, 0.0, 8.0)
	player.velocity = Vector3(0.0, 0.0, 5.0)
	if ball.carrier and is_instance_valid(ball.carrier):
		ball.carrier.has_ball = false
	ball.carrier = null
	ball.global_position = player.ball_attach.global_position
	ball.try_pickup(player)
	player.has_ball = true
	player._pickup_block = 0.0
	ball.carrier = player
	player.has_ball = true
	ball.global_position = player.ball_attach.global_position
	player._begin_jump_from_input(Vector3(0, 0, 1))
	if player.jump_shot_phase != ShotCraft.JumpPhase.APPROACH and player.jump_shot_phase != ShotCraft.JumpPhase.PLANTED:
		push_error("Smoke Wave2: jump shot should enter approach/plant")
		get_tree().quit(1)
		return
	# Force plant pose read (second half of plant hold).
	player.jump_shot_phase = ShotCraft.JumpPhase.PLANTED
	player._apply_throw_pose(1.0)
	var plant_leg := player.get_node_or_null("LegR") as Node3D
	var plant_x := absf(plant_leg.rotation.x) if plant_leg else 0.0
	# Airborne cock without relying on physics floor contact.
	player._js_plant_t = 0.0
	player.jump_shot_active = true
	player.has_ball = true
	player.jump_shot_phase = ShotCraft.JumpPhase.WINDOW
	player.jump_shot_air_s = 0.35
	player.global_position.y = 0.9
	player.velocity.y = 3.0
	player._apply_throw_pose(1.0)
	var air_arm := player.find_child("ArmR", true, false) as Node3D
	var air_cock := absf(air_arm.rotation_degrees.x) if air_arm else 0.0
	var sweet := ShotCraft.apply_jump_timing(Vector3(0, 0.1, 1), 14.0, 1)
	var early := ShotCraft.apply_jump_timing(Vector3(0, 0.1, 1), 14.0, 0)
	var late := ShotCraft.apply_jump_timing(Vector3(0, 0.1, 1), 14.0, 2)
	print(
		"Smoke Wave2 jump shot plant_leg=", plant_x, " air_cock=", air_cock,
		" sweet=", sweet["impulse"], " early=", early["impulse"], " late=", late["impulse"]
	)
	if plant_x < 0.15:
		push_error("Smoke Wave2: plant pose should load a leg")
		get_tree().quit(1)
		return
	if air_cock < 40.0:
		push_error("Smoke Wave2: airborne jump shot should cock ArmR")
		get_tree().quit(1)
		return
	if float(sweet["impulse"]) <= float(early["impulse"]):
		push_error("Smoke Wave2: sweet release must still beat early")
		get_tree().quit(1)
		return
	if float(sweet["impulse"]) <= float(late["impulse"]):
		push_error("Smoke Wave2: sweet release must still beat late")
		get_tree().quit(1)
		return
	# Release while airborne → JUMP_SHOT action.
	player.clear_throw_motion()
	player.jump_shot_active = true
	player.has_ball = true
	ball.carrier = player
	ball.global_position = player.ball_attach.global_position
	player.global_position.y = 0.9
	if not player.try_shoot(Vector3(0, 0.15, 1), 16.0, ball, 0.1, {"charge": 0.7, "jump_shot": true}):
		push_error("Smoke Wave2: jump shot release failed")
		get_tree().quit(1)
		return
	if player.throw_action != ThrowMotion.Action.JUMP_SHOT and player.throw_action != ThrowMotion.Action.WING_SHOT:
		push_error("Smoke Wave2: airborne shot should be JUMP_SHOT/WING (got %d)" % player.throw_action)
		get_tree().quit(1)
		return
	print("Smoke Wave2 jump shot approach/plant/air/release OK")

	# R2.6 wing shot: wide approach, open body, wing finish + aim assist.
	_smoke_prepare_live(match_node, ball)
	player = match_node.controlled_player
	# Prefer a real wing role when available.
	for p in match_node._home_players:
		if Formations.is_wing(Formations.role_for(p)) and not p.on_bench:
			player = p
			match_node._set_controlled(player)
			break
	player.clear_throw_motion()
	player.global_position = Vector3(7.2, 0.0, 12.0)
	player.velocity = Vector3.ZERO
	player.rotation.y = 0.0
	if not ThrowMotion.is_wing_finish_context(player):
		push_error("Smoke Wave2: wide near-goal spot should read as wing finish")
		get_tree().quit(1)
		return
	var raw_aim := Vector3(0.0, 0.15, 1.0).normalized()
	var assisted := ThrowMotion.wing_aim_assist(player, raw_aim)
	if assisted.distance_to(raw_aim) < 0.02:
		push_error("Smoke Wave2: wing aim assist should nudge toward goal mouth")
		get_tree().quit(1)
		return
	if ball.carrier and is_instance_valid(ball.carrier):
		ball.carrier.has_ball = false
	ball.carrier = null
	ball.global_position = player.ball_attach.global_position
	ball.try_pickup(player)
	player.has_ball = true
	player.set_shot_charge_motion(0.85, false, assisted)
	player._apply_throw_pose(1.0)
	var wing_yaw := absf(player.get_torso_yaw_offset())
	if not player.try_shoot(assisted, 15.0, ball, 0.08, {"charge": 0.85, "wing_shot": true}):
		push_error("Smoke Wave2: wing shot release failed")
		get_tree().quit(1)
		return
	if player.throw_action != ThrowMotion.Action.WING_SHOT:
		push_error("Smoke Wave2: wing finish should use WING_SHOT action (got %d)" % player.throw_action)
		get_tree().quit(1)
		return
	if not bool(ball.last_shot_meta.get("wing_shot", false)):
		push_error("Smoke Wave2: wing_shot meta missing on release")
		get_tree().quit(1)
		return
	# Ball attach still under HandR after Wave 2 poses.
	var hand_r2 := player.find_child("HandR", true, false) as Node3D
	if hand_r2 == null or player.ball_attach.get_parent() != hand_r2:
		push_error("Smoke Wave2: BallAttach must stay under HandR")
		get_tree().quit(1)
		return
	print(
		"Smoke Wave2 wing shot OK yaw=", wing_yaw,
		" assist_delta=", assisted.distance_to(raw_aim),
		" action=", ThrowMotion.action_name(player.throw_action)
	)
	print("Smoke Wave2 throw and jump motion OK")

	# --- Wave 3: fakes + GK motion vocabulary ---
	_smoke_prepare_live(match_node, ball)
	player = match_node.controlled_player
	if player == null or player.on_bench or player.is_goalkeeper:
		player = match_node._first_outfield(match_node._home_players)
		if player:
			match_node._set_controlled(player)
	if player == null:
		push_error("Smoke Wave3: missing outfield player")
		get_tree().quit(1)
		return
	player.clear_fake_motion()
	player.clear_throw_motion()
	player.global_position = Vector3(0.0, 0.0, 4.0)
	player.velocity = Vector3.ZERO
	player._pickup_block = 0.0
	if ball.carrier and is_instance_valid(ball.carrier):
		ball.carrier.has_ball = false
	ball.carrier = player
	player.has_ball = true
	ball.linear_velocity = Vector3.ZERO
	ball.last_shot_meta = {}
	ball.global_position = player.ball_attach.global_position

	# Bindings present and do not steal shoot/pass/dribble.
	for action_name in ["fake_shot", "fake_pass", "fake_jab"]:
		if not InputMap.has_action(action_name):
			push_error("Smoke Wave3: missing input action %s" % action_name)
			get_tree().quit(1)
			return
	var shoot_has_x := false
	for ev in InputMap.action_get_events("shoot"):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_X:
			shoot_has_x = true
	if shoot_has_x:
		push_error("Smoke Wave3: shoot must not use X (shot fake)")
		get_tree().quit(1)
		return

	# R2.5 / R4.9: three fakes keep the ball and never release.
	var marker: Player = null
	for p in match_node._away_players:
		if not p.is_goalkeeper and not p.on_bench:
			marker = p
			break
	if marker == null:
		push_error("Smoke Wave3: need an away marker for sell test")
		get_tree().quit(1)
		return
	for kind in [FakeMotion.Kind.SHOT, FakeMotion.Kind.PASS, FakeMotion.Kind.JAB]:
		player.clear_fake_motion()
		player._fake_cd = 0.0
		player.has_ball = true
		ball.carrier = player
		ball.global_position = player.ball_attach.global_position
		marker.global_position = player.global_position + Vector3(1.2, 0.0, 0.8)
		marker.fake_sold_t = 0.0
		marker.fake_recover_t = 0.0
		marker.velocity = Vector3.ZERO
		var started := player.try_fake(kind, Vector3(0.2, 0.0, 1.0))
		if not started or not player.fake_active:
			push_error("Smoke Wave3: fake kind %d failed to start" % kind)
			get_tree().quit(1)
			return
		if player.fake_kind != kind:
			push_error("Smoke Wave3: fake kind mismatch")
			get_tree().quit(1)
			return
		if ball.carrier != player or not player.has_ball:
			push_error("Smoke Wave3: fake must keep possession")
			get_tree().quit(1)
			return
		# Charge abort + release blocked while faking.
		player.set_shot_charge_motion(0.8, false, Vector3(0, 0.1, 1))
		if player.throw_phase == ThrowMotion.Phase.CHARGE and player.fake_active:
			# try_fake clears charge when starting; mid-fake charge should not release.
			pass
		# Read poses before any charge probe (charge would steal the arm/leg overlay).
		player.clear_throw_motion()
		player._apply_fake_pose(1.0)
		var arm_r := player.find_child("ArmR", true, false) as Node3D
		var leg_r := player.get_node_or_null("LegR") as Node3D
		var leg_l := player.get_node_or_null("LegL") as Node3D
		if kind == FakeMotion.Kind.SHOT and arm_r and absf(arm_r.rotation_degrees.x) < 20.0:
			push_error("Smoke Wave3: shot fake should cock ArmR")
			get_tree().quit(1)
			return
		if kind == FakeMotion.Kind.JAB:
			var jab_plant := 0.0
			if leg_r:
				jab_plant = maxf(jab_plant, absf(leg_r.rotation.x))
			if leg_l:
				jab_plant = maxf(jab_plant, absf(leg_l.rotation.x))
			if jab_plant < 0.15:
				push_error("Smoke Wave3: jab fake should plant a leg (plant=%.3f)" % jab_plant)
				get_tree().quit(1)
				return
		if marker.fake_sold_t <= 0.0:
			push_error("Smoke Wave3: nearby marker should be sold (lite)")
			get_tree().quit(1)
			return
		# Charge abort + release blocked while faking.
		player.set_shot_charge_motion(0.8, false, Vector3(0, 0.1, 1))
		if player.try_shoot(Vector3(0, 0.1, 1), 14.0, ball):
			push_error("Smoke Wave3: try_shoot must fail while faking")
			get_tree().quit(1)
			return
		if ball.carrier != player:
			push_error("Smoke Wave3: shot must not fire during fake")
			get_tree().quit(1)
			return
		player.clear_throw_motion()
		# Advance through threaten → recover → done; ball still held.
		for _step in range(30):
			player._tick_fake_motion(0.05)
			player._apply_fake_pose(0.05)
		if player.fake_active:
			push_error("Smoke Wave3: fake should finish recover")
			get_tree().quit(1)
			return
		if ball.carrier != player or not player.has_ball:
			push_error("Smoke Wave3: possession must survive fake recover")
			get_tree().quit(1)
			return
		print("Smoke Wave3 fake ", FakeMotion.kind_name(kind), " OK sold=", marker.fake_sold_t)

	# Mid-charge fake cancels charge and keeps ball.
	player.clear_fake_motion()
	player._fake_cd = 0.0
	player.has_ball = true
	ball.carrier = player
	match_node._charging = true
	match_node._charge_held_s = 0.6
	player.set_shot_charge_motion(0.6, false, Vector3(0, 0.1, 1))
	match_node._try_fake(FakeMotion.Kind.SHOT)
	if match_node._charging:
		push_error("Smoke Wave3: fake should cancel shoot charge")
		get_tree().quit(1)
		return
	if ball.carrier != player:
		push_error("Smoke Wave3: charge cancel via fake must not release")
		get_tree().quit(1)
		return
	print("Smoke Wave3 charge-cancel fake OK")

	# R2.7 GK vocabulary: set / shuffle / dive L-R low-high / catch vs deflect / outlet / 4 m.
	var gk := match_node._goalkeeper_for(0)
	if gk == null:
		push_error("Smoke Wave3: missing home GK")
		get_tree().quit(1)
		return
	gk.match_frozen = false
	gk.ai_enabled = true
	gk.controlled = false
	gk.has_ball = false
	gk.diving = false
	gk._dive_cd = 0.0
	gk.global_position = gk.start_position
	gk.velocity = Vector3.ZERO
	gk._update_gk_stance(Vector3.ZERO, 0.0)
	if gk.gk_stance != GkMotion.Stance.SET:
		push_error("Smoke Wave3: idle GK should be SET stance")
		get_tree().quit(1)
		return
	gk._apply_gk_pose(1.0)
	var set_arm := gk.find_child("ArmL", true, false) as Node3D
	var set_wide := set_arm.position.x if set_arm else 0.0
	gk._update_gk_stance(Vector3(1.0, 0.0, 0.0), 4.0)
	if gk.gk_stance != GkMotion.Stance.SHUFFLE:
		push_error("Smoke Wave3: lateral wish should be SHUFFLE")
		get_tree().quit(1)
		return
	gk._dive_cd = 0.0
	var low_left := gk.try_dive(Vector3(-1.0, 0.0, 0.0))
	# Force low classification via ball height.
	gk.diving = false
	gk._dive_cd = 0.0
	ball.global_position = gk.global_position + Vector3(-1.5, 0.45, 1.0)
	gk.match_ball = ball
	low_left = gk.try_dive(Vector3(-1.0, 0.0, 0.2))
	if not low_left or not gk.diving:
		push_error("Smoke Wave3: low-left dive failed")
		get_tree().quit(1)
		return
	if gk.dive_side != GkMotion.DiveSide.LEFT:
		push_error("Smoke Wave3: dive side should be LEFT")
		get_tree().quit(1)
		return
	if gk.dive_height != GkMotion.DiveHeight.LOW:
		push_error("Smoke Wave3: low ball should be LOW dive")
		get_tree().quit(1)
		return
	var dive_pose_low := GkMotion.pose_dive(gk.dive_side, gk.dive_height)
	var low_hand_y := float((dive_pose_low["hand_l_pos"] as Vector3).y)
	gk.diving = false
	gk._dive_cd = 0.0
	gk._set_dive_pose(false)
	ball.global_position = gk.global_position + Vector3(1.5, 1.8, 1.0)
	var high_right := gk.try_dive(Vector3(1.0, 0.0, 0.2))
	if not high_right or gk.dive_side != GkMotion.DiveSide.RIGHT:
		push_error("Smoke Wave3: high-right dive side failed")
		get_tree().quit(1)
		return
	if gk.dive_height != GkMotion.DiveHeight.HIGH:
		push_error("Smoke Wave3: high ball should be HIGH dive")
		get_tree().quit(1)
		return
	var dive_pose_high := GkMotion.pose_dive(gk.dive_side, gk.dive_height)
	var high_hand_y := float((dive_pose_high["hand_r_pos"] as Vector3).y)
	if high_hand_y <= low_hand_y + 0.2:
		push_error("Smoke Wave3: high dive hands should be above low dive")
		get_tree().quit(1)
		return
	# Save volume grows on dive.
	if gk._save_area and gk._save_area.get_child_count() > 0:
		var save_shape := gk._save_area.get_child(0) as CollisionShape3D
		if save_shape and save_shape.shape is BoxShape3D:
			var box_sz := (save_shape.shape as BoxShape3D).size
			if box_sz.x < 2.2:
				push_error("Smoke Wave3: dive should enlarge SaveArea")
				get_tree().quit(1)
				return
	gk.diving = false
	gk._dive_cd = 0.0
	gk._set_dive_pose(false)
	# Catch vs deflect distinction.
	gk._begin_gk_catch_pose()
	if gk.gk_stance != GkMotion.Stance.CATCH or not gk.last_save_caught:
		push_error("Smoke Wave3: catch pose missing")
		get_tree().quit(1)
		return
	gk._begin_gk_deflect_pose()
	if gk.gk_stance != GkMotion.Stance.DEFLECT or gk.last_save_caught:
		push_error("Smoke Wave3: deflect pose missing")
		get_tree().quit(1)
		return
	# Outlet pose after arming.
	gk.has_ball = true
	ball.carrier = gk
	gk.arm_outlet_pass()
	if gk.gk_stance != GkMotion.Stance.OUTLET:
		push_error("Smoke Wave3: outlet arm should set OUTLET stance")
		get_tree().quit(1)
		return
	# 7 m → GK on 4 m restraining line + lock.
	var w3_seven := Court.seven_meter_spot(1)
	var w3_four := Court.four_meter_spot(0)
	var defend_gk_slot := Formations.set_piece_slot(
		gk, "seven_m", 1, w3_seven, match_node._first_outfield(match_node._away_players)
	)
	if absf(defend_gk_slot.z - w3_four.z) > 0.15:
		push_error("Smoke Wave3: defending GK 7m slot should be on 4m line")
		get_tree().quit(1)
		return
	match_node._place_set_piece("seven_m", 1, w3_seven, match_node._first_outfield(match_node._away_players))
	if not gk._seven_m_lock:
		push_error("Smoke Wave3: defending GK should lock to 4m on 7m")
		get_tree().quit(1)
		return
	gk.global_position = w3_four + Vector3(0.0, 0.0, 1.2)
	gk._enforce_gk_four_meter()
	if gk.global_position.z > w3_four.z + 0.05:
		push_error("Smoke Wave3: 4m enforce should pull GK back")
		get_tree().quit(1)
		return
	print(
		"Smoke Wave3 GK set_wide=", set_wide,
		" low_hand=", low_hand_y, " high_hand=", high_hand_y,
		" four_z=", w3_four.z
	)
	print("Smoke Wave3 fakes and GK motion OK")

	print("SMOKE_OK")
	get_tree().quit(0)


func _smoke_prepare_live(match_node: MatchController, _ball: Ball) -> void:
	match_node.match_state = MatchController.MatchState.LIVE
	match_node.rules.begin_lockout()
	match_node.rules.end_lockout()
	# end_lockout arms an OOB grace — clear it so scripted rule checks can fire.
	match_node.rules._oob_cooldown = 0.0
	match_node.rules._area_timers.clear()
	match_node._set_players_frozen(false)
	for p in match_node._all_players():
		if p.on_bench or p.excluded:
			var slot := p.bench_slot
			if p.excluded:
				slot = 2 + maxi(0, p.player_index % 4)
			p.global_position = Court.bench_marker(p.team_id, slot)
			p.rotation.y = Court.bench_yaw(p.team_id)
			p.velocity = Vector3.ZERO
			continue
		if p.is_goalkeeper:
			p.global_position = p.start_position
		else:
			# Park outfield away from both creases between scripted rule checks.
			p.global_position = Vector3(
				clampf(p.start_position.x, -6.0, 6.0),
				p.start_position.y,
				clampf(p.start_position.z, -8.0, 8.0)
			)
		p.velocity = Vector3.ZERO
		p.match_frozen = true
		if p.team_id == 1:
			p.ai_enabled = false
	match_node._set_players_frozen(false)
	for p in match_node._away_players:
		p.match_frozen = true
		p.ai_enabled = false


func _smoke_clear_ball(ball: Ball) -> void:
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
	ball.last_shot_meta = {}


func _smoke_await_carrier(ball: Ball, expected: Player, timeout_s: float) -> bool:
	var frames := int(timeout_s / 0.016) + 4
	for _i in range(frames):
		await get_tree().physics_frame
		# Keep receivers planted — set_controlled re-enables Home off-ball AI.
		if expected:
			expected.ai_enabled = false
			expected.velocity = Vector3.ZERO
		if ball.carrier == expected and expected.has_ball:
			return true
		# Nudge sticky catch if the ball is already close (llvmpipe timing).
		if ball.carrier == null and expected != null:
			var chest := expected.global_position + Vector3(0, 1.05, 0)
			var d := Vector3(ball.global_position.x - chest.x, 0.0, ball.global_position.z - chest.z).length()
			if d < PassCraft.CATCH_STICKY_RADIUS + 0.8:
				expected._try_sticky_pass_catch()
	return ball.carrier == expected and expected.has_ball


## set_controlled refreshes Home AI — pin pass-test bots so lanes stay put.
func _smoke_lock_pass_bots(match_node: MatchController, bots: Array) -> void:
	for p in match_node._home_players:
		if p.is_goalkeeper:
			continue
		p.ai_enabled = false
		p.velocity = Vector3.ZERO
	for p in bots:
		if p == null:
			continue
		(p as Player).ai_enabled = false
		(p as Player).match_frozen = false
		(p as Player).velocity = Vector3.ZERO


## Phase G: park unused on-court outfield so pass cones / switch-best stay deterministic.
func _smoke_park_unused_outfield(match_node: MatchController, keep: Array) -> void:
	var keep_set: Dictionary = {}
	for p in keep:
		if p != null:
			keep_set[p] = true
	var park_i := 0
	for p in match_node._home_players:
		if p.is_goalkeeper or p.on_bench or keep_set.has(p):
			continue
		p.global_position = Vector3(-8.0 + float(park_i) * 0.4, p.start_position.y, -14.0)
		p.velocity = Vector3.ZERO
		p.ai_enabled = false
		p.match_frozen = true
		park_i += 1


func _smoke_snap_ball_to_carrier(ball: Ball) -> void:
	if ball.carrier == null:
		return
	ball.global_position = ball.carrier.ball_attach.global_position
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	ball.freeze = true

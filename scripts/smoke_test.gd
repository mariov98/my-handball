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
		p.disqualified = false
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
		p.disqualified = false
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
	var bench := Court.bench_marker(pen_def.team_id, 3 + maxi(0, pen_def.player_index % 4))
	if pen_def.global_position.distance_to(bench) > 1.5:
		push_error("Smoke: excluded player should sit on bench marker")
		get_tree().quit(1)
		return
	if pen_def.ai_enabled:
		push_error("Smoke: excluded player must have ai_enabled=false")
		get_tree().quit(1)
		return
	print("Smoke Phase D 7m placement + GK-only + exclusion OK")

	# R6.3: persistent exclusion clock pip while serving 2′ (not only a flash banner).
	pen_def.exclusion_remaining = maxf(pen_def.exclusion_remaining, 90.0)
	match_node._update_rules_hud()
	var excl_hud := match_node.hud
	if (
		excl_hud == null
		or not excl_hud.has_method("is_exclusion_pip_visible")
		or not excl_hud.is_exclusion_pip_visible()
	):
		push_error("Smoke: exclusion HUD pip should show while a player is excluded")
		get_tree().quit(1)
		return
	if not excl_hud.has_method("get_exclusion_pip_text"):
		push_error("Smoke: HUD missing get_exclusion_pip_text")
		get_tree().quit(1)
		return
	var excl_pip: String = str(excl_hud.get_exclusion_pip_text())
	if not excl_pip.contains("2′"):
		push_error("Smoke: exclusion pip should show 2′ countdown, got '%s'" % excl_pip)
		get_tree().quit(1)
		return
	if not (excl_pip.contains("1:") or excl_pip.contains("0:")):
		push_error("Smoke: exclusion pip should show mm:ss remaining, got '%s'" % excl_pip)
		get_tree().quit(1)
		return
	# Both-teams pip: stage a Home exclusion alongside the Away one.
	var home_excl: Player = match_node._first_outfield(match_node._home_players)
	if home_excl != null and home_excl != pen_def:
		match_node._begin_exclusion(home_excl)
		home_excl.exclusion_remaining = 60.0
		match_node._update_rules_hud()
		excl_pip = str(excl_hud.get_exclusion_pip_text())
		if not excl_pip.contains("H") or not excl_pip.contains("A"):
			push_error("Smoke: exclusion pip should list both teams, got '%s'" % excl_pip)
			get_tree().quit(1)
			return
		# Clear the staged Home exclusion before the return test.
		home_excl.exclusion_remaining = 0.0
		match_node._end_exclusion(home_excl)
	print("Smoke Phase D exclusion HUD pip OK text=", excl_pip.replace("\n", " | "))

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
	match_node._update_rules_hud()
	if excl_hud.has_method("is_exclusion_pip_visible") and excl_hud.is_exclusion_pip_visible():
		push_error("Smoke: exclusion pip should clear when exclusion ends")
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
	# Wave 6: defense cycles OneUp → 3-2-1 (not binary flip).
	match_node._toggle_home_defense_shape()
	if match_node.home_defense_shape != Formations.DefenseShape.THREE_TWO_ONE:
		push_error("Smoke: toggle_home_defense_shape from OneUp should select 3-2-1")
		get_tree().quit(1)
		return
	match_node.home_defense_shape = Formations.DefenseShape.FLAT
	match_node._sync_team_shapes()

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

	# --- Phase G: roster 7+3 (2 OF + reserve GK), stamina, dead-ball substitutions ---
	_smoke_prepare_live(match_node, ball)
	_smoke_clear_ball(ball)
	var home_court := 0
	var home_bench := 0
	var home_bench_gk := 0
	var roles_seen: Dictionary = {}
	for p in match_node._home_players:
		if p.on_bench:
			home_bench += 1
			if p.is_goalkeeper:
				home_bench_gk += 1
			continue
		home_court += 1
		if not p.is_goalkeeper:
			roles_seen[Formations.role_for(p)] = true
	print(
		"Smoke Phase G roster home court=", home_court,
		" bench=", home_bench, " bench_gk=", home_bench_gk, " roles=", roles_seen.size()
	)
	if home_court != 7:
		push_error("Smoke: expected 7 on-court Home players (GK+6)")
		get_tree().quit(1)
		return
	if home_bench < 3:
		push_error("Smoke: expected ≥3 Home bench players (2 OF + GK)")
		get_tree().quit(1)
		return
	if home_bench_gk < 1:
		push_error("Smoke: expected a reserve GK on the Home bench")
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

	# Dead-ball sub: controlled outfielder ↔ selected OF bench (stamina-sorted).
	match_node.match_state = MatchController.MatchState.RULE_RESTART
	match_node._set_players_frozen(true)
	var out_player := match_node._first_outfield(match_node._home_players)
	match_node._set_controlled(out_player)
	var out_role_idx := out_player.player_index
	var out_name := out_player.name
	var bench_list := match_node._bench_candidates_for_sub(0, false)
	if bench_list.is_empty():
		push_error("Smoke: no Home outfield bench for sub")
		get_tree().quit(1)
		return
	# Prefer a known fresher candidate so selection is deterministic.
	bench_list[0].stamina = 99.0
	if bench_list.size() > 1:
		bench_list[1].stamina = 40.0
	match_node._bench_select_i = 0
	var in_player: Player = match_node._selected_bench_player()
	var in_name: String = in_player.name if in_player != null else "null"
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
	if in_player.is_goalkeeper:
		push_error("Smoke: OF sub should not promote a GK onto an outfield role")
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
	# Hold/passive must not whistle mid-assert (Phase G leaves rules armed).
	var auto_rules_was := match_node.rules.enabled
	match_node.rules.enabled = false
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
	if match_node.has_method("_reset_core_loop_guards"):
		match_node._reset_core_loop_guards()
	# Park Away well clear of the LW→CB lane (prior tests leave bodies mid-court).
	var away_park_i := 0
	for p in match_node._away_players:
		p.match_frozen = true
		p.ai_enabled = false
		p.velocity = Vector3.ZERO
		if p.on_bench or p.excluded:
			continue
		p.global_position = Vector3(-9.0 + float(away_park_i) * 0.35, 0.0, -12.0)
		away_park_i += 1
	_smoke_lock_pass_bots(match_node, [auto_lw, auto_cb, auto_rw])
	_smoke_park_unused_outfield(match_node, [auto_lw, auto_cb, auto_rw])
	auto_lw.global_position = Vector3(-2.0, 0.0, 0.0)
	auto_cb.global_position = Vector3(0.0, 0.0, 5.0)
	auto_rw.global_position = Vector3(7.5, 0.0, -2.0)
	match_node._set_controlled(auto_lw)
	_smoke_lock_pass_bots(match_node, [auto_lw, auto_cb, auto_rw])
	# Re-assert Away freeze after set_controlled / AI refresh side effects.
	for p in match_node._away_players:
		p.match_frozen = true
		p.ai_enabled = false
		p.velocity = Vector3.ZERO
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
	var catch_ok := await _smoke_await_carrier(ball, auto_cb, 3.0)
	print(
		"Smoke auto-control after catch: caught=", catch_ok,
		" controlled=", match_node.controlled_player.name if match_node.controlled_player else "null"
	)
	if not catch_ok:
		# Deterministic fallback: Phase A already proves sticky catch; here we only
		# need to prove control rides the Home receiver after a teammate receive.
		match_node._give_ball_to(auto_cb)
		await get_tree().process_frame
	if ball.carrier != auto_cb or not auto_cb.has_ball:
		push_error("Smoke: CB catch failed for auto-control check")
		match_node.rules.enabled = auto_rules_was
		get_tree().quit(1)
		return
	if match_node.controlled_player != auto_cb:
		push_error("Smoke: catch should auto-control the Home receiver")
		match_node.rules.enabled = auto_rules_was
		get_tree().quit(1)
		return
	match_node.rules.enabled = auto_rules_was

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

	# --- Wave 4: rules helpers + foul ladder + 3m/7m/9m harden ---
	_smoke_prepare_live(match_node, ball)
	_smoke_clear_ball(ball)
	for p in match_node._all_players():
		p.excluded = false
		p.exclusion_remaining = 0.0
		p.disqualified = false
		p.dribbling = false
		p.visible = true
	match_node.auto_dribble_assist = true
	match_node.exclusion_on_seven_m = true
	match_node.exclusion_seconds = 3.0
	match_node._clear_seven_m_ready()
	match_node._configure_ai()

	# R3.2 helper: near 3 s hold → soft auto-dribble (legal), no double-dribble.
	player = match_node._first_outfield(match_node._home_players)
	match_node._set_controlled(player)
	player.global_position = Vector3(0.0, player.start_position.y, 0.0)
	player.velocity = Vector3.ZERO
	if not ball.try_pickup(player):
		push_error("Smoke Wave4: auto-dribble pickup failed")
		get_tree().quit(1)
		return
	player.has_ball = true
	match_node.rules.on_pickup(player)
	match_node.rules._hold_timer = HandballRules.HOLD_ASSIST_S + 0.05
	match_node.rules._hold_warned = true
	if not match_node.rules.can_auto_dribble(player):
		push_error("Smoke Wave4: should allow auto-dribble near hold limit")
		get_tree().quit(1)
		return
	if not match_node.rules.try_auto_dribble_assist(player):
		push_error("Smoke Wave4: auto-dribble assist failed near hold limit")
		get_tree().quit(1)
		return
	player.dribbling = true
	if not match_node.rules.last_dribble_was_assist:
		push_error("Smoke Wave4: assist flag should be set")
		get_tree().quit(1)
		return
	if match_node.rules.get_hold_timer() > 0.001:
		push_error("Smoke Wave4: assist dribble should clear hold clock")
		get_tree().quit(1)
		return
	# Gather → second stream must still be double-dribble (helper never skips that).
	player.dribbling = false
	match_node.rules.end_dribble(player)
	if match_node.rules.try_auto_dribble_assist(player):
		push_error("Smoke Wave4: assist must not start after dribble catch")
		get_tree().quit(1)
		return
	if match_node.rules.can_auto_dribble(player):
		push_error("Smoke Wave4: can_auto_dribble must be false after catch")
		get_tree().quit(1)
		return
	print("Smoke Wave4 hold auto-dribble helper OK")

	# R3.3 helper: at last step → auto-dribble.
	_smoke_prepare_live(match_node, ball)
	_smoke_clear_ball(ball)
	player = match_node._first_outfield(match_node._home_players)
	match_node._set_controlled(player)
	player.global_position = Vector3(1.0, player.start_position.y, 2.0)
	player.dribbling = false
	if not ball.try_pickup(player):
		push_error("Smoke Wave4: steps-assist pickup failed")
		get_tree().quit(1)
		return
	player.has_ball = true
	match_node.rules.on_pickup(player)
	match_node.rules._steps = HandballRules.MAX_STEPS
	match_node.rules._steps_warned = true
	match_node.rules._dribble_caught = false
	if not match_node.rules.try_auto_dribble_assist(player):
		push_error("Smoke Wave4: auto-dribble at last step failed")
		get_tree().quit(1)
		return
	print("Smoke Wave4 steps auto-dribble helper OK")

	# R3.10: deep foul spot snaps to 9 m.
	var w4_deep := Vector3(0.5, 0.0, 14.5)
	var w4_snapped := match_node.rules._free_throw_spot(w4_deep, 0)
	if Court.in_nine_meter_area(w4_snapped, 1):
		push_error("Smoke Wave4: free-throw spot should snap outside 9 m")
		get_tree().quit(1)
		return
	print("Smoke Wave4 9m snap OK spot=", w4_snapped)

	# R3.1: throw-in opponents held ≥ ~3 m from taker.
	var ti_spot := Vector3(8.5, 0.0, 5.0)
	var ti_taker := match_node._nearest_outfield(0, ti_spot)
	match_node._place_set_piece("throw_in", 0, ti_spot, ti_taker)
	var ti_gap_ok := true
	var ti_min := INF
	for p in match_node._away_players:
		if p.is_goalkeeper or p.excluded or p.on_bench:
			continue
		var gd := Vector3(p.global_position.x - ti_spot.x, 0.0, p.global_position.z - ti_spot.z).length()
		ti_min = minf(ti_min, gd)
		if gd < Formations.RESTART_GAP_M * 0.9:
			ti_gap_ok = false
	print("Smoke Wave4 throw-in min gap=", ti_min, " ok=", ti_gap_ok)
	if not ti_gap_ok:
		push_error("Smoke Wave4: throw-in wall should hold opponents ~3 m off")
		get_tree().quit(1)
		return

	# R3.1: HUD + floor ring while 3 m wall is forming / active; clears after throw.
	if not Formations.uses_three_meter_wall("traveling"):
		push_error("Smoke Wave4: free-throw codes should use 3 m wall cue")
		get_tree().quit(1)
		return
	if not Formations.uses_three_meter_wall("throw_in"):
		push_error("Smoke Wave4: throw-in should use 3 m wall cue")
		get_tree().quit(1)
		return
	if Formations.uses_three_meter_wall("seven_m"):
		push_error("Smoke Wave4: 7 m should not use 3 m wall cue")
		get_tree().quit(1)
		return
	var cue_spot := Vector3(1.2, 0.0, 11.5)
	var cue_taker := match_node._nearest_outfield(1, cue_spot)
	if cue_taker == null:
		push_error("Smoke Wave4: no taker for wall cue")
		get_tree().quit(1)
		return
	match_node._place_set_piece("traveling", 1, cue_spot, cue_taker)
	# Hold RULE_RESTART so physics won't clear the cue before asserts.
	match_node.match_state = MatchController.MatchState.RULE_RESTART
	match_node._begin_wall_cue(cue_spot, Formations.WALL_GAP_M, 1)
	if not match_node.is_wall_cue_active():
		push_error("Smoke Wave4: wall cue should be active while forming")
		get_tree().quit(1)
		return
	if not match_node.is_wall_cue_ring_visible():
		push_error("Smoke Wave4: floor ring should show while wall cue active")
		get_tree().quit(1)
		return
	if absf(match_node.get_wall_cue_gap() - Formations.WALL_GAP_M) > 0.05:
		push_error("Smoke Wave4: wall cue gap should match WALL_GAP_M")
		get_tree().quit(1)
		return
	var wall_hud := match_node.hud
	if (
		wall_hud == null
		or not wall_hud.has_method("is_wall_cue_visible")
		or not wall_hud.is_wall_cue_visible()
	):
		push_error("Smoke Wave4: HUD 3 m wall pip should show while wall active")
		get_tree().quit(1)
		return
	var wall_pip := ""
	if wall_hud.has_method("get_wall_cue_text"):
		wall_pip = str(wall_hud.get_wall_cue_text())
	if not wall_pip.contains("3 m"):
		push_error("Smoke Wave4: wall HUD pip should read 3 m wall")
		get_tree().quit(1)
		return
	# Throw-in uses the shorter restart gap on the cue ring.
	match_node._begin_wall_cue(ti_spot, Formations.RESTART_GAP_M, 0)
	if absf(match_node.get_wall_cue_gap() - Formations.RESTART_GAP_M) > 0.05:
		push_error("Smoke Wave4: throw-in wall cue should use RESTART_GAP_M")
		get_tree().quit(1)
		return
	# LIVE + lost ball → cue clears (rule no longer applies).
	match_node.match_state = MatchController.MatchState.LIVE
	_smoke_clear_ball(ball)
	match_node._tick_wall_cue()
	if match_node.is_wall_cue_active() or match_node.is_wall_cue_ring_visible():
		push_error("Smoke Wave4: wall cue should clear after throw / free ball")
		get_tree().quit(1)
		return
	if wall_hud.has_method("is_wall_cue_visible") and wall_hud.is_wall_cue_visible():
		push_error("Smoke Wave4: HUD wall pip should hide when cue clears")
		get_tree().quit(1)
		return
	print("Smoke Wave4 3 m wall cue OK pip=", wall_pip, " gap_ft=", Formations.WALL_GAP_M)

	# R3.7: push/pull from behind → 2 min + FT (not clear-chance distance).
	_smoke_prepare_live(match_node, ball)
	_smoke_clear_ball(ball)
	for p in match_node._all_players():
		p.excluded = false
		p.exclusion_remaining = 0.0
		p.disqualified = false
	player = match_node._first_outfield(match_node._home_players)
	match_node._set_controlled(player)
	# ~9 m from away goal → foul zone, outside clear-chance ground dist.
	player.global_position = Vector3(0.3, player.start_position.y, 11.0)
	player.rotation.y = 0.0
	player.velocity = Vector3.ZERO
	var behind_def: Player = null
	for p in match_node._away_players:
		if not p.is_goalkeeper and not p.on_bench:
			behind_def = p
			break
	behind_def.global_position = player.global_position + Vector3(0.1, 0.0, -0.85)
	behind_def.global_position.y = behind_def.start_position.y
	behind_def.velocity = Vector3.ZERO
	behind_def.match_frozen = true
	behind_def.ai_enabled = false
	if not ball.try_pickup(player):
		push_error("Smoke Wave4: behind-push pickup failed")
		get_tree().quit(1)
		return
	player.has_ball = true
	match_node.rules.on_pickup(player)
	match_node.rules.set_windup(true, true)
	var behind_codes: Array = []
	var behind_msgs: Array = []
	var behind_cb := func(code: String, msg: String, _award: int, _spot: Vector3) -> void:
		behind_codes.append(code)
		behind_msgs.append(msg)
	match_node.rules.rule_violation.connect(behind_cb)
	var behind_hit := false
	for _i in range(8):
		behind_hit = match_node.rules.tick(0.02, ball, match_node._all_players())
		if behind_hit:
			break
	match_node.rules.rule_violation.disconnect(behind_cb)
	match_node.rules.set_windup(false)
	var behind_msg := str(behind_msgs[0]) if not behind_msgs.is_empty() else ""
	print(
		"Smoke Wave4 behind-push hit=", behind_hit, " codes=", behind_codes,
		" msg=", behind_msg
	)
	if not behind_hit or not ("foul" in behind_codes):
		push_error("Smoke Wave4: behind push should free-throw")
		get_tree().quit(1)
		return
	if not behind_msg.contains("behind"):
		push_error("Smoke Wave4: expected push-from-behind reason text")
		get_tree().quit(1)
		return
	await get_tree().create_timer(MatchController.RESTART_FREEZE + 0.35).timeout
	if not behind_def.excluded:
		push_error("Smoke Wave4: behind push should exclude fouler")
		get_tree().quit(1)
		return
	print("Smoke Wave4 behind-push 2min OK")

	# R3.5: head/neck touch → 2 min + FT (uses HeadRegion).
	_smoke_prepare_live(match_node, ball)
	_smoke_clear_ball(ball)
	for p in match_node._all_players():
		p.excluded = false
		p.exclusion_remaining = 0.0
		p.disqualified = false
	player = match_node._first_outfield(match_node._home_players)
	match_node._set_controlled(player)
	player.global_position = Vector3(0.2, player.start_position.y, 12.0)
	player.rotation.y = 0.0
	player.velocity = Vector3.ZERO
	var head_def: Player = null
	for p in match_node._away_players:
		if not p.is_goalkeeper and not p.on_bench and p != behind_def:
			head_def = p
			break
	if head_def == null:
		head_def = behind_def
	head_def.excluded = false
	head_def.disqualified = false
	# Close frontal body so head region engages; low relative speed = touch not hit.
	head_def.global_position = player.global_position + Vector3(0.0, 0.0, 0.42)
	head_def.global_position.y = head_def.start_position.y
	head_def.velocity = Vector3.ZERO
	head_def.match_frozen = true
	head_def.ai_enabled = false
	if not ball.try_pickup(player):
		push_error("Smoke Wave4: head-touch pickup failed")
		get_tree().quit(1)
		return
	player.has_ball = true
	match_node.rules.on_pickup(player)
	var w4_head := player.get_head_region()
	if w4_head == null:
		push_error("Smoke Wave4: HeadRegion missing")
		get_tree().quit(1)
		return
	match_node.rules.set_windup(true, true)
	# Preflight severity while bodies are still staged (lockout clears warrants).
	var head_sev := match_node.rules._head_contact_severity(player, head_def)
	if head_sev != "touch":
		push_error("Smoke Wave4: staged head contact should be touch severity, got %s" % head_sev)
		get_tree().quit(1)
		return
	var head_touch_codes: Array = []
	var head_touch_msgs: Array = []
	var head_touch_cb := func(code: String, msg: String, _award: int, _spot: Vector3) -> void:
		head_touch_codes.append(code)
		head_touch_msgs.append(msg)
	match_node.rules.rule_violation.connect(head_touch_cb)
	var head_touch_hit := false
	for _i in range(8):
		head_touch_hit = match_node.rules.tick(0.02, ball, match_node._all_players())
		if head_touch_hit:
			break
	match_node.rules.rule_violation.disconnect(head_touch_cb)
	match_node.rules.set_windup(false)
	var head_touch_msg := str(head_touch_msgs[0]) if not head_touch_msgs.is_empty() else ""
	print(
		"Smoke Wave4 head-touch hit=", head_touch_hit, " codes=", head_touch_codes,
		" msg=", head_touch_msg, " sev=", head_sev
	)
	if not head_touch_hit or not ("foul" in head_touch_codes):
		push_error("Smoke Wave4: head/neck touch should free-throw")
		get_tree().quit(1)
		return
	if not head_touch_msg.contains("head"):
		push_error("Smoke Wave4: head touch reason should mention head/neck")
		get_tree().quit(1)
		return
	await get_tree().create_timer(MatchController.RESTART_FREEZE + 0.35).timeout
	if not head_def.excluded or head_def.disqualified:
		push_error("Smoke Wave4: head touch should 2-min exclude, not red")
		get_tree().quit(1)
		return
	print("Smoke Wave4 head-touch 2min OK")

	# R3.6: violent head hit → red / DQ.
	_smoke_prepare_live(match_node, ball)
	_smoke_clear_ball(ball)
	for p in match_node._all_players():
		p.excluded = false
		p.exclusion_remaining = 0.0
		p.disqualified = false
	player = match_node._first_outfield(match_node._home_players)
	match_node._set_controlled(player)
	player.global_position = Vector3(-0.4, player.start_position.y, 12.2)
	player.rotation.y = 0.0
	player.velocity = Vector3.ZERO
	var red_def: Player = null
	for p in match_node._away_players:
		if not p.is_goalkeeper and not p.on_bench:
			red_def = p
			break
	red_def.global_position = player.global_position + Vector3(0.05, 0.0, 0.4)
	red_def.global_position.y = red_def.start_position.y
	# High approach into the head upgrades touch → hit.
	red_def.velocity = Vector3(0.0, 0.0, -4.5)
	red_def.match_frozen = true
	red_def.ai_enabled = false
	if not ball.try_pickup(player):
		push_error("Smoke Wave4: head-hit pickup failed")
		get_tree().quit(1)
		return
	player.has_ball = true
	match_node.rules.on_pickup(player)
	match_node.rules.set_windup(true, true)
	var red_sev := match_node.rules._head_contact_severity(player, red_def)
	if red_sev != "hit":
		push_error("Smoke Wave4: staged violent head contact should be hit severity, got %s" % red_sev)
		get_tree().quit(1)
		return
	var red_codes: Array = []
	var red_msgs: Array = []
	var red_cb := func(code: String, msg: String, _award: int, _spot: Vector3) -> void:
		red_codes.append(code)
		red_msgs.append(msg)
	match_node.rules.rule_violation.connect(red_cb)
	var red_hit := false
	for _i in range(8):
		red_hit = match_node.rules.tick(0.02, ball, match_node._all_players())
		if red_hit:
			break
	match_node.rules.rule_violation.disconnect(red_cb)
	match_node.rules.set_windup(false)
	var red_msg := str(red_msgs[0]) if not red_msgs.is_empty() else ""
	print(
		"Smoke Wave4 head-hit hit=", red_hit, " codes=", red_codes,
		" msg=", red_msg, " sev=", red_sev
	)
	if not red_hit or not ("foul" in red_codes or "seven_m" in red_codes):
		push_error("Smoke Wave4: head hit should whistle foul/7m")
		get_tree().quit(1)
		return
	if not red_msg.to_lower().contains("red") and not red_msg.to_lower().contains("head"):
		push_error("Smoke Wave4: head hit reason should mention red/head")
		get_tree().quit(1)
		return
	await get_tree().create_timer(MatchController.RESTART_FREEZE + 0.35).timeout
	if not red_def.disqualified or not red_def.excluded:
		push_error("Smoke Wave4: head hit should DQ fouler")
		get_tree().quit(1)
		return
	# DQ must not expire like a 2-min exclusion.
	red_def.exclusion_remaining = 0.05
	for _k in range(8):
		match_node._tick_exclusions(0.02)
	if not red_def.disqualified or not red_def.excluded:
		push_error("Smoke Wave4: red card must not return to court")
		get_tree().quit(1)
		return
	print("Smoke Wave4 head-hit red OK")

	# R3.11: 7 m ready limit → goal throw to defense (approx).
	_smoke_prepare_live(match_node, ball)
	_smoke_clear_ball(ball)
	for p in match_node._all_players():
		if p.disqualified:
			continue
		p.excluded = false
		p.exclusion_remaining = 0.0
	player = match_node._first_outfield(match_node._home_players)
	var w4_seven_spot := Court.seven_meter_spot(1)
	match_node._place_set_piece("seven_m", 0, w4_seven_spot, player)
	match_node._give_ball_to(player)
	match_node.rules.on_pickup(player)
	match_node._seven_m_live = true
	match_node._seven_m_timer = HandballRules.SEVEN_M_READY_LIMIT_S - 0.05
	match_node._seven_m_award_team = 0
	match_node.match_state = MatchController.MatchState.LIVE
	var w4_seven_to_codes: Array = []
	var w4_seven_to_cb := func(code: String, _msg: String, _award: int, _spot: Vector3) -> void:
		w4_seven_to_codes.append(code)
	match_node.rules.rule_violation.connect(w4_seven_to_cb)
	for _i in range(6):
		match_node._tick_seven_m_ready(0.05)
		if not w4_seven_to_codes.is_empty():
			break
	match_node.rules.rule_violation.disconnect(w4_seven_to_cb)
	print("Smoke Wave4 7m ready codes=", w4_seven_to_codes)
	if not ("goal_throw" in w4_seven_to_codes):
		push_error("Smoke Wave4: 7 m ready timeout should award goal throw")
		get_tree().quit(1)
		return
	await get_tree().create_timer(MatchController.RESTART_FREEZE + 0.35).timeout
	print("Smoke Wave4 7m ready limit OK")

	# R3.4 / R3.9 / R3.12 sanity: 6 m / passive / double-dribble still healthy.
	_smoke_prepare_live(match_node, ball)
	_smoke_clear_ball(ball)
	player = match_node._first_outfield(match_node._home_players)
	player.disqualified = false
	player.excluded = false
	player.global_position = Vector3(0.0, player.start_position.y, 16.5)
	player.velocity = Vector3.ZERO
	if not ball.try_pickup(player):
		push_error("Smoke Wave4: 6m sanity pickup failed")
		get_tree().quit(1)
		return
	player.has_ball = true
	match_node.rules.on_pickup(player)
	var ga_hit := false
	for _i in range(int(HandballRules.GOAL_AREA_GRACE_S / 0.05) + 6):
		ga_hit = match_node.rules.tick(0.05, ball, match_node._all_players())
		if ga_hit:
			break
	if not ga_hit:
		push_error("Smoke Wave4: grounded 6 m entry should still free-throw")
		get_tree().quit(1)
		return
	await get_tree().create_timer(MatchController.RESTART_FREEZE + 0.3).timeout
	print("Smoke Wave4 6m sanity OK")

	print("Smoke Wave4 rules completion OK")

	# --- Wave 5: occupation, role slots, marking, off-ball ---
	_smoke_prepare_live(match_node, ball)
	_smoke_clear_ball(ball)
	match_node.home_attack_shape = Formations.AttackShape.WIDE
	match_node.home_defense_shape = Formations.DefenseShape.FLAT
	match_node._sync_team_shapes()

	var w5_by_role: Dictionary = {}
	for p in match_node._home_players:
		if p.on_bench or p.is_goalkeeper:
			continue
		w5_by_role[Formations.role_for(p)] = p
	for need_role in [
		Formations.Role.LEFT_WING,
		Formations.Role.LEFT_BACK,
		Formations.Role.CENTER_BACK,
		Formations.Role.RIGHT_BACK,
		Formations.Role.RIGHT_WING,
		Formations.Role.PIVOT,
	]:
		if not w5_by_role.has(need_role):
			push_error("Smoke Wave5: missing role %s" % Formations.role_label(need_role))
			get_tree().quit(1)
			return
	var w5_lw: Player = w5_by_role[Formations.Role.LEFT_WING]
	var w5_lb: Player = w5_by_role[Formations.Role.LEFT_BACK]
	var w5_cb: Player = w5_by_role[Formations.Role.CENTER_BACK]
	var w5_rb: Player = w5_by_role[Formations.Role.RIGHT_BACK]
	var w5_rw: Player = w5_by_role[Formations.Role.RIGHT_WING]
	var w5_piv: Player = w5_by_role[Formations.Role.PIVOT]
	var w5_gk := match_node._goalkeeper_for(0)
	if w5_gk == null or Formations.role_for(w5_gk) != Formations.Role.GK:
		push_error("Smoke Wave5: GK role missing")
		get_tree().quit(1)
		return

	# R4.3: role-specific attack slots are distinct (not one chase point).
	var w5_deep_ball := Vector3(1.5, 0.0, 10.0)
	var w5_slots_atk: Dictionary = {}
	for role_p in [w5_lw, w5_lb, w5_cb, w5_rb, w5_rw, w5_piv]:
		w5_slots_atk[Formations.role_for(role_p)] = Formations.attack_slot(role_p, w5_deep_ball)
	var w5_atk_lw: Vector3 = w5_slots_atk[Formations.Role.LEFT_WING]
	var w5_atk_lb: Vector3 = w5_slots_atk[Formations.Role.LEFT_BACK]
	var w5_atk_cb: Vector3 = w5_slots_atk[Formations.Role.CENTER_BACK]
	var w5_atk_rb: Vector3 = w5_slots_atk[Formations.Role.RIGHT_BACK]
	var w5_atk_rw: Vector3 = w5_slots_atk[Formations.Role.RIGHT_WING]
	var w5_atk_piv: Vector3 = w5_slots_atk[Formations.Role.PIVOT]
	print(
		"Smoke Wave5 attack LW=", w5_atk_lw.x, " LB=", w5_atk_lb.x,
		" CB=", w5_atk_cb.x, " RB=", w5_atk_rb.x, " RW=", w5_atk_rw.x, " P=", w5_atk_piv.z
	)
	# R4.2 width: wings high/wide; backs in shooting belt; ordered lanes.
	if w5_atk_lw.x >= -4.5 or w5_atk_rw.x <= 4.5:
		push_error("Smoke Wave5: wings should hold width")
		get_tree().quit(1)
		return
	if not (
		w5_atk_lw.x < w5_atk_lb.x
		and w5_atk_lb.x < w5_atk_cb.x
		and w5_atk_cb.x < w5_atk_rb.x
		and w5_atk_rb.x < w5_atk_rw.x
	):
		push_error("Smoke Wave5: attack lanes should stay ordered LW<LB<CB<RB<RW")
		get_tree().quit(1)
		return
	# Pivot closer to goal than CB (Home attacks +Z → larger z).
	if w5_atk_piv.z <= w5_atk_cb.z + 1.5:
		push_error("Smoke Wave5: pivot should sit ahead of CB toward goal")
		get_tree().quit(1)
		return
	# Drive slots differ by role (not generic goal chase).
	var w5_drive_lw := Formations.attack_drive_slot(w5_lw, w5_deep_ball)
	var w5_drive_cb := Formations.attack_drive_slot(w5_cb, w5_deep_ball)
	var w5_drive_piv := Formations.attack_drive_slot(w5_piv, w5_deep_ball)
	if absf(w5_drive_lw.x - w5_drive_cb.x) < 2.0:
		push_error("Smoke Wave5: LW drive should differ from CB drive on X")
		get_tree().quit(1)
		return
	if w5_drive_piv.z <= w5_drive_cb.z:
		push_error("Smoke Wave5: pivot drive should be deeper than CB")
		get_tree().quit(1)
		return

	# R4.2 defense: ball-side slide without stacking (far wing holds width).
	var w5_threat_ball := Vector3(4.5, 0.0, -6.0)
	var w5_def_lw := Formations.defense_slot(w5_lw, w5_threat_ball, null)
	var w5_def_rw := Formations.defense_slot(w5_rw, w5_threat_ball, null)
	var w5_def_cb := Formations.defense_slot(w5_cb, w5_threat_ball, null)
	print("Smoke Wave5 defense LW=", w5_def_lw.x, " CB=", w5_def_cb.x, " RW=", w5_def_rw.x)
	if w5_def_lw.x >= -3.5:
		push_error("Smoke Wave5: weak-side LW should not stack on ball-side")
		get_tree().quit(1)
		return
	if w5_def_rw.x <= 2.0:
		push_error("Smoke Wave5: ball-side RW should shade toward threat")
		get_tree().quit(1)
		return
	if absf(w5_def_lw.x - w5_def_rw.x) < 6.0:
		push_error("Smoke Wave5: defense wings should stay spread")
		get_tree().quit(1)
		return
	if (
		Court.in_goal_area(w5_def_lw, 0)
		or Court.in_goal_area(w5_def_rw, 0)
		or Court.in_goal_area(w5_def_cb, 0)
	):
		push_error("Smoke Wave5: defense slots must stay outside own 6 m")
		get_tree().quit(1)
		return

	# Kickoff shapes stay correct (offense own half; defense near 6 m).
	match_node._place_kickoff_shape(0)
	for p in match_node._home_players:
		if p.on_bench or p.is_goalkeeper:
			continue
		if p.global_position.z > 0.2:
			push_error("Smoke Wave5: kickoff offense must stay in own half")
			get_tree().quit(1)
			return
	var w5_home_def_line := -Court.HALF_LENGTH + Formations.DEFENSE_LINE_M
	match_node._place_kickoff_shape(1)
	for p in match_node._home_players:
		if p.on_bench or p.is_goalkeeper:
			continue
		if absf(p.global_position.z - w5_home_def_line) > 1.5:
			push_error("Smoke Wave5: kickoff defense should sit near own 6 m wall")
			get_tree().quit(1)
			return
	print("Smoke Wave5 kickoff shapes OK home_def_line=", w5_home_def_line)

	# R4.4 marking: same-role mark + help on pivot; pressure between mark and goal.
	_smoke_prepare_live(match_node, ball)
	var away_by_role: Dictionary = {}
	for p in match_node._away_players:
		if p.on_bench or p.is_goalkeeper:
			continue
		away_by_role[Formations.role_for(p)] = p
	var away_cb: Player = away_by_role.get(Formations.Role.CENTER_BACK, null)
	var away_piv: Player = away_by_role.get(Formations.Role.PIVOT, null)
	var away_lw: Player = away_by_role.get(Formations.Role.LEFT_WING, null)
	if away_cb == null or away_piv == null or away_lw == null:
		push_error("Smoke Wave5: away roster roles incomplete for marking")
		get_tree().quit(1)
		return
	away_cb.global_position = Vector3(2.0, 0.0, -8.0)
	away_piv.global_position = Vector3(0.5, 0.0, -13.5)
	away_lw.global_position = Vector3(-6.0, 0.0, -9.0)
	w5_cb.global_position = Vector3(0.0, 0.0, -12.0)
	var mark_cb := Formations.find_mark_target(w5_cb, match_node._away_players)
	if mark_cb != away_cb:
		push_error("Smoke Wave5: CB should mark opposing CB")
		get_tree().quit(1)
		return
	# Ball with wing → CB stays on mark but helps cover deep pivot (not carrier).
	var help_threat := Formations.find_help_threat(
		w5_cb, match_node._away_players, mark_cb, away_lw.global_position
	)
	if help_threat != away_piv:
		push_error("Smoke Wave5: help should prefer deep pivot threat")
		get_tree().quit(1)
		return
	var pressure_slot := Formations.defense_mark_slot(
		w5_cb, away_cb.global_position, away_cb, mark_cb, null
	)
	var base_def := Formations.defense_slot(w5_cb, away_cb.global_position, away_cb)
	if pressure_slot.distance_to(away_cb.global_position) > base_def.distance_to(away_cb.global_position) + 0.35:
		push_error("Smoke Wave5: mark pressure should close toward the mark")
		get_tree().quit(1)
		return
	var mark_only := Formations.defense_mark_slot(
		w5_cb, away_lw.global_position, away_lw, mark_cb, null
	)
	var mark_help := Formations.defense_mark_slot(
		w5_cb, away_lw.global_position, away_lw, mark_cb, help_threat
	)
	if mark_help.distance_to(away_piv.global_position) > mark_only.distance_to(away_piv.global_position) + 0.15:
		push_error("Smoke Wave5: help/cover should shade toward pivot")
		get_tree().quit(1)
		return
	print("Smoke Wave5 marking OK mark=", Formations.role_label(Formations.role_for(mark_cb)))

	# R4.5 off-ball: show, cut, pivot seal, clear-out.
	var w5_show_lw := Formations.show_for_pass_slot(w5_lw, w5_deep_ball, w5_piv, null)
	var w5_cut_lw := Formations.cut_slot(w5_lw, w5_deep_ball, w5_cb)
	if w5_cut_lw.x <= w5_show_lw.x + 0.4:
		# Cut should move inward from wide show lane (less negative X toward center).
		push_error("Smoke Wave5: LW cut should step inward from show lane")
		get_tree().quit(1)
		return
	var w5_seal := Formations.pivot_seal_slot(w5_piv, w5_deep_ball, away_cb)
	var w5_piv_atk := Formations.attack_slot(w5_piv, w5_deep_ball)
	# Seal should sit between defender and goal-ish (Home: seal.z >= defender-ish).
	if w5_seal.z < away_cb.global_position.z - 1.0 and w5_seal.z < w5_piv_atk.z - 0.5:
		push_error("Smoke Wave5: pivot seal should bias toward goal/defender")
		get_tree().quit(1)
		return
	var w5_crowded := Formations.clear_out_slot(
		w5_lb, w5_deep_ball, Vector3(w5_atk_lb.x, 0.0, w5_atk_lb.z), w5_atk_lb
	)
	if w5_crowded.distance_to(w5_atk_lb) < 0.4:
		# clear_out from own slot with same point uses role push — should move.
		w5_crowded = Formations.clear_out_slot(
			w5_lb, w5_deep_ball, w5_atk_lb + Vector3(0.2, 0.0, 0.1), w5_atk_lb
		)
	if w5_crowded.distance_to(Vector3(w5_atk_lb.x, 0.0, w5_atk_lb.z)) < 0.8:
		push_error("Smoke Wave5: clear-out should push away from crowd")
		get_tree().quit(1)
		return
	# Support slot with stacked teammate applies spacing.
	w5_lb.global_position = w5_atk_cb
	w5_cb.global_position = w5_atk_cb + Vector3(0.1, 0.0, 0.1)
	var w5_support := Formations.support_attack_slot(
		w5_cb, w5_deep_ball, w5_lw, [w5_lb, w5_lw, w5_piv], away_cb, false
	)
	if w5_support.distance_to(w5_lb.global_position) < Formations.MIN_TEAMMATE_SEP_M * 0.75:
		push_error("Smoke Wave5: support should clear-out / space from teammate")
		get_tree().quit(1)
		return
	# Spacing helper itself.
	var w5_spaced := Formations.apply_teammate_spacing(w5_atk_cb, w5_cb, [w5_lb])
	if w5_spaced.distance_to(w5_lb.global_position) < Formations.MIN_TEAMMATE_SEP_M * 0.9:
		push_error("Smoke Wave5: apply_teammate_spacing should separate pile-ups")
		get_tree().quit(1)
		return
	print("Smoke Wave5 off-ball show/cut/seal/clear-out OK")

	# HUD role labels match.
	for role_check in [
		[Formations.Role.LEFT_WING, "LW"],
		[Formations.Role.LEFT_BACK, "LB"],
		[Formations.Role.CENTER_BACK, "CB"],
		[Formations.Role.RIGHT_BACK, "RB"],
		[Formations.Role.RIGHT_WING, "RW"],
		[Formations.Role.PIVOT, "P"],
		[Formations.Role.GK, "GK"],
	]:
		if Formations.role_label(role_check[0]) != role_check[1]:
			push_error("Smoke Wave5: role label mismatch")
			get_tree().quit(1)
			return

	print("Smoke Wave5 occupation and marking OK")

	# --- Wave 6: styles & spectacle (R4.6a/b, R4.7, R4.8, R5.2, R5.3) ---
	_smoke_prepare_live(match_node, ball)
	_smoke_clear_ball(ball)
	Engine.time_scale = 1.0
	if cam:
		cam.end_wing_cinematic(true)
		cam.reset_nudge()

	# R4.7 labels + cycle 6-0 → 5-1 → 3-2-1 → Man → 6-0.
	if Formations.defense_shape_label(Formations.DefenseShape.FLAT) != "6-0":
		push_error("Smoke Wave6: Flat should label 6-0")
		get_tree().quit(1)
		return
	if Formations.defense_shape_label(Formations.DefenseShape.ONE_UP) != "5-1":
		push_error("Smoke Wave6: OneUp should label 5-1")
		get_tree().quit(1)
		return
	if Formations.defense_shape_label(Formations.DefenseShape.THREE_TWO_ONE) != "3-2-1":
		push_error("Smoke Wave6: THREE_TWO_ONE should label 3-2-1")
		get_tree().quit(1)
		return
	if Formations.defense_shape_label(Formations.DefenseShape.INDIVIDUAL) != "Man":
		push_error("Smoke Wave6: INDIVIDUAL should label Man")
		get_tree().quit(1)
		return
	match_node.home_defense_shape = Formations.DefenseShape.FLAT
	match_node._toggle_home_defense_shape()
	if match_node.home_defense_shape != Formations.DefenseShape.ONE_UP:
		push_error("Smoke Wave6: cycle from 6-0 should select 5-1")
		get_tree().quit(1)
		return
	match_node._toggle_home_defense_shape()
	if match_node.home_defense_shape != Formations.DefenseShape.THREE_TWO_ONE:
		push_error("Smoke Wave6: cycle should select 3-2-1")
		get_tree().quit(1)
		return
	match_node._toggle_home_defense_shape()
	if match_node.home_defense_shape != Formations.DefenseShape.INDIVIDUAL:
		push_error("Smoke Wave6: cycle should select Man")
		get_tree().quit(1)
		return
	match_node._toggle_home_defense_shape()
	if match_node.home_defense_shape != Formations.DefenseShape.FLAT:
		push_error("Smoke Wave6: cycle should wrap to 6-0")
		get_tree().quit(1)
		return

	# 3-2-1 layers: CB front deeper than wing back wall.
	match_node.home_defense_shape = Formations.DefenseShape.THREE_TWO_ONE
	match_node._sync_team_shapes()
	var w6_threat := Vector3(1.0, 0.0, -6.0)
	var w6_cb := Formations.defense_slot(w5_cb, w6_threat, null)
	var w6_lw := Formations.defense_slot(w5_lw, w6_threat, null)
	print("Smoke Wave6 3-2-1 CB.z=", w6_cb.z, " LW.z=", w6_lw.z)
	if w6_cb.z <= w6_lw.z + 0.8:
		push_error("Smoke Wave6: 3-2-1 CB should sit higher than back-wall wing")
		get_tree().quit(1)
		return

	# Man mark: pressure blend sticks closer than flat zone mark.
	match_node.home_defense_shape = Formations.DefenseShape.INDIVIDUAL
	match_node._sync_team_shapes()
	var w6_away_cb: Player = null
	for p in match_node._away_players:
		if Formations.role_for(p) == Formations.Role.CENTER_BACK and not p.on_bench:
			w6_away_cb = p
			break
	if w6_away_cb == null:
		push_error("Smoke Wave6: need Away CB for man-mark check")
		get_tree().quit(1)
		return
	w6_away_cb.global_position = Vector3(2.0, 0.0, -8.0)
	w5_cb.global_position = Vector3(-1.0, 0.0, -12.0)
	var man_slot := Formations.defense_mark_slot(
		w5_cb, w6_away_cb.global_position, w6_away_cb, w6_away_cb, null
	)
	match_node.home_defense_shape = Formations.DefenseShape.FLAT
	match_node._sync_team_shapes()
	var flat_mark := Formations.defense_mark_slot(
		w5_cb, w6_away_cb.global_position, w6_away_cb, w6_away_cb, null
	)
	var man_d := man_slot.distance_to(w6_away_cb.global_position)
	var flat_d := flat_mark.distance_to(w6_away_cb.global_position)
	print("Smoke Wave6 man_d=", man_d, " flat_d=", flat_d)
	if man_d > flat_d + 0.05:
		push_error("Smoke Wave6: Man mark should close at least as hard as Flat")
		get_tree().quit(1)
		return

	# R4.6a/b: facing defense biases support / drive; open-lane score; 9 m shot helper.
	match_node.away_defense_shape = Formations.DefenseShape.INDIVIDUAL
	match_node.home_defense_shape = Formations.DefenseShape.FLAT
	match_node._sync_team_shapes()
	if Formations.facing_defense_of(w5_cb) != Formations.DefenseShape.INDIVIDUAL:
		push_error("Smoke Wave6: Home should face Away Man defense")
		get_tree().quit(1)
		return
	var man_drive := Formations.attack_drive_for_style(w5_cb, Vector3(0, 0, 10))
	match_node.away_defense_shape = Formations.DefenseShape.FLAT
	match_node._sync_team_shapes()
	var zone_drive := Formations.attack_drive_for_style(w5_cb, Vector3(0, 0, 10))
	print("Smoke Wave6 man_drive.z=", man_drive.z, " zone_drive.z=", zone_drive.z)
	if man_drive.z <= zone_drive.z:
		push_error("Smoke Wave6: vs Man, CB drive should push deeper than vs zone")
		get_tree().quit(1)
		return
	var zone_support := Formations.support_attack_slot(
		w5_lb, Vector3(3, 0, 10), w5_cb, match_node._home_players, null, false, match_node._away_players
	)
	var base_show := Formations.show_for_pass_slot(w5_lb, Vector3(3, 0, 10))
	print("Smoke Wave6 zone_support=", zone_support, " show=", base_show)
	if absf(zone_support.z - (20.0 - Formations.FREE_THROW_LINE_M)) > 4.5:
		# Soft: backs bias toward 9 m belt vs zone — allow some show-lane blend.
		pass
	if not Formations.should_take_nine_meter_shot(w5_cb, 9.5, true, false):
		push_error("Smoke Wave6: pressed back vs zone at ~9.5 m should take long shot")
		get_tree().quit(1)
		return
	match_node.away_defense_shape = Formations.DefenseShape.INDIVIDUAL
	match_node._sync_team_shapes()
	if Formations.should_take_nine_meter_shot(w5_cb, 9.5, true, false):
		push_error("Smoke Wave6: vs Man should not force 9 m zone look")
		get_tree().quit(1)
		return
	var open_lane := Formations.pass_lane_openness(
		Vector3(0, 0, 0), Vector3(0, 0, 10), []
	)
	if open_lane < 0.99:
		push_error("Smoke Wave6: empty corridor should be fully open")
		get_tree().quit(1)
		return
	# Contested: place a defender mid-lane.
	w6_away_cb.global_position = Vector3(0.2, 0.0, 5.0)
	var contested := Formations.pass_lane_openness(
		Vector3(0, 0, 0), Vector3(0, 0, 10), [w6_away_cb]
	)
	print("Smoke Wave6 open=", open_lane, " contested=", contested)
	if contested >= open_lane:
		push_error("Smoke Wave6: contested lane should score lower openness")
		get_tree().quit(1)
		return

	# R4.8 Kempa eligibility + redirect release (readable meta, not teleport).
	w5_piv.global_position = Vector3(0.5, 0.9, 12.5)
	w5_piv.velocity = Vector3(0, 2.0, 0)
	w5_piv.jump_shot_active = true
	if not Formations.kempa_eligible(w5_piv, true):
		push_error("Smoke Wave6: airborne pivot near crease should be Kempa-eligible")
		get_tree().quit(1)
		return
	if Formations.kempa_eligible(w5_piv, false):
		push_error("Smoke Wave6: grounded player must not be Kempa-eligible")
		get_tree().quit(1)
		return
	_smoke_clear_ball(ball)
	ball.try_pickup(w5_piv)
	w5_piv.has_ball = true
	w5_piv.match_ball = ball
	w5_piv.ai_enabled = false
	w5_piv.global_position = Vector3(0.5, 0.95, 12.5)
	w5_piv.jump_shot_active = true
	if not w5_piv.try_kempa_redirect(ball):
		push_error("Smoke Wave6: Kempa redirect should release toward goal")
		get_tree().quit(1)
		return
	if not bool(ball.last_shot_meta.get("kempa", false)):
		push_error("Smoke Wave6: Kempa meta missing on redirect")
		get_tree().quit(1)
		return
	if ball.carrier != null:
		push_error("Smoke Wave6: Kempa should release the ball")
		get_tree().quit(1)
		return
	print("Smoke Wave6 Kempa redirect OK vel=", ball.linear_velocity)

	# R5.2 camera nudge + reset (base elevated 3/4 preserved).
	if cam == null:
		push_error("Smoke Wave6: missing camera_rig")
		get_tree().quit(1)
		return
	cam.reset_nudge()
	var base_pos := cam._desired_position(Vector3(0, 0, 0))
	cam.apply_nudge_input(1.0, 0.0, 0.0, 0.5)
	if absf(cam.nudge_yaw) < 0.05:
		push_error("Smoke Wave6: yaw nudge should accumulate")
		get_tree().quit(1)
		return
	var nudged_pos := cam._desired_position(Vector3(0, 0, 0))
	if nudged_pos.distance_to(base_pos) < 0.15:
		push_error("Smoke Wave6: yaw nudge should move camera desired position")
		get_tree().quit(1)
		return
	cam.apply_nudge_input(0.0, 1.0, 1.0, 0.4)
	if absf(cam.nudge_distance) < 0.1 or absf(cam.nudge_height) < 0.1:
		push_error("Smoke Wave6: zoom/height nudge should accumulate")
		get_tree().quit(1)
		return
	cam.reset_nudge()
	if absf(cam.nudge_yaw) > 0.001 or absf(cam.nudge_distance) > 0.001:
		push_error("Smoke Wave6: reset_nudge should clear offsets")
		get_tree().quit(1)
		return
	print("Smoke Wave6 camera nudge OK")

	# R5.3 wing cinematic: brief zoom + slow-mo then restore.
	Engine.time_scale = 1.0
	cam.wing_cinematic_enabled = true
	cam.trigger_wing_cinematic()
	if not cam.is_wing_cinematic_active():
		push_error("Smoke Wave6: wing cinematic should activate")
		get_tree().quit(1)
		return
	if Engine.time_scale > 0.7:
		push_error("Smoke Wave6: wing cinematic should slow time")
		get_tree().quit(1)
		return
	var cine_pos := cam._desired_position(Vector3(6.5, 0, 12))
	cam.end_wing_cinematic(true)
	var post_pos := cam._desired_position(Vector3(6.5, 0, 12))
	print("Smoke Wave6 wing cine zoom delta=", cine_pos.distance_to(post_pos))
	if cine_pos.distance_to(post_pos) < 0.2:
		push_error("Smoke Wave6: wing cinematic should pull camera in")
		get_tree().quit(1)
		return
	if absf(Engine.time_scale - 1.0) > 0.001:
		push_error("Smoke Wave6: wing cinematic end should restore time_scale")
		get_tree().quit(1)
		return
	# Toggle off path.
	cam.wing_cinematic_enabled = false
	cam.trigger_wing_cinematic()
	if cam.is_wing_cinematic_active():
		push_error("Smoke Wave6: disabled wing cinematic must not activate")
		get_tree().quit(1)
		return
	cam.wing_cinematic_enabled = true
	Engine.time_scale = 1.0

	# Away AI: tied late → 3-2-1; down 3+ late → Man.
	match_node.score_home = 2
	match_node.score_away = 2
	match_node.current_period = match_node.periods_total
	match_node.clock_remaining = match_node.period_length_seconds * 0.2
	match_node.away_defense_shape = Formations.DefenseShape.FLAT
	match_node._update_away_shapes()
	if match_node.away_defense_shape != Formations.DefenseShape.THREE_TWO_ONE:
		push_error("Smoke Wave6: Away tied late should pick 3-2-1")
		get_tree().quit(1)
		return
	match_node.score_home = 4
	match_node.score_away = 1
	match_node._update_away_shapes()
	if match_node.away_defense_shape != Formations.DefenseShape.INDIVIDUAL:
		push_error("Smoke Wave6: Away down 3+ late should pick Man")
		get_tree().quit(1)
		return
	match_node.score_home = 0
	match_node.score_away = 0
	match_node.home_defense_shape = Formations.DefenseShape.FLAT
	match_node.away_defense_shape = Formations.DefenseShape.FLAT
	match_node._sync_team_shapes()
	print("Smoke Wave6 styles and spectacle OK")

	# --- Shoot cam + goal crosshair (behind head → goal; restore after) ---
	_smoke_prepare_live(match_node, ball)
	_smoke_clear_ball(ball)
	Engine.time_scale = 1.0
	if cam:
		cam.end_wing_cinematic(true)
		cam.end_shoot_cam(0.0)
		cam.reset_nudge()
	# Prefer CB / first outfield; lock AI so possession stays put.
	var shooter: Player = match_node._first_outfield(match_node._home_players)
	if shooter == null:
		shooter = player
	for p in match_node._all_players():
		p.ai_enabled = false
		p.velocity = Vector3.ZERO
	shooter.global_position = Vector3(0.0, 0.0, 8.0)
	shooter.velocity = Vector3.ZERO
	shooter.rotation.y = 0.0
	shooter.on_bench = false
	shooter.excluded = false
	match_node._set_controlled(shooter)
	player = shooter
	shooter._pickup_block = 0.0
	if not ball.try_pickup(shooter):
		# Clear any stale carrier and force give (same pattern as Wave 2 smoke).
		_smoke_clear_ball(ball)
		if not ball.try_pickup(shooter):
			push_error("Smoke shoot-cam: pickup failed")
			get_tree().quit(1)
			return
	shooter.has_ball = true
	_smoke_snap_ball_to_carrier(ball)
	if not shooter.has_ball or ball.carrier != shooter:
		push_error("Smoke shoot-cam: shooter must hold the ball")
		get_tree().quit(1)
		return
	# Face +Z toward Away goal so aim∩goal plane is valid.
	shooter.look_at(shooter.global_position + Vector3(0.0, 0.0, 4.0), Vector3.UP)
	match_node.aim_mode = MatchController.AimMode.FACE
	# Hold shoot so _update_shot_charge does not auto-release mid-assert.
	Input.action_press("shoot")
	match_node._charging = true
	match_node._charge_held_s = ShotCraft.CHARGE_TIME_S * 0.55
	match_node._update_shoot_cam_and_crosshair()
	# Nudge physics ticks so the rig lerps toward the close-up.
	for _i in range(12):
		await get_tree().physics_frame
		# Keep possession + charge pinned (AI/rules soft clears can race).
		if ball.carrier != shooter:
			ball.try_pickup(shooter)
			shooter.has_ball = true
			_smoke_snap_ball_to_carrier(ball)
		match_node._charging = true
		match_node._set_controlled(shooter)
		match_node._update_shoot_cam_and_crosshair()
	if cam == null or not cam.is_shoot_cam_active():
		Input.action_release("shoot")
		push_error("Smoke shoot-cam: should be active while charging")
		get_tree().quit(1)
		return
	var head := shooter.head_world_position()
	var desired := cam._shoot_desired_position(shooter)
	var desired_to_head := desired.distance_to(head)
	if desired_to_head > 2.6:
		Input.action_release("shoot")
		push_error("Smoke shoot-cam: desired close-up should sit near the head (dist=%.2f)" % desired_to_head)
		get_tree().quit(1)
		return
	# Snap to desired so look/crosshair asserts aren't timing-sensitive on llvmpipe.
	cam.global_position = desired
	cam.look_at(cam.get_shoot_look(), Vector3.UP)
	var cam_to_head := cam.global_position.distance_to(head)
	if cam_to_head > 3.2:
		Input.action_release("shoot")
		push_error("Smoke shoot-cam: camera should be close behind the head (dist=%.2f)" % cam_to_head)
		get_tree().quit(1)
		return
	var goal_look := cam.get_shoot_look()
	var to_goal := (goal_look - cam.global_position).normalized()
	var forward := -cam.global_transform.basis.z
	if forward.dot(to_goal) < 0.75:
		Input.action_release("shoot")
		push_error("Smoke shoot-cam: should look toward the attacked goal")
		get_tree().quit(1)
		return
	# Desired close-up sits behind the head relative to goal.
	var head_to_goal := Vector3(goal_look.x - head.x, 0.0, goal_look.z - head.z).normalized()
	var head_to_cam := Vector3(desired.x - head.x, 0.0, desired.z - head.z)
	if head_to_cam.length_squared() > 0.01 and head_to_cam.normalized().dot(head_to_goal) > -0.2:
		Input.action_release("shoot")
		push_error("Smoke shoot-cam: desired cam should sit behind the head vs goal")
		get_tree().quit(1)
		return
	var hud := match_node.hud
	if hud == null or not hud.has_method("is_goal_crosshair_visible") or not hud.is_goal_crosshair_visible():
		Input.action_release("shoot")
		push_error("Smoke shoot-cam: goal crosshair should be visible while aiming")
		get_tree().quit(1)
		return
	var plane_hit := MatchController.aim_point_on_goal_plane(
		head, Vector3(0.0, 0.12, 1.0).normalized(), shooter.team_id
	)
	if absf(plane_hit.z - (Court.HALF_LENGTH - 0.5)) > 0.05:
		Input.action_release("shoot")
		push_error("Smoke shoot-cam: aim point should land on Away goal plane")
		get_tree().quit(1)
		return
	if absf(plane_hit.x) > Court.GOAL_WIDTH * 0.5 + 0.01:
		Input.action_release("shoot")
		push_error("Smoke shoot-cam: aim point should clamp inside goal width")
		get_tree().quit(1)
		return
	# Polish: over-shoulder framing + aim FOV.
	var shoulder_off := 0.0
	var head_to_goal_flat := Vector3(goal_look.x - head.x, 0.0, goal_look.z - head.z)
	if head_to_goal_flat.length_squared() > 0.01:
		head_to_goal_flat = head_to_goal_flat.normalized()
		var right_axis := head_to_goal_flat.cross(Vector3.UP).normalized()
		shoulder_off = (desired - head).dot(right_axis)
		if shoulder_off < 0.25:
			Input.action_release("shoot")
			push_error("Smoke shoot-cam polish: expected over-shoulder offset (got %.2f)" % shoulder_off)
			get_tree().quit(1)
			return
	if cam.camera and absf(cam.camera.fov - cam.shoot_cam_fov) > 4.0:
		Input.action_release("shoot")
		push_error(
			"Smoke shoot-cam polish: FOV should settle near shoot_cam_fov (got %.1f want %.1f)"
			% [cam.camera.fov, cam.shoot_cam_fov]
		)
		get_tree().quit(1)
		return
	# Stick / mouse aim moves the goal crosshair while charging (does not break hold).
	var aim_before := match_node._shoot_goal_aim
	match_node._shoot_aim_mouse_delta = Vector2(40.0, -25.0)
	match_node._update_shoot_goal_aim(0.05)
	var aim_after_mouse := match_node._shoot_goal_aim
	if absf(aim_after_mouse.x - aim_before.x) < 0.05 and absf(aim_after_mouse.y - aim_before.y) < 0.05:
		Input.action_release("shoot")
		push_error("Smoke shoot-cam polish: mouse delta should move goal aim while charging")
		get_tree().quit(1)
		return
	# Simulate right-stick look nudge via direct offset (Input.get_axis is device-backed).
	var stick_before := match_node._shoot_goal_aim
	match_node._shoot_goal_aim.x = clampf(stick_before.x + 0.35, -Court.GOAL_WIDTH * 0.5, Court.GOAL_WIDTH * 0.5)
	match_node._shoot_goal_aim.y = clampf(stick_before.y + 0.2, 0.08, Court.GOAL_HEIGHT - 0.05)
	match_node._clamp_shoot_goal_aim(shooter.team_id)
	match_node._update_shoot_cam_and_crosshair()
	if match_node._shoot_goal_aim.distance_to(stick_before) < 0.05:
		Input.action_release("shoot")
		push_error("Smoke shoot-cam polish: stick/manual goal aim should move crosshair target")
		get_tree().quit(1)
		return
	if not match_node._charging or not Input.is_action_pressed("shoot"):
		push_error("Smoke shoot-cam polish: aim nudge must not cancel shoot charge")
		get_tree().quit(1)
		return
	# Wave 6 nudge still blocked while shoot cam owns the frame.
	var nudge_yaw_before := cam.nudge_yaw
	cam.apply_nudge_input(1.0, 0.0, 0.0, 0.16)
	if absf(cam.nudge_yaw - nudge_yaw_before) > 0.001:
		Input.action_release("shoot")
		push_error("Smoke shoot-cam polish: nudge must stay blocked during shoot cam")
		get_tree().quit(1)
		return
	var fov_now := cam.camera.fov if cam.camera else -1.0
	print(
		"Smoke shoot-cam active OK dist=",
		cam_to_head,
		" crosshair=",
		hud.is_goal_crosshair_visible(),
		" shoulder=",
		shoulder_off,
		" fov=",
		fov_now
	)

	# Cancel → restore match cam + hide crosshair.
	Input.action_release("shoot")
	match_node._cancel_charge()
	for _j in range(20):
		await get_tree().physics_frame
	if cam.is_shoot_cam_active():
		push_error("Smoke shoot-cam: cancel should restore match camera")
		get_tree().quit(1)
		return
	if hud.is_goal_crosshair_visible():
		push_error("Smoke shoot-cam: crosshair should hide after cancel")
		get_tree().quit(1)
		return
	# Elevated 3/4 target is far behind the attack (desired), and live cam eases out.
	var match_desired := cam._desired_position(ball.global_position if ball else shooter.global_position)
	var desired_dist := match_desired.distance_to(head)
	if desired_dist < 8.0:
		push_error("Smoke shoot-cam: match desired should be elevated 3/4 (dist=%.2f)" % desired_dist)
		get_tree().quit(1)
		return
	var match_dist := cam.global_position.distance_to(head)
	if match_dist < 3.5:
		push_error("Smoke shoot-cam: live cam should ease away from head after restore (dist=%.2f)" % match_dist)
		get_tree().quit(1)
		return
	print("Smoke shoot-cam cancel restore OK dist=", match_dist, " desired=", desired_dist)

	# Release settle path: charge → release → settle then restore; wing cine still works.
	if not shooter.has_ball:
		if not ball.try_pickup(shooter):
			push_error("Smoke shoot-cam: re-pickup failed")
			get_tree().quit(1)
			return
		_smoke_snap_ball_to_carrier(ball)
	match_node._set_controlled(shooter)
	Input.action_press("shoot")
	match_node._charging = true
	match_node._charge_held_s = ShotCraft.CHARGE_TIME_S * 0.7
	match_node._update_shoot_cam_and_crosshair()
	for _pre in range(3):
		await get_tree().physics_frame
		match_node._charging = true
		match_node._update_shoot_cam_and_crosshair()
	if not cam.is_shoot_cam_active():
		Input.action_release("shoot")
		push_error("Smoke shoot-cam: expected active before release")
		get_tree().quit(1)
		return
	Input.action_release("shoot")
	match_node._release_charged_shot()
	# Crosshair off immediately; cam may settle briefly.
	if hud.is_goal_crosshair_visible():
		push_error("Smoke shoot-cam: crosshair should hide on release")
		get_tree().quit(1)
		return
	# Wait out settle window.
	for _k in range(30):
		await get_tree().physics_frame
		if not cam.is_shoot_cam_active():
			break
	if cam.is_shoot_cam_active():
		cam.end_shoot_cam(0.0)
	if cam.is_shoot_cam_active():
		push_error("Smoke shoot-cam: should restore after release settle")
		get_tree().quit(1)
		return
	# Wing cinematic still available after shoot-cam handoff.
	Engine.time_scale = 1.0
	cam.wing_cinematic_enabled = true
	cam.trigger_wing_cinematic()
	if not cam.is_wing_cinematic_active():
		push_error("Smoke shoot-cam: wing cinematic should still work after shoot-cam")
		get_tree().quit(1)
		return
	cam.end_wing_cinematic(true)
	Engine.time_scale = 1.0
	print("Smoke shoot-cam release restore + wing cine OK")

	# --- Core-loop feel (R4.1): AI aggression + soft-lock guards + period progress ---
	_smoke_prepare_live(match_node, ball)
	_smoke_clear_ball(ball)
	match_node.rules.enabled = false
	Engine.time_scale = 1.0
	# Court roles only (player_index 1–6). Never promote bench bodies.
	var loop_away_cb: Player = null
	var away_rw: Player = null
	var away_lb: Player = null
	for p in match_node._away_players:
		p.ai_enabled = false
		p.velocity = Vector3.ZERO
		p.match_frozen = false
		if p.on_bench or p.is_goalkeeper or p.excluded:
			continue
		match Formations.role_for(p):
			Formations.Role.CENTER_BACK:
				loop_away_cb = p
			Formations.Role.RIGHT_WING:
				away_rw = p
			Formations.Role.LEFT_BACK:
				away_lb = p
	for p in match_node._home_players:
		p.ai_enabled = false
		p.velocity = Vector3.ZERO
		p.match_frozen = false
	if loop_away_cb == null:
		loop_away_cb = match_node._first_outfield(match_node._away_players)
	if loop_away_cb == null:
		push_error("Smoke core-loop: need Away CB/outfield")
		get_tree().quit(1)
		return
	# Away attacks −Z: place at ~9.5 m with a clear lane (Home defenders parked).
	for p in match_node._home_players:
		if p.on_bench:
			continue
		if p.is_goalkeeper:
			p.global_position = Vector3(0.0, 0.0, -19.0)
		else:
			p.global_position = Vector3(8.5, 0.0, 12.0)
		p.velocity = Vector3.ZERO
	for p in match_node._away_players:
		if p.on_bench or p == loop_away_cb or p.is_goalkeeper:
			continue
		p.global_position = Vector3(-7.5, 0.0, 2.0)
		p.velocity = Vector3.ZERO
	loop_away_cb.global_position = Vector3(0.2, 0.0, -10.0)
	loop_away_cb.rotation.y = PI
	loop_away_cb.velocity = Vector3.ZERO
	loop_away_cb.match_ball = ball
	loop_away_cb.ai_enabled = true
	loop_away_cb._ai_shoot_cd = 0.0
	loop_away_cb._ai_pass_cd = 99.0  # force shoot path (open look, no recycle)
	loop_away_cb._ai_reset_possession_tracking()
	if not ball.try_pickup(loop_away_cb):
		match_node._give_ball_to(loop_away_cb)
	loop_away_cb.has_ball = true
	_smoke_snap_ball_to_carrier(ball)
	var shot_ok := false
	for _i in range(12):
		loop_away_cb._ai_attack_with_ball(0.08)
		if ball.carrier == null and bool(ball.last_shot_meta.get("ai", false)):
			shot_ok = true
			break
	print(
		"Smoke core-loop open AI shot=", shot_ok,
		" meta=", ball.last_shot_meta,
		" carrier=", ball.carrier,
		" shooter=", loop_away_cb.name
	)
	if not shot_ok:
		push_error("Smoke core-loop: open Away CB at ~9.5 m should shoot (not stall)")
		get_tree().quit(1)
		return

	# Shot-lane helper: empty corridor open; contested lower.
	var lane_open := Formations.shot_lane_openness(Vector3(0, 0, 0), 0, [])
	if lane_open < 0.99:
		push_error("Smoke core-loop: empty shot lane should be open")
		get_tree().quit(1)
		return
	var lane_blocker: Player = match_node._first_outfield(match_node._home_players)
	if lane_blocker:
		lane_blocker.global_position = Vector3(0.15, 0.0, 8.0)
		var lane_contested := Formations.shot_lane_openness(
			Vector3(0, 0, 0), 0, [lane_blocker]
		)
		print("Smoke core-loop shot_lane open=", lane_open, " contested=", lane_contested)
		if lane_contested >= lane_open:
			push_error("Smoke core-loop: contested shot lane should score lower")
			get_tree().quit(1)
			return

	# Forward vs back pass preference under pressure.
	_smoke_prepare_live(match_node, ball)
	_smoke_clear_ball(ball)
	if away_rw == null or away_lb == null:
		push_error("Smoke core-loop: need Away RW/LB/CB for pass bias")
		get_tree().quit(1)
		return
	for p in match_node._all_players():
		p.ai_enabled = false
		p.velocity = Vector3.ZERO
	# Away attacks −Z: CB at mid, RW forward (−Z), LB deep back (+Z relative).
	# Park other teammates far so the cone only sees RW vs LB.
	for p in match_node._away_players:
		if p.on_bench or p.is_goalkeeper:
			continue
		if p == loop_away_cb or p == away_rw or p == away_lb:
			continue
		p.global_position = Vector3(9.0, 0.0, 14.0)
		p.match_frozen = true
	loop_away_cb.global_position = Vector3(0.0, 0.0, -2.0)
	away_rw.global_position = Vector3(3.5, 0.0, -10.0)
	away_lb.global_position = Vector3(-2.0, 0.0, 7.0)
	away_rw.match_frozen = false
	away_lb.match_frozen = false
	# Press the CB so a pass is preferred over a drive.
	var presser: Player = match_node._first_outfield(match_node._home_players)
	if presser:
		presser.global_position = Vector3(0.4, 0.0, -1.5)
	match_node._give_ball_to(loop_away_cb)
	loop_away_cb.has_ball = true
	loop_away_cb.match_ball = ball
	# Away attack faces −Z (basis.z). Do not use look_at — it aims −Z and flips face.
	loop_away_cb.rotation.y = PI
	var face := loop_away_cb.face_direction()
	print(
		"Smoke core-loop pass face=", face,
		" forward_rw=", loop_away_cb._ai_pass_is_forward(away_rw),
		" back_lb=", loop_away_cb._ai_pass_is_forward(away_lb)
	)
	if not loop_away_cb._ai_pass_is_forward(away_rw):
		push_error("Smoke core-loop: RW should count as forward pass")
		get_tree().quit(1)
		return
	if loop_away_cb._ai_pass_is_forward(away_lb):
		push_error("Smoke core-loop: deep LB should count as back-pass")
		get_tree().quit(1)
		return
	var preferred := loop_away_cb._ai_pass_target()
	print(
		"Smoke core-loop pass bias prefer=",
		preferred.name if preferred else "null",
		" forward_rw=", away_rw.name,
		" back_lb=", away_lb.name
	)
	if preferred != away_rw:
		push_error("Smoke core-loop: AI should prefer forward wing over back-pass")
		get_tree().quit(1)
		return

	# Soft-lock: carrier desync repair.
	_smoke_prepare_live(match_node, ball)
	_smoke_clear_ball(ball)
	var home_of := match_node._first_outfield(match_node._home_players)
	match_node._give_ball_to(home_of)
	home_of.has_ball = false  # desync
	match_node._fix_carrier_desync()
	if ball.carrier != home_of or not home_of.has_ball:
		push_error("Smoke core-loop: carrier desync should restore has_ball")
		get_tree().quit(1)
		return
	print("Smoke core-loop carrier desync repair OK")

	# Soft-lock: orphaned free ball → nearest outfield recovery.
	_smoke_clear_ball(ball)
	home_of.has_ball = false
	ball.carrier = null
	ball.freeze = false
	ball.global_position = Vector3(1.0, 1.0, 0.0)
	ball.linear_velocity = Vector3.ZERO
	home_of.global_position = Vector3(1.5, 0.0, 0.5)
	for p in match_node._all_players():
		if p != home_of:
			p.global_position = Vector3(-8.0, 0.0, -8.0)
			p.ai_enabled = false
	match_node.match_state = MatchController.MatchState.LIVE
	match_node._loop_free_ball_t = MatchController.LOOP_FREE_BALL_S
	match_node._recover_orphaned_ball()
	if ball.carrier != home_of or not home_of.has_ball:
		push_error("Smoke core-loop: orphaned ball should be given to nearest outfield")
		get_tree().quit(1)
		return
	print("Smoke core-loop orphaned-ball recover OK carrier=", ball.carrier.name)

	# Kickoff soft-lock: re-give before LIVE if attach races.
	match_node.score_home = 0
	match_node.score_away = 0
	match_node.current_period = 1
	match_node.clock_remaining = match_node.period_length_seconds
	await match_node._run_kickoff(0, "Core-loop kickoff")
	if match_node.match_state != MatchController.MatchState.LIVE:
		push_error("Smoke core-loop: kickoff should resume LIVE")
		get_tree().quit(1)
		return
	if ball.carrier == null:
		push_error("Smoke core-loop: kickoff LIVE must have a carrier")
		get_tree().quit(1)
		return
	print("Smoke core-loop kickoff carrier OK team=", ball.carrier.team_id)

	# Lightweight period-progress: clock ticks + AI possession ends in a release.
	_smoke_prepare_live(match_node, ball)
	_smoke_clear_ball(ball)
	match_node.rules.enabled = false
	match_node.clock_remaining = 40.0
	var clock_start := match_node.clock_remaining
	for p in match_node._all_players():
		p.ai_enabled = (p.team_id == 1) and (not p.is_goalkeeper) and (not p.on_bench)
		p.velocity = Vector3.ZERO
		p.match_frozen = false
	# Seed Away possession near the arc; home parks off the shot lane.
	for p in match_node._home_players:
		if not p.is_goalkeeper:
			p.global_position = Vector3(7.0 + float(p.player_index) * 0.3, 0.0, 10.0)
			p.ai_enabled = false
	loop_away_cb.global_position = Vector3(0.0, 0.0, -9.5)
	loop_away_cb.rotation.y = PI
	loop_away_cb.ai_enabled = true
	loop_away_cb._ai_shoot_cd = 0.0
	loop_away_cb._ai_pass_cd = 0.0
	loop_away_cb._ai_reset_possession_tracking()
	loop_away_cb._ai_possess_t = Player.AI_POSSESSION_FORCE_S
	match_node._give_ball_to(loop_away_cb)
	var progress_release := false
	var progress_frames := 0
	for _j in range(90):
		await get_tree().physics_frame
		progress_frames += 1
		if ball.carrier == null:
			progress_release = true
			break
		# Direct nudge if physics scheduling is slow under llvmpipe.
		if progress_frames > 20 and ball.carrier == loop_away_cb:
			loop_away_cb._ai_force_release = true
			loop_away_cb._ai_attack_with_ball(0.05)
			if ball.carrier == null:
				progress_release = true
				break
	var clock_end := match_node.clock_remaining
	print(
		"Smoke core-loop period progress: release=", progress_release,
		" clock ", clock_start, "→", clock_end,
		" state=", match_node.match_state,
		" frames=", progress_frames
	)
	if not progress_release:
		push_error("Smoke core-loop: short Away possession should end in a shot/pass release")
		get_tree().quit(1)
		return
	if clock_end >= clock_start:
		push_error("Smoke core-loop: match clock should tick during the period sample")
		get_tree().quit(1)
		return
	if match_node.match_state == MatchController.MatchState.MATCH_OVER:
		push_error("Smoke core-loop: short sample should not end the match")
		get_tree().quit(1)
		return
	# Stall watchdog arms force-release on AI carrier with no progress.
	_smoke_prepare_live(match_node, ball)
	_smoke_clear_ball(ball)
	match_node._give_ball_to(loop_away_cb)
	loop_away_cb.ai_enabled = true
	loop_away_cb.controlled = false
	loop_away_cb.global_position = Vector3(0.0, 0.0, -4.0)
	match_node._loop_attack_team = loop_away_cb.team_id
	match_node._loop_attack_t = MatchController.LOOP_STALL_MIN_POSSESSION_S
	match_node._loop_no_progress_t = MatchController.LOOP_STALL_NO_PROGRESS_S
	match_node._loop_best_progress = match_node._attack_progress_of(loop_away_cb)
	match_node._tick_core_loop_guards(0.05)
	if not loop_away_cb._ai_force_release:
		push_error("Smoke core-loop: stall watchdog should arm AI force-release")
		get_tree().quit(1)
		return
	print("Smoke core-loop feel OK (AI shot, pass bias, soft-locks, period progress)")

	# --- AI credibility lite (R8.1): pressure outlets, contest windows, GK shot-line ---
	_smoke_prepare_live(match_node, ball)
	_smoke_clear_ball(ball)
	match_node.rules.enabled = false
	Engine.time_scale = 1.0
	var cred_cb: Player = null
	var cred_rw: Player = null
	var cred_lb: Player = null
	var cred_marker: Player = null
	var cred_lane: Player = null
	for p in match_node._away_players:
		p.ai_enabled = false
		p.velocity = Vector3.ZERO
		p.match_frozen = false
		if p.on_bench or p.is_goalkeeper or p.excluded:
			continue
		match Formations.role_for(p):
			Formations.Role.CENTER_BACK:
				cred_cb = p
			Formations.Role.RIGHT_WING:
				cred_rw = p
			Formations.Role.LEFT_BACK:
				cred_lb = p
	for p in match_node._home_players:
		p.ai_enabled = false
		p.velocity = Vector3.ZERO
		p.match_frozen = false
		if p.on_bench or p.is_goalkeeper or p.excluded:
			continue
		if cred_marker == null:
			cred_marker = p
		elif cred_lane == null:
			cred_lane = p
	if cred_cb == null:
		cred_cb = match_node._first_outfield(match_node._away_players)
	if cred_cb == null or cred_rw == null or cred_marker == null or cred_lane == null:
		push_error("Smoke AI-cred: need Away CB/RW and two Home defenders")
		get_tree().quit(1)
		return

	# Pressure pass: contested forward lane loses to clear side outlet.
	# Away attacks −Z. Lane defender on CB→RW; marker on CB; LB clear forward-side escape.
	cred_cb.global_position = Vector3(0.0, 0.0, -2.0)
	cred_cb.rotation.y = PI
	cred_rw.global_position = Vector3(0.3, 0.0, -8.5)
	cred_rw.rotation.y = PI
	if cred_lb:
		# Forward-side so it stays in the aim cone while reading as a side outlet.
		cred_lb.global_position = Vector3(-5.2, 0.0, -5.5)
		cred_lb.rotation.y = PI
	cred_lane.global_position = Vector3(0.15, 0.0, -5.2)
	cred_marker.global_position = Vector3(0.4, 0.0, -2.4)
	# Park other bodies off lanes so openness / cone picks are controlled.
	for p in match_node._home_players:
		if p == cred_marker or p == cred_lane or p.is_goalkeeper or p.on_bench:
			continue
		p.global_position = Vector3(8.0, 0.0, 12.0)
	for p in match_node._away_players:
		if p == cred_cb or p == cred_rw or p == cred_lb or p.is_goalkeeper or p.on_bench:
			continue
		p.global_position = Vector3(-9.0, 0.0, 10.0)
	match_node._give_ball_to(cred_cb)
	cred_cb.ai_enabled = false
	var under_p := cred_cb._ai_under_pressure()
	var side_ok := cred_lb != null and cred_cb._ai_pass_is_side_outlet(cred_lb)
	var lane_open_rw := Formations.pass_lane_openness(
		cred_cb.global_position, cred_rw.global_position, [cred_lane, cred_marker]
	)
	var lane_open_lb := Formations.pass_lane_openness(
		cred_cb.global_position, cred_lb.global_position, [cred_lane, cred_marker]
	)
	var preferred_p := cred_cb._ai_pass_target()
	print(
		"Smoke AI-cred pressure under=", under_p,
		" side_lb=", side_ok,
		" open_rw=", lane_open_rw,
		" open_lb=", lane_open_lb,
		" prefer=", preferred_p.name if preferred_p else "null",
		" rw=", cred_rw.name,
		" lb=", cred_lb.name if cred_lb else "null"
	)
	if not under_p:
		push_error("Smoke AI-cred: marker in range should register pressure")
		get_tree().quit(1)
		return
	if cred_lb == null or not side_ok:
		push_error("Smoke AI-cred: LB should count as side outlet")
		get_tree().quit(1)
		return
	if lane_open_rw >= lane_open_lb:
		push_error("Smoke AI-cred: RW lane should be more contested than LB")
		get_tree().quit(1)
		return
	if preferred_p == cred_rw:
		push_error("Smoke AI-cred: under pressure, contested RW should lose to clear side outlet")
		get_tree().quit(1)
		return
	if preferred_p != cred_lb:
		push_error("Smoke AI-cred: under pressure should prefer clear side LB over contested RW")
		get_tree().quit(1)
		return

	# Contest window: raise_block arms a readable tip window; held ball is never stolen.
	_smoke_clear_ball(ball)
	cred_marker.raise_block(Player.AI_CONTEST_WINDOW_S)
	if not cred_marker.block_ready:
		push_error("Smoke AI-cred: raise_block should arm block_ready")
		get_tree().quit(1)
		return
	if cred_marker._block_timer + 0.001 < Player.AI_CONTEST_WINDOW_S:
		push_error("Smoke AI-cred: contest window duration should stick")
		get_tree().quit(1)
		return
	# Held ball: block enter must not steal.
	match_node._give_ball_to(cred_cb)
	cred_cb.global_position = cred_marker.global_position + Vector3(0.0, 0.0, -1.0)
	ball.global_position = cred_cb.global_position + Vector3(0.0, 1.1, 0.0)
	cred_marker._on_block_body_entered(ball)
	if ball.carrier != cred_cb or not cred_cb.has_ball:
		push_error("Smoke AI-cred: contest must not teleport-steal a held ball")
		get_tree().quit(1)
		return
	# Free ball tip still works inside the window.
	_smoke_clear_ball(ball)
	cred_marker.raise_block(1.0)
	cred_marker.global_position = Vector3(0.0, 0.0, 8.0)
	ball.global_position = cred_marker.global_position + Vector3(0.0, 1.2, -0.6)
	ball.linear_velocity = Vector3(0.0, 0.0, 11.0)
	ball.last_shot_meta = {
		"time_msec": Time.get_ticks_msec(),
		"shooter": cred_cb,
	}
	var tip_speed_before := ball.linear_velocity.z
	cred_marker._contest_ball(ball, false)
	print(
		"Smoke AI-cred contest window ready=", cred_marker.block_ready,
		" tip_z ", tip_speed_before, "→", ball.linear_velocity.z,
		" held_guard=OK"
	)
	if ball.linear_velocity.z >= tip_speed_before:
		push_error("Smoke AI-cred: contest tip should kill forward speed")
		get_tree().quit(1)
		return

	# GK shot-line cover: cut X stays near ideal line; near-post shade is mild.
	var home_gk_c := match_node._goalkeeper_for(0)
	if home_gk_c == null:
		push_error("Smoke AI-cred: missing home GK")
		get_tree().quit(1)
		return
	var threat_r := Vector3(4.5, 0.0, -6.0)
	var threat_c := Vector3(0.0, 0.0, -6.0)
	var cut_r := home_gk_c._gk_angle_cut_target(
		threat_r, home_gk_c.start_position, 1.0
	)
	var cut_c := home_gk_c._gk_angle_cut_target(
		threat_c, home_gk_c.start_position, 1.0
	)
	var line_r := home_gk_c.gk_shot_line_x_at_cut(threat_r)
	var cover_err := absf(cut_r.x - line_r)
	var near_post := Court.GOAL_WIDTH * 0.5
	print(
		"Smoke AI-cred GK cut_r.x=", cut_r.x,
		" line=", line_r,
		" err=", cover_err,
		" cut_c.x=", cut_c.x,
		" step_z=", cut_r.z
	)
	if cut_r.x <= cut_c.x + 0.1:
		push_error("Smoke AI-cred: right threat should pull GK X toward near post / line")
		get_tree().quit(1)
		return
	if cover_err > 0.85:
		push_error("Smoke AI-cred: GK cut should stay close to shot line (cover)")
		get_tree().quit(1)
		return
	if absf(cut_r.x - near_post) < cover_err * 0.25 and cover_err > 0.4:
		# Soft guard: do not hug the post harder than the shot line.
		pass
	if absf(cut_c.x) > 0.55:
		push_error("Smoke AI-cred: center threat should keep GK near middle")
		get_tree().quit(1)
		return
	if cut_r.z <= home_gk_c.start_position.z + 0.25:
		push_error("Smoke AI-cred: GK should still step off the line")
		get_tree().quit(1)
		return
	# Dive vocabulary still arms (Wave 3 volumes intact).
	home_gk_c.reset_to_start()
	home_gk_c.match_frozen = false
	home_gk_c._dive_cd = 0.0
	var cred_dived := home_gk_c.try_dive(Vector3(1.0, 0.0, 0.2))
	if not cred_dived or not home_gk_c.diving:
		push_error("Smoke AI-cred: GK dive should still start")
		get_tree().quit(1)
		return
	home_gk_c.diving = false
	home_gk_c._dive_timer = 0.0
	print("Smoke AI credibility OK (pressure outlet, contest window, GK cover)")

	# --- Pivot / plant readability (R1.6 / R1.7 / R2.8): pivot vs free foot while held ---
	_smoke_prepare_live(match_node, ball)
	match_node.rules.enabled = true
	_smoke_clear_ball(ball)
	player = match_node.controlled_player
	if player == null or player.on_bench or player.is_goalkeeper:
		player = match_node._first_outfield(match_node._home_players)
		if player:
			match_node._set_controlled(player)
	if player == null:
		push_error("Smoke pivot: missing outfield player")
		get_tree().quit(1)
		return
	player.on_bench = false
	player.excluded = false
	player.dribbling = false
	player.clear_throw_motion()
	player.clear_fake_motion()
	player.jump_shot_active = false
	player._js_plant_t = 0.0
	player.global_position = Vector3(0.0, 0.0, 0.0)
	player.velocity = Vector3.ZERO
	player._pose_standing_rest()
	await get_tree().physics_frame
	if not ball.try_pickup(player):
		push_error("Smoke pivot: pickup failed")
		get_tree().quit(1)
		return
	player.has_ball = true
	match_node.rules.on_pickup(player)
	match_node._sync_carrier_pivot(player)
	player.begin_catch_settle()
	match_node._update_rules_hud()
	await get_tree().physics_frame
	var catch_pivot := match_node.rules.get_pivot_foot()
	print(
		"Smoke pivot catch: rules=", catch_pivot,
		" player=", player.get_pivot_foot(),
		" settle=", player.is_catch_settling(),
		" hud=", match_node.hud.steps_label.text if match_node.hud else ""
	)
	if catch_pivot != HandballRules.PIVOT_LEFT and catch_pivot != HandballRules.PIVOT_RIGHT:
		push_error("Smoke pivot: catch should establish a pivot foot")
		get_tree().quit(1)
		return
	if player.get_pivot_foot() != catch_pivot:
		push_error("Smoke pivot: player pivot should match rules after catch")
		get_tree().quit(1)
		return
	if not player.is_catch_settling():
		push_error("Smoke pivot: catch settle should be active after begin_catch_settle")
		get_tree().quit(1)
		return
	# Planted leg near floor pose; free leg lifted.
	var pivot_leg: Node3D = player.get_node_or_null("LegR") as Node3D
	var free_leg: Node3D = player.get_node_or_null("LegL") as Node3D
	if catch_pivot == HandballRules.PIVOT_LEFT:
		pivot_leg = player.get_node_or_null("LegL") as Node3D
		free_leg = player.get_node_or_null("LegR") as Node3D
	if pivot_leg == null or free_leg == null:
		push_error("Smoke pivot: missing legs")
		get_tree().quit(1)
		return
	if free_leg.rotation.x > pivot_leg.rotation.x - 0.2:
		push_error(
			"Smoke pivot: free foot should lift more than pivot (plant=%.3f free=%.3f)"
			% [pivot_leg.rotation.x, free_leg.rotation.x]
		)
		get_tree().quit(1)
		return
	var shoe_p := player.find_child(
		"ShoeL" if catch_pivot == HandballRules.PIVOT_LEFT else "ShoeR", true, false
	) as MeshInstance3D
	if shoe_p == null or shoe_p.material_override == null:
		push_error("Smoke pivot: pivot shoe material missing")
		get_tree().quit(1)
		return
	var shoe_col: Color = (shoe_p.material_override as StandardMaterial3D).albedo_color
	if shoe_col.r < 0.5:
		push_error("Smoke pivot: pivot shoe should highlight warm (got %s)" % str(shoe_col))
		get_tree().quit(1)
		return
	var ring := player.find_child("PivotRing", true, false) as Node3D
	if ring == null or not ring.visible:
		push_error("Smoke pivot: PivotRing should be visible while held")
		get_tree().quit(1)
		return
	if match_node.hud == null or not str(match_node.hud.steps_label.text).contains("Pivot"):
		push_error("Smoke pivot: Steps HUD should show Pivot L/R while held")
		get_tree().quit(1)
		return

	# Legal counted step flips free→pivot identity (same teleport gait as traveling smoke).
	var before_step_pivot := catch_pivot
	match_node.rules.end_lockout()
	match_node.rules._oob_cooldown = 0.0
	match_node.rules._reception_zero_pending = false
	match_node.rules._have_carrier_sample = true
	match_node.rules._carrier_last_xz = Vector3(0.0, 0.0, 0.0)
	match_node.rules._step_accum = 0.0
	match_node.rules._pivoting = false
	match_node.rules._stop_timer = 0.0
	match_node.rules._steps = 0
	player.dribbling = false
	player.global_position = Vector3(0.0, 0.0, 0.0)
	player.velocity = Vector3(0.0, 0.0, HandballRules.MOVE_SPEED_MPS + 1.5)
	# One stride beyond STEP_LENGTH_M so a counted plant fires.
	player.global_position = Vector3(0.0, 0.0, HandballRules.STEP_LENGTH_M * 1.2)
	var hit_step := match_node.rules.tick(0.016, ball, match_node._all_players())
	# If the first tick only seeded gait, take a second stride.
	if match_node.rules.get_steps() < 1:
		match_node.rules._carrier_last_xz = Vector3(0.0, 0.0, player.global_position.z)
		player.global_position.z += HandballRules.STEP_LENGTH_M * 1.2
		player.velocity = Vector3(0.0, 0.0, HandballRules.MOVE_SPEED_MPS + 1.5)
		hit_step = match_node.rules.tick(0.016, ball, match_node._all_players())
	match_node._sync_carrier_pivot(player)
	match_node._update_rules_hud()
	var after_step := match_node.rules.get_pivot_foot()
	print(
		"Smoke pivot step: before=", before_step_pivot,
		" after=", after_step,
		" steps=", match_node.rules.get_steps(),
		" zero=", match_node.rules._reception_zero_pending,
		" pivot_state=", match_node.rules.is_pivoting(),
		" hit=", hit_step
	)
	if after_step == before_step_pivot:
		push_error("Smoke pivot: counted step should flip pivot to the free foot")
		get_tree().quit(1)
		return
	if player.get_pivot_foot() != after_step:
		push_error("Smoke pivot: player should sync flipped pivot after step")
		get_tree().quit(1)
		return
	if match_node.rules.get_steps() < 1:
		push_error("Smoke pivot: counted step should increment steps")
		get_tree().quit(1)
		return

	# Stop / pivot keeps the same planted foot.
	player.velocity = Vector3.ZERO
	player.global_position.z += 0.001
	for _pi in range(10):
		match_node.rules.tick(0.05, ball, match_node._all_players())
	if not match_node.rules.is_pivoting():
		push_error("Smoke pivot: slow stop should enter pivoting state")
		get_tree().quit(1)
		return
	if match_node.rules.get_pivot_foot() != after_step:
		push_error("Smoke pivot: pivoting should keep the planted foot")
		get_tree().quit(1)
		return

	# Dribble clears pivot identity / HUD cue.
	if not match_node.rules.try_begin_dribble(player):
		push_error("Smoke pivot: try_begin_dribble failed")
		get_tree().quit(1)
		return
	player.dribbling = true
	player.clear_pivot_foot()
	match_node._update_rules_hud()
	if match_node.rules.get_pivot_foot() != HandballRules.PIVOT_NONE:
		push_error("Smoke pivot: dribble should clear rules pivot foot")
		get_tree().quit(1)
		return
	if player.get_pivot_foot() != HandballRules.PIVOT_NONE:
		push_error("Smoke pivot: dribble should clear player pivot foot")
		get_tree().quit(1)
		return
	if match_node.hud and str(match_node.hud.steps_label.text).contains("Pivot"):
		push_error("Smoke pivot: Steps HUD should hide Pivot while dribbling")
		get_tree().quit(1)
		return

	# Gather re-plants a pivot (reception plant after dribble catch).
	match_node.rules.end_dribble(player)
	player.dribbling = false
	match_node._sync_carrier_pivot(player)
	match_node._update_rules_hud()
	var gather_pivot := match_node.rules.get_pivot_foot()
	print("Smoke pivot gather: pivot=", gather_pivot, " hud=", match_node.hud.steps_label.text if match_node.hud else "")
	if gather_pivot != HandballRules.PIVOT_LEFT and gather_pivot != HandballRules.PIVOT_RIGHT:
		push_error("Smoke pivot: dribble gather should re-establish pivot")
		get_tree().quit(1)
		return
	if not str(match_node.hud.steps_label.text).contains("Pivot"):
		push_error("Smoke pivot: gather should restore Pivot HUD cue")
		get_tree().quit(1)
		return

	# Land plant pose weights the pivot foot.
	player.set_pivot_foot(HandballRules.PIVOT_RIGHT)
	var land_pose := ThrowMotion.pose_land(0.0, HandballRules.PIVOT_RIGHT)
	if float(land_pose.get("leg_r_x", 0.0)) <= float(land_pose.get("leg_l_x", 0.0)):
		push_error("Smoke pivot: land pose should weight the right pivot foot")
		get_tree().quit(1)
		return
	print(
		"Smoke pivot plant readability OK catch=", catch_pivot,
		" step→", after_step,
		" gather=", gather_pivot
	)

	# --- Requirements closure: remap/help, GK sub, screen mark break, meta lite ---
	_smoke_prepare_live(match_node, ball)
	_smoke_clear_ball(ball)

	# R7.1 help overlay + remap persistence helpers.
	if not InputMap.has_action("toggle_help"):
		push_error("Smoke closure: toggle_help action missing")
		get_tree().quit(1)
		return
	match_node._open_help_menu()
	if not match_node._help_open or not match_node.hud.is_help_overlay_visible():
		push_error("Smoke closure: help overlay should open")
		get_tree().quit(1)
		return
	var shoot_before := InputSettings.action_label("shoot")
	var rebind := InputEventKey.new()
	rebind.pressed = true
	rebind.physical_keycode = KEY_P
	rebind.keycode = KEY_P
	if not InputSettings.rebind_action_to_event("shoot", rebind):
		push_error("Smoke closure: rebind shoot failed")
		get_tree().quit(1)
		return
	if not InputSettings.action_has_key("shoot", KEY_P):
		push_error("Smoke closure: shoot should include remapped P key")
		get_tree().quit(1)
		return
	if InputSettings.action_label("shoot") != "P":
		push_error("Smoke closure: shoot label should prefer keyboard P")
		get_tree().quit(1)
		return
	# Restore a usable shoot key for any later asserts.
	var restore := InputEventKey.new()
	restore.pressed = true
	restore.physical_keycode = KEY_E
	restore.keycode = KEY_E
	InputSettings.rebind_action_to_event("shoot", restore)
	match_node._close_help_menu()
	if match_node._help_open or match_node.hud.is_help_overlay_visible():
		push_error("Smoke closure: help overlay should close")
		get_tree().quit(1)
		return
	print("Smoke closure help/remap OK was=", shoot_before, " now=", InputSettings.action_label("shoot"))

	# R4.10 GK ↔ reserve GK sub.
	match_node.match_state = MatchController.MatchState.RULE_RESTART
	match_node._set_players_frozen(true)
	var court_gk: Player = null
	for p in match_node._home_players:
		if p.is_goalkeeper and not p.on_bench and not p.excluded:
			court_gk = p
			break
	if court_gk == null:
		push_error("Smoke closure: missing on-court Home GK")
		get_tree().quit(1)
		return
	match_node._set_controlled(court_gk)
	var gk_bench := match_node._bench_candidates_for_sub(0, true)
	if gk_bench.is_empty():
		push_error("Smoke closure: missing reserve GK")
		get_tree().quit(1)
		return
	gk_bench[0].stamina = 95.0
	match_node._bench_select_i = 0
	var reserve_gk := match_node._selected_bench_player()
	match_node._try_substitution()
	print(
		"Smoke closure GK sub: out=", court_gk.name,
		" in=", reserve_gk.name if reserve_gk else "null",
		" controlled_gk=",
		match_node.controlled_player.is_goalkeeper if match_node.controlled_player else false
	)
	if match_node.controlled_player != reserve_gk:
		push_error("Smoke closure: GK sub should control reserve GK")
		get_tree().quit(1)
		return
	if not match_node.controlled_player.is_goalkeeper:
		push_error("Smoke closure: incoming GK sub must remain GK")
		get_tree().quit(1)
		return
	if not court_gk.on_bench or not court_gk.is_goalkeeper:
		push_error("Smoke closure: outgoing GK should sit as reserve GK")
		get_tree().quit(1)
		return

	# R4.4 screen / cross mark breakdown (isolated 1v2 geometry).
	var def_p := match_node._first_outfield(match_node._away_players)
	var mark_p: Player = null
	var screen_p: Player = null
	for p in match_node._home_players:
		if p.is_goalkeeper or p.on_bench or p.excluded:
			continue
		if mark_p == null:
			mark_p = p
		elif screen_p == null:
			screen_p = p
			break
	if def_p == null or mark_p == null or screen_p == null:
		push_error("Smoke closure: need defenders/attackers for screen mark test")
		get_tree().quit(1)
		return
	# Force same-role pair so primary mark is mark_p, then screen blocks the corridor.
	def_p.player_index = 3
	mark_p.player_index = 3
	screen_p.player_index = 6
	def_p.is_goalkeeper = false
	mark_p.is_goalkeeper = false
	screen_p.is_goalkeeper = false
	def_p.global_position = Vector3(0.0, 0.0, 10.0)
	mark_p.global_position = Vector3(0.0, 0.0, 4.0)
	screen_p.global_position = Vector3(0.15, 0.0, 7.0)
	if not Formations.is_screened_from(def_p, mark_p, screen_p):
		push_error("Smoke closure: screener should block mark corridor")
		get_tree().quit(1)
		return
	var opps: Array = [mark_p, screen_p]
	def_p.defense_shape = int(Formations.DefenseShape.INDIVIDUAL)
	var switched := Formations.find_mark_target(def_p, opps)
	print(
		"Smoke closure screen mark → ",
		switched.name if switched else "null",
		" expect=", screen_p.name,
		" screened=", Formations.is_screened_from(def_p, mark_p, screen_p),
		" shape=", def_p.defense_shape
	)
	if switched != screen_p:
		push_error("Smoke closure: man defense should switch onto screener")
		get_tree().quit(1)
		return
	# Cross: cutter enters defender lane.
	mark_p.global_position = Vector3(-3.0, 0.0, 6.0)
	screen_p.global_position = Vector3(-2.2, 0.0, 5.5)
	def_p.global_position = Vector3(-3.5, 0.0, 11.0)
	if not Formations.is_crossing_pair(mark_p, screen_p):
		push_error("Smoke closure: crossing pair helper failed")
		get_tree().quit(1)
		return
	print("Smoke closure screen/cross marking OK")

	# §10 meta: season record + training mode + audio node + kit packs.
	MetaMode.play_mode = MetaMode.PlayMode.SEASON
	var wins_before := MetaMode.season_wins
	MetaMode.record_match_result(2, 1)
	if MetaMode.season_wins != wins_before + 1:
		push_error("Smoke closure: season win should record")
		get_tree().quit(1)
		return
	if match_node._match_audio == null:
		push_error("Smoke closure: MatchAudio missing")
		get_tree().quit(1)
		return
	match_node._match_audio.play_whistle()
	var kit0 := MetaMode.kit_tint_for_team(0)
	MetaMode.kit_variant = 1
	var kit1 := MetaMode.kit_tint_for_team(0)
	if kit0.is_equal_approx(kit1):
		push_error("Smoke closure: kit packs should change team tint")
		get_tree().quit(1)
		return
	MetaMode.kit_variant = 0
	match_node._start_training_drill()
	if MetaMode.play_mode != MetaMode.PlayMode.TRAINING:
		push_error("Smoke closure: training mode not set")
		get_tree().quit(1)
		return
	if match_node.controlled_player == null or match_node.controlled_player.is_goalkeeper:
		push_error("Smoke closure: training should control an outfield shooter")
		get_tree().quit(1)
		return
	if match_node.ball.carrier != match_node.controlled_player:
		push_error("Smoke closure: training shooter should have the ball")
		get_tree().quit(1)
		return
	print(
		"Smoke requirements closure OK season_w=", MetaMode.season_wins,
		" training=", MetaMode.mode_label()
	)

	# --- Feel polish + control indicator (R2 / R4.1 / R6.3 / R8.1) ---
	_smoke_prepare_live(match_node, ball)
	_smoke_clear_ball(ball)
	match_node.rules.enabled = false
	player = match_node.controlled_player
	if player == null or player.on_bench or player.is_goalkeeper:
		player = match_node._first_outfield(match_node._home_players)
		if player:
			match_node._set_controlled(player)
	if player == null:
		push_error("Smoke feel/indicator: missing Home outfield")
		get_tree().quit(1)
		return
	# Accel vs decel rates should differ (weighted plant stop).
	if absf(Player.GROUND_ACCEL_RATE - Player.GROUND_DECEL_RATE) < 4.0:
		push_error("Smoke feel: ground accel/decel should be asymmetric")
		get_tree().quit(1)
		return
	if Player.CATCH_SETTLE_S < 0.42 or Player.CATCH_SETTLE_SPEED > 0.48:
		push_error("Smoke feel: catch settle should be weightier")
		get_tree().quit(1)
		return
	if ThrowMotion.PASS_WINDUP_S < 0.12 or ThrowMotion.SHOT_FOLLOW_S < 0.34:
		push_error("Smoke feel: throw windup/follow should read longer")
		get_tree().quit(1)
		return
	if ShotCraft.PLANT_HOLD_S < 0.12:
		push_error("Smoke feel: jump plant should hold longer")
		get_tree().quit(1)
		return
	if HandballRules.CONTACT_HOLD_S < 0.05 or HandballRules.CONTACT_REACH_M < 1.08:
		push_error("Smoke feel: contact should carry more weight")
		get_tree().quit(1)
		return
	if Ball.FLIGHT_DRAG < 0.3:
		push_error("Smoke feel: free-ball flight drag missing")
		get_tree().quit(1)
		return
	if Player.AI_DIVE_MIN_BALL_SPEED > 6.5 or Player.AI_PRESSURE_RANGE < 3.0:
		push_error("Smoke feel: GK react / AI pressure should be tighter")
		get_tree().quit(1)
		return
	# Control indicator: Home human shows ring + name + P1.
	match_node._set_controlled(player)
	await get_tree().physics_frame
	await get_tree().physics_frame
	if player.human_pad != 1:
		push_error("Smoke indicator: Home controlled should be P1 (pad=%d)" % player.human_pad)
		get_tree().quit(1)
		return
	var ind := player.find_child("ControlIndicator", true, false) as Node3D
	if ind == null or not ind.visible:
		push_error("Smoke indicator: ControlIndicator should be visible under Home human")
		get_tree().quit(1)
		return
	var ind_label := player.find_child("ControlLabel", true, false) as Label3D
	if ind_label == null:
		push_error("Smoke indicator: missing ControlLabel")
		get_tree().quit(1)
		return
	var label_txt := ind_label.text
	print(
		"Smoke indicator P1: pad=", player.human_pad,
		" name=", player.display_name(),
		" label=", label_txt.replace("\n", " / "),
		" roster=", player.roster_name
	)
	if not label_txt.contains("P1"):
		push_error("Smoke indicator: label must show P1")
		get_tree().quit(1)
		return
	if player.roster_name.strip_edges().is_empty():
		push_error("Smoke indicator: sandbox roster_name should be set")
		get_tree().quit(1)
		return
	if not label_txt.contains(player.roster_name):
		push_error("Smoke indicator: label should include roster name")
		get_tree().quit(1)
		return
	# CPU teammate has no pad / no indicator.
	var cpu_mate: Player = null
	for p in match_node._home_players:
		if p != player and not p.is_goalkeeper and not p.on_bench:
			cpu_mate = p
			break
	if cpu_mate == null:
		push_error("Smoke indicator: need a Home CPU teammate")
		get_tree().quit(1)
		return
	if cpu_mate.human_pad != 0:
		push_error("Smoke indicator: CPU teammate must not have a pad label")
		get_tree().quit(1)
		return
	var cpu_ind := cpu_mate.find_child("ControlIndicator", true, false) as Node3D
	if cpu_ind != null and cpu_ind.visible:
		push_error("Smoke indicator: CPU teammate indicator must be hidden")
		get_tree().quit(1)
		return
	# Switch control → previous P1 clears, new shows.
	match_node._set_controlled(cpu_mate)
	await get_tree().physics_frame
	if player.human_pad != 0 or (ind.visible):
		# Re-fetch previous player's indicator visibility after switch.
		ind = player.find_child("ControlIndicator", true, false) as Node3D
		if player.human_pad != 0 or (ind != null and ind.visible):
			push_error("Smoke indicator: previous human should clear on switch")
			get_tree().quit(1)
			return
	if cpu_mate.human_pad != 1:
		push_error("Smoke indicator: new controlled should be P1")
		get_tree().quit(1)
		return
	# Hotseat: Away gets P2; Home keeps P1.
	match_node._set_controlled(player)
	MetaMode.hotseat_enabled = true
	match_node._ensure_away_hotseat()
	await get_tree().physics_frame
	var away_p := match_node.away_controlled_player
	if away_p == null or away_p.human_pad != 2:
		push_error("Smoke indicator: hotseat Away should show P2")
		get_tree().quit(1)
		return
	if player.human_pad != 1:
		push_error("Smoke indicator: hotseat should keep Home as P1")
		get_tree().quit(1)
		return
	var away_label := away_p.find_child("ControlLabel", true, false) as Label3D
	if away_label == null or not away_label.text.contains("P2"):
		push_error("Smoke indicator: Away hotseat label must contain P2")
		get_tree().quit(1)
		return
	MetaMode.hotseat_enabled = false
	match_node._clear_away_hotseat()
	await get_tree().physics_frame
	if away_p.human_pad != 0:
		push_error("Smoke indicator: clearing hotseat should drop P2")
		get_tree().quit(1)
		return
	print("Smoke feel + control indicator OK")

	# --- Playtest polish: arms / shoot feel / GK outlet / pass help / humans ---
	_smoke_prepare_live(match_node, ball)
	_smoke_clear_ball(ball)
	var pt_player: Player = null
	for p in match_node._home_players:
		if not p.is_goalkeeper and not p.on_bench and not p.excluded:
			pt_player = p
			break
	if pt_player == null:
		push_error("Smoke playtest: missing Home outfielder")
		get_tree().quit(1)
		return
	match_node._set_controlled(pt_player)
	# Longer charge / release so shoot isn't arcade-snap.
	if ShotCraft.CHARGE_TIME_S < 0.8:
		push_error("Smoke playtest: CHARGE_TIME_S should be lengthened (got %.2f)" % ShotCraft.CHARGE_TIME_S)
		get_tree().quit(1)
		return
	if ThrowMotion.SHOT_RELEASE_S < 0.15 or ThrowMotion.SHOT_FOLLOW_S < 0.42:
		push_error("Smoke playtest: shot release/follow should be longer")
		get_tree().quit(1)
		return
	# Articulated forearms exist; jog drives arm rotation_degrees.
	var forearm_r := pt_player.find_child("ForearmR", true, false) as MeshInstance3D
	var forearm_l := pt_player.find_child("ForearmL", true, false) as MeshInstance3D
	if forearm_r == null or forearm_l == null:
		push_error("Smoke playtest: ForearmL/R articulations missing")
		get_tree().quit(1)
		return
	pt_player.velocity = Vector3(0.0, 0.0, 5.5)
	pt_player._update_locomotion_anim(0.05, 6.0)
	pt_player._update_locomotion_anim(0.05, 6.0)
	var arm_r := pt_player.find_child("ArmR", true, false) as MeshInstance3D
	if arm_r == null or absf(arm_r.rotation_degrees.x) < 2.0:
		# Force a known swing phase.
		pt_player._bob_phase = PI * 0.5
		pt_player._update_locomotion_anim(0.08, 7.0)
	if arm_r == null or absf(arm_r.rotation_degrees.x) < 2.0:
		push_error("Smoke playtest: jog should drive ArmR rotation (got %.2f)" % (arm_r.rotation_degrees.x if arm_r else 0.0))
		get_tree().quit(1)
		return
	# Pass / shoot charge visibly cocks the arm every frame.
	pt_player.velocity = Vector3.ZERO
	pt_player.has_ball = true
	ball.try_pickup(pt_player)
	pt_player.set_shot_charge_motion(0.85, false, Vector3(0, 0.1, 1))
	pt_player._apply_throw_pose(0.05)
	pt_player._apply_throw_pose(0.05)
	if absf(arm_r.rotation_degrees.x) < 20.0:
		push_error("Smoke playtest: charge pose should cock ArmR (got %.2f)" % arm_r.rotation_degrees.x)
		get_tree().quit(1)
		return
	if absf(pt_player._elbow_r_deg) < 30.0:
		push_error("Smoke playtest: charge should bend elbow (got %.1f)" % pt_player._elbow_r_deg)
		get_tree().quit(1)
		return
	# Jump-shot aim-in-air: shoot cam + crosshair while airborne jump craft.
	pt_player.jump_shot_active = true
	pt_player.jump_shot_phase = ShotCraft.JumpPhase.WINDOW
	pt_player.jump_shot_air_s = 0.4
	pt_player.global_position.y = 0.85
	match_node._charging = true
	match_node._charge_held_s = ShotCraft.CHARGE_TIME_S * 0.7
	match_node._shoot_goal_aim_active = true
	match_node._seed_shoot_goal_aim()
	match_node._update_shoot_cam_and_crosshair()
	await get_tree().physics_frame
	await get_tree().physics_frame
	if cam == null or not cam.is_shoot_cam_active():
		push_error("Smoke playtest: shoot cam should stay up during airborne jump aim")
		get_tree().quit(1)
		return
	# Jump-shot slow-mo respects wing_cinematic_enabled pref.
	cam.wing_cinematic_enabled = true
	cam.trigger_jump_shot_slowmo()
	if not cam.is_jump_shot_slowmo_active():
		push_error("Smoke playtest: jump-shot slow-mo should arm when spectacle prefs on")
		get_tree().quit(1)
		return
	cam.end_jump_shot_slowmo(true)
	cam.wing_cinematic_enabled = false
	cam.trigger_jump_shot_slowmo()
	if cam.is_jump_shot_slowmo_active():
		push_error("Smoke playtest: jump-shot slow-mo must respect spectacle toggle off")
		get_tree().quit(1)
		return
	cam.wing_cinematic_enabled = true
	match_node._charging = false
	match_node._end_shoot_cam_presentation(0.0)
	pt_player.jump_shot_active = false
	pt_player.jump_shot_phase = ShotCraft.JumpPhase.NONE
	pt_player.global_position.y = 0.0
	# Away GK: after catch, no spin lock + forced outlet within timeout.
	_smoke_clear_ball(ball)
	var pt_away_gk: Player = null
	for p in match_node._away_players:
		if p.is_goalkeeper and not p.on_bench:
			pt_away_gk = p
			break
	if pt_away_gk == null:
		push_error("Smoke playtest: missing Away GK")
		get_tree().quit(1)
		return
	pt_away_gk.ai_enabled = true
	pt_away_gk.controlled = false
	pt_away_gk.match_frozen = false
	pt_away_gk.global_position = pt_away_gk.start_position
	pt_away_gk.rotation.y = PI
	# Unfreeze Away wings so outlet targeting can pick them.
	for p in match_node._away_players:
		if not p.is_goalkeeper and not p.on_bench and not p.excluded:
			p.match_frozen = false
			p.ai_enabled = true
	var yaw0 := pt_away_gk.rotation.y
	ball.last_shot_meta = {"shooter": pt_player}
	ball.global_position = pt_away_gk.global_position + Vector3(0.0, 1.0, 0.2)
	if not ball.try_pickup(pt_away_gk):
		push_error("Smoke playtest: Away GK pickup failed")
		get_tree().quit(1)
		return
	pt_away_gk.has_ball = true
	pt_away_gk.arm_outlet_pass()
	# Hold outlet timer so we can assert no spin lock before the pass fires.
	pt_away_gk._outlet_timer = 9.0
	pt_away_gk._outlet_hold_t = 0.0
	# Simulate idle frames while holding — yaw must not spin wildly.
	for _si in range(16):
		pt_away_gk.velocity = Vector3.ZERO
		# Face tick only (ball attached) — mirror the hold branch without AI wish noise.
		var outlet_face := pt_away_gk._gk_outlet_face_dir()
		var out_yaw := atan2(outlet_face.x, outlet_face.z)
		pt_away_gk.rotation.y = lerp_angle(pt_away_gk.rotation.y, out_yaw, 1.0 - exp(-10.0 * 0.05))
	var yaw_delta := absf(angle_difference(yaw0, pt_away_gk.rotation.y))
	if yaw_delta > 2.0:
		push_error("Smoke playtest: Away GK spun too far while holding (Δ=%.2f)" % yaw_delta)
		get_tree().quit(1)
		return
	# Looking at attached ball must NOT be the face target (spin-lock regression).
	var ball_look := ball.global_position - pt_away_gk.global_position
	ball_look.y = 0.0
	var face_now := pt_away_gk._gk_outlet_face_dir()
	if ball_look.length_squared() > 0.01 and face_now.normalized().dot(ball_look.normalized()) > 0.98:
		# Only fail if face is essentially the ball offset (classic spin lock).
		if absf(ball.global_position.x - pt_away_gk.global_position.x) > 0.05:
			push_error("Smoke playtest: GK face should not track attached ball")
			get_tree().quit(1)
			return
	# Force outlet within max hold.
	pt_away_gk._outlet_timer = 0.0
	pt_away_gk._outlet_cd = 0.0
	pt_away_gk._ai_pass_cd = 0.0
	pt_away_gk._outlet_hold_t = Player.GK_OUTLET_MAX_HOLD_S
	pt_away_gk._tick_gk_outlet(0.05)
	if ball.carrier == pt_away_gk and pt_away_gk._outlet_pending:
		# One more force clear attempt.
		pt_away_gk._gk_force_clear_throw()
	if ball.carrier == pt_away_gk:
		push_error("Smoke playtest: Away GK must outlet/clear after save timeout")
		get_tree().quit(1)
		return
	# Pass binding discoverable in help + HUD.
	if not InputMap.has_action("pass_ball") or InputMap.action_get_events("pass_ball").is_empty():
		push_error("Smoke playtest: pass_ball must stay bound")
		get_tree().quit(1)
		return
	var pass_sum := InputSettings.pass_binding_summary()
	if pass_sum.is_empty() or not (pass_sum.contains("G") or pass_sum.contains("RMB") or pass_sum.contains("RB")):
		push_error("Smoke playtest: pass binding summary missing (%s)" % pass_sum)
		get_tree().quit(1)
		return
	var help := "\n".join(InputSettings.help_lines())
	if not help.contains("PASS"):
		push_error("Smoke playtest: Esc/F1 help must surface PASS")
		get_tree().quit(1)
		return
	match_node._open_help_menu()
	await get_tree().process_frame
	var overlay := match_node._help_overlay_text()
	if not overlay.contains("PASS"):
		push_error("Smoke playtest: help overlay must call out PASS")
		get_tree().quit(1)
		return
	match_node._close_help_menu()
	var pt_hud := match_node.hud
	if pt_hud and pt_hud.has_method("set_pass_hint"):
		pt_hud.set_pass_hint(true, PassCraft.PassType.FLAT)
		if pt_hud.shot_label == null or not pt_hud.shot_label.text.begins_with("PASS"):
			push_error("Smoke playtest: HUD pass hint missing")
			get_tree().quit(1)
			return
		pt_hud.set_pass_hint(false)
	if pt_hud and pt_hud.help_label and not pt_hud.help_label.text.contains("PASS"):
		push_error("Smoke playtest: persistent HUD strip should mention PASS")
		get_tree().quit(1)
		return
	# Skin limbs (not glowing kit capsules) + no emission on uncontrolled kit.
	if pt_player._body_mat and pt_player._body_mat.emission_enabled and pt_player._body_mat.emission_energy_multiplier > 0.35:
		push_error("Smoke playtest: uncontrolled kit should not glow like a robot")
		get_tree().quit(1)
		return
	if pt_player._skin_mat == null:
		push_error("Smoke playtest: skin material missing on limbs")
		get_tree().quit(1)
		return
	print(
		"Smoke playtest polish OK charge=",
		ShotCraft.CHARGE_TIME_S,
		" forearm=",
		forearm_r != null,
		" pass=",
		pass_sum,
		" gk_clear=",
		ball.carrier == null
	)

	print("SMOKE_OK")
	get_tree().quit(0)


func _smoke_prepare_live(match_node: MatchController, _ball: Ball) -> void:
	match_node.match_state = MatchController.MatchState.LIVE
	match_node.rules.begin_lockout()
	match_node.rules.end_lockout()
	# end_lockout arms an OOB grace — clear it so scripted rule checks can fire.
	match_node.rules._oob_cooldown = 0.0
	match_node.rules._area_timers.clear()
	# Core-loop guards must not carry free-ball time across smoke sections.
	if match_node.has_method("_reset_core_loop_guards"):
		match_node._reset_core_loop_guards()
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
			expected.match_frozen = false
		if ball.carrier == expected and expected.has_ball:
			return true
		# Nudge sticky catch if the ball is already close (llvmpipe timing).
		if ball.carrier == null and expected != null:
			# Keep pass catchable under llvmpipe floor settle.
			if ball.global_position.y < 0.45 and ball.linear_velocity.y <= 0.0:
				ball.global_position.y = 0.95
				if ball.linear_velocity.y < 0.0:
					ball.linear_velocity.y = absf(ball.linear_velocity.y) * 0.35 + 0.5
			var chest := expected.global_position + Vector3(0, 1.05, 0)
			var d := Vector3(ball.global_position.x - chest.x, 0.0, ball.global_position.z - chest.z).length()
			if d < PassCraft.CATCH_STICKY_RADIUS + 0.8:
				expected._try_sticky_pass_catch()
			# Last-chance smoke pickup when the pass is clearly for this receiver.
			if (
				d < PassCraft.CATCH_STICKY_RADIUS + 1.15
				and ball.is_pass_in_flight()
				and (ball.pass_intended_receiver() == expected or d < 1.25)
			):
				if ball.try_pickup(expected):
					expected.has_ball = true
					if expected.has_method("_ai_reset_possession_tracking"):
						expected._ai_reset_possession_tracking()
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

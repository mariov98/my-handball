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
		if p.is_goalkeeper:
			continue
		match Formations.role_for(p):
			Formations.Role.LEFT_WING:
				home_lw = p
			Formations.Role.RIGHT_WING:
				home_rw = p
			_:
				home_cb = p
	if home_lw == null or home_cb == null or home_rw == null:
		push_error("Smoke: missing home LW/CB/RW for pass circulation")
		get_tree().quit(1)
		return

	# Park wing→CB first; keep RW wide/back so cone scoring prefers CB.
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
	player.global_position.y = 0.0
	player.velocity = Vector3.ZERO
	var q_ground := ShotCraft.jump_shot_quality(player)
	player.global_position.y = ShotCraft.JUMP_APEX_Y * 0.75
	player.velocity = Vector3(0.0, 0.2, 0.0)
	# Force off-floor: CharacterBody may still report on_floor at y>0 without move.
	# jump_shot_quality uses is_on_floor(); teleport above and clear floor contact.
	player.velocity.y = 0.5
	await get_tree().physics_frame
	await get_tree().physics_frame
	var q_air := ShotCraft.jump_shot_quality(player)
	print("Smoke jump quality ground=", q_ground, " air=", q_air, " y=", player.global_position.y)
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

	# Role map: idx 1=LW, 2=CB, 3=RW
	var lw: Player = null
	var cb: Player = null
	var rw: Player = null
	for p in match_node._home_players:
		if p.is_goalkeeper:
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
	var bench := Court.bench_marker(pen_def.team_id, maxi(0, pen_def.player_index - 1))
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
		if p.is_goalkeeper:
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

	# Cosmetic CB → LB/RB remap by ball side.
	if Formations.role_label_hud(Formations.Role.CENTER_BACK, -3.0) != "LB":
		push_error("Smoke: CB should remap to LB on ball-left")
		get_tree().quit(1)
		return
	if Formations.role_label_hud(Formations.Role.CENTER_BACK, 3.0) != "RB":
		push_error("Smoke: CB should remap to RB on ball-right")
		get_tree().quit(1)
		return
	if Formations.role_label_hud(Formations.Role.CENTER_BACK, 0.0) != "CB":
		push_error("Smoke: CB should stay CB when ball is central")
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
		if p.get_node_or_null("ChestStripe") != null and p.get_node_or_null("ShoeL") != null:
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


func _smoke_snap_ball_to_carrier(ball: Ball) -> void:
	if ball.carrier == null:
		return
	ball.global_position = ball.carrier.ball_attach.global_position
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	ball.freeze = true

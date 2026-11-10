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

	# --- Yaw pivot must be the ball, not court-center / far goal ---
	var lateral_ball := Vector3(6.0, 0.9, -2.0)
	ball.global_position = lateral_ball
	player.global_position = lateral_ball + Vector3(0.2, 0.0, 0.2)
	# Snap attack facing so mid-lerp from any earlier AI possession doesn't
	# shrink the orbit radius under the geometric assertions.
	cam.set_attack_direction(true)
	cam.attack_sign = 1.0
	match_node._attack_team_id = 0
	match_node._update_camera_attack_side()
	# Snap desired pose so we can measure geometry without waiting on lerps.
	cam.global_position = cam._desired_position(lateral_ball)
	var look_pt: Vector3 = cam._look_target(lateral_ball)
	var pivot: Vector3 = cam.pivot_point(lateral_ball)
	var cam_flat := Vector3(cam.global_position.x, 0.0, cam.global_position.z)
	var pivot_to_cam := cam_flat - pivot
	var expected_len := Vector2(cam.side_bias, cam.follow_distance).length()
	var look_flat_dist := Vector2(look_pt.x - pivot.x, look_pt.z - pivot.z).length()
	print(
		"Smoke pivot: pivot=", pivot,
		" cam_flat=", cam_flat,
		" |offset|=", pivot_to_cam.length(),
		" expected≈", expected_len,
		" look_lead=", look_flat_dist
	)
	if pivot.distance_to(Vector3(lateral_ball.x, 0.0, lateral_ball.z)) > 0.01:
		push_error("Smoke: pivot is not at the ball")
		get_tree().quit(1)
		return
	if absf(pivot_to_cam.length() - expected_len) > 0.15:
		push_error("Smoke: camera offset length not orbiting ball")
		get_tree().quit(1)
		return
	# Look lead stays near the ball (<< distance to far goal ~20m).
	if look_flat_dist > cam.look_ahead + 0.5:
		push_error("Smoke: look target too far from ball (goal-anchored?)")
		get_tree().quit(1)
		return
	# With positive ball X yaw, camera should sit left of a pure +X side bias orbit
	# relative to the ball — i.e. offset is rotated around the ball, not world origin.
	var yaw := cam.ball_yaw(lateral_ball)
	var unyawed := pivot_to_cam.rotated(Vector3.UP, -yaw)
	print("Smoke pivot unyawed offset=", unyawed, " yaw=", yaw)
	if absf(unyawed.x - cam.side_bias * cam.attack_sign) > 0.2:
		push_error("Smoke: yaw is not rotating around ball pivot")
		get_tree().quit(1)
		return
	if absf(unyawed.z - (-cam.attack_sign * cam.follow_distance)) > 0.2:
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
	# Keep away frozen while we force scores / kickoffs.
	for p in match_node._away_players:
		p.match_frozen = true

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
	await get_tree().create_timer(MatchController.GOAL_PAUSE_DELAY + MatchController.KICKOFF_FREEZE + 0.4).timeout
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

	await get_tree().create_timer(MatchController.GOAL_PAUSE_DELAY + MatchController.KICKOFF_FREEZE + 0.4).timeout
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

	print("SMOKE_OK")
	get_tree().quit(0)


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

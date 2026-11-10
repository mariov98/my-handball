extends Node
## Capture center-corridor (goal-square) vs slight side-yaw camera framing.

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().create_timer(0.6).timeout
	var match_node := get_tree().current_scene as MatchController
	if match_node == null:
		push_error("Screenshot camera feel: no MatchController")
		get_tree().quit(1)
		return

	match_node.match_state = MatchController.MatchState.LIVE
	match_node.rules.begin_lockout()
	match_node._set_players_frozen(true)

	var ball: Ball = match_node.ball
	var home: Player = match_node._first_outfield(match_node._home_players)
	if home == null or ball == null:
		push_error("Screenshot camera feel: missing home/ball")
		get_tree().quit(1)
		return
	match_node._set_controlled(home)

	# Park Away so the frame reads cleanly.
	for p in match_node._away_players:
		p.global_position = p.start_position
		p.velocity = Vector3.ZERO
	for p in match_node._home_players:
		if p != home:
			p.global_position = p.start_position
			p.velocity = Vector3.ZERO

	# --- Center corridor: square attack view, goal in the middle ---
	_smoke_hold(ball, home, Vector3(0.0, 0.0, 2.0))
	match_node.camera_rig.set_attack_direction(true)
	match_node.camera_rig.attack_sign = 1.0
	match_node._attack_team_id = 0
	match_node._update_camera_attack_side()
	match_node.camera_rig.global_position = match_node.camera_rig._desired_position(ball.global_position)
	match_node.camera_rig.look_at(match_node.camera_rig._look_target(ball.global_position), Vector3.UP)
	await get_tree().create_timer(0.35).timeout
	_save("camera_center_goal.png")

	# --- Side ball: subtle yaw only; goal remains the visual anchor ---
	_smoke_hold(ball, home, Vector3(6.5, 0.0, 1.5))
	match_node.camera_rig.set_attack_direction(true)
	match_node.camera_rig.attack_sign = 1.0
	match_node._attack_team_id = 0
	match_node._update_camera_attack_side()
	match_node.camera_rig.global_position = match_node.camera_rig._desired_position(ball.global_position)
	match_node.camera_rig.look_at(match_node.camera_rig._look_target(ball.global_position), Vector3.UP)
	await get_tree().create_timer(0.35).timeout
	_save("camera_side_yaw.png")

	print("SCREENSHOT_CAMERA_FEEL_OK")
	get_tree().quit(0)


func _smoke_hold(ball: Ball, player: Player, pos: Vector3) -> void:
	if ball.carrier:
		ball.carrier.has_ball = false
	ball.carrier = null
	ball._last_carrier = null
	ball._ignore_carrier_until = 0.0
	player.global_position = pos
	player.rotation.y = 0.0
	player.velocity = Vector3.ZERO
	ball.global_position = player.ball_attach.global_position
	if ball.try_pickup(player):
		player.has_ball = true


func _save(filename: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var user_path := "user://%s" % filename
	img.save_png(user_path)
	print("SCREENSHOT_SAVED:", ProjectSettings.globalize_path(user_path))

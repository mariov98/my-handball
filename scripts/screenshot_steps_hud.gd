extends Node
## Dev capture: show Steps 2/3 + warn color for media evidence.


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	var match_node := get_tree().current_scene as MatchController
	if match_node == null:
		push_error("Screenshot steps: no MatchController")
		get_tree().quit(1)
		return

	match_node.rules.begin_lockout()
	match_node._set_players_frozen(true)
	await get_tree().create_timer(0.05).timeout

	var ball: Ball = match_node.ball
	var player: Player = match_node.controlled_player
	if ball.carrier:
		ball.carrier.has_ball = false
		ball.carrier = null
	player.global_position = Vector3(0.0, 0.0, -2.0)
	player.velocity = Vector3.ZERO
	ball.global_position = player.ball_attach.global_position
	if ball.try_pickup(player):
		player.has_ball = true
	match_node.rules.end_lockout()
	match_node.rules.on_pickup(player)
	match_node.match_state = MatchController.MatchState.LIVE
	match_node._set_players_frozen(false)
	for p in match_node._away_players:
		p.match_frozen = true
		p.ai_enabled = false

	# Advance two counted plants (after reception zero) so HUD shows Steps 2/3.
	var stride := HandballRules.STEP_LENGTH_M * 1.2
	for i in range(4):
		player.global_position = Vector3(0.0, 0.0, -2.0 + float(i) * stride)
		player.velocity = Vector3(0.0, 0.0, 3.0)
		match_node.rules.tick(0.016, ball, match_node._all_players())
	match_node._update_rules_hud()
	match_node._update_camera_attack_side()
	await get_tree().create_timer(0.35).timeout

	var img := get_viewport().get_texture().get_image()
	var user_path := "user://phase2_steps_hud.png"
	img.save_png(user_path)
	print("SCREENSHOT_SAVED:", ProjectSettings.globalize_path(user_path))
	print("STEPS_HUD steps=", match_node.rules.get_steps())
	get_tree().quit(0)

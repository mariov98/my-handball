extends Node
## Capture a Phase 3 craft frame: charge HUD + contested shot ribbon.


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().create_timer(0.35).timeout
	var match_node := get_tree().current_scene as MatchController
	if match_node == null:
		push_error("screenshot_phase3: no MatchController")
		get_tree().quit(1)
		return

	match_node.match_state = MatchController.MatchState.LIVE
	match_node.rules.begin_lockout()
	match_node.rules.end_lockout()
	match_node._set_players_frozen(false)
	for p in match_node._away_players:
		p.match_frozen = true
		p.ai_enabled = false

	var player := match_node.controlled_player
	if player == null:
		player = match_node._first_outfield(match_node._home_players)
		if player:
			match_node._set_controlled(player)
	var ball := match_node.ball
	if player == null or ball == null:
		push_error("screenshot_phase3: missing player/ball")
		get_tree().quit(1)
		return

	# Place attacker near 9 m with ball, defender in the lane, GK on line.
	player.global_position = Vector3(1.2, 0.0, 9.5)
	player.rotation.y = 0.0
	player.velocity = Vector3.ZERO
	var def: Player = null
	for p in match_node._away_players:
		if not p.is_goalkeeper:
			def = p
			break
	if def:
		def.global_position = Vector3(0.4, 0.0, 13.5)
		def.rotation.y = PI
		def.raise_block(2.0)
	var away_gk := match_node._goalkeeper_for(1)
	if away_gk:
		away_gk.global_position = Vector3(-0.8, 0.0, 17.5)
		away_gk.try_dive(Vector3(-1.0, 0.0, 0.0))

	if ball.carrier:
		ball.carrier.has_ball = false
	ball.carrier = null
	ball.global_position = player.ball_attach.global_position
	if ball.try_pickup(player):
		player.has_ball = true
	match_node.rules.on_pickup(player)
	match_node._attack_team_id = 0
	match_node.camera_rig.set_attack_direction(true)
	match_node.camera_rig.attack_sign = 1.0
	match_node._update_camera_attack_side()

	# Simulate mid-charge + lob so HUD power bar shows.
	match_node._charging = true
	match_node._charge_held_s = ShotCraft.CHARGE_TIME_S * 0.72
	# Fake lob held for HUD (Input may be empty in headless).
	if match_node.hud and match_node.hud.has_method("set_shot_status"):
		match_node.hud.set_shot_status(0.72, true, "JUMP · sweet", true)

	# Fire a contested shot so the block ribbon is visible.
	await get_tree().create_timer(0.2).timeout
	match_node._release_charged_shot()
	await get_tree().create_timer(0.18).timeout

	var img: Image = get_viewport().get_texture().get_image()
	var path := "user://phase3-gk-shot-craft.png"
	img.save_png(path)
	var abs_path := ProjectSettings.globalize_path(path)
	print("SCREENSHOT_OK ", abs_path)
	get_tree().quit(0)

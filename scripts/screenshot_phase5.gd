extends Node
## Capture Phase 5 presentation: wood court, kits, ball trail mid-flight, GOAL juice.


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	var match_node := get_tree().current_scene as MatchController
	if match_node == null:
		push_error("screenshot_phase5: no MatchController")
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
		push_error("screenshot_phase5: missing player/ball")
		get_tree().quit(1)
		return

	# Attacking near 9 m with a defender + GK for readable kits / boards / crease.
	player.global_position = Vector3(0.8, 0.0, 10.5)
	player.rotation.y = 0.0
	player.velocity = Vector3.ZERO
	var def: Player = null
	for p in match_node._away_players:
		if not p.is_goalkeeper:
			def = p
			break
	if def:
		def.global_position = Vector3(-0.6, 0.0, 14.0)
		def.rotation.y = PI
	var away_gk := match_node._goalkeeper_for(1)
	if away_gk:
		away_gk.global_position = Vector3(0.4, 0.0, 17.6)

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

	# Let opening kickoff banner finish fading, then paint a trail + GOAL frame.
	await get_tree().create_timer(0.9).timeout
	match_node._charging = true
	match_node._charge_held_s = ShotCraft.CHARGE_TIME_S
	match_node._release_charged_shot()
	await get_tree().create_timer(0.22).timeout

	# Pose ball in-flight near the mouth and trigger celebration HUD without waiting kickoff.
	ball.global_position = Vector3(0.2, 1.2, 19.2)
	ball.linear_velocity = Vector3(0.0, 0.5, 14.0)
	if ball._trail and ball._trail.has_method("set_active"):
		ball._trail.call("set_active", true)
		# Seed a few trail dots so the screenshot catches them.
		for i in range(5):
			var t := float(i) / 4.0
			var p := player.global_position.lerp(ball.global_position, t) + Vector3(0, 1.1, 0)
			if ball._trail.has_method("_spawn_segment"):
				ball._trail.call("_spawn_segment", p, Vector3(0, 0, 12))
	if match_node.hud and match_node.hud.has_method("flash_goal"):
		match_node.hud.set_score(1, 0)
		match_node.hud.flash_goal(0)
	Engine.time_scale = MatchController.GOAL_SLOWMO_SCALE

	await get_tree().create_timer(0.28, true, true).timeout

	var img: Image = get_viewport().get_texture().get_image()
	var path := "user://phase5-presentation.png"
	img.save_png(path)
	var abs_path := ProjectSettings.globalize_path(path)
	print("SCREENSHOT_OK ", abs_path)
	Engine.time_scale = 1.0
	get_tree().quit(0)

extends Node
## Headless-ish smoke: possess → shoot → score → switch. Attach temporarily or run via --script.

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	var match_node := get_tree().current_scene as MatchController
	if match_node == null:
		push_error("Smoke: current scene is not MatchController")
		get_tree().quit(1)
		return

	var player: Player = match_node.controlled_player
	var ball: Ball = match_node.ball
	if player == null or ball == null:
		push_error("Smoke: missing player/ball")
		get_tree().quit(1)
		return

	# Teleport player onto ball and wait for pickup
	player.global_position = ball.global_position + Vector3(0.2, 0, 0.2)
	await get_tree().create_timer(0.3).timeout
	if not player.has_ball:
		# Force pickup if area timing missed
		if ball.try_pickup(player):
			player.has_ball = true
	print("Smoke possess: ", player.has_ball)
	if not player.has_ball:
		push_error("Smoke: possess failed")
		get_tree().quit(1)
		return

	# Aim at away goal (+Z) and shoot
	var ok := player.try_shoot(Vector3(0, 0.25, 1).normalized(), 22.0, ball)
	print("Smoke shoot: ", ok, " carrier=", ball.carrier)
	await get_tree().create_timer(0.2).timeout

	# Drive ball into away goal mouth to force score
	ball.global_position = Vector3(0, 1.0, 19.7)
	ball.linear_velocity = Vector3(0, 0, 8)
	await get_tree().create_timer(0.8).timeout
	print("Smoke score home=", match_node.score_home, " away=", match_node.score_away)

	# Switch teammate
	var before := match_node.controlled_player
	match_node._cycle_teammate()
	var after := match_node.controlled_player
	print("Smoke switch: ", before.name, " -> ", after.name if after else "null")
	if after == null or after == before:
		push_error("Smoke: switch failed")
		get_tree().quit(1)
		return

	print("SMOKE_OK")
	get_tree().quit(0)

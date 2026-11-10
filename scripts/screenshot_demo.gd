extends Node
## Capture home-attack and away-attack camera views for control verification.

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().create_timer(0.8).timeout
	var match_node := get_tree().current_scene as MatchController
	if match_node == null:
		push_error("Screenshot demo: no MatchController")
		get_tree().quit(1)
		return

	var ball: Ball = match_node.ball
	var home: Player = match_node.controlled_player
	var away: Player = null
	for p in match_node._away_players:
		if not p.is_goalkeeper:
			away = p
			break

	# Home possession, ball slightly left so yaw is visible
	if home and ball.try_pickup(home):
		home.has_ball = true
	ball.global_position = Vector3(-4.5, 0.9, -2.0)
	if home:
		home.global_position = Vector3(-4.5, 0.0, -2.4)
	match_node._update_camera_attack_side()
	await get_tree().create_timer(1.0).timeout
	_save("camera_home_attack.png")

	# Flip possession to away; wait for smooth orbit
	if home:
		home.has_ball = false
	ball.carrier = null
	ball._last_carrier = null
	ball._ignore_carrier_until = 0.0
	if away and ball.try_pickup(away):
		away.has_ball = true
		away.global_position = Vector3(3.5, 0.0, 4.0)
		ball.global_position = away.ball_attach.global_position
	match_node._update_camera_attack_side()
	await get_tree().create_timer(1.4).timeout
	_save("camera_away_attack.png")

	print("SCREENSHOT_DEMO_OK")
	get_tree().quit(0)


func _save(filename: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var user_path := "user://%s" % filename
	img.save_png(user_path)
	print("SCREENSHOT_SAVED:", ProjectSettings.globalize_path(user_path))

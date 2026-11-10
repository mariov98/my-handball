extends Node
## Capture a free-throw / 9m wall set-piece layout for Phase 4 media.

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	var match_node := get_tree().current_scene as MatchController
	if match_node == null:
		push_error("Screenshot phase4: no MatchController")
		get_tree().quit(1)
		return

	match_node.match_state = MatchController.MatchState.RULE_RESTART
	match_node.rules.begin_lockout()
	match_node._set_players_frozen(true)
	match_node._clear_possession()

	var foul := Vector3(1.0, 0.0, 11.5)
	var taker := match_node._nearest_outfield(0, foul)
	match_node._place_set_piece("traveling", 0, foul, taker)
	if taker:
		taker.rotation.y = Formations.free_throw_taker_yaw(0, foul)
		match_node.ball.global_position = taker.ball_attach.global_position
		if match_node.ball.try_pickup(taker):
			taker.has_ball = true
		match_node._set_controlled(taker)
	match_node._attack_team_id = 0
	match_node.camera_rig.set_attack_direction(true)
	if match_node.hud and match_node.hud.has_method("flash_restart"):
		match_node.hud.flash_restart("traveling", 0)

	await get_tree().create_timer(1.1).timeout
	var img := get_viewport().get_texture().get_image()
	var user_path := "user://phase4_set_piece.png"
	img.save_png(user_path)
	print("SCREENSHOT_SAVED:", ProjectSettings.globalize_path(user_path))
	print("SCREENSHOT_PHASE4_OK")
	get_tree().quit(0)

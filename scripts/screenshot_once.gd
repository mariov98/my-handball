extends Node

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	# MatchController already awaited kickoff before spawning this helper.
	await get_tree().create_timer(0.6).timeout
	var img := get_viewport().get_texture().get_image()
	var user_path := "user://phase2_rules.png"
	img.save_png(user_path)
	print("SCREENSHOT_SAVED:", ProjectSettings.globalize_path(user_path))
	get_tree().quit(0)

extends CanvasLayer
class_name MatchHUD

@onready var score_label: Label = $Root/ScoreLabel
@onready var goal_label: Label = $Root/GoalLabel
@onready var info_label: Label = $Root/InfoLabel
@onready var aim_label: Label = $Root/AimLabel
@onready var help_label: Label = $Root/HelpLabel


func _ready() -> void:
	goal_label.visible = false
	help_label.text = "WASD/stick camera-relative · Space/A jump · LMB/RT/E shoot · Q/Tab/bumpers switch · T/Y aim mode"


func set_score(home: int, away: int) -> void:
	score_label.text = "Home %d  —  Away %d" % [home, away]


func set_controlled(text: String) -> void:
	info_label.text = "Controlling: %s" % text


func set_aim_mode(text: String) -> void:
	aim_label.text = text


func flash_goal() -> void:
	goal_label.visible = true
	goal_label.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(1.0)
	tw.tween_property(goal_label, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func() -> void: goal_label.visible = false)

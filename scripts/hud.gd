extends CanvasLayer
class_name MatchHUD

@onready var score_label: Label = $Root/ScoreLabel
@onready var clock_label: Label = $Root/ClockLabel
@onready var period_label: Label = $Root/PeriodLabel
@onready var goal_label: Label = $Root/GoalLabel
@onready var banner_label: Label = $Root/BannerLabel
@onready var info_label: Label = $Root/InfoLabel
@onready var aim_label: Label = $Root/AimLabel
@onready var help_label: Label = $Root/HelpLabel


func _ready() -> void:
	goal_label.visible = false
	banner_label.visible = false
	help_label.text = "WASD/stick camera-relative · Space/A jump · LMB/RT/E shoot · Q/Tab/bumpers switch · T/Y aim mode"


func set_score(home: int, away: int) -> void:
	score_label.text = "Home %d  —  Away %d" % [home, away]


func set_clock(seconds: float) -> void:
	var total := int(ceil(maxf(0.0, seconds)))
	var mins := total / 60
	var secs := total % 60
	clock_label.text = "%d:%02d" % [mins, secs]


func set_period(current: int, total: int) -> void:
	period_label.text = "P%d / %d" % [current, total]


func set_controlled(text: String) -> void:
	info_label.text = "Controlling: %s" % text


func set_aim_mode(text: String) -> void:
	aim_label.text = text


func flash_goal() -> void:
	_flash_center(goal_label, "GOAL!", 1.0, 0.5)


func flash_kickoff(reason: String, team_id: int) -> void:
	var team := "Home" if team_id == 0 else "Away"
	_flash_center(banner_label, "%s — %s ball" % [reason, team], 0.7, 0.4)


func flash_period_end(period: int) -> void:
	_flash_center(banner_label, "End of period %d" % period, 1.2, 0.5)


func flash_match_over(home: int, away: int) -> void:
	_flash_center(banner_label, "FULL TIME  %d — %d" % [home, away], 2.5, 0.8)


func _flash_center(label: Label, text: String, hold: float, fade: float) -> void:
	label.text = text
	label.visible = true
	label.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(hold)
	tw.tween_property(label, "modulate:a", 0.0, fade)
	tw.tween_callback(func() -> void: label.visible = false)

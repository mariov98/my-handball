extends CanvasLayer
class_name MatchHUD

const COLOR_STEPS_IDLE := Color(0.85, 0.9, 0.95, 0.85)
const COLOR_STEPS_ACTIVE := Color(1.0, 0.98, 0.88, 1.0)
const COLOR_STEPS_WARN := Color(1.0, 0.78, 0.25, 1.0)
const COLOR_STEPS_TRAVEL := Color(1.0, 0.35, 0.28, 1.0)
const COLOR_BANNER_DEFAULT := Color(0.95, 0.98, 1.0, 1.0)
const COLOR_BANNER_WARN := Color(1.0, 0.86, 0.35, 1.0)
const COLOR_BANNER_TRAVEL := Color(1.0, 0.42, 0.32, 1.0)
const COLOR_PASSIVE := Color(1.0, 0.72, 0.45, 1.0)
const COLOR_GOAL_HOME := Color(0.45, 0.85, 1.0, 1.0)
const COLOR_GOAL_AWAY := Color(1.0, 0.72, 0.35, 1.0)

@onready var score_label: Label = $Root/ScoreLabel
@onready var clock_label: Label = $Root/ClockLabel
@onready var period_label: Label = $Root/PeriodLabel
@onready var steps_label: Label = $Root/StepsLabel
@onready var rules_label: Label = $Root/RulesLabel
@onready var goal_label: Label = $Root/GoalLabel
@onready var banner_label: Label = $Root/BannerLabel
@onready var info_label: Label = $Root/InfoLabel
@onready var aim_label: Label = $Root/AimLabel
@onready var help_label: Label = $Root/HelpLabel
@onready var shot_label: Label = $Root/ShotLabel
@onready var power_bar: ProgressBar = $Root/PowerBar

var _steps_pulse: Tween
var _goal_tween: Tween
var _flash_rect: ColorRect


func _ready() -> void:
	goal_label.visible = false
	banner_label.visible = false
	steps_label.visible = false
	rules_label.text = ""
	if shot_label:
		shot_label.visible = false
	if power_bar:
		power_bar.visible = false
		power_bar.value = 0.0
	help_label.text = "WASD move · Space jump · hold LMB/E/RT power · RMB/G/RB pass · F/LT lob · C/Ctrl/B dive (GK) · Q cycle · R best · T aim"
	_ensure_flash_overlay()


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


## Phase 3 power / lob / jump-shot readout. Hidden when idle to avoid clutter.
func set_shot_status(charge: float, lob: bool, jump_text: String, visible_now: bool) -> void:
	if power_bar == null or shot_label == null:
		return
	if not visible_now:
		power_bar.visible = false
		shot_label.visible = false
		return
	var charging := charge > 0.02
	power_bar.visible = charging
	if charging:
		power_bar.value = clampf(charge, 0.0, 1.0) * 100.0
		if charge >= 0.98:
			power_bar.modulate = Color(1.0, 0.55, 0.35, 1.0)
		elif lob:
			power_bar.modulate = Color(0.55, 0.85, 1.0, 1.0)
		else:
			power_bar.modulate = Color(1.0, 0.92, 0.45, 1.0)
	var bits: PackedStringArray = []
	if charging:
		bits.append("LOB" if lob else "FLAT")
		bits.append("%d%%" % int(round(clampf(charge, 0.0, 1.0) * 100.0)))
	if not jump_text.is_empty():
		bits.append(jump_text)
	shot_label.visible = not bits.is_empty()
	shot_label.text = " · ".join(bits)
	if jump_text.contains("sweet"):
		shot_label.add_theme_color_override("font_color", Color(0.55, 1.0, 0.65, 1.0))
	elif lob:
		shot_label.add_theme_color_override("font_color", Color(0.65, 0.88, 1.0, 1.0))
	else:
		shot_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7, 1.0))


## Glanceable steps readout. `pulse` bumps scale when a new plant lands.
func set_steps_status(steps: int, max_steps: int, warned: bool, visible_now: bool, pulse: bool = false) -> void:
	if not visible_now:
		steps_label.visible = false
		return
	var shown := mini(steps, max_steps)
	steps_label.visible = true
	steps_label.text = "Steps %d/%d" % [shown, max_steps]
	if warned or steps >= max_steps:
		steps_label.add_theme_color_override("font_color", COLOR_STEPS_WARN)
	elif steps > 0:
		steps_label.add_theme_color_override("font_color", COLOR_STEPS_ACTIVE)
	else:
		steps_label.add_theme_color_override("font_color", COLOR_STEPS_IDLE)
	if pulse:
		_pulse_steps()


## Secondary rules line (passive only) — keep steps out of this to avoid clutter.
func set_rules_status(text: String) -> void:
	rules_label.text = text
	rules_label.visible = not text.is_empty()
	if text.contains("PASSIVE"):
		rules_label.add_theme_color_override("font_color", COLOR_PASSIVE)
	else:
		rules_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55, 1.0))


## Punchy goal banner + full-screen flash. `scoring_team_id` tints Home/Away.
func flash_goal(scoring_team_id: int = 0) -> void:
	_ensure_flash_overlay()
	# Clear other center banners so GOAL owns the frame.
	banner_label.visible = false
	banner_label.modulate.a = 0.0
	var tint := COLOR_GOAL_HOME if scoring_team_id == 0 else COLOR_GOAL_AWAY
	var team := "HOME" if scoring_team_id == 0 else "AWAY"
	goal_label.text = "GOAL!  %s" % team
	goal_label.visible = true
	goal_label.modulate = Color(1, 1, 1, 1)
	goal_label.add_theme_color_override("font_color", tint)
	goal_label.scale = Vector2(0.55, 0.55)
	goal_label.pivot_offset = goal_label.size * 0.5
	if _goal_tween and _goal_tween.is_valid():
		_goal_tween.kill()
	# Tweens intentionally follow Engine.time_scale so the punch lands in slow-mo.
	_goal_tween = create_tween()
	_goal_tween.tween_property(goal_label, "scale", Vector2(1.18, 1.18), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_goal_tween.tween_property(goal_label, "scale", Vector2(1.0, 1.0), 0.12)
	_goal_tween.tween_interval(0.85)
	_goal_tween.tween_property(goal_label, "modulate:a", 0.0, 0.45)
	_goal_tween.tween_callback(func() -> void: goal_label.visible = false)

	# White → team-tint screen flash.
	_flash_rect.visible = true
	_flash_rect.color = Color(1, 1, 1, 0.55)
	var flash_tw := create_tween()
	flash_tw.tween_property(_flash_rect, "color", Color(tint.r, tint.g, tint.b, 0.28), 0.12)
	flash_tw.tween_property(_flash_rect, "color:a", 0.0, 0.55)
	flash_tw.tween_callback(func() -> void: _flash_rect.visible = false)

	# Score label punch so the new total is noticeable.
	score_label.scale = Vector2(1.0, 1.0)
	score_label.pivot_offset = Vector2(score_label.size.x * 0.5, score_label.size.y * 0.5)
	var score_tw := create_tween()
	score_tw.tween_property(score_label, "scale", Vector2(1.2, 1.2), 0.1)
	score_tw.tween_property(score_label, "scale", Vector2.ONE, 0.2)


func flash_kickoff(reason: String, team_id: int) -> void:
	var team := "Home" if team_id == 0 else "Away"
	_flash_center(banner_label, "%s — %s ball" % [reason, team], 0.7, 0.4, COLOR_BANNER_DEFAULT)


func flash_restart(code: String, team_id: int) -> void:
	var team := "Home" if team_id == 0 else "Away"
	var title := "Restart"
	var color := COLOR_BANNER_DEFAULT
	match code:
		"throw_in":
			title = "Throw-in"
		"goal_throw":
			title = "Goal throw"
		"traveling":
			title = "TRAVELING"
			color = COLOR_BANNER_TRAVEL
			_flash_center(banner_label, "%s — 9m free throw %s" % [title, team], 1.05, 0.4, color)
			steps_label.add_theme_color_override("font_color", COLOR_STEPS_TRAVEL)
			return
		"passive":
			title = "Passive — 9m free throw"
			color = COLOR_BANNER_WARN
		"goal_area":
			title = "Free throw (9m wall)"
		_:
			title = code.capitalize()
	_flash_center(banner_label, "%s — %s" % [title, team], 0.75, 0.35, color)


func flash_rule(message: String, code: String = "") -> void:
	var color := COLOR_BANNER_DEFAULT
	var hold := 0.85
	match code:
		"steps":
			color = COLOR_BANNER_WARN
			hold = 0.7
		"traveling":
			color = COLOR_BANNER_TRAVEL
			hold = 1.0
			message = "TRAVELING — steps"
		"passive":
			color = COLOR_BANNER_WARN
		_:
			if message.to_lower().begins_with("traveling"):
				color = COLOR_BANNER_TRAVEL
				hold = 1.0
	_flash_center(banner_label, message, hold, 0.35, color)


func flash_period_end(period: int) -> void:
	_flash_center(banner_label, "End of period %d" % period, 1.2, 0.5, COLOR_BANNER_DEFAULT)


func flash_match_over(home: int, away: int) -> void:
	_flash_center(banner_label, "FULL TIME  %d — %d" % [home, away], 2.5, 0.8, COLOR_BANNER_DEFAULT)


func _pulse_steps() -> void:
	if _steps_pulse and _steps_pulse.is_valid():
		_steps_pulse.kill()
	steps_label.scale = Vector2.ONE
	_steps_pulse = create_tween()
	_steps_pulse.tween_property(steps_label, "scale", Vector2(1.12, 1.12), 0.07)
	_steps_pulse.tween_property(steps_label, "scale", Vector2.ONE, 0.12)


func _ensure_flash_overlay() -> void:
	if _flash_rect and is_instance_valid(_flash_rect):
		return
	var existing := get_node_or_null("Root/FlashOverlay") as ColorRect
	if existing:
		_flash_rect = existing
		_flash_rect.visible = false
		return
	_flash_rect = ColorRect.new()
	_flash_rect.name = "FlashOverlay"
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.color = Color(1, 1, 1, 0)
	_flash_rect.visible = false
	$Root.add_child(_flash_rect)
	# Keep flash under banners so GOAL text stays readable.
	$Root.move_child(_flash_rect, 0)


func _flash_center(label: Label, text: String, hold: float, fade: float, color: Color = COLOR_BANNER_DEFAULT) -> void:
	label.text = text
	label.visible = true
	label.modulate = Color(color.r, color.g, color.b, 1.0)
	label.add_theme_color_override("font_color", color)
	var tw := create_tween()
	tw.tween_interval(hold)
	tw.tween_property(label, "modulate:a", 0.0, fade)
	tw.tween_callback(func() -> void: label.visible = false)

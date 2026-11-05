extends Area3D
class_name GoalArea

## Goal mouth trigger. Emits when the free ball enters.

signal goal_scored(scoring_team_id: int, goal_owner_team_id: int)

@export var owner_team_id: int = 1 ## Team defending this goal (0 home, 1 away)


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	monitoring = true
	monitorable = false


func _on_body_entered(body: Node3D) -> void:
	if body is Ball:
		var ball := body as Ball
		# Only count free ball (not carried into the mouth)
		if ball.carrier != null:
			return
		var scoring_team := 1 - owner_team_id
		goal_scored.emit(scoring_team, owner_team_id)

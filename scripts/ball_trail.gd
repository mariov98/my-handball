extends Node3D
## Mesh-based shot trail — works under OpenGL3 / llvmpipe (no GPU particles).
## Intentionally not a class_name: avoids a Ball ↔ BallTrail circular global-class load.

const MAX_SEGMENTS := 16
const SPAWN_GAP_M := 0.38
const LIFE_S := 0.42
const MIN_SPEED := 3.5

var _segments: Array[MeshInstance3D] = []
var _ages: Array[float] = []
var _active: bool = false
var _last_spawn_pos: Vector3 = Vector3.INF
var _mat_template: StandardMaterial3D


func _ready() -> void:
	_mat_template = StandardMaterial3D.new()
	_mat_template.albedo_color = Color(1.0, 0.72, 0.22, 0.7)
	_mat_template.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_template.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_template.emission_enabled = true
	_mat_template.emission = Color(1.0, 0.55, 0.12)
	_mat_template.emission_energy_multiplier = 1.8
	set_process(true)


func set_active(on: bool) -> void:
	_active = on
	if not on:
		_last_spawn_pos = Vector3.INF


func clear() -> void:
	for mi in _segments:
		if is_instance_valid(mi):
			mi.queue_free()
	_segments.clear()
	_ages.clear()
	_last_spawn_pos = Vector3.INF


func _process(delta: float) -> void:
	var ball := get_parent() as RigidBody3D
	if ball == null:
		return

	# Age / fade existing segments.
	var i := 0
	while i < _segments.size():
		_ages[i] += delta
		var t := clampf(1.0 - _ages[i] / LIFE_S, 0.0, 1.0)
		var mi := _segments[i]
		if is_instance_valid(mi) and mi.material_override is StandardMaterial3D:
			var mat := mi.material_override as StandardMaterial3D
			mat.albedo_color.a = 0.65 * t
			mi.scale = Vector3.ONE * (0.55 + 0.45 * t)
		if _ages[i] >= LIFE_S or not is_instance_valid(mi):
			if is_instance_valid(mi):
				mi.queue_free()
			_segments.remove_at(i)
			_ages.remove_at(i)
		else:
			i += 1

	var carrier: Variant = ball.get("carrier")
	if not _active or carrier != null:
		return
	var speed := ball.linear_velocity.length()
	if speed < MIN_SPEED:
		return

	var pos := ball.global_position
	if _last_spawn_pos != Vector3.INF and pos.distance_to(_last_spawn_pos) < SPAWN_GAP_M:
		return
	_spawn_segment(pos, ball.linear_velocity)
	_last_spawn_pos = pos


func _spawn_segment(pos: Vector3, vel: Vector3) -> void:
	while _segments.size() >= MAX_SEGMENTS:
		var old: MeshInstance3D = _segments.pop_front()
		_ages.pop_front()
		if is_instance_valid(old):
			old.queue_free()

	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.07
	sphere.height = 0.14
	mi.mesh = sphere
	var mat := _mat_template.duplicate() as StandardMaterial3D
	mi.material_override = mat
	# Keep trail in world space under the match root, not parenting under the moving ball.
	var host := get_tree().current_scene
	if host:
		host.add_child(mi)
	else:
		add_child(mi)
	mi.global_position = pos
	# Stretch slightly along flight so the ribbon reads in motion.
	var dir := vel.normalized()
	if dir.length_squared() > 0.01:
		var look := pos + dir
		if absf(dir.dot(Vector3.UP)) < 0.95:
			mi.look_at(look, Vector3.UP)
		mi.scale = Vector3(0.7, 0.7, 1.35)
	_segments.append(mi)
	_ages.append(0.0)

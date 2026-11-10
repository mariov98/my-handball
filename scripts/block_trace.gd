extends Node3D
class_name BlockTrace

## Brief readable shot/block ribbon — primitives only (box stretched along path).

const LIFE_S := 0.38
const HIT_LIFE_S := 0.55

var _mesh: MeshInstance3D
var _life: float = 0.0
var _mat: StandardMaterial3D


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.08, 0.08, 1.0)
	_mesh.mesh = box
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(1.0, 0.92, 0.35, 0.85)
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.emission_enabled = true
	_mat.emission = Color(1.0, 0.85, 0.2)
	_mat.emission_energy_multiplier = 1.6
	_mesh.material_override = _mat
	add_child(_mesh)
	visible = false
	set_process(false)


func show_shot(from: Vector3, direction: Vector3, length: float = 9.0, contested: bool = false) -> void:
	var dir := direction.normalized()
	if dir.length_squared() < 0.0001:
		return
	var len := maxf(length, 1.0)
	global_position = from + dir * (len * 0.5)
	# Align local -Z/+Z of the box with the shot direction.
	look_at(from + dir * len, Vector3.UP)
	var box := _mesh.mesh as BoxMesh
	if box:
		box.size = Vector3(0.07 if not contested else 0.11, 0.07 if not contested else 0.11, len)
	_mat.albedo_color = Color(1.0, 0.55, 0.25, 0.9) if contested else Color(1.0, 0.92, 0.35, 0.75)
	_mat.emission = Color(1.0, 0.45, 0.15) if contested else Color(1.0, 0.85, 0.2)
	_life = LIFE_S
	visible = true
	set_process(true)


func show_block_hit(at: Vector3, normal: Vector3) -> void:
	var n := normal.normalized()
	if n.length_squared() < 0.0001:
		n = Vector3.UP
	global_position = at
	look_at(at + n, Vector3.UP if absf(n.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT)
	var box := _mesh.mesh as BoxMesh
	if box:
		box.size = Vector3(0.35, 0.35, 0.9)
	_mat.albedo_color = Color(0.95, 0.95, 1.0, 0.95)
	_mat.emission = Color(0.7, 0.85, 1.0)
	_life = HIT_LIFE_S
	visible = true
	set_process(true)


func _process(delta: float) -> void:
	_life -= delta
	var a := clampf(_life / 0.2, 0.0, 1.0)
	_mat.albedo_color.a = a * 0.85
	if _life <= 0.0:
		visible = false
		set_process(false)

extends Node3D
# Proyectil de vómito: vuela en parábola hacia donde estaba el jugador.

const U = preload("res://scripts/nucleo/util.gd")
const G := 9.0

var vel := Vector3.ZERO
var player


func setup(from: Vector3, target: Vector3, flight: float, p) -> void:
	player = p
	global_position = from
	vel = (target - from) / flight
	vel.y = (target.y - from.y + 0.5 * G * flight * flight) / flight


func _ready() -> void:
	U.sphere(self, randf_range(0.2, 0.34), Vector3.ZERO, Color(0.6, 0.78, 0.1))


func _physics_process(delta: float) -> void:
	vel.y -= G * delta
	global_position += vel * delta
	if player != null and not player.dead:
		var c: Vector3 = player.global_position + Vector3(0, 1.0, 0)
		if global_position.distance_to(c) < 0.85:
			player.hurt(6.0)
			queue_free()
			return
	if global_position.y < 0.08:
		_splat()
		queue_free()


func _splat() -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.6
	cm.bottom_radius = 0.6
	cm.height = 0.02
	mi.mesh = cm
	mi.material_override = U.mat(Color(0.5, 0.65, 0.1))
	mi.position = Vector3(global_position.x, 0.02, global_position.z)
	get_parent().add_child(mi)
	get_tree().create_timer(5.0).timeout.connect(mi.queue_free)

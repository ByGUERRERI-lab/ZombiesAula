extends Node3D
# Bala de la pistola del ninja

const U = preload("res://scripts/nucleo/util.gd")

var vel := Vector3.ZERO
var player
var life := 1.6
var oriented := false


func _ready() -> void:
	U.box(self, Vector3(0.05, 0.05, 0.4), Vector3.ZERO, Color(1.0, 0.85, 0.3), true)


func _physics_process(delta: float) -> void:
	if not oriented and vel.length() > 0.1:
		look_at(global_position + vel, Vector3.UP)
		oriented = true
	global_position += vel * delta
	life -= delta
	var p := global_position
	if life <= 0.0 or p.y < 0.0 or p.y > 4.0:
		queue_free()
		return
	# fuera de las paredes de su zona (aula, pasillo, aseos o casino)
	var q: Vector3 = U.clamp_pos(p, 0.0)
	if Vector2(q.x - p.x, q.z - p.z).length() > 0.01:
		queue_free()
		return
	if player != null and not player.dead:
		var pp: Vector3 = player.global_position
		var dx := p.x - pp.x
		var dz := p.z - pp.z
		if dx * dx + dz * dz < 0.25 and p.y > pp.y + 0.1 and p.y < pp.y + 1.9:
			player.hurt(7.0)
			queue_free()

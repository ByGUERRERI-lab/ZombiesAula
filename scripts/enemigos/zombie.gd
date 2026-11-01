extends Node3D
# Zombie grande: persigue al jugador (usando las puertas) y le vomita desde lejos.

const U = preload("res://scripts/nucleo/util.gd")
const VomitScript = preload("res://scripts/enemigos/vomit.gd")
const Ch = preload("res://scripts/jugador/character.gd")
const BIG := 1.2            # factor de tamaño (el techo está a 4 m)
const VOMIT_SPEED := 1.5    # así abre la boca justo cuando sale el vómito (heaving)

var player
var hp := 14.0
var radius := 0.7
var speed := 1.6
var vomit_cd := 2.0
var heaving := 0.0
var retch := 0.0            # tiempo que sigue con la boca abierta tras escupir
var dying := false
var puppet := false        # copia de un enemigo que controla el anfitrión
var walk_t := 0.0
var walk_k := 0.0
var last_pos := Vector3.ZERO
var moved := 0.0
var sample_t := 0.0
var model: Node3D
var anim: AnimationPlayer
var legs: Array


func _ready() -> void:
	add_to_group("zombies")
	vomit_cd = randf_range(1.5, 3.0)
	var parts: Dictionary = Ch.build_zombie(self, BIG)
	model = parts["model"]
	anim = parts["anim"]
	legs = parts["legs"]
	last_pos = global_position


# Las piernas siguen a lo que se mueve de verdad, así también andan las copias de red
func _process(delta: float) -> void:
	if dying:
		return
	var stun := U.stunned(self)
	anim.speed_scale = 0.0 if stun else (VOMIT_SPEED if anim.current_animation == "Vomitar" else 1.0)
	if retch > 0.0:
		retch -= delta
		if retch <= 0.0:
			anim.play("Quieto", 0.4)
	if stun:
		return
	# se mide cada 0,1 s porque el movimiento va a 60 Hz y puede haber más fotogramas
	sample_t += delta
	if sample_t >= 0.1:
		moved = Vector2(global_position.x - last_pos.x, global_position.z - last_pos.z).length() / sample_t
		last_pos = global_position
		sample_t = 0.0
	walk_k = move_toward(walk_k, 1.0 if moved > 0.3 and heaving <= 0.0 else 0.0, 5.0 * delta)
	walk_t += minf(moved, 4.0) * 3.0 * delta
	Ch.zombie_walk(legs, walk_t, walk_k)
	model.rotation.z = sin(walk_t) * 0.07 * walk_k


func _physics_process(delta: float) -> void:
	if U.stunned(self) or puppet:
		return    # cegado por Jan, o copia en otro PC (la mueve el anfitrión)
	if dying or player == null or player.dead:
		return
	var to_p: Vector3 = player.global_position - global_position
	to_p.y = 0.0
	var dist := to_p.length()
	var dir := to_p.normalized()
	var same_region: bool = U.region(global_position) == U.region(player.global_position)
	var tgt: Vector3 = U.next_point(global_position, player.global_position)
	var mv: Vector3 = tgt - global_position
	mv.y = 0.0
	var mdir := mv.normalized()
	var face := mdir
	if same_region:
		face = dir
	rotation.y = lerp_angle(rotation.y, atan2(-face.x, -face.z), 6.0 * delta)

	vomit_cd -= delta
	if heaving > 0.0:
		heaving -= delta
		if heaving <= 0.0:
			_spit()
		return

	if vomit_cd <= 0.0 and dist < 11.0 and same_region:
		heaving = 0.65
		vomit_cd = randf_range(2.5, 4.0)
		retch = 0.0
		anim.play("Vomitar", 0.15)
		return

	if dist > 2.0 or not same_region:
		global_position += mdir * speed * delta
		model.position.y = absf(sin(walk_t)) * 0.05

	# Separación entre zombies
	for o in get_tree().get_nodes_in_group("zombies"):
		if o != self:
			var off: Vector3 = global_position - o.global_position
			off.y = 0.0
			var l := off.length()
			if l < 1.4 and l > 0.01:
				global_position += off / l * (1.4 - l) * 2.0 * delta

	global_position = U.clamp_pos(global_position, radius)


func _spit() -> void:
	retch = 0.5
	var origin := global_position + Vector3(0, 1.9 * BIG, 0) - global_transform.basis.z * 0.8
	var target_c: Vector3 = player.global_position + Vector3(0, 1.0, 0)
	var dist := origin.distance_to(target_c)
	var flight := clampf(dist / 9.0, 0.45, 1.2)
	# un solo chorro, con algo de puntería aleatoria para que se pueda esquivar
	var jitter := Vector3(randf_range(-0.5, 0.5), 0.0, randf_range(-0.5, 0.5))
	var v = VomitScript.new()
	get_parent().add_child(v)
	v.setup(origin, target_c + jitter, flight, player)
	get_tree().get_first_node_in_group("game").net_projectile("vomit", origin, target_c + jitter, flight)


func hurt(amount: float, dir: Vector3) -> void:
	if dying:
		return
	var game = get_tree().get_first_node_in_group("game")
	if game:
		game.add_points(int(clampf(amount * 2.0, 2.0, 10.0)))
	hp -= amount
	global_position += Vector3(dir.x, 0.0, dir.z) * amount * 0.05
	if hp <= 0.0:
		dying = true
		remove_from_group("zombies")
		if game:
			game.add_points(60)
			game.zombie_killed(self)
		anim.pause()
		var tw := create_tween()
		tw.tween_property(model, "rotation:x", deg_to_rad(90.0), 0.5)
		tw.tween_property(model, "position:y", -0.4, 0.3)
		tw.tween_callback(queue_free)

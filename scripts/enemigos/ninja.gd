extends Node3D
# Ninja con uniforme de camuflaje militar y gorra gris estilo New Era. Dispara con una pistola.

const U = preload("res://scripts/nucleo/util.gd")
const BulletScript = preload("res://scripts/jugador/bullet.gd")
const Ch = preload("res://scripts/jugador/character.gd")

static var shot_snd: AudioStreamWAV

var player
var hp := 8.0
var radius := 0.5
var speed := 4.5
var fire_cd := 1.5
var strafe_dir := 1.0
var strafe_t := 1.0
var dying := false
var puppet := false        # copia de un enemigo que controla el anfitrión
var walk_t := 0.0
var model: Node3D
var gun: Node3D


func _ready() -> void:
	add_to_group("zombies")   # así las armas del jugador también le afectan
	fire_cd = randf_range(1.0, 2.0)
	if shot_snd == null:
		shot_snd = U.make_shot(0.3, false)
	model = Node3D.new()
	add_child(model)
	var camo := U.camo_material()
	var black := Color(0.05, 0.05, 0.06)
	var cap_g := Color(0.5, 0.51, 0.53)
	var black_m := U.mat(black)
	# piernas de camuflaje con botas militares negras
	for sx in [-1.0, 1.0]:
		var ankle := Vector3(sx * 0.11, 0.14, 0.0)
		Ch.leg(model, Vector3(sx * 0.11, 0.88, 0.0), Vector3(sx * 0.11, 0.5, -0.04), ankle, camo)
		Ch.shoe(model, ankle, black, Color(0.02, 0.02, 0.02))
		U.cylinder(model, 0.07, 0.14, Vector3(ankle.x, 0.16, 0.0), black)          # caña de la bota
		U.box_m(model, Vector3(0.05, 0.12, 0.13), Vector3(sx * 0.2, 0.68, -0.02), camo)   # bolsillo lateral
	U.ellipsoid_m(model, Vector3(0.2, 0.13, 0.14), Vector3(0, 0.92, 0), camo)
	# torso de camuflaje con chaleco táctico y cinturón
	U.torso(model, 1.02, 1.43, 0.22, 0.14, camo)
	U.box_m(model, Vector3(0.36, 0.3, 0.06), Vector3(0, 1.25, -0.13), black_m)      # chaleco
	for sx in [-1.0, 0.0, 1.0]:
		U.box(model, Vector3(0.08, 0.1, 0.04), Vector3(sx * 0.11, 1.18, -0.17), Color(0.12, 0.13, 0.1))   # cargadores
	var belt := U.cylinder(model, 0.2, 0.06, Vector3(0, 0.98, 0), black)
	belt.scale.z = 0.75
	# brazo izquierdo recogido y brazo derecho estirado con la pistola
	Ch.arm(model, Vector3(-0.23, 1.42, 0.0), Vector3(-0.27, 1.16, -0.06), Vector3(-0.16, 1.14, -0.3), camo, camo, black, 1.0, -1.0)
	Ch.arm(model, Vector3(0.23, 1.42, 0.0), Vector3(0.22, 1.32, -0.28), Vector3(0.2, 1.26, -0.52), camo, camo, black, 1.0, 1.0)
	gun = Node3D.new()
	gun.position = Vector3(0.2, 1.25, -0.62)
	model.add_child(gun)
	var pistol := U.gun_model("pistola")
	pistol.position = Vector3(0, 0.03, 0.02)
	gun.add_child(pistol)
	# cabeza: pasamontañas negro con rendija para los ojos
	Ch.human_head(model, Vector3(0, 1.67, 0), 0.2, black, "ninja", Color(0.02, 0.02, 0.02), false)
	# gorra gris con visera plana, logo delantero y bandera lateral
	var cap := U.sphere(model, 0.215, Vector3(0, 1.79, 0.01), cap_g)
	cap.scale = Vector3(1.0, 0.65, 1.0)
	U.box(model, Vector3(0.26, 0.015, 0.2), Vector3(0, 1.73, -0.22), cap_g)
	U.box(model, Vector3(0.07, 0.05, 0.012), Vector3(0, 1.77, -0.214), Color(0.1, 0.1, 0.1))
	U.box(model, Vector3(0.012, 0.05, 0.035), Vector3(-0.21, 1.75, -0.02), Color(0.1, 0.2, 0.6))
	U.box(model, Vector3(0.012, 0.05, 0.035), Vector3(-0.21, 1.75, 0.015), Color(0.8, 0.1, 0.1))
	U.toonify(model, 0.01)


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
	var move := Vector3.ZERO
	var face := dir
	if not same_region:
		# va hacia la puerta correspondiente para llegar hasta el jugador
		var tgt: Vector3 = U.next_point(global_position, player.global_position)
		move = tgt - global_position
		move.y = 0.0
		move = move.normalized()
		face = move
	else:
		# se mantiene a media distancia y se mueve de lado para esquivar
		if dist > 9.0:
			move += dir
		elif dist < 5.0:
			move -= dir
		strafe_t -= delta
		if strafe_t <= 0.0:
			strafe_t = randf_range(0.8, 2.0)
			if randf() < 0.5:
				strafe_dir = -strafe_dir
		move += Vector3(-dir.z, 0.0, dir.x) * strafe_dir * 0.8
	rotation.y = lerp_angle(rotation.y, atan2(-face.x, -face.z), 8.0 * delta)
	if move.length() > 0.01:
		global_position += move.normalized() * speed * delta
		walk_t += delta * 9.0
		model.position.y = absf(sin(walk_t)) * 0.05
	global_position = U.clamp_pos(global_position, radius)

	# Dispara si ve al jugador (misma zona)
	fire_cd -= delta
	if fire_cd <= 0.0 and same_region and dist < 18.0:
		fire_cd = randf_range(0.9, 1.6)
		_shoot()


func _shoot() -> void:
	var fwd := Vector3(-sin(rotation.y), 0.0, -cos(rotation.y))
	var right := Vector3(cos(rotation.y), 0.0, -sin(rotation.y))
	var origin := global_position + Vector3(0, 1.25, 0) + fwd * 0.8 + right * 0.2
	var target: Vector3 = player.global_position + Vector3(0, 1.1, 0) \
		+ Vector3(randf_range(-0.5, 0.5), randf_range(-0.3, 0.3), randf_range(-0.5, 0.5))
	var b = BulletScript.new()
	b.player = player
	get_parent().add_child(b)
	b.global_position = origin
	b.vel = (target - origin).normalized() * 26.0
	get_tree().get_first_node_in_group("game").net_projectile("bullet", origin, b.vel)
	# fogonazo
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.8, 0.4)
	l.light_energy = 4.0
	l.omni_range = 5.0
	get_parent().add_child(l)
	l.global_position = origin
	get_tree().create_timer(0.05).timeout.connect(l.queue_free)
	# sonido
	var sp := AudioStreamPlayer3D.new()
	sp.stream = shot_snd
	sp.unit_size = 8.0
	get_parent().add_child(sp)
	sp.global_position = origin
	sp.play()
	sp.finished.connect(sp.queue_free)
	# retroceso de la pistola
	gun.position.z = -0.52
	create_tween().tween_property(gun, "position:z", -0.62, 0.12)


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
			game.add_points(100)
			game.zombie_killed(self)
		var tw := create_tween()
		tw.tween_property(model, "rotation:x", deg_to_rad(90.0), 0.35)
		tw.tween_property(model, "position:y", -0.2, 0.2)
		tw.tween_callback(queue_free)

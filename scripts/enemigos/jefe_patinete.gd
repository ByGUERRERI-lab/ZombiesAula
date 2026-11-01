extends Node3D
# "El Repartidor": jefe original en patinete eléctrico. Embiste al jugador.

const U = preload("res://scripts/nucleo/util.gd")
const Ch = preload("res://scripts/jugador/character.gd")

var player
var hp := 100.0
var radius := 1.0
var speed := 3.6
var dying := false
var puppet := false        # copia de un enemigo que controla el anfitrión
var model: Node3D
var bag: Node3D
var wheels: Array = []
var hit_cd := 0.0
var dash_t := 3.0
var dashing := 0.0
var t := 0.0


func _ready() -> void:
	add_to_group("zombies")   # así las armas del jugador le afectan
	model = Node3D.new()
	add_child(model)
	var skin := Color(0.56, 0.36, 0.22)       # piel morena
	var jacket := Color(0.1, 0.55, 0.3)       # chaqueta verde de repartidor
	var pants := Color(0.18, 0.18, 0.2)
	var helmet := Color(0.95, 0.45, 0.05)     # casco naranja
	var black := Color(0.06, 0.06, 0.07)

	# ---- Patinete eléctrico ----
	U.box(model, Vector3(0.55, 0.1, 1.9), Vector3(0, 0.28, 0), Color(0.15, 0.15, 0.18))
	U.box(model, Vector3(0.6, 0.03, 1.7), Vector3(0, 0.2, 0), Color(0.1, 0.9, 1.0), true)
	_wheel(Vector3(0, 0.22, -0.95))
	_wheel(Vector3(0, 0.22, 0.95))
	U.box(model, Vector3(0.08, 1.1, 0.08), Vector3(0, 0.85, -0.9), Color(0.2, 0.2, 0.24))
	U.box(model, Vector3(0.8, 0.06, 0.06), Vector3(0, 1.4, -0.9), Color(0.2, 0.2, 0.24))
	U.sphere(model, 0.09, Vector3(0, 1.15, -0.98), Color(1.0, 0.95, 0.6), true)
	var lamp := SpotLight3D.new()
	lamp.position = Vector3(0, 1.15, -1.0)
	lamp.light_energy = 3.0
	lamp.spot_range = 14.0
	lamp.spot_angle = 35.0
	model.add_child(lamp)

	# ---- Repartidor grande y corpulento, de piel morena ----
	var jacket_m := U.mat(jacket)
	var pants_m := U.mat(pants)
	for sx in [-1.0, 1.0]:
		var ankle := Vector3(sx * 0.2, 0.48, 0.12)
		Ch.leg(model, Vector3(sx * 0.2, 1.3, 0.1), Vector3(sx * 0.23, 0.88, -0.02), ankle, pants_m, 1.5)
		Ch.shoe(model, ankle + Vector3(0, 0.04, 0), black, Color(0.9, 0.9, 0.9), 1.4)
	U.ellipsoid_m(model, Vector3(0.34, 0.2, 0.24), Vector3(0, 1.32, 0.08), pants_m)
	var body := Node3D.new()
	body.position = Vector3(0, 1.32, 0.08)
	body.rotation_degrees.x = -10.0          # inclinado hacia el manillar
	model.add_child(body)
	U.torso(body, 0.05, 0.72, 0.38, 0.27, jacket_m, 0.1)
	U.box(body, Vector3(0.82, 0.07, 0.04), Vector3(0, 0.3, -0.36), Color(0.95, 0.95, 0.3), true)   # franja reflectante
	U.box(body, Vector3(0.03, 0.62, 0.02), Vector3(0, 0.38, -0.34), Color(0.06, 0.3, 0.16))        # cremallera
	var collar := U.cylinder(body, 0.17, 0.08, Vector3(0, 0.8, 0.0), jacket.darkened(0.2))
	collar.scale.z = 0.9
	# mochila térmica cuadrada a la espalda
	bag = Node3D.new()
	bag.position = Vector3(0, 1.92, 0.6)
	model.add_child(bag)
	U.box(bag, Vector3(0.85, 0.85, 0.6), Vector3.ZERO, Color(0.1, 0.55, 0.3))
	U.box(bag, Vector3(0.87, 0.06, 0.62), Vector3(0, 0.2, 0), Color(0.95, 0.95, 0.3), true)
	U.box(bag, Vector3(0.5, 0.25, 0.02), Vector3(0, -0.1, 0.31), Color(0.95, 0.95, 0.95))       # logo
	for sx in [-1.0, 1.0]:
		U.box(body, Vector3(0.07, 0.6, 0.05), Vector3(sx * 0.22, 0.45, -0.3), Color(0.08, 0.3, 0.16))   # correas
	# brazos al manillar
	for sx in [-1.0, 1.0]:
		Ch.arm(body, Vector3(sx * 0.42, 0.68, 0.0), Vector3(sx * 0.52, 0.42, -0.42), Vector3(sx * 0.4, 0.26, -0.82),
			jacket_m, jacket_m, skin, 1.55, sx)
	# cabeza con casco naranja y gafas oscuras
	var hd: Dictionary = Ch.human_head(body, Vector3(0, 1.05, -0.05), 0.28, skin, "boss", black, false)
	var head: Node3D = hd["head"]
	var hel := U.sphere(head, 0.32, Vector3(0, 0.12, 0.03), helmet)
	hel.scale = Vector3(1.0, 0.72, 1.06)
	U.box(head, Vector3(0.04, 0.05, 0.6), Vector3(0, 0.33, 0.03), helmet.darkened(0.25))           # cresta
	U.limb(head, Vector3(-0.28, 0.0, 0.0), Vector3(0, -0.36, -0.08), 0.012, 0.012, black)           # correa
	U.limb(head, Vector3(0.28, 0.0, 0.0), Vector3(0, -0.36, -0.08), 0.012, 0.012, black)
	U.toonify(model, 0.014)


func _wheel(pos: Vector3) -> void:
	var pivot := Node3D.new()
	pivot.position = pos
	model.add_child(pivot)
	var w := U.cylinder(pivot, 0.22, 0.14, Vector3.ZERO, Color(0.08, 0.08, 0.1))
	w.rotation_degrees.z = 90.0
	wheels.append(pivot)


func _physics_process(delta: float) -> void:
	if U.stunned(self) or puppet:
		return    # cegado por Jan, o copia en otro PC (la mueve el anfitrión)
	if dying or player == null or player.dead:
		return
	t += delta
	hit_cd -= delta
	var tgt: Vector3 = U.next_point(global_position, player.global_position)
	var to_t: Vector3 = tgt - global_position
	to_t.y = 0.0
	var dir := to_t.normalized()
	rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 2.2 * delta)

	var spd := speed
	dash_t -= delta
	if dash_t <= 0.0:
		dashing = 0.8
		dash_t = randf_range(7.0, 10.0)
	if dashing > 0.0:
		dashing -= delta
		spd = speed * 1.6
	var fwd := Vector3(-sin(rotation.y), 0.0, -cos(rotation.y))
	global_position += fwd * spd * delta
	global_position = U.clamp_pos(global_position, radius)

	for w in wheels:
		w.rotation.x -= spd * delta * 4.5
	bag.rotation.z = sin(t * 9.0) * 0.06

	# Embestida
	var to_p: Vector3 = player.global_position - global_position
	to_p.y = 0.0
	if to_p.length() < radius + 0.7 and hit_cd <= 0.0:
		hit_cd = 1.0
		player.hurt(15.0)
		player.knock = to_p.normalized() * 11.0


func hurt(amount: float, dir: Vector3) -> void:
	if dying:
		return
	var game = get_tree().get_first_node_in_group("game")
	if game:
		game.add_points(int(clampf(amount * 2.0, 2.0, 10.0)))
	hp -= amount
	global_position += Vector3(dir.x, 0.0, dir.z) * amount * 0.01
	if hp <= 0.0:
		dying = true
		remove_from_group("zombies")
		if game:
			game.add_points(1500)
			game.zombie_killed(self)
		var tw := create_tween()
		tw.tween_property(model, "rotation:x", deg_to_rad(90.0), 0.5)
		tw.tween_property(model, "scale", Vector3.ZERO, 0.5)
		tw.tween_callback(queue_free)

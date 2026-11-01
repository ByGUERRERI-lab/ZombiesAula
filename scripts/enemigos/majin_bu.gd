extends Node3D
# "Majin Bu": jefe rosa y gordinflón (modelos/majin_buu.glb, sacado de Budokai
# Tenkaichi 3). Persigue al jugador, le vomita sushi y salta para aplastarlo con
# la barriga. Las animaciones del modelo no se usan: de "Quieto" solo se toma la
# postura inicial y todo el movimiento se calcula aquí, hueso a hueso.
# Cuando pierde la mitad de la vida se pincha un Ozempic: se deshincha y se
# transforma en Super Buu (modelos/personajes/super_buu.glb), más rápido y
# haciendo bastante más daño.

const U = preload("res://scripts/nucleo/util.gd")
const Ch = preload("res://scripts/jugador/character.gd")
const BuuScene = preload("res://modelos/majin_buu.glb")
const Js = preload("res://scripts/enemigos/jumpscare.gd")

const JUMP_TIME := 1.1
const VOMIT_TIME := 1.5      # dura el vómito entero...
const VOMIT_WIND := 0.5      # ...coge aire al principio...
const VOMIT_END := 0.3       # ...y al final ya no sale nada
const SCALE := 0.15          # el modelo viene en unidades del juego original (20 de alto)
const MOUTH_POS := Vector3(0.0, 15.6, 2.0)      # la boca del modelo es solo una línea en la textura
const SUPER_MODEL := "res://modelos/personajes/super_buu.glb"
const SUPER_SCALE := 1.1                         # el modelo mide 2,57 m: así mide unos 2,8
const SUPER_MOUTH := Vector3(0.03, 2.08, 0.16)   # boca en el .glb (que mira a +Z)
const HAND_BONE := "node_35"                     # mano derecha del modelo de Majin Bu
const TRANSFORM_TIME := 3.4
const SWAP_AT := 2.9                             # momento en que cambia de modelo
const SUPER_DMG := 1.7                           # multiplicador de daño de Super Buu
const BONES := {"spine": "node_16", "chest": "node_17", "head": "node_48",
	"hip_l": "node_8", "knee_l": "node_9", "hip_r": "node_12", "knee_r": "node_13",
	"arm_l": "node_19", "arm_r": "node_33"}

var player
var hp := 150.0
var radius := 1.0
var speed := 3.2
var dying := false
var puppet := false        # copia de un enemigo que controla el anfitrión
var model: Node3D
var body: Node3D
var skel: Skeleton3D
var pose := {}             # hueso: [índice, giro inicial, giro global inicial]
var mouth: Node3D
var last_pos := Vector3.ZERO
var moved := 0.0
var sample_t := 0.0
var t := 0.0
var walk_t := 0.0
var walk_k := 0.0
var lean := 0.0            # inclinación del cuerpo (> 0 = hacia delante)
var gape := 0.0            # boca abierta (0..1)
var swell := 0.0           # barriga hinchada al coger aire
var hit_cd := 0.0
var ball_cd := 3.0
var slam_cd := 6.0
var spew_cd := 0.0
var jumping := 0.0          # tiempo restante de salto (> 0 = en el aire)
var vomiting := 0.0         # tiempo restante de vómito
var max_hp := 0.0
var fase2 := false          # ya es Super Buu
var transforming := 0.0     # tiempo restante de la transformación
var dmg_k := 1.0
var super_body: Node3D
var pen: Node3D             # el boli de Ozempic
var glow: OmniLight3D
var clicked := false
var swapped := false
var steam_cd := 0.0


func _ready() -> void:
	add_to_group("zombies")   # así las armas del jugador le afectan
	max_hp = hp
	model = Node3D.new()
	add_child(model)
	body = BuuScene.instantiate()
	body.rotation.y = PI      # el modelo mira a +Z y en el juego se mira a -Z
	body.scale = Vector3.ONE * SCALE
	model.add_child(body)
	var anim := Ch.anim_of(body)
	anim.play("Quieto")
	anim.seek(0.0, true)
	anim.active = false
	skel = body.find_children("*", "Skeleton3D", true, false)[0]
	for key in BONES:
		var i := skel.find_bone(BONES[key])
		pose[key] = [i, skel.get_bone_pose_rotation(i), skel.get_bone_global_pose(i).basis.get_rotation_quaternion()]
	# Boca abierta pegada a la cabeza: solo se ve mientras vomita
	var att := BoneAttachment3D.new()
	att.bone_name = BONES["head"]
	skel.add_child(att)
	mouth = Node3D.new()
	mouth.position = skel.get_bone_global_pose(skel.find_bone(BONES["head"])).affine_inverse() * MOUTH_POS
	att.add_child(mouth)
	U.ellipsoid(mouth, Vector3(0.6, 0.65, 0.3), Vector3.ZERO, Color(0.3, 0.03, 0.08))
	mouth.visible = false
	last_pos = global_position


# Gira un hueso con ángulos medidos en el espacio del modelo (+Z = delante)
func _turn(key: String, e: Vector3) -> void:
	var b: Array = pose[key]
	skel.set_bone_pose_rotation(b[0], b[1] * (b[2].inverse() * Quaternion.from_euler(e) * b[2]))


# Se calcula con lo que se mueve de verdad, así también va en las copias de red
func _process(delta: float) -> void:
	if dying or U.stunned(self):
		return
	t += delta
	# se mide cada 0,1 s porque el movimiento va a 60 Hz y puede haber más fotogramas
	sample_t += delta
	if sample_t >= 0.1:
		moved = Vector2(global_position.x - last_pos.x, global_position.z - last_pos.z).length() / sample_t
		last_pos = global_position
		sample_t = 0.0
	if transforming > 0.0:
		_anim_transform(delta)
		return
	if puppet and vomiting > 0.0:
		vomiting -= delta
	walk_k = move_toward(walk_k, 1.0 if moved > 0.5 and vomiting <= 0.0 and jumping <= 0.0 else 0.0, 5.0 * delta)
	walk_t += minf(moved, 4.0) * 2.6 * delta

	var lean_to := 0.0
	var gape_to := 0.0
	var swell_to := 0.0
	if vomiting > VOMIT_TIME - VOMIT_WIND:
		lean_to = -0.3            # coge aire echándose atrás con la barriga hinchada
		gape_to = 0.3
		swell_to = 1.0
	elif vomiting > VOMIT_END:
		lean_to = 0.6 + sin(t * 30.0) * 0.05       # arcadas
		gape_to = 1.0
	var k := minf(1.0, 10.0 * delta)
	lean = lerpf(lean, lean_to, k)
	gape = lerpf(gape, gape_to, k)
	swell = lerpf(swell, swell_to, k)
	mouth.visible = gape > 0.05
	mouth.scale = Vector3.ONE * gape

	var air := 0.0
	if jumping > 0.0:
		air = sin((1.0 - jumping / JUMP_TIME) * PI)
	var s := sin(walk_t) * walk_k
	var c := cos(walk_t) * walk_k
	var breath := sin(t * 2.2) * 0.012
	if fase2:
		_anim_super(air, s, breath)
		return
	_turn("spine", Vector3(lean * 0.5, 0.0, s * 0.08))
	_turn("chest", Vector3(lean * 0.5, s * 0.15, 0.0))
	_turn("head", Vector3(lean * 0.3 + sin(t * 1.7) * 0.03, 0.0, -s * 0.06))
	_turn("hip_l", Vector3(s * 0.55 - air * 0.7, 0.0, 0.0))
	_turn("hip_r", Vector3(-s * 0.55 - air * 0.7, 0.0, 0.0))
	_turn("knee_l", Vector3(maxf(0.0, c) * 0.9 + air * 1.1, 0.0, 0.0))
	_turn("knee_r", Vector3(maxf(0.0, -c) * 0.9 + air * 1.1, 0.0, 0.0))
	var lift := air * 1.4 + gape * 0.5 + swell * 0.5
	_turn("arm_l", Vector3(-s * 0.45, 0.0, -lift))
	_turn("arm_r", Vector3(s * 0.45, 0.0, lift))
	model.rotation.z = s * 0.09
	body.scale = Vector3(1.0 + swell * 0.12, 1.0 + breath, 1.0 + swell * 0.12) * SCALE
	if jumping <= 0.0:
		model.position.y = absf(s) * 0.14      # camina dando botes


func _physics_process(delta: float) -> void:
	if U.stunned(self) or puppet:
		return    # cegado por Jan, o copia en otro PC (la mueve el anfitrión)
	if dying or player == null or player.dead:
		return
	if transforming > 0.0:
		return    # quieto mientras se pincha y se transforma
	hit_cd -= delta
	var to_p: Vector3 = player.global_position - global_position
	to_p.y = 0.0
	var dist := to_p.length()
	var same_region: bool = U.region(global_position) == U.region(player.global_position)

	# Salto para aplastar al jugador con la barriga
	if jumping > 0.0:
		jumping -= delta
		var k := 1.0 - jumping / JUMP_TIME
		model.position.y = sin(k * PI) * 1.5
		global_position += to_p.normalized() * minf(dist, speed * 2.2 * delta)
		global_position = U.clamp_pos(global_position, radius)
		if jumping <= 0.0:
			model.position.y = 0.0
			_land()
		return

	var tgt: Vector3 = U.next_point(global_position, player.global_position)
	var mv: Vector3 = tgt - global_position
	mv.y = 0.0
	var dir := mv.normalized()
	var face := dir
	if same_region:
		face = to_p.normalized()
	rotation.y = lerp_angle(rotation.y, atan2(-face.x, -face.z), 4.0 * delta)

	# Vomitando se queda parado, escupiendo sushi sin parar
	if vomiting > 0.0:
		vomiting -= delta
		spew_cd -= delta
		if vomiting < VOMIT_TIME - VOMIT_WIND and vomiting > VOMIT_END and spew_cd <= 0.0:
			spew_cd = 0.09
			_spew()
		return

	if dist > 1.6 or not same_region:
		global_position += dir * speed * delta
	global_position = U.clamp_pos(global_position, radius)

	ball_cd -= delta
	slam_cd -= delta
	if same_region and slam_cd <= 0.0 and dist < 9.0:
		slam_cd = randf_range(6.0, 9.0) * (0.65 if fase2 else 1.0)
		jumping = JUMP_TIME
	elif same_region and ball_cd <= 0.0 and dist < 16.0:
		ball_cd = randf_range(4.0, 6.0) * (0.7 if fase2 else 1.0)
		vomiting = VOMIT_TIME
		spew_cd = 0.0

	# Contacto: un barrigazo
	if dist < radius + 0.6 and hit_cd <= 0.0:
		hit_cd = 1.0
		player.hurt(15.0 * dmg_k)
		player.knock = to_p.normalized() * 10.0 * (1.0 + (dmg_k - 1.0) * 0.5)


# Una pieza de sushi que sale de la boca en parábola, con puntería aleatoria
func _spew() -> void:
	var origin := mouth.global_position - global_transform.basis.z * 0.2
	var target: Vector3 = player.global_position + Vector3(randf_range(-1.3, 1.3), 1.0, randf_range(-1.3, 1.3))
	var flight := clampf(origin.distance_to(target) / 13.0, 0.35, 1.0)
	var vel := (target - origin) / flight
	vel.y = (target.y - origin.y + 0.5 * Sushi.GRAV * flight * flight) / flight
	var b := Sushi.new()
	b.player = player
	b.dmg = 5.0 * dmg_k
	get_parent().add_child(b)
	b.global_position = origin
	b.vel = vel
	get_tree().get_first_node_in_group("game").net_projectile("sushi", origin, vel)


func _land() -> void:
	# onda expansiva rosa al caer
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.8
	tm.outer_radius = 1.0
	ring.mesh = tm
	var m := U.mat(Color(1.0, 0.45, 0.75), true)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = m
	get_parent().add_child(ring)
	ring.global_position = global_position + Vector3(0, 0.15, 0)
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(4.0, 1.0, 4.0), 0.45)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.45)
	tw.chain().tween_callback(ring.queue_free)
	var to_p: Vector3 = player.global_position - global_position
	to_p.y = 0.0
	if to_p.length() < 3.6 and player.global_position.y < 1.0:
		player.hurt(22.0 * dmg_k)
		player.knock = to_p.normalized() * 16.0
	model.scale = Vector3(1.25, 0.75, 1.25)
	create_tween().tween_property(model, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK)


func hurt(amount: float, dir: Vector3) -> void:
	if dying:
		return
	var game = get_tree().get_first_node_in_group("game")
	if game:
		game.add_points(int(clampf(amount * 2.0, 2.0, 10.0)))
	if transforming > 0.0:
		return    # mientras se transforma no le entran las balas
	hp -= amount
	if not fase2 and hp > 0.0 and hp <= max_hp * 0.5:
		start_transform()
		if Net.online and game:
			game.net_buu_transform(str(name))
		return
	if hp <= 0.0:
		dying = true
		remove_from_group("zombies")
		if game:
			game.add_points(2000)
			game.zombie_killed(self)
		# se infla, gira y explota en una nube rosa
		var tw := create_tween()
		tw.tween_property(model, "scale", Vector3.ONE * 1.4, 0.4)
		tw.parallel().tween_property(model, "rotation:y", TAU * 2.0, 0.8)
		tw.tween_callback(_puff)
		tw.tween_property(model, "scale", Vector3.ZERO, 0.15)
		tw.tween_callback(queue_free)


# ---------------- Ozempic y Super Buu ----------------
# Empieza la transformación (en todos los PCs: el anfitrión avisa a las copias)
func start_transform() -> void:
	if fase2 or transforming > 0.0 or dying:
		return
	transforming = TRANSFORM_TIME
	jumping = 0.0
	vomiting = 0.0
	model.position = Vector3.ZERO
	clicked = false
	swapped = false
	# el boli de Ozempic, en la mano derecha
	var att := BoneAttachment3D.new()
	att.bone_name = HAND_BONE
	skel.add_child(att)
	pen = _ozempic_pen()
	pen.position = Vector3(1.4, -0.3, 0.0)      # en la palma (unidades del modelo original)
	pen.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	pen.scale = Vector3.ZERO
	att.add_child(pen)
	glow = OmniLight3D.new()
	glow.light_color = Color(1.0, 0.45, 0.8)
	glow.light_energy = 0.0
	glow.omni_range = 7.0
	glow.position.y = 1.6
	add_child(glow)
	# el modelo nuevo se carga ya (oculto) para que no dé tirón al cambiar
	if ResourceLoader.exists(SUPER_MODEL):
		var ps = load(SUPER_MODEL)
		if ps is PackedScene:
			super_body = ps.instantiate()
			super_body.rotation.y = PI
			super_body.scale = Vector3.ONE * SUPER_SCALE
			super_body.visible = false
			model.add_child(super_body)
	var game = get_tree().get_first_node_in_group("game")
	if game:
		game._toast("¡Majin Bu se está pinchando un Ozempic!")


# Boli inyector: cuerpo gris claro, etiqueta y dosificador azules y la aguja
func _ozempic_pen() -> Node3D:
	var p := Node3D.new()
	var white := Color(0.9, 0.92, 0.94)
	var blue := Color(0.12, 0.36, 0.78)
	U.cylinder(p, 0.022, 0.15, Vector3.ZERO, white)
	U.cylinder(p, 0.0225, 0.05, Vector3(0, -0.02, 0), blue)                 # etiqueta
	var win := U.cylinder(p, 0.0228, 0.025, Vector3(0, 0.03, 0), Color(0.6, 0.85, 1.0))   # ventanita
	win.material_override.roughness = 0.1
	U.cylinder(p, 0.02, 0.03, Vector3(0, 0.09, 0), blue)                   # dosificador
	U.cylinder(p, 0.011, 0.02, Vector3(0, 0.115, 0), Color(0.08, 0.2, 0.5))    # botón
	U.cylinder(p, 0.016, 0.02, Vector3(0, -0.085, 0), Color(0.75, 0.77, 0.8))
	U.cylinder(p, 0.0016, 0.035, Vector3(0, -0.112, 0), Color(0.85, 0.85, 0.9))   # aguja
	U.toonify(p, 0.004)
	var holder := Node3D.new()
	holder.add_child(p)
	p.scale = Vector3.ONE * 2.2 / SCALE      # bien grande para que se vea (y el hueso va en unidades del modelo)
	return holder


func _anim_transform(delta: float) -> void:
	transforming -= delta
	var e := TRANSFORM_TIME - transforming
	if not swapped:
		# levanta el boli, se lo clava en el muslo y aguanta mientras se deshincha
		var lift := 0.0
		if e < 0.8:
			lift = smoothstep(0.0, 0.8, e) * 1.5
		elif e < 1.0:
			lift = lerpf(1.5, -0.2, (e - 0.8) / 0.2)
		else:
			lift = -0.2
		var shake := clampf((e - 1.0) / (SWAP_AT - 1.0), 0.0, 1.0)
		_turn("spine", Vector3(-0.1 * shake, 0.0, 0.0))
		_turn("chest", Vector3(-0.15 * shake, 0.0, 0.0))
		_turn("head", Vector3(-0.35 * shake + 0.15 * (1.0 - shake) * minf(e / 0.8, 1.0), 0.0, 0.0))
		_turn("hip_l", Vector3.ZERO)
		_turn("hip_r", Vector3.ZERO)
		_turn("knee_l", Vector3.ZERO)
		_turn("knee_r", Vector3.ZERO)
		_turn("arm_r", Vector3(0.0, 0.0, lift))
		_turn("arm_l", Vector3(0.0, 0.0, -0.1 - 0.8 * shake))
		if pen != null:
			if e < 1.9:
				pen.scale = Vector3.ONE * minf(1.0, e / 0.25)
			elif pen.visible:
				pen.visible = false       # lo tira
		if e >= 0.95 and not clicked:
			clicked = true
			_sound(U.make_shutter(), 0.6, 4.0)      # ¡clic!
		var d := smoothstep(1.0, 1.9, e)             # se deshincha
		var tremble := sin(t * 60.0) * 0.02 * shake
		body.scale = Vector3(1.0 - 0.22 * d + tremble, 1.0 - 0.04 * d, 1.0 - 0.22 * d - tremble) * SCALE
		model.position = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * 0.05 * shake
		if glow:
			glow.light_energy = shake * 8.0
		steam_cd -= delta
		if e > 1.3 and steam_cd <= 0.0:
			steam_cd = 0.07
			_steam()
		if e >= SWAP_AT:
			_swap()
	elif super_body != null:
		var k := clampf((e - SWAP_AT) / (TRANSFORM_TIME - SWAP_AT), 0.0, 1.0)
		var c1 := 1.70158
		var eb := 1.0 + (c1 + 1.0) * pow(k - 1.0, 3.0) + c1 * pow(k - 1.0, 2.0)
		super_body.scale = Vector3.ONE * SUPER_SCALE * (0.55 + 0.45 * eb)
		if glow:
			glow.light_energy = 14.0 * (1.0 - k)
	if transforming <= 0.0:
		_end_transform()


func _swap() -> void:
	swapped = true
	model.position = Vector3.ZERO
	_puff()
	_sound(Js.make_boom(), 1.0, 8.0)
	_sound(U.make_powerup(), 0.55, 6.0)
	var game = get_tree().get_first_node_in_group("game")
	if game:
		game._toast("¡SUPER BUU!\nAhora pega mucho más fuerte")
		game.shake(0.3)
	if super_body == null:
		return      # sin el modelo nuevo se queda el de siempre, deshinchado
	body.visible = false
	super_body.visible = true
	super_body.scale = Vector3.ONE * SUPER_SCALE * 0.55
	# boca nueva para el vómito
	mouth = Node3D.new()
	mouth.position = SUPER_MOUTH
	super_body.add_child(mouth)
	U.ellipsoid(mouth, Vector3(0.085, 0.1, 0.05), Vector3.ZERO, Color(0.3, 0.03, 0.08))
	mouth.visible = false


func _end_transform() -> void:
	transforming = 0.0
	fase2 = true
	dmg_k = SUPER_DMG
	speed *= 1.45
	if super_body != null:
		radius = 0.85
		model.rotation = Vector3.ZERO
	if glow:
		glow.queue_free()
		glow = null


# Super Buu no tiene huesos: se mueve entero (botes, balanceo e inclinación)
func _anim_super(air: float, s: float, breath: float) -> void:
	if super_body == null or not super_body.visible:
		body.scale = Vector3(0.78, 0.96 + breath, 0.78) * SCALE
		if jumping <= 0.0:
			model.position.y = absf(s) * 0.14
		return
	model.rotation.x = -(0.05 + lean * 0.35 + air * 0.15)
	model.rotation.z = s * 0.07
	super_body.scale = Vector3(1.0 + swell * 0.1, 1.0 + breath, 1.0 + swell * 0.1) * SUPER_SCALE
	if jumping <= 0.0:
		model.position.y = absf(s) * 0.12


# Vapor rosa que le sale mientras le hace efecto
func _steam() -> void:
	var p := U.sphere(get_parent(), randf_range(0.12, 0.25), global_position + Vector3(randf_range(-0.8, 0.8), randf_range(0.8, 2.6), randf_range(-0.8, 0.8)),
		Color(1.0, 0.7, 0.88), true)
	var tw := p.create_tween().set_parallel(true)
	tw.tween_property(p, "scale", Vector3.ONE * 2.5, 0.7)
	tw.tween_property(p, "position:y", p.position.y + 1.4, 0.7)
	tw.chain().tween_callback(p.queue_free)


func _sound(stream: AudioStream, pitch: float, unit: float) -> void:
	var a := AudioStreamPlayer3D.new()
	a.stream = stream
	a.pitch_scale = pitch
	a.unit_size = unit
	a.position.y = 1.5
	add_child(a)
	a.play()
	a.finished.connect(a.queue_free)


func _puff() -> void:
	for i in 10:
		var s := U.sphere(get_parent(), randf_range(0.4, 0.8), global_position + Vector3(randf_range(-1, 1), randf_range(0.5, 3.0), randf_range(-1, 1)),
			Color(1.0, 0.6, 0.8), true)
		var tw := s.create_tween().set_parallel(true)
		tw.tween_property(s, "scale", Vector3.ONE * 2.0, 0.6)
		tw.tween_property(s, "position:y", s.position.y + 1.5, 0.6)
		tw.chain().tween_callback(s.queue_free)


# Pieza de sushi que vomita Majin Bu (nigiri de salmón, maki o nigiri de atún)
class Sushi extends Node3D:
	const GRAV := 9.0
	var vel := Vector3.ZERO
	var player
	var life := 2.5
	var spin := Vector3.ZERO
	var dmg := 5.0

	func _ready() -> void:
		var rice := Color(0.97, 0.96, 0.92)
		var pivot := Node3D.new()
		pivot.scale = Vector3.ONE * 1.6      # bien grande para que se vea venir
		add_child(pivot)
		match randi() % 3:
			0:   # nigiri de salmón: bola de arroz y lámina naranja con vetas blancas
				U.ellipsoid(pivot, Vector3(0.09, 0.05, 0.13), Vector3.ZERO, rice)
				var fish := U.ellipsoid(pivot, Vector3(0.1, 0.025, 0.15), Vector3(0, 0.045, 0), Color(1.0, 0.5, 0.25))
				fish.rotation_degrees.x = 4.0
				for i in 4:
					var vein := U.box(pivot, Vector3(0.17, 0.006, 0.012), Vector3(0, 0.068, -0.09 + i * 0.06), Color(1.0, 0.85, 0.75))
					vein.rotation_degrees.y = 20.0
			1:   # maki: alga por fuera, arroz y relleno de salmón y pepino
				var nori := U.cylinder(pivot, 0.09, 0.1, Vector3.ZERO, Color(0.06, 0.12, 0.08))
				nori.rotation_degrees.x = 90.0
				var r1 := U.cylinder(pivot, 0.075, 0.102, Vector3.ZERO, rice)
				r1.rotation_degrees.x = 90.0
				var c1 := U.cylinder(pivot, 0.028, 0.104, Vector3(0.012, 0.0, 0), Color(1.0, 0.45, 0.2))
				c1.rotation_degrees.x = 90.0
				var c2 := U.cylinder(pivot, 0.018, 0.104, Vector3(-0.025, 0.01, 0), Color(0.3, 0.7, 0.25))
				c2.rotation_degrees.x = 90.0
			_:   # nigiri de atún con tira de alga
				U.ellipsoid(pivot, Vector3(0.09, 0.05, 0.13), Vector3.ZERO, rice)
				U.ellipsoid(pivot, Vector3(0.1, 0.025, 0.15), Vector3(0, 0.045, 0), Color(0.8, 0.12, 0.18))
				U.box(pivot, Vector3(0.19, 0.11, 0.035), Vector3(0, 0.01, 0), Color(0.06, 0.12, 0.08))
		U.toonify(pivot, 0.006)
		spin = Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9))

	func _physics_process(delta: float) -> void:
		vel.y -= GRAV * delta
		global_position += vel * delta
		rotation += spin * delta
		life -= delta
		var p := global_position
		if life <= 0.0 or p.y < 0.0 or p.y > 4.0:
			queue_free()
			return
		if player != null and not player.dead:
			var pp: Vector3 = player.global_position
			var dx := p.x - pp.x
			var dz := p.z - pp.z
			if dx * dx + dz * dz < 0.45 and p.y > pp.y - 0.2 and p.y < pp.y + 2.1:
				player.hurt(dmg)
				queue_free()

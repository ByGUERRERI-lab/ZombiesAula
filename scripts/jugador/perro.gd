extends Node3D
# El perro acompañante (un bichón maltés blanco, como el de la foto). Te sigue a todas
# partes (también por las puertas, con las rutas de los zombis), trota, se sienta
# cuando te paras, mueve el rabo, ladra a los zombis que se acercan y les muerde
# los tobillos (poco daño, pero ayuda). No le pueden hacer daño. Si se queda muy
# atrás, aparece a tu lado. Mirándolo de cerca: [E] acariciar.
# Modelo: modelos/personajes/perro.glb (una pieza con esqueleto). El pelo largo se
# hace con "capas" (shells): copias de la malla, cada una un poco más inflada, que
# solo dejan ver los pelos -> pelo de verdad.

const U = preload("res://scripts/nucleo/util.gd")

const NOMBRE := "Mac"           # si se le pone nombre, sale encima de su cabeza
const DISTANCIA := 1.6         # a cuánto se queda de ti
const VEL := 6.8               # trota casi tan rápido como corres andando
const MORDISCO := 2.0          # daño de cada mordisco
const CAPAS := 14              # capas de pelo
const PELO := 0.042            # largo del pelo (m)

var game
var player
var modelo: Node3D
var cabeza: Node3D
var t := 0.0
var paso := 0.0
var k_mov := 0.0
var sentado := 0.0
var meneo := 0.0               # lo contento que está (rabo)
var ladrido_cd := 2.0
var mordisco_cd := 0.0
var objetivo = null            # zombi al que va a morder
var snd: AudioStreamPlayer3D
var item := {}                 # interactuable para acariciarlo
var corazones := 0.0
var mats: Array = []           # material de cada capa de pelo


func _ready() -> void:
	_construir()
	snd = AudioStreamPlayer3D.new()
	snd.stream = _guau()
	snd.unit_size = 6.0
	snd.position.y = 0.35
	add_child(snd)
	item = {"type": "perro", "pos": global_position, "done": true}
	game.interactables.append(item)
	if NOMBRE != "":
		var tag := Label3D.new()
		tag.text = NOMBRE
		tag.font_size = 28
		tag.pixel_size = 0.0035
		tag.outline_size = 6
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.modulate = Color(1.0, 0.85, 0.9)
		tag.position.y = 0.72
		add_child(tag)


# ---------------- modelo ----------------
# modelos/personajes/perro.glb: malla de una pieza con esqueleto (17 huesos). El pelo
# son CAPAS copias de la malla (mismo esqueleto) con el shader de pelo.
const MODELO := "res://modelos/personajes/perro.glb"
var skel: Skeleton3D
var hb := {}                   # nombre de hueso -> índice
var reposo := {}               # índice -> posición de reposo

func _construir() -> void:
	modelo = Node3D.new()
	add_child(modelo)
	var inst: Node3D = load(MODELO).instantiate()
	inst.rotation.y = PI           # el .glb mira a +Z y en el juego se mira a -Z
	modelo.add_child(inst)
	skel = inst.find_children("*", "Skeleton3D", true, false)[0]
	for i in skel.get_bone_count():
		hb[skel.get_bone_name(i)] = i
		reposo[i] = skel.get_bone_pose_position(i)
	var mi: MeshInstance3D = inst.find_children("*", "MeshInstance3D", true, false)[0]
	var sh := Shader.new()
	sh.code = PELO_SHADER
	for i in CAPAS + 1:
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("capa", float(i) / CAPAS)
		m.set_shader_parameter("largo", PELO)
		mats.append(m)
		var capa_mi: MeshInstance3D = mi if i == 0 else mi.duplicate()
		capa_mi.material_override = m
		if i > 0:
			capa_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.get_parent().add_child(capa_mi)
	# cara (ojos, trufa, boca) y la diadema, pegados al hueso de la cabeza
	var att := BoneAttachment3D.new()
	att.bone_name = "Cabeza"
	skel.add_child(att)
	cabeza = Node3D.new()
	cabeza.position = Vector3(0, 0.0, 0.0)
	att.add_child(cabeza)
	var negro := StandardMaterial3D.new()
	negro.albedo_color = Color(0.02, 0.02, 0.025)
	negro.roughness = 0.12
	negro.metallic = 0.2
	# (espacio del .glb: delante es +Z; la cabeza está en (0, 0,36, 0,2))
	U.ellipsoid_m(cabeza, Vector3(0.019, 0.015, 0.013), Vector3(0, -0.006, 0.118), negro)     # trufa
	for sx in [-1.0, 1.0]:
		var ojo := U.ellipsoid_m(cabeza, Vector3(0.016, 0.016, 0.012), Vector3(sx * 0.034, 0.028, 0.072), negro)
		var brillo := U.sphere(ojo, 0.0035, Vector3(0.004, 0.005, 0.01), Color(1, 1, 1), true)
		brillo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var boca := U.ellipsoid_m(cabeza, Vector3(0.02, 0.005, 0.01), Vector3(0, -0.036, 0.1), negro)
	boca.rotation_degrees.x = -10.0
	_diadema()


# Diadema de fiesta con un lazo rojo de corazones blancos
func _diadema() -> void:
	var d := Node3D.new()
	d.position = Vector3(0, 0.015, 0.0)
	d.rotation_degrees.y = 180.0
	cabeza.add_child(d)
	var aro := TorusMesh.new()
	aro.inner_radius = 0.086
	aro.outer_radius = 0.093
	aro.rings = 24
	var mi := MeshInstance3D.new()
	mi.mesh = aro
	mi.rotation_degrees.x = 90.0
	var neg := U.mat(Color(0.04, 0.04, 0.05))
	mi.material_override = neg
	d.add_child(mi)
	var rojo := StandardMaterial3D.new()
	rojo.albedo_color = Color(0.85, 0.05, 0.1)
	rojo.roughness = 0.65
	rojo.metallic = 0.0
	var blanco := U.mat(Color(1, 1, 1))
	var lazo := Node3D.new()
	lazo.position = Vector3(0, 0.092, 0.0)
	lazo.rotation_degrees.x = -12.0
	d.add_child(lazo)
	for sx in [-1.0, 1.0]:
		var ala := U.ellipsoid_m(lazo, Vector3(0.055, 0.04, 0.022), Vector3(sx * 0.05, 0.0, 0.0), rojo)
		ala.rotation_degrees.z = sx * -18.0
		# corazoncitos blancos
		for c in [Vector2(0.03, 0.012), Vector2(0.065, -0.012), Vector2(0.05, 0.022)]:
			var h := Node3D.new()
			h.position = Vector3(sx * c.x, c.y, -0.021)
			lazo.add_child(h)
			for hx in [-1.0, 1.0]:
				U.ellipsoid_m(h, Vector3(0.0045, 0.0045, 0.002), Vector3(hx * 0.0035, 0.002, 0), blanco)
			var p := U.ellipsoid_m(h, Vector3(0.0045, 0.0045, 0.002), Vector3(0, -0.002, 0), blanco)
			p.rotation_degrees.z = 45.0
			p.scale = Vector3(0.0045, 0.0045, 0.002)
	U.ellipsoid_m(lazo, Vector3(0.018, 0.02, 0.02), Vector3.ZERO, rojo)     # nudo


# ---------------- comportamiento ----------------
func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	t += delta
	ladrido_cd -= delta
	mordisco_cd -= delta
	var yo := global_position
	var pp: Vector3 = player.global_position
	# ¿algún zombi cerca de ti o de él? -> a por él
	objetivo = null
	var mejor := 5.0
	for z in get_tree().get_nodes_in_group("zombies"):
		if z.dying:
			continue
		var dz: float = minf(z.global_position.distance_to(yo), z.global_position.distance_to(pp) + 1.0)
		if dz < mejor:
			mejor = dz
			objetivo = z
	var meta: Vector3
	var quiero := 0.0
	if objetivo != null and not player.dead:
		meta = objetivo.global_position
		quiero = 0.7
		if ladrido_cd <= 0.0:
			ladrar()
			ladrido_cd = randf_range(1.2, 2.5)
		if yo.distance_to(meta) < objetivo.radius + 0.35 and mordisco_cd <= 0.0:
			mordisco_cd = 1.0
			var dir: Vector3 = (meta - yo).normalized()
			game.damage_enemy(objetivo, MORDISCO, dir)
			_saltito()
	else:
		# detrás de ti, un poco a un lado
		var atras: Vector3 = player.global_transform.basis.z
		atras.y = 0.0
		meta = pp + atras.normalized() * DISTANCIA + player.global_transform.basis.x * 0.5
		quiero = 0.0
	# si se ha quedado muy lejos (o en otra planta), aparece a tu lado
	if yo.distance_to(pp) > 18.0 or absf(yo.y - pp.y) > 2.0:
		global_position = pp + player.global_transform.basis.z * 1.2
		return
	var hacia: Vector3 = U.next_point(yo, meta)
	var mv := hacia - yo
	mv.y = 0.0
	var dist := Vector2(meta.x - yo.x, meta.z - yo.z).length()
	var v := 0.0
	if dist > 0.35 + quiero * 0.3:
		v = clampf(dist * 3.0, 0.0, VEL * (1.15 if objetivo != null else 1.0))
		if player.sprinting:
			v = minf(v * 1.4, 10.5)
	var nueva := yo + mv.normalized() * v * delta if mv.length() > 0.01 else yo
	nueva = U.clamp_pos(nueva, 0.2)
	global_position = Vector3(nueva.x, pp.y if absf(pp.y - yo.y) < 0.5 else yo.y, nueva.z)
	# mirar hacia donde va, o hacia ti si está parado
	var mira: Vector3 = mv if v > 0.2 else (pp - yo)
	if mira.length() > 0.05:
		rotation.y = lerp_angle(rotation.y, atan2(-mira.x, -mira.z), minf(1.0, 8.0 * delta))
	k_mov = move_toward(k_mov, clampf(v / VEL, 0.0, 1.0), 5.0 * delta)
	paso += v * delta * 7.5
	sentado = move_toward(sentado, 1.0 if v < 0.1 and objetivo == null else 0.0, (1.5 if v < 0.1 else 6.0) * delta)
	meneo = move_toward(meneo, 1.0 if (objetivo != null or corazones > 0.0 or dist < 2.5) else 0.4, delta)
	corazones = maxf(0.0, corazones - delta)
	# acariciar: solo si lo estás mirando de cerca
	var cam: Camera3D = player.cam
	var a_el := (yo + Vector3(0, 0.3, 0)) - cam.global_position
	var mirando: bool = a_el.length() < 2.2 and (-cam.global_transform.basis.z).dot(a_el.normalized()) > 0.85
	item["pos"] = Vector3(pp.x, 0, pp.z) if mirando else yo      # así gana a lo demás solo si lo miras
	item["done"] = not mirando or player.dead


func _process(_delta: float) -> void:
	if skel == null:
		return
	# (huesos en el espacio del .glb: delante +Z; girar en X negativo = hacia delante)
	var trote := k_mov * (1.0 - sentado)
	for n in [["DelI", 0.0], ["DelD", PI], ["TrasI", PI], ["TrasD", 0.0]]:
		var f: float = paso + n[1]
		var s := sin(f)
		var pata: float = -s * 0.65 * trote
		var pie: float = maxf(0.0, cos(f)) * 0.7 * trote
		if str(n[0]).begins_with("Tras"):
			pie = -pie
			pata += -1.25 * sentado              # sentado: patas de atrás dobladas hacia delante
			pie += 1.2 * sentado
		else:
			pata += 0.35 * sentado
		_rot("Pata" + n[0], Vector3(pata, 0, 0))
		_rot("Pie" + n[0], Vector3(pie, 0, 0))
	# tronco: bota al trotar, se sienta (delante arriba) cuando paras
	_rot("Raiz", Vector3(-0.42 * sentado + sin(paso * 2.0) * 0.03 * trote, sin(paso) * 0.05 * trote, 0))
	var r: int = hb.get("Raiz", -1)
	if r >= 0:
		skel.set_bone_pose_position(r, reposo[r] + Vector3(0, absf(sin(paso)) * 0.012 * trote - 0.05 * sentado, -0.03 * sentado))
	_rot("Pecho", Vector3(0.12 * sentado, 0, 0))
	_rot("Cuello", Vector3(0.15 * sentado - 0.05 * trote, 0, 0))
	_rot("Cabeza", Vector3(sin(t * 0.7) * 0.05 + cab_x, sin(t * 0.31) * 0.25 * sentado, sin(t * 0.43) * 0.15 * sentado))
	# orejas que se mueven con el trote
	var oreja := 0.08 + absf(sin(paso)) * 0.3 * trote
	_rot("Oreja_I", Vector3(0.15 * trote, 0, -oreja))
	_rot("Oreja_D", Vector3(0.15 * trote, 0, oreja))
	# rabo
	var w := sin(t * (15.0 if meneo > 0.7 else 6.0)) * 0.5 * meneo
	_rot("Cola1", Vector3(0.1 * sentado, w, 0))
	_rot("Cola2", Vector3(0, w * 0.8, 0))


var cab_x := 0.0
func _rot(nombre: String, e: Vector3) -> void:
	var i: int = hb.get(nombre, -1)
	if i >= 0:
		skel.set_bone_pose_rotation(i, Quaternion.from_euler(e))


func ladrar() -> void:
	snd.pitch_scale = randf_range(0.95, 1.15)
	snd.play()
	var tw := create_tween()
	tw.tween_property(self, "cab_x", -0.3, 0.06)
	tw.tween_property(self, "cab_x", 0.0, 0.12)


func _saltito() -> void:
	var tw := modelo.create_tween()
	tw.tween_property(modelo, "position:y", 0.08, 0.08)
	tw.tween_property(modelo, "position:y", 0.0, 0.12)


# Le acaricias: corazones, rabo a tope y un ladrido contento
func acariciar() -> void:
	corazones = 2.0
	meneo = 1.0
	ladrar()
	for i in 4:
		var l := Label3D.new()
		l.text = "♥"
		l.font_size = 64
		l.pixel_size = 0.003
		l.modulate = Color(1.0, 0.3, 0.45)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		add_child(l)
		l.position = Vector3(randf_range(-0.12, 0.12), 0.55, randf_range(-0.1, 0.1))
		var tw := l.create_tween().set_parallel(true)
		tw.tween_property(l, "position:y", 0.95 + randf() * 0.2, 1.0).set_delay(i * 0.12)
		tw.tween_property(l, "modulate:a", 0.0, 1.0).set_delay(i * 0.12)
		tw.chain().tween_callback(l.queue_free)


# "¡Guau!" de perro pequeño: dos golpes de tono que baja, con un poco de ruido
func _guau() -> AudioStreamWAV:
	var rate := 22050
	var data := PackedByteArray()
	var golpes := [[0.0, 0.11], [0.16, 0.1]]
	var n := int(rate * 0.3)
	data.resize(n * 2)
	var ph := 0.0
	for i in n:
		var tt := float(i) / rate
		var v := 0.0
		for g in golpes:
			var u: float = tt - g[0]
			if u >= 0.0 and u < g[1]:
				var k: float = u / float(g[1])
				var env: float = sin(k * PI) * (1.0 - k * 0.4)
				var f := lerpf(950.0, 520.0, k)
				ph += TAU * f / rate
				v += env * (0.65 * sin(ph) + 0.25 * sin(ph * 2.0) + 0.15 * sin(ph * 3.1) + 0.12 * randf_range(-1, 1))
		var s := int(clampf(v * 0.7, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, s)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w


# Pelo con capas: cada capa se infla un poco más; cada "celda" de 4 mm de la piel es
# un pelo de largo distinto que se va afinando hacia la punta. Las puntas caen
# (pelo largo de maltés). COLOR = posición de reposo (así el pelo no "nada" al
# moverse) y COLOR.a = 1 en el cuerpo y menos en la cara (pelo más corto).
const PELO_SHADER := """
shader_type spatial;
render_mode cull_back, depth_draw_opaque;
uniform float capa = 0.0;
uniform float largo = 0.04;
varying vec3 reposo;
varying float c;
float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
void vertex() {
	c = capa;
	reposo = COLOR.rgb * 0.56;
	float l = largo * capa * COLOR.a;
	vec3 nw = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 off = nw * l + vec3(0.0, -1.0, 0.0) * capa * capa * largo * COLOR.a * 1.4;
	VERTEX += (inverse(MODEL_MATRIX) * vec4(off, 0.0)).xyz;
}
void fragment() {
	vec3 q = reposo * 190.0;
	vec3 cel = floor(q);
	vec3 f = fract(q) - 0.5;
	float rnd = hash(cel);
	float largo_pelo = 0.6 + 0.4 * rnd;
	vec3 j = vec3(hash(cel + 1.3), hash(cel + 2.7), hash(cel + 4.1)) - 0.5;
	float grosor = 0.82 * pow(max(1.0 - c / largo_pelo, 0.0), 0.6);
	if (c > 0.0 && (c > largo_pelo || length(f - j * 0.3) > grosor)) {
		discard;
	}
	// blanco roto mate, con la raíz bastante más oscura para que se vea el volumen
	// (sin brillo ni luz trasera: antes con focos fuertes se quemaba a blanco)
	ALBEDO = mix(vec3(0.17, 0.165, 0.155), vec3(0.5, 0.49, 0.47), smoothstep(0.0, 0.65, c)) * (0.85 + 0.15 * rnd);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	AO = mix(0.25, 1.0, c);
	AO_LIGHT_AFFECT = 0.9;
}
"""

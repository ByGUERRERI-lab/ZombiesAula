extends Node3D
# Arma en primera persona (solo la ve el jugador local, va pegada a la cámara).
# Lleva las manos y los antebrazos del personaje que lleves (color de la manga y de
# la piel, o los guantes del traje de Juan) agarrando cada arma por SU empuñadura y
# SU guardamanos (grip / fore en weapons.gd), así cada arma se coge como toca.
# Además: apuntar con clic derecho (la mira queda en el centro de la pantalla),
# balanceo al andar, retroceso al disparar, recarga, cambio de arma y sprint.
# El arma "de verdad" (gun_holder) la siguen viendo los demás y tú en tercera persona.

const U = preload("res://scripts/nucleo/util.gd")
const W = preload("res://scripts/jugador/weapons.gd")
const Ch = preload("res://scripts/jugador/character.gd")

const ESCALA := 0.72                           # el arma de primera persona, algo más pequeña
const CADERA := Vector3(0.19, -0.2, -0.42)    # dónde queda la mano derecha sin apuntar
const OJO := 0.36                             # distancia de la mira trasera al ojo al apuntar
const BAJO_OJO := 0.04                         # la mira trasera algo por debajo del ojo (el arma se inclina un poco para que la delantera quede en el centro)
const CULATA_MIN := 0.1                        # distancia mínima de la parte de atrás del arma a la cámara
# cómo se coloca el arma al recargar: [desplazamiento, giro]
const POSE_RECARGA := {
	"cargador": [Vector3(-0.09, 0.1, 0.02), Vector3(0.3, 0.25, -0.65)],          # pistolas: la subes y la giras
	"cargador_largo": [Vector3(-0.06, 0.05, 0.02), Vector3(0.18, 0.15, -0.4)],
	"cartuchos": [Vector3(-0.04, 0.04, 0.0), Vector3(0.12, 0.12, -0.45)],
	"frontal": [Vector3(-0.03, -0.1, 0.05), Vector3(-0.35, 0.3, 0.05)],         # la boca hacia abajo, hacia la mano
}
const CODO_D := Vector3(0.3, -0.46, 0.08)     # codos (fuera de la pantalla, abajo)
const CODO_I := Vector3(-0.28, -0.48, 0.0)

var player
var arma := ""
var pivote: Node3D          # se mueve entero (apuntar, balanceo, retroceso...)
var modelo: Node3D
var mano_d: Node3D
var mano_i: Node3D
var ante_d: MeshInstance3D
var ante_i: MeshInstance3D
var canones: Node3D         # la minigun gira
var kick := 0.0
var cambio := 1.0           # 1 = bajada (al sacar otra arma), 0 = en su sitio
var recarga := 0.0
var t := 0.0
var paso := 0.0
var giro := 0.0
var piel_key := ""
var atras := 0.0            # lo que sobresale el arma por detrás de la empuñadura (culata)
var abajo := 0.0            # el punto más bajo del arma (para saber dónde va el cargador)
# recarga
var rec_dur := 0.0          # cuánto dura la recarga que está en marcha (0 = no recarga)
var rec_tipo := "cargador"  # cargador | cartuchos | frontal
var cargador_viejo: Node3D  # el que se cae
var cargador_nuevo: Node3D  # el que trae la mano izquierda
var mano_i_reposo := Vector3.ZERO
var boca := Vector3.ZERO    # por dónde entra la munición (espacio del pivote)
# beber
var beb: Node3D             # lata + mano + manga (cuelga de la cámara, no del arma)
var beb_lata: Node3D
var beb_mano: Node3D
var beb_ante: MeshInstance3D
var beb_t := -1.0           # segundos desde que empezaste a beber (-1 = no bebes)
const BEB_DUR := 1.6


func _ready() -> void:
	pivote = Node3D.new()
	pivote.scale = Vector3.ONE * ESCALA
	add_child(pivote)
	ante_d = _antebrazo()
	ante_i = _antebrazo()


func _antebrazo() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.036
	cm.bottom_radius = 0.05
	cm.height = 1.0
	cm.radial_segments = 14
	mi.mesh = cm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


# Pone el arma id con las manos en su sitio
func poner(id: String) -> void:
	arma = id
	if modelo != null:
		modelo.queue_free()
	for m in [mano_d, mano_i]:
		if m != null:
			m.queue_free()
	modelo = U.gun_model(id)
	_sin_sombra(modelo)
	pivote.add_child(modelo)
	var d: Dictionary = W.DATA[id]
	var grip: Vector3 = d.get("grip", Vector3(0, -0.08, 0.03))
	modelo.position = -grip                     # la empuñadura en el origen del pivote
	canones = modelo.find_child("Canones", true, false)
	var cols := Ch.colores_brazo(player.skin_data)
	piel_key = str(cols)
	mano_d = _mano(pivote, Vector3.ZERO, cols[1], false)
	mano_i_reposo = (d.get("fore", Vector3(-0.012, -0.105, 0.05)) as Vector3) - grip
	mano_i = _mano(pivote, mano_i_reposo, cols[1], true)
	var bb: AABB = U.node_aabb(modelo, modelo.transform)
	atras = maxf(bb.end.z, 0.0)
	abajo = bb.position.y
	_preparar_recarga(id, d)
	for a in [ante_d, ante_i]:
		var m := StandardMaterial3D.new()
		m.albedo_color = cols[0]
		m.roughness = 0.85
		a.material_override = m
	cambio = 1.0


func _sin_sombra(n: Node) -> void:
	if n is GeometryInstance3D:
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_sin_sombra(c)


# Puño cerrado: palma, nudillos, dedos alrededor de la empuñadura y el pulgar
func _mano(padre: Node3D, pos: Vector3, piel: Color, izquierda: bool) -> Node3D:
	var h := Node3D.new()
	h.position = pos
	padre.add_child(h)
	var m := U.mat(piel)
	m.roughness = 0.7
	var lado := -1.0 if izquierda else 1.0
	if izquierda:
		# la izquierda sujeta desde abajo, con la palma hacia arriba
		U.ellipsoid_m(h, Vector3(0.042, 0.022, 0.055), Vector3(0, -0.028, 0.0), m)
		for i in 4:
			U.ellipsoid_m(h, Vector3(0.011, 0.012, 0.03), Vector3(0.03 + i * 0.0, -0.005 + i * 0.0, -0.035 + i * 0.022), m)
		U.ellipsoid_m(h, Vector3(0.012, 0.012, 0.03), Vector3(-0.03, -0.0, -0.01), m)
	else:
		U.ellipsoid_m(h, Vector3(0.03, 0.05, 0.042), Vector3(0.012 * lado, -0.005, 0.012), m)      # palma
		for i in 4:                                                                                  # dedos
			U.ellipsoid_m(h, Vector3(0.026, 0.012, 0.014), Vector3(-0.004, 0.022 - i * 0.022, -0.026), m)
		var pulgar := U.ellipsoid_m(h, Vector3(0.011, 0.03, 0.011), Vector3(-0.026 * lado, 0.03, -0.006), m)
		pulgar.rotation_degrees.x = -40.0
	_sin_sombra(h)
	return h


func disparo() -> void:
	kick = 1.0


func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var cam: Camera3D = player.cam
	var id: String = player.current_weapon_id()
	_beber_anim(delta, cam)
	var mostrar: bool = player.is_local and not player.third_person and cam.current \
			and not player.dead and not player.downed and W.DATA.has(id) \
			and player.gun_holder.visible          # el pádel (y otros) esconden el arma
	visible = mostrar
	if not mostrar:
		return
	if id != arma or str(Ch.colores_brazo(player.skin_data)) != piel_key:
		poner(id)
	var d: Dictionary = W.DATA[id]
	t += delta
	var ads: float = player.ads_k
	kick = move_toward(kick, 0.0, delta * 9.0)
	cambio = move_toward(cambio, 0.0, delta * 4.0)
	recarga = move_toward(recarga, 1.0 if player.reload_t > 0.0 else 0.0, delta * 6.0)
	if player.reload_t > 0.0 and rec_dur <= 0.0:
		rec_dur = player.reload_t                   # acaba de empezar una recarga
	elif player.reload_t <= 0.0:
		rec_dur = 0.0
	var rp := 0.0 if rec_dur <= 0.0 else clampf(1.0 - player.reload_t / rec_dur, 0.0, 1.0)
	var run: float = player.run_k
	# balanceo al andar (mucho menos apuntando)
	var vel: Vector3 = player.velocity
	var v := Vector2(vel.x, vel.z).length()
	if v > 0.5 and player.is_on_floor():
		paso += delta * v * 1.6
	var mov := clampf(v / 6.0, 0.0, 1.0) * (1.0 - 0.85 * ads)
	var bob := Vector3(sin(paso) * 0.012, -absf(cos(paso)) * 0.01, 0.0) * mov
	bob.y += sin(t * 1.6) * 0.0025 * (1.0 - ads)      # respirar
	# posición: cadera <-> mira en el centro
	var grip: Vector3 = d.get("grip", Vector3(0, -0.08, 0.03))
	var sp := Vector3(0.0, float(d.get("sight", 0.07)), float(d.get("rear", 0.0))) - grip
	var mira := Vector3(0.0, -BAJO_OJO, -OJO) - sp * ESCALA
	# que la culata no se meta en la cámara (si no, se ve el arma por dentro: un bloque negro)
	mira.z = minf(mira.z, -atras * ESCALA - CULATA_MIN)
	var pos := (d.get("fp", CADERA) as Vector3).lerp(mira, _suave(ads)) + bob
	var rot := Vector3(0.0, 0.07, 0.03).lerp(Vector3(atan2(BAJO_OJO, 0.4), 0.0, 0.0), ads)
	# retroceso
	var k: float = kick * (0.5 if ads > 0.5 else 1.0)
	pos.z += 0.045 * k
	rot.x += 0.09 * k
	# recarga: el arma se gira un poco hacia ti para que se vea por dónde entra la munición
	var r := _suave(recarga)
	var pose: Array = POSE_RECARGA[rec_tipo if (rec_tipo != "cargador" or not d.get("larga", false)) else "cargador_largo"]
	pos += (pose[0] as Vector3) * r
	rot += (pose[1] as Vector3) * r
	var golpe := _recarga_anim(rp)               # la mano izquierda, el cargador, los cartuchos...
	pos.y += 0.012 * golpe
	rot.x -= 0.06 * golpe
	# bebiendo: el arma se baja del todo
	if beb_t >= 0.0:
		var bj := _suave(clampf(minf(beb_t / 0.2, (BEB_DUR - beb_t) / 0.25), 0.0, 1.0))
		pos.y -= 0.4 * bj
		rot.x -= 0.8 * bj
	# sprint: el arma se baja y se cruza
	pos += Vector3(-0.04, -0.06, 0.04) * run
	rot += Vector3(-0.3, 0.6, 0.25) * run
	# cambio de arma: sube desde abajo
	pos.y -= 0.28 * cambio
	rot.x -= 0.7 * cambio
	pivote.position = pos
	pivote.rotation = rot
	# con mira telescópica, al apuntar del todo se ve la pantalla de la mira (hud.gd)
	pivote.visible = not (d.get("scope", false) and ads > 0.85)
	# la minigun gira mientras disparas
	if canones != null:
		var dispara: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and player.cur < 2
		giro = move_toward(giro, 30.0 if dispara else 0.0, delta * 40.0)
		canones.rotation.z += giro * delta
	# antebrazos: del codo (fuera de pantalla) a cada muñeca
	_tramo(ante_d, CODO_D + Vector3(0, -0.1, 0.05) * ads, to_local(mano_d.global_position) + Vector3(0.012, -0.03, 0.05))
	var codo_i := CODO_I
	if not d.get("larga", false):
		codo_i = Vector3(-0.08, -0.5, 0.05)      # pistolas: la izquierda va por debajo de la derecha
	_tramo(ante_i, codo_i, to_local(mano_i.global_position) + Vector3(-0.01, -0.03, 0.05))
	ante_d.visible = pivote.visible
	ante_i.visible = pivote.visible


# Coloca un cilindro (de alto 1) entre a y b
func _tramo(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var dvec := b - a
	var l := dvec.length()
	if l < 0.001:
		return
	var y := dvec / l
	var x := y.cross(Vector3.FORWARD)
	if x.length() < 0.01:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y)
	mi.transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)
	mi.scale = Vector3(1.0, l, 1.0)


static func _suave(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


# ---------------- recarga ----------------
# cargador: la izquierda saca el cargador (se cae), baja a por otro, lo mete y da un golpe
# cartuchos (escopetas): mete cartuchos uno a uno por debajo y al final bombea
# frontal (lanzacohetes, ballesta): mete el cohete / la flecha por delante
func _preparar_recarga(id: String, d: Dictionary) -> void:
	for n in [cargador_viejo, cargador_nuevo]:
		if n != null:
			n.queue_free()
	var larga: bool = d.get("larga", false)
	var metal := U.gunmetal()
	if id in ["escopeta", "escopeta_auto"]:
		rec_tipo = "cartuchos"
		boca = Vector3(0.0, 0.035, -0.12)
		cargador_nuevo = Node3D.new()
		var cart := U.cylinder(cargador_nuevo, 0.011, 0.055, Vector3.ZERO, Color(0.75, 0.08, 0.06))
		cart.rotation_degrees.x = 90.0
		var cul := U.cylinder(cargador_nuevo, 0.0115, 0.012, Vector3(0, 0, 0.026), Color(0.8, 0.65, 0.25))
		cul.rotation_degrees.x = 90.0
		cul.material_override.metallic = 0.8
	elif id in ["lanzacohetes", "ballesta"]:
		rec_tipo = "frontal"
		var sight := float(d.get("sight", 0.07)) - (d.get("grip", Vector3.ZERO) as Vector3).y
		boca = Vector3(0.0, sight * 0.5 if id == "lanzacohetes" else sight * 0.7, -0.7 if id == "lanzacohetes" else -0.25)
		cargador_nuevo = Node3D.new()
		if id == "lanzacohetes":
			var cuerpo := U.cylinder(cargador_nuevo, 0.03, 0.2, Vector3.ZERO, Color(0.3, 0.33, 0.2))
			cuerpo.rotation_degrees.x = 90.0
			var punta := U.cone(cargador_nuevo, 0.0, 0.03, 0.09, Vector3(0, 0, -0.145), Color(0.35, 0.35, 0.38))
			punta.rotation_degrees.x = -90.0
		else:
			var vir := U.cylinder(cargador_nuevo, 0.004, 0.3, Vector3.ZERO, Color(0.45, 0.3, 0.15))
			vir.rotation_degrees.x = 90.0
			var pt := U.cone(cargador_nuevo, 0.0, 0.009, 0.03, Vector3(0, 0, -0.16), Color(0.7, 0.7, 0.75))
			pt.rotation_degrees.x = -90.0
	else:
		rec_tipo = "cargador"
		var tam := Vector3(0.024, 0.085, 0.036) if not larga else Vector3(0.03, 0.12, 0.05)
		if id == "minigun":
			tam = Vector3(0.1, 0.09, 0.12)
		if larga:
			boca = Vector3(0.0, mano_i_reposo.y + 0.02, mano_i_reposo.z * 0.45)
		else:
			boca = Vector3(0.0, abajo + 0.04, 0.0)
		cargador_viejo = Node3D.new()
		U.box_m(cargador_viejo, tam, Vector3(0, -tam.y * 0.5, 0), metal)
		cargador_nuevo = Node3D.new()
		U.box_m(cargador_nuevo, tam, Vector3(0, -tam.y * 0.5, 0), metal)
		U.box(cargador_nuevo, Vector3(tam.x * 0.6, 0.01, tam.z * 0.7), Vector3(0, 0.003, 0), Color(0.75, 0.6, 0.2))   # balas de arriba
		pivote.add_child(cargador_viejo)
		_sin_sombra(cargador_viejo)
		cargador_viejo.visible = false
	pivote.add_child(cargador_nuevo)
	_sin_sombra(cargador_nuevo)
	cargador_nuevo.visible = false


# Devuelve un "golpe" (0..1) para sacudir el arma al encajar el cargador o bombear
func _recarga_anim(p: float) -> float:
	if mano_i == null:
		return 0.0
	var fuera := boca + Vector3(-0.06, -0.38, 0.12)          # abajo, fuera de la pantalla
	var mano := mano_i_reposo
	var golpe := 0.0
	if cargador_viejo != null:
		cargador_viejo.visible = false
	cargador_nuevo.visible = false
	if p <= 0.0 or p >= 1.0:
		mano_i.position = mano
		return 0.0
	match rec_tipo:
		"cargador":
			if p < 0.15:                                       # va a por el cargador
				mano = mano_i_reposo.lerp(boca, _suave(p / 0.15))
			elif p < 0.35:                                     # lo suelta y baja
				var k: float = (p - 0.15) / 0.2
				mano = boca.lerp(fuera, _suave(k))
				cargador_viejo.visible = true
				cargador_viejo.position = boca + Vector3(-0.01 * k, -0.5 * k * k - 0.03 * k, 0.03 * k)
				cargador_viejo.rotation = Vector3(0.4 * k, 0, 0.6 * k)
			elif p < 0.45:                                     # coge otro
				mano = fuera
			elif p < 0.7:                                      # lo sube
				mano = fuera.lerp(boca + Vector3(0, -0.07, 0), _suave((p - 0.45) / 0.25))
				cargador_nuevo.visible = true
				cargador_nuevo.position = mano + Vector3(0, 0.07, 0)
			elif p < 0.76:                                     # lo mete de golpe
				var k: float = (p - 0.7) / 0.06
				mano = (boca + Vector3(0, -0.07, 0)).lerp(boca, k)
				cargador_nuevo.visible = k < 0.95
				cargador_nuevo.position = mano + Vector3(0, 0.07, 0)
				golpe = k
			else:                                              # vuelve a su sitio
				var k: float = (p - 0.76) / 0.24
				golpe = maxf(0.0, 1.0 - k * 4.0)
				mano = boca.lerp(mano_i_reposo, _suave(k))
		"cartuchos":
			var n := 3
			if p < 0.85:
				var c: float = p / 0.85 * n
				var k: float = c - floor(c)
				var junto := boca + Vector3(-0.03, -0.14, 0.08)
				if k < 0.6:
					mano = junto.lerp(boca, _suave(k / 0.6))
					cargador_nuevo.visible = true
					cargador_nuevo.position = mano + Vector3(0, 0.025, 0)
				else:
					mano = boca.lerp(junto, _suave((k - 0.6) / 0.4))
				if p < 0.08:
					mano = mano_i_reposo.lerp(mano, p / 0.08)
			else:                                              # bombear
				var k: float = (p - 0.85) / 0.15
				var bomba: float = sin(clampf(k * 1.4, 0.0, 1.0) * PI)
				mano = (boca + Vector3(-0.03, -0.14, 0.08)).lerp(mano_i_reposo, clampf(k * 3.0, 0.0, 1.0)) + Vector3(0, 0, 0.07 * bomba)
				golpe = bomba * 0.6
		"frontal":
			var lado := boca + Vector3(-0.12, -0.15, 0.1)
			if p < 0.25:
				mano = mano_i_reposo.lerp(fuera, _suave(p / 0.25))
			elif p < 0.65:
				mano = fuera.lerp(lado, _suave((p - 0.25) / 0.4))
				cargador_nuevo.visible = true
				cargador_nuevo.position = mano + Vector3(0.0, 0.04, -0.05)
			elif p < 0.8:
				var k: float = (p - 0.65) / 0.15
				mano = lado.lerp(boca, _suave(k))
				cargador_nuevo.visible = k < 0.9
				cargador_nuevo.position = mano + Vector3(0.0, 0.04, -0.05 + 0.08 * k)
				golpe = k * 0.5
			else:
				mano = boca.lerp(mano_i_reposo, _suave((p - 0.8) / 0.2))
	mano_i.position = mano
	return golpe


# ---------------- beber ----------------
# Al beber de una máquina: bajas el arma, sacas la lata con la derecha, la abres,
# te la bebes (se inclina hacia ti) y la bajas.
func beber(col: Color, letra: String) -> void:
	var cam := get_parent() as Node3D
	if cam == null:
		return
	if beb != null:
		beb.queue_free()
	var cols := Ch.colores_brazo(player.skin_data)
	beb = Node3D.new()
	cam.add_child(beb)
	beb_lata = Node3D.new()
	beb.add_child(beb_lata)
	var lata_m := U.mat(col)
	lata_m.metallic = 0.5
	lata_m.roughness = 0.35
	var cuerpo := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.03
	cm.bottom_radius = 0.03
	cm.height = 0.115
	cm.radial_segments = 20
	cuerpo.mesh = cm
	cuerpo.material_override = lata_m
	beb_lata.add_child(cuerpo)
	var tapa := U.cylinder(beb_lata, 0.027, 0.008, Vector3(0, 0.061, 0), Color(0.75, 0.75, 0.78))
	tapa.material_override.metallic = 0.9
	U.box(beb_lata, Vector3(0.012, 0.003, 0.008), Vector3(0, 0.066, 0.008), Color(0.2, 0.2, 0.2))   # el agujero
	var banda := U.cylinder(beb_lata, 0.0305, 0.035, Vector3(0, 0.0, 0), Color(0.95, 0.95, 0.95))
	banda.material_override.roughness = 0.5
	var l := Label3D.new()
	l.text = letra
	l.font_size = 48
	l.pixel_size = 0.0006
	l.modulate = col
	l.outline_size = 0
	l.position = Vector3(0, 0.0, 0.031)
	beb_lata.add_child(l)
	beb_mano = _mano(beb, Vector3.ZERO, cols[1], false)
	beb_ante = _antebrazo()
	remove_child(beb_ante)
	beb.add_child(beb_ante)
	var m := StandardMaterial3D.new()
	m.albedo_color = cols[0]
	m.roughness = 0.85
	beb_ante.material_override = m
	_sin_sombra(beb)
	beb_t = 0.0
	player.cooldown = maxf(player.cooldown, BEB_DUR)       # no se dispara mientras bebes


func _beber_anim(delta: float, cam: Camera3D) -> void:
	if beb_t < 0.0 or beb == null:
		return
	beb_t += delta
	if beb_t >= BEB_DUR or player.dead or player.downed:
		beb.queue_free()
		beb = null
		beb_t = -1.0
		return
	beb.visible = player.is_local and not player.third_person and cam.current
	var abajo_v := Vector3(0.16, -0.5, -0.3)
	var delante := Vector3(0.05, -0.13, -0.26)
	var boca_v := Vector3(0.015, -0.07, -0.17)
	var p := Vector3.ZERO
	var inc := 0.0
	var t2 := beb_t
	if t2 < 0.3:                                   # sube la lata
		p = abajo_v.lerp(delante, _suave(t2 / 0.3))
	elif t2 < 0.45:                                # ¡pssst!
		p = delante
	elif t2 < 0.65:                                # a la boca
		var k: float = _suave((t2 - 0.45) / 0.2)
		p = delante.lerp(boca_v, k)
		inc = 1.5 * k
	elif t2 < 1.15:                                # glu glu glu
		p = boca_v + Vector3(0, sin((t2 - 0.65) * 18.0) * 0.003, 0)
		inc = 1.5 + 0.25 * (t2 - 0.65) / 0.5
	else:                                          # la baja
		var k: float = _suave((t2 - 1.15) / (BEB_DUR - 1.15))
		p = boca_v.lerp(abajo_v, k)
		inc = 1.75 * (1.0 - k)
	beb_lata.position = p
	beb_lata.rotation = Vector3(inc, 0.0, -0.15)
	beb_mano.position = p + beb_lata.basis * Vector3(0.022, -0.005, 0.012)
	beb_mano.rotation = beb_lata.rotation
	_tramo(beb_ante, CODO_D + Vector3(0.05, -0.05, 0.1), beb_mano.position + Vector3(0.02, -0.04, 0.05))

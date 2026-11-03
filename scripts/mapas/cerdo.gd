extends Node3D
# JORGE: el cerdo glotón de la playa de Mojácar (mapa de Mojácar, investigacion.gd).
# Está sentado en su toalla al lado del chiringuito, con su sombrero de paja, sus gafas
# de sol y su bañador turquesa, muerto de hambre. Le traes comida de la playa y del
# paseo (sandía, helados, espetos de sardinas y churros); cada cosa que se come
# le hincha un poco más la barriga... hasta que revienta. Y al reventar se abre el
# camino al siguiente sitio del bucle.
# Mira hacia +Z (su cara). Medidas en metros: sentado mide unos 2,6 m.

const U = preload("res://scripts/nucleo/util.gd")

signal reventado            # al explotar (investigacion.gd hace el resto)

const ROSA := Color(0.96, 0.62, 0.62)
const ROSA_CLARO := Color(1.0, 0.74, 0.72)
const ROSA_OSCURO := Color(0.86, 0.45, 0.5)
const PEZUNA := Color(0.55, 0.4, 0.38)
const TURQUESA := Color(0.08, 0.62, 0.68)
const PAJA := Color(0.86, 0.72, 0.42)
const AZUL := Color(0.13, 0.33, 0.62)

const TIPOS := ["sandia", "helado", "espeto", "churros"]
const FRASES_COMER := ["¡ÑAM!", "¡QUÉ RICO!", "¡MÁS, MÁS!", "¡ÑAM ÑAM!", "¡OINK!", "¡SIGUE!", "*ÑAC*"]

var gordura := 0.0          # 0 = como llega, 1 = a punto de reventar (lo que se ve, va hacia objetivo)
var objetivo := 0.0
var boca_abierta := false   # investigacion.gd lo pone a true si te acercas con comida
var t := 0.0
var masca := 0.0            # >0 mientras mastica
var parpadeo := 3.0
var reventando := false
var muerto := false

var cuerpo: Node3D
var barriga: Node3D
var cabeza: Node3D
var mandibula: Node3D
var orejas: Array = []
var ojos: Array = []
var brazos: Array = []
var sombrero: Node3D
var mat_piel: StandardMaterial3D
var mat_claro: StandardMaterial3D
var bocadillo: Label3D      # lo que dice
var snd: AudioStreamPlayer3D
var snd_nam: AudioStreamPlayer3D
var gotas: Array = []


func _ready() -> void:
	_modelo()
	snd = AudioStreamPlayer3D.new()
	snd.stream = _oink()
	snd.unit_size = 10.0
	snd.position.y = 2.0
	add_child(snd)
	snd_nam = AudioStreamPlayer3D.new()
	snd_nam.stream = _nam()
	snd_nam.unit_size = 10.0
	snd_nam.position.y = 2.0
	add_child(snd_nam)
	bocadillo = Label3D.new()
	bocadillo.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bocadillo.font_size = 64
	bocadillo.pixel_size = 0.006
	bocadillo.outline_size = 14
	bocadillo.modulate = Color(1.0, 0.95, 0.85)
	bocadillo.outline_modulate = Color(0.45, 0.1, 0.2)
	bocadillo.position = Vector3(0, 3.5, 0)
	bocadillo.modulate.a = 0.0
	add_child(bocadillo)


# ---------------- modelo ----------------
func _m(c: Color, rough: float = 0.6) -> StandardMaterial3D:
	var m := U.mat(c)
	m.roughness = rough
	return m


func _modelo() -> void:
	mat_piel = _m(ROSA, 0.55)
	mat_claro = _m(ROSA_CLARO, 0.55)
	var oscuro := _m(ROSA_OSCURO, 0.6)
	var pez := _m(PEZUNA, 0.45)
	var banador := _m(TURQUESA, 0.7)
	var blanco := _m(Color(0.96, 0.96, 0.94), 0.7)
	# la toalla de rayas
	var toalla := Node3D.new()
	add_child(toalla)
	for i in 8:
		U.box(toalla, Vector3(2.6, 0.02, 0.4), Vector3(0, 0.015, -1.5 + i * 0.4 + 0.2), Color(0.95, 0.45, 0.12) if i % 2 == 0 else Color(0.97, 0.95, 0.88))
	# --- cuerpo (lo que engorda) ---
	cuerpo = Node3D.new()
	add_child(cuerpo)
	U.ellipsoid_m(cuerpo, Vector3(0.92, 0.9, 0.8), Vector3(0, 0.98, 0), mat_piel)            # tronco
	# bañador con su cinturilla blanca y el lacito del cordón
	U.ellipsoid_m(cuerpo, Vector3(0.98, 0.4, 0.86), Vector3(0, 0.44, 0), banador)
	U.ellipsoid_m(cuerpo, Vector3(0.985, 0.05, 0.865), Vector3(0, 0.74, 0), blanco)
	for i in 6:      # hojitas de palmera blancas estampadas en el bañador
		var a := -2.3 + i * 0.9
		var h := U.ellipsoid_m(cuerpo, Vector3(0.09, 0.025, 0.02), Vector3(sin(a) * 0.985, 0.48 + (i % 2) * 0.12, cos(a) * 0.865), blanco)
		h.rotation = Vector3(0, a, 0.6 if i % 2 == 0 else -0.6)
	# piernas estiradas hacia delante (los muslos van dentro del bañador)
	for sx in [-1.0, 1.0]:
		U.ellipsoid_m(cuerpo, Vector3(0.33, 0.29, 0.5), Vector3(sx * 0.48, 0.33, 0.45), banador)
		U.ellipsoid_m(cuerpo, Vector3(0.26, 0.24, 0.36), Vector3(sx * 0.52, 0.27, 0.95), mat_piel)
		var pz := U.ellipsoid_m(cuerpo, Vector3(0.19, 0.19, 0.07), Vector3(sx * 0.54, 0.27, 1.27), pez)
		U.box_m(pz, Vector3(0.02, 0.4, 0.02), Vector3(0, 0, 0.09), _m(Color(0.12, 0.08, 0.07)))    # la pezuña partida
	# barriga (la parte que más crece)
	barriga = Node3D.new()
	barriga.position = Vector3(0, 0.95, 0.32)
	cuerpo.add_child(barriga)
	U.ellipsoid_m(barriga, Vector3(0.72, 0.68, 0.52), Vector3.ZERO, mat_claro)
	U.ellipsoid_m(barriga, Vector3(0.045, 0.055, 0.02), Vector3(0, -0.06, 0.515), oscuro)       # ombligo
	# brazos: del hombro a la barriga, con la pezuña apoyada
	for sx in [-1.0, 1.0]:
		var b := Node3D.new()
		b.position = Vector3(sx * 0.78, 1.42, 0.08)
		cuerpo.add_child(b)
		U.limb_m(b, Vector3.ZERO, Vector3(sx * 0.2, -0.42, 0.22), 0.2, 0.17, mat_piel)
		U.limb_m(b, Vector3(sx * 0.2, -0.42, 0.22), Vector3(sx * -0.12, -0.5, 0.64), 0.17, 0.14, mat_piel)
		U.ellipsoid_m(b, Vector3(0.12, 0.11, 0.1), Vector3(sx * -0.14, -0.5, 0.73), pez)
		brazos.append(b)
	# colita rizada
	var cola := Node3D.new()
	cola.position = Vector3(0, 0.55, -0.82)
	cuerpo.add_child(cola)
	var tor := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.05
	tm.outer_radius = 0.1
	tor.mesh = tm
	tor.material_override = mat_piel
	tor.rotation_degrees = Vector3(0, 90, 0)
	cola.add_child(tor)
	U.ellipsoid_m(cola, Vector3(0.04, 0.04, 0.07), Vector3(0, 0.08, -0.05), mat_piel)
	# --- cabeza ---
	cabeza = Node3D.new()
	cabeza.position = Vector3(0, 1.98, 0.14)
	add_child(cabeza)
	U.ellipsoid_m(cabeza, Vector3(0.62, 0.6, 0.6), Vector3.ZERO, mat_piel)
	for sx in [-1.0, 1.0]:
		U.ellipsoid_m(cabeza, Vector3(0.26, 0.21, 0.22), Vector3(sx * 0.33, -0.17, 0.38), mat_claro)    # mofletes
	# hocico
	U.ellipsoid_m(cabeza, Vector3(0.27, 0.21, 0.22), Vector3(0, -0.02, 0.55), mat_piel)
	var disco := U.cylinder(cabeza, 0.21, 0.07, Vector3(0, -0.02, 0.73), ROSA_OSCURO)
	disco.rotation_degrees.x = 90.0
	disco.material_override = oscuro
	for sx in [-1.0, 1.0]:
		U.ellipsoid_m(cabeza, Vector3(0.04, 0.065, 0.02), Vector3(sx * 0.075, -0.02, 0.765), _m(Color(0.3, 0.1, 0.12)))
	# ojos y cejas
	for sx in [-1.0, 1.0]:
		var o := Node3D.new()
		o.position = Vector3(sx * 0.22, 0.22, 0.5)
		cabeza.add_child(o)
		U.ellipsoid_m(o, Vector3(0.11, 0.13, 0.07), Vector3.ZERO, blanco)
		U.sphere(o, 0.055, Vector3(sx * -0.01, -0.015, 0.055), Color(0.05, 0.04, 0.04))
		U.sphere(o, 0.016, Vector3(sx * -0.01 + 0.02, 0.01, 0.1), Color(1, 1, 1), true)
		ojos.append(o)
		var ceja := U.ellipsoid_m(cabeza, Vector3(0.1, 0.022, 0.025), Vector3(sx * 0.22, 0.4, 0.52), _m(Color(0.45, 0.25, 0.22)))
		ceja.rotation.z = sx * -0.25
	# boca: el interior (fijo) y la mandíbula (se abre)
	U.ellipsoid_m(cabeza, Vector3(0.2, 0.1, 0.13), Vector3(0, -0.26, 0.5), _m(Color(0.35, 0.05, 0.08)))
	mandibula = Node3D.new()
	mandibula.position = Vector3(0, -0.22, 0.36)
	cabeza.add_child(mandibula)
	U.ellipsoid_m(mandibula, Vector3(0.25, 0.08, 0.2), Vector3(0, -0.06, 0.14), mat_piel)
	U.ellipsoid_m(mandibula, Vector3(0.15, 0.04, 0.13), Vector3(0, -0.01, 0.15), _m(Color(0.85, 0.32, 0.38)))   # lengua
	# orejas caídas hacia delante
	for sx in [-1.0, 1.0]:
		var p := Node3D.new()
		p.position = Vector3(sx * 0.36, 0.42, -0.02)
		p.rotation = Vector3(0.95, 0, sx * -0.55)
		cabeza.add_child(p)
		U.ellipsoid_m(p, Vector3(0.17, 0.27, 0.05), Vector3(0, 0.22, 0), mat_piel)
		U.ellipsoid_m(p, Vector3(0.11, 0.19, 0.03), Vector3(0, 0.22, 0.03), oscuro)
		orejas.append(p)
	# sombrero de paja con cinta azul y las gafas de sol subidas
	sombrero = Node3D.new()
	sombrero.position = Vector3(0.04, 0.5, -0.06)
	sombrero.rotation = Vector3(-0.12, 0, -0.14)
	cabeza.add_child(sombrero)
	var paja := _m(PAJA, 0.95)
	var ala := MeshInstance3D.new()
	var am := CylinderMesh.new()
	am.top_radius = 0.8
	am.bottom_radius = 0.82
	am.height = 0.035
	am.radial_segments = 40
	ala.mesh = am
	ala.material_override = paja
	sombrero.add_child(ala)
	var copa := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.33
	cm.bottom_radius = 0.4
	cm.height = 0.3
	cm.radial_segments = 32
	copa.mesh = cm
	copa.material_override = paja
	copa.position.y = 0.16
	sombrero.add_child(copa)
	var cinta := U.cylinder(sombrero, 0.405, 0.08, Vector3(0, 0.06, 0), AZUL)
	cinta.material_override.roughness = 0.5
	var negro := _m(Color(0.04, 0.04, 0.05), 0.15)
	negro.metallic = 0.3
	for sx in [-1.0, 1.0]:
		var cr := U.cylinder(sombrero, 0.085, 0.02, Vector3(sx * 0.105, 0.17, 0.375), Color.BLACK)
		cr.rotation_degrees.x = 80.0
		cr.material_override = negro
	U.box_m(sombrero, Vector3(0.06, 0.02, 0.02), Vector3(0, 0.18, 0.39), _m(Color(0.95, 0.5, 0.1)))
	# el cartel
	var cartel := Node3D.new()
	cartel.position = Vector3(1.75, 0, 0.9)
	cartel.rotation.y = -0.4
	add_child(cartel)
	U.box(cartel, Vector3(0.08, 1.5, 0.08), Vector3(0, 0.75, 0), Color(0.45, 0.3, 0.18))
	U.box(cartel, Vector3(0.95, 0.55, 0.05), Vector3(0, 1.45, 0.05), Color(0.62, 0.45, 0.28))
	var l := Label3D.new()
	l.text = "¡TENGO\nHAMBRE!"
	l.font_size = 48
	l.pixel_size = 0.0045
	l.modulate = Color(0.2, 0.1, 0.05)
	l.outline_size = 0
	l.position = Vector3(0, 1.45, 0.08)
	cartel.add_child(l)
	_sin_sombra_toalla(toalla)


func _sin_sombra_toalla(n: Node3D) -> void:
	for c in n.get_children():
		if c is GeometryInstance3D:
			c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# Punto (global) de la boca, para que la comida vuele hasta ahí
func boca_global() -> Vector3:
	return mandibula.global_position + global_transform.basis.z * 0.25


# ---------------- comer ----------------
# Se come algo: la comida vuela desde 'desde' hasta la boca, la mastica y engorda.
func comer(tipo: String, n: int, total: int, desde: Vector3) -> void:
	objetivo = clampf(float(n) / float(total), 0.0, 1.0)
	var c := comida(tipo)
	get_parent().add_child(c)
	c.global_position = desde
	c.scale = Vector3.ONE * 1.4
	var tw := c.create_tween().set_parallel(true)
	tw.tween_property(c, "global_position", boca_global(), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(c, "rotation", Vector3(4.0, 6.0, 2.0), 0.45)
	tw.tween_property(c, "scale", Vector3.ONE * 0.6, 0.45)
	tw.chain().tween_callback(func():
		c.queue_free()
		masca = 1.1
		snd_nam.pitch_scale = randf_range(0.9, 1.1)
		snd_nam.play()
		if n < total:
			_decir(FRASES_COMER[randi() % FRASES_COMER.size()] if objetivo < 0.75 else ["¡UF... CABE MÁS!", "¡UNO MÁS!", "¡ESTOY LLENÍSIMO!"][randi() % 3])
			get_tree().create_timer(0.9).timeout.connect(_gruñir)
	)


func _gruñir() -> void:
	if muerto:
		return
	snd.pitch_scale = randf_range(0.85, 1.05) - gordura * 0.2
	snd.play()


func _decir(txt: String) -> void:
	bocadillo.text = txt
	bocadillo.position.y = 3.2 + gordura * 0.6
	var tw := bocadillo.create_tween()
	tw.tween_property(bocadillo, "modulate:a", 1.0, 0.1)
	tw.parallel().tween_property(bocadillo, "position:y", bocadillo.position.y + 0.3, 1.5)
	tw.tween_property(bocadillo, "modulate:a", 0.0, 0.4)


# Revienta: se hincha a lo bestia, chilla, tiembla y ¡BUM!
func reventar() -> void:
	if reventando:
		return
	reventando = true
	objetivo = 1.0
	_decir("¡¡NO PUEDO MÁS!!")
	var ch := AudioStreamPlayer3D.new()
	ch.stream = _chillido()
	ch.unit_size = 14.0
	ch.position.y = 2.0
	add_child(ch)
	ch.play()
	var tw := create_tween()
	tw.tween_property(self, "gordura", 1.45, 1.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(_bum)


func _bum() -> void:
	muerto = true
	var centro := global_position + Vector3(0, 1.3, 0)
	cuerpo.visible = false
	cabeza.visible = false
	bocadillo.visible = false
	# nube rosa
	for i in 16:
		var s := U.sphere(get_parent(), 1.0, centro + Vector3(randf_range(-1, 1), randf_range(-0.6, 1.2), randf_range(-1, 1)), ROSA_CLARO)
		s.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		s.material_override.roughness = 1.0
		s.material_override.albedo_color.a = 0.75
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s.scale = Vector3.ONE * 0.05
		var size := randf_range(0.55, 1.15)
		var st := s.create_tween()
		st.tween_interval(randf() * 0.15)
		st.tween_property(s, "scale", Vector3.ONE * size, 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		st.parallel().tween_property(s, "position:y", s.position.y + 1.5, 2.0)
		st.tween_property(s.material_override, "albedo_color:a", 0.0, 0.9)
		st.parallel().tween_property(s, "scale", Vector3.ONE * size * 1.35, 0.9)
		st.tween_callback(s.queue_free)
	# confeti y toda la comida que llevaba dentro
	for i in 60:
		var p: Node3D
		if i < 14:
			p = comida(TIPOS[i % TIPOS.size()])
			get_parent().add_child(p)
		else:
			p = U.box(get_parent(), Vector3(0.09, 0.012, 0.06), Vector3.ZERO, [ROSA, Color(1, 0.85, 0.2), Color(0.3, 0.8, 1.0), Color(1, 1, 1), Color(0.5, 1.0, 0.4)][i % 5], true)
		p.global_position = centro
		var dest := centro + Vector3(randf_range(-9, 9), 0, randf_range(-9, 9))
		dest.y = 0.06
		var up := centro.y + randf_range(2.5, 6.5)
		var dur := randf_range(1.2, 2.4)
		var tw := p.create_tween().set_parallel(true)
		tw.tween_property(p, "global_position:x", dest.x, dur)
		tw.tween_property(p, "global_position:z", dest.z, dur)
		tw.tween_property(p, "rotation", Vector3(randf() * 14, randf() * 14, randf() * 14), dur)
		var ty := p.create_tween()
		ty.tween_property(p, "global_position:y", up, dur * 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		ty.tween_property(p, "global_position:y", dest.y, dur * 0.65).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		ty.tween_interval(6.0)
		ty.tween_callback(p.queue_free)
	# el sombrero sale volando y cae en la toalla
	var sg := sombrero.global_transform
	sombrero.get_parent().remove_child(sombrero)
	add_child(sombrero)
	sombrero.global_transform = sg
	sombrero.visible = true
	var hs := sombrero.create_tween().set_parallel(true)
	hs.tween_property(sombrero, "position", Vector3(0.3, 0.06, 0.4), 2.2).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	hs.tween_property(sombrero, "rotation", Vector3(0, 7.0, 0), 2.2)
	var hy := sombrero.create_tween()
	hy.tween_property(sombrero, "position:y", 6.0, 0.7).set_ease(Tween.EASE_OUT)
	hy.tween_property(sombrero, "position:y", 0.06, 1.3).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BOUNCE)
	reventado.emit()


# ---------------- animación ----------------
func _process(delta: float) -> void:
	t += delta
	if not reventando:
		gordura = move_toward(gordura, objetivo, delta * 0.6)
	if muerto:
		return
	var g := gordura
	# engordar: el cuerpo se ensancha y la barriga se va para delante
	var resp := sin(t * 1.7) * 0.015 * (1.0 + g * 2.0)
	cuerpo.scale = Vector3(1.0 + 0.32 * g, 1.0 + 0.14 * g + resp, 1.0 + 0.32 * g)
	barriga.scale = Vector3(1.0 + 0.4 * g, 1.0 + 0.35 * g, 1.0 + 1.1 * g)
	barriga.position.z = 0.32 + 0.12 * g
	cabeza.position.y = 1.98 + 0.28 * g + resp * 2.0
	cabeza.scale = Vector3.ONE * (1.0 + 0.12 * g)
	# cada vez más colorado
	var rojo := clampf((g - 0.4) / 0.8, 0.0, 1.0)
	mat_piel.albedo_color = ROSA.lerp(Color(1.0, 0.38, 0.38), rojo)
	mat_claro.albedo_color = ROSA_CLARO.lerp(Color(1.0, 0.5, 0.48), rojo)
	# tiembla cuando está a reventar
	var temblor := clampf((g - 0.75) * 3.0, 0.0, 1.0) + (0.8 if reventando else 0.0)
	cuerpo.position = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 0.03 * temblor
	cabeza.position.x = cuerpo.position.x
	# cabeza: mira a la cámara si está cerca, si no se balancea
	var cam := get_viewport().get_camera_3d()
	var yaw := sin(t * 0.5) * 0.25
	var pitch := sin(t * 0.8) * 0.04
	if cam != null:
		var l := to_local(cam.global_position)
		if l.length() < 14.0 and l.z > -1.0:
			yaw = clampf(atan2(l.x, maxf(l.z, 0.1)), -0.7, 0.7)
			pitch = clampf(-atan2(l.y - 2.0, Vector2(l.x, l.z).length()) * 0.6, -0.35, 0.3)
	cabeza.rotation.y = lerp_angle(cabeza.rotation.y, yaw, minf(1.0, delta * 4.0))
	cabeza.rotation.x = lerpf(cabeza.rotation.x, pitch, minf(1.0, delta * 4.0))
	# boca: masticar, abierta esperando comida, o resoplando
	var abre := 0.05 + 0.05 * sin(t * 2.1)
	if masca > 0.0:
		masca -= delta
		abre = 0.08 + absf(sin(masca * 14.0)) * 0.45
	elif boca_abierta or reventando:
		abre = 0.65 + sin(t * 6.0) * 0.06
	mandibula.rotation.x = lerpf(mandibula.rotation.x, abre, minf(1.0, delta * 14.0))
	# orejas que se mueven
	for i in orejas.size():
		var sx := -1.0 if i == 0 else 1.0
		orejas[i].rotation = Vector3(0.95 + sin(t * 2.3 + i) * 0.06 + (0.25 * temblor * sin(t * 30.0)), 0, sx * (-0.55 - sin(t * 1.7 + i * 2.0) * 0.08))
	# parpadeo
	parpadeo -= delta
	var ojo_y := 1.0
	if parpadeo < 0.12:
		ojo_y = 0.1
		if parpadeo < 0.0:
			parpadeo = randf_range(2.0, 5.0)
	if reventando:
		ojo_y = 1.35            # ojos como platos
	for o in ojos:
		o.scale = Vector3(1.0, ojo_y, 1.0)
	# se frota la barriga
	for i in brazos.size():
		var sx := -1.0 if i == 0 else 1.0
		var frota := sin(t * 3.0 + i * PI) * 0.12 if masca > 0.0 else sin(t * 1.2 + i) * 0.03
		brazos[i].rotation = Vector3(frota - 0.2 * g, 0, sx * 0.25 * g)
	# gotas de sudor cuando está muy lleno
	if g > 0.7 and randf() < delta * 2.5:
		_gota()


func _gota() -> void:
	var s := U.sphere(cabeza, 0.035, Vector3(randf_range(-0.4, 0.4), 0.35, 0.45), Color(0.7, 0.9, 1.0))
	s.material_override.metallic = 0.3
	s.material_override.roughness = 0.05
	s.scale = Vector3(0.8, 1.3, 0.8)
	var tw := s.create_tween()
	tw.tween_property(s, "position:y", -0.6, 0.9).set_ease(Tween.EASE_IN)
	tw.tween_callback(s.queue_free)


# ---------------- la comida ----------------
# Modelitos de comida de playa (unos 30 cm)
static func comida(tipo: String) -> Node3D:
	var n := Node3D.new()
	match tipo:
		"sandia":
			var pm := PrismMesh.new()
			pm.size = Vector3(0.32, 0.2, 0.07)
			var carne := MeshInstance3D.new()
			carne.mesh = pm
			carne.material_override = U.mat(Color(0.92, 0.18, 0.2))
			carne.rotation_degrees.z = 180.0
			n.add_child(carne)
			U.box(n, Vector3(0.33, 0.035, 0.075), Vector3(0, 0.11, 0), Color(0.15, 0.5, 0.15))
			U.box(n, Vector3(0.32, 0.012, 0.076), Vector3(0, 0.088, 0), Color(0.85, 0.95, 0.7))
			for p in [Vector2(-0.06, 0.04), Vector2(0.05, 0.03), Vector2(0.0, -0.01), Vector2(-0.02, 0.06), Vector2(0.08, 0.06)]:
				U.ellipsoid(n, Vector3(0.008, 0.012, 0.005), Vector3(p.x, p.y, 0.037), Color(0.05, 0.03, 0.02))
		"helado":
			var cono := U.cone(n, 0.0, 0.06, 0.18, Vector3(0, -0.06, 0), Color(0.82, 0.6, 0.32))
			cono.rotation_degrees.x = 180.0
			U.sphere(n, 0.068, Vector3(0, 0.06, 0), Color(1.0, 0.6, 0.72))
			U.sphere(n, 0.06, Vector3(0, 0.15, 0), Color(0.98, 0.96, 0.9))
			U.sphere(n, 0.02, Vector3(0.01, 0.21, 0.0), Color(0.9, 0.1, 0.15))
		"espeto":
			var cana := U.cylinder(n, 0.008, 0.5, Vector3.ZERO, Color(0.75, 0.62, 0.38))
			cana.rotation_degrees.z = 20.0
			var plata := U.mat(Color(0.62, 0.65, 0.68))
			plata.metallic = 0.6
			plata.roughness = 0.3
			for i in 3:
				var y := -0.08 + i * 0.09
				var pez := U.ellipsoid_m(n, Vector3(0.09, 0.022, 0.016), Vector3(-sin(deg_to_rad(20.0)) * y, y * cos(deg_to_rad(20.0)), 0), plata)
				pez.rotation_degrees.z = 20.0
				var colita := U.cone(pez, 0.0, 0.02, 0.04, Vector3(0.1, 0, 0), Color(0.5, 0.52, 0.55))
				colita.rotation_degrees.z = 90.0
		_:   # churros
			U.cone(n, 0.07, 0.04, 0.12, Vector3(0, -0.04, 0), Color(0.97, 0.97, 0.95))     # cucurucho de papel
			for i in 4:
				var ch := U.cylinder(n, 0.014, 0.22, Vector3(-0.03 + i * 0.02, 0.06, (i % 2) * 0.015), Color(0.78, 0.5, 0.22))
				ch.rotation_degrees.z = -12.0 + i * 8.0
	return n


# ---------------- sonidos ----------------
# Gruñido de cerdo: diente de sierra grave con trémolo y ruido
func _oink() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.45)
	var data := PackedByteArray()
	data.resize(n * 2)
	var ph := 0.0
	for i in n:
		var tt := float(i) / rate
		var k := tt / 0.45
		var f := 165.0 + 70.0 * sin(k * PI)
		ph += f / rate
		var saw := fmod(ph, 1.0) * 2.0 - 1.0
		var env := sin(k * PI) * (0.6 + 0.4 * absf(sin(tt * 2.0 * PI * 26.0)))
		var s := (saw * 0.55 + (randf() * 2.0 - 1.0) * 0.25) * env
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 26000.0))
	return U._wav(data, rate)


# Ñam ñam: tres mordiscos de ruido sordo
func _nam() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.75)
	var data := PackedByteArray()
	data.resize(n * 2)
	var prev := 0.0
	for i in n:
		var tt := float(i) / rate
		var s := 0.0
		for g in [0.0, 0.22, 0.44]:
			var d: float = tt - g
			if d >= 0.0 and d < 0.14:
				s += (randf() * 2.0 - 1.0) * sin(PI * d / 0.14) + sin(TAU * 110.0 * d) * 0.5 * exp(-d * 30.0)
		prev = prev * 0.7 + s * 0.3          # paso bajo: suena "húmedo"
		data.encode_s16(i * 2, int(clampf(prev * 1.6, -1.0, 1.0) * 26000.0))
	return U._wav(data, rate)


# Chillido que sube mientras se hincha
func _chillido() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 1.6)
	var data := PackedByteArray()
	data.resize(n * 2)
	var ph := 0.0
	for i in n:
		var tt := float(i) / rate
		var k := tt / 1.6
		var f := 300.0 + 900.0 * k * k + sin(tt * 40.0) * 30.0
		ph += f / rate
		var s := (fmod(ph, 1.0) * 2.0 - 1.0) * 0.4 + sin(ph * TAU) * 0.3
		data.encode_s16(i * 2, int(clampf(s * minf(1.0, tt * 8.0), -1.0, 1.0) * 24000.0))
	return U._wav(data, rate)

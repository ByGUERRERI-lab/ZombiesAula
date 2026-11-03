extends "res://scripts/mapas/mission.gd"
# ESCAPA DEL BUCLE: has "escapado" de CESUR y te despiertas en un sitio que no
# conoces (Mojácar, el Hotel Pueblo Indalo...). Mientras siguen llegando oleadas:
#  1. Supera las PRUEBAS DE HABILIDAD del mapa (los "!" solo se ven de cerca).
#     Cada prueba es un minijuego distinto:
#       · Puntería      dispara a 6 de las 8 dianas antes de que se escondan
#       · Memoria       repite con las flechas la secuencia de luces (3 rondas)
#       · Reflejos      pulsa la flecha que salga a tiempo, 8 seguidas
#       · Aguante       quédate 25 s dentro del círculo mientras te atacan
#       · Contrarreloj  pasa por los 5 puntos antes de que se acabe el tiempo
#     Al superarla descubres lo que no cuadra de ese sitio (el texto de la pista).
#     Si fallas, vuelve al "!" y repítela.
#  2. Con todas, aparece la puerta del aula donde no debería haber ninguna puerta.
#  3. La cruzas... y apareces en el siguiente sitio del bucle.
# En MOJÁCAR es distinto: en la playa está JORGE (cerdo.gd), un cerdo muerto de
# hambre. Los zombis que matas sueltan comida: cógela (llevas 3 como mucho) y dásela: cuanto
# más come, más engorda... y cuando ha comido COMIDA_TOTAL, revienta y te vas.
# Usa la interfaz y los sonidos de mission.gd; los sitios y los textos vienen de mapas.gd.

const CerdoScript = preload("res://scripts/mapas/cerdo.gd")
const COMIDA_TOTAL := 10     # lo que tiene que comer el cerdo para reventar
const LLEVAR_MAX := 3        # comida que puedes llevar a la vez
const COMIDA_VIDA := 30.0    # segundos que dura en el suelo la comida que suelta un zombi
const COMIDA_PROB := 0.6     # probabilidad de que un zombi suelte comida (si no hay nada en el suelo, siempre)
const NEAR_MARK := 16.0      # a qué distancia se ve el "!" de una prueba
const READ_TIME := 9.0       # segundos que se queda el texto al superar una prueba

# Qué prueba hay en cada sitio (si un sitio no está aquí, se reparten en orden)
const TIPO_DE := {"senal": "dianas", "mesas": "memoria", "taquillas": "reflejos", "radio": "aguante", "fin": "carrera",
	"registro": "reflejos", "sillas": "dianas", "llave": "memoria", "tenis": "carrera", "buffet": "aguante"}
const TIPOS := ["dianas", "memoria", "reflejos", "aguante", "carrera"]
const NOMBRE_TIPO := {"dianas": "Puntería", "memoria": "Memoria", "reflejos": "Reflejos", "aguante": "Aguante", "carrera": "Contrarreloj"}
const REGLA := {
	"dianas": "Dispara a 6 de las 8 dianas antes de que se escondan",
	"memoria": "Mira la secuencia de luces y repítela con las flechas (3 rondas)",
	"reflejos": "Pulsa la flecha que salga en pantalla a tiempo. 8 seguidas",
	"aguante": "Quédate 25 segundos dentro del círculo. Vienen a por ti",
	"carrera": "Pasa por los 5 puntos antes de que se acabe el tiempo",
}
const FLECHAS := ["←", "↑", "↓", "→"]
const TECLAS := [KEY_LEFT, KEY_UP, KEY_DOWN, KEY_RIGHT]
const COLORES := [Color(1.0, 0.25, 0.2), Color(0.25, 1.0, 0.35), Color(0.3, 0.55, 1.0), Color(1.0, 0.85, 0.2)]
const DIANAS := 8
const DIANAS_OK := 6
const AGUANTE_T := 25.0
const AGUANTE_R := 3.5
const REFLEJOS_N := 8

var mapa                     # mapas.gd
var found := {}
var glints := {}
var tipo := {}               # id del sitio -> tipo de prueba
var door: Node3D
var door_marker: Label3D
var reader: PanelContainer
var read_title: Label
var read_text: Label
var read_tw: Tween

# prueba en curso (solo en el PC de quien la está haciendo)
var reto := ""               # id del sitio ("" = ninguna)
var reto_tipo := ""
var reto_pos := Vector3.ZERO
var rt := 0.0                # tiempo dentro de la prueba
var r := {}                  # estado propio de cada prueba
var reto_nodes: Array = []
var flecha_prev := [false, false, false, false]
var big_lbl: Label           # flechas y avisos grandes en el centro
var snd_ok: AudioStreamPlayer
var snd_mal: AudioStreamPlayer
var snd_tonos: Array = []
# modo cerdo (Mojácar)
var modo_cerdo := false
var cerdo: Node3D
var comidas := {}            # id -> {nodo, pos, tipo, vida}: la comida que han soltado los zombis
var n_soltadas := 0
var llevas: Array = []       # tipos de comida que llevas encima
var comido := 0


func _ready() -> void:
	mapa = game.mapa
	_build_ui()
	_build_sounds()
	_build_reader()
	_build_reto_ui()
	if mapa.cerdo_pos != Vector3.ZERO:
		_cerdo_preparar()
		return
	var i := 0
	for p in mapa.pistas:
		found[p[0]] = false
		tipo[p[0]] = TIPO_DE.get(p[0], TIPOS[i % TIPOS.size()])
		glints[p[0]] = _glint(p[3] + Vector3(0, 1.1, 0), COLORES[i % COLORES.size()])
		markers[p[0]] = _marker(p[3] + Vector3(0, 1.7, 0), Color(1.0, 0.85, 0.3), "!")
		markers[p[0]].visible = false
		i += 1
	door = MapasScript.puerta_aula(self, mapa.puerta_pos, mapa.puerta_yaw)
	door.visible = false
	markers["door"] = _marker(mapa.puerta_pos + Vector3(0, 3.3, 0), Color(0.3, 1.0, 0.4), "LA PUERTA DEL AULA")
	markers["door"].visible = false
	brief.text = mapa.intro.replace("Investiga.", "") + "\nSupera las pruebas de habilidad de los «!» para descubrir qué está pasando."
	brief.add_theme_color_override("font_color", Color(0.95, 0.92, 0.8))
	var tw := create_tween()
	tw.tween_interval(8.0)
	tw.tween_property(brief, "modulate:a", 0.0, 1.2)


func _process(delta: float) -> void:
	t += delta
	_update_shake(delta)
	if game.explorando:
		return
	if stage == 3 or player.dead:
		prompt.text = ""
		bar.visible = false
		if reto != "":
			_cancelar()
		return
	elapsed += delta
	for id in glints:
		var g: Node3D = glints[id]
		g.rotation.y += 1.5 * delta
		g.position.y = g.get_meta("y") + sin(t * 2.2) * 0.07

	var e_now: bool = Input.is_key_pressed(KEY_E) and not player.downed and not player.input_blocked
	var e_down: bool = e_now and not e_prev
	e_prev = e_now
	prompt.text = ""
	bar.visible = false
	if stage == 0 and modo_cerdo:
		_cerdo_update(delta, e_down)
	elif stage == 0:
		if reto != "":
			_reto_update(delta)
		else:
			for p in mapa.pistas:
				if not found[p[0]] and _dist(p[3]) < 2.2:
					var tp: String = tipo[p[0]]
					prompt.text = "[E] Prueba de %s: %s  ·  %s" % [NOMBRE_TIPO[tp], p[1], REGLA[tp]]
					if e_down:
						_empezar(p)
					break
	elif stage == 1 and not modo_cerdo:
		if _dist(mapa.puerta_pos) < 2.2:
			prompt.text = "Mantén [E] para abrir la puerta del aula"
			if e_now:
				hold += delta
			bar.visible = true
			bar.value = hold / FORCE_TIME * 100.0
			if hold >= FORCE_TIME:
				hold = 0.0
				_send_inv("salir")
				return
		if _dist(mapa.puerta_pos) < 12.0:
			_horde(delta, 2.2)
	_update_inv()


func _update_inv() -> void:
	if modo_cerdo:
		_cerdo_inv()
		return
	var s := "¿DÓNDE ESTÁS?\n%s\n" % mapa.titulo
	var n := 0
	var nearest := INF
	for p in mapa.pistas:
		if found[p[0]]:
			n += 1
			s += "✔  %s\n" % p[1]
		else:
			nearest = minf(nearest, _dist(p[3]))
	if stage == 0:
		if reto != "":
			s += "▶  %s: %s\n" % [NOMBRE_TIPO[reto_tipo], _estado_reto()]
		s += "○  Pruebas: %d / %d" % [n, mapa.pistas.size()]
		if nearest < INF and reto == "":
			s += "\n     la más cercana a %d m" % int(nearest)
	else:
		s += "○  Cruza la puerta del aula · %d m" % int(_dist(mapa.puerta_pos))
	obj_lbl.text = s
	for p in mapa.pistas:
		var m: Label3D = markers[p[0]]
		m.visible = not found[p[0]] and _dist(p[3]) < NEAR_MARK and reto != p[0]
		if m.visible:
			m.text = "!\n%s\n%d m" % [NOMBRE_TIPO[tipo[p[0]]].to_upper(), int(_dist(p[3]))]
	if markers["door"].visible:
		markers["door"].text = "LA PUERTA DEL AULA\n%d m" % int(_dist(mapa.puerta_pos))


# =============================================================
# Pruebas de habilidad
# =============================================================
func _empezar(p: Array) -> void:
	reto = p[0]
	reto_tipo = tipo[reto]
	reto_pos = p[3]
	rt = 0.0
	r = {}
	flecha_prev = [true, true, true, true]
	_say("PRUEBA DE %s\n%s" % [NOMBRE_TIPO[reto_tipo].to_upper(), REGLA[reto_tipo]], Color(1.0, 0.85, 0.3))
	snd_pick.play()
	match reto_tipo:
		"dianas":
			r = {"n": 0, "aciertos": 0, "fallos": 0, "next": 1.2, "vivas": []}
		"memoria":
			r = {"ronda": 0, "seq": [], "fase": "espera", "ft": 1.0, "i": 0}
			_memoria_lamparas()
		"reflejos":
			r = {"n": 0, "flecha": -1, "ft": 1.0, "lim": 1.2}
		"aguante":
			r = {"p": 0.0, "spawn": 1.0}
			_aguante_circulo()
		"carrera":
			_carrera_ruta()


func _reto_update(delta: float) -> void:
	rt += delta
	if player.downed:
		_fallar("Te han tumbado")
		return
	var pulsada := _flecha_pulsada()
	match reto_tipo:
		"dianas":
			_dianas_update(delta)
		"memoria":
			_memoria_update(delta, pulsada)
		"reflejos":
			_reflejos_update(delta, pulsada)
		"aguante":
			_aguante_update(delta)
		"carrera":
			_carrera_update(delta)


func _estado_reto() -> String:
	match reto_tipo:
		"dianas":
			return "%d / %d dianas" % [r.get("aciertos", 0), DIANAS_OK]
		"memoria":
			return "ronda %d / 3" % (r.get("ronda", 0) + 1)
		"reflejos":
			return "%d / %d" % [r.get("n", 0), REFLEJOS_N]
		"aguante":
			return "%d / %d s" % [int(r.get("p", 0.0)), int(AGUANTE_T)]
		"carrera":
			return "punto %d / %d" % [r.get("i", 0) + 1, r.get("pts", []).size()]
	return ""


# Devuelve la flecha que acabas de pulsar (0..3) o -1
func _flecha_pulsada() -> int:
	var res := -1
	for i in 4:
		var on: bool = Input.is_key_pressed(TECLAS[i]) and not player.input_blocked
		if on and not flecha_prev[i]:
			res = i
		flecha_prev[i] = on
	return res


func _superar() -> void:
	var id := reto
	_limpiar()
	snd_ok.play()
	_send_inv("pista", id)


func _fallar(por: String) -> void:
	_limpiar()
	snd_mal.play()
	red_rect.color.a = 0.35
	red_rect.create_tween().tween_property(red_rect, "color:a", 0.0, 0.6)
	_say("¡PRUEBA FALLADA!\n%s. Vuelve al «!» para intentarlo otra vez." % por, Color(1.0, 0.35, 0.3))


func _cancelar() -> void:
	_limpiar()


func _limpiar() -> void:
	reto = ""
	reto_tipo = ""
	for n in reto_nodes:
		if is_instance_valid(n):
			n.queue_free()
	reto_nodes.clear()
	r = {}
	big_lbl.text = ""
	timer_lbl.visible = false


# ---------------- Puntería ----------------
func _dianas_update(delta: float) -> void:
	r["next"] -= delta
	if r["n"] < DIANAS and r["next"] <= 0.0:
		r["next"] = 1.25
		r["n"] += 1
		var d := Diana.new()
		d.pos_ok = _punto_diana()
		d.vida = 2.7
		d.reto = self
		add_child(d)
		d.global_position = d.pos_ok
		reto_nodes.append(d)
	# se acaba cuando ya han salido todas y no queda ninguna
	var quedan := 0
	for n in reto_nodes:
		if is_instance_valid(n) and not n.is_queued_for_deletion():
			quedan += 1
	big_lbl.text = "%d / %d" % [r["aciertos"], DIANAS_OK]
	big_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	if r["aciertos"] >= DIANAS_OK:
		_superar()
	elif r["n"] >= DIANAS and quedan == 0:
		_fallar("Solo has dado a %d de %d dianas" % [r["aciertos"], DIANAS_OK])


func diana_tocada(d) -> void:
	if reto_tipo != "dianas":
		return
	r["aciertos"] += 1
	snd_tonos[r["aciertos"] % 4].play()


# Un punto al aire libre: en el camino entre la prueba y otro sitio conocido del mapa
func _punto_diana() -> Vector3:
	var cand: Array = []
	for q in _sitios():
		var dd: float = Vector2(q.x - reto_pos.x, q.z - reto_pos.z).length()
		if dd > 6.0 and dd < 30.0:
			cand.append(q)
	var a: Vector3 = player.global_position
	var b: Vector3 = cand.pick_random() if cand.size() > 0 else reto_pos + Vector3(randf_range(-8, 8), 0, randf_range(-8, 8))
	var k := randf_range(0.35, 0.8)
	var p := a.lerp(b, k)
	p += Vector3(randf_range(-1.5, 1.5), 0.0, randf_range(-1.5, 1.5))
	p = U.clamp_pos(p, 0.6)
	p.y = randf_range(1.2, 2.8)
	return p


# ---------------- Memoria ----------------
func _memoria_lamparas() -> void:
	var lado := Vector3(1, 0, 0)
	var to_p: Vector3 = player.global_position - reto_pos
	to_p.y = 0.0
	if to_p.length() > 0.1:
		lado = to_p.normalized().cross(Vector3.UP)
	r["lamps"] = []
	for i in 4:
		var n := Node3D.new()
		add_child(n)
		n.global_position = reto_pos + Vector3(0, 2.4, 0) + lado * (i - 1.5) * 0.9
		var s := U.sphere(n, 0.28, Vector3.ZERO, COLORES[i], true)
		s.material_override.emission_energy_multiplier = 0.15
		var l := Label3D.new()
		l.text = FLECHAS[i]
		l.font_size = 64
		l.pixel_size = 0.004
		l.outline_size = 8
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.position.y = -0.55
		n.add_child(l)
		reto_nodes.append(n)
	r["lamps_mesh"] = []
	for n in reto_nodes:
		r["lamps_mesh"].append(n.get_child(0))


func _lampara(i: int, on: bool) -> void:
	var m: MeshInstance3D = r["lamps_mesh"][i]
	m.material_override.emission_energy_multiplier = 4.0 if on else 0.15
	m.scale = Vector3.ONE * (1.25 if on else 1.0)


func _memoria_update(delta: float, pulsada: int) -> void:
	if not r.has("lamps"):
		_memoria_lamparas()
	r["ft"] -= delta
	match r["fase"]:
		"espera":          # pausa antes de enseñar la ronda
			big_lbl.text = "MIRA..."
			if r["ft"] <= 0.0:
				r["seq"].append(randi() % 4)
				if r["seq"].size() < 3 + r["ronda"]:
					r["ft"] = 0.0
					return
				r["fase"] = "muestra"
				r["i"] = 0
				r["ft"] = 0.3
		"muestra":         # se encienden de una en una
			if r["ft"] <= 0.0:
				var k: int = r["i"]
				if k >= r["seq"].size() * 2:
					r["fase"] = "turno"
					r["i"] = 0
					r["ft"] = 0.0
					return
				var idx: int = r["seq"][k / 2]
				_lampara(idx, k % 2 == 0)
				if k % 2 == 0:
					snd_tonos[idx].play()
				r["ft"] = 0.5 if k % 2 == 0 else 0.22
				r["i"] = k + 1
		"turno":
			big_lbl.text = "TU TURNO  %d / %d" % [r["i"], r["seq"].size()]
			if pulsada >= 0:
				_lampara(pulsada, true)
				snd_tonos[pulsada].play()
				get_tree().create_timer(0.2).timeout.connect(func():
					if reto_tipo == "memoria" and r.has("lamps_mesh"):
						_lampara(pulsada, false))
				if pulsada != r["seq"][r["i"]]:
					_fallar("Te has equivocado en la secuencia")
					return
				r["i"] += 1
				if r["i"] >= r["seq"].size():
					r["ronda"] += 1
					if r["ronda"] >= 3:
						_superar()
						return
					r["fase"] = "espera"
					r["ft"] = 1.0
					r["seq"] = []
					snd_pick.play()
	big_lbl.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))


# ---------------- Reflejos ----------------
func _reflejos_update(delta: float, pulsada: int) -> void:
	r["ft"] -= delta
	if r["flecha"] < 0:
		big_lbl.text = "PREPÁRATE..." if r["n"] == 0 else ""
		if pulsada >= 0 and r["n"] > 0:
			_fallar("Te has adelantado")
			return
		if r["ft"] <= 0.0:
			r["flecha"] = randi() % 4
			r["ft"] = r["lim"]
			snd_beep.play()
		return
	big_lbl.text = FLECHAS[r["flecha"]]
	big_lbl.add_theme_color_override("font_color", COLORES[r["flecha"]])
	timer_lbl.visible = true
	timer_lbl.text = "%.1f" % maxf(r["ft"], 0.0)
	if pulsada >= 0:
		if pulsada != r["flecha"]:
			_fallar("Esa no era la flecha")
			return
		snd_tonos[pulsada].play()
		r["n"] += 1
		r["flecha"] = -1
		r["ft"] = randf_range(0.35, 1.1)       # pausa aleatoria para que no te lo sepas
		r["lim"] = maxf(0.6, r["lim"] - 0.07)  # cada vez hay menos tiempo
		timer_lbl.visible = false
		if r["n"] >= REFLEJOS_N:
			_superar()
	elif r["ft"] <= 0.0:
		_fallar("Demasiado lento")


# ---------------- Aguante ----------------
func _aguante_circulo() -> void:
	var n := Node3D.new()
	add_child(n)
	n.global_position = Vector3(reto_pos.x, 0.05, reto_pos.z)
	var anillo := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = AGUANTE_R - 0.12
	tm.outer_radius = AGUANTE_R
	tm.rings = 48
	anillo.mesh = tm
	anillo.material_override = U.mat(Color(1.0, 0.6, 0.15), true)
	n.add_child(anillo)
	var suelo := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = AGUANTE_R
	cm.bottom_radius = AGUANTE_R
	cm.height = 0.02
	suelo.mesh = cm
	var m := U.mat(Color(1.0, 0.6, 0.15, 0.18), true)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	suelo.material_override = m
	n.add_child(suelo)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.6, 0.2)
	l.light_energy = 1.5
	l.omni_range = AGUANTE_R + 2.0
	l.position.y = 2.0
	n.add_child(l)
	reto_nodes.append(n)


func _aguante_update(delta: float) -> void:
	var dentro := _dist(reto_pos) < AGUANTE_R
	if dentro:
		r["p"] += delta
	else:
		r["p"] = maxf(0.0, r["p"] - delta * 0.5)
	bar.visible = true
	bar.value = r["p"] / AGUANTE_T * 100.0
	big_lbl.text = "" if dentro else "¡VUELVE AL CÍRCULO!"
	big_lbl.add_theme_color_override("font_color", Color(1.0, 0.45, 0.3))
	prompt.text = "Aguante: %d / %d s" % [int(r["p"]), int(AGUANTE_T)]
	# llegan zombis sin parar (los crea el anfitrión)
	if Net.is_host():
		r["spawn"] -= delta
		if r["spawn"] <= 0.0:
			r["spawn"] = 2.4
			if get_tree().get_nodes_in_group("zombies").size() < 16:
				game._spawn_enemy()
	if r["p"] >= AGUANTE_T:
		_superar()
	elif rt > AGUANTE_T * 3.0:
		_fallar("Has pasado demasiado tiempo fuera del círculo")


# ---------------- Contrarreloj ----------------
func _sitios() -> Array:
	var res: Array = []
	for s in mapa.spawns:
		res.append(s)
	for b in game.box_spots:
		res.append(b[0])
	for p in mapa.pistas:
		res.append(p[3])
	return res


# Ruta de 5 puntos por sitios conocidos del mapa (así siempre se puede llegar)
func _carrera_ruta() -> void:
	var libres := _sitios()
	var pts: Array = []
	var cur: Vector3 = player.global_position
	var total := 0.0
	for k in 5:
		var mejor := -1
		var md := INF
		for i in libres.size():
			var q: Vector3 = libres[i]
			var d := Vector2(q.x - cur.x, q.z - cur.z).length()
			if d >= 9.0 and d < md:
				md = d
				mejor = i
		if mejor < 0:
			break
		var q2: Vector3 = libres[mejor]
		libres.remove_at(mejor)
		q2 = U.clamp_pos(Vector3(q2.x, 0.0, q2.z), 0.6)
		pts.append(q2)
		total += md
		cur = q2
	r = {"pts": pts, "i": 0, "lim": total / 6.3 + 6.0, "aros": []}
	for i in pts.size():
		var n := Node3D.new()
		add_child(n)
		n.global_position = pts[i]
		var aro := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 1.0
		tm.outer_radius = 1.18
		aro.mesh = tm
		aro.material_override = U.mat(Color(0.3, 1.0, 0.9), true)
		aro.rotation_degrees.x = 90.0
		aro.position.y = 1.3
		n.add_child(aro)
		var haz := U.box(n, Vector3(0.25, 8.0, 0.25), Vector3(0, 4.0, 0), Color(0.3, 1.0, 0.9, 0.25), true)
		haz.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		haz.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var num := Label3D.new()
		num.text = str(i + 1)
		num.font_size = 90
		num.pixel_size = 0.006
		num.outline_size = 10
		num.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		num.no_depth_test = true
		num.position.y = 2.9
		n.add_child(num)
		reto_nodes.append(n)
		r["aros"].append(n)
	_carrera_marcar()


func _carrera_marcar() -> void:
	for i in r["aros"].size():
		var n: Node3D = r["aros"][i]
		n.visible = i >= r["i"] and i <= r["i"] + 1
		n.scale = Vector3.ONE * (1.0 if i == r["i"] else 0.6)


func _carrera_update(delta: float) -> void:
	var pts: Array = r["pts"]
	if pts.is_empty():
		_superar()
		return
	var left: float = r["lim"] - rt
	timer_lbl.visible = true
	timer_lbl.text = "%.1f" % maxf(left, 0.0)
	var obj: Vector3 = pts[r["i"]]
	prompt.text = "Corre al punto %d · %d m" % [r["i"] + 1, int(_dist(obj))]
	big_lbl.text = ""
	var aro: Node3D = r["aros"][r["i"]]
	aro.rotation.y += 2.0 * delta
	if _dist(obj) < 1.8:
		snd_tonos[r["i"] % 4].play()
		r["i"] += 1
		if r["i"] >= pts.size():
			_superar()
			return
		aro.visible = false
		_carrera_marcar()
	elif left <= 0.0:
		_fallar("Se te ha acabado el tiempo")


# =============================================================
# Pasos (en red se aplican en todos los PCs)
# =============================================================
func _send_inv(what: String, id: String = "") -> void:
	if Net.online:
		_net_inv.rpc(what, id)
	else:
		_net_inv(what, id)


@rpc("any_peer", "call_local", "reliable")
func _net_inv(what: String, id: String) -> void:
	match what:
		"pista":
			if stage == 0 and found.has(id) and not found[id]:
				_found(id)
		"salir":
			if stage == 1:
				_leave()
		"comer":
			if modo_cerdo and stage == 0:
				_cerdo_come(id)
		"soltar":
			if modo_cerdo and stage == 0:
				_comida_aparece(id)
		"cogida":
			_comida_quitar(id)


func _found(id: String) -> void:
	found[id] = true
	if reto == id:          # otro jugador la ha superado mientras la hacías tú
		_limpiar()
	snd_pick.play()
	var g: Node3D = glints[id]
	var tw := g.create_tween()
	tw.tween_property(g, "scale", Vector3.ONE * 1.8, 0.12)
	tw.tween_property(g, "scale", Vector3.ZERO, 0.2)
	tw.tween_callback(g.hide)
	markers[id].visible = false
	for p in mapa.pistas:
		if p[0] == id:
			_read("¡PRUEBA SUPERADA!  ·  " + p[1], p[2])
	# cada prueba superada "despierta" a alguien
	if Net.is_host():
		for i in 2:
			game._spawn_enemy()
	var left := 0
	for k in found:
		if not found[k]:
			left += 1
	if left == 0:
		stage = 1
		hold = 0.0
		get_tree().create_timer(READ_TIME).timeout.connect(_show_door)


func _show_door() -> void:
	door.visible = true
	door.scale = Vector3(1, 0.01, 1)
	door.create_tween().tween_property(door, "scale", Vector3.ONE, 0.8).set_trans(Tween.TRANS_BACK)
	markers["door"].visible = true
	shake = 0.5
	_say("Lo tienes todo... y nada tiene sentido.\nHa aparecido una puerta donde no debería haber ninguna: la puerta del aula.", Color(0.5, 1.0, 0.6))
	for l in game.hall_lights:
		l.light_color = Color(1.0, 0.95, 0.75)


func _leave() -> void:
	stage = 3
	if reto != "":
		_limpiar()
	prompt.text = ""
	bar.visible = false
	obj_lbl.get_parent().visible = false
	reader.visible = false
	for m in markers.values():
		m.visible = false
	player.frozen = true
	game.hud.visible = false
	game.spawn_left = 0
	for z in get_tree().get_nodes_in_group("zombies"):
		z.queue_free()
	if not modo_cerdo:
		var hoja: Node3D = door.get_node("Hoja")
		hoja.create_tween().tween_property(hoja, "rotation_degrees:y", -100.0, 1.2).set_trans(Tween.TRANS_SINE)
	snd_hum = AudioStreamPlayer.new()
	snd_hum.stream = MapasScript.zumbido()
	snd_hum.volume_db = -10.0
	add_child(snd_hum)
	snd_hum.play()
	var tw := create_tween()
	tw.tween_interval(1.0)
	tw.tween_property(flash, "color", Color(1.0, 0.97, 0.85, 1.0), 1.2)
	for ln in mapa.salida:
		tw.tween_callback(_twist_line.bind(ln))
		tw.tween_interval(2.2)
	tw.tween_callback(_go_next)


# Al cruzar la puerta: el siguiente sitio del bucle (del hotel se vuelve a CESUR)
func _go_next() -> void:
	game.save_carry()
	if Net.is_host():
		Net.go_to_map(MapasScript.siguiente(Net.mapa), Net.bucle)


func _twist_line(text: String) -> void:
	super(text)
	twist_lbl.add_theme_color_override("font_color", Color(0.1, 0.08, 0.05))
	twist_lbl.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.6))


# ---------------- Panel con el texto que descubres ----------------
func _read(title: String, text: String) -> void:
	brief.modulate.a = 0.0          # que no se pise con el texto de la intro
	read_title.text = title.to_upper()
	read_text.text = text
	reader.visible = true
	reader.modulate.a = 0.0
	if read_tw:
		read_tw.kill()
	read_tw = reader.create_tween()
	read_tw.tween_property(reader, "modulate:a", 1.0, 0.3)
	read_tw.tween_interval(READ_TIME)
	read_tw.tween_property(reader, "modulate:a", 0.0, 0.8)
	read_tw.tween_callback(reader.hide)


func _build_reader() -> void:
	reader = PanelContainer.new()
	var st := HudScript.panel_style(0.72)
	st.content_margin_left = 26
	st.content_margin_right = 26
	st.content_margin_top = 16
	st.content_margin_bottom = 18
	reader.add_theme_stylebox_override("panel", st)
	reader.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	reader.grow_horizontal = Control.GROW_DIRECTION_BOTH
	reader.grow_vertical = Control.GROW_DIRECTION_BEGIN
	reader.offset_bottom = -250.0
	reader.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reader.visible = false
	layer.add_child(reader)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	reader.add_child(box)
	read_title = Label.new()
	read_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	read_title.add_theme_font_size_override("font_size", 22)
	read_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	box.add_child(read_title)
	read_text = Label.new()
	read_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	read_text.add_theme_font_size_override("font_size", 20)
	read_text.add_theme_color_override("font_color", Color(0.95, 0.93, 0.85))
	read_text.add_theme_constant_override("line_spacing", 4)
	box.add_child(read_text)


func _build_reto_ui() -> void:
	big_lbl = Label.new()
	big_lbl.set_anchors_preset(Control.PRESET_CENTER)
	big_lbl.offset_left = -400.0
	big_lbl.offset_right = 400.0
	big_lbl.offset_top = -150.0
	big_lbl.offset_bottom = -40.0
	big_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	big_lbl.add_theme_font_size_override("font_size", 72)
	big_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	big_lbl.add_theme_constant_override("outline_size", 12)
	big_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(big_lbl)
	snd_ok = AudioStreamPlayer.new()
	snd_ok.stream = _tone(520.0, 0.5, 700.0)
	snd_ok.volume_db = -4.0
	add_child(snd_ok)
	snd_mal = AudioStreamPlayer.new()
	snd_mal.stream = _tone(220.0, 0.5, -120.0)
	snd_mal.volume_db = -4.0
	add_child(snd_mal)
	for f in [392.0, 523.3, 659.3, 784.0]:        # un tono por flecha/luz
		var a := AudioStreamPlayer.new()
		a.stream = _tone(f, 0.22, 0.0)
		a.volume_db = -6.0
		add_child(a)
		snd_tonos.append(a)


# Brillo flotante que marca una prueba (un "!" de color dentro de un aro)
func _glint(pos: Vector3, c: Color = Color(1.0, 0.85, 0.3)) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.set_meta("y", pos.y)
	add_child(n)
	var tor := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.15
	tm.outer_radius = 0.2
	tor.mesh = tm
	tor.material_override = U.mat(c, true)
	tor.rotation_degrees.x = 90.0
	n.add_child(tor)
	var q := Label3D.new()
	q.text = "!"
	q.font_size = 72
	q.pixel_size = 0.004
	q.outline_size = 8
	q.modulate = c.lightened(0.3)
	q.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	n.add_child(q)
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = 1.0
	l.omni_range = 3.0
	n.add_child(l)
	return n


# Diana de la prueba de puntería: sale, se queda unos segundos y se esconde.
# player.gd la detecta en sus disparos (grupo "dianas") y llama a diana_hit().
class Diana extends Node3D:
	const U2 = preload("res://scripts/nucleo/util.gd")
	var radius := 0.65
	var vida := 2.7
	var pos_ok := Vector3.ZERO
	var reto
	var t := 0.0
	var tocada := false
	var disco: Node3D

	func _ready() -> void:
		add_to_group("dianas")
		disco = Node3D.new()
		add_child(disco)
		var cols := [Color(0.95, 0.95, 0.92), Color(0.85, 0.1, 0.1)]
		for i in 4:
			var c := U2.cylinder(disco, 0.5 - i * 0.12, 0.04 + i * 0.012, Vector3.ZERO, cols[i % 2], i == 3)
			c.rotation_degrees.x = 90.0
		U2.cylinder(disco, 0.03, 1.4, Vector3(0, -0.75, 0), Color(0.3, 0.3, 0.32))
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.3, 0.25)
		l.light_energy = 0.8
		l.omni_range = 2.5
		add_child(l)
		disco.scale = Vector3.ZERO
		disco.create_tween().tween_property(disco, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK)

	func _process(delta: float) -> void:
		t += delta
		var cam := get_viewport().get_camera_3d()
		if cam != null:        # siempre de cara a ti
			var to := cam.global_position - global_position
			to.y = 0.0
			if to.length() > 0.01:
				rotation.y = atan2(to.x, to.z)
		if not tocada and t > vida:
			tocada = true
			remove_from_group("dianas")
			var tw := disco.create_tween()
			tw.tween_property(disco, "scale", Vector3.ZERO, 0.15)
			tw.tween_callback(queue_free)

	func diana_hit() -> void:
		if tocada:
			return
		tocada = true
		remove_from_group("dianas")
		if reto != null and is_instance_valid(reto):
			reto.diana_tocada(self)
		var tw := disco.create_tween()
		tw.tween_property(disco, "scale", Vector3.ONE * 1.3, 0.06)
		tw.tween_property(disco, "scale", Vector3.ZERO, 0.12)
		tw.tween_callback(queue_free)


# =============================================================
# Mojácar: Jorge, el cerdo glotón
# =============================================================
func _cerdo_preparar() -> void:
	modo_cerdo = true
	cerdo = CerdoScript.new()
	cerdo.position = mapa.cerdo_pos
	cerdo.rotation_degrees.y = mapa.cerdo_yaw
	add_child(cerdo)
	cerdo.reventado.connect(_cerdo_bum)
	markers["cerdo"] = _marker(mapa.cerdo_pos + Vector3(0, 4.2, 0), Color(1.0, 0.6, 0.7), "JORGE")
	brief.text = mapa.intro.replace("Investiga.", "") + "\nEn la playa hay un cerdo enorme muerto de hambre. Mata zombis: sueltan comida.\nLlévasela: cuanto más coma, más se hincha... A ver qué pasa si revienta."
	brief.add_theme_color_override("font_color", Color(0.95, 0.92, 0.8))
	var tw := create_tween()
	tw.tween_interval(9.0)
	tw.tween_property(brief, "modulate:a", 0.0, 1.2)


# main.gd (en el anfitrión) avisa de cada zombi muerto: a veces suelta comida
func soltar_comida(pos: Vector3) -> void:
	if not modo_cerdo or stage != 0 or not Net.is_host():
		return
	if not comidas.is_empty() and randf() > COMIDA_PROB:
		return
	n_soltadas += 1
	var p := U.clamp_pos(pos, 0.5)
	var tipo: String = CerdoScript.TIPOS[randi() % CerdoScript.TIPOS.size()]
	_send_inv("soltar", "%d|%s|%f|%f" % [n_soltadas, tipo, p.x, p.z])


func _comida_aparece(id: String) -> void:
	var pt := id.split("|")
	if pt.size() < 4 or comidas.has(pt[0]):
		return
	var p := Vector3(float(pt[2]), 0.0, float(pt[3]))
	var n := _comida_nodo(pt[1], p)
	comidas[pt[0]] = {"nodo": n, "pos": p, "tipo": pt[1], "vida": COMIDA_VIDA}
	# sale disparada del zombi y cae al suelo
	var y: float = n.position.y
	n.position.y = 1.2
	var tw := n.create_tween()
	tw.tween_property(n, "position:y", 2.2, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(n, "position:y", y, 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BOUNCE)


func _comida_quitar(id: String) -> void:
	if not comidas.has(id):
		return
	var n: Node3D = comidas[id]["nodo"]
	comidas.erase(id)
	var tw := n.create_tween()
	tw.tween_property(n, "scale", Vector3.ONE * 0.01, 0.15)
	tw.tween_callback(n.queue_free)


# La comida: gira, flota y tiene una lucecita
func _comida_nodo(tipo: String, p: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = p + Vector3(0, 0.8, 0)
	n.set_meta("y", n.position.y)
	add_child(n)
	var c := CerdoScript.comida(tipo)
	c.scale = Vector3.ONE * 1.8
	n.add_child(c)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.75, 0.5)
	l.light_energy = 0.8
	l.omni_range = 2.5
	n.add_child(l)
	var m := _marker(Vector3(0, 0.75, 0), Color(1.0, 0.85, 0.4), "COMIDA")
	remove_child(m)
	n.add_child(m)
	n.set_meta("marca", m)
	return n


func _cerdo_frente() -> Vector3:
	return mapa.cerdo_pos + cerdo.global_transform.basis.z * 1.6


func _cerdo_update(delta: float, e_down: bool) -> void:
	# coger comida (basta con pasar por encima)
	for id in comidas.keys():
		var c: Dictionary = comidas[id]
		var n: Node3D = c["nodo"]
		n.rotation.y += 1.4 * delta
		c["vida"] -= delta
		var d := _dist(c["pos"])
		var m: Label3D = n.get_meta("marca")
		m.visible = d < 30.0
		if m.visible:
			m.text = "COMIDA\n%d m" % int(d)
		if c["vida"] < 5.0:                      # parpadea antes de desaparecer
			n.visible = fmod(c["vida"], 0.3) > 0.12
		if c["vida"] <= 0.0:
			_comida_quitar(id)
			continue
		if d < 1.6 and llevas.size() < LLEVAR_MAX and not player.dead and not player.downed:
			llevas.append(c["tipo"])
			_comida_quitar(id)
			_send_inv("cogida", id)
			snd_pick.play()
			if llevas.size() == LLEVAR_MAX:
				_say("Llevas todo lo que puedes (%d). ¡A darle de comer a Jorge!" % LLEVAR_MAX, Color(1.0, 0.8, 0.5))
	# darle de comer
	var cerca := _dist(_cerdo_frente()) < 2.6 or _dist(mapa.cerdo_pos) < 2.4
	cerdo.boca_abierta = llevas.size() > 0 and _dist(mapa.cerdo_pos) < 7.0
	if cerca:
		if llevas.is_empty():
			prompt.text = "Jorge tiene hambre. Mata zombis: sueltan comida"
		else:
			prompt.text = "[E] Darle de comer a Jorge  ·  llevas %d" % llevas.size()
			if e_down and not cerdo.reventando:
				var tipo: String = llevas.pop_back()
				var desde: Vector3 = player.cam.global_position + (-player.cam.global_transform.basis.z) * 0.6 + Vector3(0, -0.25, 0)
				_send_inv("comer", "%s|%f|%f|%f" % [tipo, desde.x, desde.y, desde.z])


func _cerdo_come(id: String) -> void:
	var partes := id.split("|")
	var tipo := partes[0]
	var desde := _cerdo_frente() + Vector3(0, 1.4, 0)
	if partes.size() == 4:
		desde = Vector3(float(partes[1]), float(partes[2]), float(partes[3]))
	comido += 1
	cerdo.comer(tipo, comido, COMIDA_TOTAL, desde)
	if comido >= COMIDA_TOTAL:
		stage = 1
		prompt.text = ""
		_say("¡¡Jorge no puede más!! ¡Apártate!", Color(1.0, 0.5, 0.55))
		get_tree().create_timer(1.2).timeout.connect(cerdo.reventar)
	elif comido == COMIDA_TOTAL - 2:
		_say("Está a punto de reventar...", Color(1.0, 0.7, 0.6))


func _cerdo_bum() -> void:
	snd_boom.play()
	shake = 1.6
	var fl := create_tween()
	fl.tween_property(flash, "color", Color(1.0, 0.75, 0.8, 0.85), 0.06)
	fl.tween_property(flash, "color:a", 0.0, 1.0)
	markers["cerdo"].visible = false
	var luz := OmniLight3D.new()
	luz.light_color = Color(1.0, 0.7, 0.75)
	luz.light_energy = 10.0
	luz.omni_range = 18.0
	luz.position = mapa.cerdo_pos + Vector3(0, 2.0, 0)
	add_child(luz)
	luz.create_tween().tween_property(luz, "light_energy", 0.0, 2.5)
	# la onda expansiva se lleva por delante a los zombis de alrededor
	if Net.is_host():
		for z in get_tree().get_nodes_in_group("zombies"):
			var d: Vector3 = z.global_position - mapa.cerdo_pos
			if not z.dying and d.length() < 12.0:
				game.damage_enemy(z, 99999.0, d.normalized())
	_say("¡¡BUUUM!!\nJorge ha reventado. Llueve sandía... y el aire huele a tiza.", Color(1.0, 0.75, 0.8))
	get_tree().create_timer(4.0).timeout.connect(_leave)


func _cerdo_inv() -> void:
	var s := "¿DÓNDE ESTÁS?\n%s\n" % mapa.titulo
	if stage == 0:
		s += "○  Dale de comer a Jorge: %d / %d\n" % [comido, COMIDA_TOTAL]
		if llevas.is_empty():
			var mejor := INF
			for c in comidas.values():
				mejor = minf(mejor, _dist(c["pos"]))
			s += ("     hay comida a %d m" % int(mejor)) if mejor < INF else "     mata zombis: sueltan comida"
		else:
			s += "     llevas %d / %d · Jorge está a %d m" % [llevas.size(), LLEVAR_MAX, int(_dist(mapa.cerdo_pos))]
	else:
		s += "✔  Jorge ha reventado"
	obj_lbl.text = s
	var mk: Label3D = markers["cerdo"]
	if mk.visible:
		mk.text = "JORGE\n%d / %d  ·  %d m" % [comido, COMIDA_TOTAL, int(_dist(mapa.cerdo_pos))]
		mk.position.y = 4.2 + cerdo.gordura * 0.8


# consola: "cerdo" le da de comer una vez, "cerdo reventar" lo llena del todo
func cerdo_debug(todo: bool) -> void:
	if not modo_cerdo or stage != 0:
		return
	var n := COMIDA_TOTAL - comido if todo else 1
	for i in n:
		_send_inv("comer", CerdoScript.TIPOS[randi() % CerdoScript.TIPOS.size()])

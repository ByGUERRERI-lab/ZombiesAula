extends Node3D
# Minijuego: partido de pádel contra Víctor en la pista del patio de CESUR.
# Entra en la pista y pulsa E en el marcador. Mientras dura el partido se paran
# las oleadas, los enemigos se quedan quietos y nadie te hace daño (como con la
# cámara libre). Solo en partidas de un jugador.
#  · Te mueves con WASD por tu mitad de la pista (la del sur) y Shift para correr.
#  · Clic izquierdo para darle a la bola cuando la tengas cerca. La bola va hacia
#    donde miras: mira más arriba para tirarla más al fondo. Si la bola viene alta,
#    el golpe es un remate (más fuerte).
#  · Reglas de pádel simplificadas: la bola tiene que botar primero en el suelo del
#    otro campo (si da antes en el cristal es falta); después puede rebotar en los
#    cristales. Dos botes en tu campo = punto para el otro. Se puede volear.
#  · Puntos 15-30-40 con punto de oro en el 40-40. Gana quien llegue a 3 juegos.
#  · Si ganas: +2000 puntos y una bebida gratis de las máquinas.
#  · Retroceso: abandonar el partido.

const U = preload("res://scripts/nucleo/util.gd")
const Ch = preload("res://scripts/jugador/character.gd")
const HudScript = preload("res://scripts/interfaz/hud.gd")
const BebidasScript = preload("res://scripts/jugador/bebidas.gd")

const HW := 5.0              # media anchura de la pista (x)
const HL := 10.0             # media longitud (z); la red está en z = 0
const RED_ALTO := 0.92
const GRAV := 9.8
const BOLA_R := 0.05
const JUEGOS_GANAR := 3
const PUNTOS := ["0", "15", "30", "40"]
const VEL_CPU := 5.4

var game
var c := Vector3.ZERO        # centro de la pista
var jugando := false
var item: Dictionary

# bola
var bola: MeshInstance3D
var sombra: MeshInstance3D
var bpos := Vector3.ZERO
var bvel := Vector3.ZERO
var bola_viva := false
var ultimo := ""             # "tu" o "cpu": quién ha dado el último golpe
var botes := 0               # botes en el campo de quien tiene que devolverla
var t_golpe := 0.0
var saque := "tu"            # quién saca en este juego
var esperando_saque := false
var pausa := 0.0             # pausa entre puntos

# marcador
var pt := {"tu": 0, "cpu": 0}
var juegos := {"tu": 0, "cpu": 0}

# Víctor
var cpu: Node3D
var cpu_rig: Dictionary
var cpu_model: Node3D
var cpu_obj := Vector3.ZERO
var cpu_ph := 0.0
var cpu_swing := 0.0
var cpu_saque_t := 0.0

# jugador
var pala: Node3D
var swing := 0.0
var lmb_prev := false
var antes := {}

# interfaz y sonidos
var capa: CanvasLayer
var marcador: Label
var aviso: Label
var ayuda: Label
var snd_pala: AudioStreamPlayer3D
var snd_bote: AudioStreamPlayer3D
var snd_red: AudioStreamPlayer3D
var snd_punto: AudioStreamPlayer
var snd_publico: AudioStreamPlayer


func _ready() -> void:
	var r: Rect2 = U.SALAS[U.R_PATIO]
	var cc := r.get_center()
	c = Vector3(cc.x, 0.0, cc.y)
	_build_poste()
	_build_bola()
	_build_cpu()
	_build_ui()
	_build_sonidos()
	item = {"type": "padel", "pos": c + Vector3(-3.9, 0.0, -2.2), "done": false}
	game.interactables.append(item)


# ---------------- Empezar y acabar ----------------
func prompt() -> String:
	return "[E] Jugar un partido de pádel contra Víctor  ·  premio: 2000 puntos y una bebida"


func empezar() -> void:
	if jugando:
		return
	if Net.online:
		game.toast_small("El pádel solo se puede jugar en partidas de un jugador")
		return
	var pl = game.player
	jugando = true
	game.explorando = true
	_congelar(true)
	antes = {"cur": pl.cur, "gun": pl.gun_holder.visible, "kat": pl.katana_pivot.visible if pl.katana_pivot else false}
	pl.gun_holder.visible = false
	if pl.katana_pivot:
		pl.katana_pivot.visible = false
	pl.global_position = c + Vector3(0.0, 0.05, -7.5)
	pl.rotation.y = PI
	pala.visible = true
	cpu.visible = true
	cpu.global_position = c + Vector3(0.0, 0.0, 7.5)
	pt = {"tu": 0, "cpu": 0}
	juegos = {"tu": 0, "cpu": 0}
	saque = "tu"
	capa.visible = true
	_actualizar_marcador()
	_avisar("¡PARTIDO DE PÁDEL!\nTú contra Víctor · a %d juegos" % JUEGOS_GANAR, 2.5)
	pausa = 2.5
	_preparar_saque()


func terminar(gana_tu: bool, abandono := false) -> void:
	jugando = false
	game.explorando = false
	_congelar(false)
	var pl = game.player
	pl.gun_holder.visible = antes.get("gun", true)
	if pl.katana_pivot:
		pl.katana_pivot.visible = antes.get("kat", false)
	pl.cooldown = 0.3
	pala.visible = false
	cpu.visible = false
	bola.visible = false
	sombra.visible = false
	bola_viva = false
	capa.visible = false
	if abandono:
		game._toast("Has abandonado el partido")
	elif gana_tu:
		game.points += 2000
		var libres: Array = []
		for id in BebidasScript.DATOS.keys():
			if not pl.has_perk(id):
				libres.append(id)
		var txt := "¡HAS GANADO A VÍCTOR AL PÁDEL! +2000 puntos"
		if libres.size() > 0 and pl.perks.size() < BebidasScript.MAX_BEBIDAS:
			var id2: String = libres.pick_random()
			pl.give_perk(id2)
			txt += "\nY te invita a un %s" % BebidasScript.DATOS[id2]["nombre"]
		game._toast(txt)
		snd_publico.play()
	else:
		game._toast("Víctor te ha ganado al pádel... y se ríe de ti")


# Enemigos y Xavier quietos mientras se juega
func _congelar(si: bool) -> void:
	var modo := Node.PROCESS_MODE_DISABLED if si else Node.PROCESS_MODE_INHERIT
	for z: Node in get_tree().get_nodes_in_group("zombies"):
		z.process_mode = modo
	if game.xavier != null:
		game.xavier.process_mode = modo


# ---------------- Bucle ----------------
func _process(delta: float) -> void:
	if not jugando:
		return
	var pl = game.player
	if Input.is_key_pressed(KEY_BACKSPACE):
		terminar(false, true)
		return
	# no puede disparar ni salir de su campo
	pl.cooldown = 1.0
	var p: Vector3 = pl.global_position
	p.x = clampf(p.x, c.x - HW + 0.35, c.x + HW - 0.35)
	p.z = clampf(p.z, c.z - HL + 0.35, c.z - 0.45)
	pl.global_position = p
	_pala_jugador(delta)
	_cpu_update(delta)
	if pausa > 0.0:
		pausa -= delta
		return
	if esperando_saque and saque == "cpu":
		cpu_saque_t -= delta
		if cpu_saque_t <= 0.0:
			_cpu_golpea(true)
	if bola_viva or esperando_saque:
		_fisica(delta)


# ---------------- Bola ----------------
func _fisica(delta: float) -> void:
	t_golpe += delta
	var pasos := 3
	var dt := delta / pasos
	for i in pasos:
		var antes_z := bpos.z
		bvel.y -= GRAV * dt
		bpos += bvel * dt
		# red
		if signf(antes_z - c.z) != signf(bpos.z - c.z) and bpos.y < RED_ALTO and absf(bpos.x - c.x) < HW:
			bpos.z = antes_z
			bvel.z *= -0.25
			bvel.x *= 0.5
			snd_red.global_position = bpos
			snd_red.play()
		# suelo
		if bpos.y < BOLA_R:
			bpos.y = BOLA_R
			if bvel.y < 0.0:
				bvel.y = -bvel.y * 0.72
				bvel.x *= 0.88
				bvel.z *= 0.88
				if absf(bvel.y) > 0.6:
					snd_bote.global_position = bpos
					snd_bote.play()
				_bote()
				if not bola_viva and not esperando_saque:
					return
		# cristales (fondos de 4 m, laterales de 3-4 m)
		var lx := bpos.x - c.x
		var lz := bpos.z - c.z
		if absf(lz) > HL - BOLA_R:
			if bpos.y < 4.0:
				bpos.z = c.z + signf(lz) * (HL - BOLA_R)
				bvel.z = -bvel.z * 0.65
				_pared()
			else:
				_fuera()
		if absf(lx) > HW - BOLA_R:
			if bpos.y < 3.5:
				bpos.x = c.x + signf(lx) * (HW - BOLA_R)
				bvel.x = -bvel.x * 0.65
				_pared()
			else:
				_fuera()
		if not bola_viva and not esperando_saque:
			return
	bola.global_position = bpos
	sombra.global_position = Vector3(bpos.x, 0.02, bpos.z)
	var s := clampf(1.0 - bpos.y / 6.0, 0.3, 1.0)
	sombra.scale = Vector3(s, 1.0, s)
	if bola_viva and t_golpe > 9.0:          # se ha quedado muerta en algún sitio
		_punto(ultimo if botes > 0 else _otro(ultimo), "")


func _lado(z: float) -> String:
	return "tu" if z < c.z else "cpu"


func _otro(q: String) -> String:
	return "cpu" if q == "tu" else "tu"


func _bote() -> void:
	if esperando_saque:
		if saque == "tu":            # la bola del saque se te ha caído: otra vez
			botes += 1
			if botes >= 3:
				_preparar_saque()
		return
	if not bola_viva:
		return
	var lado := _lado(bpos.z)
	if lado == ultimo:
		_punto(_otro(ultimo), "No ha pasado la red")
		return
	botes += 1
	if botes >= 2:
		_punto(ultimo, "Dos botes")
	elif botes == 1 and lado == "cpu":
		cpu_obj = _prediccion()


func _pared() -> void:
	if not bola_viva:
		return
	var lado := _lado(bpos.z)
	if botes == 0 and lado != ultimo:
		_punto(lado, "Ha dado en el cristal antes de botar")
	elif lado == "cpu" and botes >= 1:
		cpu_obj = _prediccion()


func _fuera() -> void:
	if not bola_viva:
		return
	if botes == 0:
		_punto(_otro(ultimo), "Fuera")
	else:
		_punto(ultimo, "La bola ha salido de la pista")


# Lanza la bola: desde "desde" para que bote en "hasta" pasando por encima de la red
func _tirar(desde: Vector3, hasta: Vector3, velocidad: float) -> void:
	var d := Vector2(hasta.x - desde.x, hasta.z - desde.z).length()
	var t := clampf(d / velocidad, 0.45, 2.2)
	for k in 6:            # que pase la red con margen
		var v := _vel_para(desde, hasta, t)
		var tn := (c.z - desde.z) / v.z if absf(v.z) > 0.01 else -1.0
		if tn > 0.0 and tn < t:
			var y := desde.y + v.y * tn - 0.5 * GRAV * tn * tn
			if y < RED_ALTO + 0.25:
				t *= 1.15
				continue
		break
	bpos = desde
	bvel = _vel_para(desde, hasta, t)
	t_golpe = 0.0
	botes = 0


func _vel_para(desde: Vector3, hasta: Vector3, t: float) -> Vector3:
	var v := (hasta - desde) / t
	v.y = (hasta.y - desde.y + 0.5 * GRAV * t * t) / t
	return v


func _preparar_saque() -> void:
	bola_viva = false
	esperando_saque = true
	botes = 0
	bola.visible = true
	sombra.visible = true
	if saque == "tu":
		var pl = game.player
		var f: Vector3 = -pl.global_transform.basis.z
		f.y = 0.0
		bpos = pl.global_position + f.normalized() * 0.7 + Vector3(0.25, 1.1, 0.0)
		bvel = Vector3(0.0, 3.0, 0.0)
		_avisar("Tu saque: lanza la bola y dale con el clic", 1.8)
	else:
		bpos = cpu.global_position + Vector3(0.3, 1.2, -0.5)
		bvel = Vector3.ZERO
		cpu_saque_t = 1.2
		_avisar("Saca Víctor", 1.2)
	bola.global_position = bpos


# ---------------- Tu pala ----------------
func _pala_jugador(delta: float) -> void:
	var pl = game.player
	var lmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var just := lmb and not lmb_prev
	lmb_prev = lmb
	if swing > 0.0:
		swing -= delta
	var k := sin(clampf(1.0 - swing / 0.25, 0.0, 1.0) * PI) if swing > 0.0 else 0.0
	pala.rotation = Vector3(-0.3 - k * 1.2, 0.5 - k * 1.4, -0.3)
	if not just or swing > 0.0 or pausa > 0.0:
		return
	swing = 0.25
	var f: Vector3 = -pl.global_transform.basis.z
	f.y = 0.0
	f = f.normalized()
	var punto: Vector3 = pl.global_position + Vector3(0, 1.0, 0) + f * 0.6
	var cerca := bpos.distance_to(punto) < 1.6
	var mio := _lado(bpos.z) == "tu"
	if esperando_saque and saque == "tu" and cerca:
		_golpe_jugador(true)
	elif bola_viva and cerca and mio and ultimo == "cpu":
		_golpe_jugador(false)


func _golpe_jugador(es_saque: bool) -> void:
	var pl = game.player
	var look: Vector3 = -pl.cam.global_transform.basis.z
	var fondo := clampf(remap(look.y, -0.35, 0.35, 2.5, 9.0), 2.5, 9.0)     # mirar arriba = más al fondo
	var hor := Vector2(look.x, look.z)
	if hor.length() < 0.1 or hor.y < 0.05:
		hor = Vector2(0, 1)
	hor = hor.normalized()
	var dz := (c.z + fondo) - bpos.z
	var x := bpos.x + hor.x / hor.y * dz
	x = clampf(x, c.x - HW + 0.5, c.x + HW - 0.5)
	var remate := bpos.y > 1.9 and not es_saque
	var hasta := Vector3(x, 0.0, c.z + fondo)
	_tirar(bpos, hasta, 21.0 if remate else (12.0 if es_saque else 15.0))
	ultimo = "tu"
	bola_viva = true
	esperando_saque = false
	snd_pala.global_position = bpos
	snd_pala.pitch_scale = 1.25 if remate else randf_range(0.95, 1.05)
	snd_pala.play()
	if remate:
		_avisar("¡REMATE!", 0.6)
	cpu_obj = _prediccion()


# ---------------- Víctor ----------------
# Dónde va a estar la bola a buena altura en su campo (simulando el vuelo)
func _prediccion() -> Vector3:
	var p := bpos
	var v := bvel
	var b := botes
	var dt := 1.0 / 60.0
	for i in 240:
		v.y -= GRAV * dt
		p += v * dt
		if p.y < BOLA_R and v.y < 0.0:
			v.y = -v.y * 0.72
			v.x *= 0.88
			v.z *= 0.88
			p.y = BOLA_R
			if p.z > c.z:
				b += 1
		if absf(p.z - c.z) > HL - BOLA_R:
			v.z = -v.z * 0.65
			p.z = c.z + signf(p.z - c.z) * (HL - BOLA_R)
		if absf(p.x - c.x) > HW - BOLA_R:
			v.x = -v.x * 0.65
			p.x = c.x + signf(p.x - c.x) * (HW - BOLA_R)
		if p.z > c.z + 0.6 and b >= 1 and p.y > 0.5 and p.y < 1.4 and v.y < 0.0:
			return Vector3(p.x, 0.0, p.z)
	return Vector3(clampf(p.x, c.x - HW + 0.5, c.x + HW - 0.5), 0.0, clampf(p.z, c.z + 1.0, c.z + HL - 0.5))


func _cpu_update(delta: float) -> void:
	var objetivo := cpu_obj
	if not bola_viva or ultimo == "cpu":
		objetivo = c + Vector3(clampf(bpos.x - c.x, -2.0, 2.0) * 0.4, 0.0, 6.5)     # vuelve a su sitio
	if esperando_saque and saque == "cpu":
		objetivo = c + Vector3(1.5, 0.0, 8.5)
	# se pone un poco detrás de la bola, con la pala a su derecha
	objetivo += Vector3(-0.35, 0.0, 0.35)
	var pos := cpu.global_position
	var d := Vector3(objetivo.x - pos.x, 0.0, objetivo.z - pos.z)
	var paso := minf(d.length(), VEL_CPU * delta)
	var mov := d.normalized() * paso if d.length() > 0.01 else Vector3.ZERO
	pos += mov
	pos.x = clampf(pos.x, c.x - HW + 0.4, c.x + HW - 0.4)
	pos.z = clampf(pos.z, c.z + 0.6, c.z + HL - 0.4)
	cpu.global_position = pos
	# mira hacia la bola
	var to := bpos - pos
	cpu.rotation.y = lerp_angle(cpu.rotation.y, atan2(-to.x, -to.z), 8.0 * delta)
	var run_k := clampf(mov.length() / maxf(delta, 0.001) / 4.0, 0.0, 1.0)
	cpu_ph += 14.0 * delta
	Ch.run_pose(cpu_rig, cpu_ph, run_k * 0.6)
	if cpu_swing > 0.0:
		cpu_swing -= delta
		var k := sin(clampf(1.0 - cpu_swing / 0.3, 0.0, 1.0) * PI)
		cpu_rig["arms"][1].rotation = Vector3(-1.6 * k, 0.0, 0.6 * k)
	# golpea si la tiene a mano
	if bola_viva and ultimo == "tu" and _lado(bpos.z) == "cpu" and pausa <= 0.0:
		var mano := pos + Vector3(0, 1.1, 0)
		var puede := botes >= 1 or bpos.z > c.z + 1.5        # también volea
		if puede and bpos.distance_to(mano) < 1.5 and bpos.y < 2.6:
			_cpu_golpea(false)


func _cpu_golpea(es_saque: bool) -> void:
	esperando_saque = false
	if es_saque:
		bpos = cpu.global_position + Vector3(0.3, 1.0, -0.4)
	# Víctor falla de vez en cuando (más cuanto más fuerte le llega la bola)
	var fallo := randf() < 0.1 + clampf(bvel.length() / 120.0, 0.0, 0.15)
	var hasta := Vector3(c.x + randf_range(-HW + 0.8, HW - 0.8), 0.0, c.z - randf_range(3.0, 8.5))
	if fallo and not es_saque:
		if randf() < 0.5:
			hasta = Vector3(hasta.x, 0.0, c.z + 0.3)          # a la red
		else:
			hasta.z = c.z - HL - 2.0                        # al cristal sin botar
	_tirar(bpos, hasta, 11.5 if es_saque else randf_range(12.0, 16.0))
	if fallo and hasta.z > c.z:
		bvel.y *= 0.55
	ultimo = "cpu"
	bola_viva = true
	cpu_swing = 0.3
	snd_pala.global_position = bpos
	snd_pala.pitch_scale = randf_range(0.9, 1.0)
	snd_pala.play()


# ---------------- Puntos ----------------
func _punto(quien: String, por: String) -> void:
	if not bola_viva:
		return
	bola_viva = false
	esperando_saque = false
	var otro := _otro(quien)
	if pt[quien] == 3 and pt[otro] == 3:          # punto de oro
		_juego(quien, por)
		return
	pt[quien] += 1
	if pt[quien] >= 4:
		_juego(quien, por)
		return
	snd_punto.pitch_scale = 1.2 if quien == "tu" else 0.8
	snd_punto.play()
	_actualizar_marcador()
	var txt := "Punto para ti" if quien == "tu" else "Punto para Víctor"
	if pt["tu"] == 3 and pt["cpu"] == 3:
		txt += "\n¡40-40! PUNTO DE ORO"
	_avisar(txt + ("\n" + por if por != "" else ""), 1.6)
	pausa = 1.6
	_preparar_saque()


func _juego(quien: String, por: String) -> void:
	juegos[quien] += 1
	pt = {"tu": 0, "cpu": 0}
	_actualizar_marcador()
	if juegos[quien] >= JUEGOS_GANAR:
		_avisar("¡JUEGO, SET Y PARTIDO!\n" + ("Has ganado tú" if quien == "tu" else "Gana Víctor"), 2.5)
		bola.visible = false
		sombra.visible = false
		var tw := create_tween()
		tw.tween_interval(2.5)
		tw.tween_callback(terminar.bind(quien == "tu"))
		pausa = 99.0
		return
	snd_publico.play()
	saque = _otro(saque)
	_avisar(("Juego para ti" if quien == "tu" else "Juego para Víctor") + ("\n" + por if por != "" else ""), 2.0)
	pausa = 2.0
	_preparar_saque()


func _actualizar_marcador() -> void:
	var a: String = PUNTOS[mini(pt["tu"], 3)]
	var b: String = PUNTOS[mini(pt["cpu"], 3)]
	marcador.text = "TÚ   %s  ·  %s   VÍCTOR\nJuegos  %d - %d" % [a, b, juegos["tu"], juegos["cpu"]]


func _avisar(texto: String, dur: float) -> void:
	aviso.text = texto
	aviso.modulate.a = 1.0
	var tw := aviso.create_tween()
	tw.tween_interval(dur)
	tw.tween_property(aviso, "modulate:a", 0.0, 0.4)


# ---------------- Construcción ----------------
# Poste con el marcador junto a la puerta oeste de la pista: aquí se pulsa E
func _build_poste() -> void:
	var p := c + Vector3(-4.4, 0.0, -2.2)
	U.cylinder(self, 0.05, 1.8, p + Vector3(0, 0.9, 0), Color(0.2, 0.22, 0.25))
	var pan := U.box(self, Vector3(0.9, 0.55, 0.06), p + Vector3(0, 1.95, 0), Color(0.05, 0.25, 0.55))
	pan.rotation_degrees.y = 90.0
	var t := Label3D.new()
	t.text = "PÁDEL\n[E] JUGAR"
	t.font_size = 48
	t.pixel_size = 0.004
	t.outline_size = 8
	t.modulate = Color(1.0, 0.95, 0.4)
	t.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	t.position = p + Vector3(0, 2.6, 0)
	add_child(t)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.9, 0.5)
	l.light_energy = 0.8
	l.omni_range = 3.0
	l.position = p + Vector3(0, 2.2, 0)
	add_child(l)


func _build_bola() -> void:
	bola = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = BOLA_R
	sm.height = BOLA_R * 2.0
	bola.mesh = sm
	bola.material_override = U.mat(Color(0.85, 1.0, 0.15), true)
	bola.material_override.emission_energy_multiplier = 0.6
	bola.visible = false
	add_child(bola)
	sombra = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.09
	cm.bottom_radius = 0.09
	cm.height = 0.005
	sombra.mesh = cm
	var m := U.mat(Color(0, 0, 0, 0.5))
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sombra.material_override = m
	sombra.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sombra.visible = false
	add_child(sombra)
	# tu pala, delante de la cámara
	pala = _pala()
	pala.position = Vector3(0.38, -0.38, -0.75)
	pala.visible = false
	game.player.cam.add_child(pala)


func _pala() -> Node3D:
	var n := Node3D.new()
	var cara := U.cylinder(n, 0.2, 0.035, Vector3(0, 0.2, 0), Color(0.08, 0.08, 0.1))
	cara.rotation_degrees.x = 90.0
	var borde := U.cylinder(n, 0.205, 0.03, Vector3(0, 0.2, 0), Color(0.95, 0.4, 0.1))
	borde.rotation_degrees.x = 90.0
	for k in 3:
		var f := U.box(n, Vector3(0.3, 0.012, 0.038), Vector3(0, 0.12 + k * 0.08, 0), Color(0.3, 0.3, 0.32))
		f.rotation_degrees.z = 20.0
	U.box(n, Vector3(0.035, 0.2, 0.03), Vector3(0, -0.07, 0), Color(0.06, 0.06, 0.06))
	return n


func _build_cpu() -> void:
	cpu = Node3D.new()
	add_child(cpu)
	var parts: Dictionary = Ch.build_victor(cpu)
	cpu_model = parts["model"]
	cpu_rig = parts["rig"]
	var p := _pala()
	p.position = Vector3(0.29, 0.62, -0.12)
	p.rotation_degrees = Vector3(-20.0, 0.0, 0.0)
	cpu_rig["hand"].add_child(p)
	var tag := Label3D.new()
	tag.text = "VÍCTOR"
	tag.font_size = 32
	tag.pixel_size = 0.004
	tag.outline_size = 8
	tag.modulate = Color(1.0, 0.8, 0.25)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position.y = 2.7
	cpu.add_child(tag)
	cpu.visible = false


func _build_ui() -> void:
	capa = CanvasLayer.new()
	capa.layer = 7
	capa.visible = false
	add_child(capa)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", HudScript.panel_style(0.7))
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.offset_top = 14.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	capa.add_child(panel)
	marcador = Label.new()
	marcador.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	marcador.add_theme_font_size_override("font_size", 26)
	marcador.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
	panel.add_child(marcador)
	aviso = Label.new()
	aviso.set_anchors_preset(Control.PRESET_CENTER)
	aviso.offset_left = -500.0
	aviso.offset_right = 500.0
	aviso.offset_top = -170.0
	aviso.offset_bottom = -60.0
	aviso.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	aviso.add_theme_font_size_override("font_size", 34)
	aviso.add_theme_color_override("font_color", Color(1, 1, 1))
	aviso.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	aviso.add_theme_constant_override("outline_size", 8)
	aviso.mouse_filter = Control.MOUSE_FILTER_IGNORE
	capa.add_child(aviso)
	ayuda = Label.new()
	ayuda.text = "WASD moverte · Shift correr · Clic darle a la bola (mira arriba = más al fondo) · Retroceso abandonar"
	ayuda.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	ayuda.offset_top = -40.0
	ayuda.offset_left = -500.0
	ayuda.offset_right = 500.0
	ayuda.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ayuda.add_theme_font_size_override("font_size", 16)
	ayuda.add_theme_color_override("font_color", Color(0.85, 0.85, 0.8))
	ayuda.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	ayuda.add_theme_constant_override("outline_size", 5)
	capa.add_child(ayuda)


func _build_sonidos() -> void:
	snd_pala = AudioStreamPlayer3D.new()
	snd_pala.stream = _pock(0.06, 1400.0)
	snd_pala.unit_size = 8.0
	add_child(snd_pala)
	snd_bote = AudioStreamPlayer3D.new()
	snd_bote.stream = _pock(0.04, 600.0)
	snd_bote.unit_size = 6.0
	add_child(snd_bote)
	snd_red = AudioStreamPlayer3D.new()
	snd_red.stream = _pock(0.12, 250.0)
	snd_red.unit_size = 6.0
	add_child(snd_red)
	snd_punto = AudioStreamPlayer.new()
	snd_punto.stream = U.make_ting()
	snd_punto.volume_db = -8.0
	add_child(snd_punto)
	snd_publico = AudioStreamPlayer.new()
	snd_publico.stream = U.make_crowd()
	snd_publico.volume_db = -6.0
	add_child(snd_publico)


# "¡Pock!" de la bola: un golpe seco con algo de tono
func _pock(dur: float, f: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var tt := float(i) / rate
		var s := (sin(TAU * f * tt) * 0.7 + (randf() * 2.0 - 1.0) * 0.4) * exp(-tt * 60.0)
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 30000.0))
	return U._wav(data, rate)

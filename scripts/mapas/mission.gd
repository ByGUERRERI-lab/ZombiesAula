extends Node3D
# MISIÓN: ESCAPA DE CESUR
#  1. Encuentra las 3 piezas de la bomba (detonador, cables y C4).
#  2. Monta la bomba en la mesa del profesor (mantén E mientras te atacan).
#  3. Cuenta atrás: corre a la salida del fondo del pasillo y fuerza la puerta.
#  4. Escapas y... ¡BOOM! (o explota contigo dentro si no llegas).
#  5. ...pero la calle es un decorado: CESUR es un backroom y no tiene salida.
#     Te despiertas en otro sitio (Mojácar, el Pueblo Indalo...) y vuelta a empezar.

const U = preload("res://scripts/nucleo/util.gd")
const HudScript = preload("res://scripts/interfaz/hud.gd")
const MapasScript = preload("res://scripts/mapas/mapas.gd")

const PLANT_TIME := 5.0       # segundos manteniendo E para montar la bomba
const FORCE_TIME := 3.0       # segundos manteniendo E para forzar la salida
const BOMB_TIME := 75.0       # segundos para escapar
const DESK_POS := Vector3(2.8, 0.0, -6.0)
const PLANT_POS := Vector3(2.8, 0.0, -4.9)
const EXIT_POS := Vector3(0.0, 0.0, 97.2)
# [id, nombre, pista, posición]
const PIECES := [
	["detonador", "Detonador", "en un váter del aseo izquierdo", Vector3(-9.0, 0.55, 15.9)],
	["cables", "Cables", "entre las máquinas del pasillo largo", Vector3(22.7, 0.3, 52.8)],
	["c4", "Explosivo C4", "en la conserjería del vestíbulo", Vector3(-8.5, 1.1, 89.0)],
]

var game
var player
var stage := 0              # 0 piezas, 1 montar, 2 cuenta atrás, 3 escapado, 4 explotó dentro
var got := {}
var piece_nodes := {}
var markers := {}
var e_prev := false
var hold := 0.0
var timer := BOMB_TIME
var beep_t := 0.0
var spawn_t := 0.0
var elapsed := 0.0
var shake := 0.0
var t := 0.0
var death_reason := ""

var bomb: Node3D
var bomb_lbl: Label3D
var bomb_led: MeshInstance3D
var exit_door: Node3D
var cine_cam: Camera3D
var backroom: Node3D
var snd_hum: AudioStreamPlayer
var twist_lbl: Label

# interfaz
var layer: CanvasLayer
var obj_lbl: Label
var timer_lbl: Label
var brief: Label
var prompt: Label
var bar: ProgressBar
var red_rect: ColorRect
var flash: ColorRect
var snd_beep: AudioStreamPlayer
var snd_boom: AudioStreamPlayer
var snd_pick: AudioStreamPlayer


func _ready() -> void:
	_build_ui()
	_build_sounds()
	_build_desk()
	_build_exit_door()
	for p in PIECES:
		var n := _piece_model(p[0])
		n.position = p[3]
		add_child(n)
		piece_nodes[p[0]] = n
		got[p[0]] = false
		markers[p[0]] = _marker(p[3] + Vector3(0, 0.8, 0), Color(1.0, 0.85, 0.2), str(p[1]).to_upper())
	markers["plant"] = _marker(DESK_POS + Vector3(0, 1.8, 0), Color(1.0, 0.3, 0.2), "MONTAR LA BOMBA")
	markers["exit"] = _marker(EXIT_POS + Vector3(0, 2.6, 0), Color(0.3, 1.0, 0.4), "SALIDA")
	markers["plant"].visible = false
	markers["exit"].visible = false
	brief.text = "MISIÓN: ESCAPA DE CESUR\nEncuentra las 3 piezas de la bomba, móntala en la mesa del profe\ny sal por la puerta de emergencia antes de que explote."
	if Net.bucle > 0:
		brief.text = "...otra vez en el aula. Bucle %d.\nLas mismas mesas, la misma pizarra. Esta vez tiene que salir bien:\nmonta la bomba y sal por la puerta de emergencia." % (Net.bucle + 1)
	var tw := create_tween()
	tw.tween_interval(7.0)
	tw.tween_property(brief, "modulate:a", 0.0, 1.0)


# =============================================================
# Bucle
# =============================================================
func _process(delta: float) -> void:
	t += delta
	_update_shake(delta)
	if game.explorando:
		return
	if stage == 3:
		return
	if stage == 4 or player.dead:
		prompt.text = ""
		bar.visible = false
		return
	elapsed += delta

	# piezas flotando y girando
	for id in piece_nodes:
		var n: Node3D = piece_nodes[id]
		if n.visible:
			n.rotation.y += 1.8 * delta
			n.position.y = PIECES[_idx(id)][3].y + sin(t * 2.5) * 0.08

	var e_now: bool = Input.is_key_pressed(KEY_E) and not player.downed and not player.input_blocked
	var e_down: bool = e_now and not e_prev
	e_prev = e_now
	prompt.text = ""
	bar.visible = false

	match stage:
		0:
			for p in PIECES:
				if not got[p[0]] and _dist(p[3]) < 1.8:
					prompt.text = "[E] Coger %s" % p[1]
					if e_down:
						_send("pick", p[0])
		1:
			if _dist(PLANT_POS) < 1.8:
				prompt.text = "Mantén [E] para montar la bomba"
				if e_now:
					hold += delta
				bar.visible = true
				bar.value = hold / PLANT_TIME * 100.0
				if hold >= PLANT_TIME:
					hold = 0.0
					_send("arm")
			if _dist(PLANT_POS) < 8.0:
				_horde(delta, 2.5)
		2:
			timer -= delta
			_bomb_effects(delta)
			if _dist(EXIT_POS) < 2.0:
				prompt.text = "Mantén [E] para forzar la puerta de emergencia"
				if e_now:
					hold += delta
				bar.visible = true
				bar.value = hold / FORCE_TIME * 100.0
				if hold >= FORCE_TIME:
					hold = 0.0
					_send("escape")
					return
			_horde(delta, 1.6)
			if timer <= 0.0 and Net.is_host():
				_send("fail")
				return
	_update_objectives()


func _idx(id: String) -> int:
	for i in PIECES.size():
		if PIECES[i][0] == id:
			return i
	return 0


func _dist(p: Vector3) -> float:
	var pp: Vector3 = player.global_position
	return Vector2(pp.x - p.x, pp.z - p.z).length()


# Más enemigos mientras montas la bomba o huyes
func _horde(delta: float, every: float) -> void:
	spawn_t -= delta
	if spawn_t <= 0.0:
		spawn_t = every
		if get_tree().get_nodes_in_group("zombies").size() < 16:
			game._spawn_enemy()


# =============================================================
# Pasos de la misión
# =============================================================
func _pick(p: Array) -> void:
	got[p[0]] = true
	snd_pick.play()
	var n: Node3D = piece_nodes[p[0]]
	var tw := n.create_tween()
	tw.tween_property(n, "scale", Vector3.ONE * 1.6, 0.12)
	tw.tween_property(n, "scale", Vector3.ZERO, 0.2)
	tw.tween_callback(n.hide)
	markers[p[0]].visible = false
	var left := 0
	for k in got:
		if not got[k]:
			left += 1
	if p[0] == "c4":
		# ¡Alarma! emboscada al coger el explosivo
		_say("¡ALARMA! ¡Te han pillado con el C4!\n¡Viene El Repartidor!", Color(1.0, 0.3, 0.2))
		game._spawn_boss()
		for i in 4:
			game._spawn_enemy()
		for l in game.hall_lights:
			l.light_color = Color(1.0, 0.25, 0.2)
	else:
		_say("¡%s conseguido! Faltan %d" % [p[1], left] if left > 0 else "¡%s conseguido!" % p[1], Color(1.0, 0.9, 0.4))
	if left == 0:
		stage = 1
		hold = 0.0
		markers["plant"].visible = true
		get_tree().create_timer(2.2).timeout.connect(_all_pieces_msg)


func _all_pieces_msg() -> void:
	if stage == 1:
		_say("¡Tienes todas las piezas!\nVuelve al aula y monta la bomba en la mesa del profe", Color(1.0, 0.6, 0.2))


func _arm_bomb() -> void:
	stage = 2
	hold = 0.0
	timer = BOMB_TIME
	markers["plant"].visible = false
	markers["exit"].visible = true
	bomb.visible = true
	bomb.scale = Vector3.ZERO
	bomb.create_tween().tween_property(bomb, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK)
	timer_lbl.visible = true
	_say("¡BOMBA ACTIVADA!\n¡Corre a la SALIDA del fondo del pasillo!", Color(1.0, 0.2, 0.15))
	for l in game.hall_lights:
		l.light_color = Color(1.0, 0.2, 0.15)


func _bomb_effects(delta: float) -> void:
	var secs := maxi(int(ceil(timer)), 0)
	var txt := "%02d:%02d" % [secs / 60, secs % 60]
	timer_lbl.text = "BOMBA  " + txt
	bomb_lbl.text = txt
	var urgent := timer < 15.0
	var pulse := 1.0 + (0.15 if urgent else 0.05) * absf(sin(t * (10.0 if urgent else 4.0)))
	timer_lbl.scale = Vector2.ONE * pulse
	red_rect.color.a = (0.18 if urgent else 0.07) * absf(sin(t * 3.0))
	beep_t -= delta
	if beep_t <= 0.0:
		beep_t = clampf(timer / BOMB_TIME * 1.2, 0.12, 1.2)
		snd_beep.play()
		bomb_led.visible = not bomb_led.visible


func _update_objectives() -> void:
	var s := "ESCAPA DE CESUR\n"
	match stage:
		0:
			for p in PIECES:
				if got[p[0]]:
					s += "✔  %s\n" % p[1]
				else:
					s += "○  %s · %d m\n     %s\n" % [p[1], int(_dist(p[3])), p[2]]
		1:
			s += "✔  Piezas de la bomba\n○  Monta la bomba en la mesa del profe · %d m" % int(_dist(PLANT_POS))
		2:
			s += "✔  Piezas de la bomba\n✔  Bomba montada\n○  ¡Escapa por la emergencia! · %d m" % int(_dist(EXIT_POS))
	s = s.strip_edges()
	obj_lbl.text = s
	for k in markers:
		var m: Label3D = markers[k]
		if m.visible:
			m.text = "%s\n%d m" % [m.get_meta("title"), int(_dist(m.position))]


# =============================================================
# Final: escapas y la bomba explota
# =============================================================
func _escape() -> void:
	stage = 3
	prompt.text = ""
	bar.visible = false
	timer_lbl.visible = false
	obj_lbl.get_parent().visible = false
	red_rect.color.a = 0.0
	for m in markers.values():
		m.visible = false
	player.frozen = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.hud.visible = false
	game.spawn_left = 0
	for z in get_tree().get_nodes_in_group("zombies"):
		z.queue_free()
	# fundido a negro y plano desde fuera del instituto
	var tw := create_tween()
	tw.tween_property(flash, "color", Color(0, 0, 0, 1), 0.35)
	tw.tween_callback(_setup_outside)
	tw.tween_property(flash, "color:a", 0.0, 0.5)
	tw.tween_interval(1.6)
	tw.tween_callback(_big_boom)
	tw.tween_interval(3.2)
	tw.tween_callback(_twist)


func _setup_outside() -> void:
	exit_door.position.x = 1.4        # puerta abierta
	game.world_env.fog_density = 0.006     # fuera se ve la calle entera
	var foco := OmniLight3D.new()           # alumbra la fachada desde la calle
	foco.position = Vector3(0.0, 7.0, 110.0)
	foco.light_color = Color(1.0, 0.9, 0.75)
	foco.light_energy = 12.0
	foco.omni_range = 26.0
	add_child(foco)
	# fachada del instituto vista desde la calle
	var fac := Node3D.new()
	fac.name = "Fachada"
	add_child(fac)
	U.box(fac, Vector3(40.0, 0.1, 50.0), Vector3(0, -0.05, 124.0), Color(0.16, 0.16, 0.18))         # calle
	for i in 12:
		U.box(fac, Vector3(0.25, 0.02, 1.6), Vector3(-6.0, 0.01, 102.0 + i * 3.2), Color(0.9, 0.9, 0.85))
	U.box(fac, Vector3(30.0, 9.0, 0.6), Vector3(0, 4.5, 98.75), Color(0.62, 0.3, 0.22))               # ladrillo
	U.box(fac, Vector3(30.2, 0.4, 0.8), Vector3(0, 9.0, 98.75), Color(0.85, 0.85, 0.8))
	U.box(fac, Vector3(2.8, 2.7, 0.66), Vector3(0, 1.35, 98.75), Color(0.02, 0.02, 0.02))              # hueco puerta
	for wx in [-11.0, -7.0, -3.5, 3.5, 7.0, 11.0]:
		for wy in [2.0, 6.0]:
			U.box(fac, Vector3(2.0, 1.6, 0.62), Vector3(wx, wy, 98.75), Color(1.0, 0.85, 0.45), true)
	var sign_l := Label3D.new()
	sign_l.text = "CESUR"
	sign_l.font_size = 260
	sign_l.pixel_size = 0.006
	sign_l.modulate = Color(0.1, 0.25, 0.85)
	sign_l.outline_size = 24
	sign_l.position = Vector3(0, 7.3, 99.1)
	fac.add_child(sign_l)
	for lx in [-8.0, 8.0]:                                                                             # farolas
		U.box(fac, Vector3(0.12, 4.0, 0.12), Vector3(lx, 2.0, 106.0), Color(0.2, 0.2, 0.22))
		U.sphere(fac, 0.25, Vector3(lx, 4.1, 106.0), Color(1.0, 0.9, 0.6), true)
		var ll := OmniLight3D.new()
		ll.light_color = Color(1.0, 0.85, 0.6)
		ll.light_energy = 1.5
		ll.omni_range = 9.0
		ll.position = Vector3(lx, 3.9, 106.0)
		fac.add_child(ll)
	# el jugador sale corriendo y se queda mirando a cámara
	# cada jugador sale por su lado para no quedar unos encima de otros
	var ids: Array = game.players.keys()
	ids.sort()
	var side := (ids.find(Net.my_id()) - (ids.size() - 1) * 0.5) * 1.3
	player.global_position = Vector3(side, 0.05, 101.0)
	player.rotation.y = PI
	player.model.visible = true
	var run: Tween = player.create_tween()
	run.tween_property(player, "position:z", 106.0, 1.2)
	cine_cam = Camera3D.new()
	cine_cam.fov = 60.0
	add_child(cine_cam)
	cine_cam.global_position = Vector3(5.5, 2.4, 116.0)
	cine_cam.look_at(Vector3(0, 3.2, 99.0), Vector3.UP)
	cine_cam.current = true


func _big_boom() -> void:
	snd_boom.play()
	shake = 1.8
	var fl := create_tween()
	fl.tween_property(flash, "color", Color(1, 0.95, 0.8, 0.9), 0.06)
	fl.tween_property(flash, "color:a", 0.0, 0.8)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.15)
	light.light_energy = 16.0
	light.omni_range = 40.0
	light.position = Vector3(0, 5.0, 97.0)
	add_child(light)
	light.create_tween().tween_property(light, "light_energy", 2.0, 3.0)
	for i in 22:
		var p := Vector3(randf_range(-13.0, 13.0), randf_range(1.0, 9.0), randf_range(95.0, 99.5))
		_fireball(p, randf_range(1.5, 3.8), randf() * 0.6)
	for i in 30:
		_debris(Vector3(randf_range(-10.0, 10.0), randf_range(2.0, 8.0), 99.2))
	# el jugador da saltos de alegría
	var hop: Tween = player.model.create_tween().set_loops(6)
	hop.tween_property(player.model, "position:y", 0.5, 0.18).set_ease(Tween.EASE_OUT)
	hop.tween_property(player.model, "position:y", 0.0, 0.18).set_ease(Tween.EASE_IN)


func _fireball(p: Vector3, size: float, delay: float) -> void:
	var c := Color(1.0, randf_range(0.35, 0.8), 0.1)
	var s := U.sphere(self, 1.0, p, c, true)
	s.material_override.emission_energy_multiplier = 3.0
	s.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	s.scale = Vector3.ONE * 0.01
	var tw := s.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(s, "scale", Vector3.ONE * size, 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tw.parallel().tween_property(s, "position:y", p.y + 2.0, 1.6)
	tw.tween_property(s.material_override, "albedo_color", Color(0.15, 0.13, 0.12, 0.0), 1.2)   # humo
	tw.parallel().tween_property(s, "scale", Vector3.ONE * size * 1.5, 1.2)
	tw.tween_callback(s.queue_free)


func _debris(p: Vector3) -> void:
	var b := U.box(self, Vector3.ONE * randf_range(0.2, 0.6), p, Color(0.55, 0.28, 0.2).darkened(randf() * 0.4))
	var target := p + Vector3(randf_range(-8.0, 8.0), 0.0, randf_range(4.0, 16.0))
	target.y = 0.15
	var up := maxf(p.y, target.y) + randf_range(2.0, 5.0)
	var dur := randf_range(1.0, 1.8)
	var tw := b.create_tween().set_parallel(true)
	tw.tween_property(b, "position:x", target.x, dur)
	tw.tween_property(b, "position:z", target.z, dur)
	tw.tween_property(b, "rotation", Vector3(randf() * 12.0, randf() * 12.0, randf() * 12.0), dur)
	var ty := b.create_tween()
	ty.tween_property(b, "position:y", up, dur * 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	ty.tween_property(b, "position:y", target.y, dur * 0.6).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)


# =============================================================
# El giro: la calle es de mentira. CESUR es un backroom sin salida.
# =============================================================
func _twist() -> void:
	_won_line_brief("¡HAS ESCAPADO DE CESUR!", Color(1.0, 0.85, 0.2))
	var tw := create_tween()
	tw.tween_interval(2.6)
	tw.tween_callback(func(): brief.modulate.a = 0.0)
	# las farolas parpadean y se apagan
	for i in 6:
		tw.tween_callback(_lights_fac.bind(i % 2 == 1))
		tw.tween_interval(0.09 + randf() * 0.12)
	tw.tween_callback(_lights_fac.bind(false))
	tw.tween_interval(1.0)
	tw.tween_callback(_reveal_backroom)
	tw.tween_interval(1.4)
	var lines := ["Espera...", "Esto no es la calle.", "El cielo es un techo.", "Nunca has salido de CESUR.", "CESUR no tiene salida."]
	if Net.bucle > 0:
		lines = ["Otra vez.", "El mismo techo. El mismo zumbido.", "Da igual cuántas bombas pongas.", "CESUR no tiene salida."]
	for ln in lines:
		tw.tween_callback(_twist_line.bind(ln))
		tw.tween_interval(2.1)
	tw.tween_property(flash, "color", Color(0, 0, 0, 1), 1.6)
	tw.tween_callback(_twist_end)


func _won_line_brief(text: String, c: Color) -> void:
	brief.text = text
	brief.add_theme_color_override("font_color", c)
	brief.modulate.a = 1.0


func _lights_fac(on: bool) -> void:
	var fac := get_node_or_null("Fachada")
	if fac != null:
		for n in fac.get_children():
			if n is OmniLight3D:
				n.visible = on
	for n in get_children():
		if n is OmniLight3D:
			n.visible = on      # el resplandor de la explosión


func _reveal_backroom() -> void:
	# la "calle" está dentro de una sala amarilla gigante
	backroom = MapasScript.backroom_sala(self, Vector3(0, 0, 124.0), Vector3(40.0, 10.0, 52.0), 4)
	var fac := get_node_or_null("Fachada")
	if fac != null:
		fac.get_child(0).visible = false      # la calle era moqueta
	var env: Environment = game.world_env
	env.background_color = Color(0.25, 0.22, 0.1)
	env.fog_light_color = Color(0.75, 0.68, 0.35)
	env.fog_density = 0.012
	snd_hum = AudioStreamPlayer.new()
	snd_hum.stream = MapasScript.zumbido()
	snd_hum.volume_db = -6.0
	add_child(snd_hum)
	snd_hum.play()
	flash.color = Color(1.0, 0.95, 0.6, 0.8)
	create_tween().tween_property(flash, "color:a", 0.0, 0.6)
	# la cámara mira poco a poco hacia arriba: hay techo y fluorescentes
	var a := Vector3(0, 3.2, 99.0)
	var b := Vector3(-2.0, 10.0, 108.0)
	create_tween().tween_method(func(k: float): cine_cam.look_at(a.lerp(b, k), Vector3.UP), 0.0, 1.0, 6.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _twist_line(text: String) -> void:
	if twist_lbl == null:
		twist_lbl = Label.new()
		twist_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		twist_lbl.offset_top = 380.0
		twist_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		twist_lbl.add_theme_font_size_override("font_size", 40)
		twist_lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.75))
		twist_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		twist_lbl.add_theme_constant_override("outline_size", 10)
		twist_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(twist_lbl)
	twist_lbl.text = text
	twist_lbl.modulate.a = 0.0
	var tw := twist_lbl.create_tween()
	tw.tween_property(twist_lbl, "modulate:a", 1.0, 0.4)
	tw.tween_interval(1.2)
	tw.tween_property(twist_lbl, "modulate:a", 0.25, 0.4)


func _twist_end() -> void:
	if twist_lbl != null:
		twist_lbl.visible = false
	var secs := int(elapsed)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	layer.add_child(box)
	_won_line(box, "BUCLE %d" % (Net.bucle + 1), 64, Color(0.95, 0.85, 0.35))
	_won_line(box, "Tiempo: %d:%02d   ·   Oleada: %d   ·   Bajas: %d   ·   Puntos: %d" % [secs / 60, secs % 60, game.wave, game.kills, game.points], 24, Color(0.85, 0.85, 0.85))
	_won_line(box, " ", 16, Color.WHITE)
	_won_line(box, "Te despiertas en un sitio que no conoces...", 30, Color(1.0, 1.0, 1.0))
	box.modulate.a = 0.0
	var tw := box.create_tween()
	tw.tween_property(box, "modulate:a", 1.0, 0.8)
	tw.tween_interval(3.5)
	tw.tween_callback(_go_next)


func _go_next() -> void:
	game.save_carry()
	if Net.is_host():
		Net.go_to_map(MapasScript.siguiente(Net.mapa), Net.bucle + 1)


func _won_line(parent: Node, text: String, size: int, c: Color) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 8)
	parent.add_child(l)


# Si se acaba el tiempo estando dentro
func _explode_inside() -> void:
	stage = 4
	timer_lbl.text = "BOMBA  00:00"
	death_reason = "¡BOOM! La bomba explotó contigo dentro de CESUR"
	snd_boom.play()
	shake = 1.5
	var fl := create_tween()
	fl.tween_property(flash, "color", Color(1, 0.9, 0.7, 1.0), 0.08)
	fl.tween_property(flash, "color", Color(0.3, 0.05, 0.0, 0.0), 1.5)
	game.coop_over = true
	player._die()


# ---------------- Red: los pasos de la misión se aplican en todos los PCs ----------------
func _send(what: String, id: String = "") -> void:
	if Net.online:
		_net_step.rpc(what, id)
	else:
		_net_step(what, id)


@rpc("any_peer", "call_local", "reliable")
func _net_step(what: String, id: String) -> void:
	match what:
		"pick":
			if stage == 0 and got.has(id) and not got[id]:
				_pick(PIECES[_idx(id)])
		"arm":
			if stage == 1:
				_arm_bomb()
		"escape":
			if stage == 2:
				_escape()
		"fail":
			if stage == 2:
				_explode_inside()


func _update_shake(delta: float) -> void:
	if shake <= 0.0:
		return
	shake -= delta
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var a := clampf(shake, 0.0, 1.0) * 0.35
	cam.h_offset = randf_range(-a, a)
	cam.v_offset = randf_range(-a, a)
	if shake <= 0.0:
		cam.h_offset = 0.0
		cam.v_offset = 0.0


func _say(text: String, c: Color) -> void:
	brief.text = text
	brief.add_theme_color_override("font_color", c)
	brief.modulate.a = 1.0
	var tw := brief.create_tween()
	brief.scale = Vector2.ONE * 1.15
	tw.tween_property(brief, "scale", Vector2.ONE, 0.2)
	tw.tween_interval(3.0)
	tw.tween_property(brief, "modulate:a", 0.0, 0.8)


# =============================================================
# Construcción
# =============================================================
func _build_desk() -> void:
	# mesa del profesor, donde se monta la bomba
	U.solid_box(self, Vector3(2.0, 0.78, 0.9), DESK_POS + Vector3(0, 0.39, 0), Color(0.55, 0.36, 0.2))
	U.box(self, Vector3(2.04, 0.05, 0.94), DESK_POS + Vector3(0, 0.8, 0), Color(0.4, 0.25, 0.12))
	U.box(self, Vector3(0.5, 0.35, 0.04), DESK_POS + Vector3(-0.5, 1.0, 0.2), Color(0.08, 0.08, 0.1))   # portátil
	bomb = Node3D.new()
	bomb.position = DESK_POS + Vector3(0.3, 0.83, -0.05)
	add_child(bomb)
	var dyn := Color(0.72, 0.62, 0.42)
	for i in 4:
		var stick := U.cylinder(bomb, 0.06, 0.4, Vector3(-0.18 + i * 0.12, 0.06, 0), Color(0.8, 0.15, 0.1))
		stick.rotation_degrees.x = 90.0
	U.box(bomb, Vector3(0.56, 0.05, 0.1), Vector3(0, 0.07, -0.12), Color(0.1, 0.1, 0.1))     # cinta
	U.box(bomb, Vector3(0.56, 0.05, 0.1), Vector3(0, 0.07, 0.12), Color(0.1, 0.1, 0.1))
	U.box(bomb, Vector3(0.28, 0.12, 0.18), Vector3(0, 0.18, 0), dyn.darkened(0.6))            # temporizador
	bomb_led = U.sphere(bomb, 0.025, Vector3(0.11, 0.25, -0.06), Color(1.0, 0.1, 0.05), true)
	for i in 3:
		U.limb(bomb, Vector3(-0.1 + i * 0.06, 0.2, 0.08), Vector3(-0.2 + i * 0.12, 0.1, 0.2), 0.008, 0.008,
			[Color(1, 0.1, 0.1), Color(0.1, 0.3, 1.0), Color(1.0, 0.9, 0.1)][i])
	bomb_lbl = Label3D.new()
	bomb_lbl.text = "01:15"
	bomb_lbl.font_size = 48
	bomb_lbl.pixel_size = 0.003
	bomb_lbl.modulate = Color(1.0, 0.15, 0.1)
	bomb_lbl.outline_size = 0
	bomb_lbl.position = Vector3(0, 0.2, -0.095)
	bomb_lbl.rotation_degrees.y = 0.0
	bomb.add_child(bomb_lbl)
	bomb.visible = false


func _build_exit_door() -> void:
	exit_door = Node3D.new()
	exit_door.position = Vector3(0, 0, 98.36)
	add_child(exit_door)
	U.box(exit_door, Vector3(1.6, 2.4, 0.08), Vector3(0, 1.2, -0.02), Color(0.75, 0.15, 0.1))
	U.box(exit_door, Vector3(1.3, 0.08, 0.1), Vector3(0, 1.05, -0.08), Color(0.8, 0.8, 0.82))   # barra antipánico
	U.box(exit_door, Vector3(1.0, 0.25, 0.02), Vector3(0, 1.75, -0.07), Color(0.1, 0.7, 0.2), true)
	var l := Label3D.new()
	l.text = "EMERGENCIA"
	l.font_size = 32
	l.pixel_size = 0.004
	l.outline_size = 0
	l.rotation_degrees.y = 180.0
	l.position = Vector3(0, 1.75, -0.09)
	exit_door.add_child(l)


func _piece_model(id: String) -> Node3D:
	var n := Node3D.new()
	match id:
		"detonador":
			U.box(n, Vector3(0.2, 0.3, 0.1), Vector3.ZERO, Color(0.85, 0.1, 0.1))
			U.box(n, Vector3(0.14, 0.08, 0.02), Vector3(0, 0.06, -0.055), Color(0.1, 0.1, 0.1))
			U.sphere(n, 0.03, Vector3(0, -0.07, -0.06), Color(0.1, 1.0, 0.2), true)
			U.cylinder(n, 0.01, 0.25, Vector3(0.06, 0.27, 0), Color(0.2, 0.2, 0.2))
			U.sphere(n, 0.02, Vector3(0.06, 0.4, 0), Color(1.0, 0.2, 0.1), true)
		"cables":
			for i in 3:
				var tor := MeshInstance3D.new()
				var tm := TorusMesh.new()
				tm.inner_radius = 0.1
				tm.outer_radius = 0.14
				tor.mesh = tm
				tor.material_override = U.mat([Color(1, 0.15, 0.1), Color(0.1, 0.35, 1.0), Color(1.0, 0.85, 0.1)][i])
				tor.position = Vector3(0, -0.06 + i * 0.05, 0)
				tor.rotation_degrees = Vector3(80.0, i * 30.0, 0)
				n.add_child(tor)
		_:
			for i in 3:
				U.box(n, Vector3(0.3, 0.07, 0.14), Vector3(0, -0.07 + i * 0.075, 0), Color(0.82, 0.76, 0.58))
			U.box(n, Vector3(0.12, 0.06, 0.1), Vector3(0, 0.15, 0), Color(0.08, 0.08, 0.1))
			U.sphere(n, 0.02, Vector3(0.04, 0.19, -0.03), Color(1.0, 0.1, 0.05), true)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.85, 0.3)
	l.light_energy = 1.2
	l.omni_range = 3.0
	n.add_child(l)
	U.toonify(n, 0.008)
	return n


# Indicador flotante que se ve a través de las paredes
func _marker(pos: Vector3, c: Color, title: String) -> Label3D:
	var m := Label3D.new()
	m.position = pos
	m.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	m.no_depth_test = true
	m.fixed_size = true
	m.pixel_size = 0.0012
	m.font_size = 28
	m.outline_size = 8
	m.modulate = c
	m.render_priority = 10
	add_child(m)
	m.set_meta("title", title)
	return m


func _build_ui() -> void:
	layer = CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	red_rect = ColorRect.new()
	red_rect.color = Color(1.0, 0.0, 0.0, 0.0)
	red_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	red_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(red_rect)
	# objetivos en un panel oscuro arriba a la derecha (mismo estilo que el HUD)
	var obj_panel := PanelContainer.new()
	obj_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	obj_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	obj_panel.offset_left = -20.0
	obj_panel.offset_right = -20.0
	obj_panel.offset_top = 16.0
	obj_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	obj_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(obj_panel)
	obj_lbl = Label.new()
	obj_lbl.add_theme_font_size_override("font_size", 13)
	obj_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	obj_lbl.add_theme_constant_override("shadow_outline_size", 5)
	obj_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	obj_lbl.add_theme_constant_override("line_spacing", 2)
	obj_lbl.add_theme_font_override("font", HudScript.fuente(HudScript.F_UI))
	obj_panel.add_child(obj_lbl)
	timer_lbl = Label.new()
	timer_lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
	timer_lbl.offset_left = -200.0
	timer_lbl.offset_right = 200.0
	timer_lbl.offset_top = 10.0
	timer_lbl.offset_bottom = 80.0
	timer_lbl.pivot_offset = Vector2(200, 35)
	timer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_lbl.add_theme_font_size_override("font_size", 40)
	timer_lbl.add_theme_font_override("font", HudScript.fuente(HudScript.F_NUM))
	timer_lbl.add_theme_color_override("font_color", Color(1.0, 0.2, 0.15))
	timer_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	timer_lbl.add_theme_constant_override("outline_size", 10)
	timer_lbl.visible = false
	layer.add_child(timer_lbl)
	brief = Label.new()
	brief.set_anchors_preset(Control.PRESET_CENTER)
	brief.offset_left = -640.0
	brief.offset_right = 640.0
	brief.offset_top = 60.0
	brief.offset_bottom = 200.0
	brief.pivot_offset = Vector2(640, 70)
	brief.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	brief.add_theme_font_size_override("font_size", 19)
	brief.add_theme_font_override("font", HudScript.fuente(HudScript.F_UI))
	brief.add_theme_color_override("font_color", Color(1.0, 0.93, 0.75))
	brief.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.65))
	brief.add_theme_constant_override("shadow_outline_size", 10)
	brief.add_theme_constant_override("shadow_offset_y", 1)
	brief.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(brief)
	prompt = Label.new()
	prompt.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	prompt.offset_top = -215.0
	prompt.offset_bottom = -175.0
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size", 28)
	prompt.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6))
	prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	prompt.add_theme_constant_override("outline_size", 6)
	prompt.visible = false        # su texto lo enseña la pastilla del HUD
	layer.add_child(prompt)
	bar = ProgressBar.new()
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.offset_left = -220.0
	bar.offset_right = 220.0
	bar.offset_top = -170.0
	bar.offset_bottom = -145.0
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1.0, 0.55, 0.1)
	bar.add_theme_stylebox_override("fill", fill)
	bar.visible = false
	layer.add_child(bar)
	flash = ColorRect.new()
	flash.color = Color(1, 1, 1, 0)
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(flash)


func _build_sounds() -> void:
	snd_beep = AudioStreamPlayer.new()
	snd_beep.stream = _tone(1500.0, 0.07, 0.0)
	snd_beep.volume_db = -8.0
	add_child(snd_beep)
	snd_pick = AudioStreamPlayer.new()
	snd_pick.stream = _tone(660.0, 0.25, 900.0)
	snd_pick.volume_db = -6.0
	add_child(snd_pick)
	snd_boom = AudioStreamPlayer.new()
	snd_boom.stream = _boom()
	snd_boom.volume_db = 4.0
	add_child(snd_boom)


# Pitido (slide = Hz que sube durante el sonido, para el "¡ding!" al coger piezas)
func _tone(freq: float, dur: float, slide: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var ph := 0.0
	for i in n:
		var k := float(i) / n
		ph += TAU * (freq + slide * k) / rate
		var s := sin(ph) * (1.0 - k) * 0.6
		data.encode_s16(i * 2, int(s * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w


# Explosión grave y larga
func _boom() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 3.0)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var tt := float(i) / rate
		lp = lerpf(lp, randf() * 2.0 - 1.0, 0.08)
		lp2 = lerpf(lp2, lp, 0.3)
		var s := lp2 * 4.0 * exp(-tt * 1.4) + sin(tt * TAU * 40.0) * exp(-tt * 3.0) * 0.5
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w

extends "res://scripts/mapas/mission.gd"
# INVESTIGA: has "escapado" de CESUR y te despiertas en un sitio que no conoces
# (Mojácar, el Hotel Pueblo Indalo...). Mientras siguen llegando oleadas:
#  1. Busca las pistas del mapa (los "?" solo se ven de cerca).
#  2. Con todas, aparece la puerta del aula donde no debería haber ninguna puerta.
#  3. La cruzas... y apareces en el siguiente sitio del bucle.
# Usa la interfaz y los sonidos de mission.gd; las pistas vienen de mapas.gd.

const NEAR_MARK := 16.0      # a qué distancia se ve el "?" de una pista
const READ_TIME := 9.0       # segundos que se queda el texto de una pista

var mapa                     # mapas.gd
var found := {}
var glints := {}
var door: Node3D
var door_marker: Label3D
var reader: PanelContainer
var read_title: Label
var read_text: Label
var read_tw: Tween


func _ready() -> void:
	mapa = game.mapa
	_build_ui()
	_build_sounds()
	_build_reader()
	for p in mapa.pistas:
		found[p[0]] = false
		glints[p[0]] = _glint(p[3] + Vector3(0, 1.1, 0))
		markers[p[0]] = _marker(p[3] + Vector3(0, 1.7, 0), Color(0.55, 0.85, 1.0), "?")
		markers[p[0]].visible = false
	door = MapasScript.puerta_aula(self, mapa.puerta_pos, mapa.puerta_yaw)
	door.visible = false
	markers["door"] = _marker(mapa.puerta_pos + Vector3(0, 3.3, 0), Color(0.3, 1.0, 0.4), "LA PUERTA DEL AULA")
	markers["door"].visible = false
	brief.text = mapa.intro
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
	if stage == 0:
		for p in mapa.pistas:
			if not found[p[0]] and _dist(p[3]) < 2.2:
				prompt.text = "[E] Investigar: %s" % p[1]
				if e_down:
					_send_inv("pista", p[0])
				break
	elif stage == 1:
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
		s += "○  Pistas: %d / %d" % [n, mapa.pistas.size()]
		if nearest < INF:
			s += "\n     la más cercana a %d m" % int(nearest)
	else:
		s += "○  Cruza la puerta del aula · %d m" % int(_dist(mapa.puerta_pos))
	obj_lbl.text = s
	for p in mapa.pistas:
		var m: Label3D = markers[p[0]]
		m.visible = not found[p[0]] and _dist(p[3]) < NEAR_MARK
		if m.visible:
			m.text = "?\n%d m" % int(_dist(p[3]))
	if markers["door"].visible:
		markers["door"].text = "LA PUERTA DEL AULA\n%d m" % int(_dist(mapa.puerta_pos))


# ---------------- Pasos (en red se aplican en todos los PCs) ----------------
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


func _found(id: String) -> void:
	found[id] = true
	snd_pick.play()
	var g: Node3D = glints[id]
	var tw := g.create_tween()
	tw.tween_property(g, "scale", Vector3.ONE * 1.8, 0.12)
	tw.tween_property(g, "scale", Vector3.ZERO, 0.2)
	tw.tween_callback(g.hide)
	markers[id].visible = false
	for p in mapa.pistas:
		if p[0] == id:
			_read(p[1], p[2])
	# cada pista que descubres "despierta" a alguien
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


# ---------------- Panel con el texto de la pista ----------------
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
	read_title.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	box.add_child(read_title)
	read_text = Label.new()
	read_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	read_text.add_theme_font_size_override("font_size", 20)
	read_text.add_theme_color_override("font_color", Color(0.95, 0.93, 0.85))
	read_text.add_theme_constant_override("line_spacing", 4)
	box.add_child(read_text)


# Brillo flotante que marca una pista (una lupa con un "?" dentro)
func _glint(pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.set_meta("y", pos.y)
	add_child(n)
	var tor := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.13
	tm.outer_radius = 0.17
	tor.mesh = tm
	tor.material_override = U.mat(Color(0.55, 0.85, 1.0), true)
	tor.rotation_degrees.x = 90.0
	n.add_child(tor)
	var mango := U.box(n, Vector3(0.05, 0.22, 0.05), Vector3(0.14, -0.2, 0), Color(0.3, 0.2, 0.12))
	mango.rotation_degrees.z = 40.0
	var q := Label3D.new()
	q.text = "?"
	q.font_size = 64
	q.pixel_size = 0.004
	q.outline_size = 8
	q.modulate = Color(0.75, 0.92, 1.0)
	q.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	n.add_child(q)
	var l := OmniLight3D.new()
	l.light_color = Color(0.55, 0.8, 1.0)
	l.light_energy = 1.0
	l.omni_range = 3.0
	n.add_child(l)
	return n

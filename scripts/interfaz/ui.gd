extends Node
# Menú de inicio animado (con escena 3D de fondo), personalización del personaje,
# pantalla de controles y menú de pausa.

const U = preload("res://scripts/nucleo/util.gd")
const Ch = preload("res://scripts/jugador/character.gd")

static var autostart := false     # true = al recargar la escena empieza a jugar directamente

const CONTROLS := "WASD  ·  mover\nShift  ·  correr (disparar corta la carrera)\nE (mantener)  ·  reanimar a un compañero caído (cooperativo)\nRatón  ·  mirar\nClic izquierdo  ·  disparar / atacar\nR  ·  recargar\n1 / 2 / 3  ·  cambiar de arma (3 = katana)\n4 / G  ·  granada Jan (mantén clic y suelta para lanzar)\nE  ·  comprar armas, abrir puertas y usar la caja\nF  ·  linterna\nV  ·  cámara primera / tercera persona\nF8  ·  cámara libre (partidas de un jugador)\nEsc  ·  pausa"
const RED := Color(0.9, 0.08, 0.1)
const HudScript = preload("res://scripts/interfaz/hud.gd")

var state := 0                    # 0 menú, 1 jugando, 2 pausa
var con_camara := false           # al empezar, entrar directamente en la cámara libre
var layer: CanvasLayer
var t := 0.0
var font_bold: Font
var font_title: Font

# Fondo 3D
var bg_container: SubViewportContainer
var bg_vp: SubViewport
var bg_cam: Camera3D
var cam_target := Vector3(-0.2, 1.25, 4.6)
var look_target := Vector3(0.4, 1.05, 0.0)
var red_light: OmniLight3D
var preview_pivot: Node3D
var preview_model: Node3D
var preview_eyes: Array = []
var custom_rot := 0.0
var blink_t := 2.0
var menu_zombies: Array = []

# Pantallas
var menu_root: Control
var title_box: Control
var title_lbl: Label
var title_base := Vector2.ZERO
var buttons_box: VBoxContainer
var menu_buttons: Array = []
var drip: CPUParticles2D
var flash_rect: ColorRect
var custom_root: Control
var custom_panel: PanelContainer
var custom_vals := {}
var custom_swatches := {}
var dragging := false
var pause_root: Control
var pause_panel: Control
var controls_root: Control
var controls_panel: Control
var fade: ColorRect
var pause_restart_btn: Button
var menu_notice: Label
# Multijugador
var net_root: Control
var net_panel: Control
var name_edit: LineEdit
var ip_edit: LineEdit
var mode_btn: Button
var net_mode := "coop"
var games_box: VBoxContainer
var no_games: Label
var net_status: Label
var lobby_root: Control
var lobby_panel: Control
var lobby_title: Label
var lobby_info: Label
var lobby_list: Label
var lobby_mode_btn: Button
var lobby_start: Button
var lobby_wait: Label
var lobby_status: Label

# Sonidos
var snd_click: AudioStreamPlayer
var snd_hover: AudioStreamPlayer
var snd_drone: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Ch.load_skin()
	font_bold = HudScript.fuente(HudScript.F_NUM)
	font_title = load("res://fuentes/Creepster-Regular.ttf") if ResourceLoader.exists("res://fuentes/Creepster-Regular.ttf") else font_bold
	layer = CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	_build_sounds()
	_build_background()
	_build_menu()
	_build_custom()
	_build_pause()
	_build_controls()
	_build_net()
	Net.lobby_changed.connect(_refresh_lobby)
	Net.games_found_changed.connect(_refresh_games)
	Net.status.connect(_on_net_status)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 1)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(fade)
	if autostart:
		autostart = false
		menu_root.visible = false
		_set_bg(false)
		state = 1
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		create_tween().tween_property(fade, "color:a", 0.0, 0.5)
	else:
		_open_main_menu()


# =============================================================
# Bucle de animación (funciona también con el juego en pausa)
# =============================================================
func _process(delta: float) -> void:
	t += delta
	if bg_container.visible:
		var wob := Vector3(sin(t * 0.3) * 0.15, sin(t * 0.5) * 0.05, 0.0)
		bg_cam.position = bg_cam.position.lerp(cam_target + wob, 3.0 * delta)
		bg_cam.look_at(look_target, Vector3.UP)
		# luz roja que late y a veces se apaga de golpe
		var e := 3.5 + sin(t * 2.0) * 1.2
		if randf() < 0.015:
			red_light.light_energy = 0.2
			flash_rect.color.a = 0.18
		red_light.light_energy = lerpf(red_light.light_energy, e, 6.0 * delta)
		flash_rect.color.a = lerpf(flash_rect.color.a, 0.0, 5.0 * delta)
		# personaje: gira solo en el menú, en personalizar lo giras tú
		if custom_root.visible:
			preview_pivot.rotation.y = lerp_angle(preview_pivot.rotation.y, PI + custom_rot, 8.0 * delta)
		else:
			preview_pivot.rotation.y += delta * 0.5
		if preview_model != null:
			preview_model.position.y = sin(t * 2.0) * 0.015
		# parpadeo
		blink_t -= delta
		if blink_t <= 0.0:
			blink_t = randf_range(2.0, 4.5)
			for eye in preview_eyes:
				var tw := create_tween()
				tw.tween_property(eye, "scale:y", 0.1, 0.06)
				tw.tween_property(eye, "scale:y", 1.0, 0.08)
		# zombies acercándose entre la niebla
		for z in menu_zombies:
			var n: Node3D = z["node"]
			n.position.z += float(z["speed"]) * delta
			var ph: float = z["phase"]
			z["model"].rotation.z = sin(t * 2.2 + ph) * 0.08
			z["model"].position.y = absf(sin(t * 2.2 + ph)) * 0.05
			Ch.zombie_walk(z["legs"], t * 2.2 + ph, 0.7)
			if n.position.z > -1.8:
				n.position = Vector3(randf_range(0.0, 5.5), 0.0, randf_range(-15.0, -11.0))

	if menu_root.visible:
		# título que late y hace "glitch" de vez en cuando
		title_lbl.scale = Vector2.ONE * (1.0 + sin(t * 2.4) * 0.025)
		if randf() < 0.01:
			title_lbl.position = title_base + Vector2(randf_range(-10, 10), randf_range(-5, 5))
			title_lbl.modulate = Color(1, 1, 1, randf_range(0.3, 0.8))
		title_lbl.position = title_lbl.position.lerp(title_base, 12.0 * delta)
		title_lbl.modulate = title_lbl.modulate.lerp(Color(1, 1, 1, 1), 6.0 * delta)
		var vs := get_viewport().get_visible_rect().size
		drip.position = Vector2(vs.x * 0.5, -10.0)
		drip.emission_rect_extents = Vector2(vs.x * 0.5, 2.0)


func _input(event: InputEvent) -> void:
	# girar al personaje arrastrando con el ratón en la pantalla de personalizar
	if custom_root.visible:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed and event.position.x < get_viewport().get_visible_rect().size.x * 0.45
		elif event is InputEventMouseMotion and dragging:
			custom_rot += event.relative.x * 0.01
	if event is InputEventKey and event.pressed and not event.echo:
		var con = get_parent().get("consola")
		if con != null and con.abierta:
			return      # escribiendo en la consola (la P no pausa)
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_P:
			if lobby_root.visible:
				_lobby_leave()
			elif net_root.visible:
				_net_back()
			elif controls_root.visible:
				_hide_controls()
			elif custom_root.visible:
				_custom_done()
			elif state == 1 and not _player_dead() and not _shop_open():
				_pause()
			elif state == 2:
				_resume()


# =============================================================
# Cambios de pantalla
# =============================================================
func _open_main_menu() -> void:
	state = 0
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_set_bg(true)
	menu_root.visible = true
	custom_root.visible = false
	pause_root.visible = false
	snd_drone.play()
	fade.color.a = 1.0
	create_tween().tween_property(fade, "color:a", 0.0, 0.9)
	_intro_anim()
	# aviso si se volvió al menú por un problema de red
	if Net.last_status != "":
		menu_notice.text = Net.last_status
		Net.last_status = ""
		menu_notice.modulate.a = 1.0
		var tw := create_tween()
		tw.tween_interval(6.0)
		tw.tween_property(menu_notice, "modulate:a", 0.0, 1.0)


func _intro_anim() -> void:
	title_box.modulate.a = 0.0
	title_box.scale = Vector2.ONE * 1.5
	var tw := create_tween().set_parallel(true)
	tw.tween_property(title_box, "modulate:a", 1.0, 0.6).set_delay(0.3)
	tw.tween_property(title_box, "scale", Vector2.ONE, 0.7).set_delay(0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	buttons_box.modulate.a = 1.0
	for i in menu_buttons.size():
		var b: Button = menu_buttons[i]
		b.modulate.a = 0.0
		b.scale = Vector2.ONE * 0.4
		var d := 0.7 + i * 0.1
		tw.tween_property(b, "modulate:a", 1.0, 0.3).set_delay(d)
		tw.tween_property(b, "scale", Vector2.ONE, 0.45).set_delay(d).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _set_bg(on: bool) -> void:
	bg_container.visible = on
	if on:
		bg_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	else:
		bg_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _player_dead() -> bool:
	var g = get_tree().get_first_node_in_group("game")
	return g != null and g.player.dead


func _start_game() -> void:
	if state != 0:
		return
	if Net.online:
		Net.leave()       # JUGAR = partida de un solo jugador
	state = -1    # en transición
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.45)
	tw.tween_callback(_begin_play)
	tw.tween_property(fade, "color:a", 0.0, 0.5)


func _begin_play() -> void:
	state = 1
	menu_root.visible = false
	custom_root.visible = false
	_set_bg(false)
	snd_drone.stop()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if con_camara:
		con_camara = false
		get_tree().get_first_node_in_group("game").camara.activar()


# Botón CÁMARA LIBRE: entra al mapa volando, sin jugar
func _start_camara() -> void:
	con_camara = true
	_start_game()


func _pause() -> void:
	state = 2
	pause_root.visible = true
	pause_restart_btn.visible = Net.is_host()
	if Net.online:
		# en red la partida sigue para los demás: solo se bloquean tus controles
		_local_player().input_blocked = true
	else:
		get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_pop_in(pause_panel)


func _resume() -> void:
	state = 1
	pause_root.visible = false
	if Net.online:
		_local_player().input_blocked = false
	else:
		get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# El menú de la tienda de Juan Carlos usa Esc para cerrarse
func _shop_open() -> bool:
	var g = get_tree().get_first_node_in_group("game")
	return g != null and ((g.tienda != null and g.tienda.menu_open) or (g.casino != null and g.casino.menu_open) or g.code_open)


func _local_player():
	return get_tree().get_first_node_in_group("game").player


func _restart() -> void:
	if Net.online:
		if Net.is_host():
			Net.start_game()      # reinicia la partida a todos
		return
	Net.reset_loop()
	autostart = true
	get_tree().paused = false
	get_tree().reload_current_scene()


func _to_menu() -> void:
	if Net.online:
		Net.quit_to_menu()
		return
	Net.reset_loop()
	autostart = false
	get_tree().paused = false
	get_tree().reload_current_scene()


func _show_controls() -> void:
	controls_root.visible = true
	_pop_in(controls_panel)


func _hide_controls() -> void:
	controls_root.visible = false


func _quit() -> void:
	get_tree().quit()


func _show_custom() -> void:
	custom_rot = 0.0
	cam_target = Vector3(-0.6, 1.3, 2.7)
	look_target = Vector3(0.1, 1.05, 0.6)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(title_box, "modulate:a", 0.0, 0.25)
	tw.tween_property(buttons_box, "modulate:a", 0.0, 0.25)
	tw.chain().tween_callback(func():
		title_box.visible = false
		buttons_box.visible = false
		custom_root.visible = true
		_update_custom_labels()
		_pop_in(custom_panel))


func _custom_done() -> void:
	Ch.save_skin()
	var g = get_tree().get_first_node_in_group("game")
	if g != null:
		g.player.refresh_look()
	custom_root.visible = false
	cam_target = Vector3(-0.2, 1.25, 4.6)
	look_target = Vector3(0.4, 1.05, 0.0)
	title_box.visible = true
	buttons_box.visible = true
	_intro_anim()


func _pop_in(c: Control) -> void:
	c.pivot_offset = c.size * 0.5
	c.modulate.a = 0.0
	c.scale = Vector2.ONE * 0.85
	var tw := create_tween().set_parallel(true)
	tw.tween_property(c, "modulate:a", 1.0, 0.2)
	tw.tween_property(c, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# =============================================================
# Personalización
# =============================================================
func _change(key: String, dir: int) -> void:
	var n: int = Ch.opt_list(key).size()
	Ch.skin[key] = posmod(int(Ch.skin[key]) + dir, n)
	Ch.save_skin()
	_update_custom_labels()
	_rebuild_preview()


func _randomize() -> void:
	Ch.randomize_skin()
	Ch.save_skin()
	_update_custom_labels()
	_rebuild_preview()


func _update_custom_labels() -> void:
	for o in Ch.OPTIONS:
		var key: String = o[0]
		var idx: int = Ch.skin[key]
		custom_vals[key].text = Ch.opt_name(key, idx)
		# con un aspecto predeterminado el resto de opciones no se usan: se ven apagadas
		custom_vals[key].modulate.a = 0.35 if key != "preset" and int(Ch.skin["preset"]) != 0 else 1.0
		var it = Ch.opt_list(key)[idx]
		var sw: ColorRect = custom_swatches[key]
		if it is Array:
			sw.visible = true
			sw.color = it[1]
		else:
			sw.visible = false


func _rebuild_preview() -> void:
	if preview_model != null:
		preview_model.free()
	var parts: Dictionary = Ch.build_player(preview_pivot, Ch.skin)
	preview_model = parts["model"]
	preview_eyes = parts["eyes"]
	var gun := U.gun_model("fusil")
	gun.position = Vector3(0.22, 1.1, -0.45)
	preview_model.add_child(gun)
	U.toonify(gun, 0.006)
	preview_model.scale = Vector3.ONE * 0.88
	preview_model.create_tween().tween_property(preview_model, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# =============================================================
# Construcción del fondo 3D
# =============================================================
func _build_background() -> void:
	bg_container = SubViewportContainer.new()
	bg_container.stretch = true
	bg_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(bg_container)
	bg_vp = SubViewport.new()
	bg_vp.own_world_3d = true
	bg_vp.msaa_3d = Viewport.MSAA_4X
	bg_container.add_child(bg_vp)
	var root := Node3D.new()
	bg_vp.add_child(root)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.0, 0.01)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.35, 0.4)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 1.0
	env.glow_bloom = 0.1
	env.fog_enabled = true
	env.fog_light_color = Color(0.25, 0.03, 0.05)
	env.fog_density = 0.07
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	# suelo, pared del fondo con CESUR y pupitres volcados
	U.box(root, Vector3(40, 0.1, 40), Vector3(0, -0.05, -8), Color(0.18, 0.15, 0.15))
	U.box(root, Vector3(40, 10, 0.5), Vector3(0, 5, -16), Color(0.35, 0.32, 0.3))
	var cesur := Label3D.new()
	cesur.text = "CESUR"
	cesur.font_size = 300
	cesur.pixel_size = 0.012
	cesur.outline_size = 0
	cesur.modulate = Color(0.05, 0.12, 0.45)
	cesur.position = Vector3(2.0, 4.5, -15.7)
	root.add_child(cesur)
	for i in 7:
		var d := Node3D.new()
		d.position = Vector3(randf_range(-6.0, 7.0), 0.0, randf_range(-13.0, -3.0))
		d.rotation = Vector3(0, randf_range(-PI, PI), randf_range(-0.3, 0.3))
		root.add_child(d)
		U.box(d, Vector3(1.4, 0.75, 0.7), Vector3(0, 0.375, 0), Color(0.75, 0.75, 0.72))
		U.box(d, Vector3(0.7, 0.45, 0.05), Vector3(0, 1.0, -0.1), Color(0.05, 0.05, 0.07))
		U.box(d, Vector3(0.62, 0.37, 0.01), Vector3(0, 1.0, -0.07), Color(0.2, 0.4, 0.9), true)

	# luces: roja que late, principal sobre el personaje y contraluz azul
	red_light = OmniLight3D.new()
	red_light.light_color = Color(1.0, 0.1, 0.12)
	red_light.light_energy = 3.5
	red_light.omni_range = 16.0
	red_light.position = Vector3(2.5, 3.0, -4.0)
	root.add_child(red_light)
	var key := SpotLight3D.new()
	key.light_color = Color(1.0, 0.92, 0.8)
	key.light_energy = 7.0
	key.spot_range = 12.0
	key.spot_angle = 28.0
	key.shadow_enabled = true
	root.add_child(key)
	key.look_at_from_position(Vector3(0.8, 4.2, 3.8), Vector3(-1.2, 1.0, 0.6), Vector3.UP)
	var rim := OmniLight3D.new()
	rim.light_color = Color(0.3, 0.55, 1.0)
	rim.light_energy = 3.0
	rim.omni_range = 4.0
	rim.position = Vector3(-1.8, 2.3, -0.8)
	root.add_child(rim)

	# protagonista (la vista previa de la personalización)
	preview_pivot = Node3D.new()
	preview_pivot.position = Vector3(-1.2, 0.0, 0.6)
	preview_pivot.rotation.y = PI
	root.add_child(preview_pivot)
	_rebuild_preview()

	# zombies caminando hacia la cámara
	for i in 5:
		var holder := Node3D.new()
		holder.rotation.y = PI
		holder.position = Vector3(randf_range(0.0, 5.5), 0.0, randf_range(-14.0, -3.0))
		root.add_child(holder)
		var parts: Dictionary = Ch.build_zombie(holder, 1.2)
		menu_zombies.append({"node": holder, "model": parts["model"], "legs": parts["legs"],
			"phase": randf() * TAU, "speed": randf_range(0.35, 0.6)})

	bg_cam = Camera3D.new()
	bg_cam.fov = 50.0
	bg_cam.position = cam_target
	root.add_child(bg_cam)
	bg_cam.current = true


# =============================================================
# Construcción de la interfaz
# =============================================================
func _style_button(b: Button, size: Vector2, font_size: int) -> void:
	# placas inclinadas con una franja roja a la izquierda (como el HUD)
	var ancho := size.x >= 200.0
	var n := StyleBoxFlat.new()
	n.bg_color = Color(0.05, 0.02, 0.025, 0.82)
	n.border_color = Color(0.75, 0.06, 0.09)
	n.set_border_width_all(0)
	n.border_width_left = 6 if ancho else 0
	n.border_width_bottom = 0 if ancho else 2
	n.set_corner_radius_all(2)
	n.skew = Vector2(0.22, 0.0) if ancho else Vector2.ZERO
	n.content_margin_left = 30 if ancho else 4
	n.content_margin_right = 12 if ancho else 4
	n.shadow_color = Color(0, 0, 0, 0.55)
	n.shadow_size = 8
	n.shadow_offset = Vector2(3, 4)
	var h: StyleBoxFlat = n.duplicate()
	h.bg_color = Color(0.62, 0.04, 0.07, 0.94)
	h.border_color = Color(1.0, 0.82, 0.36)
	h.border_width_left = 10 if ancho else 0
	h.content_margin_left = 40 if ancho else 4
	var p: StyleBoxFlat = h.duplicate()
	p.bg_color = Color(0.9, 0.12, 0.14)
	if ancho:
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	font_size = int(font_size * 1.18)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", p)
	b.add_theme_stylebox_override("focus", h)
	b.add_theme_font_override("font", font_bold)
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", Color(0.95, 0.92, 0.9))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.86, 0.45))
	b.add_theme_color_override("font_focus_color", Color(1.0, 0.86, 0.45))
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	b.add_theme_constant_override("outline_size", 4)
	b.custom_minimum_size = size
	b.pivot_offset = size * 0.5
	b.mouse_entered.connect(func():
		snd_hover.play()
		b.pivot_offset = b.size * 0.5
		create_tween().tween_property(b, "scale", Vector2.ONE * 1.08, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	b.mouse_exited.connect(func():
		create_tween().tween_property(b, "scale", Vector2.ONE, 0.12))


func _button(parent: Node, text: String, cb: Callable, size := Vector2(360, 54), font_size := 30) -> Button:
	var b := Button.new()
	b.text = text
	_style_button(b, size, font_size)
	b.pressed.connect(func():
		snd_click.play()
		cb.call())
	parent.add_child(b)
	return b


func _label(parent: Node, text: String, size: int, col: Color, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if bold:
		l.add_theme_font_override("font", font_bold)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		l.add_theme_constant_override("outline_size", 10)
	parent.add_child(l)
	return l


func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.035, 0.02, 0.03, 0.92)
	s.border_color = Color(0.75, 0.06, 0.09)
	s.set_border_width_all(1)
	s.border_width_top = 4
	s.set_corner_radius_all(4)
	s.set_content_margin_all(22)
	s.shadow_color = Color(0, 0, 0, 0.7)
	s.shadow_size = 14
	return s


func _build_menu() -> void:
	menu_root = Control.new()
	menu_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(menu_root)

	# viñeta oscura en los bordes
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.set_color(1, Color(0, 0, 0, 0.9))
	g.add_point(0.5, Color(0, 0, 0, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 1.0)
	var vig := TextureRect.new()
	vig.texture = gt
	vig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_root.add_child(vig)

	# destello rojo cuando parpadea la luz
	flash_rect = ColorRect.new()
	flash_rect.color = Color(0.8, 0.0, 0.0, 0.0)
	flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_root.add_child(flash_rect)

	# gotas de sangre cayendo desde arriba
	drip = CPUParticles2D.new()
	drip.amount = 45
	drip.lifetime = 4.0
	drip.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	drip.emission_rect_extents = Vector2(640, 2)
	drip.direction = Vector2(0, 1)
	drip.spread = 3.0
	drip.gravity = Vector2(0, 220)
	drip.initial_velocity_min = 10.0
	drip.initial_velocity_max = 60.0
	drip.scale_amount_min = 3.0
	drip.scale_amount_max = 7.0
	var dg := Gradient.new()
	dg.set_color(0, Color(0.75, 0.0, 0.03, 0.95))
	dg.set_color(1, Color(0.35, 0.0, 0.0, 0.0))
	drip.color_ramp = dg
	menu_root.add_child(drip)

	# título
	title_box = Control.new()
	title_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	title_box.offset_left = -720.0
	title_box.offset_right = -30.0
	title_box.offset_top = 30.0
	title_box.offset_bottom = 300.0
	title_box.pivot_offset = Vector2(345, 120)
	title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_root.add_child(title_box)
	title_lbl = Label.new()
	title_lbl.text = "ZOMBIES\nEN EL AULA"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.size = Vector2(690, 210)
	title_lbl.pivot_offset = Vector2(345, 105)
	title_lbl.add_theme_font_override("font", font_title)
	title_lbl.add_theme_font_size_override("font_size", 92)
	title_lbl.add_theme_constant_override("line_spacing", -18)
	title_lbl.add_theme_color_override("font_color", RED)
	title_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	title_lbl.add_theme_constant_override("outline_size", 22)
	title_lbl.add_theme_color_override("font_shadow_color", Color(0.3, 0.0, 0.0, 0.9))
	title_lbl.add_theme_constant_override("shadow_offset_x", 6)
	title_lbl.add_theme_constant_override("shadow_offset_y", 6)
	title_box.add_child(title_lbl)
	title_base = title_lbl.position
	var sub := Label.new()
	sub.text = "Sobrevive. Compra armas. No te quedes en clase."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.position = Vector2(0, 222)
	sub.size = Vector2(690, 40)
	sub.add_theme_font_size_override("font_size", 24)
	sub.add_theme_color_override("font_color", Color(0.9, 0.85, 0.85))
	sub.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	sub.add_theme_constant_override("outline_size", 6)
	title_box.add_child(sub)

	# botones
	buttons_box = VBoxContainer.new()
	buttons_box.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	buttons_box.offset_left = -565.0
	buttons_box.offset_right = -205.0
	buttons_box.offset_top = -56.0
	buttons_box.offset_bottom = 320.0
	buttons_box.add_theme_constant_override("separation", 10)
	menu_root.add_child(buttons_box)
	menu_buttons.append(_button(buttons_box, "JUGAR", _start_game))
	menu_buttons.append(_button(buttons_box, "MULTIJUGADOR", _show_net))
	menu_buttons.append(_button(buttons_box, "CÁMARA LIBRE", _start_camara))
	menu_buttons.append(_button(buttons_box, "PERSONALIZAR", _show_custom))
	menu_buttons.append(_button(buttons_box, "CONTROLES", _show_controls))
	menu_buttons.append(_button(buttons_box, "SALIR", _quit))

	var ver := Label.new()
	ver.text = "Zombies en el Aula · hecho con Godot"
	ver.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	ver.offset_left = 20.0
	ver.offset_top = -34.0
	ver.offset_right = 600.0
	ver.offset_bottom = -10.0
	ver.add_theme_font_size_override("font_size", 14)
	ver.add_theme_color_override("font_color", Color(0.8, 0.7, 0.7, 0.7))
	menu_root.add_child(ver)
	menu_notice = Label.new()
	menu_notice.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	menu_notice.offset_left = -500.0
	menu_notice.offset_right = 500.0
	menu_notice.offset_top = -80.0
	menu_notice.offset_bottom = -40.0
	menu_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_notice.add_theme_font_size_override("font_size", 22)
	menu_notice.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3))
	menu_notice.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	menu_notice.add_theme_constant_override("outline_size", 6)
	menu_root.add_child(menu_notice)
	menu_root.visible = false


func _build_custom() -> void:
	custom_root = Control.new()
	custom_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	custom_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(custom_root)
	custom_panel = PanelContainer.new()
	custom_panel.add_theme_stylebox_override("panel", _panel_style())
	custom_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	custom_panel.offset_left = -660.0
	custom_panel.offset_right = -40.0
	custom_panel.offset_top = -350.0
	custom_panel.offset_bottom = 350.0
	custom_root.add_child(custom_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	custom_panel.add_child(vb)
	_label(vb, "PERSONALIZAR", 46, RED, true)
	for o in Ch.OPTIONS:
		var key: String = o[0]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		vb.add_child(row)
		var name_l := Label.new()
		name_l.text = o[1]
		name_l.custom_minimum_size = Vector2(170, 0)
		name_l.add_theme_font_size_override("font_size", 19)
		name_l.add_theme_color_override("font_color", Color(0.8, 0.75, 0.75))
		row.add_child(name_l)
		_button(row, "<", _change.bind(key, -1), Vector2(46, 42), 24)
		var sw := ColorRect.new()
		sw.custom_minimum_size = Vector2(26, 26)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(sw)
		custom_swatches[key] = sw
		var val := Label.new()
		val.custom_minimum_size = Vector2(230, 0)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		val.add_theme_font_size_override("font_size", 21)
		row.add_child(val)
		custom_vals[key] = val
		_button(row, ">", _change.bind(key, 1), Vector2(46, 42), 24)
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 16)
	vb.add_child(bottom)
	_button(bottom, "ALEATORIO", _randomize, Vector2(220, 56), 24)
	_button(bottom, "LISTO", _custom_done, Vector2(220, 56), 24)
	_label(vb, "Arrastra con el ratón sobre el personaje para girarlo", 15, Color(0.75, 0.7, 0.7))
	custom_root.visible = false


func _build_pause() -> void:
	pause_root = Control.new()
	pause_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(pause_root)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.0, 0.0, 0.7)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_root.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(panel)
	pause_panel = panel
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	panel.add_child(vb)
	_label(vb, "PAUSA", 60, RED, true)
	_button(vb, "REANUDAR", _resume)
	_button(vb, "CONTROLES", _show_controls)
	pause_restart_btn = _button(vb, "REINICIAR PARTIDA", _restart)
	_button(vb, "MENÚ PRINCIPAL", _to_menu)
	_button(vb, "SALIR", _quit)
	pause_root.visible = false


func _build_controls() -> void:
	controls_root = Control.new()
	controls_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(controls_root)
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.6)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	controls_root.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	controls_root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(panel)
	controls_panel = panel
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	panel.add_child(vb)
	_label(vb, "CONTROLES", 52, RED, true)
	_label(vb, CONTROLS, 24, Color(0.92, 0.9, 0.9))
	_button(vb, "VOLVER", _hide_controls)
	controls_root.visible = false


# =============================================================
# Multijugador en red local: buscar/crear partida y sala de espera
# =============================================================
const MODE_NAMES := {"coop": "Cooperativo", "versus": "Todos contra todos"}


func _line_edit(parent: Node, text: String, hint: String, w: float) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.placeholder_text = hint
	e.custom_minimum_size = Vector2(w, 44)
	e.add_theme_font_size_override("font_size", 22)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.05, 0.06)
	sb.border_color = Color(0.6, 0.05, 0.08)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(8)
	e.add_theme_stylebox_override("normal", sb)
	e.add_theme_stylebox_override("focus", sb)
	parent.add_child(e)
	return e


func _row(parent: Node, label: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(150, 0)
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", Color(0.85, 0.8, 0.8))
	row.add_child(l)
	return row


func _build_net() -> void:
	# --- buscar o crear partida ---
	net_root = Control.new()
	net_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	net_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(net_root)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	panel.offset_left = -660.0
	panel.offset_right = -40.0
	panel.offset_top = -330.0
	panel.offset_bottom = 330.0
	net_root.add_child(panel)
	net_panel = panel
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	_label(vb, "MULTIJUGADOR", 46, RED, true)
	_label(vb, "En la misma red WiFi o cable", 17, Color(0.75, 0.7, 0.7))
	name_edit = _line_edit(_row(vb, "Tu nombre"), Net.my_name, "Escribe tu nombre", 300)
	name_edit.max_length = 16
	var mrow := _row(vb, "Modo")
	mode_btn = _button(mrow, MODE_NAMES[net_mode], _toggle_mode, Vector2(300, 46), 22)
	_button(vb, "CREAR PARTIDA", _net_host, Vector2(560, 56), 26)
	_label(vb, "Partidas encontradas", 22, Color(1.0, 0.85, 0.5))
	games_box = VBoxContainer.new()
	games_box.add_theme_constant_override("separation", 8)
	vb.add_child(games_box)
	no_games = _label(vb, "Buscando partidas en tu red...", 18, Color(0.7, 0.65, 0.65))
	var irow := _row(vb, "Unirse por IP")
	ip_edit = _line_edit(irow, "", "ej. 192.168.1.20", 230)
	_button(irow, "UNIRSE", func(): _net_join(ip_edit.text), Vector2(140, 46), 22)
	net_status = _label(vb, "", 18, Color(1.0, 0.75, 0.3))
	net_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	net_status.custom_minimum_size = Vector2(560, 0)
	_button(vb, "VOLVER", _net_back, Vector2(560, 52), 24)
	net_root.visible = false

	# --- sala de espera ---
	lobby_root = Control.new()
	lobby_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lobby_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(lobby_root)
	var lp := PanelContainer.new()
	lp.add_theme_stylebox_override("panel", _panel_style())
	lp.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	lp.offset_left = -660.0
	lp.offset_right = -40.0
	lp.offset_top = -300.0
	lp.offset_bottom = 300.0
	lobby_root.add_child(lp)
	lobby_panel = lp
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 14)
	lp.add_child(lv)
	lobby_title = _label(lv, "SALA", 46, RED, true)
	lobby_info = _label(lv, "", 19, Color(0.85, 0.8, 0.8))
	lobby_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lobby_info.custom_minimum_size = Vector2(560, 0)
	_label(lv, "Jugadores", 24, Color(1.0, 0.85, 0.5))
	lobby_list = _label(lv, "", 24, Color(0.95, 0.95, 0.95))
	lobby_mode_btn = _button(lv, "", _toggle_mode, Vector2(560, 50), 22)
	lobby_start = _button(lv, "EMPEZAR PARTIDA", _lobby_start, Vector2(560, 60), 28)
	lobby_wait = _label(lv, "Esperando a que el anfitrión empiece la partida...", 20, Color(0.8, 0.9, 1.0))
	lobby_status = _label(lv, "", 18, Color(1.0, 0.75, 0.3))
	_button(lv, "SALIR DE LA SALA", _lobby_leave, Vector2(560, 52), 24)
	lobby_root.visible = false


func _show_net() -> void:
	cam_target = Vector3(-0.6, 1.3, 2.7)
	look_target = Vector3(0.1, 1.05, 0.6)
	title_box.visible = false
	buttons_box.visible = false
	net_root.visible = true
	net_status.text = ""
	Net.last_status = ""
	Net.start_listening()
	_refresh_games()
	_pop_in(net_panel)


func _net_back() -> void:
	Net.save_name(name_edit.text)
	Net.stop_listening()
	net_root.visible = false
	cam_target = Vector3(-0.2, 1.25, 4.6)
	look_target = Vector3(0.4, 1.05, 0.0)
	title_box.visible = true
	buttons_box.visible = true
	_intro_anim()


func _toggle_mode() -> void:
	net_mode = "versus" if net_mode == "coop" else "coop"
	mode_btn.text = MODE_NAMES[net_mode]
	if Net.online and Net.is_host():
		Net.set_mode(net_mode)


func _net_host() -> void:
	Net.save_name(name_edit.text)
	Net.stop_listening()
	if Net.host(net_mode):
		_show_lobby()
	else:
		Net.start_listening()


func _net_join(ip: String) -> void:
	if ip.strip_edges() == "":
		net_status.text = "Escribe la IP del anfitrión"
		return
	Net.save_name(name_edit.text)
	Net.join(ip)


func _show_lobby() -> void:
	net_root.visible = false
	lobby_root.visible = true
	lobby_status.text = ""
	_refresh_lobby()
	_pop_in(lobby_panel)


func _lobby_leave() -> void:
	Net.leave()
	lobby_root.visible = false
	net_root.visible = true
	Net.start_listening()
	_refresh_games()


func _lobby_start() -> void:
	if Net.mode == "versus" and Net.players.size() < 2:
		lobby_status.text = "Hacen falta al menos 2 jugadores para todos contra todos"
		return
	Net.start_game()


func _refresh_lobby() -> void:
	if lobby_root == null:
		return
	# un cliente que acaba de entrar en la sala
	if Net.online and not lobby_root.visible and net_root.visible and Net.players.has(Net.my_id()):
		Net.stop_listening()
		_show_lobby()
		return
	if not lobby_root.visible:
		return
	if not Net.online:
		lobby_root.visible = false
		net_root.visible = true
		Net.start_listening()
		return
	var host := Net.is_host()
	lobby_title.text = "SALA · " + str(MODE_NAMES.get(Net.mode, Net.mode)).to_upper()
	var info := "Modo: %s" % MODE_NAMES.get(Net.mode, Net.mode)
	if Net.mode == "coop":
		info += " (hasta 4, oleadas y misión juntos; mantén E para reanimar)"
	else:
		info += " (gana el primero en llegar a 10 bajas)"
	if host:
		var ips := Net.local_ips()
		if ips.size() > 0:
			info += "\nTu IP: " + ", ".join(ips) + "  (por si no os aparece la partida)"
	lobby_info.text = info
	var lst := ""
	var ids: Array = Net.players.keys()
	ids.sort()
	for id in ids:
		lst += "• %s%s%s\n" % [Net.pname(id), "  (anfitrión)" if id == 1 else "", "  ← tú" if id == Net.my_id() else ""]
	lobby_list.text = lst
	lobby_mode_btn.visible = host
	lobby_mode_btn.text = "Cambiar modo: " + MODE_NAMES.get(Net.mode, Net.mode)
	lobby_start.visible = host
	lobby_wait.visible = not host


func _refresh_games() -> void:
	if games_box == null:
		return
	for c in games_box.get_children():
		c.queue_free()
	for sid in Net.found:
		var g: Dictionary = Net.found[sid]
		var ip: String = g["ip"]
		var txt := "%s  ·  %s  ·  %d/4  ·  %s" % [g.get("name", "?"), MODE_NAMES.get(g.get("mode", ""), "?"), int(g.get("count", 1)), ip]
		_button(games_box, txt, _net_join.bind(ip), Vector2(560, 48), 21)
	no_games.visible = Net.found.is_empty()


func _on_net_status(text: String) -> void:
	if net_status != null:
		net_status.text = text
	if lobby_status != null:
		lobby_status.text = text


# =============================================================
# Sonidos generados por código
# =============================================================
func _build_sounds() -> void:
	snd_click = AudioStreamPlayer.new()
	snd_click.stream = U.make_shot(0.12, true)
	snd_click.volume_db = -6.0
	add_child(snd_click)
	snd_hover = AudioStreamPlayer.new()
	snd_hover.stream = _tone(900.0, 0.05)
	snd_hover.volume_db = -18.0
	add_child(snd_hover)
	snd_drone = AudioStreamPlayer.new()
	snd_drone.stream = _make_drone()
	snd_drone.volume_db = -10.0
	add_child(snd_drone)


func _tone(freq: float, dur: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var tt := float(i) / rate
		var s := sin(TAU * freq * tt) * (1.0 - tt / dur)
		data.encode_s16(i * 2, int(s * 20000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w


# Zumbido grave y siniestro que se repite en bucle
func _make_drone() -> AudioStreamWAV:
	var rate := 22050
	var n := rate * 4
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var tt := float(i) / rate
		var amp := 0.6 + 0.4 * sin(TAU * 0.25 * tt)
		var s := 0.5 * sin(TAU * 55.0 * tt) + 0.3 * sin(TAU * 82.5 * tt) + 0.15 * sin(TAU * 110.25 * tt)
		data.encode_s16(i * 2, int(clampf(s * amp, -1.0, 1.0) * 22000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w

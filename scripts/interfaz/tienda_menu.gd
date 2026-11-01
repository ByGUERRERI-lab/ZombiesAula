extends CanvasLayer
# Menú de la tienda de Juan Carlos: se abre con E en su mostrador.
# Fondo desenfocado, tres tarjetas con el producto en 3D girando, precio,
# qué hace y botón de comprar. Teclas 1/2/3 para comprar, E o Esc para salir.
# En solitario pausa la partida; en red solo bloquea tus controles.

const U = preload("res://scripts/nucleo/util.gd")
const HudScript = preload("res://scripts/interfaz/hud.gd")

const NEON := Color(0.45, 1.0, 0.5)
const GOLD := Color(1.0, 0.86, 0.45)

var tienda
var game
var panel: PanelContainer
var points_lbl: Label
var quote: Label
var cards := {}              # id -> {"panel", "btn", "state", "item"}
var font_num: SystemFont
var font_ui: SystemFont
var snd_buy: AudioStreamPlayer
var snd_no: AudioStreamPlayer
var paused_it := false
var closing := false
var t := 0.0


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	game = tienda.game
	font_num = SystemFont.new()
	font_num.font_names = PackedStringArray(["Impact", "Arial Black", "Arial"])
	font_ui = SystemFont.new()
	font_ui.font_names = PackedStringArray(["Segoe UI", "Arial", "DejaVu Sans"])
	font_ui.font_weight = 600

	# fondo: lo que hay detrás, desenfocado y oscurecido
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bm := ShaderMaterial.new()
	bm.shader = Shader.new()
	bm.shader.code = """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, 3.0).rgb;
	float v = distance(SCREEN_UV, vec2(0.5));
	COLOR = vec4(c * (0.45 - v * 0.3) + vec3(0.0, 0.02, 0.0), 1.0);
}
"""
	bg.material = bm
	add_child(bg)

	panel = PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.03, 0.06, 0.04, 0.93)
	ps.border_color = NEON.darkened(0.3)
	ps.set_border_width_all(2)
	ps.set_corner_radius_all(18)
	ps.set_content_margin_all(26)
	ps.shadow_color = Color(0.2, 1.0, 0.3, 0.18)
	ps.shadow_size = 28
	panel.add_theme_stylebox_override("panel", ps)
	add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)

	# cabecera: título en neón y tus puntos
	var head := HBoxContainer.new()
	col.add_child(head)
	var title := _lbl(head, "LA TIENDA DE JUAN CARLOS", 40, NEON, font_num, 10)
	title.add_theme_color_override("font_outline_color", Color(0.02, 0.2, 0.04))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pts_box := VBoxContainer.new()
	pts_box.add_theme_constant_override("separation", -6)
	head.add_child(pts_box)
	var cap := _lbl(pts_box, "T U S   P U N T O S", 12, Color(1, 1, 1, 0.6), font_ui, 0)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	points_lbl = _lbl(pts_box, "", 34, GOLD, font_num, 6)
	points_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	quote = _lbl(col, "Juan Carlos:  «¿Qué te pongo, chaval?»", 18, Color(0.85, 0.95, 0.85, 0.85), font_ui, 0)

	# tarjetas de productos
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	col.add_child(row)
	var i := 0
	for id in tienda.ITEMS:
		i += 1
		_card(row, id, i)

	var foot := _lbl(col, "[1] [2] [3]  comprar      ·      [E] / [Esc]  salir", 15, Color(1, 1, 1, 0.55), font_ui, 0)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	snd_buy = AudioStreamPlayer.new()
	snd_buy.stream = U.make_kaching()
	add_child(snd_buy)
	snd_no = AudioStreamPlayer.new()
	snd_no.stream = U.make_beep(180.0)
	snd_no.volume_db = 4.0
	add_child(snd_no)

	# en solitario se para el juego; en red solo tus controles
	game.player.input_blocked = true
	if not Net.online:
		get_tree().paused = true
		paused_it = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()
	# aparece con un pequeño "pop"
	panel.reset_size()
	_center()
	panel.pivot_offset = panel.size / 2.0
	panel.scale = Vector2.ONE * 0.92
	panel.modulate.a = 0.0
	var tw := create_tween().set_parallel()
	tw.tween_property(panel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "modulate:a", 1.0, 0.15)


func _lbl(parent: Node, text: String, size: int, c: Color, font: Font, outline: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	if outline > 0:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		l.add_theme_constant_override("outline_size", outline)
	parent.add_child(l)
	return l


func _card_style(c: Color, hover: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.07, 0.08, 0.08, 0.95) if not hover else Color(0.1, 0.12, 0.11, 0.98)
	s.border_color = c if hover else Color(c.r, c.g, c.b, 0.35)
	s.set_border_width_all(2)
	s.border_width_top = 4
	s.set_corner_radius_all(12)
	s.set_content_margin_all(14)
	if hover:
		s.shadow_color = Color(c.r, c.g, c.b, 0.25)
		s.shadow_size = 14
	return s


func _card(row: Node, id: String, key: int) -> void:
	var it: Dictionary = tienda.ITEMS[id]
	var c: Color = it["color"]
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(260, 0)
	pc.add_theme_stylebox_override("panel", _card_style(c, false))
	pc.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	pc.add_child(v)

	# producto en 3D, girando en su propio mundo
	var svc := SubViewportContainer.new()
	svc.custom_minimum_size = Vector2(232, 150)
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(svc)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.size = Vector2i(232, 150)
	svc.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(1, 1, 1)
	env.environment.ambient_light_energy = 0.6
	env.environment.glow_enabled = true
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 30, 0)
	vp.add_child(sun)
	var rim := OmniLight3D.new()
	rim.light_color = c
	rim.light_energy = 2.0
	rim.position = Vector3(-0.3, 0.2, -0.3)
	vp.add_child(rim)
	var item := item_model(id)
	vp.add_child(item)
	var cam := Camera3D.new()
	cam.fov = 30.0
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0, 0.12, 0.75), Vector3(0, 0.0, 0))

	var name_l := _lbl(v, str(it["name"]).to_upper(), 30, Color(1, 1, 1), font_num, 6)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var price := _lbl(v, "%s puntos" % HudScript.thousands(int(it["price"])), 20, GOLD, font_num, 4)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var desc := _lbl(v, str(it["desc"]), 15, Color(0.85, 0.87, 0.85), font_ui, 0)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.custom_minimum_size.y = 66

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 46)
	btn.add_theme_font_override("font", font_num)
	btn.add_theme_font_size_override("font_size", 20)
	btn.focus_mode = Control.FOCUS_NONE
	var n := StyleBoxFlat.new()
	n.bg_color = c.darkened(0.55)
	n.set_corner_radius_all(8)
	var h: StyleBoxFlat = n.duplicate()
	h.bg_color = c.darkened(0.25)
	var dis: StyleBoxFlat = n.duplicate()
	dis.bg_color = Color(0.15, 0.15, 0.15, 0.9)
	btn.add_theme_stylebox_override("normal", n)
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", h)
	btn.add_theme_stylebox_override("disabled", dis)
	btn.add_theme_color_override("font_color", Color(1, 1, 1))
	btn.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.45))
	btn.pressed.connect(func(): _buy(id))
	v.add_child(btn)

	pc.mouse_entered.connect(func():
		pc.add_theme_stylebox_override("panel", _card_style(c, true))
		pc.pivot_offset = pc.size / 2.0
		create_tween().tween_property(pc, "scale", Vector2.ONE * 1.03, 0.1))
	pc.mouse_exited.connect(func():
		pc.add_theme_stylebox_override("panel", _card_style(c, false))
		create_tween().tween_property(pc, "scale", Vector2.ONE, 0.1))
	cards[id] = {"panel": pc, "btn": btn, "key": key, "item": item}


# Modelos 3D de los productos (centrados en el origen)
static func item_model(id: String) -> Node3D:
	var n := Node3D.new()
	match id:
		"porro":
			var j := Node3D.new()
			j.rotation_degrees = Vector3(0, 0, 70.0)
			n.add_child(j)
			U.cone(j, 0.028, 0.016, 0.3, Vector3(0, 0.0, 0), Color(0.96, 0.94, 0.89))
			U.cylinder(j, 0.013, 0.05, Vector3(0, -0.15, 0), Color(0.82, 0.72, 0.52))     # filtro
			var tip := U.sphere(j, 0.03, Vector3(0, 0.155, 0), Color(1.0, 0.4, 0.05), true)
			tip.material_override.emission_energy_multiplier = 4.0
			for i in 4:                                                                  # humito
				var s := U.sphere(n, 0.035 + i * 0.012, Vector3(0.13 + sin(i * 1.3) * 0.03, 0.08 + i * 0.07, 0), Color(0.9, 0.92, 0.9))
				s.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				s.material_override.albedo_color.a = 0.35 - i * 0.07
		"cafe":
			U.cylinder(n, 0.13, 0.015, Vector3(0, -0.1, 0), Color(0.96, 0.96, 0.95))      # platito
			U.cone(n, 0.075, 0.06, 0.13, Vector3(0, -0.025, 0), Color(0.97, 0.97, 0.96))  # taza
			U.cylinder(n, 0.07, 0.005, Vector3(0, 0.038, 0), Color(0.3, 0.17, 0.08))      # café
			var handle := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.025
			tm.outer_radius = 0.038
			handle.mesh = tm
			handle.material_override = U.mat(Color(0.97, 0.97, 0.96))
			handle.position = Vector3(0.08, -0.02, 0)
			handle.rotation_degrees = Vector3(90, 0, 0)
			n.add_child(handle)
			for i in 3:                                                                  # vapor
				var s := U.ellipsoid(n, Vector3(0.015, 0.05, 0.015), Vector3(-0.03 + i * 0.03, 0.1 + (i % 2) * 0.03, 0), Color(1, 1, 1))
				s.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				s.material_override.albedo_color.a = 0.3
		"gta":
			var b := Node3D.new()
			b.rotation_degrees.x = -8.0
			n.add_child(b)
			U.box(b, Vector3(0.2, 0.27, 0.03), Vector3.ZERO, Color(0.1, 0.1, 0.12))
			U.box(b, Vector3(0.19, 0.13, 0.002), Vector3(0, 0.06, 0.016), Color(0.95, 0.35, 0.6), true)
			U.box(b, Vector3(0.19, 0.12, 0.002), Vector3(0, -0.065, 0.016), Color(0.45, 0.2, 0.75), true)
			var gl := Label3D.new()
			gl.text = "GTA\nVI"
			gl.font_size = 64
			gl.pixel_size = 0.0018
			gl.outline_size = 10
			gl.outline_modulate = Color(0.1, 0.05, 0.15)
			gl.position = Vector3(0, 0.0, 0.019)
			b.add_child(gl)
	return n


func _refresh() -> void:
	points_lbl.text = HudScript.thousands(game.points)
	for id in cards:
		var c: Dictionary = cards[id]
		var st: String = tienda.status(id)
		var btn: Button = c["btn"]
		btn.disabled = st != ""
		btn.text = ("COMPRAR   [%d]" % c["key"]) if st == "" else st


func _buy(id: String) -> void:
	var ok: bool = tienda.status(id) == ""
	quote.text = "Juan Carlos:  «%s»" % tienda.buy(id)
	if ok:
		snd_buy.play()
		var pc: PanelContainer = cards[id]["panel"]
		pc.pivot_offset = pc.size / 2.0
		var tw := create_tween()
		tw.tween_property(pc, "scale", Vector2.ONE * 1.08, 0.08)
		tw.tween_property(pc, "scale", Vector2.ONE, 0.2)
	else:
		snd_no.play()
	_refresh()


func _input(event: InputEvent) -> void:
	if closing:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_E, KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				call_deferred("close")
			KEY_1, KEY_2, KEY_3:
				var k: int = event.keycode - KEY_0
				for id in cards:
					if cards[id]["key"] == k:
						_buy(id)


func _process(delta: float) -> void:
	t += delta
	for id in cards:
		var it: Node3D = cards[id]["item"]
		it.rotation.y = t * 0.9
		it.position.y = sin(t * 2.0 + cards[id]["key"]) * 0.01
	_refresh()
	_center()
	var p = game.player
	if p.dead or p.downed:
		close()


func _center() -> void:
	var vs := get_viewport().get_visible_rect().size
	panel.position = (vs - panel.size) / 2.0


func close() -> void:
	if closing:
		return
	closing = true
	game.player.input_blocked = false
	if paused_it:
		get_tree().paused = false
	if not game.player.dead:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	game.e_prev = true          # que la E de cerrar no vuelva a abrir la tienda
	tienda.menu_closed()
	var tw := create_tween().set_parallel()
	tw.tween_property(panel, "modulate:a", 0.0, 0.12)
	tw.tween_property(panel, "scale", Vector2.ONE * 0.95, 0.12)
	tw.chain().tween_callback(queue_free)


extends CanvasLayer
# HUD de la partida, minimalista: sin placas ni marcos, solo números y líneas finas
# pegados a las esquinas (Bebas Neue para los números, Barlow Condensed para textos).
#   arriba izq.  puntos (con "+60" que salen volando) y, en pequeño, bajas y la caja
#   abajo izq.   oleada en rojo, bebidas, y una línea fina de vida (y otra de aguante)
#   abajo der.   munición, nombre del arma, granadas Jan y una línea de recarga
#   centro       mira pequeña con marcador de impacto, avisos y mensajes
#   con poca vida los bordes de la pantalla laten en rojo
# main.gd sigue escribiendo en msg / prompt / small_lbl / dmg_rect como antes.

const W = preload("res://scripts/jugador/weapons.gd")

const GOLD := Color(1.0, 0.82, 0.36)
const RED := Color(0.86, 0.08, 0.08)
const BLOOD := Color(0.55, 0.02, 0.03)
const MUTED := Color(0.86, 0.86, 0.9, 0.72)
const PLATE := Color(0.03, 0.03, 0.045, 0.78)
const SKEW := 14.0                  # cuánto se inclinan las placas (px)

const F_NUM := "res://fuentes/BebasNeue-Regular.ttf"
const F_UI := "res://fuentes/BarlowCondensed-SemiBold.ttf"
const F_UI_BOLD := "res://fuentes/BarlowCondensed-Bold.ttf"

var game
var font_num: Font             # números grandes
var font_ui: Font              # textos
var font_bold: Font

# piezas que usa main.gd
var msg: Label
var prompt: Label               # main escribe aquí; se enseña en la "pastilla"
var small_lbl: Label
var dmg_rect: ColorRect

var points_lbl: Label
var pts_plate: Control
var stam_bar: Control
var info_lbl: Label
var mates_box: VBoxContainer
var round_lbl: Label
var round_cap: Label
var hp_bar: Control
var hp_lbl: Label
var perks_box: HBoxContainer
var wpn_plate: Control
var wpn_name: Label
var mag_lbl: Label
var res_lbl: Label
var dmg_lbl: Label
var pips: Control
var jan_box: Control
var pill: PanelContainer
var pill_text: RichTextLabel
var hint: RichTextLabel
var cross: Crosshair
var low_rect: ColorRect
var tele: Control           # pantalla de la mira telescópica

var shown_points := 0.0
var last_points := -1
var last_kills := 0
var last_wave := 0
var hp_shown := 100.0
var hp_lag := 100.0             # tramo blanco que se queda atrás al recibir daño
var perks_key := ""
var mates_key := ""
var t := 0.0


# Mira dibujada a mano: cuatro rayitas con hueco y una X al acertar
class Crosshair extends Control:
	var hit_t := 0.0
	var kill := false

	func _process(delta: float) -> void:
		hit_t = maxf(0.0, hit_t - delta)
		queue_redraw()

	func _draw() -> void:
		var c := (size / 2.0).round()
		var gap := 3.0
		var ln := 4.0
		for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			draw_line(c + d * gap, c + d * (gap + ln), Color(0, 0, 0, 0.3), 2.5)
			draw_line(c + d * gap, c + d * (gap + ln), Color(1, 1, 1, 0.75), 1.2)
		draw_circle(c, 1.0, Color(1, 1, 1, 0.8))
		if hit_t > 0.0:
			var a := hit_t / 0.25
			var col := Color(1.0, 0.25, 0.2, a) if kill else Color(1, 1, 1, a * 0.9)
			var r0 := 6.0
			var r1 := (11.0 if kill else 9.0) + (1.0 - a) * 2.0
			for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				var n: Vector2 = d.normalized()
				draw_line(c + n * r0, c + n * r1, col, 2.0 if kill else 1.5)


func _ready() -> void:
	layer = 1
	font_num = fuente(F_NUM)
	font_ui = fuente(F_UI)
	font_bold = fuente(F_UI_BOLD)

	# viñeta roja en los bordes al recibir daño (main pone la intensidad en color.a)
	dmg_rect = _vineta(Color(0.75, 0.0, 0.02))
	# latido rojo cuando te queda poca vida
	low_rect = _vineta(Color(0.55, 0.0, 0.0))

	# mira telescópica del francotirador (al apuntar)
	tele = Control.new()
	tele.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tele.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tele.visible = false
	tele.draw.connect(_draw_tele)
	add_child(tele)

	_build_top_left()
	_build_bottom_left()
	_build_bottom_right()
	_build_center()


# Fuente de la carpeta fuentes/ (si faltase, la del sistema)
static func fuente(ruta: String) -> Font:
	if ResourceLoader.exists(ruta):
		return load(ruta)
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Impact", "Arial Black", "Arial"] if ruta == F_NUM else ["Segoe UI", "Arial"])
	return f


func _vineta(col: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(1, 1, 1, 0)
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vm := ShaderMaterial.new()
	vm.shader = Shader.new()
	vm.shader.code = """
shader_type canvas_item;
uniform vec3 tinte = vec3(0.75, 0.0, 0.02);
void fragment() {
	float d = distance(UV, vec2(0.5)) * 1.41;
	float v = smoothstep(0.45, 1.0, d);
	COLOR = vec4(tinte, clamp(COLOR.a * 2.2, 0.0, 1.0) * v);
}
"""
	vm.set_shader_parameter("tinte", Vector3(col.r, col.g, col.b))
	r.material = vm
	add_child(r)
	return r


# ---------------- construcción ----------------
func _lbl(parent: Node, size: int, col: Color, font: Font = null, outline := 6) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", outline)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_font_override("font", font if font != null else font_ui)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


# Ancla un contenedor vacío a una esquina, desplazado pos píxeles
func _anchor(c: Control, preset: int, pos: Vector2) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = pos.x
	c.offset_right = pos.x
	c.offset_top = pos.y
	c.offset_bottom = pos.y


func _ctrl(parent: Node, pos: Vector2, sz: Vector2, dibujo: Callable) -> Control:
	var c := Control.new()
	c.position = pos
	c.size = sz
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(dibujo.bind(c))
	parent.add_child(c)
	return c


# Panel oscuro para los demás menús y avisos (consola, misión, pádel, bebidas...)
static func panel_style(alpha := 0.55) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.02, 0.02, 0.025, alpha * 0.6)
	s.set_border_width_all(0)
	s.set_corner_radius_all(4)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


# Placa inclinada con degradado (de opaco a la izquierda a transparente a la derecha)
static func placa(c: CanvasItem, r: Rect2, col: Color, acento: Color, hacia_izq := false) -> void:
	var k := SKEW
	var pts := PackedVector2Array([
		r.position + Vector2(k, 0), r.position + Vector2(r.size.x, 0),
		r.position + Vector2(r.size.x - k, r.size.y), r.position + Vector2(0, r.size.y)])
	var fin := Color(col.r, col.g, col.b, col.a * 0.15)
	var cols := PackedColorArray([col, fin, fin, col])
	if hacia_izq:
		cols = PackedColorArray([fin, col, col, fin])
	c.draw_polygon(pts, cols)
	# raya de color en el borde
	var a0 := pts[0] if not hacia_izq else pts[1]
	var a1 := pts[3] if not hacia_izq else pts[2]
	var dx := Vector2(4, 0) if not hacia_izq else Vector2(-4, 0)
	c.draw_colored_polygon(PackedVector2Array([a0, a0 + dx, a1 + dx, a1]), acento)


func _build_top_left() -> void:
	var root := Control.new()
	root.position = Vector2(20, 14)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	points_lbl = _sombra(_lbl(root, 26, Color(1.0, 0.9, 0.62, 0.9), font_num, 0))
	info_lbl = _sombra(_lbl(root, 13, Color(1, 1, 1, 0.42), font_ui, 0))
	info_lbl.position = Vector2(1, 28)
	mates_box = VBoxContainer.new()
	mates_box.position = Vector2(1, 48)
	mates_box.add_theme_constant_override("separation", 0)
	root.add_child(mates_box)


# Sin contorno: solo una sombra suave para que se lea sobre cualquier fondo
func _sombra(l: Label) -> Label:
	l.add_theme_constant_override("outline_size", 0)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.add_theme_constant_override("shadow_outline_size", 6)
	return l


func _build_bottom_left() -> void:
	var root := Control.new()
	_anchor(root, Control.PRESET_BOTTOM_LEFT, Vector2(20, -104))
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	round_cap = Label.new()        # ya no se enseña ("OLEADA" sobra)
	round_cap.visible = false
	root.add_child(round_cap)
	round_lbl = _sombra(_lbl(root, 40, Color(RED, 0.9), font_num, 0))
	round_lbl.position = Vector2(-1, 0)
	round_lbl.pivot_offset = Vector2(12, 26)
	# habilidades de la tienda (con tiempo), encima de la oleada
	perks_box = HBoxContainer.new()
	perks_box.position = Vector2(0, -14)
	perks_box.add_theme_constant_override("separation", 12)
	root.add_child(perks_box)
	# las bebidas (bebidas.gd) van en una fila entre la oleada y la vida
	# vida: una línea fina con el número al lado
	hp_bar = _ctrl(root, Vector2(0, 78), Vector2(140, 2), func(_c: Control): _draw_hp())
	hp_lbl = _sombra(_lbl(root, 12, Color(1, 1, 1, 0.6), font_ui, 0))
	hp_lbl.position = Vector2(150, 70)
	stam_bar = _ctrl(root, Vector2(0, 83), Vector2(140, 1), func(_c: Control): _draw_stamina())


func _build_bottom_right() -> void:
	var root := Control.new()
	_anchor(root, Control.PRESET_BOTTOM_RIGHT, Vector2(-20, -16))
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	wpn_name = _sombra(_lbl(root, 11, Color(1, 1, 1, 0.45), font_bold, 0))
	wpn_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wpn_name.position = Vector2(-250, -50)
	wpn_name.size = Vector2(250, 14)
	mag_lbl = _sombra(_lbl(root, 30, Color(1, 1, 1, 0.88), font_num, 0))
	mag_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mag_lbl.position = Vector2(-250, -40)
	mag_lbl.size = Vector2(214, 36)
	res_lbl = _sombra(_lbl(root, 16, Color(1, 1, 1, 0.4), font_num, 0))
	res_lbl.position = Vector2(-34, -25)
	dmg_lbl = Label.new()          # el daño ya no se enseña
	dmg_lbl.visible = false
	root.add_child(dmg_lbl)
	# línea fina: balas que quedan en el cargador o progreso de la recarga
	pips = _ctrl(root, Vector2(-110, -3), Vector2(110, 1), func(_c: Control): _draw_pips())
	# granadas Jan: cuatro puntitos a la izquierda de la línea de munición
	jan_box = _ctrl(root, Vector2(-150, -12), Vector2(36, 18), func(_c: Control): _draw_jan())


func _build_center() -> void:
	cross = Crosshair.new()
	cross.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cross)

	msg = _sombra(_lbl(self, 30, Color(1, 1, 1, 0.92), font_num, 0))
	msg.add_theme_constant_override("shadow_outline_size", 10)
	msg.add_theme_constant_override("line_spacing", -2)
	msg.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	msg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	msg.offset_bottom = -330.0
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg.add_theme_constant_override("line_spacing", -6)

	small_lbl = _sombra(_lbl(self, 15, Color(0.88, 0.94, 1.0, 0.85), font_ui, 0))
	small_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	small_lbl.offset_top = 80.0
	small_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	small_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# aviso de interacción: pastilla oscura con la tecla dibujada
	prompt = Label.new()           # solo guarda el texto (no se ve)
	prompt.visible = false
	add_child(prompt)
	pill = PanelContainer.new()
	var ps := StyleBoxEmpty.new()
	pill.add_theme_stylebox_override("panel", ps)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.visible = false
	add_child(pill)
	pill_text = RichTextLabel.new()
	pill_text.bbcode_enabled = true
	pill_text.fit_content = true
	pill_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	pill_text.scroll_active = false
	pill_text.add_theme_font_override("normal_font", font_ui)
	pill_text.add_theme_font_override("bold_font", font_bold)
	pill_text.add_theme_font_size_override("normal_font_size", 15)
	pill_text.add_theme_font_size_override("bold_font_size", 15)
	pill_text.add_theme_color_override("default_color", Color(1, 1, 1, 0.8))
	pill_text.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	pill_text.add_theme_constant_override("shadow_outline_size", 6)
	pill_text.add_theme_constant_override("shadow_offset_y", 1)
	pill_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(pill_text)

	# chuleta de controles: solo al principio, luego se va
	hint = RichTextLabel.new()
	hint.bbcode_enabled = true
	hint.fit_content = true
	hint.scroll_active = false
	hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	hint.add_theme_font_override("normal_font", font_ui)
	hint.add_theme_font_override("bold_font", font_bold)
	hint.add_theme_font_size_override("normal_font_size", 12)
	hint.add_theme_font_size_override("bold_font_size", 12)
	hint.add_theme_color_override("default_color", Color(1, 1, 1, 0.35))
	hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	hint.add_theme_constant_override("shadow_outline_size", 5)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var teclas := [["WASD", "mover"], ["Shift", "correr"], ["Clic", "disparar"], ["Clic der.", "apuntar"], ["R", "recargar"],
		["1-3", "armas"], ["4", "Jan"], ["E", "usar"], ["F", "linterna"], ["V", "cámara"],
		["F8", "cámara libre"], ["º", "consola"], ["Esc", "pausa"]]
	if _hay_mando():
		teclas = [["RT", "disparar"], ["LT", "apuntar"], ["L3", "correr"], ["A", "usar"], ["X", "recargar"], ["Y", "cambiar arma"],
			["B", "katana"], ["LB", "Jan"], ["R3", "linterna"], ["Select", "cámara"], ["Start", "pausa"]]
	var txt := "[center]"
	for k in teclas:
		txt += _tecla(k[0]) + " " + k[1] + "   "
	hint.text = txt.strip_edges() + "[/center]"
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -22.0
	hint.offset_bottom = -6.0
	hint.offset_left = 120.0
	hint.offset_right = -120.0
	add_child(hint)
	var tw := hint.create_tween()
	tw.tween_interval(8.0)
	tw.tween_property(hint, "modulate:a", 0.0, 1.5)


static func _tecla(k: String) -> String:
	return "[color=#ffffffcc][b]%s[/b][/color]" % k


# ---------------- dibujo ----------------
# Vida: línea fina blanca (roja con poca vida) y el daño reciente en rojo oscuro
func _draw_hp() -> void:
	var p = game.player
	var maxv: float = p.max_hp if p != null else 100.0
	var w := hp_bar.size.x * clampf(maxv / 100.0, 1.0, 1.6)
	var h := hp_bar.size.y
	hp_bar.draw_rect(Rect2(0, 0, w, h), Color(1, 1, 1, 0.14))
	var a := clampf(hp_lag / maxv, 0.0, 1.0)
	var b := clampf(hp_shown / maxv, 0.0, 1.0)
	hp_bar.draw_rect(Rect2(0, 0, w * a, h), Color(0.75, 0.1, 0.1, 0.8))
	var col := Color(1, 1, 1, 0.92)
	if b < 0.35:
		col = Color(1.0, 0.25, 0.2).lerp(Color(1, 0.6, 0.55), (sin(t * 9.0) * 0.5 + 0.5) * 0.5)
	hp_bar.draw_rect(Rect2(0, 0, w * b, h), col)
	hp_lbl.position.x = w + 10.0


# Mira telescópica: todo negro menos un círculo, con su retícula fina
func _draw_tele() -> void:
	var s := tele.size
	var c := s / 2.0
	var r := minf(s.x, s.y) * 0.46
	var lejos := c.length() - r + 4.0
	tele.draw_arc(c, r + lejos / 2.0, 0.0, TAU, 128, Color(0, 0, 0, 1), lejos, true)
	tele.draw_arc(c, r + 2.0, 0.0, TAU, 128, Color(0.05, 0.05, 0.05, 1), 6.0, true)
	var ret := Color(0, 0, 0, 0.85)
	tele.draw_line(Vector2(c.x - r, c.y), Vector2(c.x + r, c.y), ret, 1.0)
	tele.draw_line(Vector2(c.x, c.y - r), Vector2(c.x, c.y + r), ret, 1.0)
	tele.draw_line(Vector2(c.x - r, c.y), Vector2(c.x - r * 0.15, c.y), ret, 3.0)
	tele.draw_line(Vector2(c.x + r * 0.15, c.y), Vector2(c.x + r, c.y), ret, 3.0)
	tele.draw_line(Vector2(c.x, c.y + r * 0.15), Vector2(c.x, c.y + r), ret, 3.0)
	tele.draw_circle(c, 1.5, Color(1.0, 0.2, 0.15, 0.9))


# Aguante del sprint: solo se ve cuando no está lleno
func _draw_stamina() -> void:
	var p = game.player
	if p == null or p.stamina >= 1.0:
		return
	var w := stam_bar.size.x
	stam_bar.draw_rect(Rect2(0, 0, w, stam_bar.size.y), Color(1, 1, 1, 0.1))
	stam_bar.draw_rect(Rect2(0, 0, w * p.stamina, stam_bar.size.y), Color(1.0, 0.35, 0.3, 0.9) if p.tired else Color(1.0, 0.88, 0.55, 0.8))


# Línea de munición del cargador, o de recarga mientras recargas
func _draw_pips() -> void:
	var p = game.player
	if p == null or p.cur > 1 or p.slots[p.cur] == null:
		return
	var s: Dictionary = p.slots[p.cur]
	var d: Dictionary = W.DATA[s["id"]]
	var w := pips.size.x
	var h := pips.size.y
	pips.draw_rect(Rect2(0, 0, w, h), Color(1, 1, 1, 0.12))
	if p.reload_t > 0.0:
		var total: float = d["reload"]
		if p.cafe_t > 0.0:
			total *= p.CAFE_RELOAD
		if p.has_method("has_perk") and p.has_perk("rapida"):
			total *= 0.5
		var k := 1.0 - clampf(p.reload_t / total, 0.0, 1.0)
		pips.draw_rect(Rect2(0, 0, w * k, h), GOLD)
		return
	var f := clampf(float(s["mag"]) / float(d["mag"]), 0.0, 1.0)
	var low := f <= 0.25
	pips.draw_rect(Rect2(w * (1.0 - f), 0, w * f, h), Color(1.0, 0.35, 0.28) if low else Color(1, 1, 1, 0.75))


# Granadas Jan: puntitos (llenos los que tienes)
func _draw_jan() -> void:
	var p = game.player
	if p == null:
		return
	var y := jan_box.size.y / 2.0
	for i in p.JAN_MAX:
		var c := Vector2(3 + i * 8, y)
		if i < p.jan_count:
			jan_box.draw_circle(c, 2.2, Color(GOLD, 0.8))
		else:
			jan_box.draw_arc(c, 2.0, 0, TAU, 10, Color(1, 1, 1, 0.25), 1.0)


# ---------------- avisos que llama main ----------------
func hit(killed := false) -> void:
	cross.hit_t = 0.25
	cross.kill = killed


func _popup(text: String, col: Color) -> void:
	var l := _sombra(_lbl(self, 16, col, font_num, 0))
	l.text = text
	l.position = points_lbl.global_position + Vector2(points_lbl.size.x + 8 + randf_range(0, 12), 4 + randf_range(-3, 3))
	var tw := l.create_tween().set_parallel()
	tw.tween_property(l, "position", l.position + Vector2(randf_range(30, 60), -26), 0.9).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.3)
	tw.chain().tween_callback(l.queue_free)


func _perk(text: String, col: Color, k: float) -> void:
	var l := _sombra(_lbl(perks_box, 11, col.lightened(0.3), font_bold, 0))
	l.text = "● " + text
	l.modulate.a = 0.55 + 0.45 * k


# ---------------- actualizar cada fotograma ----------------
func _process(delta: float) -> void:
	t += delta
	var p = game.player
	if p == null:
		return
	var vs: bool = Net.mode == "versus"

	# puntos que suben/bajan poco a poco, y "+N" / "-N" al cambiar
	if last_points < 0:
		last_points = game.points
		shown_points = game.points
	var diff: int = game.points - last_points
	if diff != 0:
		_popup(("+%d" % diff) if diff > 0 else ("-%d" % -diff), GOLD if diff > 0 else Color(1.0, 0.35, 0.3))
		last_points = game.points
	shown_points = move_toward(shown_points, game.points, maxf(40.0, absf(game.points - shown_points) * 8.0) * delta)
	points_lbl.text = thousands(int(round(shown_points)))
	if game.kills > last_kills:
		hit(true)
	last_kills = game.kills

	# bajas / caja / compañeros (o la tabla del todos contra todos)
	if vs:
		var lead := 1
		for id in game.vs_kills:
			if game.vs_kills[id] > game.vs_kills.get(lead, -1):
				lead = id
		info_lbl.text = "Bajas %d  ·  Muertes %d\nLíder: %s (%d/%d)" % [game.vs_kills.get(Net.my_id(), 0),
			game.vs_deaths.get(Net.my_id(), 0), Net.pname(lead), game.vs_kills.get(lead, 0), game.VS_GOAL]
	else:
		var caja := "Caja: " + str(game.box_spots[game.box_spot][2])
		if game.box_state >= 3:
			caja = "Caja: cambiando de sala..."
		info_lbl.text = "%d bajas  ·  %s" % [game.kills, caja.to_lower()]
	_mates()

	# oleada: número grande que late al cambiar
	round_lbl.visible = not vs
	round_cap.visible = not vs
	if game.wave != last_wave:
		last_wave = game.wave
		round_lbl.text = str(game.wave)
		round_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
		var tw := round_lbl.create_tween()
		tw.tween_property(round_lbl, "scale", Vector2.ONE * 1.35, 0.15)
		tw.tween_property(round_lbl, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(round_lbl, "theme_override_colors/font_color", RED, 1.2)

	# vida
	hp_shown = lerpf(hp_shown, p.hp, minf(1.0, 12.0 * delta))
	if p.hp >= hp_lag:
		hp_lag = hp_shown
	else:
		hp_lag = move_toward(hp_lag, p.hp, 40.0 * delta)
	hp_bar.queue_redraw()
	hp_lbl.text = "%d" % int(ceil(p.hp))
	stam_bar.queue_redraw()
	# latido rojo con poca vida
	var kv: float = clampf(p.hp / maxf(1.0, p.max_hp), 0.0, 1.0)
	var low := 0.0
	if kv < 0.35 and not p.dead:
		var beat := pow(maxf(0.0, sin(t * 7.5)), 6.0)
		low = (0.35 - kv) / 0.35 * (0.25 + 0.35 * beat)
	low_rect.color.a = lerpf(low_rect.color.a, low, minf(1.0, 10.0 * delta))

	# habilidades de la tienda de Juan Carlos
	var key := "%d|%d|%s" % [ceili(p.porro_t), ceili(p.cafe_t), p.has_gta]
	if key != perks_key:
		perks_key = key
		for c in perks_box.get_children():
			c.queue_free()
		if p.porro_t > 0.0:
			_perk("COLOCÓN %ds" % ceili(p.porro_t), Color(0.35, 0.9, 0.35), clampf(p.porro_t / 5.0, 0.0, 1.0))
		if p.cafe_t > 0.0:
			_perk("CAFÉ %ds" % ceili(p.cafe_t), Color(0.85, 0.6, 0.35), clampf(p.cafe_t / 5.0, 0.0, 1.0))
		if p.has_gta:
			_perk("GTA VI", Color(1.0, 0.4, 0.75), 1.0)

	_weapon(p)
	# apuntando: la mira normal se va; con francotirador sale la pantalla de la mira
	var ads: float = p.ads_k if "ads_k" in p else 0.0
	cross.modulate.a = 1.0 - clampf(ads * 1.6, 0.0, 1.0)
	var tel := false
	if ads > 0.85 and p.cur < 2 and p.slots[p.cur] != null and not p.third_person:
		tel = W.DATA[p.slots[p.cur]["id"]].get("scope", false)
	if tel != tele.visible:
		tele.visible = tel
		tele.queue_redraw()

	# aviso de interacción (el de main o el de la misión)
	var tx: String = prompt.text
	if tx == "" and game.mission != null and is_instance_valid(game.mission):
		tx = game.mission.prompt.text
	pill.visible = tx != "" and not game.hacking
	if pill.visible:
		pill_text.text = _keycaps(tx)
		pill.reset_size()
		var vp := get_viewport().get_visible_rect().size
		pill.position = Vector2(round((vp.x - pill.size.x) / 2.0), round(vp.y * 0.5 + 46.0))

	# Jesús te ha hackeado: los números se vuelven locos
	if game.hacking:
		points_lbl.text = "%X" % randi()
		info_lbl.text = ["ERROR 0x%04X" % (randi() % 65535), "J3SUS.EXE", "ACCESO DENEGADO"].pick_random()
		round_lbl.text = str(randi() % 100)
	elif round_lbl.text != str(game.wave):
		round_lbl.text = str(game.wave)


func _weapon(p) -> void:
	var cur: int = p.cur
	if cur == 3:
		wpn_name.text = "GRANADA JAN"
		mag_lbl.text = str(p.jan_count)
		res_lbl.text = ""
		dmg_lbl.text = "Mantén clic y suelta para lanzar"
		mag_lbl.add_theme_color_override("font_color", GOLD)
	elif cur == 2 or p.slots[cur] == null:
		wpn_name.text = "KATANA"
		mag_lbl.text = "∞"
		res_lbl.text = ""
		dmg_lbl.text = "Daño 4 · golpe en abanico"
		mag_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	else:
		var s: Dictionary = p.slots[cur]
		var d: Dictionary = W.DATA[s["id"]]
		wpn_name.text = str(d["name"]).to_upper()
		mag_lbl.text = str(s["mag"])
		res_lbl.text = "/%d" % s["reserve"]
		dmg_lbl.text = W.damage_text(s["id"]) + ("   ·   RECARGANDO" if p.reload_t > 0.0 else "")
		var low: bool = s["mag"] <= int(d["mag"]) / 4
		mag_lbl.add_theme_color_override("font_color", Color(1.0, 0.3, 0.25) if low else Color(1, 1, 1))
	pips.queue_redraw()
	jan_box.queue_redraw()


func _mates() -> void:
	if not Net.online or Net.mode == "versus":
		return
	var key := ""
	for id in game.players:
		var m = game.players[id]
		if is_instance_valid(m):
			key += "%d:%d:%s:%s;" % [id, int(m.hp), m.downed, m.dead]
	if key == mates_key:
		return
	mates_key = key
	for c in mates_box.get_children():
		c.queue_free()
	for id in game.players:
		var m = game.players[id]
		if m == game.player or not is_instance_valid(m):
			continue
		var st := "%d" % int(m.hp)
		var col := Color(0.6, 1.0, 0.65, 0.9)
		if m.downed:
			st = "CAÍDO"
			col = Color(1.0, 0.75, 0.3)
		elif m.dead:
			st = "MUERTO"
			col = Color(1.0, 0.35, 0.3)
		var l := _lbl(mates_box, 17, col, font_ui, 4)
		l.text = "%s  ·  %s" % [Net.pname(id), st]


# "[E]" -> tecla dibujada
func _keycaps(tx: String) -> String:
	tx = tx.replace("[", "[lb]")
	tx = tx.replace("[lb]E]", "[color=#f2d26b][b]%s[/b][/color] " % ("A" if _hay_mando() else "E"))
	return "[center]" + tx + "[/center]"


static func _hay_mando() -> bool:
	return not Input.get_connected_joypads().is_empty()


static func thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "." + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out

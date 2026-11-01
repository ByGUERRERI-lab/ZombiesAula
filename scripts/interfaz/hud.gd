extends CanvasLayer
# HUD de la partida, estilo "zombies": limpio y pegado a las esquinas para no tapar.
#   arriba izq.  puntos (con "+60" que salen volando), bajas y dónde está la caja
#   abajo izq.   número de oleada grande en rojo, barra de vida y habilidades
#   abajo der.   arma, munición y granadas Jan
#   centro       mira con marcador de impacto, avisos y mensajes grandes
# main.gd sigue escribiendo en msg / prompt / small_lbl / dmg_rect como antes.

const W = preload("res://scripts/jugador/weapons.gd")

const GOLD := Color(1.0, 0.86, 0.45)
const RED := Color(0.78, 0.06, 0.06)
const MUTED := Color(0.85, 0.85, 0.88, 0.7)

var game
var font_num: SystemFont        # números grandes (Impact)
var font_ui: SystemFont         # textos (Segoe UI seminegrita)

# piezas que usa main.gd
var msg: Label
var prompt: Label               # main escribe aquí; se enseña en la "pastilla"
var small_lbl: Label
var dmg_rect: ColorRect

var points_lbl: Label
var stam_bar: Control
var info_lbl: Label
var mates_box: VBoxContainer
var round_lbl: Label
var round_cap: Label
var hp_bar: Control
var hp_lbl: Label
var perks_box: HBoxContainer
var wpn_name: Label
var mag_lbl: Label
var res_lbl: Label
var dmg_lbl: Label
var reload_bar: Control
var jan_lbl: Label
var pill: PanelContainer
var pill_text: RichTextLabel
var hint: Label
var cross: Crosshair

var shown_points := 0.0
var last_points := -1
var last_kills := 0
var last_wave := 0
var hp_shown := 100.0
var perks_key := ""
var mates_key := ""


# Mira dibujada a mano: cuatro rayitas con hueco y una X al acertar
class Crosshair extends Control:
	var hit_t := 0.0
	var kill := false

	func _process(delta: float) -> void:
		hit_t = maxf(0.0, hit_t - delta)
		queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		var gap := 6.0
		var ln := 8.0
		for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			draw_line(c + d * gap, c + d * (gap + ln), Color(0, 0, 0, 0.55), 4.0)
			draw_line(c + d * gap, c + d * (gap + ln), Color(1, 1, 1, 0.9), 2.0)
		draw_circle(c, 1.6, Color(1, 1, 1, 0.9))
		if hit_t > 0.0:
			var a := hit_t / 0.25
			var col := Color(1.0, 0.2, 0.15, a) if kill else Color(1, 1, 1, a)
			var r0 := 9.0
			var r1 := 17.0 if kill else 14.0
			for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				var n: Vector2 = d.normalized()
				draw_line(c + n * r0, c + n * r1, col, 3.0 if kill else 2.0)


func _ready() -> void:
	layer = 1
	font_num = SystemFont.new()
	font_num.font_names = PackedStringArray(["Impact", "Arial Black", "Arial"])
	font_ui = SystemFont.new()
	font_ui.font_names = PackedStringArray(["Segoe UI", "Arial", "DejaVu Sans"])
	font_ui.font_weight = 600

	# viñeta roja en los bordes al recibir daño (main pone la intensidad en color.a)
	dmg_rect = ColorRect.new()
	dmg_rect.color = Color(1, 1, 1, 0)
	dmg_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dmg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vm := ShaderMaterial.new()
	vm.shader = Shader.new()
	vm.shader.code = """
shader_type canvas_item;
void fragment() {
	float d = distance(UV, vec2(0.5)) * 1.41;
	float v = smoothstep(0.45, 1.0, d);
	COLOR = vec4(0.75, 0.0, 0.02, clamp(COLOR.a * 2.2, 0.0, 1.0) * v);
}
"""
	dmg_rect.material = vm
	add_child(dmg_rect)

	_build_top_left()
	_build_bottom_left()
	_build_bottom_right()
	_build_center()


# ---------------- construcción ----------------
func _lbl(parent: Node, size: int, col: Color, font: Font = null, outline := 6) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", outline)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
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


static func panel_style(alpha := 0.55) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.03, 0.03, 0.04, alpha)
	s.border_color = Color(1, 1, 1, 0.08)
	s.set_border_width_all(1)
	s.set_corner_radius_all(10)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


func _build_top_left() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(26, 16)
	box.add_theme_constant_override("separation", -4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var cap := _lbl(box, 13, MUTED, null, 4)
	cap.text = "P U N T O S"
	points_lbl = _lbl(box, 46, GOLD, font_num, 8)
	info_lbl = _lbl(box, 15, MUTED, null, 4)
	mates_box = VBoxContainer.new()
	mates_box.add_theme_constant_override("separation", 2)
	box.add_child(mates_box)


func _build_bottom_left() -> void:
	var root := Control.new()
	_anchor(root, Control.PRESET_BOTTOM_LEFT, Vector2(26, -150))
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	round_cap = _lbl(root, 13, Color(0.9, 0.5, 0.45, 0.85), null, 4)
	round_cap.text = "O L E A D A"
	round_cap.position = Vector2(4, 0)
	round_lbl = _lbl(root, 92, RED, font_num, 10)
	round_lbl.position = Vector2(0, 8)
	round_lbl.pivot_offset = Vector2(30, 60)
	# barra de vida al lado del número
	perks_box = HBoxContainer.new()
	perks_box.position = Vector2(118, 36)
	perks_box.add_theme_constant_override("separation", 6)
	root.add_child(perks_box)
	hp_bar = Control.new()
	hp_bar.position = Vector2(118, 74)
	hp_bar.custom_minimum_size = Vector2(250, 12)
	hp_bar.size = Vector2(250, 12)
	hp_bar.draw.connect(_draw_hp)
	root.add_child(hp_bar)
	hp_lbl = _lbl(root, 15, Color(1, 1, 1, 0.85), null, 4)
	hp_lbl.position = Vector2(118, 88)
	stam_bar = Control.new()
	stam_bar.position = Vector2(118, 112)
	stam_bar.size = Vector2(250, 6)
	stam_bar.draw.connect(_draw_stamina)
	root.add_child(stam_bar)


func _build_bottom_right() -> void:
	var root := Control.new()
	_anchor(root, Control.PRESET_BOTTOM_RIGHT, Vector2(-26, -26))
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	wpn_name = _lbl(root, 17, Color(1, 1, 1, 0.9), null, 4)
	wpn_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wpn_name.position = Vector2(-400, -128)
	wpn_name.size = Vector2(400, 24)
	mag_lbl = _lbl(root, 60, Color(1, 1, 1), font_num, 8)
	mag_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mag_lbl.position = Vector2(-400, -112)
	mag_lbl.size = Vector2(310, 70)
	res_lbl = _lbl(root, 28, MUTED, font_num, 6)
	res_lbl.position = Vector2(-84, -84)
	dmg_lbl = _lbl(root, 13, MUTED, null, 3)
	dmg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dmg_lbl.position = Vector2(-400, -40)
	dmg_lbl.size = Vector2(400, 18)
	reload_bar = Control.new()
	reload_bar.position = Vector2(-220, -46)
	reload_bar.size = Vector2(220, 4)
	reload_bar.draw.connect(_draw_reload)
	root.add_child(reload_bar)
	jan_lbl = _lbl(root, 15, GOLD, null, 4)
	jan_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	jan_lbl.position = Vector2(-400, -22)
	jan_lbl.size = Vector2(400, 20)


func _build_center() -> void:
	cross = Crosshair.new()
	cross.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cross)

	msg = _lbl(self, 46, Color(1, 1, 1), font_num, 12)
	msg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	msg.offset_bottom = -330.0
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	small_lbl = _lbl(self, 19, Color(0.75, 0.9, 1.0), null, 5)
	small_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	small_lbl.offset_top = 80.0
	small_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	small_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# aviso de interacción: pastilla oscura con la tecla dibujada
	prompt = Label.new()           # solo guarda el texto (no se ve)
	prompt.visible = false
	add_child(prompt)
	pill = PanelContainer.new()
	pill.add_theme_stylebox_override("panel", panel_style(0.6))
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.visible = false
	add_child(pill)
	pill_text = RichTextLabel.new()
	pill_text.bbcode_enabled = true
	pill_text.fit_content = true
	pill_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	pill_text.scroll_active = false
	pill_text.add_theme_font_override("normal_font", font_ui)
	pill_text.add_theme_font_size_override("normal_font_size", 19)
	pill_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(pill_text)

	# chuleta de controles: solo al principio, luego se va
	hint = _lbl(self, 13, Color(0.85, 0.85, 0.85, 0.75), null, 3)
	hint.text = "WASD mover · Shift correr · clic disparar · R recargar · 1/2/3 armas · 4 granada Jan · E usar · F linterna · V cámara · F3 gráficos · F8 cámara libre · Esc pausa"
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint.offset_top = -26.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var tw := hint.create_tween()
	tw.tween_interval(14.0)
	tw.tween_property(hint, "modulate:a", 0.0, 1.5)


# ---------------- dibujo de barras ----------------
func _draw_hp() -> void:
	var p = game.player
	var w := hp_bar.size.x
	var h := hp_bar.size.y
	var maxv: float = p.max_hp if p != null else 100.0
	var full := w * maxv / 100.0 * 0.8       # con 150 de vida la barra es más larga
	_round_rect(hp_bar, Rect2(0, 0, full, h), Color(0, 0, 0, 0.55))
	var k := clampf(hp_shown / maxv, 0.0, 1.0)
	var col := Color(0.9, 0.15, 0.12).lerp(Color(0.35, 0.95, 0.45), clampf((k - 0.2) / 0.6, 0.0, 1.0))
	if k > 0.0:
		_round_rect(hp_bar, Rect2(1, 1, (full - 2) * k, h - 2), col)
		hp_bar.draw_rect(Rect2(3, 2, maxf(0.0, (full - 6) * k), 2), Color(1, 1, 1, 0.25))


# Resistencia del sprint: solo se ve cuando no está llena
func _draw_stamina() -> void:
	var p = game.player
	if p == null or p.stamina >= 1.0:
		return
	var w := stam_bar.size.x
	stam_bar.draw_rect(Rect2(0, 0, w, 6), Color(0, 0, 0, 0.5))
	stam_bar.draw_rect(Rect2(0, 0, w * p.stamina, 6), Color(1.0, 0.35, 0.3) if p.tired else Color(0.95, 0.9, 0.55))


func _draw_reload() -> void:
	var p = game.player
	if p == null or p.reload_t <= 0.0 or p.cur > 1 or p.slots[p.cur] == null:
		return
	var total: float = W.DATA[p.slots[p.cur]["id"]]["reload"]
	if p.cafe_t > 0.0:
		total *= p.CAFE_RELOAD
	var k := 1.0 - clampf(p.reload_t / total, 0.0, 1.0)
	reload_bar.draw_rect(Rect2(Vector2.ZERO, reload_bar.size), Color(0, 0, 0, 0.5))
	reload_bar.draw_rect(Rect2(Vector2.ZERO, Vector2(reload_bar.size.x * k, reload_bar.size.y)), GOLD)


func _round_rect(c: Control, r: Rect2, col: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(r.size.y / 2.0))
	c.draw_style_box(sb, r)


# ---------------- avisos que llama main ----------------
func hit(killed := false) -> void:
	cross.hit_t = 0.25
	cross.kill = killed


func _popup(text: String, col: Color) -> void:
	var l := _lbl(self, 24, col, font_num, 6)
	l.text = text
	l.position = points_lbl.global_position + Vector2(points_lbl.size.x + 10 + randf_range(0, 20), 10 + randf_range(-6, 6))
	var tw := l.create_tween().set_parallel()
	tw.tween_property(l, "position", l.position + Vector2(randf_range(30, 60), -26), 0.9).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.3)
	tw.chain().tween_callback(l.queue_free)


func _perk(text: String, col: Color, k: float) -> void:
	var pc := PanelContainer.new()
	var sb := panel_style(0.6)
	sb.border_color = col
	sb.set_border_width_all(0)
	sb.border_width_bottom = 3
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	sb.set_corner_radius_all(6)
	pc.add_theme_stylebox_override("panel", sb)
	pc.modulate.a = 0.55 + 0.45 * k
	perks_box.add_child(pc)
	var l := _lbl(pc, 13, col.lightened(0.3), null, 0)
	l.text = text


# ---------------- actualizar cada fotograma ----------------
func _process(delta: float) -> void:
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
		info_lbl.text = "Bajas %d  ·  %s" % [game.kills, caja]
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
		tw.parallel().tween_method(func(v): round_lbl.add_theme_color_override("font_color", Color(1, 1, 1).lerp(RED, v)), 0.0, 1.0, 1.2)

	# vida
	hp_shown = lerpf(hp_shown, p.hp, minf(1.0, 10.0 * delta))
	hp_bar.queue_redraw()
	hp_lbl.text = "%d / %d" % [int(ceil(p.hp)), int(p.max_hp)]
	stam_bar.queue_redraw()

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

	# aviso de interacción (el de main o el de la misión)
	var t: String = prompt.text
	if t == "" and game.mission != null and is_instance_valid(game.mission):
		t = game.mission.prompt.text
	pill.visible = t != "" and not game.hacking
	if pill.visible:
		pill_text.text = _keycaps(t)
		pill.position.y = get_viewport().get_visible_rect().size.y - 225.0
		pill.position.x = (get_viewport().get_visible_rect().size.x - pill.size.x) / 2.0
		pill.reset_size()

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
	elif cur == 2 or p.slots[cur] == null:
		wpn_name.text = "KATANA"
		mag_lbl.text = "∞"
		res_lbl.text = ""
		dmg_lbl.text = "Daño 4 · golpe en abanico"
	else:
		var s: Dictionary = p.slots[cur]
		var d: Dictionary = W.DATA[s["id"]]
		wpn_name.text = str(d["name"]).to_upper()
		mag_lbl.text = str(s["mag"])
		res_lbl.text = "/ %d" % s["reserve"]
		dmg_lbl.text = W.damage_text(s["id"]) + ("   ·   RECARGANDO" if p.reload_t > 0.0 else "")
		var low: bool = s["mag"] <= int(d["mag"]) / 4
		mag_lbl.add_theme_color_override("font_color", Color(1.0, 0.3, 0.25) if low else Color(1, 1, 1))
	reload_bar.queue_redraw()
	var dots := ""
	for i in p.JAN_MAX:
		dots += "●" if i < p.jan_count else "○"
	jan_lbl.text = "JAN  %s   [4]" % dots


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
		var l := _lbl(mates_box, 15, col, null, 4)
		l.text = "%s  ·  %s" % [Net.pname(id), st]


# "[E]" -> tecla dibujada
func _keycaps(t: String) -> String:
	t = t.replace("[", "[lb]")
	t = t.replace("[lb]E]", "[bgcolor=#f2d977][color=#111111][b] E [/b][/color][/bgcolor]")
	return "[center]" + t + "[/center]"


static func thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "." + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out

extends CanvasLayer
# Menú del casino de Iván Muriel. Tres modos:
#   "slots"  tragaperras de 3 rodillos (Espacio para tirar)
#   "ruleta" ruleta europea: rojo/negro, par/impar, mitades, docenas o un número
#   "futbol" apuestas 1-X-2 al partido que echan en la tele
#   "quiz"   la pregunta de Iván: ¿Fabiana Sevillano o Lucía Bellido?
# Se apuesta con tus puntos. En solitario pausa la partida; en red solo
# bloquea tus controles. E o Esc para salir.

const U = preload("res://scripts/nucleo/util.gd")
const HudScript = preload("res://scripts/interfaz/hud.gd")

const GOLD := Color(1.0, 0.82, 0.35)
const BETS := [50, 100, 250, 500, 1000]
# [símbolo, color, premio por 3 iguales]
const SYMBOLS := [["7", Color(0.95, 0.1, 0.1), 25], ["★", Color(1.0, 0.8, 0.1), 10], ["BAR", Color(0.95, 0.95, 0.95), 6],
	["♥", Color(1.0, 0.35, 0.6), 4], ["♦", Color(0.3, 0.6, 1.0), 4], ["♣", Color(0.3, 0.9, 0.4), 4]]
const PAIR_PAY := 1.5        # dos iguales: recuperas 1,5 veces lo apostado
# orden de las casillas en la rueda europea
const WHEEL := [0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 11, 30, 8, 23, 10, 5, 24, 16, 33, 1, 20, 14,
	31, 9, 22, 18, 29, 7, 28, 12, 35, 3, 26]
const REDS := [1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36]
# apuestas de la ruleta: [id, texto, paga]
const RBETS := [["rojo", "ROJO", 2], ["negro", "NEGRO", 2], ["par", "PAR", 2], ["impar", "IMPAR", 2],
	["bajo", "1 - 18", 2], ["alto", "19 - 36", 2], ["d1", "1ª DOCENA", 3], ["d2", "2ª DOCENA", 3],
	["d3", "3ª DOCENA", 3], ["num", "NÚMERO", 36]]

var casino
var game
var mode := "slots"
var bet_amount := 100
var font_num: SystemFont
var font_ui: SystemFont
var panel: PanelContainer
var points_lbl: Label
var msg_lbl: Label
var bet_btns := {}
var busy := false            # girando: no se puede salir ni volver a apostar
var closing := false
var paused_it := false
var snd_tick: AudioStreamPlayer
var snd_win: AudioStreamPlayer
var snd_big: AudioStreamPlayer
var snd_lose: AudioStreamPlayer
# tragaperras
var reels: Array = []        # Label de cada rodillo
var reel_stop: Array = []    # tiempo en que para cada rodillo
var reel_res: Array = []     # símbolo final de cada rodillo
var spin_t := 0.0
var tick_t := 0.0
# ruleta
var wheel: WheelView
var rbet := "rojo"
var rnum := 17
var rbtns := {}
var num_lbl: Label
var result_lbl: Label
# fútbol
var odds_btns: Array = []
var fpick := 0
var finfo: Label


static func pocket_color(n: int) -> Color:
	return WheelView.pc(n)


# Rueda de la ruleta dibujada a mano: gira y la bola cae en la casilla ganadora
class WheelView extends Control:
	var angle := 0.0         # giro de la rueda
	var ball := -PI / 2.0    # ángulo de la bola (arriba = -PI/2)
	var ball_r := 1.0        # 1 = por fuera, 0 = dentro de la casilla
	var a0 := 0.0
	var a1 := 0.0
	var b0 := 0.0
	var b1 := 0.0
	var t := 0.0
	var dur := 0.0
	var font: Font

	# color de cada casilla: 0 verde, rojos y negros
	static func pc(n: int) -> Color:
		if n == 0:
			return Color(0.05, 0.55, 0.2)
		return Color(0.78, 0.08, 0.08) if n in REDS else Color(0.06, 0.06, 0.07)

	func spin(result: int, d: float) -> void:
		var step := TAU / 37.0
		var idx: int = WHEEL.find(result)
		a0 = fposmod(angle, TAU)
		# la casilla ganadora tiene que quedar arriba, debajo de la bola
		var target := -PI / 2.0 - (idx + 0.5) * step
		a1 = target - TAU * 4.0
		while a1 > a0 - TAU * 3.0:
			a1 -= TAU
		b0 = fposmod(ball, TAU)
		b1 = -PI / 2.0 + TAU * 6.0
		while b1 < b0 + TAU * 5.0:
			b1 += TAU
		t = 0.0
		dur = d

	func _process(delta: float) -> void:
		if t < dur:
			t = minf(dur, t + delta)
			var k := t / dur
			var e := 1.0 - pow(1.0 - k, 3.0)
			angle = lerpf(a0, a1, e)
			ball = lerpf(b0, b1, 1.0 - pow(1.0 - k, 2.2))
			ball_r = clampf((1.0 - k) * 2.5, 0.0, 1.0)
		queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		var R := minf(size.x, size.y) / 2.0 - 4.0
		var step := TAU / 37.0
		draw_circle(c, R + 4.0, Color(0.85, 0.65, 0.25))
		draw_circle(c, R, Color(0.3, 0.15, 0.05))
		for i in 37:
			var a := angle + i * step
			var pts := PackedVector2Array()
			for j in 5:
				var aa := a + step * j / 4.0
				pts.append(c + Vector2(cos(aa), sin(aa)) * (R - 6.0))
			for j in range(4, -1, -1):
				var aa := a + step * j / 4.0
				pts.append(c + Vector2(cos(aa), sin(aa)) * (R * 0.62))
			var n: int = WHEEL[i]
			draw_colored_polygon(pts, pc(n))
			draw_polyline(pts, Color(0.85, 0.65, 0.25, 0.6), 1.0)
			var mid := a + step / 2.0
			var tp := c + Vector2(cos(mid), sin(mid)) * (R * 0.8)
			draw_set_transform(tp, mid + PI / 2.0, Vector2.ONE)
			draw_string(font, Vector2(-8, 5), str(n), HORIZONTAL_ALIGNMENT_CENTER, 16, 12, Color(1, 1, 1))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_circle(c, R * 0.6, Color(0.45, 0.25, 0.08))
		draw_circle(c, R * 0.25, Color(0.85, 0.65, 0.25))
		for i in 4:
			var a := angle + i * PI / 2.0
			draw_line(c, c + Vector2(cos(a), sin(a)) * R * 0.5, Color(0.85, 0.65, 0.25), 4.0)
		# bola
		var br := lerpf(R * 0.72, R - 4.0, ball_r)
		draw_circle(c + Vector2(cos(ball), sin(ball)) * br, 7.0, Color(0.97, 0.97, 0.97))
		draw_circle(c + Vector2(cos(ball), sin(ball)) * br, 7.0, Color(0, 0, 0, 0.5), false, 1.0)
		# marca de arriba
		draw_colored_polygon(PackedVector2Array([c + Vector2(-8, -R - 10), c + Vector2(8, -R - 10), c + Vector2(0, -R + 2)]), GOLD)


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	game = casino.game
	font_num = SystemFont.new()
	font_num.font_names = PackedStringArray(["Impact", "Arial Black", "Arial"])
	font_ui = SystemFont.new()
	font_ui.font_names = PackedStringArray(["Segoe UI", "Arial", "DejaVu Sans"])
	font_ui.font_weight = 600

	# fondo desenfocado con un tinte morado de casino
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
	COLOR = vec4(c * (0.4 - v * 0.25) + vec3(0.04, 0.0, 0.05), 1.0);
}
"""
	bg.material = bm
	add_child(bg)

	panel = PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.07, 0.02, 0.05, 0.94)
	ps.border_color = GOLD.darkened(0.2)
	ps.set_border_width_all(2)
	ps.set_corner_radius_all(18)
	ps.set_content_margin_all(24)
	ps.shadow_color = Color(1.0, 0.7, 0.2, 0.15)
	ps.shadow_size = 26
	panel.add_theme_stylebox_override("panel", ps)
	add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)

	var head := HBoxContainer.new()
	col.add_child(head)
	var titles := {"slots": "TRAGAPERRAS", "ruleta": "RULETA", "futbol": "APUESTAS · CASINO MURIEL", "quiz": "IVÁN TE PREGUNTA"}
	var title := _lbl(head, titles[mode], 40, GOLD, font_num, 10)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pb := VBoxContainer.new()
	pb.add_theme_constant_override("separation", -6)
	head.add_child(pb)
	var cap := _lbl(pb, "T U S   P U N T O S", 12, Color(1, 1, 1, 0.6), font_ui, 0)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	points_lbl = _lbl(pb, "", 32, GOLD, font_num, 6)
	points_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	match mode:
		"slots":
			_build_slots(col)
		"ruleta":
			_build_roulette(col)
		"quiz":
			_build_quiz(col)
		_:
			_build_football(col)

	# cuánto apuestas (la pregunta de Iván no lleva apuesta)
	if mode != "quiz":
		var brow := HBoxContainer.new()
		brow.add_theme_constant_override("separation", 8)
		brow.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_child(brow)
		_lbl(brow, "Apuesta:", 18, Color(1, 1, 1, 0.8), font_ui, 0)
		for b in BETS:
			var btn := _button(brow, str(b), Vector2(78, 38), 18, Color(0.35, 0.25, 0.08))
			btn.pressed.connect(func(): _set_bet(b))
			bet_btns[b] = btn
	msg_lbl = _lbl(col, "", 22, Color(1, 1, 1), font_num, 6)
	msg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var keys := {"slots": "[Espacio] jugar      ·      ", "ruleta": "[Espacio] jugar      ·      ", "quiz": "[1] / [2] responder      ·      "}
	var foot := _lbl(col, keys.get(mode, "") + "[E] / [Esc] salir", 15, Color(1, 1, 1, 0.5), font_ui, 0)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	snd_tick = _snd(U.make_beep(1500.0), -14.0)
	snd_win = _snd(U.make_kaching(), 0.0)
	snd_big = _snd(U.make_powerup(), 2.0)
	snd_lose = _snd(U.make_beep(170.0), 2.0)

	game.player.input_blocked = true
	if not Net.online:
		get_tree().paused = true
		paused_it = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_set_bet(100)
	panel.reset_size()
	_center()
	panel.pivot_offset = panel.size / 2.0
	panel.scale = Vector2.ONE * 0.92
	panel.modulate.a = 0.0
	var tw := create_tween().set_parallel()
	tw.tween_property(panel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "modulate:a", 1.0, 0.15)


# ---------------- piezas de interfaz ----------------
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


func _button(parent: Node, text: String, min_size: Vector2, fsize: int, c: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font_num)
	b.add_theme_font_size_override("font_size", fsize)
	var n := StyleBoxFlat.new()
	n.bg_color = c
	n.set_corner_radius_all(8)
	n.border_color = GOLD
	var h: StyleBoxFlat = n.duplicate()
	h.bg_color = c.lightened(0.25)
	var d: StyleBoxFlat = n.duplicate()
	d.bg_color = Color(0.15, 0.15, 0.15, 0.9)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_stylebox_override("disabled", d)
	b.add_theme_color_override("font_color", Color(1, 1, 1))
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.4))
	parent.add_child(b)
	return b


# marca el botón elegido con un borde dorado
func _select(b: Button, on: bool) -> void:
	for st in ["normal", "hover", "pressed"]:
		var s: StyleBoxFlat = b.get_theme_stylebox(st).duplicate()
		s.set_border_width_all(3 if on else 0)
		b.add_theme_stylebox_override(st, s)


func _snd(stream: AudioStream, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	add_child(p)
	return p


func _set_bet(b: int) -> void:
	bet_amount = b
	for k in bet_btns:
		_select(bet_btns[k], k == b)


func _msg(text: String, c: Color) -> void:
	msg_lbl.text = text
	msg_lbl.add_theme_color_override("font_color", c)
	msg_lbl.pivot_offset = msg_lbl.size / 2.0
	msg_lbl.scale = Vector2.ONE * 1.15
	create_tween().tween_property(msg_lbl, "scale", Vector2.ONE, 0.2)


func _pay(amount: int) -> bool:
	if game.points < amount:
		_msg("No tienes puntos suficientes", Color(1.0, 0.4, 0.35))
		snd_lose.play()
		return false
	game.points -= amount
	return true


# ---------------- tragaperras ----------------
func _build_slots(col: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	col.add_child(row)
	var reels_box := HBoxContainer.new()
	reels_box.add_theme_constant_override("separation", 10)
	row.add_child(reels_box)
	for i in 3:
		var pc := PanelContainer.new()
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0.96, 0.95, 0.9)
		s.set_corner_radius_all(10)
		s.border_color = Color(0.6, 0.08, 0.1)
		s.set_border_width_all(4)
		pc.add_theme_stylebox_override("panel", s)
		pc.custom_minimum_size = Vector2(150, 170)
		reels_box.add_child(pc)
		var l := _lbl(pc, "7", 84, SYMBOLS[0][1], font_num, 4)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		reels.append(l)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 4)
	row.add_child(side)
	_lbl(side, "PREMIOS", 22, GOLD, font_num, 4)
	for s in SYMBOLS:
		_lbl(side, "%s  %s  %s    x%d" % [s[0], s[0], s[0], s[2]], 18, s[1], font_ui, 3)
	_lbl(side, "Dos iguales    x%s" % str(PAIR_PAY).replace(".", ","), 18, Color(1, 1, 1, 0.85), font_ui, 3)
	var spin := _button(col, "TIRAR DE LA PALANCA", Vector2(0, 52), 24, Color(0.6, 0.08, 0.1))
	spin.pressed.connect(_spin_slots)


func _spin_slots() -> void:
	if busy or not _pay(bet_amount):
		return
	busy = true
	spin_t = 0.0
	reel_res = [randi() % SYMBOLS.size(), randi() % SYMBOLS.size(), randi() % SYMBOLS.size()]
	reel_stop = [0.9, 1.4, 1.9]
	_msg("...", Color(1, 1, 1))
	casino._talk("¡Vamos, que sale!")


func _update_slots(delta: float) -> void:
	if not busy:
		return
	spin_t += delta
	tick_t -= delta
	var tick := tick_t <= 0.0
	if tick:
		tick_t = 0.06
		snd_tick.play()
	for i in 3:
		var l: Label = reels[i]
		var s: Array
		if spin_t < reel_stop[i]:
			if not tick:
				continue
			s = SYMBOLS.pick_random()
		else:
			s = SYMBOLS[reel_res[i]]
		l.text = s[0]
		l.add_theme_color_override("font_color", s[1])
	if spin_t >= reel_stop[2]:
		busy = false
		var a: int = reel_res[0]
		var b: int = reel_res[1]
		var c: int = reel_res[2]
		var win := 0
		if a == b and b == c:
			win = bet_amount * int(SYMBOLS[a][2])
		elif a == b or b == c or a == c:
			win = int(bet_amount * PAIR_PAY)
		if win > 0:
			game.points += win
			var big := a == b and b == c
			_msg(("¡¡PREMIO GORDO!! +%d" if big else "¡Premio! +%d") % win, GOLD)
			(snd_big if big else snd_win).play()
		else:
			_msg("Nada... otra vez será", Color(1.0, 0.45, 0.4))
			snd_lose.play()


# ---------------- ruleta ----------------
func _build_roulette(col: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	col.add_child(row)
	wheel = WheelView.new()
	wheel.font = font_ui
	wheel.custom_minimum_size = Vector2(320, 320)
	row.add_child(wheel)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	row.add_child(right)
	_lbl(right, "¿A qué apuestas?", 20, Color(1, 1, 1, 0.85), font_ui, 0)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	right.add_child(grid)
	for rb in RBETS:
		var c := Color(0.25, 0.25, 0.28)
		match rb[0]:
			"rojo":
				c = Color(0.65, 0.07, 0.07)
			"negro":
				c = Color(0.08, 0.08, 0.09)
			"num":
				c = Color(0.05, 0.4, 0.18)
		var btn := _button(grid, "%s  x%d" % [rb[1], rb[2]], Vector2(150, 42), 16, c)
		btn.pressed.connect(func(): _set_rbet(rb[0]))
		rbtns[rb[0]] = btn
	# número elegido (para la apuesta a un número)
	var nrow := HBoxContainer.new()
	nrow.add_theme_constant_override("separation", 8)
	right.add_child(nrow)
	_lbl(nrow, "Número:", 18, Color(1, 1, 1, 0.8), font_ui, 0)
	var minus := _button(nrow, "−", Vector2(40, 36), 20, Color(0.25, 0.25, 0.28))
	minus.pressed.connect(func(): _set_num(rnum - 1))
	num_lbl = _lbl(nrow, "", 26, Color(1, 1, 1), font_num, 4)
	num_lbl.custom_minimum_size.x = 44
	num_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var plus := _button(nrow, "+", Vector2(40, 36), 20, Color(0.25, 0.25, 0.28))
	plus.pressed.connect(func(): _set_num(rnum + 1))
	result_lbl = _lbl(right, "", 46, Color(1, 1, 1), font_num, 8)
	var go := _button(right, "GIRAR LA RULETA", Vector2(0, 52), 24, Color(0.05, 0.4, 0.18))
	go.pressed.connect(_spin_roulette)
	_set_rbet("rojo")
	_set_num(17)


func _set_rbet(id: String) -> void:
	rbet = id
	for k in rbtns:
		_select(rbtns[k], k == id)


func _set_num(n: int) -> void:
	rnum = wrapi(n, 0, 37)
	num_lbl.text = str(rnum)
	num_lbl.add_theme_color_override("font_color", pocket_color(rnum).lightened(0.35))
	_set_rbet("num")


func _spin_roulette() -> void:
	if busy or not _pay(bet_amount):
		return
	busy = true
	spin_t = 0.0
	var res := randi() % 37
	reel_res = [res]
	wheel.spin(res, 4.5)
	casino.spin_wheel(4.5)
	result_lbl.text = ""
	_msg("No va más...", Color(1, 1, 1))


func _wins(n: int) -> bool:
	match rbet:
		"rojo":
			return n in REDS
		"negro":
			return n != 0 and not n in REDS
		"par":
			return n != 0 and n % 2 == 0
		"impar":
			return n % 2 == 1
		"bajo":
			return n >= 1 and n <= 18
		"alto":
			return n >= 19
		"d1":
			return n >= 1 and n <= 12
		"d2":
			return n >= 13 and n <= 24
		"d3":
			return n >= 25
	return n == rnum


func _update_roulette(delta: float) -> void:
	if not busy:
		return
	spin_t += delta
	tick_t -= delta
	if tick_t <= 0.0 and spin_t < 4.3:
		tick_t = lerpf(0.05, 0.35, spin_t / 4.5)    # el tic-tic de la bola va frenando
		snd_tick.play()
	if spin_t >= 4.6:
		busy = false
		var n: int = reel_res[0]
		var color_name := "VERDE" if n == 0 else ("ROJO" if n in REDS else "NEGRO")
		result_lbl.text = "%d  %s" % [n, color_name]
		result_lbl.add_theme_color_override("font_color", pocket_color(n).lightened(0.4))
		if _wins(n):
			var pays := 2
			for rb in RBETS:
				if rb[0] == rbet:
					pays = rb[2]
			var win := bet_amount * pays
			game.points += win
			_msg("¡Has ganado! +%d" % win, GOLD)
			(snd_big if pays >= 36 else snd_win).play()
			casino._talk("¡Toma ya! Hoy estás que lo rompes")
		else:
			_msg("La banca gana...", Color(1.0, 0.45, 0.4))
			snd_lose.play()


# ---------------- la pregunta de Iván ----------------
func _build_quiz(col: VBoxContainer) -> void:
	var q := _lbl(col, "¿Fabiana Sevillano o Lucía Bellido?", 38, Color(1, 1, 1), font_num, 8)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q.custom_minimum_size = Vector2(680, 0)
	var hint := _lbl(col, "Piénsatelo bien: si aciertas te llevas puntos... y si no, te los quita", 16, Color(1, 1, 1, 0.6), font_ui, 0)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	var names: Array = casino.QUIZ_NAMES
	for i in names.size():
		var btn := _button(row, "[%d]  %s" % [i + 1, str(names[i]).to_upper()], Vector2(320, 70), 24,
			Color(0.5, 0.1, 0.35) if i == 0 else Color(0.1, 0.3, 0.55))
		btn.pressed.connect(func(): _answer(i))
		odds_btns.append(btn)


func _answer(i: int) -> void:
	if busy:
		return
	busy = true                 # una sola respuesta
	for b in odds_btns:
		b.disabled = true
	var right: bool = casino.answer(i)
	if right:
		_msg("¡Respuesta correcta! +%d puntos" % casino.QUIZ_PRIZE, GOLD)
		snd_big.play()
	else:
		_msg("Respuesta incorrecta... -%d puntos" % casino.QUIZ_PRIZE, Color(1.0, 0.4, 0.35))
		snd_lose.play()
	get_tree().create_timer(1.6, true).timeout.connect(func():
		busy = false
		close())


# ---------------- fútbol ----------------
func _build_football(col: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	col.add_child(row)
	var tvf := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.02, 0.02, 0.03)
	s.set_content_margin_all(6)
	s.set_corner_radius_all(8)
	tvf.add_theme_stylebox_override("panel", s)
	row.add_child(tvf)
	var tr := TextureRect.new()
	tr.texture = casino.tv_vp.get_texture()
	tr.custom_minimum_size = Vector2(448, 252)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tvf.add_child(tr)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	row.add_child(right)
	finfo = _lbl(right, "", 18, Color(1, 1, 1, 0.9), font_ui, 0)
	finfo.custom_minimum_size = Vector2(300, 0)
	for i in 3:
		var btn := _button(right, "", Vector2(300, 46), 18, Color(0.12, 0.35, 0.5) if i == 0 else (Color(0.3, 0.3, 0.32) if i == 1 else Color(0.45, 0.12, 0.12)))
		btn.pressed.connect(func(): _set_pick(i))
		odds_btns.append(btn)
	var go := _button(right, "APOSTAR", Vector2(0, 50), 24, Color(0.55, 0.4, 0.05))
	go.pressed.connect(_bet_football)
	_set_pick(0)


func _set_pick(i: int) -> void:
	fpick = i
	for k in 3:
		_select(odds_btns[k], k == i)


func _bet_football() -> void:
	var err: String = casino.place_bet(fpick, bet_amount)
	if err != "":
		_msg(err, Color(1.0, 0.45, 0.4))
		snd_lose.play()
	else:
		_msg("Apuesta hecha: %d a %s (x%s)" % [bet_amount, casino.team_name(fpick), _odd(casino.odds[fpick])], GOLD)
		snd_win.play()


func _odd(o: float) -> String:
	return ("%.2f" % o).replace(".", ",")


func _update_football() -> void:
	var labels := ["1  ·  " + casino.HOME, "X  ·  Empate", "2  ·  " + casino.away]
	for i in 3:
		odds_btns[i].text = "%s     x%s" % [labels[i], _odd(casino.odds[i])]
	var sc: Vector2i = casino.score()
	var t := "%s %d - %d %s\n" % [casino.HOME, sc.x, sc.y, casino.away]
	if casino.finished:
		t += "Partido terminado · el siguiente empieza enseguida\n"
	elif casino.minute() >= casino.BET_CLOSE:
		t += "Minuto %d · apuestas cerradas\n" % casino.minute()
	else:
		t += "Minuto %d · apuestas abiertas hasta el %d'\n" % [casino.minute(), casino.BET_CLOSE]
	if not casino.bet.is_empty():
		var b: Dictionary = casino.bet
		t += "Tu apuesta: %d a %s (x%s)" % [b["amount"], casino.team_name(b["pick"]), _odd(b["odds"])]
	else:
		t += "Sin apuesta en este partido"
	finfo.text = t


# ---------------- bucle y salida ----------------
func _process(delta: float) -> void:
	points_lbl.text = HudScript.thousands(game.points)
	match mode:
		"slots":
			_update_slots(delta)
		"ruleta":
			_update_roulette(delta)
		"quiz":
			pass
		_:
			_update_football()
	_center()
	var p = game.player
	if p.dead or p.downed:
		close()


func _input(event: InputEvent) -> void:
	if closing:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_E, KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				if not busy:
					call_deferred("close")
			KEY_1, KEY_2:
				if mode == "quiz":
					get_viewport().set_input_as_handled()
					_answer(event.keycode - KEY_1)
			KEY_SPACE:
				get_viewport().set_input_as_handled()
				if mode == "slots":
					_spin_slots()
				elif mode == "ruleta":
					_spin_roulette()


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
	game.e_prev = true          # que la E de cerrar no vuelva a abrir el menú
	casino.menu_closed()
	var tw := create_tween().set_parallel()
	tw.tween_property(panel, "modulate:a", 0.0, 0.12)
	tw.tween_property(panel, "scale", Vector2.ONE * 0.95, 0.12)
	tw.chain().tween_callback(queue_free)

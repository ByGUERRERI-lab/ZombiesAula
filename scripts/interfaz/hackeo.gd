extends CanvasLayer
# Oleada 10: "te están hackeando". La pantalla se rompe (colores separados,
# rayas y ruido), sale una terminal verde escribiendo sola y aparece Jesús
# en una ventana riéndose... y empieza a robarte. Se abre la TERMINAL DE DEFENSA:
# escribe los comandos que salen (con mando: la secuencia de flechas de la cruceta)
# antes de que la barra de Jesús llegue al 100 %.
#   · Lo consigues  -> Jesús se va con las manos vacías y te llevas 1000 puntos.
#   · No llegas     -> te lo roba TODO: puntos, armas, bebidas y Jans.
# Cada tecla mal pulsada le da un empujón a la barra; cada comando bien escrito la frena.

const U = preload("res://scripts/nucleo/util.gd")
const Ch = preload("res://scripts/jugador/character.gd")
const HudScript = preload("res://scripts/interfaz/hud.gd")

const INTRO := 3.0           # glitch + terminal escribiendo sola + sale Jesús
const ROBO_T := 18.0         # segundos que tarda Jesús en robártelo todo
const FINAL := 3.0           # lo que dura el final (ganes o pierdas)
const DURATION := INTRO + ROBO_T + FINAL       # lo más que puede durar (main.gd espera esto)
const N_COMANDOS := 4
const FALLO := 0.025         # lo que sube la barra por cada tecla mal
const FRENO := 0.07          # lo que baja por cada comando bien escrito
const LINES := [
	"> conectando con %s...",
	"> saltándose el firewall de CESUR........ OK",
	"> robando contraseñas del Moodle......... OK",
	"> copiando tus puntos y tus armas........",
]
const COMANDOS := ["firewall on", "kill jesus.exe", "cambiar password", "desconectar wifi",
	"sudo echar a jesus", "borrar virus", "bloquear ip", "antivirus ya", "cerrar puertos", "formatear jesus"]
const FLECHAS := {KEY_UP: "↑", KEY_DOWN: "↓", KEY_LEFT: "←", KEY_RIGHT: "→"}

var game
var t := 0.0
var glitch: ColorRect
var glitch_mat: ShaderMaterial
var term: Label
var term_text := ""
var line_i := 0
var char_i := 0
var type_t := 0.0
var window: Control
var title: Label
var laugh_lbl: Label
var jesus_head: Node3D
var jesus_model: Node3D
var beep: AudioStreamPlayer
var beeps: Array = []
var win_pos := Vector2.ZERO
var shown := false
var on_done: Callable
# terminal de defensa
var fase := 0                # 0 intro, 1 defensa, 2 ganaste, 3 te lo ha robado
var robo := 0.0              # 0..1 lo que lleva robado Jesús
var comandos: Array = []     # lo que hay que escribir (texto o lista de teclas de flecha)
var cmd_i := 0
var escrito := 0             # letras (o flechas) bien puestas del comando actual
var con_mando := false
var fin_t := 0.0
var def_panel: PanelContainer
var def_cmd: RichTextLabel
var def_info: Label
var def_bar: ProgressBar
var def_pct: Label
var def_log: Label
var mono_f: Font
var snd_ok: AudioStreamPlayer
var snd_mal: AudioStreamPlayer
var bloqueado_antes := false


func _ready() -> void:
	layer = 30
	game = get_tree().get_first_node_in_group("game")
	game.hacking = true

	# pantalla rota: lee lo que hay debajo y lo distorsiona
	glitch_mat = ShaderMaterial.new()
	glitch_mat.shader = Shader.new()
	glitch_mat.shader.code = """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float amount = 0.0;
uniform float t = 0.0;
float rnd(float x) { return fract(sin(x * 91.7) * 43758.5453); }
void fragment() {
	vec2 uv = SCREEN_UV;
	float line = floor(uv.y * 38.0);
	float k = floor(t * 14.0);
	float tear = step(1.0 - amount * 0.35, rnd(line + k * 7.3)) * (rnd(line * 3.1 + k) - 0.5) * 0.18 * amount;
	uv.x = fract(uv.x + tear);
	float s = 0.014 * amount;
	vec3 c;
	c.r = texture(screen_tex, uv + vec2(s, 0.0)).r;
	c.g = texture(screen_tex, uv).g;
	c.b = texture(screen_tex, uv - vec2(s, 0.0)).b;
	c *= mix(1.0, 0.82 + 0.18 * sin(uv.y * 900.0), amount);
	c = mix(c, vec3(c.r * 0.2, c.g * 1.25 + 0.05, c.b * 0.2), amount * 0.4);
	c += (rnd(uv.x * 13.0 + uv.y * 171.0 + t * 3.0) - 0.5) * 0.3 * amount;
	COLOR = vec4(c, 1.0);
}
"""
	glitch = ColorRect.new()
	glitch.material = glitch_mat
	glitch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glitch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glitch)

	# terminal verde a la izquierda
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "Courier New", "DejaVu Sans Mono", "monospace"])
	var bg := ColorRect.new()
	bg.color = Color(0, 0.03, 0, 0.82)
	bg.position = Vector2(30, 150)
	bg.size = Vector2(620, 260)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	term = Label.new()
	term.position = Vector2(14, 10)
	term.add_theme_font_override("font", mono)
	term.add_theme_font_size_override("font_size", 20)
	term.add_theme_color_override("font_color", Color(0.2, 1.0, 0.3))
	bg.add_child(term)

	mono_f = mono
	_build_window(mono)
	_build_defensa(mono)
	snd_ok = AudioStreamPlayer.new()
	snd_ok.stream = U.make_beep(1600.0)
	snd_ok.volume_db = -6.0
	add_child(snd_ok)
	snd_mal = AudioStreamPlayer.new()
	snd_mal.stream = U.make_beep(180.0)
	snd_mal.volume_db = -4.0
	add_child(snd_mal)
	if game.player != null:
		bloqueado_antes = game.player.input_blocked
		game.player.input_blocked = true      # que al escribir no te muevas ni dispares

	for f in [700.0, 900.0, 1100.0, 1300.0]:
		beeps.append(U.make_beep(f))
	beep = AudioStreamPlayer.new()
	beep.volume_db = -8.0
	add_child(beep)
	var noise := AudioStreamPlayer.new()
	noise.stream = U.make_static(0.8)
	add_child(noise)
	noise.play()


# Ventana "JESUS.EXE" con Jesús en 3D (en su propio mundo) riéndose
func _build_window(mono: Font) -> void:
	window = Control.new()
	window.size = Vector2(440, 520)
	var vs := get_viewport().get_visible_rect().size
	win_pos = Vector2(vs.x - 440 * 0.8 - 30, 30)
	window.position = win_pos
	window.pivot_offset = Vector2.ZERO
	window.scale = Vector2.ZERO
	window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(window)
	var frame := ColorRect.new()
	frame.color = Color(0.85, 0.05, 0.05)
	frame.size = window.size
	window.add_child(frame)
	var bar := Label.new()
	bar.text = "  JESUS.EXE                                   X"
	bar.add_theme_font_override("font", mono)
	bar.add_theme_font_size_override("font_size", 18)
	bar.add_theme_color_override("font_color", Color(1, 1, 1))
	bar.position = Vector2(4, 2)
	window.add_child(bar)

	var svc := SubViewportContainer.new()
	svc.position = Vector2(6, 30)
	svc.size = Vector2(428, 400)
	svc.stretch = true
	window.add_child(svc)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.size = Vector2i(428, 400)
	vp.msaa_3d = Viewport.MSAA_4X
	svc.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.0, 0.08, 0.02)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(1.0, 1.0, 1.0)
	env.environment.ambient_light_energy = 0.55
	vp.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-30, 25, 0)
	light.light_color = Color(1.0, 1.0, 0.97)
	vp.add_child(light)
	var holder := Node3D.new()
	holder.rotation_degrees.y = 180.0
	vp.add_child(holder)
	var parts: Dictionary = Ch.build_jesus(holder)
	jesus_model = parts["model"]
	jesus_head = parts["head"]
	var cam := Camera3D.new()
	cam.fov = 40.0
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.62, 1.35), Vector3(0, 1.55, 0))

	title = Label.new()
	title.text = "HACKEADO POR JESÚS"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(1, 1, 1))
	title.add_theme_constant_override("outline_size", 8)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	title.position = Vector2(30, 436)
	window.add_child(title)
	laugh_lbl = Label.new()
	laugh_lbl.text = "Tus zombis ahora son míos jajaja"
	laugh_lbl.add_theme_font_override("font", mono)
	laugh_lbl.add_theme_font_size_override("font_size", 18)
	laugh_lbl.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
	laugh_lbl.position = Vector2(50, 482)
	window.add_child(laugh_lbl)


func _process(delta: float) -> void:
	t += delta
	# intensidad del glitch: entra fuerte, se queda a medias con tirones y se va al final
	var a := clampf(t / 0.4, 0.0, 1.0)
	if t > 2.5:
		a = 0.25 + (0.4 if fmod(t, 1.3) < 0.1 else 0.0) + robo * 0.35
	if fase >= 2:
		a = clampf(1.0 - fin_t / FINAL, 0.0, 1.0) * (0.3 if fase == 2 else 0.8)
	glitch_mat.set_shader_parameter("amount", a)
	glitch_mat.set_shader_parameter("t", t)

	_type(delta)

	if t > 2.6 and not shown:
		shown = true
		var tw := create_tween()
		tw.tween_property(window, "scale", Vector2.ONE * 0.8, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		var laugh := AudioStreamPlayer.new()
		laugh.stream = U.make_laugh()
		add_child(laugh)
		laugh.play()
	if shown:
		# Jesús se ríe: cabeza arriba y abajo, hombros que botan
		var risa := 18.0 if fase != 2 else 4.0
		jesus_head.rotation.x = -0.12 + sin(t * risa) * 0.08
		jesus_model.position.y = absf(sin(t * risa * 0.5)) * 0.025
		title.visible = fmod(t, 0.5) < 0.35
		window.position.x = win_pos.x + (randf_range(-8, 8) if fmod(t, 0.9) < 0.12 else 0.0)

	match fase:
		0:
			if t >= INTRO:
				_empezar_defensa()
		1:
			robo += delta / ROBO_T
			if robo >= 1.0:
				robo = 1.0
				_perder()
			_pintar_defensa()
		_:
			fin_t += delta
			if fin_t > FINAL - 0.4 and window.scale.y > 0.79:
				create_tween().tween_property(window, "scale", Vector2(0.8, 0.0), 0.2)
			if fin_t >= FINAL:
				_terminar()


func _terminar() -> void:
	game.hacking = false
	if game.player != null:
		game.player.input_blocked = bloqueado_antes
	if on_done.is_valid():
		on_done.call()
	queue_free()


# ---------------- Terminal de defensa ----------------
func _build_defensa(mono: Font) -> void:
	def_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.04, 0.01, 0.93)
	sb.border_color = Color(0.2, 1.0, 0.35)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(18)
	def_panel.add_theme_stylebox_override("panel", sb)
	def_panel.custom_minimum_size = Vector2(720, 0)
	def_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	def_panel.visible = false
	add_child(def_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	def_panel.add_child(v)
	var cab := Label.new()
	cab.text = "TERMINAL DE DEFENSA · CESUR"
	cab.add_theme_font_override("font", mono)
	cab.add_theme_font_size_override("font_size", 16)
	cab.add_theme_color_override("font_color", Color(0.2, 1.0, 0.35, 0.7))
	v.add_child(cab)
	def_info = Label.new()
	def_info.add_theme_font_override("font", HudScript.fuente(HudScript.F_UI_BOLD))
	def_info.add_theme_font_size_override("font_size", 20)
	def_info.add_theme_color_override("font_color", Color(1, 1, 1))
	v.add_child(def_info)
	def_cmd = RichTextLabel.new()
	def_cmd.bbcode_enabled = true
	def_cmd.fit_content = true
	def_cmd.scroll_active = false
	def_cmd.autowrap_mode = TextServer.AUTOWRAP_OFF
	def_cmd.add_theme_font_override("normal_font", mono)
	def_cmd.add_theme_font_size_override("normal_font_size", 40)
	def_cmd.custom_minimum_size = Vector2(680, 56)
	v.add_child(def_cmd)
	def_log = Label.new()
	def_log.add_theme_font_override("font", mono)
	def_log.add_theme_font_size_override("font_size", 16)
	def_log.add_theme_color_override("font_color", Color(0.2, 1.0, 0.35, 0.8))
	v.add_child(def_log)
	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 12)
	v.add_child(fila)
	var lj := Label.new()
	lj.text = "JESÚS ROBANDO"
	lj.add_theme_font_override("font", HudScript.fuente(HudScript.F_UI_BOLD))
	lj.add_theme_font_size_override("font_size", 16)
	lj.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
	fila.add_child(lj)
	def_bar = ProgressBar.new()
	def_bar.show_percentage = false
	def_bar.custom_minimum_size = Vector2(480, 14)
	def_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.25, 0.05, 0.05)
	var fg := StyleBoxFlat.new()
	fg.bg_color = Color(1.0, 0.18, 0.15)
	def_bar.add_theme_stylebox_override("background", bg)
	def_bar.add_theme_stylebox_override("fill", fg)
	fila.add_child(def_bar)
	def_pct = Label.new()
	def_pct.add_theme_font_override("font", mono)
	def_pct.add_theme_font_size_override("font_size", 18)
	def_pct.add_theme_color_override("font_color", Color(1.0, 0.4, 0.35))
	fila.add_child(def_pct)


func _empezar_defensa() -> void:
	fase = 1
	con_mando = HudScript._hay_mando()
	var lista := COMANDOS.duplicate()
	lista.shuffle()
	for k in N_COMANDOS:
		if con_mando:
			var seq := []
			for j in 5 + k:
				seq.append(FLECHAS.keys().pick_random())
			comandos.append(seq)
		else:
			comandos.append(lista[k])
	def_panel.visible = true
	var vs := get_viewport().get_visible_rect().size
	def_panel.reset_size()
	def_panel.position = Vector2(40, vs.y - def_panel.size.y - 60)
	def_panel.modulate.a = 0.0
	create_tween().tween_property(def_panel, "modulate:a", 1.0, 0.2)
	laugh_lbl.text = "Dame todo lo que tienes jajaja"
	_pintar_defensa()


func _pintar_defensa() -> void:
	def_bar.value = robo * 100.0
	def_pct.text = "%d %%" % int(robo * 100.0)
	if fase != 1:
		return
	var cmd = comandos[cmd_i]
	var quedan := "Comando %d de %d" % [cmd_i + 1, N_COMANDOS]
	if con_mando:
		def_info.text = "¡Jesús te está robando! Pulsa en la cruceta:   (%s)" % quedan
		var s := "[color=#3f6]> [/color]"
		for k in cmd.size():
			var f: String = FLECHAS[cmd[k]]
			s += ("[color=#3f6]%s[/color] " % f) if k < escrito else ("[color=#ffffff]%s[/color] " % f if k == escrito else "[color=#777]%s[/color] " % f)
		def_cmd.text = s
	else:
		def_info.text = "¡Jesús te está robando! Escribe el comando:   (%s)" % quedan
		var txt: String = cmd
		var cursor := "_" if fmod(t, 0.5) < 0.25 else " "
		def_cmd.text = "[color=#3f6]> %s[/color][color=#ffffff]%s[/color][color=#666]%s[/color]" % [
			txt.substr(0, escrito), cursor, txt.substr(escrito)]


func _input(event: InputEvent) -> void:
	if fase != 1:
		return
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	get_viewport().set_input_as_handled()
	var cmd = comandos[cmd_i]
	var bien := false
	if con_mando:
		if FLECHAS.has(k.keycode):
			bien = k.keycode == cmd[escrito]
		else:
			return
	else:
		if k.unicode == 0:
			return
		var c := String.chr(k.unicode).to_lower()
		bien = c == String(cmd[escrito])
	if bien:
		escrito += 1
		beep.stream = beeps.pick_random()
		beep.play()
		var largo: int = cmd.size() if con_mando else String(cmd).length()
		if escrito >= largo:
			_comando_hecho()
	else:
		robo = minf(1.0, robo + FALLO)
		snd_mal.play()
		var tw := def_panel.create_tween()
		def_panel.modulate = Color(1.0, 0.4, 0.4)
		tw.tween_property(def_panel, "modulate", Color.WHITE, 0.25)
	_pintar_defensa()


func _comando_hecho() -> void:
	snd_ok.play()
	var cmd = comandos[cmd_i]
	def_log.text += ("> %s ... OK\n" % (cmd if not con_mando else "secuencia %d" % (cmd_i + 1)))
	robo = maxf(0.0, robo - FRENO)
	cmd_i += 1
	escrito = 0
	laugh_lbl.text = ["¡¿Qué haces?!", "¡Para quieto!", "¡Eso no vale!", "¡NOOO!"][mini(cmd_i - 1, 3)]
	if cmd_i >= N_COMANDOS:
		_ganar()


func _ganar() -> void:
	fase = 2
	def_info.text = "CONEXIÓN CORTADA"
	def_cmd.text = "[color=#3f6]> Jesús expulsado de tu PC. +1000 puntos[/color]"
	title.text = "¡ME HAS PILLADO!"
	laugh_lbl.text = "Esto no se va a quedar así..."
	game.points += 1000
	game._toast("¡Has echado a Jesús de tu PC! +1000 puntos")


func _perder() -> void:
	fase = 3
	def_info.text = "TRANSFERENCIA COMPLETADA"
	def_cmd.text = "[color=#f44]> Jesús se lo ha llevado todo[/color]"
	title.text = "TODO ES MÍO"
	laugh_lbl.text = "Gracias por los puntos jajaja"
	var laugh := AudioStreamPlayer.new()
	laugh.stream = U.make_laugh(0.85)
	add_child(laugh)
	laugh.play()
	if game.player != null:
		game.player.hackeado()
	game._toast("Jesús te ha robado TODO: puntos, armas, bebidas y Jans")


# La terminal escribe sola, letra a letra (varias por fotograma si hace falta), con pitidos
func _type(delta: float) -> void:
	type_t -= delta
	while type_t <= 0.0 and line_i < LINES.size():
		type_t += 0.014
		var line: String = LINES[line_i]
		if line_i == 0:
			line = line % ("el PC de " + Net.my_name if Net.online else "tu PC")
		if char_i < line.length():
			term_text += line[char_i]
			char_i += 1
			if char_i % 4 == 0:
				beep.stream = beeps.pick_random()
				beep.play()
		else:
			term_text += "\n"
			line_i += 1
			char_i = 0
			type_t += 0.2
	term.text = term_text + ("_" if fmod(t, 0.4) < 0.2 else "")

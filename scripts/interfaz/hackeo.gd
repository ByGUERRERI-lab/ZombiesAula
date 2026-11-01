extends CanvasLayer
# Oleada 10: "te están hackeando". La pantalla se rompe (colores separados,
# rayas y ruido), sale una terminal verde escribiendo sola y aparece Jesús
# en una ventana riéndose. Dura unos 8 segundos y luego todo vuelve a la normalidad.

const U = preload("res://scripts/nucleo/util.gd")
const Ch = preload("res://scripts/jugador/character.gd")

const DURATION := 8.0
const LINES := [
	"> conectando con %s...",
	"> saltándose el firewall de CESUR........ OK",
	"> robando contraseñas del Moodle......... OK",
	"> descargando zombis.exe ................ 100%",
	"> borrando los apuntes de programación... OK",
	"> ACCESO TOTAL CONCEDIDO",
]

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

	_build_window(mono)

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
	win_pos = get_viewport().get_visible_rect().size / 2.0 + Vector2(-60, -260)
	window.position = win_pos
	window.pivot_offset = window.size / 2.0
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
	# intensidad: entra fuerte, se queda a medias con tirones y se va al final
	var a := clampf(t / 0.4, 0.0, 1.0)
	if t > 2.5:
		a = 0.45 + (0.5 if fmod(t, 0.9) < 0.12 else 0.0)
	if t > DURATION - 1.0:
		a = clampf(DURATION - t, 0.0, 1.0) * 0.6
	glitch_mat.set_shader_parameter("amount", a)
	glitch_mat.set_shader_parameter("t", t)

	_type(delta)

	if t > 2.6 and not shown:
		shown = true
		var tw := create_tween()
		tw.tween_property(window, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		var laugh := AudioStreamPlayer.new()
		laugh.stream = U.make_laugh()
		add_child(laugh)
		laugh.play()
	if shown:
		# Jesús se ríe: cabeza arriba y abajo, hombros que botan
		jesus_head.rotation.x = -0.12 + sin(t * 18.0) * 0.08
		jesus_model.position.y = absf(sin(t * 9.0)) * 0.025
		title.visible = fmod(t, 0.5) < 0.35
		window.position.x = win_pos.x + (randf_range(-8, 8) if fmod(t, 0.9) < 0.12 else 0.0)

	if t > DURATION - 0.6 and window.scale.x > 0.99:
		create_tween().tween_property(window, "scale", Vector2(1.0, 0.0), 0.2)
	if t >= DURATION:
		game.hacking = false
		if on_done.is_valid():
			on_done.call()
		queue_free()


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

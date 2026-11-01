extends Node3D
# La tienda de Juan Carlos: un puesto en el pasillo (justo pasando la primera
# puerta) donde Juan Carlos toca la guitarra. Con E se abre su menú
# (tienda_menu.gd) y vende cosas que dan habilidades:
#   · Porro:  "colocón" de 40 s: recibes la mitad de daño y te curas muy rápido
#             (y lo ves todo verde y ondulado).
#   · Café:   60 s recargando el doble de rápido y disparando un 25 % más rápido.
#   · GTA VI: +30 % de velocidad y 150 de vida máxima hasta que te tumben.
# Cada jugador compra con sus puntos y las habilidades son solo suyas.

const U = preload("res://scripts/nucleo/util.gd")
const Ch = preload("res://scripts/jugador/character.gd")
const MenuScript = preload("res://scripts/interfaz/tienda_menu.gd")

const POS := Vector3(3.55, 0.0, 16.0)     # donde está Juan Carlos (pegado a la pared derecha)
const ITEMS := {
	"porro": {"name": "Porro", "price": 1000, "color": Color(0.4, 0.95, 0.4),
		"desc": "Colocón de 40 s:\nrecibes la mitad de daño\ny te curas muy rápido"},
	"cafe": {"name": "Café", "price": 750, "color": Color(0.9, 0.62, 0.35),
		"desc": "Cafeína durante 60 s:\nrecargas el doble de rápido\ny disparas un 25% más rápido"},
	"gta": {"name": "GTA VI", "price": 3000, "color": Color(1.0, 0.42, 0.78),
		"desc": "Hasta que te tumben:\n+30% de velocidad\ny 150 de vida máxima"},
}
const LINES := [
	"¿Qué pasa, máquina?", "Porros y GTA VI, lo mejor de lo mejor", "Esto es de calidad, eh",
	"El GTA VI aquí ya ha salido", "Tú tranqui, que yo toco", "¿Te pongo algo, chaval?",
]

var game
var model: Node3D
var head: Node3D
var strum: Node3D
var say: Label3D
var say_t := 0.0
var t := 0.0
var fx_rect: ColorRect
var fx_mat: ShaderMaterial
var menu                     # tienda_menu.gd mientras está abierto
var menu_open := false


func _ready() -> void:
	game = get_tree().get_first_node_in_group("game")
	position = POS
	_build()
	# efecto del porro en la pantalla (verde, ondulado y con viñeta)
	var layer := CanvasLayer.new()
	layer.layer = 3
	add_child(layer)
	fx_mat = ShaderMaterial.new()
	fx_mat.shader = Shader.new()
	fx_mat.shader.code = """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float amount = 0.0;
uniform float t = 0.0;
void fragment() {
	vec2 uv = SCREEN_UV;
	uv.x += sin(uv.y * 12.0 + t * 1.7) * 0.006 * amount;
	uv.y += cos(uv.x * 10.0 + t * 1.3) * 0.005 * amount;
	vec3 c = texture(screen_tex, uv).rgb;
	vec3 g = vec3(c.r * 0.75, c.g * 1.15 + 0.04, c.b * 0.7);
	c = mix(c, g, amount * 0.6);
	float v = distance(SCREEN_UV, vec2(0.5));
	c *= 1.0 - v * v * 0.9 * amount;
	COLOR = vec4(c, 1.0);
}
"""
	fx_rect = ColorRect.new()
	fx_rect.material = fx_mat
	fx_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fx_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx_rect.visible = false
	layer.add_child(fx_rect)


func _build() -> void:
	# Juan Carlos mirando al centro del pasillo
	var jc := Node3D.new()
	jc.rotation_degrees.y = 90.0
	add_child(jc)
	var parts: Dictionary = Ch.build_juancarlos(jc)
	model = parts["model"]
	head = parts["head"]
	strum = parts["strum"]
	# ampli "CUBE" a su lado
	U.box(self, Vector3(0.35, 0.4, 0.45), Vector3(0.05, 0.2, 1.0), Color(0.1, 0.1, 0.11))
	U.box(self, Vector3(0.02, 0.3, 0.38), Vector3(-0.13, 0.2, 1.0), Color(0.2, 0.2, 0.22))
	var cube := Label3D.new()
	cube.text = "CUBE"
	cube.font_size = 30
	cube.pixel_size = 0.003
	cube.outline_size = 0
	cube.position = Vector3(-0.145, 0.33, 1.0)
	cube.rotation_degrees.y = -90.0
	add_child(cube)
	var cable := U.limb(self, Vector3(-0.1, 0.25, 0.85), Vector3(-0.35, 0.95, 0.05), 0.008, 0.008, Color(0.95, 0.6, 0.1))
	cable.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# mostrador con mantel verde y cartel en la pared
	var table := U.solid_box(self, Vector3(0.7, 0.85, 2.4), Vector3(-0.75, 0.425, 0.0), Color(0.45, 0.3, 0.16))
	U.shiny(table, 0.6)
	U.box(self, Vector3(0.74, 0.02, 2.44), Vector3(-0.75, 0.86, 0.0), Color(0.15, 0.45, 0.2))
	var sign_l := Label3D.new()
	sign_l.text = "LA TIENDA DE\nJUAN CARLOS"
	sign_l.font_size = 70
	sign_l.pixel_size = 0.005
	sign_l.outline_size = 12
	sign_l.modulate = Color(0.4, 1.0, 0.45)
	sign_l.outline_modulate = Color(0.05, 0.2, 0.05)
	sign_l.position = Vector3(0.43, 2.85, 0.0)
	sign_l.rotation_degrees.y = -90.0
	add_child(sign_l)
	var neon := OmniLight3D.new()
	neon.light_color = Color(0.4, 1.0, 0.45)
	neon.light_energy = 1.2
	neon.omni_range = 4.5
	neon.shadow_enabled = true       # que no atraviese la pared del aseo
	neon.position = Vector3(-0.3, 2.6, 0.0)
	add_child(neon)

	# caja registradora (los productos se eligen en el menú)
	U.box(self, Vector3(0.3, 0.16, 0.34), Vector3(-0.72, 0.95, 0.5), Color(0.15, 0.15, 0.17))
	var scr := U.box(self, Vector3(0.04, 0.1, 0.2), Vector3(-0.66, 1.08, 0.5), Color(0.3, 0.9, 0.4), true)
	scr.rotation_degrees.z = -15.0
	U.box(self, Vector3(0.32, 0.05, 0.36), Vector3(-0.72, 0.89, 0.5), Color(0.25, 0.25, 0.28))
	var open_l := Label3D.new()
	open_l.text = "[E] COMPRAR"
	open_l.font_size = 44
	open_l.pixel_size = 0.004
	open_l.outline_size = 10
	open_l.modulate = Color(1.0, 0.88, 0.4)
	open_l.position = Vector3(-1.11, 0.6, 0.0)
	open_l.rotation_degrees.y = -90.0
	add_child(open_l)
	game.interactables.append({"type": "shop", "pos": global_position + Vector3(-1.55, 0, 0), "done": false})

	say = Label3D.new()
	say.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	say.font_size = 34
	say.pixel_size = 0.005
	say.outline_size = 8
	say.position = Vector3(0, 2.25, 0)
	add_child(say)

	# su guitarra suena (arpegios generados por código) y se oye de cerca
	var music := AudioStreamPlayer3D.new()
	music.stream = U.make_guitar_loop()
	music.unit_size = 3.0
	music.max_distance = 22.0
	music.volume_db = -4.0
	music.position = Vector3(0, 1.0, 0)
	music.autoplay = true
	add_child(music)


func _process(delta: float) -> void:
	t += delta
	# rasguea la guitarra y mueve la cabeza al ritmo
	strum.rotation.x = sin(t * 9.0) * 0.18
	head.rotation.x = sin(t * 4.5) * 0.06
	model.position.y = absf(sin(t * 4.5)) * 0.015

	var p = game.player
	if p == null:
		return
	# habla cuando te acercas
	var d: float = global_position.distance_to(p.global_position)
	say_t -= delta
	if d < 7.0:
		if say_t <= 0.0:
			say.text = LINES[randi() % LINES.size()]
			say_t = 4.0
	elif say_t <= 0.0:
		say.text = ""

	# pantalla verde mientras dura el colocón
	var a: float = clampf(p.porro_t / 5.0, 0.0, 1.0)
	fx_rect.visible = a > 0.0
	if fx_rect.visible:
		fx_mat.set_shader_parameter("amount", a)
		fx_mat.set_shader_parameter("t", t)


func _talk(text: String) -> void:
	say.text = text
	say_t = 3.0


func prompt(_it: Dictionary) -> String:
	return "[E] Ver la tienda de Juan Carlos"


func open_menu() -> void:
	if menu_open:
		return
	menu = MenuScript.new()
	menu.tienda = self
	add_child(menu)
	menu_open = true
	_talk("¿Qué te pongo, chaval?")


func menu_closed() -> void:
	menu_open = false
	menu = null


# Estado de un producto para el jugador: "" si se puede comprar, o el motivo si no
func status(id: String) -> String:
	var p = game.player
	match id:
		"porro":
			if p.porro_t > 0.0:
				return "ACTIVO %d s" % ceili(p.porro_t)
		"cafe":
			if p.cafe_t > 0.0:
				return "ACTIVO %d s" % ceili(p.cafe_t)
		"gta":
			if p.has_gta:
				return "YA LO TIENES"
	if game.points < int(ITEMS[id]["price"]):
		return "TE FALTAN %d" % (int(ITEMS[id]["price"]) - game.points)
	return ""


# Compra un producto; devuelve lo que contesta Juan Carlos
func buy(id: String) -> String:
	var p = game.player
	if status(id) != "":
		var line := "Sin pasta no hay nada, chaval" if game.points < int(ITEMS[id]["price"]) else "Eso ya lo tienes, máquina"
		_talk(line)
		return line
	game.points -= int(ITEMS[id]["price"])
	var line := ""
	match id:
		"porro":
			p.use_porro()
			_smoke(p)
			line = "Eso es de lo bueno, eh"
		"cafe":
			p.use_cafe()
			line = "Recién hecho, cargadito"
		"gta":
			p.give_gta()
			line = "Disfrútalo, que ha costado lo suyo"
	_talk(line)
	return line


# Nube de humo delante de la cara al fumar
func _smoke(p) -> void:
	var cam: Camera3D = p.cam
	for i in 7:
		var s := U.sphere(get_parent(), 0.08, Vector3.ZERO, Color(0.85, 0.88, 0.85))
		s.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		s.material_override.albedo_color.a = 0.55
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s.global_position = cam.global_position - cam.global_transform.basis.z * 0.5 \
			+ Vector3(randf_range(-0.15, 0.15), randf_range(-0.15, 0.05), randf_range(-0.15, 0.15))
		var tw := s.create_tween().set_parallel()
		var dur := randf_range(1.2, 2.0)
		tw.tween_property(s, "scale", Vector3.ONE * randf_range(4.0, 7.0), dur)
		tw.tween_property(s, "global_position", s.global_position + Vector3(randf_range(-0.4, 0.4), 0.8, randf_range(-0.4, 0.4)), dur)
		tw.tween_property(s.material_override, "albedo_color:a", 0.0, dur)
		tw.chain().tween_callback(s.queue_free)

extends Node3D
# ---------------------------------------------------------------
# CESUR rediseñado. Plano (las salas y los huecos están en util.gd):
#
#   aula (empiezas) ─A─ pasillo de los aseos ─B─ distribuidor ─┬─ patio ─D─┐
#                        ├ aseo izq.  └ aseo dcho.             │            │
#                                                pasillo de la cafetería     │
#                                                  │ cafetería               │
#                                                pasillo largo ─ casino      │
#                                                  │ biblioteca              │
#                                                  C                         │
#                                                pasillo norte ── vestíbulo ─┘ (salida de emergencia)
#
# A, B, C y D son puertas de pago. El patio y el pasillo largo forman un bucle
# para escapar de las hordas. Todo de noche: luces que parpadean, focos rotos,
# sangre, vómito, barricadas y mensajes en las paredes.
# ---------------------------------------------------------------

const U = preload("res://scripts/nucleo/util.gd")
const G = preload("res://scripts/nucleo/graficos.gd")

const CEIL := 4.0
const ALTO_VESTIBULO := 6.5
const ALTO_PATIO := 7.0
const PUERTA_H := 2.6

const ZOCALO := Color("284d85")
const RODAPIE := Color(0.22, 0.22, 0.26)
const SANGRE := Color(0.32, 0.02, 0.02)
const BILIS := Color(0.48, 0.58, 0.12)
const MADERA := Color(0.42, 0.27, 0.14)
const TAQUILLA := Color(0.15, 0.3, 0.55)
const LUZ_FRIA := Color(0.85, 1.0, 0.92)
const LUZ_AULA := Color(1.0, 0.96, 0.88)
const LUZ_EMERG := Color(1.0, 0.12, 0.08)
# Modelos 3D del mapa (.glb con texturas y materiales). Si falta alguno se usa
# la versión hecha con cajas de antes.
const MODELOS := "res://modelos/mapa/"
# Texturas pintadas a mano del rediseño (cada una cubre tantos metros como se
# indica al pedirla, así las baldosas miden lo mismo en todas las salas).
const TEXTURAS := "res://modelos/mapa/texturas/"
const SUELO_M := 2.4
const PARED_M := 4.0
const LADRILLO_M := 3.0
const CONO_ALFA := 0.05

# Haz de luz falso bajo los paneles: se difumina hacia abajo y por los bordes
const SHADER_CONO := """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform float k = 0.05;
uniform vec3 color = vec3(1.0, 0.96, 0.88);
void fragment() {
	float borde = pow(abs(dot(NORMAL, VIEW)), 1.5);
	ALBEDO = color;
	ALPHA = k * (1.0 - UV.y) * borde;
}
"""
# Viñeta, grano y un toque verdoso de película por encima del 3D
const SHADER_POST := """
shader_type canvas_item;
uniform sampler2D pantalla : hint_screen_texture, filter_linear;
void fragment() {
	vec3 c = texture(pantalla, SCREEN_UV).rgb;
	float d = distance(SCREEN_UV, vec2(0.5));
	c *= 1.0 - smoothstep(0.32, 0.95, d);
	c = mix(c, c * vec3(0.92, 1.0, 0.95), 0.5);
	float g = fract(sin(dot(SCREEN_UV * vec2(1920.0, 1080.0) + fract(TIME) * 37.0, vec2(12.9898, 78.233))) * 43758.5453);
	COLOR = vec4(c + (g - 0.5) * 0.06, 1.0);
}
"""

var game
var _mats := {}
var _tex := {}
var _chispas: Array = []     # luces que casi siempre están apagadas y a veces chisporrotean
# Luces que fallan de vez en cuando: casi siempre estables y, cada 5-14 s,
# una ráfaga corta de parpadeos o un apagón de medio segundo a dos segundos.
# El panel del techo se apaga a la vez que la luz.
var _parpadeo: Array = []    # {luz, panel (material o null), base, estado, t, c}
var _escenas := {}           # nombre -> PackedScene (o null si no existe)
var _pulsos: Array = []      # luces de emergencia que laten: [luz, energía]
var _shader_cono: Shader
var _polvo: GPUParticles3D
var _post: CanvasLayer
var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	var cam := get_viewport().get_camera_3d()
	if cam != null:                 # el polvo flota alrededor de quien mira
		_polvo.global_position = Vector3(cam.global_position.x, 2.0, cam.global_position.z)
	for e: Array in _pulsos:
		e[0].light_energy = e[1] * (0.6 + 0.4 * sin(_t * 3.0))
	for l: Light3D in _chispas:
		if randf() < 0.01:
			l.light_energy = randf_range(1.5, 3.5)
		else:
			l.light_energy = lerpf(l.light_energy, 0.0, 12.0 * delta)
	for f: Dictionary in _parpadeo:
		var l: Light3D = f["luz"]
		var base: float = f["base"]
		f["t"] -= delta
		match int(f["estado"]):
			0:      # estable
				l.light_energy = base
				if f["t"] <= 0.0:
					f["estado"] = 2 if randf() < 0.25 else 1
					f["t"] = randf_range(0.5, 2.0) if f["estado"] == 2 else randf_range(0.3, 1.3)
			1:      # ráfaga de parpadeos
				f["c"] -= delta
				if f["c"] <= 0.0:
					f["c"] = randf_range(0.04, 0.12)
					l.light_energy = base * (randf_range(0.0, 0.2) if randf() < 0.55 else randf_range(0.8, 1.1))
				if f["t"] <= 0.0:
					f["estado"] = 0
					f["t"] = randf_range(5.0, 14.0)
			2:      # apagón corto
				l.light_energy = 0.0
				if f["t"] <= 0.0:
					f["estado"] = 1
					f["t"] = randf_range(0.2, 0.6)
		var panel = f["panel"]
		var k := l.light_energy / maxf(base, 0.001)
		if panel != null:
			panel.emission_energy_multiplier = 4.0 * k
		var cono = f["cono"]
		if cono != null:
			cono.set_shader_parameter("k", CONO_ALFA * k)


func _falla(l: Light3D, panel, base: float, cono = null) -> void:
	_parpadeo.append({"luz": l, "panel": panel, "cono": cono, "base": base, "estado": 0, "t": randf_range(2.0, 12.0), "c": 0.0})


func construir() -> void:
	seed(hash("cesur"))          # mismo instituto en todos los PCs
	for i in U.SALAS.size():
		if i != U.R_CASINO:      # el casino lo construye casino.gd
			_sala(i)
	_aula()
	_pasillo_aseos()
	_aseo(-1.0)
	_aseo(1.0)
	_distribuidor()
	_pasillo_cafeteria()
	_pasillo_largo()
	_cafeteria()
	_biblioteca()
	_pasillo_norte()
	_vestibulo()
	_patio()
	_crear_polvo()
	_crear_post()
	randomize()


# Noche cerrada: casi sin luz ambiente, niebla oscura y tono de película. Se
# aplica en cada cambio de calidad (F3).
func ajustar_gfx(env: Environment) -> void:
	var ultra: bool = G.nivel >= 2
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.fog_light_color = Color("06080a")
	env.fog_density = 0.028
	env.ambient_light_energy = 0.06 if ultra else 0.14
	env.sdfgi_energy = 0.35
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_hdr_threshold = 0.85
	env.glow_intensity = 0.8
	game.fog_d0 = env.fog_density
	game.fog_c0 = env.fog_light_color
	_polvo.emitting = G.nivel >= 1
	_post.visible = G.nivel >= 1


# Motas de polvo flotando alrededor de la cámara
func _crear_polvo() -> void:
	_polvo = GPUParticles3D.new()
	_polvo.amount = 350
	_polvo.lifetime = 9.0
	_polvo.preprocess = 9.0
	_polvo.local_coords = false
	_polvo.visibility_aabb = AABB(Vector3(-12, -4, -12), Vector3(24, 8, 24))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(9.0, 1.9, 9.0)
	pm.gravity = Vector3.ZERO
	pm.spread = 180.0
	pm.initial_velocity_min = 0.01
	pm.initial_velocity_max = 0.06
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.2, Color(1, 1, 1, 1))
	fade.add_point(0.8, Color(1, 1, 1, 1))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	_polvo.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.028, 0.028)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(0.85, 0.82, 0.75, 0.55)
	q.material = m
	_polvo.draw_pass_1 = q
	_polvo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_polvo)


func _crear_post() -> void:
	_post = CanvasLayer.new()
	_post.name = "Posproceso"
	_post.layer = -1             # por debajo del HUD
	add_child(_post)
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = Shader.new()
	sm.shader.code = SHADER_POST
	rect.material = sm
	_post.add_child(rect)


# =============================================================
# Estructura genérica: suelo, techo y paredes de cada sala
# =============================================================
func _alto(i: int) -> float:
	if i == U.R_VESTIBULO:
		return ALTO_VESTIBULO
	if i == U.R_PATIO:
		return ALTO_PATIO
	return CEIL


func _sala(i: int) -> void:
	var r: Rect2 = U.SALAS[i]
	var h := _alto(i)
	var c := r.get_center()
	var exterior := i == U.R_PATIO
	# suelo hasta la mitad de las paredes (así no se solapa con el de al lado)
	var suelo_m := _suelo_mat(i)
	_solido(Vector3(r.size.x + 0.4, 0.2, r.size.y + 0.4), Vector3(c.x, -0.1, c.y), suelo_m)
	if not exterior:
		var t := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(r.size.x + 0.4, r.size.y + 0.4)
		t.mesh = pm
		t.material_override = _png("techo", SUELO_M, 0.95)
		t.position = Vector3(c.x, h, c.y)
		t.rotation_degrees = Vector3(180, 0, 0)
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		t.add_to_group("techos")
		add_child(t)
		G.sonda(self, Vector3(c.x, h / 2.0, c.y), Vector3(r.size.x, h, r.size.y))
	# paredes: lado sur, norte, oeste y este (media pared de 0,2 m por sala)
	_lado(i, "z", r.position.y - 0.2, r.position.x - 0.2, r.end.x + 0.2, r.position.y - 0.1, 1.0, h)
	_lado(i, "z", r.end.y + 0.2, r.position.x - 0.2, r.end.x + 0.2, r.end.y + 0.1, -1.0, h)
	_lado(i, "x", r.position.x - 0.2, r.position.y, r.end.y, r.position.x - 0.1, 1.0, h)
	_lado(i, "x", r.end.x + 0.2, r.position.y, r.end.y, r.end.x + 0.1, -1.0, h)


# Una pared: eje de la línea, línea, tramo [a, b], centro de la media pared,
# hacia dónde mira la cara interior (+1/-1) y altura
func _lado(i: int, eje: String, linea: float, a: float, b: float, centro: float, cara: float, h: float) -> void:
	var huecos: Array = []
	for hu: Array in U.HUECOS:
		if (hu[1] == i or hu[2] == i) and hu[3] == eje and absf(float(hu[4]) - linea) < 0.05:
			huecos.append(hu)
	huecos.sort_custom(func(p, q): return p[5] < q[5])
	var tramos: Array = []
	var cur := a
	for hu: Array in huecos:
		var s0: float = hu[5]
		var s1: float = hu[6]
		if s0 > cur:
			tramos.append([cur, s0])
		cur = maxf(cur, s1)
		var dintel: float = hu[7]
		if dintel > 0.0 and dintel < h:
			_pared(eje, centro, s0, s1, dintel, h, cara, i, false)
	if b > cur:
		tramos.append([cur, b])
	for t: Array in tramos:
		_pared(eje, centro, t[0], t[1], 0.0, h, cara, i, true)


func _pared(eje: String, centro: float, a: float, b: float, y0: float, y1: float, cara: float, sala: int, deco: bool) -> void:
	var largo := b - a
	if largo < 0.01:
		return
	var mid := (a + b) / 2.0
	var exterior := sala == U.R_PATIO
	var pm := _png("ladrillo", LADRILLO_M, 0.95) if exterior else _png(_tex_pared(sala), PARED_M, 0.85)
	var size := Vector3(0.2, y1 - y0, largo) if eje == "x" else Vector3(largo, y1 - y0, 0.2)
	var pos := Vector3(centro, (y0 + y1) / 2.0, mid) if eje == "x" else Vector3(mid, (y0 + y1) / 2.0, centro)
	_solido(size, pos, pm)
	if not deco:
		return
	# zócalo de color y rodapié en la cara interior
	var face := centro + cara * 0.105
	var zh := 1.1 if not exterior else 0.0
	if zh > 0.0:
		var zs := Vector3(0.012, zh, largo) if eje == "x" else Vector3(largo, zh, 0.012)
		var zp := Vector3(face, zh / 2.0, mid) if eje == "x" else Vector3(mid, zh / 2.0, face)
		U.box_m(self, zs, zp, _m(_color_zocalo(sala)))
		var fs := Vector3(0.016, 0.06, largo) if eje == "x" else Vector3(largo, 0.06, 0.016)
		var fp := Vector3(face, zh, mid) if eje == "x" else Vector3(mid, zh, face)
		U.box_m(self, fs, fp, _m(_color_zocalo(sala).darkened(0.4)))
	var rs := Vector3(0.02, 0.12, largo) if eje == "x" else Vector3(largo, 0.12, 0.02)
	var rp := Vector3(face, 0.06, mid) if eje == "x" else Vector3(mid, 0.06, face)
	U.box_m(self, rs, rp, _m(RODAPIE))


func _tex_pared(sala: int) -> String:
	match sala:
		U.R_ASEO_I, U.R_ASEO_D:
			return "pared_c9d9db"
		U.R_CAFETERIA:
			return "pared_e0cc9e"
		U.R_BIBLIOTECA:
			return "pared_b39e80"
		U.R_VESTIBULO:
			return "pared_cdc7bd"
	return "pared_d6d1bf"


func _color_zocalo(sala: int) -> Color:
	match sala:
		U.R_ASEO_I, U.R_ASEO_D:
			return Color("8cb2b8")
		U.R_CAFETERIA:
			return Color("9e381e")
		U.R_BIBLIOTECA:
			return Color("52331a")
		U.R_VESTIBULO:
			return Color("40404c")
	return ZOCALO


func _suelo_mat(sala: int) -> StandardMaterial3D:
	match sala:
		U.R_PATIO:
			return _png("asf", SUELO_M, 0.95)
		U.R_ASEO_I, U.R_ASEO_D:
			return _png("azu", SUELO_M, 0.25)
		U.R_BIBLIOTECA:
			return _png("moq", SUELO_M, 1.0)
		U.R_CAFETERIA:
			return _png("ter", SUELO_M, 0.35)
		U.R_AULA:
			return _png("aula", SUELO_M, 0.3)
	return _png("pas", SUELO_M, 0.3)


# =============================================================
# AULA: donde empiezas
# =============================================================
func _aula() -> void:
	# 8 paneles de luz: dos fallan (uno parpadea, otro está descolgado)
	for lx in [-4.5, 4.5]:
		for lz in [-6.0, -2.0, 2.0, 6.0]:
			if lx > 0.0 and lz == 2.0:
				_panel_roto(Vector3(lx, CEIL, lz))
			else:
				_luz(Vector3(lx, CEIL - 0.3, lz), 2.2, 0.9, 11.0, LUZ_AULA, lx < 0.0 and lz == 6.0, 2)
	# pizarra con un aviso escrito con prisa
	_b(Vector3(3.4, 1.8, 0.06), Vector3(-5.5, 1.7, -7.97), Color(0.6, 0.6, 0.62))
	_b(Vector3(3.2, 1.6, 0.03), Vector3(-5.5, 1.7, -7.93), Color(0.97, 0.97, 0.97))
	_texto("NO SALGÁIS\nNO HAGÁIS RUIDO", Vector3(-5.5, 1.85, -7.9), 0.0, 46, Color(0.55, 0.02, 0.02))
	_texto("lunes 25", Vector3(-6.6, 2.35, -7.9), 0.0, 22, Color(0.1, 0.15, 0.5))
	# televisión, proyector y reloj parado
	_b(Vector3(2.3, 1.3, 0.12), Vector3(0, 1.75, -7.94), Color(0.05, 0.05, 0.06))
	var tv := _b(Vector3(2.15, 1.15, 0.02), Vector3(0, 1.75, -7.87), Color(0.12, 0.25, 0.18), true)
	tv.material_override.emission_energy_multiplier = 0.6
	_texto("SIN SEÑAL", Vector3(0, 1.75, -7.85), 0.0, 40, Color(0.6, 1.0, 0.7))
	_b(Vector3(0.5, 0.18, 0.4), Vector3(0, 3.55, -1.0), Color(0.85, 0.85, 0.86))
	_b(Vector3(0.05, 0.25, 0.05), Vector3(0, 3.82, -1.0), Color(0.3, 0.3, 0.32))
	_reloj(Vector3(8.97, 3.0, -2.5), -90.0)
	# letrero CESUR (mayúsculas, azul oscuro) encima de la tele
	var cesur := Label3D.new()
	cesur.text = "CESUR"
	cesur.font_size = 220
	cesur.pixel_size = 0.004
	cesur.outline_size = 0
	cesur.modulate = Color(0.02, 0.08, 0.38)
	var bold := SystemFont.new()
	bold.font_weight = 900
	cesur.font = bold
	cesur.position = Vector3(0, 3.05, -7.97)
	add_child(cesur)
	# armario de Jorge con cartel encima
	game._build_armario()
	_b(Vector3(2.0, 1.0, 0.03), Vector3(6.7, 2.65, -7.97), Color(0.96, 0.96, 0.96))
	_texto("Mobbeel\nInnovation Challenge\n350 €\nSegundo premio", Vector3(6.7, 2.65, -7.94), 0.0, 40, Color(0.15, 0.1, 0.25), 0.0035)
	# una columna de 6 filas de mesas juntas (lado izquierdo)
	for row_z in [-5.2, -3.0, -0.8, 1.4, 3.6, 5.8]:
		if not _pupitres(-4.9, row_z):
			game._desk_block(-4.9, row_z)
	# ventanas tapiadas con tablas en la pared izquierda
	for wz in [-5.0, 0.0, 5.0]:
		_ventana(Vector3(-8.99, 2.2, wz), 90.0, 2.6, 1.4, true)
	var luna := SpotLight3D.new()                  # la luz de la luna se cuela entre las tablas
	luna.position = Vector3(-8.6, 3.0, 0.0)
	luna.rotation_degrees = Vector3(-35.0, -90.0, 0.0)
	luna.light_color = Color(0.55, 0.65, 1.0)
	luna.light_energy = 0.8
	luna.spot_range = 9.0
	luna.spot_angle = 30.0
	luna.light_volumetric_fog_energy = 3.0
	add_child(luna)
	# lado derecho revuelto: sillas tiradas, mesa volcada, mochilas y papeles
	var silla := Color(0.1, 0.15, 0.35)
	for p in [Vector3(3.5, 0.0, 2.5), Vector3(6.8, 0.0, -1.0), Vector3(1.5, 0.0, -3.5), Vector3(7.2, 0.0, 5.5)]:
		_silla_tirada(p, randf() * 360.0, silla)
	var mesa := _solido(Vector3(1.3, 0.05, 0.9), Vector3(5.6, 0.45, 3.6), _m(Color(0.92, 0.92, 0.9)))
	mesa.rotation_degrees = Vector3(0, 25.0, 82.0)
	for p in [Vector3(2.0, 0.0, 4.8), Vector3(7.6, 0.0, 1.5), Vector3(4.2, 0.0, -2.2)]:
		_mochila(p)
	_papeles(Rect2(0.5, -6.5, 8.0, 13.0), 40)
	# sangre: rastro hacia la puerta, mano en la pared y un charco de vómito
	_rastro(Vector3(6.0, 0.0, -0.5), Vector3(1.0, 0.0, 7.6), 6)
	_mancha(Vector3(8.99, 1.4, 3.8), Vector2(0.7, 0.9), "+x", "mano")
	_mancha(Vector3(3.2, 0.0, 0.4), Vector2(1.8, 1.4), "y", "vomito")
	# extintor junto a la puerta y cartel de salida
	_extintor(Vector3(8.85, 0.0, 6.8))
	_salida(Vector3(0, 2.85, 7.97), 180.0)


# =============================================================
# Pasillo de los aseos (tienda de Juan Carlos en la pared derecha)
# =============================================================
func _pasillo_aseos() -> void:
	_luz(Vector3(0, CEIL - 0.3, 13.0), 1.2, 0.8, 10.0, LUZ_FRIA, true, 1)
	_luz(Vector3(0, CEIL - 0.3, 19.5), 1.2, 0.8, 10.0, LUZ_FRIA, false, 0)
	for s in [-1.0, 1.0]:
		var a := _texto("ASEOS", Vector3(s * 3.98, 2.85, U.WC_Z), -s * 90.0, 40, Color(0.05, 0.15, 0.4), 0.005)
		a.outline_size = 0
		_marco(Vector3(s * 4.2, 0.0, U.WC_Z), "x", 2.2, 2.5)
	_corcho(Vector3(-3.98, 1.6, 16.5), 90.0)
	_mancha(Vector3(-3.99, 1.2, 19.0), Vector2(1.2, 1.6), "-x", "salpicadura")
	_mancha(Vector3(0.5, 0.0, 15.0), Vector2(1.0, 3.0), "y", "arrastre")
	_papeles(Rect2(-3.5, 9.0, 7.0, 12.0), 14)
	_extintor(Vector3(-3.85, 0.0, 21.0))
	_texto("ZONA DE AULAS", Vector3(0, 3.3, 21.95), 180.0, 34, Color(0.1, 0.12, 0.2), 0.005)


func _aseo(s: float) -> void:
	var h := CEIL
	var cab := Color(0.3, 0.45, 0.6)
	var white := Color(0.95, 0.96, 0.97)
	var cx := U.WC_X
	var x0 := U.HALL + 0.4
	var x1 := cx + 3.4
	_luz(Vector3(s * cx, h - 0.3, 12.4), 2.0, 1.0, 9.0, Color(0.85, 0.95, 1.0), s < 0.0, 1)
	# cabinas con inodoro (la de la punta tiene la puerta arrancada)
	for i in 5:
		_b(Vector3(0.05, 2.0, 1.5), Vector3(s * (x0 + 0.4 + i * 1.2), 1.0, 15.65), cab)
	for i in 4:
		var xl := x0 + 1.0 + i * 1.2
		if i == 3:
			var puerta := _b(Vector3(1.1, 1.8, 0.04), Vector3(s * xl, 0.05, 14.2), cab)
			puerta.rotation_degrees = Vector3(-88.0, 12.0, 0)
		else:
			_b(Vector3(1.1, 1.8, 0.04), Vector3(s * xl, 1.0, 14.9), cab)
		_b(Vector3(0.4, 0.4, 0.5), Vector3(s * xl, 0.2, 16.05), white)
		_b(Vector3(0.4, 0.45, 0.18), Vector3(s * xl, 0.6, 16.28), white)
	# lavabos con espejo en la pared exterior (el espejo, rajado)
	_solido(Vector3(0.5, 0.85, 3.6), Vector3(s * (x1 - 0.3), 0.425, 11.4), _m(white))
	for i in 3:
		_b(Vector3(0.4, 0.08, 0.4), Vector3(s * (x1 - 0.35), 0.87, 10.4 + i * 1.1), Color(0.75, 0.85, 0.9))
	var mirror := _b(Vector3(0.04, 1.0, 3.4), Vector3(s * (x1 - 0.03), 1.9, 11.4), Color(0.9, 0.93, 0.95))
	mirror.material_override = mirror.material_override.duplicate()
	mirror.material_override.metallic = 1.0
	mirror.material_override.roughness = 0.02
	for k in 5:
		var raja := _b(Vector3(0.01, 0.012, randf_range(0.3, 0.8)), Vector3(s * (x1 - 0.055), 1.9 + randf_range(-0.3, 0.3), 11.9 + randf_range(-0.3, 0.3)), Color(0.15, 0.15, 0.16))
		raja.rotation_degrees.x = randf_range(-70.0, 70.0)
	# agua por el suelo, sangre en una cabina y una pintada
	_mancha(Vector3(s * 7.0, 0.0, 12.0), Vector2(2.5, 2.0), "y", "agua")
	_mancha(Vector3(s * (x0 + 1.0), 0.0, 15.8), Vector2(1.2, 1.2), "y", "charco")
	var pared_x := s * (x1 - 0.0)
	var t := _texto("ELLOS OYEN", Vector3(pared_x - s * 0.01, 2.6, 14.3), -s * 90.0, 40, SANGRE.lightened(0.15), 0.005)
	t.outline_size = 0


# =============================================================
# Distribuidor: escalera derrumbada, máquinas y salida al patio
# =============================================================
func _distribuidor() -> void:
	_luz(Vector3(-2.5, CEIL - 0.3, 25.5), 1.6, 0.8, 10.0, LUZ_FRIA, true, 1)
	_luz(Vector3(3.5, CEIL - 0.3, 25.0), 1.6, 0.8, 10.0, LUZ_FRIA, false, 0)
	_emergencia(Vector3(0.0, 3.6, 29.9))
	# escalera a la primera planta, hundida y cerrada con cinta
	for k in 8:
		var y := 0.1 + k * 0.2
		_solido(Vector3(0.6, y * 2.0, 2.0), Vector3(-1.2 + k * 0.6, y, 29.0), _m(Color(0.6, 0.58, 0.55)))
	_solido(Vector3(1.6, 1.7, 2.0), Vector3(4.3, 0.85, 29.0), _m(Color(0.6, 0.58, 0.55)))
	for k in 7:                                     # escombros sobre el rellano
		var e := _b(Vector3(randf_range(0.4, 0.9), randf_range(0.2, 0.5), randf_range(0.4, 0.9)),
			Vector3(randf_range(2.6, 5.4), 1.85 + randf() * 0.4, randf_range(28.2, 29.8)), Color(0.5, 0.48, 0.45))
		e.rotation_degrees = Vector3(randf() * 40.0, randf() * 90.0, randf() * 40.0)
	var techo_caido := _b(Vector3(2.4, 0.08, 1.2), Vector3(3.2, 2.9, 28.6), Color(0.86, 0.86, 0.82))
	techo_caido.rotation_degrees = Vector3(18.0, 0, -25.0)
	_cinta(Vector3(-1.8, 1.0, 27.9), Vector3(5.6, 1.0, 27.9))
	_texto("PRIMERA PLANTA\nCERRADA", Vector3(1.0, 1.55, 27.92), 180.0, 30, Color(0.1, 0.1, 0.1), 0.004)
	# máquinas de bebidas a los lados de la puerta B
	_maquina(Vector3(-5.1, 0.0, 22.7), 0.0, true)
	_maquina(Vector3(5.1, 0.0, 22.7), 0.0, false)
	# cristales de la puerta del patio rotos y carteles
	_marco(Vector3(-6.2, 0.0, 26.1), "x", 4.6, 3.0)
	_cristales(Rect2(-5.8, 24.0, 2.5, 4.2), 18)
	_texto("PATIO", Vector3(-5.98, 3.4, 26.1), 90.0, 40, Color(0.05, 0.15, 0.4), 0.005)
	_texto("CAFETERÍA →", Vector3(5.98, 3.4, 26.0), -90.0, 34, Color(0.05, 0.15, 0.4), 0.005)
	_mancha(Vector3(-3.0, 0.0, 24.5), Vector2(2.2, 1.6), "y", "charco")
	_rastro(Vector3(-3.0, 0.0, 24.5), Vector3(-5.8, 0.0, 26.5), 3)
	_papeles(Rect2(-5.0, 22.8, 10.0, 4.5), 12)


# =============================================================
# Pasillo de la cafetería
# =============================================================
func _pasillo_cafeteria() -> void:
	for lx in [9.5, 14.5, 19.5]:
		_luz(Vector3(lx, CEIL - 0.3, 26.0), 1.2, 0.8, 10.0, LUZ_FRIA, lx == 14.5, 0)
	# fila de máquinas expendedoras contra la pared sur (en lugar de las taquillas)
	var fila_caf := [[8.2, "snacks", false], [9.25, "bebidas", false], [10.3, "snacks", true],
		[18.5, "bebidas", false], [19.55, "snacks", false], [20.6, "bebidas", true]]
	for f: Array in fila_caf:
		_maquina_tipo(Vector3(f[0], 0.0, 23.45), 0.0, f[1], f[2])
	_marco(Vector3(13.0, 0.0, 29.2), "z", 4.0, 2.8)
	_texto("CAFETERÍA", Vector3(13.0, 3.3, 28.98), 180.0, 40, Color(0.5, 0.15, 0.05), 0.005)
	_mancha(Vector3(16.0, 0.0, 26.5), Vector2(1.0, 6.0), "y", "arrastre", 90.0)
	_mancha(Vector3(21.3, 1.4, 28.99), Vector2(0.7, 0.9), "+z", "mano")
	_papeles(Rect2(7.0, 23.5, 14.0, 5.0), 12)


# =============================================================
# Pasillo largo: taquillas, casino, la puerta oscura del susto
# =============================================================
func _pasillo_largo() -> void:
	var lx := 25.1
	var zs := [26.0, 31.2, 36.4, 41.6, 46.8, 52.0, 57.2, 62.4, 67.6]
	for i in zs.size():
		var lz: float = zs[i]
		if i == 3 or i == 6:
			_panel_roto(Vector3(lx, CEIL, lz))
		else:
			_luz(Vector3(lx, CEIL - 0.3, lz), 1.2, 0.8, 11.0, LUZ_FRIA, i == 1 or i == 5 or i == 8, 1 if i % 2 == 0 else 0)
	_emergencia(Vector3(27.9, 3.4, 58.0))
	# taquillas en la pared oeste (algunas abiertas)
	# máquinas expendedoras contra la pared oeste (en lugar de las taquillas);
	# entre 50,6 y 55 queda un hueco (ahí están los cables de la misión)
	var fila_larga := [[31.0, "snacks", false], [32.05, "bebidas", false], [33.1, "snacks", false],
		[37.5, "bebidas", true], [38.55, "snacks", false],
		[48.0, "bebidas", false], [49.05, "snacks", true], [50.1, "bebidas", false],
		[55.5, "snacks", false], [56.55, "bebidas", false], [57.6, "snacks", false]]
	for f: Array in fila_larga:
		_maquina_tipo(Vector3(22.65, 0.0, f[0]), 90.0, f[1], f[2])
	# puertas de otras aulas en la pared este
	var n := 12
	for dz in [30.0, 35.5, 64.8, 68.0]:
		_puerta_aula(Vector3(28.0, 0.0, dz), -90.0, n)
		n += 1
	# la puerta oscura de la que sale el susto
	_solido(Vector3(0.1, 2.6, 1.4), Vector3(27.96, 1.3, 58.0), _m(Color(0.0, 0.0, 0.0)))
	_marco(Vector3(28.1, 0.0, 58.0), "x", 1.4, 2.6)
	_mancha(Vector3(27.99, 1.0, 59.3), Vector2(0.8, 1.6), "+x", "salpicadura")
	# bancos pegados a la pared este (la ganzúa puede estar debajo del primero)
	_banco(Vector3(27.65, 0.0, 52.4), 90.0)
	_banco(Vector3(27.65, 0.0, 48.0), 90.0)
	# carro de limpieza volcado, cartel de suelo mojado y pintadas
	var carro := _solido(Vector3(0.6, 0.9, 1.0), Vector3(24.2, 0.3, 39.0), _m(Color(0.7, 0.6, 0.1)))
	carro.rotation_degrees = Vector3(0, 30.0, 80.0)
	_suelo_mojado(Vector3(26.5, 0.0, 38.0))
	_mancha(Vector3(25.0, 0.0, 39.5), Vector2(2.5, 2.5), "y", "agua")
	var corred := _texto("CORRED", Vector3(22.21, 2.9, 36.0), 90.0, 90, SANGRE.lightened(0.1), 0.006)
	corred.outline_size = 0
	_rastro(Vector3(25.0, 0.0, 29.0), Vector3(26.5, 0.0, 57.5), 12)
	_mancha(Vector3(25.5, 0.0, 66.0), Vector2(2.0, 1.6), "y", "vomito")
	_papeles(Rect2(22.8, 24.0, 4.8, 45.0), 30)
	# barricada de mesas junto a la puerta C (sin cerrar el paso)
	for k in 3:
		var m := _solido(Vector3(1.3, 0.75, 0.7), Vector3(23.3, 0.375 + k * 0.0, 67.5 - k * 0.9), _m(Color(0.88, 0.88, 0.86)))
		m.rotation_degrees.y = randf_range(-20.0, 20.0)
	var tumbada := _b(Vector3(1.3, 0.05, 0.7), Vector3(23.5, 1.0, 66.6), Color(0.88, 0.88, 0.86))
	tumbada.rotation_degrees = Vector3(0, 10.0, 30.0)


# =============================================================
# Cafetería
# =============================================================
func _cafeteria() -> void:
	for lx in [10.0, 17.5]:
		for lz in [34.0, 42.0, 50.0]:
			if lx > 15.0 and lz == 42.0:
				_panel_roto(Vector3(lx, CEIL, lz))
			else:
				_luz(Vector3(lx, CEIL - 0.3, lz), 1.8, 1.0, 11.0, Color(1.0, 0.92, 0.75), lx < 15.0 and lz == 50.0, 1 if lz == 42.0 else 0)
	# barra con mampara, bandejas y vitrina iluminada
	_solido(Vector3(12.0, 1.0, 1.0), Vector3(14.0, 0.5, 53.9), _m(Color(0.55, 0.55, 0.58)))
	_b(Vector3(12.0, 0.04, 1.1), Vector3(14.0, 1.02, 53.9), Color(0.75, 0.75, 0.78))
	var vidrio := _b(Vector3(12.0, 0.5, 0.02), Vector3(14.0, 1.45, 53.5), Color(0.7, 0.85, 0.9))
	vidrio.material_override = vidrio.material_override.duplicate()
	vidrio.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	vidrio.material_override.albedo_color.a = 0.25
	var vitrina := _b(Vector3(3.0, 0.3, 0.6), Vector3(10.0, 1.2, 54.1), Color(1.0, 0.75, 0.45), true)
	vitrina.material_override.emission_energy_multiplier = 0.8
	for k in 8:
		_b(Vector3(0.45, 0.03, 0.32), Vector3(12.0 + k * 1.0, 1.06, 53.8), [Color(0.6, 0.15, 0.1), Color(0.15, 0.3, 0.55)][k % 2])
	_texto("MENÚ DEL DÍA\nLentejas · Croquetas · Flan\n3,50 €", Vector3(16.0, 2.6, 55.94), 180.0, 34, Color(0.95, 0.95, 0.9), 0.005)
	_b(Vector3(3.6, 1.2, 0.04), Vector3(16.0, 2.6, 55.98), Color(0.08, 0.1, 0.08))
	# mesas largas con bancos (algunas volcadas)
	var mesa_c := Color(0.75, 0.62, 0.42)
	for p in [Vector2(10.0, 35.0), Vector2(14.5, 35.0), Vector2(19.0, 35.0), Vector2(10.0, 41.5), Vector2(14.5, 41.5), Vector2(10.0, 48.0), Vector2(14.5, 48.0), Vector2(19.0, 48.5)]:
		var volcada: bool = p == Vector2(14.5, 41.5) or p == Vector2(19.0, 48.5)
		_mesa_cafeteria(Vector3(p.x, 0.0, p.y), mesa_c, volcada)
	# máquinas en la pared oeste y papeleras
	_maquina(Vector3(6.85, 0.0, 45.0), 90.0, true)
	_maquina(Vector3(6.85, 0.0, 46.4), 90.0, false)
	for p in [Vector3(21.3, 0.0, 30.2), Vector3(7.0, 0.0, 30.2)]:
		U.cylinder(self, 0.25, 0.8, p + Vector3(0, 0.4, 0), Color(0.2, 0.35, 0.2))
	var papelera := U.cylinder(self, 0.25, 0.8, Vector3(19.0, 0.25, 31.0), Color(0.2, 0.35, 0.2))
	papelera.rotation_degrees.z = 90.0
	# vómito por todas partes (aquí se pusieron malos los primeros)
	for p in [Vector3(12.0, 0.0, 38.0), Vector3(18.0, 0.0, 44.0), Vector3(9.0, 0.0, 51.5), Vector3(16.5, 0.0, 31.5)]:
		_mancha(p, Vector2(randf_range(1.4, 2.4), randf_range(1.2, 2.0)), "y", "vomito", randf() * 360.0)
	_mancha(Vector3(21.79, 1.6, 50.0), Vector2(1.6, 1.6), "+x", "salpicadura")
	_papeles(Rect2(7.0, 30.0, 14.0, 22.0), 25)


func _mesa_cafeteria(p: Vector3, c: Color, volcada: bool) -> void:
	var n := _modelo("mesa_cafeteria_vacia" if volcada else "mesa_cafeteria", p, 0.0)
	if n != null:
		if volcada:
			n.rotation_degrees = Vector3(0, randf_range(-30.0, 30.0), 85.0)
			_apoyar(n)
			_choque(Vector3(1.0, 1.9, 3.6), p + Vector3(0, 0.95, 0), n.rotation_degrees.y)
		else:
			_choque(Vector3(1.0, 0.06, 3.6), p + Vector3(0, 0.76, 0), 0.0)
			for sx in [-0.85, 0.85]:
				_choque(Vector3(0.35, 0.47, 3.4), p + Vector3(sx, 0.235, 0), 0.0)
		return
	var root := Node3D.new()
	root.position = p
	add_child(root)
	if volcada:
		root.rotation_degrees = Vector3(0, randf_range(-30.0, 30.0), 85.0)
		root.position.y = 0.5
	_solido_en(root, Vector3(1.0, 0.06, 3.6), Vector3(0, 0.75, 0), _m(c))
	for sz in [-1.4, 1.4]:
		U.box_m(root, Vector3(0.08, 0.72, 0.08), Vector3(0, 0.36, sz), _m(Color(0.3, 0.3, 0.32)))
	if not volcada:
		for sx in [-0.85, 0.85]:
			_solido_en(root, Vector3(0.35, 0.05, 3.4), Vector3(sx, 0.45, 0), _m(c.darkened(0.2)))
		for k in 3:
			U.box_m(root, Vector3(0.4, 0.03, 0.3), Vector3(randf_range(-0.2, 0.2), 0.79, randf_range(-1.4, 1.4)), _m(Color(0.6, 0.15, 0.1)))


# =============================================================
# Biblioteca
# =============================================================
func _biblioteca() -> void:
	for p in [Vector3(10.0, CEIL - 0.3, 60.0), Vector3(16.5, CEIL - 0.3, 60.0), Vector3(10.0, CEIL - 0.3, 66.5), Vector3(16.5, CEIL - 0.3, 66.5)]:
		_luz(p, 1.4, 0.8, 9.0, Color(1.0, 0.85, 0.6), p.x > 15.0 and p.z > 65.0, 0)
	# estanterías en dos filas (una se ha caído) y libros por el suelo
	_estanteria(Vector3(13.0, 0.0, 58.6), 10.0, false)
	_estanteria(Vector3(13.0, 0.0, 67.4), 6.0, false)
	_estanteria(Vector3(8.5, 0.0, 67.0), 3.0, true)
	# mesa de lectura con flexo verde encendido
	_solido(Vector3(4.0, 0.06, 1.4), Vector3(13.5, 0.75, 63.0), _m(MADERA))
	for sx in [-1.8, 1.8]:
		for sz in [-0.55, 0.55]:
			_b(Vector3(0.08, 0.72, 0.08), Vector3(13.5 + sx, 0.36, 63.0 + sz), MADERA.darkened(0.4))
	_b(Vector3(0.3, 0.12, 0.2), Vector3(12.2, 0.93, 63.0), Color(0.1, 0.4, 0.15), true)
	var flexo := OmniLight3D.new()
	flexo.position = Vector3(12.2, 1.1, 63.0)
	flexo.light_color = Color(0.6, 1.0, 0.6)
	flexo.light_energy = 0.9
	flexo.omni_range = 4.0
	add_child(flexo)
	for p in [Vector3(12.0, 0.0, 61.8), Vector3(15.0, 0.0, 64.3)]:
		_silla_tirada(p, randf() * 360.0, MADERA)
	# mostrador junto a la entrada y cartel
	_solido(Vector3(1.0, 1.0, 2.4), Vector3(19.8, 0.5, 67.4), _m(MADERA.darkened(0.2)))
	_texto("SILENCIO", Vector3(21.79, 3.0, 66.5), -90.0, 50, Color(0.3, 0.05, 0.05), 0.005)
	_marco(Vector3(22.0, 0.0, 62.5), "x", 3.0, 2.6)
	_texto("BIBLIOTECA", Vector3(22.21, 3.0, 62.5), 90.0, 34, Color(0.05, 0.15, 0.4), 0.005)
	_libros_suelo(Rect2(8.0, 59.5, 12.0, 7.0), 30)
	_mancha(Vector3(17.5, 0.0, 61.0), Vector2(2.0, 2.0), "y", "charco")


# =============================================================
# Pasillo norte: vitrinas de trofeos y ventanas a la calle
# =============================================================
func _pasillo_norte() -> void:
	for lx in [-1.0, 5.5, 12.0, 18.5, 25.0]:
		_luz(Vector3(lx, CEIL - 0.3, 73.1), 1.2, 0.8, 10.0, LUZ_FRIA, lx == 18.5, 0)
	for wx in [14.5, 19.5, 24.5]:
		_ventana(Vector3(wx, 2.1, 75.99), 180.0, 3.0, 1.6, wx == 19.5)
	var luna := SpotLight3D.new()
	luna.position = Vector3(19.5, 3.4, 75.6)
	luna.rotation_degrees = Vector3(-50.0, 0.0, 0.0)
	luna.light_color = Color(0.5, 0.6, 1.0)
	luna.light_energy = 0.7
	luna.spot_range = 8.0
	luna.spot_angle = 40.0
	add_child(luna)
	_vitrina(Vector3(2.0, 0.0, 70.45))
	_marco(Vector3(25.1, 0.0, 70.0), "z", 5.8, 3.4)
	_texto("AYUDA", Vector3(8.0, 2.4, 70.21), 0.0, 120, SANGRE.lightened(0.1), 0.006)
	_rastro(Vector3(24.0, 0.0, 71.0), Vector3(4.0, 0.0, 75.5), 10)
	_papeles(Rect2(-3.5, 70.8, 31.0, 4.6), 18)


# =============================================================
# Vestíbulo de la entrada: doble altura, conserjería, escalera
# =============================================================
func _vestibulo() -> void:
	var h := ALTO_VESTIBULO
	for lz in [80.5, 88.0, 95.0]:
		for lx in [-6.0, 6.0]:
			_luz(Vector3(lx, h - 0.3, lz), 1.6, 1.6, 12.0, LUZ_AULA, lx > 0.0 and lz == 88.0, 1 if lz == 88.0 else 0)
	_emergencia(Vector3(-2.5, 3.6, 98.3))
	_emergencia(Vector3(2.5, 3.6, 98.3))
	# columnas
	for p in [Vector2(-5.0, 82.0), Vector2(5.0, 82.0), Vector2(-5.0, 92.0), Vector2(5.0, 92.0)]:
		_solido(Vector3(0.7, h, 0.7), Vector3(p.x, h / 2.0, p.y), _m(Color(0.74, 0.72, 0.68)))
	# salida de emergencia (la puerta la pone la misión) y letras del instituto
	_salida(Vector3(0, 3.1, 98.37), 180.0)
	var cesur := Label3D.new()
	cesur.text = "CESUR"
	cesur.font_size = 300
	cesur.pixel_size = 0.006
	cesur.outline_size = 0
	cesur.modulate = Color(0.02, 0.08, 0.38)
	var bold := SystemFont.new()
	bold.font_weight = 900
	cesur.font = bold
	cesur.position = Vector3(0, 5.0, 98.37)
	cesur.rotation_degrees.y = 180.0
	add_child(cesur)
	# puertas de cristal de la entrada tapiadas con tablas
	for wx in [-6.5, 6.5]:
		_ventana(Vector3(wx, 1.6, 98.39), 180.0, 4.0, 2.8, true)
	# conserjería (a la izquierda): mostrador, cristal, monitor y llaves
	_solido(Vector3(5.6, 1.05, 0.9), Vector3(-9.2, 0.525, 89.0), _m(Color(0.45, 0.32, 0.2)))
	_b(Vector3(5.7, 0.05, 1.0), Vector3(-9.2, 1.07, 89.0), Color(0.3, 0.2, 0.12))
	var cristal := _b(Vector3(5.6, 1.4, 0.03), Vector3(-9.2, 1.8, 88.6), Color(0.7, 0.85, 0.9))
	cristal.material_override = cristal.material_override.duplicate()
	cristal.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cristal.material_override.albedo_color.a = 0.18
	_b(Vector3(0.6, 0.4, 0.05), Vector3(-10.8, 1.35, 89.3), Color(0.05, 0.05, 0.06))
	var pantalla := _b(Vector3(0.55, 0.35, 0.01), Vector3(-10.8, 1.35, 89.27), Color(0.2, 0.5, 1.0), true)
	pantalla.material_override.emission_energy_multiplier = 0.7
	_b(Vector3(0.04, 0.8, 1.2), Vector3(-11.97, 1.8, 90.5), Color(0.35, 0.22, 0.1))
	for k in 8:
		_b(Vector3(0.03, 0.08, 0.02), Vector3(-11.94, 1.6 + (k / 4) * 0.3, 90.1 + (k % 4) * 0.25), Color(0.8, 0.7, 0.3))
	_texto("CONSERJERÍA", Vector3(-9.2, 2.85, 88.55), 180.0, 34, Color(0.05, 0.15, 0.4), 0.005)
	# escalera ancha a la primera planta, cortada con una barricada
	for k in 10:
		var y := 0.1 + k * 0.18
		_solido(Vector3(4.6, y * 2.0, 0.6), Vector3(9.6, y, 86.5 + k * 0.6), _m(Color(0.62, 0.6, 0.57)))
	_solido(Vector3(4.6, 1.9, 2.0), Vector3(9.6, 0.95, 93.5), _m(Color(0.62, 0.6, 0.57)))
	for k in 6:
		var tabla := _solido(Vector3(4.4, 0.18, 0.06), Vector3(9.6, 2.3 + k * 0.32, 92.6), _m(MADERA))
		tabla.rotation_degrees.z = randf_range(-12.0, 12.0)
	_cinta(Vector3(7.3, 1.0, 86.0), Vector3(11.9, 1.0, 86.0))
	_texto("PROHIBIDO EL PASO", Vector3(9.6, 1.4, 85.97), 180.0, 30, Color(0.1, 0.1, 0.1), 0.004)
	# bancos, plantas muertas, tablón y rastro hacia la salida
	_banco(Vector3(-11.6, 0.0, 85.0), 90.0)
	for p in [Vector3(-3.6, 0.0, 97.5), Vector3(3.6, 0.0, 97.5)]:
		_maceta(p)
	_corcho(Vector3(11.98, 1.6, 79.5), -90.0)
	_marco(Vector3(-9.0, 0.0, 76.2), "z", 3.2, 2.6)
	_texto("PATIO", Vector3(-9.0, 2.95, 76.42), 0.0, 34, Color(0.05, 0.15, 0.4), 0.005)
	_rastro(Vector3(3.0, 0.0, 77.0), Vector3(0.5, 0.0, 96.5), 10)
	_mancha(Vector3(-1.5, 0.0, 86.0), Vector2(2.6, 2.0), "y", "charco")
	_mancha(Vector3(5.0, 0.0, 90.0), Vector2(2.0, 1.6), "y", "vomito")
	_cristales(Rect2(-9.0, 96.0, 5.0, 2.0), 20)
	_cristales(Rect2(4.0, 96.0, 5.0, 2.0), 20)
	_papeles(Rect2(-11.0, 77.0, 22.0, 20.0), 30)


# =============================================================
# Patio: pista de baloncesto, árboles, farolas y niebla
# =============================================================
func _patio() -> void:
	var r: Rect2 = U.SALAS[U.R_PATIO]
	var c := r.get_center()
	_pista_padel(Vector3(c.x, 0.0, c.y))
	# árboles, bancos y papeleras
	for p in [Vector2(-27.0, 21.0), Vector2(-10.0, 21.5), Vector2(-27.5, 71.0), Vector2(-14.0, 71.5), Vector2(-27.0, 46.0)]:
		_arbol(Vector3(p.x, 0.0, p.y))
	for z in [30.0, 60.0]:
		_banco(Vector3(-29.6, 0.0, z), 90.0)
	# farolas (una apagada, otra parpadea)
	var fl := [Vector3(-9.0, 0.0, 33.0), Vector3(-9.0, 0.0, 58.0), Vector3(-28.5, 0.0, 33.0), Vector3(-28.5, 0.0, 62.0)]
	for i in fl.size():
		_farola(fl[i], i == 1, i == 2)
	# luz de luna desde arriba y la luna
	var luna := SpotLight3D.new()
	luna.position = Vector3(c.x, 40.0, c.y)
	luna.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	luna.light_color = Color(0.5, 0.6, 0.95)
	luna.light_energy = 6.0
	luna.spot_range = 70.0
	luna.spot_angle = 38.0
	luna.spot_attenuation = 0.3
	luna.shadow_enabled = true
	luna.light_volumetric_fog_energy = 0.1
	add_child(luna)
	# claridad de la noche para que los muros de ladrillo se vean desde lejos
	for z in [28.0, 46.0, 64.0]:
		var fill := OmniLight3D.new()
		fill.position = Vector3(-21.0, 6.0, z)
		fill.light_color = Color(0.55, 0.65, 0.95)
		fill.light_energy = 9.0
		fill.omni_range = 22.0
		fill.light_volumetric_fog_energy = 0.0
		add_child(fill)
	var moon := U.sphere(self, 5.0, Vector3(-70.0, 55.0, 50.0), Color(0.85, 0.9, 1.0), true)
	moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# niebla baja (se ve con gráficos ULTRA)
	var fog := FogVolume.new()
	fog.size = Vector3(r.size.x, 3.0, r.size.y)
	fog.position = Vector3(c.x, 1.0, c.y)
	var fm := FogMaterial.new()
	fm.density = 0.015
	fm.albedo = Color(0.7, 0.8, 0.75)
	fog.material = fm
	add_child(fog)
	# valla encima de los muros y ventanas del edificio
	_valla(r)
	for z in [36.0, 44.0, 52.0, 60.0, 68.0]:
		_ventana(Vector3(-6.41, 2.0, z), -90.0, 2.2, 1.4, z == 52.0)
	for x in [-26.0, -20.0, -14.0]:
		_ventana(Vector3(x, 2.0, 17.21), 0.0, 2.2, 1.4, x == -20.0)
	# restos: sillas amontonadas, una mochila y sangre en la pista
	for k in 6:
		_silla_tirada(Vector3(-24.0 + randf_range(-1.5, 1.5), 0.0, 28.0 + randf_range(-1.5, 1.5)), randf() * 360.0, Color(0.1, 0.15, 0.35))
	_mochila(Vector3(-16.0, 0.0, 40.0))
	_mancha(Vector3(-18.0, 0.0, 47.0), Vector2(3.0, 2.4), "y", "charco")
	_rastro(Vector3(-18.0, 0.0, 47.0), Vector3(-8.5, 0.0, 74.5), 10)
	_mancha(Vector3(-22.0, 0.0, 55.0), Vector2(2.2, 1.8), "y", "vomito")
	var pintada := _texto("NO HAY SALIDA", Vector3(-29.79, 2.4, 46.0), 90.0, 90, Color(0.75, 0.75, 0.75), 0.006)
	pintada.outline_size = 0


# =============================================================
# Modelos 3D (.glb)
# =============================================================
func _escena(nombre: String) -> PackedScene:
	if not _escenas.has(nombre):
		var path := MODELOS + nombre + ".glb"
		_escenas[nombre] = load(path) if ResourceLoader.exists(path) else null
	return _escenas[nombre]


func _modelo(nombre: String, pos: Vector3, yaw: float = 0.0, parent: Node3D = null) -> Node3D:
	var ps := _escena(nombre)
	if ps == null:
		return null
	var n: Node3D = ps.instantiate()
	n.position = pos
	n.rotation_degrees.y = yaw
	(parent if parent != null else self).add_child(n)
	return n


# Baja (o sube) un modelo girado para que se apoye justo en el suelo
func _apoyar(n: Node3D) -> void:
	var bb := U.node_aabb(n, n.transform)
	n.position.y -= bb.position.y


# Choque invisible (el modelo se ve, esta caja es la que para al jugador)
func _choque(size: Vector3, pos: Vector3, yaw: float) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.position = pos
	sb.rotation_degrees.y = yaw
	add_child(sb)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	sb.add_child(cs)
	return sb


# Fila de 6 puestos con ordenador y su silla; false si no están los modelos
func _pupitres(cx: float, z: float) -> bool:
	if _escena("puesto_pc_codigo") == null or _escena("silla") == null:
		return false
	_choque(Vector3(7.8, 0.8, 0.9), Vector3(cx, 0.4, z), 0.0)
	var tipos := ["puesto_pc_codigo", "puesto_pc_codigo", "puesto_pc_aviso", "puesto_pc_noticias", "puesto_pc_apagado"]
	for i in 6:
		var x := cx + (i - 2.5) * 1.3
		var t: String = tipos[randi() % tipos.size()]
		if _escena(t) == null:
			t = "puesto_pc_codigo"
		_modelo(t, Vector3(x, 0.0, z))
		# silla un poco movida, como si alguien se hubiera levantado deprisa
		_modelo("silla", Vector3(x + randf_range(-0.12, 0.12), 0.0, z + randf_range(0.65, 0.9)), 180.0 + randf_range(-20.0, 20.0))
	return true


# Pista de pádel de 10 x 20 m (centro c): cristal, malla, red y torres de focos
func _pista_padel(c: Vector3) -> void:
	var hw := 5.0
	var hl := 10.0
	if _modelo("pista_padel", c) == null:
		_b(Vector3(2.0 * hw, 0.02, 2.0 * hl), c + Vector3(0, 0.01, 0), Color(0.1, 0.3, 0.6))
	# paredes: choque para el jugador y obstáculos para los enemigos
	var paredes: Array = []      # [centro x, centro z, ancho x, fondo z, alto]
	for sz in [-1.0, 1.0]:
		paredes.append([0.0, sz * (hl + 0.03), 2.0 * hw + 0.2, 0.12, 4.0])            # fondos
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			paredes.append([sx * (hw + 0.03), sz * 6.6, 0.12, 6.8, 4.0])            # de la puerta al fondo
		paredes.append([sx * (hw + 0.03), 0.0, 0.12, 1.6, 3.0])                     # tramo central
	for w: Array in paredes:
		_choque(Vector3(w[2], w[4], w[3]), c + Vector3(w[0], w[4] / 2.0, w[1]), 0.0)
		U.bloques.append(Rect2(c.x + w[0] - w[2] / 2.0, c.z + w[1] - w[3] / 2.0, w[2], w[3]))
	_choque(Vector3(2.0 * hw, 0.95, 0.06), c + Vector3(0, 0.475, 0), 0.0)            # red (solo el jugador)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_choque(Vector3(0.16, 6.2, 0.16), c + Vector3(sx * (hw + 0.45), 3.1, sz * 5.0), 0.0)
	U.limites = U.SALAS[U.R_PATIO]
	# focos: tres encendidos (uno falla de vez en cuando) y uno fundido
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			if sx > 0.0 and sz > 0.0:
				continue
			var f := SpotLight3D.new()
			add_child(f)
			f.look_at_from_position(c + Vector3(sx * (hw + 0.45 - 0.7), 6.0, sz * 5.0), c + Vector3(-sx * 1.5, 0.0, sz * 2.5), Vector3.UP)
			f.light_color = Color(0.92, 0.96, 1.0)
			f.light_energy = 16.0
			f.spot_range = 26.0
			f.spot_angle = 48.0
			f.spot_attenuation = 0.7
			f.shadow_enabled = sx < 0.0 and sz < 0.0
			f.light_volumetric_fog_energy = 0.4
			if sx > 0.0:
				_falla(f, null, 16.0)
	# restos en la pista: pelotas, una pala y una bolsa tirada
	for k in 9:
		U.sphere(self, 0.033, c + Vector3(randf_range(-4.5, 4.5), 0.055, randf_range(-9.5, 9.5)), Color(0.85, 0.95, 0.2))
	var pala := Node3D.new()
	pala.position = c + Vector3(1.8, 0.02, -3.5)
	pala.rotation_degrees = Vector3(-90.0, randf() * 360.0, 0)
	add_child(pala)
	var disco := U.cylinder(pala, 0.22, 0.035, Vector3(0, 0.12, 0), Color(0.1, 0.1, 0.12))
	disco.rotation_degrees.x = 90.0
	U.box(pala, Vector3(0.04, 0.2, 0.03), Vector3(0, -0.2, 0), Color(0.08, 0.08, 0.08))
	_mochila(c + Vector3(-3.6, 0.0, 8.5))


# =============================================================
# Piezas reutilizables
# =============================================================
func _luz(pos: Vector3, w: float, d: float, rango: float, col: Color, parpadeo: bool, sombra: int) -> void:
	var panel := MeshInstance3D.new()
	var pp := PlaneMesh.new()
	pp.size = Vector2(w, d)
	panel.mesh = pp
	panel.material_override = U.mat(col, true)
	panel.material_override.emission_energy_multiplier = 4.0
	panel.position = Vector3(pos.x, pos.y + 0.29, pos.z)
	panel.rotation_degrees = Vector3(180, 0, 0)
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	panel.add_to_group("techos")
	add_child(panel)
	var cono: ShaderMaterial = null
	if pos.y + 0.3 <= CEIL + 0.01 and randf() < 0.55:
		cono = _cono(Vector3(pos.x, pos.y + 0.3, pos.z), maxf(w, d), col)
	var l := SpotLight3D.new()
	l.position = pos
	l.rotation_degrees = Vector3(-90, 0, 0)
	l.light_color = col
	l.light_energy = 2.0
	l.spot_range = rango
	l.spot_angle = 80.0
	l.spot_attenuation = 0.6
	l.shadow_blur = 1.5
	l.light_volumetric_fog_energy = 1.4
	add_child(l)
	# sombra: 0 nunca, 1 solo en ULTRA, 2 también en ALTO
	if sombra > 0:
		game.ceil_lights.append([l, sombra == 2])
	if parpadeo:
		_falla(l, panel.material_override, 2.0, cono)


# Haz de luz que baja desde un panel del techo hasta el suelo
func _cono(techo: Vector3, ancho: float, col: Color) -> ShaderMaterial:
	if _shader_cono == null:
		_shader_cono = Shader.new()
		_shader_cono.code = SHADER_CONO
	var sm := ShaderMaterial.new()
	sm.shader = _shader_cono
	sm.set_shader_parameter("k", CONO_ALFA)
	sm.set_shader_parameter("color", Vector3(col.r, col.g, col.b))
	var cm := CylinderMesh.new()
	cm.top_radius = ancho * 0.45
	cm.bottom_radius = ancho * 1.15
	cm.height = techo.y - 0.05
	cm.radial_segments = 20
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = sm
	mi.position = Vector3(techo.x, techo.y / 2.0, techo.z)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return sm


# Panel de techo descolgado colgando de un cable, con chispazos
func _panel_roto(techo: Vector3) -> void:
	var piv := Node3D.new()
	piv.position = techo + Vector3(0.5, -0.05, 0)
	piv.rotation_degrees = Vector3(0, randf() * 360.0, -55.0)
	add_child(piv)
	U.box_m(piv, Vector3(1.2, 0.06, 0.6), Vector3(-0.6, 0, 0), _m(Color(0.75, 0.75, 0.72)))
	U.box_m(piv, Vector3(1.1, 0.01, 0.5), Vector3(-0.6, -0.035, 0), _m(Color(0.3, 0.32, 0.3)))
	_b(Vector3(0.01, 0.6, 0.01), techo + Vector3(-0.2, -0.3, 0.1), Color(0.05, 0.05, 0.05))
	var chispa := OmniLight3D.new()
	chispa.position = techo + Vector3(0.0, -0.5, 0.0)
	chispa.light_color = Color(0.7, 0.85, 1.0)
	chispa.omni_range = 5.0
	chispa.light_energy = 0.0
	add_child(chispa)
	_chispas.append(chispa)


func _emergencia(pos: Vector3) -> void:
	_b(Vector3(0.35, 0.12, 0.12), pos, LUZ_EMERG, true)
	var l := OmniLight3D.new()
	l.position = pos + Vector3(0, -0.2, 0)
	l.light_color = LUZ_EMERG
	l.light_energy = 0.9
	l.omni_range = 6.0
	add_child(l)
	_pulsos.append([l, 0.9])


func _salida(pos: Vector3, yaw: float) -> void:
	var cartel := _b(Vector3(1.2, 0.4, 0.05), pos, Color(0.1, 0.7, 0.2), true)
	cartel.rotation_degrees.y = yaw
	var t := _texto("SALIDA", pos + Vector3(0, 0, 0.04).rotated(Vector3.UP, deg_to_rad(yaw)), yaw, 50, Color(1, 1, 1), 0.005)
	t.outline_size = 0
	var l := OmniLight3D.new()
	l.position = pos + Vector3(0, -0.3, 0.3).rotated(Vector3.UP, deg_to_rad(yaw))
	l.light_color = Color(0.2, 1.0, 0.35)
	l.light_energy = 0.5
	l.omni_range = 3.5
	add_child(l)


func _texto(txt: String, pos: Vector3, yaw: float, size: int, c: Color, px: float = 0.004) -> Label3D:
	var l := Label3D.new()
	l.text = txt
	l.font_size = size
	l.pixel_size = px
	l.outline_size = 4
	l.outline_modulate = Color(0, 0, 0, 0.6)
	l.modulate = c
	l.position = pos
	l.rotation_degrees.y = yaw
	add_child(l)
	return l


# Marco de puerta (dos jambas y dintel) centrado en la línea de la pared
func _marco(pos: Vector3, eje: String, ancho: float, alto: float) -> void:
	var c := Color(0.35, 0.36, 0.4)
	for s in [-1.0, 1.0]:
		var jp := pos + (Vector3(0, alto / 2.0, s * (ancho / 2.0 + 0.05)) if eje == "x" else Vector3(s * (ancho / 2.0 + 0.05), alto / 2.0, 0))
		_b(Vector3(0.5, alto, 0.1) if eje == "x" else Vector3(0.1, alto, 0.5), jp, c)
	_b(Vector3(0.5, 0.12, ancho + 0.2) if eje == "x" else Vector3(ancho + 0.2, 0.12, 0.5), pos + Vector3(0, alto + 0.06, 0), c)


func _ventana(pos: Vector3, yaw: float, w: float, h: float, tablas: bool) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation_degrees.y = yaw
	add_child(root)
	var cristal := U.box_m(root, Vector3(w, h, 0.02), Vector3(0, 0, 0.01), _m(Color(0.04, 0.06, 0.12), true))
	cristal.material_override = cristal.material_override.duplicate()
	cristal.material_override.emission_energy_multiplier = 0.25
	var marco := _m(Color(0.55, 0.56, 0.6))
	for s in [-1.0, 1.0]:
		U.box_m(root, Vector3(0.08, h + 0.16, 0.06), Vector3(s * (w / 2.0 + 0.04), 0, 0.03), marco)
		U.box_m(root, Vector3(w + 0.16, 0.08, 0.06), Vector3(0, s * (h / 2.0 + 0.04), 0.03), marco)
	U.box_m(root, Vector3(0.05, h, 0.05), Vector3(0, 0, 0.03), marco)
	if tablas:
		for k in 4:
			var t := U.box_m(root, Vector3(w + 0.5, 0.18, 0.05), Vector3(0, -h / 2.0 + 0.2 + k * (h - 0.4) / 3.0, 0.09), _m(MADERA))
			t.rotation_degrees.z = randf_range(-14.0, 14.0)
	else:
		# persiana medio bajada
		for k in 8:
			U.box_m(root, Vector3(w - 0.05, 0.05, 0.015), Vector3(0, h / 2.0 - 0.05 - k * 0.07, 0.06), _m(Color(0.8, 0.8, 0.76)))


func _taquillas(pos: Vector3, yaw: float, n: int, abiertas: int) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation_degrees.y = yaw
	add_child(root)
	var ancho := n * 0.55
	# cuerpo sólido (en las paredes el frente mira a +z local)
	_solido_en(root, Vector3(ancho, 2.1, 0.45), Vector3(ancho / 2.0, 1.05, 0.0), _m(TAQUILLA))
	var abrir := []
	for k in abiertas:
		abrir.append(randi() % n)
	for i in n:
		var x := 0.275 + i * 0.55
		if abrir.has(i):
			var hinge := Node3D.new()
			hinge.position = Vector3(x - 0.27, 1.05, 0.24)
			hinge.rotation_degrees.y = randf_range(70.0, 120.0)
			root.add_child(hinge)
			U.box_m(hinge, Vector3(0.52, 2.0, 0.02), Vector3(0.26, 0, 0), _m(TAQUILLA.lightened(0.08)))
			U.box_m(root, Vector3(0.5, 2.0, 0.01), Vector3(x, 1.05, 0.2), _m(Color(0.04, 0.05, 0.08)))
		else:
			U.box_m(root, Vector3(0.02, 2.1, 0.02), Vector3(x + 0.275, 1.05, 0.23), _m(Color(0.05, 0.1, 0.2)))
			for v in 3:
				U.box_m(root, Vector3(0.3, 0.02, 0.01), Vector3(x, 1.85 - v * 0.05, 0.23), _m(Color(0.05, 0.1, 0.2)))


func _puerta_aula(pos: Vector3, yaw: float, numero: int) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation_degrees.y = yaw
	add_child(root)
	U.box_m(root, Vector3(1.1, 2.4, 0.06), Vector3(0, 1.2, 0.03), _m(Color(0.35, 0.22, 0.12)))
	U.box_m(root, Vector3(0.35, 0.5, 0.07), Vector3(0, 1.7, 0.04), _m(Color(0.25, 0.35, 0.45), true))
	U.box_m(root, Vector3(0.12, 0.03, 0.05), Vector3(0.42, 1.05, 0.09), _m(Color(0.7, 0.7, 0.72)))
	var t := Label3D.new()
	t.text = "AULA %d" % numero
	t.font_size = 28
	t.pixel_size = 0.004
	t.outline_size = 0
	t.modulate = Color(0.1, 0.12, 0.2)
	t.position = Vector3(0, 2.6, 0.04)
	root.add_child(t)


func _banco(pos: Vector3, yaw: float) -> void:
	if _modelo("banco", pos, yaw) != null:
		_choque(Vector3(2.4, 0.47, 0.45), pos + Vector3(0, 0.235, 0), yaw)
		return
	var root := Node3D.new()
	root.position = pos
	root.rotation_degrees.y = yaw
	add_child(root)
	_solido_en(root, Vector3(2.4, 0.06, 0.45), Vector3(0, 0.46, 0), _m(MADERA))
	for k in [-1.0, 1.0]:
		U.box_m(root, Vector3(0.06, 0.45, 0.06), Vector3(k * 1.05, 0.22, 0), _m(Color(0.2, 0.2, 0.22)))


func _silla_tirada(p: Vector3, yaw: float, c: Color) -> void:
	var n := _modelo("silla", p, 0.0)
	if n != null:
		n.rotation_degrees = Vector3(randf_range(70.0, 100.0), yaw, 0)
		_apoyar(n)
		return
	var root := Node3D.new()
	root.position = p + Vector3(0, 0.25, 0)
	root.rotation_degrees = Vector3(randf_range(70.0, 100.0), yaw, 0)
	add_child(root)
	U.box_m(root, Vector3(0.5, 0.06, 0.5), Vector3(0, 0, 0), _m(c))
	U.box_m(root, Vector3(0.5, 0.5, 0.06), Vector3(0, 0.27, 0.25), _m(c))
	for sx in [-0.22, 0.22]:
		for sz in [-0.22, 0.22]:
			U.box_m(root, Vector3(0.04, 0.45, 0.04), Vector3(sx, -0.24, sz), _m(Color(0.2, 0.2, 0.22)))


func _mochila(p: Vector3) -> void:
	var c: Color = [Color(0.6, 0.1, 0.1), Color(0.1, 0.2, 0.5), Color(0.15, 0.15, 0.15), Color(0.2, 0.45, 0.2)][randi() % 4]
	var m := U.ellipsoid(self, Vector3(0.18, 0.22, 0.12), p + Vector3(0, 0.14, 0), c)
	m.rotation_degrees = Vector3(randf_range(-60.0, -80.0), randf() * 360.0, 0)


func _papeles(r: Rect2, n: int) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var q := QuadMesh.new()
	q.size = Vector2(0.21, 0.297)
	mm.mesh = q
	mm.instance_count = n
	for i in n:
		var t := Transform3D(Basis(Vector3.UP, randf() * TAU) * Basis(Vector3.RIGHT, -PI / 2.0),
			Vector3(r.position.x + randf() * r.size.x, 0.008 + i * 0.0003, r.position.y + randf() * r.size.y))
		mm.set_instance_transform(i, t)
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = _m(Color(0.88, 0.87, 0.82))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _libros_suelo(r: Rect2, n: int) -> void:
	for i in n:
		var b := _b(Vector3(0.16, 0.04, 0.23), Vector3(r.position.x + randf() * r.size.x, 0.02, r.position.y + randf() * r.size.y),
			[Color(0.5, 0.1, 0.1), Color(0.1, 0.25, 0.45), Color(0.15, 0.35, 0.15), Color(0.5, 0.4, 0.15)][i % 4])
		b.rotation_degrees.y = randf() * 360.0


func _estanteria(pos: Vector3, largo: float, caida: bool) -> void:
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	if caida:
		root.rotation_degrees = Vector3(-70.0, 15.0, 0)
		root.position.y = 0.2
	var wood := _m(MADERA.darkened(0.25))
	_solido_en(root, Vector3(largo, 2.2, 0.5), Vector3(0, 1.1, 0), wood)
	var cols := [Color(0.5, 0.1, 0.1), Color(0.1, 0.25, 0.45), Color(0.15, 0.35, 0.15), Color(0.5, 0.4, 0.15), Color(0.3, 0.15, 0.35)]
	for fila in 4:
		for lado in [-1.0, 1.0]:
			var x := -largo / 2.0 + 0.1
			while x < largo / 2.0 - 0.2:
				var w := randf_range(0.04, 0.09)
				var hh := randf_range(0.25, 0.38)
				if randf() > 0.15:
					U.box_m(root, Vector3(w, hh, 0.2), Vector3(x + w / 2.0, 0.15 + fila * 0.52 + hh / 2.0, lado * 0.16), _m(cols[randi() % cols.size()]))
				x += w + 0.005


func _maquina(pos: Vector3, yaw: float, rota: bool) -> void:
	_maquina_tipo(pos, yaw, "snacks" if rota else "bebidas", rota)


# Máquina expendedora con el modelo 3D ("snacks" o "bebidas"); rota = sin luz, chisporrotea
func _maquina_tipo(pos: Vector3, yaw: float, tipo: String, rota: bool) -> void:
	var n := _modelo("maquina_" + tipo, pos, yaw)
	if n == null:
		_maquina_cajas(pos, yaw, rota)
		return
	_choque(Vector3(0.95, 1.85, 0.86), pos + Vector3(0, 0.925, 0), yaw)
	var l := OmniLight3D.new()
	l.position = pos + Vector3(0, 1.2, 0.75).rotated(Vector3.UP, deg_to_rad(yaw))
	l.light_color = Color(1.0, 0.92, 0.8) if tipo == "snacks" else Color(1.0, 0.45, 0.4)
	l.omni_range = 3.2
	add_child(l)
	if rota:
		l.light_energy = 0.0
		_chispas.append(l)
		# cristal reventado
		_mancha(pos + Vector3(-0.13, 1.15, 0.45).rotated(Vector3.UP, deg_to_rad(yaw)), Vector2(0.6, 0.9),
			_lado_pared(yaw), "salpicadura")
	else:
		l.light_energy = 0.55


func _lado_pared(yaw: float) -> String:
	# la cara delantera mira a +Z girada yaw: la calcomanía se proyecta hacia atrás (hacia la máquina)
	match int(round(fposmod(yaw, 360.0))):
		90:
			return "-x"
		180:
			return "+z"
		270:
			return "+x"
	return "-z"


func _maquina_cajas(pos: Vector3, yaw: float, rota: bool) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation_degrees.y = yaw
	add_child(root)
	_solido_en(root, Vector3(1.0, 1.9, 0.8), Vector3(0, 0.95, 0), _m(Color(0.65, 0.08, 0.08)))
	var frente := U.box_m(root, Vector3(0.7, 1.2, 0.02), Vector3(-0.1, 1.15, 0.41), _m(Color(0.9, 0.85, 0.6), true))
	if rota:
		frente.material_override = _m(Color(0.1, 0.1, 0.1))
		var l := OmniLight3D.new()
		l.position = Vector3(0, 1.2, 0.7)
		l.light_color = Color(1.0, 0.9, 0.7)
		l.light_energy = 0.0
		l.omni_range = 3.0
		root.add_child(l)
		_chispas.append(l)
	else:
		var l2 := OmniLight3D.new()
		l2.position = Vector3(0, 1.2, 0.7)
		l2.light_color = Color(1.0, 0.9, 0.7)
		l2.light_energy = 0.5
		l2.omni_range = 3.0
		root.add_child(l2)
	U.box_m(root, Vector3(0.15, 0.4, 0.02), Vector3(0.38, 1.2, 0.41), _m(Color(0.1, 0.1, 0.1)))


func _extintor(p: Vector3) -> void:
	U.cylinder(self, 0.09, 0.55, p + Vector3(0, 0.6, 0), Color(0.8, 0.05, 0.05))
	U.cylinder(self, 0.03, 0.12, p + Vector3(0, 0.94, 0), Color(0.1, 0.1, 0.1))


func _reloj(p: Vector3, yaw: float) -> void:
	var c := U.cylinder(self, 0.25, 0.05, p, Color(0.95, 0.95, 0.95))
	c.rotation_degrees = Vector3(90, yaw, 0)
	var t := _texto("3:17", p + Vector3(0, 0, 0).rotated(Vector3.UP, deg_to_rad(yaw)), yaw, 30, Color(0.1, 0.1, 0.1), 0.004)
	t.position.x -= 0.04
	t.outline_size = 0


func _corcho(p: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	root.position = p
	root.rotation_degrees.y = yaw
	add_child(root)
	U.box_m(root, Vector3(2.0, 1.2, 0.03), Vector3.ZERO, _m(Color(0.6, 0.42, 0.25)))
	for k in 7:
		var hoja := U.box_m(root, Vector3(0.21, 0.29, 0.005), Vector3(randf_range(-0.8, 0.8), randf_range(-0.4, 0.4), 0.02),
			_m([Color(0.95, 0.95, 0.9), Color(1.0, 0.9, 0.4), Color(0.6, 0.85, 1.0)][k % 3]))
		hoja.rotation_degrees.z = randf_range(-10.0, 10.0)
	var aviso := Label3D.new()
	aviso.text = "SE HA SUSPENDIDO\nLA EXCURSIÓN"
	aviso.font_size = 18
	aviso.pixel_size = 0.004
	aviso.outline_size = 0
	aviso.modulate = Color(0.1, 0.1, 0.1)
	aviso.position = Vector3(0.0, 0.42, 0.03)
	root.add_child(aviso)


func _cinta(a: Vector3, b: Vector3) -> void:
	var d := b - a
	var t := _b(Vector3(d.length(), 0.08, 0.01), (a + b) / 2.0, Color(1.0, 0.85, 0.0))
	t.rotation.y = -atan2(d.z, d.x)


func _cristales(r: Rect2, n: int) -> void:
	var m := _m(Color(0.75, 0.9, 0.95))
	for i in n:
		var c := U.box_m(self, Vector3(randf_range(0.04, 0.15), 0.005, randf_range(0.04, 0.15)),
			Vector3(r.position.x + randf() * r.size.x, 0.006, r.position.y + randf() * r.size.y), m)
		c.rotation_degrees.y = randf() * 360.0


func _suelo_mojado(p: Vector3) -> void:
	var root := Node3D.new()
	root.position = p
	add_child(root)
	for s in [-1.0, 1.0]:
		var hoja := U.box_m(root, Vector3(0.3, 0.6, 0.02), Vector3(0, 0.3, s * 0.12), _m(Color(1.0, 0.85, 0.0)))
		hoja.rotation_degrees.x = s * 20.0
	var t := Label3D.new()
	t.text = "SUELO\nMOJADO"
	t.font_size = 18
	t.pixel_size = 0.004
	t.outline_size = 0
	t.modulate = Color(0.05, 0.05, 0.05)
	t.position = Vector3(0, 0.35, 0.24)
	t.rotation_degrees.x = 20.0
	root.add_child(t)


func _vitrina(pos: Vector3) -> void:
	_solido(Vector3(4.0, 0.9, 0.5), pos + Vector3(0, 0.45, 0), _m(MADERA))
	var vidrio := _b(Vector3(4.0, 1.2, 0.5), pos + Vector3(0, 1.5, 0), Color(0.7, 0.85, 0.9))
	vidrio.material_override = vidrio.material_override.duplicate()
	vidrio.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	vidrio.material_override.albedo_color.a = 0.15
	var oro := _m(Color(0.85, 0.65, 0.2))
	for k in 5:
		var x := -1.6 + k * 0.8
		U.box_m(self, Vector3(0.18, 0.06, 0.18), pos + Vector3(x, 0.93, 0), oro)
		U.cylinder(self, 0.06, 0.25, pos + Vector3(x, 1.1, 0), Color(0.85, 0.65, 0.2))
	var l := OmniLight3D.new()
	l.position = pos + Vector3(0, 2.0, 0.4)
	l.light_color = Color(1.0, 0.9, 0.7)
	l.light_energy = 0.6
	l.omni_range = 3.0
	add_child(l)


func _maceta(p: Vector3) -> void:
	U.cylinder(self, 0.3, 0.6, p + Vector3(0, 0.3, 0), Color(0.45, 0.25, 0.15))
	for k in 5:
		var rama := _b(Vector3(0.03, 0.7, 0.03), p + Vector3(randf_range(-0.1, 0.1), 0.9, randf_range(-0.1, 0.1)), Color(0.3, 0.25, 0.12))
		rama.rotation_degrees = Vector3(randf_range(-35.0, 35.0), 0, randf_range(-35.0, 35.0))


func _arbol(p: Vector3) -> void:
	_solido(Vector3(0.4, 3.6, 0.4), p + Vector3(0, 1.8, 0), _m(Color(0.25, 0.17, 0.1)))
	for k in 4:
		var hoja := U.sphere(self, randf_range(1.2, 1.8), p + Vector3(randf_range(-0.8, 0.8), 3.8 + randf_range(0.0, 1.2), randf_range(-0.8, 0.8)), Color(0.08, 0.16, 0.08))
		hoja.scale = Vector3(1.0, 0.8, 1.0)


func _farola(p: Vector3, parpadea: bool, apagada: bool) -> void:
	U.cylinder(self, 0.08, 4.5, p + Vector3(0, 2.25, 0), Color(0.15, 0.15, 0.17))
	_b(Vector3(0.6, 0.12, 0.3), p + Vector3(0, 4.55, 0), Color(0.15, 0.15, 0.17))
	if apagada:
		return
	_b(Vector3(0.5, 0.04, 0.24), p + Vector3(0, 4.48, 0), Color(1.0, 0.8, 0.5), true)
	var l := OmniLight3D.new()
	l.position = p + Vector3(0, 4.2, 0)
	l.light_color = Color(1.0, 0.75, 0.45)
	l.light_energy = 7.0
	l.omni_range = 14.0
	l.light_volumetric_fog_energy = 0.4
	add_child(l)
	if parpadea:
		_falla(l, null, 7.0)


# Valla metálica encima de los muros del patio (postes y dos barras)
func _valla(r: Rect2) -> void:
	var gris := _m(Color(0.35, 0.36, 0.38))
	var y0 := ALTO_PATIO
	var lados := [[Vector2(r.position.x, r.position.y - 0.2), Vector2(r.end.x, r.position.y - 0.2)],
		[Vector2(r.position.x, r.end.y + 0.2), Vector2(r.end.x, r.end.y + 0.2)],
		[Vector2(r.position.x - 0.2, r.position.y), Vector2(r.position.x - 0.2, r.end.y)]]
	for ld: Array in lados:
		var a: Vector2 = ld[0]
		var b: Vector2 = ld[1]
		var d := b - a
		var n := int(d.length() / 3.0)
		for k in n + 1:
			var q := a + d * (float(k) / maxf(1.0, float(n)))
			U.box_m(self, Vector3(0.06, 1.6, 0.06), Vector3(q.x, y0 + 0.8, q.y), gris)
		for yy in [0.8, 1.55]:
			var bar := U.box_m(self, Vector3(d.length(), 0.04, 0.04), Vector3((a.x + b.x) / 2.0, y0 + yy, (a.y + b.y) / 2.0), gris)
			bar.rotation.y = -atan2(d.y, d.x)


# Rastro de sangre de a a b con n manchas alargadas
func _rastro(a: Vector3, b: Vector3, n: int) -> void:
	var d := b - a
	var yaw := rad_to_deg(atan2(d.x, d.z))
	for k in n:
		var t := (k + randf() * 0.5) / float(n)
		var p := a + d * t + Vector3(randf_range(-0.2, 0.2), 0.0, randf_range(-0.2, 0.2))
		_mancha(p, Vector2(0.5, 1.4), "y", "arrastre", yaw + randf_range(-15.0, 15.0))


# Calcomanía (decal) sobre el suelo ("y") o una pared ("+x" = la pared está en el lado +x, etc.)
func _mancha(p: Vector3, size: Vector2, normal: String, tipo: String, yaw: float = 999.0) -> void:
	var d := Decal.new()
	d.texture_albedo = _tex_mancha(tipo)
	d.size = Vector3(size.x, 0.5, size.y)
	d.position = p
	d.upper_fade = 0.3
	d.lower_fade = 0.3
	match normal:
		"y":
			d.rotation_degrees.y = randf() * 360.0 if yaw > 900.0 else yaw
		"+x":     # pared en el lado +x: proyecta hacia +x
			d.rotation_degrees = Vector3(randf() * 360.0, 0, 90.0)
		"-x":
			d.rotation_degrees = Vector3(randf() * 360.0, 0, -90.0)
		"+z":
			d.rotation_degrees = Vector3(-90.0, 0, 0)
		"-z":
			d.rotation_degrees = Vector3(90.0, 0, 0)
	add_child(d)


# Texturas de manchas hechas a mano con círculos (se cachean)
func _tex_mancha(tipo: String) -> Texture2D:
	if _tex.has(tipo):
		return _tex[tipo]
	var n := 128
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := SANGRE
	var alpha := 0.9
	match tipo:
		"vomito":
			c = BILIS
		"agua":
			c = Color(0.3, 0.33, 0.35)
			alpha = 0.35
	match tipo:
		"arrastre":
			for k in 9:
				_blob(img, Vector2(64 + randf_range(-10, 10), 10 + k * 13), randf_range(7, 13), c, alpha * randf_range(0.5, 0.9))
		"mano":
			_blob(img, Vector2(64, 78), 22, c, alpha)
			for k in 4:
				var fx := 40.0 + k * 16.0
				for s in 5:
					_blob(img, Vector2(fx, 52 - s * 7 - (8 if k == 1 or k == 2 else 0)), 6, c, alpha)
			for s in 4:
				_blob(img, Vector2(28 - s * 4, 82 - s * 6), 6, c, alpha)
		"salpicadura":
			_blob(img, Vector2(64, 64), 20, c, alpha)
			for k in 40:
				var ang := randf() * TAU
				var dist := randf_range(18, 60)
				_blob(img, Vector2(64, 64) + Vector2(cos(ang), sin(ang)) * dist, randf_range(1.5, 5.0), c, alpha)
		_:
			for k in 14:
				var ang2 := randf() * TAU
				var dist2 := randf_range(0, 34)
				_blob(img, Vector2(64, 64) + Vector2(cos(ang2), sin(ang2)) * dist2, randf_range(10, 24), c, alpha * randf_range(0.7, 1.0))
			for k in 12:
				var ang3 := randf() * TAU
				_blob(img, Vector2(64, 64) + Vector2(cos(ang3), sin(ang3)) * randf_range(44, 60), randf_range(2, 5), c, alpha)
	var tex := ImageTexture.create_from_image(img)
	_tex[tipo] = tex
	return tex


func _blob(img: Image, c: Vector2, r: float, col: Color, a: float) -> void:
	var n := img.get_width()
	var x0 := maxi(0, int(c.x - r - 1))
	var x1 := mini(n - 1, int(c.x + r + 1))
	var y0 := maxi(0, int(c.y - r - 1))
	var y1 := mini(n - 1, int(c.y + r + 1))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var d := Vector2(x, y).distance_to(c)
			if d > r:
				continue
			var k := clampf((r - d) / 2.0, 0.0, 1.0) * a
			var prev := img.get_pixel(x, y)
			var na := maxf(prev.a, k)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, na))


# =============================================================
# Materiales y cajas
# =============================================================
func _m(c: Color, emit: bool = false) -> StandardMaterial3D:
	var k := "%s|%s" % [c, emit]
	if not _mats.has(k):
		_mats[k] = U.mat(c, emit)
	return _mats[k]


# Material con una de las texturas pintadas, proyectada desde el mundo para que
# el dibujo siga de una pared a la de al lado sin saltos
func _png(nombre: String, metros: float, rough: float) -> StandardMaterial3D:
	var k := "png|" + nombre
	if _mats.has(k):
		return _mats[k]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(TEXTURAS + nombre + ".png")
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / metros
	m.roughness = rough
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
	_mats[k] = m
	return m


func _b(size: Vector3, pos: Vector3, c: Color, emit: bool = false) -> MeshInstance3D:
	return U.box_m(self, size, pos, _m(c, emit))


func _solido(size: Vector3, pos: Vector3, m: Material) -> StaticBody3D:
	return _solido_en(self, size, pos, m)


func _solido_en(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.position = pos
	parent.add_child(sb)
	U.box_m(sb, size, Vector3.ZERO, m)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	sb.add_child(cs)
	return sb

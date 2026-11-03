extends Node3D
# Mapas del bucle: al "escapar" de CESUR te despiertas en un sitio que no conoces.
#  · Mojácar: el Paseo del Mediterráneo de Mojácar Playa (37.1176, -1.8365), mirando
#    al oeste-noroeste como en el Street View: la carretera, el paseo con palmeras,
#    la playa y, al fondo, el pueblo blanco en lo alto del cerro y la Sierra Cabrera.
#  · Pueblo Indalo: el Hotel Pueblo Indalo (Paseo del Mediterráneo, Mojácar), un
#    complejo de estilo árabe-andaluz: calles de bloques blancos de 6 apartamentos,
#    arcos, piscinas, jardines con palmeras, pista de tenis, buffet y la playa.
# Pero hay cosas que no cuadran (mesas del aula en la arena, la calle que acaba en
# una pared amarilla...): sigue siendo CESUR. Las pistas las usa investigacion.gd.

const U = preload("res://scripts/nucleo/util.gd")
const G = preload("res://scripts/nucleo/graficos.gd")

const BLANCO := Color(0.95, 0.94, 0.9)
const AZUL := Color(0.13, 0.33, 0.62)       # carpintería azul de Mojácar
const VERDE := Color(0.18, 0.42, 0.3)
const OCRE := Color(0.82, 0.56, 0.27)
const TEJA := Color(0.7, 0.33, 0.2)
const MADERA := Color(0.45, 0.28, 0.15)
const CRISTAL := Color(0.08, 0.1, 0.13)
const BUGANVILLA := Color(0.82, 0.12, 0.5)
const AMARILLO := Color(0.8, 0.72, 0.4)     # papel pintado de los backrooms

var game
var titulo := ""
var intro := ""
var spawns: Array = []
var pistas: Array = []          # [id, nombre, texto, posición]
var puerta_pos := Vector3.ZERO  # la puerta del aula que aparece al final
var puerta_yaw := 0.0
var salida: Array = []          # frases al cruzar la puerta
var sky: Sky
var sun: DirectionalLight3D
var sea_mat: StandardMaterial3D
var _mats := {}


static func siguiente(m: String) -> String:
	match m:
		"cesur":
			return "mojacar"
		"mojacar":
			return "indalo"
	return "cesur"


func construir(m: String) -> void:
	seed(hash(m))       # mismo mapa en todos los PCs (alturas, ventanas, palmeras...)
	_suelo_fisico()
	if m == "indalo":
		_indalo()
	else:
		_mojacar()
	randomize()
	game._build_box()


func _process(delta: float) -> void:
	if sea_mat != null:
		sea_mat.uv1_offset += Vector3(0.004, 0.0, 0.0025) * delta


# Cielo de media tarde, sol bajo y algo de calima (se aplica en cada cambio de calidad)
func ajustar_gfx(env: Environment) -> void:
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.45 if G.nivel >= 2 else 0.8
	env.sdfgi_read_sky_light = true
	env.fog_density = 0.0016
	env.fog_light_color = Color(0.78, 0.8, 0.82)
	env.fog_sky_affect = 0.25
	env.volumetric_fog_density = 0.002
	env.tonemap_exposure = 1.0
	game.fog_d0 = env.fog_density
	game.fog_c0 = env.fog_light_color
	game.vfog_c0 = env.volumetric_fog_albedo


# =============================================================
# MOJÁCAR · Paseo del Mediterráneo
# x = este (+, el mar) / oeste (-, el pueblo) · z = sur (+) / norte (-)
# =============================================================
func _mojacar() -> void:
	titulo = "MOJÁCAR"
	intro = "...¿Mojácar?\nHace un segundo estabas delante de CESUR. Ahora hay palmeras, la playa\ny el pueblo blanco en lo alto del cerro. No sabes cómo has llegado. Investiga."
	game.start_pos = Vector3(5.5, 0.05, 2.0)
	game.start_yaw = deg_to_rad(60.0)        # mirando al oeste-noroeste, como en el Street View
	U.limites = Rect2(-25.4, -73.6, 60.0, 147.2)
	_cielo(Vector2(38.0, -50.0))       # sol de media tarde por el suroeste
	var asfalto := _tex_mat("asfalto", Color(0.17, 0.17, 0.18), Color(0.27, 0.27, 0.28), 0.9, 0.5, 0.9)
	var acera := _tex_mat("acera", Color(0.72, 0.7, 0.66), Color(0.82, 0.8, 0.76), 0.4, 0.6, 0.8)
	var paseo := _tex_mat("paseo", Color(0.72, 0.5, 0.38), Color(0.82, 0.62, 0.48), 0.6, 0.8, 0.75)
	var arena := _tex_mat("arena", Color(0.8, 0.7, 0.52), Color(0.9, 0.82, 0.64), 0.25, 0.35, 1.0)
	var monte := _tex_mat("monte", Color(0.52, 0.44, 0.3), Color(0.62, 0.55, 0.38), 0.02, 0.01, 1.0)
	# suelos
	U.box_m(self, Vector3(8.0, 0.02, 152.0), Vector3(-1.0, 0.01, 0.0), asfalto)            # carretera
	U.box_m(self, Vector3(3.5, 0.03, 152.0), Vector3(-6.75, 0.015, 0.0), acera)            # acera oeste
	U.box_m(self, Vector3(7.0, 0.03, 152.0), Vector3(6.5, 0.015, 0.0), paseo)              # paseo marítimo
	U.box_m(self, Vector3(26.0, 0.02, 152.0), Vector3(23.0, 0.0, 0.0), arena)              # playa
	U.box_m(self, Vector3(4.6, 0.025, 152.0), Vector3(-23.2, 0.012, 0.0), acera)           # callejón de atrás
	U.box_m(self, Vector3(3000.0, 0.02, 3000.0), Vector3(-1526.0, -0.02, 0.0), monte)      # tierra hacia el pueblo
	_mar(36.0)
	for i in 26:
		_b(Vector3(0.15, 0.03, 3.0), Vector3(-1.0, 0.025, -73.0 + i * 6.0), Color(0.92, 0.92, 0.88))   # línea discontinua
	for x in [-4.8, 2.8]:
		_b(Vector3(0.12, 0.03, 152.0), Vector3(x, 0.025, 0.0), Color(0.92, 0.92, 0.88))
	for x in [-5.0, 3.0]:
		_b(Vector3(0.2, 0.06, 152.0), Vector3(x, 0.03, 0.0), Color(0.75, 0.74, 0.7))       # bordillos
	# muro bajo entre el paseo y la playa, con bajadas de 4 m cada 15 m
	var z := -74.0
	while z < 74.0:
		var len := minf(11.0, 74.0 - z)
		_solido(Vector3(0.45, 0.7, len), Vector3(10.2, 0.35, z + len / 2.0), BLANCO)
		_b(Vector3(0.55, 0.08, len), Vector3(10.2, 0.74, z + len / 2.0), OCRE)
		z += 15.0
	# palmeras, farolas y bancos del paseo
	for i in 17:
		var pz := -70.0 + i * 9.0
		if absf(pz + 30.0) > 5.0:
			_palmera(Vector3(7.0, 0.0, pz), randf_range(6.5, 8.5))
	for i in 8:
		_farola(Vector3(3.6, 0.0, -63.0 + i * 18.0), i % 3 == 1)
	for i in 10:
		_banco(Vector3(9.3, 0.0, -66.0 + i * 15.0 + 4.0), 90.0)
	_indalo_estatua(Vector3(6.5, 0.0, -30.0), 3.2)
	# edificios del lado del pueblo (fachada al este, x = -8,5)
	_manzana(-73.6, -48.0, [["SUPERMERCADO", AZUL], ["", VERDE], ["HELADERÍA", Color(0.85, 0.3, 0.45)], ["", AZUL]])
	_manzana(-43.0, -24.0, [["FARMACIA", Color(0.1, 0.6, 0.3)], ["", OCRE], ["SOUVENIRS INDALO", AZUL]])
	_manzana(16.0, 33.0, [["BAR EL ALJIBE", TEJA], ["", AZUL], ["", VERDE]])
	_manzana(38.0, 42.5, [["", OCRE]])
	_hotel_entrada(42.5, 54.0)
	_manzana(54.0, 73.6, [["RESTAURANTE", AZUL], ["", VERDE], ["", TEJA]])
	_aparcamiento()
	# muro del fondo (oeste) y, detrás, la tierra que sube hacia el pueblo
	_solido(Vector3(0.5, 1.4, 150.0), Vector3(-25.75, 0.7, 0.0), BLANCO)
	_b(Vector3(0.6, 0.1, 150.0), Vector3(-25.75, 1.45, 0.0), OCRE)
	_pueblo(Vector3(-385.0, 0.0, -225.0))
	_sierra()
	_urbanizaciones()
	# la playa
	_chiringuito(Vector3(22.0, 0.0, 8.0))
	_torre_socorrista(Vector3(28.0, 0.0, -30.0))
	for sx in [15.5, 20.5, 25.5, 30.5]:
		for i in 16:
			var sz: float = -68.0 + i * 9.0 + (sx - 15.5) * 0.4
			if absf(sz - 8.0) < 8.0 or absf(sz + 50.0) < 7.0 or absf(sz + 30.0) < 4.0:
				continue
			_sombrilla(Vector3(sx, 0.0, sz))
	# lo que no cuadra
	_mesas_playa(Vector3(20.0, 0.0, -50.0))
	_taquillas(Vector3(-7.9, 0.0, 22.0))
	_senal(Vector3(-5.6, 0.0, -12.0))
	for zz in [-75.6, 75.6]:
		backroom_pared(self, Vector3(25.0, 0.0, zz), Vector3(110.0, 14.0, 0.4), Vector3(0, 0, -signf(zz)), -1.0)
	_fluorescente_flotante(Vector3(-1.0, 6.0, -66.0))
	_fluorescente_flotante(Vector3(23.0, 5.0, -50.0))
	pistas = [
		["senal", "La señal de tráfico", "«MOJÁCAR PUEBLO  3 km».\nEstás en Mojácar, Almería. Reconoces el pueblo blanco en lo alto del cerro.\nPero hace un momento estabas saliendo de CESUR... ¿Cuánto tiempo ha pasado?", Vector3(-5.0, 0.0, -12.0)],
		["mesas", "Mesas en la arena", "Seis mesas del aula, con sus ordenadores encendidos, mirando al mar.\nEn una está tu nombre rayado con un compás. La pizarra dice:\n«TAREA PARA HOY: ¿DÓNDE ESTÁS?»", Vector3(18.6, 0.0, -50.0)],
		["taquillas", "Taquillas en la acera", "Las taquillas azules del pasillo de CESUR, en plena acera.\nDentro están los cables que cogiste para la bomba... y una nota:\n«NO TE FÍES DEL CIELO»", Vector3(-7.0, 0.0, 22.0)],
		["radio", "La radio del chiringuito", "La radio no pone música. Solo suena el timbre de cambio de clase de CESUR,\nuna y otra vez. Entre timbre y timbre, alguien pasa lista.\nDice tu nombre. Nadie contesta.", Vector3(22.0, 0.0, 10.4)],
		["fin", "El final de la calle", "La carretera no sigue: acaba en una pared de papel pintado amarillo.\nHuele a moqueta mojada y se oye el zumbido de los fluorescentes.\nAlguien ha escrito con rotulador: «NO HAY SALIDA»", Vector3(-1.0, 0.0, -73.0)],
	]
	puerta_pos = Vector3(-8.45, 0.0, 48.25)
	puerta_yaw = 90.0
	salida = ["Entras en el Hotel Pueblo Indalo...", "...y en recepción huele a tiza.", "Otro sitio que no conoces."]
	game.box_spots = [
		[Vector3(8.5, 0.0, -14.0), 90.0, "el paseo marítimo"],
		[Vector3(-14.0, 0.0, 9.5), 0.0, "el aparcamiento"],
		[Vector3(24.0, 0.0, -60.0), 0.0, "la playa (norte)"],
		[Vector3(26.0, 0.0, 42.0), 0.0, "la playa (sur)"],
		[Vector3(-23.0, 0.0, -36.0), 90.0, "el callejón de atrás"],
		[Vector3(-12.0, 0.0, 34.6), 0.0, "la calle del hotel"],
	]
	spawns = [Vector3(-23.0, 0, -62.0), Vector3(-23.0, 0, 62.0), Vector3(-15.0, 0, -45.5), Vector3(-15.0, 0, 35.5),
		Vector3(25.0, 0, -68.0), Vector3(25.0, 0, 68.0), Vector3(0.0, 0, -71.0), Vector3(0.0, 0, 71.0),
		Vector3(-21.0, 0, -12.0), Vector3(32.0, 0, 0.0), Vector3(15.0, 0, -40.0), Vector3(15.0, 0, 40.0)]
	game._wall_buy("subfusil", Vector3(-8.47, 1.7, -26.0), 90.0, Vector3(-7.6, 0, -26.0))
	game._wall_buy("fusil", Vector3(-8.47, 1.7, 26.6), 90.0, Vector3(-7.6, 0, 26.6))
	game._wall_buy("francotirador", Vector3(5.0, 1.9, 75.38), 180.0, Vector3(5.0, 0, 74.2))
	game._wall_buy("revolver", Vector3(1.5, 1.7, 75.38), 180.0, Vector3(1.5, 0, 74.2))
	game._wall_buy("uzi", Vector3(-8.47, 1.7, 30.1), 90.0, Vector3(-7.6, 0, 30.1))
	game._wall_buy("escopeta", Vector3(8.5, 1.7, 75.38), 180.0, Vector3(8.5, 0, 74.2))


# Una manzana de casas blancas entre z0 y z1: [rótulo de la tienda, color]
func _manzana(z0: float, z1: float, casas: Array) -> void:
	var w := (z1 - z0) / casas.size()
	for i in casas.size():
		var h: float = [6.2, 9.2, 6.2, 9.2, 3.4][randi() % 5]
		_casa(Rect2(-21.0, z0 + i * w, 12.5, w), h, Vector3(1, 0, 0), casas[i][1], casas[i][0])


# Casa cúbica blanca (estilo Mojácar): ventanas con marcos de color, balcones,
# azotea con pretil y chimenea. normal = hacia dónde mira la fachada.
func _casa(r: Rect2, h: float, normal: Vector3, accent: Color, tienda: String = "") -> void:
	var c := Vector3(r.get_center().x, 0.0, r.get_center().y)
	_solido(Vector3(r.size.x, h, r.size.y), c + Vector3(0, h / 2.0, 0), BLANCO)
	_b(Vector3(r.size.x + 0.12, 0.35, r.size.y + 0.12), c + Vector3(0, h + 0.17, 0), BLANCO)     # pretil
	_b(Vector3(r.size.x + 0.16, 0.06, r.size.y + 0.16), c + Vector3(0, h + 0.28, 0), OCRE)     # franja
	_b(Vector3(r.size.x + 0.04, 0.4, r.size.y + 0.04), c + Vector3(0, 0.2, 0), Color(0.75, 0.72, 0.68))   # zócalo
	if randf() < 0.6:
		var ch := c + Vector3(randf_range(-0.3, 0.3) * r.size.x, h + 0.6, randf_range(-0.3, 0.3) * r.size.y)
		_b(Vector3(0.6, 1.2, 0.6), ch, BLANCO)
		_b(Vector3(0.8, 0.12, 0.8), ch + Vector3(0, 0.65, 0), BLANCO)
	var fr := _frame(r, normal)
	var width: float = fr[3]
	var floors := maxi(1, int(h / 3.0))
	for f in floors:
		var y := f * 3.0 + 1.6
		var n := maxi(1, int(width / 2.7))
		for i in n:
			var u := -width / 2.0 + (i + 0.5) * width / n
			if f == 0 and (tienda != "" or i == 0):
				continue
			_ventana(fr, u, y, accent, f > 0 and randf() < 0.45)
	if tienda != "":
		_fb(fr, width - 1.6, 2.0, 0.06, 0.4, 1.3, 0.02, CRISTAL)                  # escaparate
		_fb(fr, width - 1.4, 0.1, 0.08, 0.4, 2.35, 0.03, accent)
		_fb(fr, 1.0, 2.3, 0.07, -width / 2.0 + 0.8, 1.15, 0.03, accent.darkened(0.2))  # puerta
		var tol := _fb(fr, width - 0.6, 0.06, 1.7, 0.0, 2.85, 0.85, accent)        # toldo
		if absf(normal.x) > 0.5:
			tol.rotation_degrees.z = -14.0 * signf(normal.x)
		else:
			tol.rotation_degrees.x = 14.0 * signf(normal.z)
		_rotulo(fr, tienda, 0.0, 3.35, accent.darkened(0.35))
	else:
		_fb(fr, 1.1, 2.2, 0.07, -width / 2.0 + 1.2, 1.1, 0.03, accent)
		_fb(fr, 1.3, 0.08, 0.1, -width / 2.0 + 1.2, 2.28, 0.04, BLANCO)
	if randf() < 0.5:
		_buganvilla(fr, randf_range(-0.4, 0.4) * width, h)


# Sistema de coordenadas de una fachada: [centro en el suelo, eje a lo ancho, normal, ancho]
func _frame(r: Rect2, normal: Vector3) -> Array:
	var c := Vector3(r.get_center().x, 0.0, r.get_center().y)
	var half := Vector3(r.size.x / 2.0, 0.0, r.size.y / 2.0)
	var o := c + Vector3(normal.x * half.x, 0.0, normal.z * half.z)
	var u := Vector3(-normal.z, 0.0, normal.x)
	var width := r.size.y if absf(normal.x) > 0.5 else r.size.x
	return [o, u, normal, width]


# Caja colocada en coordenadas de la fachada (u = a lo ancho, y = altura, n = hacia fuera)
func _fb(fr: Array, su: float, sy: float, sn: float, pu: float, py: float, pn: float, c: Color, emit: bool = false) -> MeshInstance3D:
	var o: Vector3 = fr[0]
	var u: Vector3 = fr[1]
	var n: Vector3 = fr[2]
	var size := u.abs() * su + Vector3(0, sy, 0) + n.abs() * sn
	return _b(size, o + u * pu + Vector3(0, py, 0) + n * pn, c, emit)


func _ventana(fr: Array, u: float, y: float, accent: Color, balcon: bool) -> void:
	_fb(fr, 1.1, 1.35, 0.06, u, y, 0.01, accent)          # marco
	_fb(fr, 0.9, 1.15, 0.07, u, y, 0.02, CRISTAL)
	_fb(fr, 1.25, 0.07, 0.22, u, y - 0.7, 0.08, BLANCO)    # alféizar
	_fb(fr, 0.04, 1.15, 0.08, u, y, 0.03, accent)          # parteluz
	if balcon:
		_fb(fr, 1.6, 0.1, 0.8, u, y - 0.85, 0.4, BLANCO)
		_fb(fr, 1.6, 0.55, 0.04, u, y - 0.55, 0.78, Color(0.12, 0.12, 0.13))
		for k in 5:
			_fb(fr, 0.03, 0.55, 0.03, u - 0.7 + k * 0.35, y - 0.55, 0.78, Color(0.12, 0.12, 0.13))


func _rotulo(fr: Array, text: String, u: float, y: float, c: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 72
	l.pixel_size = 0.006
	l.outline_size = 0
	l.modulate = c
	var bold := SystemFont.new()
	bold.font_weight = 800
	l.font = bold
	var o: Vector3 = fr[0]
	var uu: Vector3 = fr[1]
	var n: Vector3 = fr[2]
	l.position = o + uu * u + Vector3(0, y, 0) + n * 0.06
	l.rotation_degrees.y = rad_to_deg(atan2(n.x, n.z))
	add_child(l)


func _buganvilla(fr: Array, u: float, h: float) -> void:
	var o: Vector3 = fr[0]
	var uu: Vector3 = fr[1]
	var n: Vector3 = fr[2]
	for k in 7:
		var p := o + uu * (u + randf_range(-0.9, 0.9)) + Vector3(0, h - randf_range(0.2, 2.6), 0) + n * 0.15
		var e := U.ellipsoid_m(self, Vector3(0.55, 0.4, 0.55) * randf_range(0.7, 1.2), p, _m(BUGANVILLA.lightened(randf() * 0.15)))
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for k in 4:
		var p := o + uu * (u + randf_range(-0.9, 0.9)) + Vector3(0, h - randf_range(0.5, 2.8), 0) + n * 0.1
		U.ellipsoid_m(self, Vector3(0.4, 0.3, 0.4), p, _m(Color(0.2, 0.42, 0.18)))


# La entrada del Hotel Pueblo Indalo en el paseo: arco, rótulo y el Indalo
func _hotel_entrada(z0: float, z1: float) -> void:
	var r := Rect2(-21.0, z0, 12.5, z1 - z0)
	var c := Vector3(r.get_center().x, 0.0, r.get_center().y)
	_solido(Vector3(r.size.x, 7.0, r.size.y), c + Vector3(0, 3.5, 0), BLANCO)
	_b(Vector3(r.size.x + 0.12, 0.35, r.size.y + 0.12), c + Vector3(0, 7.17, 0), BLANCO)
	_b(Vector3(r.size.x + 0.2, 0.08, r.size.y + 0.2), c + Vector3(0, 7.26, 0), TEJA)
	var fr := _frame(r, Vector3(1, 0, 0))
	# arco de la entrada (la puerta del aula aparece dentro)
	var hueco := Color(0.2, 0.16, 0.12)
	_fb(fr, 3.6, 3.4, 0.3, 0.0, 1.7, 0.12, OCRE)
	_arco(fr, 3.6, 0.0, 3.4, 0.12, OCRE)
	_fb(fr, 2.6, 2.9, 0.32, 0.0, 1.45, 0.14, hueco)
	_arco(fr, 2.6, 0.0, 2.9, 0.15, hueco)
	for u in [-4.0, 4.0]:
		_ventana(fr, u, 1.6, VERDE, false)
		_ventana(fr, u, 4.6, VERDE, true)
	_rotulo(fr, "HOTEL PUEBLO INDALO", 0.0, 6.15, TEJA)
	for u in [-2.65, 2.65]:
		var ind := Node3D.new()
		add_child(ind)
		ind.position = fr[0] + Vector3(0.1, 3.75, u)
		ind.rotation_degrees.y = 90.0
		_indalo_figura(ind, 0.75, TEJA)
	for zz in [z0 + 1.0, z1 - 1.0]:
		_palmera(Vector3(-7.0, 0.0, zz), 5.5)


# Semicírculo encima de un hueco (arcos andaluces)
func _arco(fr: Array, w: float, u: float, y: float, pn: float, c: Color) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = w / 2.0
	cm.bottom_radius = w / 2.0
	cm.height = 0.3
	cm.radial_segments = 24
	mi.mesh = cm
	mi.material_override = _m(c)
	var o: Vector3 = fr[0]
	var uu: Vector3 = fr[1]
	var n: Vector3 = fr[2]
	mi.position = o + uu * u + Vector3(0, y, 0) + n * pn
	if absf(n.x) > 0.5:
		mi.rotation_degrees.z = 90.0
	else:
		mi.rotation_degrees.x = 90.0
	add_child(mi)


func _aparcamiento() -> void:
	# explanada vacía entre las manzanas: coches aparcados y nadie
	var suelo := _tex_mat("aparca", Color(0.3, 0.3, 0.31), Color(0.38, 0.38, 0.39), 0.7, 0.5, 0.9)
	U.box_m(self, Vector3(16.5, 0.02, 40.0), Vector3(-16.75, 0.012, -4.0), suelo)
	for i in 8:
		_b(Vector3(5.0, 0.03, 0.12), Vector3(-17.0, 0.025, -20.0 + i * 3.0), Color(0.9, 0.9, 0.85))
	var cols := [Color(0.75, 0.75, 0.78), Color(0.6, 0.1, 0.1), Color(0.12, 0.12, 0.14), Color(0.9, 0.9, 0.9), Color(0.2, 0.3, 0.55)]
	for i in 5:
		_coche(Vector3(-17.0, 0.0, -18.5 + i * 3.0 + (3.0 if i > 2 else 0.0)), cols[i])
	for zz in [-22.0, 10.0]:
		_palmera(Vector3(-11.0, 0.0, zz), 7.0)
		_palmera(Vector3(-22.5, 0.0, zz), 6.0)
	# kiosco
	_solido(Vector3(2.4, 2.6, 2.4), Vector3(-22.6, 1.3, 4.0), Color(0.2, 0.42, 0.3))
	_b(Vector3(3.0, 0.15, 3.0), Vector3(-22.6, 2.7, 4.0), Color(0.85, 0.85, 0.82))
	_farola(Vector3(-12.0, 0.0, -6.0), true)


func _coche(p: Vector3, c: Color) -> void:
	_solido(Vector3(4.2, 0.75, 1.8), p + Vector3(0, 0.6, 0), c)
	_b(Vector3(2.3, 0.6, 1.6), p + Vector3(0.2, 1.25, 0), c.darkened(0.1))
	_b(Vector3(2.32, 0.42, 1.62), p + Vector3(0.2, 1.27, 0), CRISTAL)
	for dx in [-1.35, 1.35]:
		for dz in [-0.85, 0.85]:
			var wh := U.cylinder(self, 0.34, 0.24, p + Vector3(dx, 0.34, dz), Color(0.05, 0.05, 0.05))
			wh.rotation_degrees.x = 90.0


func _chiringuito(p: Vector3) -> void:
	var paja := Color(0.72, 0.6, 0.36)
	_b(Vector3(9.0, 0.2, 7.0), p + Vector3(0, 0.1, 0), MADERA)
	_solido(Vector3(5.0, 1.1, 1.0), p + Vector3(0, 0.75, 1.8), MADERA.lightened(0.15))       # barra
	_b(Vector3(5.2, 0.08, 1.2), p + Vector3(0, 1.34, 1.8), MADERA.darkened(0.2))
	_solido(Vector3(5.0, 2.6, 0.3), p + Vector3(0, 1.4, 3.3), MADERA)
	for dx in [-4.2, 4.2]:
		for dz in [-3.2, 3.2]:
			_b(Vector3(0.2, 3.2, 0.2), p + Vector3(dx, 1.7, dz), MADERA.darkened(0.3))
	var techo := _b(Vector3(10.0, 0.5, 8.0), p + Vector3(0, 3.5, 0), paja)
	techo.material_override = _tex_mat("paja", paja.darkened(0.25), paja.lightened(0.15), 2.0, 2.0, 1.0)
	for i in 6:
		var x := -2.0 + i * 0.8
		U.cylinder(self, 0.18, 0.06, p + Vector3(x, 0.8, 0.9), Color(0.85, 0.85, 0.8))
		U.cylinder(self, 0.04, 0.7, p + Vector3(x, 0.45, 0.9), Color(0.3, 0.3, 0.3))
	var rot := Label3D.new()
	rot.text = "CHIRINGUITO"
	rot.font_size = 80
	rot.pixel_size = 0.008
	rot.outline_size = 10
	rot.modulate = Color(0.95, 0.4, 0.2)
	rot.position = p + Vector3(0, 3.9, -4.05)
	rot.rotation_degrees.y = 180.0
	add_child(rot)
	# la radio
	_b(Vector3(0.45, 0.28, 0.2), p + Vector3(0, 1.52, 2.0), Color(0.55, 0.12, 0.1))
	U.sphere(self, 0.06, p + Vector3(0.1, 1.55, 1.89), Color(0.15, 0.15, 0.15))
	_b(Vector3(0.12, 0.06, 0.02), p + Vector3(-0.1, 1.58, 1.89), Color(1.0, 0.75, 0.3), true)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.75, 0.45)
	l.light_energy = 1.0
	l.omni_range = 6.0
	l.position = p + Vector3(0, 3.0, 1.5)
	add_child(l)


func _torre_socorrista(p: Vector3) -> void:
	for dx in [-0.8, 0.8]:
		for dz in [-0.8, 0.8]:
			_b(Vector3(0.15, 2.4, 0.15), p + Vector3(dx, 1.2, dz), BLANCO)
	_solido(Vector3(2.0, 1.0, 2.0), p + Vector3(0, 0.5, 0), Color.WHITE, true, false)
	_b(Vector3(2.0, 1.2, 2.0), p + Vector3(0, 3.0, 0), Color(0.85, 0.15, 0.12))
	_b(Vector3(2.2, 0.12, 2.2), p + Vector3(0, 3.7, 0), BLANCO)
	_b(Vector3(1.6, 0.5, 0.05), p + Vector3(0, 3.1, 1.01), CRISTAL)
	var f := U.cylinder(self, 0.04, 2.0, p + Vector3(0.8, 4.6, 0.8), BLANCO)
	f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_b(Vector3(0.02, 0.5, 0.8), p + Vector3(0.8, 5.3, 1.2), Color(0.9, 0.75, 0.1))       # bandera amarilla


func _sombrilla(p: Vector3) -> void:
	var paja := Color(0.66, 0.55, 0.33)
	U.box_m(self, Vector3(0.1, 2.5, 0.1), p + Vector3(0, 1.25, 0), _m(MADERA))
	var c := U.cone_m(self, 0.05, 1.5, 0.7, p + Vector3(0, 2.55, 0), _tex_mat("paja", paja.darkened(0.25), paja.lightened(0.15), 2.0, 2.0, 1.0))
	c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if randf() < 0.6:
		for s in [-1.0, 1.0]:
			_b(Vector3(0.65, 0.25, 1.9), p + Vector3(s * 1.0, 0.25, 0.6), Color(0.95, 0.95, 0.95))
			var resp := _b(Vector3(0.65, 0.08, 0.7), p + Vector3(s * 1.0, 0.55, -0.35), Color(0.95, 0.95, 0.95))
			resp.rotation_degrees.x = -40.0


func _mesas_playa(p: Vector3) -> void:
	# dos filas de mesas del aula mirando al mar y una pizarra clavada en la arena
	var screens := [Color(0.2, 0.4, 0.85), Color(0.9, 0.92, 0.97)]
	for row in 2:
		var x := p.x + row * 2.4
		_solido(Vector3(0.9, 0.8, 4.0), Vector3(x, 0.4, p.z), Color(0.92, 0.92, 0.9))
		for i in 3:
			var z := p.z - 1.3 + i * 1.3
			_b(Vector3(0.04, 0.52, 0.9), Vector3(x + 0.1, 1.3, z), Color(0.05, 0.05, 0.07))
			_b(Vector3(0.01, 0.44, 0.82), Vector3(x + 0.075, 1.3, z), screens[i % 2], true)
			_b(Vector3(0.5, 0.08, 0.5), Vector3(x - 0.9, 0.5, z), Color(0.1, 0.15, 0.35))
			_b(Vector3(0.06, 0.5, 0.5), Vector3(x - 1.15, 0.8, z), Color(0.1, 0.15, 0.35))
	var pz := Node3D.new()
	pz.position = p + Vector3(6.0, 0.0, 0.0)
	pz.rotation_degrees = Vector3(0, -90.0, -4.0)
	add_child(pz)
	U.box_m(pz, Vector3(3.4, 1.8, 0.06), Vector3(0, 1.9, 0), _m(Color(0.6, 0.6, 0.62)))
	U.box_m(pz, Vector3(3.2, 1.6, 0.03), Vector3(0, 1.9, 0.03), _m(Color(0.97, 0.97, 0.97)))
	for dx in [-1.5, 1.5]:
		U.box_m(pz, Vector3(0.08, 1.2, 0.08), Vector3(dx, 0.6, 0), _m(Color(0.6, 0.6, 0.62)))
	var t := Label3D.new()
	t.text = "TAREA PARA HOY:\n¿DÓNDE ESTÁS?"
	t.font_size = 64
	t.pixel_size = 0.005
	t.outline_size = 0
	t.modulate = Color(0.1, 0.2, 0.6)
	t.position = Vector3(0, 1.95, 0.06)
	pz.add_child(t)
	U.bloques.append(Rect2(p.x + 5.6, p.z - 1.8, 0.8, 3.6))


func _taquillas(p: Vector3) -> void:
	var azul := Color(0.15, 0.3, 0.55)
	_solido(Vector3(0.6, 2.1, 5.0), p + Vector3(0, 1.05, 0), azul)
	for i in 9:
		_b(Vector3(0.02, 2.1, 0.03), p + Vector3(0.31, 1.05, -2.2 + i * 0.55), Color(0.05, 0.1, 0.2))
		_b(Vector3(0.02, 0.12, 0.25), p + Vector3(0.31, 1.7, -1.95 + i * 0.55), Color(0.05, 0.1, 0.2))
	var l := Label3D.new()
	l.text = "CESUR"
	l.font_size = 64
	l.pixel_size = 0.004
	l.outline_size = 0
	l.modulate = Color(0.85, 0.85, 0.9)
	l.position = p + Vector3(0.32, 2.3, 0)
	l.rotation_degrees.y = 90.0
	add_child(l)


func _senal(p: Vector3) -> void:
	_b(Vector3(0.08, 3.0, 0.08), p + Vector3(0, 1.5, 0), Color(0.6, 0.6, 0.62))
	_b(Vector3(0.05, 0.7, 2.4), p + Vector3(0.05, 2.7, 0), Color(0.1, 0.35, 0.2))
	_b(Vector3(0.04, 0.62, 2.32), p + Vector3(0.07, 2.7, 0), Color(0.9, 0.9, 0.9))
	_b(Vector3(0.04, 0.56, 2.26), p + Vector3(0.08, 2.7, 0), Color(0.1, 0.35, 0.2))
	var l := Label3D.new()
	l.text = "← MOJÁCAR PUEBLO   3 km"
	l.font_size = 48
	l.pixel_size = 0.0035
	l.outline_size = 0
	l.modulate = Color(0.95, 0.95, 0.95)
	l.position = p + Vector3(0.11, 2.7, 0)
	l.rotation_degrees.y = 90.0
	add_child(l)


# El pueblo blanco en lo alto del cerro (decorado lejano: no se puede llegar)
func _pueblo(c: Vector3) -> void:
	var tierra := _m(Color(0.56, 0.47, 0.34))
	var cerro := U.ellipsoid_m(self, Vector3(120.0, 85.0, 95.0), c + Vector3(0, -12.0, 0), tierra)
	cerro.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pie := U.ellipsoid_m(self, Vector3(210.0, 30.0, 170.0), c + Vector3(30.0, -12.0, 20.0), _m(Color(0.5, 0.44, 0.3)))
	pie.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var blanco := _m(Color(0.97, 0.96, 0.92))
	var sombra := _m(Color(0.6, 0.6, 0.62))
	for i in 260:
		var a := randf() * TAU
		var rr := sqrt(randf()) * 0.78
		var hx := cos(a) * rr
		var hz := sin(a) * rr
		var top := 85.0 * sqrt(maxf(0.0, 1.0 - hx * hx - hz * hz)) - 12.0
		if top < 30.0:
			continue
		var s := Vector3(randf_range(5.0, 11.0), randf_range(4.0, 9.0), randf_range(5.0, 11.0))
		var mi := U.box_m(self, s, c + Vector3(hx * 120.0, top + s.y / 2.0 - 2.0, hz * 95.0), blanco)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if randf() < 0.5:
			var v := U.box_m(self, Vector3(1.3, 1.6, 1.3), mi.position + Vector3(0, 0.3, 0) + (Vector3(s.x, 0, 0) * 0.5 if randf() < 0.5 else Vector3(0, 0, s.z) * 0.5), sombra)
			v.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# iglesia-fortaleza de Santa María en la cima
	var iglesia := U.box_m(self, Vector3(16.0, 14.0, 26.0), c + Vector3(-8.0, 79.0, 6.0), _m(Color(0.86, 0.78, 0.62)))
	iglesia.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var torre := U.box_m(self, Vector3(8.0, 24.0, 8.0), c + Vector3(-8.0, 84.0, -9.0), _m(Color(0.86, 0.78, 0.62)))
	torre.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _sierra() -> void:
	# Sierra Cabrera, al sur-oeste, más oscura y lejana
	var cols := [Color(0.46, 0.4, 0.32), Color(0.42, 0.37, 0.3), Color(0.5, 0.43, 0.33)]
	var pts := [[-700.0, 260.0, 260.0, 150.0], [-820.0, 40.0, 300.0, 210.0], [-760.0, -180.0, 260.0, 140.0],
		[-560.0, 480.0, 240.0, 120.0], [-380.0, 620.0, 200.0, 90.0], [-900.0, -420.0, 320.0, 170.0]]
	for i in pts.size():
		var p: Array = pts[i]
		var m := U.ellipsoid_m(self, Vector3(p[2], p[3], p[2] * 0.7), Vector3(p[0], -20.0, p[1]), _m(cols[i % 3]))
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _urbanizaciones() -> void:
	# casitas blancas y matorrales sueltos por la ladera
	var blanco := _m(Color(0.95, 0.94, 0.9))
	for i in 70:
		var d := randf_range(45.0, 330.0)
		var a := deg_to_rad(randf_range(-150.0, -40.0))
		var p := Vector3(-26.0 + cos(a) * d * 0.9 - 10.0, 0.0, sin(a) * d * 1.3 + 40.0)
		if p.x > -40.0:
			continue
		var s := Vector3(randf_range(5.0, 10.0), randf_range(3.0, 7.0), randf_range(5.0, 10.0))
		var mi := U.box_m(self, s, p + Vector3(0, s.y / 2.0, 0), blanco)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mato := _m(Color(0.32, 0.38, 0.2))
	for i in 120:
		var p := Vector3(randf_range(-260.0, -30.0), 0.0, randf_range(-260.0, 260.0))
		var e := U.ellipsoid_m(self, Vector3(1.2, 0.7, 1.2) * randf_range(0.7, 2.2), p, mato)
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# =============================================================
# HOTEL PUEBLO INDALO
# Recepción al oeste (lado del paseo), calle principal hasta la playa (este)
# =============================================================
func _indalo() -> void:
	titulo = "HOTEL PUEBLO INDALO"
	intro = "Recepción del Hotel Pueblo Indalo.\nCalles blancas, piscinas, palmeras... y ni un alma. Ni un solo huésped.\n¿Por qué tienes la llave de una habitación en el bolsillo? Investiga."
	game.start_pos = Vector3(-21.0, 0.05, 0.0)
	game.start_yaw = deg_to_rad(-90.0)          # mirando a la calle principal (este)
	U.limites = Rect2(-34.6, -39.6, 75.2, 79.2)
	_cielo(Vector2(32.0, -60.0))
	var losa := _tex_mat("losa", Color(0.82, 0.76, 0.64), Color(0.9, 0.85, 0.74), 0.5, 0.5, 0.8)
	var barro := _tex_mat("barro", Color(0.66, 0.36, 0.24), Color(0.76, 0.46, 0.32), 0.7, 0.7, 0.8)
	var cesped := _tex_mat("cesped", Color(0.24, 0.42, 0.17), Color(0.36, 0.55, 0.24), 0.4, 0.4, 1.0)
	var arena := _tex_mat("arena", Color(0.8, 0.7, 0.52), Color(0.9, 0.82, 0.64), 0.25, 0.35, 1.0)
	var monte := _tex_mat("monte", Color(0.52, 0.44, 0.3), Color(0.62, 0.55, 0.38), 0.02, 0.01, 1.0)
	U.box_m(self, Vector3(67.0, 0.02, 81.0), Vector3(-3.5, 0.0, 0.0), losa)
	U.box_m(self, Vector3(53.0, 0.03, 6.0), Vector3(3.5, 0.012, 0.0), barro)                 # calle principal
	U.box_m(self, Vector3(6.0, 0.03, 75.0), Vector3(-23.5, 0.012, 0.0), barro)               # calle de recepción
	U.box_m(self, Vector3(16.0, 0.02, 80.0), Vector3(38.0, 0.0, 0.0), arena)
	U.box_m(self, Vector3(3000.0, 0.02, 3000.0), Vector3(-1537.0, -0.02, 0.0), monte)
	_mar(41.5)
	for g in [Rect2(-6.0, -14.0, 13.0, 9.0), Rect2(-6.0, 5.0, 13.0, 9.0), Rect2(3.0, -27.0, 7.0, 10.0),
			Rect2(-14.0, 25.5, 8.0, 3.0), Rect2(24.0, 5.0, 5.5, 18.0), Rect2(24.0, -17.0, 5.5, 12.0)]:
		U.box_m(self, Vector3(g.size.x, 0.04, g.size.y), Vector3(g.get_center().x, 0.02, g.get_center().y), cesped)
	# recepción con soportales
	_recepcion()
	# bloques de 6 apartamentos (3 abajo y 3 arriba) a los dos lados de las calles
	var n_apto := 1
	for c in [Vector2(-14.0, -11.0), Vector2(16.0, -11.0), Vector2(-14.0, 11.0), Vector2(16.0, 11.0),
			Vector2(-20.0, -32.0), Vector2(-4.0, -32.0), Vector2(-20.0, 32.0), Vector2(-4.0, 32.0)]:
		var normal := Vector3(0, 0, 1) if c.y < 0.0 else Vector3(0, 0, -1)
		_apartamentos(Rect2(c.x - 6.0, c.y - 4.0, 12.0, 8.0), normal, n_apto)
		n_apto += 6
	for c in [Vector2(-31.0, -25.0), Vector2(-31.0, 25.0)]:
		_apartamentos(Rect2(c.x - 3.8, c.y - 6.0, 7.6, 12.0), Vector3(1, 0, 0), n_apto)
		n_apto += 6
	# piscinas: dos de adultos y dos infantiles
	_piscina(Rect2(-6.0, -24.0, 12.0, 7.0), true)
	_piscina(Rect2(-14.0, -24.0, 5.0, 5.0), false)
	_piscina(Rect2(-6.0, 17.0, 12.0, 7.0), false)
	_piscina(Rect2(-14.0, 19.0, 5.0, 5.0), false)
	_pista_tenis(Rect2(12.0, -38.0, 12.0, 18.0))
	_buffet(Rect2(12.0, 30.0, 14.0, 9.0))
	# palmeras y farolillos a lo largo de la calle principal
	for i in 7:
		var x := -17.0 + i * 7.5
		if x > 1.0 and x < 8.0:
			continue
		_palmera(Vector3(x, 0.0, -3.9), randf_range(6.0, 8.0))
		_palmera(Vector3(x + 3.0, 0.0, 3.9), randf_range(6.0, 8.0))
	for i in 6:
		_farolillo(Vector3(-15.0 + i * 8.5, 0.0, 3.4 if i % 2 == 0 else -3.4), i == 2)
	for p in [Vector3(-3.0, 0, -9.0), Vector3(4.0, 0, -12.0), Vector3(-3.5, 0, 9.5), Vector3(4.5, 0, 12.5), Vector3(7.0, 0, -22.0),
			Vector3(27.0, 0, 8.0), Vector3(26.5, 0, 19.0), Vector3(27.0, 0, -9.0), Vector3(-29.0, 0, -12.0), Vector3(-29.0, 0, 12.0)]:
		_palmera(p, randf_range(5.5, 8.5))
	# muro del recinto (y la tapia baja de la playa, con la salida a la arena)
	for zz in [-40.8, 40.8]:
		_solido(Vector3(68.0, 2.6, 0.4), Vector3(-3.5, 1.3, zz), BLANCO)
		_b(Vector3(68.2, 0.1, 0.55), Vector3(-3.5, 2.65, zz), OCRE)
	_solido(Vector3(0.4, 2.6, 82.0), Vector3(-37.4, 1.3, 0.0), BLANCO)
	for s in [-1.0, 1.0]:
		_solido(Vector3(0.4, 1.0, 37.5), Vector3(30.2, 0.5, s * 21.75), BLANCO)
		_b(Vector3(0.55, 0.08, 37.5), Vector3(30.2, 1.04, s * 21.75), OCRE)
		_b(Vector3(0.6, 3.4, 0.6), Vector3(30.2, 1.7, s * 3.2), BLANCO)
	_b(Vector3(0.6, 0.6, 7.0), Vector3(30.2, 3.6, 0.0), BLANCO)
	_b(Vector3(0.7, 0.08, 7.1), Vector3(30.2, 3.94, 0.0), OCRE)
	# la playa
	for sx in [33.0, 37.0]:
		for i in 8:
			var sz: float = -36.0 + i * 10.0 + (sx - 33.0)
			if absf(sz + 10.0) < 4.0 or absf(sz) < 4.0:
				continue
			_sombrilla(Vector3(sx, 0.0, sz))
	for zz in [-40.8, 40.8]:
		backroom_pared(self, Vector3(55.0, 0.0, zz), Vector3(50.0, 14.0, 0.4), Vector3(0, 0, -signf(zz)), 36.0)
	_pueblo(Vector3(-420.0, 0.0, -170.0))
	_sierra()
	_urbanizaciones()
	_fluorescente_flotante(Vector3(5.0, 4.6, 0.0))
	pistas = [
		["registro", "El libro de registro", "Tu nombre aparece en todas las páginas, escrito con tu letra.\nFecha de entrada: hoy.   Fecha de salida: —\nEn observaciones pone: «Grupo de CESUR. No dejar salir».", Vector3(-24.6, 0.0, 4.0)],
		["sillas", "Sillas en la piscina", "Sillas azules del aula flotando en la piscina, en filas, como en clase.\nLlevan las pegatinas del inventario de CESUR.\nEl agua no se mueve. Ni una onda.", Vector3(0.0, 0.0, -16.3)],
		["llave", "La llave del apartamento", "Hay una llave puesta en la puerta del apartamento.\nEl llavero no tiene número: pone «AULA».\nDentro solo hay una mesa, un ordenador y una pizarra.", Vector3(-15.8, 0.0, 6.2)],
		["tenis", "El marcador de la pista", "El marcador de la pista de tenis no cuenta juegos.\nCuenta vueltas:  «BUCLE %d».\nY la pelota lleva el logo de CESUR." % (Net.bucle + 1), Vector3(13.2, 0.0, -29.0)],
		["buffet", "El menú del buffet", "Menú del día: lo mismo que la máquina de la cafetería de CESUR.\nLas sillas de la terraza son las del aula.\nEn la tele del buffet sale el pasillo de CESUR, vacío.", Vector3(19.0, 0.0, 28.5)],
	]
	puerta_pos = Vector3(37.0, 0.0, -10.0)
	puerta_yaw = -90.0
	salida = ["Abres la puerta...", "Fluorescentes. Mesas. Una pizarra blanca.", "Vuelves a estar en el aula de CESUR."]
	game.box_spots = [
		[Vector3(0.5, 0.0, -10.0), 0.0, "los jardines"],
		[Vector3(7.0, 0.0, 26.0), 180.0, "la terraza del buffet"],
		[Vector3(-20.5, 0.0, -6.5), 0.0, "la entrada"],
		[Vector3(35.0, 0.0, 20.0), 0.0, "la playa"],
		[Vector3(6.0, 0.0, -31.0), 90.0, "la pista de tenis"],
		[Vector3(-12.0, 0.0, 30.5), 90.0, "los apartamentos del fondo"],
	]
	spawns = [Vector3(-29.0, 0, -37.0), Vector3(-29.0, 0, 37.0), Vector3(0.0, 0, -38.5), Vector3(0.0, 0, 38.5),
		Vector3(28.0, 0, -38.0), Vector3(28.0, 0, 38.0), Vector3(39.0, 0, -30.0), Vector3(39.0, 0, 30.0),
		Vector3(8.0, 0, -36.0), Vector3(9.0, 0, 37.0), Vector3(-24.0, 0, -16.0), Vector3(-24.0, 0, 16.0)]
	game._wall_buy("subfusil", Vector3(-25.97, 1.7, -6.5), 90.0, Vector3(-25.0, 0, -6.5))
	game._wall_buy("fusil", Vector3(19.0, 1.7, 6.97), 180.0, Vector3(19.0, 0, 6.1))
	game._wall_buy("francotirador", Vector3(36.0, 1.9, 40.58), 180.0, Vector3(36.0, 0, 39.3))
	game._wall_buy("revolver", Vector3(-25.97, 1.7, -3.0), 90.0, Vector3(-25.0, 0, -3.0))
	game._wall_buy("uzi", Vector3(39.5, 1.7, 40.58), 180.0, Vector3(39.5, 0, 39.3))
	game._wall_buy("escopeta", Vector3(32.5, 1.7, 40.58), 180.0, Vector3(32.5, 0, 39.3))


func _recepcion() -> void:
	var r := Rect2(-36.0, -9.0, 10.0, 18.0)
	var c := Vector3(-31.0, 0.0, 0.0)
	_solido(Vector3(r.size.x, 7.0, r.size.y), c + Vector3(0, 3.5, 0), BLANCO)
	_b(Vector3(r.size.x + 0.15, 0.4, r.size.y + 0.15), c + Vector3(0, 7.2, 0), BLANCO)
	_b(Vector3(r.size.x + 0.2, 0.08, r.size.y + 0.2), c + Vector3(0, 7.3, 0), TEJA)
	# torrecilla con ventana de arco
	_b(Vector3(4.0, 3.2, 4.0), Vector3(-31.0, 8.6, 0.0), BLANCO)
	_b(Vector3(4.4, 0.25, 4.4), Vector3(-31.0, 10.3, 0.0), TEJA)
	var ft := _frame(Rect2(-33.0, -2.0, 4.0, 4.0), Vector3(1, 0, 0))
	_fb(ft, 1.2, 1.4, 0.05, 0.0, 8.3, 0.02, CRISTAL)
	_arco(ft, 1.2, 0.0, 9.0, -0.12, CRISTAL)
	# soportales con 5 arcos
	var fr := _frame(r, Vector3(1, 0, 0))
	_b(Vector3(3.0, 0.4, 18.0), Vector3(-24.5, 3.8, 0.0), BLANCO)
	_b(Vector3(3.1, 0.08, 18.1), Vector3(-24.5, 4.04, 0.0), OCRE)
	for i in 6:
		var z := -9.0 + i * 3.6
		_solido(Vector3(0.6, 3.6, 0.6), Vector3(-23.3, 1.8, z), BLANCO)
	_b(Vector3(0.62, 0.7, 18.0), Vector3(-23.3, 3.25, 0.0), BLANCO)          # dintel de los soportales
	_fb(fr, 2.4, 2.8, 0.06, 0.0, 1.4, 0.02, CRISTAL)                         # puerta de cristal
	_fb(fr, 2.6, 0.1, 0.08, 0.0, 2.85, 0.03, MADERA)
	for u in [-5.4, 5.4]:
		_ventana(fr, u, 1.6, VERDE, false)
	_rotulo(fr, "PUEBLO INDALO", 0.0, 5.6, TEJA)
	var ind := Node3D.new()
	add_child(ind)
	ind.position = Vector3(-25.9, 4.6, -6.2)
	ind.rotation_degrees.y = 90.0
	_indalo_figura(ind, 0.5, TEJA)
	# mostrador de recepción bajo los soportales, con el libro de registro
	_solido(Vector3(0.8, 1.1, 3.0), Vector3(-25.0, 0.55, 4.0), MADERA)
	_b(Vector3(0.9, 0.06, 3.1), Vector3(-25.0, 1.13, 4.0), MADERA.darkened(0.3))
	_b(Vector3(0.35, 0.04, 0.5), Vector3(-25.0, 1.18, 3.6), Color(0.55, 0.1, 0.1))
	_b(Vector3(0.1, 0.05, 0.08), Vector3(-25.1, 1.2, 4.5), Color(0.85, 0.75, 0.3))     # timbre
	for i in 3:
		_fluorescente(Vector3(-24.5, 3.55, -5.4 + i * 5.4))
	for u in [-3.0, 3.0]:
		var pz := _b(Vector3(0.9, 0.9, 0.9), Vector3(-22.4, 0.45, u * 2.5), TEJA)    # macetas
		pz.scale = Vector3(1, 1, 1)
		U.ellipsoid_m(self, Vector3(0.7, 0.9, 0.7), Vector3(-22.4, 1.4, u * 2.5), _m(Color(0.22, 0.45, 0.2)))


# Bloque de 6 apartamentos: 3 en la planta baja (puerta y reja) y 3 arriba
# (balcón con arco). Los números siguen por todo el complejo.
func _apartamentos(r: Rect2, normal: Vector3, first: int) -> void:
	var h := 6.4
	var c := Vector3(r.get_center().x, 0.0, r.get_center().y)
	_solido(Vector3(r.size.x, h, r.size.y), c + Vector3(0, h / 2.0, 0), BLANCO)
	_b(Vector3(r.size.x + 0.12, 0.4, r.size.y + 0.12), c + Vector3(0, h + 0.2, 0), BLANCO)
	_b(Vector3(r.size.x + 0.18, 0.08, r.size.y + 0.18), c + Vector3(0, h + 0.3, 0), OCRE)
	_b(Vector3(r.size.x + 0.04, 0.5, r.size.y + 0.04), c + Vector3(0, 0.25, 0), Color(0.78, 0.6, 0.45))   # zócalo
	_b(Vector3(r.size.x + 0.1, 0.12, r.size.y + 0.1), c + Vector3(0, 3.2, 0), OCRE)                       # cornisa entre plantas
	for k in 2:
		var ch := c + Vector3(randf_range(-0.35, 0.35) * r.size.x, h + 0.7, randf_range(-0.3, 0.3) * r.size.y)
		_b(Vector3(0.55, 1.2, 0.55), ch, BLANCO)
		_b(Vector3(0.75, 0.1, 0.75), ch + Vector3(0, 0.62, 0), TEJA)
	var colores := [VERDE, AZUL, MADERA]
	for side in [1.0, -1.0]:
		var fr := _frame(r, normal * side)
		var width: float = fr[3]
		for i in 3:
			var u := -width / 2.0 + (i + 0.5) * width / 3.0
			if side > 0.0:
				var col: Color = colores[(first + i) % 3]
				_fb(fr, 1.1, 2.2, 0.08, u - 1.0, 1.1, 0.03, col)                          # puerta
				_fb(fr, 0.07, 0.07, 0.1, u - 0.6, 1.1, 0.07, Color(0.85, 0.75, 0.3))      # pomo
				_fb(fr, 1.3, 0.1, 0.1, u - 1.0, 2.25, 0.04, OCRE)
				var num := Label3D.new()
				num.text = str(first + i)
				num.font_size = 40
				num.pixel_size = 0.004
				num.outline_size = 0
				num.modulate = Color(0.2, 0.25, 0.5)
				var o: Vector3 = fr[0]
				var uu: Vector3 = fr[1]
				var n: Vector3 = fr[2]
				num.position = o + uu * (u - 0.2) + Vector3(0, 2.0, 0) + n * 0.05
				num.rotation_degrees.y = rad_to_deg(atan2(n.x, n.z))
				add_child(num)
				# ventana con reja
				_fb(fr, 0.9, 1.1, 0.06, u + 0.7, 1.55, 0.02, CRISTAL)
				for k in 4:
					_fb(fr, 0.03, 1.15, 0.03, u + 0.37 + k * 0.22, 1.55, 0.1, Color(0.1, 0.1, 0.1))
				# planta de arriba: balcón con ventana de arco
				_fb(fr, 1.0, 1.4, 0.06, u, 4.5, 0.02, CRISTAL)
				_arco(fr, 1.0, u, 5.2, -0.13, CRISTAL)
				_fb(fr, 1.9, 0.1, 0.7, u, 3.75, 0.35, BLANCO)
				_fb(fr, 1.9, 0.6, 0.05, u, 4.05, 0.68, MADERA.darkened(0.2))
			else:
				_ventana(fr, u, 4.5, colores[i % 3], false)
		if side > 0.0 and randf() < 0.7:
			_buganvilla(fr, -width / 2.0 + 0.6, h)


func _piscina(r: Rect2, sillas: bool) -> void:
	var c := Vector3(r.get_center().x, 0.0, r.get_center().y)
	var playa := Color(0.9, 0.88, 0.82)
	_b(Vector3(r.size.x + 3.0, 0.05, r.size.y + 3.0), c + Vector3(0, 0.025, 0), playa)       # suelo alrededor
	_b(Vector3(r.size.x + 0.6, 0.14, r.size.y + 0.6), c + Vector3(0, 0.07, 0), Color(0.96, 0.95, 0.92))   # bordillo
	var agua := StandardMaterial3D.new()
	agua.albedo_color = Color(0.25, 0.75, 0.85)
	agua.roughness = 0.05
	agua.metallic_specular = 0.9
	agua.emission_enabled = true
	agua.emission = Color(0.05, 0.25, 0.3)
	U.box_m(self, Vector3(r.size.x, 0.02, r.size.y), c + Vector3(0, 0.15, 0), agua)
	# no te puedes meter: barrera invisible (y los zombis la rodean)
	_solido(Vector3(r.size.x, 1.2, r.size.y), c + Vector3(0, 0.6, 0), Color.WHITE, true, false)
	# escalerilla y tumbonas
	for k in 2:
		_b(Vector3(0.05, 1.0, 0.05), c + Vector3(r.size.x / 2.0 - 1.0 + k * 0.5, 0.6, -r.size.y / 2.0 - 0.15), Color(0.8, 0.8, 0.82))
	for i in int(r.size.x / 2.2):
		var x := r.position.x + 1.0 + i * 2.2
		var tz := r.end.y + 1.0 if r.position.y < 0.0 else r.position.y - 1.0
		_b(Vector3(0.7, 0.3, 1.9), Vector3(x, 0.3, tz), Color(0.97, 0.97, 0.97))
	if sillas:
		var azul := _m(Color(0.1, 0.15, 0.35))
		for row in 2:
			for i in 4:
				var ch := Node3D.new()
				ch.position = c + Vector3(-3.6 + i * 2.4, 0.2, -1.2 + row * 2.2)
				ch.rotation_degrees = Vector3(randf_range(-8, 8), randf_range(-15, 15), randf_range(-8, 8))
				add_child(ch)
				U.box_m(ch, Vector3(0.5, 0.08, 0.5), Vector3(0, 0, 0), azul)
				U.box_m(ch, Vector3(0.5, 0.5, 0.06), Vector3(0, 0.28, 0.25), azul)


func _pista_tenis(r: Rect2) -> void:
	var c := Vector3(r.get_center().x, 0.0, r.get_center().y)
	_b(Vector3(r.size.x, 0.04, r.size.y), c + Vector3(0, 0.02, 0), Color(0.2, 0.45, 0.3))
	_b(Vector3(r.size.x - 3.0, 0.045, r.size.y - 4.0), c + Vector3(0, 0.025, 0), Color(0.25, 0.4, 0.62))
	var blanco := Color(0.95, 0.95, 0.95)
	for dx in [-(r.size.x - 3.0) / 2.0, (r.size.x - 3.0) / 2.0]:
		_b(Vector3(0.08, 0.05, r.size.y - 4.0), c + Vector3(dx, 0.03, 0), blanco)
	for dz in [-(r.size.y - 4.0) / 2.0, (r.size.y - 4.0) / 2.0, -3.5, 3.5]:
		_b(Vector3(r.size.x - 3.0, 0.05, 0.08), c + Vector3(0, 0.03, dz), blanco)
	_b(Vector3(0.08, 0.05, 7.0), c + Vector3(0, 0.03, 0), blanco)
	_b(Vector3(r.size.x - 2.6, 0.9, 0.03), c + Vector3(0, 0.45, 0), Color(0.1, 0.1, 0.1))     # red
	_b(Vector3(r.size.x - 2.6, 0.06, 0.05), c + Vector3(0, 0.92, 0), blanco)
	# valla metálica (con hueco de entrada al oeste)
	var valla := StandardMaterial3D.new()
	valla.albedo_color = Color(0.15, 0.3, 0.2, 0.45)
	valla.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var hy := 1.6
	var parts := [
		[Vector3(r.size.x, 3.2, 0.06), Vector3(c.x, hy, r.position.y)],
		[Vector3(r.size.x, 3.2, 0.06), Vector3(c.x, hy, r.end.y)],
		[Vector3(0.06, 3.2, r.size.y), Vector3(r.end.x, hy, c.z)],
		[Vector3(0.06, 3.2, 7.0), Vector3(r.position.x, hy, r.position.y + 3.5)],
		[Vector3(0.06, 3.2, 7.0), Vector3(r.position.x, hy, r.end.y - 3.5)],
	]
	for p in parts:
		var sb := _solido(p[0], p[1], Color.WHITE, true, false)
		U.box_m(sb, p[0], Vector3.ZERO, valla)
	# marcador
	_b(Vector3(0.1, 1.2, 2.4), Vector3(r.position.x + 0.3, 2.2, c.z + 1.0), Color(0.1, 0.1, 0.12))
	var l := Label3D.new()
	l.text = "BUCLE  %d" % (Net.bucle + 1)
	l.font_size = 64
	l.pixel_size = 0.005
	l.outline_size = 0
	l.modulate = Color(1.0, 0.6, 0.15)
	l.position = Vector3(r.position.x + 0.36, 2.2, c.z + 1.0)
	l.rotation_degrees.y = 90.0
	add_child(l)
	U.sphere(self, 0.07, Vector3(r.position.x + 1.4, 0.07, c.z + 1.5), Color(0.85, 0.95, 0.2))


func _buffet(r: Rect2) -> void:
	var c := Vector3(r.get_center().x, 0.0, r.get_center().y)
	_solido(Vector3(r.size.x, 4.5, r.size.y), c + Vector3(0, 2.25, 0), BLANCO)
	_b(Vector3(r.size.x + 0.15, 0.1, r.size.y + 0.15), c + Vector3(0, 4.42, 0), TEJA)
	_b(Vector3(r.size.x + 0.06, 0.2, r.size.y + 0.06), c + Vector3(0, 4.55, 0), BLANCO)
	var fr := _frame(r, Vector3(0, 0, -1))
	for i in 4:
		var u := -5.25 + i * 3.5
		_fb(fr, 2.2, 2.4, 0.05, u, 1.3, 0.02, CRISTAL)
		_arco(fr, 2.2, u, 2.5, -0.13, CRISTAL)
	_rotulo(fr, "BUFFET", 0.0, 3.8, TEJA)
	# tele con el pasillo de CESUR
	_fb(fr, 1.6, 0.9, 0.08, 4.8, 3.6, 0.05, Color(0.05, 0.05, 0.06))
	_fb(fr, 1.45, 0.78, 0.02, 4.8, 3.6, 0.1, Color(0.5, 0.48, 0.35), true)
	# terraza con pérgola y mesas (con sillas del aula)
	_b(Vector3(r.size.x, 0.04, 7.0), Vector3(c.x, 0.03, r.position.y - 3.5), Color(0.75, 0.48, 0.34))
	for i in 4:
		var x := r.position.x + 1.5 + i * 3.6
		_b(Vector3(0.18, 2.8, 0.18), Vector3(x, 1.4, r.position.y - 6.8), MADERA)
		_b(Vector3(0.12, 0.12, 7.0), Vector3(x, 2.85, r.position.y - 3.5), MADERA)
	_b(Vector3(r.size.x, 0.12, 0.12), Vector3(c.x, 2.85, r.position.y - 6.8), MADERA)
	var azul := _m(Color(0.1, 0.15, 0.35))
	for i in 3:
		for j in 2:
			var p := Vector3(r.position.x + 2.6 + i * 4.0, 0.0, r.position.y - 2.0 - j * 2.8)
			_solido(Vector3(1.0, 0.75, 1.0), p + Vector3(0, 0.375, 0), Color(0.95, 0.95, 0.95))
			for s in [-1.0, 1.0]:
				U.box_m(self, Vector3(0.5, 0.08, 0.5), p + Vector3(s * 0.85, 0.48, 0), azul)
				U.box_m(self, Vector3(0.06, 0.5, 0.5), p + Vector3(s * 1.1, 0.76, 0), azul)
	var carta := _b(Vector3(0.6, 0.9, 0.06), Vector3(c.x - 0.5, 0.75, r.position.y - 0.3), Color(0.15, 0.1, 0.08))
	carta.rotation_degrees.x = -10.0


# =============================================================
# Piezas comunes
# =============================================================
func _cielo(sol: Vector2) -> void:
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.22, 0.42, 0.72)
	sm.sky_horizon_color = Color(0.72, 0.78, 0.84)
	sm.ground_horizon_color = Color(0.72, 0.74, 0.74)
	sm.ground_bottom_color = Color(0.35, 0.32, 0.28)
	sm.sun_angle_max = 20.0
	sm.sky_energy_multiplier = 1.0
	sky = Sky.new()
	sky.sky_material = sm
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-sol.x, sol.y, 0.0)
	sun.light_color = Color(1.0, 0.92, 0.8)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	sun.light_angular_distance = 0.6
	sun.light_volumetric_fog_energy = 0.3
	add_child(sun)


func _suelo_fisico() -> void:
	_solido(Vector3(220.0, 1.0, 220.0), Vector3(0, -0.5, 0), Color.WHITE, false, false)


func _mar(x0: float) -> void:
	sea_mat = StandardMaterial3D.new()
	sea_mat.albedo_color = Color(0.06, 0.3, 0.42)
	sea_mat.roughness = 0.12
	sea_mat.metallic_specular = 0.8
	var nt := NoiseTexture2D.new()
	var nz := FastNoiseLite.new()
	nz.frequency = 0.03
	nt.noise = nz
	nt.seamless = true
	nt.as_normal_map = true
	nt.bump_strength = 4.0
	sea_mat.normal_enabled = true
	sea_mat.normal_texture = nt
	sea_mat.normal_scale = 0.6
	sea_mat.uv1_triplanar = true
	sea_mat.uv1_scale = Vector3(0.12, 0.12, 0.12)
	U.box_m(self, Vector3(3000.0, 0.02, 3000.0), Vector3(x0 + 1500.0, -0.03, 0.0), sea_mat)
	var espuma := StandardMaterial3D.new()
	espuma.albedo_color = Color(0.92, 0.95, 0.95, 0.7)
	espuma.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	U.box_m(self, Vector3(1.4, 0.03, 3000.0), Vector3(x0 + 0.4, 0.0, 0.0), espuma)
	var orilla := _m(Color(0.62, 0.55, 0.42))
	U.box_m(self, Vector3(2.4, 0.015, 3000.0), Vector3(x0 - 1.0, 0.004, 0.0), orilla)
	# no se puede nadar
	_solido(Vector3(1.0, 6.0, 3000.0), Vector3(x0 + 0.6, 3.0, 0.0), Color.WHITE, false, false)


func _palmera(p: Vector3, h: float) -> void:
	var tronco := _tex_mat("tronco", Color(0.38, 0.28, 0.18), Color(0.55, 0.42, 0.28), 1.6, 0.6, 1.0)
	var lean := Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6))
	var segs := 6
	var prev := p
	for i in segs:
		var k := float(i + 1) / segs
		var nxt := p + Vector3(0, h * k, 0) + lean * k * k
		U.limb_m(self, prev, nxt, 0.22 - 0.06 * k, 0.2 - 0.06 * k, tronco)
		prev = nxt
	var hoja := _m(Color(0.22, 0.4, 0.16))
	for i in 9:
		var a := TAU * i / 9.0 + randf() * 0.3
		var dir := Vector3(cos(a), 0, sin(a))
		var mid := prev + dir * 1.4 + Vector3(0, 0.25, 0)
		var tip := prev + dir * 2.8 + Vector3(0, -0.7, 0)
		var l1 := U.limb_m(self, prev, mid, 0.07, 0.2, hoja)
		var l2 := U.limb_m(self, mid, tip, 0.2, 0.04, hoja)
		l1.scale.x = 1.8
		l2.scale.x = 1.8
	U.sphere(self, 0.3, prev, Color(0.4, 0.3, 0.15))
	_solido(Vector3(0.45, 3.0, 0.45), p + Vector3(0, 1.5, 0), Color.WHITE, false, false)


func _farola(p: Vector3, flicker: bool) -> void:
	var gris := Color(0.18, 0.2, 0.22)
	_b(Vector3(0.14, 4.6, 0.14), p + Vector3(0, 2.3, 0), gris)
	_b(Vector3(1.2, 0.1, 0.1), p + Vector3(0.5, 4.6, 0), gris)
	_b(Vector3(0.5, 0.18, 0.3), p + Vector3(1.05, 4.5, 0), gris)
	_b(Vector3(0.42, 0.04, 0.24), p + Vector3(1.05, 4.4, 0), Color(1.0, 0.85, 0.55), true)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.82, 0.55)
	l.light_energy = 0.6
	l.omni_range = 9.0
	l.position = p + Vector3(1.05, 4.2, 0)
	add_child(l)
	if flicker:
		l.set_meta("base", 0.6)
		game.hall_lights.append(l)


func _farolillo(p: Vector3, flicker: bool) -> void:
	var hierro := Color(0.1, 0.1, 0.1)
	_b(Vector3(0.12, 3.0, 0.12), p + Vector3(0, 1.5, 0), hierro)
	_b(Vector3(0.36, 0.5, 0.36), p + Vector3(0, 3.25, 0), hierro)
	_b(Vector3(0.28, 0.4, 0.28), p + Vector3(0, 3.25, 0), Color(1.0, 0.8, 0.45), true)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.8, 0.5)
	l.light_energy = 0.5
	l.omni_range = 7.0
	l.position = p + Vector3(0, 3.0, 0)
	add_child(l)
	if flicker:
		l.set_meta("base", 0.5)
		game.hall_lights.append(l)


func _banco(p: Vector3, yaw: float) -> void:
	var n := Node3D.new()
	n.position = p
	n.rotation_degrees.y = yaw
	add_child(n)
	U.box_m(n, Vector3(1.8, 0.08, 0.5), Vector3(0, 0.45, 0), _m(MADERA))
	U.box_m(n, Vector3(1.8, 0.4, 0.06), Vector3(0, 0.75, 0.24), _m(MADERA))
	for dx in [-0.75, 0.75]:
		U.box_m(n, Vector3(0.08, 0.45, 0.5), Vector3(dx, 0.22, 0), _m(Color(0.15, 0.15, 0.16)))


# El Indalo: el muñeco con un arco sobre la cabeza, símbolo de Mojácar
func _indalo_figura(parent: Node3D, s: float, c: Color) -> void:
	var m := _m(c)
	var r := 0.07 * s
	U.limb_m(parent, Vector3(-0.35, 0, 0) * s, Vector3(0, 0.75, 0) * s, r, r, m)
	U.limb_m(parent, Vector3(0.35, 0, 0) * s, Vector3(0, 0.75, 0) * s, r, r, m)
	U.limb_m(parent, Vector3(0, 0.75, 0) * s, Vector3(0, 1.5, 0) * s, r, r, m)
	U.limb_m(parent, Vector3(-0.75, 1.35, 0) * s, Vector3(0.75, 1.35, 0) * s, r, r, m)
	U.sphere(parent, 0.14 * s, Vector3(0, 1.68, 0) * s, c)
	var prev := Vector3(-0.75, 1.35, 0) * s
	for i in range(1, 13):
		var a := PI - PI * i / 12.0
		var p := Vector3(cos(a) * 0.75, 1.35 + sin(a) * 0.95, 0) * s
		U.limb_m(parent, prev, p, r, r, m)
		prev = p


func _indalo_estatua(p: Vector3, s: float) -> void:
	_solido(Vector3(1.8, 1.0, 1.8), p + Vector3(0, 0.5, 0), Color(0.75, 0.68, 0.55))
	_b(Vector3(2.0, 0.1, 2.0), p + Vector3(0, 1.02, 0), OCRE)
	var n := Node3D.new()
	n.position = p + Vector3(0, 1.05, 0)
	n.rotation_degrees.y = 90.0
	add_child(n)
	_indalo_figura(n, s, Color(0.35, 0.22, 0.12))
	var l := Label3D.new()
	l.text = "INDALO"
	l.font_size = 48
	l.pixel_size = 0.004
	l.outline_size = 0
	l.modulate = Color(0.3, 0.2, 0.1)
	l.position = p + Vector3(-0.92, 0.5, 0)
	l.rotation_degrees.y = -90.0
	add_child(l)


# Un panel fluorescente del techo de CESUR flotando donde no debería
func _fluorescente_flotante(p: Vector3) -> void:
	_fluorescente(p)
	var l := OmniLight3D.new()
	l.light_color = Color(0.9, 0.95, 1.0)
	l.light_energy = 0.8
	l.omni_range = 6.0
	l.position = p + Vector3(0, -0.4, 0)
	add_child(l)
	l.set_meta("base", 0.8)
	game.hall_lights.append(l)


func _fluorescente(p: Vector3) -> void:
	_b(Vector3(1.3, 0.08, 0.5), p, Color(0.8, 0.8, 0.8))
	var tubo := _b(Vector3(1.2, 0.03, 0.4), p + Vector3(0, -0.05, 0), Color(0.95, 0.97, 1.0), true)
	tubo.material_override.emission_energy_multiplier = 3.0
	tubo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ---------------- Backrooms ----------------
static func _papel() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = U._noise_tex("papel", FastNoiseLite.TYPE_PERLIN, 0.06, AMARILLO.darkened(0.12), AMARILLO.lightened(0.06), Vector2(0.2, 2.0))
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.6, 0.25, 0.6)
	m.roughness = 0.9
	return m


static func _moqueta() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = U._noise_tex("moqueta", FastNoiseLite.TYPE_CELLULAR, 0.9, Color(0.42, 0.38, 0.22), Color(0.55, 0.5, 0.3))
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.5, 0.5, 0.5)
	m.roughness = 1.0
	return m


# Pared de papel pintado amarillo donde se acaba el mundo (con moqueta y un fluorescente)
static func backroom_pared(parent: Node3D, c: Vector3, size: Vector3, normal: Vector3, txt_x: float) -> void:
	var sb := StaticBody3D.new()
	sb.position = c + Vector3(0, size.y / 2.0, 0)
	parent.add_child(sb)
	U.box_m(sb, size, Vector3.ZERO, _papel())
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	sb.add_child(cs)
	U.box_m(parent, Vector3(size.x, 0.03, 3.0) if absf(normal.z) > 0.5 else Vector3(3.0, 0.03, size.z),
		c + normal * 1.6 + Vector3(0, 0.02, 0), _moqueta())
	U.box_m(parent, Vector3(size.x, 0.25, 0.06) if absf(normal.z) > 0.5 else Vector3(0.06, 0.25, size.z),
		c + normal * (size.z / 2.0 + 0.03 if absf(normal.z) > 0.5 else size.x / 2.0 + 0.03) + Vector3(0, 0.12, 0), U.mat(Color(0.55, 0.48, 0.25)))
	var t := Label3D.new()
	t.text = "NO HAY SALIDA"
	t.font_size = 96
	t.pixel_size = 0.006
	t.outline_size = 0
	t.modulate = Color(0.15, 0.12, 0.1, 0.85)
	t.position = Vector3(txt_x, 1.8, c.z) + normal * 0.25
	t.rotation_degrees = Vector3(0, rad_to_deg(atan2(normal.x, normal.z)), -3.0)
	parent.add_child(t)


# Sala amarilla enorme con moqueta, techo de placas y fluorescentes (el final de CESUR)
static func backroom_sala(parent: Node3D, c: Vector3, size: Vector3, luces: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Backroom"
	parent.add_child(root)
	var papel := _papel()
	U.box_m(root, Vector3(size.x, 0.04, size.z), c + Vector3(0, 0.03, 0), _moqueta())
	var hx := size.x / 2.0
	var hz := size.z / 2.0
	for w in [[Vector3(size.x, size.y, 0.3), Vector3(0, 0, -hz)], [Vector3(size.x, size.y, 0.3), Vector3(0, 0, hz)],
			[Vector3(0.3, size.y, size.z), Vector3(-hx, 0, 0)], [Vector3(0.3, size.y, size.z), Vector3(hx, 0, 0)]]:
		U.box_m(root, w[0], c + w[1] + Vector3(0, size.y / 2.0, 0), papel)
	var techo := U.box_m(root, Vector3(size.x, 0.2, size.z), c + Vector3(0, size.y + 0.1, 0), U.mat(Color(0.82, 0.8, 0.7)))
	techo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tubo := U.mat(Color(1.0, 0.97, 0.85), true)
	tubo.emission_energy_multiplier = 3.5
	var x := -hx + 3.0
	while x < hx - 1.0:
		var z := -hz + 3.0
		while z < hz - 1.0:
			var p := U.box_m(root, Vector3(1.2, 0.04, 0.6), c + Vector3(x, size.y - 0.02, z), tubo)
			p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			z += 6.0
		x += 6.0
	for i in luces:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.93, 0.7)
		l.light_energy = 2.2
		l.omni_range = maxf(size.x, size.z) * 0.6
		l.position = c + Vector3(lerpf(-hx * 0.5, hx * 0.5, float(i % 2)), size.y - 1.0, lerpf(-hz * 0.6, hz * 0.6, float(i) / maxf(1.0, luces - 1)))
		root.add_child(l)
	return root


# Zumbido de fluorescentes (en bucle)
static func zumbido() -> AudioStreamWAV:
	var rate := 22050
	var n := rate
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	for i in n:
		var tt := float(i) / rate
		lp = lerpf(lp, randf() * 2.0 - 1.0, 0.05)
		var s := sin(tt * TAU * 100.0) * 0.25 + sin(tt * TAU * 200.0) * 0.15 + sin(tt * TAU * 300.0) * 0.06 + lp * 0.15
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 26000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = n
	return w


# La puerta del aula, sola, donde no debería haber ninguna puerta
static func puerta_aula(parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation_degrees.y = yaw
	parent.add_child(root)
	var marco := U.mat(Color(0.6, 0.6, 0.62))
	U.box_m(root, Vector3(0.12, 2.5, 0.2), Vector3(-0.66, 1.25, 0), marco)
	U.box_m(root, Vector3(0.12, 2.5, 0.2), Vector3(0.66, 1.25, 0), marco)
	U.box_m(root, Vector3(1.44, 0.12, 0.2), Vector3(0, 2.5, 0), marco)
	var negro := U.mat(Color(0.0, 0.0, 0.0))
	U.box_m(root, Vector3(1.2, 2.4, 0.04), Vector3(0, 1.2, -0.06), negro)
	var hoja := Node3D.new()
	hoja.name = "Hoja"
	hoja.position = Vector3(-0.6, 0, 0)
	root.add_child(hoja)
	U.box_m(hoja, Vector3(1.2, 2.4, 0.06), Vector3(0.6, 1.2, 0), U.mat(Color(0.55, 0.36, 0.2)))
	U.box_m(hoja, Vector3(0.3, 0.6, 0.07), Vector3(0.6, 1.7, 0), U.mat(Color(0.7, 0.8, 0.85), true))
	U.box_m(hoja, Vector3(0.14, 0.04, 0.1), Vector3(1.05, 1.05, 0.05), U.mat(Color(0.8, 0.8, 0.82)))
	var luz := U.box_m(root, Vector3(1.2, 0.03, 0.4), Vector3(0, 0.015, 0.2), U.mat(Color(1.0, 0.95, 0.8), true))
	luz.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cartel := Label3D.new()
	cartel.text = "AULA"
	cartel.font_size = 64
	cartel.pixel_size = 0.004
	cartel.outline_size = 0
	cartel.modulate = Color(0.02, 0.08, 0.38)
	cartel.position = Vector3(0, 2.75, 0.02)
	root.add_child(cartel)
	U.box_m(root, Vector3(0.7, 0.26, 0.03), Vector3(0, 2.75, 0), U.mat(Color(0.95, 0.95, 0.95)))
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.95, 0.8)
	l.light_energy = 1.5
	l.omni_range = 5.0
	l.position = Vector3(0, 2.0, 0.8)
	root.add_child(l)
	return root


# ---------------- Utilidades ----------------
func _m(c: Color, emit: bool = false) -> StandardMaterial3D:
	var k := "%s|%s" % [c, emit]
	if not _mats.has(k):
		_mats[k] = U.mat(c, emit)
	return _mats[k]


func _tex_mat(key: String, c0: Color, c1: Color, freq: float, scale: float, rough: float) -> StandardMaterial3D:
	var k := "tex|" + key
	if _mats.has(k):
		return _mats[k]
	var m := StandardMaterial3D.new()
	m.albedo_texture = U._noise_tex("mapa_" + key, FastNoiseLite.TYPE_PERLIN, freq, c0, c1)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.roughness = rough
	_mats[k] = m
	return m


func _b(size: Vector3, pos: Vector3, c: Color, emit: bool = false) -> MeshInstance3D:
	return U.box_m(self, size, pos, _m(c, emit))


# Caja sólida (el jugador choca) que además los enemigos rodean
func _solido(size: Vector3, pos: Vector3, c: Color, bloque: bool = true, visible_mesh: bool = true) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.position = pos
	add_child(sb)
	if visible_mesh:
		U.box_m(sb, size, Vector3.ZERO, _m(c))
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	sb.add_child(cs)
	if bloque and size.y > 0.5 and pos.y - size.y / 2.0 < 1.0:
		U.bloques.append(Rect2(pos.x - size.x / 2.0, pos.z - size.z / 2.0, size.x, size.z))
	return sb

extends Node3D
# El casino de Iván Muriel: una sala al lado derecho del pasillo (pasada la
# segunda puerta) con moqueta roja, neones, tres tragaperras, una ruleta y
# una tele gigante donde echan el partido del CF Trujillo. Iván lo ve de pie,
# lo celebra (o se desespera) y acepta apuestas. Los juegos se abren con E en
# casino_menu.gd y se apuesta con tus puntos.
# El partido se genera a partir de una semilla: en red el anfitrión manda la
# semilla y el reloj, así que todos ven el mismo partido.

const U = preload("res://scripts/nucleo/util.gd")
const Ch = preload("res://scripts/jugador/character.gd")
const MenuScript = preload("res://scripts/interfaz/casino_menu.gd")
const MODELOS := "res://modelos/mapa/"       # modelos 3D (.glb); si falta alguno se usan las cajas de antes

const MATCH_LEN := 90.0      # un minuto de partido por segundo
const BREAK_LEN := 12.0      # descanso entre partidos
const BET_CLOSE := 70        # minuto a partir del que no se puede apostar
const HOME := "CF Trujillo"
const HOME_SHORT := "TRU"
const RIVALS := [["Mérida AD", "MER", Color(0.9, 0.9, 0.95)], ["CD Badajoz", "BAD", Color(0.95, 0.95, 0.95)],
	["CP Cacereño", "CAC", Color(0.15, 0.4, 0.9)], ["CD Don Benito", "DBE", Color(0.1, 0.55, 0.2)],
	["CF Villanovense", "VVA", Color(0.85, 0.15, 0.15)], ["CD Coria", "COR", Color(0.95, 0.6, 0.1)],
	["Moralo CP", "MOR", Color(0.1, 0.1, 0.12)], ["CD Diocesano", "DIO", Color(0.5, 0.1, 0.5)]]
# La pregunta de Iván al acercarte. A él le gusta Lucía: si aciertas ganas puntos, si no los pierdes.
const QUIZ_NAMES := ["Fabiana Sevillano", "Lucía Bellido"]
const QUIZ_RIGHT := 1
const QUIZ_PRIZE := 500
const QUIZ_COOLDOWN := 90.0   # segundos hasta que vuelve a preguntar

var game
var menu
var menu_open := false
var t := 0.0
var cx := 0.0                # centro de la sala
var cz := 0.0

# partido
var match_seed := 0
var clock := 0.0             # segundos desde que empezó el partido
var away := ""
var away_short := ""
var away_col := Color.WHITE
var goals: Array = []        # [[minuto, lado 0 = Trujillo / 1 = rival], ...]
var odds := [2.0, 3.0, 3.0]  # 1 · X · 2
var shown_goals := 0
var finished := false
var bet := {}                # apuesta del jugador de este PC: {"pick", "amount", "odds"}
var sync_t := 0.0

# Iván y la sala
var ivan: Node3D
var ivan_model: Node3D
var arm_l: Node3D
var arm_r: Node3D
var ivan_head: Node3D
var react := ""              # "gol", "llora" o ""
var react_t := 0.0
var bubble: Node3D           # bocadillo de cómic encima de Iván
var bubble_bg: MeshInstance3D
var bubble_lbl: Label3D
var say_t := 0.0
var near_prev := false
var quiz_cd := 0.0           # > 0: ya ha preguntado hace poco
var bubble_tw: Tween
var tv_vp: SubViewport
var tv: Control
var wheel3d: Node3D
var wheel_spin := 0.0
var slot_screens: Array = []     # Label3D (versión de cajas) o [rodillo1, rodillo2, rodillo3]
var _escenas := {}
var snd_crowd: AudioStreamPlayer3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS     # el partido sigue aunque tengas un menú abierto
	game = get_tree().get_first_node_in_group("game")
	cx = (U.CASINO_WX + 0.2 + U.CASINO_X1) / 2.0
	cz = (U.CASINO_Z0 + U.CASINO_Z1) / 2.0
	_build_room()
	_build_tv()
	_build_slots()
	_build_roulette()
	_build_ivan()
	snd_crowd = AudioStreamPlayer3D.new()
	snd_crowd.stream = U.make_crowd()
	snd_crowd.unit_size = 6.0
	snd_crowd.max_distance = 30.0
	snd_crowd.position = Vector3(U.CASINO_X1 - 0.5, 2.0, cz)
	add_child(snd_crowd)
	_new_match(randi())


# ---------------- sala ----------------
func _build_room() -> void:
	var h := 4.0
	var x0 := U.CASINO_WX + 0.2
	var x1 := U.CASINO_X1 + 0.2
	var z0 := U.CASINO_Z0 - 0.2
	var z1 := U.CASINO_Z1 + 0.2
	var wall := Color(0.28, 0.05, 0.08)
	var gold := Color(0.85, 0.65, 0.25)
	# moqueta roja con dibujo, paredes burdeos, techo oscuro
	var carpet := StandardMaterial3D.new()
	carpet.albedo_texture = U._noise_tex("carpet", FastNoiseLite.TYPE_CELLULAR, 6.0, Color(0.35, 0.03, 0.06), Color(0.55, 0.1, 0.1))
	carpet.uv1_triplanar = true
	carpet.uv1_scale = Vector3.ONE * 0.6
	var fl := U.solid_box(self, Vector3(x1 - x0 + 0.4, 0.2, z1 - z0), Vector3((x0 + x1) / 2.0, -0.1, cz), Color.WHITE)
	(fl.get_child(0) as MeshInstance3D).material_override = carpet
	U.solid_box(self, Vector3(0.4, h, z1 - z0 + 0.4), Vector3(x1 + 0.2, h / 2.0, cz), wall)
	U.solid_box(self, Vector3(x1 - x0 + 0.4, h, 0.4), Vector3((x0 + x1) / 2.0, h / 2.0, z0 - 0.2), wall)
	U.solid_box(self, Vector3(x1 - x0 + 0.4, h, 0.4), Vector3((x0 + x1) / 2.0, h / 2.0, z1 + 0.2), wall)
	var ceil_m := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(x1 - x0, z1 - z0)
	ceil_m.mesh = pm
	ceil_m.material_override = U.mat(Color(0.08, 0.03, 0.05))
	ceil_m.position = Vector3((x0 + x1) / 2.0, h, cz)
	ceil_m.rotation_degrees.x = 180.0
	ceil_m.add_to_group("techos")
	add_child(ceil_m)
	# moqueta de casino, papel pintado de damasco, zócalo de madera y techo artesonado dorado
	var sala := _modelo("casino_sala", Vector3((x0 + x1) / 2.0, 0.0, cz))
	# molduras doradas y neones morados arriba
	for zz in [z0 + 0.01, z1 - 0.01]:
		if sala == null:
			U.box(self, Vector3(x1 - x0, 0.06, 0.03), Vector3((x0 + x1) / 2.0, 1.0, zz), gold)
		U.box(self, Vector3(x1 - x0, 0.05, 0.03), Vector3((x0 + x1) / 2.0, h - 0.4, zz + (0.06 if zz < cz else -0.06)), Color(0.7, 0.2, 1.0), true)
	U.box(self, Vector3(0.03, 0.05, z1 - z0), Vector3(x1 - 0.01, h - 0.25, cz), Color(0.7, 0.2, 1.0), true)
	# lámparas de araña doradas
	for lz in [cz - 3.0, cz + 3.0]:
		var lp := Vector3(cx - 1.0, h - 0.6, lz)
		if _modelo("arana", Vector3(lp.x, h, lz)) == null:
			U.sphere(self, 0.28, lp, Color(1.0, 0.85, 0.5), true)
			for i in 6:
				var a := i * TAU / 6.0
				U.sphere(self, 0.07, lp + Vector3(cos(a) * 0.4, -0.15, sin(a) * 0.4), Color(1.0, 0.9, 0.6), true)
			U.cylinder(self, 0.02, 0.4, lp + Vector3(0, 0.4, 0), gold)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.8, 0.55)
		l.light_energy = 1.6
		l.omni_range = 9.0
		l.position = lp - Vector3(0, 0.4, 0)
		add_child(l)
	var neon := OmniLight3D.new()
	neon.light_color = Color(0.7, 0.25, 1.0)
	neon.light_energy = 1.2
	neon.omni_range = 10.0
	neon.position = Vector3(x0 + 1.5, h - 0.5, cz)
	add_child(neon)
	# sofá chester frente a la tele
	if _modelo("sofa_casino", Vector3(U.CASINO_X1 - 4.7, 0.0, cz), 90.0) != null:
		_choque(Vector3(0.9, 0.85, 3.1), Vector3(U.CASINO_X1 - 4.7, 0.425, cz), 0.0)
	else:
		var sofa_c := Color(0.12, 0.1, 0.12)
		U.solid_box(self, Vector3(1.0, 0.45, 3.0), Vector3(U.CASINO_X1 - 4.6, 0.225, cz), sofa_c)
		U.box(self, Vector3(0.3, 0.6, 3.0), Vector3(U.CASINO_X1 - 5.0, 0.7, cz), sofa_c)
		for sz in [-1.0, 1.0]:
			U.box(self, Vector3(1.0, 0.3, 0.25), Vector3(U.CASINO_X1 - 4.6, 0.6, cz + sz * 1.5), sofa_c)
	# mesa de póker con sus sillas (decoración) y botellero del bar junto a la puerta
	var poker := Vector3(x0 + 3.2, 0.0, cz + 1.8)
	if _modelo("mesa_poker", poker) != null:
		_choque(Vector3(2.2, 0.8, 1.15), poker + Vector3(0, 0.4, 0), 0.0)
		var pl := OmniLight3D.new()
		pl.light_color = Color(1.0, 0.85, 0.6)
		pl.light_energy = 1.4
		pl.omni_range = 4.5
		pl.position = poker + Vector3(0, 2.4, 0)
		add_child(pl)
	var bar := Vector3(x0 + 0.2, 0.0, cz + 3.6)
	if _modelo("botellero", bar, 90.0) != null:
		_choque(Vector3(3.6, 2.4, 0.4), bar + Vector3(0, 1.2, 0), 90.0)
		var bl := OmniLight3D.new()
		bl.light_color = Color(1.0, 0.65, 0.3)
		bl.light_energy = 1.0
		bl.omni_range = 4.0
		bl.position = bar + Vector3(0.9, 1.5, 0)
		add_child(bl)
	# carteles: "CASINO" sobre la puerta (en el pasillo) y dentro
	var s1 := _neon_label("CASINO", 90, Color(1.0, 0.8, 0.2))
	s1.position = Vector3(U.CASINO_WX - 0.02, 3.15, U.CASINO_Z)
	s1.rotation_degrees.y = -90.0
	var s2 := _neon_label("CASINO MURIEL", 70, Color(1.0, 0.3, 0.75))
	s2.position = Vector3(cx, 3.1, z0 + 0.03)
	var bulbs := Node3D.new()
	add_child(bulbs)
	for i in 9:                                    # bombillas alrededor del marco de la puerta
		var by := 0.3 + i * 0.27
		for sz in [-1.0, 1.0]:
			U.sphere(bulbs, 0.04, Vector3(U.CASINO_WX - 0.03, by, U.CASINO_Z + sz * 1.22), Color(1.0, 0.85, 0.4), true)


func _neon_label(text: String, size: int, c: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.006
	l.outline_size = 14
	l.modulate = c
	l.outline_modulate = c.darkened(0.7)
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Impact", "Arial Black", "Arial"])
	l.font = f
	add_child(l)
	return l


# Tele gigante en la pared del fondo con el partido (se dibuja en un SubViewport)
func _build_tv() -> void:
	tv_vp = SubViewport.new()
	tv_vp.size = Vector2i(640, 360)
	tv_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	tv_vp.disable_3d = true
	add_child(tv_vp)
	tv = TvScreen.new()
	tv.casino = self
	tv.size = Vector2(640, 360)
	tv_vp.add_child(tv)
	var x := U.CASINO_X1 + 0.0
	U.box(self, Vector3(0.12, 2.5, 4.4), Vector3(x - 0.02, 2.2, cz), Color(0.03, 0.03, 0.04))
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(4.2, 2.36)
	q.mesh = qm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = tv_vp.get_texture()
	q.material_override = m
	q.position = Vector3(x - 0.09, 2.2, cz)
	q.rotation_degrees.y = -90.0
	add_child(q)
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.5, 0.9, 0.6)
	glow.light_energy = 0.8
	glow.omni_range = 6.0
	glow.position = Vector3(x - 1.2, 2.2, cz)
	add_child(glow)


# Tres tragaperras contra la pared de la entrada
func _build_slots() -> void:
	for i in 3:
		var p := Vector3(U.CASINO_WX + 2.4 + i * 1.3, 0.0, U.CASINO_Z0 + 0.45)
		if _modelo("tragaperras", p) != null:
			_choque(Vector3(0.9, 2.1, 0.75), p + Vector3(0, 1.05, 0), 0.0)
			_modelo("taburete", p + Vector3(randf_range(-0.08, 0.08), 0.0, 0.85), randf_range(0.0, 360.0))
			# tres rodillos: un símbolo grande en cada tercio de la pantalla
			var reels: Array = []
			for k in 3:
				var r := Label3D.new()
				r.text = "7"
				r.font_size = 96
				r.pixel_size = 0.0028
				r.outline_size = 10
				r.outline_modulate = Color(0.1, 0.05, 0.0)
				r.modulate = Color(0.85, 0.05, 0.05)
				r.position = p + Vector3(-0.227 + k * 0.227, 1.30, 0.372)
				add_child(r)
				reels.append(r)
			slot_screens.append(reels)
			var ls := OmniLight3D.new()                   # resplandor morado de la máquina
			ls.light_color = Color(0.85, 0.63, 1.0)
			ls.light_energy = 0.7
			ls.omni_range = 4.0
			ls.position = p + Vector3(0, 1.6, 1.15)
			add_child(ls)
			game.interactables.append({"type": "casino", "game": "slots", "pos": p + Vector3(0, 0, 1.1), "done": false})
			continue
		var m := Node3D.new()
		m.position = p
		add_child(m)
		var body := U.solid_box(m, Vector3(1.0, 1.75, 0.7), Vector3(0, 0.875, 0), Color(0.6, 0.08, 0.1))
		U.shiny(body, 0.3, 0.3)
		U.box(m, Vector3(1.04, 0.08, 0.74), Vector3(0, 1.0, 0), Color(0.85, 0.65, 0.25))
		var scr := U.box(m, Vector3(0.75, 0.42, 0.02), Vector3(0, 1.3, 0.36), Color(0.95, 0.95, 0.9), true)
		scr.material_override.emission_energy_multiplier = 0.6
		var sym := Label3D.new()
		sym.text = "7 7 7"
		sym.font_size = 64
		sym.pixel_size = 0.004
		sym.outline_size = 0
		sym.modulate = Color(0.85, 0.05, 0.05)
		sym.position = Vector3(0, 1.3, 0.375)
		m.add_child(sym)
		slot_screens.append(sym)
		var top := _neon_label("SLOTS", 40, Color(0.3, 0.9, 1.0))
		top.reparent(m)
		top.position = Vector3(0, 1.88, 0.2)
		var lever := U.cylinder(m, 0.025, 0.5, Vector3(0.56, 1.25, 0.1), Color(0.75, 0.75, 0.78))
		lever.rotation_degrees.x = -10.0
		U.sphere(m, 0.07, Vector3(0.56, 1.52, 0.06), Color(0.9, 0.1, 0.1))
		game.interactables.append({"type": "casino", "game": "slots", "pos": p + Vector3(0, 0, 1.1), "done": false})


# Mesa de ruleta con tapete verde y la rueda (gira de verdad cuando juegas)
func _build_roulette() -> void:
	var p := Vector3(cx - 0.8, 0.0, U.CASINO_Z1 - 1.6)
	if _modelo("mesa_ruleta", p) != null and _escena("ruleta_rueda") != null:
		_choque(Vector3(3.2, 0.88, 1.5), p + Vector3(0, 0.44, 0), 0.0)
		wheel3d = Node3D.new()
		wheel3d.position = p + Vector3(-1.0, 0.835, 0)
		add_child(wheel3d)
		_modelo("ruleta_rueda", Vector3.ZERO, 0.0, wheel3d)
		game.interactables.append({"type": "casino", "game": "ruleta", "pos": p + Vector3(0, 0, -1.3), "done": false})
		return
	var base := U.solid_box(self, Vector3(3.2, 0.85, 1.5), p + Vector3(0, 0.425, 0), Color(0.3, 0.16, 0.08))
	U.shiny(base, 0.4)
	U.box(self, Vector3(3.0, 0.02, 1.3), p + Vector3(0, 0.86, 0), Color(0.05, 0.4, 0.15))
	# casillas pintadas en el tapete
	for i in 12:
		for j in 3:
			var n := i * 3 + j + 1
			var c := Color(0.75, 0.08, 0.08) if n in [1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36] else Color(0.05, 0.05, 0.05)
			U.box(self, Vector3(0.14, 0.005, 0.24), p + Vector3(-0.5 + i * 0.16, 0.872, -0.3 + j * 0.27), c)
	wheel3d = Node3D.new()
	wheel3d.position = p + Vector3(-1.15, 0.9, 0)
	add_child(wheel3d)
	U.cylinder(wheel3d, 0.5, 0.08, Vector3.ZERO, Color(0.35, 0.18, 0.06))
	var disc := MeshInstance3D.new()
	var dq := QuadMesh.new()
	dq.size = Vector2(0.86, 0.86)
	disc.mesh = dq
	var dm := StandardMaterial3D.new()
	dm.albedo_texture = _wheel_texture()
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	disc.material_override = dm
	disc.rotation_degrees.x = -90.0
	disc.position.y = 0.045
	wheel3d.add_child(disc)
	U.cylinder(wheel3d, 0.06, 0.12, Vector3(0, 0.08, 0), Color(0.85, 0.65, 0.25))
	game.interactables.append({"type": "casino", "game": "ruleta", "pos": p + Vector3(0, 0, -1.3), "done": false})


# Textura de la rueda: 37 casillas rojo/negro/verde en orden europeo
func _wheel_texture() -> ImageTexture:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var order: Array = MenuScript.WHEEL
	for y in n:
		for x in n:
			var d := Vector2(x - n / 2.0, y - n / 2.0)
			var r := d.length() / (n / 2.0)
			if r > 1.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var a := fposmod(d.angle(), TAU)
			var num: int = order[int(a / TAU * 37.0) % 37]
			var c := MenuScript.pocket_color(num)
			if r < 0.55:
				c = Color(0.4, 0.22, 0.08)
			elif r > 0.93:
				c = Color(0.85, 0.65, 0.25)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


func spin_wheel(dur: float) -> void:
	wheel_spin = dur


# Iván Muriel, de pie viendo la tele (mirando hacia el fondo de la sala)
func _build_ivan() -> void:
	ivan = Node3D.new()
	ivan.position = Vector3(U.CASINO_X1 - 3.4, 0.0, cz - 2.2)
	ivan.rotation_degrees.y = -122.0         # mirando a la tele
	add_child(ivan)
	var parts: Dictionary = Ch.build_ivan(ivan)
	ivan_model = parts["model"]
	ivan_head = parts["head"]
	arm_l = parts["arm_l"]
	arm_r = parts["arm_r"]
	_build_bubble()
	var tag := Label3D.new()
	tag.text = "Iván Muriel"
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.font_size = 30
	tag.pixel_size = 0.005
	tag.outline_size = 8
	tag.modulate = Color(0.5, 0.85, 1.0)
	tag.position = Vector3(0, 2.0, 0)
	ivan.add_child(tag)
	game.interactables.append({"type": "casino", "game": "futbol", "pos": ivan.position + Vector3(-0.9, 0, -0.6), "done": false})


# Bocadillo de cómic: globo blanco con borde negro y piquito hacia Iván.
# El globo y el texto miran siempre a la cámara.
func _build_bubble() -> void:
	bubble = Node3D.new()
	bubble.position = Vector3(0, 2.55, 0)
	bubble.scale = Vector3.ZERO
	ivan.add_child(bubble)
	bubble_bg = MeshInstance3D.new()
	bubble_bg.mesh = QuadMesh.new()
	var m := StandardMaterial3D.new()
	m.albedo_texture = _bubble_texture()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	bubble_bg.material_override = m
	bubble_bg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bubble.add_child(bubble_bg)
	bubble_lbl = Label3D.new()
	bubble_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble_lbl.font_size = 44
	bubble_lbl.pixel_size = 0.0042
	bubble_lbl.outline_size = 0
	bubble_lbl.modulate = Color(0.05, 0.05, 0.07)
	bubble_lbl.render_priority = 1
	bubble_lbl.position.y = 0.05
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Comic Sans MS", "Segoe Print", "Segoe UI"])
	f.font_weight = 700
	bubble_lbl.font = f
	bubble.add_child(bubble_lbl)


# Globo redondeado con piquito abajo a la izquierda (generado por código)
func _bubble_texture() -> ImageTexture:
	var w := 512
	var h := 200
	var body_h := 150.0
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rad := 60.0
	var border := 9.0
	for y in h:
		for x in w:
			# distancia al rectángulo redondeado del globo
			var qx := maxf(absf(x - w / 2.0) - (w / 2.0 - rad - 4.0), 0.0)
			var qy := maxf(absf(y - body_h / 2.0) - (body_h / 2.0 - rad - 4.0), 0.0)
			var d := Vector2(qx, qy).length() - rad
			# piquito: triángulo que baja desde el globo
			var tail := false
			if y >= body_h - 20.0:
				var k := (y - (body_h - 20.0)) / (h - 4.0 - (body_h - 20.0))
				var cx0 := lerpf(150.0, 120.0, k)
				var half := lerpf(34.0, 0.0, k)
				tail = k <= 1.0 and absf(x - cx0) <= half
				if tail:
					d = minf(d, -(half - absf(x - cx0)) * 0.6)
			if d < -border:
				img.set_pixel(x, y, Color(1, 1, 1, 0.96))
			elif d < 0.0 or tail:
				img.set_pixel(x, y, Color(0.05, 0.05, 0.07))
	return ImageTexture.create_from_image(img)


func _talk(text: String, dur := 3.0) -> void:
	say_t = dur
	if bubble_lbl.text == text and bubble.scale.x > 0.9:
		return
	bubble_lbl.text = text
	# el globo se adapta al largo de la frase
	var w := clampf(text.length() * 0.1 + 0.5, 1.1, 4.4)
	(bubble_bg.mesh as QuadMesh).size = Vector2(w, 0.72)
	bubble_lbl.width = (w - 0.3) / bubble_lbl.pixel_size
	bubble_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if bubble_tw:
		bubble_tw.kill()
	bubble.scale = Vector3.ONE * 0.2
	bubble_tw = create_tween()
	bubble_tw.tween_property(bubble, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _hide_bubble() -> void:
	if bubble_lbl.text == "":
		return
	bubble_lbl.text = ""
	if bubble_tw:
		bubble_tw.kill()
	bubble_tw = create_tween()
	bubble_tw.tween_property(bubble, "scale", Vector3.ZERO, 0.15)


# ---------------- partido ----------------
func _new_match(seed: int) -> void:
	match_seed = seed
	clock = 0.0
	finished = false
	shown_goals = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var rv: Array = RIVALS[rng.randi() % RIVALS.size()]
	away = rv[0]
	away_short = rv[1]
	away_col = rv[2]
	var lh := rng.randf_range(0.9, 2.1)        # goles esperados de cada equipo
	var la := rng.randf_range(0.7, 1.9)
	goals.clear()
	for side in 2:
		var n := _poisson(rng, lh if side == 0 else la)
		for i in n:
			goals.append([rng.randi_range(2, 89), side])
	goals.sort_custom(func(a, b): return a[0] < b[0])
	# cuotas a partir de las probabilidades reales (con un 8 % para la casa)
	var p := [0.0, 0.0, 0.0]
	for i in 9:
		for j in 9:
			var pr := _pois_p(lh, i) * _pois_p(la, j)
			p[0 if i > j else (1 if i == j else 2)] += pr
	for k in 3:
		odds[k] = maxf(1.05, snappedf(0.92 / maxf(p[k], 0.01), 0.05))


func _poisson(rng: RandomNumberGenerator, lam: float) -> int:
	var l := exp(-lam)
	var k := 0
	var pp := 1.0
	while true:
		pp *= rng.randf()
		if pp <= l:
			return k
		k += 1
	return k


func _pois_p(lam: float, k: int) -> float:
	var f := 1.0
	for i in range(2, k + 1):
		f *= i
	return pow(lam, k) * exp(-lam) / f


func minute() -> int:
	return mini(int(clock), 90)


func score(upto := -1) -> Vector2i:
	var m := minute() if upto < 0 else upto
	var s := Vector2i.ZERO
	for g in goals:
		if g[0] <= m:
			if g[1] == 0:
				s.x += 1
			else:
				s.y += 1
	return s


func team_name(i: int) -> String:
	return [HOME, "Empate", away][i]


# El jugador de este PC apuesta a 0 = Trujillo, 1 = empate, 2 = rival
func place_bet(pick: int, amount: int) -> String:
	if not bet.is_empty():
		return "Ya tienes una apuesta en este partido"
	if finished or minute() >= BET_CLOSE:
		return "Apuestas cerradas: espera al siguiente partido"
	if game.points < amount:
		return "No tienes puntos suficientes"
	game.points -= amount
	bet = {"pick": pick, "amount": amount, "odds": odds[pick], "seed": match_seed}
	_talk("¡Hecho! %d a %s" % [amount, team_name(pick)])
	return ""


func _resolve() -> void:
	if bet.is_empty() or bet["seed"] != match_seed:
		bet = {}
		return
	var s := score(90)
	var res := 0 if s.x > s.y else (1 if s.x == s.y else 2)
	if bet["pick"] == res:
		var win := int(round(float(bet["amount"]) * float(bet["odds"])))
		game.points += win
		game._toast("¡APUESTA GANADA!\n+%d puntos" % win)
		_talk("¡Te lo dije! Invita tú")
	else:
		game._toast("Apuesta perdida...\n%s %d - %d %s" % [HOME_SHORT, s.x, s.y, away_short])
		_talk("Bueno... la próxima será")
	bet = {}


func _process(delta: float) -> void:
	t += delta
	clock += delta
	# goles
	var m := minute()
	while shown_goals < goals.size() and goals[shown_goals][0] <= m:
		_goal(goals[shown_goals][1])
		shown_goals += 1
	if not finished and clock >= MATCH_LEN:
		finished = true
		_resolve()
	if clock >= MATCH_LEN + BREAK_LEN and (not Net.online or Net.is_host()):
		_start_next(randi())
	# el anfitrión manda la semilla y el reloj de vez en cuando
	if Net.online and Net.running and Net.is_host():
		sync_t -= delta
		if sync_t <= 0.0:
			sync_t = 3.0
			_net_clock.rpc(match_seed, clock)
	_animate_ivan(delta)
	# ruleta 3D girando (despacio siempre, rápido cuando alguien juega)
	wheel_spin = maxf(0.0, wheel_spin - delta)
	wheel3d.rotation.y += delta * (0.4 + wheel_spin * 3.0)
	# pantallas de las tragaperras cambiando de vez en cuando
	if fmod(t, 2.5) < delta:
		var sy: Array = MenuScript.SYMBOLS
		for sc in slot_screens:
			if sc is Array:
				for r: Label3D in sc:
					var s: Array = sy.pick_random()
					r.text = s[0]
					r.modulate = s[1]
			else:
				sc.text = "%s %s %s" % [sy.pick_random()[0], sy.pick_random()[0], sy.pick_random()[0]]


func _start_next(seed: int) -> void:
	if Net.online:
		_net_clock.rpc(seed, 0.0)
	else:
		_new_match(seed)


@rpc("authority", "call_local", "unreliable_ordered")
func _net_clock(seed: int, c: float) -> void:
	if seed != match_seed:
		if not finished and not bet.is_empty():
			_resolve()
		_new_match(seed)
		# saltar los goles que ya han pasado sin celebrarlos
		clock = c
		while shown_goals < goals.size() and goals[shown_goals][0] <= minute():
			shown_goals += 1
		finished = clock >= MATCH_LEN
	elif absf(clock - c) > 1.5:
		clock = c


func _goal(side: int) -> void:
	tv.goal_t = 2.5
	tv.goal_side = side
	snd_crowd.play()
	react = "gol" if side == 0 else "llora"
	react_t = 2.5
	_talk("¡GOOOOL! ¡Vamos Trujillo!" if side == 0 else "Nooo... ¿qué hace la defensa?", 2.5)


func _animate_ivan(delta: float) -> void:
	react_t = maxf(0.0, react_t - delta)
	if react_t <= 0.0:
		react = ""
	var al := 0.0
	var ar := 0.0
	var az := 0.0
	var hop := 0.0
	match react:
		"gol":          # brazos arriba y saltitos
			al = -2.7
			ar = -2.7
			hop = absf(sin(t * 10.0)) * 0.18
		"llora":        # manos a la cabeza
			al = -2.3
			ar = -2.3
			az = 0.6
	arm_l.rotation.x = lerpf(arm_l.rotation.x, al, 10.0 * delta)
	arm_r.rotation.x = lerpf(arm_r.rotation.x, ar, 10.0 * delta)
	arm_l.rotation.z = lerpf(arm_l.rotation.z, -az, 10.0 * delta)
	arm_r.rotation.z = lerpf(arm_r.rotation.z, az, 10.0 * delta)
	ivan_model.position.y = hop
	ivan_head.rotation.x = sin(t * 1.3) * 0.04 + (0.25 if react == "llora" else 0.0)
	# al acercarte te hace la pregunta (si no te la ha hecho hace poco)
	say_t -= delta
	quiz_cd = maxf(0.0, quiz_cd - delta)
	var p = game.player
	var near: bool = p != null and ivan.global_position.distance_to(p.global_position) < 6.0
	if near and quiz_cd <= 0.0 and say_t <= 0.0:
		_talk("¿%s o %s?" % QUIZ_NAMES, 1.0)
	elif say_t <= 0.0:
		_hide_bubble()
	near_prev = near


# Respuesta a la pregunta: true si has acertado (Lucía)
func answer(i: int) -> bool:
	quiz_cd = QUIZ_COOLDOWN
	if i == QUIZ_RIGHT:
		game.points += QUIZ_PRIZE
		_talk("¡Eso es! %s, sin duda" % QUIZ_NAMES[QUIZ_RIGHT], 4.0)
		return true
	game.points = maxi(0, game.points - QUIZ_PRIZE)
	_talk("¿¡%s!? Anda, paga..." % QUIZ_NAMES[i], 4.0)
	return false


# ---------------- menús ----------------
func prompt(it: Dictionary) -> String:
	match it["game"]:
		"slots":
			return "[E] Jugar a la tragaperras"
		"ruleta":
			return "[E] Jugar a la ruleta"
	if quiz_cd <= 0.0:
		return "[E] Responder a Iván: ¿%s o %s?" % QUIZ_NAMES
	return "[E] Apostar en el partido con Iván"


func open_menu(it: Dictionary) -> void:
	if menu_open:
		return
	menu = MenuScript.new()
	menu.casino = self
	menu.mode = "quiz" if it["game"] == "futbol" and quiz_cd <= 0.0 else it["game"]
	add_child(menu)
	menu_open = true


func menu_closed() -> void:
	menu_open = false
	menu = null


# ---------------- modelos 3D ----------------
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


# Choque invisible para el jugador (el modelo se ve, esto es lo que choca)
func _choque(size: Vector3, pos: Vector3, yaw: float) -> void:
	var sb := StaticBody3D.new()
	sb.position = pos
	sb.rotation_degrees.y = yaw
	add_child(sb)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	sb.add_child(cs)


# ---------------- la tele ----------------
# Dibuja el partido: césped, líneas, jugadores que siguen al balón, marcador y goles
class TvScreen extends Control:
	var casino
	var goal_t := 0.0
	var goal_side := 0
	var ball := Vector2(320, 200)
	var ball_v := Vector2.ZERO
	var target := Vector2(320, 200)
	var retarget := 0.0

	func _process(delta: float) -> void:
		goal_t = maxf(0.0, goal_t - delta)
		# el balón va hacia la portería del que va a marcar justo antes del gol
		var next_goal = null
		for g in casino.goals:
			if g[0] > casino.clock and g[0] - casino.clock < 1.6:
				next_goal = g
				break
		retarget -= delta
		if next_goal != null:
			target = Vector2(612 if next_goal[1] == 0 else 28, 200)
		elif retarget <= 0.0 or goal_t > 2.2:
			retarget = randf_range(0.6, 1.4)
			target = Vector2(randf_range(80, 560), randf_range(70, 330))
			if goal_t > 2.2:
				ball = Vector2(320, 200)
		ball_v = ball_v.lerp((target - ball).limit_length(240.0), 4.0 * delta)
		ball += ball_v * delta
		queue_redraw()

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		draw_rect(Rect2(0, 0, 640, 360), Color(0.05, 0.08, 0.1))
		# césped a franjas y líneas
		for i in 12:
			draw_rect(Rect2(20 + i * 50, 40, 50, 320), Color(0.16, 0.5, 0.2) if i % 2 == 0 else Color(0.19, 0.56, 0.23))
		var w := Color(1, 1, 1, 0.85)
		draw_rect(Rect2(20, 40, 600, 320), w, false, 2.0)
		draw_line(Vector2(320, 40), Vector2(320, 360), w, 2.0)
		draw_arc(Vector2(320, 200), 45, 0, TAU, 40, w, 2.0)
		for gx in [20, 620]:
			var d := 1 if gx == 20 else -1
			draw_rect(Rect2(mini(gx, gx + d * 80), 120, 80, 160), w, false, 2.0)
			draw_rect(Rect2(gx - (8 if d > 0 else 0), 170, 8, 60), Color(1, 1, 1))
		# jugadores: 6 por equipo, cada uno en su zona pero atraídos por el balón
		var ft: float = casino.t
		for side in 2:
			var col: Color = Color(0.36, 0.72, 0.92) if side == 0 else casino.away_col
			for i in 6:
				var base := Vector2(110 + (i % 3) * 90, 100 + (i / 3) * 200 + (i % 3) * 20)
				if side == 1:
					base.x = 640 - base.x
				var pos := base.lerp(ball, 0.35 + 0.1 * sin(ft + i)) + Vector2(sin(ft * 1.7 + i * 2.0 + side), cos(ft * 1.3 + i)) * 12.0
				draw_circle(pos, 8.0, Color(0, 0, 0, 0.5))
				draw_circle(pos, 6.5, col)
		draw_circle(ball, 4.5, Color(1, 1, 1))
		draw_circle(ball, 4.5, Color(0, 0, 0), false, 1.0)
		# marcador y "EN DIRECTO"
		var s: Vector2i = casino.score()
		draw_rect(Rect2(14, 6, 250, 28), Color(0.02, 0.02, 0.05, 0.9))
		draw_rect(Rect2(14, 6, 6, 28), Color(0.36, 0.72, 0.92))
		draw_string(font, Vector2(28, 27), "%s  %d - %d  %s" % [casino.HOME_SHORT, s.x, s.y, casino.away_short], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1))
		var mtxt := ("%d'" % casino.minute()) if not casino.finished else "FINAL"
		draw_string(font, Vector2(196, 27), mtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1.0, 0.85, 0.3))
		if fmod(ft, 1.0) < 0.6:
			draw_circle(Vector2(512, 20), 6, Color(1, 0.15, 0.15))
		draw_string(font, Vector2(524, 27), "EN DIRECTO", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1))
		# ¡GOL!
		if goal_t > 0.0 and fmod(goal_t, 0.5) < 0.35:
			draw_rect(Rect2(0, 150, 640, 90), Color(0, 0, 0, 0.6))
			var who: String = casino.HOME if goal_side == 0 else casino.away
			draw_string(font, Vector2(0, 205), "¡GOOOOL!", HORIZONTAL_ALIGNMENT_CENTER, 640, 56, Color(1.0, 0.85, 0.2))
			draw_string(font, Vector2(0, 232), who, HORIZONTAL_ALIGNMENT_CENTER, 640, 20, Color(1, 1, 1))
		# descanso entre partidos
		if casino.finished:
			draw_rect(Rect2(0, 0, 640, 360), Color(0, 0, 0, 0.65))
			draw_string(font, Vector2(0, 170), "FINAL DEL PARTIDO", HORIZONTAL_ALIGNMENT_CENTER, 640, 34, Color(1, 1, 1))
			draw_string(font, Vector2(0, 215), "%s %d - %d %s" % [casino.HOME, s.x, s.y, casino.away], HORIZONTAL_ALIGNMENT_CENTER, 640, 26, Color(1.0, 0.85, 0.3))
			var left := int(ceil(casino.MATCH_LEN + casino.BREAK_LEN - casino.clock))
			draw_string(font, Vector2(0, 260), "Próximo partido en %d s" % maxi(left, 0), HORIZONTAL_ALIGNMENT_CENTER, 640, 18, Color(0.8, 0.8, 0.8))


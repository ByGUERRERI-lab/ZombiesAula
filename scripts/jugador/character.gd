extends RefCounted
# Construcción de personajes (caras, protagonista personalizable y zombie)
# y guardado de la personalización del jugador.

const U = preload("res://scripts/nucleo/util.gd")
const ZombiScene = preload("res://modelos/zombi_kimono.glb")

const SKINS :=[["Clara", Color(0.96, 0.8, 0.68)], ["Media", Color(0.88, 0.68, 0.52)],
	["Morena", Color(0.7, 0.5, 0.35)], ["Oscura", Color(0.45, 0.3, 0.2)]]
const SHIRTS := [["Gris", Color(0.35, 0.37, 0.42)], ["Blanca", Color(0.93, 0.93, 0.93)],
	["Negra", Color(0.08, 0.08, 0.1)], ["Roja", Color(0.8, 0.12, 0.12)], ["Azul", Color(0.15, 0.35, 0.8)],
	["Verde", Color(0.15, 0.6, 0.25)], ["Amarilla", Color(0.95, 0.8, 0.15)], ["Morada", Color(0.5, 0.2, 0.7)],
	["Naranja", Color(0.95, 0.5, 0.1)]]
const PANTS := [["Vaquero oscuro", Color(0.15, 0.18, 0.3)], ["Vaquero claro", Color(0.4, 0.52, 0.72)],
	["Negro", Color(0.08, 0.08, 0.09)], ["Caqui", Color(0.72, 0.65, 0.5)], ["Gris", Color(0.45, 0.45, 0.48)],
	["Rojo", Color(0.6, 0.1, 0.1)]]
const SHOES := [["Blancas", Color(0.95, 0.95, 0.95)], ["Negras", Color(0.07, 0.07, 0.08)],
	["Rojas", Color(0.85, 0.1, 0.1)], ["Azules", Color(0.15, 0.3, 0.85)], ["Verdes", Color(0.2, 0.75, 0.3)]]
const HAIRS := [["Castaño", Color(0.3, 0.17, 0.09)], ["Negro", Color(0.06, 0.05, 0.05)],
	["Rubio", Color(0.9, 0.75, 0.35)], ["Pelirrojo", Color(0.75, 0.3, 0.1)], ["Azul", Color(0.2, 0.4, 0.95)],
	["Rosa", Color(0.95, 0.45, 0.7)], ["Blanco", Color(0.92, 0.92, 0.92)]]
const OUTFITS := ["Camiseta", "Sudadera con capucha", "Chaqueta abierta"]
const HATS := ["Nada", "Gorra", "Gorro de lana", "Diadema"]
const GLASSES := ["Sin gafas", "Gafas", "Gafas de sol"]
# Aspectos predeterminados (personajes hechos a partir de fotos)
const PRESETS := ["Personalizado", "Spider-Juan", "Juan Gato"]

# [clave, texto, lista de opciones]
const OPTIONS := [
	["preset", "Aspecto", PRESETS],
	["outfit", "Ropa", OUTFITS], ["shirt", "Color de la ropa", SHIRTS], ["pants", "Pantalón", PANTS],
	["shoes", "Zapatillas", SHOES], ["hair", "Pelo", HAIRS], ["skin", "Piel", SKINS],
	["hat", "Cabeza", HATS], ["glasses", "Gafas", GLASSES],
]

const SAVE_PATH := "user://personaje.cfg"
const VICTOR_SCALE := 1.2      # mide 2 metros: saca una cabeza a los jugadores (los zombies son aún más grandes)

static var skin := {"preset": 0, "outfit": 0, "shirt": 0, "pants": 0, "shoes": 0, "hair": 0, "skin": 0, "hat": 0, "glasses": 0}


static func opt_list(key: String) -> Array:
	for o in OPTIONS:
		if o[0] == key:
			return o[2]
	return []


static func opt_name(key: String, i: int) -> String:
	var it = opt_list(key)[i]
	if it is Array:
		return it[0]
	return it


static func col(list: Array, i: int) -> Color:
	return list[clampi(i, 0, list.size() - 1)][1]


static func load_skin() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for k in skin.keys():
		var n: int = opt_list(k).size()
		skin[k] = clampi(int(cfg.get_value("skin", k, skin[k])), 0, n - 1)


static func save_skin() -> void:
	var cfg := ConfigFile.new()
	for k in skin.keys():
		cfg.set_value("skin", k, skin[k])
	cfg.save(SAVE_PATH)


static func randomize_skin() -> void:
	for k in skin.keys():
		skin[k] = randi() % opt_list(k).size()
	skin["preset"] = 0


# ---------------------------------------------------------------
# Cara expresiva sobre una cabeza esférica de radio r (mirando a -Z).
# kind: "player", "zombie", "ninja", "boss", "scream"
# Devuelve los ojos (para animar parpadeos).
# ---------------------------------------------------------------
static func face(head: Node3D, r: float, skin_c: Color, kind: String, brow_c: Color = Color(0.12, 0.08, 0.05)) -> Array:
	var eyes: Array = []
	var sclera := Color(1, 1, 1)
	var iris := Color(0.35, 0.22, 0.12)
	var pupil := 0.06
	var eye_scale := 1.0
	match kind:
		"zombie":
			sclera = Color(0.95, 0.9, 0.55)
			iris = Color(0.85, 0.1, 0.1)
			pupil = 0.035
		"ninja":
			iris = Color(0.15, 0.15, 0.2)
		"boss":
			sclera = Color(1.0, 0.95, 0.75)
			iris = Color(0.9, 0.35, 0.05)
			pupil = 0.04
		"scream":
			iris = Color(0.25, 0.15, 0.1)
			pupil = 0.03
			eye_scale = 1.35
	for sx in [-1.0, 1.0]:
		var eye := Node3D.new()
		eye.position = Vector3(sx * 0.36 * r, 0.1 * r, -0.84 * r)
		var es := eye_scale
		if kind == "zombie" and sx > 0.0:
			es = 1.2    # un ojo más grande que el otro
		eye.scale = Vector3.ONE * es
		head.add_child(eye)
		var sc := U.sphere(eye, 0.2 * r, Vector3.ZERO, sclera)
		sc.scale = Vector3(1.0, 1.15, 0.55)
		U.sphere(eye, 0.11 * r, Vector3(0, -0.01 * r, -0.1 * r), iris)
		U.sphere(eye, pupil * r, Vector3(0, -0.01 * r, -0.155 * r), Color(0.02, 0.02, 0.02))
		U.sphere(eye, 0.03 * r, Vector3(0.04 * r, 0.05 * r, -0.17 * r), Color(1, 1, 1), true)
		eyes.append(eye)
		# cejas
		var brow_y := 0.38 * r
		var ang := 0.0
		match kind:
			"zombie", "boss", "ninja", "hacker":
				ang = sx * 22.0
			"scream":
				ang = -sx * 18.0
				brow_y = 0.52 * r
		var brow := U.box(head, Vector3(0.3 * r, 0.07 * r, 0.06 * r), Vector3(sx * 0.36 * r, brow_y, -0.9 * r), brow_c)
		brow.rotation_degrees.z = ang
	if kind == "ninja":
		return eyes

	# nariz
	U.sphere(head, 0.1 * r, Vector3(0, -0.08 * r, -0.98 * r), skin_c.darkened(0.08))
	# orejas
	if kind != "player" and kind != "hacker":
		for sx in [-1.0, 1.0]:
			var ear := U.sphere(head, 0.17 * r, Vector3(sx * 0.98 * r, 0.0, 0.0), skin_c)
			ear.scale = Vector3(0.5, 1.0, 0.8)
	# boca
	var lip := Color(0.45, 0.08, 0.08)
	match kind:
		"player":
			U.box(head, Vector3(0.22 * r, 0.055 * r, 0.05 * r), Vector3(0, -0.45 * r, -0.91 * r), lip)
			for sx in [-1.0, 1.0]:
				var c := U.box(head, Vector3(0.11 * r, 0.055 * r, 0.05 * r), Vector3(sx * 0.14 * r, -0.415 * r, -0.905 * r), lip)
				c.rotation_degrees.z = sx * 30.0
		"seria":
			U.ellipsoid(head, Vector3(0.14, 0.035, 0.04) * r, Vector3(0, -0.44 * r, -0.87 * r), Color(0.68, 0.34, 0.33))
			U.ellipsoid(head, Vector3(0.1, 0.045, 0.04) * r, Vector3(0, -0.5 * r, -0.86 * r), Color(0.76, 0.43, 0.4))
		"zombie":
			U.box(head, Vector3(0.42 * r, 0.2 * r, 0.06 * r), Vector3(0, -0.48 * r, -0.88 * r), Color(0.15, 0.0, 0.02))
			for i in 4:
				U.box(head, Vector3(0.08 * r, 0.07 * r, 0.03 * r), Vector3((-0.15 + i * 0.1) * r, -0.4 * r, -0.92 * r), Color(0.95, 0.9, 0.7))
			for i in 2:
				U.box(head, Vector3(0.08 * r, 0.07 * r, 0.03 * r), Vector3((-0.06 + i * 0.12) * r, -0.56 * r, -0.9 * r), Color(0.95, 0.9, 0.7))
			U.box(head, Vector3(0.08 * r, 0.22 * r, 0.03 * r), Vector3(0.12 * r, -0.66 * r, -0.8 * r), Color(0.55, 0.05, 0.05))
		"boss", "hacker":
			U.box(head, Vector3(0.48 * r, 0.13 * r, 0.05 * r), Vector3(0, -0.45 * r, -0.9 * r), Color(0.97, 0.95, 0.85))
			U.box(head, Vector3(0.5 * r, 0.02 * r, 0.055 * r), Vector3(0, -0.45 * r, -0.9 * r), Color(0.2, 0.05, 0.05))
		"scream":
			var m := U.sphere(head, 0.22 * r, Vector3(0, -0.5 * r, -0.84 * r), Color(0.1, 0.0, 0.0))
			m.scale = Vector3(1.0, 1.4, 0.45)
	return eyes


# ---------------------------------------------------------------
# Piezas de cuerpo humano reutilizables
# ---------------------------------------------------------------
# Pierna con muslo, rodilla, gemelo y zapatilla. t = grosor.
static func leg(model: Node3D, hip: Vector3, knee: Vector3, ankle: Vector3, pants_m: Material, t: float = 1.0) -> void:
	U.limb_m(model, hip, knee, 0.105 * t, 0.075 * t, pants_m)
	U.limb_m(model, knee, ankle, 0.075 * t, 0.055 * t, pants_m)
	U.ellipsoid_m(model, Vector3(0.07, 0.11, 0.06) * t, (hip + knee) * 0.5 + Vector3(0, 0, -0.03 * t), pants_m)   # cuádriceps
	U.ellipsoid_m(model, Vector3(0.06, 0.09, 0.055) * t, (knee + ankle) * 0.5 + Vector3(0, 0.05, 0.03 * t), pants_m)  # gemelo


static func shoe(model: Node3D, ankle: Vector3, c: Color, sole: Color, t: float = 1.0) -> void:
	var y := ankle.y - 0.06 * t
	U.ellipsoid(model, Vector3(0.068, 0.06, 0.1) * t, Vector3(ankle.x, maxf(y, 0.06 * t), ankle.z + 0.01), c)        # talón
	U.ellipsoid(model, Vector3(0.065, 0.05, 0.11) * t, Vector3(ankle.x, maxf(y - 0.01, 0.05 * t), ankle.z - 0.09 * t), c)   # puntera
	U.box(model, Vector3(0.13, 0.03, 0.3) * t, Vector3(ankle.x, maxf(y - 0.045 * t, 0.015 * t), ankle.z - 0.045 * t), sole)


# Brazo con hombro, bíceps, codo, antebrazo y mano. sleeve_m cubre el brazo,
# lower_m el antebrazo (piel si es manga corta).
static func arm(model: Node3D, shoulder: Vector3, elbow: Vector3, wrist: Vector3, sleeve_m: Material, lower_m: Material,
		skin_c: Color, t: float = 1.0, side: float = 1.0) -> Node3D:
	U.ellipsoid_m(model, Vector3(0.085, 0.075, 0.085) * t, shoulder + Vector3(0, 0.01, 0), sleeve_m)              # deltoides
	U.limb_m(model, shoulder, elbow, 0.068 * t, 0.055 * t, sleeve_m)
	U.limb_m(model, elbow, wrist, 0.054 * t, 0.04 * t, lower_m)
	return U.hand(model, wrist + (wrist - elbow).normalized() * 0.05 * t, skin_c, t * 1.1, wrist - elbow, -side)


# Articulación: las piezas colgadas del nodo que devuelve siguen usando las
# coordenadas del modelo, pero giran alrededor de "at".
static func pivot(parent: Node3D, at: Vector3) -> Node3D:
	var p := Node3D.new()
	p.position = at
	parent.add_child(p)
	var inner := Node3D.new()
	inner.position = -at
	p.add_child(inner)
	return inner


# Pierna articulada en cadera y rodilla. Devuelve {"thigh", "shin"} para colgarle
# más piezas (el zapato va en "shin").
static func leg_rig(model: Node3D, hip: Vector3, knee: Vector3, ankle: Vector3, pants_m: Material, t: float = 1.0) -> Dictionary:
	var thigh := pivot(model, hip)
	var shin := pivot(thigh, knee)
	U.limb_m(thigh, hip, knee, 0.105 * t, 0.075 * t, pants_m)
	U.ellipsoid_m(thigh, Vector3(0.07, 0.11, 0.06) * t, (hip + knee) * 0.5 + Vector3(0, 0, -0.03 * t), pants_m)
	U.limb_m(shin, knee, ankle, 0.075 * t, 0.055 * t, pants_m)
	U.ellipsoid_m(shin, Vector3(0.06, 0.09, 0.055) * t, (knee + ankle) * 0.5 + Vector3(0, 0.05, 0.03 * t), pants_m)
	return {"thigh": thigh, "shin": shin}


# Brazo que gira en el hombro. Devuelve el nodo donde colgar lo que lleve en la mano.
static func arm_rig(model: Node3D, shoulder: Vector3, elbow: Vector3, wrist: Vector3, sleeve_m: Material, lower_m: Material,
		skin_c: Color, t: float = 1.0, side: float = 1.0) -> Node3D:
	var inner := pivot(model, shoulder)
	arm(inner, shoulder, elbow, wrist, sleeve_m, lower_m, skin_c, t, side)
	return inner


static func make_rig(upper: Node3D, legs: Array, arm_l: Node3D, arm_r: Node3D, head: Node3D) -> Dictionary:
	return {"spine": upper.get_parent(), "head": head, "hand": arm_r, "arms": [arm_l.get_parent(), arm_r.get_parent()],
		"hips": [legs[0]["thigh"].get_parent(), legs[1]["thigh"].get_parent()],
		"knees": [legs[0]["shin"].get_parent(), legs[1]["shin"].get_parent()]}


# Carrera del vídeo de clase: encorvado, cabeza levantada mirando al frente, pasos
# rápidos y los brazos a lo loco, con el de atrás lanzado hacia arriba.
# ph = fase de la zancada, k = 0 de pie, 1 corriendo a tope.
static func run_pose(rig: Dictionary, ph: float, k: float) -> void:
	rig["spine"].rotation = Vector3(-0.78, sin(ph) * 0.3, sin(ph) * 0.1) * k
	rig["head"].rotation.x = 0.62 * k
	for i in 2:
		var p := ph + PI * i
		var side := -1.0 if i == 0 else 1.0
		rig["hips"][i].rotation.x = (0.3 + 0.95 * sin(p)) * k
		rig["knees"][i].rotation.x = (-0.35 - 1.35 * maxf(0.0, cos(p))) * k
		var swing := (1.0 - sin(p)) * 0.5        # 1 = brazo delante, 0 = brazo atrás y arriba
		rig["arms"][i].rotation = Vector3(lerpf(-2.0, 0.55, swing), 0.0, side * lerpf(0.65, 0.15, swing)) * k


# Cabeza con cráneo, mandíbula, cuello y cara. Devuelve {"head", "eyes"}.
static func human_head(model: Node3D, pos: Vector3, r: float, skin_c: Color, kind: String, brow_c: Color, ears: bool = true) -> Dictionary:
	var head := Node3D.new()
	head.position = pos
	model.add_child(head)
	U.limb(head, Vector3(0, -1.15 * r, 0.04 * r), Vector3(0, -0.5 * r, 0), 0.38 * r, 0.33 * r, skin_c)   # cuello
	var skull := U.sphere(head, r, Vector3.ZERO, skin_c)
	skull.scale = Vector3(0.94, 1.06, 1.0)
	U.ellipsoid(head, Vector3(0.58, 0.4, 0.48) * r, Vector3(0, -0.55 * r, -0.3 * r), skin_c)                 # mandíbula y barbilla
	for sx in [-1.0, 1.0]:
		U.ellipsoid(head, Vector3(0.16, 0.1, 0.06) * r, Vector3(sx * 0.42 * r, -0.2 * r, -0.83 * r), skin_c)   # pómulos
	var eyes := face(head, r, skin_c, kind, brow_c)
	if ears and (kind == "player" or kind == "hacker"):
		for sx in [-1.0, 1.0]:
			var ear := U.sphere(head, 0.16 * r, Vector3(sx * 0.93 * r, -0.02 * r, 0.05 * r), skin_c)
			ear.scale = Vector3(0.45, 1.0, 0.75)
	return {"head": head, "eyes": eyes}


# ---------------------------------------------------------------
# Protagonista personalizable (pelo largo)
# Devuelve {"model", "head", "eyes"}
# ---------------------------------------------------------------
static func build_player(parent: Node, s: Dictionary) -> Dictionary:
	match int(s.get("preset", 0)):
		1:
			return build_juan(parent)
		2:
			return build_juan_gato(parent)
	var model := Node3D.new()
	parent.add_child(model)
	var skin_c := col(SKINS, s["skin"])
	var shirt := col(SHIRTS, s["shirt"])
	var pants := col(PANTS, s["pants"])
	var shoe_c := col(SHOES, s["shoes"])
	var hair := col(HAIRS, s["hair"])
	var dark_shirt := shirt.darkened(0.3)
	var sole := Color(0.95, 0.95, 0.95)
	if s["shoes"] == 0:
		sole = Color(0.3, 0.3, 0.32)
	var shirt_m := U.mat(shirt)
	var pants_m := U.mat(pants)
	var skin_m := U.mat(skin_c)

	# piernas y zapatillas
	var legs := []
	for sx in [-1.0, 1.0]:
		var ankle := Vector3(sx * 0.1, 0.13, 0.0)
		var lg := leg_rig(model, Vector3(sx * 0.11, 0.9, 0.0), Vector3(sx * 0.105, 0.5, -0.03), ankle, pants_m)
		shoe(lg["shin"], ankle, shoe_c, sole)
		legs.append(lg)
	# cadera y cinturón
	U.ellipsoid_m(model, Vector3(0.2, 0.13, 0.14), Vector3(0, 0.93, 0), pants_m)
	var root := model                  # de aquí para arriba todo se inclina con el tronco
	model = pivot(root, Vector3(0, 0.95, 0))
	var belt := U.cylinder(model, 0.19, 0.05, Vector3(0, 0.99, 0), Color(0.1, 0.08, 0.06))
	belt.scale.z = 0.74
	U.box(model, Vector3(0.06, 0.045, 0.02), Vector3(0, 0.99, -0.14), Color(0.75, 0.7, 0.5))     # hebilla

	# torso: pecho ancho y cintura más estrecha
	U.torso(model, 1.04, 1.44, 0.22, 0.14, shirt_m)
	var forearm_m := skin_m
	match int(s["outfit"]):
		0:   # camiseta: cuello, logo y mangas cortas
			var collar := U.cylinder(model, 0.085, 0.03, Vector3(0, 1.53, -0.005), dark_shirt)
			collar.scale.z = 0.9
			U.box(model, Vector3(0.09, 0.09, 0.02), Vector3(0.09, 1.3, -0.15), Color(1, 1, 1))
		1:   # sudadera con capucha
			forearm_m = shirt_m
			var hood := U.ellipsoid(model, Vector3(0.2, 0.12, 0.12), Vector3(0, 1.5, 0.12), dark_shirt)
			hood.rotation_degrees.x = -20.0
			var pocket := U.box(model, Vector3(0.26, 0.12, 0.03), Vector3(0, 1.1, -0.14), dark_shirt)
			pocket.rotation_degrees.x = -6.0
			for sx in [-1.0, 1.0]:
				U.limb(model, Vector3(sx * 0.05, 1.5, -0.13), Vector3(sx * 0.06, 1.3, -0.16), 0.008, 0.008, Color(0.95, 0.95, 0.95))
		2:   # chaqueta abierta con camiseta blanca debajo
			forearm_m = shirt_m
			U.ellipsoid(model, Vector3(0.1, 0.2, 0.05), Vector3(0, 1.27, -0.115), Color(0.95, 0.95, 0.95))
			for sx in [-1.0, 1.0]:
				var lap := U.box(model, Vector3(0.05, 0.4, 0.03), Vector3(sx * 0.09, 1.25, -0.145), dark_shirt)
				lap.rotation_degrees.z = sx * 6.0
				U.box(model, Vector3(0.06, 0.05, 0.02), Vector3(sx * 0.13, 1.12, -0.15), dark_shirt)   # bolsillos

	# brazos sujetando el arma (mano derecha en la empuñadura, izquierda bajo el cañón)
	var arm_r := arm_rig(model, Vector3(0.23, 1.43, 0.0), Vector3(0.27, 1.17, -0.12), Vector3(0.22, 1.06, -0.36), shirt_m, forearm_m, skin_c, 1.0, 1.0)
	var arm_l := arm_rig(model, Vector3(-0.23, 1.43, 0.0), Vector3(-0.2, 1.13, -0.22), Vector3(0.1, 1.06, -0.55), shirt_m, forearm_m, skin_c, 1.0, -1.0)

	# cabeza con cara
	var hp := human_head(model, Vector3(0, 1.72, -0.01), 0.22, skin_c, "player", hair.darkened(0.35))
	var head: Node3D = hp["head"]
	var eyes: Array = hp["eyes"]

	# PELO LARGO: casquete, flequillo con mechones, laterales y melena por la espalda
	var cap := U.sphere(head, 0.235, Vector3(0, 0.06, 0.04), hair)
	cap.scale = Vector3(1.0, 0.95, 1.02)
	for i in 5:
		var lock := U.ellipsoid(head, Vector3(0.05, 0.075, 0.035), Vector3(-0.15 + i * 0.075, 0.17 - absf(i - 2) * 0.012, -0.17), hair)
		lock.rotation_degrees.z = (i - 2) * -12.0
	for sx in [-1.0, 1.0]:
		U.limb(head, Vector3(sx * 0.2, 0.08, 0.04), Vector3(sx * 0.21, -0.32, 0.08), 0.06, 0.045, hair)
	U.limb(head, Vector3(0, 0.05, 0.16), Vector3(0, -0.6, 0.24), 0.17, 0.12, hair)
	var back := U.ellipsoid(head, Vector3(0.2, 0.32, 0.07), Vector3(0, -0.3, 0.24), hair)
	back.rotation_degrees.x = 8.0

	# accesorios de cabeza
	match int(s["hat"]):
		1:   # gorra
			var hat_c := Color(0.85, 0.12, 0.12)
			if s["shirt"] == 3:
				hat_c = Color(0.1, 0.1, 0.12)
			var crown := U.sphere(head, 0.245, Vector3(0, 0.15, 0.03), hat_c)
			crown.scale = Vector3(1.0, 0.62, 1.04)
			var visor := U.ellipsoid(head, Vector3(0.15, 0.012, 0.12), Vector3(0, 0.11, -0.28), hat_c)
			visor.rotation_degrees.x = 8.0
			U.sphere(head, 0.02, Vector3(0, 0.3, 0.03), hat_c.darkened(0.2))
		2:   # gorro de lana
			var crown2 := U.sphere(head, 0.25, Vector3(0, 0.15, 0.03), dark_shirt)
			crown2.scale = Vector3(1.0, 0.8, 1.04)
			var rim := U.cylinder(head, 0.255, 0.07, Vector3(0, 0.12, 0.03), dark_shirt.darkened(0.2))
			rim.scale.z = 1.04
			U.sphere(head, 0.07, Vector3(0, 0.36, 0.03), Color(0.95, 0.95, 0.95))
		3:   # diadema
			var band := U.cylinder(head, 0.24, 0.04, Vector3(0, 0.14, 0.02), Color(0.9, 0.15, 0.3))
			band.rotation_degrees.x = -15.0

	# gafas
	var frame := Color(0.08, 0.08, 0.09)
	var g := int(s["glasses"])
	if g > 0:
		var ey := 0.022
		var ez := -0.225
		for sx in [-1.0, 1.0]:
			var ex: float = sx * 0.08
			if g == 1:
				var rim2 := U.cylinder(head, 0.05, 0.012, Vector3(ex, ey, ez), frame)
				rim2.rotation_degrees.x = 90.0
				rim2.scale = Vector3(1.1, 1.0, 0.85)
				var lens := U.cylinder(head, 0.044, 0.004, Vector3(ex, ey, ez - 0.004), Color(0.75, 0.85, 0.95, 0.35))
				lens.rotation_degrees.x = 90.0
				lens.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			else:
				var sun := U.ellipsoid(head, Vector3(0.058, 0.042, 0.01), Vector3(ex, ey, ez), Color(0.03, 0.03, 0.04))
				sun.material_override.metallic = 0.6
			U.box(head, Vector3(0.01, 0.01, 0.23), Vector3(sx * 0.14, ey + 0.02, -0.11), frame)
		U.box(head, Vector3(0.05, 0.01, 0.01), Vector3(0, ey + 0.02, ez), frame)

	U.toonify(root, 0.01)
	return {"model": root, "head": head, "eyes": eyes, "rig": make_rig(model, legs, arm_l, arm_r, head)}


# ---------------------------------------------------------------
# Zombie del kimono (modelos/zombi_kimono.glb, mide 2,4 m con big = 1.2).
# Trae las animaciones "Quieto" y "Vomitar"; las piernas no están animadas,
# así que al andar las mueve zombie_walk().
# ---------------------------------------------------------------
static var _matte_mats := {}


static func build_zombie(parent: Node, big: float) -> Dictionary:
	var model := Node3D.new()
	model.scale = Vector3.ONE * big / 1.2
	parent.add_child(model)
	var inst: Node3D = ZombiScene.instantiate()
	inst.rotation.y = PI        # el modelo mira a +Z y en el juego se mira a -Z
	model.add_child(inst)
	var anim := anim_of(inst)
	anim.get_animation("Quieto").loop_mode = Animation.LOOP_LINEAR
	anim.play("Quieto")
	anim.seek(randf() * anim.current_animation_length)
	# con 14 zombies las sombras son lo más caro: solo las proyectan torso y muslos
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		if not m.name in ["Pecho", "CaderaIzq", "CaderaDer"]:
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if m.name != "Medalla":
			for i in m.mesh.get_surface_count():
				m.set_surface_override_material(i, _matte(m.mesh.surface_get_material(i)))
	var legs: Array = []
	for side in ["Izq", "Der"]:
		var hip: Node3D = inst.find_child("Cadera" + side)
		var knee: Node3D = inst.find_child("Rodilla" + side)
		legs.append({"hip": hip, "knee": knee, "hip_x": hip.rotation.x, "knee_x": knee.rotation.x})
	return {"model": model, "head": inst.find_child("Cabeza"), "eyes": [], "anim": anim, "legs": legs}


# Copia del material sin brillos ni reflejos: compartida, porque salen muchos zombies a la vez
static func _matte(m: StandardMaterial3D) -> StandardMaterial3D:
	if not _matte_mats.has(m):
		var d: StandardMaterial3D = m.duplicate()
		d.metallic = 0.0
		d.metallic_specular = 0.0
		d.roughness = 1.0
		d.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		_matte_mats[m] = d
	return _matte_mats[m]


# Mueve las piernas del zombie: phase avanza al andar y k (0..1) es la fuerza del paso
static func zombie_walk(legs: Array, phase: float, k: float) -> void:
	for i in legs.size():
		var s := sin(phase + i * PI)
		legs[i]["hip"].rotation.x = legs[i]["hip_x"] - s * 0.5 * k
		legs[i]["knee"].rotation.x = legs[i]["knee_x"] + maxf(0.0, cos(phase + i * PI)) * 0.75 * k


static func anim_of(n: Node) -> AnimationPlayer:
	return n.find_children("*", "AnimationPlayer", true, false)[0]


# ---------------------------------------------------------------
# Aspecto predeterminado: "Spider-Juan" (sacado de la foto de juan/)
# Pelo oscuro rizado y voluminoso recogido atrás, gafas finas de metal,
# barba de unos días y traje de araña rojo con telaraña plateada,
# laterales azules y araña negra en el pecho.
# ---------------------------------------------------------------
static var _web_mat: StandardMaterial3D
static var _blue_mat: StandardMaterial3D
static var _lace_mat: StandardMaterial3D


# Tela roja con la telaraña dibujada por código (celdas con hilos plateados)
static func web_material() -> StandardMaterial3D:
	if _web_mat != null:
		return _web_mat
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var red := Color(0.72, 0.07, 0.08)
	var line := Color(0.78, 0.76, 0.8)
	img.fill(red)
	for y in n:
		for x in n:
			# sombreado suave dentro de cada celda (relieve de la tela)
			var cx := float(x % 32) / 32.0
			var cy := float(y % 32) / 32.0
			var sh := 1.0 - 0.18 * (absf(cx - 0.5) + absf(cy - 0.5))
			img.set_pixel(x, y, red * sh)
	# hilos verticales y hilos horizontales en arco (forma de telaraña)
	for x in n:
		for k in 8:
			var yy := int(k * 32 + 5.0 * sin(float(x % 32) / 32.0 * PI))
			for w in 2:
				img.set_pixel(x, (yy + w) % n, line)
	for k in 8:
		for y in n:
			for w in 2:
				img.set_pixel((k * 32 + w) % n, y, line)
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 2.2
	m.roughness = 0.55
	_web_mat = m
	return m


static func blue_suit_material() -> StandardMaterial3D:
	if _blue_mat != null:
		return _blue_mat
	var m := StandardMaterial3D.new()
	m.albedo_texture = U._noise_tex("suit_blue", FastNoiseLite.TYPE_CELLULAR, 0.9, Color(0.09, 0.15, 0.42), Color(0.16, 0.26, 0.6))
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 6.0
	m.roughness = 0.6
	_blue_mat = m
	return m


static func build_juan(parent: Node) -> Dictionary:
	var model := Node3D.new()
	parent.add_child(model)
	var skin_c := Color(0.93, 0.77, 0.66)
	var hair := Color(0.09, 0.065, 0.05)
	var suit_red := Color(0.72, 0.07, 0.08)
	var web := web_material()
	var blue := blue_suit_material()
	var black := Color(0.04, 0.04, 0.05)

	# piernas: rojo con telaraña por delante y azul por los lados, botas rojas
	var legs := []
	for sx in [-1.0, 1.0]:
		var ankle := Vector3(sx * 0.1, 0.13, 0.0)
		var lg := leg_rig(model, Vector3(sx * 0.11, 0.9, 0.0), Vector3(sx * 0.105, 0.5, -0.03), ankle, web)
		U.limb_m(lg["thigh"], Vector3(sx * 0.143, 0.86, 0.01), Vector3(sx * 0.137, 0.5, -0.02), 0.08, 0.06, blue)
		U.limb_m(lg["shin"], Vector3(sx * 0.135, 0.47, -0.02), Vector3(sx * 0.128, 0.17, 0.0), 0.058, 0.042, blue)
		shoe(lg["shin"], ankle, suit_red, suit_red.darkened(0.35))
		U.cylinder(lg["shin"], 0.062, 0.12, Vector3(ankle.x, 0.16, 0.0), suit_red)   # caña de la bota
		legs.append(lg)
	U.ellipsoid_m(model, Vector3(0.2, 0.13, 0.14), Vector3(0, 0.93, 0), web)
	var root := model                  # de aquí para arriba todo se inclina con el tronco
	model = pivot(root, Vector3(0, 0.95, 0))
	# cinturón con telaraña (el traje no lleva cinturón de verdad, solo la costura)
	var seam := U.cylinder(model, 0.19, 0.03, Vector3(0, 1.0, 0), suit_red.darkened(0.3))
	seam.scale.z = 0.74

	# torso rojo con telaraña y paneles azules en los costados
	U.torso(model, 1.04, 1.44, 0.21, 0.135, web)
	for sx in [-1.0, 1.0]:
		var panel := U.ellipsoid_m(model, Vector3(0.04, 0.17, 0.09), Vector3(sx * 0.178, 1.17, 0.0), blue)
		panel.rotation_degrees.z = sx * -5.0
	# araña negra en el pecho
	var spider := Node3D.new()
	spider.position = Vector3(0, 1.27, -0.142)
	model.add_child(spider)
	U.ellipsoid(spider, Vector3(0.022, 0.03, 0.012), Vector3(0, 0.025, 0), black)
	U.ellipsoid(spider, Vector3(0.026, 0.05, 0.012), Vector3(0, -0.04, 0), black)
	for sx in [-1.0, 1.0]:
		for i in 4:
			var a := Vector3(sx * 0.015, 0.03 - i * 0.02, 0)
			var knee := a + Vector3(sx * 0.045, 0.03 - i * 0.012, -0.004)
			var tip := knee + Vector3(sx * 0.02, -0.05 + (3 - i) * 0.01 - 0.02 * i, 0)
			U.limb(spider, a, knee, 0.005, 0.004, black)
			U.limb(spider, knee, tip, 0.004, 0.003, black)
	# cuello alto del traje
	var collar := U.cylinder(model, 0.075, 0.12, Vector3(0, 1.53, 0.0), suit_red)
	collar.material_override = web

	# brazos con el traje y guantes rojos, sujetando el arma
	var arm_r := arm_rig(model, Vector3(0.22, 1.43, 0.0), Vector3(0.27, 1.17, -0.12), Vector3(0.22, 1.06, -0.36), web, web, suit_red, 0.95, 1.0)
	var arm_l := arm_rig(model, Vector3(-0.22, 1.43, 0.0), Vector3(-0.2, 1.13, -0.22), Vector3(0.1, 1.06, -0.55), web, web, suit_red, 0.95, -1.0)

	var jh := juan_head(model, skin_c, hair)
	var head: Node3D = jh["head"]
	var eyes: Array = jh["eyes"]

	U.toonify(root, 0.01)
	return {"model": root, "head": head, "eyes": eyes, "rig": make_rig(model, legs, arm_l, arm_r, head)}


# Cabeza de Juan: cara, pelo rizado recogido y gafas finas (la usan sus dos aspectos)
static func juan_head(model: Node3D, skin_c: Color, hair: Color) -> Dictionary:
	# cabeza: sonrisa y barba de unos días
	var hp := human_head(model, Vector3(0, 1.73, -0.01), 0.215, skin_c, "player", hair)
	var head: Node3D = hp["head"]
	var eyes: Array = hp["eyes"]
	# barba de unos días: sombra fina pegada a la barbilla
	var stubble := U.ellipsoid(head, Vector3(0.075, 0.03, 0.02), Vector3(0, -0.15, -0.165), skin_c.darkened(0.12))
	stubble.rotation_degrees.x = -35.0

	# PELO: rizado, oscuro y con mucho volumen, peinado hacia atrás y recogido
	var cap := U.sphere(head, 0.225, Vector3(0, 0.1, 0.075), hair)
	cap.scale = Vector3(1.04, 0.93, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024           # siempre los mismos rizos
	var c0 := Vector3(0, 0.1, 0.075)
	var placed := 0
	while placed < 90:
		# rizos repartidos por arriba, los lados y la nuca (la frente queda despejada)
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.55, 1), rng.randf_range(-1, 1)).normalized()
		if dir.z < -0.35 and dir.y < 0.75:
			continue
		if dir.y < -0.2 and absf(dir.x) > 0.6 and dir.z < 0.2:
			continue           # no tapar las orejas
		placed += 1
		var cr := rng.randf_range(0.03, 0.052)
		var curl := U.ellipsoid(head, Vector3(cr, cr * rng.randf_range(0.7, 1.15), cr * rng.randf_range(0.8, 1.2)),
			c0 + dir * rng.randf_range(0.215, 0.245), hair.lightened(rng.randf_range(0.0, 0.1)))
		curl.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, 0.0)
	# mechones encrespados en las sienes
	for sx in [-1.0, 1.0]:
		for i in 5:
			U.sphere(head, rng.randf_range(0.035, 0.05), Vector3(sx * (0.215 + rng.randf_range(0.0, 0.035)), 0.05 + i * 0.045, 0.0 + i * 0.03), hair)
	# coleta suelta de rizos por la nuca hasta los hombros
	for i in 9:
		var k := float(i) / 8.0
		var pos := Vector3(rng.randf_range(-0.07, 0.07), -0.08 - k * 0.32, 0.22 + k * 0.06)
		U.sphere(head, lerpf(0.09, 0.06, k), pos, hair.lightened(rng.randf_range(0.0, 0.06)))

	# gafas finas de metal, rectangulares
	var frame := Color(0.45, 0.45, 0.5)
	var fm := U.mat(frame)
	fm.metallic = 0.8
	var ey := 0.03
	var ez := -0.218
	for sx in [-1.0, 1.0]:
		var ex: float = sx * 0.078
		U.box_m(head, Vector3(0.088, 0.006, 0.006), Vector3(ex, ey + 0.028, ez), fm)
		U.box_m(head, Vector3(0.082, 0.006, 0.006), Vector3(ex, ey - 0.03, ez), fm)
		U.box_m(head, Vector3(0.006, 0.058, 0.006), Vector3(ex - sx * 0.044, ey, ez), fm)
		U.box_m(head, Vector3(0.006, 0.05, 0.006), Vector3(ex + sx * 0.043, ey, ez), fm)
		var lens := U.box(head, Vector3(0.082, 0.054, 0.003), Vector3(ex, ey, ez - 0.002), Color(0.85, 0.9, 0.95, 0.08))
		lens.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		U.box_m(head, Vector3(0.006, 0.006, 0.22), Vector3(sx * 0.125, ey + 0.02, -0.11), fm)    # patillas
	U.box_m(head, Vector3(0.03, 0.006, 0.006), Vector3(0, ey + 0.015, ez), fm)                   # puente

	return {"head": head, "eyes": eyes}


# ---------------------------------------------------------------
# Aspecto predeterminado: "Juan Gato" (foto juan/juangato.png)
# Orejas de gato negras, bigotes pintados, sudadera verde azulada con
# capucha y el logo "Skull studio", pantalón oscuro y cola de gato.
# ---------------------------------------------------------------
static func build_juan_gato(parent: Node) -> Dictionary:
	var model := Node3D.new()
	parent.add_child(model)
	var skin_c := Color(0.93, 0.77, 0.66)
	var hair := Color(0.09, 0.065, 0.05)
	var hoodie := Color(0.2, 0.29, 0.29)
	var cat := Color(0.05, 0.05, 0.055)
	var hoodie_m := StandardMaterial3D.new()     # tela de forro polar
	hoodie_m.albedo_texture = U._noise_tex("polar", FastNoiseLite.TYPE_SIMPLEX, 0.9, hoodie.darkened(0.12), hoodie.lightened(0.06))
	hoodie_m.uv1_triplanar = true
	hoodie_m.uv1_scale = Vector3.ONE * 5.0
	var pants_m := U.mat(Color(0.12, 0.12, 0.14))

	# pantalón oscuro y zapatillas oscuras con suela blanca
	var legs := []
	for sx in [-1.0, 1.0]:
		var ankle := Vector3(sx * 0.1, 0.13, 0.0)
		var lg := leg_rig(model, Vector3(sx * 0.11, 0.9, 0.0), Vector3(sx * 0.105, 0.5, -0.03), ankle, pants_m)
		shoe(lg["shin"], ankle, Color(0.16, 0.16, 0.18), Color(0.95, 0.95, 0.95))
		var stripe := U.ellipsoid(lg["shin"], Vector3(0.012, 0.022, 0.07), Vector3(ankle.x + sx * 0.06, 0.08, ankle.z - 0.04), Color(0.92, 0.92, 0.92))
		stripe.rotation_degrees.x = -12.0
		legs.append(lg)
	U.ellipsoid_m(model, Vector3(0.2, 0.13, 0.14), Vector3(0, 0.93, 0), pants_m)
	var root := model                  # de aquí para arriba todo se inclina con el tronco
	model = pivot(root, Vector3(0, 0.95, 0))

	# sudadera con capucha, cordones, bolsillo, puños y logo
	U.torso(model, 1.0, 1.44, 0.225, 0.145, hoodie_m, 0.01)
	var band := U.cylinder(model, 0.205, 0.07, Vector3(0, 0.95, 0), hoodie.darkened(0.15))   # cintura elástica
	band.scale.z = 0.75
	var hood := U.ellipsoid(model, Vector3(0.21, 0.14, 0.13), Vector3(0, 1.5, 0.1), hoodie.darkened(0.08))
	hood.rotation_degrees.x = -18.0
	var rim := U.cylinder(model, 0.115, 0.06, Vector3(0, 1.53, -0.01), hoodie.darkened(0.12))   # borde de la capucha
	rim.scale.z = 0.95
	U.cylinder(model, 0.08, 0.06, Vector3(0, 1.545, -0.01), Color(0.85, 0.85, 0.86))             # camiseta blanca debajo
	for sx in [-1.0, 1.0]:
		U.limb(model, Vector3(sx * 0.045, 1.5, -0.125), Vector3(sx * 0.055, 1.2, -0.17), 0.007, 0.007, Color(0.55, 0.57, 0.6))
		U.cylinder(model, 0.009, 0.03, Vector3(sx * 0.055, 1.185, -0.172), Color(0.75, 0.75, 0.78))   # puntera metálica
	var pocket := U.box_m(model, Vector3(0.28, 0.12, 0.03), Vector3(0, 1.1, -0.148), hoodie_m)
	pocket.rotation_degrees.x = -5.0
	var logo := Label3D.new()
	logo.text = "Skull\n   studio"
	var script_font := SystemFont.new()
	script_font.font_names = PackedStringArray(["Segoe Script", "Brush Script MT", "Comic Sans MS"])
	logo.font = script_font
	logo.font_size = 44
	logo.pixel_size = 0.0018
	logo.outline_size = 0
	logo.modulate = Color(0.95, 0.95, 0.92)
	logo.position = Vector3(0, 1.27, -0.152)
	logo.rotation_degrees.y = 180.0
	model.add_child(logo)

	# brazos con mangas largas (puños elásticos) sujetando el arma
	var arm_r := arm_rig(model, Vector3(0.23, 1.43, 0.0), Vector3(0.27, 1.17, -0.12), Vector3(0.22, 1.06, -0.36), hoodie_m, hoodie_m, skin_c, 1.05, 1.0)
	var arm_l := arm_rig(model, Vector3(-0.23, 1.43, 0.0), Vector3(-0.2, 1.13, -0.22), Vector3(0.1, 1.06, -0.55), hoodie_m, hoodie_m, skin_c, 1.05, -1.0)
	for w in [[Vector3(0.22, 1.06, -0.36), Vector3(0.27, 1.17, -0.12), arm_r], [Vector3(0.1, 1.06, -0.55), Vector3(-0.2, 1.13, -0.22), arm_l]]:
		U.limb(w[2], w[0], w[0] + (w[1] - w[0]).normalized() * 0.06, 0.047, 0.047, hoodie.darkened(0.15))   # puño

	# cabeza de Juan + orejas de gato y bigotes pintados
	var jh := juan_head(model, skin_c, hair)
	var head: Node3D = jh["head"]
	var eyes: Array = jh["eyes"]
	for sx in [-1.0, 1.0]:
		var ear := Node3D.new()
		ear.position = Vector3(sx * 0.13, 0.3, 0.03)
		ear.rotation_degrees = Vector3(-8.0, 0.0, -sx * 22.0)
		head.add_child(ear)
		var outer := U.cone(ear, 0.0, 0.085, 0.15, Vector3(0, 0.06, 0), cat)
		outer.scale.z = 0.45
		var inner := U.cone(ear, 0.0, 0.05, 0.09, Vector3(0, 0.04, -0.018), Color(0.16, 0.14, 0.15))
		inner.scale.z = 0.25
		for i in 3:                                            # bigotes
			var wsk := U.box(head, Vector3(0.075, 0.0035, 0.003), Vector3(sx * 0.1, -0.045 - i * 0.017, -0.193 + absf(i - 1) * 0.004), Color(0.15, 0.1, 0.08))
			wsk.rotation_degrees = Vector3(0.0, sx * 28.0, sx * (12.0 - i * 12.0))

	# cola de gato negra y peluda que sale de la espalda
	var pts := [Vector3(0, 0.9, 0.14), Vector3(0, 0.82, 0.32), Vector3(0, 0.86, 0.5), Vector3(0, 1.02, 0.62),
		Vector3(0, 1.22, 0.66), Vector3(0, 1.38, 0.6)]
	for i in pts.size() - 1:
		U.limb(model, pts[i], pts[i + 1], 0.045 + i * 0.004, 0.049 + i * 0.004, cat)
	var tip := U.sphere(model, 0.07, pts[pts.size() - 1] + Vector3(0, 0.03, -0.02), cat)
	tip.scale = Vector3(0.9, 1.25, 0.9)

	U.toonify(root, 0.01)
	return {"model": root, "head": head, "eyes": eyes, "rig": make_rig(model, legs, arm_l, arm_r, head)}


# ---------------------------------------------------------------
# Jan (foto juan/jan.jpg): gorra de rejilla negra con el frontal blanco y
# un parche amarillo, sudadera negra con estrella blanca, bigote y perilla.
# Debajo de la gorra... una calva que brilla. Se usa en miniatura como
# granada cegadora. Devuelve {"model", "head", "cap", "bald_m"}.
# ---------------------------------------------------------------
static func build_jan(parent: Node) -> Dictionary:
	var model := Node3D.new()
	parent.add_child(model)
	var skin_c := Color(0.9, 0.74, 0.62)
	var hair := Color(0.2, 0.13, 0.08)
	var black := Color(0.06, 0.06, 0.07)
	var hoodie_m := StandardMaterial3D.new()
	hoodie_m.albedo_texture = U._noise_tex("hoodie_black", FastNoiseLite.TYPE_SIMPLEX, 0.9, Color(0.04, 0.04, 0.05), Color(0.11, 0.11, 0.12))
	hoodie_m.uv1_triplanar = true
	hoodie_m.uv1_scale = Vector3.ONE * 5.0
	hoodie_m.roughness = 0.95

	# piernas con chándal negro y zapatillas blancas
	for sx in [-1.0, 1.0]:
		var ankle := Vector3(sx * 0.1, 0.13, 0.0)
		leg(model, Vector3(sx * 0.11, 0.9, 0.0), Vector3(sx * 0.105, 0.5, -0.03), ankle, hoodie_m, 1.1)
		shoe(model, ankle, Color(0.95, 0.95, 0.95), Color(0.85, 0.85, 0.85))
	U.ellipsoid_m(model, Vector3(0.21, 0.13, 0.15), Vector3(0, 0.93, 0), hoodie_m)

	# sudadera negra holgada con capucha
	U.torso(model, 1.03, 1.45, 0.24, 0.16, hoodie_m)
	var hood := U.ellipsoid_m(model, Vector3(0.21, 0.12, 0.12), Vector3(0, 1.52, 0.13), hoodie_m)
	hood.rotation_degrees.x = -20.0
	# estrella blanca de 4 puntas en el pecho (como la de la foto)
	for a in [0.0, 90.0]:
		var p := U.box(model, Vector3(0.02, 0.14, 0.008), Vector3(0.08, 1.2, -0.168), Color(0.92, 0.92, 0.92))
		p.rotation_degrees.z = a
	var core := U.box(model, Vector3(0.04, 0.04, 0.008), Vector3(0.08, 1.2, -0.168), Color(0.92, 0.92, 0.92))
	core.rotation_degrees.z = 45.0
	U.box(model, Vector3(0.1, 0.012, 0.006), Vector3(0.06, 1.1, -0.168), Color(0.85, 0.85, 0.85))
	# cadenita de plata asomando por el cuello
	for sx in [-1.0, 1.0]:
		U.limb(model, Vector3(sx * 0.07, 1.53, -0.04), Vector3(0, 1.45, -0.12), 0.006, 0.006, Color(0.8, 0.8, 0.82))

	# brazos con las mangas de la sudadera, pegados al cuerpo
	arm(model, Vector3(0.25, 1.43, 0.0), Vector3(0.3, 1.16, 0.02), Vector3(0.27, 0.92, -0.06), hoodie_m, hoodie_m, skin_c, 1.05, 1.0)
	arm(model, Vector3(-0.25, 1.43, 0.0), Vector3(-0.3, 1.16, 0.02), Vector3(-0.27, 0.92, -0.06), hoodie_m, hoodie_m, skin_c, 1.05, -1.0)

	# cabeza grande (está en miniatura y tiene que leerse bien)
	var r := 0.26
	var hp := human_head(model, Vector3(0, 1.8, -0.01), r, skin_c, "player", hair)
	var head: Node3D = hp["head"]
	# barba de unos días, bigote y perilla
	var stub := U.ellipsoid(head, Vector3(0.6, 0.3, 0.42) * r, Vector3(0, -0.6 * r, -0.33 * r), skin_c.darkened(0.18))
	stub.rotation_degrees.x = -10.0
	U.ellipsoid(head, Vector3(0.3, 0.07, 0.1) * r, Vector3(0, -0.4 * r, -0.86 * r), hair)            # bigote
	U.ellipsoid(head, Vector3(0.14, 0.16, 0.1) * r, Vector3(0, -0.82 * r, -0.66 * r), hair)          # perilla
	# pelo castaño solo por los lados y la nuca (arriba no queda nada)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in 26:
		var ang := lerpf(-PI * 0.62, PI * 0.62, float(i) / 25.0)
		var y := rng.randf_range(-0.12, 0.28) * r
		var lock := U.ellipsoid(head, Vector3(0.2, 0.32, 0.12) * r, Vector3(sin(ang) * 0.93 * r, y, cos(ang) * 0.9 * r + 0.04 * r), hair.lightened(rng.randf() * 0.08))
		lock.rotation.y = ang
	# mechones que se escapan por detrás de la gorra
	for i in 5:
		var lk := U.ellipsoid(head, Vector3(0.14, 0.32, 0.1) * r, Vector3((i - 2) * 0.22 * r, -0.25 * r, 0.95 * r), hair)
		lk.rotation_degrees.x = 25.0
	# LA CALVA: cúpula de piel muy brillante que se ilumina al explotar
	var bald_m := U.mat(skin_c.lightened(0.08))
	bald_m.roughness = 0.12
	bald_m.metallic_specular = 1.0
	bald_m.emission_enabled = true
	bald_m.emission = Color(1.0, 1.0, 0.9)
	bald_m.emission_energy_multiplier = 0.0
	U.ellipsoid_m(head, Vector3(0.82, 0.5, 0.88) * r, Vector3(0, 0.58 * r, 0.02 * r), bald_m)

	# GORRA: rejilla negra detrás, frontal blanco, parche amarillo y visera negra
	var cap := Node3D.new()
	cap.name = "Gorra"
	head.add_child(cap)
	var crown := U.sphere(cap, 1.0 * r, Vector3(0, 0.3 * r, 0.04 * r), black)
	crown.scale = Vector3(1.0, 0.68, 1.04)
	var front := U.ellipsoid(cap, Vector3(0.78, 0.5, 0.42) * r, Vector3(0, 0.48 * r, -0.6 * r), Color(0.95, 0.95, 0.93))
	front.rotation_degrees.x = 22.0
	var patch := U.box(cap, Vector3(0.62 * r, 0.26 * r, 0.02), Vector3(0, 0.5 * r, -0.98 * r), Color(0.95, 0.8, 0.15))
	patch.rotation_degrees.x = -30.0
	var pl := Label3D.new()
	pl.text = "Vertex"
	pl.font_size = 64
	pl.pixel_size = 0.0011
	pl.outline_size = 0
	pl.modulate = Color(0.05, 0.05, 0.05)
	pl.position = Vector3(0, 0, -0.011)
	patch.add_child(pl)
	var brim := U.ellipsoid(cap, Vector3(0.68, 0.04, 0.5) * r, Vector3(0, 0.12 * r, -1.2 * r), black)
	brim.rotation_degrees.x = 8.0
	U.sphere(cap, 0.08 * r, Vector3(0, 0.98 * r, 0.04 * r), black)                 # botón de arriba
	U.box(cap, Vector3(0.45 * r, 0.035 * r, 0.02), Vector3(0, 0.33 * r, -1.0 * r), Color(0.85, 0.15, 0.1))   # bordado rojo

	U.toonify(model, 0.01)
	return {"model": model, "head": head, "cap": cap, "bald_m": bald_m}


# ---------------------------------------------------------------
# Xavier (foto juan/xavier.png): alto, pelo oscuro con volumen arriba,
# gafas, jersey de punto color crema con un estampado gris, camiseta gris
# asomando, acreditación con cinta roja, pantalón beige ancho... y el móvil
# siempre en la mano. Devuelve {"model", "head", "arm", "phone", "lens", "rec"}.
# ---------------------------------------------------------------
static func build_xavier(parent: Node) -> Dictionary:
	var model := Node3D.new()
	model.scale = Vector3.ONE * 1.06
	parent.add_child(model)
	var skin_c := Color(0.94, 0.79, 0.69)
	var hair := Color(0.1, 0.07, 0.05)
	var cream := Color(0.9, 0.87, 0.78)
	var beige := Color(0.84, 0.8, 0.68)
	var grey := Color(0.5, 0.5, 0.5)
	var knit := StandardMaterial3D.new()      # jersey de punto: canalé vertical
	knit.albedo_texture = U._noise_tex("knit", FastNoiseLite.TYPE_SIMPLEX, 2.5, cream.darkened(0.1), cream.lightened(0.05), Vector2(6.0, 0.4))
	knit.uv1_triplanar = true
	knit.uv1_scale = Vector3.ONE * 3.0
	knit.roughness = 1.0
	var pants_m := StandardMaterial3D.new()
	pants_m.albedo_texture = U._noise_tex("chino", FastNoiseLite.TYPE_SIMPLEX, 1.2, beige.darkened(0.06), beige.lightened(0.04))
	pants_m.uv1_triplanar = true
	pants_m.uv1_scale = Vector3.ONE * 4.0

	# pantalón ancho beige y zapatillas oscuras
	for sx in [-1.0, 1.0]:
		var ankle := Vector3(sx * 0.11, 0.13, 0.0)
		leg(model, Vector3(sx * 0.115, 0.9, 0.0), Vector3(sx * 0.12, 0.5, -0.02), ankle, pants_m, 1.3)
		U.cylinder(model, 0.085, 0.14, Vector3(ankle.x, 0.17, 0.0), beige.darkened(0.05))     # bajo del pantalón
		shoe(model, ankle, Color(0.18, 0.18, 0.2), Color(0.85, 0.85, 0.85))
	U.ellipsoid_m(model, Vector3(0.22, 0.13, 0.15), Vector3(0, 0.93, 0), pants_m)
	# camiseta gris oscura asomando por debajo del jersey
	var tee := U.cylinder(model, 0.23, 0.07, Vector3(0, 0.98, 0), Color(0.3, 0.31, 0.33))
	tee.scale.z = 0.72

	# jersey holgado de punto con el canalé de abajo y el cuello redondo
	U.torso(model, 1.06, 1.46, 0.26, 0.17, knit)
	var rib := U.cylinder(model, 0.245, 0.07, Vector3(0, 1.04, 0), cream.darkened(0.08))
	rib.scale.z = 0.72
	var neck := U.cylinder(model, 0.09, 0.05, Vector3(0, 1.54, -0.005), cream.darkened(0.08))
	neck.scale.z = 0.9
	# estampado gris tipo grafiti en el pecho (letras gordas con borde oscuro)
	var gx := [-0.17, -0.08, 0.02, 0.11, 0.19]
	for i in gx.size():
		var gy := 1.24 + sin(i * 1.7) * 0.03
		var blob := U.ellipsoid(model, Vector3(0.035, 0.045, 0.006), Vector3(gx[i] * 0.85, gy, -0.172), grey)
		blob.rotation_degrees.z = i * 37.0
		var edge := U.ellipsoid(model, Vector3(0.042, 0.052, 0.005), Vector3(gx[i] * 0.85, gy, -0.168), grey.darkened(0.45))
		edge.rotation_degrees.z = i * 37.0
	# acreditación: cinta roja al cuello y tarjeta blanca
	var red := Color(0.85, 0.1, 0.08)
	U.limb(model, Vector3(-0.07, 1.53, -0.06), Vector3(-0.04, 1.1, -0.185), 0.011, 0.011, red)
	U.limb(model, Vector3(0.07, 1.53, -0.06), Vector3(0.0, 1.1, -0.185), 0.011, 0.011, red)
	U.box(model, Vector3(0.075, 0.1, 0.008), Vector3(-0.02, 1.04, -0.19), Color(0.97, 0.97, 0.97))
	U.box(model, Vector3(0.075, 0.02, 0.009), Vector3(-0.02, 1.075, -0.19), Color(0.2, 0.35, 0.7))

	# brazo izquierdo relajado (con la manga de punto)
	arm(model, Vector3(-0.27, 1.43, 0.0), Vector3(-0.32, 1.15, 0.02), Vector3(-0.3, 0.9, -0.04), knit, knit, skin_c, 1.15, -1.0)
	# brazo derecho en un pivote: se levanta para hacer fotos y grabar
	var arm_p := Node3D.new()
	arm_p.position = Vector3(0.27, 1.43, 0.0)
	model.add_child(arm_p)
	arm(arm_p, Vector3.ZERO, Vector3(0.03, -0.22, -0.15), Vector3(-0.08, 0.02, -0.36), knit, knit, skin_c, 1.15, 1.0)
	# móvil en vertical: la pantalla mira a Xavier y la cámara al jugador
	var phone := Node3D.new()
	phone.position = Vector3(-0.09, 0.1, -0.42)
	arm_p.add_child(phone)
	U.box(phone, Vector3(0.08, 0.16, 0.012), Vector3.ZERO, Color(0.08, 0.08, 0.1))
	U.box(phone, Vector3(0.07, 0.145, 0.002), Vector3(0, 0, 0.007), Color(0.3, 0.55, 0.9), true)
	var lens := U.cylinder(phone, 0.012, 0.01, Vector3(-0.02, 0.055, -0.008), Color(0.02, 0.02, 0.03))
	lens.rotation_degrees.x = 90.0
	var rec := U.sphere(phone, 0.008, Vector3(0.02, 0.06, -0.008), Color(1.0, 0.05, 0.05), true)
	rec.visible = false

	# cabeza: pelo oscuro corto por los lados y con volumen arriba, gafas
	var hp := human_head(model, Vector3(0, 1.74, -0.01), 0.21, skin_c, "player", hair)
	var head: Node3D = hp["head"]
	var cap := U.sphere(head, 0.222, Vector3(0, 0.07, 0.05), hair)
	cap.scale = Vector3(1.02, 0.9, 1.0)
	var top := U.ellipsoid(head, Vector3(0.18, 0.09, 0.19), Vector3(0, 0.19, -0.01), hair)
	top.rotation_degrees.z = -6.0
	var fringe := U.ellipsoid(head, Vector3(0.14, 0.05, 0.07), Vector3(0.05, 0.17, -0.16), hair)
	fringe.rotation_degrees = Vector3(-20.0, 0.0, -14.0)
	for sx in [-1.0, 1.0]:
		U.ellipsoid(head, Vector3(0.04, 0.1, 0.11), Vector3(sx * 0.19, 0.05, 0.02), hair)    # patillas
	var fm := U.mat(Color(0.12, 0.12, 0.14))
	var ey := 0.03
	var ez := -0.21
	for sx in [-1.0, 1.0]:
		var ex: float = sx * 0.075
		U.box_m(head, Vector3(0.085, 0.009, 0.008), Vector3(ex, ey + 0.027, ez), fm)
		U.box_m(head, Vector3(0.08, 0.007, 0.008), Vector3(ex, ey - 0.027, ez), fm)
		U.box_m(head, Vector3(0.008, 0.055, 0.008), Vector3(ex - sx * 0.042, ey, ez), fm)
		U.box_m(head, Vector3(0.008, 0.05, 0.008), Vector3(ex + sx * 0.041, ey, ez), fm)
		var glass := U.box(head, Vector3(0.08, 0.05, 0.003), Vector3(ex, ey, ez - 0.002), Color(0.85, 0.9, 0.95, 0.1))
		glass.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		U.box_m(head, Vector3(0.008, 0.008, 0.21), Vector3(sx * 0.12, ey + 0.02, -0.105), fm)
	U.box_m(head, Vector3(0.03, 0.008, 0.008), Vector3(0, ey + 0.015, ez), fm)

	U.toonify(model, 0.01)
	return {"model": model, "head": head, "arm": arm_p, "phone": phone, "lens": lens, "rec": rec}


# ---------------------------------------------------------------
# Jesús (foto juan/jesus.jpeg): el hacker de la oleada 10. Pelo oscuro
# corto, cejas gruesas, bigote y perilla, sudadera negra con "FREEDOM"
# en azul claro y la acreditación con cinta roja.
# Devuelve {"model", "head"}.
# ---------------------------------------------------------------
static func build_jesus(parent: Node) -> Dictionary:
	var model := Node3D.new()
	parent.add_child(model)
	var skin_c := Color(0.9, 0.73, 0.6)
	var hair := Color(0.08, 0.06, 0.05)
	var sweat_m := StandardMaterial3D.new()
	sweat_m.albedo_texture = U._noise_tex("hoodie_black", FastNoiseLite.TYPE_SIMPLEX, 0.9, Color(0.04, 0.04, 0.05), Color(0.11, 0.11, 0.12))
	sweat_m.uv1_triplanar = true
	sweat_m.uv1_scale = Vector3.ONE * 5.0

	for sx in [-1.0, 1.0]:
		var ankle := Vector3(sx * 0.1, 0.13, 0.0)
		leg(model, Vector3(sx * 0.115, 0.9, 0.0), Vector3(sx * 0.11, 0.5, -0.03), ankle, U.mat(Color(0.12, 0.13, 0.18)), 1.1)
		shoe(model, ankle, Color(0.1, 0.1, 0.1), Color(0.9, 0.9, 0.9))
	U.ellipsoid_m(model, Vector3(0.22, 0.13, 0.15), Vector3(0, 0.93, 0), sweat_m)
	# sudadera negra ancha (es un chaval grande)
	U.torso(model, 1.03, 1.45, 0.27, 0.17, sweat_m, 0.03)
	var collar := U.cylinder(model, 0.1, 0.04, Vector3(0, 1.54, -0.01), Color(0.03, 0.03, 0.04))
	collar.scale.z = 0.9
	# "FREEDOM" en letras universitarias azul claro con borde blanco
	var fr := Label3D.new()
	fr.text = "FREEDOM"
	fr.font_size = 80
	fr.pixel_size = 0.0016
	fr.outline_size = 14
	fr.modulate = Color(0.62, 0.8, 0.9)
	fr.outline_modulate = Color(0.92, 0.95, 0.97)
	var bold := SystemFont.new()
	bold.font_names = PackedStringArray(["Impact", "Arial Black", "Arial"])
	bold.font_weight = 900
	fr.font = bold
	fr.position = Vector3(0, 1.27, -0.205)
	fr.rotation_degrees.y = 180.0
	model.add_child(fr)
	var sub := Label3D.new()
	sub.text = "Ambitious"
	sub.font_size = 40
	sub.pixel_size = 0.0013
	sub.outline_size = 0
	sub.modulate = Color(0.9, 0.9, 0.9)
	sub.position = Vector3(0.04, 1.2, -0.205)
	sub.rotation_degrees.y = 180.0
	model.add_child(sub)
	# acreditación con cinta roja
	var red := Color(0.85, 0.1, 0.08)
	U.limb(model, Vector3(-0.08, 1.53, -0.07), Vector3(-0.02, 1.1, -0.215), 0.012, 0.012, red)
	U.limb(model, Vector3(0.08, 1.53, -0.07), Vector3(0.02, 1.1, -0.215), 0.012, 0.012, red)
	U.box(model, Vector3(0.11, 0.07, 0.008), Vector3(0, 1.05, -0.215), Color(0.95, 0.95, 0.97))
	U.box(model, Vector3(0.11, 0.015, 0.009), Vector3(0, 1.08, -0.215), Color(0.3, 0.45, 0.85))

	arm(model, Vector3(0.29, 1.43, 0.0), Vector3(0.33, 1.15, 0.02), Vector3(0.3, 0.9, -0.05), sweat_m, sweat_m, skin_c, 1.2, 1.0)
	arm(model, Vector3(-0.29, 1.43, 0.0), Vector3(-0.33, 1.15, 0.02), Vector3(-0.3, 0.9, -0.05), sweat_m, sweat_m, skin_c, 1.2, -1.0)

	# cabeza con cara de malo (cejas en V y sonrisa de dientes)
	var r := 0.22
	var hp := human_head(model, Vector3(0, 1.75, -0.01), r, skin_c, "hacker", hair)
	var head: Node3D = hp["head"]
	# pelo corto: degradado en los lados y algo más de volumen arriba
	var cap := U.sphere(head, 1.03 * r, Vector3(0, 0.12 * r, 0.06 * r), hair)
	cap.scale = Vector3(1.0, 0.9, 1.0)
	var top := U.ellipsoid(head, Vector3(0.82, 0.32, 0.85) * r, Vector3(0, 0.78 * r, -0.08 * r), hair)
	top.rotation_degrees.x = -8.0
	for sx in [-1.0, 1.0]:
		U.ellipsoid(head, Vector3(0.1, 0.42, 0.55) * r, Vector3(sx * 0.9 * r, 0.12 * r, 0.1 * r), hair.lightened(0.12))   # degradado
	# bigote, perilla y barba de unos días
	var stub := U.ellipsoid(head, Vector3(0.6, 0.3, 0.42) * r, Vector3(0, -0.62 * r, -0.33 * r), skin_c.darkened(0.15))
	stub.rotation_degrees.x = -10.0
	U.ellipsoid(head, Vector3(0.32, 0.07, 0.1) * r, Vector3(0, -0.33 * r, -0.88 * r), hair)          # bigote
	U.ellipsoid(head, Vector3(0.17, 0.15, 0.1) * r, Vector3(0, -0.76 * r, -0.74 * r), hair)          # perilla

	U.toonify(model, 0.01)
	return {"model": model, "head": head}


# Tela de cuadros (camisa de leñador de Juan Carlos)
static var _plaid_mat: StandardMaterial3D


static func plaid_material() -> StandardMaterial3D:
	if _plaid_mat != null:
		return _plaid_mat
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var base := Color(0.32, 0.24, 0.18)
	var band := Color(0.5, 0.52, 0.56)
	var dark := Color(0.1, 0.1, 0.14)
	for y in n:
		for x in n:
			var c := base
			var bx := (x % 32) < 10
			var by := (y % 32) < 10
			if bx and by:
				c = dark
			elif bx or by:
				c = band.lerp(base, 0.35)
			if x % 32 == 20 or y % 32 == 20:
				c = Color(0.9, 0.88, 0.85)        # raya fina blanca
			img.set_pixel(x, y, c)
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 3.0
	m.roughness = 0.9
	_plaid_mat = m
	return m


# ---------------------------------------------------------------
# Juan Carlos (foto juan/juancarlos.jpeg): pelo castaño oscuro largo y
# recogido, gafas, barba poblada, camisa de cuadros abierta sobre una
# camiseta gris con dibujo, vaqueros... y su guitarra eléctrica.
# Devuelve {"model", "head", "strum"} (strum = brazo que rasguea).
# ---------------------------------------------------------------
static func build_juancarlos(parent: Node) -> Dictionary:
	var model := Node3D.new()
	parent.add_child(model)
	var skin_c := Color(0.93, 0.76, 0.64)
	var hair := Color(0.2, 0.13, 0.08)
	var plaid := plaid_material()
	var jeans := StandardMaterial3D.new()
	jeans.albedo_texture = U._noise_tex("jeans", FastNoiseLite.TYPE_SIMPLEX, 1.6, Color(0.2, 0.27, 0.42), Color(0.33, 0.42, 0.6))
	jeans.uv1_triplanar = true
	jeans.uv1_scale = Vector3.ONE * 4.0

	for sx in [-1.0, 1.0]:
		var ankle := Vector3(sx * 0.11, 0.13, 0.0)
		leg(model, Vector3(sx * 0.115, 0.9, 0.0), Vector3(sx * 0.115, 0.5, -0.03), ankle, jeans, 1.1)
		shoe(model, ankle, Color(0.25, 0.18, 0.12), Color(0.15, 0.1, 0.08))
	U.ellipsoid_m(model, Vector3(0.21, 0.13, 0.15), Vector3(0, 0.93, 0), jeans)
	# camisa de cuadros abierta y camiseta gris con un dibujo oscuro
	U.torso(model, 1.03, 1.44, 0.23, 0.15, plaid)
	U.ellipsoid(model, Vector3(0.12, 0.21, 0.05), Vector3(0, 1.25, -0.12), Color(0.5, 0.51, 0.54))
	var print_ := U.ellipsoid(model, Vector3(0.06, 0.08, 0.02), Vector3(0.02, 1.27, -0.163), Color(0.2, 0.2, 0.22))
	print_.rotation_degrees.z = 20.0
	for sx in [-1.0, 1.0]:
		var lap := U.box_m(model, Vector3(0.05, 0.42, 0.03), Vector3(sx * 0.12, 1.25, -0.15), plaid)
		lap.rotation_degrees.z = sx * 6.0

	# guitarra eléctrica negra con golpeador blanco, colgada delante
	var guitar := Node3D.new()
	guitar.position = Vector3(0.02, 1.05, -0.24)
	guitar.rotation_degrees = Vector3(0, 0, -20.0)
	model.add_child(guitar)
	var black := Color(0.05, 0.05, 0.06)
	U.ellipsoid(guitar, Vector3(0.16, 0.12, 0.04), Vector3(0.05, -0.03, 0), black)
	U.ellipsoid(guitar, Vector3(0.12, 0.1, 0.04), Vector3(-0.08, 0.02, 0), black)
	U.ellipsoid(guitar, Vector3(0.11, 0.075, 0.008), Vector3(0.0, -0.01, -0.036), Color(0.95, 0.95, 0.93))   # golpeador
	for i in 3:
		U.box(guitar, Vector3(0.015, 0.07, 0.012), Vector3(-0.02 + i * 0.05, 0.0, -0.05), Color(0.85, 0.85, 0.85))   # pastillas
	U.box(guitar, Vector3(0.55, 0.05, 0.025), Vector3(-0.45, 0.02, -0.01), Color(0.75, 0.55, 0.3))        # mástil
	U.box(guitar, Vector3(0.55, 0.045, 0.006), Vector3(-0.45, 0.02, -0.025), Color(0.3, 0.17, 0.08))      # diapasón
	U.box(guitar, Vector3(0.15, 0.07, 0.02), Vector3(-0.78, 0.04, -0.01), Color(0.75, 0.55, 0.3))         # pala
	U.limb(model, Vector3(-0.17, 1.42, 0.05), Vector3(0.22, 0.98, -0.18), 0.012, 0.012, black)           # correa

	# brazo izquierdo en el mástil
	arm(model, Vector3(-0.23, 1.43, 0.0), Vector3(-0.32, 1.12, -0.12), Vector3(-0.38, 1.2, -0.29), plaid, plaid, skin_c, 1.0, -1.0)
	# brazo derecho en un pivote para rasguear
	var strum := Node3D.new()
	strum.position = Vector3(0.23, 1.43, 0.0)
	model.add_child(strum)
	arm(strum, Vector3.ZERO, Vector3(0.1, -0.26, -0.08), Vector3(-0.12, -0.36, -0.26), plaid, plaid, skin_c, 1.0, 1.0)

	# cabeza: melena castaña recogida, gafas finas y barba poblada
	var r := 0.215
	var hp := human_head(model, Vector3(0, 1.73, -0.01), r, skin_c, "player", hair)
	var head: Node3D = hp["head"]
	var cap := U.sphere(head, 1.04 * r, Vector3(0, 0.12 * r, 0.1 * r), hair)
	cap.scale = Vector3(1.02, 0.95, 1.02)
	for sx in [-1.0, 1.0]:
		U.limb(head, Vector3(sx * 0.85 * r, 0.3 * r, 0.2 * r), Vector3(sx * 0.8 * r, -0.6 * r, 0.45 * r), 0.25 * r, 0.18 * r, hair)
	U.limb(head, Vector3(0, 0.0, 0.9 * r), Vector3(0, -1.4 * r, 1.15 * r), 0.3 * r, 0.2 * r, hair)          # coleta
	# barba poblada que cubre mandíbula y barbilla, y bigote
	var beard := U.ellipsoid(head, Vector3(0.78, 0.6, 0.62) * r, Vector3(0, -0.6 * r, -0.36 * r), hair.lightened(0.04))
	beard.rotation_degrees.x = -12.0
	for sx in [-1.0, 1.0]:
		U.ellipsoid(head, Vector3(0.2, 0.42, 0.4) * r, Vector3(sx * 0.72 * r, -0.25 * r, -0.2 * r), hair)    # patillas
	U.ellipsoid(head, Vector3(0.36, 0.1, 0.14) * r, Vector3(0, -0.34 * r, -0.88 * r), hair)                  # bigote
	U.box(head, Vector3(0.2 * r, 0.06 * r, 0.05 * r), Vector3(0, -0.5 * r, -0.97 * r), Color(0.45, 0.12, 0.1))   # boca
	# gafas finas de metal
	var fm := U.mat(Color(0.35, 0.35, 0.38))
	var ey := 0.1 * r
	var ez := -0.98 * r
	for sx in [-1.0, 1.0]:
		var ex: float = sx * 0.36 * r
		U.box_m(head, Vector3(0.4 * r, 0.03 * r, 0.03 * r), Vector3(ex, ey + 0.13 * r, ez), fm)
		U.box_m(head, Vector3(0.38 * r, 0.03 * r, 0.03 * r), Vector3(ex, ey - 0.12 * r, ez), fm)
		U.box_m(head, Vector3(0.03 * r, 0.25 * r, 0.03 * r), Vector3(ex + sx * 0.2 * r, ey, ez), fm)
		U.box_m(head, Vector3(0.03 * r, 0.25 * r, 0.03 * r), Vector3(ex - sx * 0.19 * r, ey, ez), fm)
		U.box_m(head, Vector3(0.03 * r, 0.03 * r, 0.95 * r), Vector3(sx * 0.58 * r, ey + 0.1 * r, -0.5 * r), fm)
	U.box_m(head, Vector3(0.15 * r, 0.03 * r, 0.03 * r), Vector3(0, ey + 0.06 * r, ez), fm)

	U.toonify(model, 0.01)
	return {"model": model, "head": head, "strum": strum}


# ---------------------------------------------------------------
# Encaje rojo sobre tela negra (sombrero de bruja de Isabella): los hilos son
# los bordes de las celdas de un ruido celular
static func lace_material() -> StandardMaterial3D:
	if _lace_mat != null:
		return _lace_mat
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.frequency = 0.05
	noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	var src := noise.get_seamless_image(256, 256)
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var cloth := Color(0.13, 0.07, 0.09)
	var thread := Color(0.72, 0.1, 0.13)
	for y in n:
		for x in n:
			img.set_pixel(x, y, cloth.lerp(thread, clampf(1.0 - src.get_pixel(x, y).r * 12.0, 0.0, 1.0)))
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 2.5
	_lace_mat = m
	return m


# ---------------------------------------------------------------
# Isabella bruja (fotos juan/isabella.png e isabellabruja.jpeg): sombrero de
# bruja arrugado de encaje rojo y negro con flecos rojos, pelo moreno rizado
# recogido atrás, gafas finas redondas, tres aros dorados en la oreja, jersey
# negro de cuello alto, vaqueros anchos azul claro con el bajo vuelto,
# zapatillas blancas con rayas rojas y un bolso negro cruzado (su arma).
# Devuelve {"model", "head", "arm", "bag"} (arm = brazo que pega con el bolso).
# ---------------------------------------------------------------
static func build_isabella(parent: Node) -> Dictionary:
	var model := Node3D.new()
	model.scale = Vector3.ONE * 0.96
	parent.add_child(model)
	var skin_c := Color(0.9, 0.73, 0.6)
	var hair := Color(0.07, 0.05, 0.04)
	var knit := StandardMaterial3D.new()          # punto negro del jersey
	knit.albedo_texture = U._noise_tex("knit_black", FastNoiseLite.TYPE_SIMPLEX, 1.8, Color(0.07, 0.07, 0.09), Color(0.15, 0.15, 0.18))
	knit.uv1_triplanar = true
	knit.uv1_scale = Vector3.ONE * 5.0
	knit.roughness = 1.0
	var jeans := StandardMaterial3D.new()         # vaquero claro
	jeans.albedo_texture = U._noise_tex("jeans_light", FastNoiseLite.TYPE_SIMPLEX, 1.6, Color(0.5, 0.62, 0.78), Color(0.66, 0.76, 0.88))
	jeans.uv1_triplanar = true
	jeans.uv1_scale = Vector3.ONE * 4.0
	var red := Color(0.8, 0.08, 0.1)
	var black := Color(0.05, 0.05, 0.06)

	# vaqueros anchos con el bajo vuelto y zapatillas blancas con rayas rojas
	for sx in [-1.0, 1.0]:
		var ankle := Vector3(sx * 0.1, 0.13, 0.0)
		leg(model, Vector3(sx * 0.105, 0.9, 0.0), Vector3(sx * 0.11, 0.5, -0.02), ankle, jeans, 1.25)
		U.cylinder(model, 0.085, 0.07, Vector3(ankle.x, 0.2, 0.0), Color(0.72, 0.8, 0.9))     # bajo vuelto
		shoe(model, ankle, Color(0.96, 0.96, 0.95), Color(0.8, 0.65, 0.45))
		for i in 3:
			var st := U.box(model, Vector3(0.006, 0.05, 0.012), Vector3(sx * (0.1 + 0.068), 0.08, -0.04 - i * 0.025), red)
			st.rotation_degrees.x = -25.0
	U.ellipsoid_m(model, Vector3(0.2, 0.13, 0.14), Vector3(0, 0.93, 0), jeans)

	# jersey negro de cuello alto
	U.torso(model, 1.04, 1.43, 0.2, 0.14, knit)
	U.cone_m(model, 0.085, 0.1, 0.12, Vector3(0, 1.5, 0.005), knit)
	# bolso negro cruzado: correa por el pecho y el bolso a la cadera
	U.limb(model, Vector3(-0.15, 1.46, -0.1), Vector3(0.0, 1.24, -0.17), 0.012, 0.012, black)
	U.limb(model, Vector3(0.0, 1.24, -0.17), Vector3(0.16, 0.98, -0.17), 0.012, 0.012, black)
	var bag := Node3D.new()
	bag.position = Vector3(0.18, 0.95, -0.17)
	model.add_child(bag)
	var bb := U.ellipsoid(bag, Vector3(0.11, 0.08, 0.05), Vector3.ZERO, black)
	bb.material_override.roughness = 0.4
	U.box(bag, Vector3(0.12, 0.012, 0.004), Vector3(0, 0.03, -0.05), Color(0.6, 0.6, 0.62))   # cremallera

	# brazo izquierdo relajado; el derecho en un pivote para dar bolsazos
	arm(model, Vector3(-0.21, 1.42, 0.0), Vector3(-0.26, 1.15, 0.03), Vector3(-0.22, 0.92, -0.06), knit, knit, skin_c, 0.95, -1.0)
	var arm_p := Node3D.new()
	arm_p.position = Vector3(0.21, 1.42, 0.0)
	model.add_child(arm_p)
	arm(arm_p, Vector3.ZERO, Vector3(0.05, -0.27, 0.03), Vector3(0.02, -0.5, -0.06), knit, knit, skin_c, 0.95, 1.0)

	# cabeza: gesto serio, pelo rizado recogido atrás y gafas redondas finas
	var r := 0.205
	var hp := human_head(model, Vector3(0, 1.7, -0.01), r, skin_c, "seria", hair)
	var head: Node3D = hp["head"]
	var cap := U.sphere(head, 1.04 * r, Vector3(0, 0.12 * r, 0.08 * r), hair)
	cap.scale = Vector3(0.99, 0.95, 1.02)
	for i in 7:                                                                  # rizos del recogido
		var a := i * TAU / 7.0
		U.sphere(head, 0.3 * r, Vector3(cos(a) * 0.36 * r, -0.42 * r + sin(a) * 0.3 * r, 1.0 * r), hair)
	U.sphere(head, 0.36 * r, Vector3(0, -0.42 * r, 1.12 * r), hair)
	var gold := U.mat(Color(0.85, 0.65, 0.45))
	gold.metallic = 0.7
	for sx in [-1.0, 1.0]:
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.27 * r
		tm.outer_radius = 0.295 * r
		ring.mesh = tm
		ring.scale = Vector3(1.0, 0.35, 1.0)
		ring.material_override = gold
		ring.position = Vector3(sx * 0.36 * r, 0.1 * r, -0.99 * r)
		ring.rotation_degrees.x = 90.0
		head.add_child(ring)
		U.box_m(head, Vector3(0.025 * r, 0.025 * r, 1.0 * r), Vector3(sx * 0.68 * r, 0.14 * r, -0.5 * r), gold)   # patillas
		for i in 3:                                                              # tres aros en la oreja
			var hoop := MeshInstance3D.new()
			var hm := TorusMesh.new()
			hm.inner_radius = 0.075 * r
			hm.outer_radius = 0.1 * r
			hoop.mesh = hm
			hoop.material_override = gold
			hoop.position = Vector3(sx * 1.02 * r, (-0.24 + i * 0.03) * r, (-0.04 + i * 0.07) * r)
			hoop.rotation_degrees.z = 90.0
			head.add_child(hoop)
	U.box_m(head, Vector3(0.17 * r, 0.025 * r, 0.025 * r), Vector3(0, 0.14 * r, -1.0 * r), gold)

	# sombrero de bruja: ala negra ancha un poco caída hacia delante, copa
	# arrugada de encaje con la punta hacia arriba y flecos rojos en el ala
	var lace := lace_material()
	var red_m := U.mat(red)
	var hat := Node3D.new()
	hat.position = Vector3(0, 0.62 * r, 0.02)
	hat.rotation_degrees.x = -8.0
	head.add_child(hat)
	U.cone(hat, 0.2, 0.35, 0.025, Vector3.ZERO, Color(0.04, 0.04, 0.05))
	U.cone_m(hat, 0.2, 0.235, 0.05, Vector3(0, 0.035, 0), red_m)
	U.cone_m(hat, 0.145, 0.205, 0.16, Vector3(0, 0.13, 0), lace)
	U.limb_m(hat, Vector3(0.012, 0.2, -0.008), Vector3(-0.022, 0.33, 0.018), 0.137, 0.104, lace)   # arruga
	U.limb_m(hat, Vector3(-0.022, 0.33, 0.018), Vector3(0.008, 0.66, 0.03), 0.104, 0.006, lace)
	for i in 28:                                                                 # flecos del ala
		var a := i * TAU / 28.0
		var fr := U.box_m(hat, Vector3(0.012, 0.008, 0.03 + 0.04 * absf(sin(i * 2.3))), Vector3(sin(a) * 0.35, -0.012, cos(a) * 0.35), red_m)
		fr.rotation.y = a

	U.toonify(model, 0.01)
	gold.next_pass = null                                                        # sin contorno: las gafas son muy finas
	return {"model": model, "head": head, "arm": arm_p, "bag": bag}


# ---------------------------------------------------------------
# Ian (fotos juan/ian.jpg e ian1.jpeg): grandote, cara redonda con papada,
# pelo moreno rizado y despeinado, gafas grandes de pasta gris, bigote fino
# y barba de unos días. Camiseta negra con una sonrisa de dientes blanca
# ("Only in your smile I breathe"), vaqueros negros rotos, tatuaje en el
# antebrazo y el móvil en la mano. Devuelve {"model", "head", "belly"}.
# ---------------------------------------------------------------
static func build_ian(parent: Node) -> Dictionary:
	var model := Node3D.new()
	model.scale = Vector3.ONE * 1.04
	parent.add_child(model)
	var skin_c := Color(0.93, 0.76, 0.64)
	var hair := Color(0.1, 0.07, 0.05)
	var tee_m := StandardMaterial3D.new()
	tee_m.albedo_texture = U._noise_tex("hoodie_black", FastNoiseLite.TYPE_SIMPLEX, 0.9, Color(0.04, 0.04, 0.05), Color(0.11, 0.11, 0.12))
	tee_m.uv1_triplanar = true
	tee_m.uv1_scale = Vector3.ONE * 5.0
	var jeans := StandardMaterial3D.new()
	jeans.albedo_texture = U._noise_tex("jeans_black", FastNoiseLite.TYPE_SIMPLEX, 1.6, Color(0.05, 0.05, 0.06), Color(0.14, 0.14, 0.16))
	jeans.uv1_triplanar = true
	jeans.uv1_scale = Vector3.ONE * 4.0
	var white := Color(0.95, 0.95, 0.93)

	# vaqueros negros rotos (rodillas con rotos grises) y zapatillas negras
	for sx in [-1.0, 1.0]:
		var ankle := Vector3(sx * 0.12, 0.13, 0.0)
		leg(model, Vector3(sx * 0.13, 0.9, 0.0), Vector3(sx * 0.13, 0.5, -0.03), ankle, jeans, 1.35)
		shoe(model, ankle, Color(0.07, 0.07, 0.08), Color(0.9, 0.9, 0.9), 1.1)
		for i in 3:
			var rip := U.box(model, Vector3(0.07, 0.008, 0.01), Vector3(ankle.x + sx * 0.01, 0.52 + i * 0.03, -0.135), Color(0.55, 0.55, 0.57))
			rip.rotation_degrees.z = randf_range(-12.0, 12.0)
	U.ellipsoid_m(model, Vector3(0.25, 0.15, 0.17), Vector3(0, 0.93, 0), jeans)

	# camiseta negra holgada con barriga
	U.torso(model, 1.04, 1.45, 0.28, 0.19, tee_m, 0.07)
	var belly := U.ellipsoid_m(model, Vector3(0.25, 0.22, 0.2), Vector3(0, 1.1, -0.04), tee_m)
	var collar := U.cylinder(model, 0.1, 0.03, Vector3(0, 1.55, -0.01), Color(0.03, 0.03, 0.035))
	collar.scale.z = 0.9
	# estampado: sonrisa enorme de dientes blancos (como la de la camiseta)
	var grin := Node3D.new()
	grin.position = Vector3(-0.03, 1.33, -0.215)
	model.add_child(grin)
	U.ellipsoid(grin, Vector3(0.12, 0.065, 0.006), Vector3.ZERO, white)
	for i in 7:                                                              # huecos entre dientes
		var gx := -0.09 + i * 0.03
		U.box(grin, Vector3(0.009, 0.075 - absf(gx) * 0.35, 0.004), Vector3(gx, 0.0, -0.006), Color(0.04, 0.04, 0.05))
	U.box(grin, Vector3(0.22, 0.01, 0.004), Vector3(0, 0.0, -0.006), Color(0.04, 0.04, 0.05))    # línea de la boca
	for i in 3:                                                              # gotas que chorrean
		U.ellipsoid(grin, Vector3(0.008, 0.02, 0.004), Vector3(-0.05 + i * 0.05, -0.08 - (i % 2) * 0.015, 0.0), white)
	var txt := Label3D.new()
	txt.text = "Only\nin\nyour\nsmile\nI breathe"
	txt.font_size = 26
	txt.pixel_size = 0.0018
	txt.outline_size = 0
	txt.modulate = white
	txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	txt.position = Vector3(0.15, 1.06, -0.262)
	txt.rotation_degrees.y = 180.0
	model.add_child(txt)

	# brazos con manga corta (antebrazos gorditos); tatuaje en el derecho
	var tee_dark := Color(0.06, 0.06, 0.07)
	arm(model, Vector3(-0.29, 1.43, 0.0), Vector3(-0.35, 1.16, 0.03), Vector3(-0.31, 0.92, -0.06), tee_m, U.mat(skin_c), skin_c, 1.25, -1.0)
	arm(model, Vector3(0.29, 1.43, 0.0), Vector3(0.36, 1.18, -0.06), Vector3(0.18, 1.3, -0.3), tee_m, U.mat(skin_c), skin_c, 1.25, 1.0)
	for sx in [-1.0, 1.0]:
		U.limb(model, Vector3(sx * 0.29, 1.42, 0.0), Vector3(sx * 0.34, 1.27, 0.0), 0.095, 0.09, tee_dark)   # manga
	for i in 3:
		var tat := U.box(model, Vector3(0.05, 0.005, 0.004), Vector3(0.28 - i * 0.025, 1.24 + i * 0.015, -0.2 + i * 0.01), Color(0.15, 0.15, 0.2))
		tat.rotation_degrees.y = 35.0
	# móvil negro con las cámaras (como en el selfie)
	var phone := Node3D.new()
	phone.position = Vector3(0.15, 1.38, -0.36)
	phone.rotation_degrees = Vector3(-10.0, 25.0, 0.0)
	model.add_child(phone)
	U.box(phone, Vector3(0.08, 0.16, 0.012), Vector3.ZERO, Color(0.08, 0.08, 0.1))
	for i in 3:
		var lens := U.cylinder(phone, 0.011, 0.006, Vector3(-0.02 + (i % 2) * 0.02, 0.05 - (i / 2) * 0.02, -0.008), Color(0.02, 0.02, 0.02))
		lens.rotation_degrees.x = 90.0

	# cabeza redonda con papada, pelo rizado despeinado y gafas grandes
	var r := 0.225
	var hp := human_head(model, Vector3(0, 1.76, -0.01), r, skin_c, "player", hair)
	var head: Node3D = hp["head"]
	head.scale = Vector3(1.1, 1.0, 1.05)
	U.ellipsoid(head, Vector3(0.75, 0.38, 0.6) * r, Vector3(0, -0.85 * r, -0.2 * r), skin_c)              # papada
	var stub := U.ellipsoid(head, Vector3(0.62, 0.32, 0.45) * r, Vector3(0, -0.62 * r, -0.36 * r), skin_c.darkened(0.14))
	stub.rotation_degrees.x = -10.0
	U.ellipsoid(head, Vector3(0.26, 0.05, 0.08) * r, Vector3(0, -0.34 * r, -0.9 * r), hair.lightened(0.15))   # bigote fino
	var cap := U.sphere(head, 1.03 * r, Vector3(0, 0.15 * r, 0.06 * r), hair)
	cap.scale = Vector3(1.0, 0.88, 1.0)
	U.ellipsoid(head, Vector3(0.95, 0.75, 0.65) * r, Vector3(0, -0.05 * r, 0.45 * r), hair)                # nuca
	for sx in [-1.0, 1.0]:
		U.ellipsoid(head, Vector3(0.22, 0.5, 0.6) * r, Vector3(sx * 0.86 * r, 0.1 * r, 0.3 * r), hair)    # laterales
	var rng := RandomNumberGenerator.new()
	rng.seed = 404               # siempre los mismos rizos
	for i in 46:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.0, 1), rng.randf_range(-1, 1)).normalized()
		if dir.z < -0.5 and dir.y < 0.45:
			continue             # que no tape la cara
		var cr := rng.randf_range(0.18, 0.28) * r
		var curl := U.ellipsoid(head, Vector3(cr, cr * 0.8, cr * 1.1), Vector3(0, 0.15 * r, 0.06 * r) + dir * 1.02 * r, hair.lightened(rng.randf() * 0.08))
		curl.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, 0.0)
	for i in 4:                  # rizos que caen por la frente
		U.ellipsoid(head, Vector3(0.12, 0.2, 0.08) * r, Vector3((-0.3 + i * 0.2) * r, 0.62 * r, -0.82 * r), hair)
	# gafas grandes rectangulares de pasta gris translúcida
	var fm := U.mat(Color(0.45, 0.45, 0.46, 0.85))
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var ey := 0.1 * r
	var ez := -0.99 * r
	for sx in [-1.0, 1.0]:
		var ex: float = sx * 0.38 * r
		U.box_m(head, Vector3(0.48 * r, 0.06 * r, 0.05 * r), Vector3(ex, ey + 0.2 * r, ez), fm)
		U.box_m(head, Vector3(0.46 * r, 0.05 * r, 0.05 * r), Vector3(ex, ey - 0.18 * r, ez), fm)
		U.box_m(head, Vector3(0.05 * r, 0.42 * r, 0.05 * r), Vector3(ex + sx * 0.23 * r, ey, ez), fm)
		U.box_m(head, Vector3(0.05 * r, 0.4 * r, 0.05 * r), Vector3(ex - sx * 0.21 * r, ey, ez), fm)
		var glass := U.box(head, Vector3(0.44 * r, 0.36 * r, 0.01), Vector3(ex, ey, ez - 0.004), Color(0.8, 0.85, 0.9, 0.12))
		glass.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		U.box_m(head, Vector3(0.04 * r, 0.04 * r, 0.95 * r), Vector3(sx * 0.62 * r, ey + 0.15 * r, -0.52 * r), fm)
	U.box_m(head, Vector3(0.16 * r, 0.05 * r, 0.05 * r), Vector3(0, ey + 0.12 * r, ez), fm)

	U.toonify(model, 0.01)
	return {"model": model, "head": head, "belly": belly}


# ---------------------------------------------------------------
# Iván Muriel (foto juan/ivanmuriel.jpeg): futbolista delgado, pelo castaño
# oscuro con flequillo y degradado, sonrisa, camiseta azul cielo del CF Trujillo
# (cuello en pico y puños blancos, patrocinador "Mercoquadiana"), pantalón
# corto blanco, medias y botas, y tatuajes en el antebrazo derecho.
# Devuelve {"model", "head", "arm_l", "arm_r"} (brazos en pivote para celebrar).
# ---------------------------------------------------------------
static func build_ivan(parent: Node) -> Dictionary:
	var model := Node3D.new()
	parent.add_child(model)
	var skin_c := Color(0.93, 0.76, 0.63)
	var hair := Color(0.12, 0.08, 0.05)
	var sky := Color(0.36, 0.72, 0.92)
	var white := Color(0.96, 0.97, 0.98)
	var jersey := StandardMaterial3D.new()        # tela técnica con un rayado suave
	jersey.albedo_texture = U._noise_tex("jersey_sky", FastNoiseLite.TYPE_SIMPLEX, 3.0, sky.darkened(0.06), sky.lightened(0.06), Vector2(1.0, 4.0))
	jersey.uv1_triplanar = true
	jersey.uv1_scale = Vector3.ONE * 3.0
	jersey.roughness = 0.6
	var shorts_m := U.mat(white)
	var skin_m := U.mat(skin_c)

	# piernas: muslo con el pantalón corto, rodilla al aire, medias y botas
	for sx in [-1.0, 1.0]:
		var ankle := Vector3(sx * 0.1, 0.13, 0.0)
		leg(model, Vector3(sx * 0.11, 0.9, 0.0), Vector3(sx * 0.105, 0.5, -0.03), ankle, skin_m, 0.95)
		U.limb_m(model, Vector3(sx * 0.115, 0.92, 0.0), Vector3(sx * 0.12, 0.62, -0.02), 0.115, 0.1, shorts_m)   # pernera
		U.limb(model, Vector3(sx * 0.105, 0.42, -0.02), Vector3(ankle.x, 0.15, 0.0), 0.08, 0.064, sky)          # media
		U.cylinder(model, 0.082, 0.035, Vector3(sx * 0.105, 0.43, -0.02), white)                               # vuelta de la media
		shoe(model, ankle, Color(0.06, 0.06, 0.07), Color(0.2, 0.2, 0.22))                                     # botas negras
	U.ellipsoid_m(model, Vector3(0.2, 0.13, 0.14), Vector3(0, 0.93, 0), shorts_m)

	# camiseta azul cielo con cuello en pico blanco, escudo, logo y patrocinador
	U.torso(model, 1.0, 1.44, 0.22, 0.14, jersey)
	var hem := U.cylinder(model, 0.205, 0.12, Vector3(0, 0.97, 0), sky)          # bajo de la camiseta por fuera
	hem.scale.z = 0.72
	for sx in [-1.0, 1.0]:
		var v := U.box(model, Vector3(0.015, 0.075, 0.01), Vector3(sx * 0.03, 1.5, -0.13), white)
		v.rotation_degrees.z = sx * 28.0
	var sponsor := Label3D.new()
	sponsor.text = "Mercoquadiana"
	sponsor.font_size = 34
	sponsor.pixel_size = 0.0015
	sponsor.outline_size = 0
	sponsor.modulate = Color(0.96, 0.98, 1.0)
	sponsor.position = Vector3(0.02, 1.25, -0.152)
	sponsor.rotation_degrees.y = 180.0
	model.add_child(sponsor)
	U.box(model, Vector3(0.03, 0.03, 0.006), Vector3(-0.11, 1.25, -0.15), white)                 # logo del patrocinador
	U.ellipsoid(model, Vector3(0.016, 0.02, 0.005), Vector3(0.085, 1.37, -0.147), Color(0.92, 0.95, 1.0))   # escudo
	for sx in [-1.0, 1.0]:                                                                         # logo Macron
		var m := U.box(model, Vector3(0.008, 0.03, 0.005), Vector3(-0.085 + sx * 0.008, 1.37, -0.148), white)
		m.rotation_degrees.z = sx * -25.0

	# brazos en pivote: manga corta azul con puño blanco; tatuajes en el derecho
	var arms := []
	for sx in [-1.0, 1.0]:
		var piv := Node3D.new()
		piv.position = Vector3(sx * 0.22, 1.42, 0.0)
		model.add_child(piv)
		arm(piv, Vector3.ZERO, Vector3(sx * 0.05, -0.27, 0.03), Vector3(sx * 0.03, -0.52, -0.04), jersey, skin_m, skin_c, 0.92, sx)
		U.limb(piv, Vector3(sx * 0.005, -0.01, 0.0), Vector3(sx * 0.04, -0.17, 0.02), 0.075, 0.068, sky)   # manga
		var cuff := U.cylinder(piv, 0.069, 0.03, Vector3(sx * 0.042, -0.18, 0.02), white)   # puño
		cuff.rotation_degrees.z = sx * 10.0
		arms.append(piv)
	for i in 6:                                                                                     # tatuajes del antebrazo
		var tt := U.box(arms[1], Vector3(0.045, 0.012, 0.004), Vector3(0.045, -0.33 - i * 0.03, -0.035 - i * 0.002), Color(0.12, 0.12, 0.16))
		tt.rotation_degrees = Vector3(0.0, 15.0, (i % 3 - 1) * 25.0)

	# cabeza: sonrisa, pelo castaño oscuro con flequillo y degradado en los lados
	var r := 0.205
	var hp := human_head(model, Vector3(0, 1.72, -0.01), r, skin_c, "player", hair)
	var head: Node3D = hp["head"]
	U.box(head, Vector3(0.34 * r, 0.08 * r, 0.04 * r), Vector3(0, -0.47 * r, -0.925 * r), Color(0.98, 0.97, 0.95))   # dientes
	var top := U.sphere(head, 1.05 * r, Vector3(0, 0.13 * r, 0.04 * r), hair)
	top.scale = Vector3(1.0, 0.95, 1.02)
	for i in 7:                                                              # flequillo de mechones
		var fx := (-0.48 + i * 0.16) * r
		var lk := U.ellipsoid(head, Vector3(0.13, 0.22, 0.1) * r, Vector3(fx, 0.5 * r, -0.86 * r), hair)
		lk.rotation_degrees = Vector3(-25.0, 0.0, (i - 3) * -6.0)
	for sx in [-1.0, 1.0]:                                                   # degradado: lados cortos y más claros
		U.ellipsoid(head, Vector3(0.06, 0.3, 0.5) * r, Vector3(sx * 0.93 * r, 0.1 * r, 0.12 * r), hair.lightened(0.2))

	U.toonify(model, 0.01)
	return {"model": model, "head": head, "arm_l": arms[0], "arm_r": arms[1]}


# ---------------------------------------------------------------
# Víctor (foto juan/victor.png): pelo rizado con los lados rapados, gafas
# redondas, cazadora de cuero negra enorme con la capucha blanca asomando,
# pantalón de pana beige muy ancho, zapatillas blancas y móvil naranja.
# Mide 2 metros: saca una cabeza a los jugadores (VICTOR_SCALE).
# Devuelve {"model", "head", "rig"}; lo que roba lo lleva en rig["hand"].
# ---------------------------------------------------------------
static func build_victor(parent: Node, kind: String = "player") -> Dictionary:
	var model := Node3D.new()
	model.scale = Vector3.ONE * VICTOR_SCALE
	parent.add_child(model)
	var skin_c := Color(0.92, 0.75, 0.62)
	var hair := Color(0.1, 0.07, 0.05)
	var leather := Color(0.05, 0.05, 0.055)
	var white := Color(0.95, 0.95, 0.93)
	var pana_c := Color(0.66, 0.58, 0.42)
	var pana := StandardMaterial3D.new()          # pana: rayitas verticales
	pana.albedo_texture = U._noise_tex("pana", FastNoiseLite.TYPE_SIMPLEX, 3.0, pana_c.darkened(0.2), pana_c.lightened(0.1), Vector2(6.0, 1.0))
	pana.uv1_triplanar = true
	pana.uv1_scale = Vector3.ONE * 3.0
	var leather_m := U.mat(leather)

	# pantalón ancho que cae recto hasta taparle media zapatilla
	var legs := []
	for sx in [-1.0, 1.0]:
		var ankle := Vector3(sx * 0.15, 0.13, 0.0)
		var knee := Vector3(sx * 0.14, 0.5, -0.02)
		var lg := leg_rig(model, Vector3(sx * 0.125, 0.92, 0.0), knee, ankle, pana, 1.15)
		U.limb_m(lg["thigh"], Vector3(sx * 0.13, 0.92, 0.0), knee, 0.135, 0.115, pana)
		U.limb_m(lg["shin"], knee, Vector3(sx * 0.15, 0.17, 0.0), 0.115, 0.125, pana)
		shoe(lg["shin"], ankle, white, Color(0.72, 0.72, 0.7), 1.35)
		legs.append(lg)
	U.ellipsoid_m(model, Vector3(0.23, 0.15, 0.16), Vector3(0, 0.95, 0), pana)
	var root := model                  # de aquí para arriba todo se inclina con el tronco
	model = pivot(root, Vector3(0, 0.95, 0))

	# bajo de la camiseta blanca por debajo de la cazadora
	var tee := U.cylinder(model, 0.232, 0.11, Vector3(0, 0.99, 0), white)
	tee.scale.z = 0.76

	# cazadora de cuero enorme, abierta, con la goma de la cintura
	U.torso(model, 1.03, 1.45, 0.27, 0.19, leather_m, 0.02)
	var goma := U.cylinder(model, 0.262, 0.08, Vector3(0, 1.05, 0), leather.lightened(0.07))
	goma.scale.z = 0.78
	U.ellipsoid(model, Vector3(0.07, 0.2, 0.03), Vector3(0, 1.3, -0.183), white)                  # sudadera blanca
	for sx in [-1.0, 1.0]:
		var lap := U.box_m(model, Vector3(0.075, 0.42, 0.035), Vector3(sx * 0.09, 1.27, -0.19), leather_m)
		lap.rotation_degrees.z = sx * -7.0
		var collar := U.ellipsoid_m(model, Vector3(0.1, 0.05, 0.11), Vector3(sx * 0.1, 1.5, -0.08), leather_m)
		collar.rotation_degrees = Vector3(20.0, 0.0, sx * -22.0)
		for i in 3:                                                                                # brillos del cuero
			var fold := U.ellipsoid(model, Vector3(0.09, 0.014, 0.012), Vector3(sx * 0.17, 1.14 + i * 0.09, -0.15), leather.lightened(0.22))
			fold.rotation_degrees.z = sx * (14.0 - i * 9.0)
		U.box(model, Vector3(0.09, 0.012, 0.012), Vector3(sx * 0.17, 1.1, -0.197), leather.lightened(0.18))   # bolsillos
	var hood := U.ellipsoid(model, Vector3(0.2, 0.13, 0.13), Vector3(0, 1.53, 0.09), white)       # capucha blanca
	hood.rotation_degrees.x = -18.0
	U.cylinder(model, 0.105, 0.07, Vector3(0, 1.55, -0.01), white)

	# mangas enormes; en la izquierda el móvil naranja de la foto
	var arm_r := arm_rig(model, Vector3(0.26, 1.41, 0.0), Vector3(0.31, 1.13, 0.02), Vector3(0.29, 0.9, -0.05), leather_m, leather_m, skin_c, 1.15, 1.0)
	var arm_l := arm_rig(model, Vector3(-0.26, 1.41, 0.0), Vector3(-0.31, 1.13, 0.02), Vector3(-0.29, 0.9, -0.05), leather_m, leather_m, skin_c, 1.15, -1.0)
	var phone := U.box(arm_l, Vector3(0.085, 0.17, 0.014), Vector3(-0.29, 0.8, -0.13), Color(0.96, 0.46, 0.1))
	phone.rotation_degrees.x = 12.0
	U.box(arm_l, Vector3(0.03, 0.03, 0.006), Vector3(-0.31, 0.85, -0.145), Color(0.1, 0.1, 0.11))

	# cabeza: rizos solo arriba, lados rapados y gafas redondas
	var r := 0.205
	var hp := human_head(model, Vector3(0, 1.75, -0.01), r, skin_c, kind, hair)
	var head: Node3D = hp["head"]
	var fades := []
	for sx in [-1.0, 1.0]:
		fades.append(U.ellipsoid(head, Vector3(0.05, 0.4, 0.62) * r, Vector3(sx * 0.9 * r, 0.12 * r, 0.1 * r), skin_c.lerp(hair, 0.65)))
	var cap := U.sphere(head, 1.02 * r, Vector3(0, 0.36 * r, 0.1 * r), hair)
	cap.scale = Vector3(0.92, 0.82, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1712           # siempre los mismos rizos
	var placed := 0
	while placed < 70:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.1, 1), rng.randf_range(-1, 1)).normalized()
		if dir.z < -0.8 and dir.y < 0.45:
			continue           # la frente queda despejada
		placed += 1
		var cr := rng.randf_range(0.032, 0.05)
		var curl := U.ellipsoid(head, Vector3(cr, cr * rng.randf_range(0.7, 1.15), cr * rng.randf_range(0.8, 1.2)),
			Vector3(0, 0.3 * r, 0.05 * r) + dir * rng.randf_range(0.93, 1.1) * r, hair.lightened(rng.randf_range(0.0, 0.1)))
		curl.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, 0.0)
	var frame := Color(0.08, 0.08, 0.09)
	var ey := 0.03
	var ez := -0.205
	for sx in [-1.0, 1.0]:
		var ex: float = sx * 0.078
		for i in 14:                                       # aro redondo
			var a := i * TAU / 14.0
			var seg := U.box(head, Vector3(0.022, 0.008, 0.008), Vector3(ex + cos(a) * 0.05, ey + sin(a) * 0.05, ez), frame)
			seg.rotation.z = a + PI * 0.5
		U.box(head, Vector3(0.007, 0.007, 0.2), Vector3(sx * 0.128, ey + 0.015, -0.1), frame)     # patillas
	U.box(head, Vector3(0.03, 0.007, 0.007), Vector3(0, ey + 0.015, ez), frame)                   # puente

	U.toonify(root, 0.01)
	for f in fades:                          # tan planos, el contorno se deforma
		f.material_override.next_pass = null
	leather_m.roughness = 0.3                # el cuero brilla
	leather_m.metallic = 0.15
	return {"model": root, "head": head, "rig": make_rig(model, legs, arm_l, arm_r, head)}


# Lo robado, tal como se ve en la mano de Víctor o tirado en el suelo
static func build_loot(parent: Node3D, item: Dictionary) -> Node3D:
	var n := Node3D.new()
	parent.add_child(n)
	match str(item["k"]):
		"arma":
			n.add_child(U.gun_model(str(item["w"]["id"])))
		"jan":
			var mini := Node3D.new()
			mini.scale = Vector3.ONE * 0.09
			mini.position.y = -0.08
			n.add_child(mini)
			build_jan(mini)
		"cafe":
			U.cylinder(n, 0.05, 0.13, Vector3.ZERO, Color(0.95, 0.93, 0.9))
			U.cylinder(n, 0.053, 0.03, Vector3(0, 0.07, 0), Color(0.3, 0.17, 0.09))
		"porro":
			var p := U.limb(n, Vector3(-0.09, 0, 0), Vector3(0.09, 0, 0), 0.014, 0.022, Color(0.95, 0.93, 0.88))
			p.rotation_degrees.z += 8.0
			U.sphere(n, 0.018, Vector3(0.1, 0.012, 0), Color(1.0, 0.45, 0.1), true)
		"gta":
			U.box(n, Vector3(0.14, 0.19, 0.015), Vector3.ZERO, Color(0.95, 0.35, 0.65))
			U.box(n, Vector3(0.11, 0.06, 0.003), Vector3(0, -0.05, -0.009), Color(0.1, 0.1, 0.13))
		_:      # la cartera con los puntos
			U.box(n, Vector3(0.17, 0.11, 0.035), Vector3.ZERO, Color(0.32, 0.18, 0.1))
			U.box(n, Vector3(0.14, 0.04, 0.038), Vector3(0, 0.03, 0), Color(0.45, 0.75, 0.45))
	U.toonify(n, 0.006)
	return n

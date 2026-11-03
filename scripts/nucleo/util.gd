# Utilidades para construir mallas, materiales, sonidos y rutas por código

static var _camo: StandardMaterial3D
static var _tex_cache := {}


static var _outlines := {}


static func mat(c: Color, emit: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.75
	# Sombreado realista (los personajes se pasan a cartoon con toonify)
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
	if emit:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 2.0
	return m


static func box(parent: Node, size: Vector3, pos: Vector3, c: Color, emit: bool = false) -> MeshInstance3D:
	return box_m(parent, size, pos, mat(c, emit))


static func box_m(parent: Node, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


static func sphere(parent: Node, radius: float, pos: Vector3, c: Color, emit: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	mi.mesh = m
	mi.material_override = mat(c, emit)
	mi.position = pos
	parent.add_child(mi)
	return mi


static func capsule(parent: Node, radius: float, height: float, pos: Vector3, c: Color) -> MeshInstance3D:
	return capsule_m(parent, radius, height, pos, mat(c))


static func capsule_m(parent: Node, radius: float, height: float, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = radius
	cm.height = height
	mi.mesh = cm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


static func cylinder(parent: Node, radius: float, height: float, pos: Vector3, c: Color, emit: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	mi.mesh = cm
	mi.material_override = mat(c, emit)
	mi.position = pos
	parent.add_child(mi)
	return mi


static func cone(parent: Node, r_top: float, r_bot: float, height: float, pos: Vector3, c: Color, emit: bool = false) -> MeshInstance3D:
	return cone_m(parent, r_top, r_bot, height, pos, mat(c, emit))


static func cone_m(parent: Node, r_top: float, r_bot: float, height: float, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = height
	cm.radial_segments = 20
	mi.mesh = cm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


# Cilindro a lo largo del eje Z (cañones, miras, cargadores...)
static func tube(parent: Node, radius: float, length: float, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := cone_m(parent, radius, radius, length, pos, m)
	mi.rotation_degrees.x = 90.0
	return mi


# Esfera deformada (músculos, barriga, mejillas...)
static func ellipsoid(parent: Node, radii: Vector3, pos: Vector3, c: Color) -> MeshInstance3D:
	return ellipsoid_m(parent, radii, pos, mat(c))


static func ellipsoid_m(parent: Node, radii: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radii.x
	sm.height = radii.x * 2.0
	mi.mesh = sm
	mi.material_override = m
	mi.position = pos
	mi.scale = Vector3(1.0, radii.y / radii.x, radii.z / radii.x)
	parent.add_child(mi)
	return mi


# Segmento de extremidad que va del punto a al punto b, más ancho en a que en b
# (muslo, gemelo, brazo, antebrazo). Redondeado en los extremos para que las
# articulaciones encajen sin huecos.
static func limb(parent: Node, a: Vector3, b: Vector3, ra: float, rb: float, c: Color) -> MeshInstance3D:
	return limb_m(parent, a, b, ra, rb, mat(c))


static func limb_m(parent: Node, a: Vector3, b: Vector3, ra: float, rb: float, m: Material) -> MeshInstance3D:
	var l := a.distance_to(b)
	var mi := cone_m(parent, rb, ra, l, (a + b) * 0.5, m)
	var dir := (b - a).normalized()
	# el cilindro apunta hacia +Y (punta fina arriba); lo giramos para que vaya de a a b
	var up := Vector3(0, 1, 0)
	var axis := up.cross(dir)
	if axis.length() < 0.0001:
		if dir.y < 0.0:
			mi.rotation_degrees.x = 180.0
	else:
		mi.basis = Basis(axis.normalized(), up.angle_to(dir))
	var ja := MeshInstance3D.new()
	var sa := SphereMesh.new()
	sa.radius = ra
	sa.height = ra * 2.0
	ja.mesh = sa
	ja.material_override = m
	ja.position = a
	parent.add_child(ja)
	var jb := MeshInstance3D.new()
	var sb := SphereMesh.new()
	sb.radius = rb
	sb.height = rb * 2.0
	jb.mesh = sb
	jb.material_override = m
	jb.position = b
	parent.add_child(jb)
	return mi


# Mano con palma y dedos curvados (agarrando). fwd = hacia donde apuntan los dedos.
static func hand(parent: Node, pos: Vector3, c: Color, size: float = 1.0, fwd: Vector3 = Vector3(0, 0, -1), side: float = 1.0) -> Node3D:
	var h := Node3D.new()
	h.position = pos
	parent.add_child(h)
	var f := fwd.normalized()
	if f != Vector3(0, 0, -1):
		h.basis = Basis.looking_at(f, Vector3.UP if absf(f.y) < 0.95 else Vector3(0, 0, -1))
	h.scale = Vector3.ONE * size
	var m := mat(c)
	ellipsoid_m(h, Vector3(0.045, 0.028, 0.05), Vector3.ZERO, m)          # palma
	for i in 4:
		var fx := (-0.027 + i * 0.018)
		limb_m(h, Vector3(fx, 0.0, -0.04), Vector3(fx, -0.022, -0.075), 0.011, 0.009, m)
	limb_m(h, Vector3(side * 0.04, 0.0, 0.0), Vector3(side * 0.055, -0.02, -0.04), 0.012, 0.01, m)   # pulgar
	return h


# Torso humano: pecho ancho, cintura estrecha y cadera (y = altura de la cintura)
static func torso(parent: Node, waist_y: float, chest_y: float, w: float, depth: float, m: Material, belly: float = 0.0) -> void:
	var h := chest_y - waist_y
	var mid := cone_m(parent, w * 0.9, w * 0.72, h, Vector3(0, waist_y + h * 0.5, 0), m)
	mid.scale.z = depth / w
	ellipsoid_m(parent, Vector3(w * 1.02, h * 0.34, depth * 1.0), Vector3(0, chest_y - h * 0.24, 0), m)      # pecho/hombros
	ellipsoid_m(parent, Vector3(w * 0.78, h * 0.32, depth * 0.95), Vector3(0, waist_y, 0), m)                  # cadera
	if belly > 0.0:
		ellipsoid_m(parent, Vector3(w * 0.8 + belly, h * 0.38 + belly * 0.5, depth * 0.8 + belly), Vector3(0, waist_y + h * 0.3, -belly * 0.4), m)


# ---------- Texturas procedurales ----------
static func _noise_tex(key: String, ntype: int, freq: float, c0: Color, c1: Color, stretch: Vector2 = Vector2.ONE) -> NoiseTexture2D:
	if _tex_cache.has(key):
		return _tex_cache[key]
	var noise := FastNoiseLite.new()
	noise.noise_type = ntype
	noise.frequency = freq
	noise.fractal_octaves = 4
	var g := Gradient.new()
	g.set_color(0, c0)
	g.set_color(1, c1)
	var tex := NoiseTexture2D.new()
	tex.width = int(256 * stretch.x)
	tex.height = int(256 * stretch.y)
	tex.seamless = true
	tex.noise = noise
	tex.color_ramp = g
	_tex_cache[key] = tex
	return tex


# Metal pavonado de arma: casi negro con un leve granulado y brillo metálico
static func gunmetal(tint: Color = Color(0.13, 0.13, 0.15)) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _noise_tex("metal", FastNoiseLite.TYPE_SIMPLEX, 0.35, Color(0.7, 0.7, 0.72), Color(1.0, 1.0, 1.0))
	m.albedo_color = tint
	m.metallic = 0.75
	m.roughness = 0.35
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 2.0
	return m


# Madera con vetas alargadas a lo largo del arma
static func wood_mat(base: Color = Color(0.42, 0.24, 0.1)) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _noise_tex("wood", FastNoiseLite.TYPE_PERLIN, 0.08, base.darkened(0.45), base.lightened(0.18), Vector2(0.25, 2.0))
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(3.0, 3.0, 0.4)
	m.roughness = 0.6
	return m


# Polímero mate (empuñaduras, guardamanos)
static func polymer(c: Color = Color(0.09, 0.09, 0.1)) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _noise_tex("poly", FastNoiseLite.TYPE_CELLULAR, 1.6, Color(0.8, 0.8, 0.8), Color(1.1, 1.1, 1.1))
	m.albedo_color = c
	m.roughness = 0.85
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 4.0
	return m


static func solid_box(parent: Node, size: Vector3, pos: Vector3, c: Color, visible_mesh: bool = true) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.position = pos
	parent.add_child(sb)
	if visible_mesh:
		box(sb, size, Vector3.ZERO, c)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	sb.add_child(cs)
	return sb


# Hace brillar un poco una superficie (suelos pulidos: reflejan las luces)
static func shiny(body: Node, rough: float, metal: float = 0.0) -> void:
	for ch in body.get_children():
		if ch is MeshInstance3D:
			ch.material_override.roughness = rough
			ch.material_override.metallic = metal


# Camuflaje militar (manchas verdes, marrones y negras) generado con ruido
static func camo_material() -> StandardMaterial3D:
	if _camo != null:
		return _camo
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.02
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	g.set_color(0, Color(0.16, 0.22, 0.1))
	g.set_color(1, Color(0.07, 0.08, 0.06))
	g.add_point(0.4, Color(0.35, 0.4, 0.2))
	g.add_point(0.58, Color(0.42, 0.32, 0.18))
	g.add_point(0.78, Color(0.07, 0.08, 0.06))
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	tex.color_ramp = g
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE
	m.roughness = 0.9
	_camo = m
	return m


# Sonido de disparo generado por código (low = grave, si no seco/chasquido)
static func make_shot(dur: float, low: bool) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var prev := 0.0
	var decay := 30.0
	if low:
		decay = 12.0
	for i in n:
		var tt := float(i) / rate
		var s := randf() * 2.0 - 1.0
		if low:
			prev = lerpf(prev, s, 0.25)
			s = prev * 2.5
		s *= exp(-tt * decay)
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 30000.0))
	return _wav(data, rate)


static func _wav(data: PackedByteArray, rate: int) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w


# "Clic-clac" del obturador de una cámara de móvil
static func make_shutter() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.16)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var tt := float(i) / rate
		var s := 0.0
		for c in [0.0, 0.09]:          # dos chasquidos
			if tt >= c:
				s += (randf() * 2.0 - 1.0) * exp(-(tt - c) * 90.0)
		data.encode_s16(i * 2, int(clampf(s * 0.8, -1.0, 1.0) * 30000.0))
	return _wav(data, rate)


# Destello de la calva de Jan: "¡TIIING!" brillante + petardazo
static func make_ting() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 1.4)
	var data := PackedByteArray()
	data.resize(n * 2)
	var prev := 0.0
	for i in n:
		var tt := float(i) / rate
		var ting := (sin(TAU * 2600.0 * tt) + 0.6 * sin(TAU * 3900.0 * tt) + 0.3 * sin(TAU * 5200.0 * tt)) * exp(-tt * 3.0) * 0.35
		prev = lerpf(prev, randf() * 2.0 - 1.0, 0.3)
		var bang := prev * 3.0 * exp(-tt * 9.0)
		data.encode_s16(i * 2, int(clampf(ting + bang, -1.0, 1.0) * 30000.0))
	return _wav(data, rate)


# Guitarra de Juan Carlos: arpegios Lam - Fa - Do - Sol con cuerda pulsada
# (Karplus-Strong), en bucle
static func make_guitar_loop() -> AudioStreamWAV:
	var rate := 22050
	var beat := 0.28
	var chords := [[110.0, 164.81, 220.0, 261.63, 329.63, 261.63, 220.0, 164.81],
		[87.31, 130.81, 174.61, 220.0, 261.63, 220.0, 174.61, 130.81],
		[130.81, 196.0, 261.63, 329.63, 392.0, 329.63, 261.63, 196.0],
		[98.0, 146.83, 196.0, 246.94, 293.66, 246.94, 196.0, 146.83]]
	var n := int(rate * beat * 32)
	var mix := PackedFloat32Array()
	mix.resize(n)
	var step := int(rate * beat)
	var k := 0
	for ch in chords:
		for f in ch:
			var start: int = k * step
			k += 1
			var period := int(rate / f)
			var buf := PackedFloat32Array()
			buf.resize(period)
			for i in period:
				buf[i] = randf() * 2.0 - 1.0
			var length := mini(int(rate * 1.6), n - start)
			for i in length:
				var j := i % period
				var nx := (j + 1) % period
				var v := buf[j]
				buf[j] = (v + buf[nx]) * 0.5 * 0.996
				mix[start + i] += v * 0.3
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(mix[i], -1.0, 1.0) * 30000.0))
	var w := _wav(data, rate)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = n
	return w


# Ruido de interferencia digital (al empezar el hackeo)
static func make_static(dur: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var hold := 0.0
	for i in n:
		if i % int(randf_range(2, 40)) == 0:
			hold = randf() * 2.0 - 1.0      # ruido "a escalones", suena a datos rotos
		var s := hold * 0.5 * (1.0 - float(i) / n)
		data.encode_s16(i * 2, int(s * 30000.0))
	return _wav(data, rate)


# "¡Ka-ching!" de caja registradora al comprar en la tienda
static func make_kaching() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.7)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var tt := float(i) / rate
		var s := (randf() * 2.0 - 1.0) * exp(-tt * 60.0) * 0.6          # "ka" (cajón)
		if tt > 0.08:
			var k := tt - 0.08                                            # "ching" (campanita)
			s += (sin(TAU * 2093.0 * k) + 0.6 * sin(TAU * 3136.0 * k) + 0.3 * sin(TAU * 4186.0 * k)) * exp(-k * 5.0) * 0.3
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 30000.0))
	return _wav(data, rate)


# Jingle de power-up: arpegio rápido hacia arriba con brillo
static func make_powerup() -> AudioStreamWAV:
	var rate := 22050
	var notes := [523.25, 659.25, 783.99, 1046.5, 1318.5]
	var step := 0.07
	var n := int(rate * (step * notes.size() + 0.6))
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var tt := float(i) / rate
		var s := 0.0
		for k in notes.size():
			var t0: float = k * step
			if tt >= t0:
				var d := tt - t0
				s += (sin(TAU * notes[k] * d) + 0.4 * sin(TAU * notes[k] * 2.0 * d)) * exp(-d * 4.0) * 0.18
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 30000.0))
	return _wav(data, rate)


# Público del estadio celebrando un gol: ruido que sube y baja ("¡uuuooooh!")
static func make_crowd() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 2.6)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var tt := float(i) / rate
		lp = lerpf(lp, randf() * 2.0 - 1.0, 0.12)
		lp2 = lerpf(lp2, lp, 0.3)
		var env := clampf(tt / 0.35, 0.0, 1.0) * clampf((2.6 - tt) / 1.4, 0.0, 1.0)
		var roar := lp2 * 3.2 * (1.0 + 0.25 * sin(TAU * 3.0 * tt))
		data.encode_s16(i * 2, int(clampf(roar * env * 0.7, -1.0, 1.0) * 30000.0))
	return _wav(data, rate)


# Pitido corto de terminal (onda cuadrada)
static func make_beep(freq: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.035)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var s := (1.0 if fmod(float(i) / rate * freq, 1.0) < 0.5 else -1.0) * 0.18
		data.encode_s16(i * 2, int(s * 30000.0))
	return _wav(data, rate)


# Risa malvada "ja-ja-ja-ja": golpes de voz grave con vocal "a"
# pitch > 1 = risita más aguda y rápida (la de Isabella)
static func make_laugh(pitch := 1.0) -> AudioStreamWAV:
	var rate := 22050
	var dur := 2.2 / pitch
	var beat := 0.27 / sqrt(pitch)
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var tt := float(i) / rate
		var k := fmod(tt, beat) / beat             # posición dentro de cada "ja"
		var env := sin(clampf(k / 0.7, 0.0, 1.0) * PI) * (1.0 - tt / (dur * 1.1))
		var f0 := (150.0 - tt * 20.0) * pitch
		var ph := fmod(tt * f0, 1.0)
		var src := ph * 2.0 - 1.0                  # diente de sierra (cuerdas vocales)
		var fm := sqrt(pitch)
		var vowel := sin(TAU * 750.0 * fm * tt) * 0.5 + sin(TAU * 1200.0 * fm * tt) * 0.3   # formantes de la "a"
		var breath := (randf() * 2.0 - 1.0) * 0.25 * (1.0 if k < 0.15 else 0.0)  # la "j"
		var s := (src * (0.6 + 0.4 * vowel) + breath) * env * 0.5
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 30000.0))
	return _wav(data, rate)


# Pitido en los oídos tras quedarte cegado
static func make_ringing(dur: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var tt := float(i) / rate
		var s := sin(TAU * 3700.0 * tt) * 0.22 * clampf(1.0 - tt / dur, 0.0, 1.0)
		data.encode_s16(i * 2, int(s * 30000.0))
	return _wav(data, rate)


# Modelos de armas (apuntan hacia -Z, como el jugador). Si existe el modelo 3D
# exportado (carpeta "armas y cajas"), se usa ese con el tamaño del de código.
static func gun_model(id: String) -> Node3D:
	var g := _gun_model_code(id)
	var real := imported_model(id, g)
	if real != null:
		g.free()
		return real
	return g


# Archivos exportados de SketchUp: modelos/armas y cajas/<nombre>.glb (o .gltf, .dae, .fbx, .obj)
const MODEL_DIR := "res://modelos/armas y cajas/"
const MODEL_EXTS := ["glb", "gltf", "dae", "fbx", "obj"]
# Giro extra por modelo (grados) si al exportar no queda apuntando hacia -Z
const MODEL_FIX := {}


static func model_path(name: String) -> String:
	for ext in MODEL_EXTS:
		var p: String = MODEL_DIR + name + "." + ext
		if ResourceLoader.exists(p):
			return p
	return ""


# Carga el modelo <name> y lo escala/centra para que ocupe lo mismo que "ref"
# (el eje más largo del modelo pasa a ser el del de referencia). null si no existe.
static func imported_model(name: String, ref: Node3D) -> Node3D:
	var p := model_path(name)
	if p == "":
		return null
	var res = load(p)
	var inst: Node3D
	if res is PackedScene:
		inst = res.instantiate()
	elif res is Mesh:
		inst = MeshInstance3D.new()
		inst.mesh = res
	else:
		return null
	var holder := Node3D.new()
	var pivot := Node3D.new()
	holder.add_child(pivot)
	pivot.add_child(inst)
	pivot.rotation_degrees = MODEL_FIX.get(name, Vector3.ZERO)
	var src := node_aabb(pivot, pivot.transform)
	var dst := node_aabb(ref, Transform3D.IDENTITY)
	if src.size.length() < 0.0001:
		return holder
	# el eje largo del modelo se gira para coincidir con el del de referencia
	# (en las armas es Z: el cañón hacia delante)
	var ls := src.get_longest_axis_index()
	var ld := dst.get_longest_axis_index()
	if ls != ld:
		var other := 3 - ls - ld          # el eje que queda: se gira alrededor de él
		var r := pivot.rotation_degrees
		r[other] += 90.0
		pivot.rotation_degrees = r
	src = node_aabb(pivot, pivot.transform)
	var k := dst.size[dst.get_longest_axis_index()] / src.size[src.get_longest_axis_index()]
	pivot.scale = Vector3.ONE * k
	src = node_aabb(pivot, pivot.transform)
	pivot.position = dst.get_center() - src.get_center()
	return holder


# Caja que envuelve todas las mallas de un nodo (en el espacio de "xf")
static func node_aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	if n is MeshInstance3D and n.mesh != null:
		var a: AABB = xf * n.mesh.get_aabb()
		out = a
		first = false
	for c in n.get_children():
		if c is Node3D:
			var b := node_aabb(c, xf * c.transform)
			if b.size != Vector3.ZERO:
				if first:
					out = b
					first = false
				else:
					out = out.merge(b)
	return out


static func _gun_model_code(id: String) -> Node3D:
	var g := Node3D.new()
	var gm := gunmetal()
	var gm2 := gunmetal(Color(0.22, 0.22, 0.25))     # piezas algo más claras
	var poly := polymer()
	var wd := wood_mat()
	var blk := mat(Color(0.03, 0.03, 0.035))
	match id:
		"pistola":
			box_m(g, Vector3(0.05, 0.062, 0.25), Vector3(0, 0.025, -0.1), gm2)              # corredera
			for i in 5:                                                                     # estrías traseras
				box_m(g, Vector3(0.052, 0.045, 0.006), Vector3(0, 0.03, -i * 0.012), blk)
			box_m(g, Vector3(0.022, 0.02, 0.06), Vector3(0.016, 0.035, -0.09), blk)         # ventana de expulsión
			tube(g, 0.012, 0.02, Vector3(0, 0.02, -0.228), blk)                              # boca del cañón
			box_m(g, Vector3(0.008, 0.012, 0.01), Vector3(0, 0.062, -0.21), gm)              # mira delantera
			box_m(g, Vector3(0.04, 0.012, 0.012), Vector3(0, 0.062, 0.015), gm)              # mira trasera
			box_m(g, Vector3(0.046, 0.035, 0.19), Vector3(0, -0.018, -0.09), poly)           # armazón
			box_m(g, Vector3(0.03, 0.01, 0.06), Vector3(0, -0.04, -0.15), poly)              # raíl
			var grip := box_m(g, Vector3(0.044, 0.13, 0.058), Vector3(0, -0.09, 0.02), poly)
			grip.rotation_degrees.x = -14.0
			box_m(g, Vector3(0.048, 0.014, 0.064), Vector3(0, -0.155, 0.035), gm)            # base del cargador
			box_m(g, Vector3(0.008, 0.006, 0.07), Vector3(0, -0.07, -0.055), poly)           # guardamonte
			box_m(g, Vector3(0.008, 0.035, 0.006), Vector3(0, -0.052, -0.09), poly)
			box_m(g, Vector3(0.006, 0.026, 0.006), Vector3(0, -0.05, -0.05), gm)             # gatillo
		"subfusil":
			box_m(g, Vector3(0.06, 0.085, 0.36), Vector3(0, 0.0, -0.08), gm)                 # cajón
			box_m(g, Vector3(0.015, 0.02, 0.05), Vector3(-0.035, 0.03, -0.2), gm2)           # palanca de carga
			var hg := cone_m(g, 0.036, 0.04, 0.2, Vector3(0, -0.005, -0.33), poly)           # guardamanos
			hg.rotation_degrees.x = 90.0
			for i in 4:
				box_m(g, Vector3(0.082, 0.008, 0.02), Vector3(0, -0.005, -0.27 - i * 0.04), blk)
			tube(g, 0.013, 0.12, Vector3(0, 0.0, -0.48), gm2)                                # cañón
			tube(g, 0.02, 0.03, Vector3(0, 0.0, -0.54), blk)                                 # bocacha
			cone_m(g, 0.012, 0.02, 0.05, Vector3(0, 0.06, -0.38), gm)                        # mira delantera
			tube(g, 0.016, 0.04, Vector3(0, 0.065, 0.06), gm)                                # alza de tambor
			for i in 4:                                                                      # cargador curvo
				var seg := box_m(g, Vector3(0.035, 0.055, 0.05), Vector3(0, -0.07 - i * 0.045, -0.13 - i * i * 0.006), gm2)
				seg.rotation_degrees.x = -i * 8.0
			var grip := box_m(g, Vector3(0.042, 0.13, 0.055), Vector3(0, -0.09, 0.02), poly)
			grip.rotation_degrees.x = -16.0
			box_m(g, Vector3(0.012, 0.008, 0.07), Vector3(0, -0.05, -0.04), gm)
			box_m(g, Vector3(0.006, 0.028, 0.006), Vector3(0, -0.055, -0.04), gm2)
			for sx in [-1.0, 1.0]:                                                           # culata de varillas
				tube(g, 0.007, 0.26, Vector3(sx * 0.026, 0.0, 0.22), gm)
			box_m(g, Vector3(0.07, 0.11, 0.025), Vector3(0, -0.02, 0.35), poly)
		"fusil":
			box_m(g, Vector3(0.062, 0.095, 0.4), Vector3(0, 0.0, -0.05), gm)                 # cajón
			box_m(g, Vector3(0.064, 0.02, 0.36), Vector3(0, 0.055, -0.05), gm2)              # tapa
			box_m(g, Vector3(0.015, 0.018, 0.03), Vector3(0.04, 0.02, -0.1), gm2)            # palanca
			box_m(g, Vector3(0.07, 0.07, 0.28), Vector3(0, -0.01, -0.38), wd)                # guardamanos inferior
			box_m(g, Vector3(0.05, 0.035, 0.22), Vector3(0, 0.05, -0.36), wd)                # guardamanos superior
			tube(g, 0.012, 0.3, Vector3(0, 0.05, -0.62), gm)                                 # tubo de gases
			tube(g, 0.014, 0.42, Vector3(0, 0.0, -0.68), gm)                                 # cañón
			box_m(g, Vector3(0.02, 0.06, 0.03), Vector3(0, 0.04, -0.78), gm)                 # mira delantera
			tube(g, 0.022, 0.07, Vector3(0, 0.0, -0.92), gm2)                                # freno de boca
			box_m(g, Vector3(0.024, 0.02, 0.04), Vector3(0, 0.074, -0.22), gm)               # alza
			for i in 5:                                                                      # cargador curvo
				var seg := box_m(g, Vector3(0.036, 0.05, 0.065), Vector3(0, -0.075 - i * 0.04, -0.14 - i * i * 0.008), gm2)
				seg.rotation_degrees.x = -i * 7.0
			var grip := box_m(g, Vector3(0.042, 0.12, 0.055), Vector3(0, -0.09, 0.12), wd)
			grip.rotation_degrees.x = -18.0
			box_m(g, Vector3(0.012, 0.008, 0.08), Vector3(0, -0.055, 0.06), gm)
			box_m(g, Vector3(0.006, 0.03, 0.006), Vector3(0, -0.06, 0.06), gm2)
			var st := box_m(g, Vector3(0.05, 0.09, 0.34), Vector3(0, -0.035, 0.32), wd)      # culata
			st.rotation_degrees.x = 8.0
			box_m(g, Vector3(0.054, 0.12, 0.02), Vector3(0, -0.06, 0.49), gm)                # cantonera
		"francotirador":
			var barrel := cone_m(g, 0.012, 0.02, 0.9, Vector3(0, 0.0, -0.7), gm)             # cañón cónico
			barrel.rotation_degrees.x = -90.0
			tube(g, 0.02, 0.05, Vector3(0, 0.0, -1.17), blk)                                 # freno de boca
			for i in 3:
				box_m(g, Vector3(0.042, 0.012, 0.012), Vector3(0, 0.0, -1.16 + i * 0.017), gm2)
			tube(g, 0.032, 0.32, Vector3(0, 0.0, -0.08), gm)                                 # cajón del cerrojo
			limb_m(g, Vector3(0.03, 0.01, 0.05), Vector3(0.09, -0.03, 0.06), 0.007, 0.007, gm2)
			sphere(g, 0.018, Vector3(0.09, -0.03, 0.06), Color(0.1, 0.1, 0.12))              # bola del cerrojo
			# visor telescópico con monturas y lentes
			tube(g, 0.022, 0.26, Vector3(0, 0.085, -0.06), gm)
			var bell := cone_m(g, 0.034, 0.022, 0.08, Vector3(0, 0.085, -0.22), gm)
			bell.rotation_degrees.x = -90.0
			var eyep := cone_m(g, 0.03, 0.022, 0.06, Vector3(0, 0.085, 0.1), gm)
			eyep.rotation_degrees.x = 90.0
			tube(g, 0.028, 0.03, Vector3(0, 0.085, -0.03), gm2)                             # torreta
			cone_m(g, 0.012, 0.012, 0.03, Vector3(0, 0.12, -0.04), gm2)
			for zz in [-0.14, 0.03]:
				box_m(g, Vector3(0.02, 0.05, 0.02), Vector3(0, 0.045, zz), gm2)
			tube(g, 0.031, 0.004, Vector3(0, 0.085, -0.262), mat(Color(0.2, 0.55, 0.9), true))   # lente
			# culata de tirador con apoyo para la mejilla
			box_m(g, Vector3(0.062, 0.06, 0.55), Vector3(0, -0.045, -0.2), poly)            # guardamanos
			var grip := box_m(g, Vector3(0.045, 0.12, 0.06), Vector3(0, -0.11, 0.13), poly)
			grip.rotation_degrees.x = -20.0
			box_m(g, Vector3(0.06, 0.07, 0.3), Vector3(0, -0.04, 0.3), poly)
			box_m(g, Vector3(0.05, 0.035, 0.18), Vector3(0, 0.01, 0.32), poly)              # apoyo mejilla
			box_m(g, Vector3(0.062, 0.16, 0.08), Vector3(0, -0.09, 0.46), poly)
			box_m(g, Vector3(0.064, 0.17, 0.02), Vector3(0, -0.09, 0.51), blk)
			box_m(g, Vector3(0.012, 0.008, 0.08), Vector3(0, -0.08, 0.07), gm)
			box_m(g, Vector3(0.035, 0.07, 0.06), Vector3(0, -0.1, -0.02), gm2)              # cargador
			for sx in [-1.0, 1.0]:                                                          # bípode plegado
				tube(g, 0.006, 0.22, Vector3(sx * 0.02, -0.085, -0.38), gm2)
		"revolver":
			var acero := gunmetal(Color(0.45, 0.46, 0.5))                                    # acero pulido
			tube(g, 0.016, 0.2, Vector3(0, 0.03, -0.17), acero)                              # cañón
			box_m(g, Vector3(0.022, 0.012, 0.2), Vector3(0, 0.048, -0.17), acero)            # costilla
			box_m(g, Vector3(0.006, 0.014, 0.012), Vector3(0, 0.06, -0.26), gm)              # mira delantera
			tube(g, 0.012, 0.16, Vector3(0, 0.002, -0.15), acero)                            # varilla del extractor
			var tambor := tube(g, 0.032, 0.06, Vector3(0, 0.012, -0.03), acero)              # tambor
			tambor.rotation_degrees.z = 0.0
			for i in 6:                                                                      # recámaras
				var a := TAU * i / 6.0
				tube(g, 0.008, 0.062, Vector3(cos(a) * 0.02, 0.012 + sin(a) * 0.02, -0.03), blk)
			box_m(g, Vector3(0.04, 0.06, 0.07), Vector3(0, 0.012, 0.025), acero)             # armazón
			box_m(g, Vector3(0.012, 0.02, 0.02), Vector3(0, 0.05, 0.05), gm)                 # martillo
			var grip := box_m(g, Vector3(0.04, 0.11, 0.05), Vector3(0, -0.06, 0.06), wd)
			grip.rotation_degrees.x = -22.0
			box_m(g, Vector3(0.006, 0.006, 0.05), Vector3(0, -0.03, 0.0), acero)            # guardamonte
			box_m(g, Vector3(0.005, 0.022, 0.005), Vector3(0, -0.025, 0.01), gm)             # gatillo
		"deagle":
			var cromo := gunmetal(Color(0.62, 0.6, 0.55))
			box_m(g, Vector3(0.052, 0.075, 0.28), Vector3(0, 0.03, -0.11), cromo)            # corredera grande
			box_m(g, Vector3(0.054, 0.012, 0.22), Vector3(0, 0.07, -0.12), gm)               # carril superior
			for i in 6:
				box_m(g, Vector3(0.055, 0.055, 0.006), Vector3(0, 0.03, 0.0 - i * 0.012), gm)
			tube(g, 0.016, 0.02, Vector3(0, 0.03, -0.255), blk)                              # boca
			box_m(g, Vector3(0.048, 0.035, 0.2), Vector3(0, -0.02, -0.09), cromo)            # armazón
			var grip := box_m(g, Vector3(0.048, 0.14, 0.064), Vector3(0, -0.1, 0.025), poly)
			grip.rotation_degrees.x = -12.0
			box_m(g, Vector3(0.05, 0.014, 0.07), Vector3(0, -0.17, 0.04), cromo)
			box_m(g, Vector3(0.008, 0.035, 0.008), Vector3(0, -0.055, -0.08), cromo)         # guardamonte
			box_m(g, Vector3(0.006, 0.026, 0.006), Vector3(0, -0.05, -0.05), gm)
		"uzi":
			box_m(g, Vector3(0.05, 0.075, 0.26), Vector3(0, 0.0, -0.06), gm)                 # cajón
			box_m(g, Vector3(0.052, 0.02, 0.2), Vector3(0, 0.045, -0.06), gm2)               # tapa
			box_m(g, Vector3(0.012, 0.016, 0.03), Vector3(0, 0.06, -0.15), gm)               # mira delantera
			box_m(g, Vector3(0.03, 0.014, 0.02), Vector3(0, 0.06, 0.05), gm)                 # alza
			tube(g, 0.012, 0.07, Vector3(0, 0.0, -0.22), gm2)                                # cañón corto
			var grip := box_m(g, Vector3(0.04, 0.14, 0.05), Vector3(0, -0.1, -0.02), poly)   # empuñadura con el cargador dentro
			grip.rotation_degrees.x = -6.0
			box_m(g, Vector3(0.028, 0.06, 0.035), Vector3(0, -0.2, -0.025), gm2)             # base del cargador
			box_m(g, Vector3(0.042, 0.035, 0.08), Vector3(0, -0.03, -0.14), poly)            # guardamanos
			box_m(g, Vector3(0.008, 0.03, 0.05), Vector3(0, -0.05, 0.03), gm)                # guardamonte
			for sx in [-1.0, 1.0]:                                                           # culata plegada
				box_m(g, Vector3(0.006, 0.01, 0.16), Vector3(sx * 0.03, -0.01, 0.0), gm2)
		"escopeta":
			tube(g, 0.019, 0.72, Vector3(0, 0.012, -0.46), gm)                               # cañón
			tube(g, 0.016, 0.56, Vector3(0, -0.025, -0.4), gm2)                              # depósito tubular
			var bomba := tube(g, 0.032, 0.2, Vector3(0, -0.02, -0.36), wd)                   # corredera (la bomba)
			for i in 6:
				tube(g, 0.034, 0.008, Vector3(0, -0.02, -0.28 - i * 0.03), mat(Color(0.2, 0.12, 0.06)))
			bomba.scale = Vector3(1.0, 1.0, 1.0)
			box_m(g, Vector3(0.05, 0.075, 0.24), Vector3(0, 0.0, -0.02), gm)                 # cajón
			box_m(g, Vector3(0.008, 0.012, 0.012), Vector3(0, 0.035, -0.81), mat(Color(0.9, 0.85, 0.7)))   # punto de mira
			box_m(g, Vector3(0.012, 0.03, 0.07), Vector3(0, -0.05, 0.03), gm)                # guardamonte
			var cuello := box_m(g, Vector3(0.042, 0.08, 0.1), Vector3(0, -0.04, 0.13), wd)
			cuello.rotation_degrees.x = -14.0
			var st := box_m(g, Vector3(0.048, 0.11, 0.3), Vector3(0, -0.06, 0.3), wd)        # culata
			st.rotation_degrees.x = 7.0
			box_m(g, Vector3(0.052, 0.13, 0.02), Vector3(0, -0.08, 0.46), blk)               # cantonera
		"escopeta_auto":
			box_m(g, Vector3(0.07, 0.1, 0.5), Vector3(0, 0.0, -0.1), poly)                   # cuerpo
			box_m(g, Vector3(0.03, 0.02, 0.4), Vector3(0, 0.065, -0.1), gm)                  # raíl
			box_m(g, Vector3(0.02, 0.03, 0.03), Vector3(0, 0.075, -0.3), gm)                 # mira
			tube(g, 0.02, 0.24, Vector3(0, 0.02, -0.46), gm)                                 # cañón
			tube(g, 0.03, 0.06, Vector3(0, 0.02, -0.58), blk)                                # bocacha
			var tambor := cone_m(g, 0.085, 0.085, 0.06, Vector3(0, -0.11, -0.08), gm2)       # cargador de tambor
			tambor.rotation_degrees.z = 90.0
			var grip := box_m(g, Vector3(0.045, 0.13, 0.055), Vector3(0, -0.1, 0.1), poly)
			grip.rotation_degrees.x = -16.0
			box_m(g, Vector3(0.055, 0.11, 0.24), Vector3(0, -0.02, 0.27), poly)              # culata
			box_m(g, Vector3(0.06, 0.13, 0.02), Vector3(0, -0.03, 0.4), blk)
			box_m(g, Vector3(0.04, 0.06, 0.1), Vector3(0, -0.07, -0.3), poly)                # empuñadura delantera
		"ametralladora":
			box_m(g, Vector3(0.075, 0.11, 0.42), Vector3(0, 0.0, -0.05), gm)                 # cajón
			box_m(g, Vector3(0.08, 0.025, 0.3), Vector3(0, 0.068, -0.03), gm2)               # tapa del alimentador
			box_m(g, Vector3(0.045, 0.06, 0.3), Vector3(0, 0.0, -0.36), gm2)                 # guardamanos
			for i in 6:
				box_m(g, Vector3(0.05, 0.065, 0.012), Vector3(0, 0.0, -0.25 - i * 0.04), blk)
			tube(g, 0.018, 0.5, Vector3(0, 0.0, -0.72), gm)                                  # cañón
			tube(g, 0.026, 0.07, Vector3(0, 0.0, -0.98), blk)                                # apagallamas
			box_m(g, Vector3(0.016, 0.05, 0.02), Vector3(0, 0.04, -0.9), gm)                 # mira delantera
			box_m(g, Vector3(0.03, 0.03, 0.03), Vector3(0, 0.095, 0.1), gm)                  # alza
			box_m(g, Vector3(0.11, 0.13, 0.12), Vector3(0.0, -0.11, -0.08), mat(Color(0.25, 0.3, 0.18)))   # caja de munición
			for i in 5:                                                                      # cinta de balas
				tube(g, 0.007, 0.03, Vector3(0.05, 0.03 - i * 0.012, -0.08), mat(Color(0.75, 0.6, 0.25)))
			tube(g, 0.008, 0.03, Vector3(0, 0.12, -0.12), gm2)                               # asa de transporte
			box_m(g, Vector3(0.012, 0.012, 0.14), Vector3(0, 0.135, -0.12), gm2)
			var grip := box_m(g, Vector3(0.045, 0.12, 0.055), Vector3(0, -0.1, 0.14), poly)
			grip.rotation_degrees.x = -18.0
			box_m(g, Vector3(0.055, 0.1, 0.3), Vector3(0, -0.03, 0.33), poly)                # culata
			for sx in [-1.0, 1.0]:                                                           # bípode
				var pata := tube(g, 0.006, 0.26, Vector3(sx * 0.03, -0.08, -0.78), gm2)
				pata.rotation_degrees = Vector3(30.0, 0.0, sx * 10.0)
		"minigun":
			var giro := Node3D.new()                                                         # el haz de cañones
			giro.name = "Canones"
			giro.position = Vector3(0, 0, -0.3)
			g.add_child(giro)
			for i in 6:
				var a := TAU * i / 6.0
				tube(giro, 0.012, 0.75, Vector3(cos(a) * 0.035, sin(a) * 0.035, -0.25), gm)
			for zz in [-0.05, -0.35, -0.6]:
				tube(giro, 0.055, 0.02, Vector3(0, 0, zz), gm2)
			tube(g, 0.06, 0.25, Vector3(0, 0, 0.05), gm2)                                    # motor
			box_m(g, Vector3(0.12, 0.16, 0.26), Vector3(0, -0.02, 0.18), gm)                 # carcasa
			box_m(g, Vector3(0.14, 0.14, 0.18), Vector3(0.11, -0.04, 0.2), mat(Color(0.3, 0.32, 0.2)))   # caja de munición
			for sx in [-1.0, 1.0]:                                                           # asas
				limb_m(g, Vector3(sx * 0.03, 0.06, 0.18), Vector3(sx * 0.03, 0.11, -0.12), 0.012, 0.012, poly)
			box_m(g, Vector3(0.012, 0.03, 0.04), Vector3(0, 0.14, 0.0), gm)                  # mira
		"ballesta":
			box_m(g, Vector3(0.05, 0.06, 0.62), Vector3(0, 0.0, -0.08), wd)                  # cuerpo
			box_m(g, Vector3(0.02, 0.012, 0.5), Vector3(0, 0.035, -0.12), gm)                # carril del virote
			for sx in [-1.0, 1.0]:                                                           # arco
				var brazo := box_m(g, Vector3(0.3, 0.025, 0.035), Vector3(sx * 0.15, 0.02, -0.36), gm)
				brazo.rotation_degrees.y = sx * -18.0
				limb_m(g, Vector3(sx * 0.29, 0.02, -0.28), Vector3(0.0, 0.035, 0.04), 0.002, 0.002, mat(Color(0.85, 0.85, 0.8)))
			tube(g, 0.006, 0.42, Vector3(0, 0.05, -0.2), mat(Color(0.5, 0.4, 0.3)))          # virote
			var punta := cone_m(g, 0.0, 0.015, 0.05, Vector3(0, 0.05, -0.43), mat(Color(1.0, 0.45, 0.1), true))
			punta.rotation_degrees.x = -90.0
			box_m(g, Vector3(0.012, 0.03, 0.02), Vector3(0, 0.06, 0.05), gm)                 # mira
			var grip := box_m(g, Vector3(0.042, 0.12, 0.055), Vector3(0, -0.08, 0.15), wd)
			grip.rotation_degrees.x = -18.0
			box_m(g, Vector3(0.05, 0.1, 0.24), Vector3(0, -0.04, 0.32), wd)                  # culata
		"lanzacohetes":
			var verde := mat(Color(0.22, 0.28, 0.16))
			tube(g, 0.055, 1.0, Vector3(0, 0.0, -0.15), verde)                               # tubo
			tube(g, 0.064, 0.08, Vector3(0, 0.0, -0.62), gm)                                 # boca
			tube(g, 0.064, 0.1, Vector3(0, 0.0, 0.33), gm)                                   # tobera trasera
			var cabeza := cone_m(g, 0.02, 0.05, 0.16, Vector3(0, 0.0, -0.72), mat(Color(0.35, 0.38, 0.3)))   # cohete asomando
			cabeza.rotation_degrees.x = -90.0
			box_m(g, Vector3(0.03, 0.07, 0.08), Vector3(0.0, 0.08, -0.1), gm)                # mira
			box_m(g, Vector3(0.04, 0.12, 0.05), Vector3(0, -0.1, 0.05), poly)                # empuñadura
			box_m(g, Vector3(0.04, 0.1, 0.05), Vector3(0, -0.1, -0.3), poly)                 # empuñadura delantera
			box_m(g, Vector3(0.012, 0.03, 0.07), Vector3(0, -0.06, 0.0), gm)
		_:
			# Pistola de rayos retro: cromo, aletas y anillos verdes brillantes
			var chrome := StandardMaterial3D.new()
			chrome.albedo_color = Color(0.82, 0.85, 0.9)
			chrome.metallic = 1.0
			chrome.roughness = 0.18
			var red := mat(Color(0.75, 0.08, 0.06))
			var glow := mat(Color(0.1, 1.0, 0.4), true)
			ellipsoid_m(g, Vector3(0.06, 0.07, 0.15), Vector3(0, 0.01, -0.06), chrome)      # cuerpo
			var nose := cone_m(g, 0.025, 0.05, 0.14, Vector3(0, 0.01, -0.24), chrome)
			nose.rotation_degrees.x = -90.0
			for i in 3:
				tube(g, 0.045 - i * 0.006, 0.014, Vector3(0, 0.01, -0.2 - i * 0.04), glow)
			var dish := cone_m(g, 0.06, 0.02, 0.04, Vector3(0, 0.01, -0.33), chrome)        # emisor
			dish.rotation_degrees.x = -90.0
			sphere(g, 0.02, Vector3(0, 0.01, -0.34), Color(0.3, 1.0, 0.5), true)
			for a in [0.0, 120.0, 240.0]:                                                     # aletas
				var fin := Node3D.new()
				fin.position = Vector3(0, 0.01, 0.05)
				fin.rotation_degrees.z = a
				g.add_child(fin)
				box_m(fin, Vector3(0.008, 0.07, 0.08), Vector3(0, 0.08, 0), red)
			tube(g, 0.02, 0.06, Vector3(0, 0.07, -0.02), glow)                               # depósito de energía
			var grip := box_m(g, Vector3(0.042, 0.13, 0.06), Vector3(0, -0.09, 0.03), red)
			grip.rotation_degrees.x = -14.0
			for i in 3:
				box_m(g, Vector3(0.046, 0.008, 0.062), Vector3(0, -0.06 - i * 0.03, 0.025 + i * 0.007), chrome)
			box_m(g, Vector3(0.01, 0.008, 0.07), Vector3(0, -0.06, -0.02), chrome)
	return g


# ---------- Zonas del mapa y rutas (para que los enemigos usen las puertas) ----------
# Medidas del instituto (las usan cesur.gd, main.gd, casino.gd y tienda.gd)
const HALL := 4.0           # medio ancho del primer pasillo (8 m de pared a pared)
const DOOR := 2.5           # medio ancho de la puerta del aula
const WC_Z := 10.9          # z de la puerta de los aseos (hueco de 2,2 m)
const WC_X := 7.8           # centro de cada aseo (x = ±WC_X)
const CASINO_WX := 28.0     # cara este del pasillo largo, donde está la puerta del casino
const CASINO_Z := 42.2      # z de la puerta del casino (hueco de 2,4 m)
const CASINO_Z0 := 37.0     # el casino va de z 37 a 49...
const CASINO_Z1 := 49.0
const CASINO_X1 := 39.4     # ...y de la pared del pasillo largo hasta x = 39,4

# Salas del instituto: rectángulos interiores en el plano XZ (x, z, ancho, fondo).
# Entre dos salas vecinas hay siempre 0,4 m de pared.
enum { R_AULA, R_PASILLO, R_ASEO_I, R_ASEO_D, R_CASINO, R_DISTRIB, R_PASILLO_CAF,
	R_PASILLO_LARGO, R_CAFETERIA, R_BIBLIOTECA, R_PASILLO_NORTE, R_VESTIBULO, R_PATIO }
const SALAS := [
	Rect2(-9.0, -8.0, 18.0, 16.0),       # aula (donde empiezas)
	Rect2(-4.0, 8.4, 8.0, 13.4),         # pasillo de los aseos
	Rect2(-11.2, 8.4, 6.8, 8.0),         # aseo izquierdo
	Rect2(4.4, 8.4, 6.8, 8.0),           # aseo derecho
	Rect2(28.4, 37.0, 11.0, 12.0),       # casino de Iván
	Rect2(-6.0, 22.2, 12.0, 7.8),        # distribuidor (escalera derrumbada)
	Rect2(6.4, 23.0, 15.4, 6.0),         # pasillo de la cafetería
	Rect2(22.2, 23.0, 5.8, 46.8),        # pasillo largo (taquillas, casino, el susto)
	Rect2(6.4, 29.4, 15.4, 26.6),        # cafetería
	Rect2(6.4, 56.4, 15.4, 13.4),        # biblioteca
	Rect2(-4.0, 70.2, 32.0, 5.8),        # pasillo norte
	Rect2(-12.0, 76.4, 24.0, 22.0),      # vestíbulo de la entrada (salida de emergencia)
	Rect2(-30.0, 17.2, 23.6, 58.8),      # patio
]
const NOMBRES_SALA := ["el aula", "el pasillo de los aseos", "el aseo izquierdo", "el aseo derecho",
	"el casino", "el distribuidor", "el pasillo de la cafetería", "el pasillo largo", "la cafetería",
	"la biblioteca", "el pasillo norte", "el vestíbulo", "el patio"]
# Huecos entre salas: [id de puerta de pago ("" = siempre abierto), sala a, sala b,
#  eje ("z" = pared a z constante, el hueco va en x; "x" = al revés), línea de la pared,
#  desde, hasta, altura del dintel (0 = sin dintel, el hueco llega al techo)]
const HUECOS := [
	["A", R_AULA, R_PASILLO, "z", 8.2, -2.5, 2.5, 2.5],
	["", R_PASILLO, R_ASEO_I, "x", -4.2, 9.8, 12.0, 2.5],
	["", R_PASILLO, R_ASEO_D, "x", 4.2, 9.8, 12.0, 2.5],
	["B", R_PASILLO, R_DISTRIB, "z", 22.0, -4.0, 4.0, 0.0],
	["", R_DISTRIB, R_PATIO, "x", -6.2, 23.8, 28.4, 3.0],
	["", R_DISTRIB, R_PASILLO_CAF, "x", 6.2, 23.0, 29.0, 0.0],
	["", R_PASILLO_CAF, R_PASILLO_LARGO, "x", 22.0, 23.0, 29.0, 0.0],
	["", R_PASILLO_CAF, R_CAFETERIA, "z", 29.2, 11.0, 15.0, 2.8],
	["", R_PASILLO_LARGO, R_CAFETERIA, "x", 22.0, 42.0, 46.0, 2.8],
	["", R_PASILLO_LARGO, R_CASINO, "x", 28.2, 41.0, 43.4, 2.6],
	["", R_PASILLO_LARGO, R_BIBLIOTECA, "x", 22.0, 61.0, 64.0, 2.6],
	["C", R_PASILLO_LARGO, R_PASILLO_NORTE, "z", 70.0, 22.2, 28.0, 0.0],
	["", R_PASILLO_NORTE, R_VESTIBULO, "z", 76.2, -3.0, 9.0, 3.2],
	["D", R_PATIO, R_VESTIBULO, "z", 76.2, -10.6, -7.4, 2.6],
]
const ANCHO_PARED := 0.4

# Mapas abiertos del bucle (Mojácar, Pueblo Indalo): una sola zona con un borde
# y obstáculos rectangulares (edificios, piscinas...) que los enemigos rodean
static var mapa := "cesur"
static var limites := Rect2()
static var bloques: Array = []      # Rect2 en el plano XZ (x, z)
# Puertas de pago que siguen cerradas en CESUR (los enemigos no las cruzan)
static var cerradas := {}


static func abierto() -> bool:
	return mapa != "cesur"


static func hueco_abierto(h: Array) -> bool:
	return h[0] == "" or not cerradas.has(h[0])


# Sala en la que está un punto (si está dentro de una pared, la más cercana)
static func region(p: Vector3) -> int:
	if abierto():
		return 0
	var q := Vector2(p.x, p.z)
	for i in SALAS.size():
		var r: Rect2 = SALAS[i]
		if r.has_point(q):
			return i
	var best := 0
	var best_d := 1e9
	for i in SALAS.size():
		var r: Rect2 = SALAS[i]
		var dx := maxf(maxf(r.position.x - q.x, q.x - r.end.x), 0.0)
		var dz := maxf(maxf(r.position.y - q.y, q.y - r.end.y), 0.0)
		var d := dx * dx + dz * dz
		if d < best_d:
			best_d = d
			best = i
	return best


# Primer hueco del camino más corto (en número de salas) de la sala a a la b
static func _primer_hueco(a: int, b: int) -> int:
	var prev := {}
	prev[a] = -1
	var cola: Array = [a]
	var via := {}
	var head := 0
	while head < cola.size():
		var s: int = cola[head]
		head += 1
		if s == b:
			break
		for i in HUECOS.size():
			var h: Array = HUECOS[i]
			if not hueco_abierto(h):
				continue
			var n := -1
			if h[1] == s:
				n = h[2]
			elif h[2] == s:
				n = h[1]
			if n < 0 or prev.has(n):
				continue
			prev[n] = s
			via[n] = i
			cola.append(n)
	if not prev.has(b):
		return -1
	var cur := b
	while prev[cur] != a:
		cur = prev[cur]
	return via[cur]


# Siguiente punto al que ir para llegar de from_p a to_p pasando por las puertas
static func next_point(from_p: Vector3, to_p: Vector3) -> Vector3:
	if abierto():
		return _rodear(from_p, to_p)
	var a := region(from_p)
	var b := region(to_p)
	var p := _paso_cesur(from_p, to_p, a, b)
	# en el patio está la pista de pádel: se rodean sus paredes
	if a == R_PATIO and not bloques.is_empty():
		return _rodear(from_p, p)
	return p


static func _paso_cesur(from_p: Vector3, to_p: Vector3, a: int, b: int) -> Vector3:
	if a == b:
		return to_p
	var hi := _primer_hueco(a, b)
	if hi < 0:
		return to_p
	var h: Array = HUECOS[hi]
	var linea: float = h[4]
	var s0: float = h[5]
	var s1: float = h[6]
	var ra: Rect2 = SALAS[a]
	var en_z: bool = h[3] == "z"
	# lado de la sala a respecto a la pared (+1 o -1)
	var lado := 1.0
	if en_z:
		lado = 1.0 if ra.get_center().y > linea else -1.0
	else:
		lado = 1.0 if ra.get_center().x > linea else -1.0
	var m := minf((s1 - s0) / 2.0, 1.1)        # margen: que quepan hasta los jefes (radio 1 m)
	var lat := clampf(from_p.x if en_z else from_p.z, s0 + m, s1 - m)
	var dentro := ((from_p.z if en_z else from_p.x) - linea) * lado    # > 0: aún en la sala a
	var off := 0.7 if dentro > 0.8 else -1.6
	if en_z:
		return Vector3(lat, 0.0, linea + lado * off)
	return Vector3(linea + lado * off, 0.0, lat)


# Mantiene a un enemigo (o una bala) dentro de las paredes de su sala;
# por los huecos abiertos puede pasar a la sala de al lado
static func clamp_pos(p: Vector3, r: float) -> Vector3:
	if abierto():
		return _clamp_abierto(p, r)
	var reg := region(p)
	var sala: Rect2 = SALAS[reg]
	var x0 := sala.position.x + r
	var x1 := sala.end.x - r
	var z0 := sala.position.y + r
	var z1 := sala.end.y - r
	for h: Array in HUECOS:
		if h[1] != reg and h[2] != reg:
			continue
		if not hueco_abierto(h):
			continue
		var linea: float = h[4]
		var s0: float = h[5] + r
		var s1: float = h[6] - r
		if h[3] == "z":
			if p.x >= s0 and p.x <= s1:
				if linea > sala.end.y:
					z1 = linea + 1.0
				else:
					z0 = linea - 1.0
		else:
			if p.z >= s0 and p.z <= s1:
				if linea > sala.end.x:
					x1 = linea + 1.0
				else:
					x0 = linea - 1.0
	var q := p
	q.x = clampf(q.x, x0, maxf(x0, x1))
	q.z = clampf(q.z, z0, maxf(z0, z1))
	if reg == R_PATIO:
		q = _fuera_de_bloques(q, minf(r, 0.5))     # los jefes grandes rozan el cristal, pero no se atascan
	return q


# Navegación en los mapas abiertos: una cuadrícula de 1 m con las casillas
# ocupadas por obstáculos y, por cada casilla destino, un mapa de distancias
# (BFS). Si hay vía libre se va en línea recta; si no, a la casilla vecina
# que está más cerca del destino. Se guardan los últimos mapas calculados.
const NAV_CELL := 1.0
static var _nav_w := 0
static var _nav_h := 0
static var _nav_block := PackedByteArray()
static var _nav_fields := {}
static var _nav_order: Array = []


static func preparar_nav(margen: float = 1.05) -> void:
	_nav_w = int(ceil(limites.size.x / NAV_CELL))
	_nav_h = int(ceil(limites.size.y / NAV_CELL))
	_nav_block.resize(_nav_w * _nav_h)
	_nav_block.fill(0)
	_nav_fields = {}
	_nav_order = []
	for r: Rect2 in bloques:
		var g := r.grow(margen)    # por defecto, el radio de los jefes (1 m) y un poco más
		var x0 := maxi(0, int(floor((g.position.x - limites.position.x) / NAV_CELL)))
		var x1 := mini(_nav_w - 1, int(floor((g.end.x - limites.position.x) / NAV_CELL)))
		var z0 := maxi(0, int(floor((g.position.y - limites.position.y) / NAV_CELL)))
		var z1 := mini(_nav_h - 1, int(floor((g.end.y - limites.position.y) / NAV_CELL)))
		for iz in range(z0, z1 + 1):
			for ix in range(x0, x1 + 1):
				var c := Vector2(limites.position.x + (ix + 0.5) * NAV_CELL, limites.position.y + (iz + 0.5) * NAV_CELL)
				if g.has_point(c):
					_nav_block[iz * _nav_w + ix] = 1


static func _nav_cell(p: Vector3) -> int:
	var ix := clampi(int(floor((p.x - limites.position.x) / NAV_CELL)), 0, _nav_w - 1)
	var iz := clampi(int(floor((p.z - limites.position.y) / NAV_CELL)), 0, _nav_h - 1)
	return iz * _nav_w + ix


static func _nav_field(target: int) -> PackedInt32Array:
	if _nav_fields.has(target):
		return _nav_fields[target]
	var f := PackedInt32Array()
	f.resize(_nav_w * _nav_h)
	f.fill(-1)
	f[target] = 0
	var q := PackedInt32Array([target])
	var head := 0
	while head < q.size():
		var c := q[head]
		head += 1
		var cx := c % _nav_w
		var cz := c / _nav_w
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = cx + d.x
			var nz: int = cz + d.y
			if nx < 0 or nz < 0 or nx >= _nav_w or nz >= _nav_h:
				continue
			var n := nz * _nav_w + nx
			if f[n] >= 0 or _nav_block[n] == 1:
				continue
			f[n] = f[c] + 1
			q.append(n)
	_nav_fields[target] = f
	_nav_order.append(target)
	if _nav_order.size() > 12:
		_nav_fields.erase(_nav_order.pop_front())
	return f


static func _rodear(from_p: Vector3, to_p: Vector3) -> Vector3:
	var a := Vector2(from_p.x, from_p.z)
	var b := Vector2(to_p.x, to_p.z)
	var libre := true
	for r: Rect2 in bloques:
		if _corta(a, b, r.grow(0.7)):
			libre = false
			break
	if libre or _nav_w == 0:
		return to_p
	var f := _nav_field(_nav_cell(to_p))
	var c := _nav_cell(from_p)
	var cx := c % _nav_w
	var cz := c / _nav_w
	var best := -1
	var best_v := 1 << 30
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dz == 0:
				continue
			var nx := cx + dx
			var nz := cz + dz
			if nx < 0 or nz < 0 or nx >= _nav_w or nz >= _nav_h:
				continue
			var n := nz * _nav_w + nx
			var v := f[n]
			if v < 0:
				continue
			# en diagonal solo si no se corta una esquina
			if dx != 0 and dz != 0 and (_nav_block[cz * _nav_w + nx] == 1 or _nav_block[nz * _nav_w + cx] == 1):
				continue
			if v < best_v:
				best_v = v
				best = n
	if best < 0:
		return to_p
	return Vector3(limites.position.x + (best % _nav_w + 0.5) * NAV_CELL, 0.0, limites.position.y + (best / _nav_w + 0.5) * NAV_CELL)


# ¿El segmento a-b atraviesa el rectángulo r?
static func _corta(a: Vector2, b: Vector2, r: Rect2) -> bool:
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	for ax in 2:
		var lo: float = r.position[ax]
		var hi: float = r.end[ax]
		if absf(d[ax]) < 0.0001:
			if a[ax] < lo or a[ax] > hi:
				return false
		else:
			var u0: float = (lo - a[ax]) / d[ax]
			var u1: float = (hi - a[ax]) / d[ax]
			if u0 > u1:
				var tmp := u0
				u0 = u1
				u1 = tmp
			t0 = maxf(t0, u0)
			t1 = minf(t1, u1)
			if t0 > t1:
				return false
	return true


static func _clamp_abierto(p: Vector3, r: float) -> Vector3:
	var q := p
	q.x = clampf(q.x, limites.position.x + r, limites.end.x - r)
	q.z = clampf(q.z, limites.position.y + r, limites.end.y - r)
	return _fuera_de_bloques(q, r)


# Saca un punto de los obstáculos rectangulares por el lado más cercano
static func _fuera_de_bloques(p: Vector3, r: float) -> Vector3:
	var q := p
	for b: Rect2 in bloques:
		var g := b.grow(r)
		if not g.has_point(Vector2(q.x, q.z)):
			continue
		# sale por el lado más cercano
		var dl := q.x - g.position.x
		var dr := g.end.x - q.x
		var dt := q.z - g.position.y
		var db := g.end.y - q.z
		var m := minf(minf(dl, dr), minf(dt, db))
		if m == dl:
			q.x = g.position.x
		elif m == dr:
			q.x = g.end.x
		elif m == dt:
			q.z = g.position.y
		else:
			q.z = g.end.y
	return q


# ---------- Cegado (granada de Jan) ----------
# Deja a un enemigo (o a Xavier) quieto y sin atacar durante t segundos
static func stun(n: Node3D, t: float) -> void:
	var until := Time.get_ticks_msec() / 1000.0 + t
	n.set_meta("stun_until", maxf(until, float(n.get_meta("stun_until", 0.0))))
	var lbl: Label3D = n.get_node_or_null("Cegado")
	if lbl == null:
		lbl = Label3D.new()
		lbl.name = "Cegado"
		lbl.text = "¡CEGADO!"
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.font_size = 48
		lbl.pixel_size = 0.006
		lbl.outline_size = 10
		lbl.modulate = Color(1.0, 1.0, 0.6)
		lbl.position.y = 2.9
		n.add_child(lbl)


# true mientras siga cegado (y quita el cartel cuando se le pasa)
static func stunned(n: Node3D) -> bool:
	if not n.has_meta("stun_until"):
		return false
	if Time.get_ticks_msec() / 1000.0 < float(n.get_meta("stun_until")):
		return true
	n.remove_meta("stun_until")
	var lbl := n.get_node_or_null("Cegado")
	if lbl != null:
		lbl.queue_free()
	return false


# Material de contorno negro (técnica de "casco invertido")
static func outline_mat(w: float) -> StandardMaterial3D:
	if _outlines.has(w):
		return _outlines[w]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.03, 0.02, 0.03)
	m.cull_mode = BaseMaterial3D.CULL_FRONT
	m.grow = true
	m.grow_amount = w
	_outlines[w] = m
	return m


# Estilo cartoon para personajes: sombreado por bandas + contorno negro
static func toonify(n: Node, w: float = 0.012) -> void:
	for c in n.get_children():
		if c is MeshInstance3D and c.material_override is StandardMaterial3D:
			var m: StandardMaterial3D = c.material_override
			m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
			m.specular_mode = BaseMaterial3D.SPECULAR_TOON
			m.roughness = 0.55
			if w > 0.0 and m.next_pass == null and m.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and not m.emission_enabled:
				m.next_pass = outline_mat(w)
		toonify(c, w)


# Pone todas las mallas de un nodo en una capa visual (para ocultar la cabeza en primera persona)
static func set_layer(n: Node, layer: int) -> void:
	if n is VisualInstance3D:
		n.layers = 1 << (layer - 1)
	for c in n.get_children():
		set_layer(c, layer)

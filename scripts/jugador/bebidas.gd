extends Node3D
# Bebidas con habilidades (como los Perk-a-Cola de CoD Zombies). Cada una está en
# su propia máquina expendedora, con su color, su cartel luminoso y su musiquilla.
# Te duran hasta que te tumban o te matan. Como mucho llevas MAX_BEBIDAS a la vez.
#  · Batido Tanque     2500  ->  250 de vida en vez de 100
#  · Cola Rápida       3000  ->  recargas el doble de rápido
#  · Doble Chupito     2000  ->  disparas un 30 % más rápido y haces el doble de daño
#  · Zumo Revivo       1500  ->  te curas antes; jugando solo te levantas una vez tú solo;
#                                en equipo reanimas el doble de rápido
#  · Energética Turbo  2000  ->  corres más rápido y aguantas el doble esprintando
# El efecto lo aplica player.gd (has_perk). Las máquinas de CESUR son algunas de las
# del mapa (cesur.gd ya pone el modelo y el choque); en Mojácar y el Pueblo Indalo se
# ponen máquinas nuevas al lado de los sitios de la caja misteriosa.

const U = preload("res://scripts/nucleo/util.gd")
const HudScript = preload("res://scripts/interfaz/hud.gd")

const MAX_BEBIDAS := 4
const DATOS := {
	"tanque": {"nombre": "Batido Tanque", "precio": 2500, "color": Color(0.9, 0.12, 0.12), "letra": "T",
		"desc": "250 de vida", "notas": [196.0, 196.0, 233.1, 196.0, 174.6, 155.6]},
	"rapida": {"nombre": "Cola Rápida", "precio": 3000, "color": Color(0.15, 0.8, 0.3), "letra": "R",
		"desc": "recargas el doble de rápido", "notas": [523.3, 659.3, 784.0, 659.3, 784.0, 1046.5]},
	"doble": {"nombre": "Doble Chupito", "precio": 2000, "color": Color(1.0, 0.78, 0.12), "letra": "D",
		"desc": "más cadencia y el doble de daño", "notas": [392.0, 392.0, 523.3, 392.0, 392.0, 587.3]},
	"revivir": {"nombre": "Zumo Revivo", "precio": 1500, "color": Color(0.25, 0.6, 1.0), "letra": "Z",
		"desc": "te levantas una vez tú solo · reanimas el doble de rápido", "notas": [659.3, 587.3, 523.3, 587.3, 659.3, 659.3]},
	"turbo": {"nombre": "Energética Turbo", "precio": 2000, "color": Color(1.0, 0.5, 0.1), "letra": "E",
		"desc": "corres más y aguantas el doble esprintando", "notas": [440.0, 554.4, 659.3, 880.0, 659.3, 880.0]},
}
# CESUR: [id, posición de la máquina, giro] (máquinas de bebidas que ya pone cesur.gd)
const CESUR := [
	["revivir", Vector3(5.1, 0.0, 22.7), 0.0],        # distribuidor, al lado de la puerta B
	["doble", Vector3(9.25, 0.0, 23.45), 0.0],        # pasillo de la cafetería
	["rapida", Vector3(6.85, 0.0, 46.4), 90.0],       # cafetería
	["tanque", Vector3(22.65, 0.0, 32.05), 90.0],     # pasillo largo (sur)
	["turbo", Vector3(22.65, 0.0, 56.55), 90.0],      # pasillo largo (norte)
]
const ORDEN := ["revivir", "doble", "rapida", "tanque", "turbo"]

var game
var maquinas: Array = []       # {"id", "pos", "luz", "audio"}
var iconos: HBoxContainer
var _vistos := []
var jingle_t := 12.0
var snd_beber: AudioStreamPlayer
var flash: ColorRect


func _ready() -> void:
	if Net.mapa == "cesur":
		for m: Array in CESUR:
			_maquina(m[0], m[1], m[2], false)
	else:
		# al lado de los sitios de la caja (en su misma pared, 2,2 m hacia un lado)
		var spots: Array = game.box_spots
		for i in mini(ORDEN.size(), spots.size()):
			var s: Array = spots[i]
			var yaw: float = s[1]
			var p: Vector3 = s[0] + Vector3(2.2, 0.0, 0.0).rotated(Vector3.UP, deg_to_rad(yaw))
			_maquina(ORDEN[i], p, yaw, true)
	_build_hud()
	snd_beber = AudioStreamPlayer.new()
	snd_beber.stream = _sonido_beber()
	add_child(snd_beber)


func _process(delta: float) -> void:
	var player = game.player
	if player == null:
		return
	# iconos de las bebidas que llevas
	if player.perks != _vistos:
		_vistos = player.perks.duplicate()
		for c in iconos.get_children():
			c.queue_free()
		for id in _vistos:
			iconos.add_child(_icono(id))
	# de vez en cuando suena la musiquilla de la máquina que tengas cerca
	jingle_t -= delta
	if jingle_t <= 0.0:
		jingle_t = randf_range(25.0, 45.0)
		for m in maquinas:
			if player.global_position.distance_to(m["pos"]) < 9.0:
				m["audio"].play()
				break
	for m in maquinas:       # los carteles parpadean un poco, como un neón viejo
		var l: OmniLight3D = m["luz"]
		l.light_energy = 1.3 if randf() > 0.01 else 0.2


# ---------------- Comprar ----------------
func prompt(it: Dictionary) -> String:
	var d: Dictionary = DATOS[it["perk"]]
	var player = game.player
	if player.has_perk(it["perk"]):
		return "Ya llevas %s" % d["nombre"]
	if player.perks.size() >= MAX_BEBIDAS:
		return "%s · Solo puedes llevar %d bebidas" % [d["nombre"], MAX_BEBIDAS]
	return "[E] Beber %s (%d puntos)  ·  %s" % [d["nombre"], d["precio"], d["desc"]]


func comprar(it: Dictionary) -> void:
	var id: String = it["perk"]
	var d: Dictionary = DATOS[id]
	var player = game.player
	if player.has_perk(id) or player.perks.size() >= MAX_BEBIDAS:
		return
	if game.points < int(d["precio"]):
		game._toast("Te faltan %d puntos" % (int(d["precio"]) - game.points))
		return
	game.points -= int(d["precio"])
	player.give_perk(id)
	if player.vista != null:
		player.vista.beber(d["color"], d["letra"])        # animación de bebérsela
	snd_beber.play()
	for m in maquinas:
		if m["id"] == id:
			m["audio"].play()
	flash.color = Color(d["color"], 0.35)
	flash.create_tween().tween_property(flash, "color:a", 0.0, 0.8)
	game._toast("%s: %s" % [d["nombre"], d["desc"]])


# ---------------- Máquina ----------------
func _maquina(id: String, pos: Vector3, yaw: float, con_modelo: bool) -> void:
	var d: Dictionary = DATOS[id]
	var col: Color = d["color"]
	var root := Node3D.new()
	root.position = pos
	root.rotation_degrees.y = yaw
	add_child(root)
	if con_modelo:
		var ps = load("res://modelos/mapa/maquina_bebidas.glb") if ResourceLoader.exists("res://modelos/mapa/maquina_bebidas.glb") else null
		if ps is PackedScene:
			root.add_child(ps.instantiate())
		else:
			U.box(root, Vector3(1.0, 1.9, 0.8), Vector3(0, 0.95, 0), col.darkened(0.5))
		var sb := StaticBody3D.new()
		sb.position = Vector3(0, 0.925, 0)
		root.add_child(sb)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(0.95, 1.85, 0.86)
		cs.shape = sh
		sb.add_child(cs)
	# carcasa de color por los lados y el cartel luminoso de arriba
	for sx in [-1.0, 1.0]:
		var lado := U.box(root, Vector3(0.04, 1.86, 0.88), Vector3(sx * 0.5, 0.93, 0.0), col)
		lado.material_override.roughness = 0.35
	var cartel := U.box(root, Vector3(1.0, 0.34, 0.16), Vector3(0, 2.07, 0.3), col, true)
	cartel.material_override.emission_energy_multiplier = 1.6
	var franja := U.box(root, Vector3(0.9, 0.05, 0.02), Vector3(0, 1.88, 0.44), col, true)
	franja.material_override.emission_energy_multiplier = 2.5
	for lado2 in [1.0, -1.0]:
		var t := Label3D.new()
		t.text = d["nombre"].to_upper()
		t.font_size = 44
		t.pixel_size = 0.0034
		t.outline_size = 10
		t.outline_modulate = Color(0, 0, 0, 0.8)
		t.modulate = Color(1, 1, 1)
		t.position = Vector3(0, 2.08, 0.3 + lado2 * 0.085)
		t.rotation_degrees.y = 0.0 if lado2 > 0.0 else 180.0
		root.add_child(t)
	var precio := Label3D.new()
	precio.text = "%d" % d["precio"]
	precio.font_size = 40
	precio.pixel_size = 0.0035
	precio.outline_size = 8
	precio.modulate = Color(1.0, 0.92, 0.5)
	precio.position = Vector3(0, 1.78, 0.46)
	root.add_child(precio)
	var luz := OmniLight3D.new()
	luz.light_color = col
	luz.light_energy = 1.3
	luz.omni_range = 4.0
	luz.position = Vector3(0, 1.6, 0.9)
	root.add_child(luz)
	var audio := AudioStreamPlayer3D.new()
	audio.stream = _jingle(d["notas"])
	audio.unit_size = 4.0
	audio.position = Vector3(0, 1.4, 0.4)
	root.add_child(audio)
	var ipos := pos + Vector3(0, 0, 0.95).rotated(Vector3.UP, deg_to_rad(yaw))
	maquinas.append({"id": id, "pos": ipos, "luz": luz, "audio": audio})
	game.interactables.append({"type": "perk", "perk": id, "pos": ipos, "done": false})


# ---------------- HUD ----------------
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 4
	add_child(layer)
	# fila de chapas entre la oleada y la barra de vida del HUD
	iconos = HBoxContainer.new()
	iconos.add_theme_constant_override("separation", 4)
	iconos.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	iconos.offset_left = 20.0
	iconos.offset_right = 20.0
	iconos.offset_top = -50.0
	iconos.offset_bottom = -36.0
	iconos.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(iconos)
	flash = ColorRect.new()
	flash.color = Color(1, 1, 1, 0)
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(flash)


# Circulito plano del color de la bebida con su letra
func _icono(id: String) -> Control:
	var d: Dictionary = DATOS[id]
	var col: Color = d["color"]
	var c := Control.new()
	c.custom_minimum_size = Vector2(14, 14)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var f := HudScript.fuente(HudScript.F_UI_BOLD)
	c.draw.connect(func():
		var m := Vector2(7, 7)
		c.draw_circle(m, 7.0, Color(0, 0, 0, 0.25))
		c.draw_circle(m, 6.3, Color(col, 0.85))
		c.draw_string(f, Vector2(0, 10.5), d["letra"], HORIZONTAL_ALIGNMENT_CENTER, 14, 10, Color(1, 1, 1, 0.95)))
	c.pivot_offset = Vector2(7, 7)
	c.scale = Vector2.ONE * 1.5
	c.create_tween().tween_property(c, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return c


# ---------------- Sonidos ----------------
# Musiquilla de la máquina: unas notas de "órgano" con un poco de vibrato
func _jingle(notas: Array) -> AudioStreamWAV:
	var rate := 22050
	var paso := 0.16
	var n := int(rate * (paso * notas.size() + 0.5))
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var tt := float(i) / rate
		var s := 0.0
		var k := int(tt / paso)
		if k < notas.size():
			var f: float = notas[k] * (1.0 + 0.004 * sin(tt * 35.0))
			var dt := tt - k * paso
			var env := minf(1.0, dt * 40.0) * exp(-dt * 3.0)
			s = (sin(TAU * f * tt) * 0.6 + sin(TAU * f * 2.0 * tt) * 0.25 + sin(TAU * f * 3.0 * tt) * 0.12) * env
		else:
			var dt2 := tt - notas.size() * paso
			var f2: float = notas[-1]
			s = (sin(TAU * f2 * tt) * 0.5 + sin(TAU * f2 * 1.5 * tt) * 0.2) * exp(-dt2 * 5.0)
		data.encode_s16(i * 2, int(clampf(s * 0.45, -1.0, 1.0) * 30000.0))
	return U._wav(data, rate)


# Lata que se abre, tres tragos y un eructo
func _sonido_beber() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 1.9)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var tt := float(i) / rate
		var s := 0.0
		if tt < 0.12:                                   # ¡pssst!
			s = (randf() * 2.0 - 1.0) * exp(-tt * 25.0) * 0.8
		for g in [0.35, 0.6, 0.85]:                     # glu, glu, glu
			var d: float = tt - g
			if d > 0.0 and d < 0.18:
				s += sin(TAU * (180.0 - d * 400.0) * d) * sin(PI * d / 0.18) * 0.7
		if tt > 1.25:                                   # eructo
			var d2 := tt - 1.25
			var f := 85.0 + 25.0 * sin(d2 * 9.0)
			s += (sin(TAU * f * d2) + (randf() * 2.0 - 1.0) * 0.35) * sin(PI * minf(d2 / 0.6, 1.0)) * 0.6
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 28000.0))
	return U._wav(data, rate)

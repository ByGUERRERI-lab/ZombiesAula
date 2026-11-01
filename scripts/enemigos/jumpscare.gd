extends Node3D
# Jumpscare en el pasillo: sale de una puerta oscura y corre hacia el jugador.

const U = preload("res://scripts/nucleo/util.gd")
const Ch = preload("res://scripts/jugador/character.gd")

var player
var zona := Rect2()          # tramo del pasillo donde se activa (plano XZ); vacío = el de siempre
var state := 0              # 0 oculto, 1 corriendo, 2 susto, 3 terminado
var t := 0.0
var body: Node3D
var head: Node3D
var flash: ColorRect
var scream: AudioStreamPlayer
var boom: AudioStreamPlayer


func _ready() -> void:
	body = Node3D.new()
	body.scale = Vector3.ONE * 1.15
	add_child(body)
	_build_body()
	body.visible = false

	scream = AudioStreamPlayer.new()
	scream.stream = make_scream()
	scream.volume_db = 2.0
	add_child(scream)
	boom = AudioStreamPlayer.new()
	boom.stream = make_boom()
	add_child(boom)

	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	flash = ColorRect.new()
	flash.color = Color(0.8, 0.0, 0.0, 0.0)
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(flash)


func _physics_process(delta: float) -> void:
	match state:
		0:
			# Se activa cuando el jugador se acerca por el pasillo
			var pp: Vector3 = player.global_position
			var dentro := zona.has_point(Vector2(pp.x, pp.z)) if zona.has_area() else pp.z > 46.0
			if dentro and not player.dead:
				state = 1
				body.visible = true
				boom.play()
		1:
			var to_p: Vector3 = player.global_position - global_position
			to_p.y = 0.0
			var dist := to_p.length()
			var d := to_p.normalized()
			rotation.y = atan2(-d.x, -d.z)
			global_position += d * 11.0 * delta
			t += delta
			body.position.y = absf(sin(t * 14.0)) * 0.12
			if dist < 1.8:
				_start_scare(d)
		2:
			_scare(delta)


func _start_scare(d: Vector3) -> void:
	state = 2
	t = 0.0
	player.frozen = true
	player.velocity = Vector3.ZERO
	# Obliga al jugador a mirarle a la cara
	player.rotation.y = atan2(d.x, d.z)
	player.pitch = 0.25
	player.head_pivot.rotation.x = 0.25
	global_position = player.global_position - d * 1.4
	global_position.y = 0.0
	scream.play()


func _scare(delta: float) -> void:
	t += delta
	var k := clampf(t / 0.25, 0.0, 1.0)
	var fwd := Vector3(-sin(rotation.y), 0.0, -cos(rotation.y))
	global_position = player.global_position - fwd * lerpf(1.4, 0.65, k)
	global_position.y = 0.0
	head.scale = Vector3.ONE * lerpf(1.0, 1.5, k)
	body.position = Vector3(randf_range(-0.03, 0.03), 0.0, randf_range(-0.03, 0.03))
	player.cam.h_offset = randf_range(-0.07, 0.07)
	player.cam.v_offset = randf_range(-0.07, 0.07)
	flash.color = Color(0.8, 0.0, 0.0, 0.4 + 0.25 * sin(t * 40.0))
	if t > 1.8:
		state = 3
		body.visible = false
		player.frozen = false
		player.cam.h_offset = 0.0
		player.cam.v_offset = 0.0
		flash.color = Color(0.8, 0.0, 0.0, 0.0)


func _build_body() -> void:
	var skin := Color(0.82, 0.68, 0.58)
	var white := Color(0.93, 0.93, 0.9)
	var black := Color(0.06, 0.06, 0.07)
	var yellow := Color(0.95, 0.82, 0.1)
	var jeans := Color(0.27, 0.4, 0.62)
	var red := Color(0.8, 0.08, 0.08)
	var hair_c := Color(0.07, 0.05, 0.04)
	# piernas vaqueras
	U.box(body, Vector3(0.28, 0.9, 0.3), Vector3(-0.17, 0.45, 0), jeans)
	U.box(body, Vector3(0.28, 0.9, 0.3), Vector3(0.17, 0.45, 0), jeans)
	# sudadera blanca con banda amarilla, bloque negro y capucha negra
	U.capsule(body, 0.4, 1.1, Vector3(0, 1.3, 0), white)
	U.box(body, Vector3(0.8, 0.2, 0.8), Vector3(0, 0.88, 0), yellow)
	var blk := U.box(body, Vector3(0.5, 0.45, 0.02), Vector3(0.2, 1.55, -0.41), black)
	blk.rotation_degrees.z = -28.0
	var hood := U.sphere(body, 0.3, Vector3(0, 1.82, 0.12), black)
	hood.scale = Vector3(1.2, 0.6, 1.0)
	# logo naranja y rojo
	U.box(body, Vector3(0.3, 0.12, 0.02), Vector3(-0.05, 1.08, -0.41), Color(0.8, 0.15, 0.1))
	U.box(body, Vector3(0.2, 0.1, 0.02), Vector3(0, 1.15, -0.415), Color(0.95, 0.5, 0.1))
	# cordón rojo con acreditación
	var c1 := U.box(body, Vector3(0.025, 0.5, 0.015), Vector3(-0.07, 1.5, -0.405), red)
	c1.rotation_degrees.z = 10.0
	var c2 := U.box(body, Vector3(0.025, 0.5, 0.015), Vector3(0.07, 1.5, -0.405), red)
	c2.rotation_degrees.z = -10.0
	U.box(body, Vector3(0.11, 0.08, 0.015), Vector3(0, 1.2, -0.415), Color(0.9, 0.93, 1.0))
	# cabeza: pelo oscuro rizado, ojos desorbitados, boca abierta
	head = Node3D.new()
	head.position = Vector3(0, 2.0, 0)
	body.add_child(head)
	U.sphere(head, 0.27, Vector3.ZERO, skin)
	var hair := U.sphere(head, 0.285, Vector3(0, 0.08, 0.03), hair_c)
	hair.scale = Vector3(1.0, 0.75, 1.0)
	U.box(head, Vector3(0.44, 0.1, 0.12), Vector3(0, 0.23, -0.15), hair_c)
	Ch.face(head, 0.27, skin, "scream", hair_c)
	# brazos hacia delante: izquierdo blanco, derecho negro (como la sudadera)
	U.box(body, Vector3(0.2, 0.2, 0.7), Vector3(-0.55, 1.55, -0.4), white)
	U.box(body, Vector3(0.2, 0.2, 0.7), Vector3(0.55, 1.55, -0.4), black)
	U.box(body, Vector3(0.17, 0.17, 0.25), Vector3(-0.55, 1.55, -0.85), skin)
	U.box(body, Vector3(0.17, 0.17, 0.25), Vector3(0.55, 1.55, -0.85), skin)
	U.toonify(body, 0.012)


# Sonidos generados por código (no hace falta ningún archivo de audio)
static func make_scream() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 1.4)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for i in n:
		var tt := float(i) / rate
		var f := 600.0 + 900.0 * sin(tt * 18.0) + 500.0 * tt
		phase += TAU * f / rate
		var s := sin(phase) * 0.5 + (randf() * 2.0 - 1.0) * 0.5
		s = clampf(s * 2.4, -1.0, 1.0)
		var env := 1.0
		if tt > 1.0:
			env = (1.4 - tt) / 0.4
		data.encode_s16(i * 2, int(s * env * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w


static func make_boom() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.8)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var tt := float(i) / rate
		var s := sin(TAU * 55.0 * tt) * exp(-tt * 5.0) + (randf() * 2.0 - 1.0) * 0.5 * exp(-tt * 14.0)
		s = clampf(s * 1.5, -1.0, 1.0)
		data.encode_s16(i * 2, int(s * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w

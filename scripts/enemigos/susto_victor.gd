extends Node3D
# Susto de Víctor: al robarte, su cara gritando se te echa encima de la pantalla.
# Va pegado a la cámara y solo lo ve el jugador robado. No te congela: mientras
# dura, los zombies siguen a lo suyo.

const U = preload("res://scripts/nucleo/util.gd")
const Ch = preload("res://scripts/jugador/character.gd")
const Js = preload("res://scripts/enemigos/jumpscare.gd")

const VOZ := "res://sonidos/victor_robo.ogg"
const TIME := 1.25
const HEAD_Y := 1.75 * Ch.VICTOR_SCALE     # altura de su cara

var t := 0.0
var holder: Node3D
var head: Node3D
var flash: ColorRect


func _ready() -> void:
	holder = Node3D.new()
	holder.position.z = -2.4
	add_child(holder)
	var parts: Dictionary = Ch.build_victor(holder, "scream")
	var model: Node3D = parts["model"]
	var rig: Dictionary = parts["rig"]
	head = parts["head"]
	model.position.y = -HEAD_Y
	model.rotation_degrees.y = 180.0          # mirándote a la cara
	rig["spine"].rotation.x = -0.12
	rig["head"].rotation.x = 0.12
	for i in 2:                                # brazos abiertos, sin taparle la cara
		rig["arms"][i].rotation = Vector3(0.8, 0.0, -1.0 if i == 0 else 1.0)

	# que se le vea la cara aunque estés a oscuras
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.92, 0.85)
	l.light_energy = 1.0
	l.omni_range = 3.0
	l.position = Vector3(0.0, 0.35, -0.2)
	add_child(l)

	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	flash = ColorRect.new()
	flash.color = Color(0.0, 0.0, 0.0, 1.0)    # un parpadeo negro y ¡bum!
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(flash)

	# en vez del grito, Víctor te dice la nota de voz a la cara (bien alto, sin 3D)
	var scream := AudioStreamPlayer.new()
	if ResourceLoader.exists(VOZ):
		scream.stream = load(VOZ)
		scream.volume_db = 6.0
		for v in get_tree().get_nodes_in_group("victors"):    # que no suene repetida desde él
			if v.snd != null and v.snd.playing:
				v.snd.stop()
	else:
		scream.stream = Js.make_scream()
		scream.pitch_scale = 0.8
		scream.volume_db = 3.0
	add_child(scream)
	scream.play()
	var boom := AudioStreamPlayer.new()
	boom.stream = Js.make_boom()
	add_child(boom)
	boom.play()


func _process(delta: float) -> void:
	t += delta
	if t >= TIME:
		queue_free()
		return
	var k := clampf(t / 0.14, 0.0, 1.0)        # se lanza casi de golpe
	holder.position = Vector3(randf_range(-0.025, 0.025), 0.07 + randf_range(-0.025, 0.025), lerpf(-2.4, -0.78, k * k))
	head.scale = Vector3.ONE * (1.0 + 0.14 * sin(t * 30.0) * 0.5 + 0.2 * k)
	if t < 0.05:
		flash.color = Color(0.0, 0.0, 0.0, 1.0)
	else:
		flash.color = Color(0.75, 0.0, 0.0, 0.14 + 0.12 * sin(t * 40.0))

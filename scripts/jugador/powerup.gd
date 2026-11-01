extends Node3D
# Munición Máxima (como en CoD Zombies): caja de munición que flota, gira y
# brilla en verde. La suelta la última Isabella de su ronda. El primero que
# pasa por encima la coge y TODOS los jugadores recargan munición y Janes.
# Si nadie la coge, a los 30 s empieza a parpadear y desaparece.

const U = preload("res://scripts/nucleo/util.gd")

const LIFE := 30.0

var game
var body: Node3D
var t := 0.0
var taken := false


func _ready() -> void:
	game = get_tree().get_first_node_in_group("game")
	body = Node3D.new()
	body.position.y = 0.9
	add_child(body)
	# caja de munición verde oliva con balas doradas encima
	U.box(body, Vector3(0.5, 0.3, 0.26), Vector3.ZERO, Color(0.28, 0.33, 0.16))
	U.box(body, Vector3(0.52, 0.04, 0.28), Vector3(0, 0.16, 0), Color(0.2, 0.24, 0.12))
	U.box(body, Vector3(0.14, 0.03, 0.06), Vector3(0, 0.19, 0), Color(0.12, 0.12, 0.1))       # asa
	for i in 5:
		var b := Node3D.new()
		b.position = Vector3(-0.16 + i * 0.08, 0.27, 0.0)
		body.add_child(b)
		U.cylinder(b, 0.017, 0.12, Vector3.ZERO, Color(0.85, 0.65, 0.2))
		U.cone(b, 0.0, 0.017, 0.04, Vector3(0, 0.08, 0), Color(0.75, 0.45, 0.2))
	var tag := Label3D.new()
	tag.text = "MUNICIÓN"
	tag.font_size = 40
	tag.pixel_size = 0.0035
	tag.outline_size = 0
	tag.modulate = Color(0.95, 0.9, 0.6)
	tag.position = Vector3(0, 0.0, 0.135)
	body.add_child(tag)
	# brillo verde alrededor
	var glow := U.sphere(body, 0.45, Vector3.ZERO, Color(0.3, 1.0, 0.35), true)
	glow.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.material_override.albedo_color.a = 0.18
	glow.material_override.emission_energy_multiplier = 2.5
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var l := OmniLight3D.new()
	l.light_color = Color(0.35, 1.0, 0.4)
	l.light_energy = 2.5
	l.omni_range = 5.0
	body.add_child(l)
	U.toonify(body, 0.008)


func _process(delta: float) -> void:
	t += delta
	body.rotation.y = t * 1.6
	body.position.y = 0.9 + sin(t * 2.5) * 0.12
	# a punto de desaparecer: parpadea cada vez más rápido
	if t > LIFE - 8.0:
		body.visible = fmod(t, 0.5 if t < LIFE - 3.0 else 0.2) < (0.3 if t < LIFE - 3.0 else 0.1)
	if t > LIFE:
		queue_free()
		return
	var p = game.player
	if taken or p == null or p.dead or p.downed:
		return
	if Vector2(p.global_position.x - global_position.x, p.global_position.z - global_position.z).length() < 1.2:
		taken = true
		game.take_max_ammo()

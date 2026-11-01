extends Node3D
# Lo que suelta Víctor al morir: flota en el suelo y brilla en dorado. El primero
# que pasa por encima se lo queda. Si nadie lo coge, a los 30 s desaparece.

const U = preload("res://scripts/nucleo/util.gd")
const W = preload("res://scripts/jugador/weapons.gd")
const Ch = preload("res://scripts/jugador/character.gd")

const LIFE := 30.0

var item := {}
var game
var body: Node3D
var t := 0.0
var taken := false


func _ready() -> void:
	game = get_tree().get_first_node_in_group("game")
	body = Node3D.new()
	body.position.y = 0.9
	add_child(body)
	Ch.build_loot(body, item)
	var glow := U.sphere(body, 0.4, Vector3.ZERO, Color(1.0, 0.8, 0.25), true)
	glow.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.material_override.albedo_color.a = 0.16
	glow.material_override.emission_energy_multiplier = 2.5
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.8, 0.3)
	l.light_energy = 2.5
	l.omni_range = 5.0
	l.position.y = 0.9
	add_child(l)
	var tag := Label3D.new()
	tag.text = W.loot_name(item)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.font_size = 40
	tag.pixel_size = 0.004
	tag.outline_size = 10
	tag.modulate = Color(1.0, 0.85, 0.35)
	tag.position.y = 1.55
	add_child(tag)


func _process(delta: float) -> void:
	t += delta
	body.rotation.y = t * 1.6
	body.position.y = 0.9 + sin(t * 2.5) * 0.12
	# a punto de desaparecer: parpadea cada vez más rápido
	if t > LIFE - 8.0:
		visible = fmod(t, 0.5 if t < LIFE - 3.0 else 0.2) < (0.3 if t < LIFE - 3.0 else 0.1)
	if t > LIFE:
		queue_free()
		return
	var p = game.player
	if taken or p == null or p.dead or p.downed:
		return
	if Vector2(p.global_position.x - global_position.x, p.global_position.z - global_position.z).length() < 1.3:
		taken = true
		game.take_loot(self)

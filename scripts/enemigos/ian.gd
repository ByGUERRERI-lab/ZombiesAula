extends Node3D
# Ian: minijefe "tanque". Lento pero con mucha vida. Al aparecer suelta su frase
# (sonidos/ian.ogg) y lo oye todo el mundo. Si te pilla cerca se echa para atrás
# y te da un panzazo que te manda volando.

const U = preload("res://scripts/nucleo/util.gd")
const Ch = preload("res://scripts/jugador/character.gd")
const VOICE := preload("res://sonidos/ian.ogg")

var player
var hp := 80.0
var radius := 0.65
var speed := 2.4
var dying := false
var puppet := false        # copia de un enemigo que controla el anfitrión
var model: Node3D
var belly: Node3D
var hit_cd := 1.0
var windup := 0.0          # > 0 mientras coge carrerilla para el panzazo
var t := 0.0


func _ready() -> void:
	add_to_group("zombies")
	var parts: Dictionary = Ch.build_ian(self)
	model = parts["model"]
	belly = parts["belly"]
	_arrive()


# Llega pisando fuerte: temblor, polvo y su frase (en todos los PCs)
func _arrive() -> void:
	var game = get_tree().get_first_node_in_group("game")
	var voice := AudioStreamPlayer.new()
	voice.stream = VOICE
	voice.volume_db = 4.0
	add_child(voice)
	voice.play()
	var thud := AudioStreamPlayer3D.new()
	thud.stream = U.make_shot(0.5, true)
	thud.unit_size = 10.0
	add_child(thud)
	thud.play()
	for i in 8:
		var d := U.sphere(self, 0.25, Vector3(cos(i * TAU / 8.0) * 0.6, 0.15, sin(i * TAU / 8.0) * 0.6), Color(0.75, 0.72, 0.68))
		d.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		d.material_override.albedo_color.a = 0.5
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var tw := d.create_tween().set_parallel()
		tw.tween_property(d, "position", d.position * 3.0 + Vector3(0, 0.4, 0), 0.8)
		tw.tween_property(d, "scale", Vector3.ONE * 3.0, 0.8)
		tw.tween_property(d.material_override, "albedo_color:a", 0.0, 0.8)
		tw.chain().tween_callback(d.queue_free)
	if game:
		game.toast_small("¡Ha llegado Ian!")
		if game.player != null and game.player.global_position.distance_to(global_position) < 25.0:
			game.shake(0.35)


func _physics_process(delta: float) -> void:
	t += delta
	if dying:
		return
	if U.stunned(self) or puppet:
		return    # cegado por Jan, o copia en otro PC (la mueve el anfitrión)
	if player == null or player.dead:
		return
	hit_cd -= delta
	var to_p: Vector3 = player.global_position - global_position
	to_p.y = 0.0
	var dist := to_p.length()
	var tgt: Vector3 = U.next_point(global_position, player.global_position)
	var mv: Vector3 = tgt - global_position
	mv.y = 0.0
	var dir := mv.normalized()
	rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 4.0 * delta)

	# panzazo: se echa para atrás y se lanza con la barriga por delante
	if windup > 0.0:
		windup -= delta
		model.rotation.x = lerpf(model.rotation.x, 0.3, 10.0 * delta)
		if windup <= 0.0:
			model.rotation.x = -0.35
			create_tween().tween_property(model, "rotation:x", 0.0, 0.35)
			var bump := create_tween()
			bump.tween_property(belly, "scale", belly.scale * 1.25, 0.08)
			bump.tween_property(belly, "scale", belly.scale, 0.2)
			if dist < radius + 1.3:
				player.hurt(25.0)
				player.knock = to_p.normalized() * 14.0
		return
	if dist < radius + 0.9 and hit_cd <= 0.0:
		hit_cd = 1.8
		windup = 0.35
		return
	if dist > radius + 0.6:
		global_position += dir * speed * delta
		# camina pesado, balanceándose de lado a lado
		model.rotation.z = sin(t * 5.0) * 0.08
		model.position.y = absf(sin(t * 5.0)) * 0.04
	global_position = U.clamp_pos(global_position, radius)


func hurt(amount: float, dir: Vector3) -> void:
	if dying:
		return
	var game = get_tree().get_first_node_in_group("game")
	if game:
		game.add_points(int(clampf(amount * 2.0, 2.0, 10.0)))
	hp -= amount
	global_position += Vector3(dir.x, 0.0, dir.z) * amount * 0.008     # pesa mucho: apenas se mueve
	if hp <= 0.0:
		dying = true
		remove_from_group("zombies")
		if game:
			game.add_points(500)
			game.zombie_killed(self)
		var tw := create_tween()
		tw.tween_property(model, "rotation:x", deg_to_rad(-90.0), 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.6)
		tw.tween_property(model, "scale", Vector3.ZERO, 0.4)
		tw.tween_callback(queue_free)

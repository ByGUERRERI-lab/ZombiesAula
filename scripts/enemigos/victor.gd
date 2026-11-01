extends Node3D
# Víctor: el chorizo de la clase. Va a por el jugador más cercano corriendo
# encorvado, te mete mano al bolsillo y sale por patas con lo que te ha robado
# (un arma, Janes, una habilidad de la tienda o puntos). Corre más que tú andando
# pero menos que tu sprint: si le alcanzas y lo matas, suelta lo robado.
# Si pasa demasiado tiempo huyendo desaparece con el botín.

const U = preload("res://scripts/nucleo/util.gd")
const W = preload("res://scripts/jugador/weapons.gd")
const Ch = preload("res://scripts/jugador/character.gd")

const FLEE_SPEED := 8.2       # el sprint del jugador va a 9,6
const FLEE_TIME := 16.0       # segundos que tienes para pillarle
const POINTS := 250
# Nota de voz de Víctor al robarte; si no está el archivo, usa la risa de siempre
const VOZ_ROBO := "res://sonidos/victor_robo.ogg"

var player
var game
var hp := 24.0
var radius := 0.55
var speed := 7.2
var dying := false
var puppet := false           # copia de un enemigo que controla el anfitrión
var model: Node3D
var rig: Dictionary
var fleeing := false
var flee_t := FLEE_TIME
var flee_to := Vector3.ZERO
var loot := {}                # lo que lleva robado (vacío = nada)
var held: Node3D
var tag: Label3D
var snd: AudioStreamPlayer3D
var ph := 0.0
var run_k := 0.0
var last_pos := Vector3.ZERO


func _ready() -> void:
	add_to_group("zombies")
	add_to_group("victors")
	game = get_tree().get_first_node_in_group("game")
	var parts: Dictionary = Ch.build_victor(self)
	model = parts["model"]
	rig = parts["rig"]
	tag = Label3D.new()
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true         # se le ve a través de las paredes mientras huye
	tag.fixed_size = true
	tag.pixel_size = 0.0011
	tag.font_size = 26
	tag.outline_size = 8
	tag.modulate = Color(1.0, 0.8, 0.25)
	tag.position.y = 2.85
	tag.visible = false
	add_child(tag)
	snd = AudioStreamPlayer3D.new()
	if ResourceLoader.exists(VOZ_ROBO):
		snd.stream = load(VOZ_ROBO)
		snd.unit_size = 14.0      # que se le oiga bien aunque salga corriendo
		snd.max_db = 6.0
	else:
		snd.stream = U.make_laugh(1.5)
		snd.unit_size = 8.0
	snd.position.y = 2.0
	add_child(snd)
	last_pos = global_position
	if game:
		game.toast_small("¡Víctor anda suelto! Vigila tus bolsillos")


func _process(delta: float) -> void:
	if dying or delta <= 0.0:
		return
	# la animación sale de cómo se mueve, y así vale también para las copias en red
	var v := (global_position - last_pos).length() / delta
	last_pos = global_position
	run_k = move_toward(run_k, clampf(v / 4.0, 0.0, 1.0), 6.0 * delta)
	ph += 15.0 * delta
	Ch.run_pose(rig, ph, run_k)
	if not puppet:
		model.position.y = absf(sin(ph)) * 0.07 * run_k


func _physics_process(delta: float) -> void:
	if dying or puppet or U.stunned(self):
		return    # cegado por Jan, o copia en otro PC (la mueve el anfitrión)
	if fleeing:
		_flee(delta)
	elif player != null and not player.dead and not player.downed:
		_hunt(delta)


func _hunt(delta: float) -> void:
	var to_p: Vector3 = player.global_position - global_position
	to_p.y = 0.0
	if to_p.length() < radius + 0.8:
		_steal()
		return
	_run_to(player.global_position, speed, delta)


# Le mete la mano al bolsillo: el PC del jugador decide qué le quita y avisa
func _steal() -> void:
	fleeing = true
	flee_to = _flee_point()
	_laugh()
	if Net.online:
		game.net_victor_laugh(name)
	player.rob()


func _flee(delta: float) -> void:
	flee_t -= delta
	if flee_t <= 0.0:
		game.victor_escaped(self)
		return
	if Vector2(flee_to.x - global_position.x, flee_to.z - global_position.z).length() < 1.5:
		flee_to = _flee_point()
	_run_to(flee_to, FLEE_SPEED, delta)


# De varios sitios posibles, el que quede más lejos de quien lo persigue
func _flee_point() -> Vector3:
	var best := global_position
	var bd := -1.0
	for i in 5:
		var p: Vector3 = game._spawn_pos()
		var d: float = p.distance_squared_to(player.global_position)
		if d > bd:
			bd = d
			best = p
	return best


func _run_to(to: Vector3, spd: float, delta: float) -> void:
	var mv: Vector3 = U.next_point(global_position, to) - global_position
	mv.y = 0.0
	var dir := mv.normalized()
	rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 10.0 * delta)
	global_position = U.clamp_pos(global_position + dir * spd * delta, radius)


func _laugh() -> void:
	snd.pitch_scale = randf_range(0.97, 1.04)
	snd.play()


# Enseña en la mano lo que ha robado (en todos los PCs)
func take(item: Dictionary) -> void:
	loot = item
	if held != null:
		held.queue_free()
	var hand: Node3D = rig["hand"]
	held = Ch.build_loot(hand, item)
	held.position = Vector3(0.29, 0.78, -0.1)
	tag.text = "VÍCTOR  ·  " + W.loot_name(item)
	tag.visible = true


# Se esfuma con el botín
func vanish() -> void:
	dying = true
	remove_from_group("zombies")
	remove_from_group("victors")
	tag.visible = false
	if game:
		game.toast_small("Víctor se ha escapado con %s" % W.loot_name(loot, true) if not loot.is_empty() else "Víctor se ha escapado")
	var tw := create_tween()
	tw.tween_property(model, "scale", Vector3(0.1, 1.3, 0.1) * Ch.VICTOR_SCALE, 0.25)
	tw.tween_property(model, "scale", Vector3.ZERO, 0.1)
	tw.tween_callback(queue_free)


func hurt(amount: float, dir: Vector3) -> void:
	if dying:
		return
	if game:
		game.add_points(int(clampf(amount * 2.0, 2.0, 10.0)))
	hp -= amount
	global_position += Vector3(dir.x, 0.0, dir.z) * amount * 0.02
	if hp <= 0.0:
		dying = true
		remove_from_group("zombies")
		remove_from_group("victors")
		tag.visible = false
		if game:
			game.add_points(POINTS)
			game.zombie_killed(self)
			if not loot.is_empty():
				game.drop_loot(U.clamp_pos(global_position, 0.5), loot)
		if held != null:
			held.visible = false
		var tw := create_tween()
		tw.tween_property(model, "rotation:x", deg_to_rad(80.0), 0.3)
		tw.tween_interval(0.4)
		tw.tween_property(model, "scale", Vector3.ZERO, 0.3)
		tw.tween_callback(queue_free)

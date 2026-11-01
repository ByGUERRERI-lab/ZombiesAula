extends Node3D
# Granada cegadora "Jan": un Jan en miniatura y sin gorra que sale volando,
# rebota por el suelo y las paredes y, al rato, su calva pega un destello
# que ciega a todo el que la esté mirando: enemigos, Xavier... y jugadores
# (tú también, si no apartas la vista). No hace daño.
# Cada PC simula su copia: el anfitrión ciega a los enemigos y cada uno
# calcula si su propio jugador se queda cegado.

const U = preload("res://scripts/nucleo/util.gd")
const Ch = preload("res://scripts/jugador/character.gd")

const MINI := 0.26          # tamaño del muñeco (Jan mide 1,75 m -> 45 cm)
const FUSE := 1.5           # segundos desde que sale de la mano hasta el destello
const RANGE := 22.0         # hasta dónde ciega
const ENEMY_RANGE := 14.0

var vel := Vector3.ZERO
var fuse := FUSE
var resting := false
var done := false
var game
var parts: Dictionary
var bald_m: StandardMaterial3D
var spin := Vector3.ZERO


func _ready() -> void:
	game = get_tree().get_first_node_in_group("game")
	var holder := Node3D.new()
	holder.scale = Vector3.ONE * MINI
	holder.position.y = -0.03
	add_child(holder)
	parts = Ch.build_jan(holder)
	parts["cap"].visible = false              # la gorra se la ha quitado antes de lanzarse
	bald_m = parts["bald_m"]
	spin = Vector3(randf_range(8.0, 12.0), randf_range(-4.0, 4.0), randf_range(-3.0, 3.0))


func _physics_process(delta: float) -> void:
	if done:
		return
	fuse -= delta
	# la calva se va calentando antes de explotar
	var k := 1.0 - fuse / FUSE
	bald_m.emission_energy_multiplier = k * k * 2.0 + (0.6 if fmod(fuse, 0.3) < 0.15 and fuse < 0.6 else 0.0)
	if fuse <= 0.0:
		_flash()
		return
	if resting:
		rotation = rotation.lerp(Vector3(0, rotation.y, 0), minf(1.0, 10.0 * delta))
		return
	vel.y -= 14.0 * delta
	var from := global_position
	var to := from + vel * delta
	var q := PhysicsRayQueryParameters3D.create(from + Vector3(0, 0.05, 0), to + Vector3(0, 0.05, 0))
	var ex: Array[RID] = []
	for p in get_tree().get_nodes_in_group("players"):
		if p is CollisionObject3D:
			ex.append(p.get_rid())
	q.exclude = ex
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		global_position = to
		rotation += spin * delta
		return
	# rebote contra suelo, paredes o muebles
	var n: Vector3 = hit["normal"]
	global_position = hit["position"] + n * 0.02 - Vector3(0, 0.05, 0)
	vel = vel.bounce(n) * 0.45
	spin *= 0.5
	if n.y > 0.7 and vel.length() < 1.6:
		resting = true             # se queda de pie en el suelo, mirando al frente
		vel = Vector3.ZERO
		global_position.y = hit["position"].y


func _flash() -> void:
	done = true
	var head_pos: Vector3 = global_position + Vector3(0, 0.4, 0)
	bald_m.emission_energy_multiplier = 25.0
	# luz enorme y una bola blanca que se expande
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 1.0, 0.92)
	l.light_energy = 40.0
	l.omni_range = RANGE
	add_child(l)
	l.global_position = head_pos
	var ball := U.sphere(self, 0.3, Vector3.ZERO, Color(1, 1, 0.95), true)
	ball.global_position = head_pos
	ball.material_override.emission_energy_multiplier = 8.0
	ball.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tw := create_tween()
	tw.tween_property(ball, "scale", Vector3.ONE * 9.0, 0.25)
	tw.parallel().tween_property(ball.material_override, "albedo_color:a", 0.0, 0.25)
	tw.parallel().tween_property(l, "light_energy", 0.0, 1.2)
	tw.parallel().tween_property(bald_m, "emission_energy_multiplier", 0.0, 2.0)
	tw.tween_interval(1.5)
	tw.tween_property(self, "scale", Vector3.ONE * 0.01, 0.3)     # Jan se va (con su calva)
	tw.tween_callback(queue_free)
	var snd := AudioStreamPlayer3D.new()
	snd.stream = U.make_ting()
	snd.unit_size = 18.0
	snd.max_db = 6.0
	add_child(snd)
	snd.play()

	var space := get_world_3d().direct_space_state
	# enemigos y Xavier: los que tengan la calva a la vista se quedan cegados
	for e in get_tree().get_nodes_in_group("zombies") + get_tree().get_nodes_in_group("npcs"):
		if e.get("dying"):
			continue
		var ep: Vector3 = e.global_position + Vector3(0, 1.4, 0)
		var d := ep.distance_to(head_pos)
		if d < ENEMY_RANGE and _clear(space, head_pos, ep):
			U.stun(e, lerpf(5.0, 2.5, d / ENEMY_RANGE))

	# el jugador de este PC: cuánto le ciega depende de si estaba mirando y de lo cerca
	var p = game.player
	if p == null or p.dead:
		return
	var eye: Vector3 = p.cam.global_position
	var dist := eye.distance_to(head_pos)
	if dist > RANGE or not _clear(space, head_pos, eye):
		return
	var look: Vector3 = -p.cam.global_transform.basis.z
	var facing := look.dot((head_pos - eye).normalized())     # 1 = mirándola de frente
	var amount := lerpf(0.3, 1.0, clampf((facing + 0.2) / 0.9, 0.0, 1.0)) * lerpf(1.0, 0.35, dist / RANGE)
	game.blind(amount)


# true si no hay paredes entre a y b
func _clear(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b)
	var ex: Array[RID] = []
	for p in get_tree().get_nodes_in_group("players"):
		if p is CollisionObject3D:
			ex.append(p.get_rid())
	q.exclude = ex
	return space.intersect_ray(q).is_empty()

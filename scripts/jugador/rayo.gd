extends Node3D
# Proyectil que explota al chocar: la bola verde de la Pistola Rayo, el cohete del
# lanzacohetes o el virote de la ballesta ("proj" en weapons.gd). Vuela hacia donde
# apuntas (también hacia arriba o hacia el suelo). La explosión daña a todos los
# enemigos cercanos, pero nunca al jugador que ha disparado.

const U = preload("res://scripts/nucleo/util.gd")
const W = preload("res://scripts/jugador/weapons.gd")
const VS_SPLASH := 4.0       # en todos contra todos la explosión hace dmg x esto a otros jugadores

var vel := Vector3.ZERO
var shooter                  # el jugador que dispara (nunca se hace daño a sí mismo)
var visual_only := false     # copia de otro PC: se ve y explota, pero no hace daño
var life := 2.0
var direct_dmg := 8.0
var splash_dmg := 14.0
var splash_r := 3.0
var done := false
var game
var arma := "pistola_rayo"
var color := Color(0.3, 1.0, 0.45)
var humo_t := 0.0


func _ready() -> void:
	game = get_tree().get_first_node_in_group("game")
	var d: Dictionary = W.DATA.get(arma, W.DATA["pistola_rayo"])
	direct_dmg = d["dmg"]
	splash_dmg = d["splash_dmg"]
	splash_r = d["splash_r"]
	match str(d.get("proj", "energia")):
		"cohete":
			color = Color(1.0, 0.55, 0.15)
			var cuerpo := Node3D.new()
			add_child(cuerpo)
			if vel.length() > 0.1 and absf(vel.normalized().y) < 0.99:
				cuerpo.basis = Basis.looking_at(vel.normalized(), Vector3.UP)
			U.tube(cuerpo, 0.045, 0.4, Vector3(0, 0, 0.05), U.mat(Color(0.35, 0.38, 0.3)))
			var cab := U.cone_m(cuerpo, 0.0, 0.045, 0.14, Vector3(0, 0, -0.22), U.mat(Color(0.3, 0.3, 0.32)))
			cab.rotation_degrees.x = -90.0
			var fuego := U.sphere(cuerpo, 0.08, Vector3(0, 0, 0.3), Color(1.0, 0.7, 0.2), true)
			fuego.material_override.emission_energy_multiplier = 4.0
		"virote":
			color = Color(1.0, 0.5, 0.15)
			var cuerpo := Node3D.new()
			add_child(cuerpo)
			if vel.length() > 0.1 and absf(vel.normalized().y) < 0.99:
				cuerpo.basis = Basis.looking_at(vel.normalized(), Vector3.UP)
			U.tube(cuerpo, 0.008, 0.45, Vector3.ZERO, U.mat(Color(0.5, 0.4, 0.3)))
			U.sphere(cuerpo, 0.025, Vector3(0, 0, -0.23), Color(1.0, 0.45, 0.1), true)
		_:
			U.sphere(self, 0.13, Vector3.ZERO, Color(0.3, 1.0, 0.45), true)
			var core := U.sphere(self, 0.07, Vector3.ZERO, Color(0.9, 1.0, 0.9), true)
			core.material_override.emission_energy_multiplier = 3.0
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = 2.5
	l.omni_range = 4.0
	add_child(l)


func _physics_process(delta: float) -> void:
	if done:
		return
	var from := global_position
	var to := from + vel * delta
	life -= delta
	# choque con paredes, suelo, techo o muebles
	var q := PhysicsRayQueryParameters3D.create(from, to)
	if shooter != null and is_instance_valid(shooter) and shooter is CollisionObject3D:
		q.exclude = [shooter.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	# impacto directo contra un enemigo
	for z in get_tree().get_nodes_in_group("zombies"):
		if z.dying:
			continue
		var zp: Vector3 = z.global_position
		var dx := to.x - zp.x
		var dz := to.z - zp.z
		if dx * dx + dz * dz < z.radius * z.radius and to.y > zp.y and to.y < zp.y + 2.6:
			if not visual_only:
				game.damage_enemy(z, direct_dmg, vel.normalized())
			_explode(to)
			return
	# impacto directo contra otro jugador (todos contra todos)
	if Net.mode == "versus":
		for p in get_tree().get_nodes_in_group("players"):
			if p == shooter or not p.can_be_hit():
				continue
			var pp: Vector3 = p.global_position
			if Vector2(to.x - pp.x, to.z - pp.z).length() < 0.45 and to.y > pp.y and to.y < pp.y + 1.9:
				_explode(to)
				return
	if not hit.is_empty():
		_explode(hit["position"] - vel.normalized() * 0.05)
		return
	if to.y <= 0.02 or life <= 0.0:
		_explode(Vector3(to.x, maxf(to.y, 0.05), to.z))
		return
	global_position = to
	# estela de humo del cohete
	if arma == "lanzacohetes":
		humo_t -= delta
		if humo_t <= 0.0:
			humo_t = 0.03
			var h := U.sphere(get_parent(), 0.12, global_position, Color(0.7, 0.7, 0.7, 0.5))
			h.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var tw := h.create_tween().set_parallel(true)
			tw.tween_property(h, "scale", Vector3.ONE * 3.0, 0.7)
			tw.tween_property(h.material_override, "albedo_color:a", 0.0, 0.7)
			tw.chain().tween_callback(h.queue_free)


func _explode(pos: Vector3) -> void:
	done = true
	global_position = pos
	for c in get_children():
		c.queue_free()
	# bola verde que se expande y se desvanece
	var s := U.sphere(get_parent(), 1.0, pos, Color(color.r, color.g, color.b, 0.75), true)
	s.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	s.material_override.emission_energy_multiplier = 2.5
	s.scale = Vector3.ONE * 0.2
	var tw := s.create_tween().set_parallel(true)
	tw.tween_property(s, "scale", Vector3.ONE * splash_r, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tw.tween_property(s.material_override, "albedo_color:a", 0.0, 0.35)
	tw.chain().tween_callback(s.queue_free)
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = 8.0
	l.omni_range = splash_r * 2.5
	get_parent().add_child(l)
	l.global_position = pos + Vector3(0, 0.3, 0)
	l.create_tween().tween_property(l, "light_energy", 0.0, 0.35).finished.connect(l.queue_free)
	var snd := AudioStreamPlayer3D.new()
	snd.stream = U.make_shot(0.7 if arma == "lanzacohetes" else 0.45, true)
	snd.unit_size = 10.0
	get_parent().add_child(snd)
	snd.global_position = pos
	snd.play()
	snd.finished.connect(snd.queue_free)
	# marca quemada en el suelo
	if pos.y < 0.3:
		var mark := U.cylinder(get_parent(), splash_r * 0.35, 0.01, Vector3(pos.x, 0.012, pos.z), Color(0.08, 0.2, 0.1) if arma == "pistola_rayo" else Color(0.06, 0.05, 0.05))
		get_tree().create_timer(4.0).timeout.connect(mark.queue_free)

	if not visual_only:
		# daño en área: más cuanto más cerca del centro; al que dispara, nada
		for z in get_tree().get_nodes_in_group("zombies"):
			if z.dying:
				continue
			var c: Vector3 = z.global_position + Vector3(0, 1.0, 0)
			var d := c.distance_to(pos)
			if d < splash_r + z.radius:
				var k := clampf(1.0 - 0.6 * maxf(d - z.radius, 0.0) / splash_r, 0.4, 1.0)
				var away := (c - pos)
				away.y = 0.0
				game.damage_enemy(z, splash_dmg * k, away.normalized() if away.length() > 0.01 else Vector3.FORWARD)
		if Net.mode == "versus" and shooter != null:
			for p in get_tree().get_nodes_in_group("players"):
				if p == shooter or not p.can_be_hit():
					continue
				var d2: float = (p.global_position + Vector3(0, 1.0, 0)).distance_to(pos)
				if d2 < splash_r:
					var k2 := clampf(1.0 - 0.6 * d2 / splash_r, 0.4, 1.0)
					p.hurt(splash_dmg * VS_SPLASH * k2, shooter.peer_id)
	get_tree().create_timer(0.5).timeout.connect(queue_free)

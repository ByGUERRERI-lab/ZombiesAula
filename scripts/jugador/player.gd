extends CharacterBody3D
# Jugador en primera persona (V = tercera persona). Hasta 2 armas de fuego + katana.
# En red: el jugador local se controla con teclado y ratón y envía su estado;
# los de los demás PCs son "marionetas" que siguen lo que llega por la red.

const U = preload("res://scripts/nucleo/util.gd")
const W = preload("res://scripts/jugador/weapons.gd")
const Ch = preload("res://scripts/jugador/character.gd")
const RayScript = preload("res://scripts/jugador/rayo.gd")
const JanScript = preload("res://scripts/jugador/jan_bang.gd")
const SustoScript = preload("res://scripts/enemigos/susto_victor.gd")
const KatanaScene = preload("res://modelos/katana.glb")

const SPEED := 6.0
const SPRINT := 1.6            # con Shift corres un 60 % más (9,6)
const SPRINT_TIME := 6.0      # segundos de sprint con la barra llena...
const SPRINT_BACK := 9.0      # ...y los que tarda en llenarse otra vez
const SENS := 0.0025
const BLEED_TIME := 30.0      # segundos caído antes de morir (cooperativo)
const VS_MULT := 8.0          # multiplicador de daño entre jugadores (todos contra todos)
const JAN_START := 2          # granadas Jan al empezar (y al reaparecer)
const JAN_MAX := 4
const SUSTO_CHANCE := 0.3      # el primer robo de cada mapa asusta siempre; los demás, a veces
const CAFE_RELOAD := 0.5      # con café recargas en la mitad de tiempo...
const CAFE_FIRE := 0.75       # ...y disparas un 25 % más rápido
const HEAD_MULT := 2.5        # daño de un disparo a la cabeza
const JAN_IDLE := Vector3(0.17, 1.3, -0.48)    # Jan en la mano
const JAN_UP := Vector3(0.07, 1.44, -0.5)      # levantado, quitándose la gorra

var hp := 100.0
var dead := false
var downed := false           # caído esperando a que le reanimen
var bleed := 0.0
var since_hit := 10.0
var knock := Vector3.ZERO:
	set(v):
		if is_local or not Net.running:
			knock = v
		else:
			_net_knock.rpc_id(peer_id, v)
var slots: Array = [null, null]     # cada una: {"id", "mag", "reserve"}
var cur := 0                         # 0 y 1 = armas de fuego, 2 = katana, 3 = granada Jan
var jan_count := JAN_START
var jan_charge := -1.0               # >= 0 mientras mantienes el clic (Jan sin gorra)
var jan_hold: Node3D                 # Jan en miniatura en la mano
var jan_cap: Node3D
var jan_tween: Tween
# Habilidades de la tienda de Juan Carlos (se pierden al caer o morir)
var porro_t := 0.0                   # segundos de colocón que quedan
var cafe_t := 0.0                    # segundos de café que quedan
var has_gta := false
var perks: Array = []                # bebidas de las máquinas (bebidas.gd): "tanque", "rapida", "doble", "revivir", "turbo"
var autorevive_t := 0.0
var dios := false                    # consola: no te hacen daño
var aim_y := 0.0                     # altura de los ojos al disparar...
var aim_slope := 0.0                 # ...y cuánto sube o baja el disparo por metro (según miras arriba o abajo)
var snd_head: AudioStreamPlayer              # > 0 mientras te levantas solo con el Zumo Revivo
# Sprint (carrera del vídeo de clase, ver Ch.run_pose)
var sprinting := false
var stamina := 1.0                   # de 0 a 1
var tired := false                   # te has quedado sin aire: hay que recuperar un poco
var run_k := 0.0                     # 0 de pie, 1 corriendo a tope
var run_ph := 0.0
var run_on := false
var max_hp := 100.0
var reload_t := 0.0
var reload_slot := 0
var cooldown := 0.0
var prev_lmb := false
var aim_dir := Vector3(0, 0, -1)
var cam: Camera3D
var head_pivot: Node3D
var pitch := 0.0
var third_person := false
var frozen := false
var input_blocked := false           # menú de pausa abierto en una partida online
var flashlight: SpotLight3D
var snd_shot: AudioStreamPlayer
var snd_swing: AudioStreamPlayer
var snd_cache := {}
var model: Node3D
var head_node: Node3D
var rig: Dictionary
var gun_holder: Node3D
var gun_models := {}
var katana_pivot: Node3D
var swing_tween: Tween

# Red
var peer_id := 1
var is_local := true
var skin_data: Dictionary = {}
var display_name := ""
var tag: Label3D
var game
var send_t := 0.0
var net_pos := Vector3.ZERO
var net_rot := 0.0
var net_weapon := "pistola"
var snd_remote: AudioStreamPlayer3D


func _ready() -> void:
	add_to_group("players")
	if is_local:
		add_to_group("player")
	game = get_tree().get_first_node_in_group("game")
	set_multiplayer_authority(peer_id)
	if skin_data.is_empty():
		skin_data = Ch.skin
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	if not is_local:
		collision_layer = 0          # los compañeros no te bloquean el paso
		collision_mask = 0
	_build_model()

	# Cámara en primera persona (a la altura de los ojos)
	head_pivot = Node3D.new()
	head_pivot.position = Vector3(0, 1.62, -0.08)
	add_child(head_pivot)
	cam = Camera3D.new()
	cam.fov = 75.0
	cam.near = 0.05
	head_pivot.add_child(cam)
	if is_local:
		cam.current = true
		cam.set_cull_mask_value(2, false)

	# Linterna (tecla F): en CESUR empiezas con ella encendida, es de noche
	flashlight = SpotLight3D.new()
	flashlight.light_color = Color(1.0, 0.94, 0.82)
	flashlight.light_energy = 4.0
	flashlight.spot_range = 30.0
	flashlight.spot_angle = 26.0
	flashlight.spot_attenuation = 0.8
	flashlight.shadow_enabled = is_local
	flashlight.light_volumetric_fog_energy = 2.0
	flashlight.visible = game.mapa == null
	flashlight.position = Vector3(0.22, -0.22, 0.05)
	cam.add_child(flashlight)

	# Sonidos generados por código
	snd_shot = AudioStreamPlayer.new()
	snd_shot.volume_db = 2.0
	add_child(snd_shot)
	snd_swing = AudioStreamPlayer.new()
	snd_swing.stream = U.make_shot(0.18, false)
	snd_swing.volume_db = -14.0
	add_child(snd_swing)
	snd_remote = AudioStreamPlayer3D.new()
	snd_remote.unit_size = 8.0
	snd_remote.position.y = 1.3
	add_child(snd_remote)

	# Nombre encima de la cabeza de los demás jugadores
	if not is_local:
		tag = Label3D.new()
		tag.text = display_name
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = Net.mode == "coop"
		tag.fixed_size = true
		tag.pixel_size = 0.0011
		tag.font_size = 26
		tag.outline_size = 8
		tag.modulate = Color(0.4, 1.0, 0.5) if Net.mode == "coop" else Color(1.0, 0.35, 0.3)
		tag.position.y = 2.15
		add_child(tag)
		net_pos = position
		net_rot = rotation.y

	slots[0] = _new_weapon("pistola")
	_select(0, true)


func _input(event: InputEvent) -> void:
	if not is_local:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not dead and not frozen and not input_blocked:
		rotation.y -= event.relative.x * SENS
		pitch = clampf(pitch - event.relative.y * SENS, deg_to_rad(-80.0), deg_to_rad(80.0))
		head_pivot.rotation.x = pitch
	elif event is InputEventKey and event.pressed and not event.echo and not input_blocked:
		if event.keycode == KEY_F:
			flashlight.visible = not flashlight.visible
		elif event.keycode == KEY_V:
			third_person = not third_person
			cam.set_cull_mask_value(2, third_person)
			if third_person:
				cam.position = Vector3(0.0, 0.5, 3.2)
			else:
				cam.position = Vector3.ZERO
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not dead and not input_blocked:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_model() -> void:
	var parts: Dictionary = Ch.build_player(self, skin_data)
	model = parts["model"]
	head_node = parts["head"]
	rig = parts["rig"]
	if is_local:
		U.set_layer(head_node, 2)      # tu propia cabeza solo se ve en tercera persona
		if parts.has("cuerpo3d"):
			U.set_layer(parts["cuerpo3d"], 2)    # avatar 3D: en primera persona no te ves por dentro

	# Sitio donde se coloca el arma de fuego equipada
	gun_holder = Node3D.new()
	gun_holder.position = Vector3(0.22, 1.1, -0.45)
	if parts.has("arma_pos"):
		gun_holder.position = parts["arma_pos"]
	var hand: Node3D = rig["hand"]     # todo lo que empuñas se mueve con el brazo
	hand.add_child(gun_holder)

	# Katana
	katana_pivot = Node3D.new()
	katana_pivot.position = Vector3(0.17, 1.07, -0.52)     # entre las dos manos
	hand.add_child(katana_pivot)
	var katana: Node3D = KatanaScene.instantiate()
	katana.scale = Vector3.ONE * 1.25
	# el modelo apunta a +Y: punta hacia delante y arriba, con la cara de la hoja hacia la cámara
	katana.rotation_degrees = Vector3(-62.0, 20.0, 0.0)
	katana.rotate_object_local(Vector3.UP, deg_to_rad(68.0))
	katana_pivot.add_child(katana)
	# Acero menos espejo: si no, la hoja coge el color del suelo y no se distingue
	var blade: MeshInstance3D = katana.find_child("Hoja", true, false)
	var steel: StandardMaterial3D = blade.mesh.surface_get_material(0).duplicate()
	steel.metallic = 0.45
	steel.roughness = 0.3
	blade.material_override = steel
	katana_pivot.visible = false

	# Granada Jan: en miniatura en la mano, mirándote a la cara
	jan_hold = Node3D.new()
	jan_hold.position = JAN_IDLE
	jan_hold.rotation_degrees.y = 180.0
	hand.add_child(jan_hold)
	var mini := Node3D.new()
	mini.scale = Vector3.ONE * 0.07
	jan_hold.add_child(mini)
	jan_cap = Ch.build_jan(mini)["cap"]
	jan_hold.visible = false


# Vuelve a construir el aspecto (tras cambiar la ropa en el menú)
func refresh_look() -> void:
	if model != null:
		model.free()
	if is_local:
		skin_data = Ch.skin
	gun_models.clear()
	_build_model()
	run_on = false       # si ibas corriendo, _run_anim vuelve a ocultar el cuerpo nuevo
	_select(cur, true)


# ---------------- Sistema de armas ----------------
func _new_weapon(id: String) -> Dictionary:
	var d: Dictionary = W.DATA[id]
	return {"id": id, "mag": d["mag"], "reserve": d["reserve"]}


func _gun_node(id: String) -> Node3D:
	if not gun_models.has(id):
		var g := U.gun_model(id)
		U.toonify(g, 0.006)
		g.visible = false
		gun_holder.add_child(g)
		gun_models[id] = g
	return gun_models[id]


func _select(i: int, force: bool = false) -> void:
	if i < 2 and slots[i] == null:
		return
	if i == cur and not force:
		return
	if i == 3 and jan_count <= 0:
		return
	cur = i
	reload_t = 0.0
	gun_holder.rotation.x = 0.0
	for gid in gun_models:
		gun_models[gid].visible = false
	katana_pivot.visible = (cur == 2)
	_jan_reset()
	jan_hold.visible = (cur == 3)
	if cur < 2:
		var id: String = slots[cur]["id"]
		_gun_node(id).visible = true


# Para las marionetas: enseña el arma que lleva el jugador remoto
func _show_weapon(id: String) -> void:
	for gid in gun_models:
		gun_models[gid].visible = false
	katana_pivot.visible = (id == "katana")
	jan_hold.visible = (id == "jan")
	if id != "katana" and W.DATA.has(id):
		_gun_node(id).visible = true


func current_weapon_id() -> String:
	if cur == 3:
		return "jan"
	if cur == 2 or slots[cur] == null:
		return "katana"
	return slots[cur]["id"]


func has_weapon(id: String) -> bool:
	for s in slots:
		if s != null and s["id"] == id:
			return true
	return false


func ammo_full(id: String) -> bool:
	for s in slots:
		if s != null and s["id"] == id:
			var d: Dictionary = W.DATA[id]
			return s["mag"] >= d["mag"] and s["reserve"] >= d["reserve"]
	return true


func refill_ammo(id: String) -> void:
	for s in slots:
		if s != null and s["id"] == id:
			var d: Dictionary = W.DATA[id]
			s["mag"] = d["mag"]
			s["reserve"] = d["reserve"]


# Da un arma: si ya la tiene recarga munición; si hay hueco la añade; si no, sustituye la actual
func give_weapon(id: String) -> void:
	if has_weapon(id):
		refill_ammo(id)
		return
	var target := 0
	if slots[0] == null:
		target = 0
	elif slots[1] == null:
		target = 1
	elif cur < 2:
		target = cur
	slots[target] = _new_weapon(id)
	_select(target, true)


func _start_reload() -> void:
	if reload_t > 0.0 or cur > 1:
		return
	var s = slots[cur]
	var d: Dictionary = W.DATA[s["id"]]
	if s["mag"] >= d["mag"] or s["reserve"] <= 0:
		return
	reload_t = d["reload"] * (CAFE_RELOAD if cafe_t > 0.0 else 1.0) * (0.5 if has_perk("rapida") else 1.0)
	reload_slot = cur
	var tw := create_tween()
	tw.tween_property(gun_holder, "rotation:x", deg_to_rad(-40.0), 0.2)
	tw.tween_interval(maxf(reload_t - 0.4, 0.1))
	tw.tween_property(gun_holder, "rotation:x", 0.0, 0.2)


func _finish_reload() -> void:
	var s = slots[reload_slot]
	if s == null:
		return
	var d: Dictionary = W.DATA[s["id"]]
	var take: int = mini(int(d["mag"]) - int(s["mag"]), int(s["reserve"]))
	s["mag"] += take
	s["reserve"] -= take


func _physics_process(delta: float) -> void:
	_run_anim(delta)
	if not is_local:
		_puppet(delta)
		return
	_send_state(delta)
	if dead:
		return
	if downed:
		bleed -= delta
		if bleed <= 0.0:
			_die()
		return
	if autorevive_t > 0.0:
		autorevive_t -= delta
		sprinting = false
		if autorevive_t <= 0.0:
			hp = max_hp
			since_hit = 3.0
			_set_pose(0)
			game.toast_small("¡Te has levantado con el Zumo Revivo!")
		return
	if frozen:
		sprinting = false
		return
	cooldown = maxf(0.0, cooldown - delta)
	since_hit += delta
	porro_t = maxf(0.0, porro_t - delta)
	cafe_t = maxf(0.0, cafe_t - delta)
	var high := porro_t > 0.0
	var revivo := has_perk("revivir")
	if since_hit > (2.0 if high or revivo else 5.0) and hp < max_hp:
		hp = minf(max_hp, hp + (45.0 if high else (35.0 if revivo else 20.0)) * delta * (2.0 if has_perk("tanque") else 1.0))

	# Movimiento WASD relativo a hacia dónde miras
	var d := Vector3.ZERO
	if not input_blocked:
		if Input.is_key_pressed(KEY_W): d.z -= 1.0
		if Input.is_key_pressed(KEY_S): d.z += 1.0
		if Input.is_key_pressed(KEY_A): d.x -= 1.0
		if Input.is_key_pressed(KEY_D): d.x += 1.0
	d = (global_transform.basis * d.normalized())
	_update_sprint(delta)
	var turbo := has_perk("turbo")
	var spd := SPEED * (1.3 if has_gta else 1.0) * (1.08 if turbo else 1.0) * ((SPRINT + (0.25 if turbo else 0.0)) if sprinting else 1.0)
	velocity.x = d.x * spd + knock.x
	velocity.z = d.z * spd + knock.z
	knock = knock.lerp(Vector3.ZERO, 8.0 * delta)
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= 25.0 * delta
	move_and_slide()

	# Dirección de ataque = hacia donde miras (en horizontal)
	aim_dir = -global_transform.basis.z
	aim_dir.y = 0.0
	aim_dir = aim_dir.normalized()
	if input_blocked:
		return

	# Cambio de arma y recarga
	if Input.is_key_pressed(KEY_1): _select(0)
	if Input.is_key_pressed(KEY_2): _select(1)
	if Input.is_key_pressed(KEY_3): _select(2)
	if Input.is_key_pressed(KEY_4) or Input.is_key_pressed(KEY_G): _select(3)
	if Input.is_key_pressed(KEY_R) and cur < 2:
		_start_reload()
	if reload_t > 0.0:
		reload_t -= delta
		if reload_t <= 0.0:
			_finish_reload()

	# Disparo / ataque
	var lmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var just := lmb and not prev_lmb
	prev_lmb = lmb
	if cur == 3:
		_jan_input(lmb, delta)
	elif lmb and cooldown <= 0.0:
		if cur == 2:
			_slash()
		else:
			var wd: Dictionary = W.DATA[slots[cur]["id"]]
			if wd["auto"] or just:
				_shoot()


# Shift + W para correr. Disparar o lanzar a Jan corta el sprint.
func _update_sprint(delta: float) -> void:
	var attacking := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or jan_charge >= 0.0
	sprinting = Input.is_key_pressed(KEY_SHIFT) and Input.is_key_pressed(KEY_W) and not Input.is_key_pressed(KEY_S) \
			and not input_blocked and not attacking and not tired
	if sprinting:
		stamina -= delta / (SPRINT_TIME * (2.0 if has_perk("turbo") else 1.0))
		if stamina <= 0.0:
			stamina = 0.0
			tired = true
			sprinting = false
	else:
		stamina = minf(1.0, stamina + delta / SPRINT_BACK)
		if tired and stamina >= 0.3:
			tired = false


func _run_anim(delta: float) -> void:
	run_k = move_toward(run_k, 1.0 if sprinting else 0.0, 7.0 * delta)
	if run_k <= 0.0 and not run_on:
		return
	if run_on != (run_k > 0.0):
		_hide_body(run_k > 0.0)
	run_on = run_k > 0.0
	run_ph += 15.0 * delta
	Ch.run_pose(rig, run_ph, run_k)
	model.position.y = (absf(sin(run_ph)) * 0.07 - 0.05) * run_k
	if is_local:
		# en primera persona: cámara agachada, balanceo y más campo de visión
		cam.fov = 75.0 + 10.0 * run_k
		head_pivot.position = Vector3(sin(run_ph) * 0.04 * run_k, 1.62 - (0.2 - absf(cos(run_ph)) * 0.05) * run_k, -0.08 - 0.16 * run_k)
		head_pivot.rotation.z = sin(run_ph) * 0.02 * run_k


# Al encorvarse el tronco se te pondría delante de la cámara: en primera persona
# se oculta como la cabeza (en tercera persona y para los demás se sigue viendo)
func _hide_body(on: bool) -> void:
	if is_local:
		U.set_layer(rig["spine"], 2 if on else 1)
		U.set_layer(head_node, 2)


func _stop_run() -> void:
	sprinting = false
	run_k = 0.0
	if run_on:
		_hide_body(false)
	run_on = false
	Ch.run_pose(rig, 0.0, 0.0)
	if is_local:
		cam.fov = 75.0
		head_pivot.position.x = 0.0
		head_pivot.position.z = -0.08


func _snd(id: String) -> AudioStreamWAV:
	if not snd_cache.has(id):
		var d: Dictionary = W.DATA[id]
		snd_cache[id] = U.make_shot(d["snd"], d["low"])
	return snd_cache[id]


func _shoot() -> void:
	if reload_t > 0.0:
		return
	var s = slots[cur]
	var id: String = s["id"]
	var d: Dictionary = W.DATA[id]
	if s["mag"] <= 0:
		_start_reload()
		return
	s["mag"] -= 1
	cooldown = d["cd"] * (CAFE_FIRE if cafe_t > 0.0 else 1.0) * (0.7 if has_perk("doble") else 1.0)
	if d.get("explode", false):
		_fire_ray(d)
	else:
		_fire_bullets(id, d)
	snd_shot.stream = _snd(id)
	snd_shot.play()
	var gm: Node3D = _gun_node(id)
	gm.position.z = 0.1
	create_tween().tween_property(gm, "position:z", 0.0, 0.12)
	if s["mag"] <= 0 and s["reserve"] > 0:
		_start_reload()


# Pistola Rayo: bola de energía hacia donde miras (con la inclinación de la cámara)
func _fire_ray(d: Dictionary) -> void:
	var basis_h: Basis = head_pivot.global_transform.basis
	var dir := -basis_h.z
	var origin: Vector3 = head_pivot.global_position + dir * 0.6 + basis_h.x * 0.15 - basis_h.y * 0.12
	var vel: Vector3 = dir.rotated(Vector3.UP, deg_to_rad(randf_range(-0.5, 0.5))) * float(d["speed"])
	_spawn_ray(origin, vel, false)
	_fx_shot(origin, PackedVector3Array(), d["tracer"], "pistola_rayo")
	if Net.running and Net.online:
		_net_ray.rpc(origin, vel)


func _spawn_ray(origin: Vector3, vel: Vector3, visual: bool) -> void:
	var r = RayScript.new()
	r.shooter = self
	r.visual_only = visual
	r.vel = vel
	get_parent().add_child(r)
	r.global_position = origin


@rpc("authority", "unreliable")
func _net_ray(origin: Vector3, vel: Vector3) -> void:
	_spawn_ray(origin, vel, true)
	_fx_shot(origin, PackedVector3Array(), Color(0.2, 1.0, 0.4), "pistola_rayo")


func _fire_bullets(id: String, d: Dictionary) -> void:
	var origin := global_position + Vector3(0, 1.3, 0) + aim_dir * 0.9
	# inclinación real de la mirada, para saber a qué altura llega la bala (disparos a la cabeza)
	var d3: Vector3 = -head_pivot.global_transform.basis.z
	aim_y = head_pivot.global_position.y
	aim_slope = d3.y / maxf(Vector2(d3.x, d3.z).length(), 0.05)
	var ends := PackedVector3Array()
	for i in int(d["pellets"]):
		var sp := float(d["spread"])
		var ang := deg_to_rad(randf_range(-sp, sp))
		ends.append(_pellet(origin, aim_dir.rotated(Vector3.UP, ang), float(d["dmg"]) * (2.0 if has_perk("doble") else 1.0), float(d["range"]), d["pierce"]))
	_fx_shot(origin, ends, d["tracer"], id)
	if Net.running and Net.online:
		_net_shot.rpc(origin, ends, d["tracer"], id)


# Calcula a quién da un perdigón y devuelve dónde acaba la trazadora
func _pellet(origin: Vector3, dir: Vector3, dmg: float, rng: float, pierce: bool) -> Vector3:
	var hits: Array = []
	for z in get_tree().get_nodes_in_group("zombies"):
		if z.dying:
			continue
		var rel: Vector3 = z.global_position - origin
		rel.y = 0.0
		var t := rel.dot(dir)
		if t < 0.0 or t > rng:
			continue
		var perp := (rel - dir * t).length()
		if perp < z.radius:
			hits.append([t, z, false, _es_cabeza(z, t, perp)])
	if Net.mode == "versus":
		for p in get_tree().get_nodes_in_group("players"):
			if p == self or not p.can_be_hit():
				continue
			var rel2: Vector3 = p.global_position - origin
			rel2.y = 0.0
			var t2 := rel2.dot(dir)
			if t2 < 0.0 or t2 > rng:
				continue
			if (rel2 - dir * t2).length() < 0.45:
				hits.append([t2, p, true])
	# dianas de las pruebas de habilidad (investigacion.gd): solo las ve quien hace la prueba
	for dn in get_tree().get_nodes_in_group("dianas"):
		var rel3: Vector3 = dn.global_position - origin
		rel3.y = 0.0
		var t3 := rel3.dot(dir)
		if t3 > 0.0 and t3 < rng and (rel3 - dir * t3).length() < dn.radius:
			dn.diana_hit()
	var end_t := rng
	if hits.size() > 0:
		hits.sort_custom(func(a, b): return a[0] < b[0])
		if pierce:
			for h in hits:
				_hit(h, dmg, dir)
		else:
			_hit(hits[0], dmg, dir)
			end_t = hits[0][0]
	return origin + dir * end_t


func _hit(h: Array, dmg: float, dir: Vector3) -> void:
	if h[2]:
		h[1].hurt(dmg * VS_MULT, peer_id)
	elif h.size() > 3 and h[3]:
		game.damage_enemy(h[1], dmg * HEAD_MULT, dir)     # ¡a la cabeza!
		if snd_head == null:
			snd_head = AudioStreamPlayer.new()
			snd_head.stream = U.make_ting()
			snd_head.volume_db = -12.0
			snd_head.pitch_scale = 1.6
			add_child(snd_head)
		snd_head.play()
	else:
		game.damage_enemy(h[1], dmg, dir)


# ¿La bala le llega a la altura de la cabeza? (el 18 % de arriba del cuerpo, y más estrecho)
func _es_cabeza(z, t: float, perp: float) -> bool:
	if perp > z.radius * 0.75:
		return false
	var alto := _altura(z)
	if alto <= 0.0:
		return false
	var y: float = aim_y + (t + 0.9) * aim_slope - z.global_position.y
	return y > alto * 0.82 and y < alto * 1.08


# Altura del enemigo: la da él mismo si sabe dónde tiene la cabeza (Isabella con su sombrero,
# Majin Bu...) y si no se mide con sus mallas visibles (se guarda un rato)
func _altura(z) -> float:
	if z.has_method("altura_cabeza"):
		return z.altura_cabeza()
	var now := Time.get_ticks_msec()
	if z.has_meta("alto") and now - int(z.get_meta("alto_t")) < 1500:
		return z.get_meta("alto")
	var m = z.get("model")
	var n: Node3D = m if m is Node3D else z
	var b := _aabb_visible(n, Transform3D(n.global_transform.basis, n.global_position - z.global_position))
	var alto := b.end.y if b.size != Vector3.ZERO else 0.0
	z.set_meta("alto", alto)
	z.set_meta("alto_t", now)
	return alto


static func _aabb_visible(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	if n is MeshInstance3D and n.mesh != null:
		out = xf * n.mesh.get_aabb()
	for c in n.get_children():
		if c is Node3D and c.visible:
			var b := _aabb_visible(c, xf * c.transform)
			if b.size != Vector3.ZERO:
				out = b if out.size == Vector3.ZERO else out.merge(b)
	return out


func can_be_hit() -> bool:
	return not dead and not downed


# Trazadoras, fogonazo y sonido de un disparo (propio o de otro jugador)
func _fx_shot(origin: Vector3, ends: PackedVector3Array, col: Color, id: String) -> void:
	for end in ends:
		var seg := origin.distance_to(end)
		if seg < 0.05:
			continue
		var tracer := U.box(get_parent(), Vector3(0.03, 0.03, seg), (origin + end) * 0.5, col, true)
		tracer.look_at(end, Vector3.UP)
		get_tree().create_timer(0.07).timeout.connect(tracer.queue_free)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.7, 0.3)
	l.light_energy = 6.0
	l.omni_range = 7.0
	get_parent().add_child(l)
	l.global_position = origin
	get_tree().create_timer(0.07).timeout.connect(l.queue_free)
	if not is_local:
		snd_remote.stream = _snd(id)
		snd_remote.play()


@rpc("authority", "unreliable")
func _net_shot(origin: Vector3, ends: PackedVector3Array, col: Color, id: String) -> void:
	_fx_shot(origin, ends, col, id)
	var gm: Node3D = _gun_node(id)
	gm.position.z = 0.1
	create_tween().tween_property(gm, "position:z", 0.0, 0.12)


# ---------------- Granada Jan ----------------
func _jan_input(lmb: bool, delta: float) -> void:
	if jan_charge < 0.0:
		if lmb and cooldown <= 0.0 and jan_count > 0:
			jan_charge = 0.0
			_jan_cap_off()
		return
	jan_charge = minf(1.0, jan_charge + delta)
	if not lmb:
		_throw_jan()


# Se quita la gorra (y la calva empieza a brillar) mientras mantienes el clic
func _jan_cap_off() -> void:
	if jan_tween:
		jan_tween.kill()
	jan_tween = create_tween().set_parallel()
	jan_tween.tween_property(jan_hold, "position", JAN_UP, 0.25)
	jan_tween.tween_property(jan_cap, "position", Vector3(0.12, 0.5, 0.05), 0.3)
	jan_tween.tween_property(jan_cap, "rotation_degrees", Vector3(-40.0, 0.0, 35.0), 0.3)


func _jan_reset() -> void:
	jan_charge = -1.0
	if jan_tween:
		jan_tween.kill()
	if jan_hold != null:
		jan_hold.position = JAN_IDLE
		jan_cap.position = Vector3.ZERO
		jan_cap.rotation = Vector3.ZERO


# Cuanto más rato mantengas el clic, más lejos llega
func _throw_jan() -> void:
	var basis_h: Basis = head_pivot.global_transform.basis
	var dir := -basis_h.z
	var origin: Vector3 = head_pivot.global_position + dir * 0.5 + basis_h.x * 0.15
	var vel: Vector3 = dir * lerpf(7.0, 16.0, jan_charge) + Vector3.UP * 3.0
	jan_count -= 1
	cooldown = 0.5
	_spawn_jan(origin, vel)
	if Net.running and Net.online:
		_net_jan.rpc(origin, vel)
	_jan_reset()
	if jan_count <= 0:
		_select(0 if slots[0] != null else 2, true)


func _spawn_jan(origin: Vector3, vel: Vector3) -> void:
	var j = JanScript.new()
	j.vel = vel
	get_parent().add_child(j)
	j.global_position = origin


@rpc("authority", "reliable")
func _net_jan(origin: Vector3, vel: Vector3) -> void:
	_spawn_jan(origin, vel)


func add_jan(n: int) -> void:
	jan_count = mini(JAN_MAX, jan_count + n)


func _slash() -> void:
	cooldown = 0.45
	snd_swing.play()
	for z in get_tree().get_nodes_in_group("zombies"):
		var rel: Vector3 = z.global_position - global_position
		rel.y = 0.0
		var dist := rel.length()
		if dist < 2.4 + z.radius and (dist < 0.1 or aim_dir.angle_to(rel) < deg_to_rad(65.0)):
			game.damage_enemy(z, 4.0, aim_dir)
	if Net.mode == "versus":
		for p in get_tree().get_nodes_in_group("players"):
			if p == self or not p.can_be_hit():
				continue
			var rel2: Vector3 = p.global_position - global_position
			rel2.y = 0.0
			if rel2.length() < 2.4 and aim_dir.angle_to(rel2) < deg_to_rad(65.0):
				p.hurt(50.0, peer_id)
	_swing_anim()
	if Net.running and Net.online:
		_net_slash.rpc()


func _swing_anim() -> void:
	if swing_tween:
		swing_tween.kill()
	katana_pivot.rotation.y = deg_to_rad(70.0)
	swing_tween = create_tween()
	swing_tween.tween_property(katana_pivot, "rotation:y", deg_to_rad(-70.0), 0.16)
	swing_tween.tween_property(katana_pivot, "rotation:y", 0.0, 0.25)


@rpc("authority", "unreliable")
func _net_slash() -> void:
	snd_remote.stream = snd_swing.stream
	snd_remote.play()
	_swing_anim()


# ---------------- Vida, caer, morir y reaparecer ----------------
# attacker = id del jugador que te ha dado (0 = un zombie)
func hurt(amount: float, attacker: int = 0) -> void:
	if not is_local:
		# la vida de cada jugador la lleva su propio PC
		if Net.running:
			_net_hurt.rpc_id(peer_id, amount, attacker)
		return
	if game.explorando:
		return
	if dead or downed or autorevive_t > 0.0 or dios:
		return
	if porro_t > 0.0:
		amount *= 0.5
	hp -= amount
	since_hit = 0.0
	if hp <= 0.0:
		hp = 0.0
		# Zumo Revivo jugando solo: te levantas tú solo (y pierdes las bebidas)
		if has_perk("revivir") and Net.mode != "versus" and not (Net.mode == "coop" and Net.players.size() > 1):
			_jan_reset()
			lose_perks()
			reload_t = 0.0
			autorevive_t = 3.0
			_set_pose(1)
			game.toast_small("¡Caído! El Zumo Revivo te levanta...")
			return
		if Net.mode == "versus":
			_die()
			game.vs_local_killed(attacker)
		elif Net.mode == "coop" and Net.players.size() > 1:
			_go_down()
		else:
			_die()


@rpc("any_peer", "reliable")
func _net_hurt(amount: float, attacker: int) -> void:
	if is_local:
		hurt(amount, attacker)


@rpc("any_peer", "reliable")
func _net_knock(v: Vector3) -> void:
	if is_local:
		knock = v


func _go_down() -> void:
	_jan_reset()
	lose_perks()
	downed = true
	bleed = BLEED_TIME
	reload_t = 0.0
	_set_pose(1)


func _die() -> void:
	lose_perks()
	downed = false
	dead = true
	_set_pose(2)
	if Net.mode != "versus":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ---------------- Habilidades (tienda de Juan Carlos) ----------------
func use_porro() -> void:
	porro_t = 40.0


func use_cafe() -> void:
	cafe_t = 60.0


func give_gta() -> void:
	has_gta = true
	_recalc_vida()
	hp = max_hp


# ---------------- Bebidas de las máquinas (bebidas.gd) ----------------
func has_perk(id: String) -> bool:
	return perks.has(id)


func give_perk(id: String) -> void:
	if not perks.has(id):
		perks.append(id)
	_recalc_vida()
	if id == "tanque":
		hp = max_hp


# 100 de base, +50 con el GTA de la tienda, +150 con el Batido Tanque
func _recalc_vida() -> void:
	max_hp = 100.0 + (50.0 if has_gta else 0.0) + (150.0 if has_perk("tanque") else 0.0)
	hp = minf(hp, max_hp)


func lose_perks() -> void:
	porro_t = 0.0
	cafe_t = 0.0
	has_gta = false
	perks.clear()
	_recalc_vida()


# ---------------- Víctor te roba ----------------
# Se decide en el PC del jugador, que es el que sabe lo que lleva encima
func rob() -> void:
	if not is_local:
		if Net.running:
			_net_rob.rpc_id(peer_id)
		return
	if dead or downed:
		return
	var susto: bool = not game.hacking and (not game.victor_scared or randf() < SUSTO_CHANCE)
	if susto:
		game.victor_scared = true
		cam.add_child(SustoScript.new())
	var item := _take_something()
	if item.is_empty():
		return
	game.robbed(item, global_position)
	var text := "¡Víctor te ha robado %s!" % W.loot_name(item, true)
	if susto:             # el aviso espera a que acabe, para no taparle la cara
		get_tree().create_timer(SustoScript.TIME).timeout.connect(game._toast.bind(text))
	else:
		game._toast(text)


@rpc("any_peer", "reliable")
func _net_rob() -> void:
	if is_local:
		rob()


# Coge algo al azar. Siempre te deja un arma de fuego; si no llevas nada
# que robar te vacía la cartera.
func _take_something() -> Dictionary:
	var opts := []
	if slots[0] != null and slots[1] != null:
		for i in 2:
			if slots[i]["id"] != "pistola":
				opts.append("arma%d" % i)
	if jan_count > 0: opts.append("jan")
	if cafe_t > 0.0: opts.append("cafe")
	if porro_t > 0.0: opts.append("porro")
	if has_gta: opts.append("gta")
	if opts.is_empty():
		if game.points <= 0:
			return {}
		var n: int = mini(500, maxi(game.points / 4, 1))
		game.points -= n
		return {"k": "puntos", "n": n}
	var pick: String = opts.pick_random()
	match pick:
		"jan":
			var n := mini(2, jan_count)
			jan_count -= n
			if cur == 3 and jan_count <= 0:
				_select(0 if slots[0] != null else 2, true)
			return {"k": "jan", "n": n}
		"cafe":
			var c := cafe_t
			cafe_t = 0.0
			return {"k": "cafe", "t": c}
		"porro":
			var c := porro_t
			porro_t = 0.0
			return {"k": "porro", "t": c}
		"gta":
			has_gta = false
			_recalc_vida()
			return {"k": "gta"}
	var i := int(pick.substr(4))
	var w: Dictionary = slots[i]
	slots[i] = null
	if reload_slot == i:
		reload_t = 0.0
	if cur == i:
		_select(1 - i, true)
	return {"k": "arma", "w": w}


# Devuelve lo que soltó Víctor a quien lo haya cogido
func recover(item: Dictionary) -> void:
	match str(item["k"]):
		"arma":
			var w: Dictionary = item["w"]
			if has_weapon(w["id"]):
				refill_ammo(w["id"])
			else:
				give_weapon(w["id"])
				for s in slots:
					if s != null and s["id"] == w["id"]:
						s["mag"] = w["mag"]
						s["reserve"] = w["reserve"]
		"jan":
			add_jan(int(item["n"]))
		"cafe":
			cafe_t = maxf(cafe_t, float(item["t"]))
		"porro":
			porro_t = maxf(porro_t, float(item["t"]))
		"gta":
			give_gta()
		_:
			game.points += int(item["n"])


# 0 de pie, 1 caído (de rodillas en el suelo), 2 muerto
func _set_pose(p: int) -> void:
	_stop_run()
	match p:
		0:
			model.rotation.x = 0.0
			model.position.y = 0.0
			head_pivot.position.y = 1.62
			head_pivot.rotation.z = 0.0
		1:
			model.rotation.x = deg_to_rad(-70.0)
			model.position.y = 0.25
			head_pivot.position.y = 0.55
			head_pivot.rotation.z = deg_to_rad(15.0)
		2:
			model.rotation.x = deg_to_rad(-90.0)
			model.position.y = 0.3
			head_pivot.position.y = 0.4
			head_pivot.rotation.z = deg_to_rad(60.0)


# Un compañero te ha reanimado
@rpc("any_peer", "reliable")
func net_revive() -> void:
	if not is_local or not downed:
		return
	downed = false
	hp = 50.0
	since_hit = 0.0
	_set_pose(0)


# Vuelves a la partida (al empezar oleada en cooperativo o tras morir en versus)
func respawn(pos: Vector3, reset_weapons: bool) -> void:
	dead = false
	downed = false
	autorevive_t = 0.0
	hp = max_hp
	since_hit = 10.0
	knock = Vector3.ZERO
	global_position = pos
	_set_pose(0)
	if reset_weapons:
		slots = [_new_weapon("pistola"), null]
		jan_count = JAN_START
		_select(0, true)
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not input_blocked:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ---------------- Sincronización por red ----------------
func _send_state(delta: float) -> void:
	if not Net.running or not Net.online:
		return
	send_t -= delta
	if send_t > 0.0:
		return
	send_t = 0.05      # 20 veces por segundo
	var st := 0
	if downed:
		st = 1
	elif dead:
		st = 2
	_net_state.rpc(global_position, rotation.y, pitch, current_weapon_id(), st, flashlight.visible, hp, sprinting)


@rpc("authority", "unreliable_ordered")
func _net_state(pos: Vector3, rot: float, p: float, wid: String, st: int, light: bool, h: float, spr: bool) -> void:
	sprinting = spr
	net_pos = pos
	net_rot = rot
	pitch = p
	hp = h
	flashlight.visible = light
	if wid != net_weapon:
		net_weapon = wid
		_show_weapon(wid)
	var was := 2 if dead else (1 if downed else 0)
	downed = st == 1
	dead = st == 2
	if st != was:
		_set_pose(st)
	if tag != null:
		tag.visible = not dead


func _puppet(delta: float) -> void:
	# si da un salto grande (reaparecer) se teletransporta, si no se suaviza
	if position.distance_to(net_pos) > 4.0:
		position = net_pos
	else:
		position = position.lerp(net_pos, minf(1.0, 14.0 * delta))
	rotation.y = lerp_angle(rotation.y, net_rot, minf(1.0, 14.0 * delta))
	head_pivot.rotation.x = pitch
	aim_dir = -global_transform.basis.z
	aim_dir.y = 0.0
	aim_dir = aim_dir.normalized()

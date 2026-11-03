extends Node3D

const U = preload("res://scripts/nucleo/util.gd")
const W = preload("res://scripts/jugador/weapons.gd")
const PlayerScript = preload("res://scripts/jugador/player.gd")
const ZombieScript = preload("res://scripts/enemigos/zombie.gd")
const JumpscareScript = preload("res://scripts/enemigos/jumpscare.gd")
const NinjaScript = preload("res://scripts/enemigos/ninja.gd")
const BossScript = preload("res://scripts/enemigos/jefe_patinete.gd")
const BuuScript = preload("res://scripts/enemigos/majin_bu.gd")
const UiScript = preload("res://scripts/interfaz/ui.gd")
const MissionScript = preload("res://scripts/mapas/mission.gd")
const BulletScript = preload("res://scripts/jugador/bullet.gd")
const VomitScript = preload("res://scripts/enemigos/vomit.gd")
const Ch = preload("res://scripts/jugador/character.gd")
const XavierScript = preload("res://scripts/enemigos/xavier.gd")
const TiendaScript = preload("res://scripts/mapas/tienda.gd")
const HackScript = preload("res://scripts/interfaz/hackeo.gd")
const HudScript = preload("res://scripts/interfaz/hud.gd")
const IsabellaScript = preload("res://scripts/enemigos/isabella.gd")
const PowerupScript = preload("res://scripts/jugador/powerup.gd")
const IanScript = preload("res://scripts/enemigos/ian.gd")
const VictorScript = preload("res://scripts/enemigos/victor.gd")
const BotinScript = preload("res://scripts/jugador/botin.gd")
const CasinoScript = preload("res://scripts/mapas/casino.gd")
const G = preload("res://scripts/nucleo/graficos.gd")
const MapasScript = preload("res://scripts/mapas/mapas.gd")
const InvestigaScript = preload("res://scripts/mapas/investigacion.gd")
const CesurScript = preload("res://scripts/mapas/cesur.gd")
const CamaraScript = preload("res://scripts/nucleo/camara_libre.gd")
const BebidasScript = preload("res://scripts/jugador/bebidas.gd")
const PerroScript = preload("res://scripts/jugador/perro.gd")
const ConsolaScript = preload("res://scripts/nucleo/consola.gd")
const PadelScript = preload("res://scripts/mapas/padel.gd")
const IAN_FIRST := 3        # Ian (minijefe tanque) sale en la oleada 3...
const IAN_EVERY := 6        # ...y luego cada 6 (3, 9, 15, 21...)
const VICTOR_FIRST := 2     # Víctor sale a robar desde la oleada 2 (una vez por oleada como mucho)
const ISABELLA_FIRST := 6   # primera ronda de Isabella (como la de perros de CoD)...
const ISABELLA_EVERY := 8   # ...y luego cada 8 oleadas (6, 14, 22...)
const HACK_WAVE := 10       # oleada en la que Jesús te hackea

const CEIL := 4.0         # altura del techo
const SHADOWS := true     # pon false si va lento (quita sombras de los focos)
const BOX_COST := 950     # precio de la caja misteriosa
const BOX_SPIN := 4.0     # segundos que pasan las armas antes de parar
const REVIVE_TIME := 3.0  # segundos manteniendo E para reanimar (cooperativo)
const VS_GOAL := 10       # bajas para ganar en todos contra todos
const VS_SPAWNS := [
	Vector3(-7.0, 0.05, -6.0), Vector3(7.0, 0.05, -6.0), Vector3(0.0, 0.05, 6.5), Vector3(-7.8, 0.05, 12.0),
	Vector3(7.8, 0.05, 12.0), Vector3(0.0, 0.05, 25.0), Vector3(14.0, 0.05, 45.0), Vector3(25.0, 0.05, 60.0),
	Vector3(-20.0, 0.05, 40.0), Vector3(-15.0, 0.05, 70.0), Vector3(0.0, 0.05, 90.0), Vector3(18.0, 0.05, 73.0),
	Vector3(12.0, 0.05, 64.0), Vector3(25.0, 0.05, 30.0),
]
# Sitios donde puede aparecer la caja misteriosa: [posición, giro, nombre de la sala]
const BOX_SPOTS := [
	[Vector3(6.0, 0.0, -5.8), 0.0, "el aula (al fondo)"],
	[Vector3(6.0, 0.0, 7.3), 180.0, "el aula (junto a la puerta)"],
	[Vector3(-6.8, 0.0, 9.0), 0.0, "el aseo izquierdo"],
	[Vector3(6.8, 0.0, 9.0), 0.0, "el aseo derecho"],
	[Vector3(27.4, 0.0, 33.0), -90.0, "el pasillo largo"],
	[Vector3(7.0, 0.0, 40.0), 90.0, "la cafetería"],
	[Vector3(7.0, 0.0, 63.0), 90.0, "la biblioteca"],
	[Vector3(-29.4, 0.0, 40.0), 90.0, "el patio"],
	[Vector3(11.4, 0.0, 80.0), -90.0, "el vestíbulo"],
]

var mapa                    # mapas.gd: Mojácar o el Pueblo Indalo (null en CESUR)
var instituto               # cesur.gd (null en los otros mapas)
var ui                      # ui.gd
var camara                  # camara_libre.gd
var explorando := false     # cámara libre activa: sin oleadas, sin bomba y sin daño
var box_spots: Array = BOX_SPOTS
var start_pos := Vector3(0.0, 0.05, 6.5)   # dónde se despierta el jugador
var start_yaw := 0.0                       # y hacia dónde mira
var fog_d0 := 0.006                        # niebla normal del mapa (la de Isabella vuelve a esto)
var fog_c0 := Color(0.5, 0.55, 0.6)
var vfog_c0 := Color(0.85, 0.88, 0.95)
var amb0 := 0.35
var player                  # el jugador de este PC
var players := {}           # peer_id -> jugador (todos, también los de otros PCs)
var mission
# Red
var attacker := 1           # jugador al que se le apuntan los puntos del daño actual
var enemy_seq := 0
var net_t := 0.0
var target_t := 0.0
var coop_over := false
var revive_t := 0.0
var bebidas                # bebidas.gd: máquinas de bebidas con habilidades
var perro            # el perro acompañante (perro.gd)
var consola                # consola.gd: comandos de prueba (º o F1)
var padel                  # padel.gd: partido de pádel contra Víctor en el patio
var box_owner := 1
# Todos contra todos
var vs_kills := {}
var vs_deaths := {}
var vs_respawn_t := 0.0
var vs_last_killer := ""
var vs_winner := 0
var vs_end_lbl: Label
var xavier                  # el que te persigue haciéndote fotos
var small_lbl: Label        # avisos pequeños (fotos de Xavier)
var blind_rect: ColorRect   # pantalla en blanco al mirar la calva de Jan
var snd_ring: AudioStreamPlayer
var tienda                  # puesto de Juan Carlos
var casino                  # casino de Iván Muriel
var hacking := false        # pantalla hackeada por Jesús
var isabella_round := false # ronda de Isabella en marcha (solo lo sabe el anfitrión)
var world_env: Environment
var fog_tween: Tween
var isa_fog := false
var victor_scared := false  # Víctor ya te ha dado su primer susto en este mapa
var hud                     # hud.gd
var msg: Label
var prompt: Label
var dmg_rect: ColorRect
var points := 500
var wave := 0
var kills := 0
var wave_active := false
var wave_timer := 3.0
var spawn_left := 0
var spawn_cd := 0.0
var special_round := false   # ronda solo de repartidores
var snd_horn: AudioStreamPlayer
var hall_lights: Array = []
var ceil_lights: Array = []   # [foco, ¿sombra en calidad ALTO?]
var interactables: Array = []
var near = null
var e_prev := false
var doors_open := {"A": false, "B": false, "C": false, "D": false}
# Caja misteriosa
var box_root: Node3D
var box_item: Dictionary
var box_spot := 0
var box_uses := 0
var box_move_after := 4
var box_state := 0          # 0 cerrada, 1 girando, 2 ofreciendo arma, 3 se va, 4 viajando
var box_t := 0.0
var box_cycle := 0.0
var box_weapon := ""
var box_label: Label3D
var box_lid: Node3D
var box_gun: Node3D
var box_show: Node3D        # soporte donde salen las armas al girar la caja
var box_guns := {}          # un modelo por arma, se van mostrando de una en una
var box_shown := ""
# Easter egg: el armario del aula guarda la maleta de Jorge (código 2503 o ganzúa)
const ARM_CODE := "2503"
const ARM_X := 6.7
const ARM_Z := -7.7
const PICK_SPOTS := [          # sitios donde puede estar la ganzúa (uno al azar)
	Vector3(10.75, 0.86, 12.95),    # en el lavabo del aseo derecho
	Vector3(27.55, 0.02, 52.4),     # debajo de un banco del pasillo largo
	Vector3(9.0, 0.02, 15.45),      # en una cabina del aseo derecho
]
var arm_open := false
var arm_block: StaticBody3D     # frente invisible: no se puede entrar con las puertas cerradas
var arm_doors: Array = []       # [bisagra, ángulo al abrir]
var arm_led: MeshInstance3D
var has_pick := false
var pick_node: Node3D
var maleta: Node3D
var code_open := false
var code_layer: CanvasLayer
var code_lbl: Label
var code_msg: Label
var code_txt := ""
var snd_beep: AudioStreamPlayer


func _ready() -> void:
	add_to_group("game")
	randomize()
	_build_env()
	U.mapa = Net.mapa
	U.bloques = []
	if Net.mapa == "cesur":
		U.cerradas = {"A": true, "B": true, "C": true, "D": true}
		_build_room()
	else:
		mapa = MapasScript.new()      # el aula ya no es el aula...
		mapa.name = "Mapa"
		mapa.game = self
		add_child(mapa)
		mapa.construir(Net.mapa)
		U.preparar_nav()
	_apply_gfx()
	# lo que se crea a partir de ahora (jugadores, zombis, efectos) se mueve:
	# fuera de la iluminación global para que no deje manchas de luz
	get_tree().node_added.connect(_on_node_added)
	Ch.load_skin()
	_spawn_players()
	_restore_carry()
	if Net.mode != "versus" and mapa == null:
		var js = JumpscareScript.new()
		js.player = player
		add_child(js)
		js.global_position = Vector3(U.CASINO_WX - 0.6, 0.0, 58.0)
		js.zona = Rect2(22.2, 49.0, 5.8, 20.8)      # se activa al entrar en el tramo norte del pasillo largo
	_build_hud()
	if Net.mode != "versus":
		perro = PerroScript.new()
		perro.name = "Perro"
		perro.game = self
		perro.player = player
		add_child(perro)
		perro.global_position = player.global_position + player.global_transform.basis.z * 1.5
	bebidas = BebidasScript.new()
	bebidas.name = "Bebidas"
	bebidas.game = self
	add_child(bebidas)
	if mapa == null and Net.mode != "versus":
		padel = PadelScript.new()
		padel.name = "Padel"
		padel.game = self
		add_child(padel)
	if Net.mode != "versus":
		# misión para ganar: escapar de CESUR (o, en el bucle, investigar dónde estás)
		mission = MissionScript.new() if mapa == null else InvestigaScript.new()
		mission.name = "Mission"
		mission.game = self
		mission.player = player
		add_child(mission)
	else:
		_vs_setup()
	xavier = XavierScript.new()
	xavier.name = "Xavier"
	xavier.player = player
	add_child(xavier)
	xavier.global_position = Vector3(7.0, 0.0, 4.0) if mapa == null else start_pos + Vector3(6.0, -0.05, 4.0)
	if mapa == null:
		tienda = TiendaScript.new()
		tienda.name = "Tienda"
		add_child(tienda)
		casino = CasinoScript.new()
		casino.name = "Casino"
		add_child(casino)
	ui = UiScript.new()           # menú de inicio y de pausa
	add_child(ui)
	camara = CamaraScript.new()
	camara.game = self
	camara.ui = ui
	add_child(camara)
	consola = ConsolaScript.new()
	consola.name = "Consola"
	consola.game = self
	add_child(consola)
	Net.scene_ready()


# Crea al jugador local y, en red, a los de los demás PCs
func _spawn_players() -> void:
	var ids: Array = [1]
	if Net.online:
		ids = Net.players.keys()
		ids.sort()
	for i in ids.size():
		var id: int = ids[i]
		var p = PlayerScript.new()
		p.name = "P%d" % id
		p.peer_id = id
		p.is_local = (not Net.online) or id == Net.my_id()
		if Net.online:
			p.skin_data = Net.players[id]["skin"]
			p.display_name = Net.pname(id)
		add_child(p)
		if Net.mode == "versus":
			p.position = VS_SPAWNS[i % VS_SPAWNS.size()]
		else:
			p.position = start_pos + Vector3(-1.2 + i * 0.8, 0.0, 0.0)
			p.rotation.y = start_yaw
		players[id] = p
		if p.is_local:
			player = p
		vs_kills[id] = 0
		vs_deaths[id] = 0


# Lo que te llevas del mapa anterior del bucle (puntos, armas, oleada...)
func save_carry() -> void:
	Net.carry = {"points": points, "kills": kills, "wave": wave, "jan": player.jan_count,
		"slots": player.slots.duplicate(true), "perks": player.perks.duplicate()}


func _restore_carry() -> void:
	var c: Dictionary = Net.carry
	Net.carry = {}
	if c.is_empty() or Net.mode == "versus":
		return
	points = c["points"]
	kills = c["kills"]
	wave = c["wave"]
	player.jan_count = c["jan"]
	player.slots = c["slots"]
	for id in c.get("perks", []):          # las bebidas también se vienen contigo
		player.give_perk(id)
	player._select(0, true)


# Todos los PCs han cargado la partida
func net_go() -> void:
	if Net.is_host():
		_box_set(5, "", box_spot, 0)      # todos con la caja en el mismo sitio
	if Net.online:
		_toast("¡Todos conectados! (%d jugadores)" % players.size())


func net_player_left(id: int, who: String) -> void:
	if players.has(id):
		var p = players[id]
		players.erase(id)
		if is_instance_valid(p):
			p.queue_free()
		_toast("%s se ha ido de la partida" % who)


func _mission_stage() -> int:
	return mission.stage if mission != null else 0


# ---------------- Puntos y bajas ----------------
# Los enemigos solo existen de verdad en el anfitrión: allí se reparten los
# puntos al jugador que ha hecho el daño (attacker).
func add_points(n: int) -> void:
	if not Net.is_host():
		return
	_give_points(attacker, n, 0)


func zombie_killed(z = null) -> void:
	if not Net.is_host():
		return
	_give_points(attacker, 0, 1)
	if Net.online and z != null:
		_net_enemy_dead.rpc(z.name)
	# la última Isabella de la ronda suelta una Munición Máxima
	var last_isabella: bool = z != null and z.get_script() == IsabellaScript and spawn_left == 0 \
			and get_tree().get_nodes_in_group("isabellas").is_empty()
	if isabella_round and last_isabella:
		isabella_round = false
		var pos: Vector3 = U.clamp_pos(z.global_position, 0.5)
		if Net.online:
			_net_powerup.rpc(pos)
		else:
			_net_powerup(pos)


func _give_points(to: int, n: int, k: int) -> void:
	if to == Net.my_id() or not Net.online:
		points += n
		kills += k
	elif Net.players.has(to):
		_net_points.rpc_id(to, n, k)


@rpc("authority", "reliable")
func _net_points(n: int, k: int) -> void:
	points += n
	kills += k


# Daño de un jugador a un enemigo: si no eres el anfitrión se le pide a él
func damage_enemy(z, dmg: float, dir: Vector3) -> void:
	hud.hit()
	if Net.is_host():
		attacker = Net.my_id()
		z.hurt(dmg, dir)
	elif Net.running:
		_net_damage.rpc_id(1, str(z.name), dmg, dir)


@rpc("any_peer", "reliable")
func _net_damage(n: String, dmg: float, dir: Vector3) -> void:
	var z = get_node_or_null(NodePath(n))
	if z == null or z.dying:
		return
	attacker = multiplayer.get_remote_sender_id()
	z.hurt(dmg, dir)
	attacker = Net.my_id()


@rpc("authority", "reliable")
func _net_enemy_dead(n: String) -> void:
	var z = get_node_or_null(NodePath(n))
	if z != null and not z.dying:
		z.hurt(1e9, Vector3.ZERO)    # solo hace la animación de muerte


# ---------------- Bucle ----------------
func _process(delta: float) -> void:
	for l in hall_lights:
		var base: float = l.get_meta("base")
		if randf() < 0.01:
			l.light_energy = randf_range(0.0, 1.2) * base
		else:
			l.light_energy = lerpf(l.light_energy, base, 4.0 * delta)

	_update_hud()
	if explorando:
		return
	if vs_winner != 0:
		_end_keys()
		return
	if Net.online and not Net.running:
		msg.text = "Esperando a los demás jugadores..."
		return
	if Net.online:
		_net_sync(delta)

	if player.dead or player.downed:
		prompt.text = ""
		_dead_screen(delta)
		if player.dead:
			_update_box(delta)
			return

	# Tienda: caja, armas en la pared y puertas
	_update_box(delta)
	if not player.downed:
		_find_near()
		if near != null:
			prompt.text = _prompt_for(near)
		else:
			prompt.text = ""
		var e_now := Input.is_key_pressed(KEY_E)
		if e_now and not e_prev and near != null and not player.input_blocked:
			_interact(near)
		e_prev = e_now
		if Net.mode == "coop" and Net.online:
			_revive_check(delta, e_now)

	if Net.mode == "versus":
		return
	# Oleadas (las lleva el anfitrión; se acaban al escapar)
	if not Net.is_host() or _mission_stage() >= 3:
		return
	if not wave_active:
		wave_timer -= delta
		if wave_timer <= 0.0:
			_start_wave()
	else:
		if spawn_left > 0:
			spawn_cd -= delta
			if spawn_cd <= 0.0 and get_tree().get_nodes_in_group("zombies").size() < 14:
				if isabella_round:
					_add_enemy("isabella", 6.0 + wave * 0.6, _spawn_pos())
					spawn_cd = randf_range(0.5, 1.3)     # llegan en manada
				elif special_round:
					_spawn_boss()
					_horn_all()
					spawn_cd = 7.0      # van llegando de uno en uno
				else:
					_spawn_enemy()
					spawn_cd = maxf(0.7, 2.5 - wave * 0.15)
				spawn_left -= 1
		elif get_tree().get_nodes_in_group("zombies").size() == 0:
			wave_active = false
			wave_timer = 5.0
			isabella_round = false
			if special_round:
				special_round = false
				_reward()
	_coop_over_check()


# El HUD (hud.gd) se actualiza solo; aquí solo la viñeta roja al recibir daño
func _update_hud() -> void:
	dmg_rect.color.a = clampf(0.5 - player.since_hit * 1.2, 0.0, 0.5)


func _dead_screen(delta: float) -> void:
	if player.downed:
		msg.text = "¡ESTÁS CAÍDO!\nUn compañero puede reanimarte (%d s)" % int(ceil(player.bleed))
		return
	if Net.mode == "versus":
		if vs_winner != 0:
			return
		vs_respawn_t -= delta
		msg.text = "Te ha eliminado %s\nReapareces en %d..." % [vs_last_killer, int(ceil(maxf(vs_respawn_t, 0.0)))]
		if vs_respawn_t <= 0.0:
			msg.text = ""
			player.respawn(_vs_spawn_point(), true)
		return
	if Net.online and Net.mode == "coop" and not coop_over:
		msg.text = "HAS MUERTO\nReaparecerás en la próxima oleada si tus compañeros aguantan"
		return
	var reason := ""
	if mission != null and mission.death_reason != "":
		reason = mission.death_reason + "\n"
	var again := "Pulsa R para reiniciar"
	if Net.online:
		again = "Pulsa R para jugar otra vez · M para salir al menú" if Net.is_host() else "Esperando a que el anfitrión reinicie · M para salir al menú"
	msg.text = reason + "HAS MUERTO\nOleada %d · %d bajas\n%s" % [wave, kills, again]
	_end_keys()


# R = reiniciar, M = menú (en red solo el anfitrión reinicia a todos)
func _end_keys() -> void:
	if Input.is_key_pressed(KEY_R) and Net.is_host():
		if Net.online:
			Net.start_game()
		else:
			Net.reset_loop()
			UiScript.autostart = true
			get_tree().reload_current_scene()
	elif Input.is_key_pressed(KEY_M) and Net.online:
		Net.quit_to_menu()


# ---------------- Oleadas ----------------
func _start_wave() -> void:
	wave += 1
	wave_active = true
	spawn_left = 3 + wave * 2
	spawn_cd = 0.0
	var text := "OLEADA %d" % wave
	special_round = wave % 4 == 0
	isabella_round = wave >= ISABELLA_FIRST and (wave - ISABELLA_FIRST) % ISABELLA_EVERY == 0
	if isabella_round:
		special_round = false
		spawn_left = mini(6 + (wave - ISABELLA_FIRST) / ISABELLA_EVERY * 2 + (players.size() - 1) * 3, 18)
		spawn_cd = 3.0
		text = "OLEADA %d\n¡RONDA DE ISABELLA!\nViene con el bolso cargado..." % wave
	elif special_round:
		# Ronda especial (como la de perros de CoD): solo repartidores, cada vez más
		spawn_left = mini(wave / 4, 4)
		spawn_cd = 2.5
		text = "OLEADA %d\n¡RONDA DEL REPARTIDOR!\nTienes un pedido... y no viene solo" % wave
	elif wave % 5 == 0:
		var bu_hp := 120.0 + wave * 12.0
		if wave == HACK_WAVE:
			spawn_cd = HackScript.DURATION      # que el hackeo termine antes de que lleguen
			get_tree().create_timer(HackScript.DURATION).timeout.connect(func(): _add_enemy("bu", bu_hp, _spawn_pos()))
		else:
			_add_enemy("bu", bu_hp, _spawn_pos())
		text += "\n¡Ha despertado Majin Bu!"
	# Ian llega a mitad de oleada (no en las rondas especiales)
	if wave >= IAN_FIRST and (wave - IAN_FIRST) % IAN_EVERY == 0 and not special_round and not isabella_round:
		var ian_hp := 70.0 + wave * 10.0
		get_tree().create_timer(6.0).timeout.connect(func():
			if wave_active:
				_add_enemy("ian", ian_hp, _spawn_pos()))
	# Víctor se cuela a mitad de oleada: siempre la primera vez, luego la mitad de ellas
	if not special_round and not isabella_round and wave != HACK_WAVE and (wave == VICTOR_FIRST or (wave > VICTOR_FIRST and randf() < 0.5)):
		var vic_hp := 18.0 + wave * 3.0
		get_tree().create_timer(randf_range(8.0, 16.0)).timeout.connect(func():
			if wave_active and get_tree().get_nodes_in_group("victors").is_empty():
				_add_enemy("victor", vic_hp, _spawn_pos()))
	if Net.online:
		_net_wave.rpc(wave, text, special_round, isabella_round)
	else:
		_net_wave(wave, text, special_round, isabella_round)


@rpc("authority", "call_local", "reliable")
func _net_wave(w: int, text: String, special: bool, isa: bool = false) -> void:
	wave = w
	msg.text = text
	_isabella_fog(isa)
	if w == HACK_WAVE:
		msg.text = ""
		var hk = HackScript.new()
		hk.on_done = func(): _toast(text)
		add_child(hk)
	if special:
		var fl := ColorRect.new()
		fl.color = Color(1.0, 0.5, 0.0, 0.45)
		fl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.add_child(fl)
		var tw := fl.create_tween()
		tw.tween_property(fl, "color:a", 0.0, 1.5)
		tw.tween_callback(fl.queue_free)
		_horn()
	# en cooperativo los muertos vuelven al empezar la oleada
	if w > 1:
		player.add_jan(1)          # un Jan más por oleada
	if player.dead and Net.online and Net.mode == "coop" and not coop_over:
		player.respawn(start_pos + Vector3(randf_range(-1.5, 1.5), 0.0, 0.0), false)
	get_tree().create_timer(2.5).timeout.connect(_clear_msg)


# Premio al acabar la ronda especial, como en Call of Duty
func _reward() -> void:
	if Net.online:
		_net_reward.rpc()
	else:
		_net_reward()


@rpc("authority", "call_local", "reliable")
func _net_reward() -> void:
	for sl in player.slots:
		if sl != null:
			player.refill_ammo(sl["id"])
	points += 500
	player.jan_count = player.JAN_MAX
	_toast("¡PEDIDO ENTREGADO!\nMunición máxima  +500 puntos")


# ---------------- Ronda de Isabella ----------------
# Niebla rosa y luz más oscura mientras dura la ronda (como la niebla de los perros)
func _isabella_fog(on: bool) -> void:
	if world_env == null or on == isa_fog:
		return
	isa_fog = on
	if fog_tween:
		fog_tween.kill()
	fog_tween = create_tween().set_parallel()
	fog_tween.tween_property(world_env, "fog_density", 0.035 if on else fog_d0, 2.5)
	fog_tween.tween_property(world_env, "fog_light_color", Color(0.85, 0.35, 0.6) if on else fog_c0, 2.5)
	fog_tween.tween_property(world_env, "ambient_light_energy", amb0 * (0.65 if on else 1.0), 2.5)
	fog_tween.tween_property(world_env, "volumetric_fog_density", 0.06 if on else 0.01, 2.5)
	fog_tween.tween_property(world_env, "volumetric_fog_albedo", Color(0.95, 0.5, 0.75) if on else vfog_c0, 2.5)
	if on:
		var fl := ColorRect.new()
		fl.color = Color(1.0, 0.35, 0.75, 0.5)
		fl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.add_child(fl)
		var tw := fl.create_tween()
		tw.tween_property(fl, "color:a", 0.0, 1.5)
		tw.tween_callback(fl.queue_free)
		var snd := AudioStreamPlayer.new()
		snd.stream = U.make_laugh(1.8)
		add_child(snd)
		snd.play()
		snd.finished.connect(snd.queue_free)


# La última Isabella ha soltado la Munición Máxima
@rpc("authority", "call_local", "reliable")
func _net_powerup(pos: Vector3) -> void:
	_isabella_fog(false)
	var pu = PowerupScript.new()
	pu.name = "MunicionMaxima"
	add_child(pu)
	pu.global_position = Vector3(pos.x, 0.0, pos.z)
	_toast("¡Isabella ha soltado algo!")


# La llama el power-up cuando el jugador de este PC pasa por encima
func take_max_ammo() -> void:
	if Net.online:
		_net_take_powerup.rpc()
	else:
		_net_take_powerup()


@rpc("any_peer", "call_local", "reliable")
func _net_take_powerup() -> void:
	var pu = get_node_or_null("MunicionMaxima")
	if pu == null:
		return             # otro jugador la ha cogido justo antes
	pu.queue_free()
	for sl in player.slots:
		if sl != null:
			player.refill_ammo(sl["id"])
	player.jan_count = player.JAN_MAX
	_toast("¡MUNICIÓN MÁXIMA!")
	var snd := AudioStreamPlayer.new()
	snd.stream = U.make_powerup()
	add_child(snd)
	snd.play()
	snd.finished.connect(snd.queue_free)


# Bocina de moto "mec-mec" que avisa de que llega un repartidor
func _horn() -> void:
	if snd_horn == null:
		snd_horn = AudioStreamPlayer.new()
		snd_horn.volume_db = -4.0
		add_child(snd_horn)
		var rate := 22050
		var n := int(rate * 0.7)
		var data := PackedByteArray()
		data.resize(n * 2)
		for i in n:
			var tt := float(i) / rate
			var s := 0.0
			if tt < 0.25 or (tt > 0.35 and tt < 0.65):
				s = signf(sin(tt * TAU * 420.0)) * 0.3 + signf(sin(tt * TAU * 530.0)) * 0.3
			data.encode_s16(i * 2, int(s * 22000.0))
		var w := AudioStreamWAV.new()
		w.format = AudioStreamWAV.FORMAT_16_BITS
		w.mix_rate = rate
		w.data = data
		snd_horn.stream = w
	snd_horn.play()


func _horn_all() -> void:
	if Net.online:
		_net_horn.rpc()
	else:
		_horn()


@rpc("authority", "call_local", "unreliable")
func _net_horn() -> void:
	_horn()


# Cooperativo: si caen todos se acaba la partida
func _coop_over_check() -> void:
	if not Net.online or Net.mode != "coop" or coop_over:
		return
	for p in players.values():
		if is_instance_valid(p) and not p.dead and not p.downed:
			return
	_net_coop_over.rpc()


@rpc("authority", "call_local", "reliable")
func _net_coop_over() -> void:
	coop_over = true
	if not player.dead:
		player._die()


# Reanimar a un compañero caído manteniendo E
func _revive_check(delta: float, e_now: bool) -> void:
	var target = null
	for p in players.values():
		if p != player and is_instance_valid(p) and p.downed:
			if Vector2(p.global_position.x - player.global_position.x, p.global_position.z - player.global_position.z).length() < 1.7:
				target = p
	if target == null:
		revive_t = 0.0
		return
	var rt := REVIVE_TIME * (0.5 if player.has_perk("revivir") else 1.0)     # Zumo Revivo: el doble de rápido
	if e_now:
		revive_t += delta
	else:
		revive_t = 0.0
	prompt.text = "Mantén [E] para reanimar a %s  %d%%" % [target.display_name, int(revive_t / rt * 100.0)]
	if revive_t >= rt:
		revive_t = 0.0
		target.net_revive.rpc_id(target.peer_id)
		points += 100
		_toast("¡Has reanimado a %s! +100" % target.display_name)


# ---------------- Sincronización de enemigos ----------------
func _net_sync(delta: float) -> void:
	if Net.is_host():
		# cada enemigo persigue al jugador vivo más cercano
		target_t -= delta
		if target_t <= 0.0:
			target_t = 0.3
			for z in get_tree().get_nodes_in_group("zombies"):
				z.player = _nearest_player(z.global_position)
			xavier.player = _nearest_player(xavier.global_position)
		net_t -= delta
		if net_t <= 0.0:
			net_t = 1.0 / 15.0
			var data: Array = []
			for z in get_tree().get_nodes_in_group("zombies"):
				data.append([str(z.name), z.global_position.x, z.global_position.z, z.rotation.y, z.model.position.y])
			if data.size() > 0:
				_net_enemies.rpc(data)
	else:
		for z in get_tree().get_nodes_in_group("zombies"):
			if z.has_meta("np"):
				var tp: Vector3 = z.get_meta("np")
				z.global_position = z.global_position.lerp(tp, minf(1.0, 10.0 * delta))
				z.rotation.y = lerp_angle(z.rotation.y, z.get_meta("nr"), minf(1.0, 10.0 * delta))
				z.model.position.y = lerpf(z.model.position.y, z.get_meta("ny"), minf(1.0, 12.0 * delta))


func _nearest_player(pos: Vector3):
	var best = player
	var bd := INF
	for p in players.values():
		if not is_instance_valid(p) or p.dead or p.downed:
			continue
		var d: float = p.global_position.distance_squared_to(pos)
		if d < bd:
			bd = d
			best = p
	return best


@rpc("authority", "unreliable_ordered")
func _net_enemies(data: Array) -> void:
	for e in data:
		var z = get_node_or_null(NodePath(e[0]))
		if z == null or z.dying:
			continue
		z.set_meta("np", Vector3(e[1], 0.0, e[2]))
		z.set_meta("nr", e[3])
		z.set_meta("ny", e[4])


# Crea un enemigo (solo en el anfitrión, que avisa a los demás)
func _add_enemy(kind: String, hp: float, pos: Vector3, speed: float = -1.0) -> void:
	if not Net.is_host():
		return
	enemy_seq += 1
	var n := "E%d" % enemy_seq
	_make_enemy(kind, n, hp, pos, speed, false)
	if Net.online:
		_net_spawn.rpc(kind, n, hp, pos)


@rpc("authority", "reliable")
func _net_spawn(kind: String, n: String, hp: float, pos: Vector3) -> void:
	_make_enemy(kind, n, hp, pos, -1.0, true)


func _make_enemy(kind: String, n: String, hp: float, pos: Vector3, speed: float, puppet: bool) -> void:
	var z
	match kind:
		"ninja":
			z = NinjaScript.new()
		"boss":
			z = BossScript.new()
		"bu":
			z = BuuScript.new()
		"isabella":
			z = IsabellaScript.new()
		"ian":
			z = IanScript.new()
		"victor":
			z = VictorScript.new()
		_:
			z = ZombieScript.new()
	z.name = n
	z.hp = hp
	if speed > 0.0:
		z.speed = speed
	z.puppet = puppet
	z.player = player if puppet else _nearest_player(pos)
	add_child(z)
	z.global_position = pos
	z.set_meta("np", pos)
	z.set_meta("nr", 0.0)
	z.set_meta("ny", 0.0)


# ---------------- Víctor ----------------
# El PC del jugador robado avisa al anfitrión de qué se ha llevado
func robbed(item: Dictionary, pos: Vector3) -> void:
	if Net.is_host():
		_robbed(item, pos)
	else:
		_net_robbed.rpc_id(1, item, pos)


@rpc("any_peer", "reliable")
func _net_robbed(item: Dictionary, pos: Vector3) -> void:
	_robbed(item, pos)


func _robbed(item: Dictionary, pos: Vector3) -> void:
	var v = get_tree().get_first_node_in_group("victors")
	if v == null:          # le han matado justo mientras llegaba el aviso
		drop_loot(pos, item)
		return
	v.take(item)
	if Net.online:
		_net_victor_take.rpc(str(v.name), item)


@rpc("authority", "reliable")
func _net_victor_take(n: String, item: Dictionary) -> void:
	var v = get_node_or_null(NodePath(n))
	if v != null:
		v.take(item)


func net_victor_laugh(n: String) -> void:
	_net_victor_laugh.rpc(n)


@rpc("authority", "unreliable")
func _net_victor_laugh(n: String) -> void:
	var v = get_node_or_null(NodePath(n))
	if v != null:
		v._laugh()


# Majin Bu se pincha el Ozempic: el anfitrión avisa a las copias para que también se transformen
func net_buu_transform(n: String) -> void:
	_net_buu_transform.rpc(n)


@rpc("authority", "reliable")
func _net_buu_transform(n: String) -> void:
	var z = get_node_or_null(NodePath(n))
	if z != null and z.has_method("start_transform"):
		z.start_transform()


func victor_escaped(v) -> void:
	if Net.online:
		_net_victor_gone.rpc(str(v.name))
	v.vanish()


@rpc("authority", "reliable")
func _net_victor_gone(n: String) -> void:
	var v = get_node_or_null(NodePath(n))
	if v != null and not v.dying:
		v.vanish()


func drop_loot(pos: Vector3, item: Dictionary) -> void:
	if not Net.is_host():
		return
	enemy_seq += 1
	var n := "B%d" % enemy_seq
	if Net.online:
		_net_loot.rpc(n, pos, item)
	else:
		_net_loot(n, pos, item)


@rpc("authority", "call_local", "reliable")
func _net_loot(n: String, pos: Vector3, item: Dictionary) -> void:
	var b = BotinScript.new()
	b.name = n
	b.item = item
	add_child(b)
	b.global_position = pos


func take_loot(b) -> void:
	player.recover(b.item)
	_toast("¡Has recuperado %s!" % W.loot_name(b.item, true))
	if Net.online:
		_net_loot_gone.rpc(str(b.name))
	b.queue_free()


@rpc("any_peer", "reliable")
func _net_loot_gone(n: String) -> void:
	var b = get_node_or_null(NodePath(n))
	if b != null:
		b.queue_free()


# Proyectiles de los enemigos: en los demás PCs se ven, pero no hacen daño
func net_projectile(kind: String, a: Vector3, b: Vector3, c: float = 0.0) -> void:
	if Net.online and Net.is_host():
		_net_proj.rpc(kind, a, b, c)


@rpc("authority", "unreliable")
func _net_proj(kind: String, a: Vector3, b: Vector3, c: float) -> void:
	match kind:
		"bullet":
			var bl = BulletScript.new()
			add_child(bl)
			bl.global_position = a
			bl.vel = b
		"vomit":
			var v = VomitScript.new()
			add_child(v)
			v.setup(a, b, c, null)
		"sushi":
			var k = BuuScript.Sushi.new()
			add_child(k)
			k.global_position = a
			k.vel = b
			for z in get_tree().get_nodes_in_group("zombies"):
				if z is BuuScript:
					z.vomiting = maxf(z.vomiting, 0.5)      # su copia pone cara de vomitar


func _clear_msg() -> void:
	if not player.dead and not player.downed:
		msg.text = ""


# Temblor de cámara (cuando llega Ian pisando fuerte)
func shake(strength: float) -> void:
	var cam: Camera3D = player.cam
	var tw := create_tween()
	for i in 10:
		var k := strength * (1.0 - i / 10.0)
		tw.tween_property(cam, "h_offset", randf_range(-k, k), 0.035)
		tw.parallel().tween_property(cam, "v_offset", randf_range(-k, k), 0.035)
	tw.tween_property(cam, "h_offset", 0.0, 0.05)
	tw.parallel().tween_property(cam, "v_offset", 0.0, 0.05)


# Aviso pequeño debajo de la mira, sin tapar los mensajes grandes
func toast_small(text: String) -> void:
	small_lbl.text = text
	small_lbl.modulate.a = 1.0
	var tw := small_lbl.create_tween()
	tw.tween_interval(1.2)
	tw.tween_property(small_lbl, "modulate:a", 0.0, 0.5)


# Te ha cegado la calva de Jan: pantalla blanca y pitido (amount de 0 a 1)
func blind(amount: float) -> void:
	blind_rect.color.a = clampf(0.6 + amount, 0.0, 1.0)
	var tw := blind_rect.create_tween()
	tw.tween_interval(0.3 + 1.5 * amount)
	tw.tween_property(blind_rect, "color:a", 0.0, 1.0 + 1.5 * amount)
	if snd_ring == null:
		snd_ring = AudioStreamPlayer.new()
		snd_ring.stream = U.make_ringing(4.0)
		add_child(snd_ring)
	snd_ring.volume_db = linear_to_db(amount)
	snd_ring.play()
	if amount > 0.6:
		_toast("¡LA CALVA DE JAN!")


func _toast(text: String) -> void:
	msg.text = text
	get_tree().create_timer(1.8).timeout.connect(_clear_msg)


# Puntos de aparición en las zonas ya abiertas
func _spawn_pos() -> Vector3:
	var pts: Array = []
	if mapa != null:
		pts = mapa.spawns.duplicate()
		pts.shuffle()
		for p in pts:
			var ok := true
			for pl in players.values():
				if is_instance_valid(pl) and Vector2(p.x - pl.global_position.x, p.z - pl.global_position.z).length() < 16.0:
					ok = false
			if ok:
				return p
		return pts[0]
	for i in 3:
		pts.append(Vector3(randf_range(-7.0, 7.0), 0.0, -6.6))
	pts.append(Vector3(-7.5, 0.0, randf_range(-6.0, 3.0)))
	pts.append(Vector3(7.5, 0.0, randf_range(-6.0, 3.0)))
	if doors_open["A"]:
		pts.append(Vector3(0.0, 0.0, 17.0))
		pts.append(Vector3(-U.WC_X, 0.0, 14.0))
		pts.append(Vector3(U.WC_X, 0.0, 14.0))
	if doors_open["B"]:
		pts.append(Vector3(randf_range(-4.0, 4.0), 0.0, 25.0))                         # distribuidor
		pts.append(Vector3(randf_range(9.0, 20.0), 0.0, 26.0))                         # pasillo de la cafetería
		for zz in [32.0, 40.0, 55.0, 66.0]:
			pts.append(Vector3(randf_range(23.2, 27.0), 0.0, zz))                       # pasillo largo
		pts.append(Vector3(randf_range(8.0, 20.0), 0.0, randf_range(31.0, 52.0)))     # cafetería
		pts.append(Vector3(37.5, 0.0, 47.5))                                           # fondo del casino
		pts.append(Vector3(randf_range(8.0, 20.0), 0.0, 64.5))                         # biblioteca
		for k in 3:
			pts.append(Vector3(randf_range(-28.0, -9.0), 0.0, randf_range(20.0, 74.0)))   # patio
	if doors_open["C"] or doors_open["D"]:
		pts.append(Vector3(randf_range(-2.0, 26.0), 0.0, 73.0))                        # pasillo norte
		for k in 2:
			pts.append(Vector3(randf_range(-10.0, 10.0), 0.0, randf_range(80.0, 96.0)))   # vestíbulo
	var far: Array = []
	for p in pts:
		var ok := true
		for pl in players.values():
			if is_instance_valid(pl) and Vector2(p.x - pl.global_position.x, p.z - pl.global_position.z).length() < 12.0:
				ok = false
		if ok:
			far.append(p)
	if far.is_empty():
		far = pts
	return far[randi() % far.size()]


func _spawn_enemy() -> void:
	if wave >= 2 and randi() % 3 == 0:
		_add_enemy("ninja", 6.0 + wave, _spawn_pos())
	else:
		_add_enemy("zombie", 12.0 + wave * 2.0, _spawn_pos(), 1.6 + minf(wave * 0.15, 1.8))


func _spawn_boss() -> void:
	_add_enemy("boss", 70.0 + wave * 10.0, _spawn_pos())


# ---------------- Todos contra todos ----------------
func _vs_setup() -> void:
	# todo el instituto abierto desde el principio
	for it in interactables:
		if it["type"] == "door":
			it["done"] = true
			doors_open[it["id"]] = true
			U.cerradas.erase(it["id"])
			it["node"].queue_free()
			it["label"].queue_free()
	msg.text = "TODOS CONTRA TODOS\nEl primero en llegar a %d bajas gana" % VS_GOAL
	get_tree().create_timer(4.0).timeout.connect(_clear_msg)


func _vs_spawn_point() -> Vector3:
	var best: Vector3 = VS_SPAWNS[0]
	var best_d := -1.0
	for s in VS_SPAWNS:
		var dmin := INF
		for p in players.values():
			if is_instance_valid(p) and p != player and not p.dead:
				dmin = minf(dmin, s.distance_to(p.global_position))
		dmin += randf() * 6.0
		if dmin > best_d:
			best_d = dmin
			best = s
	return best


# El jugador local ha muerto en versus
func vs_local_killed(killer: int) -> void:
	vs_respawn_t = 4.0
	_net_vs_kill.rpc(Net.my_id(), killer)


@rpc("any_peer", "call_local", "reliable")
func _net_vs_kill(victim: int, killer: int) -> void:
	vs_deaths[victim] = vs_deaths.get(victim, 0) + 1
	if killer != 0 and killer != victim:
		vs_kills[killer] = vs_kills.get(killer, 0) + 1
	if victim == Net.my_id():
		vs_last_killer = Net.pname(killer)
	if killer == Net.my_id():
		points += 100
		kills += 1
		_toast("¡Has eliminado a %s! +100" % Net.pname(victim))
	elif victim != Net.my_id():
		_toast("%s ha eliminado a %s" % [Net.pname(killer), Net.pname(victim)])
	if killer != 0 and vs_kills.get(killer, 0) >= VS_GOAL and vs_winner == 0:
		_vs_win(killer)


func _vs_win(id: int) -> void:
	vs_winner = id
	player.frozen = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var l := Label.new()
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 40)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 10)
	var won := id == Net.my_id()
	l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2) if won else Color(1.0, 0.4, 0.35))
	var table := ""
	var ids: Array = vs_kills.keys()
	ids.sort_custom(func(a, b): return vs_kills[a] > vs_kills[b])
	for pid in ids:
		table += "\n%s   %d bajas · %d muertes" % [Net.pname(pid), vs_kills[pid], vs_deaths.get(pid, 0)]
	var again := "R para la revancha · M para salir al menú" if Net.is_host() else "Esperando la revancha del anfitrión · M para salir al menú"
	l.text = ("¡HAS GANADO!" if won else "GANA %s" % Net.pname(id)) + "\n" + table + "\n\n" + again
	layer.add_child(l)
	vs_end_lbl = l


# ---------------- Tienda estilo Call of Duty Zombies ----------------
func _find_near() -> void:
	near = null
	var best := 2.6
	var pp: Vector3 = player.global_position
	for it in interactables:
		if it["done"]:
			continue
		var d: float = Vector2(pp.x - it["pos"].x, pp.z - it["pos"].z).length()
		if d < best:
			best = d
			near = it


func _prompt_for(it) -> String:
	match it["type"]:
		"door":
			return "[E] Abrir puerta (%d puntos)" % it["cost"]
		"wall":
			var id: String = it["weapon"]
			var d: Dictionary = W.DATA[id]
			if player.has_weapon(id):
				return "[E] Munición de %s (%d puntos)" % [d["name"], int(d["price"]) / 2]
			return "[E] Comprar %s (%d puntos)  ·  %s" % [d["name"], d["price"], W.damage_text(id)]
		"box":
			if box_state == 0:
				return "[E] Caja misteriosa (%d puntos)" % BOX_COST
			if box_state == 2:
				if box_owner != Net.my_id():
					return "%s es de %s" % [W.DATA[box_weapon]["name"], Net.pname(box_owner)]
				return "[E] Coger %s  ·  %s" % [W.DATA[box_weapon]["name"], W.damage_text(box_weapon)]
		"shop":
			return tienda.prompt(it)
		"casino":
			return casino.prompt(it)
		"armario":
			if has_pick:
				return "[E] Forzar el candado con la ganzúa"
			return "[E] Armario cerrado con código"
		"ganzua":
			return "[E] Coger ganzúa"
		"maleta":
			return "[E] Abrir la maleta de Jorge"
		"perk":
			return bebidas.prompt(it)
		"padel":
			return padel.prompt()
		"perro":
			return "[E] Acariciar a Mac"
	return ""


func _interact(it) -> void:
	match it["type"]:
		"door":
			if points >= it["cost"]:
				points -= it["cost"]
				if Net.online:
					_net_open_door.rpc(it["id"])
				else:
					_open_door(it)
			else:
				_toast("Te faltan %d puntos" % (int(it["cost"]) - points))
		"wall":
			var id: String = it["weapon"]
			var d: Dictionary = W.DATA[id]
			if player.has_weapon(id):
				var c: int = int(d["price"]) / 2
				if player.ammo_full(id):
					_toast("Ya tienes la munición llena")
				elif points >= c:
					points -= c
					player.refill_ammo(id)
					_toast("Munición recargada")
				else:
					_toast("Te faltan %d puntos" % (c - points))
			else:
				var c2: int = int(d["price"])
				if points >= c2:
					points -= c2
					player.give_weapon(id)
					_toast("Has comprado: %s" % d["name"])
				else:
					_toast("Te faltan %d puntos" % (c2 - points))
		"box":
			if box_state == 0:
				if points >= BOX_COST:
					points -= BOX_COST
					if Net.is_host():
						_box_use(Net.my_id())
					else:
						_net_box_use.rpc_id(1)
				else:
					_toast("Te faltan %d puntos" % (BOX_COST - points))
			elif box_state == 2 and box_owner == Net.my_id():
				player.give_weapon(box_weapon)
				_toast("Has conseguido: %s" % W.DATA[box_weapon]["name"])
				if Net.is_host():
					_box_set(0, "", box_spot, 0)
				else:
					_net_box_take.rpc_id(1)
		"shop":
			tienda.open_menu()
		"casino":
			casino.open_menu(it)
		"armario":
			if has_pick:
				_toast("Has forzado el candado con la ganzúa")
				_arm_unlock()
			else:
				_open_code()
		"ganzua":
			it["done"] = true
			has_pick = true
			pick_node.queue_free()
			_toast("Has encontrado una ganzúa... ¿qué podrá abrir?")
		"maleta":
			_open_maleta(it)
		"perk":
			bebidas.comprar(it)
		"padel":
			padel.empezar()
		"perro":
			perro.acariciar()


@rpc("any_peer", "call_local", "reliable")
func _net_open_door(id: String) -> void:
	for it in interactables:
		if it["type"] == "door" and it["id"] == id and not it["done"]:
			_open_door(it)


func _open_door(it) -> void:
	it["done"] = true
	doors_open[it["id"]] = true
	U.cerradas.erase(it["id"])
	var body: StaticBody3D = it["node"]
	body.collision_layer = 0
	it["label"].queue_free()
	var tw := create_tween()
	tw.tween_property(body, "position:y", body.position.y + CEIL + 1.0, 0.8)
	tw.tween_callback(body.queue_free)
	_toast("¡Puerta abierta!")


# ---------------- Caja misteriosa (la decide el anfitrión) ----------------
@rpc("any_peer", "reliable")
func _net_box_use() -> void:
	var who := multiplayer.get_remote_sender_id()
	if box_state == 0:
		_box_use(who)
	else:
		_give_points(who, BOX_COST, 0)     # alguien se adelantó: se le devuelve


@rpc("any_peer", "reliable")
func _net_box_take() -> void:
	if box_state == 2:
		_box_set(0, "", box_spot, 0)


func _box_use(who: int) -> void:
	_box_set(1, "", box_spot, who)


# Cambia el estado de la caja en todos los PCs
#   0 cerrar · 1 empezar a girar · 2 ofrecer arma · 3 irse · 5 aparecer en otro sitio
func _box_set(st: int, weapon: String, spot: int, who: int) -> void:
	if Net.online:
		_net_box.rpc(st, weapon, spot, who)
	else:
		_net_box(st, weapon, spot, who)


@rpc("authority", "call_local", "reliable")
func _net_box(st: int, weapon: String, spot: int, who: int) -> void:
	match st:
		0:
			_close_box()
		1:
			box_owner = who
			box_state = 1
			box_t = BOX_SPIN
			box_cycle = 0.0
			box_show.rotation.y = 0.0
		2:
			box_weapon = weapon
			box_label.text = W.DATA[box_weapon]["name"]
			_box_show_gun(box_weapon)
			box_gun = box_guns[box_weapon]
			# pequeño salto al quedarse fija el arma elegida
			box_show.scale = Vector3.ONE * 1.3
			create_tween().tween_property(box_show, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK)
			box_state = 2
			box_t = 8.0
		3:
			# La caja se va a otra sala (devuelve los puntos a quien la usó)
			box_label.text = "¡Adiós!"
			_box_show_gun("")
			if who == Net.my_id():
				points += BOX_COST
			_toast("¡La caja misteriosa se va a otra sala!\nSe devuelven %d puntos" % BOX_COST)
			box_item["done"] = true
			box_state = 3
			box_t = 2.5
		5:
			var moved := spot != box_spot or box_state == 4
			_place_box(spot)
			box_state = 0
			box_label.text = "?"
			if moved:
				_toast("La caja misteriosa ha aparecido en " + str(box_spots[spot][2]))


func _close_box() -> void:
	box_state = 0
	box_label.text = "?"
	box_weapon = ""
	box_gun = null
	_box_show_gun("")
	box_show.position.y = 0.6


# Enseña solo el modelo del arma id dentro de la caja ("" = ninguno)
func _box_show_gun(id: String) -> void:
	box_shown = id
	for k in box_guns:
		box_guns[k].visible = (k == id)


func _box_pick() -> String:
	var pool: Array = []
	for id in W.BOX_POOL:
		if not (box_owner == Net.my_id() and player.has_weapon(id)):
			pool.append(id)
	if pool.is_empty():
		pool = W.BOX_POOL.duplicate()
	return pool[randi() % pool.size()]


func _update_box(delta: float) -> void:
	var open_angle := 0.0
	if box_state == 1 or box_state == 2:
		open_angle = -1.1
	box_lid.rotation.x = lerpf(box_lid.rotation.x, open_angle, 8.0 * delta)
	var host: bool = Net.is_host()
	if box_state == 1:
		box_t -= delta
		box_cycle -= delta
		# las armas suben de la caja y van cambiando, cada vez más despacio
		var prog := 1.0 - clampf(box_t / BOX_SPIN, 0.0, 1.0)
		box_show.position.y = lerpf(0.6, 1.5, minf(prog * 3.0, 1.0))
		box_show.rotation.y += lerpf(9.0, 2.0, prog) * delta
		if box_cycle <= 0.0 and box_t > 0.0:
			box_cycle = lerpf(0.07, 0.45, prog * prog)
			var rid: String = box_shown
			while rid == box_shown:
				rid = W.BOX_POOL[randi() % W.BOX_POOL.size()]
			_box_show_gun(rid)
			box_label.text = W.DATA[rid]["name"]
		if box_t <= 0.0 and host:
			box_t = 999.0         # que no se repita mientras llega la respuesta
			box_uses += 1
			if box_uses >= box_move_after:
				_box_set(3, "", box_spot, box_owner)
			else:
				_box_set(2, _box_pick(), box_spot, box_owner)
	elif box_state == 2:
		box_t -= delta
		box_show.rotation.y += 1.5 * delta
		if box_t < 1.5:
			box_show.position.y = lerpf(0.6, 1.5, maxf(box_t, 0.0) / 1.5)   # vuelve a meterse en la caja
		if box_t <= 0.0 and host:
			box_t = 999.0
			_box_set(0, "", box_spot, 0)
	elif box_state == 3:
		# sube girando y se encoge
		box_t -= delta
		box_root.position.y += 1.2 * delta
		box_root.rotation.y += 4.0 * delta
		box_root.scale = Vector3.ONE * clampf(box_t / 2.5, 0.05, 1.0)
		if box_t <= 0.0:
			box_root.visible = false
			box_state = 4
			box_t = 4.0
	elif box_state == 4:
		box_t -= delta
		if box_t <= 0.0 and host:
			box_t = 999.0
			var j := box_spot
			while j == box_spot:
				j = randi() % box_spots.size()
			_box_set(5, "", j, 0)


# Coloca la caja en uno de los sitios posibles
func _place_box(i: int) -> void:
	box_spot = i
	var spot: Array = box_spots[i]
	var pos: Vector3 = spot[0]
	var yaw: float = spot[1]
	box_root.position = pos
	box_root.rotation_degrees = Vector3(0, yaw, 0)
	box_root.scale = Vector3.ONE
	box_root.visible = true
	box_item["pos"] = pos + Vector3(0, 0, 1.0).rotated(Vector3.UP, deg_to_rad(yaw))
	box_item["done"] = false
	box_uses = 0
	box_move_after = randi_range(3, 6)


func _build_shop() -> void:
	# A: aula -> pasillo de los aseos · B: -> distribuidor (patio, cafetería, pasillo largo)
	# C: pasillo largo -> pasillo norte y vestíbulo · D: patio -> vestíbulo (atajo)
	_door("A", Vector3(0, 1.25, 8.2), Vector3(U.DOOR * 2.0, 2.5, 0.3), 750, Vector3(0, 1.5, 7.98), Vector3(0, 0, 7.0))
	_door("B", Vector3(0, CEIL / 2.0, 22.0), Vector3(U.HALL * 2.0, CEIL, 0.3), 1250, Vector3(0, 1.6, 21.8), Vector3(0, 0, 20.8))
	_door("C", Vector3(25.1, CEIL / 2.0, 70.0), Vector3(5.8, CEIL, 0.3), 2000, Vector3(25.1, 1.6, 69.8), Vector3(25.1, 0, 68.8))
	_door("D", Vector3(-9.0, 1.3, 76.2), Vector3(3.2, 2.6, 0.3), 1500, Vector3(-9.0, 1.6, 76.0), Vector3(-9.0, 0, 75.0))
	_wall_buy("subfusil", Vector3(8.97, 1.7, 3.0), -90.0, Vector3(8.0, 0, 3.0))
	_wall_buy("fusil", Vector3(15.15, 1.7, 23.03), 0.0, Vector3(15.15, 0, 23.8))
	_wall_buy("francotirador", Vector3(-11.97, 1.9, 82.0), 90.0, Vector3(-11.2, 0, 82.0))
	_wall_buy("revolver", Vector3(8.97, 1.7, -3.0), -90.0, Vector3(8.0, 0, -3.0))
	_wall_buy("uzi", Vector3(12.0, 1.7, 23.03), 0.0, Vector3(12.0, 0, 23.8))
	_wall_buy("escopeta", Vector3(6.43, 1.7, 36.0), 90.0, Vector3(7.3, 0, 36.0))
	_build_box()


func _door(id: String, pos: Vector3, size: Vector3, cost: int, lpos: Vector3, ipos: Vector3) -> void:
	var body := U.solid_box(self, size, pos, Color(0.42, 0.12, 0.1))
	U.shiny(body, 0.4, 0.3)
	var lab := Label3D.new()
	lab.text = "PUERTA\n%d" % cost
	lab.font_size = 60
	lab.pixel_size = 0.006
	lab.outline_size = 8
	lab.modulate = Color(1.0, 0.9, 0.4)
	lab.rotation_degrees = Vector3(0, 180, 0)
	lab.position = lpos
	add_child(lab)
	interactables.append({"type": "door", "id": id, "pos": ipos, "cost": cost, "node": body, "label": lab, "done": false})


func _wall_buy(id: String, pos: Vector3, yaw: float, ipos: Vector3) -> void:
	var d: Dictionary = W.DATA[id]
	var root := Node3D.new()
	root.position = pos
	root.rotation_degrees.y = yaw
	add_child(root)
	U.box(root, Vector3(2.2, 0.9, 0.04), Vector3(0, 0, 0.02), Color(0.72, 0.72, 0.75))
	var gun := U.gun_model(id)
	gun.rotation_degrees.y = 90.0
	gun.position = Vector3(0.15, 0.05, 0.1)
	root.add_child(gun)
	var lab := Label3D.new()
	lab.text = "%s\n%d puntos\n%s" % [d["name"], d["price"], W.damage_text(id)]
	lab.font_size = 36
	lab.pixel_size = 0.0035
	lab.outline_size = 0
	lab.modulate = Color(0.5, 0.05, 0.05)
	lab.position = Vector3(0, -0.65, 0.05)
	root.add_child(lab)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.3, 0.2)
	l.light_energy = 0.8
	l.omni_range = 3.5
	l.position = Vector3(0, 0, 0.8)
	root.add_child(l)
	interactables.append({"type": "wall", "weapon": id, "pos": ipos, "done": false})


func _build_box() -> void:
	box_root = Node3D.new()
	add_child(box_root)
	var wood := Color(0.36, 0.2, 0.1)
	var gold := Color(0.85, 0.7, 0.2)
	U.solid_box(box_root, Vector3(1.3, 0.7, 0.8), Vector3(0, 0.35, 0), wood)
	U.box(box_root, Vector3(0.1, 0.72, 0.82), Vector3(-0.4, 0.35, 0), gold)
	U.box(box_root, Vector3(0.1, 0.72, 0.82), Vector3(0.4, 0.35, 0), gold)
	box_lid = Node3D.new()
	box_lid.position = Vector3(0, 0.7, -0.4)
	box_root.add_child(box_lid)
	U.box(box_lid, Vector3(1.3, 0.18, 0.8), Vector3(0, 0.09, 0.4), wood)
	U.box(box_lid, Vector3(0.1, 0.2, 0.82), Vector3(-0.4, 0.09, 0.4), gold)
	U.box(box_lid, Vector3(0.1, 0.2, 0.82), Vector3(0.4, 0.09, 0.4), gold)
	# modelo exportado de la caja: sustituye a la de código (que se queda solo como choque)
	var real := U.imported_model("caja", box_root)
	if real != null:
		for c in box_root.get_children():
			if c is MeshInstance3D:
				c.visible = false
			for cc in c.get_children():
				if cc is MeshInstance3D:
					cc.visible = false
		box_root.add_child(real)
	var beam := U.box(box_root, Vector3(0.5, 3.2, 0.5), Vector3(0, 1.8, 0), Color(0.2, 0.9, 1.0, 0.18), true)
	beam.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var l := OmniLight3D.new()
	l.light_color = Color(0.3, 0.9, 1.0)
	l.light_energy = 0.9
	l.omni_range = 5.0
	l.position = Vector3(0, 1.2, 0)
	box_root.add_child(l)
	box_show = Node3D.new()
	box_show.position = Vector3(0, 0.6, 0)
	box_root.add_child(box_show)
	for id in W.BOX_POOL:
		var g := U.gun_model(id)
		U.toonify(g, 0.006)
		g.rotation_degrees.y = 90.0      # de lado, para que se vea entera
		g.scale = Vector3.ONE * 1.5
		g.visible = false
		box_show.add_child(g)
		box_guns[id] = g
	box_label = Label3D.new()
	box_label.text = "?"
	box_label.font_size = 120
	box_label.pixel_size = 0.006
	box_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	box_label.modulate = Color(0.4, 0.95, 1.0)
	box_label.position = Vector3(0, 2.5, 0)
	box_root.add_child(box_label)
	box_item = {"type": "box", "pos": Vector3.ZERO, "done": false}
	interactables.append(box_item)
	_place_box(randi() % box_spots.size())   # empieza en una sala al azar


func _build_hud() -> void:
	hud = HudScript.new()
	hud.game = self
	add_child(hud)
	msg = hud.msg
	prompt = hud.prompt
	small_lbl = hud.small_lbl
	dmg_rect = hud.dmg_rect
	# capa propia por encima del HUD para el cegado
	var top := CanvasLayer.new()
	top.layer = 5
	add_child(top)
	blind_rect = ColorRect.new()
	blind_rect.color = Color(1.0, 1.0, 0.97, 0.0)
	blind_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blind_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(blind_rect)


func _build_env() -> void:
	G.cargar()
	var env := G.entorno()
	world_env = env
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _apply_gfx() -> void:
	G.aplicar(world_env, get_viewport())
	for e in ceil_lights:
		var l: SpotLight3D = e[0]
		l.shadow_enabled = G.nivel >= 2 or (G.nivel == 1 and e[1])
		l.light_size = 0.35 if G.nivel >= 2 else 0.0     # sombras suaves (penumbra real)
	if mapa != null:
		mapa.ajustar_gfx(world_env)
	elif instituto != null:
		instituto.ajustar_gfx(world_env)
	amb0 = world_env.ambient_light_energy
	if isa_fog:
		world_env.volumetric_fog_density = 0.06


func _on_node_added(n: Node) -> void:
	if n is GeometryInstance3D:
		n.gi_mode = GeometryInstance3D.GI_MODE_DISABLED


func _unhandled_key_input(event: InputEvent) -> void:
	if event.pressed and not event.echo and event.keycode == KEY_F3:
		G.siguiente()
		_apply_gfx()
		toast_small("Gráficos: " + G.NOMBRES[G.nivel] + "  (F3 para cambiar)")


# ---------------------------------------------------------------
# El instituto entero (aula, aseos, pasillos, cafetería, biblioteca,
# patio y vestíbulo) se construye en cesur.gd; el plano está en util.gd
# ---------------------------------------------------------------
func _build_room() -> void:
	var inst = CesurScript.new()
	inst.name = "Instituto"
	inst.game = self
	add_child(inst)
	inst.construir()
	instituto = inst
	if not U.bloques.is_empty():
		U.preparar_nav(0.45)      # los enemigos rodean la pista de pádel del patio
	_build_shop()


# Un bloque de 6 puestos con las mesas pegadas, cada uno con su ordenador
func _desk_block(cx: float, z: float) -> void:
	U.solid_box(self, Vector3(7.8, 0.8, 0.9), Vector3(cx, 0.4, z), Color(0.92, 0.92, 0.9))
	for i in range(1, 6):
		U.box(self, Vector3(0.02, 0.01, 0.9), Vector3(cx + (i - 3) * 1.3, 0.8, z), Color(0.65, 0.65, 0.67))
	var screens := [Color(0.2, 0.4, 0.85), Color(0.08, 0.08, 0.12), Color(0.9, 0.92, 0.97)]
	for i in 6:
		var x := cx + (i - 2.5) * 1.3
		U.box(self, Vector3(0.1, 0.25, 0.1), Vector3(x, 0.92, z - 0.1), Color(0.1, 0.1, 0.12))
		U.box(self, Vector3(0.9, 0.52, 0.04), Vector3(x, 1.3, z - 0.1), Color(0.05, 0.05, 0.07))
		U.box(self, Vector3(0.82, 0.44, 0.01), Vector3(x, 1.3, z - 0.075), screens[randi() % screens.size()], true)
		U.box(self, Vector3(0.45, 0.02, 0.15), Vector3(x, 0.81, z + 0.2), Color(0.1, 0.1, 0.12))
		# silla
		U.box(self, Vector3(0.5, 0.08, 0.5), Vector3(x, 0.5, z + 0.9), Color(0.1, 0.15, 0.35))
		U.box(self, Vector3(0.5, 0.5, 0.06), Vector3(x, 0.8, z + 1.15), Color(0.1, 0.15, 0.35))


func _ceiling(w: float, d: float, pos: Vector3) -> void:
	var c := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w, d)
	c.mesh = pm
	c.material_override = U.mat(Color(0.9, 0.9, 0.86))
	c.position = pos
	c.rotation_degrees = Vector3(180, 0, 0)
	c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(c)


# Panel luminoso en el techo + foco que ilumina hacia abajo
func _ceiling_light(pos: Vector3, w: float, d: float, range_m: float, col: Color, flicker: bool, shadow: bool) -> void:
	var panel := MeshInstance3D.new()
	var pp := PlaneMesh.new()
	pp.size = Vector2(w, d)
	panel.mesh = pp
	panel.material_override = U.mat(col, true)
	panel.material_override.emission_energy_multiplier = 4.0   # brilla (bloom) y rebota en la GI
	panel.position = Vector3(pos.x, pos.y + 0.29, pos.z)
	panel.rotation_degrees = Vector3(180, 0, 0)
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(panel)
	var l := SpotLight3D.new()
	l.position = pos
	l.rotation_degrees = Vector3(-90, 0, 0)
	l.light_color = col
	l.light_energy = 2.0
	l.spot_range = range_m
	l.spot_angle = 80.0
	l.spot_attenuation = 0.6
	l.shadow_enabled = shadow
	l.shadow_blur = 1.5
	l.light_volumetric_fog_energy = 1.4
	add_child(l)
	ceil_lights.append([l, shadow])
	if flicker:
		l.set_meta("base", 2.0)
		hall_lights.append(l)


# ---------------------------------------------------------------
# Easter egg: armario del aula con la maleta de Jorge dentro.
# Se abre con el código 2503 (pista en un pósit del espejo del aseo
# izquierdo) o con una ganzúa escondida en un sitio al azar.
# ---------------------------------------------------------------
func _build_armario() -> void:
	var white := Color(0.9, 0.9, 0.92)
	var x := ARM_X
	var z := ARM_Z
	U.solid_box(self, Vector3(1.7, 2.1, 0.03), Vector3(x, 1.05, z - 0.285), white.darkened(0.15))   # fondo
	for sx in [-1.0, 1.0]:
		U.solid_box(self, Vector3(0.03, 2.1, 0.6), Vector3(x + sx * 0.835, 1.05, z), white)        # laterales
	U.solid_box(self, Vector3(1.7, 0.03, 0.6), Vector3(x, 2.085, z), white)                        # techo
	U.solid_box(self, Vector3(1.7, 0.06, 0.6), Vector3(x, 0.03, z), white)                         # suelo
	U.box(self, Vector3(1.64, 0.025, 0.56), Vector3(x, 1.4, z), white)                              # balda
	var folders := [Color(0.7, 0.15, 0.1), Color(0.1, 0.3, 0.6), Color(0.2, 0.5, 0.2)]
	for i in 3:                                                                                     # carpetas en la balda
		U.box(self, Vector3(0.08, 0.32, 0.26), Vector3(x - 0.55 + i * 0.1, 1.575, z - 0.1), folders[i])
	arm_block = U.solid_box(self, Vector3(1.7, 2.1, 0.05), Vector3(x, 1.05, z + 0.28), white, false)

	# dos puertas con bisagra en los lados
	for sx in [-1.0, 1.0]:
		var hinge := Node3D.new()
		hinge.position = Vector3(x + sx * 0.85, 1.05, z + 0.3)
		add_child(hinge)
		U.box(hinge, Vector3(0.84, 2.06, 0.03), Vector3(-sx * 0.425, 0, 0.015), white)
		U.box(hinge, Vector3(0.025, 0.28, 0.035), Vector3(-sx * 0.78, 0.0, 0.05), Color(0.6, 0.6, 0.64))   # tirador
		arm_doors.append([hinge, sx * 100.0])
		if sx < 0.0:
			var note := Label3D.new()
			note.text = "PROPIEDAD DE JORGE\nNO TOCAR"
			note.font_size = 30
			note.pixel_size = 0.0035
			note.outline_size = 0
			note.modulate = Color(0.6, 0.05, 0.05)
			note.position = Vector3(0.425, 0.35, 0.035)
			hinge.add_child(note)
	# candado con teclado numérico en el lateral derecho
	var pad := Node3D.new()
	pad.position = Vector3(x + 0.87, 1.2, z + 0.12)
	pad.rotation_degrees.y = 90.0
	add_child(pad)
	U.box(pad, Vector3(0.14, 0.22, 0.03), Vector3.ZERO, Color(0.12, 0.12, 0.14))
	U.box(pad, Vector3(0.1, 0.035, 0.005), Vector3(0, 0.075, 0.016), Color(0.1, 0.35, 0.15), true)
	for r in 4:
		for c in 3:
			U.box(pad, Vector3(0.022, 0.022, 0.008), Vector3(-0.03 + c * 0.03, 0.03 - r * 0.03, 0.017), Color(0.7, 0.7, 0.72))
	arm_led = U.sphere(pad, 0.008, Vector3(0.05, 0.09, 0.016), Color(1.0, 0.1, 0.05), true)
	interactables.append({"type": "armario", "pos": Vector3(x + 0.5, 0, z + 0.9), "done": false})

	# la maleta de Jorge, de pie en el suelo del armario
	maleta = Node3D.new()
	maleta.position = Vector3(x + 0.2, 0.06, z - 0.02)
	maleta.rotation_degrees.y = -12.0
	add_child(maleta)
	var shell := Color(0.32, 0.34, 0.37)
	var dark := Color(0.08, 0.08, 0.09)
	U.box(maleta, Vector3(0.42, 0.56, 0.22), Vector3(0, 0.33, 0), shell)                     # cuerpo
	U.box(maleta, Vector3(0.38, 0.2, 0.04), Vector3(0, 0.5, 0.12), shell.darkened(0.15))     # bolsillo de arriba
	U.box(maleta, Vector3(0.38, 0.26, 0.03), Vector3(0, 0.22, 0.12), shell.darkened(0.1))    # bolsillo de abajo
	U.box(maleta, Vector3(0.43, 0.012, 0.23), Vector3(0, 0.4, 0), dark)                       # cremallera
	for sx in [-1.0, 1.0]:
		U.box(maleta, Vector3(0.02, 0.2, 0.02), Vector3(sx * 0.12, 0.7, -0.08), Color(0.55, 0.56, 0.6))   # barras del asa
		var wheel := U.cylinder(maleta, 0.03, 0.025, Vector3(sx * 0.16, 0.03, -0.08), dark)
		wheel.rotation_degrees.z = 90.0
	U.box(maleta, Vector3(0.28, 0.03, 0.03), Vector3(0, 0.8, -0.08), dark)                    # asa
	U.box(maleta, Vector3(0.03, 0.12, 0.05), Vector3(-0.225, 0.35, 0), dark)                  # asa lateral
	var real := U.imported_model("maleta", maleta)
	if real != null:
		for c in maleta.get_children():
			c.queue_free()
		maleta.add_child(real)

	# ganzúa en un sitio al azar
	pick_node = Node3D.new()
	pick_node.position = PICK_SPOTS[randi() % PICK_SPOTS.size()]
	pick_node.rotation_degrees.y = randf() * 360.0
	add_child(pick_node)
	var steel := U.gunmetal(Color(0.6, 0.62, 0.66))
	steel.metallic = 1.0
	steel.roughness = 0.2
	U.box(pick_node, Vector3(0.09, 0.018, 0.022), Vector3(0, 0.01, 0), Color(0.15, 0.1, 0.08))   # mango
	U.box_m(pick_node, Vector3(0.13, 0.005, 0.005), Vector3(0.11, 0.01, 0), steel)              # púa
	U.box_m(pick_node, Vector3(0.006, 0.014, 0.005), Vector3(0.175, 0.016, 0), steel)           # punta doblada
	var glint := OmniLight3D.new()                                                              # brillito para encontrarla
	glint.light_color = Color(1.0, 0.95, 0.8)
	glint.light_energy = 0.5
	glint.omni_range = 0.7
	glint.position = Vector3(0.05, 0.15, 0)
	pick_node.add_child(glint)
	interactables.append({"type": "ganzua", "pos": pick_node.position, "done": false})

	# pista del código: pósit pegado en el espejo del aseo izquierdo
	var postit := U.box(self, Vector3(0.006, 0.2, 0.2), Vector3(-(U.WC_X + 3.4 - 0.06), 2.2, 10.3), Color(1.0, 0.9, 0.3))
	postit.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var hint := Label3D.new()
	hint.text = "Jorge\n25·03"
	hint.font_size = 26
	hint.pixel_size = 0.0022
	hint.outline_size = 0
	hint.modulate = Color(0.1, 0.1, 0.35)
	hint.rotation_degrees.y = 90.0
	hint.position = postit.position + Vector3(0.005, 0, 0)
	add_child(hint)

	snd_beep = AudioStreamPlayer.new()
	snd_beep.volume_db = -6.0
	add_child(snd_beep)


func _arm_unlock() -> void:
	if Net.online:
		_net_arm_open.rpc()
	else:
		_arm_open()


@rpc("any_peer", "call_local", "reliable")
func _net_arm_open() -> void:
	_arm_open()


func _arm_open() -> void:
	if arm_open:
		return
	arm_open = true
	for it in interactables:
		if it["type"] == "armario":
			it["done"] = true
	arm_block.collision_layer = 0
	arm_led.material_override = U.mat(Color(0.1, 1.0, 0.2), true)
	for d in arm_doors:
		var tw := create_tween()
		tw.tween_property(d[0], "rotation_degrees:y", d[1], 1.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	interactables.append({"type": "maleta", "pos": Vector3(ARM_X, 0, ARM_Z + 0.8), "done": false})
	_toast("¡El armario se ha abierto! Dentro hay una maleta...")


# Cada jugador abre la maleta una vez: Pistola Rayo y 2503 puntos
func _open_maleta(it) -> void:
	it["done"] = true
	points += 2503
	player.give_weapon("pistola_rayo")
	_toast("La maleta de Jorge: ¡Pistola Rayo y 2503 puntos!")
	snd_beep.stream = U.make_powerup()
	snd_beep.play()
	var gun := U.gun_model("pistola_rayo")
	gun.position = maleta.position + Vector3(0, 0.6, 0.35)
	gun.rotation_degrees.y = 90.0
	gun.scale = Vector3.ONE * 1.6
	add_child(gun)
	var l := OmniLight3D.new()
	l.light_color = Color(0.2, 1.0, 0.4)
	l.light_energy = 2.5
	l.omni_range = 3.0
	gun.add_child(l)
	var tw := create_tween()
	tw.set_parallel()
	tw.tween_property(gun, "position:y", gun.position.y + 0.7, 1.2).set_trans(Tween.TRANS_SINE)
	tw.tween_property(gun, "rotation_degrees:y", 90.0 + 720.0, 2.0)
	tw.chain().tween_property(gun, "scale", Vector3.ONE * 0.01, 0.3)
	tw.chain().tween_callback(gun.queue_free)


# ---------- Teclado del candado ----------
func _open_code() -> void:
	if code_layer == null:
		code_layer = CanvasLayer.new()
		code_layer.layer = 4
		add_child(code_layer)
		var center := CenterContainer.new()
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		code_layer.add_child(center)
		var bg := ColorRect.new()
		bg.color = Color(0.03, 0.03, 0.05, 0.92)
		bg.custom_minimum_size = Vector2(420, 240)
		center.add_child(bg)
		var title := Label.new()
		title.text = "CANDADO DEL ARMARIO"
		title.add_theme_font_size_override("font_size", 24)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.position = Vector2(0, 18)
		title.size = Vector2(420, 30)
		bg.add_child(title)
		code_lbl = Label.new()
		code_lbl.add_theme_font_size_override("font_size", 56)
		code_lbl.add_theme_color_override("font_color", Color(0.3, 1.0, 0.45))
		code_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		code_lbl.position = Vector2(0, 60)
		code_lbl.size = Vector2(420, 70)
		bg.add_child(code_lbl)
		code_msg = Label.new()
		code_msg.add_theme_font_size_override("font_size", 16)
		code_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		code_msg.position = Vector2(0, 150)
		code_msg.size = Vector2(420, 70)
		bg.add_child(code_msg)
	code_txt = ""
	code_open = true
	player.input_blocked = true
	code_layer.visible = true
	_code_refresh(CODE_HELP if Input.get_connected_joypads().is_empty() else CODE_HELP_MANDO, Color(0.8, 0.8, 0.85))


const CODE_HELP := "Escribe el código de 4 cifras\nRetroceso borrar · Esc salir"
const CODE_HELP_MANDO := "Mando: cruceta ↑↓ elegir número · A meterlo\nB borrar · Start salir"


func _close_code() -> void:
	code_open = false
	code_layer.visible = false
	player.input_blocked = false
	e_prev = true       # que la E que sigue pulsada no lo vuelva a abrir


func _code_refresh(text: String, col: Color) -> void:
	var shown := ""
	for i in 4:
		shown += (code_txt[i] if i < code_txt.length() else "_") + " "
	code_lbl.text = shown.strip_edges()
	code_msg.text = text
	code_msg.add_theme_color_override("font_color", col)


func _input(event: InputEvent) -> void:
	if not code_open or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	if code_txt.length() >= 4:
		return          # comprobando el código
	if event.keycode == KEY_ESCAPE:
		_close_code()
	elif event.keycode == KEY_BACKSPACE:
		code_txt = code_txt.left(-1)
		_code_refresh(CODE_HELP, Color(0.8, 0.8, 0.85))
	elif event.unicode >= 48 and event.unicode <= 57:
		code_txt += char(event.unicode)
		snd_beep.stream = U.make_beep(900.0)
		snd_beep.play()
		_code_refresh("", Color.WHITE)
		if code_txt.length() == 4:
			_check_code()


func _check_code() -> void:
	if code_txt == ARM_CODE:
		_code_refresh("¡CÓDIGO CORRECTO!", Color(0.3, 1.0, 0.4))
		await get_tree().create_timer(0.6).timeout
		_close_code()
		_arm_unlock()
	else:
		_code_refresh("CÓDIGO INCORRECTO", Color(1.0, 0.25, 0.2))
		snd_beep.stream = U.make_beep(180.0)
		snd_beep.play()
		await get_tree().create_timer(0.7).timeout
		code_txt = ""
		if code_open:
			_code_refresh(CODE_HELP, Color(0.8, 0.8, 0.85))

extends Node
# Red local (LAN): crear/buscar partidas, sala de espera y arranque sincronizado.
# Está registrado como autoload "Net", así que sobrevive a los reinicios de escena.
#
# Modelo: el anfitrión manda sobre el mundo (zombies, oleadas, caja, misión) y cada
# jugador manda sobre su propio personaje (movimiento, vida, puntos y armas).

signal lobby_changed
signal games_found_changed
signal status(text: String)

const PORT := 7777            # partida (ENet)
const DISCOVERY_PORT := 7778  # anuncios de partidas por broadcast UDP
const MAX_PLAYERS := 4
const SAVE_PATH := "user://red.cfg"

var mode := "solo"            # "solo", "coop" o "versus"
# Backrooms: CESUR no tiene salida. Al escapar apareces en otro sitio que no conoces
var mapa := "cesur"           # "cesur", "mojacar" o "indalo"
var bucle := 0                # vueltas que llevas (cuántas veces has "escapado")
var carry := {}               # lo que te llevas al siguiente mapa (puntos, armas, oleada...)
var online := false
var my_name := "Jugador"
var players := {}             # peer_id -> {"name", "skin"}
var started := false          # la partida está en marcha (no se aceptan más jugadores)
var running := false          # todos han cargado la escena: ya se pueden mandar RPC de juego
var ready_peers := {}
var last_status := ""         # último aviso (se enseña en el menú)
var found := {}               # id de partida -> {"name", "mode", "count", "time", "ips", "ip"}
var _sid := ""                # id de la partida que anunciamos

var _bcast: PacketPeerUDP
var _listen: PacketPeerUDP
var _bcast_t := 0.0
var _bcast_dests: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	status.connect(func(t): last_status = t)
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		my_name = str(cfg.get_value("red", "nombre", my_name))
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_failed)
	multiplayer.server_disconnected.connect(_on_server_gone)


func save_name(n: String) -> void:
	my_name = n.strip_edges().left(16)
	if my_name == "":
		my_name = "Jugador"
	var cfg := ConfigFile.new()
	cfg.set_value("red", "nombre", my_name)
	cfg.save(SAVE_PATH)


func is_host() -> bool:
	return not online or multiplayer.is_server()


func my_id() -> int:
	return multiplayer.get_unique_id() if online else 1


func pname(id: int) -> String:
	if players.has(id):
		return players[id]["name"]
	return "Jugador %d" % id


func local_ips() -> Array:
	var out: Array = []
	for a in IP.get_local_addresses():
		if a.begins_with("192.168.") or a.begins_with("10.") or a.begins_with("172."):
			out.append(a)
	return out


# =============================================================
# Crear / unirse / salir
# =============================================================
func host(m: String) -> bool:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS - 1)
	if err != OK:
		status.emit("No se pudo crear la partida (¿ya hay otra abierta en este PC?)")
		return false
	multiplayer.multiplayer_peer = peer
	online = true
	mode = m
	players = {1: {"name": my_name, "skin": _my_skin()}}
	_sid = str(randi())
	_bcast = PacketPeerUDP.new()
	_bcast.set_broadcast_enabled(true)
	# se anuncia en cada red del PC (WiFi, cable...) y en la general
	_bcast_dests = ["255.255.255.255"]
	for ip in local_ips():
		var parts: PackedStringArray = ip.split(".")
		_bcast_dests.append("%s.%s.%s.255" % [parts[0], parts[1], parts[2]])
	lobby_changed.emit()
	return true


func join(ip: String) -> void:
	leave()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(ip.strip_edges(), PORT) != OK:
		status.emit("No se pudo conectar a " + ip)
		return
	multiplayer.multiplayer_peer = peer
	online = true
	status.emit("Conectando a %s..." % ip)


func leave() -> void:
	if multiplayer.multiplayer_peer != null and online:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	online = false
	started = false
	running = false
	mode = "solo"
	players = {}
	ready_peers = {}
	_bcast = null
	lobby_changed.emit()


func _my_skin() -> Dictionary:
	var Ch = load("res://scripts/jugador/character.gd")
	return Ch.skin.duplicate()


func _on_connected() -> void:
	_register.rpc_id(1, my_name, _my_skin())


func _on_failed() -> void:
	leave()
	status.emit("No se pudo conectar. ¿Está la partida abierta y en la misma red?")


func _on_server_gone() -> void:
	var was_playing := started
	leave()
	status.emit("El anfitrión ha cerrado la partida")
	if was_playing:
		_back_to_menu()


func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server() and started:
		# la partida ya ha empezado: no se puede entrar a mitad
		multiplayer.multiplayer_peer.disconnect_peer(id)


func _on_peer_disconnected(id: int) -> void:
	if not players.has(id):
		return
	var who := pname(id)
	players.erase(id)
	ready_peers.erase(id)
	if multiplayer.is_server():
		_sync_lobby.rpc(players, mode)
	lobby_changed.emit()
	var game = get_tree().get_first_node_in_group("game")
	if game != null:
		game.net_player_left(id, who)


@rpc("any_peer", "reliable")
func _register(n: String, skin: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if started or players.size() >= MAX_PLAYERS:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	# nombres repetidos: se les añade un número
	var base := n
	var k := 2
	var taken := true
	while taken:
		taken = false
		for p in players.values():
			if p["name"] == n:
				taken = true
				n = "%s %d" % [base, k]
				k += 1
	players[id] = {"name": n, "skin": skin}
	_sync_lobby.rpc(players, mode)
	lobby_changed.emit()


@rpc("authority", "reliable")
func _sync_lobby(p: Dictionary, m: String) -> void:
	players = p
	mode = m
	lobby_changed.emit()


# El anfitrión cambia el modo desde la sala
func set_mode(m: String) -> void:
	mode = m
	if online and multiplayer.is_server():
		_sync_lobby.rpc(players, mode)
	lobby_changed.emit()


# =============================================================
# Arranque de la partida
# =============================================================
func start_game() -> void:
	if not multiplayer.is_server():
		return
	reset_loop()      # reiniciar siempre vuelve a empezar en CESUR
	_start.rpc(players, mode, mapa, bucle)


# Pasa al siguiente mapa del bucle (sin red recarga la escena directamente)
func go_to_map(m: String, b: int) -> void:
	if not online:
		mapa = m
		bucle = b
		var UiScript = load("res://scripts/interfaz/ui.gd")
		UiScript.autostart = true
		get_tree().paused = false
		get_tree().reload_current_scene()
	elif multiplayer.is_server():
		_start.rpc(players, mode, m, b)


@rpc("authority", "call_local", "reliable")
func _start(p: Dictionary, m: String, mp: String = "cesur", b: int = 0) -> void:
	players = p
	mode = m
	mapa = mp
	bucle = b
	started = true
	running = false
	ready_peers = {}
	var UiScript = load("res://scripts/interfaz/ui.gd")
	UiScript.autostart = true
	get_tree().paused = false
	get_tree().reload_current_scene()


# Lo llama la escena del juego al terminar de construirse
func scene_ready() -> void:
	if not online:
		running = true
		return
	_report_ready.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func _report_ready() -> void:
	if not multiplayer.is_server():
		return
	var sid := multiplayer.get_remote_sender_id()
	ready_peers[1 if sid == 0 else sid] = true
	for id in players:
		if not ready_peers.has(id):
			return
	_go.rpc()


@rpc("authority", "call_local", "reliable")
func _go() -> void:
	running = true
	var game = get_tree().get_first_node_in_group("game")
	if game != null:
		game.net_go()


func _back_to_menu() -> void:
	reset_loop()
	var UiScript = load("res://scripts/interfaz/ui.gd")
	UiScript.autostart = false
	get_tree().paused = false
	get_tree().reload_current_scene()


func reset_loop() -> void:
	mapa = "cesur"
	bucle = 0
	carry = {}


# Volver al menú desde la partida (cierra la conexión)
func quit_to_menu() -> void:
	leave()
	_back_to_menu()


# =============================================================
# Descubrimiento de partidas en la red local
# =============================================================
func start_listening() -> void:
	if _listen != null:
		return
	_listen = PacketPeerUDP.new()
	if _listen.bind(DISCOVERY_PORT) != OK:
		_listen = null
		status.emit("No se pueden buscar partidas (puerto ocupado). Usa \"Unirse por IP\".")


# Las IP terminadas en .1 suelen ser adaptadores virtuales (VirtualBox, VMware...)
func _best_ip(ips: Array) -> String:
	for ip in ips:
		if not str(ip).ends_with(".1"):
			return ip
	return ips[0]


func stop_listening() -> void:
	if _listen != null:
		_listen.close()
		_listen = null
	found = {}


func _process(delta: float) -> void:
	# el anfitrión anuncia su partida cada segundo mientras espera jugadores
	if _bcast != null and online and multiplayer.is_server() and not started:
		_bcast_t -= delta
		if _bcast_t <= 0.0:
			_bcast_t = 1.0
			var info := {"juego": "zombies_aula", "sid": _sid, "name": my_name, "mode": mode, "count": players.size()}
			var pkt := JSON.stringify(info).to_utf8_buffer()
			for dest in _bcast_dests:
				_bcast.set_dest_address(dest, DISCOVERY_PORT)
				_bcast.put_packet(pkt)
	if _listen != null:
		var changed := false
		while _listen.get_available_packet_count() > 0:
			var pkt := _listen.get_packet()
			var ip := _listen.get_packet_ip()
			var d = JSON.parse_string(pkt.get_string_from_utf8())
			if d is Dictionary and d.get("juego", "") == "zombies_aula":
				# la misma partida llega por cada red del anfitrión: se junta en una
				var sid: String = str(d.get("sid", ip))
				var ips: Array = found[sid]["ips"] if found.has(sid) else []
				if not ips.has(ip):
					ips.append(ip)
					changed = true
				d["ips"] = ips
				d["ip"] = _best_ip(ips)
				d["time"] = Time.get_ticks_msec()
				if not found.has(sid) or found[sid]["count"] != d["count"] or found[sid]["mode"] != d["mode"]:
					changed = true
				found[sid] = d
		for sid in found.keys():
			if Time.get_ticks_msec() - int(found[sid]["time"]) > 3500:
				found.erase(sid)
				changed = true
		if changed:
			games_found_changed.emit()

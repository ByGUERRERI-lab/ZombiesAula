extends Node
# Cámara libre (F8, o el botón CÁMARA LIBRE del menú): vuela por el mapa
# atravesando paredes para ver lo que hay sin tener que jugar. Mientras está
# activa se paran las oleadas y la bomba, los enemigos se quedan quietos y no
# te pueden hacer daño. Solo funciona en partidas de un jugador.

const U = preload("res://scripts/nucleo/util.gd")
const UiScript = preload("res://scripts/interfaz/ui.gd")
const MapasScript = preload("res://scripts/mapas/mapas.gd")

const VEL := 6.0
const VEL_MIN := 1.0
const VEL_MAX := 40.0
const SENS := 0.0025
const AYUDA := "F8  salir  ·  Intro  dejar al jugador aquí\nWASD  moverse  ·  Q / E  bajar / subir\nShift  rápido  ·  rueda  velocidad\nTab  siguiente lugar  ·  C  vista aérea\nO  abrir puertas  ·  F  linterna\nN  poner enemigo  ·  B  enemigos quietos / activos\nM  siguiente mapa  ·  H  ocultar esto"
# nombre, posición, giro y cabeceo
const LUGARES := [
	["Aula", Vector3(0.0, 1.7, 6.5), 0.0, 0.0],
	["Aseos", Vector3(7.0, 1.7, 9.2), PI, 0.0],
	["Distribuidor", Vector3(-3.0, 1.7, 23.0), -2.6, 0.0],
	["Pasillo de la cafetería", Vector3(8.0, 1.7, 26.0), -PI / 2.0, 0.0],
	["Cafetería", Vector3(14.0, 1.7, 31.0), PI, -0.1],
	["Pasillo largo", Vector3(25.0, 1.7, 28.0), PI, 0.0],
	["Casino", Vector3(29.2, 1.7, 41.6), -2.0, -0.05],
	["Biblioteca", Vector3(20.0, 1.7, 63.0), PI / 2.0, 0.0],
	["Pasillo norte", Vector3(24.0, 1.7, 73.0), PI / 2.0, 0.0],
	["Vestíbulo", Vector3(0.0, 1.7, 78.0), PI, 0.15],
	["Pádel", Vector3(-12.0, 1.7, 30.0), 2.6, 0.0],
]
const ENEMIGOS := ["zombie", "ninja", "boss", "bu", "isabella", "ian", "victor"]

static var al_cargar := false     # true = entra en la cámara libre nada más cargar el mapa

var game
var ui
var activa := false
var cam: Camera3D
var prev_cam: Camera3D
var linterna: SpotLight3D
var yaw := 0.0
var pitch := 0.0
var vel := VEL
var lugar := -1
var enemigo := 0
var quietos := true
var aerea := false
var niebla := 0.0
var luz_jugador := false
var cuerpo_jugador := true
var marcas: Array = []            # marcadores de misión ocultos mientras vuelas
var capas: Array = []             # interfaz oculta mientras vuelas
var capa: CanvasLayer
var panel: PanelContainer
var estado: Label
var aviso: Label


func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = 75.0
	cam.near = 0.05
	add_child(cam)
	linterna = SpotLight3D.new()
	linterna.light_color = Color(1.0, 0.94, 0.82)
	linterna.light_energy = 4.0
	linterna.spot_range = 30.0
	linterna.spot_angle = 26.0
	linterna.shadow_enabled = true
	linterna.visible = false
	cam.add_child(linterna)
	capa = CanvasLayer.new()
	capa.layer = 6
	capa.visible = false
	add_child(capa)
	panel = PanelContainer.new()
	panel.position = Vector2(14, 14)
	panel.modulate.a = 0.9
	capa.add_child(panel)
	var vb := VBoxContainer.new()
	panel.add_child(vb)
	var titulo := Label.new()
	titulo.text = "CÁMARA LIBRE"
	titulo.add_theme_color_override("font_color", Color(0.61, 0.83, 0.23))
	titulo.add_theme_font_size_override("font_size", 20)
	vb.add_child(titulo)
	var ayuda := Label.new()
	ayuda.text = AYUDA
	ayuda.add_theme_font_size_override("font_size", 14)
	vb.add_child(ayuda)
	estado = Label.new()
	estado.add_theme_color_override("font_color", Color(0.75, 0.85, 0.7))
	estado.add_theme_font_size_override("font_size", 14)
	estado.position = Vector2(14, 0)
	estado.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	estado.offset_top = -30.0
	estado.offset_left = 14.0
	capa.add_child(estado)
	aviso = Label.new()
	aviso.set_anchors_preset(Control.PRESET_CENTER_TOP)
	aviso.offset_left = -300.0
	aviso.offset_right = 300.0
	aviso.offset_top = 20.0
	aviso.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	aviso.add_theme_font_size_override("font_size", 24)
	aviso.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	aviso.add_theme_constant_override("outline_size", 6)
	capa.add_child(aviso)
	if al_cargar:
		al_cargar = false
		activar.call_deferred()


func activar() -> void:
	if activa:
		return
	if Net.online:
		game.toast_small("La cámara libre solo funciona en partidas de un jugador")
		return
	var pl = game.player
	if pl.dead or pl.downed or pl.frozen or ui.state != 1 or ui._shop_open():
		return
	activa = true
	game.explorando = true
	pl.frozen = true
	pl.input_blocked = true
	luz_jugador = pl.flashlight.visible
	pl.flashlight.visible = false
	cuerpo_jugador = pl.model.visible
	pl.model.visible = false          # la cámara empieza dentro de su cabeza
	marcas.clear()
	if game.mission != null:
		for m: Node3D in game.mission.markers.values():
			if m.visible:
				m.visible = false
				marcas.append(m)
	prev_cam = get_viewport().get_camera_3d()
	var t: Transform3D = prev_cam.global_transform
	cam.global_position = t.origin
	yaw = t.basis.get_euler().y
	pitch = t.basis.get_euler().x
	_aplicar_giro()
	cam.current = true
	linterna.visible = luz_jugador
	quietos = true
	capas.clear()
	for c: CanvasLayer in game.find_children("*", "CanvasLayer", true, false):
		if c.layer >= 1 and c != capa and c != ui.layer and c.visible:
			c.visible = false
			capas.append(c)
	capa.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func desactivar(traer_jugador: bool = false) -> void:
	if not activa:
		return
	if aerea:
		_set_aerea(false)
	activa = false
	game.explorando = false
	_mover_enemigos(true)
	var pl = game.player
	pl.frozen = false
	pl.input_blocked = false
	pl.flashlight.visible = luz_jugador
	pl.model.visible = cuerpo_jugador
	for m: Node3D in marcas:
		if is_instance_valid(m):
			m.visible = true
	if traer_jugador:
		var p := U.clamp_pos(Vector3(cam.global_position.x, 0.05, cam.global_position.z), 0.4)
		pl.global_position = Vector3(p.x, 0.05, p.z)
		pl.rotation.y = yaw
	if is_instance_valid(prev_cam):
		prev_cam.current = true
	linterna.visible = false
	for c: CanvasLayer in capas:
		if is_instance_valid(c):
			c.visible = true
	capa.visible = false


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo:
		return
	if event.keycode == KEY_F8:
		if activa:
			desactivar()
		else:
			activar()
		return
	if not activa:
		return
	match event.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			desactivar(true)
		KEY_TAB:
			_siguiente_lugar()
		KEY_C:
			_set_aerea(not aerea)
		KEY_O:
			_abrir_puertas()
		KEY_F:
			linterna.visible = not linterna.visible
		KEY_H:
			panel.visible = not panel.visible
		KEY_N:
			_poner_enemigo()
		KEY_B:
			quietos = not quietos
			_avisar("Enemigos quietos" if quietos else "Enemigos activos (no te hacen daño)")
		KEY_M:
			_siguiente_mapa()


func _input(event: InputEvent) -> void:
	if not activa:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * SENS
		pitch = clampf(pitch - event.relative.y * SENS, -1.5, 1.5)
		_aplicar_giro()
	elif event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and ui.state == 1:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			vel = minf(vel * 1.2, VEL_MAX)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			vel = maxf(vel / 1.2, VEL_MIN)


func _process(delta: float) -> void:
	if not activa:
		return
	var d := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): d.z -= 1.0
	if Input.is_key_pressed(KEY_S): d.z += 1.0
	if Input.is_key_pressed(KEY_A): d.x -= 1.0
	if Input.is_key_pressed(KEY_D): d.x += 1.0
	var sube := 0.0
	if Input.is_key_pressed(KEY_E): sube += 1.0
	if Input.is_key_pressed(KEY_Q): sube -= 1.0
	var v := vel * (3.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	cam.global_position += (cam.global_transform.basis * d.normalized() + Vector3.UP * sube) * v * delta
	_mover_enemigos(not quietos)
	var p := cam.global_position
	var sitio := "" if U.abierto() else str(U.NOMBRES_SALA[U.region(p)]) + "  ·  "
	estado.text = "%s%.1f, %.1f, %.1f  ·  velocidad %.1f m/s" % [sitio, p.x, p.y, p.z, v]


func _aplicar_giro() -> void:
	cam.global_rotation = Vector3(pitch, yaw, 0.0)


func _ir(pos: Vector3, y: float, x: float) -> void:
	cam.global_position = pos
	yaw = y
	pitch = x
	_aplicar_giro()


func _lista_lugares() -> Array:
	if game.mapa == null:
		return LUGARES
	var r: Array = [["Inicio", game.start_pos + Vector3(0, 1.65, 0), game.start_yaw, 0.0]]
	for pista: Array in game.mapa.pistas:
		r.append([pista[1], pista[3] + Vector3(0.0, 1.7, 3.0), 0.0, 0.0])
	return r


func _siguiente_lugar() -> void:
	if aerea:
		_set_aerea(false)
	var l := _lista_lugares()
	lugar = (lugar + 1) % l.size()
	var e: Array = l[lugar]
	_ir(e[1], e[2], e[3])
	_avisar(e[0])


# Vista desde arriba sin techos ni niebla, para ver el plano entero
func _set_aerea(on: bool) -> void:
	aerea = on
	get_tree().set_group("techos", "visible", not on)
	var env: Environment = game.world_env
	if on:
		niebla = env.fog_density
		env.fog_density = 0.002
		if game.mapa == null:
			_ir(Vector3(19.0, 50.0, 45.0), PI / 2.0, -1.3)
		else:
			var c: Vector2 = U.limites.get_center()
			_ir(Vector3(c.x, 70.0, c.y + 40.0), 0.0, -1.05)
	else:
		env.fog_density = niebla


func _abrir_puertas() -> void:
	var n := 0
	for it in game.interactables:
		if it["type"] == "door" and not it["done"]:
			game._open_door(it)
			n += 1
	_avisar("Puertas abiertas" if n > 0 else "No quedan puertas cerradas")


func _poner_enemigo() -> void:
	var kind: String = ENEMIGOS[enemigo]
	enemigo = (enemigo + 1) % ENEMIGOS.size()
	var delante := cam.global_position - cam.global_transform.basis.z * 4.0
	game._add_enemy(kind, 9999.0, Vector3(delante.x, 0.0, delante.z))
	_avisar("Enemigo: " + kind)


func _siguiente_mapa() -> void:
	Net.mapa = MapasScript.siguiente(Net.mapa)
	UiScript.autostart = true
	al_cargar = true
	get_tree().reload_current_scene()


# Con la cámara libre los enemigos y Xavier se quedan parados (si no, irían a por el jugador)
func _mover_enemigos(si: bool) -> void:
	var modo := Node.PROCESS_MODE_INHERIT if si else Node.PROCESS_MODE_DISABLED
	for z: Node in get_tree().get_nodes_in_group("zombies"):
		z.process_mode = modo
	if game.xavier != null:
		game.xavier.process_mode = modo


func _avisar(texto: String) -> void:
	aviso.text = texto
	aviso.modulate.a = 1.0
	var tw := aviso.create_tween()
	tw.tween_interval(1.2)
	tw.tween_property(aviso, "modulate:a", 0.0, 0.4)

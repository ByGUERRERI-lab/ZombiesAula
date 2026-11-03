extends Node
# Consola de pruebas: se abre con º (la tecla de la izquierda del 1) o con F1.
# Sirve para moverte entre mapas, pasar a modo espectador (la cámara libre de
# camara_libre.gd) o volver a modo normal y probar cosas sin tener que jugar
# la partida entera. Escribe "ayuda" para ver todos los comandos.
# Flecha arriba / abajo: comandos anteriores · Esc: cerrar.

const W = preload("res://scripts/jugador/weapons.gd")
const CamaraScript = preload("res://scripts/nucleo/camara_libre.gd")
const BebidasScript = preload("res://scripts/jugador/bebidas.gd")
const HudScript = preload("res://scripts/interfaz/hud.gd")

const MAPAS := ["cesur", "mojacar", "indalo"]
const ENEMIGOS := ["zombie", "ninja", "boss", "bu", "isabella", "ian", "victor"]
const AYUDA := """[color=#9be05a]COMANDOS[/color]
  [b]mapa[/b] cesur | mojacar | indalo   ir a ese mapa (añade [b]espectador[/b] para llegar volando)
  [b]espectador[/b]                     cámara libre: vuela por el mapa (F8 también)
  [b]normal[/b]                         vuelves a jugar donde esté la cámara
  [b]dios[/b]                           no te hacen daño (otra vez para quitarlo)
  [b]puntos[/b] 5000                    te da puntos
  [b]oleada[/b] 5                       salta a esa oleada (la 5 trae a Majin Bu)
  [b]enemigo[/b] bu [vida]              pone un enemigo delante: zombie, ninja, boss, bu, isabella, ian, victor
  [b]monstruos[/b]                      galería: todos los monstruos en fila delante de ti, quietos y con su nombre
  [b]monstruos andar[/b] | [b]quitar[/b]       que den vueltas andando (otra vez para pararlos) · quitarlos
  [b]matar[/b]                          mata a todos los enemigos
  [b]perro[/b]                          quitar / poner al perro acompañante
  [b]arma[/b] fusil                     te da un arma: pistola, subfusil, fusil, francotirador, pistola_rayo
  [b]municion[/b]                       munición llena
  [b]bebida[/b] tanque | todas          bebida de las máquinas: tanque, rapida, doble, revivir, turbo
  [b]curar[/b]                          vida llena
  [b]pruebas[/b]                        supera todas las pruebas del mapa (Mojácar / Indalo)
  [b]prueba[/b] 2                       te lleva delante de la prueba número 2
  [b]hackeo[/b]                         Jesús te hackea (la terminal de defensa de la oleada 10)
  [b]cerdo[/b] | [b]cerdo ir[/b] | [b]cerdo reventar[/b]   Mojácar: darle de comer a Jorge el cerdo · ir a él · que reviente
  [b]padel[/b]                          empieza un partido de pádel contra Víctor (en CESUR)
  [b]reiniciar[/b]                      vuelve a empezar este mapa
  [b]limpiar[/b]                        borra la consola"""

var game
var abierta := false
var capa: CanvasLayer
var panel: PanelContainer
var log_txt: RichTextLabel
var entrada: LineEdit
var historial: Array = []
var hist_i := 0
var raton_antes := Input.MOUSE_MODE_CAPTURED
var vitrina: Array = []          # galería de monstruos: {"z", "base", "fase"}
var vitrina_andar := false
var vitrina_t := 0.0
var bloqueado_antes := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	capa = CanvasLayer.new()
	capa.layer = 30
	capa.visible = false
	add_child(capa)
	panel = PanelContainer.new()
	var st := HudScript.panel_style(0.88)
	st.set_corner_radius_all(0)
	st.border_width_left = 0
	st.border_width_bottom = 2
	st.border_color = Color(1.0, 0.82, 0.36, 0.7)
	st.content_margin_left = 16
	st.content_margin_right = 16
	st.content_margin_top = 10
	st.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", st)
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.offset_bottom = 380.0
	capa.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "Cascadia Mono", "Courier New", "DejaVu Sans Mono"])
	log_txt = RichTextLabel.new()
	log_txt.bbcode_enabled = true
	log_txt.scroll_following = true
	log_txt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_txt.add_theme_font_override("normal_font", mono)
	log_txt.add_theme_font_override("bold_font", mono)
	log_txt.add_theme_font_size_override("normal_font_size", 15)
	log_txt.add_theme_font_size_override("bold_font_size", 15)
	vb.add_child(log_txt)
	entrada = LineEdit.new()
	entrada.placeholder_text = "Escribe un comando (ayuda)  ·  Esc o º para cerrar"
	entrada.add_theme_font_override("font", mono)
	entrada.add_theme_font_size_override("font_size", 17)
	var es := StyleBoxFlat.new()
	es.bg_color = Color(0, 0, 0, 0.55)
	es.border_color = Color(1.0, 0.82, 0.36, 0.9)
	es.border_width_left = 3
	es.border_width_bottom = 1
	es.content_margin_left = 12
	es.content_margin_top = 6
	es.content_margin_bottom = 6
	entrada.add_theme_stylebox_override("normal", es)
	entrada.add_theme_stylebox_override("focus", es)
	entrada.add_theme_color_override("caret_color", Color(1.0, 0.82, 0.36))
	entrada.add_theme_color_override("font_placeholder_color", Color(1, 1, 1, 0.35))
	entrada.text_submitted.connect(_ejecutar)
	vb.add_child(entrada)
	_linea("[color=#9be05a]Consola de Zombies en el Aula[/color]  ·  escribe [b]ayuda[/b] para ver los comandos")


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var tecla_consola: bool = event.physical_keycode == KEY_QUOTELEFT or event.keycode == KEY_F1 \
			or event.unicode == 186 or event.unicode == 170      # º y ª
	if tecla_consola:
		if abierta:
			cerrar()
		else:
			abrir()
		get_viewport().set_input_as_handled()
		return
	if not abierta:
		return
	if event.keycode == KEY_ESCAPE:
		cerrar()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_UP and historial.size() > 0:
		hist_i = maxi(0, hist_i - 1)
		entrada.text = historial[hist_i]
		entrada.caret_column = entrada.text.length()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_DOWN and historial.size() > 0:
		hist_i = mini(historial.size(), hist_i + 1)
		entrada.text = historial[hist_i] if hist_i < historial.size() else ""
		entrada.caret_column = entrada.text.length()
		get_viewport().set_input_as_handled()


func abrir() -> void:
	if game.ui != null and game.ui.state != 1:
		return          # solo durante la partida (no en el menú ni en pausa)
	abierta = true
	capa.visible = true
	raton_antes = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if game.player != null:
		bloqueado_antes = game.player.input_blocked
		game.player.input_blocked = true
	entrada.text = ""
	entrada.grab_focus.call_deferred()


func cerrar() -> void:
	abierta = false
	capa.visible = false
	entrada.release_focus()
	if game.player != null:
		game.player.input_blocked = bloqueado_antes or (game.camara != null and game.camara.activa)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _linea(t: String) -> void:
	log_txt.append_text(t + "\n")


func _ok(t: String) -> void:
	_linea("[color=#9be05a]✔[/color] " + t)


func _error(t: String) -> void:
	_linea("[color=#ff6a55]✖ " + t + "[/color]")


func _ejecutar(texto: String) -> void:
	entrada.text = ""
	texto = texto.strip_edges()
	if texto == "":
		return
	historial.append(texto)
	hist_i = historial.size()
	_linea("[color=#8a8f9a]> " + texto + "[/color]")
	var p := texto.to_lower().split(" ", false)
	var cmd: String = p[0]
	var arg: String = p[1] if p.size() > 1 else ""
	var pl = game.player
	match cmd:
		"ayuda", "help", "?":
			_linea(AYUDA)
		"limpiar", "clear", "cls":
			log_txt.clear()
		"mapa", "map":
			var m := arg.replace("á", "a")
			if not MAPAS.has(m):
				_error("Mapas: cesur, mojacar, indalo")
				return
			if Net.online and not Net.is_host():
				_error("Solo el anfitrión puede cambiar de mapa")
				return
			var volar: bool = p.has("espectador") or p.has("libre") or (game.camara != null and game.camara.activa)
			if volar and not Net.online:
				CamaraScript.al_cargar = true
			_ok("Cargando %s..." % m)
			game.save_carry()
			Net.go_to_map(m, Net.bucle)
		"espectador", "libre", "volar", "spectator":
			if Net.online:
				_error("El modo espectador solo funciona en partidas de un jugador")
				return
			cerrar()
			game.camara.activar()
			if not game.camara.activa:
				_error("No se puede ahora (¿estás caído o en un menú?)")
		"normal", "jugar":
			if is_instance_valid(sala):
				_quitar_galeria()
				_ok("Fuera de la galería: vuelves a donde estabas")
			elif game.camara != null and game.camara.activa:
				cerrar()
				game.camara.desactivar(true)
			else:
				_ok("Ya estás en modo normal")
		"dios", "god":
			pl.dios = not pl.dios
			_ok("Modo dios " + ("activado: no te hacen daño" if pl.dios else "desactivado"))
		"puntos", "points":
			var n := int(arg) if arg.is_valid_int() else 5000
			game.points += n
			_ok("+%d puntos (tienes %d)" % [n, game.points])
		"oleada", "wave":
			if not Net.is_host():
				_error("Solo el anfitrión")
				return
			var w: int = maxi(1, int(arg)) if arg.is_valid_int() else int(game.wave) + 1
			_matar()
			game.wave = w - 1
			game.wave_active = false
			game.wave_timer = 0.5
			_ok("Saltando a la oleada %d" % w)
		"enemigo", "spawn":
			if not Net.is_host():
				_error("Solo el anfitrión")
				return
			if not ENEMIGOS.has(arg):
				_error("Enemigos: " + ", ".join(ENEMIGOS))
				return
			var vida := float(p[2]) if p.size() > 2 and p[2].is_valid_float() else _vida_de(arg)
			var cam: Camera3D = get_viewport().get_camera_3d()
			var delante: Vector3 = cam.global_position - cam.global_transform.basis.z * 5.0
			game._add_enemy(arg, vida, Vector3(delante.x, 0.0, delante.z))
			_ok("%s con %d de vida" % [arg, int(vida)])
		"monstruos", "monstruo", "bichos", "galeria", "galería":
			_galeria(arg)
		"perro", "dog":
			if game.perro == null:
				_error("Aquí no hay perro (en todos contra todos no viene)")
				return
			game.perro.visible = not game.perro.visible
			game.perro.process_mode = Node.PROCESS_MODE_INHERIT if game.perro.visible else Node.PROCESS_MODE_DISABLED
			game.perro.item["done"] = true
			if game.perro.visible:
				game.perro.global_position = game.player.global_position + game.player.global_transform.basis.z * 1.2
			_ok("Mac " + ("está contigo" if game.perro.visible else "se ha ido a dormir"))
		"matar", "kill":
			var n2 := _matar()
			_ok("%d enemigos eliminados" % n2)
		"arma", "weapon":
			if not W.DATA.has(arg):
				_error("Armas: " + ", ".join(W.DATA.keys()))
				return
			if pl.has_weapon(arg):
				pl.refill_ammo(arg)
			else:
				pl.give_weapon(arg)
			_ok("Tienes: " + W.DATA[arg]["name"])
		"municion", "munición", "ammo":
			for s in pl.slots:
				if s != null:
					pl.refill_ammo(s["id"])
			pl.add_jan(4)
			_ok("Munición llena")
		"bebida", "perk":
			var ids: Array = BebidasScript.DATOS.keys() if arg == "todas" else [arg]
			for id in ids:
				if not BebidasScript.DATOS.has(id):
					_error("Bebidas: " + ", ".join(BebidasScript.DATOS.keys()) + ", todas")
					return
				pl.give_perk(id)
			if pl.vista != null and ids.size() == 1:
				var bd: Dictionary = BebidasScript.DATOS[ids[0]]
				pl.vista.beber(bd["color"], bd["letra"])
			_ok("Bebidas: " + ", ".join(pl.perks))
		"curar", "heal":
			pl.hp = pl.max_hp
			_ok("Vida llena (%d)" % int(pl.max_hp))
		"pruebas":
			var mi = game.mission
			if mi == null or not ("found" in mi):
				_error("Aquí no hay pruebas (solo en Mojácar y el Pueblo Indalo)")
				return
			for id in mi.found:
				if not mi.found[id]:
					mi._send_inv("pista", id)
			_ok("Pruebas superadas: ahora sale la puerta del aula")
		"prueba":
			var mi2 = game.mission
			if mi2 == null or not ("found" in mi2):
				_error("Aquí no hay pruebas (solo en Mojácar y el Pueblo Indalo)")
				return
			var lista: Array = game.mapa.pistas
			var k := int(arg) - 1 if arg.is_valid_int() else 0
			if k < 0 or k >= lista.size():
				_error("Hay %d pruebas" % lista.size())
				return
			var pos: Vector3 = lista[k][3]
			if game.camara.activa:
				game.camara._ir(pos + Vector3(0, 1.7, 3.0), 0.0, 0.0)
			else:
				pl.global_position = pos + Vector3(0, 0.05, 1.5)
			_ok("%d. %s (prueba de %s)" % [k + 1, lista[k][1], mi2.tipo.get(lista[k][0], "?")])
		"hackeo", "jesus", "jesús":
			if game.hacking:
				_error("Jesús ya te está hackeando")
				return
			cerrar()
			game.add_child(load("res://scripts/interfaz/hackeo.gd").new())
		"cerdo", "jorge":
			var mi3 = game.mission
			if mi3 == null or not ("modo_cerdo" in mi3) or not mi3.modo_cerdo:
				_error("Jorge está en Mojácar (mapa mojacar)")
				return
			if arg == "ir":
				var cp: Vector3 = mi3._cerdo_frente()
				if game.camara.activa:
					game.camara._ir(cp + Vector3(0, 1.7, 0) + mi3.cerdo.global_transform.basis.z * 3.0, 0.0, 0.0)
				else:
					pl.global_position = cp + mi3.cerdo.global_transform.basis.z * 2.0 + Vector3(0, 0.05, 0)
					var hacia: Vector3 = mi3.cerdo.global_transform.basis.z
					pl.rotation.y = atan2(hacia.x, hacia.z)            # mirándolo
				_ok("Delante de Jorge")
				return
			mi3.cerdo_debug(arg == "reventar")
			_ok("Jorge: %d / %d" % [mi3.comido + (mi3.COMIDA_TOTAL - mi3.comido if arg == "reventar" else 1), mi3.COMIDA_TOTAL])
		"padel", "pádel":
			if game.padel == null:
				_error("La pista de pádel está en el patio de CESUR")
				return
			if game.camara.activa:
				game.camara.desactivar()
			cerrar()
			game.padel.empezar()
		"reiniciar", "restart":
			if Net.online and not Net.is_host():
				_error("Solo el anfitrión")
				return
			Net.go_to_map(Net.mapa, Net.bucle)
		_:
			_error("No conozco «%s». Escribe ayuda" % cmd)


# ---------------- Galería de monstruos ----------------
# Jugando solo se monta una sala aparte (bajo el mapa, a oscuras y con focos) y
# entras en la cámara libre para verlos de cerca. En red salen delante de ti.
# [tipo, nombre, descripción, altura del cartel si el enemigo no la dice]
const GALERIA := [
	["ninja", "NINJA", "Camuflaje, gorra y pistola", 2.25],
	["isabella", "ISABELLA", "«¡Ponle bozal a tu perro!» · bolsazos", 2.1],
	["victor", "VÍCTOR", "Te roba y sale por patas", 2.2],
	["zombie", "ZOMBI VOMITÓN", "Te persigue y te vomita desde lejos", 2.75],
	["bu", "MAJIN BU", "Minijefe · vomita sushi y aplasta", 3.4],
	["bu", "SUPER BUU", "Se pincha Ozempic · +70 % de daño", 3.4],
	["ian", "IAN", "Minijefe tanque · mucha vida", 2.6],
	["boss", "EL REPARTIDOR", "Jefe en patinete · embiste", 2.6],
]
const SALA := Vector3(0.0, -500.0, 0.0)     # muy por debajo de cualquier mapa
const SALA_R := 9.5                          # radio del abanico de monstruos
const SALA_ARCO := 0.78                      # medio abanico, en radianes

var sala: Node3D

func _galeria(arg: String) -> void:
	if arg in ["quitar", "fuera", "borrar", "salir", "no"]:
		_quitar_galeria()
		_ok("Galería quitada")
		return
	if arg in ["andar", "mover", "caminar"] and not vitrina.is_empty():
		vitrina_andar = not vitrina_andar
		if not vitrina_andar:
			for v in vitrina:
				if is_instance_valid(v["z"]):
					v["z"].global_position = v["base"]
					_mirar(v["z"], v["mira"])
		_ok("Los monstruos " + ("dan vueltas andando" if vitrina_andar else "se quedan quietos"))
		return
	_quitar_galeria()
	# dónde se pone el que mira y hacia dónde
	var ojo: Vector3
	var f: Vector3
	var en_sala := not Net.online and game.camara != null
	if en_sala:
		ojo = SALA
		f = Vector3.FORWARD
		_montar_sala()
	else:
		var cam: Camera3D = get_viewport().get_camera_3d()
		ojo = Vector3(cam.global_position.x, 0.0, cam.global_position.z)
		f = -cam.global_transform.basis.z
		f.y = 0.0
		f = f.normalized() if f.length() > 0.01 else Vector3.FORWARD
	var r := f.cross(Vector3.UP)
	var n := GALERIA.size()
	var fuente_n := HudScript.fuente(HudScript.F_NUM)
	var fuente_t := HudScript.fuente(HudScript.F_UI)
	for i in n:
		var g: Array = GALERIA[i]
		var a := lerpf(-SALA_ARCO, SALA_ARCO, float(i) / float(n - 1))
		var pos: Vector3 = ojo + (f * cos(a) + r * sin(a)) * SALA_R
		pos.y = ojo.y
		var nombre := "VITRINA_%d_%d" % [i, randi() % 100000]
		game._make_enemy(g[0], nombre, 1e9, pos, -1.0, true)
		var z = game.get_node_or_null(NodePath(nombre))
		if z == null:
			continue
		# fuera del grupo de enemigos: no cuentan para la oleada ni te atacan
		z.remove_from_group("zombies")
		z.add_to_group("vitrina")
		_mirar(z, ojo)
		var alto: float = g[3]
		if z.has_method("altura_cabeza"):
			alto = z.altura_cabeza() + 0.55
		_cartel(z, g[1], g[2], alto, fuente_n, fuente_t)
		_peana(pos, ojo, en_sala)
		vitrina.append({"z": z, "base": pos, "mira": ojo, "fase": float(i) * 0.7})
		if g[1] == "SUPER BUU":
			# este Majin Bu se pincha el Ozempic delante de ti
			get_tree().create_timer(2.0).timeout.connect(func():
				if is_instance_valid(z):
					z.start_transform())
	cerrar()
	if en_sala:
		game.camara.activar()
		if game.camara.activa:
			game.camara._ir(SALA + Vector3(0.0, 2.2, 0.8), 0.0, -0.1)
	_ok("%d monstruos" % vitrina.size())
	game.hud.small_lbl.text = "GALERÍA DE MONSTRUOS  ·  º → monstruos andar / monstruos quitar"
	get_tree().create_timer(6.0).timeout.connect(func():
		if game.hud.small_lbl.text.begins_with("GALERÍA"):
			game.hud.small_lbl.text = "")


# Suelo brillante, pared curva al fondo, focos y el título
func _montar_sala() -> void:
	sala = Node3D.new()
	sala.name = "SalaMonstruos"
	game.add_child(sala)
	sala.global_position = SALA
	var suelo := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(46, 46)
	suelo.mesh = pm
	var ms := StandardMaterial3D.new()
	ms.albedo_color = Color(0.07, 0.055, 0.06)
	ms.roughness = 0.55
	ms.metallic = 0.0
	suelo.material_override = ms
	sala.add_child(suelo)
	var fondo := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 15.0
	cm.bottom_radius = 15.0
	cm.height = 16.0
	cm.radial_segments = 48
	cm.cap_top = true
	cm.cap_bottom = false
	fondo.mesh = cm
	var mf := StandardMaterial3D.new()
	mf.albedo_color = Color(0.11, 0.025, 0.035)
	mf.roughness = 0.9
	mf.cull_mode = BaseMaterial3D.CULL_FRONT       # se ve por dentro
	fondo.material_override = mf
	fondo.position = Vector3(0, 7.9, 0)
	fondo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sala.add_child(fondo)
	# luz suave general y un contraluz rojo
	var amb := OmniLight3D.new()
	amb.position = Vector3(0, 5, 3)
	amb.omni_range = 26.0
	amb.light_energy = 1.4
	amb.light_color = Color(1.0, 0.85, 0.85)
	sala.add_child(amb)
	var rojo := OmniLight3D.new()
	rojo.position = Vector3(0, 3, -13)
	rojo.omni_range = 16.0
	rojo.light_energy = 2.5
	rojo.light_color = Color(1.0, 0.1, 0.08)
	sala.add_child(rojo)
	var titulo := Label3D.new()
	titulo.text = "GALERÍA DE MONSTRUOS"
	var ft: Font = load("res://fuentes/Creepster-Regular.ttf") if ResourceLoader.exists("res://fuentes/Creepster-Regular.ttf") else HudScript.fuente(HudScript.F_NUM)
	titulo.font = ft
	titulo.font_size = 160
	titulo.outline_size = 24
	titulo.modulate = Color(0.95, 0.1, 0.08)
	titulo.outline_modulate = Color(0.05, 0.0, 0.0)
	titulo.pixel_size = 0.012
	titulo.position = Vector3(0, 6.6, -12.5)
	sala.add_child(titulo)


func _mirar(z: Node3D, a: Vector3) -> void:
	var d := a - z.global_position
	z.rotation.y = atan2(-d.x, -d.z)


func _cartel(z: Node3D, titulo: String, desc: String, alto: float, fn: Font, ft: Font) -> void:
	var l := Label3D.new()
	l.text = titulo
	l.font = fn
	l.font_size = 64
	l.outline_size = 12
	l.modulate = Color(1.0, 0.84, 0.4)
	l.outline_modulate = Color(0.08, 0.0, 0.0)
	l.pixel_size = 0.005
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 10
	l.position = Vector3(0, alto + 0.2, 0)
	z.add_child(l)
	var d := Label3D.new()
	d.text = desc
	d.font = ft
	d.font_size = 34
	d.outline_size = 8
	d.modulate = Color(0.95, 0.93, 0.9)
	d.outline_modulate = Color(0, 0, 0)
	d.pixel_size = 0.005
	d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	d.no_depth_test = true
	d.render_priority = 10
	d.position = Vector3(0, alto, 0)
	z.add_child(d)


# Círculo rojo brillante en el suelo y un foco encima, como en un museo
func _peana(pos: Vector3, ojo: Vector3, en_sala: bool) -> void:
	var padre: Node3D = sala if en_sala else game
	var anillo := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.95
	tm.outer_radius = 1.05
	tm.rings = 48
	anillo.mesh = tm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.15, 0.1)
	anillo.material_override = m
	anillo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	padre.add_child(anillo)
	anillo.global_position = pos + Vector3(0, 0.02, 0)
	anillo.scale = Vector3(1, 0.12, 1)
	anillo.add_to_group("vitrina_extra")
	var foco := SpotLight3D.new()
	padre.add_child(foco)
	var hacia := (ojo - pos)
	hacia.y = 0.0
	hacia = hacia.normalized()
	foco.global_position = pos + hacia * 2.6 + Vector3(0, 6.5, 0)
	foco.look_at(pos + Vector3(0, 1.2, 0), Vector3.UP)
	foco.spot_angle = 26.0
	foco.spot_range = 12.0
	foco.spot_attenuation = 0.6
	foco.light_energy = 6.0 if en_sala else 3.0
	foco.light_color = Color(1.0, 0.95, 0.88)
	foco.shadow_enabled = en_sala
	foco.add_to_group("vitrina_extra")


func _quitar_galeria() -> void:
	for v in vitrina:
		if is_instance_valid(v["z"]):
			v["z"].queue_free()
	vitrina.clear()
	vitrina_andar = false
	for e in get_tree().get_nodes_in_group("vitrina_extra"):
		e.queue_free()
	if is_instance_valid(sala):
		sala.queue_free()
		sala = null
		# sales de la sala: vuelves a donde estabas
		if game.camara != null and game.camara.activa:
			game.camara.desactivar(false)


func _process(delta: float) -> void:
	if not vitrina_andar or vitrina.is_empty() or get_tree().paused:
		return
	vitrina_t += delta
	for v in vitrina:
		var z = v["z"]
		if not is_instance_valid(z) or z.dying:
			continue
		var a: float = vitrina_t * 0.9 + v["fase"]
		var p: Vector3 = v["base"] + Vector3(cos(a), 0.0, sin(a)) * 0.9
		var tang := Vector3(-sin(a), 0.0, cos(a))
		z.global_position = p
		z.rotation.y = atan2(-tang.x, -tang.z)


func _matar() -> int:
	var n := 0
	for z in get_tree().get_nodes_in_group("zombies"):
		if not z.dying:
			game.damage_enemy(z, 1e9, Vector3.ZERO)
			n += 1
	return n


func _vida_de(kind: String) -> float:
	match kind:
		"bu":
			return 120.0 + maxi(game.wave, 5) * 12.0
		"boss":
			return 400.0
		"ian":
			return 70.0 + game.wave * 10.0
		"isabella":
			return 8.0
		"victor":
			return 24.0
	return 60.0 + game.wave * 8.0

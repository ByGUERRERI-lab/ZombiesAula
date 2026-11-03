extends Node
# Soporte de mando (Xbox, PlayStation, Switch Pro o genérico). Va como autoload "Mando".
# En vez de tocar todo el juego, traduce el mando a las teclas y al ratón que el
# juego ya entiende (Input.parse_input_event), así funciona en todos los sitios:
# jugador, misiones, pruebas de habilidad, pádel, cámara libre...
#
#   JUGANDO                                   EN MENÚS (tienda, casino, pausa...)
#   stick izq.   moverse (WASD)               stick izq. / cruceta   moverse por los botones
#   stick der.   mirar (ratón)                A                      aceptar
#   L3           correr (Shift)               B / Start              volver / salir
#   RT           disparar (clic)              stick der.             girar al personaje (personalizar)
#   LT           apuntar (clic derecho)
#   A            usar / comprar / reanimar (E)
#   X            recargar (R)
#   Y            cambiar de arma (1 <-> 2)
#   B            katana (3)
#   LB           granada Jan (4) · mantén RT y suelta para lanzar
#   R3           linterna (F)
#   Select       cámara 1ª / 3ª persona (V) · salir del pádel
#   cruceta      flechas (pruebas de reflejos de Mojácar)
#   Start        pausa (Esc)
#   Teclado de código: cruceta arriba/abajo elige el número, A lo mete, B borra

const ZONA := 0.2               # zona muerta de los sticks
const UMBRAL_MOVER := 0.38      # cuánto hay que inclinar el stick para andar
const MIRAR_X := 1300.0         # "píxeles de ratón" por segundo con el stick a tope
const MIRAR_Y := 800.0
const GATILLO := 0.4

var teclas := {}                # teclas que el mando tiene pulsadas ahora mismo
var pulsos := {}                # teclas de un solo toque -> segundos que les quedan pulsadas
var clic := false
var clic_der := false
var correr := false
var prev := {}                  # botones del mando del fotograma anterior
var ahora := {}                 # botones del mando en este fotograma
var digito := 0                 # teclado de código
var activo := false             # se ha usado el mando hace poco (para los menús)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# el stick izquierdo también mueve por los menús (por defecto solo la cruceta)
	_eje_ui("ui_up", JOY_AXIS_LEFT_Y, -1.0)
	_eje_ui("ui_down", JOY_AXIS_LEFT_Y, 1.0)
	_eje_ui("ui_left", JOY_AXIS_LEFT_X, -1.0)
	_eje_ui("ui_right", JOY_AXIS_LEFT_X, 1.0)
	Input.joy_connection_changed.connect(_conexion)


static func conectado() -> bool:
	return not Input.get_connected_joypads().is_empty()


func _eje_ui(accion: String, eje: int, signo: float) -> void:
	if not InputMap.has_action(accion):
		return
	var e := InputEventJoypadMotion.new()
	e.device = -1
	e.axis = eje
	e.axis_value = signo
	InputMap.action_add_event(accion, e)


func _conexion(dev: int, si: bool) -> void:
	var game = get_tree().get_first_node_in_group("game")
	if game != null and game.has_method("toast_small"):
		game.toast_small(("Mando conectado: " + Input.get_joy_name(dev)) if si else "Mando desconectado")
	if not si:
		_soltar_todo()


# Jugando (ratón capturado) o en un menú
func _en_juego() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


# ---------------- lectura del mando ----------------
func _pads() -> Array:
	return Input.get_connected_joypads()


func _boton(b: int) -> bool:
	for d in _pads():
		if Input.is_joy_button_pressed(d, b):
			return true
	return false


func _eje(a: int) -> float:
	var mejor := 0.0
	for d in _pads():
		var v := Input.get_joy_axis(d, a)
		if absf(v) > absf(mejor):
			mejor = v
	return 0.0 if absf(mejor) < ZONA else (mejor - signf(mejor) * ZONA) / (1.0 - ZONA)


# true solo el fotograma en que se pulsa
func _pulsado(b: int) -> bool:
	return ahora.get(b, false) and not prev.get(b, false)


# ---------------- envío de teclas / ratón ----------------
func _tecla(k: Key, on: bool, uni := 0) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = on
	e.unicode = uni if on else 0
	Input.parse_input_event(e)


func _clic(on: bool) -> void:
	if clic == on:
		return
	clic = on
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = on
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if on else 0
	e.position = get_viewport().get_visible_rect().size / 2.0
	e.global_position = e.position
	Input.parse_input_event(e)


func _apuntar(on: bool) -> void:
	if clic_der == on:
		return
	clic_der = on
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_RIGHT
	e.pressed = on
	e.button_mask = MOUSE_BUTTON_MASK_RIGHT if on else 0
	e.position = get_viewport().get_visible_rect().size / 2.0
	e.global_position = e.position
	Input.parse_input_event(e)


func _mirar(v: Vector2) -> void:
	if v == Vector2.ZERO:
		return
	var e := InputEventMouseMotion.new()
	e.relative = v
	e.screen_relative = v
	e.position = get_viewport().get_visible_rect().size / 2.0
	e.global_position = e.position
	Input.parse_input_event(e)


func _soltar_todo() -> void:
	for k in teclas.keys():
		_tecla(k, false)
	teclas.clear()
	pulsos.clear()
	_clic(false)
	_apuntar(false)
	correr = false


# Deja pulsadas exactamente las teclas de "quiero" (y suelta las demás)
func _sincronizar(quiero: Dictionary, delta: float) -> void:
	for k in pulsos.keys():
		quiero[k] = true
		pulsos[k] -= delta
		if pulsos[k] <= 0.0:
			pulsos.erase(k)
	for k in teclas.keys():
		if not quiero.has(k):
			_tecla(k, false)
			teclas.erase(k)
	for k in quiero.keys():
		if not teclas.has(k):
			_tecla(k, true)
			teclas[k] = true


func _toque(k: Key) -> void:
	pulsos[k] = 0.07       # lo bastante para que lo vean un par de pasos de física


# ---------------- cada fotograma ----------------
func _process(delta: float) -> void:
	if _pads().is_empty():
		if not teclas.is_empty() or clic:
			_soltar_todo()
		return
	prev = ahora
	ahora = {}
	for b in JOY_BUTTON_SDL_MAX:
		ahora[b] = _boton(b)
	var game = get_tree().get_first_node_in_group("game")
	var quiero := {}
	var con = game.get("consola") if game != null else null
	if con != null and con.abierta:
		_sincronizar(quiero, delta)        # escribiendo en la consola: el mando no hace nada
		_clic(false)
		return
	if game != null and game.get("code_open"):
		_codigo(game)
		_sincronizar(quiero, delta)
		return
	if _en_juego():
		_jugando(game, quiero, delta)
	else:
		_menus(game, delta)
		_clic(false)
		_apuntar(false)
		correr = false
	_sincronizar(quiero, delta)


func _jugando(game, quiero: Dictionary, delta: float) -> void:
	# moverse
	var lx := _eje(JOY_AXIS_LEFT_X)
	var ly := _eje(JOY_AXIS_LEFT_Y)
	if ly < -UMBRAL_MOVER: quiero[KEY_W] = true
	if ly > UMBRAL_MOVER: quiero[KEY_S] = true
	if lx < -UMBRAL_MOVER: quiero[KEY_A] = true
	if lx > UMBRAL_MOVER: quiero[KEY_D] = true
	# correr: se pulsa L3 y sigue corriendo mientras vayas hacia delante
	if _pulsado(JOY_BUTTON_LEFT_STICK):
		correr = not correr
	if ly > -0.3:
		correr = false
	if correr:
		quiero[KEY_SHIFT] = true
	# mirar (curva cuadrática: suave en el centro, rápido al fondo)
	var rx := _eje(JOY_AXIS_RIGHT_X)
	var ry := _eje(JOY_AXIS_RIGHT_Y)
	_mirar(Vector2(rx * absf(rx) * MIRAR_X, ry * absf(ry) * MIRAR_Y) * delta)
	# disparar
	_clic(_eje(JOY_AXIS_TRIGGER_RIGHT) > GATILLO)
	_apuntar(_eje(JOY_AXIS_TRIGGER_LEFT) > GATILLO)
	# botones que se mantienen
	if _boton(JOY_BUTTON_A): quiero[KEY_E] = true
	if _boton(JOY_BUTTON_X): quiero[KEY_R] = true
	if _boton(JOY_BUTTON_DPAD_UP): quiero[KEY_UP] = true
	if _boton(JOY_BUTTON_DPAD_DOWN): quiero[KEY_DOWN] = true
	if _boton(JOY_BUTTON_DPAD_LEFT): quiero[KEY_LEFT] = true
	if _boton(JOY_BUTTON_DPAD_RIGHT): quiero[KEY_RIGHT] = true
	if _boton(JOY_BUTTON_BACK): quiero[KEY_BACKSPACE] = true
	# toques
	if _pulsado(JOY_BUTTON_B): _toque(KEY_3)
	if _pulsado(JOY_BUTTON_LEFT_SHOULDER): _toque(KEY_4)
	if _pulsado(JOY_BUTTON_RIGHT_STICK): _toque(KEY_F)
	if _pulsado(JOY_BUTTON_BACK): _toque(KEY_V)
	if _pulsado(JOY_BUTTON_START): _toque(KEY_ESCAPE)
	if _pulsado(JOY_BUTTON_Y):
		var p = game.player if game != null else null
		var c: int = p.cur if p != null else 0
		_toque(KEY_2 if c != 1 else KEY_1)


func _menus(game, delta: float) -> void:
	if _pulsado(JOY_BUTTON_B) or _pulsado(JOY_BUTTON_START):
		_toque(KEY_ESCAPE)
	# si nada tiene el foco, se lo damos al primer botón que se vea
	var tocado := false
	for b in [JOY_BUTTON_A, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]:
		if _boton(b):
			tocado = true
	if absf(_eje(JOY_AXIS_LEFT_X)) > 0.5 or absf(_eje(JOY_AXIS_LEFT_Y)) > 0.5:
		tocado = true
	# jugando pero sin el ratón capturado (p. ej. tras cambiar de ventana): A vuelve al juego
	if game != null and game.get("ui") != null and game.ui.state == 1 and _pulsado(JOY_BUTTON_A) \
			and _primer_boton() == null:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if tocado:
		activo = true
		var f := get_viewport().gui_get_focus_owner()
		if f == null or not f.is_visible_in_tree():
			var b := _primer_boton()
			if b != null:
				b.grab_focus()
	# personalizar: girar al personaje con el stick derecho
	if game != null and game.get("ui") != null:
		var ui = game.ui
		if ui.custom_root != null and ui.custom_root.visible:
			ui.custom_rot += _eje(JOY_AXIS_RIGHT_X) * 3.0 * delta


func _primer_boton() -> Control:
	var mejor: Control = null
	for b: Control in get_tree().root.find_children("*", "BaseButton", true, false):
		if not b.is_visible_in_tree() or b.focus_mode == Control.FOCUS_NONE or b.disabled:
			continue
		if mejor == null or b.global_position.y < mejor.global_position.y - 1.0 \
				or (absf(b.global_position.y - mejor.global_position.y) <= 1.0 and b.global_position.x < mejor.global_position.x):
			mejor = b
	return mejor


# Teclado de la puerta con código: elegir número con la cruceta
func _codigo(game) -> void:
	var cambia := 0
	if _pulsado(JOY_BUTTON_DPAD_UP): cambia = 1
	if _pulsado(JOY_BUTTON_DPAD_DOWN): cambia = -1
	if cambia != 0:
		digito = posmod(digito + cambia, 10)
		game._code_refresh("Mando: número %d   ·   ↑↓ cambiar   ·   A meter   ·   B borrar" % digito, Color(1.0, 0.85, 0.4))
	if _pulsado(JOY_BUTTON_A):
		var k: int = KEY_0 + digito
		_tecla(k as Key, true, 48 + digito)
		_tecla(k as Key, false)
	if _pulsado(JOY_BUTTON_B):
		_tecla(KEY_BACKSPACE, true)
		_tecla(KEY_BACKSPACE, false)
	if _pulsado(JOY_BUTTON_START):
		_tecla(KEY_ESCAPE, true)
		_tecla(KEY_ESCAPE, false)

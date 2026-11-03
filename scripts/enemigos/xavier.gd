extends Node3D
# Xavier: no hace daño, pero te persigue por todo el instituto con el móvil.
# Se pone a unos metros y va alternando: hace fotos con flash (te deslumbra un
# poco) y te graba en vídeo (sale "REC" en pantalla). Lo controla el anfitrión
# y los demás PCs solo copian su posición.

const U = preload("res://scripts/nucleo/util.gd")
const Ch = preload("res://scripts/jugador/character.gd")

const SPEED := 4.3          # más lento que tú (6): si corres, le dejas atrás
const NEAR := 2.6           # más cerca de esto, se echa para atrás
const FAR := 4.5            # más lejos de esto, va a por ti
const MODE_TIME := 8.0      # segundos haciendo fotos / grabando

var player                  # a quién sigue (lo pone main.gd)
var game
var radius := 0.5
var recording := false
var mode_t := 4.0
var photo_cd := 2.0
var photos := 0
var walk_t := 0.0
var send_t := 0.0
var net_pos := Vector3.ZERO
var net_rot := 0.0
var model: Node3D
var arm: Node3D
var lens: Node3D
var rec: Node3D
var flash_l: OmniLight3D
var shutter: AudioStreamPlayer3D
var rec_lbl: Label
var flash_rect: ColorRect


func _ready() -> void:
	add_to_group("npcs")
	game = get_tree().get_first_node_in_group("game")
	var parts: Dictionary = Ch.build_xavier(self)
	model = parts["model"]
	arm = parts["arm"]
	lens = parts["lens"]
	rec = parts["rec"]
	arm.rotation.x = deg_to_rad(-60.0)       # móvil a la altura del pecho
	flash_l = OmniLight3D.new()
	flash_l.light_color = Color(1.0, 0.98, 0.92)
	flash_l.light_energy = 0.0
	flash_l.omni_range = 9.0
	lens.add_child(flash_l)
	flash_l.position = Vector3(0, -0.03, 0)
	shutter = AudioStreamPlayer3D.new()
	shutter.stream = U.make_shutter()
	shutter.unit_size = 6.0
	shutter.position.y = 1.6
	add_child(shutter)
	var tag := Label3D.new()
	tag.text = "Xavier"
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.font_size = 36
	tag.pixel_size = 0.005
	tag.outline_size = 8
	tag.modulate = Color(0.75, 0.9, 1.0)
	tag.position.y = 2.25
	add_child(tag)

	# "REC" en la pantalla cuando te está grabando, y el fogonazo de las fotos
	var layer := CanvasLayer.new()
	layer.layer = 4
	add_child(layer)
	flash_rect = ColorRect.new()
	flash_rect.color = Color(1, 1, 1, 0)
	flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(flash_rect)
	rec_lbl = Label.new()
	rec_lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
	rec_lbl.offset_left = -250.0
	rec_lbl.offset_right = 250.0
	rec_lbl.offset_top = 12.0
	rec_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rec_lbl.add_theme_font_size_override("font_size", 13)
	rec_lbl.add_theme_color_override("font_color", Color(1.0, 0.3, 0.25, 0.85))
	rec_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	rec_lbl.add_theme_constant_override("shadow_outline_size", 5)
	layer.add_child(rec_lbl)
	net_pos = global_position


func _physics_process(delta: float) -> void:
	_rec_hud()
	if Net.online and not Net.is_host():
		_follow_net(delta)
		return
	if U.stunned(self):
		recording = false
		_pose(false, delta)
		_send(delta)
		return
	if player == null or not is_instance_valid(player):
		player = game.player
	var to_p: Vector3 = player.global_position - global_position
	to_p.y = 0.0
	var dist := to_p.length()
	var dir := to_p.normalized()
	var same := U.region(global_position) == U.region(player.global_position)

	# siempre mirando al jugador (para la foto); si no le ve, mira por dónde va
	var tgt: Vector3 = U.next_point(global_position, player.global_position)
	var mv: Vector3 = tgt - global_position
	mv.y = 0.0
	var face := dir if same else mv.normalized()
	rotation.y = lerp_angle(rotation.y, atan2(-face.x, -face.z), 7.0 * delta)

	var step := Vector3.ZERO
	if not same or dist > FAR:
		step = mv.normalized() * SPEED
	elif dist < NEAR:
		step = -dir * SPEED * 0.5           # da un pasito atrás para encuadrar
	global_position += step * delta
	if step.length() > 0.1:
		walk_t += delta * 6.0
		model.position.y = absf(sin(walk_t)) * 0.04
		model.rotation.z = sin(walk_t) * 0.04
	else:
		model.position.y = lerpf(model.position.y, 0.0, 8.0 * delta)
		model.rotation.z = lerpf(model.rotation.z, 0.0, 8.0 * delta)
	global_position = U.clamp_pos(global_position, radius)

	# fotos o vídeo, por turnos
	mode_t -= delta
	if mode_t <= 0.0:
		recording = not recording
		mode_t = MODE_TIME
		photo_cd = 0.8
	var shooting: bool = same and dist < 12.0 and not player.dead
	_pose(shooting, delta)
	if shooting and not recording:
		photo_cd -= delta
		if photo_cd <= 0.0:
			photo_cd = randf_range(1.6, 2.6)
			var pid: int = player.peer_id
			if Net.online:
				_net_photo.rpc(pid)
			else:
				_net_photo(pid)
	_send(delta)


# Brazo arriba con el móvil delante de la cara cuando está sacando fotos o grabando
func _pose(up: bool, delta: float) -> void:
	var want := 0.0 if up else deg_to_rad(-60.0)
	arm.rotation.x = lerpf(arm.rotation.x, want, 6.0 * delta)
	rec.visible = up and recording and fmod(Time.get_ticks_msec() / 500.0, 2.0) < 1.3


# ¡Foto! Fogonazo del flash para todos y pantallazo blanco para el fotografiado
@rpc("authority", "call_local", "reliable")
func _net_photo(target: int) -> void:
	photos += 1
	shutter.play()
	flash_l.light_energy = 14.0
	create_tween().tween_property(flash_l, "light_energy", 0.0, 0.25)
	var me: int = Net.my_id() if Net.online else 1
	if target == me and game.player != null and not game.player.dead:
		flash_rect.color.a = 0.55
		create_tween().tween_property(flash_rect, "color:a", 0.0, 0.5)
		game.toast_small("Xavier te ha hecho una foto (%d)" % photos)


# Aviso de "REC" si te está grabando a ti (cada PC lo mira por su cuenta)
func _rec_hud() -> void:
	var p = game.player
	var on: bool = recording and p != null and not U.stunned(self) \
		and global_position.distance_to(p.global_position) < 12.0 \
		and U.region(global_position) == U.region(p.global_position)
	if on:
		var blink := fmod(Time.get_ticks_msec() / 500.0, 2.0) < 1.3
		rec_lbl.text = ("●  REC" if blink else "     REC") + "  ·  Xavier te está grabando"
	else:
		rec_lbl.text = ""


# ---------------- Red ----------------
func _send(delta: float) -> void:
	if not Net.online:
		return
	send_t -= delta
	if send_t > 0.0:
		return
	send_t = 1.0 / 15.0
	var st: float = float(get_meta("stun_until", 0.0)) - Time.get_ticks_msec() / 1000.0
	_net_state.rpc(global_position, rotation.y, arm.rotation.x, recording, st)


@rpc("authority", "unreliable_ordered")
func _net_state(pos: Vector3, rot: float, arm_x: float, rec_on: bool, stun_left: float) -> void:
	net_pos = pos
	net_rot = rot
	arm.rotation.x = arm_x
	recording = rec_on
	if stun_left > 0.0 and not U.stunned(self):
		U.stun(self, stun_left)


func _follow_net(delta: float) -> void:
	U.stunned(self)          # quita el cartel de cegado cuando toca
	var moving := global_position.distance_to(net_pos) > 0.02
	global_position = global_position.lerp(net_pos, minf(1.0, 10.0 * delta))
	rotation.y = lerp_angle(rotation.y, net_rot, minf(1.0, 10.0 * delta))
	rec.visible = recording and arm.rotation.x > -0.3 and fmod(Time.get_ticks_msec() / 500.0, 2.0) < 1.3
	if moving:
		walk_t += delta * 6.0
		model.position.y = absf(sin(walk_t)) * 0.04

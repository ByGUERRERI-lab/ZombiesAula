extends Node3D
# Isabella: la "ronda de perros" del juego. Salen varias, aparecen con un rayo
# rosa, corren casi tan rápido como tú, tienen poca vida y te dan bolsazos.
# La última de la ronda suelta una Munición Máxima (lo gestiona main.gd).

const U = preload("res://scripts/nucleo/util.gd")
const Ch = preload("res://scripts/jugador/character.gd")
# Modelo realista (.glb) con piezas móviles; si no está, se usa el de formas simples
const MODELO := "res://modelos/personajes/isabella.glb"
# Voz: si pones estos audios en sonidos/ (.ogg, .mp3 o .wav) se usan ellos;
# si no, habla la voz en español del sistema (texto a voz de Godot).
const AUDIO_FRASE := "res://sonidos/isabella_bozal"
const AUDIO_RISA := "res://sonidos/isabella_risa"
const TXT_FRASE := "¡Ponle bozal a tu perro!"
const TXT_RISA := "¡Aaaa ka ka ka ka ka ka ka ka ka ka ka!"
static var _ultima_voz := -100.0   # compartido: que no hablen todas a la vez
static var _voz_tts := ""

var player
var hp := 8.0
var radius := 0.45
var speed := 5.3
var dying := false
var puppet := false        # copia de un enemigo que controla el anfitrión
var model: Node3D
var arm: Node3D
var bag: Node3D
var arm_l: Node3D           # solo en el modelo realista
var leg_l: Node3D
var leg_r: Node3D
var hit_cd := 0.0
var swing := 0.0           # > 0 mientras da el bolsazo
var t := 0.0
var voz: AudioStreamPlayer3D
var voz_cd := 0.0


func _ready() -> void:
	add_to_group("zombies")
	add_to_group("isabellas")
	if not _cargar_modelo():
		var parts: Dictionary = Ch.build_isabella(self)
		model = parts["model"]
		arm = parts["arm"]
		bag = parts["bag"]
	t = randf() * 10.0
	voz = AudioStreamPlayer3D.new()
	voz.unit_size = 7.0
	voz.max_db = 4.0
	voz.position.y = 1.5
	add_child(voz)
	voz_cd = randf_range(6.0, 11.0)
	_spawn_fx()


# Isabella realista: el .glb mira a +Z, así que va girado dentro de "model"
# (que mira a -Z como el resto de personajes). Piezas: BrazoIzq, BrazoDer,
# PiernaIzq, PiernaDer y Bolso.
func _cargar_modelo() -> bool:
	if not ResourceLoader.exists(MODELO):
		return false
	var ps = load(MODELO)
	if not (ps is PackedScene):
		return false
	model = Node3D.new()
	model.scale = Vector3.ONE * 0.96
	add_child(model)
	var inst: Node3D = ps.instantiate()
	inst.rotation.y = PI
	inst.scale = Vector3.ONE * 0.941         # 0.96 x 0.941 x 1.771 m = 1,60 m (sin sombrero)
	model.add_child(inst)
	arm = inst.find_child("BrazoDer", true, false)
	arm_l = inst.find_child("BrazoIzq", true, false)
	leg_l = inst.find_child("PiernaIzq", true, false)
	leg_r = inst.find_child("PiernaDer", true, false)
	bag = inst.find_child("Bolso", true, false)
	if arm == null or bag == null:
		model.queue_free()
		return false
	return true


# Rayo rosa y risita al aparecer (se ve en todos los PCs)
func _spawn_fx() -> void:
	var fx := Node3D.new()
	add_child(fx)
	var bolt := U.cylinder(fx, 0.12, 9.0, Vector3(0, 4.5, 0), Color(1.0, 0.45, 0.85), true)
	bolt.material_override.emission_energy_multiplier = 6.0
	bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.4, 0.85)
	l.light_energy = 12.0
	l.omni_range = 9.0
	l.position.y = 1.5
	fx.add_child(l)
	var tw := fx.create_tween().set_parallel()
	tw.tween_property(bolt, "scale", Vector3(0.1, 1.0, 0.1), 0.35)
	tw.tween_property(l, "light_energy", 0.0, 0.5)
	tw.chain().tween_callback(fx.queue_free)
	model.scale = Vector3.ONE * 0.1
	create_tween().tween_property(model, "scale", Vector3.ONE * 0.96, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if not _hablar(true):
		var snd := AudioStreamPlayer3D.new()
		snd.stream = U.make_laugh(2.1)
		snd.unit_size = 6.0
		snd.position.y = 1.6
		add_child(snd)
		snd.play()


# ---------------- voz ----------------
static func _buscar_audio(base: String) -> AudioStream:
	for ext in [".ogg", ".mp3", ".wav"]:
		if ResourceLoader.exists(base + ext):
			return load(base + ext)
	return null


# Elige la voz del sistema en español (mejor colombiana o latina) para el texto a voz
static func _elegir_voz_tts() -> String:
	if _voz_tts != "":
		return _voz_tts
	var mejor := ""
	var nota := -1
	for v in DisplayServer.tts_get_voices():
		var lang := str(v.get("language", "")).to_lower().replace("-", "_")
		if not lang.begins_with("es"):
			continue
		var n := 1
		if lang.begins_with("es_co"):
			n = 5
		elif lang.begins_with("es_419") or lang.begins_with("es_us") or lang.begins_with("es_mx"):
			n = 3
		if str(v.get("name", "")).to_lower().contains("female") or str(v.get("name", "")).to_lower().contains("sabina") or str(v.get("name", "")).to_lower().contains("helena") or str(v.get("name", "")).to_lower().contains("salom"):
			n += 1
		if n > nota:
			nota = n
			mejor = str(v.get("id", ""))
	_voz_tts = mejor
	return mejor


# Dice la frase ("¡Ponle bozal a tu perro!") o se ríe. Devuelve false si no ha sonado nada.
func _hablar(frase: bool) -> bool:
	var ahora := Time.get_ticks_msec() / 1000.0
	if ahora - _ultima_voz < 2.5:
		return false
	var st := _buscar_audio(AUDIO_FRASE if frase else AUDIO_RISA)
	if st != null:
		voz.stream = st
		voz.pitch_scale = randf_range(0.97, 1.05)
		voz.play()
		_ultima_voz = ahora
		return true
	if not ProjectSettings.get_setting("audio/general/text_to_speech", false):
		return false
	var id := _elegir_voz_tts()
	if id == "" or DisplayServer.tts_is_speaking():
		return false
	var cerca := 1.0
	if player != null:
		cerca = clampf(1.0 - global_position.distance_to(player.global_position) / 25.0, 0.15, 1.0)
	if frase:
		DisplayServer.tts_speak(TXT_FRASE, id, int(100 * cerca), 1.35, 1.15)
	else:
		DisplayServer.tts_speak(TXT_RISA, id, int(100 * cerca), 1.6, 1.9)
	_ultima_voz = ahora
	return true


func _physics_process(delta: float) -> void:
	t += delta
	_anim(delta)
	if U.stunned(self) or puppet:
		return    # cegada por Jan, o copia en otro PC (la mueve el anfitrión)
	if dying or player == null or player.dead:
		return
	hit_cd -= delta
	voz_cd -= delta
	if voz_cd <= 0.0:
		voz_cd = randf_range(7.0, 13.0)
		_hablar(randf() < 0.6)
	var to_p: Vector3 = player.global_position - global_position
	to_p.y = 0.0
	var dist := to_p.length()
	var tgt: Vector3 = U.next_point(global_position, player.global_position)
	var mv: Vector3 = tgt - global_position
	mv.y = 0.0
	var dir := mv.normalized()
	rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 9.0 * delta)
	if dist > radius + 0.6:
		# corre haciendo un pequeño zigzag, como los perros
		var side := Vector3(-dir.z, 0.0, dir.x) * sin(t * 3.0) * 0.35
		global_position += (dir + side).normalized() * speed * delta
	elif hit_cd <= 0.0:
		hit_cd = 0.9
		swing = 0.35
		player.hurt(14.0)
		player.knock = to_p.normalized() * 5.0
		if randf() < 0.55:
			_hablar(false)    # risa después del bolsazo

	# separación para que no se amontonen
	for o in get_tree().get_nodes_in_group("isabellas"):
		if o != self:
			var off: Vector3 = global_position - o.global_position
			off.y = 0.0
			var l := off.length()
			if l < 0.9 and l > 0.01:
				global_position += off / l * (0.9 - l) * 3.0 * delta
	global_position = U.clamp_pos(global_position, radius)


# Carrera inclinada hacia delante y bolsazo con el brazo derecho
func _anim(delta: float) -> void:
	if dying:
		return
	model.rotation.x = -0.18
	model.position.y = absf(sin(t * 11.0)) * 0.07
	model.rotation.z = sin(t * 11.0) * 0.05
	var w := t * 11.0
	# modelo realista: piernas y brazo izquierdo en carrera (en su marco, delante es -X de giro)
	if leg_l != null:
		leg_l.rotation.x = sin(w) * 0.65
		leg_r.rotation.x = -sin(w) * 0.65
	if arm_l != null:
		arm_l.rotation.x = -sin(w) * 0.55
		arm_l.rotation.z = -0.12
	if swing > 0.0:
		swing -= delta
		var k := 1.0 - swing / 0.35
		arm.rotation.x = -sin(k * PI) * 2.0
		bag.rotation.x = -sin(k * PI) * 1.2
	else:
		arm.rotation.x = sin(w) * 0.6 if arm_l == null else sin(w) * 0.55     # brazos al correr
		bag.rotation.x = sin(w + 1.0) * 0.3


func hurt(amount: float, dir: Vector3) -> void:
	if dying:
		return
	var game = get_tree().get_first_node_in_group("game")
	if game:
		game.add_points(int(clampf(amount * 2.0, 2.0, 10.0)))
	hp -= amount
	global_position += Vector3(dir.x, 0.0, dir.z) * amount * 0.04
	if hp <= 0.0:
		dying = true
		remove_from_group("zombies")
		remove_from_group("isabellas")
		if game:
			game.add_points(70)
			game.zombie_killed(self)
		var tw := create_tween()
		tw.tween_property(model, "rotation:x", deg_to_rad(80.0), 0.35)
		tw.tween_property(model, "scale", Vector3.ZERO, 0.3)
		tw.tween_callback(queue_free)

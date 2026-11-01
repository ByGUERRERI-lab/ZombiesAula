# Calidad gráfica: BAJO / ALTO / ULTRA (se cambia con F3 y se guarda).
# ULTRA = iluminación global en tiempo real (SDFGI, la luz rebota en
# paredes y suelo), reflejos en pantalla, niebla volumétrica con haces
# de luz bajo los focos y sombras suaves en todas las luces.

const SAVE_PATH := "user://graficos.cfg"
const NOMBRES := ["BAJO", "ALTO", "ULTRA"]

static var nivel := 2
static var _loaded := false


static func cargar() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		nivel = clampi(int(cfg.get_value("graficos", "nivel", nivel)), 0, 2)


static func guardar() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("graficos", "nivel", nivel)
	cfg.save(SAVE_PATH)


static func siguiente() -> void:
	nivel = (nivel + 1) % NOMBRES.size()
	guardar()


# Entorno base del instituto (lo que no depende de la calidad)
static func entorno() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.8, 0.9)
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 0.95
	env.glow_enabled = true
	env.glow_normalized = true
	env.glow_hdr_threshold = 1.0
	env.glow_hdr_scale = 2.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_intensity = 0.9
	env.glow_bloom = 0.02
	for i in 7:
		env.set_glow_level(i, [0.0, 1.0, 0.8, 1.0, 0.6, 0.3, 0.0][i])
	env.fog_enabled = true
	env.fog_light_color = Color(0.5, 0.55, 0.6)
	env.fog_density = 0.006
	env.volumetric_fog_albedo = Color(0.85, 0.88, 0.95)
	env.volumetric_fog_anisotropy = 0.55      # la luz se dispersa hacia delante: haces visibles
	env.volumetric_fog_length = 48.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_gi_inject = 0.4
	env.volumetric_fog_ambient_inject = 0.0
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.0
	env.ssao_detail = 0.6
	env.ssil_radius = 4.0
	env.ssil_intensity = 1.2
	env.ssr_max_steps = 72
	env.ssr_fade_in = 0.12
	env.ssr_fade_out = 2.5
	env.ssr_depth_tolerance = 0.25
	env.sdfgi_use_occlusion = true
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = 0.15
	env.sdfgi_energy = 1.1
	env.sdfgi_bounce_feedback = 0.6
	env.sdfgi_read_sky_light = false
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.15
	env.adjustment_saturation = 1.12
	return env


# Activa o quita los efectos según el nivel
static func aplicar(env: Environment, vp: Viewport) -> void:
	var ultra := nivel >= 2
	var alto := nivel >= 1
	env.sdfgi_enabled = ultra
	env.volumetric_fog_enabled = ultra
	env.volumetric_fog_density = 0.01
	env.ssil_enabled = ultra
	env.ssr_enabled = alto
	env.ssao_enabled = alto
	# con SDFGI la luz ya rebota de verdad: menos luz ambiente "falsa"
	env.ambient_light_energy = 0.12 if ultra else 0.35
	vp.msaa_3d = Viewport.MSAA_4X if alto else Viewport.MSAA_2X
	vp.use_debanding = true
	vp.positional_shadow_atlas_size = 8192 if ultra else 4096
	var q := RenderingServer.SHADOW_QUALITY_SOFT_HIGH if ultra else (RenderingServer.SHADOW_QUALITY_SOFT_LOW if alto else RenderingServer.SHADOW_QUALITY_HARD)
	RenderingServer.positional_soft_shadow_filter_set_quality(q)
	RenderingServer.directional_soft_shadow_filter_set_quality(q)
	RenderingServer.gi_set_use_half_resolution(true)     # la GI a media resolución: casi igual y mucho más rápida


# Suelo pulido de verdad: poco rugoso y con manchas de desgaste,
# así los reflejos de los focos se ven en él
static func pulir(body: Node, rough: float) -> void:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.02
	noise.fractal_octaves = 4
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.seamless = true
	tex.width = 256
	tex.height = 256
	for ch in body.get_children():
		if ch is MeshInstance3D:
			var m: StandardMaterial3D = ch.material_override
			m.roughness = rough * 2.2
			m.roughness_texture = tex
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(0.15, 0.15, 0.15)
			m.metallic_specular = 0.6


# Sonda de reflejos para una sala (se calcula una vez)
static func sonda(parent: Node3D, center: Vector3, size: Vector3) -> void:
	var p := ReflectionProbe.new()
	p.position = center
	p.size = size
	p.box_projection = true
	p.interior = true
	p.update_mode = ReflectionProbe.UPDATE_ONCE
	p.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	p.max_distance = maxf(size.x, size.z)
	parent.add_child(p)

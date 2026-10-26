class_name Weather
extends CanvasLayer
## Clima en pantalla (data/weather.json): niebla de la mañana, llovizna después del almuerzo, aguanieve y la nevada
## de las 17:47, con el viento empujándola de costado. Es igual en todos los loops: sigue la hora, no el azar.
## Solo se ve en los exteriores, sobre el mundo y debajo del HUD, con el color de la luz del día (DayLight).
## La niebla es un shader sobre la pantalla: jirones de ruido anclados al mundo (no siguen al jugador; el viento
## los arrastra) y un desenfoque suave de lo que hay detrás. Lluvia y nieve caen en coordenadas de pantalla.

const DATA_PATH: String = "res://data/weather.json"
const SIZE: Vector2 = Vector2(640.0, 360.0)
const MAX_DROPS: int = 340
const MAX_FLAKES: int = 700
const FOG_SHADER: String = """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float amount = 0.0;
uniform vec3 tint = vec3(0.86, 0.88, 0.9);
uniform vec2 origin = vec2(0.0);        // px del mundo en la esquina superior izquierda de la pantalla
uniform vec2 view = vec2(640.0, 360.0); // px del mundo que entran en pantalla
uniform float drift = 0.0;              // corrimiento acumulado por el viento (px)

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * noise(p); p = p * 2.03 + vec2(1.7, 9.2); a *= 0.5; }
	return v;
}
void fragment() {
	vec2 world = origin + SCREEN_UV * view;
	vec2 p = (world + vec2(drift, 0.0)) / vec2(260.0, 120.0);   // jirones estirados a lo ancho
	float n = fbm(p) * 0.7 + fbm(p * 2.6 - vec2(drift * 0.004, 0.0)) * 0.3;
	float density = clamp(amount * (0.2 + 1.4 * (n - 0.35)), 0.0, 1.0);
	vec2 px = SCREEN_PIXEL_SIZE * (1.5 + 1.5 * amount);
	vec3 base = texture(screen_tex, SCREEN_UV).rgb;
	vec3 blur = base * 0.2;
	blur += texture(screen_tex, SCREEN_UV + vec2(px.x, 0.0)).rgb * 0.1;
	blur += texture(screen_tex, SCREEN_UV - vec2(px.x, 0.0)).rgb * 0.1;
	blur += texture(screen_tex, SCREEN_UV + vec2(0.0, px.y)).rgb * 0.1;
	blur += texture(screen_tex, SCREEN_UV - vec2(0.0, px.y)).rgb * 0.1;
	blur += texture(screen_tex, SCREEN_UV + px).rgb * 0.1;
	blur += texture(screen_tex, SCREEN_UV - px).rgb * 0.1;
	blur += texture(screen_tex, SCREEN_UV + vec2(px.x, -px.y)).rgb * 0.1;
	blur += texture(screen_tex, SCREEN_UV + vec2(-px.x, px.y)).rgb * 0.1;
	vec3 col = mix(base, blur, clamp(amount * 0.3 + density * 0.5, 0.0, 1.0));
	col = mix(col, tint, density * 0.6 + amount * 0.06);
	COLOR = vec4(col, 1.0);
}
"""

var _keys: Array = []
var _zone_fog: Dictionary = {}
var _day_light: DayLight
var _now: Dictionary = {"fog": 0.0, "rain": 0.0, "snow": 0.0, "wind": 0.0}
var _tint: Color = Color.WHITE
var _drops: Array[Vector3] = []    # x, y, velocidad
var _flakes: Array[Vector3] = []   # x, y, velocidad
var _time: float = 0.0
var _drift: float = 0.0
var _fog: ColorRect
var _fog_material: ShaderMaterial
var _canvas: Node2D


func setup(day_light: DayLight) -> void:
	_day_light = day_light


func _ready() -> void:
	layer = 5
	var parsed: Dictionary = GameConfig.read_data(DATA_PATH)
	if not parsed.is_empty():
		for key: Dictionary in parsed.get("keys", []):
			var k: Dictionary = key.duplicate()
			k["t"] = TimeManager.parse_clock(key["time"])
			_keys.append(k)
		_zone_fog = parsed.get("zone_fog", {})
	var rng := RandomNumberGenerator.new()
	rng.seed = 1947   # cualquier semilla fija: el clima es el mismo en todos los loops
	for i in MAX_DROPS:
		_drops.append(Vector3(rng.randf() * SIZE.x, rng.randf() * SIZE.y, rng.randf_range(260.0, 340.0)))
	for i in MAX_FLAKES:
		_flakes.append(Vector3(rng.randf() * SIZE.x, rng.randf() * SIZE.y, rng.randf_range(18.0, 52.0)))
	var shader := Shader.new()
	shader.code = FOG_SHADER
	_fog_material = ShaderMaterial.new()
	_fog_material.shader = shader
	_fog = ColorRect.new()
	_fog.material = _fog_material
	_fog.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fog)
	_canvas = Node2D.new()
	_canvas.draw.connect(_draw_weather)
	add_child(_canvas)


func _process(delta: float) -> void:
	_time += delta
	_sample(TimeManager.now_minutes())
	visible = ZoneManager.is_exterior(ZoneManager.current_zone)
	if not visible:
		return
	if _day_light != null:
		_tint = _day_light.sample(TimeManager.now_minutes(), true)["color"].lerp(Color.WHITE, 0.35)
	var wind: float = _now["wind"]
	for i in int(MAX_DROPS * _now["rain"]):
		var d: Vector3 = _drops[i]
		d.y += d.z * delta
		d.x += d.z * delta * (0.08 + wind * 0.35)
		if d.y > SIZE.y:
			d.y = -8.0
			d.x = fposmod(d.x - SIZE.y * (0.08 + wind * 0.35), SIZE.x)
		d.x = fposmod(d.x, SIZE.x)
		_drops[i] = d
	for i in int(MAX_FLAKES * _now["snow"]):
		var f: Vector3 = _flakes[i]
		f.y += f.z * delta * (1.0 + wind * 0.6)
		f.x += (sin(_time * 1.3 + i) * 6.0 + wind * 120.0 * (0.5 + f.z / 52.0)) * delta
		if f.y > SIZE.y:
			f.y = -2.0
		f.x = fposmod(f.x, SIZE.x)
		_flakes[i] = f
	_drift += (6.0 + wind * 18.0) * delta
	_update_fog()
	_canvas.queue_redraw()


## Intensidades interpoladas para la hora `minutes` (la niebla, además, según la zona).
func _sample(minutes: float) -> void:
	if _keys.is_empty():
		return
	var a: Dictionary = _keys[0]
	var b: Dictionary = _keys[0]
	for i in range(1, _keys.size()):
		b = _keys[i]
		if minutes <= b["t"]:
			a = _keys[i - 1]
			break
		a = b
	var f: float = 0.0 if b["t"] == a["t"] else clampf((minutes - a["t"]) / (b["t"] - a["t"]), 0.0, 1.0)
	for key: String in ["fog", "rain", "snow", "wind"]:
		_now[key] = lerpf(a[key], b[key], f)
	_now["fog"] = clampf(_now["fog"] * float(_zone_fog.get(ZoneManager.current_zone, 1.0)), 0.0, 1.0)


## La niebla se ancla al mundo: el shader recibe qué parte del mundo está en pantalla.
func _update_fog() -> void:
	var fog: float = _now["fog"]
	_fog.visible = fog > 0.01
	if not _fog.visible:
		return
	var to_world: Transform2D = get_viewport().canvas_transform.affine_inverse()
	_fog_material.set_shader_parameter("amount", fog)
	_fog_material.set_shader_parameter("tint", Color(0.86, 0.88, 0.9) * _tint)
	_fog_material.set_shader_parameter("origin", to_world * Vector2.ZERO)
	_fog_material.set_shader_parameter("view", to_world.basis_xform(get_viewport().get_visible_rect().size))
	_fog_material.set_shader_parameter("drift", _drift)


func _draw_weather() -> void:
	var rain_color := Color(Color(0.78, 0.84, 0.94) * _tint, 0.6)
	var slant: float = 0.08 + _now["wind"] * 0.35
	for i in int(MAX_DROPS * _now["rain"]):
		var d: Vector3 = _drops[i]
		var tail := Vector2(-slant, -1.0).normalized() * (6.0 + d.z * 0.015)
		_canvas.draw_line(Vector2(floorf(d.x), floorf(d.y)), Vector2(floorf(d.x + tail.x), floorf(d.y + tail.y)), rain_color, 1.0)
	# la nieve casi no se apaga de noche: refleja los faroles y las ventanas
	var flake_color := Color(Color(0.97, 0.97, 1.0) * _tint.lerp(Color.WHITE, 0.5), 0.9)
	for i in int(MAX_FLAKES * _now["snow"]):
		var f: Vector3 = _flakes[i]
		var s: float = 1.0 if f.z < 28.0 else 2.0
		_canvas.draw_rect(Rect2(floorf(f.x), floorf(f.y), s, s), flake_color)

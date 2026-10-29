extends Node
## Audio del juego (canon 09 §10). Todo el audio es CC0 / dominio público (assets/audio/CREDITS.md,
## se regenera con tools/import_audio.py).
##
## Cuatro capas: música (mínima; silencio entre 17:30 y 17:47), ambiente por zona, efectos
## diegéticos y el tic del reloj, que sube de volumen desde las 17:00.
## Buses: Master > Music / SFX / Ambient (los crea SettingsManager). Todo se configura en data/audio.json.

const CONFIG_PATH: String = "res://data/audio.json"
const MUSIC_DIR: String = "res://assets/audio/music/"
const SFX_DIR: String = "res://assets/audio/sfx/"
const AMBIENT_DIR: String = "res://assets/audio/ambient/"
const CROSSFADE: float = 2.0
const SILENT_DB: float = -60.0
## Un ambiente nuevo entra desde este volumen (no desde el silencio) y salteando los primeros/últimos segundos.
const AMBIENT_FADE_FROM_DB: float = -18.0
const AMBIENT_SKIP: float = 6.0
## Fundido del ambiente al cambiar de zona: corto, para que el lugar suene apenas se entra.
const ZONE_AMBIENT_FADE: float = 0.35
const ZONE_MUSIC_FADE: float = 0.8
const SFX_VOICES: int = 8
const SFX_COOLDOWN_MS: int = 120   # un mismo efecto no se dispara dos veces seguidas (evita los clics de fichin-2.0)

var current_track: String = ""
var current_ambient: String = ""
var in_game: bool = false

var _config: Dictionary = {}
var _music: Array[AudioStreamPlayer] = []
var _ambient: Array[AudioStreamPlayer] = []
var _sfx: Array[AudioStreamPlayer] = []
var _active_music: int = 0
var _active_ambient: int = 0
var _sfx_index: int = 0
var _last_played: Dictionary = {}
var _streams: Dictionary = {}
var _variants: Dictionary = {}   # "dir+nombre" -> [nombre, nombre_2, nombre_3...]
var _fade_music: Tween
var _fade_ambient: Tween
var _desired_track: String = ""
var _chasing: bool = false   # la sospecha pasó la advertencia y todavía no bajó lo suficiente: suena la música de persecución


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_config = GameConfig.read_data(CONFIG_PATH)
	for i in 2:
		_music.append(_make_player("Music"))
		_ambient.append(_make_player("Ambient"))
	for i in SFX_VOICES:
		_sfx.append(_make_player("SFX"))
	TimeManager.minute_changed.connect(_on_minute_changed)
	ZoneManager.zone_changed.connect(_on_zone_changed)
	GameManager.suspicion_changed.connect(_on_suspicion_changed)


func _make_player(bus: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = bus
	player.volume_db = SILENT_DB
	add_child(player)
	return player


# ── Música ──────────────────────────────────────────────────────────────────
func play_music(track: String, fade: float = CROSSFADE) -> void:
	_desired_track = track
	if track == current_track:
		return
	var stream: AudioStream = _stream(MUSIC_DIR, track)
	if stream == null:
		return
	var old: AudioStreamPlayer = _music[_active_music]
	_active_music = 1 - _active_music
	var fresh: AudioStreamPlayer = _music[_active_music]
	fresh.stream = stream
	fresh.volume_db = SILENT_DB
	fresh.play()
	if _fade_music != null:
		_fade_music.kill()
	_fade_music = create_tween().set_parallel(true)
	_fade_music.tween_property(fresh, "volume_db", 0.0, fade)
	_fade_music.tween_property(old, "volume_db", SILENT_DB, fade)
	_fade_music.chain().tween_callback(old.stop)
	current_track = track


func stop_music(fade: float = CROSSFADE) -> void:
	_desired_track = ""
	current_track = ""
	if _fade_music != null:
		_fade_music.kill()
	_fade_music = create_tween().set_parallel(true)
	for player in _music:
		_fade_music.tween_property(player, "volume_db", SILENT_DB, fade)
	_fade_music.chain().tween_callback(func() -> void: for p in _music: p.stop())


# ── Efectos ─────────────────────────────────────────────────────────────────
func play_sfx(sfx_name: String, volume_db: float = 0.0, pitch_variation: float = 0.0) -> void:
	var now: int = Time.get_ticks_msec()
	if now - int(_last_played.get(sfx_name, -10000)) < SFX_COOLDOWN_MS:
		return
	_last_played[sfx_name] = now
	var stream: AudioStream = _stream(SFX_DIR, _pick_variant(SFX_DIR, sfx_name))
	if stream == null:
		return
	var voice: AudioStreamPlayer = _sfx[_sfx_index]
	_sfx_index = (_sfx_index + 1) % _sfx.size()
	voice.stream = stream
	voice.volume_db = volume_db
	voice.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	voice.play()


## Paso del personaje según el suelo (data/audio.json -> surfaces).
func play_footstep(surface: String) -> void:
	play_sfx("footstep_" + surface, -14.0, 0.08)


func surface_for_tile(atlas_x: int) -> String:
	var surfaces: Dictionary = _config.get("surfaces", {})
	for surface: String in surfaces:
		# El JSON trae los índices como float y `int in [float]` da falso: se compara uno por uno.
		for tile: Variant in surfaces[surface]:
			if int(tile) == atlas_x:
				return surface
	return "stone"


# ── Ambiente ────────────────────────────────────────────────────────────────
func set_ambient(ambient_name: String, fade: float = 1.5) -> void:
	if ambient_name == current_ambient:
		return
	current_ambient = ambient_name
	var old: AudioStreamPlayer = _ambient[_active_ambient]
	if _fade_ambient != null:
		_fade_ambient.kill()
	_fade_ambient = create_tween().set_parallel(true)
	_fade_ambient.tween_property(old, "volume_db", SILENT_DB, fade)
	_fade_ambient.chain().tween_callback(old.stop)
	if ambient_name == "":
		return
	var stream: AudioStream = _stream(AMBIENT_DIR, ambient_name)
	if stream == null:
		return
	_active_ambient = 1 - _active_ambient
	var fresh: AudioStreamPlayer = _ambient[_active_ambient]
	fresh.stream = stream
	# Arranca casi audible y desde un punto cualquiera de la grabación: al entrar a un lugar, el lugar ya estaba
	# sonando (desde -60 dB, la mitad del fundido no se oía; y algunas tomas empiezan con su propio fundido).
	fresh.volume_db = AMBIENT_FADE_FROM_DB
	var length: float = stream.get_length()
	fresh.play(randf_range(AMBIENT_SKIP, length - AMBIENT_SKIP) if length > AMBIENT_SKIP * 3.0 else 0.0)
	_fade_ambient.tween_property(fresh, "volume_db", 0.0, fade)


# ── Estados del juego ───────────────────────────────────────────────────────
func enter_menu() -> void:
	in_game = false
	set_ambient("", 0.8)
	var menu_track: String = _config.get("menu_music", "")
	if menu_track != "":
		play_music(menu_track, 1.5)
	else:
		stop_music(0.8)


func enter_game() -> void:
	in_game = true
	current_track = ""
	_update_for_time(true)
	_update_ambient()


func _on_minute_changed(_hour: int, _minute: int) -> void:
	if not in_game:
		return
	_update_for_time(false)
	var now: int = TimeManager.now_minutes()
	# "clock_tick_from": desde esa hora suena el tic del reloj, cada vez más fuerte (media hora hasta el máximo).
	var tick_from: int = TimeManager.parse_clock(_config.get("clock_tick_from", "")) if _config.has("clock_tick_from") else 99999
	if now >= tick_from:
		var progress: float = clampf(float(now - tick_from) / 30.0, 0.0, 1.0)
		play_sfx("clock_tick", lerpf(-28.0, -4.0, progress))
	_update_ambient()


func _update_for_time(force: bool, fade: float = CROSSFADE) -> void:
	var now: int = TimeManager.now_minutes()
	# "music_silence_from": desde esa hora no hay música; "music_periods": qué tema suena desde cada hora.
	var silence_from: int = TimeManager.parse_clock(_config["music_silence_from"]) if _config.has("music_silence_from") else 99999
	var track: String = ""
	var chasing: bool = _chase_active()
	# "music_muted_in": zonas con su propia música en el ambiente (el acordeón del bar): ahí no suena la de fondo.
	if ZoneManager.current_zone in _config.get("music_muted_in", []):
		now = silence_from
	if now < silence_from:
		for period: Dictionary in _config.get("music_periods", []):
			if now >= TimeManager.parse_clock(period["from"]):
				track = period["track"]
	if track == "":
		if current_track != "" or force:
			stop_music(minf(3.0, fade * 1.5))
		return
	# "chase": la persecución manda sobre la del horario (pero no sobre el silencio final ni las zonas sin música de fondo).
	if chasing:
		track = str(_config["chase"].get("track", track))
	play_music(track, fade)


## ¿Está la policía encima? Entra al pasar la advertencia de sospecha y sale al bajar de "release_below" (así no parpadea
## entre dos temas alrededor del umbral).
func _chase_active() -> bool:
	var chase: Dictionary = _config.get("chase", {})
	if chase.is_empty():
		return false
	if _chasing:
		_chasing = GameManager.suspicion >= int(chase.get("release_below", GameManager.suspicion_warning))
	else:
		_chasing = GameManager.suspicion >= GameManager.suspicion_warning
	return _chasing


func _on_suspicion_changed(_value: int) -> void:
	if in_game:
		_update_for_time(false)


func _on_zone_changed(_zone_id: String) -> void:
	if in_game:
		_update_for_time(false, ZONE_MUSIC_FADE)
		_update_ambient(ZONE_AMBIENT_FADE)


func _update_ambient(fade: float = 1.5) -> void:
	var zone: String = ZoneManager.current_zone
	var wanted: String = _config.get("ambient", {}).get(zone, "")
	# "ambient_changes": desde una hora, un ambiente se cambia por otro (el pueblo con lluvia cuando empieza a llover)
	for change: Dictionary in _config.get("ambient_changes", []):
		if wanted == change["replace"] and TimeManager.now_minutes() >= TimeManager.parse_clock(change["from"]):
			wanted = change["with"]
	# "ambient_crowds": con al menos `people` personas en la zona, el ambiente se cambia por su versión llena (el bar
	# a la hora del almuerzo). Sigue a la gente, no al reloj: si alguien se va antes, se nota.
	var crowd: Dictionary = _config.get("ambient_crowds", {}).get(wanted, {})
	if not crowd.is_empty() and people_in_zone(zone) >= int(crowd.get("people", 1)):
		wanted = crowd["busy"]
	set_ambient(wanted, fade)


## NPCs que están ahora en `zone_id` (extras incluidos).
func people_in_zone(zone_id: String) -> int:
	return get_tree().get_nodes_in_group("npc_actors").filter(func(n: Node) -> bool: return n.get("zone") == zone_id).size()


## Un efecto puede tener varias tomas (puerta.ogg, puerta_2.ogg, puerta_3.ogg...): se sortea una cada vez.
## Evita que los pasos y las puertas suenen siempre idénticos.
func _pick_variant(dir: String, base: String) -> String:
	var key: String = dir + base
	if not _variants.has(key):
		var names: Array[String] = [base]
		var n: int = 2
		while ResourceLoader.exists("%s%s_%d.ogg" % [dir, base, n]) or ResourceLoader.exists("%s%s_%d.wav" % [dir, base, n]):
			names.append("%s_%d" % [base, n])
			n += 1
		_variants[key] = names
	var options: Array = _variants[key]
	return options[randi() % options.size()]


func _stream(dir: String, stream_name: String) -> AudioStream:
	var path: String = dir + stream_name + ".ogg"
	if not ResourceLoader.exists(path) and ResourceLoader.exists(dir + stream_name + ".wav"):
		path = dir + stream_name + ".wav"
	if _streams.has(path):
		return _streams[path]
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = load(path)
		if stream is AudioStreamOggVorbis and dir != SFX_DIR:
			(stream as AudioStreamOggVorbis).loop = true
	elif DirAccess.dir_exists_absolute(dir):
		push_warning("AudioManager: falta %s" % path)   # sin la carpeta, el juego no tiene ese sonido: no se avisa
	_streams[path] = stream
	return stream

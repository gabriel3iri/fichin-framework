extends SceneTree
## Runner de addons/testkit. Corre los `test_*` de cada `test_*.gd` bajo res://tests y sale con 1 si alguno falla.
##   godot --headless --path . -s res://addons/jornada/testkit/runner.gd                 # todas menos las lentas
##   godot --headless --path . -s res://addons/jornada/testkit/runner.gd -- --slow       # también las test_slow_*
##   godot --headless --path . -s res://addons/jornada/testkit/runner.gd -- journal      # solo archivos o pruebas que contengan "journal"
## En macOS no hay `timeout`: usar tools/run_tests.sh, que corta si se cuelga.

const TEST_DIR: String = "res://tests"

var _passed: int = 0
var _failed: Array[String] = []


func _initialize() -> void:
	await process_frame   # los autoloads recién corren su _ready después del primer cuadro
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var slow: bool = "--slow" in args
	var filters: Array[String] = []
	for arg: String in args:
		if not arg.begins_with("--"):
			filters.append(arg)
	var started: int = Time.get_ticks_msec()
	var broken: Array[String] = _scripts_that_do_not_compile("res://")
	if not broken.is_empty():
		# Un script roto hace que todo lo que lo usa se cuelgue o falle lejos del error: se corta acá.
		print("NO COMPILAN %d scripts (ver los Parse Error de arriba):" % broken.size())
		for path: String in broken:
			print("  · " + path)
		quit(1)
		return
	for path: String in _find_tests(TEST_DIR):
		await _run_file(path, slow, filters)
	var total: int = _passed + _failed.size()
	print("")
	if _failed.is_empty():
		print("OK: %d pruebas en %.1f s" % [total, (Time.get_ticks_msec() - started) / 1000.0])
	else:
		print("FALLARON %d de %d:" % [_failed.size(), total])
		for name: String in _failed:
			print("  · " + name)
	quit(0 if _failed.is_empty() else 1)


func _run_file(path: String, slow: bool, filters: Array[String]) -> void:
	var script: GDScript = load(path)
	if script == null or not script.can_instantiate():
		_failed.append("%s (no compila)" % path)
		return
	for method: Dictionary in script.get_script_method_list():
		var method_name: String = method["name"]
		if not method_name.begins_with("test_") or (method_name.begins_with("test_slow_") and not slow):
			continue
		var full: String = "%s::%s" % [path.get_file().get_basename(), method_name]
		if not filters.is_empty() and not filters.any(func(f: String) -> bool: return f in full):
			continue
		var test: Variant = script.new()   # un TestCase (sin el tipo: así no depende del caché de class_name)
		test.tree = self
		var started: int = Time.get_ticks_msec()
		await test.before_each()
		await Callable(test, method_name).call()
		await test.after_each()
		var ms: int = Time.get_ticks_msec() - started
		if test.failures.is_empty():
			_passed += 1
			print("  ok    %s (%d ms)" % [full, ms])
		else:
			_failed.append(full)
			print("  FALLA %s (%d ms)" % [full, ms])
			for failure: String in test.failures:
				print("        - " + failure)


## Todos los .gd del proyecto que no compilan (salteando carpetas ocultas y los scripts sueltos tools/_*).
func _scripts_that_do_not_compile(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	for sub: String in DirAccess.get_directories_at(dir_path):
		var sub_path: String = dir_path.path_join(sub)
		# Como Godot: no entra a carpetas con .gdignore ni a otros proyectos (p. ej. un juego de ejemplo).
		if not sub.begins_with(".") and not FileAccess.file_exists(sub_path.path_join(".gdignore")) \
				and not FileAccess.file_exists(sub_path.path_join("project.godot")):
			out.append_array(_scripts_that_do_not_compile(sub_path))
	for file: String in DirAccess.get_files_at(dir_path):
		if file.ends_with(".gd") and not file.begins_with("_"):
			var script: GDScript = load(dir_path.path_join(file))
			if script == null or not script.can_instantiate():
				out.append(dir_path.path_join(file))
	return out


func _find_tests(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for sub: String in dir.get_directories():
		out.append_array(_find_tests(dir_path.path_join(sub)))
	for file: String in dir.get_files():
		if file.begins_with("test_") and file.ends_with(".gd"):
			out.append(dir_path.path_join(file))
	out.sort()
	return out

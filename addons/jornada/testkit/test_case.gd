class_name TestCase
extends RefCounted
## Base de las pruebas (addons/testkit, independiente del juego). Cada método `test_*` de un `tests/**/test_*.gd`
## es una prueba; puede ser asíncrono (await). Los que empiezan con `test_slow_` solo corren con `--slow`.
## Cada prueba usa una instancia nueva del script. Los asserts no cortan la prueba: anotan el fallo y siguen, así se
## ven todos los problemas de una vez. `before_each` / `after_each` se pueden redefinir (también con await).

var tree: SceneTree
var failures: Array[String] = []


func before_each() -> void:
	pass


func after_each() -> void:
	pass


# --- Asserts ---------------------------------------------------------------------------------------

func fail(message: String) -> void:
	failures.append(message)


func assert_true(condition: bool, message: String = "se esperaba verdadero") -> bool:
	if not condition:
		fail(message)
	return condition


func assert_false(condition: bool, message: String = "se esperaba falso") -> bool:
	return assert_true(not condition, message)


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> bool:
	if typeof(actual) == typeof(expected) and actual == expected:
		return true
	fail("%s: se esperaba %s y dio %s" % [message if message != "" else "assert_eq", var_to_str(expected), var_to_str(actual)])
	return false


func assert_ne(actual: Variant, unexpected: Variant, message: String = "") -> bool:
	if typeof(actual) != typeof(unexpected) or actual != unexpected:
		return true
	fail("%s: no se esperaba %s" % [message if message != "" else "assert_ne", var_to_str(actual)])
	return false


func assert_has(container: Variant, item: Variant, message: String = "") -> bool:
	if item in container:
		return true
	fail("%s: falta %s" % [message if message != "" else "assert_has", var_to_str(item)])
	return false


func assert_near(actual: float, expected: float, tolerance: float, message: String = "") -> bool:
	if absf(actual - expected) <= tolerance:
		return true
	fail("%s: se esperaba %s ± %s y dio %s" % [message if message != "" else "assert_near", expected, tolerance, actual])
	return false


# --- Tiempo y entrada ------------------------------------------------------------------------------

func frames(count: int = 1) -> void:
	for i in count:
		await tree.process_frame


func physics_frames(count: int = 1) -> void:
	for i in count:
		await tree.physics_frame


## Segundos reales: corre aunque el árbol esté en pausa y no lo acelera Engine.time_scale.
func seconds(amount: float) -> void:
	await tree.create_timer(amount, true, false, true).timeout


## Espera (cuadro a cuadro) a que `predicate` dé verdadero, hasta `timeout` segundos reales. Devuelve si lo logró.
func until(predicate: Callable, timeout: float = 5.0) -> bool:
	var limit: int = Time.get_ticks_msec() + int(timeout * 1000.0)
	while not predicate.call():
		if Time.get_ticks_msec() > limit:
			return false
		await tree.process_frame
	return true


## Aprieta y suelta una acción del InputMap (los botones de Godot disparan al soltar).
func press(action: String) -> void:
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	await tree.process_frame
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await tree.process_frame


func autoload(autoload_name: String) -> Node:
	return tree.root.get_node("/root/" + autoload_name)

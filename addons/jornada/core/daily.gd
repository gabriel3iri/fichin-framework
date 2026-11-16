extends RefCounted
## Elecciones «al azar» que se repiten igual cada jornada (día de la marmota): en vez de randi(), un número que sale
## de una clave (quién, qué y a qué minuto del día). Si el jugador no interviene, cada día se dice y se hace lo mismo
## a la misma hora; si cambia algo (está en otro lugar, pregunta otra cosa), cambia lo que oye.
## Sin class_name: quien lo usa lo precarga (`const Daily := preload(...)`), así no depende del caché de clases del
## editor (un clon sin --import, o el juego de ejemplo, no lo conocería).


## Índice entre 0 y n-1 para `key` (siempre el mismo para la misma clave).
static func index(key: String, n: int) -> int:
	if n <= 0:
		return 0
	return absi(key.hash()) % n


## Un elemento de `options` elegido por `key`.
static func pick(options: Array, key: String) -> Variant:
	return options[index(key, options.size())] if not options.is_empty() else null


## Un número entre `from` y `to` elegido por `key`.
static func range_f(from: float, to: float, key: String) -> float:
	return from + (to - from) * float(index(key, 10007)) / 10006.0


## La clave de `id` en este minuto de la jornada.
static func at_minute(id: String) -> String:
	return "%s@%d" % [id, int(TimeManager.minutes)]

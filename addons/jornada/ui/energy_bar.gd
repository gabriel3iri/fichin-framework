class_name EnergyBar
extends Control
## Barra de energía del HUD: un marco y un relleno, sin número. Ámbar mientras alcanza, roja cuando queda poco, y parpadea
## mientras el personaje está sin aliento. Se alimenta con Stamina.changed (ver Hud).

const LOW: float = 0.25

var fraction: float = 1.0
var _blink: Tween


func _init() -> void:
	custom_minimum_size = Vector2(60, 5)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_fraction(value: float) -> void:
	fraction = clampf(value, 0.0, 1.0)
	queue_redraw()


func set_exhausted(on: bool) -> void:
	if _blink != null:
		_blink.kill()
		_blink = null
	modulate.a = 1.0
	if on:
		_blink = create_tween().set_loops()
		_blink.tween_property(self, "modulate:a", 0.35, 0.3)
		_blink.tween_property(self, "modulate:a", 1.0, 0.3)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UiStyle.INK)
	draw_rect(Rect2(Vector2.ZERO, size), UiStyle.BORDER, false, 1.0)
	var inner: float = maxf(0.0, size.x - 2.0) * fraction
	if inner > 0.0:
		draw_rect(Rect2(1.0, 1.0, inner, size.y - 2.0), UiStyle.BAD if fraction <= LOW else UiStyle.ACCENT)

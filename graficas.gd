extends Control
class_name RealTimePlot

@export var title: String = "Variable"
@export var unit: String = ""
@export var line_color: Color = Color(0.2, 0.85, 1.0)
@export var ref_color: Color = Color(0.2, 0.9, 0.4, 0.85)
@export var max_points: int = 300 # 300 muestras = 5 segundos a 60 Hz
@export var auto_scale: bool = true
@export var y_min: float = -1.0
@export var y_max: float = 1.0

var _values: Array[float] = []
var _refs: Array[float] = []

func add_sample(value: float, ref_value: float = NAN) -> void:
	_values.append(value)
	_refs.append(ref_value)
	if _values.size() > max_points:
		_values.pop_front()
		_refs.pop_front()
	queue_redraw()

func clear() -> void:
	_values.clear()
	_refs.clear()
	queue_redraw()

func _draw() -> void:
	# 1. Fondo y borde del panel
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.09, 0.12, 0.85), true)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.35, 0.4, 0.5, 0.8), false, 1.0)

	var margin_top: float = 24.0
	var margin_bottom: float = 8.0
	var margin_x: float = 8.0
	var plot_w: float = maxf(size.x - margin_x * 2.0, 1.0)
	var plot_h: float = maxf(size.y - margin_top - margin_bottom, 1.0)

	# 2. Calcular rango vertical (auto-escala o fijo)
	var min_v: float = y_min
	var max_v: float = y_max

	if auto_scale and _values.size() > 0:
		min_v = _values[0]
		max_v = _values[0]
		for i: int in range(_values.size()):
			min_v = minf(min_v, _values[i])
			max_v = maxf(max_v, _values[i])
			if not is_nan(_refs[i]):
				min_v = minf(min_v, _refs[i])
				max_v = maxf(max_v, _refs[i])

		var span: float = max_v - min_v
		if span < 0.05:
			# Evitar division por cero cuando la señal es completamente plana
			var mid: float = (max_v + min_v) * 0.5
			min_v = mid - 0.05
			max_v = mid + 0.05
		else:
			min_v -= span * 0.15
			max_v += span * 0.15

	# 3. Linea horizontal de referencia en Y = 0
	if min_v < 0.0 and max_v > 0.0:
		var zero_norm: float = (0.0 - min_v) / (max_v - min_v)
		var zero_y: float = margin_top + plot_h * (1.0 - zero_norm)
		draw_line(
			Vector2(margin_x, zero_y),
			Vector2(size.x - margin_x, zero_y),
			Color(1.0, 1.0, 1.0, 0.2),
			1.0
		)

	# 4. Construir polilineas de datos y referencia
	var pts := PackedVector2Array()
	var ref_pts := PackedVector2Array()
	var step_x: float = plot_w / float(maxi(max_points - 1, 1))

	for i: int in range(_values.size()):
		var px: float = margin_x + float(i) * step_x
		var norm_y: float = clampf((_values[i] - min_v) / (max_v - min_v), 0.0, 1.0)
		var py: float = margin_top + plot_h * (1.0 - norm_y)
		pts.append(Vector2(px, py))

		if not is_nan(_refs[i]):
			var r_norm_y: float = clampf((_refs[i] - min_v) / (max_v - min_v), 0.0, 1.0)
			var r_py: float = margin_top + plot_h * (1.0 - r_norm_y)
			ref_pts.append(Vector2(px, r_py))

	if ref_pts.size() >= 2:
		draw_polyline(ref_pts, ref_color, 1.5, true)

	if pts.size() >= 2:
		draw_polyline(pts, line_color, 2.0, true)

	# 5. Textos de titulo, valor actual y rango
	var font: Font = ThemeDB.fallback_font
	var val_text: String = "0.00"
	if _values.size() > 0:
		val_text = "%.2f" % _values[-1]

	var header: String = "%s: %s %s" % [title, val_text, unit]
	draw_string(font, Vector2(8.0, 16.0), header, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)

	var range_text: String = "[%.1f, %.1f]" % [min_v, max_v]
	draw_string(
		font,
		Vector2(size.x - 8.0, 16.0),
		range_text,
		HORIZONTAL_ALIGNMENT_RIGHT,
		-1,
		11,
		Color(0.7, 0.75, 0.8, 0.85)
	)

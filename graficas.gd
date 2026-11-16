extends Control
class_name RealTimePlot

# ============================================================
# GRAFICA EN TIEMPO REAL CON EJES
# ============================================================
# Eje horizontal: tiempo de simulacion t [s] (ventana deslizante).
# Eje vertical:   la magnitud medida, p. ej. "x [m]" o "θ' [°/s]".
# Hasta tres series: no lineal (principal), lineal y referencia.

@export var title: String = "Variable"
@export var show_title: bool = true          # false si el contenedor ya muestra el titulo
@export var axis_label: String = "y"         # Simbolo de la magnitud (x, θ, x', θ')
@export var unit: String = ""
@export var line_color: Color = Color(0.2, 0.85, 1.0)
@export var ref_color: Color = Color(0.2, 0.9, 0.4, 0.85)
@export var linear_color: Color = Color(1.0, 0.45, 0.85, 0.9)
@export var window_seconds: float = 5.0      # Tiempo visible en el eje horizontal
@export var auto_scale: bool = true
@export var y_min: float = -1.0
@export var y_max: float = 1.0

@export_group("Texto")
@export var font_size_title: int = 11
@export var font_size_axis: int = 9
@export var font_size_ticks: int = 8

# Nombres de las series en la leyenda
var main_name: String = "no lineal"
var linear_name: String = "lineal"
var ref_name: String = "referencia"

var _t: Array[float] = []
var _values: Array[float] = []
var _refs: Array[float] = []
var _lins: Array[float] = []

const MARGEN_IZQ: float = 44.0
const MARGEN_DER: float = 10.0
const MARGEN_SUP: float = 30.0
const MARGEN_INF: float = 28.0
const COLOR_FONDO := Color(0.08, 0.09, 0.12, 0.92)
const COLOR_BORDE := Color(0.35, 0.4, 0.5, 0.8)
const COLOR_REJILLA := Color(1.0, 1.0, 1.0, 0.07)
const COLOR_CERO := Color(1.0, 1.0, 1.0, 0.25)
const COLOR_TEXTO_EJE := Color(0.75, 0.8, 0.85, 0.95)


# t: tiempo de simulacion [s]; value: modelo no lineal; ref_value: referencia;
# linear_value: modelo lineal. NAN en ref_value o linear_value = no se dibuja.
func add_sample(t: float, value: float, ref_value: float = NAN, linear_value: float = NAN) -> void:
	_t.append(t)
	_values.append(value)
	_refs.append(ref_value)
	_lins.append(linear_value)
	# Conservar solo lo que cabe en la ventana (con un pequeno margen)
	while _t.size() > 2 and _t[1] < t - window_seconds:
		_t.pop_front()
		_values.pop_front()
		_refs.pop_front()
		_lins.pop_front()
	if is_visible_in_tree():
		queue_redraw()


func clear() -> void:
	_t.clear()
	_values.clear()
	_refs.clear()
	_lins.clear()
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and visible:
		queue_redraw()


func _draw() -> void:
	var font: Font = get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_FONDO, true)
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BORDE, false, 1.0)

	var area := Rect2(
		Vector2(MARGEN_IZQ, MARGEN_SUP),
		Vector2(maxf(size.x - MARGEN_IZQ - MARGEN_DER, 1.0), maxf(size.y - MARGEN_SUP - MARGEN_INF, 1.0))
	)

	# --- Rangos ---
	var rango_y: Vector2 = _rango_vertical()
	var t_fin: float = maxf(window_seconds, _t[-1] if _t.size() > 0 else 0.0)
	var t_ini: float = t_fin - window_seconds

	# --- Rejilla y marcas del eje vertical ---
	var paso_y: float = _paso_bonito((rango_y.y - rango_y.x) / 4.0)
	var v: float = ceilf(rango_y.x / paso_y) * paso_y
	while v <= rango_y.y + paso_y * 0.001:
		var y: float = _y_pantalla(v, rango_y, area)
		var es_cero: bool = absf(v) < paso_y * 0.001
		draw_line(Vector2(area.position.x, y), Vector2(area.end.x, y),
			COLOR_CERO if es_cero else COLOR_REJILLA, 1.0)
		draw_string(font, Vector2(0.0, y + font_size_ticks * 0.35), _formato(0.0 if es_cero else v, paso_y),
			HORIZONTAL_ALIGNMENT_RIGHT, area.position.x - 4.0, font_size_ticks, COLOR_TEXTO_EJE)
		v += paso_y

	# --- Rejilla y marcas del eje horizontal (tiempo) ---
	var paso_t: float = _paso_bonito(window_seconds / 5.0)
	var tm: float = ceilf(t_ini / paso_t) * paso_t
	while tm <= t_fin + paso_t * 0.001:
		var x: float = area.position.x + (tm - t_ini) / window_seconds * area.size.x
		draw_line(Vector2(x, area.position.y), Vector2(x, area.end.y), COLOR_REJILLA, 1.0)
		draw_line(Vector2(x, area.end.y), Vector2(x, area.end.y + 3.0), COLOR_BORDE, 1.0)
		draw_string(font, Vector2(x - 20.0, area.end.y + 4.0 + font_size_ticks), _formato(tm, paso_t),
			HORIZONTAL_ALIGNMENT_CENTER, 40.0, font_size_ticks, COLOR_TEXTO_EJE)
		tm += paso_t

	draw_rect(area, COLOR_BORDE, false, 1.0)

	# --- Nombres de los ejes ---
	draw_string(font, Vector2(area.position.x, size.y - 3.0), "Tiempo  t [s]",
		HORIZONTAL_ALIGNMENT_CENTER, area.size.x, font_size_axis, COLOR_TEXTO_EJE)

	var etiqueta_y: String = "%s [%s]" % [axis_label, unit] if unit != "" else axis_label
	draw_set_transform(Vector2(font_size_axis + 1.0, area.get_center().y), -PI / 2.0)
	draw_string(font, Vector2(-area.size.y * 0.5, 0.0), etiqueta_y,
		HORIZONTAL_ALIGNMENT_CENTER, area.size.y, font_size_axis, COLOR_TEXTO_EJE)
	draw_set_transform(Vector2.ZERO, 0.0)

	# --- Series ---
	for serie: Array in [[_refs, ref_color, 1.5], [_lins, linear_color, 1.5], [_values, line_color, 2.0]]:
		for tramo: PackedVector2Array in _tramos(serie[0], rango_y, area, t_ini):
			if tramo.size() >= 2:
				draw_polyline(tramo, serie[1], serie[2], true)

	# --- Titulo y leyenda con el valor actual ---
	if show_title:
		draw_string(font, Vector2(8.0, 6.0 + font_size_title), title,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_title, Color.WHITE)

	var leyenda: Array = []
	if _values.size() > 0:
		leyenda.append([main_name, _values[-1], line_color])
		if not is_nan(_lins[-1]):
			leyenda.append([linear_name, _lins[-1], linear_color])
		if not is_nan(_refs[-1]):
			leyenda.append([ref_name, _refs[-1], ref_color])
	var x_der: float = size.x - MARGEN_DER
	for i in range(leyenda.size() - 1, -1, -1):
		var item: Array = leyenda[i]
		var texto: String = "%s: %.2f %s" % [item[0], item[1], unit]
		var ancho: float = font.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_ticks + 1).x
		draw_string(font, Vector2(x_der - ancho, 6.0 + font_size_title), texto,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_ticks + 1, item[2])
		draw_line(Vector2(x_der - ancho - 14.0, 2.0 + font_size_title * 0.6),
			Vector2(x_der - ancho - 4.0, 2.0 + font_size_title * 0.6), item[2], 2.0)
		x_der -= ancho + 24.0


# Rango vertical: fijo, o ajustado a los datos visibles.
func _rango_vertical() -> Vector2:
	if not auto_scale or _values.is_empty():
		return Vector2(y_min, y_max)
	var mn: float = INF
	var mx: float = -INF
	for serie: Array[float] in [_values, _refs, _lins]:
		for valor: float in serie:
			if not is_nan(valor):
				mn = minf(mn, valor)
				mx = maxf(mx, valor)
	var span: float = mx - mn
	if span < 0.05:
		var mid: float = (mx + mn) * 0.5
		return Vector2(mid - 0.05, mid + 0.05)
	return Vector2(mn - span * 0.1, mx + span * 0.1)


func _y_pantalla(valor: float, rango_y: Vector2, area: Rect2) -> float:
	var norm: float = clampf((valor - rango_y.x) / (rango_y.y - rango_y.x), 0.0, 1.0)
	return area.end.y - norm * area.size.y


# Convierte una serie en tramos de puntos de pantalla; los NAN cortan la linea.
func _tramos(serie: Array[float], rango_y: Vector2, area: Rect2, t_ini: float) -> Array[PackedVector2Array]:
	var tramos: Array[PackedVector2Array] = []
	var actual := PackedVector2Array()
	for i in range(serie.size()):
		if is_nan(serie[i]) or _t[i] < t_ini:
			if actual.size() > 0:
				tramos.append(actual)
				actual = PackedVector2Array()
			continue
		var x: float = area.position.x + (_t[i] - t_ini) / window_seconds * area.size.x
		actual.append(Vector2(x, _y_pantalla(serie[i], rango_y, area)))
	if actual.size() > 0:
		tramos.append(actual)
	return tramos


# Paso "redondo" (1, 2 o 5 x 10^n) cercano a 'aproximado'.
func _paso_bonito(aproximado: float) -> float:
	if aproximado <= 0.0 or not is_finite(aproximado):
		return 1.0
	var base: float = pow(10.0, floorf(log(aproximado) / log(10.0)))
	var r: float = aproximado / base
	if r < 1.5:
		return base
	if r < 3.5:
		return 2.0 * base
	if r < 7.5:
		return 5.0 * base
	return 10.0 * base


func _formato(valor: float, paso: float) -> String:
	var decimales: int = maxi(0, -int(floorf(log(paso) / log(10.0) + 0.0001)))
	return String.num(valor, decimales)

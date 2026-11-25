extends Control
class_name RealTimePlot

# ============================================================
# GRAFICA EN TIEMPO REAL CON EJES (fondo blanco)
# ============================================================
# Eje horizontal: tiempo de simulacion t [s].
# Eje vertical:   la magnitud medida, p. ej. "x [m]" o "θ' [°/s]".
# Series: no lineal (linea continua), referencia (continua, fina) y
# modelo lineal (punteada, dibujada encima para compararla).
# Se marcan con un punto el valor maximo y el minimo de la serie principal.

@export var title: String = "Variable"
@export var show_title: bool = true          # false si el contenedor ya muestra el titulo
@export var axis_label: String = "y"         # Simbolo de la magnitud (x, θ, x', θ')
@export var unit: String = ""
@export var line_color: Color = Color(0.0, 0.45, 0.85)
@export var ref_color: Color = Color(0.1, 0.6, 0.25)
@export var linear_color: Color = Color(0.08, 0.08, 0.08)
@export var window_seconds: float = 5.0      # Tiempo visible en el eje horizontal
@export var auto_scale: bool = true
@export var y_min: float = -1.0
@export var y_max: float = 1.0
@export var show_extremes: bool = true       # Puntos en el maximo y el minimo

# Lineas horizontales de limite (p. ej. saturacion ±u_max), en rojo punteado
var limites := PackedFloat64Array()
var limite_nombre: String = ""
const COLOR_LIMITE := Color(0.85, 0.15, 0.15, 0.8)

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
const MARGEN_DER: float = 12.0
const MARGEN_SUP: float = 34.0
const MARGEN_INF: float = 28.0
const COLOR_FONDO := Color(1.0, 1.0, 1.0)
const COLOR_BORDE := Color(0.55, 0.58, 0.62)
const COLOR_REJILLA := Color(0.0, 0.0, 0.0, 0.08)
const COLOR_CERO := Color(0.0, 0.0, 0.0, 0.35)
const COLOR_TEXTO := Color(0.12, 0.13, 0.15)
const COLOR_TEXTO_EJE := Color(0.3, 0.32, 0.36)
const COLOR_MAXIMO := Color(0.8, 0.1, 0.1)
const COLOR_MINIMO := Color(0.1, 0.3, 0.8)

const GUION: float = 6.0     # Largo de cada trazo de la linea punteada [px]
const ESPACIO: float = 4.0   # Espacio entre trazos [px]


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
	var paso_y: float = _paso_bonito((rango_y.y - rango_y.x) / 5.0)
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

	# --- Limites horizontales (saturacion) ---
	for lim: float in limites:
		if lim < rango_y.x or lim > rango_y.y:
			continue
		var yl: float = _y_pantalla(lim, rango_y, area)
		_polilinea_punteada(PackedVector2Array([Vector2(area.position.x, yl), Vector2(area.end.x, yl)]),
			COLOR_LIMITE, 1.0, 3.0, 3.0)
		if limite_nombre != "":
			# A la derecha, para no encimarse con las etiquetas de maximo/minimo
			var txt_lim: String = "%s = %s %s" % [limite_nombre, String.num(lim, 1), unit]
			var w: float = font.get_string_size(txt_lim, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_ticks).x
			draw_string(font, Vector2(area.end.x - w - 3.0, yl + (-3.0 if lim > 0.0 else font_size_ticks + 1.0)),
				txt_lim, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_ticks, COLOR_LIMITE)

	# --- Series: referencia y no lineal continuas; lineal punteada encima ---
	for tramo: PackedVector2Array in _tramos(_refs, rango_y, area, t_ini):
		if tramo.size() >= 2:
			draw_polyline(tramo, ref_color, 1.5, true)
	for tramo: PackedVector2Array in _tramos(_values, rango_y, area, t_ini):
		if tramo.size() >= 2:
			draw_polyline(tramo, line_color, 2.0, true)
	for tramo: PackedVector2Array in _tramos(_lins, rango_y, area, t_ini):
		_polilinea_punteada(tramo, linear_color, 2.0)

	# --- Puntos en el maximo y el minimo de la serie principal ---
	if show_extremes:
		_dibujar_extremos(font, rango_y, area, t_ini)

	# --- Titulo y leyenda con el valor actual ---
	if show_title:
		draw_string(font, Vector2(8.0, 6.0 + font_size_title), title,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_title, COLOR_TEXTO)
	_dibujar_leyenda(font)


# Leyenda arriba a la derecha: muestra de linea + nombre + valor actual.
func _dibujar_leyenda(font: Font) -> void:
	if _values.is_empty():
		return
	var leyenda: Array = [[main_name, _values[-1], line_color, false]]
	if not is_nan(_lins[-1]):
		leyenda.append([linear_name, _lins[-1], linear_color, true])
	if not is_nan(_refs[-1]):
		leyenda.append([ref_name, _refs[-1], ref_color, false])

	var tam: int = font_size_ticks + 1
	var y_texto: float = 8.0 + tam
	var y_linea: float = y_texto - tam * 0.35
	var x_der: float = size.x - MARGEN_DER
	for i in range(leyenda.size() - 1, -1, -1):
		var item: Array = leyenda[i]
		var texto: String = "%s: %.2f %s" % [item[0], item[1], unit]
		var ancho: float = font.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x
		draw_string(font, Vector2(x_der - ancho, y_texto), texto,
			HORIZONTAL_ALIGNMENT_LEFT, -1, tam, COLOR_TEXTO)
		var a := Vector2(x_der - ancho - 22.0, y_linea)
		var b := Vector2(x_der - ancho - 4.0, y_linea)
		if item[3]:
			_polilinea_punteada(PackedVector2Array([a, b]), item[2], 2.0, 4.0, 2.5)
		else:
			draw_line(a, b, item[2], 2.0)
		x_der -= ancho + 32.0


# Punto y etiqueta en el maximo (rojo) y el minimo (azul) de la serie no lineal.
func _dibujar_extremos(font: Font, rango_y: Vector2, area: Rect2, t_ini: float) -> void:
	var i_max: int = -1
	var i_min: int = -1
	for i in range(_values.size()):
		if is_nan(_values[i]) or _t[i] < t_ini:
			continue
		if i_max == -1 or _values[i] > _values[i_max]:
			i_max = i
		if i_min == -1 or _values[i] < _values[i_min]:
			i_min = i
	if i_max == -1 or is_equal_approx(_values[i_max], _values[i_min]):
		return
	for extremo: Array in [[i_max, "máx", COLOR_MAXIMO, -1.0], [i_min, "mín", COLOR_MINIMO, 1.0]]:
		var i: int = extremo[0]
		var p := Vector2(
			area.position.x + (_t[i] - t_ini) / window_seconds * area.size.x,
			_y_pantalla(_values[i], rango_y, area))
		draw_circle(p, 4.5, Color.WHITE)
		draw_circle(p, 3.5, extremo[2])
		var texto: String = "%s %.2f %s (t=%.2f s)" % [extremo[1], _values[i], unit, _t[i]]
		var tam: int = font_size_ticks
		var dim: Vector2 = font.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tam)
		# Etiqueta arriba del maximo y abajo del minimo, sin salirse del area
		var x: float = clampf(p.x + 6.0, area.position.x + 2.0, area.end.x - dim.x - 2.0)
		var y: float = p.y + (extremo[3] * 8.0) + (0.0 if extremo[3] < 0.0 else tam)
		y = clampf(y, area.position.y + tam + 1.0, area.end.y - 3.0)
		draw_rect(Rect2(Vector2(x - 2.0, y - tam), Vector2(dim.x + 4.0, tam + 3.0)), Color(1, 1, 1, 0.85), true)
		draw_string(font, Vector2(x, y), texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, extremo[2])


# Linea punteada a lo largo de una polilinea; el patron continua entre segmentos.
func _polilinea_punteada(puntos: PackedVector2Array, color: Color, ancho: float,
		guion: float = GUION, espacio: float = ESPACIO) -> void:
	if puntos.size() < 2:
		return
	var periodo: float = guion + espacio
	var fase: float = 0.0   # distancia recorrida dentro del periodo actual
	for k in range(puntos.size() - 1):
		var a: Vector2 = puntos[k]
		var b: Vector2 = puntos[k + 1]
		var largo: float = a.distance_to(b)
		if largo <= 0.0:
			continue
		var dir: Vector2 = (b - a) / largo
		var s: float = 0.0
		while s < largo:
			var en_guion: bool = fase < guion
			var resta: float = (guion - fase) if en_guion else (periodo - fase)
			var paso: float = minf(resta, largo - s)
			if en_guion:
				draw_line(a + dir * s, a + dir * (s + paso), color, ancho, true)
			s += paso
			fase = fmod(fase + paso, periodo)


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
	# Los limites entran en la escala solo si la senal se les acerca (>= 40 %);
	# si no, la curva quedaria aplastada.
	var pico: float = maxf(absf(mn), absf(mx))
	for lim: float in limites:
		if pico >= 0.4 * absf(lim):
			mn = minf(mn, lim)
			mx = maxf(mx, lim)
	var span: float = mx - mn
	if span < 0.05:
		var mid: float = (mx + mn) * 0.5
		return Vector2(mid - 0.05, mid + 0.05)
	# Margen extra para que quepan las etiquetas de maximo y minimo
	return Vector2(mn - span * 0.15, mx + span * 0.15)


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

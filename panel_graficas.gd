class_name PanelGraficas
extends PanelContainer

# ============================================================
# PANEL DESPLEGABLE CON LAS GRAFICAS DEL ESTADO
# ============================================================
# Muestra una sola grafica a la vez; los botones ◀ ▶ cambian entre
# x, θ, x' y θ'. Todas siguen registrando datos aunque esten ocultas,
# asi que al cambiar de grafica no se pierde la historia.
#
# Uso:
#   var panel := PanelGraficas.new()
#   canvas_layer.add_child(panel)
#   panel.position = ...; panel.size = ...
#   boton.pressed.connect(panel.alternar)
#   panel.agregar_muestra(t, estado, estado_lineal)   # cada paso

const IDX_X: int = 0
const IDX_THETA: int = 1
const IDX_DX: int = 2
const IDX_DTHETA: int = 3

var graficas: Array[RealTimePlot] = []
var actual: int = 0

var _lbl_titulo: Label


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP

	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.05, 0.06, 0.08, 0.94)
	estilo.border_color = Color(0.35, 0.4, 0.5, 0.9)
	estilo.set_border_width_all(1)
	estilo.set_corner_radius_all(4)
	estilo.set_content_margin_all(5)
	add_theme_stylebox_override("panel", estilo)

	var caja := VBoxContainer.new()
	caja.add_theme_constant_override("separation", 4)
	add_child(caja)

	# Barra de navegacion: ◀  "1/4  Posición del carro"  ▶
	var barra := HBoxContainer.new()
	barra.add_theme_constant_override("separation", 6)
	caja.add_child(barra)

	var btn_ant := _boton("◀", "Gráfica anterior")
	btn_ant.pressed.connect(func() -> void: mostrar(actual - 1))
	barra.add_child(btn_ant)

	_lbl_titulo = Label.new()
	_lbl_titulo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_titulo.add_theme_font_size_override("font_size", 11)
	barra.add_child(_lbl_titulo)

	var btn_sig := _boton("▶", "Gráfica siguiente")
	btn_sig.pressed.connect(func() -> void: mostrar(actual + 1))
	barra.add_child(btn_sig)

	# Las cuatro graficas (solo una visible)
	var defs: Array = [
		["Posición del carro", "x", "m", Color(0.25, 0.85, 1.0)],
		["Ángulo del péndulo", "θ", "°", Color(1.0, 0.75, 0.2)],
		["Velocidad del carro", "x'", "m/s", Color(0.75, 0.45, 1.0)],
		["Velocidad angular del péndulo", "θ'", "°/s", Color(1.0, 0.35, 0.45)],
	]
	for d: Array in defs:
		var g := RealTimePlot.new()
		g.title = d[0]
		g.show_title = false
		g.axis_label = d[1]
		g.unit = d[2]
		g.line_color = d[3]
		g.size_flags_vertical = Control.SIZE_EXPAND_FILL
		g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		caja.add_child(g)
		graficas.append(g)

	mostrar(0)


func _boton(texto: String, ayuda: String) -> Button:
	var b := Button.new()
	b.text = texto
	b.tooltip_text = ayuda
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(28.0, 0.0)
	b.add_theme_font_size_override("font_size", 11)
	return b


func mostrar(indice: int) -> void:
	actual = posmod(indice, graficas.size())
	for i in range(graficas.size()):
		graficas[i].visible = i == actual
	_lbl_titulo.text = "%d / %d   %s" % [actual + 1, graficas.size(), graficas[actual].title]


func alternar() -> void:
	visible = not visible


# Escala vertical fija para una grafica (auto_scale = false).
func fijar_rango(indice: int, minimo: float, maximo: float) -> void:
	graficas[indice].auto_scale = false
	graficas[indice].y_min = minimo
	graficas[indice].y_max = maximo


# Registra el estado X = [x, θ, x', θ'] (SI) en las cuatro graficas.
# Los angulos se muestran en grados. 'lineal' y 'ref_x' son opcionales (NAN).
func agregar_muestra(t: float, estado: Vector4, lineal: Vector4 = Vector4(NAN, NAN, NAN, NAN),
		ref_x: float = NAN) -> void:
	graficas[IDX_X].add_sample(t, estado.x, ref_x, lineal.x)
	graficas[IDX_THETA].add_sample(t, rad_to_deg(estado.y), NAN, rad_to_deg(lineal.y))
	graficas[IDX_DX].add_sample(t, estado.z, NAN, lineal.z)
	graficas[IDX_DTHETA].add_sample(t, rad_to_deg(estado.w), NAN, rad_to_deg(lineal.w))


func limpiar() -> void:
	for g: RealTimePlot in graficas:
		g.clear()


# Eje de tiempo fijo en [0, segundos], como plot(t, ...) en MATLAB.
func fijar_duracion(segundos: float) -> void:
	for g: RealTimePlot in graficas:
		g.window_seconds = maxf(segundos, 0.1)
		g.queue_redraw()

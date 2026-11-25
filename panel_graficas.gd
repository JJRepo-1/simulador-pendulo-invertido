class_name PanelGraficas
extends PanelContainer

# ============================================================
# PANEL DESPLEGABLE CON LAS GRAFICAS Y LOS RESULTADOS
# ============================================================
# Muestra una pagina a la vez; los botones ◀ ▶ cambian entre:
#   x, θ, x', θ'  (siempre)
#   u, e          (si la escena las agrega con agregar_grafica)
#   Resultados    (metricas calculadas al terminar la simulacion)
# Todas las graficas siguen registrando datos aunque esten ocultas.
#
# "Exportar CSV" guarda el RegistroSimulacion de la escena con sus
# metadatos (parametros, ganancias, polos, condiciones) y las metricas.
#
# Uso:
#   var panel := PanelGraficas.new()
#   canvas_layer.add_child(panel)
#   panel.position = PanelGraficas.RECT.position; panel.size = PanelGraficas.RECT.size
#   panel.registro = registro;  panel.metadatos = func() -> PackedStringArray: ...
#   panel.agregar_muestra(t, estado, estado_lineal)   # cada cuadro
#   panel.mostrar_resultados(secciones)               # al terminar

const IDX_X: int = 0
const IDX_THETA: int = 1
const IDX_DX: int = 2
const IDX_DTHETA: int = 3

# Zona de pantalla del panel (coordenadas de la ventana 720x380): casi
# cuadrada, a la derecha de los controles. No tapa el boton Simular, ni los
# textos de la esquina superior derecha, ni el boton Salir.
const RECT := Rect2(148.0, 12.0, 384.0, 344.0)

const COLOR_TEXTO := Color(0.12, 0.13, 0.15)

var graficas: Array[RealTimePlot] = []
var actual: int = 0

# Datos de la simulacion para exportar (los asigna la escena)
var registro: RegistroSimulacion = null
var metadatos: Callable = Callable()        # () -> PackedStringArray
var nombre_escena: String = "simulacion"

var _secciones: Array = []                   # metricas de la ultima simulacion
var _caja: VBoxContainer
var _lbl_titulo: Label
var _lbl_estado: Label
var _pagina_resultados: PanelContainer
var _txt_resultados: RichTextLabel
var _dialogo: FileDialog


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP

	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.93, 0.94, 0.95)
	estilo.border_color = Color(0.55, 0.58, 0.62)
	estilo.set_border_width_all(1)
	estilo.set_corner_radius_all(4)
	estilo.set_content_margin_all(5)
	add_theme_stylebox_override("panel", estilo)

	_caja = VBoxContainer.new()
	_caja.add_theme_constant_override("separation", 4)
	add_child(_caja)

	# Barra de navegacion: ◀  "1/7  Posición del carro"  ▶  [Exportar CSV]
	var barra := HBoxContainer.new()
	barra.add_theme_constant_override("separation", 6)
	_caja.add_child(barra)

	var btn_ant := _boton("◀", "Página anterior")
	btn_ant.pressed.connect(func() -> void: mostrar(actual - 1))
	barra.add_child(btn_ant)

	_lbl_titulo = Label.new()
	_lbl_titulo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_titulo.add_theme_font_size_override("font_size", 11)
	_lbl_titulo.add_theme_color_override("font_color", COLOR_TEXTO)
	_lbl_titulo.clip_text = true
	barra.add_child(_lbl_titulo)

	var btn_sig := _boton("▶", "Página siguiente")
	btn_sig.pressed.connect(func() -> void: mostrar(actual + 1))
	barra.add_child(btn_sig)

	var btn_csv := _boton("Exportar CSV", "Guardar los datos de la simulación (t, estados, modelo lineal, u, r) y los resultados")
	btn_csv.pressed.connect(_on_exportar)
	barra.add_child(btn_csv)

	# Las cuatro graficas del estado. Colores oscuros para el fondo blanco;
	# el modelo lineal siempre va en negro punteado.
	agregar_grafica("Posición del carro", "x", "m", Color(0.0, 0.45, 0.85))
	agregar_grafica("Ángulo del péndulo", "θ", "°", Color(0.9, 0.45, 0.0))
	agregar_grafica("Velocidad del carro", "x'", "m/s", Color(0.5, 0.2, 0.75))
	agregar_grafica("Velocidad angular del péndulo", "θ'", "°/s", Color(0.8, 0.1, 0.3))

	# Pagina de resultados (al final)
	_pagina_resultados = PanelContainer.new()
	var fondo := StyleBoxFlat.new()
	fondo.bg_color = Color.WHITE
	fondo.border_color = Color(0.55, 0.58, 0.62)
	fondo.set_border_width_all(1)
	fondo.set_content_margin_all(8)
	_pagina_resultados.add_theme_stylebox_override("panel", fondo)
	_pagina_resultados.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_txt_resultados = RichTextLabel.new()
	_txt_resultados.bbcode_enabled = true
	_txt_resultados.selection_enabled = true
	_txt_resultados.add_theme_color_override("default_color", Color(0.25, 0.27, 0.3))
	_txt_resultados.add_theme_font_size_override("normal_font_size", 9)
	_txt_resultados.add_theme_font_size_override("bold_font_size", 10)
	_txt_resultados.add_theme_constant_override("table_h_separation", 6)
	_pagina_resultados.add_child(_txt_resultados)
	_caja.add_child(_pagina_resultados)
	_txt_resultados.text = "Los resultados aparecen al terminar la simulación."

	_lbl_estado = Label.new()
	_lbl_estado.add_theme_font_size_override("font_size", 9)
	_lbl_estado.add_theme_color_override("font_color", Color(0.1, 0.45, 0.2))
	_lbl_estado.clip_text = true
	_lbl_estado.visible = false
	_caja.add_child(_lbl_estado)

	_dialogo = FileDialog.new()
	_dialogo.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_dialogo.access = FileDialog.ACCESS_FILESYSTEM
	_dialogo.use_native_dialog = true
	_dialogo.title = "Exportar datos de la simulación"
	_dialogo.filters = PackedStringArray(["*.csv ; Valores separados por comas"])
	_dialogo.file_selected.connect(exportar_csv)
	add_child(_dialogo)

	mostrar(0)


func _boton(texto: String, ayuda: String) -> Button:
	var b := Button.new()
	b.text = texto
	b.tooltip_text = ayuda
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(28.0, 0.0)
	b.add_theme_font_size_override("font_size", 11)
	return b


# Agrega una grafica antes de la pagina de resultados. Devuelve su indice.
func agregar_grafica(titulo: String, simbolo: String, unidad: String, color: Color) -> int:
	var g := RealTimePlot.new()
	g.title = titulo
	g.show_title = false
	g.axis_label = simbolo
	g.unit = unidad
	g.line_color = color
	g.size_flags_vertical = Control.SIZE_EXPAND_FILL
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_caja.add_child(g)
	if _pagina_resultados:
		_caja.move_child(g, _pagina_resultados.get_index())
	graficas.append(g)
	if _lbl_titulo:
		mostrar(actual)
	return graficas.size() - 1


func _num_paginas() -> int:
	return graficas.size() + 1


func mostrar(indice: int) -> void:
	actual = posmod(indice, _num_paginas())
	for i in range(graficas.size()):
		graficas[i].visible = i == actual
	if _pagina_resultados:
		_pagina_resultados.visible = actual == graficas.size()
	var nombre: String = "Resultados" if actual == graficas.size() else graficas[actual].title
	_lbl_titulo.text = "%d / %d   %s" % [actual + 1, _num_paginas(), nombre]


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
	_secciones = []
	_txt_resultados.text = "Simulación en curso… los resultados aparecen al terminar."
	_lbl_estado.visible = false


# Eje de tiempo fijo en [0, segundos], como plot(t, ...) en MATLAB.
func fijar_duracion(segundos: float) -> void:
	for g: RealTimePlot in graficas:
		g.window_seconds = maxf(segundos, 0.1)
		g.queue_redraw()


# Metricas de MetricasSimulacion.calcular() al terminar la simulacion.
func mostrar_resultados(secciones: Array) -> void:
	_secciones = secciones
	_txt_resultados.text = MetricasSimulacion.a_bbcode(secciones)


# ------------------------------------------------------------
# Exportacion
# ------------------------------------------------------------

func _on_exportar() -> void:
	if registro == null or registro.tamano() < 2:
		_estado("Primero ejecuta una simulación.", false)
		return
	var fecha: String = Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	_dialogo.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	_dialogo.current_file = "%s_%s.csv" % [nombre_escena, fecha]
	_dialogo.popup_centered_ratio(0.6)


# Escribe el CSV en 'ruta' (tambien se puede llamar directamente).
func exportar_csv(ruta: String) -> Error:
	if not ruta.to_lower().ends_with(".csv"):
		ruta += ".csv"
	var lineas := PackedStringArray()
	lineas.append("Simulador de Péndulo Invertido v%s - %s" % [
		ProjectSettings.get_setting("application/config/version", ""), nombre_escena])
	lineas.append("Exportado: " + Time.get_datetime_string_from_system(false, true))
	if metadatos.is_valid():
		lineas.append_array(metadatos.call())
	if not _secciones.is_empty():
		lineas.append_array(MetricasSimulacion.a_lineas(_secciones))
	var err: Error = registro.exportar_csv(ruta, lineas)
	if err == OK:
		_estado("Exportado: " + ruta.get_file(), true)
	else:
		_estado("No se pudo guardar el archivo (%s)." % error_string(err), false)
	return err


func _estado(texto: String, ok: bool) -> void:
	_lbl_estado.text = texto
	_lbl_estado.add_theme_color_override("font_color", Color(0.1, 0.45, 0.2) if ok else Color(0.75, 0.1, 0.1))
	_lbl_estado.visible = true

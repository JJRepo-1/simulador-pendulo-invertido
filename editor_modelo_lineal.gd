class_name EditorModeloLineal
extends VBoxContainer

# ============================================================
# EDITOR DE LOS MODELOS (pantalla de Configuracion)
# ============================================================
# Pestana 1 - Modelo no lineal: el estudiante escribe las dos ecuaciones
#   de movimiento (dinamica del carro y del pendulo) con '='. La simulacion
#   despeja x'' y θ'' de esas ecuaciones. Se comparan contra el modelo de
#   referencia ideal y con friccion (modelo_pendulo.gd).
#
# Pestana 2 - Modelo lineal: A y B como formulas de los parametros.
#   Cada celda se compara contra la linealizacion numerica (jacobiano)
#   del modelo no lineal del estudiante:
#     verde   = coincide
#     naranja = se evalua, pero no coincide
#     rojo    = la formula tiene un error

const COLOR_OK := Color(0.45, 0.9, 0.5)
const COLOR_DIFERENTE := Color(1.0, 0.7, 0.25)
const COLOR_ERROR := Color(1.0, 0.4, 0.4)
const COLOR_TEXTO := Color(0.85, 0.87, 0.9)

const NOMBRES_ESTADO: Array[String] = ["x", "θ", "x'", "θ'"]
const NOMBRES_FILA: Array[String] = ["x'", "θ'", "x''", "θ''"]

const FUENTE: int = 12

var _parametros: Dictionary = {}
var _jacobiano: Dictionary = {}
var _origen_jacobiano: String = ""   # "usuario" o "referencia"
var _error_parametros: String = ""
var _resultado: Dictionary = {}
var _resultado_nl: Dictionary = {}

var _celdas: Array[LineEdit] = []   # 0..15 = A por filas, 16..19 = B
var _celda_activa: int = -1

# Pestana no lineal
var _txt_carro: LineEdit
var _txt_pendulo: LineEdit
var _lbl_errores_nl: Label
var _lbl_masas: Label
var _lbl_resumen_nl: Label

# Pestana lineal
var _txt_aux: TextEdit
var _lbl_errores_aux: Label
var _chk_esperados: CheckBox
var _lbl_detalle: Label
var _lbl_resumen: Label

# Pestana 3: sistema aumentado con accion integral (pendulo3)
var aumentado: EditorAumentado


func _ready() -> void:
	_construir_interfaz()


# ------------------------------------------------------------
# API usada por configuracion.gd
# ------------------------------------------------------------

func cargar(aux: String, formulas_A: PackedStringArray, formulas_B: PackedStringArray) -> void:
	_txt_aux.text = aux
	for k in range(16):
		_celdas[k].text = formulas_A[k] if k < formulas_A.size() else ""
	for k in range(4):
		_celdas[16 + k].text = formulas_B[k] if k < formulas_B.size() else ""
	_reevaluar()


func cargar_no_lineal(ecuacion_carro: String, ecuacion_pendulo: String) -> void:
	_txt_carro.text = ecuacion_carro
	_txt_pendulo.text = ecuacion_pendulo
	_reevaluar()


func actualizar_parametros(p: Dictionary) -> void:
	_parametros = p
	_error_parametros = PenduloModelo.desde_parametros(p).validar()
	_reevaluar()


func obtener_aux() -> String:
	return _txt_aux.text


func obtener_A() -> PackedStringArray:
	var A := PackedStringArray()
	for k in range(16):
		A.append(_celdas[k].text.strip_edges())
	return A


func obtener_B() -> PackedStringArray:
	var B := PackedStringArray()
	for k in range(4):
		B.append(_celdas[16 + k].text.strip_edges())
	return B


func obtener_ecuacion_carro() -> String:
	return _txt_carro.text.strip_edges()


func obtener_ecuacion_pendulo() -> String:
	return _txt_pendulo.text.strip_edges()


func tiene_errores() -> bool:
	return _resultado.is_empty() or not _resultado.ok


# A y B numericas de la pestaña 2 ({} si tienen errores), para el calculo de K.
func matrices_lineales() -> Dictionary:
	if tiene_errores():
		return {}
	return {"A": _resultado.A, "B": _resultado.B}


func tiene_errores_no_lineal() -> bool:
	return _resultado_nl.is_empty() or not _resultado_nl.ok


# ------------------------------------------------------------
# Construccion de la interfaz
# ------------------------------------------------------------

func _construir_interfaz() -> void:
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_font_size_override("font_size", 13)
	add_child(tabs)

	var tab_nl := _crear_tab(tabs)
	tabs.set_tab_title(0, "1. Modelo no lineal")
	_construir_tab_no_lineal(tab_nl)

	var tab_lin := _crear_tab(tabs)
	tabs.set_tab_title(1, "2. Modelo lineal (A, B)")
	_construir_tab_lineal(tab_lin)

	var tab_aum := _crear_tab(tabs)
	tabs.set_tab_title(2, "3. Seguimiento (Aa, Ba, Ka)")
	aumentado = EditorAumentado.new()
	aumentado.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_aum.add_child(aumentado)


func _crear_tab(tabs: TabContainer) -> VBoxContainer:
	var margen := MarginContainer.new()
	for lado: String in ["left", "right", "top", "bottom"]:
		margen.add_theme_constant_override("margin_" + lado, 8)
	tabs.add_child(margen)
	var caja := VBoxContainer.new()
	caja.add_theme_constant_override("separation", 6)
	margen.add_child(caja)
	return caja


func _construir_tab_no_lineal(caja: VBoxContainer) -> void:
	caja.add_child(_etiqueta("Modelo no lineal: ecuaciones de movimiento", 16))

	var ayuda := _etiqueta(
		"Escribe cada ecuación con '='. Estado: x, θ (o theta), velocidades x', θ', "
		+ "aceleraciones x'', θ''. Entrada: u (fuerza). Parámetros: M, m, l, J, g, "
		+ "c (fricción del carro), b (fricción del pivote). Funciones: sen, cos, tan, sqrt... "
		+ "(senθ y cosθ se pueden escribir sin paréntesis). θ = 0 es el péndulo hacia arriba. "
		+ "Para incluir fricción suma  + c*x'  en la del carro y  + b*θ'  en la del péndulo.", 11)
	ayuda.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ayuda.modulate = Color(1, 1, 1, 0.75)
	caja.add_child(ayuda)

	caja.add_child(_etiqueta("1. Dinámica del carro", 13))
	_txt_carro = _fila_ecuacion(caja, FormulasLineales.EJEMPLO_CARRO)
	caja.add_child(_etiqueta("2. Dinámica del péndulo", 13))
	_txt_pendulo = _fila_ecuacion(caja, FormulasLineales.EJEMPLO_PENDULO)

	_lbl_errores_nl = _etiqueta("", 11)
	_lbl_errores_nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_errores_nl.add_theme_color_override("font_color", COLOR_ERROR)
	caja.add_child(_lbl_errores_nl)

	_lbl_masas = _etiqueta("", 11)
	_lbl_masas.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_masas.modulate = Color(1, 1, 1, 0.8)
	caja.add_child(_lbl_masas)

	_lbl_resumen_nl = _etiqueta("", 13)
	_lbl_resumen_nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caja.add_child(_lbl_resumen_nl)

	var botones := HBoxContainer.new()
	botones.add_theme_constant_override("separation", 8)
	caja.add_child(botones)

	var btn_ideal := Button.new()
	btn_ideal.text = "Cargar sistema ideal"
	btn_ideal.pressed.connect(func() -> void:
		cargar_no_lineal(FormulasLineales.EJEMPLO_CARRO, FormulasLineales.EJEMPLO_PENDULO))
	botones.add_child(btn_ideal)

	var btn_friccion := Button.new()
	btn_friccion.text = "Cargar con fricción"
	btn_friccion.pressed.connect(func() -> void:
		cargar_no_lineal(FormulasLineales.EJEMPLO_CARRO_FRICCION,
			FormulasLineales.EJEMPLO_PENDULO_FRICCION))
	botones.add_child(btn_friccion)

	var btn_limpiar := Button.new()
	btn_limpiar.text = "Limpiar ecuaciones"
	btn_limpiar.pressed.connect(func() -> void: cargar_no_lineal("", ""))
	botones.add_child(btn_limpiar)


# Fila con el campo de la ecuacion y botones para insertar simbolos
# que no estan en el teclado.
func _fila_ecuacion(caja: VBoxContainer, ejemplo: String) -> LineEdit:
	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 4)
	caja.add_child(fila)
	var campo := LineEdit.new()
	campo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	campo.add_theme_font_size_override("font_size", 14)
	campo.placeholder_text = ejemplo
	campo.text_changed.connect(func(_t: String) -> void: _reevaluar())
	fila.add_child(campo)
	for simbolo: String in ["θ", "θ'", "θ''"]:
		var btn := Button.new()
		btn.text = simbolo
		btn.focus_mode = Control.FOCUS_NONE
		btn.tooltip_text = "Insertar " + simbolo
		btn.add_theme_font_size_override("font_size", FUENTE)
		btn.pressed.connect(func() -> void:
			campo.insert_text_at_caret(simbolo)
			campo.grab_focus()
			_reevaluar())
		fila.add_child(btn)
	return campo


func _construir_tab_lineal(caja: VBoxContainer) -> void:
	caja.add_child(_etiqueta("Modelo lineal:  dX/dt = A·X + B·u,   X = [x, θ, x', θ']", 16))

	var ayuda := _etiqueta(
		"Variables: M (carro), m (péndulo), l, J, g, c (fricción del carro), b (fricción del pivote) "
		+ "y las auxiliares que definas. Operadores + - * / ^ ( ). Funciones: sin, cos, tan, sqrt, "
		+ "exp, log, abs, pow, min, max. Constante: pi. Celda vacía = 0.", 11)
	ayuda.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ayuda.modulate = Color(1, 1, 1, 0.75)
	caja.add_child(ayuda)

	caja.add_child(_etiqueta("Variables auxiliares constantes (ej.  Delta = (M + m)*J + M*m*l^2):", FUENTE))

	_txt_aux = TextEdit.new()
	_txt_aux.custom_minimum_size = Vector2(0, 52)
	_txt_aux.add_theme_font_size_override("font_size", FUENTE)
	_txt_aux.placeholder_text = "Delta = (M + m)*J + M*m*l^2"
	_txt_aux.text_changed.connect(_reevaluar)
	caja.add_child(_txt_aux)

	_lbl_errores_aux = _etiqueta("", 11)
	_lbl_errores_aux.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_errores_aux.add_theme_color_override("font_color", COLOR_ERROR)
	_lbl_errores_aux.visible = false
	caja.add_child(_lbl_errores_aux)

	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 4)
	caja.add_child(grid)

	# Encabezados de columna
	grid.add_child(_etiqueta("", FUENTE))
	for nombre: String in NOMBRES_ESTADO:
		var e := _etiqueta("A: " + nombre, FUENTE)
		e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(e)
	var eb := _etiqueta("B: u", FUENTE)
	eb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	grid.add_child(eb)

	_celdas.resize(20)
	for i in range(4):
		grid.add_child(_etiqueta(NOMBRES_FILA[i], FUENTE))
		for j in range(4):
			var k: int = i * 4 + j
			_celdas[k] = _crear_celda(k)
			grid.add_child(_celdas[k])
		_celdas[16 + i] = _crear_celda(16 + i)
		grid.add_child(_celdas[16 + i])

	_chk_esperados = CheckBox.new()
	_chk_esperados.text = "Mostrar el valor esperado (linealización numérica)"
	_chk_esperados.add_theme_font_size_override("font_size", FUENTE)
	_chk_esperados.toggled.connect(func(_v: bool) -> void: _actualizar_detalle())
	caja.add_child(_chk_esperados)

	_lbl_detalle = _etiqueta("Selecciona una celda para ver su valor.", FUENTE)
	_lbl_detalle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_detalle.custom_minimum_size = Vector2(0, 70)
	caja.add_child(_lbl_detalle)

	_lbl_resumen = _etiqueta("", 13)
	_lbl_resumen.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caja.add_child(_lbl_resumen)

	var botones := HBoxContainer.new()
	botones.add_theme_constant_override("separation", 8)
	caja.add_child(botones)

	var btn_ejemplo := Button.new()
	btn_ejemplo.text = "Cargar sistema ideal"
	btn_ejemplo.pressed.connect(func() -> void:
		cargar(FormulasLineales.EJEMPLO_AUX,
			PackedStringArray(FormulasLineales.EJEMPLO_A),
			PackedStringArray(FormulasLineales.EJEMPLO_B)))
	botones.add_child(btn_ejemplo)

	var btn_friccion := Button.new()
	btn_friccion.text = "Cargar con fricción"
	btn_friccion.pressed.connect(func() -> void:
		cargar(FormulasLineales.EJEMPLO_AUX,
			PackedStringArray(FormulasLineales.EJEMPLO_A_FRICCION),
			PackedStringArray(FormulasLineales.EJEMPLO_B)))
	botones.add_child(btn_friccion)

	var btn_limpiar := Button.new()
	btn_limpiar.text = "Limpiar A y B"
	btn_limpiar.pressed.connect(_on_limpiar)
	botones.add_child(btn_limpiar)


func _etiqueta(texto: String, tam: int) -> Label:
	var e := Label.new()
	e.text = texto
	e.add_theme_font_size_override("font_size", tam)
	return e


func _crear_celda(k: int) -> LineEdit:
	var celda := LineEdit.new()
	celda.custom_minimum_size = Vector2(98, 0)
	celda.placeholder_text = "0"
	celda.add_theme_font_size_override("font_size", FUENTE)
	celda.text_changed.connect(func(_t: String) -> void: _reevaluar())
	celda.focus_entered.connect(func() -> void:
		_celda_activa = k
		_actualizar_detalle())
	return celda


# ------------------------------------------------------------
# Evaluacion y comparacion
# ------------------------------------------------------------

func _reevaluar() -> void:
	if _celdas.is_empty() or _parametros.is_empty():
		return
	_reevaluar_no_lineal()
	_reevaluar_lineal()
	aumentado.actualizar(_parametros, _txt_aux.text, _error_parametros, _jacobiano)


# Construye el modelo no lineal del estudiante, lo compara con el de
# referencia y fija la linealizacion contra la que se revisan A y B.
func _reevaluar_no_lineal() -> void:
	_resultado_nl = ModeloFormulas.construir(_parametros, _txt_carro.text, _txt_pendulo.text)

	var errores := PackedStringArray()
	if _resultado_nl.error_carro != "":
		errores.append("Carro: " + _resultado_nl.error_carro)
	if _resultado_nl.error_pendulo != "":
		errores.append("Péndulo: " + _resultado_nl.error_pendulo)
	if _resultado_nl.error_sistema != "":
		errores.append(_resultado_nl.error_sistema)
	_lbl_errores_nl.text = "\n".join(errores)
	_lbl_errores_nl.visible = not errores.is_empty()

	_txt_carro.add_theme_color_override("font_color",
		COLOR_ERROR if _resultado_nl.error_carro != "" else COLOR_TEXTO)
	_txt_pendulo.add_theme_color_override("font_color",
		COLOR_ERROR if _resultado_nl.error_pendulo != "" else COLOR_TEXTO)

	_jacobiano = {}
	_origen_jacobiano = ""
	_lbl_masas.text = ""

	if _error_parametros != "":
		_resumen_nl("Parámetros inválidos: " + _error_parametros, COLOR_ERROR)
		return

	var referencia := PenduloModelo.desde_parametros(_parametros)

	if not _resultado_nl.ok:
		_resumen_nl("Tus ecuaciones tienen errores. La simulación usará el modelo de referencia "
			+ "hasta que las corrijas.", COLOR_ERROR)
		_jacobiano = referencia.jacobiano()
		_origen_jacobiano = "referencia"
		return

	var usuario: ModeloFormulas = _resultado_nl.modelo
	var jac_usuario: Dictionary = usuario.jacobiano()
	if usuario.error_ejecucion != "":
		_resumen_nl("Tus ecuaciones fallan en el equilibrio: " + usuario.error_ejecucion, COLOR_ERROR)
		_jacobiano = referencia.jacobiano()
		_origen_jacobiano = "referencia"
		return

	_jacobiano = jac_usuario
	_origen_jacobiano = "usuario"

	# Matriz de masas que se desprende de las ecuaciones, en el equilibrio
	var co: Dictionary = usuario.coeficientes(0.0, 0.0, 0.0, 0.0, 0.0)
	_lbl_masas.text = ("Matriz de masas en θ = 0:  [ %s   %s ;  %s   %s ]     determinante = %s"
		% [_num(co.a11), _num(co.a12), _num(co.a21), _num(co.a22), _num(co.det)])

	# Comparacion contra el modelo de referencia: ideal (c = b = 0) y con friccion
	var p_ideal: Dictionary = _parametros.duplicate()
	p_ideal.c = 0.0
	p_ideal.b = 0.0
	var dif_ideal: Dictionary = _diferencia(usuario, PenduloModelo.desde_parametros(p_ideal))
	if usuario.error_ejecucion != "":
		_resumen_nl("Tus ecuaciones fallan lejos del equilibrio: " + usuario.error_ejecucion, COLOR_ERROR)
		return
	var dif_friccion: Dictionary = _diferencia(usuario, referencia)
	var hay_friccion: bool = referencia.c > 0.0 or referencia.b > 0.0

	if dif_ideal.max < 1e-6:
		var nota: String = ""
		if hay_friccion:
			nota = " Los coeficientes c y b de la izquierda no se usan porque las ecuaciones no los incluyen."
		_resumen_nl("Correcto: tus ecuaciones son las del sistema ideal (sin fricción). "
			+ "La simulación usará tus ecuaciones." + nota, COLOR_OK)
	elif hay_friccion and dif_friccion.max < 1e-6:
		_resumen_nl("Correcto: tus ecuaciones son las del sistema con fricción viscosa "
			+ "(c = %s, b = %s). La simulación usará tus ecuaciones." % [
				_num(referencia.c), _num(referencia.b)], COLOR_OK)
	else:
		var peor: Array = dif_ideal.punto
		_resumen_nl("Tus ecuaciones se pueden simular, pero difieren del modelo de referencia "
			+ "(p. ej. en θ = %.0f°, x' = %.1f, θ' = %.1f, u = %.0f). La simulación usará TUS ecuaciones; "
			% [rad_to_deg(peor[1]), peor[2], peor[3], peor[4]]
			+ "A y B se comparan contra su linealización.", COLOR_DIFERENTE)


# Maxima diferencia relativa de las aceleraciones en los estados de prueba.
# Devuelve {"max": float, "punto": Array}.
func _diferencia(usuario: ModeloFormulas, referencia: PenduloModelo) -> Dictionary:
	var max_dif: float = 0.0
	var peor: Array = ModeloFormulas.PUNTOS_PRUEBA[0]
	for punto: Array in ModeloFormulas.PUNTOS_PRUEBA:
		var a_u: PackedFloat64Array = usuario.aceleraciones_estado(
			punto[0], punto[1], punto[2], punto[3], punto[4])
		var a_r: PackedFloat64Array = referencia.aceleraciones(punto[1], punto[2], punto[3], punto[4])
		if usuario.error_ejecucion != "":
			return {"max": INF, "punto": punto}
		for k in range(2):
			var dif: float = absf(a_u[k] - a_r[k]) / (1.0 + absf(a_r[k]))
			if dif > max_dif:
				max_dif = dif
				peor = punto
	return {"max": max_dif, "punto": peor}


func _num(v: float) -> String:
	return String.num(v, 4)


func _resumen_nl(texto: String, color: Color) -> void:
	_lbl_resumen_nl.text = texto
	_lbl_resumen_nl.add_theme_color_override("font_color", color)


func _reevaluar_lineal() -> void:
	_resultado = FormulasLineales.evaluar_modelo(
		_txt_aux.text, obtener_A(), obtener_B(), _parametros)

	var errores_aux: PackedStringArray = _resultado.errores_aux
	_lbl_errores_aux.visible = not errores_aux.is_empty()
	_lbl_errores_aux.text = "\n".join(errores_aux)

	var correctas_A: int = 0
	var correctas_B: int = 0
	var con_error: int = 0

	for k in range(20):
		var estado: String = _estado_celda(k)
		var color: Color = COLOR_TEXTO
		match estado:
			"ok":
				color = COLOR_OK
				if k < 16:
					correctas_A += 1
				else:
					correctas_B += 1
			"diferente":
				color = COLOR_DIFERENTE
			"error":
				color = COLOR_ERROR
				con_error += 1
		_celdas[k].add_theme_color_override("font_color", color)
		_celdas[k].tooltip_text = _celdas[k].text if _celdas[k].text != "" else "0"

	var origen: String = (" (referencia: linealización de tus ecuaciones no lineales)"
		if _origen_jacobiano == "usuario"
		else " (referencia: modelo de referencia, porque tus ecuaciones no lineales tienen errores)")

	if _error_parametros != "":
		_lbl_resumen.text = "Parámetros inválidos: " + _error_parametros
		_lbl_resumen.add_theme_color_override("font_color", COLOR_ERROR)
	elif con_error > 0 or not errores_aux.is_empty():
		_lbl_resumen.text = "A: %d/16 correctas · B: %d/4 correctas · %d celda(s) con error de escritura." % [
			correctas_A, correctas_B, con_error]
		_lbl_resumen.add_theme_color_override("font_color", COLOR_ERROR)
	elif correctas_A == 16 and correctas_B == 4:
		_lbl_resumen.text = "Correcto: A y B coinciden con la linealización en X = 0, u = 0" + origen + "."
		_lbl_resumen.add_theme_color_override("font_color", COLOR_OK)
	else:
		_lbl_resumen.text = "A: %d/16 correctas · B: %d/4 correctas. Las celdas en naranja no coinciden%s." % [
			correctas_A, correctas_B, origen]
		_lbl_resumen.add_theme_color_override("font_color", COLOR_DIFERENTE)

	_actualizar_detalle()


# "error", "ok", "diferente" o "sin_referencia"
func _estado_celda(k: int) -> String:
	if _error_celda(k) != "":
		return "error"
	if _jacobiano.is_empty():
		return "sin_referencia"
	return "ok" if _coincide(_valor_celda(k), _esperado_celda(k)) else "diferente"


func _valor_celda(k: int) -> float:
	return _resultado.A[k] if k < 16 else _resultado.B[k - 16]


func _esperado_celda(k: int) -> float:
	return _jacobiano.A[k] if k < 16 else _jacobiano.B[k - 16]


func _error_celda(k: int) -> String:
	return _resultado.errores_A[k] if k < 16 else _resultado.errores_B[k - 16]


func _coincide(valor: float, esperado: float) -> bool:
	return absf(valor - esperado) <= 1e-5 + 1e-4 * absf(esperado)


func _nombre_celda(k: int) -> String:
	if k < 16:
		var i: int = floori(k / 4.0)
		var j: int = k % 4
		return "A[%d,%d]  (fila %s, columna %s)" % [i + 1, j + 1, NOMBRES_FILA[i], NOMBRES_ESTADO[j]]
	var f: int = k - 16
	return "B[%d]  (fila %s)" % [f + 1, NOMBRES_FILA[f]]


func _actualizar_detalle() -> void:
	if _lbl_detalle == null:
		return
	if _celda_activa < 0 or _resultado.is_empty():
		_lbl_detalle.text = "Selecciona una celda para ver su valor."
		return

	var k: int = _celda_activa
	var formula: String = _celdas[k].text if _celdas[k].text.strip_edges() != "" else "0"
	var lineas: Array[String] = [_nombre_celda(k), "Fórmula: " + formula]

	var error: String = _error_celda(k)
	if error != "":
		lineas.append("Error: " + error)
	else:
		var texto_valor: String = "Valor: " + String.num(_valor_celda(k), 6)
		if _chk_esperados.button_pressed and not _jacobiano.is_empty():
			texto_valor += "     Esperado: " + String.num(_esperado_celda(k), 6)
		lineas.append(texto_valor)

		match _estado_celda(k):
			"ok":
				lineas.append("Coincide con la linealización.")
			"diferente":
				var pista: String = "No coincide con la linealización."
				var p := PenduloModelo.desde_parametros(_parametros)
				var col_vel: bool = k < 16 and floori(k / 4.0) >= 2 and k % 4 >= 2
				if col_vel and (p.c > 0.0 or p.b > 0.0):
					pista += " Pista: el modelo incluye fricción (c = %s, b = %s)." % [
						String.num(p.c, 4), String.num(p.b, 4)]
				lineas.append(pista)

	_lbl_detalle.text = "\n".join(lineas)


func _on_limpiar() -> void:
	for celda: LineEdit in _celdas:
		celda.text = ""
	_reevaluar()

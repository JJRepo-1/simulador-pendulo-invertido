class_name EditorAumentado
extends VBoxContainer

# ============================================================
# PESTANA 3: SISTEMA AUMENTADO CON ACCION INTEGRAL (pendulo3)
# ============================================================
# Equivale a codigo_seguimiento.m:
#   Xa = [x, θ, x', θ', z],   z' = r - x
#   dXa/dt = Aa*Xa + Ba*u + Br*r
#   Aa = [A, 0; -C, 0],  Ba = [B; 0],  Br = [0 0 0 0 1]',  C = [1 0 0 0]
#   u = -Ka*Xa,  Ka = [K, -ki]
#
# Cada celda de Aa y Ba se compara (verde/naranja/rojo) contra el sistema
# aumentado construido con la linealizacion del modelo no lineal.
# Ademas se muestran los polos de Aa - Ba*Ka (eig(Acl) en MATLAB).

# Boton "Calcular Ka con MATLAB" (lo atiende configuracion.gd)
signal calcular_con_matlab

const N: int = 5
const NOMBRES_ESTADO: Array[String] = ["x", "θ", "x'", "θ'", "z"]
const NOMBRES_FILA: Array[String] = ["x'", "θ'", "x''", "θ''", "z'"]
const FUENTE: int = 12

const COLOR_OK := Color(0.45, 0.9, 0.5)
const COLOR_DIFERENTE := Color(1.0, 0.7, 0.25)
const COLOR_ERROR := Color(1.0, 0.4, 0.4)
const COLOR_TEXTO := Color(0.85, 0.87, 0.9)

# Datos que entrega el editor principal
var _parametros: Dictionary = {}
var _aux: String = ""
var _error_parametros: String = ""
var _esperado_A := PackedFloat64Array()   # 25 valores, vacio si no hay referencia
var _esperado_B := PackedFloat64Array()   # 5 valores

var _resultado: Dictionary = {}
var _celdas: Array[LineEdit] = []   # 0..24 = Aa por filas, 25..29 = Ba
var _celda_activa: int = -1
var _spin_ka: Array[SpinBox] = []

var _chk_esperados: CheckBox
var _lbl_detalle: Label
var _lbl_resumen: Label
var _lbl_ki: Label
var _lbl_polos: Label


func _init() -> void:
	add_theme_constant_override("separation", 6)
	_construir()


# ------------------------------------------------------------
# API
# ------------------------------------------------------------

func cargar(formulas_A: PackedStringArray, formulas_B: PackedStringArray) -> void:
	for k in range(N * N):
		_celdas[k].text = formulas_A[k] if k < formulas_A.size() else ""
	for k in range(N):
		_celdas[N * N + k].text = formulas_B[k] if k < formulas_B.size() else ""
	_reevaluar()


func cargar_ganancias(Ka: PackedFloat64Array) -> void:
	for k in range(N):
		_spin_ka[k].value = Ka[k] if k < Ka.size() else 0.0
	_reevaluar()


# Llamado por el editor principal cada vez que cambian los parametros,
# las auxiliares (pestana 2) o la linealizacion del modelo no lineal.
# jac: {"A": 16, "B": 4} o {} si no hay referencia.
func actualizar(p: Dictionary, aux: String, error_parametros: String, jac: Dictionary) -> void:
	_parametros = p
	_aux = aux
	_error_parametros = error_parametros
	_esperado_A = PackedFloat64Array()
	_esperado_B = PackedFloat64Array()
	if not jac.is_empty():
		_esperado_A.resize(N * N)
		_esperado_B.resize(N)
		for i in range(4):
			for j in range(4):
				_esperado_A[i * N + j] = jac.A[i * 4 + j]
			_esperado_B[i] = jac.B[i]
		_esperado_A[4 * N + 0] = -1.0   # z' = r - x  ->  fila -C
	_reevaluar()


func obtener_A() -> PackedStringArray:
	var A := PackedStringArray()
	for k in range(N * N):
		A.append(_celdas[k].text.strip_edges())
	return A


func obtener_B() -> PackedStringArray:
	var B := PackedStringArray()
	for k in range(N):
		B.append(_celdas[N * N + k].text.strip_edges())
	return B


func obtener_ganancias() -> PackedFloat64Array:
	var Ka := PackedFloat64Array()
	for s: SpinBox in _spin_ka:
		Ka.append(s.value)
	return Ka


func tiene_errores() -> bool:
	return _resultado.is_empty() or not _resultado.ok


# Aa y Ba numericas ({} si tienen errores), para el calculo de Ka.
func matrices() -> Dictionary:
	if tiene_errores():
		return {}
	return {"A": _resultado.A, "B": _resultado.B}


# ------------------------------------------------------------
# Interfaz
# ------------------------------------------------------------

func _construir() -> void:
	add_child(_etiqueta("Sistema aumentado:  dXa/dt = Aa·Xa + Ba·u + Br·r", 16))

	var ayuda := _etiqueta(
		"Xa = [x, θ, x', θ', z], con z' = r − x (integral del error de posición). "
		+ "Aa = [A 0; −C 0], Ba = [B; 0], Br = [0 0 0 0 1]ᵀ, C = [1 0 0 0]. "
		+ "Usa las mismas variables y auxiliares (Delta) de la pestaña 2. "
		+ "Ley de control: u = −Ka·Xa, con Ka = [K, −ki].", 11)
	ayuda.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ayuda.modulate = Color(1, 1, 1, 0.75)
	add_child(ayuda)

	var grid := GridContainer.new()
	grid.columns = N + 2
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 4)
	add_child(grid)

	grid.add_child(_etiqueta("", FUENTE))
	for nombre: String in NOMBRES_ESTADO:
		var e := _etiqueta("Aa: " + nombre, FUENTE)
		e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(e)
	var eb := _etiqueta("Ba: u", FUENTE)
	eb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	grid.add_child(eb)

	_celdas.resize(N * N + N)
	for i in range(N):
		grid.add_child(_etiqueta(NOMBRES_FILA[i], FUENTE))
		for j in range(N):
			var k: int = i * N + j
			_celdas[k] = _crear_celda(k)
			grid.add_child(_celdas[k])
		_celdas[N * N + i] = _crear_celda(N * N + i)
		grid.add_child(_celdas[N * N + i])

	_chk_esperados = CheckBox.new()
	_chk_esperados.text = "Mostrar el valor esperado"
	_chk_esperados.add_theme_font_size_override("font_size", FUENTE)
	_chk_esperados.toggled.connect(func(_v: bool) -> void: _actualizar_detalle())
	add_child(_chk_esperados)

	_lbl_detalle = _etiqueta("Selecciona una celda para ver su valor.", FUENTE)
	_lbl_detalle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_detalle.custom_minimum_size = Vector2(0, 52)
	add_child(_lbl_detalle)

	_lbl_resumen = _etiqueta("", 13)
	_lbl_resumen.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_lbl_resumen)

	# Ganancias Ka = [K, -ki]
	var fila_titulo := HBoxContainer.new()
	add_child(fila_titulo)
	var lbl_ka := _etiqueta("Ganancias Ka = [K1, K2, K3, K4, −ki]  (LMI de orden 5):", FUENTE)
	lbl_ka.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fila_titulo.add_child(lbl_ka)
	var btn_matlab := Button.new()
	btn_matlab.text = "Calcular Ka con MATLAB"
	btn_matlab.add_theme_font_size_override("font_size", FUENTE)
	btn_matlab.pressed.connect(func() -> void: calcular_con_matlab.emit())
	fila_titulo.add_child(btn_matlab)
	var fila_ka := HBoxContainer.new()
	fila_ka.add_theme_constant_override("separation", 6)
	add_child(fila_ka)
	for k in range(N):
		var s := SpinBox.new()
		s.min_value = -100000.0
		s.max_value = 100000.0
		s.step = 0.0001
		s.allow_greater = true
		s.allow_lesser = true
		s.custom_minimum_size = Vector2(118, 0)
		s.prefix = "Ka%d:" % (k + 1)
		s.get_line_edit().add_theme_font_size_override("font_size", FUENTE)
		s.value_changed.connect(func(_v: float) -> void: _actualizar_polos())
		fila_ka.add_child(s)
		_spin_ka.append(s)

	_lbl_ki = _etiqueta("", 11)
	_lbl_ki.modulate = Color(1, 1, 1, 0.8)
	add_child(_lbl_ki)

	_lbl_polos = _etiqueta("", 12)
	_lbl_polos.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_lbl_polos)

	var botones := HBoxContainer.new()
	botones.add_theme_constant_override("separation", 8)
	add_child(botones)

	var btn_ideal := Button.new()
	btn_ideal.text = "Cargar sistema ideal"
	btn_ideal.pressed.connect(func() -> void:
		cargar(PackedStringArray(FormulasLineales.EJEMPLO_AUM_A),
			PackedStringArray(FormulasLineales.EJEMPLO_AUM_B)))
	botones.add_child(btn_ideal)

	var btn_friccion := Button.new()
	btn_friccion.text = "Cargar con fricción"
	btn_friccion.pressed.connect(func() -> void:
		cargar(PackedStringArray(FormulasLineales.EJEMPLO_AUM_A_FRICCION),
			PackedStringArray(FormulasLineales.EJEMPLO_AUM_B)))
	botones.add_child(btn_friccion)

	var btn_limpiar := Button.new()
	btn_limpiar.text = "Limpiar Aa y Ba"
	btn_limpiar.pressed.connect(func() -> void:
		for celda: LineEdit in _celdas:
			celda.text = ""
		_reevaluar())
	botones.add_child(btn_limpiar)


func _etiqueta(texto: String, tam: int) -> Label:
	var e := Label.new()
	e.text = texto
	e.add_theme_font_size_override("font_size", tam)
	return e


func _crear_celda(k: int) -> LineEdit:
	var celda := LineEdit.new()
	celda.custom_minimum_size = Vector2(84, 0)
	celda.placeholder_text = "0"
	celda.add_theme_font_size_override("font_size", FUENTE)
	celda.text_changed.connect(func(_t: String) -> void: _reevaluar())
	celda.focus_entered.connect(func() -> void:
		_celda_activa = k
		_actualizar_detalle())
	return celda


# ------------------------------------------------------------
# Evaluacion
# ------------------------------------------------------------

func _reevaluar() -> void:
	if _celdas.is_empty() or _parametros.is_empty():
		return
	_resultado = FormulasLineales.evaluar_modelo(_aux, obtener_A(), obtener_B(), _parametros, N)

	var correctas: int = 0
	var con_error: int = 0
	for k in range(_celdas.size()):
		var color: Color = COLOR_TEXTO
		match _estado_celda(k):
			"ok":
				color = COLOR_OK
				correctas += 1
			"diferente":
				color = COLOR_DIFERENTE
			"error":
				color = COLOR_ERROR
				con_error += 1
		_celdas[k].add_theme_color_override("font_color", color)
		_celdas[k].tooltip_text = _celdas[k].text if _celdas[k].text != "" else "0"

	var total: int = _celdas.size()
	if _error_parametros != "":
		_resumen("Parámetros inválidos: " + _error_parametros, COLOR_ERROR)
	elif not _resultado.errores_aux.is_empty():
		_resumen("Las auxiliares de la pestaña 2 tienen errores.", COLOR_ERROR)
	elif con_error > 0:
		_resumen("%d/%d correctas · %d celda(s) con error de escritura." % [correctas, total, con_error], COLOR_ERROR)
	elif _esperado_A.is_empty():
		_resumen("Sin referencia: corrige las ecuaciones de la pestaña 1.", COLOR_DIFERENTE)
	elif correctas == total:
		_resumen("Correcto: Aa y Ba coinciden con [A 0; −C 0] y [B; 0] de la linealización.", COLOR_OK)
	else:
		_resumen("%d/%d correctas. Las celdas en naranja no coinciden con el sistema aumentado esperado."
			% [correctas, total], COLOR_DIFERENTE)

	_actualizar_detalle()
	_actualizar_polos()


func _resumen(texto: String, color: Color) -> void:
	_lbl_resumen.text = texto
	_lbl_resumen.add_theme_color_override("font_color", color)


func _estado_celda(k: int) -> String:
	if _error_celda(k) != "":
		return "error"
	if _esperado_A.is_empty():
		return "sin_referencia"
	var v: float = _valor_celda(k)
	var e: float = _esperado_celda(k)
	return "ok" if absf(v - e) <= 1e-5 + 1e-4 * absf(e) else "diferente"


func _valor_celda(k: int) -> float:
	return _resultado.A[k] if k < N * N else _resultado.B[k - N * N]


func _esperado_celda(k: int) -> float:
	return _esperado_A[k] if k < N * N else _esperado_B[k - N * N]


func _error_celda(k: int) -> String:
	return _resultado.errores_A[k] if k < N * N else _resultado.errores_B[k - N * N]


func _nombre_celda(k: int) -> String:
	if k < N * N:
		var i: int = floori(k / float(N))
		var j: int = k % N
		return "Aa[%d,%d]  (fila %s, columna %s)" % [i + 1, j + 1, NOMBRES_FILA[i], NOMBRES_ESTADO[j]]
	var f: int = k - N * N
	return "Ba[%d]  (fila %s)" % [f + 1, NOMBRES_FILA[f]]


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
		var texto: String = "Valor: " + String.num(_valor_celda(k), 6)
		if _chk_esperados.button_pressed and not _esperado_A.is_empty():
			texto += "     Esperado: " + String.num(_esperado_celda(k), 6)
		match _estado_celda(k):
			"ok":
				texto += "   ✓ coincide"
			"diferente":
				texto += "   ✗ no coincide"
		lineas.append(texto)
	_lbl_detalle.text = "\n".join(lineas)


# Polos de Aa - Ba*Ka con las formulas actuales (como eig(Acl) en MATLAB).
func _actualizar_polos() -> void:
	if _lbl_polos == null or _spin_ka.is_empty():
		return
	var Ka := PackedFloat64Array()
	for s: SpinBox in _spin_ka:
		Ka.append(s.value)
	_lbl_ki.text = "ki = −Ka5 = %s     (u = −K·X + ki·z)" % String.num(-Ka[4], 4)

	if _resultado.is_empty() or not _resultado.ok:
		_lbl_polos.text = "Polos de lazo cerrado: corrige Aa y Ba para calcularlos."
		_lbl_polos.add_theme_color_override("font_color", COLOR_ERROR)
		return

	var Acl: PackedFloat64Array = Algebra.lazo_cerrado(_resultado.A, _resultado.B, Ka)
	var polos: Array[Vector2] = Algebra.polos(Acl, N)
	var textos: Array[String] = []
	var estable: bool = true
	var mayor: float = -INF
	for p: Vector2 in polos:
		if p.y < 0.0:
			continue   # el conjugado ya se muestra con ±
		var t: String = Algebra.texto_polo(p).replace("+ ", "± ")
		textos.append(t)
		estable = estable and p.x < 0.0
		mayor = maxf(mayor, p.x)
	var texto: String = "Polos de Aa − Ba·Ka:  " + ",   ".join(textos)
	if estable:
		texto += "\n→ Estable: todos con parte real negativa (la más lenta en %s)." % String.num(mayor, 3)
		_lbl_polos.add_theme_color_override("font_color", COLOR_OK)
	else:
		texto += "\n→ INESTABLE: hay polos con parte real ≥ 0. Revisa Ka (o el signo de ki)."
		_lbl_polos.add_theme_color_override("font_color", COLOR_ERROR)
	_lbl_polos.text = texto

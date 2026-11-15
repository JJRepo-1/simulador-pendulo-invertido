class_name ModeloFormulas
extends RefCounted

# ============================================================
# MODELO NO LINEAL DEFINIDO POR LAS FORMULAS DEL USUARIO
# ============================================================
# x''     = formula_ddx (x, theta, dx, dtheta, u, parametros, auxiliares)
# theta'' = formula_ddth(..., y ademas ddx)
#
# Misma interfaz que PenduloModelo (derivada, jacobiano), asi que la
# simulacion puede usar cualquiera de los dos como planta.
#
# Orden de evaluacion en cada llamada:
#   parametros y auxiliares constantes (fijos) -> estado -> auxiliares
#   del modelo no lineal (una por linea) -> x'' -> theta''

# Indices fijos de las variables de estado en el arreglo de valores
var _i_x: int
var _i_theta: int
var _i_dx: int
var _i_dtheta: int
var _i_u: int
var _i_ddx: int

var _valores: Array = []
var _aux_programas: Array[FormulasLineales.Programa] = []
var _aux_indices: Array[int] = []
var _aux_nombres: Array[String] = []
var _prog_ddx: FormulasLineales.Programa
var _prog_ddth: FormulasLineales.Programa

# Error ocurrido durante la simulacion (division entre cero, etc.)
var error_ejecucion: String = ""


# Construye el modelo. Devuelve:
# {"ok": bool, "modelo": ModeloFormulas o null,
#  "errores_aux": PackedStringArray, "error_ddx": String, "error_ddth": String}
static func construir(p: Dictionary, aux_constantes: String, aux_nl: String,
		formula_ddx: String, formula_ddth: String) -> Dictionary:
	var modelo := ModeloFormulas.new()
	var nombres := PackedStringArray()

	# 1. Parametros y auxiliares constantes (los errores de estas se
	#    muestran en la pestana del modelo lineal; aqui solo se omiten)
	var constantes: Dictionary = FormulasLineales.evaluar_auxiliares(
		aux_constantes, FormulasLineales.variables_parametros(p)).variables
	for nombre: String in constantes:
		nombres.append(nombre)
		modelo._valores.append(constantes[nombre])

	# 2. Estado y entrada
	modelo._i_x = nombres.size()
	for nombre: String in FormulasLineales.VARIABLES_ESTADO:
		nombres.append(nombre)
		modelo._valores.append(0.0)
	modelo._i_theta = modelo._i_x + 1
	modelo._i_dx = modelo._i_x + 2
	modelo._i_dtheta = modelo._i_x + 3
	modelo._i_u = modelo._i_x + 4

	# 3. Auxiliares que pueden depender del estado
	var errores_aux := PackedStringArray()
	for item: Dictionary in FormulasLineales.leer_auxiliares(aux_nl, nombres):
		if item.error != "":
			errores_aux.append(item.error)
			continue
		var r: Dictionary = FormulasLineales.compilar(item.formula, nombres, "no_lineal")
		if not r.ok:
			errores_aux.append("Linea %d (%s): %s" % [item.linea, item.nombre, r.error])
			continue
		modelo._aux_programas.append(r.programa)
		modelo._aux_indices.append(nombres.size())
		modelo._aux_nombres.append(item.nombre)
		nombres.append(item.nombre)
		modelo._valores.append(0.0)

	# 4. Aceleraciones (theta'' puede usar ddx)
	var error_ddx: String = ""
	var error_ddth: String = ""

	if formula_ddx.strip_edges().is_empty():
		error_ddx = "Escribe la ecuacion de x''."
	else:
		var r_ddx: Dictionary = FormulasLineales.compilar(formula_ddx, nombres, "no_lineal")
		modelo._prog_ddx = r_ddx.programa
		error_ddx = r_ddx.error

	modelo._i_ddx = nombres.size()
	nombres.append(FormulasLineales.VARIABLE_DDX)
	modelo._valores.append(0.0)

	if formula_ddth.strip_edges().is_empty():
		error_ddth = "Escribe la ecuacion de theta''."
	else:
		var r_ddth: Dictionary = FormulasLineales.compilar(formula_ddth, nombres, "no_lineal")
		modelo._prog_ddth = r_ddth.programa
		error_ddth = r_ddth.error

	var ok: bool = errores_aux.is_empty() and error_ddx == "" and error_ddth == ""
	return {
		"ok": ok,
		"modelo": modelo if ok else null,
		"errores_aux": errores_aux,
		"error_ddx": error_ddx,
		"error_ddth": error_ddth,
	}


# Aceleraciones [x'', theta''] en doble precision. Si una formula falla
# durante la ejecucion, guarda el motivo en error_ejecucion y devuelve NAN.
func aceleraciones_estado(x: float, theta: float, x_dot: float, theta_dot: float,
		u: float) -> PackedFloat64Array:
	_valores[_i_x] = x
	_valores[_i_theta] = theta
	_valores[_i_dx] = x_dot
	_valores[_i_dtheta] = theta_dot
	_valores[_i_u] = u

	for k in range(_aux_programas.size()):
		var v: float = _aux_programas[k].ejecutar(_valores)
		if _aux_programas[k].error != "":
			return _fallo("Auxiliar '%s': %s" % [_aux_nombres[k], _aux_programas[k].error])
		_valores[_aux_indices[k]] = v

	var ddx: float = _prog_ddx.ejecutar(_valores)
	if _prog_ddx.error != "":
		return _fallo("x'': " + _prog_ddx.error)
	_valores[_i_ddx] = ddx

	var ddth: float = _prog_ddth.ejecutar(_valores)
	if _prog_ddth.error != "":
		return _fallo("theta'': " + _prog_ddth.error)

	if not (is_finite(ddx) and is_finite(ddth)):
		return _fallo("Las ecuaciones dieron un valor no finito (theta = %.2f°)." % rad_to_deg(theta))

	return PackedFloat64Array([ddx, ddth])


func _fallo(mensaje: String) -> PackedFloat64Array:
	if error_ejecucion == "":
		error_ejecucion = mensaje
	return PackedFloat64Array([NAN, NAN])


# Derivada completa del estado, para los integradores de la simulacion.
func derivada(state: Vector4, u: float) -> Vector4:
	var acc: PackedFloat64Array = aceleraciones_estado(state.x, state.y, state.z, state.w, u)
	return Vector4(state.z, state.w, acc[0], acc[1])


func _f(X: PackedFloat64Array, u: float) -> PackedFloat64Array:
	var acc: PackedFloat64Array = aceleraciones_estado(X[0], X[1], X[2], X[3], u)
	return PackedFloat64Array([X[2], X[3], acc[0], acc[1]])


# Linealizacion numerica alrededor de (X0, u0). Devuelve {"A", "B"}.
func jacobiano(X0: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0, 0.0]),
		u0: float = 0.0, eps: float = 1e-6) -> Dictionary:
	return PenduloModelo.jacobiano_numerico(_f, X0, u0, eps)

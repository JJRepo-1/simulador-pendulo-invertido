class_name ModeloFormulas
extends RefCounted

# ============================================================
# MODELO NO LINEAL DEFINIDO POR LAS ECUACIONES DEL USUARIO
# ============================================================
# El estudiante escribe las dos ecuaciones de movimiento tal como salen
# de Euler-Lagrange, por ejemplo (sistema ideal):
#
#   carro:   (M+m)*x'' + m*l*θ''*cosθ - m*l*θ'^2*senθ = u
#   pendulo: (J+m*l^2)*θ'' + m*l*x''*cosθ - m*g*l*senθ = 0
#
# Cada ecuacion se guarda como su residuo R = izquierda - derecha.
# Como las ecuaciones son lineales en las aceleraciones,
#
#   R_i(x'', θ'') = a_i1*x'' + a_i2*θ'' + r_i
#
# y los coeficientes se obtienen evaluando R en (0,0), (1,0) y (0,1).
# [a_ij] es la matriz de masas; el sistema 2x2 se resuelve por Cramer.
#
# Misma interfaz que PenduloModelo (derivada, jacobiano), asi que la
# simulacion puede usar cualquiera de los dos como planta.

# Estados de prueba [x, theta, dx, dtheta, u] para revisar las ecuaciones
# lejos del equilibrio.
const PUNTOS_PRUEBA: Array = [
	[0.0, 0.0, 0.0, 0.0, 0.0],
	[0.1, 0.3, 0.5, -1.0, 5.0],
	[-0.4, -1.2, -0.3, 2.0, -20.0],
	[0.0, 2.5, 1.0, 0.5, 0.0],
	[0.7, 3.0, -2.0, -3.0, 50.0],
	[0.0, -0.05, 0.2, 0.1, 1.0],
]

# Indices de las variables en el arreglo de valores
var _i_x: int
var _i_theta: int
var _i_dx: int
var _i_dtheta: int
var _i_u: int
var _i_ddx: int
var _i_ddtheta: int

var _valores: Array = []
var _prog_carro: FormulasLineales.Programa
var _prog_pendulo: FormulasLineales.Programa

# Error ocurrido durante la simulacion (division entre cero, etc.)
var error_ejecucion: String = ""


# Construye el modelo. Devuelve:
# {"ok": bool, "modelo": ModeloFormulas o null,
#  "error_carro": String, "error_pendulo": String, "error_sistema": String}
static func construir(p: Dictionary, ecuacion_carro: String, ecuacion_pendulo: String) -> Dictionary:
	var modelo := ModeloFormulas.new()
	var nombres := PackedStringArray()

	var parametros: Dictionary = FormulasLineales.variables_parametros(p)
	for nombre: String in parametros:
		nombres.append(nombre)
		modelo._valores.append(parametros[nombre])

	modelo._i_x = nombres.size()
	for nombre: String in FormulasLineales.VARIABLES_ESTADO + FormulasLineales.VARIABLES_ACELERACION:
		nombres.append(nombre)
		modelo._valores.append(0.0)
	modelo._i_theta = modelo._i_x + 1
	modelo._i_dx = modelo._i_x + 2
	modelo._i_dtheta = modelo._i_x + 3
	modelo._i_u = modelo._i_x + 4
	modelo._i_ddx = modelo._i_x + 5
	modelo._i_ddtheta = modelo._i_x + 6

	var r_carro: Dictionary = FormulasLineales.compilar_ecuacion(ecuacion_carro, nombres, "no_lineal")
	var r_pendulo: Dictionary = FormulasLineales.compilar_ecuacion(ecuacion_pendulo, nombres, "no_lineal")
	modelo._prog_carro = r_carro.programa
	modelo._prog_pendulo = r_pendulo.programa

	var error_sistema: String = ""
	if r_carro.ok and r_pendulo.ok:
		error_sistema = modelo._revisar_estructura()

	var ok: bool = r_carro.ok and r_pendulo.ok and error_sistema == ""
	return {
		"ok": ok,
		"modelo": modelo if ok else null,
		"error_carro": r_carro.error,
		"error_pendulo": r_pendulo.error,
		"error_sistema": error_sistema,
	}


# Verifica en los estados de prueba que las ecuaciones sean lineales en
# x'' y θ'' y que se puedan despejar (matriz de masas invertible).
func _revisar_estructura() -> String:
	for punto: Array in PUNTOS_PRUEBA:
		var co: Dictionary = coeficientes(punto[0], punto[1], punto[2], punto[3], punto[4])
		var donde: String = " (en θ = %.0f°)" % rad_to_deg(punto[1])
		if co.error != "":
			return co.error + donde
		if absf(co.det) < 1e-12:
			return ("No se pueden despejar x'' y θ''" + donde
				+ ": la matriz de masas es singular. Revisa que x'' y θ'' aparezcan en las ecuaciones.")

		# Prueba con x'' = 2, θ'' = -3: si fueran lineales, R = 2*a1 - 3*a2 + r
		_valores[_i_ddx] = 2.0
		_valores[_i_ddtheta] = -3.0
		var reales: Array[float] = [_prog_carro.ejecutar(_valores), _prog_pendulo.ejecutar(_valores)]
		var esperados: Array[float] = [
			2.0 * co.a11 - 3.0 * co.a12 + co.r1,
			2.0 * co.a21 - 3.0 * co.a22 + co.r2,
		]
		for i in range(2):
			var escala: float = 1.0 + absf(esperados[i]) + absf(reales[i])
			if not is_finite(reales[i]) or absf(reales[i] - esperados[i]) > 1e-8 * escala:
				return ("La ecuacion %s no es lineal en x'' y θ''%s (por ejemplo, x''^2 o sen(θ'')). "
					% ["del carro" if i == 0 else "del pendulo", donde]
					+ "En las ecuaciones de movimiento las aceleraciones solo aparecen multiplicadas por coeficientes.")
	return ""


# Coeficientes de las ecuaciones en un estado:
#   carro:   a11*x'' + a12*θ'' + r1 = 0
#   pendulo: a21*x'' + a22*θ'' + r2 = 0
# Devuelve {"a11","a12","a21","a22","r1","r2","det","error"}.
func coeficientes(x: float, theta: float, x_dot: float, theta_dot: float, u: float) -> Dictionary:
	_valores[_i_x] = x
	_valores[_i_theta] = theta
	_valores[_i_dx] = x_dot
	_valores[_i_dtheta] = theta_dot
	_valores[_i_u] = u

	var r: Array[float] = []
	for acc: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)]:
		_valores[_i_ddx] = acc.x
		_valores[_i_ddtheta] = acc.y
		var v_carro: float = _prog_carro.ejecutar(_valores)
		if _prog_carro.error != "":
			return {"error": "Ecuacion del carro: " + _prog_carro.error}
		var v_pendulo: float = _prog_pendulo.ejecutar(_valores)
		if _prog_pendulo.error != "":
			return {"error": "Ecuacion del pendulo: " + _prog_pendulo.error}
		r.append(v_carro)
		r.append(v_pendulo)

	var a11: float = r[2] - r[0]
	var a21: float = r[3] - r[1]
	var a12: float = r[4] - r[0]
	var a22: float = r[5] - r[1]
	return {
		"a11": a11, "a12": a12, "a21": a21, "a22": a22,
		"r1": r[0], "r2": r[1],
		"det": a11 * a22 - a12 * a21,
		"error": "",
	}


# Aceleraciones [x'', theta''] en doble precision. Si algo falla durante
# la ejecucion, guarda el motivo en error_ejecucion y devuelve NAN.
func aceleraciones_estado(x: float, theta: float, x_dot: float, theta_dot: float,
		u: float) -> PackedFloat64Array:
	var co: Dictionary = coeficientes(x, theta, x_dot, theta_dot, u)
	if co.error != "":
		return _fallo(co.error)
	if co.det == 0.0:
		return _fallo("La matriz de masas es singular en θ = %.2f°." % rad_to_deg(theta))

	# a11*x'' + a12*θ'' = -r1 ;  a21*x'' + a22*θ'' = -r2
	var ddx: float = (-co.r1 * co.a22 + co.a12 * co.r2) / co.det
	var ddth: float = (-co.a11 * co.r2 + co.a21 * co.r1) / co.det

	if not (is_finite(ddx) and is_finite(ddth)):
		return _fallo("Las ecuaciones dieron un valor no finito (θ = %.2f°)." % rad_to_deg(theta))

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

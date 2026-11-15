class_name PenduloModelo
extends RefCounted

# ============================================================
# MODELO DINAMICO NO LINEAL DEL PENDULO INVERTIDO SOBRE CARRO
# ============================================================
# Estado X = [x, theta, x', theta'] en SI, theta = 0 -> pendulo arriba.
#
# [M+m          m*l*cos(th)] [x'' ]   [u - c*x' + m*l*sin(th)*th'^2]
# [m*l*cos(th)  J + m*l^2  ] [th''] = [m*g*l*sin(th) - b*th'       ]
#
# Lo comparten pendulo.gd (u = 0), pendulo_2.gd (control) y la
# pantalla de Configuracion (linealizacion numerica de referencia).

var M: float = 2.0     # Masa del carro [kg]
var m: float = 0.2     # Masa del pendulo [kg]
var l: float = 0.5     # Distancia pivote - centro de masa [m]
var J: float = 0.05    # Momento de inercia respecto al centro de masa [kg*m^2]
var g: float = 9.81    # Gravedad [m/s^2]
var c: float = 0.10    # Friccion viscosa del carro [N*s/m]
var b: float = 0.005   # Amortiguamiento viscoso del pivote [N*m*s/rad]


# Para crear el modelo con los parametros guardados usa Globals.crear_modelo().
static func desde_parametros(p: Dictionary) -> PenduloModelo:
	var modelo := PenduloModelo.new()
	modelo.M = float(p.get("M", modelo.M))
	modelo.m = float(p.get("m", modelo.m))
	modelo.l = float(p.get("l", modelo.l))
	modelo.J = float(p.get("J", modelo.J))
	modelo.g = float(p.get("g", modelo.g))
	modelo.c = float(p.get("c", modelo.c))
	modelo.b = float(p.get("b", modelo.b))
	return modelo


func parametros() -> Dictionary:
	return {"M": M, "m": m, "l": l, "J": J, "g": g, "c": c, "b": b}


# Devuelve "" si los parametros son fisicamente validos, o el motivo.
func validar() -> String:
	if M <= 0.0 or m <= 0.0:
		return "Las masas deben ser positivas."
	if l <= 0.0:
		return "La longitud debe ser positiva."
	if J < 0.0:
		return "El momento de inercia no puede ser negativo."
	if c < 0.0 or b < 0.0:
		return "Los coeficientes de friccion no pueden ser negativos."
	return ""


# Aceleraciones [x'', theta''] en doble precision.
func aceleraciones(theta: float, x_dot: float, theta_dot: float, u: float) -> PackedFloat64Array:
	var s: float = sin(theta)
	var co: float = cos(theta)

	var a11: float = M + m
	var a12: float = m * l * co
	var a22: float = J + m * l * l

	var rhs1: float = u - c * x_dot + m * l * s * theta_dot * theta_dot
	var rhs2: float = m * g * l * s - b * theta_dot

	var det: float = a11 * a22 - a12 * a12
	if det <= 0.0:
		return PackedFloat64Array([0.0, 0.0])

	return PackedFloat64Array([
		(a22 * rhs1 - a12 * rhs2) / det,
		(a11 * rhs2 - a12 * rhs1) / det,
	])


# Derivada completa del estado, para los integradores de la simulacion.
func derivada(state: Vector4, u: float) -> Vector4:
	var acc: PackedFloat64Array = aceleraciones(state.y, state.z, state.w, u)
	return Vector4(state.z, state.w, acc[0], acc[1])


# f(X, u) en doble precision.
func _f(X: PackedFloat64Array, u: float) -> PackedFloat64Array:
	var acc: PackedFloat64Array = aceleraciones(X[1], X[2], X[3], u)
	return PackedFloat64Array([X[2], X[3], acc[0], acc[1]])


# Linealizacion numerica (diferencias centrales) alrededor de (X0, u0).
# Devuelve {"A": 16 valores por filas, "B": 4 valores}.
func jacobiano(X0: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0, 0.0]),
		u0: float = 0.0, eps: float = 1e-6) -> Dictionary:
	return jacobiano_numerico(_f, X0, u0, eps)


# Jacobiano por diferencias centrales de cualquier f(X, u) -> dX/dt
# (tambien lo usa ModeloFormulas).
static func jacobiano_numerico(f: Callable, X0: PackedFloat64Array, u0: float,
		eps: float) -> Dictionary:
	var A := PackedFloat64Array()
	A.resize(16)
	var B := PackedFloat64Array()
	B.resize(4)

	for j in range(4):
		var Xp: PackedFloat64Array = X0.duplicate()
		var Xm: PackedFloat64Array = X0.duplicate()
		Xp[j] += eps
		Xm[j] -= eps
		var fp: PackedFloat64Array = f.call(Xp, u0)
		var fm: PackedFloat64Array = f.call(Xm, u0)
		for i in range(4):
			A[i * 4 + j] = (fp[i] - fm[i]) / (2.0 * eps)

	var fup: PackedFloat64Array = f.call(X0, u0 + eps)
	var fum: PackedFloat64Array = f.call(X0, u0 - eps)
	for i in range(4):
		B[i] = (fup[i] - fum[i]) / (2.0 * eps)

	return {"A": A, "B": B}

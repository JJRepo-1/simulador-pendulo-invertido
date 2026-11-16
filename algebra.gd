class_name Algebra
extends RefCounted

# ============================================================
# ALGEBRA LINEAL PEQUENA (matrices n x n en filas)
# ============================================================
# Polos de lazo cerrado, equivalente a eig(Acl) de MATLAB:
#   1. Polinomio caracteristico por Faddeev-LeVerrier.
#   2. Raices por el metodo de Durand-Kerner.
# Suficiente para n <= 6 con los valores del pendulo.


# Acl = A - B*K  (A: n*n por filas, B: n, K: n)
static func lazo_cerrado(A: PackedFloat64Array, B: PackedFloat64Array,
		K: PackedFloat64Array) -> PackedFloat64Array:
	var n: int = B.size()
	var Acl := PackedFloat64Array(A)
	for i in range(n):
		for j in range(n):
			Acl[i * n + j] -= B[i] * K[j]
	return Acl


# Polos de la matriz M (n*n por filas). Cada polo es Vector2(real, imag).
# Ordenados de la parte real mayor a la menor.
static func polos(M: PackedFloat64Array, n: int) -> Array[Vector2]:
	var c: PackedFloat64Array = polinomio_caracteristico(M, n)
	var raices: Array[Vector2] = _durand_kerner(c)
	raices.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return a.x > b.x if absf(a.x - b.x) > 1e-9 else a.y > b.y)
	return raices


# Coeficientes [1, c1, ..., cn] de det(sI - M).
static func polinomio_caracteristico(M: PackedFloat64Array, n: int) -> PackedFloat64Array:
	var c := PackedFloat64Array([1.0])
	var Mk: PackedFloat64Array = _identidad(n)   # M_1 = I
	for k in range(1, n + 1):
		var AM: PackedFloat64Array = _producto(M, Mk, n)
		var ck: float = -_traza(AM, n) / float(k)
		c.append(ck)
		# M_{k+1} = A*M_k + c_k*I
		Mk = AM
		for i in range(n):
			Mk[i * n + i] += ck
	return c


static func _durand_kerner(c: PackedFloat64Array) -> Array[Vector2]:
	var n: int = c.size() - 1
	var raices: Array[Vector2] = []
	# Radio inicial segun el tamano de los coeficientes (cota de Cauchy)
	var radio: float = 1.0
	for k in range(1, c.size()):
		radio = maxf(radio, 1.0 + absf(c[k]))
	radio = minf(radio, 1e3)
	for i in range(n):
		var ang: float = 0.4 + TAU * float(i) / float(n)
		raices.append(Vector2(cos(ang), sin(ang)) * radio * 0.5)

	for _iter in range(500):
		var cambio: float = 0.0
		for i in range(n):
			var num: Vector2 = _evaluar(c, raices[i])
			var den := Vector2(1.0, 0.0)
			for j in range(n):
				if j != i:
					den = _cmul(den, raices[i] - raices[j])
			if den.length_squared() == 0.0:
				den = Vector2(1e-12, 0.0)
			var paso: Vector2 = _cdiv(num, den)
			raices[i] -= paso
			cambio = maxf(cambio, paso.length())
		if cambio < 1e-12:
			break

	# Limpiar partes imaginarias numericamente nulas
	for i in range(n):
		if absf(raices[i].y) < 1e-7 * (1.0 + absf(raices[i].x)):
			raices[i].y = 0.0
	return raices


static func _evaluar(c: PackedFloat64Array, z: Vector2) -> Vector2:
	var r := Vector2.ZERO
	for a: float in c:
		r = _cmul(r, z) + Vector2(a, 0.0)
	return r


static func _cmul(a: Vector2, b: Vector2) -> Vector2:
	return Vector2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x)


static func _cdiv(a: Vector2, b: Vector2) -> Vector2:
	var d: float = b.x * b.x + b.y * b.y
	return Vector2(a.x * b.x + a.y * b.y, a.y * b.x - a.x * b.y) / d


static func _identidad(n: int) -> PackedFloat64Array:
	var I := PackedFloat64Array()
	I.resize(n * n)
	for i in range(n):
		I[i * n + i] = 1.0
	return I


static func _producto(A: PackedFloat64Array, B: PackedFloat64Array, n: int) -> PackedFloat64Array:
	var C := PackedFloat64Array()
	C.resize(n * n)
	for i in range(n):
		for j in range(n):
			var s: float = 0.0
			for k in range(n):
				s += A[i * n + k] * B[k * n + j]
			C[i * n + j] = s
	return C


static func _traza(A: PackedFloat64Array, n: int) -> float:
	var t: float = 0.0
	for i in range(n):
		t += A[i * n + i]
	return t


# Texto de un polo: "-3.79 ± 6.89j" o "-2.94"
static func texto_polo(p: Vector2) -> String:
	if p.y == 0.0:
		return String.num(p.x, 3)
	return "%s %s %sj" % [String.num(p.x, 3), "+" if p.y > 0.0 else "−", String.num(absf(p.y), 3)]

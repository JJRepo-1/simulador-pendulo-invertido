class_name FormulasLineales
extends RefCounted

# ============================================================
# FORMULAS DEL USUARIO: COMPILADOR Y EVALUADOR
# ============================================================
# Se usa para:
#  - el modelo no lineal  x'' = f(...), theta'' = g(...)   (ModeloFormulas)
#  - el modelo lineal     A (4x4) y B (4x1)
#
# Interprete propio (descenso recursivo) en lugar de la clase Expression:
#  - '^' es potencia, como en MATLAB (en Expression es XOR).
#  - Todos los numeros son reales: 1/2 = 0.5 (Expression haria division entera).
#  - Solo admite variables conocidas y una lista cerrada de funciones.
#  - Mensajes de error en espanol, pensados para el estudiante.
#
# Cada formula se compila una vez a notacion polaca inversa (Programa) y se
# ejecuta muchas veces, lo que permite usarla dentro del integrador RK4.
#
# Precedencia: ( )  >  ^ (asociativa a la derecha)  >  signo unario  >  * /  >  + -
# Por eso -x^2 = -(x^2), igual que en MATLAB.

const VARIABLES_BASE: Array[String] = ["M", "m", "l", "J", "g", "c", "b"]
const VARIABLES_ESTADO: Array[String] = ["x", "theta", "dx", "dtheta", "u"]
const VARIABLE_DDX: String = "ddx"

const FUNCIONES: Dictionary = {
	"sin": 1, "cos": 1, "tan": 1,
	"asin": 1, "acos": 1, "atan": 1, "atan2": 2,
	"sqrt": 1, "exp": 1, "log": 1, "abs": 1, "sign": 1,
	"pow": 2, "min": 2, "max": 2,
}

const CONSTANTES: Dictionary = {"pi": PI, "PI": PI}

# --- Modelo no lineal de referencia escrito en forma explicita ---
# Equivale a resolver la matriz de masas de modelo_pendulo.gd.
const EJEMPLO_NL_AUX: String = "a12 = m*l*cos(theta)\nD = (M + m)*(J + m*l^2) - a12^2\nF1 = u - c*dx + m*l*sin(theta)*dtheta^2\nF2 = m*g*l*sin(theta) - b*dtheta"
const EJEMPLO_DDX: String = "((J + m*l^2)*F1 - a12*F2)/D"
const EJEMPLO_DDTH: String = "((M + m)*F2 - a12*F1)/D"

# --- Linealizacion del modelo de referencia en X = 0, u = 0 ---
# Con c = b = 0 se reduce a las matrices del script de MATLAB.
const EJEMPLO_AUX: String = "Delta = (M + m)*J + M*m*l^2"

const EJEMPLO_A: Array[String] = [
	"0", "0", "1", "0",
	"0", "0", "0", "1",
	"0", "-(m^2*g*l^2)/Delta", "-(J + m*l^2)*c/Delta", "m*l*b/Delta",
	"0", "(M + m)*m*g*l/Delta", "m*l*c/Delta", "-(M + m)*b/Delta",
]

const EJEMPLO_B: Array[String] = [
	"0",
	"0",
	"(J + m*l^2)/Delta",
	"-(m*l)/Delta",
]

# Codigos de operacion del programa compilado
enum Op { NUM, VAR, ADD, SUB, MUL, DIV, POW, NEG, FUNC }


# ------------------------------------------------------------
# Programa compilado
# ------------------------------------------------------------

class Programa:
	extends RefCounted
	# Pares [op, argumento] consecutivos
	var codigo: Array = []
	# Error de la ultima ejecucion ("" si no hubo)
	var error: String = ""

	func ejecutar(valores: Array) -> float:
		error = ""
		var pila: Array[float] = []
		var i: int = 0
		var n: int = codigo.size()
		while i < n:
			var op: int = codigo[i]
			var arg = codigo[i + 1]
			i += 2
			match op:
				Op.NUM:
					pila.append(arg)
				Op.VAR:
					pila.append(valores[arg])
				Op.NEG:
					pila[-1] = -pila[-1]
				Op.ADD, Op.SUB, Op.MUL, Op.DIV, Op.POW:
					var d: float = pila.pop_back()
					var a: float = pila[-1]
					match op:
						Op.ADD: pila[-1] = a + d
						Op.SUB: pila[-1] = a - d
						Op.MUL: pila[-1] = a * d
						Op.POW: pila[-1] = pow(a, d)
						Op.DIV:
							if d == 0.0:
								error = "Division entre cero."
								return NAN
							pila[-1] = a / d
				Op.FUNC:
					var nargs: int = FUNCIONES[arg]
					var b: float = pila.pop_back() if nargs == 2 else 0.0
					var a: float = pila[-1]
					pila[-1] = _aplicar(arg, a, b)
					if error != "":
						return NAN
		return pila[-1] if pila.size() == 1 else NAN

	func _aplicar(nombre: String, a: float, b: float) -> float:
		match nombre:
			"sin": return sin(a)
			"cos": return cos(a)
			"tan": return tan(a)
			"asin": return asin(a)
			"acos": return acos(a)
			"atan": return atan(a)
			"atan2": return atan2(a, b)
			"sqrt":
				if a < 0.0:
					error = "Raiz cuadrada de un numero negativo."
					return NAN
				return sqrt(a)
			"exp": return exp(a)
			"log":
				if a <= 0.0:
					error = "Logaritmo de un numero no positivo."
					return NAN
				return log(a)
			"abs": return absf(a)
			"sign": return signf(a)
			"pow": return pow(a, b)
			"min": return minf(a, b)
			"max": return maxf(a, b)
		return NAN


# ------------------------------------------------------------
# API publica
# ------------------------------------------------------------

# Compila una formula. 'nombres' son las variables permitidas; la posicion
# de cada nombre es el indice que se usara en el arreglo de valores.
# 'contexto' ajusta las pistas de error: "lineal" o "no_lineal".
# Una formula vacia vale 0.
# Devuelve {"ok": bool, "programa": Programa, "error": String}.
static func compilar(formula: String, nombres: PackedStringArray,
		contexto: String = "") -> Dictionary:
	var texto: String = formula.strip_edges().trim_suffix(";").strip_edges()
	var programa := Programa.new()
	if texto.is_empty():
		programa.codigo = [Op.NUM, 0.0]
		return {"ok": true, "programa": programa, "error": ""}

	var c := _Compilador.new(texto, nombres, contexto)
	c.compilar()
	if c.error != "":
		return {"ok": false, "programa": null, "error": c.error}
	programa.codigo = c.codigo
	return {"ok": true, "programa": programa, "error": ""}


# Compila y evalua una formula con un diccionario nombre -> valor.
# Devuelve {"ok": bool, "valor": float, "error": String}.
static func evaluar(formula: String, variables: Dictionary, contexto: String = "") -> Dictionary:
	var nombres := PackedStringArray(variables.keys())
	var r: Dictionary = compilar(formula, nombres, contexto)
	if not r.ok:
		return {"ok": false, "valor": NAN, "error": r.error}

	var programa: Programa = r.programa
	var valor: float = programa.ejecutar(variables.values())
	if programa.error != "":
		return {"ok": false, "valor": NAN, "error": programa.error}
	if is_nan(valor) or is_inf(valor):
		return {"ok": false, "valor": valor, "error": "El resultado no es un numero finito."}
	return {"ok": true, "valor": valor, "error": ""}


# Separa "nombre = formula" de cada linea de auxiliares, ignorando
# lineas vacias y comentarios ('#' o '%').
# Devuelve un arreglo de {"linea", "nombre", "formula", "error"}.
static func leer_auxiliares(texto: String, reservados: PackedStringArray) -> Array[Dictionary]:
	var salida: Array[Dictionary] = []
	var nombre_valido := RegEx.create_from_string("^[A-Za-z_][A-Za-z0-9_]*$")

	var lineas: PackedStringArray = texto.split("\n")
	for n in range(lineas.size()):
		var linea: String = _quitar_comentario(lineas[n]).strip_edges()
		if linea.is_empty():
			continue

		var item: Dictionary = {"linea": n + 1, "nombre": "", "formula": "", "error": ""}
		var igual: int = linea.find("=")
		if igual < 0:
			item.error = "Linea %d: falta '=' (formato: nombre = formula)." % (n + 1)
		else:
			item.nombre = linea.substr(0, igual).strip_edges()
			item.formula = linea.substr(igual + 1)
			if nombre_valido.search(item.nombre) == null:
				item.error = "Linea %d: '%s' no es un nombre de variable valido." % [n + 1, item.nombre]
			elif item.nombre in VARIABLES_BASE:
				item.error = "Linea %d: '%s' es un parametro del modelo y no se puede redefinir." % [n + 1, item.nombre]
			elif item.nombre in VARIABLES_ESTADO or item.nombre == VARIABLE_DDX:
				item.error = "Linea %d: '%s' es una variable de estado y no se puede redefinir." % [n + 1, item.nombre]
			elif FUNCIONES.has(item.nombre) or CONSTANTES.has(item.nombre) or item.nombre in reservados:
				item.error = "Linea %d: '%s' es un nombre reservado o ya definido." % [n + 1, item.nombre]
		salida.append(item)
	return salida


# Evalua las variables auxiliares constantes (solo parametros).
# Cada linea puede usar las anteriores.
# Devuelve {"ok": bool, "variables": Dictionary, "errores": PackedStringArray}.
static func evaluar_auxiliares(texto: String, variables_base: Dictionary) -> Dictionary:
	var variables: Dictionary = variables_base.duplicate()
	var errores := PackedStringArray()

	for item: Dictionary in leer_auxiliares(texto, PackedStringArray()):
		if item.error != "":
			errores.append(item.error)
			continue
		if variables.has(item.nombre):
			errores.append("Linea %d: '%s' ya fue definida." % [item.linea, item.nombre])
			continue
		var r: Dictionary = evaluar(item.formula, variables, "lineal")
		if not r.ok:
			errores.append("Linea %d (%s): %s" % [item.linea, item.nombre, r.error])
			continue
		variables[item.nombre] = r.valor

	return {"ok": errores.is_empty(), "variables": variables, "errores": errores}


# Parametros con los nombres de las formulas (M, m, l, J, g, c, b).
static func variables_parametros(p: Dictionary) -> Dictionary:
	var base: Dictionary = {}
	for nombre: String in VARIABLES_BASE:
		base[nombre] = float(p.get(nombre, 0.0))
	return base


# Evalua A (16 formulas por filas) y B (4 formulas) con los parametros p.
# Devuelve {"ok", "A", "B", "errores_A", "errores_B", "errores_aux"}.
static func evaluar_modelo(aux: String, formulas_A: PackedStringArray,
		formulas_B: PackedStringArray, p: Dictionary) -> Dictionary:
	var r_aux: Dictionary = evaluar_auxiliares(aux, variables_parametros(p))
	var variables: Dictionary = r_aux.variables

	var A := PackedFloat64Array()
	A.resize(16)
	var errores_A := PackedStringArray()
	errores_A.resize(16)
	var B := PackedFloat64Array()
	B.resize(4)
	var errores_B := PackedStringArray()
	errores_B.resize(4)

	var ok: bool = r_aux.ok
	for k in range(16):
		var r: Dictionary = evaluar(formulas_A[k] if k < formulas_A.size() else "", variables, "lineal")
		A[k] = r.valor
		errores_A[k] = r.error
		ok = ok and r.ok
	for k in range(4):
		var r: Dictionary = evaluar(formulas_B[k] if k < formulas_B.size() else "", variables, "lineal")
		B[k] = r.valor
		errores_B[k] = r.error
		ok = ok and r.ok

	return {
		"ok": ok,
		"A": A,
		"B": B,
		"errores_A": errores_A,
		"errores_B": errores_B,
		"errores_aux": r_aux.errores,
	}


static func _quitar_comentario(linea: String) -> String:
	var corte: int = linea.length()
	for simbolo: String in ["#", "%"]:
		var pos: int = linea.find(simbolo)
		if pos >= 0 and pos < corte:
			corte = pos
	return linea.substr(0, corte)


# ------------------------------------------------------------
# Compilador de expresiones a notacion polaca inversa
# ------------------------------------------------------------

class _Compilador:
	var texto: String
	var nombres: PackedStringArray
	var contexto: String
	var codigo: Array = []
	var pos: int = 0
	var error: String = ""

	# Token actual: tipo ("num", "id", "op", "fin"), valor y posicion
	var tipo: String = ""
	var valor: String = ""
	var inicio: int = 0

	func _init(t: String, n: PackedStringArray, ctx: String) -> void:
		texto = t
		nombres = n
		contexto = ctx

	func compilar() -> void:
		_siguiente()
		_suma()
		if error == "" and tipo != "fin":
			_fallar("Simbolo inesperado '%s'." % valor)

	func _emitir(op: int, arg = null) -> void:
		codigo.append(op)
		codigo.append(arg)

	func _fallar(mensaje: String) -> void:
		if error == "":
			error = mensaje + " (posicion %d)" % (inicio + 1)

	# --- Analizador lexico ---

	func _siguiente() -> void:
		while pos < texto.length() and texto[pos] in [" ", "\t"]:
			pos += 1
		inicio = pos
		if pos >= texto.length():
			tipo = "fin"
			valor = ""
			return

		var ch: String = texto[pos]

		# Operadores elemento a elemento de MATLAB (.^ .* ./) -> escalares
		if ch == "." and pos + 1 < texto.length() and texto[pos + 1] in ["^", "*", "/"]:
			pos += 1
			ch = texto[pos]
			inicio = pos

		if _es_digito(ch) or (ch == "." and pos + 1 < texto.length() and _es_digito(texto[pos + 1])):
			var fin: int = pos
			while fin < texto.length() and (_es_digito(texto[fin]) or texto[fin] == "."):
				fin += 1
			# Notacion cientifica: 1e-3, 2.5E4
			if fin < texto.length() and texto[fin] in ["e", "E"]:
				var k: int = fin + 1
				if k < texto.length() and texto[k] in ["+", "-"]:
					k += 1
				if k < texto.length() and _es_digito(texto[k]):
					while k < texto.length() and _es_digito(texto[k]):
						k += 1
					fin = k
			tipo = "num"
			valor = texto.substr(pos, fin - pos)
			pos = fin
			return

		if _es_letra(ch):
			var fin: int = pos
			while fin < texto.length() and (_es_letra(texto[fin]) or _es_digito(texto[fin])):
				fin += 1
			tipo = "id"
			valor = texto.substr(pos, fin - pos)
			pos = fin
			return

		tipo = "op"
		valor = ch
		pos += 1
		if not ch in ["+", "-", "*", "/", "^", "(", ")", ","]:
			_fallar("Caracter no valido '%s'." % ch)

	func _es_digito(ch: String) -> bool:
		return ch >= "0" and ch <= "9"

	func _es_letra(ch: String) -> bool:
		return (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or ch == "_"

	func _es_op(simbolo: String) -> bool:
		return tipo == "op" and valor == simbolo

	# --- Analizador sintactico ---

	# suma := producto (('+' | '-') producto)*
	func _suma() -> void:
		_producto()
		while error == "" and (_es_op("+") or _es_op("-")):
			var op: int = Op.ADD if valor == "+" else Op.SUB
			_siguiente()
			_producto()
			_emitir(op)

	# producto := unario (('*' | '/') unario)*
	func _producto() -> void:
		_unario()
		while error == "" and (_es_op("*") or _es_op("/")):
			var op: int = Op.MUL if valor == "*" else Op.DIV
			_siguiente()
			_unario()
			_emitir(op)

	# unario := ('-' | '+') unario | potencia
	func _unario() -> void:
		if _es_op("-"):
			_siguiente()
			_unario()
			_emitir(Op.NEG)
			return
		if _es_op("+"):
			_siguiente()
			_unario()
			return
		_potencia()

	# potencia := primario ('^' unario)?
	func _potencia() -> void:
		_primario()
		if error == "" and _es_op("^"):
			_siguiente()
			_unario()
			_emitir(Op.POW)

	# primario := numero | variable | funcion '(' args ')' | '(' suma ')'
	func _primario() -> void:
		if error != "":
			return

		if tipo == "num":
			if not valor.is_valid_float():
				_fallar("Numero mal escrito '%s'." % valor)
				return
			_emitir(Op.NUM, valor.to_float())
			_siguiente()
			return

		if tipo == "id":
			var nombre: String = valor
			_siguiente()
			if _es_op("("):
				_llamada(nombre)
				return
			var indice: int = nombres.find(nombre)
			if indice >= 0:
				_emitir(Op.VAR, indice)
			elif CONSTANTES.has(nombre):
				_emitir(Op.NUM, CONSTANTES[nombre])
			elif FUNCIONES.has(nombre):
				_fallar("La funcion '%s' necesita parentesis." % nombre)
			elif contexto == "lineal" and (nombre in VARIABLES_ESTADO or nombre == VARIABLE_DDX):
				_fallar("'%s' es una variable de estado: A y B deben ser constantes (evaluadas en el equilibrio)." % nombre)
			elif contexto == "no_lineal" and nombre == VARIABLE_DDX:
				_fallar("'ddx' solo se puede usar en la ecuacion de theta''.")
			else:
				_fallar("Variable desconocida '%s'." % nombre)
			return

		if _es_op("("):
			_siguiente()
			_suma()
			if error == "" and not _es_op(")"):
				_fallar("Falta cerrar un parentesis ')'.")
				return
			_siguiente()
			return

		if tipo == "fin":
			_fallar("La formula termina de forma incompleta.")
		else:
			_fallar("Se esperaba un numero, una variable o '(' y aparecio '%s'." % valor)

	func _llamada(nombre: String) -> void:
		if not FUNCIONES.has(nombre):
			_fallar("Funcion desconocida '%s'." % nombre)
			return
		_siguiente() # consume '('

		var nargs: int = 0
		if not _es_op(")"):
			_suma()
			nargs = 1
			while error == "" and _es_op(","):
				_siguiente()
				_suma()
				nargs += 1
		if error != "":
			return
		if not _es_op(")"):
			_fallar("Falta cerrar el parentesis de '%s'." % nombre)
			return
		_siguiente()

		var esperados: int = FUNCIONES[nombre]
		if nargs != esperados:
			_fallar("'%s' recibe %d argumento(s) y se dieron %d." % [nombre, esperados, nargs])
			return
		_emitir(Op.FUNC, nombre)

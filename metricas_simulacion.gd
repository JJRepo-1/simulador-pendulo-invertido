class_name MetricasSimulacion
extends RefCounted

# ============================================================
# METRICAS DE DESEMPENO A PARTIR DE UN RegistroSimulacion
# ============================================================
# Devuelve secciones [{"titulo": String, "filas": [[nombre, valor], ...]}]
# que se muestran en la pagina "Resultados" y se agregan al CSV.
#
# Definiciones (se incluyen en la seccion "Criterios"):
#  - Tiempo de establecimiento: ultimo instante en que la senal sale de una
#    banda de ±2 % alrededor de su valor final, medido desde t = 0 (o desde
#    el cambio de referencia en seguimiento).
#  - Sobreimpulso: cuanto pasa la senal del valor final, en % del cambio.
#  - Tiempo de subida: del 10 % al 90 % del cambio de referencia.
#  - IAE = ∫|e|dt, ISE = ∫e²dt, ITAE = ∫t|e|dt (regla del trapecio).
#  - Lineal vs no lineal: error maximo max|y_NL - y_L|, RMSE y RMSE
#    relativo al rango de la senal no lineal.

const BANDA: float = 0.02   # criterio de establecimiento ±2 %


# tipo: "sin_control", "regulador" o "seguimiento"
static func calcular(reg: RegistroSimulacion, tipo: String, u_max: float = INF) -> Array:
	var secciones: Array = []
	if reg == null or reg.tamano() < 3:
		return secciones

	var t: PackedFloat64Array = reg.columna("t")
	var x: PackedFloat64Array = reg.columna("x")
	var th: PackedFloat64Array = reg.columna("theta")

	match tipo:
		"sin_control":
			secciones.append(_seccion_sin_control(t, x, th))
		"regulador":
			secciones.append(_seccion_regulador(t, x, th, PackedFloat64Array()))
		"seguimiento":
			secciones.append(_seccion_seguimiento(t, x, th, reg.columna("r")))

	if tipo != "sin_control":
		secciones.append(_seccion_indices(t, x, th, reg.columna("r") if reg.tiene("r") else PackedFloat64Array()))
		secciones.append(_seccion_control(t, reg.columna("u"), reg.columna("u_cmd"), u_max))
		var comparacion: Dictionary = _seccion_lineal(reg)
		if not comparacion.is_empty():
			secciones.append(comparacion)

	var criterios: Array = []
	if tipo != "sin_control":
		criterios.append(["Establecimiento", "banda ±2 % del cambio (valor final)"])
		if tipo == "seguimiento":
			criterios.append(["Subida", "10 % → 90 % del cambio de referencia"])
		criterios.append(["Índices", "IAE=∫|e|dt, ISE=∫e²dt, ITAE=∫t|e|dt (trapecio)"])
		criterios.append(["Lineal vs no lineal", "RMSE/rango = RMSE ÷ (máx − mín) de la señal no lineal"])
	criterios.append(["Muestras", "%d, una por paso de integración" % t.size()])
	secciones.append({"titulo": "Criterios", "filas": criterios})
	return secciones


# ------------------------------------------------------------
# Secciones
# ------------------------------------------------------------

static func _seccion_sin_control(t: PackedFloat64Array, x: PackedFloat64Array,
		th: PackedFloat64Array) -> Dictionary:
	var filas: Array = []
	filas.append(["θ inicial", _deg(th[0])])
	var i_caida: int = -1
	for i in range(th.size()):
		if absf(th[i]) >= PI / 2.0:
			i_caida = i
			break
	filas.append(["Tiempo en llegar a |θ| = 90°",
		_s(t[i_caida]) if i_caida >= 0 else "no llegó"])
	var e_th: Array = _extremo_abs(t, th)
	filas.append(["|θ| máximo", "%s (t = %s)" % [_deg(e_th[0]), _s(e_th[1])]])
	var e_x: Array = _extremo_abs(t, x)
	filas.append(["|x| máximo", "%s (t = %s)" % [_m(e_x[0]), _s(e_x[1])]])
	filas.append(["Valores finales", "x = %s,  θ = %s" % [_m(x[-1]), _deg(th[-1])]])
	return {"titulo": "Respuesta (sin control)", "filas": filas}


static func _seccion_regulador(t: PackedFloat64Array, x: PackedFloat64Array,
		th: PackedFloat64Array, _r: PackedFloat64Array) -> Dictionary:
	var filas: Array = []
	var th0: float = th[0]
	filas.append(["θ inicial", _deg(th0)])
	var e_th: Array = _extremo_abs(t, th)
	filas.append(["|θ| máximo", "%s (t = %s)" % [_deg(e_th[0]), _s(e_th[1])]])
	if absf(th0) > 1e-9:
		# Cuanto cruza el pendulo al lado contrario del angulo inicial
		var cruce: float = 0.0
		for v: float in th:
			cruce = maxf(cruce, -signf(th0) * v)
		filas.append(["Sobreimpulso de θ (lado opuesto)", "%s %%  (%s)" % [_num(cruce / absf(th0) * 100.0, 1), _deg(cruce)]])
		filas.append(["Establecimiento de θ (±2 % de θ₀)",
			_s_o_no(_establecimiento(t, th, 0.0, BANDA * absf(th0), 0.0))])
	var e_x: Array = _extremo_abs(t, x)
	filas.append(["|x| máximo", "%s (t = %s)" % [_m(e_x[0]), _s(e_x[1])]])
	var banda_x: float = maxf(BANDA * e_x[0], 1e-3)
	filas.append(["Establecimiento de x (±2 % de |x|máx)",
		_s_o_no(_establecimiento(t, x, 0.0, banda_x, 0.0))])
	filas.append(["Valores finales", "x = %s,  θ = %s" % [_m(x[-1]), _deg(th[-1])]])
	return {"titulo": "Respuesta (regulación a X = 0)", "filas": filas}


static func _seccion_seguimiento(t: PackedFloat64Array, x: PackedFloat64Array,
		th: PackedFloat64Array, r: PackedFloat64Array) -> Dictionary:
	# Ultimo cambio de referencia (escalon)
	var k: int = -1
	for i in range(1, r.size()):
		if absf(r[i] - r[i - 1]) > 1e-12:
			k = i
	if k == -1:
		var sec: Dictionary = _seccion_regulador(t, x, th, r)
		sec.titulo = "Respuesta (sin cambio de referencia)"
		return sec

	var filas: Array = []
	var r0: float = r[k - 1]
	var rf: float = r[k]
	var dr: float = rf - r0
	var sg: float = signf(dr)
	filas.append(["Escalón de referencia", "%s → %s en t = %s" % [_m(r0), _m(rf), _s(t[k])]])

	var t10: float = NAN
	var t90: float = NAN
	var pico: float = 0.0
	var t_pico: float = t[k]
	var inverso: float = 0.0
	for i in range(k, t.size()):
		var avance: float = sg * (x[i] - r0) / absf(dr)   # 0 al inicio, 1 en la referencia
		if is_nan(t10) and avance >= 0.1:
			t10 = t[i]
		if is_nan(t90) and avance >= 0.9:
			t90 = t[i]
		if avance - 1.0 > pico:
			pico = avance - 1.0
			t_pico = t[i]
		inverso = maxf(inverso, -avance)
	filas.append(["Tiempo de subida (10–90 %)",
		_s(t90 - t10) if not (is_nan(t10) or is_nan(t90)) else "no alcanzó el 90 %"])
	filas.append(["Sobreimpulso", "%s %%  (t = %s)" % [_num(pico * 100.0, 1), _s(t_pico)]])
	filas.append(["Respuesta inversa inicial (fase no mínima)", "%s %%" % _num(inverso * 100.0, 1)])
	var ts: float = _establecimiento(t, x, rf, BANDA * absf(dr), t[k])
	filas.append(["Establecimiento (±2 %, desde el escalón)", _s_o_no(ts - t[k] if is_finite(ts) else ts)])
	filas.append(["Error en estado estacionario e = r − x", _num(rf - x[-1], 7) + " m"])
	var e_th: Array = _extremo_abs(t, th)
	filas.append(["|θ| máximo", "%s (t = %s)" % [_deg(e_th[0]), _s(e_th[1])]])
	return {"titulo": "Respuesta al escalón de referencia", "filas": filas}


static func _seccion_indices(t: PackedFloat64Array, x: PackedFloat64Array,
		th: PackedFloat64Array, r: PackedFloat64Array) -> Dictionary:
	var e := PackedFloat64Array()
	e.resize(x.size())
	for i in range(x.size()):
		e[i] = (r[i] - x[i]) if r.size() == x.size() else -x[i]
	var nombre_e: String = "e = r − x [m]" if r.size() == x.size() else "e = −x [m]"
	return {"titulo": "Índices integrales", "filas": [
		["IAE  " + nombre_e, _num(_integral(t, e, 1), 4) + " m·s"],
		["ISE  " + nombre_e, _num(_integral(t, e, 2), 5) + " m²·s"],
		["ITAE " + nombre_e, _num(_integral(t, e, 3), 4) + " m·s²"],
		["IAE  θ [rad]", _num(_integral(t, th, 1), 4) + " rad·s"],
		["ISE  θ [rad]", _num(_integral(t, th, 2), 5) + " rad²·s"],
	]}


static func _seccion_control(t: PackedFloat64Array, u: PackedFloat64Array,
		u_cmd: PackedFloat64Array, u_max: float) -> Dictionary:
	var e_u: Array = _extremo_abs(t, u)
	var e_cmd: Array = _extremo_abs(t, u_cmd)
	var saturado: float = 0.0
	for i in range(1, t.size()):
		if absf(u_cmd[i]) > u_max:
			saturado += t[i] - t[i - 1]
	return {"titulo": "Señal de control", "filas": [
		["|u| máximo aplicado", "%s N (t = %s)" % [_num(e_u[0], 2), _s(e_u[1])]],
		["|u| máximo pedido por el controlador", "%s N (t = %s)" % [_num(e_cmd[0], 2), _s(e_cmd[1])]],
		["Tiempo en saturación (|u| > %s N)" % _num(u_max, 1), _s(saturado)],
		["Energía de control ∫u²dt", _num(_integral(t, u, 2), 2) + " N²·s"],
	]}


# Error entre el modelo no lineal y el lineal en cada variable.
static func _seccion_lineal(reg: RegistroSimulacion) -> Dictionary:
	if not reg.tiene("x_lin"):
		return {}
	var t: PackedFloat64Array = reg.columna("t")
	var pares: Array = [
		["x", "x", "x_lin", 1.0, "m"],
		["θ", "theta", "theta_lin", rad_to_deg(1.0), "°"],
		["x'", "dx", "dx_lin", 1.0, "m/s"],
		["θ'", "dtheta", "dtheta_lin", rad_to_deg(1.0), "°/s"],
		["u", "u", "u_lin", 1.0, "N"],
	]
	var filas: Array = []
	for p: Array in pares:
		if not (reg.tiene(p[1]) and reg.tiene(p[2])):
			continue
		var nl: PackedFloat64Array = reg.columna(p[1])
		var li: PackedFloat64Array = reg.columna(p[2])
		var n: int = 0
		var suma2: float = 0.0
		var dmax: float = 0.0
		var t_dmax: float = 0.0
		var mn: float = INF
		var mx: float = -INF
		for i in range(t.size()):
			if is_nan(li[i]) or is_nan(nl[i]):
				continue
			var d: float = (nl[i] - li[i]) * p[3]
			n += 1
			suma2 += d * d
			if absf(d) > dmax:
				dmax = absf(d)
				t_dmax = t[i]
			mn = minf(mn, nl[i] * p[3])
			mx = maxf(mx, nl[i] * p[3])
		if n == 0:
			return {}
		var rmse: float = sqrt(suma2 / n)
		var rango: float = mx - mn
		var rel: String = "%s %%" % _num(rmse / rango * 100.0, 1) if rango > 1e-12 else "—"
		filas.append(["%s: error máx | RMSE | RMSE/rango" % p[0],
			"%s %s (t = %s) | %s %s | %s" % [_num(dmax, 4), p[4], _s(t_dmax), _num(rmse, 4), p[4], rel]])
	if filas.is_empty():
		return {}
	return {"titulo": "Modelo no lineal vs lineal", "filas": filas}


# ------------------------------------------------------------
# Utilidades numericas
# ------------------------------------------------------------

# modo 1: ∫|y|dt, 2: ∫y²dt, 3: ∫t|y|dt  (regla del trapecio)
static func _integral(t: PackedFloat64Array, y: PackedFloat64Array, modo: int) -> float:
	var s: float = 0.0
	for i in range(1, t.size()):
		var a: float = _f(y[i - 1], t[i - 1], modo)
		var b: float = _f(y[i], t[i], modo)
		if is_nan(a) or is_nan(b):
			continue
		s += 0.5 * (a + b) * (t[i] - t[i - 1])
	return s


static func _f(v: float, tt: float, modo: int) -> float:
	match modo:
		1: return absf(v)
		2: return v * v
		_: return tt * absf(v)


# [max|y|, t en que ocurre]
static func _extremo_abs(t: PackedFloat64Array, y: PackedFloat64Array) -> Array:
	var m: float = 0.0
	var tm: float = 0.0
	for i in range(y.size()):
		if absf(y[i]) > m:
			m = absf(y[i])
			tm = t[i]
	return [m, tm]


# Instante a partir del cual |y - objetivo| <= banda hasta el final.
# INF si al final todavia esta fuera de la banda.
static func _establecimiento(t: PackedFloat64Array, y: PackedFloat64Array, objetivo: float,
		banda: float, desde: float) -> float:
	var ultimo_fuera: int = -1
	for i in range(y.size()):
		if t[i] < desde:
			continue
		if absf(y[i] - objetivo) > banda:
			ultimo_fuera = i
	if ultimo_fuera == y.size() - 1:
		return INF
	if ultimo_fuera == -1:
		return desde
	return t[ultimo_fuera + 1]


# ------------------------------------------------------------
# Formato
# ------------------------------------------------------------

static func _num(v: float, dec: int) -> String:
	if is_nan(v):
		return "—"
	return String.num(v, dec)


static func _s(v: float) -> String:
	return _num(v, 3) + " s"


static func _s_o_no(v: float) -> String:
	return "no se establece" if not is_finite(v) else _s(v)


static func _m(v: float) -> String:
	return _num(v, 4) + " m"


static func _deg(rad: float) -> String:
	return _num(rad_to_deg(rad), 2) + "°"


# Texto para la pagina "Resultados" (BBCode de RichTextLabel)
static func a_bbcode(secciones: Array) -> String:
	var t: PackedStringArray = []
	for s: Dictionary in secciones:
		t.append("[b]%s[/b]" % s.titulo)
		t.append("[table=2]")
		for fila: Array in s.filas:
			t.append("[cell]%s   [/cell][cell][color=#1a1a1a]%s[/color][/cell]" % [fila[0], fila[1]])
		t.append("[/table]")
		t.append("")
	return "\n".join(t)


# Lineas para los metadatos del CSV
static func a_lineas(secciones: Array) -> PackedStringArray:
	var t: PackedStringArray = []
	for s: Dictionary in secciones:
		t.append("--- " + str(s.titulo) + " ---")
		for fila: Array in s.filas:
			t.append("%s: %s" % [fila[0], fila[1]])
	return t

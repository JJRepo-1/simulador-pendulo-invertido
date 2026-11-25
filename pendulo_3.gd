extends Node2D

# ============================================================
# PENDULO INVERTIDO CON SEGUIMIENTO DE TRAYECTORIA (ACCION INTEGRAL)
# ============================================================
# Equivale a codigo_seguimiento.m (modelo lineal aumentado) y
# CodigoSeguimientoLinealANoLineal.m (mismo controlador en el no lineal):
#
#   Xa = [x, θ, x', θ', z],   z' = r - x
#   u  = -Ka * Xa,   Ka = [K, -ki]   (LMI de orden 5 en MATLAB)
#
# La referencia r de la posicion del carro se cambia en escalon con el
# spinbox "Referencia" y el boton "Aceptar". El integrador z elimina el
# error en estado estacionario aunque haya friccion no modelada.
# La planta "real" son las ecuaciones de movimiento de Configuracion;
# en paralelo se simula dXa/dt = Aa*Xa + Ba*u + Br*r para comparar.

const N: int = 5   # orden del sistema aumentado

# ============================================================
# 1. PARAMETROS (se cargan desde el Autoload Globals en _ready)
# ============================================================

var modelo: PenduloModelo = PenduloModelo.new()

# Planta: ecuaciones del usuario (ModeloFormulas) o el modelo de referencia
var planta = null
var planta_status: String = ""
var planta_es_usuario: bool = false

var max_force_newtons: float = 150.0    # Saturacion del actuador [N]

# Ka = [K1, K2, K3, K4, -ki]
var Ka := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0])


# ============================================================
# 2. CONTROLADOR Y CONDICIONES INICIALES
# ============================================================

@export_group("Controlador")
@export var control_enabled: bool = true

@export_group("Condiciones Iniciales")
@export var initial_cart_x_px: float = 0.0   # Posicion inicial [px]
@export var initial_angle_deg: float = 5.0   # Angulo inicial [grados]
@export var simulation_time_s: float = 10.0  # Tiempo de simulacion [s] (t_final en MATLAB)

const MAX_INITIAL_ANGLE_DEG: float = 40.0
const WARNING_ANGLE_DEG: float = 30.0

@export_group("Comparacion con Modelo Lineal")
@export var compare_linear: bool = true


# ============================================================
# 3. CONFIGURACION NUMERICA Y GRAFICA
# ============================================================

@export_group("Integracion Numerica")
@export var max_integration_step: float = 1.0 / 240.0  # Paso maximo RK4 [s]
@export var simulation_speed: float = 1.0

@export_group("Representacion")
@export var pixels_per_meter: float = 100.0

@export_group("Limites de Movimiento")
@export var min_x: float = -300.0  # [px]
@export var max_x: float = 300.0   # [px]


# ============================================================
# 4. VARIABLES DE ESTADO (SI)
# ============================================================
# Planta: [x, θ, x', θ', z], θ = 0 -> pendulo arriba

var is_simulating: bool = false
var sim_time: float = 0.0

var cart_x: float = 0.0
var theta: float = 0.0
var cart_velocity: float = 0.0
var theta_velocity: float = 0.0
var integral_error: float = 0.0     # z = ∫(r - x) dt  [m*s]

var reference_m: float = 0.0        # Referencia r de la posicion [m]
var applied_control_force: float = 0.0

# --- Modelo lineal aumentado ---
var linear_available: bool = false
var linear_status: String = ""
var Aa_lin := PackedFloat64Array()   # 25 valores por filas
var Ba_lin := PackedFloat64Array()   # 5 valores
var linear_state := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0])
var linear_max_angle_gap: float = 0.0

const GRAFICAS_RECT := PanelGraficas.RECT


# ============================================================
# 5. REFERENCIAS A NODOS
# ============================================================

@onready var cart_sprite: Sprite2D = $Carrito
@onready var link_sprite: Sprite2D = $Eslabon
@onready var bob_sprite: Sprite2D = $masa

@onready var input_pos_inicial: SpinBox = $CanvasLayer/VBoxContainer/SpinBox
@onready var input_angulo_inicial: SpinBox = $CanvasLayer/VBoxContainer/angle
@onready var btn_simular: Button = $CanvasLayer/VBoxContainer/Simular
@onready var input_referencia: SpinBox = $CanvasLayer/VBoxContainer/referencia
@onready var btn_aceptar: Button = $CanvasLayer/VBoxContainer/Aceptar

# Creados por codigo
var panel_graficas: PanelGraficas
var btn_graficas: Button
var lbl_angle_warning: Label
var control_tiempo: ControlTiempo
var idx_grafica_u: int = -1
var idx_grafica_e: int = -1
var cambios_referencia: Array = []   # [[t, r], ...] para los metadatos del CSV

# Registro por paso de integracion (metricas y CSV), en SI
var registro := RegistroSimulacion.new(
	PackedStringArray(["t", "x", "theta", "dx", "dtheta", "z",
		"x_lin", "theta_lin", "dx_lin", "dtheta_lin", "z_lin",
		"u", "u_cmd", "u_lin", "r", "e", "e_lin"]),
	PackedStringArray(["s", "m", "rad", "m/s", "rad/s", "m*s",
		"m", "rad", "m/s", "rad/s", "m*s",
		"N", "N", "N", "m", "m", "m"]))
var chk_linear: CheckBox
var lbl_linear: Label
var lbl_plant: Label
var lbl_tracking: Label
var linear_overlay: Node2D


# ============================================================
# 6. INICIALIZACION
# ============================================================

func _ready() -> void:
	_load_parameters()

	if not _validate_parameters():
		set_physics_process(false)
		return

	_load_linear_model()
	_setup_plots()
	_setup_inputs()
	_setup_linear_ui()

	reset_state(input_pos_inicial.value, input_angulo_inicial.value)


func _load_parameters() -> void:
	modelo = Globals.crear_modelo()
	max_force_newtons = Globals.max_force_newtons
	Ka = PackedFloat64Array(Globals.Ka)
	Ka.resize(N)
	_load_plant()


func _load_plant() -> void:
	var r: Dictionary = Globals.crear_modelo_usuario()
	planta_es_usuario = r.ok
	if r.ok:
		planta = r.modelo
		planta_status = "Planta: tus ecuaciones no lineales"
	else:
		planta = modelo
		planta_status = "Planta: modelo de referencia (tus ecuaciones tienen errores)"
		push_warning("Ecuaciones no lineales del usuario con errores; se usa el modelo de referencia.")


func _validate_parameters() -> bool:
	var error_modelo: String = modelo.validar()
	if error_modelo != "":
		push_error(error_modelo)
		return false
	if max_force_newtons <= 0.0:
		push_error("La fuerza maxima debe ser positiva.")
		return false
	if pixels_per_meter <= 0.0 or max_integration_step <= 0.0 or max_x <= min_x:
		push_error("Parametros numericos o de representacion invalidos.")
		return false
	return true


# Evalua Aa y Ba (pestana 3 de Configuracion) con los parametros actuales.
func _load_linear_model() -> void:
	var r: Dictionary = FormulasLineales.evaluar_modelo(
		Globals.lineal_aux, Globals.aumentado_A, Globals.aumentado_B, modelo.parametros(), N)
	linear_available = r.ok
	if r.ok:
		Aa_lin = r.A
		Ba_lin = r.B
		linear_status = "Modelo lineal aumentado listo"
	else:
		Aa_lin = PackedFloat64Array()
		Ba_lin = PackedFloat64Array()
		linear_status = "Aa/Ba con errores: revisa Configuración"


func _setup_plots() -> void:
	panel_graficas = PanelGraficas.new()
	$CanvasLayer.add_child(panel_graficas)
	panel_graficas.position = GRAFICAS_RECT.position
	panel_graficas.size = GRAFICAS_RECT.size
	panel_graficas.fijar_rango(PanelGraficas.IDX_X, min_x / pixels_per_meter, max_x / pixels_per_meter)
	panel_graficas.graficas[PanelGraficas.IDX_X].ref_name = "referencia r"

	# Senal de control u(t) con saturacion y error de seguimiento e(t) = r - x
	idx_grafica_u = panel_graficas.agregar_grafica("Señal de control", "u", "N", Color(0.0, 0.5, 0.5))
	var g_u: RealTimePlot = panel_graficas.graficas[idx_grafica_u]
	g_u.main_name = "u aplicada"
	g_u.limites = PackedFloat64Array([max_force_newtons, -max_force_newtons])
	g_u.limite_nombre = "±u_max"
	idx_grafica_e = panel_graficas.agregar_grafica("Error de seguimiento e = r − x", "e", "m", Color(0.75, 0.0, 0.55))

	panel_graficas.registro = registro
	panel_graficas.metadatos = _metadatos
	panel_graficas.nombre_escena = "seguimiento"

	btn_graficas = Button.new()
	btn_graficas.text = "Mostrar gráficas"
	btn_graficas.focus_mode = Control.FOCUS_NONE
	btn_graficas.pressed.connect(_on_btn_graficas_pressed)
	btn_simular.add_sibling(btn_graficas)


func _on_btn_graficas_pressed() -> void:
	panel_graficas.alternar()
	btn_graficas.text = "Ocultar gráficas" if panel_graficas.visible else "Mostrar gráficas"


func _setup_inputs() -> void:
	input_pos_inicial.min_value = min_x
	input_pos_inicial.max_value = max_x
	input_pos_inicial.step = 1.0
	input_pos_inicial.prefix = "Pos:"
	input_pos_inicial.suffix = "px"
	input_pos_inicial.value = clampf(initial_cart_x_px, min_x, max_x)

	input_angulo_inicial.min_value = -MAX_INITIAL_ANGLE_DEG
	input_angulo_inicial.max_value = MAX_INITIAL_ANGLE_DEG
	input_angulo_inicial.step = 0.1
	input_angulo_inicial.prefix = "Ang:"
	input_angulo_inicial.suffix = "°"
	input_angulo_inicial.value = clampf(initial_angle_deg, -MAX_INITIAL_ANGLE_DEG, MAX_INITIAL_ANGLE_DEG)

	lbl_angle_warning = Label.new()
	lbl_angle_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_angle_warning.custom_minimum_size = Vector2(220.0, 0.0)
	lbl_angle_warning.add_theme_font_size_override("font_size", 13)
	lbl_angle_warning.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2))
	lbl_angle_warning.text = ("⚠ Advertencia: con más de %d° el péndulo sale de la zona donde "
		+ "el modelo lineal es válido; el controlador podría no estabilizarlo.") % int(WARNING_ANGLE_DEG)
	lbl_angle_warning.visible = false
	input_angulo_inicial.add_sibling(lbl_angle_warning)

	# Duracion de la simulacion (t_final de codigo_seguimiento.m)
	control_tiempo = ControlTiempo.new(simulation_time_s)
	lbl_angle_warning.add_sibling(control_tiempo)
	control_tiempo.spin.value_changed.connect(_on_preview_changed)

	input_referencia.min_value = min_x
	input_referencia.max_value = max_x
	input_referencia.step = 1.0
	input_referencia.prefix = "Ref:"
	input_referencia.suffix = "px"

	btn_simular.text = "Simular"
	btn_aceptar.text = "Aceptar referencia"

	btn_simular.pressed.connect(_on_btn_simular_pressed)
	btn_aceptar.pressed.connect(_on_btn_aceptar_pressed)
	input_pos_inicial.value_changed.connect(_on_preview_changed)
	input_angulo_inicial.value_changed.connect(_on_preview_changed)


func _setup_linear_ui() -> void:
	var panel := VBoxContainer.new()
	panel.position = Vector2(540.0, 6.0)
	panel.scale = Vector2(0.5, 0.5)
	$CanvasLayer.add_child(panel)

	lbl_plant = Label.new()
	lbl_plant.add_theme_font_size_override("font_size", 14)
	lbl_plant.text = planta_status
	panel.add_child(lbl_plant)

	chk_linear = CheckBox.new()
	chk_linear.text = "Comparar con modelo lineal"
	chk_linear.button_pressed = compare_linear and linear_available
	chk_linear.disabled = not linear_available
	chk_linear.add_theme_color_override("font_color", Color(1.0, 0.45, 0.85))
	chk_linear.toggled.connect(_on_linear_toggled)
	panel.add_child(chk_linear)

	lbl_linear = Label.new()
	lbl_linear.add_theme_font_size_override("font_size", 14)
	panel.add_child(lbl_linear)

	lbl_tracking = Label.new()
	lbl_tracking.add_theme_font_size_override("font_size", 14)
	lbl_tracking.add_theme_color_override("font_color", Color(0.2, 0.85, 0.4))
	panel.add_child(lbl_tracking)

	linear_overlay = Node2D.new()
	linear_overlay.z_index = 1
	linear_overlay.draw.connect(_draw_linear_overlay)
	add_child(linear_overlay)

	_update_labels()


func _stop_with_error(message: String) -> void:
	is_simulating = false
	_finalizar()
	push_warning(message)
	if lbl_plant:
		lbl_plant.text = message
		lbl_plant.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))


func _linear_enabled() -> bool:
	return linear_available and chk_linear != null and chk_linear.button_pressed


# ============================================================
# 7. INTERFAZ
# ============================================================

func _on_preview_changed(_new_value: float) -> void:
	_update_angle_warning()
	if not is_simulating:
		reset_state(input_pos_inicial.value, input_angulo_inicial.value)


func _on_btn_simular_pressed() -> void:
	input_pos_inicial.apply()
	input_angulo_inicial.apply()
	reset_state(input_pos_inicial.value, input_angulo_inicial.value)
	is_simulating = true


# Nueva referencia de posicion (escalon), como r = A_ref*(t >= t0) en MATLAB.
func _on_btn_aceptar_pressed() -> void:
	input_referencia.apply()
	reference_m = clampf(input_referencia.value, min_x, max_x) / pixels_per_meter
	if is_simulating:
		cambios_referencia.append([sim_time, reference_m])
	_update_labels()
	queue_redraw()


func _on_linear_toggled(_pressed: bool) -> void:
	linear_state = PackedFloat64Array([cart_x, theta, cart_velocity, theta_velocity, integral_error])
	linear_max_angle_gap = 0.0
	_update_labels()
	update_visuals()


func _update_angle_warning() -> void:
	if lbl_angle_warning:
		lbl_angle_warning.visible = absf(input_angulo_inicial.value) > WARNING_ANGLE_DEG


# ============================================================
# 8. REINICIAR ESTADOS
# ============================================================

# La referencia arranca en la posicion inicial (el carro se queda ahi)
# y el integrador en cero.
func reset_state(start_x_px: float, start_angle_deg: float) -> void:
	start_angle_deg = clampf(start_angle_deg, -MAX_INITIAL_ANGLE_DEG, MAX_INITIAL_ANGLE_DEG)
	cart_x = clampf(start_x_px / pixels_per_meter, min_x / pixels_per_meter, max_x / pixels_per_meter)
	cart_velocity = 0.0
	theta = deg_to_rad(start_angle_deg)
	theta_velocity = 0.0
	integral_error = 0.0
	initial_angle_deg = start_angle_deg
	applied_control_force = 0.0
	sim_time = 0.0

	reference_m = cart_x
	input_referencia.set_value_no_signal(cart_x * pixels_per_meter)

	if planta_es_usuario:
		planta.error_ejecucion = ""
	if lbl_plant:
		lbl_plant.text = planta_status
		lbl_plant.add_theme_color_override("font_color",
			Color(0.45, 0.9, 0.5) if planta_es_usuario else Color(1.0, 0.7, 0.25))

	linear_state = PackedFloat64Array([cart_x, theta, 0.0, 0.0, 0.0])
	linear_max_angle_gap = 0.0

	# Graficas en [0, t_final] desde la condicion inicial (t = 0)
	panel_graficas.limpiar()
	panel_graficas.fijar_duracion(control_tiempo.t_final())
	var lin0 := Vector4(NAN, NAN, NAN, NAN)
	if _linear_enabled():
		lin0 = Vector4(linear_state[0], linear_state[1], linear_state[2], linear_state[3])
	panel_graficas.agregar_muestra(sim_time, Vector4(cart_x, theta, cart_velocity, theta_velocity),
		lin0, reference_m)
	cambios_referencia = [[0.0, reference_m]]
	registro.limpiar()
	var X0 := PackedFloat64Array([cart_x, theta, cart_velocity, theta_velocity, integral_error])
	_registrar(sim_time, X0, _linear_enabled())
	_graficar_control(sim_time, X0, _linear_enabled())
	control_tiempo.mostrar(sim_time, false)

	_update_angle_warning()
	_update_labels()
	update_visuals()


# ============================================================
# 9. FISICA PRINCIPAL
# ============================================================

func _physics_process(delta: float) -> void:
	if not is_simulating:
		return

	# El ultimo paso se recorta para terminar exactamente en t_final
	var t_final: float = control_tiempo.t_final()
	var simulation_delta: float = minf(delta * simulation_speed, t_final - sim_time)
	if simulation_delta <= 0.0:
		return

	var substeps: int = maxi(1, int(ceil(simulation_delta / max_integration_step)))
	var h: float = simulation_delta / float(substeps)

	var X := PackedFloat64Array([cart_x, theta, cart_velocity, theta_velocity, integral_error])
	var use_linear: bool = _linear_enabled()

	for i in range(substeps):
		X = _rk4(_plant_derivative, X, h)
		X = _enforce_cart_limits(X)
		if use_linear:
			linear_state = _rk4(_linear_derivative, linear_state, h)
		_registrar(sim_time + h * float(i + 1), X, use_linear)

	if planta_es_usuario and planta.error_ejecucion != "":
		_stop_with_error("Simulación detenida: " + planta.error_ejecucion)
		return
	for v: float in X:
		if not is_finite(v):
			_stop_with_error("Simulación detenida: el estado dejó de ser finito.")
			return

	cart_x = X[0]
	theta = X[1]
	cart_velocity = X[2]
	theta_velocity = X[3]
	integral_error = X[4]
	applied_control_force = _control_force(X)
	sim_time += simulation_delta

	update_visuals()

	var estado := Vector4(cart_x, theta, cart_velocity, theta_velocity)
	if use_linear:
		linear_max_angle_gap = maxf(linear_max_angle_gap, absf(theta - linear_state[1]))
		var lin := Vector4(linear_state[0], linear_state[1], linear_state[2], linear_state[3])
		panel_graficas.agregar_muestra(sim_time, estado, lin, reference_m)
	else:
		panel_graficas.agregar_muestra(sim_time, estado, Vector4(NAN, NAN, NAN, NAN), reference_m)
	_graficar_control(sim_time, X, use_linear)
	_update_labels()

	var terminada: bool = sim_time >= t_final - 1e-9
	control_tiempo.mostrar(sim_time, terminada)
	if terminada:
		is_simulating = false
		_finalizar()


# Una fila del registro: estado no lineal (con z), lineal (o NAN), fuerzas y error.
func _registrar(t: float, X: PackedFloat64Array, use_linear: bool) -> void:
	var u_cmd: float = _control_law(X)
	var u: float = clampf(u_cmd, -max_force_newtons, max_force_newtons)
	var fila: Array = [t, X[0], X[1], X[2], X[3], X[4]]
	if use_linear:
		fila.append_array([linear_state[0], linear_state[1], linear_state[2], linear_state[3], linear_state[4]])
		fila.append_array([u, u_cmd, _control_law(linear_state), reference_m,
			reference_m - X[0], reference_m - linear_state[0]])
	else:
		fila.append_array([NAN, NAN, NAN, NAN, NAN, u, u_cmd, NAN, reference_m, reference_m - X[0], NAN])
	registro.agregar(fila)


func _graficar_control(t: float, X: PackedFloat64Array, use_linear: bool) -> void:
	panel_graficas.graficas[idx_grafica_u].add_sample(t, _control_force(X), NAN,
		_control_law(linear_state) if use_linear else NAN)
	panel_graficas.graficas[idx_grafica_e].add_sample(t, reference_m - X[0], NAN,
		reference_m - linear_state[0] if use_linear else NAN)


func _finalizar() -> void:
	panel_graficas.mostrar_resultados(
		MetricasSimulacion.calcular(registro, "seguimiento", max_force_newtons))


# Condiciones de la prueba para el CSV (para poder reproducir la figura).
func _metadatos() -> PackedStringArray:
	var p: Dictionary = modelo.parametros()
	var m := PackedStringArray()
	m.append("Escena: seguimiento de trayectoria con acción integral, u = -Ka*[x, theta, dx, dtheta, z], z' = r - x")
	m.append("Planta: " + ("ecuaciones del usuario" if planta_es_usuario else "modelo de referencia"))
	m.append("Ecuación del carro: " + Globals.no_lineal_carro)
	m.append("Ecuación del péndulo: " + Globals.no_lineal_pendulo)
	m.append("Parámetros: M=%s kg, m=%s kg, l=%s m, J=%s kg*m^2, g=%s m/s^2, c=%s N*s/m, b=%s N*m*s/rad" % [
		p.M, p.m, p.l, p.J, p.g, p.c, p.b])
	m.append("u_max: %s N" % max_force_newtons)
	m.append("Ka = [K, -ki]: [%s]  (ki = %s)" % [", ".join(Array(Ka).map(func(v): return str(v))), -Ka[4]])
	if linear_available:
		var polos: Array[Vector2] = Algebra.polos(Algebra.lazo_cerrado(Aa_lin, Ba_lin, Ka), N)
		var tp: PackedStringArray = []
		for q: Vector2 in polos:
			tp.append(Algebra.texto_polo(q))
		m.append("Polos de Aa-Ba*Ka (modelo lineal aumentado): " + ", ".join(tp))
	m.append("Condiciones iniciales: x0=%s m, theta0=%s deg, dx0=0, dtheta0=0, z0=0" % [
		registro.columna("x")[0] if registro.tamano() > 0 else 0.0,
		rad_to_deg(registro.columna("theta")[0]) if registro.tamano() > 0 else 0.0])
	var cambios: PackedStringArray = []
	for c: Array in cambios_referencia:
		cambios.append("t=%s s -> r=%s m" % [String.num(c[0], 4), String.num(c[1], 4)])
	m.append("Referencia r (escalones): " + "; ".join(cambios))
	m.append("t_final: %s s" % control_tiempo.t_final())
	m.append("Integrador: Runge-Kutta 4, paso <= %s s (una fila por paso)" % String.num(max_integration_step, 6))
	m.append("Comparación lineal: " + ("sí (dXa/dt = Aa*Xa + Ba*u + Br*r, sin saturación)" if _linear_enabled() else "no"))
	return m


# ============================================================
# 10. INTEGRADOR RUNGE-KUTTA DE CUARTO ORDEN (5 estados)
# ============================================================

func _rk4(f: Callable, X: PackedFloat64Array, h: float) -> PackedFloat64Array:
	var k1: PackedFloat64Array = f.call(X)
	var k2: PackedFloat64Array = f.call(_axpy(X, k1, h * 0.5))
	var k3: PackedFloat64Array = f.call(_axpy(X, k2, h * 0.5))
	var k4: PackedFloat64Array = f.call(_axpy(X, k3, h))
	var out := PackedFloat64Array(X)
	for i in range(N):
		out[i] += (k1[i] + 2.0 * k2[i] + 2.0 * k3[i] + k4[i]) * (h / 6.0)
	return out


# X + a*Y
func _axpy(X: PackedFloat64Array, Y: PackedFloat64Array, a: float) -> PackedFloat64Array:
	var out := PackedFloat64Array(X)
	for i in range(N):
		out[i] += a * Y[i]
	return out


# ============================================================
# 11. CONTROLADOR: u = -Ka * Xa = -K*X + ki*z
# ============================================================

func _control_law(X: PackedFloat64Array) -> float:
	if not control_enabled:
		return 0.0
	return -(
		Ka[0] * X[0] +
		Ka[1] * wrapf(X[1], -PI, PI) +
		Ka[2] * X[2] +
		Ka[3] * X[3] +
		Ka[4] * X[4]
	)


func _control_force(X: PackedFloat64Array) -> float:
	return clampf(_control_law(X), -max_force_newtons, max_force_newtons)


# ============================================================
# 12. MODELOS DINAMICOS
# ============================================================

# Planta no lineal + integrador del error: z' = r - x
func _plant_derivative(X: PackedFloat64Array) -> PackedFloat64Array:
	var d: Vector4 = planta.derivada(Vector4(X[0], X[1], X[2], X[3]), _control_force(X))
	return PackedFloat64Array([d.x, d.y, d.z, d.w, reference_m - X[0]])


# Modelo lineal aumentado: dXa/dt = Aa*Xa + Ba*u + Br*r, Br = [0 0 0 0 1]'
# (misma ley de control, sin saturacion ni topes de pista).
func _linear_derivative(X: PackedFloat64Array) -> PackedFloat64Array:
	var u: float = _control_law(X)
	var d := PackedFloat64Array()
	d.resize(N)
	for i in range(N):
		var s: float = Ba_lin[i] * u
		for j in range(N):
			s += Aa_lin[i * N + j] * X[j]
		d[i] = s
	d[N - 1] += reference_m
	return d


# ============================================================
# 13. LIMITES FISICOS DEL CARRITO
# ============================================================

func _enforce_cart_limits(X: PackedFloat64Array) -> PackedFloat64Array:
	var lower_limit: float = min_x / pixels_per_meter
	var upper_limit: float = max_x / pixels_per_meter
	if X[0] < lower_limit:
		X[0] = lower_limit
		X[2] = maxf(X[2], 0.0)
	elif X[0] > upper_limit:
		X[0] = upper_limit
		X[2] = minf(X[2], 0.0)
	return X


# ============================================================
# 14. REPRESENTACION GRAFICA
# ============================================================

func update_visuals() -> void:
	var pivot: Vector2 = Vector2(cart_x * pixels_per_meter, cart_sprite.position.y)
	cart_sprite.position = pivot

	var arm_length_px: float = modelo.l * pixels_per_meter
	var bob_offset: Vector2 = Vector2(sin(theta), -cos(theta)) * arm_length_px

	bob_sprite.position = pivot + bob_offset
	link_sprite.position = pivot + bob_offset * 0.5
	link_sprite.rotation = theta - PI

	if link_sprite.texture:
		var tex_height: float = float(link_sprite.texture.get_height())
		if tex_height > 0.0:
			link_sprite.scale.y = arm_length_px / tex_height

	queue_redraw()
	if linear_overlay:
		linear_overlay.queue_redraw()


func _update_labels() -> void:
	if lbl_linear == null:
		return
	if not linear_available:
		lbl_linear.text = linear_status
		lbl_linear.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	elif not chk_linear.button_pressed:
		lbl_linear.text = linear_status
		lbl_linear.remove_theme_color_override("font_color")
	else:
		lbl_linear.text = "Δθ actual: %.2f°   máx: %.2f°" % [
			rad_to_deg(absf(theta - linear_state[1])), rad_to_deg(linear_max_angle_gap)]
		lbl_linear.add_theme_color_override("font_color", Color(1.0, 0.45, 0.85))
	lbl_tracking.text = "r = %.2f m    error e = r − x = %.3f m" % [reference_m, reference_m - cart_x]


func _draw_linear_overlay() -> void:
	if not _linear_enabled():
		return
	var color := Color(1.0, 0.45, 0.85, 0.85)
	var track_y: float = cart_sprite.position.y
	var pivot := Vector2(linear_state[0] * pixels_per_meter, track_y)
	var cart_size := Vector2(32.0, 32.0)
	if cart_sprite.texture:
		cart_size = cart_sprite.texture.get_size() * cart_sprite.scale
	linear_overlay.draw_rect(Rect2(pivot - cart_size * 0.5, cart_size), color, false, 2.0)
	var tip: Vector2 = pivot + Vector2(sin(linear_state[1]), -cos(linear_state[1])) * modelo.l * pixels_per_meter
	linear_overlay.draw_line(pivot, tip, color, 2.0)
	linear_overlay.draw_circle(tip, 5.0, color)


func _draw() -> void:
	if not cart_sprite:
		return
	var track_y: float = cart_sprite.position.y
	var color_pista := Color(0.6, 0.6, 0.6, 0.35)
	var color_limite := Color(0.95, 0.25, 0.25, 0.95)
	var color_ref := Color(0.2, 0.85, 0.4, 0.95)

	draw_line(Vector2(min_x, track_y), Vector2(max_x, track_y), color_pista, 2.0)

	var alto_tope: float = 28.0
	for limit_x: float in [min_x, max_x]:
		draw_line(Vector2(limit_x, track_y - alto_tope), Vector2(limit_x, track_y + alto_tope), color_limite, 4.0)
		var dir: float = -1.0 if limit_x == min_x else 1.0
		draw_line(Vector2(limit_x, track_y - alto_tope), Vector2(limit_x + 8.0 * dir, track_y - alto_tope), color_limite, 3.0)
		draw_line(Vector2(limit_x, track_y + alto_tope), Vector2(limit_x + 8.0 * dir, track_y + alto_tope), color_limite, 3.0)

	# Referencia r (linea verde, como en la animacion de MATLAB)
	var ref_px: float = reference_m * pixels_per_meter
	draw_dashed_line(Vector2(ref_px, track_y - 60.0), Vector2(ref_px, track_y + 25.0), color_ref, 2.0, 6.0)
	var punta := Vector2(ref_px, track_y + 24.0)
	draw_colored_polygon(PackedVector2Array([
		punta, punta + Vector2(-8.0, 14.0), punta + Vector2(8.0, 14.0)]), color_ref)

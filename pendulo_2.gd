extends Node2D

# ============================================================
# PENDULO INVERTIDO CON CONTROL LINEAL POR REALIMENTACION DE ESTADOS
# ============================================================
# Equivale a codigo4.m (modelo lineal) y pruebaCodigo4vnolineal.m
# (el mismo controlador aplicado al modelo no lineal):
#
#   u = -K * X,   X = [x, theta, x', theta']
#
# El controlador lleva el sistema al equilibrio X = 0 (carro en x = 0,
# pendulo vertical) desde la posicion y el angulo iniciales asignados.
# La planta "real" son las ecuaciones de movimiento escritas en
# Configuracion; en paralelo se simula dX/dt = A*X + B*u para comparar.

# ============================================================
# 1. PARAMETROS (se cargan desde el Autoload Globals en _ready)
# ============================================================

# Parametros fisicos (M, m, l, J, g, c, b) y modelo de referencia
var modelo: PenduloModelo = PenduloModelo.new()

# Planta que se simula: las ecuaciones no lineales del usuario
# (ModeloFormulas) o, si tienen errores, el modelo de referencia.
var planta = null
var planta_status: String = ""
var planta_es_usuario: bool = false

var max_force_newtons: float = 150.0    # Saturacion del actuador [N]

# K = [kx, ktheta, kdx, kdtheta], calculada en MATLAB (LMI).
# Debe recalcularse manualmente si cambian los parametros fisicos.
var K: Vector4 = Vector4.ZERO


# ============================================================
# 2. CONTROLADOR Y CONDICIONES INICIALES
# ============================================================

@export_group("Controlador Lineal")
@export var control_enabled: bool = true

@export_group("Condiciones Iniciales")
@export var initial_cart_x_px: float = 0.0   # Posicion inicial [px]
@export var initial_angle_deg: float = 20.0  # Angulo inicial [grados]

# Angulo inicial maximo que se puede asignar y umbral de la advertencia
const MAX_INITIAL_ANGLE_DEG: float = 40.0
const WARNING_ANGLE_DEG: float = 30.0

@export_group("Comparacion con Modelo Lineal")
# Simula en paralelo dX/dt = A*X + B*u con las A y B escritas en Configuracion
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
# X = [x, theta, x_dot, theta_dot], theta = 0 -> pendulo arriba

var is_simulating: bool = false
var sim_time: float = 0.0   # Tiempo de simulacion desde "Simular" [s]

# Zona de pantalla del panel de graficas (coordenadas de la ventana 720x380):
# a la derecha de los controles, para no tapar el boton Simular.
const GRAFICAS_RECT := Rect2(148.0, 58.0, 562.0, 238.0)

var cart_x: float = 0.0
var theta: float = 0.0
var cart_velocity: float = 0.0
var theta_velocity: float = 0.0

# Fuerza de control aplicada al final del ultimo paso [N]
var applied_control_force: float = 0.0

# --- Modelo lineal ---
var linear_available: bool = false
var linear_status: String = ""
var A_lin := PackedFloat64Array()   # 16 valores por filas
var B_lin := PackedFloat64Array()   # 4 valores
var linear_state: Vector4 = Vector4.ZERO
var linear_max_angle_gap: float = 0.0  # max |theta_nl - theta_lin| [rad]


# ============================================================
# 5. REFERENCIAS A NODOS
# ============================================================

@onready var cart_sprite: Sprite2D = $Carrito
@onready var link_sprite: Sprite2D = $Eslabon
@onready var bob_sprite: Sprite2D = $masa

@onready var input_pos_inicial: SpinBox = $CanvasLayer/VBoxContainer/SpinBox
@onready var input_angulo_inicial: SpinBox = $CanvasLayer/VBoxContainer/angle
@onready var btn_simular: Button = $CanvasLayer/VBoxContainer/Simular

# Creados por codigo
var panel_graficas: PanelGraficas
var btn_graficas: Button
var lbl_angle_warning: Label
var chk_linear: CheckBox
var lbl_linear: Label
var lbl_plant: Label
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
	K = Globals.K
	_load_plant()


# Planta no lineal: ecuaciones del usuario si compilan, si no la referencia.
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
	if pixels_per_meter <= 0.0:
		push_error("pixels_per_meter debe ser positivo.")
		return false
	if max_integration_step <= 0.0:
		push_error("El paso de integracion debe ser positivo.")
		return false
	if max_x <= min_x:
		push_error("El limite maximo debe ser mayor que el minimo.")
		return false
	return true


# Evalua las formulas de A y B (Configuracion) con los parametros actuales.
func _load_linear_model() -> void:
	var r: Dictionary = FormulasLineales.evaluar_modelo(
		Globals.lineal_aux, Globals.lineal_A, Globals.lineal_B, modelo.parametros())

	linear_available = r.ok
	if r.ok:
		A_lin = r.A
		B_lin = r.B
		linear_status = "Modelo lineal listo"
	else:
		A_lin = PackedFloat64Array()
		B_lin = PackedFloat64Array()
		linear_status = "A/B con errores: revisa Configuración"


# Panel desplegable con las graficas de x, θ, x', θ' (una a la vez).
# Se abre con el boton "Gráficas" que queda debajo de "Simular".
func _setup_plots() -> void:
	panel_graficas = PanelGraficas.new()
	$CanvasLayer.add_child(panel_graficas)
	panel_graficas.position = GRAFICAS_RECT.position
	panel_graficas.size = GRAFICAS_RECT.size

	# x en escala fija (toda la pista); el resto se ajusta a los datos
	panel_graficas.fijar_rango(PanelGraficas.IDX_X, min_x / pixels_per_meter, max_x / pixels_per_meter)
	panel_graficas.graficas[PanelGraficas.IDX_X].ref_name = "equilibrio"

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

	# Advertencia de seguridad debajo del angulo inicial
	lbl_angle_warning = Label.new()
	lbl_angle_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_angle_warning.custom_minimum_size = Vector2(220.0, 0.0)
	lbl_angle_warning.add_theme_font_size_override("font_size", 13)
	lbl_angle_warning.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2))
	lbl_angle_warning.text = ("⚠ Advertencia: con más de %d° el péndulo sale de la zona donde "
		+ "el modelo lineal es válido; el controlador podría no estabilizarlo.") % int(WARNING_ANGLE_DEG)
	lbl_angle_warning.visible = false
	input_angulo_inicial.add_sibling(lbl_angle_warning)

	btn_simular.text = "Simular"

	if not btn_simular.pressed.is_connected(_on_btn_simular_pressed):
		btn_simular.pressed.connect(_on_btn_simular_pressed)
	if not input_pos_inicial.value_changed.is_connected(_on_preview_changed):
		input_pos_inicial.value_changed.connect(_on_preview_changed)
	if not input_angulo_inicial.value_changed.is_connected(_on_preview_changed):
		input_angulo_inicial.value_changed.connect(_on_preview_changed)


# Casilla, estado y "fantasma" del modelo lineal.
func _setup_linear_ui() -> void:
	var panel := VBoxContainer.new()
	panel.position = Vector2(540.0, 19.0)
	panel.scale = Vector2(0.5, 0.5)
	$CanvasLayer.add_child(panel)

	lbl_plant = Label.new()
	lbl_plant.add_theme_font_size_override("font_size", 14)
	lbl_plant.add_theme_color_override("font_color",
		Color(0.45, 0.9, 0.5) if planta_es_usuario else Color(1.0, 0.7, 0.25))
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

	# Nodo dibujado encima de los sprites para el pendulo lineal
	linear_overlay = Node2D.new()
	linear_overlay.z_index = 1
	linear_overlay.draw.connect(_draw_linear_overlay)
	add_child(linear_overlay)

	_update_linear_label()


func _stop_with_error(message: String) -> void:
	is_simulating = false
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


func _on_linear_toggled(_pressed: bool) -> void:
	# Al activar a mitad de simulacion, el lineal arranca desde el estado real
	linear_state = Vector4(cart_x, theta, cart_velocity, theta_velocity)
	linear_max_angle_gap = 0.0
	_update_linear_label()
	update_visuals()


func _update_angle_warning() -> void:
	if lbl_angle_warning:
		lbl_angle_warning.visible = absf(input_angulo_inicial.value) > WARNING_ANGLE_DEG


# ============================================================
# 8. REINICIAR ESTADOS
# ============================================================

func reset_state(start_x_px: float, start_angle_deg: float) -> void:
	start_angle_deg = clampf(start_angle_deg, -MAX_INITIAL_ANGLE_DEG, MAX_INITIAL_ANGLE_DEG)
	cart_x = clampf(
		start_x_px / pixels_per_meter,
		min_x / pixels_per_meter,
		max_x / pixels_per_meter
	)
	cart_velocity = 0.0
	theta = deg_to_rad(start_angle_deg)
	theta_velocity = 0.0
	initial_angle_deg = start_angle_deg
	applied_control_force = 0.0

	# Limpiar un error de simulacion anterior de las ecuaciones del usuario
	if planta_es_usuario:
		planta.error_ejecucion = ""
	if lbl_plant:
		lbl_plant.text = planta_status
		lbl_plant.add_theme_color_override("font_color",
			Color(0.45, 0.9, 0.5) if planta_es_usuario else Color(1.0, 0.7, 0.25))

	# El modelo lineal parte de las mismas condiciones iniciales
	linear_state = Vector4(cart_x, theta, 0.0, 0.0)
	linear_max_angle_gap = 0.0

	sim_time = 0.0
	panel_graficas.limpiar()

	_update_angle_warning()
	_update_linear_label()
	update_visuals()


# ============================================================
# 9. FISICA PRINCIPAL
# ============================================================

func _physics_process(delta: float) -> void:
	if not is_simulating:
		return

	var simulation_delta: float = delta * simulation_speed
	if simulation_delta <= 0.0:
		return

	# Sub-pasos para mejorar la estabilidad numerica
	var substeps: int = maxi(1, int(ceil(simulation_delta / max_integration_step)))
	var h: float = simulation_delta / float(substeps)

	var state: Vector4 = Vector4(cart_x, theta, cart_velocity, theta_velocity)
	var use_linear: bool = _linear_enabled()

	for _i in range(substeps):
		state = _rk4_step(state, h)
		state = _enforce_cart_limits(state)
		if use_linear:
			linear_state = _rk4_step_linear(linear_state, h)

	# Si las ecuaciones del usuario fallan (division entre cero, valores no
	# finitos), se detiene la simulacion y se informa en pantalla.
	if planta_es_usuario and planta.error_ejecucion != "":
		_stop_with_error("Simulación detenida: " + planta.error_ejecucion)
		return
	if not (is_finite(state.x) and is_finite(state.y) and is_finite(state.z) and is_finite(state.w)):
		_stop_with_error("Simulación detenida: el estado dejó de ser finito.")
		return

	cart_x = state.x
	theta = state.y
	cart_velocity = state.z
	theta_velocity = state.w
	applied_control_force = _control_force(state)

	sim_time += simulation_delta
	update_visuals()

	# Equilibrio x = 0 como referencia en la grafica de posicion
	if use_linear:
		linear_max_angle_gap = maxf(linear_max_angle_gap, absf(theta - linear_state.y))
		panel_graficas.agregar_muestra(sim_time, state, linear_state, 0.0)
		_update_linear_label()
	else:
		panel_graficas.agregar_muestra(sim_time, state, Vector4(NAN, NAN, NAN, NAN), 0.0)


# ============================================================
# 10. INTEGRADORES RUNGE-KUTTA DE CUARTO ORDEN
# ============================================================

func _rk4_step(state: Vector4, h: float) -> Vector4:
	var k1: Vector4 = _state_derivative(state)
	var k2: Vector4 = _state_derivative(state + k1 * (h * 0.5))
	var k3: Vector4 = _state_derivative(state + k2 * (h * 0.5))
	var k4: Vector4 = _state_derivative(state + k3 * h)
	return state + (k1 + k2 * 2.0 + k3 * 2.0 + k4) * (h / 6.0)


func _rk4_step_linear(state: Vector4, h: float) -> Vector4:
	var k1: Vector4 = _linear_derivative(state)
	var k2: Vector4 = _linear_derivative(state + k1 * (h * 0.5))
	var k3: Vector4 = _linear_derivative(state + k2 * (h * 0.5))
	var k4: Vector4 = _linear_derivative(state + k3 * h)
	return state + (k1 + k2 * 2.0 + k3 * 2.0 + k4) * (h / 6.0)


# ============================================================
# 11. CONTROLADOR LINEAL: u = -K * X
# ============================================================

func _control_law(state: Vector4) -> float:
	if not control_enabled:
		return 0.0
	return -(
		K.x * state.x +
		K.y * wrapf(state.y, -PI, PI) +
		K.z * state.z +
		K.w * state.w
	)


# Fuerza que recibe la planta no lineal: ley de control con saturacion.
func _control_force(state: Vector4) -> float:
	return clampf(_control_law(state), -max_force_newtons, max_force_newtons)


# ============================================================
# 12. MODELOS DINAMICOS
# ============================================================

# Planta no lineal: ecuaciones del usuario o modelo de referencia
func _state_derivative(state: Vector4) -> Vector4:
	return planta.derivada(state, _control_force(state))


# Modelo lineal: dX/dt = A*X + B*u, con la misma ley de control pero sin
# saturacion ni topes de pista (lo que "predice" el diseno lineal, codigo4.m).
func _linear_derivative(state: Vector4) -> Vector4:
	var u: float = _control_law(state)
	var X: Array[float] = [state.x, state.y, state.z, state.w]
	var d: Array[float] = [0.0, 0.0, 0.0, 0.0]
	for i in range(4):
		var s: float = B_lin[i] * u
		for j in range(4):
			s += A_lin[i * 4 + j] * X[j]
		d[i] = s
	return Vector4(d[0], d[1], d[2], d[3])


# ============================================================
# 13. LIMITES FISICOS DEL CARRITO
# ============================================================

func _enforce_cart_limits(state: Vector4) -> Vector4:
	var lower_limit: float = min_x / pixels_per_meter
	var upper_limit: float = max_x / pixels_per_meter

	if state.x < lower_limit:
		state.x = lower_limit
		if state.z < 0.0:
			state.z = 0.0
	elif state.x > upper_limit:
		state.x = upper_limit
		if state.z > 0.0:
			state.z = 0.0

	return state


# ============================================================
# 14. REPRESENTACION GRAFICA
# ============================================================

func update_visuals() -> void:
	var pivot: Vector2 = Vector2(cart_x * pixels_per_meter, cart_sprite.position.y)
	cart_sprite.position = pivot

	# theta se mide desde la vertical superior; en Godot +Y apunta hacia abajo.
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


func _update_linear_label() -> void:
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
			rad_to_deg(absf(theta - linear_state.y)), rad_to_deg(linear_max_angle_gap)]
		lbl_linear.add_theme_color_override("font_color", Color(1.0, 0.45, 0.85))


# Pendulo "fantasma" del modelo lineal, dibujado encima de los sprites.
func _draw_linear_overlay() -> void:
	if not _linear_enabled():
		return

	var color := Color(1.0, 0.45, 0.85, 0.85)
	var track_y: float = cart_sprite.position.y
	var pivot := Vector2(linear_state.x * pixels_per_meter, track_y)

	var cart_size := Vector2(32.0, 32.0)
	if cart_sprite.texture:
		cart_size = cart_sprite.texture.get_size() * cart_sprite.scale
	linear_overlay.draw_rect(Rect2(pivot - cart_size * 0.5, cart_size), color, false, 2.0)

	var tip: Vector2 = pivot + Vector2(sin(linear_state.y), -cos(linear_state.y)) * modelo.l * pixels_per_meter
	linear_overlay.draw_line(pivot, tip, color, 2.0)
	linear_overlay.draw_circle(tip, 5.0, color)


func _draw() -> void:
	if not cart_sprite:
		return

	var track_y: float = cart_sprite.position.y

	var color_pista := Color(0.6, 0.6, 0.6, 0.35)
	var color_limite := Color(0.95, 0.25, 0.25, 0.95)
	var color_equilibrio := Color(0.2, 0.85, 0.4, 0.95)

	# 1. Pista entre los limites
	draw_line(Vector2(min_x, track_y), Vector2(max_x, track_y), color_pista, 2.0)

	# 2. Topes en los limites de recorrido
	var alto_tope: float = 28.0
	for limit_x: float in [min_x, max_x]:
		draw_line(
			Vector2(limit_x, track_y - alto_tope),
			Vector2(limit_x, track_y + alto_tope),
			color_limite, 4.0
		)
		var dir: float = -1.0 if limit_x == min_x else 1.0
		draw_line(
			Vector2(limit_x, track_y - alto_tope),
			Vector2(limit_x + 8.0 * dir, track_y - alto_tope),
			color_limite, 3.0
		)
		draw_line(
			Vector2(limit_x, track_y + alto_tope),
			Vector2(limit_x + 8.0 * dir, track_y + alto_tope),
			color_limite, 3.0
		)

	# 3. Punto de equilibrio al que lleva el controlador (x = 0)
	draw_dashed_line(
		Vector2(0.0, track_y - 60.0),
		Vector2(0.0, track_y + 25.0),
		color_equilibrio, 2.0, 6.0
	)
	var punta := Vector2(0.0, track_y + 24.0)
	draw_colored_polygon(PackedVector2Array([
		punta,
		punta + Vector2(-8.0, 14.0),
		punta + Vector2(8.0, 14.0)
	]), color_equilibrio)

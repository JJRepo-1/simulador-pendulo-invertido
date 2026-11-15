extends Node2D

# ============================================================
# 1. PARAMETROS FISICOS (SISTEMA INTERNACIONAL)
# ============================================================
# Se cargan desde el Autoload Globals en _ready() (unica fuente
# de verdad, editable desde la pantalla de Configuracion).

var cart_mass: float = 2.0              # M [kg]
var bob_mass: float = 0.2               # m [kg]
var arm_length: float = 0.5             # l [m]
var inertia: float = 0.05               # J [kg*m^2]
var gravity: float = 9.81               # g [m/s^2]
var cart_viscous_friction: float = 0.10 # [N*s/m]
var pivot_viscous_damping: float = 0.005 # [N*m*s/rad]
var max_force_newtons: float = 150.0    # Saturacion del actuador [N]

# K = [kx, ktheta, kdx, kdtheta], calculada en MATLAB (LMI).
# Debe recalcularse manualmente si cambian los parametros fisicos.
var K: Vector4 = Vector4.ZERO


# ============================================================
# 2. CONTROLADOR Y TRAYECTORIA
# ============================================================

@export_group("Controlador Lineal")
@export var control_enabled: bool = true
# Prealimentacion u_ff = (M+m)*ddx_ref + c*dx_ref
@export var use_feedforward: bool = true

@export_group("Condiciones Iniciales")
@export var initial_cart_x_px: float = 0.0   # Posicion inicial [px]
@export var initial_angle_deg: float = 20.0  # Perturbacion angular [grados]

@export_group("Seguimiento en Tiempo Real")
@export var move_duration: float = 2.0       # Tiempo [s] para llegar al nuevo punto

# Variables internas de la trayectoria polinomica de 5o orden (metros)
var traj_time: float = 0.0
var traj_duration: float = 1.0
var traj_target_m: float = 0.0
var poly_c: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]


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

var cart_x: float = 0.0
var theta: float = 0.0
var cart_velocity: float = 0.0
var theta_velocity: float = 0.0

# Fuerza de control aplicada al final del ultimo paso [N]
var applied_control_force: float = 0.0


# ============================================================
# 5. REFERENCIAS A NODOS
# ============================================================

@onready var cart_sprite: Sprite2D = $Carrito
@onready var link_sprite: Sprite2D = $Eslabon
@onready var bob_sprite: Sprite2D = $masa

@onready var input_pos_inicial: SpinBox = $CanvasLayer/VBoxContainer/SpinBox
@onready var input_angulo_inicial: SpinBox = $CanvasLayer/VBoxContainer/angle
@onready var input_nueva_pos: SpinBox = $CanvasLayer/VBoxContainer/SpinBox2
@onready var btn_simular: Button = $CanvasLayer/VBoxContainer/Simular
@onready var btn_mover: Button = $CanvasLayer/VBoxContainer/Button

@onready var plot_pos: RealTimePlot = $CanvasLayer/plots/Control
@onready var plot_angle: RealTimePlot = $CanvasLayer/plots/Control3
@onready var plot_vel: RealTimePlot = $CanvasLayer/plots/Control4
@onready var plot_ang_vel: RealTimePlot = $CanvasLayer/plots/Control2


# ============================================================
# 6. INICIALIZACION
# ============================================================

func _ready() -> void:
	_load_parameters()

	if not _validate_parameters():
		set_physics_process(false)
		return

	_setup_plots()
	_setup_inputs()

	reset_state(input_pos_inicial.value, input_angulo_inicial.value)


func _load_parameters() -> void:
	cart_mass = Globals.cart_mass
	bob_mass = Globals.bob_mass
	arm_length = Globals.arm_length
	inertia = Globals.inertia
	gravity = Globals.gravity
	cart_viscous_friction = Globals.cart_viscous_friction
	pivot_viscous_damping = Globals.pivot_viscous_damping
	max_force_newtons = Globals.max_force_newtons
	K = Globals.K


func _validate_parameters() -> bool:
	if pixels_per_meter <= 0.0:
		push_error("pixels_per_meter debe ser positivo.")
		return false
	if arm_length <= 0.0 or cart_mass <= 0.0 or bob_mass <= 0.0:
		push_error("Las masas y la longitud deben ser positivas.")
		return false
	if inertia < 0.0:
		push_error("El momento de inercia no puede ser negativo.")
		return false
	if cart_viscous_friction < 0.0 or pivot_viscous_damping < 0.0:
		push_error("Los coeficientes de friccion no pueden ser negativos.")
		return false
	if max_force_newtons <= 0.0:
		push_error("La fuerza maxima debe ser positiva.")
		return false
	if max_integration_step <= 0.0:
		push_error("El paso de integracion debe ser positivo.")
		return false
	if max_x <= min_x:
		push_error("El limite maximo debe ser mayor que el minimo.")
		return false
	return true


func _setup_plots() -> void:
	plot_pos.title = "Posición Carro (x)"
	plot_pos.unit = "m"
	plot_pos.line_color = Color(0.25, 0.85, 1.0)
	plot_pos.auto_scale = false
	plot_pos.y_min = min_x / pixels_per_meter
	plot_pos.y_max = max_x / pixels_per_meter

	plot_angle.title = "Ángulo Péndulo (θ)"
	plot_angle.unit = "°"
	plot_angle.line_color = Color(1.0, 0.75, 0.2)
	plot_angle.auto_scale = false
	plot_angle.y_min = -40.0
	plot_angle.y_max = 40.0

	plot_vel.title = "Velocidad Carro (dx)"
	plot_vel.unit = "m/s"
	plot_vel.line_color = Color(0.75, 0.45, 1.0)
	plot_vel.auto_scale = false
	plot_vel.y_min = -3.0
	plot_vel.y_max = 3.0

	plot_ang_vel.title = "Vel. Angular (dθ)"
	plot_ang_vel.unit = "°/s"
	plot_ang_vel.line_color = Color(1.0, 0.35, 0.45)
	plot_ang_vel.auto_scale = false
	plot_ang_vel.y_min = -200.0
	plot_ang_vel.y_max = 200.0


func _setup_inputs() -> void:
	input_pos_inicial.min_value = min_x
	input_pos_inicial.max_value = max_x
	input_pos_inicial.step = 1.0
	input_pos_inicial.prefix = "Pos:"
	input_pos_inicial.suffix = "px"
	input_pos_inicial.value = clampf(initial_cart_x_px, min_x, max_x)

	input_angulo_inicial.min_value = -20.0
	input_angulo_inicial.max_value = 20.0
	input_angulo_inicial.step = 1.0
	input_angulo_inicial.prefix = "Ang:"
	input_angulo_inicial.suffix = "°"
	input_angulo_inicial.value = initial_angle_deg

	input_nueva_pos.min_value = min_x
	input_nueva_pos.max_value = max_x
	input_nueva_pos.step = 1.0
	input_nueva_pos.prefix = "Ref:"
	input_nueva_pos.suffix = "px"
	input_nueva_pos.value = input_pos_inicial.value

	btn_simular.text = "Simular"
	btn_mover.text = "Ir a posición"

	if not btn_simular.pressed.is_connected(_on_btn_simular_pressed):
		btn_simular.pressed.connect(_on_btn_simular_pressed)
	if not input_pos_inicial.value_changed.is_connected(_on_preview_changed):
		input_pos_inicial.value_changed.connect(_on_preview_changed)
	if not input_angulo_inicial.value_changed.is_connected(_on_preview_changed):
		input_angulo_inicial.value_changed.connect(_on_preview_changed)


# ============================================================
# 7. INTERFAZ
# ============================================================

func _on_preview_changed(_new_value: float) -> void:
	if not is_simulating:
		reset_state(input_pos_inicial.value, input_angulo_inicial.value)


func _on_btn_simular_pressed() -> void:
	input_pos_inicial.apply()
	input_angulo_inicial.apply()
	reset_state(input_pos_inicial.value, input_angulo_inicial.value)
	is_simulating = true


# Nueva referencia: genera un polinomio de 5o orden desde el estado
# actual de la referencia (x0, v0, a0) hasta (xf, 0, 0) en T segundos.
func _on_button_pressed() -> void:
	if not is_simulating:
		return

	input_nueva_pos.apply()
	var new_target_px: float = clampf(input_nueva_pos.value, min_x, max_x)
	var xf: float = new_target_px / pixels_per_meter

	var current_ref: Vector3 = _evaluate_trajectory(traj_time)
	var x0: float = current_ref.x
	var v0: float = current_ref.y
	var a0: float = current_ref.z

	var T: float = maxf(move_duration, 0.2)
	var T2: float = T * T
	var T3: float = T2 * T
	var T4: float = T3 * T
	var T5: float = T4 * T

	var c0: float = x0
	var c1: float = v0
	var c2: float = 0.5 * a0

	var dx: float = xf - (c0 + c1 * T + c2 * T2)
	var dv: float = -(c1 + 2.0 * c2 * T)
	var da: float = -(2.0 * c2)

	var c3: float = (10.0 * dx - 4.0 * dv * T + 0.5 * da * T2) / T3
	var c4: float = (-15.0 * dx + 7.0 * dv * T - da * T2) / T4
	var c5: float = (6.0 * dx - 3.0 * dv * T + 0.5 * da * T2) / T5

	poly_c = [c0, c1, c2, c3, c4, c5]
	traj_target_m = xf
	traj_duration = T
	traj_time = 0.0


# ============================================================
# 8. REINICIAR ESTADOS
# ============================================================

func reset_state(start_x_px: float, start_angle_deg: float) -> void:
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

	# Referencia en reposo sobre la posicion inicial
	traj_target_m = cart_x
	traj_time = 0.0
	traj_duration = 1.0
	poly_c = [cart_x, 0.0, 0.0, 0.0, 0.0, 0.0]
	input_nueva_pos.value = cart_x * pixels_per_meter

	plot_pos.clear()
	plot_angle.clear()
	plot_vel.clear()
	plot_ang_vel.clear()

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

	for _i in range(substeps):
		state = _rk4_step(state, traj_time, h)
		state = _enforce_cart_limits(state)
		traj_time += h

	cart_x = state.x
	theta = state.y
	cart_velocity = state.z
	theta_velocity = state.w
	applied_control_force = _control_force(state, traj_time)

	update_visuals()

	var ref_x_actual: float = _evaluate_trajectory(traj_time).x
	plot_pos.add_sample(cart_x, ref_x_actual)
	plot_angle.add_sample(rad_to_deg(theta))
	plot_vel.add_sample(cart_velocity)
	plot_ang_vel.add_sample(rad_to_deg(theta_velocity))


# ============================================================
# 10. INTEGRADOR RUNGE-KUTTA DE CUARTO ORDEN
# ============================================================

func _rk4_step(state: Vector4, t: float, h: float) -> Vector4:
	var k1: Vector4 = _state_derivative(state, t)
	var k2: Vector4 = _state_derivative(state + k1 * (h * 0.5), t + h * 0.5)
	var k3: Vector4 = _state_derivative(state + k2 * (h * 0.5), t + h * 0.5)
	var k4: Vector4 = _state_derivative(state + k3 * h, t + h)
	return state + (k1 + k2 * 2.0 + k3 * 2.0 + k4) * (h / 6.0)


# ============================================================
# 11. CONTROLADOR LINEAL (realimentacion de estado por error)
# ============================================================
# u = u_ff - K * (X - X_ref), con X_ref = [x_ref, 0, dx_ref, 0].
# Equivale a u = -K*X + Nbar*r de MATLAB (Nbar = K(1)).

func _control_force(state: Vector4, t: float) -> float:
	if not control_enabled:
		return 0.0

	var ref: Vector3 = _evaluate_trajectory(t)

	var x_error: float = state.x - ref.x
	var theta_error: float = wrapf(state.y, -PI, PI)
	var dx_error: float = state.z - ref.y
	var dtheta_error: float = state.w

	var u_ff: float = 0.0
	if use_feedforward:
		u_ff = (cart_mass + bob_mass) * ref.z + cart_viscous_friction * ref.y

	var u: float = u_ff - (
		K.x * x_error +
		K.y * theta_error +
		K.z * dx_error +
		K.w * dtheta_error
	)

	return clampf(u, -max_force_newtons, max_force_newtons)


# ============================================================
# 12. MODELO DINAMICO NO LINEAL
# ============================================================

func _state_derivative(state: Vector4, t: float) -> Vector4:
	var u: float = _control_force(state, t)
	return Vector4(state.z, state.w, 0.0, 0.0) + _accelerations(state, u)


# Resuelve la matriz de masas 2x2:
# [M+m          m*l*cos(th)] [ddx ]   [u - c*dx + m*l*sin(th)*dth^2]
# [m*l*cos(th)  J + m*l^2  ] [ddth] = [m*g*l*sin(th) - b*dth       ]
func _accelerations(state: Vector4, u: float) -> Vector4:
	var x_dot: float = state.z
	var theta_dot: float = state.w
	var sin_theta: float = sin(state.y)
	var cos_theta: float = cos(state.y)

	var a11: float = cart_mass + bob_mass
	var a12: float = bob_mass * arm_length * cos_theta
	var a22: float = inertia + bob_mass * arm_length * arm_length

	var rhs1: float = (
		u
		- cart_viscous_friction * x_dot
		+ bob_mass * arm_length * sin_theta * theta_dot * theta_dot
	)
	var rhs2: float = (
		bob_mass * gravity * arm_length * sin_theta
		- pivot_viscous_damping * theta_dot
	)

	var denominator: float = a11 * a22 - a12 * a12
	if denominator <= 0.0:
		return Vector4.ZERO

	var cart_acceleration: float = (a22 * rhs1 - a12 * rhs2) / denominator
	var theta_acceleration: float = (a11 * rhs2 - a12 * rhs1) / denominator

	return Vector4(0.0, 0.0, cart_acceleration, theta_acceleration)


# ============================================================
# 13. TRAYECTORIA DE REFERENCIA
# ============================================================
# Devuelve (x_ref, dx_ref, ddx_ref) en unidades SI.

func _evaluate_trajectory(t: float) -> Vector3:
	if t >= traj_duration:
		return Vector3(traj_target_m, 0.0, 0.0)

	var t2: float = t * t
	var t3: float = t2 * t
	var t4: float = t3 * t
	var t5: float = t4 * t

	var x_ref: float = poly_c[0] + poly_c[1]*t + poly_c[2]*t2 + poly_c[3]*t3 + poly_c[4]*t4 + poly_c[5]*t5
	var dx_ref: float = poly_c[1] + 2.0*poly_c[2]*t + 3.0*poly_c[3]*t2 + 4.0*poly_c[4]*t3 + 5.0*poly_c[5]*t4
	var ddx_ref: float = 2.0*poly_c[2] + 6.0*poly_c[3]*t + 12.0*poly_c[4]*t2 + 20.0*poly_c[5]*t3

	return Vector3(x_ref, dx_ref, ddx_ref)


# ============================================================
# 14. LIMITES FISICOS DEL CARRITO
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
# 15. REPRESENTACION GRAFICA
# ============================================================

func update_visuals() -> void:
	var pivot: Vector2 = Vector2(cart_x * pixels_per_meter, cart_sprite.position.y)
	cart_sprite.position = pivot

	# theta se mide desde la vertical superior; en Godot +Y apunta hacia abajo.
	var arm_length_px: float = arm_length * pixels_per_meter
	var bob_offset: Vector2 = Vector2(sin(theta), -cos(theta)) * arm_length_px

	bob_sprite.position = pivot + bob_offset
	link_sprite.position = pivot + bob_offset * 0.5
	link_sprite.rotation = theta - PI

	if link_sprite.texture:
		var tex_height: float = float(link_sprite.texture.get_height())
		if tex_height > 0.0:
			link_sprite.scale.y = arm_length_px / tex_height

	queue_redraw()


func _draw() -> void:
	if not cart_sprite:
		return

	var track_y: float = cart_sprite.position.y

	var color_pista := Color(0.6, 0.6, 0.6, 0.35)
	var color_limite := Color(0.95, 0.25, 0.25, 0.95)
	var color_objetivo := Color(0.2, 0.85, 0.4, 0.95)
	var color_ref_movil := Color(1.0, 0.8, 0.2, 0.95)

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

	# 3. Destino final asignado
	var target_px: float = traj_target_m * pixels_per_meter
	draw_dashed_line(
		Vector2(target_px, track_y - 60.0),
		Vector2(target_px, track_y + 25.0),
		color_objetivo, 2.0, 6.0
	)
	var punta := Vector2(target_px, track_y + 24.0)
	var triangulo := PackedVector2Array([
		punta,
		punta + Vector2(-8.0, 14.0),
		punta + Vector2(8.0, 14.0)
	])
	draw_colored_polygon(triangulo, color_objetivo)

	# 4. Referencia instantanea de la trayectoria suave
	var ref_actual_px: float = _evaluate_trajectory(traj_time).x * pixels_per_meter
	draw_circle(Vector2(ref_actual_px, track_y), 5.0, color_ref_movil)

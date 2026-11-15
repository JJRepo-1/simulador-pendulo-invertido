
extends Node2D

# ============================================================
# 1. CONFIGURACION FISICA (SISTEMA INTERNACIONAL)
# ============================================================

@export_group("Propiedades Fisicas")

@export var arm_length: float = 0.5
@export var gravity: float = 9.81
@export var cart_mass: float = 2.0
@export var bob_mass: float = 0.2
@export var inertia: float = 0.05

# Coeficientes de friccion viscosa
# Friccion del carrito [N*s/m]
# Amortiguamiento del pivote [N*m*s/rad]

@export var cart_viscous_friction: float = 0.10
@export var pivot_viscous_damping: float = 0.005


@onready var plot_pos: RealTimePlot = $CanvasLayer/plots/Control
@onready var plot_angle: RealTimePlot = $CanvasLayer/plots/Control3
@onready var plot_vel: RealTimePlot = $CanvasLayer/plots/Control4
@onready var plot_ang_vel: RealTimePlot = $CanvasLayer/plots/Control2

# ============================================================
# 2. CONTROLADOR LINEAL LMI
# ============================================================

@export_group("Controlador Lineal")

@export var control_enabled: bool = true

# Posicion de referencia en pixeles
@export var target_x: float = 0.0

# Posicion inicial del carrito en pixeles
@export var initial_cart_x_px: float = 0.0

# Perturbacion angular inicial en grados
@export var initial_angle_deg: float = 20.0

# Conversion grafica
@export var pixels_per_meter: float = 100.0

# K = [kx, ktheta, kdx, kdtheta]
# Calculada en MATLAB para el modelo proporcionado

@export var K: Vector4 = Vector4(
	-86.9937,
	-340.2803,
	-77.5246,
	-104.9065
)

# Saturacion del actuador [N]
@export var max_force_newtons: float = 150.0


@export_group("Trayectoria")
@export var trajectory_enabled: bool = true
@export var use_feedforward: bool = true
@export var amplitude_px: float = 120.0      # Amplitud desde el centro [px]
@export var frequency_hz: float = 0.25       # Frecuencia de oscilacion [Hz]

var sim_time: float = 0.0

# ============================================================
# 3. CONFIGURACION NUMERICA
# ============================================================

@export_group("Integracion Numerica")

# Paso maximo de integracion [s]
@export var max_integration_step: float = 1.0 / 240.0

# Velocidad de simulacion
@export var simulation_speed: float = 1.0


@export_group("Seguimiento en Tiempo Real")
@export var move_duration: float = 2.0 # Tiempo [s] que tarda en llegar al nuevo punto

@onready var input_nueva_pos: SpinBox = $CanvasLayer/VBoxContainer/SpinBox2
@onready var btn_mover: Button = $CanvasLayer/VBoxContainer/Button

# Variables internas de la trayectoria polinómica (en unidades SI: metros)
var traj_time: float = 0.0
var traj_duration: float = 1.0
var traj_target_m: float = 0.0
var poly_c: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]

# ============================================================
# 4. LIMITES DEL CARRITO (PIXELES)
# ============================================================

@export_group("Limites de Movimiento")

@export var min_x: float = -300.0
@export var max_x: float = 300.0


# ============================================================
# 5. VARIABLES DE ESTADO (SI)
# ============================================================

var is_simulating: bool = false

# Estado:
# X = [x, theta, x_dot, theta_dot]

var cart_x: float = 0.0
var theta: float = 0.0

var cart_velocity: float = 0.0
var theta_velocity: float = 0.0

var applied_control_force: float = 0.0


# ============================================================
# 6. REFERENCIAS A NODOS
# ============================================================

@onready var cart_sprite: Sprite2D = $Carrito
@onready var link_sprite: Sprite2D = $Eslabon
@onready var bob_sprite: Sprite2D = $masa

@onready var input_pos_inicial: SpinBox = $CanvasLayer/VBoxContainer/SpinBox
@onready var input_angulo_inicial: SpinBox = $CanvasLayer/VBoxContainer/angle
@onready var seguimiento: SpinBox = $CanvasLayer/VBoxContainer/SpinBox2

@onready var btn_simular: Button = $CanvasLayer/VBoxContainer/Simular


# ============================================================
# 7. INICIALIZACION
# ============================================================

func _ready() -> void:

# 1. Cargar configuración desde el Autoload Globals
	cart_mass = Globals.cart_mass
	bob_mass = Globals.bob_mass
	arm_length = Globals.arm_length
	inertia = Globals.inertia
	gravity = Globals.gravity
	cart_viscous_friction = Globals.cart_viscous_friction
	pivot_viscous_damping = Globals.pivot_viscous_damping
	max_force_newtons = Globals.max_force_newtons
	K = Globals.K

	# Comprobar parametros fisicos

	if pixels_per_meter <= 0.0:
		push_error("pixels_per_meter debe ser positivo.")
		set_physics_process(false)
		return

	if arm_length <= 0.0 or cart_mass <= 0.0 or bob_mass <= 0.0:
		push_error("Las masas y la longitud deben ser positivas.")
		set_physics_process(false)
		return

	if inertia < 0.0:
		push_error("El momento de inercia no puede ser negativo.")
		set_physics_process(false)
		return

	if max_integration_step <= 0.0:
		push_error("El paso de integracion debe ser positivo.")
		set_physics_process(false)
		return

	if max_x <= min_x:
		push_error("El limite maximo debe ser mayor que el minimo.")
		set_physics_process(false)
		return

	# Configuracion del SpinBox de posicion
	plot_pos.title = "Posición Carro (x)"
	plot_pos.unit = "m"
	plot_pos.line_color = Color(0.25, 0.85, 1.0)
	plot_pos.auto_scale = false
	plot_pos.y_min = min_x / pixels_per_meter
	plot_pos.y_max = max_x / pixels_per_meter

	# 2. Ángulo: rango fijo simétrico (0° siempre queda en el centro)
	plot_angle.title = "Ángulo Péndulo (θ)"
	plot_angle.unit = "°"
	plot_angle.line_color = Color(1.0, 0.75, 0.2)
	plot_angle.auto_scale = false
	plot_angle.y_min = -40.0
	plot_angle.y_max = 40.0

	# 3. Velocidad del carro: rango fijo simétrico
	plot_vel.title = "Velocidad Carro (dx)"
	plot_vel.unit = "m/s"
	plot_vel.line_color = Color(0.75, 0.45, 1.0)
	plot_vel.auto_scale = false
	plot_vel.y_min = -3.0
	plot_vel.y_max = 3.0

	# 4. Velocidad angular: rango fijo simétrico
	plot_ang_vel.title = "Vel. Angular (dθ)"
	plot_ang_vel.unit = "°/s"
	plot_ang_vel.line_color = Color(1.0, 0.35, 0.45)
	plot_ang_vel.auto_scale = false
	plot_ang_vel.y_min = -200.0
	plot_ang_vel.y_max = 200.0
	
	
	input_pos_inicial.min_value = min_x
	input_pos_inicial.max_value = max_x
	input_pos_inicial.step = 1.0
	input_pos_inicial.prefix = "Pos:"
	input_pos_inicial.suffix = "px"
	
	seguimiento.min_value = min_x
	seguimiento.max_value = max_x

	input_pos_inicial.value = clampf(
		initial_cart_x_px,
		min_x,
		max_x
	)
	
	seguimiento.value = clamp(
		initial_cart_x_px,
		min_x,
		max_x
	)

	# Configuracion del SpinBox angular

	input_angulo_inicial.min_value = -20.0
	input_angulo_inicial.max_value = 20.0
	input_angulo_inicial.step = 1.0
	input_angulo_inicial.prefix = "Ang:"
	input_angulo_inicial.suffix = "°"

	input_angulo_inicial.value = initial_angle_deg

	btn_simular.text = "Simular"

	# Conectar interfaz

	if not btn_simular.pressed.is_connected(_on_btn_simular_pressed):
		btn_simular.pressed.connect(_on_btn_simular_pressed)

	if not input_pos_inicial.value_changed.is_connected(_on_preview_changed):
		input_pos_inicial.value_changed.connect(_on_preview_changed)

	if not input_angulo_inicial.value_changed.is_connected(_on_preview_changed):
		input_angulo_inicial.value_changed.connect(_on_preview_changed)

	reset_state(
		input_pos_inicial.value,
		input_angulo_inicial.value
	)
	
	
	input_nueva_pos.min_value = min_x
	input_nueva_pos.max_value = max_x
	input_nueva_pos.step = 1.0
	input_nueva_pos.prefix = "Ref:"
	input_nueva_pos.suffix = "px"
	input_nueva_pos.value = clampf(target_x, min_x, max_x)

	btn_mover.text = "Ir a posición"




func _get_trajectory(t: float) -> Vector3:
	var x_center: float = target_x / pixels_per_meter

	if not trajectory_enabled:
		return Vector3(x_center, 0.0, 0.0)

	var amp_m: float = amplitude_px / pixels_per_meter
	var omega: float = TAU * frequency_hz # 2 * pi * f

	# Usamos (1 - cos) para que en t = 0 la posicion y velocidad inicien suavemente en 0
	var x_ref: float = x_center + amp_m * (1.0 - cos(omega * t)) * 0.5
	var dx_ref: float = amp_m * 0.5 * omega * sin(omega * t)
	var ddx_ref: float = amp_m * 0.5 * omega * omega * cos(omega * t)

	return Vector3(x_ref, dx_ref, ddx_ref)
# ============================================================
# 8. PREVISUALIZACION DE CONDICIONES INICIALES
# ============================================================

func _on_preview_changed(_new_value: float) -> void:

	if not is_simulating:

		reset_state(
			input_pos_inicial.value,
			input_angulo_inicial.value
		)


# ============================================================
# 9. INICIAR SIMULACION
# ============================================================

func _on_btn_simular_pressed() -> void:

	input_pos_inicial.apply()
	input_angulo_inicial.apply()

	reset_state(
		input_pos_inicial.value,
		input_angulo_inicial.value
	)

	is_simulating = true


# ============================================================
# 10. REINICIAR ESTADOS
# ============================================================

func reset_state(start_x_px: float, start_angle_deg: float) -> void:

	# Convertir posicion inicial de pixeles a metros

	cart_x = clampf(
		start_x_px / pixels_per_meter,
		min_x / pixels_per_meter,
		max_x / pixels_per_meter
	)

	cart_velocity = 0.0

	# Angulo medido respecto a la vertical superior
	# theta = 0 significa pendulo invertido

	theta = deg_to_rad(start_angle_deg)

	theta_velocity = 0.0

	initial_angle_deg = start_angle_deg

	applied_control_force = 0.0
	
	traj_target_m = cart_x
	traj_time = 0.0
	traj_duration = 1.0
	poly_c = [cart_x, 0.0, 0.0, 0.0, 0.0, 0.0]
	input_nueva_pos.value = cart_x * pixels_per_meter
	
	if plot_pos:
		plot_pos.clear()
		plot_angle.clear()
		plot_vel.clear()
		plot_ang_vel.clear()
	
	
	update_visuals()


# ============================================================
# 11. FISICA PRINCIPAL
# ============================================================

func _physics_process(delta: float) -> void:

	if not is_simulating or delta <= 0.0:
		return

	var simulation_delta: float = delta * simulation_speed

	if simulation_delta <= 0.0:
		return

	# Dividir el tiempo para mejorar la estabilidad numerica

	var substeps: int = maxi(
		1,
		int(ceil(simulation_delta / max_integration_step))
	)

	var h: float = simulation_delta / float(substeps)

	# Estado actual:
	# [x, theta, x_dot, theta_dot]

	var state: Vector4 = Vector4(
		cart_x,
		theta,
		cart_velocity,
		theta_velocity
	)

	# Integracion RK4

	for _i in range(substeps):


		state = _rk4_step(state, traj_time, h)
		state = _enforce_cart_limits(state)
		traj_time += h

	# Recuperar estados

	cart_x = state.x
	theta = state.y

	cart_velocity = state.z
	theta_velocity = state.w
	
	for _i in range(substeps):
		state = _rk4_step(state, sim_time, h)
		state = _enforce_cart_limits(state)
		sim_time += h

	update_visuals()
	
	var ref_x_actual: float = _evaluate_trajectory(traj_time).x

	plot_pos.add_sample(cart_x, ref_x_actual)
	plot_angle.add_sample(rad_to_deg(theta))
	plot_vel.add_sample(cart_velocity)
	plot_ang_vel.add_sample(rad_to_deg(theta_velocity))
	
func _rk4_step(state: Vector4, t: float, h: float) -> Vector4:
	var k1: Vector4 = _state_derivative(state, t)
	var k2: Vector4 = _state_derivative(state + k1 * (h * 0.5), t + h * 0.5)
	var k3: Vector4 = _state_derivative(state + k2 * (h * 0.5), t + h * 0.5)
	var k4: Vector4 = _state_derivative(state + k3 * h, t + h)
	return state + (k1 + k2 * 2.0 + k3 * 2.0 + k4) * (h / 6.0)


# ============================================================
# 12. CONTROLADOR LINEAL
# ============================================================

func _control_force(state: Vector4, t: float) -> float:
	if not control_enabled:
		return 0.0

	var ref: Vector3 = _evaluate_trajectory(t)

	var x_error: float = state.x - ref.x
	var theta_error: float = wrapf(state.y, -PI, PI)
	var dx_error: float = state.z - ref.y
	var dtheta_error: float = state.w

	# Prealimentación opcional para eliminar el retraso por inercia durante el desplazamiento
	var u_ff: float = (cart_mass + bob_mass) * ref.z + cart_viscous_friction * ref.y

	var u: float = u_ff - (
		K.x * x_error +
		K.y * theta_error +
		K.z * dx_error +
		K.w * dtheta_error
	)

	var force_limit: float = maxf(max_force_newtons, 0.0)
	return clampf(u, -force_limit, force_limit)


# ============================================================
# 13. MODELO DINAMICO NO LINEAL
# ============================================================

func _state_derivative(state: Vector4, t: float) -> Vector4:

	# Recuperar estados

	var x_dot: float = state.z
	var theta_dot: float = state.w

	var sin_theta: float = sin(state.y)
	var cos_theta: float = cos(state.y)

	# Fuerza de control [N]

	var u: float = _control_force(state, t)

	applied_control_force = u

	# --------------------------------------------------------
	# Matriz de masas del sistema
	# --------------------------------------------------------

	var a11: float = cart_mass + bob_mass

	var a12: float = bob_mass * arm_length * cos_theta

	var a22: float = inertia + bob_mass * arm_length * arm_length

	# --------------------------------------------------------
	# Terminos independientes de las ecuaciones dinamicas
	# --------------------------------------------------------

	var rhs1: float = (
		u
		- cart_viscous_friction * x_dot
		+ bob_mass * arm_length * sin_theta * theta_dot * theta_dot
	)

	var rhs2: float = (
		bob_mass * gravity * arm_length * sin_theta
		- pivot_viscous_damping * theta_dot
	)

	# --------------------------------------------------------
	# Determinante de la matriz de masas
	# --------------------------------------------------------

	var denominator: float = a11 * a22 - a12 * a12

	if denominator <= 0.0:
		return Vector4(
			x_dot,
			theta_dot,
			0.0,
			0.0
		)

	# --------------------------------------------------------
	# Aceleracion horizontal del carrito
	# --------------------------------------------------------

	var cart_acceleration: float = (
		a22 * rhs1 - a12 * rhs2
	) / denominator

	# --------------------------------------------------------
	# Aceleracion angular del pendulo
	# --------------------------------------------------------

	var theta_acceleration: float = (
		a11 * rhs2 - a12 * rhs1
	) / denominator

	# --------------------------------------------------------
	# Derivadas del vector de estado
	# --------------------------------------------------------

	return Vector4(
		x_dot,
		theta_dot,
		cart_acceleration,
		theta_acceleration
	)


# ============================================================
# 14. INTEGRADOR RUNGE-KUTTA DE CUARTO ORDEN
# ============================================================



# ============================================================
# 15. LIMITES FISICOS DEL CARRITO
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
# 16. REPRESENTACION GRAFICA
# ============================================================

func update_visuals() -> void:

	# Convertir posicion del carrito a pixeles

	var cart_x_px: float = cart_x * pixels_per_meter

	var pivot: Vector2 = Vector2(
		cart_x_px,
		cart_sprite.position.y
	)

	cart_sprite.position = pivot

	# Longitud del pendulo en pixeles

	var arm_length_px: float = arm_length * pixels_per_meter

	# El angulo theta se mide desde la vertical superior.
	# Godot tiene el eje Y positivo hacia abajo.

	var bob_offset: Vector2 = Vector2(
		sin(theta),
		-cos(theta)
	) * arm_length_px

	# Posicion de la masa

	bob_sprite.position = pivot + bob_offset

	# Posicion del eslabon

	link_sprite.position = pivot + bob_offset * 0.5

	# Rotacion del eslabon
	# Se conserva la orientacion de la textura original.

	link_sprite.rotation = theta - PI

	# Escalar longitud de la textura

	if link_sprite.texture:

		var tex_height: float = float(
			link_sprite.texture.get_height()
		)

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

	# 1. Linea de pista entre los limites
	draw_line(
		Vector2(min_x, track_y),
		Vector2(max_x, track_y),
		color_pista,
		2.0
	)

	# 2. Topes visuales en los limites de recorrido (min_x y max_x)
	var alto_tope: float = 28.0
	for limit_x: float in [min_x, max_x]:
		draw_line(
			Vector2(limit_x, track_y - alto_tope),
			Vector2(limit_x, track_y + alto_tope),
			color_limite,
			4.0
		)
		# Pequeñas pestañas horizontales en los extremos del tope
		var dir: float = -1.0 if limit_x == min_x else 1.0
		draw_line(
			Vector2(limit_x, track_y - alto_tope),
			Vector2(limit_x + 8.0 * dir, track_y - alto_tope),
			color_limite,
			3.0
		)
		draw_line(
			Vector2(limit_x, track_y + alto_tope),
			Vector2(limit_x + 8.0 * dir, track_y + alto_tope),
			color_limite,
			3.0
		)

	# 3. Marcador de la posicion asignada (destino final)
	var target_px: float = traj_target_m * pixels_per_meter
	draw_dashed_line(
		Vector2(target_px, track_y - 60.0),
		Vector2(target_px, track_y + 25.0),
		color_objetivo,
		2.0,
		6.0
	)

	# Triangulo indicador debajo del carrito apuntando al destino
	var punta := Vector2(target_px, track_y + 24.0)
	var triangulo := PackedVector2Array([
		punta,
		punta + Vector2(-8.0, 14.0),
		punta + Vector2(8.0, 14.0)
	])
	draw_colored_polygon(triangulo, color_objetivo)

	# 4. Marcador de la referencia instantanea de la trayectoria suave
	var ref_actual_px: float = _evaluate_trajectory(traj_time).x * pixels_per_meter
	draw_circle(Vector2(ref_actual_px, track_y), 5.0, color_ref_movil)

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

func _on_button_pressed() -> void:
	if not is_simulating:
		return

	input_nueva_pos.apply()
	var new_target_px: float = clampf(input_nueva_pos.value, min_x, max_x)
	var xf: float = new_target_px / pixels_per_meter

	# Estado actual de la referencia (permite cambiar de destino en pleno movimiento)
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

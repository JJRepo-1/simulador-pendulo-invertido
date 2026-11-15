extends Node2D

# ============================================================
# PENDULO INVERTIDO NO LINEAL SIN CONTROL (u = 0)
# ============================================================
# Mismo modelo, unidades y convenciones que pendulo_2.gd:
#   estado X = [x, theta, x_dot, theta_dot] en SI,
#   theta = 0 -> pendulo vertical hacia arriba.

# --- Parametros fisicos (se cargan desde Globals) ---
var cart_mass: float = 2.0               # M [kg]
var bob_mass: float = 0.2                # m [kg]
var arm_length: float = 0.5              # l [m]
var inertia: float = 0.05                # J [kg*m^2]
var gravity: float = 9.81                # g [m/s^2]
var cart_viscous_friction: float = 0.10  # [N*s/m]
var pivot_viscous_damping: float = 0.005 # [N*m*s/rad]

@export_group("Condiciones Iniciales")
@export var initial_cart_x_px: float = 0.0   # Posicion inicial [px]
@export var initial_angle_deg: float = 10.0  # Angulo inicial desde la vertical superior [grados]

@export_group("Integracion Numerica")
@export var max_integration_step: float = 1.0 / 240.0  # Paso maximo RK4 [s]
@export var simulation_speed: float = 1.0

@export_group("Representacion")
@export var pixels_per_meter: float = 100.0

@export_group("Limites de Movimiento")
@export var min_x: float = -300.0  # [px]
@export var max_x: float = 300.0   # [px]

# --- Variables de estado (SI) ---
var cart_x: float = 0.0
var theta: float = 0.0
var cart_velocity: float = 0.0
var theta_velocity: float = 0.0

# --- Referencias a nodos ---
@onready var cart_sprite: Sprite2D = $Carrito
@onready var link_sprite: Sprite2D = $Eslabon
@onready var bob_sprite: Sprite2D = $masa


func _ready() -> void:
	cart_mass = Globals.cart_mass
	bob_mass = Globals.bob_mass
	arm_length = Globals.arm_length
	inertia = Globals.inertia
	gravity = Globals.gravity
	cart_viscous_friction = Globals.cart_viscous_friction
	pivot_viscous_damping = Globals.pivot_viscous_damping

	if pixels_per_meter <= 0.0 or arm_length <= 0.0 or cart_mass <= 0.0 \
			or bob_mass <= 0.0 or inertia < 0.0 or max_integration_step <= 0.0 \
			or max_x <= min_x:
		push_error("Parametros fisicos o numericos invalidos.")
		set_physics_process(false)
		return

	reset_state(initial_cart_x_px, initial_angle_deg)


func reset_state(start_x_px: float, start_angle_deg: float) -> void:
	cart_x = clampf(start_x_px, min_x, max_x) / pixels_per_meter
	cart_velocity = 0.0
	theta = deg_to_rad(start_angle_deg)
	theta_velocity = 0.0
	update_visuals()


func _physics_process(delta: float) -> void:
	var simulation_delta: float = delta * simulation_speed
	if simulation_delta <= 0.0:
		return

	var substeps: int = maxi(1, int(ceil(simulation_delta / max_integration_step)))
	var h: float = simulation_delta / float(substeps)

	var state: Vector4 = Vector4(cart_x, theta, cart_velocity, theta_velocity)
	for _i in range(substeps):
		state = _rk4_step(state, h)
		state = _enforce_cart_limits(state)

	cart_x = state.x
	theta = state.y
	cart_velocity = state.z
	theta_velocity = state.w

	update_visuals()


# ============================================================
# MODELO DINAMICO NO LINEAL (identico a pendulo_2.gd con u = 0)
# ============================================================
# [M+m          m*l*cos(th)] [ddx ]   [u - c*dx + m*l*sin(th)*dth^2]
# [m*l*cos(th)  J + m*l^2  ] [ddth] = [m*g*l*sin(th) - b*dth       ]

func _state_derivative(state: Vector4) -> Vector4:
	var u: float = 0.0

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
		return Vector4(x_dot, theta_dot, 0.0, 0.0)

	var cart_acceleration: float = (a22 * rhs1 - a12 * rhs2) / denominator
	var theta_acceleration: float = (a11 * rhs2 - a12 * rhs1) / denominator

	return Vector4(x_dot, theta_dot, cart_acceleration, theta_acceleration)


func _rk4_step(state: Vector4, h: float) -> Vector4:
	var k1: Vector4 = _state_derivative(state)
	var k2: Vector4 = _state_derivative(state + k1 * (h * 0.5))
	var k3: Vector4 = _state_derivative(state + k2 * (h * 0.5))
	var k4: Vector4 = _state_derivative(state + k3 * h)
	return state + (k1 + k2 * 2.0 + k3 * 2.0 + k4) * (h / 6.0)


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
# REPRESENTACION GRAFICA (misma convencion que pendulo_2.gd)
# ============================================================

func update_visuals() -> void:
	var pivot: Vector2 = Vector2(cart_x * pixels_per_meter, cart_sprite.position.y)
	cart_sprite.position = pivot

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

	draw_line(Vector2(min_x, track_y), Vector2(max_x, track_y), color_pista, 2.0)

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

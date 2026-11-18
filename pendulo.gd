extends Node2D

# ============================================================
# PENDULO INVERTIDO NO LINEAL SIN CONTROL (u = 0)
# ============================================================
# Mismo modelo, unidades y convenciones que pendulo_2.gd:
#   estado X = [x, theta, x_dot, theta_dot] en SI,
#   theta = 0 -> pendulo vertical hacia arriba.

# --- Parametros fisicos y modelo de referencia (desde Globals) ---
var modelo: PenduloModelo = PenduloModelo.new()

# Planta simulada: ecuaciones no lineales del usuario (Configuracion)
# o, si tienen errores, el modelo de referencia. Igual que pendulo_2.gd.
var planta = null
var planta_es_usuario: bool = false

@export_group("Condiciones Iniciales")
@export var initial_cart_x_px: float = 0.0   # Posicion inicial [px]
@export var initial_angle_deg: float = 10.0  # Angulo inicial desde la vertical superior [grados]
@export var simulation_time_s: float = 3.0   # Tiempo de simulacion [s] (t_final en MATLAB)

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

var sim_time: float = 0.0  # Tiempo de simulacion [s]

# --- Referencias a nodos ---
@onready var cart_sprite: Sprite2D = $Carrito
@onready var link_sprite: Sprite2D = $Eslabon
@onready var bob_sprite: Sprite2D = $masa

# Interfaz creada por codigo (misma zona de pantalla que en pendulo_2)
const GRAFICAS_RECT := Rect2(148.0, 58.0, 562.0, 238.0)
var panel_graficas: PanelGraficas
var btn_graficas: Button
var control_tiempo: ControlTiempo
var simulando: bool = true


func _ready() -> void:
	modelo = Globals.crear_modelo()

	var r: Dictionary = Globals.crear_modelo_usuario()
	planta_es_usuario = r.ok
	planta = r.modelo if r.ok else modelo
	if not r.ok:
		var motivo: String = "; ".join(PackedStringArray(
			[r.error_carro, r.error_pendulo, r.error_sistema].filter(func(e: String) -> bool: return e != "")))
		push_warning("Ecuaciones de movimiento con errores (%s); se usa el modelo de referencia." % motivo)

	var error_modelo: String = modelo.validar()
	if error_modelo != "":
		push_error(error_modelo)
		set_physics_process(false)
		return
	if pixels_per_meter <= 0.0 or max_integration_step <= 0.0 or max_x <= min_x:
		push_error("Parametros numericos o de representacion invalidos.")
		set_physics_process(false)
		return

	_setup_ui()
	reset_state(initial_cart_x_px, initial_angle_deg)


# Botones (graficas y reinicio) y panel desplegable de graficas.
func _setup_ui() -> void:
	var capa := CanvasLayer.new()
	add_child(capa)

	var caja := VBoxContainer.new()
	caja.position = Vector2(29.0, 19.0)
	caja.scale = Vector2(0.5, 0.5)
	capa.add_child(caja)

	# Duracion de la simulacion; "Reiniciar" la vuelve a correr desde t = 0
	control_tiempo = ControlTiempo.new(simulation_time_s)
	caja.add_child(control_tiempo)

	btn_graficas = Button.new()
	btn_graficas.text = "Mostrar gráficas"
	btn_graficas.focus_mode = Control.FOCUS_NONE
	btn_graficas.pressed.connect(func() -> void:
		panel_graficas.alternar()
		btn_graficas.text = "Ocultar gráficas" if panel_graficas.visible else "Mostrar gráficas")
	caja.add_child(btn_graficas)

	var btn_reiniciar := Button.new()
	btn_reiniciar.text = "Reiniciar"
	btn_reiniciar.focus_mode = Control.FOCUS_NONE
	btn_reiniciar.pressed.connect(func() -> void:
		reset_state(initial_cart_x_px, initial_angle_deg)
		simulando = true
		set_physics_process(true))
	caja.add_child(btn_reiniciar)

	panel_graficas = PanelGraficas.new()
	capa.add_child(panel_graficas)
	panel_graficas.position = GRAFICAS_RECT.position
	panel_graficas.size = GRAFICAS_RECT.size
	panel_graficas.fijar_rango(PanelGraficas.IDX_X, min_x / pixels_per_meter, max_x / pixels_per_meter)


func reset_state(start_x_px: float, start_angle_deg: float) -> void:
	cart_x = clampf(start_x_px, min_x, max_x) / pixels_per_meter
	cart_velocity = 0.0
	theta = deg_to_rad(start_angle_deg)
	theta_velocity = 0.0
	sim_time = 0.0
	if planta_es_usuario:
		planta.error_ejecucion = ""
	if panel_graficas:
		panel_graficas.limpiar()
		panel_graficas.fijar_duracion(control_tiempo.t_final())
		panel_graficas.agregar_muestra(sim_time, Vector4(cart_x, theta, cart_velocity, theta_velocity))
		control_tiempo.mostrar(sim_time, false)
	update_visuals()


func _physics_process(delta: float) -> void:
	if not simulando:
		return
	# El ultimo paso se recorta para terminar exactamente en t_final
	var t_final: float = control_tiempo.t_final()
	var simulation_delta: float = minf(delta * simulation_speed, t_final - sim_time)
	if simulation_delta <= 0.0:
		return

	var substeps: int = maxi(1, int(ceil(simulation_delta / max_integration_step)))
	var h: float = simulation_delta / float(substeps)

	var state: Vector4 = Vector4(cart_x, theta, cart_velocity, theta_velocity)
	for _i in range(substeps):
		state = _rk4_step(state, h)
		state = _enforce_cart_limits(state)

	if planta_es_usuario and planta.error_ejecucion != "":
		push_warning("Simulación detenida: " + planta.error_ejecucion)
		set_physics_process(false)
		return
	if not (is_finite(state.x) and is_finite(state.y) and is_finite(state.z) and is_finite(state.w)):
		push_warning("Simulación detenida: el estado dejó de ser finito.")
		set_physics_process(false)
		return

	cart_x = state.x
	theta = state.y
	cart_velocity = state.z
	theta_velocity = state.w
	sim_time += simulation_delta

	update_visuals()
	panel_graficas.agregar_muestra(sim_time, state)

	var terminada: bool = sim_time >= t_final - 1e-9
	control_tiempo.mostrar(sim_time, terminada)
	if terminada:
		simulando = false


# Planta no lineal con u = 0.
func _state_derivative(state: Vector4) -> Vector4:
	return planta.derivada(state, 0.0)


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

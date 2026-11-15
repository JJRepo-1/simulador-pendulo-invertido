extends Node2D

# --- Configuración Física ---
@export_group("Propiedades Físicas")
@export var arm_length: float = 50.0     # Longitud del eslabón (píxeles)
@export var gravity: float = 980.0        # Gravedad
@export var cart_mass: float = 5.0        # Masa del carrito (más masa = se mueve menos)
@export var bob_mass: float = 2.0         # Masa del péndulo (más masa = empuja más)
@export var friction: float = 0.98        # Fricción del carrito (1.0 = sin fricción)
@export var damping: float = 0.995        # Amortiguación del péndulo

# --- Límites del Carrito ---
@export_group("Límites de Movimiento")
@export var min_x: float = -300.0
@export var max_x: float = 300.0

# --- Variables de Estado ---
var angle: float = PI / 3                 # Ángulo inicial (60 grados)
var angular_velocity: float = 0.0
var cart_x: float = 0.0                 # Posición inicial X del carrito
var cart_velocity: float = 0.0

# --- Referencias a Nodos ---
@onready var cart_sprite: Sprite2D = $Carrito
@onready var link_sprite: Sprite2D = $Eslabon
@onready var bob_sprite: Sprite2D = $masa

func _ready() -> void:
	
	cart_mass = Globals.cart_mass
	bob_mass = Globals.bob_mass
	arm_length = Globals.arm_length *100
	# Posicionar el carrito inicialmente en el centro de los límites o en su posición actual
	cart_x = clamp(cart_sprite.position.x, min_x, max_x)
	update_visuals()

func _physics_process(delta: float) -> void:
	# 1. Calcular aceleraciones acopladas (Ecuaciones de Euler-Lagrange simplificadas)
	var sin_a = sin(angle)
	var cos_a = cos(angle)
	var total_mass = cart_mass + bob_mass
	
	# Aceleración angular del péndulo considerando la inercia del carrito
	var num1 = -gravity * total_mass * sin_a
	var num2 = -bob_mass * arm_length * angular_velocity * angular_velocity * sin_a * cos_a
	var den = arm_length * (total_mass - bob_mass * cos_a * cos_a)
	var angular_acceleration = (num1 + num2) / den
	
	# Aceleración horizontal del carrito provocada por la tensión del péndulo
	var cart_acceleration = (bob_mass * sin_a * (arm_length * angular_velocity * angular_velocity + gravity * cos_a)) / (total_mass - bob_mass * cos_a * cos_a)

	# 2. Integrar velocidades y posiciones
	angular_velocity += angular_acceleration * delta
	angular_velocity *= damping
	angle += angular_velocity * delta

	cart_velocity += cart_acceleration * delta
	cart_velocity *= friction
	cart_x += cart_velocity * delta

	# 3. Aplicar límites de distancia mínima y máxima en X
	if cart_x <= min_x:
		cart_x = min_x
		cart_velocity = 0.0 # Detener en seco al chocar con el límite
	elif cart_x >= max_x:
		cart_x = max_x
		cart_velocity = 0.0

	# 4. Actualizar posiciones y rotaciones de los Sprites
	update_visuals()

func _draw() -> void:
	if not cart_sprite:
		return

	var track_y: float = cart_sprite.position.y

	var color_pista := Color(0.6, 0.6, 0.6, 0.35)
	var color_limite := Color(0.95, 0.25, 0.25, 0.95)

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

	# Triangulo indicador debajo del carrito apuntando al destino

	# 4. Marcador de la referencia instantanea de la trayectoria suave

func update_visuals() -> void:
	# Posición del carrito (solo cambia X, mantiene su Y original)
	var pivot = Vector2(cart_x, cart_sprite.position.y)
	cart_sprite.position = pivot
	
	# Posición de la masa (calculada desde el carrito)
	var bob_offset = Vector2(sin(angle), cos(angle)) * arm_length
	bob_sprite.position = pivot + bob_offset
	
	# Posición y rotación del eslabón
	# Se coloca en el punto medio entre el carrito y la masa
	link_sprite.position = pivot + (bob_offset * 0.5)
	# Rotamos el eslabón (en Godot 0 radianes apunta a la derecha, restamos ángulo para alinear)
	link_sprite.rotation = -angle
	
	# Ajustar el largo visual del eslabón (asumiendo que su textura base mide 1 píxel de alto)
	# Si usas una textura de por ejemplo 64px de alto, divide arm_length entre 64.0
	if link_sprite.texture:
		var tex_height = link_sprite.texture.get_height()
		link_sprite.scale.y = arm_length / tex_height
	queue_redraw()

extends Node

# Propiedades físicas (Sistema Internacional)
var cart_mass: float = 2.0
var bob_mass: float = 0.2
var arm_length: float = 0.5
var inertia: float = 0.05
var gravity: float = 9.81

# Fricción y saturación
var cart_viscous_friction: float = 0.10
var pivot_viscous_damping: float = 0.005
var max_force_newtons: float = 150.0

# Ganancias del controlador lineal [kx, ktheta, kdx, kdtheta]
var K: Vector4 = Vector4(
	-86.9937,
	-340.2803,
	-77.5246,
	-104.9065
)


# Modelo no lineal escrito por el usuario (pantalla de Configuracion):
# ecuaciones de movimiento del carro y del pendulo. Por defecto, sistema ideal.
var no_lineal_carro: String = FormulasLineales.EJEMPLO_CARRO
var no_lineal_pendulo: String = FormulasLineales.EJEMPLO_PENDULO

# Modelo lineal dX/dt = A*X + B*u escrito por el usuario como formulas
# (pantalla de Configuracion). Variables: M, m, l, J, g, c, b y las auxiliares.
var lineal_aux: String = FormulasLineales.EJEMPLO_AUX
var lineal_A: PackedStringArray = PackedStringArray(FormulasLineales.EJEMPLO_A)
var lineal_B: PackedStringArray = PackedStringArray(FormulasLineales.EJEMPLO_B)


var PenduloSeleccion: int  = 0


# Parametros fisicos con los nombres usados en las formulas.
func parametros_modelo() -> Dictionary:
	return {
		"M": cart_mass,
		"m": bob_mass,
		"l": arm_length,
		"J": inertia,
		"g": gravity,
		"c": cart_viscous_friction,
		"b": pivot_viscous_damping,
	}


# Modelo no lineal de referencia (ecuaciones fijas) con los parametros guardados.
func crear_modelo() -> PenduloModelo:
	return PenduloModelo.desde_parametros(parametros_modelo())


# Modelo no lineal con las ecuaciones que escribio el usuario.
# Mismo diccionario que ModeloFormulas.construir().
func crear_modelo_usuario() -> Dictionary:
	return ModeloFormulas.construir(parametros_modelo(), no_lineal_carro, no_lineal_pendulo)

func _ready() -> void:
	pass # Replace with function body.

func _set_escena(seleccion: int) -> void:
	match seleccion:
		0:
			PenduloSeleccion = 0
		1:
			PenduloSeleccion = 1
		_:
			return
	
	get_tree().change_scene_to_file("res://pruebas.tscn")
 
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass

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


var PenduloSeleccion: int  = 0

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

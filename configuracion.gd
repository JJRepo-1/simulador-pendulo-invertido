extends Control

@onready var input_cart_mass: SpinBox = $VBoxContainer/cartmass
@onready var input_bob_mass: SpinBox = $VBoxContainer/boobmass
@onready var input_arm_length: SpinBox = $"VBoxContainer/armtamaño"
@onready var input_inertia: SpinBox = $VBoxContainer/inerciamomento
@onready var input_cart_friction: SpinBox = $VBoxContainer/friccioncarro
@onready var input_pivot_damping: SpinBox = $VBoxContainer/pivote
@onready var input_max_force: SpinBox = $VBoxContainer/imputmaxforce

@onready var input_kx: SpinBox = $VBoxContainer/kx
@onready var input_ktheta: SpinBox = $VBoxContainer/kteta
@onready var input_kdx: SpinBox = $VBoxContainer/kdx
@onready var input_kdtheta: SpinBox = $VBoxContainer/kdteta
@onready var notificar: Label = $Label
@onready var timerrr: Timer = $Timer
@onready var editor_lineal: EditorModeloLineal = $ModeloLineal
@onready var btn_calcular_k: Button = $CalcularK

# Calculo de K / Ka con MATLAB en modo batch (YALMIP + SeDuMi)
var calculo_matlab: CalculoMatlab

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	notificar.hide()
	notificar.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notificar.size.x = 370.0
# Rellenar los campos con los valores almacenados en Globals
# 1. Configurar precision y rangos ANTES de asignar los valores
	var k_boxes: Array[SpinBox] = [input_kx, input_ktheta, input_kdx, input_kdtheta]
	for box: SpinBox in k_boxes:
		box.step = 0.0001
		box.min_value = -100000.0
		box.max_value = 100000.0
		box.allow_lesser = true
		box.allow_greater = true

	# (Opcional) Hacer lo mismo para los parametros fisicos con 4 decimales
	var param_boxes: Array[SpinBox] = [
		input_cart_mass, input_bob_mass, input_arm_length,
		input_inertia, input_cart_friction, input_pivot_damping, input_max_force
	]
	for box: SpinBox in param_boxes:
		box.step = 0.0001
		box.min_value = 0.0
		box.max_value = 100000.0
		box.allow_greater = true

	# 2. Ahora si, cargar los valores desde Globals sin que se recorten ni redondeen
	input_cart_mass.value = Globals.cart_mass
	input_bob_mass.value = Globals.bob_mass
	input_arm_length.value = Globals.arm_length
	input_inertia.value = Globals.inertia
	input_cart_friction.value = Globals.cart_viscous_friction
	input_pivot_damping.value = Globals.pivot_viscous_damping
	input_max_force.value = Globals.max_force_newtons

	input_kx.value = Globals.K.x
	input_ktheta.value = Globals.K.y
	input_kdx.value = Globals.K.z
	input_kdtheta.value = Globals.K.w

	# 3. Editor del modelo lineal: se evalua con los parametros de esta pantalla
	editor_lineal.cargar(Globals.lineal_aux, Globals.lineal_A, Globals.lineal_B)
	editor_lineal.cargar_no_lineal(Globals.no_lineal_carro, Globals.no_lineal_pendulo)
	editor_lineal.aumentado.cargar(Globals.aumentado_A, Globals.aumentado_B)
	editor_lineal.aumentado.cargar_ganancias(Globals.Ka)
	editor_lineal.actualizar_parametros(_parametros_actuales())
	for box: SpinBox in [input_cart_mass, input_bob_mass, input_arm_length,
			input_inertia, input_cart_friction, input_pivot_damping]:
		box.value_changed.connect(_on_parametro_cambiado)

	# 4. Botones para calcular las ganancias con MATLAB
	calculo_matlab = CalculoMatlab.new()
	add_child(calculo_matlab)
	calculo_matlab.terminado.connect(_on_ganancias_calculadas)
	btn_calcular_k.tooltip_text = "Resuelve el LMI de codigo4.m con la A y B de la pestaña 2"
	btn_calcular_k.pressed.connect(_on_calcular_k_pressed)
	editor_lineal.aumentado.calcular_con_matlab.connect(_on_calcular_ka_pressed)


# K del pendulo con control (regulacion): LMI de orden 4, alpha = 2, beta = 10.
func _on_calcular_k_pressed() -> void:
	var mat: Dictionary = editor_lineal.matrices_lineales()
	if mat.is_empty():
		_notificar("Corrige A y B (pestaña 2) antes de calcular K.")
		return
	calculo_matlab.solicitar("regulador", mat.A, mat.B, 4, 2.0, 10.0)


# Ka del seguimiento de trayectoria: LMI de orden 5, alpha = 1, beta = 10.
func _on_calcular_ka_pressed() -> void:
	var mat: Dictionary = editor_lineal.aumentado.matrices()
	if mat.is_empty():
		_notificar("Corrige Aa y Ba (pestaña 3) antes de calcular Ka.")
		return
	calculo_matlab.solicitar("seguimiento", mat.A, mat.B, 5, 1.0, 10.0)


func _on_ganancias_calculadas(sistema: String, K: PackedFloat64Array, _polos: Array[Vector2]) -> void:
	if sistema == "regulador":
		input_kx.value = K[0]
		input_ktheta.value = K[1]
		input_kdx.value = K[2]
		input_kdtheta.value = K[3]
	else:
		editor_lineal.aumentado.cargar_ganancias(K)
	_notificar("Ganancias calculadas con MATLAB. Presiona \"Guardar datos\" para usarlas.")


func _notificar(texto: String) -> void:
	notificar.text = texto
	notificar.show()
	timerrr.start()


func _parametros_actuales() -> Dictionary:
	return {
		"M": input_cart_mass.value,
		"m": input_bob_mass.value,
		"l": input_arm_length.value,
		"J": input_inertia.value,
		"g": Globals.gravity,
		"c": input_cart_friction.value,
		"b": input_pivot_damping.value,
	}


func _on_parametro_cambiado(_valor: float) -> void:
	editor_lineal.actualizar_parametros(_parametros_actuales())



# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_button_pressed() -> void:
	# Guardar los valores ingresados por el usuario en Globals
	Globals.cart_mass = input_cart_mass.value
	Globals.bob_mass = input_bob_mass.value
	Globals.arm_length = input_arm_length.value
	Globals.inertia = input_inertia.value
	Globals.cart_viscous_friction = input_cart_friction.value
	Globals.pivot_viscous_damping = input_pivot_damping.value
	Globals.max_force_newtons = input_max_force.value

	Globals.K = Vector4(
		input_kx.value,
		input_ktheta.value,
		input_kdx.value,
		input_kdtheta.value
	)

	Globals.lineal_aux = editor_lineal.obtener_aux()
	Globals.lineal_A = editor_lineal.obtener_A()
	Globals.lineal_B = editor_lineal.obtener_B()
	Globals.no_lineal_carro = editor_lineal.obtener_ecuacion_carro()
	Globals.no_lineal_pendulo = editor_lineal.obtener_ecuacion_pendulo()
	Globals.aumentado_A = editor_lineal.aumentado.obtener_A()
	Globals.aumentado_B = editor_lineal.aumentado.obtener_B()
	Globals.Ka = editor_lineal.aumentado.obtener_ganancias()

	var avisos: Array[String] = []
	if editor_lineal.tiene_errores_no_lineal():
		avisos.append("ecuaciones no lineales con errores (se usará el modelo de referencia)")
	if editor_lineal.tiene_errores():
		avisos.append("A/B con errores (no habrá comparación lineal)")
	if editor_lineal.aumentado.tiene_errores():
		avisos.append("Aa/Ba con errores (no habrá comparación lineal en el seguimiento)")
	if avisos.is_empty():
		notificar.text = "Datos guardados correctamente"
	else:
		notificar.text = "Datos guardados. Ojo: " + "; ".join(avisos) + "."
	notificar.show()
	timerrr.start()


func _on_button_2_pressed() -> void:
	get_tree().change_scene_to_file("res://main.tscn")


func _on_timer_timeout() -> void:
	notificar.hide()
	

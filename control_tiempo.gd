class_name ControlTiempo
extends VBoxContainer

# ============================================================
# TIEMPO DE SIMULACION (t_final de los scripts de MATLAB)
# ============================================================
# Etiqueta + spinbox para elegir la duracion y una linea de estado con
# el tiempo actual. Lo usan los tres pendulos; cada uno detiene la
# simulacion exactamente en t_final y las graficas muestran [0, t_final],
# igual que plot(t, ...) en MATLAB.

const MINIMO_S: float = 0.5
const MAXIMO_S: float = 120.0

var spin: SpinBox
var _lbl_estado: Label


func _init(t_inicial: float = 3.0) -> void:
	add_theme_constant_override("separation", 2)

	var titulo := Label.new()
	titulo.text = "Tiempo de simulación"
	add_child(titulo)

	spin = SpinBox.new()
	spin.min_value = MINIMO_S
	spin.max_value = MAXIMO_S
	spin.step = 0.1
	spin.prefix = "t final:"
	spin.suffix = "s"
	spin.value = clampf(t_inicial, MINIMO_S, MAXIMO_S)
	add_child(spin)

	_lbl_estado = Label.new()
	_lbl_estado.add_theme_font_size_override("font_size", 13)
	_lbl_estado.modulate = Color(1, 1, 1, 0.8)
	add_child(_lbl_estado)
	mostrar(0.0, false)


# Duracion elegida [s]
func t_final() -> float:
	return spin.value


# Linea de estado: "t = 1.25 / 3.00 s" o "✓ Terminada en 3.00 s"
func mostrar(t: float, terminada: bool) -> void:
	if terminada:
		_lbl_estado.text = "✓ Terminada en %.2f s" % t
		_lbl_estado.add_theme_color_override("font_color", Color(0.45, 0.9, 0.5))
	else:
		_lbl_estado.text = "t = %.2f / %.2f s" % [t, spin.value]
		_lbl_estado.remove_theme_color_override("font_color")

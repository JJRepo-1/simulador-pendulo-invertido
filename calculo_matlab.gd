class_name CalculoMatlab
extends Node

# ============================================================
# CALCULO DE GANANCIAS CON MATLAB (MODO BATCH)
# ============================================================
# Flujo:
#   1. Advertencia: se necesita MATLAB con YALMIP y SeDuMi. El usuario
#      revisa la ruta de MATLAB, alpha y beta, y elige Aceptar o Cancelar.
#   2. Se escribe entrada.json (A, B, alpha, beta) en la carpeta de datos
#      del usuario y se copia ahi matlab/calcular_ganancias.m.
#   3. Se lanza, sin bloquear la ventana:
#        matlab -batch "addpath('<carpeta>'); calcular_ganancias('entrada.json','salida.json')"
#   4. Al terminar MATLAB se lee salida.json y se emite 'terminado'.
#
# Uso (configuracion.gd):
#   calculo.solicitar("regulador", A, B, 4, 2.0, 10.0)
#   calculo.terminado.connect(func(sistema, K, polos): ...)

signal terminado(sistema: String, K: PackedFloat64Array, polos: Array[Vector2])

const SCRIPT_MATLAB: String = "res://matlab/calcular_ganancias.m"
const CARPETA_TRABAJO: String = "user://matlab"
const AJUSTES: String = "user://ajustes.cfg"
const TIEMPO_MAXIMO_S: float = 300.0

const NOMBRES: Dictionary = {
	"regulador": "Péndulo con control (regulación): A 4×4, K = [K1 K2 K3 K4]",
	"seguimiento": "Seguimiento de trayectoria: Aa 5×5, Ka = [K1 K2 K3 K4 −ki]",
}

var _sistema: String = ""
var _A := PackedFloat64Array()
var _B := PackedFloat64Array()
var _n: int = 4

var _alpha: float = 0.0
var _beta: float = 0.0
var _pid: int = -1
var _transcurrido: float = 0.0
var _salida_global: String = ""

# Ventanas
var _dlg_confirmar: ConfirmationDialog
var _lbl_sistema: Label
var _txt_ruta: LineEdit
var _spin_alpha: SpinBox
var _spin_beta: SpinBox
var _dlg_progreso: AcceptDialog
var _lbl_progreso: Label
var _dlg_resultado: AcceptDialog


func _ready() -> void:
	_construir_dialogos()
	set_process(false)


# ------------------------------------------------------------
# API
# ------------------------------------------------------------

# Abre la advertencia. A: n*n por filas, B: n.
func solicitar(sistema: String, A: PackedFloat64Array, B: PackedFloat64Array, n: int,
		alpha: float, beta: float) -> void:
	if _pid != -1:
		_mostrar_resultado("Ya hay un cálculo en curso.", false)
		return
	_sistema = sistema
	_A = A
	_B = B
	_n = n
	_lbl_sistema.text = "Sistema: " + NOMBRES.get(sistema, sistema)
	_spin_alpha.value = alpha
	_spin_beta.value = beta
	if _txt_ruta.text.strip_edges() == "":
		_txt_ruta.text = detectar_matlab()
	_dlg_confirmar.reset_size()
	_dlg_confirmar.popup_centered()


# Ruta guardada, o la que se encuentre en el PATH o en las carpetas habituales.
static func detectar_matlab() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(AJUSTES) == OK:
		var guardada: String = cfg.get_value("matlab", "ruta", "")
		if guardada != "" and FileAccess.file_exists(guardada):
			return guardada

	var salida: Array = []
	var comando: String = "where" if OS.get_name() == "Windows" else "which"
	if OS.execute(comando, ["matlab"], salida) == 0 and salida.size() > 0:
		var primera: String = String(salida[0]).split("\n")[0].strip_edges()
		if primera != "" and FileAccess.file_exists(primera):
			return primera

	var bases: Array[String] = []
	var relativo: String = "bin/matlab"
	match OS.get_name():
		"Windows":
			bases = ["C:/Program Files/MATLAB", "C:/Program Files (x86)/MATLAB"]
			relativo = "bin/matlab.exe"
		"macOS":
			bases = ["/Applications"]
		_:
			bases = ["/usr/local/MATLAB", "/opt/MATLAB"]
	for base: String in bases:
		var dir := DirAccess.open(base)
		if dir == null:
			continue
		var versiones: PackedStringArray = dir.get_directories()
		versiones.sort()
		versiones.reverse()   # la version mas reciente primero (R2026b > R2024a)
		for v: String in versiones:
			if OS.get_name() == "macOS" and not v.begins_with("MATLAB_"):
				continue
			var ruta: String = base.path_join(v).path_join(relativo)
			if FileAccess.file_exists(ruta):
				return ruta
	return ""


# ------------------------------------------------------------
# Ventanas
# ------------------------------------------------------------

func _construir_dialogos() -> void:
	# 1. Advertencia y opciones
	_dlg_confirmar = ConfirmationDialog.new()
	_dlg_confirmar.title = "Calcular ganancias con MATLAB"
	_dlg_confirmar.ok_button_text = "Aceptar"
	_dlg_confirmar.cancel_button_text = "Cancelar"
	_dlg_confirmar.min_size = Vector2i(560, 0)
	_dlg_confirmar.confirmed.connect(_on_confirmado)
	add_child(_dlg_confirmar)

	var caja := VBoxContainer.new()
	caja.add_theme_constant_override("separation", 8)
	_dlg_confirmar.add_child(caja)

	var aviso := Label.new()
	aviso.text = ("⚠ Para continuar es necesario que tengas MATLAB instalado en esta PC, "
		+ "con YALMIP y SeDuMi agregados al path de MATLAB.\n"
		+ "MATLAB se abrirá en segundo plano para resolver el LMI; puede tardar de 10 a 60 segundos.")
	aviso.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	aviso.custom_minimum_size = Vector2(540, 0)
	aviso.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2))
	caja.add_child(aviso)

	_lbl_sistema = Label.new()
	_lbl_sistema.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_sistema.custom_minimum_size = Vector2(540, 0)
	caja.add_child(_lbl_sistema)

	var fila_lmi := HBoxContainer.new()
	fila_lmi.add_theme_constant_override("separation", 10)
	caja.add_child(fila_lmi)
	var lbl_region := Label.new()
	lbl_region.text = "Región de polos:  −β ≤ Re(p) ≤ −α"
	fila_lmi.add_child(lbl_region)
	_spin_alpha = _spin("α:", 0.0, 1000.0)
	fila_lmi.add_child(_spin_alpha)
	_spin_beta = _spin("β:", 0.0, 10000.0)
	fila_lmi.add_child(_spin_beta)

	var lbl_ruta := Label.new()
	lbl_ruta.text = "Ruta de MATLAB (matlab.exe):"
	caja.add_child(lbl_ruta)
	_txt_ruta = LineEdit.new()
	_txt_ruta.placeholder_text = "C:/Program Files/MATLAB/R20xxx/bin/matlab.exe"
	caja.add_child(_txt_ruta)

	# 2. Progreso
	_dlg_progreso = AcceptDialog.new()
	_dlg_progreso.title = "MATLAB"
	_dlg_progreso.ok_button_text = "Cancelar cálculo"
	_dlg_progreso.dialog_close_on_escape = false
	_dlg_progreso.confirmed.connect(_cancelar)
	_dlg_progreso.canceled.connect(_cancelar)
	add_child(_dlg_progreso)
	_lbl_progreso = Label.new()
	_lbl_progreso.custom_minimum_size = Vector2(420, 0)
	_lbl_progreso.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dlg_progreso.add_child(_lbl_progreso)

	# 3. Resultado
	_dlg_resultado = AcceptDialog.new()
	_dlg_resultado.title = "Resultado del cálculo"
	_dlg_resultado.ok_button_text = "Aceptar"
	_dlg_resultado.min_size = Vector2i(520, 0)
	add_child(_dlg_resultado)


func _spin(prefijo: String, minimo: float, maximo: float) -> SpinBox:
	var s := SpinBox.new()
	s.prefix = prefijo
	s.min_value = minimo
	s.max_value = maximo
	s.step = 0.1
	s.custom_minimum_size = Vector2(110, 0)
	return s


func _mostrar_resultado(texto: String, ok: bool) -> void:
	_dlg_resultado.dialog_text = texto
	_dlg_resultado.title = "Ganancias calculadas" if ok else "No se pudo calcular"
	_dlg_resultado.popup_centered()


# ------------------------------------------------------------
# Ejecucion
# ------------------------------------------------------------

func _on_confirmado() -> void:
	var ruta: String = _txt_ruta.text.strip_edges().replace("\\", "/")
	if ruta == "" or not FileAccess.file_exists(ruta):
		_mostrar_resultado("No se encontró MATLAB en:\n%s\n\nEscribe la ruta completa de matlab.exe "
			% (ruta if ruta != "" else "(vacío)")
			+ "(por ejemplo C:/Program Files/MATLAB/R2024a/bin/matlab.exe).", false)
		return
	var alpha: float = _spin_alpha.value
	var beta: float = _spin_beta.value
	if beta <= alpha:
		_mostrar_resultado("β debe ser mayor que α.", false)
		return
	_alpha = alpha
	_beta = beta

	var cfg := ConfigFile.new()
	cfg.load(AJUSTES)
	cfg.set_value("matlab", "ruta", ruta)
	cfg.save(AJUSTES)

	var error: String = _preparar_archivos(alpha, beta)
	if error != "":
		_mostrar_resultado(error, false)
		return

	var carpeta: String = ProjectSettings.globalize_path(CARPETA_TRABAJO)
	var entrada: String = carpeta.path_join("entrada.json")
	_salida_global = carpeta.path_join("salida.json")
	var comando: String = "addpath('%s'); calcular_ganancias('%s','%s')" % [
		_matlab_str(carpeta), _matlab_str(entrada), _matlab_str(_salida_global)]

	# -wait: en Windows el lanzador matlab.exe espera a que termine el calculo
	var argumentos := PackedStringArray(["-batch", comando])
	if OS.get_name() == "Windows":
		argumentos = PackedStringArray(["-wait", "-batch", comando])
	_pid = OS.create_process(ruta, argumentos)
	if _pid == -1:
		_mostrar_resultado("No se pudo iniciar MATLAB:\n" + ruta, false)
		return

	_transcurrido = 0.0
	_actualizar_progreso()
	_dlg_progreso.popup_centered()
	set_process(true)


# Escribe entrada.json y copia la funcion de MATLAB a la carpeta de trabajo.
func _preparar_archivos(alpha: float, beta: float) -> String:
	DirAccess.make_dir_recursive_absolute(CARPETA_TRABAJO)

	var fuente := FileAccess.open(SCRIPT_MATLAB, FileAccess.READ)
	if fuente == null:
		return "No se encontró %s dentro del proyecto." % SCRIPT_MATLAB
	var codigo: String = fuente.get_as_text()
	fuente.close()
	var destino := FileAccess.open(CARPETA_TRABAJO.path_join("calcular_ganancias.m"), FileAccess.WRITE)
	if destino == null:
		return "No se pudo escribir en la carpeta de trabajo."
	destino.store_string(codigo)
	destino.close()

	var filas: Array = []
	for i in range(_n):
		var fila: Array = []
		for j in range(_n):
			fila.append(_A[i * _n + j])
		filas.append(fila)
	var datos: Dictionary = {
		"A": filas,
		"B": Array(_B),
		"alpha": alpha,
		"beta": beta,
		"ts": 0.001,
	}
	var archivo := FileAccess.open(CARPETA_TRABAJO.path_join("entrada.json"), FileAccess.WRITE)
	if archivo == null:
		return "No se pudo escribir entrada.json."
	archivo.store_string(JSON.stringify(datos, "  ", false, true))
	archivo.close()

	if FileAccess.file_exists(CARPETA_TRABAJO.path_join("salida.json")):
		DirAccess.remove_absolute(CARPETA_TRABAJO.path_join("salida.json"))
	return ""


func _matlab_str(ruta: String) -> String:
	return ruta.replace("\\", "/").replace("'", "''")


func _process(delta: float) -> void:
	if _pid == -1:
		set_process(false)
		return
	_transcurrido += delta
	_actualizar_progreso()

	var corriendo: bool = OS.is_process_running(_pid)
	if corriendo and _transcurrido < TIEMPO_MAXIMO_S:
		return
	if corriendo:
		OS.kill(_pid)
		_terminar()
		_mostrar_resultado("MATLAB tardó más de %d s y se canceló el cálculo." % int(TIEMPO_MAXIMO_S), false)
		return
	_terminar()
	_leer_resultado()


func _actualizar_progreso() -> void:
	_lbl_progreso.text = ("Calculando con MATLAB (YALMIP + SeDuMi)…  %d s\n\n"
		+ "La primera vez MATLAB tarda en iniciar. No cierres esta pantalla.") % int(_transcurrido)


func _cancelar() -> void:
	if _pid != -1:
		if OS.is_process_running(_pid):
			OS.kill(_pid)
		_terminar()


func _terminar() -> void:
	_pid = -1
	set_process(false)
	if _dlg_progreso.visible:
		_dlg_progreso.hide()


func _leer_resultado() -> void:
	var archivo := FileAccess.open(_salida_global, FileAccess.READ)
	if archivo == null:
		_mostrar_resultado("MATLAB terminó sin generar resultados.\n\n"
			+ "Revisa que la ruta sea la de MATLAB y que tengas licencia activa. "
			+ "Puedes probar la función a mano en MATLAB:\n"
			+ "calcular_ganancias('entrada.json','salida.json')\n"
			+ "en la carpeta:\n" + ProjectSettings.globalize_path(CARPETA_TRABAJO), false)
		return
	var datos = JSON.parse_string(archivo.get_as_text())
	archivo.close()
	if typeof(datos) != TYPE_DICTIONARY:
		_mostrar_resultado("La salida de MATLAB no es un JSON válido.", false)
		return
	if not datos.get("ok", false):
		_mostrar_resultado("MATLAB respondió con un error:\n\n" + str(datos.get("error", "desconocido")), false)
		return

	var K := PackedFloat64Array()
	for v in _como_arreglo(datos.get("K", [])):
		K.append(float(v))
	if K.size() != _n:
		_mostrar_resultado("MATLAB devolvió %d ganancias y se esperaban %d." % [K.size(), _n], false)
		return

	var re: Array = _como_arreglo(datos.get("polos_re", []))
	var im: Array = _como_arreglo(datos.get("polos_im", []))
	var polos: Array[Vector2] = []
	for i in range(mini(re.size(), im.size())):
		polos.append(Vector2(float(re[i]), float(im[i])))

	var textos_K: Array[String] = []
	for v: float in K:
		textos_K.append(String.num(v, 4))
	var textos_p: Array[String] = []
	var estable: bool = true
	var en_region: bool = true
	for p: Vector2 in polos:
		textos_p.append(Algebra.texto_polo(p))
		estable = estable and p.x < 0.0
		en_region = en_region and p.x <= -_alpha + 1e-6 and p.x >= -_beta - 1e-6
	var estado: String = "⚠ El lazo cerrado NO es estable."
	if estable and en_region:
		estado = "Estable: todos los polos cumplen −%s ≤ Re(p) ≤ −%s." % [String.num(_beta, 2), String.num(_alpha, 2)]
	elif estable:
		estado = "Estable, pero algún polo quedó fuera de la región pedida (−β ≤ Re ≤ −α)."
	var info: String = str(datos.get("info", ""))
	var texto: String = "%s = [ %s ]\n\nPolos de lazo cerrado:\n%s\n\n%s\nSolver: %s\n" % [
		"K" if _sistema == "regulador" else "Ka",
		"   ".join(textos_K), ",   ".join(textos_p), estado, info]
	if not info.contains("Successfully"):
		texto += "⚠ SeDuMi no reportó una solución limpia; revisa los polos antes de usar estas ganancias.\n"
	texto += "\n"
	texto += "Los valores se copiaron a la pantalla. Presiona \"Guardar datos\" para usarlos en la simulación."
	_mostrar_resultado(texto, true)
	terminado.emit(_sistema, K, polos)


# jsonencode de MATLAB devuelve un escalar si el vector tiene un solo elemento.
func _como_arreglo(valor) -> Array:
	if valor is Array:
		return valor
	return [valor]


func _exit_tree() -> void:
	_cancelar()

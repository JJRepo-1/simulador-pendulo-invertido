class_name RegistroSimulacion
extends RefCounted

# ============================================================
# REGISTRO DE UNA SIMULACION (para metricas y exportacion CSV)
# ============================================================
# Guarda una fila por paso de integracion (no por cuadro de pantalla),
# asi las metricas y el CSV tienen la resolucion de la simulacion.
# Todas las columnas van en el Sistema Internacional (m, rad, N, s),
# igual que el vector q de los scripts de MATLAB.

var columnas: PackedStringArray
var unidades: PackedStringArray
var _datos: Array[PackedFloat64Array] = []


func _init(nombres: PackedStringArray, unidades_si: PackedStringArray) -> void:
	columnas = nombres
	unidades = unidades_si
	limpiar()


func limpiar() -> void:
	_datos.clear()
	for _c in columnas:
		_datos.append(PackedFloat64Array())


# Agrega una fila; 'valores' en el mismo orden que 'columnas'.
func agregar(valores: Array) -> void:
	for i in range(columnas.size()):
		_datos[i].append(float(valores[i]) if i < valores.size() else NAN)


func tamano() -> int:
	return _datos[0].size() if not _datos.is_empty() else 0


func tiene(nombre: String) -> bool:
	return columnas.has(nombre)


func columna(nombre: String) -> PackedFloat64Array:
	var i: int = columnas.find(nombre)
	return _datos[i] if i >= 0 else PackedFloat64Array()


# Escribe el CSV: lineas de metadatos con '#' y despues los datos.
# En MATLAB:  T = readtable('archivo.csv', 'CommentStyle', '#');
func exportar_csv(ruta: String, metadatos: PackedStringArray) -> Error:
	var f := FileAccess.open(ruta, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	for linea: String in metadatos:
		f.store_line("# " + linea)
	var u: PackedStringArray = []
	for i in range(columnas.size()):
		u.append("%s[%s]" % [columnas[i], unidades[i]])
	f.store_line("# unidades: " + ", ".join(u))
	f.store_line("# MATLAB: T = readtable('archivo.csv', 'CommentStyle', '#');  plot(T.t, T.x)")
	f.store_line(",".join(columnas))
	var fila := PackedStringArray()
	fila.resize(columnas.size())
	for k in range(tamano()):
		for i in range(columnas.size()):
			var v: float = _datos[i][k]
			fila[i] = "NaN" if is_nan(v) else String.num(v, 9)
		f.store_line(",".join(fila))
	f.close()
	return OK

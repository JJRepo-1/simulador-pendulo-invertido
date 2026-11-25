class_name Creditos
extends Control

# ============================================================
# PANTALLA DE CREDITOS Y LICENCIAS
# ============================================================
# Muestra el autor, la licencia del proyecto (CC BY-NC-SA 4.0) y los
# avisos de licencia de Godot Engine y de sus componentes de terceros.
# Los textos del motor se obtienen del propio motor (Engine.get_license_text,
# get_copyright_info, get_license_info), asi siempre corresponden a la
# version con la que se exporto el ejecutable, como pide su licencia MIT.

const AUTOR: String = "Josue Jordan Ramos Sanchez"
const COLABORADORES: Array[String] = [
	"Ernesto Imanol Ramírez Hernández",
	"Jesús Salvador Martínez Farías",
]
const TITULO_ARTICULO: String = ("Desarrollo de una herramienta educativa para simular un péndulo "
	+ "invertido con carrito mediante Godot y MATLAB")
const REPOSITORIO: String = "https://github.com/JJRepo-1/simulador-pendulo-invertido"
const LICENCIA_URL: String = "https://creativecommons.org/licenses/by-nc-sa/4.0/deed.es"


func _ready() -> void:
	get_tree().root.content_scale_size = Vector2i(1280, 720)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_construir()


func _construir() -> void:
	var margen := MarginContainer.new()
	margen.set_anchors_preset(Control.PRESET_FULL_RECT)
	for lado: String in ["left", "right", "top", "bottom"]:
		margen.add_theme_constant_override("margin_" + lado, 30)
	add_child(margen)

	var caja := VBoxContainer.new()
	caja.add_theme_constant_override("separation", 10)
	margen.add_child(caja)

	var titulo := Label.new()
	titulo.text = "Créditos y licencias"
	titulo.add_theme_font_size_override("font_size", 32)
	caja.add_child(titulo)

	var texto := RichTextLabel.new()
	texto.bbcode_enabled = true
	texto.size_flags_vertical = Control.SIZE_EXPAND_FILL
	texto.selection_enabled = true
	texto.add_theme_font_size_override("normal_font_size", 15)
	texto.add_theme_font_size_override("bold_font_size", 15)
	texto.add_theme_font_size_override("mono_font_size", 12)
	texto.meta_clicked.connect(func(meta) -> void: OS.shell_open(str(meta)))
	texto.text = texto_bbcode()
	caja.add_child(texto)

	var btn_volver := Button.new()
	btn_volver.text = "Volver al inicio"
	btn_volver.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	btn_volver.add_theme_font_size_override("font_size", 20)
	btn_volver.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://main.tscn"))
	caja.add_child(btn_volver)


# ------------------------------------------------------------
# Textos (tambien los usa la generacion de LICENCIAS.txt)
# ------------------------------------------------------------

static func version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))


static func texto_bbcode() -> String:
	var t: PackedStringArray = []
	t.append("[b]Simulador de Péndulo Invertido[/b]  v%s" % version())
	t.append("Plataforma didáctica gratuita y sin fines de lucro.")
	t.append("[url=%s]%s[/url]" % [REPOSITORIO, REPOSITORIO])
	t.append("")
	t.append("[b]Autor[/b]")
	t.append(AUTOR)
	t.append("")
	t.append("[b]Artículo asociado[/b]")
	t.append("[i]%s[/i] (en preparación)." % TITULO_ARTICULO)
	t.append("Colaboradores en la investigación: " + " y ".join(COLABORADORES) + ".")
	t.append("")
	t.append("[b]Licencia de este proyecto[/b]")
	t.append("© 2026 %s. Esta obra está bajo la licencia Creative Commons " % AUTOR
		+ "Atribución-NoComercial-CompartirIgual 4.0 Internacional (CC BY-NC-SA 4.0): "
		+ "puedes usarla, compartirla y modificarla con fines no comerciales, dando crédito "
		+ "al autor y publicando tus cambios con la misma licencia.")
	t.append("[url=%s]%s[/url]" % [LICENCIA_URL, LICENCIA_URL])
	t.append("")
	t.append("[b]Otros créditos[/b]")
	t.append("• MATLAB es marca registrada de The MathWorks, Inc. YALMIP y SeDuMi son "
		+ "herramientas externas: no se incluyen, solo se usan si el usuario ya las tiene instaladas.")
	t.append("")
	t.append("[b]Godot Engine[/b]")
	t.append("Este programa usa Godot Engine, disponible bajo la siguiente licencia:")
	t.append("[code]" + _escapar(Engine.get_license_text()) + "[/code]")
	t.append("")
	t.append("[b]Componentes de terceros incluidos en Godot Engine[/b]")
	t.append(_escapar(componentes_terceros()))
	t.append("")
	t.append("[b]Textos de las licencias de terceros[/b]")
	t.append("[code]" + _escapar(textos_licencias()) + "[/code]")
	return "\n".join(t)


# Version en texto plano para LICENCIAS.txt
static func texto_plano() -> String:
	var t: PackedStringArray = []
	var linea: String = "=".repeat(72)
	t.append(linea)
	t.append("SIMULADOR DE PÉNDULO INVERTIDO v%s - CRÉDITOS Y LICENCIAS" % version())
	t.append(linea)
	t.append("")
	t.append("Autor: " + AUTOR)
	t.append("Repositorio: " + REPOSITORIO)
	t.append("")
	t.append("Artículo asociado (en preparación):")
	t.append("  " + TITULO_ARTICULO)
	t.append("  Colaboradores en la investigación: " + " y ".join(COLABORADORES) + ".")
	t.append("")
	t.append(linea)
	t.append("LICENCIA DE ESTE PROYECTO")
	t.append(linea)
	t.append("© 2026 %s." % AUTOR)
	t.append("Esta obra está bajo la licencia Creative Commons")
	t.append("Atribución-NoComercial-CompartirIgual 4.0 Internacional (CC BY-NC-SA 4.0).")
	t.append("Resumen: " + LICENCIA_URL)
	t.append("Texto legal completo: archivo LICENSE del repositorio.")
	t.append("")
	t.append("Otros créditos:")
	t.append("- MATLAB es marca registrada de The MathWorks, Inc. YALMIP y SeDuMi son")
	t.append("  herramientas externas: no se incluyen, solo se usan si el usuario ya las tiene.")
	t.append("")
	t.append(linea)
	t.append("GODOT ENGINE")
	t.append(linea)
	t.append("Este programa usa Godot Engine, disponible bajo la siguiente licencia:")
	t.append("")
	t.append(Engine.get_license_text())
	t.append("")
	t.append(linea)
	t.append("COMPONENTES DE TERCEROS INCLUIDOS EN GODOT ENGINE")
	t.append(linea)
	t.append(componentes_terceros())
	t.append("")
	t.append(linea)
	t.append("TEXTOS DE LAS LICENCIAS DE TERCEROS")
	t.append(linea)
	t.append(textos_licencias())
	return "\n".join(t)


# Lista de componentes con su copyright y licencia (Engine.get_copyright_info).
static func componentes_terceros() -> String:
	var t: PackedStringArray = []
	for componente: Dictionary in Engine.get_copyright_info():
		if str(componente.get("name", "")) == "Godot Engine":
			continue
		t.append("- " + str(componente.get("name", "")))
		for parte: Dictionary in componente.get("parts", []):
			for c in parte.get("copyright", []):
				t.append("    © " + str(c))
			t.append("    Licencia: " + str(parte.get("license", "")))
	return "\n".join(t)


# Textos completos de cada licencia usada por los componentes (Engine.get_license_info).
static func textos_licencias() -> String:
	var t: PackedStringArray = []
	var info: Dictionary = Engine.get_license_info()
	var nombres: Array = info.keys()
	nombres.sort()
	for nombre in nombres:
		t.append("----- " + str(nombre) + " -----")
		t.append(str(info[nombre]))
		t.append("")
	return "\n".join(t)


static func _escapar(texto: String) -> String:
	return texto.replace("[", "[lb]")

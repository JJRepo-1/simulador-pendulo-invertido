extends Node2D

var penduloSuelto : PackedScene = load("res://pendulo.tscn")
var penduloLineal : PackedScene = load("res://pendulo2.tscn")

@onready var macador: Marker2D = $Marker2D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	get_window().content_scale_size = Vector2i(720, 380)
	var pendulo: PackedScene = null
	match Globals.PenduloSeleccion:
		0:
			pendulo = penduloSuelto
		1:
			pendulo = penduloLineal
	
	if pendulo != null:
		var nuevaInstancia = pendulo.instantiate()
		nuevaInstancia.global_position = macador.global_position
		add_child(nuevaInstancia)
	


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_button_pressed() -> void:
	get_tree().change_scene_to_file("res://main.tscn")

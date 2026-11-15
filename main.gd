extends Control


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	get_tree().root.content_scale_size = Vector2i(1280, 720)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_button_pressed() -> void:
	Globals._set_escena(0)

func _on_lineal_pressed() -> void:
	Globals._set_escena(1)


func _on_opciones_pressed() -> void:
	get_tree().change_scene_to_file("res://configuracion.tscn")

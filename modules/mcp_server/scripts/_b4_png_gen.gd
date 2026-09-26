extends SceneTree

func _init() -> void:
	var img := Image.create_empty(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 1))
	img.set_pixel(0, 0, Color(1, 0, 0, 1))
	var err := img.save_png("res://source.png")
	print("SAVE_ERR=", err)
	quit(0)

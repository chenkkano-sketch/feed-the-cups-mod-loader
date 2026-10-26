extends Node2D
var cells = []
func _draw():
	for cell in cells:
		draw_rect(Rect2(cell * 100, Vector2(100, 100)), Color(0.1, 0.9, 0.7, 0.12), true)
		draw_rect(Rect2(cell * 100, Vector2(100, 100)), Color(0.2, 1.0, 0.8, 0.65), false, 2)

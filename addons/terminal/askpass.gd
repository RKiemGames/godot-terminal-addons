extends Control

func _ready():
	pass

func _on_LineEdit_text_entered(new_text):
	print(new_text)
	get_parent().visible = false

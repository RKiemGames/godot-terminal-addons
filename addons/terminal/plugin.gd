@tool
extends EditorPlugin

var dock : Node

func _enter_tree():
	dock = preload("res://addons/terminal/dock.tscn").instantiate()
	
	add_control_to_bottom_panel(dock, "Terminal")
	#add_control_to_dock(DOCK_SLOT_RIGHT_BR, dock)
	

func _exit_tree():
	remove_control_from_bottom_panel(dock)
	#remove_control_from_docks(dock) # Remove the dock
	dock.queue_free()

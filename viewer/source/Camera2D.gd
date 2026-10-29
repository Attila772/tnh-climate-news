extends Camera2D
# Customize these values as needed
var zoom_speed: float = 0.01
var min_zoom: float = 0.1
var max_zoom: float = 5.0
var dragging: bool = false
var drag_last_position: Vector2

func _ready():
	var dir = DirAccess.open("user://")
	dir.make_dir("screenshots")
	# Initial setup if needed
	pass

func _input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				dragging = true
				drag_last_position = event.global_position
			else:
				dragging = false
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var zoom_direction = 0
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				zoom_direction = 1
			else:
				zoom_direction = -1

			zoom += Vector2(zoom_speed, zoom_speed) * zoom_direction
			# Clamp the zoom value
			zoom.x = clamp(zoom.x, min_zoom, max_zoom)
			zoom.y = clamp(zoom.y, min_zoom, max_zoom)
			zoom += Vector2(zoom_speed, zoom_speed) * zoom_direction
			# Clamp the zoom value to ensure it's within the min and max thresholds
			zoom.x = clamp(zoom.x, min_zoom, max_zoom)
			zoom.y = clamp(zoom.y, min_zoom, max_zoom)
	
	elif event is InputEventMouseMotion and dragging:
		# Calculate the drag movement
		var drag_current_position = event.global_position
		var drag_delta = drag_last_position - drag_current_position
		# Move the camera based on the drag
		position += drag_delta
		drag_last_position = drag_current_position


var exporting = false

func _on_button_button_up() -> void:
	if exporting:
		return
	exporting = true
	var button = get_parent().get_node("CanvasLayer2/Button")
	button.hide()
	for ui in get_tree().get_nodes_in_group("export_ui"):
		ui.hide()
	Global.high_quality = true
	for edge in get_tree().get_nodes_in_group("edges"):
		edge.recalculate_edge()
		edge.queue_redraw()
	await RenderingServer.frame_post_draw
	var config = ConfigFile.new()
	config.load(Global.config_path())
	var folder = str(config.get_value("graph_settings", "screenshot_path", "user://screenshots"))
	if folder.is_empty():
		folder = "user://screenshots"
	if folder.is_relative_path():
		folder = Global.viewer_dir().path_join(folder)  # e.g. "exports" next to the program
	else:
		folder = ProjectSettings.globalize_path(folder)
	var dir_error = DirAccess.make_dir_recursive_absolute(folder)
	if dir_error == OK:
		var count = 0
		var stem = folder.path_join("ss0")
		while FileAccess.file_exists(stem+".png") or FileAccess.file_exists(stem+".svg") or FileAccess.file_exists(stem+".layout.json"):
			count += 1
			stem = folder.path_join("ss"+str(count))
		var png_error = get_viewport().get_texture().get_image().save_png(stem+".png")
		var svg_error = preload("res://SceneSvg.gd").save(get_tree(),get_viewport(),stem+".svg")
		var positions = {}
		for n in get_tree().get_nodes_in_group("nodes"):
			positions[n.node_id] = [n.position.x,n.position.y]
		var file = FileAccess.open(stem+".layout.json",FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify({"positions":positions,"camera":[position.x,position.y],"zoom":[zoom.x,zoom.y]},"  "))
		if png_error != OK or svg_error != OK or file == null:
			push_error("Export failed: PNG=%s SVG=%s layout=%s" % [png_error,svg_error,file!=null])
		else:
			print("Saved PNG + SVG + layout: ",stem)
	else:
		push_error("Cannot create export directory: "+folder)
	Global.high_quality = false
	button.show()
	for ui in get_tree().get_nodes_in_group("export_ui"):
		ui.show()
	exporting = false

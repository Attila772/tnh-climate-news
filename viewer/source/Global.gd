extends Node

var group_dictionary = {}
var group_count = 0
var high_quality = false
var total_nodes = 0
var edges = null

# Function to initialize the groups from a list of group names
func initialize_groups(group_names: Array):
	group_dictionary.clear()
	group_count = 0
	
	# Add each group name with an index (1-based)
	for group_name in group_names:
		group_count += 1
		group_dictionary[group_name] = group_count

# Function to get the index of a group name
func get_group_index(group_name: String) -> int:
	if group_name in group_dictionary:
		return group_dictionary[group_name]
	return -1 # Return -1 if the group is not found

# Function to get group name by index (if needed later)
func get_group_name(group_index: int) -> String:
	for gname in group_dictionary:
		if group_dictionary[gname] == group_index:
			return gname
	return ""

## Labels use the bundled Liberation Serif (SIL OFL), which has the same metrics as
## Times New Roman. If "Times New Roman.ttf" is placed next to the program, it is used
## instead, which reproduces the figures of the paper exactly.
var _label_font = null
func label_font():
	if _label_font == null:
		var path = viewer_dir().path_join("Times New Roman.ttf")
		if FileAccess.file_exists(path):
			var f = FontFile.new()
			if f.load_dynamic_font(path) == OK:
				_label_font = f
		if _label_font == null:
			_label_font = false
	return _label_font if _label_font else null

## Settings: conf.cfg next to the program if present (editable without re-exporting),
## otherwise the copy packed into the program.
func config_path() -> String:
	var outside = viewer_dir().path_join("conf.cfg")
	return outside if FileAccess.file_exists(outside) else "res://conf.cfg"

var current_file = ""  # absolute path of the hypergraph (.txt) on screen

## Folder whose .txt files are listed: the folder of the exported program,
## or the folder that contains the Godot project when it is run from the editor.
func viewer_dir() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir()
	return OS.get_executable_path().get_base_dir()

func hypergraph_files() -> Array:
	var files = []
	var dir = DirAccess.open(viewer_dir())
	if dir:
		for f in dir.get_files():
			if f.get_extension().to_lower() == "txt":
				files.append(viewer_dir().path_join(f))
	files.sort()
	return files

var paper_width_expression: Expression = null
func paper_width(support):
	if paper_width_expression == null:
		var config=ConfigFile.new()
		config.load(Global.config_path())
		paper_width_expression=Expression.new()
		var error=paper_width_expression.parse(config.get_value("graph_settings","edge_width_expression","2.0"),["support","node_count","total_nodes"])
		if error != OK:
			push_error("Invalid edge-width expression")
			return 2.0
	return paper_width_expression.execute([support,0,0])

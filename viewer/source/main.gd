extends Node2D
const HGData = preload("res://core/hg_data.gd")
const HGLayouts = preload("res://core/hg_layouts.gd")
const HGExport = preload("res://core/hg_export.gd")


var edges : Dictionary
var nodes : Dictionary
var node_to_edges = {}  # node_id -> [edge_instances]
var file_data_cached = {}
var _edge_color_index = 0

func create_nodes(nodes: Dictionary):
	var scene = load("res://HyperNode.tscn")
	var row = 1
	var column = 1
	var spacing = Vector2(100, 100)
	var per_row = 10
	
	for id in nodes.keys():
		var node_instance = scene.instantiate()
		node_instance.node_id = id
		node_instance.name = str(id)
		node_instance.position = Vector2(column * spacing.x, row * spacing.y)
		node_instance._set_node_id(str(id))
		
		# Set the edges property for the node
		node_instance.edges = nodes[id]["edges"]
		
		# Connect the position change signal
		node_instance.connect("node_position_changed", _on_node_position_changed)
	
		# Add the node instance to the scene
		add_child(node_instance)
		
		# Increment column and row for positioning nodes
		column += 1
		if column >= per_row:
			column = 0
			row += 1

func _on_node_position_changed(node):
	# Only mark edges that are connected to this node as dirty
	if node_to_edges.has(node.node_id):
		for edge_instance in node_to_edges[node.node_id]:
			if edge_instance and edge_instance.has_method("mark_dirty"):
				edge_instance.mark_dirty()

func populate_edge_data(file_data):
	var hyperedge_scene = load("res://HyperEdge.tscn")
	var nodes = file_data["nodes"]  # Retrieve nodes from the file data
	var edges = file_data["edges"]  # Retrieve edges from the file data

	var group_names = []
	for edge_id in edges:
		var group_name = edges[edge_id]["group"]
		if group_name not in group_names:
			group_names.append(group_name)
	Global.initialize_groups(group_names)

	# Step 1: Build a per-node mapping of edge IDs to radii
	var node_edge_radius_map = {}  # Dictionary mapping node_id to {edge_id: radius}
	for node_id in nodes:
		var node_edges = nodes[node_id]["edges"]
		var circle_ref = get_node(str(node_id))  # Get node instance with 'offset_circles'
		var offset_circles = circle_ref.offset_circles  # List of radii for offset circles

		var edge_ids = node_edges.keys()
		var edge_radius_map = {}

		# Ensure there are enough radii for each edge
		if offset_circles.size() < edge_ids.size():
			print("Error: Node %s has more edges (%s) than offset circles provided." % [node_id, edge_ids.size()])
			continue  # Skip this node if radii are insufficient

		# Map each edge_id to its corresponding radius for this node
		for i in range(edge_ids.size()):
			var edge_id = edge_ids[i]
			var radius = offset_circles[i]
			edge_radius_map[edge_id] = radius

		node_edge_radius_map[node_id] = edge_radius_map

	# Step 2: Build edges data using node_edge_radius_map
	for edge_id in edges:
		var edge_nodes = edges[edge_id]["nodes"]  # Nodes connected by this edge
		var edge_radii = []
		var edge_node_ids = []

		for node_id in edge_nodes:
			if node_edge_radius_map.has(node_id):
				var edge_radius_map = node_edge_radius_map[node_id]
				if edge_radius_map.has(edge_id):
					var radius = edge_radius_map[edge_id]
					edge_node_ids.append(node_id)
					edge_radii.append(radius)
				else:
					print("Error: Edge radius not found for node %s and edge %s" % [node_id, edge_id])
			else:
				print("Error: Node %s not found in node_edge_radius_map" % node_id)

		# Update edges[edge_id] with aligned nodes and radii
		edges[edge_id]["nodes"] = edge_node_ids
		edges[edge_id]["radii"] = edge_radii

	# Step 3: Instantiate hyperedges and visualize them
	for edge_id in edges:
		var hyperedge_instance = hyperedge_scene.instantiate()
		var edge_data = edges[edge_id]
		var node_radii_pairs = {}

		# Ensure nodes and radii arrays are aligned
		if edge_data["nodes"].size() != edge_data["radii"].size():
			print("Error: Mismatch between nodes and radii sizes for edge", edge_id)
			continue  # Skip this edge if there's a mismatch

		# Map each node to its radius
		for i in range(edge_data["nodes"].size()):
			var nodeid = edge_data["nodes"][i]
			var radius = edge_data["radii"][i]
			node_radii_pairs[nodeid] = radius

		# Assign the nodes and radii to the hyperedge instance
		hyperedge_instance.nodes = node_radii_pairs

		# Deterministic color from the shared palette (reproducible renders)
		var color = HGExport.PALETTE[_edge_color_index % HGExport.PALETTE.size()]
		color.a = 0.5
		_edge_color_index += 1
		hyperedge_instance.color = color

		# Set the group name to the hyperedge instance for future use
		hyperedge_instance.group = edge_data["group"]

		hyperedge_instance.add_to_group("edges")
		hyperedge_instance.name = str(edge_id)
		var config = ConfigFile.new()
		var expression = Expression.new()
		var err = config.load(Global.config_path())
		var expression_text = config.get_value("graph_settings", "edge_width_expression")
	
		var error = expression.parse(expression_text, ["support", "node_count", "total_nodes"])

		if error != OK:
			$AcceptDialog.window_title = "Error"
			$AcceptDialog.dialog_text = "The expression cannot be parsed: " + error
			$AcceptDialog.get_ok().text = "Close"
			$AcceptDialog.popup_centered()
		# Set the width of the hyperedge based on the support value
		var result = expression.execute([edges[edge_id]["support"], edge_data["nodes"].size(), nodes.size()] )
		if result == null: 
			$AcceptDialog.title = "Error"
			$AcceptDialog.dialog_text = "The expression cannot be parsed:  Error" + str(error)
			$AcceptDialog.ok_button_text = "Close"
			$AcceptDialog.popup_centered()
			return 1.0
		hyperedge_instance.width = result

		# Add the hyperedge instance to the scene tree
		add_child(hyperedge_instance)
		
		# Build node-to-edges mapping
		for node_id in edge_data["nodes"]:
			if not node_to_edges.has(node_id):
				node_to_edges[node_id] = []
			node_to_edges[node_id].append(hyperedge_instance)
	
	Global.edges = edges



func _ready():
	# The hypergraphs are the .txt files next to the program (see Global.viewer_dir).
	var files = Global.hypergraph_files()
	if not files.has(Global.current_file):
		Global.current_file = files[0] if files.size() > 0 else ""
	if Global.current_file == "":
		call_deferred("paper_setup")
		return
	var file_data = read_file(Global.current_file)
	file_data_cached = file_data
	# Fill the class members too — apply_force_directed_layout reads them
	# (previously they stayed empty: the attraction force never fired)
	self.nodes = file_data["nodes"]
	self.edges = file_data["edges"]
	create_nodes(file_data["nodes"])
	calculate_centrality_and_resize_nodes(file_data)
	populate_edge_data(file_data)
	# Without a saved <name>.layout.json the layout of conf.cfg is computed.
	if not FileAccess.file_exists(layout_path()):
		apply_configured_layout(file_data)
	call_deferred("paper_setup")

func apply_configured_layout(file_data):
	# Load layout configuration from conf.cfg
	var config = ConfigFile.new()
	var err = config.load(Global.config_path())

	if err != OK:
		print("Error loading conf.cfg: ", err)
		return

	var layout = config.get_value("graph_settings", "layout", "")
	var parameters = config.get_value("graph_settings", "parameters", [])

	match layout:
		"force-directed":
			if parameters.size() == 3:
				apply_force_directed_layout(parameters[0], parameters[1], parameters[2])
				print("Applied force-directed layout with parameters: ", parameters)
			else:
				print("Invalid parameters for force-directed layout: ", parameters)
		"circular":
			if parameters.size() == 1:
				apply_circular_layout(parameters[0])
				print("Applied circular layout with parameter: ", parameters[0])
			else:
				print("Invalid parameters for circular layout: ", parameters)
		"radial":
			if parameters.size() == 1:
				apply_radial_layout(parameters[0],file_data)
				print("Applied radial layout with radius step: ", parameters[0])
			else:
				print("Invalid parameters for radial layout: ", parameters)
		"untangled":
			apply_untangled_layout(parameters)
			print("Applied untangled (containment-correct) layout")
		_:
			print("Unknown layout type: ", layout)



func read_file(path):
	# Shared, tolerant parser (accepts both "#GROUP:" and legacy "#GROUP")
	return HGData.parse_file(path)



# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
	
	
func apply_hyperedge_constrained_layout():
	var node_positions = {} # Dictionary to store node positions temporarily
	var edge_bounds = {} # Dictionary to store edge bounds (min and max positions)
	
	# Initialize node positions
	for node in get_children():
		if node.is_in_group("nodes"): # Assuming your nodes are added to a "nodes" group
			node_positions[node.node_id] = node.position
	
	# Calculate edge bounds based on nodes in the edge
	for edge_id in edges:
		var edge_nodes = edges[edge_id]["nodes"]
		var min_x = INF
		var min_y = INF
		var max_x = -INF
		var max_y = -INF
		
		for node_id in edge_nodes:
			var pos = node_positions[node_id]
			min_x = min(min_x, pos.x)
			min_y = min(min_y, pos.y)
			max_x = max(max_x, pos.x)
			max_y = max(max_y, pos.y)
		
		edge_bounds[edge_id] = Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))
	
	# Reposition nodes to ensure they are outside of edges they don't belong to
	for node_id in node_positions.keys():
		var node_pos = node_positions[node_id]
		for edge_id in edges:
			var edge_nodes = edges[edge_id]["nodes"]
			if node_id not in edge_nodes:
				var bounds = edge_bounds[edge_id]
				if bounds.has_point(node_pos):
					# Move the node outside the edge bounds
					var direction = (node_pos - bounds.position).normalized()
					node_positions[node_id] = bounds.position + bounds.size * direction
	
	# Update actual node positions
	for node in get_children():
		if node.is_in_group("nodes"):
			node.position = node_positions[node.node_id]
	
	
func apply_force_directed_layout(iterations: int, repulsion_force: float, spring_length: float):
	var node_positions = {} # Szótár a csomópontok pozícióinak ideiglenes tárolására
	var forces = {}         # Szótár a csomópontokra ható erők tárolására
	
	var all_nodes = []
	for child in get_children():
		if child.is_in_group("nodes"):
			all_nodes.append(child)

	if all_nodes.is_empty():
		print("Nincsenek csomópontok az elrendezéshez.")
		return

	# Kezdeti pozíciók és erők inicializálása
	for node in all_nodes:
		node_positions[node.node_id] = node.position
		forces[node.node_id] = Vector2.ZERO

	# Iteratív erőszimuláció
	for i in range(iterations):
		# --- 1. Vonzóerők számítása (ÚJ, SÚLYPONT-ALAPÚ LOGIKA) ---
		var edge_centers = {} # Szótár a hiperélek középpontjainak tárolására

		# Először minden hiperél középpontját kiszámoljuk
		for edge_id in edges:
			var edge_data = edges[edge_id]
			var center_pos = Vector2.ZERO
			var node_count_in_edge = edge_data["nodes"].size()
			
			if node_count_in_edge > 0:
				for node_id in edge_data["nodes"]:
					if node_positions.has(node_id):
						center_pos += node_positions[node_id]
				center_pos /= node_count_in_edge
				edge_centers[edge_id] = center_pos

		# Most alkalmazzuk a vonzóerőt a csomópontokra a középpontok felé
		for edge_id in edges:
			var edge_data = edges[edge_id]
			if not edge_centers.has(edge_id):
				continue

			var center = edge_centers[edge_id]
			for node_id in edge_data["nodes"]:
				if forces.has(node_id):
					var delta = center - node_positions[node_id]
					var distance = delta.length()
					
					# A Hooke-törvényhez hasonló rugóerő
					# A spring_length most a csomópont és a hiperél-középpont ideális távolsága
					var displacement = distance - spring_length
					var spring_force_magnitude = displacement * 0.1 # A 0.1 egy "rugóállandó", finomhangolható
					
					if distance > 0:
						forces[node_id] += delta.normalized() * spring_force_magnitude

		# --- 2. Taszítóerők számítása (VÁLTOZATLAN LOGIKA) ---
		for j in range(all_nodes.size()):
			for k in range(j + 1, all_nodes.size()):
				var node1_id = all_nodes[j].node_id
				var node2_id = all_nodes[k].node_id

				var delta = node_positions[node1_id] - node_positions[node2_id]
				var distance = delta.length()
				
				if distance > 0: # Elkerüljük a nullával való osztást
					# Az erő a távolság négyzetével fordítottan arányos a realisztikusabb hatásért
					var repulsive_force_magnitude = repulsion_force / (distance * distance)
					var force_vector = delta.normalized() * repulsive_force_magnitude
					
					forces[node1_id] += force_vector
					forces[node2_id] -= force_vector # Egyenlő és ellentétes erő

		# --- 3. Erők alkalmazása és pozíciók frissítése ---
		var damping = 0.9 # Csillapítás, hogy a rendszer stabilizálódjon és ne "robbanjon szét"
		for node_id in node_positions.keys():
			node_positions[node_id] += forces[node_id] * damping
			forces[node_id] = Vector2.ZERO # Erők nullázása a következő iterációhoz

	# Végleges pozíciók beállítása a szimuláció után
	for node in all_nodes:
		node.position = node_positions[node.node_id]
			
			
			
			

func apply_circular_layout(radius: float):
	var center = get_viewport_rect().size / 2
	var nodes = [] # List to store nodes
	for child in get_children():
		if child.is_in_group("nodes"):
			nodes.append(child)
	var node_count = nodes.size()
	var angle_step = 2 * PI / node_count
	for i in range(node_count):
		var node = nodes[i] # Get the node from the filtered list
		var angle = i * angle_step
		var x = center.x + radius * cos(angle)
		var y = center.y + radius * sin(angle)
		node.position = Vector2(x, y)
		
		
func calculate_centrality_and_resize_nodes(file_data):
	var nodes = file_data["nodes"]
	var max_centrality = 0
	var centrality_scores = {}
	Global.total_nodes = nodes.size()  # Store total node count in a global variable

	# Calculate centrality (degree centrality in this case)
	for node_id in nodes:
		var degree = nodes[node_id]["edges"].size()
		centrality_scores[node_id] = degree
		max_centrality = max(max_centrality, degree)

	# Resize nodes based on centrality
	for node_id in nodes:
		var node_instance = get_node(str(node_id))
		if node_instance:
			var normalized_centrality = float(centrality_scores[node_id]) / max_centrality
			node_instance.update_size(normalized_centrality, normalized_centrality)


func apply_radial_layout(radius_step: float, file_data):
	# A csomópontokat egy egyszerű listában gyűjtjük, a circular_layout mintájára.
	var all_node_instances = []
	for child in get_children():
		if child.is_in_group("nodes"):
			all_node_instances.append(child)

	if all_node_instances.is_empty():
		print("Hiba: Nincsenek csomópontok a radiális elrendezéshez.")
		return

	# A gráf szerkezetének beolvasása a fájlból a megbízhatóság érdekében.

	var nodes_data = file_data["nodes"]
	var edges_data = file_data["edges"]
	print(nodes_data)
	if nodes_data.is_empty() or edges_data.is_empty():
		print("Hiba: A fájlból beolvasott gráf adatok üresek.")
		return

	# --- 1. A legcentrálisabb csomópont megkeresése ---
	var central_node_id = ""
	var max_degree = -1
	for node_id in nodes_data:
		var degree = nodes_data[node_id]["edges"].size()
		if degree > max_degree:
			max_degree = degree
			central_node_id = node_id

	if central_node_id == "":
		print("Nem található központi csomópont.")
		return

	# --- 2. Szélességi bejárás (BFS) a távolságokhoz ---
	var levels = {} # node_id -> távolság a centrumtól
	var queue = [[central_node_id, 0]]
	var visited = {central_node_id: true}
	levels[central_node_id] = 0

	var adjacency_list = {}
	for edge_data in edges_data.values():
		var edge_node_list = edge_data["nodes"]
		for i in range(edge_node_list.size()):
			var node_id = edge_node_list[i]
			if not adjacency_list.has(node_id):
				adjacency_list[node_id] = []
			for j in range(edge_node_list.size()):
				if i != j:
					var other_node_id = edge_node_list[j]
					if other_node_id not in adjacency_list[node_id]:
						adjacency_list[node_id].append(other_node_id)
	
	var head = 0
	while head < queue.size():
		var current_pair = queue[head]
		head += 1
		var current_id = current_pair[0]
		var current_level = current_pair[1]

		if adjacency_list.has(current_id):
			for neighbor_id in adjacency_list[current_id]:
				if not visited.has(neighbor_id):
					visited[neighbor_id] = true
					levels[neighbor_id] = current_level + 1
					queue.append([neighbor_id, current_level + 1])

	# Csomópont objektumok csoportosítása szintenként
	var nodes_by_level = {}
	for node_instance in all_node_instances:
		var level = levels.get(node_instance.node_id, -1)
		if not nodes_by_level.has(level):
			nodes_by_level[level] = []
		nodes_by_level[level].append(node_instance)

	# --- 3. Pozíciók kiosztása ---
	var center = get_viewport_rect().size / 2
	
	# A központi csomópont középre kerül
	if nodes_by_level.has(0) and not nodes_by_level[0].is_empty():
		nodes_by_level[0][0].position = center

	# A többi csomópont a körökre
	for level in nodes_by_level:
		if level <= 0:
			continue
			
		var nodes_on_this_level = nodes_by_level[level]
		var node_count = nodes_on_this_level.size()
		if node_count == 0:
			continue
			
		var radius = level * radius_step
		var angle_step = (2 * PI) / node_count

		for i in range(node_count):
			var node = nodes_on_this_level[i] # Itt már közvetlenül a node objektumot használjuk
			var angle = i * angle_step
			var x = center.x + radius * cos(angle)
			var y = center.y + radius * sin(angle)
			node.position = Vector2(x, y)


func apply_untangled_layout(parameters):
	# Containment-correct layout: no node ends up visually inside a
	# hyperedge hull it does not belong to. Parameters (optional):
	# [iterations, repulsion, spring_length]
	var node_radii = {}
	for child in get_children():
		if child.is_in_group("nodes"):
			node_radii[child.node_id] = child.radius_global
	var edge_widths = {}
	for e in get_tree().get_nodes_in_group("edges"):
		edge_widths[int(str(e.name))] = e.width
	var opts = {}
	if parameters.size() == 3:
		opts = {"iterations": int(parameters[0]),
			"repulsion": float(parameters[1]),
			"spring_length": float(parameters[2])}
	var result = HGLayouts.untangled(file_data_cached, node_radii, edge_widths, opts)
	var center = get_viewport_rect().size / 2
	for child in get_children():
		if child.is_in_group("nodes"):
			if result["positions"].has(child.node_id):
				child.position = result["positions"][child.node_id] + center
	print("Untangled layout: violations=", result["violations"],
		" rounds=", result["rounds"], " scale_ups=", result["scale_ups"])
	for e in get_tree().get_nodes_in_group("edges"):
		e.mark_dirty()

func paper_setup():
	var selector = OptionButton.new()
	selector.position = Vector2(15,15)
	var files = Global.hypergraph_files()
	for f in files:
		selector.add_item(f.get_file().get_basename())
	if files.is_empty():
		selector.add_item("No .txt hypergraph files next to the program")
		selector.disabled = true
	else:
		selector.select(files.find(Global.current_file))
	selector.add_to_group("export_ui")
	$CanvasLayer2.add_child(selector)
	selector.item_selected.connect(func(index): Global.current_file=files[index]; get_tree().reload_current_scene())
	if files.is_empty():
		return
	var path = layout_path()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--layout="):
			path=arg.substr(9)
	var load_button = Button.new()
	load_button.text = "Load saved layout"
	load_button.position = Vector2(260,15)
	load_button.add_to_group("export_ui")
	$CanvasLayer2.add_child(load_button)
	var dialog = FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.json ; Saved layout"])
	$CanvasLayer2.add_child(dialog)
	load_button.pressed.connect(func(): dialog.popup_centered(Vector2i(800,600)))
	dialog.current_dir = Global.viewer_dir()
	dialog.file_selected.connect(paper_load_layout)
	if FileAccess.file_exists(path):
		paper_load_layout(path)
	else:
		var positions = {}
		for n in get_tree().get_nodes_in_group("nodes"):
			positions[n.node_id] = [n.position.x, n.position.y]
		apply_saved_layout({"positions": positions})

func layout_path() -> String:
	return Global.current_file.get_basename() + ".layout.json"

func paper_load_layout(path):
	var saved = JSON.parse_string(FileAccess.get_file_as_string(path))
	if saved == null or not saved.has("positions"):
		push_error("Invalid layout: "+path)
		return
	apply_saved_layout(saved)

func apply_saved_layout(saved):
	for n in get_tree().get_nodes_in_group("nodes"):
		if not saved.positions.has(n.node_id):
			push_error("This layout belongs to another graph; select its figure first.")
			return
	var lo = Vector2(INF,INF)
	var hi = Vector2(-INF,-INF)
	for n in get_tree().get_nodes_in_group("nodes"):
		if saved.positions.has(n.node_id):
			var xy=saved.positions[n.node_id]
			n.position=Vector2(xy[0],xy[1])
		lo=lo.min(n.position)
		hi=hi.max(n.position)
		var label=n.get_node("Label")
		label.add_theme_font_size_override("font_size",int(22/n.scale.x))
		label.position=Vector2(-80,-55)/n.scale
	for edge in get_tree().get_nodes_in_group("edges"):
		edge.recalculate_edge()
		edge.mark_dirty()
	var cam=get_viewport().get_camera_2d()
	if cam:
		cam.position=(lo+hi)/2
		var viewport_size=get_viewport_rect().size
		var extent=hi-lo+Vector2(500,350)
		cam.zoom=Vector2.ONE*min(viewport_size.x/extent.x,viewport_size.y/extent.y)
		if saved.has("camera") and saved.has("zoom"):
			cam.position=Vector2(saved.camera[0],saved.camera[1])
			cam.zoom=Vector2(saved.zoom[0],saved.zoom[1])

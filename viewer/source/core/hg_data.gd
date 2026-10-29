## Shared hypergraph data loading - used by both the GUI (main.gd) and
## headless mode. Tolerant SPMF-like parser:
##   v1 v2 v3 #WEIGHT: 123 #GROUP: 2022
##   v1 v2 v3 #WEIGHT: 123 #GROUP 2022     (legacy, no colon)
##   v1 v2 v3 #WEIGHT: 123                 (group defaults to "1")

static func parse_file(path: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("HGData: cannot open file: %s" % path)
		return {"nodes": {}, "edges": {}, "error": "cannot open %s" % path}
	var text = file.get_as_text()
	file.close()
	return parse_text(text)

static func parse_text(text: String) -> Dictionary:
	var nodes = {}   # id -> {"edges": {edge_id: support}}
	var edges = {}   # edge_id -> {"nodes": [...], "support": int, "group": String, "radii": []}
	var edge_id = 0

	for raw_line in text.split("\n"):
		var line = raw_line.strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		if line.find("#WEIGHT:") == -1:
			continue

		var parts = line.split("#WEIGHT:")
		var node_ids_raw = parts[0].strip_edges().split(" ")
		var rest = parts[1].strip_edges()

		var support := 0
		var group := "1"
		# Accept both "#GROUP:" and legacy "#GROUP"
		var gpos = rest.find("#GROUP")
		if gpos == -1:
			support = int(rest)
		else:
			support = int(rest.substr(0, gpos).strip_edges())
			var gval = rest.substr(gpos + len("#GROUP")).strip_edges()
			if gval.begins_with(":"):
				gval = gval.substr(1).strip_edges()
			if gval != "":
				group = gval

		var node_ids = []
		for nid in node_ids_raw:
			var n = nid.strip_edges()
			if n != "":
				node_ids.append(n)
		if node_ids.is_empty():
			continue

		for node_id in node_ids:
			if not nodes.has(node_id):
				nodes[node_id] = {"edges": {}}
			nodes[node_id]["edges"][edge_id] = support

		edges[edge_id] = {
			"nodes": node_ids,
			"support": support,
			"radii": [],
			"group": group,
		}
		edge_id += 1

	return {"nodes": nodes, "edges": edges}

## Degree centrality for every node (number of incident hyperedges).
static func degree_centrality(data: Dictionary) -> Dictionary:
	var out = {}
	for node_id in data["nodes"]:
		out[node_id] = data["nodes"][node_id]["edges"].size()
	return out

static func group_names(data: Dictionary) -> Array:
	var names = []
	for edge_id in data["edges"]:
		var g = data["edges"][edge_id]["group"]
		if g not in names:
			names.append(g)
	return names

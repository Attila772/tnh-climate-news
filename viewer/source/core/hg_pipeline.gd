const HGData = preload("res://core/hg_data.gd")
const HGGeometry = preload("res://core/hg_geometry.gd")
const HGLayouts = preload("res://core/hg_layouts.gd")
const HGExport = preload("res://core/hg_export.gd")
## One-call pipeline used by both headless.gd (CLI) and the in-editor test
## scene: parse -> radii/widths from conf.cfg expressions -> layout ->
## validate containment -> export SVG/PNG.

static func run(opts: Dictionary) -> Dictionary:
	var input_path: String = opts.get("input", "res://patterns.txt")
	var png_path: String = opts.get("output", "")
	var svg_path: String = opts.get("svg", "")
	var layout: String = opts.get("layout", "untangled")
	var width: int = opts.get("width", 1400)
	var height: int = opts.get("height", 1050)
	var supersample: int = opts.get("supersample", 2)
	var rng_seed: int = opts.get("seed", 7)
	var title: String = opts.get("title", "")
	var point_count: int = opts.get("point_count", 96)
	var style: String = opts.get("style", "classic")

	var t0 = Time.get_ticks_msec()
	var data = HGData.parse_file(input_path)
	if data.has("error"):
		return {"ok": false, "error": data["error"]}
	if data["nodes"].is_empty():
		return {"ok": false, "error": "no hyperedges parsed from %s" % input_path}

	# --- conf.cfg expressions (same ones the GUI uses) -------------------
	var config = ConfigFile.new()
	config.load("res://conf.cfg")  # missing file -> defaults below
	var width_expr_text = config.get_value("graph_settings",
		"edge_width_expression", "pow(support, 0.35)")
	var radius_expr_text = config.get_value("graph_settings",
		"node_radius_expression", "30")

	var total_nodes = data["nodes"].size()
	var centrality = HGData.degree_centrality(data)
	var max_deg = 1
	for nid in centrality:
		max_deg = max(max_deg, centrality[nid])

	var radius_expr = Expression.new()
	if radius_expr.parse(radius_expr_text, ["centrality", "total_nodes"]) != OK:
		radius_expr.parse("30", ["centrality", "total_nodes"])
	var node_radii = {}
	for nid in data["nodes"]:
		var norm_c = float(centrality[nid]) / float(max_deg)
		var r = radius_expr.execute([norm_c, total_nodes])
		node_radii[nid] = 30.0 if (r == null or radius_expr.has_execute_failed()) else float(r)

	var width_expr = Expression.new()
	if width_expr.parse(width_expr_text, ["support", "node_count", "total_nodes"]) != OK:
		width_expr.parse("pow(support, 0.35)", ["support", "node_count", "total_nodes"])
	var edge_widths = {}
	for eid in data["edges"]:
		var e = data["edges"][eid]
		var w = width_expr.execute([e["support"], e["nodes"].size(), total_nodes])
		edge_widths[eid] = 4.0 if (w == null or width_expr.has_execute_failed()) else float(w)

	# --- layout ----------------------------------------------------------
	var positions: Dictionary
	var layout_stats = {}
	match layout:
		"circular":
			positions = HGLayouts.circular(data["nodes"].keys(),
				opts.get("radius", 170.0 + 26.0 * total_nodes), Vector2.ZERO)
		"radial":
			positions = HGLayouts.radial(data, opts.get("radius_step", 400.0), Vector2.ZERO)
		"force-directed":
			var rng = RandomNumberGenerator.new()
			rng.seed = rng_seed
			var start = {}
			for nid in data["nodes"]:
				start[nid] = Vector2(rng.randf_range(-300, 300), rng.randf_range(-300, 300))
			positions = HGLayouts.force_directed(data, start,
				opts.get("iterations", 250), opts.get("repulsion", 60000.0),
				opts.get("spring_length", 160.0))
		_:
			# default: containment-correct layout
			var result = HGLayouts.untangled(data, node_radii, edge_widths, {
				"iterations": opts.get("iterations", 250),
				"repulsion": opts.get("repulsion", 60000.0),
				"spring_length": opts.get("spring_length", 160.0),
				"seed": rng_seed,
			})
			positions = result["positions"]
			layout_stats = {"repair_rounds": result["rounds"],
				"scale_ups": result["scale_ups"]}

	# --- strict validation (any layout) -----------------------------------
	var eff_radii = {}
	for nid in data["nodes"]:
		var nr = node_radii.get(nid, 30.0)
		var rings = HGGeometry.offset_radii(data["nodes"][nid]["edges"], nr)
		var per_edge = {}
		for eid2 in rings:
			per_edge[eid2] = HGGeometry.effective_radius(rings[eid2], nr)
		eff_radii[nid] = per_edge
	var violations = HGLayouts.count_violations(data, positions, node_radii,
		edge_widths, eff_radii, 48, 4.0)

	# --- export ------------------------------------------------------------
	var prims = HGExport.build_primitives(data, positions, node_radii,
		edge_widths, point_count)
	var export_result = HGExport.export_files(prims, width, height,
		png_path, svg_path, supersample, title, style)
	if export_result.has("error"):
		return {"ok": false, "error": export_result["error"]}

	return {
		"ok": true,
		"input": input_path,
		"layout": layout,
		"nodes": total_nodes,
		"edges": data["edges"].size(),
		"groups": HGData.group_names(data),
		"containment_violations": violations,
		"layout_stats": layout_stats,
		"written": export_result.get("written", []),
		"ms": Time.get_ticks_msec() - t0,
	}

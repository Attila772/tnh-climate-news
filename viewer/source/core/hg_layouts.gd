const HGGeometry = preload("res://core/hg_geometry.gd")
## Shared layout algorithms. All deterministic (seeded RNG, fixed iteration
## counts). Positions are returned as {node_id: Vector2}.
##
## "untangled" is the containment-correct layout: it starts from a
## force-directed arrangement (nice), then iteratively repairs every
## containment violation (a node lying visually inside a hyperedge hull it
## does not belong to) until none remain. Guarantees: every node's edge
## membership is visually unambiguous.

# ---------------------------------------------------------------- circular
static func circular(node_ids: Array, radius: float, center: Vector2) -> Dictionary:
	var out = {}
	var n = max(node_ids.size(), 1)
	for i in range(node_ids.size()):
		var a = TAU * float(i) / float(n)
		out[node_ids[i]] = center + Vector2(cos(a), sin(a)) * radius
	return out

# ----------------------------------------------------------- force-directed
## Port of main.gd's simulation: spring force towards each hyperedge's
## centroid + pairwise inverse-square repulsion, damping 0.9.
static func force_directed(data: Dictionary, start_positions: Dictionary,
		iterations: int, repulsion_force: float, spring_length: float) -> Dictionary:
	var edges = data["edges"]
	var node_ids = data["nodes"].keys()
	var pos = {}
	for id in node_ids:
		pos[id] = start_positions.get(id, Vector2.ZERO)
	var forces = {}
	for id in node_ids:
		forces[id] = Vector2.ZERO

	for _i in range(iterations):
		# attraction towards hyperedge centroids
		for edge_id in edges:
			var edge_nodes = edges[edge_id]["nodes"]
			if edge_nodes.is_empty():
				continue
			var center = Vector2.ZERO
			for nid in edge_nodes:
				center += pos[nid]
			center /= edge_nodes.size()
			for nid in edge_nodes:
				var delta = center - pos[nid]
				var dist = delta.length()
				if dist > 0.0:
					var displacement = dist - spring_length
					forces[nid] += delta.normalized() * displacement * 0.1
		# pairwise repulsion
		for j in range(node_ids.size()):
			for k in range(j + 1, node_ids.size()):
				var a = node_ids[j]
				var b = node_ids[k]
				var delta = pos[a] - pos[b]
				var dist = delta.length()
				if dist > 0.0:
					var f = delta.normalized() * (repulsion_force / (dist * dist))
					forces[a] += f
					forces[b] -= f
		for id in node_ids:
			pos[id] += forces[id] * 0.9
			forces[id] = Vector2.ZERO
	return pos

# ------------------------------------------------------------------ radial
## BFS levels from the highest-degree node, each level on its own ring.
static func radial(data: Dictionary, radius_step: float, center: Vector2) -> Dictionary:
	var nodes = data["nodes"]
	var edges = data["edges"]
	var out = {}
	if nodes.is_empty():
		return out

	var central = ""
	var max_deg = -1
	for nid in nodes:
		var deg = nodes[nid]["edges"].size()
		if deg > max_deg:
			max_deg = deg
			central = nid

	var adjacency = {}
	for edge_data in edges.values():
		var lst = edge_data["nodes"]
		for i in range(lst.size()):
			if not adjacency.has(lst[i]):
				adjacency[lst[i]] = []
			for j in range(lst.size()):
				if i != j and lst[j] not in adjacency[lst[i]]:
					adjacency[lst[i]].append(lst[j])

	var levels = {central: 0}
	var queue = [central]
	var head = 0
	while head < queue.size():
		var cur = queue[head]
		head += 1
		for nb in adjacency.get(cur, []):
			if not levels.has(nb):
				levels[nb] = levels[cur] + 1
				queue.append(nb)

	var by_level = {}
	for nid in nodes:
		var lv = levels.get(nid, 1)
		if not by_level.has(lv):
			by_level[lv] = []
		by_level[lv].append(nid)

	for lv in by_level:
		var ring = by_level[lv]
		if lv == 0:
			out[ring[0]] = center
			continue
		var step = TAU / max(ring.size(), 1)
		for i in range(ring.size()):
			var a = i * step
			out[ring[i]] = center + Vector2(cos(a), sin(a)) * (lv * radius_step)
	return out

# -------------------------------------------------------------- untangled
## Containment-correct layout.
##   data        : parsed hypergraph (HGData.parse_file)
##   node_radii  : {node_id: drawn node radius}
##   edge_widths : {edge_id: stroke width}
##   opts        : iterations, repulsion, spring_length, seed, pad,
##                 point_count, max_rounds, max_scale_ups
## Returns {positions, violations, rounds, scale_ups}.
static func untangled(data: Dictionary, node_radii: Dictionary,
		edge_widths: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var iterations: int = opts.get("iterations", 250)
	var repulsion: float = opts.get("repulsion", 60000.0)
	var spring_length: float = opts.get("spring_length", 160.0)
	var rng_seed: int = opts.get("seed", 7)
	var pad: float = opts.get("pad", 14.0)
	var point_count: int = opts.get("point_count", 28)
	var max_rounds: int = opts.get("max_rounds", 120)
	var max_scale_ups: int = opts.get("max_scale_ups", 6)

	var nodes = data["nodes"]
	var edges = data["edges"]
	var node_ids = nodes.keys()

	# deterministic seeded start
	var rng = RandomNumberGenerator.new()
	rng.seed = rng_seed
	var pos = {}
	for id in node_ids:
		pos[id] = Vector2(rng.randf_range(-300, 300), rng.randf_range(-300, 300))

	# 1) aesthetics: force-directed base
	pos = force_directed(data, pos, iterations, repulsion, spring_length)

	# per-(node,edge) effective ring radii — identical to what gets drawn
	var eff_radii = {}  # node_id -> {edge_id: radius}
	for nid in node_ids:
		var nr = node_radii.get(nid, 30.0)
		var rings = HGGeometry.offset_radii(nodes[nid]["edges"], nr)
		var per_edge = {}
		for eid in rings:
			per_edge[eid] = HGGeometry.effective_radius(rings[eid], nr)
		eff_radii[nid] = per_edge

	# 2) constraint repair
	var rounds = 0
	var scale_ups = 0
	var violations = -1
	while rounds < max_rounds:
		rounds += 1
		violations = 0
		var moves = {}
		# containment violations
		for eid in edges:
			var member_list = edges[eid]["nodes"]
			var members = {}
			for nid in member_list:
				members[nid] = true
			var radii = {}
			for nid in member_list:
				radii[nid] = eff_radii[nid].get(eid, node_radii.get(nid, 30.0))
			var hull = HGGeometry.edge_hull(member_list, pos, radii, point_count)
			if hull.size() < 3:
				continue
			var half_w = edge_widths.get(eid, 4.0) / 2.0
			for nid in node_ids:
				if members.has(nid):
					continue
				var clearance = node_radii.get(nid, 30.0) + half_w + pad
				var v = HGGeometry.exit_vector(pos[nid], hull, clearance)
				if v != Vector2.ZERO:
					violations += 1
					moves[nid] = moves.get(nid, Vector2.ZERO) + v
		# node-node overlap separation (keeps repair from stacking nodes)
		for j in range(node_ids.size()):
			for k in range(j + 1, node_ids.size()):
				var a = node_ids[j]
				var b = node_ids[k]
				var min_d = node_radii.get(a, 30.0) + node_radii.get(b, 30.0) + 30.0
				var delta = pos[a] - pos[b]
				var d = delta.length()
				if d < min_d:
					var push: Vector2
					if d < 0.001:
						push = Vector2(1, 0) * (min_d / 2.0)
					else:
						push = delta.normalized() * ((min_d - d) / 2.0)
					moves[a] = moves.get(a, Vector2.ZERO) + push
					moves[b] = moves.get(b, Vector2.ZERO) - push
					violations += 1
		if violations == 0:
			break
		for nid in moves:
			pos[nid] += moves[nid]
		# escalation: spread the whole layout — rings have fixed pixel size,
		# so scaling up makes hulls relatively tighter and repair easier
		if rounds % 25 == 0 and scale_ups < max_scale_ups:
			scale_ups += 1
			var c = HGGeometry.centroid(pos)
			for nid in pos:
				pos[nid] = c + (pos[nid] - c) * 1.25

	# 3) strict final validation with finer sampling
	var final_violations = count_violations(data, pos, node_radii, edge_widths,
			eff_radii, 48, pad * 0.5)
	return {"positions": pos, "violations": final_violations,
			"rounds": rounds, "scale_ups": scale_ups}

## Count containment violations (strict check used for validation/tests).
static func count_violations(data: Dictionary, pos: Dictionary,
		node_radii: Dictionary, edge_widths: Dictionary, eff_radii: Dictionary,
		point_count: int, pad: float) -> int:
	var edges = data["edges"]
	var node_ids = data["nodes"].keys()
	var bad = 0
	for eid in edges:
		var member_list = edges[eid]["nodes"]
		var members = {}
		for nid in member_list:
			members[nid] = true
		var radii = {}
		for nid in member_list:
			radii[nid] = eff_radii[nid].get(eid, node_radii.get(nid, 30.0))
		var hull = HGGeometry.edge_hull(member_list, pos, radii, point_count)
		if hull.size() < 3:
			continue
		var half_w = edge_widths.get(eid, 4.0) / 2.0
		for nid in node_ids:
			if members.has(nid):
				continue
			var clearance = node_radii.get(nid, 30.0) + half_w + pad
			if HGGeometry.signed_distance(pos[nid], hull) < clearance:
				bad += 1
	return bad

## Shared geometry: offset rings, circle sampling, Andrew's monotone chain,
## convex point-membership and minimal exit vectors.
## Mirrors the visual logic of HyperNode.make_offset_circles + HyperEdge so
## the headless render matches the GUI pixel-for-pixel in structure.

## Per-node ring radii for each incident edge, replicating
## HyperNode.make_offset_circles(): rings accumulate outward from the node
## radius by half of the previous + half of the current edge width.
## Returns {edge_id: ring_radius} in the node's edge insertion order.
static func offset_radii(node_edges: Dictionary, node_radius: float) -> Dictionary:
	var widths = []
	var edge_ids = node_edges.keys()
	for edge_id in edge_ids:
		widths.append(pow(float(node_edges[edge_id]), 0.35))
	var out = {}
	var cumulative = node_radius
	for i in range(widths.size()):
		if i == 0:
			cumulative += widths[0] / 2.0
		else:
			cumulative += (widths[i - 1] / 2.0) + (widths[i] / 2.0)
		out[edge_ids[i]] = cumulative
	return out

## The radius HyperEdge actually draws with (it adds the node radius and
## subtracts the legacy 30px baseline).
static func effective_radius(ring_radius: float, node_radius: float) -> float:
	return ring_radius + node_radius - 30.0

static func circle_points(center: Vector2, radius: float, n: int) -> PackedVector2Array:
	var pts = PackedVector2Array()
	for i in range(n):
		var a = TAU * float(i) / float(n)
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	return pts

static func convex_hull(points: PackedVector2Array) -> PackedVector2Array:
	var pts = Array(points)
	if pts.size() < 3:
		return PackedVector2Array(pts)
	pts.sort_custom(func(a, b):
		return a.x < b.x if a.x != b.x else a.y < b.y)
	var lower = []
	for p in pts:
		while lower.size() >= 2 and _cross(lower[-2], lower[-1], p) <= 0:
			lower.pop_back()
		lower.append(p)
	var upper = []
	for i in range(pts.size() - 1, -1, -1):
		var p = pts[i]
		while upper.size() >= 2 and _cross(upper[-2], upper[-1], p) <= 0:
			upper.pop_back()
		upper.append(p)
	lower.pop_back()
	upper.pop_back()
	return PackedVector2Array(lower + upper)

static func _cross(o, a, b) -> float:
	return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)

## Hull polygon (CCW) of one hyperedge given node positions and the
## per-(node,edge) effective radii.
static func edge_hull(edge_nodes: Array, positions: Dictionary,
		radii: Dictionary, point_count: int) -> PackedVector2Array:
	var pts = PackedVector2Array()
	for node_id in edge_nodes:
		if not positions.has(node_id):
			continue
		var r = radii.get(node_id, 30.0)
		pts.append_array(circle_points(positions[node_id], r, point_count))
	return convex_hull(pts)

## True when p is inside (or on) the convex polygon (CCW order).
static func point_in_convex(p: Vector2, hull: PackedVector2Array) -> bool:
	var n = hull.size()
	if n < 3:
		return false
	for i in range(n):
		var a = hull[i]
		var b = hull[(i + 1) % n]
		if _cross(a, b, p) < 0:
			return false
	return true

## Signed clearance of p from the hull: negative when inside (depth),
## positive when outside (distance to boundary).
static func signed_distance(p: Vector2, hull: PackedVector2Array) -> float:
	var d = distance_to_boundary(p, hull)
	return -d if point_in_convex(p, hull) else d

static func distance_to_boundary(p: Vector2, hull: PackedVector2Array) -> float:
	var best = INF
	var n = hull.size()
	for i in range(n):
		var a = hull[i]
		var b = hull[(i + 1) % n]
		best = min(best, _dist_point_segment(p, a, b))
	return best

## Minimal translation that takes p OUT of the hull plus `clearance` extra.
## Returns Vector2.ZERO when p is already outside with enough clearance.
static func exit_vector(p: Vector2, hull: PackedVector2Array, clearance: float) -> Vector2:
	var inside = point_in_convex(p, hull)
	var best = INF
	var best_proj = Vector2.ZERO
	var n = hull.size()
	for i in range(n):
		var a = hull[i]
		var b = hull[(i + 1) % n]
		var proj = _closest_point_segment(p, a, b)
		var d = p.distance_to(proj)
		if d < best:
			best = d
			best_proj = proj
	if not inside and best >= clearance:
		return Vector2.ZERO
	var dir: Vector2
	if inside:
		dir = (best_proj - p)
		if dir.length() < 0.001:
			dir = Vector2.RIGHT  # degenerate: pick any direction
		else:
			dir = dir.normalized()
		return dir * (best + clearance)
	else:
		# outside but too close: push further out, away from the hull
		dir = (p - best_proj)
		if dir.length() < 0.001:
			dir = Vector2.RIGHT
		else:
			dir = dir.normalized()
		return dir * (clearance - best)

static func _dist_point_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	return p.distance_to(_closest_point_segment(p, a, b))

static func _closest_point_segment(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab = b - a
	var t = 0.0
	var denom = ab.length_squared()
	if denom > 0.0:
		t = clamp((p - a).dot(ab) / denom, 0.0, 1.0)
	return a + ab * t

static func centroid(positions: Dictionary) -> Vector2:
	var c = Vector2.ZERO
	if positions.is_empty():
		return c
	for k in positions:
		c += positions[k]
	return c / positions.size()

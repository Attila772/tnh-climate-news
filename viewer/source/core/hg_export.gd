const HGData = preload("res://core/hg_data.gd")
const HGGeometry = preload("res://core/hg_geometry.gd")
## Headless-safe rendering: builds draw primitives from a laid-out
## hypergraph, then writes SVG (vector) and/or PNG (CPU rasterizer with
## supersampling — works with --headless, no GPU or window needed).

const PALETTE = [
	Color("#2563eb"), Color("#dc2626"), Color("#059669"), Color("#d97706"),
	Color("#7c3aed"), Color("#0891b2"), Color("#be185d"), Color("#4d7c0f"),
	Color("#b45309"), Color("#1d4ed8"),
]

## Build resolution-independent primitives (world space).
## Returns {hulls: [...], nodes: [...], groups: [...]}
static func build_primitives(data: Dictionary, positions: Dictionary,
		node_radii: Dictionary, edge_widths: Dictionary,
		point_count: int = 96) -> Dictionary:
	var nodes = data["nodes"]
	var edges = data["edges"]
	var groups = HGData.group_names(data)

	# per-(node,edge) effective radii — identical to layout + GUI logic
	var eff_radii = {}
	for nid in nodes:
		var nr = node_radii.get(nid, 30.0)
		var rings = HGGeometry.offset_radii(nodes[nid]["edges"], nr)
		var per_edge = {}
		for eid in rings:
			per_edge[eid] = HGGeometry.effective_radius(rings[eid], nr)
		eff_radii[nid] = per_edge

	var hulls = []
	var color_i = 0
	for eid in edges:
		var member_list = edges[eid]["nodes"]
		var radii = {}
		for nid in member_list:
			radii[nid] = eff_radii[nid].get(eid, node_radii.get(nid, 30.0))
		var hull = HGGeometry.edge_hull(member_list, positions, radii, point_count)
		if hull.size() < 3:
			continue
		var group = edges[eid]["group"]
		var gi = groups.find(group)
		hulls.append({
			"edge_id": eid,
			"points": hull,
			"color": PALETTE[color_i % PALETTE.size()],
			"width": edge_widths.get(eid, 4.0),
			"dashed": groups.size() == 2 and gi == 1,
			"group": group,
			"area": _polygon_area(hull),
		})
		color_i += 1
	hulls.sort_custom(func(a, b): return a["area"] > b["area"])

	var node_prims = []
	var max_deg = 1
	for nid in nodes:
		max_deg = max(max_deg, nodes[nid]["edges"].size())
	for nid in nodes:
		node_prims.append({
			"id": nid,
			"pos": positions.get(nid, Vector2.ZERO),
			"radius": node_radii.get(nid, 30.0) * 0.55,
			"label": str(nid),
			"degree": nodes[nid]["edges"].size(),
		})
	return {"hulls": hulls, "nodes": node_prims, "groups": groups}

static func _polygon_area(poly: PackedVector2Array) -> float:
	var s = 0.0
	for i in range(poly.size()):
		var a = poly[i]
		var b = poly[(i + 1) % poly.size()]
		s += a.x * b.y - b.x * a.y
	return abs(s) / 2.0

## World-space bounds of everything, with padding.
static func _bounds(prims: Dictionary, padding: float) -> Rect2:
	var lo = Vector2(INF, INF)
	var hi = Vector2(-INF, -INF)
	for h in prims["hulls"]:
		for p in h["points"]:
			lo = lo.min(p)
			hi = hi.max(p)
	for n in prims["nodes"]:
		lo = lo.min(n["pos"] - Vector2.ONE * n["radius"])
		hi = hi.max(n["pos"] + Vector2.ONE * n["radius"])
	if lo.x == INF:
		return Rect2(0, 0, 100, 100)
	return Rect2(lo - Vector2.ONE * padding, (hi - lo) + Vector2.ONE * padding * 2.0)

static func _fit(prims: Dictionary, w: float, h: float):
	# returns [scale: float, offset: Vector2] mapping world -> canvas
	var b = _bounds(prims, 60.0)
	var s = min(w / b.size.x, h / b.size.y)
	var offset = Vector2(w, h) / 2.0 - (b.position + b.size / 2.0) * s
	return [s, offset]

# ====================================================================== SVG
static func to_svg(prims: Dictionary, w: int, h: int, title: String = "",
		style: String = "classic") -> String:
	var fit = _fit(prims, w, h)
	var s: float = fit[0]
	var off: Vector2 = fit[1]
	var out = []
	out.append('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">' % [w, h, w, h])
	out.append('<rect width="%d" height="%d" fill="white"/>' % [w, h])
	if title != "":
		out.append('<text x="%d" y="28" font-family="sans-serif" font-size="18" font-weight="bold" text-anchor="middle">%s</text>' % [int(w * 0.5), title.xml_escape()])
	for hull in prims["hulls"]:
		var pts = []
		for p in hull["points"]:
			var q = p * s + off
			pts.append("%.1f,%.1f" % [q.x, q.y])
		var col = "#" + hull["color"].to_html(false)
		var dash = ' stroke-dasharray="10,7"' if hull["dashed"] else ""
		var fill_op = 0.0 if style == "classic" else 0.13
		var stroke_op = 0.4 if style == "classic" else 0.9
		out.append('<polygon points="%s" fill="%s" fill-opacity="%.2f" stroke="%s" stroke-opacity="%.2f" stroke-width="%.1f"%s stroke-linejoin="round"/>' %
			[" ".join(pts), col, fill_op, col, stroke_op, max(hull["width"] * s, 1.2), dash])
	for n in prims["nodes"]:
		var q = n["pos"] * s + off
		var r = max(n["radius"] * s, 4.0)
		out.append('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="#1f2937"/>' % [q.x, q.y, r])
		out.append('<text x="%.1f" y="%.1f" font-family="sans-serif" font-size="13" text-anchor="middle" fill="#111827" stroke="white" stroke-width="3" paint-order="stroke">%s</text>' %
			[q.x, q.y - r - 6.0, str(n["label"]).xml_escape()])
	if prims["groups"].size() > 1:
		var gy = 24
		for gi in range(prims["groups"].size()):
			var dash_attr = "stroke-dasharray=\"10,7\" " if gi == 1 and prims["groups"].size() == 2 else ""
			out.append('<line x1="20" y1="%d" x2="60" y2="%d" stroke="#444" stroke-width="3" %s/>' % [gy, gy, dash_attr])
			out.append('<text x="68" y="%d" font-family="sans-serif" font-size="13">%s</text>' % [gy + 4, str(prims["groups"][gi]).xml_escape()])
			gy += 22
	out.append('</svg>')
	return "\n".join(out)

# ====================================================================== PNG
## CPU rasterizer. Renders at `supersample`x size, then Lanczos-downscales.
static func to_png_image(prims: Dictionary, w: int, h: int, supersample: int = 2,
		style: String = "classic") -> Image:
	var W = w * supersample
	var H = h * supersample
	var fit = _fit(prims, W, H)
	var s: float = fit[0]
	var off: Vector2 = fit[1]

	var buf = PackedByteArray()
	buf.resize(W * H * 3)
	buf.fill(255)  # white background

	for hull in prims["hulls"]:
		var poly = PackedVector2Array()
		for p in hull["points"]:
			poly.append(p * s + off)
		# "classic" = the article's look: thick translucent outline, no fill
		var fill_a = 0.0 if style == "classic" else 0.13
		var stroke_a = 0.4 if style == "classic" else 0.9
		if fill_a > 0.0:
			_fill_convex(buf, W, H, poly, hull["color"], fill_a)
		var lw = max(hull["width"] * s, 1.5)
		_stroke_polygon(buf, W, H, poly, hull["color"], stroke_a, lw, hull["dashed"])
	for n in prims["nodes"]:
		var q = n["pos"] * s + off
		var r = max(n["radius"] * s, 4.0 * supersample)
		_fill_disc(buf, W, H, q, r, Color("#1f2937"), 1.0)
		var fscale = max(supersample, 1) * 2
		_draw_text(buf, W, H, str(n["label"]),
			q + Vector2(0, -r - 8.0 * supersample), fscale, Color("#111827"))

	var img = Image.create_from_data(W, H, false, Image.FORMAT_RGB8, buf)
	if supersample > 1:
		img.resize(w, h, Image.INTERPOLATE_LANCZOS)
	return img

static func _blend(buf: PackedByteArray, W: int, H: int, x: int, y: int,
		color: Color, alpha: float) -> void:
	if x < 0 or y < 0 or x >= W or y >= H:
		return
	var i = (y * W + x) * 3
	var ia = 1.0 - alpha
	buf[i] = int(color.r * 255.0 * alpha + buf[i] * ia)
	buf[i + 1] = int(color.g * 255.0 * alpha + buf[i + 1] * ia)
	buf[i + 2] = int(color.b * 255.0 * alpha + buf[i + 2] * ia)

static func _fill_convex(buf: PackedByteArray, W: int, H: int,
		poly: PackedVector2Array, color: Color, alpha: float) -> void:
	if poly.size() < 3:
		return
	var ymin = H
	var ymax = 0
	for p in poly:
		ymin = min(ymin, int(floor(p.y)))
		ymax = max(ymax, int(ceil(p.y)))
	ymin = max(ymin, 0)
	ymax = min(ymax, H - 1)
	var n = poly.size()
	for y in range(ymin, ymax + 1):
		var fy = float(y) + 0.5
		var xmin = INF
		var xmax = -INF
		for i in range(n):
			var a = poly[i]
			var b = poly[(i + 1) % n]
			if (a.y <= fy and b.y > fy) or (b.y <= fy and a.y > fy):
				var t = (fy - a.y) / (b.y - a.y)
				var x = a.x + (b.x - a.x) * t
				xmin = min(xmin, x)
				xmax = max(xmax, x)
		if xmin > xmax:
			continue
		var x0 = max(int(floor(xmin)), 0)
		var x1 = min(int(ceil(xmax)), W - 1)
		for x in range(x0, x1 + 1):
			_blend(buf, W, H, x, y, color, alpha)

static func _fill_disc(buf: PackedByteArray, W: int, H: int, c: Vector2,
		r: float, color: Color, alpha: float) -> void:
	var r2 = r * r
	var y0 = max(int(c.y - r), 0)
	var y1 = min(int(c.y + r) + 1, H - 1)
	var x0 = max(int(c.x - r), 0)
	var x1 = min(int(c.x + r) + 1, W - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var dx = float(x) + 0.5 - c.x
			var dy = float(y) + 0.5 - c.y
			if dx * dx + dy * dy <= r2:
				_blend(buf, W, H, x, y, color, alpha)

static func _stroke_segment(buf: PackedByteArray, W: int, H: int,
		a: Vector2, b: Vector2, color: Color, alpha: float, width: float) -> void:
	var dir = b - a
	if dir.length() < 0.001:
		return
	var nrm = Vector2(-dir.y, dir.x).normalized() * (width / 2.0)
	var quad = PackedVector2Array([a + nrm, b + nrm, b - nrm, a - nrm])
	_fill_convex(buf, W, H, quad, color, alpha)

static func _stroke_polygon(buf: PackedByteArray, W: int, H: int,
		poly: PackedVector2Array, color: Color, alpha: float, width: float,
		dashed: bool) -> void:
	var n = poly.size()
	for i in range(n):
		var a = poly[i]
		var b = poly[(i + 1) % n]
		if dashed:
			var seg_len = a.distance_to(b)
			var dash = 12.0
			var gap = 8.0
			var t = 0.0
			while t < seg_len:
				var t2 = min(t + dash, seg_len)
				_stroke_segment(buf, W, H, a + (b - a) * (t / seg_len),
					a + (b - a) * (t2 / seg_len), color, alpha, width)
				t = t2 + gap
		else:
			_stroke_segment(buf, W, H, a, b, color, alpha, width)
			_fill_disc(buf, W, H, b, width / 2.0, color, alpha)

# ------------------------------------------------------------- bitmap font
# 5x7 micro font (rows of 5-bit masks, MSB = leftmost pixel).
const FONT = {
	"A": [14,17,17,31,17,17,17], "B": [30,17,17,30,17,17,30],
	"C": [14,17,16,16,16,17,14], "D": [30,17,17,17,17,17,30],
	"E": [31,16,16,30,16,16,31], "F": [31,16,16,30,16,16,16],
	"G": [14,17,16,23,17,17,14], "H": [17,17,17,31,17,17,17],
	"I": [14,4,4,4,4,4,14],      "J": [7,2,2,2,2,18,12],
	"K": [17,18,20,24,20,18,17], "L": [16,16,16,16,16,16,31],
	"M": [17,27,21,21,17,17,17], "N": [17,25,21,19,17,17,17],
	"O": [14,17,17,17,17,17,14], "P": [30,17,17,30,16,16,16],
	"Q": [14,17,17,17,21,18,13], "R": [30,17,17,30,20,18,17],
	"S": [15,16,16,14,1,1,30],   "T": [31,4,4,4,4,4,4],
	"U": [17,17,17,17,17,17,14], "V": [17,17,17,17,17,10,4],
	"W": [17,17,17,21,21,27,17], "X": [17,10,4,4,4,10,17],
	"Y": [17,17,10,4,4,4,4],     "Z": [31,1,2,4,8,16,31],
	"0": [14,17,19,21,25,17,14], "1": [4,12,4,4,4,4,14],
	"2": [14,17,1,2,4,8,31],     "3": [14,17,1,6,1,17,14],
	"4": [2,6,10,18,31,2,2],     "5": [31,16,30,1,1,17,14],
	"6": [6,8,16,30,17,17,14],   "7": [31,1,2,4,8,8,8],
	"8": [14,17,17,14,17,17,14], "9": [14,17,17,15,1,2,12],
	"_": [0,0,0,0,0,0,31],       "-": [0,0,0,14,0,0,0],
	".": [0,0,0,0,0,12,12],      "+": [0,4,4,31,4,4,0],
	" ": [0,0,0,0,0,0,0],
}

static func _draw_text(buf: PackedByteArray, W: int, H: int, text: String,
		center: Vector2, px: int, color: Color) -> void:
	text = text.to_upper()
	if text.length() > 24:
		text = text.substr(0, 23) + "."
	var total_w = text.length() * 6 * px
	var x0 = int(center.x - total_w / 2.0)
	var y0 = int(center.y - 7 * px)
	# white halo box so labels stay readable on top of hull fills
	for hy in range(y0 - px, y0 + 8 * px):
		for hx in range(x0 - px, x0 + total_w + px):
			_blend(buf, W, H, hx, hy, Color.WHITE, 0.72)
	for ci in range(text.length()):
		var glyph = FONT.get(text[ci], FONT["."])
		var gx = x0 + ci * 6 * px
		for row in range(7):
			var bits: int = glyph[row]
			for col in range(5):
				if bits & (16 >> col):
					for dy in range(px):
						for dx in range(px):
							_blend(buf, W, H, gx + col * px + dx,
								y0 + row * px + dy, color, 1.0)

## Write outputs. `png_path`/`svg_path` empty string = skip that format.
static func export_files(prims: Dictionary, w: int, h: int,
		png_path: String, svg_path: String, supersample: int = 2,
		title: String = "", style: String = "classic") -> Dictionary:
	var written = []
	if svg_path != "":
		var fh = FileAccess.open(svg_path, FileAccess.WRITE)
		if fh == null:
			return {"error": "cannot write %s" % svg_path}
		fh.store_string(to_svg(prims, w, h, title, style))
		fh.close()
		written.append(svg_path)
	if png_path != "":
		var img = to_png_image(prims, w, h, supersample, style)
		var err = img.save_png(png_path)
		if err != OK:
			return {"error": "cannot write %s (err %d)" % [png_path, err]}
		written.append(png_path)
	return {"written": written}

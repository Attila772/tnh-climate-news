extends RefCounted
## Export the visible graph in viewport coordinates, preserving camera and alpha.

static func f(v: float) -> String:
	return "%.4f" % v

static func save(tree: SceneTree, viewport: Viewport, path: String) -> Error:
	var size = viewport.get_visible_rect().size
	var out = PackedStringArray(['<svg xmlns="http://www.w3.org/2000/svg" width="%s" height="%s" viewBox="0 0 %s %s">' % [f(size.x),f(size.y),f(size.x),f(size.y)], '<rect width="100%" height="100%" fill="white"/>'])
	# Sort by canvas z and scene order to match the current scene.
	var items: Array = []
	items.append_array(tree.get_nodes_in_group("nodes"))
	items.append_array(tree.get_nodes_in_group("edges"))
	items.sort_custom(func(a,b): return a.z_index < b.z_index if a.z_index != b.z_index else a.is_greater_than(b) == false)
	for item in items:
		if not item.is_visible_in_tree():
			continue
		var tr = item.get_global_transform_with_canvas()
		var scale_factor = tr.x.length()
		if item.is_in_group("edges"):
			var commands = PackedStringArray()
			for i in range(item.cached_hull.size()):
				var p = tr * item.cached_hull[i]
				commands.append(("M" if i == 0 else "L") + f(p.x) + " " + f(p.y))
			var c: Color = item.color * item.modulate * item.self_modulate
			var dash = ' stroke-dasharray="%s %s"' % [f(10*scale_factor),f(10*scale_factor)] if tree.root.get_node("Global").get_group_index(item.group)==2 else ""
			out.append('<path d="%s Z" fill="none" stroke="#%s" stroke-opacity="%s" stroke-width="%s" stroke-linejoin="round"%s/>' % [" ".join(commands),c.to_html(false),f(c.a),f(item.width*scale_factor),dash])
		else:
			var panel = item.get_node("Panel")
			var center = tr * Vector2.ZERO
			var fill: Color = panel.get_theme_stylebox("panel").bg_color
			out.append('<circle cx="%s" cy="%s" r="%s" fill="#%s"/>' % [f(center.x),f(center.y),f(20*scale_factor),fill.to_html(false)])
			var label: Label = item.get_node("Label")
			if label.is_visible_in_tree():
				var lt = label.get_global_transform_with_canvas()
				var fs = label.get_theme_font_size("font_size")
				var font = label.get_theme_font("font")
				var col = label.get_theme_color("font_color")
				for i in range(label.get_line_count()):
					var line = label.text.split("\n")[i] if i < label.text.split("\n").size() else ""
					var at = lt * Vector2(0,font.get_ascent(fs)+i*font.get_height(fs))
					out.append('<text x="%s" y="%s" font-family="Times New Roman, Liberation Serif, serif" font-size="%s" fill="#%s">%s</text>' % [f(at.x),f(at.y),f(fs*lt.x.length()),col.to_html(false),line.replace(" "," ").xml_escape()])
	out.append('</svg>')
	var file = FileAccess.open(path,FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string("\n".join(out))
	return OK

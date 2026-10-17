extends Node3D

# The card room around the table: panelled walls under damask paper, a plank
# floor and a worn rug, a bar with its shelves and mirror along the far wall,
# a sideboard, a glass-fronted bookcase, oil paintings in gilt frames, the
# door behind the seated player, beams overhead, and the haze that hangs in
# the lamp's light. Built from boxes and procedural materials so it
# needs no textures.

const WOOD := """shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec3 base : source_color = vec3(0.24, 0.13, 0.07);
uniform vec3 dark : source_color = vec3(0.12, 0.06, 0.03);
uniform float plank = 0.0;
uniform float plank_len = 1.6;
uniform float grain = 20.0;
uniform float gloss = 0.3;
uniform float seed = 0.0;
varying vec3 wpos;
varying vec3 wnrm;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec3 n = abs(wnrm);
	vec2 uv = n.y > max(n.x, n.z) ? wpos.xz : (n.x > n.z ? vec2(wpos.z, wpos.y) : wpos.xy);
	uv += vec2(seed * 3.7, seed * 1.3);
	vec2 cell = vec2(0.0);
	float seam = 1.0;
	if (plank > 0.0) {
		float row = floor(uv.y / plank);
		float off = hash(vec2(row, 3.1)) * plank_len;
		cell = vec2(floor((uv.x + off) / plank_len), row);
		vec2 f = vec2(fract((uv.x + off) / plank_len) * plank_len, fract(uv.y / plank) * plank);
		seam = smoothstep(0.0, 0.004, f.y) * smoothstep(0.0, 0.004, plank - f.y);
		seam *= smoothstep(0.0, 0.006, f.x) * smoothstep(0.0, 0.006, plank_len - f.x);
	}
	float h = hash(cell + seed);
	vec2 g = uv + vec2(h * 13.0, h * 7.0);
	float rings = sin(g.y * grain + fbm(g * vec2(1.3, 7.0)) * 7.0) * 0.5 + 0.5;
	float streak = fbm(g * vec2(0.7, 34.0));
	float t = clamp(rings * 0.4 + streak * 0.6, 0.0, 1.0);
	vec3 col = mix(dark, base, t) * mix(0.8, 1.15, h);
	ALBEDO = col * mix(0.4, 1.0, seam);
	ROUGHNESS = mix(0.72, 0.72 - gloss, t);
	SPECULAR = 0.38;
}
"""

const PAPER := """shader_type spatial;
render_mode diffuse_burley;
uniform vec3 ground : source_color = vec3(0.11, 0.14, 0.12);
uniform vec3 ink : source_color = vec3(0.17, 0.22, 0.17);
uniform float tile = 0.34;
varying vec3 wpos;
varying vec3 wnrm;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec2 uv = abs(wnrm.x) > abs(wnrm.z) ? vec2(wpos.z, wpos.y) : wpos.xy;
	vec2 q = uv / vec2(tile, tile * 1.35);
	float row = floor(q.y);
	q.x += mod(row, 2.0) * 0.5;
	vec2 f = fract(q) - 0.5;
	f.x = abs(f.x);
	// A damask medallion: lozenge, inner leaf, scrolls at the sides.
	float lozenge = abs(f.x) * 1.7 + abs(f.y);
	float body = smoothstep(0.43, 0.41, lozenge) - smoothstep(0.35, 0.33, lozenge) * 0.75;
	float leaf = smoothstep(0.035, 0.0, abs(length(vec2(f.x * 2.2, f.y + 0.06)) - 0.13));
	float scroll = smoothstep(0.03, 0.0, abs(length(vec2(f.x - 0.36, f.y * 1.2)) - 0.09));
	float stem = smoothstep(0.012, 0.0, abs(f.x)) * step(abs(f.y), 0.22);
	float motif = clamp(body + leaf + scroll + stem, 0.0, 1.0);
	float age = noise(uv * 2.2) * 0.6 + noise(uv * 9.0) * 0.4;
	vec3 col = mix(ground, ink, motif * 0.85);
	col *= mix(0.72, 1.06, age) * mix(0.85, 1.0, smoothstep(0.9, 1.7, wpos.y));
	ALBEDO = col;
	ROUGHNESS = mix(0.86, 0.6, motif);
	SPECULAR = mix(0.2, 0.42, motif);
}
"""

const RUG := """shader_type spatial;
render_mode diffuse_burley;
uniform vec3 field : source_color = vec3(0.3, 0.055, 0.045);
uniform vec3 band : source_color = vec3(0.07, 0.085, 0.16);
uniform vec3 gold : source_color = vec3(0.6, 0.43, 0.18);
uniform vec3 ivory : source_color = vec3(0.62, 0.55, 0.42);
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
void fragment() {
	vec2 uv = UV;
	vec2 c = abs(uv - 0.5) * 2.0;
	float edge = max(c.x, c.y);
	vec3 col = field;
	// Lattice of small lozenges over the field.
	vec2 q = uv * vec2(18.0, 13.0);
	vec2 fq = fract(q) - 0.5;
	float lattice = smoothstep(0.07, 0.03, abs(abs(fq.x) + abs(fq.y) - 0.32));
	float dots = smoothstep(0.1, 0.06, length(fq));
	col = mix(col, gold * 0.75, lattice * 0.55);
	col = mix(col, ivory * 0.7, dots * 0.45);
	// Central medallion in rings.
	vec2 m = (uv - 0.5) * vec2(1.35, 1.0);
	float r = length(m);
	float ring = smoothstep(0.012, 0.0, abs(r - 0.2)) + smoothstep(0.01, 0.0, abs(r - 0.15));
	float star = smoothstep(0.02, 0.0, abs(r - (0.09 + 0.03 * cos(atan(m.y, m.x) * 8.0))));
	col = mix(col, band * 1.3, smoothstep(0.205, 0.19, r) * 0.65);
	col = mix(col, gold, clamp(ring + star, 0.0, 1.0));
	// Borders: an ivory guard, a navy band with a running motif, gold lines.
	if (edge > 0.8) {
		col = band;
		float run = fract((c.x > c.y ? uv.y : uv.x) * 26.0);
		float motif = smoothstep(0.12, 0.05, abs(run - 0.5)) * step(0.84, edge) * step(edge, 0.93);
		col = mix(col, field * 1.2, motif);
	}
	col = mix(col, gold, smoothstep(0.006, 0.0, abs(edge - 0.8)) + smoothstep(0.006, 0.0, abs(edge - 0.95)));
	if (edge > 0.965) {
		col = ivory * 0.75;
	}
	// Wear: a lighter, threadbare middle and darker dust at the rim.
	float wear = noise(uv * vec2(60.0, 45.0)) * 0.5 + noise(uv * 9.0) * 0.5;
	col *= mix(0.72, 1.05, wear);
	col = mix(col, col * 1.18 + vec3(0.03), smoothstep(0.5, 0.0, edge) * 0.25);
	ALBEDO = col;
	ROUGHNESS = 0.97;
	SPECULAR = 0.08;
}
"""

const PAINTING := """shader_type spatial;
render_mode diffuse_burley;
uniform float seed = 1.0;
uniform vec3 sky_top : source_color = vec3(0.12, 0.16, 0.18);
uniform vec3 sky_low : source_color = vec3(0.55, 0.36, 0.16);
uniform vec3 land : source_color = vec3(0.09, 0.08, 0.05);
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p *= 2.1;
		a *= 0.5;
	}
	return v;
}
void fragment() {
	vec2 uv = vec2(UV.x, 1.0 - UV.y);
	vec2 s = uv + vec2(seed * 7.3, seed * 3.1);
	// Sky with clouds, a glow low on the horizon.
	vec3 col = mix(sky_low, sky_top, smoothstep(0.25, 0.95, uv.y));
	float clouds = fbm(s * vec2(3.0, 6.0));
	col = mix(col, col * 1.35 + vec3(0.05), smoothstep(0.55, 0.8, clouds) * smoothstep(0.35, 0.8, uv.y) * 0.6);
	// Two ranges of hills and a dark tree mass.
	float far = 0.38 + 0.08 * fbm(s * vec2(2.5, 1.0));
	float near = 0.24 + 0.1 * fbm(s * vec2(4.0, 1.5) + 4.0);
	col = mix(col, mix(land * 2.4, sky_low * 0.5, 0.4), smoothstep(far + 0.006, far - 0.006, uv.y));
	col = mix(col, land, smoothstep(near + 0.006, near - 0.006, uv.y));
	float tree = smoothstep(0.62, 0.5, fbm(s * 9.0) + abs(uv.x - (0.3 + 0.4 * hash(vec2(seed, 1.0)))) * 2.2 - (0.62 - uv.y) * 0.4);
	col = mix(col, land * 0.7, tree * step(near - 0.02, uv.y) * step(uv.y, 0.75));
	// Brush strokes, canvas weave, and darkened old varnish toward the frame.
	col *= 0.85 + 0.3 * noise(vec2(uv.x * 60.0, uv.y * 14.0) + seed);
	col *= 0.92 + 0.08 * sin(uv.x * 900.0) * sin(uv.y * 900.0);
	vec2 v = uv - 0.5;
	col *= mix(1.0, 0.55, smoothstep(0.3, 0.8, length(v * vec2(1.0, 1.25))));
	col *= vec3(1.0, 0.9, 0.68) * 1.7;
	ALBEDO = col;
	ROUGHNESS = 0.45;
	SPECULAR = 0.35;
}
"""

const BEAM := """shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 tint : source_color = vec3(1.0, 0.74, 0.45);
uniform float strength = 0.032;
uniform float top = 1.6;
uniform float bottom = 0.72;
varying vec3 wpos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float h = clamp((wpos.y - bottom) / (top - bottom), 0.0, 1.0);
	float rim = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 3.2);
	float drift = 0.7 + 0.3 * noise(vec2(atan(wpos.z, wpos.x) * 3.0, wpos.y * 4.0 + TIME * 0.15));
	ALBEDO = tint * strength * rim * drift * mix(0.35, 1.0, h);
}
"""

var _materials := {}


func build(half: float, height: float, lamp: Vector3) -> void:
	_floor(half)
	_rug()
	for wall in _walls(half):
		_wall(wall, height)
	_ceiling(half, height)
	_bar(half)
	_sideboard(half)
	_bookcase(half)
	_door(half)
	_paintings(half)
	_sconces(half)
	_floor_lamp(half)
	_beam(lamp)


# --- materials ------------------------------------------------------------------

func _shader(code: String) -> Shader:
	var key := "s%d" % code.hash()
	if not _materials.has(key):
		var shader := Shader.new()
		shader.code = code
		_materials[key] = shader
	return _materials[key]


func _wood(base: Color, dark: Color, plank := 0.0, gloss := 0.3, seed := 0.0, grain := 20.0) -> ShaderMaterial:
	var key := "w%s%s%.2f%.2f%.2f%.1f" % [base, dark, plank, gloss, seed, grain]
	if _materials.has(key):
		return _materials[key]
	var mat := ShaderMaterial.new()
	mat.shader = _shader(WOOD)
	mat.set_shader_parameter("base", base)
	mat.set_shader_parameter("dark", dark)
	mat.set_shader_parameter("plank", plank)
	mat.set_shader_parameter("gloss", gloss)
	mat.set_shader_parameter("seed", seed)
	mat.set_shader_parameter("grain", grain)
	_materials[key] = mat
	return mat


func _plain(color: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var key := "p%s%.2f%.2f" % [color, rough, metal]
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	mat.metallic = metal
	_materials[key] = mat
	return mat


func _brass() -> StandardMaterial3D:
	return _plain(Color(0.72, 0.55, 0.26), 0.3, 0.85)


func _gilt() -> StandardMaterial3D:
	return _plain(Color(0.66, 0.48, 0.2), 0.38, 0.8)


func _glass(color: Color) -> StandardMaterial3D:
	var key := "g%s" % color
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.06
	mat.metallic_specular = 0.7
	_materials[key] = mat
	return mat


func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return mat


func _box(size: Vector3, at: Vector3, mat: Material, yaw := 0.0) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = mat
	node.position = at
	node.rotation.y = yaw
	add_child(node)
	return node


func _cylinder(radius: float, tall: float, at: Vector3, mat: Material, top := -1.0, sides := 20) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top < 0.0 else top
	mesh.height = tall
	mesh.radial_segments = sides
	mesh.rings = 1
	node.mesh = mesh
	node.material_override = mat
	node.position = at
	add_child(node)
	return node


func _sphere(radius: float, at: Vector3, mat: Material, squash := 1.0) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0 * squash
	mesh.radial_segments = 20
	mesh.rings = 10
	node.mesh = mesh
	node.material_override = mat
	node.position = at
	add_child(node)
	return node


# --- floor, rug, walls, ceiling ---------------------------------------------------------

func _floor(half: float) -> void:
	var boards := _wood(Color(0.27, 0.15, 0.08), Color(0.11, 0.055, 0.028), 0.16, 0.32, 0.0, 26.0)
	_box(Vector3(half * 2.0, 0.06, half * 2.0), Vector3(0.0, -0.03, 0.0), boards)


func _rug() -> void:
	var rug := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(3.9, 3.1)
	rug.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = _shader(RUG)
	rug.material_override = mat
	rug.position = Vector3(0.0, 0.004, -0.15)
	add_child(rug)


func _walls(half: float) -> Array:
	# Each wall: centre on the floor, the direction it faces into the room,
	# and its length.
	return [
		{"at": Vector3(0.0, 0.0, -half), "in": Vector3.BACK, "len": half * 2.0},
		{"at": Vector3(0.0, 0.0, half), "in": Vector3.FORWARD, "len": half * 2.0},
		{"at": Vector3(-half, 0.0, 0.0), "in": Vector3.RIGHT, "len": half * 2.0},
		{"at": Vector3(half, 0.0, 0.0), "in": Vector3.LEFT, "len": half * 2.0},
	]


func _wall(wall: Dictionary, height: float) -> void:
	# Damask paper above a chair rail; below it raised panels framed by
	# stiles and rails; a skirting board, a picture rail and a cornice.
	var at: Vector3 = wall["at"]
	var inward: Vector3 = wall["in"]
	var length: float = wall["len"]
	var yaw := atan2(inward.x, inward.z)
	var along := Vector3.UP.cross(inward).normalized()
	var paper := ShaderMaterial.new()
	paper.shader = _shader(PAPER)
	var dado := 1.02
	_box(Vector3(length, height, 0.1), at + Vector3.UP * (height * 0.5) - inward * 0.05, paper, yaw)
	var panel_wood := _wood(Color(0.27, 0.14, 0.07), Color(0.11, 0.055, 0.028), 0.0, 0.34, at.x + at.z, 14.0)
	var frame_wood := _wood(Color(0.32, 0.17, 0.085), Color(0.13, 0.065, 0.032), 0.0, 0.42, at.x - at.z + 2.0, 18.0)
	_box(Vector3(length, dado, 0.03), at + Vector3.UP * (dado * 0.5) + inward * 0.015, panel_wood, yaw)
	var bays := int(floor(length / 0.85))
	var bay := length / float(bays)
	for i in bays + 1:
		var offset := -length * 0.5 + float(i) * bay
		_box(Vector3(0.09, dado - 0.16, 0.025), at + along * offset + Vector3.UP * (0.08 + (dado - 0.16) * 0.5) + inward * 0.04, frame_wood, yaw)
	for y in [0.2, dado - 0.06]:
		_box(Vector3(length, 0.07, 0.025), at + Vector3.UP * y + inward * 0.04, frame_wood, yaw)
	for i in bays:
		# A raised field in each bay with a bevelled lip.
		var offset := -length * 0.5 + (float(i) + 0.5) * bay
		var centre := at + along * offset + Vector3.UP * ((0.24 + dado - 0.1) * 0.5) + inward * 0.034
		_box(Vector3(bay - 0.2, dado - 0.4, 0.012), centre, panel_wood, yaw)
		_box(Vector3(bay - 0.12, dado - 0.32, 0.006), centre - inward * 0.004, frame_wood, yaw)
	_box(Vector3(length, 0.05, 0.06), at + Vector3.UP * (dado + 0.01) + inward * 0.05, frame_wood, yaw)
	_box(Vector3(length, 0.16, 0.035), at + Vector3.UP * 0.08 + inward * 0.05, _wood(Color(0.14, 0.07, 0.035), Color(0.06, 0.03, 0.015)), yaw)
	_box(Vector3(length, 0.035, 0.03), at + Vector3.UP * (height - 0.52) + inward * 0.02, frame_wood, yaw)
	_box(Vector3(length, 0.14, 0.12), at + Vector3.UP * (height - 0.07) + inward * 0.06, frame_wood, yaw)
	_box(Vector3(length, 0.05, 0.18), at + Vector3.UP * (height - 0.16) + inward * 0.09, frame_wood, yaw)


func _ceiling(half: float, height: float) -> void:
	var boards := _wood(Color(0.13, 0.07, 0.035), Color(0.05, 0.025, 0.012), 0.22, 0.1, 5.0, 12.0)
	_box(Vector3(half * 2.0, 0.08, half * 2.0), Vector3(0.0, height + 0.04, 0.0), boards)
	var beam := _wood(Color(0.17, 0.09, 0.045), Color(0.07, 0.035, 0.018), 0.0, 0.2, 9.0, 16.0)
	for i in 5:
		var x := -half + (float(i) + 0.5) * half * 2.0 / 5.0
		_box(Vector3(0.18, 0.2, half * 2.0), Vector3(x, height - 0.1, 0.0), beam)
	for z in [-half * 0.45, half * 0.45]:
		_box(Vector3(half * 2.0, 0.12, 0.14), Vector3(0.0, height - 0.08, z), beam)


# --- furniture ------------------------------------------------------------------------

func _bar(half: float) -> void:
	# Counter with a brass foot rail and three stools; behind it a back bar of
	# shelves and bottles around a gilt-framed mirror.
	var z := -half + 0.62
	var body := _wood(Color(0.22, 0.11, 0.055), Color(0.09, 0.045, 0.022), 0.0, 0.38, 3.0, 16.0)
	var top := _wood(Color(0.32, 0.17, 0.08), Color(0.14, 0.07, 0.035), 0.0, 0.55, 4.0, 10.0)
	_box(Vector3(3.6, 1.0, 0.56), Vector3(0.0, 0.5, z), body)
	for i in 6:
		_box(Vector3(0.52, 0.66, 0.02), Vector3(-1.5 + i * 0.6, 0.5, z + 0.285), _wood(Color(0.24, 0.12, 0.06), Color(0.1, 0.05, 0.025), 0.0, 0.42, float(i), 16.0))
	_box(Vector3(3.74, 0.06, 0.66), Vector3(0.0, 1.03, z + 0.02), top)
	_cylinder(0.018, 3.7, Vector3(0.0, 0.16, z + 0.42), _brass()).rotation = Vector3(0.0, 0.0, PI * 0.5)
	for x in [-1.7, 0.0, 1.7]:
		_box(Vector3(0.03, 0.14, 0.03), Vector3(x, 0.1, z + 0.38), _brass())
	for x in [-1.1, 0.0, 1.1]:
		_cylinder(0.025, 0.72, Vector3(x, 0.36, z + 0.85), _brass())
		_cylinder(0.2, 0.025, Vector3(x, 0.02, z + 0.85), _brass(), 0.18)
		_cylinder(0.2, 0.08, Vector3(x, 0.76, z + 0.85), _plain(Color(0.3, 0.07, 0.05), 0.65), 0.21)
	var back := -half + 0.12
	var shelf_wood := _wood(Color(0.2, 0.1, 0.05), Color(0.08, 0.04, 0.02), 0.0, 0.35, 6.0, 16.0)
	_box(Vector3(3.4, 1.62, 0.04), Vector3(0.0, 1.95, back + 0.02), shelf_wood)
	for y in [1.32, 1.76, 2.2]:
		for side in [-1.0, 1.0]:
			_box(Vector3(1.05, 0.035, 0.26), Vector3(side * 1.12, y, back + 0.15), shelf_wood)
	for side in [-1.0, 1.0]:
		for x in [0.6, 1.64]:
			_box(Vector3(0.05, 1.62, 0.28), Vector3(side * x, 1.95, back + 0.15), shelf_wood)
	_box(Vector3(3.5, 0.08, 0.32), Vector3(0.0, 2.78, back + 0.16), shelf_wood)
	# Mirror in the middle bay.
	_box(Vector3(1.0, 1.24, 0.06), Vector3(0.0, 1.88, back + 0.06), _gilt())
	_box(Vector3(0.88, 1.12, 0.02), Vector3(0.0, 1.88, back + 0.1), _plain(Color(0.12, 0.13, 0.14), 0.04, 0.95))
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var tints := [Color(0.25, 0.4, 0.15, 0.6), Color(0.45, 0.2, 0.08, 0.62), Color(0.12, 0.1, 0.08, 0.75), Color(0.6, 0.45, 0.18, 0.5), Color(0.15, 0.3, 0.25, 0.6), Color(0.5, 0.12, 0.1, 0.6)]
	for y in [1.32, 1.76, 2.2]:
		for side in [-1.0, 1.0]:
			var x: float = side * 0.66
			while absf(x) < 1.58:
				var tall := rng.randf_range(0.2, 0.32)
				var radius := rng.randf_range(0.032, 0.045)
				var glass: StandardMaterial3D = _glass(tints[rng.randi() % tints.size()])
				var base := Vector3(x, y + 0.018 + tall * 0.36, back + 0.16 + rng.randf_range(-0.04, 0.04))
				_cylinder(radius, tall * 0.72, base, glass)
				_cylinder(radius * 0.35, tall * 0.3, base + Vector3.UP * (tall * 0.5), glass, radius * 0.3)
				x += side * rng.randf_range(0.1, 0.14)
	# A few glasses on the counter.
	for x in [-0.9, -0.75, 0.6]:
		_cylinder(0.03, 0.09, Vector3(x, 1.105, z + 0.08), _glass(Color(0.8, 0.85, 0.9, 0.25)), 0.035)


func _sideboard(half: float) -> void:
	# Against the left wall: a low sideboard, brass vase, decanter and two
	# candlesticks.
	var x := -half + 0.32
	var body := _wood(Color(0.21, 0.105, 0.05), Color(0.085, 0.04, 0.02), 0.0, 0.42, 11.0, 16.0)
	_box(Vector3(0.52, 0.86, 1.9), Vector3(x, 0.47, -0.55), body)
	_box(Vector3(0.58, 0.05, 2.0), Vector3(x + 0.02, 0.92, -0.55), _wood(Color(0.3, 0.16, 0.075), Color(0.13, 0.065, 0.03), 0.0, 0.55, 12.0, 10.0))
	for i in 3:
		var zc := -1.18 + i * 0.63
		_box(Vector3(0.02, 0.56, 0.56), Vector3(x + 0.265, 0.42, zc), _wood(Color(0.25, 0.125, 0.06), Color(0.1, 0.05, 0.025), 0.0, 0.45, 13.0 + i, 16.0))
		_sphere(0.022, Vector3(x + 0.29, 0.5, zc + 0.18), _brass())
	_box(Vector3(0.5, 0.06, 1.86), Vector3(x, 0.05, -0.55), _wood(Color(0.12, 0.06, 0.03), Color(0.05, 0.025, 0.012)))
	_cylinder(0.06, 0.06, Vector3(x, 0.98, -1.15), _brass(), 0.09)
	_sphere(0.11, Vector3(x, 1.12, -1.15), _brass(), 1.15)
	_cylinder(0.035, 0.22, Vector3(x, 1.32, -1.15), _brass(), 0.05)
	_sphere(0.07, Vector3(x, 1.02, -0.35), _glass(Color(0.55, 0.3, 0.1, 0.55)))
	_cylinder(0.018, 0.12, Vector3(x, 1.13, -0.35), _glass(Color(0.55, 0.3, 0.1, 0.45)))
	for zc in [-0.05, 0.25]:
		_cylinder(0.035, 0.03, Vector3(x, 0.96, zc), _brass())
		_cylinder(0.012, 0.22, Vector3(x, 1.08, zc), _brass())
		_cylinder(0.012, 0.12, Vector3(x, 1.25, zc), _plain(Color(0.9, 0.86, 0.74), 0.7))
		_sphere(0.012, Vector3(x, 1.33, zc), _glow(Color(1.0, 0.7, 0.35), 3.0), 1.6)


func _bookcase(half: float) -> void:
	# Right wall: a tall glass-fronted case of books with a clock on top.
	var x := half - 0.27
	var body := _wood(Color(0.2, 0.1, 0.05), Color(0.08, 0.04, 0.02), 0.0, 0.4, 21.0, 16.0)
	var z0 := -1.0
	_box(Vector3(0.44, 2.3, 1.5), Vector3(x, 1.15, z0), body)
	_box(Vector3(0.5, 0.08, 1.58), Vector3(x - 0.02, 2.33, z0), body)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var spines := [Color(0.35, 0.07, 0.06), Color(0.12, 0.2, 0.12), Color(0.3, 0.2, 0.1), Color(0.1, 0.1, 0.18), Color(0.4, 0.3, 0.15), Color(0.22, 0.05, 0.05)]
	for shelf in 4:
		var y := 0.42 + shelf * 0.48
		_box(Vector3(0.36, 0.03, 1.4), Vector3(x - 0.02, y, z0), body)
		var z := z0 - 0.66
		while z < z0 + 0.64:
			var w := rng.randf_range(0.025, 0.05)
			var h := rng.randf_range(0.26, 0.38)
			var spine: Color = spines[rng.randi() % spines.size()]
			var book := _box(Vector3(0.24, h, w), Vector3(x - 0.06, y + 0.015 + h * 0.5, z + w * 0.5), _plain(spine, 0.8))
			book.rotation.x = rng.randf_range(-0.04, 0.04)
			if rng.randf() < 0.5:
				_box(Vector3(0.002, 0.02, w * 0.9), Vector3(x - 0.185, y + h * 0.7, z + w * 0.5), _gilt())
			z += w + 0.004
			if rng.randf() < 0.06:
				z += 0.1
	for k in 2:
		var zc := z0 - 0.37 + k * 0.74
		_box(Vector3(0.025, 2.06, 0.7), Vector3(x - 0.225, 1.16, zc), _glass(Color(0.6, 0.7, 0.75, 0.12)))
		_box(Vector3(0.03, 2.08, 0.04), Vector3(x - 0.225, 1.16, zc - 0.35), body)
		_box(Vector3(0.03, 2.08, 0.04), Vector3(x - 0.225, 1.16, zc + 0.35), body)
		_sphere(0.016, Vector3(x - 0.25, 1.2, zc + (0.3 if k == 0 else -0.3)), _brass())
	var inside := OmniLight3D.new()
	inside.light_color = Color(1.0, 0.76, 0.5)
	inside.light_energy = 0.45
	inside.omni_range = 1.1
	inside.position = Vector3(x - 0.12, 1.45, z0)
	add_child(inside)
	_box(Vector3(0.2, 0.28, 0.32), Vector3(x - 0.05, 2.51, z0), body)
	_cylinder(0.09, 0.02, Vector3(x - 0.16, 2.53, z0), _plain(Color(0.88, 0.84, 0.72), 0.5)).rotation = Vector3(0.0, 0.0, PI * 0.5)


func _door(half: float) -> void:
	# Behind the seated player: a panelled door in a moulded case.
	var z := half - 0.06
	var case_wood := _wood(Color(0.22, 0.11, 0.055), Color(0.09, 0.045, 0.022), 0.0, 0.4, 31.0, 16.0)
	var leaf := _wood(Color(0.19, 0.095, 0.047), Color(0.075, 0.037, 0.018), 0.0, 0.42, 32.0, 14.0)
	_box(Vector3(1.24, 2.26, 0.1), Vector3(0.0, 1.13, z), case_wood)
	_box(Vector3(0.96, 2.06, 0.06), Vector3(0.0, 1.03, z - 0.05), leaf)
	for row in 3:
		for col in 2:
			var cx := -0.22 + col * 0.44
			var cy := 0.42 + row * 0.6
			_box(Vector3(0.34, 0.48, 0.015), Vector3(cx, cy, z - 0.085), case_wood)
			_box(Vector3(0.28, 0.42, 0.012), Vector3(cx, cy, z - 0.092), leaf)
	_sphere(0.035, Vector3(0.38, 1.02, z - 0.1), _brass())
	_box(Vector3(0.05, 0.14, 0.02), Vector3(0.38, 1.02, z - 0.085), _brass())


func _paintings(half: float) -> void:
	var specs := [
		{"at": Vector3(-half + 0.08, 1.78, -0.55), "in": Vector3.RIGHT, "size": Vector2(1.3, 0.92), "seed": 2.0},
		{"at": Vector3(half - 0.08, 1.7, 1.25), "in": Vector3.LEFT, "size": Vector2(0.8, 1.0), "seed": 5.0},
		{"at": Vector3(-1.75, 1.72, half - 0.08), "in": Vector3.FORWARD, "size": Vector2(0.9, 0.7), "seed": 8.0},
		{"at": Vector3(1.75, 1.72, half - 0.08), "in": Vector3.FORWARD, "size": Vector2(0.9, 0.7), "seed": 11.0},
		{"at": Vector3(-half + 0.08, 1.72, 2.2), "in": Vector3.RIGHT, "size": Vector2(0.7, 0.9), "seed": 14.0},
	]
	for spec in specs:
		var at: Vector3 = spec["at"]
		var inward: Vector3 = spec["in"]
		var size: Vector2 = spec["size"]
		var yaw := atan2(inward.x, inward.z)
		_box(Vector3(size.x + 0.16, size.y + 0.16, 0.05), at + inward * 0.025, _gilt(), yaw)
		_box(Vector3(size.x + 0.06, size.y + 0.06, 0.02), at + inward * 0.055, _plain(Color(0.25, 0.17, 0.08), 0.5, 0.5), yaw)
		var canvas := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = size
		canvas.mesh = quad
		var mat := ShaderMaterial.new()
		mat.shader = _shader(PAINTING)
		mat.set_shader_parameter("seed", float(spec["seed"]))
		canvas.material_override = mat
		canvas.position = at + inward * 0.068
		canvas.rotation.y = yaw
		add_child(canvas)


func _sconces(half: float) -> void:
	var spots := [
		[Vector3(-half + 0.09, 1.72, -1.75), Vector3.RIGHT],
		[Vector3(-half + 0.09, 1.72, 0.65), Vector3.RIGHT],
		[Vector3(half - 0.09, 1.66, 0.35), Vector3.LEFT],
		[Vector3(half - 0.09, 1.66, 2.15), Vector3.LEFT],
		[Vector3(-0.95, 1.7, half - 0.09), Vector3.FORWARD],
		[Vector3(0.95, 1.7, half - 0.09), Vector3.FORWARD],
		[Vector3(-2.35, 1.95, -half + 0.09), Vector3.BACK],
		[Vector3(2.35, 1.95, -half + 0.09), Vector3.BACK],
	]
	for spot in spots:
		var at: Vector3 = spot[0]
		var inward: Vector3 = spot[1]
		_box(Vector3(0.1, 0.18, 0.04) if absf(inward.z) > 0.5 else Vector3(0.04, 0.18, 0.1), at, _brass())
		_cylinder(0.012, 0.12, at + inward * 0.07 + Vector3.DOWN * 0.02, _brass()).rotation = Vector3(PI * 0.5 * absf(inward.z), 0.0, PI * 0.5 * absf(inward.x))
		var shade := _cylinder(0.075, 0.13, at + inward * 0.14 + Vector3.UP * 0.06, _glow(Color(1.0, 0.78, 0.5), 1.1), 0.045)
		shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.7, 0.42)
		light.light_energy = 0.95
		light.omni_range = 3.0
		light.omni_attenuation = 1.4
		light.position = at + inward * 0.16 + Vector3.UP * 0.04
		add_child(light)


func _floor_lamp(half: float) -> void:
	# Far right corner: a standing lamp with a pleated silk shade.
	var at := Vector3(half - 0.55, 0.0, -half + 0.6)
	_cylinder(0.17, 0.035, at + Vector3.UP * 0.018, _brass(), 0.14)
	_cylinder(0.014, 1.5, at + Vector3.UP * 0.78, _brass())
	var shade := _cylinder(0.24, 0.3, at + Vector3.UP * 1.58, _glow(Color(0.95, 0.72, 0.45), 0.85), 0.15, 24)
	shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.72, 0.45)
	light.light_energy = 1.4
	light.omni_range = 3.6
	light.position = at + Vector3.UP * 1.55
	add_child(light)


# --- air ------------------------------------------------------------------------------

func _beam(lamp: Vector3) -> void:
	# The lamp's light made visible in the haze: a soft cone down to the felt.
	var cone := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.2
	mesh.bottom_radius = 0.95
	mesh.height = lamp.y - 0.72
	mesh.radial_segments = 48
	mesh.rings = 1
	mesh.cap_top = false
	mesh.cap_bottom = false
	cone.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = _shader(BEAM)
	mat.set_shader_parameter("top", lamp.y)
	mat.set_shader_parameter("bottom", 0.72)
	cone.material_override = mat
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cone.position = Vector3(lamp.x, (lamp.y + 0.72) * 0.5, lamp.z)
	add_child(cone)


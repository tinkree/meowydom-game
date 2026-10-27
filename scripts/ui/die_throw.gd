extends SubViewportContainer

const DIE_SCALE := Vector3(0.32, 0.32, 0.32)

var _die: MeshInstance3D
var _shadow: MeshInstance3D
var _shadow_mat: StandardMaterial3D
var _face_normal: Dictionary = {}
var _face_up: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var viewport := SubViewport.new()
	viewport.name = "DieViewport"
	viewport.size = Vector2i(720, 720)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.handle_input_locally = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0, 0, 0, 0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(1, 0.96, 0.9)
	environment.ambient_light_energy = 0.7
	var world := WorldEnvironment.new()
	world.environment = environment
	viewport.add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, 38, 0)
	key.light_energy = 1.25
	key.shadow_enabled = true
	viewport.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18, -150, 0)
	fill.light_energy = 0.4
	viewport.add_child(fill)
	var camera := Camera3D.new()
	camera.position = Vector3(1.55, 2.35, 3.55)
	camera.fov = 26
	camera.current = true
	viewport.add_child(camera)
	camera.look_at(Vector3(0, 0.0, 0))
	_shadow = MeshInstance3D.new()
	_shadow.mesh = QuadMesh.new()
	_shadow.mesh.size = Vector2(0.62, 0.62)
	_shadow.rotation_degrees = Vector3(-90, 0, 0)
	_shadow.position = Vector3(0, -0.52, 0)
	_shadow_mat = StandardMaterial3D.new()
	_shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shadow_mat.albedo_texture = _shadow_texture()
	_shadow_mat.albedo_color = Color(0, 0, 0, 0.45)
	_shadow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shadow.mesh.material = _shadow_mat
	viewport.add_child(_shadow)
	_die = MeshInstance3D.new()
	_die.mesh = _cube_mesh()
	_die.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	viewport.add_child(_die)
	_die.position = Vector3(0, 3.2, 0)


func play(face: int) -> void:
	if _die == null:
		return
	var shown := clampi(face, 1, 6)
	var final_basis := _basis_for_face(shown)
	var start := Vector3(-0.95, 0.42, -0.45)
	var landing := Vector3(0.0, 0.0, 0.0)
	var spins := Vector3(TAU * 2.2, TAU * 3.4, TAU * 1.6)
	var duration := 0.95
	var elapsed := 0.0
	while elapsed < duration:
		var delta := get_process_delta_time()
		if delta <= 0.0:
			delta = 0.016
		elapsed += delta
		var u: float = clampf(elapsed / duration, 0.0, 1.0)
		var travel := u * u * (3.0 - 2.0 * u)
		var pos := start.lerp(landing, travel)
		pos.y += sin(u * PI) * 0.28
		if u > 0.78:
			var bounce := (u - 0.78) / 0.22
			pos.y += sin(bounce * PI) * 0.16 * (1.0 - bounce)
		var spin_basis := Basis.from_euler(spins * (1.0 - travel))
		_die.transform = Transform3D(_posed(spin_basis, final_basis, u), pos)
		_place_shadow(pos.y)
		await get_tree().process_frame
	_die.transform = Transform3D(final_basis.scaled(DIE_SCALE), landing)
	_place_shadow(landing.y)
	await get_tree().create_timer(0.55).timeout


func _posed(spin_basis: Basis, final_basis: Basis, u: float) -> Basis:
	if u < 0.58:
		return spin_basis.scaled(DIE_SCALE)
	var settle: float = (u - 0.58) / 0.42
	settle = settle * settle * (3.0 - 2.0 * settle)
	return spin_basis.slerp(final_basis, settle).scaled(DIE_SCALE)


func _place_shadow(height: float) -> void:
	var lift: float = clampf(height / 2.2, 0.0, 1.0)
	_shadow.position = Vector3(_die.position.x, -0.52, _die.position.z)
	var spread := lerpf(0.72, 1.25, lift)
	_shadow.scale = Vector3(spread, spread, 1.0)
	_shadow_mat.albedo_color = Color(0, 0, 0, lerpf(0.42, 0.12, lift))


func _basis_for_face(face: int) -> Basis:
	var normal: Vector3 = _face_normal[face]
	var texture_up: Vector3 = _face_up[face]
	var align := _quat_from_to(normal, Vector3.UP)
	var pointing: Vector3 = align * texture_up
	pointing.y = 0.0
	if pointing.length_squared() < 0.0001:
		return Basis(align)
	var twist := _quat_from_to(pointing.normalized(), Vector3(0, 0, 1))
	return Basis(twist * align)


func _quat_from_to(from_dir: Vector3, to_dir: Vector3) -> Quaternion:
	var a := from_dir.normalized()
	var b := to_dir.normalized()
	var dot := clampf(a.dot(b), -1.0, 1.0)
	if dot > 0.9999:
		return Quaternion.IDENTITY
	if dot < -0.9999:
		var fallback := a.cross(Vector3.RIGHT)
		if fallback.length_squared() < 0.0001:
			fallback = a.cross(Vector3.UP)
		return Quaternion(fallback.normalized(), PI)
	return Quaternion(a.cross(b).normalized(), acos(dot))


func _cube_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var specs: Array = [
		[Vector3.UP, Vector3(0, 0, 1), 1],
		[Vector3.DOWN, Vector3(0, 0, 1), 6],
		[Vector3.RIGHT, Vector3.UP, 3],
		[Vector3.LEFT, Vector3.UP, 4],
		[Vector3.BACK, Vector3.UP, 2],
		[Vector3.FORWARD, Vector3.UP, 5],
	]
	for spec in specs:
		var normal: Vector3 = spec[0]
		var texture_up: Vector3 = spec[1]
		var face := int(spec[2])
		_face_normal[face] = normal
		_face_up[face] = texture_up
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		_add_face(tool, normal, texture_up)
		tool.set_material(_face_material(face))
		tool.commit(mesh)
	return mesh


func _add_face(tool: SurfaceTool, normal: Vector3, texture_up: Vector3) -> void:
	var n := normal.normalized()
	var up := texture_up.slide(n).normalized()
	var right := up.cross(n).normalized()
	var center := n * 0.5
	var half := 0.5
	var corners: Array[Vector3] = [
		center + (-right - up) * half,
		center + (right - up) * half,
		center + (right + up) * half,
		center + (-right + up) * half,
	]
	var uvs: Array[Vector2] = [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	var order: Array[int] = [0, 1, 2, 0, 2, 3]
	for index in order:
		tool.set_normal(n)
		tool.set_uv(uvs[index])
		tool.add_vertex(corners[index])


func _face_material(face: int) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = load("res://assets/ui/d%d.png" % face)
	material.roughness = 0.42
	material.metallic = 0.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return material


func _shadow_texture() -> Texture2D:
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var point := Vector2(float(x) / 63.0, float(y) / 63.0) * 2.0 - Vector2.ONE
			var dist := point.length()
			var alpha := clampf(1.0 - smoothstep(0.15, 1.0, dist), 0.0, 1.0)
			image.set_pixel(x, y, Color(0, 0, 0, alpha))
	return ImageTexture.create_from_image(image)

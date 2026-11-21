extends RefCounted
## Unreal-style conservative decal admission before allocating/recycling GPU nodes.
## The same finite-input, distance and projected-screen-size rules are in C++.
## This policy is cosmetic-only: no physics occlusion or server simulation.


static func should_spawn(camera_position: Vector3, decal_position: Vector3,
		diameter_m: float, max_distance_m: float, viewport_height_px: float,
		vertical_fov_deg: float, min_diameter_px: float = 3.0) -> bool:
	if not camera_position.is_finite() or not decal_position.is_finite() \
			or not is_finite(diameter_m) or not is_finite(max_distance_m) \
			or not is_finite(viewport_height_px) or not is_finite(vertical_fov_deg) \
			or not is_finite(min_diameter_px) \
			or diameter_m < 0.01 or diameter_m > 128.0 \
			or max_distance_m < 0.5 or max_distance_m > 10000.0 \
			or viewport_height_px < 32.0 or viewport_height_px > 16384.0 \
			or vertical_fov_deg < 5.0 or vertical_fov_deg > 170.0 \
			or min_diameter_px < 0.0 or min_diameter_px > 128.0:
		return false
	# Direct component checks: no temporary arrays or Variant dictionaries
	# per combat hit on the stock-Godot fallback path.
	if absf(camera_position.x) > 10000000.0 \
			or absf(camera_position.y) > 10000000.0 \
			or absf(camera_position.z) > 10000000.0 \
			or absf(decal_position.x) > 10000000.0 \
			or absf(decal_position.y) > 10000000.0 \
			or absf(decal_position.z) > 10000000.0:
		return false
	var distance: float = camera_position.distance_to(decal_position)
	if distance > max_distance_m + diameter_m * 0.5:
		return false
	var focal: float = viewport_height_px / (
		2.0 * tan(deg_to_rad(vertical_fov_deg * 0.5)))
	var pixels: float = diameter_m * focal / maxf(distance, 0.1)
	return pixels >= min_diameter_px


## Conservative legacy behavior when there is no live perspective camera,
## for example during a headless test or while loading a scene.
static func can_project(node: Node3D, position: Vector3,
		diameter_m: float, max_distance_m: float, min_pixels: float,
		native_policy: Object = null) -> bool:
	if node == null or not node.is_inside_tree():
		return true
	var viewport: Viewport = node.get_viewport()
	if viewport == null:
		return true
	var camera: Camera3D = viewport.get_camera_3d()
	if camera == null or camera.projection != Camera3D.PROJECTION_PERSPECTIVE:
		return true
	var viewport_size: Vector2 = viewport.get_visible_rect().size
	if viewport_size.x < 32.0 or viewport_size.y < 32.0:
		return true
	var vertical_fov: float = camera.fov
	if camera.keep_aspect == Camera3D.KEEP_WIDTH:
		vertical_fov = rad_to_deg(2.0 * atan(
			tan(deg_to_rad(camera.fov * 0.5)) *
			viewport_size.y / viewport_size.x))
	if native_policy != null and native_policy.has_method("should_spawn"):
		return bool(native_policy.call("should_spawn", camera.global_position,
			position, diameter_m, max_distance_m, viewport_size.y,
			vertical_fov, min_pixels))
	return should_spawn(camera.global_position, position, diameter_m,
		max_distance_m, viewport_size.y, vertical_fov, min_pixels)

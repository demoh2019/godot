extends Node3D
## Cosmetic rigid-body debris, spent casings and blast impulses (Unreal Chaos Destruction "lite" + Physics Fields,
## Unity PhysX rigidbodies + explosion force). Everything lives on its own collision layer against one local
## heightmap collider that follows the player, so nothing here can touch gameplay or server state.
##  - barricade breaks burst into wood chunks that tumble, sleep, shrink away and are pooled
##  - ranged shots eject brass casings
##  - blasts push debris and ragdoll corpses (PhysicalBone3D on Ragdoll.LAYER) with a radial falloff field
##  - bodies in water float and bob on a wave surface (buoyancy)
## Per-tier budgets cap live bodies; the oldest are recycled first.

const Ragdoll = preload("res://scripts/client/ragdoll.gd")
const EngineFeatures = preload("res://scripts/client/engine_features.gd")
const DebrisLOD = preload("res://scripts/client/debris_simulation_lod.gd")

const LAYER := 1 << 20
const CHUNK_BUDGET := [0, 10, 24, 48] # Low, Medium, High, Ultra.
const CASING_BUDGET := [0, 0, 10, 24]
const LIFETIME := 9.0 # Hard cap per body.
const SLEEP_RETIRE := 1.5 # Seconds asleep before shrinking away.
const SHRINK := 0.8
const GROUND_SIZE := 17 # Heightmap samples per side, 1 m apart.
const RECENTER := 4.0
const WATER_SURFACE := -0.35 # Matches the water plane in online_main (WATER_LEVEL - 0.35).
const BLAST_WALL_MASK := 1 # World geometry (not cosmetic debris or ragdolls).
const BLAST_WALL_ATTENUATION := 0.25 # Thick walls absorb 75% of the impulse.
const BLAST_MAX_OCCLUSION_RAYS := 24 # One extra ray per body, bounded.
# Chaos-style cosmetic simulation tiers, distinct from collision/AI physics.
const SIMULATE_RADIUS := 24.0
const RETIRE_RADIUS := 56.0
const SIMULATION_HYSTERESIS := 2.0
const BLAST_WAKE_GRACE := 0.40 # Keep blast-affected frozen pieces temporarily live.

var _height_at := Callable()
var _is_water := Callable()
var _ground: StaticBody3D
var _ground_center := Vector2(INF, INF)
var _bodies: Array[RigidBody3D] = [] # Active, oldest first.
var _free: Array[RigidBody3D] = []
var _blasts: Array = []
var _clock := 0.0
var _wood_material: StandardMaterial3D
var _brass_material: StandardMaterial3D
var _viewer_position := Vector3.ZERO
var _viewer_valid := false
var _native_lod: Object = EngineFeatures.make("DebrisSimulationLOD3D")


## Current graphics tier; loaded lazily so the pure helpers above stay unit-testable without the renderer stack.
static func quality_level() -> int:
	return load("res://scripts/client/graphics_quality.gd").level()


static func chunk_budget(level: int) -> int:
	return CHUNK_BUDGET[clampi(level, 0, CHUNK_BUDGET.size() - 1)]


static func casing_budget(level: int) -> int:
	return CASING_BUDGET[clampi(level, 0, CASING_BUDGET.size() - 1)]


static func total_budget(level: int) -> int:
	return chunk_budget(level) + casing_budget(level)


## How many chunks a break spawns, bounded by the tier.
static func chunk_count(level: int, strength: float = 1.0) -> int:
	var cap := chunk_budget(level)
	if cap <= 0:
		return 0
	return clampi(int(round(cap * 0.5 * clampf(strength, 0.0, 2.0))), 1, cap)


## Edge lengths of chunk number `index` from a deterministic hash (planks vs shards).
static func chunk_size(index: int) -> Vector3:
	var h := fposmod(sin(float(index) * 12.9898) * 43758.5453, 1.0)
	return Vector3(lerpf(0.1, 0.3, h), lerpf(0.05, 0.1, fposmod(h * 7.3, 1.0)), lerpf(0.08, 0.5, fposmod(h * 3.1, 1.0)))


## Radial blast falloff: 1 at the centre, 0 at the radius, quadratic in between.
static func falloff(distance: float, radius: float) -> float:
	if radius <= 0.0 or distance >= radius or distance < 0.0:
		return 0.0
	var k := 1.0 - distance / radius
	return k * k


## Factor for the energy of an explosion behind a wall. The same
## calculation is in RadialForceField3D::occlusion_scale (native C++).
static func blast_shielding(blocked: bool, attenuation: float = BLAST_WALL_ATTENUATION) -> float:
	return clampf(attenuation, 0.0, 1.0) if blocked else 1.0


## Mass-independent explosion: the impulse scales by mass, so the
## resulting velocity change is independent of the body's weight.
static func blast_impulse_magnitude(strength: float, falloff_scale: float, mass: float) -> float:
	return strength * falloff_scale * mass


## Upward buoyancy force for a body whose centre is `depth` metres below the surface (<= 0 = above water).
## `density_ratio` is body density over water density: wood (< 1) floats, brass (> 1) sinks.
static func buoyancy_force(depth: float, mass: float, density_ratio: float, gravity: float = 9.8) -> float:
	if depth <= 0.0 or density_ratio <= 0.0:
		return 0.0
	var submerged := clampf(depth / 0.2, 0.0, 1.0)
	return mass * gravity * (1.0 / density_ratio) * submerged


## Water surface height with a gentle travelling swell, so floating props bob.
static func surface_height(x: float, z: float, time: float) -> float:
	return WATER_SURFACE + sin(time * 1.6 + x * 0.55 + z * 0.35) * 0.04


## Retire when too old, or after sleeping for a while (it has stopped moving, so the eye no longer needs it).
static func should_retire(age: float, asleep_for: float) -> bool:
	return age >= LIFETIME or asleep_for >= SLEEP_RETIRE


## Scale (1 -> 0) of a body that has been retiring for `t` seconds.
static func shrink_scale(t: float) -> float:
	return clampf(1.0 - t / SHRINK, 0.0, 1.0)


## Heights of a GROUND_SIZE x GROUND_SIZE grid centred on (cx, cz), absolute y.
static func ground_heights(cx: float, cz: float, height_at: Callable) -> PackedFloat32Array:
	var data := PackedFloat32Array()
	var half := (GROUND_SIZE - 1) / 2
	for j in GROUND_SIZE:
		for i in GROUND_SIZE:
			data.append(float(height_at.call(floorf(cx) + i - half, floorf(cz) + j - half)))
	return data


func setup(height_at: Callable, is_water: Callable) -> void:
	_height_at = height_at
	_is_water = is_water
	_wood_material = StandardMaterial3D.new()
	_wood_material.albedo_color = Color(0.46, 0.31, 0.17)
	_wood_material.roughness = 0.9
	_brass_material = StandardMaterial3D.new()
	_brass_material.albedo_color = Color(0.82, 0.62, 0.22)
	_brass_material.metallic = 0.9
	_brass_material.roughness = 0.35


func active_count() -> int:
	return _bodies.size()


## The local camera/player location controls COSMETIC debris simulation only.
## Missing or invalid viewer data preserves the prior full-simulation behavior.
func set_viewer_position(at: Vector3) -> void:
	_viewer_valid = at.is_finite()
	if _viewer_valid:
		_viewer_position = at
	else:
		# An invalid/missing viewer must restore legacy full simulation.
		# Otherwise a body frozen on the last valid frame could never wake.
		for body in _bodies:
			if int(body.get_meta("sim_lod", 0)) == 1:
				body.freeze = false
				body.sleeping = false
				body.set_meta("sim_lod", 0)


func _within_relevance(at: Vector3, padding: float = 0.0) -> bool:
	if not _viewer_valid:
		return true
	var limit: float = RETIRE_RADIUS + padding
	return _viewer_position.distance_squared_to(at) <= limit * limit


func _classify_lod(distance_m: float, in_water: bool, previous_tier: int) -> int:
	if _native_lod != null and _native_lod.has_method("classify"):
		return int(_native_lod.call("classify", distance_m, in_water,
			previous_tier, SIMULATE_RADIUS, RETIRE_RADIUS, SIMULATION_HYSTERESIS))
	return DebrisLOD.classify(distance_m, in_water, previous_tier,
		SIMULATE_RADIUS, RETIRE_RADIUS, SIMULATION_HYSTERESIS)


func _ensure_ground(at: Vector3) -> void:
	if not _height_at.is_valid():
		return
	var key := Vector2(floorf(at.x), floorf(at.z))
	if _ground != null and key.distance_to(_ground_center) < RECENTER:
		return
	if _ground == null:
		_ground = StaticBody3D.new()
		_ground.name = "DebrisGround"
		_ground.collision_layer = LAYER
		_ground.collision_mask = 0
		var shape := HeightMapShape3D.new()
		shape.map_width = GROUND_SIZE
		shape.map_depth = GROUND_SIZE
		var collider := CollisionShape3D.new()
		collider.shape = shape
		_ground.add_child(collider)
		add_child(_ground)
	((_ground.get_child(0) as CollisionShape3D).shape as HeightMapShape3D).map_data = \
		ground_heights(key.x, key.y, _height_at)
	_ground.position = Vector3(key.x, 0.0, key.y)
	_ground_center = key
	# Anything now outside the patch would fall forever: recycle it.
	var half := float(GROUND_SIZE - 1) * 0.5 - 0.5
	for body in _bodies.duplicate():
		var p: Vector3 = body.position
		if absf(p.x - key.x) > half or absf(p.z - key.y) > half:
			_retire(body)


func _acquire(kind: String, size: Vector3) -> RigidBody3D:
	var cap := total_budget(quality_level())
	if cap <= 0:
		return null
	while _bodies.size() >= cap:
		_retire(_bodies[0])
	var body: RigidBody3D
	if not _free.is_empty():
		body = _free.pop_back()
	else:
		body = RigidBody3D.new()
		body.collision_layer = LAYER
		body.collision_mask = LAYER
		body.continuous_cd = true
		body.can_sleep = true
		body.add_child(CollisionShape3D.new())
		body.add_child(MeshInstance3D.new())
		add_child(body)
	var box := BoxShape3D.new()
	var mesh_instance := body.get_child(1) as MeshInstance3D
	if kind == "casing":
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.012
		cylinder.bottom_radius = 0.012
		cylinder.height = 0.05
		cylinder.radial_segments = 6
		cylinder.rings = 1
		mesh_instance.mesh = cylinder
		mesh_instance.material_override = _brass_material
		box.size = Vector3(0.025, 0.05, 0.025)
		body.mass = 0.02
	else:
		var plank := BoxMesh.new()
		plank.size = size
		mesh_instance.mesh = plank
		mesh_instance.material_override = _wood_material
		box.size = size
		body.mass = maxf(size.x * size.y * size.z * 600.0, 0.2)
	(body.get_child(0) as CollisionShape3D).shape = box
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.scale = Vector3.ONE
	body.set_meta("kind", kind)
	body.set_meta("born", _clock)
	body.set_meta("asleep", 0.0)
	body.set_meta("retiring", -1.0)
	body.set_meta("sim_lod", 0)
	body.set_meta("blast_wake_until", 0.0)
	body.visible = true
	body.freeze = false
	body.sleeping = false
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.process_mode = Node.PROCESS_MODE_INHERIT
	_bodies.append(body)
	return body


func _retire(body: RigidBody3D) -> void:
	_bodies.erase(body)
	body.visible = false
	body.freeze = true
	body.process_mode = Node.PROCESS_MODE_DISABLED
	body.position = Vector3(0, -1000, 0)
	_free.append(body)


## A destroyed barricade/crate: wood chunks fly out and tumble.
func burst_chunks(at: Vector3, strength: float = 1.0) -> int:
	if not at.is_finite():
		return 0
	var count := chunk_count(quality_level(), strength)
	if count <= 0 or not at.is_finite() or not _within_relevance(at):
		return 0
	_ensure_ground(at)
	var spawned := 0
	for i in count:
		var body := _acquire("chunk", chunk_size(i + _bodies.size()))
		if body == null:
			break
		var angle := randf() * TAU
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		body.position = at + Vector3(dir.x * 0.3, 0.1 + randf() * 0.6, dir.z * 0.3)
		body.rotation = Vector3(randf(), randf(), randf()) * TAU
		body.linear_velocity = dir * (1.5 + randf() * 3.0) + Vector3.UP * (2.0 + randf() * 3.0)
		body.angular_velocity = Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 14.0
		spawned += 1
	return spawned


## An ejected brass casing flying out to the right of `facing_yaw`.
func eject_casing(at: Vector3, facing_yaw: float) -> bool:
	var level := quality_level()
	if casing_budget(level) <= 0 or not at.is_finite() or not _within_relevance(at):
		return false
	var live := 0
	for body in _bodies:
		if body.get_meta("kind") == "casing":
			live += 1
	if live >= casing_budget(level):
		return false
	_ensure_ground(at)
	var casing := _acquire("casing", Vector3.ONE)
	if casing == null:
		return false
	var right := Vector3(cos(facing_yaw), 0.0, -sin(facing_yaw))
	casing.position = at
	casing.linear_velocity = right * (1.6 + randf() * 0.8) + Vector3.UP * (1.8 + randf() * 0.6)
	casing.angular_velocity = Vector3(randf(), randf(), randf()) * 20.0
	return true


## Queue a radial impulse field; applied on the next physics step to debris and ragdoll bones in range.
## The one place blasts push debris and ragdolls (physics_world_fx feeds it): the engine's
## RadialForceField3D when compiled in, else the script sphere query below — never both.
func blast(center: Vector3, radius: float, impulse: float) -> void:
	if not center.is_finite() or not is_finite(radius) or not is_finite(impulse) \
			or radius <= 0.0 or impulse <= 0.0:
		return
	# Do not spend overlap/raycast work for entirely irrelevant explosions.
	# The padding keeps any blast sphere that reaches the active area.
	if not _within_relevance(center, radius):
		return
	# A frozen rigid body ignores an otherwise valid blast field. Wake the
	# affected cosmetic pieces, then grant a short physics grace period.
	var radius_squared: float = radius * radius
	for body in _bodies:
		if body.freeze and body.global_position.distance_squared_to(center) <= radius_squared:
			body.freeze = false
			body.sleeping = false
			body.set_meta("sim_lod", 0)
			body.set_meta("blast_wake_until", _clock + BLAST_WAKE_GRACE)
	if is_inside_tree() \
			and EngineFeatures.radial_push(self, center, radius, impulse, 0.6, LAYER | Ragdoll.LAYER,
				BLAST_WALL_MASK, BLAST_WALL_ATTENUATION, true, 2):
		return
	if radius > 0.0 and impulse > 0.0 and center.is_finite() and _blasts.size() < 8:
		_blasts.append([center, radius, impulse])


func _apply_blasts() -> void:
	if _blasts.is_empty():
		return
	var space := get_world_3d().direct_space_state
	for blast_data in _blasts:
		var occlusion_rays := 0
		var seen: Dictionary = {} # Multiple collision shapes must not push one body twice.
		var center: Vector3 = blast_data[0]
		var radius: float = blast_data[1]
		var impulse: float = blast_data[2]
		var sphere := SphereShape3D.new()
		sphere.radius = radius
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = sphere
		query.transform = Transform3D(Basis(), center)
		query.collision_mask = LAYER | Ragdoll.LAYER
		for hit in space.intersect_shape(query, 48):
			var collider: Object = hit["collider"]
			if not (collider is RigidBody3D or collider is PhysicalBone3D):
				continue
			var object_id: int = collider.get_instance_id()
			if seen.has(object_id):
				continue
			seen[object_id] = true
			var offset: Vector3 = (collider as Node3D).global_position - center
			var push := falloff(offset.length(), radius)
			if push <= 0.0:
				continue
			# Mirror the native field: ray-test world collision separately
			# from the debris/ragdoll overlap mask, using one conservative
			# 24-query budget per explosion. Exclude the receiving body.
			var shielding := 1.0
			if offset.length_squared() > 0.000001 and BLAST_WALL_MASK != 0:
				var blocked := true
				if occlusion_rays < BLAST_MAX_OCCLUSION_RAYS:
					var wall_ray := PhysicsRayQueryParameters3D.create(
						center, (collider as Node3D).global_position, BLAST_WALL_MASK)
					wall_ray.collide_with_areas = false
					var excluded: Array[RID] = [(collider as PhysicsBody3D).get_rid()]
					wall_ray.exclude = excluded
					blocked = not space.intersect_ray(wall_ray).is_empty()
					occlusion_rays += 1
				shielding = blast_shielding(blocked)
			if shielding <= 0.0:
				continue
			var outward := offset.normalized() if offset.length_squared() > 0.000001 else Vector3.UP
			var direction := (outward + Vector3.UP * 0.6).normalized()
			if collider is RigidBody3D:
				var rigid := collider as RigidBody3D
				rigid.sleeping = false
				rigid.apply_central_impulse(direction * blast_impulse_magnitude(impulse, push * shielding, rigid.mass))
				rigid.set_meta("asleep", 0.0)
			else:
				var bone := collider as PhysicalBone3D
				bone.apply_central_impulse(direction * blast_impulse_magnitude(impulse, push * shielding, bone.mass))
	_blasts.clear()


func _physics_process(delta: float) -> void:
	_clock += delta
	_apply_blasts()
	# Reverse iteration permits retiring/recycling bodies without making a
	# new duplicate array every physics frame (up to 72 rigid bodies).
	for index in range(_bodies.size() - 1, -1, -1):
		var body: RigidBody3D = _bodies[index]
		var kind: String = body.get_meta("kind")
		var in_water: bool = _is_water.is_valid() and _is_water.call(body.position.x, body.position.z)
		if _viewer_valid:
			var previous_lod: int = int(body.get_meta("sim_lod", 0))
			var distance: float = _viewer_position.distance_to(body.global_position)
			var tier: int = _classify_lod(distance, in_water, previous_lod)
			if tier == 1 and _clock < float(body.get_meta("blast_wake_until", 0.0)):
				tier = 0
			if tier == 2:
				_retire(body)
				continue
			if tier == 1 and previous_lod != 1:
				# Keep the last visible pose but remove distant cosmetic bodies
				# from active rigid-body integration until the viewer comes back.
				body.freeze = true
				body.set_meta("sim_lod", 1)
			elif tier == 0 and previous_lod == 1:
				body.freeze = false
				body.sleeping = false
				body.set_meta("sim_lod", 0)
		if in_water:
			# Wood floats and bobs, casings sink.
			var depth: float = surface_height(body.position.x, body.position.z, _clock) - body.position.y
			body.apply_central_force(Vector3.UP * buoyancy_force(depth, body.mass, 0.6 if kind == "chunk" else 8.5))
			if depth > 0.0:
				body.linear_velocity *= 1.0 - minf(delta * 3.0, 0.5)
				body.angular_velocity *= 1.0 - minf(delta * 2.0, 0.5)
		var asleep := (float(body.get_meta("asleep")) + delta) if body.sleeping else 0.0
		body.set_meta("asleep", asleep)
		var age := _clock - float(body.get_meta("born"))
		var retiring := float(body.get_meta("retiring"))
		if retiring < 0.0:
			if age >= LIFETIME or (asleep >= SLEEP_RETIRE and not in_water):
				body.set_meta("retiring", 0.0)
		else:
			retiring += delta
			body.set_meta("retiring", retiring)
			(body.get_child(1) as MeshInstance3D).scale = Vector3.ONE * shrink_scale(retiring)
			if retiring >= SHRINK:
				_retire(body)

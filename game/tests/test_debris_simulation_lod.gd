extends RefCounted
## Native vs stock-Godot Chaos-style physics LOD and real cosmetic bodies.
const LOD = preload("res://scripts/client/debris_simulation_lod.gd")
const Debris = preload("res://scripts/client/physics_debris.gd")
const PhysicsFX = preload("res://scripts/client/physics_world_fx.gd")


static func _make_body() -> RigidBody3D:
	var body := RigidBody3D.new()
	body.add_child(CollisionShape3D.new())
	body.add_child(MeshInstance3D.new())
	body.position = Vector3(30, 0, 0)
	body.set_meta("kind", "chunk")
	body.set_meta("born", 0.0)
	body.set_meta("asleep", 0.0)
	body.set_meta("retiring", -1.0)
	body.set_meta("sim_lod", 0)
	return body


func run(t) -> void:
	t.current = "pure distance LOD hysteresis and water constraints"
	t.eq(LOD.classify(0.0, false, 0), 0, "near debris always simulates")
	t.eq(LOD.classify(25.99, false, 0), 0, "below outer band stays awake")
	t.eq(LOD.classify(26.0, false, 0), 1, "crossing upper band freezes")
	t.eq(LOD.classify(24.0, false, 1), 1, "return to band does not thrash")
	t.eq(LOD.classify(22.01, false, 1), 1, "just outside lower band remains frozen")
	t.eq(LOD.classify(22.0, false, 1), 0, "approaching viewer reactivates")
	t.eq(LOD.classify(55.99, false, 1), 1, "frozen visuals remain until far boundary")
	t.eq(LOD.classify(56.0, false, 1), 2, "far away bodies retire from pool")
	t.eq(LOD.classify(30.0, true, 1), 0, "floating fragments cannot stay frozen")
	t.eq(LOD.classify(56.0, true, 0), 2, "water does not keep invisible bodies forever")
	for bad in [NAN, INF, -1.0, 10000001.0]:
		t.eq(LOD.classify(bad, false, 0), -1, "bad distance cannot change a rigid body")
	t.eq(LOD.classify(10.0, false, 2), -1, "invalid prior state rejected")
	t.eq(LOD.classify(10.0, false, 0, 24.0, 26.0, 2.0), -1,
		"invalid non-separated radii rejected")
	t.eq(LOD.classify(10.0, false, 0, 24.0, 56.0, NAN), -1,
		"invalid hysteresis rejected")

	t.current = "native and portable LOD decisions match under crowd movement"
	var native: Object = null
	if ClassDB.class_exists("DebrisSimulationLOD3D"):
		native = ClassDB.instantiate("DebrisSimulationLOD3D")
		t.check(native != null and native.has_method("classify"),
			"custom engine exports native Chaos-style LOD")
	var tiers: Array[int] = [0, 1]
	for frame in 480:
		var dist: float = 24.0 + sin(float(frame) * 0.11) * 4.0
		for previous in tiers:
			for water in [false, true]:
				var gd: int = LOD.classify(dist, water, previous)
				if native != null:
					t.eq(int(native.call("classify", dist, water, previous,
						24.0, 56.0, 2.0)), gd, "native/script parity across movement")
	for previous in tiers:
		var state: int = previous
		for frame in 180:
			state = LOD.classify(24.0 + sin(float(frame) * 0.21) * 1.5,
				false, state)
			t.eq(state, previous, "hysteresis prevents simulation toggle thrash")

	t.current = "actual pooled rigid body freezes, unfreezes and recycles"
	var debris := Debris.new()
	var body := _make_body()
	debris.add_child(body)
	debris._bodies.append(body)
	debris.set_viewer_position(Vector3.ZERO)
	debris._physics_process(1.0 / 60.0)
	t.check(body.freeze, "far body is removed from active physics integration")
	t.eq(body.get_meta("sim_lod"), 1, "frozen body remembers its tier")
	t.eq(debris.active_count(), 1, "frozen mesh remains visible in the pool")
	debris.blast(Vector3(30, 0, 0), 5.0, 4.0)
	t.check(not body.freeze, "nearby blast wakes frozen cosmetic debris")
	# Isolated headless node has no physics world; avoid executing ray queries.
	debris._blasts.clear()
	debris._physics_process(1.0 / 60.0)
	t.check(not body.freeze, "short grace preserves visible explosion motion")
	debris._clock += Debris.BLAST_WAKE_GRACE
	debris._physics_process(1.0 / 60.0)
	t.check(body.freeze, "after blast grace the distance LOD freezes again")
	debris.set_viewer_position(Vector3(7, 0, 0))
	debris._physics_process(1.0 / 60.0)
	t.check(body.freeze, "approach inside hysteresis holds frozen state")
	debris.set_viewer_position(Vector3(9, 0, 0))
	debris._physics_process(1.0 / 60.0)
	t.check(not body.freeze, "near viewer reactivates the real rigid body")
	t.eq(body.get_meta("sim_lod"), 0, "reactivated body updates pool metadata")
	debris.set_viewer_position(Vector3.ZERO)
	debris._physics_process(1.0 / 60.0)
	t.check(body.freeze, "viewer moving away can freeze again")
	debris.set_viewer_position(Vector3.INF)
	t.check(not body.freeze and body.get_meta("sim_lod") == 0,
		"invalid viewer restores full physical simulation immediately")
	debris.set_viewer_position(Vector3(-40, 0, 0))
	debris._physics_process(1.0 / 60.0)
	t.eq(debris.active_count(), 0, "far debris leaves the live physics pool")
	t.eq(debris._free.size(), 1, "retired rigid body is recycled, not deleted")
	t.check(not body.visible, "far retired mesh no longer submits rendering")
	t.check(not debris._within_relevance(Vector3(1000, 0, 0)),
		"far events are culled before spawning extra physics")
	t.eq(debris.burst_chunks(Vector3(1000, 0, 0)), 0,
		"real distant wood destruction does not allocate bodies")
	t.eq(debris.active_count(), 0,
		"far burst leaves the recycled pool untouched")
	debris.set_viewer_position(Vector3.INF)
	t.check(debris._within_relevance(Vector3(1000, 0, 0)),
		"missing/invalid viewer preserves legacy behavior")
	debris.free()

	t.current = "viewer wiring reaches networked live physics-world visual effects"
	var fx: String = (PhysicsFX as Script).source_code
	t.check(fx.contains('debris.call("set_viewer_position", player)'),
		"game frame updates the location for optional Chaos LOD")
	var source: String = (Debris as Script).source_code
	t.check(source.contains('EngineFeatures.make("DebrisSimulationLOD3D")'),
		"native C++ path is used in actual rigid-body loop")
	t.check(source.contains("range(_bodies.size() - 1, -1, -1)"),
		"per-frame rigid-body loop avoids copying all active bodies")
	t.check(source.contains('body.freeze = true') and
		source.contains('body.freeze = false') and source.contains("_retire(body)"),
		"real RigidBody3D lifecycle implements all three LOD states")
	t.check(source.contains("if in_water:") and
		source.contains("buoyancy_force(depth, body.mass,"),
		"existing water buoyancy stays active in nearby simulation")

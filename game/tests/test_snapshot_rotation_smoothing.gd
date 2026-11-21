extends RefCounted
## Native/stock-Godot UE-style simulated proxy yaw smoothing, no prediction.
const Smooth = preload("res://scripts/client/network_snapshot_smoothing.gd")
const EntityView = preload("res://scripts/client/entity_view.gd")
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")


func run(t) -> void:
	t.current = "single snapshot pair retains legacy linear turning"
	var older := [1.0, Vector3.ZERO, 0.0]
	var newer := [1.1, Vector3(1, 0, 0), 1.0]
	for i in 51:
		var fraction: float = float(i) / 50.0
		t.near(Smooth.sample_yaw([], older, newer, [], fraction),
			lerp_angle(0.0, 1.0, fraction), 0.0000001,
			"two-point yaw is still shortest-arc linear")
	t.near(Smooth.interpolate_yaw(0.2, 0.9, 7.0, 7.0, 0.1, 0.5),
		0.55, 0.0000001, "equal tangents exactly match linear interpolation")
	t.near(Smooth.interpolate_yaw(0.2, 0.9, 7.0, 7.0, 0.1, -1.0),
		0.2, 0.0000001, "no backward extrapolation")
	t.near(Smooth.interpolate_yaw(0.2, 0.9, 7.0, 7.0, 0.1, 9.0),
		0.9, 0.0000001, "no forward extrapolation")

	t.current = "neighbor snapshots add bounded angular smoothness"
	var previous := [0.9, Vector3.ZERO, -0.1]
	var following := [1.2, Vector3.ZERO, 1.8]
	var refined: float = Smooth.sample_yaw(previous, older, newer, following, 0.5)
	t.check(refined > 0.0 and refined < 1.0 and absf(refined - 0.5) > 0.01,
		"angular acceleration reshapes midpoint without overshooting")
	for i in 101:
		var fraction: float = float(i) / 100.0
		var yaw: float = Smooth.sample_yaw(previous, older, newer, following,
			fraction)
		t.check(yaw >= 0.0 and yaw <= 1.0,
			"cubic interpolation stays within server-authoritative turn")

	t.current = "179 to -179 degrees crosses seam without a fake full revolution"
	var from_yaw: float = deg_to_rad(179.0)
	var to_yaw: float = deg_to_rad(-179.0)
	var last_yaw: float = from_yaw
	for i in 101:
		var fraction: float = float(i) / 100.0
		var angle: float = Smooth.interpolate_yaw(
			from_yaw, to_yaw, 20.0, -30.0, 0.1, fraction)
		t.check(angle >= from_yaw - 0.000001 and
			angle <= from_yaw + deg_to_rad(2.0) + 0.000001,
			"shortest arc stays inside a 2 degree envelope")
		t.check(angle >= last_yaw - 0.000001,
			"yaw is continuous across the full render interpolation interval")
		last_yaw = angle
	t.near(last_yaw, from_yaw + deg_to_rad(2.0), 0.000001,
		"terminal value is authoritative modulo 2 pi")
	t.near(Smooth.interpolate_yaw(0.0, 3.0, 50.0, -50.0, 0.1, 0.5),
		1.5, 0.000001, "abrupt turns retain safe linear path")
	t.near(Smooth.interpolate_yaw(0.0, 1.0, 10.0, 10.0, 1.0, 0.5),
		0.5, 0.000001, "long packet gaps cannot create extrapolated spinning")

	t.current = "bad network timestamps and angular velocities fail safely"
	t.near(Smooth.interpolate_yaw(NAN, 0.7, 1.0, 1.0, 0.1, 0.5),
		0.7, 0.000001, "invalid source uses a valid authoritative target")
	t.near(Smooth.interpolate_yaw(0.7, INF, 1.0, 1.0, 0.1, 0.5),
		0.7, 0.000001, "invalid destination retains previous authority")
	t.near(Smooth.interpolate_yaw(INF, NAN, 1.0, 1.0, 0.1, 0.5),
		0.0, 0.000001, "two invalid endpoints fail to a finite zero angle")
	t.near(Smooth.interpolate_yaw(0.0, 1.0, INF, 1.0, 0.1, 0.5),
		0.5, 0.000001, "invalid angular speed falls back to linear")
	t.near(Smooth.sample_yaw([], older, newer, [], 3.0),
		1.0, 0.000001, "missing future packets hold the latest server yaw")
	t.near(Smooth.sample_yaw([], older, newer, [], -2.0),
		0.0, 0.000001, "render time cannot precede first yaw sample")
	var stale_prev := [1.04, Vector3.ZERO, -2.0]
	var inverted_next := [1.08, Vector3.ZERO, 3.0]
	t.near(Smooth.sample_yaw(stale_prev, older, newer, inverted_next, 0.5),
		0.5, 0.000001,
		"out-of-order neighbor snapshots cannot distort trusted rotation")

	t.current = "Cgame engine and portable script agree across angular input matrix"
	var native: Object = null
	if ClassDB.class_exists("SnapshotRotationSmoothing3D"):
		native = ClassDB.instantiate("SnapshotRotationSmoothing3D")
		t.check(native != null and native.has_method("interpolate_yaw"),
			"native engine exposes the pure yaw smoothing policy")
	for initial_yaw in [0.0, 1.0, -2.0, deg_to_rad(179.0)]:
		for final_yaw in [0.2, -1.0, 2.3, deg_to_rad(-179.0)]:
			for v0 in [-35.0, -5.0, 0.0, 3.0, 40.0]:
				for v1 in [-40.0, 0.0, 5.0, 35.0]:
					for alpha in [0.0, 0.01, 0.25, 0.5, 0.75, 0.99, 1.0]:
						var scripted: float = Smooth.interpolate_yaw(
							initial_yaw, final_yaw, v0, v1, 0.1, alpha)
						t.check(is_finite(scripted),
							"scripted yaw remains finite")
						if native != null:
							var computed: float = float(native.call(
								"interpolate_yaw", initial_yaw, final_yaw,
								v0, v1, 0.1, alpha))
							t.near(computed, scripted, 0.000001,
								"native/script yaw smoothing parity")

	t.current = "actual remote players and infected use native or fallback policy"
	var view := EntityView.new()
	t.eq(view._rotation_smoother != null,
		ClassDB.class_exists("SnapshotRotationSmoothing3D"),
		"live EntityView chooses available native rotation policy")
	var entity_source: String = (EntityView as Script).source_code
	t.check(entity_source.contains("SnapshotSmoothing.sample_yaw("),
		"actual replicated actor sampling uses yaw Hermite")
	t.check(entity_source.contains("SnapshotSmoothing.sample_position("),
		"existing safe translation smoothing is preserved")
	t.check(entity_source.contains("if GraphicsQuality.level() == 0:") and
		entity_source.contains("lerp_angle(float(older[2]), float(newer[2]), k)"),
		"Performance preset retains cheap shortest-arc turning")
	t.check(entity_source.contains("history.clear() # A teleport"),
		"teleports continue to reset history instead of blending positions")
	t.check(entity_source.contains("if _render_time >= float(older[0]):"),
		"missing packets never trigger extrapolation")

	# Execute the real remote-actor _sample() path with four replicated
	# snapshots instead of merely inspecting the source string.
	t.current = "live EntityView interpolates replicated player/zombie turns"
	var prior_quality: int = GraphicsQuality.level()
	GraphicsQuality.set_level(2, false)
	view._history["player:37"] = [previous, older, newer, following]
	view._history["zombie:88"] = [previous, older, newer, following]
	view._render_time = 1.05
	var player_sample: Array = view._sample("player:37")
	var zombie_sample: Array = view._sample("zombie:88")
	t.near(float(player_sample[1]), refined, 0.000001,
		"networked player's real render yaw uses angular Hermite")
	t.near(float(zombie_sample[1]), refined, 0.000001,
		"networked infected's real render yaw uses the same policy")
	GraphicsQuality.set_level(0, false)
	var cheap_sample: Array = view._sample("player:37")
	t.near(float(cheap_sample[1]), 0.5, 0.000001,
		"Performance tier uses cheap linear yaw on real game history")
	GraphicsQuality.set_level(prior_quality, false)
	view.free()

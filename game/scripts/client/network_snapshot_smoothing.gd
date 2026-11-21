extends RefCounted
## Jitter-buffered visual smoothing for replicated players and enemies.
## Endpoints are server-authoritative; no prediction, movement or physics edits.
## Unreal simulated-proxy smoothing + Gaffer Hermite snapshots, bounded to
## prevent curve overshoot at walls, teleport gates and rapid turnarounds.

const TELEPORT_DISTANCE := 8.0
const MAX_SAMPLE_SECONDS := 0.5


## Hermite axis whose endpoint derivatives cannot reverse the server chord.
## Keeping every component inside the endpoint box is critical for collision
## silhouettes, network spikes, stair steps and pathfinding around walls.
static func _axis(a: float, b: float, va: float, vb: float, span: float, t: float) -> float:
	var chord: float = b - a
	if absf(chord) <= 0.00001:
		return a
	var m0: float = chord * clampf(va * span / chord, 0.0, 3.0)
	var m1: float = chord * clampf(vb * span / chord, 0.0, 3.0)
	var t2: float = t * t
	var t3: float = t2 * t
	var result: float = (2.0 * t3 - 3.0 * t2 + 1.0) * a \
		+ (t3 - 2.0 * t2 + t) * m0 \
		+ (-2.0 * t3 + 3.0 * t2) * b + (t3 - t2) * m1
	return clampf(result, minf(a, b), maxf(a, b))


static func hermite(from: Vector3, to: Vector3, v_from: Vector3,
		v_to: Vector3, span: float, alpha: float, host: Node3D = null) -> Vector3:
	# Broken network coordinates must not leak NaNs into the scene tree,
	# culling AABBs or motion vectors. Match the native Node3D guard.
	if not from.is_finite() or not to.is_finite():
		return to if to.is_finite() else (from if from.is_finite() else Vector3.ZERO)
	var t: float = clampf(alpha if is_finite(alpha) else 0.0, 0.0, 1.0)
	if t <= 0.0:
		return from
	if t >= 1.0:
		return to
	if not is_finite(span) or span <= 0.00001 or span > MAX_SAMPLE_SECONDS \
			or from.distance_squared_to(to) > TELEPORT_DISTANCE * TELEPORT_DISTANCE \
			or not v_from.is_finite() or not v_to.is_finite():
		return from.lerp(to, t)
	if host != null and host.has_method("interpolate_network_snapshot"):
		return host.call("interpolate_network_snapshot", from, to, v_from, v_to, span, t)
	return Vector3(
		_axis(from.x, to.x, v_from.x, v_to.x, span, t),
		_axis(from.y, to.y, v_from.y, v_to.y, span, t),
		_axis(from.z, to.z, v_from.z, v_to.z, span, t))


## Each sample is [server_time, Vector3 position, yaw]. Extra samples provide
## better endpoint velocity estimates; two samples reproduce the original
## straight linear path exactly. Never derive tangents across a teleport.
static func sample_position(previous: Array, older: Array, newer: Array,
		following: Array, alpha: float, host: Node3D = null) -> Vector3:
	var from: Vector3 = older[1]
	var to: Vector3 = newer[1]
	var t0: float = float(older[0])
	var t1: float = float(newer[0])
	var span: float = t1 - t0
	if span <= 0.00001:
		return to
	var segment_velocity: Vector3 = (to - from) / span
	var v_from: Vector3 = segment_velocity
	var v_to: Vector3 = segment_velocity
	if previous.size() >= 2:
		var previous_pos: Vector3 = previous[1]
		var earlier_span: float = t1 - float(previous[0])
		if earlier_span > 0.00001 and earlier_span <= MAX_SAMPLE_SECONDS * 3.0 \
				and previous_pos.distance_to(from) <= TELEPORT_DISTANCE:
			v_from = (to - previous_pos) / earlier_span
	if following.size() >= 2:
		var following_pos: Vector3 = following[1]
		var later_span: float = float(following[0]) - t0
		if later_span > 0.00001 and later_span <= MAX_SAMPLE_SECONDS * 3.0 \
				and following_pos.distance_to(to) <= TELEPORT_DISTANCE:
			v_to = (following_pos - from) / later_span
	return hermite(from, to, v_from, v_to, span, alpha, host)


## Shortest arc between two server rotations. Never extrapolates outside the
## authoritative angular span, including the -pi/+pi seam.
static func _yaw_delta(from_yaw: float, to_yaw: float) -> float:
	return wrapf(to_yaw - from_yaw, -PI, PI)


## Pure native policy with stock-Godot mathematical parity. No scene writes.
static func interpolate_yaw(from_yaw: float, to_yaw: float,
		from_angular_velocity: float, to_angular_velocity: float,
		snapshot_span: float, alpha: float, native_policy: Object = null) -> float:
	if native_policy != null and native_policy.has_method("interpolate_yaw"):
		return float(native_policy.call("interpolate_yaw",
			from_yaw, to_yaw, from_angular_velocity,
			to_angular_velocity, snapshot_span, alpha))
	if not is_finite(from_yaw) or absf(from_yaw) > 10000.0:
		return to_yaw if is_finite(to_yaw) and absf(to_yaw) <= 10000.0 else 0.0
	if not is_finite(to_yaw) or absf(to_yaw) > 10000.0:
		return from_yaw
	var k: float = clampf(alpha if is_finite(alpha) else 0.0, 0.0, 1.0)
	var turn: float = _yaw_delta(from_yaw, to_yaw)
	if k <= 0.0 or absf(turn) <= 0.00001:
		return from_yaw
	if k >= 1.0:
		# Equivalent to authoritative yaw modulo TAU without a seam jump.
		return from_yaw + turn
	var linear: float = from_yaw + turn * k
	if not is_finite(snapshot_span) or snapshot_span <= 0.00001 \
			or snapshot_span > MAX_SAMPLE_SECONDS or absf(turn) > 2.4 \
			or not is_finite(from_angular_velocity) \
			or not is_finite(to_angular_velocity) \
			or absf(from_angular_velocity) > 1000.0 \
			or absf(to_angular_velocity) > 1000.0:
		return linear
	var m0: float = turn * clampf(
		from_angular_velocity * snapshot_span / turn, 0.0, 3.0)
	var m1: float = turn * clampf(
		to_angular_velocity * snapshot_span / turn, 0.0, 3.0)
	var k2: float = k * k
	var k3: float = k2 * k
	var offset: float = (k3 - 2.0 * k2 + k) * m0 \
		+ (-2.0 * k3 + 3.0 * k2) * turn + (k3 - k2) * m1
	return from_yaw + clampf(offset, minf(0.0, turn), maxf(0.0, turn))


## Four server snapshots refine the endpoints' angular velocities. Two
## samples retain the original lerp_angle exactly, preserving low-bandwidth
## and freshly spawned actor behavior. Neighbor yaw cannot span teleport
## turns; old/inverted timestamps fail back to safe angular interpolation.
static func sample_yaw(previous: Array, older: Array, newer: Array,
		following: Array, alpha: float, native_policy: Object = null) -> float:
	if older.size() < 3 or newer.size() < 3:
		return 0.0
	var a: float = float(older[2])
	var b: float = float(newer[2])
	if not is_finite(a) or absf(a) > 10000.0 \
			or not is_finite(b) or absf(b) > 10000.0:
		return interpolate_yaw(a, b, 0.0, 0.0, 0.1, alpha, native_policy)
	var t: float = clampf(alpha if is_finite(alpha) else 0.0, 0.0, 1.0)
	var t0: float = float(older[0])
	var t1: float = float(newer[0])
	var span: float = t1 - t0
	var turn: float = _yaw_delta(a, b)
	if not is_finite(span) or span <= 0.00001 or span > MAX_SAMPLE_SECONDS \
			or absf(turn) > 2.4:
		return lerp_angle(a, b, t)
	var v: float = turn / span
	var v0: float = v
	var v1: float = v
	var have_neighbor := false
	if previous.size() >= 3:
		var prev_t: float = float(previous[0])
		var prev_angle: float = float(previous[2])
		var prev_delta: float = _yaw_delta(prev_angle, a) if is_finite(prev_angle) else INF
		var earlier_span: float = t1 - prev_t
		if is_finite(prev_t) and prev_t < t0 \
				and is_finite(earlier_span) and earlier_span > 0.00001 \
				and earlier_span <= MAX_SAMPLE_SECONDS * 3.0 \
				and absf(prev_angle) <= 10000.0 and absf(prev_delta) <= 2.4:
			v0 = (prev_delta + turn) / earlier_span
			have_neighbor = true
	if following.size() >= 3:
		var next_t: float = float(following[0])
		var next_angle: float = float(following[2])
		var next_delta: float = _yaw_delta(b, next_angle) if is_finite(next_angle) else INF
		var later_span: float = next_t - t0
		if is_finite(next_t) and next_t > t1 \
				and is_finite(later_span) and later_span > 0.00001 \
				and later_span <= MAX_SAMPLE_SECONDS * 3.0 \
				and absf(next_angle) <= 10000.0 and absf(next_delta) <= 2.4:
			v1 = (turn + next_delta) / later_span
			have_neighbor = true
	if not have_neighbor:
		return lerp_angle(a, b, t)
	return interpolate_yaw(a, b, v0, v1, span, t, native_policy)

extends RefCounted
## Pure stock-Godot fallback for SpatialSoundEventPolicy.
## Cosmetic-only, does not mutate playback, physics or network state.

static func should_emit(listener: Vector3, source: Vector3,
		previous_source: Vector3, now_seconds: float, last_seconds: float,
		retrigger_seconds: float, merge_radius: float, max_distance: float,
		listener_ready: bool = true) -> bool:
	if not source.is_finite():
		return false
	if not listener_ready or not listener.is_finite():
		return true
	if not is_finite(now_seconds) or not is_finite(last_seconds) \
			or not is_finite(retrigger_seconds) or not is_finite(merge_radius) \
			or not is_finite(max_distance) or now_seconds < 0.0 \
			or now_seconds > 1.0e10 or retrigger_seconds < 0.0 \
			or retrigger_seconds > 2.0 or merge_radius < 0.0 \
			or merge_radius > 100.0 or max_distance < 1.0 \
			or max_distance > 10000.0:
		return true
	var limit: float = max_distance + 2.0
	if listener.distance_squared_to(source) > limit * limit:
		return false
	if retrigger_seconds == 0.0 or last_seconds < 0.0 \
			or last_seconds > now_seconds or not previous_source.is_finite():
		return true
	return not (now_seconds - last_seconds < retrigger_seconds \
		and previous_source.distance_squared_to(source) <= merge_radius * merge_radius)

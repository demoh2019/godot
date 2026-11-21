extends RefCounted
## Predictive mip prefetch for the native TextureStreaming engine module.
## GPU material feedback still selects the visible textures; the streaming
## memory-budget fitter may drop the prefetch during VRAM pressure.
## Only streamed textures are affected; ordinary textures cost nothing extra.

# Ultra opts into one more sharp resident mip when the VRAM fitter permits.
# All premium I/O uploads remain limited to a two-mip improvement step.
const PREFETCH_MIPS := [0, 0, 1, 2]
# Unreal-style safety pool: reserve a little streamed-texture budget for
# transient render targets/materials when the custom native budget is active.
# Performance deliberately has no extra reserve; none in Compatibility.
const SAFETY_MARGIN_PERCENT := [0, 4, 6, 8]


static func prefetch_mips(level: int, method: String) -> int:
	if method != "forward_plus":
		return 0
	return PREFETCH_MIPS[clampi(level, 0, PREFETCH_MIPS.size() - 1)]


## Adaptive prefetch is useful only when Forward+ has speculative detail
## residency. Low tiers and Compatibility keep their previous predictable use.
## The native worker changes only speculative mip prefetch, not visible mip
## feedback or the budget fitter's approved target.
static func adaptive_prefetch_enabled(level: int, method: String) -> bool:
	return method == "forward_plus" and prefetch_mips(level, method) > 0


static func safety_margin_percent(level: int, method: String) -> int:
	if method != "forward_plus":
		return 0
	return SAFETY_MARGIN_PERCENT[clampi(level, 0, SAFETY_MARGIN_PERCENT.size() - 1)]


static func apply(level: int, method: String) -> void:
	# Stock Godot and Compatibility builds must still run this game.
	if not Engine.has_singleton("TextureStreaming"):
		return
	var server: Object = Engine.get_singleton("TextureStreaming")
	if server != null and server.has_method("set_detail_prefetch_mips"):
		server.call("set_detail_prefetch_mips", prefetch_mips(level, method))
	# Feature-detect to support older Cgame binaries and stock Godot.
	if server != null and server.has_method("set_adaptive_detail_prefetch_enabled"):
		server.call("set_adaptive_detail_prefetch_enabled",
			adaptive_prefetch_enabled(level, method))
	# Does nothing on stock Godot or when engine memory fitting is disabled.
	# Settings apply on preset changes; feedback worker reads one atomic byte.
	if server != null and server.has_method("set_safety_margin_percent"):
		server.call("set_safety_margin_percent", safety_margin_percent(level, method))


## Native equivalent of Unreal STAT STREAMING, exposed as real Godot
## Performance monitors. These values are cheap atomic gauges published by
## the texture feedback worker; no object-list traversal on each monitor poll.
## 0 for "TextureStreamingBudgetBytes" means budget fitting is disabled.
## "Pending" counts textures not yet at the fitted mip, not active I/O jobs.
const PROFILER_METRICS := {
	&"Albion/TextureStreamingActive": &"get_streaming_texture_count",
	&"Albion/TextureStreamingPending": &"get_streaming_pending_count",
	&"Albion/TextureStreamingBudgetMipCuts": &"get_streaming_budget_reduction_steps",
	&"Albion/TextureStreamingRequestedBytes": &"get_streaming_requested_bytes",
	&"Albion/TextureStreamingFittedBytes": &"get_streaming_fitted_bytes",
	&"Albion/TextureStreamingBudgetBytes": &"get_streaming_budget_bytes",
	&"Albion/TextureStreamingConfiguredBudgetBytes": &"get_streaming_configured_budget_bytes",
	&"Albion/TextureStreamingSafetyReserveBytes": &"get_streaming_safety_reserve_bytes",
	&"Albion/TextureStreamingResidentBytes": &"get_memory_budget_bytes_used",
}


static func register_profiler_monitors() -> Array[StringName]:
	var registered: Array[StringName] = []
	# Stock Godot, Compatibility renderer and pre-telemetry Cgame binaries
	# must run normally. A registered monitor is removed by online_main.
	if not Engine.has_singleton("TextureStreaming"):
		return registered
	var server: Object = Engine.get_singleton("TextureStreaming")
	if server == null:
		return registered
	for name in PROFILER_METRICS:
		var monitor_name: StringName = StringName(name)
		var method_name: StringName = PROFILER_METRICS[name]
		if server.has_method(method_name) and not Performance.has_custom_monitor(monitor_name):
			Performance.add_custom_monitor(monitor_name, Callable(server, method_name))
			registered.append(monitor_name)
	return registered

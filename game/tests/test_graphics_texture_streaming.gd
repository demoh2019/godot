extends RefCounted
## Cross-layer graphics contract: game quality -> engine mip prefetch.

const Streaming = preload("res://scripts/client/graphics_texture_streaming.gd")
const Quality = preload("res://scripts/client/graphics_quality.gd")


func run(t) -> void:
	t.current = "engine streamed texture prefetch budgets"
	for method in ["gl_compatibility", "mobile", "unknown"]:
		for tier in 4:
			t.eq(Streaming.prefetch_mips(tier, method), 0,
				"non-Forward+ renderer never requests extra mip residency")
	t.eq(Streaming.prefetch_mips(0, "forward_plus"), 0, "Performance keeps minimum memory")
	t.eq(Streaming.prefetch_mips(1, "forward_plus"), 0, "Balanced avoids extra residency")
	t.eq(Streaming.prefetch_mips(2, "forward_plus"), 1, "High prefetches a sharper mip")
	t.eq(Streaming.prefetch_mips(3, "forward_plus"), 2, "Ultra prefetches two sharper mips where memory permits")
	t.eq(Streaming.prefetch_mips(-99, "forward_plus"), 0, "negative quality clamps")
	t.eq(Streaming.prefetch_mips(99, "forward_plus"), 2, "high quality clamps")
	t.current = "Unreal-style VRAM safety pool is isolated from quality defaults"
	for renderer in ["gl_compatibility", "mobile", "unknown"]:
		for level in 4:
			t.eq(Streaming.safety_margin_percent(level, renderer), 0,
				"non-Forward+ never reserves streamed VRAM")
	for level in 4:
		t.eq(Streaming.safety_margin_percent(level, "forward_plus"),
			[0, 4, 6, 8][level],
			"each preset reserves its bounded margin only on Forward+")
	t.eq(Streaming.safety_margin_percent(-9, "forward_plus"), 0,
		"invalid negative tier clamps")
	t.eq(Streaming.safety_margin_percent(50, "forward_plus"), 8,
		"oversized tier clamps to highest approved reserve")
	t.current = "adaptive prefetch only on Forward+ detail tiers"
	for tier in 4:
		t.eq(Streaming.adaptive_prefetch_enabled(tier, "forward_plus"), tier >= 2,
			"High/Ultra opt in and Performance/Balanced stay legacy")
		t.eq(Streaming.adaptive_prefetch_enabled(tier, "gl_compatibility"), false,
			"Compatibility never schedules VRAM prefetch")
		t.eq(Streaming.adaptive_prefetch_enabled(tier, "mobile"), false,
			"non-Forward+ never schedules predictive mip residency")
	Streaming.apply(1, "gl_compatibility")
	Streaming.apply(3, "forward_plus")
	if Engine.has_singleton("TextureStreaming"):
		var server: Object = Engine.get_singleton("TextureStreaming")
		if server != null and server.has_method("get_detail_prefetch_mips"):
			t.eq(int(server.call("get_detail_prefetch_mips")), 2,
				"runtime Ultra quality reaches native streaming worker")
			if server.has_method("is_adaptive_detail_prefetch_enabled"):
				t.eq(bool(server.call("is_adaptive_detail_prefetch_enabled")), true,
					"Ultra enables native memory-pressure admission")
			if server.has_method("get_safety_margin_percent"):
				t.eq(int(server.call("get_safety_margin_percent")), 8,
					"Ultra reserves eight percent of the native texture pool")
				server.call("set_safety_margin_percent", -200)
				t.eq(int(server.call("get_safety_margin_percent")), 0,
					"native setter bounds negative reserve to zero")
				server.call("set_safety_margin_percent", 900)
				t.eq(int(server.call("get_safety_margin_percent")), 25,
					"native setter caps reserve at 25 percent")
				server.call("set_safety_margin_percent", 8)
			if server.has_method("get_streaming_configured_budget_bytes") \
					and server.has_method("get_streaming_safety_reserve_bytes"):
				var raw_pool: int = int(server.call("get_streaming_configured_budget_bytes"))
				var active_pool: int = int(server.call("get_streaming_budget_bytes"))
				var safety_reserve: int = int(server.call("get_streaming_safety_reserve_bytes"))
				t.check(raw_pool >= active_pool and active_pool >= 0,
					"usable streamed pool never exceeds configured pool")
				t.eq(raw_pool - active_pool, safety_reserve,
					"native profiler exposes exact last-pass reserve accounting")
				if server.has_method("get_effective_detail_prefetch_mips"):
					var effective: int = int(server.call("get_effective_detail_prefetch_mips"))
					t.check(effective >= 0 and effective <= 2,
						"effective speculative mip count never exceeds the user cap")
			Streaming.apply(0, "forward_plus")
			t.eq(int(server.call("get_detail_prefetch_mips")), 0,
				"downgrade immediately cancels predictive prefetch")
			if server.has_method("is_adaptive_detail_prefetch_enabled"):
				t.eq(bool(server.call("is_adaptive_detail_prefetch_enabled")), false,
					"downgrade disables native adaptive prefetch")
			if server.has_method("get_safety_margin_percent"):
				t.eq(int(server.call("get_safety_margin_percent")), 0,
					"Performance resets native safety pool to legacy zero")
				if server.has_method("get_effective_detail_prefetch_mips"):
					t.eq(int(server.call("get_effective_detail_prefetch_mips")), 0,
						"no speculative mips left when Performance is selected")
	var quality_source: String = (Quality as Script).source_code
	t.check(quality_source.contains("GraphicsTextureStreaming.apply(_level"),
		"shared graphics quality profile configures engine prefetch")


	t.current = "Unreal STAT STREAMING-style runtime profiler integration"
	var registered: Array[StringName] = Streaming.register_profiler_monitors()
	if Engine.has_singleton("TextureStreaming"):
		var streaming_server: Object = Engine.get_singleton("TextureStreaming")
		t.check(streaming_server != null, "native texture server is available for profiler callbacks")
		if streaming_server != null:
			for monitor_name in Streaming.PROFILER_METRICS:
				var metric_method: StringName = Streaming.PROFILER_METRICS[monitor_name]
				if streaming_server.has_method(metric_method):
					t.check(Performance.has_custom_monitor(monitor_name),
						"live engine metric %s is visible in Godot's profiler" % monitor_name)
					t.check(float(streaming_server.call(metric_method)) >= 0.0,
						"native texture metric %s is a nonnegative gauge" % monitor_name)
				else:
					t.check(not registered.has(monitor_name),
						"older engine skips unsupported metric %s" % monitor_name)
			if streaming_server.has_method("get_streaming_texture_count"):
				t.eq(int(streaming_server.call("get_streaming_texture_count")), 0,
					"fresh headless renderer starts without active streamed textures")
				t.eq(int(streaming_server.call("get_streaming_pending_count")), 0,
					"without GPU material feedback there are no pending mip changes")
				t.eq(int(streaming_server.call("get_streaming_budget_reduction_steps")), 0,
					"no stream feedback means zero budget-induced quality cuts")
			var duplicate: Array[StringName] = Streaming.register_profiler_monitors()
			t.check(duplicate.is_empty(), "registering monitoring twice does not overwrite callbacks")
	else:
		t.check(registered.is_empty(), "stock Godot skips native texture statistics safely")
	for monitor_name in registered:
		t.check(Performance.has_custom_monitor(monitor_name),
			"registered texture metrics use the ordinary Godot Performance API")
		Performance.remove_custom_monitor(monitor_name)
		t.check(not Performance.has_custom_monitor(monitor_name),
			"texture callbacks can be cleaned up on leaving online play")

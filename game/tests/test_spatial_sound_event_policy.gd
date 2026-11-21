extends RefCounted
## Native vs stock Godot spatial sound retrigger policy in real Audio class.
const Emission = preload("res://scripts/client/audio_spatial_emission.gd")
const Audio = preload("res://scripts/client/audio.gd")

func run(t) -> void:
	t.current = "spatially independent duplicate sound concurrency"
	var listener := Vector3.ZERO
	var location := Vector3(8, 0, 0)
	t.check(Emission.should_emit(listener, location, Vector3.INF,
		10.0, -1.0, 0.075, 3.5, 90.0), "first sound at an emitter is eligible")
	t.check(not Emission.should_emit(listener, location, location,
		10.04, 10.0, 0.075, 3.5, 90.0), "same-place duplicate is suppressed")
	t.check(Emission.should_emit(listener, location, location,
		10.08, 10.0, 0.075, 3.5, 90.0), "retrigger window expires")
	t.check(Emission.should_emit(listener, location + Vector3(4, 0, 0), location,
		10.01, 10.0, 0.075, 3.5, 90.0), "distant emitter has independent audio")
	t.check(Emission.should_emit(listener, location, location,
		10.02, 10.0, 0.0, 3.5, 90.0), "combat priority has no retrigger suppression")
	t.check(Emission.should_emit(listener, location, location,
		9.9, 10.0, 0.075, 3.5, 90.0), "time reset does not block future sounds")
	t.check(Emission.should_emit(listener, Vector3(92, 0, 0), location,
		10.0, -1.0, 0.075, 3.5, 90.0), "outer attenuation boundary is conservative")
	t.check(not Emission.should_emit(listener, Vector3(92.1, 0, 0), location,
		10.0, -1.0, 0.075, 3.5, 90.0), "outside max audibility no voice allocated")
	t.check(Emission.should_emit(listener, Vector3(400, 0, 0), location,
		10.0, -1.0, 0.075, 3.5, 90.0, false),
		"scene loading before a listener preserves old sounds")
	t.check(not Emission.should_emit(listener, Vector3.INF, location,
		10.0, -1.0, 0.075, 3.5, 90.0),
		"invalid source position never reaches player transform")
	t.check(Emission.should_emit(listener, location, location,
		10.04, 10.0, NAN, 3.5, 90.0),
		"malformed delay preserves existing sounds")
	t.check(Emission.should_emit(listener, location, location,
		10.04, 10.0, 0.075, -1.0, 90.0),
		"malformed spatial radius fails open")

	t.current = "native and portable gate agree across varied listener and foley"
	var native: Object = null
	if ClassDB.class_exists("SpatialSoundEventPolicy"):
		native = ClassDB.instantiate("SpatialSoundEventPolicy")
		t.check(native != null and native.has_method("should_emit"),
			"native Cgame exposes sound event admission")
	for distance in [0.0, 3.0, 20.0, 89.0, 92.0, 93.0, 130.0]:
		for separate in [0.0, 2.0, 4.0, 100.0]:
			for age in [-1.0, 0.0, 0.01, 0.05, 0.09, 0.25]:
				for margin in [0.0, 0.05, 0.095, 0.15]:
					var source := Vector3(distance, 0, 0)
					var earlier := source + Vector3(separate, 0, 0)
					var before: float = -1.0 if age < 0.0 else 20.0 - age
					var fallback: bool = Emission.should_emit(listener,
						source, earlier, 20.0, before, margin, 3.5, 90.0)
					if native != null:
						t.eq(bool(native.call("should_emit", listener,
							source, earlier, 20.0, before,
							margin, 3.5, 90.0, true)), fallback,
							"native and stock-Godot sound coalescing parity")

	t.current = "actual Albion audio only records successfully admitted foley"
	var live := Audio.new()
	live._listener_ready = true
	live._listener = listener
	t.check(live._should_emit_spatial("enemy_hurt", location, 100.0),
		"first local enemy hit admitted")
	live._record_spatial_emission("enemy_hurt", location, 100.0)
	t.check(not live._should_emit_spatial("enemy_hurt", location, 100.02),
		"repeat hit rejected before AudioStreamPlayer3D allocation")
	t.check(live._should_emit_spatial("enemy_hurt", location + Vector3(4, 0, 0), 100.02),
		"neighboring skirmish remains audible")
	t.check(live._should_emit_spatial("enemy_hurt", location, 100.10),
		"last accepted hit does not block later sound forever")
	for critical in ["blaster", "blaster_repeater", "enemy_destroy", "enemy_attack"]:
		live._record_spatial_emission(critical, location, 100.0)
		t.check(live._should_emit_spatial(critical, location, 100.01),
			"critical gameplay sound is not spatially coalesced")
	t.eq(live._last_spatial_emissions.size(), 1,
		"untracked sound kinds never create unbounded emitter histories")
	live._listener_ready = false
	t.check(live._should_emit_spatial("enemy_hurt", Vector3(500, 0, 0), 100.03),
		"temporarily missing listener never suppresses existing client sound")
	live._listener_ready = true
	t.check(not live._should_emit_spatial("blaster", Vector3(500, 0, 0), 101.0),
		"far weapons are culled only when listener range is known")
	var script: String = (Audio as Script).source_code
	var begin: int = script.find("func play_at(")
	var end: int = script.find("func _physics_process(", begin)
	var section: String = script.substr(begin, end - begin)
	t.check(section.find("_should_emit_spatial(sound_name, position, now)") >= 0
		and section.find("_should_emit_spatial(sound_name, position, now)") < section.find("Assets.sound(sound_name)")
		and section.find("Assets.sound(sound_name)") < section.find("AudioStreamPlayer3D.new()"),
		"real game filters repeated sound before resource lookup and voice allocation")
	t.check(section.find("_record_spatial_emission(sound_name, position, now)")
		> section.find("player.play()"),
		"only emitted audio events enter the short cooldown")
	t.check((Audio as Script).source_code.contains('EngineFeatures.make("SpatialSoundEventPolicy")'),
		"real game tries native policy with script fallback")
	live.free()

extends Node
## Sound: positional effects for what the server announces, footsteps and ambience for the local player.

const Assets = preload("res://scripts/client/assets.gd")
const Defs = preload("res://scripts/shared/defs.gd")
const ReverbZones = preload("res://scripts/client/reverb_zones.gd")
const AudioMix = preload("res://scripts/client/audio_mix.gd")
const AudioSurfaces = preload("res://scripts/client/audio_surfaces.gd")
const AudioVoices = preload("res://scripts/client/audio_voices.gd")
const AudioSpatial = preload("res://scripts/client/audio_spatial.gd")
const AudioEmission = preload("res://scripts/client/audio_spatial_emission.gd")
const AudioDucking = preload("res://scripts/client/audio_ducking.gd")
const AudioMixSnapshots = preload("res://scripts/client/audio_mix_snapshots.gd")
const AudioAmbient = preload("res://scripts/client/audio_ambient.gd")
const EngineFeatures = preload("res://scripts/client/engine_features.gd")
## Optional engine SoundConcurrencyManager (null on a binary without the gameplay_fx module).
const CONCURRENCY_GROUPS := {"enemy_hurt": 4, "coin": 3, "blaster": 4, "blaster_repeater": 4, "break": 3}
# Coalesce only low-priority repeated local foley; never suppress shots,
# kill confirmation, elite warning, dialogue or music.
const SPATIAL_RETRIGGER := {"enemy_hurt": 0.075, "break": 0.095, "coin": 0.09}
const SPATIAL_MERGE_RADIUS := 3.5
const SPATIAL_MAX_DISTANCE := 90.0
var _concurrency: Node = null
var _concurrency_tried := false
var _native_voice_admission: Object = null
var _native_spatial_emission: Object = null
var _last_spatial_emissions: Dictionary = {} # Only the three fixed sound names.
var _listener_ready: bool = false
var _spatial_emission_rejections: int = 0
var _voice_hold_rejections: int = 0
var _sfx_bus := -1
var _sfx_lowpass := -1
var _rain: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _voices: Array = [] # Active 3D sources, including bounded obstacle probes.
# Unreal-style sound obstruction checks: only static geometry on layer 1,
# no per-frame physics casts for every active sound.
const OBSTRUCTION_RAYS_PER_TICK := 3
const OBSTRUCTION_RECHECK_SECONDS := 0.25
const OBSTRUCTION_GEOMETRY_MASK := 1
var _obstruction_clock := 0.0
var _listener := Vector3.ZERO
var _ground := Callable()
var _humidity := 0.0
var _duck := 0.0
var _duck_sources: Dictionary = {} # Old binaries: independent event holds in GDScript.
var _native_duck: Object = null # Native AudioDuckMix, a data-only mixer.
var _native_mix_snapshots: Object = null # Unreal Control Bus Mix-style layered profiles.
var _script_mix_snapshots: Dictionary = {} # Older Cgame/stock Godot parity.
var _mix_zone: String = "" # Only change zone mix when the listener moves zones.
var _storm_mix_active: bool = false
var _surface := "grass"
var _cutoff := AudioSpatial.OPEN_CUTOFF

var _ambience: AudioStreamPlayer
var _steps: AudioStreamPlayer
var _footsteps_wanted := false
var enabled := true

# Music (Fantasy RPG Music Vol. 2, imported into assets/packs/music by tools/import_downloads.sh; silent without it).
# One AudioStreamInteractive (the engine's adaptive music) holds a clip per mood, calm by day, eerie at night, drums
# while fighting, and crossfades between them itself when the mood changes.
const MUSIC := {
	"day": ["Light Ambient 1 (Loop)", "Light Ambient 2 (Loop)", "Light Ambient 3 (Loop)"],
	"night": ["Night Ambient 2 (Loop)", "Night Ambient 3 (Loop)"],
	"combat": ["Action 1 (Loop)", "Action 2 (Loop)"],
}
const MUSIC_DB := -17.0
const COMBAT_SECONDS := 9.0 # Fighting music keeps going this long after the last blow.
var _music: AudioStreamPlayer
var _mood := ""
var _daylight := 1.0
var _combat_left := 0.0


func _ready() -> void:
	AudioMix.ensure_buses()
	_sfx_bus = ReverbZones.ensure_bus()
	_sfx_lowpass = AudioMix.ensure_lowpass(ReverbZones.BUS)
	AudioMix.load_all()
	_native_duck = EngineFeatures.make("AudioDuckMix")
	_native_mix_snapshots = EngineFeatures.make("AudioMixSnapshotController")
	_native_voice_admission = EngineFeatures.make("AudioVoiceAdmissionPlanner")
	_native_spatial_emission = EngineFeatures.make("SpatialSoundEventPolicy")
	_ambience = AudioStreamPlayer.new()
	_ambience.bus = "Ambience"
	_ambience.stream = Assets.sound("ambience")
	_ambience.volume_db = -22.0
	add_child(_ambience)
	_steps = AudioStreamPlayer.new()
	_steps.stream = Assets.sound("walking")
	_steps.volume_db = -14.0
	_steps.bus = ReverbZones.BUS
	add_child(_steps)
	if _ambience.stream is AudioStreamOggVorbis:
		(_ambience.stream as AudioStreamOggVorbis).loop = true
	if _steps.stream is AudioStreamOggVorbis:
		(_steps.stream as AudioStreamOggVorbis).loop = true
	_ambience.play()
	_rain = _noise_loop(0.0, 7)
	_wind = _noise_loop(0.93, 11)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	_music.volume_db = MUSIC_DB
	add_child(_music)
	var adaptive := _adaptive_music()
	if adaptive != null:
		_music.stream = adaptive


## A silent looping generated-noise player on the Ambience bus (rain hiss / wind rumble).
func _noise_loop(smooth: float, noise_seed: int) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = AudioAmbient.noise_stream(2.0, smooth, noise_seed)
	player.bus = "Ambience"
	player.volume_db = -80.0
	add_child(player)
	player.play()
	return player


## The day, night and combat clips (one track each, picked at random), with a crossfade from any clip to any other:
## two seconds between calm moods, one into a fight.
func _adaptive_music() -> AudioStreamInteractive:
	var moods: Array = MUSIC.keys()
	var music := AudioStreamInteractive.new()
	music.clip_count = moods.size()
	for i in moods.size():
		var tracks: Array = MUSIC[moods[i]]
		var stream := music_track(String(tracks[randi() % tracks.size()]))
		if stream == null:
			return null
		stream.bpm = 60.0 # So a beat is a second for the fade lengths below.
		music.set_clip_name(i, moods[i])
		music.set_clip_stream(i, stream)
	music.add_transition(AudioStreamInteractive.CLIP_ANY, AudioStreamInteractive.CLIP_ANY,
		AudioStreamInteractive.TRANSITION_FROM_TIME_IMMEDIATE, AudioStreamInteractive.TRANSITION_TO_TIME_START,
		AudioStreamInteractive.FADE_CROSS, 2.0)
	var combat: int = moods.find("combat")
	music.add_transition(AudioStreamInteractive.CLIP_ANY, combat,
		AudioStreamInteractive.TRANSITION_FROM_TIME_IMMEDIATE, AudioStreamInteractive.TRANSITION_TO_TIME_START,
		AudioStreamInteractive.FADE_CROSS, 1.0)
	music.initial_clip = moods.find("day")
	return music


static func music_track(track: String) -> AudioStream:
	var path := Assets.PACKS + "music/" + track + ".mp3"
	if not ResourceLoader.exists(path):
		return null
	var stream := load(path) as AudioStreamMP3
	if stream != null:
		stream.loop = true
	return stream


## Called every frame with the light level; picks the mood and lets the adaptive stream fade to it.
func update_music(daylight: float, delta: float) -> void:
	_daylight = daylight
	_combat_left = maxf(_combat_left - delta, 0.0)
	if _music.stream == null:
		return
	if not enabled:
		_music.stop()
		_mood = ""
		return
	var mood := "combat" if _combat_left > 0.0 else ("day" if _daylight > 0.3 else "night")
	if not _music.playing:
		_music.play()
		_mood = ""
	if mood != _mood:
		_mood = mood
		var playback := _music.get_stream_playback() as AudioStreamPlaybackInteractive
		if playback != null:
			playback.switch_to_clip_by_name(mood)


## A short musical phrase over everything (death, a level gained, a victory). Silent without the music pack.
func play_sting(track: String, volume_db: float = -9.0) -> void:
	if not enabled:
		return
	var path := Assets.PACKS + "music/" + track + ".mp3"
	if not ResourceLoader.exists(path):
		return
	var player := AudioStreamPlayer.new()
	player.stream = load(path)
	player.volume_db = volume_db
	player.bus = "Music"
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


func mark_combat() -> void:
	_combat_left = COMBAT_SECONDS
	# A short Unreal Control Bus Mix-style combat focus stage reduces
	# ambient masking of important attack cues. Repeated hits extend its
	# life without resetting the existing fade; user sliders still apply.
	_activate_timed_mix_snapshot("Combat.Focus",
		{"Ambience": -3.0, "Music": -1.0}, 0.15, COMBAT_SECONDS, 1.5)


func set_footsteps(active: bool) -> void:
	if active == _footsteps_wanted:
		return
	_footsteps_wanted = active
	if active:
		_steps.play()
	else:
		_steps.stop()


## Gore foley (CC0, assets/gore): wet flesh hits and bone cracks, with pitch variation.
const FLESH := [preload("res://assets/gore/flesh_1.ogg"), preload("res://assets/gore/flesh_2.ogg"), preload("res://assets/gore/flesh_3.ogg")]
const BONE := [preload("res://assets/gore/bone_break_1.ogg"), preload("res://assets/gore/bone_break_2.ogg"),
	preload("res://assets/gore/bone_break_3.ogg"), preload("res://assets/gore/bone_break_4.ogg")]


func play_gore(bone: bool, position: Vector3, volume_db: float = -6.0) -> void:
	if not enabled:
		return
	var pool: Array = BONE if bone else FLESH
	var player := AudioStreamPlayer3D.new()
	player.stream = pool[randi() % pool.size()]
	player.volume_db = volume_db
	player.pitch_scale = randf_range(0.88, 1.12)
	player.unit_size = 10.0
	player.max_distance = 60.0
	player.bus = ReverbZones.BUS
	add_child(player)
	player.global_position = position
	player.play()
	player.finished.connect(player.queue_free)


## Native anti-thrashing planner when available. Older engine builds use
## the equivalent GDScript policy rather than an unprotected legacy API.
func _choose_voice_victim(snapshot: Array, sound_name: String,
		loudness: float, priority: int) -> int:
	if _native_voice_admission != null and _native_voice_admission.has_method("select_victim_stable"):
		return int(_native_voice_admission.call("select_victim_stable",
			snapshot, sound_name, loudness, priority,
			AudioVoices.MAX_VOICES, AudioVoices.SAME_SOUND_MAX,
			AudioVoices.STEAL_HOLD_SECONDS, AudioVoices.STEAL_EARLY_OVERRIDE_DB))
	return AudioVoices.prioritized_victim_stable(snapshot, sound_name, loudness, priority)


func get_voice_hold_rejections() -> int:
	return _voice_hold_rejections


func get_spatial_emission_rejections() -> int:
	return _spatial_emission_rejections


## Early, data-only admission before sound resource resolution, allocation,
## sound-voice policy, physics queries or audio-server work.
func _should_emit_spatial(name: String, at: Vector3, now: float) -> bool:
	var last_position := Vector3.INF
	var last_time := -1.0
	var window: float = float(SPATIAL_RETRIGGER.get(name, 0.0))
	if window > 0.0:
		var recent: Dictionary = _last_spatial_emissions.get(name, {})
		last_position = recent.get("at", Vector3.INF)
		last_time = float(recent.get("time", -1.0))
	if _native_spatial_emission != null and _native_spatial_emission.has_method("should_emit"):
		return bool(_native_spatial_emission.call("should_emit", _listener, at,
			last_position, now, last_time, window, SPATIAL_MERGE_RADIUS,
			SPATIAL_MAX_DISTANCE, _listener_ready))
	return AudioEmission.should_emit(_listener, at, last_position, now,
		last_time, window, SPATIAL_MERGE_RADIUS, SPATIAL_MAX_DISTANCE,
		_listener_ready)


func _record_spatial_emission(name: String, at: Vector3, now: float) -> void:
	if _listener_ready and SPATIAL_RETRIGGER.has(name):
		# Only a successfully started voice may block a following event.
		_last_spatial_emissions[name] = {"at": at, "time": now}


func play_at(sound_name: String, position: Vector3, volume_db: float = 0.0) -> void:
	if not enabled:
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	if not _should_emit_spatial(sound_name, position, now):
		_spatial_emission_rejections += 1
		return
	var stream := Assets.sound(sound_name)
	if stream == null:
		return
	# Plan sound admission before creating a 3D voice Node.
	var distance := position.distance_to(_listener)
	var loudness := AudioVoices.audibility(volume_db, distance, 14.0)
	var priority: int = AudioVoices.priority_for(sound_name)
	var snapshot: Array = []
	for v in _voices:
		snapshot.append({"name": v["name"], "audibility": v["audibility"],
			"age": maxf(0.0, now - float(v["born"])),
			"priority": int(v.get("priority", 0))})
	var cull: int = _choose_voice_victim(snapshot, sound_name, loudness, priority)
	if cull == AudioVoices.DROP_NEW:
		# Count only voice holds, not ordinary too-quiet or malformed requests.
		# This comparison is evaluated only on rejection, not the hot play path.
		if AudioVoices.prioritized_victim(snapshot, sound_name, loudness, priority) >= 0:
			_voice_hold_rejections += 1
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.unit_size = 14.0
	player.max_distance = 90.0
	player.bus = ReverbZones.BUS
	if cull >= 0:
		var old: Dictionary = _voices[cull]
		_voices.remove_at(cull)
		if is_instance_valid(old["player"]):
			(old["player"] as Node).queue_free()
	# Random pitch and volume per shot, then air absorption and terrain occlusion on the source itself.
	var variation := AudioVoices.variation(randf(), randf())
	player.pitch_scale = variation["pitch"]
	player.volume_db = volume_db + float(variation["db"])
	var occluded: bool = _ground.is_valid() and AudioSpatial.terrain_blocked(_listener + Vector3(0, 1.6, 0), position, _ground)
	# Store the *unblocked* distance/air attenuation. The native obstruction
	# curve (or the stock fallback) will apply cover exactly once, over time.
	# Starting at an already blocked cutoff would double-apply muffling.
	player.attenuation_filter_cutoff_hz = AudioSpatial.source_cutoff(distance, false, _humidity)
	player.attenuation_filter_db = -24.0
	var initial_obstruction: float = 1.0 if occluded else 0.0
	var unblocked_volume_db: float = player.volume_db
	var unblocked_cutoff_hz: float = player.attenuation_filter_cutoff_hz
	# The terrain test is already known at spawn. Muffle the FIRST audio
	# buffer, not just the next 0.25 s obstruction-physics update.
	if player.has_method("set_obstruction_amount"):
		player.call("set_obstruction_amount", initial_obstruction)
	elif occluded:
		player.attenuation_filter_cutoff_hz = AudioSpatial.obstruction_cutoff(
			unblocked_cutoff_hz, initial_obstruction)
		player.volume_db = unblocked_volume_db + AudioSpatial.obstruction_db(initial_obstruction)
	_ensure_concurrency()
	if _concurrency != null and not bool(_concurrency.call("request_play", StringName(sound_name), player, position, _listener)):
		player.free()
		return
	add_child(player)
	player.global_position = position
	var record := {
		"player": player, "name": sound_name, "priority": priority,
		"audibility": loudness + AudioSpatial.obstruction_db(initial_obstruction),
		"born": now, "base_audibility": loudness, "terrain_blocked": occluded,
		"obstruction": initial_obstruction,
		"target_obstruction": initial_obstruction,
		"next_obstruction_check": 0.0,
		"original_db": unblocked_volume_db,
		"original_cutoff": unblocked_cutoff_hz
	}
	_voices.append(record)
	player.finished.connect(func() -> void:
		_voices.erase(record)
		player.queue_free())
	player.play()
	_record_spatial_emission(sound_name, position, now)


## Scene physics is read only during physics ticks. This detects wooden
## barricades, ruins and dungeon walls in addition to the existing terrain
## heightfield obstruction, without querying on every audio mixer update.
## The native engine handles the actual volume/low-pass response. Stock
## Godot receives the identical effect via its standard player properties.
func _physics_process(delta: float) -> void:
	if not enabled or _voices.is_empty() or not is_finite(delta) or delta <= 0.0:
		return
	_obstruction_clock += minf(delta, 0.1)
	var viewport: Viewport = get_viewport()
	var world: World3D = viewport.world_3d if viewport != null else null
	var state: PhysicsDirectSpaceState3D = world.direct_space_state if world != null else null
	var rays: int = 0
	for index in _voices.size():
		var record: Dictionary = _voices[index]
		var player: AudioStreamPlayer3D = record.get("player") as AudioStreamPlayer3D
		if not is_instance_valid(player) or not player.is_playing():
			continue
		var target: float = float(record.get("target_obstruction", 0.0))
		if state != null and rays < OBSTRUCTION_RAYS_PER_TICK \
				and _obstruction_clock >= float(record.get("next_obstruction_check", 0.0)):
			var listener_eye: Vector3 = _listener + Vector3(0.0, 1.6, 0.0)
			var source_eye: Vector3 = player.global_position + Vector3(0.0, 0.5, 0.0)
			# Include world obstacles and barriers, not Area3D triggers.
			# Impacts very near the source are the source's own floor/prop.
			var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
				listener_eye, source_eye, OBSTRUCTION_GEOMETRY_MASK)
			ray.collide_with_areas = false
			var hit: Dictionary = state.intersect_ray(ray)
			var blocked: bool = not hit.is_empty() and \
				(hit.get("position", source_eye) as Vector3).distance_to(source_eye) > 0.75
			# Live occlusion rays keep terrain masking current as the listener
			# moves around ridges. Reuse the SAME three-ray scheduler: no
			# uncapped per-frame sound-source heightfield scans.
			var terrain_blocked: bool = _ground.is_valid() and AudioSpatial.terrain_blocked(
				listener_eye, source_eye, _ground)
			record["terrain_blocked"] = terrain_blocked
			target = 1.0 if blocked or terrain_blocked else 0.0
			record["target_obstruction"] = target
			record["next_obstruction_check"] = _obstruction_clock + OBSTRUCTION_RECHECK_SECONDS
			rays += 1
		# Unreal-style occlusion attack/release: fall behind a wall quickly,
		# recover smoothly when the player steps into the open. Cgame handles
		# interpolation in the native 3D source; stock Godot uses the same
		# frame-rate-independent exponential curve in GDScript.
		var old_amount: float = float(record.get("obstruction", 0.0))
		var native_smoothing: bool = player.has_method("advance_obstruction_amount")
		var amount: float
		if native_smoothing:
			amount = float(player.call("advance_obstruction_amount", target, delta,
				AudioSpatial.OBSTRUCTION_ATTACK_SECONDS, AudioSpatial.OBSTRUCTION_RELEASE_SECONDS))
		else:
			amount = AudioSpatial.smooth_obstruction(old_amount, target, delta)
		if absf(amount - old_amount) > 0.0001:
			record["obstruction"] = amount
			# Muffled shots should lose voice-priority against clear,
			# closer combat events instead of stealing a louder channel.
			record["audibility"] = float(record.get("base_audibility", record["audibility"])) \
				+ AudioSpatial.obstruction_db(amount)
			if player.has_method("set_obstruction_amount"):
				if not native_smoothing:
					player.call("set_obstruction_amount", amount)
			else:
				var base_cutoff: float = float(record["original_cutoff"])
				player.attenuation_filter_cutoff_hz = AudioSpatial.obstruction_cutoff(base_cutoff, amount)
				player.volume_db = float(record["original_db"]) + AudioSpatial.obstruction_db(amount)
		_voices[index] = record


## Creates the engine SoundConcurrencyManager once, when the binary has it; victims it stops are freed here.
func _ensure_concurrency() -> void:
	if _concurrency_tried:
		return
	_concurrency_tried = true
	_concurrency = EngineFeatures.make("SoundConcurrencyManager") as Node
	if _concurrency == null:
		return
	add_child(_concurrency)
	_concurrency.connect("voice_stopped", func(stopped: Node) -> void:
		if is_instance_valid(stopped):
			stopped.queue_free())
	for group in CONCURRENCY_GROUPS:
		var rule := EngineFeatures.make("SoundConcurrency", {
			"max_count": int(CONCURRENCY_GROUPS[group]), "resolution_rule": 1, "volume_scale": 0.85}) as Resource
		_concurrency.call("set_group_config", StringName(group), rule)


func play_ui(sound_name: String, volume_db: float = -6.0) -> void:
	if not enabled:
		return
	var player := AudioStreamPlayer.new()
	player.stream = Assets.sound(sound_name)
	player.volume_db = volume_db
	player.bus = "UI"
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


## Glides world-sound reverb toward the listener's acoustic zone (cave, forest, open ground).
func update_reverb(underground: bool, biome: String, delta: float) -> void:
	ReverbZones.blend(ReverbZones.reverb(_sfx_bus), ReverbZones.zone_for(underground, biome), 1.0 - exp(-2.0 * delta))


## Named bus snapshots live independently of temporary sound-event ducks.
## The C++ module only calculates offsets; we compose them with user sliders.
func _activate_mix_snapshot(source: String, offsets: Dictionary, fade_seconds: float) -> void:
	if _native_mix_snapshots != null:
		_native_mix_snapshots.call("activate_mix", StringName(source), offsets, fade_seconds)
	else:
		AudioMixSnapshots.activate_mix(_script_mix_snapshots, source, offsets, fade_seconds)


func _activate_timed_mix_snapshot(source: String, offsets: Dictionary,
		attack_seconds: float, hold_seconds: float, release_seconds: float) -> void:
	if _native_mix_snapshots != null and _native_mix_snapshots.has_method("activate_timed_mix"):
		_native_mix_snapshots.call("activate_timed_mix", StringName(source),
			offsets, attack_seconds, hold_seconds, release_seconds)
	else:
		# Old native engines can still run their manually managed zone mixes.
		# This timed profile is tracked in script only, then combined below.
		AudioMixSnapshots.activate_timed_mix(_script_mix_snapshots, source,
			offsets, attack_seconds, hold_seconds, release_seconds)


func _deactivate_mix_snapshot(source: String, fade_seconds: float) -> void:
	if _native_mix_snapshots != null:
		_native_mix_snapshots.call("deactivate_mix", StringName(source), fade_seconds)
	else:
		AudioMixSnapshots.deactivate_mix(_script_mix_snapshots, source, fade_seconds)


func _snapshot_bus_db(bus: String) -> float:
	var native_offset := 0.0
	if _native_mix_snapshots != null:
		native_offset = float(_native_mix_snapshots.call("get_bus_offset_db", StringName(bus)))
	# When a pre-timed Cgame build has native zone mixing but no timed API,
	# combine its zone contribution with the scripted combat focus mix.
	return maxf(-60.0, native_offset + AudioMixSnapshots.bus_offset_db(_script_mix_snapshots, bus))


## Unreal Audio Volume / Control Bus Mix-style independent, layered profiles.
## Storm has hysteresis: a fluctuating forecast cannot re-trigger every frame.
func _update_environment_mix_snapshots(underground: bool, biome: String,
		storm: float, delta: float) -> void:
	var zone: String = ReverbZones.zone_for(underground, biome)
	if zone != _mix_zone:
		if _mix_zone == "underground":
			_deactivate_mix_snapshot("Zone.Underground", 1.25)
		elif _mix_zone == "forest":
			_deactivate_mix_snapshot("Zone.Forest", 1.25)
		if zone == "underground":
			_activate_mix_snapshot("Zone.Underground", {
				"Music": -3.0, "Ambience": -4.0, "SFX": -2.0}, 1.25)
		elif zone == "forest":
			_activate_mix_snapshot("Zone.Forest", {
				"Ambience": -1.5, "SFX": -0.5}, 1.25)
		_mix_zone = zone
	if is_finite(storm):
		if not _storm_mix_active and storm >= 0.70:
			_activate_mix_snapshot("Weather.Storm", {
				"Music": -2.0, "Ambience": -1.0, "SFX": -0.75}, 2.0)
			_storm_mix_active = true
		elif _storm_mix_active and storm <= 0.55:
			_deactivate_mix_snapshot("Weather.Storm", 2.0)
			_storm_mix_active = false
	if _native_mix_snapshots != null:
		_native_mix_snapshots.call("tick", delta)
	# Script timed mixes may coexist with native zone mixes on older Cgame
	# binaries, while native timed builds have an empty script dictionary.
	AudioMixSnapshots.tick(_script_mix_snapshots, delta)


## Do not resubmit identical AudioServer bus gain every render frame.
static func _apply_bus_gain(bus: String, gain_db: float) -> void:
	var index: int = AudioServer.get_bus_index(bus)
	gain_db = maxf(-80.0, gain_db)
	if index >= 0 and absf(AudioServer.get_bus_volume_db(index) - gain_db) > 0.01:
		AudioServer.set_bus_volume_db(index, gain_db)


## Per-frame environment audio: listener filtering, surface footsteps, weather loops, biome bed, music ducking.
## `storm` 0..1, `wind` is the wind speed, `covered` = sheltered or underground.
func update_environment(listener: Vector3, ground_height: Callable, underground: bool, biome: String,
		daylight: float, storm: float, wind: float, covered: bool, speed: float, delta: float) -> void:
	_listener = listener
	_listener_ready = listener.is_finite()
	_ground = ground_height
	_humidity = clampf(storm, 0.0, 1.0)
	# Listener low-pass on the SFX bus (underground / storm).
	_cutoff = AudioSpatial.glide(_cutoff, AudioSpatial.listener_cutoff(underground, storm), delta)
	var lowpass := AudioServer.get_bus_effect(_sfx_bus, _sfx_lowpass) as AudioEffectLowPassFilter if _sfx_lowpass >= 0 else null
	if lowpass != null:
		lowpass.cutoff_hz = _cutoff
	# Surface footsteps retune the walking loop.
	var h := float(ground_height.call(listener.x, listener.z)) if ground_height.is_valid() else 1.0
	_surface = AudioSurfaces.surface_for(underground, biome, h, Defs.WATER_LEVEL)
	var profile := AudioSurfaces.profile(_surface)
	_steps.pitch_scale = AudioSurfaces.speed_pitch(float(profile["pitch"]), speed)
	_steps.volume_db = float(profile["db"])
	# Biome ambience bed, rain and wind loops.
	var bed := AudioAmbient.bed(biome, daylight, underground)
	_ambience.pitch_scale = lerpf(_ambience.pitch_scale, float(bed["pitch"]), 1.0 - exp(-1.5 * delta))
	_ambience.volume_db = lerpf(_ambience.volume_db, float(bed["db"]), 1.0 - exp(-1.5 * delta))
	_rain.volume_db = lerpf(_rain.volume_db, AudioAmbient.rain_db(storm, covered), 1.0 - exp(-2.0 * delta))
	_wind.volume_db = lerpf(_wind.volume_db, AudioAmbient.wind_db(wind, storm, underground), 1.0 - exp(-2.0 * delta))
	# Long-lived zone/weather mix profiles are separate from transient audio ducks.
	_update_environment_mix_snapshots(underground, biome, storm, delta)
	# Native Unreal-style duck bus mixer, with independent event holds.
	# The fallback follows the same target and 40/4 dB/s envelope exactly.
	if _native_duck != null:
		_duck = float(_native_duck.call("tick", delta))
	else:
		_duck = AudioDucking.tick_sources(_duck_sources, _duck, delta)
	# Sum user volume, independent named zone/weather offsets and event ducking.
	# Muted user sliders remain muted even when a profile is activated.
	var music_gain: float = AudioMix.linear_to_db(AudioMix.volumes["Music"]) + _duck + _snapshot_bus_db("Music") if AudioMix.volumes["Music"] > 0.0001 else -80.0
	var ambience_gain: float = AudioMix.linear_to_db(AudioMix.volumes["Ambience"]) + _duck * 0.4 + _snapshot_bus_db("Ambience") if AudioMix.volumes["Ambience"] > 0.0001 else -80.0
	var effects_gain: float = AudioMix.linear_to_db(AudioMix.volumes["SFX"]) + _snapshot_bus_db("SFX") if AudioMix.volumes["SFX"] > 0.0001 else -80.0
	_apply_bus_gain("Music", music_gain)
	_apply_bus_gain("Ambience", ambience_gain)
	_apply_bus_gain("SFX", effects_gain)


## Dip music for one named event. Retrigger resets only that source's hold.
## Legacy call sites without a name keep the established shared "Generic" key.
func duck(depth_db: float, source: String = "Generic") -> void:
	if _native_duck != null:
		_native_duck.call("trigger", StringName(source), depth_db, AudioDucking.HOLD)
	else:
		AudioDucking.trigger_source(_duck_sources, source, depth_db, AudioDucking.HOLD)


var _slider := 0


## Ctrl+Home picks the next volume slider (Master/Music/SFX/UI/Ambience), Ctrl+PageUp/PageDown change it.
## Returns the message to show, or "" when the key is not an audio shortcut.
func handle_key(event: InputEventKey) -> String:
	if not event.ctrl_pressed:
		return ""
	var bus: String = AudioMix.SLIDERS[_slider]
	match event.keycode:
		KEY_HOME:
			_slider = (_slider + 1) % AudioMix.SLIDERS.size()
			bus = AudioMix.SLIDERS[_slider]
		KEY_PAGEUP:
			AudioMix.nudge(bus, 0.1)
		KEY_PAGEDOWN:
			AudioMix.nudge(bus, -0.1)
		_:
			return ""
	return "Volume %s: %d%% (Ctrl+Home bus, Ctrl+PgUp/PgDn)" % [bus, roundi(float(AudioMix.volumes[bus]) * 100.0)]


func surface() -> String:
	return _surface


## Reacts to one server event. `height` is the ground height used for positions without one.
func on_event(event: Dictionary, local_peer: int, ground_height: Callable) -> void:
	_ground = ground_height
	if event.get("peer", local_peer) == local_peer or event["type"] in ["zombie_died", "knockback"]:
		duck(AudioDucking.depth_for(str(event["type"])), str(event["type"]))
	var position := Vector3.ZERO
	if event.has("x") and event.has("z"):
		position = Vector3(event["x"], float(ground_height.call(event["x"], event["z"])) + 1.0, event["z"])
	match event["type"]:
		"attack":
			if event.get("peer", -1) == local_peer:
				mark_combat()
			play_at("blaster" if event.get("ranged", false) else "break", position, -4.0 if event.get("ranged", false) else -14.0)
		"hit":
			if event.get("kind", "") == "zombie":
				play_at("enemy_hurt", position, -4.0)
			elif event.get("id", -1) == local_peer:
				mark_combat()
				play_ui("enemy_attack", -4.0)
		"zombie_died":
			play_at("enemy_destroy", position, -2.0)
		"barricade_broken", "snare_triggered":
			play_at("break", position, -4.0)
		"flash_thrown":
			play_at("blaster_repeater", position, -6.0)
		"knockback":
			play_at("enemy_hurt", position, -8.0)
		"restoration_pulse":
			play_at("coin", position, -6.0)
		"outpost_taken":
			play_ui("weapon_change", -6.0)
		"gathered":
			play_ui("coin", -8.0)
		"crate":
			play_ui("weapon_change", -6.0)
		"death":
			if event.get("peer", -1) == local_peer:
				play_ui("fall", -2.0)
				play_sting("Death")
		"skill_up":
			if event.get("peer", -1) == local_peer:
				play_sting("Complete", -12.0)
		"outpost_taken":
			play_sting("Victory", -10.0)

# Spatial sound event coalescing (Unreal-inspired)

Unreal Engine Sound Concurrency supports Retrigger Time and owner-scoped
concurrency. Cgame already limits simultaneous sound voices and protects
their opening attack from repeated eviction, but every incoming event
previously decoded a stream, planned a voice, and risked a 3D source
allocation and terrain occlusion checks before being dropped.

This reusable data-only policy admits a new sound based on:
- Whether the listener is ready and a source coordinate is finite.
- A conservative max-distance check (real player 90 m plus 2 m pad).
- Whether the previous successful event of the SAME sound name arose
  within a small radius and a short retrigger window.

This is early **event coalescing**, not active voice limiting.
The existing SoundConcurrencyManager and AudioVoiceAdmissionPlanner
still decide which started voices win their global/group budgets.
The policy never calls AudioServer/PhysicsServer, creates nodes,
changes networking, or suppresses gameplay events themselves.

## Engine API

SpatialSoundEventPolicy is a RefCounted native class in gameplay_fx
with one pure method:

should_emit(listener, source, previous_source, now_seconds, last_seconds,
retrigger_seconds, merge_radius, max_distance, listener_ready=true)

It returns true when a new audio event is eligible. Negative last time
means no previous accepted event. Invalid source vectors are rejected
so no audio transform contains NaNs; missing/invalid listeners bypass
spatial suppression. Other malformed optional parameters fail open.
A monotonically rewound clock also bypasses the retrigger restriction.
The implementation uses squared-distance tests without allocations,
scripting dictionaries or physics raycasts.

## Live Albion After integration

The real Audio.play_at runtime calls the policy BEFORE Assets.sound,
voice snapshots, AudioStreamPlayer3D construction and obstruction tests.
Only three low-priority short cosmetic sound names have retrigger
windows: enemy_hurt 75 ms, break 95 ms and coin 90 ms, all limited to
3.5 m around the last successfully emitted event of that name.

No extra spatial retrigger is applied to gunfire, boss attacks, enemy
kills, dialogue, UI or music. Different encounters more than 3.5 m
apart can still play independently. Only successfully started audio
updates a bounded, three-entry per-sound history dictionary. The
existing 90 m AudioStreamPlayer3D max_distance is reused for a safe
early cull; when the listener is not yet ready the legacy path runs.
Native and stock-Godot fallback APIs use matching conditions.

## Test coverage

- C++ doctests: near/far, same/different location, exact time boundary,
  startup listener, invalid coordinates and timing, no retroactive
  suppression when time is reset.
- Focused headless game: matching native/fallback matrix, important
  combat bypass, bounded tracking, source-code checks of the actual
  playback ordering and a real Audio node.
- CI: source contracts plus real Godot/Cgame native build, C++ tests,
  Albion After import, focused run and complete game headless suite.

This is a CPU/source-churn optimization, not a measured audio latency
or FPS claim. Real battle scenes need profiling and listening tests.
Official Unreal reference:
https://dev.epicgames.com/documentation/en-us/unreal-engine/sound-concurrency-reference-guide

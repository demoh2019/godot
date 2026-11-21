# Cosmetic debris simulation LOD (Chaos-inspired)

Unreal Engine Chaos includes Sleep, Disable and Kill Fields to reduce the
number of active rigid bodies while preserving convincing destruction.
Albion After has pooled cosmetic rigid bodies for broken barricades,
blast fragments and spent shell casings. The physics loop previously
simulated every live body until natural sleep or its nine-second lifetime.

## Cgame engine API

The `DebrisSimulationLOD3D` native RefCounted class exports the pure
`classify(distance_m, in_water, previous_tier, simulate_radius_m=24.0,
retire_radius_m=56.0, hysteresis_m=2.0)` function.

- **0** simulates full rigid-body movement near the viewer.
- **1** freezes a distant dry body's simulation while keeping its mesh.
- **2** retires an irrelevant body to the game's existing node pool.
- **-1** means invalid input and must never change physics state.

At 24m nominal distance, moving away freezes at 26m and approaching
unfreezes at 22m: the 4m hysteresis gap prevents boundary thrashing.
Water exempts bodies from medium-range freezing so wood keeps floating
and brass keeps sinking. Retirement at 56m applies to both. No camera
node, renderer, physics server, networking, mutable global state,
allocation or clock access exists in the native API.

## Albion After integration

The actual networked client already invokes
`physics_fx.update(delta, position)` each frame. Its
`physics_world_fx.gd` forwards the local viewer position to
`physics_debris.gd`. The debris physics tick now:

1. Uses the optional native class, with a matching stock-Godot fallback.
2. Freezes dry shards and casings beyond the 26m boundary, unfreezing
   as the player approaches within 22m.
3. Retires any cosmetic fragments beyond 56m into the bounded pool.
4. Preserves near debris physics and water buoyancy, including existing
   9s lifetime/sleep-retirement shrink and server-invisible collision.
5. Suppresses out-of-range chunk/casing spawns and blast queries before
   allocating mesh/shape objects or doing physics-ray overlap work.
6. Wakes frozen fragments for 400 ms if a nearby explosion can affect
   them, so blast impulses still animate visible pieces. Frozen bodies
   also immediately unfreeze if the viewer position becomes invalid.
7. Iterates active bodies backwards, removing the per-physics-frame
   `_bodies.duplicate()` temporary array even during mass recycling.

Invalid or missing viewer positions disable the distance policy and
retain the old full-physics path. The game does not modify server-owned
damage, hitboxes, zombies, navigation, combat, saves or network state.

## Validation

- Native C++ doctests: exact threshold boundaries, water, invalid
  inputs, 600-frame hysteresis simulation and safe radius constraints.
- Focused and full headless game regression: parity, state transitions
  on actual pooled `RigidBody3D` nodes, no-camera fallback, early
  spawn culling, short blast-wake grace and the live `physics_fx` update chain.
- GitHub Actions workflow: source contracts, native editor build,
  doctests, import, focused and full Albion After tests.

This controls the number of bodies submitted for active simulation;
performance gains are not asserted without measuring the physics
server time and active body counts on a real gameplay scene.

Unreal documentation:
https://dev.epicgames.com/documentation/en-us/unreal-engine/chaos-fields-user-guide-in-unreal-engine

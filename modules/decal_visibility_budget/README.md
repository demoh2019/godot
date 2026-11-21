# Projected-size decal admission (Cgame)

Unreal Engine exposes decal screen-size fading and distance settings.
Large deferred decal boxes and expensive materials can produce overdraw
even when their surface contribution is imperceptibly small. Albion After
already used GPU-native distance fades and bounded projector pools, but
distant combat hit events still recycled visible projector slots, picked
random texture variants and changed render-server decal properties.

## Engine API

The reusable native class DecalVisibilityAdmission3D has a pure method
should_spawn(camera_position, decal_position, diameter_m, max_distance_m,
viewport_height_px, vertical_fov_deg, min_diameter_px=3.0).

- Objects remain eligible within max distance plus half the decal diameter,
  retaining large partially visible scorch marks near the fade edge.
- Conservative projected diameter in screen pixels:
  diameter_m * viewport_height / (2 * tan(vertical_fov / 2) * max(distance, 0.1)).
- Subpixel projectors are rejected before allocation or recycling.
- Width/height convert horizontal to vertical camera FOV as needed in-game.
  Orthographic and missing cameras preserve legacy behavior.
- Finite-input and range validation; no state, physics raycasts, GPU calls,
  materials, Node lookups or networking inside the native policy.
- Matching GDScript policy on stock Godot and older Cgame binaries.

## Albion After gameplay use

Both impact_decals.gd and blood_decals.gd call the policy before picking
or evicting GPU decal pool slots. Rejected events no longer allocate
textures, use RNG variants, or update native projector nodes. Blood
splats and explosion scorch marks use their authored sizes and the same
distance fading limits as existing native Decal nodes.

The existing near-visible blood/impact effects, pooled texture budgets,
footprints and fade durations are unchanged. Only client-side visuals
change; authoritative hit registration, AI, save files and world state
are unaffected.

## Validation

C++ doctests cover distance, partial volume edges, screen-size cutoff,
invalid input, monotonic diameter and near behavior. Game tests cover
optional native/stock fallback parity across a camera/size matrix,
no-camera legacy admission and actual impact pool integration. CI builds
the native editor, runs C++ doctests, imports Albion After and executes
focused/full headless gameplay tests.

This is an early-admission/pool-churn optimization, not a claim of
measured GPU speedup without profiler traces.

Unreal references:
https://dev.epicgames.com/documentation/en-us/unreal-engine/decal-actors-in-unreal-engine
https://dev.epicgames.com/documentation/unreal-engine/decal-materials-in-unreal-engine

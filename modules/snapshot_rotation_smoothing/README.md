# Replicated yaw smoothing (Cgame)

Inspired by Unreal Engine CharacterMovementComponent's simulated-proxy
NetworkSmoothingMode (especially network rotation smoothing). Albion
After already uses jitter-buffered position histories with conservative
Hermite interpolation for remote players and infected. Until now,
rotation always used a two-snapshot lerp, producing unnaturally even
turns around corners and during interrupted animations.

## Native engine policy

SnapshotRotationSmoothing3D.interpolate_yaw(from_yaw, to_yaw,
from_angular_velocity, to_angular_velocity, snapshot_span, fraction)
is a pure RefCounted function. It does not access the network, a Node,
PhysicsServer, Renderer, clocks, or player authority.

- Interpolates only on the shorter angular arc (supports +/-180 seam).
- Four-snapshot motion history estimates turn rate at both endpoints;
  asymmetric rates produce smoother-looking acceleration/deceleration.
- Signed Hermite tangents are restricted to 0..3 of the shortest arc;
  resulting yaw is clamped to the unwrapped endpoint interval.
- Abrupt turns above 2.4 radians, stale/missing neighbors, long network
  gaps and invalid angular velocities use shortest-arc linear smoothing.
- Nonfinite authoritative angles fail safely to the other finite
  angle or zero. No NaNs can reach a transform.
- Alpha is always clamped to 0..1. At t=1, the server endpoint is
  represented modulo 2*pi while keeping yaw numerically continuous
  across +/-pi to avoid a full artificial revolution.

## Live Albion After integration

The real EntityView._sample() already samples player/zombie motion
from 10Hz authoritative histories and a monotonic jitter-buffer clock.
It now uses SnapshotSmoothing.sample_yaw for non-Performance graphics
tiers and an optional native SnapshotRotationSmoothing3D instance.
Ordinary Godot and previous Cgame engine builds use the equivalent
GDScript algorithm; Performance continues the original cheap
lerp_angle with only two samples.

Two-snapshot or invalid-neighbor histories retain linear interpolation.
Existing teleport reset and newest-server-pose hold logic stay in
place. The client does not predict future combat or modify any
server-authoritative physics, movement, replication or animation state.

## Validation

- C++ doctests: shortest-arc seam, linear limiting cases,
  angular-slope clamps and input sanitization.
- Headless GDScript: two-snapshot compatibility, 101-step continuous
  seam, abrupt turns, lost packets, acceleration, native/fallback parity
  on a multi-axis input matrix and actual EntityView wiring.
- Dedicated GitHub Actions: source-contract tests, native editor
  build/doctests, Albion After import, focused and full headless tests.

This is an interpolation quality improvement; frame timing and GPU
performance are unchanged. It adds no extra network packets.

Unreal Engine reference:
https://dev.epicgames.com/documentation/unreal-engine/understanding-networked-movement-in-the-character-movement-component-for-unreal-engine

extends Node3D
## One client-only entry point for cosmetic physics and world interactivity: server events in, debris / blasts /
## plant shakes out, plus the per-frame player grass bend. Owns physics_debris.gd and plant_interaction.gd.
## It reads events and positions but never writes anything back to the simulation.
## See docs/ENGINE_PARITY_FX.md ("Physics and world interactivity").

const PhysicsDebris = preload("res://scripts/client/physics_debris.gd")
const PlantInteraction = preload("res://scripts/client/plant_interaction.gd")

var debris: Node3D
var plants := PlantInteraction.new()


## Blast field for an event type as Vector2(radius m, impulse m/s); ZERO when the event does not push things.
static func blast_for(event_type: String) -> Vector2:
	match event_type:
		"barricade_broken":
			return Vector2(4.5, 5.0)
		"flash_thrown":
			return Vector2(5.0, 4.0)
		"ember_thrown":
			return Vector2(3.5, 3.0)
		"knockback":
			return Vector2(3.0, 3.5)
		"zombie_died":
			return Vector2(1.6, 1.5)
	return Vector2.ZERO


## Events that spawn chunk debris, with the strength of the burst.
static func chunk_strength_for(event_type: String) -> float:
	return 1.0 if event_type == "barricade_broken" else 0.0


func setup(world) -> void:
	debris = PhysicsDebris.new()
	debris.name = "PhysicsDebris"
	add_child(debris)
	debris.setup(world.height_at, world.is_water)


func on_event(event: Dictionary, at: Vector3) -> void:
	var event_type := str(event.get("type", ""))
	var level := PhysicsDebris.quality_level()
	if level <= 0 or debris == null:
		return
	plants.shake(at, PlantInteraction.shake_amplitude_for(event_type))
	var strength := chunk_strength_for(event_type)
	if strength > 0.0:
		debris.burst_chunks(Vector3(at.x, at.y - 0.6, at.z), strength)
	var field := blast_for(event_type)
	if field != Vector2.ZERO:
		debris.blast(at - Vector3(0, 0.4, 0), field.x, field.y)
	# Casings for ranged attacks come from combat_vfx.gd, which reads the server's `dir`
	# (attack events carry no yaw); spawning here too would double every casing.


func update(delta: float, player: Vector3) -> void:
	# Same local viewer used for plant bending also controls non-authoritative
	# Chaos-style rigid-body LOD. Server simulation is unchanged.
	if debris != null:
		debris.call("set_viewer_position", player)
	plants.update(delta, player, PhysicsDebris.quality_level())

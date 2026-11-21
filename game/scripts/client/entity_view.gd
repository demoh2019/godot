extends Node3D
## Draws the moving things: other players, zombies and loot bags, smoothed between snapshots.

const Defs = preload("res://scripts/shared/defs.gd")
const Structures = preload("res://scripts/shared/structures.gd")
const ModelCatalog = preload("res://scripts/client/model_catalog.gd")
const Meshes = preload("res://scripts/client/meshes.gd")
const CharacterModel = preload("res://scripts/client/character_model.gd")
const TrailBikeVisual = preload("res://scripts/client/trail_bike_visual.gd")
const HandFlareVisual = preload("res://scripts/client/hand_flare_visual.gd")
const Assets = preload("res://scripts/client/assets.gd")
const LootLabel = preload("res://scripts/shared/loot_label.gd")
const Ragdoll = preload("res://scripts/client/ragdoll.gd")
const CharacterAnim = preload("res://scripts/client/character_anim.gd")
const SnapshotSmoothing = preload("res://scripts/client/network_snapshot_smoothing.gd")
const NetworkJitterBuffer = preload("res://scripts/client/network_jitter_buffer.gd")
const LootDropBounce = preload("res://scripts/client/loot_drop_bounce.gd")
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")
const EngineFeatures = preload("res://scripts/client/engine_features.gd")
const GameplayCues = preload("res://scripts/client/gameplay_cues.gd")
const AnimLod = preload("res://scripts/client/anim_lod.gd")
const CombatAnimationPriority = preload("res://scripts/client/combat_animation_priority.gd")
const CampfireFx = preload("res://scripts/client/campfire_fx.gd")
const LootBeam = preload("res://scripts/client/loot_beam.gd")
const CorpseBurn = preload("res://scripts/client/corpse_burn.gd")
const BlobShadow = preload("res://scripts/client/blob_shadow.gd")
const FarmPlotVisual = preload("res://scripts/client/farm_plot_visual.gd")
var _anim_lod: Node = null # Native AnimationLODController when the engine has it, else the GDScript AnimLod.
var _priority_quality: int = -1
var _world = null
var _corpses: Array[Dictionary] = []
var _leaps: Dictionary = {} # "zombie:id" -> {"from": Vector3, "to": Vector3, "t": float}
const LEAP_SECONDS := 0.55
const CORPSE_MAX_SECONDS := 900.0 # A looted-out or abandoned body still goes eventually.
const LOOT_GLOW_SHADER := preload("res://shaders/loot_glow.gdshader")

const ZOMBIE_LOOK := {
	"walker": {"tint": Color(0.62, 0.85, 0.55), "scale": 2.0, "walk": 0.8, "model": "Orc_Male"},
	"runner": {"tint": Color(0.9, 0.9, 0.45), "scale": 1.85, "walk": 1.8, "model": "Elf_Female"},
	"brute": {"tint": Color(0.55, 0.5, 0.7), "scale": 3.0, "walk": 0.7, "model": "Orc_Female"},
	"spitter": {"tint": Color(0.42, 0.87, 0.28), "scale": 2.1, "walk": 0.65, "model": "Orc_Male"},
	"stalker": {"tint": Color(0.32, 0.3, 0.36), "scale": 1.95, "walk": 1.6, "model": "Elf_Male"},
	"sentinel": {"tint": Color(0.5, 0.58, 0.72), "scale": 2.6, "walk": 0.9, "model": "Orc_Female"},
	"howler": {"tint": Color(0.82, 0.7, 0.9), "scale": 2.0, "walk": 1.0, "model": "Elf_Female"},
	"crawler": {"tint": Color(0.72, 0.62, 0.42), "scale": 1.35, "walk": 1.6, "model": "Orc_Male"},
}


static func zombie_look(zombie_type: String) -> Dictionary:
	return ZOMBIE_LOOK.get(zombie_type, ZOMBIE_LOOK["walker"])
const ALERT_TINT := Color(1.0, 0.45, 0.4)

var _nodes: Dictionary = {} # "kind:id" -> Node3D
var _targets: Dictionary = {} # "kind:id" -> {"position": Vector3, "yaw": float}
var _history: Dictionary = {} # "player:id" / "zombie:id" -> [[server time, position, yaw], ...] oldest first
var _wetness_step: int = 0
var _snapshot_time := 0.0
var _last_hp: Dictionary = {} # "player:id" / "zombie:id" -> last seen HP, for hit flashes.
var _tag_epoch: Dictionary = {} # Sync native live tags once per server timestamp, not per render frame.
var _render_time := -1.0
# Native jitter telemetry and delay adaptation on Cgame, with 1:1 script
# policy on official Godot. Positions/teleports stay server-authoritative.
var _snapshot_buffer = ClassDB.instantiate("AdaptiveNetworkJitterBuffer") if ClassDB.class_exists("AdaptiveNetworkJitterBuffer") else NetworkJitterBuffer.new()
var _rotation_smoother: Object = EngineFeatures.make("SnapshotRotationSmoothing3D")
const INTERPOLATION_DELAY := 0.12 # Baseline for 10 server snapshots per second.
const TELEPORT_DISTANCE := 8.0


func _init() -> void:
	# Match the dedicated server's actual snapshot rate. Configuration
	# only resets this local presentation buffer, never server simulation.
	_snapshot_buffer.configure(INTERPOLATION_DELAY, NetworkJitterBuffer.MAX_DELAY,
		1.0 / float(Defs.SNAPSHOT_RATE))


## House piece models (Kenney Fantasy Town Kit, CC0), sized to the 3 m building grid. Upgraded
## walls (tier 2+) turn from timber to stone.
const PIECE_DIR := "res://assets/models/kenney_building/town/"
const PIECE_MODELS := {
	"wall": [["wall-wood", "length", 3.0], ["wall", "length", 3.0]],
	"door": [["wall-wood-door", "length", 3.0], ["wall-doorway-square", "length", 3.0]],
	"window": [["wall-wood-window-shutters", "length", 3.0], ["wall-window-shutters", "length", 3.0]],
	"floor": [["planks", "length", 3.0], ["planks", "length", 3.0]],
	"roof": [["roof", "length", 3.2], ["roof", "length", 3.2]],
	"pillar": [["pillar-wood", "height", 3.0], ["pillar-wood", "height", 3.0]],
	"bed": [["../../kenney_ruins/survival/bedroll-frame", "length", 2.2], ["../../kenney_ruins/survival/bedroll-frame", "length", 2.2]],
	"lamp": [["../../kenney_ruins/graveyard/fire-basket", "height", 1.3], ["../../kenney_ruins/graveyard/fire-basket", "height", 1.3]],
	"chest": [["../survival/chest", "length", 1.2], ["../survival/chest", "length", 1.2]],
	"workbench": [["../survival/workbench", "length", 1.8], ["../survival/workbench", "length", 1.8]],
	"door_open": [["wall-wood-doorway-base", "length", 3.0], ["wall-doorway-square", "length", 3.0]],
}


static func piece_mesh(piece: String, tier: int) -> Mesh:
	if not PIECE_MODELS.has(piece):
		return wall_mesh(tier)
	var choice: Array = PIECE_MODELS[piece][0 if tier <= 1 else 1]
	var mesh: Mesh = ModelCatalog.entry_mesh({"path": PIECE_DIR + str(choice[0]) + ".glb", "kind": str(choice[1]), "size": float(choice[2])})
	return mesh if mesh != null else wall_mesh(tier)


## The wall model of a tier, or a timber box when the packs are missing.
static func wall_mesh(tier: int) -> Mesh:
	var mesh: Mesh = ModelCatalog.barricade_mesh(tier)
	if mesh != null:
		return mesh
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 1.6, 0.5)
	var material := StandardMaterial3D.new()
	material.albedo_color = Structures.color_for_tier(tier)
	box.material = material
	return box


## A single discrete weather switch updates existing actors; no per-zombie
## per-frame material edits. Newly streamed actors inherit _wetness_step.
func set_wetness_step(step: int) -> void:
	var next_step: int = clampi(step, 0, 4)
	if _wetness_step == next_step:
		return
	_wetness_step = next_step
	for key in _nodes:
		if not (str(key).begins_with("player:") or str(key).begins_with("zombie:")):
			continue
		var model := (_nodes[key] as Node3D).get_node_or_null("Model")
		if model != null:
			model.set_wetness_step(_wetness_step)


## Reusable local diagnostics for network-quality debug overlays.
## Server-side privacy and gameplay snapshots are never modified.
func network_jitter_stats() -> Dictionary:
	return _snapshot_buffer.get_stats()


func update_from(client) -> void:
	# This method runs every render frame, not on every network event.
	# Only new *server timestamps* may update the measured arrival jitter.
	var incoming_time: float = float(client.server_time)
	if not is_finite(incoming_time) or incoming_time < 0.0:
		return
	if incoming_time < _snapshot_time:
		if _snapshot_time - incoming_time <= 0.5:
			return # Out-of-order sample: keep the newest authoritative pose.
		# Reconnect to an earlier server epoch: flush visual history only.
		_snapshot_buffer.reset()
		_history.clear()
		_render_time = -1.0
	_snapshot_time = incoming_time
	_snapshot_buffer.observe(_snapshot_time, float(Time.get_ticks_usec()) * 0.000001)
	if _render_time < 0.0 or absf(_render_time - (_snapshot_time - _snapshot_buffer.delay)) > 0.5:
		_render_time = _snapshot_time - _snapshot_buffer.delay
	var seen: Dictionary = {}
	for id in client.players:
		_touch("player:%d" % id, "player", client.players[id], seen)
	for id in client.zombies:
		_touch("zombie:%d" % id, "zombie", client.zombies[id], seen)
	for id in client.spit_zones:
		_touch("spit:%d" % id, "spit_warning", client.spit_zones[id], seen)
	for id in client.acid_pools:
		_touch("pool:%d" % id, "acid_pool", client.acid_pools[id], seen)
	for id in client.ember_pools:
		_touch("ember:%d" % id, "ember_pool", client.ember_pools[id], seen)
	for id in client.bags:
		_touch("bag:%d" % id, "bag", client.bags[id], seen)
	for id in client.barricades:
		_touch("barricade:%d" % id, "barricade", client.barricades[id], seen)
	for id in client.farm_plots:
		_touch("plot:%d" % id, "plot", client.farm_plots[id], seen)
		FarmPlotVisual.update(_nodes["plot:%d" % id], client.farm_plots[id])
	for id in client.campfires:
		_touch("campfire:%d" % id, "campfire", client.campfires[id], seen)
	for id in client.shelters:
		_touch("shelter:%d" % id, "shelter", client.shelters[id], seen)
	for id in client.decoys:
		_touch("decoy:%d" % id, "decoy", client.decoys[id], seen)
	for id in client.smoke_clouds:
		_touch("smoke:%d" % id, "smoke", client.smoke_clouds[id], seen)
	for id in client.infected_snares:
		_touch("snare:%d" % id, "snare", client.infected_snares[id], seen)
	for id in client.fish_traps:
		_touch("fish_trap:%d" % id, "fish_trap", client.fish_traps[id], seen)
	if not client.raid_telegraph.is_empty():
		_touch("raid_warning:%d" % int(client.raid_telegraph["id"]),
			"raid_warning", client.raid_telegraph, seen)
	_world = client.world
	for key in _nodes.keys():
		if not seen.has(key):
			_unregister_anim_lod(_nodes[key])
			if not (key.begins_with("zombie:") and _try_ragdoll(_nodes[key])):
				_nodes[key].queue_free()
			_nodes.erase(key)
			_targets.erase(key)
			_history.erase(key)
			_last_hp.erase(key)
			_tag_epoch.erase(key)


func _touch(key: String, kind: String, entity: Dictionary, seen: Dictionary) -> void:
	seen[key] = true
	if not _nodes.has(key):
		_nodes[key] = _make(kind, entity)
		add_child(_nodes[key])
		_nodes[key].position = Vector3(entity["x"], entity["y"], entity["z"])
	_targets[key] = {"position": Vector3(entity["x"], entity["y"], entity["z"]), "yaw": float(entity.get("yaw", 0.0))}
	if (kind == "player" or kind == "zombie") and float(_tag_epoch.get(key, -1.0)) != _snapshot_time:
		EngineFeatures.sync_runtime_tags(_nodes[key], kind, entity)
		_tag_epoch[key] = _snapshot_time
	if (kind == "player" or kind == "zombie") and entity.has("hp"):
		var hp: float = float(entity["hp"])
		var before: float = float(_last_hp.get(key, hp))
		_last_hp[key] = hp
		if hp < before and hp > 0.0:
			var hit_model := (_nodes[key] as Node3D).get_node_or_null("Model")
			if hit_model != null and hit_model.has_method("hit_flash"):
				# Bigger hits flash brighter (fraction of the pre-hit HP).
				var strength: float = 0.5 + (before - hp) / maxf(before, 1.0) * 2.0
				hit_model.hit_flash(EngineFeatures.hit_feedback_strength(_nodes[key], strength))
	if kind == "player" or kind == "zombie":
		# Moving things keep a short history on the server clock; they are drawn a little in the past, between two
		# real samples, so uneven packet arrival does not show as stutter.
		var history: Array = _history.get_or_add(key, [])
		var sample := [_snapshot_time, Vector3(entity["x"], entity["y"], entity["z"]), float(entity.get("yaw", 0.0))]
		if not history.is_empty() and float(history[-1][0]) >= _snapshot_time:
			history[-1] = sample
		else:
			if not history.is_empty() and (history[-1][1] as Vector3).distance_to(sample[1]) > TELEPORT_DISTANCE:
				history.clear() # A teleport, a hatch, a respawn: no sliding across the map.
				_nodes[key].position = sample[1]
			history.append(sample)
		while history.size() > 8:
			history.pop_front()
	var label: Label3D = _nodes[key].get_node_or_null("Label")
	if label != null:
		if kind == "fish_trap":
			label.text = "FISH NET T%d | %s" % [
				int(entity.get("tier", 1)), "READY" if bool(entity.get("ready", false)) else
				("%ds" % ceili(float(entity.get("ready_in", 0.0))))]
		elif kind == "zombie":
			label.visible = false # The overlay draws a health bar instead (world_overlay.gd).
			label.text = "%s%s  %d" % [
				"ENRAGED RAID BOSS " if bool(entity.get("raid_enraged", false)) else (
				"RAID BOSS " if bool(entity.get("raid_boss", false)) else (
				"ELITE " if bool(entity.get("elite", false)) else "")),
				str(entity["type"]), int(entity["hp"])]
			if float(entity.get("stagger_seconds", 0.0)) > 0.0:
				label.text += " [STAGGERED]"
			elif float(entity.get("snared_seconds", 0.0)) > 0.0:
				label.text += " [PINNED]"
			if float(entity.get("sunder_seconds", 0.0)) > 0.0:
				label.text += " [EXPOSED]"
		elif kind == "player":
			label.text = ("%s%s" % [
				("OUTLAW " if bool(entity.get("outlaw", false)) else "") + (("[%s] " % str(entity.get("faction", "")).capitalize()) if bool(entity.get("faction_flagged", false)) else ""), str(entity["name"])]) if entity["alive"] else "%s (dead)" % entity["name"]
		elif kind == "bag":
			label.text = LootLabel.for_bag(entity)
			label.visible = not label.text.is_empty()
	if kind == "bag":
		LootBeam.update(_nodes[key], entity)
	if kind == "bag":
		# Gold = available to your party, grey = reserved, brown = public.
		var loot_mesh: MeshInstance3D = _nodes[key].get_child(0)
		var loot_material: StandardMaterial3D = loot_mesh.material_override
		if bool(entity.get("supply_drop", false)):
			loot_material.albedo_color = (Color(0.91, 0.33, 0.16)
				if int(entity.get("guards_remaining", 0)) > 0 else Color(0.20, 0.73, 0.96))
		elif bool(entity.get("reserved", false)):
			loot_material.albedo_color = (
				Color(0.96, 0.69, 0.22) if bool(entity.get("can_loot", false))
				else Color(0.43, 0.47, 0.51))
		else:
			loot_material.albedo_color = Color(0.64, 0.42, 0.23)
	if kind == "barricade":
		# The tier's wall model, turned to its facing, darkening as it is damaged.
		var barricade_mesh: MeshInstance3D = _nodes[key].get_node("Wall")
		var tier: int = Structures.tier_of(entity)
		var piece: String = str(entity.get("piece", ""))
		if piece == "door" and bool(entity.get("open", true)):
			piece = "door_open" # An open door shows the empty frame.
		if piece == "lamp" and not _nodes[key].has_node("Light"):
			var glow := OmniLight3D.new()
			glow.name = "Light"
			glow.position = Vector3(0, 1.2, 0)
			glow.light_color = Color(1.0, 0.72, 0.4)
			glow.light_energy = 1.6
			glow.omni_range = 9.0
			glow.shadow_enabled = false
			_nodes[key].add_child(glow)
		if int(barricade_mesh.get_meta("tier", 0)) != tier or str(barricade_mesh.get_meta("piece", "")) != piece:
			barricade_mesh.set_meta("tier", tier)
			barricade_mesh.set_meta("piece", piece)
			barricade_mesh.mesh = piece_mesh(piece, tier) if piece != "" else wall_mesh(tier)
			if barricade_mesh.material_overlay == null:
				var wear := StandardMaterial3D.new()
				wear.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				wear.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				barricade_mesh.material_overlay = wear
		_nodes[key].rotation.y = float(entity.get("yaw", 0.0))
		var fraction: float = clampf(float(entity.get("hp", 0.0)) / maxf(1.0, Structures.max_health(tier)), 0.0, 1.0)
		(barricade_mesh.material_overlay as StandardMaterial3D).albedo_color = Color(0.08, 0.06, 0.05, (1.0 - fraction) * 0.6)
	if kind == "zombie":
		# A zombie that has locked on to someone flushes red.
		var model: Node3D = _nodes[key].get_node("Model")
		var base: Color = zombie_look(str(entity["type"]))["tint"]
		if bool(entity.get("raid_enraged", false)):
			base = Color(1.0, 0.12, 0.12)
		elif bool(entity.get("raid_boss", false)):
			base = Color(0.92, 0.2, 0.63)
		elif bool(entity.get("elite", false)):
			base = Color(0.98, 0.65, 0.18)
		var blocked: bool = bool(entity.get("melee_blocked", false))
		# The native tag store is now the source for this visual cue when available.
		# The snapshot fallback keeps stock Godot clients fully compatible.
		var staggered: bool = EngineFeatures.runtime_effect_remaining(_nodes[key],
			"Runtime.Status.Staggered", float(entity.get("stagger_seconds", 0.0))) > 0.0
		var pinned: bool = EngineFeatures.runtime_effect_remaining(_nodes[key],
			"Runtime.Status.Snared", float(entity.get("snared_seconds", 0.0))) > 0.0
		var exposed: bool = EngineFeatures.runtime_effect_remaining(_nodes[key],
			"Runtime.Status.Sundered", float(entity.get("sunder_seconds", 0.0))) > 0.0
		var wound_phase: String = str(entity.get("wound_phase", ""))
		var fallback_resolve: int = int(entity.get("resolve_stacks", 0)) if float(entity.get("resolve_seconds", 0.0)) > 0.0 else 0
		var resolve: bool = EngineFeatures.runtime_stack_count(_nodes[key],
			"Runtime.Status.Resolve", fallback_resolve) >= 2 and EngineFeatures.runtime_effect_remaining(
			_nodes[key], "Runtime.Status.Resolve", float(entity.get("resolve_seconds", 0.0))) > 0.0
		var tint: Color = base.lerp(ALERT_TINT, 0.45) if int(entity["state"]) >= 2 else base
		if wound_phase == "limping":
			tint = base.lerp(Color(0.54, 0.52, 0.66), 0.65)
		elif wound_phase == "frenzied":
			tint = base.lerp(Color(1.0, 0.19, 0.1), 0.78)
		if resolve:
			tint = base.lerp(Color(0.74, 0.42, 0.95), 0.65)
		if exposed:
			tint = base.lerp(Color(0.96, 0.42, 0.14), 0.65)
		if blocked:
			tint = base.lerp(Color(0.94, 0.75, 0.38), 0.62)
		if pinned:
			tint = base.lerp(Color(1.0, 0.84, 0.25), 0.65)
		if staggered:
			tint = base.lerp(Color(0.38, 0.8, 1.0), 0.7)
		model.set_tint(tint)
		model.set_zombie_state(int(entity["state"]))
	# Snapshot-driven priority is purely visual: never changes server AI or damage.
	if kind == "zombie":
		_apply_combat_animation_priority(_nodes[key].get_node("Model"), kind, entity)
	if kind == "player":
		_nodes[key].get_node("HandFlare").set_burning(bool(entity.get("flare_lit", false)) and bool(entity.get("alive", false)))
		var bike = _nodes[key].get_node("TrailBike")
		bike.set_panniers(bool(entity.get("bike_panniers", false)))
		bike.set_lamp(bool(entity.get("bike_lamp_lit", false)))
		bike.set_riding(bool(entity.get("mounted", false)) and bool(entity.get("alive", false)))
		var player_model: Node3D = _nodes[key].get_node("Model")
		if player_model.pack_mode:
			# Sneaking and riding are real poses; the weapon they carry is in their hand.
			player_model.set_stance(bool(entity.get("crouching", false)), bool(entity.get("mounted", false)))
			# What they are busy with shows as the pose and the tool in hand: a rod held out, an axe at a tree.
			var doing: String = str(entity.get("doing", ""))
			player_model.set_action_loop({"fish": "Idle_Torch_Loop", "chop": "TreeChopping_Loop", "harvest": "Farm_Harvest"}.get(doing, ""))
			player_model.set_weapon({"fish": "fishing_rod", "chop": "axe_1"}.get(doing, str(entity.get("weapon", ""))))
			player_model.set_gear(entity.get("gear", {}) if entity.get("gear", {}) is Dictionary else {})
		else:
			player_model.scale = Vector3(1.0, 0.72 if bool(entity.get("crouching", false)) else 1.0, 1.0)
		if player_model.pack_mode:
			player_model.set_dead(not bool(entity["alive"])) # A dead player lies down instead of vanishing.
		else:
			player_model.visible = bool(entity["alive"])


func _make(kind: String, entity: Dictionary) -> Node3D:
	var root := Node3D.new()
	if kind == "acid_pool":
		var puddle := MeshInstance3D.new()
		var pool_disk := CylinderMesh.new()
		pool_disk.top_radius = float(entity.get("radius", 2.4))
		pool_disk.bottom_radius = pool_disk.top_radius
		pool_disk.height = 0.04
		puddle.mesh = pool_disk
		puddle.position.y = 0.07
		var poison := ShaderMaterial.new()
		poison.shader = preload("res://shaders/toxic_pool.gdshader")
		poison.set_shader_parameter("liquid", preload("res://assets/gore/poison_liquid.png"))
		poison.set_shader_parameter("radius", pool_disk.top_radius)
		puddle.material_override = poison
		root.add_child(puddle)
		return root
	if kind == "ember_pool":
		var embers := MeshInstance3D.new()
		var shape := CylinderMesh.new()
		shape.top_radius = float(entity.get("radius", 3.0))
		shape.bottom_radius = shape.top_radius
		shape.height = 0.06
		embers.mesh = shape
		embers.position.y = 0.10
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1.0, 0.36, 0.07, 0.43)
		embers.material_override = mat
		root.add_child(embers)
		var light := OmniLight3D.new()
		light.position.y = 0.8
		light.light_color = Color(1.0, 0.32, 0.08)
		light.light_energy = 0.55
		light.omni_range = 4.5
		light.shadow_enabled = false
		root.add_child(light)
		return root
	if kind == "spit_warning":
		var warning := MeshInstance3D.new()
		var disk := CylinderMesh.new()
		disk.top_radius = float(entity.get("radius", 2.4))
		disk.bottom_radius = disk.top_radius
		disk.height = 0.06
		warning.mesh = disk
		warning.position.y = 0.08
		var chemical := StandardMaterial3D.new()
		chemical.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		chemical.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		chemical.albedo_color = Color(0.48, 1.0, 0.18, 0.38)
		warning.material_override = chemical
		root.add_child(warning)
		return root
	if kind == "barricade":
		var barricade := MeshInstance3D.new()
		barricade.name = "Wall"
		root.add_child(barricade)
		return root
	if kind == "fish_trap":
		var bobber := MeshInstance3D.new()
		var shape := CylinderMesh.new()
		shape.top_radius = 0.42
		shape.bottom_radius = 0.45
		shape.height = 0.22
		bobber.mesh = shape
		bobber.position.y = 0.12
		var orange := StandardMaterial3D.new()
		orange.albedo_color = Color(0.83, 0.49, 0.15)
		bobber.material_override = orange
		root.add_child(bobber)
		var net := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(1.12, 0.07, 1.12)
		net.mesh = mesh
		net.position.y = 0.015
		var gray := StandardMaterial3D.new()
		gray.albedo_color = Color(0.30, 0.36, 0.25)
		net.material_override = gray
		root.add_child(net)
		var label := Label3D.new()
		label.name = "Label"
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 18
		label.pixel_size = 0.007
		label.position.y = 1.0
		root.add_child(label)
		return root
	if kind == "snare":
		var tripwire := MeshInstance3D.new()
		var bar := BoxMesh.new()
		bar.size = Vector3(1.8, 0.12, 0.22)
		tripwire.mesh = bar
		tripwire.position.y = 0.08
		var metal := StandardMaterial3D.new()
		metal.albedo_color = Color(0.78, 0.53, 0.22)
		tripwire.material_override = metal
		root.add_child(tripwire)
		var label := Label3D.new()
		label.name = "Label"
		label.text = "SNARE"
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 18
		label.pixel_size = 0.006
		label.position.y = 0.7
		root.add_child(label)
		return root
	if kind == "smoke":
		var cloud := MeshInstance3D.new()
		var shape := SphereMesh.new()
		shape.radius = float(entity.get("radius", 4.5))
		shape.height = 3.2
		shape.radial_segments = 24
		shape.rings = 12
		cloud.mesh = shape
		cloud.position.y = 1.6
		var haze := StandardMaterial3D.new()
		haze.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		haze.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		haze.albedo_color = Color(0.52, 0.57, 0.58, 0.28)
		haze.cull_mode = BaseMaterial3D.CULL_DISABLED
		cloud.material_override = haze
		root.add_child(cloud)
		return root
	if kind == "decoy":
		var clacker := MeshInstance3D.new()
		var shape := CylinderMesh.new()
		shape.top_radius = 0.22
		shape.bottom_radius = 0.3
		shape.height = 0.26
		clacker.mesh = shape
		clacker.position.y = 0.18
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(0.98, 0.68, 0.16)
		clacker.material_override = material
		root.add_child(clacker)
		var label := Label3D.new()
		label.text = "NOISE LURE"
		label.name = "Label"
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 18
		label.pixel_size = 0.006
		label.position.y = 1.0
		root.add_child(label)
		return root
	if kind == "shelter":
		var canopy := MeshInstance3D.new()
		var roof := BoxMesh.new()
		roof.size = Vector3(3.0, 0.12, 2.6)
		canopy.mesh = roof
		canopy.position.y = 1.8
		var canvas := StandardMaterial3D.new()
		canvas.albedo_color = Color(0.31, 0.42, 0.29)
		canopy.material_override = canvas
		root.add_child(canopy)
		for dx in [-1.25, 1.25]:
			for dz in [-1.08, 1.08]:
				var pole := MeshInstance3D.new()
				var pole_mesh := CylinderMesh.new()
				pole_mesh.top_radius = 0.045
				pole_mesh.bottom_radius = 0.06
				pole_mesh.height = 1.75
				pole.mesh = pole_mesh
				pole.position = Vector3(dx, 0.89, dz)
				var wood := StandardMaterial3D.new()
				wood.albedo_color = Color(0.35, 0.24, 0.16)
				pole.material_override = wood
				root.add_child(pole)
		return root
	if kind == "plot":
		root.add_child(FarmPlotVisual.make(str(entity.get("crop", "carrot"))))
		return root
	if kind == "campfire":
		var wood := MeshInstance3D.new()
		var wood_mesh := CylinderMesh.new()
		wood_mesh.top_radius = 0.42
		wood_mesh.bottom_radius = 0.5
		wood_mesh.height = 0.22
		wood.mesh = wood_mesh
		wood.position.y = 0.13
		var wood_material := StandardMaterial3D.new()
		wood_material.albedo_color = Color(0.32, 0.18, 0.09)
		wood.material_override = wood_material
		root.add_child(wood)
		# Animated HDR flame, flickering light, embers and heat haze (High/Ultra).
		var fire := CampfireFx.new()
		fire.build(GraphicsQuality.level(),
			str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")))
		root.add_child(fire)
		return root
	if kind == "raid_warning":
		# Flat translucent danger disc. No physics body, network authority or
		# client damage calculation; the server alone resolves the timed slam.
		var circle := MeshInstance3D.new()
		var shape := CylinderMesh.new()
		shape.top_radius = float(entity.get("radius", 5.0))
		shape.bottom_radius = shape.top_radius
		shape.height = 0.06
		shape.radial_segments = 48
		circle.mesh = shape
		circle.position.y = 0.16
		var warning_material := StandardMaterial3D.new()
		warning_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		warning_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		warning_material.albedo_color = Color(0.98, 0.12, 0.36, 0.30)
		warning_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		circle.material_override = warning_material
		root.add_child(circle)
		return root
	if kind == "bag":
		var mesh := MeshInstance3D.new()
		if Assets.has_village():
			mesh.mesh = Assets.village_mesh("EA03_Prop_Container_Basket_01a")
			mesh.scale = Vector3.ONE * 1.8
			var basket_material := mesh.mesh.surface_get_material(0)
			mesh.material_override = basket_material.duplicate() if basket_material is StandardMaterial3D else StandardMaterial3D.new()
		else:
			mesh.mesh = Meshes.get_mesh("bag")
			mesh.material_override = StandardMaterial3D.new()
		root.add_child(mesh)
		var label := Label3D.new()
		label.name = "Label"
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.pixel_size = 0.008
		label.font_size = 24
		label.outline_size = 8
		label.position.y = 1.3
		label.visible = false
		root.add_child(label)
		root.add_child(LootBeam.make())
		return root
	root.add_child(BlobShadow.make(BlobShadow.wanted(bool(GraphicsQuality.profile(GraphicsQuality.level())["shadows"]))))
	var model := CharacterModel.new()
	model.name = "Model"
	var height := 2.0
	if kind == "zombie":
		var look: Dictionary = zombie_look(str(entity["type"]))
		var zombie_model: String = look["model"]
		if entity["type"] == "walker" and int(entity["id"]) % 2 == 1:
			zombie_model = "Orc_Female"
		model.setup(look["tint"], float(look["scale"]) * (
			1.75 if bool(entity.get("raid_boss", false)) else (
			1.18 if bool(entity.get("elite", false)) else 1.0)), look["walk"], zombie_model, true, int(entity["id"]))
		height = 1.3 * float(look["scale"]) * (1.75 if bool(entity.get("raid_boss", false)) else 1.0)
	else:
		var hue := float(abs(int(entity["id"]) * 2654435761 % 1000)) / 1000.0
		var character: String = Assets.CHARACTER_NAMES[int(abs(int(entity["id"]))) % Assets.CHARACTER_NAMES.size()]
		model.setup(Color.WHITE if Assets.has_characters() else Color.from_hsv(hue, 0.45, 1.0), 2.0, 1.0, character, false, int(abs(int(entity["id"]))) / Assets.CHARACTER_NAMES.size())
	model.set_wetness_step(_wetness_step)
	root.add_child(model)
	if _world != null and GraphicsQuality.level() >= 2: # High and Ultra; no-op without the native class.
		model.enable_foot_placement(_world.height_at)
	_register_anim_lod(model)
	if kind == "zombie":
		EngineFeatures.tag_node(root, ["Enemy.Infected.%s" % String(entity["type"]).capitalize()])
	else:
		EngineFeatures.tag_node(root, ["Player"])
	if kind == "player":
		var bike := TrailBikeVisual.new()
		bike.name = "TrailBike"
		root.add_child(bike)
		var flare := HandFlareVisual.new()
		flare.name = "HandFlare"
		root.add_child(flare)
	var label := Label3D.new()
	label.name = "Label"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.009
	label.font_size = 28
	label.outline_size = 8
	label.position = Vector3(0, height + 0.5, 0)
	root.add_child(label)
	return root


## Animation update-rate LOD for character animators: the native controller if the engine has it, else the script fallback.
func _register_anim_lod(model: Node) -> void:
	var animator: AnimationPlayer = model.get("animator")
	if animator == null:
		return
	# One owner per animator: without the native controller, CharacterModel's own
	# crowd tiers (set_anim_lod) already throttle updates, so a second script LOD
	# would advance the same AnimationPlayer twice.
	if not EngineFeatures.has("AnimationLODController"):
		return
	model.set("external_anim_lod", true)
	if _anim_lod == null:
		var lod_scale := AnimLod.distance_scale(GraphicsQuality.level())
		_anim_lod = ClassDB.instantiate("AnimationLODController")
		_anim_lod.near_distance = AnimLod.NEAR * lod_scale
		_anim_lod.mid_distance = AnimLod.MID * lod_scale
		_anim_lod.far_distance = AnimLod.FAR * lod_scale
		_anim_lod.name = "AnimLod"
		add_child(_anim_lod)
		if _anim_lod.has_method("set_max_priority_mixers"):
			_priority_quality = GraphicsQuality.level()
			_anim_lod.call("set_max_priority_mixers", CombatAnimationPriority.slots(_priority_quality))
	if _anim_lod is AnimLod:
		_anim_lod.register(animator, model as Node3D)
	else:
		_anim_lod.register_mixer(animator) # Native: skips inactive/paused (ragdolled) animators itself.
		# The upper-body attack layer is a separate AnimationPlayer: register it
		# with the SAME scheduler, otherwise distant actors animate it at 60 Hz.
		var upper_layer: AnimationPlayer = model.get("_layer")
		if upper_layer != null:
			# The body animator alone controls shared SkeletonModifier3D culling.
			_anim_lod.register_mixer(upper_layer, false)


## Sync the same priority hint to both native animation LOD and stock Godot's
## existing animation-tick fallback. A per-model meta flag avoids repeated
## native method dispatches when successive network snapshots are unchanged.
func _apply_combat_animation_priority(model: Node, kind: String, entity: Dictionary) -> void:
	if model == null:
		return
	var priority: bool = CombatAnimationPriority.wants_priority(kind, entity)
	if bool(model.get_meta("aa_combat_animation_priority", false)) == priority:
		return
	model.set_meta("aa_combat_animation_priority", priority)
	if _anim_lod != null and _anim_lod.has_method("set_mixer_high_priority"):
		var animator: AnimationPlayer = model.get("animator")
		if animator != null:
			_anim_lod.call("set_mixer_high_priority", animator, priority)
		var upper_layer: AnimationPlayer = model.get("_layer")
		if upper_layer != null:
			_anim_lod.call("set_mixer_high_priority", upper_layer, priority)


func _unregister_anim_lod(node: Node) -> void:
	var model := node.get_node_or_null("Model")
	if _anim_lod == null or model == null:
		return
	var animator: AnimationPlayer = model.get("animator")
	if animator == null:
		return
	if _anim_lod is AnimLod:
		_anim_lod.unregister(animator)
	else:
		_anim_lod.unregister_mixer(animator)
		var upper_layer: AnimationPlayer = model.get("_layer")
		if upper_layer != null:
			_anim_lod.unregister_mixer(upper_layer)


## A zombie that just left the snapshot (killed) falls as a ragdoll instead of vanishing, within the tier budget.
func _try_ragdoll(node: Node3D) -> bool:
	var fresh := 0
	for corpse in _corpses:
		if float(corpse["age"]) < Ragdoll.SETTLE_SECONDS:
			fresh += 1
	if _world == null or fresh >= Ragdoll.budget(GraphicsQuality.level()):
		return false
	var model := node.get_node_or_null("Model")
	if model == null or not model.has_method("start_ragdoll"):
		return false
	var push := -node.global_transform.basis.z * 2.5 + Vector3.UP * 1.2
	if model.start_ragdoll(push) == null:
		return false
	for child in node.get_children():
		if child != model and child is Node3D:
			(child as Node3D).visible = false # Names, rings and markers go with the life.
	var p := node.position
	var ground := Ragdoll.ground_patch(p.x, float(_world.height_at(p.x, p.z)), p.z, _world.height_at)
	add_child(ground)
	_corpses.append({"node": node, "ground": ground, "age": 0.0, "burn": null, "model": model})
	return true


## Bodies stay where they fell while they still carry loot, glowing so you know to search them.
func _update_corpses(delta: float) -> void:
	for i in range(_corpses.size() - 1, -1, -1):
		var corpse: Dictionary = _corpses[i]
		corpse["life"] = float(corpse.get("life", 0.0)) + delta
		if not corpse.has("bag") and float(corpse["life"]) < 3.0 and is_instance_valid(corpse["node"]):
			_link_corpse_bag(corpse)
		var bag_key: String = str(corpse.get("bag", ""))
		var holds_loot: bool = bag_key != "" and _nodes.has(bag_key) and float(corpse["life"]) < CORPSE_MAX_SECONDS
		_set_corpse_glow(corpse, holds_loot)
		if holds_loot:
			# Keep the body settled and searchable; the basket stand-in is hidden behind it.
			corpse["age"] = minf(float(corpse["age"]) + delta, Ragdoll.SETTLE_SECONDS - 0.01)
			continue
		corpse["age"] = float(corpse["age"]) + delta
		var burn_t: float = CorpseBurn.progress(float(corpse["age"]), Ragdoll.SETTLE_SECONDS, Ragdoll.SINK_SECONDS)
		if burn_t > 0.0:
			if corpse["burn"] == null and is_instance_valid(corpse["model"]):
				corpse["burn"] = CorpseBurn.start(corpse["model"])
			if corpse["burn"] != null:
				(corpse["burn"] as ShaderMaterial).set_shader_parameter("progress", burn_t)
		if corpse["age"] > Ragdoll.SETTLE_SECONDS:
			# The ground patch sinks and the body settles into the earth with it, then both go.
			(corpse["ground"] as Node3D).position.y -= delta * 0.5
		if corpse["age"] > Ragdoll.SETTLE_SECONDS + Ragdoll.SINK_SECONDS:
			(corpse["node"] as Node).queue_free()
			(corpse["ground"] as Node).queue_free()
			_corpses.remove_at(i)


func _process(delta: float) -> void:
	# Native full-rate combat slots follow the same live 4-tier graphics budget.
	# The setter is called only on quality transitions, not each render frame.
	if _anim_lod != null and _anim_lod.has_method("set_max_priority_mixers"):
		var quality: int = GraphicsQuality.level()
		if _priority_quality != quality:
			_priority_quality = quality
			_anim_lod.call("set_max_priority_mixers", CombatAnimationPriority.slots(quality))
	_update_corpses(delta)
	var blend := 1.0 - exp(-14.0 * delta)
	if _render_time >= 0.0:
		# One native/fallback visual clock serves every entity in this frame.
		# Rate is always nonnegative and never predicts beyond server data.
		_render_time = NetworkJitterBuffer.advance_clock(
			_render_time, _snapshot_time, _snapshot_buffer.delay, delta, self)
	var anim_models: Array = []
	for key in _nodes:
		var node: Node3D = _nodes[key]
		var periodic_pulses: Dictionary = {}
		if key.begins_with("zombie:") or key.begins_with("player:"):
			periodic_pulses = EngineFeatures.tick_runtime_effects(node, delta)
		var target: Dictionary = _targets[key]
		var sampled: Array = _sample(key)
		if sampled.is_empty():
			node.position = node.position.lerp(target["position"], blend)
		else:
			node.position = sampled[0]
			target["yaw"] = sampled[1]
		if key.begins_with("bag"):
			LootDropBounce.apply(node, delta, GraphicsQuality.level())
		if not (key.begins_with("bag") or key.begins_with("barricade") or key.begins_with("campfire") or key.begins_with("plot") or key.begins_with("shelter") or key.begins_with("smoke") or key.begins_with("snare") or key.begins_with("fish_trap") or key.begins_with("decoy") or key.begins_with("pool") or key.begins_with("ember") or key.begins_with("spit")):
			node.rotation.y = lerp_angle(node.rotation.y, target["yaw"], blend)
			var model: Node3D = node.get_node("Model")
			model.update_motion(delta)
			# Gameplay Cues coalesce replicated status starts and periodic pulses.
			# Dispatch is cosmetic only; no combat events or RPCs originate here.
			if key.begins_with("zombie:"):
				var cues: Array = GameplayCues.frame_events(node, periodic_pulses)
				if GraphicsQuality.level() >= 2 and model.has_method("status_pulse"):
					for cue in cues:
						if str(cue.get("event", "")) == "stopped":
							continue
						var pulse_color: Color = GameplayCues.pulse_color(str(cue.get("tag", "")))
						if pulse_color.a > 0.0:
							model.call("status_pulse", pulse_color)
							break
			anim_models.append(model)
			if key.begins_with("player:"):
				var bike = node.get_node("TrailBike")
				if bike.visible:
					bike.set_riding(true, model.speed, delta)
	_apply_leaps(delta)
	# Animation LOD / crowd budget, foot IK terrain source and head look-at (character_anim.gd).
	CharacterAnim.apply_crowd(anim_models, get_viewport().get_camera_3d(), GraphicsQuality.level(),
		_world.height_at if _world != null else Callable())


## Position and facing of a moving entity at the render time, between the two samples around it; past the newest
## sample it holds there (a short gap in packets is a pause, not a guess). [] when there is no history.
func _sample(key: String) -> Array:
	var history: Array = _history.get(key, [])
	if history.is_empty():
		return []
	if history.size() == 1 or _render_time <= float(history[0][0]):
		return [history[0][1], history[0][2]]
	for i in range(history.size() - 1, 0, -1):
		var older: Array = history[i - 1]
		var newer: Array = history[i]
		if _render_time >= float(older[0]):
			var span: float = maxf(float(newer[0]) - float(older[0]), 0.001)
			var k: float = clampf((_render_time - float(older[0])) / span, 0.0, 1.0)
			# Performance retains the old two-point smoothing with no
			# additional velocity history reads or cubic GDScript work.
			if GraphicsQuality.level() == 0:
				return [(older[1] as Vector3).lerp(newer[1], k),
					lerp_angle(float(older[2]), float(newer[2]), k)]
			# Bounded Hermite reconstructs smooth visual speed from the
			# two neighboring server snapshots. Teleports and missing
			# timestamps keep the original safe linear behavior.
			var previous: Array = history[i - 2] if i >= 2 else []
			var following: Array = history[i + 1] if i + 1 < history.size() else []
			var host: Node3D = _nodes.get(key) as Node3D
			var position: Vector3 = SnapshotSmoothing.sample_position(
				previous, older, newer, following, k, host)
			# UE-style simulated-proxy angular smoothing shares the trusted
			# server snapshot history, without extrapolation or facing overshoot.
			var yaw: float = SnapshotSmoothing.sample_yaw(
				previous, older, newer, following, k, _rotation_smoother)
			return [position, yaw]
	return [history[-1][1], history[-1][2]]


## A swing or a shot by another player.
func play_attack(peer_id: int, weapon_id: String, ranged: bool) -> void:
	var key := "player:%d" % peer_id
	if _nodes.has(key):
		_nodes[key].get_node("Model").play_action(attack_animation(weapon_id, ranged))


## Which animation a weapon uses.
static func attack_animation(weapon_id: String, ranged: bool) -> String:
	if ranged:
		return "Pistol_Shoot"
	if weapon_id == "":
		return "Punch_Jab" if randf() < 0.55 else "Punch_Cross"
	match CharacterModel.weapon_family(weapon_id):
		"sledgehammer", "purifier_maul", "sunder_axe":
			return "Sword_Regular_C" # Big overhead blows.
		"spear":
			return "Sword_Regular_B"
		"restoration_staff":
			return "Spell_Simple_Shoot"
	return "Sword_Regular_A" if randf() < 0.5 else "Sword_Regular_B"


## Any one-shot animation on a player or zombie drawn here.
func play_action_on(kind: String, id: int, animation_name: String) -> void:
	var key := "%s:%d" % [kind, id]
	if _nodes.has(key) and _nodes[key].has_node("Model"):
		_nodes[key].get_node("Model").play_action(animation_name, 1.2)


## A flinch on whoever was struck.
## The character model of an entity, or null.
func model_of(kind: String, id: int) -> Node3D:
	var key := "%s:%d" % [kind, id]
	if _nodes.has(key) and is_instance_valid(_nodes[key]) and _nodes[key].has_node("Model"):
		return _nodes[key].get_node("Model") as Node3D
	return null


func play_hit(kind: String, id: int, heavy: bool = false) -> void:
	var key := "%s:%d" % [kind, id]
	if _nodes.has(key) and _nodes[key].has_node("Model"):
		var model = _nodes[key].get_node("Model")
		if model.has_method("play_hit"):
			model.play_hit(heavy)


## Nearest zombie / loot bag / player node to a ground point (for hover outlines).
func nearest_hoverable(point: Vector3, radius: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = radius * radius
	for key in _nodes:
		var kind: String = str(key).get_slice(":", 0)
		if kind != "zombie" and kind != "bag" and kind != "player":
			continue
		var node := _nodes[key] as Node3D
		if node == null or not node.visible:
			continue
		var p: Vector3 = node.global_position
		var d: float = Vector2(p.x - point.x, p.z - point.z).length_squared()
		if d < best_d:
			best_d = d
			best = {"node": node, "kind": kind}
	return best


## Up to `count` nearest visible nodes of one kind ("zombie", "player", "bag") to a point.
func nearest_of_kind(point: Vector3, kind: String, count: int, radius: float) -> Array[Node3D]:
	var found: Array = []
	var prefix := kind + ":"
	for key in _nodes:
		if not str(key).begins_with(prefix):
			continue
		var node := _nodes[key] as Node3D
		if node == null or not node.visible:
			continue
		var d: float = node.global_position.distance_to(point)
		if d <= radius:
			found.append([d, node])
	found.sort_custom(func(a, b): return a[0] < b[0])
	var result: Array[Node3D] = []
	for i in mini(count, found.size()):
		result.append(found[i][1])
	return result


func _link_corpse_bag(corpse: Dictionary) -> void:
	var at: Vector3 = (corpse["node"] as Node3D).position
	for key in _nodes:
		if str(key).begins_with("bag:") and Vector2(_nodes[key].position.x - at.x, _nodes[key].position.z - at.z).length() < 1.6:
			corpse["bag"] = key
			var basket = _nodes[key].get_child(0)
			if basket is MeshInstance3D:
				(basket as MeshInstance3D).visible = false # The body itself is what you loot.
			return


func _set_corpse_glow(corpse: Dictionary, on: bool) -> void:
	if bool(corpse.get("glowing", false)) == on or not is_instance_valid(corpse["model"]):
		return
	corpse["glowing"] = on
	var overlay: ShaderMaterial = null
	if on:
		overlay = ShaderMaterial.new()
		overlay.shader = LOOT_GLOW_SHADER
	for mesh in (corpse["model"] as Node).find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).material_overlay = overlay


## A tree ambusher's drop: an arc from the branch to the ground in front of its prey.
func leap(id: int, from: Vector3, to: Vector3) -> void:
	var key := "zombie:%d" % id
	if not _nodes.has(key):
		return
	_leaps[key] = {"from": from, "to": to, "t": 0.0}
	play_hit("zombie", id, true)


func _apply_leaps(delta: float) -> void:
	for key in _leaps.keys():
		var leap_state: Dictionary = _leaps[key]
		leap_state["t"] = float(leap_state["t"]) + delta
		var k: float = clampf(float(leap_state["t"]) / LEAP_SECONDS, 0.0, 1.0)
		if not _nodes.has(key) or k >= 1.0:
			_leaps.erase(key)
			continue
		var p: Vector3 = (leap_state["from"] as Vector3).lerp(leap_state["to"], k)
		p.y += sin(k * PI) * 1.2 # Up off the branch, then down hard.
		_nodes[key].position = p


## A short red "!" over an infected that is winding up a leap or charge.
func telegraph(id: int, seconds: float, charge: bool) -> void:
	var key := "zombie:%d" % id
	if not _nodes.has(key):
		return
	var mark := Label3D.new()
	mark.text = "!!" if charge else "!"
	mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mark.no_depth_test = true
	mark.pixel_size = 0.012
	mark.font_size = 64
	mark.outline_size = 12
	mark.modulate = Color(1.0, 0.22, 0.12)
	mark.position = Vector3(0, 2.35, 0)
	_nodes[key].add_child(mark)
	var tween := mark.create_tween()
	tween.tween_property(mark, "scale", Vector3.ONE * 1.4, maxf(seconds, 0.1) * 0.5).set_trans(Tween.TRANS_BACK)
	tween.tween_property(mark, "modulate:a", 0.0, maxf(seconds, 0.1) * 0.5)
	tween.tween_callback(mark.queue_free)

extends Node3D
## Ground blood splats (Diablo / Left 4 Dead): pooled native Decals project a
## procedurally generated splat onto terrain under hits, then fade out. Decals
## need Forward+/Mobile; Compatibility and Performance skip them entirely.

const DecalVisibility = preload("res://scripts/client/decal_visibility_policy.gd")
const EngineFeatures = preload("res://scripts/client/engine_features.gd")

const POOL_SIZE := 32
const LIFETIME := 24.0
const FADE := 4.0

var _pool: Array[Decal] = []
var _age: Array[float] = []
var _next := 0
static var _splat_tex: Texture2D
var _native_visibility: Object = EngineFeatures.make("DecalVisibilityAdmission3D")


## Splats per hit for a tier/renderer (0 = off).
static func enabled(level: int, rendering_method: String) -> bool:
	return level >= 1 and rendering_method != "gl_compatibility"


## Zombie ichor is dark olive (matching its spray), player blood is red.
static func tint(zombie: bool) -> Color:
	return Color(0.16, 0.2, 0.06) if zombie else Color(0.42, 0.02, 0.02)


static func splat_texture() -> Texture2D:
	if _splat_tex != null:
		return _splat_tex
	# A hand-painted CC0 splatter mask (white on alpha, tinted per decal); procedural fallback.
	if ResourceLoader.exists("res://assets/gore/blood_splatter.png"):
		# Crop to the painted part so the splat fills the decal.
		var source: Image = (load("res://assets/gore/blood_splatter.png") as Texture2D).get_image()
		if source.is_compressed():
			source.decompress()
		var used: Rect2i = source.get_used_rect()
		var side: int = maxi(used.size.x, used.size.y)
		var square := Rect2i(used.get_center() - Vector2i(side, side) / 2, Vector2i(side, side)).intersection(Rect2i(Vector2i.ZERO, source.get_size()))
		var cropped: Image = source.get_region(square) if side > 8 else source
		cropped.generate_mipmaps()
		_splat_tex = ImageTexture.create_from_image(cropped)
		return _splat_tex
	var noise := FastNoiseLite.new()
	noise.frequency = 0.09
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var drops: Array[Vector3] = []
	for i in 7:
		drops.append(Vector3(rng.randf_range(10, 54), rng.randf_range(10, 54), rng.randf_range(2.0, 5.0)))
	for y in 64:
		for x in 64:
			var d: float = Vector2(x - 31.5, y - 31.5).length() / 22.0
			var a: float = clampf(1.0 - d + noise.get_noise_2d(x, y) * 0.55, 0.0, 1.0)
			for drop in drops:
				if Vector2(x - drop.x, y - drop.y).length() < drop.z:
					a = maxf(a, 0.9)
			a = smoothstep(0.35, 0.55, a)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_splat_tex = ImageTexture.create_from_image(img)
	return _splat_tex


func _ready() -> void:
	for i in POOL_SIZE:
		var d := Decal.new()
		d.size = Vector3(1.4, 1.2, 1.4)
		d.texture_albedo = splat_texture()
		d.visible = false
		d.cull_mask = 1
		d.distance_fade_enabled = true
		d.distance_fade_begin = 35.0
		d.distance_fade_length = 10.0
		add_child(d)
		_pool.append(d)
		_age.append(LIFETIME)


func splat(world, x: float, z: float, zombie: bool, damage: float) -> void:
	if world == null:
		return
	var s: float = clampf(0.6 + damage / 40.0, 0.6, 1.6)
	var ground: float = float(world.height_at(x, z))
	# Use the same 35m + 10m native distance fade and exact impact size.
	# Rejected distant hits never consume the shared 32-slot ring.
	if not DecalVisibility.can_project(self, Vector3(x, ground + 0.2, z),
			1.3 * s, 45.0, 3.0, _native_visibility):
		return
	var d := _pool[_next]
	_age[_next] = 0.0
	_next = (_next + 1) % POOL_SIZE
	d.size = Vector3(1.3 * s, 1.2, 1.3 * s)
	d.modulate = tint(zombie)
	d.albedo_mix = 0.9
	d.position = Vector3(x + randf_range(-0.3, 0.3), ground + 0.2, z + randf_range(-0.3, 0.3))
	d.rotation.y = randf() * TAU
	d.visible = true


func _process(delta: float) -> void:
	for i in POOL_SIZE:
		if _age[i] >= LIFETIME:
			continue
		_age[i] += delta
		var d := _pool[i]
		if _age[i] >= LIFETIME:
			d.visible = false
		elif _age[i] > LIFETIME - FADE:
			d.albedo_mix = 0.9 * (LIFETIME - _age[i]) / FADE


## Scorch mark (lightning strikes, explosions): a large sooty splat from the same pool.
func scorch(world, x: float, z: float, radius: float) -> void:
	if world == null:
		return
	var s: float = clampf(radius, 1.0, 6.0)
	var ground: float = float(world.height_at(x, z))
	# Large scorch projection volumes remain visible up to their radius
	# beyond the fade edge; tiny far-away splats do not take live slots.
	if not DecalVisibility.can_project(self, Vector3(x, ground + 0.4, z),
			s * 1.6, 45.0, 3.0, _native_visibility):
		return
	var d := _pool[_next]
	_age[_next] = 0.0
	_next = (_next + 1) % POOL_SIZE
	d.size = Vector3(s * 1.6, 2.0, s * 1.6)
	d.modulate = Color(0.05, 0.045, 0.04)
	d.albedo_mix = 0.9
	d.position = Vector3(x, ground + 0.4, z)
	d.rotation.y = randf() * TAU
	d.visible = true

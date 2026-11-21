extends Node3D
## Pooled projected impact decals (blood / infected ichor / scorch) — the Godot
## equivalent of Unity's URP Decal Projector and Unreal's deferred decals.
## A fixed ring buffer per quality tier bounds GPU cost; oldest decals are reused.

const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")
const DecalVisibility = preload("res://scripts/client/decal_visibility_policy.gd")
const EngineFeatures = preload("res://scripts/client/engine_features.gd")
const BUDGET := [0, 24, 48, 96] # Low, Medium, High, Ultra.
const LIFETIME := 40.0
const FADE := 6.0

var _pool: Array[Decal] = []
var _born: Array[float] = []
var _next := 0
var _clock := 0.0
var _textures := {}
var _level := -1
var _method := ""
var _native_visibility: Object = EngineFeatures.make("DecalVisibilityAdmission3D")


static func budget(level: int) -> int:
	return BUDGET[clampi(level, 0, BUDGET.size() - 1)]


## Decal projection is unsupported on the Compatibility backend. Do not
## create unused GPU scene instances there, regardless of quality override.
static func effective_budget(level: int, method: String) -> int:
	return 0 if method == "gl_compatibility" else budget(level)


## Large projection volumes cost screen fill rate. Limit distant splats,
## scaling the fade threshold with visual quality, as in other deferred engines.
static func draw_distance(level: int) -> float:
	return [0.0, 45.0, 65.0, 85.0][clampi(level, 0, 3)]


## Quantize an already-fading alpha to 8-bit precision, avoiding excessive
## renderer updates at high FPS without changing full-opacity lifetimes.
static func display_alpha(age: float) -> float:
	var alpha: float = alpha_for_age(age)
	return roundf(alpha * 255.0) / 255.0


## Opacity of a decal of the given age: full, then a linear fade over the last FADE seconds.
static func alpha_for_age(age: float) -> float:
	if age < 0.0:
		return 1.0
	return clampf((LIFETIME - age) / FADE, 0.0, 1.0)


static func splat_texture(seed: int) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var blobs: Array[Vector3] = [Vector3(32, 32, 14)]
	for i in 7:
		var a := rng.randf() * TAU
		var r := rng.randf_range(8.0, 20.0)
		blobs.append(Vector3(32 + cos(a) * r, 32 + sin(a) * r, rng.randf_range(3.0, 7.0)))
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var v := 0.0
			for b in blobs:
				v = maxf(v, 1.0 - Vector2(x - b.x, y - b.y).length() / b.z)
			image.set_pixel(x, y, Color(1, 1, 1, smoothstep(0.0, 0.25, v)))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


func configure(level: int) -> void:
	var method: String = str(RenderingServer.get_current_rendering_method())
	var wanted: int = effective_budget(level, method)
	while _pool.size() > wanted:
		_pool.pop_back().queue_free()
		_born.pop_back()
	while _pool.size() < wanted:
		var decal := Decal.new()
		decal.size = Vector3(1.2, 2.0, 1.2)
		decal.cull_mask = 1
		decal.visible = false
		decal.upper_fade = 0.3
		decal.lower_fade = 0.3
		decal.distance_fade_enabled = true
		decal.distance_fade_begin = draw_distance(level)
		decal.distance_fade_length = 12.0
		add_child(decal)
		_pool.append(decal)
		_born.append(-INF)
	# Existing projected decals inherit a changed graphics preset too.
	for decal in _pool:
		var new_begin: float = draw_distance(level)
		if not is_equal_approx(decal.distance_fade_begin, new_begin):
			decal.distance_fade_begin = new_begin
	_next = 0 if _pool.is_empty() else _next % _pool.size()


## Projects a splat onto whatever lies below `position` (terrain, floors, props).
func splat(position: Vector3, color: Color, size: float = 1.0) -> void:
	if _pool.is_empty():
		return
	# Unreal-style projected screen-size admission. Reject useless distant
	# impacts before texture generation, RNG, pool eviction and GPU updates.
	var current_quality: int = _level if _level >= 0 else GraphicsQuality.level()
	if not DecalVisibility.can_project(self, position, size,
			draw_distance(current_quality) + 12.0, 3.0, _native_visibility):
		return
	var key := randi() % 4
	if not _textures.has(key):
		_textures[key] = splat_texture(key + 1)
	var decal := _pool[_next]
	_born[_next] = _clock
	_next = (_next + 1) % _pool.size()
	decal.texture_albedo = _textures[key]
	decal.modulate = color
	# A recycled slot may have been almost transparent on its last life.
	# Restore full opacity before it becomes visible, not one frame later.
	decal.albedo_mix = 1.0
	decal.size = Vector3(size, 2.0, size)
	decal.position = position # The pool node sits at the world origin.
	decal.rotation.y = randf() * TAU
	decal.visible = true


func _process(delta: float) -> void:
	_clock += delta
	var quality: int = GraphicsQuality.level()
	var method: String = str(RenderingServer.get_current_rendering_method())
	if quality != _level or method != _method:
		_level = quality
		_method = method
		configure(_level)
	for i in _pool.size():
		var decal := _pool[i]
		if not decal.visible:
			continue
		var age: float = _clock - _born[i]
		if age >= LIFETIME:
			decal.visible = false
		elif age > LIFETIME - FADE:
			var alpha: float = display_alpha(age)
			if not is_equal_approx(alpha, decal.albedo_mix):
				decal.albedo_mix = alpha
		# Earlier lifetime is already fully opaque: no setter or server call.

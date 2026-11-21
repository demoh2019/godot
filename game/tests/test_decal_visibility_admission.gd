extends RefCounted
## Unreal-style decal screen coverage and actual impact/blood pool integration.
const Visibility = preload("res://scripts/client/decal_visibility_policy.gd")
const Impact = preload("res://scripts/client/impact_decals.gd")
const Blood = preload("res://scripts/client/blood_decals.gd")


func run(t) -> void:
	t.current = "near projectors survive, distant and subpixel decals are culled"
	var camera := Vector3(0, 2, 0)
	t.check(Visibility.should_spawn(camera, Vector3(0, 2, 2),
		1.0, 60.0, 1080.0, 60.0), "near contact preserves clear visuals")
	t.check(Visibility.should_spawn(camera, Vector3(0, 2, 30),
		1.0, 60.0, 1080.0, 60.0), "midrange decals remain visible")
	t.check(not Visibility.should_spawn(camera, Vector3(0, 2, 80),
		1.0, 60.0, 1080.0, 60.0), "distant projectors do not spend GPU slots")
	t.check(not Visibility.should_spawn(camera, Vector3(0, 2, 55),
		0.05, 60.0, 720.0, 60.0, 3.0),
		"subpixel impacts do not churn expensive textures")
	t.check(Visibility.should_spawn(camera, Vector3(0, 2, 55),
		1.4, 60.0, 720.0, 60.0, 3.0),
		"large scorches still project across the world")
	t.check(Visibility.should_spawn(camera, Vector3(0, 2, 60.4),
		1.0, 60.0, 1080.0, 60.0), "large partial volumes survive fade edge")
	t.check(not Visibility.should_spawn(camera, Vector3(0, 2, 60.6),
		1.0, 60.0, 1080.0, 60.0), "fully distant volume is culled")
	t.check(Visibility.should_spawn(camera, Vector3(0, 2, -3),
		1.0, 60.0, 1080.0, 60.0), "camera turning does not erase nearby marks")

	t.current = "invalid cameras and projection settings cannot allocate decals"
	for invalid in [NAN, INF, -INF]:
		t.check(not Visibility.should_spawn(camera, Vector3.ZERO,
			invalid, 60.0, 1080.0, 60.0), "invalid decal dimensions rejected")
		t.check(not Visibility.should_spawn(camera, Vector3.ZERO,
			1.0, invalid, 1080.0, 60.0), "invalid draw distances rejected")
		t.check(not Visibility.should_spawn(camera, Vector3.ZERO,
			1.0, 60.0, invalid, 60.0), "invalid viewport dimensions rejected")
	t.check(not Visibility.should_spawn(camera, Vector3.ZERO,
		1.0, 60.0, 1080.0, 171.0), "invalid FOV rejected")
	t.check(not Visibility.should_spawn(camera, Vector3.ZERO,
		1.0, 60.0, 1080.0, 60.0, 129.0), "unbounded pixel threshold rejected")
	t.check(not Visibility.should_spawn(Vector3(INF, 2, 0), Vector3.ZERO,
		1.0, 60.0, 1080.0, 60.0), "nonfinite camera rejected")
	t.check(not Visibility.should_spawn(camera, Vector3(10000001.0, 0, 0),
		1.0, 60.0, 1080.0, 60.0), "out-of-range world coordinates rejected")

	t.current = "native and stock-Godot policy agree over projection profiles"
	var native: Object = null
	if ClassDB.class_exists("DecalVisibilityAdmission3D"):
		native = ClassDB.instantiate("DecalVisibilityAdmission3D")
		t.check(native != null and native.has_method("should_spawn"),
			"registered native engine policy is callable")
	for size in [0.05, 0.2, 0.6, 1.0, 2.0, 6.0]:
		for distance in [0.0, 3.0, 20.0, 45.0, 65.0, 85.0, 120.0]:
			for fov in [40.0, 60.0, 90.0]:
				for height in [360.0, 720.0, 1080.0]:
					var at := Vector3(0, 2, distance)
					var scripted: bool = Visibility.should_spawn(camera, at,
						size, 85.0, height, fov, 3.0)
					if native != null:
						t.eq(bool(native.call("should_spawn", camera, at,
							size, 85.0, height, fov, 3.0)), scripted,
							"native/portable projection parity")
	t.current = "real impact pool keeps legacy behavior without a camera"
	var impacts := Impact.new()
	var reused := Decal.new()
	impacts.add_child(reused)
	impacts._pool.append(reused)
	impacts._born.append(-INF)
	t.check(Visibility.can_project(impacts, Vector3(500, 0, 500),
		1.0, 45.0, 3.0, native),
		"missing viewport/camera must preserve legacy projected impacts")
	impacts.splat(Vector3(2, 0.5, 3), Color.WHITE, 1.0)
	t.check(reused.visible and reused.albedo_mix == 1.0,
		"existing near impact pool recycling still renders correctly")
	impacts.free()

	t.current = "live impact/blood pools reject before slots, textures and RNG"
	var source: String = (Impact as Script).source_code
	var check_index: int = source.find("if not DecalVisibility.can_project(")
	var texture_index: int = source.find("var key := randi() % 4")
	t.check(check_index >= 0 and texture_index > check_index,
		"actual impact client avoids texture generation for rejected marks")
	t.check(source.contains("draw_distance(current_quality) + 12.0"),
		"impact admission matches native projectors' distance-fade range")
	var blood: String = (Blood as Script).source_code
	t.check(blood.count("if not DecalVisibility.can_project(") == 2,
		"both hit blood and explosion scorches use projected admission")
	t.check(blood.contains("1.3 * s, 45.0, 3.0") and
		blood.contains("s * 1.6, 45.0, 3.0"),
		"real blood and scorch sizes drive the GPU policy")

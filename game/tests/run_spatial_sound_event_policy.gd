extends SceneTree
## godot --headless --path game --script res://tests/run_spatial_sound_event_policy.gd
const Case = preload("res://tests/test_case.gd")
const Suite = preload("res://tests/test_spatial_sound_event_policy.gd")

func _initialize() -> void:
	var t := Case.new()
	Suite.new().run(t)
	for failure in t.failures:
		printerr("FAIL " + failure)
	print("SPATIAL SOUND TOTAL: %d checks, %d failures" % [t.checks, t.failures.size()])
	quit(1 if t.failures.size() > 0 else 0)

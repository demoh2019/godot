extends SceneTree
## Standalone headless network yaw smoothing regression.
## godot --headless --path game --script res://tests/run_snapshot_rotation_smoothing.gd
const TestCase = preload("res://tests/test_case.gd")
const Suite = preload("res://tests/test_snapshot_rotation_smoothing.gd")


func _initialize() -> void:
	var t := TestCase.new()
	Suite.new().run(t)
	for message in t.failures:
		printerr("FAIL " + message)
	print("ROTATION SMOOTHING TOTAL: %d checks, %d failures" % [
		t.checks, t.failures.size()])
	quit(1 if t.failures.size() > 0 else 0)

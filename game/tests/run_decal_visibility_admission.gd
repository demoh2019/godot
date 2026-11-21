extends SceneTree
## Focused native/GDScript decal projection policy tests on headless Cgame.
## godot --headless --path game --script res://tests/run_decal_visibility_admission.gd
const TestCase = preload("res://tests/test_case.gd")
const Suite = preload("res://tests/test_decal_visibility_admission.gd")


func _initialize() -> void:
	var t := TestCase.new()
	Suite.new().run(t)
	for failure in t.failures:
		printerr("FAIL " + failure)
	print("DECAL ADMISSION TOTAL: %d checks, %d failures" % [
		t.checks, t.failures.size()])
	quit(1 if t.failures.size() > 0 else 0)

extends SceneTree
## Focused Cgame native/stock Godot cosmetic debris LOD regression.
## godot --headless --path game --script res://tests/run_debris_simulation_lod.gd
const TestCase = preload("res://tests/test_case.gd")
const Suite = preload("res://tests/test_debris_simulation_lod.gd")


func _initialize() -> void:
	var test := TestCase.new()
	Suite.new().run(test)
	for failure in test.failures:
		printerr("FAIL " + failure)
	print("DEBRIS LOD TOTAL: %d checks, %d failures" % [
		test.checks, test.failures.size()])
	quit(1 if test.failures.size() > 0 else 0)

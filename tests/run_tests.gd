extends SceneTree

func _init() -> void:
	var code: int = preload("res://tests/test_rules.gd").new().run()
	print("RESULT %d" % code)
	quit(code)

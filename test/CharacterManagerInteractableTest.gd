class_name CharacterManagerInteractableTest
extends GdUnitTestSuite

# 验证 CharacterManager.get_clicked_interactable() 已泛化为按 "interactable" 分组
# 查询，而不再局限于 "chairs" 分组，从而支持未来新增的可交互物类型。

const ChairScript = preload("res://script/Chair.gd")

func _make_chair(pos: Vector2) -> Node:
	var chair: Node = auto_free(ChairScript.new())
	chair.global_position = pos
	add_child(chair)
	return chair

func test_get_clicked_interactable_finds_chair_within_radius() -> void:
	var chair := _make_chair(Vector2(100, 100))
	var character_manager := get_node("/root/CharacterManager")
	var result = character_manager.get_clicked_interactable(Vector2(105, 100))
	assert_object(result).is_equal(chair)

func test_get_clicked_interactable_returns_null_outside_radius() -> void:
	_make_chair(Vector2(100, 100))
	var character_manager := get_node("/root/CharacterManager")
	var result = character_manager.get_clicked_interactable(Vector2(1000, 1000))
	assert_object(result).is_null()

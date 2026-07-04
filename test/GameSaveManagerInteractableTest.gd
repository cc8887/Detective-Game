class_name GameSaveManagerInteractableTest
extends GdUnitTestSuite

# 验证 GameSaveManager.find_interactable_by_name() 已泛化为按 "interactable"
# 分组查询（原 find_chair_by_name 只能查 "chairs" 分组），存档才能支持未来
# 新增的可交互物类型。

const ChairScript = preload("res://script/Chair.gd")

func _make_chair(chair_name: String) -> Node:
	var chair: Node = auto_free(ChairScript.new())
	chair.name = chair_name
	add_child(chair)
	return chair

func test_find_interactable_by_name_finds_chair() -> void:
	var chair := _make_chair("Chair1")
	var save_manager := get_node("/root/GameSaveManager")
	var result = save_manager.find_interactable_by_name("Chair1")
	assert_object(result).is_equal(chair)

func test_find_interactable_by_name_returns_null_when_missing() -> void:
	var save_manager := get_node("/root/GameSaveManager")
	var result = save_manager.find_interactable_by_name("NoSuchThing")
	assert_object(result).is_null()

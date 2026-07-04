class_name ChairTest
extends GdUnitTestSuite

# 针对重构后 Chair.gd（继承 Interactable）的测试。
# Chair 特有行为（坐下位置、朝向、z-index、站起偏移）通过 _on_interact/_on_release
# 覆盖 Interactable 的模板方法实现，占用状态本身完全复用基类逻辑。

const ChairScript = preload("res://script/Chair.gd")

func _make_character() -> CharacterBody2D:
	var character := CharacterBody2D.new()
	character.z_index = 0
	return auto_free(character)

func _make_chair() -> Node:
	var chair: Node = auto_free(ChairScript.new())
	chair.sit_position = Vector2(0, 10)
	chair.sit_direction = "down"
	chair.base_z_index = 0
	add_child(chair)
	return chair

# 椅子应同时属于通用的 "interactable" 分组和向后兼容的 "chairs" 分组
func test_chair_is_interactable_and_in_chairs_group() -> void:
	var chair := _make_chair()
	assert_bool(chair.is_in_group("interactable")).is_true()
	assert_bool(chair.is_in_group("chairs")).is_true()

func test_chair_starts_available() -> void:
	var chair := _make_chair()
	assert_bool(chair.is_occupied()).is_false()
	assert_bool(chair.is_available()).is_true()

# interact() 应把角色移动到椅子的坐位置（全局坐标）
func test_interact_sits_character_at_sit_position() -> void:
	var chair := _make_chair()
	chair.sit_position = Vector2(0, 10)
	chair.global_position = Vector2(100, 100)
	var character := _make_character()
	assert_bool(chair.interact(character)).is_true()
	assert_vector(character.global_position).is_equal(Vector2(100, 110))
	assert_bool(chair.is_occupied()).is_true()

# 已被占用的椅子不能再坐人，且不应移动第二个角色
func test_interact_fails_when_chair_already_occupied() -> void:
	var chair := _make_chair()
	var first := _make_character()
	var second := _make_character()
	chair.interact(first)
	assert_bool(chair.interact(second)).is_false()
	assert_vector(second.global_position).is_equal(Vector2.ZERO)

# release() 应站起角色并释放椅子占用
func test_release_stands_character_up_and_frees_chair() -> void:
	var chair := _make_chair()
	var character := _make_character()
	chair.interact(character)
	assert_bool(chair.release(character)).is_true()
	assert_bool(chair.is_occupied()).is_false()
	assert_bool(chair.is_available()).is_true()

# 站起后角色应被放置在椅子背后（依据朝向的偏移量，与原实现保持一致）
func test_release_positions_character_behind_chair() -> void:
	var chair := _make_chair()
	chair.sit_direction = "down"
	chair.global_position = Vector2.ZERO
	var character := _make_character()
	chair.interact(character)
	chair.release(character)
	assert_vector(character.global_position).is_equal(Vector2(0, -20))

# sit_direction = "up" 时，角色在椅子后面：角色层级低于椅子
func test_z_index_when_sit_direction_up() -> void:
	var chair := _make_chair()
	chair.sit_direction = "up"
	chair.base_z_index = 5
	var character := _make_character()
	chair.interact(character)
	assert_int(character.z_index).is_equal(5)
	assert_int(chair.z_index).is_equal(6)

# sit_direction = "down" 时，角色在椅子前面：角色层级高于椅子
func test_z_index_when_sit_direction_down() -> void:
	var chair := _make_chair()
	chair.sit_direction = "down"
	chair.base_z_index = 5
	var character := _make_character()
	chair.interact(character)
	assert_int(character.z_index).is_equal(6)
	assert_int(chair.z_index).is_equal(5)

# AI 描述应包含"椅子"功能说明及占用状态，不依赖节点名字符串匹配
func test_ai_description_mentions_chair_and_occupancy() -> void:
	var chair := _make_chair()
	chair.name = "Chair1"
	assert_str(chair.get_ai_description()).contains("椅子")
	assert_str(chair.get_ai_description()).contains("无人使用")
	chair.interact(_make_character())
	assert_str(chair.get_ai_description()).contains("有人正在使用")

# 点击检测复用基类的 interaction_radius 逻辑
func test_is_clicked_on_uses_interaction_radius() -> void:
	var chair := _make_chair()
	chair.global_position = Vector2(50, 50)
	assert_bool(chair.is_clicked_on(Vector2(55, 50))).is_true()
	assert_bool(chair.is_clicked_on(Vector2(500, 500))).is_false()

# get_interaction_position() 应返回椅子坐位的全局坐标，供角色寻路使用
func test_get_interaction_position_returns_sit_position_offset() -> void:
	var chair := _make_chair()
	chair.sit_position = Vector2(5, -5)
	chair.global_position = Vector2(20, 20)
	assert_vector(chair.get_interaction_position()).is_equal(Vector2(25, 15))

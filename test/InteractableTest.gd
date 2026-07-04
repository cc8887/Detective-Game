class_name InteractableTest
extends GdUnitTestSuite

# 针对通用可交互物基类 Interactable 的测试。
# 该基类尚未实现（见重构方案），本测试文件先固定其对外接口契约：
#   - is_occupied() / is_available()
#   - interact(character) / release(character)
#   - max_occupants 控制并发占用数量（0 表示不限）
#   - get_ai_description(character) 生成统一的 AI 感知描述
#   - is_clicked_on(position) 统一点击检测
#   - interaction_started / interaction_ended 信号

const InteractableScript = preload("res://script/Interactable.gd")

func _make_character() -> Node2D:
	return auto_free(Node2D.new())

func _make_interactable() -> Node:
	var obj: Node = auto_free(InteractableScript.new())
	add_child(obj)
	return obj

# 新创建的物体应自动加入 "interactable" 分组，供 AI/点击检测统一查询
func test_added_to_interactable_group() -> void:
	var obj := _make_interactable()
	assert_bool(obj.is_in_group("interactable")).is_true()

# 默认状态：未被占用，可交互
func test_default_state_is_available_and_not_occupied() -> void:
	var obj := _make_interactable()
	assert_bool(obj.is_occupied()).is_false()
	assert_bool(obj.is_available()).is_true()

# interact() 成功后应标记为已占用
func test_interact_marks_object_as_occupied() -> void:
	var obj := _make_interactable()
	var character := _make_character()
	assert_bool(obj.interact(character)).is_true()
	assert_bool(obj.is_occupied()).is_true()
	assert_bool(obj.is_available()).is_false()

# 默认容量为 1，第二个角色交互应失败
func test_interact_fails_when_already_occupied_by_default_capacity() -> void:
	var obj := _make_interactable()
	var first := _make_character()
	var second := _make_character()
	assert_bool(obj.interact(first)).is_true()
	assert_bool(obj.interact(second)).is_false()

# release() 应释放占用，使物体恢复可用
func test_release_frees_up_availability() -> void:
	var obj := _make_interactable()
	var character := _make_character()
	obj.interact(character)
	assert_bool(obj.release(character)).is_true()
	assert_bool(obj.is_occupied()).is_false()
	assert_bool(obj.is_available()).is_true()

# 非占用者不能释放别人的占用
func test_release_fails_for_non_occupant() -> void:
	var obj := _make_interactable()
	var occupant := _make_character()
	var stranger := _make_character()
	obj.interact(occupant)
	assert_bool(obj.release(stranger)).is_false()
	assert_bool(obj.is_occupied()).is_true()

# max_occupants > 1 时应支持多人同时占用（未来多人沙发等场景）
func test_max_occupants_allows_multiple_users() -> void:
	var obj := _make_interactable()
	obj.max_occupants = 2
	var a := _make_character()
	var b := _make_character()
	var c := _make_character()
	assert_bool(obj.interact(a)).is_true()
	assert_bool(obj.interact(b)).is_true()
	assert_bool(obj.is_available()).is_false()
	assert_bool(obj.interact(c)).is_false()

# max_occupants = 0 表示不限占用（如公共白板）
func test_max_occupants_zero_means_unlimited() -> void:
	var obj := _make_interactable()
	obj.max_occupants = 0
	for i in range(5):
		assert_bool(obj.interact(_make_character())).is_true()
	assert_bool(obj.is_available()).is_true()

# interact/release 应各自广播信号，供角色控制器/UI 监听
func test_interaction_signals_emitted() -> void:
	var obj: Node = monitor_signals(InteractableScript.new())
	add_child(obj)
	var character := _make_character()
	obj.interact(character)
	await assert_signal(obj).is_emitted("interaction_started", character)
	obj.release(character)
	await assert_signal(obj).is_emitted("interaction_ended", character)

# AI 描述应包含展示名和功能描述，不依赖节点名字符串匹配
func test_ai_description_contains_label_and_functional_text() -> void:
	var obj := _make_interactable()
	obj.display_label = "白板"
	obj.ai_description = "可以用来开会讨论或记录想法"
	var description: String = obj.get_ai_description()
	assert_str(description).contains("白板")
	assert_str(description).contains("可以用来开会讨论或记录想法")

# AI 描述应反映当前占用状态，替代原先失效的 has_method("is_occupied") 判断
func test_ai_description_reports_occupancy_state() -> void:
	var obj := _make_interactable()
	obj.display_label = "椅子"
	assert_str(obj.get_ai_description()).contains("无人使用")
	obj.interact(_make_character())
	assert_str(obj.get_ai_description()).contains("有人正在使用")

# AI 描述在传入角色时应附带距离信息
func test_ai_description_includes_distance_when_character_given() -> void:
	var obj := _make_interactable()
	obj.global_position = Vector2(100, 0)
	var character := _make_character()
	character.global_position = Vector2(0, 0)
	var description: String = obj.get_ai_description(character)
	assert_str(description).contains("距离约100")

# 统一点击检测：基于 interaction_radius，不需要每个子类重复实现
func test_is_clicked_on_within_and_outside_radius() -> void:
	var obj := _make_interactable()
	obj.interaction_radius = 32.0
	obj.global_position = Vector2(200, 200)
	assert_bool(obj.is_clicked_on(Vector2(210, 200))).is_true()
	assert_bool(obj.is_clicked_on(Vector2(250, 200))).is_false()

# display_label 为空时，展示名应回退为节点名
func test_get_label_falls_back_to_node_name() -> void:
	var obj := _make_interactable()
	obj.name = "CoffeeMachine1"
	assert_str(obj.get_label()).is_equal("CoffeeMachine1")

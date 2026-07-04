class_name BTJsonLoaderTest
extends GdUnitTestSuite

# 验证 BTJsonLoader：JSON -> BehaviorTree，覆盖
#   1. 正常构建（Sequence + 内置 BTConsolePrint + 自定义 BTLog）
#   2. params 映射到 @export 属性
#   3. 嵌套 children
#   4. 错误处理（未知类型 / 缺 type / 坏 JSON）

const _LOADER := preload("res://script/ai/bt/BTJsonLoader.gd")

# 辅助：建一个 agent + blackboard，返回 [agent, blackboard]，由调用方负责 free。
func _make_agent() -> Array:
	var agent := Node.new()
	add_child(agent)
	var blackboard := Blackboard.new()
	blackboard.set_var("log", [])
	return [agent, blackboard]

# 1. 正常构建并 tick：Sequence[BTLog("x"), BTLog("y")] -> log=["x","y"]
func test_parse_basic_sequence_with_custom_task() -> void:
	var json := """{
		"root": {
			"type": "BTSequence",
			"name": "seq1",
			"children": [
				{"type": "BTLog", "params": {"message": "x"}},
				{"type": "BTLog", "params": {"message": "y"}}
			]
		}
	}"""
	var bt := _LOADER.parse(json)
	assert_object(bt).is_not_null()
	assert_str(bt.root_task.get_class()).is_equal("BTSequence")
	assert_str(bt.root_task.custom_name).is_equal("seq1")
	assert_int(bt.root_task.get_child_count()).is_equal(2)

	var ab := _make_agent()
	var agent: Node = ab[0]
	var blackboard: Blackboard = ab[1]
	var instance := bt.instantiate(agent, blackboard, agent, agent)
	assert_object(instance).is_not_null()
	assert_int(instance.update(0.0)).is_equal(BTTask.SUCCESS)
	assert_array(blackboard.get_var("log", [])).is_equal(["x", "y"])
	agent.queue_free()

# 2. params 映射 + 嵌套：Selector[ Invert[ BTLog ], BTLog ]
#    第一个分支 Invert->BTLog("a") 返回 SUCCESS 被 Invert 翻成 FAILURE，
#    Selector 落到第二个 BTLog("b") -> SUCCESS，log=["a","b"]。
func test_parse_nested_with_params() -> void:
	var json := """{
		"root": {
			"type": "BTSelector",
			"children": [
				{"type": "BTInvert", "children": [
					{"type": "BTLog", "params": {"message": "a"}}
				]},
				{"type": "BTLog", "params": {"message": "b"}}
			]
		}
	}"""
	var bt := _LOADER.parse(json)
	assert_object(bt).is_not_null()
	assert_str(bt.root_task.get_class()).is_equal("BTSelector")

	var ab := _make_agent()
	var agent: Node = ab[0]
	var blackboard: Blackboard = ab[1]
	var instance := bt.instantiate(agent, blackboard, agent, agent)
	assert_int(instance.update(0.0)).is_equal(BTTask.SUCCESS)
	assert_array(blackboard.get_var("log", [])).is_equal(["a", "b"])
	agent.queue_free()

# 3. 错误：未知类型应返回 null
func test_parse_unknown_type_returns_null() -> void:
	var json := """{"root": {"type": "BTNoSuchNode"}}"""
	var bt := _LOADER.parse(json)
	assert_object(bt).is_null()

# 4. 错误：缺 type 应返回 null
func test_parse_missing_type_returns_null() -> void:
	var json := """{"root": {"children": []}}"""
	var bt := _LOADER.parse(json)
	assert_object(bt).is_null()

# 5. 错误：坏 JSON 应返回 null
func test_parse_bad_json_returns_null() -> void:
	var json := """{not valid json"""
	var bt := _LOADER.parse(json)
	assert_object(bt).is_null()

# 6. 错误：缺 root 应返回 null
func test_parse_missing_root_returns_null() -> void:
	var json := """{"foo": 1}"""
	var bt := _LOADER.parse(json)
	assert_object(bt).is_null()

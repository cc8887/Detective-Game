class_name LimboAITest
extends GdUnitTestSuite

# 最小行为树用例：验证 LimboAI 已加载、可在运行时用代码构建树结构、
# 自定义节点（BTLog）能被 tick 并产出 log。
#
# 覆盖三个核心诉求：
#   1. 运行时改/建树结构 —— 用 BTSequence + BTLog 代码拼装
#   2. 新节点种类        —— 自定义 BTLog（script/ai/bt/tasks/BTLog.gd）
#   3. log 输出          —— tick 后从 blackboard["log"] 取回断言

# LimboAI 核心类应在 GDExtension 加载后可用。
func test_limboai_classes_are_registered() -> void:
	assert_object(ClassDB.instantiate("BTSequence")).is_not_null()
	assert_object(ClassDB.instantiate("BTSelector")).is_not_null()
	assert_object(ClassDB.instantiate("BTPlayer")).is_not_null()
	assert_object(ClassDB.instantiate("Blackboard")).is_not_null()

# 运行时构建一棵 Sequence[BTLog("a"), BTLog("b")]，tick 一次应全部 SUCCESS，
# 且 blackboard["log"] 顺序记录 ["a", "b"]。
func test_runtime_build_and_tick_tree() -> void:
	var bt := BehaviorTree.new()
	var seq := BTSequence.new()
	bt.root_task = seq

	var log_a := BTLog.new()
	log_a.message = "a"
	var log_b := BTLog.new()
	log_b.message = "b"
	seq.add_child(log_a)
	seq.add_child(log_b)

	# 用一个普通 Node 作为 agent / instance owner，提供场景根。
	var agent := Node.new()
	add_child(agent)
	var blackboard := Blackboard.new()
	blackboard.set_var("log", [])

	var instance := bt.instantiate(agent, blackboard, agent, agent)
	assert_object(instance).is_not_null()

	var status: int = instance.update(0.0)
	assert_int(status).is_equal(BTTask.SUCCESS)
	assert_array(blackboard.get_var("log", [])).is_equal(["a", "b"])

	agent.queue_free()

# 验证运行时可动态修改树结构：建好树后追加一个 BTLog("c")，再 tick 应记录三条。
func test_runtime_modify_tree_structure() -> void:
	var bt := BehaviorTree.new()
	var seq := BTSequence.new()
	bt.root_task = seq

	var log_a := BTLog.new()
	log_a.message = "a"
	seq.add_child(log_a)

	var agent := Node.new()
	add_child(agent)
	var blackboard := Blackboard.new()
	blackboard.set_var("log", [])

	var instance := bt.instantiate(agent, blackboard, agent, agent)

	# 第一次 tick：只有 a
	assert_int(instance.update(0.0)).is_equal(BTTask.SUCCESS)
	assert_array(blackboard.get_var("log", [])).is_equal(["a"])

	# 运行时追加新节点（改树结构）——注意要操作实例的根任务（实例化时树被克隆），
	# 且新加入的 task 需手动 initialize 才能拿到 agent/blackboard/scene_root。
	var log_b := BTLog.new()
	log_b.message = "b"
	instance.get_root_task().add_child(log_b)
	log_b.initialize(agent, blackboard, agent)

	# 清空 log，再次 tick 应记录 a, b
	blackboard.set_var("log", [])
	assert_int(instance.update(0.0)).is_equal(BTTask.SUCCESS)
	assert_array(blackboard.get_var("log", [])).is_equal(["a", "b"])

	agent.queue_free()

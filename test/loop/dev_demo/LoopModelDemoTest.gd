class_name LoopModelDemoTest
extends GdUnitTestSuite

# 场景加载后应能找到按钮与输出面板（节点命名语义化，供 find_child 查找）
func test_nodes_exist() -> void:
	var runner := scene_runner("res://scene/loop_dev/LoopModelDemo.tscn")
	await runner.simulate_frames(2)

	var run_button: Button = runner.find_child("RunDemoButton")
	var output_label: RichTextLabel = runner.find_child("OutputLabel")

	assert_object(run_button).is_not_null()
	assert_object(output_label).is_not_null()

# _ready() 应自动运行一遍演示，输出面板应包含每个小节标题且不出现 FAIL
func test_auto_runs_demo_on_ready_and_all_checks_pass() -> void:
	var runner := scene_runner("res://scene/loop_dev/LoopModelDemo.tscn")
	await runner.simulate_frames(2)

	var output_label: RichTextLabel = runner.find_child("OutputLabel")
	var text: String = output_label.get_parsed_text()

	assert_str(text).contains("TraumaType 归因偏差表")
	assert_str(text).contains("Belief.resistance() 数值验证")
	assert_str(text).contains("NPCState.clone_deep() 深拷贝隔离性")
	assert_str(text).contains("演示结束")
	assert_str(text).not_contains("FAIL")

# 点击"运行数据模型演示"按钮应触发 _on_run_demo_button_pressed 并重新填充输出
# 用直接触发 pressed 信号的方式（headless 模式下鼠标事件不会真正传递，
# 参照 test/GodUIPauseButtonTest.gd 的既有写法）
func test_run_demo_button_click_invokes_callback() -> void:
	var spyed_scene: Object = spy("res://scene/loop_dev/LoopModelDemo.tscn")
	var runner := scene_runner(spyed_scene)
	await runner.simulate_frames(2)

	var run_button: Button = runner.find_child("RunDemoButton")
	run_button.emit_signal("pressed")
	await runner.simulate_frames(2)

	# _ready() 里已经调用过一次，点击按钮应再触发一次，累计至少 2 次
	verify(spyed_scene, 2)._on_run_demo_button_pressed()

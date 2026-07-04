# UI 按钮测试模板
# 复制此文件到 res://test/ 目录下，修改场景路径和按钮名称
# 文件名必须与 class_name 一致，例如 MySceneButtonTest.gd

class_name MySceneButtonTest
extends GdUnitTestSuite

# 场景路径 - 修改为实际要测试的场景
const SCENE_PATH := "res://scene/ui/MyScene.tscn"

# 测试按钮存在且初始状态正确
func test_buttons_exist() -> void:
	var runner := scene_runner(SCENE_PATH)
	await runner.simulate_frames(2)

	var button: Button = runner.find_child("MyButton")
	assert_object(button).is_not_null()
	assert_bool(button.disabled).is_false()

# 测试鼠标点击按钮
func test_button_click_via_mouse() -> void:
	var runner := scene_runner(SCENE_PATH)
	await runner.simulate_frames(2)

	var button: Button = runner.find_child("MyButton")
	var rect := button.get_global_rect()
	var center := rect.position + rect.size / 2

	runner.set_mouse_position(center)
	await runner.simulate_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	await runner.simulate_frames(2)

	# 根据实际业务逻辑添加断言
	# 例如：验证界面状态变化、信号触发等

# 测试直接触发按钮信号（不经过鼠标）
func test_button_signal_directly() -> void:
	var runner := scene_runner(SCENE_PATH)
	await runner.simulate_frames(2)

	var button: Button = runner.find_child("MyButton")
	button.emit_signal("pressed")
	await runner.simulate_frames(2)

	# 根据实际业务逻辑添加断言

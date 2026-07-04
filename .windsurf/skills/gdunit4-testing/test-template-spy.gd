# Spy 测试模板
# 使用 spy() 监控场景方法调用，验证按钮点击后是否触发了正确的回调
# 复制此文件到 res://test/ 目录下，修改场景路径和方法名

class_name MySpyTest
extends GdUnitTestSuite

const SCENE_PATH := "res://scene/ui/MyScene.tscn"

# 测试按钮点击后回调被调用
func test_button_click_invokes_callback() -> void:
	# 用 spy 包装场景
	var spyed_scene := spy(SCENE_PATH)
	var runner := scene_runner(spyed_scene)
	await runner.simulate_frames(2)

	# 找到按钮并模拟点击
	var button: Button = runner.find_child("MyButton")
	var rect := button.get_global_rect()
	runner.set_mouse_position(rect.position + rect.size / 2)
	await runner.simulate_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	await runner.simulate_frames(2)

	# 验证回调被调用了一次
	verify(spyed_scene, 1)._on_my_button_pressed()

# 测试按钮点击后回调未被调用（反向验证）
func test_other_callback_not_invoked() -> void:
	var spyed_scene := spy(SCENE_PATH)
	var runner := scene_runner(spyed_scene)
	await runner.simulate_frames(2)

	var button: Button = runner.find_child("MyButton")
	var rect := button.get_global_rect()
	runner.set_mouse_position(rect.position + rect.size / 2)
	await runner.simulate_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	await runner.simulate_frames(2)

	# 验证另一个方法未被调用
	verify(spyed_scene, 0)._on_other_button_pressed()

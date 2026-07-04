---
name: gdunit4-testing
description: Guides how to write and run gdUnit4 automated tests for this Godot project, including unit tests, UI button interaction tests, scene runner usage, spy/mock patterns, and CI integration.
---

## Overview

This project uses **gdUnit4** (v6.2.0-rc2) as its automated testing framework. Tests are located in `res://test/`. The framework supports unit tests, scene integration tests, UI interaction simulation, and spy/mock patterns.

## Running Tests

### Local (Windows)

```cmd
set GODOT_BIN=F:\path\to\Godot_v4.7-stable_win64.exe
runtests.cmd
```

Run a specific test file:

```cmd
runtests.cmd res://test/CharacterPersonalityTest.gd
```

### Local (Linux/macOS)

```bash
export GODOT_BIN=/path/to/godot
./runtests.sh
```

### CI (GitHub Actions)

Tests run automatically on push/PR to `main`/`master` via `.github/workflows/tests.yml`.

## Test File Structure

All test files go in `res://test/` and must follow these rules:

1. `class_name` must end with `Test` (e.g. `RoomDataTest`)
2. Must extend `GdUnitTestSuite`
3. Test functions must be prefixed with `test_`
4. Use `assert_*` methods for assertions (not Godot's built-in `assert()`)

### Basic Test Template

```gdscript
class_name MyFeatureTest
extends GdUnitTestSuite

# 测试基本功能
func test_basic_functionality() -> void:
    var result := SomeClass.do_something()
    assert_str(result).is_equal("expected_value")

# 测试边界条件
func test_edge_case() -> void:
    var result := SomeClass.do_something(null)
    assert_bool(result.is_empty()).is_true()
```

## Assertion Reference

gdUnit4 uses fluent assertion API. Common patterns:

```gdscript
# 字符串
assert_str(value).is_equal("expected")
assert_str(value).contains("substring")
assert_str(value).is_empty()

# 数字
assert_int(value).is_equal(42)
assert_int(value).is_greater(10)
assert_float(value).is_equal_approx(3.14, 0.01)

# 布尔
assert_bool(value).is_true()
assert_bool(value).is_false()

# 字典
assert_dict(dict).is_empty()
assert_dict(dict).contains_keys("key1", "key2")
assert_dict(dict).contains_key_value("key", expected_value)

# 数组
assert_array(arr).is_empty()
assert_array(arr).has_size(3)
assert_array(arr).contains("item")

# 向量
assert_vector(vec).is_equal(Vector2(100, 200))

# 对象
assert_object(obj).is_not_null()
assert_object(obj).is_instance_of(SomeClass)

# 信号
assert_signal(obj).is_connected("signal_name")
```

## UI Button Testing

gdUnit4 does NOT support tagging or auto-indexing UI elements. Buttons are found by **node name** or **node path** using `find_child()` or `scene().get_node()`.

### Key APIs

| API | Purpose |
|-----|---------|
| `scene_runner("res://path/Scene.tscn")` | Load a scene for testing |
| `runner.find_child("ButtonName")` | Find a node by name (recursive) |
| `runner.scene().get_node("Path/To/Button")` | Find a node by path |
| `runner.set_mouse_position(pos)` | Move mouse to position |
| `runner.simulate_mouse_button_pressed(MOUSE_BUTTON_LEFT)` | Simulate click |
| `runner.simulate_frames(n)` | Advance n frames |
| `runner.simulate_action_pressed("ui_select")` | Simulate input action |
| `runner.simulate_key_pressed(KEY_SPACE)` | Simulate key press |
| `spy(scene)` | Wrap scene to verify method calls |
| `verify(spyed)._on_method_called()` | Assert a method was called |
| `verify(spyed, 0)._on_method_called()` | Assert a method was NOT called |

### Example 1: Verify Button Exists and Initial State

```gdscript
class_name SaveLoadUITest
extends GdUnitTestSuite

func test_buttons_exist_and_initial_state() -> void:
    var runner := scene_runner("res://scene/ui/SaveLoadUI.tscn")
    await runner.simulate_frames(2)

    # 按节点名查找按钮
    var save_button: Button = runner.find_child("SaveButton")
    var load_button: Button = runner.find_child("LoadButton")
    var delete_button: Button = runner.find_child("DeleteButton")
    var close_button: Button = runner.find_child("CloseButton")

    # 验证按钮存在
    assert_object(save_button).is_not_null()
    assert_object(load_button).is_not_null()
    assert_object(delete_button).is_not_null()
    assert_object(close_button).is_not_null()

    # 验证初始状态：LoadButton 和 DeleteButton 应该是禁用的
    assert_bool(load_button.disabled).is_true()
    assert_bool(delete_button.disabled).is_true()
```

### Example 2: Simulate Button Click via Mouse

```gdscript
func test_close_button_click_hides_ui() -> void:
    var runner := scene_runner("res://scene/ui/SaveLoadUI.tscn")
    await runner.simulate_frames(2)

    var close_button: Button = runner.find_child("CloseButton")
    assert_object(close_button).is_not_null()

    # 确保界面初始是可见的（先调用 show_ui）
    runner.scene().show_ui()
    await runner.simulate_frames(1)
    assert_bool(runner.scene().visible).is_true()

    # 计算按钮中心位置并模拟点击
    var rect := close_button.get_global_rect()
    var center := rect.position + rect.size / 2
    runner.set_mouse_position(center)
    await runner.simulate_mouse_button_pressed(MOUSE_BUTTON_LEFT)
    await runner.simulate_frames(2)

    # 验证界面已隐藏
    assert_bool(runner.scene().visible).is_false()
```

### Example 3: Spy to Verify Callback Invoked

```gdscript
func test_close_button_invokes_on_close_pressed() -> void:
    # 用 spy 包装场景以监控方法调用
    var spyed_scene := spy("res://scene/ui/SaveLoadUI.tscn")
    var runner := scene_runner(spyed_scene)
    await runner.simulate_frames(2)

    # 找到关闭按钮并模拟点击
    var close_button: Button = runner.find_child("CloseButton")
    var rect := close_button.get_global_rect()
    runner.set_mouse_position(rect.position + rect.size / 2)
    await runner.simulate_mouse_button_pressed(MOUSE_BUTTON_LEFT)
    await runner.simulate_frames(2)

    # 验证 _on_close_pressed 被调用了一次
    verify(spyed_scene, 1)._on_close_pressed()
```

### Example 4: Direct Signal Emission (No Mouse)

```gdscript
func test_save_button_signal_directly() -> void:
    var runner := scene_runner("res://scene/ui/SaveLoadUI.tscn")
    await runner.simulate_frames(2)

    var save_button: Button = runner.find_child("SaveButton")

    # 直接触发按钮的 pressed 信号（不经过鼠标模拟）
    save_button.emit_signal("pressed")
    await runner.simulate_frames(2)

    # 验证状态标签显示了提示（因为没输入存档名）
    var status_label: Label = runner.find_child("StatusLabel")
    assert_str(status_label.text).is_equal("请输入存档名称")
```

### Example 5: Test Button with Keyboard Action

```gdscript
func test_toggle_settings_via_keyboard() -> void:
    var runner := scene_runner("res://scene/ui/GlobalSettingsUI.tscn")
    await runner.simulate_frames(2)

    # 模拟按下 toggle_settings 按键（ESC）
    runner.simulate_action_pressed("toggle_settings")
    await runner.simulate_frames(2)

    # 验证设置界面可见性发生了变化
    var settings_ui = runner.scene()
    assert_object(settings_ui).is_not_null()
```

## Scene Runner Reference

```gdscript
# 加载场景
var runner := scene_runner("res://scene/ui/MyScene.tscn")

# 推进帧
await runner.simulate_frames(10)

# 推进帧并指定帧间隔（毫秒）
await runner.simulate_frames(10, 16)

# 等待信号
await runner.await_signal("some_signal", [], 2000)

# 等待某个函数返回值
var result := await runner.await_func("get_status").is_equal("ready")

# 设置时间因子（加速模拟）
runner.set_time_factor(2.0)

# 获取场景根节点
var scene: Node = runner.scene()

# 查找子节点
var button: Button = runner.find_child("MyButton")

# 获取/设置属性
var value = runner.get_property("some_property")
runner.set_property("some_property", new_value)

# 调用场景方法
var ret = await runner.invoke("do_something", arg1, arg2)
```

## Spy & Mock

### Spy (监控真实实例的方法调用)

```gdscript
# 包装场景实例
var spyed := spy("res://scene/ui/MyScene.tscn")

# 验证方法被调用了 N 次
verify(spyed, 1)._on_button_pressed()
verify(spyed, 0)._on_button_pressed()  # 验证未被调用

# 重置 spy 记录
reset(spyed)
```

### Mock (替换依赖，返回默认值)

```gdscript
# 创建 mock 实例
var mock_obj := mock(SomeClass)

# 设置 mock 方法的返回值
@warning_ignore("return_value_discarded")
mock_obj.__mock__return_value("get_data", {"key": "value"})

# 验证 mock 方法被调用
verify(mock_obj, 1).get_data()
```

## Common Pitfalls

1. **`contains_key` does not exist** — use `contains_keys("key1", "key2")` instead
2. **`class_name` must match file name** — gdUnit4 resolves types by registered `class_name`
3. **Headless mode requires `--ignoreHeadlessMode`** — add this flag when running via CLI
4. **UI tests need `await runner.simulate_frames(n)`** — Godot needs frames to process `_ready()` and layout
5. **`find_child` is recursive by default** — no need to specify full path
6. **Mouse simulation requires exact position** — use `get_global_rect()` to compute button center
7. **`spy()` needs a scene with a script** — scenes without scripts cannot be spied on

## Project Test Files

| File | Tests | Description |
|------|-------|-------------|
| `res://test/CharacterPersonalityTest.gd` | 3 | 角色性格数据验证 |
| `res://test/RoomDataTest.gd` | 2 | 房间数据初始化验证 |
| `res://test/RoomManagerTest.gd` | 3 | 房间位置判断验证 |

## File Layout

```
.windsurf/skills/gdunit4-testing/
├── SKILL.md                          # This file
├── test-template-unit.gd             # Unit test template
├── test-template-ui-button.gd        # UI button test template
└── test-template-spy.gd              # Spy-based test template
```

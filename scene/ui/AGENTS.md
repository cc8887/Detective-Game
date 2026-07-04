# UI 测试友好设计规范

gdUnit4 通过 `find_child("节点名")` 查找 UI 元素，无 tag 机制。UI 命名直接决定测试可读性和可维护性。

## 规则

1. **节点名唯一且语义化**：用 `SaveButton` 而非 `Button`，测试中 `find_child("SaveButton")` 一目了然
2. **场景根节点必须挂脚本**：`spy()` 依赖脚本拦截方法调用，无脚本的场景无法 spy
3. **回调命名遵循 `_on_{节点名}_pressed` 模式**：如 `_on_save_button_pressed`，便于 `verify(spy)._on_save_button_pressed()` 验证
4. **按钮状态可观测**：通过 `disabled`/`visible` 属性表达状态，测试可直接断言
5. **避免深层动态嵌套**：`find_child` 递归查找不依赖路径，但动态增删的节点会让测试时序不确定
6. **每个新创建的 UI 必须调用 `@gdunit4-testing` skill**，并在 `res://test/` 下添加对应的测试用例

## 正例

```gdscript
# ✅ 节点名语义化，回调命名可预测
# SaveLoadUI.tscn 节点结构:
#   SaveButton   -> _on_save_button_pressed()
#   LoadButton   -> _on_load_button_pressed()
#   CloseButton  -> _on_close_button_pressed()
# 测试代码:
var btn: Button = runner.find_child("SaveButton")
assert_bool(btn.disabled).is_false()
verify(spyed, 1)._on_save_button_pressed()
```

```gdscript
# ✅ 按钮状态与业务逻辑绑定，可直接断言
# 未选中存档时 LoadButton.disabled == true
# 选中存档后 LoadButton.disabled == false
# 测试可验证状态切换:
assert_bool(load_button.disabled).is_true()
save_list.select(0)
await runner.simulate_frames(1)
assert_bool(load_button.disabled).is_false()
```

```gdscript
# ✅ 场景根节点挂载脚本，spy 可用
# GlobalSettingsUI.tscn -> GlobalSettingsUI.gd
# 测试中可以直接 spy 整个场景:
var spyed := spy("res://scene/ui/GlobalSettingsUI.tscn")
var runner := scene_runner(spyed)
verify(spyed, 1)._on_quit_button_pressed()
```

## 反例

```gdscript
# ❌ 节点名无语义，测试不可读
# 场景节点: Button, Button2, Button3
# 测试中完全无法区分:
var btn = runner.find_child("Button")   # 哪个按钮？
var btn2 = runner.find_child("Button2") # 含义不明
```

```gdscript
# ❌ 场景根节点无脚本，spy 不可用
# SomePanel.tscn 没有挂载 .gd 脚本
# 以下代码会报错:
var spyed := spy("res://scene/ui/SomePanel.tscn") # Error: Can't create a spy on a scene without script
```

```gdscript
# ❌ 信号回调用匿名 lambda，无法通过 verify 验证
button.pressed.connect(func(): hide())
# 测试中无法 verify，因为没有具名方法可拦截:
verify(spyed, 1)._on_close_pressed() # 失败：方法不存在

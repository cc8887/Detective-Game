class_name BTJsonLoader
extends RefCounted
## BTJsonLoader
## 把 JSON 文本/字典转成 BehaviorTree 资源，让 AI（LLM）只需输出 JSON 即可
## 在运行时构建或热替换行为树，无需写 .tres / .tscn。
##
## JSON Schema（最小集）：
##   {
##     "root": {
##       "type": "<BTTask 子类名>",          # 必填，如 BTSequence / BTSelector / BTInvert / BTDelay / BTLog
##       "name": "<可选 custom_name>",
##       "params": { "<属性名>": <值>, ... }, # 可选，映射到节点的 @export 属性
##       "children": [ <node>, ... ],         # 可选，复合/装饰节点才有
##       "script": "<可选 res:// 脚本路径>"   # 可选，自定义 GDScript 节点类可直接给路径
##     }
##   }
##
## 节点类型解析顺序：
##   1. ClassDB 内置类（BTSequence 等 C++ 注册的 LimboAI 类）
##   2. 通过 register_type() 显式注册的脚本类
##   3. JSON 里的 "script" 字段（res:// 路径，最通用，AI 可直接给路径）
##
## 用法：
##   var bt: BehaviorTree = BTJsonLoader.parse(json_string)
##   var instance := bt.instantiate(agent, blackboard, owner, scene_root)
##   instance.update(delta)
##
## 错误处理：解析失败时 push_error 并返回 null；调用方应判空。

# --- 脚本类注册表 -----------------------------------------------------------
# ClassDB 只含 C++ 注册的类；GDScript 的 class_name 在导出运行时不在 ClassDB。
# 我们用一个静态字典把自定义节点类名映射到脚本资源路径，供 _instantiate_type 回退。
static var _SCRIPT_TYPES: Dictionary = {}

# 注册一个 GDScript 自定义节点类。name 是 class_name，path 是 res:// 脚本路径。
# 建议在项目启动时（如 autoload 的 _ready）注册所有自定义 BT 节点。
static func register_type(type_name: String, script_path: String) -> void:
	_SCRIPT_TYPES[type_name] = script_path

# 预注册项目自带的自定义节点。新增自定义 BT 节点时，在此处加一行即可。
static func _ensure_builtin_types_registered() -> void:
	if not _SCRIPT_TYPES.has("BTLog"):
		_SCRIPT_TYPES["BTLog"] = "res://script/ai/bt/tasks/BTLog.gd"

# --- public API -------------------------------------------------------------

# 从 JSON 字符串构建 BehaviorTree。失败返回 null。
static func parse(json_text: String) -> BehaviorTree:
	# Godot 4.x: 用 JSON.new().parse 拿到 data + 错误信息。
	var j := JSON.new()
	var status := j.parse(json_text)
	if status != OK:
		push_error("[BTJsonLoader] JSON parse failed: %s" % j.get_error_message())
		return null
	var parsed: Variant = j.data
	if parsed == null:
		push_error("[BTJsonLoader] JSON parsed to null.")
		return null
	return build(parsed)

# 从已有字典/数组构建 BehaviorTree。失败返回 null。
static func build(data: Variant) -> BehaviorTree:
	_ensure_builtin_types_registered()
	if typeof(data) != TYPE_DICTIONARY:
		push_error("[BTJsonLoader] Top-level JSON must be an object with a 'root' key.")
		return null
	var root_spec: Variant = data.get("root", null)
	if root_spec == null:
		push_error("[BTJsonLoader] Missing 'root' key in JSON.")
		return null
	var root_task := _build_task(root_spec)
	if root_task == null:
		return null
	var bt := BehaviorTree.new()
	bt.root_task = root_task
	return bt

# --- internals --------------------------------------------------------------

# 递归构建单个 BTTask。失败返回 null。
static func _build_task(spec: Variant) -> BTTask:
	if typeof(spec) != TYPE_DICTIONARY:
		push_error("[BTJsonLoader] Task spec must be an object.")
		return null
	var type: String = spec.get("type", "")
	if type.is_empty():
		push_error("[BTJsonLoader] Task spec missing 'type'.")
		return null
	var task: BTTask = _instantiate_type(type, spec.get("script", ""))
	if task == null:
		# _instantiate_type 已 push_error
		return null
	# 可选 custom_name
	var cname: String = spec.get("name", "")
	if not cname.is_empty():
		task.custom_name = cname
	# params -> set() 属性
	var params: Variant = spec.get("params", {})
	if typeof(params) == TYPE_DICTIONARY:
		for key in params:
			var value: Variant = params[key]
			_try_set(task, key, value)
	# children -> 递归
	var children: Variant = spec.get("children", [])
	if typeof(children) == TYPE_ARRAY:
		for child_spec in children:
			var child := _build_task(child_spec)
			if child == null:
				# 子节点失败则整体失败，释放已建节点
				_safe_free(task)
				return null
			task.add_child(child)
	return task

# 按优先级实例化节点：ClassDB -> 注册表 -> script 字段。
static func _instantiate_type(type: String, script_path: String) -> BTTask:
	# 1. ClassDB 内置类（LimboAI C++ 类）
	if ClassDB.class_exists(type):
		var obj: Object = ClassDB.instantiate(type)
		if obj is BTTask:
			return obj as BTTask
		if obj != null:
			# 类存在但不是 BTTask，释放并报错
			_safe_free(obj)
	# 2. 注册表中的脚本类
	_ensure_builtin_types_registered()
	if _SCRIPT_TYPES.has(type):
		var path: String = _SCRIPT_TYPES[type]
		return _instantiate_script(path)
	# 3. JSON 里直接给的 script 路径
	if not script_path.is_empty():
		return _instantiate_script(script_path)
	push_error("[BTJsonLoader] Unknown task type: %s" % type)
	return null

# 从脚本资源路径实例化一个 BTTask。失败返回 null。
static func _instantiate_script(path: String) -> BTTask:
	if not ResourceLoader.exists(path):
		push_error("[BTJsonLoader] Script not found: %s" % path)
		return null
	var scr: Resource = load(path)
	if not (scr is GDScript):
		push_error("[BTJsonLoader] Resource is not a GDScript: %s" % path)
		return null
	var obj: Object = (scr as GDScript).new()
	if obj is BTTask:
		return obj as BTTask
	push_error("[BTJsonLoader] Script does not extend BTTask: %s" % path)
	_safe_free(obj)
	return null

# 安全释放 Object（BTTask 是 Object 而非 RefCounted）。对 null/RefCounted 静默跳过。
static func _safe_free(obj: Object) -> void:
	if obj == null:
		return
	if obj is RefCounted:
		return
	obj.free()

# 安全地给 task 设置属性；属性不存在时 push_error 并返回 false。
static func _try_set(task: BTTask, prop: String, value: Variant) -> bool:
	var props := task.get_property_list()
	for p in props:
		if p.name == prop:
			task.set(prop, value)
			return true
	push_error("[BTJsonLoader] Property '%s' not found on %s" % [prop, task.get_class()])
	return false

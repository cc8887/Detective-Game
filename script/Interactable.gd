extends StaticBody2D
class_name Interactable

## 通用可交互物基类。
## 统一管理占用/可用状态、AI 感知描述、点击检测和交互区域的生成，
## 新增可交互物只需继承此类并覆盖 _on_interact()/_on_release() 等虚方法。

@export var interaction_radius: float = 32.0
@export var max_occupants: int = 1
@export var display_label: String = ""
@export var ai_description: String = ""

var occupants: Array = []

signal interaction_started(character)
signal interaction_ended(character)

func _ready() -> void:
	add_to_group("interactable")
	_setup_interaction_area()

## 生成统一的交互检测区域，子类不需要各自重复实现 Area2D/CollisionShape2D
func _setup_interaction_area() -> void:
	var area := Area2D.new()
	var collision_shape := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = interaction_radius
	collision_shape.shape = shape
	area.add_child(collision_shape)
	add_child(area)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("controllable_characters"):
		_on_character_entered(body)

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("controllable_characters"):
		_on_character_exited(body)

## 角色进入交互范围时触发，子类可覆盖（例如 Chair 设置 character.nearby_interactable）
func _on_character_entered(_character: Node) -> void:
	pass

## 角色离开交互范围时触发，子类可覆盖
func _on_character_exited(_character: Node) -> void:
	pass

func is_occupied() -> bool:
	return occupants.size() > 0

func is_available() -> bool:
	return max_occupants <= 0 or occupants.size() < max_occupants

func can_interact(_character) -> bool:
	return is_available()

func interact(character) -> bool:
	if not can_interact(character):
		return false
	if not _on_interact(character):
		return false
	occupants.append(character)
	interaction_started.emit(character)
	return true

func release(character) -> bool:
	if not occupants.has(character):
		return false
	if not _on_release(character):
		return false
	occupants.erase(character)
	interaction_ended.emit(character)
	return true

func _on_interact(_character) -> bool:
	return true

func _on_release(_character) -> bool:
	return true

func get_interaction_position(_character = null) -> Vector2:
	return global_position

## 交互后角色应朝向的方向，空字符串表示保持角色当前朝向（子类可覆盖，如 Chair 返回坐姿朝向）
func get_facing_direction(_character = null) -> String:
	return ""

## 交互开始时应播放的动画名，空字符串表示不需要切换动画
func get_interaction_animation(_character = null) -> String:
	return ""

## 交互结束时应播放的动画名，空字符串表示不需要切换动画
func get_release_animation(_character = null) -> String:
	return ""

func get_label() -> String:
	return display_label if display_label != "" else String(name)

func get_ai_description(character = null) -> String:
	var info := get_label()
	if ai_description != "":
		info += "（%s）" % ai_description
	if max_occupants > 0:
		info += "，目前有人正在使用" if is_occupied() else "，目前无人使用"
	if character:
		var distance := int(global_position.distance_to(character.global_position))
		info += "，距离约%d米" % distance
	return info

func is_clicked_on(click_position: Vector2) -> bool:
	return global_position.distance_to(click_position) <= interaction_radius

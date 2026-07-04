extends Interactable
class_name Chair

@export var sit_position: Vector2 = Vector2.ZERO  # 角色坐下时的位置偏移
@export var sit_direction: String = "right"  # 坐下时角色朝向
@export var base_z_index: int = 0  # 基础Z轴顺序

# 向后兼容旧调用方（CharacterController 等直接读取 chair.occupied / chair.current_character）
var occupied: bool:
	get: return is_occupied()
var current_character:
	get: return occupants[0] if occupants.size() > 0 else null

func _ready() -> void:
	super._ready()
	# 将椅子加入chairs组（向后兼容依赖该分组的代码，如 CharacterManager/Desk）
	add_to_group("chairs")
	if ai_description == "":
		ai_description = "一把椅子，可以坐下休息或工作"
	# 设置椅子的Z轴顺序
	z_index = base_z_index

func _on_character_entered(character: Node) -> void:
	character.nearby_interactable = self

func _on_character_exited(character: Node) -> void:
	if character.nearby_interactable == self:
		character.nearby_interactable = null

func _draw() -> void:
	# 绘制坐位位置指示器（仅在编辑器中可见）
	if Engine.is_editor_hint():
		draw_circle(sit_position, 5, Color.RED)
		# 绘制一条从椅子中心到坐位的线
		draw_line(Vector2.ZERO, sit_position, Color.YELLOW, 2)

# 获取椅子的坐位置（全局坐标）
func get_interaction_position(_character = null) -> Vector2:
	return global_position + sit_position

func get_sit_position() -> Vector2:
	return get_interaction_position()

func get_facing_direction(_character = null) -> String:
	return sit_direction

func get_interaction_animation(_character = null) -> String:
	if sit_direction == "up":
		return "sit_up"
	elif sit_direction == "down":
		return "sit_down"
	return "sit_" + sit_direction

func get_release_animation(_character = null) -> String:
	if sit_direction == "up":
		return "stand_up"
	elif sit_direction == "down":
		return "stand_down"
	return "stand_" + sit_direction

func _on_interact(character) -> bool:
	# 将角色移动到椅子的坐位置
	character.global_position = get_interaction_position(character)

	# 根据坐姿调整Z轴顺序
	if sit_direction == "up":
		# 角色在椅子后面
		character.z_index = base_z_index  # 角色保持在基础层
		z_index = base_z_index + 1  # 椅子移到角色上面
	else:
		# 角色在椅子前面
		character.z_index = base_z_index + 1  # 角色在椅子前面
		z_index = base_z_index  # 椅子保持原位

	return true

func _on_release(character) -> bool:
	# 计算角色站起后的位置（椅子背后）
	var stand_up_offset = Vector2.ZERO
	match sit_direction:
		"up":
			# 椅子朝上，角色站在椅子下方（背后）
			stand_up_offset = Vector2(0, 16)
		"down":
			# 椅子朝下，角色站在椅子上方（背后）
			stand_up_offset = Vector2(0, -20)
		"left":
			# 椅子朝左，角色站在椅子右方（背后）
			stand_up_offset = Vector2(16, 0)
		"right":
			# 椅子朝右，角色站在椅子左方（背后）
			stand_up_offset = Vector2(-20, 0)

	# 将角色移动到椅子背后的位置
	character.global_position = global_position + stand_up_offset

	# 重置Z轴顺序
	character.z_index = base_z_index  # 角色回到基础层
	z_index = base_z_index  # 椅子回到默认层

	return true

# 向后兼容旧调用方，后续 CharacterController 迁移到统一的 interact()/release() 后可移除
func sit_character(character: CharacterBody2D) -> bool:
	return interact(character)

func stand_up() -> bool:
	if occupants.is_empty():
		return false
	return release(occupants[0])

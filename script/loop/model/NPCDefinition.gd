class_name NPCDefinition
extends Resource

## NPC 的静态属性：由关卡设计或 LLM 生成时确定，循环内不变。
## 对照设计文档：docs/design/loop-collapse-architecture.md §3.1
##
## 实现说明：字段故意不使用 @export —— Godot 的 @export 只能安全导出内置类型/
## Resource 子类，Belief 等模型类是 RefCounted（不是 Resource），
## 强行 @export 自定义 RefCounted 类型的数组/字典会导致编辑器属性系统报错。
## Phase 1 全部通过代码构造故事弧数据，不依赖 Inspector 面板编辑，因此不需要 @export。

var id: String = ""
var display_name: String = ""
var trauma_type: TraumaType.Type = TraumaType.Type.ISOLATION
var breakdown_threshold: float = 85.0
var stress_gain_multiplier: float = 1.0
var belief_resistance_bonus: float = 0.0
var initial_beliefs: Array[Belief] = []
## { npc_id: float }，非对称。
var initial_trust: Dictionary = {}
var initial_stress: float = 20.0
var background_summary: String = ""

## 深拷贝，防止某一轮循环期间对派生 NPCState 的修改回流污染这份"设计蓝图"数据。
func clone_deep() -> NPCDefinition:
	var copy := NPCDefinition.new()
	copy.id = id
	copy.display_name = display_name
	copy.trauma_type = trauma_type
	copy.breakdown_threshold = breakdown_threshold
	copy.stress_gain_multiplier = stress_gain_multiplier
	copy.belief_resistance_bonus = belief_resistance_bonus

	copy.initial_beliefs = []
	for belief in initial_beliefs:
		copy.initial_beliefs.append(belief.clone_deep())

	copy.initial_trust = initial_trust.duplicate()
	copy.initial_stress = initial_stress
	copy.background_summary = background_summary
	return copy

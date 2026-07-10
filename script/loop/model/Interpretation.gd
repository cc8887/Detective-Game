class_name Interpretation
extends RefCounted

## 事件的候选解读：一个客观事件在触发时会附带若干候选解读，
## InterpretationResolver 会依据 NPC 当前信念/压力从候选中选出最终解读。
## 对照设计文档：docs/design/loop-collapse-architecture.md §3.6 / §6.3 / §8.1

var interpretation_id: String = ""
var base_confidence: float = 0.0
var resulting_fact_id: String = ""
var resulting_direction: bool = true
## 对应 TraumaType.ATTRIBUTION_BIAS 的 trigger_category，供归因链传播做分类匹配。
var trigger_category: String = ""
## 该解读是否属于"负面"解读，供确认偏误公式在高压时额外加权。
var is_negative: bool = false

func _init(p_id: String = "", p_base_confidence: float = 0.0, p_fact_id: String = "",
		p_direction: bool = true, p_trigger_category: String = "", p_is_negative: bool = false) -> void:
	interpretation_id = p_id
	base_confidence = p_base_confidence
	resulting_fact_id = p_fact_id
	resulting_direction = p_direction
	trigger_category = p_trigger_category
	is_negative = p_is_negative

func clone_deep() -> Interpretation:
	return Interpretation.new(
		interpretation_id, base_confidence, resulting_fact_id,
		resulting_direction, trigger_category, is_negative
	)

class_name TraumaType
extends RefCounted

## 六种创伤类型，决定 NPC 在高压状态下的感知偏向与崩坏方向。
## 对照设计文档：docs/design/loop-collapse-architecture.md §3.2 / §5.2 / §5.4

enum Type { ABANDONMENT, BETRAYAL, UNWORTHINESS, CONTROL_LOSS, INJUSTICE, ISOLATION }

## 归因偏差规则表：创伤类型 -> 该创伤最容易被激活的事件分类标签、以及由此产生的负面信念标签。
## trigger_category / biased_belief 均为枚举化的语义标签（不是自由文本），
## 便于 InterpretationResolver / AttributionPropagator 用查表方式判定，而不依赖 LLM 语义理解。
const ATTRIBUTION_BIAS := {
	Type.ABANDONMENT:  {"trigger_category": "departure_or_change", "biased_belief": "is_being_abandoned"},
	Type.BETRAYAL:     {"trigger_category": "private_behavior",    "biased_belief": "is_being_schemed_against"},
	Type.UNWORTHINESS: {"trigger_category": "positive_event",      "biased_belief": "is_pity_not_merit"},
	Type.CONTROL_LOSS: {"trigger_category": "unexpected_event",    "biased_belief": "is_losing_control"},
	Type.INJUSTICE:    {"trigger_category": "disparity",           "biased_belief": "is_unfairly_targeted"},
	Type.ISOLATION:    {"trigger_category": "affection_shown",     "biased_belief": "is_fake_concern"},
}

## 崩坏方向：压力超过阈值且核心创伤信念确认后，NPC 倾向采取的行为类型。
const BREAKDOWN_DIRECTION := {
	Type.ABANDONMENT:  "attack_or_withdraw",
	Type.BETRAYAL:     "preemptive_strike",
	Type.UNWORTHINESS: "self_harm_or_sabotage",
	Type.CONTROL_LOSS:  "extreme_control_or_giveup",
	Type.INJUSTICE:    "retaliation",
	Type.ISOLATION:    "cut_all_ties",
}

## 返回全部创伤类型枚举值，供遍历测试/演示使用。
static func all_types() -> Array:
	return [Type.ABANDONMENT, Type.BETRAYAL, Type.UNWORTHINESS, Type.CONTROL_LOSS, Type.INJUSTICE, Type.ISOLATION]

## 类型枚举转可读中文名，仅供 CLI/演示输出使用，不参与任何判定逻辑。
static func type_name(type: Type) -> String:
	match type:
		Type.ABANDONMENT: return "被抛弃恐惧"
		Type.BETRAYAL: return "背叛恐惧"
		Type.UNWORTHINESS: return "自我否定"
		Type.CONTROL_LOSS: return "失控恐惧"
		Type.INJUSTICE: return "不公执念"
		Type.ISOLATION: return "孤立恐惧"
		_: return "未知创伤"

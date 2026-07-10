class_name Belief
extends RefCounted

## 信念：NPC 对某个客观事实的主观判断。
## 对照设计文档：docs/design/loop-collapse-architecture.md §3.4 / §6.4

## 关联的客观事实 ID（见 WorldFact）。
var fact_id: String = ""
## true=相信该事实为真，false=相信为假。
var direction: bool = true
## 置信度，0.0 ~ 1.0。
var confidence: float = 0.0
## 信念已存在了多少个时间步（越老越难撼动）。
var age_in_steps: int = 0
## 有多少独立事件已经支持了这条信念。
var evidence_count: int = 1
## 来源：npc_id 或 event_id。
var source: String = ""
## 是否为核心创伤信念：若为是，拥有额外抵抗力，几乎无法被推翻。
var is_core_trauma_belief: bool = false

## 信念抵抗力：决定这条信念有多难被推翻。
## 公式：0.3（基础） + stress*0.003 + age_in_steps*0.01 + evidence_count*0.05
##       + (0.5 如果是核心创伤信念) + npc_def.belief_resistance_bonus（性格加成）
## 上限 0.95，确保任何信念在理论上都有被推翻的可能。
func resistance(npc_state: NPCState, npc_def: NPCDefinition) -> float:
	var r := 0.3
	r += npc_state.stress * 0.003
	r += age_in_steps * 0.01
	r += evidence_count * 0.05
	if is_core_trauma_belief:
		r += 0.5
	r += npc_def.belief_resistance_bonus
	return min(r, 0.95)

func clone_deep() -> Belief:
	var copy := Belief.new()
	copy.fact_id = fact_id
	copy.direction = direction
	copy.confidence = confidence
	copy.age_in_steps = age_in_steps
	copy.evidence_count = evidence_count
	copy.source = source
	copy.is_core_trauma_belief = is_core_trauma_belief
	return copy

class_name EventRecord
extends RefCounted

## 客观事件记录，同时也是 NPC "记忆库"（NPCState.memory_log）里的条目。
## 对照设计文档：docs/design/loop-collapse-architecture.md §3.6 / §6.1~§6.3

var event_id: String = ""
var time_step: int = -1
var location: String = ""
var visibility: Visibility.Level = Visibility.Level.PUBLIC
var actors: Array[String] = []
var targets: Array[String] = []
## 客观描述，不含任何解读，给叙事接口层用于生成中立文本。
var raw_description: String = ""
var candidate_interpretations: Array[Interpretation] = []
## { npc_id: Interpretation } —— 每个感知到该事件的 NPC 各自选出的解读。
var chosen_interpretation_by: Dictionary = {}
## 直接目击者，在 perceive 阶段填充。
var witnesses: Array[String] = []

## 深拷贝，供 NPCState.clone_deep() / WorldStateContext.snapshot() 使用。
func clone_deep() -> EventRecord:
	var copy := EventRecord.new()
	copy.event_id = event_id
	copy.time_step = time_step
	copy.location = location
	copy.visibility = visibility
	copy.actors = actors.duplicate()
	copy.targets = targets.duplicate()
	copy.raw_description = raw_description

	copy.candidate_interpretations = []
	for interp in candidate_interpretations:
		copy.candidate_interpretations.append(interp.clone_deep())

	copy.chosen_interpretation_by = {}
	for npc_id in chosen_interpretation_by:
		copy.chosen_interpretation_by[npc_id] = chosen_interpretation_by[npc_id].clone_deep()

	copy.witnesses = witnesses.duplicate()
	return copy

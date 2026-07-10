class_name NPCState
extends RefCounted

## NPC 的动态属性：每个时间步由推导引擎更新。
## 对照设计文档：docs/design/loop-collapse-architecture.md §3.3

var npc_id: String = ""
var stress: float = 0.0
var beliefs: Array[Belief] = []
## { target_id: float }，非对称，目标可以是其他 npc_id 或 "__player__"。
var trust_towards: Dictionary = {}
## { target_id: float } 当前怀疑度。
var suspicion_towards: Dictionary = {}
## {} 表示无意图；否则 {type, target, formed_at_step}。
var intent: Dictionary = {}
## "记忆库"——已感知并解读过的事件。
var memory_log: Array[EventRecord] = []
## 本时间步待竞争的行为（临时数据，每步结算后清空）。
var pending_action_queue: Array = []

## 深拷贝：供 WorldStateContext.snapshot() / LoopSnapshotStore 使用。
## 必须保证修改副本的任意嵌套字段都不会影响原始对象——这是复盘/重放系统正确性的前提。
func clone_deep() -> NPCState:
	var copy := NPCState.new()
	copy.npc_id = npc_id
	copy.stress = stress

	copy.beliefs = []
	for belief in beliefs:
		copy.beliefs.append(belief.clone_deep())

	copy.trust_towards = trust_towards.duplicate()
	copy.suspicion_towards = suspicion_towards.duplicate()
	copy.intent = intent.duplicate()

	copy.memory_log = []
	for event in memory_log:
		copy.memory_log.append(event.clone_deep())

	# pending_action_queue 是本步临时数据，每步结算后会被清空，浅拷贝即可。
	copy.pending_action_queue = pending_action_queue.duplicate()
	return copy

## 查找当前对某个事实持有的信念，找不到返回 null。
func find_belief(fact_id: String) -> Belief:
	for belief in beliefs:
		if belief.fact_id == fact_id:
			return belief
	return null

## 查找核心创伤信念（若存在多条，返回置信度最高的一条）。
func find_core_trauma_belief() -> Belief:
	var best: Belief = null
	for belief in beliefs:
		if belief.is_core_trauma_belief:
			if best == null or belief.confidence > best.confidence:
				best = belief
	return best

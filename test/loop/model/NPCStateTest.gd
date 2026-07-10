class_name NPCStateTest
extends GdUnitTestSuite

func _make_populated_state() -> NPCState:
	var state := NPCState.new()
	state.npc_id = "A"
	state.stress = 50.0

	var belief := Belief.new()
	belief.fact_id = "fact_1"
	belief.confidence = 0.7
	state.beliefs.append(belief)

	state.trust_towards["B"] = 60.0

	var event := EventRecord.new()
	event.event_id = "evt_1"
	event.witnesses.append("A")
	state.memory_log.append(event)

	state.intent = {"type": "none"}
	return state

# TC-NPCSTATE-01：副本与原始对象不是同一引用
func test_clone_deep_creates_new_instance() -> void:
	var original := _make_populated_state()
	var copy := original.clone_deep()
	assert_bool(copy == original).is_false()

# TC-NPCSTATE-02：修改副本的信念不影响原始对象
func test_clone_deep_isolates_beliefs() -> void:
	var original := _make_populated_state()
	var copy := original.clone_deep()
	copy.beliefs[0].confidence = 0.1
	assert_float(original.beliefs[0].confidence).is_equal_approx(0.7, 0.0001)

# TC-NPCSTATE-03：修改副本的信任字典不影响原始对象
func test_clone_deep_isolates_trust_towards() -> void:
	var original := _make_populated_state()
	var copy := original.clone_deep()
	copy.trust_towards["B"] = 0.0
	copy.trust_towards["C"] = 99.0
	assert_float(original.trust_towards["B"]).is_equal_approx(60.0, 0.0001)
	assert_bool(original.trust_towards.has("C")).is_false()

# TC-NPCSTATE-04：修改副本记忆库中的事件不影响原始对象（EventRecord 也要被深拷贝）
func test_clone_deep_isolates_memory_log() -> void:
	var original := _make_populated_state()
	var copy := original.clone_deep()
	copy.memory_log[0].witnesses.append("Z")
	assert_array(original.memory_log[0].witnesses).contains_exactly(["A"])

# TC-NPCSTATE-05：修改副本的 intent 字典不影响原始对象
func test_clone_deep_isolates_intent() -> void:
	var original := _make_populated_state()
	var copy := original.clone_deep()
	copy.intent["type"] = "breakdown"
	assert_str(original.intent["type"]).is_equal("none")

# find_belief() 能按 fact_id 找到对应信念，找不到返回 null
func test_find_belief_returns_matching_or_null() -> void:
	var state := _make_populated_state()
	assert_object(state.find_belief("fact_1")).is_not_null()
	assert_object(state.find_belief("fact_unknown")).is_null()

# find_core_trauma_belief() 只返回标记为核心创伤的信念，且取置信度最高的一条
func test_find_core_trauma_belief_picks_highest_confidence() -> void:
	var state := NPCState.new()

	var low := Belief.new()
	low.fact_id = "f1"
	low.confidence = 0.5
	low.is_core_trauma_belief = true

	var high := Belief.new()
	high.fact_id = "f2"
	high.confidence = 0.9
	high.is_core_trauma_belief = true

	var non_core := Belief.new()
	non_core.fact_id = "f3"
	non_core.confidence = 0.99
	non_core.is_core_trauma_belief = false

	state.beliefs.append_array([low, high, non_core])

	assert_str(state.find_core_trauma_belief().fact_id).is_equal("f2")

# 没有任何核心创伤信念时应返回 null
func test_find_core_trauma_belief_returns_null_when_none_marked() -> void:
	var state := NPCState.new()
	var belief := Belief.new()
	belief.fact_id = "f1"
	belief.is_core_trauma_belief = false
	state.beliefs.append(belief)
	assert_object(state.find_core_trauma_belief()).is_null()

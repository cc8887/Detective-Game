class_name BeliefTest
extends GdUnitTestSuite

func _make_npc_state(stress: float) -> NPCState:
	var state := NPCState.new()
	state.npc_id = "npc_test"
	state.stress = stress
	return state

func _make_npc_def(bonus: float = 0.0) -> NPCDefinition:
	var def := NPCDefinition.new()
	def.id = "npc_test"
	def.belief_resistance_bonus = bonus
	return def

func _make_belief(age: int = 0, evidence: int = 1, core: bool = false) -> Belief:
	var belief := Belief.new()
	belief.age_in_steps = age
	belief.evidence_count = evidence
	belief.is_core_trauma_belief = core
	return belief

# TC-BELIEF-01：基线组合 stress=0/age=0/evidence=1/core=false/bonus=0 -> 0.35
func test_resistance_baseline() -> void:
	var belief := _make_belief()
	var resistance := belief.resistance(_make_npc_state(0.0), _make_npc_def())
	assert_float(resistance).is_equal_approx(0.35, 0.0001)

# TC-BELIEF-02：stress=100 时应比基线多 0.3（100*0.003）
func test_resistance_high_stress_adds_expected_amount() -> void:
	var belief := _make_belief()
	var baseline := belief.resistance(_make_npc_state(0.0), _make_npc_def())
	var high_stress := belief.resistance(_make_npc_state(100.0), _make_npc_def())
	assert_float(high_stress - baseline).is_equal_approx(0.3, 0.0001)

# TC-BELIEF-03：age_in_steps=70 时应触顶到 0.95（不会超过上限）
# 注：0.3(基础) + 70*0.01(=0.7) + 1*0.05(=0.05) = 1.05，超过上限应被 min() 夹到 0.95。
func test_resistance_caps_at_0_95_via_age() -> void:
	var belief := _make_belief(70, 1, false)
	var resistance := belief.resistance(_make_npc_state(0.0), _make_npc_def())
	assert_float(resistance).is_equal_approx(0.95, 0.0001)

# TC-BELIEF-04：evidence_count=20 时同样触顶 0.95
func test_resistance_caps_at_0_95_via_evidence() -> void:
	var belief := _make_belief(0, 20, false)
	var resistance := belief.resistance(_make_npc_state(0.0), _make_npc_def())
	assert_float(resistance).is_equal_approx(0.95, 0.0001)

# TC-BELIEF-05：核心创伤信念在未触顶时应精确 +0.5，而不是覆盖基线
func test_resistance_core_trauma_adds_half_precisely() -> void:
	var belief := _make_belief(0, 1, true)
	var resistance := belief.resistance(_make_npc_state(0.0), _make_npc_def())
	assert_float(resistance).is_equal_approx(0.85, 0.0001)

# TC-BELIEF-06：极端组合应精确等于上限 0.95，而不是负数或溢出
func test_resistance_extreme_combo_equals_cap() -> void:
	var belief := _make_belief(100, 100, true)
	var resistance := belief.resistance(_make_npc_state(100.0), _make_npc_def())
	assert_float(resistance).is_equal_approx(0.95, 0.0001)

# TC-BELIEF-07：NPCDefinition.belief_resistance_bonus 应独立叠加
func test_resistance_npc_definition_bonus_is_additive() -> void:
	var belief := _make_belief()
	var resistance := belief.resistance(_make_npc_state(0.0), _make_npc_def(0.2))
	assert_float(resistance).is_equal_approx(0.55, 0.0001)

# clone_deep() 后修改副本不应影响原始信念
func test_clone_deep_is_independent() -> void:
	var belief := _make_belief(5, 2, true)
	belief.fact_id = "fact_1"
	belief.confidence = 0.7

	var copy := belief.clone_deep()
	copy.confidence = 0.1
	copy.evidence_count = 99

	assert_float(belief.confidence).is_equal_approx(0.7, 0.0001)
	assert_int(belief.evidence_count).is_equal(2)

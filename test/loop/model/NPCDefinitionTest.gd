class_name NPCDefinitionTest
extends GdUnitTestSuite

# TC-NPCDEF-01：未设置字段时命中架构文档约定的默认值
func test_default_values() -> void:
	var def := NPCDefinition.new()
	assert_float(def.breakdown_threshold).is_equal_approx(85.0, 0.0001)
	assert_float(def.stress_gain_multiplier).is_equal_approx(1.0, 0.0001)
	assert_float(def.initial_stress).is_equal_approx(20.0, 0.0001)
	assert_float(def.belief_resistance_bonus).is_equal_approx(0.0, 0.0001)
	assert_dict(def.initial_trust).is_empty()
	assert_array(def.initial_beliefs).is_empty()

# clone_deep() 后修改副本的 initial_trust 不应影响原始定义
# （对应 phase1 计划 TC-WORLD-01 的前提：NPCDefinition 本身必须支持安全深拷贝）
func test_clone_deep_isolates_initial_trust() -> void:
	var def := NPCDefinition.new()
	def.initial_trust["B"] = 50.0

	var copy := def.clone_deep()
	copy.initial_trust["B"] = 0.0
	copy.initial_trust["C"] = 10.0

	assert_float(def.initial_trust["B"]).is_equal_approx(50.0, 0.0001)
	assert_bool(def.initial_trust.has("C")).is_false()

# clone_deep() 后修改副本的 initial_beliefs 不应影响原始定义
func test_clone_deep_isolates_initial_beliefs() -> void:
	var def := NPCDefinition.new()
	var belief := Belief.new()
	belief.confidence = 0.7
	def.initial_beliefs.append(belief)

	var copy := def.clone_deep()
	copy.initial_beliefs[0].confidence = 0.1

	assert_float(def.initial_beliefs[0].confidence).is_equal_approx(0.7, 0.0001)

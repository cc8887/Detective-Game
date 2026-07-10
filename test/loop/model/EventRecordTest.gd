class_name EventRecordTest
extends GdUnitTestSuite

# 目击者按追加顺序保存，不做去重（去重是感知/传播模块的职责，不是数据类职责）
func test_witnesses_preserve_append_order_without_dedup() -> void:
	var event := EventRecord.new()
	event.witnesses.append("A")
	event.witnesses.append("B")
	event.witnesses.append("A")
	assert_array(event.witnesses).contains_exactly(["A", "B", "A"])

# 不同 NPC 各自写入 chosen_interpretation_by 应互不覆盖
func test_chosen_interpretation_by_is_per_npc() -> void:
	var event := EventRecord.new()
	event.chosen_interpretation_by["A"] = Interpretation.new("alpha", 0.4, "fact_1", true)
	event.chosen_interpretation_by["B"] = Interpretation.new("beta", 0.4, "fact_1", false)

	assert_str(event.chosen_interpretation_by["A"].interpretation_id).is_equal("alpha")
	assert_str(event.chosen_interpretation_by["B"].interpretation_id).is_equal("beta")

# clone_deep() 后修改副本不应影响原始事件（快照系统正确性前提）
func test_clone_deep_is_independent() -> void:
	var event := EventRecord.new()
	event.witnesses.append("A")
	event.candidate_interpretations.append(Interpretation.new("alpha", 0.4, "fact_1", true))
	event.chosen_interpretation_by["A"] = Interpretation.new("alpha", 0.4, "fact_1", true)

	var copy := event.clone_deep()
	copy.witnesses.append("B")
	copy.candidate_interpretations[0].base_confidence = 0.9
	copy.chosen_interpretation_by["A"].base_confidence = 0.9

	assert_array(event.witnesses).contains_exactly(["A"])
	assert_float(event.candidate_interpretations[0].base_confidence).is_equal_approx(0.4, 0.0001)
	assert_float(event.chosen_interpretation_by["A"].base_confidence).is_equal_approx(0.4, 0.0001)

class_name TraumaTypeTest
extends GdUnitTestSuite

# TC-TRAUMA-01：六种创伤类型都应该能在归因偏差表里查到非空的 trigger_category / biased_belief
func test_attribution_bias_covers_all_types() -> void:
	for type in TraumaType.all_types():
		var bias: Dictionary = TraumaType.ATTRIBUTION_BIAS[type]
		assert_str(bias.get("trigger_category", "")).is_not_empty()
		assert_str(bias.get("biased_belief", "")).is_not_empty()

# TC-TRAUMA-02：六种创伤类型的崩坏方向应该齐全且互不相同（防止复制粘贴漏改）
func test_breakdown_direction_covers_all_types_and_unique() -> void:
	var directions := {}
	for type in TraumaType.all_types():
		var direction: String = TraumaType.BREAKDOWN_DIRECTION[type]
		assert_str(direction).is_not_empty()
		directions[direction] = true
	assert_int(directions.size()).is_equal(TraumaType.all_types().size())

# type_name() 应该对每种类型都返回非"未知创伤"的可读名称
func test_type_name_covers_all_types() -> void:
	for type in TraumaType.all_types():
		assert_str(TraumaType.type_name(type)).is_not_equal("未知创伤")

class_name CharacterPersonalityTest
extends GdUnitTestSuite

# 测试已知角色的性格数据
func test_get_personality_known_character() -> void:
	var personality := CharacterPersonality.get_personality("Alice")
	assert_dict(personality).contains_keys("personality", "speaking_style")
	# Alice 的职位应包含"前端工程师"
	assert_str(personality["position"]).contains("前端工程师")

# 测试未知角色返回默认值
func test_get_personality_unknown_character() -> void:
	var personality := CharacterPersonality.get_personality("UnknownPerson")
	assert_dict(personality).contains_keys("personality")
	assert_str(personality["personality"]).is_equal("普通的办公室职员")
	assert_str(personality["speaking_style"]).is_equal("正常的交谈方式")

# 测试所有角色配置的完整性
func test_all_characters_have_required_fields() -> void:
	var character_names := ["Stephen", "Tom", "Lea", "Alice", "Grace", "Jack", "Joe", "Monica"]
	for char_name in character_names:
		var p := CharacterPersonality.get_personality(char_name)
		assert_dict(p).contains_keys("position", "personality", "speaking_style", "work_duties", "work_habits")

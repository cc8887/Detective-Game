class_name RoomDataTest
extends GdUnitTestSuite

# 测试 RoomData 初始化
func test_room_data_init() -> void:
	var room := RoomData.new("办公室", Vector2(100, 200), Vector2(400, 300), "一间普通的办公室")
	assert_str(room.name).is_equal("办公室")
	assert_vector(room.position).is_equal(Vector2(100, 200))
	assert_vector(room.size).is_equal(Vector2(400, 300))
	assert_str(room.description).is_equal("一间普通的办公室")
	assert_dict(room.important_locations).is_empty()

# 测试 RoomData 默认 important_locations 为空字典
func test_room_data_default_important_locations() -> void:
	var room := RoomData.new("会议室", Vector2.ZERO, Vector2(50, 50), "")
	assert_dict(room.important_locations).is_empty()
	# 写入后应保留数据
	room.important_locations["door"] = Vector2(10, 10)
	assert_dict(room.important_locations).contains_keys("door")

class_name RoomManagerTest
extends GdUnitTestSuite

const RoomManagerScript = preload("res://script/RoomManager.gd")

# 测试位置在房间内
func test_is_position_in_room_inside() -> void:
	var room := RoomData.new("办公室", Vector2(100, 100), Vector2(200, 200), "测试房间")
	var manager := RoomManagerScript.new()
	assert_bool(manager.is_position_in_room(Vector2(100, 100), room)).is_true()
	assert_bool(manager.is_position_in_room(Vector2(50, 50), room)).is_true()
	assert_bool(manager.is_position_in_room(Vector2(150, 150), room)).is_true()
	manager.free()

# 测试位置在房间外
func test_is_position_in_room_outside() -> void:
	var room := RoomData.new("办公室", Vector2(100, 100), Vector2(200, 200), "测试房间")
	var manager := RoomManagerScript.new()
	assert_bool(manager.is_position_in_room(Vector2(-1, -1), room)).is_false()
	assert_bool(manager.is_position_in_room(Vector2(201, 100), room)).is_false()
	manager.free()

# 测试 null 房间应返回 false
func test_is_position_in_room_null() -> void:
	var manager := RoomManagerScript.new()
	assert_bool(manager.is_position_in_room(Vector2(100, 100), null)).is_false()
	manager.free()

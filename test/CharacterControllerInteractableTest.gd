class_name CharacterControllerInteractableTest
extends GdUnitTestSuite

# 集成测试：验证 CharacterController 通过通用的 interact_with()/
# release_current_interactable() 与任意 Interactable（目前只有 Chair）交互，
# 不再依赖椅子专属的 sit_on_chair()/stand_up_from_chair()。

const ChairScript = preload("res://script/Chair.gd")

func _make_chair() -> Node:
	var chair: Node = auto_free(ChairScript.new())
	chair.sit_position = Vector2(0, 10)
	chair.sit_direction = "down"
	add_child(chair)
	return chair

func test_interact_with_sits_character_on_chair() -> void:
	var runner := scene_runner("res://scene/characters/Alice.tscn")
	await runner.simulate_frames(2)
	var character = runner.scene()

	var chair := _make_chair()
	chair.global_position = Vector2(200, 200)
	character.global_position = Vector2(200, 200)

	assert_bool(character.interact_with(chair)).is_true()
	assert_bool(character.is_sitting).is_true()
	assert_object(character.current_interactable).is_equal(chair)
	assert_vector(character.global_position).is_equal(Vector2(200, 210))
	assert_bool(chair.is_occupied()).is_true()

func test_interact_with_fails_when_chair_occupied() -> void:
	var runner_a := scene_runner("res://scene/characters/Alice.tscn")
	var runner_b := scene_runner("res://scene/characters/Tom.tscn")
	await runner_a.simulate_frames(2)
	await runner_b.simulate_frames(2)
	var alice = runner_a.scene()
	var tom = runner_b.scene()

	var chair := _make_chair()
	chair.global_position = Vector2(0, 0)
	alice.global_position = Vector2(0, 0)
	tom.global_position = Vector2(0, 0)

	assert_bool(alice.interact_with(chair)).is_true()
	assert_bool(tom.interact_with(chair)).is_false()
	assert_bool(tom.is_sitting).is_false()

func test_release_current_interactable_stands_character_up() -> void:
	var runner := scene_runner("res://scene/characters/Alice.tscn")
	await runner.simulate_frames(2)
	var character = runner.scene()

	var chair := _make_chair()
	chair.global_position = Vector2(0, 0)
	character.global_position = Vector2(0, 0)

	character.interact_with(chair)
	assert_bool(character.is_sitting).is_true()

	# release_current_interactable 内部状态变更发生在等待动画播放完成之前，
	# 无需等待动画即可立即验证占用状态已释放
	character.release_current_interactable()
	assert_bool(character.is_sitting).is_false()
	assert_object(character.current_interactable).is_null()
	assert_bool(chair.is_occupied()).is_false()

func test_move_to_interactable_rejects_occupied_target() -> void:
	var runner_a := scene_runner("res://scene/characters/Alice.tscn")
	var runner_b := scene_runner("res://scene/characters/Tom.tscn")
	await runner_a.simulate_frames(2)
	await runner_b.simulate_frames(2)
	var alice = runner_a.scene()
	var tom = runner_b.scene()

	var chair := _make_chair()
	chair.global_position = Vector2(300, 300)
	alice.global_position = Vector2(300, 300)

	assert_bool(alice.interact_with(chair)).is_true()
	assert_bool(tom.move_to_interactable(chair)).is_false()

# 单元测试模板
# 复制此文件到 res://test/ 目录下，修改 class_name 和测试内容
# 文件名必须与 class_name 一致，例如 MyFeatureTest.gd

class_name MyFeatureTest
extends GdUnitTestSuite

# 测试基本功能
func test_basic() -> void:
	var result := SomeClass.do_something()
	assert_str(result).is_equal("expected")

# 测试边界条件
func test_edge_case() -> void:
	var result := SomeClass.do_something(null)
	assert_bool(result.is_empty()).is_true()

# 测试错误处理
func test_error_handling() -> void:
	var result := SomeClass.do_something("")
	assert_bool(result.is_empty()).is_true()

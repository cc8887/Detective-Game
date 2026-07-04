@tool
class_name BTLog
extends BTAction
## BTLog
## 最小自定义行为树节点：tick 时向 Blackboard 上的 "log" 数组追加一条消息，
## 并通过 print 输出，便于 AI/调试观察行为树执行轨迹。
##
## 用法（运行时建树示例见 test/LimboAITest.gd）：
##   var log_task := BTLog.new()
##   log_task.message = "hello"
##   seq.add_child(log_task)

## 打印/记录的消息内容。
@export var message: String = ""


# _tick 由 LimboAI 在每次行为树步进时调用。
func _tick(_delta: float) -> Status:
	var msg := message
	if msg.is_empty():
		msg = "BTLog tick (agent=%s)" % [str(agent)]
	print("[BTLog] %s" % msg)
	# 把日志写入 blackboard 的 "log" 数组（若存在），方便测试断言。
	if blackboard != null:
		var logs = blackboard.get_var("log", null)
		if logs is Array:
			logs.append(msg)
	return SUCCESS

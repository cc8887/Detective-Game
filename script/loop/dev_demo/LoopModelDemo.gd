class_name LoopModelDemo
extends Control

## Phase 1 · Increment 1 的可视化演示面板。
## 只依赖 script/loop/model/ 下的数据类，不依赖场景树以外的任何系统（无 LLM、无存档）。
## 用法：在 Godot 编辑器中打开 res://scene/loop_dev/LoopModelDemo.tscn，按 F6 运行当前场景，
##       或点击"运行数据模型演示"按钮重新执行一遍。
## 全部条目应显示 PASS；如出现 FAIL，说明实现与 docs/design/loop-collapse-test-plan.md 的数值约定不一致。

@onready var run_demo_button: Button = $RunDemoButton
@onready var output_label: RichTextLabel = $OutputLabel

func _ready() -> void:
	run_demo_button.pressed.connect(_on_run_demo_button_pressed)
	_on_run_demo_button_pressed()

func _on_run_demo_button_pressed() -> void:
	output_label.clear()
	_append_line("[b]=== 《循环崩坏》数据模型层演示（Phase 1 · Increment 1）===[/b]")
	_run_trauma_type_demo()
	_run_belief_resistance_demo()
	_run_npc_state_isolation_demo()
	_append_line("\n[b]演示结束。[/b]对照 docs/design/loop-collapse-test-plan.md §1 的数值表核对。")

func _append_line(text: String) -> void:
	output_label.append_text(text + "\n")

func _pass_fail(condition: bool) -> String:
	return "[color=#4CAF50]PASS[/color]" if condition else "[color=#E53935]FAIL[/color]"

# --- 1. TraumaType 归因偏差 / 崩坏方向查表 ---
func _run_trauma_type_demo() -> void:
	_append_line("\n[b][1] TraumaType 归因偏差表[/b]（对照 TC-TRAUMA-01/02）")
	for type in TraumaType.all_types():
		var bias: Dictionary = TraumaType.ATTRIBUTION_BIAS[type]
		var direction: String = TraumaType.BREAKDOWN_DIRECTION[type]
		var ok: bool = bias.get("trigger_category", "") != "" \
			and bias.get("biased_belief", "") != "" and direction != ""
		_append_line("  %s -> trigger=%s, belief=%s, breakdown=%s  %s" % [
			TraumaType.type_name(type), bias.get("trigger_category"), bias.get("biased_belief"),
			direction, _pass_fail(ok)
		])

# --- 2. Belief.resistance() 核心公式，逐条对照测试计划里的数值表 ---
func _run_belief_resistance_demo() -> void:
	_append_line("\n[b][2] Belief.resistance() 数值验证[/b]（对照 TC-BELIEF-01~07）")
	_check_resistance("TC-BELIEF-01 基线", 0.0, 0, 1, false, 0.0, 0.35)
	_check_resistance("TC-BELIEF-02 高压 stress=100", 100.0, 0, 1, false, 0.0, 0.65)
	_check_resistance("TC-BELIEF-03 高龄 age=70（触顶）", 0.0, 70, 1, false, 0.0, 0.95)
	_check_resistance("TC-BELIEF-04 多佐证 evidence=20（触顶）", 0.0, 0, 20, false, 0.0, 0.95)
	_check_resistance("TC-BELIEF-05 核心创伤信念", 0.0, 0, 1, true, 0.0, 0.85)
	_check_resistance("TC-BELIEF-06 极端组合（触顶）", 100.0, 100, 100, true, 0.0, 0.95)
	_check_resistance("TC-BELIEF-07 性格加成 bonus=0.2", 0.0, 0, 1, false, 0.2, 0.55)

func _check_resistance(label: String, stress: float, age: int, evidence: int,
		core: bool, bonus: float, expected: float) -> void:
	var npc_state := NPCState.new()
	npc_state.stress = stress
	var npc_def := NPCDefinition.new()
	npc_def.belief_resistance_bonus = bonus
	var belief := Belief.new()
	belief.age_in_steps = age
	belief.evidence_count = evidence
	belief.is_core_trauma_belief = core

	var actual: float = belief.resistance(npc_state, npc_def)
	var ok: bool = abs(actual - expected) < 0.0001
	_append_line("  %s -> 实际=%.4f 期望=%.4f  %s" % [label, actual, expected, _pass_fail(ok)])

# --- 3. NPCState.clone_deep() 深拷贝隔离性 ---
func _run_npc_state_isolation_demo() -> void:
	_append_line("\n[b][3] NPCState.clone_deep() 深拷贝隔离性[/b]（对照 TC-NPCSTATE-01~05）")

	var original := NPCState.new()
	original.npc_id = "A"
	original.stress = 50.0

	var belief := Belief.new()
	belief.fact_id = "fact_1"
	belief.confidence = 0.7
	original.beliefs.append(belief)

	original.trust_towards["B"] = 60.0

	var event := EventRecord.new()
	event.event_id = "evt_1"
	event.witnesses.append("A")
	original.memory_log.append(event)

	var copy := original.clone_deep()
	copy.beliefs[0].confidence = 0.1
	copy.trust_towards["B"] = 0.0
	copy.memory_log[0].witnesses.append("Z")

	_append_line("  副本与原始对象引用不同  %s" % _pass_fail(copy != original))
	_append_line("  修改副本信念置信度后，原始值应仍为 0.7 -> 实际=%.2f  %s" % [
		original.beliefs[0].confidence, _pass_fail(abs(original.beliefs[0].confidence - 0.7) < 0.0001)
	])
	_append_line("  修改副本信任值后，原始值应仍为 60.0 -> 实际=%.2f  %s" % [
		original.trust_towards["B"], _pass_fail(abs(original.trust_towards["B"] - 60.0) < 0.0001)
	])
	_append_line("  修改副本记忆目击者后，原始 witnesses 应仍只有 1 人 -> 实际=%s  %s" % [
		str(original.memory_log[0].witnesses), _pass_fail(original.memory_log[0].witnesses.size() == 1)
	])

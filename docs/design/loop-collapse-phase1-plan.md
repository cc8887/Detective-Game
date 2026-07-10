# 《循环崩坏》Phase 1 任务拆解

**对应**：`loop-collapse-architecture.md` §14 "Phase 1：原型验证"
**范围**：纯算法推导引擎，不接入 LLM、不接入 Godot 场景/UI
**验收基准**：GDD 附录 A《遗嘱》崩坏模拟示例（唯一给出完整数值轨迹的官方样例，作为 golden test）
**运行方式**：全部通过 gdUnit4 headless 跑通，复用现有 `./runtests.sh`
**配套文档**：[`loop-collapse-test-plan.md`](./loop-collapse-test-plan.md) —— 每个功能点对应的详细 Given/When/Then 测试用例（本文档 M1.3/M1.5/M1.6 提到的测试文件在其中有完整展开）

---

## 0. Phase 1 的"完成"是什么样子

对照 GDD 原文的 5 条验收标准，逐条映射到本拆解里的具体任务：

| GDD 验收标准 | 对应任务 |
|---|---|
| 手写一个固定故事弧（3 NPC，5 时间步） | M1.5《遗嘱》Fixture |
| 实现推导引擎核心算法（step/perceive/interpret/updateBelief） | M1.3 + M1.4 |
| 实现命令行版本的复盘输出 | M1.7 |
| 验证崩坏路径和救济路径均符合预期 | M1.5（崩坏路径）+ M1.6（救济路径） |
| 验证玩家干预有效性公式的体感合理性 | M1.6 |

Phase 1 完全不依赖 `.tscn` 场景、不依赖 `APIManager`，因此可以和现有沙盒模式并行开发，互不冲突，也不需要占用美术/关卡资源。

---

## 1. 依赖关系图

```
M1.0 目录骨架
   │
M1.1 数据模型层 ──────────────┐
   │                          │
M1.2 WorldStateContext        │
   │                          │
M1.3 五个算法子模块单测 ────────┤
   │                          │
M1.4 InferenceEngine.step() 组装
   │                          │
   ├── M1.5《遗嘱》Fixture + 崩坏路径回归测试
   │                          │
   └── M1.6 Action 注入 + 有效性公式 + 救济路径回归测试
                              │
M1.7 CLI 复盘输出 ─────────────┘
   │
M1.8 验收 & 文档回填
```

M1.1~M1.4 是主链路，必须按顺序完成；M1.5 和 M1.6 可以并行（都依赖 M1.4，互不依赖）；M1.7 依赖 M1.5/M1.6 跑出的真实 `ScriptFrame` 数据。

---

## 2. M1.0 目录骨架

```
script/loop/
├── model/
├── engine/
├── fixtures/          # 新增：手写故事弧固定数据（不是 Resource 文件，直接 GDScript 构造函数）
└── tools/              # 新增：CLI 输出脚本
test/loop/
├── model/
├── engine/
└── fixtures/
```

- [ ] 创建以上目录（Godot 里空目录不会被追踪，建议每个目录先放一个 `.gdignore` 占位或直接跟着 M1.1 的第一个文件一起提交）
- [ ] 在 `docs/design/loop-collapse-architecture.md` 顶部加一条指向本文档的链接（保持两份文档互相可发现）

---

## 3. M1.1 数据模型层

严格按架构文档 §3 落地，**这一步只写数据结构和纯函数（如 `Belief.resistance()`），不写引擎逻辑**。

| 文件 | 内容 | 单测文件 |
|---|---|---|
| `model/TraumaType.gd` | 6 种创伤枚举 + `ATTRIBUTION_BIAS` + `BREAKDOWN_DIRECTION` 查表 | `TraumaTypeTest.gd` |
| `model/Visibility.gd` | `Level` 枚举 + `PRIVATE_TRUST_THRESHOLD` | — （纯常量，可省略专门测试） |
| `model/ActionPriority.gd` | 优先级分层常量 | — |
| `model/NPCDefinition.gd` | 静态属性 Resource | `NPCDefinitionTest.gd`（默认值校验） |
| `model/Belief.gd` | 信念 + `resistance()` | `BeliefTest.gd`（**重点**：抵抗力上限 0.95、核心创伤 +0.5、各项系数独立叠加） |
| `model/Interpretation.gd` | 候选解读 | — |
| `model/EventRecord.gd` | 客观事件/记忆库条目 | `EventRecordTest.gd`（`witnesses`/`chosen_interpretation_by` 的增删） |
| `model/NPCState.gd` | 动态属性 + `clone_deep()` | `NPCStateTest.gd`（**重点**：`clone_deep()` 后修改副本不影响原对象，这是快照系统的正确性前提） |
| `model/WorldFact.gd` | 客观事实 | — |
| `model/TimeStepSpec.gd` | 时间步定义 | — |
| `model/ActionDefinition.gd` | Action 定义（四层结构） | `ActionDefinitionTest.gd`（`Tier` 枚举与解锁条件字段） |
| `model/PlayerActionRequest.gd` | 玩家提交的 Action 请求 | — |
| `model/ScriptFrame.gd` | 叙事帧 | — |
| `model/PlayerActionResolution.gd` | 干预结算结果 | — |
| `model/LoopRecord.gd` | 单轮循环记录 | — |
| `model/StoryArcDefinition.gd` | 故事弧聚合定义 | — |

**验收标准**：`./runtests.sh res://test/loop/model/` 全绿；`Belief.resistance()` 对以下边界值有专门断言：
- 压力 0 / 50 / 100 三档
- `age_in_steps` = 0 / 50（确认线性无溢出）
- `evidence_count` = 1 / 20（确认能触顶 0.95）
- `is_core_trauma_belief` = true 时单独 +0.5 是否叠加正确

---

## 4. M1.2 WorldStateContext（补充设计，架构文档中省略的关键拼接类）

架构文档 §4.1 的 `InferenceEngine.world` 在主文档里只以用法出现，没有单独展开定义，这里补齐：

```gdscript
class_name WorldStateContext
extends RefCounted

var npc_defs: Dictionary = {}       # npc_id -> NPCDefinition
var npc_states: Dictionary = {}     # npc_id -> NPCState
var facts: Dictionary = {}          # fact_id -> WorldFact
var events_by_id: Dictionary = {}   # event_id -> EventRecord（含尚未触发的）
var current_step_index: int = 0
var breakdown_log: Array = []       # [{npc_id, step_index}]

func load_from_arc(arc: StoryArcDefinition, loop_variance: Dictionary = {}) -> void
func all_npc_ids() -> Array
func get_npc_state(id: String) -> NPCState
func get_npc_def(id: String) -> NPCDefinition
func get_trust(from_id: String, to_id: String) -> float
func activate_scheduled_events(event_ids: Array) -> Array   # 返回 Array[EventRecord]
func mark_breakdown(npc_id: String, step_index: int) -> void
func has_breakdown() -> bool
func advance_step() -> void
func snapshot() -> Dictionary   # 深拷贝可序列化字典，供 M1.7 CLI 与后续 LoopSnapshotStore 使用
```

- [ ] 实现 `load_from_arc`：把 `StoryArcDefinition.npc_definitions` 转成 `npc_states`（初始信念/信任/压力从 `NPCDefinition` 拷贝，注意信任是 `Dictionary` 需要深拷贝不能共享引用）
- [ ] 实现 `get_trust`：读 `npc_states[from_id].trust_towards.get(to_id, 0.0)`，玩家 id 固定用 `"__player__"`
- [ ] 实现 `snapshot()`：不能直接 `duplicate()` 整个 Dictionary（浅拷贝会共享子对象引用），必须逐个 NPCState 调 `clone_deep()`

**验收标准**：`WorldStateContextTest.gd` 验证 `load_from_arc` 后修改某个 NPC 的信任值不会影响 `NPCDefinition.initial_trust`（防止"重置循环"时脏数据污染下一轮初始条件）。

---

## 5. M1.3 五个算法子模块（各自独立可测）

严格对应架构文档 §4.2~§4.6，**先写这五个模块并单独打靠边球测试，最后才在 M1.4 里组装成 `step()`**，这样出 bug 时能立刻定位到具体是哪一层算错。

### 5.1 `PerceptionFilter.gd`

- [ ] `PUBLIC`：任何 NPC 都能感知
- [ ] `SECRET`：只有 `actors` 里的人能感知
- [ ] `PRIVATE`：目击者直接感知；非目击者需要**某个目击者对该 NPC 的信任 > 40** 才能感知——⚠️ 方向容易写反，务必按架构文档 §4.2 的强调专门测一条"信任方向"用例：A 是目击者，A 对 C 信任 60，B 对 C 信任 0 → C 应该能感知（因为是 A 愿意告诉 C，不看 B）

`PerceptionFilterTest.gd` 至少 4 个 case：public 无差别 / secret 仅当事人 / private 目击者直接可见 / private 通过信任链可见（方向测试）。

### 5.2 `InterpretationResolver.gd`

- [ ] 基础分数 = `base_confidence`
- [ ] 命中支持信念：`+0.4 * matching_belief.confidence`
- [ ] 命中冲突信念：`-0.3 * conflicting_belief.confidence`
- [ ] `stress > 60` 时对负面解读线性加权（按架构文档公式 `(stress-60)/40*0.3`）
- [ ] 平局情况下的 tie-break 规则需要显式定义并测试（架构文档未指定，建议：取 `candidate_interpretations` 数组中靠前的一个，保证确定性）

`InterpretationResolverTest.gd` 覆盖：无信念时选 base_confidence 最高项 / 有支持信念时逆转选择 / 高压时负面解读胜出 / 平局确定性。

### 5.3 `BeliefUpdater.gd`

- [ ] 全新信念创建
- [ ] 同方向强化：`confidence = min(1.0, confidence + 0.1*base_confidence)`，`evidence_count += 1`
- [ ] 反方向挑战：`drop = base_confidence * (1 - resistance)`，`confidence -= drop`
- [ ] 置信度 < 0.2 时翻转方向并重置 `evidence_count=1, age_in_steps=0`
- [ ] 认知失调固定 `+10` 压力（无论翻转成功与否，只要发生"挑战"就要加）

`BeliefUpdaterTest.gd` 覆盖以上 5 种路径，并验证 `last_stress_delta` 只在"挑战"路径产生非零值。

### 5.4 `AttributionPropagator.gd`

- [ ] 深度上限 3 层的递归终止
- [ ] 同一个 `event_id` 在一次 `propagate()` 调用内不会被访问两次（`visited_event_ids` 去重）
- [ ] 触发新一层传播时压力叠加正确累计到 `PropagateResult.stress_delta`

`AttributionPropagatorTest.gd` 需要构造一个人工的"链式记忆"fixture（4 条互相关联的记忆，验证第 4 条不会被处理，因为深度上限是 3）。

### 5.5 `BreakdownEvaluator.gd`

- [ ] `stress < breakdown_threshold` → 不形成意图
- [ ] 无核心创伤信念，或核心创伤信念 `confidence < 0.75` → 不形成意图
- [ ] 满足条件 → 返回 `{type, target, formed_at_step}`，`type` 来自 `TraumaType.BREAKDOWN_DIRECTION`

`BreakdownEvaluatorTest.gd` 覆盖临界值（`stress == threshold` 是否算触发，需要在实现前明确"≥"还是">"，建议按 GDD 附录 A"压力值 85，恰好触及崩坏阈值"的措辞定为 `>=`）。

**M1.3 整体验收标准**：`./runtests.sh res://test/loop/engine/` 全绿，且五个测试文件之间**不互相 import 对方的实现**（保证真的是隔离单测，不是靠组合测试凑出来的绿）。

---

## 6. M1.4 `InferenceEngine.step()` 组装

- [ ] 按架构文档 §4.1 伪代码实现 `step(spec, player_action)`，五阶段顺序不可打乱
- [ ] 强制约束检查：`script/loop/engine/` 目录下任何文件不得出现 `HTTPRequest` / `APIManager` / `randi(` / `randf(` / `rand_range(` 字样
  - [ ] 写一条 `EngineDeterminismLintTest.gd`，用 `DirAccess` 遍历 `res://script/loop/engine/*.gd` 读取文件内容做字符串扫描断言，防止未来有人不小心引入随机数或网络调用
- [ ] `InferenceEngineDeterminismTest.gd`：对同一个 `StoryArcDefinition` fixture，`step()` 跑两遍完全独立的引擎实例，逐字段比较所有 `ScriptFrame` 和 `WorldStateContext.snapshot()` 结果必须相等

**验收标准**：确定性测试通过 + lint 测试通过。这一步跑通之后，"核心真相层"就已经建立起来，后续 M1.5/M1.6 只是往里喂不同的 fixture。

---

## 7. M1.5《遗嘱》Fixture 复刻（崩坏路径回归测试）

直接把 GDD 附录 A 的完整数值轨迹当作 golden test，是 Phase 1 性价比最高的一步——不需要自己设计数值，答案已经写在 GDD 里了。

### 7.1 Fixture 内容（`fixtures/WillArcFixture.gd`）

3 个 NPC：
- **A**（长子，`INJUSTICE`，breakdown_threshold=85，初始 stress=35，初始信念"父亲从未重视过我" confidence=0.75）
- **B**（次子）
- **母亲**（Mother，对 A 信任=70）

5 个时间步的事件序列，逐条还原 GDD 附录 A 原文：

| T | 事件 | 关键数值 |
|---|------|---------|
| T=1 | 遗嘱公开（PUBLIC） | 候选解读 α/β 各 base_confidence=0.4 |
| T=2 | A 解读遗嘱 + 归因链传播（2 条旧记忆被重新解读） | stress 35→58→73 |
| T=2/T=3 | 玩家干预失败（向 A 传递事实 F1，玩家信任度 35） | effectiveness≈0.069，confidence 0.70→0.67，stress +3 |
| T=4 | B 与律师会面（PRIVATE，经母亲转述） | confidence 0.67→0.81，stress 76→85 |
| T=5 | 崩坏检查 | stress=85=breakdown_threshold，核心信念 confidence=0.81>0.75 → 崩坏 |

- [ ] 把上表编码成 `StoryArcDefinition` + 对应 `EventRecord`/`Interpretation` 数据
- [ ] `WillArcBreakdownTest.gd`：不提交任何玩家 Action，跑满 5 步，断言：
  - T=2 结束后 `A.stress` 在 `[70, 76]`（GDD 给的是 73，允许小范围容差，因为归因链传播的两条记忆 +8/+7 顺序可能造成浮点误差）
  - T=4 结束后 `A.stress` 在 `[83, 87]`
  - T=5 触发崩坏，`breakdown_log` 记录 `{npc_id: "A", step_index: 5}`

> 如果实现后跑出来的数字和 GDD 差异较大（不是浮点误差级别，而是整体走势不对），说明某个子模块的公式理解有偏差，应该回到 M1.3 对应模块修正，而不是反向修改 fixture 数值去凑 —— fixture 的数值来自设计文档，是"标准答案"，不是可调参数。

---

## 8. M1.6 Action 注入 + 有效性公式（救济路径回归测试）

复用 M1.5 的《遗嘱》fixture，但换一条玩家干预序列，还原 GDD 附录 A 结尾给出的"最优干预路径"：

> 第一步 T=1 陪伴母亲信任建立至 60；第二步 T=2 立即引导母亲向 A 说明 B 的真实身世 → A"父亲偏心"信念置信度降至约 0.15，归因链不触发，stress 维持约 45，T=5 不崩坏

- [ ] 实现 §5 架构文档的 `ActionQueueResolver`（Phase 1 只需要"单个玩家 Action 的注入 + 有效性结算"，暂不需要完整的"多来源优先级竞争队列"，因为 fixture 里没有 NPC 自发行为与之竞争——**这是 Phase 1 的合理简化**，完整队列竞争放到 Phase 4 结合真实场景再补全）
- [ ] `WillArcRescueTest.gd`：
  - 第一步提交"陪伴母亲"Action，断言母亲对玩家信任从 0 提升到 60 附近
  - 第二步提交"引导母亲说出真相"Action，断言 `effectiveness_score >= 0.5`（成功），且 A 的"父亲偏心"信念 `confidence` 降到 0.2 以下并翻转方向
  - 跑完剩余步骤，断言 `breakdown_log` 为空（未崩坏），且 `A.stress` 在 T=5 时低于 `breakdown_threshold`
- [ ] 补一条"失败干预"的回归测试：还原 T=3 那次失败的干预（玩家信任度 35，直接对信念年龄1/佐证3/压力73 的信念发起挑战），断言 `effectiveness_score` 落在 `[0.05, 0.09]` 区间（对应 GDD 给出的 0.069）

**验收标准**：崩坏路径（M1.5）与救济路径（M1.6）用的是**同一份初始条件**、仅玩家 Action 序列不同，这正是 GDD "验证崩坏路径和救济路径均符合预期"的字面要求——一份 fixture，两种玩法结果。

---

## 9. M1.7 CLI 复盘输出

不需要真正接入 LLM，只需要把 `ScriptFrame` 结构体格式化成人类可读的中文文本，验证"数据结构够不够支撑叙事"这件事本身。

- [ ] `script/loop/tools/run_arc_cli.gd`：一个 `SceneTree` 子类脚本（参照 gdUnit4 自身 `GdUnitCmdTool.gd` 的写法），加载 `WillArcFixture`，跑满 5 步（先无干预崩坏一次，再用救济路径跑一次），把每步产生的 `ScriptFrame` 用简单模板打印，例如：

  ```
  [T=2 第二天上午 | 书房] A 感知：遗嘱公开，全部遗产留给次子B
    -> A 的解读：父亲故意偏心B（置信度 0.70）
    -> 压力变化：+23（35 → 58）
  ```

- [ ] 在 `runtests.sh` 旁新增 `run_loop_cli.sh`，用法参照现有脚本风格：
  ```bash
  "$GODOT_BIN" --headless --path . -s res://script/loop/tools/run_arc_cli.gd
  ```

**验收标准**：命令行运行后完整打印出崩坏路径和救济路径两条轨迹，肉眼看文本即可复述出 GDD 附录 A 的完整因果链——这就是 GDD 要求的"命令行版本的复盘输出"。

---

## 10. M1.8 验收与文档回填

- [ ] `./runtests.sh res://test/loop/` 全绿（建议同时跑一次 `./runtests.sh res://test/` 确认没有破坏沙盒模式现有测试）
- [ ] 在 `loop-collapse-architecture.md` §14 "Phase 1" 下补一行"已完成，详见 `loop-collapse-phase1-plan.md`"及关键实现偏差记录（如果有任何数值/公式在实现时发现和文档不一致，在这里回填修正说明，保持两份文档同步）
- [ ] 团队 Review 时重点看两点：
  1. `script/loop/engine/` 是否真的做到零 LLM/零随机数依赖（lint 测试是否覆盖到位）
  2. 《遗嘱》fixture 的两条回归测试是否真的是"同一份初始条件、仅 Action 不同"，而不是为了让测试通过偷偷改了初始条件

---

## 11. 明确排除在 Phase 1 之外的内容（避免范围蔓延）

- ❌ 任何 `.tscn` 场景 / UI（表现层是 Phase 4）
- ❌ `NarrativeBridge` / `StoryArcGenerator`（LLM 集成是 Phase 2）
- ❌ `LoopController` 状态机、`LoopSnapshotStore`、`StoryProgressSave`（循环控制与持久化是 Phase 3/4）
- ❌ `ActionUnlockManager`（Action 解锁系统是 Phase 4）
- ❌ 完整的多来源优先级竞争队列（Phase 1 的 `ActionQueueResolver` 只需支持"单个玩家 Action vs 无竞争对手"这个最简场景，见 M1.6 说明）

保持 Phase 1 范围收紧在"确定性算法本身能不能跑对"这一件事上，是它能在不依赖任何美术/UI/LLM 资源的情况下独立验收的关键。

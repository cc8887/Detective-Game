# 《循环崩坏》游戏架构分析

**基于**：`GDD_循环崩坏.md` v0.1
**目标代码库**：Detective-Game / Microverse（Godot 4.7, GDScript）
**分支**：`feature/game-architecture-analysis`
**分析深度**：详细技术设计（数据结构 / 类划分 / 算法伪代码级别）
**前提**：复用现有工程基础设施，不推翻现有 Godot 项目骨架

---

## 0. 结论先行

《循环崩坏》与当前 Microverse 沙盒在**呈现层技术栈**（Godot 场景、角色移动、对话气泡、LLM API 调用、存档 JSON 化）上高度可复用，但在**决策核心**上是根本性的范式转变：

| 维度 | Microverse 现状 | 《循环崩坏》要求 |
|------|----------------|-----------------|
| NPC 决策来源 | 每次决策都现场组一大段 prompt，直接把"要不要做 XX"这个判断交给 LLM | 决策由**纯算法**（压力/信任/信念/归因）确定性计算，LLM 完全不参与判定 |
| 随机性/可复现性 | 无所谓，反正是沙盒 | **强制要求**：相同初始条件 + 相同玩家干预序列 → 永远相同结果（供复盘/最优路径回溯） |
| 时间模型 | 连续时间 + Timer 轮询（60s 一次决策）+ 全局倍速 | 离散**时间步**，每步是一次完整的"扳机式"计算轮次，无倍速概念 |
| 记忆模型 | 扁平字符串列表（`content/type/importance/timestamp`） | 需要区分**客观事件记忆**（EventRecord）与**主观信念**（Belief，含置信度/抵抗力/佐证链） |
| 玩家干预 | 玩家=一个可控角色，直接对话即生效 | 玩家=无实体观察者，干预是"注入队列 + 优先级竞争"，可能被拒绝/压制/反效果 |
| 存档语义 | 单一存档=当前世界快照 | 需要拆分为「本轮循环历史（可重放/复盘）」与「跨循环持久知识（事实/断层/解锁）」两套持久化 |

因此本分析的核心任务是：**在现有 Godot 工程骨架上新增一个独立的、不依赖 LLM 的确定性推导引擎（Inference Engine）子系统**，同时最大化复用现有的 LLM 调用层、房间/视野系统、UI 框架和存档基础设施。

---

## 1. 现有工程可复用资产清单

| 现有模块 | 文件 | 复用方式 |
|---------|------|---------|
| 多 LLM 供应商抽象 | `script/ai/APIManager.gd` + `APIConfig.gd` | 直接复用，仅新增两类 prompt 模板（初始条件生成 / 叙事包装+对话生成），职责从"决策"降级为"文本生成" |
| 房间/地点系统 | `script/RoomManager.gd`, `RoomData.gd`, `RoomArea.gd` | 直接对应 GDD §12.4「地点节点」，观察者的位置=当前 Room |
| 视野/遮挡系统 | `script/FogOfWarManager.gd` | 复用其可见性多边形计算，作为「观察者能否感知某地点事件」及「NPC 之间是否同地点」的几何基础 |
| 暂停/倍速 | `script/PauseManager.gd` | 倍速机制不再需要（离散时间步无所谓快慢），但 `Engine.time_scale`/灰化视觉的模式可复用于「叙事文本播放速度」这类非物理时间的控制 |
| 可交互物基类 | `script/Interactable.gd` | 其"虚方法覆盖 + 统一注册"模式是设计 `ActionDefinition` 四层体系的直接参照 |
| 角色人设静态配置 | `script/CharacterPersonality.gd` | 结构可扩展为 `NPCDefinition`（增加创伤类型、崩坏阈值等字段），Phase 1 手写故事弧可沿用这种"静态字典"写法 |
| 记忆系统 | `script/ai/memory/MemoryManager.gd` | 拆分为二：客观事件日志沿用其"追加+清理"模式；主观信念需要全新的 `BeliefStore`（详见 §5.3） |
| 存档 JSON 化模式 | `script/GameSaveManager.gd` | 复用其文件 I/O 与 `collect_*`/`apply_*` 结构，但存档语义需要重新设计（§11） |
| 上帝视角调试面板 | `script/ui/GodUI.gd`, `scene/ui/GodUI.tscn` | 其"角色列表 + 详情 Tab + 弹窗注入状态"的布局，是复盘 UI 和开发期调试面板的直接参照骨架 |
| JSON→资源热加载模式 | `script/ai/bt/BTJsonLoader.gd` | 证明本工程已有"LLM 只需输出 JSON，引擎负责解析构建"的先例，可直接照搬这个模式做 `StoryArcJsonLoader` |
| 行为树框架 LimboAI | `addons/limboai/`, `script/ai/bt/` | **不用于决策**（会破坏确定性/可重放性），仅可选用于 NPC 在地点之间走动的寻路/动画表现层 |
| 测试框架 | `addons/gdUnit4/`, `.windsurf/skills/gdunit4-testing` | 推导引擎的确定性正是 gdUnit4 单元测试的最佳应用场景（给定输入断言唯一输出） |
| 对话气泡/聊天记录 UI | `script/ui/DialogBubble.gd`, `script/ChatHistory.gd` | 可复用于 NPC 间对话的呈现层，但对话生成的"决策"部分（继续/结束对话）需要被推导引擎接管，LLM 只管措辞 |

**不建议复用/需要新写的部分**：`AIAgent.gd` 的决策循环（prompt 里问"1/2选哪个"）、`ConversationManager.gd` 的双向轮流生成对话逐字发出的模式（对话内容生成可以保留 API 调用方式，但"是否继续对话"这个判定必须移交推导引擎）。

---

## 2. 分层架构总览

严格对应 GDD §13.1 的四层，同时标注 Godot 侧实现形态：

```
┌─────────────────────────────────────────────────────────────┐
│ L4 表现层 (Presentation)                                      │
│   Godot Scene / CanvasLayer UI / 角色移动动画 / DialogBubble   │
│   新增: LoopMainUI(叙事区+NPC状态栏+行动区) / ReviewUI / …      │
├─────────────────────────────────────────────────────────────┤
│ L3 叙事接口层 (Narrative Bridge)                               │
│   新增 autoload: NarrativeBridge.gd                           │
│   ScriptFrame -> LLM prompt -> 自然语言文本                    │
│   玩家 Action(UI) -> PlayerActionRequest -> 推导引擎           │
├─────────────────────────────────────────────────────────────┤
│ L2 推导引擎层 (Inference Engine) — 核心真相，纯算法无随机数     │
│   新增: InferenceEngine (RefCounted) + WorldState/NPCState/   │
│   Belief/TrustMatrix/ActionQueue 等纯数据类                    │
├─────────────────────────────────────────────────────────────┤
│ L1 初始条件生成层 (Story Arc Generation)                       │
│   新增: StoryArcGenerator(调用 LLM) + StoryArcValidator(算法)  │
│   仅在故事弧开始时运行一次                                      │
└─────────────────────────────────────────────────────────────┘
```

关键设计原则（延续 GDD §13.2）：**L2 层任何类都不得直接持有 `HTTPRequest`/`APIManager` 引用，也不得调用 `randi()`/`randf()`**。这是保证"确定性可复盘"的硬约束，需要在 code review / lint 层面强制（可写一条 gdUnit4 测试静态扫描 `script/loop/engine/` 目录禁止出现 `APIManager`、`randi`、`randf` 字样）。

---

## 3. 核心数据模型

建议新增目录 `script/loop/` 存放全部新系统，与沙盒模式的 `script/ai/` 完全隔离，便于两种游戏模式共存/切换或未来剥离成独立项目。

```
script/loop/
├── model/                  # 纯数据类（Resource 或 RefCounted）
│   ├── NPCDefinition.gd        # 静态属性
│   ├── NPCState.gd             # 动态属性
│   ├── Belief.gd
│   ├── TrustMatrix.gd
│   ├── EventRecord.gd
│   ├── WorldFact.gd
│   ├── TimeStepSpec.gd
│   ├── ActionDefinition.gd
│   ├── PlayerActionRequest.gd
│   ├── ScriptFrame.gd
│   ├── StoryArcDefinition.gd
│   └── LoopRecord.gd
├── engine/                 # 推导引擎（禁止依赖 LLM/随机数）
│   ├── InferenceEngine.gd
│   ├── PerceptionFilter.gd
│   ├── InterpretationResolver.gd
│   ├── AttributionPropagator.gd
│   ├── BeliefUpdater.gd
│   ├── ActionQueueResolver.gd
│   └── BreakdownEvaluator.gd
├── generation/              # LLM 生成 + 验证
│   ├── StoryArcGenerator.gd
│   ├── StoryArcValidator.gd
│   └── StoryArcJsonLoader.gd
├── bridge/                  # 叙事接口层
│   ├── NarrativeBridge.gd
│   ├── ScriptFrameFormatter.gd
│   └── DialogueConstraintBuilder.gd
├── loop/                    # 循环/时间步控制
│   ├── LoopController.gd    # autoload
│   └── LoopSnapshotStore.gd
├── persistence/
│   ├── StoryProgressSave.gd  # 跨循环持久化
│   └── LoopSaveManager.gd
└── unlock/
    └── ActionUnlockManager.gd
```

### 3.1 NPCDefinition（静态属性，对应 GDD §5.1 上半部分）

```gdscript
class_name NPCDefinition
extends Resource

@export var id: String
@export var display_name: String
@export var trauma_type: TraumaType.Type          # 见 3.2
@export var breakdown_threshold: float = 85.0
@export var stress_gain_multiplier: float = 1.0    # 敏感型>1，冷静型<1
@export var belief_resistance_bonus: float = 0.0
@export var initial_beliefs: Array[Belief] = []
@export var initial_trust: Dictionary = {}          # { npc_id: float }
@export var initial_stress: float = 20.0
@export var background_summary: String = ""
```

### 3.2 创伤类型（GDD §5.2 / §5.4）

```gdscript
class_name TraumaType
extends RefCounted

enum Type { ABANDONMENT, BETRAYAL, UNWORTHINESS, CONTROL_LOSS, INJUSTICE, ISOLATION }

# 归因偏差规则表：事件的"模糊性类别" -> 该创伤会把它归因成什么负面判断
const ATTRIBUTION_BIAS := {
    Type.ABANDONMENT:  {"trigger_category": "departure_or_change", "biased_belief": "is_being_abandoned"},
    Type.BETRAYAL:     {"trigger_category": "private_behavior",    "biased_belief": "is_being_schemed_against"},
    Type.UNWORTHINESS: {"trigger_category": "positive_event",      "biased_belief": "is_pity_not_merit"},
    Type.CONTROL_LOSS: {"trigger_category": "unexpected_event",    "biased_belief": "is_losing_control"},
    Type.INJUSTICE:    {"trigger_category": "disparity",           "biased_belief": "is_unfairly_targeted"},
    Type.ISOLATION:    {"trigger_category": "affection_shown",     "biased_belief": "is_fake_concern"},
}

const BREAKDOWN_DIRECTION := {
    Type.ABANDONMENT:  "attack_or_withdraw",
    Type.BETRAYAL:     "preemptive_strike",
    Type.UNWORTHINESS: "self_harm_or_sabotage",
    Type.CONTROL_LOSS:  "extreme_control_or_giveup",
    Type.INJUSTICE:    "retaliation",
    Type.ISOLATION:    "cut_all_ties",
}
```

> 这里刻意用 `trigger_category`/`biased_belief` 这类**枚举化的语义标签**而不是自由文本，是为了让 L1 生成层（LLM）在描述"事件的候选解读"时，只需要给每个候选解读打上分类标签，L2 引擎就能用查表方式而非文本理解来判定"这个解读是否命中了 NPC 的创伤"。LLM 完全不参与这个判定过程。

### 3.3 NPCState（动态属性，对应 GDD §5.1 下半部分）

```gdscript
class_name NPCState
extends RefCounted

var npc_id: String
var stress: float
var beliefs: Array[Belief] = []          # 见 3.4
var trust_towards: Dictionary = {}        # { target_id: float } 非对称
var suspicion_towards: Dictionary = {}    # { target_id: float } 当前怀疑度
var intent: Dictionary = {}               # {} 表示无意图；否则 {type, target, formed_at_step}
var memory_log: Array[EventRecord] = []   # "记忆库"——已感知并解读过的事件
var pending_action_queue: Array = []      # 本时间步待竞争的行为，见 §7

func duplicate_deep() -> NPCState:
    # 用于 LoopSnapshotStore 逐步快照，必须是深拷贝，不能共享引用
    ...
```

### 3.4 Belief（信念，GDD §5.3 / §6.4）

```gdscript
class_name Belief
extends RefCounted

var fact_id: String            # 关联的客观事实 ID（见 WorldFact）
var direction: bool             # true=相信为真，false=相信为假
var confidence: float           # 0.0 ~ 1.0
var age_in_steps: int = 0
var evidence_count: int = 1
var source: String = ""         # 来源：npc_id 或 event_id
var is_core_trauma_belief: bool = false

func resistance(npc_state: NPCState, npc_def: NPCDefinition) -> float:
    var r := 0.3
    r += npc_state.stress * 0.003
    r += age_in_steps * 0.01
    r += evidence_count * 0.05
    if is_core_trauma_belief:
        r += 0.5
    r += npc_def.belief_resistance_bonus
    return min(r, 0.95)
```

### 3.5 TrustMatrix

不单独建类，直接用 `NPCState.trust_towards`（含玩家，玩家 id 固定为 `"__player__"`），因为信任本质上就是"该 NPC 对某目标"的单向映射，属于每个 NPC 自己的状态，不需要全局矩阵类。全局访问通过 `InferenceEngine.get_trust(from_id, to_id)` 提供只读查询接口即可。

### 3.6 EventRecord（客观事件 / 记忆库条目）

```gdscript
class_name EventRecord
extends RefCounted

var event_id: String
var time_step: int
var location: String
var visibility: Visibility.Level      # PUBLIC / PRIVATE / SECRET
var actors: Array[String]             # 主体
var targets: Array[String]            # 客体
var raw_description: String            # 客观描述（给 LLM 叙事用，不含解读）
var candidate_interpretations: Array[Interpretation]
var chosen_interpretation_by: Dictionary = {}  # { npc_id: Interpretation }
var witnesses: Array[String] = []      # 直接目击者（perceive 阶段填充）
```

```gdscript
class_name Interpretation
extends RefCounted

var interpretation_id: String
var base_confidence: float
var resulting_fact_id: String
var resulting_direction: bool
var trigger_category: String          # 对应 TraumaType.ATTRIBUTION_BIAS 的 key
```

### 3.7 Visibility（GDD §6.2）

```gdscript
class_name Visibility
extends RefCounted

enum Level { PUBLIC, PRIVATE, SECRET }
const PRIVATE_TRUST_THRESHOLD := 40.0
```

### 3.8 ActionDefinition（玩家 Action，GDD §7.3 / §15.2）

```gdscript
class_name ActionDefinition
extends Resource

enum Tier { BASE, INFORMATION, RELATIONSHIP, BREAKTHROUGH }

@export var action_id: String
@export var tier: Tier
@export var target_npc_ids: Array[String] = []      # 1 或 2 个
@export var content_template: String                # 自然语言模板，供 LLM 叙事时套用
@export var base_priority_weight: float = 0.3        # 情感支持>信息传递>行为引导，由此字段区分
@export var execution_conditions: Array[Dictionary] = []  # [{type:"stress_below", value:60}, ...]
@export var side_effect_tags: Array[String] = []
@export var unlock_condition: Dictionary = {}         # 见 §13
@export var is_time_limited: bool = false             # 情境依赖型
@export var expires_condition: Dictionary = {}
```

### 3.9 TimeStepSpec（GDD §4.1）

```gdscript
class_name TimeStepSpec
extends Resource

@export var index: int
@export var narrative_label: String        # "第一天下午"
@export var primary_location: String
@export var scheduled_events: Array[String] = []   # event_id 列表
@export var intervention_window_open: bool = true
@export var is_key_window: bool = false
```

### 3.10 StoryArcDefinition（L1 生成层输出，GDD §8.1）

```gdscript
class_name StoryArcDefinition
extends Resource

@export var arc_id: String
@export var setting_description: String
@export var narrative_tone: String
@export var total_steps: int
@export var npc_definitions: Array[NPCDefinition] = []
@export var world_facts: Array[WorldFact] = []
@export var events: Array[EventRecord] = []
@export var time_steps: Array[TimeStepSpec] = []
@export var default_breakdown_step: int
@export var information_gaps: Array[Dictionary] = []   # GDD §8.1 "关键信息断层列表"
```

```gdscript
class_name WorldFact
extends RefCounted
var fact_id: String
var content: String
var known_by: Array[String] = []
var earliest_reveal_step: int = 0
```

### 3.11 ScriptFrame（叙事帧，GDD §9.2）

```gdscript
class_name ScriptFrame
extends RefCounted

var time_label: String
var location: String
var event_type: String            # "perception" / "action" / "dialogue"
var subject_id: String
var object_id: String
var perceived_content: String
var interpretation_summary: Dictionary   # {fact_id, direction, confidence}
var stress_delta: float
var dominant_emotion: String
var behavior_output: String
var intent_formed: bool
var narrative_constraints: Array[String]  # 传给 LLM 的"禁止事项"
```

### 3.12 LoopRecord / ReviewFrame（复盘数据，GDD §10）

```gdscript
class_name LoopRecord
extends RefCounted

var loop_index: int
var arc_id: String
var step_snapshots: Array[WorldStateSnapshot] = []   # 逐步快照，见 §11.1
var player_actions: Array[PlayerActionResolution] = []
var outcome: String   # "breakdown" / "resolved"
var breakdown_npc_id: String = ""
var breakdown_step: int = -1
var information_gaps_revealed: Array[Dictionary] = []
```

```gdscript
class_name PlayerActionResolution
extends RefCounted

var step_index: int
var action_id: String
var target_npc_id: String
var trust_at_execution: float
var target_belief_resistance: float
var timing_coefficient: float
var stress_coefficient: float
var effectiveness_score: float     # 各因子相乘
var succeeded: bool
var failure_reason: String
```

---

## 4. 推导引擎（InferenceEngine）详细设计

### 4.1 主循环：`step()`

```gdscript
class_name InferenceEngine
extends RefCounted

var world: WorldStateContext            # 持有全部 NPCState + WorldFact + 当前 step index
var perception := PerceptionFilter.new()
var interpretation := InterpretationResolver.new()
var propagator := AttributionPropagator.new()
var belief_updater := BeliefUpdater.new()
var breakdown_evaluator := BreakdownEvaluator.new()
var action_resolver := ActionQueueResolver.new()

# 每个时间步调用一次，返回本步产生的全部 ScriptFrame（供叙事接口层消费）
func step(spec: TimeStepSpec, player_action: PlayerActionRequest) -> Array[ScriptFrame]:
    var frames: Array[ScriptFrame] = []

    # 阶段1：触发预定事件
    var active_events := world.activate_scheduled_events(spec.scheduled_events)

    # 阶段2：逐 NPC 独立运行 perceive -> interpret -> attribute -> propagate -> updateEmotion
    for npc_id in world.all_npc_ids():
        var npc := world.get_npc_state(npc_id)
        var npc_def := world.get_npc_def(npc_id)
        for event in active_events:
            if not perception.can_perceive(npc, event, world):
                continue
            npc.memory_log.append(event)
            event.witnesses.append(npc_id)

            var chosen := interpretation.resolve(npc, npc_def, event)
            event.chosen_interpretation_by[npc_id] = chosen

            var belief := belief_updater.apply(npc, npc_def, chosen)
            var propagate_result := propagator.propagate(npc, npc_def, belief, max_depth=3)

            var stress_delta := belief_updater.last_stress_delta + propagate_result.stress_delta
            npc.stress = clamp(npc.stress + stress_delta, 0, 100)

            frames.append(ScriptFrameFormatter.from_perception(
                spec, npc_id, event, chosen, belief, stress_delta))

    # 阶段3：崩坏检查（在处理玩家行动之前，行动只能影响“正在形成”而非“已经形成”的意图）
    for npc_id in world.all_npc_ids():
        var npc := world.get_npc_state(npc_id)
        var npc_def := world.get_npc_def(npc_id)
        if npc.intent.is_empty():
            var intent := breakdown_evaluator.check(npc, npc_def)
            if not intent.is_empty():
                npc.intent = intent

    # 阶段4：意图执行（若本步已到达崩坏时间步或意图已形成且无更高优先级事件压制）
    for npc_id in world.all_npc_ids():
        var npc := world.get_npc_state(npc_id)
        if not npc.intent.is_empty():
            frames.append(ScriptFrameFormatter.from_breakdown(spec, npc_id, npc.intent))
            world.mark_breakdown(npc_id, spec.index)

    # 阶段5：处理玩家行动（注入队列，不代表一定执行，见 §5）
    if player_action != null:
        var resolution := action_resolver.inject(world, player_action, spec)
        frames.append(ScriptFrameFormatter.from_player_action(spec, resolution))

    # 队列结算：每个 NPC 的 pending_action_queue 在本步末尾按优先级取最高项执行
    for npc_id in world.all_npc_ids():
        var npc := world.get_npc_state(npc_id)
        var executed := action_resolver.resolve_queue(npc, world)
        if executed != null:
            frames.append(ScriptFrameFormatter.from_behavior(spec, npc_id, executed))

    world.advance_step()
    return frames
```

**关键不变量**：`step()` 内部不允许出现 `await`、HTTP 调用或 `randi()`。它是一个同步、纯函数式（相对于传入的 `world` 而言）的状态转移。这使得：
1. gdUnit4 可以直接 `assert_that(engine.step(spec, action)).is_equal(expected_frames)`。
2. `LoopSnapshotStore` 可以在每步后 `world.snapshot()` 存档，用于复盘时间线的精确重放，不用重新跑一遍引擎。

### 4.2 感知过滤层 `PerceptionFilter`

```gdscript
func can_perceive(npc: NPCState, event: EventRecord, world) -> bool:
    match event.visibility:
        Visibility.Level.PUBLIC:
            return true
        Visibility.Level.SECRET:
            return npc.npc_id in event.actors  # 只有当事人自己
        Visibility.Level.PRIVATE:
            if npc.npc_id in event.actors or npc.npc_id in event.witnesses:
                return true
            # 通过信任链得知：任一目击者对该 npc 的信任值需 > 40
            for witness_id in event.witnesses:
                if world.get_trust(witness_id, npc.npc_id) > Visibility.PRIVATE_TRUST_THRESHOLD:
                    return true
            return false
```

> 注意信任方向：GDD 原文是"从信任值高于 40 的他人处得知"，指的是**转述者对听者的信任**（转述者愿意告诉这个人），而不是听者对转述者的信任。这是容易实现反的一处细节，建议在 gdUnit4 里专门写一条测试锁定这个方向。

### 4.3 解读层 `InterpretationResolver`（确认偏误，GDD §6.3）

```gdscript
func resolve(npc: NPCState, npc_def: NPCDefinition, event: EventRecord) -> Interpretation:
    var best: Interpretation = null
    var best_score := -INF
    for candidate in event.candidate_interpretations:
        var score := candidate.base_confidence
        var matching_belief := _find_belief_supporting(npc, candidate)
        if matching_belief:
            score += 0.4 * matching_belief.confidence
        var conflicting_belief := _find_belief_conflicting(npc, candidate)
        if conflicting_belief:
            score -= 0.3 * conflicting_belief.confidence
        if npc.stress > 60.0 and _is_negative(candidate):
            # 压力越高，负面解读权重越大；用线性插值而非硬编码固定加成，
            # 便于关卡设计师在验证器阶段做数值调优
            score += (npc.stress - 60.0) / 40.0 * 0.3
        if score > best_score:
            best_score = score
            best = candidate
    return best
```

### 4.4 信念更新层 `BeliefUpdater`（贝叶斯式 + 抵抗因子，GDD §6.4）

```gdscript
var last_stress_delta: float = 0.0

func apply(npc: NPCState, npc_def: NPCDefinition, interp: Interpretation) -> Belief:
    var existing := _find_belief(npc, interp.resulting_fact_id)
    last_stress_delta = 0.0

    if existing == null:
        var belief := Belief.new()
        belief.fact_id = interp.resulting_fact_id
        belief.direction = interp.resulting_direction
        belief.confidence = interp.base_confidence
        belief.source = interp.interpretation_id
        npc.beliefs.append(belief)
        return belief

    existing.age_in_steps += 1
    if existing.direction == interp.resulting_direction:
        # 强化
        existing.confidence = min(1.0, existing.confidence + 0.1 * interp.base_confidence)
        existing.evidence_count += 1
    else:
        # 挑战：置信度下降幅度 = 来源可信度 vs 抵抗力对比
        var resistance := existing.resistance(npc, npc_def)
        var drop := interp.base_confidence * (1.0 - resistance)
        existing.confidence = max(0.0, existing.confidence - drop)
        if existing.confidence < 0.2:
            existing.direction = interp.resulting_direction
            existing.confidence = interp.base_confidence
            existing.evidence_count = 1
            existing.age_in_steps = 0
        last_stress_delta += 10.0   # 认知失调，无论信念被推翻与否都会产生
    return existing
```

### 4.5 归因链传播 `AttributionPropagator`（GDD §6.5）

```gdscript
func propagate(npc: NPCState, npc_def: NPCDefinition, new_belief: Belief, max_depth: int) -> PropagateResult:
    var result := PropagateResult.new()
    _propagate_recursive(npc, npc_def, new_belief, max_depth, result)
    return result

func _propagate_recursive(npc, npc_def, belief, depth_left, result):
    if depth_left <= 0:
        return
    for memory in npc.memory_log:
        if memory.event_id in result.visited_event_ids:
            continue
        var reinterpretation := _try_reinterpret(memory, belief, npc_def)
        if reinterpretation == null:
            continue
        result.visited_event_ids.append(memory.event_id)
        result.stress_delta += reinterpretation.stress_gain
        memory.chosen_interpretation_by[npc.npc_id] = reinterpretation.interpretation
        var derived_belief := belief_updater_ref.apply(npc, npc_def, reinterpretation.interpretation)
        _propagate_recursive(npc, npc_def, derived_belief, depth_left - 1, result)
```

`_try_reinterpret` 的判定同样走 `TraumaType.ATTRIBUTION_BIAS` 的分类标签匹配（"这条旧记忆的 trigger_category 是否与新信念的偏向一致"），不涉及 LLM 语义理解。

### 4.6 崩坏检测 `BreakdownEvaluator`

```gdscript
func check(npc: NPCState, npc_def: NPCDefinition) -> Dictionary:
    if npc.stress < npc_def.breakdown_threshold:
        return {}
    var core_belief := _find_core_trauma_belief(npc, npc_def)
    if core_belief == null or core_belief.confidence < 0.75:
        return {}
    return {
        "type": TraumaType.BREAKDOWN_DIRECTION[npc_def.trauma_type],
        "target": _resolve_breakdown_target(npc, core_belief),
        "formed_at_step": npc.owner_step_index,
    }
```

---

## 5. Action 注入与优先级队列系统（GDD §7）

### 5.1 优先级分层常量

```gdscript
class_name ActionPriority
extends RefCounted

const BREAKDOWN_INTENT := 100.0
const STRONG_EMOTION := 80.0
const SCENE_EVENT := 60.0
const PLAYER_INJECTED_BASE := 40.0     # 会按信任/时机上调，但天花板低于 SCENE_EVENT
const NPC_ROUTINE := 20.0
```

### 5.2 判定四步（GDD §7.4）

```gdscript
class_name ActionQueueResolver
extends RefCounted

func inject(world, request: PlayerActionRequest, spec: TimeStepSpec) -> PlayerActionResolution:
    var res := PlayerActionResolution.new()
    res.step_index = spec.index
    res.action_id = request.action_def.action_id
    res.target_npc_id = request.target_npc_id

    var npc := world.get_npc_state(request.target_npc_id)
    var trust := world.get_trust(request.target_npc_id, "__player__")
    res.trust_at_execution = trust

    # 第一步：注入检查
    var injection_threshold := _injection_threshold_for(request.action_def.tier)
    if trust < injection_threshold:
        res.succeeded = false
        res.failure_reason = "trust_below_injection_threshold"
        return res

    # 计算注入优先级
    var priority := ActionPriority.PLAYER_INJECTED_BASE
    priority += trust * 0.2
    priority += request.action_def.base_priority_weight * 20.0
    if _in_receptive_window(npc, world):
        priority *= 1.3
    if npc.stress > 80.0:
        priority *= 0.7   # 临界区：玩家注入行为优先级额外下降一级

    npc.pending_action_queue.append({
        "source": "player",
        "priority": priority,
        "action_def": request.action_def,
        "request": request,
        "resolution_ref": res,
    })
    return res

# 第二/三/四步：队列竞争 + 执行条件验证 + 结算，在每步末尾统一调用
func resolve_queue(npc: NPCState, world) -> Dictionary:
    var candidates := npc.pending_action_queue.duplicate()
    candidates.append(_build_intent_candidate(npc))       # 崩坏意图/强情绪等自发行为
    candidates.append_array(_build_scene_event_candidates(npc, world))
    candidates.sort_custom(func(a, b): return a["priority"] > b["priority"])
    npc.pending_action_queue.clear()

    if candidates.is_empty():
        return {}
    var winner = candidates[0]

    if winner.get("source", "") == "player":
        var res: PlayerActionResolution = winner["resolution_ref"]
        if not _verify_execution_conditions(npc, winner["action_def"], world):
            res.succeeded = false
            res.failure_reason = "execution_conditions_failed_at_resolve_time"
            _apply_minor_side_effect_intent_sensed(npc, world)
            return {}
        res.effectiveness_score = _compute_effectiveness(npc, winner, world)
        res.succeeded = res.effectiveness_score >= 0.5
        _apply_action_effects(npc, winner, world, res.succeeded)
        return {"type": "player_action_executed", "detail": winner}

    return {"type": "npc_self_action", "detail": winner}
```

### 5.3 有效性公式（GDD §10.1 干预分析 + 附录 A 示例）

```gdscript
func _compute_effectiveness(npc: NPCState, candidate: Dictionary, world) -> float:
    var request: PlayerActionRequest = candidate["request"]
    var trust_factor := world.get_trust(npc.npc_id, "__player__") / 100.0
    var belief := _find_target_belief(npc, request)
    var resistance := belief.resistance(npc, world.get_npc_def(npc.npc_id)) if belief else 0.3
    var belief_factor := 1.0 - resistance
    var timing_factor := _timing_coefficient(npc, request, world)
    var stress_factor := _stress_coefficient(npc)
    return trust_factor * belief_factor * timing_factor * stress_factor
```

四个系数在 `PlayerActionResolution` 中逐一记录（`trust_at_execution` / `target_belief_resistance` / `timing_coefficient` / `stress_coefficient`），这正是 GDD §10.1「干预分析面板」需要展示的全部字段——**引擎产出的结构化数据和复盘 UI 需要的字段是一一对应设计的**，不需要复盘阶段重新计算或用 LLM 总结。

### 5.4 副作用系统（GDD §7.6）

建议用一个独立的 `SideEffectApplier`，输入是 `(npc, action_def, succeeded, world)`，按 `action_def.side_effect_tags` 逐条应用：

```gdscript
const SIDE_EFFECT_HANDLERS := {
    "trust_fluctuation": _apply_trust_fluctuation,
    "stress_disturbance": _apply_cognitive_dissonance_stress,
    "third_party_perception": _register_as_witnessable_event,   # 生成一条新 EventRecord 供其他 NPC perceive
    "behavior_trace_accumulation": _increment_suspicion_towards_player,
    "chain_event_trigger": _emit_derived_event,
}
```

其中 `third_party_perception` 与 `chain_event_trigger` 的实现方式是：**玩家引导的行为本身被包装成一条新的 `EventRecord`，重新丢回 `InferenceEngine.step()` 的事件池**，完全复用 §4 的感知/解读/传播管线，天然满足"后续连锁反应遵循第6章推导引擎"的要求。

---

## 6. 循环与时间步控制器 `LoopController`（autoload）

替代现有 `PauseManager` 在本模式下的角色（不是删除 `PauseManager`，是新增一个专用状态机，两者可以并存，沙盒模式仍用 `PauseManager`）：

```gdscript
extends Node
# autoload: LoopController

enum State { AWAITING_PLAYER_ACTION, RESOLVING_STEP, PRESENTING_NARRATIVE, REVIEW, LOOP_TRANSITION }

signal state_changed(new_state: State)
signal step_resolved(frames: Array)
signal loop_ended(record: LoopRecord)

var engine: InferenceEngine
var current_arc: StoryArcDefinition
var current_loop_index: int = 0
var snapshot_store: LoopSnapshotStore
var state: State = State.AWAITING_PLAYER_ACTION

func start_arc(arc: StoryArcDefinition) -> void:
    current_arc = arc
    engine = InferenceEngine.new()
    engine.world.load_from_arc(arc, StoryProgressSave.get_loop_variance(arc.arc_id, current_loop_index))
    snapshot_store = LoopSnapshotStore.new()
    _set_state(State.AWAITING_PLAYER_ACTION)

func submit_player_action(request: PlayerActionRequest) -> void:
    if state != State.AWAITING_PLAYER_ACTION:
        return
    _set_state(State.RESOLVING_STEP)
    var spec := current_arc.time_steps[engine.world.current_step_index]
    var frames := engine.step(spec, request)
    snapshot_store.record(engine.world.snapshot(), request, frames)
    _set_state(State.PRESENTING_NARRATIVE)
    step_resolved.emit(frames)   # NarrativeBridge 监听此信号，逐帧转成文本播出

func on_narrative_presentation_finished() -> void:
    if engine.world.has_breakdown() or engine.world.current_step_index >= current_arc.total_steps:
        var record := _build_loop_record()
        loop_ended.emit(record)
        _set_state(State.REVIEW)
    else:
        _set_state(State.AWAITING_PLAYER_ACTION)

func start_next_loop() -> void:
    current_loop_index += 1
    start_arc(current_arc)   # 携带 StoryProgressSave 中的跨循环知识，世界状态重置
```

**要点**：玩家在每个时间步只能 `submit_player_action` 一次（GDD §7.8 的硬约束），因此“观察”本身不是一次 Action，而是 UI 层允许玩家在 `AWAITING_PLAYER_ACTION` 状态下自由移动镜头/查看 NPC 状态，直到主动提交 Action 或选择"本步不干预"（等价于提交一个 no-op request）才会推进状态机。

---

## 7. LLM 集成层改造（复用 APIManager / APIConfig）

### 7.1 职责边界（重申 GDD §9.1，代码层面强制）

新增 `NarrativeBridge.gd`（autoload），是**唯一**允许调用 `APIManager` 的地方（在 `script/loop/` 范围内）：

```gdscript
extends Node
# autoload: NarrativeBridge

func request_narrative_text(frame: ScriptFrame) -> void:
    var prompt := ScriptFrameFormatter.build_llm_prompt(frame)
    var http := await APIManager.generate_dialog(prompt, "narrator")
    http.request_completed.connect(func(result, code, headers, body):
        var text := _parse_and_sanitize(body, frame)
        narrative_text_ready.emit(frame, text)
    )

func request_npc_dialogue(npc_id: String, context: DialogueContext) -> void:
    var prompt := DialogueConstraintBuilder.build(npc_id, context)
    # 复用现有 APIManager.generate_dialog，character_name 传入以复用现有的
    # 每角色独立 AI 设置（SettingsManager.get_character_ai_settings）
    var http := await APIManager.generate_dialog(prompt, npc_id)
    ...
```

`APIManager.gd` / `APIConfig.gd` **无需改动**，其"按 character_name 取独立 API 设置"的能力（原本是为了让不同 NPC 用不同模型对话）恰好可以复用为"叙事者用一个模型、每个 NPC 对话用另一个模型"的配置粒度。

### 7.2 初始条件生成 Pipeline（GDD §8.1 + §8.2）

```gdscript
class_name StoryArcGenerator
extends RefCounted

func generate(params: Dictionary) -> StoryArcDefinition:
    var prompt := _build_generation_prompt(params)   # 场景设定/NPC数量/创伤分配方式/期望崩坏模式
    var raw_json := await _call_llm_for_json(prompt)
    return StoryArcJsonLoader.parse(raw_json)          # 复用 BTJsonLoader 的解析套路
```

```gdscript
class_name StoryArcValidator
extends RefCounted

func validate(arc: StoryArcDefinition) -> ValidationReport:
    var report := ValidationReport.new()
    # 1. 崩坏路径存在：不注入任何玩家行动，跑一遍确定性引擎
    var dry_run := InferenceEngine.new()
    dry_run.world.load_from_arc(arc, {})
    var breakdown_found := false
    for step_spec in arc.time_steps:
        dry_run.step(step_spec, null)
        if dry_run.world.has_breakdown():
            breakdown_found = true
            break
    report.breakdown_path_exists = breakdown_found

    # 2. 救济路径存在 + 3. 难度校验：对干预步骤数做穷举/启发式搜索（Phase 3 再实现，
    #    Phase 1 可先用人工标注的"标准解法序列"重放验证，见 §14 路线图）
    ...

    # 4. 信息断层可发现性：检查每条 information_gap 是否存在对应的 witnessable EventRecord
    report.gaps_discoverable = _check_gap_discoverability(arc)
    return report
```

这与 `StoryArcJsonLoader` 复用 `BTJsonLoader.gd` 的解析模式（ClassDB 优先 → 注册表 → 显式路径的三层查找）思路一致：**LLM 只输出结构化 JSON，Godot 侧负责把 JSON 安全地转成强类型 Resource，任何字段缺失/类型不符直接 `push_error` 而不是静默接受**。

### 7.3 对话生成约束（GDD §9.3）

```gdscript
class_name DialogueConstraintBuilder
extends RefCounted

static func build(npc_id: String, ctx: DialogueContext) -> String:
    var npc := ctx.world.get_npc_state(npc_id)
    var npc_def := ctx.world.get_npc_def(npc_id)
    var prompt := "你是 %s。" % npc_def.display_name
    prompt += "\n当前信念：%s" % _describe_beliefs_without_revealing_numbers(npc)
    prompt += "\n当前压力状态：%s" % _describe_stress_qualitative(npc.stress)
    prompt += "\n对话对象：%s，场景：%s" % [ctx.partner_id, ctx.location]
    prompt += "\n【硬性约束】禁止直接说出你的内心判断或猜测的原文，只能通过间接试探、"
    prompt += "反常的措辞精确度、回避话题等方式体现；不要提及任何数值。"
    return prompt
```

“不能直接表述内心判断”是 prompt 层面的软约束，无法 100% 保证。建议补一个轻量后处理：`DialogueSanitizer` 用关键词黑名单（如"置信度""压力值""creo trust"等术语 + 明显的第三人称心理学措辞）做兜底过滤，命中则重新请求或替换为预置的安全台词模板。

---

## 8. 观察者（玩家）表现层

### 8.1 地点节点：直接复用 `RoomManager` / `RoomArea` / `RoomData`

无需新写。`RoomManager.rooms: Dictionary<String, RoomData>` 本身就是 GDD §12.4 的"地点节点"模型。差异点：现有 `RoomManager.get_current_room` 是给可控角色用的，Loop Collapse 里观察者没有物理刚体，需要新增一个轻量的 `ObserverController.gd`：

```gdscript
extends Node2D
class_name ObserverController

var current_room_key: String = ""

func move_to_location(room_key: String) -> void:
    if not RoomManagerRef.rooms.has(room_key):
        return
    current_room_key = room_key
    global_position = RoomManagerRef.rooms[room_key].position
    observer_moved.emit(room_key)

func can_perceive_event(event: EventRecord) -> bool:
    if event.visibility == Visibility.Level.PUBLIC:
        return true
    return event.location == current_room_key
```

### 8.2 视野：复用 `FogOfWarManager` 的可见性多边形计算

`FogOfWarManager` 现在的用法是"以选中角色为原点算可见性多边形，决定其他节点 `visible` 与否"。Loop Collapse 里可以把 `active_character` 替换为 `ObserverController`，同一套射线可见性多边形算法直接决定：
- 观察者当前能看到地图上哪些区域（表现层，纯视觉）
- **Action 解锁系统**判定"玩家是否完整目击了某段对话/事件"（§13）时，可以复用 `is_node_visible_to_player(npc_node)` 来判断玩家是否真的在场，而不是"人在场景里但隔着墙"。

### 8.3 主界面布局（GDD §12.1）

新场景 `scene/ui/LoopMainUI.tscn`，三区域直接对应：

```
LoopMainUI (Control)
├── NarrativeArea (70%)       # RichTextLabel 滚动文字流，接收 NarrativeBridge.narrative_text_ready
├── NPCStatusBar (20%)        # HBoxContainer，每个 NPC 一个 NPCStatusCard（表情/边框颜色，不显示数字）
└── ActionSelectionArea (10%) # ItemList/VBox，按 ActionDefinition.Tier 分组渲染，
                               # 复用 GDD §15.6 的"基础层置顶，已解锁未满足条件的灰显+悬浮提示条件"规则
```

`NPCStatusCard` 的状态映射表（GDD §12.2）建议做成纯配置，不写死在 UI 脚本里：

```gdscript
const STRESS_VISUAL_TABLE := [
    {"max": 30, "expression": "calm", "border": Color.TRANSPARENT},
    {"max": 60, "expression": "slight_frown", "border": Color.TRANSPARENT},
    {"max": 80, "expression": "tense", "border": Color(1, 0.6, 0, 0.6)},
    {"max": 90, "expression": "erratic", "border": Color(1, 0.3, 0, 0.8)},
    {"max": 101, "expression": "critical", "border": Color(1, 0, 0, 1.0)},
]
```

按照 `.devin/skills` 中 `script/ui/AGENTS.md` 的规范，`LoopMainUI` 及其子节点命名需保证语义化唯一（如 `SubmitActionButton`、`SkipStepButton`），并在 `res://test/` 下补齐 gdUnit4 场景测试。

---

## 9. 存档与跨循环持久化

现有 `GameSaveManager` 面向"单一连续世界快照"，Loop Collapse 需要拆成两套完全独立的持久化，**不复用其 `collect_game_data`/`apply_game_data` 语义**，但复用其"JSON 文件 I/O + `user://saves/` 目录"的基础设施写法。

### 9.1 `LoopSnapshotStore`（本轮循环内，可丢弃/仅用于当前复盘）

```gdscript
class_name LoopSnapshotStore
extends RefCounted

var step_snapshots: Array[Dictionary] = []   # 每步: {world_state_json, frames_json, player_action_json}

func record(world_state: Dictionary, request: PlayerActionRequest, frames: Array) -> void:
    step_snapshots.append({
        "world_state": world_state,
        "player_action": request.to_dict() if request else null,
        "frames": frames.map(func(f): return f.to_dict()),
    })

func replay_to_step(target_step: int) -> Dictionary:
    return step_snapshots[target_step]["world_state"]
```

由于引擎无随机数，`LoopSnapshotStore` 甚至可以只存"每步的玩家 Action 序列 + 初始条件"，需要看历史状态时**重放引擎**而不存完整快照，节省存储；但存完整快照能让复盘 UI 的时间线拖动做到 O(1) 跳转，权衡后建议**两者都存**：Action 序列做校验用（防止快照被手改破坏确定性），快照做 UI 渲染用。

### 9.2 `StoryProgressSave`（跨循环持久，游戏真正的"存档"）

```gdscript
class_name StoryProgressSave
extends RefCounted

const SAVE_PATH := "user://saves/story_progress.json"

var discovered_facts: Array[String] = []
var discovered_gaps: Array[String] = []
var unlocked_action_ids: Array[String] = []
var completed_arc_ids: Array[String] = []
var per_arc_loop_history: Dictionary = {}   # { arc_id: Array[LoopRecord 摘要] }

func save() -> void:
    var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    file.store_string(JSON.stringify(to_dict()))

static func load() -> StoryProgressSave:
    ...
```

信任值/压力值/本轮信念**不出现**在 `StoryProgressSave` 里（GDD §7.7："信任值在每轮循环重置"），只有"哪些事实被发现""哪些 Action 被解锁"这类元知识才跨循环持久，这是设计上的硬性区分，也是实现时最容易踩坑的一点（不要偷懒把整个 `NPCState` 存进去）。

### 9.3 与现有 `GameSaveManager` 的关系

建议：`GameSaveManager` 保留给沙盒模式（Microverse）使用不变；Loop Collapse 新增独立的 `LoopSaveManager.gd` autoload，二者不共享存档目录（`user://saves/sandbox/` vs `user://saves/loop_collapse/`），避免存档 schema 混淆。

---

## 10. 复盘系统（GDD §10）

三层界面对应的数据来源全部已经在引擎运行过程中产出（§5.3 的 `PlayerActionResolution`、§4 的 `ScriptFrame`、`StoryArcDefinition.information_gaps`），复盘 UI 本质上是**纯展示层**，不需要额外计算：

| GDD 层级 | 数据来源 | 新增场景 |
|---------|---------|---------|
| 第一层：时间线视图 | `LoopRecord.step_snapshots` + 每步 `ScriptFrame.stress_delta` | `ReviewTimelinePanel.tscn` |
| 第二层：信息断层高亮 | `StoryArcDefinition.information_gaps` + `LoopRecord.information_gaps_revealed` | `ReviewGapDetailPanel.tscn` |
| 第三层：干预分析 | `LoopRecord.player_actions`（即 `PlayerActionResolution[]`） | `ReviewActionAnalysisPanel.tscn` |

布局可直接借鉴 `GodUI.tscn` 的"左侧列表 + 右侧详情 Tab"骨架（`GodUI.gd` 中 `character_list.item_selected` → `_update_character_detail()` 的模式），把"角色列表"换成"时间步列表"，"角色详情 Tab"换成"该步的推导细节/断层/干预分析"三个 Tab。

最优路径提示（GDD §10.2）：`StoryArcValidator` 在验证阶段本就需要算出至少一条救济路径（否则验证不通过），把这条路径原样存进 `StoryArcDefinition.recommended_solution_path`，失败 3 次后直接展示，不需要在复盘阶段重新搜索。

---

## 11. Action 解锁系统（GDD §15）

```gdscript
class_name ActionUnlockManager
extends Node   # autoload

signal action_unlocked(action_def: ActionDefinition)

func check_observation_trigger(observer: ObserverController, event: EventRecord, npc_witnessed: String) -> void:
    for action_def in _locked_actions_pending_observation():
        if _observation_satisfies(action_def.unlock_condition, observer, event, npc_witnessed):
            _unlock(action_def)

func check_cross_loop_trigger(progress: StoryProgressSave) -> void:
    for action_def in _locked_actions_pending_cross_loop():
        if _cross_loop_condition_satisfied(action_def.unlock_condition, progress):
            _unlock(action_def)

func _unlock(action_def: ActionDefinition) -> void:
    StoryProgressSave.instance.unlocked_action_ids.append(action_def.action_id)
    action_unlocked.emit(action_def)
    # 交由 NarrativeBridge 生成内嵌式提示文本（GDD §15.4），而不是这里硬编码字符串
```

`unlock_condition` 的 JSON schema 建议与 `ActionDefinition` 一起由 `StoryArcGenerator` 生成（信息层/关系层 Action 的解锁条件本质上是关卡内容，天然应该和故事弧一起由 LLM 生成 + 验证器校验"该条件在故事弧中是否真的可达"）。

---

## 12. 现有文件改造清单

| 文件 | 处理方式 | 说明 |
|------|---------|------|
| `script/ai/APIManager.gd`, `APIConfig.gd` | **保留不改** | 直接被 `NarrativeBridge` 复用 |
| `script/RoomManager.gd`, `RoomData.gd`, `RoomArea.gd` | **保留不改** | 直接作为地点节点系统 |
| `script/FogOfWarManager.gd` | **扩展**：新增对 `ObserverController` 类型原点的支持（当前硬编码依赖 `CharacterManager.current_character`） | 视野计算逻辑不变，只改"原点从哪来" |
| `script/Interactable.gd` | **保留，作为设计参照**，不直接复用于 Action（Action 不是场景里的物理节点） | — |
| `script/CharacterPersonality.gd` | **不复用于 Loop Collapse**，改用 `NPCDefinition` Resource；沙盒模式继续用原文件 | 两套人设数据模型语义不同（一个是"性格话术"，一个是"创伤/阈值/信念") |
| `script/ai/memory/MemoryManager.gd` | **不直接复用**，拆分为 `EventRecord`（客观记忆）+ `Belief`（主观信念）两个新模型 | 原有的"重要性枚举+清理策略"思路可以照搬到 `EventRecord` 的裁剪逻辑上 |
| `script/ai/AIAgent.gd` | **不复用**（决策循环整体不适用） | 沙盒模式继续用 |
| `script/ai/DialogManager.gd`, `DialogService.gd`, `ConversationManager.gd` | **不复用决策部分**；对话的"文本生成 + 呈现（气泡/ChatHistory）"部分可抽出复用 | 是否继续对话由 `ActionQueueResolver`/`BreakdownEvaluator` 决定，不再由 LLM 回答"1或2" |
| `script/GameSaveManager.gd` | **保留给沙盒模式**，Loop Collapse 新建 `LoopSaveManager.gd` | 存档语义不同，不应合并 |
| `script/PauseManager.gd` | **保留**，Loop Collapse 不使用倍速概念，但可复用其"灰化视觉"技巧用于"上一步/下一步"过渡效果 | — |
| `script/ui/GodUI.gd` | **保留作为沙盒调试工具**；其布局模式作为 `ReviewUI` 的设计参照（不直接继承代码） | — |
| `script/ai/bt/BTJsonLoader.gd` | **模式复用**，新写 `StoryArcJsonLoader.gd` 照抄其"三层类型解析 + 安全释放"结构 | — |
| `addons/limboai/` | **可选复用于表现层**（NPC 走动动画/寻路），**禁止用于决策** | — |
| `addons/gdUnit4/` | **复用**，是推导引擎正确性的核心保障 | 见 §13 |

---

## 13. 测试策略（gdUnit4）

推导引擎的确定性是可测试性最强的部分，建议在 Phase 1 一开始就建立测试基线：

```
test/loop/
├── engine/
│   ├── PerceptionFilterTest.gd      # 公开/私密/秘密三种可见性 + 信任阈值边界值
│   ├── InterpretationResolverTest.gd # 确认偏误加权 + 高压权重提升
│   ├── BeliefUpdaterTest.gd          # 强化/挑战/推翻三种路径 + 抵抗力上限0.95
│   ├── AttributionPropagatorTest.gd  # 传播深度上限=3 的递归终止
│   ├── ActionQueueResolverTest.gd    # 优先级竞争 + 注入门槛拒绝 + 有效性公式
│   └── InferenceEngineDeterminismTest.gd  # 同输入两次 step() 结果必须逐字段相等
└── generation/
    └── StoryArcValidatorTest.gd      # 用手写的固定 arc fixture 验证"崩坏路径存在"判定
```

`InferenceEngineDeterminismTest` 建议直接对照 GDD 附录 A 的《遗嘱》示例数值（stress 35→58→73→76→85 等具体数字）写成断言，这是 GDD 里唯一给出了完整数值轨迹的例子，天然适合当作黄金测试用例（golden test）。

---

## 14. 开发路线图对照与建议顺序

严格对齐 GDD §14，但补充与本文档模块的映射，便于排期拆任务：

### Phase 1：推导引擎原型验证
- 落地 §3 全部数据模型 + §4 `InferenceEngine`（不含 LLM、不含 Godot 场景）
- 手写 1 个固定故事弧 fixture（3 NPC / 5 步），对应 `test/loop/fixtures/will_arc.gd`
- CLI 输出：临时用 `print()` 把 `ScriptFrame` 转成人类可读文本即可，不需要真正的 LLM 包装
- 验收标准：`InferenceEngineDeterminismTest` 通过 + 手工验证崩坏/救济路径与 GDD 附录 A 数值吻合

### Phase 2：LLM 集成
- 落地 §7（`NarrativeBridge`、`StoryArcGenerator`、`DialogueConstraintBuilder`），复用 `APIManager`
- 落地 §7.2 `StoryArcValidator`（先只做"崩坏路径存在性"这一条，救济路径搜索可以先用人工标注）
- 验收标准：3-5 个不同 LLM 生成的故事弧都能通过验证器，且叙事文本不泄露数值/内部判定

### Phase 3：复盘系统
- 落地 §10（三层复盘 UI）+ §9.1 `LoopSnapshotStore` 结构化记录
- 验收标准：任意一次失败循环，复盘面板能展示出与 §5.3 完全一致的有效性拆解数字

### Phase 4：完整游戏循环
- 落地 §8（地点节点+观察者视野，复用 `RoomManager`/`FogOfWarManager`）、§6 `LoopController` 状态机、§11 `ActionUnlockManager`
- 落地 §9.2 跨循环持久化
- 验收标准：3 个完整故事弧可从头玩到复盘到下一循环，全流程无需人工干预状态

**建议**：Phase 1 与现有 Godot 场景完全解耦，可以先用纯 GDScript 单元测试 + `SceneTree` 之外的 `RefCounted` 类跑通，不占用美术/关卡资源，是投入产出比最高的起点，也最贴合"复用现有工程"的要求（复用的是 `APIManager`/`RoomManager`/`FogOfWarManager` 这类基础设施，而不是复用沙盒模式的决策逻辑）。

---

## 15. 风险与开放问题

1. **确定性边界**：`Visibility.Level.PRIVATE` 的信息传递依赖遍历顺序（`for witness_id in event.witnesses`）,若同一事件有多个目击者且信任值均超阈值，遍历顺序不应影响最终结果（本例中只是"是否可感知"的布尔判定，顺序无关；但如果后续版本改成"取信任值最高的转述者作为来源"，就必须固定排序规则，否则破坏确定性）。
2. **归因链传播的性能**：`memory_log` 随循环推进无限增长，`propagate` 每次新信念都要遍历全部历史记忆，长故事弧（10 步 × 5 NPC）需要评估是否要做记忆索引（按 `trigger_category` 建索引）而非线性扫描。
3. **LLM 输出的结构化可靠性**：§7.2 的 JSON 生成依赖 LLM 严格遵守 schema，需要复用/扩展 `APIConfig.parse_response` 之外再加一层 schema 校验（可参考 `BTJsonLoader` 的错误处理风格：任何字段缺失直接 `push_error` 并中止，而不是"尽量补默认值"，因为初始条件的正确性直接决定验证器判断是否可信）。
4. **对话生成"禁止泄露内心判断"的软约束**：纯 prompt 约束无法保证 100% 合规，§7.3 提出的关键词黑名单是兜底方案，长期看可能需要引入结构化输出（要求 LLM 分别返回"台词"和"是否触碰红线"的自评分，再做二次过滤）。
5. **Action 解锁的"完整理解"判定**（GDD §15.3 观察触发）："信息需要达到一定的完整度"目前用语义模糊，建议在 §5.8 的 `unlock_condition` schema 中把它拆成可判定的子条件（如"玩家在场 AND 该事件的因果 event 链中所有前置 event 均已被感知"），避免又退化成需要 LLM 判断"玩家是否理解了"这种不可确定性的东西。

---

*本文档为架构设计阶段产出，随实现推进需持续更新。核心算法伪代码已尽量贴合 GDD 给出的具体公式/数值，但最终数值需在 Phase 1 原型阶段用 gdUnit4 回归验证并按需调整。*

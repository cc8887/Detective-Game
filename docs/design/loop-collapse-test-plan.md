# 《循环崩坏》测试计划：功能点 ↔ 测试用例映射

**对照文档**：`loop-collapse-architecture.md`（章节号与本文一一对应）
**配套文档**：`loop-collapse-phase1-plan.md`（M1.5/M1.6《遗嘱》黄金测试已在此定义，本文档不重复展开，只做交叉引用）
**测试框架**：gdUnit4（约定参见 `.windsurf/skills/gdunit4-testing/SKILL.md`）
**运行方式**：`./runtests.sh res://test/loop/`（沙盒模式测试不受影响，仍用 `./runtests.sh res://test/`）

---

## 0. 文档体例

- 每个功能点给一个 **测试 ID 前缀**（如 `TC-BELIEF-xx`），后续实现阶段可以直接拿 ID 当 commit message / PR 描述里的 checklist。
- 每条测试用例采用 **Given / When / Then** 简写，直接可以照抄成 gdUnit4 的 `func test_xxx()`。
- 「阶段」列对应架构文档 §14 的 Phase 1~4，标注这条测试**最早**可以在哪个阶段落地（不代表必须卡到那个阶段才写，很多是纯数据结构测试，Phase 1 就可以全部写完）。
- 「测试类型」：`单元`（不依赖场景树/LLM）、`集成`（多个类协作）、`场景`（gdUnit4 `scene_runner`）、`Mock依赖`（需要 mock/spy 掉 LLM 或文件 IO）、`静态扫描`（不是运行期断言，是对源码文本做规则检查）。
- 对所有**依赖 LLM 的模块**（§7 全部、§10 少量），测试策略统一为：**永不在测试里发真实网络请求**。做法是给 `NarrativeBridge`/`StoryArcGenerator` 的 LLM 调用点做依赖注入（构造函数/属性传入一个 `LLMCaller` 接口的假实现，或者直接 `mock(APIManager)` 拦截 `generate_dialog`），断言的重点永远是"**prompt 里有没有放对字段 / 收到 LLM 返回后有没有正确解析与净化**"，而不是断言 LLM 会说什么。

---

## 1. 数据模型层（对照架构文档 §3）

### 1.1 `TraumaType`（§3.2）

| ID | Given/When/Then | 阶段 |
|---|---|---|
| TC-TRAUMA-01 | Given 六种 `TraumaType.Type` 枚举值逐一遍历 / When 查 `ATTRIBUTION_BIAS[type]` / Then 每个都返回非空 `{trigger_category, biased_belief}`，无 `KeyError` | P1 |
| TC-TRAUMA-02 | Given 同上遍历 / When 查 `BREAKDOWN_DIRECTION[type]` / Then 每个都有对应字符串，且六个值互不相同（防止复制粘贴漏改） | P1 |

测试文件：`test/loop/model/TraumaTypeTest.gd`

### 1.2 `Belief.resistance()`（§3.4）—— 核心公式，单独重点覆盖

`resistance = 0.3 + stress*0.003 + age_in_steps*0.01 + evidence_count*0.05 + (0.5 if core) + npc_def.belief_resistance_bonus`，上限 0.95。

| ID | Given | When | Then | 阶段 |
|---|---|---|---|---|
| TC-BELIEF-01 | stress=0, age=0, evidence=1, core=false, bonus=0 | 调 `resistance()` | 结果 = 0.3 + 0.05 = 0.35 | P1 |
| TC-BELIEF-02 | stress=100 | 调 `resistance()` | 结果比 TC-01 多 0.3（100*0.003） | P1 |
| TC-BELIEF-03 | age_in_steps=50 | 调 `resistance()` | 结果比基线多 0.5（50*0.01），此时应**触顶到 0.95** 而不是超过 | P1 |
| TC-BELIEF-04 | evidence_count=20 | 调 `resistance()` | 触顶 0.95 | P1 |
| TC-BELIEF-05 | is_core_trauma_belief=true，其余取 TC-01 基线 | 调 `resistance()` | 结果 = 0.35 + 0.5 = 0.85（不触顶时验证 +0.5 是精确叠加，不是覆盖） | P1 |
| TC-BELIEF-06 | 极端组合：stress=100, age=100, evidence=100, core=true | 调 `resistance()` | 结果精确等于 0.95（验证 `min()` 生效，不会算出 >0.95 或负数） | P1 |
| TC-BELIEF-07 | `npc_def.belief_resistance_bonus` 单独设为 0.2，其余取基线 | 调 `resistance()` | 结果 = 0.35 + 0.2 = 0.55（验证性格加成独立叠加） | P1 |

测试文件：`test/loop/model/BeliefTest.gd`

### 1.3 `EventRecord` / `Interpretation`（§3.6 / §3.7）

| ID | Given/When/Then | 阶段 |
|---|---|---|
| TC-EVENT-01 | Given 新建 `EventRecord` / When 追加 `witnesses` / Then 数组按追加顺序保存，无去重（去重是 `PerceptionFilter`/`Propagator` 的职责，不是数据类职责） | P1 |
| TC-EVENT-02 | Given 一个事件 / When 两个不同 `npc_id` 分别写入 `chosen_interpretation_by` / Then 两条记录互不覆盖 | P1 |
| TC-EVENT-03 | Given `Interpretation.trigger_category` 取值 / When 与 `TraumaType.ATTRIBUTION_BIAS` 的 `trigger_category` 字段比较 / Then 每个 fixture 里用到的分类标签都能在某个创伤类型下找到匹配（防止关卡数据里手误拼错分类标签，写成"孤儿标签"） | P1/P2 |

测试文件：`test/loop/model/EventRecordTest.gd`

### 1.4 `Visibility`（§3.7）

| ID | Given/When/Then | 阶段 |
|---|---|---|
| TC-VIS-01 | Given `Visibility.Level` 三个枚举值 / When 转成字符串用于日志 / Then 不抛异常（纯健壮性检查，逻辑测试见 §2.1 `PerceptionFilter`） | P1 |

### 1.5 `NPCState.clone_deep()`（§3.3）—— 快照系统正确性前提，务必重点覆盖

| ID | Given | When | Then | 阶段 |
|---|---|---|---|---|
| TC-NPCSTATE-01 | 原始 `NPCState` 含 1 条 `Belief`、1 条 `trust_towards` 记录、1 条 `memory_log` | 调 `clone_deep()` 得到副本 | 副本与原始对象**不是同一引用**（`!=` id 比较通过 `is_same()`） | P1 |
| TC-NPCSTATE-02 | 同上 | 修改副本的 `beliefs[0].confidence` | 原始对象的 `beliefs[0].confidence` **不变**（验证 `beliefs` 数组元素也被深拷贝，不是只拷贝了数组容器） | P1 |
| TC-NPCSTATE-03 | 同上 | 修改副本的 `trust_towards["X"]` | 原始对象的 `trust_towards["X"]` 不变 | P1 |
| TC-NPCSTATE-04 | 同上 | 修改副本的 `memory_log[0].witnesses` | 原始对象的 `memory_log[0].witnesses` 不变（`EventRecord` 也要深拷贝，这是最容易漏的一层，因为 `memory_log` 里存的是引用而不是值） | P1 |
| TC-NPCSTATE-05 | 原始对象 `intent = {}` | 调 `clone_deep()` 后修改副本 `intent` | 原始对象的 `intent` 仍为空字典 | P1 |

测试文件：`test/loop/model/NPCStateTest.gd`（这是 Phase 1 里**优先级最高**的数据类测试，`LoopSnapshotStore`/`WorldStateContext.snapshot()` 全部依赖它的正确性，一旦这里有浅拷贝漏洞，会导致"重放历史快照"看到的其实是"当前最新状态"这种隐蔽 bug）

### 1.6 `NPCDefinition`（§3.1）

| ID | Given/When/Then | 阶段 |
|---|---|---|
| TC-NPCDEF-01 | Given 只设置必填字段（id/display_name/trauma_type） / Then 未设置字段命中默认值：`breakdown_threshold=85.0`, `stress_gain_multiplier=1.0`, `initial_stress=20.0` | P1 |
| TC-NPCDEF-02 | Given 一个 `NPCDefinition.initial_trust = {"B": 50.0}` / When 通过 `WorldStateContext.load_from_arc()` 加载后修改 `NPCState.trust_towards["B"]` / Then `NPCDefinition.initial_trust["B"]` **不变**（防止"重置循环"复用同一个 `NPCDefinition` 对象时被污染，见 §2 TC-WORLD-01） | P1 |

测试文件：`test/loop/model/NPCDefinitionTest.gd`

### 1.7 `ActionDefinition`（§3.8）

| ID | Given/When/Then | 阶段 |
|---|---|---|
| TC-ACTIONDEF-01 | Given 四个 `Tier` 枚举值 / Then 都能正确赋值且互不相等 | P1 |
| TC-ACTIONDEF-02 | Given `execution_conditions = [{"type":"stress_below","value":60}]` / Then 字段结构可被 `ActionQueueResolver._verify_execution_conditions` 读取（先写一个"能读出这个 dict"的最小单测，真正的条件判定逻辑测试见 §4） | P1 |
| TC-ACTIONDEF-03 | Given `is_time_limited=true` 但 `expires_condition={}` | Then 允许（架构文档未强制两者绑定校验，此测试用于**记录当前设计决定**：是否要在 `_ready`/校验器阶段强制两者同时出现，留给 Phase 2 `StoryArcValidator` 决定，Phase1 先只测试字段独立可读） | P1 |

测试文件：`test/loop/model/ActionDefinitionTest.gd`

### 1.8 序列化往返（`ScriptFrame` / `PlayerActionResolution` / `LoopRecord` / `StoryArcDefinition`）

这几个类本身架构文档里没写 `to_dict()`/`from_dict()`，但 §9.1 `LoopSnapshotStore.record()` 的注释写了 `frames.map(func(f): return f.to_dict())`，说明**这是需要补的接口**，测试要覆盖：

| ID | Given/When/Then | 阶段 |
|---|---|---|
| TC-SERIAL-01 | Given 一个填满全部字段的 `ScriptFrame` / When `to_dict()` 再 `from_dict()` / Then 还原后的对象逐字段相等 | P1 |
| TC-SERIAL-02 | 同上，对象换成 `PlayerActionResolution` | P1 |
| TC-SERIAL-03 | 同上，对象换成 `LoopRecord`（含嵌套的 `player_actions` 数组） | P3（`LoopRecord` 到 Phase 3 才会被真正落盘使用，但序列化接口本身 Phase 1 就该定好签名，避免后面改接口影响一堆调用点） |
| TC-SERIAL-04 | Given `StoryArcDefinition`（LLM 生成的产物） / When JSON 序列化再反序列化 / Then 与 `StoryArcJsonLoader.parse()` 直接解析同一份 JSON 得到的对象等价 | P2 |

测试文件：`test/loop/model/SerializationRoundtripTest.gd`

---

## 2. `WorldStateContext`（补充设计类，Phase 1 计划 §M1.2）

| ID | Given/When/Then | 阶段 |
|---|---|---|
| TC-WORLD-01 | Given 一个 `StoryArcDefinition`（2 NPC） / When `load_from_arc()` 两次（模拟"进入循环两次"） / Then 第二次加载后的初始信任值与第一次完全相同（证明第一次循环期间对 `NPCState` 的修改没有污染 `NPCDefinition` 源数据） | P1 |
| TC-WORLD-02 | Given 玩家 id 约定 `"__player__"` / When `get_trust("A", "__player__")` 且 A 未显式设置对玩家的信任 / Then 返回默认值 `0.0`（不抛异常，不返回 null） | P1 |
| TC-WORLD-03 | Given `TimeStepSpec.scheduled_events` 含 2 个 event_id / When 同一个 `spec` 被 `activate_scheduled_events()` 调用两次（误触发场景） / Then 第二次不重复把同一事件加入 `active_events` 返回值（需要设计"事件是否已激活"的标记字段，防止 `LoopController` 出现重试逻辑时事件被算两遍） | P1 |
| TC-WORLD-04 | Given 引擎跑完一步产生崩坏 / When 调 `mark_breakdown("A", 5)` 后调 `has_breakdown()` | Then 返回 `true`，且 `breakdown_log` 含 `{npc_id:"A", step_index:5}` | P1 |
| TC-WORLD-05 | Given 任意 `WorldStateContext` 状态 / When 调 `snapshot()` 后立即修改原始 `npc_states` 中某个 NPC 的 `stress` | Then 快照里的对应值不变（即 `snapshot()` 内部必须调用 §1.5 的 `clone_deep()`，这条测试是 TC-NPCSTATE-01~05 的集成验证版） | P1 |
| TC-WORLD-06 | Given `advance_step()` 连续调用 N 次 / Then `current_step_index` 精确 +N，不跳步不回退 | P1 |

测试文件：`test/loop/engine/WorldStateContextTest.gd`

---

## 3. 推导引擎五个子模块（对照架构文档 §4.2~§4.6）

> 这一节是整个测试计划里**优先级最高、覆盖要求最严**的部分——它是 GDD 反复强调的"可解释性/确定性"承诺的直接落地。每个子模块必须能在**不实例化其他四个子模块**的情况下独立测试。

### 3.1 `PerceptionFilter.can_perceive()`（§4.2）

| ID | Given | When | Then | 阶段 |
|---|---|---|---|---|
| TC-PERCEIVE-01 | `event.visibility = PUBLIC`，NPC 与事件毫无关联 | `can_perceive()` | 返回 `true` | P1 |
| TC-PERCEIVE-02 | `event.visibility = SECRET`，NPC 不在 `event.actors` 里 | `can_perceive()` | 返回 `false` | P1 |
| TC-PERCEIVE-03 | `event.visibility = SECRET`，NPC 就是 `event.actors[0]` | `can_perceive()` | 返回 `true` | P1 |
| TC-PERCEIVE-04 | `event.visibility = PRIVATE`，NPC 是 `event.witnesses` 之一 | `can_perceive()` | 返回 `true`（目击者天然可感知，不需要信任判断） | P1 |
| TC-PERCEIVE-05 | `event.visibility = PRIVATE`，NPC 不是目击者，且所有目击者对该 NPC 的信任都 ≤40 | `can_perceive()` | 返回 `false` | P1 |
| TC-PERCEIVE-06（**方向测试，架构文档 §4.2 特别标注的易错点**） | `event.visibility = PRIVATE`；目击者 A 对听者 C 信任=60；另一 NPC B 对 C 信任=0；B **不是**该事件目击者 | `can_perceive(C, event)` | 返回 `true`（只看"目击者对听者的信任"，B 的信任值应完全不参与判定，因为 B 没目击这件事） | P1 |
| TC-PERCEIVE-07 | `event.visibility = PRIVATE`，目击者对听者信任正好 = 40.0（边界值） | `can_perceive()` | 按架构文档"高于 40"的措辞，40.0 本身应判定为 `false`（严格大于），需要在实现里用 `> 40.0` 而非 `>= 40.0`，本测试锁定这一边界 | P1 |

测试文件：`test/loop/engine/PerceptionFilterTest.gd`

### 3.2 `InterpretationResolver.resolve()`（§4.3）

| ID | Given | When | Then | 阶段 |
|---|---|---|---|---|
| TC-INTERP-01 | 两个候选解读，`base_confidence` 分别 0.6/0.4，NPC 无相关信念，stress=20 | `resolve()` | 返回 base_confidence=0.6 的那个 | P1 |
| TC-INTERP-02 | 两个候选解读 base_confidence 均 0.4；NPC 持有信念恰好支持候选 B（`confidence=0.75`） | `resolve()` | 返回候选 B（0.4 + 0.4*0.75=0.70 > 0.4） | P1 |
| TC-INTERP-03 | 同上场景，NPC 持有的信念改为与候选 B **冲突**（`confidence=0.75`） | `resolve()` | 返回候选 A（B 被扣到 0.4 - 0.3*0.75=0.175 < 0.4） | P1 |
| TC-INTERP-04 | NPC `stress=75`（>60），候选 B 被标记为"负面解读"，两候选 base_confidence 相同 | `resolve()` | 候选 B 获得额外加权 `(75-60)/40*0.3=0.1125`，胜出 | P1 |
| TC-INTERP-05 | NPC `stress=60`（**边界值**，架构文档公式在 `stress>60` 才生效） | `resolve()` | 加权量为 0（严格大于判断，60 本身不加权），需要专门锁定这个边界 | P1 |
| TC-INTERP-06（**平局测试，架构文档未指定但必须确定**） | 两候选算出的最终得分完全相等 | `resolve()` 连续调用 10 次 | 每次都返回同一个候选（数组里排在前面的那个），验证平局裁决规则的确定性 | P1 |

测试文件：`test/loop/engine/InterpretationResolverTest.gd`

### 3.3 `BeliefUpdater.apply()`（§4.4）

| ID | Given | When | Then | 阶段 |
|---|---|---|---|---|
| TC-BUPD-01 | NPC 对某 `fact_id` 无任何已有信念 | `apply(interp)` | 新建一条 `Belief`，`confidence = interp.base_confidence`，`evidence_count=1`，`last_stress_delta == 0` | P1 |
| TC-BUPD-02 | 已有信念 `direction=true, confidence=0.5`；新解读同方向，`base_confidence=0.4` | `apply()` | `confidence = min(1.0, 0.5+0.1*0.4) = 0.54`，`evidence_count` 从原值 +1 | P1 |
| TC-BUPD-03 | 已有信念 `confidence=0.95`；新解读同方向 `base_confidence=1.0` | `apply()` | `confidence` 触顶 `1.0`（验证 `min()` 生效） | P1 |
| TC-BUPD-04 | 已有信念 `direction=true, confidence=0.7`；新解读**反方向**，`base_confidence=0.35`；此时 `resistance()` 算出 0.669（复刻 GDD 附录A T=3 场景数值） | `apply()` | `drop = 0.35*(1-0.669) ≈ 0.116`，`confidence ≈ 0.584`（未跌破 0.2，方向不翻转），`last_stress_delta == 10.0` | P1 |
| TC-BUPD-05 | 已有信念 `confidence=0.18`（已经很低）；新解读反方向，任意 `base_confidence` | `apply()` | 只要 `drop` 让结果 <0.2 → `direction` 翻转，`confidence=interp.base_confidence`，`evidence_count` 重置为 1，`age_in_steps` 重置为 0 | P1 |
| TC-BUPD-06 | 恰好使 `confidence` 算出精确等于 `0.2`（**边界值**） | `apply()` | 按"降至 0.2 以下才推翻"的措辞，`0.2` 本身不翻转（严格小于判断），需要专门锁定 | P1 |

测试文件：`test/loop/engine/BeliefUpdaterTest.gd`

### 3.4 `AttributionPropagator.propagate()`（§4.5）

| ID | Given | When | Then | 阶段 |
|---|---|---|---|---|
| TC-PROP-01 | NPC 的 `memory_log` 中有 1 条记忆能被新信念重新解读为负面 | `propagate(max_depth=3)` | `result.stress_delta > 0`，且该记忆的 `chosen_interpretation_by` 被更新 | P1 |
| TC-PROP-02 | `memory_log` 中有一条"链"：记忆①触发新信念X，X 又能让记忆②被重新解读，记忆②又触发信念Y，Y 又能让记忆③被重新解读……一共链 4 层 | `propagate(max_depth=3)` | 只处理到第 3 层，第 4 层的记忆**不会**被重新解读（`visited_event_ids` 最多 3 个新增） | P1 |
| TC-PROP-03 | 同一条记忆理论上会被两条不同的传播路径都命中一次 | `propagate()` 单次调用内 | 该记忆只被处理一次（`visited_event_ids` 去重生效，不会重复叠加压力） | P1 |
| TC-PROP-04 | `memory_log` 为空 | `propagate()` | `result.stress_delta == 0`，不抛异常，`_propagate_recursive` 第一层直接返回 | P1 |
| TC-PROP-05 | 复刻 GDD 附录A T=2：两条历史记忆分别产生 `+8`/`+7` 压力 | `propagate()` | `result.stress_delta == 15`（精确匹配 GDD 给出的数值，58→73 这一跳完全由这条测试锁定） | P1 |

测试文件：`test/loop/engine/AttributionPropagatorTest.gd`

### 3.5 `BreakdownEvaluator.check()`（§4.6）

| ID | Given | When | Then | 阶段 |
|---|---|---|---|---|
| TC-BREAK-01 | `stress = threshold - 1` | `check()` | 返回空字典 | P1 |
| TC-BREAK-02 | `stress = threshold`（**边界，GDD 附录A 原文"恰好触及"用的是 ≥**） | `check()` | 返回非空意图字典（`>=` 判断） | P1 |
| TC-BREAK-03 | `stress >= threshold` 但无任何核心创伤信念 | `check()` | 返回空字典 | P1 |
| TC-BREAK-04 | `stress >= threshold`，核心创伤信念 `confidence = 0.74`（**边界，刚好不够**） | `check()` | 返回空字典（严格 `>= 0.75` 判断） | P1 |
| TC-BREAK-05 | `stress >= threshold`，核心创伤信念 `confidence = 0.75` | `check()` | 返回非空，`type` 字段与 `TraumaType.BREAKDOWN_DIRECTION[npc_def.trauma_type]` 完全一致 | P1 |

测试文件：`test/loop/engine/BreakdownEvaluatorTest.gd`

### 3.6 `InferenceEngine.step()` 组装（§4.1）

| ID | Given/When/Then | 阶段 |
|---|---|---|
| TC-STEP-01 | Given 一个只含 1 个 `PUBLIC` 事件、2 个 NPC 的最小 fixture / When 调 `step()` 一次 / Then 返回的 `Array[ScriptFrame]` 里每个 NPC 都至少产生 1 条 perception 类型的 frame（验证阶段2循环覆盖到所有 NPC） | P1 |
| TC-STEP-02 | Given 某 NPC 已在上一步形成 `intent` / When 再调一次 `step()` / Then 阶段3不会覆盖已存在的 `intent`（`if npc.intent.is_empty()` 分支生效，已形成的意图不会被"重新评估"改写） | P1 |
| TC-STEP-03 | Given 传入 `player_action = null` / When 调 `step()` / Then 不抛异常，阶段5静默跳过 | P1 |
| TC-STEP-04（**确定性测试，最高优先级**） | Given 同一份 `StoryArcDefinition` fixture + 同一组 5 步的 `PlayerActionRequest` 序列 | 用两个完全独立的 `InferenceEngine` 实例各跑一遍全部 5 步 | 两次运行产出的 `Array[ScriptFrame]`（逐字段）与 `world.snapshot()`（逐字段）完全相等 | P1 |
| TC-STEP-05 | 同 TC-STEP-04 的 fixture，运行 3 遍 | 三次结果两两相等（防止"跑两次刚好撞对"的偶然通过） | P1 |

测试文件：`test/loop/engine/InferenceEngineStepTest.gd` + `test/loop/engine/InferenceEngineDeterminismTest.gd`

### 3.7 确定性硬约束的静态扫描（§4.1 强制约束）

| ID | Given/When/Then | 阶段 |
|---|---|---|
| TC-LINT-01 | Given 遍历 `res://script/loop/engine/*.gd` 全部文件内容 / Then 不出现子串 `HTTPRequest` | P1 |
| TC-LINT-02 | 同上遍历 / Then 不出现 `APIManager` | P1 |
| TC-LINT-03 | 同上遍历 / Then 不出现 `randi(`、`randf(`、`rand_range(`、`randi_range(` | P1 |
| TC-LINT-04 | 同上遍历 / Then 不出现 `await`（引擎层禁止任何异步等待，否则无法在 `LoopController` 里同步调用） | P1 |

测试文件：`test/loop/engine/EngineDeterminismLintTest.gd`（**静态扫描类型**，用 `DirAccess`/`FileAccess` 读文本做字符串匹配，不实例化任何被测类）

### 3.8《遗嘱》黄金测试（架构文档附录A 复刻）

已在 `loop-collapse-phase1-plan.md` §7/§8 定义完整数值断言，此处仅做索引，不重复：

| ID | 对应 Phase1 计划里的位置 | 阶段 |
|---|---|---|
| TC-WILL-BREAKDOWN-01~03 | `WillArcBreakdownTest.gd`（M1.5，无干预崩坏路径，T=2/T=4/T=5 三个检查点） | P1 |
| TC-WILL-RESCUE-01~03 | `WillArcRescueTest.gd`（M1.6，最优路径救济 + 失败干预 effectiveness≈0.069 回归） | P1 |

---

## 4. Action 注入与优先级队列系统（对照架构文档 §5）

### 4.1 `ActionQueueResolver.inject()`（§5.2 第一/二步）

| ID | Given | When | Then | 阶段 |
|---|---|---|---|---|
| TC-INJECT-01 | 目标 NPC 对玩家信任 = 5，`action_def.tier = BASE`（注入门槛较低，假设阈值设定为 0） | `inject()` | 成功进入队列（`res.succeeded` 字段此时还不代表最终结果，只代表"没被拒绝"，需要在实现里明确 `inject()` 返回值语义：是"是否成功注入"还是"占位待定"——**这条测试的附带产出是把这个语义在代码里显式化**） | P1 |
| TC-INJECT-02 | 目标 NPC 对玩家信任 = 5，`action_def.tier = BREAKTHROUGH`（注入门槛高，假设阈值 60） | `inject()` | `res.succeeded=false`，`res.failure_reason="trust_below_injection_threshold"`，且**不会**被加入 `npc.pending_action_queue` | P1 |
| TC-INJECT-03 | 目标 NPC 信任=50，处于"可接受窗口"内 | `inject()` | 计算出的 priority 比同等信任但窗口外的场景高（乘 1.3） | P1 |
| TC-INJECT-04 | 目标 NPC `stress=85`（>80 临界区） | `inject()` | priority 在窗口/信任加权之后再乘 0.7 | P1 |
| TC-INJECT-05 | 连续对同一 NPC 提交两次 `inject()`（模拟同一时间步误触发两次，正常游玩不该发生，但要防御性覆盖） | `inject()` ×2 | 队列里出现两条记录（不做去重，去重是 §6 `LoopController` 的"每步一次 Action"约束负责的，`ActionQueueResolver` 本身不重复承担这个校验，这条测试用来**明确职责边界**，避免两层都做校验或都不做） | P1 |

测试文件：`test/loop/engine/ActionQueueInjectTest.gd`

### 4.2 `ActionQueueResolver.resolve_queue()`（§5.2 第三/四步）—— 优先级竞争

| ID | Given | When | Then | 阶段 |
|---|---|---|---|---|
| TC-RESOLVE-01 | 队列里同时有 1 条崩坏意图候选（priority=100）和 1 条玩家注入候选（priority=52） | `resolve_queue()` | 执行崩坏意图，玩家 Action 被压制，`res.succeeded=false`（需要在 `resolve_queue` 里回填被压制的 `PlayerActionResolution`，架构文档伪代码只在"胜出且是玩家 Action"分支回填，这里要补上"未胜出"分支的回填逻辑并测试它） | P1 |
| TC-RESOLVE-02 | 队列里只有 1 条玩家注入候选，且注入时的 `execution_conditions` 到结算时刻已不满足（如条件是"stress<60"，但结算前 stress 被别的事件推高到 70） | `resolve_queue()` | `res.succeeded=false`，`res.failure_reason="execution_conditions_failed_at_resolve_time"`，且触发"轻微副作用"（`_apply_minor_side_effect_intent_sensed`） | P1 |
| TC-RESOLVE-03 | 队列里只有 1 条玩家注入候选，条件满足，`_compute_effectiveness()` 返回 0.6 | `resolve_queue()` | `res.succeeded=true`，`res.effectiveness_score=0.6` | P1 |
| TC-RESOLVE-04 | 队列里只有 1 条玩家注入候选，`_compute_effectiveness()` 返回 0.49（**边界值**） | `resolve_queue()` | `res.succeeded=false`（严格 `>=0.5` 判断） | P1 |
| TC-RESOLVE-05（**平局裁决，需要补充设计**） | 两条非玩家候选（如 1 条"场景事件" + 1 条"NPC日常自发行为"）priority 恰好相等 | `resolve_queue()` 连续调用多次 | 结果稳定一致（需要在实现里显式定义 tie-break：建议按"候选加入队列的顺序"作为次级排序键，而不是依赖 `sort_custom` 的不稳定排序） | P1 |
| TC-RESOLVE-06 | 队列为空 | `resolve_queue()` | 返回空字典，不抛异常 | P1 |

测试文件：`test/loop/engine/ActionQueueResolveTest.gd`

### 4.3 有效性公式 `_compute_effectiveness()`（§5.3）

| ID | Given/When/Then | 阶段 |
|---|---|---|
| TC-EFFECT-01 | 复刻 GDD 附录A T=3 失败案例：trust=35, resistance=0.669, timing=0.7, stress_coef=0.85 | 计算得 `0.35 * (1-0.669) * 0.7 * 0.85 ≈ 0.069` | P1 |
| TC-EFFECT-02 | 复刻"最优路径"：trust=60（母亲对玩家）、目标信念抵抗力较低（因为是刚形成不久的次级信念，非核心创伤信念）、timing=1.0（窗口内）、stress_coef 接近 1.0 | 计算得分 ≥0.5 | P1 |
| TC-EFFECT-03 | 单独把 `trust_factor` 设为 0，其余因子设为 1 | 结果精确为 0（验证是相乘关系，不是相加，任一因子为 0 则整体失效） | P1 |
| TC-EFFECT-04 | `PlayerActionResolution` 四个中间系数字段（`trust_at_execution`/`target_belief_resistance`/`timing_coefficient`/`stress_coefficient`）| 与传入 `_compute_effectiveness` 的四个原始值逐一核对 | 完全一致（这是给 §10 复盘系统"干净分析面板"的数据契约测试，任何一个字段算错都会导致复盘 UI 显示错误的归因） | P1 |

测试文件：`test/loop/engine/EffectivenessFormulaTest.gd`

### 4.4 副作用系统 `SideEffectApplier`（§5.4）

| ID | Given/When/Then | 阶段 |
|---|---|---|
| TC-SIDEFX-01 | `side_effect_tags=["trust_fluctuation"]`，Action 执行成功且对 NPC 有利 | 目标 NPC 对玩家信任小幅上升 | P1 |
| TC-SIDEFX-02 | 同 tag，但 NPC 判断"被利用" | 信任大幅下降（需要定义"被利用"的判定输入来源，Phase 1 先用最简单规则：`succeeded=true` 但 `action_def` 标记了 `is_manipulative` 之类的辅助字段——**若架构文档未定义该字段，此测试同时驱动补一个字段**） | P2（依赖字段先在 P1 定义，但完整判定逻辑留到 P2 场景丰富后再验收） |
| TC-SIDEFX-03 | `side_effect_tags=["stress_disturbance"]`，打破的信念 `evidence_count=5` | 压力上升幅度与 `evidence_count` 正相关（复刻 §7.6"打破信念的收益 vs 短暂压力上升"的说法，但架构文档没给出具体系数——此测试同时确定一个可测的系数公式草案） | P1 |
| TC-SIDEFX-04 | `side_effect_tags=["third_party_perception"]`，第三个 NPC 与事件发生在同一地点 | 生成一条新的 `EventRecord`，且该记录能被**重新丢回** `InferenceEngine` 的事件池并触发第三方 NPC 的 perceive/interpret 流程（集成测试，验证"连锁反应复用第4章管线"这条设计承诺） | P1 |
| TC-SIDEFX-05 | `side_effect_tags=["behavior_trace_accumulation"]`，对同一 NPC 连续 3 次注入 Action | 该 NPC 后续注入门槛（TC-INJECT-02 里的阈值）逐次上升 | P2 |
| TC-SIDEFX-06 | `side_effect_tags=["chain_event_trigger"]` | 产生的衍生事件带有正确的 `time_step`（当前步）和 `actors`（执行行为的 NPC） | P1 |

测试文件：`test/loop/engine/SideEffectApplierTest.gd`

---

## 5. `LoopController` 状态机（对照架构文档 §6）

| ID | Given/When/Then | 阶段 |
|---|---|---|
| TC-LOOP-01 | Given 初始状态 | `start_arc()` | 状态变为 `AWAITING_PLAYER_ACTION`，`state_changed` 信号发出一次 | P4 |
| TC-LOOP-02 | Given 状态为 `RESOLVING_STEP` | 调 `submit_player_action()` | 请求被忽略（不重复推进状态机），需要显式的"重复提交防御" | P4 |
| TC-LOOP-03 | Given 状态为 `AWAITING_PLAYER_ACTION` | 调 `submit_player_action()` | 状态经过 `RESOLVING_STEP` 最终落在 `PRESENTING_NARRATIVE`，`step_resolved` 信号携带的 frames 与 `engine.step()` 直接返回值一致 | P4 |
| TC-LOOP-04 | Given `engine.world.has_breakdown()==true` | 调 `on_narrative_presentation_finished()` | 状态变为 `REVIEW`，`loop_ended` 信号发出且携带的 `LoopRecord.outcome=="breakdown"` | P4 |
| TC-LOOP-05 | Given 未崩坏且 `current_step_index < total_steps` | 调 `on_narrative_presentation_finished()` | 状态回到 `AWAITING_PLAYER_ACTION`（可以继续下一步） | P4 |
| TC-LOOP-06 | Given 处于 `REVIEW` 状态 | 调 `start_next_loop()` | `current_loop_index+1`；新一轮 `engine.world` 的 NPC 信任值重置为 `NPCDefinition.initial_trust`（GDD §7.7 "信任值每轮重置"的硬约束），但 `StoryProgressSave` 中的跨循环知识不受影响 | P4 |
| TC-LOOP-07 | Given 每个时间步 | 玩家试图在同一步内调用两次 `submit_player_action()` | 第二次被拒绝（GDD §7.8"每时间步只能提交一个 Action"的硬约束，这条与 TC-LOOP-02 一起构成双重保险：一次是"状态不对拒绝"，一次是"同状态内重复提交拒绝"，需要确认这两条测试覆盖的是两个不同的代码分支） | P4 |

测试文件：`test/loop/loop/LoopControllerTest.gd`

---

## 6. LLM 集成层（对照架构文档 §7）—— 全部采用 Mock，不发真实请求

### 6.1 `NarrativeBridge`（§7.1）

| ID | Given/When/Then | 阶段 |
|---|---|---|
| TC-NARR-01 | Given mock 掉 `APIManager.generate_dialog`，拦截其参数 | 调 `request_narrative_text(frame)` | 传给 `APIManager` 的 prompt 字符串包含 `frame.time_label`、`frame.location`、`frame.narrative_constraints` 的全部内容 | P2 |
| TC-NARR-02 | 同上 mock，但让 `generate_dialog` 模拟返回一段"包含具体数值"的文本（如"压力值73"） | 调 `request_narrative_text()` 完整流程 | 最终 `narrative_text_ready` 信号发出的文本经过净化（若净化逻辑存在，验证黑名单命中；若尚未实现净化，本测试会失败并驱动补上——见 §6.4） | P2 |
| TC-NARR-03 | Given HTTP 请求失败（mock 返回 `result != RESULT_SUCCESS`） | 调 `request_narrative_text()` | 不崩溃，走降级路径（例如用 `frame.raw_description` 兜底文案），需要在实现里补一个降级分支并测试 | P2 |

测试文件：`test/loop/bridge/NarrativeBridgeTest.gd`

### 6.2 `StoryArcGenerator` + `StoryArcJsonLoader`（§7.2）

| ID | Given/When/Then | 阶段 |
|---|---|---|
| TC-GEN-01 | Given mock LLM 返回一段合法的故事弧 JSON（3 NPC / 5 步，字段齐全） | 调 `generate(params)` | 返回的 `StoryArcDefinition` 各字段与 JSON 输入一一对应 | P2 |
| TC-GEN-02 | Given mock LLM 返回**缺字段**的 JSON（如缺 `breakdown_threshold`） | 调 `generate(params)` | 参照 `BTJsonLoader` 的错误处理风格：`push_error` 并返回 `null`，**不**用默认值静默补全（架构文档 §15 风险点3 明确要求这个行为） | P2 |
| TC-GEN-03 | Given mock LLM 返回类型错误的 JSON（如 `trauma_type` 给了字符串而不是枚举名） | 调 `generate(params)` | 同上，`push_error` + `null` | P2 |
| TC-GEN-04 | Given 合法 JSON，但 `npc_definitions` 数组为空 | 调 `generate(params)` | 视为非法（0 NPC 的故事弧不合理），`push_error` + `null` | P2 |

测试文件：`test/loop/generation/StoryArcJsonLoaderTest.gd`（照抄 `test/BTJsonLoaderTest.gd` 的测试组织方式）

### 6.3 `StoryArcValidator`（§7.2）

| ID | Given/When/Then | 阶段 |
|---|---|---|
| TC-VALID-01 | Given《遗嘱》fixture（已知会崩坏） | 调 `validate(arc)` | `report.breakdown_path_exists == true` | P2（复用 Phase1 的 fixture，无需重新造数据） |
| TC-VALID-02 | Given 一个人为构造的、任何 NPC 压力都不可能超过阈值的"温和故事弧" | 调 `validate(arc)` | `report.breakdown_path_exists == false`（验证器应该能筛掉这种不合格的初始条件） | P2 |
| TC-VALID-03 | Given《遗嘱》fixture，`information_gaps` 里声明了断层①但对应的 `witnessable EventRecord` 不存在 | 调 `validate(arc)` | `report.gaps_discoverable == false` | P2 |
| TC-VALID-04 | Given《遗嘱》fixture 原始数据（断层可被观察到） | 调 `validate(arc)` | `report.gaps_discoverable == true` | P2 |

测试文件：`test/loop/generation/StoryArcValidatorTest.gd`

### 6.4 `DialogueConstraintBuilder` + 净化兜底（§7.3）

| ID | Given/When/Then | 阶段 |
|---|---|---|
| TC-DIALOGUE-01 | Given `npc.beliefs` 含一条 `confidence=0.68` 的信念 | 调 `build()` | 生成的 prompt 文本中**不出现**裸露的数字 `0.68`（应转成"较高把握"一类的定性描述，验证 `_describe_beliefs_without_revealing_numbers` 确实做了脱敏） | P2 |
| TC-DIALOGUE-02 | Given mock LLM 返回的对话文本命中黑名单关键词（如"置信度"） | 走净化流程 | 触发重新请求或替换为预置安全模板（需要先确定策略：本测试驱动在 §7.3 基础上明确"重试几次后强制走模板"的兜底上限，避免死循环重试） | P2 |
| TC-DIALOGUE-03 | Given mock LLM 返回的文本完全合规 | 走净化流程 | 原文本原样通过，不被误伤（防止黑名单误杀正常台词，比如"我很确信"这种日常用语不应被拦截，只拦截"置信度""压力值"这类明显的术语） | P2 |

测试文件：`test/loop/bridge/DialogueConstraintBuilderTest.gd`

---

## 7. 观察者表现层（对照架构文档 §8）—— 场景测试，待 UI/场景资源就位后落地

### 7.1 `ObserverController`（§8.1）

| ID | Given/When/Then | 阶段 |
|---|---|---|
| TC-OBS-01 | Given `RoomManager.rooms` 含 `"MeetingRoom"` | 调 `move_to_location("MeetingRoom")` | `current_room_key` 更新，`global_position` 等于该房间 `RoomData.position`，`observer_moved` 信号发出 | P4 |
| TC-OBS-02 | Given 传入一个不存在的 room_key | 调 `move_to_location()` | 不移动，`current_room_key` 不变，不抛异常 | P4 |
| TC-OBS-03 | Given `event.visibility=PUBLIC` | 调 `can_perceive_event(event)` | 返回 `true`（无论观察者在哪） | P4 |
| TC-OBS-04 | Given `event.visibility=PRIVATE`，`event.location != current_room_key` | 调 `can_perceive_event(event)` | 返回 `false` | P4 |
| TC-OBS-05 | Given `event.visibility=PRIVATE`，`event.location == current_room_key` | 调 `can_perceive_event(event)` | 返回 `true` | P4 |

测试文件：`test/loop/presentation/ObserverControllerTest.gd`（单元测试，不需要 `scene_runner`，`ObserverController` 是纯逻辑 `Node2D`）

### 7.2 `FogOfWarManager` 扩展（§8.2）—— 现有文件的回归测试

| ID | Given/When/Then | 阶段 |
|---|---|---|
| TC-FOW-REG-01 | Given 现有 `test/FogOfWarManagerTest.gd` 全部用例 | 扩展支持 `ObserverController` 作为可见性原点后重跑 | 全部沿用现有断言，**不允许**因为新增分支导致原有沙盒模式（以 `CharacterManager.current_character` 为原点）的行为发生变化——这是一条纯回归测试，不新增断言，只保证不破坏 | P4 |
| TC-FOW-OBS-01 | Given 场景中只有 `ObserverController`（无 `CharacterManager.current_character`） | 调 `is_node_visible_to_player()` | 以 `ObserverController` 位置为原点计算可见性多边形，逻辑与原有算法一致（只是原点来源不同） | P4 |

测试文件：`test/loop/presentation/FogOfWarObserverIntegrationTest.gd`（新增，不修改现有 `FogOfWarManagerTest.gd`）

### 7.3 `LoopMainUI`（§8.3）—— 场景交互测试

| ID | Given/When/Then | 阶段 |
|---|---|---|
| TC-UI-MAIN-01 | Given 场景加载 | `find_child("NarrativeArea")`/`find_child("NPCStatusBar")`/`find_child("ActionSelectionArea")` | 三个节点均存在（对照 `script/ui/AGENTS.md` 的"节点名唯一且语义化"规范） | P4 |
| TC-UI-MAIN-02 | Given 某个 `ActionDefinition` 已解锁但当前 `execution_conditions` 不满足 | 渲染 Action 列表 | 对应列表项 `disabled=true`（灰显），且附带条件提示文本可读取 | P4 |
| TC-UI-MAIN-03 | Given NPC `stress=92` | 渲染 `NPCStatusCard` | 命中 `STRESS_VISUAL_TABLE` 最后一档（`critical`/红色边框），验证查表逻辑而不是一堆 `if/elif` | P4 |
| TC-UI-MAIN-04 | Given 玩家点击某个已解锁且条件满足的 Action 按钮 | 模拟点击（参照 skill 里 Example 2/3 的鼠标模拟或 spy 方案） | `LoopController.submit_player_action()` 被调用一次（`verify(spyed,1)`），且参数里的 `action_def.action_id` 与被点击项一致 | P4 |

测试文件：`test/loop/presentation/LoopMainUITest.gd`

---

## 8. 存档与跨循环持久化（对照架构文档 §9）

### 8.1 `LoopSnapshotStore`（§9.1）

| ID | Given/When/Then | 阶段 |
|---|---|---|
| TC-SNAP-01 | Given 连续调用 `record()` 5 次（模拟 5 个时间步） | `step_snapshots.size()` | 等于 5，且顺序与调用顺序一致 | P3 |
| TC-SNAP-02 | Given 已记录 5 步 | 调 `replay_to_step(2)` | 返回第 2 步（0-indexed）记录的 `world_state`，与 `record()` 时传入的深拷贝内容一致（不是引用） | P3 |
| TC-SNAP-03 | Given `replay_to_step()` 传入越界下标 | 调用 | 明确的错误处理（`push_error` 或返回空字典），不越界崩溃 | P3 |

测试文件：`test/loop/persistence/LoopSnapshotStoreTest.gd`

### 8.2 `StoryProgressSave`（§9.2）—— 关键：字段范围的负面测试

| ID | Given/When/Then | 阶段 |
|---|---|---|
| TC-PROGRESS-01 | Given 填充 `discovered_facts`/`unlocked_action_ids`/`completed_arc_ids` | `save()` 再 `load()` | 还原后字段完全一致 | P4 |
| TC-PROGRESS-02（**负面测试，防止误存状态**） | Given 检查 `StoryProgressSave` 的全部字段声明 | 静态扫描其属性列表 | **不包含**任何 `stress`/`trust`/`belief` 相关字段名（架构文档 §9.2 明确"这几项不应该出现在跨循环存档里"，这条测试直接把这条设计原则变成可执行断言，而不是只停留在文档注释） | P4 |
| TC-PROGRESS-03 | Given 存档文件不存在 | 调 `load()` | 返回一个字段全部为空/默认值的新实例，不抛异常（"首次游玩"场景） | P4 |
| TC-PROGRESS-04 | Given 存档文件内容是损坏的 JSON | 调 `load()` | 优雅降级（同上），并 `push_error` 记录日志，不让游戏崩溃 | P4 |

测试文件：`test/loop/persistence/StoryProgressSaveTest.gd`

### 8.3 存档目录隔离（架构文档 §9.3）

| ID | Given/When/Then | 阶段 |
|---|---|---|
| TC-SAVEDIR-01 | Given `LoopSaveManager.SAVE_PATH`（或所在目录）与现有 `GameSaveManager.SAVE_DIR` | 比较两个路径常量 | 不相同，且互不为对方的子路径（防止未来某次改动导致两套存档互相覆盖） | P4 |

测试文件：`test/loop/persistence/SaveDirIsolationTest.gd`

---

## 9. 复盘系统（对照架构文档 §10）

复盘系统本身是纯展示层（架构文档 §10 原文："复盘 UI 本质上是纯展示层，不需要额外计算"），因此测试重点是**数据绑定正确性**，不是重新验证推导引擎的数值（那是 §3 的职责）。

| ID | Given/When/Then | 阶段 |
|---|---|---|
| TC-REVIEW-01 | Given 一个已有 `LoopRecord`（含 5 步 `step_snapshots`） | 打开 `ReviewTimelinePanel` | 时间线上渲染出 5 个节点，每个节点的压力数值标注与 `step_snapshots[i]` 对应 NPC 的 `stress` 完全一致 | P3 |
| TC-REVIEW-02 | Given `LoopRecord.information_gaps_revealed` 含 1 条断层 | 打开 `ReviewGapDetailPanel` | 展开面板显示的"错误信念/客观事实/沉默动机"三项文本，与 `StoryArcDefinition.information_gaps` 中对应条目的字段一致 | P3 |
| TC-REVIEW-03 | Given `LoopRecord.player_actions` 含 1 条 `PlayerActionResolution`（失败案例） | 打开 `ReviewActionAnalysisPanel` | 面板展示的四个系数值与 `PlayerActionResolution` 字段逐一对应（复用 §4.3 TC-EFFECT-04 的数据契约） | P3 |
| TC-REVIEW-04 | Given 玩家失败次数 ≥3（存储在 `StoryProgressSave.per_arc_loop_history`） | 打开复盘面板 | 显示"最优路径提示"按钮，点击后展示 `StoryArcDefinition.recommended_solution_path`（该字段需要在 §7.2 `StoryArcValidator` 阶段就已经算出并存入，这条测试同时验证"验证器产出"和"复盘展示"两端的数据打通） | P3 |
| TC-REVIEW-05 | Given 玩家失败次数 <3 | 打开复盘面板 | 不显示"最优路径提示"按钮 | P3 |

测试文件：`test/loop/review/ReviewTimelinePanelTest.gd` / `ReviewGapDetailPanelTest.gd` / `ReviewActionAnalysisPanelTest.gd`

---

## 10. Action 解锁系统（对照架构文档 §11）

| ID | Given/When/Then | 阶段 |
|---|---|---|
| TC-UNLOCK-01 | Given 一个锁定的 `ActionDefinition`，`unlock_condition` 要求"观察到事件 E 且目击 NPC 为 A" | 调 `check_observation_trigger(observer, event_E, "A")` | 触发 `action_unlocked` 信号，`StoryProgressSave.unlocked_action_ids` 追加该 Action | P4 |
| TC-UNLOCK-02 | 同上条件，但传入的 `npc_witnessed` 是 "B" 而非 "A" | 调 `check_observation_trigger()` | 不解锁，不发信号 | P4 |
| TC-UNLOCK-03 | Given 一个"跨循环触发型"Action，条件是"该信息断层已在 ≥2 轮循环中被观察到不同侧面" | 调 `check_cross_loop_trigger(progress)`，`progress` 里只记录了 1 轮 | 不解锁 | P4 |
| TC-UNLOCK-04 | 同上，`progress` 记录了 2 轮 | 调 `check_cross_loop_trigger()` | 解锁 | P4 |
| TC-UNLOCK-05 | Given 该 Action 已经解锁过一次 | 再次满足解锁条件并调用 `check_*_trigger()` | 不重复触发 `action_unlocked` 信号，`unlocked_action_ids` 不出现重复项 | P4 |
| TC-UNLOCK-06 | Given `ActionDefinition.is_time_limited=true`，其 `expires_condition` 已满足（情境依赖型过期，§15.5） | 检查该 Action 在当前 Action 列表中的状态 | 自动移除/标记失效，附带说明文本（需要一个 `ActionExpiryChecker`，架构文档未展开此类，此测试同时驱动补充其最小接口） | P4 |

测试文件：`test/loop/unlock/ActionUnlockManagerTest.gd`

---

## 11. 现有系统改造的回归测试（对照架构文档 §12）

| 现有测试文件 | 改造后是否需要重跑并保持绿色 | 说明 |
|---|---|---|
| `test/FogOfWarManagerTest.gd` | 是 | §8.2 扩展原点来源后必须保持通过 |
| `test/OfficeFogOfWarIntegrationTest.gd` | 是 | 同上，场景集成层面 |
| `test/CharacterPersonalityTest.gd` | 是（不受影响） | Loop Collapse 不改 `CharacterPersonality.gd`，此文件应始终为绿色基线 |
| `test/RoomManagerTest.gd` / `RoomDataTest.gd`（若存在） | 是（不受影响） | `RoomManager` 被直接复用未改动 |
| `test/GameSaveManagerInteractableTest.gd` | 是（不受影响） | `GameSaveManager` 保留给沙盒模式，未改动 |
| `test/BTJsonLoaderTest.gd` | 是（不受影响） | 仅作为 `StoryArcJsonLoader` 的模式参照，原文件未改动 |

**验收方式**：`./runtests.sh res://test/`（全量，不限定 `test/loop/`）在每个 Phase 结束时都要跑一次，防止 Loop Collapse 的新代码意外影响沙盒模式（例如不小心改了 `FogOfWarManager.gd` 的公共方法签名）。

---

## 12. 测试覆盖优先级矩阵（汇总）

| 优先级 | 范围 | 理由 |
|---|---|---|
| **P0（Phase 1 必须先行，其余一切工作的地基）** | §1 全部数据模型 + §2 `WorldStateContext` + §3 五个推导子模块 + §3.6/3.7 引擎组装与确定性/Lint | 没有这些测试打底，后续任何数值 bug 都会被误判成"策划数值需要调整"而不是"实现错误" |
| **P1（Phase 1 收尾，验收门槛）** | §3.8《遗嘱》黄金测试 + §4 全部 Action 队列测试 | 是 GDD 明确写出的 Phase 1 验收标准原文对应的测试 |
| **P2（Phase 2 开始前应设计好接口，Mock 优先）** | §6 LLM 集成层 | 由于是 Mock 驱动，理论上可以在真正接 LLM 之前就把测试和接口定义写完，反过来约束 `NarrativeBridge`/`StoryArcGenerator` 的实现 |
| **P3** | §9.1 `LoopSnapshotStore` + §10 复盘系统数据绑定 | 依赖 P0/P1 产出的真实 `ScriptFrame`/`PlayerActionResolution` 数据，不能提前太多 |
| **P4** | §5 `LoopController` + §7 观察者表现层/UI + §8.2/8.3 存档 + §11 Action 解锁 | 依赖 Godot 场景资源就位，是最后一批 |

---

## 13. 新增测试文件一览（可直接当作开发 checklist）

```
test/loop/
├── model/
│   ├── TraumaTypeTest.gd
│   ├── BeliefTest.gd
│   ├── EventRecordTest.gd
│   ├── NPCStateTest.gd
│   ├── NPCDefinitionTest.gd
│   ├── ActionDefinitionTest.gd
│   └── SerializationRoundtripTest.gd
├── engine/
│   ├── WorldStateContextTest.gd
│   ├── PerceptionFilterTest.gd
│   ├── InterpretationResolverTest.gd
│   ├── BeliefUpdaterTest.gd
│   ├── AttributionPropagatorTest.gd
│   ├── BreakdownEvaluatorTest.gd
│   ├── InferenceEngineStepTest.gd
│   ├── InferenceEngineDeterminismTest.gd
│   ├── EngineDeterminismLintTest.gd
│   ├── ActionQueueInjectTest.gd
│   ├── ActionQueueResolveTest.gd
│   ├── EffectivenessFormulaTest.gd
│   ├── SideEffectApplierTest.gd
│   ├── WillArcBreakdownTest.gd      # 见 phase1-plan.md
│   └── WillArcRescueTest.gd         # 见 phase1-plan.md
├── loop/
│   └── LoopControllerTest.gd
├── bridge/
│   ├── NarrativeBridgeTest.gd
│   └── DialogueConstraintBuilderTest.gd
├── generation/
│   ├── StoryArcJsonLoaderTest.gd
│   └── StoryArcValidatorTest.gd
├── presentation/
│   ├── ObserverControllerTest.gd
│   ├── FogOfWarObserverIntegrationTest.gd
│   └── LoopMainUITest.gd
├── persistence/
│   ├── LoopSnapshotStoreTest.gd
│   ├── StoryProgressSaveTest.gd
│   └── SaveDirIsolationTest.gd
├── review/
│   ├── ReviewTimelinePanelTest.gd
│   ├── ReviewGapDetailPanelTest.gd
│   └── ReviewActionAnalysisPanelTest.gd
└── unlock/
    └── ActionUnlockManagerTest.gd
```

共 **32 个测试文件**，覆盖架构文档 §3~§13 的每一个具名类/模块。P0+P1（Phase 1 范围）合计 **17 个文件**，是当前应该立刻动手实现的部分。

---

*本文档随 `loop-collapse-architecture.md` 的实现推进同步更新；任何架构文档里的类/方法签名发生变化，本文档对应的 Given/When/Then 描述需要同步修订，避免"设计文档、测试文档、实际代码"三者语义漂移。*

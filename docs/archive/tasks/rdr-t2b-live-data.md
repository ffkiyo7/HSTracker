# 红龙 T2b —— 接对局数据：局面读取、后台搜索、展示模型、开关（无 UI）

先读 `docs/tasks/_common.md`。前置：T2a（`docs/tasks/rdr-t2a-formula-audit.md`，已提交）。背景：`docs/research/red-dragon-rogue-spike.md`
第二节（揭示节奏 / 多条线 / 同名牌 / 抽牌 / 对手侧 / 预启动 / 重编号）、第四节（现成材料，**行号是 09-11 旧线的，以现码为准**）、
第六节（已决）；`docs/research/red-dragon-card-model.md` 的 A / B 节，尤其 **B3「读日志 vs 自己算」**。

## 要做出什么

T2c 只负责画。本书把「对局 → 该画什么」整条链做完，并能离线测：

1. **局面读取**：从当前对局构造红龙搜索的输入。费用、附魔、减费层、复制体、召唤失调、敌方有效血量 / 嘲讽 / 圣盾、本回合已出牌、牌库与边牌剩余、T2a 新增的前提状态，都要有出处；哪些读游戏、哪些自己推，按 B3 的原则定，报告里逐字段列出处。
2. **只在这副牌上启用**：判据由你定（spike 二、8），不靠用户手动开；其它卡组零开销。
3. **后台计算**：去抖、可取消、过时结果不上屏；结果要能标出「正在算 / 已过时 / 被截断」。不在主线程跑搜索。
4. **展示模型**：一个与 SwiftUI 无关的值类型，覆盖 spike 第二、六节要的全部信息：能否斩杀与差值、最简线的难度档、参与牌（必打 / 可选）、前 3 步的手牌序号、不在手牌上的步骤（场面目标 / 发现选择）、一行「下一步」文字、抽牌分叉、缺件、「单回合不够 / 场面危险」提示、答题模式的对错判定。三档揭示的升降与「基础线不许升到 L2」的规则也在这一层，T2c 只读结果。
   手牌 / 场面上的标记要能落到**具体 entity**，打出一张后重编号。
5. **开关**：设置里一个「红龙辅助」总开关（默认关），**热切换**：开关一变立即生效，关掉后不再做任何计算、已有结果清空。另加 T2c 要用的偏好（默认揭示档、答题模式）。键名记进 `docs/PLAN.md`「与上游的默认值差异」—— 这一处文档由我改，你在报告里给出键名和默认值即可。
6. **离线回放测试**：本机 `/Applications/Hearthstone/Logs/Hearthstone_2026_09_2*` / `_10_01_*` 下有带 E.T.C.（`ETC_080`）的 `Power.log`，是这副牌的真实对局。从中截出 2~3 局做 fixture，在我方回合逐个跑「读取 → 搜索 → 展示模型」，挑若干回合人工核对结论（有解 / 无解 / 最大伤害 / 缺件），固化成断言；能核的话顺手验 card-model G4（币的临时水晶不算进晦鳞回费上限）。若能找到「本可斩杀但没打出」的回合，写进报告。

## T2a 留下的（`d73f8a67`，详见 T2a 任务书末尾）

- 引擎新增要从对局填的状态：幸运彗星剩余次数、敌方随从「已受伤」（背刺目标判定）、我方场面的现有顺序（落位 / 爆手规则依赖它）。
- 待日志核：彗星「连击没开也消耗」「与鲨鱼同场按 ×2」；快枪固定费是否覆盖减费；舞动手牌满烧最右（用户已定，顺手验）。日志里碰不到的写明。
- 生产默认配置不斩杀的局面会三遍搜索跑满 40 万状态（-O 单局面平均 0.18 s、最慢 1.17 s），`termination` 常为 `.budgetExceeded` —— 展示层别把它一律当成「被截断」吓用户，怎么区分由你定。

## 硬约束

- 线程照 `AGENTS.md`「线程与时序」：写展示状态一律 `DispatchQueue.main.async`，同一份状态在同一个 main block 内提交，禁止 `main.sync`；报告里列出「状态变化 → 结果上屏」的每一跳。
- 不拖慢记牌器刷新：挂点在现有刷新链上只能是一次轻量的通知，搜索本身不能进记牌器的刷新路径；关掉开关或非本牌组时零开销。
- `Game.swift` 是上游合并热点：只允许加挂点所需的极少行数，其余全在新文件（`HSTracker/RedDragon/` 下）。上游其它文件同理，每碰一个在报告里说明为什么非碰不可。
- 读取层**不准**用 `Game.opponentHeroHealth`（不减伤害、不算护甲，spike 四、2）。
- 回放 fixture 是截取的原始日志，允许用 shell 截取（`AGENTS.md`「写文件」的唯一例外，仅限日志截取），报告里给出截取命令与来源文件；单个 fixture ≤ 5 MB，放 `HSTrackerTests/Fixtures/RedDragon/`。测试不许读仓库外的路径。

## 构建节奏（10-05 用户定）

- 改动过程中只跑相关测试（`-only-testing:` 红龙 / 本书新增的测试类），全套 `test` 只在交付前跑一次。
- 测 Release 级耗时不用 Xcode 切 `SWIFT_OPTIMIZATION_LEVEL`（会整包重编两次）；在 scratchpad 里 `swiftc -O` 只编所需源文件 + 一个基准 main，不入库，报告写命令。

## 允许修改的文件

`HSTracker/RedDragon/`（新增 / 修改）、`HSTracker/Logging/Game.swift`（挂点）、设置键所在文件、`HSTrackerTests/` 下红龙相关测试与 fixture、`project.pbxproj`（只登记）。还需要碰别的，先在报告里论证。

## 验收

1. 受限环境 `clean build` 成功；`test` 条数与失败数如实报告。
2. 读取层单测：手工构造的对局实体覆盖同名不同费、1/1 复制体、减费层跨舞动、手牌满、对方护甲 + 嘲讽、非本牌组不启用。
3. 回放测试：每局至少 3 个我方回合有断言；报告给出每个断言回合的局面摘要和引擎结论。
4. 开关热切换有测试（开 → 有结果；关 → 结果清空且不再调度计算）。
5. 报告：字段出处表、线程跳数表、挂点改了哪些上游行、Debug 下单次「读取 + 搜索」耗时（回放局面上的平均 / 最慢）。

## 执行结果

2026-10-04，实现者（Opus 子代理），工作区 `dev0923`（HEAD `463b8c4d`），未提交。

### 改动文件

| 文件 | 内容 |
|---|---|
| `HSTracker/RedDragon/RedDragonSnapshot.swift`（新） | `RDGameSnapshot`：主线程从 `Game.entities` 拷出的值类型快照（Hashable，用于去重）；`capture(game:)` + 不经 `Game` 的 `capture(entities:…)`（测试用） |
| `HSTracker/RedDragon/RedDragonReader.swift`（新） | `RDDeckGate`（本牌组判据）、`RDStateReader.read`（快照 → `RDState`，纯函数，后台线程调） |
| `HSTracker/RedDragon/RedDragonHint.swift`（新） | 展示模型：`RedDragonHint` / `RDAnalysis` / 步骤 / 标记 / 揭示档规则 `RDRevealPolicy` / 答题 `RDQuizState` / `RDHintBuilder` / 引擎 id → 游戏 entity 的 `RDLineWalker` |
| `HSTracker/RedDragon/RedDragonAssistant.swift`（新） | 调度：挂点、去抖、取消、代号防过时、开关热切换；`Game.updateRedDragon()` |
| `HSTracker/RedDragon/RedDragonSearch.swift` | `RDCancellation`（可取消令牌）+ `RedDragonConfig.cancellation`；结果加 `cpuBudgetHit` / `cancelled`；三遍搜索和缺件补齐逐节点查取消 |
| `HSTracker/Fork/Settings+Fork.swift` | 三个设置键（见下） |
| `HSTracker/Logging/Game.swift` | `updateAllTrackers()` 末尾加一行 `self.updateRedDragon()` |
| `HSTracker.xcodeproj/project.pbxproj` | 只登记：4 个源文件、2 个测试文件、3 个 fixture（Resources） |
| `HSTrackerTests/RedDragonLiveTests.swift`（新） | 读取层 / 展示模型 / 揭示档 / 答题 / 热切换单测，19 条 |
| `HSTrackerTests/RedDragonLiveReplayTests.swift`（新） | 3 局离线回放（每局一条断言测试）+ 线上配置耗时，4 条 |
| `HSTrackerTests/Fixtures/RedDragon/2026-10-01-*.log`（新） | 3 局 fixture，1.7 / 2.7 / 2.7 MB |

### 设置键（`PLAN.md`「与上游的默认值差异」由总指挥写）

| 键 | 类型 | 默认 | 用途 |
|---|---|---|---|
| `red_dragon_assist` | Bool | `false` | 总开关，热切换（通知 → `settingsDidChange`） |
| `red_dragon_reveal_level` | Int | `0` | 进回合默认揭示档：0 判定 / 1 参与牌 / 2 顺序 |
| `red_dragon_quiz_mode` | Bool | `false` | 答题模式 |

### 上游行改动

- `HSTracker/Logging/Game.swift:242`：`updateAllTrackers()` 里 `self.updateCounters()` 之后加 `self.updateRedDragon()`。只此一行。选这里是因为它本来就是「tag 变了 → 16 ms 去抖 → 刷新全部记牌器」的汇合点，红龙要的正是同一个触发；挂点本身只读一次 UserDefaults，开着才投一个 `main.async`。
- 其余上游文件没碰。`Settings+Fork.swift` 是 fork 自己的文件。

### 本牌组判据

`RDDeckGate`：套牌含 `ETC_080`，且它的乐队里有阿莱（`LEG_CS3_031`），且主牌里有刀油 / 鲨鱼 / 暗影施法者 / 巢母 / 狐人老千中至少 3 张。只看 `game.currentDeck`，按套牌 id 缓存判定结果。其它卡组：挂点在开关开着时每次刷新付一次 `main.async` + 一次缓存比较，不拷快照、不碰实体；开关关着时只读一次 UserDefaults。

### 字段出处（B3：日志算好的直接读，日志里没有的才推）

| `RDState` 字段 | 出处 | 读 / 推 |
|---|---|---|
| `maxMana` | 玩家实体 `RESOURCES` | 读 |
| `mana` | `RESOURCES − RESOURCES_USED − OVERLOAD_LOCKED`（下限 0） | 读 |
| `tempMana` | 玩家实体 `TEMP_RESOURCES`（日志实测：先花它） | 读 |
| `cardsPlayedThisTurn`（连击） | 玩家实体 `NUM_CARDS_PLAYED_THIS_TURN` | 读 |
| `spellDamage` | 玩家实体 `CURRENT_SPELLPOWER` | 读 |
| `heroAttackedThisTurn` | 我方英雄 `NUM_ATTACKS_THIS_TURN > 0` | 读 |
| `heroPowerUsed` | 我方英雄技能 `EXHAUSTED` | 读 |
| `weapon` | 场上武器 `ATK`、`DURABILITY − DAMAGE`；`drawOnHeroAttack` = 卡是快速拾取 | 读 + 卡表 |
| `layers` | 玩家实体上挂的附魔：`BAR_552o`（槽 = 2 − `TAG_SCRIPT_DATA_NUM_1`，日志实测 0→1→2 后移除）、`EX1_145o`（法术）、`DMF_511e`（连击牌）、`REV_939e`（任意） | 读附魔 + 推槽数 |
| `luckyCometCharges` | 玩家实体上 `GDB_873e` 的个数 | 读（未在日志里见过，见下） |
| `hand[].entityId` / 顺序 | 实体 id，按 `ZONE_POSITION` 排 | 读 |
| `hand[].card` | `cardId` → 卡表；不在卡表的 → `junkPlaceholder` + 原 cardId；对局给的幸运币（`isTheCoin`）→ `.coin` | 读 |
| `hand[]` 费用 | **当前费用读 `COST`**；引擎需要「底费」，= `COST` + 匹配层的减免。`COST` 被压到 0 时看不出原值，底费按「带 1 费附魔（`SCH_352e2` / `OG_291e` / `ETC_079e`）→ 1，否则印刷费」封顶，记进 `inferredBaseCostEntities`（印刷费 0 的不算推断） | 读 + 推 |
| `hand[].statsOverride` | 带 `SCH_352e` / `OG_291e` 的复制体：读实体 `ATK` / `HEALTH` | 读 |
| `hand[].isShadowOfDemise` | 卡本身是殒命暗影，或带 `RLK_567e*` 附魔 | 读 |
| `board[]` | 实体 `ATK` / `HEALTH`（已扣伤）/ 最大生命 `HEALTH` tag，按 `ZONE_POSITION` 排（保留现有顺序） | 读 |
| `board[].summoningSick` | `FROZEN` ∨ `CANT_ATTACK` ∨ `DORMANT` ∨（`EXHAUSTED` ∧ 本回合未攻击 ∧ 无冲锋） | 读 |
| `board[].statsSetTo1x1` / `enchants` | 带 `SCH_352e` / `OG_291e` → 1/1、`[.set(1)]` | 读 |
| `board[].silenced` / `attacksThisTurn` | `SILENCED` / `NUM_ATTACKS_THIS_TURN` | 读 |
| `opponent.health` / `armor` / `immune` | 敌方英雄 `Entity.health`（= `HEALTH − DAMAGE`）、`ARMOR`、`IMMUNE`；**不用 `Game.opponentHeroHealth`** | 读 |
| `opponent.board[]` | 敌方场上随从 `ATK` / 剩余生命 / `TAUNT` / `DIVINE_SHIELD` / `IMMUNE` / `STEALTH`；`damaged` = `DAMAGE > 0`；潜行 / 休眠 / `UNTOUCHABLE` 的不进局面 | 读 |
| `opponent.secretCount` | 敌方 SECRET 区奥秘数 | 读 |
| `deck` | `player.getDeckState().remainingInDeck`（记牌器自己的剩余牌）；不在卡表的 → `junkPlaceholder` | 读（HSTracker 已算） |
| `sideboard` | 套牌乐队 − 已发现的：对局里我方实体 `COPIED_FROM_ENTITY_ID` 指回 SETASIDE 里同 cardId 的乐队牌、且不是 1/1 复制体，就扣掉（日志实测：选中的离开 SETASIDE，没选的留着） | 读 + 推 |
| `secretsInPlay` | 我方 SECRET 区 | 读 |
| `nextEntityId` | 对局最大 entity id + 1000（引擎新造实体不和游戏 id 撞） | 推 |
| 展示用：场攻 / 场面危险 | `BoardState(game:)` 的 `opponent.damage`、`isPlayerDeadToBoard()` | 读（HSTracker 已算） |

### 线程跳数（状态变化 → 结果上屏）

| # | 线程 | 做什么 |
|---|---|---|
| 1 | 解析线程 | tag 变化 → `Game.updateTrackers()` |
| 2 | guiupdate 队列（`OverlayRefreshScheduler`，16 ms 去抖） | `updateAllTrackers()` → `updateRedDragon()` → `gameDidUpdate`：开关关着直接返回；开着投 **`main.async`（第 1 跳）** |
| 3 | 主线程 | 判菜单 / 套牌（缓存）/ 模式 / 起手 / 当前玩家 → 拷快照；与上一份相同就停。否则作废在算的、发布「正在算」（旧结论标过时）、`workQueue.asyncAfter(0.12 s)` |
| 4 | 后台串行队列（utility） | 已作废就不跑；读取 + 搜索（逐节点查取消）+ 生成结论 → **`main.async`（第 2 跳）** |
| 5 | 主线程 | 代号仍是最新、开关仍开 → 结论 + 揭示档 + 答题判定在同一个 block 里写入 `hint`，回调 `onChange`（T2c 接） |

没有 `main.sync`。设置通知（总开关 / 揭示档 / 答题）在 `queue: .main` 上收，直接在主线程处理。

### 展示模型要点（判断点，请总指挥 / 用户定）

- **截断口径**：`.complete`（搜完 / 找到最优）、`.capped`（撞 40 万状态闸门，T2a 说的 `.budgetExceeded`，不当截断）、`.truncated`（只有撞 3 s CPU 兜底才标）。
- **基础线揭示上限 = L1**（参与牌），升不到 L2；不斩杀只给 L0。spike 另一处写「基础线只给 L0」，两种读法取了前者，`RDRevealPolicy.cap` 一行可改。
- **只有困难线时**默认直接开到 L2（兜底引导），用户按热键降下来就听用户的。
- 多条斩杀线：优先不靠抽牌的；必打 = 各线交集，可选 = 并集 − 交集。
- 「下一步」文字只用卡名 + 符号（→ ⚔ ▸），没有写死语言。卡名用 `Cards.any(byId:)?.name`，跟随应用语言。
- 抽牌分叉不含边牌发现；不在卡表的牌库牌按杂牌算，不会成为抽牌分叉里的「斩杀件」。
- 场面危险 = 记牌器的 dead-to-board，或对方场攻 + 3 ≥ 我方血 + 甲。

### 测试与构建

- 受限环境（加 github.com 代理的 git 配置）`clean build`：**成功**（57 条警告，均不在 `RedDragon` 下）。
- 红龙新增两类（`-only-testing:HSTrackerTests/RedDragonLiveTests -only-testing:HSTrackerTests/RedDragonLiveReplayTests`）：**23 条，0 失败**（81 s，其中回放 3 局断言 + 线上配置耗时 ≈ 80 s）。
- 全套 `test`（不加 skip）：**399 条，1 跳过，2 失败**，457 s，宿主未重启。跳过的是 `RedDragonFormulaTests.testProductionConfigCostRelease`（Debug 下按设计跳过）。两个失败都与本书无关、是既有的：`OfficialBuildTests.testHostAppIsRecognizedAsOfficial`（本地签名，之前基线就失败）、`LocalizationFormatTests`（「found no string catalogs under Translations/」，之前基线是 `-skip-testing` 掉它跑的）。新增 23 条全过。

### 读取层单测（`RedDragonLiveTests`，手工构造实体）

同名不同费（两张刀油 4 / 2 费都是合法出牌）、1/1 复制体（手里 + 场上，暗影步收回 0 费、致聋沉默回 8/8）、减费层跨舞动（两层各剩 1 槽，`ETC_079e` 的 0 费随从底费推为 1，层吃完后回到 1，E.T.C. 回到 4）、玩家附魔 → 层 + 彗星次数、手牌满 + 未建模牌 + 对局幸运币、对方护甲 + 嘲讽 + 潜行 / 休眠不进局面 + 已受伤、法力与临时水晶、E.T.C. 发现后边牌扣减、非本牌组不启用（`RDDeckGate` 五种）。展示：两张 1 费阿莱 → 必打 + 落到 entity + 打出一张后重编号；场面目标落到真实随从；不斩杀的缺件 / 单回合不够 / `.capped` 与 `.truncated` 区分；场面危险阈值；揭示档规则；答题判定。热切换：开 → 有结果、同局面不重算；关 → 立即清空、之后不再调度计算；再开 → 请求一次刷新；算到一半关掉不上屏；去抖只上屏最后一个局面、旧结论标过时。

### 离线回放（`RedDragonLiveReplayTests`）

- 来源：`/Applications/Hearthstone/Logs/Hearthstone_2026_10_01_00_43_36/Power.log`（09-2* 目录本机不存在）。截取命令（仓库根，`L` 为上述文件）：
  ```
  F='^D [0-9:.]+ (GameState\.|PowerTaskList\.DebugPrintPower|PowerProcessor\.EndCurrentTaskList)'
  awk 'NR>=90653 && NR<=114079' "$L" | grep -E "$F" > HSTrackerTests/Fixtures/RedDragon/2026-10-01-g4-second.log
  awk 'NR>=114080 && NR<=137401' "$L" | grep -E "$F" > HSTrackerTests/Fixtures/RedDragon/2026-10-01-g5-first.log
  awk 'NR>=76053 && NR<=90652' "$L" | grep -E "$F" > HSTrackerTests/Fixtures/RedDragon/2026-10-01-g3-lost.log
  ```
- 回放方式：只把 `PowerTaskList` 行交给 `PowerGameStateParser`（与 `LogReaderManager` 一致）；玩家名从 `GameState.DebugPrintGame` 的 `PlayerName=` 行取（线上来自 HearthMirror），否则 `CURRENT_PLAYER` 认不到人。在我方每个 `STEP=MAIN_ACTION`（抽完牌、未出牌）拷快照 → 读取 → 搜索 → 展示模型。断言用「CPU 兜底放开、只留 40 万状态闸门」的配置，结论不随机器快慢变。
- 断言回合（局面摘要 → 引擎结论 → 实际）：

| 局 | 回合 | 局面 | 引擎 | 实际 |
|---|---|---|---|---|
| G4 后手赢 | T2 | 1 费，手：挖宝 / 地图 / 步 / 斗篷 / 对局币 / 殒命；敌 30 | 不斩杀，最大 1（技能） | 对方 30 |
| | T6 | 3 费，手有鱼、牛，无刀无狐；敌 30 | 不斩杀，最大 1 | 对方 29 |
| | T8 | 4 费，手：步 / 斗篷 / 币 / 殒命 / 鱼 / 牛 / 狐 / 暗 / 行骗 / 巢母（无刀油）；敌 30，场 3 随从 | **可斩杀 32/30，困难，但靠抽**：行骗抽到币或暗影步才成（252 个抽牌分支里 2 种抽法斩杀） | 对方回合后仍 30 —— 「有概率斩但没打」，不是确定漏斩 |
| | T10 | 5 费，鱼 / 狐 0 费 / 刀 / 牛 / 暗 / 巢母 / 两币；敌 30 | 可斩杀 32/30，基础，不靠抽，第一步鲨鱼 | 本回合斩杀 |
| G5 先手赢 | T1 | 1 费，致聋 / 斗篷 / 挖宝 ×2 | 不斩杀，最大 0 | — |
| | T5 | 3 费，有黑水弯刀 | 不斩杀，最大 2（弯刀） | — |
| | T9 | 5 费，鱼狐刀暗牛巢母齐但无币 | 不斩杀（搜完） | 对方 30 |
| | T11 | 6 费 + 伪造的币，鱼狐刀暗牛巢母步；敌 30，奥秘 1 | 可斩杀 32/30，进阶，不靠抽，第一步鲨鱼 | 本回合 32 伤斩杀（实际打法同为确定性线） |
| G3 先手输（投降） | T1 | 1 费，地图 / 弯刀 / 币 / 暗 | 不斩杀，最大 2 | — |
| | T9 | 5 费，无巢母；敌 28，4/4 嘲讽圣盾 | 不斩杀，最大 16（两次阿莱），撞状态闸门 | 对方 27 |
| | T11 | 6 费，无刀无巢母；敌 27，嘲讽 | 不斩杀，最大 0 | 对方 27 |
| | T13 | 7 费，无刀；敌 27，敌场 6 随从 | 不斩杀，单回合不够；场面危险（我 16 血） | 对方下一回合攻击后我方投降 |

- 每个回合另断言：手牌张数与顺序、敌方有效血量、水晶、边牌、手里没有未建模牌。18 个我方回合全部读出、全部在卡表内。
- **「本可斩杀但没打出」**：无确定性漏斩。G4 T8 是靠抽牌的困难线（行骗抽对才成）。
- G4（币的临时水晶不算进晦鳞回费上限）：三局里没有「币的临时水晶未花完时打巢母」的局面（G5 T11 先花了币再打巢母），**日志碰不到**。

### Debug 下「读取 + 搜索」耗时（线上配置 `RedDragonConfig()`，回放 18 个我方回合，线程 CPU）

- **平均 1.24 s，最慢 5.01 s**（G3 T9，三遍搜索里主遍撞 3 s 兜底后另两遍继续跑）。两次运行分别为 1.30 / 5.03 s 和 1.24 / 5.01 s。
- **问题：Debug 下线上配置会漏斩杀。** G5 T11 两次都是「不斩杀，最大 17，被截断」；G4 T8 / T10 一次截断、一次找到（3 s 边缘）。放开 CPU 兜底三处都能斩杀（Debug 3.2 / 3.4 / 4.1 s）。
- 对照 Release 级（scratchpad `swiftc -O -wmo`，同样的 8 个最重根局面、默认配置）：**平均 0.54 s，最慢 1.27 s**，三个斩杀回合 0.27 / 0.27 / 0.35 s 全部找到。Debug 约慢 11 倍。命令（仓库根，`B` = scratchpad 下 `bench2b/`，`main.swift` 里的根局面由 `RedDragonLiveReplayTests.literal` 打印）：
  ```
  env PATH=/usr/bin:/bin:/usr/sbin:/sbin xcrun swiftc -O -wmo -enable-testing -emit-library -emit-module \
    -module-name HSTracker -emit-module-path $B/HSTracker.swiftmodule -o $B/libHSTracker.dylib \
    HSTracker/RedDragon/RedDragon{Cards,Components,Difficulty,Engine,Replay,Search,State}.swift
  env PATH=/usr/bin:/bin:/usr/sbin:/sbin xcrun swiftc -O -module-name RDBench -I $B -L $B -lHSTracker \
    -Xlinker -rpath -Xlinker $B -o $B/rdbench $B/main.swift && $B/rdbench
  ```
  只编引擎 7 个文件：新增的 Snapshot / Reader / Hint / Assistant 依赖 `Entity` / `Game` / `Settings`，`HSTracker/RedDragon/*.swift` 整目录已不能单独编（T2a 的命令要相应改）。

### T2a 留下的待核项

- **舞动手牌满「烧最右」：被日志否定。** 本机 10-01 日志 5 次爆手：4 次烧的是最右（场位 6–7），但 `Hearthstone_2026_10_01_00_43_36/Power.log` PowerTaskList 第 31601 行那次，回手的是场位 4–7（鲨鱼 / 刀油 / E.T.C. / 巢母，按本回合上场先后），烧掉的是场位 1–3（玩家放在最左的后上场随从，含刚从手里打出的 E.T.C. id 185）。与 5 次都一致的规则是「按上场先后回手，最后上场的被烧」，没有落位到左边时它恰好等于「烧最右」。引擎现在按最右烧，**没改**（任务外）。
- 彗星两条假设：日志里我方没打过幸运彗星（`GDB_873`），**碰不到**。读取层按 `GDB_873e` 个数填次数，未经实测。
- 快枪固定费：唯一的快枪牌脱水（`WW_325`）我方没打过（对手打过 `WW_411`），**碰不到**。

### 风险 / 任务外发现

1. **Debug 下漏斩杀**（上节）。用户日常跑 Debug，线上配置在 Debug 里三处斩杀回合有一处稳定漏、两处时有时无。可选：Debug 构建放宽 CPU 兜底（如 `#if DEBUG` 15 s，代价是 Debug 下最坏要等十几秒才出结论）；或维持现状、overlay 上把「被截断」标显眼。待定。
2. **难度打分**：只有两张阿莱的预启动线被打成进阶（模板五张全缺 5×6 + 2 = 32），而 `RedDragonDifficulty.swift` 注释写「基础 = 预启动」。属 T2a 的阈值口径，没改。
3. fixture 里有真实 BattleTag 和 GameAccountId（我方 + 三个对手），截取命令没脱敏。私有 fork 不外发，如需脱敏要另定做法（shell 改写日志超出本书允许的「截取」）。
4. 全套测试会被本机真实炉石的进程事件打断：跑测试时炉石正好退出，宿主 app 按 `quit_when_hs_closes = 1` 自行退出，xcodebuild 重启宿主后后半截 0 条执行；同时宿主 app 对真实炉石做了 HSReplay 收藏同步（401）。与本改动无关，跑测试前最好关掉炉石。
5. 回放测试较慢（Debug 约 80 s，主要是 G3 三个撞 40 万状态闸门的回合各 12–15 s）。
6. 未建模的牌库牌不进抽牌分叉的「斩杀件」，只占数量。

## 第二轮（10-05，总指挥 review 后的 14 条）

实现者（Opus 子代理），工作区 `dev0923`（HEAD `463b8c4d`），未提交。中途被 API 限流打断一次，恢复后先 `git diff` 核对、清掉了临时诊断代码（`testZZDiagSupplement`）再继续。**本节与上面第一轮冲突处以本节为准**：挂点、线程跳数、G3 T9 / T13 的结论、Debug 耗时、风险 1 / 3 / 5 都已变。

### 改动文件（本轮）

| 文件 | 内容 |
|---|---|
| `HSTracker/RedDragon/Package.swift`（新） | 本地包 `RedDragonCore`：引擎 + 读取 + 展示模型 10 个文件，`-O -enable-testing`（C13） |
| `HSTracker/RedDragon/RedDragonGameSnapshot.swift`（新） | `RDGameSnapshot` 值类型从 Snapshot.swift 拆出来进包；加 `match`、`optionsPlayedThisTurn`、`heroFrozen`、`Minion.playOrder` |
| `HSTracker/RedDragon/RedDragonSnapshot.swift` | 只剩 app 侧的拷快照（`capture`），要碰 `Game` / `Entity` |
| `HSTracker/RedDragon/RedDragonAssistant.swift` | 重写调度：解析线程挂点、开关缓存、套牌判定缓存、局面版本 + 对局身份核对；`RDDeckGate.isRedDragonDeck(PlayingDeck)` 挪到这里 |
| `HSTracker/RedDragon/RedDragonReader.swift` | 填上场先后、英雄冻结；`RDDeckGate` 用卡表认 E.T.C.（包里没有 `CardIds`） |
| `HSTracker/RedDragon/RedDragonHint.swift` | `RDLethalVerdict` 四态、答题按操作数判卷 |
| `HSTracker/RedDragon/RedDragonEngine.swift` / `RedDragonState.swift` / `RedDragonSearch.swift` | 舞动按上场先后；英雄冻结；穷举标记；收尾阶段查取消 |
| `HSTracker/Logging/LogReaderManager.swift` | 挂点（见下） |
| `HSTracker/Logging/Game.swift` | 第一轮加的 `self.updateRedDragon()` 删掉，**现在零 diff** |
| `HSTracker.xcodeproj/project.pbxproj` | 本地包引用 + 产品依赖 + 链接；app 的 Sources 里去掉进包的 9 个文件（文件引用和分组保留）；登记 g2 fixture |
| `HSTrackerTests/RedDragon*.swift` | `@testable import RedDragonCore`；新测试见各条 |
| `HSTrackerTests/Fixtures/RedDragon/*.log` | 4 局，全部脱敏重截（C12） |
| `docs/research/red-dragon-card-model.md`、`docs/tasks/rdr-t2a-formula-audit.md` | 舞动顺序订正（A4） |

### A. 舞动顺序

1. **舞动按上场先后处理**。`RDBoardMinion.playOrder` + `RDState.nextPlayOrder`，引擎每下一个随从取一个号，`.bounceAllFriendly` 按 `boardIndicesByPlayOrder()` 收回、放不下的后上场者烧掉。根局面的号由读取层填：快照里每个我方随从带 `EntityInfo.boardOrder`（`TagChangeActions.updateBoardOrder` 在实体 ZONE → PLAY 时发的递增号，HSTracker 现成的），按 `(boardOrder ?? Int.max, entityId)` 排成 1…n，`nextPlayOrder = n + 1`。没有号的（直接建在场上的）排在最后、按 entity id。号相同时引擎按场位。证据（原 Power.log 第 75004 行那次）写在 card-model「T2b 舞动顺序订正」。
2. **幻觉药水没找到证据，维持按场位，标待核**：本机唯一有药水的日志里 7 次药水都没爆手，且每次场位顺序 = 上场顺序，两种口径分不出来。
3. **延后落位的机制只留给药水**：`boardOrderCards` 只认 `copyAllFriendlyToHand`；排法补搜只在起手够得着药水（`RDEngine.boardOrderMatters`）时跑。哈希只在「场位 ≠ 上场先后」时多喂上场顺序，对齐的局面哈希不变（否则采样补搜抽样变了，`t2-wuhui-03` 会掉到 16）。
4. **公式表重跑**：`RedDragonFormulaTests` 7 条全过（1 跳过，Debug 242 s）。结论变化、缺件补齐的两个已知搜索漏线（`t2-wuhu-10` 65/80、`t2-wuhui-04` 49/64，记在 `rdExpectedSupplementMisses`）都写在 T2a 任务书末尾「T2b 舞动顺序订正」。通过 85 → 80。

### B. 读取与调度

5. **同一时刻的快照 + 提交前核对**。快照改在解析线程上拷：`LogReaderManager` 每处理完一批日志行调 `parserBatchDidEnd`，解析器没有未闭合的 BLOCK（`powerGameStateParser.currentBlock == nil`）时才拷；一批断在 BLOCK 中间就记「待拷」，到下一个空闲的批末再拷。这时只有本线程写实体，实体 tag、`BoardState`、`getDeckState()` 读的是同一时刻（前提：实体只由解析线程写，没有逐处核过其它写入方）。每投递一个不同的输入，局面版本 +1、作废在算的那次；结果回到主线程时，版本必须等于解析线程最新的版本、对局身份（`Game.startTime`）没变，否则丢弃（计 `discardedComputations`）。测试 `testResultForOlderParsedVersionIsDiscarded`（主线程被占住时解析线程又拷出新局面，旧结果不上屏）。
6. **英雄冻结**：快照读我方英雄 `FROZEN` → `RDState.heroFrozen`，引擎冻结时不出英雄攻击。测试 `testFrozenHeroNeverAttacks`（引擎）、`testFrozenHeroCannotAttack`（读取层，带武器）。哈希只在冻结时多喂一项。
7. **「没搜到」≠「证明不能斩」**：`RDLethalVerdict` = `.lethal` / `.lethalIfDraw` / `.notFound` / `.provenNotLethal`。`.provenNotLethal` 要同时满足：搜索穷举（`RedDragonResult.exhaustive`：终止原因是走完，且没发生任何有损裁剪 —— 束截断、每节点动作上限、药水排法上限、深度上限下还有前沿）、手牌费用没有推断的、没被取消。「单回合不够」只在 `.provenNotLethal` 时出；答题只在证明了不能斩时判错。回放里 G4 T2（动作上限裁过）、G3 T13（撞状态上限）因此都从「单回合不够」变成 `.notFound`。
8. **答题按操作数判卷**：读玩家实体 `NUM_OPTIONS_PLAYED_THIS_TURN`（回合内只增不减），比判过的大才判，同一步的重算只更新结论。日志里这个计数先于那一步的 BLOCK 在顶层 +1（g2 fixture 第 16164 → 16184 行），所以「只有计数变了」的快照不投递（`onlyOptionCountChanged`），免得拿出牌前的局面判这一步。测试 `testQuizActionsAreMonotonic`、`testQuizNeverMarksWrongWithoutProof`。
9. **取消贯穿收尾**：主循环外，落位翻译、重放校验（包括抽牌分支）、去重、排序前后都查取消，取消就返回空线。测试 `testCancellationStopsRunningSearch`：10 张手牌、对手 999 血、不设状态上限，0.5 s 后取消，要求 1 s 内返回且 `cancelled == true`；实测 3 ms / 9 ms 返回（-O / -Onone）。
10. **零开销**：开关缓存在锁里（主线程在开关通知里更新），解析线程每批只加锁读一个 Bool，关着就返回，不读 UserDefaults。套牌判定按套牌 id 缓存（加锁，任何线程可读）。不是本牌组 / 不在对局 → `.inactive`，和上次投递的相同就不投，所以非本牌组的对局**一次 `main.async` 都没有**（`testNoMainAsyncForInactiveOrUnchangedInput`；回放 `testHookOnReplayFeedsOnlyAtConsistentPoints` 里非本牌组 0 次投递）。
11. **回放的连招中间采样点**（`boundaries()`：在我方回合每个顶层 `BLOCK_END` 后拷快照，并且每行都调挂点）：
    - 所有采样点：手牌里不是推断底费的牌，引擎费用 = 日志 `COST`（`checkCosts`）。
    - g2（新 fixture，舞动爆手那一局）舞动之前那个点：手牌 `[5, 8, 17, 166, 179, 188, 216]`；场位 `[185, 182, 31, 7, 14, 30, 19]`，上场先后 `[7, 14, 30, 19, 31, 182, 185]`；两层 `BAR_552o`（刀油）`TAG_SCRIPT_DATA_NUM_1 = 1` → 读成两层各剩 1 槽（**减费层消耗中途**）；牌库 12 张（快照合计和 `s.deck.total` 都断言）。**牌库数是独立核的**：scratchpad 的 `deckcount.py` 只按 fixture 的 PowerTaskList 行跟踪每个实体的 ZONE / CONTROLLER，数到同一行，得 12。然后让引擎打出舞动：预测的手牌 = 日志里舞动之后那个点的手牌 `[5, 7, 8, 14, 17, 19, 30, 166, 179, 188]`，狐没回手（**爆手**）。
    - g4 **临时水晶变化**：币（id=35）的 BLOCK 后 `tempMana 3`、可用 8；鲨鱼（id=48）的 BLOCK 后临时水晶用光、可用 4。
    - 挂点：每个空闲的边界局面都投递到了（1 < 回合 < 最后一回合），对方回合投递 `.opponentTurn`，非本牌组 0 次。
    - **热切换走真的设置通知**：`testHotSwitchThroughSettingsNotifications` 用 `observeSettings: true` 的实例，改 `Settings.redDragonAssist`（UserDefaults → 通知 → `settingsDidChange`），开 → 拷一次、有结果；关 → 清空、之后挂点不再拷。测试结束恢复原值。

### C. 其它

12. **fixture 脱敏**：4 个 fixture 用同一份占位重截（截取命令先确认和原 fixture 逐字节相同，再加 `sed`）：我方 BattleTag → `Me#1001`，对手 `OpponentA#2001` / `OpponentB#2002` / `OpponentC#2003` / `OpponentD#2004`；GameAccountId `hi=…` → `hi=1`，`lo=` 我方 → `1001`、对手 → `2001`…`2004`。核对：原 BattleTag、名字、账号号段逐个 `grep -c`，4 个文件全是 0。
    ```
    L=/Applications/Hearthstone/Logs/Hearthstone_2026_10_01_00_43_36/Power.log
    F='^D [0-9:.]+ (GameState\.|PowerTaskList\.DebugPrintPower|PowerProcessor\.EndCurrentTaskList)'
    # 真实值不入库：<我方Tag> / <对手A..D 的 Tag> / <hi> / <各方 lo> 取自本机原始日志
    ANON='s/<我方Tag>/Me#1001/g; s/<对手A Tag>/OpponentA#2001/g; …; s/hi=<hi>/hi=1/g; s/lo=<我方lo>\]/lo=1001]/g; s/lo=<对手A lo>\]/lo=2001]/g; …'
    awk 'NR>=90653 && NR<=114079' "$L" | grep -E "$F" | sed -E "$ANON" > 2026-10-01-g4-second.log          # 2.72 MB
    awk 'NR>=114080 && NR<=137401' "$L" | grep -E "$F" | sed -E "$ANON" > 2026-10-01-g5-first.log         # 2.68 MB
    awk 'NR>=76053 && NR<=90652' "$L" | grep -E "$F" | sed -E "$ANON" > 2026-10-01-g3-lost.log            # 1.65 MB
    awk 'NR>=55540 && NR<=76052' "$L" | grep -E "$F" | sed -E "$ANON" > 2026-10-01-g2-bounce-overflow.log  # 2.39 MB，18604 行
    ```
    （实际是每局用只含本局对手的那几条替换跑的，结果相同。）
13. **Debug 下也跑 -O 的引擎**：引擎、读取、展示模型 10 个文件做成本地包 `RedDragonCore`（`HSTracker/RedDragon/Package.swift`，源文件不挪，用 `sources` 点名），`swiftSettings: .unsafeFlags(["-O", "-enable-testing"])`。项目的 `SWIFT_OPTIMIZATION_LEVEL` 没动：Xcode 给包传 `-Onone`，后面跟上的 `-O` 生效（构建日志里两者都在，耗时证明 `-O` 生效）。app 侧（Assistant、拷快照）和测试用 `@testable import RedDragonCore`，所以引擎不用改成 `public`；代价是 Release 里这个包也带 `-enable-testing`（会导出 internal 符号，我认为对搜索热路径没有影响，但没有测过）。Release 构建能编过（见风险 1）。
    - **数据**（线上配置 `RedDragonConfig()`，3 s CPU 兜底，Debug，回放 18 个我方回合）：**平均 0.21 s，最慢 1.21 s**（G3 T13，撞 40 万状态闸门）。四个斩杀回合 **全部找到**：G4 T8 0.30 s、G4 T10 0.25 s、G5 T11 0.30 s、G3 T9 0.35 s。第一轮同样的测试是平均 1.24 s、最慢 5.01 s，G5 T11 两次都漏。回放测试整类 73.6 s → 21.2 s。
14. **展示规则没动**：`.capped` / `.truncated` 的口径、基础线最多 L1、只有困难线时默认开到 L2，照第一轮。

### 挂点（上游行）

- `HSTracker/Logging/LogReaderManager.swift` 解析循环里 `processMap.removeAll()` 之后加 3 行（1 行注释 + 1 个调用）：`RedDragonAssistant.shared.parserBatchDidEnd(coreManager.game, linesProcessed: !keys.isEmpty, idle: powerGameStateParser.currentBlock == nil)`。**非碰不可的理由**：第 5 条要「同一时刻的快照」，只有解析线程自己在两批之间知道没人在写实体、也只有它知道 BLOCK 是否闭合；第一轮挂在 `Game.updateAllTrackers()`（guiupdate 队列 + 主线程拷）拷到的可能是一批的中间态。
- `Game.swift` 第一轮那一行已删，现在没有 diff。

### 线程跳数（本轮，取代第一轮的表）

| # | 线程 | 做什么 |
|---|---|---|
| 1 | 解析线程（`LogReaderManager` 的读日志循环） | 每批末 `parserBatchDidEnd`：加锁读开关缓存，关着返回；有新行记「待拷」，解析器空闲才拷 → 判菜单 / 套牌（缓存）/ 模式 / 起手 / 当前玩家 → 拷快照；和上次投递的相同或只有操作数变了 → 停。否则版本 +1、作废在算的、投 **`main.async`（第 1 跳）** |
| 2 | 主线程 `submit` | 开关再查一次；换局清回合状态；同一局面且已有 / 正在算就停；否则作废、发布「正在算」（旧结论标过时）、`workQueue.asyncAfter(0.12 s)` |
| 3 | 后台串行队列（utility） | 已作废就不跑；读取 + 搜索（主循环和收尾都查取消）+ 生成结论 → **`main.async`（第 2 跳）** |
| 4 | 主线程 | 代号是最新、开关开着、局面版本 = 解析线程最新版本、对局身份没变 → 结论 + 揭示档 + 答题判定在同一个 block 里写入 `hint`、回调 `onChange`；否则丢弃 |

没有 `main.sync`。设置通知在 `queue: .main` 上收。

### 回放结论的变化

- **G3 T9：现在判可斩杀（32/28，基础，不靠抽）**，第一轮是「最多 16，撞状态闸门」。线：鲨→狐→刀油→暗影施法者复制刀油→牛（发现舞动 + 阿莱）→币 ×3→刀油复制品→舞动→鲨→刀油→刀油→阿莱打脸→刀油→施法者复制阿莱→阿莱打脸。这条线不爆手（手算：舞动后手里剩 3 张、收回 6 个随从），按场位和按上场先后结果一样，**第一轮的引擎同样合法、是束搜索漏了**；本轮哈希把「场位 ≠ 上场先后」的局面分开后束里留下的局面变了，搜到了。引擎严格重放通过，**没有人工逐步核过费用**。若成立，这是一局「本可斩杀但没打出」（实际对方回合后 27 血）。
- G4 T2、G3 T13：`.notFound`，不再出「单回合不够」（第 7 条）。
- 其余回合结论不变。

### 构建 / 测试

- `clean build`（受限环境 + github 代理）：**成功**，57 条警告，没有在 `RedDragon` 下的。
- 改动过程只跑 `-only-testing` 红龙四类。`RedDragonFormulaTests` 在 C13 之前（-Onone）跑过一次：7 条 0 失败 1 跳过，242 s。
- 全套 `test`：第一次不加 skip，跑到 `LocalizationFormatTests` 就卡住（01:45 开始，30 分钟无输出，我手动停了 xcodebuild）。这个测试从 `#filePath` 推出仓库根、枚举 `Translations/`，第一轮是秒失败（「found no string catalogs」），这次卡住，猜是宿主 app 读 `~/Desktop` 下的路径触发了系统权限弹窗，和本书改动无关，T2a 的基线也是 skip 掉它跑的。
- 全套 `test -skip-testing:HSTrackerTests/LocalizationFormatTests`：**405 条，1 跳过，1 失败**，106.5 s。失败是既有的 `OfficialBuildTests.testHostAppIsRecognizedAsOfficial`（本地签名）；跳过的是 `testProductionConfigCostRelease`（Debug 下按设计跳过）。红龙四类：Formula 7（1 跳过）23 s、LiveReplay 7 条 20.7 s、Live 25 条、引擎 42 条，全过。这一次的线上配置耗时：平均 0.20 s、最慢 1.16 s，四个斩杀回合全部找到。
- C13 之后 `RedDragonFormulaTests` 从 242 s 降到 23 s。

### 风险 / 任务外发现（本轮）

1. **Release**：交付前在同一受限环境下跑了一次 `-configuration Release build`（增量，不是 clean），**成功**。包在 Release 下也带 `-enable-testing`，app 用 `@testable import` 访问它；没有实际启动 Release 包验证。
2. `HSTracker/RedDragon/.swiftpm/xcode/`（空目录）是 Xcode 解析本地包时建的，没进 `.gitignore`（空目录 git 不跟踪，目前不影响）。新文件 `Package.swift`、`RedDragonGameSnapshot.swift` 没加进 Xcode 的文件分组（包里的文件不需要登记，只是在项目导航里看不到；Xcode 会在 Package Dependencies 下显示这个包）。
3. **上游已提交的 fixture 也有真实 BattleTag**：`HSTrackerTests/Fixtures/ZoneReplay/2026-09-*.log` 里有用户本人的真实 BattleTag（不是本书的文件，没动）。
4. **缺件补齐两个已知搜索漏线**（A4，T2a 任务书末尾）：要不要为它调束，待定。
5. 第一轮风险 3（fixture 没脱敏）已解决；风险 1（Debug 漏斩杀）、风险 5（回放慢）由 C13 解决。
6. 「实体只由解析线程写」这个前提没有逐处核过（第 5 条）。

## 第三轮（10-05，本机 Codex 审出的 7 条）

实现者（Opus 子代理），工作区 `dev0923`（HEAD `463b8c4d`），未提交。**与第二轮冲突处以本节为准**：线程跳数多了一跳「标过时」，`.provenNotLethal` 的条件更严，风险 2 已解决。

### 改动文件（本轮）

| 文件 | 内容 |
|---|---|
| `HSTracker/RedDragon/RedDragonAssistant.swift` | BLOCK 开着时有新行就作废旧局面（`staleMarked` / `markStale`）；边界上的快照没变也重投一次；`captureTimings`（只在 `recordsFeeds` 测试实例里记） |
| `HSTracker/RedDragon/RedDragonEngine.swift` | `legalActions(_:options:dropped:)` 报告丢掉的合法分支；连抽按剩余张数枚举、组合超上限置 `dropped`；舞动可达时友方目标逐个列出（`arrivalOrderMatters`） |
| `HSTracker/RedDragon/RedDragonSearch.swift` | `dropped` 计入 `pruned`（不再算穷举）；`RedDragonConfig.exact` 的 `maxChoiceCombinations = .max` |
| `HSTracker/RedDragon/RedDragonHint.swift` | `.provenNotLethal` 另要求牌库里没有未建模的牌 |
| `HSTracker/RedDragon/RedDragonReader.swift` | 场上随从的费用附魔按挂上的先后恢复成引擎附魔链（`boardCostEnchants`） |
| `HSTrackerTests/RedDragonLiveTests.swift`、`RedDragonTests.swift`、`RedDragonLiveReplayTests.swift`、`RedDragonFormulaTests.swift` | 各条的测试，见下 |
| `.gitignore`、`HSTracker.xcodeproj/project.pbxproj` | 第 7 条 |

### 1. P1 BLOCK 开着时旧结果仍能上屏

- 「旧局面作废」和「新快照可读」拆开：`parserBatchDidEnd` 里，这一批有新行、解析器还有未闭合的 BLOCK、上次投递的是局面（`.snapshot`），就在锁里把局面版本 +1、取走在算的取消标记，锁外 `cancel()`，再 `main.async` 调 `markStale`。每段（两次一致边界之间）只作废一次。
- `markStale`（主线程）：作废在算的、`lastSnapshot = nil`；屏上是 ready / computing 就发布「正在算 + 旧结论标过时」。在算的那次就算已经算完、提交排在主队列里，回来时版本对不上，丢弃。
- 到一致边界再拷：拷出来的和上次投递的一样（这段日志没改到相关实体），因为作废过，仍把它原样再投一次，重算后上屏。只有操作数变了的那份照旧不投（第二轮第 8 条）。
- 判据是「BLOCK 内有新行」，没细到「相关实体变了」。代价是我方回合每个顶层 BLOCK 多一次重算（结果相同）。回放里 g4 投递 92 次，第二轮没记这个数。
- 测试 `testOpenBlockLinesInvalidateInFlightResult`：
  - 先有结果 R；喂 A，主线程睡 1 s 让 A 算完、提交排进主队列。
  - 解析线程连调两次 `parserBatchDidEnd(idle: false)`，断言：A 被丢（`discardedComputations == 1`）、没上屏、phase 是 computing、R 标过时。
  - 边界上喂和 A 相同的快照，断言重算上屏、投递 3 次。
  - 对方回合时 BLOCK 内的新行不触发作废。

### 2. P1 `provenNotLethal` 不可靠

- **动作层报告丢掉的分支**：新重载 `legalActions(_:options:dropped:)`。下面三种情况置 `dropped = true`，搜索把它并进 `pruned`，走完也不算穷举：
  - 抽牌 / 发现组合超过 `maxChoiceCombinations`，被截断；
  - 手里有被跳过的过牌（`truncatedDraws` 那条检查：地图 / 垂钓之类）；
  - 手里有未建模的牌（`unmodeledCardId`）。
- **连抽按剩余张数枚举**：`choiceCombinations` 改成逐个槽位递归，每一支各自扣牌库 / 边牌。
  - 牌库两张同名牌时可以两次都抽到它，原来同一张牌不许重复选。
  - 这一刻只剩一种牌就直接拿、不占 choice，和引擎结算一致。
- **精确档解除上限**：`RedDragonConfig.exact` 设 `maxChoiceCombinations = .max`。
- **「不能斩」的口径收紧**：`.provenNotLethal` = 穷举、手牌费用没有推断的、牌库里没有未建模的牌、没被取消。手里的未建模牌 / 跳过的过牌已经通过上一点让结果不穷举，最多判 `.notFound`（「没搜到」，不出「单回合不够」，答题不判错）。
- 测试 `testConsecutiveDrawsEnumerateRemainingCopiesAndReportTruncation`（隐藏，牌库狐 ×2、鲨鱼 ×1）：
  - 组合正好是 `狐狐 / 狐鲨 / 鲨` 三种，打出 `狐狐` 后手里两只狐、牌库没狐；
  - 上限 2 时只给 2 种并置 `dropped`；`exact` 的上限是 `.max`；
  - 截断时搜索 `exhaustive == false`，不截断时 `true`。
- 回放和公式表的结论**都没变**：`[live]` 18 回合平均 0.21 s、最慢 1.22 s，四个斩杀回合全找到；公式表通过数仍为 80。

### 3. P2 同款友方目标在舞动可达时被合并

- `appendFriendlyTargets`：`boardOrderMatters || arrivalOrderMatters` 时逐个列出全部友方随从。`arrivalOrderMatters` = 手牌 / 边牌 / 牌库里有带 `.bounceAllFriendly` 的牌。
- 列出来之后由搜索的 `collapseEquivalentTargets` 执行后按「局面 + 场序偏序」去重。哈希在上场先后 ≠ 场位时会喂上场顺序（第二轮 A3），所以留下的上场先后不同就不会被并掉。
- 测试 `testIdenticalFriendlyTargetsStayDistinctWhenBounceAroundReachable`：
  - 局面：上场先后 A₁、B、C、A₂（两只一模一样的失调狐），手牌满（骨刺 + 舞动 + 8 杂）。
  - 两只狐都在 `legalActions` 里，`collapseEquivalentTargets` 后也都在。
  - 骨刺杀 A₁ 再舞动收回 鲨、刀油；杀 A₂ 收回 狐、鲨。
  - 对照：拿掉舞动后只列一个。

### 4. P2 读取层丢了场上随从的费用附魔

- `RDStateReader.boardCostEnchants`：场上随从的附魔（快照里按附魔实体编号排 = 挂上的先后）映射成引擎附魔链：
  - `ETC_079e`（舞动，本回合 1 费）→ `.set(1)`
  - `SCH_352e2`（药水复制品）→ `.set(1)`
  - `OG_291e`（暗影施法者复制品）→ `.set(1)`
  - `GBL_002e`（暗影步 −2）→ `.delta(-2)`
  - 其它（身材 buff 等）忽略。
  - 只看到管身材的 `SCH_352e`、没看到 `SCH_352e2` 时，按复制品在链首补 `.set(1)`。第二轮之前的口径就是这样，`testBoardTargetsResolveToRealEntities` 依赖它，第一次跑时它失败了，补上后通过。
- 测试 `testBoardCostEnchantsSurviveReplayAndShadowstep`：三条场上鲨鱼，暗影步收回后的费用：
  - 挂 `ETC_079e` 的 → 0；
  - 没附魔的 → 2；
  - 挂 `GBL_002e` 的 → 0。
- **待核**：这几个附魔在「场上 → 回手 → 再下场」之后还挂不挂着，本机日志没有足够样本。scratchpad 的 `step.py` 只找到 2 次「暗影步目标身上有附魔」：一次狐的 `TTN_858t2e1` 还在，一次 `DAL_714e` 没了。上面的映射按引擎模型（附魔随回手带走）和总指挥的判断写，没有日志直接证明舞动 `ETC_079e` 再下场后仍在。

### 5. P2 `rdExpectedSupplementMisses` 断言太松

- 表改成 `RDSupplementMiss(floor:note:)`。在表里的案例按下面四条断言：
  1. 搜索伤害 ≥ `floor`（现在能到的值：`t2-wuhu-10` 65、`t2-wuhui-04` 49），防止进一步退化；
  2. 本案例自己的线补齐后严格重放仍通过（线确实存在）；
  3. 「到目标」的断言照写，包在 `XCTExpectFailure` 里，说明里写「若这条预期失败没发生，说明搜到了，从 rdExpectedSupplementMisses 里删掉」。默认 strict，搜到时预期失败没发生，测试会报错；
  4. 表里有、却没走到补齐断言的条目（案例改名 / 不再缺件）报错。
- **第 2、3 条修完后两个漏线没有消失**：仍是 65/80、49/64，合计都撞 40 万状态闸门。

### 6. 快照成本

- `parserBatchDidEnd` 里 `feed(input(from: game))` 那一段（判菜单 / 套牌 / 模式 / 当前玩家 + 拷快照 + 和上次比较 + 投递）计时，只在测试实例（`recordsFeeds`）里记。
- 测试 `testSnapshotCaptureCostOnLogThread`：四局本牌组回放，一行一批，凡是在一致边界上拷了的批都计。Debug 构建：app 侧 -Onone，`RDGameSnapshot` 的比较在 -O 的包里。

  | 对局 | 拷了的批 | 平均 | 最大 | 投递 |
  |---|---|---|---|---|
  | g2 | 894 | 537 µs | 4.1 ms | 106 |
  | g3 | 843 | 453 µs | 4.3 ms | 105 |
  | g4 | 761 | 754 µs | 5.4 ms | 92 |
  | g5 | 768 | 657 µs | 5.1 ms | 98 |
  | 合计 | 3266 | 594 µs（中位 43 µs，p99 5.0 ms） | 5.4 ms | — |

- 中位 43 µs 是对方回合 / 起手前那些只判到 `.opponentTurn` / `.inactive` 的批；几百 µs 到 5 ms 的是我方回合真拷了快照的。线上一批是多行，拷的次数比回放少得多。**没有改成先比便宜字段**：耗时大头在拷快照本身（遍历实体、`getDeckState()`），先比便宜字段省不掉它；要省得知道这批改没改相关实体，那要在解析器里加钩子，超出本书。数字留给总指挥定要不要做。
- 开关关着：挂点第一个判断（锁里读 `enabledCache`）就 return，不拷、不计时。测试里关着的实例跑完 g4，`captureTimings` 和 `fedInputs` 都为空。

### 7. 小项

- `.gitignore` 加 `HSTracker/RedDragon/.swiftpm/`（`git check-ignore` 已确认生效）。
- `project.pbxproj`：`Package.swift`（`A01C`）、`RedDragonGameSnapshot.swift`（`A01D`）加文件引用并放进 `RedDragon` 分组，不进任何 build phase。第二轮风险 2 解决。

### 线程跳数（本轮，在第二轮的表上加一行）

| # | 线程 | 做什么 |
|---|---|---|
| 1′ | 解析线程 | 批末：有新行、BLOCK 开着、上次投递的是局面、本段还没作废 → 锁里版本 +1、取走取消标记；锁外取消，投 **`main.async`（标过时）** |
| 1″ | 主线程 `markStale` | 开关再查一次；作废、清 `lastSnapshot`；ready / computing 时发布「正在算 + 旧结论标过时」 |
| 1–4 | 同第二轮 | 一致边界上的快照没变也重投一次（本段作废过时） |

没有 `main.sync`。

### 构建 / 测试

- 过程中跑 `-only-testing`：
  - 红龙引擎 / Live / LiveReplay：第一次 `testBoardTargetsResolveToRealEntities` 失败（见第 4 条），修后通过。
  - Live + Formula：34 条，1 跳过，0 失败，Formula 24 s。
- 全套 `test -skip-testing:HSTrackerTests/LocalizationFormatTests`：**410 条，1 跳过，1 失败**，120.4 s。
  - 失败是既有的 `OfficialBuildTests.testHostAppIsRecognizedAsOfficial`（本地签名）。
  - 跳过的是 `testProductionConfigCostRelease`（Debug 下按设计跳过）。
  - 红龙类：引擎 44、Live 27、LiveReplay 8、Formula 7（1 跳过），全过。
- 没跑 `clean build`（`HearthMirror-version.txt` 没变，按规则增量）。

### 风险 / 任务外发现（本轮）

1. 第 4 条的附魔映射缺日志证据（见上）。错了的后果是重拍快照后费用估低，可能报出打不出来的线。
2. 第 1 条按「BLOCK 内有新行」作废，没细到相关实体：每个顶层 BLOCK 多一次结果相同的重算，线上搜索平均 0.21 s。
3. 第二轮风险 3（上游已提交的 ZoneReplay fixture 有真实 BattleTag）仍在，不是本书的文件，没动。
4. 第二轮风险 4（两个已知漏线要不要调束）仍待定；本轮确认它们和第 2、3 条无关。

## 第四轮（10-05，Codex 实跑最小复现的两条 P1）

实现者（Opus 子代理），工作区 `dev0923`（HEAD `463b8c4d`），未提交。中途被 API 限流打断一次，恢复后 `git diff` 核对过，没有临时代码。**与前几轮冲突处以本节为准**：`RDAction.attack` 多了 `choices`；只差操作数的快照不再在解析线程上丢；答题判卷改成按操作完成的边界配对。

### 改动文件（本轮）

| 文件 | 内容 |
|---|---|
| `HSTracker/RedDragon/RedDragonEngine.swift` | `.attack(attacker:defender:choices:)` + `RDAction.choices`；矿锄攻击后抽牌；英雄攻击按抽牌分叉；`combinations(of:)` 从打牌的组合枚举里抽出来共用；能交易时置 `dropped` |
| `HSTracker/RedDragon/RedDragonCards.swift` | `RDCards.tradeableCards` / `isTradeable` |
| `HSTracker/RedDragon/RedDragonState.swift` | 哈希在武器攻击后抽牌时多喂一项（矿锄和技能匕首同为 1/2） |
| `HSTracker/RedDragon/RedDragonSearch.swift` | 线签名带上攻击的抽牌；分支键 / 先验跟着新的 `.attack` |
| `HSTracker/RedDragon/RedDragonHint.swift` | `RDQuizState` 重写（见第 2 条）；`dependsOnDraw` 和步骤的 `picks` 也算攻击的抽牌 |
| `HSTracker/RedDragon/RedDragonAssistant.swift` | 只差操作数的快照照投；主线程见到只差操作数、屏上结论就是这个局面的，不重算、直接判卷；`commit` 带上快照 |
| `HSTrackerTests/RedDragonTests.swift`、`RedDragonLiveTests.swift`、`RedDragonLiveReplayTests.swift` | 新测试见下；三条答题测试改用快照驱动；跟着新 `.attack` 改模式匹配 |

### 1. 疾速矿锄攻击后的抽牌

- **证据**：10-01 原始 Power.log 第 4119 行（不在 fixture 里，fixture 是重截的）。武器耐久已经用满（`DAMAGE` 到 2）之后，矿锄的 TRIGGER 块照样从牌库抽了一张，而且这个块排在攻击块之后、是单独一个顶层块。g2 fixture 第 5700–5824 行同样是「ATTACK → 矿锄 TRIGGER 抽牌 → DEATHS 销毁武器 → 计数 +1」。
- **引擎**：
  - `resolveAttack` 结算完伤害、清掉死亡随从之后，武器带 `drawOnHeroAttack` 时按 `.draw(.any, 1)` 抽一张，口径和行骗 / 帷幕的抽牌相同：牌库只剩一种牌就直接拿，多种就要一个 choice，手牌满就烧掉。
  - 耐久只剩 1 的矿锄打完也抽。不是矿锄的攻击带了 choices 时判非法。
- **合法动作**：英雄攻击按牌库剩余逐种列出抽牌分支，走 `combinations(of:)`，超上限照样置 `dropped`。
- **哈希**：技能匕首和矿锄都是 1/2，原来哈希只喂攻击力和耐久，两种局面会被去重成一个。现在只在武器攻击后会抽牌时多喂一项，其它局面的哈希不变。
- **展示 / 判定**：`dependsOnDraw` 改成看 `RDAction.choices`（打牌和攻击的都算），所以靠矿锄抽到关键牌的线判 `.lethalIfDraw`；牌库只剩一种牌时抽什么是确定的，仍判 `.lethal`。步骤的 `picks` 也列出攻击抽到的牌。
- **测试 `testQuickPickDrawAfterHeroAttackIsResolvedAndSearched`**（Codex 的复现）：
  - 局面：7 费，场上一只失调的阿莱，装矿锄，牌库只剩暗影步，对手 9 血。精确档和默认档都判斩杀，线严格重放到 9，`dependsOnDraw == false`。
  - 引擎层：攻击后抽到暗影步；技能匕首攻击不抽；两者哈希不同；耐久 1 的矿锄也抽。
  - 牌库两种牌：英雄攻击列出两个抽牌分支，斩杀线 `dependsOnDraw == true`。

### 1′. 排查「不是打出卡牌」触发的效果

本牌组 25 个 id 加技能，逐个对了卡表文本（`downloaded-frameworks/cards/251952/CardDefs.xml` 的 enUS `CARDTEXT` 和关键字 tag）：

| 牌 | 非打牌触发 | 处理 |
|---|---|---|
| 疾速矿锄 `DEEP_014` | 英雄攻击后抽一张 | 本轮建模（上一条） |
| 黑水弯刀 `DED_004` | **可交易**：1 费洗回牌库、抽一张，交易后给手里一张法术减 1 | 不建模，计入遗漏：手里有它、可用法力 ≥ 1、牌库不空时 `legalActions` 置 `dropped`，搜索不算穷举，不出「证明不能斩」。测试 `testTradeableCardInHandMakesSearchNonExhaustive` |
| 挖掘宝藏 `TOY_510` | 抽到海盗再给一张币 | 本牌组的随从都不是海盗；牌库里的未建模牌已经让 `.provenNotLethal` 不成立（第三轮第 2 条），不另处理 |
| 闪避 `LOOT_214` | 奥秘：我方英雄受伤后免疫 | 不增减我方伤害，不处理 |
| 殒命暗影 | 施法后变形 | 已建模 |
| 技能 匕首精通 | 装 1/2 匕首 | 已建模，不抽牌 |

没有亡语牌，也没有别的武器 / 技能 / 奥秘会抽牌、生成或减费。

### 2. 攻击计数晚到，打错了仍显示绿色

- **日志**：出牌时 `NUM_OPTIONS_PLAYED_THIS_TURN` 先于 PLAY 块在顶层 +1（g2 第 16164 → 16184 行）。攻击时它在 ATTACK、矿锄 TRIGGER、DEATHS 几个块都结束之后才在顶层 +1（g2 第 4078 行到 2、第 5824 行到 1）。第三轮在解析线程上丢掉「只差计数」的快照，又用同一计数的新结论覆盖「上一次结论」，于是攻击那一步判不到，或者拿进行中的结论当操作之前的结论。
- **解析线程**：只差操作数的快照照投，`onlyOptionCountChanged` 只留作判断工具。
- **主线程 `submit`**：只差操作数、屏上是 ready 且不过时的结论就是这个局面的 → 不重算，`actionsTaken` 改成新计数，拿现有结论判卷、发布。
- **`RDQuizState`** 记 `settled`（最近一个已完成的局面）、`baseline`（它的结论 = 下一步操作之前的结论）、`lastOp`（上一步操作之前的结论和判定）、`pending`。新结论到了按下表处理：

  | 情形 | 处理 |
  |---|---|
  | 计数涨了、局面（不看计数）和 `settled` 相同 | 出牌刚开始，等 |
  | 计数涨了、局面变了 | 这一步完成：用 `baseline` 判，局面记成新的 `settled` |
  | 计数没涨、已在 `pending` | 等 |
  | 计数没涨，但英雄 / 场上随从本回合攻击次数、出牌数涨了，或技能用掉了 | 攻击 / 技能进行中，置 `pending`，**不覆盖** `baseline` |
  | 其余（出牌后的死亡结算、回合开始的抽牌、同局面重算） | 更新 `settled` / `baseline`；本回合判过一步的，用同一个「操作之前」重判这一步 |

  判卷规则不变：现在能斩 → 绿；操作之前能斩（或已经判红）、现在证明不能斩 → 红；其余不判。
- **测试**：
  - `testQuizPairsAttackWithLateOptionCount`（纯状态机）：攻击后旧计数的局面 → `pending`、`baseline` 仍是「能斩」；只差计数那份 → 判红。出牌后的死亡结算 → 同一步重判成红。
  - `testAssistantJudgesAttackWhenLateCountArrives`（Assistant 全程）：上一步绿 → 攻击后（旧计数）证明不能斩，不判红 → 计数晚到，判红，且 `scheduledComputations` 没增加（没重算）。
  - `testAttackOptionCountArrivesLateG2`（g2 回放，一行一批）。两个窗口里，计数那一行之前的那份都是「攻击已结算、计数没涨」，判卷 `pending`、没判；计数那一行判这一步、`lastOp.before` = 攻击之前的结论。两次攻击前后的真实结论都不是「能斩」（第一次 `provenNotLethal` → `provenNotLethal`，第二次 `notFound` → `notFound`），判不出颜色，所以在同一串真实局面上换成 Codex 复现的结论（上一步绿、攻击前能斩、攻击后证明不能斩）再走一遍：攻击中 `baseline` 不被覆盖，第 4078 / 5824 行判红。

    | 行 | 计数 | 英雄攻击 | 状态 |
    |---|---|---|---|
    | 3727 | 1 | 0 | 已完成 |
    | 3908 / 4028 / 4055 / 4075 | 1 | 1 | `pending` |
    | **4078** | **2** | 1 | 判这一步 |
    | 5514 / 5567 | 0 | 0 | 回合开始 |
    | 5740 / 5772 / 5808 / 5819 | 0 | 1 | `pending` |
    | **5824** | **1** | 1 | 判这一步 |
- 三条旧答题测试（`testQuizMarks` / `testQuizNeverMarksWrongWithoutProof` / `testQuizActionsAreMonotonic`）改成快照驱动，断言不变；出牌都按「计数先涨、场面后变」两步喂，中间那步断言不判。

### 线程跳数

没有新的跳。只差操作数的快照走第二轮表里的第 1 跳 `main.async` 到 `submit`，命中快路径时在同一个 main block 里写 `quizState` 和 `hint`、不排后台任务。没有 `main.sync`。

### 构建 / 测试

- 过程中跑红龙四类。第一次 `testAttackOptionCountArrivesLateG2` 失败：回放 helper 没读 `PlayerName` 行，认不出我方玩家，一份快照都没拷到。补上后通过。同一次运行里 `testHookOnReplayFeedsOnlyAtConsistentPoints` 进程意外退出一次，xcodebuild 自动重启；单独跑、之后两次整类跑都通过，`DiagnosticReports` 里没有新的崩溃报告，原因不明。
- 红龙四类：Formula 7（1 跳过）、LiveReplay 9、Live 29、引擎 46，共 91 条，0 失败。
  - 回放 18 回合结论和第三轮逐行相同，平均 0.24 s、最慢 1.29 s，四个斩杀回合全找到。
  - 公式表仍通过 80，两个已知漏线仍是 65/80、49/64。
  - 快照成本合计平均 635 µs、最大 5.9 ms（只差计数的那份现在也投，g2 / g3 各多投 2–3 次）。
- 全套 `test -skip-testing:HSTrackerTests/LocalizationFormatTests`：**415 条，1 跳过，1 失败**，129.9 s。失败是既有的 `OfficialBuildTests.testHostAppIsRecognizedAsOfficial`，跳过的是 `testProductionConfigCostRelease`。

### 风险 / 任务外发现（本轮）

1. `pending` 期间（攻击结算到计数涨之间，日志里同一时间戳、几十 ms）屏上仍是上一步的判定。计数一到就改判。
2. 「进行中」只认攻击次数、出牌数、技能三种信号。如果出了别的、计数在结算之后才涨的操作，会被当成同一局面的后续，用旧的「操作之前」重判。本牌组目前没有这种操作。
3. 出牌后紧跟的死亡结算会把同一步重判一次，所以判定可能在出牌后的几十 ms 内从绿变红或反过来。按设计判的是结算完的局面。
4. 交易只计入遗漏、没建模。手里有黑水弯刀、有 1 费、牌库不空时，所有「不能斩」都只到 `.notFound`。
5. **任务外**：搜索不看对手奥秘数（`opponent.secretCount` 只读进状态，`RedDragonHint` 不用它）。对手有寒冰屏障一类奥秘时照样判「可斩杀」，可能误报绿。没改。

## 第五轮（10-05，Codex 核第四轮：1 条 P1、1 条 P2）

实现者（Opus 子代理），工作区 `dev0923`（HEAD `463b8c4d`），未提交。开工前 `git diff` 核对过，没有临时代码。**与第四轮冲突处以本节为准**：「操作已开始」的判据、`pending` 的解除条件、`dependsOnDraw` 的口径都变了。

### 改动文件（本轮）

| 文件 | 内容 |
|---|---|
| `HSTracker/RedDragon/RedDragonGameSnapshot.swift` | 新字段 `minionsAttackedThisTurn`（默认 0） |
| `HSTracker/RedDragon/RedDragonSnapshot.swift` | 读玩家实体 `NUM_FRIENDLY_MINIONS_THAT_ATTACKED_THIS_TURN` |
| `HSTracker/RedDragon/RedDragonHint.swift` | `RDQuizState` 改用 `RDOpCounters` 判「操作已开始」，`pending` 换成带解除条件的 `pendingOp`（`RDQuizPending`），`lastOp` 改成 `RDQuizOp`；`dependsOnDraw` 改成逐个替换抽牌结果再重放 |
| `HSTracker/RedDragon/RedDragonEngine.swift` | `RDAction.replacingChoices`、`RDEngine.choiceVariants(for:in:)` |
| `HSTrackerTests/RedDragonLiveTests.swift`、`RedDragonTests.swift`、`RedDragonLiveReplayTests.swift` | 新测试见下；回放测试跟着新的 `RDQuizState` 构造器改 |

### P1：攻击随从撞死时认不出「操作已开始」

- **原因**：第四轮按「仍在场随从的 `attacksThisTurn`」认随从攻击。攻击随从撞死后不在 `board` 里，信号丢了：死亡后的局面被当成同一局面的后续，覆盖了攻击前的结论；计数涨 1 时这份局面又只差计数，被当成「出牌开始」跳过。
- **新判据**：只认**操作计数器** `RDOpCounters`，四个数里有一个比 `settled` 大就算操作已开始：
  - 英雄 `NUM_ATTACKS_THIS_TURN`；
  - 玩家实体 `NUM_FRIENDLY_MINIONS_THAT_ATTACKED_THIS_TURN`；
  - `NUM_CARDS_PLAYED_THIS_TURN`；
  - 英雄技能 `EXHAUSTED`。
- **证据**：10-04 16:47 那局原始 Power.log 第 69815 行起（不在 fixture 里）。我方 E.T.C. 攻击时，这个玩家 tag 在 ATTACK 块开头就 +1（与 `PROPOSED_ATTACKER` 同一段），攻击者离场后不回退。英雄攻击的计数在英雄实体上，英雄不会离场。
- **为什么不会把非操作的场面变化当成操作**：这四个数只在玩家出牌、攻击、用技能时涨。回合开始的效果、死亡结算、亡语 / 扳机连锁清场、随从被移走都不动它们，场面增减本身不参与判断。测试 `testQuizNonOperationBoardChangeIsNotPending`：移走随从和手牌、计数器不变 → 不进 pending，更新「操作之前」。
- **`pending` 的解除条件**（不会卡死整回合）：
  1. 操作数 `NUM_OPTIONS_PLAYED_THIS_TURN` 涨了 → 这一步完成，判卷；
  2. 换回合 → 清零；
  3. pending 期间计数器**又**涨了（上一个操作计数没涨就结束了，下一个已经开始）→ 用 pending 期间最后一份局面和结论把上一步判完，然后进入新的 pending；
  4. 计数器比 pending 开始时小（回合内只增不减，不该发生）→ 解除，当前局面当作 `settled`。

  非操作的变化根本不进 pending，所以「回合开始移走随从、计数之后不涨」不会出现卡住的 pending。测试 `testQuizPendingReleases` 覆盖条件 2、3、4，条件 1 在下面的回归用例里。
- **回归用例** `testQuizAttackerDiesBeforeLateCount`（Codex 复现）：
  - 上一步判绿、攻击前能斩。狐撞死后的局面先算完（攻击者离场、对面随从也没了、玩家攻击计数 1、操作数没涨）→ `pending`，`baseline` 仍是「能斩」。
  - 操作数后到 → `lastActions` 变成 1、判红。
  - 另断言快照读的就是那个玩家 tag。
- g2 回放（`testAttackOptionCountArrivesLateG2`）的轨迹和第四轮逐行相同。

### P2：致死之后的抽牌被判「依赖抽牌」

- **原因**：第四轮的 `dependsOnDraw` 只要线里出现随机抽牌就算依赖。Codex 复现：对手 1 血，矿锄攻击本身就致死，牌库两种牌，两条斩杀线都被判依赖抽牌，结论降成「可斩杀（需抽到）」。
- **新口径**：线里每一步带随机抽牌的（打牌、矿锄攻击），把这一步的抽牌换成每一种可能的结果，发现的选择不动；结果由 `RDEngine.choiceVariants` 给出，超过 256 种或认不出这一步时按「依赖」算。剩下的步骤原样重放：
  - 每种结果在这一步结算后已经致死，或在剩下的步骤里打到致死 → 这次抽牌不降低确定性；
  - 有一种结果打不出剩下的步骤（抽到的牌后面要打，换一张就身份 / 编号对不上）或打不到致死 → 依赖抽牌。
  - 每一步单独替换，其余步骤保持原样。换了之后后面的抽牌对不上的，按依赖算（保守）。
- **测试** `testDrawAfterLethalOrUnusedDoesNotMakeLineDrawDependent`：
  1. 对手 1 血、矿锄打脸致死：抽到暗影步或币的两条线都不依赖；搜索给出的所有斩杀线都不依赖。
  2. 暗影步本来就在手：矿锄打脸（抽到的牌没用上）→ 暗影步收回阿莱 → 再下阿莱，线严格重放到 9，不依赖。
  3. 第四轮那个局面（要打抽到的暗影步）仍判依赖。

### 构建 / 测试

- 过程中跑红龙四类：Formula 7（1 跳过）、LiveReplay 9、Live 32、引擎 47，共 95 条，0 失败。
  - 回放 18 回合结论和第四轮逐行相同，平均 0.21 s、最慢 1.18 s。
  - 公式表仍通过 80。
- 全套 `test -skip-testing:HSTrackerTests/LocalizationFormatTests`：**419 条，1 跳过，1 失败**，119.1 s。失败是既有的 `OfficialBuildTests.testHostAppIsRecognizedAsOfficial`，跳过的是 `testProductionConfigCostRelease`。

### 风险 / 任务外发现（本轮）

1. `NUM_FRIENDLY_MINIONS_THAT_ATTACKED_THIS_TURN` 的口径只看了一局原始日志里的一次随从攻击（我方随从在 fixture 里几乎不攻击）。若某种攻击不动它（比如攻击前就被奥秘打断），那次攻击会被当成非操作变化；计数随后涨时只差计数会被跳过，直到下一步完成才判。
2. 条件 3 判完的那一步用的是 pending 期间最后一份局面；如果上一个操作的计数其实只是来得很晚（晚于下一个操作开始），判卷会早一步。
3. `dependsOnDraw` 每一步单独替换，没有穷举多次抽牌的组合；多次随机抽牌都没用上的线可能被保守地判成依赖。

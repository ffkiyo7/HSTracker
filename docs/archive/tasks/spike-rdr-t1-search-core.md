# Spike RDR / T1 — 红龙贼搜索核心（无 UI）

先读 `docs/tasks/_common.md`。本任务不属于 `docs/PLAN.md` 的任何 Phase，背景与全部已决事项在：

- `docs/research/red-dragon-rogue-spike.md` —— 需求、边界、已决（第六节）、下一步（第九节）
- `docs/research/red-dragon-card-model.md` —— 24 张牌的当前文本与建模，**G 节的 G1~G3 必须落实**，末尾带 ✅ 的待核项已定
- `HSTrackerTests/Fixtures/RedDragon/formulas.json` —— 社区公式表转录成的 75 行 fixture；`sim.py` 是只算法力的参考推演器，**fixture 行 → 初始状态的映射约定以它的 `seed_for` / `run_row` 为准**

## 要做出什么

一个纯 Swift 模块，输入一个回合的局面，输出这回合能打出的最大伤害与一条**可重放**的动作序列。不接 `Game`，不画 UI，不开线程。

```
输入  RedDragonState：手牌（每张：卡 + 当前费用 + 附魔）、我方场面（含召唤失调、1/1 复制体标记、左→右顺序）、
      敌方场面 + 英雄血 / 护甲、当前法力 / 水晶上限、本回合已出牌数、减费层、牌库剩余、边牌剩余
输出  RedDragonResult：
      maxDamage / 对方有效血量 / 是否斩杀
      chosenLine：动作序列（含目标）+ difficulty。**有解时选难度最低的斩杀线**（并列取伤害冗余最大的）；
                  无解时选伤害最高的线
      lethalLines：所有找到的斩杀线（各带 damage + difficulty），去重后按难度升序，给 T2 做揭示策略用；上限条数可配
      branches：抽牌分叉时每种结果各一条（伤害 + 序列 + 难度）
      missingPieces：无解时，牌库剩余里哪张进手就能斩杀（可空）
      termination：.reachedUpperBound / .exhausted / .budgetExceeded
      cpuTime
```

### 难度（用户 2026-09-11 提的需求）

原表里的公式实战难度差很多：有的三五步顺手就打出来，有的计算量大、顺序卡手。T2 的揭示策略要靠它：
**当前能用的最简单斩杀线属于「基础」时，不允许开兜底引导，只给能不能斩的提示；只有难线可用时才默认开引导。**
所以 T1 要给每条线一个**确定性的难度分**，至少由这三项组成（权重做成常量，T2 再调）：

1. **操作数**：动作序列长度（含攻击、发现选择）。
2. **牛的用量**：这条线里 E.T.C. 一共要从边牌拿几张（拿 1 张 vs 3 张全拿）。
3. **与惯用顺序的偏离**：大多数公式的起手是「鱼 → 狐 → 刀 → 暗（刀）→ 牛」。一条线的起手序列与这个模板的编辑距离越大越难（例如「先下狐再下鱼也行」这种打破定势的线必定更难记）。模板做成常量，别写死在算法里。

报告里给出 75 行 fixture 各自的难度分分布，并说明你建议的「基础 / 进阶 / 困难」两个阈值落在哪，让用户按实战感觉调。

## 已决（见两份 research 文档，此处只列对实现有直接约束的）

| 项 | 决定 |
|---|---|
| 范围 | 只算**本回合**。状态 = 手牌 + 我方场面 + 敌方场面 |
| 动作集合 | 打牌（含目标选择，**对自己随从施放骨刺 / 暗影步是合法且常用的**）、随从攻击、英雄攻击（武器）、E.T.C. 发现（边牌三选一枚举）、抽牌分叉 |
| 抽牌 | 行骗 / 潜伏帷幕 / 挖掘宝藏：从牌库剩余枚举每种结果各算一条；剩余 ≤ 抽取数时折入主线不分叉。**异教地图 / 垂钓时光：当「花费 + 抽 1 张未知」截断，不展开** |
| 殒命暗影 | 复制品费用 = 被复制法术的印刷费，**支持抄 3 费的舞动**（G1） |
| 减费层 | 跨舞动「阶段」不清空（G2）；刀油被鲨鱼双触发 = 两层各 2 槽；0 费牌照样吃槽；狐人的层只被连击牌吃 |
| 晦鳞回费 | `min(cur + 2, maxMana)`，`maxMana` = 永久水晶，**币的临时水晶不算** |
| 鲨鱼 | 只翻倍**随从**的战吼 / 连击 |
| 步 × 舞动 | 后挂的附魔在上层：先舞动后步 = 0，先步后舞动 = 1 |
| 手牌满 | 舞动弹回时**最右侧随从被烧**；药水 / 暗影施法者的复制进不来即烧 |
| 致聋术 | 沉默去掉 1/1 附魔，复制体变回原身材；能打死的只有狐人老千 |
| 缺件 | 无解时，对牌库剩余的每种 combo 零件试「加进手牌再算」，能跨过有效血量的列出 |
| 多条线可用 | **按最简单的那条判定 / 处理**（难度最低），不是伤害最高的；无解时才取伤害最高 |
| 卡牌识别 | 按 dbfId 或 id 集合（三张是 Core 版 id），不写死单个字符串 |

## 硬约束

- **全部新代码放 `HSTracker/RedDragon/` 目录**。不改 `Game.swift` / `Player.swift` / `Entity.swift` / 任何 UI 文件 / `SizeHelper`。
- **卡牌效果做成数据表**（不可变的卡定义 + 效果枚举），不写成散在引擎里的 `if cardId ==`。状态是值语义 `struct`，卡表 `static let` 共享。
- **同步、单线程、纯函数**：同一输入两次调用结果逐字节相同。预算按 **CPU 时间**（`clock_gettime(CLOCK_THREAD_CPUTIME_ID, …)` 或 `thread_info`），不按墙钟；超时返回已找到的最好结果并标 `.budgetExceeded`。线程与去抖是 T2 的事。
- **路径重放校验是 P0**：任何返回给调用方的序列，返回前必须由同一套规则引擎从初始状态**重放一遍**，费用 / 格子 / 手牌数 / 目标合法性全过；过不了就不返回这条线。
- **先做精确搜索**（状态哈希去重 + 剪枝）。只有在 fixture 上超预算时才上束搜索，且要在报告里给出数据说明为什么。
- 不复制 `zcr0701/hearthstone-selfplay` 的任何代码或卡表。
- 14 个没有常量的 cardId 补进 `HSTracker/Logging/CardIds/` 对应文件（只加常量，别动别的）。`Neutral.swift` 里已有的 `Alexstrasza = "EX1_561"` 是另一张牌，别复用。

## 允许修改的文件

- 新增 `HSTracker/RedDragon/*.swift`，**手工登记进 `project.pbxproj`**（4 处，见 `AGENTS.md`「构建」）
- 新增 `HSTrackerTests/RedDragonTests.swift`；把 `HSTrackerTests/Fixtures/RedDragon/formulas.json` 登记为测试 target 的资源。**`formulas.json` 与 `sim.py` 内容不改**——发现 fixture 有错写进报告
- `HSTracker/Logging/CardIds/Rogue.swift` / `Neutral.swift`（只加常量）
- `HSTracker.xcodeproj/project.pbxproj`（只加登记）

## 验收

1. Debug build `BUILD SUCCEEDED`；`xcodebuild … test` 通过，原有 50 个测试不动。
2. **卡库测试**：24 个 cardId 经 `Cards.by(cardId:)` 都能查到且名字与 card-model 一致。
3. **fixture 重放测试**：对每个 `steps` 完整的行，把表里的序列喂给规则引擎逐步执行，每步 `manaAfter` 一致、最终伤害 = `damage`。card-model G 节「原表的错」列出的行**预期失败**，在测试里显式列成白名单并写明原因；白名单之外不许有失败。
4. **搜索测试**：对重放通过的每一行，从同一初始状态跑搜索，`maxDamage ≥ damage`，且 `chosenLine` 与 `lethalLines` 每条都重放通过。
5. **确定性测试**：同一输入跑两次，结果相等（含 `lethalLines` 的顺序与难度分）。
5b. **难度测试**：三条手写断言——同一局面下更长的线难度更高；用到 3 张边牌的线比用 1 张的高；起手「狐 → 鱼 → …」比「鱼 → 狐 → …」高。
6. **规则边界测试**（手写局面，各一条）：第 8 个随从下不去；舞动弹回手牌满时烧最右侧；晦鳞回费不超过水晶上限、币不抬上限；致聋术打不死 1/1 阿莱复制体、能打死狐；先舞动后步 = 0 / 先步后舞动 = 1；刀油的层跨舞动保留。
7. **性能**：每行的 CPU 时间列进报告；目标单行 ≤ 1 s。超的行单独列出并说明。
8. 报告里写清：模块文件清单与各自职责一段话；搜索策略与剪枝；`missingPieces` 的预算怎么定；fixture 里你认为转录或原表有错的行；card-model 里你认为写错或写漏的规则。

## 汇报

结果写进本文件末尾「执行结果」一节，格式照 `docs/tasks/phase7-t1-session-recap-window.md`。
**不要 commit、不要动 `docs/PLAN.md` / `docs/PROGRESS.md` / 两份 research 文档**。

## 执行结果（2026-09-11）

- 新增 `HSTracker/RedDragon/` 六个文件，已按 4 处（`PBXBuildFile` / `PBXFileReference` / 新建 `RedDragon` group 挂进 `HSTracker` / `Sources` phase）登记进 `project.pbxproj`：
  - `RedDragonCards.swift` —— 卡牌效果数据表：`RDCard`（23 张牌 + 两个公式表占位）、`enum RDEffect`、不可变的 `RDCardDef` 静态数组（cardId 集合 / dbfId / 印刷费 / 身材 / 龙 / 连击 / 目标作用域 / 效果 / 是否被鲨鱼翻倍 / 边牌 / 牌库张数）。引擎只读这张表，全模块没有一处 `if cardId ==`。
  - `RedDragonState.swift` —— 全部值语义 `struct`：`RDState` / `RDHandCard` / `RDBoardMinion` / `RDDiscountLayer` / `RDDeck` / `RDOpponent`，费用结算（`effBase = set 覆盖 + Σdelta`，再减匹配层）与确定性指纹 `canonicalHash()`（自写 FNV 变体，不用随机种子的 `Hasher`，跨进程稳定）。
  - `RedDragonEngine.swift` —— 纯函数 `apply(action:to:options:)` + `legalActions`。打牌、目标合法性、7 格 / 10 手牌、减费层消耗、鲨鱼双触发、殒命暗影镜像、发现 / 抽牌的确定化分支、平 A / 英雄技能全在这里。
  - `RedDragonReplay.swift` —— 路径重放校验（P0）：`run` 逐步重放并给出每步剩余法力，`validate` 过不了就返回 nil。
  - `RedDragonDifficulty.swift` —— 难度分：权重常量 + 惯用起手模板 + 编辑距离 + 三档阈值。
  - `RedDragonSearch.swift` —— `RedDragonConfig` / `RedDragonResult` / `RedDragonLine` 与束搜索本体，CPU 预算走 `clock_gettime(CLOCK_THREAD_CPUTIME_ID)`。
- 新增 `HSTrackerTests/RedDragonTests.swift`（18 个用例），`HSTrackerTests/Fixtures/RedDragon/formulas.json` 登记成测试 target 的资源。`formulas.json` / `sim.py` 一个字节没动。
- `CardIds/Rogue.swift` 加 13 个常量（`ShadowOfDemise` / `ShadowOfDemiseCore` / `GoneFishin` / `Deafen` / `BlackwaterCutlass` / `CultistMap` / `FoxyFraudCore` / `SerratedBoneSpike` / `ScabbsCutterbutter` / `SpiritOfTheShark` / `PotionOfIllusion` / `MathiasShaw`，以及 `NonCollectible` 的 `DaggerMasteryMathiasShaw`），`CardIds/Neutral.swift` 加 2 个（`DarkscaleBroodmother` / `AlexstraszaTheLifeBinder`，旁边写了一行「与 `EX1_561` 是两张牌」）。别的一行没动。

### 验收

- `xcodebuild … build`：`** BUILD SUCCEEDED **`
- `xcodebuild … test`：`** TEST SUCCEEDED **`，`Executed 68 tests, with 0 failures (0 unexpected) in 161.948 seconds`（原有 50 + 新增 18）
- 重放：**通过 52 / 失败 22（全部在白名单）/ 跳过 1**（`t2-wudao-01` 没有费用列）。白名单之外零失败；白名单里若有行「变成通过了」测试也会红，防止它烂在那里。
- 搜索：重放通过且有伤害列的 **49 行全部 `maxDamage ≥ 表中伤害`**，`chosenLine` 与每条 `lethalLines` 都过了重放校验。

### 搜索策略与剪枝

**精确搜索先做了，数据说明它不够用。** 把束宽设成无穷、动作不截断（= 带状态哈希去重的分层穷举），**Release 构建 5s 预算**下 48 行只到**深度 8~10**、展开 300 万状态，**43 行拿不到表中伤害**；而公式表的线深度是 14~30。所以上束搜索，配置与理由：

| 项 | 值 | 为什么 |
|---|---|---|
| 分层束搜索 | 束宽 1500 | 层内全局状态哈希去重；再窄（600 / 800 / 1000）分别漏 15 / 8 / 4 行 |
| 每节点动作上限 | 14 | 先验由卡表推出（打脸伤害 > 鲨鱼光环 > 边牌发现 > 回费 > 复制 > 减费 > 弹回 > 抽牌 > 杂牌），不写死单张牌 |
| 等价目标合并 | 有 | 同卡、同身材、同附魔的两个随从指谁都一样 —— 这是**真等价**不是启发式，7 格场面的目标展开从 7 条压到 3~4 条 |
| 伤害分桶保底 | 每桶 ≥ `width/(3×桶数)` | 只取全局 Top-K 会把「龙数低、还在蓄力」的桶整个砍掉（win 项目 V1.1 的原漏解）。实测去掉这条，48 组大面积只到 17 伤 |
| **两条正交排序分** | 共识占一半、蓄力占一半 | 单一分数要么急着打龙（长线被砍，27 行失败）、要么只蓄力不转化（深度 30 还是 1 伤，26 行失败）。两条并存后降到 0 行失败 |
| 斩杀截断 | 最浅一层出现斩杀即停 | 同层操作数相同，正是「最简单的那条」所在的层；`lethalLines` 取这一层的全部，按难度升序 |
| 预算 | CPU 时间，`CLOCK_THREAD_CPUTIME_ID` | 另配 `maxStatesExpanded`，因为**被 CPU 预算截断时结果依赖机器负载**，确定性要靠一个可复现的闸门 |

**没做成硬剪枝的一处（重要）**：card-model F 节的上界 `8 × S × A` **不是真上界** —— 幻觉药水 / 暗影施法者能无限造复制，「还能触发几次阿莱」没有闭式上限。实测拿 `UB < 斩杀线` 当硬剪枝，48 / 64 线会被剪掉（15 行失败，且大量提前 `exhausted`）。现在它只进排序分，不参与剪枝。

`missingPieces` 的预算：单列 `missingPieceBudget`（默认 0.4s），**只在主搜索无解时才跑**，按牌库剩余的种类数平分、每种至少 20ms，束宽压到 300，超时就停。理由是缺件是「多这一张能不能斩」的粗判，不能反过来吃掉主线的预算。

### CPU 时间

| 构建 | 平均 | 最慢 | 超 1s 的行 |
|---|---|---|---|
| Debug（`-Onone`，测试宿主） | 3.185s | 6.951s（`t1-48p-07`，80 伤 / 26.3 万状态 / 深度 30） | 49 / 49 |
| Release（`-O`，同一份代码同一组参数） | **0.289s** | **0.619s** | **0 / 49** |

**49 行全部超 1s 的唯一原因是测试跑在 Debug 宿主上**，同一份代码 `-O` 快约 11 倍，目标「单行 ≤ 1s」在 Release 下达成（最慢 0.62s）。生产路径（T2）跑 Release，默认预算保持 1s；测试里把预算放到 12s 并在代码注释里写明了这条。Release 数字取自 scratchpad 里的独立基准（`swiftc -O` 直接编译 `HSTracker/RedDragon/*.swift` + 同一套 seed），不入库。

### 难度分分布与建议阈值

52 条可重放线：**min 13 / p25 26 / 中位 29 / p75 33 / max 38**。权重是「操作数 ×1 + 边牌张数 ×3 + 起手偏离 ×4」，模板 `鱼 → 狐 → 刀 → 暗 → 牛`。

建议阈值取 p25 / p75：**基础 ≤ 26，进阶 27~33，困难 > 33**（已写进 `RDDifficulty.basicThreshold / advancedThreshold`）。落到具体行：

- 基础（13~26）：`t1-32-01`(20)、`t1-48-01`(21)、`t1-48-03a`/`t1-48-13a/b`(23)、`t1-16-01`(23)、三条预启动、`t1-32-02/03`(26)、`t2-chou-01`(26)
- 进阶（27~33）：`t1-32-05`(27)、`t1-48-04`(28)、`t1-48-06a`/`t1-48-07`(29)、`t1-48p-03`(31)、`t2-wuhu-04a/05/06`(32)、`t1-48-05/09/10`(33)
- 困难（34~38）：`t1-48p-05`(34)、`t1-48p-06/07`(35)、`t1-48p-01`(36)、`t2-wuhu-09`(36)、`t2-wuhu-10/11`(37)、`t2-wuhu-02`(38)

分档的实战含义正好对上：32 公式和最简的 48 落在基础，48+ / 80 和无狐长线落在困难。**照这个阈值，T2 的规则「最简单可用线是基础 → 不许升到 L2」会在标准 32/48 局面下关掉兜底引导**，这应该就是想要的效果；数不合手直接改这两个常量。

### 重放白名单（22 行，全部是原表或转录的错）

**① 彗逆序系统性算法错，18 行**（`t2-huqs-01/02/03/04a/04b/05`、`t2-daoqs-01/02/03/04a/04b/05`、`t2-wuhui2-01/02`、`t2-16-01a/01b`、`t2-pre-01/02`）：把第一张刀油的连击按「下两张各 -4」算，可鲨鱼此时还没下场。按正确规则每条多付 4 费，6~8 费的启动打不出来（`t2-daoqs-*` 直接在第 1 步 `notEnoughMana`）。
⚠️ **card-model G 节说是 16 行，实际是 18 行**：刀起手是 6 行不是 5 行（`t2-daoqs-02` 也在内），预启动是 2 行不是 1 行（`t2-pre-01` 和 `t2-pre-02`，前者的 `expandedLines` 自己就标了「按表的首刀 -4 复现」）。

**② 单格笔误，4 行**：

| 行 | 现象 | 依据 |
|---|---|---|
| `t1-48-02` | 第 7 步「晦5」实得 4 | 4 水晶时复原到不了 5；水晶列应为 5（fixture `inference` 已核高清图） |
| `t1-48-06b` | 第 11 步「晦5」实得 4 | 合并单元格，4 水晶那一半照抄了 5 水晶的二阶段 |
| `t1-48-11` | 二阶段起手「鱼0」实得 1 | fixture `inference`；旁证 `t1-48p-01` 同一阶段写的就是「鱼1」 |
| `t1-48p-08` | 三阶段起手「鱼3」实得 2 | 二阶段「殒舞3」漏了连字符，应是单 token「殒-舞3」；拆成两个 token 时手里没有第二张舞 |

`t1-48p-08` 这条 **card-model G 节的错表里没有**，fixture 的 `inference` 已经论证过，建议补进 G 节。

### fixture / card-model 的其它发现

1. **`sim.py` 的 `seed_for` 给出 12~18 张起手，超过手牌上限 10。** 它本身不建模手牌上限，所以公式表这批用例只能把 `handLimit` 放开跑；手牌上限单独由手写用例 `testBounceAroundBurnsRightmostWhenHandIsFull` 覆盖。这是照任务书用 `seed_for` 的必然代价，不是 bug，但报告里得说清「公式表全过 ≠ 手牌上限已验」。
2. **`sim.py` 把弹回建模成「印刷费 + 这一次的新附魔」，丢掉了实体原有的附魔。** 炉石的附魔挂在实体上，board → hand → board → hand 一路带着；本引擎按实体保留，否则验收 6 的「先舞动后步 = 0」根本做不出来（那张龙必须同时带着 `set(1)` 和 `delta(-2)`）。两种模型只在「暗影步弹一个由带附魔的牌下场的随从」时不同，公式表里没有这种 token，所以两边在 fixture 上等价。
3. **「24 张牌」实际是 23 张 + 英雄技能**，且 `Cards.by(cardId:)` 会**过滤掉 `hero_power` 和 hero_skins 的 `hero`**（`Cards.swift:61-67`），所以 `HERO_03bmhp`（匕首精通）和 `HERO_03bm`（马迪亚斯·肖尔）**用 `Cards.by(cardId:)` 恒为 nil**，只能用 `Cards.any(byId:)`。验收第 2 条的措辞按这个理解落的：23 张牌走 `by(cardId:)` 并连 dbfId / 印刷费 / 身材 / 龙牌一起断言，英雄与英雄技能走 `any(byId:)`。
4. **card-model §20 说暗影施法者「战吼结算时它自己已经在场上，可以指自己」——这条存疑。** 炉石的指向性战吼是**下场前**选目标，被打出的随从本身不在候选里。本引擎按「下场前选目标」实现（搜索侧），公式表重放侧沿用 `sim.py` 的口径（未指定目标时复制品身份是「含它自己的场面并集」）。两边在 fixture 上没有分歧，但**「暗-暗」这种自复制线要不要允许，需要用户实战确认一次**。
5. **G1 得到独立验证，而且不需要任何特例。** 殒命暗影按「每施放一个法术就改写成那张法术的印刷版」建模后，公式表的 `殒-舞` token 自动成立（费用 3、吃掉刀油两层各一槽），全表 16 个 `殒-舞` 里除了 `t1-48p-08` 那个漏连字符的都逐 token 对上。
6. **挖掘宝藏的「海盗 → 给币」写了断言**（`testNoPirateAmongDeckMinions`）：牌库 6 张随从没有一张是海盗，换牌时这条会先红。
7. `t2-wuhu-03` 在 card-model G 节的错表里没有、`sim.py` 也报不一致，但那只是因为它的一阶段是 `null`。按 `expandedLines` 的第一条（表里印的数字对应的那条）代入后**整行通过**，不是错行。
8. `t2-wudao-01`（无刀做无限）只有散文没有费用列，无法重放；G5 说的两条鲨鱼同时在场也只影响这一行，v1 确实碰不到。

### 与任务书硬约束的对照

- 卡牌效果**全在数据表里**，引擎零 `if cardId ==`；状态全是值语义 `struct`，卡表 `static let`。
- **同步、单线程、纯函数**：没有全局可变状态、没有跨状态记忆化、没有 `Hasher` 的随机种子；确定性用例断言两次调用的 `maxDamage` / `termination` / `lethalLines`（顺序 + 难度分 + 动作序列）/ `chosenLine` / `missingPieces` / `statesExpanded` / `depthReached` 全等。
- **路径重放校验是 P0**：`chosenLine`、`lethalLines`、`branches` 在返回前一律由同一套引擎从根状态重放，过不了直接丢掉这条线。
- 没有复制 `zcr0701/hearthstone-selfplay` 的任何代码或卡表；借的只有思路（正交通道、分桶保底、随机 → 分支、CPU 预算），卡表是从 card-model 的官方文本重新建的。
- 异教地图 / 垂钓时光按已决当截断：搜索侧直接不允许打（`RDOptions.allowTruncatedDraws = false`），重放侧允许并计入 `state.truncatedDraws`，带截断的线不进 `lethalLines`。

## review 后修正（2026-09-11）

只动 `HSTracker/RedDragon/*.swift` 与 `HSTrackerTests/RedDragonTests.swift`，未 commit。

### 改了什么

1. **阿莱的伤害只能指敌方**（必修）。原来 `targetScope = .anyCharacter` + `dealDamage` 对 `.friendlyMinion` 真扣血 —— 搜索能生成「战吼打死自己的 1/1 复制体腾格」这种游戏里不存在的动作，而重放用的是同一套错规则，挡不住。新增作用域 `RDTargetScope.enemyCharacter`（敌方随从 + 敌方英雄），阿莱改用它；`legalTargets` / `hasLegalTarget` / `isLegalTarget` 各加一支，`validate` 里 `.unspecifiedFriendly`（公式表重放口径）也按作用域拦住，非友方作用域直接 `illegalTarget`。搜索启发式里三处 `def.targetScope == .anyCharacter` 换成 `RDCards.canTargetEnemyHero(def)`，仍然不写死单张牌。`.anyCharacter` 保留在枚举里备用。真实卡牌对友方是治疗 8，card-model 第三部分第 9 条「治疗友方分支不展开」照旧成立。
2. **手牌去重 key 加两项**（应修）。`RDState.canonicalHash()` 的手牌 key 和 `RDEngine.legalActions` 的 `seenCardKeys` 原来只看 (身份, 有效费用[, 附魔数])，把「殒命暗影变成的 X」和「真的 X」、「1/1 复制体」和「原版」合并了 —— 搜索只展开先遇到的那张。两处 key 都补上 `isShadowOfDemise` 与「是否 1/1 复制体」（`statsOverride != nil`；`seenCardKeys` 本来就有后者，补的是前者）。
3. **卡表一致性检查**（保护）。`RDCards.def(_:)` 按 rawValue 索引排序后的表，少登记一条就静默错位。建表的 `byCard` 闭包里加 `assert`（条目数 = `RDCard.allCases.count`、第 i 条的 rawValue 就是 i）；Release 不编译 `assert`，所以同一条不变量另由单元测试 `testCardTableIsCompleteAndAligned` 守着。

新增测试 2 个：`testAlexstraszaCannotDamageFriendlyMinions`（指友方随从 → `illegalTarget`，`.unspecifiedFriendly` 在 `.replay` 下也 `illegalTarget`，`legalActions` 里没有指向友方的阿莱动作，打脸 / 指敌方随从仍在，友方随从一点血没掉）、`testCardTableIsCompleteAndAligned`。

### 验收

- `xcodebuild … build`：`** BUILD SUCCEEDED **`
- `xcodebuild … test`：`** TEST SUCCEEDED **`，`Executed 70 tests, with 0 failures (0 unexpected) in 164.160 seconds`（原 68 + 新增 2；`RedDragonTests` 18 → 20）

### 数字前后对比

前值是**本机重测的改动前基线**（同一台 Mac mini M4 / 同一条命令），不是原执行结果里那台机器的数，免得把机器差异算进来；原执行结果的 Debug 平均 3.185s / 最慢 6.951s 与本机基线基本一致。

| 项 | 改前 | 改后 |
|---|---|---|
| 重放 通过 / 失败（全白名单）/ 跳过 | 52 / 22 / 1 | **52 / 22 / 1**（不变） |
| 搜索 `maxDamage ≥ 表中伤害` | 49 / 49 | **49 / 49** |
| 难度分 min / p25 / 中位 / p75 / max | 13 / 26 / 29 / 33 / 38 | **13 / 26 / 29 / 33 / 38**（不变） |
| 搜索 CPU 合计（Debug 宿主，49 行） | 155.49s | **158.66s**（+2.0%） |
| 平均 / 最慢 | 3.173s / 6.993s（`t1-48p-07`） | **3.238s / 6.735s**（同一行） |
| 展开状态数（`t1-48p-07` / `t1-48p-06` / `t2-wuhu-11`） | 263213 / 215063 / 220049 | **255446 / 231751 / 206340** |

状态数如预期变得有增有减：去重变细让某些行多展开状态，阿莱不再枚举友方目标又省掉一批动作，两边大致抵消，总 CPU 只涨 2%。唯一的结果变化是 `t1-48p-05` 的 `maxDamage` 从 80 变 81（同层找到一条多 1 伤的线，仍过重放校验）。

⚠️ 一次**与本次改动无关的偶发**：改动前跑全量测试时，测试宿主在 `testSearchReachesTableDamage` 跑到约 90s 时静默退出（`Restarting after unexpected exit, crash, or test timeout`，`DiagnosticReports` 里没有对应崩溃报告，进程 RSS 一直只有 250~370 MB）。单独重跑该用例通过（155.5s），改动后的全量测试也通过（70/70）。当成宿主偶发死亡记一笔，没做进一步处理。

## 第二轮修正（2026-09-11）

只动 `HSTracker/RedDragon/*.swift`、`HSTrackerTests/RedDragonTests.swift`、`formulas.json` 的**批注字段**（`phases` / `raw` / `note` / `crossCheck` 一字未动）与本文件末尾，未 commit。

### A. 那 18 行不是「原表算错」，是前提条件没进转录

表 2 的组名是「提前**彗**」= 上回合已打过**幸运彗星**（Lucky Comet，`GDB_873`，dbfId 111292，2 费潜行者法术：发现一张连击随从；你打出的下一张连击随从的连击效果触发两次，**不限本回合**）。有它在，首张刀油的连击就是两层各 -2 = -4，而狐人老千不是连击随从、不吃彗星仍 -2 —— **两者不矛盾，18 行全部自洽**。用户不带这张牌，所以这 18 行对本牌组不适用。

1. `formulas.json` 批注改口（JSON 仍合法，75 行 / 16 组不变）：
   - `notation` 新增 `彗` / `彗星`（= 幸运彗星 `GDB_873` 全文）与 `提前彗`（组名释义 + 「本牌组不带」），`彗逆序` 条补「= 幸运彗星 + 逆序启动」。
   - `groups`：`狐起手` 的 ⚠️ 从「推演发现的系统性算法错…16 行」改成「**前提：已打过幸运彗星；本牌组不带**…18 行」，保留原误判与被推翻的过程；`刀起手` 的一行同改；`提前弊` 组里「组名第三字推定为『费』」那条作废，改成 ✅「组名第三字是『彗』」（`name` 字段仍是转录原样）。
   - 三行带 `inference.首刀减费` 的（`t2-daoqs-02` / `t2-pre-01` / `t2-pre-02`）逐条改口；`t2-pre-02` 那条原是「空场预启动 → 判决性证据证明是算错」，现在改成同一事实的正解：**-4 不是鲨鱼给的，是上回合的彗星给的**。（另外 15 行本来就没有 `inference`，靠组级批注覆盖。）
2. `RedDragonTests.swift` 白名单：18 行统一改成「依赖幸运彗星（GDB_873）：首刀连击双触发 -4，本牌组不带这张牌，不建模」，4 行单格笔误不变。白名单表改成闭包形式以共用这句原因。
3. **引擎不建模幸运彗星**，落实一般规则「状态里出现卡表没建模的牌 → 当作不可打的杂牌，只占手牌格」：
   - `RDCard.junkPlaceholder` 直接承担这个角色，不需要新牌。新增 `RDOptions.allowPlaceholderPlays`（搜索 `false` / 公式表重放 `true`）+ `RDIllegal.unplayableJunk`：搜索侧 `legalActions` 不产生占位牌的动作、`apply` 直接拒；公式表的「杂」/「腾格」仍打得出（表里那是真牌，只是没写是哪张）。
   - `RDHandCard` 加了一个字段 `unmodeledCardId`（+ 便捷构造 `RDHandCard.unmodeled(entityId:cardId:)`）给 T2 在 overlay 上显示「这张是什么牌」；**它不进 `canonicalHash`** —— 对搜索来说所有杂牌等价，按 cardId 区分只会让去重失效。
   - `findMissingPieces` 跳过占位牌（打不出去的牌不可能是「缺的那一张」）。
   - 新增用例 `testUnmodeledCardIsUnplayableJunkThatOnlyOccupiesAHandSlot`：塞一张 `GDB_873` 进手 → 占掉手牌格、`legalActions` 里没有它、`apply` 抛 `unplayableJunk`、不进 `missingPieces`、`.replay` 下仍可打。

### B. 难度分 v2：重点是「逆序启动」

删掉 `editDistance` / `openingDeviation`（用户否决「和模板前 n 张比编辑距离」），`Components` 改成五项，权重全部是常量：

| 项 | 权重 | 说明 |
|---|---|---|
| **顺序颠倒对数** | **12** | 只看线里出现的模板牌（`鱼 → 狐 → 刀 → 暗 → 牛`），每张取**首次打出**的位置，数「模板说 x 在 y 前、线里却 y 在 x 前」的对数（Kendall tau）。缺的牌不算颠倒；同一张牌打第二次不算新位置 |
| 缺件数 | 6 | 模板五张里线里没有的张数（无狐 = 1） |
| 中途插牌数 | 2 | 第一张与最后一张模板牌**之间**插进来的非模板动作。模板开始之前的偷费（币 / 伺）不算 |
| 操作数 | 1 | 动作序列长度 |
| 边牌张数 | 3 | 这条线从边牌拿了几张 |

`monotonicLowerBound` 保留（另外三项都 ≥ 0，它仍是合法下界）。

验收 5b 由 3 条断言扩成 5 个用例：更长更难（同一套模板牌后面多接三步）／边牌多更难／**狐 → 鱼 比 鱼 → 狐 难且由「颠倒 = 1」体现**（操作数与缺件数完全相同；再加「刀起手 = 颠倒 2 更难」）／**缺狐的线比同顺序有狐的线难**／中途插牌更难（且模板前的币 / 伺不算插牌）。

### C. 暗影施法者不能指自己

重放侧 `.unspecifiedFriendly` 的复制体身份池原来是「含自己的场面并集」，现在把施法者本人（`ctx.source`）剔掉（`uniqueBoardCards(_:excludingEntity:)`）；**场上没有别的随从时不产生复制**。搜索侧本来就是「下场前选目标、自己不在候选」，两边口径终于一致（card-model §20 那条「战吼结算时它已在场、可以指自己」的存疑点就此按「不能」定案）。新增用例 `testShadowcasterCannotCopyItself`。

**重放数字：52 / 22 / 1 没有变化，逐行伤害仍与表一致。** 原因查清了：全表 57 行打两次以上「暗」，第二张「暗」都来自舞动把施法者本体弹回手，没有一行需要「复制出来的身份是暗」；`pickHandCard` 也优先用身份已定的牌。所以剔掉自己只是把一个从没被选中的候选身份去掉。

### 验收

- `xcodebuild … build`：`** BUILD SUCCEEDED **`
- `xcodebuild … test`：`** TEST SUCCEEDED **`，`Executed 74 tests, with 0 failures (0 unexpected) in 167.188 seconds`（原 70 + 新增 4；`RedDragonTests` 20 → 24）
- 重放：**通过 52 / 失败 22（全部在白名单）/ 跳过 1**，与上一轮逐项相同
- 搜索：49 行全部 `maxDamage ≥ 表中伤害`；`chosenLine` / `lethalLines` 全过重放校验

### 难度分 v2 的新分布与阈值

52 条可重放线：**min 12 / p25 23 / 中位 27 / p75 33 / max 48**（旧口径是 13 / 26 / 29 / 33 / 38）。仍取 p25 / p75 当分界：**基础 ≤ 23，进阶 24~33，困难 > 33**（写进 `RDDifficulty.basicThreshold / advancedThreshold`）。

逐组落点（n / min / 中位 / max）：

| 组 | n | min | 中位 | max |
|---|---|---|---|---|
| 预启动 | 3 | 12 | 14 | 15 |
| 32 公式 | 5 | 20 | 23 | **43** |
| 48 公式 | 13 | 21 | 25 | **45** |
| 打 / 回 16 | 5 | 21 | 25 | **45** |
| 无晦 | 4 | 21 | 29 | 33 |
| 无暗 + 无晦 | 2 | 22 | 29 | 29 |
| 常用缺随抽随 | 1 | 24 | 24 | 24 |
| 48+ 公式（64 / 80） | 7 | 26 | 30 | **44** |
| 无狐 | 12 | 26 | 30 | **48** |

分档名单（困难 10 条，全部是「颠倒 ≥ 1」或无狐最长的三条）：

- **基础（12~23，16 条）**：三条预启动（12 / 14 / 15）、`t1-32-01`(20)、`t1-48-01`(21)、`t1-16-02a`(21)、`t2-wuhui-01/02`(21)、`t1-32-03`(22)、`t2-wuan-02`(22)、`t1-32-05`/`t1-48-03a/b`/`t1-48-13a/b`/`t1-16-01`(23)
- **进阶（24~33，26 条）**：`t1-32-02`/`t1-48-08`/`t2-chou-01`(24) → `t1-48p-07`/`t2-wuhui-03`(33)，48 / 48+ / 80 的长线与大部分无狐线都在这一档
- **困难（34~48，10 条）**：`t2-wuhu-09`(34)、`t2-wuhu-10/11`(35)、`t1-48-09`/`t1-48-10`/`t1-16-03a`(41，颠倒 1 + 插牌 2~3)、`t1-32-04`(43)、`t1-48p-01`(44)、`t1-48-12`/`t1-16-03b`(45)、`t2-wuhu-02`(48，颠倒 1 + 缺件 1 + 插牌 2)

**看落点的两句话**：① 困难档现在是「先牛后暗」这类**颠倒了模板顺序**的线（`鱼狐刀牛晦步-刀暗…`），以及无狐里最长的三条 —— 正是用户说的「逆序启动最难」；② 纯粹长（48+ / 80，操作 20~25 但顺序规矩）落在进阶而不是困难，这是 v2 相对 v1 的主要变化，**如果实战感觉 80 线该算困难，把 `advancedThreshold` 从 33 调到 30 即可**（会把 `t1-48p-04/05/06`、`t2-wuhu-04a/05/06` 六条抬进困难）。
③ 真正的「彗逆序」组（狐起手 / 刀起手，颠倒 2）因为依赖幸运彗星、重放不过，**不在这 52 条里** —— 它们如果能跑，颠倒 2 = +24，会稳稳落在困难档顶端。

### 数字前后对比

| 项 | 第一轮 review 后 | 本轮 |
|---|---|---|
| 测试数 | 70（RedDragon 20） | **74（RedDragon 24）** |
| 重放 通过 / 失败 / 跳过 | 52 / 22 / 1 | **52 / 22 / 1**（不变） |
| 搜索 `maxDamage ≥ 表中伤害` | 49 / 49 | **49 / 49** |
| 难度分 min / p25 / 中位 / p75 / max | 13 / 26 / 29 / 33 / 38 | **12 / 23 / 27 / 33 / 48** |
| 阈值（基础 / 进阶上限） | 26 / 33 | **23 / 33** |
| 搜索 CPU 合计（Debug 宿主，49 行） | 158.66s | **161.95s**（+2.1%，噪声） |
| 平均 / 最慢 | 3.238s / 6.735s（`t1-48p-07`） | **3.305s / 7.206s**（同一行） |
| 展开状态数（`t1-48p-07` / `t1-48p-06` / `t2-wuhu-11`） | 255446 / 231751 / 206340 | **255446 / 231751 / 206340**（逐个相同） |

状态数逐个相同说明 A / C 两项都没碰搜索的展开路径：占位牌本来就没出现在搜索用的局面里，`.unspecifiedFriendly` 只存在于重放口径。难度分只改排序与分档，不改搜索。

## 校准（2026-09-11，Claude 按用户决定直接改）

- 模板改为**暗、牛同级**（`RDDifficulty.openingRank`），同级不计颠倒——用户：牛暗互换很常见，不算逆序。
- **纯长线不算困难**，阈值维持 基础 ≤ 23 / 进阶 ≤ 33。用户：这套牌拼思路不拼手速，和别的 OTK 比手速要求不高。
- 重跑 `RedDragonTests` 24 / 24 通过。52 条线**全部颠倒 = 0**，分布 min 12 / p25 23 / 中位 27 / p75 30 / max 36；困难档只剩无狐最长的四条（`t2-wuhu-09/10/11/02`，34~36），此前因「牛在暗前」被判困难的 8 条回到进阶（`t1-32-04` 43 → 31）。逆序线（+12 / 对）不在样本里，一出现即困难。

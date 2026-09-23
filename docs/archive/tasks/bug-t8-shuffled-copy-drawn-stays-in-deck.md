# Bug T8：洗入副本被抽走后，牌库段仍留着它（T7 第 1 条的残留，根治）

先读 `docs/tasks/_common.md`，再读 `docs/tasks/bug-t7-zone-accounting-edges.md`（尤其「第 1 条」「一处残留」「修不了 / 只修一半」三节）
和 `docs/tasks/bug-t6-zone-sections-stale.md`。本书就是 T7 明写「本书不许动 `TagChangeActions`」而留下的那一条，**这次允许动**。

## 症状（用户原话，2026-09-15）

「被抽走卡牌仍在牌库变绿不可接受，修成正常符合三段的行为。」

用户点名的原因就是 T7 的残留：**洗入的同名副本被抽走后，牌库段少算 1**。
T7 用的「洗入副本」信号（在库 + `info.created` + `CREATOR` 指向有 cardId 的实体）只在实体**还在牌库里**时成立；
副本一抽到手，它就落进 `entitiesThatLeftTheDeck`，被当成牌表那份扣掉。

三段的正确行为：牌库段 = 此刻真的还在牌库里的张数（牌表未抽的 + 洗入未抽的）；手牌段 = 此刻在手上的；
两段各自对，行才该在哪就在哪。牌库段的行绿名沿用 Phase 2 / T1 定下的含义（「库里还有、手上也有一张」），
**行本身的张数错了才是 bug**，绿名不是。

## 方向

T7 报告给的根治方向：**在实体创建那一刻记下「这张是新造的、不属于牌表」**，而不是事后从当前区域倒推。
落在 `TagChangeActions` / `Game.swift` / `Player` 的入库钩子哪一处、记成什么字段、`EntityInfo` 要不要加东西，你定，报告里给理由。
注意 T6 / T7 已经证伪的两条：`info.created` 单独不可信（普通抽牌、探寻、从墓地 / 备用区回库都会置 true）；
`originalZone` 分不出洗入与原版（`FULL_ENTITY` 直接进库时就是 `.deck`）。别再踩。

## 硬约束

- 不变式照旧：每个 cardId 牌库 + 手牌 + |已打出| == 已知张数；牌库段无 `count == 0`。改了定义同步改测试和任务书里的表。
- `playerCardList` / `opponentCardList` / `getDeckState()` 一行不动。上游解析路径可以动，但**只加不改**：
  已有的 `info.created` / `originalZone` 赋值逻辑一处不许改语义，平铺模式行为必须和修前逐字一致。
- 对手侧 `hidden` 过滤保住；对手侧同样要对（对手洗入的副本被抽走）。
- **先失败再修**：至少一条测试先红 —— 「牌表 A×2 未抽 + 洗入一张 A + 洗入的那张被抽走」牌库段应报 2、手牌段 1；
  回放 fixture `HSTrackerTests/Fixtures/ZoneReplay/2026-09-14-standard.log` 有降落伞（不在牌表）洗入又被抽的片段，
  可以用它验新信号不误伤；同名洗入的真实日志在 `~/Desktop/dev/HSTracker-logs/2026-09-14-phase2-t1-Power.log` 别的局里找，找不到就造单元测试并在报告里说明。
- T7 的回归护栏 `testNoDeckListCardIsCountedAboveItsListCount` 必须继续绿。
- `_common.md` 规则照旧：不 commit、不动 PLAN / PROGRESS、`.xcstrings` 不动。

## 允许修改的文件

- `HSTracker/Logging/Parsers/TagChangeActions.swift`、`HSTracker/Logging/Game.swift`、`HSTracker/Logging/Player.swift`、`HSTracker/Logging/Entity.swift`（如需加字段）
- `HSTrackerTests/CardZoneGroupsTests.swift`、`HSTrackerTests/ZoneGroupsReplayTests.swift`；新增 fixture / 文件登记 pbxproj

## 验收

1. 受限环境 Debug build `BUILD SUCCEEDED`；测试原 106 条 + 新增全绿。
2. 报告里：新信号是什么、写在哪一处、为什么它在「副本被抽走」之后仍然可信；用什么证明它不误伤牌表卡
   （探寻、从墓地回库、被夺走再还回、幸运币）；平铺模式为什么没变；哪条修不了直说。

## 汇报

结果写进本文件末尾「执行结果」一节。**不要 commit、不要动 `docs/PLAN.md` / `docs/PROGRESS.md`**。

## 执行结果（2026-09-15）

修了。改了 5 个文件、没有新增文件，所以 `project.pbxproj` 一行没动。

### 先失败：新增 5 条测试里 4 条红

把三处行为改动退回原样（**签名和 `Entity.wasShuffledIntoDeck` 字段保留**，否则测试编译不过）：
`TagChangeActions` 里三个 `markShuffledIntoDeck` 调用点删掉、`CardZoneGroups.make` 的
`leftFromList` 退回 `left`、`shuffledIntoDeckByCardId` 退回 T7 的现场推导。跑两个分区测试类：

```
Executed 27 tests, with 8 failures
CardZoneGroupsTests.testAShuffledInCopyBeingDrawnDoesNotCostTheDeckListACard   ["A": 1] ≠ ["A": 2]；不变式 2 ≠ 3
CardZoneGroupsTests.testAShuffledInCopyBeingPlayedDoesNotCostTheDeckListACard  ["A": 1] ≠ ["A": 2]；不变式 2 ≠ 3
CardZoneGroupsTests.testAShuffledInCopyThatWasDrawnStillLeavesTheListInTheDeck Optional(1) ≠ Optional(2)
ZoneGroupsReplayTests.testTheShuffledInSignalIsLatchedOnTheShuffledInCopiesOnly 0 ≠ 6（信号根本没落地）
```

第 5 条 `testADrawnDeckListCardStillLeavesTheDeckSection` 修前就是绿的 —— 它是**对照组**：
同一个实体不带新标志时仍然是牌表那份，抽走就得从牌库段扣掉。信号一旦放宽成「谁抽走都不扣」，它立刻红。

### 新信号：`Entity.wasShuffledIntoDeck`，在解析时落闩

字段加在 `Entity`（`Entity.swift:26` 一带），不是 `EntityInfo` —— 任务书的「允许修改的文件」里
只有 `Entity.swift`，`EntityInfo.swift` 不在列内，所以没动它。`Entity.copy(with:)` 里补了一行同步。

落闩点：`TagChangeActions.markShuffledIntoDeck(eventHandler:id:)`，从 `findAction` 的
`.zone` / `.creator` / `.displayed_creator` 三个 case 调用。条件三个，与 T7 验证过的那组逐字相同：

1. 实体**此刻在牌库区**；
2. `info.created`；
3. `CREATOR`（没有就退 `DISPLAYED_CREATOR`）指向一个**有 cardId 的实体**。

**为什么它在「副本被抽走」之后仍然可信**：条件 1 只在**落闩那一刻**判一次，判完写进实体、再不回头看区域。
T7 的写法是每次取数现场重算，所以副本一离开牌库条件 1 就不成立、信号消失；现在它是实体的身份，
跟着实体从牌库走到手牌、走到战场、被夺走，都还在。

**为什么必须挂在三个 tag 上**（踩过的坑）：`FULL_ENTITY` 的创建 tag 在
`TagChangeHandler.tagChange` 里走 `isCreationTag` 分支，动作被**排队**到 `invokeQueuedActions`；
而紧随其后的 `TAG_CHANGE … DISPLAYED_CREATOR` 是普通 tag，**立刻执行**。
fixture 2538-2542 行就是这个形状（降落伞 id=96：先 `FULL_ENTITY … tag=ZONE value=DECK`，
再 `TAG_CHANGE … tag=DISPLAYED_CREATOR value=16`）。所以：
creator 先到时 `info.created` 还没打上（排队的 `zoneChange` 还没跑）→ 不落闩；
等排队的 `zoneChange` 跑完 `createInDeck` 打上 `created`，`.zone` 那一路补落闩。
反过来（实体早就在库里，creator 后到）由 creator 两路落闩。两边都挂才不漏。

### 算法：只有牌表自己的那份才从牌表里扣

`CardZoneGroups.make` 加 `shuffledLeftDeck: [String: Int] = [:]`（离开牌库的里有几张是洗入副本），
牌库段算式从

```
max( max(牌表 − 离开, 0) + 洗入在库 , 已知在库 )
```

改成

```
max( max(牌表 − (离开 − 离开里的洗入副本), 0) + 洗入在库 , 已知在库 )
```

`leftDeck` / 已打出段一个字没改：洗入副本被抽走后**照旧**进已打出段（T6 定下的形态，2.7 再定），
只是不再从牌表里扣一张。手推四种情况：

| 局面 | 牌库段 | 手牌段 | 已打出段 | 合计 vs 已知 |
|---|---|---|---|---|
| 牌表 A×2 未抽 + 洗入 1 张 A 在库 | 3 | 0 | 0 | 3 = 3 |
| 洗入那张被抽到手（**本 bug**） | 2 | 1 | 0 | 3 = 3 |
| 洗入那张被打出 | 2 | 0 | 1 | 3 = 3 |
| 降落伞（不在牌表）6 张洗入、抽走 3 | 3 | — | 3 | 6 = 6，**与修前逐字相同** |

### 怎么证明它不误伤牌表卡

回放 fixture `2026-09-14-standard.log` 跑一遍，把**我方**落闩的实体全列出来：
`testTheShuffledInSignalIsLatchedOnTheShuffledInCopiesOnly` 断言恰好 6 个、全是降落伞 `VAC_933t`、
抽走 3 张之后仍然是 6 个（其中 3 个已不在库），且没有一个 cardId 落在牌表 13 张里。
这一局里被覆盖到的「会把 `info.created` 打上、但不该算洗入」的路径：
普通抽牌（第 2 回合起 100% `created=true`，T6 记过）、探寻 / deck→setaside→deck、
从 SETASIDE 回手、幸运币（`originalZone == .hand`，压根进不了 `entitiesThatLeftTheDeck`）、
被夺走再还回（跳虫 `SC_010`，`originalController` 那条继续管着）。全部没落闩。
T7 的回归护栏 `testNoDeckListCardIsCountedAboveItsListCount` 继续绿。

**一个真实的意外，值得记下来**：第一版断言写的是「全场只有 6 个」，实际跑出 **26 个**。
多出的 20 个是**对手**的，`DISPLAYED_CREATOR=52`，而实体 52 是 `JAIL_430` =
**阿札莉娜·摄魂者**（fixture 948-949 行，开局 TRIGGER）—— 她把对手的牌库整副换成复制牌。
那 20 张确实是「被牌造出来、放进牌库」的副本，落闩是**对的**，是断言的范围写错了。
（HSTracker 本来就有 `deckCopiedFromEnemy` 认这张牌。）测试改成只看我方实体，并在注释里写明原因。
顺带说明：对手侧同样吃到这次修复 —— 对手洗入的副本被抽走，也不再从对手牌表里扣。

### 平铺模式为什么没变

`playerCardList` / `opponentCardList` / `getDeckState()` 一行没动，没有任何一处新代码被它们调用。
`wasShuffledIntoDeck` 是新字段，除了 `Player` 的两个私有分区取数没有第二个读者。
上游解析里已有的 `info.created` / `originalZone` 赋值一处没改语义 —— `markShuffledIntoDeck`
只读不写这两者，且是在原有动作**之后**追加调用，原动作的参数和顺序都没动。

### 不变式

定义没改：「每个 cardId：牌库 + 手牌 + |已打出| == 已知张数」「牌库段无 `count == 0`」。
洗入副本无论在库还是已抽都算进「已知张数」，两条新的 `make` 测试都带
`assertNoCardIsLost` / `assertDeckHasNoZeroCount`。对手侧 `hidden` 过滤没动：
`shuffledIntoDeckByCardId` 仍带 `isLocalPlayer || !info.hidden`，
`shuffledCopiesThatLeftTheDeck` 走 `entitiesThatLeftTheDeck`（`revealedEntities`，要求 `hasCardId`）。

措辞要准确：不变式在**对手侧有一个已知的缺口**，且不是本书引入的 —— 对手洗入的副本被抽到手、
再从手上回到牌库时，`handToDeck` 会把 `info.hidden` 置回 `true`，于是这张牌**同时**从
「在库统计」（`shuffledIntoDeckByCardId` / `knownCardsInDeckZone` 的 `!info.hidden`）和
「离库统计」（`revealedEntities` 要求 `hasCardId`）里消失，对手侧那个 cardId 的「已知张数」少 1。
这是 T6 / T7 一路沿用的「不泄露对手未揭示牌库」取舍，本书没改，见下节。

### 改了哪些文件

- `HSTracker/Logging/Entity.swift` —— 加 `wasShuffledIntoDeck` 字段 + 在 `copy(with:)` 里同步。
- `HSTracker/Logging/Parsers/TagChangeActions.swift` —— 新增 `markShuffledIntoDeck`，
  从 `.zone` / `.creator` / `.displayed_creator` 三处**追加**调用（原有调用一行没改）。
- `HSTracker/Logging/Player.swift` —— `make` 加 `shuffledLeftDeck` 参数并改牌库段算式；
  `shuffledIntoDeckByCardId` 改读闩；新增 `shuffledCopiesThatLeftTheDeck`；`zoneGroups` 多传一个参数。
  平铺路径一行没动。
- `HSTrackerTests/CardZoneGroupsTests.swift` —— 新增 4 条（2 条纯函数、2 条走 `opponentCardGroups`
  真实体，其中 1 条是对照组）+ `addDrawnDeckCard` helper。
- `HSTrackerTests/ZoneGroupsReplayTests.swift` —— 新增 1 条回放断言（信号落地 + 不误伤）。

**没有新增文件，`project.pbxproj` 一行没动。**

### 验收

- `xcodebuild -project HSTracker.xcodeproj -scheme HSTracker -configuration Debug -destination 'platform=macOS' build`：`** BUILD SUCCEEDED **`
- `xcodebuild … test`：`** TEST SUCCEEDED **`，`Executed 111 tests, with 0 failures (0 unexpected) in 175.630 (176.288) seconds`（原 106 + 新增 5）
  —— 这是**返工前**的一轮，最终数字见末节「返工」（112）。
- 🎮 待用户实测：带「洗入同名副本」的牌组（如复制自己牌库里的牌再抽出来），看牌库段张数是否还对；
  带探寻的牌组（牌库段不许超过牌表张数）；`open …/Debug/HSTracker.app`

### 修不了 / 只修一半 / 按规则没动

- **落闩依赖 `CREATOR` / `DISPLAYED_CREATOR` 这一条没变**，所以「游戏不写 creator 的洗入」
  仍然判不出来 —— 信号方向是保守的：判不出来就退回「按牌表那份算」，宁可少算不会多算。
  T7 那条残留（洗入副本被抽走少算 1）本书已根治，剩下的是这条更窄的口子。
- **牌表卡被抽走后又真正洗回牌库**（不是探寻）：它回到牌库、不带 creator，仍按牌表那份算，正确；
  但如果游戏把它当**新实体**重造，会落闩成洗入副本，牌库段会比牌表多 1 张。
  fixture 里没有这种牌，没法验证，先记着。
- **降落伞类的牌进「已打出段」**：形态没动，仍是 T6 的既有行为，2.7 再定。
- **平铺路径的 `getDeckState()` 同源 bug 仍未修**（T6 / T7 执行结果都记过），本书一行没动。
- `EntityInfo.swift` 不在允许修改的文件里，所以新字段挂在 `Entity` 上而不是 `info` 上。
  语义上它更像 `EntityInfo` 的成员，将来若放开可以搬过去。
- `Entity.copy(with:)` 不复制 `info.originalZone`（上游遗留，分区路径不走 copy），沿用现状没修。
- **对手侧「洗入副本被抽走再回库」会让已知张数少 1**：`handToDeck` 把 `info.hidden` 置回 `true`，
  这张牌从在库统计和离库统计里同时消失（见上节「不变式」）。这是 T6 / T7 沿用的对手侧 hidden 取舍
  —— 要修就得记住「这张我们见过」，等于在对手牌库里留一份揭示过的影子，是另一本书的事，本书没动。

## 返工：Codex review（2026-09-15）一条 Major

**问题成立**：`markShuffledIntoDeck` 没沿用 `creatorChanged`（原 `TagChangeActions.swift:506-510`）
对**视界术**的排除。视界术（`FarSight` / `FarSightCore` / `FarSightVanilla`）把 `DISPLAYED_CREATOR`
写在**被它抽的那张原牌**上，而不是某张生成副本上。那张原牌之后回到牌库时 `info.created` 早已为 true，
三个条件全中，会被误闩成「洗入副本」；再被抽走时 `shuffledLeftDeck` 把本该从牌表扣的那张抵消掉，
**牌库段多 1**（方向和本 bug 正好相反）。

**修法**：把 `creatorChanged` 里那段 `cardId ==` 三连比较抽成私有 helper
`isFarSight(_ entity: Entity?) -> Bool`，两处共用 —— **只重构不改语义**：原来是
`if let displayedCreator = …, displayedCreator.cardId == …` 三选一就 `return`，
helper 对 `nil` 返回 `false`，两者等价。`markShuffledIntoDeck` 里在解析 `creatorId` **之前**
加一道 `guard`，`CREATOR` 和 `DISPLAYED_CREATOR` 两个 tag 指向的实体**任一**是视界术就不落闩
（只查解析后的那一个会漏掉「`.creator` 另有其人、`.displayed_creator` 是视界术」的形状）。

**先红后绿**：新增 `CardZoneGroupsTests.testFarSightDoesNotMakeTheCardItDrawsLookShuffledIn`，
走真实解析入口 `TagChangeHandler().tagChange(eventHandler:tag:.displayed_creator, id:21, value:20)`
（不手工赋 `wasShuffledIntoDeck`）：我方一张在库、`info.created == true` 的牌，
`DISPLAYED_CREATOR` 指向一个 cardId 为视界术的实体 → 不许落闩；同一形状把 creator 换成普通卡
（`VAC_933` 帕奇斯）→ 必须落闩，作对照组。把那道 `guard` 删掉重跑：

```
CardZoneGroupsTests.testFarSightDoesNotMakeTheCardItDrawsLookShuffledIn
  XCTAssertFalse failed - CS2_053 creates nothing, it only draws
  XCTAssertFalse failed - CORE_CS2_053 creates nothing, it only draws
  XCTAssertFalse failed - VAN_CS2_053 creates nothing, it only draws
** TEST FAILED **
```

三条视界术全红、对照组绿。装回 `guard` 后全量绿。

**返工后的验收**：

- `xcodebuild … build`：`** BUILD SUCCEEDED **`
- `xcodebuild … test`：`** TEST SUCCEEDED **`，`Executed 112 tests, with 0 failures (0 unexpected) in 168.784 (169.416) seconds`（原 106 + 新增 6）

其余结论不变，改动仍在同样 5 个文件里，没有新增文件。

## review（Claude + Codex，2026-09-15）通过

Claude 逐行核对了 5 个文件的 diff，自己跑了两遍受限环境 `test`：返工前 111 / 111、返工后 **112 / 112 全绿**。
Codex（`gpt-6-astra`，effort medium）独立 review 给了 2 条 Major + 1 条 Minor，逐条核实：

- **Major #1 成立，已返工**：视界术把 `DISPLAYED_CREATOR` 写在被抽的原牌上，原牌回库会被误闩。上游 `creatorChanged` 本来就排除它，新函数没沿用。修法是把排除抽成 `isFarSight` 让两处共用（只重构不改语义），并加了走真实解析入口的先红后绿测试。
- **Major #2 不是本次引入**：对手洗入副本被抽走再回库，`handToDeck` 置 `hidden = true`，它同时从在库 / 离库两边消失。这是 T6 / T7 沿用的「不泄露对手未揭示牌库」取舍，任务书「不变式」一节已改成如实陈述，列入「按规则没动」。
- **Minor #3 部分采纳**：返工加的视界术测试就是走解析器的；`Player` 级测试手工赋闩是有意为之（隔离算式），回放测试里的闩落地断言补上了解析器这层。「被夺走再还回」仍靠 `originalController` 那条护栏，没有单独测试。

信号本身与 T7 同一组条件，区别只在「落闩一次写进实体」而不是每次取数现场重算 —— 这是根治残留的全部。
仍然依赖游戏写 `CREATOR`，不写 creator 的洗入判不出来，方向保守（少算不多算）。

**🎮 待实测**：带「洗入同名副本再抽出」的牌组，看牌库段张数；带探寻的牌组，牌库段不许超过牌表张数。
`open ~/Library/Developer/Xcode/DerivedData/HSTracker-aahnpvwazbthckamdujfswcqfrtp/Build/Products/Debug/HSTracker.app`

# Bug T7：分区取数的三个边角错账（Codex review 2026-09-15）

先读 `docs/tasks/_common.md`，再读 `docs/tasks/bug-t6-zone-sections-stale.md`（尤其末节「Codex review」表，本书就是那三条）和
`docs/tasks/phase2-t1-zone-groups.md`。三条都在 Bug T6 新写的 `Player.zoneGroups` / `CardZoneGroups.make` 一带。

## 症状（Codex 原话的要点，已由 Claude 复核成立）

1. **同名副本洗入牌库时少算**：`CardZoneGroups.make` 牌库段用 `max(牌表 − 离开, 已知在库)`。两张原版未揭示（`listed = 2, left = 0`）+ 洗入一张同名（`known = 1`）→ 报 2，实际 3。
2. **控制权变化算错**：`entitiesThatLeftTheDeck` 走 `playerEntities`，按**当前**控制者过滤。我方从牌库抽出的随从被对手夺走后，从「离开牌库」里消失，牌库段当它还在；反过来夺来的对手随从被算进我方「离开牌库」，扣掉我方同名牌。
3. **定制 Zilliax 不归一**：牌表里是基础 id `CardIds.Collectible.Neutral.ZilliaxDeluxe3000`，抽到的实体是装饰模块 id，减法对不上，基础 Zilliax 永留牌库段。

## 线索（不是结论）

- 旧 `getDeckState()` 对 2 和 3 各有处理：`revealedEntities`（`Player.swift:251`，`isControlled || originalController == self.id`）；`Player.swift:790-797` 遇到装饰 id 就把基础 id 从牌表移除。**别把旧函数搬过来**，它对 `info.created` 的依赖就是 Bug T6 的根。
- 第 1 条最难：需要一个不依赖 `info.created` 的「这张是洗进来的副本、不是牌表那份」信号。候选：实体 `originalZone != .deck` 且当前 `isInDeck`；或 `info.created` 只在**当前在库**的实体上用（Bug T6 证明它对**抽出去**的实体不可信，对一直在库里的实体是否可信要你用回放 fixture 验证）。哪条成立用日志说话，都不成立就直说，报告里给理由。
- 回放 fixture `HSTrackerTests/Fixtures/ZoneReplay/2026-09-14-standard.log` 里有降落伞洗入（不在牌表，不触发第 1 条）；第 1 条要么造单元测试，要么从 `~/Desktop/dev/HSTracker-logs/2026-09-14-phase2-t1-Power.log` 别的局里找同名洗入的片段。

## 硬约束

- 只动分区路径：`CardZoneGroups` 与 `Player` 上 Bug T6 新增的那几个私有取数。`playerCardList` / `opponentCardList` / `getDeckState()` 一行不动；不动 `Game.swift`。
- 不变式照旧：每个 cardId 牌库 + 手牌 + |已打出| == 已知张数；牌库段无 `count == 0`。改了定义同步改测试。
- 对手侧的 `hidden` 过滤（不泄露未揭示的对手牌库）保住。
- 三条各至少一条测试，**先失败再修**。
- `_common.md` 规则照旧：不 commit、不动 PLAN / PROGRESS、`.xcstrings` 不动。

## 允许修改的文件

- `HSTracker/Logging/Player.swift`（只动 Bug T6 新增段）
- `HSTrackerTests/CardZoneGroupsTests.swift`、`HSTrackerTests/ZoneGroupsReplayTests.swift`；新增 fixture / 文件登记 pbxproj

## 验收

1. 受限环境 Debug build `BUILD SUCCEEDED`；测试原 100 条 + 新增全绿。
2. 报告里：三条各自的修法与依据；第 1 条用的「洗入副本」信号是什么、用什么证明它可信；哪条修不了或只修了一半。

## 汇报

结果写进本文件末尾「执行结果」一节。**不要 commit、不要动 `docs/PLAN.md` / `docs/PROGRESS.md`**。

## 执行结果（2026-09-15）

三条都修了。改了 3 个文件、没有新增文件，所以 `project.pbxproj` 一行没动。

### 先失败：三条各自的红

把 `Player.swift` 的四处改动逐条退回原样、测试文件不动，跑 6 条新测试：

```
Executed 6 tests, with 11 failures
CardZoneGroupsTests.testAShuffledInCopyIsNotSwallowedByUnrevealedListCopies  ["A": 2] ≠ ["A": 3]
CardZoneGroupsTests.testAShuffledInCopySurvivesACopyOfTheSameCardBeingDrawn  ["A": 1] ≠ ["A": 2]
CardZoneGroupsTests.testAChangeOfControlDoesNotMoveCardsBetweenTheDecks      BT_753 还在牌库段；SC_010 被扣掉
CardZoneGroupsTests.testACustomisedZilliaxLeavesTheDeckSectionOnceItIsDrawn  基础 Zilliax 还在牌库段
ZoneGroupsReplayTests.testADeckCardGivenToTheOpponentLeavesTheDeckSection    SC_010 还在牌库段
```

第 6 条 `testNoDeckListCardIsCountedAboveItsListCount` 修前就是绿的 —— 它不是复现，是给第 1 条那个新信号加的**回归护栏**（信号一旦误判牌表卡，牌库段的张数会超过牌表张数）。

### 第 1 条：同名副本洗入少算

**用的信号：实体当前在牌库区 + `info.created` + `CREATOR` / `DISPLAYED_CREATOR` 指向一个「有 cardId 的实体」。**
即「这张是某张牌造出来的」，不是「这张被标了 created」。

为什么不能只用 `info.created`（任务书线索里那条待验的）：**不成立**。用回放 fixture 打了一份
全实体 dump（`entity[.creator]` / `originalZone` / `originalController` / `created` / `turn`），结论：

- 洗进来的 6 张降落伞 `originalZone` **也是 `.deck`**（`FULL_ENTITY … tag=ZONE value=DECK` 直接进库，
  `TagChangeActions.zoneChange` 第 981-986 行拿 `value` 当 `originalZone`）。
  所以线索里「`originalZone != .deck` 且当前在库」这条**直接不成立**，fixture 4165 行一带可复现。
- 只用 `info.created` 会误伤：`zoneChangeFromOther`（`TagChangeActions:1122`）对**任何**从
  SETASIDE / GRAVEYARD 回到牌库的实体都打 `created = true`，`Player.createInDeck` 的 `created || turn > 1`
  同理。**探寻（dredge）就是 deck → setaside → deck**，所以被探寻过的牌表卡在库里 `created == true`，
  拿它当「洗入」信号会把牌库段的张数算多。这条比原来的少算更糟。
- 而 `CREATOR` 只有游戏**造新牌**时才写。dump 里：牌表卡 BT_490 `creator=1`（GameEntity，没有 cardId，
  被 `creatorHasCardId` 挡掉），其余牌表卡 `creator=0`；6 张降落伞 `creator=16`（帕奇斯本体，有 cardId）。
  三个条件与起来，fixture 四个检查点上只命中降落伞，一张牌表卡都没命中 —— 这正是
  `testNoDeckListCardIsCountedAboveItsListCount` 断言的东西。

算法相应改成加法而不是取大：

```
牌库段张数 = max( max(牌表张数 − 离开牌库张数, 0) + 洗入张数 , 已知在库张数 )
```

`max(…, 0)` 是给「牌表里没有、洗进来又被抽走」的牌（降落伞）留的；`已知在库` 退化成下限，
只在牌表不完整时起作用。Codex 的反例（2 张未揭示 + 1 张同名洗入）现在报 3。

**一处残留**（已知、没修）：牌表卡被抽出去之后又洗回牌库（不是探寻，是真正回到牌库），
它不在「离开牌库」里、也不带 CREATOR，所以按牌表那份算 —— 正确；但如果洗回来的是**洗入的副本**
被抽走，那 1 张会少算。信号是保守的：判不出来就退回 Bug T6 的行为，不会多算。

### 第 2 条：控制权变化

`entitiesThatLeftTheDeck` 的取数从 `playerEntities`（按**当前**控制者）换成 `revealedEntities`
再按 `info.originalController == self.id` 过滤（`originalController == 0` 时回退到当前控制者）。
这和旧 `getDeckState()` 的 `revealedEntities`（`isControlled || originalController == self.id`）同源，
但没有把旧函数搬过来 —— 只借了「按原控制者判归属」这一点，`info.created` 一概不碰。

顺带补一处**同源的漏**：`cardsInHandFromDeck` 原来数的是 `entity.isInHand`，不分谁的手牌。
我方牌被对手拿走后落在**对手手上**，于是「已打出段」的补集把它减掉，牌里凭空少一张。
加了 `entity.isControlled(by: self.id)`：手牌段本来就只看自己的手，两边现在一致。

**依据是实打实的**：留存 fixture 里就有这个局面 —— 跳虫 `SC_010`（实体 18，我方牌表卡）
在 4125 行被抽进手，4922 行 `tag=CONTROLLER value=2` 被对手拿走。
`testADeckCardGivenToTheOpponentLeavesTheDeckSection` 直接断言它：牌库段没有、手牌段没有、已打出段 1 张。

### 第 3 条：定制 Zilliax

`zoneGroups` 的四个取数（在库 / 手牌 / 离开牌库 / 其中在手）统一走新的 `zoneCardId(_:)`：
实体的 cardId 若是 Zilliax 装饰模块（`Card.zilliaxCustomizableCosmeticModule`），一律归一成基础 id
`CardIds.Collectible.Neutral.ZilliaxDeluxe3000`。牌表本来就是基础 id，减法这才对得上。

没有照旧路径「遇到装饰 id 就把基础 id 从牌表移除」的写法：那要先拿到 `game.currentDeck?.sideboards`，
对手侧没有；按卡库标记归一两侧通用，而且展示端不受影响 —— 我方侧 `annotateCards` 里的
`Helper.resolveZilliax3000` 照旧把基础 id 换成装饰卡（带合并后的费 / 攻 / 血），和平铺路径逐字同源。
**对手侧有一处可见变化**：对手的定制 Zilliax 现在按基础卡显示（对手侧不跑 `annotateCards`），
而牌表里写的就是基础卡，算一致，不算回退。

测试里的装饰模块用 `TOY_330t10`，并断言它在卡库里仍带 `zilliaxCustomizableCosmeticModule` 标记，
卡库换版本导致标记消失时会直接红，不会静默失效。

### 一个测试基建上的坑（别人也会踩）

`CardZoneGroupsTests` 按字母序跑在 `DatabaseTests` 前面，而宿主 app 的**卡库是后台异步加载的**：
第一次写的 Zilliax 测试拿到的是加载到一半的 `Cards.cards`（8405 张，`TOY_330t10` 还没进去），
表现为「卡库里没有这张牌」。加了 `waitForCard(_:)` 轮询等待。凡是在 `CardZoneGroupsTests` 里
读卡库的新测试都得这么等一下 —— `ZoneGroupsReplayTests` 等的是 `coreManager`，不是一回事。

### 不变式

没改定义，还是「每个 cardId：牌库 + 手牌 + |已打出| == 已知张数」「牌库段无 `count == 0`」。
洗入的副本算进「已知张数」，两条新的 `make` 测试都带 `assertNoCardIsLost` / `assertDeckHasNoZeroCount`。
对手侧的 `hidden` 过滤保住了：`shuffledIntoDeckByCardId` 和 `knownCardsInDeckZone` 一样带
`isLocalPlayer || !info.hidden`。

### 改了哪些文件

- `HSTracker/Logging/Player.swift` —— `CardZoneGroups.make` 加 `shuffledIntoDeck` 参数并改牌库段算式；
  新增 `zoneCardId(_:)` / `shuffledIntoDeckByCardId`；`entitiesThatLeftTheDeck` 改按原控制者；
  `cardsInHandFromDeck` 只数自己手上的；四处取数走 `zoneCardId`。
  `playerCardList` / `opponentCardList` / `getDeckState()` 一行没动，`Game.swift` 没动。
- `HSTrackerTests/CardZoneGroupsTests.swift` —— 新增 4 条（第 1 条 2 条纯函数、第 2 / 3 条各 1 条走
  `opponentCardGroups` 真实体）+ `waitForCard` / `makeGame` / `addPlayedDeckCard` 三个 helper。
- `HSTrackerTests/ZoneGroupsReplayTests.swift` —— 新增 2 条回放断言。

**没有新增文件，`project.pbxproj` 一行没动。**

### 验收

- `xcodebuild … clean build`（受限环境）：`** BUILD SUCCEEDED **`
- `xcodebuild … test`（受限环境）：`** TEST SUCCEEDED **`，`Executed 106 tests, with 0 failures`（原 100 + 新增 6）
- 🎮 待用户实测：带探寻的牌组（牌库段张数不许超过牌表张数）、被心灵控制 / 送牌的对局、
  带定制 Zilliax 的牌组。

### 修不了 / 只修一半 / 按规则没动

- **第 1 条只修了一半**：见上面「一处残留」—— 洗入的副本被抽走时会少算 1 张。要根治得在
  实体创建那一刻记一个「这是新造的」标志，那要动 `TagChangeActions` / `Game.swift`，本书不许。
- **降落伞类的牌进「已打出段」**：洗入的副本被抽走后按 `leftDeck` 算进已打出段，语义上它确实
  离开了牌库，但它从来不在牌表里。这是 T6 的既有形态，2.7 再定。
- **平铺路径的 `getDeckState()` 同源 bug 仍未修**（T6 执行结果里已记），本书一行没动。
- `DynamicEntity.init` 收 `extraInfo` 不赋值（`Player.swift:18`，上游遗留）仍未修，沿用现状。

## review（Claude，2026-09-15）通过

逐行核对了 `Player.swift` 的 diff 和 6 条新测试，自己跑了受限环境 `test`：106 / 106 全绿。

- 第 2 条按 `originalController` 判归属、`cardsInHandFromDeck` 只数自己手上的，两处与 `revealedEntities` 同源但没把 `info.created` 带回来，对。fixture 里跳虫被夺走的真实局面直接断言，依据硬。
- 第 1 条的 CREATOR 信号：三个条件（在库 + created + creator 是有 cardId 的实体）在 fixture 四个检查点上只命中降落伞，有回归护栏测试。算式 `max(max(牌表−离开,0)+洗入, 已知)` 对 Codex 反例（→3）、降落伞（→3）、「一张原版已抽 + 一张洗入」（→2）三种情况手推都对。残留（洗入副本被抽走少算 1）是保守方向，接受。
- 第 3 条按卡库标记归一，两侧通用；对手侧定制 Zilliax 显示为基础卡，与牌表一致，不算回退。
- 任务书里「`originalZone != .deck`」那条线索被证伪（降落伞 FULL_ENTITY 直接进库，`originalZone` 就是 `.deck`），记住：**`originalZone` 分不出洗入与原版**。
- 测试基建的坑（卡库异步加载，`CardZoneGroupsTests` 按字母序先跑）值得写进 `AGENTS.md` 测试一节，列入 strike-done 的下一步。

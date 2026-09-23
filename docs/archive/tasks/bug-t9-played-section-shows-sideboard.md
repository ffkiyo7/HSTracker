# Bug T9：分区模式「已打出」段把牛头人酋长（E.T.C. 乐队经理）的备牌当成打出的牌

先读 `docs/tasks/_common.md`，再读 `docs/tasks/bug-t6-zone-sections-stale.md`、`bug-t7-zone-accounting-edges.md`、
`bug-t8-shuffled-copy-drawn-stays-in-deck.md`（三段的定义、不变式、已证伪的信号都在那里）。

## 症状（用户，2026-09-17）

三行头 / 分区模式下，「已打出」段直接列出了 E.T.C. 乐队经理的备牌（sideboard）。备牌不在牌表主列表里，
从来没进过牌库，它们只属于面板上已有的「备牌」区（`Tracker.playerSideboardsData` / `playerSideboardsDict`），
不该出现在牌库 / 手牌 / 已打出任何一段。用户判定这是错误。

平铺模式没这个问题：`getDeckState()` 用 `copied_from_entity_id` 指向 set-aside 实体 + `info.createdInDeck` 识别
「从备牌拿出来的那张」，把它记进 `removedFromSideboards` 而不是 `removedFromDeck`。分区模式的取数
（`zoneGroups` 喂给 `CardZoneGroups.make` 的那几个列表）没有做同样的区分。

## 方向

分区三段只覆盖**牌表里的卡 + 洗入的副本**（T8 的 `wasShuffledIntoDeck`）。备牌来源的实体在哪一步混进来
（`entitiesThatLeftTheDeck` / `cardsInHandByCardId` / 别处）你自己查；识别信号优先复用 `getDeckState()` 已有的那套，
别再发明第二套。齐利亚克 3000 的备牌模块同理，一并验。

## 硬约束

- 不变式照旧：每个 cardId 牌库 + 手牌 + |已打出| == 已知张数（牌表 + 洗入）；备牌 cardId 不在任何一段。
- `playerCardList` / `opponentCardList` / `getDeckState()` 一行不动；平铺模式行为逐字一致。
- 备牌区本身的显示不变。
- **先失败再修**：至少一条测试先红 —— 「牌表含 E.T.C.，打出 E.T.C.，从备牌选一张到手再打出」，已打出段只该有 E.T.C.，
  备牌那张不在三段任何一段。回放 fixture 找不到就造单元测试并说明。
- T7 / T8 的回归护栏全部继续绿（现 112 条不改期望）。
- `_common.md` 规则照旧：不 commit、不动 PLAN / PROGRESS、`.xcstrings` 不动。

## 允许修改的文件

- `HSTracker/Logging/Player.swift`（仅 `zoneGroups` 及其喂料的私有列表）、`HSTracker/Logging/Entity.swift`、
  `HSTracker/Logging/Parsers/TagChangeActions.swift`（只加不改）
- `HSTrackerTests/CardZoneGroupsTests.swift`、`HSTrackerTests/ZoneGroupsReplayTests.swift`；新增 fixture 登记 pbxproj

## 验收

1. 受限环境 Debug build `BUILD SUCCEEDED`；112 条 + 新增全绿。
2. 报告里：备牌实体从哪条路混进已打出段、用的什么信号把它排除、为什么该信号在「从备牌拿到手再打出」之后仍可信、
   齐利亚克验了没有、对手侧要不要同样处理。

## 汇报

结果写进本文件末尾「执行结果」一节。**不要 commit、不要动 `docs/PLAN.md` / `docs/PROGRESS.md`**。

## 执行结果（2026-09-17）

修了。改了 5 个文件、没有新增文件，所以 `project.pbxproj` 一行没动。

### 备牌实体从哪条路混进已打出段

**不是从 `copied_from_entity_id` 那条路，是 `TagChangeActions.zoneChange` 的 setup 分支
（`TagChangeActions.swift:1084`，原 1067）把它们直接写成了牌库卡。**

证据是用户自己今天那局的日志 `/Applications/Hearthstone/Logs/Hearthstone_2026_09_17_22_31_34/Power.log`
（我方牛头人酋长 `ETC_080` = 实体 6，备牌 = 实体 34/35/36）。`CREATE_GAME` 里 158/168/185 行：

```
FULL_ENTITY - Creating ID=34 CardID=TOY_644      ← 备牌，cardId 当场就揭示
    tag=ZONE value=SETASIDE
    tag=CONTROLLER value=1
FULL_ENTITY - Creating ID=35 CardID=JAIL_205 …   tag=ZONE value=SETASIDE
FULL_ENTITY - Creating ID=36 CardID=GDB_142  …   tag=ZONE value=SETASIDE
```

`zoneChange` 收到 `prevValue = INVALID`，走 `case .invalid`；此时 `setupDone == false`
且 `id(34) <= maxId(67)`，于是执行 **`entity.info.originalZone = .deck`**，再进
`simulateZoneChangesFromDeck`，`value == SETASIDE` 那一支只打一个 `info.created = true` 就返回。
结果：备牌实体 `originalZone == .deck`、`created == true`、人在 SETASIDE、有 cardId、
`originalController == 我`。`Player.entitiesThatLeftTheDeck` 的条件是
「`originalZone == .deck` && `!isInDeck` && 原控制者是我」——**三条全中**，于是三张备牌
从开局第 0 回合就躺在已打出段里。先红的那一跑把这个原样打了出来：
`["ETC_080": 1, "JAIL_205": 1, "TOY_644": 1]`。

**平铺模式为什么没事**（和任务书里的猜测不同，值得记下）：不是靠
`copied_from_entity_id` + `createdInDeck` 那段——`getDeckState()` 里
`removedFromSideboardIds`（`Player.swift:912-921`）同时要求 `originalZone == .hand`
**和** `info.createdInDeck`（= `originalZone == .deck`），两者互斥，那个 filter 恒为空。
平铺模式真正的护栏是 `revealedNotInDeck` 的第一条 `!info.created`：备牌被打上了 `created`，
直接被挡在 `removedFromDeck` 之外。这条上游遗留的矛盾条件**没动**，见末节。

另外：被选中的那张备牌**不是**上面这三个实体。ETC 打出时游戏又造三个副本
（22:42:50 一带，实体 184/185/186，`COPIED_FROM_ENTITY_ID` 分别指回 36/35/34），
选中的那个 SETASIDE → HAND。它是**中局**创建的，`setupDone` 已经是 true，
走不到那条 setup 分支，`originalZone` 最终是 `.hand`，所以它本来就进不了已打出段。
（2026-09-14 那份留存日志里 ETC 的备牌是**打出 ETC 时**才创建的 —— 实体 186/187/188，
也没有 setup 分支的问题。所以这个 bug 只在「备牌在 CREATE_GAME 就建好」的形状下出现，
今天 09-17 的日志就是这个形状。）

### 用的什么信号

**`Entity.wasSetAsideAtSetup`，在解析时落闩**，与 T8 的 `wasShuffledIntoDeck` 同一套做法。

- 字段加在 `Entity`（`EntityInfo.swift` 不在允许修改的文件里，沿用 T8 的选择），
  `Entity.copy(with:)` 里补一行同步。
- 落闩点：`TagChangeActions.markSetAsideAtSetup(entity:value:)`，**只在**上面那条
  `entity.info.originalZone = .deck` 的**后一行**追加调用，条件只有一个：
  `value == SETASIDE`。即「setup 阶段被直接造进 SETASIDE 的实体」。
  原有的 `originalZone` / `created` 赋值一个字没改（`_common.md` 的「只加不改」）。
- 解闩：`zoneChange` 开头加一句「`value == DECK` 就清掉」。这类实体要是**真的**进了牌库
  （fixture 里的抉择半张 `EX1_164a/b` 就有 SETASIDE → DECK 的形状），从那一刻起它就和别的
  在库副本一样，由 T8 的 `wasShuffledIntoDeck` 接手，行为与修前逐字相同。
- 取数端：`Player.entitiesThatLeftTheDeck` 加一道 `guard !entity.wasSetAsideAtSetup`。

**为什么这个信号在「从备牌拿到手再打出」之后仍然可信**：因为被拿到手的根本不是落闩的那个实体。
落闩的是 CREATE_GAME 建的 34/35/36，它们**永远留在 SETASIDE**，闩一直有效；
玩家拿到手的是中局新造的副本 184/185/186，从来没落过闩，靠 `originalZone == .hand`
自然落在三段之外。就算游戏哪天改成把原实体本身挪进手里，闩也跟着实体走
（落闩只在创建那一刻判一次，之后不再回头看区域），照样排除。

### 齐利亚克验了

验了，**同一条路、同一处修复**。齐利亚克的模块也是 CREATE_GAME 直接造进 SETASIDE 的，
所以同样被写成 `originalZone = .deck`；更糟的是 T7 的 `zoneCardId` 会把装饰模块的 id 归一成
基础 id `ZilliaxDeluxe3000`，于是**一张没打的定制齐利亚克从开局就显示成「已打出」，
同时从牌库段消失**。新增 `testZilliaxModulesAreInNoZoneSection` 断言这两条，修前两条都红：

```
testZilliaxModulesAreInNoZoneSection
  XCTAssertTrue failed - nothing has been played yet
  XCTAssertEqual failed: ("nil") is not equal to ("Optional(1)") - the assembled Zilliax is still in the deck
```

### 对手侧要不要同样处理

**代码是同一条路，已经一起修了，但对手侧实际上碰不到这个 bug。**
`entitiesThatLeftTheDeck` 是 `Player` 上的属性，我方和对手侧共用，落闩在解析层不分阵营。
不过对手的备牌在 `CREATE_GAME` 里是**没有 cardId 的**（只有我方的备牌当场揭示），
而 `revealedEntities` 要求 `hasCardId`，所以对手的备牌本来就进不了任何一段。
对手打出 ETC 后揭示出来的那张，走的是中局创建那条路（`originalZone == .hand`），同样不受影响。
结论：不需要额外处理，也没有为对手侧单独写测试。

### 不变式

定义没改。有一处措辞要说准：任务书写的「备牌 cardId 不在任何一段」，实现上是
**备牌实体不进牌库段和已打出段**；那张被选到手、还没打出的备牌**仍然在手牌段里**——
它确实就在手上，手牌段的定义（T6：手上全部有 cardId 的实体）不允许把它藏起来，
藏了反而会让手牌段又一次对不上真实手牌。打出之后它从三段里一起消失，这正是
`testTheSideboardIsInNoZoneSection` 断言的终局。牌表侧的不变式
「牌库 + 手牌 + |已打出| == 牌表 + 洗入」不受影响：备牌 cardId 的牌表张数是 0，
它既不从牌表扣，也不往牌表加。

### 先失败：4 条新测试里 3 条红

把两处行为改动退回原样（**`Entity.wasSetAsideAtSetup` 字段保留**，否则测试编译不过）：
`TagChangeActions` 里那一行 `markSetAsideAtSetup` 调用删掉、`Player.entitiesThatLeftTheDeck`
的 `guard` 删掉。跑 `CardZoneGroupsTests`：

```
Executed 23 tests, with 6 failures (0 unexpected)
testSideboardCardsCreatedAtSetupAreLatchedAsNeverHavingBeenInTheDeck
  XCTAssertTrue failed - it was created set aside, it was never in the deck
testTheSideboardIsInNoZoneSection
  XCTAssertEqual failed: ("["ETC_080": 1, "JAIL_205": 1, "TOY_644": 1]") is not equal to ("["ETC_080": 1]")
      - only E.T.C. was played out of the deck list
  XCTAssertNil failed: "1"   ×2   （TOY_644 / JAIL_205 在已打出段）
testZilliaxModulesAreInNoZoneSection
  XCTAssertTrue failed - nothing has been played yet
  XCTAssertEqual failed: ("nil") is not equal to ("Optional(1)") - the assembled Zilliax is still in the deck
** TEST FAILED **
```

第 4 条 `ZoneGroupsReplayTests.testTheSetAsideAtSetupSignalNeverLandsOnADeckCard` 修前就是绿的
—— 它是**回归护栏**，不是复现：回放的那副牌没有备牌，护栏断言的是新信号**不误伤**
（牌表卡、洗入副本、在库的卡一律不许带这个闩）。信号一旦放宽，它立刻红。

### 改了哪些文件

- `HSTracker/Logging/Entity.swift` —— 加 `wasSetAsideAtSetup` 字段 + 在 `copy(with:)` 里同步。
- `HSTracker/Logging/Parsers/TagChangeActions.swift` —— 新增 `markSetAsideAtSetup`，
  从 setup 分支**追加**一行调用；`zoneChange` 开头加「进牌库就解闩」。原有赋值一行没改。
- `HSTracker/Logging/Player.swift` —— `entitiesThatLeftTheDeck` 加一道 `guard`（+ 注释）。
  `playerCardList` / `opponentCardList` / `getDeckState()` 一行没动。
- `HSTrackerTests/CardZoneGroupsTests.swift` —— 新增 3 条（1 条走真实解析入口验落闩、
  2 条走 `playerCardGroups` 真实体验三段）+ `setActiveDeck` / `createSideboardCardAtSetup` 两个 helper。
- `HSTrackerTests/ZoneGroupsReplayTests.swift` —— 新增 1 条回放护栏。

**没有新增文件，`project.pbxproj` 一行没动。**

### 验收

- `xcodebuild -project HSTracker.xcodeproj -scheme HSTracker -configuration Debug -destination 'platform=macOS' build`：`** BUILD SUCCEEDED **`
- `xcodebuild … test`：`** TEST SUCCEEDED **`，`Executed 126 tests, with 0 failures (0 unexpected) in 187.157 (187.864) seconds`
  —— **基线是 122 不是任务书写的 112**：工作区里 V2a / V2b 的未提交改动已经给
  `TrackerMetricsTests` 等加了 10 条。T7 / T8 的护栏（`testNoDeckListCardIsCountedAboveItsListCount`、
  `testTheShuffledInSignalIsLatchedOnTheShuffledInCopiesOnly`）全绿。
- 🎮 待用户实测：带牛头人酋长的牌组，看已打出段开局是不是干净的、选一张备牌打出后已打出段只多本体；
  带定制齐利亚克的牌组，看齐利亚克是不是老实待在牌库段。
  `open ~/Library/Developer/Xcode/DerivedData/HSTracker-cgfkydaatbcvlygsoujdqwiezsjx/Build/Products/Debug/HSTracker.app`

### 修不了 / 只修一半 / 按规则没动

- **`getDeckState()` 的 `removedFromSideboardIds` 是一段死代码**（`Player.swift:912-921`）：
  filter 同时要求 `info.originalZone == .hand` 和 `info.createdInDeck`（= `originalZone == .deck`），
  互斥，恒为空。也就是说**平铺模式的「备牌区已用掉的牌」从来没被扣减过**——
  备牌区永远显示 3 张全满。这是上游遗留，`getDeckState()` 按任务书一行不动，没修。
- **抉择半张之类的 setup SETASIDE 实体**（fixture 里的 `EX1_164a/b`）以前也会混进已打出段，
  现在一并被排除了。这是同一个根因的顺带修复，方向是对的（它们从来不在牌表里），
  但不在用户报告范围内，记一笔。
- **上游那条 `originalZone = .deck` 本身没改。** 它影响的不只是分区取数
  （`createdInDeck` 在别处也有读者），改语义的风险远大于加一个闩，所以走的是 T8 的老路子。
  代价是这条错误的归属仍然存在，只是分区路径不再信它。
- **「备牌拿到手后仍显示在手牌段」是有意的**，理由见「不变式」一节。要改成「手牌段也不显示备牌」
  得先定「手牌段到底是手牌还是牌表的手牌」，是另一本书的事。
- T8 记过的那几条（对手侧 `handToDeck` 置 `hidden` 造成的缺口、不写 creator 的洗入判不出来、
  平铺 `getDeckState()` 同源 bug）本书一条没动。

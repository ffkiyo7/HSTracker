# Bug T10：牌库段的行张数和事实对不上（发挥优势只剩 1 张却显示 2）

先读 `docs/tasks/_common.md`，再读 `bug-t6` / `bug-t7` / `bug-t8` / `bug-t9` 四本（三段定义、不变式、已证伪的信号），
以及 `perf-p2-vector-rows-compositing-cost.md` 的「缓存键与失效」一节。

## 症状（用户，2026-09-19，Perf P1 + P2 的包 `143db6f3`）

截图（用户口述 + Claude 读图）：

- 段头「牌库 (3)」，但牌库段画出来的三行是：第三道阿古斯传送门 ×1、**发挥优势 ×2**、**幽灵视觉 ×2** —— 行加起来是 5。
- 段头「手牌 (3)」，但手牌段只画了两行：无底海渊、巨怪塔迪乌斯（★）。
- 已打出段里已经有一张发挥优势。用户确认：整套牌只有两张发挥优势，没有被复制过。所以牌库里应该只剩 1 张。

**段头的数字是同一个 `viewModel.rows` 的张数之和**（`TrackerSectionView`），它和画出来的行对不上 ——
要么行画的是旧的，要么段头是旧的，要么两者都来自错账。这一点先分清，别直接当成分区取数 bug 去修。

## 证据

- 日志已留存：`~/Desktop/dev/HSTracker-logs/2026-09-19-bug-t10-Power.log`，第 4 局（`CREATE_GAME` 在第 42593 行，12:28:39），我方是 `player=2`。
- `END_007`（发挥优势）两个实体：id=57 在 12:31:32 **回合开始正常抽到**（无 creator、不是洗入）、12:31:46 打出；id=60 在 12:32:29 才被抽到、12:32:38 打出。
  塔迪乌斯（id=59，`NX2_033`）起手被换回牌库，12:32:14 再抽到。所以截图时刻大约在 **12:32:14 – 12:32:29**：此时牌库里的发挥优势事实上只有 id=60 一张。

## 先做这一步（决定往哪修）

用现有回放设施（`ZoneGroupsReplayTests` 那套）把这份日志回放到上述时间窗口，读出 `playerCardGroups` 的三段：

- **算出来就是 发挥优势 ×2** → 分区取数错账。查 `CardZoneGroups.make` 的 `known` 下限、T8 的 `shuffledLeftDeck`、
  换牌回库的实体（塔迪乌斯那条路）有没有把别的卡带歪；幽灵视觉 ×2 一并对账。
- **算出来是 ×1、段合计 3** → 数据是对的，**画出来的行是旧的**。嫌疑是 Perf P2 的位图缓存路径（行没重画 / 键没变 / SwiftUI 跳过了 body）
  或 Perf P1 的同值跳过。手牌段少画一行也要一起解释。

两条路哪条成立、用什么证明的，写进报告。两条都不成立就如实说，别硬修。

## 硬约束

- **先失败再修**：先有一条红的测试复现截图里的状态（回放 fixture 或最小单测），再改。
- 不变式照旧：每个 cardId 牌库 + 手牌 + |已打出| == 牌表 + 洗入；段头合计 == 该段画出来的行张数之和。
- `getDeckState()` / 平铺模式一行不动；P2 的逐像素外观不变、四个诊断键保留。
- 现有 145 条测试不改期望。
- `_common.md` 规则照旧：不 commit、不动 PLAN / PROGRESS、`.xcstrings` 不动。

## 允许修改的文件

- `HSTracker/Logging/Player.swift`（仅分区取数一族）、`HSTracker/Logging/Entity.swift`、`HSTracker/Logging/Parsers/TagChangeActions.swift`（只加不改）
- `HSTracker/UIs/Trackers/SwiftUI/` 下全部文件
- `HSTrackerTests/` 下现有文件只加不改；新增 fixture / 测试文件登记 pbxproj（fixture 只截需要的那一局，别把 8MB 整个放进仓库）

## 验收

1. Debug build `BUILD SUCCEEDED`；145 条 + 新增全绿。
2. 报告里：根因是哪条路、证据、先红后绿的输出、幽灵视觉和手牌段少一行是不是同一个根因、哪条修不了直说。
3. 给用户的 🎮 验法和启动命令。

## 汇报

结果写进本文件末尾「执行结果」一节。**不要 commit、不要动 `docs/PLAN.md` / `docs/PROGRESS.md`**。

## 执行结果（2026-09-19）

**判定：不是分区取数错账，是画出来的行是旧的。** 修的是 Perf P2 的行视图，`Player.swift` /
`TagChangeActions.swift` / `Entity.swift` 一行没动。

### 先做这一步：回放，读出三段

**先纠正一处：截图不是第 4 局，是第 1 局（`CREATE_GAME` 在第 2 行，12:13:00）。**
任务书按 `END_007` 的实体号定位到第 4 局（12:28:39），但第 4 局对不上 ——
那一局里牌库段从来没有同时出现过幽灵视觉、发挥优势和阿古斯传送门（12:32:14–12:32:29 的牌库段
是 `发挥优势 1 / 轻蔑印记（后为最后一道阿古斯传送门）1 / 大型法术欧珀石 1`，手牌 6~7 张）。
第 1 局逐张对得上，连两个段头的数字都对得上：

| 局 | 12:1x / 12:3x 窗口里的牌库段 | 与截图 |
|---|---|---|
| 第 4 局 12:32:14–29 | 发挥优势 1、大型法术欧珀石 1、轻蔑印记 / 最后一道阿古斯传送门 1 | ✗ 没有幽灵视觉、没有第三道 |
| **第 1 局 12:17:49** | **第三道阿古斯传送门 1、发挥优势 1、幽灵视觉 1** | ✓ 三行逐张相同 |

第 1 局的相关时刻（我方 `player=2`，牌库是实体 51…80）：

```
12:15:15  SHOW_ENTITY id=68 CORE_BT_491（幽灵视觉）在牌库 → 抽到
12:15:19  id=68 打出
12:15:53  SHOW_ENTITY id=59 END_007（发挥优势）在牌库 → 抽到
12:16:10  id=59 打出              ← 窗口起点：发挥优势只剩 id=60 一张在库
12:17:37  第二道阿古斯传送门 id=136 打出，洗入第三道 id=229
12:17:49  塞纳留斯之斧 id=70 打出  ← 截图就在这一拍之前
12:18:32  幽灵视觉 id=61 抽到并打出 ← 窗口终点
```

回放（`ZoneGroupsT10ReplayTests`，喂 `2026-09-19-bug-t10.log`）在 12:17:49 读出的三段：

```
deck   ["CORE_BT_491": 1, "END_007": 1, "TIME_020t4": 1]     → 3 行，合计 3
hand   ["NX2_033": 1, "TIME_020t1": 1, "TSC_608": 1]         → 3 行，合计 3
```

**算出来是 ×1、段合计 3 —— 数据是对的**，走的是任务书第二条路。
两个段头「牌库 (3)」「手牌 (3)」和这份数据**逐字一致**（`TrackerSectionView.copies` 就是
`rows` 的 `abs(count)` 之和），而画出来的行不是：发挥优势和幽灵视觉各多画了一个「2」的数字框，
手牌段少画一行。三段合计 == 已知张数的不变式在窗口内每个检查点都成立
（`testNoDeckListCardIsCountedAboveItsListCount`、`testHandSectionMatchesTheHandThroughTheWindow`）。

顺带排掉的两条：第 1 局我方 `wasShuffledIntoDeck` 只落在阿古斯传送门那一串上
（136 / 229），没有一张牌表卡被误闩；`wasSetAsideAtSetup` 全程为空。T8 / T9 的信号都没问题。

### 根因：SwiftUI 跳过了行的 `body`，因为 `Card` 的 `==` 只比 id

`HSTracker/Database/Models/Card.swift:477`：

```swift
static func == (lhs: Card, rhs: Card) -> Bool {
    return lhs.id == rhs.id
}
```

`Card` 是 class，`CardRowView` 把它当存储属性拿着。SwiftUI 判断要不要重跑 `body` 时比较
新旧 view 值，比到 `card` 这一项就用上面这个 `==` —— **同一张牌的两次刷新永远相等，张数从
2 掉到 1 也相等**。于是 `CardRowView.body` 不再执行：`rasterKey` 不重算、位图缓存不查，
行就一直挂着它第一次被光栅化时的那张图。

所以发挥优势在 12:15:53 之前是「牌库里 2 张」，那一刻的位图带着数字框「2」；之后张数掉到 1，
`viewModel.rows` 更新了、段头跟着变了，**行却再没重画过**。幽灵视觉同理（12:15:15 之前是 2）。
第三道阿古斯传送门是 12:17:37 才新出现的行，位图是新的，所以它画对了 ×1 —— 截图里三行的对错
分布正好印证这条：**只有"曾经是别的样子"的行是错的**。

P2 的缓存键（19 个字段，含 `count`）没有问题，`NSCache` 也没有问题：键根本没被重新算过。
这也是为什么 P1 / P2 之前看不出来 —— 跳过 `body` 连矢量画法也一样跳，只是那时没人盯着张数。

### 先红后绿

新增 `TrackerMetricsTests.testACountChangeRepaintsTheRow`：把一张 count=2 的牌喂进
`TrackerCardListViewModel`，挂进真的 `NSHostingView` 画一遍，再喂 count=1 画一遍，
比 `TrackerRowRaster.lookups` 和 `cacheDisplay` 出来的像素。修之前：

```
TrackerMetricsTests.swift:630: error: testACountChangeRepaintsTheRow :
  XCTAssertGreaterThan failed: ("1") is not greater than ("1")
  - the row's body was skipped, so it still shows the old count
TrackerMetricsTests.swift:635: error: testACountChangeRepaintsTheRow :
  XCTAssertNotEqual failed: ("[173, 124, 51, 255, 173, 124, 51, 255, …]") …
  - the count box still reads 2
** TEST FAILED **
```

`lookups` 停在 1 —— 张数变了之后 `body` **一次都没再跑**，两次画出来的像素逐字节相同。
修完三条全绿：

```
Test Case '-[HSTrackerTests.TrackerMetricsTests testACountChangeRepaintsTheRow]' passed (0.132 seconds).
Test Case '-[HSTrackerTests.TrackerMetricsTests testAnUnchangedRowIsStillNotRedrawn]' passed (0.272 seconds).
Test Case '-[HSTrackerTests.TrackerMetricsTests testARowInsertedAboveOthersLeavesNoBlankStripe]' passed (0.143 seconds).
** TEST SUCCEEDED **
```

`testAnUnchangedRowIsStillNotRedrawn` 是**对照组**，修前修后都绿：没变的行刷新三次
`TrackerRowRaster.renders` 一次不涨。P2 的收益必须留着，修法不能变成「每帧全部重画」。

### 修法：`==` 就用光栅键

`CardRowView` 加 `Equatable`，`TrackerCardListView` 的调用点加 `.equatable()`，
让 SwiftUI 用我们的 `==` 而不是它自己那套（那套会落到 `Card.==` 上）。

比较的内容**直接复用 `CardRowContentView.rasterKey`** —— 那本来就是「决定这一行长什么样的全集」，
再手写一遍字段清单等于把同一个坑往下挪一层：下次多一个外观输入，就要在两处记得改。
两个 `==` 够不到的输入（`@State` 的 `tile`、`@Environment` 的 `isHandSection`）在两边都钉成同一个值，
因为 SwiftUI 对自己的 state / environment 变化本来就会失效；`flattensToBitmap` 和 `playerType`
不在键里，单独比。

### 改了哪些文件

- `HSTracker/UIs/Trackers/SwiftUI/CardRowView.swift` —— 加 `comparableContent` 和
  `extension CardRowView: Equatable`（比较 = 光栅键 + `flattensToBitmap` + `playerType`）。画法一行没动。
- `HSTracker/UIs/Trackers/SwiftUI/TrackerCardListView.swift` —— 行视图后面加 `.equatable()` 和一句
  「这不是优化，是修 bug」的注释。
- `HSTrackerTests/TrackerMetricsTests.swift` —— 新增 3 条（复现 + 插行不留空条 + 对照组）和
  `paint(_:rows:window:host:)` helper（挂 `NSHostingView` 取真实像素）。
- `HSTrackerTests/ZoneGroupsReplayTests.swift` —— 新增 `ZoneGroupsT10ReplayTests` 5 条：
  截图那一拍的三段、发挥优势只剩 1、幽灵视觉只剩 1、手牌段逐张等于手牌、牌表张数上限护栏。
- `HSTrackerTests/Fixtures/ZoneReplay/2026-09-19-bug-t10.log` —— 新增 fixture，第 1 局
  `CREATE_GAME` 到 12:18:45，按 `LogReaderManager` 的过滤条件原样截
  （`GameState.` / `PowerTaskList.DebugPrintPower` / `PowerProcessor.EndCurrentTaskList` 三路全留，
  18243 行 / 2.24 MB）。
- `HSTracker.xcodeproj/project.pbxproj` —— fixture 登记 Resources 4 处。本次 pbxproj 只有这一项。

`Player.swift` / `Entity.swift` / `TagChangeActions.swift` **一行没动**，`getDeckState()` /
平铺模式自然也没动；P2 的四个诊断键、逐像素外观都没动。

### 修不了 / 怀疑但没证实

- **手牌段少画一行，没能独立复现。** 数据侧证据是硬的：12:17:49 手牌段就是
  `无底海渊 / 塞纳留斯之斧 / 巨怪塔迪乌斯` 三行，截图只画了第一和第三。新增的
  `testARowInsertedAboveOthersLeavesNoBlankStripe`（两行之上插一行，逐条带检查非空）
  **修前就是绿的**，所以「插行导致空条」这条不成立。我倾向于它和数字框是同一个根因的另一面
  （那一行在此之前一直存在，`body` 从没重跑过，而它的外观确实没变过 —— 那就不该是空的），
  但拿不出证据，也可能只是截图裁掉了。**这条请 🎮 实测时重点看。**
- **段头和行"来自同一个 `rows`"这句话是对的**，任务书担心的「两者都来自错账」不成立：
  `TrackerSectionView.copies` 和 `TrackerCardListView` 在同一个 `body` 里读同一个数组，
  不可能来自两个快照 —— 所以「段头 3 / 行加起来 5」这个矛盾本身就已经指向画面，回放只是坐实了。
- **回放用的牌表是从 30 个 `CREATE_GAME` 实体反推的**（实体 51…80，全局都揭示过），
  不是 HearthMirror 那份。两者应当一致（牌库物理上就是这 30 张），但没法离线核对。
- **`Card.==` 只比 id 这件事本身没改。** 它是上游的，`Card.swift` 不在允许修改的文件里，
  而且别处（去重、`contains`）依赖这个语义。本次只在行视图这一处绕开它。
  **同类风险仍在**：任何拿 `Card` 当 SwiftUI view 存储属性的地方都会踩，
  目前只有 `CardRowView` 和 `TrackerCardRowSensor`（后者是 `NSViewRepresentable`，
  `updateNSView` 每次都赋值，不受影响）。
- **`Card.textColor()` 依赖的几个 Settings（`playerInHandColor` / `highlightLastDrawn` …）
  改了以后行不会重画**，因为它们既不是行的存储属性也不在 publish 路径上。
  这是修本 bug 时看到的同族问题，范围之外，没动。
- **fixture 2.24 MB**，比 T6 那份（764 KB）大。这一局从 `CREATE_GAME` 到截图时刻就有这么长，
  砍 `GameState.DebugPrintOptions` 能省 13%，但那就不是「原样截」了，不划算。

### 验收

- `xcodebuild -project HSTracker.xcodeproj -scheme HSTracker -configuration Debug -destination 'platform=macOS' build`：`** BUILD SUCCEEDED **`
- `xcodebuild … test`：`** TEST SUCCEEDED **`，
  `Executed 153 tests, with 0 failures (0 unexpected) in 191.242 (191.922) seconds`
  —— 原 145 + 新增 8（`TrackerMetricsTests` 3 + `ZoneGroupsT10ReplayTests` 5）。
  T6 / T7 / T8 / T9 的护栏（`testNoDeckListCardIsCountedAboveItsListCount`、
  `testTheShuffledInSignalIsLatchedOnTheShuffledInCopiesOnly`、
  `testTheSetAsideAtSetupSignalNeverLandsOnADeckCard`）全绿，
  P2 的 `testColdAndWarmRasterCost` / `testFlatteningCollapsesTheRowLayerTree` /
  `testFlattenedRowIsTheSamePicture` 也全绿 —— `.equatable()` 没有改变层数、外观和缓存命中率。
- 🎮 待用户实测（这个 bug 只有实战能最终确认，回放证明不了"画出来的是什么"）：
  打一局，**盯一张两张的牌**：抽走一张之后牌库段那一行的数字框必须从 2 变 1（而不是继续显示 2）；
  再看**手牌段的行数是不是等于段头的数字**。
  `open ~/Library/Developer/Xcode/DerivedData/HSTracker-cgfkydaatbcvlygsoujdqwiezsjx/Build/Products/Debug/HSTracker.app`

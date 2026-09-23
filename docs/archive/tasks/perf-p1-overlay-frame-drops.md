# Perf P1：overlay 开着时炉石掉帧（面板刷新路径的四处无谓开销）

先读 `docs/tasks/_common.md`。本书是 Codex 2026-09-17 排查报告（`/private/tmp/hstracker-performance-findings.md`，
临时文件、可能已不在；要点已全部抄进下文）的落地。

## 症状（用户，2026-09-17）

overlay 开启时炉石整体帧数不稳、明显卡顿；退出 HSTracker 恢复；**只关掉玩家 / 对手两个面板也恢复**；
抽牌、出牌、悬停时最明显。环境：3840×2160 165Hz，炉石 3840×1874 / 165FPS，Debug 包，`HSTRACKER_LATENCY_PROBE=1`。
退出 HSTracker 后 GPU 仍到过 92%，所以 GPU 占用不能单独归罪面板。

Codex 报告没能用修前后帧时间对照锁定唯一根因；Claude 已逐条核对代码，下面四条**都是真的**，
按报告建议的顺序修，**每改一条就单独测一次**，别一口气全改再说「好了」。

## 已核实的四处（按修的顺序）

1. **窗口每次刷新都同步提交 WindowServer 事务。** `WindowManager.show(controller:show:frame:title:overlay:)`
   每次调用无条件 `setFrame(_:display:true)` 和 `orderFront`，没有「位置 / 可见性没变就跳过」的检查。
   `Game.updatePlayerTracker` / `updateOpponentTracker` 每次 GUI tick（16ms 去抖）都走到它。
   采样里主线程 254 个样本卡在 CA 事务提交 → `SLSConnectionSetLastSLSCATransaction` → unfair lock。
   这是首要嫌疑：它直接和游戏的合成路径抢 WindowServer。
2. **一次分区刷新算四遍 `getDeckState()`。** `Player.playerCardGroups` 三个分区各自 `annotateCards`，
   `annotateCards` 又读 `playerSideboardsDict`（`getDeckState()` 一次）；`Game.swift` 传 `sideboards:` 时再读一次。
   平铺模式是三遍。`getDeckState()` 遍历全部 revealed entities 做分组，不便宜。
3. **每次刷新都读一次 Realm 并开一个空写事务。** `Game.swift` 刷新里 `RealmHelper.getDeck(with:)` 只为算
   战绩标签；`getDeck` 无条件调 `validateCardCounts`，后者**没有 `count > 30` 的卡也照样 `realm.write {}`**。
   Realm 空事务仍要拿文件锁、提交。dense 和 lag-now 两份采样都抓到这条路径。
4. **同值 `playerType` 每次刷新触发 7 个 `@Published` 通知。** `Tracker.update` 每次给 `viewModel.playerType` 赋值，
   `TrackerViewModel.playerType.didSet` 无条件转发给 7 个列表的 `@Published var playerType`，
   SwiftUI 因此每次刷新都收到 7 次 `objectWillChange`，即使值根本没变。`rows` / `showRarityColors` 都做了同值跳过，就它没做。

## 方向

- 第 1 条：**只在帧 / 可见性 / 层级 / collectionBehavior / styleMask 真变了才提交**。但 `orderFront` 不能简单换成
  `!isVisible`：Space 切换、炉石前后台切换（`Events.space_changed` / `hearthstone_active` / `hearthstone_deactived`）
  后窗口要保持在游戏之上的正确层级。这些事件本来就走 `updateAllTrackers`，怎么区分「日常刷新」和「必须重新置前」你定，报告里给理由。
  `controller.updateFrames()` 是否也该受同样的门控，一并判断。
- 第 2 条：一次刷新只算一次 `getDeckState()`，算出来的东西在 `playerCardGroups` / `playerCardList` / `playerSideboardsDict`
  之间怎么传你定。**不许**改 `getDeckState()` 的语义、不许缓存跨刷新（T6 / T7 / T8 的账都靠它每次现算）。
- 第 3 条：读之前先判断有没有要修的卡，没有就不开写事务；战绩标签要不要按 `currentDeck.id` 缓存到 `reload_decks` / 局结束再失效，你定。
- 第 4 条：`Tracker` 和 `TrackerViewModel` 两层都加同值跳过。

## 硬约束

- **不要先删阴影、改画质、把锅推给 Debug。** 报告明说了，这次也不许。
- 视觉、内容、分区行为、悬停高亮、tooltip 一律不变。Phase 2 / V1 / V2 已落地的样式一像素不动。
- 每条改完跑一次同场景对照：`HSTRACKER_LATENCY_PROBE=1` 下「D tick → UI committed」和 `player tracker` 块的 p50 / p95，
  修前修后各记一次写进报告（改前基线：玩家面板 p50 9.9ms / p95 28.4ms / max 95.1ms；D p50 40.1ms / p95 172.4ms）。
  探针只量 HSTracker 自己的提交耗时，**不等于炉石帧耗时**，报告里别混着说。
- 现有 126 条测试全绿（`68ccc14e` 后的基线）；分区 / 回放测试（`CardZoneGroupsTests` / `ZoneGroupsReplayTests` / `TrackerMetricsTests`）不许改期望。
- `_common.md` 规则照旧：不 commit、不动 PLAN / PROGRESS、`.xcstrings` 不动。

## 允许修改的文件

- `HSTracker/UIs/Trackers/WindowManager.swift`
- `HSTracker/Logging/Game.swift`（仅 `updatePlayerTracker` / `updateOpponentTracker` 及其直接辅助）
- `HSTracker/Logging/Player.swift`（仅 `playerCardList` / `playerCardGroups` / `annotateCards` / `playerSideboardsDict` 一族）
- `HSTracker/Database/RealmHelper.swift`（仅 `getDeck` / `validateCardCounts`）
- `HSTracker/UIs/Trackers/Tracker.swift`、`HSTracker/UIs/Trackers/SwiftUI/TrackerViewModel.swift`、
  `HSTracker/UIs/Trackers/SwiftUI/TrackerCardListViewModel.swift`
- 测试：可新增，`HSTrackerTests/` 下现有文件只加不改

## 验收

1. 受限环境 Debug build `BUILD SUCCEEDED`；126 条 + 新增全绿。
2. 报告里按 1→4 分别给：改了什么、为什么这样区分「要不要提交」、修前修后的探针数字、哪条没效果直说。
3. 报告末尾列出**你没动但怀疑的**下一批候选，Claude 已知的两条先写这里，实现者补充或反驳：
   - `Game.housekeepingTick` 每 250ms 做 `CGWindowListCopyWindowInfo` + 4 次跨进程 AX 调用打进炉石主线程
     （`SizeHelper.hearthstoneWindow.reload()`），165FPS 下一帧只有 6ms，AX 请求会让游戏主线程停下来应答。
     用户「只关面板也恢复」的证据不指向它，所以本书不修；但若 1→4 修完仍卡，它是第一候选。
   - 悬停 → `highlightPlayerDeckCards` → 4 个列表各自 `setHighlight` 重算 rows，再加 400ms 后 tooltip 窗口走一遍
     `WindowManager.show`。第 1 条修好后它自然受益，单独不动。

## 汇报

结果写进本文件末尾「执行结果」一节。**不要 commit、不要动 `docs/PLAN.md` / `docs/PROGRESS.md`**。
🎮 实测由用户做：报告里给启动命令 `open <DerivedData>/Build/Products/Debug/HSTracker.app`，并说明要用
`HSTRACKER_LATENCY_PROBE=1` 环境变量启动才有探针数字。

## 执行结果（2026-09-18）

四条都改完了，**每条单独跑过一次 Debug build**，四次都 `BUILD SUCCEEDED`。探针数字这边补不了
（没有炉石可开），下面每条给的是代码级证据 + 用户实测的方法。

### 1. `WindowManager.show` 不再每次刷新提交 WindowServer 事务

`WindowManager.swift`：`setFrame` 加 `window.frame != frame` 前置；`level` / `collectionBehavior` /
`styleMask` 三处原本就有同值跳过，现在每处真改了就置 `attributesChanged = true`；`orderFront` 改为只在
`WindowManager.shouldOrderFront(...)` 为真时调用。隐藏分支的 `orderOut` 也加了 `window.isVisible` 门控。

**怎么区分「日常刷新」和「必须重新置前」**——四个理由，任一成立就 `orderFront`：

1. `!window.isVisible`：窗口根本没 order in（首次显示、`show:false` 之后再显示、`hideGameTrackers` 之后）。
2. `!window.occlusionState.contains(.visible)`：被别的窗口整个盖住。这条专门覆盖「被盖住后重新置前」，
   不依赖任何事件。
3. `attributesChanged`：这次刷新真写了 frame / level / collectionBehavior / styleMask —— 这些写操作本身
   就可能改变窗口在 WindowServer 里的次序，所以配一次 `orderFront`。
4. `pendingReorder`：**Space 切换 / 炉石前后台切换**。`WindowManager.reorderEvents` =
   `space_changed` / `hearthstone_active` / `hearthstone_deactived` / `hearthstone_running` /
   `hearthstone_closed`，`startManager()` 自己订阅这五个事件，命中就 `orderFrontGeneration += 1`；
   每个窗口记住自己上次置前用的 generation，下一次 `show()` 时不等就置前一次。
   这五个事件本来就在 `Game.allTrackerUpdateEvents` 里，`startManager()` 在 `Game` 注册观察者**之前**执行，
   所以 generation 一定先于那一轮 `updateAllTrackers` 的主队列块被加上。

**证据**：`shouldOrderFront` 是纯函数，`TrackerMetricsTests` 新增三条测试锁住
「什么都没变 → 不置前」「四个理由各自 → 置前」「五个事件都在 `reorderEvents` 里」。

**没能覆盖的场景（老实说）**：别的 app 的窗口**部分**盖住面板、又没触发上面五个事件时，
`occlusionState` 仍报 `.visible`，面板要等到下一次事件才会重新置前。改之前每 tick 无条件 `orderFront`
会顺手修掉这种情况。判断是可接受的代价：代价是罕见的局部遮挡要等一次事件，收益是每 tick 少一次
和炉石抢 WindowServer 的事务。

`controller.updateFrames()` **没有**受同样的门控，理由：它是唯一把表头状态（手牌 / 牌库计数、战绩、
职业）推进 SwiftUI view model 的路径，按「frame 没变就跳过」会把表头冻住；而且它的开销是进程内布局，
不是 WindowServer 提交。

**探针**：用户实测时对比 `player tracker` 块的 p50 / p95（改前基线 9.9 / 28.4ms，max 95.1ms）。
另外可用 `sample HSTracker` 看主线程还有没有样本卡在 `SLSConnectionSetLastSLSCATransaction`。

### 2. 一次刷新只算一次 `getDeckState()`

`Player.swift` 新增 `playerTrackerSnapshot(useZoneGroups:)`，一次 `getDeckState()` 出
`cards` / `groups` / `sideboards` 三样；`annotateCards` 改成接收 `sideboards:` 参数而不是自己去读
`playerSideboardsDict`；`getPlayerSideboards(_:)`（那个参数从来没被用过）换成
`playerSideboards(from: DeckState)`。`playerCardList` / `playerCardGroups` 两个属性保留（测试在用），
各自内部也只算一次。`Game.updatePlayerTracker` 改成取一次 snapshot。
`getDeckState()` 的语义没动，也没有跨刷新缓存。

**证据**：`Player.deckStateEvaluations` 计数器 + `CardZoneGroupsTests` 新增四条测试：
分区模式一次刷新 == 1 次、平铺模式 == 1 次、没有 deck 时 == 0 次、snapshot 的三段和平铺列表与旧属性逐卡相等。
改前是分区 4 次 / 平铺 3 次。

### 3. 刷新不再开空写事务，战绩标签按 deck id 缓存

`RealmHelper.validateCardCounts` 前面加 `guard needsCardCountFix(deck)`：没有 `count > 30` 的卡就直接返回，
连 `try? Realm()` 都不做，更不会 `realm.write {}`。

`Game.deckRecordLabel(for:)`：战绩标签按 `currentDeck.id` 缓存，失效点三个 —— `Events.reload_decks`
（改牌 / 存牌 / 导入 / 战绩上传后都会发）、`gameEnded` 翻转（对局中战绩不会变，一局结束就重算）、
以及 `handleEndGame` 里 `RealmHelper.addStatistics(to:stats:)` 之后。
观察者第一次用到时懒注册，挂进 `Game.observers` 由 `deinit` 清理。所以稳定态下一次刷新既不读 Realm
也不遍历 `deck.statistics`。

**第三个失效点是 review 补的回归修复**：`addStatistics` 那条路径不发 `reload_decks`，而顺序是
`gameEnded` 先翻 true → 刷新一次（把「存战绩前」的旧标签写进缓存）→ 之后才 `addStatistics`，
结果局后菜单里的战绩要等下一局开始才更新，改前是立即更新。现在 `addStatistics` 之后
`DispatchQueue.main.async { self.invalidateDeckRecordLabel() }` —— `handleEndGame` 不在主线程，
而 `cachedRecordLabel` 只在主线程读写，所以失效必须 hop 过去。

**证据**：`DatabaseTests` 新增两条 —— 正常牌组 `needsCardCountFix == false`（不开写事务），
`count = 31` 的牌组仍会被修成 1（守卫没把修复逻辑关掉）。

### 4. 同值 `playerType` 不再触发 7 次 `objectWillChange`

`TrackerViewModel.playerType.didSet` 加 `guard oldValue != playerType`，转发时再按
`where list.playerType != playerType` 过一遍；`Tracker.update` 赋值前也比一次。

**证据**：`TrackerMetricsTests.testSamePlayerTypeDoesNotNotifyTheLists` 订阅七个列表的
`objectWillChange`：重复赋同值 0 次通知，真的改值 7 次通知。

### 构建与测试

```
xcodebuild -project HSTracker.xcodeproj -scheme HSTracker -configuration Debug -destination 'platform=macOS' build
→ ** BUILD SUCCEEDED **

xcodebuild -project HSTracker.xcodeproj -scheme HSTracker -configuration Debug -destination 'platform=macOS' test
→ 135 passed / 1 failed（126 基线 + 新增 10 条 = 136）
```

唯一失败是 `SecretTests.testSingleSecret_OpponentDamage()`（`"Optional(false)" is not equal to "Optional(true)" - Evasion`）。
**不是本次改动造成的**：`git stash` 到干净 HEAD 后单跑 `-only-testing:HSTrackerTests/SecretTests` 同样失败；
而且两次单跑失败集合不一样（一次还多一条 `testSingleSecret_OneMinionDied()`），是这台机器上的既有 flake。
新增的 10 条全绿，现有测试的期望一条没改。

### 🎮 实测怎么跑

```
open /Users/wadorudi/Library/Developer/Xcode/DerivedData/HSTracker-cgfkydaatbcvlygsoujdqwiezsjx/Build/Products/Debug/HSTracker.app
```

要探针数字必须带环境变量启动（`open` 不传环境变量，用下面这条）：

```
HSTRACKER_LATENCY_PROBE=1 /Users/wadorudi/Library/Developer/Xcode/DerivedData/HSTracker-cgfkydaatbcvlygsoujdqwiezsjx/Build/Products/Debug/HSTracker.app/Contents/MacOS/HSTracker
```

看 `D tick → UI committed` 和 `player tracker` 两块的 p50 / p95。
**探针只量 HSTracker 自己的提交耗时，不是炉石的帧耗时**，两者别混着说；炉石那边看游戏内 FPS 显示。

### 没动但怀疑的下一批候选

1. （任务书已列）`Game.housekeepingTick` 每 250ms 的 `CGWindowListCopyWindowInfo` + 4 次跨进程 AX
   （`SizeHelper.hearthstoneWindow.reload()`）。**核对属实**，代码里那段注释自己就写明「4 blocking
   cross-process AX calls」。1→4 修完还卡就先动它。
2. （任务书已列）悬停 → `highlightPlayerDeckCards` → 4 个列表各自 `setHighlight` 重算 rows + 400ms 后
   tooltip 走 `WindowManager.show`。第 1 条修完后 tooltip 那一半已经受益。
3. **新增**：`Tracker.updateFrames()` 每次刷新都重算整套布局，opponent 侧还每次
   `removeTrackingArea` + `addTrackingArea` 重建 tracking area。它现在是刷新路径里最重的进程内部分
   （第 1 条把 WindowServer 那部分砍掉之后更明显）。要拆的话得先把「表头数据更新」和「几何重算」
   分开，本书范围内没动。
4. **新增（bug，不是性能）**：`WindowManager.appliedWindowTitles` 在 `show(show: false)` 分支里没被清掉，
   但那条路径会 `NSApp.removeWindowsItem(window)`。窗口再显示时标题没变 → `addWindowsItem` 被跳过 →
   窗口不会回到「窗口」菜单里。是 `appliedWindowTitles` 那次改动就带进来的既有 bug，本次没顺手改。

## 🎮 实测结果（用户 2026-09-18 晚，Claude 读 `~/Library/Logs/HSTracker/hstracker.log`）

**仍卡，关掉双方记牌器后恢复。四条修复没有命中根因。**

- 记牌器开着的窗口（21:54–22:06，n=204）：`player tracker` 块 p50 **12.8** / p95 **29.6** ms，
  修前基线 9.9 / 28.4 —— **没降**。`D tick → UI committed` p50 180 / p95 724 ms，其中 54.5% 是
  `first main-queue wait`（avg 142ms），不在任何面板块里。
- 记牌器关掉之后（22:12 起）：`player tracker` 归零，但 `first main-queue wait` 仍 avg ≈96ms。
  也就是说 **HSTracker 主线程一样堵，炉石却不卡了** —— 炉石掉帧不跟 HSTracker 的 CPU 走，跟「面板窗口在不在屏上」走。
- 回读 Codex 的 dense 采样：主线程 66% 在等事件；那 254 个 CA 提交样本挂在 `UpdateCycle → stepTransactionFlush`
  （常规显示周期提交）下面，**不在 `setFrame` 下面**；`updatePlayerTracker` 整个闭包只占主线程约 3.6%。
  任务书第 1 条把它归到 `setFrame(display:true)` 是 Claude 核对时的误判。
- 当前设置：`use_swiftui_tracker = 1`、`card_size = 2`、`tracker_opacity = 50`。

**现在的判断**：成本在 WindowServer / GPU 侧 —— 面板内容每次变化（抽牌 / 出牌 / 悬停高亮）都要重新合成一块
不透明度 50% 的大窗口，叠在 4K 165Hz、GPU 已经 92% 的游戏上面。这是推断，还没证实；下一步先做不改代码的 A/B
（切回旧 AppKit 面板、不透明度拉满），定位到是 SwiftUI 面板（V1 矢量卡条 / V2b 原画铺满 / 文字阴影）还是窗口半透明本身，再写 Perf P2。
四条改动本身是真浪费、测试全绿，保留与否由用户定。

# Bug T1：watcher 后台回调直接写 SwiftUI view model，导致主线程死锁

## 背景

2026-08-30 实战中 HSTracker 主线程死锁 790 秒，直到用户强制退出。表现是所有 overlay
冻在最后一帧且**永不消失** —— 跟着用户从对局到排队页、到炉石主菜单、甚至叠在终端窗口上；
悬停高亮、相关牌浮窗、牛头人酋长一类的提示全部失效；对手卡牌标记和回合计时器一直挂在屏幕上。

系统抓到了 hang report：`/Library/Logs/DiagnosticReports/HSTracker_2026-08-30-173357_wadomarkm4.hang`
（`Event: hang`，`Duration: 790.21s`，起始 17:20:25，对局中）。主线程栈：

```
Game.updatePlayerTracker
  → Tracker.update(cards:top:bottom:sideboards:relatedCards:reset:)   Tracker.swift:131
    → TrackerCardListViewModel.playerType.setter                      @Published
      → Published.withMutation → PublishedSubject.send
        → ObservableObjectPublisher.Inner.send()
          → __ulock_wait2
            (blocked by turnstile waiting for HSTracker thread 0x26101a)
```

`0x26101a` 是 **`DiscoverStateWatcher` 线程**（同一份报告里 `Thread name "DiscoverStateWatcher"`，
`last ran 789.115s ago`，卡在 `__psynch_cvwait`）。两个线程同时改同一个 `ObservableObject`
的 `@Published` 存储，抢 Combine publisher 的内部锁，互等。

根因是 `Watchers.swift:133`：

```swift
private static func onDiscoverStateChange(_ sender: DiscoverStateWatcher, _ args: DiscoverStateArgs) {
    let game = AppDelegate.instance().coreManager.game
    game.setRelatedCardsTrigger(args)
    if game.isTraditionalHearthstoneMatch {
        game.windowManager.playerTracker.highlightPlayerDeckCards(highlightSourceCardId: args.cardId)
    }
}
```

这个回调跑在 `DiscoverStateWatcher` 自己的 `DispatchQueue` 上、**每 16ms 一次**
（`DiscoverStateWatcher.swift:27,53-68`）。`highlightPlayerDeckCards`（`Tracker.swift:825`）
会走到 `swiftUICards?.viewModel.setHighlight(fn)`，而 `setHighlight`
（`TrackerCardListViewModel.swift:106-112`）直接写 `@Published rows`，全程没有主线程跳转。
本机 `use_swiftui_tracker = 1`，走的正是这一支。

**这不是孤例，是同一条规则漏了一半。** 仓库里已经有做对的对照组，且注释写明了规则
（`Game.swift:5061` 那段「This runs on the DiscoverStateWatcher queue… 每次访问都要在主线程」）：

| 位置 | 修复前现状 |
|---|---|
| `Watchers.swift:133` → `highlightPlayerDeckCards` | ❌ **已实证死锁** |
| `Watchers.swift:106` → `battlegroundsHeroPicking.viewModel.isViewingTeammate` | ❌ |
| `Game.swift:4758-4769` `setDeckPickerState` → 四个 view model 属性 | ❌ |
| `Game.swift:4242-4244` `setChoicesVisible` → `viewModel.choicesVisible` | ❌ |
| `Game.swift:1074-1077` `setBaconState` → 三个属性 | ❌（同函数 `:1079` 的 visibility 部分反而跳了主线程） |
| `Game.swift:4275-4281` `handleShopBoardState` | ✅ |
| `Game.swift:5036-5054` `onBigCardChange` | ✅ |
| `Game.swift:5065-5073` `setRelatedCardsTrigger` 的 `cardId == ""` 分支 | ✅ |

上表是本轮顺手扫出来的，**不保证穷尽**，见要求 1。

## 全面排查清单（2026-08-30）

先从 `Watchers.initialize()` 的全部注册点反查到 16 个 watcher 的 `run()`：它们都创建自己的
串行 `DispatchQueue`，事件闭包就在该队列调用。再沿每个闭包追到 `Game` / `CoreManager` /
`SceneHandler` 的间接写入；最后反查仓库内显式的后台队列、`Task.detached` 与所有
`@Published` / `objectWillChange` 写点。

| watcher 入口 | 可观察 / UI view model 写入路径 | 处理结论 |
|---|---|---|
| `ArenaWatcher.onCompleteDeck` | `Game.set(activeDeck:)` 最终刷新 tracker | 保留；组装牌组不碰 view model，赋值和 tracker 刷新已在 main block |
| `BaconWatcher.change` | `setBaconState` 的模式、弹窗状态、session 模式 | **已修**；三项和依赖它们的 visibility 刷新合进同一个 main block |
| `BattlegroundsLeaderboardWatcher.change` | `_leaderboardHoveredEntityId` 后触发 overlay `update()` | 保留；前者是未观察的普通缓存，真正的 AppKit 更新已异步回主线程，不会进入 Combine publisher |
| `BattlegroundsLobbyInfoWatcher.change` | `Game.battlegroundsLobbyInfo` | 保留；只写上传用的普通游戏元数据，没有 publisher / `propertyChanged` |
| `BattlegroundsTeammateBoardStateWatcher.change` | `battlegroundsHeroPicking.viewModel.isViewingTeammate` | **已修**；回调先异步回主线程 |
| `BigCardWatcher.change` | tracker 高亮、tooltip、`hoveredAnomalyCard` | 保留；`hoveredCard` 是普通游戏状态，三个 UI / `@Published` 写入原本就在同一个 main block |
| `ChoicesWatcher.change` | `battlegroundsTrinketPicking.viewModel.choicesVisible` | **已修**；setter 在 main block 内执行 |
| `SpecialShopChoicesStateWatcher.change` | Timewarp toast、`battlegroundsMinionPinning.onShopChange` | 保留；两个 toast 方法及 pinning 入口都各自在内部异步回主线程 |
| `DeckPickerWatcher.change` | 旧 pre-lobby view model 三项 + SwiftUI widget 两项 | **已修**；比较、写入和派生更新全部在同一个 main block |
| `DiscoverStateWatcher.change` | 相关牌 tooltip + tracker `setHighlight` | **已修**；tooltip 两个分支原本已回主线程，漏掉的高亮现也先回主线程；hover / exit 的主线程调用仍同步执行，没有多一帧延迟 |
| `DungeonRunDeckWatcher` 两个事件 | 选牌组后刷新 tracker；其余为 Realm 数据 | 保留；`Game.set(activeDeck:)` 的赋值 / 刷新已回主线程，数据更新不经过 publisher |
| `ExperienceWatcher.newExperienceHandler` | 旧 AppKit experience panel | 保留；不含 `@Published`、`ObservableObject` 或 `objectWillChange`，重绘已在 main block；不属于本次 Combine 争锁面 |
| `PlayZoneWatcher.change` | `battlegroundsMinionPinning.onShopChange` | 保留；`handleShopBoardState` 已异步回主线程 |
| `PVPDungeonRunWatcher` 两个事件 | 与普通 dungeon watcher 相同 | 保留；可观察的 tracker 刷新最终在 main block，其他是 Realm 数据 |
| `QueueWatcher.inQueueChanged` | `setConstructedQueue` 两个 view model；`setBaconQueue`；`Game.reset` | **补扫发现并已修** `setConstructedQueue`，两项合进同一个 main block；另两路的 visibility / SwiftUI reset 原本已回主线程 |
| `SceneWatcher.change` | pre-lobby / 战棋 visibility；离开战棋时 `invalidateUserState` | **补扫发现并已修** `invalidateUserState`；其余 view model 写入已有 main block。`invlidateAllDecks` 只清未观察缓存，保留 |

非 watcher 的明确后台入口也逐项反查：

| 后台入口 | 可观察写入 | 结论 |
|---|---|---|
| `Game._queue` / `_windowQueue` 的 tracker 与跟窗刷新 | `TrackerCardListViewModel`、turn counter、资源 widget、RootOverlay 各 view model | 保留；所有写入均由对应 `update*` 方法派到主线程，hang 栈里的主线程写正来自这条正确路径 |
| 16ms mulligan live poll 与日志解析回调 | mulligan V2、战棋 minion / quest、pinning、资源 widget | 保留；调用点已有 main block，相关选择 / trinket async handler 标为 `@MainActor` |
| `Task.detached` 的战棋 / pre-lobby API 加载 | guides、composition、widget 的 `@Published` 状态 | 保留；写入段使用 `MainActor.run` 或目标方法标为 `@MainActor` |
| counter 的 `propertyChanged` 与图片加载完成回调 | `CounterChipViewModel` 及图片型 view model 的 `@Published` | 保留；桥接闭包均先派到主线程 |
| `CoreManager` 的应用启动、退出、前后台通知 | stop/reset 与 pre-lobby widget 状态 | 保留；监听器明确指定 `OperationQueue.main` |

本轮没有保留任何已确认会在后台触发 publisher / `propertyChanged` 的写入；也没有加入锁、
`main.sync`、节流或去抖。

## 允许修改

- `HSTracker/Hearthstone/Watchers.swift`
- `HSTracker/Logging/Game.swift`
- `HSTracker/UIs/Trackers/Tracker.swift`
- `HSTracker/UIs/Trackers/SwiftUI/` 下的 view model
- 其他经要求 1 的排查确认存在同类问题的文件
- `AGENTS.md`
- `docs/PROGRESS.md`
- 本任务书

不要修改上述范围外的文件，不要 `git add` 或 commit，不要动 `.xib`，
不要动 `HSTracker.xcodeproj/project.pbxproj`（这次不涉及新增文件）。

> ⚠️ `Game.swift` 里带 `[trackervis]` 标记的三处临时诊断代码（`logTrackerVisibility`
> 及其两个调用点、`cacheGameType` 里那行）是本轮排查用的，**不要删也不要改**。
> 它们负责验收，等这一轮验完再单独删。

## 要求

1. **先把面扫全，再动手。** 背景里那张表是抽查结果，不是清单。需要系统地列出**所有**
   从 watcher 回调 / 非主线程路径写入 `@Published`、`ObservableObject` 属性或
   `objectWillChange` 的位置 —— 包括经由 `Game` 的方法间接写入的。把清单写进本任务书。
   有意保留不改的，要逐条说明为什么它不会与主线程争锁。

2. **修法必须是把写入搬到主线程，不许用锁绕。** 不要给 view model 加互斥量、不要换成
   自定义串行队列、不要把 `@Published` 换成手动 `objectWillChange`。SwiftUI / Combine
   的契约就是主线程，绕过去只会把死锁挪个位置。

3. **同一个回调里的一组写入要落在同一个 main block 里。** 不要给每个属性 setter 各包一个
   `DispatchQueue.main.async` —— 那会让本来一次提交的状态被拆成多帧，产生中间态闪烁。
   `setDeckPickerState` 和 `setBaconState` 各自那几行属于同一批。

4. **不要引入 `DispatchQueue.main.sync`。** 这些回调线程可能已经持有别的锁，`sync` 会把
   一个死锁换成另一个。

5. **不得改变触发时序到影响手感。** `DiscoverStateWatcher` 是 16ms 轮询，高亮必须仍然跟手；
   不许为了"安全"加节流、去抖或延迟。已有的 `curr == _prev` 去重是够的。

6. **不要顺手重构 `Tracker.update` 或 `TrackerCardListViewModel` 的数据流。** 这一轮只解决
   线程归属。Phase 1 的 T5 / T6 还没做，大改会和后面撞车。

7. 如果决定让 `setHighlight` 这类 view model 方法自己保证主线程（而不是每个调用点各自跳），
   要保证已经在主线程的调用路径（`Tracker.swift:850`、`:926` 的 hover / exit）
   **不会被推迟一帧**，否则悬停高亮会变钝。哪种做法都行，但要说明选择理由。

8. **战棋相关的三处（`isViewingTeammate`、`choicesVisible`、`setBaconState`）静态改对即可。**
   用户不玩战棋，验收不排"打一局战棋"。改动要能从代码上讲清楚正确性。

9. 在 `AGENTS.md` 里留下一条可检的规则：watcher 回调在自己的队列上跑，任何写 SwiftUI
   view model 的路径都必须先回主线程。写清楚为什么（Combine publisher 锁 + 主线程渲染），
   并留下这次 hang report 的路径作为证据锚点。

## 验收

1. 构建：受限环境 Debug build `BUILD SUCCEEDED`。

   ```sh
   env -u http_proxy -u https_proxy -u all_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
     PATH=/usr/bin:/bin:/usr/sbin:/sbin \
     xcodebuild -project HSTracker.xcodeproj -scheme HSTracker \
     -configuration Debug -destination 'platform=macOS' build
   ```

2. 🎮 **实战一局标准模式**，必须同时满足：
   - 全程不卡死；对局结束后 `/Library/Logs/DiagnosticReports/` 下**没有**新的
     `HSTracker_*.hang`；
   - 对局中反复悬停牌库里的卡，协同高亮**每次都出**（这条路径就是死锁现场，不出说明改坏了）；
   - 相关牌浮窗、发现/三选一的提示正常；
   - 打完回主菜单，记牌器该消失时消失 —— 这次的"排队页 / 主菜单 / 终端上都不消失"
     本质是主线程死了没人 `orderOut`，修好后应自然恢复。

3. 日志核对（临时诊断还在，正好用）：

   ```sh
   grep '\[trackervis\]' ~/Library/Logs/HSTracker/hstracker.log
   ```

   进队列应看到 `player show=true … inQueue=true deckTrackerQueue=true`，
   且**全程有 `show=false` 的翻转出现**（上一轮死锁后就再没打出过任何一行，
   因为主线程根本没跑到）。

4. 最后检查完整 diff：没有遗留的后台写入、没有新加的锁、没有 `main.sync`、
   没有把诊断代码删掉。

## 备注

排队残留那本（`docs/tasks/phase6-t1-queue-residue.md`）的代码本身是对的 ——
本轮诊断日志证明排队时我方记牌器判定 `show=true`、对手判定 `show=false`，两个都正确。
用户看到的"对手记牌器残留"是这个死锁的表象，不是显示条件写错。

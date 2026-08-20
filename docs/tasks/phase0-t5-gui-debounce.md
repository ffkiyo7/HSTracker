# Phase 0 / T5 — GUI 刷新由轮询改为防抖调度

先读 `docs/tasks/_common.md` 里的通用约束，再读本文件。

## 背景（决定了本任务的形状，请先读懂再动手）

现在的机制：`updateTrackers()`（`Game.swift:243`）只把 `guiNeedsUpdate` 置为 true，
由 `internalUpdateCheck()`（`:1562`）每 100ms 轮询一次消费它。

2026-08-21 的 Release 版埋点实测（`docs/PROGRESS.md`）显示：

```
C 置位 -> tick 消费    n=101  p50=106.9  p95=195.3  max=199.7   ← 就是这个轮询
D tick -> UI 提交      n=102  p50=20.1   p95=273.5  max=409.2
E2E 日志行 -> UI       n=89   p50=309.8
```

**C 段的 p50 是一个完整周期，不是半个。** 因为对局激烈时日志事件几乎不断，
每个 tick 刚把标志清掉、下一个请求立刻又置上，于是每次刷新都要等满一整拍。
它占 E2E 的 35%，是目前最大的一块可控成本。

## 目标文件

- `HSTracker/Logging/Game.swift`（主要改动）
- `HSTracker/Utility/LatencyProbe.swift`（**只允许改两处注释/日志文案**，见改动 6）

**除这两个文件外一律不许改。**

## 改动 1 — 常量与状态

`Game.swift:42` 现有 `static let guiUpdateDelay: TimeInterval = 0.1`。
它改动之后的含义变成「杂务循环的周期」，请**改名为 `housekeepingInterval`** 并保持 `0.1`。

新增：

```swift
/// 请求到达后合并刷新的窗口。取一帧多一点：再小就压不住突发日志，
/// 再大就把 C 段的收益还回去了。
static let guiUpdateDebounce: TimeInterval = 0.016
```

新增两个只在 `_queue` 上访问的状态（放在 `guiNeedsUpdate` / `guiUpdateResets` 旁边）：

```swift
private var guiUpdateScheduled = false
private var guiUpdateInFlight = false
```

新增一条串行队列（放在 `_queue` 声明旁边）：

```swift
private let _windowQueue = DispatchQueue(label: "net.hearthsim.hstracker.windowpoll", attributes: [])
```

## 改动 2 — `updateTrackers()` 置位后顺手排一次刷新

`Game.swift:243`。保持它「只置标志、不直接重绘」的语义不变，**51 个调用点一个都不要动**，
只在置位之后调用调度函数：

```swift
func updateTrackers(reset: Bool = false) {
    _queue.async {
        LatencyProbe.shared.updateRequested()
        self.guiNeedsUpdate = true
        self.guiUpdateResets = reset || self.guiUpdateResets
        self.scheduleGuiUpdate()
    }
}
```

## 改动 3 — 调度与执行（本任务的核心）

两个新函数，**都只允许在 `_queue` 上调用**：

```swift
/// 必须在 _queue 上调用。
private func scheduleGuiUpdate() {
    guard !guiUpdateScheduled, !guiUpdateInFlight else { return }
    guiUpdateScheduled = true
    _queue.asyncAfter(deadline: .now() + Game.guiUpdateDebounce, execute: {
        self.runGuiUpdate()
    })
}

/// 必须在 _queue 上调用。
private func runGuiUpdate() {
    guiUpdateScheduled = false
    guard guiNeedsUpdate else { return }
    guiNeedsUpdate = false
    guiUpdateInFlight = true
    LatencyProbe.shared.updateStarted()
    updateAllTrackers()
    guiUpdateResets = false
    // updateAllTrackers() 只是把 20 个块排进主队列。主队列是 FIFO，
    // 所以排在它们之后的这个块跑到时，那一轮刷新才算真的做完。
    DispatchQueue.main.async {
        self._queue.async {
            self.guiUpdateInFlight = false
            if self.guiNeedsUpdate {
                self.scheduleGuiUpdate()
            }
        }
    }
}
```

### ⚠️ 两个必须理解的点，写错了会造成比现在更糟的回归

1. **不要实现「每次请求都重置定时器」那种经典防抖。** 那是 trailing-edge debounce，
   日志密集时请求永不停歇 → 定时器被无限推后 → **overlay 永远不刷新**。
   这里要的是「第一个请求排一次，窗口内后续请求全部被吸收」，
   即 `guard !guiUpdateScheduled` 那一行的作用。**改完请自己复述一遍这个区别。**

2. **`guiUpdateInFlight` 不是可选的。** 没有它，一轮刷新还堵在主线程上时下一轮就会被排进去；
   D 段 p95 有 273ms 而防抖窗口只有 16ms，堆积是必然的。有了它，下一轮最早也要等上一轮
   在主线程上真正做完 —— 节奏自动变成「刷新耗时 + 16ms」，不会压垮主线程。

## 改动 4 — 杂务循环拆出去，别再和刷新抢同一条队列

`internalUpdateCheck()`（`:1562`）现在干三件事：轮询窗口矩形（250ms 节流）、
消费 `guiNeedsUpdate`、无条件调 `updateBoardOverlay()`。第二件事已由改动 3 接管，
把剩下两件改名为 `housekeepingTick()` 并**搬到 `_windowQueue` 上**：

```swift
/// 在 _windowQueue 上自循环。
private func housekeepingTick() {
    let now = Date().timeIntervalSince1970
    if now - lastWindowPoll >= Game.windowPollInterval {
        lastWindowPoll = now
        let rect = SizeHelper.hearthstoneWindow.frame
        // fullscreen-flag flips can leave _frame unchanged but still shift the 50px game-menu offset
        let wasFullscreen = SizeHelper.hearthstoneWindow.isFullscreen()
        SizeHelper.hearthstoneWindow.reload()
        if rect != SizeHelper.hearthstoneWindow.frame
            || wasFullscreen != SizeHelper.hearthstoneWindow.isFullscreen() {
            _queue.async { self.applyWindowChange() }
        }
    }

    self.updateBoardOverlay()

    _windowQueue.asyncAfter(deadline: .now() + Game.housekeepingInterval, execute: {
        self.housekeepingTick()
    })
}

/// 必须在 _queue 上调用。窗口矩形变了，所有 overlay 都要按新位置重画。
private func applyWindowChange() {
    guiNeedsUpdate = true
    scheduleGuiUpdate()
    updateBattlegroundsOverlays()
}
```

搬走的理由要写进代码注释（一两行即可）：`reload()` 是 4 次阻塞式跨进程 AX 调用，
留在 `_queue` 上会把下一拍刷新整个推后 —— 实测 C 段 p95 195ms（约两拍）多半就是它。

**为什么 `applyWindowChange()` 不照抄原来的 else 分支**：原分支是
`updateAllTrackers()` + `updateBattlegroundsOverlays()` + 另外 4 个方法，
而那 4 个（`updateConstructedMulliganOverlays` / `updateActiveEffects` /
`updateMaxResourcesWidget` / `updateRootOverlay`）`updateAllTrackers()` 里已经调过了，
只有 `updateBattlegroundsOverlays()`（复数）是它没有的。所以走调度 + 补那一个即可，语义不变。

启动处 `:1541` 的 `_queue.async { self.internalUpdateCheck() }` 相应改为
`_windowQueue.async { self.housekeepingTick() }`。**GUI 刷新不再需要启动循环**，
它现在完全由请求驱动。顺手删掉 `:1544` 那两行注释掉的 `while true` / `Thread.sleep` 死代码。

## 改动 5 — 堵掉两处绕过 `updateTrackers()` 的直接置位

`Game.swift:857` 和 `:868` 有两处直接写 `self.guiNeedsUpdate = true`，不走 `updateTrackers()`。

**这是本任务最容易漏掉的地方。** 现在有 100ms 轮询兜底，所以它们照样能生效；
改成事件驱动之后，**这两处置位将永远等不到刷新**（除非碰巧有别的请求路过）。
而且它们分别跑在主线程和调用者线程上，本来就是对 `_queue` 私有状态的数据竞争。

两处都改为调用 `updateTrackers()`。`:857` 在一个 `DispatchQueue.main.async` 块里，
改成 `self.updateTrackers()`；`:868` 改成 `updateTrackers()`。
不要改这两处附近的其它任何逻辑。

改完自查，`guiNeedsUpdate` 的赋值点应当只剩下 `_queue` 上那几处：

```
grep -n "guiNeedsUpdate" HSTracker/Logging/Game.swift
```

## 改动 6 — 让埋点的文案跟上

`LatencyProbe.swift` 只允许改这两处**文案**，不许动任何逻辑：

- `:93` 的注释 `Game.internalUpdateCheck, where the tick picks the flag up.`
  → 改为指向 `Game.runGuiUpdate`
- `:148` 日志里的 `<- guiUpdateDelay` → 改为 `<- debounce`

## 明确不要动

- **`updateTrackers()` 的 51 个调用点一个都不要动**，包括不要把任何一处改成直接重绘。
  合并机制是刻意设计的，日志密集时每事件直接重绘会被淹没。
- **不要动 `updateAllTrackers()` 里那 20 个 update 方法**，也不要改它们的顺序。
- **不要动 `windowPollInterval = 0.25`**，也不要改 `updateBoardOverlay()` 的 100ms 节奏
  （它现在由 `housekeepingInterval` 承担，值不变）。
- **不要动 `LatencyProbe` 的三个埋点位置和语义**：`updateRequested()` 仍在
  `updateTrackers()` 的 `_queue` 块里、`updateStarted()` 仍紧邻 `updateAllTrackers()` 之前、
  `updateCommitted()` 保持在 `:415` 不动。这三处一动，和 8-20 / 8-21 两轮基线就没法比了。
- 不要顺手把 `guiUpdateDebounce` 调成别的值。16ms 是有理由的初值，调优要拿探针数据说话。

## 验收

1. 构建通过。按 `_common.md` 的命令跑，改的是 `.swift`，普通环境即可：

   ```
   cd /Users/wadorudi/Desktop/dev/HSTracker
   xcodebuild -project HSTracker.xcodeproj -scheme HSTracker \
     -configuration Debug -destination 'platform=macOS' build
   ```

2. `grep -n "guiNeedsUpdate" HSTracker/Logging/Game.swift` 的输出里，
   除声明外的每一处赋值都在 `_queue` 上（`updateTrackers` / `runGuiUpdate` / `applyWindowChange`）。
3. `grep -rn "internalUpdateCheck\|guiUpdateDelay" HSTracker/` 应当只剩
   `SizeHelper.swift:139` 那条历史注释（**那条不要动**，它讲的是另一件事）。
4. `git diff --stat` 只有 `Game.swift` 和 `LatencyProbe.swift` 两个文件。

## 报告里请额外回答

- 用你自己的话说明「本任务要的合并语义」和「经典 trailing-edge debounce」的区别，
  以及你的实现为什么不会在日志密集时饿死。
- `guiUpdateInFlight` 在什么情况下会挡住一次调度，挡住之后那次请求由谁负责补上。

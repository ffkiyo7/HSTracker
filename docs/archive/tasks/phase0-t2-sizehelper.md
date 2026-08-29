# Phase 0 / T2 — 把 Accessibility 调用移出主线程

先读 `docs/tasks/_common.md` 里的通用约束，再读本文件。

## 目标文件

- `HSTracker/Core/SizeHelper.swift` —— 主要改动，`class HearthstoneWindow` 的 `reload()`（约 37-118 行）
- `HSTracker/Logging/Game.swift` —— 只允许改**一行**：把 `updateAllTrackers()` 里那句 `SizeHelper.hearthstoneWindow.reload()`（约 209 行）删掉

**本任务只允许修改这两个文件，且 `Game.swift` 只能动那一句。**

## 问题

`HearthstoneWindow.reload()` 一次调用会做：

1. `CGWindowListCopyWindowInfo` —— 快照系统上所有窗口的元数据
2. `AXUIElementCreateApplication(pid)` —— **每次都重新创建**
3. 四次阻塞式的跨进程 Accessibility 调用：`kAXFocusedWindowAttribute`、`AXFullScreen`、
   `kAXPositionAttribute`、`kAXSizeAttribute`

AX 调用会阻塞在目标进程（炉石）的主 run loop 上。炉石正忙时（动画、读取），单次调用可能耗时几十毫秒。

而 `reload()` 目前被 `Game.updateAllTrackers()`（`Game.swift:209`）调用，`updateAllTrackers()` 又挂在
`Game.swift` 约 1544-1549 行那几个 `queue: OperationQueue.main` 的 NotificationCenter 观察者上。
**结果就是这些阻塞式 AX 调用会跑在主线程上，直接卡住所有 overlay 的绘制。**

另外 `HearthstoneWindow` 的可变状态（`_frame`、`windowId`、`screenRect`、`fullscreen`）目前**没有任何同步**，
却同时被后台的 `_queue` 和主线程读写。

## 要做的改动

### 1. 给可变状态加锁

用仓库里现成的 `HSTracker/Utility/UnfairLock.swift` 保护 `_frame` / `windowId` / `screenRect` / `fullscreen`。
读取方（`frame`、`isFullscreen()` 等）走加锁快照，不要在持锁期间做 AX 调用或其它可能阻塞的事。

### 2. 缓存 `AXUIElementCreateApplication`

现在每次 `reload()` 都重建。改为缓存，仅当 pid 变化时才重建。

### 3. 让 `reload()` 只在后台队列被调用

- 从 `Game.updateAllTrackers()`（`Game.swift:209`）里**删掉** `SizeHelper.hearthstoneWindow.reload()` 这一句。
- 保留 `Game.internalUpdateCheck()` 里（约 1577 行）那次 `reload()` —— 那里本来就跑在后台的 `_queue` 上，
  今后由它独占负责刷新窗口矩形。
- 主线程一律只读加锁快照，不再触发 AX。

## 关键约束

`Game.internalUpdateCheck()` 里有这样一段语义（约 1573-1580 行）：先记下当前 `frame` 和 `isFullscreen()`，
调用 `reload()`，再比较前后是否变化来决定要不要 `updateAllTrackers()`。

**这个"前后比较"的语义必须保持可用。** 加锁和快照化之后，`reload()` 仍然要同步地更新状态，
使得紧接其后的 `frame` / `isFullscreen()` 读取能拿到本次刷新的**新值**。
不要把 `reload()` 改成异步派发后立即返回 —— 那会让这个比较永远读到旧值，窗口跟随直接失效。

换句话说：`reload()` 保持同步语义，改变的是**谁来调用它**（只有后台队列），不是它自己变异步。

## 已知代价（可接受，不用规避）

通知驱动的更新（例如用户改设置）之后会用到最多落后一个 tick 的窗口矩形。这是有意的取舍。

## 明确不要动

- 不要改 `reload()` 之外的 `SizeHelper` 里那些计算各 overlay 位置的函数。
- 不要动 `screenshot()`。
- 不要改 `Game.swift` 里除第 209 行那句之外的任何内容 —— tick 频率、`counter > 3` 门槛都留给 T3。

## 验收

1. 构建通过。
2. 在报告里明确写出：加锁覆盖了哪些字段、`reload()` 的同步语义如何保持、`Game.swift` 只改了哪一行。
3. 人工检查：`updateAllTrackers()` 里不再有 `reload()` 调用。

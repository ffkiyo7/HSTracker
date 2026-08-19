# Phase 0 / T3 — 提高刷新率与窗口跟随频率

先读 `docs/tasks/_common.md` 里的通用约束，再读本文件。

**前置依赖：T2 必须已经完成并通过验收。** 如果 `Game.updateAllTrackers()` 里还能看到
`SizeHelper.hearthstoneWindow.reload()`，说明 T2 没做完，请停下并在报告里说明，不要继续。

## 目标文件

`HSTracker/Logging/Game.swift`

**本任务只允许修改这一个文件。**

## 问题

1. `Game.guiUpdateDelay`（约 42 行）= `0.5` 秒。它是整个 overlay 的刷新节拍，
   `internalUpdateCheck()`（约 1567-1600 行）按这个间隔自我重排。
   结果是**所有 overlay 对游戏状态的反应上限被钉死在 2 fps**。

2. `internalUpdateCheck()` 里有个 `counter > 3` 的门槛：只有在连续 4 个 tick 都没有
   `guiNeedsUpdate` 的情况下，才会重新读一次炉石窗口矩形。
   即 **≈2 秒才跟一次窗口**。用户移动或缩放炉石窗口时，overlay 要滞后最多 2 秒才跟上。

## 要做的改动

1. `guiUpdateDelay` 由 `0.5` 改为 `0.1`。
2. 去掉 `counter > 3` 门槛，改为**每个 tick 都刷新窗口矩形并做前后比较**。
   `counter` 这个变量如果因此没有用处了，一并删掉。

改完之后 `internalUpdateCheck()` 的每个 tick 应该是：
- 若 `guiNeedsUpdate` → `updateAllTrackers()`
- 否则 → 刷新窗口矩形，若矩形或全屏状态发生变化 → 触发那一组更新（原来 `counter > 3` 分支里的那些调用）
- 末尾照旧 `updateBoardOverlay()` 并重排下一次

## 明确不要动

- **`updateTrackers()`（约 247 行）那套"只置 `guiNeedsUpdate` 标志、由轮询循环消费"的合并机制必须原样保留。**
  它有 51 个调用点，遍布日志解析路径。改成事件直接驱动重绘会被日志事件淹没。
  本任务改的只是**合并窗口的大小**，不是改成事件直驱。
- 不要动 `_queue` 的定义或它的串行性。
- 不要动 `updateAllTrackers()` 内部的那 18 个 update 方法。
- 不要碰 `pollMulliganLiveState()`（约 114-131 行）那个 16ms 循环 —— 不在本任务范围。

## 验收

1. 构建通过。
2. 报告里写明：`counter` 是删了还是留着、为什么；`internalUpdateCheck()` 改动后的控制流。
3. 特别确认：`guiNeedsUpdate` 的置位/清位逻辑没有被改动。

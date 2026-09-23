# REFORK S5：刷新合并与性能改动

计划见 `docs/REFORK.md` S5；通用约束见 `docs/tasks/_common.md`，以下为本任务的差异。

## 在哪干

- 分支 `dev0923`，worktree `.claude/worktrees/refork`（上游 `3.6.12` + 已提交的 S1–S4）。改动只落在这里。
- 主仓库（分支 `dev`）只读，是旧实现的来源：`git show dev:<path>`、`git log master..dev`。

## 目标

dev 上为「overlay 开着时炉石掉帧 / 记牌器延迟」做过的刷新与性能改动，在新线上**仍然成立的**落地，不成立的给出依据放弃。延迟探针能在新线上照旧取数。

## 来源

dev 上相关提交：`7617b8ad`（刷新合并 `scheduleGuiUpdate` / `runGuiUpdate`）、`4e5dc8f8` / `e59d60e5` / `7ae582f4` / `b0374928` / `7c0f2390`（`Utility/LatencyProbe.swift`、3 处埋点、scheme 的 `HSTRACKER_LATENCY_PROBE`）、`ce4f0523`（`SizeHelper` AX 读挪后台 + `UnfairLock`）、`f3d81021`（`ImageUtils` 异步加载 + LRU）、`143db6f3` 中未被 S3 / S4 带走的部分（`WindowManager.show` 同值不写、`Game.deckRecordLabel` 缓存等）。

3.6.12 的 overlay 已换成单画布（`RootOverlayWindow` / `RootOverlayView`），`WindowManager.swift`、`Core/SizeHelper.swift` 大幅缩水，`Tracker.swift` / `CardHud.swift` 已删。每一处改动先看 3.6.12 的对应代码还在不在、问题还有没有，再决定搬、改写还是放弃。

## 约束

- 对上游文件的改动越少越好；fork 自有代码放 `HSTracker/Fork/` 或 `Utility/LatencyProbe.swift` 这类新文件。
- `tracker_perf_*` 键 S4 已在 `HSTracker/Fork/Settings+Tracker.swift` 建好，不重复造。
- 线程与时序遵守 `AGENTS.md`「线程与时序」。
- 本任务允许改 `project.pbxproj`（文件登记）和 scheme 文件；不改 `.xcstrings`。

## 验收

- 受限环境 `clean build` 过；`test` 除 `OfficialBuildTests.testHostAppIsRecognizedAsOfficial` 外全绿，报告总条数。
- 报告：每个来源提交的处理结论（搬 / 改写 / 已被上游取代 / 放弃 + 依据）；上游文件改动清单与行数；探针在新线上怎么开、埋点各在哪；刷新链路写入到显示的每一跳 `main.async`。
- 🎮（由人做）：与 S4 同一局，不掉帧、悬停卡图无顿挫。

## 执行结果

（执行者追加）

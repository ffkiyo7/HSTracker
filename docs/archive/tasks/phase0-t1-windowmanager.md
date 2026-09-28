# Phase 0 / T1 — `WindowManager.show()` 停止每帧重设窗口属性

先读 `docs/tasks/_common.md` 里的通用约束，再读本文件。

## 目标文件

`HSTracker/UIs/Trackers/WindowManager.swift`，函数 `show(controller:show:frame:title:overlay:)`（约 418-483 行）。

**本任务只允许修改这一个文件。**

## 问题

`show()` 是 overlay 的热路径：`Game.updateAllTrackers()` 每个 GUI tick 会对大约 20 个 overlay 窗口各调用一次。
而当前实现对**每一次**调用都无条件重新赋值这些属性，无论值是否真的变了：

- `window.level`
- `window.collectionBehavior`
- `window.styleMask`
- `window.title` + `NSApp.addWindowsItem(...)`

在 macOS 上给一个已经上屏的 `NSWindow` 重新赋值 `styleMask` 会强制 AppKit 重建窗口框架，并产生一次同步的
WindowServer 往返。约 20 个窗口 × 每秒若干次 = 持续的无用开销，也是 overlay 闪烁/顿挫的直接来源之一。

`window.title` 那条还额外每次都跑一遍 `String.localizedString(...)` 查表，并重复调用 `NSApp.addWindowsItem`。

## 要做的改动

把上述属性改成**先比较、值确实变化时才赋值**：

1. `window.level` — 先算出目标 level，与 `window.level` 比较，不同才写。
2. `window.collectionBehavior` — 同上。
3. `window.styleMask` — 同上。
4. `window.title` / `NSApp.addWindowsItem(...)` — 只在标题首次设置或发生变化时执行。
   需要记住"上次应用的标题"。放在哪里由你判断，`OverWindowController` 上加一个属性是自然的做法
   （`HSTracker/UIs/Trackers/OverWindowController.swift`），但**如果那样就要改第二个文件，本任务不允许** ——
   请改为在 `WindowManager` 内部用一个以窗口为键的映射来记录，或其它不需要动其它文件的等价做法。

## 明确不要动

- **`window.orderFront(nil)` 保持无条件调用。** 它同样有 WindowServer 往返开销，但改成
  `if !window.isVisible` 有让 overlay 在用户切换应用后沉到炉石窗口下面的真实风险。
  这一项等有实测数据之后再单独处理，本任务不碰。
- `show == false` 那条分支（`orderOut` / `removeWindowsItem`）不动。
- 不要改 `show()` 的签名，不要改调用方。
- 函数开头那段 "not main thread → 派发回主线程" 的逻辑不动。

## 验收

1. 构建通过（命令见 `_common.md`）。
2. 人工检查：改动后的代码里，上述 4 项都在比较之后才赋值，且 `orderFront` 仍是无条件的。
3. 逻辑等价性：对于**首次**显示某个窗口的情况，最终生效的 level / collectionBehavior / styleMask / title
   必须和改动前完全一致 —— 这一点请在报告里明确说明你是怎么保证的。

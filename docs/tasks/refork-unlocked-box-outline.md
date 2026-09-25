# REFORK：解锁时的可移动框不再染色

通用约束见 `docs/tasks/_common.md`；在哪干同 `refork-s5-refresh-perf.md`（分支 `dev0923`，HEAD `ab723fda`）。

## 现象（09-26 用户实测）

解锁 overlay 后，上游照 HDT 在每个可移动元件上盖一层 `#4C0000FF`（ARGB，30% 蓝）的实心方块当拖动把手。它盖在内容**上面**，记牌器的字和卡图全被染蓝，用户调位置时看不清在调什么，评价「根本不适合给人使用」。

## 目标

解锁时可移动元件**内容保持原样可读**，只用描边等不遮挡内容的方式标出可拖动范围与右下角缩放把手。拖动 / 缩放的可点范围与现在一致，锁定后不画、不吃点击。

## 范围

`#4C0000FF` 的全部用处：`UIs/Overlay/Trackers/TrackerPanelView.swift`、`UIs/Overlay/Trackers/SecretsPanelView.swift`、`UIs/Overlay/OverlayWidgetPlacement.swift`（计数器、水晶上限等共用）、`UIs/Battlegrounds/Session/BattlegroundsSessionOverlayView.swift`（战棋只做静态确认）。顺带：`SecretsPanelView` 与 `BattlegroundsSessionOverlayView` 的拖动 / 缩放手势仍用随框移动的 `.local` 坐标（与 `ab723fda` 修掉的记牌器同病，拖动会闪），一并改到 `.rootOverlayCanvas`。

## 约束

- 上游文件改动越少越好；几处共用同一种样式，不要各写一份。
- 线程与点击穿透不动（`RootOverlayWindow` 的 `updateFrames` / `alwaysLocked` 覆写保留）。

## 验收

- 受限环境 `clean build` 过；`test` 除 `OfficialBuildTests.testHostAppIsRecognizedAsOfficial`（及若因桌面权限失败的 `LocalizationFormatTests`）外全绿，报告总条数。
- 报告：改了哪些文件与行数；新样式长什么样（颜色、线宽、把手）。
- 🎮（由人做）：解锁后记牌器 / 奥秘 / 计数器 / 水晶上限内容不染色、看得清；拖动与缩放不闪；锁定后一切如常。

## 执行结果

（执行者追加）

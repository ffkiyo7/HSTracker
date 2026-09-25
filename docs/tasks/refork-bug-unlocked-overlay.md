# REFORK Bug：解锁后 overlay 露出窗口边框、拖动记牌器闪烁

通用约束见 `docs/tasks/_common.md`；在哪干同 `docs/archive/tasks/refork-s5-refresh-perf.md`（分支 `dev0923`，HEAD `8a86299d`）。

## 现象（09-26 用户实测，菜单「窗口 → 解锁窗口」后进对局）

1. 覆盖整个炉石窗口的 overlay 顶部露出一条 macOS 标题栏，标题「Window」，带红黄绿三个按钮。
2. 用户形容 overlay「遮罩上了奇怪的滤镜颜色」：截图里双方记牌器整块盖着半透明蓝色。要查清这是上游有意的可移动框（`TrackerPanelView.movableBox`，注释称 HDT 的 `#4C0000FF`）还是别的层；若是前者且与 HDT 一致，就不算 bug，报告里写明依据。
3. 拖动记牌器时，整个组件一直闪烁。
4. 锁定状态下以上都没有；锁定时一切正常。

## 线索

- `WindowManager.show` 在未锁定时给窗口设 `.titled` 等 styleMask，锁定与否取 `Settings.windowsLocked || controller.alwaysLocked`；`OverWindowController.alwaysLocked` 默认 false，`RootOverlayWindow` 未覆写。3.6.12 原样即如此，`upstream/master` 之后也没改。
- S5（`cc0fa753`）把刷新从最多 2 次 / 秒提到最多约 60 次 / 秒，并让 `show` 只在 frame 等值不同时 `setFrame`；第二批修复（`d589ff8a`）覆写了 `RootOverlayWindow.updateFrames()`。闪烁是否与这些相关，要查到根因。

## 约束

- 对上游文件的改动越少越好；修法要对「锁定 / 解锁」两种状态都成立，不破坏 `d589ff8a` 按光标位置设的点击穿透。
- 解锁后必须能拖动、能用右下角缩放；锁定后面板不吃点击。

## 验收

- 受限环境 `clean build` 过；`test` 除 `OfficialBuildTests.testHostAppIsRecognizedAsOfficial` 与 `LocalizationFormatTests`（测试宿主无桌面权限）外全绿，报告总条数。
- 报告：三条现象各自的根因（附证据）与修法；上游文件改动清单与行数；需要 🎮 实机看的点。
- 🎮（由人做）：解锁 → 无标题栏、拖动 / 缩放不闪、松手后位置保持；再锁定 → 点击穿透正常。

## 执行结果

09-26 Opus 子代理完成，`dev0923` `ab723fda`；测试 289 条只挂 `OfficialBuildTests`。待 🎮。
1. 标题栏：`RootOverlayWindow` 覆写 `alwaysLocked = true`，整屏画布始终 `[.borderless, .nonactivatingPanel]`。
2. 蓝色：HDT `OverlayWindow.Input.cs` `UnlockUi` 的 `#4C0000FF`（WPF ARGB，30% 蓝），本仓库 `Color(hex:)` 同样按 ARGB 解析，非 bug；但盖在内容上不可用，另开 `refork-unlocked-box-outline.md`。
3. 闪烁：主因是 `TrackerPanelView` 拖动 / 缩放手势用随框 `.offset` 移动的 `.local` 坐标，每步抵消上一步，框在两个位置间跳 → 改 `.rootOverlayCanvas`；次因（推断，未打日志）是带标题栏的窗口被压到菜单栏下，每次刷新 frame 不等都 `setFrame`，去掉标题栏即消失。
- 同病未修：`SecretsPanelView`、`BattlegroundsSessionOverlayView` → 已在 `5ff7f87c` 一并改。

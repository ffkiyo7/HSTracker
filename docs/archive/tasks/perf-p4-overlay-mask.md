# Perf P4 — 画布遮罩只在有切口时才挂

先读 `docs/tasks/_common.md`。实现分支：从最新 `dev0923` 切 `perf/overlay-mask`。
**开工条件：滚动那本（`phase2-scroll-collapse.md`）已合入 `dev0923`。** 两本都动 overlay 根视图一带。
滚动那本明令不许再加全画布遮罩，并把拿掉常驻遮罩留给本书。

## 为什么

整个 overlay 画布一直套着一层遮罩，哪怕什么都不用挖。这一层每次重绘都要做一次和炉石窗口一样大的离屏合成：
用户的 3840×1874 窗口约 29 MB 一次。画布上任何动画（T8 行动画、红龙转圈、回合计时）都会触发整块重合成，
最高 165 Hz。**这些代价都是从代码推断的，没量过，本片要量。**

## 现状（`origin/dev0923` `35a783f6`）

- `UIs/Overlay/Root/RootOverlayView.swift:630`：`.mask(RootOverlayOpacityMaskView(...))` 套在整个画布 `ZStack` 上，永远在。
- `UIs/Overlay/Root/OverlayOpacityMask.swift:148-166`：遮罩 = 一块全黑 `Rectangle` + 每个切口 `.blendMode(.destinationOut)` + `.compositingGroup()`。
  `:117-122` 的注释说明了为什么用 `destinationOut` 而不用 even-odd：切口经常互相重叠。
- 切口只在短时间内存在：大卡悬停、发现、好友列表、游戏菜单（后两者见 `Hearthstone/Watchers.swift:256-263`）等。平时 `maskedRects` 为空，遮罩照样在。
- `RootOverlayWindow.swift:14` / `:32` 持有 `hostingView`。

## 要做出什么

1. `maskedRects` 为空、且 `debugShowRegions` 关时，画布不带任何遮罩或合成层。有切口时行为和今天逐像素一致，包括重叠切口的语义。
2. 整个 overlay 的 SwiftUI 视图身份不能随「有没有切口」翻转。用 `if / else` 包住整棵树会重建所有子视图、丢掉它们的状态。
   建议在 `hostingView` 的 layer 上挂 / 摘 mask layer，或用其他不翻身份的办法；选了什么、为什么，写进报告。
3. 加诊断键 `overlay_perf_always_mask`（默认 false）：打开就恢复「永远遮罩」，方便同一会话里 A/B。照 `Fork/Settings+Tracker.swift` 里 `tracker_perf_*` 的写法；键名列进报告（之后进 PLAN「与上游的默认值差异」）。
4. `RootOverlayOpacityMaskDebugView` 照旧可用。

## 不在本片

- 红龙转圈（`RedDragon/RedDragonOverlayView.swift:603`）：FF 本机这个文件有未提交改动（rdr-t6），等那边提交后另开。
- 三行头 / 段头没合层（Perf P2 留下的 4 层阴影 + 3 层组透明）：动 `TrackerHeaderView` 会撞滚动那本。
- 每 0.25 秒对炉石的 4 次辅助功能读取（`Core/SizeHelper.swift:44-100`）。

## 硬约束

- 遮罩以外的绘制顺序、遮罩之后的 `.overlay` 链（`RootOverlayView.swift:634` 起）不动。
- 所有写入在主线程（`OverlayOpacityMask` 本来就是主线程的）。
- FF 本机有未提交改动的文件一律不碰：`Fork/PlayerCardZones.swift`、`TagChangeActions+ZoneLatches.swift`、`Logging/Entity.swift`、分区相关测试、`RedDragonOverlayModel` / `RedDragonOverlayView` 及其测试、`docs/PLAN.md`。

## 允许修改的文件

- `HSTracker/UIs/Overlay/Root/RootOverlayView.swift`：只动遮罩那一处
- `HSTracker/UIs/Overlay/Root/OverlayOpacityMask.swift`
- `HSTracker/UIs/Overlay/Root/RootOverlayWindow.swift`：只在走 layer 方案时动 `hostingView` 的 layer
- `HSTracker/Fork/Settings+Tracker.swift`：只加诊断键
- 测试：加进合适的现有测试文件；要新建就按 `AGENTS.md` 登记 4 处

## 测试

- 没有切口时不挂遮罩，有切口时挂上；切口清空后摘掉。
- 诊断键打开时永远挂着。
- 有切口时，切口内的像素是透明的（离屏渲染 hosting view 取像素即可，`TrackerMetricsTests.swift` 里有现成的托管窗口手法）。

## 验收

1. Debug `BUILD SUCCEEDED`；全套测试只允许 PLAN 里记着的两条老失败。
2. 测量，Release 包，同一局里切诊断键 A/B：
   - 对局中 `sudo powermetrics --samplers gpu_power -i 1000 -n 30`，键关一次、键开一次，HSTracker 退出后再记一次基线；
   - 活动监视器 % GPU：WindowServer 和 HSTracker 各自的数。
3. 🎮 用户看：悬停大卡、发现、好友列表、游戏菜单时 overlay 照样被挖空；平时 overlay 看起来没有任何变化。

## 汇报

结果写进本文件末尾「执行结果」一节：改动清单、测试条数、三组 GPU 数字。
**不要 commit，不要动 `docs/PLAN.md`。**

# HSTracker 个人分支：Overlay SwiftUI 重写 + 记牌器分区 + 中文化 + 设置/菜单修复

## Context

`~/Desktop/HSTracker` 是 HearthSim/HSTracker 的 fork，当前与 upstream 完全一致（`ecf64cff` = 3.6.4，本机安装的是 3.6.2）。定位为**个人自用版**，不以回合并 upstream 为约束。

用户在实际使用中提出四个问题，已逐条定位到源码根因：

1. **Overlay 不跟手 / 卡顿 / 帧数低**（对比 Windows 上的 Firestone）。根因是渲染层用即时模式 `NSView.draw()` 手绘、每帧从磁盘重读并解码主题 PNG、每帧拆掉整棵视图树重建，外加 500ms 的全局刷新节流。
2. **记牌器是 30 张平铺**，打出/抽到的牌只是变暗但仍占位，列表又长又难看还看不出牌库里还剩什么。Firestone 分「牌库 / 手牌 / 坟场」三段。
3. **简体中文没翻全**，设置页大量英文；全项目 846 个 key 有 410 个（48%）没有 zh-Hans。
4. **设置界面粗糙**（20 个原生 checkbox 平铺在 XIB 里），**Dock 菜单「卡组」点了没反应**。

目标产出：一个在 macOS 上手感接近 Firestone 的记牌器 —— 渲染改为 SwiftUI、卡牌按区域分组、界面全中文、设置页可读、菜单可用。

---

## 总体决策

### 1. 提升部署目标到 macOS 14.0

`HSTracker.xcodeproj/project.pbxproj` 现为 `MACOSX_DEPLOYMENT_TARGET = 10.14`，这是全项目 97 处 `@available(macOS 10.15, *)` 的来源，也是 SwiftUI 无法自由使用的唯一障碍。

改为 **14.0**，理由：
- SwiftUI 无需任何 availability 守卫
- 可用 Observation 框架的 `@Observable` 宏，比 `ObservableObject` 的失效粒度细得多（避免每次数据更新让整棵视图树重算）——这对本次性能目标是实质性的
- 个人自用版，本机是 macOS 26，无兼容性负担

提升部署目标**不会破坏编译**，现存 `@available` 守卫仍然合法（只是恒真）。清理这 97 处守卫是可选的后续收尾，不阻塞主线。

### 2. 架构：保留窗口层，替换内容视图

**保留**（`WindowManager` / `SizeHelper` 的定位逻辑全部依赖它们，动了牵连太广）：
- `Tracker: OverWindowController` 这个 NSPanel 本身
- 数据管线 `Game.updatePlayerTracker()` → `tracker.update(...)`

**替换**（窗口内容视图下的一切）：
- `AnimatedCardList`、`CardBar`(+4 个主题子类)、`DeckLens`、`DeckSideboards`、`CardCounter`、`PlayerDrawChance`、`OpponentDrawChance`、`GraveyardCounter`、`StringTracker`
- `Tracker.updateFrames()` 那 280 行手写 y 游标布局（`Tracker.swift:127-405`）

做法与仓库里已有的 SwiftUI 落地点一致 —— `HSTracker/UIs/Overlay/Root/RootOverlayWindow.swift:24` 已经在用 `window?.contentView = NSHostingView(...)`。**upstream 自己正在往 SwiftUI 迁移**（Mulligan V2、RootOverlay 都是 2026 年新加的 SwiftUI 代码），本次重写是顺着这个方向走，不是逆流。

### 3. 开发期 A/B 开关

加一个 `Settings.useSwiftUITracker`（默认 true）。重写期间可随时切回旧 AppKit 记牌器做视觉对照和性能对比。**全部验收通过后删除该开关与旧代码**，不留长期分叉。

---

## Phase 0 — 地基：驱动循环与窗口层

> SwiftUI 重写只解决"画得慢"，解决不了"半秒才知道要画"。这一阶段必须先做，否则新渲染层仍然被 2 Hz 的节流卡住。每一项都是局部改动。

### 0.1 提升部署目标
`HSTracker.xcodeproj/project.pbxproj`：`MACOSX_DEPLOYMENT_TARGET` → `14.0`（Debug/Release 两处）。

### 0.2 降低刷新延迟
`HSTracker/Logging/Game.swift:42` `guiUpdateDelay = 0.5` → `0.1`。

`updateTrackers()`（`Game.swift:247`）只置 `guiNeedsUpdate` 标志、由 `internalUpdateCheck()`（`Game.swift:1569`）消费的合并机制**必须保留** —— 它有 51 个调用点，去掉会被日志事件淹没。这里改的只是合并窗口，不是改成每事件重绘。

### 0.3 把 Accessibility 调用挪离主线程
`HSTracker/Core/SizeHelper.swift:37-118` `reload()` 里有 4 次阻塞式跨进程 AX 调用（`kAXFocusedWindowAttribute` / `AXFullScreen` / `kAXPosition` / `kAXSize`）。它经 `Game.swift:209` 被 `updateAllTrackers()` 调用，而后者又挂在 `Game.swift:1544-1549` 的 `OperationQueue.main` 通知观察者上 —— **AX 阻塞调用会跑在主线程上**，炉石忙的时候直接卡住绘制。

- `reload()` 只在后台队列执行，结果写入一份带锁的快照，主线程只读快照
- 缓存 `AXUIElementCreateApplication(pid)`（现在每次重建），pid 变化时才重建
- `HearthstoneWindow` 的 `_frame` / `windowId` / `screenRect` / `fullscreen` 目前**无任何同步**却被 `_queue` 和主线程同时读写 —— 一并用 `HSTracker/Utility/UnfairLock.swift` 保护

做完这一项，窗口跟随才能提频。

### 0.4 窗口跟随提频
`Game.swift:1573` 的 `counter > 3`（≈2 秒才重新读炉石窗口矩形）→ 每次 tick 都读。移窗/改分辨率时 overlay 从"2 秒后才跟上"变成"跟手"。依赖 0.3 先落地。

### 0.5 `WindowManager.show()` 去抖
`HSTracker/UIs/Trackers/WindowManager.swift:418-483` 每次调用（约 20 窗口 × 每 tick）无条件重设 `styleMask`、`level`、`collectionBehavior`、`orderFront`，还每次 `NSApp.addWindowsItem` 重加窗口菜单项、每次跑一遍 `String.localizedString`。

在 macOS 上给活动 `NSWindow` 重新赋值 `styleMask` 会强制 AppKit 重建窗口框架并同步往返 WindowServer —— 这是闪烁和顿挫的直接来源。

改为**值变化时才赋值**：每个属性先比较再写；`title` / `addWindowsItem` 只在首次或标题变化时做。

---

## Phase 0 任务拆分（交给本机 grok headless 执行）

计划本身另存一份到项目内：`/Users/wadorudi/Desktop/HSTracker/docs/PLAN.md`，任务书放 `docs/tasks/`。

本机已确认：`grok` 在 `~/.grok/bin/grok`，已登录 grok.com，`~/.grok/config.toml` 里 `default = "grok-4.6"`、`default_reasoning_effort = "xhigh"`，与要求一致（下面仍显式传参，保证可复现）。

### T0 — 前置环境（**先做，不交给 grok**）

实测发现的构建阻塞项：

1. **`wget` 未安装**，而 `project.pbxproj` 有两个 build phase 依赖它（`:5087` 下载 `HearthMirror.framework`、`:5128` 下载 Mono 运行时）。不装的话**首次构建必然失败** → `brew install wget`
2. `downloaded-frameworks/` 目录不存在，首次构建会联网拉 HearthMirror + Mono，耗时较长 → 先手动跑一次基线构建把它暖起来，别让 grok 的第一个任务卡在这
3. `Config.xcconfig` 需把签名两行注释对调（`CODE_SIGN_IDENTITY = -`、`DEVELOPMENT_TEAM =`）才能本地签名构建。**此文件改动不要提交**（`CONTRIBUTING.md` 明确要求）
4. SwiftLint 未安装，但 build phase 里是 `which swiftlint` 判断后仅告警（`:5066`），**不阻塞构建**，可装可不装

> **实测补记（T0 已完成）**：除上述四项外，还发现 upstream 在 HEAD 上有一个真实的构建 bug ——
> commit `d70efe05` 把 `HSTracker/mono-version.txt` 从 `7.0.20` 升到 `8.0.29`，但 "Embed Mono"
> build phase 里的 `NET_VERSION=net7.0` 没有同步更新。下载到的 mono 8.0.29 只提供 `net8.0` 目录，
> 脚本却去找 `net7.0`，**全新 clone 必然构建失败**。已把该处改为 `net8.0`（`project.pbxproj` 单字改动）。
> 佐证：本机安装的 3.6.2 内嵌的是 7.0.20 程序集 —— 它早于 `d70efe05`，那时 `net7.0` 是对的。
> 修复后 Debug 构建已 `BUILD SUCCEEDED`。

基线构建命令（同时作为后续每个任务的验收命令）：

```
cd /Users/wadorudi/Desktop/HSTracker
xcodebuild -project HSTracker.xcodeproj -scheme HSTracker \
  -configuration Debug -destination 'platform=macOS' build
```

### 任务顺序与依赖

刻意把**部署目标放最后**：T1–T3 是纯行为改动，跑完就能做一次干净的 A/B 实测（"Phase 0 前 vs 后"），中间不掺入部署目标这个变量。T4 只是给 Phase 1 铺路，不影响性能对比。

```
T1 (WindowManager)  ──┐
T2 (SizeHelper)     ──┼─→ T3 (Game loop，依赖 T2)  ──→  实测  ──→  T4 (部署目标)
```

T1 与 T2 互不相干可并行，但都改 overlay 行为，**建议还是串行**跑完各自验收，出问题好定位。T3 **必须**在 T2 之后：AX 调用还在主线程时提高轮询频率会比现在更卡。

### T1 — `WindowManager.show()` 停止每帧重设窗口属性

- **文件**：`HSTracker/UIs/Trackers/WindowManager.swift:418-483`
- **改动**：`window.level`、`window.collectionBehavior`、`window.styleMask` 三项改为**先比较、值变化时才赋值**；`window.title` 与 `NSApp.addWindowsItem` 只在标题首次设置或发生变化时执行（需要记住上次应用的标题）
- **明确不要动**：`window.orderFront(nil)` 保持无条件调用。它虽然也有 WindowServer 往返开销，但改成 `if !window.isVisible` 有让 overlay 在切换应用后沉到炉石下面的真实风险，这一项留到有实测数据再说
- **验收**：构建通过；启动 HSTracker，记牌器正常出现、位置正确；锁定/解锁窗口（菜单栏 Window 菜单）切换后 `styleMask` 仍正确跟随

### T2 — `SizeHelper` 的 Accessibility 调用移出主线程

- **文件**：`HSTracker/Core/SizeHelper.swift:37-118`（`HearthstoneWindow.reload()`）
- **背景**：`reload()` 内有 4 次阻塞式跨进程 AX 调用（`kAXFocusedWindowAttribute`、`AXFullScreen`、`kAXPosition`、`kAXSize`）。它经 `Game.swift:209` 被 `updateAllTrackers()` 调用，而后者挂在 `Game.swift:1544-1549` 的 `OperationQueue.main` 通知观察者上 —— **AX 阻塞调用会跑在主线程**，炉石忙时直接卡住绘制
- **改动**：
  1. `HearthstoneWindow` 的可变状态（`_frame` / `windowId` / `screenRect` / `fullscreen`）目前**无任何同步**却被 `_queue` 与主线程同时读写 —— 用 `HSTracker/Utility/UnfairLock.swift` 包起来，读取方走加锁快照
  2. 缓存 `AXUIElementCreateApplication(pid)`（现在每次调用都重建），仅在 pid 变化时重建
  3. **把 `reload()` 从 `updateAllTrackers()`（`Game.swift:209`）里摘掉**，改由后台 `_queue` 上的 `internalUpdateCheck()` 独占负责刷新；主线程一律只读快照
- **已知代价**：通知驱动的更新（改设置等）会用到最多落后一个 tick 的窗口矩形。T3 之后一个 tick = 100ms，可接受
- **注意**：`Game.swift:1573-1580` 会在 `reload()` 前后比较 rect 来判断窗口是否移动，改动**不能破坏这个比较语义**
- **验收**：构建通过；对局中移动/缩放炉石窗口，overlay 仍跟随；Instruments 采样确认主线程上不再出现 `AXUIElementCopyAttributeValue`

### T3 — 提高刷新率与窗口跟随频率（依赖 T2）

- **文件**：`HSTracker/Logging/Game.swift:42`、`:1567-1600`
- **改动**：
  1. `guiUpdateDelay` 由 `0.5` 改为 `0.1`
  2. `internalUpdateCheck()` 里去掉 `counter > 3` 的门槛（现在要 ≈2 秒才重新读炉石窗口矩形），改为每个 tick 都在后台队列刷新窗口矩形
- **明确不要动**：`updateTrackers()`（`Game.swift:247`）只置 `guiNeedsUpdate` 标志、由轮询循环消费的**合并机制必须保留**。它有 51 个调用点，改成每事件直接重绘会被日志事件淹没。这里改的只是合并窗口大小，不是改成事件直驱
- **验收**：构建通过；对局中拖动炉石窗口，overlay 立即跟上（改前最多滞后 2 秒）；Instruments 确认 HSTracker 主线程 CPU 没有因为提频而显著上升 —— 若上升明显，说明 T2 没做干净，回头查

> **执行补记（T3 已完成，review 时加了一处设计改动）**：T2 把 `reload()` 从 `updateAllTrackers()` 里摘掉之后，
> 若 T3 按原文"每个 tick 都刷新"实现，`reload()` 就只剩在 `else` 分支里 —— 日志密集时 `guiNeedsUpdate`
> 每拍都为真，窗口矩形将**长时间不刷新**，overlay 被钉在旧位置。这是 T2 与 T3 组合才会出现的回归，
> 单独看任一任务都发现不了。
> 已改为：把窗口轮询**提到分支之外**，并用 250ms 时间阈值单独节流（不跟随 100ms 的 GUI tick）。
> 原因有二 —— 一是两个分支都要拿到新鲜矩形；二是每次 `reload()` 是 4 次阻塞式 AX 跨进程调用，
> 若真按 10Hz 跑就是每秒 40 次打进炉石自己的 run loop，反而拖累我们想保住流畅度的那个进程。
> 250ms 把 AX 频率维持在接近原先的水平，同时把跟窗延迟从 ~2s 降到 ~250ms。

### T4 — 部署目标提到 macOS 14.0（为 Phase 1 铺路，**实测之后再做**）

- **文件**：`HSTracker.xcodeproj/project.pbxproj`
- **改动**：`MACOSX_DEPLOYMENT_TARGET` 由 `10.14` 改为 `14.0`（Debug / Release 两处都要）
- **注意**：pbxproj 里另有一处 `10.12`，属于其它 target，**不要动**。提升部署目标不会破坏编译，现存 97 处 `@available(macOS 10.15, *)` 守卫仍然合法（只是恒真），清理它们是可选的后续收尾，**本任务不做**
- **验收**：构建通过；`grep -n "MACOSX_DEPLOYMENT_TARGET" HSTracker.xcodeproj/project.pbxproj` 确认改到位；应用能正常启动

### grok 调用方式

每个任务一次独立调用，跑完我 review diff、确认验收项，再放下一个：

```
cd /Users/wadorudi/Desktop/HSTracker
grok --prompt-file docs/tasks/phase0-t1-windowmanager.md \
     -m grok-4.6 --effort xhigh \
     --permission-mode acceptEdits \
     --output-format plain
```

任务书里统一要求：**只改任务指定的文件**、改完自己跑一遍验收构建、输出改动摘要、**不要 commit**（由我 review 后再提交，每个任务一个独立 commit）。

---

## Phase 1 — SwiftUI 记牌器渲染

新目录 `HSTracker/UIs/Trackers/SwiftUI/`：

| 文件 | 职责 | 取代 |
|---|---|---|
| `TrackerViewModel.swift` | `@Observable`，持有分组、计数器、W/L、抽卡率、坟场统计 | — |
| `TrackerView.swift` | 根 `VStack`，按设置条件拼装各段 | `Tracker.updateFrames()` |
| `TrackerSectionView.swift` | 分段头（图标+标题）+ 卡行列表，空则折叠 | `DeckLens` / `DeckSideboards` |
| `CardRowView.swift` | 单张卡行 | `CardBar` + 4 个主题子类 |
| `TrackerBarViews.swift` | 卡数 / 抽卡率 / 坟场 / 战绩 四种横条 | `CardCounter` 等 4 个 `TextFrame` 子类 |
| `ThemeImageCache.swift` | 主题 PNG 一次性加载缓存 | — |

### 1.1 `CardRowView` —— 本阶段的核心

`CardBar.draw()`（`CardBar.swift:295-371`）是一串 `add*()` 的图层叠加，在 SwiftUI 里天然就是 `ZStack`：底图 → 卡图 tile → fade → countbox+数字 → created/legendary 图标 → frame → gem+费用 → 高亮边框 → 卡名 → darken 蒙版 → 调度胜率条。

必须消灭的具体开销（均已核对到行）：
- **`CardBar.swift:796-816`**：`add(themeElement:)` → `NSImage(contentsOfFile:)`，**每次 draw 都重新读盘+解码 PNG，零缓存**。一次记牌器重绘约 150–500 次 PNG 解码。→ `ThemeImageCache` 按 `(主题, 文件名)` 缓存 `NSImage`，进程内加载一次。
- **`CardBar.swift:68-81`**：`hasAllRequired` 在每次 draw 开头对 14 个文件逐个 `fileExists`。→ 每个主题启动时校验一次并缓存结果。
- **`CardBar.swift:160-204`**：`required` / `optionalFrame` / `optionalGems` / `optionalCountBoxes` 是**计算属性**，每次访问新建整个字典，一次 draw 访问约 15 次。→ 改为按主题的静态常量表。
- **`CardBar.swift:697-730`**：`fitFontForSize` 用二分查找试字号，每次迭代新建 `NSFont`+属性字典+`NSAttributedString` 跑完整文本排版；经 `addCountText`/`addCoinCost`/`addCardName` 每行约 12 次全量排版。→ SwiftUI 用 `.minimumScaleFactor()` + `.lineLimit(1)`，交给框架。
- **`Settings.swift:34-37`**：`UserDefault.wrappedValue.get` 每次都走 `UserDefaults.object(forKey:)`，无缓存；`CardBar.ratio()` 每绘制一个元素都读，一次记牌器重绘约 2000 次。→ 视图模型统一读一次、随通知失效。
- **`CardBar.swift:243-272`**：`update(highlight:)` 每次新建两个 `CALayer` 塞进 `flashLayer` 且 `isRemovedOnCompletion = false`，而 `draw()` 只清 `cardLayer` 的 sublayers（`:302`）——**flash 图层无上限累积**。→ SwiftUI 动画取代，泄漏消失。
- **`CardBar.swift:226-241`**：`cardLayer` 从不接收内容，纯粹是每帧被清空的死重。→ 删除。

`MinimalBar.swift:24-49` 每行每帧跑一次 Core Image 高斯模糊 → SwiftUI `.blur()`（GPU）。

### 1.2 卡图加载改为真异步
`HSTracker/UIs/ImageUtils.swift:119-146`：缓存未命中时 `loadImage` 在**调用线程**同步 `NSImage(contentsOf:)`，而调用方是 `draw()` → 主线程磁盘读+JPEG 解码。

→ `CardRowView` 命中缓存直接显示，未命中显示占位并触发异步加载，完成后经视图模型驱动刷新。顺带给 `SynchronizedDictionary` 缓存（`ImageUtils.swift:36-39`，目前**无上限无淘汰**）加个 LRU 上限。

### 1.3 消灭每帧视图树重建
`AnimatedCardList.swift:186-201` 每帧 `for view in subviews { view.removeFromSuperview() }` 再全部 `addSubview` —— 把 `update(cards:reset:)`（`:81-162`）刚做完的增量 diff 全部作废。SwiftUI 的 `ForEach` + 稳定 `id` 天然是增量的，此问题随重写消失。

同样模式还存在于 `CountersOverlay.swift:46-61`（每帧从 XIB 新建 `CounterView`）和 `ActiveEffectsOverlay.swift:55-68`（每帧拆掉整个 `NSGridView` 的行列）。**本轮不动这两个**，但记在这里 —— 它们是同一 tick 里的邻居，会一起拖慢主线程。

### 1.4 布局
`Tracker.updateFrames()` 的自适应逻辑必须保住：`Tracker.swift:298-300` 的 `cardHeight = min(cardHeight, (windowHeight - offsetFrames) / totalCards)` —— 卡多时行高自动压缩以塞进窗口。

在 `TrackerView` 里用 `GeometryReader` 量出可用高度，按同一公式算出行高传给各段。行高常量沿用 `HSTracker/UIs/Cards/CardSize.swift`（`kRowHeight 34` / `kHighRowHeight 52` / `kMediumRowHeight 29` / `kSmallRowHeight 23` / `kTinyRowHeight 17`）。

### 1.5 悬停
`CardCellHover` 协议（`CardBar.swift:12-15`）+ `Tracker.getHoverComponent()`（`Tracker.swift:474-495`，靠向上遍历 superview 猜自己属于哪一段）→ 换成 `CardRowView` 的 `.onHover`，分段身份**直接作为参数传入**，那段脆弱的 superview 遍历直接删掉。悬停出卡图仍走现有的 `windowManager` floating card 路径。

---

## Phase 2 — 记牌器分区（牌库 / 手牌 / 已打出）

新设置 `Settings.groupCardsByZone`，**默认开启**；关闭则回到现有平铺。

### 2.1 数据层
`Player.swift:389-408` 的 `playerCardList` **保持原样不动** —— 它还被 `Game.swift:2161`（战绩上传）和 `AppDelegate.swift:616`（套牌导出）依赖。

**新增** `Player.playerCardGroups`，复用现成材料：
- `getDeckState()`（`Player.swift:531-663`）已经给出 `remainingInDeck` / `removedFromDeck`
- `hand` / `graveyard` / `board` 分区数组已存在于 `Player.swift:183-186`
- `getHighlightedCardsInHand(cardsInDeck:)`（`Player.swift:374-387`）已经在做"手牌里有哪些"的匹配，可直接复用其匹配逻辑

分组定义（保证三段之和恒等于原始牌表，这是关键不变式）：

| 段 | 内容 |
|---|---|
| **牌库** | `deckState.remainingInDeck` + `getPredictedCardsInDeck(hidden: false)` |
| **手牌** | `hand` 实体按 cardId 分组计数（并入 `createdCardsInHand`，受 `Settings.showPlayerGet` 控制） |
| **已打出** | `deckState.removedFromDeck` **减去**手牌部分 |

第三段刻意叫**「已打出」而不是「坟场」**：一张打出后还站在场上的随从属于 `board` 区，既不在牌库也不在手牌也不在坟场。用"补集"定义（离开牌库且不在手上）能保证它有归属、三段永远加得起来。若之后想把场上单独拆成第四段，数据（`Player.swift:184` `board`）是现成的。

对手记牌器：`opponentCardList`（`Player.swift:464-525`）在未知牌表时全部来自 `revealedEntities`，**分区意义不大**，且会泄露"这张在手上"这种本不该知道的信息。→ 对手侧仅在已链接牌表时（`Player.knownOpponentDeck != nil`）启用分区，否则保持平铺。

### 2.2 UI 层
分组直接喂给 Phase 1 的 `TrackerSectionView`。分段头沿用 `DeckLens` 现有视觉（底色 `#23272A`、边框 `#141617`、左侧 17×17 图标 + 白字标题，见 `DeckLens.swift:29-41`），空段自动折叠（`DeckLens.swift:59-68` 的现有行为）。

现存的「置顶」「置底」「备牌」「相关牌」本来就是分段，在新结构里成为同一套 `TrackerSectionView` 的不同实例，`Tracker.swift:74-78` 那几处 `String.localizedString("On Top"/"On Bottom"/"Related_Cards")` 沿用。

### 2.3 设置接线
- `Settings.swift` ~L352 加属性、~L652 加 key 常量（照 `removeCardsFromDeck` 的写法）
- **必须**把新 key 加进 `Game.swift:1508` 的 `playerTrackerUpdateEvents`，否则改设置不会实时重绘
- `TrackersPreferences.swift` 加 outlet + `viewWillAppear` 读取 + `checkboxClicked` 写回（`:52-55` / `:109-117` 的现有模式）

### 2.4 顶部信息区重做（移除现有面板，改 Firestone 三行式）

现有顶部堆了四个独立组件，**用户看不懂且没有任何 tooltip**，要整块拿掉：

| 组件 | 文件 | 显示内容 | 开关 |
|---|---|---|---|
| 手牌数 / 牌库数 | `CardCounter.swift`（`Tracker.swift:18` outlet，`:409-410` 赋值） | 图标 + `4` / `21` | `Settings.showPlayerCardCount`（`:321`） |
| **抽卡概率** | `PlayerDrawChance.swift:17-18,24-25` | `1 4.76%` `2 9.52%` | `Settings.showPlayerDrawChance`（`:319`） |
| 疲劳指示 | — | `1` / `0` | `Settings.fatigueIndicator`（`:427`） |
| 胜负比 | `Tracker.swift` | `6 - 7 (46%)` | `Settings.showWinLossRatio`（`:391`） |

**抽卡概率那两个百分比是重灾区** —— `1 4.76%` / `2 9.52%` 是「下回合抽到某张牌的概率（该牌剩 1 张 / 剩 2 张时）」，但界面上没有任何东西说明这一点，鼠标悬停也没有提示。

替换为 Firestone 式三行头：

```
第 1 行   套牌名称          手牌数  牌库数
第 2 行   套牌胜率     58.7%      27 / 19
第 3 行   对阵 <对方职业>  62.5%   10 / 6
```

- 第 1 行的数字沿用 `CardCounter` 现有的 `deckCount` / `handCount` 数据源，只换呈现
- 第 2/3 行需要统计数据，数据源待调研（`StatsManager` 下已有胜率统计，第 3 行的「对阵职业」维度是否现成需确认）
- 套牌名称沿用 `Settings.showDeckNameInTracker`（`:451`）

**注意**：第 3 行依赖「已知对手职业」，开局前应显示占位或整行隐藏。

### 2.5 ETC（牛头人酋长）改为悬停展开

现在备牌占一块独立区域，完整铺开三张卡条 —— `Tracker.swift:123` `playerSideboards.update(sideboards:)`，高度按 `Tracker.swift:337` 的 `count * cardHeight + smallFrameHeight * sideboardCount` 算，很占竖向空间。

改为：**ETC 本体只显示一条卡条**，光标移上去时才浮出它所携带的三张卡（形态参照现有的「相关牌」衍生物提示）。实现落点 `DeckSideboards.swift`。

### 2.6 关联卡牌高亮加强

能力已经有：`CardBar.swift:348` 读 `card.highlightColor`，主题资源在 `ThemeElement.swift:174-176`（`highlight_teal.png` / `highlight_orange.png` / `highlight_green.png`）。

问题**纯粹是视觉强度不够** —— 例如光标移到弑君者，牌库里所有传说牌确实会高亮，但在游戏画面背景上几乎看不出来。属于主题资源 + 混合模式的调整，不需要动数据层。

### 2.7 已打出段的卡条形态

三段式落地后，**抽到过的牌不再暗色处理，直接移出「牌库中」段**。现在的暗色逻辑在 `AnimatedCardList.swift:45` 和 `CardBar.swift:362`（`card.count <= 0 || card.jousted`），分段后这两处的暗色分支应当废弃 —— 暗色卡条留在原位会持续抢占视觉注意力，这正是要解决的问题。

「已打出」段的卡条右侧加状态图标（参照 Firestone）：

| 图标 | 含义 |
|---|---|
| 骷髅 | 进了坟场 |
| 火焰 | 被弃 / 被撕 / 爆牌销毁 |

`wasDiscarded` 字段已存在（`AnimatedCardList.swift:183`、`CardBar.swift:890` 都在比较它），坟场数据见 Phase 2.1 引用的 `Player.swift` 分区数组。

---

## Phase 3 — 补全简体中文

### 3.0 先合并 gaenyong fork 的现成翻译（已实测覆盖率）

`gaenyong/HSTracker@9e7b653f`（"Update Simplified Chinese translations"，2026-07-16，+1081/-194）。已把该 commit 的 16 个 `.xcstrings` 拉下来与我们 HEAD **逐 key 比对**，实测结果：

**我们缺 410 个 zh-Hans，它能补上 139 个（34%），剩 271 个。** 另有 **77 个 key 它给了不同（多数更准）的译法**，值得逐条采纳。

直接归零的目录：

| 目录 | 我们缺 | 它补上 | 剩余 |
|---|---|---|---|
| `UIs/mul.lproj/MainMenu.xcstrings` | 41 | **41** | **0** |
| `UIs/StatsManager/mul.lproj/LadderTab.xcstrings` | 12 | 12 | 0 |
| `UIs/Preferences/mul.lproj/PlayerTrackersPreferences.xcstrings` | 6 | 6 | 0 |
| `UIs/Preferences/mul.lproj/OpponentTrackersPreferences.xcstrings` | 5 | 5 | 0 |
| `UIs/StatsManager/mul.lproj/StatsTab.xcstrings` | 4 | 4 | 0 |
| `UIs/Preferences/mul.lproj/TrackersPreferences.xcstrings` | 5 | 4 | 1 |
| `Translations/macOS/Localizable.xcstrings` | 198 | 67 | 131 |

**MainMenu 41/41 全覆盖**是最大收获 —— 它同时是 4.2 那个菜单栏 bug 的前提条件。

用户点名的那几条，实测逐条结果：
- ✅ Enable Mulligan Guide → 「启用起手留牌指南」
- ✅ Show mulligan overlay at start of game → 「游戏开始时显示起手留牌窗口」
- ✅ Show availability on deck selection screen → 「在卡组选择界面显示起手留牌指南可用性」
- ✅ 分页标题 `Battlegrounds` → 「酒馆战棋」、`Replays` → 「回放」
- ❌ `gV2-en-Cel.title`（Enable Mulligan G-V2）—— **它那边根本没有这个 key**。它的 commit 是 7-16，而我们 HEAD 的 Mulligan V2（`e361ec10` / `e18150db`）在那之后，这条得自己翻
- ❌ 分页标题 `Player` / `Opponent` / `Importing` —— 它那边 key 也不存在
- ❌ 套牌管理器的 `Classes` / `Modes`（`Hyt-EI-Vfy.label` / `BHN-1k-K8M.label`）—— **两边都缺**
- ❌ `Archive` / `Unarchive` —— 两边 `Localizable.xcstrings` 里都没有这两个 key（见 3.3）

**合并注意事项：**
1. **按 key 合并，不要整文件覆盖。** 双方 base 不同：它的文件里有我们没有的 key（`HSReplayPreferences` 多 8、`PlayerTrackers` 多 7、`TrackersPreferences` 多 6、`GeneralPreferences` 多 4…），我们也有它没有的（Mulligan V2）。整文件拷贝会把我们 HEAD 的新 key 删掉。
2. **只取 `.xcstrings`，不要碰它那 3 个 `.xib`**（`HSReplayPreferences.xib` / `NewDeck.xib` / `LadderTab.xib`，都是等量增删）。我们 Phase 4 要用 SwiftUI 重做设置页，引入它的 XIB 改动是纯风险。
3. 那 77 条"它译得不一样"的，建议逐条过一遍再采纳 —— 抽查到的几条确实是改进（`显示对手英雄和名字` → `显示对手职业和名字`、`清空对手记牌器` → `对局结束清空对手记牌器`），但不宜无条件全盘接受。
4. upstream 是 MIT，复用没有许可问题；commit message 里注明来源 `gaenyong/HSTracker@9e7b653f`。

### 3.1 剩下 271 条自己补

合并后仍需人工翻译的部分，按影响排序：

| 目录 | 剩余 | 说明 |
|---|---|---|
| `Translations/macOS/Localizable.xcstrings` | 131 | 主catalog，代码里 353 处调用都走它 |
| `UIs/DeckManager/mul.lproj/DeckManager.xcstrings` | 26 | 含用户点名的 `Classes`/`Modes`；该 commit 只改了既有译文、没补新的 |
| `UIs/DeckManager/mul.lproj/EditDeck.xcstrings` | 24 | 同上 |
| `UIs/Preferences/mul.lproj/BattlegroundsPreferences.xcstrings` | 23 | commit 完全没碰 |
| `UIs/Battlegrounds/Session/mul.lproj/BattlegroundsSession.xcstrings` | 19 | commit 完全没碰 |
| `UIs/Preferences/mul.lproj/ImportingPreferences.xcstrings` | 16 | **0% 中文**，就是截图里的 "Importing" 整页；commit 没碰 |
| `UIs/Trackers/mul.lproj/BobsBuddyPanel.xcstrings` | 16 | **0% 中文**；commit 没碰 |
| `HSReplay/mul.lproj/HSReplayPreferences.xcstrings` | 9 | |
| `UIs/Preferences/mul.lproj/MercenariesPreferences.xcstrings` | 5 | **0% 中文**；commit 没碰 |
| `UIs/Preferences/mul.lproj/TrackersPreferences.xcstrings` | 1 | Mulligan V2 那条 |
| `UIs/Preferences/mul.lproj/GeneralPreferences.xcstrings` | 1 | |

### 3.2 先把埋着的翻译挖出来
`HSTracker/UIs/zh-Hans.lproj/MainMenu.strings` 等一整套 per-language `.lproj/*.strings` **完全没有被 `project.pbxproj` 引用**（`grep -c "zh-Hans.lproj" project.pbxproj` → 0），是 Xcode 15 之前格式的遗留，从不参与编译。里面有现成的中文翻译从未上线。

→ 先把这些文件里的译文迁移进 String Catalog（可能还能再啃掉 3.1 里的一部分），**然后删除整套死目录**，避免以后再有人对着不生效的文件改翻译。

### 3.3 修两个"翻译了也不生效"的代码 bug
- `HSTracker/HSReplay/HSReplayPreferences.swift:15`：`var preferencePaneTitle = "HSReplay"` 是**裸字符串**，没走 `String.localizedString` —— 翻译了也不会用上。→ 包起来。
- `HSTracker/UIs/DeckManager/DeckManager.swift:693-694`：XIB 里 `Archive` 明明已译为「存档」，却在运行时被 `String.localizedString("Archive")` 覆写；而 `Localizable.xcstrings` 里根本没有 `Archive`/`Unarchive` 这两个 key（只有 `Archived`），于是 `String.localizedString`（`HSTracker/Core/Extensions/String.swift:81-93`）回退后**原样返回 key**，显示英文。→ 补这两个 key。

> 注意 `String.localizedString` 的失败是静默的：key 完全不存在时它返回 key 本身，界面上看起来就是"没翻译"，不会有任何报错。补完后建议加一个跑一遍所有 key 的调试断言。

---

## Phase 4 — 设置界面 + Dock 菜单

### 4.1 Dock 菜单「卡组」点了没反应

用户截图里的是 **Dock 菜单**（`AppDelegate.swift:459-489` 全代码构建，所以标题是中文的），不是菜单栏。有两条嫌疑路径，**先跑起来加日志定位是哪条**（`AppDelegate.playDeck(_:)` 在 `AppDelegate.swift:572-578`，三个静默出口一个日志都没有）：

1. `AppDelegate.swift:509` Dock 子菜单项是 `classmenuitem.copy() as? NSMenuItem`，依赖 `NSCopying` 把整棵子菜单的 `representedObject` 带过去。若没带过去，`playDeck` 里 `sender.representedObject as? Deck` 的 `if let` 直接失败返回 —— 完美的静默 no-op。
2. 套牌其实**设置成功了**，但 `Game.updatePlayerTracker()` 被 `Game.swift:335-341` 挡住：要求 `currentGameType != .gt_unknown`，而 `currentGameType`（`Game.swift:1147-1169`）在 `currentMode != .gameplay` 时恒返回 `.gt_unknown`。也就是说**没进对局就不显示记牌器**，而从 Dock 选套牌恰恰是在没进对局时做的 —— 零视觉反馈。菜单项也没打勾，也没有 toast。

修法（两条都做，互不冲突）：
- `representedObject` 改存 **`deck.deckId` 字符串**而非活的 Realm `Deck` 对象。顺带解决另一个隐患：`RealmHelper.getActiveDecks()`（`RealmHelper.swift:139-155`）返回的是活对象、被菜单项无限期持有，套牌被删后 `deck.deckId` 会抛异常；而 `Game.set(activeDeckId:)`（`Game.swift:1731`）按 id 取不到时走 else 分支**静默清空** `currentDeck`/`originalClass`/`currentClass`，等于选个旧套牌反而把记牌器重置了。
- 加可见反馈：选中项 `.state = .on`，并弹一个 Toast（`HSTracker/UIs/Toast/` 已有现成组件）。

### 4.2 顺带修菜单栏（同一个 bug 的另一面）

`AppDelegate.swift:440` 用 `mainMenu?.item(withTitle: String.localizedString("Decks", comment: ""))` 按**标题字符串**找菜单项。中文下 `String.localizedString("Decks")` 返回「卡组」，但菜单栏来自 `UIs/Base.lproj/MainMenu.xib`、由 zh-Hans 覆盖率为 **0/41** 的 `MainMenu.xcstrings` 本地化 —— 实际标题还是英文 `Decks`。查不到 → 返回 nil → 后面全是可选链 no-op → **菜单栏的「卡组」子菜单从来就没被填进过任何套牌**。

同样的写法还坑了 `:514` 的 `Replays` 和 `:546` 的 `Window`（`Window` 有中文「窗口」但 XIB 标题是英文，于是 `:547-550` 的"锁定/解锁窗口"切换也永远不更新）。

→ 改为按 **tag 或 IBOutlet** 定位菜单项，不再按标题字符串。Phase 3 补上 `MainMenu.xcstrings` 之后，标题查找会以另一种方式再坏一次（变成中文能查到、英文查不到），所以**这个改法是必须的，不是可选的**。

### 4.3 设置界面重做

现状：SPM 包 `sindresorhus/Preferences`（`AppDelegate.swift:44-59`）+ 9 个 XIB 面板。`TrackersPreferences.xib` 是 469 行、20 个 checkbox 平铺在 `NSStackView` 里、54 条手写约束、**没有分组框、没有分节标题、没有说明文字**，全部汇入 `TrackersPreferences.swift:109-176` 一个巨大的 `if/else if` 链按 `sender ==` 比对。这就是"粗糙"的来源。

既然已经上了 macOS 14 + SwiftUI，用 SwiftUI 的 `Form` + `Section` 重建面板，原生外观直接就对了，还自带分节标题和 footer 说明。

**先只做 Trackers 一页**（问题最集中、20 个开关最需要分组），验证 `NSHostingController` 接进 `PreferencePane` 协议的接法可行后，再逐页迁移。分页标题与图标定义在各控制器的 13/15/17 行（`preferencePaneIdentifier` / `preferencePaneTitle` / `toolbarItemIcon`），图标资源在 `HSTracker/Assets/Assets.xcassets/settings-*.imageset`，这部分不动。

---

## Phase 5 — 计数器 overlay 可自由拖动

场攻 / 无界空宇 / 大范等计数器（`CountersOverlay.swift`，由 `CounterSystem/` 下的 `StatsCounter` 子类供数）**位置写死**，用户无法拖到自己习惯的位置。

现在的位置由 `SizeHelper.playerCountersFrame()`（`:609`）和 `opponentCountersFrame()`（`:602`）按炉石窗口算出来，每次刷新都重算，因此拖了也会被弹回去。

**已有现成范式可照抄** —— `TimerHud` 就是可拖动且位置持久化的：

```
TimerHud.swift:76     拖动结束 → Settings.timerHudFrame = self.window?.frame
Settings.swift:383    @UserDefaultCustom(key: timer_hud_frame, defaultValue: nil)
Game.swift:443        重新定位时优先读 SizeHelper.timerHudFrame()
```

照这个模式给两个 counters overlay 各加一个持久化 frame，`nil` 时回落到现有算法。**需要额外考虑**：计数器数量会随对局变化（新增/移除计数器），持久化的应当是**锚点**而非绝对 rect，否则计数器变多时会溢出屏幕。

设置里应提供「重置计数器位置」入口（Phase 4.3 设置界面重做时一并做）。

---

## 关键文件清单

| 文件 | 涉及阶段 |
|---|---|
| `HSTracker.xcodeproj/project.pbxproj` | 0.1（部署目标） |
| `HSTracker/Logging/Game.swift` | 0.2 / 0.4（`:42` `:1569-1600`）、2.3（`:1508`）、4.1（`:335-341`） |
| `HSTracker/Core/SizeHelper.swift` | 0.3（`:37-118`） |
| `HSTracker/UIs/Trackers/WindowManager.swift` | 0.5（`:418-483`） |
| `HSTracker/UIs/Trackers/SwiftUI/*`（新建 6 个文件） | 1 / 2.2 |
| `HSTracker/UIs/Trackers/Tracker.swift` | 1（内容视图换成 `NSHostingView`，删 `:127-405`） |
| `HSTracker/UIs/Cards/CardBar.swift`（+ 4 个主题子类） | 1.1（最终删除） |
| `HSTracker/UIs/Trackers/AnimatedCardList.swift` / `DeckLens.swift` / `DeckSideboards.swift` | 1.3 / 2.2（最终删除） |
| `HSTracker/UIs/ImageUtils.swift` | 1.2（`:119-146`、`:36-39`） |
| `HSTracker/Logging/Player.swift` | 2.1（新增 `playerCardGroups`，复用 `:183-186` `:531-663`） |
| `HSTracker/Core/Settings.swift` | 2.3（~`:352` / ~`:652`） |
| `Translations/macOS/Localizable.xcstrings` + 22 个 `mul.lproj/*.xcstrings` | 3 |
| `HSTracker/AppDelegate.swift` | 4.1 / 4.2（`:431-556`、`:572-578`） |
| `HSTracker/UIs/DeckManager/DeckManager.swift` | 3.3（`:693-694`） |
| `HSTracker/HSReplay/HSReplayPreferences.swift` | 3.3（`:15`） |

---

## 验证

本机 `/Applications/Hearthstone` 与 `/Applications/HSTracker.app` 都在，可以真机验证。

**构建**：`Config.xcconfig` 需把签名两行注释对调改成本地签名（`CODE_SIGN_IDENTITY = -`）。README 强调 **HSTracker 必须签名才能正常工作**（要 Accessibility 权限）。注意 `CONTRIBUTING.md` 明确说 `Config.xcconfig` 的改动不要提交。SwiftLint 本机**未安装**，若 build phase 依赖它需先 `brew install swiftlint`。

**Phase 0/1（性能）** —— 必须有对照数据，不能凭手感：
1. 开 Instruments 的 Time Profiler + Core Animation FPS，挂上 HSTracker
2. 用 `Settings.useSwiftUITracker` 开关跑同一局的新旧两版，各记一次
3. 关键指标：对局中 HSTracker 主线程 CPU 占用、`CardBar.draw`/`CardRowView` 体感耗时、`AnimatedCardList.updateFrames` 是否已从火焰图消失
4. 专门验窗口跟随：对局中拖动/缩放炉石窗口，overlay 应立即跟上（改前是最多 2 秒）
5. 长局观察内存曲线，确认 flash 图层泄漏（`CardBar.swift:243-272`）已消失

**Phase 2（分区）**：打一局，逐一确认——抽到的牌从「牌库」移进「手牌」；打出后进「已打出」并变暗；三段数量之和恒等于原牌表；关掉 `groupCardsByZone` 能干净回到平铺；对手侧未链接牌表时保持平铺、不泄露手牌信息。

**Phase 3（中文化）**：把系统语言/应用语言切到简体中文，逐页翻设置的 9 个分页 + 套牌管理器 + 菜单栏，确认无残留英文、无裸露的 key 字符串（key 泄漏是 `String.localizedString` 静默失败的特征）。

**Phase 4（菜单）**：不启动炉石，从 Dock 菜单选一个套牌 → 应看到 Toast + 菜单项打勾；再启动炉石进对局 → 记牌器应用的就是那副牌。切中文后重复一遍，确认菜单栏「卡组」子菜单确实被套牌填充了。

**回归面**：`HSTrackerTests/` 有测试目标，改完 `Player.swift` 后跑一遍（`Cmd+U`）。

---

## 风险与顺序

- **Phase 0 必须先于 Phase 1**。先上 SwiftUI 而不动 0.2/0.3，新渲染层照样被 500ms 节流和主线程 AX 阻塞卡住，会得出"SwiftUI 也没变快"的错误结论。
- **0.4 依赖 0.3**。AX 调用还在主线程时就提高窗口轮询频率，会比现在更卡。
- **Phase 1 是本计划的绝大部分工作量**。`CardBar` 是 908 行、4 个主题、十几种叠加元素，逐元素比对像素是免不了的。A/B 开关就是为此存在。
- **Phase 2 依赖 Phase 1**，在旧 AppKit 布局里塞三个分段要重写 `Tracker.updateFrames()` 的高度计算，是白扔的工。
- **Phase 3 与 4.2 有耦合**：补完 `MainMenu.xcstrings` 会让 `item(withTitle:)` 的查找从"英文下能用"翻转成"中文下能用"，两边都得改。4.2 换成 tag/outlet 定位是硬性前提，不是可选优化。
- **Phase 3、4 与 0–2 完全独立**，可以任何时候并行做。

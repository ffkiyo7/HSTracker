# Phase 1 / T6 — 根视图 `TrackerView` + 布局收口

先读 `docs/tasks/_common.md`，再读 `docs/PLAN.md` Phase 1 一节（尤其 1.3 / 1.4 / 1.5 和「目录结构」表）。
本片是 Phase 1 切片表的 **T6**，对应实测卡点 ③。⚠️ 别和 Phase 0 / T6（延迟）搞混。

## 现状

T2 / T4 / T5 各做了一块 SwiftUI，但都是以 `NSHostingView` 当兄弟视图挂进老 `Tracker` 窗口：

| host（`Tracker.swift:31-37`） | 内容 | 来自 |
|---|---|---|
| `swiftUIHeader` | 三行头 | T5 |
| `swiftUICards` | 主牌表 | T2 |
| `swiftUIPlayerTop` / `swiftUIPlayerBottom` / `swiftUIOpponentRelatedCards` | 置顶 / 置底 / 相关牌 | T4 |

真正的排版仍是 `Tracker.updateFrames()`（`Tracker.swift:371` 起，约 300 行）在做：算每段高度、从上往下减 `y`、
逐个 `host.frame = NSRect(...)`，并在开关关闭时把旧视图 / 新 host 互相 `isHidden`。文件里 `useSwiftUITracker` 分支约 30 处。

## 要做出什么

`Settings.useSwiftUITracker` 为 true 时，记牌器内容区只挂**一个** host，里面是根视图 `TrackerView`，
由它自己按设置条件拼装三行头 + 各段并完成排版。数据经 `TrackerViewModel` 进入。
两个文件名沿用 PLAN「目录结构」表。

为 false 时**逐字回到现状**：旧路径的每一行代码、每个 outlet 的 frame 计算都不许变。

## 硬约束

- **行高压缩公式必须保住**：`cardHeight = min(cardHeight, (windowHeight - offsetFrames) / totalCards)`（`Tracker.swift:560`）。
  卡多时行高自动压缩是上游行为。行高常量沿用 `CardSize.swift` 的五个值；`smallFrameHeight = round(40 / ratio)` 这一套比例换算也沿用。
- **每段的高度、顺序、间距与现状逐像素一致**。段头高度、段间那个 `+ 5`、三行头 `smallFrameHeight × 行数` 都是现状定义，不是本片可以重新设计的东西。
  对手侧的 hero 卡条（`playerClass`，AppKit）不在本片范围，根视图从它下面开始。
- **一次刷新不许重建视图树**（PLAN 1.3）。段的显示 / 隐藏用条件视图，不许每帧重新 `addSubview`。
- **悬停**：段身份作为参数传入（T2 / T4 的 host 已经这么做，`Tracker.swift:199-330`），不许回到 superview 遍历。
  旧路径的 `getHoverComponent()`（`:836`）留给「收尾」阶段删，本片不动。
- 胜率查询 / 原画加载的刷新时机沿用 T5 的缓存键逻辑，不许因为搬家变成每帧查 Realm。
- 所有 view model 写入必须在主线程；上游 3.6.8 / 3.6.9 加了 `MainThreadGuard.assertMainThread()`，命中即 trap。
- 新视图透明；整体不透明度仍涂在 window 背景上（`Tracker.swift:113`）。
- 不动窗口层（`WindowManager` / `SizeHelper`）、不动 `Player.swift` / `Game.swift`、不改 `.xib` / `.xcstrings`。
- 不做动效（T8）、不做分区（Phase 2）。

## 允许修改的文件

- `HSTracker/UIs/Trackers/Tracker.swift`
- `HSTracker/UIs/Trackers/SwiftUI/` 下已有文件（现有 host 类怎么处置由你定，但 `CardRowView` 的外观不许变）
- 新增 `TrackerView.swift`、`TrackerViewModel.swift`，**必须手工登记进 `project.pbxproj`**（4 处，见 `AGENTS.md`「构建」）；只允许这一类 pbxproj 改动

## 验收

1. 受限环境 Debug build `BUILD SUCCEEDED`（命令见 `AGENTS.md`「构建」）。
2. 测试 target 仍 50 / 50 全绿：同一命令把 `build` 换成 `test`。
3. 报告里给出：
   - **新旧两条路径每段高度的逐项对照表**，至少覆盖三种配置：只有主牌表；主牌表 + 置顶 + 置底；卡数多到触发行高压缩。
     算法从代码里推，不是跑一遍看。
   - 压缩公式现在住在哪、`updateFrames()` 在 SwiftUI 路径下还剩什么。
   - 开关关掉后哪些代码路径被走到；`useSwiftUITracker` 分支数从多少降到多少。
4. ✅ ~~卡点 ③ 由用户实战看：**整个布局**，独占一局，各段都有内容的套牌最好。不排在本次验收里。→ 2026-09-11 实战通过。~~

## 汇报

结果写进本文件末尾「执行结果」一节，格式照 `docs/tasks/phase1-t5-tracker-header.md`。
**不要 commit、不要动 `docs/PLAN.md` / `docs/PROGRESS.md`**。

## 执行结果（2026-09-09）

- 新增 `TrackerViewModel.swift`（根 view model：持有 header + 四个卡表的子 model，并算出 `TrackerLayout`）和 `TrackerView.swift`（根 `VStack` + 唯一的 `TrackerRootHost`），已按 4 处登记进 `project.pbxproj`。
- 开关打开时窗口里只剩两个视图：AppKit 的对手 hero 卡条（`playerClass`，我方恒隐藏）和内容区那一个 host。`TrackerCardListHost` / `TrackerSectionHost` / `TrackerHeaderHost` 三个兄弟 host 类删除，`TrackerTransparentHostingView`、`TrackerCardListView`、`TrackerSectionView`、`TrackerHeaderView`、`CardRowView` 的外观代码一行没动。
- 段的显示/隐藏改成根视图里的 `if`（条件视图），不再是每帧改 frame + `isHidden`；卡表本身仍是 `ForEach` + 稳定 id，一次刷新不重建视图树。
- 悬停身份仍是参数：`ensureSwiftUIRoot()` 建 host 时一次性把 `.playerCardView`/`.opponentCardView`、`.playerTop`、`.playerBottom`、`.opponentRelatedCards` 绑到四个 list view model 的 `onHover` 上。`getHoverComponent()` 只剩旧路径在用，按任务书没动。
- 胜率查询仍走 T5 的缓存键（`updateSwiftUIHeader` 原样保留，只把写入目标从 header host 换成 `root.viewModel.header`），没有变成每帧查 Realm。

### 每段高度：旧路径 vs 新路径

算法从代码推。共同前提：我方记牌器、`cardSize = .big`（`ratio = 1`，`smallFrameHeight = round(40/1) = 40`，行高常量 `kRowHeight = 34`）、`contentView` 高 700、hero 卡条隐藏（`startHeight = 0`）、三行头只有第 1 行（`headerHeight = 1 × 40 = 40`）、`showGraveyard = false`。

| 段 | ① 只有主牌表（15 张） | ② 主 10 + 置顶 2 + 置底 3 | ③ 主 30 + 置顶 2 + 置底 3（触发压缩） |
|---|---|---|---|
| 预留 `offsetFrames` | 40 → 40 | 120 → 120 | 120 → 120 |
| `totalCards` | 15 → 15 | 15 → 15 | 35 → 35 |
| 行高 | 34 → 34（`(700-40)/15 = 44` 不压缩） | 34 → 34（`(700-120)/15 = 38.7`） | 16.571 → 16.571（`(700-120)/35`） |
| 三行头 | 40 → 40 | 40 → 40 | 40 → 40 |
| 置顶段 | — | 113 → 113（`2×34+40+5`） | 78.14 → 78.14 |
| 主牌表 | 510 → 510 | 340 → 340 | 497.14 → 497.14 |
| 置底段 | — | 147 → 147（`3×34+40+5`） | 94.71 → 94.71 |
| 内容合计 | 550 → 550 | 640 → 640 | 710 → 710 |
| `bottomY` | 150 → 150 | 60 → 60 | −10 → −10 |

逐项相等。两处是刻意对齐、不是自然结果：

1. **段间那个 `+5` 不进 `offsetFrames`**（上游如此），所以满压缩时内容会比可用高度多 `5 × 段数`（③ 的 710 = 700 + 5×2，`bottomY` 因此为负）。新路径照抄，没有"顺手修正"。
2. **`showGraveyard` 仍占一行预留**：坟场计数在 SwiftUI 路径下从不绘制（T5 就隐藏了），但旧代码照样 `offsetFrames += smallFrameHeight`。新路径用 `reserveGraveyardRow` 参数保住。同配置 ③ 若开坟场：两条路径都是 `(700−160)/35 = 15.43`。

### 压缩公式住哪、`updateFrames()` 还剩什么

- 公式在 `TrackerViewModel.updateLayout(availableHeight:frameHeight:reserveGraveyardRow:)`：`cardHeight = min(baseCardHeight, (availableHeight - offset) / totalCards)`。`availableHeight` 是 hero 卡条以下的窗口高，等价于原来的 `windowHeight - offsetFrames`（hero 卡条那份 `smallFrameHeight` 从两边同时消掉）。行高常量仍取 `CardSize.swift` 的五个值，`smallFrameHeight = round(40 / ratio)` 仍由 `Tracker` 按 `Settings.cardSize` 算好传进来。
- **没有用 `GeometryReader`**（PLAN 1.4 的写法）：`Tracker.bottomY`（对手侧 tracking area / 关联牌组浮窗）必须和渲染出来的高度是同一个数，`GeometryReader` 量到的值 `Tracker` 拿不到，两套算法迟早漂移。改成 view model 算一次，视图和 `bottomY` 都读它。
- SwiftUI 路径下 `updateFrames()` 只剩 `updateSwiftUIFrames()` 这一段：藏掉 5 个旧面板和 5 个旧卡表 outlet、按设置摆对手 hero 卡条、调 `updateSwiftUIHeader()`、把 `availableHeight / frameHeight / showGraveyard` 交给 view model、给 host 一个整块 frame、按 `layout.contentHeight` 反算 `bottomY`。没有任何逐段的 `y -=`。
- 顺带不再每帧做的两件事（都只喂隐藏视图）：坟场 entity→card 的字典统计，和 `recordTracker.message` 赋值。开关一关，下一次 `updateFrames()` 立刻补回。

### 开关关掉

- 走 `updateLegacyFrames()` + `update(cards:...)` 的 `else` 分支：`cardsView` / `playerTop` / `playerBottom` / `playerSideboards` / `opponentRelatedCards` / `cardCounter` / `playerDrawChance` / `opponentDrawChance` / `recordTracker` / `graveyardCounter` / `playerClass` 全部按老算法排，逐行搬过来没改语义；根 host 一次性 `frame = .zero` + 隐藏，并把 `cardsView` 解除隐藏。
- 唯一的结构性改动是 hero 卡条抽成 `layoutHeroBar(cardId:windowWidth:windowHeight:height:hideCost:)` 给两条路径共用，语句逐条照搬（包括上游那句 `width: windowHeight` 的写法，没有改成 `windowWidth`）。
- `Settings.useSwiftUITracker` 分支：**23 处 → 3 处**（`update(cards:)`、`updateFrames()`、`highlightPlayerDeckCards()` 各一）。`Tracker.swift` 1061 行 → 878 行。

### 验收

- `xcodebuild ... build`：`** BUILD SUCCEEDED **`
- `xcodebuild ... test`：`** TEST SUCCEEDED **`，`Executed 50 tests, with 0 failures`
- 改动文件全量重编，无新增编译警告。
- ✅ ~~卡点 ③（整个布局）2026-09-11 用户实战通过：「布局 ok」。~~

## review（Claude，2026-09-10）通过

逐行核对了 `Tracker.swift` 的 diff 和两个新文件：SwiftUI 路径的段顺序（hero → 三行头 → 置顶 → 主表 → 置底 → 相关牌）、
`offsetFrames` 的构成（hero 两边同时消掉、坟场行照旧预留）、`bottomY = availableHeight − contentHeight` 与旧的逐段 `y -=` 等价；
旧路径 `layoutHeroBar` 抽取逐句对得上（含 `width: windowHeight` 那句上游写法）。悬停身份仍是绑定时传参。
不用 `GeometryReader` 的理由成立（`bottomY` 必须与渲染高度同源）。未发现需要返工的地方。

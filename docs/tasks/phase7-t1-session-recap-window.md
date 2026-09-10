# Phase 7 / T1 — 局末小结弹窗（D2 记牌器同款）

先读 `docs/tasks/_common.md`，再读 `docs/PLAN.md` Phase 7 一节。
设计定稿 **D2**，对照页 https://claude.ai/code/artifact/5f974e11-72ec-424a-9ec5-053759a6aaa4（看不到就按下面的文字定义做）。

## 要做出什么

炉石进程退出时弹一个独立小窗，列出**本次会话**（炉石启动 → 退出）打过的构筑对局：总账一行，
下面按套牌分组，每组一行胜率 + 逐局明细。用户手动关闭，不自动消失。

```
┌ 本次小结 · 20:41 – 22:56 ─────────────────────┐
│ 本次 7 局                    57.1%     4 / 3   │   ← 总账行（fade 底）
├ 🔮 火妖法                    66.7%     2 / 1   ┤   ← 套牌行（fade 底，职业图标）
│     vs 🏹 猎人      20:41    9 回合       胜    │   ← 逐局行
│     vs ⚔ 战士       20:58   12 回合       负    │
│     …                                          │
├ ✝ 宇宙牧                     50.0%     2 / 2   ┤
│     …                                          │
│ 2 小时 15 分                          [ 关闭 ]  │
└────────────────────────────────────────────────┘
```

## 已决（用户 2026-09-10 定）

| 项 | 决定 |
|---|---|
| 触发 | 炉石退出时弹一次，钩子是 `CoreManager.appTerminated`（`CoreManager.swift:440` 附近，`setHearthstoneRunning(flag: false)` 那一段） |
| 会话边界 | `setHearthstoneRunning(flag: true)`（`:433`）时记起点，退出时结束 |
| 形态 | 独立 `NSWindow`，普通窗口层级，不挂 overlay、不受 `hideAllWhenGameInBackground` 影响 |
| 自动消失 | **不**。用户点关闭或 ESC |
| 0 局 | **不弹** |
| 「打开统计」 | **接现有统计窗**：复用 `Statistics`（`HSTracker/UIs/StatsManager/Statistics.swift`，目前是 `DeckManager` 上的 sheet，按套牌）。每个套牌行给一个入口，打开该套牌的统计。不许新做统计 UI |

## 视觉：逐字沿用三行头

`TrackerHeaderView.swift` 的 `HeaderStyle` 就是规范：文字字体 `TrackerTextFont.name`、数字字体 `Belwe Bd BT`、
胜 `#62D97A` / 负 `#FF6B5E`、格线 `white 18%`、边框 `#141617`、底 `#23272A`、三列 `1fr / 62 / 76`（按 `smallFrameHeight / 40` 缩放，本窗取 1）。
总账行和套牌行铺当前主题的卡条 `fade.png`（`TrackerFade`，`CardRowView.swift`），和三行头同一做法。
`HeaderStyle` 现在是 `private`，**允许把它和需要的辅助类型改成 internal**，但 `TrackerHeaderView.swift` 里别的一行都不动 ——
这个文件有 T6 尚未提交的改动在工作区里，不要还原。

职业图标用 `Classes.xcassets/<class>.png`（三行头已在用）。固定深色，不跟系统外观。

## 数据

- 对局记录已在 Realm：`Deck.gameStats`（`GameStats`：`playerHero` / `opponentHero` / `result` / `turns` / `startTime` / `endTime` / `wasConceded` / `gameMode` / `gameType`）。
  **不新采集**，在 `RealmHelper` 加一个按 `startTime >= 会话起点` 取的查询即可（参考 `getValidStatistics()`）。
- 只算构筑类对局（标准 / 狂野 / 经典 / 休闲 / 竞技场 / 乱斗）；战棋、佣兵、对 AI 排除。**用户不玩战棋，但过滤要写对**。
- 胜率 = 胜 /（胜 + 负），平局和未知结果不计入分母，明细里照样列出。
- 套牌名、职业取自 `Deck`；找不到套牌的记录（套牌已删）归到「未知套牌」一组，不许丢。
- 会话起点存在内存即可，不落盘；HSTracker 自己重启则会话重新开始。

## 硬约束

- **`Settings.quitWhenHearthstoneCloses` 打开时**：弹窗照弹，等用户关掉弹窗再退出 HSTracker；0 局时照原逻辑直接退出。
- 加一个 `Settings` 开关（默认开），命名别撞上游战棋的 `showSessionRecap`。**本片不加设置 UI**，报告里写明 key 名，Phase 4 再接。
- 窗口内容用 SwiftUI（`NSHostingController`），Phase 4 已验证接法。局数多时窗口限高、内容滚动，最大高度别超过屏幕的 80%。
- 弹窗要在主线程；`appTerminated` 的回调线程自己核实。
- 新增文案要有 en + zh-Hans，加在默认 `Localizable.xcstrings`（T5 的先例）；**其它 `.xcstrings` / `.xib` 不动**。
- 不动 `Tracker.swift`、`TrackerView.swift`、`TrackerViewModel.swift`、`Game.swift`、`Player.swift`、`WindowManager`。
- 工作区里已有 T6 的未提交改动（`Tracker.swift`、`SwiftUI/` 下几个文件、`project.pbxproj`）和文档改动，**不要还原、不要顺手改**。

## 允许修改的文件

- 新增 `HSTracker/UIs/SessionRecap/` 目录下的 `.swift`（视图、view model、window controller、会话数据模型），**手工登记进 `project.pbxproj`**（4 处，见 `AGENTS.md`「构建」；T6 刚登记过两个文件，照那个格式）
- `HSTracker/Logging/CoreManager.swift`（只加起点记录 + 触发弹窗）
- `HSTracker/Database/RealmHelper.swift`（只加查询）
- `HSTracker/Core/Settings.swift`（只加开关）
- `HSTracker/AppDelegate.swift`（仅在需要持有 window controller 时）
- `HSTracker/UIs/Trackers/SwiftUI/TrackerHeaderView.swift`（仅改可见性）
- `HSTracker/Resources/Localizable.xcstrings`（或项目里默认表所在路径，自己找）

## 验收

1. 受限环境 Debug build `BUILD SUCCEEDED`（命令见 `AGENTS.md`「构建」）；测试 50 / 50。
2. 报告里写清：钩子插在哪一行、回调线程、`quitWhenHearthstoneCloses` 两种情况的时序；过滤掉哪些 `gameMode` / `gameType`；Settings key 名；「打开统计」怎么复用 `Statistics`（sheet 还是独立窗，为什么）。
3. ✅ ~~用户实战：打完一局退出炉石，看弹窗：局数、套牌、职业、胜率、逐局明细对不对；关闭后不再弹；点「打开统计」进对应套牌。**与 Phase 1 卡点 ③ 同一次验收**。→ 2026-09-11 实战通过，用户反馈「做的不错」；设置开关的 UI 留到 Phase 4 / 4.3 补。~~

## 汇报

结果写进本文件末尾「执行结果」一节，格式照 `docs/tasks/phase1-t6-tracker-root-layout.md`。
**不要 commit、不要动 `docs/PLAN.md` / `docs/PROGRESS.md`**。

## 执行结果（2026-09-10）

- 新增 `HSTracker/UIs/SessionRecap/` 三个文件，已按 4 处（`PBXBuildFile` / `PBXFileReference` / 新建 `SessionRecap` group 挂进 `UIs` / `Sources` phase）登记进 `project.pbxproj`：
  - `SessionRecap.swift` —— 会话边界（内存里的 `sessionStart`）、构筑过滤、Realm 结果聚合成纯 Swift 结构（`SessionRecapSummary` / `SessionRecapDeck` / `SessionRecapGame`）。
  - `SessionRecapView.swift` —— D2 表格，字体 / 颜色 / 格线 / `1fr · 62 · 76` 三列全部读 `HeaderStyle`，总账行与套牌行铺 `TrackerFade`。
  - `SessionRecapWindowController.swift` —— 独立 `NSWindow` + `NSHostingController`，ESC / 关闭 / 「打开统计」。
- `CoreManager.swift` 三处：`:66`（炉石已在跑时补记会话起点）、`:439`（`appLaunched` 记起点）、`:457`（`appTerminated` 触发弹窗并接管退出时序）。
- `RealmHelper.swift` 只加了 `getStatistics(since:)`，照 `getValidStatistics()` 的写法。
- `Settings.swift` 加开关 `showConstructedSessionRecap`（key `show_constructed_session_recap`，默认 **开**）。本片不加设置 UI。
- `TrackerHeaderView.swift` 只把 `private enum HeaderStyle` 改成 `enum HeaderStyle`（加一行说明），别的一行没动。
- `Translations/macOS/Localizable.xcstrings` 新增 11 个 `session_recap_*` key，en + zh-Hans。`AppDelegate.swift` 没动 —— window controller 自己用 `static retained` 持有。

### 钩子、线程、退出时序

- 钩子在 `appTerminated`，紧跟 `Watchers.experienceWatcher.stop()`（`CoreManager.swift:457`）。
- **回调线程已核实是主线程**：`startListeners()`（`:406`）用 `center.addObserver(forName:object:queue: OperationQueue.main)` 注册全部五个 workspace 通知，所以 `appTerminated` 本身就在主线程。`showIfNeeded()` 里加了 `assertMainThread()` 兜底（Debug 命中即 trap）。
- `quitWhenHearthstoneCloses` 两种情况：

  | 情况 | 时序 |
  |---|---|
  | 有构筑对局（弹窗弹出） | `stopTracking` → `setHearthstoneRunning(false)` → `showIfNeeded` 返回 true，窗口 `makeKeyAndOrderFront` + `NSApp.activate` → **不退出**；用户点关闭 / ESC → `windowWillClose` → 回调里才 `NSApplication.shared.terminate` |
  | 0 局 / 开关关掉 / 无会话 | `showIfNeeded` 返回 false → **当场** `terminate`，与改动前逐字同一条路径 |

  开关关掉时仍打原来那句 `logger.info("Not closing app since setting says so.")`。

### 过滤

`gameMode` 白名单 + `gameType` 黑名单，两个都要过：

- 白名单 `GameMode`：`.ranked`、`.casual`、`.arena`、`.brawl`。标准 / 狂野 / 经典 / 扭曲是 `format` 的区别而不是 mode，全落在 `.ranked` / `.casual` 里。被挡掉的：`.battlegrounds`、`.mercenaries`、`.duels`、`.practice`（对 AI）、`.friendly`、`.spectator`、`.none`、`.all`。
- 黑名单 `GameType`（防 mode 记成构筑样子）：`gt_vs_ai`、`gt_tutorial`、`gt_test`、`gt_tb_1p_vs_ai`、`gt_tb_2p_coop`、`gt_fsg_brawl_1p_vs_ai`、`gt_fsg_brawl_2p_coop`，加全部 8 个 `gt_battlegrounds*` 和全部 5 个 `gt_mercenaries*`。
- 胜率 = `StatsHelper.getDeckWinRate`（`wins / (wins + losses)`，无对局返回 -1 → 显示 `--`），平局和 `unknown` 不进分母但照样进 `total` 和明细。

### 「打开统计」

**做成弹窗自己的 sheet**（`window.beginSheet(statisticsWindow)`），不是独立窗：

- `Statistics.xib` 里那个 Close 按钮接的是 `closeWindow:` → `self.window?.sheetParent?.endSheet(...)`。做成独立窗 `sheetParent` 是 nil，**按钮直接变死键**，而 `Statistics.swift` 和 `.xib` 都不在本片可改范围里。做成 sheet 两个 action（`closeWindow:` 和 `deleteStatistics:` 的 `NSAlert.show(window:)`）都原样能用，`Statistics` 一行没动。
- 复用方式和 `DeckManager.showStatistics` 逐字一致：`Statistics(windowNibName: "Statistics")` → 先赋 `deck` 再取 `.window`（顺序不能反，取 `.window` 会加载 nib 并跑 `windowDidLoad`，那里把 deck 传给两个 tab）。
- 套牌行的入口按 `deckId` 在点击时才 `RealmHelper.getDeck(with:)` 重新解析，套牌这期间被删就静默不开。

### 其它实现取舍

- **会话起点**：`appLaunched` 记一次；另外 `CoreManager.init` 里如果炉石已经在跑也记一次 —— HSTracker 后启动时 `appLaunched` 根本不会触发，否则该场会话永远没有起点、永不弹窗。只在内存，不落盘。`endSession()` 取走起点后置 nil，所以同一场会话只可能弹一次。
- **窗口**：`[.titled, .closable, .resizable]`，默认 `.normal` 层级，不经 `WindowManager`，因此 `hideAllWhenGameInBackground` 够不到。标题是 `本次小结 · HH:mm – HH:mm`。高度 `min(内容自然高, 主屏 visibleFrame 高 × 0.8)`，超出部分 `ScrollView` 滚动；`NSHostingController.sizingOptions = []` 是必须的，否则 hosting controller 会把整张表的高度当作窗口首选尺寸，80% 上限失效。ESC 两条路都通：Close 按钮 `.keyboardShortcut(.cancelAction)`，以及 `NSWindow.cancelOperation` 覆写。
- **未知套牌**：`GameStats` 是 `EmbeddedObject`，删套牌会连着删掉它的对局记录，**孤儿记录在这个 schema 下结构上不可能出现**。所以「未知套牌」是防御路径：`deck.isInvalidated`（弹窗开着时用户在套牌管理器删了牌组）或 `deck.name` 为空时归进去，职业取该局的 `playerHero`，并且不给统计入口。分组顺序按会话内首局时间。
- **行阴影**：`.shadow` 挂在 `.background` **之前**，否则 fade 图层自己也投影，会在下一行顶上留一条黑线。

### 验收

- `xcodebuild -project HSTracker.xcodeproj -scheme HSTracker -configuration Debug -destination 'platform=macOS' build`：`** BUILD SUCCEEDED **`
- 同命令 `test`：`** TEST SUCCEEDED **`，`Executed 50 tests, with 0 failures`
- `python3 docs/tasks/tools/check_xcstrings.py --baseline HEAD --allow-new-key …`（11 个新 key）：`✓ 校验通过`
- 改动文件全量重编，无新增编译警告。
- ✅ ~~弹窗的实际观感（局数 / 套牌 / 职业 / 胜率 / 逐局明细 / 关闭后不再弹 / 打开统计）2026-09-11 与卡点 ③ 同一局实战通过。~~

## review（Claude，2026-09-10）通过，改了一处

- 核对：钩子线程（`OperationQueue.main` 注册）、`quitWhenHearthstoneCloses` 两条时序、过滤表、职业名 / 图标的 key 与三行头同源（`CardClass` rawValue 小写，`Localizable` 有 `mage` 等 key）、11 条文案 en + zh-Hans、pbxproj 4 处登记、`TrackerHeaderView.swift` 只动了可见性。
- **改了一处**（`SessionRecapWindowController.showIfNeeded`）：原实现在上一场的小结窗还开着时，第二次退出炉石只把旧窗提前，**新会话的记录永远不显示**，且旧窗的关闭回调（可能是退出 app）仍挂着。改为先 `endSession()` 取新数据，再静默关掉旧窗（清空它的 `onClose`），`windowWillClose` 里只在 `retained === self` 时才清引用，避免把新窗的引用清掉。改后 Debug build 通过。

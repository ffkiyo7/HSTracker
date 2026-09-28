# 上游合并手册

每次把 HearthSim/HSTracker 的新 tag 合进工作分支都按本文走。**合完必须更新本文**：§4 追加一节记录，
§1 / §2 有新的热点或新规则就补一行。本文与 `git log --merges dev0923` 一一对应。

- 上游：`upstream` = https://github.com/HearthSim/HSTracker.git，只合 **tag**（`3.6.13` 这种），不合 `upstream/master` 中间态
- 工作分支 `dev0923`，基座 **3.6.12**（`c723bfd4`，2026-09-23 REFORK 换轨，见 `docs/REFORK.md`）；`master` 只做上游纯镜像（只允许 `--ff-only`）
- 旧线 `dev`（基座 3.6.9）冻结作回滚点，不再合上游；它的三次合并记录（U / U2 / U3）留在 §4 末尾
- 3.6.13 的评估已做（`docs/REFORK.md`「上游 3.6.13 评估」），是新线第一次 merge

## 0. 固定流程

```bash
git fetch --all --tags --prune
git log --oneline $(git merge-base dev0923 <tag>)..<tag>                                   # 上游新 commit 一览
comm -12 <(git diff --name-only $(git merge-base dev0923 <tag>)..<tag> | sort) \
         <(git diff --name-only $(git merge-base dev0923 <tag>)..dev0923 | sort)           # 双方都改过的文件
git merge-tree --write-tree dev0923 <tag> | grep '^CONFLICT'                               # 干跑：列出会冲突的文件
```

1. 先把上游每个 commit 和 §1 的热点表对一遍：**上游修的 bug 我们是不是已经自己修过**（旧线 U2 的 CardHud、
   U3 的 Watchers / MonoHelper / ImageUtils 都是这种）。这一步决定冲突怎么解，不要等到冲突标记前再想。
2. `git merge <tag>`（直接合，不经 master；合完 `git checkout master && git merge --ff-only <tag>` 把镜像跟上）。
3. 冲突按 §2 解。自动合并成功但**双方都改过**的文件也要人工过一遍（U2 的 CardHud、WindowManager 就是自动合并出来的问题）。
4. `BobsBuddy-version.txt` 冲突 → §2.2 重新 vendor；`HearthMirror-version.txt` 变了 → 必须 `clean build`。
5. 校验：`python3 docs/tasks/tools/check_xcstrings.py --baseline dev0923`（只应报上游新增 key；我们有意覆盖过上游 zh 的 key 要带 `--allow-zh-edit`）；受限环境 Debug `clean build` → `BUILD SUCCEEDED`；`xcodebuild test` → 条数 ≥ 合并前（09-28：295 条，只挂签名 1 条；命令见 `AGENTS.md`「构建」）。
6. merge commit 标题 `merge: 合入 upstream <版本>`，正文逐个冲突文件写「保留了谁的什么、为什么」+ 手工复核的自动合并项 + 构建 / 测试结果（模板看 `git show 5835f8a4` / `9da27c8e`）。
7. 更新文档：`docs/PLAN.md` 头表（基座、测试基线）+ 阶段表加 Phase Ux 行；本文 §4 追加记录。
8. 合完 grep 一遍 `docs/PLAN.md`「与上游的默认值差异」表，一个单词的默认值最容易被静默还原。

## 1. 排查从哪开始看：热点文件

`git diff --stat 3.6.12 dev0923 -- HSTracker HSTrackerTests HSTracker.xcodeproj Translations` 就是全部分歧面
（2026-09-28：91 个文件；其中 fork 自有的整目录 `Fork/` 11 个、`RedDragon/` 6 个、`UIs/SessionRecap/` 3 个、`UIs/Trackers/SwiftUI/` 11 个、`Utility/LatencyProbe.swift`、
测试 5 个 + fixtures，上游不会碰）。下表只列**上游文件**，按「上游最可能碰到」排序，每行写清新线在这里干了什么、合并时要守住什么。

| 文件 | 新线改了什么（行数 = 相对 3.6.12） | 合并时盯什么 |
|---|---|---|
| `HSTracker.xcodeproj/project.pbxproj`（259）、`xcshareddata/xcschemes/HSTracker.xcscheme`（+5） | ① `MACOSX_DEPLOYMENT_TARGET = 14.0`（上游 6 处 10.15）② fork 新文件登记（`Fork/` 11、`RedDragon/` 6、`SessionRecap/` 3、`SwiftUI/` 11、`LatencyProbe`、测试 4 + fixtures）③ `Embed Mono` / `HearthDb` 版本强校验 + wget PATH + 条件代理 ④ scheme 加 `HSTRACKER_LATENCY_PROBE` 环境变量 | 上游每个新 swift / xib / 图集必须四处登记齐（PBXBuildFile、PBXFileReference、group、phase），`grep -c 文件名` 应为 3~4；`MARKETING_VERSION` 取上游；上游删 Swift 包（3.6.13 删了 `Preferences`）连 `Package.resolved` 一起收 |
| `HSTracker/BobsBuddy-version.txt`、`HearthDb-version.txt`（fork 新增）、`Vendor/Managed/*.zip` | 两份 zip 固定进仓库，版本文件是唯一真相，构建时强校验；DLL 装到 `Contents/Resources/Resources/Managed/`（`MonoHelper.load()` 真正读的位置） | 上游改版本号 = 必须重新 vendor，见 §2.2（3.6.13：1.76.3 → 1.78.2） |
| `HSTracker/Logging/Game.swift`（153） | S3 / S4：三处 `tracker.update(cards:…)` 旁多传分区 `groups:`，`updateTrackers` 单次取数（Perf P1）；S5：3 处 `LatencyProbe` 埋点、`OverlayRefreshScheduler` 16ms 合并；S6a：排队显示牌组 + 清残留、场景门（`Fork/Game+TrackerGate.swift` 的入口） | 上游在 `updatePlayerTracker` / `updateOpponentTracker` 开头加门（3.6.13 加了 `gameTime == nil`）要落在我们传分区之前；`reset()` 加参数（3.6.13 `reset(updateUI:)`）时确认分区闩随 `entities` 一起清；埋点留在 main block 之内 |
| `HSTracker/UIs/ImageUtils.swift`（130） | S5：LRU 256（`Fork/SynchronizedLRUCache.swift`）+ 404 负缓存 + 后台解码，回调回主线程 | 上游加「主线程 hop」「404 要回调」多半已有；上游新增图片类型要接进同一套 LRU / 队列 |
| `HSTracker/Core/SizeHelper.swift`（101） | S5：AX 读挪后台 + `UnfairLock`，窗口轮询 0.25s（上游约 2s） | 上游改窗口探测 / 全屏判断时看锁的范围 |
| `HSTracker/UIs/Trackers/WindowManager.swift`（47） | S5：`show` 同值不写（styleMask 写会同步 round trip）；`OverlayOrderFrontGate` | 上游在 `show` 里加 hop / 改 styleMask 逻辑时保住短路 |
| `HSTracker/UIs/Overlay/Trackers/TrackerPanelView.swift`（42）、`TrackerPanelViewModel.swift`（+3）、`TrackerCardHoverHandler.swift`（+4）、`CardTileView.swift`（15） | S4：分区列表接入点（`TrackerPanelLayout(zonePanelOf:)` 为 nil 时走上游布局）；解锁拖动手势改 `.rootOverlayCanvas` 坐标、染色框改描边；S6b：`tooltipDisplay` 备牌先返回 | 上游改面板布局 / 悬停链路时，看 `UIs/Trackers/SwiftUI/TrackerPanelZone.swift` 的接入点是否还对得上；上游若自己修了 `.local` 坐标 bug 取上游 |
| `HSTracker/UIs/Overlay/Root/RootOverlayWindow.swift`（+21）、`OverlayWidgetPlacement.swift`（41）、`SecretsPanelView.swift`（11）、`Battlegrounds/Session/BattlegroundsSessionOverlayView.swift`（14） | `alwaysLocked = true` + `updateFrames` 覆写（按光标点击穿透）；可移动框描边 `OverlayMovableOutline` / `OverlayResizeGrip` 四处共用 | 上游改解锁 / 点击穿透逻辑时优先看它有没有修同一个 bug |
| `HSTracker/Logging/Parsers/TagChangeActions.swift`（15）、`Entity.swift`（+6）、`Player.swift`（12） | S3：`case .zone` 后 `updateZoneLatches`、`creator` 后 `markShuffledIntoDeck`、`Entity` 两个闩 + `copy()` 拷贝；`predictFabled` 只写对手（Bug T3）；`Player.game` 放宽 | 上游在 `zoneChange` 同一处加东西（3.6.13 `updateBoardOrder`）顺序无关；`Entity.copy()` 上游加字段时我们的两个闩也要在 |
| `HSTracker/AppDelegate.swift`（34） | S6a：菜单按 tag 定位（`Fork/AppDelegate+MainMenu.swift`）、Dock 打勾 + Toast | 上游重写设置窗初始化（3.6.13）与我们不在同一段；上游 `item(withTitle:)` 新增处要改 tag |
| `HSTracker/Logging/CoreManager.swift`（22）、`Database/RealmHelper.swift`（20）、`UIs/StatsManager/Statistics.swift`（+1） | S6b：局末小结三处钩子（init / `appLaunched` / `appTerminated`）、`getStatistics(since:)` | 上游改 `appTerminated` 的退出时序时保住「小结窗开着不 terminate」 |
| `HSTracker/Logging/LogReaderManager.swift`（5） | S6a：`removeLogfile: !Settings.keepPowerLog`、`stop` 例外；S5：`LatencyProbe.logLineStarted` | 3.6.13 在同一处加 rewind 跳过 → 会冲突，两边都留，探针放在跳过之后 |
| `HSTracker/Logging/QueueEvents.swift`（+6）、`SceneHandler.swift`（5） | S6a：排队 / 场景门 | 读 `QueueEvents.isInQueue` 的代码不得在对局路径上（`AGENTS.md`） |
| `HSTracker/Core/Settings.swift`（3）、`HSReplay/HSReplayPreferences.swift`（2） | `show_mulligan_toast` 默认 `false`；HSReplay 标题本地化。fork 自己的键都在 `Fork/Settings+Fork.swift` / `Settings+Tracker.swift` | 默认值最容易被静默还原，合完 grep `docs/PLAN.md` 那张表 |
| `HSTracker/Database/Models/Card.swift`（+1） | `copy()` 补拷 `enText`（上游 3.6.13 仍漏） | 上游哪天补了就取上游 |
| 22 个 `*.xcstrings` | S2 注入 zh-Hans（1066 / 1078），195 条是有意覆盖上游 zh；S6b 统一「卡组」 | 逐块保留双方：我们插 zh-Hans，上游插别的语言；合完跑 `check_xcstrings.py --baseline dev0923 --allow-zh-edit`；上游 3.6.13 起自带 zh-Hans，看它有没有把我们的覆盖还原 |
| `HSTrackerTests/DatabaseTests.swift`（+36） | 断言英文用 `card.enText` | 红了先判断是回归还是上游改了行为，不改期望凑绿 |

## 2. 解冲突的固定规则

### 2.1 原则

- 我们这边是功能 + 探针，上游是 bug 修：**两边意图都保留**，不是二选一。
- 上游和我们独立修了同一个 bug → 取更完整的那版（U3 的 MonoHelper 取上游：它在异常分支 `return`，dev 版会继续对 faulted Task 调 `get_Result`），把另一边的注释 / 探针合过去。
- 上游加的 `DispatchQueue.main.async`：我们的回调已经在主线程或已 hop 的地方**不叠第二层**；上游加的 `assertMainThread()` 照收，它是探针不是 hop。
- fork 自有代码放 `Fork/`、`RedDragon/`、`UIs/Trackers/SwiftUI/`、`UIs/SessionRecap/`；改上游文件时能用 extension 落在 `Fork/` 就不改上游文件本体（`Settings+Fork` / `Game+TrackerGate` / `RealmHelper+CardCountFix` 是先例）。
- 不做冲突解决以外的重构、不顺手改风格、不删我们的注释和探针；行为改动（如日志级别）单独提。

### 2.2 BobsBuddy / HearthDb 重新 vendor

上游只钉版本号，我们固定 zip。脚本只能拉 latest，两个依赖必须一起换：

```bash
scripts/update-managed-deps.sh            # 打印 latest 实际版本
scripts/update-managed-deps.sh --apply <BobsBuddy版本> <HearthDb版本>
```

落盘版本可能高于上游钉的（U2：上游 1.70.0 → 落 1.70.2；U3：上游 1.70.7 → 落 1.71.1；S1：上游 1.76.3 → 落 1.76.10 / HearthDb 36.6.0）。
vendor **折进 merge commit**，拆开会留下一个 version.txt 与 zip 不一致、构建不过的中间提交。
latest 低于上游声明、下载失败、HearthDb 大版本跳变 → 停下来问。

### 2.3 pbxproj

`plutil -lint` 通过只说明语法对。还要 grep 上游每个新文件名出现次数（swift 4 次、Base + mul 的 xib 8 次），
以及每个 PBXBuildFile id 恰好 2 次（声明 + phase）、被丢弃的 id 0 次。

## 3. 上游主线程改动的判定表

上游 3.6.8 起在补 Sentry 上报的线程问题，这类改动会撞我们的探针层。判定顺序：

1. 上游改的代码路径我们还在用吗？（新线记牌器列表是我们的 SwiftUI 块，外壳、悬停、坟场详情是上游的）
2. 我们是否已有等价保护？（`completeOnMain`、已存在的 `main.async`、`MainThreadGuard`、`DelayedTooltip` 的主线程断言）
3. 合入后会不会双重 hop（时序变化）或断言互相打架？
4. 探针要留在 hop 之内，否则量的是排队而不是工作。

## 4. 历次记录

每节固定四项：上游更新一览 / 冲突与处理 / 白得与风险 / 待验。上游 commit 列表随时可重生成：
`git log --oneline <merge>^1..<merge>^2`。

### REFORK — 换轨到 3.6.12（2026-09-23 ～ 09-28，不是 merge）

上游 3.6.11 之后把 overlay 重写成单一 SwiftUI 画布并删了 `Tracker.swift` / `CardHud.swift`，旧线的记牌器窗口层改动整体作废。
不合并，从 `3.6.12`（`c723bfd4`）开 `dev0923`，按 `docs/REFORK.md` S0–S8 只搬值得留的东西；每步的取舍、勘误、上游 bug 都记在那里。
新线第一次 merge 将是 3.6.13（评估见 `docs/REFORK.md`「上游 3.6.13 评估」：干跑 3 处冲突 —— `project.pbxproj` / `BobsBuddy-version.txt` / `LogReaderManager.swift`）。

---

以下三节是旧线 `dev`（基座 3.6.9）的合并记录，留档；旧线已冻结。

### U3 — 3.6.9（2026-09-08，`9da27c8e`，上游 `ee2ad031..8ea0eaea`）

**上游更新（11 commits）**

| commit | 内容 | 对 dev |
|---|---|---|
| `20e1943c` | `Watchers.onDiscoverStateChange` 加 main hop；`AnimatedCardList.shouldHighlightCard` 补 `main.async` | Watchers dev 已修（冲突，取 dev + 上游注释）；AnimatedCardList 照收 |
| `530f8517` | `CardBar.fadeIn/fadeOut`、`AnimatedCardList.update/updateFrames` 加 `assertMainThread()` | 照收，Debug 实战验 |
| `4c1f2676` | Bob's Buddy 启动自检异常不再 crash | dev 也修过，冲突取上游 |
| `bdf9b9e4` | 自检只在 Debug 跑 | 照收 |
| `ff2d124e` | The OutFinder 设置面板（swift + xib + xcstrings + 图集，`Settings` 5 个 key） | 照收，pbxproj 登记齐 |
| `7381eb05` | 新卡 EmeraldPortal | 照收 |
| `cf1429ba` | Defensive Sacrifice 磁力随从 | 照收 |
| `d05f103c` / `7b7a93f0` | outfinder 池按 HDT 方式绘制、悬停预览 | 照收（`RelatedCardsBrowserTileList: AnimatedCardList`） |
| `ce9bfd9c` | Version 3.6.9，BobsBuddy 钉 1.70.7 | `MARKETING_VERSION` 取上游；vendor 见下 |
| `8ea0eaea` | Sentry 不再把后端 5xx 当 crash（`enableCaptureFailedRequests = false`） | 照收 |

**冲突 5 个**

- `Watchers.swift`：保留 dev 的 `main.async` + LatencyProbe 埋点，吸收上游注释，不叠 hop。
- `MonoHelper.swift`：整体取上游 `testSimulation`。
- `ImageUtils.swift`：dev 的 `decodedImage(data:)` guard 已覆盖上游「404 要回调」，只挪注释；日志级别保持 dev 的 `error`（上游用 `verbose`，认为 `/bgs` 变体 404 是常态 —— 噪音大再单独降级）。
- `BobsBuddy-version.txt`：上游 1.70.7 → vendor 到 **1.71.1**，HearthDb 36.4.2 不变。
- `project.pbxproj` 4 处：丢上游的 `B8FA0C0100000006`（Outfinder 进测试 target）；`MainThreadGuard` 重复条目去重；测试 target Sources 整块取 dev；`14.0` + `3.6.9`。

自动合并但双改的 5 个文件（AppDelegate / Settings / Game / Tracker / Localizable.xcstrings）人工扫过无问题；
`check_xcstrings.py --baseline dev` 只报上游新增 key `The OutFinder`。

**白得 / 风险**：Bob's Buddy 自检崩溃修复、5xx 误报修复、OutFinder 设置页。
风险：BobsBuddy 跳到 1.71.x（上游还在 1.70.x），构建 + 50 测试全绿但无实战覆盖。

**待验 🎮**：Debug 跑一局，`AnimatedCardList.update/updateFrames` 的 `assertMainThread()` 若 trap，
调用方在 `DeckLens.swift:84` / `DeckSideboards.swift:121`，那是上游探针抓到真 bug，不是合并回归。

### U2 — 3.6.8（2026-09-05，`5835f8a4`，31 commits）

**上游更新（要点）**：macOS 26 overlay 崩溃根因（`lockFocus` 破坏堆 → `NSImage(drawingHandler:)`）、
`MainThreadGuard.assertMainThread()`、watcher 双线程 start 崩溃、sideboard 闪现、`LogReaderManager` stop 流程重写、
`WindowManager.show` 主线程 hop 前移。

**冲突 2 个**：`project.pbxproj`（6 块：测试 target 不收 `B8A17C03`；MainThreadGuard 与 LatencyProbe 成对冲突两边都留；`14.0` + `3.6.8`）、
`BobsBuddy-version.txt`（上游 1.70.0 → vendor 到 1.70.2 / HearthDb 36.4.2）。

**自动合并里手工调整**：`WindowManager.show` idempotent 短路保留在上游 hop 之后；`LogReaderManager` 取上游重写、埋点未动；
`CardHud.updateSourceCard` **去掉上游新加的 `main.async`**（`completeOnMain` 已覆盖），保留 `[weak self]`。

**待验 🎮**：Debug 实战一局看有没有命中 `assertMainThread()`（与 U3 待验合并成一次）。

### U — 3.6.7（2026-08-30 前后，`eaa55850`，42 commits / 1036 文件）

**上游更新（要点）**：卡牌数据库管线 CardDefs.xml → CardDefs.bin，Mono 装配移出 `Contents/Resources/Resources/`；
`setRelatedCardsTooltip` 重写为 OutFinder 一部分；hero 图片路径；net7.0。

**冲突 4 个**：`project.pbxproj`（保 net8.0、`14.0`、SwiftUI 七个新文件；顺手补上游漏登记的 EternalKnightCounter / AncestralAutomatonCounter；加 `Embed Mono` 版本强校验，BobsBuddy 升 1.69.0）、
`Tracker.swift`（`setRelatedCardsTooltip` 取上游；T3 的 `showTooltipGridCards` 改用 `RelatedCardsTooltipPanel` 新 API 并清池统计）、
`ImageUtils.swift`（hero 接进 T7 的 LRU / 队列；改 ImageIO 强制解码；4 路 OperationQueue；修 nil 不回调）、
`MainMenu.xcstrings`（61 块逐块保留双方）。

**结果**：卡点 ① 已实战（2026-08-30），串卡修复确认，产出 5 条反馈（见 PLAN）。

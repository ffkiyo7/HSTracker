# 上游合并手册

每次把 HearthSim/HSTracker 的新版本合进 `dev` 都按本文走。**合完必须更新本文**：§4 追加一节记录，
§1 / §2 有新的热点或新规则就补一行。本文与 `git log --merges dev` 一一对应。

- 上游：`upstream` = https://github.com/HearthSim/HSTracker.git
- 本 fork 的工作分支 `dev`；`master` 只做上游纯镜像（只允许 `--ff-only`）
- 历次记录：Phase U（3.6.7，`eaa55850`）→ U2（3.6.8，`5835f8a4`）→ U3（3.6.9，`9da27c8e`）

## 0. 固定流程

```bash
git fetch --all --tags --prune
git log --oneline $(git merge-base dev upstream/master)..upstream/master        # 上游新 commit 一览
comm -12 <(git diff --name-only $(git merge-base dev upstream/master)..upstream/master | sort) \
         <(git diff --name-only $(git merge-base dev upstream/master)..dev | sort)   # 双方都改过的文件
git merge-tree --write-tree --name-only dev upstream/master                      # 干跑：列出会冲突的文件
```

1. 先把上游每个 commit 和 §1 的热点表对一遍：**上游修的 bug 我们是不是已经自己修过**（U2 的 CardHud、
   U3 的 Watchers / MonoHelper / ImageUtils 都是这种）。这一步决定冲突怎么解，不要等到冲突标记前再想。
2. `git merge upstream/master`（直接合，不经 master；合完 `git checkout master && git merge --ff-only upstream/master` 把镜像跟上）。
3. 冲突按 §2 解。自动合并成功但**双方都改过**的文件也要人工过一遍（U2 的 CardHud、WindowManager 就是自动合并出来的问题）。
4. `BobsBuddy-version.txt` 冲突 → §2.2 重新 vendor。
5. 校验：`python3 docs/tasks/tools/check_xcstrings.py --baseline dev`（只应报上游新增 key）；受限环境 Debug `clean build` → `BUILD SUCCEEDED`；`xcodebuild test` → 50 / 50（命令见 AGENTS.md「构建」）。
6. merge commit 标题 `merge: 合入 upstream <版本>`，正文逐个冲突文件写「保留了谁的什么、为什么」+ 手工复核的自动合并项 + 构建 / 测试结果（模板看 `git show 5835f8a4` / `9da27c8e`）。
7. 更新文档：`docs/PROGRESS.md` 头表（分支基线、构建、待实战）+「其余阶段」加 Phase Ux 行；`docs/PLAN.md` 阶段表加行；本文 §4 追加记录。

## 1. 排查从哪开始看：热点文件

`git diff --stat upstream/master dev -- . ':!docs'` 就是全部分歧面（2026-09-08：40 个代码文件 + 21 个 `.xcstrings`）。
下表按「上游最可能碰到」排序，每行写清 dev 在这里干了什么、合并时要守住什么。

| 文件 | dev 侧改了什么 | 合并时盯什么 | 历次冲突 |
|---|---|---|---|
| `HSTracker.xcodeproj/project.pbxproj` | ① `MACOSX_DEPLOYMENT_TARGET = 14.0`（上游 10.14 / 11.0）② 测试 target `439C7E58 Sources` 只留 9 个测试文件 ③ SwiftUI 记牌器 / `LatencyProbe` / `SynchronizedLRUCache` 等新文件四处登记 ④ `Embed Mono` 程序集版本强校验 | 上游每个新 swift / xib / 图集必须四处登记齐（PBXBuildFile、PBXFileReference、group、phase）；上游往测试 target 加的 `… in Sources` 一律不收，连带声明删掉不留孤儿；上游挪动 `MainThreadGuard` 会和 dev 撞成重复条目，去重各留一份；`MARKETING_VERSION` 取上游 | U / U2 / U3 每次都冲突 |
| `HSTracker/BobsBuddy-version.txt`、`HearthDb-version.txt`、`Vendor/Managed/*.zip` | 两份 zip 固定进仓库，版本文件是唯一真相，构建时强校验 | 上游改版本号 = 必须重新 vendor，见 §2.2 | U2 / U3 |
| `HSTracker/UIs/ImageUtils.swift` | T7：LRU（`SynchronizedLRUCache`）+ 4 路后台 ImageIO 解码 + **所有回调经 `completeOnMain` 回主线程**；nil / 解不出图也回调 | 上游在这里加的「主线程 hop」「404 要回调」多半 dev 已有；上游新增图片类型（hero、outfinder 池）要接进同一套 LRU / 队列 | U / U3 |
| `HSTracker/Hearthstone/Watchers.swift`、`Logging/Game.swift`、`Logging/LogReaderManager.swift`、`UIs/Trackers/WindowManager.swift`、`UIs/Trackers/CardHud.swift` | `LatencyProbe` 埋点（`mainQueueWorkStarted/Finished`）、若干 `main.async` hop、`WindowManager.show` 的 idempotent 短路 | 上游加 main hop 时先看 dev 是否已 hop（别叠两层）；埋点必须留在 hop 之内；上游重写整段流程时把埋点搬过去 | U2（WindowManager / LogReaderManager / CardHud 自动合并）、U3（Watchers 冲突） |
| `HSTracker/UIs/Trackers/Tracker.swift` | `swiftUICards` 分支（SwiftUI 记牌器）、T3 `showTooltipGridCards` 走 `RelatedCardsTooltipPanel` 新 API、`setRelatedCardsTooltip` 取上游 OutFinder 版 | 上游改 AppKit 卡列表 / hover 逻辑时，看是否也该镜像到 SwiftUI 分支；OutFinder 相关整体跟上游 | U |
| `HSTracker/UIs/Trackers/AnimatedCardList.swift`、`UIs/Cards/CardBar.swift` | dev 未改，但 `Settings.useSwiftUITracker` 默认 **false**，AppKit 卡列表仍是实跑路径；`DeckLens` / `DeckSideboards` / outfinder 池浏览器也用它 | 上游加的 `assertMainThread()`（Debug 会 trap）照收，实战一局验证 | U3（自动合并） |
| `HSTracker/Core/Settings.swift` | `useSwiftUITracker` 开关、`show_mulligan_toast` 默认改 `false`（完整默认值差异表见 PROGRESS「与上游的默认值差异」） | 一个单词的默认值最容易被静默还原，合完 grep 一遍那张表 | — |
| `HSTracker/UIs/Preferences/TrackersPreferences.{swift,xib}` | Phase 4 设置页重排（xib 删 469 行） | 上游新增设置控件要手工搬进新布局 | — |
| `HSTracker/Mono/MonoHelper.swift`、`AppDelegate.swift` | 启动自检 / 日志 / AppMover 改动 | 上游修同一处崩溃时优先取上游（更完整），确认 dev 意图被覆盖 | U3 |
| 21 个 `*.xcstrings` | Phase 3 补齐 zh-Hans（945 / 945） | 逐块保留双方：dev 插 zh-Hans，上游插别的语言；合完跑 `check_xcstrings.py --baseline dev` | U（MainMenu 61 块） |
| `HSTrackerTests/*` | 只编 9 个文件；`DatabaseTests` 用 `card.enText`；PowerParser / Secret / ReplayUpload 期望已按本 fork 调整 | 红了先判断是回归还是上游改了行为，不改期望凑绿 | — |
| `HSTracker/Core/SizeHelper.swift`、`Core/Extensions/String.swift`、`UIs/Trackers/SwiftUI/*`、`Utility/LatencyProbe.swift` | dev 独有 | 上游不会碰；只需确认上游改的 AppKit 行为要不要镜像到 SwiftUI | — |

## 2. 解冲突的固定规则

### 2.1 原则

- dev 侧是功能 + 探针，上游侧是 bug 修：**两边意图都保留**，不是二选一。
- 上游和 dev 独立修了同一个 bug → 取更完整的那版（U3 的 MonoHelper 取上游：它在异常分支 `return`，dev 版会继续对 faulted Task 调 `get_Result`），把另一边的注释 / 探针合过去。
- 上游加的 `DispatchQueue.main.async`：dev 回调已经在主线程（`completeOnMain`）或已 hop 的地方**不叠第二层**；上游加的 `assertMainThread()` 照收，它是探针不是 hop。
- 不做冲突解决以外的重构、不顺手改风格、不删 dev 的注释和探针；行为改动（如日志级别）单独提。

### 2.2 BobsBuddy / HearthDb 重新 vendor

上游只钉版本号，我们固定 zip。脚本只能拉 latest，两个依赖必须一起换：

```bash
scripts/update-managed-deps.sh            # 打印 latest 实际版本
scripts/update-managed-deps.sh --apply <BobsBuddy版本> <HearthDb版本>
```

落盘版本可能高于上游钉的（U2：上游 1.70.0 → 落 1.70.2；U3：上游 1.70.7 → 落 1.71.1）。
vendor **折进 merge commit**，拆开会留下一个 version.txt 与 zip 不一致、构建不过的中间提交。
latest 低于上游声明、下载失败、HearthDb 大版本跳变 → 停下来问。

### 2.3 pbxproj

`plutil -lint` 通过只说明语法对。还要 grep 上游每个新文件名出现次数（swift 4 次、Base + mul 的 xib 8 次），
以及每个 PBXBuildFile id 恰好 2 次（声明 + phase）、被丢弃的 id 0 次。

## 3. 上游主线程改动的判定表

上游 3.6.8 起在补 Sentry 上报的线程问题，这类改动每次都会撞 dev 的探针层。判定顺序：

1. 上游改的代码路径 dev 还在用吗？（SwiftUI 记牌器默认关，AppKit 路径**都还在用**）
2. dev 是否已有等价保护？（`completeOnMain`、已存在的 `main.async`、`MainThreadGuard`）
3. 合入后会不会双重 hop（时序变化）或断言互相打架？
4. 探针要留在 hop 之内，否则量的是排队而不是工作。

## 4. 历次记录

每节固定四项：上游更新一览 / 冲突与处理 / 白得与风险 / 待验。上游 commit 列表随时可重生成：
`git log --oneline <merge>^1..<merge>^2`。

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

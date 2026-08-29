# 进度

| | |
|---|---|
| 最后更新 | 2026-08-30 |
| 分支 | `phase0+3`（已合入 upstream `534ee2d8` / **3.6.7**，review 通过并提交；`master` 同步快进到 3.6.7） |
| 构建 | 本轮串卡、排队残留与延迟口径修复后 Debug 增量 `BUILD SUCCEEDED`；现有 warning 来自上游旧 API / 资源名 / `-ld_classic` / always-run phase 与未安装 SwiftLint |
| 阻塞 | Phase 0 / T6 第 2 步等待一局 Release 探针数据；拿到前不做优化 |
| **下一步** | 人工验串卡与排队行为，并跑一局 Release 探针；拿到数据后再继续 Phase 0 / T6 第 2 步 |
| **下一次要你亲自看** | ① 🎮 **串卡修完**：连着悬停两张相关牌数量相同的卡，不能带出上一张的图。② 🎮 **排队残留修完**：进队列 30 张全在、`30 / 0`、匹配后不闪。③ 📊 **延迟口径修完**：跑一局 **Release** 探针重取基线（上一局是 Debug 包，那组数不能用） |
| **不作为验收手段** | **战棋** —— 用户不玩（2026-08-30 确认）。战棋代码该对还是要对，但验证只能静态做，不排"打一局战棋"这种项 |

> 本文件只回答三件事：**做到哪了 / 下一步是什么 / 哪些结论还作数**。
>
> 过程记录（每个任务怎么做的、review 改了什么、模型 A/B 怎么比的、录屏怎么分析的）
> 已整体归档到 **`docs/archive/progress-detail-2026-08-22.md`**，本文件不再复述。
> 计划全文见 `docs/PLAN.md`。

---

## 状态总览

### Phase 0 — 地基（🟡 T0–T5 完成，T6 本轮新增）

| | 内容 | 状态 |
|---|---|---|
| T0 | 前置环境（`wget`、本地签名、`net8.0` 修复） | ✅ |
| T1 | `WindowManager.show()` 去抖 | ✅ |
| T2 | AX 调用移出主线程 | ✅ |
| T3 | 提高 tick 频率 + 跟窗 | ✅ review 时改了设计，见 PLAN |
| T4 | 部署目标 → macOS 14.0 | ✅ |
| T5 | GUI 刷新改防抖 | ✅ 代码已合，但**实测收益未兑现**，见下节 |
| **T6** | **修埋点量程（D 段 + B 段 + E2E 归因）→ 取 Release 基线 → 打 p50** | 🟡 第 1 步代码完成并通过 Debug 构建；等待 Release 基线，未做优化 |

### Phase 1 — SwiftUI 记牌器渲染（🟡 5 / 8）

| 片 | 内容 | 状态 |
|---|---|---|
| T1 | `CardRowView` + `ThemeImageCache` + 并排比对窗 | ✅ 合入 grok 版（模型 A/B 的产物，codex 版留在 `ab/t1-codex`） |
| T2 | 主牌表接进 `Tracker` + `Settings.useSwiftUITracker` 开关 | ✅ 实战验过一局，**开关默认关**（本机 defaults 已置 1） |
| T3 | ETC / 下水道之王 改悬停浮出 | ✅ **卡点 ① 实战通过** —— ETC 标题正确 |
| T4 | 其余三段卡表 → `TrackerSectionView` | ✅ **卡点 ① 实战通过** —— 协同高亮描边视觉 OK |
| T5 | 顶部信息区重做（Firestone 三行头） | ⬜ |
| T6 | 根视图 + 布局收口 | ⬜ |
| T7 | 卡图异步加载 + LRU | ✅ **卡点 ① 实战通过** —— 卡图基本没有顿挫感 |
| T8 | 动效 | ⬜ |

**实测卡点**：~~① T3+T4+T7 + Phase U~~ ✅ → ② T5 → ③ T6 → ④ T8。
分批理由见 PLAN 的「执行卡点」一节。原来的 T9（删开关、删旧路径）**已挪到 Phase 2 之后**。

**卡点 ① 已于 2026-08-30 实战通过**（标准模式一局）。三片本身都过了；同一局产出 5 条反馈，
其中两条是真 bug（一条上游、一条时机），已开任务书，见下面「本轮任务」。

> ⚠️ **那一局的延迟基线作废** —— 起的是 `Build/Products/Debug` 的包，
> 而 D 段量程也还没修。**Phase 0 / T6 修完口径后要重跑一局 Release。**

### 其余阶段

| | 内容 | 状态 |
|---|---|---|
| **Phase U** | **合并上游 3.6.7** | ✅ 42 commits / 4 个冲突文件 · **卡点 ① 已实战**；串卡修复代码完成，待人工验 |
| Phase 2 | 记牌器分区（牌库 / 手牌 / 已打出） | ⬜ 依赖 Phase 1 的 T4 / T6 · 🎮 ×4 |
| 收尾 | 删 A/B 开关、删旧路径 | ⬜ 排在 Phase 2 之后 · 🎮 |
| Phase 3 | 补全简体中文 | ✅ Phase U 补课后 **945 / 945（100%）** |
| Phase 4 | 设置 UI + Dock 菜单 | ⬜ 三项都不依赖任何东西，随时可开始 · 🎮 + 🖥️ |
| Phase 5 | 计数器 overlay 可拖动 | ⬜ 🎮 · 3.6.7 落点已重查，根因仍在窗口层 |
| Phase 6 | 排队时就显示牌组 | 🟡 T1 代码完成并通过 Debug 构建，待标准/战棋队列人工验 · 🎮 |

> 🎮 = 这一阶段有需要**你亲自开炉石看**的卡点，🖥️ = 只需静态看（比对窗 / 设置窗口）。
> 每个卡点具体验什么、要备什么料，见 `docs/PLAN.md` 的「🎮 需要人亲自看的卡点」。

### 本轮任务（2026-08-30，卡点 ① 实战产出）

用户打完一局提了 5 条，逐条核对后的落点：

| # | 反馈 | 核对结论 | 落点 |
|---|---|---|---|
| ① | 抽到手上的牌还留在牌库段，延迟一两回合甚至一直不消 | **不是延迟。** 探针 E2E p50 171ms / p95 450ms，没有那个量级的样本。真因是 `Settings.highlightCardsInHand`（本机开着）—— `getHighlightedCardsInHand()`（`Player.swift:381`）**故意**把手牌里的卡塞回列表，`count = 0` + 亮绿名 | Phase 2 / 2.1 分区时消化（PLAN 已记）。用户已认可 |
| ② | 卡池浮窗串卡（「误炸」`WW_348` 窜进好几张卡的相关牌） | **上游 3.6.7 的回归。** `RelatedCardImageView` 的 `@State image` + `ForEach(0..<rows/cols, id:\.self)`，格子身份是行列下标不是卡；`hide()` 只 `orderOut`，视图树不销毁 → 复用时留着上一张的图。`git diff 534ee2d8` 对该文件为空；3.6.5 用的是 AppKit `GridCardImages`，所以是换 SwiftUI 时引入的 | ✅ 格子身份改为位置 + card id，待人工验 |
| ③ | 排队时显示的是上一局残局 | `game.reset()` 只在 `Gameplay.Start` / `CREATE_GAME` 跑，排队时 `revealedEntities` 还是满的。**且这同时解释了"排队时记牌器为什么会显示"** —— `_currentGameType` 也没被清，绕过了 `Game.swift:376` 的条件。**清残留会让记牌器消失**，必须和放宽条件一起做 | ✅ 进队列完整 reset + 构筑模式白名单显示，待人工验 |
| ④ | 卡条尺寸一局之内会变大 | **上游一直如此**：`Tracker.swift:459` 的 `cardHeight = min(cardHeight, (windowHeight - offsetFrames) / totalCards)`，行高按当前行数压缩。3.6.7 的 `:298-299` 一字不差 | 记在 PLAN 2.8，**等用户决定**（(a) 固定行高 / (b) 宽度跟着缩，二选一） |
| ⑤ | 留牌时右下角的 HSReplay 引流浮窗（`MulliganToastView`，「What should I keep?」，`SizeHelper.swift:474` 定位在右下） | 有现成开关 `Settings.showMulliganToast` | ✅ **已改为本 fork 默认关闭**，见「与上游的默认值差异」 |

顺带确认：**E2E p99 5.0s / max 9.3s 的长尾是真的**，且 >10s 的样本被 `outlierCutoff` 直接丢进
`dropped` 计数、不进百分位。连同两个旧的 🔴（D 段量程、B 段没埋点）一起进 Phase 0 / T6。

三本任务书的代码均已完成并通过 review；Phase 0 / T6 按任务书停在第 1 步，等待 Release 取数。

**review 挡下的一条**（记着，因为它是竞态、上线后极难查）：排队那本原本给
`updateOpponentTracker` 也加了 `!queueEvents.isInQueue`。它**多余** —— 进队列的 `reset()`
已把 `_currentGameType` 打回 `.gt_unknown`（`:1702`），而 `cacheGameType()` 只在 `gameStart()`
里调（`:1990`），排队期间没人重新填它，原有条件已经挡住了对手记牌器。它还**有害**：
`QueueWatcher.stop()`（`:49`）只 `store(_watch,false)`、**从不发 `inQueueChanged`**，而
`LoadingScreenHandler:126` 一进 `.gameplay` 就 `stop()`（`Mode.gameplay ∈ ignoredModes`）。
watcher 200ms 才轮询一次，只要模式那行日志抢在轮询前面，
`QueueEvents.isInQueue`（全仓库唯一写入点 `QueueEvents.swift:24`）就永远停在 `true`
—— **那一整局对手记牌器都不出现**。

> **为什么这个陈旧状态一直没咬到人**：`isInQueue` 原有的读者只有 `Game.swift:1046` / `:1068`，
> 都是已被 `isInMenu` 挡住的 pre-lobby 覆盖层。那一行是**第一个把它接到对局路径上的地方**。
> 以后谁再想读 `isInQueue`，先确认自己不在对局路径上。

**自动化测试边界**：尝试只跑现有 `DatabaseTests`，但测试 target 在编译测试模块前就失败：
`ReplayUploadTests.swift` 仍 import 已不在依赖图里的 `Wrap`，测试 target 的 Header Search Paths
仍指向旧 Mono include 路径。两项在 3.6.5 基线和 3.6.7 上游都存在；修复前者涉及恢复或替换依赖，
按范围规则本轮不动。主 app 的 clean / 增量构建与实际 CardDefs.bin 产物检查均已通过。

---

## 延迟实测

三轮探针数据（`HSTRACKER_LATENCY_PROBE=1`，各一整局标准模式，OBS 同规格录屏保持负载恒定）。
单位毫秒，格式 **p50 / p95**。分段口径见本文件末尾。

| 段 | 8-20 Debug | 8-21 Release | 8-22 Release（T5 后） | **8-30 Debug（3.6.7 后）** |
|---|---|---|---|---|
| A 日志行 → 解析 | 197.5 / 993.3 | 150.3 / 227.9 | 162.5 / 285.6 | 85 / 200 |
| C 置位 → tick | 106.4 / 199.5 | 106.9 / 195.3 | 114.3 / 398.0 | 17 / 116 |
| D tick → UI 提交 | 179.6 / 819.1 | 20.1 / 273.5 | 14.8 / 384.3 | 57 / 224 |
| E2E 日志行 → UI | 479.8 / 1872.7 | 309.8 / 787.4 | 283.3 / 1570.7 | 171 / 450 |

> 🔴 **8-30 那一列只能当"没有数量级问题"的证据，不能横向比。** 两个理由：
> **(a) 是 Debug 包**（从 `Build/Products/Debug` 起的），D 段含 `-Onone`；
> **(b) D 段量程仍未修**，只覆盖 `updateAllTrackers()` 派出的 ~20 个 block 里的第一个。
> 该列的长尾：E2E **p99 = 5044 / max = 9293**，D **max = 10946**，且 >10s 的样本被丢弃。

### 仍然作数的结论

- 🔴 **这三轮数据在 Phase U 之后都只能当参考。** 上游 3.6.7 往同一个主线程 tick 里加了不少
  东西（counters 改 SwiftUI、战棋指南、OutFinder 的卡池计算），基座变了。
  **卡点 ① 那一局要在合完上游之后重取 before 基线** —— 那也是最后一次机会，T6 一动
  「旧布局 + Phase 0 全部优化」就拿不回来了。
- **Debug 数据不算数。** D 段那 180ms 里约 160ms 是 `-Onone` 的锅。
  任何性能结论在 Release 对照做完之前都不成立 —— 这条踩过两次。
- **T5 预期的 ~100ms 没有兑现**，C 段只从 107 动到 114。
  瓶颈从「100ms 轮询定时器」换成了「一次完整刷新占住主队列多久」，两者数量级碰巧相同。
- ✅ **D 段量程已修正**：终点移到 `runGuiUpdate` 尾部的二次主队列 marker；它排在第一层刷新
  block 及其追加的第二层 block 后面，D 和 E2E 现在都覆盖整轮 UI 提交。旧数据不可按新口径解释。
  > **两级 marker 是按当前调用图算出来的，不是通用保险。** review 时扫过
  > `Game.swift` 里所有缩进 >12 的 `DispatchQueue.main.async`：`updateAllTrackers()` 那批
  > 嵌套**最深只有一层**（`updateCounters` `:596`/`:609`、`updateConstructedMulliganOverlays`
  > `:628`/`:639`、`updateRootOverlay` `:756`/`:767`/`:778`）。**谁以后往刷新路径里加了
  > 两层嵌套的 async，D 就会重新低估，而且不报错。**
  > ⚠️ **这不只是埋点改动。** `guiUpdateInFlight = false` 跟着挪进了第二层 async，
  > 所以**不开探针时刷新节奏也变了** —— 下一轮刷新要多等一个主队列 turn。
  > 判断是**可接受且更正确**：按 T5 自己的理由（「上一轮还堵在主线程时下一轮就排进去了，
  > 必然堆积」），嵌套 block 没跑完这一轮本来就不算完。但 Release 那一局如果 C 或 E2E
  > 的 p50 变差，**第一个怀疑对象就是它**。
- ✅ **E2E 已排除非日志触发刷新**，并把待刷新与在途刷新的日志时钟分开；窗口位置、设置变更、
  延迟重试仍计 C / D，但不再冒充某一行日志的 E2E。
- ✅ **B 段已埋点**：`processLine` 入口 → `updateTrackers()` 在 GUI 串行队列里置位。
  新探针已实际启动并打印 A / B / C / D / E2E 五行。
- **掉帧不是 HSTracker 造成的**（在这套录屏方法的精度内）：对照组
  （HSTracker 完全没启动、只有静态主菜单）横跨了同样的范围。头号嫌疑是采集管线
  （4K 165Hz 面板压成 1080p120）。要排除它得换一个不经过 OBS 的测量手段，再录一段没用。

### Phase 0 剩下的优化候选（**先修 D 段量程再动手**）

| 候选 | 预计收益 |
|---|---|
| 两个日志轮询用信号量串起来 | ~50ms（A 段里属于我们的那部分） |
| 文件轮询换 `DispatchSource` | ~25ms，完全取决于炉石的 flush 行为 |
| ~~优化 `updateFrames()`~~ | ~~作废~~ —— Phase 1 的理由只剩动效和分区，不再是延迟 |

---

## 已知问题（都已定位，等对应阶段处理）

| 问题 | 根因 | 归属 |
|---|---|---|
| 卡牌从右侧消失时"卡顿" | `CardBar.fadeOut(highlight:)`（`:285`）函数体只有 `if highlight`，count==0 的卡淡出根本不播，但 `asyncAfter` 仍死等满 **600ms** 才删行 | Phase 1 / T8 |
| 数量变化（4→3）一帧跳变 | 插新 bar + 立即删旧 bar，`fadeOut: false`；全局没有任何布局动画 | Phase 1 / T8 |
| Discover 开着时悬停记牌器，OutFinder 的池会消失 | 备牌浮窗和 OutFinder 共用 `RelatedCardsTooltipPanel.shared`；鼠标移开触发 `hide()`，而 `DiscoverStateWatcher` 只在状态**变化**时回调（`:63` `if curr == _prev { continue }`），要等玩家真的选牌才回来 | 合并上游相关牌框架时一并解决（PLAN 的 Phase U 后续任务） |
| 卡条尺寸一局之内会变大 | `Tracker.swift:459` 行高按当前行数压缩，牌打光了弹回 `card_size` 上限。**上游一直如此**，非回归 | 等用户决定，选项记在 PLAN 2.8 |
| 抽到手上的牌仍留在牌库段（看起来像"延迟一两回合"） | `Settings.highlightCardsInHand` 的既定行为：`getHighlightedCardsInHand()`（`Player.swift:381`）把手牌里的卡以 `count = 0` 塞回列表。**不是延迟**，探针 E2E p50 171ms | Phase 2 / 2.1 分区时消化（用户已认可） |

> 合并前评估说过「不存在两个 tooltip 抢同一扇窗」—— 那个结论只覆盖了**注册表**层面
> （`RelatedCardsSystem/` 里没有 ETC / 下水道之王），**窗口层是共用的**，review 时才补上。
> 不崩、能自愈、触发条件窄，卡点 ① 顺手试一次即可。

本轮已关闭的四项不再留在“已知问题”里：两个战棋计数器已各完成 pbxproj 四处登记并在二进制中检出
（**到此为止，实机验证已取消 —— 用户不玩战棋**）；
`BobsBuddy-version.txt` 已更新到 1.69.1（Phase U 时是 1.69.0，08-30 服务器发新版后跟进）
且构建会核对程序集版本；T7 的磁盘/网络图片都通过
ImageIO 在后台强制解码，后台工作由最多 4 路的专用队列承载。

### 与上游的默认值差异（本 fork 故意改的）

**每加一条都要记在这里** —— 这类改动在 `git diff` 里只是一个单词，合并上游时最容易被静默还原。

| 设置 | 上游 | 本 fork | 理由 |
|---|---|---|---|
| `show_mulligan_toast` | `true` | **`false`**（`Settings.swift:235`） | 留牌阶段右下角那个 HSReplay 引流浮窗（`MulliganToastView`，「What should I keep?」）。**留牌指南本身不受影响** —— `enable_mulligan_guide` / `enable_mulligan_gv2` 都还是默认开 |

> 设置界面里那个 checkbox 仍然在（`TrackersPreferences.swift:149`），想要的人自己勾回来。
> 已经手动设过这个 key 的机器不受默认值影响 —— `@UserDefault` 只在 key 缺失时用默认值。

### macOS 14 部署目标带来的两处 deprecated（都没修）

| API | 位置 | 说明 |
|---|---|---|
| `.activateIgnoringOtherApps` | `AppDelegate.swift:257`、`NSAlert.swift:28`、`CoreManager.swift:446` | macOS 14 起被系统忽略，改成协作式激活。**下次开游戏留意 alert 会不会被压在炉石后面** |
| `CGWindowListCreateImage` | `SizeHelper.swift:236`（3 个调用点在 `ImageUtilities.swift`） | 官方推荐 ScreenCaptureKit；部署目标 ≥14 后迁移不再有版本包袱 |

### 两处过期描述（按"只改任务书指定文件"的规矩没动）

1. `PreferencePaneController.swift:21` 的注释说 tab icon 必须用 PDF，理由是「10.14 部署目标」——
   **理由已不成立**。它是上游 `bdb0ec12` 写的，改了会和上游冲突。
2. `README.md:9` 写「macOS 10.10 or higher」，上游升到 10.14 时就没跟。

### Phase 3 遗留（都不阻塞任何事）

1. `LadderTab` / `StatsTab` 有 16 条 zh-Hans 是 `Text Cell` 这类 XIB 占位（英文原样填的），
   用户看不见，但让覆盖率数字虚高。撤掉会让这两个文件永远显示"未翻译"，所以留着。
2. `Base.lproj/` 里还有 6 个没被 pbxproj 引用的 `Localizable.strings`，意味着
   `String.localizedString` 的 "Base.lproj 回退" 分支永远取不到东西。没删是因为
   `Base.lproj` 是活目录（有在用的 `.xib`），混着删风险大。
3. `HSReplayPreferences` 有几条旧译和英文对不上（`My Account` → 「上传收藏」），
   两边 catalog 都没有更好的版本，需要人肉重译。

---

## Phase 1 / T2 的当前状态

主牌表（`Tracker.swift` 的 `cardsView`）已可切到 SwiftUI 渲染，玩家和对手记牌器共用 `Tracker`、一起生效。

```
defaults write net.hearthsim.hstracker use_swiftui_tracker -bool true
```

**默认值是 `false`**，和 PLAN 第 3 节写的终态不一样：按切片推进，每一片都要在真实对局里看过才算数，
而这台机器每天在打游戏 —— 默认值不能是没验收过的那条路径。**开关在 Phase 2 之后才删**
（Phase 2 的分区还要靠它做对照）。

**故意没做的**：动效全部没做；`DeckLens` / 战棋两处仍是 `AnimatedCardList`（600ms 空等还在）；
协同高亮只画边框没有闪光；`Game.swift` 的 `playerTrackerUpdateEvents` 没加这个 key，
所以 `defaults write` 要等下一拍 tracker 刷新才生效。

## T3 的当前状态（2026-08-22 完成，2026-08-30 实战通过）

备牌段已从记牌器里拿掉，改成悬停牌表里的 ETC / 下水道之王**本体那一行**时浮出携带的卡，
载体是现成的 `windowManager.tooltipGridCards`。`Settings.hidePlayerSideboards` 为 true 时整条路径短路。

- 匹配按 `Sideboard.ownerCardId` 通用进行，不硬编码卡 ID
- 一张卡同时有备牌和相关牌时**备牌优先**（两者共用同一扇浮窗，不能同时亮）
- 浮窗标题用 `card.name`，不是旧段头那个 `DeckSideboard_Label_ETCBand`
- **`DeckSideboards.swift` 从此喂不到数据**，是死代码，留到收尾阶段统一删

> **2026-08-30 实战结论：标题正确**（浮窗顶上是那张卡的名字，不是「相关牌」）。

**没条件验证、不是没通过的两项**（不值得再打一局，改设置或用比对窗静态看即可）：
行高压缩、frost / minimal 的传说卡位移。协同高亮边框已在实战中确认视觉 OK。

Phase U 已把这一片接到 `RelatedCardsTooltipPanel`：标题改走 `setTitle()`，显示/隐藏改走
panel 自身 API；备牌 tooltip 会显式清空 OutFinder 的池统计与右键大池状态，避免复用窗口时残留
上一张相关牌的数据。

> 串卡修复已给每格加入“位置 + card id”的身份；相同卡可重复，换卡时图片视图会重建。
> 代码已通过 Debug 构建，仍需实战连续悬停验收。

## T4 的当前状态（2026-08-28 完成，2026-08-30 实战通过 —— 卡条相关牌的描边高光视觉 OK）

置顶 / 置底 / 相关牌三段在开关打开时改由 `TrackerSectionView` 渲染，卡条复用 T1 的
`CardRowView`、列表复用 T2 的 `TrackerCardListViewModel`。三个 `TrackerSectionHost` 是
`contentView` 的兄弟视图，与 `DeckLens` 按开关互相让位（`.xib` 里 outlet 类型写死，不许改）。

- `updateFrames()` 的行数账走 `playerTopCount` / `playerBottomCount` / `opponentRelatedCardsCount`
- 悬停的分段身份构造时传参，不走 `getHoverComponent()` 的 superview 遍历（该函数保留，旧路径还在用）
- 三段都不接 `setHighlight`，与 `DeckLens` 没有协同高亮一致

**review 改了两处视觉**，都是「按任务书字面实现反而与现状不符」：段头原本多画了一圈
1px `#141617` 边框（`DeckLens` 的 `NSBox` 是 `.noBorder` + `borderWidth = 0`，那行
`borderColor` 永远不生效）；`#23272A` 原本只涂段头，而 `DeckLens` 的 `box.frame` 是
`(0,0,w,h)`、铺满整个段（段头 + 卡条区 + 底部 5pt），已改为涂在整个 `VStack` 上。

**没移植的一处行为**：`DeckLens.update()` 在有卡被移除时会回调
`updatePlayerTracker(reset: false)`。那是给 `AnimatedCardList` 600ms 延迟删除兜底的，
SwiftUI 路径 `rows` 同步更新、`updateFrames()` 本就由 `WindowManager.swift:448` 按 tick 驱动，
不依赖它。

## T7 的当前状态（2026-08-29 完成，2026-08-30 实战通过 —— 卡图基本没有顿挫感）

`ImageUtils` 五个缓存（含 3.6.7 新增的 hero 图）统一用 `SynchronizedLRUCache`（各 256 项）。
缓存未命中交给最多 4 路的专用 `OperationQueue`；磁盘文件和下载数据都经 ImageIO 的
`kCGImageSourceShouldCacheImmediately` 在后台强制解码，首次绘制不再承担 JPEG / PNG 解码。
completion 继续统一回主队列，当前 28 个调用点均符合该契约。

> **2026-08-30 实战**：用户「卡图基本没发现顿挫感」。日志里仍有少量
> `ImageUtils.loadImage - download returned an invalid image`（几张 token 卡的 tile 在
> hearthstonejson 上就是坏的，如 `ETC_206e` / `EDR_979e2`），会反复重试下载 ——
> **不影响顿挫，但是没有负缓存**。不值得单开任务，记在这里，谁下次动 `ImageUtils` 顺手加。

---

## 操作备忘

### 并排比对窗

```
env HSTRACKER_CARD_ROW_COMPARE=1 \
  ~/Library/Developer/Xcode/DerivedData/HSTracker-cgfkydaatbcvlygsoujdqwiezsjx/Build/Products/Debug/HSTracker.app/Contents/MacOS/HSTracker
```

（这是合入的 grok 版。codex 版在另一个 DerivedData 下、环境变量叫 `HSTRACKER_CARD_ROW_COMPARISON`，
见归档文件。一次只开一个，两份产物共用同一份用户设置。）

### 素材留档

| 用途 | 路径 |
|---|---|
| 改动前基线（Debug，T5 前） | `~/Movies/2026-08-20 22-21-48.mp4`、`~/Desktop/Snipaste_2026-08-20_22-25-23.png` |
| Release 对照 | `~/Movies/2026-08-21 00-07-23.mp4` |
| 掉帧对照组（HSTracker 未启动） | `~/Movies/2026-08-21 00-04-08.mp4` |
| T5 之后 | `~/Movies/2026-08-22 00-31-43.mp4`、`~/Desktop/dev/HSTracker-ab/logs/probe-2026-08-22-release-t5.txt` |

掉帧分析工具 `docs/tasks/tools/frame_gaps.py`，**跨录像对比必须加 `--busy`**
（按"动画确实在进行的时段"归一化；不加的话内容差异会造出假结论）。

### 埋点分段口径

| 段 | 起点 | 终点 |
|---|---|---|
| A | 日志行自带的时间戳（`LogDate`） | `LogReaderManager.processLine` 拿到它 |
| B | `processLine` 开始 | `updateTrackers()` 置 `guiNeedsUpdate` |
| C | `guiNeedsUpdate` 置位 | tick 消费它 |
| D | `updateAllTrackers()` 开始 | 主线程 UI 提交完成 |

A 段包含炉石自己的 flush 延迟，是不可优化的地板。`LatencyProbe` 每 30s dump 一次、累计不清零。

---

## 环境备注（换机器或重开时需要）

1. `brew install wget` —— 两个 build phase 依赖它（下载 HearthMirror 和 Mono）。**不装必然构建失败。**
2. `Config.xcconfig` 已改为本地签名（`CODE_SIGN_IDENTITY = -`）并 `git update-index --skip-worktree`，
   `git status` 里看不到它。换机器要重做这一步。
3. `project.pbxproj` 的 `NET_VERSION` 必须保持 `net8.0`；3.6.7 上游仍是错误的 `net7.0`。
4. SwiftLint **故意没装**：build phase 里未安装只告警不阻塞，装了反而会给执行模型的验收构建引入无关失败。
5. git 身份是 repo-local 配置的（`ffkiyo7 / ffkiyo7@gmail.com`），没有写进 global。
6. **增量包可以直接交测。** 3.6.7 的卡库是 `Contents/Resources/CardDefs.bin`，Mono / BobsBuddy
   在 `Contents/Resources/Managed`，都不再位于 folder reference 会覆盖的 `Resources/Resources`。
   实测强制重跑 Resources 阶段后产物仍完整。只有 `HearthMirror-version.txt` 刚变化、旧 PCH 报
   framework header 被修改时，需要执行一次 `clean build`。
7. `BobsBuddy-version.txt` 当前是 `1.69.1`。官方地址只提供 latest，因此脚本会在解压临时目录后
   读取程序集信息版本；不匹配就失败且不会覆盖已缓存 DLL。更新该文件前先核对服务器实际版本。
   **这个 pin 会自己过期**：2026-08-30 当天早些时候还构建成功，几小时后服务器发了 1.69.1 就红了
   （`expects 1.69.0, but the server published 1.69.1`）。失败在下载阶段、一行 Swift 都没编译，
   **看到这条报错先别怀疑代码**；照服务器的数改版本文件即可，不要放宽校验。

---

## 详细记录去哪了

| 想找 | 去看 |
|---|---|
| 每个任务的执行细节、review 改了什么、踩过的坑 | `docs/archive/progress-detail-2026-08-22.md` |
| T1 切片的模型 A/B 完整比对（grok vs codex，逐元素） | 同上，「Phase 1 / T1 的模型 A/B」一节 |
| Phase 3 的六步任务、译文来源、72 处 review 改动 | 同上，「Phase 3」一节 |
| 录屏差分的方法学备忘 | 同上，「同一局的录屏分析」一节 |
| 任务书（**在做 / 待验**） | `docs/tasks/` —— 当前只有 `phase0-t6` / `phase6-t1` / `phaseU-t1` 三本 |
| 任务书（**已完成**） | `docs/archive/tasks/`，索引见该目录的 `README.md` |
| Firestone / HDT 的调研 | `docs/research/` |

> **`docs/tasks/` 是工作区，不是档案馆。** 一本书验收通过就挪进 `docs/archive/tasks/`，
> 剩下的永远是「现在该看哪几本」。归档的书里相对路径故意不改，理由见那边的 `README.md`。

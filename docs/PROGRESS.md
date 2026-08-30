# 进度

| | |
|---|---|
| 最后更新 | 2026-08-30 |
| 分支 | `phase0+3`（已合入 upstream `534ee2d8` / **3.6.7**，review 通过并提交；`master` 同步快进到 3.6.7） |
| 构建 | Bug T2 的 Tier7 旁路删除后，受限环境 Debug `BUILD SUCCEEDED`；现有 warning 来自上游旧 API / 资源名 / `-ld_classic` / always-run phase 与未安装 SwiftLint |
| 阻塞 | 无硬阻塞。Bug T1 / T2 均已实战验收并提交 |
| **下一步** | Bug T3（对手记牌器混进我方卡牌，已确认是**上游行为**）；之后 Phase 0 / T6 第 3 步，按新基线打 p50，目标 D 段 |
| **下一次要你亲自看** | 🎮 **Bug T2 修完后**：标准模式一局，全程不该出现左上角那个 `Tier7 Battlegrounds Overlay` 浮窗。另：**对手记牌器混进我方卡牌**这条还缺证据 —— 下次撞见请记「哪几张卡 + 大概第几回合冒出来」（一开局就有 = 牌组/初始实体归属；中途才有 = 某张卡效果触发的归属错误） |
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
| **T6** | **修埋点量程（D 段 + B 段 + E2E 归因）→ 取 Release 基线 → 打 p50** | 🟡 第 1 步 ✅、第 2 步（取基线）✅ 2026-08-30；第 3 步打 p50 未开始 |

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
> 而 D 段量程也还没修。**已于 2026-08-30 补跑 Release 重取**，见下面「延迟实测」。

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
| ③ | 排队时显示的是上一局残局 | `game.reset()` 只在 `Gameplay.Start` / `CREATE_GAME` 跑，排队时 `revealedEntities` 还是满的。**且这同时解释了"排队时记牌器为什么会显示"** —— `_currentGameType` 也没被清，绕过了 `Game.swift:376` 的条件。**清残留会让记牌器消失**，必须和放宽条件一起做 | 🟡 **我方卡组已修**（2026-08-30 实战确认 30 张全在），但带出两条新反馈，见下面「③ 的两条余留」 |
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
>
> ⚠️ **但挡掉的只是两处里的一处。** 最终合进去的 `isDeckTrackerQueue`（`Game.swift:253`）
> 自己就读 `isInQueue`，而且**没有 `isInMenu` 门**。同一个陈旧状态一旦发生，受害者换成
> 我方记牌器：`isInQueue` 卡在 `true` 时它会被强制显示，包括对局结束回到菜单之后。
> 目前只靠 `QueueEvents.modes` 白名单 + `currentDeck != nil` 兜着 —— 菜单模式 `.hub`
> 不在白名单里，所以要 `currentMode` 也一起陈旧才会露出来。**这条还没被证伪，见下。**

#### ③ 的余留已查明：不是显示条件，是主线程死锁（代码已修，待实战）

用户原话：「现在的确是显示完全的卡组了，但是对手的也会残留下来，正确的行为应该是只显示
我方的卡组，而且退出排队回到炉石主菜单的时候，还继续显示，这也是错误的。」

第一轮静态分析查不出来 —— 按代码对手记牌器应该已经消失（`reset()` 打回 `.gt_unknown`
→ `updateOpponentTracker` 条件为假 → `updateAllTrackers()` 每轮都调 → 无条件
`window.orderOut(nil)`）。加了 `[trackervis]` 临时诊断后第二次复现，**答案是代码没错，
是主线程死了**：

```
17:17:38 player show=true gameType=gt_unknown inQueue=true deckTrackerQueue=true mode=tournament
```

排队时我方判定 `true` ✅，同一时刻对手**没有翻转行**，说明它一直是 `false` ✅ —— 两个判定
都正确。用户看到的"残留"是 **overlay 冻在最后一帧、没人执行 `orderOut`**，所以跟着他从
对局到排队页、到主菜单、一直叠到终端窗口上。同批症状还有：悬停协同高亮消失、相关牌浮窗
消失、对手卡牌标记和回合计时器一直挂着。

🔴 **根因见 `docs/tasks/bug-t1-viewmodel-offmain-writes.md`**：`Watchers.swift:133` 的
`onDiscoverStateChange` 在 `DiscoverStateWatcher` 自己的队列上（16ms 一次）直接调
`highlightPlayerDeckCards` → `TrackerCardListViewModel.setHighlight` 写 `@Published rows`，
与主线程的 `Tracker.update` → `playerType.setter` 抢同一个 Combine publisher 锁。
证据是系统 hang report
`/Library/Logs/DiagnosticReports/HSTracker_2026-08-30-173357_wadomarkm4.hang`
（`Duration: 790.21s`，turnstile 明写主线程 waiting for `DiscoverStateWatcher` 线程）。
同类的后台写入至少还有四处，一并进那本任务书。

2026-08-30 已按任务书完成静态修复：从 `Watchers.initialize()` 全量反查 16 个 watcher，确认并把
7 条后台 UI 写路径异步搬回主线程；其中 `QueueWatcher → setConstructedQueue` 和
`SceneWatcher → invalidateUserState` 是抽查表外补出的两条。高亮只在 watcher 调用点跳主线程，
tracker 自己的 hover / exit 仍同步执行。受限环境 Debug 已 `BUILD SUCCEEDED`，诊断代码完整保留；
任务仍留在 `docs/tasks/`，等标准模式实战、hang report 与 `[trackervis]` 日志三项验收通过再归档。

> **`hide_all_trackers_when_not_in_game` 默认 `false`**（`Settings.swift:215`，用户
> `defaults` 里也没写过）这条仍然成立，只是不是本次的解释：即使没有死锁，一局打完回主菜单
> 两个记牌器本来也会挂着显示终局。修完死锁后如果用户仍觉得碍事，那是**开关问题不是 bug**。

> ⚠️ 上面那条"`isDeckTrackerQueue` 没有 `isInMenu` 门"的隐患**仍未被证伪**，只是这次没轮到它 ——
> 本次 5 局每个 `Now in queue` 都有配对的 `No longer in queue`，`isInQueue` 没卡住。留着。

#### Bug T1 已验收提交（`ac116be0`），同局带回两条新反馈

2026-08-30 18:31 那一局：**无新的 `.hang`**，`[trackervis]` 从 18:31 到 18:39 全程正常翻转
（死锁那一轮是一行都不打的），协同高亮每次都出，卡池浮窗不再串卡。三项验收全过。

新反馈两条：

**(a) 构筑对局中弹出 `Tier7 Battlegrounds Overlay` 浮窗**，停在 `Loading...` 压住对手记牌器。
✅ **已于 2026-08-30 21:11–21:35 实战验收通过**（三局标准模式，浮窗全程不再出现，无新 hang，
`[trackervis]` 正常翻转）。Codex 独立复核确认这是 `ac116be0` 的时序回归：线程修复后的同一个 main
block 先由规范路径隐藏窗口，`isModalOpen` 派出的延迟 property 回调随后又绕过 `.bacon` 场景门，
把 controller 的 `isVisible` 改回 true，最后由 `updateBattlegroundsOverlays()` 显示。已删除这条
重复的旁路，保留 `updateTier7PreLobbyVisibility()` 作为唯一正常显示决定；完整 FIFO 推演和
review 七条逐项结论见任务书。

**(b) 对手记牌器混进我方卡牌。** 日志坐实了那一局是 `DEMONHUNTER` vs `WARRIOR`
（`HSReplayAPI.getConstructedMulliganV2` 那两行），用户点名 DH 的牌出现在战士对手的记牌器里。
**跟本次改动无关** —— diff 没有一行碰实体归属或对手卡表。已排除三条系统性原因：
> - **不是相关卡牌推测**：`Cards/` 下所有 `shouldShowForOpponent` 里能返回 true 的**全部**调了
>   `CardUtils.mayCardBeRelevant(..., playerClass: opponent.originalClass)` 做职业门（唯一没调的
>   是张 Neutral 卡，中立不需要）；且它列的是 `getRelatedCards(player: opponent)`，对手自己打出的牌。
> - **不是 `knownOpponentDeck`**：只有手动关联对手牌组和 Whizbang 会设，每局开始清（`Game.swift:2456`）。
> - **不是 `revealedEntities` 越界**：它按控制者收口（`Player.swift:174`）。
>
> 落点在**实体归属**，需要那一局的原始 Power.log，HSTracker 自己的日志没留够。
> **暂不开任务书** —— 现在只能写「去查」，给不出有效约束。下次复现请记：
> **哪几张卡** + **第几回合冒出来**（开局就有 = 牌组/初始归属；中途才有 = 某张卡效果触发）。

**自动化测试边界**：尝试只跑现有 `DatabaseTests`，但测试 target 在编译测试模块前就失败：
`ReplayUploadTests.swift` 仍 import 已不在依赖图里的 `Wrap`，测试 target 的 Header Search Paths
仍指向旧 Mono include 路径。两项在 3.6.5 基线和 3.6.7 上游都存在；修复前者涉及恢复或替换依赖，
按范围规则本轮不动。主 app 的 clean / 增量构建与实际 CardDefs.bin 产物检查均已通过。

---

## 延迟实测

五轮探针数据（`HSTRACKER_LATENCY_PROBE=1`，各一整局标准模式，OBS 同规格录屏保持负载恒定）。
单位毫秒，格式 **p50 / p95**。分段口径见本文件末尾。

| 段 | 8-20 Debug | 8-21 Release | 8-22 Release（T5 后） | 8-30 Debug（3.6.7 后） | **8-30 Release（T6 新口径）** |
|---|---|---|---|---|---|
| A 日志行 → 解析 | 197.5 / 993.3 | 150.3 / 227.9 | 162.5 / 285.6 | 85 / 200 | **152.1 / 285.3** |
| B 解析 → 置位 | — | — | — | — | **0.3 / 8.6** |
| C 置位 → tick | 106.4 / 199.5 | 106.9 / 195.3 | 114.3 / 398.0 | 17 / 116 | **114.5 / 202.4** |
| D tick → UI 提交 | 179.6 / 819.1 | 20.1 / 273.5 | 14.8 / 384.3 | 57 / 224 | **81.7 / 269.4** |
| E2E 日志行 → UI | 479.8 / 1872.7 | 309.8 / 787.4 | 283.3 / 1570.7 | 171 / 450 | **350.0 / 622.2** |

> 🔴 **8-30 Debug 那一列只能当"没有数量级问题"的证据，不能横向比。** 两个理由：
> **(a) 是 Debug 包**（从 `Build/Products/Debug` 起的），D 段含 `-Onone`；
> **(b) D 段量程仍未修**，只覆盖 `updateAllTrackers()` 派出的 ~20 个 block 里的第一个。
> 该列的长尾：E2E **p99 = 5044 / max = 9293**，D **max = 10946**，且 >10s 的样本被丢弃。

**最后一列是现在唯一作数的基线**：`Build/Products/Release`、3.6.7.3733、5 局标准模式
（14:41–15:23，2 胜 3 负），`dropped 0 outliers`。原始 dump 与注意事项存在
`~/Desktop/dev/HSTracker-ab/logs/probe-2026-08-30-release-t6.txt`。
长尾：E2E **p99 = 1279.7 / max = 2488.6**，D **p99 = 629.0 / max = 1928.2**，
C **max = 2021.2**。

> ⚠️ **A 段的百分位只覆盖最后约 3000–4000 行**，不是整段 42 分钟 ——
> `LatencyProbe.maxSamples = 4000`，满了丢最旧的 25%（`LatencyProbe.swift:36,67`）。
> B / C / D / E2E 的 n 都在 1000 以下，是全程累计值。

### 新基线读出来的三件事（2026-08-30）

- ✅ **分段能对上总账**：A 152.1 + B 0.3 + C 114.5 + D 81.7 = 348.6 ≈ E2E 350.0。
  口径自洽，不存在没被任何一段覆盖的空隙。
- 🎯 **该打的是 D，不是 C。** `Game.guiUpdateDebounce` 只有 16ms
  （`HSTracker/Logging/Game.swift:46`），最多解释 C 的 114.5 里的 16 —— 剩下约 98ms 是
  `guiUpdateInFlight` 闸门（`Game.swift:271`）：下一轮刷新在等上一轮的主队列 block 提交完。
  **C 是 D 的因变量，压 D 会同时把 C 带下来**，两段合计 196ms，是 E2E 350ms 里唯一能动的部分。
  探针输出里 C 那行还标着 `<- debounce`，这个标注现在是误导的。
- 🔒 **A 段的 152ms 基本动不了。** 我们自己只占 `LogReaderManager.updateDelay = 50ms`
  的轮询（`LogReaderManager.swift:16`，均摊约 25ms），其余约 127ms 是炉石自己的写盘节奏。
  把轮询压到 16ms 最多省 17ms，还要按 CPU 换，优先级排在 D 后面。

### 仍然作数的结论

- ✅ **8-20 / 8-21 / 8-22 三轮已被 8-30 Release 取代。** 上游 3.6.7 往同一个主线程 tick 里加了
  不少东西（counters 改 SwiftUI、战棋指南、OutFinder 的卡池计算），基座变了；
  T6 又改了 D 和 E2E 的量程。**旧三轮只能看趋势，不能和新列比数。**
- **Debug 数据不算数。** D 段那 180ms 里约 160ms 是 `-Onone` 的锅。
  任何性能结论在 Release 对照做完之前都不成立 —— 这条踩过两次。
- **T5 预期的 ~100ms 始终没有兑现**，C 段三轮 Release 是 106.9 → 114.3 → 114.5，纹丝不动。
  瓶颈从「100ms 轮询定时器」换成了「一次完整刷新占住主队列多久」，两者数量级碰巧相同。
  新基线把这件事坐实了：16ms 的防抖只占 C 的一成半，其余是在等上一轮刷新。
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
  > **→ 8-30 结果：C 的 p50 没变（114.3 → 114.5），这条怀疑排除。** E2E 的 p50 从 283.3
  > 涨到 350.0，涨幅 66.7 与 D 的涨幅 66.9（14.8 → 81.7）几乎相等 —— 是量程变宽，不是变慢。
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
`BobsBuddy-version.txt` 已更新到 1.69.3（Phase U 时是 1.69.0），并和 HearthDb 36.4.0 一起固定进
仓库；构建会核对两份程序集版本。T7 的磁盘/网络图片都通过
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
| **T6 新口径 Release 基线（现行）** | `~/Desktop/dev/HSTracker-ab/logs/probe-2026-08-30-release-t6.txt` |

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
7. BobsBuddy `1.69.3` 与 HearthDb `36.4.0` 的 zip 固定在 `Vendor/Managed/`，普通构建不访问两个
   会变化的 latest URL。版本文件是唯一声明；安装阶段先在 staging 校验四个文件与两份程序集版本，
   全部通过才 `cp` 到 `downloaded-frameworks/managed/`。升级时同时替换对应 zip 和版本文件。
   不要把版本写进制品路径，也不要改成直接 unzip 到 outputs —— 后者会保留归档旧时间，导致阶段
   每次构建都被 Xcode 判为过期。升级用 `scripts/update-managed-deps.sh` 预览版本，确认后加
   脚本打印的 `--apply <BobsBuddy版本> <HearthDb版本>` 落盘，再跑一次受限环境构建。

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

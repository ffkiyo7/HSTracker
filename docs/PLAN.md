# HSTracker 个人分支改造计划

> **本文件是「要做什么、为什么这么做」。「做到哪了」看 `docs/PROGRESS.md`。**
> 已完成阶段在此只保留结论；执行细节与踩坑记录归档在 `docs/archive/plan-detail-2026-08-22.md`。

## Context

`~/Desktop/dev/HSTracker` 是 HearthSim/HSTracker 的 fork，定位为**个人自用版**，不以回合并 upstream 为约束。

用户提出的四个问题，均已定位到源码根因：

1. **Overlay 不跟手 / 卡顿**（对比 Windows 上的 Firestone）—— 渲染层用即时模式 `NSView.draw()` 手绘、
   每帧从磁盘重读并解码主题 PNG、每帧拆掉整棵视图树重建，外加 500ms 的全局刷新节流。
2. **记牌器是 30 张平铺** —— 打出/抽到的牌只是变暗但仍占位，看不出牌库里还剩什么。Firestone 分三段。
3. **简体中文没翻全** —— 846 个 key 有 410 个（48%）没有 zh-Hans。
4. **设置界面粗糙**（20 个原生 checkbox 平铺在 XIB 里），**Dock 菜单「卡组」点了没反应**。

目标：一个在 macOS 上手感接近 Firestone 的记牌器 —— 渲染改 SwiftUI、卡牌按区域分组、界面全中文、
设置页可读、菜单可用。

---

## 阶段总览

| 阶段 | 内容 | 状态 |
|---|---|---|
| **Phase 0** | 地基：驱动循环与窗口层 | ✅ **T0–T6 完成。T6 于 2026-08-31 主动收在测量阶段，不做延迟优化** —— 理由见 Phase 0 一节 |
| **Phase 1** | SwiftUI 记牌器渲染 | 🟡 T1–T4 / T7 完成并已实战，T5 / T6 / T8 待做 |
| **Phase U** | **合并上游 3.6.7** | ✅ 卡点 ① 已实战（2026-08-30），产出 5 条反馈，见下 |
| **Phase 2** | 记牌器分区（牌库 / 手牌 / 已打出） | ⬜ 依赖 Phase 1 的 T4 / T6 |
| **收尾** | 删 A/B 开关、删旧路径（原 Phase 1 的 T9） | ⬜ **排在 Phase 2 之后** |
| **Phase 3** | 补全简体中文 | ✅ 完成（Phase U 补课后 100%） |
| **Phase 4** | 设置界面 + Dock 菜单 | ⬜ 前置已解除，随时可开始 |
| **Phase 5** | 计数器 overlay 可自由拖动 | ⬜ 落点已按 3.6.7 重新确认 |
| **Phase 6** | 排队时就显示牌组 | ✅ T1 2026-08-30 实战通过（进队列 30 张全在）；**「改动很小」的判断已被推翻**，见 Phase 6 一节。排队入口随后被 Bug T4 收紧（补 `isInMenu` 门、对手无排队入口） |

### 本轮（2026-08-30）—— 卡点 ① 实战产出

用户打完一局提了 5 条。逐条核对后的归属：

| # | 反馈 | 结论 | 归属 |
|---|---|---|---|
| ① | 抽到手上的牌还留在牌库段，延迟一两回合甚至一直不消 | **不是延迟**（E2E p50 171ms）。是 `highlightCardsInHand` 的既定行为 | Phase 2 / 2.1 分区时消化 |
| ② | 卡池浮窗串卡（「误炸」窜进好几张卡的相关牌） | **上游 3.6.7 的回归**：`RelatedCardImageView` 的 `@State` 按行列下标复用 | `docs/archive/tasks/phaseU-t1-outfinder-stale-tile.md` |
| ③ | 排队时显示的是上一局残局 | `game.reset()` 只在对局开始时跑 | `docs/archive/tasks/phase6-t1-queue-residue.md` |
| ④ | 卡条尺寸一局之内会变大 | **上游一直如此**（行高按行数压缩），用户暂不改 | 记在 2.8，待用户决定 |
| ⑤ | 留牌时右下角的 HSReplay 引流浮窗 | 有开关，已改为**本 fork 默认关闭** | ✅ 已落地 |

顺带确认的：E2E **p99 5.0s / max 9.3s** 的长尾是真的，且 >10s 的样本被探针直接丢弃。
连同「D 段量程存疑」「B 段没埋点」两个旧的 🔴，一起进 `docs/archive/tasks/phase0-t6-latency-spike.md`（已归档）。

**顺序约束**：Phase 0 必须先于 Phase 1（否则新渲染层仍被节流和主线程 AX 阻塞卡住，
会得出「SwiftUI 也没变快」的错误结论）；Phase 2 依赖 Phase 1；Phase 3 / 4 与 0–2 完全独立。

**2026-08-29 的重排**：新增 `Phase U`（合并上游 3.6.7），插到 Phase 1 的卡点 ① 之前。
一句话理由是 **T3 用的 tooltip 类被上游换掉了、合完编译不过**，而延迟基线的 before / after
必须站在同一个上游基座上才有可比性。完整评估见下面 Phase U 一节。

---

## 🎮 需要人亲自看的卡点

**凡是改视觉的，都要用户亲自看过才算过。** 下表是全程清单：做到带 🎮 的那一片时**停下来交包**，
不要连着往下做。

| 标记 | 含义 |
|---|---|
| 🎮 | **必须开炉石进一局**（或进队列），肉眼看 |
| 🖥️ | 不用开炉石 —— 比对窗 / 设置窗口静态看即可 |
| 📊 | 要开探针跑一局取数据，看的是数不是眼 |

| 到哪一步 | 标记 | 这一次要亲自看什么 | 备料 |
|---|---|---|---|
| Phase 1 / T4 段头做完 | 🖥️ | 段头的底色、边框、图标、字体、行距，与 `DeckLens` 逐像素比 | `HSTRACKER_CARD_ROW_COMPARE=1` |
| **Phase U 合完上游** | 🖥️ | app 能起、记牌器有卡条、设置窗口不出现裸 key —— 静态过一遍就够，真正的验收并进卡点 ① | 增量包已验证完整，不再强制 `clean build` |
| ~~**Phase 1 卡点 ①**~~ | ✅ | **2026-08-30 已过**：ETC 标题正确、协同高亮描边 OK、卡图无顿挫。产出 5 条反馈见「本轮」一节。**延迟 before 基线取的是 Debug 包，不可用**，Phase 0 / T6 修完口径后要重取一次 Release | — |
| ~~卡点 ① 的战棋那一局~~ | ❌ | **取消。用户不玩战棋**（2026-08-30 确认）。两个新计数器的工程登记已完成、二进制里检出，但**没有人会去实机数它们**，这条不再挂在清单上 | — |
| **Phase 1 卡点 ②**（T5） | 🎮 | 三行头的数字对不对：手牌数 / 牌库数 / 总胜率 / 对阵职业胜率 | 开局前第 3 行应是占位或整行隐藏 |
| **Phase 1 卡点 ③**（T6） | 🎮 | **整个布局** —— 必须独占一局，混着别的改动根本没法定位 | 各段都有内容的一局最好 |
| **Phase 1 卡点 ④**（T8） | 🎮 | 动效 —— 要**录像逐帧看**，不是当场看手感 | OBS 同规格录屏 |
| Phase 2 分区落地（2.1 / 2.2） | 🎮 | 抽到的牌从「牌库」进「手牌」、打出后进「已打出」；**三段之和恒等于原牌表**；关掉 `groupCardsByZone` 能干净回平铺；对手侧未链接牌表时保持平铺 | 一局标准模式 |
| Phase 2 / 2.6 高亮加强 | 🎮 | **只能在游戏画面背景上看** —— 问题本身就是「在炉石背景上几乎看不出来」，比对窗验不了 | 一张弑君者之类的关联卡 |
| Phase 2 / 2.7 已打出段图标 | 🎮 | 骷髅 / 火焰状态图标 —— 要真的弃牌、爆牌才会出现 | 带弃牌的牌组 |
| Phase 2 / 2.8 尺寸重做 | 🎮 | **全屏实机** —— 这是最初提的「卡条太宽、整体太高」，只有全屏才作数；换一次分辨率再看一遍 | 全屏 + 至少两种分辨率 |
| 收尾（删开关、删旧路径） | 🎮 | 完整打一局，确认新路径没有退路也不出问题 | **不可逆** —— 做之前新路径要已经连续用过一段时间 |
| Phase 4 / 4.1 Dock 菜单 | 🎮 | 先不开炉石，看 Toast + 菜单项打勾；**再开炉石进一局**确认用的就是那副牌 | 切中文后重复一遍 |
| Phase 4 / 4.3 设置界面 | 🖥️ | 设置窗口逐页看，不用开炉石 | 中英文各看一遍 |
| Phase 5 计数器拖动 | 🎮 | 在炉石窗口上真拖一次；计数器变多时往哪个方向长；换分辨率后位置跟不跟 | **构筑局，有计数器的职业**（不走战棋） |
| ~~Phase 6 排队显示~~ | ✅ | **2026-08-30 已过**：进队列 30 张全在；Bug T4（08-31）又验了排队只我方 / 对局双方 / 打完即消失 / 主菜单不显示。战棋侧只做静态论证（用户不玩） | — |
| ~~Phase 0 剩余优化~~ | ❌ | **取消。** D 段量程已修、Release 基线已取，但 T6 于 2026-08-31 收在测量阶段，优化候选表作废（见 Phase 0 一节）。仅剩「合并 18 次投递」以帧一致性立项，排在 Phase 1 / T5、T6 之后 | — |

> 3.6.7 已消除原来的 bundle 双写入者。增量构建即使重跑 `Resources` 阶段，
> `CardDefs.bin` 和 `Resources/Managed` 也不会再被覆盖；只有 HearthMirror 版本刚变化、旧 PCH
> 与新 framework 冲突时需要执行一次 `clean build`。机制与实测见 `AGENTS.md`「构建」。

---

## 总体决策

### 1. 部署目标 macOS 14.0（✅ 已落地）

原为 `10.14`，这是全项目 97 处 `@available(macOS 10.15, *)` 的来源，也是 SwiftUI 无法自由使用的
唯一障碍。升到 14.0 之后 SwiftUI 无需守卫，并可用 Observation 框架的 `@Observable`
（失效粒度比 `ObservableObject` 细得多，对性能目标是实质性的）。

代价：本 fork 从此不能在 macOS 13 及更早的系统上运行。个人自用版，可接受。
那 97 处守卫只是变成恒真，清理它们是可选收尾，不阻塞主线。

### 2. 架构：保留窗口层，替换内容视图

**保留**（`WindowManager` / `SizeHelper` 的定位逻辑全部依赖它们，动了牵连太广）：
`Tracker: OverWindowController` 这个 NSPanel 本身、数据管线 `Game.updatePlayerTracker()` → `tracker.update(...)`。

**替换**（窗口内容视图下的一切）：`AnimatedCardList`、`CardBar`(+4 主题子类)、`DeckLens`、
`DeckSideboards`、`CardCounter`、`PlayerDrawChance`、`OpponentDrawChance`、`GraveyardCounter`、
`StringTracker`，以及 `Tracker.updateFrames()` 那 280 行手写 y 游标布局（`Tracker.swift:127-405`）。

做法与仓库已有的 SwiftUI 落地点一致（`RootOverlayWindow.swift:24` 已在用 `NSHostingView`）。
**upstream 自己正在往 SwiftUI 迁移**（Mulligan V2、RootOverlay 都是 2026 年新加的 SwiftUI 代码），
本次重写是顺着这个方向走。

### 3. 开发期 A/B 开关

`Settings.useSwiftUITracker`，重写期间可随时切回旧 AppKit 记牌器做对照。

> **默认 `false`，删除时机在 Phase 2 之后**（见文末「收尾」一节）。
> 这台机器每天在打游戏，默认值不能是没在真实对局里看过的那条路径。

---

## Phase 0 — 地基：驱动循环与窗口层（✅ 完成）

> SwiftUI 重写只解决"画得慢"，解决不了"半秒才知道要画"。

| | 做了什么 | 落点 |
|---|---|---|
| T0 | 前置环境；修 upstream 的 `NET_VERSION = net7.0`（mono 已升 8.0.29，全新 clone 必然构建失败） | `project.pbxproj` |
| T1 | `WindowManager.show()` 改为**值变化时才赋值** `styleMask` / `level` / `collectionBehavior` | `WindowManager.swift:418-483` |
| T2 | 4 次阻塞式 AX 调用移出主线程；缓存 `AXUIElementCreateApplication`；`HearthstoneWindow` 可变状态加锁 | `SizeHelper.swift:37-118` |
| T3 | `guiUpdateDelay` 0.5 → 0.1；窗口轮询独立节流 250ms | `Game.swift` |
| T4 | 部署目标 → macOS 14.0（app target 的 Debug / Release 两行） | `project.pbxproj` |
| T5 | GUI 刷新由 100ms 轮询改为 16ms 防抖调度 | `Game.swift` |
| **T6** | **修埋点量程（D 段 + B 段 + E2E 归因）→ 取 Release 基线 → 拆 D** ✅ **收在测量阶段，不做延迟优化** | `LatencyProbe.swift` / `Game.swift` / `LogReader*.swift` |

**T6 的顺序是死的：口径没修好之前不许调参、不许优化。** 这个仓库已经在这上面栽过两次
（拿 Debug 数当 Release、拿只覆盖 1/20 的 D 段排序）。任务书
`docs/archive/tasks/phase0-t6-latency-spike.md`（已归档）与 `docs/tasks/phase0-t6b-shrink-refresh-cost.md`（已结案）。

### 🔻 T6 为什么收在这里（2026-08-31 决定）

四轮测量（修口径 → Release 基线 → 拆 D 成 22 块 → 拆补集）**没有降低一毫秒**，
而且决定**不再继续**。这不是失败收场，是前提被复查之后的主动收口。三条理由：

1. **压延迟这个目标没有用户反馈支撑，而且是探针自己证伪的。** 唯一一条听起来像延迟的
   反馈是①「抽到手上的牌延迟一两回合」—— 探针一测 E2E p50 171ms，根本不是延迟，
   是 `highlightCardsInHand` 的既定行为（见上面本轮反馈表）。
   **探针最大的贡献是证明了延迟不是痛点**，而 T6b 的任务书随后把「E2E p50 = 350ms，
   要把它压下来」写成了"定死、别自己改目标"，四轮没人回头看那句话。
2. **天花板小。** A 段 p50 ≈ 139ms 里绝大部分是炉石自己的写盘节奏，动不了。
   最好情况 E2E 317 → 约 230ms。这个差别在实际对局中察觉不到。
3. **机会成本具体。** ①的真正修复在 Phase 2，Phase 2 卡在 **Phase 1 的 T6（布局收口）**，
   那一片一行没动。⚠️ **两个阶段的 T6 同名，这本身就是走偏的一部分原因，以后引用时写全
   「Phase 0 / T6」或「Phase 1 / T6」。**

**T6 实际产出的是排除法结论，都写进了 `docs/PROGRESS.md` 的「延迟实测」整节**：
A 段是地板、C 是 D 的因变量、22 个刷新 block 的代码只占 D 的 27%、watcher 插队约等于 0。
探针本身保留（`HSTRACKER_LATENCY_PROBE=1` 才开），以后任何改动都能免费打分。

### 🔹 唯一留下的候选：合并 18 次主队列投递（**不以延迟立项**）

`Game.updateAllTrackers()` 里 18 个 `updateXxx()` 各自 `DispatchQueue.main.async`，
**一轮刷新被切成 18 个独立的主队列 turn**。T6b 第 2 步测到 `gap: runloop wait/outside`
平均 19.3ms/轮非零 —— 探针的 observer 挂在 order 0、先于 CoreAnimation 的 order 2000000
翻到 `.waiting`，所以这个桶装的就是 runloop 休眠 + CA 提交。

**非零意味着：一轮刷新中间至少发生过一次 CoreAnimation 提交，也就是记牌器各段不落在同一帧。**

所以这件事真正的理由是**一致性，不是速度**：

- **肉眼可验**：牌表、计数器、水晶上限等各段可能在不同帧更新，密集操作时会看出撕裂。
- **少一份时序危险**：18 个独立投递之间的排序在这个仓库已经咬过两次
  （Tier7 浮窗的 FIFO 回归、`ac116be0` 之后的排序副作用）。合成一个 block 就没有这个缝。
- **速度是副产品**，不作为验收标准 —— 复用 Phase 1 那条"延迟不是 KPI"的纪律。

⚠️ **爆炸半径大**（18 个投递的相对顺序全变），必须独占一次实战验收，不要和别的改动混。
探针现有口径能免费给它打分（D、`wait/outside`、`source phase` 一起看），但**打分不等于验收**，
验收标准是肉眼看各段是否同步。**排在 Phase 1 的 T5 / T6 之后**，不插队。

**T3 在 review 时改了设计，这一条值得记住。** 任务书原文写「去掉 `counter > 3`，每个 tick 都刷新
窗口矩形」，按字面实现会引入回归：T2 已把 `reload()` 从 `updateAllTrackers()` 里摘掉，于是 `reload()`
只剩在 `else` 分支里，日志密集时窗口矩形将长时间不刷新、overlay 被钉在旧位置 —— 比改之前更差。
**这是 T2 与 T3 组合才出现的问题，单看任一任务都发现不了。**
实际实现是把窗口轮询提到分支之外、用独立的 250ms 阈值节流（每次 `reload()` 是 4 次跨进程 AX 调用，
真按 10Hz 跑就是每秒 40 次打进炉石自己的 run loop）。

**T5 的两个设计点**（改动它时必须保住）：
1. **不是经典 trailing-edge debounce** —— 那种「每次新请求把定时器推后」的写法在日志密集时
   会让 overlay 永远不刷新。这里是「第一个请求排一次、窗口内后续只置标志」。
2. **`guiUpdateInFlight` 不是可选项** —— 没有在途标志，上一轮还堵在主线程时下一轮就排进去了，必然堆积。

**Phase 0 的实测数据和排除法结论见 `docs/PROGRESS.md` 的「延迟实测」整节。**
量程问题已在 T6 修完；**旧的"优化候选"表已作废** —— 那张表是在 D 段量程还错着的时候排的，
而且现在延迟本身已不作为立项理由。以后要动延迟，先拿一条用户反馈来，不要拿 p50 立项。

---

## Phase 1 — SwiftUI 记牌器渲染

### 验收标准

**延迟不是本阶段的 KPI。** 拿延迟当验收标准，做完一测「只快了 20ms」，会得出「白干了」的错误结论，
而实际是标准选错了。改用三组可证伪的标准：

1. **视觉一致。** 逐元素与现有 `CardBar` 比对，同一张卡 + 同一主题下不可区分。
   `Settings.useSwiftUITracker` 这个 A/B 开关就是为此存在。
2. **具体开销被消灭。** 下面 1.1 那张清单每一条都已核对到行，逐条验证即可 ——
   **不用 ms 表达也能验证**（计数、Instruments 分配曲线、代码结构）。
3. **动效与分区。** 这才是「HDT 明显更流畅」的真正来源（见 `docs/research/hdt-overlay.md`）：
   HDT 有 1.7s 的连续 ramp，把 100~200ms 的离散步进完全藏在里面；我们只有 alpha 动画、布局一帧跳变。

> **对照基线有时间窗口。** 现存录像是 Debug 版且在 T5 之前，拿它当 Phase 1 的 before 会把
> 构建配置和 T5 混进差值里。动渲染层之前应当再跑一局 Release 探针 + 同规格录像 ——
> 一旦开始改，「旧渲染层 + Phase 0 全部优化」这个状态就再也拿不回来了。

### 切片划分

下面 1.1–1.5 是技术分解，不是干活的顺序。实际按这 8 片推进，每片一本任务书、一次 review、一个 commit：

| 片 | 内容 | 状态 |
|---|---|---|
| T1 | `CardRowView` + `ThemeImageCache` + 并排比对窗 | ✅ |
| T2 | 主牌表接进 `Tracker`，`Settings.useSwiftUITracker` 开关 | ✅ |
| T3 | ETC / 下水道之王 改悬停浮出，备牌段整体消失（见 2.5，**从 Phase 2 提前**） | ✅ 已适配 3.6.7，2026-08-30 实战通过 |
| T4 | 其余三段卡表 → `TrackerSectionView`：置顶 / 置底 / 相关牌（`DeckLens` ×3） | ✅ 2026-08-30 实战通过 |
| T5 | 顶部信息区重做：拿掉旧面板，上 Firestone 三行头（见 2.4，**从 Phase 2 提前**） | ⬜ |
| T6 | 根视图 `TrackerView` + `TrackerViewModel`，布局收口（见 1.4） | ⬜ |
| T7 | 卡图异步加载 + `ImageUtils` 缓存加 LRU（见 1.2） | ✅ 含限宽后台队列和预解码，2026-08-30 实战通过 |
| T8 | 动效：淡入淡出、抽卡闪光、布局动画（验收标准第 3 条） | ⬜ |

> **原来的 T9（删开关、删旧路径）已挪到 Phase 2 之后**，见文末「收尾」一节。
> 理由：Phase 2 的分区还要靠 `useSwiftUITracker` 做对照，删早了就没有退路了。

### 执行卡点（交给 Codex 时按这个分批）

**调用粒度不变：一次一本任务书，跑完 review diff 再放下一本。**
任务书按新规矩只给约束不给实现，越长越容易漂移；而 T3 的教训恰恰是「组合型回归单看任一任务
发现不了」，那要求人在中间 review。**能合并的是实测卡点，不是 review 轮次** ——
连着跑几本、逐本 review，然后做一次验收构建交给人打一局。

**这四个卡点都要人亲自开游戏看** —— 每到一个就停下来交包。全程的人肉验收清单
（含 Phase 2 / 4 / 5 / 6）见本文件开头的「🎮 需要人亲自看的卡点」。

| 卡点 | 批次 | 这一局验什么 | 风险 |
|---|---|---|---|
| ① 🎮 | **T3 + T4 + T7 + Phase U** | 备牌悬停展开；三个段头 + 空段折叠；卡图不再有首次加载的顿挫；上游合并没搞坏记牌器 | 中 |
| ② 🎮 | **T5** | 三行头的数据对不对（手牌数 / 牌库数 / 胜率 / 对阵职业） | 中 |
| ③ 🎮 | **T6** | 整个布局 | **高** |
| ④ 🎮 | **T8** | 动效 —— 要录像逐帧看 | 中 |

**① 能塞三片，是因为三者改的文件几乎不重叠，坏了能定位**：T3 → `DeckSideboards.swift`；
T4 → 新的 `TrackerSectionView` + `Tracker.swift` 里三个 `DeckLens` outlet；
T7 → `ImageUtils.swift` + `CardRowView.swift`。且 T3 / T7 本来就标着「与 SwiftUI 迁移无依赖」。
T7 提前做还有额外好处：后面三个卡点都能享受到异步卡图。

**T5 和 T6 不合并**，虽然看着是同一块地方。它们是剩下最难的两片，合成一个卡点等于把风险叠一起；
而实际重复的工作很小 —— T5 做出来的 `TrackerHeaderView` 本身就是 SwiftUI 视图，用 T2 那个
`NSHostingView` 兄弟视图的套路挂进旧布局，T6 只是把它挪进 `VStack`，扔掉的是几行 frame 赋值。

**③ 必须独占。** 出问题的形态是「整个记牌器错位」，混在别的改动里根本没法定位。

三条排期上的提醒：

0. **Phase U 已在卡点 ① 之前完成。** 延迟基线与 T6 的 after 现在会站在同一个 3.6.7 基座上。
1. **卡点 ① 要提前准备一副带 ETC 或下水道之王的牌**，否则 T3 那部分验不了。
2. **置顶 / 置底靠特定卡效果触发，约不出来** —— 卡点 ① 大概率会留下「没条件验证」的项，
   像 T2 那次一样。用比对窗或改设置静态看即可，不值得为它专门打局。
3. **卡点 ① 那一局顺手把探针开着**（`HSTRACKER_LATENCY_PROBE=1`）。T6 一动，
   「旧布局 + Phase 0 全部优化」这个状态就再也拿不回来了，那是最后一次拿 before 基线的机会。

### 排序的总规则

**Phase 2 里凡是「删掉某组件」或「改变某组件形态」的条目，一律排在 Phase 1 对应的移植片之前。**
否则就是把马上要删的东西先用 SwiftUI 重写一遍。已知的两条是 **2.4**（删四个顶部面板）
和 **2.5**（备牌改悬停），都已提前为 T5 / T3。2.6 / 2.7 是改视觉不改结构，留在 Phase 2。

其余约束：

- **T4 做完，`Tracker.getHoverComponent()` 那段靠 superview 遍历猜分段的代码才能删干净**（1.5 的后半）。
  T2 只让主牌表不再依赖它，其余各段还在用。
- **T6 是最难的一片** —— `Tracker.updateFrames()` 是 280 行手工排版、十几个条件分支。
  T3 / T4 / T5 都在给它减负，它要排的段越少越好动。
- **T3 和 T7 与 SwiftUI 迁移无依赖**，随时可以插队。T3 用现成的 `tooltipGridCards`，T7 是纯性能。
- **Phase 2 依赖 T4 和 T6** —— 分段头和段容器是 T4 做出来的 `TrackerSectionView`，
  三段并排的高度分配要等 T6 的布局收口。

> **待决：2.8（尺寸重做）要不要并进 T6。** 2.8 的第 3、4 条改法动的正是 T6 和 T5 那两段代码，
> 分两次做等于把同一段布局逻辑写两遍。但 2.8 还绑着贴图矢量化，那部分是独立的资源工作。**尚未决定。**

> **`CardBar` 这个类本身永远删不掉（本计划范围内）。** 除了记牌器，`CardList.swift`、`EditDeck.swift`、
> `DeckManager.swift`、战棋的 `BattlegroundsTierDetailsView` 都在用 `CardBar.factory()`，
> `AnimatedCardList` 也还被 `BattlegroundsCardsGroups` 用着。
> 收尾阶段删掉的只是**开关和记牌器里的旧路径**。

### 目录结构

新目录 `HSTracker/UIs/Trackers/SwiftUI/`：

| 文件 | 职责 | 取代 |
|---|---|---|
| `TrackerViewModel.swift` | `@Observable`，持有分组、以及 2.4 三行头要的套牌名 / 手牌数 / 牌库数 / 胜率 | — |
| `TrackerView.swift` | 根 `VStack`，按设置条件拼装各段 | `Tracker.updateFrames()` |
| `TrackerSectionView.swift` | 分段头（图标+标题）+ 卡行列表，空则折叠 | `DeckLens` / `DeckSideboards` |
| `CardRowView.swift` ✅ | 单张卡行 | `CardBar` + 4 个主题子类 |
| `TrackerHeaderView.swift` | 2.4 的三行头 | `CardCounter` / `PlayerDrawChance` / `OpponentDrawChance` / `StringTracker`（**删掉，不移植**） |
| `ThemeImageCache.swift` ✅ | 主题 PNG 一次性加载缓存 | — |

### 1.1 `CardRowView` —— 本阶段的核心（✅ T1 已完成）

`CardBar.draw()`（`CardBar.swift:295-371`）是一串 `add*()` 的图层叠加，在 SwiftUI 里天然就是 `ZStack`。

必须消灭的具体开销（均已核对到行，即验收标准第 2 条的清单）：

| 位置 | 开销 | 做法 |
|---|---|---|
| `CardBar.swift:796-816` | `NSImage(contentsOfFile:)` **每次 draw 都重新读盘+解码 PNG，零缓存**，一次重绘约 150–500 次 | `ThemeImageCache` 按 (主题, 文件名) 缓存 |
| `:68-81` | `hasAllRequired` 每次 draw 开头对 14 个文件逐个 `fileExists` | 每主题启动时校验一次 |
| `:160-204` | `required` / `optionalFrame` / `optionalGems` / `optionalCountBoxes` 是**计算属性**，每次访问新建整个字典，一次 draw 约 15 次 | 改为按主题的静态常量表 |
| `:697-730` | `fitFontForSize` 二分查找试字号，每次迭代跑完整文本排版；每行约 12 次 | `.minimumScaleFactor()` + `.lineLimit(1)` |
| `Settings.swift:34-37` | `UserDefault.get` 每次走 `UserDefaults.object(forKey:)` 无缓存，一次重绘约 2000 次 | 视图模型统一读一次、随通知失效 |
| `CardBar.swift:243-272` | `update(highlight:)` 每次新建两个 `CALayer` 塞进 `flashLayer` 且 `isRemovedOnCompletion = false`，而 `draw()` 只清 `cardLayer` —— **图层无上限累积** | SwiftUI 动画取代，泄漏消失 |
| `:226-241` | `cardLayer` 从不接收内容，纯粹是每帧被清空的死重 | 删除 |
| `MinimalBar.swift:24-49` | 每行每帧跑一次 Core Image 高斯模糊 | `.blur()`（GPU） |

### 1.2 卡图加载改为真异步（T7）

`ImageUtils.swift:119-146`：缓存未命中时 `loadImage` 在**调用线程**同步 `NSImage(contentsOf:)`，
而调用方是 `draw()` → 主线程磁盘读 + JPEG 解码。

→ 命中缓存直接显示，未命中显示占位并触发异步加载，完成后经视图模型驱动刷新。
顺带给 `SynchronizedDictionary` 缓存（`:36-39`，目前**无上限无淘汰**）加 LRU 上限。

### 1.3 消灭每帧视图树重建

`AnimatedCardList.swift:186-201` 每帧 `removeFromSuperview()` 再全部 `addSubview` ——
把 `update(cards:reset:)` 刚做完的增量 diff 全部作废。SwiftUI 的 `ForEach` + 稳定 `id`
天然是增量的，此问题随重写消失。

> 同样模式还存在于 `CountersOverlay.swift:46-61` 和 `ActiveEffectsOverlay.swift:55-68`。
> **本轮不动这两个**，但它们是同一 tick 里的邻居，会一起拖慢主线程。
>
> **2026-08-29 更新**：`CountersOverlay` 那一条**上游已经做掉了** —— 3.6.6 把它 port 成
> SwiftUI（`CounterChipView` + `CountersOverlayContentView`），`CountersView` 那个每帧
> 重排的 `layout()` 不存在了。Phase U 合完之后只剩 `ActiveEffectsOverlay` 一处。

### 1.4 布局（T6）

`Tracker.updateFrames()` 的自适应逻辑必须保住 —— `Tracker.swift:298-300` 的
`cardHeight = min(cardHeight, (windowHeight - offsetFrames) / totalCards)`，卡多时行高自动压缩。

在 `TrackerView` 里用 `GeometryReader` 量出可用高度，按同一公式算行高传给各段。行高常量沿用
`CardSize.swift`（`kRowHeight 34` / `kHighRowHeight 52` / `kMediumRowHeight 29` / `kSmallRowHeight 23` / `kTinyRowHeight 17`）。

### 1.5 悬停

`CardCellHover` 协议（`CardBar.swift:12-15`）+ `Tracker.getHoverComponent()`（`Tracker.swift:474-495`，
靠向上遍历 superview 猜自己属于哪一段）→ 换成 `.onHover`，**分段身份直接作为参数传入**，
那段脆弱的 superview 遍历直接删掉。悬停出卡图仍走现有的 `windowManager` floating card 路径。

---

## Phase U — 合并上游 3.6.7（✅ 完成，2026-08-30 实战验收通过）

2026-08-29 落地。正式 tag `534ee2d8` 比我们的基座（`77a85be2` / 3.6.5）多 **42 个 commit、
1036 个文件、+35498 / −26115**。3.6.7 的头条是
**The OutFinder**（Discover 助手：悬停任何生成/发现卡看完整卡池 + 费用/攻血分布，
右键开池浏览器，覆盖 700+ 效果）。另有战棋的阵容 / 英雄 / 任务指南、酒馆钉选、
一批 Bob's Buddy 修复，以及两个信息泄露修复（Azalina、始源之石）。

### 实际冲突 4 个文件

| 文件 | 冲突块 | 冲突行 | 性质 |
|---|---|---|---|
| `HSTracker.xcodeproj/project.pbxproj` | 7 | 556 | 双方各自加文件 —— **但块里压着我们两处 fork 关键设置**，见下 |
| `HSTracker/UIs/ImageUtils.swift` | 3 | 约 80 | 正式 tag 最后 5 个 commit 新增 hero 图片路径，与 T7 重叠 |
| `HSTracker/UIs/Trackers/Tracker.swift` | 2 | 52 | 正好落在 T3 改过的区域 |
| `HSTracker/UIs/mul.lproj/MainMenu.xcstrings` | 61 | 2545 | 形状全一样，可脚本化 |

其余全部自动合并。`ImageUtils` 的额外冲突已把上游 hero 图片能力接进同一套 LRU、限宽队列和后台预解码。

### 会真的咬到我们的四件事

**① T3 编译不过。** `tooltipGridCards` 换了类：`GridCardImages`（xib + `OverWindowController`）
→ `RelatedCardsTooltipPanel`（`NSPanel` + SwiftUI）。我们 T3 的 `showTooltipGridCards`
（`Tracker.swift:763`）是照抄旧 `setRelatedCardsTooltip` 的，两处失效 ——
`tooltipGridCards.title =` 要改成 `setTitle()`；`windowManager.show(controller:)` 收的是
`OverWindowController`，新类不是，要换成 `panel.show(frame:)` / `.hide()`。
改动约 10 行，**但备牌悬停必须重验**。

**② 卡牌数据库管线整个换了。** `Download enUS cards` 阶段删除；`Download cards XML` 改为
下载到 `BUILT_PRODUCTS_DIR`（app **外面**）；新增 `Compile CardDefs` 阶段编译出
`CardDefs.bin`，配套新增 `CardDefsBinary.swift` 和 `Tools/CardDefsCompiler`，
`Database.swift` 重写。→ 原来「增量包缺 `Contents/Resources/Resources/Cards/`」的备注已作废。
实测强制让 `Resources` 阶段重跑后，增量包里的 `CardDefs.bin` 仍完整，交包不再强制 clean。

**③ Mono 装配路径也改了**（`Resources/Resources/Managed` → `Resources/Managed`）。上游把根因
写进了注释：`HSTracker/Resources` 是 folder reference，Copy Bundle Resources 会整目录替换，
把这个 build phase 写进去的东西抹掉，而且构建系统看不见这次抹除。
**和我们 Cards 那条是同一类机制** —— 上游等于顺手解释了我们踩的坑。

**④ pbxproj 的冲突块里压着我们两处 fork 关键设置**：`NET_VERSION = net8.0`（上游仍是 `net7.0`）
和 `MACOSX_DEPLOYMENT_TARGET = 14.0`（上游仍是 `10.14`）。
**解冲突时必须手工保住 —— 丢了是静默回退，构建照样过。**

### 要改计划的两处

- **Phase 5 已重查。** SwiftUI 只替换了计数器内容；窗口仍是 `CountersOverlay`，`Game.swift`
  仍每拍用 `SizeHelper.playerCountersFrame()` / `opponentCountersFrame()` 覆盖位置。
  持久化锚点和拖动仍应落在窗口层，不应塞进 `CounterChipView`。见 Phase 5 一节。
- **2.6（关联卡牌高亮）的上下文变了。** OutFinder 把相关牌扩到 700+ 效果、加了池统计和
  右键池浏览器，可能已经做掉了一部分。见 2.6。

### 不受影响的（好消息）

- **`CardBar.swift` / `AnimatedCardList.swift` / `DeckLens.swift` / `CardSize.swift` 上游一行没动** ——
  Phase 1 的核心地基安全
- `Game.swift` 在我们 Phase 0 动过的区域只删了一行 `updateBattlegroundsTierOverlay`
- `SizeHelper.swift` 只删了两个战棋 frame 函数（`turnCounterFrame` / `battlegroundsTierOverlayFrame`），
  `trackerFrame()` 和 T2 的 AX 那块没碰
- `ImageUtils.swift` 在正式 tag 最后新增 hero 图片路径；已与 T7 的线程契约和缓存语义合并
- 战棋侧上游动作巨大，但与我们的路线完全不重叠，纯白拿
- 两个没登记进 pbxproj 的战棋计数器上游仍没登记；本轮已补齐 4 处工程登记并验证进入二进制。
  **实机验证已取消 —— 用户不玩战棋**（2026-08-30）

> **战棋一律不作为验收手段。** 用户不玩，凑不出局，排出来的战棋验收项只会永远挂着。
> 战棋代码该正确还是要正确（比如 Phase 6 必须挡住战棋排队），但**验证方式只能是静态的** ——
> 读代码、看构建产物、最多进队列再退出，不要写"打一局战棋"这种验收项。

### 为什么排在卡点 ① 之前

1. **T3 的 tooltip 本来就得改**，合完一起验，省一局
2. **卡点 ① 是最后一次拿 before 基线的机会** —— 但基线要和 T6 的 after 站在同一个上游基座上
   才有可比性。先合再取，基线才作数
3. 上游这轮往主线程 tick 里加了不少东西（counters SwiftUI 化、guides、OutFinder 的池计算），
   **现有基线数据本来也要重取**

代价是卡点 ① 那一局会同时验「我们三片 + 上游合并」，违反了「坏了能定位」。
缓解：上游 42 个 commit 已正式发布，我们真正的风险面是 4 个冲突文件的解法 ——
而 `Tracker.swift` 那 52 行正好落在 T3 区域，本来就要一起看。

### 执行清单

1. ✅ 开 checkpoint 分支 `backup/phase0+3-before-upstream-367`
2. ✅ `project.pbxproj` 保住 `net8.0` 和两个 `MACOSX_DEPLOYMENT_TARGET = 14.0`
3. ✅ `Tracker.swift` 按 `RelatedCardsTooltipPanel` API 适配 T3，并清空备牌浮窗的池统计状态
4. ✅ `MainMenu.xcstrings`：61 个块合并（我们插 `zh-Hans`，上游往同一个 localizations 块插
   es / fr / it / ja / ko / …），脚本化解完过
   String Catalog 校验
5. ✅ 受限环境 `clean build` 和强制 Resources 重跑后的增量 `build` 均成功；增量包完整
6. ✅ Phase 3 补课：新增 82 条简中，11 个空白/符号控制 key 标为不需翻译，覆盖率 100%

### 合并之后的后续任务：把 T3 接进 `ICardWithRelatedCards`

**先说清楚不冲突**：OutFinder 的相关牌注册表里**没有 ETC / 下水道之王**
（`HSTracker/Hearthstone/RelatedCardsSystem/` 全目录 grep `sideboard` / 这两个卡 ID 均零命中）。
它管的是 Discover / 生成类效果的卡池，备牌不是卡池 —— 合完之后悬停 ETC 仍然只有 T3 那条路径
在响应，不存在两个 tooltip 抢同一扇窗。上游 `CardUtils` 里唯一碰 sideboard 的地方是
`handleZilliax3000`，与展示无关。

**但它的框架值得复用。** 上游的形状是：实现一个 `ICardWithRelatedCards`，
`getRelatedCards(player:)` 返回要显示的卡，`ReflectionHelper.getRelatedClases()` 自动注册
（不用改注册表），定位 / 显示 / 隐藏全走 `setRelatedCardsTooltip` 这一条公共路径。
备牌完全能套进去 —— `getRelatedCards(player:)` 直接读 `player.playerSideboardsDict`
按 `ownerCardId` 匹配，和 T3 现在做的事一样，只是换了挂载点。

收益：**T3 那份 25 行的 `showTooltipGridCards` 副本可以整个删掉**（它正是合并时会编译不过的
那一段），`sideboardCards(for:)` 和 `tooltipDisplay` 里「备牌优先」的分支也一起没了。
等于用上游的框架把我们的补丁消化掉。

四个要注意的：

- `Settings.hidePlayerSideboards` 的短路要挪进新实现（返回空数组即可）
- **标题会从 `card.name` 退回「相关牌」** —— T3 当初特意用卡名，这是小退步。
  要么接受，要么在 tooltip 侧留一个标题覆盖
- `shouldShowForOpponent` 必须返回 `false`，否则 ETC 会跑进对手记牌器的「相关牌」段
- **基里亚斯那个坑还在**：注册表按 cardId 索引，而 `resolveZilliax3000` 把卡换成了外观组件的
  副本、id 匹配不上。T3 用 `card.deckbuildingCard.id` 解决过一次，接进新框架要在查表点重做

统计面板不会误弹：`getPoolStatistics` 只对实现了 `ICardWithRelatedCardsSummary` 的卡返回数据，
不实现就是 `(nil, nil, false)`；三张备牌也远低于 `largePoolThreshold = 20`，右键池浏览器不触发。

**排期：不要挤进 Phase U。** Phase U 里只做最小改动让 T3 编译过（约 10 行）。
理由是卡点 ① 那一局已经要同时验三片 + 上游合并，再叠一次架构重构就没法定位了；
而且改成框架实现之后**标题和优先级语义都变了**，那是要重新验的东西。

---

## Phase 2 — 记牌器分区（牌库 / 手牌 / 已打出）

新设置 `Settings.groupCardsByZone`，**默认开启**；关闭则回到现有平铺。

### 2.1 数据层

`Player.swift:389-408` 的 `playerCardList` **保持原样不动** —— 它还被 `Game.swift:2161`（战绩上传）
和 `AppDelegate.swift:616`（套牌导出）依赖。

**新增** `Player.playerCardGroups`，复用现成材料：`getDeckState()`（`Player.swift:531-663`）已给出
`remainingInDeck` / `removedFromDeck`；`hand` / `graveyard` / `board` 分区数组已存在于 `:183-186`；
`getHighlightedCardsInHand(cardsInDeck:)`（`:374-387`）已经在做匹配，可直接复用。

分组定义（**保证三段之和恒等于原始牌表，这是关键不变式**）：

| 段 | 内容 |
|---|---|
| **牌库** | `deckState.remainingInDeck` + `getPredictedCardsInDeck(hidden: false)` |
| **手牌** | `hand` 实体按 cardId 分组计数（并入 `createdCardsInHand`，受 `Settings.showPlayerGet` 控制） |
| **已打出** | `deckState.removedFromDeck` **减去**手牌部分 |

第三段刻意叫**「已打出」而不是「坟场」**：一张打出后还站在场上的随从属于 `board` 区，
既不在牌库也不在手牌也不在坟场。用"补集"定义能保证它有归属、三段永远加得起来。

> **分区顺带解决的一个抱怨（2026-08-30）**：用户报「牌抽到手上了，右侧还显示在牌库内，
> 延迟一两回合才更新，有些牌干脆一直不更新」。探针数据反证了延迟说
> （E2E p50 171ms），真正的原因是 `Settings.highlightCardsInHand`（用户开着）——
> `getHighlightedCardsInHand()`（`Player.swift:381`）**故意**把手牌里的卡重新塞回列表，
> `count = 0` + 亮绿名字。拿在手里几回合它就留几回合，一局不打就一直在。
>
> **这正是分区要消灭的东西**：三段式之后它属于「手牌」段，位置本身就说明了状态，
> 不需要"塞回牌库段再染个色"这种表达。**2.1 落地时 `highlightCardsInHand` 在分区模式下
> 应当失效**（或者说，它的语义被段归属取代），实现时要给出结论。

**对手记牌器**：`opponentCardList`（`:464-525`）在未知牌表时全部来自 `revealedEntities`，
分区意义不大且会泄露"这张在手上"这种本不该知道的信息。→ 仅在已链接牌表时
（`Player.knownOpponentDeck != nil`）启用分区，否则保持平铺。

### 2.2 UI 层

分组直接喂给 Phase 1 的 `TrackerSectionView`。分段头沿用 `DeckLens` 现有视觉
（底色 `#23272A`、边框 `#141617`、左侧 17×17 图标 + 白字标题，`DeckLens.swift:29-41`），
空段自动折叠（`:59-68` 的现有行为）。

现存的「置顶」「置底」「相关牌」本来就是分段，在新结构里成为同一套 `TrackerSectionView` 的不同实例。

**「备牌」不在此列 —— 见 2.5，它整段消失、改成悬停浮出。**

### 2.3 设置接线

- `Settings.swift` ~L352 加属性、~L652 加 key 常量（照 `removeCardsFromDeck` 的写法）
- **必须**把新 key 加进 `Game.swift:1508` 的 `playerTrackerUpdateEvents`，否则改设置不会实时重绘
- `TrackersPreferences.swift` 加 outlet + `viewWillAppear` 读取 + `checkboxClicked` 写回

### 2.4 顶部信息区重做（→ Phase 1 的 T5 执行）

现有顶部堆了四个独立组件，**用户看不懂且没有任何 tooltip**，要整块拿掉：

| 组件 | 文件 | 显示内容 | 开关 |
|---|---|---|---|
| 手牌数 / 牌库数 | `CardCounter.swift`（`Tracker.swift:18` outlet） | 图标 + `4` / `21` | `showPlayerCardCount` |
| **抽卡概率** | `PlayerDrawChance.swift:17-18,24-25` | `1 4.76%` `2 9.52%` | `showPlayerDrawChance` |
| 疲劳指示 | — | `1` / `0` | `fatigueIndicator` |
| 胜负比 | `Tracker.swift` | `6 - 7 (46%)` | `showWinLossRatio` |
| 坟场计数 | `GraveyardCounter.swift`（`Tracker.swift:23` outlet） | 随从数 / 鱼人数 | `showPlayerGraveyard` / `showOpponentGraveyard` |

**抽卡概率那两个百分比是重灾区** —— `1 4.76%` / `2 9.52%` 是「下回合抽到某张牌的概率
（该牌剩 1 张 / 剩 2 张时）」，但界面上没有任何东西说明这一点。

**坟场计数一并删掉**：Phase 2 的「已打出」段已经能看到哪些牌离开了牌库。
**代价记在这里** —— 对手侧的「坟场里几个随从 / 几条鱼人」是「已打出」段覆盖不到的
（那段只讲自己牌库里的牌），真需要时得单独加回来，不要以为分区顺带做掉了。

替换为 Firestone 式三行头（**2026-09-04 定稿 D2**，比稿过程和参数见 `docs/tasks/phase1-t5-tracker-header.md`「定稿」）：

```
第 1 行   [职业图标] 套牌名称   ｜ 手牌数 ｜ 牌库数
第 2 行   套牌胜率              ｜ 58.7%  ｜ 27 / 19
第 3 行   vs [对手职业图标] 职业 ｜ 62.5%  ｜ 10 / 6
```

- 三列表格、细白格线；底是**英雄皮肤原画**（`ImageUtils.art` 方图）左深右浅压暗，与卡条 fade 同向
- 我方 **hero 卡条不再显示**（行 1 已承担套牌名和英雄身份）；对手侧暂不动
- 中文用卡条同款字体（`TrackerTextFont.name`），数字用 Belwe Bd BT；胜绿负红

- 第 1 行的数字沿用 `CardCounter` 现有的 `deckCount` / `handCount` 数据源，只换呈现
- 第 2/3 行数据源**已确认现成**：`StatsHelper.getDeckRecord(deck:againstClass:mode:)`
  （`Statistics/StatsHelper.swift:64,87`）本来就带 `againstClass` 维度，第 2 行传 `.neutral`
  取总体、第 3 行传对手职业
- 套牌名称沿用 `Settings.showDeckNameInTracker`
- **第 3 行依赖「已知对手职业」**，开局前应显示占位或整行隐藏

### 2.5 ETC / 下水道之王 改为悬停展开（→ Phase 1 的 T3 执行）

现在备牌占一块独立区域、完整铺开三张卡条（`Tracker.swift:123`，高度按 `:337` 算），很占竖向空间。

改为：**本体只显示一条卡条**，光标移上去时才浮出所携带的三张卡（形态参照现有的「相关牌」提示）。
实现落点 `DeckSideboards.swift` —— 里面装的是**两段**（`cards` 和 `kingOfTheUnderbellyCardList`），
是同一种备牌机制，两段都要改。

浮出的载体用现成的 `windowManager.tooltipGridCards`（`Tracker.setRelatedCardsTooltip` 在用），
所以**这一片不依赖 SwiftUI 迁移**，在旧路径上就能做完。

### 2.6 关联卡牌高亮加强

能力已经有：`CardBar.swift:348` 读 `card.highlightColor`，主题资源在 `ThemeElement.swift:174-176`。

问题**纯粹是视觉强度不够** —— 光标移到弑君者，牌库里所有传说牌确实会高亮，但在游戏画面背景上
几乎看不出来。属于主题资源 + 混合模式的调整，不需要动数据层。

**建议加一个 100~150ms 淡入** —— Firestone 是硬切换，而我们的问题是高亮太弱，
淡入能强化存在感且不像位移动画那样干扰读牌。

> **2026-08-29：Phase U 已合入，卡点 ① 实测时重新看这一条。** The OutFinder 把相关牌系统
> 扩到 700+ 效果，加了卡池统计面板和右键池浏览器，`tooltipGridCards` 也换成了
> `RelatedCardsTooltipPanel`。本节讲的是**牌库里已有卡条的高亮强度**，和它不是一回事，
> 但上游可能已经顺手改善了一部分感知 —— 合完先实际看一眼再决定还要不要做。

### 2.7 已打出段的卡条形态

三段式落地后，**抽到过的牌不再暗色处理，直接移出「牌库中」段**。现在的暗色逻辑在
`AnimatedCardList.swift:45` 和 `CardBar.swift:362`，分段后这两处的暗色分支应当废弃 ——
暗色卡条留在原位会持续抢占视觉注意力，这正是要解决的问题。

「已打出」段的卡条右侧加状态图标：骷髅 = 进了坟场，火焰 = 被弃 / 被撕 / 爆牌销毁。
`wasDiscarded` 字段已存在（`AnimatedCardList.swift:183`、`CardBar.swift:890`）。

#### 两个 spike 的结论（完整调研见 `docs/research/`）

**Firestone（`firestone-overlay.md`）—— 原假设"卡牌被抽到/打出时应该有动效"不成立。**
实机 120fps 逐帧：卡条插入无动画，新行瞬间出现在最终位置，维持约 125ms 的**空白灰条**再瞬间填入
（这是渲染延迟造成的占位符闪烁，**是缺陷不是设计，不要照抄**）；关联高亮是 8.3ms 完成的硬切换。
源码交叉验证：卡条自身的 transition 被注释掉了，注释写着 `Removing the transition fixes the flicker` ——
**不做动画是选择而非能力缺失**。可借鉴的是它的 8 种状态图标。

**HDT（`hdt-overlay.md`）—— 我们端口时丢掉的东西。**
`AnimatedCardList.swift` 是 `AnimatedCardList.xaml.cs` 的逐行翻译，**唯独动画层没跟着翻译过来**：

| | HDT | 我们 |
|---|---|---|
| 抽牌闪烁 | 1.0s（0.5 淡入 + 0.5 淡出） | 0.5s，**只有淡出**（`CardBar.swift:262-268`） |
| 卡条移除 | 淡出 0.7s **+ 布局高度 ScaleY 1→0 塌陷** | 只有 `alphaValue → 0.3`，**无高度动画** |
| 下方卡条上移 | 随塌陷连续上移 | **无 —— 600ms 后跳一格** |
| 卡条插入 | ScaleY 0→1 撑开 | 只有 alpha |

关键细节：HDT 用的是 WPF 的 **`LayoutTransform`**（参与布局测量）而非 `RenderTransform`，
所以卡条收缩时下方内容每帧重排、连续上移。我们这边 `frame` 是直接赋值、不走 animator，
布局变化永远是一帧跳变 —— 这就是"向上合并"缺失的直接原因。

**做法**：照 HDT 的两段式（先闪、再塌陷），但**总时长压到约一半** ——
建议 **闪烁 0.4s + 塌陷 0.25s，数字立即更新**（HDT 是 1.7s 且数字要等 1.0s 才变，快速连抽会滞后）。
跨分区移动动画 Firestone 结构上做不到，SwiftUI 的 `matchedGeometryEffect` 可以。
**前提都是 1.3 先落地。**

### 2.8 尺寸重做：解耦宽高、改为按窗口比例

用户反馈：**全屏下卡条太宽、整体太高**。三个原因：

**（1）尺寸全部写死，且不随炉石窗口缩放。** `SizeHelper.swift:311-321` 的 `trackerFrame()` 用绝对点值，
且 `relativeFrame` 只在 `keepRatio: true` 时缩放宽高（`:220-223`），记牌器用的是默认 `false`。
而常量是按 `BaseWidth = 1440` / `BaseHeight = 922`（`:16-17`，注释写明是**原作者的 MBA 分辨率**）
调的，只在那一个分辨率下比例正确。

**（2）五档预设共用同一个宽高比。** `CardSize.swift` 里宽度是从高度推出来的
（`kSmallFrameWidth = kFrameWidth / kRowHeight * kSmallRowHeight`），五档全部锁死 **6.38 : 1**，
而 Firestone 实测是 **8.14 : 1**。**调参数解决不了，缺的是"宽高可独立设置"这个能力。**

**（3）行高被挤压时宽度不跟着收。** `Tracker.swift:296-299` 把行高压到 ~24pt 但宽度仍是 217，
宽高比从 6.38 掉到 9.0，贴图纵向压扁。`CardBar.ratioHeight`（`:841-858`）就是在给这种情况打补丁。

> **（3）的另一个可见后果：行高在一局之内会变。** 用户 2026-08-30 反馈「一开始密集，
> 打到后面卡条变大了」。就是 `Tracker.swift:459` 那行 ——
> `cardHeight = min(cardHeight, (windowHeight - offsetFrames) / totalCards)`，
> 行高是按**当前行数**压出来的，牌打光了就弹回 `card_size` 的上限。
> **这是上游一直以来的行为**（3.6.7 的 `Tracker.swift:298-299` 一字不差），不是我们改出来的。
>
> 用户当前的判断是「优先级不高，先记着，可能改变主意」。真要改，选项是
> **（a）行高固定为 `card_size`，放不下就滚动/截断**，或
> **（b）保留自适应但把宽度一起缩**（就是本节第 3 条）。
> (a) 是行为变更、要单独验一局；(b) 只是让压缩看起来不畸形，不消除"会变"这件事本身。
> **两者不能同时做。**

#### 目标尺寸（实测见 `docs/research/firestone-overlay.md` 第七节）

| 项 | 目标 | 表达为占比 |
|---|---|---|
| 面板宽 | 171 px @1920 | **8.9% 窗口宽** |
| 卡条高 | 21 px @1080 | **1.94% 窗口高** |
| 宽高比 | 8.14 : 1 | — |
| 费用格 | 22 × 21（近正方） | 12.9% 面板宽 |
| 标题栏 / 套牌行 / 分段标题 | 22 / 23 / 22 px | **均与卡条同高** |

> **本机实测确认（2026-08-20）**：逻辑分辨率 1920×1080 下实际行距 **29pt**、面板宽 **186pt**，
> 对应 `card_size = medium` 而非 `.big`。所以差距是**宽度只差 8%、行高差 38%**。
> 卡条贴图是 217×34 的 1x PNG，画在 372×58 物理像素上，放大 1.7 倍 —— 贴图问题在这块屏上实际发生。

#### 改法

1. **`trackerFrame()` 改为按窗口比例算宽度**，或保留绝对值但乘 `scaleX`（能力已有，只是没用）。
2. **宽高解耦**：`CardSize` 从"一个枚举推出宽高"改成每档各自给定宽和高。
3. **行高挤压时宽度同步收缩**，保持宽高比恒定；`CardBar.ratioHeight` 那个补丁随之删除。
4. **顶部信息区（2.4）统一到卡条行高** —— Firestone 四类元素全在 21~23px，
   我们现在 `smallFrameHeight` / `bigFrameHeight` 各不相同，是"整体太高"的另一半原因。

**绑定工作量：主题贴图矢量化。** `Themes/Bars/*/` 全部是 1x 的 217×34 PNG，**没有 `@2x`**。
改宽高比会直接拉伸它们。卡条框架应改成矢量绘制（`Path` / `Shape`），彻底摆脱固定尺寸贴图。

> **矢量化归本节，不归 Phase 1。** 它和 Phase 1 的验收标准第 1 条**直接冲突**
> （那条要求"逐元素与现有 `CardBar` 比对、不可区分"，而矢量重画就是把外观换掉）。
> T1 / T2 因此照着 PNG 逐像素复刻。矢量化是**视觉重做**，和 2.8 的宽高比一起做才成立。

---

## 收尾 — 删 A/B 开关与旧路径（**Phase 2 之后**）

原本是 Phase 1 的 T9，2026-08-22 挪到这里。**理由：Phase 2 的分区还要靠 `useSwiftUITracker`
做对照，Phase 1 一结束就删掉等于自断退路。** 这个位置没有技术上的硬约束，纯粹是排期选择。

- 删 `Settings.useSwiftUITracker` 及其所有分支
- 删 `Tracker.swift` 里的旧路径：`updateFrames()` 的手工排版残余、`cardsView` 那条 `AnimatedCardList` 分支、
  `TrackerCardListHost` 的让位逻辑、`getHoverComponent()`
- 删记牌器专用的 `DeckLens` / `DeckSideboards` 实例（**类本身留着**，别处还在用）

**这一步不可逆**，做之前要确认新路径已经连续用过一段时间没出问题。做完再打一局完整验一遍。

---

## Phase 3 — 补全简体中文（✅ 完成）

zh-Hans 覆盖率先从 **436/846 (51.5%) → 841/848 (99.2%)**；Phase U 后补上
战棋指南、OutFinder 和设置项新增的 82 条，并把 11 个空白/图标控制 key 正确标成不需翻译，
当前为 **945/945 (100%)**。

| 任务 | 内容 |
|---|---|
| T1 | 按 key 合并 `gaenyong/HSTracker@9e7b653f`（MIT），补 139 条 |
| T2 | 清掉从不参与编译的 `.lproj/*.strings`（删 104 文件 / 72 目录；可抢救译文 **0 条**） |
| T3 | 修两个"翻译了也不生效"的 bug（裸字符串 + 缺 `Archive`/`Unarchive` key） |
| T4–T6 | 主 catalog + 设置窗口 6 个 + 卡组/对局 4 个，共 264 条 |

**三条计划本身被实测推翻的地方**（留档以免重犯，详见归档）：

1. **3.2 的前提是错的。** 计划说废弃的 `zh-Hans.lproj/*.strings` 里"有现成翻译从未上线"。
   实测挖不出东西，且它把 Deck 译作**「套牌」**而现行 catalog 一律「卡组」——
   `AppDelegate.swift:440` 按标题字符串找菜单项，真按计划去"挖"反而会弄坏中文下的菜单栏。
2. **4.2 的诊断要修正。** 计划说合并 `MainMenu.xcstrings` 后菜单项查找会"变成中文能查到、英文查不到"。
   实际不会 —— gaenyong 的译法与 `Localizable.xcstrings` 已有的逐字相同，这个 bug **顺手被修好了**。
   4.2 因此从「硬性前提」降级为「消除脆弱性」。
3. **`String.localizedString` 的失败是静默的** —— key 不存在时原样返回 key，界面上看起来就是"没翻译"。

**后续动 `.xcstrings` 必须过校验器**：`python3 docs/tasks/tools/check_xcstrings.py --baseline <ref>`。

> **2026-08-29：Phase U 补课已完成。** `MainMenu.xcstrings` 的 61 个冲突保住原简中，
> 新增的战棋指南、酒馆钉选、OutFinder 和三个设置项文案已补齐；校验器对正式 3.6.7 基线通过。

---

## Phase 4 — 设置界面 + Dock 菜单

### 4.1 Dock 菜单「卡组」点了没反应

用户截图里的是 **Dock 菜单**（`AppDelegate.swift:459-489` 全代码构建），不是菜单栏。
两条嫌疑路径，**先跑起来加日志定位是哪条**（`playDeck(_:)` 在 `:572-578`，三个静默出口一个日志都没有）：

1. `:509` Dock 子菜单项是 `classmenuitem.copy() as? NSMenuItem`，依赖 `NSCopying` 把整棵子菜单的
   `representedObject` 带过去。若没带过去，`sender.representedObject as? Deck` 的 `if let` 直接失败返回。
2. 套牌其实**设置成功了**，但 `Game.updatePlayerTracker()` 被 `Game.swift:374` 挡住：
   要求 `currentGameType != .gt_unknown`，而它在对局开始前恒为 `.gt_unknown`。
   **没进对局就不显示记牌器**，而从 Dock 选套牌恰恰是在没进对局时做的 —— 零视觉反馈。
   **→ 这条与 Phase 6 是同一个根因，两者应当一起做**；Phase 6 落地后这条就不用单独修了。

修法（两条都做）：

- `representedObject` 改存 **`deck.deckId` 字符串**而非活的 Realm `Deck` 对象。顺带解决另一个隐患：
  `getActiveDecks()` 返回活对象、被菜单项无限期持有，套牌被删后 `deck.deckId` 会抛异常；
  而 `Game.set(activeDeckId:)`（`:1731`）按 id 取不到时**静默清空** `currentDeck` —— 等于选个旧套牌
  反而把记牌器重置了。
- 加可见反馈：选中项 `.state = .on`，并弹一个 Toast（`HSTracker/UIs/Toast/` 已有现成组件）。

### 4.2 顺带修菜单栏（同一个 bug 的另一面）

`AppDelegate.swift:440` 用 `mainMenu?.item(withTitle:)` 按**标题字符串**找菜单项。同样的写法还坑了
`:514` 的 `Replays` 和 `:546` 的 `Window`（导致 `:547-550` 的"锁定/解锁窗口"切换永远不更新）。

→ 改为按 **tag 或 IBOutlet** 定位。Phase 3 落地后这个 bug 已被顺手修好（见 Phase 3 第 2 条），
所以本项**从"硬性前提"降级为"消除脆弱性"** —— 两个 catalog 任何一边以后重译一次就会再次静默失效，
仍然值得做。

### 4.3 设置界面重做

现状：SPM 包 `sindresorhus/Preferences`（`AppDelegate.swift:44-59`）+ 9 个 XIB 面板。
`TrackersPreferences.xib` 是 469 行、20 个 checkbox 平铺在 `NSStackView` 里、54 条手写约束、
**没有分组框、没有分节标题、没有说明文字**，全部汇入 `TrackersPreferences.swift:109-176`
一个巨大的 `if/else if` 链按 `sender ==` 比对。这就是"粗糙"的来源。

既然已经上了 macOS 14 + SwiftUI，用 `Form` + `Section` 重建面板，原生外观直接就对了。

**先只做 Trackers 一页**，验证 `NSHostingController` 接进 `PreferencePane` 协议的接法可行后，
再逐页迁移。分页标题与图标定义在各控制器的 13/15/17 行，图标资源在
`Assets.xcassets/settings-*.imageset`，这部分不动。

---

## Phase 5 — 计数器 overlay 可自由拖动

> **2026-08-29：已按 3.6.7 重新调研。** `CountersView` / `CounterView.xib` 虽已换成
> `CounterChipView` + `CountersOverlayContentView`，但这只改变窗口里的内容。窗口控制器仍是
> `CountersOverlay`；`Game.swift:585/598` 仍在每拍把两个窗口重设为
> `SizeHelper.playerCountersFrame()` / `opponentCountersFrame()`，所以下面的根因继续成立。

场攻 / 无界空宇 / 大范等计数器（`CountersOverlay.swift`）**位置写死**。现在的位置由
`SizeHelper.playerCountersFrame()`（`:591`）/ `opponentCountersFrame()`（`:584`）按炉石窗口算出，
每次刷新都重算，因此拖了也会被弹回去。

新的实现边界也已确定：拖动手势和持久化属于 `CountersOverlay` / 窗口层；
`CounterChipView` 只负责单个数字胶囊，不能在这里存窗口位置。上游已经提供
`forceShowExampleCounters()`，并在解锁窗口时调用，原计划里的“拖动模式显示示例计数器”无需再新增。

**已有现成范式可照抄** —— `TimerHud` 就是可拖动且位置持久化的：

```
TimerHud.swift:76     拖动结束 → Settings.timerHudFrame = self.window?.frame
Settings.swift:383    @UserDefaultCustom(key: timer_hud_frame, defaultValue: nil)
Game.swift:443        重新定位时优先读 SizeHelper.timerHudFrame()
```

**关键：持久化的应当是锚点而非绝对 rect**，否则计数器变多时会溢出屏幕。
HDT 已有现成方案（`docs/research/hdt-overlay.md` 第四节），三个设计点正好印证这个判断：

1. **存百分比不存像素** —— `PlayerCountersVertical += delta.Y / Height`，换分辨率自动跟随。
2. **横向额外过一次画面比例折算**（`GetScaledXPos(pct, width, ScreenRatio)`）——
   炉石在超宽屏上是居中 letterbox，直接按窗口宽取百分比会飘。我们 `SizeHelper` 有同类问题。
3. **玩家侧锚上边、对手侧锚下边**，面板朝**远离锚定边**的方向生长 ——
   这就是"计数器数量变化时往哪长"的答案。

另有一个 UX 细节值得抄：进入拖动模式时**强制显示一组示例计数器**，
否则当前没有计数器激活时用户看不到自己在拖什么。

设置里应提供「重置计数器位置」入口（4.3 重做设置界面时一并做）。

---

## Phase 6 — 排队时就显示牌组（✅ T1 2026-08-30 实战通过）

用户反馈（2026-08-22）：**在匹配队列里等待时记牌器完全不出现**，看不到自己这副牌带了什么；
Firestone 在排队阶段就把牌表铺出来了。

### 根因：只有一个条件挡着

`Game.updatePlayerTracker()`（`Game.swift:366`）的显示条件里有一项：

```swift
// Game.swift:374
(!self.isBattlegroundsMatch() && !self.isMercenariesMatch() && self.currentGameType != .gt_unknown) &&
```

而 `currentGameType`（`:1185`）的值只有两个来源 —— `cacheGameType()` 读 mirror（`:1744`）
和 `cacheMatchInfo()` 里的 `matchInfo.gameType`（`:1366`）——**两者都要等对局真正开始才有值**。
排队阶段恒为 `.gt_unknown`，于是整个记牌器被跳过。

`updateOpponentTracker()`（`:291`）的 `:299` 有一模一样的条件。

> **这和 4.1 是同一个根因**（4.1 的「嫌疑路径 2」写的就是这条）。两处应当一起改：
> 4.1 抱怨的「从 Dock 选套牌零反馈」，本质也是选完之后记牌器不出现。

### 好消息：数据链路已经是通的，不用新建任何东西

1. **牌组在排队时已经拿到了。** `QueueEvents.handle()`（`QueueEvents.swift:41-45`）在进队列时就
   调 `autoDetectDeck(mode:)` → `game.set(activeDeck:)`。
2. **刷新也已经会触发。** `set(activeDeck:)` 结尾就是 `updateTrackers(reset: true)`（`Game.swift:1863`）。
3. ~~**牌表内容天然正确。**~~ **❌ 这条是错的，2026-08-30 实测推翻** —— 见下一节。
4. **计数框也已经处理过未开局的情况。** `:397` 的
   `let gameStarted = !self.isInMenu && self.entities.count >= 67`，未开局时写死 `deckCount: 30, handCount: 0`。

### ❌ 被实测推翻的假设，以及它带出来的一个反直觉结论

原第 3 条写「开局前 `revealedEntities` 是空的 → 正好是完整的 30 张」。**不成立。**
`game.reset()` 只在 `Gameplay.Start`（`LoadingScreenHandler.swift:137`）和 `CREATE_GAME`
（`PowerGameStateParser.swift:1461`）触发，**都在"对局真的开始"那一刻**。上一局结束后
`revealedEntities` 一直是满的，所以排队时看到的是**上一局的残局**（2026-08-30 用户实测）。

**更要紧的是它的另一面**：`_currentGameType` 同样只在 `reset()` 里被清回 `.gt_unknown`
（`Game.swift:1694`）。所以**现在排队时记牌器之所以会出现，恰恰是因为上一局的状态没被清掉**，
把上面那个 `currentGameType != .gt_unknown` 的条件绕过去了。

> **推论：清干净残留，记牌器在排队时就会消失。** 清残留和放宽显示条件**必须一次做完**，
> 只做前者是净退步。任务书 `docs/archive/tasks/phase6-t1-queue-residue.md`。

**所以这一项不再是"只放宽那个条件"** —— 是「在正确的时机清状态」+「放宽条件」两件事。

### 改法

把 `currentGameType != .gt_unknown` 换成「**已知牌组 + 处于构筑类排队/大厅**」：

- 队列状态用现成的 `game.queueEvents.isInQueue`（`Game.swift:97` 的 lazy 属性，
  `:1036` / `:1056` 已经在用这个模式）
- 牌组用 `currentDeck != nil`
- **战棋 / 佣兵必须继续排除。** 现在靠 `isBattlegroundsMatch()` / `isMercenariesMatch()` 挡，
  但那两个判断本身依赖 gameType，排队时同样是 unknown —— **不能指望它们**。
  改为按 `currentMode` 白名单：只在 `.tournament` / `.friendly` / `.draft` / `.tavern_brawl` /
  `.adventure` 下放行，`.bacon` 和 `lettuce_*` 一律不放行（`QueueEvents.swift:12-13` 已经有现成的两组常量）

### 要决定的两件事（已决，落地形态见下）

> **落地结果**：两件都选了保守档。① **没加新设置** —— `Settings.swift` 里没有队列相关 key，
> 排队显示是无条件行为；② **只做队列**，不做大厅。现行判定是 `Game.isDeckTrackerQueue`
> （`Game.swift:254`）：`isInMenu && isInQueue && currentDeck != nil && QueueEvents.modes 含
> currentMode && currentMode != .bacon`，其中 `isInMenu` 是 Bug T4 后补的门；对手记牌器没有排队入口。
> 下面两条保留当初的权衡。

1. **加不加新设置？** 已有 `Settings.hideAllTrackersWhenNotInGame` 语义相近，但它管的是
   「不在对局时是否隐藏**全部** overlay」，粒度不对。**倾向新加一个
   `Settings.showTrackerWhileQueuing`，默认开**；不想要的人关掉就回到现状。
2. **范围到哪为止？** 最小是「只在队列里显示」；再往外可以到「选好牌组站在大厅就显示」。
   Firestone 是后者。**建议先做队列**，`isInQueue` 是明确的开关信号，误显示的风险小；
   大厅那一档等实际用下来再说。

### 验收

进队列 → 记牌器出现、30 张全在、计数框显示 `30 / 0`；匹配成功进对局 → 平滑过渡成正常记牌器
（**不要闪一下或重置**）；退出队列 → 消失（没有设置，回主菜单一律不显示，Bug T4 定的表）。
战棋和佣兵排队时**不出现**。

**2026-08-30 标准模式实战通过**（进队列 30 张全在）；战棋队列只静态确认（`.bacon` 不在白名单）。

---

## 关键文件清单

| 文件 | 涉及阶段 |
|---|---|
| `HSTracker/Logging/Game.swift` | 0.2 / 0.4、2.3（`:1508`）、4.1（`:335-341`） |
| `HSTracker/Core/SizeHelper.swift` | 0.3（`:37-118`）、2.8（`:311-321`）、5 |
| `HSTracker/UIs/Trackers/WindowManager.swift` | 0.5（`:418-483`） |
| `HSTracker/UIs/Trackers/SwiftUI/*` | 1 / 2.2 |
| `HSTracker/UIs/Trackers/Tracker.swift` | 1（内容视图换 `NSHostingView`，删 `:127-405`） |
| `HSTracker/UIs/Cards/CardBar.swift`（+4 主题子类） | 1.1（记牌器路径删除，类本身留着） |
| `AnimatedCardList.swift` / `DeckLens.swift` / `DeckSideboards.swift` | 1.3 / 2.2 / 2.5 |
| `HSTracker/UIs/ImageUtils.swift` | 1.2（`:119-146`、`:36-39`） |
| `HSTracker/Logging/Player.swift` | 2.1（新增 `playerCardGroups`） |
| `HSTracker/Core/Settings.swift` | 2.3（~`:352` / ~`:652`） |
| `HSTracker/UIs/Cards/CardSize.swift` | 2.8 |
| `HSTracker/AppDelegate.swift` | 4.1 / 4.2（`:431-556`、`:572-578`） |
| `HSTracker/UIs/Trackers/CountersOverlay.swift` | 5 |
| `HSTracker/Logging/QueueEvents.swift` | 6（队列状态与模式白名单的现成常量） |

---

## 验证

本机 `/Applications/Hearthstone` 与 `/Applications/HSTracker.app` 都在，可以真机验证。
构建的环境要求见 `docs/PROGRESS.md` 的「环境备注」。

**Phase 0 / 1（性能）** —— 必须有对照数据，不能凭手感：

1. 探针 `HSTRACKER_LATENCY_PROBE=1`，**Release 构建**，一整局，与历史数据同规格录屏
2. 用 `Settings.useSwiftUITracker` 开关跑同一局的新旧两版
3. Instruments：`AnimatedCardList.updateFrames` 是否已从火焰图消失、主线程 CPU 占用
4. 长局观察内存曲线，确认 flash 图层泄漏（`CardBar.swift:243-272`）已消失
5. 拖动/缩放炉石窗口，overlay 应立即跟上

**Phase 2（分区）**：打一局，逐一确认 —— 抽到的牌从「牌库」移进「手牌」；打出后进「已打出」；
**三段数量之和恒等于原牌表**；关掉 `groupCardsByZone` 能干净回到平铺；
对手侧未链接牌表时保持平铺、不泄露手牌信息。

**Phase 3（中文化）**：切到简体中文，逐页翻设置的 9 个分页 + 套牌管理器 + 菜单栏，
确认无残留英文、**无裸露的 key 字符串**（key 泄漏是 `String.localizedString` 静默失败的特征）。

**Phase 4（菜单）**：不启动炉石，从 Dock 菜单选一个套牌 → 应看到 Toast + 菜单项打勾；
再启动炉石进对局 → 记牌器应用的就是那副牌。切中文后重复一遍。

**Phase 6（排队显示）**：进队列 → 记牌器出现、30 张全在、计数框 `30 / 0`；
匹配成功 → **平滑过渡，不闪不重置**；退队列 → 按设置消失。战棋 / 佣兵排队时不出现。

**回归面**：`HSTrackerTests/` 有测试目标，改完 `Player.swift` 后跑一遍（`Cmd+U`）。

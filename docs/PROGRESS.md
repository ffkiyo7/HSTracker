# 进度

| | |
|---|---|
| 最后更新 | 2026-09-03 |
| 分支 | `dev`（长期主开发线，2026-08-31 由 `phase0+3` 改名；已合入 upstream `534ee2d8` / **3.6.7**，`master` 保持为上游纯镜像） |
| 构建 | T6b 第 2 步埋点 + Bug T4 显示门受限环境 Debug / Release 均 `BUILD SUCCEEDED`（review 侧独立复跑）；测试 **50 / 50 全绿**（2026-09-03，受限环境 `xcodebuild test`），从此是红绿灯 |
| 阻塞 | 无。Bug T1 / T2 / T3 三本均已实战验收并提交 |
| **在做** | 两本都已 review 通过并提交：`docs/tasks/phase1-t5-tracker-header.md`（Phase 1 / T5，2026-09-04 按定稿 D2 重做）、`docs/tasks/phase4-t1-dock-menu-and-settings.md`（Phase 4 三件）。Bug T5 已实战确认 |
| **待实战 🎮** | 卡点 ②（T5 三行头四个数字、开局前第 3 行、原画底观感）+ Phase 4 / 4.1（Dock 打勾 + Toast，进局确认用的是那副牌）+ 🖥️ 设置页中英文各看一遍 |
| **下一片** | **Phase 1 / T5（顶部信息区）→ Phase 1 / T6（布局收口）** —— T6 收口才能解锁 Phase 2，而 Phase 2 才是反馈①的真正修复 |
| **待办（等你）** | 🎮 下一局顺带看一眼：结算瞬间两个主记牌器 + 水晶上限 + 计数器**同一轮一起消失**。**不再需要为延迟单独取数** |
| **不作为验收手段** | **战棋** —— 用户不玩（2026-08-30 确认）。战棋代码该对还是要对，但验证只能静态做，不排"打一局战棋"这种项 |

> 本文件只回答三件事：**做到哪了 / 下一步是什么 / 哪些结论还作数**。
>
> 过程记录（每个任务怎么做的、review 改了什么、模型 A/B 怎么比的、录屏怎么分析的）
> 已整体归档到 **`docs/archive/progress-detail-2026-08-22.md`**，本文件不再复述。
> 计划全文见 `docs/PLAN.md`。

---

## 状态总览

### Phase 0 — 地基（✅ T0–T6 完成）

| | 内容 | 状态 |
|---|---|---|
| T0 | 前置环境（`wget`、本地签名、`net8.0` 修复） | ✅ |
| T1 | `WindowManager.show()` 去抖 | ✅ |
| T2 | AX 调用移出主线程 | ✅ |
| T3 | 提高 tick 频率 + 跟窗 | ✅ review 时改了设计，见 PLAN |
| T4 | 部署目标 → macOS 14.0 | ✅ |
| T5 | GUI 刷新改防抖 | ✅ 代码已合，但**实测收益未兑现**，见下节 |
| **T6** | **修埋点量程（D 段 + B 段 + E2E 归因）→ 取 Release 基线 → 拆 D** | ✅ **2026-08-31 收在测量阶段，不做延迟优化**（前提复查后的主动收口，理由见「延迟实测」末尾）。产出是排除法结论 + 一个可复用的探针；唯一留下的候选「合并 18 次投递」改以**帧一致性**立项，见 `docs/PLAN.md` Phase 0 一节 |

### Phase 1 — SwiftUI 记牌器渲染（🟡 5 / 8）

| 片 | 内容 | 状态 |
|---|---|---|
| T1 | `CardRowView` + `ThemeImageCache` + 并排比对窗 | ✅ 合入 grok 版（模型 A/B 的产物，codex 版留在 `ab/t1-codex`） |
| T2 | 主牌表接进 `Tracker` + `Settings.useSwiftUITracker` 开关 | ✅ 实战验过一局，**开关默认关**（本机 defaults 已置 1） |
| T3 | ETC / 下水道之王 改悬停浮出 | ✅ **卡点 ① 实战通过** —— ETC 标题正确 |
| T4 | 其余三段卡表 → `TrackerSectionView` | ✅ **卡点 ① 实战通过** —— 协同高亮描边视觉 OK |
| T5 | 顶部信息区重做（Firestone 三行头） | 🟡 **代码完成**（2026-09-04 定稿 D2：Firestone 表格 + 皮肤原画底 + 去 hero 卡条，见任务书「定稿」），等卡点 ② 实战 |
| T6 | 根视图 + 布局收口 | ⬜ **Phase 2 的堵点**，也就是反馈①真正的前置。⚠️ 别和 Phase 0 / T6（延迟）搞混，引用时写全阶段号 |
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
| **Phase U** | **合并上游 3.6.7** | ✅ 42 commits / 4 个冲突文件 · **卡点 ① 已实战**；串卡修复 **2026-08-30 实战确认「串卡没了」** |
| Phase 2 | 记牌器分区（牌库 / 手牌 / 已打出） | ⬜ 依赖 Phase 1 的 T4 / T6 · 🎮 ×4 |
| 收尾 | 删 A/B 开关、删旧路径 | ⬜ 排在 Phase 2 之后 · 🎮 |
| Phase 3 | 补全简体中文 | ✅ Phase U 补课后 **945 / 945（100%）** |
| Phase 4 | 设置 UI + Dock 菜单 | ⬜ 三项都不依赖任何东西，随时可开始 · 🎮 + 🖥️ |
| Phase 5 | 计数器 overlay 可拖动 | ⬜ 🎮 · 3.6.7 落点已重查，根因仍在窗口层 |
| Phase 6 | 排队时就显示牌组 | ✅ T1 **2026-08-30 标准模式实战通过**（进队列 30 张全在）。战棋队列按惯例只静态确认（`.bacon` 不在白名单） |

> 🎮 = 这一阶段有需要**你亲自开炉石看**的卡点，🖥️ = 只需静态看（比对窗 / 设置窗口）。
> 每个卡点具体验什么、要备什么料，见 `docs/PLAN.md` 的「🎮 需要人亲自看的卡点」。

### 本轮任务（2026-08-30，卡点 ① 实战产出）

用户打完一局提了 5 条，逐条核对后的落点：

| # | 反馈 | 核对结论 | 落点 |
|---|---|---|---|
| ① | 抽到手上的牌还留在牌库段，延迟一两回合甚至一直不消 | **不是延迟。** 探针 E2E p50 171ms / p95 450ms，没有那个量级的样本。真因是 `Settings.highlightCardsInHand`（本机开着）—— `getHighlightedCardsInHand()`（`Player.swift:381`）**故意**把手牌里的卡塞回列表，`count = 0` + 亮绿名 | Phase 2 / 2.1 分区时消化（PLAN 已记）。用户已认可 |
| ② | 卡池浮窗串卡（「误炸」`WW_348` 窜进好几张卡的相关牌） | **上游 3.6.7 的回归。** `RelatedCardImageView` 的 `@State image` + `ForEach(0..<rows/cols, id:\.self)`，格子身份是行列下标不是卡；`hide()` 只 `orderOut`，视图树不销毁 → 复用时留着上一张的图。`git diff 534ee2d8` 对该文件为空；3.6.5 用的是 AppKit `GridCardImages`，所以是换 SwiftUI 时引入的 | ✅ 格子身份改为位置 + card id，**2026-08-30 实战通过** |
| ③ | 排队时显示的是上一局残局 | `game.reset()` 只在 `Gameplay.Start` / `CREATE_GAME` 跑，排队时 `revealedEntities` 还是满的。**且这同时解释了"排队时记牌器为什么会显示"** —— `_currentGameType` 也没被清，绕过了 `Game.swift:376` 的条件。**清残留会让记牌器消失**，必须和放宽条件一起做 | ✅ **Bug T4 已于 2026-08-31 实战验收通过**（排队只我方 / 对局中双方 / 打完即消失 / 主菜单都不显示）。带出的两条一致性问题转 Bug T5 |
| ④ | 卡条尺寸一局之内会变大 | **上游一直如此**：`Tracker.swift:459` 的 `cardHeight = min(cardHeight, (windowHeight - offsetFrames) / totalCards)`，行高按当前行数压缩。3.6.7 的 `:298-299` 一字不差 | 记在 PLAN 2.8，**等用户决定**（(a) 固定行高 / (b) 宽度跟着缩，二选一） |
| ⑤ | 留牌时右下角的 HSReplay 引流浮窗（`MulliganToastView`，「What should I keep?」，`SizeHelper.swift:474` 定位在右下） | 有现成开关 `Settings.showMulliganToast` | ✅ **已改为本 fork 默认关闭**，见「与上游的默认值差异」 |

顺带确认：**E2E p99 5.0s / max 9.3s 的长尾是真的**，且 >10s 的样本被 `outlierCutoff` 直接丢进
`dropped` 计数、不进百分位。连同两个旧的 🔴（D 段量程、B 段没埋点）一起进 Phase 0 / T6。

这五条对应的三本任务书均已完成、review 通过并实战验收。**Phase 0 / T6 已于 2026-08-31 收在测量阶段
（修口径 + 取基线 + 拆 D 完成，"打 p50"那一步主动取消）** —— 理由见下面「延迟实测」末尾那节。
注意①的真正修复在 Phase 2，不在 T6。

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
> Bug T4 已给 `isDeckTrackerQueue` 补上 `isInMenu` 门。即使 `isInQueue` 因 watcher stop 竞态卡在
> `true`，一进对局排队入口也会关闭；对局入口不读它，因此不会再把陈旧排队位接到整局显示路径上。

#### ③ 的余留已查明：不是显示条件，是主线程死锁（已修并实战验收）

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

🔴 **根因见 `docs/archive/tasks/bug-t1-viewmodel-offmain-writes.md`**：`Watchers.swift:133` 的
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
tracker 自己的 hover / exit 仍同步执行。**已于 2026-08-30 实战验收通过并提交 `ac116be0`**
（无新 hang report、`[trackervis]` 全程正常翻转、协同高亮每次都出）。
`[trackervis]` 那组临时诊断已在三条报告全部结案后删除。

> **`hide_all_trackers_when_not_in_game` 默认 `false`**（`Settings.swift:215`，用户
> `defaults` 里也没写过）仍是这次复现的直接原因。Bug T4 已不再让该开关决定两个主记牌器能否留在
> 非对局界面；它若打开还会误伤排队显示，因此不能拿设置代替场景门。

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

**(b) 对手记牌器混进我方卡牌。** ✅ **已于 2026-08-30 22:49–22:55 实战验收通过**（那三张不再出现，
对手真实亮牌 / 剩余牌库数 / 抽牌概率均正常，无新 hang）。原 A / B 二分漏了
第三条路径：三张症状牌正好是恶魔猎手的完整奇闻组。开局 `START_OF_GAME_KEYWORD` 揭示本机的
布洛克斯加时，`TagChangeActions.predictFabled` 不看控制者，一律把整个奇闻组写进
`opponent.inDeckPredictions`。原始 Power.log 四局交叉核对中，本机玩家 ID 与布洛克斯加控制者每次
都一致，实体归属没有错；`knownOpponentDeck` 也解释不了每局重新出现的精确奇闻组。

修复只给这条开局预测加对手控制者门：玩家奇闻跳过，对手奇闻维持原预测。没有在显示层做职业过滤，
不影响真实亮牌、牌库计数和抽牌概率。review 的 RelatedCards 职业门与 `revealedEntities` 收口结论
成立，但前者只覆盖 RelatedCards 子系统；另一个旧结论“`knownOpponentDeck` 每局开始清”不成立，
实际是传统模式结束时条件清。本次完整证据、逐项复核和临时日志处置见 Bug T3 任务书。

**自动化测试已是红绿灯（2026-09-03，50 / 50）**。Build T2（`10c6a812`）先去掉失效的 `Wrap` / 系统 Mono
依赖，测试 target 改为宿主 `HSTracker.app` 并只编译 9 个测试文件，不再复制编译 302 个 app 源文件；
当时 49 项里 24 个旧预期失败，逐项分类及 pbxproj 对账见 `docs/archive/tasks/build-t2-fix-test-target.md`。
2026-09-03 把旧预期更新到当前规则，全绿：

- **23 条测试过期**：Dreadscale 卡面文案、`CORE_EX1_249` 的 `CARD_SET=1810`（`.placeholder_202204`，
  不是 2021 的 `.core`）、Bargain Bin（随从 / 法术打出即排除，6 处）、Mystic Misdirection（随从发起攻击即
  排除，5 处）、Bait and Switch（英雄攻击随从那一支）、上游 `c0fd1210` 的秘密撤销规则（随从死亡不再
  撤销"打出随从"那批排除，9 处）。review 侧此前抽查过 `SecretsManager`（`:563` / `:564` / `:839` /
  `:873` / `:473`），排除逻辑确在，方向在安全一侧。
- **1 条测试夹具耦合**：宿主 app 先按本机 zhCN 加载卡库，`card.text` 是中文；改断言 `card.enText`。
- **顺带抓到一个运行时真 bug**：`Card.copy()` 漏拷 `enText`，而 `Cards.any(byId:)` / `Cards.by(cardId:)`
  返回的都是副本 —— 所以任何走查表拿到的卡 `enText` 都是空串。受影响的读者：`Card.hideCost`
  （`enText.contains("Passive")`）、`BattlegroundsKeyword.swift:65`、`BattlegroundsDb.swift:179`
  （种族文本检测）。已补一行 `copy.enText = self.enText`。上游 3.6.7 同样有此漏拷，合并时留意别被还原。
- `PowerParserTests` 空方法已换成两条真测试（`CREATE_GAME` + `GameEntity` / `Player` 行能建出实体）。

没有测试需要炉石进程。**以后改完跑一次测试**（`AGENTS.md` 已加规则），红了就是回归。

#### 2026-08-31 复现：打完回主菜单两个记牌器仍挂着（→ Bug T4）

用户第二次提这件事，截图为 22:20 的炉石主菜单，左侧对手记牌器（牧师）和右侧我方记牌器
（牌组「地沟油」）同时可见，内容是刚结束那一局的终局状态。

🟢 **已排除是 8-30 那个死锁的复发**：无新 `.hang`（最新一份仍是 8-30 17:33 那份）；
延迟探针到 22:20:09 仍在正常产出（D 的 `n` 从 135 涨到 139），主队列是活的；
本局 `Now in queue`(22:10:59) / `No longer in queue`(22:11:12) 正常配对，
`isInQueue` 没卡住 —— 上面那条「`isDeckTrackerQueue` 没有 `isInMenu` 门」的隐患**这次也没轮到它**，
继续留着。

**所以这次是显示条件本身的问题。** 前面那条注（`hide_all_trackers_when_not_in_game`
默认 `false`，即使没死锁打完回菜单也会挂着）现在从"开关问题"升级为要修的 bug ——
因为**现有开关表达不了用户要的那张表**：排队时要显示我方牌组，主菜单时两个都不显示，
而这两种情形都不在对局里。

✅ **Bug T4 已实战验收通过（2026-08-31 23:17–23:26，Release，标准模式一局）。** 两个主记牌器现在只认
正向场景：传统对局由 `!gameEnded && !isInMenu` 放行；我方额外保留构筑排队入口，对手没有。
排队入口补上 `isInMenu`，因此**上面那条挂了两轮的"`isInQueue` 卡住会让我方记牌器整局强制显示"
隐患从结构上关闭了**。默认值没改。静态真值表、状态异常边界和 review 的四条副作用见
`docs/archive/tasks/bug-t4-tracker-visibility-out-of-game.md`。

用户确认四项行为全部一致：排队只我方 / 对局中双方 / **打完瞬间双方消失** / 同一时刻水晶上限
overlay 单独留着。后两项是 review 预先指出的副作用，用户已分别拍板：

- **「打完瞬间消失」保留**，不改回"离开牌桌才消失"。理由是 `gameEnded` 同时充当判定和触发点 ——
  `inMenu()`（`Game.swift:2211`）只置位、不请求刷新，改条件而不补刷新会重新开出显示陈旧终局的窗口。
- ✅ **Bug T5 已完成静态验收。** 水晶上限 overlay 和双方计数器不再读旧的
  `hide_all_trackers_when_not_in_game` 判定，统一复用 T4 的 `!gameEnded && !isInMenu` 对局门；因此结算
  瞬间会与两个主记牌器一起隐藏。`clearTrackersOnGameEnd` 只在带 `reset` 的结束刷新清空一次，普通刷新
  不再反复写隐藏窗口。受限环境 Debug `BUILD SUCCEEDED`；标准模式窗口实效仍需下一局顺带确认，战棋只做
  静态论证。完整读者清单和边界见 `docs/tasks/bug-t5-tracker-visibility-consistency.md`。

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

### D 段分解实测（2026-08-31 Release 一局）

原始 dump：`~/Desktop/dev/HSTracker-ab/logs/probe-2026-08-31-release-t6b.txt`。
本局 D `p50 = 63.8`（n=139），`coverage = 100.0%`，恒等式闭合。

| D part | p50 | avg | share |
|---|---|---|---|
| **unattributed / queue gaps** | **44.0** | 44.2 | **61.8%** |
| player tracker | 6.9 | 9.1 | 12.7% |
| first main-queue wait | 0.1（p95 42.3 / p99 93.3） | 8.0 | 11.2% |
| counters | 3.4 | 3.7 | 5.1% |
| 其余 18 项合计 | — | ~6.6 | 9.2% |

🔴 **补集是最大项，所以还不能进优化。** 这正是 T6b 第 1 步预先写下的判据：
`coverage` 100% 只说明恒等式闭合（补集按定义永远补得齐），不说明定位成功。
D 中位数 63.8ms 里有 44.0ms 不在任何一个命名 block 里；22 个 block 的代码加起来只有约 19.5ms。
**单个 block 的代码不是成本所在。**

补集的物理位置是确定的：`Game.updateAllTrackers()` 里 18 个 `updateXxx()` 各自
`DispatchQueue.main.async`，一轮刷新被切成 18 个独立的主队列 turn，44ms 落在这些 turn 之间。
成因至少两类，**优化手段完全不同，必须先分开**：runloop 自己的工作
（AppKit layout / display、CATransaction 提交、SwiftUI 刷新 —— 用户 `use_swiftui_tracker = 1`，
`@Published` 写完的视图更新在 turn 之间 flush，成本因此不落在写它的 block 里），
或者别人投进主队列的 block 插队（`ac116be0` 刚把 7 条 watcher→UI 写路径搬上主队列，
其中 `DiscoverStateWatcher` 16ms 一次）。→ **第 2 步已把这两类分开，结果见下。**

### 补集已拆开（2026-08-31 第 2 步，Release 一局）

原始 dump：`~/Desktop/dev/HSTracker-ab/logs/probe-2026-08-31-release-t6b-step2.txt`。
两条 coverage 都是 **100.0%**，`unknown` 桶为 0，测量本身可靠。
D total 7849.4（n=107，p50 66.5 / avg 73.4），补集 4779.0 = **D 的 60.9%**。

| 补集分项 | 占补集 | 占 D | avg | p50 → p95 |
|---|---|---|---|---|
| `gap: runloop source phase` | **51.3%** | 31.2% | 22.9 | 4.2 → 51.9 |
| `gap: runloop wait/outside` | 43.3% | 26.4% | 19.3 | 4.9 → 60.7 |
| `gap: runloop transitions` | 5.3% | 3.2% | 2.4 | 0.3 → 7.7 |
| **`gap: watcher ...` × 7** | **0%** | **0%** | — | — |

- 🟢 **watcher 插队被干净否定。** 对局那一段（n=107）七个桶全程零样本，包括 16ms 一跳的
  `DiscoverStateWatcher`。**"合并 turn 没用、要改 watcher 排队方式"这条路走死了，
  以后不必再回头看。** 同时说明 `ac116be0` 的线程修复没给刷新路径引入插队成本。
  > 后来 HSTracker 在主菜单空转了 20 分钟，累计到 n=339 时有两个桶出现了痕量值
  > （`watcher battlegrounds state` 合计 **0.1ms / 25373ms**、`choices visible` 0.0）。
  > 结论不变。**但这说明回归哨兵的阈值不能设成"任何非零"** —— 菜单空转本来就会蹭到几微秒。
  > 要看的是 share 有没有到能和 `source phase` / `wait/outside` 相提并论的量级。
- 🟡 **多 turn 确实在收费，已有实证。** observer 用 order 0 注册，先于 CA 的 order 2000000
  翻到 `.waiting`，所以 `wait/outside` 装的是 runloop 休眠 + CoreAnimation 提交 + AppKit display。
  **一轮刷新平均 19.3ms 花在"我们的 block 之间、系统在提交画面"上。**
  ⚠️ 这个解读依赖 observer 的 order 关系，谁改了掩码或 order，桶的含义会静默翻转。
- 🔴 **仍不进优化：`source phase` 是最大项（51.3%）**，按设计是混桶（没被包住的主队列 block、
  其它 RunLoop source、libdispatch 排空开销）。一半把握不足以支撑"把 18 个投递合成 1 个"
  这种爆炸半径的改动 —— 主队列时序在这个仓库已经咬过两次。
  **→ 第 3 步（继续拆 `source phase`）已取消，T6 收在这里，理由见下面那节。**

**两条给以后的读数纪律：**

- **两个大桶都尾部重**（source p50 4.2 / p95 51.9 / max 278.5，wait p50 4.9 / p95 60.7），
  中位数那轮刷新其实很便宜，均值被尾部拉起。**判断优化收益要盯 p95，只看 p50 会低估。**
- **结构在两局之间高度一致**（补集 60.9% vs 61.8%，player tracker 13.2% vs 12.7%，
  counters 5.3% vs 5.1%，首次等待 11.4% vs 11.2%）。两次独立采样吻合到这个程度，
  说明这个结构是真的，不是单局噪声。绝对值仍不宜跨轮比 —— 第 2 步的 observer 开销落在
  D 窗口内部，方向是抬高 D（量级 <0.1%）。

> **不要和 8-30 那份五局基线（D p50 = 81.7）直接比强弱。** 本局只有一局、n=139，
> 对局节奏也不同。**能比的是结构，不是绝对值。**

> ⚠️ **取数踩到两个坑，命令已在任务书里修正。**
> (a) **Release 包不往 stdout 打日志** —— `ConsoleDestination` 在
> `AppDelegate.swift:200-203` 被 `#if DEBUG` 包着，只有 `FileDestination` 常开。
> 原任务书让 `tee` stdout 再从该文件 `rg`，永远读不到 `[latency]`，浪费了一局。
> 正确读法是 `grep '\[latency\]' ~/Library/Logs/HSTracker/hstracker.log`。
> (b) **首次从 DerivedData 直接启动会卡在 AppMover 的 "Move to Applications folder" 模态框上** ——
> 它在 `applicationWillFinishLaunching` 里阻塞，而日志系统在之后的
> `applicationDidFinishLaunching` 才配置，表现为"进程在跑但一个字都不写日志"，
> 极容易误判成没启动。窗口常被炉石盖住，要切到 HSTracker 点 Don't Move。

### D 补集第 2 层埋点的口径（2026-08-31，Release 数据已取，结果见上节）

- 两层：精确计时 `ac116be0` 新增的 7 类 watcher / scene 主队列写入；其余间隙由主 RunLoop observer
  按 `source phase`、`timer/observer phase`、`wait/outside`、`transitions`、`unknown` 分桶。
- 两条恒等式：`D gaps additive` 检查子桶能否加回原补集；`D breakdown additive` 检查整轮 D 闭合。
  两条 coverage 都必须约等于 100%。
- **`source phase` 是混合桶**（AppKit/SwiftUI、未包住的 app/framework 主队列任务、其它 source 处理）。
  它最大就必须再拆，不能当成"渲染"直接合并 turn。判据和 Release 命令在 T6b 任务书。
- 没有改变任何刷新 block、顺序、防抖或频率。Debug 烟雾样本（`n=1`）两条 coverage 100%，数值不作性能判断。

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
- ✅ **T6b 已把 D 拆成可加总分布**：18 个一级刷新 block、4 个条件二级 block、首次主队列等待和
  未归因间隙逐轮结算；累计 `componentTotal / D total` 是覆盖率。
  **两局 Release 已取到数**，结论见上面「D 段分解实测」和「补集已拆开」——
  补集稳定占 D 的 61%；第 2 步把它拆成 RunLoop phase + 7 类 watcher 插队，
  **watcher 插队为 0（干净否定）**，多 turn 收费拿到实证（`wait/outside` 19.3ms/轮），
  但 `source phase` 51% 仍是混桶。→ **第 3 步已取消，T6 收在这里**，理由见下面那节。
- **掉帧不是 HSTracker 造成的**（在这套录屏方法的精度内）：对照组
  （HSTracker 完全没启动、只有静态主菜单）横跨了同样的范围。头号嫌疑是采集管线
  （4K 165Hz 面板压成 1080p120）。要排除它得换一个不经过 OBS 的测量手段，再录一段没用。

### 🔻 T6 到此为止：为什么主动收在测量阶段（2026-08-31 决定）

四轮测量（修口径 → Release 基线 → 拆 D 成 22 块 → 拆补集）**没有降低一毫秒**，
决定不再继续。不是失败收场，是前提被复查之后的主动收口：

1. **压延迟这个目标没有用户反馈支撑，而且是探针自己证伪的。** 唯一一条听起来像延迟的反馈
   是①「抽到手上的牌延迟一两回合」—— 探针一测 E2E p50 171ms，根本不是延迟，是
   `highlightCardsInHand` 的既定行为。**探针最大的贡献是证明了延迟不是痛点**，
   而 T6b 的任务书随后把「E2E p50 = 350ms，要把它压下来」写成了"定死、别自己改目标"，
   四轮没人回头看那句话。这是编排上的失误，记着。
2. **天花板小。** A 段 p50 ≈ 139ms 基本是炉石自己的写盘节奏。最好情况 E2E 317 → 约 230ms，
   实际对局中察觉不到。
3. **机会成本具体。** ①的真正修复在 Phase 2，Phase 2 卡在 **Phase 1 的 T6（布局收口）**，
   那一片一行没动。⚠️ **两个阶段的 T6 同名，这本身就是走偏的一部分原因** ——
   以后引用一律写全「Phase 0 / T6」或「Phase 1 / T6」。

**成本没看上去那么大**：8-30 那五局和 8-31 的两局本来就要打（验死锁、Tier7、奇闻牌、Bug T4），
探针是搭车的。真正吃掉的是 Codex 的实现轮次和 review 轮次。

**留下来的东西**：上面整节的排除法结论，加一个默认关闭、口径自洽的探针 ——
以后任何改动都能免费打分。**唯一留下的优化候选「合并 18 次主队列投递」改以帧一致性立项**
（一轮刷新中间至少有一次 CA 提交，各段不落在同一帧），详见 `docs/PLAN.md` Phase 0 一节。

> **以后要动延迟，先拿一条用户反馈来，不要拿 p50 立项。**

### ~~Phase 0 剩下的优化候选~~（已作废）

~~两个日志轮询用信号量串起来 / 文件轮询换 `DispatchSource` / 优化 `updateFrames()`~~ ——
这张表是在 D 段量程还错着的时候排的，而且前两项打的都是 A 段，
现在已知 A 段 152ms 里只有约 25ms 属于我们。**延迟本身已不作为立项理由，整表作废。**

---

## 已知问题（都已定位，等对应阶段处理）

| 问题 | 根因 | 归属 |
|---|---|---|
| 卡牌从右侧消失时"卡顿" | `CardBar.fadeOut(highlight:)`（`:285`）函数体只有 `if highlight`，count==0 的卡淡出根本不播，但 `asyncAfter` 仍死等满 **600ms** 才删行 | Phase 1 / T8 |
| 数量变化（4→3）一帧跳变 | 插新 bar + 立即删旧 bar，`fadeOut: false`；全局没有任何布局动画 | Phase 1 / T8 |
| Discover 开着时悬停记牌器，OutFinder 的池会消失 | 备牌浮窗和 OutFinder 共用 `RelatedCardsTooltipPanel.shared`；鼠标移开触发 `hide()`，而 `DiscoverStateWatcher` 只在状态**变化**时回调（`:63` `if curr == _prev { continue }`），要等玩家真的选牌才回来 | 合并上游相关牌框架时一并解决（PLAN 的 Phase U 后续任务） |
| 卡条尺寸一局之内会变大 | `Tracker.swift:459` 行高按当前行数压缩，牌打光了弹回 `card_size` 上限。**上游一直如此**，非回归 | 等用户决定，选项记在 PLAN 2.8 |
| 抽到手上的牌仍留在牌库段（看起来像"延迟一两回合"） | `Settings.highlightCardsInHand` 的既定行为：`getHighlightedCardsInHand()`（`Player.swift:381`）把手牌里的卡以 `count = 0` 塞回列表。**不是延迟**，探针 E2E p50 171ms | Phase 2 / 2.1 分区时消化（用户已认可） |
| 设置里「不在对局时隐藏全部记牌器」现在是个**完全没用的勾选框** | Bug T5 把最后两个读者（水晶上限、计数器）改走 T4 的对局门后，`hideAllTrackersWhenNotInGame` 只剩 `Settings` 声明和 `TrackersPreferences` 的读写，不再影响任何窗口。撤掉它要动 XIB，而任务书按 `_common.md` 禁止改 XIB，所以只能留着 | Phase 4（设置 UI）—— **那时一并撤掉控件和本地化 key** |

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
| 任务书（**在做 / 待验**） | `docs/tasks/` —— 当前只有 `bug-t5`（review 通过，等一局实战）。`bug-t4` / `build-t2` / `phase0-t6b` 已于 2026-09-03 归档 |
| 任务书（**已完成**） | `docs/archive/tasks/`，索引见该目录的 `README.md` |
| Firestone / HDT 的调研 | `docs/research/` |

> **`docs/tasks/` 是工作区，不是档案馆。** 一本书验收通过就挪进 `docs/archive/tasks/`，
> 剩下的永远是「现在该看哪几本」。归档的书里相对路径故意不改，理由见那边的 `README.md`。

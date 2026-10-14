# 在上游新画布上重建 fork

上游 3.6.11 之后把 overlay 重写成单一 SwiftUI 画布（`RootOverlayWindow`），`Tracker.swift` / `CardHud.swift` 已删，
`WindowManager.swift`（479 → 132 行）/ `SizeHelper.swift`（611 → 317 行）只剩通用窗口壳。
不再 merge，改为从上游新 tag 开分支、只搬值得留的东西。
每步由 Opus 子代理按薄任务书执行，Claude review 后提交。状态符号见 `AGENTS.md`。

## 开工卡点（全部满足才开分支）

| | 卡点 | 状态 |
|---|---|---|
| G1 | 🎮 上游原样包（`.claude/worktrees/upstream-probe`，已删，所测 commit 未记录）实战一局不掉帧；若卡，关掉双方记牌器即恢复也算过 | ✅ 2026-09-21「一点都不卡」 |
| G2 | 上游发出包含 `b2209e9a` + `6a57ae0f`（记牌器上画布）的 tag | ✅ 2026-09-23 核对：`3.6.12` = `c723bfd4`（09-22）含两提交 |
| G3 | dev 减负三片已提交（`d309a8ff` / `7c0f2390` / `892873de`），工作区干净 | ✅ 2026-09-21 |

G1 不过（关掉记牌器仍卡）→ 停，改评估「冻结 3.6.9 + cherry-pick」路线。

## 步骤

分支 `dev0923`（09-23 ～ 09-29 在 worktree `.claude/worktrees/refork` 里做，09-30 主仓库切过来、worktree 删除），起点 = `3.6.12`（`c723bfd4`）。旧 `dev` 原样保留不改名，随时可回。每步验收过了才做下一步；构建 / 测试一律用 `AGENTS.md` 的受限环境命令。

| | 内容 | 验收 |
|---|---|---|
| S0 | 基线：开分支，换本地 `Config.xcconfig`，原样构建 | ✅ 09-23：受限环境失败（wget 不在 `PATH`，S1 修）；普通环境 `BUILD SUCCEEDED`；测试 151 条 150 过，唯一失败 `OfficialBuildTests.testHostAppIsRecognizedAsOfficial`（ad-hoc 签名自编译包，预期内）；`SecretTests` 全过，`96883c5b` 不用搬 |
| S1 | 构建层：部署目标 14.0（3.6.12 为 6 处 `10.15`，全改）、`Vendor/Managed` 固定 zip + 版本强校验、build phase 的 PATH / 条件代理、`update-managed-deps.sh`；BobsBuddy 升到 tag 要求的 **1.76.3**（dev 为 1.71.1；3.6.12 用到 `BobsBuddySimulationFailure` / Deity 接口）；HearthDb 重定版本，新建 `HearthDb-version.txt`（上游无此文件）并登记进 Resources 与 build phase inputs。`NET_VERSION` 上游已由 `mono-version.txt`（8.0.29）推出 `net8.0`，不再写死 | ✅ 09-23 第一批 review 过（`dev0923` `17302764`）：受限环境 `clean build` 过；版本不符构建报错；BobsBuddy 1.76.10 / HearthDb 36.6.0；DLL 放 `Contents/Resources/Resources/Managed/`（`MonoHelper.swift:434` 真正读的位置，不改 Swift；dev 放错位置，BobsBuddy 从未加载成功，日志 18 次 `Failed to load BobsBuddy`）；测试宿主启动日志已见 `Loaded BobsBuddy version 1.76.10.0`。余项：Download Mono / HearthMirror 的 wget 路径因缓存命中今天没真跑过，且 Download Mono 无 `set -e`（上游遗留），换机器首次构建时留意 |
| S2 | 翻译：`scripts/inject-zh-hans.py` 注入（对 3.6.12 干跑：注入 230 / 相同 440 / 分歧 179 / 无 zh 170）；`check_xcstrings.py` 加分隔符风格探测；179 条分歧以我们为准（09-23 用户定）；上游删掉的 3 个 catalog（`BattlegroundsSession` 43 / `BobsBuddyPanel` 16 / `LinkOpponentDeckPanel` 6，共 65 条 zh，文案已迁进 `Localizable.xcstrings` 新 key）脚本不注入，逐条对到新 key；上游新增 `ArenaPreferences`（无 zh）；`String.swift` 的 DEBUG 缺 key 警告不搬（上游 `LocalizationFormatTests` 兜底） | ✅ 09-23 第一批 review 过：17 个 catalog 只增改 zh-Hans；覆盖率 1035 / 1060（dev 967 / 981）；迁走的 65 条对上 33 条，其余 28 条是 xib 占位、4 条无对应 key；校验器加分隔符探测，验收命令须带 `--allow-zh-edit`（195 条是有意覆盖上游 zh）；🖥️ 设置页中文正常。**dev 的 `Localizable` 有 53 条带译文的 fork key（`session_recap_*` / `tracker_*` / `Zone_*` 等）没进来，S3–S6 搬对应代码时一起补，否则显示英文**。余项归 S6：3.6.12 新增、界面会显示却无 zh 的 9 个 key（`Secret_Helper` 可用旧线 `tracker_secret_helper`「显示奥秘助手」、`Overlay_Layout`、`Overlay_Layout_Section_Order`、`Enum_DeckPanel_Graveyard`、`CardTile_Drawn_By`、`No minions on board`、`ArenaPreDraft_Panel_Title`、`aberration`、`BE`）；「套牌 / 卡组」混用 8 处待统一；校验器 E2 改成按 baseline 的风格比（现为四种风格任一即过，会放过风格被换） |
| S3 | 分区数据层：`Fork/PlayerCardZones.swift`、`Entity` / `TagChangeActions` 的洗入闩、全部 fixture 和分区测试；把 `Player.game` 放宽，余下约 40 行（含 Perf P1 的 `playerTrackerSnapshot` / `playerCardList(deckState:sideboards:)` / `playerCardGroups`）一并搬出；`Card.copy()` 补拷 `enText`（`9ab2f0cd`，3.6.12 仍漏）；`RealmHelper.needsCardCountFix`（Perf P1）；Bug T3 奇闻预测只写对手（`999f2eee`，3.6.12 `TagChangeActions.predictFabled` 仍不判控制者） | ✅ 09-26 实测分区张数与 dev 一致；`687aa134` 第二批 review 过（09-24）：测试 202 条只挂预期 1 条；`Player.swift` 改 14 行（第二批修复后 12 行）；任务书已归档 `docs/archive/tasks/refork-s3-zone-data.md` |
| S4 | 面板上画布：`UIs/Trackers/SwiftUI/` 整目录 + 位图缓存搬入。上游不是单点：`RootOverlayView:571/575` 两个 `TrackerPanelView(viewModel:canvasSize:isLocked:hoverHandler:)`，绑着 `TrackerCardHoverHandler`（卡图预览 / 协同高亮）、`InteractiveRegion` / `HoverRegion` 上报（画布不接鼠标，拖拽 / 缩放只在上报区生效）、`TrackerGraveyardDetailsView`、位置设置（`player_deck_top/left/height`、`overlay_player_scaling`、`deck_panel_order_player`、`overlay_center_player_stack`）+ `migratePlacementIfNeeded`、`TrackerDeckLensView`（`2747763e`）。**外壳用 A（09-23 用户定）**：保留上游 `TrackerPanelViewModel` / `TrackerPanelView` 当外壳（位置、拖拽缩放、悬停区、坟场详情、lens 白拿），只把卡牌列表换成我们的；框的位置 / 大小走上游设置，框内行高压缩沿用我们的算法。否决 B（整个换成我们的，上述全部自己重接）。`Game` 三处 `tracker.update(cards:…)`（`:303/341/406`）旁多传分区，Perf P1 的 `updateTrackers` 单次取数一并带上 | ✅ `8c2a4081` 第二批 review 过（09-24），修复见 S5 行：测试 254 条只挂预期 1 条（`TrackerMetricsTests` 52 条全绿）；分区开关关掉退回上游原生面板；zone 模式下被替换段的 `deck_panel_order` 不再生效。09-26 实测：外观与 dev 一致、分区正确、不掉帧、锁定可用、高亮在 3.6.12 上正常（灵力瓜 / 调酒师鲍勃不亮是上游没写规则）；解锁两个上游 bug 已修（标题栏 + 拖动闪烁 `ab723fda`；蓝色染色框改天蓝描边 + 斜线把手 `5ff7f87c`，任务书归档 `docs/archive/tasks/refork-bug-unlocked-overlay.md` / `refork-unlocked-box-outline.md`），09-27 复测通过，实测转出项见「S6b 待办」 |
| S5 | 刷新合并（`scheduleGuiUpdate` / `runGuiUpdate`）+ 3 处埋点 + `Utility/LatencyProbe.swift` 本体 + scheme 的 `HSTRACKER_LATENCY_PROBE` + `tracker_perf_*` 诊断键；`WindowManager.show` 同值不写（Perf P1）、`SizeHelper` AX 读挪后台 + `UnfairLock`（T3）逐段看 3.6.12 还适不适用；`ImageUtils` 的 LRU / 后台解码先看上游现状（3.6.12 仍无 LRU）再决定搬不搬，动了就顺手加负缓存 | ✅ 09-26 实测不掉帧、悬停卡图无顿挫、锁定时点击穿透正常；`cc0fa753` + 第二批 review 修复 `d589ff8a`（09-24，我 + Fable + Codex；两本任务书已归档 `docs/archive/tasks/refork-s5-refresh-perf.md` / `refork-batch2-fixes.md`）：测试 265 条只挂预期 1 条。刷新 16ms 合并、窗口轮询 0.25s（上游约 2s、dev 0.1s）、卡图 LRU 256 + 404 负缓存、`RootOverlayWindow.updateFrames` 覆写保住按光标的点击穿透 |
| S6 | 小件，逐个先查上游有没有：排队显示牌组 + 清上一局残留、场景门（`381a9c80` 回菜单后记牌器 / 水晶上限 / 计数器不再挂着；3.6.12 仍靠 `hideAllTrackersWhenNotInGame`）、局末小结、Dock 打勾 + Toast、菜单栏按 tag 定位（4.2 `35fea72a`；3.6.12 `AppDelegate` 仍 7 处 `item(withTitle:)`，中文界面失效）、`HSReplayPreferences` 标题本地化、`Power.log` 截断修复（3.6.12 已重写 `LogReader` 截断逻辑，要重做不能 apply）、Bug T1 watcher 回主线程（`ac116be0` 7 条；3.6.12 只修了高亮一条，`isViewingTeammate` `Watchers:267`、`setBaconState`、`setDeckPickerState`、`choicesVisible` 仍后台写）、默认值差异表（`show_mulligan_toast` 等）、Trackers 设置页（上游有新的 Overlay layout 页和 Related Cards 页 `a95c4b1f`，倾向用上游的） | 🚧 拆两半。**S6a** ✅ `8a86299d`（09-24 第三批 review 过：我 + Fable + Codex，无必修；09-26 实测：排队显示、结算即隐藏、Dock 打勾 + Toast、中文菜单「解锁窗口」、退出炉石后 `Power.log` 84MB；任务书已归档 `docs/archive/tasks/refork-s6a-small-fixes.md`）：排队 / 清残留、场景门、T1 三处回主线程（`isViewingTeammate` / `choicesVisible` / discover 3.6.12 已自带，原写「仍后台写」不准）、Power.log 改在 `LogReaderManager`（新键 `keep_power_log` 默认 true）、菜单 tag + Dock 打勾 / Toast、HSReplay 标题、`show_mulligan_toast` false；测试 289 条，失败 = 签名 + `LocalizationFormatTests`（测试宿主无桌面权限）。**S6b** 🎮 09-28 四本一批，同日实测通过（备牌悬停、无抽牌概率 / 坟场行、英雄条同高、小结窗、设置页中文；三本任务书归档 `docs/archive/tasks/refork-s6b-*.md`）；09-29 Codex 事后核对打回两条必修（小结窗：旧窗关掉会随炉石退出设置杀掉新会话；`toGameStats()` 没拷 `startTime`，小结用的是结束时刻），修复 `7312c31c` 09-30 用户实测通过（任务书归档 `docs/archive/tasks/refork-s6b-fixes.md`）（`a8e59f43` 分区面板三处遗留 / `2618be4b` 局末小结 + 翻译余项 / `b12ead8c` 红龙测试预算；我读 diff + Fable 核对员「可提交、无必修」；Codex 因账号不支持默认模型没跑起来）：分区模式不画抽牌概率 / 坟场 / 备牌段、备牌悬停浮出（`deckbuildingCard.id == ownerCardId` 通用匹配）、对手英雄条 = 行高；小结窗与 dev 逐字节同；zh-Hans 补 13 + 5 条、「套牌」→「卡组」10 处、校验器 E2 按 baseline 风格比；红龙测试 `maxStatesExpanded = 400_000` + 撞顶独立断言。测试 295 条只挂签名 1 条。余项见下「S6b 待办」 |
| S7 | 红龙：`HSTracker/RedDragon/` + `RedDragonTests` 原样拷入，连同 `CardIds/Rogue.swift`（+13）/ `Neutral.swift`（+3）新增常量（3.6.12 全无，不带编不过） | ✅ 09-24 `aae3f397`（任务书已归档 `docs/archive/tasks/refork-s7-red-dragon.md`）：9 个文件与 dev 逐字节相同，未用 `CardIds`（原写「不带编不过」有误，无需补常量）；全套 289 条，`RedDragonTests` 24 条全绿（`testSearchReachesTableDamage` Debug 约 160s）。09-24 夜里一次全套跑了 7 小时未结束、采样在红龙搜索里，次晨复跑单条 162s、全套 4 分钟均正常，未复现，原因未定（疑似夜里机器挂起）。09-26 又一次全套里该条 480s 失败（23 行全 `budgetExceeded`，伤害不达表），当时炉石开着、负载 5–6.5：预算按线程 CPU 秒计，忙时测试线程多落在能效核上，每 CPU 秒干的活少 → 不稳定测试；归 S6b：测试改按展开状态数（`maxStatesExpanded`）给预算，或放宽 / 提 QoS |
| S8 | 切换：`dev0923` 推到 origin 成为工作分支（旧 `dev` 不动，作回滚点）；`AGENTS.md` 工作分支改名；重写 `docs/upstream-merges.md` 热点表 | ✅ 09-29：`docs/`、`AGENTS.md`、`.claude/agents/`、`scripts/inject-zh-hans.py` 从 `dev` 搬上新线（此后文档只在 `dev0923` 上维护）；`AGENTS.md` / PLAN 头改 `dev0923` + 3.6.12；`upstream-merges.md` 按新线重写（热点表 16 行，旧线 U / U2 / U3 记录留档）；推送见下。主仓库 checkout 仍在 `dev`，切法在 PLAN「操作备忘」 |

### S6b 余项（09-28 实测通过后剩下的）

- Trackers 设置页：fork 开关（`keep_power_log` / `show_constructed_session_recap` / 分区）进上游设置页 + `hide_all_trackers_when_not_in_game` 复选框撤控件（`clearTrackersOnGameEnd` 已成死分支，场景门在 `gameEnded` 时先隐藏）。3.6.13 已于 09-29 合入，可以做了（上游设置窗已是侧栏 + 搜索的新版，直接在新版 Trackers 页上加）。
- 等用户定：「高亮手牌」在分区模式下是否强制关（现有开关可关，按 cardId 匹配，复制到手里的同名牌也会让牌库行亮，上游 / dev 同）；备牌浮窗不受「显示相关牌」开关管（dev 同，上游备牌段也不受管）。
- 不动的上游问题：菜单勾选只在 `playDeck` 更新（清空卡组 / 自动识别不同步，dev 同）；`Watchers.swift:217` arena `main.sync`，停日志读取时主线程最多卡 5s（3.6.13 未改，dev 无此代码）；战棋 `setBaconState` 在对局中读 `isInQueue`。
- 翻译剩 12 条无 zh：11 条符号 key + `BE`（扩展包名），不补；zh-Hant 里的「套牌」按规则不动；「overlay」译法「内嵌」4 处 /「悬浮窗」3 处并存，新译文用「悬浮窗」。
- 红龙本体 `findMissingPieces` 子搜索的预算仍按 CPU 秒（测试走不到），T2 时一起看。

## 上游 3.6.13 —— ✅ 09-29 合入（Phase U4）

用户 09-29 定「先 S8 再合」。记录在 `docs/upstream-merges.md` §4 U4（冲突处理、`QueueEvents` 的 `gameTime` 哨兵补丁、HearthMirror `1a6012b5` CDN 404 → 留 `912e88ea` + `Fork/HearthMirrorMinionPoolShim.swift` 及撤法、324 条测试）；09-26 的评估原文挪到 `docs/archive/upstream-3.6.13-eval.md`。待验两项（排队牌组、rewind 一局）09-30 用户实测通过。

## 不搬的东西

- `Tracker.swift` / `CardHud.swift` 里的记牌器窗口层改动（上游已删文件）；`WindowManager` / `SizeHelper` 的窗口层改动随之作废，但其中的性能改动归 S5 逐段核对。**勘误（09-26 实测发现）**：这两个文件里不全是窗口层，`8dcf2f47` 备牌悬停浮出（ETC / 深邃之王，按 `ownerCardId` 通用匹配）是功能，被一并漏掉，新线反而画出了上游的整块备牌段；S6b-1 `a8e59f43` 已重做（分区模式不画备牌段 + 悬停本体经 `TrackerCardHoverHandler` 浮出，即 dev `0f1beb5a` 记过的「接进上游相关牌框架」）。09-26 核对员逐条查完 11 个提交（全部只动 `Tracker.swift`）：真正丢的只有 `8dcf2f47` 一组三件——悬停浮出、分区模式不画备牌段、按 `deckbuildingCard.id == ownerCardId` 通用匹配（新线上游 `TrackerPanelViewModel.sideboardBoxes` 硬编码 ETC + 深邃之王，基里亚斯组件不显示）、有备牌时备牌优先于相关牌；另 3 处与旧线的差：① 旧 SwiftUI 路径无条件隐藏抽牌概率 / 坟场计数，新线按设置照画（`showPlayerDrawChance` 默认 true，多一行）；② 对手英雄条高 `width*34/217` 不在行网格上（`1745adfa` 要求 = 行高）；③ 协同高亮只落牌库区（`d589ff8a` 有意收窄）。①② 归 S6b；① 09-26 用户定照 dev 隐藏（分区模式下不画抽牌概率 / 坟场计数；注意坟场计数行也是上游坟场详情的悬停区，隐藏后坟场详情随之没有，dev 本来也没有）
- `useSwiftUITracker` 开关和 AppKit 旧路径；Phase 5「计数器可拖动」（上游 `0b8dfd16` 已做）
- BLACK_MARKET 崩溃修复、翻译回退修复（上游 `f5641f98` / `a2ac19fc` 已做且更完整）；`Mode.fromMirror` + `EnumTests.testModeFromMirrorToleratesUnknownOrdinals`（上游 `Mode.allCases[safeIndex:]` 已覆盖，拷测试会红）
- Tier7 pre-lobby 旁路修复 `eb52832e`（3.6.12 已删该文件，由 `Game.updateTier7PreLobbyVisibility()` 接管）
- 卡池浮窗串卡修复 `dbdab593`（3.6.12 用 `.id(imageIdentity)`，含 `baconCard`，更强）
- 启动自检不再杀进程 `5e91c63f`（3.6.12 `MonoHelper.testSimulation` 已改为记日志）
- 自编译包不上报 Sentry / Mixpanel：上游 `920aa5f2` / `132538ac` 按 bundle id + team id 自动关，无需处理
- `[T11]` 诊断日志；`ab/*` 分支

## 回到主线的标准

1. S0–S8 全部 ✅。
2. 🎮 收口局一次过：外观 = dev、分区账正确、不掉帧、Bug T11 两条症状复查（高亮链路已换成上游的，要重新看）。
3. 测试全绿，条数 ≥ 上游自带 + 我们的分区 / 面板 / 红龙测试。
4. 被我们改过的上游文件不设数量门槛（原「≤15 个」是 09-21 起草时自定的，用户未定过；09-24 用户确认 fork 不回流上游，撤掉）。S8 在 `docs/upstream-merges.md` 列出 `git diff <tag> --stat -- HSTracker` 里每个上游文件与行数，改动大的（现为 `Game` / `ImageUtils` / `SizeHelper`）标为合并热点；fork 自有代码照旧放 `Fork/`、`RedDragon/`、`UIs/Trackers/SwiftUI/`、`UIs/SessionRecap/`。

之后的主线：Phase 2 / V2 余项（折叠、拖拽吸附、套牌名截断）→ Phase 4 / 4.3 其余设置页 → 红龙 T2 overlay。
T8 动效已在 dev 上做完（`UIs/Trackers/SwiftUI/` 内，S4 整目录带走），09-23 卡点 ④ 已过。

## 未决

- G1 实测带出两条上游现象（2026-09-21，上游原样包，commit 未记录）：① 卡条很小、上下的框很大 —— 面板换成我们的之后不存在，S4 验收时顺带确认；② **相关卡牌高亮在上游包里同样不亮** —— Bug T11 第 2 条症状不是我们的回归，S4 接高亮时在 3.6.12 上从上游链路查起。**09-26 两条都有了结论**：① 实测面板外观与 dev 一致，框大条小不再出现；② 根因是上游 `TrackerCardHoverHandler.deckHighlight` 只发布、自己的列表从没读，S4 把我们的列表接上后实测记牌器行高亮正常（手牌 / 发现两个入口没单独看，Bug T11 在 PLAN 里留着）。

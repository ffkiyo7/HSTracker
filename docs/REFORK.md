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

分支 `dev0923`（worktree `.claude/worktrees/refork`），起点 = `3.6.12`（`c723bfd4`）。旧 `dev` 原样保留不改名，随时可回。每步验收过了才做下一步；构建 / 测试一律用 `AGENTS.md` 的受限环境命令。

| | 内容 | 验收 |
|---|---|---|
| S0 | 基线：开分支，换本地 `Config.xcconfig`，原样构建 | ✅ 09-23：受限环境失败（wget 不在 `PATH`，S1 修）；普通环境 `BUILD SUCCEEDED`；测试 151 条 150 过，唯一失败 `OfficialBuildTests.testHostAppIsRecognizedAsOfficial`（ad-hoc 签名自编译包，预期内）；`SecretTests` 全过，`96883c5b` 不用搬 |
| S1 | 构建层：部署目标 14.0（3.6.12 为 6 处 `10.15`，全改）、`Vendor/Managed` 固定 zip + 版本强校验、build phase 的 PATH / 条件代理、`update-managed-deps.sh`；BobsBuddy 升到 tag 要求的 **1.76.3**（dev 为 1.71.1；3.6.12 用到 `BobsBuddySimulationFailure` / Deity 接口）；HearthDb 重定版本，新建 `HearthDb-version.txt`（上游无此文件）并登记进 Resources 与 build phase inputs。`NET_VERSION` 上游已由 `mono-version.txt`（8.0.29）推出 `net8.0`，不再写死 | ✅ 09-23 第一批 review 过（`dev0923` `17302764`）：受限环境 `clean build` 过；版本不符构建报错；BobsBuddy 1.76.10 / HearthDb 36.6.0；DLL 放 `Contents/Resources/Resources/Managed/`（`MonoHelper.swift:434` 真正读的位置，不改 Swift；dev 放错位置，BobsBuddy 从未加载成功，日志 18 次 `Failed to load BobsBuddy`）；测试宿主启动日志已见 `Loaded BobsBuddy version 1.76.10.0`。余项：Download Mono / HearthMirror 的 wget 路径因缓存命中今天没真跑过，且 Download Mono 无 `set -e`（上游遗留），换机器首次构建时留意 |
| S2 | 翻译：`scripts/inject-zh-hans.py` 注入（对 3.6.12 干跑：注入 230 / 相同 440 / 分歧 179 / 无 zh 170）；`check_xcstrings.py` 加分隔符风格探测；179 条分歧以我们为准（09-23 用户定）；上游删掉的 3 个 catalog（`BattlegroundsSession` 43 / `BobsBuddyPanel` 16 / `LinkOpponentDeckPanel` 6，共 65 条 zh，文案已迁进 `Localizable.xcstrings` 新 key）脚本不注入，逐条对到新 key；上游新增 `ArenaPreferences`（无 zh）；`String.swift` 的 DEBUG 缺 key 警告不搬（上游 `LocalizationFormatTests` 兜底） | ✅ 09-23 第一批 review 过：17 个 catalog 只增改 zh-Hans；覆盖率 1035 / 1060（dev 967 / 981）；迁走的 65 条对上 33 条，其余 28 条是 xib 占位、4 条无对应 key；校验器加分隔符探测，验收命令须带 `--allow-zh-edit`（195 条是有意覆盖上游 zh）；🖥️ 设置页中文正常。**dev 的 `Localizable` 有 53 条带译文的 fork key（`session_recap_*` / `tracker_*` / `Zone_*` 等）没进来，S3–S6 搬对应代码时一起补，否则显示英文**。余项归 S6：3.6.12 新增、界面会显示却无 zh 的 9 个 key（`Secret_Helper` 可用旧线 `tracker_secret_helper`「显示奥秘助手」、`Overlay_Layout`、`Overlay_Layout_Section_Order`、`Enum_DeckPanel_Graveyard`、`CardTile_Drawn_By`、`No minions on board`、`ArenaPreDraft_Panel_Title`、`aberration`、`BE`）；「套牌 / 卡组」混用 8 处待统一；校验器 E2 改成按 baseline 的风格比（现为四种风格任一即过，会放过风格被换） |
| S3 | 分区数据层：`Fork/PlayerCardZones.swift`、`Entity` / `TagChangeActions` 的洗入闩、全部 fixture 和分区测试；把 `Player.game` 放宽，余下约 40 行（含 Perf P1 的 `playerTrackerSnapshot` / `playerCardList(deckState:sideboards:)` / `playerCardGroups`）一并搬出；`Card.copy()` 补拷 `enText`（`9ab2f0cd`，3.6.12 仍漏）；`RealmHelper.needsCardCountFix`（Perf P1） | ⬜ `CardZoneGroupsTests` + `ZoneGroupsReplayTests` 全绿；`Player.swift` 相对 tag 的改动 ≤15 行 |
| S4 | 面板上画布：`UIs/Trackers/SwiftUI/` 整目录 + 位图缓存搬入。上游不是单点：`RootOverlayView:571/575` 两个 `TrackerPanelView(viewModel:canvasSize:isLocked:hoverHandler:)`，绑着 `TrackerCardHoverHandler`（卡图预览 / 协同高亮）、`InteractiveRegion` / `HoverRegion` 上报（画布不接鼠标，拖拽 / 缩放只在上报区生效）、`TrackerGraveyardDetailsView`、位置设置（`player_deck_top/left/height`、`overlay_player_scaling`、`deck_panel_order_player`、`overlay_center_player_stack`）+ `migratePlacementIfNeeded`、`TrackerDeckLensView`（`2747763e`）。**外壳用 A（09-23 用户定）**：保留上游 `TrackerPanelViewModel` / `TrackerPanelView` 当外壳（位置、拖拽缩放、悬停区、坟场详情、lens 白拿），只把卡牌列表换成我们的；框的位置 / 大小走上游设置，框内行高压缩沿用我们的算法。否决 B（整个换成我们的，上述全部自己重接）。`Game` 三处 `tracker.update(cards:…)`（`:303/341/406`）旁多传分区，Perf P1 的 `updateTrackers` 单次取数一并带上 | ⬜ `TrackerMetricsTests` 全绿；🎮 一局：外观与 dev 一致、分区正确、不掉帧、拖拽 / 锁定可用；高亮在 3.6.12 上重看（G1 结论不能直接套） |
| S5 | 刷新合并（`scheduleGuiUpdate` / `runGuiUpdate`）+ 3 处埋点 + `Utility/LatencyProbe.swift` 本体 + scheme 的 `HSTRACKER_LATENCY_PROBE` + `tracker_perf_*` 诊断键；`WindowManager.show` 同值不写（Perf P1）、`SizeHelper` AX 读挪后台 + `UnfairLock`（T3）逐段看 3.6.12 还适不适用；`ImageUtils` 的 LRU / 后台解码先看上游现状（3.6.12 仍无 LRU）再决定搬不搬，动了就顺手加负缓存 | ⬜ 与 S4 同一局复测不掉帧；悬停卡图无顿挫 |
| S6 | 小件，逐个先查上游有没有：排队显示牌组 + 清上一局残留、局末小结、Dock 打勾 + Toast、菜单栏按 tag 定位（4.2 `35fea72a`；3.6.12 `AppDelegate` 仍 7 处 `item(withTitle:)`，中文界面失效）、`HSReplayPreferences` 标题本地化、`Power.log` 截断修复（3.6.12 已重写 `LogReader` 截断逻辑，要重做不能 apply）、Bug T1 watcher 回主线程（`ac116be0` 7 条；3.6.12 只修了高亮一条，`isViewingTeammate` `Watchers:267`、`setBaconState`、`setDeckPickerState`、`choicesVisible` 仍后台写）、默认值差异表（`show_mulligan_toast` 等）、Trackers 设置页（上游有新的 Overlay layout 页和 Related Cards 页 `a95c4b1f`，倾向用上游的） | ⬜ 每项一句话核对结论；🎮 排队 / 退出炉石各看一次 |
| S7 | 红龙：`HSTracker/RedDragon/` + `RedDragonTests` 原样拷入，连同 `CardIds/Rogue.swift`（+13）/ `Neutral.swift`（+3）新增常量（3.6.12 全无，不带编不过） | ⬜ `RedDragonTests` 全绿 |
| S8 | 切换：`dev0923` 推到 origin 成为工作分支（旧 `dev` 不动，作回滚点）；`AGENTS.md` 工作分支改名；重写 `docs/upstream-merges.md` 热点表 | ⬜ `origin/dev0923` 为新线 |

## 不搬的东西

- `Tracker.swift` / `CardHud.swift` 里的记牌器窗口层改动（上游已删文件）；`WindowManager` / `SizeHelper` 的窗口层改动随之作废，但其中的性能改动归 S5 逐段核对
- `useSwiftUITracker` 开关和 AppKit 旧路径；Phase 5「计数器可拖动」（上游 `0b8dfd16` 已做）
- BLACK_MARKET 崩溃修复、翻译回退修复（上游 `f5641f98` / `a2ac19fc` 已做且更完整）；`Mode.fromMirror` + `EnumTests.testModeFromMirrorToleratesUnknownOrdinals`（上游 `Mode.allCases[safeIndex:]` 已覆盖，拷测试会红）
- Tier7 pre-lobby 旁路修复 `eb52832e`（3.6.12 已删该文件，由 `Game.updateTier7PreLobbyVisibility()` 接管）
- 卡池浮窗串卡修复 `dbdab593`（3.6.12 用 `.id(imageIdentity)`，含 `baconCard`，更强）
- 自编译包不上报 Sentry / Mixpanel：上游 `920aa5f2` / `132538ac` 按 bundle id + team id 自动关，无需处理
- `[T11]` 诊断日志；`ab/*` 分支

## 回到主线的标准

1. S0–S8 全部 ✅。
2. 🎮 收口局一次过：外观 = dev、分区账正确、不掉帧、Bug T11 两条症状复查（高亮链路已换成上游的，要重新看）。
3. 测试全绿，条数 ≥ 上游自带 + 我们的分区 / 面板 / 红龙测试。
4. `git diff <tag> --stat -- HSTracker` 里被我们改过的**上游文件 ≤15 个**，其余都在 `Fork/`、`RedDragon/`、`UIs/Trackers/SwiftUI/`、`UIs/SessionRecap/`。

之后的主线：Phase 2 / V2 余项（折叠、拖拽吸附、套牌名截断）→ Phase 4 / 4.3 其余设置页 → 红龙 T2 overlay。
T8 动效已在 dev 上做完（`UIs/Trackers/SwiftUI/` 内，S4 整目录带走），09-23 卡点 ④ 已过。

## 未决

- G1 实测带出两条上游现象（2026-09-21，上游原样包，commit 未记录）：① 卡条很小、上下的框很大 —— 面板换成我们的之后不存在，S4 验收时顺带确认；② **相关卡牌高亮在上游包里同样不亮** —— Bug T11 第 2 条症状不是我们的回归，S4 接高亮时在 3.6.12 上从上游链路查起。

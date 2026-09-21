# 在上游新画布上重建 fork

上游 3.6.11 之后把 overlay 重写成单一 SwiftUI 画布（`RootOverlayWindow`），`Tracker.swift` / `CardHud.swift` /
`WindowManager` 窗口层已删。不再 merge，改为从上游新 tag 开分支、只搬值得留的东西。
每步由 Opus 子代理按薄任务书执行，Claude review 后提交。状态符号见 `AGENTS.md`。

## 开工卡点（全部满足才开分支）

| | 卡点 | 状态 |
|---|---|---|
| G1 | 🎮 上游原样包（`.claude/worktrees/upstream-probe`）实战一局不掉帧；若卡，关掉双方记牌器即恢复也算过 | ✅ 2026-09-21「一点都不卡」 |
| G2 | 上游发出包含 `b2209e9a` + `6a57ae0f`（记牌器上画布）的 tag，预计 3.6.12 | ⬜ |
| G3 | dev 减负三片已提交（`d309a8ff` / `7c0f2390` / `892873de`），工作区干净 | ✅ 2026-09-21 |

G1 不过（关掉记牌器仍卡）→ 停，改评估「冻结 3.6.9 + cherry-pick」路线。

## 步骤

分支 `refork`，起点 = G2 的 tag。每步验收过了才做下一步；构建 / 测试一律用 `AGENTS.md` 的受限环境命令。

| | 内容 | 验收 |
|---|---|---|
| S0 | 基线：开分支，换本地 `Config.xcconfig`，原样构建 | ⬜ `BUILD SUCCEEDED`，上游自带测试全绿，记下条数 |
| S1 | 构建层：部署目标 14.0、`Vendor/Managed` 固定 zip + 版本强校验、build phase 的 PATH / 条件代理、`update-managed-deps.sh` | ⬜ 受限环境 `clean build` 过；增量构建只改 `BobsBuddy-version.txt` 时包里 DLL 跟着变 |
| S2 | 翻译：`scripts/inject-zh-hans.py` 注入；`check_xcstrings.py` 加分隔符风格探测；179 条术语分歧定取舍 | ⬜ 校验器通过；🖥️ 设置页中文正常 |
| S3 | 分区数据层：`Fork/PlayerCardZones.swift`、`Entity` / `TagChangeActions` 的洗入闩、全部 fixture 和分区测试；把 `Player.game` 放宽，余下约 40 行一并搬出 | ⬜ `CardZoneGroupsTests` + `ZoneGroupsReplayTests` 全绿；`Player.swift` 相对 tag 的改动 ≤15 行 |
| S4 | 面板上画布：`UIs/Trackers/SwiftUI/` 整目录 + 位图缓存搬入；在 `RootOverlayView` 单点替换上游 `TrackerPanelView`；`Game` 在 `tracker.update(…)` 旁多传分区；悬停 / 高亮接上游的 frame 路由 | ⬜ `TrackerMetricsTests` 全绿；🎮 一局：外观与 dev 一致、分区正确、不掉帧、拖拽 / 锁定可用 |
| S5 | 刷新合并（`scheduleGuiUpdate` / `runGuiUpdate`）+ 3 处埋点；`ImageUtils` 的 LRU / 后台解码先看上游现状再决定搬不搬 | ⬜ 与 S4 同一局复测不掉帧；悬停卡图无顿挫 |
| S6 | 小件，逐个先查上游有没有：排队显示牌组 + 清上一局残留、局末小结、Dock 打勾 + Toast、`Power.log` 截断修复、默认值差异表（`show_mulligan_toast` 等）、Trackers 设置页（上游有新的 Overlay layout 页，倾向用上游的） | ⬜ 每项一句话核对结论；🎮 排队 / 退出炉石各看一次 |
| S7 | 红龙：`HSTracker/RedDragon/` + `RedDragonTests` 原样拷入 | ⬜ `RedDragonTests` 全绿 |
| S8 | 切换：旧 `dev` → `backup/dev-pre-refork`，`refork` → `dev`；重写 `docs/upstream-merges.md` 热点表；PLAN / PROGRESS 合并成一份 | ⬜ `origin/dev` 指向新线；删 `upstream-probe` worktree |

## 不搬的东西

- `Tracker.swift` / `WindowManager.swift` / `CardHud.swift` / `SizeHelper` 里的记牌器窗口层改动（上游已删对应代码）
- `useSwiftUITracker` 开关和 AppKit 旧路径；Phase 5「计数器可拖动」（上游 `0b8dfd16` 已做）
- BLACK_MARKET 崩溃修复、翻译回退修复（上游 `f5641f98` / `a2ac19fc` 已做且更完整）
- `[T11]` 诊断日志；`ab/*` 分支

## 回到主线的标准

1. S0–S8 全部 ✅。
2. 🎮 收口局一次过：外观 = dev、分区账正确、不掉帧、Bug T11 两条症状复查（高亮链路已换成上游的，要重新看）。
3. 测试全绿，条数 ≥ 上游自带 + 我们的分区 / 面板 / 红龙测试。
4. `git diff <tag> --stat -- HSTracker` 里被我们改过的**上游文件 ≤15 个**，其余都在 `Fork/`、`RedDragon/`、`UIs/Trackers/SwiftUI/`、`UIs/SessionRecap/`。

之后的主线：Phase 1 / T8 记牌器动效 → Phase 2 / V2 余项（折叠、套牌名截断）→ Phase 4 / 4.3 其余设置页 → 红龙 T2 overlay。

## 未决

- 179 条 zh-Hans 术语分歧：保留我们的「套牌 / 竞技模式」，还是用上游的再单独修词（S2 前定）。
- G1 实测带出两条上游现象（2026-09-21，上游原样包）：① 卡条很小、上下的框很大 —— 面板换成我们的之后不存在，S4 验收时顺带确认；② **相关卡牌高亮在上游包里同样不亮** —— Bug T11 第 2 条症状不是我们的回归，S4 接高亮时从上游链路查起。

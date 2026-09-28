# 上游 3.6.13 评估（归档原文）

原在 `docs/REFORK.md`「上游 3.6.13 评估」，09-26 写，09-29 合入（Phase U4）后整段挪来。结果与勘误见 `docs/upstream-merges.md` §4 U4：干跑说的 3 处冲突都按下表解了，多出一处没预见的 —— 上游 pin 的 HearthMirror `1a6012b5` 在 CDN 上 404，留 `912e88ea` + shim。

---

## 上游 3.6.13 评估（09-26，tag `41f89c04`，09-24 发布）

新线基座是 3.6.12，3.6.13 是增量（110 文件 +4377 / −520，无 overlay 重写），**走 merge 而不是再开分支**，手册 `docs/upstream-merges.md`。干跑 `git merge-tree --write-tree dev0923 3.6.13` 只 3 处冲突：

| 冲突 | 怎么解 |
|---|---|
| `project.pbxproj` | 上游删了 `Preferences` Swift 包（`Package.resolved` −9），新增 `PreferencesWindowController` / `PreferencePane` / `CountersPreferences` / `BoardOrderView(Model)` / `RewoundEntityCreationFilter` 等文件登记；我们的登记照 §1 规则合 |
| `BobsBuddy-version.txt` | 上游 1.76.3 → **1.78.2**（Volumizer 增益），我们固定 1.76.10；按 §2.2 用 `scripts/update-managed-deps.sh` 重新 vendor，HearthDb 一起换 |
| `LogReaderManager.swift` | 上游加 `logPath` / `ignoredTimeRanges` / `requestStop()` + `processLine` 开头的 rewind 跳过；我们加 `removeLogfile: !Settings.keepPowerLog`、`stop` 的 `keepPowerLog` 例外、`LatencyProbe.logLineStarted`。两边都留，探针放在 rewind 跳过之后（跳过的行不算延迟） |

自动合并但双方都改过、要人工过的：`Game.swift`（上游 +123：`gameTime == nil` 门加在 `updateOpponentTracker` / `updatePlayerTracker` 开头 —— 正是我们 S4 传分区的三处；`reset(updateUI:)`；`boardOrderCounter`；战棋 minion pool）、`TagChangeActions.swift`（上游删 `drBoomsMonsterRebornHealth`、`zoneChange` 里加 `updateBoardOrder`；我们在同一 `case .zone` 后加 `updateZoneLatches`，顺序不冲突）、`Entity.swift`（`copy()` 上游加 `boardOrder`，我们加两个闩）、`AppDelegate.swift`（上游 `MonoHelper.start()` 后台起 BobsBuddy + 设置窗改 groups 初始化；我们的菜单 tag / Dock 在别处）、`Localizable.xcstrings`（上游 +675 行）。

要重点核的：**rewind**（`fba088ca` / `eb4deaad` / `577e5b25`）会 `reset(updateUI: false)` 后重读日志，我们的 `wasShuffledIntoDeck` / `wasSetAsideAtSetup` 闩挂在 `Entity` 上，随 `entities` 清空一起重建，理论上无事，但要一局带 rewind（半稳定传送门）实测或看 `RewoundEntityCreationFilterTests` 能否加分区断言。`HearthMirror-version.txt` 变了 → 必须 `clean build`。

对我们计划的影响：
- **Phase 4 / 4.3 基本被上游做掉**：设置窗改成侧栏分组 + 搜索（`PreferencesWindowController` 471 行新写，`ccc9e8c4`），新增 Counters 页（每个计数器 总是 / 从不 / 相关时 显示，`f7fde96e`）。4.3「其余 8 页」撤，Trackers 页只补 fork 自有开关（`keep_power_log`、`show_constructed_session_recap`、分区开关）。
- 翻译：`Localizable` 新增 13 key（全有 zh-Hans）+ 改 1；`TrackersPreferences.xcstrings` 新增 2 key（有 zh）。**上游这版自带 zh-Hans**，合完只需 `check_xcstrings.py --baseline dev0923 --allow-zh-edit` 确认没被还原。
- S6b 的 `Watchers.swift:217` arena `main.sync` 上游未改，仍留 S6b。
- 上游 `883be52e` BobsBuddy 改后台启动（`MonoHelper.isReady`），我们 S1 的 DLL 路径 `Contents/Resources/Resources/Managed/` 不受影响（`MonoHelper.load()` 路径未动）。
- 新功能顺带得到：场上随从入场序号（`show_board_entry_order`，构筑可用）、启动更快（`ReflectionHelper` 读 Swift 元数据 `a7447ac7`）、rewind 不闪。战棋部分（minion pool / Dark Paradox / Duos）只静态确认。

**时机（等用户定）**：解锁复测 09-27 已过，剩 ① S8 切换前先合（切换时新线已含 3.6.13）；② 先 S8 切换，再合 3.6.13 作为新线第一次 merge（`upstream-merges.md` 热点表先按新线重写，合并时有表可对）。→ 用户 09-29 定 ②。

# 进度

> 计划全文见 `docs/PLAN.md`。本文件只记录**做到哪了 / 下一步是什么**，每完成一项就更新。

**最后更新**：2026-08-19
**分支**：`phase0+3`（基于 `master` = upstream `77a85be2` / **3.6.5**）—— 原名 `perf/phase0-overlay`；后续阶段落地后再改名
**构建状态**：合并 3.6.5 后**尚未重新构建**（3.6.4 基线上是 Debug `BUILD SUCCEEDED`）
**当前卡在**：等待人工游戏内实测（Phase 0 效果验证）—— Phase 3 已完成，不阻塞它

**已跟上游 3.6.5**（2026-08-19）：`git merge master` 无冲突，两处重叠文件（`Game.swift` / `project.pbxproj`）
自动合并且两边改动都保留。3.6.5 对齐炉石 36.2.2（卡牌数据 248348 → 249896、BobsBuddy 1.57.6 → 1.62.1），
修了 Duos 里 Sandy 的崩溃，新增 Eternal Knight / Ancestral Automaton 两个战棋计数器。
**不产生新的本地化欠账** —— 3.6.5 没碰任何 `.xcstrings`，新文件里也没有用户可见文案。
顺带一提，上游 `89548845` 把 mirror 读取从 `currentGameType` 的 getter 里挪走了，和 Phase 0 同向。

---

## 状态总览

| 阶段 | 内容 | 状态 |
|---|---|---|
| T0 | 前置环境 | ✅ 完成 |
| T1 | `WindowManager.show()` 去抖 | ✅ 完成并 review |
| T2 | AX 调用移出主线程 | ✅ 完成并 review |
| T3 | 提高 tick 频率 + 跟窗 | ✅ 完成并 review（review 时加了一处设计改动） |
| — | **游戏内实测** | ⏸ **待办 —— 下一步就是这个** |
| T4 | 部署目标 → macOS 14.0 | ⬜ 未开始（**刻意压后到实测之后**） |
| Phase 1 | SwiftUI 记牌器渲染 | ⬜ 未开始 |
| Phase 2 | 记牌器分区（牌库/手牌/已打出） | ⬜ 未开始（依赖 Phase 1） |
| Phase 3 | 补全简体中文 | ✅ 完成并 review（未译 410 → 7，99.2%） |
| Phase 4 | 设置 UI + Dock 菜单 | ⬜ 4.1/4.2 可随时开始；**4.3 被 T4 阻塞** |

---

## 已完成的提交

```
a89fce6d  Record the T2/T3 window-polling interaction found on review
330ef0e8  Raise overlay tick to 10Hz and decouple window polling        ← T3
c6bab26f  Keep Hearthstone window Accessibility reads off the main thread ← T2
45d36c47  Only reassign overlay window properties when they change      ← T1
a7c1aaf2  Add Phase 0 plan and grok task books under docs/
1ff31cb1  Fix Embed Mono build phase for mono 8.0.29                    ← T0
```

T1/T2/T3 的代码由本机 grok-4.6（`--effort xhigh`）按 `docs/tasks/` 里的任务书写成，逐个人工 review 后提交。

## Phase 3 —— 补全简体中文（已完成）

zh-Hans 覆盖率 **436/846 (51.5%) → 841/848 (99.2%)**，剩 7 个是标点/字形 key（`""` `\n` `!` `?` `✕` `i`），有意不译。

代码由本机 grok-4.6（`--effort xhigh`）按 `docs/tasks/phase3-t*.md` 六本任务书依次写成，
每步之间有自动闸（`docs/tasks/tools/check_xcstrings.py`），六步的缺失数精确命中预期（271→271→271→147→92→7）。

| 任务 | 内容 | 产出 |
|---|---|---|
| T1 | 按 key 合并 `gaenyong/HSTracker@9e7b653f` | 补 139 条；77 条译法差异写进 `docs/tasks/phase3-t1-diff-report.md` |
| T2 | 清掉从不参与编译的 `.lproj/*.strings` | 删 104 个文件 / 72 个目录；可抢救译文 **0 条** |
| T3 | 修 3.3 两个"翻译了也不生效"的 bug | + `Archive`/`Unarchive` 两个 key，+ DEBUG 缺 key 日志 |
| T4 | 主 catalog `Localizable.xcstrings` | 124 条 |
| T5 | 设置窗口 6 个 catalog | 55 条 |
| T6 | 卡组/对局 4 个 catalog + 8 条"假翻译" | 85 + 8 条 |

**review 时另做了 72 处改动**（见下节）。

### 复用的外部译文

- `gaenyong/HSTracker@9e7b653f`（MIT）—— T1 的 139 条 + 采纳的 56 条差异。16 个 `.xcstrings` 已下到
  `.refs/gaenyong-9e7b653f/`（在 `.git/info/exclude` 里），合并可复现，不需要联网。
- T4 自己发现 `MulliganGV2_*` / `BattlegroundsXxx_*` / `ConstructedPreLobbyWidget_*` 与 **HDT 和 HSReplay 官方 i18n 是同一套 key**，
  按官方中文对齐 —— 这条路任务书里没写，是它自己找到的。

## 与计划不一致的地方

**T3 在 review 时改了设计。** 任务书原文写「去掉 `counter > 3`，每个 tick 都刷新窗口矩形」，按字面实现会引入一个回归：
T2 已把 `reload()` 从 `updateAllTrackers()` 里摘掉，于是 `reload()` 只剩在 `else` 分支里；日志密集时
`guiNeedsUpdate` 每拍为真，窗口矩形将长时间不刷新，overlay 被钉在旧位置 —— 比改之前更差。
这是 T2 与 T3 组合才出现的问题，单看任一任务都发现不了。

实际实现：把窗口轮询提到分支之外，并用独立的 **250ms** 阈值节流（不跟随 100ms 的 GUI tick）。
除了让两个分支都拿到新鲜矩形，也是因为每次 `reload()` 是 4 次阻塞式 AX 跨进程调用 ——
真按 10Hz 跑就是每秒 40 次打进炉石自己的 run loop，反而拖累我们想保住流畅度的那个进程。
250ms 把 AX 频率维持在接近原先的水平，同时把跟窗延迟从 ~2s 降到 ~250ms。

见 `Game.swift` 的 `windowPollInterval` / `lastWindowPoll`。

**Phase 3 的 3.2 前提是错的。** 计划说那套废弃的 `zh-Hans.lproj/*.strings` 里"有现成的中文翻译从未上线"，
可以先挖出来再删。实测挖不出东西：5 个 `Localizable.strings` 只有 5 条能对上我们缺的 key，且**全是英文原样**
（`"HSReplay" = "HSReplay";`）；`MainMenu.strings` 那 38 条全被 gaenyong 的 41 条覆盖。
更要紧的是它把 Deck 译作**「套牌」**，而现行 catalog 一律「卡组」——
`AppDelegate.swift:440` 按标题字符串找菜单项，真按计划去"挖"反而会弄坏中文下的菜单栏。
所以 T2 改成了「先证明它确实是死的 → 删掉 → 不许覆盖 T1 写的值」。

**Phase 4.2 的诊断也要修正。** 计划说合并 `MainMenu.xcstrings` 后菜单项查找会「变成中文能查到、英文查不到」。
实际不会 —— gaenyong 给 MainMenu 的译法与 `Localizable.xcstrings` 已有的**逐字相同**
（卡组 / 回放 / 最近回放 / 窗口 / 锁定窗口），所以 T1 落地后中英文两边都能查到，这个 bug **顺手被修好了**。
4.2 改成按 tag/outlet 定位仍然值得做（两个 catalog 任何一边以后重译一次就再次静默失效），
但它从「硬性前提」降级为「消除脆弱性」。

### review 时在 grok 产物之上做的 72 处改动

任务书禁止 grok 改既有译文，所以这些留给 review：

- **56 条**：采纳 `phase3-t1-diff-report.md` 里建议「采纳它」的 gaenyong 译法。值取自 `.refs/`，不取报告里的 markdown 单元格。
- **7 条**：报告里标「都不好」的，用它另拟的译法（`Fatigue : ` 的尾空格、`Show flavor text`→「显示卡牌趣闻」、
  两条 draw chance→「抽到概率」、`Arena or Brawl deck`→「竞技场或乱斗卡组」等）。
- **9 条**：我自己扫出来的 ——
  `MainMenu` 的「隐藏 其他」多一个空格（gaenyong 带进来的，macOS 系统菜单是「隐藏其他」）；
  「血量」→「生命值」×2；「友谊赛」→「好友对战」；「竞技模式」→「竞技场」×2；
  「旅店大乱斗」→「乱斗模式」；`DeckManager` 工具栏「存档」→「归档」×2（与 T3 补的 `Archive` 对齐）。

效果：跨 catalog 的术语漂移从 **37 处降到 0**（「套牌」23 处全清），
「同一英文译法不一」从 13 组降到 8 组，剩下 8 组都是有意的语境差异
（`mode_*` 系列统一带「模式」；工具栏项带宾语「删除卡组」而菜单项只写「删除」）。

另删掉 `HSTracker/TrackOBot/ko-KR.lproj/` —— T2 按规则没碰（不在任务书路径里）但报告了，同样是 0 引用的死文件。

---

## 下一步：游戏内实测

Debug 构建产物：
```
~/Library/Developer/Xcode/DerivedData/HSTracker-aqezlgillbghuralonpbmtmljzam/Build/Products/Debug/HSTracker.app
```

**测之前注意：**
1. 先退出已安装的 3.6.2，否则两个实例会同时 tail 炉石日志。
2. 这个构建是 **ad-hoc 签名**，macOS 视其为与 3.6.2 不同的 app —— 辅助功能（Accessibility）和屏幕录制权限**要单独授予**，不会继承。
3. 启动时会弹「移动到「应用程序」」对话框（`AppDelegate.swift:63` 无条件调 `AppMover.moveApp()`）——
   **选否**，否则 DerivedData 里的构建会把自己搬走。

**该看什么：**
- overlay 对游戏状态的反应从 2fps → 10fps
- 拖动/缩放炉石窗口，overlay 跟随从最长 2 秒 → 约 250ms
- 闪烁减少（`styleMask` 不再每 tick 被重写约 20 次）
- 主线程不再因 Accessibility 调用卡住

**该预期什么：**
Phase 0 完全没碰渲染层。主题 PNG 仍每次 draw 从磁盘重新解码，`AnimatedCardList` 仍每帧拆掉整棵视图树。
所以预期是「更跟手、更少抖」，**不是**「像 Firestone 一样顺」。忙碌回合里仍然发沉是**预期结果，不是失败**。

若要留对照数据：Instruments 的 Time Profiler + Core Animation FPS，重点看主线程 CPU 占用，
以及 `AXUIElementCopyAttributeValue` 是否已从主线程调用栈上消失。

---

## 环境备注（换机器或重开时需要）

1. `brew install wget` —— 两个 build phase 依赖它（下载 HearthMirror 和 Mono）。**不装必然构建失败。**
2. `Config.xcconfig` 已改为本地签名（`CODE_SIGN_IDENTITY = -`），并已 `git update-index --skip-worktree`，
   `git status` 里看不到它。换机器要重做这一步。
3. `project.pbxproj` 里 `NET_VERSION` 已由 `net7.0` 修为 `net8.0`（commit `1ff31cb1`）——
   这是修 upstream 的真实 bug，不是本地 hack。
4. SwiftLint **故意没装**。build phase 里未安装只告警、不阻塞；装了反而会给 grok 的验收构建引入无关失败。
5. git 身份是 repo-local 配置的（`ffkiyo7 / ffkiyo7@gmail.com`），没有写进 global。

## 待办清单里还欠的

- `docs/tasks/` 现有 Phase 0 和 Phase 3 的任务书。Phase 1 / 2 / 4 若也要交给 grok，需要按同样颗粒度另写。
- Phase 1 不建议整块丢给 grok —— 它按任务书执行很稳，但不会替你发现任务书本身有问题（T3 就是例子）。
- **Phase 3 遗留（都不阻塞任何事）：**
  1. `LadderTab` / `StatsTab` 有 16 条 zh-Hans 是 `Text Cell` / `Table View Cell` 这类 XIB 占位，
     gaenyong 拿英文原样填的。用户看不见，但它让覆盖率数字虚高。撤掉会让这两个文件永远显示"未翻译"，所以留着。
  2. `Base.lproj/` 里还躺着 6 个同样没被 pbxproj 引用的 `Localizable.strings`。
     意味着 `String.localizedString` 那条 "Base.lproj 回退" 分支永远取不到东西 —— key 不存在时只会原样返回 key。
     没删是因为 `Base.lproj` 是活目录（有在用的 `.xib`），混着删风险大。
  3. `HSReplayPreferences` 有几条旧译和英文对不上（`My Account`→「上传收藏」），双方 catalog 都没有更好的版本，
     需要人肉重译。
- **Phase 4 的前置**：4.3（SwiftUI 重做设置页）依赖 T4（部署目标 → macOS 14.0），而 T4 被压在游戏内实测之后。
  4.1 / 4.2 不依赖任何东西，随时可做。

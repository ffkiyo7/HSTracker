# HSTracker 个人分支：计划与进度

最后更新 2026-10-04。本文件是唯一的计划 + 进度文档（原 `PLAN.md` / `PROGRESS.md` 全文归档在
`docs/archive/plan-2026-09-22.md` / `progress-2026-09-22.md`，决策理由、实测数据、排查经过都在那里）。
主线换轨见 `docs/REFORK.md`；上游合并见 `docs/upstream-merges.md`；任务书在做的放 `docs/tasks/`，完成的放 `docs/archive/tasks/`。

## 目标与现状

`HearthSim/HSTracker` 的个人自用 fork，不回流上游。当初的四个问题：

| 问题 | 现状 |
|---|---|
| Overlay 不跟手 / 卡顿 | ✅ 渲染层已换 SwiftUI（Phase 1），刷新改 16ms 防抖（Phase 0）；延迟不是 KPI（见「仍作数的决策」） |
| 记牌器 30 张平铺 | ✅ 牌库 / 手牌 / 已打出三段（Phase 2 / T1 + Bug T6–T11），视觉重做 V1 / V2a / V2b |
| 简体中文没翻全 | ✅ 945 / 945 |
| 设置粗糙、Dock 菜单没反应 | 🟡 Dock ✅；设置只重做了 Trackers 一页 |

分支 `dev0923`，基座上游 **3.6.13**（`41f89c04`，2026-09-29 Phase U4 合入；09-23 REFORK 从 3.6.12 换轨）；旧线 `dev`（基座 3.6.9）冻结作回滚点。`master` 是上游纯镜像（已 ff 到 3.6.13）。
测试：基线 **324 条，只挂签名 1 条**（`OfficialBuildTests.testHostAppIsRecognizedAsOfficial`，自编译包预期内；U4 合并，2026-09-29，受限环境，`-skip-testing:HSTrackerTests/LocalizationFormatTests`）。

## 阶段总览

| 阶段 | 状态 | 依据 |
|---|---|---|
| Phase 0 地基（驱动循环 / 窗口层 / 部署目标 14.0） | ✅ T0–T6 | T6 于 08-31 收在测量阶段，不做延迟优化 |
| Phase 1 SwiftUI 记牌器 | ✅ 8 / 8 | T1–T7 实战（卡点 ①②③）；T8 动效 `2e9713b5`，09-23 卡点 ④ 通过（120 fps 录像零掉帧；数据在 `docs/archive/tasks/phase1-t8-tracker-motion.md`） |
| Phase U / U2 / U3 / U4 合上游 3.6.7 / 3.6.8 / 3.6.9 / 3.6.13 | ✅ | `docs/upstream-merges.md`；U4 09-29：HearthMirror 留 `912e88ea` + `Fork/HearthMirrorMinionPoolShim.swift`（上游 pin 的 `1a6012b5` CDN 404），撤法在 §4 U4 |
| Phase 2 分区 + 视觉重做 | 🚧 | T1 分区 `1c44b212`；Bug T6 `e9a67db6` / T7 `7bd3192b` / T8+T9 `68ccc14e` / T10 `04dae47a` / T11 护栏 `f8fa4c86`；V1 `e3797ba8`；V2a+V2b `1745adfa`；Perf P1+P2 `143db6f3`；2.7 状态图标 + 套牌外的牌进已打出 `7dbc86b1`（10-04 用户确认提交，任务书归档 `docs/archive/tasks/phase2-27-status-icons.md`）。**余：V2 折叠 + 拖拽吸附 + 套牌名截断、2.6 高亮加强** |
| Phase 3 简体中文 | ✅ | 945 / 945；动 `.xcstrings` 必须过 `docs/tasks/tools/check_xcstrings.py --baseline <ref>` |
| Phase 4 设置 + Dock | 🟡 | 4.1 Dock 打勾 + Toast、4.2 菜单栏改 tag 定位 ✅ `35fea72a`（S6a 已搬新线）；4.3 **其余 8 页 ❌ 撤**：上游 3.6.13 把设置窗改成侧栏分组 + 搜索并新增 Counters 页（见 REFORK「上游 3.6.13 评估」），合入后只补 fork 自有开关（`keep_power_log` / `show_constructed_session_recap` / 分区）进 Trackers 页 |
| Phase 5 计数器可拖动 | ❌ | 上游 `0b8dfd16` 已做，REFORK 不搬 |
| Phase 6 排队显示牌组 | ✅ | 08-30 实战；入口 `Game.isDeckTrackerQueue`（Bug T4 补 `isInMenu` 门） |
| Phase 7 局末小结窗 | ✅ | 09-11 实战；钩子 `CoreManager.appTerminated`，开关 `show_constructed_session_recap`（默认开，**设置 UI 留 4.3**） |
| 收尾（删 `useSwiftUITracker` 与旧路径） | ❌ | 被 REFORK 取代：旧路径随重建消失 |
| 红龙贼 combo 提示器 spike | ⏸ | T0 + T1 已提交 `0a921d6b`（`HSTracker/RedDragon/`，24 测试）；恢复点 `docs/research/red-dragon-rogue-spike.md` 第九节第 5 条；REFORK S7 原样搬 |
| **REFORK**：在上游新画布上重建 | 🚧 | `docs/REFORK.md`；新线 `dev0923`（09-30 起主仓库直接 checkout）。S0–S5、S6a、S7 ✅（09-26 实测，S4 的解锁复测 09-27 过）；S6b ✅ 09-28 四本一批（`a8e59f43` / `2618be4b` / `b12ead8c`）同日实测过，09-29 Codex 打回小结窗两条必修 `7312c31c` 修复、09-30 实测过；S8 ✅ 09-29：文档 / `AGENTS.md` / 代理定义 / 注入脚本搬上新线，`upstream-merges.md` 热点表按新线重写，`dev0923` 推到 origin；3.6.13 ✅ 09-29 合入（Phase U4），09-30 实测过（排队牌组、rewind 分区）。**余：REFORK「S6b 余项」（Trackers 设置页 = 4.3）+「回到主线的标准」第 2 条收口局** |

**顺序**：Phase 2 / V2 余项 → 4.3 fork 开关补进上游设置页（3.6.13 已合，可做）→ 红龙 T2 overlay。

## 🎮 待你亲自看

| 项 | 看什么 | 备料 |
|---|---|---|
| 🖥️ HearthMirror `1a6012b5` 上线 | `curl -I https://libs.hearthsim.net/hstracker/1a6012b545ba7af09afc14da3cd8286986c996f1/HearthMirror.framework.zip` 变 200 就撤 shim（撤法在 §4 U4） | 不开炉石 |
| 🖥️ `LocalizationFormatTests` 挂住 | 受限环境跑 `xcodebuild test` 时到这组就不动（>10 分钟），疑似桌面访问授权弹窗；你在本机跑一次 `-only-testing:HSTrackerTests/LocalizationFormatTests` 看有没有弹窗，点允许 | 不开炉石 |
| Bug T10 | 两张的牌抽走一张后数字框 2 → 1；手牌段行数 = 段头数字 | 一局 |
| Bug T11 | ① 再见「被炸的牌还在牌库」时记牌名 / 段数字 / 已打出段有无；② 高亮三入口（记牌器行 / 手牌 / 发现）哪个不亮 —— **上游原样包也不亮**（REFORK 未决），从上游链路查；09-26 新线实测记牌器行高亮正常（S4 接上了上游只发布没人用的 `deckHighlight`），手牌 / 发现两入口未单独看 | 一局 |
| Phase 2 / 2.6 高亮加强 | 只能在炉石背景上看 | 弑君者之类关联卡 |
| Phase 4 / 4.3 Trackers 页 | 🖥️ 设置窗口中英文各一遍 | 不开炉石 |

战棋不作为验收手段（用户不玩），只做静态确认。

## 等你定

- **V2 余项**：折叠 / 拖拽 / 吸附共用一个鼠标模型（不锁定 + 边缘吸附 + 锚点持久化，已决 09-15，细节在 `docs/tasks/phase2-v-visual-redesign.md`）；三行头 40 → 21 实机看。
- **卡条行高一局之内会变**（上游行为，行高按当前行数压缩）：V1 已让宽度跟着缩；是否改成固定行高 + 滚动 / 截断，用户说优先级不高。
- Phase 7 要不要回看历史会话（首版没做）。
- 「高亮手牌」在分区模式下是否强制关；备牌浮窗要不要受「显示相关牌」开关管（现在不受，dev 同）。

## 已知问题（未修）

| 问题 | 根因 / 位置 | 归属 |
|---|---|---|
| Discover 开着时悬停记牌器，OutFinder 池消失 | 备牌浮窗与 OutFinder 共用 `RelatedCardsTooltipPanel.shared`；`DiscoverStateWatcher` 只在状态变化时回调 | REFORK S4 接上游悬停路由时解决 |
| 段头折叠箭头只画不点 | V2a 画了 chevron，折叠未实现 | V2 余项 |
| 3.6.12 新增 `Watchers.swift:217` arena `main.sync`，停日志读取时主线程最多卡 5s | 上游问题，3.6.13 未改 | S6b |
| 测试宿主启动约 0.2s 崩一次，xcodebuild 自动重启后全过，但退出码 65 | 上游 3.6.13 `AnomalyGuideMulliganTriggerView.swift:78` 解包 nil 的 `coreManager`（由 `RootOverlayView.swift:550` 触发）；09-30 2.7 核对时发现 | 看测试结果以条数为准，别只看退出码 |
| 「只换顺序 + 一次张数变化」的刷新会滑一下重排 | T8 判定只看 id 和张数 | 🎮 后看要不要收 |
| 坏 tile 反复重试下载（`ETC_206e` / `EDR_979e2`） | `ImageUtils` 没有负缓存 | 谁动 `ImageUtils` 顺手加 |
| `.activateIgnoringOtherApps` 被 macOS 14 忽略 | `AppDelegate.swift:257`、`NSAlert.swift:28`、`CoreManager.swift:446` | 留意 alert 会不会被压在炉石后面 |
| `CGWindowListCreateImage` deprecated | `SizeHelper.swift:236` | 可迁 ScreenCaptureKit，不急 |
| `PreferencePaneController.swift:21` 注释「10.14 所以 icon 用 PDF」已不成立；`README.md:9` 写 10.10 | 上游文案 | 不改，避免冲突 |
| Phase 3 遗留：`LadderTab` / `StatsTab` 16 条 XIB 占位译文虚高；`Base.lproj/` 6 个未引用的 `Localizable.strings`；`HSReplayPreferences` 几条旧译对不上 | — | 不阻塞 |

## 与上游的默认值差异

合并上游时最容易被静默还原，每加一条记这里：

| 键 | 上游 | 本 fork | 说明 |
|---|---|---|---|
| `show_mulligan_toast` | true | **false** | 留牌时右下角 HSReplay 引流浮窗；留牌指南本身不受影响 |
| `use_swiftui_tracker` | — | false（本机 defaults 置 1） | 开发期 A/B 开关，REFORK 后消失 |
| `group_cards_by_zone` | — | true | 分区 |
| `hide_all_trackers_when_not_in_game` | 控件在 | **控件已撤**（`35fea72a`），声明保留给老 defaults | Bug T4 / T5 改走场景门后无读者 |
| `show_constructed_session_recap` | — | true | Phase 7 |
| `tracker_motion`、`tracker_perf_*` | — | 诊断键，不进设置页 | T8 / Perf P2 |

合并还要保住：`project.pbxproj` 的 `NET_VERSION = net8.0`（3.6.12 起上游由 `mono-version.txt` 推出，同值）与 `MACOSX_DEPLOYMENT_TARGET = 14.0`（dev 4 处，另 2 处 10.12；3.6.12 为 6 处 10.15，REFORK S1 全改）；`Card.copy()` 补的 `enText` 拷贝（上游漏拷，查表拿到的卡 `enText` 为空）。

## 仍作数的决策

- **延迟不是 KPI。** Phase 0 / T6 四轮测量（口径 → Release 基线 → 拆 D → 拆补集）没有降一毫秒后主动收口：唯一像延迟的反馈实为 `highlightCardsInHand` 行为；A 段 ~150ms 是炉石写盘节奏；以后动延迟先拿用户反馈立项。数据与排除法结论见 `docs/archive/progress-2026-09-22.md`「延迟实测」。唯一留下的候选「合并 18 次主队列投递」以帧一致性立项，落到 REFORK S5。
- **探针** `HSTRACKER_LATENCY_PROBE=1`（Release 包读 `~/Library/Logs/HSTracker/hstracker.log`）。口径：A 日志时间戳 → `processLine`；B → `guiNeedsUpdate` 置位；C → tick 消费；D `updateAllTrackers()` → UI 提交完成。D 的终点靠两级 main marker，刷新路径里再嵌两层 `async` 会静默低估。REFORK 后埋点收到 3 处（`7c0f2390`）。
- **T5 防抖的两个不变量**：不是 trailing-edge（第一个请求排一次、窗口内只置标志）；`guiUpdateInFlight` 不可去。
- **两个阶段的 T6 同名**，引用写全「Phase 0 / T6」「Phase 1 / T6」。
- **视觉验收只认实机**：改视觉的一律 🎮，2.6 只能在游戏背景看，2.8 只有全屏才作数。
- **Firestone 不做卡条动画是选择**（transition 注释掉修 flicker）；HDT 的三段 storyboard 是我们 T8 的参照，时长减半、数字立即更新。调研在 `docs/research/`。
- **T8 动效常量定稿**（09-23 卡点 ④）：`TrackerMotion.swift` 塌陷 0.28s / 闪光 0.4s / 峰值 0.38；离场行只塌陷不闪（收敛性取舍）；行高不动画、压缩态一律瞬切；诊断键 `tracker_motion` + 系统「减弱动态效果」都能关。

## 操作备忘

- Debug 包：`open ~/Library/Developer/Xcode/DerivedData/HSTracker-cgfkydaatbcvlygsoujdqwiezsjx/Build/Products/Debug/HSTracker.app`（DerivedData 目录按 `.xcodeproj` 路径分；worktree 时期的 `HSTracker-gpzxozpoxxwadygwnfkovyqpczcw` 已是旧包，别再开）。交测前看 `Contents/MacOS/HSTracker.debug.dylib` 的时间 ≥ HEAD 提交时间（Xcode 把代码放 debug dylib，主可执行文件只是壳），不然增量 build 一次。
- 09-30 主仓库已切到 `dev0923`，worktree `.claude/worktrees/refork` 已删。回旧线：`git checkout dev`（`dev` 已于 09-30 推到 origin，`647c310d`，远端也有回滚点）。
- 掉帧分析 `docs/tasks/tools/frame_gaps.py`，跨录像对比必须加 `--busy`。
- 素材：改动前基线 `~/Movies/2026-08-20 22-21-48.mp4`；Release 对照 `~/Movies/2026-08-21 00-07-23.mp4`；掉帧对照组（HSTracker 未启动）`~/Movies/2026-08-21 00-04-08.mp4`；T5 后 `~/Movies/2026-08-22 00-31-43.mp4`；探针 dump `~/Desktop/dev/HSTracker-ab/logs/probe-2026-08-30-release-t6.txt`（现行基线）、`probe-2026-08-31-release-t6b*.txt`。
- HearthMirror 闭源，只能从 `libs.hearthsim.net/hstracker/<sha>/` 拿；上游 pin 的 sha 404 时留上一版 + `Fork/` shim（U4 先例），Download 阶段失败会先 `rm -rf` 缓存，重跑前别慌。
- 环境：`brew install wget`（两个 build phase 依赖）；`Config.xcconfig` 本地签名 + `skip-worktree`，换机器重做；SwiftLint 故意不装；git 身份 repo-local；增量包可直接交测。
- 沙箱首次跑测试会因 swiftpm 缓存无权失败，本机权限重跑；`DatabaseTests` 断言英文用 `card.enText`。
- Release 包只写 `~/Library/Logs/HSTracker/hstracker.log`；首次从 `Build/Products/Release` 启动被 AppMover 模态框挡住，点 Don't Move。排查渲染前确认包内有 `Contents/Resources/CardDefs.bin`、`Contents/Resources/Managed/`。
- build phase 的 inputs 必须覆盖真正读的东西；`Embed Mono` 整拷 `net8.0` 目录；vendored 安装阶段保留 staging → 校验 → `cp`；代理 `127.0.0.1:7890` 探到才设；`grep -c 新文件.swift project.pbxproj` 应为 3~4。

# HSTracker 个人分支：计划与进度

最后更新 2026-10-08。本文件是唯一的计划 + 进度文档（原 `PLAN.md` / `PROGRESS.md` 全文归档在
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
测试：最近一次全套 **472 条，467 通过 / 3 跳过 / 2 失败**（红龙 T4 交付，2026-10-06，受限环境）。两条失败都是老问题：签名（`OfficialBuildTests.testHostAppIsRecognizedAsOfficial`，自编译包预期内）和 `LocalizationFormatTests`（桌面访问授权，见 🖥️）。U4 合并时（09-29）的基线是 324 条。

## 阶段总览

| 阶段 | 状态 | 依据 |
|---|---|---|
| Phase 0 地基（驱动循环 / 窗口层 / 部署目标 14.0） | ✅ T0–T6 | T6 于 08-31 收在测量阶段，不做延迟优化 |
| Phase 1 SwiftUI 记牌器 | ✅ 8 / 8 | T1–T7 实战（卡点 ①②③）；T8 动效 `2e9713b5`，09-23 卡点 ④ 通过（120 fps 录像零掉帧；数据在 `docs/archive/tasks/phase1-t8-tracker-motion.md`） |
| Phase U / U2 / U3 / U4 合上游 3.6.7 / 3.6.8 / 3.6.9 / 3.6.13 | ✅ | `docs/upstream-merges.md`；U4 09-29：HearthMirror 留 `912e88ea` + `Fork/HearthMirrorMinionPoolShim.swift`（上游 pin 的 `1a6012b5` CDN 404），撤法在 §4 U4 |
| Phase 2 分区 + 视觉重做 | 🚧 | T1 分区 `1c44b212`；Bug T6 `e9a67db6` / T7 `7bd3192b` / T8+T9 `68ccc14e` / T10 `04dae47a` / T11 护栏 `f8fa4c86`；V1 `e3797ba8`；V2a+V2b `1745adfa`；Perf P1+P2 `143db6f3`；2.7 状态图标 + 套牌外的牌进已打出 `7dbc86b1`（10-04 用户确认提交，任务书归档 `docs/archive/tasks/phase2-27-status-icons.md`）。**余：固定行高 + 滚动、段头折叠（⬜ `docs/tasks/phase2-scroll-collapse.md`，10-08 定）；V2 拖拽吸附 + 套牌名截断；2.6 高亮加强** |
| Phase 3 简体中文 | ✅ | 945 / 945；动 `.xcstrings` 必须过 `docs/tasks/tools/check_xcstrings.py --baseline <ref>` |
| Phase 4 设置 + Dock | 🟡 | 4.1 Dock 打勾 + Toast、4.2 菜单栏改 tag 定位 ✅ `35fea72a`（S6a 已搬新线）；4.3 **其余 8 页 ❌ 撤**：上游 3.6.13 把设置窗改成侧栏分组 + 搜索并新增 Counters 页（见 REFORK「上游 3.6.13 评估」），合入后只补 fork 自有开关（`keep_power_log` / `show_constructed_session_recap` / 分区）进 Trackers 页 |
| Phase 5 计数器可拖动 | ❌ | 上游 `0b8dfd16` 已做，REFORK 不搬 |
| Phase 6 排队显示牌组 | ✅ | 08-30 实战；入口 `Game.isDeckTrackerQueue`（Bug T4 补 `isInMenu` 门） |
| Phase 7 局末小结窗 | ✅ | 09-11 实战；钩子 `CoreManager.appTerminated`，开关 `show_constructed_session_recap`（默认开，**设置 UI 留 4.3**） |
| 收尾（删 `useSwiftUITracker` 与旧路径） | ❌ | 被 REFORK 取代：旧路径随重建消失 |
| 红龙贼 combo 提示器 | 🚧 | T0 + T1 ✅ `0a921d6b`（REFORK S7 原样搬）。T2a 公式表全量验证 ✅ `d73f8a6`（90 案例，T2b 后通过 80 / 未验证 10；5 项待定，任务书留 `docs/tasks/rdr-t2a-formula-audit.md` 至定完）。T2b 接对局数据 + 开关 ✅ `61fbcbd`（任务书和 T2 交付清单已归档）。T2c overlay + 设置页 🖥️ `359916c`，待效果图验收 + 🎮 一局（`rdr-t2c-overlay.md`）。T3 跟手 ✅ `507d354`，10-06 实测过。T4 奶 16 + 完整公式锁定 🎮 `a3326ac`。T5 引擎全量核对 🚧 10-07 A1 / A2 / B1 / B2 已修未提交（`docs/tasks/rdr-t5-engine-audit.md`）。流程：每本由子代理实现，我读 diff，本机 Codex review 后提交 |
| **REFORK**：在上游新画布上重建 | 🚧 | `docs/REFORK.md`；新线 `dev0923`（09-30 起主仓库直接 checkout）。S0–S5、S6a、S7 ✅（09-26 实测，S4 的解锁复测 09-27 过）；S6b ✅ 09-28 四本一批（`a8e59f43` / `2618be4b` / `b12ead8c`）同日实测过，09-29 Codex 打回小结窗两条必修 `7312c31c` 修复、09-30 实测过；S8 ✅ 09-29：文档 / `AGENTS.md` / 代理定义 / 注入脚本搬上新线，`upstream-merges.md` 热点表按新线重写，`dev0923` 推到 origin；3.6.13 ✅ 09-29 合入（Phase U4），09-30 实测过（排队牌组、rewind 分区）。**余：REFORK「S6b 余项」（Trackers 设置页 = 4.3）+「回到主线的标准」第 2 条收口局** |

**顺序**：红龙 T4 复测 → 红龙 T5 引擎核对（本机做，云端没有 Swift 工具链）→ Phase 2 滚动 + 折叠（`docs/tasks/phase2-scroll-collapse.md`）→ V2 其余 → 4.3 fork 开关补进上游设置页（3.6.13 已合，可做）。

- 🚧 **红龙 T5 引擎全量核对**（`docs/tasks/rdr-t5-engine-audit.md`，结果和数字在书末）。10-07 本机核实（我 + Codex 交叉）：书里的条目全部属实。**改动在工作区，没提交、没过 Codex review。**
  - ✅ 已修：A1 抽牌线抢先收口；A2 两条束搜索漏线（`t2-wuhu-10` 补狐 80/80、`t2-wuhui-04` 补晦 64/64）；B1 扰魔；B2 剧毒。
  - ✅ Codex 另报、核实后一并修的：英雄撞随从不掉血、第二张闪避还能打、免疫随从可被指向且嘲讽挡路、敌方目标合并键撞车。
  - ⬜ 没做：A3 缺件召回、A4 G3 T9 人工核；Codex 另报的 4 条（我方圣盾 / 免疫没用上、敌方被沉默不恢复身材、冻结被沉默解不了、`dependsOnDraw` 两处抽牌同时换没验）。
  - 🎮 要复测跟手：A2 改了束，锁定的线变短（回放里 18 → 17 步、22 → 21 步），历史回放的偏离 20 → 22 次。
  - 数字：红龙组 153 条 0 失败；公式表 80 / 10 不变，齐件 53/53、缺件 27/27；单案例平均 0.202 → 0.253 s，最慢 1.77 → 1.81 s。全套 482 条，只挂两条老的（另有一条按墙钟等的锁定测试 6 次里偶发 1 次）。
  - C1 两条鲨鱼的口径，见「等你定」。
- 🎮 **红龙 T4**：10-06 用户说可以提交，`rdr-t4` 并入 `dev0923`（`a3326ac`）；三轮实测的修复里最后两批还没复测，任务书留 `docs/tasks/rdr-t4-setup-lines.md`（过程、数字、定因都在书末）。现状：
  - 斩不了且危险（对方场攻 ≥ 血量 − 5）时给奶 16 线，凑不出提示「等死」；阿莱可对我方英雄回血。
  - 揭示档只剩判定 / 顺序（L1「参与牌」、手牌 / 场面上的框和序号 10-06 用户定删）。设置选「顺序」且没开答题时给完整公式并锁定：按舞 / 幻分行，每步只核对在不在线上，殒命暗影写「步（殒）」，乐队经理写「牛（龙舞）1」（括号金色）。
  - 重算 / 过时 / 偏离时面板内容不动、只整块置灰；偏离标「已偏离，重算中」。锁定 / 偏离写 `hstracker.log`。
  - 照着打却被判偏离：45 局离线回放 49 → 17 次（余下 8 次是步目标 / 乐队发现不同，用户定算偏离；9 次零散未修）。攻击后重算卡住（10-06 14:47 实测 11 秒）已修。
  - Codex review 一轮（8 条，修 3 条，其余在「等你定」）。
  - 测试：红龙七组 145 条 0 失败 4 跳过（10-06 第二批后），之后的改动只重跑相关组（0 失败）。提交前全套（跳过 `LocalizationFormatTests`）470 条跑了 6157 秒（平时约 570 秒，当时炉石在跑、负载 5.6），挂 5 条：签名 1 条预期内，其余 4 条都是卡时间的（红龙两条「跟随 < 1 秒」实测 1.59 秒、一条等待超时，`SecretTests` 两条 2 秒等待超时）；同分支 10-06 凌晨空闲时全套只挂签名和本地化两条。**空闲时再跑一遍全套确认**。
用户验收原话（10-04）：引擎验证截图内全部公式，可反推、无错漏；齐件 / 缺件分开算；设置里可热开启；overlay 不卡顿、符合设计语言、不与已有组件冲突。

## 🎮 待你亲自看

| 项 | 看什么 | 备料 |
|---|---|---|
| 🖥️ HearthMirror `1a6012b5` 上线 | `curl -I https://libs.hearthsim.net/hstracker/1a6012b545ba7af09afc14da3cd8286986c996f1/HearthMirror.framework.zip` 变 200 就撤 shim（撤法在 §4 U4） | 不开炉石 |
| 🖥️ `LocalizationFormatTests` 挂住 | 受限环境跑 `xcodebuild test` 时到这组就不动（>10 分钟），疑似桌面访问授权弹窗；你在本机跑一次 `-only-testing:HSTrackerTests/LocalizationFormatTests` 看有没有弹窗，点允许 | 不开炉石 |
| Bug T10 | 两张的牌抽走一张后数字框 2 → 1；手牌段行数 = 段头数字 | 一局 |
| Bug T11 | ① 再见「被炸的牌还在牌库」时记牌名 / 段数字 / 已打出段有无；② 高亮三入口（记牌器行 / 手牌 / 发现）哪个不亮 —— **上游原样包也不亮**（REFORK 未决），从上游链路查；09-26 新线实测记牌器行高亮正常（S4 接上了上游只发布没人用的 `deckHighlight`），手牌 / 发现两入口未单独看 | 一局 |
| 红龙 T2c overlay | 🖥️ 先看效果图 artifact；再打一局红龙贼：面板位置对不对（手牌序号 / 场面标记 10-06 已删，不用看）、⌃⌥W/S/Q 热键、设置页开关热切换 | 红龙贼套牌，设置里开「红龙辅助」 |
| 红龙 T4 | 设置选「顺序」打红龙贼：① 可斩杀时浮窗给完整公式（按舞 / 幻分行），照着打每步划掉、中途不消失、面板不跳；② 故意打偏一步，旧公式置灰并标「已偏离，重算中」，随后换新公式；③ 斩不了且对方场攻 ≥ 血量 − 5 时出「奶 16」线或「等死」；④ 公式多行时不挡手牌 / 记牌器；⑤ **10-06 后两批没复测**：牛那步「牛（龙舞）1」金色括号好不好认；打币、打完刀之后照着打不再误判偏离；先用英雄攻击再启动时不再卡在「重算中」；舞之后公式不会让牛再拿一次龙 | 红龙贼套牌；包在 `/private/tmp/HSTracker-rdr-t4-build/Build/Products/Debug/HSTracker.app` |
| Phase 2 / 2.6 高亮加强 | 只能在炉石背景上看 | 弑君者之类关联卡 |
| Phase 4 / 4.3 Trackers 页 | 🖥️ 设置窗口中英文各一遍 | 不开炉石 |

战棋不作为验收手段（用户不玩），只做静态确认。

## 等你定

- **红龙 T2a 公式**（细节在 `docs/tasks/rdr-t2a-formula-audit.md` 末尾）：① `t1-pre-03-n1` 下回合杂牌数截图没写（0~3 通过，4 起手 11 张非法）；② `t2-huqs-03-n1` 是否适用「提前彗」组注（步不计杂 → 起手 11 张判不成立）；③ 13 条腾格行靠「公式表是给另一版牌组写的」推断通过（用背刺 / 袋底藏沙）；④ 快枪固定费用是否覆盖减费（待核）；⑤ 彗星「连击没开也消耗 / 与鲨鱼同场 ×2」两条假设（待 T2b 日志核）。
- **构建环境**：`AGENTS.md` 构建命令清掉了全部代理，SwiftPM 拉不到 github.com；实现者临时加 `GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.https://github.com.proxy GIT_CONFIG_VALUE_0=<原 https_proxy>`。要不要写进 `AGENTS.md`。`-configuration Release` 下测试 target 编不过（`HSTracker-Test-Bridging-Header.h:13` 找不到 HockeySDK），要不要修。
- **红龙 T2b**（原文在 `docs/archive/tasks/rdr-t2-delivery.md`「等用户定」）：
  - 幻觉药水处理顺序无证据，按场位（待核，等一局药水爆手的日志）。
  - 展示规则：「被截断」只在撞 CPU 兜底时标；只有困难线时默认 L2。
  - 本地包 Release 也带 `-enable-testing` 能否接受；另一条路是把 app 用到的 API 改成 public。
  - 对手奥秘不进搜索（T2c 标「⚠ 对方有奥秘」）。
  - 已结的：两条缺件漏线、G3 T9 人工核，10-06 用户定修，进 T5 A2 / A4；「舞动 / 暗影步的费用附魔回手再下场还在不在」由 10-05 日志结案（card-model B2 订正，T3）；「基础线封顶」由 T4 改成删 L1，剩下的问题见 T4 ⑥。
- **红龙 T5 C1 两条鲨鱼**：代码按 2 次（不叠加）。card-model §19 / #13 写的是 4 次，只影响 `t2-wudao-01`。按代码（炉石里布莱恩类效果多张不叠加）还是按文档？10-07 Codex 核对：官方卡文是「触发两次」，多条不相乘，代码对；点头后只改 card-model 两处。
- **隐私**：已推到 origin 的 `HSTrackerTests/Fixtures/ZoneReplay/2026-09-*.log` 和 `docs/tasks/bug-t11-*.md` 里有用户本人的 BattleTag。彻底清掉要改写历史并强推，没动。
- **红龙 T4**（细节在 `docs/tasks/rdr-t4-setup-lines.md` 书末）：① 奶 16 线在多条里先挑「下回合伤害高」的，步数可能很长（回放里 15–19 步），要不要改成先挑步数少的；② 奶 16 按回血量 16 算、不看实际血量上限（28 血时也推荐）；③ 危险且「抽到才能斩」时现在只列抽牌分支、**不**搜奶 16（Codex 10-06 核出，之前这里写反了），要不要改成也给奶 16（T5 A1 修好后，「抽到才能斩」误判会少很多）；④ 预启动线引擎能搜、默认不提示（开关 `suggestsPreLaunch`），要不要在「等死」前先试预启动；⑤ 10-05 晚上的 DK 局 / 猎人局不在 fixture 里，锁定回放没单列，靠实测；⑥ 删 L1 后「基础」档斩杀线（设置不是「顺序」时）热键升不到顺序、只剩判定，要不要放开；⑦ 误判偏离还剩 9 次零散的（对手让我方牌 +5 费的局、所有牌读成 2 费的局、场面满、一步跳多步等，每种 1–2 例，明细在任务书「误判偏离定因」），要不要继续查；「操作计数没变时线接不上不标偏离、静默重算」是实现者加的，要不要留；⑧ Codex 10-06：公式不写落位、敌方随从只写「怪」，标记删掉后没处补，要不要写进公式（E.T.C. 发现选哪张已写进公式）；⑨ 两条待证风险（英雄撞随从反伤不扣血、牌库有边牌同名牌时抽到当发现）要不要查。
- **小结窗被点掉**：10-06 定因——弹出 2.3 秒后被一次鼠标点击关掉，开着「炉石关闭时退出」所以 HSTracker 跟着退。选项：弹出后头几秒不响应关闭 / 关小结窗不再退出 HSTracker / 不改。
- **本机签名**：10-06 `Config.xcconfig` 改成个人 Apple ID 的 Apple Development 证书（Team `DY725KK25V`，2027-10-05 到期，Xcode 自动续），辅助功能授权不再随重编失效；改动在主仓库未提交，要不要提交。

- **V2 余项**：拖拽 / 吸附（不锁定 + 边缘吸附 + 锚点持久化，已决 09-15，细节在 `docs/tasks/phase2-v-visual-redesign.md`）；三行头 40 → 21 实机看。折叠 10-08 拆出，进 `docs/tasks/phase2-scroll-collapse.md`：换轨后记牌器在上游画布上，锁定时箭头格自己报交互区就能收点击，不用等这套鼠标模型。
- Phase 7 要不要回看历史会话（首版没做）。
- 「高亮手牌」在分区模式下是否强制关；备牌浮窗要不要受「显示相关牌」开关管（现在不受，dev 同）。

## 已知问题（未修）

| 问题 | 根因 / 位置 | 归属 |
|---|---|---|
| Discover 开着时悬停记牌器，OutFinder 池消失 | 备牌浮窗与 OutFinder 共用 `RelatedCardsTooltipPanel.shared`；`DiscoverStateWatcher` 只在状态变化时回调 | REFORK S4 接上游悬停路由时解决 |
| 段头折叠箭头只画不点 | V2a 画了 chevron，折叠未实现 | `docs/tasks/phase2-scroll-collapse.md` |
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
| `red_dragon_assist` / `red_dragon_reveal_level` / `red_dragon_quiz_mode` | — | false / 0 / false | 红龙 T2b，热切换；设置页控件 T2c 加 |

合并还要保住：`project.pbxproj` 的 `NET_VERSION = net8.0`（3.6.12 起上游由 `mono-version.txt` 推出，同值）与 `MACOSX_DEPLOYMENT_TARGET = 14.0`（dev 4 处，另 2 处 10.12；3.6.12 为 6 处 10.15，REFORK S1 全改）；`Card.copy()` 补的 `enText` 拷贝（上游漏拷，查表拿到的卡 `enText` 为空）。
还要保住 `RealmHelper.add(mirrorDeck:)` 补存的 sideboard（`507d354`）：上游这里漏了，新导入的套牌首局 E.T.C. 乐队为空，红龙判定不成立，整个 overlay 不出。

## 仍作数的决策

- **延迟不是 KPI。** Phase 0 / T6 四轮测量（口径 → Release 基线 → 拆 D → 拆补集）没有降一毫秒后主动收口：唯一像延迟的反馈实为 `highlightCardsInHand` 行为；A 段 ~150ms 是炉石写盘节奏；以后动延迟先拿用户反馈立项。数据与排除法结论见 `docs/archive/progress-2026-09-22.md`「延迟实测」。唯一留下的候选「合并 18 次主队列投递」以帧一致性立项，落到 REFORK S5。
- **探针** `HSTRACKER_LATENCY_PROBE=1`（Release 包读 `~/Library/Logs/HSTracker/hstracker.log`）。口径：A 日志时间戳 → `processLine`；B → `guiNeedsUpdate` 置位；C → tick 消费；D `updateAllTrackers()` → UI 提交完成。D 的终点靠两级 main marker，刷新路径里再嵌两层 `async` 会静默低估。REFORK 后埋点收到 3 处（`7c0f2390`）。
- **T5 防抖的两个不变量**：不是 trailing-edge（第一个请求排一次、窗口内只置标志）；`guiUpdateInFlight` 不可去。
- **两个阶段的 T6 同名**，引用写全「Phase 0 / T6」「Phase 1 / T6」。
- **视觉验收只认实机**：改视觉的一律 🎮，2.6 只能在游戏背景看，2.8 只有全屏才作数。
- **Firestone 不做卡条动画是选择**（transition 注释掉修 flicker）；HDT 的三段 storyboard 是我们 T8 的参照，时长减半、数字立即更新。调研在 `docs/research/`。
- **红龙揭示档**：设置选「顺序」时，斩杀线一律给顺序，连招中途重算出基础线也不降档（10-05 实测：中途降档后公式消失，`507d354`）。T3 跟手的数字在 `docs/archive/tasks/rdr-t3-live-feedback.md`：同口径中位 348 → 30 ms，36 步里 2 步没赶上下一次点击；炉石写日志本身的等待仍约 3 秒，不归我们管。
- **T8 动效常量定稿**（09-23 卡点 ④）：`TrackerMotion.swift` 塌陷 0.28s / 闪光 0.4s / 峰值 0.38；离场行只塌陷不闪（收敛性取舍）；行高不动画、压缩态一律瞬切；诊断键 `tracker_motion` + 系统「减弱动态效果」都能关。
- **记牌器放不下改滚动**（10-08 用户定，取代上游按行数压缩行高、V1 让宽度跟着缩的做法）：固定行高；三行头固定、卡段滚；刷新后保持位置，夹回合法范围；两侧同一套；视口底边淡出。实现见 `docs/tasks/phase2-scroll-collapse.md`。

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

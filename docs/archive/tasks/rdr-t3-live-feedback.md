# 红龙 T3 —— 10-05 实测反馈：跟手、rewind 后失效、舞动后误判

先读 `docs/tasks/_common.md`。前置：T2a / T2b / T2c 已提交（`d73f8a67` / `61fbcbd3` / `359916c9`），代码在 `HSTracker/RedDragon/`，交付细节在 `docs/tasks/rdr-t2-delivery.md` 和三本 T2 任务书末尾。

## 用户的原话（10-05，打了 7 局红龙贼）

> 1、计算时间较长，没法跟上我的操作速度，进入可斩杀公式后，我打出一步后计算大概需要 3 秒才给出下一步。
> 2、刚刚最后一局直接崩溃了，浮窗无显示。
> 3、有一局我按照公式出的牌，到了舞动全场回手后，浮窗直接提示无法斩杀，不知道是计算错误还是我真的打错了顺序。

10-05 用户补充问题 1：体感是「计算完成 → overlay 显示下一步」约 3 秒，而用户出一张牌只要 1 秒左右。**目标：炉石写出这一步到浮窗显示下一步 ≤ 1 秒。**用户的「计算完成」是体感，不代表瓶颈一定在提交 / 绘制，以实测为准。

## 材料

- 炉石日志：`/Applications/Hearthstone/Logs/Hearthstone_2026_10_05_17_20_23/Power.log`（7 局，17:22 – 18:05）。舞动全场（`ETC_079`）出过 4 次：第 32786 行（第 2 局，17:34，输）、第 63515 / 74024 行（第 4 局，17:44 / 17:46，赢）、第 131528 行（第 7 局，18:03，输）。
- HSTracker 日志：`~/Library/Logs/HSTracker/hstracker.log`。红龙代码自身不打日志。
- **问题 2 的初判（我看日志得出，你来证实或推翻）**：HSTracker 没崩（10-05 只有 14:21 两个 `AnomalyGuideMulliganTriggerView` 崩溃报告，是 PLAN 已知的测试宿主问题）。第 7 局 17:59:22、18:01:44 两次 `LogReaderManager` 停了又从对局开头重读，没有 `Starting log reader` —— 走的是 `CoreManager.handleRewind` → `resetAndReprocess`（半稳定传送门的 Rewind）。之后红龙浮窗再没出现过。
- 日志含真实 BattleTag：要做成 fixture 就按 T2b 的做法脱敏，原始日志不入库。

## 要做出什么

1. **跟手**：用户在斩杀线中途每打一步，下一步提示要在用户打下一张牌之前出来。先用今天的日志量出「炉石写出这一步 → 浮窗更新」每一跳各占多少（写日志 / 解析 / 拷快照 / 去抖 / 搜索 / 提交），找到 3 秒花在哪，再定怎么改。给出改前改后同口径的数字；口径和测量方法写清楚，别人能复现。
2. **rewind 后恢复**：证实或推翻上面的初判；rewind 重读之后（以及任何让对局被重新读一遍的路径：中途启动 HSTracker、断线重连）浮窗要恢复正常。
3. **舞动后误判**：把 4 次舞动前后的每个局面喂给引擎，逐个说清楚：舞动之后判「无法斩杀」的那一局，是引擎 / 读取错了，还是用户的出牌顺序确实断了线。如果是用户打错，指出从哪一步起断的、当时正确的下一步是什么；如果是我们错，修掉并补测试。结论用用户看得懂的牌名写（公式表缩写见 `HSTrackerTests/Fixtures/RedDragon/formulas.json` 的 `notation`）。

## 硬约束

- 已有行为不能退：T2a 公式表结论、T2b 回放（10-01 四局四个斩杀回合）、T2c 的不卡顿测量和 0 相交扫描。
- 「宁可不给路径，也不给打不出来的路径」（`RedDragonReplay.swift` 顶部）不变：为了快而返回未经重放校验的线不行。
- `AGENTS.md`「线程与时序」：改调度时序前，列出写入到显示的每一跳。为测量加的日志 / 计时，交付前删掉或收进只在测试里开的开关。
- 上游文件（`CoreManager` / `LogReaderManager` / `Game` 等）只加挂接所需的极少行；能在 `HSTracker/RedDragon/` 里解决的就在里面解决。

## 构建节奏（10-05 用户定）

- 改动过程中只跑相关测试（`-only-testing:` 红龙相关测试类），全套 `test` 只在交付前跑一次。
- 不切换 `SWIFT_OPTIMIZATION_LEVEL` / configuration 做测量；Release 级耗时用 scratchpad 里的独立 `swiftc -O` 基准。
- SwiftPM 拉 github.com 需要时临时加 `GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.https://github.com.proxy GIT_CONFIG_VALUE_0=<原 https_proxy>`（T2 先例）。

## 允许修改的文件

`HSTracker/RedDragon/`、`HSTrackerTests/` 红龙相关与其 fixture、`HSTracker/Logging/CoreManager.swift` / `LogReaderManager.swift`（只为挂接）、`project.pbxproj`（只登记）。还要碰别的，先在报告里论证。

## 验收

- 问题 1：今天日志里每个「斩杀线中途打出一步」的局面，浮窗更新延迟的分布（中位 / 最慢），改前改后对比；目标是用户打下一张牌前出结果，达不到就说清卡在哪一跳、还剩什么选择。
- 问题 2：一个能复现「rewind 后浮窗消失」的测试，修后通过。
- 问题 3：4 次舞动逐个的结论表 + 判定依据。
- 全套测试条数与 T2c 交付时（442 条，1 跳过，只挂签名 1 条）对得上。

## 2026-10-05 接手续做记录

- 用户本次授权：只完成 T3，交付后停下等反馈；不安排 review；构建与全套测试集中到交付前。T4 第 5 项已确认要做，但本次只同步任务书状态。
- 起点 `359916c9` / `dev0923`。原目录暂存区为空，7 个已跟踪文件有未暂存修改；它们均出现在 Claude subagent `afb177a00a69a938e` 的编辑记录中。两本 T3/T4 任务书由主会话 `c3483664-50dc-443b-9805-a913e200ba08` 创建。隔离目录 `/Users/wadorudi/.codex/worktrees/rdr-t3/HSTracker`，分支 `codex/rdr-t3`，不改原工作区。
- 继承的五份 10-05 回放素材逐文件核对一致，保留已有脱敏别名 `Me#1001` / `OpponentE` 至 `OpponentI`；未引入新的真实对局素材。`Config.xcconfig` 是早已存在的本地签名设置，不算 T3 修改；构建通过 `-xcconfig` 读取原文件，worktree 内该文件不改。

### 规则证据与公式

- 第 2 局 fixture 14652 行暗影步指向晦鳞巢母 #22；14731 行恢复印刷费 3，14765 行变成 1，证实舞动后重新打出再暗影步不按 0 费算。
- 独立样本：第 4 局 fixture 15229 行鲨鱼 #60 被舞动设为 1；重新上场后 16472–16480 行舞动附魔 #218 自行触发并进坟场，16517 行费用恢复为 4。该样本验证的是舞动附魔打出时移除，不声称它又被暗影步回手。
- 第 7 局 fixture 30523 行暗影步指向阿莱复制体 #389；30603/30604 行恢复印刷费 9、攻击 8，30640 行变为 7 费。复制体回手清除复制附魔。
- 10-01 第 3 局 T11 的额外 1 点：殒命暗影已变成致聋术，沉默 #41 的嘲讽 → 英雄技能 → 英雄攻击对方英雄。补上逐步断言，不仅修改最终数值。
- 独立 `swiftc -O` 诊断确认 90 个公式案例仍为 80 通过、10 个原有未通过/待确认，订正规则没有新增失败。严格重放与搜索分开：`t2-wuhui-03` 的正确路线在原主搜索第 14 步（第二次 E.T.C. 后）被评分裁掉，5923 个候选中仅排 4702；采样纯靠哈希排序则受局面编码影响。补搜改按伤害、法力、场面格数、手牌格数、边牌余量轮流保留候选，层内按蓄力分排序，总状态预算仍 400000。所有返回路线仍逐步重放验证。

### 时序与测量口径

1. `LogReaderManager` 每 50 ms 轮询，解析一批 PowerTaskList 日志，到无未闭合 BLOCK 的边界拷快照。
2. 第一次 `main.async`：`RedDragonAssistant.submit` 提交当前快照并调度后台工作；普通搜索等待 120 ms 去抖。
3. 后台串行队列：当前仍可接上同一回合的斩杀线时，跳过去抖和搜索，将所有候选剩余步骤在真实局面重放；接不上才走原搜索。
4. 第二次 `main.async`：校验版本与对局身份后一次提交结论、揭示档和答题状态。
5. 第三次 `main.async`：`RedDragonOverlayViewModel.receive` 合并同一轮事件、一次更新 model，随后 SwiftUI 布局和绘制。没有新增 `main.sync`。

`RedDragonFeedbackTests.testFollowLatency` 通过 `TEST_RUNNER_HSTRACKER_RDR_LATENCY=1` 开启，按原日志时间间隔回放六个斩杀回合，真实 assistant + view model + 离屏 NSHostingView 执行 layout/display。改前/改后是同一份修正规则后的代码，仅关闭/打开接续重放；不冒充旧版代码的完整对照。点击当时是否已显示斩杀按当时墙钟判定，步骤只和同一回合的快照配对，两次都已显示斩杀的同一批步骤另外成对统计。

该测量包含拷快照、主线程排队、去抖、后台计算、提交和离屏绘制；不含真实磁盘写入至轮询读到的时间（轮询周期另列 50 ms），也不等于屏幕实际出光。GameState 完成到 PowerTaskList 完成的时间直接由日志相减，单列为炉石结算/动画排队，不能归到 HSTracker 的绘制耗时。真实对局体感仍需用户实测。

### 构建与复现入口

2026-10-05 22:36（北京时间）隔离 worktree 构建输出 `BUILD SUCCEEDED`，退出码 0。首次尝试尚未编译就遇到 AppMover 的 GitHub HTTP/2 更新请求失败；第二次禁用远程更新，使用已锁定的依赖缓存通过。没有改动依赖版本或项目签名文件。

在 worktree 根目录执行（应用构建将最后的 `test` 改成 `build`，并去掉 `-skip-testing` 与延迟环境变量）：

```sh
env -u http_proxy -u https_proxy -u all_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
  PATH=/usr/bin:/bin:/usr/sbin:/sbin TEST_RUNNER_HSTRACKER_RDR_LATENCY=1 \
  xcodebuild -project HSTracker.xcodeproj -scheme HSTracker \
  -configuration Debug -destination 'platform=macOS' \
  -xcconfig /Users/wadorudi/Desktop/dev/HSTracker/Config.xcconfig \
  -derivedDataPath /private/tmp/HSTracker-rdr-t3-build \
  -clonedSourcePackagesDirPath /Users/wadorudi/Library/Developer/Xcode/DerivedData/HSTracker-cgfkydaatbcvlygsoujdqwiezsjx/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -parallel-testing-enabled NO \
  -skip-testing:HSTrackerTests/LocalizationFormatTests test
```

构建产物已检查 `HSTracker.debug.dylib`、`CardDefs.bin`、arm64 的 .NET 核心库、BobsBuddy 和 HearthDb 均在包内。启动：

```sh
open /private/tmp/HSTracker-rdr-t3-build/Build/Products/Debug/HSTracker.app
```

测试首次只到编译阶段，新增统计输出的跨行字符串插值有语法错误；改为先计算数组再格式化后重新启动测试。这次编译失败不计入测试执行条数。

### 延迟结果与边界

22:46 完成延迟回放，Feedback 10 条全部通过。两次点击时都已显示斩杀的同一批 36 步：

| 指标 | 关闭接续 | 开启接续 |
|---|---:|---:|
| 读到局面→离屏绘制，中位 / p90 / 最慢（35 步有结果） | 348 / 504 / 772 ms | 30 / 416 / 608 ms |
| 未赶上下一次点击 | 1/36 | 2/36 |
| GameState 整步结束→绘制，中位 / 最慢（34 步可配对） | 3357 / 6497 ms | 3082 / 6049 ms |

开启接续时全部「点击前已显示斩杀」样本为 36 步，22 步接续成功；结果提交→绘制中位 3 ms、最慢 10 ms。关闭接续时为 37 步，提交→绘制中位 2 ms、最慢 15 ms；因此另外列共同步骤，不能直接用不同样本集合比较。GameState→PowerTaskList 中位 3061 ms，最慢 6809 ms。旧测量里跨回合配对产生的 86.7 秒已修正。

**没有达到「每步都赶上下次点击」**：一个步骤的计算在下一次局面变化前未提交，另一次虽然有结果但晚于点击；不能把 608 ms 当作全部步骤的最慢值。第 1 局连招后重新搜索仍有约 1.1–1.7 秒的步骤。T3 没有越过用户决定去实现 GameState 提前显示，真实对局完整延迟也不保证 ≤1 秒。

### 四次舞动的结论

| 局面 | 结论与依据 |
|---|---|
| 第 2 局 T13 | 读取错误：殒命暗影变成暗影步后仍按原身份读取。修后在 14085、14989、15813 行均有斩杀；之后阿莱指向自己回血，原斩杀线断开。正确方向是阿莱打对方英雄，接狐人老千、暗影步回刀油、刀油、E.T.C.、幻觉药水，再阿莱打脸。不能把先前浮窗误判归咎于用户。 |
| 第 4 局 T11 | 读取错误：殒命暗影已变成舞动，原读取漏掉第二次舞动。16181 行修后仍有斩杀；旧记录中随后先下阿莱复制体占满场面，路线断开。 |
| 第 4 局 T13 | 舞动前后仍可斩杀，新增回放断言通过，实际这一回合获胜。 |
| 第 7 局 T13 | 费用模型错误：阿莱 1/1 复制体暗影步回手应为 7 费。30183 行修后返回的斩杀线经重放验证，不再把复制体当作低费回手目标；30418 行已偏离后正确判不能斩杀。 |

rewind 回放两次重置后，T11/T13 都有真实 assistant 提交的斩杀结论，已通过。测试复用生产的跳过判断和真实解析器，按 CoreManager 相同步骤重置与重读；未直接重启系统日志管理器，亦没有断线重连的真实样本。用户实测仍需看实际浮窗恢复和出牌节奏。

### 文件与范围

- `RedDragonAssistant.swift` / `RedDragonReplay.swift`：复用现有搜索、重放和展示链路，增加剩余路线校验后接续；所有有效候选一起交给必打/可选标记。
- `RedDragonSnapshot.swift`：读取变身身份、排除 rewind 产生的假玩家实体。
- `LogReaderManager.swift`：保留被回溯 PLAY 前同时间戳的结算结束行；每次读取重置跳过进度。它修的是阻断所有一致边界的读取问题，无法仅在红龙模块内补救。
- `RedDragonEngine.swift` / `RedDragonReader.swift` / `RedDragonState.swift`：订正回手、打出与沉默的附魔生命周期，同步旧注释。
- `RedDragonSearch.swift`：补搜按资源阶段保留候选；`t2-wuhui-03` 默认预算搜到 32，公式重放仍 80/90，无新增失败案例。
- `RedDragonTests.swift` / `RedDragonLiveTests.swift` / `RedDragonLiveReplayTests.swift` / `RedDragonFormulaTests.swift`：更新被日志反证的预期，补沉默回手、1 点伤害的逐步验证、搜索换排列验证，避免短路径导致测试越界崩溃。
- 继承的 `RedDragonFeedbackTests.swift` 与五份脱敏日志：完成回溯恢复、四次舞动和延迟测量；`project.pbxproj` 只登记它们。
- `PLAN.md`、本任务书、T4 任务书与 `docs/research/red-dragon-card-model.md`：同步进度、T4 已定范围和规则证据。卡牌模型文档超出任务书代码列表，但规则已改变，必须同步，避免后续按旧规则回改。

未处理的既有问题：对方免疫时仍可能耗费搜索预算；回合开始资源更新期间可能短暂显示未找到；拖动到自定义位置的其他浮窗避让仍按 T2c 的已知限制。准备线和完整公式显示留给 T4。

### 最终验收记录（22:52）

- 应用构建通过。全套实际执行 **454 条**（T2c 442 + 本次 12）：xcresult 汇总 **449 通过、1 预期失败、2 跳过、2 失败**。2 个跳过是 Debug 下的 Release CPU 基准与按需效果图；LocalizationFormatTests 是整类排除，未算进 454。
- 两条失败之一是既有官方签名检查；另一条是 10-01 第 4 局 T10 的旧断言写死「先鲨鱼」，新的合法 32 伤路线先幸运币。只改测试为完整路线重放 + 首步实体/牌身份映射（兼容幸运币的不同编号），保留伤害、难度和斩杀断言；修正过程中又处理了币别名比较与 Optional 解包，最终单项 **1 条通过，TEST SUCCEEDED，退出码 0**。没有重复全套，也没有为通过而修改产品代码。
- 最终逐项合并状态：**450 通过、1 已知预期失败、2 跳过、1 已知官方签名失败**，不是一次全绿全套。预期失败仍是原有缺件补齐搜索漏线；公式 80/90 结论不变，默认预算的 `t2-wuhui-03` 与换排列验证通过。10-01 四局的斩杀断言通过；T2c 23 条 overlay 测试中除按需图库外均通过，含避让与刷新性能检查。
- 结果包：`/private/tmp/HSTracker-rdr-t3-tests-final.xcresult`（全套）、`/private/tmp/HSTracker-rdr-t3-g4-verified.xcresult`（最终单项复验）。
- 当前交付状态为 **🎮 待实测**，原 `dev0923` 工作区和暂存区保留，改动只在隔离分支，未提交。T4 不开始；用户只需启动上面的包，实测舞动后提示、回溯后浮窗恢复和出牌跟手。

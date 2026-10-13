# 红龙 T7：连着出牌时公式进度跟不上

先读 `docs/tasks/_common.md`，再读 `HSTracker/RedDragon/RedDragonAssistant.swift` 文件头的跳数说明和
`docs/archive/tasks/rdr-t3-live-feedback.md`（跟手的设计和当时的数字）。

## 症状（用户，2026-10-13 实测，Release 包）

设置「顺序」、锁定模式。可斩杀，面板给了 21 步公式。用户连着出 币、鱼、狐、刀：面板显示 1/21 之后
**6.3 秒没有任何更新**，一直停在旧公式的 1/21，也不置灰；之后才标「已偏离」并换新公式。用户照着屏上落后的公式
又出了一张，斩杀断了。公式本身是对的（已逐步核过），问题只在进度跟不上。

## 证据

- 炉石日志：`/Applications/Hearthstone/Logs/Hearthstone_2026_10_13_22_24_57/Power.log`，这一局从字节偏移 24907211 起
  （`CREATE_GAME` 23:16:29），出事的回合是 23:19:27 起的 TURN 9，本地玩家是 PlayerId 1。
- `~/Library/Logs/HSTracker/hstracker.log` 第 11983–11987 行（`red dragon: locked …` / `deviated`）。
- 解析器吃的 PowerTaskList 一路里，顶层 PLAY 块的开闭时刻：

  | 牌 | 开 | 闭 | 面板 |
  |---|---|---|---|
  | 币 | 23:19:30.963 | 31.818 | 31.895 显示 1/21 |
  | 鱼 | 32.031 | 34.370 | 无 |
  | 狐 | 34.370 | 35.007 | 无 |
  | 刀 | 35.007 | 38.370 | 38.422 标偏离，38.796 新公式 |

  鱼闭合和狐打开在同一时刻，狐闭合和刀打开也是。32.031 → 38.370 之间没有一次局面被读出来。
- 不是偶发：同一份 Power.log 里 23:10:20 起的那一回合，鱼 / 狐 / 刀 / 牛连出，日志进度从 0/20 直接到 4/20。

## 要什么（用户定：小改）

顶层 BLOCK 一闭合，那一刻的局面就要能读出来并且**结论能上屏**，不因为下一个 BLOCK 紧跟着打开而丢掉。
上面那个回合里，鱼闭合后面板到 2/21，狐闭合后到 3/21，刀闭合后标偏离（用户跳过了公式里的「伺」）。

不做的：不改成读 GameState 那一路（那是「大改」，用户没选）；每一步仍然等它自己的动画播完，这是预期内的。

## 硬约束

- `AGENTS.md`「线程与时序」全部适用。动手前在报告里列出从解析线程读到一行、到面板显示的每一跳，以及你改了哪一跳。
- 屏上不能出现比已上屏结论更旧的局面的结论（不倒退）；换局、换回合后旧结论不上屏，这两条现有保证不能丢。
- BLOCK 开着、实体改到一半时不读局面，这条现有规则不变。
- 非锁定模式（答题、非「顺序」档）下「局面在变时结果标过时」的现有行为不变，除非你能说明为什么必须变。
- 不开红龙辅助、不是红龙贼套牌、不在对局里时，解析线程上不能多出可测量的开销；开着时每次读局面的耗时报个数
  （现有 `captureNanos`）。
- 不动引擎、搜索、公式、面板外观、设置项。

## 可改的文件

`HSTracker/RedDragon/RedDragonAssistant.swift`、`HSTracker/Logging/LogReaderManager.swift`、
`HSTracker/Logging/Parsers/PowerGameStateParser.swift`（只为拿到「顶层 BLOCK 刚闭合」这个时刻）、
`HSTrackerTests/RedDragonFeedbackTests.swift`、`HSTrackerTests/RedDragonLiveReplayTests.swift`。
要把上面那一局截成 fixture 的话放 `HSTrackerTests/Fixtures/RedDragon/`，截取方式照现有 fixture（T2b 任务书执行结果里有命令）；
为登记这个 fixture 才可以动 `project.pbxproj`，别的不动。

## 验收

- 有测试按上面的时序复现「连出三张、块首尾相接」，改动前失败、改动后通过：每个顶层块闭合后的结论都上屏，顺序不乱。
- 有测试守住「不倒退」和「换回合 / 换局旧结论不上屏」（现有的够用就指出是哪几条）。
- 受限环境 `build` 过；迭代中只跑红龙相关的测试组，交付前跑一次全套（`-skip-testing:HSTrackerTests/LocalizationFormatTests`），报告条数。
- 报告：跳数清单、改了哪一跳、作废 / 版本 / 取消这几样各自怎么处理的、读局面耗时、你认为还剩的风险。
- 🎮（由人做）：打一局红龙贼，连着出牌，看进度一步一步跟上。

## 执行结果

10-14 第一轮（Opus 子代理），我读 diff 通过（本书不跑 Codex，用户定），未提交。

- 改了：`RedDragonAssistant.swift`（新挂点 `parserTopBlockDidClose`；`fedVersion` / `sharedTokenLocked` / `inFlightLocked`）、
  `LogReaderManager.swift`（`processLine` 里最外层 BLOCK 闭合时调挂点）、`RedDragonFeedbackTests.swift`（+2 条）、
  新 fixture `Fixtures/RedDragon/2026-10-13-g12-chain.log`（10733 行，已脱敏）、`project.pbxproj`（只登记 fixture，4 行）。
  `PowerGameStateParser.swift`、`RedDragonLiveReplayTests.swift` 没动。
- 光提前拷不够：下一个 BLOCK 打开会把刚投的核对作废。现在锁定公式的核对只被**更新的投递**作废，不被
  「BLOCK 开着来新行」作废（解析线程不取消它、`markStale` 不涨代号、结果按 `fedVersion` 核对）；非锁定模式照旧。
  没有新增 `main.async`。
- fixture 回放（同一条测试跑修前 / 修后两遍）：修前 币 1/21 之后鱼、狐无更新；修后 1/21 → 2/21 → 3/21 →
  刀闭合标偏离 → 新公式 0/17，公式文本和线上日志相同。
- 测试：`RedDragonFeedbackTests` 12 条 0 失败 1 跳过，`RedDragonLiveTests` 33 条 0 失败（我复跑）；
  全套 499 条，493 过 / 5 跳过 / 1 失败（签名老失败）。
- 读局面耗时（Debug）：斩杀回合 13 次平均 2.4 ms、最大 3.6 ms；现有四局基准中位 44 µs、p99 5.0 ms。Release 没量。
- 行为变化，等用户定：偏离后的重搜属于同一次锁定核对，不再被下一个 BLOCK 打断，新公式会更早上屏
  （基于偏离那一刻的局面，下一张闭合后再核对）。
- 没动的：`RedDragonSnapshot.swift` 第 6 行注释还写着「一批日志处理完时拷」；换局没有专门测试，靠没动过的对局身份核对。

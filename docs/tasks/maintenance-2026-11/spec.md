# HSTracker fork 独立维护 Spec

> **日期**：2026-11-21（初稿 11-20）　**状态**：已定稿，决策记录见第 6 节，实施细节在 `packages/` 下
> **基线**：本地仓库 `HSTracker`，`dev0923` = `claude/project-thread-y79oo9` @ `5e6b89ac`（上游基座 3.7.1）
> **依据**：外部评估报告 `report-v2.md`（不入库），以及对代码、本机炉石日志、HSTracker 日志、hsdata 和 HDT 公开仓库的核对
> **证据标记**：【核实】直接看过代码、日志或数据；【推断】由已核实事实推出，没有实际跑过；【未核实】需要实施时确认

本文件只放目标、范围、约束、证据、未决问题和拆分索引。每个工作项的要求、设计和验收，都写在 `packages/` 下对应的包文件里，以包文件为准。

---

## 0. 背景与目标

官方 HSTracker 从 3.7.2 起不再公开源码。本 fork 停在 3.7.1，今后独立维护，只服务**构筑模式和红龙贼**。

目标：

1. 卡牌数据跟随**国服客户端**的 build。
2. 消除对闭源 `HearthMirror` 的硬依赖：它失效时，构筑记牌（牌表、计数器）和红龙仍然能用。
3. 按需移植 HDT 公开源码里的构筑修复，止于 `2698623`（11-03，标题为 v1.59.8，没有 git tag）。
4. 修好会让卡牌附加信息（`extraInfo`）丢失的问题，在此基础上做组装牌的悬浮显示。
5. 把仓库和规则调整成「上游已断供」的状态。

## 1. 范围

### 1.1 工作项与归属的包

| 工作项 | 内容 | 所在包 |
| :-- | :-- | :-- |
| W0 | 开打前退出 ModHost 安全模式（你在设置里操作，不改代码） | 开打前 |
| W1 | 卡牌数据跟随国服客户端 build（现为 `255790`） | 包 1 |
| W2a–d | HearthMirror 失效兜底：日志目录、游戏模式、我方 / 对手识别、Debug 失效开关 | 包 4、包 5 |
| W3a–c | 移植 N'zoth、C'Thun、Gloomstone 三处修复 | 包 3 |
| W3d | 移植发掘关联卡 | 包 7 |
| W3e | 组装牌悬浮（按 D3 的规则） | 包 6 |
| W3f | 修复 `extraInfo` 在分组和复制时丢失（疑似伊辛迪奥斯计数不显示的原因），顺带修 `Array.swift:29` 排序比较写错 | 包 2 |
| W4 | 仓库整理：`upstream`、`master`、交接记录 | 包 0 |
| W5 | 新拓展包维护流程，写进 `docs/upstream-merges.md` | 包 0 |
| W6 | 修订本地化规则（D1），补 `BE` 系列名的 zh-Hans | 包 0 |

### 1.2 不做

- 不升级 `HearthDb.dll` / `BobsBuddy.dll`。它们只给 Mono 侧的战棋模拟用。
- 不做任何战棋或竞技场改动。
- 不改亚煞极计数器：它和 HDT 逐行一致（见 O5）。
- 不改 `CriminalContract`：HDT `19b9e38` 修的是 C# 端自己的 bug。
- 不移植 HDT `980f635`（在卡条名后加组装来源卡名），与 D3 冲突。
- 不做独立的红龙 App。
- 不排查 11-17 开局卡住（暂缓，见 O1）。
- 不推送 `master`（D2）。

## 2. 约束

来自 `AGENTS.md`（包 0 合入后，本地化一条以新规则为准）：

- **线程**：`HearthWatcher/` 的回调在各自的队列上执行。写 SwiftUI view model 前必须先 `DispatchQueue.main.async`，同一份状态在同一个 main block 里提交，禁止 `main.sync`。改 overlay 或 view model 的时序之前，先列出从写入到显示之间每一次 `main.async`。读 `QueueEvents.isInQueue` 的代码不能放在对局路径上。
- **构建**：只用 AGENTS.md 里那条受限环境下的 `xcodebuild` 命令。日常用 `build`（增量），测试把它换成 `test`。只有 `HearthMirror-version.txt` 变了才需要 `clean build`。
- **工程文件**：每新增一个 `.swift`，要在 `project.pbxproj` 里手工登记 4 处。计数器和关联卡是靠 `ReflectionHelper` 在运行时扫描类来发现的，漏登记**不会报错，这张卡就静默失效**。
- **本地化**：改动 `.xcstrings` 后必须跑 `check_xcstrings.py --baseline`。
- **文档**：`docs/` 用中文。`docs/PLAN.md` 只记提交记录、构建 / 测试记录和项目细节，不列待办。
- **提交**：用 Conventional Commits 前缀（merge commit 不加）；保留 `Co-Authored-By`；不写会话链接，也不写「Generated with」行。

使用习惯：

- 用户不玩战棋，验收不能依赖战棋对局。
- 需要用户实测时，直接给出 Debug 包的启动命令（见第 7 节）。

## 3. 现状（证据）

| 事实 | 证据 | 标记 |
| :-- | :-- | :-- |
| 本机是国服，客户端 build 是 `255790` | 11-17 `Hearthstone.log` 写着 `Region: CN`、`Data = 37003`；当天 `Power.log` 的 `BuildNumber=255790`，且正常打了排位 | 【核实】 |
| hsdata 有 `255790` 这个 tag，三个 XML 都在；`256589` 是外服 37.0.2 | hsdata 提交记录 | 【核实】 |
| 卡牌数据版本只钉在 `HSTracker/cards-version.txt` 一处 | 全仓库搜 `255130`，另一处是 `docs/upstream-merges.md:107` 的历史记录 | 【核实】 |
| `HearthDb.dll` 只供战棋用 | `MonoHelper` 只加载 `BobsBuddy.dll` | 【核实】 |
| 拿不到日志目录就每秒重试，没有上限 | `CoreManager.swift:316-334` | 【核实】 |
| 游戏模式只从 HearthMirror 取 | `Game.swift` 约 L1431、L1832；`GameInfoHandler` 只解析 `BuildNumber=` 和 `PlayerID=` | 【核实】 |
| 我方 / 对手编号只从 HearthMirror 取 | 全仓库只在 `Game.swift:1429-1430`、`:1976-1977` 赋值 | 【核实】 |
| 编号缺失时，牌的归属判断全部失效 | `TagChangeActions.swift` 有 39 处 `player.id`；创建类 tag 的动作会一直排队，等 `determinedPlayers()` 为 true | 判断方式【核实】；牌表整体失效【推断】 |
| 2017 年有过只靠日志识别双方的逻辑 | 提交 `f30225cd` 删掉了 `determinePlayers` | 【核实】 |
| 「有名字的是自己」这一规则不可靠 | `Fixtures/ZoneReplay/2026-09-20-bug-t11.log` 第二局双方都显示 BattleTag | 【核实】 |
| `GameType=` 在 `PowerTaskList` 的 `CREATE_GAME` 之前出现 | 11-15 Power.log：第 2 行 `GameState` 的 CREATE_GAME，第 586 行 `GameType=`，第 597 行 `PowerTaskList` 的 CREATE_GAME | 【核实】 |
| `DynamicEntity` 会丢掉 `extraInfo` | `Player.swift:13` 起的 `init` 收了 `extraInfo` 参数却不赋值，`==` 和 `hash` 也不比较它；从 `e86b4407`（2024-12-18）起就是这样 | 【核实】 |
| `Entity.copy()` 会丢掉 `extraInfo` | `Entity.swift:265` 写成了 `e.info.extraInfo = e.info.extraInfo`，自己赋给自己 | 【核实】 |
| 卡条的分组和身份没有考虑组装 | `TrackerCardRowID`、`RowKey` 只带伊辛迪奥斯的字段；`TrackerCardRow ==` 比的是 `cardNameSuffix`；`Array.swift:29` 排序时把 `$0` 和 `$0` 比较（写错了） | 【核实】 |
| 悬浮提示只按卡牌 ID 取图和关联卡 | `TrackerRowCardPreview.request`、`setRelatedCardsTooltip` 都只传 `card.id` | 【核实】 |
| 组装牌的两个半边文本用 `&` 分隔，zhCN 文本里也有 | 例如 `BE_349` 的 zhCN 文本是「在你的英雄攻击后，&召唤……」；本地 `Card.formattedText()` 不会去掉 `&` | 【核实】 |
| 本地日志里没有组装牌的样本 | 本机 Power.log 和测试 fixture 里都没有大于 1 的 `CRAFTABLE_*_HALF_DBID` | 【核实】 |
| `BE` 这个 key 缺 zh-Hans | `Localizable.xcstrings` 里 `BE` 只有 de / en；国服官方译名在 `/Applications/Hearthstone/Strings/zhCN/GLOBAL.txt:165`：`GLOBAL_CARD_SET_BE` = 黑暗帝国的统治 | 【核实】 |
| 校验脚本已经支持放行新 key | `check_xcstrings.py` 有 `--allow-new-key`；E4 只比较新旧都有的 key | 【核实】 |
| ModHost 当前处于安全模式 | `state.json` 里 `safeMode.enteredAt = 2026-11-17T14:45:23Z` | 【核实】 |
| 本地 `master` 停在 3.7.0，可以离线快进 | `8d5ff469` 是 tag `3.7.1`（`782c881c`）的祖先 | 【核实】 |

## 4. 拆分与顺序

每个包从 `dev0923` 拉一个分支，验收通过后合回 `dev0923`，然后再开始下一个包。

**排顺序的依据**：会改同一批文件的包不同时进行。共用的文件有：

- `project.pbxproj`：包 2–7 都可能新增源码或测试文件；
- `PowerGameStateParser.swift`：包 3、包 4；
- `Core/Extensions/Array.swift`：包 2 修 `$0` / `$0` 的比较，包 6 再加按组装结果排序；
- `Game.swift`：包 4；
- `PLAN.md`：所有包。合并时如果 PLAN 冲突，两边的记录行都保留。

| 顺序 | 包 | 内容 | 依赖 | 文件 |
| :-- | :-- | :-- | :-- | :-- |
| 任意时候 | 包 0 | 规则与仓库整理（W4、W5、W6） | 无 | `packages/00-rules-repo.md` |
| 1 | 包 1 | 卡牌数据改成 `255790`（W1） | 无 | `packages/01-cards.md` |
| 2 | 包 2 | 修复 `extraInfo` 丢失（W3f） | 无 | `packages/02-extrainfo.md` |
| 3 | 包 3 | N'zoth、C'Thun、Gloomstone 三处移植（W3a–c） | 无 | `packages/03-small-ports.md` |
| 4 | 包 4 | 日志侧兜底：游戏模式、我方 / 对手识别（W2b、W2c） | 包 3 先合入，两者都改 `PowerGameStateParser.swift` | `packages/04-log-fallback.md` |
| 5 | 包 5 | 启动侧兜底和 Debug 开关（W2a、W2d），并做 W2 的整体实机验收 | 包 4 | `packages/05-startup-fallback.md` |
| 6 | 包 6 | 组装牌悬浮（W3e） | 包 2 | `packages/06-assemble-hover.md` |
| 7 | 包 7 | 发掘关联卡移植（W3d） | 无（排在最后，因为要改大量 pbxproj） | `packages/07-excavate.md` |

**实机验收合成三轮**，每轮一个 Debug 包：

1. **包 1–3 合入后**：正常打构筑。确认卡牌文本和国服一致；顺带看伊辛迪奥斯、N'zoth、C'Thun、Gloomstone，遇到就看，不专门去凑。
2. **包 4–5 合入后**：打开「模拟 HearthMirror 失效」开关打一到两局天梯，再关掉开关打一局，确认和平时一样。
3. **包 6–7 合入后**：正常打构筑。遇到组装牌和发掘牌时检查。

## 5. 未决问题（不排期，只记录）

| ID | 问题 | 已知证据 | 接手时的第一步 |
| :-- | :-- | :-- | :-- |
| O1 | 11-17 重启炉石后，开局时 HSTracker 连续三次停住 | 三次都停在 `LoadingScreenHandler` 的「Game mode from tournament to gameplay」之后，`Game Started` 没有出现；同一个炉石进程、同一份 `Hearthstone_2026_11_17_22_41_56/Power.log`；22:45 那次没有加载 mod；没有崩溃报告；包大概率基于 `5e6b89ac`【推断】 | `LoadingScreenHandler.swift:139-140` 调用 `gameStart`，`Game.swift:2017-2021` 在打印 `Game Started` 之前做了同步的 HearthMirror 读取。再碰到时 `sample HSTracker` 取一份调用栈；离线可以回放那份 Power.log |
| O2 | 退出炉石时 HSTracker 卡住（官方 3.7.4 修过） | 本机 11-17 22:41:50 那次退出约 40 ms 就完成了，没有复现 | 再碰到时取调用栈。主线程上的阻塞点有两处：`logReaderManager.stop()` 最多等 5 秒，`MirrorHelper.destroy()` 没有超时 |
| O3 | 伊辛迪奥斯计数不显示 | 已转为包 2：`extraInfo` 丢失是疑似原因【推断】 | 看包 2 的验收结果；包 2 合入后仍不显示，再从 `Game.swift:2836` 往下查 |
| O4 | 删卡组时崩溃（官方 3.7.4 修过） | 没有定位到代码 | 碰到再查 |
| O5 | 亚煞极计数在 37.0.3 后的口径 | 本地实现和 HDT 一致；「包含生命 / 护甲 / 尸体」的说法没有证据 | 用本地 `Power.log` 实测 `NUM_RESOURCES_SPENT_THIS_GAME` 的变化 |

## 6. 决策记录

| ID | 问题 | 决定 | 落到哪个包 |
| :-- | :-- | :-- | :-- |
| D1 | 新系列名要在 `.xcstrings` 里新增 key | 新系列名属于游戏内的新词条，不算例外，改规则来容纳：游戏新内容带来的词条随功能新增 key，zh-Hans 取国服客户端的官方译名 | 包 0 |
| D2 | `master` 要不要推到 origin | 不推，只在本地快进到 3.7.1 | 包 0 |
| D3 | 组装牌悬浮做不做 | 做。按实际游戏体验：记牌器里组装牌的悬浮页面**始终显示玩家组装后的卡牌**，卡条上仍用母牌的名字和费用 | 包 6 |
| D4 | 发掘移植新增的 26 个类怎么放 | 一类一个文件，和现有 1,180 个关联卡文件的布局一致，也和 HDT 一一对应；再加一个守护测试，逐张确认新卡都被识别到，把「漏登记静默失效」变成测试失败（Claude 决定） | 包 7 |
| D3 补充 | 实现时的默认做法（Claude 决定） | ① 我方和对手的记牌器、分区面板都按同一规则处理；② 同一张母牌组装成不同结果时，分成多行显示；③ 某一半的文本取不到时，悬浮退回显示母牌原图；④ 文本底板用代码绘制，不新增图片资源 | 包 6 |

## 7. 通用验收方式

- **构建**：AGENTS.md 里那条受限环境的 `xcodebuild` 命令，日常用 `build`，测试改成 `test`。
- **改了 `.xcstrings`**：跑 `python3 docs/tasks/tools/check_xcstrings.py --baseline <改动前 ref>`。
- **需要你实测时**，启动 Debug 包：

  ```bash
  open ~/Library/Developer/Xcode/DerivedData/HSTracker-batppbchpubuefehmmfbulefeevu/Build/Products/Debug/HSTracker.app
  ```

- **记录**：每个包完成后，在 `docs/PLAN.md` 的「提交记录」和「构建 / 测试记录」各补一行。

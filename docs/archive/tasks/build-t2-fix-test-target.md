# Build T2 — 让测试 target 能跑起来

先读 `docs/tasks/_common.md` 里的通用约束。

## 为什么做这件事

这个项目现在**每一次验收都要用户亲自开炉石打一局**。2026-08-30 一天里为了验四个修复
打了十几局。这是当前最大的瓶颈。

仓库里本来就有 `HSTrackerTests/`（`DatabaseTests` / `PowerParserTests` / `LogReaderTests` /
`SecretTests` / `AlgorithmTests` 等），但**测试 target 现在根本编不过**，所以一次都没跑过。
先把它救活，纯逻辑的回归才有可能不靠打一局来验。

## 现状

`xcodebuild ... build-for-testing` 现在两处失败（原文）：

```
HSTrackerTests/ReplayUploadTests.swift:10:8: error: unable to resolve module dependency: 'Wrap'

error: bridging header dependency scanning failure: In file included from
  HSTrackerTests/HSTracker-Test-Bridging-Header.h:26:
  HSTracker/HSTracker-Bridging-Header.h:23:10: fatal error: 'mono/jit/jit.h' file not found

** TEST BUILD FAILED **
```

两项在 3.6.5 基线和 3.6.7 上游都存在，不是本 fork 改出来的。

## 目标

`xcodebuild test` 能跑起来并给出结果。**不要求全绿** —— 有测试因为上游逻辑变化而失败是正常的，
那种失败要在报告里逐条说明是"真 bug"还是"测试过期"，但不要为了变绿去改被测代码。

## 硬约束

- **不许碰 app 的运行时代码。** `HSTracker/` 下的 `.swift` 一行都不要动。
  理由：Phase 0 / T6b 正在并行改刷新路径并做延迟测量，任何运行时改动都会污染它的数据。
  只允许动测试 target 自己的文件、`project.pbxproj` 的测试 target 配置、以及必要的依赖声明。
- **`project.pbxproj` 这次明确放开**（通用约束里那条"非必要不改"本任务不适用），
  但改动要局限在测试 target 的配置上，不要动 app target。
- **不许靠删测试来让它编过。** 如果结论是某个测试文件确实该删（比如它测的功能已经不存在了），
  要在报告里论证清楚，而不是为了绕过编译错误就删。
- 不要 `git add` 或 commit，不要动 `.xib`。

## 验收

1. 受限环境下测试能编译并运行：

   ```sh
   env -u http_proxy -u https_proxy -u all_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
     PATH=/usr/bin:/bin:/usr/sbin:/sbin \
     xcodebuild -project HSTracker.xcodeproj -scheme HSTracker \
     -configuration Debug -destination 'platform=macOS' test
   ```

2. app 本身的 Debug 构建仍然 `BUILD SUCCEEDED`（证明没碰坏 app target）。

3. 报告里给出：跑了多少个测试、过了多少、失败的逐条说明原因（真 bug / 测试过期 / 环境依赖），
   以及哪些测试**需要炉石在跑**才有意义（那些不算数，要标出来）。

4. 在本任务书里写清楚改了 `project.pbxproj` 的哪些地方、为什么 —— 下次合并上游要对账。

## 之后

跑得起来之后，`AGENTS.md` 的构建一节要补一条"改完跑一次测试"。那条等这本验收通过再加，
本任务不写。

## 执行结果（2026-08-31）

测试 target 已能编译、链接并实际执行；没有改 `HSTracker/` 下的运行时代码，也没有删除测试。

### 测试侧改动

- `ReplayUploadTests` 不再恢复已经移除的 `Wrap` 依赖，改为验证生产上传路径正在使用的
  `JSONEncoder` 输出，并把 2017 年的旧属性名对齐当前 `Player` 模型。
- `DatabaseTests` 删除两条 `Card.artist` 断言。这个字段在 2024 年切换 CardDefs 数据源时已经从
  生产模型删除，当前卡库没有可替代字段；其余卡牌字段断言和测试方法均保留。

### `project.pbxproj` 对账

改动只落在 `HSTrackerTests` target 及其专用引用：

- Debug / Release（`439C7E74` / `439C7E75`）的 Mono header path 从不存在的 `ios-arm` 改为
  `osx-arm64` / `osx-x64` 分架构路径，并把最低系统版本从 11.0 对齐宿主 app 的 14.0。
- 两个配置新增 `TEST_HOST` 和 `BUNDLE_LOADER`，指向构建出的 `HSTracker.app`。测试由此链接
  `@testable import HSTracker` 的真实实现。
- Sources phase（`439C7E58`）从 311 项收敛为 9 个测试文件。删掉的是 302 个 app 源文件的重复
  target membership 及其孤立 `PBXBuildFile`，不是测试；所有测试本来就导入宿主模块，旧清单既重复
  编译 app，又会因漏登记后来的源码而不断报“找不到类型”。
- Frameworks phase（`439C7E59`）删除只供测试 target 使用、且本机和仓库都不存在的旧
  `/Library/Frameworks/Mono.framework` 依赖及专用引用；同时删除已无使用者的旧 Mono library
  search path。宿主 app 自己的 CoreCLR 装配没有改。

### 实际测试结果

受限环境的完整命令执行了 **49** 个测试，**25 通过、24 个断言失败**（分布在 14 个测试方法），
没有 unexpected failure；同一份最终工程配置下，单独的 app Debug 构建为 `BUILD SUCCEEDED`。
24 个失败逐项归类如下：

- `DatabaseTests.testFromId`（1）：**测试过期**。当前 CardDefs 中 Dreadscale 的英文牌面已改为
  “deal 1 damage to all enemies”，测试仍写旧的 “all other minions”。
- `DatabaseTests.testGetFromName`（2）：一项是**测试过期**，当前 `CORE_EX1_249` 的 `CARD_SET=1810`
  对应 `.placeholder_202204`，不是 2021 年测试写的 `.core`；另一项是**测试环境耦合**，宿主 app
  先按本机 zhCN 加载进程级 `Cards.cards`，测试随后追加 enUS 却不清旧数组，按英文名取第一项时
  `card.text` 因而是中文。`card.enText` 仍是正确英文，不需要炉石进程。
- `SecretTests.testMultipleSecrets_MinionPlayed_MinionDied`（9）：**测试过期**。上游
  `c0fd1210` 已修正规则：随从后来死亡时，只有日志确认某张“打出随从”秘密实际触发，才撤销同批
  排除；旧测试没有喂触发日志，却仍期待九张秘密全部重新变为未知。
- 6 个 Bargain Bin 断言：**测试过期**。该秘密在 `f9adb591` 加入处理后，随从、法术或武器被打出
  都应排除；旧预期漏了它。涉及 `testMultipleSecrets_MinionPlayed_AnotherMinionDied`、
  `testSingleSecret_MinionPlayed`、两个 `testSingleSecret_*SpellPlayed`、`*ThirdThisTurn` 和
  `*MinionOnBoard*SpellPlayed`。
- 5 个 Mystic Misdirection 断言：**测试过期**。该秘密随 36.0 的 `9546652e` 加入，敌方随从发起
  攻击时就应排除；旧预期漏了它。涉及 `testMultipleSecrets_MinionToHero_*`、
  `testSingleSecret_MinionToDivineShieldMinion_*`、`testSingleSecret_MinionToHero_*`（两次检查）和
  `testSingleSecret_MinionToMinion_*`。
- `SecretTests.testSingleSecret_HeroToMinion_PlayerAttack` 的 Bait and Switch（1）：**测试过期**。
  友方随从被攻击正是这张秘密的触发条件，当前处理与卡面一致；该测试在其他同类分支已经把它写进
  预期，唯独漏了英雄攻击随从这一支。

结论：这轮没有发现运行时代码真 bug；失败是 23 个旧预期加 1 个测试夹具语言状态耦合。它们按任务
要求保留为可见失败，没有为了全绿改被测代码。

### 环境边界

- 现有 49 项都不需要炉石在运行：算法、枚举、上传编码和日志测试使用内存/硬编码数据；数据库与
  秘密测试使用 app bundle 的 CardDefs 和自行构造的 `Game(isRunning: false)`。
- `PowerParserTests.testCreateGameEntity` 方法体为空，虽然 XCTest 记为通过，但不能当作解析器验证。
- Secret suite 每例都会创建 `Game` / `WindowManager`，本轮超过 100 个存活窗口后 AppKit 给出警告；
  没影响这次结果，但这是测试清理层的后续风险，不是炉石环境依赖。

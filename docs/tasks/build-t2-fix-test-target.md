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

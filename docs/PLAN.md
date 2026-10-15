# HSTracker 个人分支：记录

最后更新 2026-10-15。只记三样：提交记录、构建 / 测试记录、项目细节。10-14 之前的计划、待办、待定项和排查经过
已整份归档（`docs/archive/plan-2026-10-14.md`、`docs/archive/refork-2026-09.md`、`docs/archive/tasks/`），按「已读、已决定」处理，不再跟进。

`HearthSim/HSTracker` 的个人自用 fork，不回流上游。分支 `dev0923`，基座上游 **3.7.0**（`8d5ff469`，10-15 合入 `b227ef15`；09-23 从 3.6.12 换轨重建）；
旧线 `dev`（基座 3.6.9，`647c310d`）冻结作回滚点；`master` 是上游纯镜像。上游合并见 `docs/upstream-merges.md`。

## 提交记录

| 内容 | 提交 |
|---|---|
| 地基：驱动循环 / 窗口层 / 部署目标 14.0 / 16ms 刷新合并 | Phase 0 T0–T6（旧线）；新线 REFORK S1 `17302764`、S5 `cc0fa753` + `d589ff8a` |
| SwiftUI 记牌器 + 动效 | Phase 1 T1–T8，T8 `2e9713b5`；新线 S4 `8c2a4081` |
| 合上游 3.6.7 / 3.6.8 / 3.6.9 / 3.6.13 / 3.7.0 | `eaa55850` / `5835f8a4` / `9da27c8e` / U4 / U5 `b227ef15`（HearthMirror 升 `ec7b1d7e`，shim 已撤；BobsBuddy 1.92.7 / HearthDb 37.0.0） |
| 换轨到 3.6.12（REFORK S0–S8） | S2 `3883c940`、S3 `687aa134`、S6a `8a86299d`、S6b `a8e59f43` / `2618be4b` / `b12ead8c` / `7312c31c`、S7 `aae3f397`、S8 `54576cce` |
| 牌库 / 手牌 / 已打出分区 | T1 `1c44b212`；Bug T6 `e9a67db6` / T7 `7bd3192b` / T8+T9 `68ccc14e` / T10 `04dae47a` / T11 护栏 `f8fa4c86` |
| 视觉重做与掉帧 | V1 `e3797ba8`；V2a+V2b `1745adfa`；Perf P1+P2 `143db6f3`；2.7 状态图标 `7dbc86b1` |
| 2.9 骷髅只标死亡随从 | `296572ef` |
| 2.10 记牌器滚动 + 段头折叠 | `b35ca384` |
| 简体中文 945 / 945 | Phase 3（旧线）；新线 S2 注入 |
| Dock 打勾 + Toast、菜单栏按 tag 定位 | `35fea72a`（S6a 搬新线） |
| 排队显示牌组、局末小结窗 | Phase 6 / 7；新线 S6a / S6b |
| 包体瘦身（不打包 `HearthDb.xml`，.NET 基础库只嵌本架构） | PR #3 `aecd42bf` |
| 红龙贼 combo 提示器 | T0+T1 `0a921d6b`；T2a `d73f8a6`；T2b `61fbcbd`；T2c `359916c`；T3 跟手 `507d354`；T4 奶 16 + 完整公式 `a3326ac`；T5 引擎核对 `35a783f6`；T6 面板 1.6 倍 `1f6384bf`；T7 跟手延迟 `cf73e238`；T8 破冰 `8f5a1636` + `2a126604` + `d8da0b4b` + `e2a85b3d` |
| 红龙解耦与 mod 化（评估 `docs/research/red-dragon-mod-eval.md`） | M1 引擎包挪到 `Packages/RedDragonCore/`、去掉 `sources:` 点名、pbxproj 删 12 条导航引用；M2 引擎立公开接口（顶层 53 个类型标 `public`，比评估的 30 个多出的是 public 签名连带的；`-enable-testing` 只在 Debug，app 侧改普通 `import`）；M3 拆测试：只碰引擎的 100 条（`RedDragonTests` 54、`RedDragonIceBreakTests` 32、`RedDragonSetupTests` 6、`RedDragonFormulaTests` 8 整个）挪进包的 `RedDragonCoreTests`，`formulas.json` / `sim.py` 跟着挪，HSTrackerTests 留 105 条（分支 `claude/project-thread-rdkiom`） |

## 构建 / 测试记录

| 日期 | 范围 | 结果 |
|---|---|---|
| 10-15 | M3 拆测试：`swift test`（包，不启动 app）、app `build-for-testing` | 包 100 条过（跳过 1 条：生产配置 CPU 只在 -O 下测，和原来一样），125 秒；两边合计 205 条与拆前相同；HSTrackerTests 里的 105 条未跑（在打炉石） |
| 10-15 | M2 引擎立公开接口：包 `swift build` Debug / Release、app Debug 增量 build、`build-for-testing` | 都通过；红龙测试未跑（在打炉石） |
| 10-15 | M1 引擎包挪目录：`swift build` 单独编包、Debug clean build（独立 DerivedData，复用本机包缓存） | 都通过；红龙测试未跑（当时在打炉石，测试会启动 Debug 包） |
| 10-15 | 合上游 3.7.0：Debug clean build、全套（跳过 `LocalizationFormatTests`，负载 4.5）、Release clean build | 549 条挂 4 条：签名、反射断言（上游修好，测试已改）、红龙回放 2 条（CPU 预算抖动，单跑有全过）；Release 3.7.0 通过 |
| 10-14 | 全套，受限环境，跳过 `LocalizationFormatTests`（T8 破冰终版） | 547 条：541 过 / 5 跳过 / 1 失败（签名，自编译包预期内），536 秒 |
| 10-14 | 包体瘦身合入后 Debug 构建 + 启动 | 通过 |
| 10-13 | 全套（T7） | 499 条，只挂签名 1 条 |
| 10-07 | 全套（T5） | 482 条，只挂两条老的；红龙组 153 条 0 失败 |
| 10-06 | 全套（T4，炉石开着、负载 5.6） | 470 条，6157 秒，挂 5 条（签名 + 4 条卡时间）；同日空闲时只挂签名和本地化 |
| 09-29 | 全套（合上游 3.6.13） | 324 条 |
| 09-23 | 基线（3.6.12 原样） | 151 条，只挂签名 |

**本机性能测试**（最近一次 10-09 晚，包内 `PerfLog` 来自没合的 PR #4，数据不在仓库里）：
- 帧时间 A/B，`~/Desktop/dev/HSTracker-perf-builds/frames/`：不开 HSTracker 均 159.7 fps；官方包 137.6；我们的 Release 134.8；Debug 113.5（1% low 49.4 / 57.0 / 55.6 / 46.2）。
- 每局性能日志，`~/Library/Logs/HSTracker/perf/`，10-09 22:58 ～ 10-10 00:38 天梯 8 局：CPU 平均 21–34%、p95 52–68%；内存峰值 303–498 MB；主线程卡顿 p95 10–20 ms、最大 24–178 ms。
- 之后合进 `dev0923` 的：2.9、2.10、红龙 T6 / T7 / T8、包体瘦身（PR #3）、上游 3.7.0。

## 与上游的默认值差异

合并上游时最容易被静默还原（代码注释引用本节）：

| 键 | 上游 | 本 fork | 说明 |
|---|---|---|---|
| `show_mulligan_toast` | true | **false** | 留牌时右下角 HSReplay 引流浮窗 |
| `group_cards_by_zone` | — | true | 分区 |
| `hide_all_trackers_when_not_in_game` | 控件在 | 控件已撤，声明保留给老 defaults | 改走场景门后无读者 |
| `show_constructed_session_recap` | — | true | 局末小结 |
| `keep_power_log` | — | true | `Power.log` 不截断 |
| `tracker_motion`、`tracker_perf_*` | — | 诊断键，不进设置页 | — |
| `red_dragon_assist` / `red_dragon_reveal_level` / `red_dragon_quiz_mode` | — | false / 0 / false | 红龙，热切换 |

合并还要保住：`NET_VERSION = net8.0`；`MACOSX_DEPLOYMENT_TARGET = 14.0`；`Card.copy()` 补拷 `enText`；
`RealmHelper.add(mirrorDeck:)` 补存 sideboard（`507d354`，不补则新导入套牌首局 E.T.C. 为空、红龙 overlay 不出）。

## 项目细节

- Release 包：`open ~/Library/Developer/Xcode/DerivedData/HSTracker-batppbchpubuefehmmfbulefeevu/Build/Products/Release/HSTracker.app`（10-15 起本机只留这一个包，Debug 包已清；要 Debug 包时增量 build，交测前看 `Contents/MacOS/HSTracker.debug.dylib` 的时间 ≥ HEAD 提交时间）。
- 回旧线：`git checkout dev`（origin 上也有）。
- HearthMirror 闭源，只能从 `libs.hearthsim.net/hstracker/<sha>/` 拿，合上游前先 `curl -I` 一下新 pin；Download 阶段失败会先 `rm -rf` 缓存，重跑前别慌。
- 探针 `HSTRACKER_LATENCY_PROBE=1`（Release 包读 `~/Library/Logs/HSTracker/hstracker.log`）；掉帧分析 `docs/tasks/tools/frame_gaps.py`，跨录像对比加 `--busy`。
- 环境：`brew install wget`（两个 build phase 依赖）；`Config.xcconfig` 本地签名（个人 Apple Development 证书，Team `DY725KK25V`）+ `skip-worktree`，换机器重做；SwiftLint 故意不装；git 身份 repo-local。
- SwiftPM 在受限环境拉不到 github.com 时，临时加 `GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.https://github.com.proxy GIT_CONFIG_VALUE_0=<原 https_proxy>`。
- 沙箱首次跑测试会因 swiftpm 缓存无权失败，本机权限重跑；`DatabaseTests` 断言英文用 `card.enText`。测试宿主启动偶发崩一次后自动重启，退出码 65 但条数全过，以条数为准。
- Release 包只写 `~/Library/Logs/HSTracker/hstracker.log`；首次从 `Build/Products/Release` 启动被 AppMover 模态框挡住，点 Don't Move。排查渲染前确认包内有 `Contents/Resources/CardDefs.bin`、`Contents/Resources/Managed/`。
- build phase 的 inputs 必须覆盖真正读的东西；`Embed Mono` 整拷 `net8.0` 目录；vendored 安装阶段保留 staging → 校验 → `cp`；代理 `127.0.0.1:7890` 探到才设；`grep -c 新文件.swift project.pbxproj` 应为 3~4。
- `-configuration Release` 下测试 target 编不过（`HSTracker-Test-Bridging-Header.h:13` 找不到 HockeySDK）。
- 红龙引擎测试：`cd Packages/RedDragonCore && swift test`（同样去掉代理环境变量、`PATH=/usr/bin:/bin:/usr/sbin:/sbin`），不启动 app、不读卡库；要 HSTracker 在场的红龙测试仍在 HSTrackerTests。
- 红龙解耦 / mod 化评估（10-15，只评估，没动代码）：`docs/research/red-dragon-mod-eval.md`。结论是让 HSTracker 支持 mod、红龙做成第一个 mod，分三阶段，第一阶段是仓库内解耦。

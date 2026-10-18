# HSTracker 个人分支：记录

最后更新 2026-10-18。只记三样：提交记录、构建 / 测试记录、项目细节。10-14 之前的计划、待办、待定项和排查经过
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
| 红龙贼 combo 提示器 | T0+T1 `0a921d6b`；T2a `d73f8a6`；T2b `61fbcbd`；T2c `359916c`；T3 跟手 `507d354`；T4 奶 16 + 完整公式 `a3326ac`；T5 引擎核对 `35a783f6`；T6 面板 1.6 倍 `1f6384bf`；T7 跟手延迟 `cf73e238`；T8 破冰 `8f5a1636` + `2a126604` + `d8da0b4b` + `e2a85b3d`；T9 破冰改按下回合手里阿莱张数排序、下回合伤害不算场上随从（口径 15，`docs/research/red-dragon-card-model.md` J3；分支 `claude/project-thread-t36isn`） |
| 食魂者之镰 / 受缚之魂悬浮显示被吞食的随从（解析镰刀开局块亮到 SETASIDE 的随从记到镰刀 `storedCardIds`；新增 `BoundSoul` 关联卡牌类） | 分支 `claude/project-thread-1suo58` |
| 红龙解耦与 mod 化（评估 `docs/research/red-dragon-mod-eval.md`） | M1 引擎包挪到 `Packages/RedDragonCore/`、去掉 `sources:` 点名、pbxproj 删 12 条导航引用；M2 引擎立公开接口（顶层 53 个类型标 `public`，比评估的 30 个多出的是 public 签名连带的；`-enable-testing` 只在 Debug，app 侧改普通 `import`）；M3 拆测试：只碰引擎的 100 条（`RedDragonTests` 54、`RedDragonIceBreakTests` 32、`RedDragonSetupTests` 6、`RedDragonFormulaTests` 8 整个）挪进包的 `RedDragonCoreTests`，`formulas.json` / `sim.py` 跟着挪，HSTrackerTests 留 105 条；M4 合入 ModKit / ModHost，app 适配层 `HSTracker/Mods/`（mod 管理器、对局 / 实体适配、宿主服务和 mod 设置存取、overlay 图层、设置窗「Mod」分组），5 处挂点改调 `ModManager`，红龙胶水改走 ModKit、作为内置 mod 仍编在 app 里，设置键改成 `mod.red-dragon.*`（老 `red_dragon_*` 键启动时抄一次、不删）；M5 红龙胶水 8 个文件挪到 `Mods/RedDragon/`（SwiftPM 动态库 + 入口 `hstracker_mod_entry`，`build.sh` 编 Release、把 ModKit 依赖改指 app 里的 `ModKit.framework`、ad hoc 签名，`--install` 装进 Mods 目录），app 不再含红龙（RedDragonCore 也移出 app target），HSTrackerTests 直接编 mod 源码（除入口文件）、Debug 加 `-DDEBUG`（分支 `claude/project-thread-rdkiom`） |

## 构建 / 测试记录

| 日期 | 范围 | 结果 |
|---|---|---|
| 10-18 | 食魂者之镰关联卡牌：Debug 增量 build、全套 HSTrackerTests | build 通过；455 条 450 过 / 4 跳过 / 1 失败（签名，自编译包预期内），575 秒；游戏内悬浮未实测 |
| 10-16 | T9 破冰口径 15（炉石关着）：包 `swift test`；全套 HSTrackerTests（含新加的两局对法师 fixture）；152 个局面（12 局逐回合当对方挂冰，原血和改 12 血）新旧对比 `8d0458c6`，确定性 + 生产配置、-O | 包 103 条 102 过 1 跳过；全套 455 条 450 过 / 4 跳过（按需开的红龙）/ 1 失败（签名，自编译包预期内），540 秒；结论档不变（可斩 24 / 差一点 6 / 破不了 122），22 行换了路线，下回合手里阿莱没有一行变少，旧版 9 行「0 张阿莱报可斩」都留下 1–4 张；最慢 1.11 s，合计 19.0 → 20.8 s，没撞 CPU 兜底 |
| 10-16 | M5 验收（炉石关着）：包 `swift test`；HSTrackerTests 红龙 7 个类；10 局 fixture 逐回合导出（`describe`，确定性配置）对比 M4 之前的 `ab35b73f`（独立目录、独立 DerivedData）；Debug 包装 mod 启动 | 包 100 条 99 过 1 跳过；红龙 105 条 101 过 4 跳过（按需开的 4 条，基线同样跳过）0 失败，基线同；10 局 71 行逐回合一致（去掉 CPU 秒；整套跑时卡名语言随测试宿主卡库加载先后变，单跑两边逐字节一致）；mod 已加载、已启用，老设置抄到 `mod.red-dragon.*`，正常退出不进安全模式。顺手修：`ModManager.start()` 挪到 logger 建好之后，原来加载日志全丢 |
| 10-16 | M5 红龙搬成 mod：`Mods/RedDragon/build.sh`（导出入口、不带 ModKit）、app Debug 增量 build、`build-for-testing` | 都通过；app 二进制里红龙符号 0 个，测试包里有；105 条红龙测试、回放逐回合比对、Debug 包加载 mod 未跑（在打炉石） |
| 10-16 | M4 适配层 + 红龙改走 ModKit：Debug 增量 build、`build-for-testing`（HSTrackerTests 链接 ModKit，app 里只有一份 ModKit.framework） | 都通过；HSTrackerTests 里的 105 条红龙测试未跑（在打炉石） |
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
| `mod.red-dragon.assist` / `.revealLevel` / `.quizMode`（老键 `red_dragon_*`） | — | false / 0 / false | 红龙 mod，热切换 |

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
- mod：app 侧只在 `HSTracker/Mods/` 接 ModKit（上游改宿主类型时只改这层）；`~/Library/Application Support/HSTracker/Mods/` 里的动态库由 ModHost 加载，启动时按住 ⇧ 进安全模式；设置窗「Mod」页的开关下次启动生效；跑测试时不扫 Mods 目录（测试宿主退出不走 `applicationWillTerminate`，会被当成崩溃）。红龙测试的设置用单独的 UserDefaults 域（`RedDragonTestSupport.swift`）。红龙 mod：`Mods/RedDragon/build.sh --install`（受限环境，装到 Mods 目录；Release 3.7.0 不读这个目录），改了 mod 源码要重装再重启 HSTracker。
- 红龙解耦 / mod 化评估（10-15，只评估，没动代码）：`docs/research/red-dragon-mod-eval.md`。结论是让 HSTracker 支持 mod、红龙做成第一个 mod，分三阶段，第一阶段是仓库内解耦。

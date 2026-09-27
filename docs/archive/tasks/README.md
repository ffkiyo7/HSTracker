# 已完成的任务书

`docs/tasks/` 只放在做和待验的；验收通过就挪到这里。留档是为了回答「当初是怎么下的约束」——
尤其几次「按任务书字面实现反而与现状不符」的 review 改动，光看代码看不出来。结论去 `docs/PLAN.md`，
过程去 `docs/archive/progress-*.md`。

两条路径规则：① **归档后文件里的相对路径故意不改**（`docs/tasks/xxx.md` 现在都在这里），留档就该是当初交出去的原文；
② `_common.md` 不归档，在做的书都引用它；只有 Phase 3 专用的 `_common-phase3.md` 跟着六本书进来了。
例外：**事实错误改**。「深邃之王」是硬译、炉石里没有这张卡，已就地改成「下水道之王」（`JAIL_831`）；用户口中的「牛头人」= ETC（`ETC_080`）。

## 批次

| 批次 | 归档的 | 依据 |
|---|---|---|
| 1（08-30） | `phase0-t1`…`t5`、`phase1-t1/t2/t3/t4/t7`、`phase3-t1`…`t6` + `_common-phase3.md` | Phase 0 T1–T5 ✅；Phase 1 五片卡点 ① 实战；zh-Hans 945 / 945 |
| 2（08-30） | `phaseU-t1-outfinder-stale-tile`、`phase6-t1-queue-residue`、`build-t1-vendor-managed-deps`（`756e08a5`）、`bug-t1-viewmodel-offmain-writes`（`ac116be0`）、`bug-t2-tier7-prelobby-in-constructed`（`eb52832e`）、`bug-t3-opponent-tracker-shows-player-cards`（`999f2eee`） | 卡点 ① 那一局的五条反馈全部结案。T2 / T3 两本刻意留白（只给症状与证据），两次都被执行侧推翻了 review 的读法 —— **交叉检验要留出被推翻的余地** |
| 3（09-03） | `phase0-t6b-shrink-refresh-cost`（`b0374928` / `c19b0bd7`）、`bug-t4-tracker-visibility-out-of-game`（`381a9c80`）、`build-t2-fix-test-target`（`10c6a812`） | T6b 值得回看它写死的判据（「补集最大就不进优化」）和第 3 步取消的理由；Bug T4 的四条副作用生出了 Bug T5 |
| 4（09-04） | `bug-t5-tracker-visibility-consistency` | 09-03 实战「结算瞬间一起消失」 |
| 5（09-13） | `phase1-t5-tracker-header`（`ddde2cae`）、`phase1-t6-tracker-root-layout`（`e7beb430`）、`phase4-t1-dock-menu-and-settings`（`35fea72a`）、`phase7-t1-session-recap-window`（`0af024d7`） | 卡点 ②③ + Dock + 小结窗实战通过。T6 值得回看为什么没用 `GeometryReader`（`bottomY` 要和渲染高度同源） |
| 6（09-22） | `phase2-t1-zone-groups`（`1c44b212`）、`bug-t6`（`e9a67db6`）、`bug-t7`（`7bd3192b`）、`bug-t8` + `bug-t9`（`68ccc14e`）、`phase2-v1-vector-card-bars`（`e3797ba8`）、`phase2-v2a` + `v2b`（`1745adfa`）、`perf-p1` + `perf-p2`（`143db6f3`）、`refork-prep`（`d309a8ff` / `7c0f2390` / `892873de`）、`spike-rdr-t1-search-core`（`0a921d6b`，⏸ 暂缓） | 全部已提交；分区 / 视觉 / 掉帧的实战由 09-18～09-21 的对局覆盖（后续 Bug T10 / T11 即由此产出）。P1 末尾「🎮 实测结果」记着四条为什么没命中 |

| 7（09-23） | `phase1-t8-tracker-motion`（`2e9713b5`，卡点 ④ 通过） | 书末有 review 第一轮「两半都齐了再定」的改法，和 120 fps 录像的逐帧数据；三个时长常量没调 |
| 8（09-23，补登） | `refork-s1-build-layer`（`dev0923` `17302764`）、`refork-s2-l10n`（`3883c940`） | REFORK 第一批 review 过（Claude + Fable）。S1 书末记着 dev 的 BobsBuddy 从未加载成功（DLL 放错位置） |
| 9（09-26） | `refork-s3-zone-data`（`687aa134`）、`refork-s5-refresh-perf`（`cc0fa753`）、`refork-batch2-fixes`（`d589ff8a`）、`refork-s6a-small-fixes`（`8a86299d`）、`refork-s7-red-dragon`（`aae3f397`） | 均在 `dev0923`；第二 / 三批 review（Claude + Fable + Codex）+ 09-26 实测。`batch2-fixes` 值得回看：两条真 bug（LRU 淘汰后永久缺图、高亮落到手牌区）是不看任务书的 Codex 挖出来的 |
| 10（09-27） | `refork-s4-panel-on-canvas`（`8c2a4081`）、`refork-bug-unlocked-overlay`（`ab723fda`）、`refork-unlocked-box-outline`（`5ff7f87c`） | S4 09-26 实测 + 09-27 解锁复测过。两本解锁书值得回看：标题栏和拖动闪烁都是上游 3.6.12 原有、被 S5 高频刷新放大；HDT 的 `#4C0000FF` 染色框不是 bug 但不可用 |

`phase3-t1-diff-report.md` 不是任务书，是 gaenyong 与我们译法不同的 77 条对照表。

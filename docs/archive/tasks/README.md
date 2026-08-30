# 已完成的任务书

`docs/tasks/` 只放**在做和待验**的任务书。一本书对应的切片验收通过之后就挪到这里。

结论不在这些文件里 —— 任务书写的是「要做成什么、不许碰什么」，不是「最后做成了什么」。
想知道结果去 `docs/PLAN.md` / `docs/PROGRESS.md`，想知道过程去
`docs/archive/progress-detail-2026-08-22.md`。**这些文件留档是为了回答「当初是怎么下的约束」**
—— 尤其是几次「按任务书字面实现反而与现状不符」的 review 改动，光看结果代码是看不出来的。

## 归档时间

### 第一批：2026-08-30（卡点 ① 实战通过之后一次性整理）

| 归档的 | 完成于 | 状态依据 |
|---|---|---|
| `phase0-t1` … `phase0-t5` | 2026-08-20 ~ 08-21 | Phase 0 T1–T5 全部 ✅ |
| `phase1-t1` / `t2` / `t3` / `t4` / `t7` | 2026-08-20 ~ 08-29 | 五片均已实战（T3 / T4 / T7 在 08-30 的卡点 ① 过） |
| `phase3-t1` … `phase3-t6` + `_common-phase3.md` | 2026-08-22 | zh-Hans 945 / 945（Phase U 补课后） |

### 第二批：2026-08-30 晚（卡点 ① 那一局产出的五条反馈全部结案）

| 归档的 | 完成于 | 状态依据 |
|---|---|---|
| `phaseU-t1-outfinder-stale-tile` | 08-30 | 卡池浮窗串卡，实战确认「串卡没了」 |
| `phase6-t1-queue-residue` | 08-30 | 排队时显示完整牌组，实战确认 30 张全在 |
| `build-t1-vendor-managed-deps` | 08-30 | BobsBuddy / HearthDb 制品固定进仓库（`756e08a5`） |
| `bug-t1-viewmodel-offmain-writes` | 08-30 | 790s 主线程死锁，hang report 定位 + 实战验收（`ac116be0`） |
| `bug-t2-tier7-prelobby-in-constructed` | 08-30 | 构筑局弹战棋浮窗，T1 的时序回归（`eb52832e`） |
| `bug-t3-opponent-tracker-shows-player-cards` | 08-30 | 我方奇闻被算进对手牌库预测（`999f2eee`） |

> **这三本 bug 书值得回看的地方是「怎么下的约束」，不是结论。** T2 / T3 两本是刻意
> **留白写的** —— 只给症状、证据和 review 侧的待验说法，明确写「review 可能读错，
> 独立复核后直说哪条不成立」。两次都生效了：T2 里 Codex 推翻了 review 的「最终仍会隐藏」
> （review 漏看了 `propertyChanged` 闭包里的一层 `main.async`），T3 里 Codex 证伪了
> 任务书给的 A / B 两条线索、查出了第三条路径。**交叉检验要留出被推翻的余地才有价值。**

`phase3-t1-diff-report.md` 不是任务书，是 T1 产出的「gaenyong 与我们译法不同的 77 条」对照表，
一起放这儿。

## 两条路径提醒

1. **归档后的相对路径没有跟着改。** 这些文件里写的
   `docs/tasks/_common-phase3.md`、`docs/tasks/phase1-t1-card-row.md` 之类，现在都在
   `docs/archive/tasks/` 下。**故意不改** —— 留档就该是当初交给执行模型的那份原文，
   改了它就不再是"当初下的约束"了。`docs/archive/*.md` 里指向这些书的链接同理。
2. **`_common.md` 没有归档**，它还在 `docs/tasks/`：Phase 0 / T6 和另两本在做的书都在引用它。
   只有 Phase 3 那份专用的 `_common-phase3.md` 跟着它的六本书一起进来了。

## 勘误（2026-08-30）

**「深邃之王」→「下水道之王」。** 备牌那张猎人传说是 `JAIL_831`
（`CardIds.Collectible.Hunter.KingOfTheUnderbelly`，enUS `King of the Underbelly`），
官方简中是**「下水道之王」** —— Underbelly 指达拉然的下水道。
「深邃之王」是我们从英文硬译出来的，炉石里根本没有这张卡（整个 `CardDefs.xml` 零命中）。
`phase1-t3-sideboard-hover.md` 和 `../plan-detail-2026-08-22.md` 里的写法**已就地改正**。

> **这一处例外于上面第 1 条。** 那条护的是「当初下的约束和措辞」；
> 卡名写错是**事实错误**，留着只会让以后读档的人去找一张不存在的卡。
> 相对路径不改、错的卡名改，界线就在这里。

顺带记一个同源的口误：用户口中的**「牛头人」就是 ETC**
（`ETC_080`，官方全名「乐队经理精英牛头人酋长」），不是另一张卡。


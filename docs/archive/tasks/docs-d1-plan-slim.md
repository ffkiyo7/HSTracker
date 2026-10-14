# Docs D1 — 给 `PLAN.md` 瘦身，归档能归档的任务书

先读 `docs/tasks/_common.md` 和 `AGENTS.md`「文档」一节；本书的规则全部以那一节为准。实现分支：从最新 `dev0923` 切 `docs/slim`。
**开工条件：FF 本机 `docs/PLAN.md` 的未提交改动、本机那三本没推的任务书都已提交到 `dev0923`。** 否则一定冲突。
按项目目标，本书排在滚动和 P3–P6 之后做最好：那几本收尾时都要改 `PLAN.md`。

## 为什么

每个代理会话开头都要读 `AGENTS.md`（3.9 KB）、`docs/tasks/_common.md`（1.5 KB）和 `docs/PLAN.md`。
`PLAN.md` 是大头：145 行、23.6 KB（`35a783f6` 时），很多行是一整段。红龙 T4 / T5 的过程细节占了很大一块，而这些细节在各自任务书的书末都已经有了。
`docs/` 一共 86 个 Markdown、1.27 MB，但除了 `PLAN.md`，其余只有点名时才会读。

## 要做出什么

1. **`PLAN.md` 按 `AGENTS.md` 的规则清一遍。**
   - 已完成、已拍板、已提炼成一行的内容，整段挪进 `docs/archive/plan-<当天日期>.md`。
   - 进行中的条目只留一行状态 + 依据（commit / 日期 / 任务书路径），过程和数字留在任务书书末。书末没有的才挪进归档，不能丢。
   - 对照 `git log` 改掉过时的状态。例：`35a783f6` 已提交红龙 T5 修复，PLAN 还写着「改动在工作区，没提交」。
   - 目标：`PLAN.md` ≤ 12 KB。做不到就写清卡在哪。
   - 「决策理由、数字、路径、命令、未决问题只能挪位置，不能丢」（`AGENTS.md`）：每处删改都要能在归档或任务书里找到原文。
2. **`docs/tasks/` 按「归档看状态」清一遍。** 能归档的挪进 `docs/archive/tasks/`，并在 `docs/archive/tasks/README.md` 的批次表登记一行。🚧 / 🎮 / ⬜ / ⏸ 的一律留着。
3. **研究图片。** 不删任何被引用的图：`red-dragon-formulas-1.png` 和 `-1-hires.png` 都被 `docs/research/red-dragon-rogue-spike.md:335-336` 引用。本机有 `oxipng` / `pngcrush` 就无损压一遍，没有就跳过。

## 不在本片

- `HSTrackerTests/Fixtures/` 的 30 MB 日志：改它要动测试；里面的 BattleTag 要清干净得改写历史（PLAN「等你定」的隐私条）。等用户定。
- 上游留下的 `CHANGELOG.md`、`fastlane/`、`.travis.yml`、`Gemfile`、README 图片：还会合上游 tag（Phase U4 先例），删了每次合并都会冲突。
- 给 `docs/archive/` 加 `.ignore`，让代理搜索跳过归档：省搜索噪音，但也会让人找不到「当初怎么定的」。只在报告里提建议，不做。

## 硬约束

- 只动 `docs/` 下的文件；`docs/archive/` 里的原文不改（事实错误除外，`AGENTS.md`）。
- 已完成的东西归档，不划线，不手写 `~~`（`AGENTS.md`）。
- 纯文档，不需要构建，在哪做都行。在云端做时就开 PR 到 `dev0923`，PR 就是 `_common.md` 说的「由人 review 后统一提交」那一关。

## 允许修改的文件

- `docs/PLAN.md`、`docs/tasks/*.md`（只挪不改）、`docs/archive/` 下新建的归档文件、`docs/archive/tasks/README.md`
- `docs/research/assets/*.png`（只无损压缩）

## 验收

1. 汇报里有一张「挪动清单」：每一段从哪挪到哪（文件 + 小节）。
2. `PLAN.md` 前后的字节数和行数。
3. `PLAN.md` 里引用的每个路径都还存在（用 `rg -o` 抽出来逐个 `test -e`，输出贴进报告）。
4. 用户读一遍新 `PLAN.md`，确认能看出「现在在做什么、等谁定什么」。

## 汇报

结果写进本文件末尾「执行结果」一节。

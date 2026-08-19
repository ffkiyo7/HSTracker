# Phase 3 / T1 —— 合并 gaenyong fork 的现成中文翻译

先读 `docs/tasks/_common-phase3.md` 里的通用约束，再读本文件。

## 背景

`gaenyong/HSTracker@9e7b653f`（"Update Simplified Chinese translations"，2026-07-16）里有一批现成的简体中文，
能直接补上我们缺的 410 条里的 **139 条**。upstream 是 MIT，复用没有许可问题。

那个 commit 的 16 个 `.xcstrings` **我已经预先下载好**，放在：

```
.refs/gaenyong-9e7b653f/<与仓库同构的路径>
```

例如 `.refs/gaenyong-9e7b653f/Translations/macOS/Localizable.xcstrings` 对应
仓库里的 `Translations/macOS/Localizable.xcstrings`。

**不要联网去 fetch 那个仓库**，直接用 `.refs/` 下的文件。`.refs/` 只读。

## 目标文件

`.refs/` 里那 16 个文件所对应的仓库内同名 `.xcstrings`，**只有这 16 个**。
其中 7 个会真的被补上内容，另外 9 个只在「差异报告」里出现。

## 要做的改动

### 第一步：按 key 合并 139 条空缺（这是本任务的产物）

对每个 key：**我们缺 zh-Hans、而它有 zh-Hans → 采纳它的值**，`state` 写 `"translated"`。

预期结果（写个脚本做，做完必须与下表逐行对上）：

| 文件 | 应补 |
|---|---|
| `HSTracker/UIs/mul.lproj/MainMenu.xcstrings` | 41 |
| `Translations/macOS/Localizable.xcstrings` | 67 |
| `HSTracker/UIs/StatsManager/mul.lproj/LadderTab.xcstrings` | 12 |
| `HSTracker/UIs/Preferences/mul.lproj/PlayerTrackersPreferences.xcstrings` | 6 |
| `HSTracker/UIs/Preferences/mul.lproj/OpponentTrackersPreferences.xcstrings` | 5 |
| `HSTracker/UIs/Preferences/mul.lproj/TrackersPreferences.xcstrings` | 4 |
| `HSTracker/UIs/StatsManager/mul.lproj/StatsTab.xcstrings` | 4 |
| **合计** | **139** |

数字对不上就停下来查，**不要**为了凑数去改判定规则。

### 第二步：把 77 条「它译得不一样」的写成报告（不要采纳）

我们**已有** zh-Hans、它**也有**且**不同**的 key，共 77 条。这些**一条都不要动**，
写进 `docs/tasks/phase3-t1-diff-report.md`，由人逐条决定。格式：

```markdown
# T1 —— gaenyong 与我们译法不同的 77 条

## Translations/macOS/Localizable.xcstrings（31 条）

| key | 英文 | 我们的 | gaenyong 的 | 建议 |
|---|---|---|---|---|
| `Show opponent hero and name` | Show opponent hero and name | 显示对手英雄和名字 | 显示对手职业和名字 | 采纳它 |
```

「建议」一栏写你的判断（`采纳它` / `保留我们的` / `都不好，理由…`），并给一句话理由。
判断依据是 `_common-phase3.md` 的术语表和界面语境，不是"谁更长"。

预期条数分布（对不上就查）：`Localizable` 31、`DeckManager` 11、`TrackersPreferences` 7、
`OpponentTrackers` 6、`PlayerTrackers` 6、`NewDeck` 4、`GamePreferences` 4、`Statistics` 2、
`HSReplayPreferences` 1、`EditDeck` 1、`SaveDeck` 1、`GeneralPreferences` 1、`InitialConfiguration` 1、`StatsTab` 1。

## 明确不要做的事

- **不要整文件覆盖。** 双方 base 不同：它有我们没有的 key，我们也有它没有的（Mulligan V2 是我们 HEAD 之后加的）。
  整文件拷贝会把我们的新 key 删掉。**按 key 合并。**
- **不要取它的 3 个 `.xib`**（`HSReplayPreferences.xib` / `NewDeck.xib` / `LadderTab.xib`）。`.refs/` 里也没放它们。
- **不要动 zh-Hans 以外的语言。** 它那边可能也改了别的语言，一律不取。
- **不要改我们已有的 zh-Hans**（那是第二步报告的内容，不是本次改动）。
- **不要新增我们没有的 key。**

## 一个必须注意的坑

`MainMenu.xcstrings` 里 "Decks" 菜单项（`1a9-Jp-R8O.title` / `8x4-Eu-hed.title`），
gaenyong 译作**「卡组」**，而仓库里那套废弃的 `HSTracker/UIs/zh-Hans.lproj/MainMenu.strings`
译作**「套牌」**。

必须用 gaenyong 的「卡组」—— 因为 `AppDelegate.swift:440` 是用
`mainMenu?.item(withTitle: String.localizedString("Decks", comment: ""))` 按**标题字符串**找菜单项的，
而 `Localizable.xcstrings` 里 `Decks` → 「卡组」。两边必须一致，否则中文环境下菜单栏「卡组」子菜单会查不到。

同理，以下几对在两个 catalog 之间必须保持一致，合并时顺手确认（不一致就在报告里指出，不要自己改 `Localizable`）：

| Localizable.xcstrings | MainMenu.xcstrings |
|---|---|
| `Decks` → 卡组 | `1a9-Jp-R8O.title` / `8x4-Eu-hed.title` |
| `Window` → 窗口 | `aUF-d1-5bR.title` / `Td7-aD-5lo.title` |
| `Lock windows` → 锁定窗口 | `9Mn-Tj-Fg1.title` |
| `Replays` → （我们目前缺，T4 会补）| `esn-TJ-7Ds.title` / `RBa-X9-6k6.title` → 回放 |
| `Last replays` → （我们目前缺，T4 会补）| `Ck1-T5-ndx.title` / `gKK-Xg-cTS.title` → 最近回放 |

> 这条耦合的根治办法是改成按 tag/outlet 定位菜单项，那是 Phase 4 的事，不在本任务范围。
> 本任务只要**不把它弄得更坏**。

## 验收

1. `python3 docs/tasks/tools/check_xcstrings.py` 通过（不加 `--allow-zh-edit` —— 本任务不许改既有译文）。
2. 校验器输出的「仍缺」总数应从 **410 降到 271**。
3. 构建通过。
4. `docs/tasks/phase3-t1-diff-report.md` 已生成，77 条齐全，每条都有建议和理由。
5. 报告里写明：每个文件实际补了多少条、与上表是否完全一致。

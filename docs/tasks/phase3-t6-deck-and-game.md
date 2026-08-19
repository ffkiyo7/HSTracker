# Phase 3 / T6 —— 翻译卡组管理与对局界面的 4 个 catalog（85 条）+ 收尾

先读 `docs/tasks/_common-phase3.md` 里的通用约束（尤其是**术语表**和 `.xcstrings` 写法），再读本文件。

**前置依赖：T1 必须已完成。**

## 第一部分 —— 翻译 85 条

| 文件 | 待译 |
|---|---|
| `HSTracker/UIs/DeckManager/mul.lproj/DeckManager.xcstrings` | 26 |
| `HSTracker/UIs/DeckManager/mul.lproj/EditDeck.xcstrings` | 24 |
| `HSTracker/UIs/Battlegrounds/Session/mul.lproj/BattlegroundsSession.xcstrings` | 19 |
| `HSTracker/UIs/Trackers/mul.lproj/BobsBuddyPanel.xcstrings` | 16 |
| **合计** | **85** |

`BobsBuddyPanel` 目前是 **0% 中文**。

用户点名要的两条在 `DeckManager.xcstrings` 里：`Hyt-EI-Vfy.label`（Classes）→「职业」、
`BHN-1k-K8M.label`（Modes）→「模式」。gaenyong 那边也没有这两条，必须自己译。

翻译要求同 T5（XIB key、`comment` 里能看出控件类型、同文件用词自洽、占位符原样保留）。
额外注意：

- `DeckManager` / `EditDeck` 里 `Deck` → 「卡组」，**不要用「套牌」**。
  原因见下面那节坑，也和 `Localizable.xcstrings` 的 `Decks` → 「卡组」保持一致。
- `BobsBuddyPanel` 是对局中悬浮在战棋战斗画面上的小面板，**标签必须极短**。
  `Win` / `Tie` / `Lose` → 「胜」/「平」/「负」，`Damage` → 「伤害」，`Lethal` → 「致死」。
  "Bob's Buddy" 这个名字本身保留英文。
- `BattlegroundsSession` 是战棋场次统计面板，`MMR` 保留英文。

## 第二部分 —— 修 8 条「假翻译」

这 8 个 key **已经有 zh-Hans，但值就是英文原文**，等于没翻。改掉它们。
**这部分需要修改既有译文，跑校验器时加 `--allow-zh-edit`。**

| 文件 | key | 现值（英文） | 应改为 |
|---|---|---|---|
| `HSTracker/UIs/Views/mul.lproj/LinkOpponentDeckPanel.xcstrings` | `rp4-Z9-eiC.title` | Know your opponent's deck? | 知道对手的卡组？ |
| 同上 | `EeO-25-kGw.title` | Copy a deck code to your clipboard and click the button below to see their deck update as they play | 自己译（这是说明文字，可以长） |
| 同上 | `ogh-3B-QHX.title` | Set deck from clipboard | 从剪贴板设置卡组 |
| 同上 | `lWR-k8-nsx.title` | Clear | 清除 |
| 同上 | `4gN-Ez-53m.title` | Error | 错误 |
| `HSTracker/UIs/DeckManager/mul.lproj/NewDeck.xcstrings` | `trs-D1-mgZ.title` | OK | 确定 |
| `HSTracker/UIs/StatsManager/mul.lproj/Statistics.xcstrings` | `PwO-Us-vPh.title` | OK | 确定 |
| `Translations/macOS/Localizable.xcstrings` | `Vs %@` | Vs %@ | 对阵 %@ |

`LinkOpponentDeckPanel.xcstrings` 这个文件 `docs/PLAN.md` 里根本没提到 —— 它是我在校验时发现的漏网之鱼。
上表第 4 条「Clear」的译法要和 `Localizable.xcstrings` 里已有的 `Clear` → 「清除」一致。

**不要动**下面这些同样「zh 等于 en」但确实不该改的：
`BattlegroundsSession.xcstrings` 里那 16 条 `Box` / `0` / `MMR` / `Label A` / `Label B`
（XIB 的占位控件标题，运行时会被代码覆写），以及 `Localizable.xcstrings` 的 `%@ vs %@`。

## 一个必须注意的坑：不要写「套牌」

仓库里那套废弃的 `zh-Hans.lproj/*.strings`（T2 已删）把 Deck 译作「套牌」，
而现行 catalog 一律用「卡组」。`AppDelegate.swift:440` 是按**标题字符串**去找菜单项的
（`item(withTitle: String.localizedString("Decks"))`），两个 catalog 的用词必须完全一致，
否则中文环境下菜单栏的「卡组」子菜单会查不到、静默变成空菜单。

本任务里凡是出现 Deck 的地方，**一律「卡组」**。

## 验收

1. `python3 docs/tasks/tools/check_xcstrings.py --allow-zh-edit --allow-new-key Archive --allow-new-key Unarchive` 通过。
2. 再跑一次**不带** `--allow-zh-edit`（但保留 `--allow-new-key Archive --allow-new-key Unarchive`）的版本，把它报的 E5 贴进报告 ——
   应当**恰好是上表那 8 条**，一条不多。多出来的说明你误改了别的译文。
3. 全局仍缺应为 **7**（`Localizable.xcstrings` 里那 7 个符号 key，T4 已说明有意跳过）。
   换算：846 个 key 里 839 个有中文 = **99.2%**。
4. 构建通过。
5. 报告里逐文件写明补了多少条，外加「拿不准的译法」清单。

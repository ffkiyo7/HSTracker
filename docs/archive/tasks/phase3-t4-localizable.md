# Phase 3 / T4 —— 翻译主 catalog `Localizable.xcstrings` 剩余 124 条

先读 `docs/tasks/_common-phase3.md` 里的通用约束（尤其是**术语表**和 `.xcstrings` 写法），再读本文件。

**前置依赖：T1 和 T3 必须已完成。** 检查方式：`Translations/macOS/Localizable.xcstrings` 里
`Decks` 应已有 zh-Hans「卡组」（T1 补的），`Archive` 这个 key 应已存在（T3 加的）。
不满足就停下，在报告里说明。

## 目标文件

`Translations/macOS/Localizable.xcstrings`

**本任务只允许修改这一个文件。**

## 背景

这是主 catalog，代码里 353 处 `String.localizedString(...)` 调用都走它。
T1 合并后还剩 **131 个 key 没有 zh-Hans**，其中 **7 个不该翻**（见下），实际要译 **124 条**。

内容大致分四块：
- `BattlegroundsXxx_*` / `Counter_*` —— 酒馆战棋悬浮窗的提示与计数器
- `MulliganGV2_*` / `ConstructedMulliganGuide*` —— 起手留牌指南 V2（我们 HEAD 才有的新功能，gaenyong 那边没有）
- `ConstructedPreLobbyWidget_*` / `ConstructedTrialsExhausted_*` / `Options_HSReplay_Account_*` —— HSReplay 订阅/试用相关
- `BobsBuddyStatusMessage_*` —— Bob's Buddy 状态提示
- 少数散的：`Player`、`Opponent`、`Importing`、`Compare heroes`、`Compare Timewarped Cards`

`Player` / `Opponent` / `Importing` 是设置窗口的**分页标题**（用户点名要的），务必译准：
「玩家」/「对手」/「导入」。

## 明确不要翻的 7 个 key

这几个 key 的"英文原文"本身就是标点或排版字符，翻译没有意义，**原样跳过、不要加 zh-Hans**：

```
""        "\n"      "\n\n"     "!"      "?"      "✕"      "i"
```

在报告里列出来，说明是有意跳过的。校验器最后会显示"仍缺 7"，那是正确结果。

## 翻译时特别注意

1. **占位符是重灾区。** 这批 key 里有大量 `%@` / `%d`，例如
   `BattlegroundsPreLobby_Trial_ResetTimeRemaining_DaysHours`、`MulliganGV2_Tooltip_*`。
   校验器会逐条比对英文与中文的占位符集合，对不上直接 FAIL。
   中文语序需要调换顺序时，**整条改用位置化写法** `%1$@` / `%2$@`，不要一半带位置一半不带。

2. **同一族 key 的译法必须成体系。** 例如
   `MulliganGV2_IconTooltip_KeptMore` / `_KeptMore_Coin` / `_KeptMore_First` / `_KeptMore_Opponent` / `_KeptMore_SecondCopy`
   是同一句话的五个变体，中文也应当是同一句式的五个变体，不要各译各的。
   `BattlegroundsHeroPicking_Header_Tier{1,2,3,4}Tooltip_Title` 同理。

3. **`Counter_*` 是悬浮窗上的短标签，必须短。** 这些字挤在计数器旁边，
   例如 `Counter_FreeRefresh`、`Counter_GoldNextTurn`、`Counter_UndeadBuff`。
   先去看它们在代码里的用法（`grep -rn 'Counter_' --include='*.swift' HSTracker/`），
   确认是标签还是整句，再决定长度。

4. **`MulliganGV2_Keep` / `MulliganGV2_Replace`** 是起手留牌界面上的动作词：「保留」/「替换」。
   炉石本体在起手界面用的就是这两个词。

5. **Tier7 / Premium / Trial 这些订阅词汇**：`Tier7` 是 HSReplay 的付费档名，**保留英文**；
   `Premium` → 「高级会员」，`Trial` → 「试用」，`Subscribe` → 「订阅」。

6. **译之前先读英文原文的 `comment` 字段**（很多 key 有），它说明了这条字符串出现在哪。

## 别把菜单栏弄坏

T1 已经让下面这几条与 `MainMenu.xcstrings` 对齐了。它们**不在本任务的 124 条里**，
但如果你出于"统一用词"的想法顺手改了它们，会重新弄坏 `AppDelegate.swift:440/514/546` 的
`item(withTitle:)` 菜单项查找：

```
Decks → 卡组      Replays → 回放      Last replays → 最近回放
Window → 窗口     Lock windows → 锁定窗口     Unlock windows → 解锁窗口
```

**一个字都不要动。** 校验器的 E5 会拦住，但别去试。

## 验收

1. `python3 docs/tasks/tools/check_xcstrings.py --allow-new-key Archive --allow-new-key Unarchive` 通过。
   （那两个 key 是 T3 有意新增的，用这两个开关放行；除此之外不要加任何开关。）
2. 该文件的缺失数应从 **131 降到 7**（就是上面那 7 个符号 key）。全局仍缺应为 **147**。
3. 构建通过。
4. 报告里必须包含**「拿不准的译法」清单**：key、英文、你给的中文、疑虑。
   这批字符串里 HSReplay 订阅体系和 Mulligan V2 的措辞最容易译歪，宁可多列几条。

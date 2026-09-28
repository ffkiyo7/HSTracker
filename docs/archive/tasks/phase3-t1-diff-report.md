# T1 —— gaenyong 与我们译法不同的 77 条

本文件只记录**双方都有 zh-Hans 且译法不同**的 key。这些条目**一条都没有改**，等人工逐条决定。

## 第一步合并结果（已写入工作区）

判定规则：我们缺 zh-Hans、它有 zh-Hans → 采纳它的值，`state` 写 `"translated"`。不增 key、不改既有译文、不动其它语言。

| 文件 | 应补 | 实补 | 一致 |
|---|---:|---:|---|
| `HSTracker/UIs/mul.lproj/MainMenu.xcstrings` | 41 | 41 | 是 |
| `Translations/macOS/Localizable.xcstrings` | 67 | 67 | 是 |
| `HSTracker/UIs/StatsManager/mul.lproj/LadderTab.xcstrings` | 12 | 12 | 是 |
| `HSTracker/UIs/Preferences/mul.lproj/PlayerTrackersPreferences.xcstrings` | 6 | 6 | 是 |
| `HSTracker/UIs/Preferences/mul.lproj/OpponentTrackersPreferences.xcstrings` | 5 | 5 | 是 |
| `HSTracker/UIs/Preferences/mul.lproj/TrackersPreferences.xcstrings` | 4 | 4 | 是 |
| `HSTracker/UIs/StatsManager/mul.lproj/StatsTab.xcstrings` | 4 | 4 | 是 |
| **合计** | **139** | **139** | **是** |

其余 9 个 `.refs` 对照文件没有可补空缺，只出现在下面的差异表里。

## 菜单栏耦合核对

`AppDelegate.swift` 用 `item(withTitle: String.localizedString(...))` 按标题找菜单项，两个 catalog 必须一致。

| Localizable.xcstrings | MainMenu.xcstrings | 结果 |
|---|---|---|
| `Decks` → 卡组（原先已有，未改） | `1a9-Jp-R8O.title` / `8x4-Eu-hed.title` → 卡组 | 一致 |
| `Window` → 窗口（原先已有，未改） | `aUF-d1-5bR.title` / `Td7-aD-5lo.title` → 窗口 | 一致 |
| `Lock windows` → 锁定窗口（原先已有，未改） | `9Mn-Tj-Fg1.title` → 锁定窗口 | 一致 |
| `Replays` → 回放（本次补上） | `esn-TJ-7Ds.title` / `RBa-X9-6k6.title` → 回放 | 一致 |
| `Last replays` → 最近回放（本次补上） | `Ck1-T5-ndx.title` / `gKK-Xg-cTS.title` → 最近回放 | 一致 |

任务书里写 `Replays` / `Last replays`「我们目前缺，T4 会补」。gaenyong 的 Localizable 里这两条已有译文，按「缺则采纳」进了上面的 67 条，现已与 MainMenu 对齐。没有改既有 Localizable 译文。`Unlock windows` 本来就是「解锁窗口」，本次未动。

## Translations/macOS/Localizable.xcstrings（31 条）

| key | 英文 | 我们的 | gaenyong 的 | 建议 |
|---|---|---|---|---|
| `All classes` | All classes | 所有英雄 | 所有职业 | 采纳它。术语表 Class→职业，这是卡组管理器的职业筛选，不是英雄。 |
| `Are you sure you want to close this deck ? Your changes will not be saved.` | Are you sure you want to close this deck ? Your changes will not be saved. | 确定要退出吗？您的修改将不会被保存。 | 确定要退出吗？你的修改将不会被保存。 | 采纳它。同一 catalog 里多数对白用「你」，也更接近 Apple 中文口径。 |
| `Arena %@ %@` | Arena %@ %@ | 竞技场 %@ %@ | 竞技模式 %@ %@ | 保留我们的。术语表 Arena→竞技场。 |
| `By clicking 'Reset' you will clear your list of Latest Games and make your Start MMR the same as your current MMR.` | By clicking 'Reset' you will clear your list of Latest Games and make your Start MMR the same as your current MMR. | 通过点击“重置”，将清除你的最近对局记录，并使起始MMR与当前MMR相同。 | 通过点击“重置”，你将清除最近对局记录，并使起始MMR与当前MMR相同。 | 采纳它。补上主语「你将」，读起来才是完整句子。 |
| `DeckType_all` | All | 全部 | 全部模式 | 保留我们的。英文只是 All，旁边 `mode_all` 也是「所有」，加「模式」是添字。 |
| `DeckType_arena` | Arena | 竞技场 | 竞技模式 | 保留我们的。术语表 Arena→竞技场；本 catalog 其它 Arena 相关句也用「竞技场」。 |
| `DeckType_classic` | Classic | 经典 | 经典模式 | 采纳它。术语表 Classic→经典模式；同组刚补上的 `DeckType_twist` 已是「幻变模式」。 |
| `DeckType_duels` | Duels | 对决 | 对决模式 | 采纳它。术语表 Duels→对决模式。 |
| `DeckType_dungeon` | Dungeon Run | 地下城 | 地下城冒险 | 采纳它。国服冒险名是「地下城冒险」，比单写「地下城」准。 |
| `DeckType_standard` | Standard | 标准 | 标准模式 | 采纳它。术语表 Standard→标准模式。 |
| `DeckType_wild` | Wild | 狂野 | 狂野模式 | 采纳它。术语表 Wild→狂野模式。 |
| `Do you want to send an anonymous crash report so we can try to fix the issue?` | Do you want to send an anonymous crash report so we can try to fix the issue? | 你是否愿意发送一个匿名的崩溃报告以帮助我们修复这个问题? | 您是否愿意发送一个匿名的崩溃报告以帮助我们修复这个问题? | 保留我们的。称谓应继续用「你」，不要改回「您」。 |
| `Failed to import deck from \n` | Failed to import deck from \n | 从 \n 获取卡组失败 | 从 \n 导入卡组失败 | 采纳它。术语表 Import→导入，英文也是 import 不是 fetch。 |
| `Fatigue : ` | Fatigue :  | 疲劳:  | 疲劳： | 都不好，应作「疲劳： 」。全角冒号按标点规则，但英文 key 是前缀、必须留尾空格，它删掉了。 |
| `HSReplay.net - Mulligan Guide` | HSReplay.net - Mulligan Guide | HSReplay.net - 调度建议 | HSReplay.net - 起手留牌指南 | 采纳它。术语表 Mulligan→起手留牌；设置页刚补的也是「起手留牌指南」。 |
| `LinkOpponentDeck_NoValidDeckOnClipboardMessage` | No valid deck code found on clipboard | 在剪贴板中没有找到有效的卡组代码 | 剪贴板中没有找到有效的卡组代码 | 采纳它。少一个「在」更干净，意思不变。 |
| `Logout` | Logout | 注销 | 退出登录 | 采纳它。这是 HSReplay 账号退出，用「退出登录」比系统味的「注销」清楚。 |
| `mode_arena` | Arena | 竞技场模式 | 竞技模式 | 保留我们的。术语表是竞技场；同组 `mode_*` 也带「模式」（排名模式、休闲模式）。 |
| `mode_friendly` | Friendly | 友好模式 | 好友对战 | 采纳它。术语表 Friendly→好友对战，「友好」是字面直译。 |
| `Opponent tracker` | Opponent tracker | 对手的记牌器 | 对手记牌器 | 采纳它。少一个「的」更像界面标签，术语 Tracker→记牌器两边一样。 |
| `Save Arena Deck` | Save Arena Deck | 保存竞技场卡组 | 保存竞技模式卡组 | 保留我们的。术语表 Arena→竞技场，Deck→卡组我们这边已经对。 |
| `There was an issue saving your arena deck. Try relaunching Hearthstone and clicking on 'Arena', and then try to save again.` | There was an issue saving your arena deck. Try relaunching Hearthstone and clicking on 'Arena', and then try to save again. | 出了一些问题，你的竞技场卡组没有保存。请尝试重启炉石传说和重新保存卡组。 | 您的竞技模式卡组因为某个问题没有保存。请尝试重启炉石传说，点击竞技模式，然后重新保存。 | 都不好，理由：应用「竞技场」+「你」，并保留它补上的「点进竞技场再保存」步骤。 |
| `To export a deck to Hearthstone, create a new deck with the correct class in your collection, then click OK and switch to Hearthstone.\nDo not touch your mouse or keyboard during the import.` | To export a deck to Hearthstone, create a new deck with the correct class in your collection, then click OK and switch to Hearthstone.\nDo not touch your mouse or keyboard during the import.\nWARNING, this is a beta feature ! | 如果想将本卡组导出到炉石传说中, 请创建一个与卡组英雄对应的新卡组, 然后点击 OK 并切换到炉石传说。\n。在导入过程中，请不要使用鼠标或键盘。\n警告, 这只是一个测试功能! | 若想将本卡组导出到炉石传说中, 请创建一个同一职业的新卡组, 然后点击 OK 并切换到炉石传说。\n。在导入过程中，请不要使用鼠标或键盘。\n警告，这只是一个测试功能！ | 采纳它。英文是 correct class，术语表 Class→职业；两边都残留 `\n。`，以后再单修。 |
| `Top deck:` | Top deck: | 下一抽抽中概率: | 下一抽抽中概率： | 保留我们的。同 catalog 的「下两抽抽中概率:」用的是半角冒号，先保持一对标签一致。 |
| `Turn %d` | Turn %d | 回合 %d | 第 %d 回合 | 保留我们的。记牌器/酒馆战棋回合标签要短，「回合 3」够用。 |
| `What should I keep?` | What should I keep? | 我应该保留什么? | 我应该留下哪张牌? | 采纳它。这是起手留牌提示，用「留下」比笼统的「保留」贴语境。 |
| `You are now connected to Hearthstats` | You are now connected to Hearthstats | 您已连接到 Hearthstats | 你已连接到 Hearthstats | 采纳它。统一用「你」。 |
| `You are now connected to Track-o-Bot` | You are now connected to Track-o-Bot | 您已连接到 Track-o-Bot | 你已连接到 Track-o-Bot | 采纳它。同上。 |
| `You must restart HSTracker for the language change to take effect` | You must restart HSTracker for the language change to take effect | 必须重启 HSTracker 使语言设置生效 | 您必须重启 HSTracker 使语言设置生效 | 保留我们的。语气已经够硬，不必再加「您」。 |
| `Your arena deck count 30 cards, do you want to save it ?` | Your arena deck count 30 cards, do you want to save it ? | 竞技场卡组已有 30 张卡, 要保存吗? | 竞技模式卡组已有 30 张卡, 要保存吗? | 保留我们的。术语表 Arena→竞技场。 |
| `Your replay has been uploaded on HSReplay` | Your replay has been uploaded on HSReplay | 你的游戏录像已上传至 HSReplay | 你的回放已上传至 HSReplay | 采纳它。术语表 Replay→回放。 |

## HSTracker/UIs/DeckManager/mul.lproj/DeckManager.xcstrings（11 条）

主 catalog 里 `Deck Manager` / `Delete deck` / `Rename` 等早已写成「卡组*」，这里还在用废弃的「套牌」。

| key | 英文 | 我们的 | gaenyong 的 | 建议 |
|---|---|---|---|---|
| `3nu-q9-wC1.label` | Use | 使用套牌 | 使用卡组 | 采纳它。术语表 Deck→卡组；与 Localizable「使用本卡组」对齐。 |
| `3nu-q9-wC1.paletteLabel` | Use | 使用套牌 | 使用卡组 | 采纳它。同上，工具栏标签要和按钮一致。 |
| `7FY-gv-qwP.label` | Add | 新建套牌 | 新建卡组 | 采纳它。Deck→卡组。 |
| `7FY-gv-qwP.paletteLabel` | Add | 新建套牌 | 新建卡组 | 采纳它。同上。 |
| `aaa-LK-buD.label` | Delete | 删除套牌 | 删除卡组 | 采纳它。与 Localizable「删除卡组」对齐。 |
| `aaa-LK-buD.paletteLabel` | Delete | 删除套牌 | 删除卡组 | 采纳它。同上。 |
| `cbH-rI-BvP.label` | Edit | 修改套牌 | 修改卡组 | 采纳它。与 Localizable「修改卡组」对齐。 |
| `cbH-rI-BvP.paletteLabel` | Edit | 修改套牌 | 修改卡组 | 采纳它。同上。 |
| `Qp2-0h-Sid.label` | Rename | 重命名套牌 | 重命名卡组 | 采纳它。与 Localizable「重命名卡组」对齐。 |
| `Qp2-0h-Sid.paletteLabel` | Rename | 重命名套牌 | 重命名卡组 | 采纳它。同上。 |
| `QvC-M9-y7g.title` | Deck Manager | 套牌管理器 | 卡组管理器 | 采纳它。Deck→卡组。菜单项 Localizable 是「卡组管理」（无「器」），窗口标题带「器」可以接受。 |

## HSTracker/UIs/Preferences/mul.lproj/TrackersPreferences.xcstrings（7 条）

| key | 英文 | 我们的 | gaenyong 的 | 建议 |
|---|---|---|---|---|
| `5rZ-fg-pB4.title` | Auto position trackers | 自动移动记牌器 | 自动设定记牌器位置 | 采纳它。英文是 position 不是 move，说的是自动摆位置。 |
| `cBa-wb-tRb.ibShadowedObjectValues[1]` | Frost | 寒冰 | 冰霜 | 采纳它。这是主题下拉（按 index 写入 `frost`，改显示名不会坏设置）；国服 Frost 用「冰霜」，繁中也是「冰霜」。 |
| `Ehf-nl-mzO.title` | Show flavor text | 显示风味文字 | 显示卡牌趣文 | 都不好，国服卡牌底部文案叫「趣闻」，建议「显示卡牌趣闻」。 |
| `HeE-hK-rL7.title` | Show constructed mulligan | 显示构造调度建议 | 构筑模式中显示起手留牌指南 | 采纳它。术语表 Mulligan→起手留牌；国服把 Constructed 叫「构筑」不是「构造」。 |
| `HY0-s6-p7U.title` | Show card on tracker hover | 鼠标悬停时显示卡牌 | 鼠标悬停在记牌器显示卡牌详情 | 保留我们的。checkbox 标题求短，两边意思一样。 |
| `s9w-5p-pJs.title` | Remove cards if count is 0 | 卡牌数为零时不显示该卡牌 | 若卡牌数为零，移除该卡牌 | 采纳它。英文是 Remove，跟设置项 `removeCardsFromDeck` 的实际行为一致。 |
| `yeJ-ZI-Pca.title` | Highlight discarded from deck | 显示弃掉的卡牌 | 高亮弃掉的卡牌 | 采纳它。英文是 Highlight，同页其它项也用「高亮」。 |

## HSTracker/UIs/Preferences/mul.lproj/OpponentTrackersPreferences.xcstrings（6 条）

| key | 英文 | 我们的 | gaenyong 的 | 建议 |
|---|---|---|---|---|
| `avf-qA-8vU.title` | Show opponent draw chance | 显示对手抽卡机会 | 显示对手抽牌机率 | 都不好，术语表 Draw chance→抽到概率，建议「显示对手抽到概率」。 |
| `aW1-2y-nKx.title` | Show player class and name | 显示对手英雄和名字 | 显示对手职业和名字 | 采纳它。英文是 class；对手记牌器顶栏显示的是职业，不是英雄名。 |
| `eGQ-pE-MU0.title` | Clear opponent tracker on game end | 清空对手记牌器 | 对局结束清空对手记牌器 | 采纳它。补上「对局结束」，否则看不出触发时机。 |
| `fah-Dr-Amh.title` | Show board damage | 显示场攻（包括武器） | 显示场攻 | 采纳它。英文没有「包括武器」，checkbox 标题也不该加括号说明。 |
| `iqA-b1-owW.title` | Show opponent card count | 显示对手的卡牌数 | 显示对手卡牌数 | 采纳它。少一个「的」更像标签。 |
| `pMP-qQ-LuR.title` | Cardlist opens on mouseover | 鼠标进入时显示卡牌列表 | 鼠标悬停显示卡牌列表 | 采纳它。「悬停」才是 mouseover 的界面用语。 |

## HSTracker/UIs/Preferences/mul.lproj/PlayerTrackersPreferences.xcstrings（6 条）

| key | 英文 | 我们的 | gaenyong 的 | 建议 |
|---|---|---|---|---|
| `1dP-3v-VLS.title` | Cardlist opens on mouseover | 鼠标进入时显示卡牌列表 | 鼠标悬停显示卡牌列表 | 采纳它。与对手页同一控件，应用「悬停」。 |
| `acK-XF-6wQ.title` | Show player draw chance | 显示你的抽卡机会 | 显示你的抽牌机率 | 都不好，术语表 Draw chance→抽到概率，建议「显示抽到概率」。 |
| `e7g-zd-YkC.title` | Show deck name | 显示套牌名称 | 显示卡组名称 | 采纳它。Deck→卡组；Localizable 已是「卡组名称」。 |
| `gpo-Wo-m50.title` | Flash on card draw | 抽的卡牌在记牌器上闪烁 | 抽到的牌在记牌器上闪烁 | 采纳它。「抽到的牌」更顺，繁中也是这个说法。 |
| `MiE-Lr-Vdi.title` | Show player tracker | 显示记牌器 | 显示你的记牌器 | 采纳它。这页是玩家侧，加上「你的」才能和「对手记牌器」对上。 |
| `rj2-8a-HGB.title` | Show board damage | 显示场攻（包括武器） | 显示场攻 | 采纳它。与对手页同一选项，去掉括号说明。 |

## HSTracker/UIs/DeckManager/mul.lproj/NewDeck.xcstrings（4 条）

| key | 英文 | 我们的 | gaenyong 的 | 建议 |
|---|---|---|---|---|
| `0dN-Ei-UM2.title` | Arena or Brawl deck | 竞技模式套牌 | 竞技模式卡组 | 都不好，英文还有 Brawl。应作「竞技场或乱斗卡组」。 |
| `bnr-YF-pLP.title` | How do you want to create your new deck ? | 你想如何创建新的套牌? | 你想如何创建新的卡组? | 采纳它。Deck→卡组。 |
| `N10-sK-1gZ.title` | Using HSTracker deck builder | 使用 HSTracker 构建套牌 | 使用 HSTracker 构建卡组 | 采纳它。Deck→卡组。 |
| `QvC-M9-y7g.title` | New Deck | 新套牌 | 新卡组 | 采纳它。Deck→卡组。 |

## HSTracker/UIs/Preferences/mul.lproj/GamePreferences.xcstrings（4 条）

| key | 英文 | 我们的 | gaenyong 的 | 建议 |
|---|---|---|---|---|
| `biS-yx-frk.title` | Hearthstone language | 炉石传说语言 | 炉石传说 语言 | 保留我们的。中英文之间不加空格。 |
| `hMe-FU-CjR.title` | Auto archive Arena deck on run end | 在每轮结束时，自动存储竞技模式套牌 | 每轮结束自动储存竞技模式卡组 | 都不好，应作「每轮结束时自动存档竞技场卡组」（Arena→竞技场，Deck→卡组，archive→存档）。 |
| `mhj-j8-OPU.title` | Auto import and select decks | 自动导入并选择套牌 | 自动导入并选择卡组 | 采纳它。Deck→卡组。 |
| `s5e-Q8-cm8.title` | Hearthstone directory | 炉石传说目录 | 炉石传说 目录 | 保留我们的。中英文之间不加空格。 |

## HSTracker/UIs/StatsManager/mul.lproj/Statistics.xcstrings（2 条）

| key | 英文 | 我们的 | gaenyong 的 | 建议 |
|---|---|---|---|---|
| `F0z-JX-Cv5.title` | Deck Statistics | 套牌统计 | 卡组统计 | 采纳它。Deck→卡组。 |
| `hZh-Kz-cgX.title` | No deck selected | 没有选择套牌 | 尚未选择卡组 | 采纳它。Deck→卡组。 |

## HSTracker/HSReplay/mul.lproj/HSReplayPreferences.xcstrings（1 条）

| key | 英文 | 我们的 | gaenyong 的 | 建议 |
|---|---|---|---|---|
| `zQQ-GF-3Lg.title` | Login to claim your replays and enable all HSReplay.net features. | 在连接 HSReplay 后，打开你的收藏，上传会自动进行。 | 登录以同步你的回放并启用HSReplay.net的所有功能。 | 采纳它。我们这句完全是另一条「已登录、上传收藏」的文案，和英文对不上。 |

## HSTracker/UIs/DeckManager/mul.lproj/EditDeck.xcstrings（1 条）

| key | 英文 | 我们的 | gaenyong 的 | 建议 |
|---|---|---|---|---|
| `QvC-M9-y7g.title` | Edit Deck | 修改套牌 | 修改卡组 | 采纳它。Deck→卡组；与 Localizable「修改卡组」对齐。 |

## HSTracker/UIs/DeckManager/mul.lproj/SaveDeck.xcstrings（1 条）

| key | 英文 | 我们的 | gaenyong 的 | 建议 |
|---|---|---|---|---|
| `LWn-HE-BcI.title` | Deck Name | 套牌名称 | 卡组名称 | 采纳它。Deck→卡组；Localizable 已是「卡组名称」。 |

## HSTracker/UIs/Preferences/mul.lproj/GeneralPreferences.xcstrings（1 条）

| key | 英文 | 我们的 | gaenyong 的 | 建议 |
|---|---|---|---|---|
| `1BI-nh-nxq.title` | Prefer golden cards when exporting to Hearthstone | 将套牌导入炉石传说时，优先使用金色卡牌 | 将卡组导入炉石传说时，优先使用金色卡牌 | 采纳它。Deck→卡组。英文是 exporting，两边都写成了「导入」（实际流程是把卡组写进炉石收藏），以后可再改成「导出」。 |

## HSTracker/UIs/Preferences/mul.lproj/InitialConfiguration.xcstrings（1 条）

| key | 英文 | 我们的 | gaenyong 的 | 建议 |
|---|---|---|---|---|
| `iQb-5L-jZW.title` | Hearthstone language | 炉石传说语言 | 炉石传说 语言 | 保留我们的。中英文之间不加空格。 |

## HSTracker/UIs/StatsManager/mul.lproj/StatsTab.xcstrings（1 条）

| key | 英文 | 我们的 | gaenyong 的 | 建议 |
|---|---|---|---|---|
| `2EV-QP-KAN.headerCell.title` | Versus Class | 对手英雄 | 对手职业 | 采纳它。列头是 Versus Class，术语表 Class→职业。 |

## 建议汇总

| 判断 | 条数 |
|---|---:|
| 采纳它 | 56 |
| 保留我们的 | 14 |
| 都不好，另拟 | 7 |
| **合计** | **77** |

「都不好」的 7 条：`Fatigue : `、竞技场保存失败那句长说明、`Show flavor text`、两条 draw chance、`Arena or Brawl deck`、`Auto archive Arena deck on run end`。替代译法写在各行「建议」栏。

## 本次按规则采纳、但建议人工再看的 fill

这些已经写入（原先空缺），不在上面 77 条里：

- `Spell_School_Physical_Combat`（Localizable）：英文 Attack，它译「无」。若这条出现在「打出过的法术派系」里，把物理攻击显示成「无」可能是故意的，但用户看见的不是「攻击」。
- `Counter_SilverHandRecruitBuff`：它译「报告兵强化」。国服随从名是「白银之手新兵」。
- `Counter_Herald`：它译「兆示」，没在术语表里，对不对得上具体计数器要再对代码。
- `CardTile_Created_By`：它译「由 %@ 制作」。炉石生成牌一般写「创建」不是「制作」。
- `Lq9-gc-KKd.title` / `UGt-FV-Bds.title`：它译「显示血量、法力水晶和手牌数上限」。术语表 Health→生命值、Mana→法力值，但这条说的是血条/水晶/手牌上限 HUD，「血量」「法力水晶」更贴界面。
- `UXw-QE-lUP.title`：它译「游戏开始时显示起手留牌窗口」。术语表 Overlay→悬浮窗，不是「窗口」。
- `ZkO-13-FoB.title`：它译「在非好友对战中启用对手卡组设置」。英文是 setting opponent deck，意思是「允许指定对手卡组」，「启用……设置」有点绕。
- `Vdr-fp-XzO.title`（MainMenu Hide Others）：它译「隐藏 其他」，中间多了一个空格；系统菜单一般是「隐藏其他」。
- `BOF-NM-1cW.title`（MainMenu Preferences…）：它译「设置…」。术语表是「偏好设置」，但 Localizable 的 `Preferences` 本来就是「设置」，两边现在一致，不要单独改菜单项。
- `LadderTab` 12 条 + `StatsTab` 4 条：它给的是 XIB 占位「Text Cell」/「Table View Cell」，用户看不到。照规则采纳了。
- `%lld`：无 `en`、无其它语言，它给了原样 `%lld`。格式串，保留即可。

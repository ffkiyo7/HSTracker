# 红龙贼（狂野「致聋双闪避」）24 张牌的效果模型草稿

> 供 `docs/research/red-dragon-rogue-spike.md` 九、2「卡表草稿」用。**这是规格文档，不是代码**，只在第二部分给一个 enum 草图说明数据形状。
> 卡牌效果**按官方卡牌文本自己建模**，不复制 `zcr0701/hearthstone-selfplay` 的任何卡表或代码。

## 0. 文本出处与核对方式（2026-09-11）

| 来源 | 用途 | 版本证据 |
|---|---|---|
| HearthstoneJSON `https://api.hearthstonejson.com/v1/latest/enUS/cards.collectible.json` 与 `.../zhCN/...` | **中英文本、费用、身材、种族、职业、mechanics 的主依据** | HTTP `last-modified: Thu, 03 Sep 2026 17:49:41 GMT` |
| HearthstoneJSON `.../enUS/cards.json`（含非收藏） | 附属衍生物（附魔实体）的 id 与文本 | 同上 |
| `hearthstone.wiki.gg/wiki/<英文名>` | **改动历史**（哪张被改过、改成什么），逐卡在下面给 URL | 页面自带 patch 表 |
| 本仓库 `downloaded-frameworks/cards/251332/CardDefs.xml`（69 MB，2026-09-05 下载） | 确认 24 个 cardId 在**本地卡库**里查得到 | 构建号 251332 |

**卡表是从牌组代码反解的，不是照抄 spike 的表**。解码 `AAEBAYHmBwrcrwK0hgOd8AO9gAS3swT9xAXJgAaMrQeEvQeI2QcK7QL1uwLf4wLn3QP+7gP3nwT13QTungatpwbBlwcAAQPl0QP9xAXuwwX9xAWf9Ab9xAUAAA==` 得到 hero dbfId=127745 + 20 种主牌 + 3 张边牌，再用 dbfId 反查 HearthstoneJSON。**这一步纠正了 spike 里三处 cardId**（见 0.2）。

### 0.1 仓库 cardId 核对结果

`rg '"<id>"' HSTracker/ -g '*.swift'`，对 `HSTracker/Logging/CardIds/*.swift`：

| cardId | 卡 | `CardIds.swift` 有登记？ | 本地 `CardDefs.xml` 有？ |
|---|---|---|---|
| `CFM_630` | 伪造的幸运币 | ✅ `Rogue.swift:46 CounterfeitCoin` | ✅ |
| `CORE_EX1_145` | 伺机待发（**牌组用的是 Core 版**） | ✅ `Rogue.swift:178 PreparationCore`（另有 `:72 Preparation = EX1_145`） | ✅ |
| `EX1_144` | 暗影步 | ✅ `Rogue.swift:71 Shadowstep`（另有 `:237 ShadowstepCore = CORE_EX1_144`） | ✅ |
| `CORE_RLK_567` | 殒命暗影（**Core 版**） | ❌ 缺（`RLK_567` 也缺） | ✅ |
| `TSC_916` | 垂钓时光 | ❌ 缺 | ✅ |
| `TOY_510` | 挖掘宝藏 | ✅ `Rogue.swift:175 DigForTreasure` | ✅ |
| `JAM_022` | 致聋术 | ❌ 缺 | ✅ |
| `DED_004` | 黑水弯刀 | ❌ 缺 | ✅ |
| `TLC_515` | 异教地图 | ❌ 缺 | ✅ |
| `CORE_DMF_511` | 狐人老千（**Core 版**） | ❌ 缺（只有 `:207 FoxyFraud = DMF_511`） | ✅ |
| `DEEP_014` | 疾速矿锄 | ✅ `Rogue.swift:242 QuickPick` | ✅ |
| `DMF_515` | 行骗 | ✅ `Rogue.swift:223 Swindle` | ✅ |
| `REV_939` | 锯齿骨刺 | ❌ 缺 | ✅ |
| `LOOT_214` | 闪避 | ✅ `Rogue.swift:127 Evasion`（另有 `:415` 的 `MultiIdCard`） | ✅ |
| `CATA_111` | 晦鳞巢母 | ❌ 缺 | ✅ |
| `WC_016` | 潜伏帷幕 | ✅ `Rogue.swift:231 ShroudOfConcealment` | ✅ |
| `ETC_080` | 乐队经理精英牛头人酋长 | ✅ `Neutral.swift:645 ETCBandManager` | ✅ |
| `BAR_552` | 斯卡布斯·刀油 | ❌ 缺 | ✅ |
| `TRL_092` | 鲨鱼之灵 | ❌ 缺 | ✅ |
| `OG_291` | 暗影施法者 | ✅ `Rogue.swift:114 Shadowcaster` | ✅ |
| `ETC_079` | 舞动全场（ft.迦罗娜） | ✅ `Rogue.swift:259 BounceAroundFtGarona` | ✅ |
| `SCH_352` | 幻觉药水 | ❌ 缺 | ✅ |
| `LEG_CS3_031` | 生命的缚誓者阿莱克丝塔萨 | ❌ 缺（`Neutral.swift:270 Alexstrasza = EX1_561` 是**另一张**九费 8/8 老阿莱，别混） | ✅ |

**结论**：24 张里 **14 个 cardId 在 `CardIds.swift` 里没有常量**，但**全部**在本地 `CardDefs.xml` 里查得到，所以 `Cards.by(cardId:)` 一定能解析，卡名/费用/种族都能读。
T1 要做两件事：① 把缺的 14 个补进 `CardIds.swift`（`Collectible.Rogue` / `Collectible.Neutral`）；② 单元测试断言 24 个 id 都 `Cards.by(cardId:) != nil` 且 `card.name` 对得上。

### 0.2 对 spike 的三处订正

1. **舞动全场不是「各 -1」，是「本回合费用变成 1」**（set，不是 delta）。spike 三、1 写的「全收回各 -1」是旧理解，会把 combo 算少很多。当前文本 `They cost (1) this turn.`，附魔 `ETC_079e "Costs (1) this turn."`。费用也是 **3** 不是 5。
2. **鲨鱼之灵只翻倍「随从的」战吼和连击**：`Your minions' Battlecries and Combos trigger twice.`（附魔 `TRL_092e` 同）。所以**法术连击（致聋术、垂钓时光、行骗）不翻倍**。spike 里列的四个数字（阿莱 16、晦鳞回 4、刀油各 -4、暗影施法者 2 张）全部是随从，与此一致。
3. **三个 cardId 要用 Core 版**：伺机待发 `CORE_EX1_145`、狐人老千 `CORE_DMF_511`、殒命暗影 `CORE_RLK_567`。暗影步是非 Core 的 `EX1_144`。搜索器识别卡时建议按 **dbfId** 或一个 `MultiIdCard` 集合，别写死单个字符串。
4. **英雄是马迪亚斯·肖尔（`HERO_03bm`，dbfId 127745）**，不是瓦莉拉——同为潜行者，英雄技能一样是「匕首精通」（`HERO_03bmhp`，2 费装备 1/2 匕首），对建模无影响。

---

# 第一部分：逐卡表

约定：
- **目标作用域**：`none / friendlyMinion / enemyMinion / anyMinion / anyCharacter`。
- **连击（Combo）条件**：本回合此前已使用过至少一张牌（`NUM_CARDS_PLAYED_THIS_TURN > 0`）。
- **鲨鱼双触发**：`鲨鱼之灵` 在我方场上时，**随从的**战吼与连击各触发两次；法术不受影响。
- 「杂牌」按 spike 八、记法：随从牌、偷费牌（币 / 伺机 / 骨刺）之外的牌。

---

## 1. 伪造的幸运币 / Counterfeit Coin

- **cardId** `CFM_630`（牌组代码 dbfId 40437 → HearthstoneJSON）· 0 费 · 法术 · 无学派 · 主牌 ×2
- **当前文本**
  - EN: `Gain 1 Mana Crystal this turn only.`
  - ZH: `在本回合中，获得一个法力水晶。`
  - 出处 https://hearthstone.wiki.gg/wiki/Counterfeit_Coin
- **搜索器建模**
  - 打出条件：目标作用域 `none`，永远可打。
  - 效果：`gainTempMana(1)`。**临时法力不受水晶上限约束**（可以把本回合可用费用顶到 10 以上），但它**不是水晶**，晦鳞巢母的「复原」不会把它补回来。
  - 连击：无（本身不是连击牌，但它**会把 combo 计数 +1**，是最便宜的「开连击」手段）。
  - 鲨鱼：无关。
  - 随机性：无。
- **交互陷阱**
  - 0 费牌**照样消耗刀油的槽和骨刺的层**（「下两张牌」按张数计，不按费用）。手里有刀油减费在生效时，先甩两张币等于把 -2/-2 浪费掉。这是搜索器最容易多算的地方，必须显式建模槽消耗。
  - **币本身是法术，所以也会消耗伺机待发的那一层**（`appliesTo: .spell`）。序列里币必须排在伺机**之前**，否则伺机白给。
- **不建模**：无。

## 2. 伺机待发 / Preparation

- **cardId** `CORE_EX1_145`（dbfId 69623）· 0 费 · 法术 · 主牌 ×2
- **当前文本**
  - EN: `The next spell you cast this turn costs (2) less.`
  - ZH: `在本回合中，你所施放的下一个法术的法力值消耗减少（2）点。`
  - 出处 https://hearthstone.wiki.gg/wiki/Preparation ；玩家附魔实体 `EX1_145o "The next spell you cast this turn costs (2) less."`
  - ⚠️ **这是削弱后的文本**（原为 -3）。仓库 `CardIds.Collectible.Rogue.Preparation_PreparationEnchantment = "EX1_145o"` 已存在，可直接用来在日志里定位这层减费。
- **搜索器建模**
  - 打出条件：`none`，永远可打。
  - 效果：`pushDiscountLayer(amount: 2, slots: 1, appliesTo: .spell, consumedBy: .spell, oneTurn: true)`。
  - 连击 / 鲨鱼 / 随机性：均无。
- **交互陷阱**
  - **只有施放法术会消耗它**；打随从、装武器、用英雄技能都不消耗。所以「伺机 → 下随从 → 再打大法术」是合法的。
  - 两张伺机叠加：⚠️ 建模为**两层独立层**，下一个法术 -4 且**两层同时消耗**。（见第三部分待核。）
  - 币是法术，会吃掉伺机的这一层——序列里币要放在伺机**之前**。
- **不建模**：无。

## 3. 暗影步 / Shadowstep

- **cardId** `EX1_144`（dbfId 365）· 0 费 · 法术（暗影）· 主牌 ×2
- **当前文本**
  - EN: `Return a friendly minion to your hand. It costs (2) less.`
  - ZH: `将一个友方随从移回你的手牌，它的法力值消耗减少（2）点。`
  - 出处 https://hearthstone.wiki.gg/wiki/Shadowstep
- **搜索器建模**
  - 打出条件：目标作用域 `friendlyMinion`，**必须有合法目标**；我方场上无随从时**不能打**。
  - 效果：`bounce(target, costDelta: -2)` —— 随从回手，回手后的那张牌获得**永久** -2（跨回合保留，可叠加：步两次 = -4）。
  - 连击 / 鲨鱼：无（法术）。
  - 随机性：无。
- **交互陷阱**
  - **腾格主力**：弹回自己场上的随从 = 空出一格，且能再打一次战吼。
  - ⚠️ **手牌满 10 时弹回会「弹进虚空」，随从被销毁**（格子腾出来了，但牌没了）。搜索器必须在 `hand.count == 10` 时把这条分支的结果标成「随从消失」，否则会凭空多算一次战吼。
  - 与舞动全场的**费用叠加顺序**：舞动是「设为 1」，暗影步是「-2」。谁后附加谁生效在上层（先舞动后步 → 0；先步后舞动 → 1）。见第二部分「减费栈」。
  - 弹回**鲨鱼之灵**会让光环消失——序列里所有要翻倍的战吼都得在鲨鱼还在场时打完。
- **不建模**：无。

## 4. 殒命暗影 / Shadow of Demise

- **cardId** `CORE_RLK_567`（dbfId 126088）· 0 费 · 法术（暗影）· 传说 · 主牌 ×1
- **当前文本**
  - EN: `Each time you cast a spell, transform this into a copy of it.`
  - ZH: `每当你施放一个法术，变形成为该法术的复制。`
  - 出处 https://hearthstone.wiki.gg/wiki/Shadow_of_Demise
  - 相关附魔（`cards.json`）：`RLK_567e "Death's Reflection — Always copy your last played card."`、`RLK_567e2 "Shadow of Death — Transforming into recent spells."` → **变形后仍带着这个附魔，所以会一直跟着最后一张法术变**，不是只变一次。
- **搜索器建模**
  - 打出条件：取决于它当前**变成了哪张法术**；未变形时（原始形态）`none`，永远可打但无效果。
  - 效果：本身无效果；它是一个**手牌槽上的镜像**：`mirrorLastSpellCast`。搜索器每执行一次「施放法术 X」，都要把手里这张的身份改写成 X。
  - 连击 / 鲨鱼：无。
  - 随机性：无（完全确定，取决于出牌顺序）。
- **交互陷阱**
  - ⚠️ **复制品的费用**：wiki 只说 28.2.0 修过「复制的是基础版而非精确复制」的 bug。本文按 **「复制品的费用 = 被复制法术的费用」** 建模，并**建议搜索器只在被复制法术费用为 0 时（暗影步 / 伺机 / 币）把这条线折入主线**，其余情况标 ⚠️ 不确定。公式表把「殒」和「步 / 伺 / 骨」并列成「特殊杂牌」，也说明实战里就是拿它抄 0 费法术。
  - 顺序敏感：要抄暗影步，就得让暗影步成为**最后一张施放的法术**，再打这张。中间插一张别的法术就抄错了。
  - 它本身是法术：打出它时**会消耗伺机的层、消耗刀油的槽**。
- **不建模**：跨回合保留的镜像状态（v1 只做单回合，根状态直接读它当前的 `entity.cardId`——日志里它已经变形完了）。

## 5. 垂钓时光 / Gone Fishin'

- **cardId** `TSC_916`（dbfId 72119）· 1 费 · 法术 · 主牌 ×1
- **当前文本**
  - EN: `Dredge. Combo: Draw a card.`
  - ZH: `探底。连击：抽一张牌。`
  - 出处 https://hearthstone.wiki.gg/wiki/Gone_Fishin%27
- **搜索器建模**
  - 打出条件：`none`。
  - 普通效果：`dredge()` —— 看牌库**底部 3 张**，选一张置顶。**本回合手牌不变**，对本回合伤害贡献 0（但仍花 1 费、消耗刀油槽）。
  - 连击效果：`dredge()` 然后 `draw(any, 1)` → 实际结果是**把探底选中的那张抽进手**（探底先结算）。⚠️ 见第三部分待核。
  - 鲨鱼：**不翻倍**（法术连击）。
  - 随机性：**牌库底部 3 张是什么，HSTracker 不知道**（只知道牌库剩余集合，不知道顺序）。
    - `deckRemaining.count <= 3` → 3 张全在底部 → **可折入主线**，等价「从剩余牌里任选一张抽进手」。
    - 否则 → 只能分支，且**每条分支都不保证**（那张牌可能不在底 3）。**建议 v1 默认不折入**，把连击垂钓当成 `draw(unknownFromDeck, 1)` 的概率分支并标「取决于探底」。
- **交互陷阱**：无连击时它是纯 tempo 亏损，搜索器要允许「打出但什么都不做」（用来开连击 / 腾手牌格）。
- **不建模**：探底的置顶效果对**下回合**的意义（v1 单回合）。

## 6. 挖掘宝藏 / Dig for Treasure

- **cardId** `TOY_510`（dbfId 103341）· 1 费 · 法术 · 主牌 ×2
- **当前文本**
  - EN: `Draw a minion. If it's a Pirate, get a Coin.`
  - ZH: `抽一张随从牌。如果是海盗牌，获取一张幸运币。`
  - 出处 https://hearthstone.wiki.gg/wiki/Dig_for_Treasure
- **搜索器建模**
  - 打出条件：`none`。
  - 效果：`draw(filter: .minion, n: 1)`。
  - 连击 / 鲨鱼：无。
  - 随机性：抽牌源 = **牌库里剩下的随从**。本牌组主牌只有 **6 张随从**（暗影施法者、鲨鱼之灵、斯卡布斯、E.T.C.、狐人老千、晦鳞巢母；**阿莱在边牌，不在牌库**）。
    - `remainingMinions == 0` → 空过（HSTracker 能确定），只花费用。
    - `remainingMinions == 1` → 确定，折入主线。
    - 否则 → 按剩余随从种类分支。
- **交互陷阱**
  - **「海盗 → 给币」这一条在本牌组永远不触发**：主牌 6 张随从的种族分别是 —— 暗影施法者(无)、鲨鱼之灵(亡灵/野兽)、斯卡布斯(无)、E.T.C.(无)、狐人老千(无)、晦鳞巢母(龙)，**没有海盗**。**明确忽略**，并在实现里写死断言，换牌时会失败。
  - 手牌满 10 时抽到的牌**被烧掉**。
- **不建模**：海盗分支（理由同上）。

## 7. 致聋术 / Deafen

- **cardId** `JAM_022`（dbfId 98377）· 1 费 · 法术（暗影）· **双职业 牧师 + 潜行者** · 主牌 ×1
- **当前文本**
  - EN: `Silence a minion. Combo: Also deal $2 damage to it.`
  - ZH: `沉默一个随从。连击：并对其造成$2点伤害。`
  - 出处 https://hearthstone.wiki.gg/wiki/Deafen
- **搜索器建模**
  - 打出条件：目标作用域 `anyMinion`，**必须有合法目标**（任一方场上有随从）；全场无随从时不能打。
  - 普通效果：`silence(target)`。
  - 连击效果：`silence(target)` + `damage(2 + spellDamage, target)`。`$` 前缀表示**吃法术伤害加成**（`current_spellpower`，GameTag 291）。
  - 鲨鱼：**不翻倍**（法术连击）。
  - 随机性：无。
- **交互陷阱（本文最重要的一条）**
  - ⚠️⚠️ **「致聋术打自己的 1/1 复制体来腾格」是错的**。幻觉药水 / 暗影施法者的「1/1」是**附魔**（`SCH_352e "1/1."`、`OG_291e "Shadowcaster made this 1/1."`），**沉默会把附魔一起移除，随从恢复原始身材**。所以：
    - 致聋术打 1/1 阿莱复制体 → 变成 **8/8**，再吃 2 点 → **8/6，活着，格子没腾出来**。
    - 只有**基础生命值 ≤ 2** 的随从会被「沉默 + 2 伤」打死。本牌组基础生命：暗影施法者 4、鲨鱼之灵 3、斯卡布斯 3、E.T.C. 4、狐人老千 **2**、晦鳞巢母 3、阿莱 8 → **只有狐人老千的复制体会死**。
  - 这**正是 win 项目 issue #2 / #3「致聋术建模错，算出的 64 伤线在游戏里打不出来」的根因**，spike 八、里「致聋术 = 腾格牌」的说法要按这条订正：致聋术只对狐人老千复制体是腾格牌，其余情况它是**沉默牌**（拆对方嘲讽 / 拆对方光环）。干净的腾格工具是**锯齿骨刺**（纯 3 伤，不沉默）和**暗影步 / 舞动全场**。
  - 沉默自己的鲨鱼之灵 = **光环立刻消失**，后续战吼不再翻倍。搜索器必须在沉默结算后重算光环。
- **不建模**：沉默对对方随从的长期价值（v1 只算本回合伤害；沉默嘲讽 = 解锁攻击路径，**这一条要建模**，因为影响平 A）。

## 8. 黑水弯刀 / Blackwater Cutlass

- **cardId** `DED_004`（dbfId 65597）· 1 费 · **武器 2/2** · 主牌 ×1
- **当前文本**
  - EN: `Tradeable — After you Trade this, reduce the Cost of a spell in your hand by (1).`
  - ZH: `可交易 — 在你交易此牌后，使你手牌中的一张法术牌的法力值消耗减少（1）点。`
  - 出处 https://hearthstone.wiki.gg/wiki/Blackwater_Cutlass ；附魔 `DED_004e "Blackwater Treasure — Costs (1) less."`
- **搜索器建模**
  - 动作一 `playCard`：`equipWeapon(atk: 2, durability: 2)` —— **替换**当前武器。英雄攻击力变 2。
  - 动作二 `tradeCard`（可交易）：花 **1 费**，把这张牌**洗回牌库**并 `draw(any, 1)`，然后 `discountCard(-1, 一张手牌中的法术)`。
  - 连击 / 鲨鱼：无。
  - 随机性：① 交易抽到什么 = 牌库剩余全集分支；② ⚠️ 减费落在**哪张法术**上——文本没写「发现」，按**随机一张手牌法术**建模；手里只有一张法术时确定。
- **交互陷阱**
  - 装它 = 覆盖疾速矿锄（丢掉「攻击后抽牌」），装矿锄 = 覆盖它（攻击力 2 → 1）。**同一回合最多一次英雄攻击**，所以「装哪把」是一个二选一，不是叠加。
  - 英雄技能匕首精通（2 费 1/2）攻击力更低且更贵，一般只在没别的武器时用。
- **不建模**：耐久度跨回合（v1 单回合）。

## 9. 异教地图 / Cultist Map

- **cardId** `TLC_515`（dbfId 117697）· 2 费 · 法术（暗影）· 主牌 ×2
- **当前文本**
  - EN: `Discover a card from your deck. If you play it this turn, also pick one of the others.`
  - ZH: `从你的牌库中发现一张牌，如果你在本回合中使用该牌，再从其余选项中选择一张。`
  - 出处 https://hearthstone.wiki.gg/wiki/Cultist_Map ；玩家附魔 `TLC_515e "Cultist Map Player Enchant — If you play the Discovered card this turn, also choose one of the other two options."`
- **搜索器建模**
  - 打出条件：`none`（牌库空时无效果）。
  - 效果：`discoverFromDeck(offer: 3, take: 1)` → 该牌进手、离开牌库；同时挂一个**待触发钩子**：`onPlay(thatCard, thisTurn) -> takeOneOf(otherTwoOffered)`（第二张也从牌库取走）。
  - 连击 / 鲨鱼：无。
  - 随机性：**三选一里「提供哪 3 张」是随机的**。
    - `deckRemaining.distinctCards <= 3` → 三个选项就是全部剩余牌，**可折入主线**（枚举 ≤3 条确定分支）。
    - 否则 → 分支，但**不保证**目标牌被提供，整条线标「概率」。
  - **这是本牌组分支因子最大的牌（两张，且是两级发现）**。建议 v1：只在能确定时展开，否则把它当成「花 2 费 + 抽 1 张未知牌」的截断点。
- **交互陷阱**：第二次选择要求「**本回合把第一张打出去**」，所以第一张必须是打得起、且有合法目标的牌，否则第二张拿不到。搜索器要把这个前置条件真的验一遍（属于路径重放校验的一部分）。
- **不建模**：无。

## 10. 狐人老千 / Foxy Fraud

- **cardId** `CORE_DMF_511`（dbfId 120460）· 2 费 · 随从 **3/2** · 无种族 · 主牌 ×1
- **当前文本**
  - EN: `Battlecry: Your next Combo card this turn costs (2) less.`
  - ZH: `战吼：在本回合中，你的下一张连击牌法力值消耗减少（2）点。`
  - 出处 https://hearthstone.wiki.gg/wiki/Foxy_Fraud ；玩家附魔 `DMF_511e "Enabling"`、手牌附魔 `DMF_511e2 "Cheaper Combos — Costs (2) less."`
- **搜索器建模**
  - 打出条件：目标作用域 `none`（无目标战吼），**需要一个场上格子**。
  - 效果：`pushDiscountLayer(amount: 2, slots: 1, appliesTo: .comboCard, consumedBy: .comboCard, oneTurn: true)`。
  - 连击：本身无连击。
  - **鲨鱼双触发**：→ **两层**同样的层 → 下一张连击牌 **-4**，两层同时消耗。
  - 随机性：无。
- **交互陷阱**
  - **只作用于「带连击关键字」的牌**。本牌组的连击牌只有 4 种：垂钓时光、致聋术、行骗、**斯卡布斯·刀油**。狐 → 刀油（4 → 2，鲨鱼在场 4 → 0）是核心用法。
  - 打非连击牌**不会**消耗这一层（层是「下一张连击牌」）。
  - 基础生命 2 —— 全牌组唯一一张会被「沉默 + 2 伤」打死的随从（见 §7）。
- **不建模**：无。

## 11. 疾速矿锄 / Quick Pick

- **cardId** `DEEP_014`（dbfId 102254）· 2 费 · **武器 1/2** · 双职业 潜行者 + 恶魔猎手 · 主牌 ×2
- **当前文本**
  - EN: `After your hero attacks, draw a card.`
  - ZH: `在你的英雄攻击后，抽一张牌。`
  - 出处 https://hearthstone.wiki.gg/wiki/Quick_Pick
- **搜索器建模**
  - 打出条件：`none`。`equipWeapon(atk: 1, durability: 2, trigger: .afterHeroAttack(draw: 1))`，**替换**当前武器。
  - 动作 `heroAttack(target)`：英雄本回合未攻击过 → 造成 1 点伤害（可打脸，也可用来撞对方随从），耐久 -1，然后 `draw(any, 1)`。
  - 连击 / 鲨鱼：无。
  - 随机性：抽到什么 = 牌库剩余全集分支；`deckRemaining <= 1` 时确定。
- **交互陷阱**
  - 「英雄攻击」在**有嘲讽时被强制导向嘲讽**——想用矿锄打脸抽牌，得先解掉嘲讽。
  - 装第二把矿锄会**覆盖**第一把（耐久重置为 2），但**英雄一回合仍只能攻击一次**，所以第二把在本回合毫无收益。
  - 这是本牌组**唯一稳定的「花 2 费换一张牌」**，在缺零件的线里很关键。
- **不建模**：耐久跨回合、风怒。

## 12. 行骗 / Swindle

- **cardId** `DMF_515`（dbfId 61159）· 2 费 · 法术 · 主牌 ×2
- **当前文本**
  - EN: `Draw a spell. Combo: And a minion.`
  - ZH: `抽一张法术牌。连击：并抽一张随从牌。`
  - 出处 https://hearthstone.wiki.gg/wiki/Swindle
- **搜索器建模**
  - 打出条件：`none`。
  - 普通效果：`draw(filter: .spell, n: 1)`。
  - 连击效果：`draw(.spell, 1)` + `draw(.minion, 1)`。
  - 鲨鱼：**不翻倍**（法术连击）。
  - 随机性：两个独立的池 —— 法术池（牌库共 21 张法术）、随从池（牌库共 6 张随从）。各自按「剩余 ≤ 抽取数 → 确定」折入。**随从池小，中后期经常是确定的**，这是本牌组抽牌能折入主线的主要来源。
- **交互陷阱**：手牌满 10 时抽到的被烧。连击的两张抽牌是**先法术后随从**，手牌格子只剩 1 个时后一张会烧掉。
- **不建模**：无。

## 13. 锯齿骨刺 / Serrated Bone Spike

- **cardId** `REV_939`（dbfId 77557）· 2 费 · 法术 · 主牌 ×2
- **当前文本**
  - EN: `Deal $3 damage to a minion. If it dies, your next card this turn costs (2) less.`
  - ZH: `对一个随从造成$3点伤害。如果该随从死亡，在本回合中，你的下一张牌法力值消耗减少（2）点。`
  - 出处 https://hearthstone.wiki.gg/wiki/Serrated_Bone_Spike ；玩家附魔 `REV_939e2 "Serrated — Your next card this turn costs (2) less."`
- **搜索器建模**
  - 打出条件：目标作用域 `anyMinion`，**必须有合法目标**。
  - 效果：`damage(3 + spellDamage, target)`；若目标**因此死亡** → `pushDiscountLayer(amount: 2, slots: 1, appliesTo: .any, consumedBy: .any, oneTurn: true)`。
  - 连击 / 鲨鱼：无。
  - 随机性：无。
- **击杀判定（必须精确，决定减不减费）**
  1. 目标 `immune` → 不结算伤害，不死。
  2. 目标有 `divine_shield` → 圣盾破，伤害归 0，**不死 → 不减费**。
  3. 否则 `health - damage <= 0` 即死（`health` 用 `Entity.health = [.health] - [.damage]`）。
  4. 法术伤害加成 `current_spellpower` 要加进去（本牌组一般为 0，但对方 / 复制体可能带）。
- **交互陷阱**
  - **腾格首选**：3 伤打死自己场上的 1/1 复制体（不沉默，所以 1/1 就是 1/1，稳死），腾出一格**并且**下一张牌 -2。这是公式表里「腾格是骨刺时 5 水晶」的那 2 费来源。
  - 打死**自己的鲨鱼之灵**（0/3）→ 光环没了，别乱腾。
  - **打不到英雄**，对斩杀伤害的直接贡献是 0。
- **不建模**：无。

## 14. 闪避 / Evasion

- **cardId** `LOOT_214`（dbfId 45535）· 2 费 · 法术 · **奥秘** · 主牌 ×2
- **当前文本**
  - EN: `Secret: After your hero takes damage, become Immune this turn.`
  - ZH: `奥秘：你的英雄在受到伤害后，在本回合中免疫。`
  - 出处 https://hearthstone.wiki.gg/wiki/Evasion
- **搜索器建模**
  - 打出条件：`none`（同名奥秘已在场时不能打；奥秘上限 5）。
  - 效果：`castSecret` —— **对本回合伤害贡献 0**。
  - 连击 / 鲨鱼 / 随机性：无。
- **为什么仍要留在动作集合里**：它是「杂牌」，打出去会 ① 花 2 费、② **消耗刀油 / 骨刺的槽**、③ **腾出一个手牌格**。第三条在药水 / 暗影施法者往手里塞复制品、手牌接近 10 张时是**有正收益的**，所以不能从动作集合里删掉，只能建成「无效果但可打出」。
- **不建模**（明确忽略 + 理由）
  - 免疫效果本身：只在**对手回合**才有意义，v1 只算我方本回合伤害。
  - 奥秘上限 5 / 同名限制：本牌组只有这一种奥秘、最多 2 张，且第二张打不出（同名奥秘不能重复）——**要建模同名限制**，否则会算出「打两张闪避腾两个手牌格」这种非法动作。

## 15. 晦鳞巢母 / Darkscale Broodmother

- **cardId** `CATA_111`（dbfId 122500）· 3 费 · 随从 **4/3** · **龙** · 中立 · 主牌 ×1
- **当前文本**
  - EN: `Battlecry: If you're holding a Dragon, refresh 2 Mana Crystals.`
  - ZH: `战吼：如果你的手牌中有龙牌，复原两个法力水晶。`
  - 出处 https://hearthstone.wiki.gg/wiki/Darkscale_Broodmother （2026-03-10 Patch 35.0.0 加入，CATACLYSM 系列）
- **搜索器建模**
  - 打出条件：`none`（无目标战吼），**需要一个场上格子**。
  - 效果：`refreshMana(2, condition: .holdingDragon)`。
    - 条件判定时机：**战吼结算时**，此时这张牌**已经离开手牌**。所以「手里有龙」指的是**另一张**龙牌 —— 本牌组的龙只有两种：**晦鳞巢母自己（的复制体）** 和 **阿莱克丝塔萨（含 1/1 复制体）**。
    - 「复原」= `currentMana = min(currentMana + 2, maxMana)`，**不能超过水晶上限**，也**不会补回临时法力（币）**。这就是公式表把「水晶数」单列的原因：水晶不够时回费直接亏掉。
  - 连击：无。
  - **鲨鱼双触发**：两次独立的 `refresh 2`，各自受上限约束 → 实际最多回 4（`min(cur+2, max)` 连做两次）。
  - 随机性：无。
- **交互陷阱**
  - 判断「手里有龙」要用 `entity.card.races.contains(.dragon)`（`Card.races: [Race]` 已有，见 `Database.swift:202/226`）。**鲨鱼之灵是亡灵/野兽，不是龙**。
  - 药水 / 暗影施法者做出的 1/1 晦鳞复制体**仍是龙**，所以「手里留一张晦鳞复制体」就能满足条件——这是回费引擎能连转的关键。
  - `maxMana` 要用 `Player.maxMana`（水晶数），不是 `currentMana`。
- **不建模**：无。

## 16. 潜伏帷幕 / Shroud of Concealment

- **cardId** `WC_016`（dbfId 63358）· 3 费 · 法术（暗影）· 主牌 ×2
- **当前文本**
  - EN: `Draw 2 minions. Any played this turn gain Stealth for 1 turn.`
  - ZH: `抽两张随从牌，在本回合中使用则使其获得潜行一回合。`
  - 出处 https://hearthstone.wiki.gg/wiki/Shroud_of_Concealment ；附魔 `WC_016e "Cloaking"`、`WC_016e2 "Cloaked — Stealth for 1 turn."`
- **搜索器建模**
  - 打出条件：`none`。
  - 效果：`draw(filter: .minion, n: 2)`。
  - 连击 / 鲨鱼：无。
  - 随机性：随从池（牌库最多 6 张随从）。`remainingMinions <= 2` → **确定，折入主线**。这是本牌组最容易折入的抽牌牌。
- **交互陷阱**：手牌格不够 2 张时后一张被烧。牌库随从不足 2 张时只抽到有的那些。
- **不建模**（明确忽略）：**潜行**。潜行不影响我方随从攻击（潜行随从照样能攻击，攻击后失去潜行），只影响**对手回合**能不能被指向，与本回合伤害无关。

## 17. 乐队经理精英牛头人酋长 / E.T.C., Band Manager

- **cardId** `ETC_080`（dbfId 90749）· 4 费 · 随从 **4/4** · 中立传说 · 主牌 ×1
- **当前文本**
  - EN: `While building your deck, assemble a band of 3 cards. Battlecry: Discover one!`
  - ZH: `在构筑你的套牌时，用3张牌组建一支乐队。战吼：发现其中一张！`
  - 出处 https://hearthstone.wiki.gg/wiki/E.T.C.,_Band_Manager
- **搜索器建模**
  - 打出条件：`none`（无目标战吼），**需要一个场上格子**。
  - 效果：`discoverFromSideboard(pool: remainingBand, take: 1)` —— 发现后该牌**永久离开边牌池**（本局不再出现）。
  - 连击：无。
  - **鲨鱼双触发**：**两次发现** → 第二次只在剩下的两张里选。若三张都在，`(取 2 张)` 的组合数 = C(3,2) = 3 条分支。
  - 随机性：**边牌池 HSTracker 完全已知**（`DeckSideboards`），所以这是**枚举，不是概率**：v1 直接展开全部分支。
- **交互陷阱**
  - **阿莱克丝塔萨只在边牌里**，所以每条 combo 都必须先过 E.T.C.。「牛」出现在每条公式里就是这个原因。
  - 场上 7 格的分母里 E.T.C. 占 1 格（鱼狐刀暗牛晦龙正好 7）。
  - 发现的牌进手 → 手牌满 10 时**发现不到**（要在动作合法性里挡掉，属于路径重放校验）。
- **不建模**：边牌的构筑期限制。

## 18. 斯卡布斯·刀油 / Scabbs Cutterbutter

- **cardId** `BAR_552`（dbfId 63517）· 4 费 · 随从 **3/3** · 潜行者传说 · 主牌 ×1
- **当前文本**
  - EN: `Combo: The next two cards you play this turn cost (2) less.`
  - ZH: `连击：在本回合中，你使用的下两张牌的法力值消耗减少（2）点。`
  - 出处 https://hearthstone.wiki.gg/wiki/Scabbs_Cutterbutter ；玩家附魔 `BAR_552o "Cookin! — The next two cards you play this turn costs (2) less."`
  - ⚠️ **削弱后文本**：Patch 32.2.4.221850（2025-05-22）由 **(3) less → (2) less**。spike 六、表里说的「刀油削弱」就是这次。
  - Patch 22.0.0.127581 修过优先级：**刀油的减费优先级最低，可被其它费用修改效果覆盖**。
- **搜索器建模**
  - 打出条件：`none`（无目标战吼），**需要一个场上格子**。
  - 普通效果（未连击）：只是一个 3/3。
  - 连击效果：`pushDiscountLayer(amount: 2, slots: 2, appliesTo: .any, consumedBy: .any, oneTurn: true)`。
  - **鲨鱼双触发**：`push` **两层**（各 2 槽 -2）→ **下两张牌各 -4**，两层的槽**同步递减**（不是 4 槽 -2）。这就是 spike 三、3 说的「一层 2 槽」，双层就是「两层各 2 槽」。
  - 随机性：无。
- **交互陷阱**
  - **任何牌都消耗槽**，包括 0 费的币 / 伺机 / 暗影步。序列里把 0 费牌塞进刀油的两槽 = 白白浪费 -4。这是搜索器最容易高估伤害的地方。
  - 连击条件要求**本回合此前已出过牌**，所以刀油不能当回合第一张打（除非只想要 3/3 身材）。
  - 狐人老千的层作用于「连击牌」，**刀油自己就是连击牌** → 狐 → 刀油是标准起手。
- **不建模**：优先级细节（我们用 `max(0, effBase - Σ)` 统一算，见第二部分；仅在与「设为 1」类效果同时存在时有分歧，已在待核清单）。

## 19. 鲨鱼之灵 / Spirit of the Shark

- **cardId** `TRL_092`（dbfId 49972）· 4 费 · 随从 **0/3** · **亡灵 / 野兽** · 主牌 ×1
- **当前文本**
  - EN: `Stealth for 1 turn. Your minions' Battlecries and Combos trigger twice.`
  - ZH: `潜行一回合。你的随从的战吼和连击触发两次。`
  - 出处 https://hearthstone.wiki.gg/wiki/Spirit_of_the_Shark ；光环附魔 `TRL_092e "Power of the Shark"`
- **搜索器建模**
  - 打出条件：`none`，**需要一个场上格子**。
  - 效果：**光环**（`mechanics: [AURA, STEALTH]`），在场期间 `battlecryTriggers = 2`、`minionComboTriggers = 2`。
  - ⚠️ **只对随从生效**。本牌组受影响的：阿莱克丝塔萨（战吼）、晦鳞巢母（战吼）、暗影施法者（战吼）、E.T.C.（战吼）、狐人老千（战吼）、斯卡布斯（连击）。**不受影响**：致聋术、垂钓时光、行骗（法术连击）、幻觉药水、舞动全场、暗影步（法术）。
  - 随机性：无。
- **具体数字（鲨鱼在场时）**

  | 牌 | 单次 | 鲨鱼在场 |
  |---|---|---|
  | 阿莱克丝塔萨 | 8 伤 | **16 伤**（两次独立的 8） |
  | 晦鳞巢母 | 复原 2 水晶 | **复原 4**（两次 `min(cur+2, max)`） |
  | 斯卡布斯·刀油 | 下两张各 -2 | **下两张各 -4**（两层） |
  | 暗影施法者 | 进手 1 张 1/1 复制 | **进手 2 张**（同一个目标） |
  | 乐队经理 E.T.C. | 发现 1 张边牌 | **发现 2 张** |
  | 狐人老千 | 下一张连击牌 -2 | **-4** |

- **交互陷阱**
  - **0 攻击力 → 不能攻击**，不能靠平 A 腾自己的格子；只能用暗影步弹回、舞动全场、或骨刺打死（3 伤刚好打死 0/3）。
  - 光环**只在它在场时**生效：任何把它弹回 / 打死 / 沉默的动作之后，后续战吼恢复单次。搜索器每一步都要重算「鲨鱼是否在场」。
  - ⚠️ **两条鲨鱼同时在场**（药水复制出 1/1 鲨鱼再打下去，光环文本保留）→ 触发次数按「乘」建模为 4 次，见第三部分待核。
- **不建模**：潜行（理由同 §16）。

## 20. 暗影施法者 / Shadowcaster

- **cardId** `OG_291`（dbfId 38876）· 5 费 · 随从 **4/4** · 主牌 ×1
- **当前文本**
  - EN: `Battlecry: Choose a friendly minion. Add a 1/1 copy to your hand that costs (1).`
  - ZH: `战吼：选择一个友方随从，将它的一张1/1的复制置入你的手牌，其法力值消耗为（1）点。`
  - 出处 https://hearthstone.wiki.gg/wiki/Shadowcaster ；附魔 `OG_291e "Flickering Darkness — Shadowcaster made this 1/1."`
- **搜索器建模**
  - 打出条件：目标作用域 `friendlyMinion`，**需要一个场上格子**。~~目标总是存在（战吼结算时它自己已经在场上，可以指自己）~~ **错。指向性战吼在下场前选目标，自己不在候选里**（用户 2026-09-11 确认）。场上没有别的友方随从时**裸下、不触发**。
  - 效果：`copyToHand(target, setStats: 1/1, setCost: 1, keepPrintedText: true, dropEnchantments: true)`。
  - **鲨鱼双触发**：**两张**复制进手，**目标相同**（目标在打出时就锁定，第二次不重新选）。
  - 随机性：无。
- **交互陷阱**
  - **复制品保留卡牌原文（含战吼）**，但**不带原随从身上的附魔**。所以复制一个已经是 1/1 的复制体，得到的还是 1/1 费用 1 的复制体（可无限循环）。
  - 复制**场上的阿莱** → 手里一张 1 费、打出去仍造成 8 伤（鲨鱼在场 16）的牌。**这是整套 combo 的伤害引擎。**
  - 「费用为 1」是 **set**，且**永久**（不是本回合）。后续减费（刀油 -2 / 伺机）会把它压到 0。
  - ⚠️ 手牌满 10 时复制被烧。鲨鱼在场要塞 2 张，要有 2 个空格。
  - **沉默会让 1/1 变回原始身材**（见 §7）。
- **不建模**：无。

## 21. 舞动全场（ft.迦罗娜）/ Bounce Around (ft. Garona)

- **cardId** `ETC_079`（dbfId 90606）· **3 费** · 法术 · 潜行者传说 · **边牌**
- **当前文本**
  - EN: `Return all friendly minions to your hand. They cost (1) this turn.`
  - ZH: `将所有友方随从移回你的手牌。在本回合中，其法力值消耗为（1）点。`
  - 出处 https://hearthstone.wiki.gg/wiki/Bounce_Around_(ft._Garona) ；附魔 `ETC_079e "Bouncing Around — Costs (1) this turn."`
  - ⚠️ **订正 spike**：是「**设为 1**」，不是「-1」。
- **搜索器建模**
  - 打出条件：`none`（我方场上无随从时打出无效果）。
  - 效果：对**所有**我方随从 `bounce(setCostThisTurn: 1)`。**一次性清空自己的场面** → 7 格全空（最大的腾格）。
  - 连击 / 鲨鱼：无（法术）。
  - 随机性：无。
- **交互陷阱**
  - ⚠️ **手牌上限 10**：弹回的随从超过手牌容量的部分**被销毁**。⚠️ 销毁顺序（场上从左到右 / 召唤顺序）待核，见第三部分。这是「杂牌数」这一列存在的直接原因。
  - **费用是「设为 1，仅本回合」**，与暗影步的「永久 -2」叠加时顺序敏感（见 §3 / 第二部分）。
  - 弹回鲨鱼 → 光环消失，但它变成一张 **1 费**的鲨鱼牌，可以立刻重新下场（本回合再开光环）。这就是「三阶段」公式里舞动分段的意义。
  - 弹回阿莱 → 一张 **1 费**的阿莱，再打一次 8/16 伤。
- **不建模**：无。

## 22. 幻觉药水 / Potion of Illusion

- **cardId** `SCH_352`（dbfId 59621）· 4 费 · 法术（奥术）· **双职业 法师 + 潜行者** · **边牌**
- **当前文本**
  - EN: `Add 1/1 copies of your minions to your hand. They cost (1).`
  - ZH: `将你的所有随从的1/1的复制置入你的手牌，并使其法力值消耗变为（1）点。`
  - 出处 https://hearthstone.wiki.gg/wiki/Potion_of_Illusion ；附魔 `SCH_352e "1/1."`、`SCH_352e2 "Costs (1)."`
- **搜索器建模**
  - 打出条件：`none`（场上无随从则无效果）。
  - 效果：对**每一个**我方场上随从 `copyToHand(setStats: 1/1, setCost: 1, keepPrintedText: true, dropEnchantments: true)`。**原随从留在场上**（不是弹回！与舞动全场的关键区别）。
  - 连击 / 鲨鱼：无（法术）。
  - 随机性：无。
- **交互陷阱**
  - **格子不变、手牌暴涨** —— 药水是「制造复制」，舞动是「腾格 + 制造便宜牌」，两者互补且顺序不同结果差很多。
  - ⚠️ **手牌上限 10**：超出的复制**被烧**。场上 7 个随从 + 手里 6 张杂 → 只有 4 张能进手。「杂牌数」这一列直接决定药水的收益。
  - 「费用 1」是 **set 且永久**（文本无「this turn」）。
  - 复制品保留原文（战吼/光环），不带附魔 —— 复制 1/1 阿莱得到的还是 1 费 1/1 阿莱；复制鲨鱼得到 1 费 1/1 鲨鱼（光环仍在）。
- **不建模**：无。

## 23. 生命的缚誓者阿莱克丝塔萨 / Alexstrasza the Life-Binder

- **cardId** `LEG_CS3_031`（dbfId 113183）· **9 费** · 随从 **8/8** · **龙** · 中立传说 · **边牌**
- **当前文本**
  - EN: `Battlecry: Choose a character. If it's friendly, restore #8 Health. If it's an enemy, deal 8 damage.`
  - ZH: `战吼：选择一个角色。如果是友方角色，为其恢复#8点生命值；如果是敌方角色，对其造成8点伤害。`
  - 出处 https://hearthstone.wiki.gg/wiki/Alexstrasza_the_Life-Binder
  - ⚠️ 别与 `EX1_561` / `Neutral.swift:270` 的老「阿莱克丝塔萨」（把生命值设为 15）混淆——是两张不同的牌。
- **搜索器建模**
  - 打出条件：目标作用域 `anyCharacter`，**需要一个场上格子**。敌方英雄永远是合法目标，所以总能打。
  - 效果：`damage(8, target)` 若目标是敌方；`heal(8, target)` 若是友方。**8 是定值，不吃法术伤害加成**（战吼不是法术，且文本是 `#8` 不是 `$8`）。
  - **鲨鱼双触发**：**两次独立的 8 伤**（不是一次 16）—— 对方有「受到伤害后」类奥秘 / 免疫时结果不同。
  - 随机性：无。
- **交互陷阱**
  - **本牌组唯一的打脸伤害源**，所有伤害数字都是 8 的倍数（8/16/32/48/64/…）。
  - 只能从**边牌**经 E.T.C. 拿到；之后靠暗影步 / 舞动 / 药水 / 暗影施法者反复复用。
  - 打出后 8/8 站在场上**占一格**（1/1 复制体也占一格），要靠腾格牌清掉才能继续下人。
  - 敌方英雄**免疫**（如冰箱、对方的闪避）时 8 伤全部无效 —— 状态里要有 `opponentHero.immune`。
- **不建模**：治疗友方的分支（v1 只算伤害；实现上保留 `heal` 动作但搜索器不展开，理由：本回合伤害无关）。

## 24. 英雄技能：匕首精通 / Dagger Mastery

- **cardId** `HERO_03bmhp`（本局英雄 `HERO_03bm` 马迪亚斯·肖尔；瓦莉拉是 `HERO_03bp`，技能相同）· 2 费
- **当前文本**
  - EN: `Hero Power — Equip a 1/2 Dagger.`
  - ZH: `英雄技能 — 装备一把 1/2 的匕首。`
- **搜索器建模**
  - 打出条件：本回合未使用过英雄技能（英雄技能实体 `[.exhausted] == 0`），费用 ≥ 2。
  - 效果：`equipWeapon(atk: 1, durability: 2)`，**替换**当前武器。
  - 随机性：无。
- **交互陷阱**：2 费换 1 点脸伤，性价比极低；只在「已经没别的用途、还差 1 点」时才有意义。**会覆盖黑水弯刀的 2 攻**，绝不能在弯刀已装备时用。
- **不建模**：无。

---

# 第二部分：搜索状态与动作

## A. 状态字段清单

字段名英文；「来源」列写 HSTracker 的属性或 GameTag（路径:行号沿用 spike 四、）。

### A1. 资源

| 字段 | 类型 | 来源 | 说明 |
|---|---|---|---|
| `maxMana` | Int | `Player.maxMana` | 水晶数。**晦鳞复原的上限**。公式表「水晶数」列 |
| `currentMana` | Int | `Player.currentMana`（`Player.swift:266`） | 当前可用（不含尚未打出的币） |
| `tempMana` | Int | 前推时自己算 | 币给的临时法力，**不受 `maxMana` 约束、不被复原补回** |
| `cardsPlayedThisTurn` | Int | `CardsPlayedThisTurnCounter`（`CounterSystem/Counters/`）或 GameTag `NUM_CARDS_PLAYED_THIS_TURN` | 连击条件 = `> 0` |
| `spellDamage` | Int | `current_spellpower`（GameTag 291），读法先例 `ShimmerShot.swift:19-20` | 只影响骨刺 / 致聋术打随从 |
| `heroAttackedThisTurn` | Bool | 英雄实体 `NUM_ATTACKS_THIS_TURN > 0` | 英雄一回合一次攻击 |
| `heroPowerUsed` | Bool | 英雄技能实体 `[.exhausted] == 1` | |
| `weapon` | `Weapon?` | `PlayerBoard.getWeapon(list:)`；英雄+武器攻击力 `BoardHero.swift:37-66` | `attack / durability / cardId`（矿锄要记「攻击后抽牌」） |

### A2. 手牌

`hand: [HandCard]`，来源 `Player.hand`（`Player.swift:189`，**取一次缓存，别在循环里反复过滤全量 entities**）。

| 字段 | 来源 |
|---|---|
| `entityId` | `Entity.id` |
| `cardId` | `Entity.cardId`（殒命暗影会变形，读的就是变形后的 id） |
| `cost` | **`entity[.cost]`** —— 日志已算好全部减费，根状态**绝不重算** |
| `zonePosition` | `Entity.zonePosition`（`Entity.swift:218-224`，从 1 起） |
| `type / isCombo / isDragon / baseCost` | `Entity.card`（带缓存，`Entity.swift:200-208`）+ `Card.races` |
| `setCostEnchant` | 前推时自己维护（药水/暗影施法者/舞动的「设为 1」） |
| `perCardDelta` | 前推时自己维护（暗影步 -2、弯刀交易 -1） |

### A3. 我方场面

`board: [BoardMinion]`，来源 `Player.board`。

| 字段 | 来源 |
|---|---|
| `entityId / cardId` | `Entity` |
| `attack / health / maxHealth` | `entity[.atk]`、`Entity.health`（`= [.health] - [.damage]`，`Entity.swift:180`） |
| `summoningSick` | `entity[.exhausted] == 1`（本回合刚下）。**不能攻击，但战吼照触发** |
| `taunt / stealth / divineShield / immune / cantAttack / windfury` | `entity[.taunt]` 等，先例 `BoardCard.swift:67-85` |
| `hasSharkAura` | `cardId == TRL_092`（含 1/1 复制体） |
| `isStatSetTo1x1` | 有 `OG_291e` / `SCH_352e` 附魔 → **被沉默会变回原身材** |

`boardSlotsFree = 7 - board.count`。

### A4. 敌方

| 字段 | 来源 |
|---|---|
| `opponentHero.health` | `Entity.health`（`= [.health] - [.damage]`）。**不要用 `Game.opponentHeroHealth`**（没减伤害也没算护甲） |
| `opponentHero.armor` | `hero[.armor]`（GameTag 292） |
| `opponentHero.immune` | `hero[.immune]` |
| `opponentBoard[]` | `attack / health / taunt / divineShield / immune / poisonous` |
| `opponentSecretCount` | 已知奥秘数量（贼看不到内容 → 只在角标旁标 `⚠ 对方有奥秘`） |

`effectiveEnemyHealth = health + armor` → `lethal_threshold`。

### A5. 牌库 / 边牌

| 字段 | 来源 |
|---|---|
| `deckRemaining` | `Player.getDeckState()`（spike 二、4）。要能按类型切片：`.minion`（本牌组最多 6）/ `.spell`（最多 21）/ `.any`（30） |
| `deckOrderKnown` | 恒 false。**探底 / 异教地图的「哪 3 张」不可知** |
| `sideboardRemaining` | `DeckSideboards` 里 E.T.C. 的 3 张，减去已发现的 |

### A6. 减费栈与手牌上限

| 字段 | 说明 |
|---|---|
| `discountLayers: [DiscountLayer]` | 见 B 节 |
| `handSlotsFree` | `10 - hand.count` |
| `secretsInPlay: Set<CardId>` | 同名奥秘不能重复打 |

## B. 减费栈的精确模型

### B1. 两类费用修改

**（1）层（stack layer）—— 挂在玩家身上，按「张数」消耗**

| 来源 | `amount` | `slots` | `appliesTo` = `consumedBy` | 日志里的附魔 |
|---|---|---|---|---|
| 伺机待发 | 2 | 1 | `.spell` | `EX1_145o` |
| 狐人老千（战吼） | 2 | 1 | `.comboCard` | `DMF_511e` |
| 斯卡布斯·刀油（连击） | 2 | **2** | `.any` | `BAR_552o` |
| 锯齿骨刺（击杀时） | 2 | 1 | `.any` | `REV_939e2` |

规则：
- 打出一张牌时，**所有 `appliesTo` 匹配的层**同时把 `amount` 减到这张牌上（可累加），然后**这些层各消耗 1 槽**，槽为 0 的层移除。
- **不匹配的层不减费也不消耗槽**。（打随从不消耗伺机；打非连击牌不消耗狐人。）
- 刀油「一层 2 槽」：**一层，两张牌**。鲨鱼在场是**两层各 2 槽** → 下两张牌**各 -4**，两层的槽同步递减。**不是 4 槽 -2。**
- 两张伺机 = 两层 → 下一个法术 -4，两层同时消耗（⚠️ 见第三部分）。
- **0 费牌照样消耗 `.any` 层的槽**（币 / 伺机 / 暗影步 / 殒命暗影都算一张）。这是搜索器最容易高估的地方。
- 所有层 `oneTurn = true`，回合结束清空。

**（2）每张牌的附魔 —— 挂在具体那张牌上**

| 来源 | 形式 | 持续 | 附魔 |
|---|---|---|---|
| 暗影步 | `delta -2`（可叠加） | **永久** | （无独立附魔实体，直接改 COST） |
| 黑水弯刀「交易后」 | `delta -1`，落在**随机一张手牌法术** | 永久 | `DED_004e` |
| 暗影施法者 / 幻觉药水的复制品 | **`setCost = 1`** | 永久 | `OG_291e` / `SCH_352e2` |
| 舞动全场弹回的随从 | **`setCost = 1`** | **仅本回合** | `ETC_079e` |

### B2. 结算公式（前推时用）

```
effBase = hasSetCost ? setCostValue                    // 最后一次 set 覆盖之前的一切
                     : baseCost + Σ perCardDelta       // 暗影步 -2 等
cost    = max(0, effBase - Σ matchingLayer.amount)
```

⚠️ **唯一有分歧的组合**：一张牌同时带「暗影步 -2」和「舞动全场 设为 1」。炉石按**附魔挂载顺序**结算（后挂的 set 会盖掉先前的 delta；set 之后再挂的 delta 在 set 之上生效）：
- 先步后舞动 → **1**
- 先舞动后步 → **0**

搜索器必须按动作发生顺序维护 `enchantOrder`，不能只存一个标量。见第三部分待核。

### B3. 「读日志」vs「自己算」的分界（这条决定正确性）

**只读 `entity[.cost]`（日志已算好，绝不重算）：**
- 根状态下**每一张手牌的当前费用**。它已经包含了：本回合已生效的伺机 / 狐人 / 刀油 / 骨刺层、暗影步的永久 -2、复制品的「设为 1」、舞动的「本回合 1」、弯刀交易的 -1。**把这些再算一遍就是双重减费。**
- 根状态下场上随从的攻/血、嘲讽、圣盾、召唤失调等所有 tag。

**前推时必须自己算：**
1. **层的剩余槽数** —— 没有直接 tag。根状态怎么拿到？两条路（见第三部分待核）：
   - (a) 回放本回合的出牌序列（HSTracker 有本回合已出牌记录），从每层被创建的位置往后数张数；
   - (b) 读玩家身上的附魔实体（`BAR_552o` / `EX1_145o` / `DMF_511e` / `REV_939e2`）：**存在 = 层还有槽**；伺机 / 狐人 / 骨刺是 1 槽，存在即 1；**刀油的 2 槽需要 (a) 补齐**。
   建议 (b) 判存在 + (a) 数刀油槽。
2. **搜索过程中新产生的一切**：新 push 的层、新的 set/delta 附魔、复制品的初始费用。
3. **`currentMana` 的逐步扣减**，以及晦鳞的 `min(cur + 2, maxMana)`（**每次触发各自 clamp**）。
4. **`tempMana`** 单独一格，不参与复原。
5. **鲨鱼光环是否还在**（每一步重算，弹回 / 打死 / 沉默都会摘掉）。
6. **手牌 / 场面格子数**。

## C. 动作集合（草图）

> 这是**数据形状**示意，不是实现。

```swift
enum TargetScope { case none, friendlyMinion, enemyMinion, anyMinion, anyCharacter }

enum CardFilter { case any, spell, minion, comboCard }

enum Effect {
    case damage(Int, TargetScope)                    // 阿莱 8 / 骨刺 3 / 致聋 2
    case heal(Int, TargetScope)
    case silence(TargetScope)                        // 致聋：会移除 1/1 附魔！
    case bounce(TargetScope, costDelta: Int)         // 暗影步 -2
    case bounceAll(setCostThisTurn: Int)             // 舞动全场 = 1
    case copyToHand(TargetScope, setCost: Int, setStats: (Int, Int))   // 暗影施法者
    case copyAllToHand(setCost: Int, setStats: (Int, Int))             // 幻觉药水
    case refreshMana(Int, condition: Condition)      // 晦鳞：holdingDragon，clamp 到 maxMana
    case gainTempMana(Int)                           // 币
    case pushDiscount(amount: Int, slots: Int, filter: CardFilter)     // 伺 / 狐 / 刀 / 骨
    case discountRandomCardInHand(amount: Int, filter: CardFilter)     // 弯刀交易
    case draw(CardFilter, Int)                       // 挖掘 / 帷幕 / 行骗 / 矿锄
    case dredge                                      // 垂钓（无连击时本回合无收益）
    case discoverFromDeck(offer: Int, take: Int, followUpOnPlay: Bool) // 异教地图
    case discoverFromSideboard(take: Int)            // E.T.C.
    case equipWeapon(attack: Int, durability: Int, onHeroAttack: Effect?)
    case castSecret(CardId)                          // 闪避：本回合零贡献
    case mirrorLastSpell                             // 殒命暗影（被动，随每次施法改写身份）
    case auraDoubleMinionBattlecryAndCombo           // 鲨鱼之灵
}

enum Action {
    case playCard(handIndex: Int, target: EntityId?)
    case tradeCard(handIndex: Int)                   // 可交易，固定 1 费
    case heroPower
    case attack(attacker: EntityId, defender: EntityId)   // 英雄或随从
    case branchDiscover(choice: Int)                 // 发现 / 抽牌的确定化分支
}
```

## D. 硬约束

| 约束 | 规则 |
|---|---|
| **场上 7 格** | 我方随从 ≤ 7。第 8 个随从**打不出去**（连战吼都不触发）。鱼狐刀暗牛晦龙正好占满 7 格 → 每多打一次阿莱都要先腾格 |
| **手牌 10 张** | 抽牌 / 发现 / 复制 / 弹回超出 10 张 → **溢出即烧**。三种烧法不同：抽牌被烧（牌没了）、发现直接拿不到、**弹回的随从被销毁**（格子腾了但牌没了）。⚠️ 舞动全场一次弹回多个时的销毁顺序待核 |
| **法力水晶** | `currentMana + tempMana >= cost` 才能打。晦鳞「复原」`min(cur + 2, maxMana)` —— **回费被水晶上限卡死**，这是公式表「水晶数」列存在的全部理由 |
| **召唤失调** | 本回合下场的随从 `[.exhausted] == 1` → **不能攻击**；但**战吼照常触发**。上回合就在场的（预启动）可以攻击 → 能参与腾格 |
| **英雄攻击** | 一回合一次（`NUM_ATTACKS_THIS_TURN`），需要武器且攻击力 > 0 |
| **英雄技能** | 一回合一次 |
| **同名奥秘** | 同名奥秘场上只能有一个 → 第二张闪避打不出 |
| **目标合法性** | 法术**无合法目标不能打**（暗影步 / 骨刺 / 致聋术）；随从的**指向性战吼在无目标时仍可裸下**，战吼哑火（本牌组不会发生：暗影施法者自己就是目标） |

## E. 场面交换（平 A）规则

1. **谁能攻击**：我方随从满足 `!summoningSick && attack > 0 && !cantAttack && !frozen && attacksThisTurn < (windfury ? 2 : 1)`。英雄需要武器且未攻击过。
2. **嘲讽**：敌方场上存在 `taunt == 1 && stealth == 0` 的随从时，**所有攻击（含英雄攻击）必须指向嘲讽随从**。沉默 / 打死嘲讽后重新开放。
3. **逐对结算**：一次只结算一个「攻击者 → 防御者」对。攻防互相造成等于对方攻击力的伤害 → 圣盾优先破盾 → 判死（`health <= 0`）→ **立刻从场上移除** → 再选下一对。**不能批量算完再统一移除。**
4. **不撞尸**：每一对之前重算双方场面，已死的实体不再是合法目标 / 攻击者。
5. **腾格的两条路**：① 我方随从撞死在对方随从上（对方攻击力 ≥ 我方生命值，或对方带剧毒）；② 用骨刺 / 暗影步 / 舞动主动清掉自己的随从。**致聋术基本不算腾格牌**（见 §7）。
6. **打脸也是伤害**：非召唤失调的随从可以直接攻击敌方英雄，攻击力直接计入本回合伤害。所以「腾格」和「打脸」是**同一批随从的两个互斥用途**，搜索器要都展开。

## F. 「达到理论上限」的定义（`only_best_damage` 提前停止）

### F1. 每个节点的乐观上界（推荐，用于剪枝）

```
UB(node) = damageDealt
         + Σ attack(可攻击且未攻击的我方随从)          // 全部打脸
         + heroAttackPotential                        // 未攻击时：max(当前武器攻击力, 能装的最大武器攻击力)
         + 8 × S × A
```

- `S`（鲨鱼倍率上界）= `2` 若鲨鱼在场**或**手里/牌库里还能拿到鲨鱼且有格子；否则 `1`。
- `A`（还能触发几次阿莱战吼的上界）=
  ```
  A = handAlexCount
    + boardAlexCount × (potionsReachable + shadowcastersReachable + bouncesReachable)
    + etcDiscoversRemaining × (阿莱是否还在边牌池 ? 1 : 0)
  ```
  其中 `bouncesReachable` = 手里 / 可抽到的暗影步 + 舞动全场张数。这是**极度乐观**的（忽略费用与格子），但**单调不增**，可以安全剪枝。

**提前停止条件**：`damageDealt >= UB(root)`，或 `damageDealt >= effectiveEnemyHealth`（`lethal_threshold` 截断，spike 三、3 说提速 50~100%）。

### F2. 更紧的上界（可选，二阶剪枝）

每次阿莱触发至少要 **1 点法力 + 1 个场上格子**，且一个格子在被腾掉前只能用一次。所以：

```
A ≤ min( 上式,
         floor((currentMana + tempMana + 可回费上界) / 1),
         boardSlotsFree + 本回合可腾格次数 )
```
`可回费上界 = 晦鳞可触发次数 × 2 × S`，且每次 clamp 到 `maxMana`。
`可腾格次数 = 手里骨刺数 + 手里暗影步数 + 舞动全场数 + 能撞死的我方随从数`。

### F3. 结果标注（spike 三、4 的红线）

搜索结束必须回答三选一：`达到理论上限` / `被 CPU 时间预算截断` / `搜索空间穷尽`。角标上要能区分「28/27 可斩杀」和「最大 19/27（被截断）」。

---

# 第三部分：待用户核对

按重要性排序，每条一句话。

## 建模取舍 / 需要你拍板

1. ✅ ~~**致聋术不是腾格牌** —— 沉默会移除「1/1」附魔让复制体变回原身材（阿莱复制体沉默后是 8/8，2 伤打不死），spike 八、里「致聋术对自己 1/1 复制体的用法 = 腾格」要改；这大概率就是 win 项目 issue #2/#3 的根因。**用户 2026-09-11 确认：致聋只能打死狐人老千。**~~
2. **舞动全场是「本回合费用设为 1」不是「-1」** —— spike 三、1 的描述是旧的，改过之后 combo 能算出的伤害会明显变高，请确认。
3. **鲨鱼之灵只翻倍随从的战吼和连击** —— 致聋术 / 垂钓时光 / 行骗这三张**法术**的连击**不翻倍**，请确认与你实战一致。
4. **殒命暗影复制品的费用**：本文按「= 被复制法术的费用」建模，并建议只在复制 0 费法术（步 / 伺 / 币）时折入主线，其余标不确定 —— 你实战里有没有用它抄过非 0 费法术、抄出来是多少费？
5. ✅ ~~**异教地图（×2）的分支爆炸**：三选一 + 打出后再选一，牌库剩余 > 3 张时**任何一条经过它的线都不保证**。**用户定：v1 当「花 2 费抽 1 张未知牌」截断，不展开。**~~
6. ✅ ~~**垂钓时光的探底**：牌库底 3 张 HSTracker 不可知。**用户定：v1 不折入主线，当过牌截断。** 配套要求：这类过牌用户自己找 key 牌，但工具要给「缺件提示」（spike 二、4）。~~
7. **闪避保留在动作集合里但效果为空**：理由是它能腾一个手牌格（药水 / 暗影施法者塞复制时有用）。同意还是直接从动作集合里删掉？
8. **挖掘宝藏的「海盗 → 给币」永不触发**（本牌组 6 张随从无海盗），建议写死忽略 + 加断言。同意？
9. **阿莱治疗友方的分支不展开**（v1 只算伤害）。同意？

## 交互细节（我不确定，需要你或实战验证）

10. **两张伺机待发是否叠加成 -4 并同时消耗**（本文按「是」建模）。
11. ✅ ~~**暗影步的 -2 与舞动全场的「设为 1」谁盖谁** —— 后挂的附魔在上层：先步后舞动 = 1，先舞动后步 = 0。**用户 2026-09-11 实战确认。**~~
12. ✅ ~~**舞动全场弹回时手牌不够**：**用户确认：最右侧随从被烧，回收不了。** 弹回顺序从左到右，手牌满时右边的进不来。搜索器要把「场上位置」当状态的一部分（影响保留哪张阿莱）。~~
13. **两条鲨鱼同时在场，战吼触发几次**（本文按「乘」= 4 次建模，也可能是「加」= 3 次或仍是 2 次）。
14. **黑水弯刀交易后的 -1 落在哪张法术上** —— 本文按「随机一张手牌法术」建模，官方文本没说是发现。
15. **垂钓时光「探底 + 连击抽牌」是否一定抽到探底选中的那张**（本文按「是」，探底先结算）。
16. **暗影施法者被鲨鱼双触发时，两张复制是否都是同一个目标**（本文按「是」，目标在打出时锁定）。
17. **刀油的层剩余槽数在根状态怎么读** —— 本文建议「玩家附魔实体 `BAR_552o` 判存在 + 回放本回合出牌序列数张数」，需要在真实 `Power.log` 上验一次这个附魔实体是否可见。

## 文本版本

18. 全部 24 张的文本来自 **HearthstoneJSON `latest`（`last-modified` 2026-09-03）**，与本地卡库 `downloaded-frameworks/cards/251332/CardDefs.xml`（2026-09-05）同期，**没有 ⚠️ 查不到文本的牌**。
19. 明确核过改动的：**斯卡布斯·刀油**（2025-05-22 由 -3 削到 -2）、**伺机待发**（Core 版 -2）、**鲨鱼之灵**（2022 加了亡灵/野兽种族，效果文本自 2018 未变）、**舞动全场 / 锯齿骨刺 / 狐人老千 / 幻觉药水 / 暗影施法者**（均无平衡性改动）。
20. **牌组代码里三张牌用的是 Core 版**（伺机 `CORE_EX1_145`、狐人 `CORE_DMF_511`、殒命暗影 `CORE_RLK_567`），与 spike 六、给的 id 不同；识别卡牌请按 dbfId 或 `MultiIdCard` 集合，别写死单个字符串。
21. **英雄是马迪亚斯·肖尔（`HERO_03bm`）不是瓦莉拉**，英雄技能相同，对建模无影响。

## G. 公式表推演的反馈（2026-09-11，`HSTrackerTests/Fixtures/RedDragon/formulas.json`）

用本文 B 节规则写了只算法力的推演器，逐 token 对公式表 75 行：**一致 1150 / 1202（95.7%）**；把原表自己算错的彗逆序 16 行、两处水晶列笔误按表的口径复现后 98.8%。不一致的**全部归因到原表或转录**，没有一处要靠改规则才能对上。

### 必须改（T1 前）

- **G1 殒命暗影复制品费用 = 被复制法术的印刷费，且必须支持抄非 0 费法术。** `t2-wuhu-09/10`、`t1-48p-07` 的「殒-舞1」是从法力 4 掉到 1、当时没有任何减费层 → 正好 3 费。**§4 的「只在复制 0 费法术时折入主线」作废**：全表 7 行靠殒抄舞动做第二次全弹回，是 64 / 80 线的主力。待核 #4 定案。
- **G2 减费层跨「阶段」不清空。** 舞动分出的阶段不是回合，刀油的层带着剩余槽进入下一阶段：`t1-32-02` 二阶段起手的鱼 0 费，吃的是一阶段最后一张刀的第 2 槽。全表到处依赖，实现最容易错的一处。
- **G3 首次阿莱是 9 费原版。** 每条 48 线都靠两层刀油 -8 把它压到 1 费，之后才是 1 费复制体。F 节上界里「每次阿莱至少 1 费」的例外。

### 已由公式表验证

- 刀油被鲨鱼双触发 = **两层各 2 槽**（「龙 9-8=1」只有两层同时生效才成立），不是 4 槽 -2。
- 0 费牌照样消耗 `.any` 槽（舞 / 殒 / 步都吃槽）。
- 狐人的层只被连击牌消耗（`t2-huqs-03`「狐4 骨-狐2 刀2」骨刺没吃狐的层）。
- 鲨鱼光环按时点重算：舞动后鱼落地前打的刀只压一层 -2（`t1-48p-03`、`t1-16-02a`）。
- 晦鳞 `min(cur+2, maxMana)` 每次触发各自 clamp：71 / 75 行吻合；**表里红字的「晦4」就是被上限截断的标记**（备注「晦回费爆费了」），可直接做成角标提示文案。

### 待拍板 / 待日志验证

- ✅ ~~**G4 `maxMana` 取永久水晶**，币的临时水晶**不算**进晦鳞回费上限（用户 2026-09-11 定）。`t1-48-02` 按水晶列笔误（应为 5）处理，`t1-48-06b` 的 4 水晶那一半按不成立处理。有 Power.log 时顺手验一次即可，不阻塞。~~
- **G5 待核 #13（两条鲨鱼）只影响 `t2-wudao-01`（无刀做无限）一行**，v1 可先不解。
- **G6 公式表 fixture 不覆盖的东西**：待核 #10 / #12 / #14 / #15 / #16 在表里一次没出现；币、致聋术、垂钓、行骗、挖掘宝藏、闪避、矿锄、地图、英雄技能、平 A 全部没有 token。**T1「公式表全过」≠ 卡表验收通过**，这些要另写用例。

### 原表的错（fixture 里已标 `inference`，`phases` 原文未动）

- ~~**彗逆序 18 行**：把第一张刀油按鲨鱼翻倍的 -4 算，但鲨鱼还没下场；按正确规则每条要多付 4 费~~ **这个判断错了（用户 2026-09-11 看图纠正）**。表 2 那一组的组名是「提前**彗**」，指**上回合已打过幸运彗星**（Lucky Comet，`GDB_873`，dbfId 111292，2 费潜行者法术：「发现一张连击随从。你打出的下一张连击随从的连击效果触发两次」，效果不限本回合）。有它在，首张刀油的连击就是两层 -2 = -4，18 行全部自洽——是**前提条件没进转录**，不是原表算错。「彗逆序」= 幸运彗星 + 逆序（先刀 / 先狐再鱼）启动。表里没提醒的一个坑：刀油是连击不是战吼，刀之前得先垫一张牌。
  **用户不带幸运彗星** → 这 18 行对本牌组不适用，白名单原因改为「依赖幸运彗星，本牌组无」。不建模幸运彗星；一般规则见 spike 六「未建模的牌」。
- `t2-daoqs-01 / 04a / 04b` 的「刀1」应为「刀0」（从 7 费行抄下来漏改）；`t1-48-11` 二阶段「鱼0」应为「鱼1」；`t1-48-02` 水晶列应为 5；`t1-48-06b` 的 4 水晶那一半不能照抄合并单元格的二阶段（差 1 费）；`t1-48p-08` 二阶段「殒舞3」漏了连字符，应为单 token「殒-舞3」。
- 以上 22 行是 T1 重放测试的显式白名单（`HSTrackerTests/RedDragonTests.swift`），白名单之外零失败。
- 术语：「快枪脱水」= 持枪要挟（`WW_411`）发现出的脱水（`WW_325`，快枪 1 费，4 伤，是腾格牌）；「袋底藏沙」（`WW_403`）同样只能靠持枪要挟拿到 → **公式表是给带持枪要挟 + 幸运彗星的另一版牌组写的**，本牌组都没有，`t1-48-06a`「无快枪脱水」对我们恒成立。~~「提前弊」推定为「提前费」~~ → 是「提前彗」（见上）。

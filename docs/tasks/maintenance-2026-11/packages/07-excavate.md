# 包 7　发掘关联卡移植（W3d，按 D4）

> 总 spec：`../spec.md`。顺序第 7，不依赖其他包。排在最后，因为要大量修改 pbxproj，放最后可以少解决冲突。
> 来源：HDT `b9d6e1b`。看补丁用 `gh api repos/HearthSim/Hearthstone-Deck-Tracker/commits/b9d6e1b`。

## 目标

悬浮在发掘牌上时，关联卡网格显示「下一次发掘能拿到的宝藏」；几张「随机获得泰坦」的卡显示泰坦池。

## 现状【核实】

- 本地 `HSTracker/Hearthstone/RelatedCardsSystem/` 下有 1,180 个 `.swift` 文件，**没有**这次补丁新增的 26 个类。
- 本地已有补丁要用的基础设施，不用另外补（只需改一个排除名单，见下文）：
  - `ExcavateTierCounter`（`CounterSystem/Counters/ExcavateTierCounter.swift`，129 行）；
  - `DiscoverPoolCard` 有 `picks()`、`eventCount()`、`isWithReplacement()`、`getCardPool(playerClass:gt:format:)`、`filterPool(_:_:)`（L43-56）；
  - `[Card].filterCardsByPlayerClass(playerClass:ignoreNeutral:)`（`CardUtils.swift:242`）；
  - `GameTag.titan`（`GameTag.swift:440`）。
- 绝大多数卡牌 ID 在本地都有，只是用 HearthDb 的命名，例如 `KoboldMiner_TheAzeriteHawkToken`。

## 要做的事（D4：一个类一个文件）

### 1. 两个基类

- `Cards/ExcavateCard.swift`：抽象基类，实现 `ICardWithRelatedCards`。
  - `shouldShowForOpponent` 返回 false；
  - `getRelatedCards(player:)`：按 `player.id` 取我方或对手的计数器，找到 `ExcavateTierCounter`，返回它的 `getCardsToDisplay()` 对应的卡；找不到就返回空数组。
- `Cards/Pools/TitanMinionPool.swift`：继承 `DiscoverPoolCard`，卡池是所有可收藏的、带 `TITAN` tag 的随从。

注意：Swift 没有「抽象类」的运行时标记，抽象基类要手动排除，否则会被 `ReflectionHelper` 当成具体卡注册。把 `"ExcavateCard"` 和 `"TitanMinionPool"` 加进 `ReflectionHelper.swift:21` 的 `abstractPoolBaseClassNames`。现有的 `CthunAbilityCard`、`LarvaCard` 和各个 Pool 基类都是这样排除的【核实】。

### 2. 24 个具体卡

按 HDT 的目录放到对应职业目录。基类和覆盖项都取自 `b9d6e1b` 的补丁。24 个卡牌 ID 本地都有，名字和 HDT 相同（例如 `KoboldMiner = "WW_001"`），不用补【核实】。

**A. 15 张发掘牌**：继承 `ExcavateCard`，只实现 `getCardId()`，ID 用 `Collectible` 下的同名常量。

| 目录 | 类 |
| :-- | :-- |
| DeathKnight | ReapWhatYouSow、SkeletonCrew |
| Mage | BlastmageMiner、Cryopreservation |
| Neutral | BurrowBuster、KoboldMiner |
| Paladin | FossilizedKaleidosaur、Shroomscavate |
| Rogue | BloodrockCoShovel、DrillyTheKid |
| Shaman | DiggingStraightDown |
| Warlock | MoargDrillfist、Smokestack |
| Warrior | BlastCharge、ReinforcedPlating |

**B. 9 张发掘宝藏 token**：各自继承本地**已有**的卡池基类（只有 Hawk 用新的 `TitanMinionPool`），ID 用 `NonCollectible` 下的常量。

| 目录 | 类 | 基类 | 覆盖项（照抄 HDT） |
| :-- | :-- | :-- | :-- |
| Mage | TheAzeriteHawk | `TitanMinionPool`（新增） | `picks` 1；`isWithReplacement` true；**`filterPool` 直接返回整个卡池**。默认过滤会去掉泰坦，而这个池子全是泰坦，不覆盖就会变成空池 |
| Neutral | AzeriteChunk | `ClassOrNeutralCost3CardPool` | 无 |
| Neutral | AzeriteGem | `ClassOrNeutralCost5CardPool` | 无 |
| Neutral | FoolsAzerite | `ClassOrNeutralCost2CardPool` | 无 |
| Neutral | LivingStone | `Cost2MinionPool` | `picks` 1；`isWithReplacement` true |
| Neutral | WorldPillarFragment | `ClassOrNeutralElementalMinionPool` | 无 |
| Rogue | TheAzeriteScorpion | `SpellPool` | `picks` 1；`eventCount` 4；`isWithReplacement` true |
| Shaman | TheAzeriteMurloc | `RelativeCostPoolCard` | `costOffset` 3 |
| Warrior | TheAzeriteOx | `ClassOrNeutralCost8MinionPool` | `eventCount` 2 |

本地这 8 个已有基类都在 `Cards/Pools/`，`RelativeCostPoolCard` 在 `RelatedCardsSystem/` 下，它的 `costOffset` 是要求子类覆盖的属性【核实】。

### 3. 计数器改动

`ExcavateTierCounter.getCardsToDisplay()`（约 L110）：HDT 把 `filterCardsByClassAndFormat` 换成了只按职业过滤，不再按赛制过滤。照改。

### 4. pbxproj

26 个新文件，每个登记 4 处，共 104 条。pbxproj 只增不改；各职业目录组都已存在，不用新建。

## 涉及文件

- 新增：上面 26 个 `.swift`；守护测试文件（同样要登记）。
- 修改：`ExcavateTierCounter.swift`、`ReflectionHelper.swift`（排除名单）、`project.pbxproj`。

## 验收

- **守护测试**（D4）：
  - 对 26 个类里的 24 个具体卡，逐张断言：`RelatedCardsManager` 用它的 cardId 能查到对应的类；
  - 再断言两个抽象基类**不会**出现在注册结果里；
  - 这样以后少登记一个文件，测试就会失败，而不是运行时静默不显示。
- **单元测试**：
  - `ExcavateCard`：给计数器设定不同的发掘等级，返回的宝藏和 `getCardsToDisplay()` 一致；没有计数器时返回空；
  - `TitanMinionPool`：卡池非空、全是泰坦；`TheAzeriteHawk` 的卡池经过 `filterPool` 后仍不为空。
- 全套测试通过。
- 实机放在第三轮：遇到发掘牌时，悬浮能看到宝藏网格。

## 风险

- 低到中。主要风险是 pbxproj 漏登记，由守护测试兜底。
- 卡牌 ID 对名字时，如果对错了，那张卡会静默不生效。守护测试用的 ID 要和类里写的是同一个常量。

## 记录

一个 `feat:` 提交（或者把计数器改动单独拆成一个）；`docs/PLAN.md` 补一行。

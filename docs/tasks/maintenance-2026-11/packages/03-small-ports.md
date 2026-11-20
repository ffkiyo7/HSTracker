# 包 3　N'zoth、C'Thun、Gloomstone 三处移植（W3a–c）

> 总 spec：`../spec.md`。顺序第 3。**必须在包 4 之前合入**，两者都改 `PowerGameStateParser.swift`。
> 来源是 HDT 公开仓库。它没有 v1.59.x 的 git tag，引用时一律用 SHA，看补丁用 `gh api repos/HearthSim/Hearthstone-Deck-Tracker/commits/<sha>`。

每一项单独提交，用 `feat:` 或 `fix:` 前缀。

## W3a　恩佐斯显示已死亡的亡语随从（HDT `ff1e3ea`）

- **现状**：`HSTracker/Hearthstone/RelatedCardsSystem/Cards/Neutral/NzothDreamsEnd.swift:12` 还是旧的 `ICardWithRelatedCards`，只显示固定的 4 个 token【核实】。
- **要做**：改成继承 `ResurrectionCard`。本地这个基类已经有需要覆盖的方法（`ResurrectionCard.swift` L17、L27、L32）【核实】：
  - `getCardId()`：返回 N'zoth 本身；
  - `filterCard`：类型是随从，并且有亡语；
  - `resurrectsMultipleCards()`：返回 false；
  - `shouldShowForOpponent` 用基类的默认值 false，和 HDT 一致。
- **验收**：单元测试确认关联卡来自我方已死亡的亡语随从，并且去重。

## W3b　克苏恩计数器显示已用过的能力（HDT `ba5eb9e`，+11 行）

- **现状**：`CthunAbilitiesTriggeredCounter.getCardsToDisplay()`（约 L39）没有「已用能力」的分支。4 个能力 token 的 ID 本地都有：`Neutral.swift:1380-1384` 的 `CThunEyeoftheEmpire_WrathOfCthunToken`、`_DomainOfCthunToken`、`_GlareOfCthunToken1`、`_ServantsOfCthunToken`【核实】。
- **要做**：按 HDT 的顺序（Wrath、Domain、Glare、Servants）建一个能力 ID 数组。`counter > 0` 时只显示已用过的能力，否则保持原来的逻辑。
- **验收**：单元测试，用了 0、1、4 个能力时，显示的卡都正确。

## W3c　对手锻造时 Gloomstone Guardian 的选项泄露（HDT `9564545`）

- **现状**：`PowerGameStateParser.swift:481-483` 和 HDT 修复前的逻辑一样，只看 `shouldHideForBlock || beforeMulligan`【核实】。
- **要做**：加一个条件，满足就把实体标记为隐藏：
  - 当前 block 的类型是 `POWER`，并且父 block 的类型是 `DECK_ACTION`；
  - 这个 block 的来源实体不是当前实体本身；
  - 来源实体是锻造过的牌（`info.forged`，L280），在手牌里，并且由对手控制。

  本地 `Block`（`Logging/Block.swift`）有 `parent`、`type`、`sourceEntityId` 这几个字段，可以直接用【核实】。
- **验收**：用几行合成的 Power.log 做单元测试：对手锻造时揭示出的「抉择」选项实体被隐藏；我方锻造时不受影响。

## 整体验收

- 全套测试通过。
- 实机放在第一轮，遇到这几张卡时看一眼，不专门去凑。

## 记录

`docs/PLAN.md` 按提交逐行记。

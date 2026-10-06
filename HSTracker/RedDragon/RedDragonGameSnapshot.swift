//
//  RedDragonGameSnapshot.swift
//  HSTracker
//
//  红龙辅助的「局面读取」第一步拷出来的纯值（拷的过程在 app 侧的 RedDragonSnapshot.swift，要碰 `Entity`）。
//  在本地包 RedDragonCore 里（见 Package.swift）：读取层（RedDragonReader.swift）和展示模型只认这份值。
//

import Foundation

struct RDGameSnapshot: Hashable {

    struct HandCard: Hashable {
        var entityId: Int
        var cardId: String
        /// `entity[.cost]`：日志里已经算好的当前费用（含本回合的减费层）
        var cost: Int
        var zonePosition: Int
        var attack: Int
        var health: Int
        var isCoin: Bool
        /// 挂在这张牌上的附魔 cardId（复制体的 1/1、殒命暗影的镜像、舞动的「本回合 1 费」等）
        var enchantments: [String]
    }

    struct Minion: Hashable {
        var entityId: Int
        var cardId: String
        var zonePosition: Int
        var attack: Int
        /// `[.health] - [.damage]`
        var health: Int
        var maxHealth: Int
        var damage: Int
        var exhausted: Bool
        var attacksThisTurn: Int
        var silenced: Bool
        var frozen: Bool
        var cantAttack: Bool
        var charge: Bool
        var windfury: Bool
        var taunt: Bool
        var divineShield: Bool
        var immune: Bool
        var stealth: Bool
        var dormant: Bool
        var untouchable: Bool
        var enchantments: [String]
        /// `EntityInfo.boardOrder`：每次进 PLAY 时解析器发的递增号（上场先后，舞动按它处理）。
        /// 直接建在场上的实体没有
        var playOrder: Int?
    }

    struct Weapon: Hashable {
        var cardId: String
        var attack: Int
        var durability: Int
    }

    /// 挂在玩家实体上的附魔（伺机待发 / 狐人老千 / 刀油 / 骨刺的减费层、幸运彗星）
    struct PlayerEnchantment: Hashable {
        var entityId: Int
        var cardId: String
        /// `TAG_SCRIPT_DATA_NUM_1`：刀油的层已经用掉了几张（日志实测 0 → 1 → 2 后移除）
        var scriptData1: Int
    }

    /// 对局身份（`Game.startTime`）。结果提交前核对，换局后旧结果不上屏
    var match: Date?

    // 回合
    var turn: Int
    var isPlayerTurn: Bool
    /// 玩家实体的 `NUM_OPTIONS_PLAYED_THIS_TURN`：本回合做过几次操作（出牌、攻击、英雄技能），
    /// 回合内只增不减（日志实测回合开始归 0）。答题模式按它数步，不按场面推
    var optionsPlayedThisTurn: Int

    // 我方资源（玩家实体）
    var resources: Int
    var resourcesUsed: Int
    var overloadLocked: Int
    var tempResources: Int
    var cardsPlayedThisTurn: Int
    /// 玩家实体的 `NUM_FRIENDLY_MINIONS_THAT_ATTACKED_THIS_TURN`：在 ATTACK 块开头就 +1，攻击随从撞死、
    /// 离场之后也不回退（10-04 16:47 那局原始 Power.log 第 69815 行起）。答题用它认「随从攻击已开始」（T2b 第五轮）
    var minionsAttackedThisTurn: Int = 0
    var spellPower: Int
    var playerEnchantments: [PlayerEnchantment]

    // 我方英雄
    var heroHealth: Int
    var heroArmor: Int
    var heroAttacksThisTurn: Int
    /// 英雄身上的 FROZEN：本回合不能攻击
    var heroFrozen: Bool
    var heroPowerExhausted: Bool
    var weapon: Weapon?

    var hand: [HandCard]
    var board: [Minion]
    var secrets: [String]

    // 敌方
    var opponentHeroCardId: String
    var opponentHeroHealth: Int
    var opponentHeroArmor: Int
    var opponentHeroImmune: Bool
    var opponentBoard: [Minion]
    var opponentSecretCount: Int
    /// `BoardState` 算出的对方下回合场攻（随从 + 英雄武器），以及我方是否死于对方场面
    var opponentBoardDamage: Int
    var deadToBoard: Bool

    /// 牌库剩余（`Player.getDeckState()`），cardId → 张数
    var deck: [String: Int]
    /// E.T.C. 乐队还没被发现的牌。nil = 不知道套牌的边牌（读取层按三张都在处理）
    var sideboard: [String]?

    var maxEntityId: Int

    /// 双方场上占格子的实体（随从 + 地标），按 `ZONE_POSITION`。overlay 按它找随从在第几格，
    /// 和 `BoardOverlayView` 的排法一致（地标也占格，`board` / `opponentBoard` 里没有它们）
    var boardSlots: [Int] = []
    var opponentBoardSlots: [Int] = []
    /// 我方英雄的血量上限（回血封顶用，T4）
    var heroMaxHealth: Int = 30
}

extension RDGameSnapshot {

    static let copyStatEnchantments: Set<String> = ["SCH_352e", "OG_291e"]
    /// 「费用变为 (1)」的附魔：幻觉药水复制品、暗影施法者复制品（同一个附魔管身材和费用）、舞动全场
    static let setCostToOneEnchantments: Set<String> = ["SCH_352e2", "OG_291e", "ETC_079e"]
    static let shadowOfDemisePrefix = "RLK_567e"
}

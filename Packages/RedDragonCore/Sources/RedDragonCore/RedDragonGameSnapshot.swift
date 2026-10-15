//
//  RedDragonGameSnapshot.swift
//  HSTracker
//
//  红龙辅助的「局面读取」第一步拷出来的纯值（拷的过程在 app 侧的 RedDragonSnapshot.swift，要碰 `Entity`）。
//  在本地包 RedDragonCore 里（见 Package.swift）：读取层（RedDragonReader.swift）和展示模型只认这份值。
//

import Foundation

public struct RDGameSnapshot: Hashable {

    public struct HandCard: Hashable {
        public var entityId: Int
        public var cardId: String
        /// `entity[.cost]`：日志里已经算好的当前费用（含本回合的减费层）
        public var cost: Int
        public var zonePosition: Int
        public var attack: Int
        public var health: Int
        public var isCoin: Bool
        /// 挂在这张牌上的附魔 cardId（复制体的 1/1、殒命暗影的镜像、舞动的「本回合 1 费」等）
        public var enchantments: [String]

        /// 和编译器合成的逐成员构造一致；写出来是为了 public（app 侧拷快照要用）
        public init(entityId: Int,
                    cardId: String,
                    cost: Int,
                    zonePosition: Int,
                    attack: Int,
                    health: Int,
                    isCoin: Bool,
                    enchantments: [String]) {
            self.entityId = entityId
            self.cardId = cardId
            self.cost = cost
            self.zonePosition = zonePosition
            self.attack = attack
            self.health = health
            self.isCoin = isCoin
            self.enchantments = enchantments
        }
    }

    public struct Minion: Hashable {
        public var entityId: Int
        public var cardId: String
        public var zonePosition: Int
        public var attack: Int
        /// `[.health] - [.damage]`
        public var health: Int
        public var maxHealth: Int
        public var damage: Int
        public var exhausted: Bool
        public var attacksThisTurn: Int
        public var silenced: Bool
        public var frozen: Bool
        public var cantAttack: Bool
        public var charge: Bool
        public var windfury: Bool
        public var taunt: Bool
        public var divineShield: Bool
        public var immune: Bool
        public var stealth: Bool
        public var dormant: Bool
        public var untouchable: Bool
        /// 不能成为法术的目标（`CANT_BE_TARGETED_BY_SPELLS`，扰魔）；剧毒 / 一次性剧毒。只有敌方随从用得上
        public var elusive = false
        public var poisonous = false
        public var venomous = false
        public var enchantments: [String]
        /// `EntityInfo.boardOrder`：每次进 PLAY 时解析器发的递增号（上场先后，舞动按它处理）。
        /// 直接建在场上的实体没有
        public var playOrder: Int?

        /// 和编译器合成的逐成员构造一致；写出来是为了 public（app 侧拷快照要用）
        public init(entityId: Int,
                    cardId: String,
                    zonePosition: Int,
                    attack: Int,
                    health: Int,
                    maxHealth: Int,
                    damage: Int,
                    exhausted: Bool,
                    attacksThisTurn: Int,
                    silenced: Bool,
                    frozen: Bool,
                    cantAttack: Bool,
                    charge: Bool,
                    windfury: Bool,
                    taunt: Bool,
                    divineShield: Bool,
                    immune: Bool,
                    stealth: Bool,
                    dormant: Bool,
                    untouchable: Bool,
                    elusive: Bool = false,
                    poisonous: Bool = false,
                    venomous: Bool = false,
                    enchantments: [String],
                    playOrder: Int? = nil) {
            self.entityId = entityId
            self.cardId = cardId
            self.zonePosition = zonePosition
            self.attack = attack
            self.health = health
            self.maxHealth = maxHealth
            self.damage = damage
            self.exhausted = exhausted
            self.attacksThisTurn = attacksThisTurn
            self.silenced = silenced
            self.frozen = frozen
            self.cantAttack = cantAttack
            self.charge = charge
            self.windfury = windfury
            self.taunt = taunt
            self.divineShield = divineShield
            self.immune = immune
            self.stealth = stealth
            self.dormant = dormant
            self.untouchable = untouchable
            self.elusive = elusive
            self.poisonous = poisonous
            self.venomous = venomous
            self.enchantments = enchantments
            self.playOrder = playOrder
        }
    }

    public struct Weapon: Hashable {
        public var cardId: String
        public var attack: Int
        public var durability: Int

        /// 和编译器合成的逐成员构造一致；写出来是为了 public（app 侧拷快照要用）
        public init(cardId: String,
                    attack: Int,
                    durability: Int) {
            self.cardId = cardId
            self.attack = attack
            self.durability = durability
        }
    }

    /// 挂在玩家实体上的附魔（伺机待发 / 狐人老千 / 刀油 / 骨刺的减费层、幸运彗星）
    public struct PlayerEnchantment: Hashable {
        public var entityId: Int
        public var cardId: String
        /// `TAG_SCRIPT_DATA_NUM_1`：刀油的层已经用掉了几张（日志实测 0 → 1 → 2 后移除）
        public var scriptData1: Int

        /// 和编译器合成的逐成员构造一致；写出来是为了 public（app 侧拷快照要用）
        public init(entityId: Int,
                    cardId: String,
                    scriptData1: Int) {
            self.entityId = entityId
            self.cardId = cardId
            self.scriptData1 = scriptData1
        }
    }

    /// 对局身份（`Game.startTime`）。结果提交前核对，换局后旧结果不上屏
    public var match: Date?

    // 回合
    public var turn: Int
    public var isPlayerTurn: Bool
    /// 玩家实体的 `NUM_OPTIONS_PLAYED_THIS_TURN`：本回合做过几次操作（出牌、攻击、英雄技能），
    /// 回合内只增不减（日志实测回合开始归 0）。答题模式按它数步，不按场面推
    public var optionsPlayedThisTurn: Int

    // 我方资源（玩家实体）
    public var resources: Int
    public var resourcesUsed: Int
    public var overloadLocked: Int
    public var tempResources: Int
    public var cardsPlayedThisTurn: Int
    /// 玩家实体的 `NUM_FRIENDLY_MINIONS_THAT_ATTACKED_THIS_TURN`：在 ATTACK 块开头就 +1，攻击随从撞死、
    /// 离场之后也不回退（10-04 16:47 那局原始 Power.log 第 69815 行起）。答题用它认「随从攻击已开始」（T2b 第五轮）
    public var minionsAttackedThisTurn: Int = 0
    public var spellPower: Int
    public var playerEnchantments: [PlayerEnchantment]

    // 我方英雄
    public var heroHealth: Int
    public var heroArmor: Int
    public var heroAttacksThisTurn: Int
    /// 英雄身上的 FROZEN：本回合不能攻击
    public var heroFrozen: Bool
    public var heroPowerExhausted: Bool
    public var weapon: Weapon?

    public var hand: [HandCard]
    public var board: [Minion]
    public var secrets: [String]

    // 敌方
    public var opponentHeroCardId: String
    public var opponentHeroHealth: Int
    public var opponentHeroArmor: Int
    public var opponentHeroImmune: Bool
    public var opponentBoard: [Minion]
    public var opponentSecretCount: Int
    /// `BoardState` 算出的对方下回合场攻（随从 + 英雄武器），以及我方是否死于对方场面
    public var opponentBoardDamage: Int
    public var deadToBoard: Bool

    /// 牌库剩余（`Player.getDeckState()`），cardId → 张数
    public var deck: [String: Int]
    /// E.T.C. 乐队还没被发现的牌。nil = 不知道套牌的边牌（读取层按三张都在处理）
    public var sideboard: [String]?

    public var maxEntityId: Int

    /// 双方场上占格子的实体（随从 + 地标），按 `ZONE_POSITION`。overlay 按它找随从在第几格，
    /// 和 `BoardOverlayView` 的排法一致（地标也占格，`board` / `opponentBoard` 里没有它们）
    public var boardSlots: [Int] = []
    public var opponentBoardSlots: [Int] = []
    /// 我方英雄的血量上限（回血封顶用，T4）
    public var heroMaxHealth: Int = 30

    /// 和编译器合成的逐成员构造一致；写出来是为了 public（app 侧拷快照要用）
    public init(match: Date? = nil,
                turn: Int,
                isPlayerTurn: Bool,
                optionsPlayedThisTurn: Int,
                resources: Int,
                resourcesUsed: Int,
                overloadLocked: Int,
                tempResources: Int,
                cardsPlayedThisTurn: Int,
                minionsAttackedThisTurn: Int = 0,
                spellPower: Int,
                playerEnchantments: [PlayerEnchantment],
                heroHealth: Int,
                heroArmor: Int,
                heroAttacksThisTurn: Int,
                heroFrozen: Bool,
                heroPowerExhausted: Bool,
                weapon: Weapon? = nil,
                hand: [HandCard],
                board: [Minion],
                secrets: [String],
                opponentHeroCardId: String,
                opponentHeroHealth: Int,
                opponentHeroArmor: Int,
                opponentHeroImmune: Bool,
                opponentBoard: [Minion],
                opponentSecretCount: Int,
                opponentBoardDamage: Int,
                deadToBoard: Bool,
                deck: [String: Int],
                sideboard: [String]? = nil,
                maxEntityId: Int,
                boardSlots: [Int] = [],
                opponentBoardSlots: [Int] = [],
                heroMaxHealth: Int = 30) {
        self.match = match
        self.turn = turn
        self.isPlayerTurn = isPlayerTurn
        self.optionsPlayedThisTurn = optionsPlayedThisTurn
        self.resources = resources
        self.resourcesUsed = resourcesUsed
        self.overloadLocked = overloadLocked
        self.tempResources = tempResources
        self.cardsPlayedThisTurn = cardsPlayedThisTurn
        self.minionsAttackedThisTurn = minionsAttackedThisTurn
        self.spellPower = spellPower
        self.playerEnchantments = playerEnchantments
        self.heroHealth = heroHealth
        self.heroArmor = heroArmor
        self.heroAttacksThisTurn = heroAttacksThisTurn
        self.heroFrozen = heroFrozen
        self.heroPowerExhausted = heroPowerExhausted
        self.weapon = weapon
        self.hand = hand
        self.board = board
        self.secrets = secrets
        self.opponentHeroCardId = opponentHeroCardId
        self.opponentHeroHealth = opponentHeroHealth
        self.opponentHeroArmor = opponentHeroArmor
        self.opponentHeroImmune = opponentHeroImmune
        self.opponentBoard = opponentBoard
        self.opponentSecretCount = opponentSecretCount
        self.opponentBoardDamage = opponentBoardDamage
        self.deadToBoard = deadToBoard
        self.deck = deck
        self.sideboard = sideboard
        self.maxEntityId = maxEntityId
        self.boardSlots = boardSlots
        self.opponentBoardSlots = opponentBoardSlots
        self.heroMaxHealth = heroMaxHealth
    }
}

extension RDGameSnapshot {

    public static let copyStatEnchantments: Set<String> = ["SCH_352e", "OG_291e"]
    /// 「费用变为 (1)」的附魔：幻觉药水复制品、暗影施法者复制品（同一个附魔管身材和费用）、舞动全场
    static let setCostToOneEnchantments: Set<String> = ["SCH_352e2", "OG_291e", "ETC_079e"]
    /// 其中只在本回合有效的：舞动全场。回合结束时附魔自己移除，费用回到印刷费（`RDHandCard.costThisTurnOnly`）
    static let oneTurnCostEnchantments: Set<String> = ["ETC_079e"]
    static let shadowOfDemisePrefix = "RLK_567e"
}

//
//  GameState.swift
//  ModKit
//
//  口子 2：读对局状态。只在 `ModGameEventHandler.handle` 回调里按需读（见 GameEvents.swift），不读不拷。
//
//  宿主的适配层直接让自己的对局、实体对象实现这些协议（不复制），所以：
//  - 只能在解析线程、回调期间读；要留着用就拷成自己的值。
//  - tag 一律按炉石原始数值读（`ModGameTag`），宿主新增的 tag 名字不必等 ModKit 加常量。
//  - 需要宿主自己判断规则的（假区域 FAKE_ZONE、佣兵的控制者、幸运币、CHANGE_ENTITY 之后的新身份）由宿主算好给出，
//    mod 不自己重写一遍。
//

import Foundation

// MARK: - 炉石枚举的原始数值

/// 炉石 GameTag 的原始数值。常量只列常用的，其余用 `ModGameTag(rawValue:)`
public struct ModGameTag: RawRepresentable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let tagScriptDataNum1 = ModGameTag(rawValue: 2)
    public static let turn = ModGameTag(rawValue: 20)
    public static let currentPlayer = ModGameTag(rawValue: 23)
    public static let resourcesUsed = ModGameTag(rawValue: 25)
    public static let resources = ModGameTag(rawValue: 26)
    public static let playerId = ModGameTag(rawValue: 30)
    public static let attached = ModGameTag(rawValue: 40)
    public static let exhausted = ModGameTag(rawValue: 43)
    public static let damage = ModGameTag(rawValue: 44)
    public static let health = ModGameTag(rawValue: 45)
    public static let atk = ModGameTag(rawValue: 47)
    public static let cost = ModGameTag(rawValue: 48)
    public static let zone = ModGameTag(rawValue: 49)
    public static let controller = ModGameTag(rawValue: 50)
    public static let entityId = ModGameTag(rawValue: 53)
    public static let durability = ModGameTag(rawValue: 187)
    public static let silenced = ModGameTag(rawValue: 188)
    public static let windfury = ModGameTag(rawValue: 189)
    public static let taunt = ModGameTag(rawValue: 190)
    public static let stealth = ModGameTag(rawValue: 191)
    public static let divineShield = ModGameTag(rawValue: 194)
    public static let charge = ModGameTag(rawValue: 197)
    public static let cardType = ModGameTag(rawValue: 202)
    public static let secret = ModGameTag(rawValue: 219)
    public static let cantAttack = ModGameTag(rawValue: 227)
    public static let immune = ModGameTag(rawValue: 240)
    public static let frozen = ModGameTag(rawValue: 260)
    public static let zonePosition = ModGameTag(rawValue: 263)
    public static let numCardsPlayedThisTurn = ModGameTag(rawValue: 269)
    public static let currentSpellPower = ModGameTag(rawValue: 291)
    public static let armor = ModGameTag(rawValue: 292)
    public static let tempResources = ModGameTag(rawValue: 295)
    public static let numAttacksThisTurn = ModGameTag(rawValue: 297)
    public static let cantBeTargetedByAbilities = ModGameTag(rawValue: 311)
    public static let numOptionsPlayedThisTurn = ModGameTag(rawValue: 358)
    public static let poisonous = ModGameTag(rawValue: 363)
    public static let overloadLocked = ModGameTag(rawValue: 393)
    public static let numFriendlyMinionsThatAttackedThisTurn = ModGameTag(rawValue: 417)
    public static let untouchable = ModGameTag(rawValue: 448)
    public static let dormant = ModGameTag(rawValue: 1518)
    public static let copiedFromEntityId = ModGameTag(rawValue: 1565)
    public static let venomous = ModGameTag(rawValue: 2853)
}

/// 炉石 Zone 的原始数值
public struct ModZone: RawRepresentable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let invalid = ModZone(rawValue: 0)
    public static let play = ModZone(rawValue: 1)
    public static let deck = ModZone(rawValue: 2)
    public static let hand = ModZone(rawValue: 3)
    public static let graveyard = ModZone(rawValue: 4)
    public static let removedFromGame = ModZone(rawValue: 5)
    public static let setAside = ModZone(rawValue: 6)
    public static let secret = ModZone(rawValue: 7)
}

/// 炉石 CardType 的原始数值
public struct ModCardType: RawRepresentable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let invalid = ModCardType(rawValue: 0)
    public static let game = ModCardType(rawValue: 1)
    public static let player = ModCardType(rawValue: 2)
    public static let hero = ModCardType(rawValue: 3)
    public static let minion = ModCardType(rawValue: 4)
    public static let spell = ModCardType(rawValue: 5)
    public static let enchantment = ModCardType(rawValue: 6)
    public static let weapon = ModCardType(rawValue: 7)
    public static let heroPower = ModCardType(rawValue: 10)
    public static let location = ModCardType(rawValue: 39)
    public static let battlegroundSpell = ModCardType(rawValue: 42)
}

// MARK: - 实体

/// 对局里的一个实体（宿主的实体对象本身，不是拷贝）
public protocol ModEntity: AnyObject {
    var id: Int { get }
    /// 实体创建时的卡牌 id（未知时为空串）
    var cardId: String { get }
    /// 现在是什么牌：CHANGE_ENTITY 之后的新身份，没变过就等于 `cardId`
    var currentCardId: String { get }
    /// 日志里的实体名（游戏实体是 "GameEntity"）
    var name: String { get }
    /// 按原始数值读 tag，没有这个 tag 时为 0
    func tag(_ tag: ModGameTag) -> Int
    /// 所在区域，宿主已按 FAKE_ZONE 修正
    var zone: ModZone { get }
    /// 是否归这个玩家控制（宿主已考虑佣兵的控制者）
    func isControlled(by playerId: Int) -> Bool
    /// 是不是幸运币（含各种「视为幸运币」的法术）
    var isTheCoin: Bool { get }
    /// 宿主记的入场序号（入场顺序徽章用的那个），没记时为 nil
    var boardOrder: Int? { get }
}

extension ModEntity {
    public func has(_ tag: ModGameTag) -> Bool { self.tag(tag) > 0 }
    public var cardType: ModCardType { ModCardType(rawValue: tag(.cardType)) }
    public var zonePosition: Int { tag(.zonePosition) }
    public var attack: Int { tag(.atk) }
    /// 当前血量（HEALTH − DAMAGE）
    public var health: Int { tag(.health) - tag(.damage) }
    public var isMinion: Bool { cardType == .minion }
    public var isHero: Bool { cardType == .hero }
    public var isHeroPower: Bool { cardType == .heroPower }
    public var isWeapon: Bool { cardType == .weapon }
    public var isSpell: Bool { cardType == .spell }
    public var isEnchantment: Bool { cardType == .enchantment }
    public var isLocation: Bool { cardType == .location }
    public var isSecret: Bool { has(.secret) }
    public var isCurrentPlayer: Bool { has(.currentPlayer) }
    public var isInPlay: Bool { zone == .play }
    public var isInHand: Bool { zone == .hand }
    public var isInDeck: Bool { zone == .deck }
    public var isInSecretZone: Bool { zone == .secret }
    public var isInSetAside: Bool { zone == .setAside }
    public var isInGraveyard: Bool { zone == .graveyard }
}

// MARK: - 套牌

/// 当前使用的套牌（值，读的时候拷一份，很小）
public struct ModDeck: Hashable, Sendable {
    /// 宿主里的套牌 id（同一副牌不变；改了牌也不变）
    public var id: String
    public var name: String
    /// 卡牌 id → 张数
    public var cards: [String: Int]
    /// sideboard：主卡（如 E.T.C. 乐队经理）的卡牌 id → 它带的卡牌 id，每张一条
    public var sideboards: [String: [String]]

    public init(id: String, name: String, cards: [String: Int], sideboards: [String: [String]]) {
        self.id = id
        self.name = name
        self.cards = cards
        self.sideboards = sideboards
    }
}

// MARK: - 对局

/// 当前对局（宿主的对局对象本身，只在回调期间读）
public protocol ModGameState: AnyObject {
    /// 对局身份：本局开始的时间。换局就变；不在对局时为 nil
    var matchStartTime: Date? { get }
    /// 在菜单里（不在对局）
    var isInMenu: Bool { get }
    /// 本局已分胜负
    var isGameOver: Bool { get }
    /// 双方换牌都结束了
    var isMulliganDone: Bool { get }
    var isBattlegrounds: Bool { get }
    var isMercenaries: Bool { get }

    /// 我方玩家的 PLAYER_ID（还不知道时为 0）
    var playerId: Int { get }
    /// 对方玩家的 PLAYER_ID（还不知道时为 0）
    var opponentId: Int { get }

    /// 全部实体，顺序不保证
    var entities: [any ModEntity] { get }
    func entity(id: Int) -> (any ModEntity)?

    /// 当前套牌（我方），没选套牌时为 nil
    var currentDeck: ModDeck? { get }
    /// 我方牌库里还剩的牌：卡牌 id → 张数（只含张数 > 0 的），没选套牌时为空
    var remainingDeck: [String: Int] { get }

    /// 对方场上这回合能打出的伤害（宿主的场攻计算）
    var opponentBoardDamage: Int { get }
    /// 按场攻我方下回合会死
    var isPlayerDeadToBoard: Bool { get }
}

//
//  RedDragonState.swift
//  HSTracker
//
//  一个回合的局面。全部值语义 —— 引擎不改传入的 state，只返回新的。
//  字段清单照 docs/research/red-dragon-card-model.md 第二部分 A 节。
//

import Foundation

/// 挂在某一张牌 / 某一个随从实体上的费用附魔，按挂载顺序求值（先步后舞 = 1，先舞后步 = 0）
enum RDEnchant: Equatable {
    case set(Int)
    case delta(Int)
}

struct RDDiscountLayer: Equatable {
    var amount: Int
    var slots: Int
    var filter: RDCardFilter

    static func == (lhs: RDDiscountLayer, rhs: RDDiscountLayer) -> Bool {
        return lhs.amount == rhs.amount && lhs.slots == rhs.slots
            && filterCode(lhs.filter) == filterCode(rhs.filter)
    }

    static func filterCode(_ f: RDCardFilter) -> Int {
        switch f {
        case .any: return 0
        case .spell: return 1
        case .minion: return 2
        case .comboCard: return 3
        }
    }
}

struct RDHandCard {
    var entityId: Int
    var card: RDCard
    /// 身份未定的牌：E.T.C. 发现（边牌三张之一）、未指定目标的暗影施法者复制。
    /// 精确搜索里恒为空（发现 / 复制都枚举成确定分支），只有公式表重放会用到。
    var pool: [RDCard]
    var enchants: [RDEnchant]
    /// 1/1 复制体的身材覆盖
    var statsOverride: RDStats?
    /// 殒命暗影：每次施放法术都会把它改写成那张法术
    var isShadowOfDemise: Bool
    /// 公式表占位「杂」/「腾格」的费用
    var printedCostOverride: Int?
    /// pool 来自边牌池：身份确定时要把那张从 sideboard 里扣掉
    var poolFromSideboard: Bool
    /// 卡表没建模的牌被塞成 `.junkPlaceholder` 时，这里留原 cardId 供 T2 在 overlay 上显示是哪张。
    /// **不进 `canonicalHash`**：对搜索来说所有杂牌等价（都打不出去、都只占一个手牌格），
    /// 按 cardId 区分只会让去重失效、状态数翻倍。
    var unmodeledCardId: String?

    init(entityId: Int, card: RDCard, pool: [RDCard] = [], enchants: [RDEnchant] = [],
         statsOverride: RDStats? = nil, isShadowOfDemise: Bool = false,
         printedCostOverride: Int? = nil, poolFromSideboard: Bool = false,
         unmodeledCardId: String? = nil) {
        self.entityId = entityId
        self.card = card
        self.pool = pool
        self.enchants = enchants
        self.statsOverride = statsOverride
        self.isShadowOfDemise = isShadowOfDemise
        self.printedCostOverride = printedCostOverride
        self.poolFromSideboard = poolFromSideboard
        self.unmodeledCardId = unmodeledCardId
    }

    /// 卡表没建模的牌 → 不可打的杂牌，只占一个手牌格（spike 六「未建模的牌」）
    static func unmodeled(entityId: Int, cardId: String?) -> RDHandCard {
        return RDHandCard(entityId: entityId, card: .junkPlaceholder,
                          unmodeledCardId: cardId)
    }

    var identities: [RDCard] { return pool.isEmpty ? [card] : pool }

    // 热路径用这三个，别用 identities —— 它每次访问都要新建一个数组
    var identityCount: Int { return pool.isEmpty ? 1 : pool.count }
    func identity(at index: Int) -> RDCard { return pool.isEmpty ? card : pool[index] }
    func hasIdentity(_ c: RDCard) -> Bool { return pool.isEmpty ? card == c : pool.contains(c) }
}

struct RDStats: Equatable {
    var attack: Int
    var health: Int
}

struct RDBoardMinion {
    var entityId: Int
    var card: RDCard
    var attack: Int
    var health: Int
    var maxHealth: Int
    /// 身材是被「1/1」附魔设出来的 —— 沉默会让它变回原身材
    var statsSetTo1x1: Bool
    var silenced: Bool
    var summoningSick: Bool
    var attacksThisTurn: Int
    /// 费用附魔跟着实体走（board → hand → board），这是「先舞后步 = 0」的前提
    var enchants: [RDEnchant]

    var isAlive: Bool { return health > 0 }
}

struct RDEnemyMinion {
    var entityId: Int
    var attack: Int
    var health: Int
    var taunt: Bool
    var divineShield: Bool
    var immune: Bool
    var stealth: Bool
}

struct RDOpponent {
    var health: Int
    var armor: Int
    var immune: Bool
    var board: [RDEnemyMinion]
    var secretCount: Int

    var effectiveHealth: Int { return health + armor }

    init(health: Int, armor: Int = 0, immune: Bool = false,
         board: [RDEnemyMinion] = [], secretCount: Int = 0) {
        self.health = health
        self.armor = armor
        self.immune = immune
        self.board = board
        self.secretCount = secretCount
    }
}

struct RDWeapon {
    var attack: Int
    var durability: Int
    var drawOnHeroAttack: Bool
}

/// 牌库剩余，按卡计数（不知道顺序）
struct RDDeck {
    private(set) var counts: [Int]
    private(set) var total: Int

    init() {
        counts = [Int](repeating: 0, count: RDCard.allCases.count)
        total = 0
    }

    init(_ pairs: [(RDCard, Int)]) {
        counts = [Int](repeating: 0, count: RDCard.allCases.count)
        total = 0
        for (c, n) in pairs {
            counts[c.rawValue] += n
            total += n
        }
    }

    func count(_ card: RDCard) -> Int { return counts[card.rawValue] }

    mutating func remove(_ card: RDCard) {
        if counts[card.rawValue] > 0 {
            counts[card.rawValue] -= 1
            total -= 1
        }
    }

    mutating func add(_ card: RDCard) {
        counts[card.rawValue] += 1
        total += 1
    }

    /// 按 RDCard 顺序列出剩余的卡（确定性）
    func remaining(filter: RDCardFilter) -> [RDCard] {
        var out: [RDCard] = []
        guard total > 0 else { return out }
        for raw in 0..<counts.count where counts[raw] > 0 {
            guard let c = RDCard(rawValue: raw) else { continue }
            if RDCards.matches(RDCards.def(c), filter) { out.append(c) }
        }
        return out
    }

    func count(filter: RDCardFilter) -> Int {
        var n = 0
        for raw in 0..<counts.count where counts[raw] > 0 {
            guard let c = RDCard(rawValue: raw) else { continue }
            if RDCards.matches(RDCards.def(c), filter) { n += counts[raw] }
        }
        return n
    }
}

struct RDState {
    var maxMana: Int
    var mana: Int
    var tempMana: Int
    var cardsPlayedThisTurn: Int
    var spellDamage: Int
    var heroAttackedThisTurn: Bool
    var heroPowerUsed: Bool
    var weapon: RDWeapon?

    var hand: [RDHandCard]
    var board: [RDBoardMinion]
    var opponent: RDOpponent
    var deck: RDDeck
    var sideboard: [RDCard]
    var layers: [RDDiscountLayer]
    var secretsInPlay: [RDCard]

    var damageDealt: Int
    var nextEntityId: Int
    /// 打过几次「花费用 + 抽 1 张未知」的截断牌（异教地图 / 垂钓时光）
    var truncatedDraws: Int

    /// 场上 7 格
    var boardLimit: Int
    /// 手牌 10 张。公式表的 `seed_for` 会给出 12~18 张起手，那批用例把上限放开（见 RedDragonTests）
    var handLimit: Int

    var availableMana: Int { return mana + tempMana }
    var boardSlotsFree: Int { return boardLimit - board.count }
    var handSlotsFree: Int { return handLimit - hand.count }
    var sharkAuraActive: Bool {
        for m in board where RDCards.def(m.card).providesSharkAura && !m.silenced {
            return true
        }
        return false
    }
    var comboActive: Bool { return cardsPlayedThisTurn > 0 }

    init(maxMana: Int, mana: Int, opponent: RDOpponent) {
        self.maxMana = maxMana
        self.mana = mana
        self.tempMana = 0
        self.cardsPlayedThisTurn = 0
        self.spellDamage = 0
        self.heroAttackedThisTurn = false
        self.heroPowerUsed = false
        self.weapon = nil
        self.hand = []
        self.board = []
        self.opponent = opponent
        self.deck = RDDeck()
        self.sideboard = RDCards.sideboardCards
        self.layers = []
        self.secretsInPlay = []
        self.damageDealt = 0
        self.nextEntityId = 1
        self.truncatedDraws = 0
        self.boardLimit = 7
        self.handLimit = 10
    }

    mutating func takeEntityId() -> Int {
        let id = nextEntityId
        nextEntityId += 1
        return id
    }

    func effectiveBaseCost(_ card: RDHandCard, as identity: RDCard) -> Int {
        var value = card.printedCostOverride ?? RDCards.def(identity).printedCost
        for e in card.enchants {
            switch e {
            case .set(let v): value = v
            case .delta(let v): value += v
            }
        }
        return max(0, value)
    }

    func discount(for card: RDHandCard, as identity: RDCard) -> Int {
        let def = RDCards.def(identity)
        var total = 0
        for layer in layers where RDCards.matches(def, layer.filter) {
            total += layer.amount
        }
        return total
    }

    func cost(of card: RDHandCard, as identity: RDCard) -> Int {
        return max(0, effectiveBaseCost(card, as: identity) - discount(for: card, as: identity))
    }

    var holdingDragon: Bool {
        for c in hand {
            for i in 0..<c.identityCount where RDCards.def(c.identity(at: i)).isDragon {
                return true
            }
        }
        return false
    }

    func handIndex(ofEntity id: Int) -> Int? {
        return hand.firstIndex { $0.entityId == id }
    }

    func boardIndex(ofEntity id: Int) -> Int? {
        return board.firstIndex { $0.entityId == id }
    }

    /// 去重用的确定性指纹。跨进程稳定（不用 Swift 的随机种子 Hasher）
    func canonicalHash() -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        func feed(_ v: Int) {
            h = (h ^ UInt64(bitPattern: Int64(v &+ 0x9e37_79b9))) &* 0x1000_0000_01b3
        }
        feed(mana); feed(tempMana); feed(maxMana)
        feed(cardsPlayedThisTurn); feed(damageDealt); feed(truncatedDraws)
        feed(heroAttackedThisTurn ? 1 : 0); feed(heroPowerUsed ? 1 : 0)
        feed(opponent.health); feed(opponent.armor)
        feed(weapon?.attack ?? -1); feed(weapon?.durability ?? -1)
        // 手牌与顺序无关：把每张牌的 key 哈希交换律地并起来，省掉排序与分配。
        // key 必须带上 isShadowOfDemise 和「是否 1/1 复制体」：殒变成的「步」和真「步」同费但
        // 未来不同（殒打出后就没了，真步留着还能让殒镜像下一张法术），1/1 复制体与原版同费但
        // 攻击力 / 致聋判定不同 —— 合并它们会让搜索只展开先遇到的那张。
        var handMix: UInt64 = 0
        var handSum: UInt64 = 0
        for c in hand {
            let identity = c.identity(at: 0)
            var key = UInt64(identity.rawValue &* 64 &+ min(63, effectiveBaseCost(c, as: identity)))
            key = key &* 2 &+ (c.statsOverride == nil ? 0 : 1)
            key = key &* 2 &+ (c.isShadowOfDemise ? 1 : 0)
            let mixed = (key &+ 0x9e37_79b9_7f4a_7c15) &* 0xff51_afd7_ed55_8ccd
            handMix ^= mixed
            handSum = handSum &+ mixed
        }
        h = (h ^ handMix) &* 0x1000_0000_01b3
        h = (h ^ handSum) &* 0x1000_0000_01b3
        feed(hand.count)
        // 场面有顺序（舞动弹回顺序 / 最右侧被烧）
        for m in board {
            feed(m.card.rawValue)
            feed(m.attack); feed(m.health)
            feed(m.summoningSick ? 1 : 0); feed(m.silenced ? 1 : 0)
            feed(m.attacksThisTurn)
            for e in m.enchants {
                switch e {
                case .set(let v): feed(1000 + v)
                case .delta(let v): feed(2000 + v)
                }
            }
            feed(-3)
        }
        feed(-4)
        for l in layers {
            feed(l.amount); feed(l.slots); feed(RDDiscountLayer.filterCode(l.filter))
        }
        feed(-5)
        for c in sideboard { feed(c.rawValue) }
        feed(-6)
        if deck.total > 0 {
            for raw in 0..<deck.counts.count where deck.counts[raw] > 0 {
                feed(raw &* 64 &+ deck.counts[raw])
            }
        }
        feed(-7)
        for s in secretsInPlay { feed(s.rawValue) }
        for m in opponent.board {
            feed(m.attack); feed(m.health); feed(m.taunt ? 1 : 0); feed(m.divineShield ? 1 : 0)
        }
        return h
    }
}

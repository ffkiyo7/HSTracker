//
//  RedDragonEngine.swift
//  HSTracker
//
//  规则引擎：纯函数 `apply`，同一 (state, action) 两次调用结果逐字节相同。
//  搜索与「路径重放校验」共用这一份实现，所以重放能真的挡住算得出、打不出的线。
//

import Foundation

enum RDTarget: Equatable {
    case none
    case friendlyMinion(Int)
    case enemyMinion(Int)
    case enemyHero
    /// 公式表重放专用：表里没写目标，复制品的身份先留成场上随从的并集
    case unspecifiedFriendly
    /// 英雄攻击的攻击者
    case friendlyHero
}

/// 发现 / 抽牌的确定化选择，按效果出现顺序消费
enum RDChoice: Equatable {
    case pick(RDCard)
}

enum RDAction: Equatable {
    /// `position`：随从落位（插在场上第几格之前，0 = 最左）。nil = 最右。
    /// 真实炉石由玩家决定落位；舞动按场上从左到右收回、手牌放不下的（最右侧）被烧，
    /// 复制全场也按从左到右进手，所以落位会改变结果。法术 / 武器恒为 nil。
    case play(entityId: Int, identity: RDCard, target: RDTarget, choices: [RDChoice],
              position: Int? = nil)
    case heroPower
    case attack(attacker: RDTarget, defender: RDTarget)
}

enum RDIllegal: Error, Equatable {
    case noSuchCard
    case wrongIdentity
    case notEnoughMana
    case boardFull
    case noTarget
    case illegalTarget
    case duplicateSecret
    case heroPowerUsed
    case cannotAttack
    case tauntInTheWay
    case noWeapon
    case missingChoice
    case truncatedDrawNotAllowed
    /// 卡表没建模的牌（占位「杂」）：只占手牌格，打不出去
    case unplayableJunk
    /// 落位越界，或给非随从指定了落位
    case illegalPosition
}

struct RDOptions {
    /// 公式表重放：发现结果留成 pool、暗影施法者允许不指定目标
    var deferredChoices = false
    /// 异教地图 / 垂钓时光在搜索里不展开（v1 已决）
    var allowTruncatedDraws = false
    /// 每张牌的发现 / 抽牌组合上限，防止分支爆炸
    var maxChoiceCombinations = 12
    /// 占位牌（「杂」/「腾格」）能不能打。
    /// 搜索侧恒 false —— 用户定的一般规则「牌组里出现卡表没建模的牌 → 当作不可打的杂牌，
    /// 只占手牌格」（spike 六「未建模的牌」）就落在这里：不建模就搜不出依赖它的线，最多算保守。
    /// 公式表重放侧为 true，因为表里的「杂」/「腾格」是真牌，只是表没写是哪张。
    var allowPlaceholderPlays = false
    /// `legalActions` 是否把随从的不等价落位逐个列出来（见 `placements`）。严格重放 / 外部调用用 true；
    /// 束搜索内部用 false —— 随从先一律放最右，等到真正爆手的全场弹回 / 复制时再决定场面顺序，
    /// 再把顺序翻译回落位（`RedDragonSearch` 的「落位」一节）。结果等价、分支少得多
    var expandPlacements = true

    static let search = RDOptions()
    static let replay = RDOptions(deferredChoices: true, allowTruncatedDraws: true,
                                  maxChoiceCombinations: 12, allowPlaceholderPlays: true)
}

enum RDEngine {

    // MARK: - 打牌

    static func apply(_ action: RDAction, to state: RDState,
                      options: RDOptions = .search) throws -> RDState {
        switch action {
        case .play(let entityId, let identity, let target, let choices, let position):
            return try playCard(entityId: entityId, identity: identity, target: target,
                                choices: choices, position: position, state: state,
                                options: options)
        case .heroPower:
            return try useHeroPower(state)
        case .attack(let attacker, let defender):
            return try resolveAttack(attacker: attacker, defender: defender, state: state)
        }
    }

    private static func playCard(entityId: Int, identity: RDCard, target: RDTarget,
                                 choices: [RDChoice], position: Int?, state: RDState,
                                 options: RDOptions) throws -> RDState {
        guard let handIndex = state.handIndex(ofEntity: entityId) else { throw RDIllegal.noSuchCard }
        let handCard = state.hand[handIndex]
        guard handCard.hasIdentity(identity) else { throw RDIllegal.wrongIdentity }
        let def = RDCards.def(identity)
        if let p = position {
            guard def.type == .minion, p >= 0, p <= state.board.count else {
                throw RDIllegal.illegalPosition
            }
        }

        if !options.allowTruncatedDraws && hasTruncatedDraw(def) {
            throw RDIllegal.truncatedDrawNotAllowed
        }
        if def.isPlaceholder && !options.allowPlaceholderPlays {
            throw RDIllegal.unplayableJunk
        }

        let cost = state.cost(of: handCard, as: identity)
        guard state.availableMana >= cost else { throw RDIllegal.notEnoughMana }
        if def.type == .minion { guard state.boardSlotsFree > 0 else { throw RDIllegal.boardFull } }
        if isSecret(def) {
            guard !state.secretsInPlay.contains(identity) else { throw RDIllegal.duplicateSecret }
        }
        try validate(target: target, def: def, state: state, options: options)

        var s = state
        s.hand.remove(at: handIndex)
        if handCard.poolFromSideboard, let i = s.sideboard.firstIndex(of: identity) {
            s.sideboard.remove(at: i)
        }

        // 临时水晶先花（币给的那格不参与晦鳞复原）
        let fromTemp = min(s.tempMana, cost)
        s.tempMana -= fromTemp
        s.mana -= (cost - fromTemp)

        let comboActive = s.comboActive
        // 幸运彗星：下一张连击随从一打出就吃掉这次。
        // 待核假设（T2b 用日志验）：连击没开时也算用掉
        let cometDoubles = consumesLuckyComet(def) && s.luckyCometCharges > 0
        if cometDoubles { s.luckyCometCharges -= 1 }
        s.cardsPlayedThisTurn += 1
        consumeLayers(&s, def: def)

        var summonedId: Int?
        if def.type == .minion {
            let stats = handCard.statsOverride ?? RDStats(attack: def.attack, health: def.health)
            let id = s.takeEntityId()
            let minion = RDBoardMinion(entityId: id, card: identity,
                                       attack: stats.attack, health: stats.health,
                                       maxHealth: stats.health,
                                       statsSetTo1x1: handCard.statsOverride != nil,
                                       silenced: false, summoningSick: true,
                                       attacksThisTurn: 0, enchants: handCard.enchants)
            s.board.insert(minion, at: position ?? s.board.count)
            summonedId = id
        }

        let usesCombo = comboActive && !def.comboEffects.isEmpty
        let effects = usesCombo ? def.comboEffects : def.effects
        let triggers = triggerCount(def, sharkAura: s.sharkAuraActive,
                                    cometDoubles: cometDoubles && usesCombo)

        var ctx = RDEffectContext(target: target, choices: choices, source: summonedId,
                                  options: options)
        for _ in 0..<triggers {
            ctx.choiceIndex = ctx.choiceIndexAtTriggerStart
            for effect in effects {
                try resolve(effect, state: &s, ctx: &ctx)
            }
            ctx.choiceIndexAtTriggerStart = ctx.choiceIndex
        }

        if def.type == .spell {
            mirrorShadowOfDemise(&s, into: identity)
        }
        removeDeadMinions(&s)
        return s
    }

    /// 鲨鱼之灵只翻倍「随从的」战吼 / 连击；幸运彗星只翻倍连击随从的连击。
    /// 待核假设（T2b 用日志验）：两者同时生效时不叠加，按 2 次算。
    /// 公式表里彗星那一刀打出时鲨鱼都还没下场，碰不到这个分歧。
    private static func triggerCount(_ def: RDCardDef, sharkAura: Bool, cometDoubles: Bool) -> Int {
        if def.doubledByShark && sharkAura { return 2 }
        return cometDoubles ? 2 : 1
    }

    private static func consumesLuckyComet(_ def: RDCardDef) -> Bool {
        return def.type == .minion && def.isCombo
    }

    private static func isSecret(_ def: RDCardDef) -> Bool {
        for e in def.effects { if case .castSecret = e { return true } }
        return false
    }

    private static func hasTruncatedDraw(_ def: RDCardDef) -> Bool {
        for e in def.effects { if case .truncatedDraw = e { return true } }
        for e in def.comboEffects { if case .truncatedDraw = e { return true } }
        return false
    }

    private static func consumeLayers(_ s: inout RDState, def: RDCardDef) {
        guard !s.layers.isEmpty else { return }
        var needsCompaction = false
        for i in s.layers.indices where RDCards.matches(def, s.layers[i].filter) {
            s.layers[i].slots -= 1
            if s.layers[i].slots <= 0 { needsCompaction = true }
        }
        if needsCompaction { s.layers.removeAll { $0.slots <= 0 } }
    }

    private static func mirrorShadowOfDemise(_ s: inout RDState, into spell: RDCard) {
        for i in s.hand.indices where s.hand[i].isShadowOfDemise {
            s.hand[i].card = spell
            s.hand[i].pool = []
            s.hand[i].enchants = []
            s.hand[i].statsOverride = nil
            s.hand[i].printedCostOverride = nil
            s.hand[i].poolFromSideboard = false
        }
    }

    private static func validate(target: RDTarget, def: RDCardDef, state: RDState,
                                 options: RDOptions) throws {
        switch def.targetScope {
        case .none:
            guard target == .none else { throw RDIllegal.illegalTarget }
        case .friendlyMinion, .enemyMinion, .anyMinion, .anyCharacter, .enemyCharacter:
            if target == .none {
                // 随从的指向性战吼在无目标时仍可裸下，法术不行
                guard !def.needsTargetToPlay else { throw RDIllegal.noTarget }
                guard !hasLegalTarget(def, state: state) else { throw RDIllegal.noTarget }
                return
            }
            if target == .unspecifiedFriendly {
                guard options.deferredChoices else { throw RDIllegal.illegalTarget }
                switch def.targetScope {
                case .friendlyMinion, .anyMinion, .anyCharacter: break
                default: throw RDIllegal.illegalTarget
                }
                guard !state.board.isEmpty else { throw RDIllegal.noTarget }
                return
            }
            guard isLegalTarget(target, scope: def.targetScope, state: state) else {
                throw RDIllegal.illegalTarget
            }
            if def.targetMustBeUndamaged && !isUndamaged(target, state: state) {
                throw RDIllegal.illegalTarget
            }
        }
    }

    /// 背刺类「未受伤的随从」：我方看当前生命 = 生命上限，敌方看本回合有没有受过伤
    private static func isUndamaged(_ target: RDTarget, state: RDState) -> Bool {
        switch target {
        case .friendlyMinion(let id):
            guard let m = state.board.first(where: { $0.entityId == id }) else { return false }
            return m.health >= m.maxHealth
        case .enemyMinion(let id):
            guard let m = state.opponent.board.first(where: { $0.entityId == id }) else { return false }
            return !m.damaged
        default:
            return false
        }
    }

    private static func isLegalTarget(_ target: RDTarget, scope: RDTargetScope,
                                      state: RDState) -> Bool {
        switch target {
        case .friendlyMinion(let id):
            guard scope == .friendlyMinion || scope == .anyMinion || scope == .anyCharacter else {
                return false
            }
            return state.boardIndex(ofEntity: id) != nil
        case .enemyMinion(let id):
            guard scope == .enemyMinion || scope == .anyMinion || scope == .anyCharacter
                    || scope == .enemyCharacter else {
                return false
            }
            return state.opponent.board.contains { $0.entityId == id }
        case .enemyHero:
            return scope == .anyCharacter || scope == .enemyCharacter
        default:
            return false
        }
    }

    static func hasLegalTarget(_ def: RDCardDef, state: RDState) -> Bool {
        if def.targetMustBeUndamaged { return !legalTargets(for: def, state: state).isEmpty }
        switch def.targetScope {
        case .none: return false
        case .friendlyMinion: return !state.board.isEmpty
        case .enemyMinion: return !state.opponent.board.isEmpty
        case .anyMinion: return !state.board.isEmpty || !state.opponent.board.isEmpty
        case .anyCharacter, .enemyCharacter: return true
        }
    }

    /// 等价目标只留一个代表：同一张牌、同身材、同附魔的两个随从，指谁结果都一样。
    /// 这是真等价，不是启发式剪枝 —— 但它把 7 格场面的目标展开从 7 条压到 3~4 条。
    static func legalTargets(for def: RDCardDef, state: RDState) -> [RDTarget] {
        var out: [RDTarget] = []
        switch def.targetScope {
        case .none:
            return []
        case .friendlyMinion:
            appendFriendlyTargets(state, into: &out)
        case .enemyMinion:
            appendEnemyTargets(state, into: &out)
        case .anyMinion:
            appendFriendlyTargets(state, into: &out)
            appendEnemyTargets(state, into: &out)
        case .anyCharacter:
            appendFriendlyTargets(state, into: &out)
            appendEnemyTargets(state, into: &out)
            out.append(.enemyHero)
        case .enemyCharacter:
            appendEnemyTargets(state, into: &out)
            out.append(.enemyHero)
        }
        if def.targetMustBeUndamaged {
            out = out.filter { isUndamaged($0, state: state) }
        }
        return out
    }

    /// 友方目标。手牌 / 边牌 / 牌库里有「按场序处理全场」的牌（`boardOrderMatters`）时**按实体全部列出**：
    /// 两个一模一样的随从站位不同，指左边还是右边，会改变之后舞动 / 药水收到哪几张（例：骨刺杀右边那只
    /// 1/1 阿莱，药水才复制得到左边那只），所以不等价。等价的那几个由搜索在执行后按「局面 + 场序偏序」去重
    /// （`RedDragonSearch.collapseEquivalentTargets`）。没有这类牌时场序不影响任何结果，
    /// 进哈希的字段全相同（`minionKey`）的随从才合并
    private static func appendFriendlyTargets(_ state: RDState, into out: inout [RDTarget]) {
        if boardOrderMatters(state) {
            for m in state.board { out.append(.friendlyMinion(m.entityId)) }
            return
        }
        var seen: [Int] = []
        for m in state.board {
            let key = minionKey(m)
            if seen.contains(key) { continue }
            seen.append(key)
            out.append(.friendlyMinion(m.entityId))
        }
    }

    /// 敌方目标：本牌组没有按敌方场序起作用的效果，所以字段全相同的敌方随从指谁都一样，合并成一个
    private static func appendEnemyTargets(_ state: RDState, into out: inout [RDTarget]) {
        var seen: [Int] = []
        for m in state.opponent.board {
            var key = (min(63, m.health) &* 64 &+ min(31, m.attack) &* 4
                &+ (m.taunt ? 2 : 0) &+ (m.divineShield ? 1 : 0)) &* 2 &+ (m.damaged ? 1 : 0)
            key = key &* 4 &+ (m.immune ? 2 : 0) &+ (m.stealth ? 1 : 0)
            if seen.contains(key) { continue }
            seen.append(key)
            out.append(.enemyMinion(m.entityId))
        }
    }

    // MARK: - 效果结算

    private struct RDEffectContext {
        var target: RDTarget
        var choices: [RDChoice]
        var source: Int?
        var options: RDOptions
        var choiceIndex = 0
        var choiceIndexAtTriggerStart = 0
        var lastTargetDied = false
    }

    private static func nextChoice(_ ctx: inout RDEffectContext) -> RDCard? {
        guard ctx.choiceIndex < ctx.choices.count else { return nil }
        defer { ctx.choiceIndex += 1 }
        if case .pick(let c) = ctx.choices[ctx.choiceIndex] { return c }
        return nil
    }

    private static func resolve(_ effect: RDEffect, state s: inout RDState,
                                ctx: inout RDEffectContext) throws {
        switch effect {
        case .damageTarget(let amount, let usesSpellDamage):
            let n = amount + (usesSpellDamage ? s.spellDamage : 0)
            ctx.lastTargetDied = dealDamage(n, to: ctx.target, state: &s)

        case .silenceTarget:
            if case .friendlyMinion(let id) = ctx.target, let i = s.boardIndex(ofEntity: id) {
                silence(&s.board[i])
            } else if case .enemyMinion(let id) = ctx.target,
                      let i = s.opponent.board.firstIndex(where: { $0.entityId == id }) {
                s.opponent.board[i].taunt = false
                s.opponent.board[i].divineShield = false
            }

        case .bounceTarget(let costDelta):
            guard case .friendlyMinion(let id) = ctx.target,
                  let i = s.boardIndex(ofEntity: id) else { return }
            let minion = s.board.remove(at: i)
            returnToHand(minion, extraEnchant: .delta(costDelta), state: &s)

        case .bounceAllFriendly(let setCost):
            let minions = s.board
            s.board = []
            for minion in minions {
                returnToHand(minion, extraEnchant: .set(setCost), state: &s)
            }

        case .copyTargetToHand(let setCost, let attack, let health):
            guard s.handSlotsFree > 0 else { return }
            let stats = RDStats(attack: attack, health: health)
            if case .friendlyMinion(let id) = ctx.target, let i = s.boardIndex(ofEntity: id) {
                let card = s.board[i].card
                let eid = s.takeEntityId()
                appendThisTurn(&s, RDHandCard(entityId: eid, card: card, enchants: [.set(setCost)],
                                         statsOverride: stats))
            } else if ctx.target == .unspecifiedFriendly {
                // 指向性战吼是**下场前**选目标，施法者自己不在候选里（搜索侧本来就是这个口径）。
                // 公式表重放侧身份未定，池子同样要把 ctx.source 剔掉；场上没有别的随从就不产生复制。
                let pool = uniqueBoardCards(s, excludingEntity: ctx.source)
                guard let first = pool.first else { return }
                let eid = s.takeEntityId()
                appendThisTurn(&s, RDHandCard(entityId: eid, card: first,
                                         pool: pool.count > 1 ? pool : [],
                                         enchants: [.set(setCost)], statsOverride: stats))
            }

        case .copyAllFriendlyToHand(let setCost, let attack, let health):
            let stats = RDStats(attack: attack, health: health)
            for minion in s.board {
                guard s.handSlotsFree > 0 else { break }
                let eid = s.takeEntityId()
                appendThisTurn(&s, RDHandCard(entityId: eid, card: minion.card,
                                         enchants: [.set(setCost)], statsOverride: stats))
            }

        case .refreshMana(let amount, let requiresDragon):
            if !requiresDragon || s.holdingDragon {
                s.mana = min(s.mana + amount, s.maxMana)
            }

        case .gainTempMana(let amount):
            s.tempMana += amount

        case .pushDiscount(let amount, let slots, let filter):
            s.layers.append(RDDiscountLayer(amount: amount, slots: slots, filter: filter))

        case .discountIfTargetDied(let amount, let slots):
            if ctx.lastTargetDied {
                s.layers.append(RDDiscountLayer(amount: amount, slots: slots, filter: .any))
            }

        case .draw(let filter, let count):
            for _ in 0..<count {
                let candidates = s.deck.remaining(filter: filter)
                guard !candidates.isEmpty else { continue }
                let picked: RDCard
                if candidates.count == 1 {
                    picked = candidates[0]
                } else if let c = nextChoice(&ctx), candidates.contains(c) {
                    picked = c
                } else {
                    throw RDIllegal.missingChoice
                }
                s.deck.remove(picked)
                guard s.handSlotsFree > 0 else { continue }  // 手牌满 → 抽到的被烧
                let eid = s.takeEntityId()
                appendThisTurn(&s, RDHandCard(entityId: eid, card: picked,
                                         isShadowOfDemise: picked == .shadowOfDemise))
            }

        case .discoverFromSideboard(let count):
            for _ in 0..<count {
                guard !s.sideboard.isEmpty else { continue }
                if ctx.options.deferredChoices {
                    guard s.handSlotsFree > 0 else { continue }
                    let pool = s.sideboard
                    let eid = s.takeEntityId()
                    appendThisTurn(&s, RDHandCard(entityId: eid, card: pool[0],
                                             pool: pool.count > 1 ? pool : [],
                                             poolFromSideboard: true))
                } else {
                    let picked: RDCard
                    if s.sideboard.count == 1 {
                        picked = s.sideboard[0]
                    } else if let c = nextChoice(&ctx), s.sideboard.contains(c) {
                        picked = c
                    } else {
                        throw RDIllegal.missingChoice
                    }
                    if let i = s.sideboard.firstIndex(of: picked) { s.sideboard.remove(at: i) }
                    guard s.handSlotsFree > 0 else { continue }  // 手牌满 → 发现不到
                    let eid = s.takeEntityId()
                    appendThisTurn(&s, RDHandCard(entityId: eid, card: picked))
                }
            }

        case .truncatedDraw:
            s.truncatedDraws += 1

        case .equipWeapon(let attack, let durability, let draws):
            s.weapon = RDWeapon(attack: attack, durability: durability, drawOnHeroAttack: draws)

        case .castSecret:
            break   // 本回合零贡献，只花费用 / 吃槽 / 腾一个手牌格

        case .removeOneFriendlyMinion:
            guard case .friendlyMinion(let id) = ctx.target,
                  let i = s.boardIndex(ofEntity: id) else { return }
            s.board.remove(at: i)
        }
    }

    /// 本回合进手的牌（抽到 / 发现 / 复制 / 弹回）都走这里，打上「本回合进手」（快枪看它）
    private static func appendThisTurn(_ s: inout RDState, _ card: RDHandCard) {
        var c = card
        c.enteredHandThisTurn = true
        s.hand.append(c)
    }

    private static func uniqueBoardCards(_ s: RDState, excludingEntity skip: Int?) -> [RDCard] {
        var seen = [Bool](repeating: false, count: RDCard.allCases.count)
        var out: [RDCard] = []
        for m in s.board where m.entityId != skip && !seen[m.card.rawValue] {
            seen[m.card.rawValue] = true
            out.append(m.card)
        }
        return out
    }

    private static func returnToHand(_ minion: RDBoardMinion, extraEnchant: RDEnchant,
                                     state s: inout RDState) {
        // 手牌满 → 弹回的随从被销毁（格子腾了，牌没了）
        guard s.handSlotsFree > 0 else { return }
        let eid = s.takeEntityId()
        appendThisTurn(&s, RDHandCard(entityId: eid, card: minion.card,
                                 enchants: minion.enchants + [extraEnchant],
                                 statsOverride: minion.statsSetTo1x1
                                     ? RDStats(attack: minion.attack, health: minion.maxHealth)
                                     : nil,
                                 isShadowOfDemise: false))
    }

    private static func silence(_ minion: inout RDBoardMinion) {
        minion.silenced = true
        if minion.statsSetTo1x1 {
            let def = RDCards.def(minion.card)
            minion.attack = def.attack
            minion.health = def.health
            minion.maxHealth = def.health
            minion.statsSetTo1x1 = false
        }
    }

    /// 返回「目标因这次伤害死亡」
    @discardableResult
    private static func dealDamage(_ amount: Int, to target: RDTarget,
                                   state s: inout RDState) -> Bool {
        guard amount > 0 else { return false }
        switch target {
        case .enemyHero:
            guard !s.opponent.immune else { return false }
            s.damageDealt += amount
            let toArmor = min(s.opponent.armor, amount)
            s.opponent.armor -= toArmor
            s.opponent.health -= (amount - toArmor)
            return s.opponent.health <= 0
        case .enemyMinion(let id):
            guard let i = s.opponent.board.firstIndex(where: { $0.entityId == id }) else {
                return false
            }
            if s.opponent.board[i].immune { return false }
            if s.opponent.board[i].divineShield {
                s.opponent.board[i].divineShield = false
                return false
            }
            s.opponent.board[i].health -= amount
            s.opponent.board[i].damaged = true
            return s.opponent.board[i].health <= 0
        case .friendlyMinion(let id):
            guard let i = s.boardIndex(ofEntity: id) else { return false }
            s.board[i].health -= amount
            return s.board[i].health <= 0
        default:
            return false
        }
    }

    private static func removeDeadMinions(_ s: inout RDState) {
        s.board.removeAll { !$0.isAlive }
        s.opponent.board.removeAll { $0.health <= 0 }
    }

    // MARK: - 英雄技能 / 攻击

    private static func useHeroPower(_ state: RDState) throws -> RDState {
        guard !state.heroPowerUsed else { throw RDIllegal.heroPowerUsed }
        guard state.availableMana >= 2 else { throw RDIllegal.notEnoughMana }
        var s = state
        let fromTemp = min(s.tempMana, 2)
        s.tempMana -= fromTemp
        s.mana -= (2 - fromTemp)
        s.heroPowerUsed = true
        s.weapon = RDWeapon(attack: 1, durability: 2, drawOnHeroAttack: false)
        return s
    }

    private static func resolveAttack(attacker: RDTarget, defender: RDTarget,
                                      state: RDState) throws -> RDState {
        var s = state
        let taunts = s.opponent.board.filter { $0.taunt && !$0.stealth }
        if !taunts.isEmpty {
            guard case .enemyMinion(let id) = defender,
                  taunts.contains(where: { $0.entityId == id }) else {
                throw RDIllegal.tauntInTheWay
            }
        }
        var attackPower = 0
        switch attacker {
        case .friendlyHero:
            guard let weapon = s.weapon, weapon.attack > 0, weapon.durability > 0 else {
                throw RDIllegal.noWeapon
            }
            guard !s.heroAttackedThisTurn else { throw RDIllegal.cannotAttack }
            attackPower = weapon.attack
            s.heroAttackedThisTurn = true
            s.weapon?.durability -= 1
        case .friendlyMinion(let id):
            guard let i = s.boardIndex(ofEntity: id) else { throw RDIllegal.cannotAttack }
            let m = s.board[i]
            guard !m.summoningSick, m.attack > 0, m.attacksThisTurn < 1 else {
                throw RDIllegal.cannotAttack
            }
            attackPower = m.attack
            s.board[i].attacksThisTurn += 1
        default:
            throw RDIllegal.cannotAttack
        }

        switch defender {
        case .enemyHero:
            dealDamage(attackPower, to: .enemyHero, state: &s)
        case .enemyMinion(let id):
            guard let i = s.opponent.board.firstIndex(where: { $0.entityId == id }) else {
                throw RDIllegal.illegalTarget
            }
            let counter = s.opponent.board[i].attack
            dealDamage(attackPower, to: .enemyMinion(id), state: &s)
            if case .friendlyMinion(let aid) = attacker {
                dealDamage(counter, to: .friendlyMinion(aid), state: &s)
            }
        default:
            throw RDIllegal.illegalTarget
        }
        removeDeadMinions(&s)
        return s
    }

    // MARK: - 合法动作枚举

    static func legalActions(_ state: RDState, options: RDOptions = .search) -> [RDAction] {
        var out: [RDAction] = []
        out.reserveCapacity(24)

        let orderMatters = options.expandPlacements && boardOrderMatters(state)
        // 同一张牌的不同实例（费用相同、附魔相同）只展开一次
        var seenCardKeys: [Int] = []
        seenCardKeys.reserveCapacity(state.hand.count)
        for card in state.hand {
            for identityIndex in 0..<card.identityCount {
                let identity = card.identity(at: identityIndex)
                let def = RDCards.def(identity)
                if !options.allowTruncatedDraws && hasTruncatedDraw(def) { continue }
                // 未建模的牌只占手牌格，不产生动作
                if def.isPlaceholder && !options.allowPlaceholderPlays { continue }
                let cost = state.cost(of: card, as: identity)
                guard state.availableMana >= cost else { continue }
                if def.type == .minion && state.boardSlotsFree <= 0 { continue }
                if isSecret(def) && state.secretsInPlay.contains(identity) { continue }
                var key = identity.rawValue &* 64 &+ min(63, cost)
                key = key &* 4 &+ min(3, card.enchants.count)
                key = key &* 2 &+ (card.statsOverride == nil ? 0 : 1)
                // 殒命暗影变成的 X 与真的 X 不是同一张（打出后前者没了，后者留着还能镜像下一张法术）
                key = key &* 2 &+ (card.isShadowOfDemise ? 1 : 0)
                if seenCardKeys.contains(key) { continue }
                seenCardKeys.append(key)

                var targets: [RDTarget]
                if def.targetScope == .none {
                    targets = [.none]
                } else {
                    targets = legalTargets(for: def, state: state)
                    if targets.isEmpty {
                        if def.needsTargetToPlay { continue }
                        targets = [.none]
                    }
                }
                let choiceSets = choiceCombinations(for: def, state: state, options: options)
                let positions = def.type == .minion && orderMatters
                    ? placements(for: card, identity: identity, state: state)
                    : [nil]
                for target in targets {
                    for choices in choiceSets {
                        for position in positions {
                            out.append(.play(entityId: card.entityId, identity: identity,
                                             target: target, choices: choices,
                                             position: position))
                        }
                    }
                }
            }
        }

        if !state.heroPowerUsed && state.availableMana >= 2 && state.weapon == nil {
            out.append(.heroPower)
        }

        let defenders: [RDTarget] = state.opponent.board.isEmpty
            ? [.enemyHero]
            : state.opponent.board.map { .enemyMinion($0.entityId) } + [.enemyHero]
        for m in state.board where !m.summoningSick && m.attack > 0 && m.attacksThisTurn < 1 {
            for d in defenders {
                out.append(.attack(attacker: .friendlyMinion(m.entityId), defender: d))
            }
        }
        if let w = state.weapon, w.attack > 0, w.durability > 0, !state.heroAttackedThisTurn {
            for d in defenders {
                out.append(.attack(attacker: .friendlyHero, defender: d))
            }
        }
        return out
    }

    // MARK: - 落位

    /// 场上顺序只通过「按从左到右处理全场」的效果影响结果：舞动全弹回（手牌满时右侧的被烧）、
    /// 幻觉药水复制全场（手牌满时右侧的进不了手）。本牌组没有相邻 / 位置类效果。
    /// 所以手牌、边牌、牌库里都没有这类效果时，所有落位等价，只展开最右一种。
    /// 殒命暗影只会镜像「打出过的法术」，那张法术本身一定也在这三处之一，不必单独看。
    static func boardOrderMatters(_ s: RDState) -> Bool {
        let ordered = processesBoardInOrder
        for c in s.hand {
            for i in 0..<c.identityCount where ordered(c.identity(at: i)) { return true }
        }
        for c in s.sideboard where ordered(c) { return true }
        for raw in 0..<s.deck.counts.count where s.deck.counts[raw] > 0 {
            if let card = RDCard(rawValue: raw), ordered(card) { return true }
        }
        return false
    }

    /// 这张牌有「从左到右处理全场、手牌放不下的丢掉」的效果（舞动全弹回 / 幻觉药水复制全场）
    static func processesBoardInOrder(_ card: RDCard) -> Bool {
        return boardOrderCards[card.rawValue]
    }

    /// 按 rawValue 预先算好（搜索里每个动作都要问一次）
    private static let boardOrderCards: [Bool] = RDCard.allCases.map { card in
        let def = RDCards.def(card)
        return (def.effects + def.comboEffects).contains { e in
            switch e {
            case .bounceAllFriendly, .copyAllFriendlyToHand: return true
            default: return false
            }
        }
    }

    /// 场上随从按进哈希的字段算的键：两个随从键相同，互换位置得到同一个局面
    static func minionKey(_ m: RDBoardMinion) -> Int {
        var k = m.card.rawValue &* 4096 &+ min(63, m.health) &* 64 &+ min(31, m.attack) &* 2
        k = k &* 2 &+ (m.statsSetTo1x1 ? 1 : 0)
        k = k &* 8 &+ (m.summoningSick ? 0 : 1) &+ (m.silenced ? 2 : 0) &+ min(1, m.attacksThisTurn) &* 4
        for e in m.enchants {
            switch e {
            case .set(let v): k = k &* 31 &+ 100 &+ v
            case .delta(let v): k = k &* 31 &+ 200 &+ v
            }
        }
        return k
    }

    /// 结果上不等价的落位（`expandPlacements` 为 true 时 `legalActions` 用；束搜索和严格重放改用
    /// `RDBoardOrder` 在爆手时再决定，见文件末尾）。把新随从插进第 p 格，得到的场面序列（按进哈希的全部字段比较）
    /// 相同的落位只留一个：插在一个完全相同的随从左边还是右边，结果是同一个状态。
    /// 最右一格用 nil 表示（和不指定落位等价），排在最前。
    static func placements(for card: RDHandCard, identity: RDCard, state: RDState) -> [Int?] {
        let def = RDCards.def(identity)
        let stats = card.statsOverride ?? RDStats(attack: def.attack, health: def.health)
        var newKey = identity.rawValue &* 4096 &+ min(63, stats.health) &* 64 &+ min(31, stats.attack) &* 2
        newKey = newKey &* 2 &+ (card.statsOverride != nil ? 1 : 0)
        newKey = newKey &* 8   // 新下的随从：召唤失调、未沉默、未攻击
        for e in card.enchants {
            switch e {
            case .set(let v): newKey = newKey &* 31 &+ 100 &+ v
            case .delta(let v): newKey = newKey &* 31 &+ 200 &+ v
            }
        }
        var keys: [Int] = state.board.map(minionKey)
        let n = keys.count
        var seen: [[Int]] = []
        var out: [Int?] = []
        for p in stride(from: n, through: 0, by: -1) {
            keys.insert(newKey, at: p)
            if !seen.contains(keys) {
                seen.append(keys)
                out.append(p == n ? nil : p)
            }
            keys.remove(at: p)
        }
        return out
    }

    /// 发现 / 抽牌的确定化分支。剩余 ≤ 抽取数时只有一种结果，折入主线不分叉。
    private static let noChoices: [[RDChoice]] = [[]]

    private static func mayNeedChoices(_ def: RDCardDef) -> Bool {
        for e in def.effects {
            switch e {
            case .draw, .discoverFromSideboard: return true
            default: break
            }
        }
        for e in def.comboEffects {
            switch e {
            case .draw, .discoverFromSideboard: return true
            default: break
            }
        }
        return false
    }

    private static func choiceCombinations(for def: RDCardDef, state: RDState,
                                           options: RDOptions) -> [[RDChoice]] {
        guard mayNeedChoices(def) else { return noChoices }
        if options.deferredChoices { return noChoices }
        var pools: [[RDCard]] = []
        var deck = state.deck
        var sideboard = state.sideboard
        let usesCombo = state.comboActive && !def.comboEffects.isEmpty
        let triggers = triggerCount(def, sharkAura: state.sharkAuraActive,
                                    cometDoubles: usesCombo && consumesLuckyComet(def)
                                        && state.luckyCometCharges > 0)
        let effects = usesCombo ? def.comboEffects : def.effects
        for _ in 0..<triggers {
            for e in effects {
                switch e {
                case .draw(let filter, let count):
                    for _ in 0..<count {
                        let candidates = deck.remaining(filter: filter)
                        if candidates.count > 1 {
                            pools.append(candidates)
                            deck.remove(candidates[0])
                        } else if candidates.count == 1 {
                            deck.remove(candidates[0])
                        }
                    }
                case .discoverFromSideboard(let count):
                    for _ in 0..<count where !sideboard.isEmpty {
                        if sideboard.count > 1 {
                            pools.append(sideboard)
                            sideboard.removeFirst()
                        } else {
                            sideboard.removeFirst()
                        }
                    }
                default:
                    break
                }
            }
        }
        guard !pools.isEmpty else { return [[]] }

        var combos: [[RDChoice]] = [[]]
        for pool in pools {
            var next: [[RDChoice]] = []
            for combo in combos {
                for card in pool {
                    // 同一张牌不重复选（发现 / 连抽都是从池里拿走）
                    if combo.contains(.pick(card)) { continue }
                    next.append(combo + [.pick(card)])
                }
            }
            combos = next
            if combos.count > options.maxChoiceCombinations {
                combos = Array(combos.prefix(options.maxChoiceCombinations))
            }
        }
        return combos.isEmpty ? [[]] : combos
    }
}

// MARK: - 延后决定的落位

/// 场面顺序只在「从左到右处理全场、手牌放不下就丢」的那一刻起作用（舞动全弹回 / 幻觉药水复制全场，
/// 用户 09-11 定的规则）。下随从时可以插到任意一格，所以不必在每次下随从时逐格展开：随从先一律放最右，
/// 只记下**哪些先后关系已经定了**（`RDBoardConstraints`，一个偏序），到爆手那一步展开「进手的是哪几张」
/// ——偏序里大小为 k 的每个下闭集（排在它们前面的必须也在里面）——事后再翻译回每次下随从的落位
/// （`assignPositions`）。偏序怎么来：
/// - 回合开始就在场上的随从：按原顺序全序；
/// - 新下的随从：和谁都没有先后关系（可以插任意一格）；
/// - 爆手时选定进手的集合 C：C 里的每个都排在没进手的每个左边。舞动之后场面清空，这条无所谓；
///   **幻觉药水保留场面**，C 内部、C 外部的相对顺序仍然没定，留给之后的舞动 / 药水去定。
/// 和逐格展开得到的结果集合相同（单测逐个比对），分支少得多。
/// 束搜索和公式验证的严格重放都走这条路；翻译出的带落位动作序列再由引擎原样重放校验。
/// 本牌组没有召唤效果；以后加了，召唤出的随从不是玩家放的，要按场上现有位置加约束。
struct RDOrderPair: Equatable {
    var left: Int
    var right: Int
}

/// 场上已经定下来的先后关系（entityId 对），只含当前在场的随从，始终传递闭合。
/// 状态里 `board` 的顺序永远是这个偏序的一个线性扩展，只是代表，不是定论。
struct RDBoardConstraints {
    var pairs: [RDOrderPair] = []

    /// 起始场面：回合开始就在场上的随从按原顺序全序
    static func root(_ s: RDState) -> RDBoardConstraints {
        var c = RDBoardConstraints()
        let ids = s.board.map { $0.entityId }
        for i in ids.indices {
            for j in (i + 1)..<max(i + 1, ids.count) {
                c.pairs.append(RDOrderPair(left: ids[i], right: ids[j]))
            }
        }
        return c
    }

    /// 只保留两端都还在场的关系（离场的随从不会再回来：弹回 / 复制进手的是新实体）
    func restricted(to board: [RDBoardMinion]) -> RDBoardConstraints {
        if pairs.isEmpty { return self }
        var out = RDBoardConstraints()
        for p in pairs where board.contains(where: { $0.entityId == p.left })
            && board.contains(where: { $0.entityId == p.right }) {
            out.pairs.append(p)
        }
        return out
    }

    /// 按格子位置编码（第 i 格必须在第 j 格左边 → 第 i*8+j 位），与 entityId 无关，进去重键
    func positionMask(_ board: [RDBoardMinion]) -> UInt64 {
        if pairs.isEmpty { return 0 }
        var mask: UInt64 = 0
        for p in pairs {
            guard let i = board.firstIndex(where: { $0.entityId == p.left }),
                  let j = board.firstIndex(where: { $0.entityId == p.right }), i < 8, j < 8 else { continue }
            mask |= 1 << UInt64(i * 8 + j)
        }
        return mask
    }
}

/// 爆手那一步定下的顺序
struct RDOrderDecision: Equatable {
    /// 打出前场面被排成的顺序（entityId，从左到右）。它是当时偏序的一个线性扩展，前 `front` 个正好是 C
    var order: [Int]
    /// 进手的集合 C 的大小（最后一轮没处理完的那部分）
    var front: Int
}

struct RDBoardOutcome {
    var state: RDState
    var constraints: RDBoardConstraints
    /// 爆手时选定的顺序；不爆手时 nil
    var decision: RDOrderDecision?
}

enum RDBoardOrder {

    /// 打出 `action` 的所有结果。`first` = 按状态里现有顺序打出的结果，总排第一个。
    /// 不是全场弹回 / 复制、或顺序不影响结果时只有一种（decision = nil）；
    /// 爆手时偏序允许的每种「进手集合」一个（结果相同的只留一个）
    static func outcomes(of action: RDAction, from s: RDState, constraints c: RDBoardConstraints,
                         first: RDState, options: RDOptions) -> [RDBoardOutcome] {
        let plain = [RDBoardOutcome(state: first, constraints: c.restricted(to: first.board), decision: nil)]
        guard case .play(let eid, let identity, _, _, _) = action,
              RDEngine.processesBoardInOrder(identity),
              s.hand.contains(where: { $0.entityId == eid }) else { return plain }
        let n = s.board.count
        // 打出的牌离手后，这张牌送进手牌几张。复制全场可能结算多轮（每轮按从左到右），
        // 只有最后没处理完的那一轮受顺序影响：进手的是场面的前 k mod n 个
        let k = first.hand.count - (s.hand.count - 1)
        guard n > 0, k >= 0 else { return plain }
        let m = k % n
        guard m > 0 else { return plain }

        let ids = s.board.map { $0.entityId }
        var pred = [Int](repeating: 0, count: n)   // pred[j]：必须排在第 j 个左边的位置掩码
        for p in c.pairs {
            if let i = ids.firstIndex(of: p.left), let j = ids.firstIndex(of: p.right) { pred[j] |= 1 << i }
        }
        let keepsBoard = !RDCards.def(identity).effects.contains { e in
            if case .bounceAllFriendly = e { return true }
            return false
        }
        let keys = s.board.map(RDEngine.minionKey)
        // 现有顺序的前 m 个（状态里的顺序是偏序的线性扩展，所以它一定合法）排第一个
        let firstMask = (1 << m) - 1
        var masks = [firstMask]
        for combo in combinations(n, m) {
            let mask = combo.reduce(0) { $0 | (1 << $1) }
            if mask != firstMask { masks.append(mask) }
        }
        var out: [RDBoardOutcome] = []
        var tried = Set<[Int]>()
        var hashes = Set<UInt64>()
        for mask in masks {
            // 下闭集：C 里每个随从，偏序要求排在它左边的也都在 C 里
            var closed = true
            for j in 0..<n where mask & (1 << j) != 0 && pred[j] & ~mask != 0 {
                closed = false
                break
            }
            guard closed else { continue }
            let frontIdx = (0..<n).filter { mask & (1 << $0) != 0 }
            let backIdx = (0..<n).filter { mask & (1 << $0) == 0 }
            let orderIdx = frontIdx + backIdx
            // 先不结算，按结果去重：一模一样的随从选哪个结果相同。
            // 全弹回之后场面清空，只看进手的多重集；复制全场之后场面保留，要比整个场面序列 + 之后的偏序
            var newPairs = c.pairs
            for a in frontIdx {
                for b in backIdx where !c.pairs.contains(RDOrderPair(left: ids[a], right: ids[b])) {
                    newPairs.append(RDOrderPair(left: ids[a], right: ids[b]))
                }
            }
            let nc = RDBoardConstraints(pairs: newPairs)
            let reordered = orderIdx.map { s.board[$0] }
            var signature = frontIdx.map { keys[$0] }.sorted()
            if keepsBoard {
                signature += [-1] + orderIdx.map { keys[$0] }
                let pm = nc.positionMask(reordered)
                signature += [Int(truncatingIfNeeded: pm), Int(truncatingIfNeeded: pm >> 32)]
            }
            guard tried.insert(signature).inserted else { continue }
            let next: RDState
            if mask == firstMask {
                next = first
            } else {
                var p = s
                p.board = reordered
                guard let x = try? RDEngine.apply(action, to: p, options: options) else { continue }
                next = x
            }
            let restricted = nc.restricted(to: next.board)
            let h = next.canonicalHash() ^ (restricted.positionMask(next.board) &* 0x9e37_79b9_7f4a_7c15)
            guard hashes.insert(h).inserted else { continue }
            out.append(RDBoardOutcome(state: next, constraints: restricted,
                                      decision: RDOrderDecision(order: orderIdx.map { ids[$0] }, front: m)))
        }
        return out
    }

    /// 不爆手的动作之后的偏序：只去掉离场的随从（新下的随从不加任何关系）
    static func carry(_ c: RDBoardConstraints, to next: RDState) -> RDBoardConstraints {
        return c.restricted(to: next.board)
    }

    /// 把爆手处选定的顺序（`decisions[i]`，只在爆手处非空）翻译成每次下随从的落位，并把后续动作里的
    /// entityId 换成带落位重放时的实际编号。失败（翻译不出、重放走不通）返回 nil，调用方丢掉这条线。
    ///
    /// 做法：第一遍按搜索的口径重走（随从放最右、爆手处按 decision 重排），收集所有先后关系
    /// ——起始场面的全序 + 每次爆手「C 在其余之左」——并起来是一个无环关系（偏序始终传递闭合、
    /// 随从在场的时间是连续的一段），取一个拓扑序 G（并列时按上场先后）。第二遍带落位重走：
    /// 每次下随从都插到「场上 G 序比它小的随从」之后，于是任何时刻场面都按 G 排好，每次爆手时
    /// 前几个正好是选定的 C。
    ///
    /// 编号：落位一变，不爆手的复制 / 弹回进手顺序就变了，新实体拿到的编号对应的牌也跟着变。
    /// 所以第二遍每走一步，都把两遍里这一步新出现的实体按内容（除编号外的全部字段）配对，
    /// 后续动作里的编号按这张对照表改写。内容完全相同的两个实体互换不影响结果。
    static func assignPositions(_ actions: [RDAction], decisions: [RDOrderDecision?], root: RDState,
                                options: RDOptions) -> [RDAction]? {
        guard decisions.count == actions.count else { return nil }
        guard decisions.contains(where: { $0 != nil }) else { return actions }

        // 第一遍：搜索口径
        var pre1: [RDState] = []
        var post1: [RDState] = []
        var s = root
        var pairs = RDBoardConstraints.root(root).pairs
        var appear: [Int] = root.board.map { $0.entityId }
        for (i, a) in actions.enumerated() {
            if let d = decisions[i] {
                guard d.order.count == s.board.count, d.front <= d.order.count else { return nil }
                let board = d.order.compactMap { id in s.board.first { $0.entityId == id } }
                guard board.count == s.board.count else { return nil }
                s.board = board
                for x in d.order.prefix(d.front) {
                    for y in d.order.dropFirst(d.front) { pairs.append(RDOrderPair(left: x, right: y)) }
                }
            }
            guard let next = try? RDEngine.apply(a, to: s, options: options) else { return nil }
            for m in next.board where !appear.contains(m.entityId) { appear.append(m.entityId) }
            pre1.append(s)
            post1.append(next)
            s = next
        }

        // 拓扑序 G：并列时取上场最早的（没有约束的新随从因此排在已在场的之后 = 放最右）
        var remaining = appear
        var rank: [Int: Int] = [:]
        while !remaining.isEmpty {
            guard let pick = remaining.firstIndex(where: { id in
                !pairs.contains { $0.right == id && rank[$0.left] == nil && $0.left != id }
            }) else { return nil }   // 有环：不该发生
            rank[remaining[pick]] = rank.count
            remaining.remove(at: pick)
        }

        // 第二遍：带落位重走，同时维护「第一遍编号 → 第二遍编号」
        var map: [Int: Int] = [:]
        var back: [Int: Int] = [:]
        func fwd(_ id: Int) -> Int { return map[id] ?? id }
        func remap(_ t: RDTarget) -> RDTarget {
            if case .friendlyMinion(let id) = t { return .friendlyMinion(fwd(id)) }
            return t
        }
        var t = root
        var out: [RDAction] = []
        for (i, a) in actions.enumerated() {
            var action: RDAction
            switch a {
            case .play(let eid, let identity, let target, let choices, let position):
                var pos = position
                if RDCards.def(identity).type == .minion {
                    guard let n1 = post1[i].board.first(where: { m in
                        !pre1[i].board.contains { $0.entityId == m.entityId }
                    })?.entityId, let r = rank[n1] else { return nil }
                    let p = t.board.filter { m in (rank[back[m.entityId] ?? m.entityId] ?? Int.max) < r }.count
                    pos = p == t.board.count ? nil : p
                }
                action = .play(entityId: fwd(eid), identity: identity, target: remap(target),
                               choices: choices, position: pos)
            case .heroPower:
                action = a
            case .attack(let attacker, let defender):
                action = .attack(attacker: remap(attacker), defender: remap(defender))
            }
            guard let next = try? RDEngine.apply(action, to: t, options: options) else { return nil }
            // 这一步新出现的实体按内容配对
            let new1 = newEntities(before: pre1[i], after: post1[i])
            let new2 = newEntities(before: t, after: next)
            guard new1.count == new2.count else { return nil }
            var used = [Bool](repeating: false, count: new2.count)
            for (id1, content) in new1 {
                guard let j = new2.indices.first(where: { !used[$0] && new2[$0].content == content }) else {
                    return nil
                }
                used[j] = true
                map[id1] = new2[j].id
                back[new2[j].id] = id1
            }
            out.append(action)
            t = next
        }
        return out
    }

    /// 这一步新出现的实体（编号 ≥ 打出前的 nextEntityId）及其内容（除编号外的全部字段）
    private static func newEntities(before: RDState, after: RDState) -> [(id: Int, content: String)] {
        var out: [(id: Int, content: String)] = []
        for c in after.hand where c.entityId >= before.nextEntityId {
            let stats = c.statsOverride.map { "\($0.attack)/\($0.health)" } ?? "-"
            out.append((c.entityId, "h\(c.card.rawValue)|\(c.pool.map { $0.rawValue })|\(c.enchants)|\(stats)|"
                        + "\(c.isShadowOfDemise)|\(c.printedCostOverride ?? -1)|\(c.poolFromSideboard)|"
                        + "\(c.enteredHandThisTurn)"))
        }
        for m in after.board where m.entityId >= before.nextEntityId {
            out.append((m.entityId, "b\(m.card.rawValue)|\(m.attack)|\(m.health)|\(m.maxHealth)|"
                        + "\(m.statsSetTo1x1)|\(m.silenced)|\(m.summoningSick)|\(m.attacksThisTurn)|"
                        + "\(m.enchants)"))
        }
        return out
    }

    /// 从 n 个里取 m 个的全部组合（下标升序）
    private static func combinations(_ n: Int, _ m: Int) -> [[Int]] {
        guard m > 0 else { return [[]] }
        guard m <= n else { return [] }
        var out: [[Int]] = []
        var acc: [Int] = []
        func rec(_ from: Int) {
            if acc.count == m { out.append(acc); return }
            guard from < n else { return }
            for i in from..<n {
                acc.append(i)
                rec(i + 1)
                acc.removeLast()
            }
        }
        rec(0)
        return out
    }
}

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
    case play(entityId: Int, identity: RDCard, target: RDTarget, choices: [RDChoice])
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

    static let search = RDOptions()
    static let replay = RDOptions(deferredChoices: true, allowTruncatedDraws: true,
                                  maxChoiceCombinations: 12, allowPlaceholderPlays: true)
}

enum RDEngine {

    // MARK: - 打牌

    static func apply(_ action: RDAction, to state: RDState,
                      options: RDOptions = .search) throws -> RDState {
        switch action {
        case .play(let entityId, let identity, let target, let choices):
            return try playCard(entityId: entityId, identity: identity, target: target,
                                choices: choices, state: state, options: options)
        case .heroPower:
            return try useHeroPower(state)
        case .attack(let attacker, let defender):
            return try resolveAttack(attacker: attacker, defender: defender, state: state)
        }
    }

    private static func playCard(entityId: Int, identity: RDCard, target: RDTarget,
                                 choices: [RDChoice], state: RDState,
                                 options: RDOptions) throws -> RDState {
        guard let handIndex = state.handIndex(ofEntity: entityId) else { throw RDIllegal.noSuchCard }
        let handCard = state.hand[handIndex]
        guard handCard.hasIdentity(identity) else { throw RDIllegal.wrongIdentity }
        let def = RDCards.def(identity)

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
        s.cardsPlayedThisTurn += 1
        consumeLayers(&s, def: def)

        var summonedId: Int?
        if def.type == .minion {
            let stats = handCard.statsOverride ?? RDStats(attack: def.attack, health: def.health)
            let id = s.takeEntityId()
            s.board.append(RDBoardMinion(entityId: id, card: identity,
                                         attack: stats.attack, health: stats.health,
                                         maxHealth: stats.health,
                                         statsSetTo1x1: handCard.statsOverride != nil,
                                         silenced: false, summoningSick: true,
                                         attacksThisTurn: 0, enchants: handCard.enchants))
            summonedId = id
        }

        let effects = (comboActive && !def.comboEffects.isEmpty) ? def.comboEffects : def.effects
        // 鲨鱼之灵只翻倍「随从的」战吼 / 连击
        let triggers = (def.doubledByShark && s.sharkAuraActive) ? 2 : 1

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
        return out
    }

    private static func appendFriendlyTargets(_ state: RDState, into out: inout [RDTarget]) {
        var seen: [Int] = []
        for m in state.board {
            var key = m.card.rawValue &* 4096 &+ min(63, m.health) &* 64 &+ min(31, m.attack) &* 2
            key &+= m.statsSetTo1x1 ? 1 : 0
            for e in m.enchants {
                switch e {
                case .set(let v): key = key &* 31 &+ 100 &+ v
                case .delta(let v): key = key &* 31 &+ 200 &+ v
                }
            }
            if seen.contains(key) { continue }
            seen.append(key)
            out.append(.friendlyMinion(m.entityId))
        }
    }

    private static func appendEnemyTargets(_ state: RDState, into out: inout [RDTarget]) {
        var seen: [Int] = []
        for m in state.opponent.board {
            let key = min(63, m.health) &* 64 &+ min(31, m.attack) &* 4
                &+ (m.taunt ? 2 : 0) &+ (m.divineShield ? 1 : 0)
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
                s.hand.append(RDHandCard(entityId: eid, card: card, enchants: [.set(setCost)],
                                         statsOverride: stats))
            } else if ctx.target == .unspecifiedFriendly {
                // 指向性战吼是**下场前**选目标，施法者自己不在候选里（搜索侧本来就是这个口径）。
                // 公式表重放侧身份未定，池子同样要把 ctx.source 剔掉；场上没有别的随从就不产生复制。
                let pool = uniqueBoardCards(s, excludingEntity: ctx.source)
                guard let first = pool.first else { return }
                let eid = s.takeEntityId()
                s.hand.append(RDHandCard(entityId: eid, card: first,
                                         pool: pool.count > 1 ? pool : [],
                                         enchants: [.set(setCost)], statsOverride: stats))
            }

        case .copyAllFriendlyToHand(let setCost, let attack, let health):
            let stats = RDStats(attack: attack, health: health)
            for minion in s.board {
                guard s.handSlotsFree > 0 else { break }
                let eid = s.takeEntityId()
                s.hand.append(RDHandCard(entityId: eid, card: minion.card,
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
                s.hand.append(RDHandCard(entityId: eid, card: picked,
                                         isShadowOfDemise: picked == .shadowOfDemise))
            }

        case .discoverFromSideboard(let count):
            for _ in 0..<count {
                guard !s.sideboard.isEmpty else { continue }
                if ctx.options.deferredChoices {
                    guard s.handSlotsFree > 0 else { continue }
                    let pool = s.sideboard
                    let eid = s.takeEntityId()
                    s.hand.append(RDHandCard(entityId: eid, card: pool[0],
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
                    s.hand.append(RDHandCard(entityId: eid, card: picked))
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
        s.hand.append(RDHandCard(entityId: eid, card: minion.card,
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
                for target in targets {
                    for choices in choiceSets {
                        out.append(.play(entityId: card.entityId, identity: identity,
                                         target: target, choices: choices))
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
        let triggers = (def.doubledByShark && state.sharkAuraActive) ? 2 : 1
        let effects = (state.comboActive && !def.comboEffects.isEmpty)
            ? def.comboEffects : def.effects
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

//
//  RedDragonLiveTests.swift
//  HSTrackerTests
//
//  T2b：读取层（手工构造的对局实体 → 快照 → 根局面）、展示模型、揭示档 / 答题规则、开关热切换。
//  真实对局的回放在 RedDragonLiveReplayTests.swift。
//

import XCTest
@testable import HSTracker
@testable import RedDragonCore

class RedDragonLiveTests: HSTrackerTests {

    override class func setUp() {
        super.setUp()
        if Cards.by(cardId: CardIds.Collectible.Rogue.Shadowstep) == nil {
            Database().loadDatabase(splashscreen: nil, withLanguages: [.enUS])
        }
        // 宿主 app 启动时自己也在后台读卡牌库，是一张张读进来的：上面只看「暗影步」在不在，读到一半也会放行。
        // 这个类单独跑时排第一的用例正好撞上 —— `Table.add` 靠卡牌库定牌的类型，鲨鱼之灵还没读进来就不算随从、
        // 局面里没有它（T8 阶段 B 撞到过：破冰线少了翻倍）。等红龙卡表里的牌都查得到再开始
        let ids = RDCard.allCases.compactMap { RDCards.def($0).ids.first }
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, ids.contains(where: { Cards.any(byId: $0) == nil }) {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }

    // MARK: - 手工构造的对局

    private static let me = 1
    private static let them = 2

    /// 一局最小的对局：游戏实体、双方玩家实体、双方英雄、我方英雄技能。`build` 往里加牌
    private final class Table {
        var entities: [Entity] = []
        var nextId = 100
        let player: Entity
        let opponentHero: Entity

        init(resources: Int = 10, used: Int = 0, turn: Int = 9) {
            let gameEntity = Entity(id: 1)
            gameEntity.name = "GameEntity"
            gameEntity[.cardtype] = CardType.game.rawValue
            gameEntity[.turn] = turn
            player = Entity(id: 2)
            player[.player_id] = RedDragonLiveTests.me
            player[.resources] = resources
            player[.resources_used] = used
            player[.current_player] = 1
            let opponent = Entity(id: 3)
            opponent[.player_id] = RedDragonLiveTests.them
            let hero = Entity(id: 4)
            hero.cardId = RDCards.heroId
            hero[.cardtype] = CardType.hero.rawValue
            hero[.controller] = RedDragonLiveTests.me
            hero[.zone] = Zone.play.rawValue
            hero[.health] = 30
            let power = Entity(id: 5)
            power.cardId = RDCards.heroPowerId
            power[.cardtype] = CardType.hero_power.rawValue
            power[.controller] = RedDragonLiveTests.me
            power[.zone] = Zone.play.rawValue
            opponentHero = Entity(id: 6)
            opponentHero.cardId = "HERO_01"
            opponentHero[.cardtype] = CardType.hero.rawValue
            opponentHero[.controller] = RedDragonLiveTests.them
            opponentHero[.zone] = Zone.play.rawValue
            opponentHero[.health] = 30
            entities = [gameEntity, player, opponent, hero, power, opponentHero]
        }

        @discardableResult
        func add(_ cardId: String, zone: Zone, controller: Int = RedDragonLiveTests.me,
                 tags: [GameTag: Int] = [:]) -> Entity {
            let e = Entity(id: nextId)
            nextId += 1
            e.cardId = cardId
            let card = Cards.any(byId: cardId)
            switch card?.type {
            case .minion?: e[.cardtype] = CardType.minion.rawValue
            case .spell?: e[.cardtype] = CardType.spell.rawValue
            case .weapon?: e[.cardtype] = CardType.weapon.rawValue
            default: break
            }
            e[.controller] = controller
            e[.zone] = zone.rawValue
            e[.cost] = card?.cost ?? 0
            e[.atk] = card?.attack ?? 0
            e[.health] = card?.health ?? 0
            let sameZone = entities.filter { $0[.zone] == zone.rawValue && $0[.controller] == controller
                && ($0.isMinion || zone == .hand) }
            e[.zone_position] = sameZone.count + 1
            for (k, v) in tags { e[k] = v }
            entities.append(e)
            return e
        }

        /// 附魔：挂在 `target` 上（玩家实体或一张牌）
        @discardableResult
        func enchant(_ cardId: String, on target: Entity, tags: [GameTag: Int] = [:]) -> Entity {
            let e = Entity(id: nextId)
            nextId += 1
            e.cardId = cardId
            e[.cardtype] = CardType.enchantment.rawValue
            e[.controller] = RedDragonLiveTests.me
            e[.zone] = Zone.play.rawValue
            e[.attached] = target.id
            for (k, v) in tags { e[k] = v }
            entities.append(e)
            return e
        }

        func snapshot(deck: [String: Int] = [:], band: [String]? = RDCards.sideboardCards.map(RedDragonLiveTests.id))
            -> RDGameSnapshot {
            return RDGameSnapshot.capture(entities: entities, playerId: RedDragonLiveTests.me,
                                          opponentId: RedDragonLiveTests.them, deck: deck, band: band)
        }
    }

    static func id(_ c: RDCard) -> String { return RDCards.def(c).ids[0] }

    // MARK: - 读取层

    /// 同名不同费：一张原版刀油 4 费、一张被暗影步收回过的 2 费。费用逐张读 entity[.cost]，两张都能打
    func testSameNameDifferentCostKeepsPerEntityCost() {
        let t = Table(resources: 4)
        let a = t.add("BAR_552", zone: .hand)
        let b = t.add("BAR_552", zone: .hand, tags: [.cost: 2])
        let live = RDStateReader.read(t.snapshot())
        let s = live.state
        XCTAssertEqual(s.hand.map { $0.entityId }, [a.id, b.id])
        XCTAssertEqual(s.hand.map { s.cost(of: $0, as: $0.card) }, [4, 2])
        XCTAssertEqual(live.handZonePositions[a.id], 1)
        XCTAssertEqual(live.handZonePositions[b.id], 2)
        let plays = RDEngine.legalActions(s).compactMap { a -> Int? in
            if case .play(let eid, .scabbsCutterbutter, _, _, _) = a { return eid }
            return nil
        }
        XCTAssertEqual(Set(plays), [a.id, b.id], "费用不同的同名牌不能被当成同一张合并掉")
    }

    /// 1/1 复制体：手里的药水复制品（SCH_352e + SCH_352e2）、场上的暗影施法者复制品（OG_291e）
    func testOneOneCopiesInHandAndOnBoard() {
        let t = Table(resources: 5)
        let inHand = t.add("LEG_CS3_031", zone: .hand, tags: [.cost: 1, .atk: 1, .health: 1])
        t.enchant("SCH_352e", on: inHand)
        t.enchant("SCH_352e2", on: inHand)
        let onBoard = t.add("LEG_CS3_031", zone: .play, tags: [.atk: 1, .health: 1, .exhausted: 1])
        t.enchant("OG_291e", on: onBoard)
        t.add("EX1_144", zone: .hand)
        t.add("JAM_022", zone: .hand)
        let s = RDStateReader.read(t.snapshot()).state

        let copy = s.hand[0]
        XCTAssertEqual(copy.card, .alexstrasza)
        XCTAssertEqual(copy.statsOverride, RDStats(attack: 1, health: 1))
        XCTAssertEqual(s.cost(of: copy, as: .alexstrasza), 1)

        let m = s.board[0]
        XCTAssertTrue(m.statsSetTo1x1)
        XCTAssertEqual(m.enchants, [.set(1)])
        XCTAssertTrue(m.summoningSick)

        // 暗影步收回复制体：复制附魔消失，印刷 9 - 2 = 7
        let step = s.hand[1]
        let bounced = try? RDEngine.apply(.play(entityId: step.entityId, identity: .shadowstep,
                                                target: .friendlyMinion(m.entityId), choices: []), to: s)
        let back = bounced?.hand.last
        XCTAssertEqual(back?.card, .alexstrasza)
        XCTAssertEqual(back.map { bounced!.cost(of: $0, as: .alexstrasza) }, 7)
        XCTAssertNil(back?.statsOverride)

        // 致聋术沉默复制体：1/1 附魔被拿掉，变回 8/8
        let deafen = s.hand[2]
        let silenced = try? RDEngine.apply(.play(entityId: deafen.entityId, identity: .deafen,
                                                 target: .friendlyMinion(m.entityId), choices: []), to: s)
        XCTAssertEqual(silenced?.board.first?.attack, 8)
        XCTAssertEqual(silenced?.board.first?.health, 8)
    }

    /// T3 日志订正：当前场上实体的费用附魔可读取，但回手清除。无论此前被舞动或暗影步收回过，
    /// 再被暗影步收回都按印刷费 4 - 2，不跨区域叠加旧减费。
    func testBoardCostEnchantsAreClearedByShadowstep() throws {
        let t = Table(resources: 10)
        let danced = t.add("TRL_092", zone: .play, tags: [.exhausted: 1])
        t.enchant("ETC_079e", on: danced)
        let plain = t.add("TRL_092", zone: .play, tags: [.exhausted: 1])
        let stepped = t.add("TRL_092", zone: .play, tags: [.exhausted: 1])
        t.enchant("GBL_002e", on: stepped)
        t.add("EX1_144", zone: .hand)
        let s = RDStateReader.read(t.snapshot()).state

        func board(_ e: Entity) -> RDBoardMinion? { return s.board.first { $0.entityId == e.id } }
        XCTAssertEqual(board(danced)?.enchants, [.set(1)])
        XCTAssertEqual(board(plain)?.enchants, [])
        XCTAssertEqual(board(stepped)?.enchants, [.delta(-2)])

        let step = try XCTUnwrap(s.hand.first { $0.card == .shadowstep })
        func costAfterStep(_ e: Entity) throws -> Int? {
            let next = try RDEngine.apply(.play(entityId: step.entityId, identity: .shadowstep,
                                                target: .friendlyMinion(e.id), choices: []), to: s)
            return next.hand.first { $0.card == .spiritOfTheShark }.map { next.cost(of: $0, as: .spiritOfTheShark) }
        }
        XCTAssertEqual(try costAfterStep(danced), 2, "旧舞动费用清除，印刷费 4 − 2")
        XCTAssertEqual(try costAfterStep(plain), 2, "对照：印刷费 4 − 2")
        XCTAssertEqual(try costAfterStep(stepped), 2, "两次暗影步不跨区域叠加")
        // 不认识的附魔（身材 buff 等）不进费用链
        XCTAssertEqual(RDStateReader.boardCostEnchants(["TTN_858t2e1", "ETC_079e", "DAL_714e"]), [.set(1)])
    }

    /// 减费层跨舞动：鲨鱼在场时刀油压了两层（各用掉 1 张，`TAG_SCRIPT_DATA_NUM_1` = 1），舞动收回的
    /// 随从「本回合 1 费」被压到 0。底费按 1 算；层用完后费用回到 1，不是印刷费
    func testDiscountLayersAcrossBounceAround() {
        let t = Table(resources: 7, used: 5)
        t.enchant("BAR_552o", on: t.player, tags: [.tag_script_data_num_1: 1])
        t.enchant("BAR_552o", on: t.player, tags: [.tag_script_data_num_1: 1])
        let shark = t.add("TRL_092", zone: .hand, tags: [.cost: 0])
        t.enchant("ETC_079e", on: shark)
        let mother = t.add("CATA_111", zone: .hand, tags: [.cost: 0])
        t.enchant("ETC_079e", on: mother)
        let step = t.add("EX1_144", zone: .hand, tags: [.cost: 0])
        let etc = t.add("ETC_080", zone: .hand, tags: [.cost: 0])   // 4 − 4，没有「1 费」附魔
        let coin = t.add("CFM_630", zone: .hand, tags: [.cost: 0])
        let live = RDStateReader.read(t.snapshot())
        let s = live.state

        XCTAssertEqual(s.layers, [RDDiscountLayer(amount: 2, slots: 1, filter: .any),
                                  RDDiscountLayer(amount: 2, slots: 1, filter: .any)])
        XCTAssertEqual(s.mana, 2)
        for c in s.hand { XCTAssertEqual(s.cost(of: c, as: c.card), 0, "\(c.card) 现在是 0 费") }
        XCTAssertEqual(Set(live.inferredBaseCostEntities), [shark.id, mother.id, etc.id],
                       "被压到 0 的随从底费靠推断；暗影步、币印刷费就是 0，不算推断")

        // 先甩一张币把两层都吃掉：舞动收回的随从回到 1 费，E.T.C. 回到印刷费 4，暗影步仍是 0
        guard let after = try? RDEngine.apply(.play(entityId: coin.id, identity: .coin, target: .none,
                                                    choices: []), to: s) else {
            return XCTFail("币打不出去")
        }
        XCTAssertTrue(after.layers.isEmpty)
        func cost(_ e: Entity) -> Int? {
            return after.hand.first { $0.entityId == e.id }.map { after.cost(of: $0, as: $0.card) }
        }
        XCTAssertEqual(cost(shark), 1)
        XCTAssertEqual(cost(mother), 1)
        XCTAssertEqual(cost(step), 0)
        XCTAssertEqual(cost(etc), 4)
    }

    /// 伺机待发 / 狐人老千 / 骨刺的层：玩家附魔存在就是 1 槽；幸运彗星按附魔个数记次数
    func testPlayerEnchantmentsBecomeLayersAndComet() {
        let t = Table()
        t.enchant("EX1_145o", on: t.player)
        t.enchant("DMF_511e", on: t.player)
        t.enchant("REV_939e", on: t.player)
        t.enchant("BAR_552o", on: t.player, tags: [.tag_script_data_num_1: 2])   // 用完了，正要移除
        t.enchant("GDB_873e", on: t.player)
        let s = RDStateReader.read(t.snapshot()).state
        XCTAssertEqual(s.layers, [RDDiscountLayer(amount: 2, slots: 1, filter: .spell),
                                  RDDiscountLayer(amount: 2, slots: 1, filter: .comboCard),
                                  RDDiscountLayer(amount: 2, slots: 1, filter: .any)])
        XCTAssertEqual(s.luckyCometCharges, 1)
    }

    /// 手牌满：10 张，其中一张卡表没建模（只占格），一张是对局给的「幸运币」（按伪造的幸运币建模）
    func testFullHandAndUnmodeledCards() {
        let t = Table(resources: 3)
        t.add("CS2_029", zone: .hand)                           // 火球术：不在卡表
        let coin = t.add("TTN_COIN2", zone: .hand)
        coin[.coin_card] = 1
        for _ in 0..<8 { t.add("LOOT_214", zone: .hand) }
        let s = RDStateReader.read(t.snapshot(deck: ["TRL_092": 1])).state
        XCTAssertEqual(s.hand.count, 10)
        XCTAssertEqual(s.handSlotsFree, 0)
        XCTAssertEqual(s.hand[0].card, .junkPlaceholder)
        XCTAssertEqual(s.hand[0].unmodeledCardId, "CS2_029")
        XCTAssertEqual(s.hand[1].card, .coin)
        // 手满时缺件不成立（多抽的那张会被烧）
        var config = RedDragonConfig()
        config.maxStatesExpanded = 2_000
        let r = RedDragonSearch.solve(s, config: config)
        XCTAssertTrue(r.missingPieces.isEmpty)
    }

    /// 对方护甲 + 嘲讽：有效血量 = 血 − 已受伤害 + 护甲；嘲讽挡住随从打脸；潜行 / 休眠的敌方随从不进局面；
    /// 开局就带伤的敌方随从标「已受伤」（背刺判定）
    func testOpponentArmorTauntAndHiddenMinions() {
        let t = Table(resources: 0)
        t.opponentHero[.damage] = 5
        t.opponentHero[.armor] = 4
        let taunt = t.add("CS2_179", zone: .play, controller: RedDragonLiveTests.them,
                          tags: [.taunt: 1, .atk: 0, .health: 5, .damage: 1])
        t.add("EX1_010", zone: .play, controller: RedDragonLiveTests.them, tags: [.stealth: 1])
        t.add("CS2_172", zone: .play, controller: RedDragonLiveTests.them, tags: [.dormant: 1])
        let etc = t.add("ETC_080", zone: .play)
        let snap = t.snapshot()
        XCTAssertEqual(snap.opponentHeroHealth, 25)
        let s = RDStateReader.read(snap).state
        XCTAssertEqual(s.opponent.effectiveHealth, 29)
        XCTAssertEqual(s.opponent.board.map { $0.entityId }, [taunt.id])
        XCTAssertTrue(s.opponent.board[0].damaged)
        XCTAssertEqual(s.opponent.board[0].health, 4)

        let attacks = RDEngine.legalActions(s).filter { if case .attack = $0 { return true }; return false }
        XCTAssertFalse(attacks.isEmpty)
        for a in attacks {
            guard case .attack(_, let defender, _) = a else { continue }
            if defender == .enemyHero {
                XCTAssertThrowsError(try RDEngine.apply(a, to: s), "嘲讽在场，打脸不合法")
            }
        }
        XCTAssertNoThrow(try RDEngine.apply(.attack(attacker: .friendlyMinion(etc.id),
                                                    defender: .enemyMinion(taunt.id)), to: s))
    }

    /// 法力：水晶 − 已用 − 过载锁定，币的临时水晶单独一格（晦鳞复原不补它）
    func testManaAndTempMana() {
        let t = Table(resources: 5, used: 3)
        t.player[.overload_locked] = 1
        t.player[.temp_resources] = 2
        let s = RDStateReader.read(t.snapshot()).state
        XCTAssertEqual(s.maxMana, 5)
        XCTAssertEqual(s.mana, 1)
        XCTAssertEqual(s.tempMana, 2)
        XCTAssertEqual(s.availableMana, 3)
    }

    /// 边牌：E.T.C. 发现出来的那张（COPIED_FROM_ENTITY_ID 指回开局 SETASIDE 的乐队牌）从池里扣掉
    func testDiscoveredBandCardLeavesSideboard() {
        let t = Table()
        let original = t.add("LEG_CS3_031", zone: .setaside)
        t.add("ETC_079", zone: .setaside)
        t.add("SCH_352", zone: .setaside)
        t.add("LEG_CS3_031", zone: .hand, tags: [.copied_from_entity_id: original.id])
        let s = RDStateReader.read(t.snapshot()).state
        XCTAssertEqual(s.sideboard, [.bounceAround, .potionOfIllusion])
    }

    /// 非本牌组不启用：套牌判据只看套牌本身
    func testDeckGate() {
        let deck = RedDragonLiveReplayTests.deckList.map { $0.0 }
        let band = [CardIds.Collectible.Neutral.ETCBandManager: RedDragonLiveReplayTests.band]
        XCTAssertTrue(RDDeckGate.isRedDragonDeck(cardIds: deck, sideboards: band))
        XCTAssertFalse(RDDeckGate.isRedDragonDeck(cardIds: deck, sideboards: [:]), "乐队里没有阿莱")
        XCTAssertFalse(RDDeckGate.isRedDragonDeck(cardIds: deck.filter { $0 != "ETC_080" }, sideboards: band))
        let thin = deck.filter { !["BAR_552", "TRL_092", "OG_291"].contains($0) }
        XCTAssertFalse(RDDeckGate.isRedDragonDeck(cardIds: thin, sideboards: band), "引擎件不到 3 张")
        XCTAssertFalse(RDDeckGate.isRedDragonDeck(cardIds: ["CS2_029", "EX1_010"], sideboards: [:]))
    }

    // MARK: - 展示模型

    /// 两张 1 费阿莱复制体、对方 16 血：两张都是必打；前两步落在手牌上的具体 entity；
    /// 打出第一张后重算，剩下那张重新编为第 1 步
    func testHandMarksAndRenumberingAfterAPlay() {
        let t = Table(resources: 2)
        t.opponentHero[.health] = 16
        let a = t.add("LEG_CS3_031", zone: .hand, tags: [.cost: 1, .atk: 1, .health: 1])
        t.enchant("SCH_352e", on: a)
        t.add("LOOT_214", zone: .hand)
        let b = t.add("LEG_CS3_031", zone: .hand, tags: [.cost: 1, .atk: 1, .health: 1])
        t.enchant("SCH_352e", on: b)
        let first = analyze(t.snapshot())
        XCTAssertTrue(first.isLethal)
        XCTAssertEqual(first.maxDamage, 16)
        XCTAssertEqual(first.margin, 0)
        XCTAssertEqual(Set(first.handMarks.map { $0.entityId }), [a.id, b.id])
        XCTAssertTrue(first.handMarks.allSatisfy { $0.role == .required })
        XCTAssertEqual(first.handMarks.first { $0.entityId == b.id }?.zonePosition, 3)
        XCTAssertEqual(first.steps.count, 2)
        XCTAssertEqual(first.steps.map { $0.kind }, [.playFromHand, .playFromHand])
        XCTAssertEqual(first.steps.map { $0.target }, [.enemyHero, .enemyHero])
        XCTAssertFalse(first.nextStepText.isEmpty)
        // 只有两张阿莱：模板五张全缺（5×6）+ 2 个动作 = 32 → 进阶（引擎现行打分，不是本任务改的）
        XCTAssertEqual(first.tier, .advanced)
        XCTAssertEqual(first.completeness, .complete)

        // 打出 a：a 上场，对方掉 8，手牌重排
        a[.zone] = Zone.play.rawValue
        a[.exhausted] = 1
        t.player[.resources_used] = 1
        t.player[.num_cards_played_this_turn] = 1
        t.player[.num_options_played_this_turn] = 1
        t.opponentHero[.damage] = 8
        b[.zone_position] = 2
        let second = analyze(t.snapshot())
        XCTAssertTrue(second.isLethal)
        XCTAssertEqual(second.steps.first?.index, 1)
        XCTAssertEqual(second.steps.first?.handEntityId, b.id)
        XCTAssertEqual(second.steps.first?.zonePosition, 2)
        XCTAssertEqual(second.actionsTaken, 1)
    }

    /// 场面目标落到具体随从：暗影步收回场上那条（预启动下的）阿莱，再打出它
    func testBoardTargetsResolveToRealEntities() throws {
        let t = Table(resources: 7)
        t.opponentHero[.health] = 8
        let alex = t.add("LEG_CS3_031", zone: .play, tags: [.atk: 1, .health: 1, .exhausted: 1])
        t.enchant("SCH_352e", on: alex)
        let step = t.add("EX1_144", zone: .hand)
        let r = analyze(t.snapshot())
        XCTAssertTrue(r.isLethal)
        XCTAssertEqual(r.steps.count, 2)
        guard r.steps.count == 2 else { return }
        XCTAssertEqual(r.steps[0].handEntityId, step.id)
        XCTAssertEqual(r.steps[0].target, .friendlyMinion(entityId: alex.id, cardId: "LEG_CS3_031"))
        XCTAssertEqual(r.boardMarks, [RDBoardMark(entityId: alex.id, isEnemy: false, stepIndex: 1, role: .target)])
        // 第二步打的是弹回来的那张：游戏里还是同一个实体，引擎里是新编号，不在「现在的手牌」里
        XCTAssertEqual(r.steps[1].kind, .playGenerated)
        XCTAssertEqual(r.steps[1].cardId, "LEG_CS3_031")
    }

    /// 不斩杀：给出最大伤害、缺件、「单回合不够」；搜索没走完但撞的是状态闸门，标 `.capped` 不标截断
    func testNotLethalReportsMissingPiecesAndCompleteness() {
        let t = Table(resources: 8)
        t.opponentHero[.health] = 8
        t.add("LEG_CS3_031", zone: .hand)   // 9 费，差一张币
        let snap = t.snapshot(deck: ["CFM_630": 1, "LOOT_214": 2])
        let live = RDStateReader.read(snap)
        let result = RedDragonSearch.solve(live.state)
        let a = RDHintBuilder.analyze(snapshot: snap, live: live, result: result, cardName: { $0 })
        XCTAssertFalse(a.isLethal)
        XCTAssertEqual(a.maxDamage, 1, "只有英雄技能的匕首能打 1")
        XCTAssertEqual(a.missingPieces, ["CFM_630"])
        XCTAssertTrue(result.exhaustive, "这么小的局面搜索没有裁剪")
        XCTAssertEqual(a.verdict, .provenNotLethal)
        XCTAssertTrue(a.singleTurnInsufficient)
        XCTAssertTrue(a.handMarks.isEmpty)
        XCTAssertNil(a.tier)
        XCTAssertNotEqual(a.completeness, .truncated)

        // 撞了状态闸门：只是「没搜到」，不能说「单回合不够」
        var capped = result
        capped.termination = .budgetExceeded
        capped.exhaustive = false
        let c = RDHintBuilder.analyze(snapshot: snap, live: live, result: capped, cardName: { $0 })
        XCTAssertEqual(c.completeness, .capped)
        XCTAssertEqual(c.verdict, .notFound)
        XCTAssertFalse(c.singleTurnInsufficient)
        capped.cpuBudgetHit = true
        XCTAssertEqual(RDHintBuilder.analyze(snapshot: snap, live: live, result: capped, cardName: { $0 })
            .completeness, .truncated)

        // 有手牌的底费是推断的：穷举了也不算证明
        var inferred = live
        inferred.inferredBaseCostEntities = [live.state.hand[0].entityId]
        let i = RDHintBuilder.analyze(snapshot: snap, live: inferred, result: result, cardName: { $0 })
        XCTAssertTrue(i.costsInferred)
        XCTAssertEqual(i.verdict, .notFound)
        XCTAssertFalse(i.singleTurnInsufficient)
    }

    /// 英雄冻结：快照读到 FROZEN，根局面不许英雄攻击；搜索里装上的武器也打不出去
    func testFrozenHeroCannotAttack() {
        let t = Table(resources: 3)
        t.opponentHero[.health] = 2
        t.entities.first { $0.id == 4 }?[.frozen] = 1
        t.add("DED_004", zone: .play, tags: [.atk: 2, .durability: 2])   // 装着的黑水弯刀
        t.add("CORE_EX1_145", zone: .hand)                               // 伺机待发，打不出伤害
        let snap = t.snapshot()
        XCTAssertTrue(snap.heroFrozen)
        let live = RDStateReader.read(snap)
        XCTAssertTrue(live.state.heroFrozen)
        let r = RedDragonSearch.solve(live.state)
        XCTAssertFalse(r.isLethal, "冻结的英雄挥不了武器")
        XCTAssertFalse(r.chosenLine?.actions.contains {
            if case .attack(.friendlyHero, _, _) = $0 { return true }
            return false
        } ?? false, "包括英雄技能中途装上的匕首")

        t.entities.first { $0.id == 4 }?[.frozen] = 0
        let thawed = RDStateReader.read(t.snapshot())
        XCTAssertFalse(thawed.state.heroFrozen)
        XCTAssertTrue(RedDragonSearch.solve(thawed.state).isLethal, "不冻结时 2 攻武器打 2 血斩杀")
    }

    /// 场面危险：对方下回合场攻 ≥ 我方血量 + 护甲 − 余量（T4：余量 3 → 5）
    func testBoardDanger() {
        XCTAssertEqual(RDHintBuilder.dangerMargin, 5)
        let t = Table()
        var snap = t.snapshot()
        snap.heroHealth = 10
        snap.heroArmor = 2
        snap.opponentBoardDamage = 6
        let live = RDStateReader.read(snap)
        let r = RedDragonSearch.solve(live.state)
        XCTAssertFalse(RDHintBuilder.analyze(snapshot: snap, live: live, result: r, cardName: { $0 }).boardDanger)
        snap.opponentBoardDamage = 7
        XCTAssertTrue(RDHintBuilder.analyze(snapshot: snap, live: live, result: r, cardName: { $0 }).boardDanger)
    }

    func testRevealPolicy() {
        // 不斩杀只有判定
        XCTAssertEqual(RDRevealPolicy.cap(isLethal: false, tier: nil), .verdict)
        XCTAssertEqual(RDRevealPolicy.effective(requested: .order, preference: .order, isLethal: false, tier: nil),
                       .verdict)
        // 偏好不是「顺序」时，基础线不许升到 L2（热键也不行）
        XCTAssertEqual(RDRevealPolicy.cap(isLethal: true, tier: .basic), .verdict)
        XCTAssertEqual(RDRevealPolicy.effective(requested: .order, preference: .verdict, isLethal: true, tier: .basic),
                       .verdict)
        // 只剩两档；以前存过「参与牌」（1）的设置读出来按判定
        XCTAssertEqual(RDRevealLevel.allCases, [.verdict, .order])
        XCTAssertNil(RDRevealLevel(rawValue: 1))
        // 偏好是「顺序」：任何难度的斩杀线都给顺序，线中途变成基础也不降档（10-05 用户定）
        XCTAssertEqual(RDRevealPolicy.cap(isLethal: true, tier: .basic, preference: .order), .order)
        for tier in [RDDifficulty.Tier.basic, .advanced, .hard] {
            XCTAssertEqual(RDRevealPolicy.effective(requested: nil, preference: .order, isLethal: true, tier: tier),
                           .order, "\(tier)")
        }
        // 用户按热键降下来仍听用户的；不斩杀仍只有判定
        XCTAssertEqual(RDRevealPolicy.effective(requested: .verdict, preference: .order, isLethal: true, tier: .basic),
                       .verdict)
        XCTAssertEqual(RDRevealPolicy.cap(isLethal: false, tier: nil, preference: .order), .verdict)
        // 进阶按偏好
        XCTAssertEqual(RDRevealPolicy.effective(requested: nil, preference: .verdict, isLethal: true, tier: .advanced),
                       .verdict)
        XCTAssertEqual(RDRevealPolicy.effective(requested: .order, preference: .verdict, isLethal: true,
                                                tier: .advanced), .order)
        // 只有难线：兜底引导默认开，但用户按热键降下来就听用户的
        XCTAssertEqual(RDRevealPolicy.effective(requested: nil, preference: .verdict, isLethal: true, tier: .hard),
                       .order)
        XCTAssertEqual(RDRevealPolicy.effective(requested: .verdict, preference: .verdict, isLethal: true, tier: .hard),
                       .verdict)
    }

    /// 判卷用的局面：`step` 是第几次出牌（手里少一张、对手掉血），`count` 是操作数
    private func quizSnap(turn: Int, count: Int, step: Int = 0, heroAttacks: Int = 0) -> RDGameSnapshot {
        var s = lethalSnapshot(health: 30 - step)
        s.turn = turn
        s.optionsPlayedThisTurn = count
        s.cardsPlayedThisTurn = step
        s.heroAttacksThisTurn = heroAttacks
        return s
    }

    /// 出牌：计数先涨、场面后变（日志口径），完成后才判
    private func play(_ q: RDQuizState?, turn: Int, to n: Int, verdict: RDLethalVerdict) -> RDQuizState {
        var r = RDQuizState.next(q, snapshot: quizSnap(turn: turn, count: n, step: n - 1), verdict: .lethal)
        XCTAssertEqual(r.lastActions, n - 1, "计数先涨、牌还没打：不判")
        r = RDQuizState.next(r, snapshot: quizSnap(turn: turn, count: n, step: n), verdict: verdict)
        XCTAssertEqual(r.lastActions, n)
        return r
    }

    func testQuizMarks() {
        var q = RDQuizState.next(nil, snapshot: quizSnap(turn: 9, count: 0), verdict: .lethal)
        XCTAssertNil(q.mark)
        q = RDQuizState.next(q, snapshot: quizSnap(turn: 9, count: 0), verdict: .lethal)
        XCTAssertNil(q.mark, "同一局面重算不判卷")
        q = play(q, turn: 9, to: 1, verdict: .lethal)
        XCTAssertEqual(q.mark, .onLine)
        q = play(q, turn: 9, to: 2, verdict: .provenNotLethal)
        XCTAssertEqual(q.mark, .offLine, "之前确定能斩、现在证明不能")
        q = play(q, turn: 9, to: 3, verdict: .provenNotLethal)
        XCTAssertEqual(q.mark, .offLine, "已经打错，之后仍证明不能斩就一直是红")
        q = play(q, turn: 9, to: 4, verdict: .notFound)
        XCTAssertNil(q.mark, "没证明的结论把红清掉、不判")
        q = RDQuizState.next(q, snapshot: quizSnap(turn: 11, count: 0), verdict: .provenNotLethal)
        XCTAssertNil(q.mark, "新回合清零")
        q = play(q, turn: 11, to: 1, verdict: .provenNotLethal)
        XCTAssertNil(q.mark, "一开始就不能斩，打牌不判")
    }

    /// 没证明的「不能斩」不判红：撞上限 / 费用推断（`.notFound`）、要靠抽牌（`.lethalIfDraw`）
    func testQuizNeverMarksWrongWithoutProof() {
        var q = RDQuizState.next(nil, snapshot: quizSnap(turn: 5, count: 0), verdict: .lethal)
        q = play(q, turn: 5, to: 1, verdict: .notFound)
        XCTAssertNil(q.mark, "没搜到 ≠ 打错")
        q = RDQuizState.next(nil, snapshot: quizSnap(turn: 5, count: 0), verdict: .lethal)
        q = play(q, turn: 5, to: 1, verdict: .lethalIfDraw)
        XCTAssertNil(q.mark, "只剩靠抽牌的线，不判")
        q = RDQuizState.next(nil, snapshot: quizSnap(turn: 5, count: 0), verdict: .lethalIfDraw)
        q = play(q, turn: 5, to: 1, verdict: .provenNotLethal)
        XCTAssertNil(q.mark, "原本就要靠抽牌：抽空了不算打错")
    }

    /// T2b 第四轮 P1：攻击的计数在攻击结算**之后**才涨（g2 第 4078、5824 行）。攻击完、计数没涨的那份局面
    /// 不能覆盖「操作之前」的结论；计数涨了（只差计数）才算这一步完成，用操作之前的结论判
    func testQuizPairsAttackWithLateOptionCount() {
        var q = RDQuizState.next(nil, snapshot: quizSnap(turn: 7, count: 0), verdict: .lethal)
        var attacked = quizSnap(turn: 7, count: 0, heroAttacks: 1)
        attacked.opponentHeroHealth -= 1
        q = RDQuizState.next(q, snapshot: attacked, verdict: .provenNotLethal)
        XCTAssertTrue(q.pending, "攻击开始了、计数没涨")
        XCTAssertEqual(q.baseline, .lethal, "操作之前的结论不被进行中的局面覆盖")
        XCTAssertNil(q.mark)
        // 死亡结算等后续块（计数仍没涨）：照样等
        q = RDQuizState.next(q, snapshot: attacked, verdict: .provenNotLethal)
        XCTAssertTrue(q.pending)
        // 只差计数的那份：这一步完成
        var done = attacked
        done.optionsPlayedThisTurn = 1
        q = RDQuizState.next(q, snapshot: done, verdict: .provenNotLethal)
        XCTAssertFalse(q.pending)
        XCTAssertEqual(q.lastActions, 1)
        XCTAssertEqual(q.mark, .offLine, "能斩时打错了一下，判红，不是绿")

        // 出牌后的死亡结算（计数不涨、没有新操作）：同一步的后续，用同一个「操作之前」重判
        var r = RDQuizState.next(nil, snapshot: quizSnap(turn: 3, count: 0), verdict: .lethal)
        r = play(r, turn: 3, to: 1, verdict: .notFound)
        XCTAssertNil(r.mark)
        var settled = quizSnap(turn: 3, count: 1, step: 1)
        settled.opponentBoard = []
        settled.heroHealth -= 1
        r = RDQuizState.next(r, snapshot: settled, verdict: .provenNotLethal)
        XCTAssertFalse(r.pending)
        XCTAssertEqual(r.mark, .offLine, "结算完证明不能斩，按出牌之前的「能斩」判红")
    }

    /// 场上有一只自己的狐（能攻击）的局面
    private func boardQuizSnap(turn: Int, count: Int) -> RDGameSnapshot {
        let t = Table(resources: 1, turn: turn)
        t.opponentHero[.health] = 8
        let a = t.add("LEG_CS3_031", zone: .hand, tags: [.cost: 1, .atk: 1, .health: 1])
        t.enchant("SCH_352e", on: a)
        t.add("CORE_DMF_511", zone: .play)
        t.add("CS2_231", zone: .play, controller: RedDragonLiveTests.them)
        t.player[.num_options_played_this_turn] = count
        return t.snapshot()
    }

    /// T2b 第五轮 P1（Codex 复现）：攻击随从撞死。死亡后的局面里攻击者已不在场，原来按「仍在场随从的攻击次数」
    /// 认不出攻击，死亡局面被当成新的「操作之前」；计数涨 1 又因只差计数被当成出牌开始而跳过，应判红却不判。
    /// 现在认玩家实体的 `NUM_FRIENDLY_MINIONS_THAT_ATTACKED_THIS_TURN`（撞死也不回退）
    func testQuizAttackerDiesBeforeLateCount() {
        let before = boardQuizSnap(turn: 7, count: 0)
        XCTAssertEqual(before.board.count, 1)
        XCTAssertEqual(before.minionsAttackedThisTurn, 0)
        var q = RDQuizState.next(nil, snapshot: before, verdict: .lethal)
        // 上一步判了绿（出牌完成）
        q.lastOp = RDQuizOp(before: .lethal, markBefore: nil)
        q.mark = .onLine
        // 狐撞死在对面随从上：死亡结算后的局面先算完（攻击者离场、计数没涨）
        var dead = before
        dead.board = []
        dead.opponentBoard = []
        dead.minionsAttackedThisTurn = 1
        q = RDQuizState.next(q, snapshot: dead, verdict: .provenNotLethal)
        XCTAssertTrue(q.pending, "攻击者不在场了也认得出攻击已开始")
        XCTAssertEqual(q.baseline, .lethal, "攻击前的「能斩」没被死亡局面覆盖")
        XCTAssertEqual(q.lastActions, 0)
        // 计数后到
        var done = dead
        done.optionsPlayedThisTurn = 1
        q = RDQuizState.next(q, snapshot: done, verdict: .provenNotLethal)
        XCTAssertFalse(q.pending)
        XCTAssertEqual(q.lastActions, 1)
        XCTAssertEqual(q.mark, .offLine)

        // 快照读的就是玩家实体那个 tag
        let t = Table()
        t.player[.num_friendly_minions_that_attacked_this_turn] = 2
        XCTAssertEqual(t.snapshot().minionsAttackedThisTurn, 2)
    }

    /// 非操作的场面变化（回合开始的效果移走随从、亡语清场）不动操作计数器 → 不进 pending，当作同一局面的后续
    func testQuizNonOperationBoardChangeIsNotPending() {
        let start = boardQuizSnap(turn: 5, count: 0)
        var q = RDQuizState.next(nil, snapshot: start, verdict: .lethal)
        var removed = start
        removed.board = []
        removed.hand.removeAll()
        q = RDQuizState.next(q, snapshot: removed, verdict: .provenNotLethal)
        XCTAssertFalse(q.pending)
        XCTAssertEqual(q.baseline, .provenNotLethal, "回合开始的变化更新「操作之前」")
        XCTAssertNil(q.mark)
    }

    /// pending 不会卡死整回合：计数一直不涨、下一个操作先开始（计数器又涨了）→ 用 pending 期间最后一份局面
    /// 把上一步判完、进入新的 pending；计数器倒退 → 解除；换回合 → 清零
    func testQuizPendingReleases() {
        let start = quizSnap(turn: 9, count: 0)
        var q = RDQuizState.next(nil, snapshot: start, verdict: .lethal)
        var hit = quizSnap(turn: 9, count: 0, heroAttacks: 1)
        hit.opponentHeroHealth -= 1
        q = RDQuizState.next(q, snapshot: hit, verdict: .provenNotLethal)
        XCTAssertTrue(q.pending)
        // 计数没涨，又一只随从开始攻击
        var second = hit
        second.minionsAttackedThisTurn = 1
        second.opponentHeroHealth -= 3
        q = RDQuizState.next(q, snapshot: second, verdict: .provenNotLethal)
        XCTAssertEqual(q.mark, .offLine, "上一步按 pending 期间最后一份（英雄攻击后）判完")
        XCTAssertEqual(q.settled, hit)
        XCTAssertEqual(q.baseline, .provenNotLethal)
        XCTAssertTrue(q.pending, "第二个攻击进入 pending")
        XCTAssertEqual(q.pendingOp?.counters, RDOpCounters(second))

        // 计数器倒退（不该发生）：解除
        q = RDQuizState.next(q, snapshot: start, verdict: .lethal)
        XCTAssertFalse(q.pending)
        XCTAssertEqual(q.settled, start)

        // 换回合：清零
        q = RDQuizState.next(q, snapshot: hit, verdict: .provenNotLethal)
        XCTAssertTrue(q.pending)
        q = RDQuizState.next(q, snapshot: quizSnap(turn: 11, count: 0), verdict: .lethal)
        XCTAssertFalse(q.pending)
        XCTAssertNil(q.mark)
    }

    /// 同一件事走 Assistant 全程（投递 → 主线程 → 后台算 → 提交）：攻击结算后的局面（旧计数）算完不判卷，
    /// 只差计数的那份投下来不重算，直接拿现有结论判红
    func testAssistantJudgesAttackWhenLateCountArrives() {
        let sw = Switch()
        let assistant = makeAssistant(sw, quiz: true)
        func feed(_ s: RDGameSnapshot) { DispatchQueue.global().sync { assistant.feed(.snapshot(s)) } }
        var s0 = lethalSnapshot(health: 8)
        s0.optionsPlayedThisTurn = 0
        feed(s0)
        spin { assistant.hint.phase == .ready }
        XCTAssertEqual(assistant.hint.analysis?.verdict, .lethal)
        // 上一步：出牌（计数先涨，再变场面），仍能斩 → 绿
        var c1 = s0
        c1.optionsPlayedThisTurn = 1
        feed(c1)
        var s1 = c1
        s1.opponentHeroHealth = 7
        s1.cardsPlayedThisTurn = 1
        feed(s1)
        spin { assistant.hint.phase == .ready && assistant.hint.analysis?.effectiveEnemyHealth == 7 }
        XCTAssertEqual(assistant.hint.quiz, .onLine)
        // 攻击：结算后（计数还是 1）证明不能斩
        var s2 = s1
        s2.heroAttacksThisTurn = 1
        s2.opponentHeroHealth = 99
        feed(s2)
        spin { assistant.hint.phase == .ready && assistant.hint.analysis?.effectiveEnemyHealth == 99 }
        XCTAssertEqual(assistant.hint.analysis?.verdict, .provenNotLethal)
        XCTAssertNotEqual(assistant.hint.quiz, .offLine, "计数还没涨，这一步还没完成")
        let scheduled = assistant.scheduledComputations
        // 计数晚到
        var s3 = s2
        s3.optionsPlayedThisTurn = 2
        feed(s3)
        spin { assistant.hint.quiz == .offLine }
        XCTAssertEqual(assistant.hint.quiz, .offLine, "攻击之前能斩、之后证明不能斩：红")
        XCTAssertEqual(assistant.hint.analysis?.actionsTaken, 2)
        XCTAssertEqual(assistant.scheduledComputations, scheduled, "只差计数，不重算")
    }

    /// 锁定模式下，上一份局面还在核对时只差计数的那份紧跟着到（10-06 14:47 实测：英雄攻击 → 随从死亡 → 计数）：
    /// 不能走「只更新计数」的捷径——那会丢掉在算的那次又不重排，面板停在「重算中」
    func testLateCountDuringLockedCheckStillRecomputes() {
        let sw = Switch()
        let assistant = makeAssistant(sw, reveal: .order)
        func feed(_ s: RDGameSnapshot) { DispatchQueue.global().sync { assistant.feed(.snapshot(s)) } }
        let s0 = lethalSnapshot(health: 8)
        feed(s0)
        spin { assistant.hint.phase == .ready }
        XCTAssertTrue(assistant.hint.locked)
        // 局面变了（锁定的线接不上）、计数还没涨；紧接着只差计数的那份
        var s1 = s0
        s1.opponentHeroHealth = 7
        var s2 = s1
        s2.optionsPlayedThisTurn += 1
        feed(s1)
        feed(s2)
        spin(until: { assistant.hint.phase == .ready && assistant.hint.analysis?.effectiveEnemyHealth == 7 }, timeout: 5)
        XCTAssertEqual(assistant.hint.phase, .ready, "重算要出结果，不能停在「重算中」")
        XCTAssertEqual(assistant.hint.analysis?.effectiveEnemyHealth, 7)
        XCTAssertFalse(assistant.hint.deviated)
        XCTAssertEqual(assistant.hint.analysis?.actionsTaken, s2.optionsPlayedThisTurn)
    }

    /// 操作数只增不减：计数倒退（不该发生）不重判
    func testQuizActionsAreMonotonic() {
        var q = RDQuizState.next(nil, snapshot: quizSnap(turn: 7, count: 2, step: 2), verdict: .lethal)
        q = play(q, turn: 7, to: 3, verdict: .lethal)
        XCTAssertEqual(q.mark, .onLine)
        var back = quizSnap(turn: 7, count: 1, step: 3, heroAttacks: 1)
        back.opponentHeroHealth -= 1
        q = RDQuizState.next(q, snapshot: back, verdict: .provenNotLethal)
        XCTAssertEqual(q.mark, .onLine, "计数倒退不判卷")
        XCTAssertEqual(q.lastActions, 3)

        // 快照里的操作数来自 NUM_OPTIONS_PLAYED_THIS_TURN，和场面无关
        let t = Table()
        t.player[.num_options_played_this_turn] = 4
        let snap = t.snapshot()
        XCTAssertEqual(snap.optionsPlayedThisTurn, 4)
        XCTAssertEqual(analyze(snap).actionsTaken, 4)

        // 只有操作数变了（计数先于那一步的 BLOCK 加 1）不算新局面
        var bumped = snap
        bumped.optionsPlayedThisTurn = 5
        XCTAssertTrue(RedDragonAssistant.onlyOptionCountChanged(.snapshot(bumped), .snapshot(snap)))
        bumped.heroHealth -= 1
        XCTAssertFalse(RedDragonAssistant.onlyOptionCountChanged(.snapshot(bumped), .snapshot(snap)))
    }

    private func analyze(_ snap: RDGameSnapshot) -> RDAnalysis {
        let live = RDStateReader.read(snap)
        let result = RedDragonSearch.solve(live.state)
        return RDHintBuilder.analyze(snapshot: snap, live: live, result: result, cardName: { $0 })
    }

    // MARK: - 开关热切换

    private final class Switch {
        var enabled = true
    }

    private func makeAssistant(_ sw: Switch, debounce: TimeInterval = 0, quiz: Bool = false,
                               reveal: RDRevealLevel = .verdict) -> RedDragonAssistant {
        let env = RedDragonAssistant.Environment(
            isEnabled: { sw.enabled },
            revealPreference: { reveal },
            quizMode: { quiz },
            debounce: debounce,
            config: RedDragonConfig(),
            cardName: { $0 })
        return RedDragonAssistant(environment: env, recordsFeeds: true)
    }

    private func lethalSnapshot(health: Int = 8) -> RDGameSnapshot {
        let t = Table(resources: 1)
        t.opponentHero[.health] = health
        let a = t.add("LEG_CS3_031", zone: .hand, tags: [.cost: 1, .atk: 1, .health: 1])
        t.enchant("SCH_352e", on: a)
        return t.snapshot()
    }

    private func spin(until condition: () -> Bool, timeout: TimeInterval = 10) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
    }

    /// 开 → 有结果；关 → 结果立即清空，之后的局面不再调度计算；再开 → 下一个局面照常算
    func testHotSwitch() {
        let sw = Switch()
        let assistant = makeAssistant(sw)
        var published: [RedDragonHint.Phase] = []
        assistant.onChange = { published.append($0.phase) }

        assistant.submit(.snapshot(lethalSnapshot()))
        XCTAssertEqual(assistant.hint.phase, .computing)
        spin { assistant.hint.phase == .ready }
        XCTAssertEqual(assistant.hint.phase, .ready)
        XCTAssertEqual(assistant.hint.analysis?.isLethal, true)
        XCTAssertEqual(assistant.hint.analysis?.maxDamage, 8)
        XCTAssertFalse(assistant.hint.isStale)
        XCTAssertEqual(assistant.scheduledComputations, 1)
        XCTAssertEqual(published, [.computing, .ready])

        // 同一局面再来一次（记牌器刷新常有与红龙无关的变化）：不重算
        assistant.submit(.snapshot(lethalSnapshot()))
        XCTAssertEqual(assistant.scheduledComputations, 1)

        sw.enabled = false
        assistant.settingsDidChange()
        XCTAssertEqual(assistant.hint, .inactive, "关掉立即清空")
        assistant.submit(.snapshot(lethalSnapshot(health: 7)))
        spin(until: { false }, timeout: 0.3)
        XCTAssertEqual(assistant.scheduledComputations, 1, "关着时不再调度计算")
        XCTAssertEqual(assistant.hint, .inactive)

        sw.enabled = true
        assistant.settingsDidChange()
        assistant.submit(.snapshot(lethalSnapshot(health: 7)))
        spin { assistant.hint.phase == .ready }
        XCTAssertEqual(assistant.hint.analysis?.effectiveEnemyHealth, 7)
        XCTAssertEqual(assistant.scheduledComputations, 2)
    }

    /// 走真实的设置链：改 mod 设置的开关（`ModSettingsStore`）→ 主线程观察者 → 开关缓存。
    /// 关着时挂点（`feed`）直接丢，不投 main.async
    func testHotSwitchThroughSettingsNotifications() {
                RDTestSettings.assist = true
        let env = RedDragonAssistant.Environment(
            isEnabled: { RDTestSettings.assist }, revealPreference: { .verdict }, quizMode: { false },
            debounce: 0, config: RedDragonConfig(), cardName: { $0 })
        let assistant = RedDragonAssistant(environment: env, settings: RDTestSettings.store, recordsFeeds: true)

        assistant.feed(.snapshot(lethalSnapshot()))
        spin { assistant.hint.phase == .ready }
        XCTAssertEqual(assistant.hint.analysis?.isLethal, true)

        RDTestSettings.assist = false
        spin { assistant.hint == .inactive }
        XCTAssertEqual(assistant.hint, .inactive, "通知到了就清空")
        assistant.feed(.snapshot(lethalSnapshot(health: 7)))
        spin(until: { false }, timeout: 0.3)
        XCTAssertEqual(assistant.fedInputs.count, 1, "关着时挂点不投递")
        XCTAssertEqual(assistant.scheduledComputations, 1)

        RDTestSettings.assist = true
        spin(until: { false }, timeout: 0.1)
        assistant.feed(.snapshot(lethalSnapshot(health: 7)))
        spin { assistant.hint.phase == .ready && assistant.hint.analysis?.effectiveEnemyHealth == 7 }
        XCTAssertEqual(assistant.hint.analysis?.effectiveEnemyHealth, 7)
        XCTAssertEqual(assistant.fedInputs.count, 2)
    }

    /// 非本牌组 / 不在对局：输入一直是 `.inactive`，挂点一次都不投 main.async；相同局面也不重投
    func testNoMainAsyncForInactiveOrUnchangedInput() {
        let sw = Switch()
        let assistant = makeAssistant(sw)
        for _ in 0..<5 { assistant.feed(.inactive) }
        XCTAssertTrue(assistant.fedInputs.isEmpty)
        let snap = lethalSnapshot()
        assistant.feed(.snapshot(snap))
        assistant.feed(.snapshot(snap))
        XCTAssertEqual(assistant.fedInputs.count, 1)
        spin { assistant.hint.phase == .ready }
    }

    /// 解析线程已经拷出新局面、主线程还没收到时，旧局面的结果不上屏（核对局面版本）。
    /// 主线程睡着时 A 算完、把提交排进主队列，然后才投 B：A 的提交先跑，代号还是最新的，只能靠版本挡住
    func testResultForOlderParsedVersionIsDiscarded() {
        let sw = Switch()
        let assistant = makeAssistant(sw, debounce: 0.05)
        assistant.feed(.snapshot(lethalSnapshot(health: 8)))
        spin { assistant.hint.phase == .computing }
        XCTAssertEqual(assistant.hint.phase, .computing)
        Thread.sleep(forTimeInterval: 1.0)   // A 在后台算完，提交排进主队列
        DispatchQueue.global().sync {
            // 解析线程拷出 B（版本 +1），B 的 submit 排在 A 的提交后面
            assistant.feed(.snapshot(lethalSnapshot(health: 9)))
        }
        spin { assistant.hint.phase == .ready && assistant.hint.analysis?.effectiveEnemyHealth == 9 }
        XCTAssertEqual(assistant.discardedComputations, 1, "A 的结果因版本过时被丢")
        XCTAssertEqual(assistant.committedComputations, 1, "只有 B 上屏")
        XCTAssertEqual(assistant.hint.analysis?.effectiveEnemyHealth, 9)
    }

    /// T2b 第三轮 P1：A 在算时，下一批日志在 BLOCK 开着时改了实体（`idle == false`，还不能拷）。
    /// 那一刻就要作废 A、把屏上的结果标过时；A 算完也不能以「最新」上屏。到一致边界再拷：
    /// 这一段没改到相关实体、拷出来和 A 一样，也要重算一次再上屏
    func testOpenBlockLinesInvalidateInFlightResult() {
        let sw = Switch()
        let assistant = makeAssistant(sw, debounce: 0.05)
        let game = Game(hearthstoneRunState: HearthstoneRunState(isRunning: false, isActive: false))
        // 先有一个上屏的结果 R
        DispatchQueue.global().sync { assistant.feed(.snapshot(lethalSnapshot(health: 9))) }
        spin { assistant.hint.phase == .ready }
        XCTAssertEqual(assistant.committedComputations, 1)

        // A 开始算；主线程睡着，A 在后台算完、提交排进主队列
        DispatchQueue.global().sync { assistant.feed(.snapshot(lethalSnapshot(health: 8))) }
        spin { assistant.hint.phase == .computing }
        Thread.sleep(forTimeInterval: 1.0)
        // 解析线程：这一批有新行，BLOCK 还开着
        DispatchQueue.global().sync {
            assistant.parserBatchDidEnd(game, linesProcessed: true, idle: false)
            // 同一段里再来一批（仍开着）不重复作废
            assistant.parserBatchDidEnd(game, linesProcessed: true, idle: false)
        }
        spin(until: { false }, timeout: 0.5)
        XCTAssertEqual(assistant.discardedComputations, 1, "A 的结果因局面已作废被丢")
        XCTAssertEqual(assistant.committedComputations, 1, "A 没有上屏")
        XCTAssertEqual(assistant.hint.phase, .computing, "等一致边界，不显示「已算好」")
        XCTAssertTrue(assistant.hint.isStale, "屏上还是 R，标成过时")
        XCTAssertEqual(assistant.hint.analysis?.effectiveEnemyHealth, 9)

        // 一致边界：拷出来和 A 一模一样（这段日志没改到相关实体）→ 仍要重算后上屏
        DispatchQueue.global().sync { assistant.feed(.snapshot(lethalSnapshot(health: 8))) }
        spin { assistant.hint.phase == .ready }
        XCTAssertEqual(assistant.committedComputations, 2)
        XCTAssertFalse(assistant.hint.isStale)
        XCTAssertEqual(assistant.hint.analysis?.effectiveEnemyHealth, 8)
        XCTAssertEqual(assistant.fedInputs.count, 3, "R、A、边界上的 A")

        // 上次投递的不是局面（对方回合）时，BLOCK 开着来新行不投任何东西
        DispatchQueue.global().sync { assistant.feed(.opponentTurn) }
        spin { assistant.hint.phase == .opponentTurn }
        let before = assistant.discardedComputations
        DispatchQueue.global().sync { assistant.parserBatchDidEnd(game, linesProcessed: true, idle: false) }
        spin(until: { false }, timeout: 0.3)
        XCTAssertEqual(assistant.hint.phase, .opponentTurn)
        XCTAssertEqual(assistant.discardedComputations, before)
    }

    /// 算到一半关掉：结果不上屏
    func testSwitchOffDropsInFlightResult() {
        let sw = Switch()
        let assistant = makeAssistant(sw, debounce: 0.2)
        assistant.submit(.snapshot(lethalSnapshot()))
        sw.enabled = false
        assistant.settingsDidChange()
        spin(until: { false }, timeout: 0.6)
        XCTAssertEqual(assistant.hint, .inactive)
        XCTAssertEqual(assistant.committedComputations, 0)
    }

    /// 去抖 + 过时结果不上屏：连续两个局面只上屏后一个；中间标「正在算」且旧结果标过时
    func testDebounceAndStaleResults() {
        let sw = Switch()
        let assistant = makeAssistant(sw, debounce: 0.15)
        assistant.submit(.snapshot(lethalSnapshot(health: 8)))
        assistant.submit(.snapshot(lethalSnapshot(health: 9)))
        spin { assistant.hint.phase == .ready }
        XCTAssertEqual(assistant.committedComputations, 1)
        XCTAssertEqual(assistant.hint.analysis?.effectiveEnemyHealth, 9)
        XCTAssertEqual(assistant.hint.analysis?.isLethal, false)

        assistant.submit(.snapshot(lethalSnapshot(health: 8)))
        XCTAssertEqual(assistant.hint.phase, .computing)
        XCTAssertTrue(assistant.hint.isStale, "旧结论还在，但标成过时")
        spin { assistant.hint.phase == .ready }
        XCTAssertEqual(assistant.hint.analysis?.isLethal, true)

        assistant.submit(.opponentTurn)
        XCTAssertEqual(assistant.hint.phase, .opponentTurn)
        XCTAssertNil(assistant.hint.analysis)
    }

    /// 揭示档热键：进阶线能升到 L2；基础线停在判定（临时放宽基础阈值造一条基础线）
    func testRevealHotkeysRespectCap() {
        let sw = Switch()
        let assistant = makeAssistant(sw)
        assistant.submit(.snapshot(lethalSnapshot()))
        spin { assistant.hint.phase == .ready }
        XCTAssertEqual(assistant.hint.analysis?.tier, .advanced)
        XCTAssertEqual(assistant.hint.revealLevel, .verdict)
        assistant.raiseReveal()
        assistant.raiseReveal()
        assistant.raiseReveal()
        XCTAssertEqual(assistant.hint.revealLevel, .order)
        XCTAssertEqual(assistant.hint.maxRevealLevel, .order)

        let saved = RDDifficulty.basicThreshold
        RDDifficulty.basicThreshold = 40
        defer { RDDifficulty.basicThreshold = saved }
        assistant.submit(.opponentTurn)
        assistant.submit(.snapshot(lethalSnapshot(health: 7)))
        spin { assistant.hint.phase == .ready }
        XCTAssertEqual(assistant.hint.analysis?.tier, .basic)
        XCTAssertEqual(assistant.hint.revealLevel, .verdict)
        assistant.raiseReveal()
        XCTAssertEqual(assistant.hint.revealLevel, .verdict, "基础线不许升到 L2")
        XCTAssertEqual(assistant.hint.maxRevealLevel, .verdict)
        assistant.lowerReveal()
        XCTAssertEqual(assistant.hint.revealLevel, .verdict)
    }

    // MARK: - 破冰模式（T8 阶段 B）：按键开关、自动关、跟手、偏离

    private static let matchA = Date(timeIntervalSince1970: 1_760_000_000)
    private static let matchB = Date(timeIntervalSince1970: 1_760_003_600)

    /// 对方 16 血、挂着一个奥秘；我方 3 费、「伺机待发」生效中（下一张法术 −2），鲨鱼之灵在场，手里一张 1 费的
    /// 阿莱复制体和幻觉药水。破冰线只有一种写法（阶段 A `testBreakThenLethalNextTurn` 的局面，临时水晶换成伺机待发）：
    /// 阿莱打脸（鲨鱼让战吼打两次：16 → 8，第二下致命 → 冰碎，剩 8）→ 喝药水（鲨鱼、阿莱各进手一张 1 费复制体），
    /// 下回合 4 费下 1 费阿莱 16 ≥ 8。只破冰不喝药水的话下回合 4 费只够喝药水，斩不了。
    /// `stage`：0 = 还没动；1 = 阿莱打完；2 = 药水也喝了。实体编号各阶段不变（阿莱上场还是手里那个号）。
    /// `iceBlock`（阶段 ≥ 1）：那个奥秘是寒冰屏障（致命的那下被免、对方免疫）；不是的话当它是别的奥秘
    /// （第二下之前对方叠了甲：剩 8 血，没有免疫）—— 两种情形奥秘都没了。
    /// `potion: false`（只有阶段 0 / 1）：手里不是药水而是第二张 1 费阿莱复制体，也没有伺机待发，**对方 9 血** ——
    /// 破冰线只有阿莱打脸一步（第一个 8 照扣剩 1，第二个 8 触发，剩 1：已经压到最低，先按英雄技能垫一下也还是剩 1、
    /// 白多一步；下回合另一张阿莱 16 ≥ 1），打完还剩 2 费。
    /// （对方要是 16 血，口径 11 之下线会变成「英雄技能 → 匕首攻脸 → 阿莱」剩 7，费用用光，就没有「线走完还能动」了）
    private func iceSnapshot(stage: Int = 0, iceBlock: Bool = true, potion: Bool = true) -> RDGameSnapshot {
        let t = Table(resources: 3, used: [0, 1, 3][stage])
        let health = potion ? 16 : 9
        t.opponentHero[.health] = health
        t.add("TRL_092", zone: .play, tags: [.exhausted: 1])
        let alex = t.add("LEG_CS3_031", zone: stage == 0 ? .hand : .play,
                         tags: stage == 0 ? [.cost: 1, .atk: 1, .health: 1] : [.atk: 1, .health: 1, .exhausted: 1])
        t.enchant("SCH_352e", on: alex)
        t.enchant("SCH_352e2", on: alex)
        if !potion {
            precondition(stage < 2)
            let second = t.add("LEG_CS3_031", zone: .hand, tags: [.cost: 1, .atk: 1, .health: 1])
            t.enchant("SCH_352e", on: second)
            t.enchant("SCH_352e2", on: second)
        } else if stage < 2 {
            t.add(Self.id(.potionOfIllusion), zone: .hand, tags: [.cost: 2])
            t.enchant("EX1_145o", on: t.player)
        } else {
            t.add(Self.id(.potionOfIllusion), zone: .graveyard, tags: [.cost: 2])
            t.nextId += 1
            for id in ["TRL_092", "LEG_CS3_031"] {
                let copy = t.add(id, zone: .hand, tags: [.cost: 1, .atk: 1, .health: 1])
                t.enchant("SCH_352e", on: copy)
                t.enchant("SCH_352e2", on: copy)
            }
        }
        var snap = t.snapshot()
        snap.match = Self.matchA
        snap.cardsPlayedThisTurn = stage
        snap.optionsPlayedThisTurn = stage
        snap.opponentSecretCount = stage == 0 ? 1 : 0
        if stage > 0 {
            // 阿莱的第一个 8 照扣，第二个 8 被挡
            snap.opponentHeroHealth = health - 8
            snap.opponentHeroImmune = iceBlock
        }
        return snap
    }

    /// 线上没有的一步：按了英雄技能
    private func afterHeroPower(_ s: RDGameSnapshot) -> RDGameSnapshot {
        var n = s
        n.heroPowerExhausted = true
        n.weapon = RDGameSnapshot.Weapon(cardId: "CS2_082", attack: 1, durability: 2)
        n.resourcesUsed += 2
        n.optionsPlayedThisTurn += 1
        return n
    }

    private func iceTokens(_ assistant: RedDragonAssistant) -> [String]? {
        return assistant.hint.analysis?.ice?.formula?.tokens.map { RDText.formulaToken($0) }
    }

    /// 喂一份局面（走解析线程的入口）、等斩杀判定上屏、点开破冰、等破冰结论上屏
    private func turnIceOn(_ assistant: RedDragonAssistant, _ s: RDGameSnapshot,
                           file: StaticString = #filePath, line: UInt = #line) {
        DispatchQueue.global().sync { assistant.feed(.snapshot(s)) }
        spin { assistant.hint.phase == .ready && assistant.hint.analysis?.opponentHasSecrets == true }
        assistant.toggleIceBreak()
        spin { assistant.hint.phase == .ready && assistant.hint.analysis?.ice != nil }
        XCTAssertTrue(assistant.iceMode, file: file, line: line)
        XCTAssertNotNil(assistant.hint.analysis?.ice, file: file, line: line)
    }

    /// 点按键（面板上的点击同步调到 `toggleIceBreak`）：模式当场翻转并发布（按键立刻换成开 / 关），不等下一条日志、
    /// 不去抖，立刻对当前局面重算；开 → 破冰口径的结论，关 → 回到斩杀判定。
    /// 对方没有奥秘时开不了（按键也不出现）；不在我方回合时不响应
    func testIceToggleRecomputesImmediately() {
        let sw = Switch()
        // 去抖设得很长：点按键的重算如果也去抖，下面的耗时过不了
        let assistant = makeAssistant(sw, debounce: 1.5)
        func feed(_ s: RDGameSnapshot) { DispatchQueue.global().sync { assistant.feed(.snapshot(s)) } }
        func button() -> Bool? { return RDOverlayModel.make(assistant.hint, cardName: { $0 }).badge?.iceButton }
        let s0 = iceSnapshot()
        feed(s0)
        spin { assistant.hint.phase == .ready }
        XCTAssertEqual(assistant.hint.analysis?.opponentHasSecrets, true)
        XCTAssertNil(assistant.hint.analysis?.ice)
        XCTAssertEqual(assistant.hint.analysis?.isLethal, true, "斩杀搜索不看奥秘：鲨鱼 + 阿莱 16 就「可斩」")
        XCTAssertFalse(assistant.hint.iceMode)
        XCTAssertEqual(button(), false, "对方有奥秘：按键在，关着")

        var published: [RedDragonHint] = []
        assistant.onChange = { published.append($0) }
        let scheduled = assistant.scheduledComputations
        let fed = assistant.fedInputs.count
        var start = CFAbsoluteTimeGetCurrent()
        assistant.toggleIceBreak()
        XCTAssertTrue(assistant.iceMode)
        XCTAssertEqual(published.first?.iceMode, true, "模式当场发布，按键不等结论")
        XCTAssertEqual(button(), true)
        XCTAssertEqual(assistant.scheduledComputations, scheduled + 1, "立刻重排计算")
        spin { assistant.hint.phase == .ready && assistant.hint.analysis?.ice != nil }
        let onCost = CFAbsoluteTimeGetCurrent() - start
        XCTAssertLessThan(onCost, 1.0, "不去抖（去抖是 1.5 秒）")
        XCTAssertEqual(assistant.fedInputs.count, fed, "没有新局面进来：不等下一条日志")
        let ice = assistant.hint.analysis?.ice
        XCTAssertEqual(ice?.kind, .lethalNextTurn)
        XCTAssertEqual(iceTokens(assistant), ["龙2", "幻0"])
        XCTAssertEqual(ice?.formula?.breakStep, 1, "冰在第 1 步碎")
        XCTAssertEqual(ice?.formula?.done, 0)
        XCTAssertEqual(ice?.remaining, 8)
        XCTAssertGreaterThanOrEqual(ice?.nextTurnDamage ?? 0, 16)
        XCTAssertEqual(ice?.broken, false)
        XCTAssertEqual(assistant.hint.analysis?.isLethal, false, "破冰口径的结论里没有斩杀判定")
        XCTAssertTrue(assistant.hint.locked, "破冰线一律锁定，不看揭示档")
        XCTAssertFalse(assistant.hint.isStale)
        let model = RDOverlayModel.make(assistant.hint, cardName: { $0 })
        XCTAssertEqual(model.badge?.title, RDText.iceLethalNextTurn)
        XCTAssertEqual(model.lines.filter { $0.isFormula }.map { $0.pieces.map { $0.text } }, [["龙2", "冰碎"], ["幻0"]])
        XCTAssertEqual(model.lines.last?.kind, .icePremise)

        // 再点：关掉，同样立刻重算，回到斩杀判定
        published = []
        start = CFAbsoluteTimeGetCurrent()
        assistant.toggleIceBreak()
        XCTAssertFalse(assistant.iceMode)
        XCTAssertEqual(published.first?.iceMode, false)
        XCTAssertEqual(published.first?.locked, false, "破冰线不再锁着：等斩杀判定时置灰")
        XCTAssertEqual(assistant.scheduledComputations, scheduled + 2)
        spin { assistant.hint.phase == .ready && assistant.hint.analysis?.ice == nil }
        let offCost = CFAbsoluteTimeGetCurrent() - start
        XCTAssertLessThan(offCost, 1.0)
        XCTAssertEqual(assistant.fedInputs.count, fed)
        XCTAssertEqual(assistant.hint.analysis?.isLethal, true)
        XCTAssertEqual(button(), false)
        print(String(format: "T8TOGGLE on → ice conclusion %.0f ms, off → lethal verdict %.0f ms (debounce 1500 ms not applied)",
                     onCost * 1000, offCost * 1000))

        // 对方没有奥秘：开不了
        var none = s0
        none.opponentSecretCount = 0
        feed(none)
        spin { assistant.hint.phase == .ready && assistant.hint.analysis?.opponentHasSecrets == false }
        XCTAssertNil(button())
        let before = assistant.scheduledComputations
        assistant.toggleIceBreak()
        XCTAssertFalse(assistant.iceMode)
        XCTAssertEqual(assistant.scheduledComputations, before)
        // 对方回合：不响应
        DispatchQueue.global().sync { assistant.feed(.opponentTurn) }
        spin { assistant.hint.phase == .opponentTurn }
        assistant.toggleIceBreak()
        XCTAssertFalse(assistant.iceMode)
        XCTAssertEqual(assistant.scheduledComputations, before)
    }

    /// 口径 6 的两条自动关：换了对局；轮到我方时对方没有奥秘。对方回合里不关，下回合对方奥秘还在就接着是破冰口径
    /// （按键在第一份结论到之前就在）。另外不在对局 / 关掉总开关也关
    func testIceModeTurnsOffOnNewGameAndWhenNoSecretAtTurnStart() {
        let sw = Switch()
        func feed(_ assistant: RedDragonAssistant, _ input: RDAssistantInput) {
            DispatchQueue.global().sync { assistant.feed(input) }
        }
        let s0 = iceSnapshot()

        // 1. 新对局：对方照样有奥秘，破冰也从关着开始
        var assistant = makeAssistant(sw)
        turnIceOn(assistant, s0)
        var published: [RedDragonHint] = []
        assistant.onChange = { published.append($0) }
        var other = s0
        other.match = Self.matchB
        other.turn = 5
        feed(assistant, .snapshot(other))
        spin { assistant.hint.phase == .ready && assistant.hint.analysis?.ice == nil }
        XCTAssertFalse(assistant.iceMode, "新对局自动关")
        XCTAssertFalse(assistant.hint.iceMode)
        XCTAssertNil(assistant.hint.analysis?.ice)
        XCTAssertEqual(assistant.hint.analysis?.isLethal, true, "回到斩杀判定")
        XCTAssertFalse(published.contains { $0.deviated }, "换局不是偏离")
        XCTAssertEqual(RDOverlayModel.make(assistant.hint, cardName: { $0 }).badge?.iceButton, false, "按键还在（对方有奥秘），关着")

        // 2. 对方回合不关；轮到我方时对方已经没有奥秘：关
        assistant = makeAssistant(sw)
        turnIceOn(assistant, s0)
        feed(assistant, .opponentTurn)
        spin { assistant.hint.phase == .opponentTurn }
        XCTAssertTrue(assistant.iceMode, "对方回合里不关")
        var mine = s0
        mine.turn += 2
        mine.resources = 3
        mine.opponentSecretCount = 0
        feed(assistant, .snapshot(mine))
        spin { assistant.hint.phase == .ready }
        XCTAssertFalse(assistant.iceMode, "轮到我方时对方没有奥秘：自动关")
        XCTAssertNil(assistant.hint.analysis?.ice)
        XCTAssertNil(RDOverlayModel.make(assistant.hint, cardName: { $0 }).badge?.iceButton, "没有奥秘也没开着：按键不在")

        // 3. 轮到我方时奥秘还在：不关，新回合直接按破冰口径算；第一份结论到之前按键就在
        assistant = makeAssistant(sw)
        turnIceOn(assistant, s0)
        feed(assistant, .opponentTurn)
        spin { assistant.hint.phase == .opponentTurn }
        published = []
        assistant.onChange = { published.append($0) }
        var still = s0
        still.turn += 2
        still.resources = 3
        feed(assistant, .snapshot(still))
        spin { assistant.hint.phase == .ready }
        XCTAssertTrue(assistant.iceMode)
        XCTAssertNotNil(assistant.hint.analysis?.ice, "新回合直接是破冰口径")
        XCTAssertEqual(published.first?.phase, .computing)
        XCTAssertEqual(published.first.map { RDOverlayModel.make($0, cardName: { $0 }).badge?.iceButton }, true,
                       "结论到之前按键就在（开）")
        XCTAssertFalse(published.contains { $0.analysis != nil && $0.analysis?.ice == nil }, "没有闪过斩杀判定")

        // 4. 不在对局：关
        feed(assistant, .inactive)
        spin { assistant.hint.phase == .inactive }
        XCTAssertFalse(assistant.iceMode)

        // 5. 总开关关掉再开：关
        assistant = makeAssistant(sw)
        turnIceOn(assistant, s0)
        sw.enabled = false
        assistant.settingsDidChange()
        XCTAssertFalse(assistant.iceMode)
        sw.enabled = true
        assistant.settingsDidChange()
        feed(assistant, .snapshot(s0))
        spin { assistant.hint.phase == .ready }
        XCTAssertFalse(assistant.iceMode)
        XCTAssertNil(assistant.hint.analysis?.ice)
    }

    /// 沿破冰线一步步跟手，包括打掉冰的那一步之后（口径 6：中途冰被打掉 —— 对方免疫、奥秘数变 0 —— 不关，
    /// 线上剩下的准备步照常跟）。每一步都是「接着用」（不重新搜索、不去抖、面板不置灰），到面板更新不到 1 秒（T3）
    func testIceLineFollowsAcrossTheBreakWithoutTurningOff() {
        let sw = Switch()
        // 去抖 1 秒：跟手如果去抖，下面每一步的耗时过不了
        let assistant = makeAssistant(sw, debounce: 1.0)
        func feed(_ s: RDGameSnapshot) { DispatchQueue.global().sync { assistant.feed(.snapshot(s)) } }
        func done() -> Int? { return assistant.hint.analysis?.ice?.formula?.done }
        let s0 = iceSnapshot()
        turnIceOn(assistant, s0)
        XCTAssertEqual(iceTokens(assistant), ["龙2", "幻0"])
        let nextTurn = assistant.hint.analysis?.ice?.nextTurnDamage
        let followed = assistant.followedComputations
        let scheduled = assistant.scheduledComputations
        var published: [RedDragonHint] = []
        assistant.onChange = { published.append($0) }

        // 第 1 步：阿莱打脸，冰碎
        let s1 = iceSnapshot(stage: 1)
        var start = CFAbsoluteTimeGetCurrent()
        feed(s1)
        spin { done() == 1 && assistant.hint.phase == .ready }
        let first = CFAbsoluteTimeGetCurrent() - start
        XCTAssertEqual(done(), 1)
        XCTAssertTrue(assistant.iceMode, "口径 6：中途冰被打掉不关")
        XCTAssertEqual(assistant.followedComputations, followed + 1, "接着用，不重新搜索")
        XCTAssertLessThan(first, 1.0, "出一步到面板更新 ≤ 1 秒，也没有去抖")
        var ice = assistant.hint.analysis?.ice
        XCTAssertEqual(ice?.kind, .lethalNextTurn)
        XCTAssertEqual(ice?.broken, true)
        XCTAssertEqual(ice?.formula?.breakStep, 1, "冰碎的记号留在原来那一步后面")
        XCTAssertEqual(iceTokens(assistant), ["龙2", "幻0"], "公式不换，只是划掉走过的")
        XCTAssertEqual(ice?.remaining, 8)
        XCTAssertEqual(ice?.nextTurnDamage, nextTurn, "下回合的数是锁定那条线的，跟手不重算")
        XCTAssertTrue(assistant.hint.locked)
        let model = RDOverlayModel.make(assistant.hint, cardName: { $0 })
        XCTAssertEqual(model.badge?.title, RDText.iceBrokenLethalNextTurn)
        XCTAssertEqual(model.badge?.iceButton, true, "对方奥秘数已经是 0，按键还在")
        XCTAssertEqual(model.badge?.dimmed, false)
        XCTAssertEqual(model.lines.filter { $0.isFormula }.flatMap { $0.pieces.map { $0.state } }, [.done, .note, .next])

        // 第 2 步：幻觉药水（冰碎之后的准备步）
        let s2 = iceSnapshot(stage: 2)
        start = CFAbsoluteTimeGetCurrent()
        feed(s2)
        spin { done() == 2 && assistant.hint.phase == .ready }
        let second = CFAbsoluteTimeGetCurrent() - start
        XCTAssertEqual(done(), 2)
        XCTAssertTrue(assistant.iceMode)
        XCTAssertEqual(assistant.followedComputations, followed + 2)
        XCTAssertLessThan(second, 1.0)
        ice = assistant.hint.analysis?.ice
        XCTAssertEqual(ice?.kind, .lethalNextTurn)
        XCTAssertEqual(ice?.broken, true)
        XCTAssertEqual(assistant.scheduledComputations, scheduled + 2, "两步各排一次核对")
        XCTAssertFalse(published.contains { $0.deviated || $0.isStale || $0.phase == .computing },
                       "锁定的线跟手时不置灰、不标正在算")
        XCTAssertFalse(published.contains { !$0.iceMode })
        print(String(format: "T8FOLLOW step 1 (break) %.0f ms, step 2 (prep) %.0f ms from feed to committed hint",
                     first * 1000, second * 1000))
    }

    /// 破冰线走完之后还有费用、再动一下（英雄技能）：不算偏离，重算仍是破冰口径（对方免疫，只算准备步，可以是 0 步）
    func testActingAfterTheIceLineIsDoneIsNotADeviation() {
        let sw = Switch()
        let assistant = makeAssistant(sw, debounce: 0.05)
        func feed(_ s: RDGameSnapshot) { DispatchQueue.global().sync { assistant.feed(.snapshot(s)) } }
        // 两张阿莱、没有药水、对方 9 血：线只有阿莱打脸一步（剩 1），打完还剩 2 费
        turnIceOn(assistant, iceSnapshot(potion: false))
        let line = iceTokens(assistant)
        XCTAssertEqual(line, ["龙2"])
        XCTAssertEqual(assistant.hint.analysis?.ice?.kind, .lethalNextTurn)
        let s1 = iceSnapshot(stage: 1, potion: false)
        feed(s1)
        spin { assistant.hint.analysis?.ice?.formula?.done == 1 }
        XCTAssertEqual(assistant.hint.analysis?.ice?.formula?.done, 1, "线走完了")
        XCTAssertTrue(assistant.iceMode)
        var published: [RedDragonHint] = []
        assistant.onChange = { published.append($0) }
        let scheduled = assistant.scheduledComputations
        feed(afterHeroPower(s1))
        spin { assistant.scheduledComputations > scheduled && assistant.hint.phase == .ready
            && assistant.hint.analysis?.ice?.formula?.done == 0 }
        XCTAssertTrue(assistant.iceMode)
        XCTAssertFalse(published.contains { $0.deviated }, "线已经走完，之后怎么打都不是偏离")
        XCTAssertFalse(published.contains { $0.analysis != nil && $0.analysis?.ice == nil }, "没有退回斩杀判定")
        let ice = assistant.hint.analysis?.ice
        XCTAssertNotNil(ice)
        XCTAssertEqual(ice?.broken, true)
        XCTAssertEqual(ice?.formula?.done, 0)
        XCTAssertEqual(iceTokens(assistant), [], "对方免疫、费用用完：0 步")
        XCTAssertNil(ice?.formula?.breakStep)
        XCTAssertEqual(ice?.kind, .lethalNextTurn, "下回合另一张阿莱照样够")
        XCTAssertEqual(ice?.remaining, 1)
        XCTAssertEqual(RDOverlayModel.make(assistant.hint, cardName: { $0 }).badge?.iceButton, true)
        print("T8AFTER line \(String(describing: line)) then hero power: \(String(describing: ice?.kind)) "
            + "tokens \(String(describing: iceTokens(assistant))) next \(String(describing: ice?.nextTurnDamage))")
    }

    /// 打偏：锁着的破冰线接不上 → 先标「已偏离，重算中」（旧线置灰留在原位），再照破冰口径重算，不退回斩杀判定。
    /// 冰碎之前打偏：重算出来的还是一条破冰线；冰碎之后打偏：对方免疫，重算只算准备步
    func testIceLineDeviationRecomputesInIceMode() {
        let sw = Switch()
        for broken in [false, true] {
            let assistant = makeAssistant(sw, debounce: 0.05)
            func feed(_ s: RDGameSnapshot) { DispatchQueue.global().sync { assistant.feed(.snapshot(s)) } }
            let s0 = iceSnapshot()
            turnIceOn(assistant, s0)
            var base = s0
            if broken {
                base = iceSnapshot(stage: 1)
                feed(base)
                spin { assistant.hint.analysis?.ice?.formula?.done == 1 }
                XCTAssertEqual(assistant.hint.analysis?.ice?.formula?.done, 1)
            }
            var published: [RedDragonHint] = []
            assistant.onChange = { published.append($0) }
            let followed = assistant.followedComputations
            // 线上的下一步是阿莱打脸 / 幻觉药水，用户却按了英雄技能
            feed(afterHeroPower(base))
            spin { published.contains { $0.deviated } && assistant.hint.phase == .ready && !assistant.hint.deviated }
            let marked = published.first { $0.deviated }
            XCTAssertNotNil(marked, "冰\(broken ? "碎之后" : "碎之前")打偏：先标已偏离")
            XCTAssertEqual(marked?.phase, .computing)
            XCTAssertEqual(marked?.iceMode, true)
            XCTAssertEqual(marked?.locked, false)
            if let marked {
                let model = RDOverlayModel.make(marked, cardName: { $0 })
                XCTAssertEqual(model.badge?.title, RDText.deviated)
                XCTAssertEqual(model.badge?.dimmed, true)
                XCTAssertEqual(model.badge?.iceButton, true)
                XCTAssertEqual(model.lines.filter { $0.isFormula }.flatMap { $0.pieces.map { $0.text } },
                               ["龙2", "冰碎", "幻0"], "旧线留在原位")
                XCTAssertFalse(model.lines.contains { $0.pieces.contains { $0.state == .next } })
            }
            XCTAssertTrue(assistant.iceMode, "重算仍按破冰口径")
            XCTAssertEqual(assistant.followedComputations, followed, "不是接着用，是重算")
            let ice = assistant.hint.analysis?.ice
            XCTAssertNotNil(ice)
            XCTAssertEqual(ice?.broken, broken)
            XCTAssertEqual(ice?.formula?.done, 0)
            if broken {
                // 对方免疫：只算准备步，线上没有「冰碎」
                XCTAssertNil(ice?.formula?.breakStep)
                XCTAssertNotEqual(ice?.kind, .cannotBreak)
                XCTAssertEqual(ice?.remaining, 8)
            } else {
                // 费用被英雄技能用掉 2：阿莱还打得出去（1 费），冰照样能破
                XCTAssertEqual(iceTokens(assistant)?.contains("龙0"), true)
                XCTAssertNotNil(ice?.formula?.breakStep)
                XCTAssertNotEqual(ice?.kind, .cannotBreak)
            }
            XCTAssertTrue(assistant.hint.locked, "新线重新锁定")
            XCTAssertFalse(published.contains { $0.analysis != nil && $0.analysis?.ice == nil }, "没有退回斩杀判定")
            print("T8DEVIATE broken=\(broken): \(String(describing: ice?.kind)) tokens \(iceTokens(assistant) ?? []) "
                + "remaining \(String(describing: ice?.remaining)) next \(String(describing: ice?.nextTurnDamage))")
        }
    }

    /// 口径 7：破冰那一下触发的不是寒冰屏障（对方没有免疫，奥秘没了）—— 不做专门处理，走「已偏离，重算」。
    /// 没有冰可破了，破冰自己关掉，重算回到斩杀判定；按键跟着奥秘一起消失
    func testSecretThatWasNotIceBlockGoesThroughDeviation() {
        let sw = Switch()
        let assistant = makeAssistant(sw, debounce: 0.05)
        let s0 = iceSnapshot()
        turnIceOn(assistant, s0)
        var published: [RedDragonHint] = []
        assistant.onChange = { published.append($0) }
        DispatchQueue.global().sync { assistant.feed(.snapshot(iceSnapshot(stage: 1, iceBlock: false))) }
        spin { assistant.hint.phase == .ready && assistant.hint.analysis?.ice == nil }
        XCTAssertTrue(published.contains { $0.deviated }, "锁着的破冰线标已偏离")
        XCTAssertFalse(assistant.iceMode)
        XCTAssertNil(assistant.hint.analysis?.ice)
        XCTAssertFalse(assistant.hint.deviated)
        XCTAssertEqual(assistant.hint.analysis?.effectiveEnemyHealth, 8, "斩杀判定按真实局面：对方剩 8 血、没有免疫")
        XCTAssertNil(RDOverlayModel.make(assistant.hint, cardName: { $0 }).badge?.iceButton)
    }

    /// T7 的那一条对破冰线同样成立：锁定的破冰线在核对上一个 BLOCK 闭合时的局面，下一个 BLOCK 紧跟着打开、
    /// 来了新行（`parserBatchDidEnd(idle: false)`）—— 这次核对不作废，进度照常上屏，面板不标过时。
    /// 之后一致边界上的局面（和上一份一样）到了，照常再核对一次，进度不丢
    func testOpenBlockLinesDoNotInvalidateTheLockedIceCheck() {
        let sw = Switch()
        let assistant = makeAssistant(sw, debounce: 0.05)
        let game = Game(hearthstoneRunState: HearthstoneRunState(isRunning: false, isActive: false))
        let s0 = iceSnapshot()
        turnIceOn(assistant, s0)
        let followed = assistant.followedComputations
        let discarded = assistant.discardedComputations
        var published: [RedDragonHint] = []
        assistant.onChange = { published.append($0) }
        let s1 = iceSnapshot(stage: 1)
        // 解析线程：攻击的 BLOCK 闭合、投出局面；同一批里下一个 BLOCK 已经打开、来了新行。主线程这时还没转
        DispatchQueue.global().sync {
            assistant.feed(.snapshot(s1))
            assistant.parserBatchDidEnd(game, linesProcessed: true, idle: false)
        }
        spin { assistant.hint.analysis?.ice?.formula?.done == 1 }
        XCTAssertEqual(assistant.hint.analysis?.ice?.formula?.done, 1, "核对的结论照常上屏")
        XCTAssertEqual(assistant.followedComputations, followed + 1)
        XCTAssertEqual(assistant.discardedComputations, discarded, "没有因为 BLOCK 开着来新行被丢掉")
        XCTAssertTrue(assistant.hint.locked)
        XCTAssertFalse(published.contains { $0.isStale || $0.deviated || $0.phase == .computing })

        // 一致边界：这一段没改到相关实体，拷出来和上一份一样 —— 再核对一次，仍在第 1 步之后
        DispatchQueue.global().sync { assistant.feed(.snapshot(s1)) }
        spin { assistant.followedComputations == followed + 2 }
        XCTAssertEqual(assistant.followedComputations, followed + 2)
        XCTAssertEqual(assistant.hint.analysis?.ice?.formula?.done, 1)
        XCTAssertTrue(assistant.iceMode)
        XCTAssertFalse(published.contains { $0.isStale || $0.deviated })
    }

    /// 从点按键到破冰结论上屏的墙钟（线上的预算配置；搜索在 -O 的包里）：fixture 里破冰最慢的几个回合开始的局面，
    /// 当成对方有冰。任务书硬约束 ≤ 3 秒；数字看打印的 `T8CLICK2RESULT`。
    /// 前五个是破不了 / 订正前最慢的；后三个是口径 12（冰还在时一直往下压血）之后破得了的里面最慢的
    func testClickToIceConclusionWithinThreeSeconds() {
        let picks: [(fixture: String, playerId: Int, turn: Int, health: Int?)] = [
            ("2026-10-05-g1-first", 1, 11, nil), ("2026-10-01-g3-lost", 1, 7, nil), ("2026-10-01-g3-lost", 1, 7, 12),
            ("2026-10-05-g7-rewind", 2, 13, 12), ("2026-10-05-g2-dance-lost", 2, 11, nil),
            ("2026-10-01-g4-second", 2, 10, 12), ("2026-10-05-g4-dance-won", 2, 11, 12), ("2026-10-01-g4-second", 2, 10, nil)
        ]
        var rows: [String] = []
        for p in picks {
            let all = RedDragonSetupTests.boundaries(lines: RedDragonFeedbackTests.lines(p.fixture), playerId: p.playerId)
                .filter { $0.snapshot.turn == p.turn }
            guard let top = all.map({ $0.snapshot.resources }).max(),
                  var snap = (all.first { $0.snapshot.resources == top && $0.snapshot.resourcesUsed == 0 }
                              ?? all.first { $0.snapshot.resources == top })?.snapshot else {
                XCTFail("\(p.fixture) T\(p.turn) 没有回合开始的边界")
                continue
            }
            snap.opponentSecretCount = max(1, snap.opponentSecretCount)
            snap.opponentHeroImmune = false
            if let h = p.health {
                snap.opponentHeroHealth = h
                snap.opponentHeroArmor = 0
            }
            let env = RedDragonAssistant.Environment(
                isEnabled: { true }, revealPreference: { .verdict }, quizMode: { false },
                debounce: RedDragonAssistant.Environment.liveDebounce, config: RedDragonConfig(), cardName: { $0 })
            let assistant = RedDragonAssistant(environment: env)
            assistant.submit(.snapshot(snap))
            spin(until: { assistant.hint.phase == .ready }, timeout: 30)
            // 危险且斩不了的局面这时奶 16 的线可能还在后台算：点按键要把它取消掉，不排在它后面
            let start = CFAbsoluteTimeGetCurrent()
            assistant.toggleIceBreak()
            spin(until: { assistant.hint.phase == .ready && assistant.hint.analysis?.ice != nil }, timeout: 30)
            let wall = CFAbsoluteTimeGetCurrent() - start
            let ice = assistant.hint.analysis?.ice
            XCTAssertNotNil(ice, "\(p.fixture) T\(p.turn)")
            XCTAssertLessThan(wall, 3.0, "\(p.fixture) T\(p.turn)")
            let verdict: String
            switch ice?.kind {
            case .lethalNextTurn?: verdict = "①"
            case .shortNextTurn?: verdict = "②"
            case .cannotBreak?: verdict = "③"
            case nil: verdict = "?"
            }
            rows.append(String(format: "%@ T%d%@ danger=%@ → %@ %d 步 %.3f s", p.fixture, p.turn,
                               p.health.map { " 改\($0)血" } ?? "", assistant.hint.analysis?.boardDanger == true ? "Y" : "N",
                               verdict, ice?.formula?.tokens.count ?? 0, wall))
        }
        print("T8CLICK2RESULT\n" + rows.joined(separator: "\n"))
    }
}

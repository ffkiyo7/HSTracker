//
//  RedDragonOverlayModel.swift
//  HSTracker
//
//  展示模型（`RedDragonHint`）→ overlay 上每样东西画不画、画成什么。纯值、纯函数：揭示档、答题、
//  过时这些「画不画」的规则都在这里，视图只按它摆位置。几何（手牌 / 场面 / 角标的位置）也在这里，
//  照搬 `BoardOverlayView` 的公式，保证和入场序号、悬停区域落在同一套坐标上。
//

import Foundation
import CoreGraphics
@testable import RedDragonCore

struct RDOverlayModel: Equatable {

    enum Tone: Equatable {
        case lethal, lethalIfDraw, notFound, provenNotLethal, neutral
        /// 准备线（奶 16 / 预启动）和「等死」：和斩杀线的绿色一眼分开
        case setup, doomed
    }

    enum Status: Hashable {
        case computing, truncated
    }

    struct Badge: Equatable {
        var title: String
        /// 「32 / 30」
        var numbers: String?
        /// 「+2」/「差 8」
        var margin: String?
        var tone: Tone
        var tier: String?
        var statuses: [Status]
        /// 判定角标旁的「⚠ 对方有奥秘」：搜索不看对手奥秘，可斩杀可能是误报
        var opponentSecrets: Bool
        var level: RDRevealLevel
        var maxLevel: RDRevealLevel
        var quizMode: Bool
        var quiz: RDQuizMark?
        /// 结论不是当前局面的（过时 / 正在算 / 已偏离）：整块置灰，内容和大小不变
        var dimmed: Bool
    }

    enum LineKind: Equatable {
        case nextStep
        case branch(lethal: Bool)
        case missing
        case insufficient
        case danger
        /// 完整公式（多行排版，不截断）。`setup`：准备线（奶 16 / 预启动），否则是斩杀线
        case formula(setup: Bool)
        /// 准备线的「回合末留下什么」
        case leftover
    }

    /// 公式里的一步。`done` 划掉、`next` 高亮、`pending` 正常、`note` 是「抽到 X 才继续」之类的说明
    struct Piece: Equatable {
        enum State: Equatable { case done, next, pending, note }
        var text: String
        var state: State
        /// `text` 里要换色突出的那一段（乐队经理拿的牌「（龙舞）」）
        var accent: String? = nil
    }

    struct Line: Equatable {
        var kind: LineKind
        var text: String
        /// 公式行开头的小标签（「斩杀」/「奶16」/「预启动」）
        var label: String? = nil
        var pieces: [Piece] = []

        var isFormula: Bool {
            if case .formula = kind { return true }
            return false
        }
    }

    var badge: Badge?
    var lines: [Line] = []

    var isVisible: Bool { return badge != nil }

    static let hidden = RDOverlayModel(badge: nil)

    /// 抽牌分叉最多列几条
    static let maxBranches = 3

    // MARK: - 规则

    static func make(_ hint: RedDragonHint, cardName: (String) -> String) -> RDOverlayModel {
        switch hint.phase {
        case .inactive, .opponentTurn:
            return .hidden
        case .computing, .ready:
            break
        }
        // 锁定的公式不变暗：炉石日志晚到的窗口里照常显示（10-06 用户定）
        let dimmed = hint.deviated || ((hint.phase == .computing || hint.isStale) && !hint.locked)
        guard let a = hint.analysis else {
            return RDOverlayModel(badge: Badge(title: RDText.assistantName, numbers: nil, margin: nil, tone: .neutral,
                                               tier: nil, statuses: [.computing], opponentSecrets: false,
                                               level: hint.revealLevel, maxLevel: hint.maxRevealLevel,
                                               quizMode: hint.quizMode, quiz: nil, dimmed: false))
        }

        // 重算 / 过时期间不加「正在算」「过时」标签（多一行面板就会跳）：只把整块置灰，内容原样留着，
        // 算完再换（10-06 用户定：照着打的时候浮窗不要变形）
        var statuses: [Status] = []
        if a.completeness == .truncated { statuses.append(.truncated) }

        // 准备建议只在斩不了时有（斩得了先斩）
        let setup = a.isLethal ? nil : a.setup
        let title: String
        let tone: Tone
        if let s = setup {
            switch s.kind {
            case .heal16: (title, tone) = (RDText.heal16Title, .setup)
            case .preLaunch: (title, tone) = (RDText.preLaunchTitle, .setup)
            case .doomed: (title, tone) = (RDText.doomed, .doomed)
            }
        } else {
            switch a.verdict {
            case .lethal: (title, tone) = (RDText.lethal, .lethal)
            case .lethalIfDraw: (title, tone) = (RDText.lethalIfDraw, .lethalIfDraw)
            case .notFound: (title, tone) = (RDText.notFound, .notFound)
            case .provenNotLethal: (title, tone) = (RDText.provenNotLethal, .provenNotLethal)
            }
        }
        // 「最大伤害 / 敌方有效血量」。不斩杀时标题已经说了「不能 / 未搜到」，不再加「最大」两字，省出角标宽度。
        // 准备线的角标不放伤害数字（那几个数和这条线无关）
        // 锁定的线走不通（`deviated`）：旧公式置灰留在原位、不再高亮下一步，只把标题换成「已偏离，重算中」
        // （数字让给它，标题行不变宽）；标签行、公式行、回合末行都不增不减，新线算出来再整块换掉
        // （10-06 用户定，取代「只留一个角标」）
        let plain = setup == nil && !hint.deviated
        let numbers = plain ? "\(a.maxDamage) / \(a.effectiveEnemyHealth)" : nil
        let badge = Badge(title: hint.deviated ? RDText.deviated : title, numbers: numbers,
                          margin: plain ? RDText.margin(a.margin) : nil,
                          tone: hint.deviated ? .notFound : tone,
                          tier: a.isLethal ? a.tier.map(RDText.tier) : nil, statuses: statuses,
                          opponentSecrets: a.opponentHasSecrets,
                          level: hint.revealLevel, maxLevel: hint.maxRevealLevel,
                          quizMode: hint.quizMode, quiz: hint.quizMode ? hint.quiz : nil, dimmed: dimmed)
        var model = RDOverlayModel(badge: badge)

        // 奶 16 / 预启动 / 等死：永远直接给完整步骤，不受揭示档和答题模式影响（10-05 用户定：危险时没必要练习）
        if let s = setup {
            if let f = s.formula {
                model.lines += formulaLines(f, setup: true, highlightsNext: !dimmed)
                model.lines.append(Line(kind: .leftover, text: leftover(f)))
            }
            return model
        }

        if !hint.quizMode && hint.revealLevel >= .order {
            if hint.locked || hint.deviated, a.isLethal, let f = a.formula {
                // 「顺序」档锁定：完整公式，已走的划掉（答题模式下不显示完整公式）
                model.lines += formulaLines(f, setup: false, highlightsNext: !dimmed)
            } else if let first = a.steps.first {
                model.lines.append(Line(kind: .nextStep,
                                        text: RDText.nextStep(RDText.step(first, cardName: cardName),
                                                              total: a.totalSteps, shown: a.steps.count)))
            }
        }
        if a.verdict != .lethal {
            for b in a.drawBranches.prefix(maxBranches) {
                model.lines.append(Line(kind: .branch(lethal: b.isLethal),
                                        text: RDText.branch(b.drawn.map(cardName), damage: b.damage)))
            }
        }
        if !a.isLethal && !a.missingPieces.isEmpty {
            model.lines.append(Line(kind: .missing,
                                    text: RDText.missing(a.missingPieces.map(cardName),
                                                         incomplete: a.missingPiecesIncomplete)))
        }
        if a.singleTurnInsufficient {
            model.lines.append(Line(kind: .insufficient, text: RDText.singleTurnInsufficient))
        }
        if a.boardDanger {
            model.lines.append(Line(kind: .danger, text: RDText.boardDanger))
        }

        return model
    }

    private static func label(_ goal: RDFormula.Goal) -> String {
        switch goal {
        case .lethal: return RDText.lethalLabel
        case .heal16: return RDText.healLabel
        case .preLaunch: return RDText.preLaunchLabel
        }
    }

    /// 整条公式的每一步（不分行）
    static func pieces(_ f: RDFormula) -> [Piece] {
        return formulaLines(f, setup: false).flatMap { $0.pieces }
    }

    /// 公式按阶段分行（公式表的一二三阶段）：打出「舞」或「幻」的那一步收尾一行，下一步另起一行。
    /// 只有第一行带标签；`highlightsNext` 为 false 时不高亮下一步（已偏离的旧公式）
    static func formulaLines(_ f: RDFormula, setup: Bool, highlightsNext: Bool = true) -> [Line] {
        var rows: [[Piece]] = [[]]
        for (i, t) in f.tokens.enumerated() {
            if i > 0 {
                let prev = f.tokens[i - 1]
                if prev.kind == .play, prev.card == .bounceAround || prev.card == .potionOfIllusion {
                    rows.append([])
                }
            }
            let state: Piece.State = i < f.done ? .done : (i == f.done && highlightsNext ? .next : .pending)
            rows[rows.count - 1].append(Piece(text: RDText.formulaToken(t), state: state,
                                                 accent: RDText.formulaPicks(t)))
            if let note = RDText.formulaNote(t) { rows[rows.count - 1].append(Piece(text: note, state: .note)) }
        }
        return rows.enumerated().map { i, row in
            Line(kind: .formula(setup: setup), text: "", label: i == 0 ? label(f.goal) : nil, pieces: row)
        }
    }

    /// 「回合末：场 鱼 狐｜手 刀 暗｜下回合约 40」
    static func leftover(_ f: RDFormula) -> String {
        var parts: [String] = []
        if !f.leftBoard.isEmpty { parts.append(RDText.leftBoard + f.leftBoard.map(RDText.abbr).joined(separator: " ")) }
        if !f.leftHand.isEmpty { parts.append(RDText.leftHand + f.leftHand.map(RDText.abbr).joined(separator: " ")) }
        if f.potential > 0 { parts.append(RDText.nextTurnPotential(f.potential)) }
        return RDText.leftoverPrefix + parts.joined(separator: "｜")
    }
}

// MARK: - 几何

/// 全部在 `RootOverlayView` 的固定像素层里算（canvas = 炉石窗口的真实像素）：手牌和场面的位置照搬
/// `BoardOverlayView`（它也在这一层，入场序号同样），尺寸按窗口高 / 1080 缩放
enum RDOverlayGeometry {

    static func unit(_ canvas: CGSize) -> CGFloat { return canvas.height / 1080 }

    /// 悬停判定用的手牌矩形大小（`BoardOverlayView.handTargets`）
    static func handCardSize(_ canvas: CGSize) -> CGSize {
        return CGSize(width: canvas.height * 0.125, height: canvas.height * 0.189)
    }

    static func handCard(index: Int, count: Int, canvas: CGSize) -> (center: CGPoint, angle: Double) {
        let pos = BoardOverlayView.handCardPosition(index: index, count: count, canvasSize: canvas)
        return (pos, BoardOverlayView.handCardAngle(index: index, count: count, pos: pos, canvasSize: canvas))
    }

    /// 入场序号同款徽章的高度（`BoardOrderSlotViewModel.badgeSize`）
    static func badgeSize(_ canvas: CGSize) -> CGFloat {
        return BoardOrderSlotViewModel.badgeSize(height: BoardOverlayView.boardHeight(canvas))
    }

    /// 第 `index` 格随从（共 `count` 格）的矩形。横向照 `BoardOverlayView.row` 的居中 HStack，
    /// 纵向是它的 `opponentTop` / `playerTop`（构筑模式，无佣兵偏移）
    static func minionRect(isEnemy: Bool, index: Int, count: Int, canvas: CGSize) -> CGRect {
        let width = BoardOverlayView.minionWidth(canvas)
        let margin = BoardOverlayView.minionMargin(canvas, isMercenariesMatch: false)
        let slot = width + 2 * margin
        let height = BoardOverlayView.boardHeight(canvas)
        let centerX = canvas.width / 2 + (CGFloat(index) - CGFloat(count - 1) / 2) * slot
        let top = isEnemy
            ? BoardOverlayView.opponentTop(canvas, isMercenariesMatch: false, isMainAction: false, mercsToNominate: false)
            : BoardOverlayView.playerTop(canvas, isMercenariesMatch: false, isMainAction: false, mercsToNominate: false)
        return CGRect(x: centerX - width / 2, y: top, width: width, height: height)
    }

    // MARK: 判定面板的位置

    /// 默认位置：4:3 区域左下（手牌左边、我方英雄左下的空地），底边在 0.985 H，宽 ≤ 320 u。
    /// 面板不和任何「障碍」相交：手牌（1~10 张转过角的外接框并集）、双方场面一行、双方场攻图标、我方计数器、
    /// 双方英雄区、法力、对方手牌标记，以及两个记牌器（位置 / 尺寸 / 缩放取自记牌器 view model，拖动中也跟着变）。
    ///
    /// 面板只在我方英雄区左边找位置。放不下时按这个顺序降级（`panelLayout`），第一个放得下的就用：
    /// 1. 行数：全部 → 留 2 行 → 留 1 行 → 只留角标（判定 + 标签行）。收行按重要度：场面危险 > 下一步 >
    ///    单回合不够 > 抽牌分叉 > 缺件；收掉几行写在角标末尾（「收起 N 条」）。最后一档再去掉「伤害 / 血量」，
    ///    只留标题、差值和标签行（「⚠ 对方有奥秘」始终保留）。
    /// 2. 每种行数下底边：先 0.985 H（默认一行），再手牌上沿之上，再每个记牌器的上沿之上（从低到高）。
    /// 3. 每个底边下字号 / 间距：×1 → ×0.85 → ×0.72。
    /// 4. 每个字号下左沿：先 4:3 内缩，再画布左边 8 u，再每个障碍的右沿 + 8 u；宽度到右边第一个障碍为止
    ///    （所以记牌器在右边时面板缩在它左边，在左边时挪到它右边）。
    /// 5. 全都放不下：不画面板。
    static let panelInsetFraction: CGFloat = 0.025
    static let panelBottomFraction: CGFloat = 0.985
    static let panelMaxWidth: CGFloat = 320
    static let panelMinWidth: CGFloat = 200
    static let panelScales: [CGFloat] = [1, 0.85, 0.72]
    /// 面板和障碍之间至少留的空（u）
    static let panelGap: CGFloat = 8

    /// 1~10 张手牌全部（转过角的悬停矩形）的外接框
    static func handBox(_ canvas: CGSize) -> CGRect {
        let size = handCardSize(canvas)
        var box = CGRect.null
        for count in 1...10 {
            for index in 0..<count {
                let card = handCard(index: index, count: count, canvas: canvas)
                let rect = CGRect(x: card.center.x - size.width / 2, y: card.center.y - size.height / 2,
                                  width: size.width, height: size.height)
                box = box.union(rect.applying(CGAffineTransform(translationX: -rect.midX, y: -rect.midY)
                    .concatenating(CGAffineTransform(rotationAngle: CGFloat(card.angle * .pi / 180)))
                    .concatenating(CGAffineTransform(translationX: rect.midX, y: rect.midY))))
            }
        }
        return box
    }

    /// 和记牌器无关的固定障碍（位置照各组件的默认百分比；场攻图标 75 px、计数器一行 400 u 宽都按偏大估）
    static func fixedObstacles(_ canvas: CGSize, hand: CGRect? = nil) -> [CGRect] {
        let u = unit(canvas)
        let h = canvas.height
        let ratio = BoardOverlayView.ratio(canvas)
        let x43 = { (f: CGFloat) in SizeHelper.getScaledXPos(f, width: canvas.width, ratio: ratio) }
        let board = minionRect(isEnemy: false, index: 0, count: 7, canvas: canvas)
            .union(minionRect(isEnemy: false, index: 6, count: 7, canvas: canvas))
        let enemyBoard = minionRect(isEnemy: true, index: 0, count: 7, canvas: canvas)
            .union(minionRect(isEnemy: true, index: 6, count: 7, canvas: canvas))
        let icon = max(75, 75 * u)
        return [
            hand ?? handBox(canvas),
            board,
            CGRect(x: x43(0.255), y: h * 0.6762, width: icon, height: icon),                         // 我方场攻
            CGRect(x: x43(0.677), y: h * 0.684, width: 400 * u, height: 51 * u),                     // 我方计数器
            CGRect(x: canvas.width / 2 - h * 0.2, y: h * 0.70, width: h * 0.4, height: h * 0.17),    // 我方英雄 / 武器 / 技能
            CGRect(x: x43(0.752), y: h * 0.956, width: 160 * u, height: 40 * u),                     // 法力
            // 对方半场（面板只在最后一档、贴着记牌器上沿时才会去上半屏）
            enemyBoard,
            CGRect(x: x43(0.255), y: h * 0.2239, width: icon, height: icon),                         // 对方场攻
            CGRect(x: canvas.width / 2 - h * 0.2, y: h * 0.09, width: h * 0.4, height: h * 0.2),     // 对方英雄 / 武器 / 技能
            CGRect(x: canvas.width / 2 - 220 * u, y: 0, width: 440 * u, height: 48 * u)               // 对方手牌标记
        ]
    }

    /// 记牌器的位置参数（`TrackerPanelViewModel` 的 top / left / height / scaling / isShown）
    struct TrackerPlacement: Equatable {
        var isOpponent: Bool
        var isShown: Bool
        var left: Double
        var top: Double
        var height: Double
        var scaling: Double
    }

    /// 记牌器占的矩形，照 `TrackerPanelView` 的摆法：对手的左沿挂在 left%，我方的右沿挂在 left%；
    /// 高 = height% H；宽取「按区域分组」和老布局两种宽度的大者（不管哪种布局都不会少算）
    static func trackerBox(_ p: TrackerPlacement, cardSize: CardSize, canvas: CGSize) -> CGRect? {
        guard p.isShown else { return nil }
        let scale = CGFloat(max(p.scaling / 100, 0.01))
        let width = max(TrackerMetrics.panelWidth(windowWidth: canvas.width, windowHeight: canvas.height,
                                                  cardSize: cardSize),
                        legacyTrackerWidth(cardSize)) * scale
        let anchor = canvas.width * CGFloat(p.left / 100)
        return CGRect(x: p.isOpponent ? anchor : anchor - width, y: canvas.height * CGFloat(p.top / 100),
                      width: width, height: canvas.height * CGFloat(p.height / 100))
    }

    /// `SizeHelper.trackerWidth` 的同一张表，按参数而不是当前设置取
    static func legacyTrackerWidth(_ cardSize: CardSize) -> CGFloat {
        switch cardSize {
        case .tiny: return CGFloat(kTinyFrameWidth)
        case .small: return CGFloat(kSmallFrameWidth)
        case .medium: return CGFloat(kMediumFrameWidth)
        case .big: return CGFloat(kFrameWidth)
        case .huge: return CGFloat(kHighRowFrameWidth)
        }
    }

    struct PanelLayout: Equatable {
        /// 画布像素
        var frame: CGRect
        /// 面板内部的缩放（字号、间距、圆角都乘它）
        var scale: CGFloat
        var lines: [RDOverlayModel.Line]
        /// 放不下被收掉的行数
        var droppedLines: Int
        /// 最后一档：角标去掉「伤害 / 血量」，只留标题和差值
        var hidesNumbers = false
    }

    /// 按上面的降级顺序找第一个放得下的位置；nil = 哪都放不下，不画面板
    static func panelLayout(canvas: CGSize, badge: RDOverlayModel.Badge, lines: [RDOverlayModel.Line],
                            trackers: [CGRect]) -> PanelLayout? {
        let u = unit(canvas)
        guard u > 0 else { return nil }
        let gap = panelGap * u
        let hand = handBox(canvas)
        let obstacles = fixedObstacles(canvas, hand: hand) + trackers.filter { !$0.isEmpty }
        let inset = SizeHelper.getScaledXPos(panelInsetFraction, width: canvas.width, ratio: BoardOverlayView.ratio(canvas))
        // 左沿候选：4:3 内缩；画布左边（记牌器被拖进 4:3 区域、让出了黑边时）；每个障碍的右沿 + 间隙
        var xs = [inset, gap]
        for x in obstacles.map({ $0.maxX + gap }).sorted() where x > gap && !xs.contains(x) {
            xs.append(x)
        }
        // 底边候选：默认一行；手牌上沿之上；每个记牌器的上沿之上（记牌器占满左下时贴着它的头顶放）
        var bottoms = [canvas.height * panelBottomFraction, hand.minY - gap]
        for t in trackers.map({ $0.minY - gap }).sorted(by: >) where t > gap && !bottoms.contains(t) {
            bottoms.append(t)
        }
        let bounds = CGRect(origin: .zero, size: canvas)
        // 面板只在画面左半边找位置（我方英雄区左边）：右半边有法力水晶、牌库、我方记牌器，跑过去也不好找
        let region = canvas.width / 2 - canvas.height * 0.2 - gap
        xs = xs.filter { $0 < region }

        func rightLimit(x: CGFloat, top: CGFloat, bottom: CGFloat) -> CGFloat {
            var limit = region
            for o in obstacles where o.maxY > top && o.minY < bottom && o.minX >= x {
                limit = min(limit, o.minX - gap)
            }
            return limit
        }

        // 公式行不能收（收了就是截掉后半段）：降级只收别的行，缩字号 / 换位置也放不下就不画面板
        let required = lines.filter { $0.isFormula }.count
        var variants = lineCaps(lines).map { (keep: $0, hidesNumbers: false) }
        if badge.numbers != nil {
            variants.append((keep: required, hidesNumbers: true))
        }
        for variant in variants {
            let shown = compact(lines, keep: variant.keep)
            let dropped = lines.count - shown.count
            var badge = badge
            if variant.hidesNumbers { badge.numbers = nil }
            for bottom in bottoms {
                for s in panelScales {
                    let p = u * s
                    let minWidth = RDPanelMetrics.minWidth(badge: badge, dropped: dropped) * p
                    let tallest = RDPanelMetrics.height(badge: badge, lines: shown, width: panelMaxWidth) * p
                    for x in xs {
                        // 宽度先按最矮的情形取，再按这个宽度下的真实行数复核一次
                        var width = min(panelMaxWidth * p, rightLimit(x: x, top: bottom - tallest, bottom: bottom) - x)
                        guard width >= minWidth else { continue }
                        var height = RDPanelMetrics.height(badge: badge, lines: shown, width: width / p) * p
                        width = min(width, rightLimit(x: x, top: bottom - height, bottom: bottom) - x)
                        guard width >= minWidth else { continue }
                        height = RDPanelMetrics.height(badge: badge, lines: shown, width: width / p) * p
                        let frame = CGRect(x: x, y: bottom - height, width: width, height: height)
                        guard bounds.contains(frame),
                              !obstacles.contains(where: { $0.intersects(frame.insetBy(dx: -gap / 2, dy: -gap / 2)) })
                        else { continue }
                        return PanelLayout(frame: frame, scale: s, lines: shown, droppedLines: dropped,
                                           hidesNumbers: variant.hidesNumbers)
                    }
                }
            }
        }
        return nil
    }

    /// 留几行：全部 → 2 → 1 → 0
    static func lineCaps(_ count: Int) -> [Int] {
        return [count] + [2, 1, 0].filter { $0 < count }
    }

    /// 同上，但公式行一定留（不低于公式行的条数）
    static func lineCaps(_ lines: [RDOverlayModel.Line]) -> [Int] {
        let required = lines.filter { $0.isFormula }.count
        return lineCaps(lines.count).filter { $0 >= required }
    }

    /// 按重要度留 `keep` 行，留下的保持原来的顺序
    static func compact(_ lines: [RDOverlayModel.Line], keep: Int) -> [RDOverlayModel.Line] {
        guard keep < lines.count else { return lines }
        func rank(_ k: RDOverlayModel.LineKind) -> Int {
            switch k {
            case .formula: return -2
            case .leftover: return -1
            case .danger: return 0
            case .nextStep: return 1
            case .insufficient: return 2
            case .branch: return 3
            case .missing: return 4
            }
        }
        let kept = lines.indices.sorted { (rank(lines[$0].kind), $0) < (rank(lines[$1].kind), $1) }.prefix(keep)
        return kept.sorted().map { lines[$0] }
    }
}

/// 面板的尺寸估计，单位是「面板单位」（乘上 u × 缩放才是像素）。数字和 `RDPanel` 的写法一一对应；
/// 文字宽度按偏大估（汉字 / 符号 1 em，其余 0.62 em，Belwe 数字 0.7 em），高度按估出的行数算，
/// 所以估计值只会比实际大（测试里用 NSHostingView 实测核对）
enum RDPanelMetrics {
    static let fontScale: CGFloat = 1.2
    /// 一行文字的高度 / 字号
    static let lineHeightFactor: CGFloat = 1.45
    static let paddingH: CGFloat = 22
    static let paddingV: CGFloat = 14
    static let spacing: CGFloat = 4
    static let pipsWidth: CGFloat = 26
    static let headerSpacing: CGFloat = 6
    static let chipPaddingH: CGFloat = 12
    static let chipPaddingV: CGFloat = 3
    static let chipSpacing: CGFloat = 5
    static let lineGlyphColumn: CGFloat = 16

    static let titleSize: CGFloat = 16
    static let numbersSize: CGFloat = 15
    static let marginSize: CGFloat = 12
    static let chipSize: CGFloat = 11
    static let nextStepSize: CGFloat = 14
    static let lineSize: CGFloat = 13

    static func textWidth(_ s: String, size: CGFloat, latin: CGFloat = 0.62) -> CGFloat {
        var w: CGFloat = 0
        for c in s.unicodeScalars {
            let wide = c.value >= 0x2E80 || (0x2000...0x2BFF).contains(c.value)
            w += (wide ? 1 : latin) * size * fontScale
        }
        return w
    }

    static func chipWidth(_ text: String) -> CGFloat {
        return textWidth(text, size: chipSize) + chipPaddingH + 2
    }

    static func chipTexts(_ b: RDOverlayModel.Badge) -> [String] {
        var out: [String] = []
        if let tier = b.tier { out.append(tier) }
        for s in b.statuses {
            switch s {
            case .computing: out.append(RDText.computing)
            case .truncated: out.append(RDText.truncated)
            }
        }
        if b.opponentSecrets { out.append(RDText.opponentSecrets) }
        return out
    }

    static func hasChipRow(_ b: RDOverlayModel.Badge) -> Bool {
        return !chipTexts(b).isEmpty
    }

    static func headerWidth(_ b: RDOverlayModel.Badge, dropped: Int) -> CGFloat {
        // 标题字实测比 textWidth 的估计宽（SwiftUI 的中文标题约 1.2 倍）：只有标题单独撑宽、又没有数字 / 余量垫着的
        // 长标题（「已偏离，重算中」）才露出来，所以单独按 1.2 倍算一个下限
        var rest: CGFloat = 0
        if let n = b.numbers { rest += headerSpacing + textWidth(n, size: numbersSize, latin: 0.7) }
        if let m = b.margin { rest += headerSpacing + textWidth(m, size: marginSize) + 10 }
        if dropped > 0 { rest += headerSpacing + textWidth(RDText.droppedLines(dropped), size: marginSize) }
        let title = textWidth(b.title, size: titleSize)
        let base = paddingH + pipsWidth + headerSpacing
        let plain = base + title + rest
        // 有数字 / 余量的标题行，上面的老估计本来就偏大（测试里核对过）；只对纯标题行加这条下限
        return b.numbers == nil && b.margin == nil ? max(plain, base + 1.2 * title + 3 + rest) : plain
    }

    static func chipRowWidth(_ b: RDOverlayModel.Badge) -> CGFloat {
        let chips = chipTexts(b)
        guard !chips.isEmpty else { return 0 }
        // 「正在算」是小圈 + 字，比同样的字做成标签窄
        return paddingH + chips.map(chipWidth).reduce(0, +) + chipSpacing * CGFloat(chips.count - 1)
    }

    static func quizRowWidth(_ b: RDOverlayModel.Badge) -> CGFloat {
        guard b.quizMode else { return 0 }
        var w = paddingH + chipWidth(RDText.quizChip)
        if let q = b.quiz {
            w += chipSpacing + chipWidth(q == .onLine ? RDText.quizOnLine : RDText.quizOffLine)
        }
        return w
    }

    /// 面板至少要多宽，标题行 / 标签行才不被截断
    static func minWidth(badge: RDOverlayModel.Badge, dropped: Int) -> CGFloat {
        return max(RDOverlayGeometry.panelMinWidth, headerWidth(badge, dropped: dropped),
                   chipRowWidth(badge), quizRowWidth(badge))
    }

    static func lineHeight(_ size: CGFloat) -> CGFloat {
        return size * fontScale * lineHeightFactor
    }

    static func chipHeight() -> CGFloat {
        return lineHeight(chipSize) + 2 * chipPaddingV
    }

    /// 每行文字最多两行（`lineLimit(2)`；「回合末」三行）：估宽超过可用宽就多算一行
    static func rows(_ line: RDOverlayModel.Line, width: CGFloat) -> Int {
        let size = line.kind == .nextStep ? nextStepSize : lineSize
        let avail = width - paddingH - lineGlyphColumn
        let limit = line.kind == .leftover ? 3 : 2
        return min(limit, max(1, Int((textWidth(line.text, size: size) / max(1, avail)).rounded(.up))))
    }

    static let formulaSize: CGFloat = 14
    static let pieceGap: CGFloat = 7
    static let rowGap: CGFloat = 3

    /// 公式按词流式排：行首是小标签，每个词放不下就换行（和视图的 `RDFlowLayout` 同一套规则，估宽偏大）
    static func formulaRows(_ line: RDOverlayModel.Line, width: CGFloat) -> Int {
        let avail = width - paddingH - lineGlyphColumn
        var x: CGFloat = line.label.map { chipWidth($0) + pieceGap } ?? 0
        var rows = 1
        for p in line.pieces {
            let w = textWidth(p.text, size: formulaSize)
            if x > 0 && x + w > avail {
                rows += 1
                x = 0
            }
            x += w + pieceGap
        }
        return rows
    }

    static func blockHeight(_ line: RDOverlayModel.Line, width: CGFloat) -> CGFloat {
        if line.isFormula {
            let r = formulaRows(line, width: width)
            return CGFloat(r) * lineHeight(formulaSize) + CGFloat(r - 1) * rowGap
        }
        let size = line.kind == .nextStep ? nextStepSize : lineSize
        return CGFloat(rows(line, width: width)) * lineHeight(size)
    }

    static func height(badge: RDOverlayModel.Badge, lines: [RDOverlayModel.Line], width: CGFloat) -> CGFloat {
        var h = paddingV + max(lineHeight(titleSize), lineHeight(numbersSize))
        if hasChipRow(badge) { h += spacing + chipHeight() }
        if badge.quizMode { h += spacing + chipHeight() }
        if !lines.isEmpty {
            h += spacing + 1
            for line in lines {
                h += spacing + blockHeight(line, width: width)
            }
        }
        return h
    }
}

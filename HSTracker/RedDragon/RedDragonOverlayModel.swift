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
    }

    enum Status: Hashable {
        case computing, stale, truncated
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
        /// 结论不是当前局面的（过时 / 正在算）：整块变暗，不画标记
        var dimmed: Bool
    }

    enum LineKind: Equatable {
        case nextStep
        case branch(lethal: Bool)
        case missing
        case insufficient
        case danger
    }

    struct Line: Equatable {
        var kind: LineKind
        var text: String
    }

    /// 手牌上的标记。`index` 从 0 起、从左到右，`count` 是手牌张数（`BoardOverlayView.handCardPosition` 的参数）
    struct HandMark: Equatable {
        var entityId: Int
        var index: Int
        var count: Int
        /// L1 的必打 / 可选；只有序号没有高亮时为 nil
        var role: RDHandMark.Role?
        /// L2 的步骤序号（同一张牌可能出现在多步里）
        var steps: [Int]
    }

    struct BoardMark: Equatable {
        var entityId: Int
        var isEnemy: Bool
        var index: Int
        var count: Int
        var steps: [Int]
        /// 这格随从在某一步是目标（画圈）；否则只是攻击方
        var isTarget: Bool
    }

    var badge: Badge?
    var lines: [Line] = []
    var handMarks: [HandMark] = []
    var boardMarks: [BoardMark] = []
    /// 指向对方英雄的步骤
    var heroTargetSteps: [Int] = []

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
        let dimmed = hint.phase == .computing || hint.isStale
        guard let a = hint.analysis else {
            return RDOverlayModel(badge: Badge(title: RDText.assistantName, numbers: nil, margin: nil, tone: .neutral,
                                               tier: nil, statuses: [.computing], opponentSecrets: false,
                                               level: hint.revealLevel, maxLevel: hint.maxRevealLevel,
                                               quizMode: hint.quizMode, quiz: nil, dimmed: false))
        }

        var statuses: [Status] = []
        if hint.phase == .computing { statuses.append(.computing) }
        if hint.isStale { statuses.append(.stale) }
        if a.completeness == .truncated { statuses.append(.truncated) }

        let title: String
        let tone: Tone
        switch a.verdict {
        case .lethal: (title, tone) = (RDText.lethal, .lethal)
        case .lethalIfDraw: (title, tone) = (RDText.lethalIfDraw, .lethalIfDraw)
        case .notFound: (title, tone) = (RDText.notFound, .notFound)
        case .provenNotLethal: (title, tone) = (RDText.provenNotLethal, .provenNotLethal)
        }
        // 「最大伤害 / 敌方有效血量」。不斩杀时标题已经说了「不能 / 未搜到」，不再加「最大」两字，省出角标宽度
        let numbers = "\(a.maxDamage) / \(a.effectiveEnemyHealth)"
        let badge = Badge(title: title, numbers: numbers, margin: RDText.margin(a.margin), tone: tone,
                          tier: a.isLethal ? a.tier.map(RDText.tier) : nil, statuses: statuses,
                          opponentSecrets: a.opponentHasSecrets,
                          level: hint.revealLevel, maxLevel: hint.maxRevealLevel,
                          quizMode: hint.quizMode, quiz: hint.quizMode ? hint.quiz : nil, dimmed: dimmed)
        var model = RDOverlayModel(badge: badge)
        // 过时的结论只留角标：它的建议、手牌 / 场面排位都可能已经不对了
        guard !dimmed else { return model }

        let marksAllowed = !hint.quizMode
        let level = hint.revealLevel
        if marksAllowed && level >= .order, let first = a.steps.first {
            model.lines.append(Line(kind: .nextStep,
                                    text: RDText.nextStep(RDText.step(first, cardName: cardName),
                                                          total: a.totalSteps, shown: a.steps.count)))
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

        guard marksAllowed && level >= .cards else { return model }
        let handIndex = Dictionary(a.handOrder.enumerated().map { ($0.element, $0.offset) },
                                   uniquingKeysWith: { first, _ in first })
        var hand: [Int: HandMark] = [:]
        for m in a.handMarks {
            guard let i = handIndex[m.entityId] else { continue }
            hand[m.entityId] = HandMark(entityId: m.entityId, index: i, count: a.handOrder.count,
                                        role: m.role, steps: [])
        }
        if level >= .order {
            for s in a.steps where s.kind == .playFromHand {
                guard let id = s.handEntityId, let i = handIndex[id] else { continue }
                hand[id, default: HandMark(entityId: id, index: i, count: a.handOrder.count,
                                           role: nil, steps: [])].steps.append(s.index)
            }
            var board: [Int: BoardMark] = [:]
            for m in a.boardMarks {
                let slots = m.isEnemy ? a.opponentBoardSlots : a.boardSlots
                guard let i = slots.firstIndex(of: m.entityId) else { continue }
                var mark = board[m.entityId] ?? BoardMark(entityId: m.entityId, isEnemy: m.isEnemy, index: i,
                                                          count: slots.count, steps: [], isTarget: false)
                if !mark.steps.contains(m.stepIndex) { mark.steps.append(m.stepIndex) }
                mark.isTarget = mark.isTarget || m.role == .target
                board[m.entityId] = mark
            }
            model.boardMarks = board.values.sorted { ($0.isEnemy ? 1 : 0, $0.index) < ($1.isEnemy ? 1 : 0, $1.index) }
            model.heroTargetSteps = a.steps.filter { $0.target == .enemyHero }.map { $0.index }
        }
        model.handMarks = hand.values.sorted { $0.index < $1.index }
        return model
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

    /// 场面标记的中心：随从格的下沿。入场序号挂在上沿，两者不重叠
    static func boardMarkCenter(_ rect: CGRect, canvas: CGSize) -> CGPoint {
        return CGPoint(x: rect.midX, y: rect.maxY - badgeSize(canvas) * 0.2)
    }

    /// 对方英雄头像左下角（头像约在画面正中、0.19 H；武器徽章在 0.144 H 更靠左，场面入场序号在 0.29 H 以下）
    static func heroTargetCenter(_ canvas: CGSize) -> CGPoint {
        return CGPoint(x: canvas.width / 2 - canvas.height * 0.075, y: canvas.height * 0.235)
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
    /// 5. 全都放不下：不画面板（手牌 / 场面标记照画）。
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

        var variants = lineCaps(lines.count).map { (keep: $0, hidesNumbers: false) }
        if badge.numbers != nil {
            variants.append((keep: 0, hidesNumbers: true))
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

    /// 按重要度留 `keep` 行，留下的保持原来的顺序
    static func compact(_ lines: [RDOverlayModel.Line], keep: Int) -> [RDOverlayModel.Line] {
        guard keep < lines.count else { return lines }
        func rank(_ k: RDOverlayModel.LineKind) -> Int {
            switch k {
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
            case .stale: out.append(RDText.stale)
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
        var w = paddingH + pipsWidth + headerSpacing + textWidth(b.title, size: titleSize)
        if let n = b.numbers { w += headerSpacing + textWidth(n, size: numbersSize, latin: 0.7) }
        if let m = b.margin { w += headerSpacing + textWidth(m, size: marginSize) + 10 }
        if dropped > 0 { w += headerSpacing + textWidth(RDText.droppedLines(dropped), size: marginSize) }
        return w
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

    /// 每行文字最多两行（`lineLimit(2)`）：估宽超过可用宽就算两行
    static func rows(_ line: RDOverlayModel.Line, width: CGFloat) -> Int {
        let size = line.kind == .nextStep ? nextStepSize : lineSize
        return textWidth(line.text, size: size) > width - paddingH - lineGlyphColumn ? 2 : 1
    }

    static func height(badge: RDOverlayModel.Badge, lines: [RDOverlayModel.Line], width: CGFloat) -> CGFloat {
        var h = paddingV + max(lineHeight(titleSize), lineHeight(numbersSize))
        if hasChipRow(badge) { h += spacing + chipHeight() }
        if badge.quizMode { h += spacing + chipHeight() }
        if !lines.isEmpty {
            h += spacing + 1
            for line in lines {
                let size = line.kind == .nextStep ? nextStepSize : lineSize
                h += spacing + CGFloat(rows(line, width: width)) * lineHeight(size)
            }
        }
        return h
    }
}

//
//  RedDragonOverlayView.swift
//  HSTracker
//
//  红龙辅助的 overlay：只有左下角的判定面板（手牌 / 场面上的框和序号 10-06 删掉了）。
//  挂在 `RootOverlayView` 的固定像素层（canvas = 炉石窗口的真实像素）：面板让位用的手牌 / 场面几何
//  （`BoardOverlayView.handCardPosition`、`playerTop` 等）都在这一层；
//  面板的尺寸按窗口高 / 1080 缩放，效果等同于缩放层。
//
//  状态只从 `RedDragonAssistant.subscribe` 来，到这里再投一次 `main.async`、在同一个 block 里一次提交
//  （见 `RedDragonOverlayViewModel.receive`）。视图只观察自己的 view model 和记牌器位置（`RDTrackerObstacles`，
//  去重后只在影响让位的值变了时发）：记牌器内容刷新不会让它重算，它变了也不会让 `RootOverlayView` 重算。不接鼠标，不报交互 / 悬停区域，窗口保持点击穿透。
//  悬停手牌时游戏放大的那张牌由 overlay 根上的 opacity mask 整块挖掉（`setCardOpacityMask` 的 hand 分支），
//  这里画在同一个被 mask 的 ZStack 里，所以标记不会盖住它。
//

import AppKit
import Combine
import SwiftUI
@testable import RedDragonCore

final class RedDragonOverlayViewModel: ObservableObject {

    @Published private(set) var model = RDOverlayModel.hidden
    /// 记牌器的位置（面板让位用）。单独一个 ObservableObject：只在影响让位的值变了时才发
    let trackers: RDTrackerObstacles

    private let cardName: (String) -> String
    private var pending: RedDragonHint?
    private var flushScheduled = false
    private weak var assistant: RedDragonAssistant?
    private var subscription: Int?
    /// 提交了几次（测试 / 性能数据用）
    private(set) var commits = 0

    /// 订阅 assistant（多订阅，不占 `onChange`；释放时退订）。接的是 `RedDragonAssistant.shared` 时顺带启动热键。
    /// `trackers`：两个记牌器的 view model，面板据它们的位置让位
    init(assistant: RedDragonAssistant? = .shared, trackers: [TrackerPanelViewModel] = [],
         cardName: @escaping (String) -> String = { Cards.any(byId: $0)?.name ?? $0 }) {
        self.cardName = cardName
        self.trackers = RDTrackerObstacles(trackers: trackers)
        guard let assistant else { return }
        self.assistant = assistant
        subscription = assistant.subscribe { [weak self] hint in
            self?.receive(hint)
        }
        receive(assistant.hint)
        if assistant === RedDragonAssistant.shared {
            RedDragonHotkeys.shared.start()
        }
    }

    deinit {
        guard let token = subscription, let assistant else { return }
        if Thread.isMainThread {
            assistant.unsubscribe(token)
        } else {
            DispatchQueue.main.async { [weak assistant] in
                assistant?.unsubscribe(token)
            }
        }
    }

    /// 主线程（assistant 的提交 block、设置通知、热键）。再投一次 `main.async`：一个 runloop 里连着来的几份
    /// （例如「正在算」紧跟「结果」）只提交最后一份，提交在同一个 block 里一次写完
    func receive(_ hint: RedDragonHint) {
        pending = hint
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.flush()
        }
    }

    private func flush() {
        flushScheduled = false
        guard let hint = pending else { return }
        pending = nil
        let next = RDOverlayModel.make(hint, cardName: cardName)
        guard next != model else { return }
        model = next
        commits += 1
    }
}

/// 两个记牌器占的位置。订阅它们 view model 的 isShown / left / top / height / scaling（拖动、改高度时
/// 这些 @Published 每一步都变，存盘要等松手）和卡牌尺寸设置；去重后才发，记牌器内容刷新不会让红龙重算。
/// 变化先攒着，下一跳 main.async 里一次提交（同一 runloop 内的 left / top 只提交一次）
final class RDTrackerObstacles: ObservableObject {
    struct State: Equatable {
        var placements: [RDOverlayGeometry.TrackerPlacement]
        var cardSize: CardSize
    }

    @Published private(set) var state: State
    /// 提交了几次（测试用）
    private(set) var commits = 0
    private var cancellables: [AnyCancellable] = []
    private var cardSizeObserver: NSObjectProtocol?

    init(trackers: [TrackerPanelViewModel]) {
        state = State(placements: trackers.map(Self.placement), cardSize: Settings.cardSize)
        for (i, vm) in trackers.enumerated() {
            let isOpponent = vm.playerType == .opponent
            Publishers.CombineLatest(Publishers.CombineLatest3(vm.$isShown, vm.$left, vm.$top),
                                     Publishers.CombineLatest(vm.$height, vm.$scaling))
                .map { a, b in
                    RDOverlayGeometry.TrackerPlacement(isOpponent: isOpponent, isShown: a.0, left: a.1, top: a.2,
                                                       height: b.0, scaling: b.1)
                }
                .removeDuplicates()
                .sink { [weak self] p in
                    self?.stage { $0.placements[i] = p }
                }
                .store(in: &cancellables)
        }
        cardSizeObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name(rawValue: Settings.card_size), object: nil, queue: .main) { [weak self] _ in
                self?.stage { $0.cardSize = Settings.cardSize }
            }
    }

    deinit {
        if let cardSizeObserver {
            NotificationCenter.default.removeObserver(cardSizeObserver)
        }
    }

    private static func placement(_ vm: TrackerPanelViewModel) -> RDOverlayGeometry.TrackerPlacement {
        return RDOverlayGeometry.TrackerPlacement(isOpponent: vm.playerType == .opponent, isShown: vm.isShown,
                                                  left: vm.left, top: vm.top, height: vm.height, scaling: vm.scaling)
    }

    private var staged: State?
    private var flushScheduled = false

    /// 主线程（记牌器的 @Published 在主线程写）。拖动一步会先后改 left、top：先攒着，下一跳 main.async 一次提交
    private func stage(_ change: (inout State) -> Void) {
        var next = staged ?? state
        change(&next)
        staged = next
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.flush()
        }
    }

    private func flush() {
        flushScheduled = false
        guard let next = staged else { return }
        staged = nil
        guard next != state else { return }
        state = next
        commits += 1
    }

    func boxes(canvas: CGSize) -> [CGRect] {
        return state.placements.compactMap { RDOverlayGeometry.trackerBox($0, cardSize: state.cardSize, canvas: canvas) }
    }
}

struct RedDragonOverlayView: View {
    @ObservedObject var viewModel: RedDragonOverlayViewModel
    @ObservedObject private var trackers: RDTrackerObstacles
    let canvasSize: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    #if DEBUG
    /// body 求值次数 / 被父视图重新构造的次数（测试量「无关刷新不重算」用）
    static var bodyEvaluations = 0
    static var constructions = 0
    /// 最近一次 body 算出的面板位置（测试核对让位用）
    static var lastPanelLayout: RDOverlayGeometry.PanelLayout?
    #endif

    init(viewModel: RedDragonOverlayViewModel, canvasSize: CGSize) {
        self.viewModel = viewModel
        self._trackers = ObservedObject(wrappedValue: viewModel.trackers)
        self.canvasSize = canvasSize
        #if DEBUG
        Self.constructions += 1
        #endif
    }

    var body: some View {
        #if DEBUG
        Self.bodyEvaluations += 1
        #endif
        let model = viewModel.model
        let usable = RootOverlayView.isUsableCanvas(canvasSize)
        let layout: RDOverlayGeometry.PanelLayout? = usable ? model.badge.flatMap {
            RDOverlayGeometry.panelLayout(canvas: canvasSize, badge: $0, lines: model.lines,
                                          trackers: trackers.boxes(canvas: canvasSize))
        } : nil
        #if DEBUG
        Self.lastPanelLayout = layout
        #endif
        return ZStack(alignment: .topLeading) {
            Color.clear
            if model.isVisible && usable {
                if let badge = model.badge, let layout {
                    RDPanel(badge: badge, layout: layout, canvas: canvasSize)
                }
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
        .animation(RDStyle.animation(reduceMotion: reduceMotion), value: model)
        .allowsHitTesting(false)
    }
}

// MARK: - 样式（借自现有 overlay 组件，见任务书执行结果「借用样式表」）

enum RDStyle {
    static let panelFill = TrackerBarStyle.base.opacity(0.9)
    static let panelLine = TrackerBarStyle.line
    static let text = TrackerBarStyle.text
    static let dimText = TrackerBarStyle.text.opacity(TrackerBarStyle.dimContent + 0.15)
    static let gold = TrackerBarStyle.gold
    static let step = TrackerBarStyle.star
    static let target = TrackerBarStyle.flame
    static let lethal = TrackerBarStyle.highlight(.green) ?? .green
    static let draw = TrackerBarStyle.highlight(.orange) ?? .orange
    static let optional = TrackerBarStyle.highlight(.teal) ?? .teal
    static let wrong = Color(red: 0xE5 / 255, green: 0x48 / 255, blue: 0x3C / 255)

    static func tone(_ t: RDOverlayModel.Tone) -> Color {
        switch t {
        case .lethal: return lethal
        case .lethalIfDraw: return draw
        case .notFound: return gold
        case .provenNotLethal: return skullGrey
        case .neutral: return gold
        case .setup: return optional
        case .doomed: return wrong
        }
    }

    static let skullGrey = TrackerBarStyle.skull.opacity(0.75)

    /// 面板文字：主题字体（简中是 AR LisuGB），数字用 Belwe —— 和记牌器面板同一套
    static func label(_ u: CGFloat, _ size: CGFloat) -> Font {
        return Font.custom("AR LisuGB Medium", size: size * fontScale * u)
    }

    static func digits(_ u: CGFloat, _ size: CGFloat) -> Font {
        return TrackerBarStyle.digits(u, size: size * fontScale)
    }

    /// 面板字号整体放大（1080 下标题约 19 px，和计数器的 15 px ChunkFive 数字同一量级）
    static let fontScale: CGFloat = RDPanelMetrics.fontScale

    /// `TrackerMotion.duration` 的同一条曲线；系统「减弱动态效果」打开时不动
    static func animation(reduceMotion: Bool) -> Animation? {
        guard !reduceMotion, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return nil }
        return .easeOut(duration: TrackerMotion.duration)
    }
}

// MARK: - 判定面板

/// 摆在 `panelLayout` 算出的位置（底边对齐）；内容按 u × 缩放画
struct RDPanel: View {
    let badge: RDOverlayModel.Badge
    let layout: RDOverlayGeometry.PanelLayout
    let canvas: CGSize

    var body: some View {
        let frame = layout.frame
        var badge = badge
        if layout.hidesNumbers { badge.numbers = nil }
        return RDPanelContent(badge: badge, lines: layout.lines, dropped: layout.droppedLines,
                              u: RDOverlayGeometry.unit(canvas) * layout.scale)
            .frame(width: frame.width, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .opacity(badge.dimmed ? 0.6 : 1)
            .alignmentGuide(.leading) { _ in -frame.minX }
            .alignmentGuide(.top) { d in -(frame.maxY - d.height) }
            .transition(.opacity)
    }
}

/// 面板内容。尺寸常数和 `RDPanelMetrics` 一一对应（那边据此估宽高、决定放哪）
struct RDPanelContent: View {
    let badge: RDOverlayModel.Badge
    let lines: [RDOverlayModel.Line]
    let dropped: Int
    let u: CGFloat

    private typealias M = RDPanelMetrics

    var body: some View {
        content(u)
    }

    private func content(_ u: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: M.spacing * u) {
            headerRow(u)
            if M.hasChipRow(badge) {
                chipRow(u)
            }
            if badge.quizMode {
                quizRow(u)
            }
            if !lines.isEmpty {
                Rectangle().fill(TrackerBarStyle.rowLine).frame(height: 1)
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    RDLineView(line: line, u: u)
                }
            }
        }
        .padding(.vertical, M.paddingV / 2 * u)
        .padding(.leading, 12 * u)
        .padding(.trailing, (M.paddingH - 12) * u)
        .background(
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8 * u).fill(RDStyle.panelFill)
                // 左缘一道判定色，像记牌器行的高亮条
                RoundedRectangle(cornerRadius: 1.5 * u)
                    .fill(RDStyle.tone(badge.tone))
                    .frame(width: 3 * u)
                    .padding(.vertical, 6 * u)
                    .padding(.leading, 3 * u)
            }
        )
        .overlay(RoundedRectangle(cornerRadius: 8 * u).stroke(RDStyle.panelLine, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.55), radius: 4 * u, x: 0, y: 1 * u)
    }

    private func headerRow(_ u: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 6 * u) {
            RDLevelPips(level: badge.level, maxLevel: badge.maxLevel, quizMode: badge.quizMode, u: u)
            Text(verbatim: badge.title)
                .font(RDStyle.label(u, 16))
                .foregroundColor(RDStyle.tone(badge.tone))
                .fixedSize()
            if let numbers = badge.numbers {
                Text(verbatim: numbers)
                    .font(RDStyle.digits(u, 15))
                    .foregroundColor(RDStyle.text)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            if let margin = badge.margin {
                Text(verbatim: margin)
                    .font(RDStyle.label(u, 12))
                    .foregroundColor(RDStyle.tone(badge.tone))
                    .fixedSize()
                    .padding(.horizontal, 5 * u)
                    .padding(.vertical, 1 * u)
                    .background(Capsule().fill(RDStyle.tone(badge.tone).opacity(0.18)))
            }
            if dropped > 0 {
                Text(verbatim: RDText.droppedLines(dropped))
                    .font(RDStyle.label(u, M.marginSize))
                    .foregroundColor(RDStyle.dimText)
                    .fixedSize()
            }
            Spacer(minLength: 0)
        }
    }

    private func chipRow(_ u: CGFloat) -> some View {
        HStack(spacing: 5 * u) {
            if let tier = badge.tier {
                RDChip(text: tier, color: RDStyle.gold, filled: false, u: u)
            }
            ForEach(badge.statuses, id: \.self) { s in
                switch s {
                case .computing:
                    HStack(spacing: 3 * u) {
                        RDSpinner(u: u)
                        Text(verbatim: RDText.computing).font(RDStyle.label(u, 11)).foregroundColor(RDStyle.dimText)
                    }
                case .truncated:
                    RDChip(text: RDText.truncated, color: RDStyle.draw, filled: false, u: u)
                }
            }
            if badge.opponentSecrets {
                RDChip(text: RDText.opponentSecrets, color: RDStyle.step, filled: true, u: u)
            }
            Spacer(minLength: 0)
        }
    }

    private func quizRow(_ u: CGFloat) -> some View {
        HStack(spacing: 5 * u) {
            RDChip(text: RDText.quizChip, color: RDStyle.optional, filled: false, u: u)
            if let q = badge.quiz {
                RDChip(text: q == .onLine ? RDText.quizOnLine : RDText.quizOffLine,
                       color: q == .onLine ? RDStyle.lethal : RDStyle.wrong, filled: true, u: u)
                    .transition(.scale.combined(with: .opacity))
            }
            Spacer(minLength: 0)
        }
    }
}

private struct RDLineView: View {
    let line: RDOverlayModel.Line
    let u: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5 * u) {
            // 公式的后续阶段行不带标签，也不重复箭头：缩进对齐在第一行下面
            Text(verbatim: line.isFormula && line.label == nil ? "" : glyph)
                .font(RDStyle.label(u, 11))
                .foregroundColor(color)
                .frame(width: 11 * u)
            if line.isFormula {
                // 完整公式：流式多行排版，一步不截
                RDFlowLayout(hSpacing: RDPanelMetrics.pieceGap * u, vSpacing: RDPanelMetrics.rowGap * u) {
                    if let label = line.label {
                        RDChip(text: label, color: color, filled: true, u: u)
                    }
                    ForEach(Array(line.pieces.enumerated()), id: \.offset) { _, p in
                        RDPieceView(piece: p, u: u)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(verbatim: line.text)
                    .font(RDStyle.label(u, line.kind == .nextStep ? 14 : 13))
                    .foregroundColor(line.kind == .nextStep ? RDStyle.text : textColor)
                    .lineLimit(line.kind == .leftover ? 3 : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var glyph: String {
        switch line.kind {
        case .nextStep, .formula: return "▶"
        case .branch, .leftover: return "↳"
        case .missing: return "◇"
        case .insufficient: return "!"
        case .danger: return "⚠"
        }
    }

    private var color: Color {
        switch line.kind {
        case .nextStep: return RDStyle.step
        case .formula(let setup): return setup ? RDStyle.optional : RDStyle.lethal
        case .leftover: return RDStyle.dimText
        case .branch(let lethal): return lethal ? RDStyle.lethal : RDStyle.dimText
        case .missing: return RDStyle.optional
        case .insufficient: return RDStyle.draw
        case .danger: return RDStyle.target
        }
    }

    private var textColor: Color {
        switch line.kind {
        case .danger: return RDStyle.target
        case .branch(let lethal): return lethal ? RDStyle.text : RDStyle.dimText
        case .leftover: return RDStyle.dimText
        default: return RDStyle.text
        }
    }
}

/// 公式里的一步：已走的划掉变暗，下一步高亮，其余正常，说明（抽到什么才继续）橙色小字
private struct RDPieceView: View {
    let piece: RDOverlayModel.Piece
    let u: CGFloat

    /// 没走到的步骤里，乐队经理拿的牌换成金色；已走的整段一起变暗
    private func accented(_ base: Color) -> Text {
        guard let accent = piece.accent, let r = piece.text.range(of: accent) else {
            return Text(verbatim: piece.text).foregroundColor(base)
        }
        return Text(verbatim: String(piece.text[..<r.lowerBound])).foregroundColor(base)
            + Text(verbatim: accent).foregroundColor(RDStyle.gold)
            + Text(verbatim: String(piece.text[r.upperBound...])).foregroundColor(base)
    }

    var body: some View {
        switch piece.state {
        case .done:
            Text(verbatim: piece.text)
                .font(RDStyle.label(u, RDPanelMetrics.formulaSize))
                .foregroundColor(RDStyle.dimText)
                .strikethrough(true, color: RDStyle.dimText)
                .lineLimit(1)
                .fixedSize()
        case .next:
            accented(RDStyle.step)
                .font(RDStyle.label(u, RDPanelMetrics.formulaSize))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 3 * u)
                .background(RoundedRectangle(cornerRadius: 3 * u).fill(RDStyle.step.opacity(0.22)))
                .padding(.horizontal, -3 * u)
        case .pending:
            accented(RDStyle.text)
                .font(RDStyle.label(u, RDPanelMetrics.formulaSize))
                .lineLimit(1)
                .fixedSize()
        case .note:
            Text(verbatim: piece.text)
                .font(RDStyle.label(u, 12))
                .foregroundColor(RDStyle.draw)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

/// 从左到右排、放不下就换行。每个子视图取自己的理想尺寸（`fixedSize`），宽度到提议宽度为止
private struct RDFlowLayout: Layout {
    var hSpacing: CGFloat
    var vSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        return arrange(proposal.width ?? .infinity, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrange(bounds.width, subviews).frames
        for (i, f) in frames.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY),
                              anchor: .topLeading, proposal: ProposedViewSize(f.size))
        }
    }

    private func arrange(_ maxWidth: CGFloat, _ subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        var frames: [CGRect] = []
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + vSpacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + hSpacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - hSpacing)
        }
        return (CGSize(width: widest, height: y + rowHeight), frames)
    }
}

private struct RDChip: View {
    let text: String
    let color: Color
    let filled: Bool
    let u: CGFloat

    var body: some View {
        Text(verbatim: text)
            .font(RDStyle.label(u, 11))
            .foregroundColor(filled ? TrackerBarStyle.base : color)
            .lineLimit(1)
            .padding(.horizontal, 6 * u)
            .padding(.vertical, 1.5 * u)
            .background(Capsule().fill(filled ? color : Color.clear))
            .overlay(Capsule().stroke(color.opacity(filled ? 0 : 0.7), lineWidth: 1))
    }
}

/// 三个点：亮到第几档；超过本结论封顶的档画空心。答题模式不揭示，三点全暗
private struct RDLevelPips: View {
    let level: RDRevealLevel
    let maxLevel: RDRevealLevel
    let quizMode: Bool
    let u: CGFloat

    var body: some View {
        HStack(spacing: 2.5 * u) {
            ForEach(RDRevealLevel.allCases, id: \.rawValue) { l in
                Circle()
                    .fill(!quizMode && l <= level ? RDStyle.step : Color.clear)
                    .overlay(Circle().stroke(l <= maxLevel ? RDStyle.step.opacity(0.8) : RDStyle.dimText.opacity(0.5),
                                             lineWidth: 1))
                    .frame(width: 7 * u, height: 7 * u)
            }
        }
    }
}

/// 「正在算」的小圈。SpinningIndicator 是 NSView，离屏渲染不出来，这里用 SwiftUI 画；减弱动态效果时不转
private struct RDSpinner: View {
    let u: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @SwiftUI.State private var turning = false

    var body: some View {
        Circle()
            .trim(from: 0.12, to: 0.82)
            .stroke(RDStyle.dimText, style: StrokeStyle(lineWidth: 1.5 * u, lineCap: .round))
            .frame(width: 9 * u, height: 9 * u)
            .rotationEffect(.degrees(turning ? 360 : 0))
            .onAppear {
                guard RDStyle.animation(reduceMotion: reduceMotion) != nil else { return }
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                    turning = true
                }
            }
    }
}


//  GameView.swift
//  Yirmibeş — oyun ekranı

import SwiftUI

struct GameView: View {
    @ObservedObject var game: GameEngine
    var onBack: () -> Void
    var onSkipDemo: (() -> Void)? = nil
    @EnvironmentObject private var language: AppLanguage
    @State private var showRules = false
    @State private var showPause = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                TopBar(
                    round: game.round,
                    isDemo: game.isDemo,
                    onSkipDemo: onSkipDemo,
                    showRules: $showRules,
                    onPause: {
                        guard !game.isDemo else { return }
                        game.setPaused(true)
                        showPause = true
                    }
                )

                Spacer(minLength: 4)

                HStack(spacing: 6) {
                    ForEach(1..<4, id: \.self) { i in
                        SeatView(player: game.players[i],
                                 isHolder: game.holder == i,
                                 isActing: game.actingPlayer == i)
                    }
                }

                Spacer(minLength: 8)

                feltPanel

                Spacer(minLength: 8)

                if game.isDemo {
                    CoachBubble(text: displayFeed)
                } else {
                    Text(displayFeed)
                        .font(Typo.textBodySm())
                        .foregroundColor(.ivory.opacity(0.78))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                }

                Spacer(minLength: 8)

                handSection
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, Metrics.screenInsetH)
            .padding(.bottom, Metrics.gameHandBottomInset)
            .opacity(game.demoAwaitingIntro ? 0.35 : 1)
            .allowsHitTesting(!showPause)

            if game.demoAwaitingIntro {
                DemoIntroOverlay(
                    onStart: { game.beginDemoPlay() },
                    onSkip: { onSkipDemo?() }
                )
                .zIndex(5)
            }

            if showRules {
                HowToPlayLightbox(isPresented: $showRules)
                    .zIndex(10)
            }

            if showPause {
                PauseOverlay(
                    onContinue: {
                        showPause = false
                        game.setPaused(false)
                    },
                    onQuit: {
                        showPause = false
                        game.quitToMenu()
                    }
                )
                .zIndex(20)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: showPause)
        #if os(macOS)
        .onExitCommand(perform: handleExitCommand)
        #endif
    }

    #if os(macOS)
    private func handleExitCommand() {
        if showRules {
            showRules = false
        } else if showPause {
            showPause = false
            game.setPaused(false)
        } else if game.isDemo {
            onSkipDemo?()
        } else {
            game.setPaused(true)
            showPause = true
        }
    }
    #endif

    private var displayFeed: String {
        _ = language.choice
        return game.displayMessage
    }

    // MARK: Çuha
    private var feltPanel: some View {
        VStack(spacing: 14) {
            HStack(spacing: 0) {
                ForEach(Array(game.order.enumerated()), id: \.offset) { pair in
                    SlotView(played: game.table.indices.contains(pair.offset)
                                     ? game.table[pair.offset] : nil,
                             owner: game.players[pair.element].name,
                             isHolder: pair.element == game.holder,
                             isActing: game.actingPlayer == pair.element,
                             flipped: game.revealed,
                             delay: Double(pair.offset) * Rules.flipStep)
                    .frame(maxWidth: .infinity)
                }
            }

            ThresholdGauge(sum: game.tableSum,
                           shown: game.sumShown,
                           outcome: game.outcome,
                           holderName: game.players.isEmpty ? "" : game.players[game.holder].name)
        }
        .padding(.horizontal, 8)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .background(
            LinearGradient(colors: [.white.opacity(0.05), .black.opacity(0.26)],
                           startPoint: .top, endPoint: .bottom)
        )
        .overlay(Rectangle().fill(warmth))
        .overlay(Rectangle().strokeBorder(Color.brass.opacity(0.45), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 8)
        .contentShape(Rectangle())
        .onTapGesture { game.skipHold() }
        .animation(.easeOut(duration: 0.4), value: game.sumShown)
    }

    private var warmth: Color {
        guard game.sumShown, let outcome = game.outcome else { return Color.clear }
        switch outcome {
        case .over:  return Color.brass.opacity(0.13)
        case .exact, .cap: return Color.ivory.opacity(0.09)
        case .under: return Color.clear
        }
    }

    // MARK: El
    private var handSection: some View {
        VStack(spacing: 0) {
            handStatsRow
                .font(Typo.labelUI())
                .tracking(1.4)
                .foregroundColor(.ivory.opacity(0.55))
                .padding(.bottom, 16)

            HandFan(
                cards: game.me.hand,
                enabled: game.isMyTurn,
                highlight: game.highlightTarget
            ) { card in game.play(card) }
                .frame(height: handAreaHeight)
        }
    }

    /// El sayısı + toplam üstte; değer/ceza alt satırda (ES/FR/DE uzun etiketler sığar).
    private var handStatsRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(L10n.handCount(game.me.hand.count))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text("\(game.me.score)")
                    .font(Typo.displayBrand(bold: true))
                    .foregroundColor(.ivory.opacity(0.9))
            }
            Text(L10n.valuePenalty(value: game.me.handValue, penalty: game.me.penalty))
                .foregroundColor(.ivory.opacity(0.45))
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var handAreaHeight: CGFloat {
        // Eski (236/132) ile sıkı (196/108) arası — VALUE satırına yakın ama yapışık değil.
        game.me.hand.count > Metrics.handSingleRowMax ? 212 : 118
    }
}

private struct DemoIntroOverlay: View {
    let onStart: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()

            VStack(spacing: 16) {
                Text(L10n.demoIntroTitle)
                    .font(Typo.displayTitle(bold: true))
                    .foregroundColor(.brassHi)
                    .multilineTextAlignment(.center)

                Text(L10n.demoIntroBody)
                    .font(Typo.textBodySm())
                    .foregroundColor(.ivory.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 8)

                BrassButton(title: L10n.demoStart, action: onStart)

                Button(L10n.demoSkip, action: onSkip)
                    .font(Typo.labelCaption(bold: true))
                    .tracking(1.2)
                    .foregroundColor(.brass.opacity(0.85))
                    .padding(.top, 4)
            }
            .padding(22)
            .background(Color(hex: 0x0A241C))
            .overlay(Rectangle().strokeBorder(Color.brass.opacity(0.5), lineWidth: 1))
            .padding(.horizontal, 20)
        }
    }
}

/// Demo yönlendirme konuşma balonu.
private struct CoachBubble: View {
    let text: String

    var body: some View {
        VStack(spacing: 0) {
            Text(text)
                .font(Typo.textBodySm())
                .foregroundColor(Color(hex: 0x1A1208))
                .multilineTextAlignment(.center)
                .lineLimit(5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.brassHi.opacity(0.95))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.brassDk.opacity(0.5), lineWidth: 1)
                )

            BubbleTail()
                .fill(Color.brassHi.opacity(0.95))
                .frame(width: 16, height: 10)
                .offset(y: -1)
        }
        .padding(.horizontal, 8)
        .animation(.easeInOut(duration: 0.25), value: text)
    }
}

private struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX - 7, y: 0))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX + 7, y: 0))
        path.closeSubpath()
        return path
    }
}

// MARK: - Üst şerit
private struct TopBar: View {
    let round: Int
    var isDemo: Bool
    var onSkipDemo: (() -> Void)?
    @Binding var showRules: Bool
    var onPause: () -> Void

    var body: some View {
        AppChromeBar(showHowToPlay: $showRules) {
            Text(L10n.round(round, of: isDemo ? GameEngine.demoRounds : Rules.rounds))
                .font(Typo.labelUI(bold: true))
                .tracking(1.4)
                .foregroundColor(.brass)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        } trailing: {
            if isDemo {
                Button {
                    onSkipDemo?()
                } label: {
                    Text(L10n.demoSkip)
                        .font(Typo.labelCaption(bold: true))
                        .tracking(0.6)
                        .foregroundColor(.brass.opacity(0.9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 8)
                        .frame(height: Metrics.topBarControl)
                        .overlay(
                            Rectangle().strokeBorder(Color.brass.opacity(0.45), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.demoSkip)
            } else {
                TopBarIconButton(
                    systemName: "pause.fill",
                    accessibilityLabel: L10n.pauseTitle,
                    action: onPause
                )
            }
        }
    }
}

// MARK: - Pause
private struct PauseOverlay: View {
    @ObservedObject private var settings = AppSettings.shared
    let onContinue: () -> Void
    let onQuit: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()

            VStack(spacing: 0) {
                Text(L10n.pauseTitle)
                    .font(Typo.displayTitle(bold: true))
                    .foregroundColor(.brassHi)
                    .padding(.bottom, 18)

                Toggle(isOn: $settings.soundEnabled) {
                    Text(L10n.settingsSound)
                        .font(Typo.labelUI(bold: true))
                        .foregroundColor(.ivory)
                }
                .tint(.brass)
                .padding(.horizontal, 4)
                .padding(.bottom, 20)

                BrassButton(title: L10n.pauseContinue, action: onContinue)
                    .keyboardShortcut(.defaultAction)

                Button(action: onQuit) {
                    Text(L10n.pauseQuit)
                        .font(Typo.labelUI(bold: true))
                        .tracking(1.4)
                        .foregroundColor(.lacLit.opacity(0.95))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .overlay(Rectangle().strokeBorder(Color.lacLit.opacity(0.45), lineWidth: 1))
                }
                .buttonStyle(PressDownStyle())
                .keyboardShortcut(.cancelAction)
                .padding(.top, 10)
            }
            .padding(22)
            .background(Color(hex: 0x0A241C))
            .overlay(Rectangle().strokeBorder(Color.brass.opacity(0.5), lineWidth: 1))
            .padding(.horizontal, 28)
        }
    }
}

// MARK: - Rakip koltuğu
private struct SeatView: View {
    let player: Player
    let isHolder: Bool
    let isActing: Bool

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                if isHolder {
                    Text("♛")
                        .font(.system(size: 9))
                        .foregroundColor(.brass)
                        .offset(y: -12)
                }
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: 0x2A8D6B), Color(hex: 0x0B3A2C)],
                                         center: .init(x: 0.35, y: 0.25),
                                         startRadius: 1, endRadius: 28))
                    .frame(width: 26, height: 26)
                    .overlay(Circle().strokeBorder(
                        isHolder ? Color.brassHi : Color.brass.opacity(0.45),
                        lineWidth: isHolder ? 1.5 : 1))
                Text(String(player.name.prefix(1)))
                    .font(Typo.displayCaption()).foregroundColor(.ivory)
            }
            .frame(height: 34)
            .padding(.top, 1)

            Text(player.name)
                .font(Typo.label(Typo.caption - 1, bold: true))
                .foregroundColor(.ivory)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 2) {
                    Text("\(player.hand.count)")
                        .font(Typo.display(Typo.caption, bold: false))
                        .foregroundColor(.brassHi)
                    Text(L10n.cards)
                        .font(Typo.label(Typo.caption - 2))
                        .tracking(0.8)
                        .foregroundColor(.ivory.opacity(0.5))
                        .lineLimit(1)
                }
                VStack(spacing: 0) {
                    Text("\(player.hand.count)")
                        .font(Typo.display(Typo.caption, bold: false))
                        .foregroundColor(.brassHi)
                    Text(L10n.cards)
                        .font(Typo.label(Typo.caption - 2))
                        .tracking(0.8)
                        .foregroundColor(.ivory.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .padding(.horizontal, 2)
        .background(isHolder ? Color.brass.opacity(0.11) : Color.black.opacity(0.22))
        .overlay(Rectangle().strokeBorder(
            isHolder ? Color.brass : Color.white.opacity(0.07), lineWidth: 1))
        .overlay {
            if isActing {
                Rectangle().strokeBorder(Color.ivory.opacity(0.35), lineWidth: 1).padding(2)
            }
        }
        .animation(.easeOut(duration: 0.25), value: isHolder)
    }
}

// MARK: - Masa yuvası
private struct SlotView: View {
    let played: Played?
    let owner: String
    let isHolder: Bool
    let isActing: Bool
    let flipped: Bool
    let delay: Double

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Rectangle()
                    .strokeBorder(Color.white.opacity(0.15),
                                  style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(width: Metrics.tableCardWidth,
                           height: Metrics.tableCardWidth * Metrics.cardRatio)
                if let played = played {
                    PlayedCardEffect(
                        card: played.card,
                        width: Metrics.tableCardWidth,
                        flipped: flipped,
                        delay: delay
                    )
                    .id(played.id)
                }
            }
            .padding(3)
            .overlay {
                if isActing {
                    Rectangle()
                        .strokeBorder(Color.brassHi, lineWidth: 2)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: isActing)

            Text(owner.uppercased())
                .font(Typo.labelCaption(bold: isHolder))
                .tracking(1.1)
                .foregroundColor(isHolder ? .brassHi : .ivory.opacity(0.45))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 16)
        }
    }
}

/// Masaya düşen kart — uçuş + pirinç parıltı.
private struct PlayedCardEffect: View {
    let card: Card
    let width: CGFloat
    let flipped: Bool
    let delay: Double

    @State private var landed = false
    @State private var flash = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if flash {
                RoundedRectangle(cornerRadius: width * 0.09, style: .continuous)
                    .strokeBorder(Color.brassHi.opacity(0.95), lineWidth: 2.5)
                    .frame(width: width + 10, height: width * Metrics.cardRatio + 10)
                    .blur(radius: 0.5)
                    .opacity(flash ? 1 : 0)
            }

            FlipCard(card: card, width: width, flipped: flipped, delay: delay)
                .scaleEffect(landed ? 1 : (reduceMotion ? 1 : 1.22))
                .rotationEffect(.degrees(landed || reduceMotion ? 0 : -12))
                .offset(y: landed || reduceMotion ? 0 : -52)
                .opacity(landed || reduceMotion ? 1 : 0.25)
                .shadow(
                    color: Color.brass.opacity(landed ? 0.15 : 0.85),
                    radius: landed ? 4 : 18,
                    y: landed ? 4 : 10
                )
        }
        .onAppear {
            if reduceMotion {
                landed = true
                return
            }
            landed = false
            flash = false
            withAnimation(.spring(response: 0.42, dampingFraction: 0.68)) {
                landed = true
            }
            withAnimation(.easeOut(duration: 0.18).delay(0.12)) {
                flash = true
            }
            withAnimation(.easeOut(duration: 0.35).delay(0.32)) {
                flash = false
            }
        }
    }
}

// MARK: - Eşik göstergesi
private struct ThresholdGauge: View {
    let sum: Int
    let shown: Bool
    let outcome: Outcome?
    let holderName: String

    private var fraction: CGFloat {
        guard shown else { return 0 }
        return min(CGFloat(sum) / CGFloat(Rules.gaugeMax), 1)
    }

    private var numberColor: Color {
        guard shown, let outcome = outcome else { return .ivory.opacity(0.5) }
        switch outcome {
        case .over:        return .brassHi
        case .exact, .cap: return .ivory
        case .under:       return .lacLit
        }
    }

    private var fillColors: [Color] {
        guard let outcome = outcome else { return [.lacLit, .lac] }
        switch outcome {
        case .over:        return [.brass, .brassHi]
        case .exact, .cap: return [.ivory, .brassHi]
        case .under:       return [.lacLit, .lac]
        }
    }

    private var verdict: String {
        guard shown, let outcome = outcome else { return " " }
        let name = holderName.uppercased()
        switch outcome {
        case .over:  return L10n.verdictOver(name)
        case .exact: return L10n.verdictExact(name)
        case .cap:   return L10n.verdictCap(name)
        case .under: return L10n.verdictUnder(name)
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom) {
                Text(L10n.tableTotal)
                    .font(Typo.labelCaption()).tracking(2)
                    .foregroundColor(.ivory.opacity(0.5))
                Spacer()
                Text(shown ? "\(sum)" : " ")
                    .font(Typo.displayHero(bold: true))
                    .foregroundColor(numberColor)
                    .opacity(shown ? 1 : 0)
                    .accessibilityHidden(!shown)
            }

            VStack(spacing: 6) {
                GeometryReader { geo in
                    let inset = geo.size.width * 0.03
                    let trackW = geo.size.width - inset * 2
                    let mark25 = trackW * CGFloat(Double(Rules.limit) / Rules.gaugeMax)

                    VStack(spacing: 6) {
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color.black.opacity(0.42))
                            Rectangle()
                                .fill(LinearGradient(colors: fillColors,
                                                     startPoint: .leading, endPoint: .trailing))
                                .frame(width: trackW * fraction)
                            // 25 eşiği
                            Rectangle()
                                .fill(Color.brass)
                                .frame(width: 2, height: 15)
                                .offset(x: mark25 - 1, y: -3)
                            // 40 (üst sınır) — çubuğun sağ ucu
                            Rectangle()
                                .fill(Color.brass)
                                .frame(width: 2, height: 15)
                                .offset(x: trackW - 2, y: -3)
                        }
                        .frame(width: trackW, height: 9)
                        .overlay(Rectangle().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))

                        ZStack {
                            Text("25")
                                .font(Typo.labelCaption(bold: true))
                                .foregroundColor(.brass)
                                .position(x: mark25, y: 9)
                            Text("40")
                                .font(Typo.labelCaption(bold: true))
                                .foregroundColor(.brass.opacity(0.85))
                                .position(x: trackW, y: 9)
                        }
                        .frame(width: trackW, height: 18)
                    }
                    .frame(width: trackW)
                    .frame(maxWidth: .infinity)
                }
                .frame(height: 33)
            }

            Text(verdict)
                .font(Typo.labelCaption(bold: true))
                .tracking(1.1)
                .foregroundColor(numberColor)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 22)
                .padding(.top, 2)
                .opacity(shown ? 1 : 0)
        }
        .animation(.easeOut(duration: 0.75), value: fraction)
    }
}

// MARK: - El yelpazesi
private struct HandFan: View {
    let cards: [Card]
    let enabled: Bool
    var highlight: GameEngine.CardRef? = nil
    let onTap: (Card) -> Void

    private var useTwoRows: Bool { cards.count > Metrics.handSingleRowMax }

    private var rows: [[Card]] {
        guard useTwoRows else { return [cards] }
        let mid = (cards.count + 1) / 2
        return [Array(cards.prefix(mid)), Array(cards.suffix(cards.count - mid))]
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: useTwoRows ? 6 : 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    fanRow(row, width: geo.size.width)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .animation(.easeInOut(duration: 0.28), value: cards.count)
    }

    private func fanRow(_ row: [Card], width: CGFloat) -> some View {
        let count = max(row.count, 1)
        // Daha geniş basma aralığı
        let step = max(30, min(46, (width - Metrics.handCardWidth) / CGFloat(max(count - 1, 1))))
        return HStack(spacing: -(Metrics.handCardWidth - step)) {
            ForEach(Array(row.enumerated()), id: \.element.id) { pair in
                cardButton(pair.element, index: pair.offset, count: count)
            }
        }
        .frame(width: width, alignment: .center)
    }

    private func cardButton(_ card: Card, index: Int, count: Int) -> some View {
        let offset = Double(index) - Double(count - 1) / 2
        let isTarget = highlight?.matches(card) == true
        let canTap = enabled && (highlight == nil || isTarget)
        let button = Button {
            onTap(card)
        } label: {
            CardFace(card: card, width: Metrics.handCardWidth, compact: true)
                .overlay {
                    if isTarget {
                        RoundedRectangle(cornerRadius: Metrics.handCardWidth * 0.09, style: .continuous)
                            .strokeBorder(Color.brassHi, lineWidth: 2.5)
                    }
                }
                .rotationEffect(.degrees(offset * 1.6))
                .offset(y: (isTarget ? -12 : 0) + abs(offset) * 1.6)
                .shadow(color: isTarget ? Color.brass.opacity(0.7) : .black.opacity(0.5),
                        radius: isTarget ? 8 : 3, y: 3)
        }
        .buttonStyle(LiftButtonStyle())
        .disabled(!canTap)
        .opacity(canTap || !enabled ? (isTarget || highlight == nil ? 1 : 0.35) : 0.35)
        .zIndex(isTarget ? 100 : Double(index))
        .animation(.easeInOut(duration: 0.35), value: isTarget)

        #if os(macOS)
        let shortcutIndex = cards.firstIndex(where: { $0.id == card.id }) ?? index
        return Group {
            if shortcutIndex < 9 {
                button.keyboardShortcut(
                    KeyEquivalent(Character(String(shortcutIndex + 1))),
                    modifiers: []
                )
            } else {
                button
            }
        }
        #else
        return button
        #endif
    }
}

private struct LiftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(y: configuration.isPressed ? -22 : 0)
            .scaleEffect(configuration.isPressed ? 1.1 : 1)
            .rotationEffect(.degrees(configuration.isPressed ? -4 : 0))
            .shadow(
                color: .brass.opacity(configuration.isPressed ? 0.55 : 0),
                radius: configuration.isPressed ? 12 : 0,
                y: configuration.isPressed ? 6 : 0
            )
            .animation(.spring(response: 0.22, dampingFraction: 0.68),
                       value: configuration.isPressed)
    }
}

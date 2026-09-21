//  MenuView.swift
//  Yirmibeş — açılış ekranı

import SwiftUI

struct MenuView: View {
    let playerName: String
    let gamesPlayed: Int
    let gamesWon: Int
    let isGuest: Bool
    let canResume: Bool
    var offerDemo: Bool = false
    let onResume: () -> Void
    let onStart: () -> Void
    var onPlayDemo: (() -> Void)? = nil

    @EnvironmentObject private var language: AppLanguage
    @State private var showHowToPlay = false

    private let spread: [Card] = [
        Card(rank: .king, suit: .spade),
        Card(rank: .nine, suit: .heart),
        Card(rank: .ace,  suit: .club)
    ]

    var body: some View {
        let _ = language.choice
        ZStack {
            VStack(spacing: 0) {
                AppChromeBar(showHowToPlay: $showHowToPlay) {
                    HStack(spacing: 7) {
                        Text("♠").font(Typo.displayCaption()).foregroundColor(.brass)
                        Text(L10n.brandName).font(Typo.displayBrand(bold: true))
                            .tracking(2.6).foregroundColor(.brassHi)
                        Text("♥").font(Typo.displayCaption()).foregroundColor(.lacLit)
                    }
                } trailing: {
                    SettingsButton()
                }

                playerChip
                    .padding(.top, 14)

                if offerDemo, onPlayDemo != nil {
                    demoOffer
                        .padding(.top, 14)
                }

                Spacer()

                ZStack {
                    ForEach(Array(spread.enumerated()), id: \.element.id) { pair in
                        CardFace(card: pair.element, width: 78)
                            .rotationEffect(.degrees(Double(pair.offset - 1) * 18))
                            .offset(x: CGFloat(pair.offset - 1) * 44,
                                    y: pair.offset == 1 ? -7 : 0)
                            .shadow(color: .black.opacity(0.5), radius: 9, y: 9)
                    }
                }
                .frame(height: 130)
                .padding(.bottom, 24)

                VStack(spacing: 0) {
                    Text(L10n.menuTagline1)
                        .font(Typo.displayTitle())
                    Text(L10n.menuTagline2)
                        .font(Typo.displayTitle(bold: true))
                        .foregroundColor(.brassHi)
                }

                Text(L10n.menuBlurb)
                    .font(Typo.textBodySm())
                    .foregroundColor(.ivory.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 26)
                    .padding(.top, 12)

                Spacer()

                if canResume {
                    BrassButton(title: L10n.menuContinue, action: onResume)
                        .keyboardShortcut(.defaultAction)
                    Button(action: onStart) {
                        Text(L10n.menuNewGame)
                            .font(Typo.labelUI(bold: true))
                            .tracking(2)
                            .foregroundColor(.brassHi)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .overlay(Rectangle().strokeBorder(Color.brass.opacity(0.55), lineWidth: 1))
                    }
                    .buttonStyle(PressDownStyle())
                    .padding(.top, 10)
                } else {
                    BrassButton(title: L10n.menuSit, action: onStart)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .foregroundColor(.ivory)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Metrics.screenInsetH)
            .padding(.bottom, Metrics.screenInsetBottom)

            if showHowToPlay {
                HowToPlayLightbox(isPresented: $showHowToPlay, onPlayDemo: onPlayDemo)
            }
        }
    }

    private var demoOffer: some View {
        VStack(spacing: 10) {
            Text(L10n.demoOfferTitle)
                .font(Typo.labelUI(bold: true))
                .tracking(1.2)
                .foregroundColor(.brassHi)
            Text(L10n.demoOfferBody)
                .font(Typo.textCaption())
                .foregroundColor(.ivory.opacity(0.75))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
            if let onPlayDemo {
                Button(action: onPlayDemo) {
                    Text(L10n.demoReplay)
                        .font(Typo.labelUI(bold: true))
                        .tracking(1.2)
                        .foregroundColor(Color(hex: 0x2E230A))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(colors: [.brassHi, .brass, Color(hex: 0xB08C33)],
                                           startPoint: .top, endPoint: .bottom)
                        )
                        .overlay(Rectangle().strokeBorder(Color.brassDk, lineWidth: 1))
                }
                .buttonStyle(PressDownStyle())
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color.brass.opacity(0.12))
        .overlay(Rectangle().strokeBorder(Color.brass.opacity(0.45), lineWidth: 1))
    }

    private var playerChip: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: 0x2A8D6B), Color(hex: 0x0B3A2C)],
                                         center: .init(x: 0.35, y: 0.25),
                                         startRadius: 1, endRadius: 28))
                    .frame(width: 34, height: 34)
                    .overlay(Circle().strokeBorder(Color.brass.opacity(0.55), lineWidth: 1))
                Text(String(playerName.prefix(1)).uppercased())
                    .font(Typo.displayBrand())
                    .foregroundColor(.ivory)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(playerName)
                    .font(Typo.labelUI(bold: true))
                    .foregroundColor(.ivory)
                Text(statsLine)
                    .font(Typo.textCaption())
                    .foregroundColor(.ivory.opacity(0.5))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.28))
        .overlay(Rectangle().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    private var statsLine: String {
        if isGuest {
            #if DEBUG
            return "Debug oturumu"
            #else
            return L10n.menuStats(played: gamesPlayed, won: gamesWon)
            #endif
        }
        return L10n.menuStats(played: gamesPlayed, won: gamesWon)
    }
}

// MARK: - Pirinç buton
struct BrassButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Typo.label(Typo.body, bold: true))
                .tracking(title.count > 18 ? 0.8 : 3)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .foregroundColor(Color(hex: 0x2E230A))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 15)
                .background(
                    LinearGradient(colors: [.brassHi, .brass, Color(hex: 0xB08C33)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .overlay(Rectangle().strokeBorder(Color.brassDk, lineWidth: 1))
                .shadow(color: .black.opacity(0.34), radius: 8, y: 6)
        }
        .buttonStyle(PressDownStyle())
    }
}

struct PressDownStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(y: configuration.isPressed ? 3 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

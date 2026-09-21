//  HowToPlayView.swift
//  25-40 — nasıl oynanır (? + lightbox)

import SwiftUI

struct HowToPlayPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.howToPlay)
                .font(Typo.labelUI(bold: true))
                .tracking(1.4)
                .foregroundColor(.brassHi)
                .padding(.bottom, 4)

            line(L10n.rule1)
            line(L10n.rule2)
            line(L10n.rule3)
            line(L10n.rule4)
            line(L10n.rule5)
            line(L10n.rule6)
        }
        .font(Typo.textBodySm())
        .foregroundColor(.ivory.opacity(0.85))
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0x0A241C))
        .overlay(Rectangle().strokeBorder(Color.brass.opacity(0.45), lineWidth: 1))
    }

    private func line(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("♠")
                .font(Typo.displayCaption())
                .foregroundColor(.brass.opacity(0.7))
                .padding(.top, 2)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .lineSpacing(3)
        }
    }
}

/// Soru işareti — tıklanınca lightbox açılır.
struct HowToPlayButton: View {
    @Binding var isPresented: Bool

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Text("?")
                .font(Typo.labelUI(bold: true))
                .foregroundColor(.brass)
                .frame(width: Metrics.topBarControl, height: Metrics.topBarControl)
                .overlay(Circle().strokeBorder(Color.brass.opacity(0.5), lineWidth: 1))
        }
        .accessibilityLabel(L10n.howToPlay)
    }
}

/// Sayfayı kaydırmayan üst katman kural penceresi.
struct HowToPlayLightbox: View {
    @Binding var isPresented: Bool
    var onPlayDemo: (() -> Void)? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.62)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.2)) { isPresented = false }
                    }

                VStack(spacing: 0) {
                    HStack {
                        Spacer(minLength: 0)
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) { isPresented = false }
                        } label: {
                            Text("✕")
                                .font(Typo.labelUI(bold: true))
                                .foregroundColor(.brass)
                                .frame(width: 32, height: 32)
                                .overlay(Circle().strokeBorder(Color.brass.opacity(0.5), lineWidth: 1))
                        }
                    }
                    .padding(.bottom, 10)

                    ScrollView {
                        HowToPlayPanel()
                    }
                    .frame(maxHeight: max(geo.size.height * 0.78, 480))

                    if let onPlayDemo {
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) { isPresented = false }
                            onPlayDemo()
                        } label: {
                            Text(L10n.demoReplay)
                                .font(Typo.labelUI(bold: true))
                                .tracking(1.2)
                                .foregroundColor(Color(hex: 0x2E230A))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    LinearGradient(colors: [.brassHi, .brass, Color(hex: 0xB08C33)],
                                                   startPoint: .top, endPoint: .bottom)
                                )
                                .overlay(Rectangle().strokeBorder(Color.brassDk, lineWidth: 1))
                        }
                        .buttonStyle(PressDownStyle())
                        .padding(.top, 14)
                    }
                }
                .padding(18)
                .frame(maxWidth: min(geo.size.width - 24, 440))
                .background(Color(hex: 0x071A14).opacity(0.92))
                .overlay(Rectangle().strokeBorder(Color.brass.opacity(0.4), lineWidth: 1))
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .accessibilityAddTraits(.isModal)
    }
}

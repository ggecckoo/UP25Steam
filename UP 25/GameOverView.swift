//  GameOverView.swift
//  Yirmibeş — sonuç ekranı

import SwiftUI

struct GameOverView: View {
    let standings: [Standing]
    let onRestart: () -> Void
    var onMenu: (() -> Void)? = nil
    @EnvironmentObject private var language: AppLanguage

    var body: some View {
        let _ = language.choice
        VStack(spacing: 0) {
            Spacer()

            Text("♠ ♥ ♦ ♣")
                .font(Typo.displayTitle())
                .tracking(4)
                .foregroundColor(.brass)
                .padding(.bottom, 6)

            Text(L10n.roundsDone(Rules.rounds))
                .font(Typo.labelCaption(bold: true))
                .tracking(3.4)
                .foregroundColor(.ivory.opacity(0.5))

            Text(L10n.won(standings.first?.name ?? ""))
                .font(Typo.displayTitle())
                .foregroundColor(.ivory)
                .padding(.top, 5)

            Text(L10n.lightest(standings.first?.score ?? 0))
                .font(Typo.textCaption())
                .foregroundColor(.ivory.opacity(0.6))
                .padding(.bottom, 22)

            VStack(spacing: 5) {
                ForEach(Array(standings.enumerated()), id: \.element.id) { pair in
                    row(pair.element, rank: pair.offset + 1)
                }
            }
            .padding(.bottom, 24)

            Spacer()

            BrassButton(title: L10n.newGame, action: onRestart)

            if let onMenu {
                Button(L10n.backToMenu, action: onMenu)
                    .font(Typo.labelCaption(bold: true))
                    .tracking(1.6)
                    .foregroundColor(.brassHi)
                    .padding(.top, 14)
            }
        }
        .padding(.horizontal, Metrics.screenInsetH)
        .padding(.bottom, Metrics.screenInsetBottom)
    }

    private func row(_ s: Standing, rank: Int) -> some View {
        let isWinner = rank == 1
        return HStack(spacing: 10) {
            Text("\(rank)")
                .font(Typo.displayBrand())
                .foregroundColor(.brass)
                .frame(width: 14, alignment: .leading)

            Text(s.name)
                .font(Typo.labelUI(bold: true))
                .foregroundColor(.ivory)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    Text(L10n.overValuePenalty(value: s.value, penalty: s.penalty))
                        .font(Typo.textCaption())
                        .foregroundColor(.ivory.opacity(0.5))
                        .lineLimit(1)
                    Text("\(s.score)")
                        .font(Typo.displayBrand(bold: isWinner))
                        .foregroundColor(isWinner ? .brassHi : .ivory)
                        .frame(minWidth: 32, alignment: .trailing)
                }
                VStack(alignment: .trailing, spacing: 2) {
                    Text(L10n.overValuePenalty(value: s.value, penalty: s.penalty))
                        .font(Typo.textCaption())
                        .foregroundColor(.ivory.opacity(0.5))
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(s.score)")
                        .font(Typo.displayBrand(bold: isWinner))
                        .foregroundColor(isWinner ? .brassHi : .ivory)
                }
            }
            .layoutPriority(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(isWinner ? Color.brass.opacity(0.13) : Color.black.opacity(0.22))
        .overlay(Rectangle().strokeBorder(
            isWinner ? Color.brass : Color.white.opacity(0.07), lineWidth: 1))
    }
}

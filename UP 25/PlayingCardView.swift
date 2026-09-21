//  PlayingCardView.swift
//  Yirmibeş — iskambil kartı çizimi
//
//  Neyi düzeltiyor:
//  1) Pip sütunları köşedeki rakamla çakışıyordu.
//  2) Gerçek iskambil: masada küçük rakam + pip; elde büyük rakam, pip yok (compact).
//  3) Kart arkası: çapraz kafes + pirinç "25" madalyonu.

import SwiftUI

// MARK: - Pip dizilimi
struct Pip: Identifiable {
    let id: Int
    let x: CGFloat        // pip alanının genişliğine oranla 0...100
    let y: CGFloat        // pip alanının yüksekliğine oranla 0...100
    let flipped: Bool     // alt yarıdaki semboller ters basılır
    let big: Bool         // yalnızca As
}

enum PipLayout {
    /// Sütunlar: sol = 0, orta = 50, sağ = 100.
    /// Satırlar üstten alta 0...100. Alt yarıdaki semboller ters.
    private static func raw(_ rank: Rank) -> [(CGFloat, CGFloat, Bool, Bool)] {
        switch rank {
        case .ace:   return [(50, 50, false, true)]
        case .two:   return [(50, 0, false, false), (50, 100, true, false)]
        case .three: return [(50, 0, false, false), (50, 50, false, false),
                             (50, 100, true, false)]
        case .four:  return [(0, 0, false, false), (100, 0, false, false),
                             (0, 100, true, false), (100, 100, true, false)]
        case .five:  return [(0, 0, false, false), (100, 0, false, false),
                             (50, 50, false, false),
                             (0, 100, true, false), (100, 100, true, false)]
        case .six:   return [(0, 0, false, false), (100, 0, false, false),
                             (0, 50, false, false), (100, 50, false, false),
                             (0, 100, true, false), (100, 100, true, false)]
        case .seven: return [(0, 0, false, false), (100, 0, false, false),
                             (50, 25, false, false),
                             (0, 50, false, false), (100, 50, false, false),
                             (0, 100, true, false), (100, 100, true, false)]
        case .eight: return [(0, 0, false, false), (100, 0, false, false),
                             (50, 25, false, false),
                             (0, 50, false, false), (100, 50, false, false),
                             (50, 75, true, false),
                             (0, 100, true, false), (100, 100, true, false)]
        case .nine:  return [(0, 0, false, false), (100, 0, false, false),
                             (0, 33, false, false), (100, 33, false, false),
                             (50, 50, false, false),
                             (0, 67, true, false), (100, 67, true, false),
                             (0, 100, true, false), (100, 100, true, false)]
        case .ten:   return [(0, 0, false, false), (100, 0, false, false),
                             (50, 16, false, false),
                             (0, 33, false, false), (100, 33, false, false),
                             (0, 67, true, false), (100, 67, true, false),
                             (50, 84, true, false),
                             (0, 100, true, false), (100, 100, true, false)]
        default:     return []
        }
    }

    static func pips(for rank: Rank) -> [Pip] {
        raw(rank).enumerated().map { index, p in
            Pip(id: index, x: p.0, y: p.1, flipped: p.2, big: p.3)
        }
    }
}

// MARK: - Kart yüzü
struct CardFace: View {
    let card: Card
    let width: CGFloat
    /// true: el / masa açılışı — büyük köşe rakamı, pip yok.
    /// false: klasik masa yüzü — küçük rakam + tam pip dizilimi.
    var compact: Bool = false

    private var height: CGFloat { width * Metrics.cardRatio }
    private var tint: Color { card.isRed ? .lac : .ink }
    private var corner: CGFloat { width * 0.09 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner)
                .fill(LinearGradient(colors: [Color(hex: 0xFFFDF6), .ivorySh],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))

            if !compact {
                if card.rank.isCourt { court } else { pipField }
            }
        }
        .frame(width: width, height: height)
        .overlay(alignment: .topLeading) {
            index(rank: compact ? 0.30 : 0.125, suit: compact ? 0.21 : 0.095)
                .padding(.leading, width * (compact ? 0.09 : 0.06))
                .padding(.top, height * (compact ? 0.045 : 0.030))
        }
        .overlay(alignment: .bottomTrailing) {
            if compact {
                Text(card.suit.rawValue)
                    .font(Typo.display(width * 0.34))
                    .foregroundColor(tint)
                    .opacity(0.85)
                    .padding(.trailing, width * 0.10)
                    .padding(.bottom, height * 0.05)
            } else {
                index(rank: 0.125, suit: 0.095)
                    .rotationEffect(.degrees(180))
                    .padding(.trailing, width * 0.06)
                    .padding(.bottom, height * 0.030)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner))
        .overlay(RoundedRectangle(cornerRadius: corner)
            .strokeBorder(Color(hex: 0xCBBF9F), lineWidth: 1))
        .accessibilityLabel(L10n.cardA11y(rank: card.rank.rawValue, suit: card.suit.rawValue, value: card.value))
    }

    private func index(rank: CGFloat, suit: CGFloat) -> some View {
        VStack(spacing: -width * 0.02) {
            Text(card.rank.rawValue).font(Typo.display(width * rank, bold: true))
            Text(card.suit.rawValue).font(Typo.display(width * suit))
        }
        .foregroundColor(tint)
    }

    private var pipField: some View {
        GeometryReader { geo in
            pipStack(in: geo.size)
        }
    }

    /// Pip alanı: yatayda %30-%70, dikeyde %13-%87.
    /// Bu aralık köşedeki rakamı temizler; ölçüm dosya başındaki nota bakılabilir.
    private func pipStack(in size: CGSize) -> some View {
        let field = CGRect(x: size.width * 0.30, y: size.height * 0.13,
                           width: size.width * 0.40, height: size.height * 0.74)
        return ForEach(PipLayout.pips(for: card.rank)) { pip in
            Text(card.suit.rawValue)
                .font(Typo.display(width * (pip.big ? 0.40 : 0.15)))
                .foregroundColor(tint)
                .rotationEffect(.degrees(pip.flipped ? 180 : 0))
                .position(x: field.minX + field.width * pip.x / 100,
                          y: field.minY + field.height * pip.y / 100)
        }
    }

    private var court: some View {
        ZStack {
            RoundedRectangle(cornerRadius: width * 0.05).strokeBorder(tint, lineWidth: 1)
            Text(card.rank.rawValue)
                .font(Typo.display(width * 0.38, bold: true))
                .foregroundColor(tint)
            Text(card.suit.rawValue)
                .font(Typo.display(width * 0.15))
                .foregroundColor(tint)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(width * 0.04)
        }
        .padding(.horizontal, width * 0.24)
        .padding(.vertical, height * 0.14)
    }
}

// MARK: - Kart arkası (çapraz kafes + pirinç madalyon)
struct CardBack: View {
    let width: CGFloat
    private var height: CGFloat { width * Metrics.cardRatio }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: width * 0.09)
                .fill(LinearGradient(colors: [Color(hex: 0xFFFDF6), .ivorySh],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))

            ZStack {
                RadialGradient(colors: [Color(hex: 0x1F6A51), Color(hex: 0x07301F)],
                               center: .init(x: 0.5, y: 0.38),
                               startRadius: 1, endRadius: width)
                lattice
                medallion
            }
            .clipShape(RoundedRectangle(cornerRadius: width * 0.045))
            .overlay(RoundedRectangle(cornerRadius: width * 0.045)
                .strokeBorder(Color.brass.opacity(0.6), lineWidth: 1))
            .padding(width * 0.06)
        }
        .frame(width: width, height: height)
        .overlay(RoundedRectangle(cornerRadius: width * 0.09)
            .strokeBorder(Color(hex: 0xCBBF9F), lineWidth: 1))
        .accessibilityLabel(L10n.faceDown)
    }

    /// İki yönlü çapraz tarama — klasik kart arkası dokusu.
    private var lattice: some View {
        Canvas { context, size in
            let color = Color.brassHi.opacity(0.18)
            let step: CGFloat = 5
            var x = -size.height
            while x < size.width + size.height {
                var down = Path()
                down.move(to: CGPoint(x: x, y: 0))
                down.addLine(to: CGPoint(x: x + size.height, y: size.height))
                context.stroke(down, with: .color(color), lineWidth: 1)

                var up = Path()
                up.move(to: CGPoint(x: x, y: size.height))
                up.addLine(to: CGPoint(x: x + size.height, y: 0))
                context.stroke(up, with: .color(color), lineWidth: 1)

                x += step
            }
        }
    }

    private var medallion: some View {
        Text("25")
            .font(Typo.display(width * 0.20, bold: true))
            .foregroundColor(.brassHi)
            .frame(width: width * 0.46, height: width * 0.46)
            .background(
                Circle().fill(RadialGradient(
                    colors: [Color(hex: 0x27805F), Color(hex: 0x0A3527)],
                    center: .init(x: 0.38, y: 0.28),
                    startRadius: 1, endRadius: width * 0.5))
            )
            .overlay(Circle().strokeBorder(Color.brassHi.opacity(0.75), lineWidth: 1))
            .shadow(color: Color(hex: 0x07301F).opacity(0.5), radius: width * 0.05)
    }
}

// MARK: - Çevrilen kart
struct FlipCard: View {
    let card: Card
    let width: CGFloat
    let flipped: Bool
    let delay: Double
    /// El ile aynı gösterim: büyük köşe rakamı, pip yok.
    var compact: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            CardBack(width: width).opacity(flipped ? 0 : 1)
            CardFace(card: card, width: width, compact: compact)
                .opacity(flipped ? 1 : 0)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
        }
        .rotation3DEffect(.degrees(flipped ? 180 : 0),
                          axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        .animation(reduceMotion
                   ? .linear(duration: 0.01)
                   : .spring(response: 0.5, dampingFraction: 0.72).delay(delay),
                   value: flipped)
    }
}

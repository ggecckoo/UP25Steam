//  Theme.swift
//  25-40 — renk, tipografi, ölçü
//
//  Yön: Las Vegas değil kıraathane. Yıllanmış pirinç, oksitlenmiş yeşil çuha,
//  fildişi kart stoğu, lake kırmızı. Parlak altın ve neon yok.

import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue:  Double(hex & 0xFF) / 255,
                  opacity: 1)
    }

    static let feltDeep = Color(hex: 0x0A3B2E)
    static let feltLit  = Color(hex: 0x1E6E52)
    static let feltEdge = Color(hex: 0x052620)
    static let brass    = Color(hex: 0xC9A44C)
    static let brassHi  = Color(hex: 0xF0DA9E)
    static let brassDk  = Color(hex: 0x6E5320)
    static let ivory    = Color(hex: 0xF7F2E4)
    static let ivorySh  = Color(hex: 0xE4DBC4)
    static let lac      = Color(hex: 0xB3302B)
    static let lacLit   = Color(hex: 0xE8837C)
    static let ink      = Color(hex: 0x1B1712)
}

// iOS'ta hazır bulunan yazı tipleri kullanılıyor, paket gerekmez.
// Bodoni 72: didone yapı, Avrupa iskambil destelerinin gravür geleneği.
// Avenir Next Condensed: sıkı büyük harf etiketler, emaye masa levhası hissi.
//
// Tek tip ölçeği — ekranlar arası tutarlılık için yalnızca bunları kullan.
enum Typo {
    // Punto ölçeği (Avenir Condensed küçük göründüğü için bir kademe büyük tutulur)
    static let hero: CGFloat = 40
    static let title: CGFloat = 32
    static let brand: CGFloat = 24
    static let body: CGFloat = 19
    static let bodySm: CGFloat = 18
    static let ui: CGFloat = 17
    static let caption: CGFloat = 16

    static func display(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? "BodoniSvtyTwoITCTT-Bold" : "BodoniSvtyTwoITCTT-Book", size: size)
    }
    static func label(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? "AvenirNextCondensed-Bold" : "AvenirNextCondensed-DemiBold", size: size)
    }
    static func body(_ size: CGFloat) -> Font {
        .custom("AvenirNextCondensed-Medium", size: size)
    }

    // Anlamsal yardımcılar
    static func displayHero(bold: Bool = false) -> Font { display(hero, bold: bold) }
    static func displayTitle(bold: Bool = false) -> Font { display(title, bold: bold) }
    static func displayBrand(bold: Bool = false) -> Font { display(brand, bold: bold) }
    static func displayBody(bold: Bool = false) -> Font { display(body, bold: bold) }
    static func displayCaption(bold: Bool = false) -> Font { display(caption, bold: bold) }
    static func labelUI(bold: Bool = false) -> Font { label(ui, bold: bold) }
    static func labelCaption(bold: Bool = false) -> Font { label(caption, bold: bold) }
    static func textBody() -> Font { body(body) }
    static func textBodySm() -> Font { body(bodySm) }
    static func textCaption() -> Font { body(caption) }
}

enum Metrics {
    /// El kartları; masa biraz daha büyük tutulur.
    static let handCardWidth:  CGFloat = 60
    static let tableCardWidth: CGFloat = 76
    static let cardRatio:      CGFloat = 1.4      // 5:7
    /// Bu sayıya kadar el tek satır; üstünde iki satıra bölünür.
    static let handSingleRowMax: Int = 6
    /// Menü / oyun / giriş — aynı üst/alt kenar boşlukları.
    static let screenInsetH: CGFloat = 16
    static let screenInsetBottom: CGFloat = 8
    /// Oyun eli — home indicator’dan nefes payı.
    static let gameHandBottomInset: CGFloat = 22
    static let topBarControl: CGFloat = 30
    static let chromeTopPad: CGFloat = 12
    static let chromeBottomPad: CGFloat = 9
}

/// Çuha zemini: üstten gelen ışık ve dokuma dokusu.
struct FeltBackground: View {
    var body: some View {
        ZStack {
            RadialGradient(colors: [.feltLit, .feltDeep, .feltEdge],
                           center: .init(x: 0.5, y: 0.0),
                           startRadius: 10, endRadius: 620)
            Canvas { context, size in
                let line = Color.black.opacity(0.10)
                var x: CGFloat = 0
                while x < size.width {
                    context.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)),
                                 with: .color(line))
                    x += 3
                }
                var y: CGFloat = 0
                while y < size.height {
                    context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                                 with: .color(.white.opacity(0.045)))
                    y += 3
                }
            }
            .blendMode(.overlay)
        }
        .ignoresSafeArea()
    }
}

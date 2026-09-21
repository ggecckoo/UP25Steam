//  Model.swift
//  Yirmibeş — kart, deste ve kural sabitleri

import Foundation

// MARK: - Kural sabitleri
// Bu sayılar ölçülmüştür, keyfi değildir. Gerekçeleri tasarım dokümanında.
enum Rules {
    static let limit           = 25    // eşik: sıra sahibi bunu aşmak zorunda
    static let cap             = 40    // 4×10: herkes en yüksek atarsa masa cezası
    static let rounds          = 12    // 4'ün katı -> sıra sahipliği 3-3-3-3 dağılır
    static let handSize        = 13    // 13 x 4 = 52, deste tam biter
    static let penaltyPerCard  = 4     // elde kalan her kart için ceza puanı
    static let gaugeMax        = 40.0  // eşik göstergesinin üst sınırı

    // Tempo (saniye)
    static let aiDelay   = 1.15  // rakip hamleleri arası
    static let sumDelay  = 1.70  // kartlar açıldıktan toplamın belirmesine
    static let holdDelay = 2.90  // toplam göründükten sonra turun kapanmasına
    static let flipStep  = 0.36  // kartların tek tek çevrilme gecikmesi
}

// MARK: - Tür
enum Suit: String, CaseIterable {
    case spade = "♠", heart = "♥", diamond = "♦", club = "♣"
    var isRed: Bool { self == .heart || self == .diamond }
}

// MARK: - Değer
enum Rank: String, CaseIterable {
    case ace = "A", two = "2", three = "3", four = "4", five = "5", six = "6"
    case seven = "7", eight = "8", nine = "9", ten = "10"
    case jack = "J", queen = "Q", king = "K"

    var value: Int {
        switch self {
        case .ace:   return 1
        case .two:   return 2
        case .three: return 3
        case .four:  return 4
        case .five:  return 5
        case .six:   return 6
        case .seven: return 7
        case .eight: return 8
        case .nine:  return 9
        case .ten, .jack, .queen, .king: return 10
        }
    }

    var isCourt: Bool { self == .jack || self == .queen || self == .king }
}

// MARK: - Kart
struct Card: Identifiable, Equatable {
    let id = UUID()
    let rank: Rank
    let suit: Suit

    var value: Int { rank.value }
    var isRed: Bool { suit.isRed }

    static func shuffledDeck() -> [Card] {
        var deck: [Card] = []
        for suit in Suit.allCases {
            for rank in Rank.allCases {
                deck.append(Card(rank: rank, suit: suit))
            }
        }
        deck.shuffle()
        return deck
    }
}

// MARK: - Oyuncu
struct Player: Identifiable {
    let id: Int
    let name: String
    let isHuman: Bool
    var hand: [Card]

    var handValue: Int { hand.reduce(0) { $0 + $1.value } }
    var penalty: Int { hand.count * Rules.penaltyPerCard }
    var score: Int { handValue + penalty }
}

// MARK: - Masaya atılan kart
struct Played: Identifiable {
    let id = UUID()
    let card: Card
    let by: Int
}

// MARK: - Tur sonucu
enum Outcome: Equatable {
    case over        // 25 < toplam < 40  -> sıra sahibi kart çekmez
    case exact       // toplam = 25       -> sıra sahibi hariç herkes 1 kart
    case cap         // toplam = 40       -> sıra sahibi hariç herkes 1 kart (aynı ceza)
    case under       // toplam < 25       -> sıra sahibi 2 kart çeker
}

// MARK: - Sonuç tablosu satırı
struct Standing: Identifiable {
    let id: Int
    let name: String
    let cards: Int
    let value: Int
    let penalty: Int
    var score: Int { value + penalty }
}

// MARK: - Tur kuralları
// Motor ve testler aynı kaynağı kullanır; kural tek yerde tanımlıdır.
enum RoundRules {
    static func outcome(for total: Int) -> Outcome {
        // 40 önce: aksi halde >25 dalı onu "over" sayardı.
        if total == Rules.cap { return .cap }
        if total > Rules.limit { return .over }
        if total == Rules.limit { return .exact }
        return .under
    }

    /// Hangi oyuncunun kaç kart çekeceğini döner.
    /// over  -> kimse çekmez, atılan kartlar yanar
    /// exact / cap -> sıra sahibi hariç herkes 1 kart
    /// under -> sıra sahibi 2 kart
    static func draws(outcome: Outcome, holder: Int, order: [Int]) -> [Int: Int] {
        switch outcome {
        case .over:
            return [:]
        case .exact, .cap:
            var plan: [Int: Int] = [:]
            for player in order where player != holder { plan[player] = 1 }
            return plan
        case .under:
            return [holder: 2]
        }
    }
}

// MARK: - Yapay zeka
// Sıra sahibi 25'i geçmek ister -> en yükseğini atar.
// Diğerleri iki şey ister: sıra sahibini yakmak (düşük at) ve kendi puanını
// düşürmek (yüksek at). Karar masadaki duruma bakar.
enum AI {
    static func pick(hand: [Card], isHolder: Bool, running: Int, after: Int, round: Int) -> Card {
        let sorted = hand.sorted { $0.value < $1.value }
        guard let low = sorted.first, let high = sorted.last else { return hand[0] }

        if isHolder { return high }

        // En küçüğümü atsam bile eşik aşılacak -> yaktırmak imkânsız
        if running + low.value + after * 1 > Rules.limit { return high }

        // En yükseğimi atsam bile eşik aşılmaz -> bedava, puanını düşür
        if running + high.value + after * 10 <= Rules.limit { return high }

        // Gerçek ikilem: tur ilerledikçe puan kaygısı ağırlaşır
        let dumpChance = 0.18 + Double(round) * 0.06
        return Double.random(in: 0..<1) < dumpChance ? high : low
    }
}

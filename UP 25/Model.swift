//  Model.swift
//  Yirmibeş — kart, deste ve kural sabitleri

import Foundation

// MARK: - Kural sabitleri
// Bu sayılar ölçülmüştür, keyfi değildir. Gerekçeleri tasarım dokümanında.
enum Rules {
    static let limit           = 25    // eşik: sıra sahibi bunu aşmak zorunda
    static let cap             = 40    // 4×10: herkes en yüksek atarsa masa cezası
    static let rounds          = 8     // 4'ün katı -> sıra sahipliği 2-2-2-2 dağılır
    static let handSize        = 9     // turdan bir fazla: kimsenin eli bitmez; 9 x 4 = 36
    static let deckSize        = 52    // kalan 16 kart kapalı çekme destesi olur
    static let penaltyPerCard  = 4     // elde kalan her kart için ceza puanı
    static let underDraw       = 2     // 25'in altında kalan sıra sahibinin çektiği kart
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

    /// Kartın köşesinde ve ortasında yazan: A, 2–10, J, Q, K.
    var face: String { rawValue }
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
        for rank in Rank.allCases {
            for suit in Suit.allCases {
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
    case over        // 25 < toplam, 40 değil -> sıra sahibi kart çekmez
    case exact       // toplam = 25       -> sıra sahibi hariç herkes 1 kart
    case cap         // toplam = 40       -> sıra sahibi hariç herkes 1 kart
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
    /// Kartlar her zaman çekme destesinin üstünden gelir (GameEngine.apply).
    static func draws(outcome: Outcome, holder: Int, order: [Int]) -> [Int: Int] {
        switch outcome {
        case .over:
            return [:]
        case .exact, .cap:
            var plan: [Int: Int] = [:]
            for player in order where player != holder { plan[player] = 1 }
            return plan
        case .under:
            return [holder: Rules.underDraw]
        }
    }
}

// MARK: - Yapay zeka
// Bot, masadaki bir oyuncunun bildiğini bilir: kendi elini, bu tur masada kaç
// kapalı kart olduğunu ve sıra sahibininkinin aralarında olup olmadığını,
// önceki turlarda açılmış kartları. Kapalı kartları ve masa toplamını görmez.
// Sıra sahibi en yükseğini atar. Diğerleri her kartı, göremedikleri kartlar
// için yapılan `guesses` tahmin üzerinden tartar: atılan kart puanı kadar
// değerlidir, sıra sahibini batırmak onun çekeceği iki kartın bir payı kadar,
// toplamı tam 25 ya da 40 yapmak ise kendi çekeceği bir kart kadar pahalıdır.
// İlk iki seçenek birbirine yakınsa beşte bir ikinciyi oynar.
enum AI {
    static let guesses = 40
    static let holderGuess = 5
    static let close = 3.0
    static let sinkShare = 0.7

    /// `unseen`: botun göremediği kartların değerleri (destedeki tüm kartlar
    /// eksi kendi eli eksi açılmış kartlar); `down`: masadaki kapalı kart
    /// sayısı; `after`: kendisinden sonra oynayacak oyuncu sayısı.
    static func pick<G: RandomNumberGenerator>(hand: [Card], isHolder: Bool, unseen: [Int],
                                                down: Int, holderDown: Bool, after: Int,
                                                using rng: inout G) -> Card {
        guard var high = hand.first else { fatalError("boş el") }
        var byValue: [Int: Card] = [:]
        for card in hand {
            if card.value > high.value { high = card }
            if byValue[card.value] == nil { byValue[card.value] = card }
        }
        if isHolder || unseen.isEmpty || byValue.count == 1 { return high }

        let values = byValue.keys.sorted()
        var odds = Dictionary(uniqueKeysWithValues: values.map { ($0, 0.0) })
        let cost = 6.5 + Double(Rules.penaltyPerCard)
        var pool = unseen
        let need = min(down + after, pool.count)
        for _ in 0..<guesses {
            for k in 0..<need {
                pool.swapAt(k, Int.random(in: k..<pool.count, using: &rng))
            }
            var total = 0
            for k in 0..<need {
                if holderDown && k == 0 {
                    var best = 0
                    for _ in 0..<holderGuess { best = max(best, pool[Int.random(in: 0..<pool.count, using: &rng)]) }
                    total += best
                } else {
                    total += pool[k]
                }
            }
            for value in values {
                switch RoundRules.outcome(for: total + value) {
                case .under: odds[value, default: 0] += cost * Double(Rules.underDraw) * sinkShare
                case .exact, .cap: odds[value, default: 0] -= cost
                case .over: break
                }
            }
        }
        let worth = Dictionary(uniqueKeysWithValues: values.map { ($0, Double($0) + odds[$0, default: 0] / Double(guesses)) })
        let ranked = values.sorted { worth[$0]! > worth[$1]! }
        if ranked.count > 1, worth[ranked[0]]! - worth[ranked[1]]! < close,
           Double.random(in: 0..<1, using: &rng) < 0.2 {
            return byValue[ranked[1]]!
        }
        return byValue[ranked[0]]!
    }

    static func pick(hand: [Card], isHolder: Bool, unseen: [Int], down: Int, holderDown: Bool, after: Int) -> Card {
        var rng = SystemRandomNumberGenerator()
        return pick(hand: hand, isHolder: isHolder, unseen: unseen, down: down,
                    holderDown: holderDown, after: after, using: &rng)
    }

    /// Bir oyuncunun göremediği kartların değerleri: destedeki 52 kart, eksi
    /// kendi eli, eksi önceki turlarda açılıp atılmış kartlar.
    static func unseen(hand: [Card], discard: [Card]) -> [Int] {
        var left: [Int: Int] = [:]
        for rank in Rank.allCases { left[rank.value, default: 0] += 4 }
        for card in hand + discard { left[card.value, default: 0] -= 1 }
        return left.keys.sorted().flatMap { value in Array(repeating: value, count: max(left[value] ?? 0, 0)) }
    }
}

//  RulesTests.swift
//  YirmibesTests — kural ve denge doğrulaması
//
//  Bu testler oyunun ölçülmüş dengesini korur. Xcode'da Cmd+U ile çalıştırılır.
//  Modül adı: UP_25

import XCTest
@testable import UP_25

// MARK: - Test stratejileri
private enum Strategy {
    case engine
    case alwaysHighest

    func choose(hand: [Card], isHolder: Bool, unseen: [Int], down: Int, holderDown: Bool, after: Int) -> Card {
        switch self {
        case .engine:
            return AI.pick(hand: hand, isHolder: isHolder, unseen: unseen,
                           down: down, holderDown: holderDown, after: after)
        case .alwaysHighest:
            return hand.max(by: { $0.value < $1.value }) ?? hand[0]
        }
    }
}

// MARK: - Sabit tohumlu üreteç (botun kararını tekrarlanabilir sınamak için)
private struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

// MARK: - Arayüzsüz oyun simülasyonu
// GameEngine ile aynı akış: kartlar kapalı atılır, botlar yalnız kendi elini
// ve önceki turlarda açılan kartları bilir; çekilen kart çekme destesinin
// üstünden gelir, deste yetmezse atılanlar geri karılır.
private struct Sim {
    let strategies: [Strategy]
    var hands: [[Card]]
    var stock: [Card]
    var discard: [Card] = []
    var holder: Int
    var over = 0
    var exact25 = 0
    var cap40 = 0
    var under = 0
    var cardLossSeen = false
    var emptyHandSeen = false
    var refills = 0

    init(strategies: [Strategy]) {
        self.strategies = strategies
        let deck = Card.shuffledDeck()
        hands = (0..<4).map { index in
            Array(deck[(index * Rules.handSize)..<((index + 1) * Rules.handSize)])
        }
        stock = Array(deck[(4 * Rules.handSize)...])
        holder = Int.random(in: 0..<4)
    }

    mutating func run() {
        for _ in 1...Rules.rounds {
            let order = (0..<4).map { (holder + $0) % 4 }
            var table: [Card] = []

            for (slot, pi) in order.enumerated() {
                if hands[pi].isEmpty { emptyHandSeen = true; return }
                let card = strategies[pi].choose(hand: hands[pi],
                                                 isHolder: pi == holder,
                                                 unseen: AI.unseen(hand: hands[pi], discard: discard),
                                                 down: table.count,
                                                 holderDown: slot > 0,
                                                 after: 3 - slot)
                hands[pi].removeAll { $0.id == card.id }
                table.append(card)
            }

            let total = table.reduce(0, { $0 + $1.value })
            let outcome = RoundRules.outcome(for: total)
            switch outcome {
            case .over:  over += 1
            case .exact: exact25 += 1
            case .cap:   cap40 += 1
            case .under: under += 1
            }

            discard.append(contentsOf: table)
            let plan = RoundRules.draws(outcome: outcome, holder: holder, order: order)
            if plan.values.reduce(0, +) > stock.count {
                refills += 1
                stock.append(contentsOf: discard)
                discard = []
                stock.shuffle()
            }
            for pi in order {
                guard let count = plan[pi], count > 0 else { continue }
                hands[pi].append(contentsOf: stock.suffix(count).reversed())
                stock.removeLast(min(count, stock.count))
            }

            let inHands = hands.reduce(0, { $0 + $1.count })
            if inHands + stock.count + discard.count != Rules.deckSize { cardLossSeen = true }

            holder = (holder + 1) % 4
        }
    }

    var scores: [Int] {
        hands.map { hand -> Int in
            let value = hand.reduce(0, { $0 + $1.value })
            return value + hand.count * Rules.penaltyPerCard
        }
    }

    var winner: Int {
        let s = scores
        var best = 0
        for i in 1..<4 where s[i] < s[best] { best = i }
        return best
    }
}

// MARK: - Testler
final class RulesTests: XCTestCase {

    func testDeckIntegrity() {
        for _ in 0..<400 {
            var sim = Sim(strategies: Array(repeating: .engine, count: 4))
            sim.run()
            XCTAssertFalse(sim.cardLossSeen, "toplam kart sayısı 52'den saptı")
            XCTAssertFalse(sim.emptyHandSeen, "bir oyuncunun eli bitti")
        }
    }

    func testThresholdBalance() {
        var over = 0, exact25 = 0, cap40 = 0, total = 0
        for _ in 0..<400 {
            var sim = Sim(strategies: Array(repeating: .engine, count: 4))
            sim.run()
            over += sim.over
            exact25 += sim.exact25
            cap40 += sim.cap40
            total += sim.over + sim.exact25 + sim.cap40 + sim.under
        }
        let overRate = Double(over) / Double(total)
        let exact25Rate = Double(exact25) / Double(total)
        let cap40Rate = Double(cap40) / Double(total)
        XCTAssertTrue((0.50...0.68).contains(overRate),
                      "sıra sahibinin kazanma oranı aralık dışı: \(overRate)")
        XCTAssertTrue((0.02...0.09).contains(exact25Rate),
                      "tam 25 oranı aralık dışı: \(exact25Rate)")
        XCTAssertTrue((0.01...0.06).contains(cap40Rate),
                      "tam 40 oranı aralık dışı: \(cap40Rate)")
    }

    func testAlwaysHighestIsNotDominant() {
        var wins = 0
        let games = 1200
        for _ in 0..<games {
            var sim = Sim(strategies: [.alwaysHighest, .engine, .engine, .engine])
            sim.run()
            if sim.winner == 0 { wins += 1 }
        }
        let rate = Double(wins) / Double(games)
        XCTAssertLessThan(rate, 0.40, "hep-en-yüksek stratejisi baskın hale gelmiş: \(rate)")
    }

    /// 8 tur, 4 oyuncu: sıra sahipliği 2-2-2-2.
    func testHolderRotationIsEven() {
        for start in 0..<4 {
            var counts = [0, 0, 0, 0]
            var holder = start
            for _ in 1...Rules.rounds {
                counts[holder] += 1
                holder = (holder + 1) % 4
            }
            XCTAssertEqual(counts, [2, 2, 2, 2], "başlangıç \(start) için dağılım bozuk")
        }
    }

    func testScoreIncludesPenalty() {
        let hand = [Card(rank: .king, suit: .spade), Card(rank: .ace, suit: .heart)]
        let player = Player(id: 0, name: "Test", isHuman: true, hand: hand)
        XCTAssertEqual(player.handValue, 11)
        XCTAssertEqual(player.penalty, 2 * Rules.penaltyPerCard)
        XCTAssertEqual(player.score, 11 + 2 * Rules.penaltyPerCard)
    }

    /// 52 kart, her biri bir kez; As 1, 2–9 kendi değeri, 10 ve resimler 10.
    func testDeckAndValues() {
        let deck = Card.shuffledDeck()
        XCTAssertEqual(deck.count, Rules.deckSize)
        XCTAssertEqual(Set(deck.map { "\($0.rank.rawValue)\($0.suit.rawValue)" }).count, 52)
        XCTAssertEqual(Rank.allCases.map(\.value), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 10, 10, 10])
        XCTAssertEqual(Rules.handSize, Rules.rounds + 1)
    }

    /// Bot kapalı kartları görmez; yalnız göremediği kartların değerleri,
    /// masadaki kapalı kart sayısı ve kendinden sonrakiler üzerinden karar verir.
    func testBotWeighsWhatItCannotSee() {
        let hand = [Card(rank: .ace, suit: .spade), Card(rank: .king, suit: .heart)]
        var rng = SplitMix(state: 7)
        let nines = Array(repeating: 9, count: 30)
        let tens = Array(repeating: 10, count: 30)
        let fives = Array(repeating: 5, count: 30)
        let aces = Array(repeating: 1, count: 30)
        XCTAssertEqual(AI.pick(hand: hand, isHolder: true, unseen: tens, down: 0, holderDown: false, after: 3, using: &rng).rank, .king)
        // Batıramaz, tam 25/40 da yapmaz: papazdan kurtulur.
        XCTAssertEqual(AI.pick(hand: hand, isHolder: false, unseen: nines, down: 1, holderDown: true, after: 2, using: &rng).rank, .king)
        // Papaz toplamı tam 40 yapardı: as oynar.
        XCTAssertEqual(AI.pick(hand: hand, isHolder: false, unseen: tens, down: 1, holderDown: true, after: 2, using: &rng).rank, .ace)
        // Papaz tam 25 yapardı, as sıra sahibini batırır.
        XCTAssertEqual(AI.pick(hand: hand, isHolder: false, unseen: fives, down: 3, holderDown: true, after: 0, using: &rng).rank, .ace)
        // İkisi de batırır: papazdan kurtulur.
        XCTAssertEqual(AI.pick(hand: hand, isHolder: false, unseen: aces, down: 3, holderDown: true, after: 0, using: &rng).rank, .king)
        // Göremediği kartlar: 52 eksi eli eksi açılanlar.
        let shown = [Card(rank: .ten, suit: .club), Card(rank: .two, suit: .diamond)]
        XCTAssertEqual(AI.unseen(hand: hand, discard: shown).count, 52 - 2 - 2)
    }

    func testOutcomeAndDrawPlan() {
        XCTAssertEqual(RoundRules.outcome(for: 40), .cap)
        XCTAssertEqual(RoundRules.outcome(for: 39), .over)
        XCTAssertEqual(RoundRules.outcome(for: 26), .over)
        XCTAssertEqual(RoundRules.outcome(for: 25), .exact)
        XCTAssertEqual(RoundRules.outcome(for: 24), .under)

        let order = [2, 3, 0, 1]
        XCTAssertTrue(RoundRules.draws(outcome: .over, holder: 2, order: order).isEmpty)
        XCTAssertEqual(RoundRules.draws(outcome: .under, holder: 2, order: order), [2: 2])
        XCTAssertEqual(RoundRules.draws(outcome: .exact, holder: 2, order: order),
                       [3: 1, 0: 1, 1: 1])
        XCTAssertEqual(RoundRules.draws(outcome: .cap, holder: 2, order: order),
                       [3: 1, 0: 1, 1: 1])
    }
}

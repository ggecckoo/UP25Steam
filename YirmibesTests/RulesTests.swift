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

    func choose(hand: [Card], isHolder: Bool, running: Int, after: Int, round: Int) -> Card {
        switch self {
        case .engine:
            return AI.pick(hand: hand, isHolder: isHolder,
                           running: running, after: after, round: round)
        case .alwaysHighest:
            return hand.max(by: { $0.value < $1.value }) ?? hand[0]
        }
    }
}

// MARK: - Arayüzsüz oyun simülasyonu
private struct Sim {
    let strategies: [Strategy]
    var hands: [[Card]]
    var middle: [Card]
    var holder: Int
    var over = 0
    var exact25 = 0
    var cap40 = 0
    var under = 0
    var emptyHandSeen = false
    var cardLossSeen = false
    var pileShortSeen = false

    init(strategies: [Strategy]) {
        self.strategies = strategies
        let deck = Card.shuffledDeck()
        hands = (0..<4).map { index in
            Array(deck[(index * Rules.handSize)..<((index + 1) * Rules.handSize)])
        }
        middle = Array(deck[(4 * Rules.handSize)...])
        holder = Int.random(in: 0..<4)
    }

    mutating func run() {
        for round in 1...Rules.rounds {
            let order = (0..<4).map { (holder + $0) % 4 }
            var table: [Card] = []

            for (slot, pi) in order.enumerated() {
                if hands[pi].isEmpty { emptyHandSeen = true; return }
                let running = table.reduce(0, { $0 + $1.value })
                let card = strategies[pi].choose(hand: hands[pi],
                                                 isHolder: pi == holder,
                                                 running: running,
                                                 after: 3 - slot,
                                                 round: round)
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

            var pile = table.shuffled() + middle
            let plan = RoundRules.draws(outcome: outcome, holder: holder, order: order)
            for pi in order {
                guard let count = plan[pi], count > 0 else { continue }
                if pile.count < count { pileShortSeen = true }
                let take = min(count, pile.count)
                hands[pi].append(contentsOf: pile.prefix(take))
                pile.removeFirst(take)
            }
            middle = pile

            let inHands = hands.reduce(0, { $0 + $1.count })
            if inHands + middle.count != 52 { cardLossSeen = true }

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
            XCTAssertFalse(sim.emptyHandSeen, "bir oyuncunun eli turdan önce tükendi")
            XCTAssertFalse(sim.cardLossSeen, "toplam kart sayısı 52'den saptı")
            XCTAssertFalse(sim.pileShortSeen, "havuzda çekilecek kart kalmadı")
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
        XCTAssertTrue((0.48...0.60).contains(overRate),
                      "sıra sahibinin kazanma oranı aralık dışı: \(overRate)")
        XCTAssertTrue((0.04...0.12).contains(exact25Rate),
                      "tam 25 oranı aralık dışı: \(exact25Rate)")
        XCTAssertTrue((0.02...0.10).contains(cap40Rate),
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
        XCTAssertLessThan(rate, 0.34, "hep-en-yüksek stratejisi baskın hale gelmiş: \(rate)")
    }

    /// 12 tur, 4 oyuncu: sıra sahipliği 3-3-3-3.
    func testHolderRotationIsEven() {
        for start in 0..<4 {
            var counts = [0, 0, 0, 0]
            var holder = start
            for _ in 1...Rules.rounds {
                counts[holder] += 1
                holder = (holder + 1) % 4
            }
            XCTAssertEqual(counts, [3, 3, 3, 3], "başlangıç \(start) için dağılım bozuk")
        }
    }

    func testScoreIncludesPenalty() {
        let hand = [Card(rank: .king, suit: .spade), Card(rank: .ace, suit: .heart)]
        let player = Player(id: 0, name: "Test", isHuman: true, hand: hand)
        XCTAssertEqual(player.handValue, 11)
        XCTAssertEqual(player.penalty, 2 * Rules.penaltyPerCard)
        XCTAssertEqual(player.score, 11 + 2 * Rules.penaltyPerCard)
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

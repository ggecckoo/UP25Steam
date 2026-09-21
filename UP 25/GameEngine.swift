//  GameEngine.swift
//  25-40 — oyun döngüsü + yönlendirmeli demo

import SwiftUI
import Combine

@MainActor
final class GameEngine: ObservableObject {

    enum Phase: Equatable { case menu, playing, reveal, over }

    struct CardRef: Equatable {
        let rank: Rank
        let suit: Suit
        func matches(_ card: Card) -> Bool { card.rank == rank && card.suit == suit }
    }

    /// Dil değişince yeniden çevrilebilen durum mesajı (ham string tutulmaz).
    enum StatusMessage: Equatable {
        case none
        case youAreHolder
        case holderIs(String)
        case playCard
        case thinking(String)
        case played(String)
        case revealing
        case over(String)
        case exact
        case cap
        case under(String)
        case demoRound1Start
        case demoHolderYou
        case demoTapHigh
        case demoRound1End
        case demoRound2Start
        case demoTapLow
        case demoRound2End
        case demoExplainExactCap
        case demoExplainGoal
        case demoDone
        case demoRevealing
        case demoWrongCard
        case demoWatch(String)
        case demoExplainOver(String)
        case demoExplainUnder(String)

        var text: String {
            switch self {
            case .none: return ""
            case .youAreHolder: return L10n.feedYouAreHolder
            case .holderIs(let n): return L10n.feedHolderIs(n)
            case .playCard: return L10n.feedPlayCard
            case .thinking(let n): return L10n.feedThinking(n)
            case .played(let n): return L10n.feedPlayed(n)
            case .revealing: return L10n.feedRevealing
            case .over(let n): return L10n.feedOver(n)
            case .exact: return L10n.feedExact
            case .cap: return L10n.feedCap
            case .under(let n): return L10n.feedUnder(n)
            case .demoRound1Start: return L10n.demoCoachRound1Start
            case .demoHolderYou: return L10n.demoCoachHolderYou
            case .demoTapHigh: return L10n.demoCoachTapHigh
            case .demoRound1End: return L10n.demoCoachRound1End
            case .demoRound2Start: return L10n.demoCoachRound2Start
            case .demoTapLow: return L10n.demoCoachTapLow
            case .demoRound2End: return L10n.demoCoachRound2End
            case .demoExplainExactCap: return L10n.demoCoachExactCap
            case .demoExplainGoal: return L10n.demoCoachGoal
            case .demoDone: return L10n.demoCoachDone
            case .demoRevealing: return L10n.demoCoachRevealing
            case .demoWrongCard: return L10n.demoCoachWrongCard
            case .demoWatch(let n): return L10n.demoCoachWatch(n)
            case .demoExplainOver(let n): return L10n.demoCoachExplainOver(n)
            case .demoExplainUnder(let n): return L10n.demoCoachExplainUnder(n)
            }
        }
    }

    @Published private(set) var phase: Phase = .menu
    @Published private(set) var players: [Player] = []
    @Published private(set) var table: [Played] = []
    @Published private(set) var holder: Int = 0
    @Published private(set) var round: Int = 1
    @Published private(set) var outcome: Outcome? = nil
    @Published private(set) var revealed: Bool = false
    @Published private(set) var sumShown: Bool = false
    @Published private(set) var status: StatusMessage = .none
    @Published private(set) var coach: StatusMessage = .none
    @Published private(set) var standings: [Standing] = []
    @Published private(set) var isDemo: Bool = false
    @Published private(set) var demoAwaitingIntro: Bool = false
    @Published private(set) var highlightTarget: CardRef? = nil
    @Published private(set) var canResume: Bool = false
    @Published private(set) var isPaused: Bool = false

    /// Yönlendirmeli demoda tur sayısı.
    static let demoRounds = 2

    private var middle: [Card] = []
    private var loop: Task<Void, Never>? = nil
    private var handGate: CheckedContinuation<Card?, Never>? = nil
    private var timeGate: CheckedContinuation<Void, Never>? = nil
    private var onDemoFinished: ((Bool) -> Void)?

    // MARK: Türetilmiş değerler
    var order: [Int] { (0..<4).map { (holder + $0) % 4 } }
    var tableSum: Int { table.reduce(0) { $0 + $1.card.value } }
    var me: Player { players.isEmpty ? Player(id: 0, name: "Sen", isHuman: true, hand: []) : players[0] }

    /// Görünen yönlendirme metni — her okumada güncel dile çözülür.
    var displayMessage: String {
        if isDemo, coach != .none { return coach.text }
        let t = status.text
        return t.isEmpty ? " " : t
    }

    var isMyTurn: Bool {
        phase == .playing && !isPaused && table.count < 4 && order[table.count] == 0
            && (players.first?.isHuman == true)
    }

    var actingPlayer: Int? {
        guard phase == .playing, !isPaused, table.count < 4 else { return nil }
        return order[table.count]
    }

    private var aiDelay: Double { isDemo ? 1.45 : Rules.aiDelay }
    private var sumDelay: Double { isDemo ? 2.2 : Rules.sumDelay }
    private var holdDelay: Double { isDemo ? 3.4 : Rules.holdDelay }

    // MARK: Oyunu kur
    func newGame(playerName: String = "Sen") {
        loop?.cancel()
        releaseHandGate()
        releaseTimeGate()
        clearDemoState()
        canResume = false
        isPaused = false

        let deck = Card.shuffledDeck()
        let names = [playerName, "Kemal", "Nur", "Sabri"]
        players = names.enumerated().map { index, name in
            let start = index * Rules.handSize
            let hand = Array(deck[start ..< (start + Rules.handSize)])
            return Player(id: index, name: name, isHuman: index == 0, hand: hand)
        }
        middle = Array(deck[(4 * Rules.handSize)...])

        holder = Int.random(in: 0..<4)
        round = 1
        table = []
        outcome = nil
        revealed = false
        sumShown = false
        standings = []
        status = .none
        coach = .none
        phase = .playing

        loop = Task { await self.runGame() }
    }

    func setPaused(_ paused: Bool) {
        guard !isDemo else { return }
        isPaused = paused
    }

    func quitToMenu() {
        isPaused = false
        pauseToMenu()
    }

    func pauseToMenu() {
        isPaused = false
        if isDemo {
            finishDemo(completed: false)
            return
        }
        loop?.cancel()
        releaseHandGate()
        releaseTimeGate()
        highlightTarget = nil
        coach = .none

        // Kartlar açıldıysa tur bitti sayılır: sonuç uygulanır, sonraki tura geçilir.
        // Böylece menüye gidip gelerek aynı turu ikinci kez oynama açığı kapanır.
        if phase == .reveal || revealed {
            finalizeRevealedRoundForPause()
            return
        }

        // Tur henüz açılmadı: masadaki kartlar ele geri, tur başa.
        for played in table {
            players[played.by].hand.append(played.card)
        }
        table = []
        outcome = nil
        revealed = false
        sumShown = false
        status = .none
        canResume = !players.isEmpty
        phase = .menu
    }

    /// Açılmış turun cezasını uygular ve bir sonraki tura (veya bitişe) hazırlar.
    private func finalizeRevealedRoundForPause() {
        if outcome == nil, !table.isEmpty {
            outcome = RoundRules.outcome(for: tableSum)
        }
        let finishedRound = round
        if !table.isEmpty {
            apply()
        }
        table = []
        revealed = false
        sumShown = false
        outcome = nil
        status = .none

        if finishedRound >= Rules.rounds {
            standings = players.map {
                Standing(id: $0.id, name: $0.name, cards: $0.hand.count,
                         value: $0.handValue, penalty: $0.penalty)
            }
            .sorted { ($0.score, $0.cards) < ($1.score, $1.cards) }
            canResume = false
        } else {
            round = finishedRound + 1
            canResume = true
        }
        phase = .menu
    }

    func resumeGame() {
        guard canResume, !players.isEmpty, !isDemo else { return }
        loop?.cancel()
        releaseHandGate()
        releaseTimeGate()
        isPaused = false
        table = []
        outcome = nil
        revealed = false
        sumShown = false
        status = holder == 0 ? .youAreHolder : .holderIs(players[holder].name)
        coach = .none
        phase = .playing
        loop = Task { await self.runGameFromCurrentRound() }
    }

    func returnToMenu() {
        isPaused = false
        if isDemo {
            finishDemo(completed: false)
            return
        }
        loop?.cancel()
        releaseHandGate()
        releaseTimeGate()
        canResume = false
        phase = .menu
    }

    func startDemo(onFinished: @escaping (Bool) -> Void) {
        loop?.cancel()
        releaseHandGate()
        releaseTimeGate()
        canResume = false

        isDemo = true
        demoAwaitingIntro = true
        onDemoFinished = onFinished
        highlightTarget = nil
        status = .none
        coach = .none

        dealScriptedDemoHands()
        holder = 0
        round = 1
        table = []
        outcome = nil
        revealed = false
        sumShown = false
        standings = []
        phase = .playing
    }

    /// Yönlendirmeli iki tur için sabit kartlar.
    private func dealScriptedDemoHands() {
        let r1Targets = [
            CardRef(rank: .king, suit: .spade),
            CardRef(rank: .nine, suit: .heart),
            CardRef(rank: .eight, suit: .diamond),
            CardRef(rank: .seven, suit: .club),
        ]
        let r2Targets = [
            CardRef(rank: .two, suit: .spade),
            CardRef(rank: .three, suit: .heart),
            CardRef(rank: .four, suit: .diamond),
            CardRef(rank: .five, suit: .club),
        ]

        let reserved = Set((r1Targets + r2Targets).map { "\($0.rank.rawValue)\($0.suit.rawValue)" })
        let filler = Card.shuffledDeck().filter {
            !reserved.contains("\($0.rank.rawValue)\($0.suit.rawValue)")
        }

        func hand(script: [CardRef], fillFrom: Int) -> [Card] {
            var cards = script.map { Card(rank: $0.rank, suit: $0.suit) }
            let need = Rules.handSize - cards.count
            cards.append(contentsOf: filler[fillFrom ..< (fillFrom + need)])
            return cards
        }

        players = [
            Player(id: 0, name: "Sen", isHuman: true,
                   hand: hand(script: [r1Targets[0], r2Targets[3]], fillFrom: 0)),
            Player(id: 1, name: "Kemal", isHuman: false,
                   hand: hand(script: [r1Targets[1], r2Targets[0]], fillFrom: 11)),
            Player(id: 2, name: "Nur", isHuman: false,
                   hand: hand(script: [r1Targets[2], r2Targets[1]], fillFrom: 22)),
            Player(id: 3, name: "Sabri", isHuman: false,
                   hand: hand(script: [r1Targets[3], r2Targets[2]], fillFrom: 33)),
        ]
        middle = Array(filler[44...])
    }

    func beginDemoPlay() {
        guard isDemo, demoAwaitingIntro else { return }
        demoAwaitingIntro = false
        loop = Task { await self.runGuidedDemo() }
    }

    func skipDemo() {
        guard isDemo else { return }
        finishDemo(completed: false)
    }

    // MARK: Ana döngü
    private func runGame() async {
        for r in 1...Rules.rounds {
            if Task.isCancelled { return }
            round = r
            await playRound()
            if Task.isCancelled { return }
        }
        canResume = false
        finish()
    }

    private func runGameFromCurrentRound() async {
        let start = max(round, 1)
        for r in start...Rules.rounds {
            if Task.isCancelled { return }
            round = r
            await playRound()
            if Task.isCancelled { return }
        }
        canResume = false
        finish()
    }

    private func runGuidedDemo() async {
        round = 1
        holder = 0
        coach = .demoRound1Start
        status = .demoHolderYou
        await sleep(2.4)
        if Task.isCancelled { return }

        await playDemoRound(
            script: [
                .init(rank: .king, suit: .spade),
                .init(rank: .nine, suit: .heart),
                .init(rank: .eight, suit: .diamond),
                .init(rank: .seven, suit: .club),
            ],
            humanHint: .demoTapHigh
        )
        if Task.isCancelled { return }

        coach = .demoRound1End
        await sleep(2.6)
        if Task.isCancelled { return }

        round = 2
        coach = .demoRound2Start
        status = .holderIs("Kemal")
        await sleep(2.2)
        if Task.isCancelled { return }

        await playDemoRound(
            script: [
                .init(rank: .two, suit: .spade),
                .init(rank: .three, suit: .heart),
                .init(rank: .four, suit: .diamond),
                .init(rank: .five, suit: .club),
            ],
            humanHint: .demoTapLow
        )
        if Task.isCancelled { return }

        coach = .demoRound2End
        await sleep(2.8)
        if Task.isCancelled { return }

        coach = .demoExplainExactCap
        await sleep(3.6)
        if Task.isCancelled { return }

        coach = .demoExplainGoal
        await sleep(3.6)
        if Task.isCancelled { return }

        coach = .demoDone
        await sleep(2.0)
        finishDemo(completed: true)
    }

    private func playDemoRound(script: [CardRef], humanHint: StatusMessage) async {
        table = []
        outcome = nil
        revealed = false
        sumShown = false

        for slot in 0..<4 {
            if Task.isCancelled { return }
            let pi = order[slot]
            let target = script[slot]

            if players[pi].isHuman {
                highlightTarget = target
                coach = humanHint
                status = humanHint
                guard let card = await waitForHumanCard() else { return }
                if Task.isCancelled { return }
                highlightTarget = nil
                place(card, by: pi)
                status = .played(players[pi].name)
            } else {
                highlightTarget = nil
                coach = .demoWatch(players[pi].name)
                status = .thinking(players[pi].name)
                await sleep(aiDelay)
                if Task.isCancelled { return }
                placeMatching(target, by: pi)
                status = .played(players[pi].name)
                await sleep(0.55)
            }
        }

        await resolveDemo()
    }

    private func playRound() async {
        table = []
        outcome = nil
        revealed = false
        sumShown = false
        status = holder == 0 ? .youAreHolder : .holderIs(players[holder].name)

        for slot in 0..<4 {
            if Task.isCancelled { return }
            let pi = order[slot]

            if players[pi].isHuman {
                status = holder == 0 ? .youAreHolder : .playCard
                guard let card = await waitForHumanCard() else { return }
                if Task.isCancelled { return }
                place(card, by: pi)
            } else {
                status = .thinking(players[pi].name)
                await sleep(aiDelay)
                if Task.isCancelled { return }
                let card = AI.pick(
                    hand: players[pi].hand,
                    isHolder: pi == holder,
                    running: tableSum,
                    after: 3 - slot,
                    round: round
                )
                place(card, by: pi)
                status = .played(players[pi].name)
            }
        }

        await resolve()
    }

    private func placeMatching(_ ref: CardRef, by index: Int) {
        if let match = players[index].hand.first(where: { ref.matches($0) }) {
            place(match, by: index)
        } else {
            place(Card(rank: ref.rank, suit: ref.suit), by: index)
        }
    }

    private func place(_ card: Card, by index: Int) {
        players[index].hand.removeAll { $0.id == card.id }
        SoundFX.cardPlayed()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
            table.append(Played(card: card, by: index))
        }
    }

    private func resolve() async {
        phase = .reveal
        let total = tableSum
        outcome = RoundRules.outcome(for: total)
        status = .revealing
        withAnimation { revealed = true }
        SoundFX.roundReveal()

        await gate(sumDelay)
        if Task.isCancelled { return }

        withAnimation { sumShown = true }
        let name = players[holder].name
        switch outcome! {
        case .over:  status = .over(name)
        case .exact: status = .exact
        case .cap:   status = .cap
        case .under: status = .under(name)
        }

        await gate(holdDelay)
        if Task.isCancelled { return }

        apply()
        phase = .playing
    }

    private func resolveDemo() async {
        phase = .reveal
        let total = tableSum
        outcome = RoundRules.outcome(for: total)
        coach = .demoRevealing
        status = .revealing
        withAnimation { revealed = true }
        SoundFX.roundReveal()

        await gate(sumDelay)
        if Task.isCancelled { return }

        withAnimation { sumShown = true }
        let name = players[holder].name
        switch outcome! {
        case .over:
            status = .over(name)
            coach = players[holder].isHuman ? .demoRound1End : .demoExplainOver(name)
        case .exact:
            status = .exact
            coach = .exact
        case .cap:
            status = .cap
            coach = .cap
        case .under:
            status = .under(name)
            coach = .demoExplainUnder(name)
        }

        await gate(holdDelay)
        if Task.isCancelled { return }

        apply()
        phase = .playing
    }

    private func apply() {
        var pile = table.map(\.card).shuffled() + middle
        let plan = RoundRules.draws(outcome: outcome ?? .under, holder: holder, order: order)

        for pi in order {
            guard let count = plan[pi], count > 0 else { continue }
            let take = min(count, pile.count)
            players[pi].hand.append(contentsOf: pile.prefix(take))
            pile.removeFirst(take)
        }

        middle = pile
        holder = (holder + 1) % 4
    }

    private func finish() {
        canResume = false
        standings = players.map {
            Standing(id: $0.id, name: $0.name, cards: $0.hand.count,
                     value: $0.handValue, penalty: $0.penalty)
        }
        .sorted { ($0.score, $0.cards) < ($1.score, $1.cards) }
        phase = .over
    }

    private func finishDemo(completed: Bool) {
        loop?.cancel()
        releaseHandGate()
        releaseTimeGate()
        highlightTarget = nil
        coach = .none
        demoAwaitingIntro = false
        let done = onDemoFinished
        onDemoFinished = nil
        // Menüye geç + UI demoyu kapatsın; sonra isDemo temizlenir.
        // Aksi halde showDemo hâlâ true iken isDemo=false → sahte oyun ekranı flaşı.
        phase = .menu
        done?(completed)
        clearDemoState()
        table = []
        outcome = nil
        revealed = false
        sumShown = false
        status = .none
    }

    private func clearDemoState() {
        isDemo = false
        demoAwaitingIntro = false
        coach = .none
        highlightTarget = nil
        onDemoFinished = nil
    }

    func play(_ card: Card) {
        guard isMyTurn, let gate = handGate else { return }
        if let target = highlightTarget, !target.matches(card) {
            coach = .demoWrongCard
            return
        }
        handGate = nil
        highlightTarget = nil
        gate.resume(returning: card)
    }

    func skipHold() {
        guard phase == .reveal, sumShown else { return }
        releaseTimeGate()
    }

    private func waitForHumanCard() async -> Card? {
        await withCheckedContinuation { (cont: CheckedContinuation<Card?, Never>) in
            handGate = cont
        }
    }

    private func sleep(_ seconds: Double) async {
        var remaining = seconds
        while remaining > 0.001 {
            if Task.isCancelled { return }
            while isPaused {
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            let slice = min(0.05, remaining)
            try? await Task.sleep(nanoseconds: UInt64(slice * 1_000_000_000))
            remaining -= slice
        }
    }

    private func gate(_ seconds: Double) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            timeGate = cont
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.sleep(seconds)
                self.releaseTimeGate()
            }
        }
    }

    private func releaseTimeGate() {
        guard let gate = timeGate else { return }
        timeGate = nil
        gate.resume()
    }

    private func releaseHandGate() {
        guard let gate = handGate else { return }
        handGate = nil
        gate.resume(returning: nil)
    }
}

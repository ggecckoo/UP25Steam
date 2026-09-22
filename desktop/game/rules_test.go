package game

import (
	"math/rand/v2"
	"testing"
)

type strategy int

const (
	strategyEngine strategy = iota
	strategyHigh
)

type sim struct {
	rng    *rand.Rand
	strats []strategy
	hands  [][]Card
	middle []Card
	holder int
	over   int
	exact  int
	cap    int
	under  int
	empty  bool
	loss   bool
	short  bool
}

func newSim(rng *rand.Rand, strats []strategy) *sim {
	deck := make([]Card, 0, 52)
	id := 1
	for suit := Suit(0); suit < 4; suit++ {
		for rank := Rank(0); rank < 13; rank++ {
			deck = append(deck, Card{ID: id, Rank: rank, Suit: suit})
			id++
		}
	}
	rng.Shuffle(len(deck), func(i, j int) { deck[i], deck[j] = deck[j], deck[i] })
	s := &sim{rng: rng, strats: strats, holder: rng.IntN(4)}
	for i := 0; i < 4; i++ {
		start := i * HandSize
		s.hands = append(s.hands, append([]Card(nil), deck[start:start+HandSize]...))
	}
	return s
}

func (s *sim) choose(pi, slot, running, round int) Card {
	hand := s.hands[pi]
	if s.strats[pi] == strategyHigh {
		best := hand[0]
		for _, card := range hand[1:] {
			if card.Value() > best.Value() {
				best = card
			}
		}
		return best
	}
	return Pick(s.rng, hand, pi == s.holder, running, 3-slot, round)
}

func (s *sim) run() {
	for round := 1; round <= Rounds; round++ {
		order := make([]int, 4)
		for i := 0; i < 4; i++ {
			order[i] = (s.holder + i) % 4
		}
		var table []Card
		for slot, pi := range order {
			if len(s.hands[pi]) == 0 {
				s.empty = true
				return
			}
			running := 0
			for _, card := range table {
				running += card.Value()
			}
			card := s.choose(pi, slot, running, round)
			s.hands[pi] = withoutCard(s.hands[pi], card.ID)
			table = append(table, card)
		}
		total := 0
		for _, card := range table {
			total += card.Value()
		}
		outcome := OutcomeFor(total)
		switch outcome {
		case OutcomeOver:
			s.over++
		case OutcomeExact:
			s.exact++
		case OutcomeCap:
			s.cap++
		default:
			s.under++
		}
		pile := append([]Card(nil), table...)
		s.rng.Shuffle(len(pile), func(i, j int) { pile[i], pile[j] = pile[j], pile[i] })
		pile = append(pile, s.middle...)
		plan := Draws(outcome, s.holder)
		for _, pi := range order {
			n := plan[pi]
			if n <= 0 {
				continue
			}
			if len(pile) < n {
				s.short = true
			}
			if n > len(pile) {
				n = len(pile)
			}
			s.hands[pi] = append(s.hands[pi], pile[:n]...)
			pile = pile[n:]
		}
		s.middle = pile
		n := len(s.middle)
		for _, hand := range s.hands {
			n += len(hand)
		}
		if n != 52 {
			s.loss = true
		}
		s.holder = (s.holder + 1) % 4
	}
}

func (s *sim) scores() [4]int {
	var out [4]int
	for i, hand := range s.hands {
		out[i] = HandValue(hand) + len(hand)*PenaltyPerCard
	}
	return out
}

func (s *sim) winner() int {
	scores := s.scores()
	best := 0
	for i := 1; i < 4; i++ {
		if scores[i] < scores[best] {
			best = i
		}
	}
	return best
}

func TestDeckIntegrity(t *testing.T) {
	for i := 0; i < 400; i++ {
		rng := rand.New(rand.NewPCG(uint64(i+1), 0x2540))
		s := newSim(rng, []strategy{strategyEngine, strategyEngine, strategyEngine, strategyEngine})
		s.run()
		if s.empty {
			t.Fatal("a hand was empty before the round")
		}
		if s.loss {
			t.Fatal("card count left 52")
		}
		if s.short {
			t.Fatal("the stock ran out")
		}
	}
}

func TestThresholdBalance(t *testing.T) {
	over, exact, cap, total := 0, 0, 0, 0
	for i := 0; i < 400; i++ {
		rng := rand.New(rand.NewPCG(uint64(1000+i), 0x2540))
		s := newSim(rng, []strategy{strategyEngine, strategyEngine, strategyEngine, strategyEngine})
		s.run()
		over += s.over
		exact += s.exact
		cap += s.cap
		total += s.over + s.exact + s.cap + s.under
	}
	overRate := float64(over) / float64(total)
	exactRate := float64(exact) / float64(total)
	capRate := float64(cap) / float64(total)
	if overRate < 0.48 || overRate > 0.60 {
		t.Fatalf("holder win rate out of range: %v", overRate)
	}
	if exactRate < 0.04 || exactRate > 0.12 {
		t.Fatalf("exact 25 rate out of range: %v", exactRate)
	}
	if capRate < 0.02 || capRate > 0.10 {
		t.Fatalf("exact 40 rate out of range: %v", capRate)
	}
}

func TestAlwaysHighestIsNotDominant(t *testing.T) {
	wins := 0
	const games = 1200
	for i := 0; i < games; i++ {
		rng := rand.New(rand.NewPCG(uint64(5000+i), 0x2540))
		s := newSim(rng, []strategy{strategyHigh, strategyEngine, strategyEngine, strategyEngine})
		s.run()
		if s.winner() == 0 {
			wins++
		}
	}
	rate := float64(wins) / float64(games)
	if rate >= 0.34 {
		t.Fatalf("always-highest became dominant: %v", rate)
	}
}

func TestHolderRotationIsEven(t *testing.T) {
	for start := 0; start < 4; start++ {
		counts := [4]int{}
		holder := start
		for range Rounds {
			counts[holder]++
			holder = (holder + 1) % 4
		}
		if counts != [4]int{3, 3, 3, 3} {
			t.Fatalf("start %d distribution %v", start, counts)
		}
	}
}

func TestScoreIncludesPenalty(t *testing.T) {
	player := Player{Hand: []Card{{Rank: King, Suit: Spade}, {Rank: Ace, Suit: Heart}}}
	if HandValue(player.Hand) != 11 {
		t.Fatal(HandValue(player.Hand))
	}
	if player.Penalty() != 8 || player.Score() != 19 {
		t.Fatalf("penalty %d score %d", player.Penalty(), player.Score())
	}
}

func TestOutcomeAndDrawPlan(t *testing.T) {
	if OutcomeFor(40) != OutcomeCap || OutcomeFor(39) != OutcomeOver || OutcomeFor(26) != OutcomeOver {
		t.Fatal("high outcomes")
	}
	if OutcomeFor(25) != OutcomeExact || OutcomeFor(24) != OutcomeUnder {
		t.Fatal("low outcomes")
	}
	if Draws(OutcomeOver, 2) != [4]int{} {
		t.Fatal("over draws")
	}
	if Draws(OutcomeUnder, 2) != [4]int{0, 0, 2, 0} {
		t.Fatal(Draws(OutcomeUnder, 2))
	}
	want := [4]int{1, 1, 0, 1}
	if Draws(OutcomeExact, 2) != want || Draws(OutcomeCap, 2) != want {
		t.Fatal("exact/cap draws")
	}
}

func TestPickThresholds(t *testing.T) {
	rng := rand.New(rand.NewPCG(1, 1))
	hand := []Card{{ID: 1, Rank: Ace, Suit: Spade}, {ID: 2, Rank: King, Suit: Heart}}
	if Pick(rng, hand, true, 0, 3, 1).Rank != King {
		t.Fatal("holder")
	}
	if Pick(rng, hand, false, 25, 0, 1).Rank != King {
		t.Fatal("forced high")
	}
	if Pick(rng, hand, false, 0, 0, 1).Rank != King {
		t.Fatal("free high")
	}
}

func TestFormatRound(t *testing.T) {
	if !SetLanguage("en") {
		t.Fatal("en")
	}
	if got := Format("game.round %lld %lld", 1, 12); got != "ROUND 1 / 12" {
		t.Fatal(got)
	}
	if !SetLanguage("tr") {
		t.Fatal("tr")
	}
	if got := Format("game.round %lld %lld", 1, 12); got != "TUR 1 / 12" {
		t.Fatal(got)
	}
	if T("ui.quit") != "Çıkış" {
		t.Fatal(T("ui.quit"))
	}
}

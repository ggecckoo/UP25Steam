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
	rng     *rand.Rand
	strats  []strategy
	hands   [][]Card
	stock   []Card
	discard []Card
	holder  int
	over    int
	exact   int
	cap     int
	under   int
	empty   bool
	loss    bool
	short   bool
}

func newSim(rng *rand.Rand, strats []strategy) *sim {
	deck := make([]Card, 0, DeckSize)
	id := 1
	for rank := Ace; rank <= King; rank++ {
		for suit := Suit(0); suit < 4; suit++ {
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
	s.stock = append([]Card(nil), deck[4*HandSize:]...)
	return s
}

func (s *sim) choose(pi int, table []Played) Card {
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
	holderDown := len(table) > 0 && table[0].By == s.holder
	return Pick(s.rng, hand, pi == s.holder, unseenValues(hand, s.discard), len(table), holderDown, 3-len(table))
}

func (s *sim) run() {
	for round := 1; round <= Rounds; round++ {
		order := make([]int, 4)
		for i := 0; i < 4; i++ {
			order[i] = (s.holder + i) % 4
		}
		var table []Played
		for _, pi := range order {
			if len(s.hands[pi]) == 0 {
				s.empty = true
				return
			}
			card := s.choose(pi, table)
			s.hands[pi] = withoutCard(s.hands[pi], card.ID)
			table = append(table, Played{Card: card, By: pi})
		}
		total := 0
		for _, played := range table {
			total += played.Card.Value()
			s.discard = append(s.discard, played.Card)
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
		plan := Draws(outcome, s.holder)
		wanted := 0
		for _, n := range plan {
			wanted += n
		}
		if wanted > len(s.stock) {
			s.stock = append(s.stock, s.discard...)
			s.discard = nil
			s.rng.Shuffle(len(s.stock), func(i, j int) { s.stock[i], s.stock[j] = s.stock[j], s.stock[i] })
		}
		for _, pi := range order {
			n := plan[pi]
			if n > len(s.stock) {
				s.short = true
				n = len(s.stock)
			}
			for k := 0; k < n; k++ {
				top := len(s.stock) - 1
				s.hands[pi] = append(s.hands[pi], s.stock[top])
				s.stock = s.stock[:top]
			}
		}
		n := len(s.stock) + len(s.discard)
		for _, hand := range s.hands {
			n += len(hand)
			if len(hand) == 0 {
				s.empty = true
			}
		}
		if n != DeckSize {
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
			t.Fatal("a hand ran out of cards")
		}
		if s.loss {
			t.Fatal("card count left the deck")
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
	if overRate < 0.52 || overRate > 0.66 {
		t.Fatalf("holder win rate out of range: %v", overRate)
	}
	if exactRate < 0.02 || exactRate > 0.09 {
		t.Fatalf("exact 25 rate out of range: %v", exactRate)
	}
	if capRate < 0.008 || capRate > 0.05 {
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
		if counts != [4]int{2, 2, 2, 2} {
			t.Fatalf("start %d distribution %v", start, counts)
		}
	}
}

func TestRankValuesAndLabels(t *testing.T) {
	values := []int{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 10, 10, 10}
	labels := []string{"A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"}
	total := 0
	for rank := Ace; rank <= King; rank++ {
		if rank.Value() != values[rank] {
			t.Fatalf("rank %d counts %d", rank, rank.Value())
		}
		if rank.Label() != labels[rank] {
			t.Fatalf("rank %d reads %q", rank, rank.Label())
		}
		total += 4 * rank.Value()
	}
	if total != 340 {
		t.Fatal(total)
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

func TestUnseenLeavesOutHandAndDiscard(t *testing.T) {
	hand := []Card{{ID: 1, Rank: King, Suit: Spade}, {ID: 2, Rank: Ace, Suit: Heart}}
	discard := []Card{{ID: 3, Rank: Ten, Suit: Club}, {ID: 4, Rank: Five, Suit: Club}}
	unseen := unseenValues(hand, discard)
	if len(unseen) != DeckSize-4 {
		t.Fatal(len(unseen))
	}
	count := map[int]int{}
	for _, v := range unseen {
		count[v]++
	}
	if count[10] != 14 || count[1] != 3 || count[5] != 3 || count[9] != 4 {
		t.Fatal(count)
	}
}

func repeat(value, n int) []int {
	out := make([]int, n)
	for i := range out {
		out[i] = value
	}
	return out
}

func TestPickHolderPlaysHigh(t *testing.T) {
	rng := rand.New(rand.NewPCG(1, 1))
	hand := []Card{{ID: 1, Rank: Ace, Suit: Spade}, {ID: 2, Rank: Five, Suit: Heart}, {ID: 3, Rank: King, Suit: Heart}}
	for i := 0; i < 100; i++ {
		if Pick(rng, hand, true, repeat(10, 30), 0, false, 3).Rank != King {
			t.Fatal("holder")
		}
	}
}

// A bot that cannot sink the holder sheds its king, unless the king would
// make exactly 40; one that can sink, and would otherwise make exactly 25,
// sinks with its ace; with nothing to lose either way it sheds the king.
func TestPickWeighsWhatItCannotSee(t *testing.T) {
	rng := rand.New(rand.NewPCG(1, 1))
	hand := []Card{{ID: 1, Rank: Ace, Suit: Spade}, {ID: 2, Rank: King, Suit: Heart}}
	cases := []struct {
		name       string
		unseen     int
		down       int
		holderDown bool
		after      int
		want       Rank
	}{
		{"forced high", 9, 1, true, 2, King},
		{"sink rather than make 25", 5, 3, true, 0, Ace},
		{"free high", 1, 3, true, 0, King},
	}
	for _, c := range cases {
		for i := 0; i < 100; i++ {
			if got := Pick(rng, hand, false, repeat(c.unseen, 30), c.down, c.holderDown, c.after); got.Rank != c.want {
				t.Fatalf("%s: played %s", c.name, got.Rank.Label())
			}
		}
	}
	// The king would make exactly 40. The ace is worth only a point and a
	// half more, a close call, so one time in five the bot plays the king.
	aces := 0
	const tries = 400
	for i := 0; i < tries; i++ {
		if Pick(rng, hand, false, repeat(10, 30), 1, true, 2).Rank == Ace {
			aces++
		}
	}
	if rate := float64(aces) / tries; rate < 0.7 || rate > 0.9 {
		t.Fatalf("shed into exactly 40: ace %v of the time", rate)
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

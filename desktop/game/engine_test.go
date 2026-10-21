package game

import (
	"encoding/json"
	"math/rand/v2"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestMain(m *testing.M) {
	dir, err := os.MkdirTemp("", "2540-test")
	if err != nil {
		panic(err)
	}
	saveOverride = filepath.Join(dir, "save.json")
	code := m.Run()
	os.RemoveAll(dir)
	os.Exit(code)
}

func isolate(t *testing.T) {
	t.Helper()
	saveOverride = filepath.Join(t.TempDir(), "save.json")
}

func TestEngineReachesGameOver(t *testing.T) {
	isolate(t)
	e := New()
	e.rng = rand.New(rand.NewPCG(9, 9))
	e.NewGame()
	for i := 0; i < 200000 && e.Phase != PhaseOver; i++ {
		if n := countCards(e); n != DeckSize {
			t.Fatalf("cards %d round %d phase %d", n, e.Round, e.Phase)
		}
		if e.HumanTurn() {
			index := 0
			if e.Holder == 0 {
				index = len(e.Players[0].Hand) - 1
			}
			if !e.PlayCard(index) {
				t.Fatal("play rejected")
			}
		} else {
			e.Tick(0.5)
		}
	}
	if e.Phase != PhaseOver {
		t.Fatalf("did not finish, phase %d round %d", e.Phase, e.Round)
	}
	if e.GamesFinished != 1 {
		t.Fatal(e.GamesFinished)
	}
	if e.CanResume() {
		t.Fatal("finished game still resumable")
	}
}

func TestQuitReturnsCards(t *testing.T) {
	isolate(t)
	e := New()
	e.rng = rand.New(rand.NewPCG(1, 2))
	e.NewGame()
	for i := 0; i < 100 && len(e.Table) == 0 && e.Phase == PhasePlaying; i++ {
		if e.HumanTurn() {
			e.PlayCard(0)
		} else {
			e.Tick(2)
		}
	}
	if len(e.Table) == 0 {
		t.Fatal("no card reached the table")
	}
	e.QuitMatch()
	if e.Phase != PhaseMenu || !e.CanResume() || len(e.Table) != 0 || countCards(e) != DeckSize {
		t.Fatalf("phase %d resume %v cards %d", e.Phase, e.CanResume(), countCards(e))
	}
	e2 := New()
	if !e2.CanResume() || countCards(e2) != DeckSize {
		t.Fatalf("reload resume %v cards %d", e2.CanResume(), countCards(e2))
	}
	e2.Resume()
	if e2.Phase != PhasePlaying || len(e2.Table) != 0 {
		t.Fatalf("resume phase %d table %d", e2.Phase, len(e2.Table))
	}
}

func TestQuitOnFinalRevealEndsMatch(t *testing.T) {
	isolate(t)
	e := New()
	e.rng = rand.New(rand.NewPCG(4, 4))
	e.NewGame()
	e.Round = Rounds
	e.Phase = PhaseReveal
	e.HasOutcome = true
	e.Outcome = OutcomeOver
	e.SumShown = true
	e.applied = false
	e.Table = nil
	for i := 0; i < 4; i++ {
		card := e.Players[i].Hand[0]
		e.Players[i].Hand = e.Players[i].Hand[1:]
		e.Table = append(e.Table, Played{Card: card, By: i})
	}
	e.QuitMatch()
	if e.Phase != PhaseOver || e.CanResume() || e.GamesFinished != 1 || countCards(e) != DeckSize {
		t.Fatalf("phase %d resume %v finished %d cards %d", e.Phase, e.CanResume(), e.GamesFinished, countCards(e))
	}
}

func TestSwiftSaveKeepsSoundOn(t *testing.T) {
	isolate(t)
	body := []byte(`{"version":1,"gamesFinished":2,"gamesWon":1,"demoCompleted":true}`)
	if err := os.WriteFile(saveOverride, body, 0o644); err != nil {
		t.Fatal(err)
	}
	e := New()
	if !e.Sound || e.GamesFinished != 2 || e.GamesWon != 1 || !e.demoDone {
		t.Fatalf("sound %v finished %d won %d demo %v", e.Sound, e.GamesFinished, e.GamesWon, e.demoDone)
	}
	e.SetSound(false)
	data, err := os.ReadFile(saveOverride)
	if err != nil {
		t.Fatal(err)
	}
	text := string(data)
	if !strings.Contains(text, `"demoCompleted": true`) || !strings.Contains(text, `"sound": false`) {
		t.Fatal(text)
	}
	if strings.Contains(text, `"gamesWon": 2`) {
		t.Fatal("wins changed")
	}
}

func TestInvalidResumeIsDropped(t *testing.T) {
	isolate(t)
	body := []byte(`{"version":1,"gamesFinished":3,"gamesWon":9,"sound":false,"resume":{"round":1,"holder":0,"hands":[[],[],[],[]],"stock":[],"discard":[]}}`)
	if err := os.WriteFile(saveOverride, body, 0o644); err != nil {
		t.Fatal(err)
	}
	e := New()
	if e.CanResume() || e.Sound || e.GamesFinished != 3 || e.GamesWon != 3 {
		t.Fatalf("resume %v sound %v finished %d won %d", e.CanResume(), e.Sound, e.GamesFinished, e.GamesWon)
	}
}

// checkDeck fails unless the hands, the table, the stock and the discard
// hold the 52 cards once each.
func checkDeck(t *testing.T, e *Engine) {
	t.Helper()
	all := append(append([]Card(nil), e.stock...), e.discard...)
	for _, played := range e.Table {
		all = append(all, played.Card)
	}
	for _, p := range e.Players {
		all = append(all, p.Hand...)
	}
	if len(all) != DeckSize {
		t.Fatalf("%d cards", len(all))
	}
	ids := map[int]bool{}
	faces := map[[2]int]bool{}
	for _, c := range all {
		face := [2]int{int(c.Rank), int(c.Suit)}
		if ids[c.ID] || faces[face] {
			t.Fatalf("card %s%s twice", c.Rank.Label(), c.Suit.Symbol())
		}
		ids[c.ID] = true
		faces[face] = true
	}
}

func dealt(t *testing.T, seed uint64) *Engine {
	t.Helper()
	isolate(t)
	e := New()
	e.rng = rand.New(rand.NewPCG(seed, seed))
	e.NewGame()
	return e
}

// playLast puts each player's last card face down on the table, holder first.
func playLast(e *Engine) {
	for _, pi := range e.Order() {
		hand := e.Players[pi].Hand
		card := hand[len(hand)-1]
		e.Players[pi].Hand = withoutCard(hand, card.ID)
		e.Table = append(e.Table, Played{Card: card, By: pi})
	}
}

func hasCard(cards []Card, id int) bool {
	for _, c := range cards {
		if c.ID == id {
			return true
		}
	}
	return false
}

func TestDealLeavesSixteenInStock(t *testing.T) {
	e := dealt(t, 9)
	for _, p := range e.Players {
		if len(p.Hand) != HandSize {
			t.Fatalf("%s holds %d", p.Name, len(p.Hand))
		}
	}
	if len(e.stock) != 16 || len(e.discard) != 0 || len(e.Table) != 0 {
		t.Fatalf("stock %d discard %d table %d", len(e.stock), len(e.discard), len(e.Table))
	}
	checkDeck(t, e)
}

func TestUnderDrawsTheStockTop(t *testing.T) {
	e := dealt(t, 21)
	e.Holder = 1
	playLast(e)
	top := []int{e.stock[len(e.stock)-1].ID, e.stock[len(e.stock)-2].ID}
	row := e.Table
	e.Outcome = OutcomeUnder
	e.HasOutcome = true
	e.applyRound()
	holder := e.Players[1].Hand
	if len(holder) != HandSize+1 || !hasCard(holder, top[0]) || !hasCard(holder, top[1]) {
		t.Fatalf("holder drew wrong: %d cards", len(holder))
	}
	for _, pi := range []int{0, 2, 3} {
		if len(e.Players[pi].Hand) != HandSize-1 {
			t.Fatalf("seat %d holds %d", pi, len(e.Players[pi].Hand))
		}
	}
	if len(e.stock) != 14 || len(e.discard) != 4 {
		t.Fatalf("stock %d discard %d", len(e.stock), len(e.discard))
	}
	for _, played := range row {
		if !hasCard(e.discard, played.Card.ID) {
			t.Fatalf("round card %d not on the discard", played.Card.ID)
		}
	}
	checkDeck(t, e)
}

func TestShortStockTakesTheDiscardBack(t *testing.T) {
	e := dealt(t, 21)
	for len(e.stock) > 1 {
		top := len(e.stock) - 1
		e.discard = append(e.discard, e.stock[top])
		e.stock = e.stock[:top]
	}
	e.Holder = 2
	playLast(e)
	e.Outcome = OutcomeExact
	e.HasOutcome = true
	e.applyRound()
	for _, p := range e.Players {
		want := HandSize
		if p.ID == 2 {
			want = HandSize - 1
		}
		if len(p.Hand) != want {
			t.Fatalf("seat %d holds %d", p.ID, len(p.Hand))
		}
	}
	if len(e.discard) != 0 || len(e.stock) != 16+4-3 {
		t.Fatalf("stock %d discard %d", len(e.stock), len(e.discard))
	}
	checkDeck(t, e)
}

// Seat 3 plays third, after the holder in seat 1 and seat 2. Whether those
// two put down their highest or their lowest card, seat 3 sees the same
// hand and the same discard, so it plays the same card.
func TestPickIgnoresFaceDownCards(t *testing.T) {
	for seed := uint64(1); seed <= 40; seed++ {
		var picks, sums [2]int
		for variant := 0; variant < 2; variant++ {
			e := dealt(t, seed)
			playLast(e)
			e.Outcome = OutcomeFor(e.TableSum())
			e.HasOutcome = true
			e.applyRound()
			e.Holder = 1
			for _, pi := range []int{1, 2} {
				hand := e.Players[pi].Hand
				card := hand[0]
				for _, c := range hand {
					if (variant == 0 && c.Value() > card.Value()) || (variant == 1 && c.Value() < card.Value()) {
						card = c
					}
				}
				e.Players[pi].Hand = withoutCard(hand, card.ID)
				e.Table = append(e.Table, Played{Card: card, By: pi})
			}
			sums[variant] = e.TableSum()
			e.rng = rand.New(rand.NewPCG(seed, 99))
			picks[variant] = e.choose(3).ID
		}
		if sums[0] <= sums[1] {
			t.Fatalf("seed %d: face-down totals %v", seed, sums)
		}
		if picks[0] != picks[1] {
			t.Fatalf("seed %d: the face-down cards changed the pick", seed)
		}
	}
}

func TestBotsPlayWholeHands(t *testing.T) {
	isolate(t)
	e := New()
	const hands = 150
	for n := 0; n < hands; n++ {
		e.rng = rand.New(rand.NewPCG(uint64(n+1), 0x2540))
		e.NewGame()
		for i := 0; i < 10000 && e.Phase != PhaseOver; i++ {
			checkDeck(t, e)
			for _, p := range e.Players {
				if len(p.Hand) == 0 {
					t.Fatalf("hand %d round %d: %s has no cards", n, e.Round, p.Name)
				}
			}
			if e.HumanTurn() {
				card := e.choose(0)
				index := -1
				for k, c := range e.Players[0].Hand {
					if c.ID == card.ID {
						index = k
					}
				}
				if !e.PlayCard(index) {
					t.Fatal("play rejected")
				}
			} else {
				e.Tick(0.5)
			}
		}
		if e.Phase != PhaseOver || e.Round != Rounds {
			t.Fatalf("hand %d ended in round %d, phase %d", n, e.Round, e.Phase)
		}
		checkDeck(t, e)
		for _, row := range e.Standings {
			if row.Cards == 0 {
				t.Fatalf("hand %d: %s ended with no cards", n, row.Name)
			}
		}
	}
	if e.GamesFinished != hands {
		t.Fatal(e.GamesFinished)
	}
}

func TestResumeKeepsStockAndDiscard(t *testing.T) {
	isolate(t)
	e := New()
	e.rng = rand.New(rand.NewPCG(6, 6))
	e.NewGame()
	for i := 0; i < 10000 && e.Round < 3; i++ {
		if e.HumanTurn() {
			e.PlayCard(0)
		} else {
			e.Tick(0.5)
		}
	}
	if e.Round != 3 || len(e.discard) != 8 {
		t.Fatalf("round %d discard %d", e.Round, len(e.discard))
	}
	e.QuitMatch()
	e2 := New()
	if !e2.CanResume() {
		t.Fatal("no resume")
	}
	checkDeck(t, e2)
	same := func(a, b []Card) bool {
		if len(a) != len(b) {
			return false
		}
		for i := range a {
			if a[i].Rank != b[i].Rank || a[i].Suit != b[i].Suit {
				return false
			}
		}
		return true
	}
	if !same(e.stock, e2.stock) || !same(e.discard, e2.discard) {
		t.Fatalf("stock %d/%d discard %d/%d", len(e.stock), len(e2.stock), len(e.discard), len(e2.discard))
	}
}

func TestOldDeckSaveDoesNotResume(t *testing.T) {
	isolate(t)
	// A 30-80 save: 28 cards (aces, odd pips, jacks and kings), seven a hand.
	hands := make([][]cardDisk, 4)
	k := 0
	for _, rank := range []Rank{Ace, Three, Five, Seven, Nine, Jack, King} {
		for suit := 0; suit < 4; suit++ {
			hands[k%4] = append(hands[k%4], cardDisk{R: int(rank), S: suit})
			k++
		}
	}
	body, err := json.Marshal(map[string]any{
		"version":       1,
		"gamesFinished": 5,
		"gamesWon":      2,
		"sound":         false,
		"resume": map[string]any{
			"round":  3,
			"holder": 1,
			"names":  []string{"Player", "Kemal", "Nur", "Sabri"},
			"hands":  hands,
			"middle": []cardDisk{},
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(saveOverride, body, 0o644); err != nil {
		t.Fatal(err)
	}
	e := New()
	if e.CanResume() || len(e.Players) != 0 || e.Sound || e.GamesFinished != 5 || e.GamesWon != 2 {
		t.Fatalf("resume %v sound %v finished %d won %d", e.CanResume(), e.Sound, e.GamesFinished, e.GamesWon)
	}
}

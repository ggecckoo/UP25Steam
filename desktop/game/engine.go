package game

import (
	"math/rand/v2"
	"strings"
	"time"
)

type Phase int

const (
	PhaseMenu Phase = iota
	PhasePlaying
	PhaseReveal
	PhaseOver
)

type Standing struct {
	ID      int
	Name    string
	Cards   int
	Value   int
	Penalty int
	Score   int
}

type Cue int

const (
	CueNone Cue = iota
	CueCard
	CueReveal
)

type statusKind int

const (
	statusNone statusKind = iota
	statusYouHolder
	statusPlay
	statusThinking
	statusRevealing
	statusOver
	statusExact
	statusCap
	statusUnder
)

const (
	stageIdle = iota
	stageWaitAI
	stageFlip
	stageHold
)

type Engine struct {
	Phase         Phase
	Players       []Player
	Table         []Played
	Holder        int
	Round         int
	Outcome       Outcome
	HasOutcome    bool
	SumShown      bool
	RevealAge     float64
	Standings     []Standing
	GamesFinished int
	GamesWon      int
	Sound         bool
	Paused        bool

	// The croupier's deck (top card last) and the cards played out this hand.
	stock      []Card
	discard    []Card
	rng        *rand.Rand
	timer      float64
	stage      int
	status     statusKind
	statusName string
	pending    Cue
	recorded   bool
	canResume  bool
	applied    bool
	nextID     int
	demoDone   bool
}

func New() *Engine {
	e := &Engine{
		Phase: PhaseMenu,
		Sound: true,
		rng:   rand.New(rand.NewPCG(uint64(time.Now().UnixNano()), 0x25402540)),
	}
	e.load()
	return e
}

func (e *Engine) NewGame() {
	e.Paused = false
	e.recorded = false
	e.applied = false
	deck := e.newDeck()
	names := []string{T("common.player"), "Kemal", "Nur", "Sabri"}
	e.Players = make([]Player, 4)
	for i := 0; i < 4; i++ {
		start := i * HandSize
		hand := append([]Card(nil), deck[start:start+HandSize]...)
		e.Players[i] = Player{ID: i, Name: names[i], Human: i == 0, Hand: hand}
	}
	sortHand(e.Players[0].Hand)
	e.stock = append([]Card(nil), deck[4*HandSize:]...)
	e.discard = nil
	e.Holder = e.rng.IntN(4)
	e.Round = 1
	e.Standings = nil
	e.Table = nil
	e.startRound()
}

func (e *Engine) Resume() {
	if !e.CanResume() {
		return
	}
	e.recorded = false
	e.startRound()
}

func (e *Engine) CanResume() bool {
	return e.canResume && len(e.Players) == 4 && e.Round >= 1 && e.Round <= Rounds && e.Phase != PhaseOver
}

func (e *Engine) ReturnToMenu() {
	e.Paused = false
	e.Phase = PhaseMenu
	e.canResume = false
	e.Players = nil
	e.Table = nil
	e.stock = nil
	e.discard = nil
	e.Standings = nil
	e.recorded = false
	e.HasOutcome = false
	e.SumShown = false
	e.Save()
}

func (e *Engine) SetPaused(paused bool) {
	if e.Phase != PhasePlaying && e.Phase != PhaseReveal {
		return
	}
	e.Paused = paused
}

func (e *Engine) SetSound(on bool) {
	e.Sound = on
	e.Save()
}

func (e *Engine) QuitMatch() {
	e.Paused = false
	switch e.Phase {
	case PhaseReveal:
		e.finishReveal()
		if e.Phase == PhaseOver {
			return
		}
		e.Phase = PhaseMenu
		e.canResume = len(e.Players) == 4
		e.Save()
	case PhasePlaying:
		for _, played := range e.Table {
			if played.By >= 0 && played.By < len(e.Players) {
				e.Players[played.By].Hand = append(e.Players[played.By].Hand, played.Card)
			}
		}
		if len(e.Players) > 0 {
			sortHand(e.Players[0].Hand)
		}
		e.Table = nil
		e.HasOutcome = false
		e.SumShown = false
		e.Phase = PhaseMenu
		e.canResume = len(e.Players) == 4
		e.Save()
	default:
		e.Phase = PhaseMenu
	}
}

func (e *Engine) Tick(dt float64) {
	if dt <= 0 || e.Paused {
		return
	}
	switch e.Phase {
	case PhasePlaying:
		e.tickPlaying(dt)
	case PhaseReveal:
		e.tickReveal(dt)
	}
}

func (e *Engine) PlayCard(index int) bool {
	if !e.HumanTurn() || index < 0 || index >= len(e.Players[0].Hand) {
		return false
	}
	e.place(0, e.Players[0].Hand[index])
	return true
}

func (e *Engine) SkipReveal() {
	if e.Phase != PhaseReveal || e.Paused {
		return
	}
	if !e.SumShown {
		e.showSum()
		return
	}
	e.finishReveal()
}

func (e *Engine) HumanTurn() bool {
	if e.Phase != PhasePlaying || e.Paused || len(e.Table) >= 4 || len(e.Players) == 0 || !e.Players[0].Human {
		return false
	}
	return e.Order()[len(e.Table)] == 0
}

func (e *Engine) Acting() int {
	if e.Phase != PhasePlaying || e.Paused || len(e.Table) >= 4 || len(e.Players) < 4 {
		return -1
	}
	return e.Order()[len(e.Table)]
}

func (e *Engine) Order() []int {
	order := make([]int, 4)
	for i := 0; i < 4; i++ {
		order[i] = (e.Holder + i) % 4
	}
	return order
}

func (e *Engine) TableSum() int {
	n := 0
	for _, played := range e.Table {
		n += played.Card.Value()
	}
	return n
}

// Stock is the croupier's face-down deck, top card last.
func (e *Engine) Stock() []Card { return e.stock }

// Discard is the cards played out in earlier rounds of this hand.
func (e *Engine) Discard() []Card { return e.discard }

func (e *Engine) TurnToken() int { return e.Round*10 + len(e.Table) }

func (e *Engine) CardFaceUp(index int) bool {
	if e.Phase != PhaseReveal {
		return false
	}
	if e.SumShown {
		return true
	}
	return e.RevealAge >= float64(index)*FlipStep
}

func (e *Engine) TakeSound() Cue {
	cue := e.pending
	e.pending = CueNone
	return cue
}

func (e *Engine) StatusText() string {
	switch e.status {
	case statusYouHolder:
		return T("feed.youAreHolder")
	case statusPlay:
		return T("feed.playCard")
	case statusThinking:
		return Format("feed.thinking %@", e.statusName)
	case statusRevealing:
		return T("feed.revealing")
	case statusOver:
		return Format("feed.over %@", e.statusName)
	case statusExact:
		return T("feed.exact")
	case statusCap:
		return T("feed.cap")
	case statusUnder:
		return Format("feed.under %@", e.statusName)
	default:
		return ""
	}
}

func (e *Engine) VerdictText() string {
	if !e.SumShown || !e.HasOutcome || e.Holder < 0 || e.Holder >= len(e.Players) {
		return ""
	}
	name := strings.ToUpper(e.Players[e.Holder].Name)
	switch e.Outcome {
	case OutcomeOver:
		return Format("verdict.over %@", name)
	case OutcomeExact:
		return Format("verdict.exact %@", name)
	case OutcomeCap:
		return Format("verdict.cap %@", name)
	default:
		return Format("verdict.under %@", name)
	}
}

func (e *Engine) HintText() string {
	if !e.HumanTurn() {
		return ""
	}
	if e.Holder == 0 {
		return T("game.hint.holder")
	}
	return T("game.hint.other")
}

func (e *Engine) startRound() {
	e.Phase = PhasePlaying
	e.Table = nil
	e.HasOutcome = false
	e.SumShown = false
	e.RevealAge = 0
	e.applied = false
	e.Paused = false
	e.canResume = true
	e.armTurn()
	e.Save()
}

func (e *Engine) armTurn() {
	if len(e.Players) < 4 || len(e.Table) >= 4 {
		return
	}
	pi := e.Order()[len(e.Table)]
	if len(e.Players[pi].Hand) == 0 {
		e.finishGame()
		return
	}
	if pi == 0 {
		if e.Holder == 0 {
			e.status = statusYouHolder
		} else {
			e.status = statusPlay
		}
		e.statusName = ""
		e.stage = stageIdle
		return
	}
	e.status = statusThinking
	e.statusName = e.Players[pi].Name
	e.stage = stageWaitAI
	e.timer = AIDelay
}

func (e *Engine) tickPlaying(dt float64) {
	if e.HumanTurn() || e.stage != stageWaitAI {
		return
	}
	e.timer -= dt
	if e.timer > 0 {
		return
	}
	pi := e.Acting()
	if pi < 0 {
		return
	}
	e.playAI(pi)
}

func (e *Engine) playAI(pi int) {
	if len(e.Players[pi].Hand) == 0 {
		e.finishGame()
		return
	}
	e.place(pi, e.choose(pi))
}

// choose is the card a bot in seat pi plays now. It knows what a player at
// the table knows: its own hand, the cards turned up in earlier rounds, and
// how many cards lie face down this round, never what they are.
func (e *Engine) choose(pi int) Card {
	hand := e.Players[pi].Hand
	holderDown := len(e.Table) > 0 && e.Table[0].By == e.Holder
	unseen := unseenValues(hand, e.discard)
	return Pick(e.rng, hand, pi == e.Holder, unseen, len(e.Table), holderDown, 3-len(e.Table))
}

func (e *Engine) place(pi int, card Card) {
	e.Players[pi].Hand = withoutCard(e.Players[pi].Hand, card.ID)
	e.Table = append(e.Table, Played{Card: card, By: pi})
	e.pending = CueCard
	if len(e.Table) >= 4 {
		e.beginReveal()
		return
	}
	e.armTurn()
}

func (e *Engine) beginReveal() {
	e.Phase = PhaseReveal
	e.Outcome = OutcomeFor(e.TableSum())
	e.HasOutcome = true
	e.SumShown = false
	e.RevealAge = 0
	e.stage = stageFlip
	e.timer = SumDelay
	e.status = statusRevealing
	e.statusName = ""
	e.pending = CueReveal
}

func (e *Engine) tickReveal(dt float64) {
	e.RevealAge += dt
	e.timer -= dt
	if e.timer > 0 {
		return
	}
	switch e.stage {
	case stageFlip:
		e.showSum()
	case stageHold:
		e.finishReveal()
	}
}

func (e *Engine) showSum() {
	e.SumShown = true
	e.RevealAge = SumDelay
	e.stage = stageHold
	e.timer = HoldDelay
	e.setVerdict()
}

func (e *Engine) setVerdict() {
	if e.Holder >= 0 && e.Holder < len(e.Players) {
		e.statusName = e.Players[e.Holder].Name
	}
	switch e.Outcome {
	case OutcomeOver:
		e.status = statusOver
	case OutcomeExact:
		e.status = statusExact
	case OutcomeCap:
		e.status = statusCap
	default:
		e.status = statusUnder
	}
}

func (e *Engine) finishReveal() {
	e.applyRound()
	if e.Round >= Rounds {
		e.finishGame()
		return
	}
	e.Round++
	e.startRound()
}

func (e *Engine) applyRound() {
	if e.applied {
		return
	}
	e.applied = true
	if !e.HasOutcome {
		e.Outcome = OutcomeFor(e.TableSum())
		e.HasOutcome = true
	}
	// The round's cards are played out; whoever draws gets the croupier's
	// top cards. If the stock has too few, the played-out cards are shuffled
	// back in with what is left of it first.
	for _, played := range e.Table {
		e.discard = append(e.discard, played.Card)
	}
	plan := Draws(e.Outcome, e.Holder)
	wanted := 0
	for _, n := range plan {
		wanted += n
	}
	if wanted > len(e.stock) {
		e.stock = append(e.stock, e.discard...)
		e.discard = nil
		e.rng.Shuffle(len(e.stock), func(i, j int) { e.stock[i], e.stock[j] = e.stock[j], e.stock[i] })
	}
	for _, pi := range e.Order() {
		n := min(plan[pi], len(e.stock))
		if n <= 0 {
			continue
		}
		for k := 0; k < n; k++ {
			top := len(e.stock) - 1
			e.Players[pi].Hand = append(e.Players[pi].Hand, e.stock[top])
			e.stock = e.stock[:top]
		}
		if pi == 0 {
			sortHand(e.Players[pi].Hand)
		}
	}
	e.Holder = (e.Holder + 1) % 4
	e.Table = nil
	e.HasOutcome = false
	e.SumShown = false
}

func (e *Engine) finishGame() {
	if e.Phase == PhaseOver {
		return
	}
	for _, played := range e.Table {
		e.discard = append(e.discard, played.Card)
	}
	e.Table = nil
	e.Phase = PhaseOver
	e.Paused = false
	e.canResume = false
	e.Standings = e.standings()
	if !e.recorded {
		e.recorded = true
		e.GamesFinished++
		if len(e.Standings) > 0 && e.Standings[0].ID == 0 {
			e.GamesWon++
		}
	}
	e.Save()
}

func (e *Engine) standings() []Standing {
	rows := make([]Standing, len(e.Players))
	for i, p := range e.Players {
		rows[i] = Standing{
			ID:      p.ID,
			Name:    p.Name,
			Cards:   len(p.Hand),
			Value:   HandValue(p.Hand),
			Penalty: p.Penalty(),
			Score:   p.Score(),
		}
	}
	for i := 1; i < len(rows); i++ {
		row := rows[i]
		j := i
		for j > 0 && worse(rows[j-1], row) {
			rows[j] = rows[j-1]
			j--
		}
		rows[j] = row
	}
	return rows
}

func worse(a, b Standing) bool {
	if a.Score != b.Score {
		return a.Score > b.Score
	}
	if a.Cards != b.Cards {
		return a.Cards > b.Cards
	}
	return a.ID > b.ID
}

func (e *Engine) newDeck() []Card {
	deck := make([]Card, 0, DeckSize)
	for rank := Ace; rank <= King; rank++ {
		for suit := Suit(0); suit < 4; suit++ {
			deck = append(deck, e.mint(rank, suit))
		}
	}
	e.rng.Shuffle(len(deck), func(i, j int) { deck[i], deck[j] = deck[j], deck[i] })
	return deck
}

func (e *Engine) mint(rank Rank, suit Suit) Card {
	e.nextID++
	return Card{ID: e.nextID, Rank: rank, Suit: suit}
}

func sortHand(hand []Card) {
	for i := 1; i < len(hand); i++ {
		card := hand[i]
		j := i
		for j > 0 && cardLess(card, hand[j-1]) {
			hand[j] = hand[j-1]
			j--
		}
		hand[j] = card
	}
}

func cardLess(a, b Card) bool {
	if a.Value() != b.Value() {
		return a.Value() < b.Value()
	}
	if a.Suit != b.Suit {
		return a.Suit < b.Suit
	}
	return a.Rank < b.Rank
}

func withoutCard(hand []Card, id int) []Card {
	for i, card := range hand {
		if card.ID == id {
			out := make([]Card, 0, len(hand)-1)
			out = append(out, hand[:i]...)
			out = append(out, hand[i+1:]...)
			return out
		}
	}
	return hand
}

func countCards(e *Engine) int {
	n := len(e.stock) + len(e.discard) + len(e.Table)
	for _, p := range e.Players {
		n += len(p.Hand)
	}
	return n
}

package game

import "math/rand/v2"

const (
	Limit          = 25
	Cap            = 40
	Rounds         = 12
	HandSize       = 13
	PenaltyPerCard = 4
	AIDelay        = 1.15
	SumDelay       = 1.70
	HoldDelay      = 2.90
	FlipStep       = 0.36
)

type Suit int

const (
	Spade Suit = iota
	Heart
	Diamond
	Club
)

func (s Suit) Symbol() string {
	switch s {
	case Heart:
		return "♥"
	case Diamond:
		return "♦"
	case Club:
		return "♣"
	default:
		return "♠"
	}
}

func (s Suit) Red() bool { return s == Heart || s == Diamond }

type Rank int

const (
	Ace Rank = iota
	Two
	Three
	Four
	Five
	Six
	Seven
	Eight
	Nine
	Ten
	Jack
	Queen
	King
)

func (r Rank) Value() int {
	switch r {
	case Ace:
		return 1
	case Two:
		return 2
	case Three:
		return 3
	case Four:
		return 4
	case Five:
		return 5
	case Six:
		return 6
	case Seven:
		return 7
	case Eight:
		return 8
	case Nine:
		return 9
	default:
		return 10
	}
}

func (r Rank) Label() string {
	switch r {
	case Ace:
		return "A"
	case Two:
		return "2"
	case Three:
		return "3"
	case Four:
		return "4"
	case Five:
		return "5"
	case Six:
		return "6"
	case Seven:
		return "7"
	case Eight:
		return "8"
	case Nine:
		return "9"
	case Ten:
		return "10"
	case Jack:
		return "J"
	case Queen:
		return "Q"
	default:
		return "K"
	}
}

type Card struct {
	ID   int
	Rank Rank
	Suit Suit
}

func (c Card) Value() int { return c.Rank.Value() }
func (c Card) Red() bool  { return c.Suit.Red() }

type Player struct {
	ID    int
	Name  string
	Human bool
	Hand  []Card
}

func HandValue(hand []Card) int {
	n := 0
	for _, c := range hand {
		n += c.Value()
	}
	return n
}

func (p Player) Penalty() int { return len(p.Hand) * PenaltyPerCard }
func (p Player) Score() int   { return HandValue(p.Hand) + p.Penalty() }

type Played struct {
	Card Card
	By   int
}

type Outcome int

const (
	OutcomeOver Outcome = iota
	OutcomeExact
	OutcomeCap
	OutcomeUnder
)

func OutcomeFor(total int) Outcome {
	if total == Cap {
		return OutcomeCap
	}
	if total > Limit {
		return OutcomeOver
	}
	if total == Limit {
		return OutcomeExact
	}
	return OutcomeUnder
}

// Draws reports how many cards each player picks up. Index is the player ID.
// The caller must deal those cards in table order; that order changes who
// receives which card when the stock is short.
func Draws(outcome Outcome, holder int) [4]int {
	var plan [4]int
	switch outcome {
	case OutcomeExact, OutcomeCap:
		for i := 0; i < 4; i++ {
			if i != holder {
				plan[i] = 1
			}
		}
	case OutcomeUnder:
		plan[holder] = 2
	}
	return plan
}

func Pick(rng *rand.Rand, hand []Card, isHolder bool, running, after, round int) Card {
	if len(hand) == 0 {
		return Card{}
	}
	low, high := hand[0], hand[0]
	for _, c := range hand[1:] {
		if c.Value() < low.Value() {
			low = c
		}
		if c.Value() >= high.Value() {
			high = c
		}
	}
	if isHolder {
		return high
	}
	if running+low.Value()+after > Limit {
		return high
	}
	if running+high.Value()+after*10 <= Limit {
		return high
	}
	if rng.Float64() < 0.18+float64(round)*0.06 {
		return high
	}
	return low
}

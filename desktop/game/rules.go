package game

import "math/rand/v2"

// A hand runs two rounds a seat, so everyone holds twice, and everyone is
// dealt a card more than that. The other 16 cards stay with the croupier,
// face down, and every card drawn comes off them.
const (
	Limit          = 25
	Cap            = 40
	Rounds         = 8
	HandSize       = 9
	DeckSize       = 52
	PenaltyPerCard = 4
	UnderDraw      = 2
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
// The caller must deal those cards in table order off the top of the stock;
// that order decides who receives which card.
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
		plan[holder] = UnderDraw
	}
	return plan
}

// A bot weighs its cards over pickGuesses guesses at what it cannot see, and
// guesses the holder's face-down card as the best of holderGuess. Choices
// within closeGap points count as close; sinkShare is the share of the cards
// a sunk holder draws that counts for each of the others.
const (
	pickGuesses = 40
	holderGuess = 5
	closeGap    = 3.0
	sinkShare   = 0.7
)

// Pick chooses a bot's card from what a player at the table knows: its own
// hand, how many cards lie face down this round (down) and whether the
// holder's is one of them, how many players are still to play (after), and
// unseen, the values of every card it has not seen (see unseenValues). The
// holder plays high. The others weigh each card over guesses at the
// face-down cards and the ones still to come: a card shed is worth its
// points, sinking the holder a share of the cards they would draw, and a
// total of exactly the limit or the cap costs a card of one's own. When the
// two best are close, one time in five a bot plays the second.
func Pick(rng *rand.Rand, hand []Card, isHolder bool, unseen []int, down int, holderDown bool, after int) Card {
	if len(hand) == 0 {
		return Card{}
	}
	high := hand[0]
	byValue := map[int]Card{}
	var values []int
	for _, c := range hand {
		if c.Value() > high.Value() {
			high = c
		}
		if _, ok := byValue[c.Value()]; !ok {
			byValue[c.Value()] = c
			values = append(values, c.Value())
		}
	}
	if isHolder || len(unseen) == 0 || len(values) == 1 {
		return high
	}
	odds := map[int]float64{}
	pool := append([]int(nil), unseen...)
	cost := 6.5 + float64(PenaltyPerCard)
	need := min(down+after, len(pool))
	for range pickGuesses {
		for k := 0; k < need; k++ {
			j := k + rng.IntN(len(pool)-k)
			pool[k], pool[j] = pool[j], pool[k]
		}
		total := 0
		for k := 0; k < need; k++ {
			if holderDown && k == 0 {
				best := 0
				for range holderGuess {
					best = max(best, pool[rng.IntN(len(pool))])
				}
				total += best
			} else {
				total += pool[k]
			}
		}
		for _, v := range values {
			switch OutcomeFor(total + v) {
			case OutcomeUnder:
				odds[v] += cost * UnderDraw * sinkShare
			case OutcomeExact, OutcomeCap:
				odds[v] -= cost
			}
		}
	}
	worth := map[int]float64{}
	for _, v := range values {
		worth[v] = float64(v) + odds[v]/pickGuesses
	}
	for i := 1; i < len(values); i++ {
		v := values[i]
		j := i
		for j > 0 && worth[values[j-1]] < worth[v] {
			values[j] = values[j-1]
			j--
		}
		values[j] = v
	}
	if worth[values[0]]-worth[values[1]] < closeGap && rng.Float64() < 0.2 {
		return byValue[values[1]]
	}
	return byValue[values[0]]
}

// unseenValues lists the values of the cards a player cannot see: the whole
// deck but its own hand and the cards turned up in earlier rounds.
func unseenValues(hand, discard []Card) []int {
	var left [11]int
	for r := Ace; r <= King; r++ {
		left[r.Value()] += 4
	}
	for _, c := range hand {
		left[c.Value()]--
	}
	for _, c := range discard {
		left[c.Value()]--
	}
	out := make([]int, 0, DeckSize)
	for v := 1; v <= 10; v++ {
		for n := 0; n < left[v]; n++ {
			out = append(out, v)
		}
	}
	return out
}

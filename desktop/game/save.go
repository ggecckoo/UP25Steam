package game

import (
	"encoding/json"
	"os"
	"path/filepath"
)

var saveOverride string

func progressPath() string {
	if saveOverride != "" {
		return saveOverride
	}
	dir, err := os.UserConfigDir()
	if err != nil {
		dir = "."
	}
	return filepath.Join(dir, "Atiko Labs", "25-40", "save.json")
}

type cardDisk struct {
	R int `json:"r"`
	S int `json:"s"`
}

type resumeDisk struct {
	Round  int          `json:"round"`
	Holder int          `json:"holder"`
	Names  []string     `json:"names"`
	Hands  [][]cardDisk `json:"hands"`
	Middle []cardDisk   `json:"middle"`
}

type saveDisk struct {
	Version       int         `json:"version"`
	GamesFinished int         `json:"gamesFinished"`
	GamesWon      int         `json:"gamesWon"`
	DemoCompleted bool        `json:"demoCompleted"`
	Language      string      `json:"language,omitempty"`
	Sound         *bool       `json:"sound,omitempty"`
	Resume        *resumeDisk `json:"resume,omitempty"`
}

func (e *Engine) load() {
	data, err := os.ReadFile(progressPath())
	if err != nil {
		SetLanguage(DetectLanguage(platformLocale()))
		return
	}
	var raw map[string]json.RawMessage
	var file saveDisk
	if json.Unmarshal(data, &raw) != nil || json.Unmarshal(data, &file) != nil {
		SetLanguage(DetectLanguage(platformLocale()))
		return
	}
	if file.Language != "" {
		SetLanguage(file.Language)
	} else {
		SetLanguage(DetectLanguage(platformLocale()))
	}
	e.GamesFinished = file.GamesFinished
	if e.GamesFinished < 0 {
		e.GamesFinished = 0
	}
	e.GamesWon = file.GamesWon
	if e.GamesWon < 0 {
		e.GamesWon = 0
	}
	if e.GamesWon > e.GamesFinished {
		e.GamesWon = e.GamesFinished
	}
	e.demoDone = file.DemoCompleted
	if _, ok := raw["sound"]; ok {
		var on bool
		if json.Unmarshal(raw["sound"], &on) == nil {
			e.Sound = on
		}
	} else {
		e.Sound = true
	}
	if !e.restore(file.Resume) {
		e.Players = nil
		e.middle = nil
		e.Table = nil
		e.canResume = false
		e.Phase = PhaseMenu
	}
}

func (e *Engine) restore(file *resumeDisk) bool {
	if file == nil || file.Round < 1 || file.Round > Rounds || file.Holder < 0 || file.Holder > 3 || len(file.Hands) != 4 {
		return false
	}
	seen := map[[2]int]bool{}
	hands := make([][]Card, 4)
	total := 0
	take := func(list []cardDisk) ([]Card, bool) {
		out := make([]Card, 0, len(list))
		for _, c := range list {
			if c.R < 0 || c.R > int(King) || c.S < 0 || c.S > int(Club) {
				return nil, false
			}
			key := [2]int{c.R, c.S}
			if seen[key] {
				return nil, false
			}
			seen[key] = true
			out = append(out, e.mint(Rank(c.R), Suit(c.S)))
			total++
		}
		return out, true
	}
	for i := 0; i < 4; i++ {
		hand, ok := take(file.Hands[i])
		if !ok {
			return false
		}
		hands[i] = hand
	}
	middle, ok := take(file.Middle)
	if !ok || total != 52 {
		return false
	}
	names := []string{T("common.player"), "Kemal", "Nur", "Sabri"}
	if len(file.Names) == 4 {
		for i := 0; i < 4; i++ {
			if file.Names[i] != "" {
				names[i] = file.Names[i]
			}
		}
	}
	e.Players = make([]Player, 4)
	for i := 0; i < 4; i++ {
		e.Players[i] = Player{ID: i, Name: names[i], Human: i == 0, Hand: hands[i]}
	}
	sortHand(e.Players[0].Hand)
	e.middle = middle
	e.Holder = file.Holder
	e.Round = file.Round
	e.Table = nil
	e.Phase = PhaseMenu
	e.canResume = true
	e.applied = false
	e.HasOutcome = false
	e.SumShown = false
	return true
}

func (e *Engine) Save() {
	on := e.Sound
	file := saveDisk{
		Version:       1,
		GamesFinished: e.GamesFinished,
		GamesWon:      e.GamesWon,
		DemoCompleted: e.demoDone,
		Language:      Language(),
		Sound:         &on,
		Resume:        e.resumeSnapshot(),
	}
	data, err := json.MarshalIndent(file, "", "  ")
	if err != nil {
		return
	}
	data = append(data, '\n')
	path := progressPath()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, data, 0o644); err != nil {
		return
	}
	_ = os.Rename(tmp, path)
}

func (e *Engine) resumeSnapshot() *resumeDisk {
	if e.Phase == PhaseOver || len(e.Players) != 4 || e.Round < 1 || e.Round > Rounds {
		return nil
	}
	if e.Phase == PhaseMenu && !e.canResume {
		return nil
	}
	hands := make([][]Card, 4)
	for i := range e.Players {
		hands[i] = append([]Card(nil), e.Players[i].Hand...)
	}
	if !e.applied {
		for _, played := range e.Table {
			if played.By >= 0 && played.By < 4 {
				hands[played.By] = append(hands[played.By], played.Card)
			}
		}
	}
	file := &resumeDisk{
		Round:  e.Round,
		Holder: e.Holder,
		Names:  make([]string, 4),
		Hands:  make([][]cardDisk, 4),
		Middle: cardsToDisk(e.middle),
	}
	for i := 0; i < 4; i++ {
		file.Names[i] = e.Players[i].Name
		file.Hands[i] = cardsToDisk(hands[i])
	}
	return file
}

func cardsToDisk(cards []Card) []cardDisk {
	out := make([]cardDisk, len(cards))
	for i, card := range cards {
		out[i] = cardDisk{R: int(card.Rank), S: int(card.Suit)}
	}
	return out
}

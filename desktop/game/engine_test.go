package game

import (
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
		if n := countCards(e); n != 52 {
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
	if e.Phase != PhaseMenu || !e.CanResume() || len(e.Table) != 0 || countCards(e) != 52 {
		t.Fatalf("phase %d resume %v cards %d", e.Phase, e.CanResume(), countCards(e))
	}
	e2 := New()
	if !e2.CanResume() || countCards(e2) != 52 {
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
	if e.Phase != PhaseOver || e.CanResume() || e.GamesFinished != 1 || countCards(e) != 52 {
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
	body := []byte(`{"version":1,"gamesFinished":3,"gamesWon":9,"sound":false,"resume":{"round":1,"holder":0,"hands":[[],[],[],[]],"middle":[]}}`)
	if err := os.WriteFile(saveOverride, body, 0o644); err != nil {
		t.Fatal(err)
	}
	e := New()
	if e.CanResume() || e.Sound || e.GamesFinished != 3 || e.GamesWon != 3 {
		t.Fatalf("resume %v sound %v finished %d won %d", e.CanResume(), e.Sound, e.GamesFinished, e.GamesWon)
	}
}

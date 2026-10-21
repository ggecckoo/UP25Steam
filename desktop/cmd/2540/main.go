package main

import (
	_ "embed"
	"fmt"
	"os"

	"github.com/ggecckoo/UP25Steam/desktop/game"
	"github.com/hajimehoshi/ebiten/v2"
	"github.com/hajimehoshi/ebiten/v2/audio"
)

//go:embed assets/NotoSans-Regular.ttf
var fontLatin []byte

//go:embed assets/NotoSansArabic-Regular.ttf
var fontArabic []byte

//go:embed assets/NotoSansDevanagari-Regular.ttf
var fontDeva []byte

//go:embed assets/NotoSansCJK-Regular.otf
var fontCJK []byte

const (
	viewW = 1280
	viewH = 800
)

type screen int

const (
	screenMenu screen = iota
	screenHow
	screenLang
	screenPlay
	screenPause
	screenOver
)

type item int

const (
	itemContinue item = iota
	itemNew
	itemHow
	itemLang
	itemQuitApp
	itemResume
	itemSound
	itemQuitMatch
	itemMenu
)

type button struct {
	x, y, w, h float64
	label      string
	primary    bool
	focused    bool
	id         item
	index      int
}

func (b button) contains(x, y float64) bool {
	return x >= b.x && y >= b.y && x < b.x+b.w && y < b.y+b.h
}

type cardSpot struct {
	x, y, w, h float64
	index      int
}

func (c cardSpot) contains(x, y float64) bool {
	return x >= c.x && y >= c.y && x < c.x+c.w && y < c.y+c.h
}

type app struct {
	e          *game.Engine
	fonts      *typeface
	off        *ebiten.Image
	screen     screen
	focus      int
	card       int
	token      int
	scroll     float64
	back       screen
	quit       bool
	cool       float64
	repeating  bool
	mx, my     int
	outW, outH int
	cardSnd    *audio.Player
	revealSnd  *audio.Player
}

func main() {
	faces, err := loadTypeface(fontLatin, fontArabic, fontDeva, fontCJK)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	card, reveal := newCues()
	g := &app{
		e:         game.New(),
		fonts:     faces,
		token:     -1,
		mx:        -1,
		my:        -1,
		cardSnd:   card,
		revealSnd: reveal,
	}
	ebiten.SetWindowTitle("25-40")
	ebiten.SetWindowSize(viewW, viewH)
	ebiten.SetWindowSizeLimits(960, 600, -1, -1)
	ebiten.SetWindowResizingMode(ebiten.WindowResizingModeEnabled)
	if os.Getenv("SteamDeck") == "1" {
		ebiten.SetFullscreen(true)
	}
	if err := ebiten.RunGame(g); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

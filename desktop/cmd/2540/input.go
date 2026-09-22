package main

import (
	"github.com/ggecckoo/UP25Steam/desktop/game"
	"github.com/hajimehoshi/ebiten/v2"
	"github.com/hajimehoshi/ebiten/v2/inpututil"
)

func (g *app) Update() error {
	if g.quit {
		return ebiten.Termination
	}
	g.ensure()
	g.input()
	g.e.Tick(1 / float64(ebiten.TPS()))
	g.sync()
	g.pumpSound()
	if g.quit {
		return ebiten.Termination
	}
	return nil
}

func (g *app) sync() {
	switch g.e.Phase {
	case game.PhaseOver:
		if g.screen == screenPlay || g.screen == screenPause {
			g.screen = screenOver
			g.focus = 0
		}
	case game.PhaseMenu:
		if g.screen == screenPlay || g.screen == screenPause {
			g.screen = screenMenu
			g.focus = 0
		}
	}
}

func (g *app) pumpSound() {
	cue := g.e.TakeSound()
	if !g.e.Sound {
		return
	}
	switch cue {
	case game.CueCard:
		playCue(g.cardSnd)
	case game.CueReveal:
		playCue(g.revealSnd)
	}
}

func (g *app) input() {
	if inpututil.IsKeyJustPressed(ebiten.KeyF11) {
		ebiten.SetFullscreen(!ebiten.IsFullscreen())
	}
	dx, dy := g.nav()
	x, y, clicked := g.click()
	hx, hy, hovered := g.hover()
	switch g.screen {
	case screenHow:
		g.inputHow(dy, clicked, x, y)
	case screenLang:
		g.inputLang(dy, clicked, x, y, hovered, hx, hy)
	case screenPlay:
		g.inputPlay(dx, dy, clicked, x, y, hovered, hx, hy)
	case screenPause:
		if backPressed() || startPressed() {
			g.activate(itemResume)
			return
		}
		g.inputList(g.pauseButtons(), dy, clicked, x, y, hovered, hx, hy)
	case screenOver:
		if backPressed() {
			g.activate(itemMenu)
			return
		}
		g.inputList(g.overButtons(), dy, clicked, x, y, hovered, hx, hy)
	default:
		g.inputList(g.menuButtons(), dy, clicked, x, y, hovered, hx, hy)
	}
}

func (g *app) inputList(buttons []button, dy int, clicked bool, x, y float64, hovered bool, hx, hy float64) {
	g.clampFocus(len(buttons))
	if hovered {
		for i, b := range buttons {
			if b.contains(hx, hy) {
				g.focus = i
			}
		}
	}
	if dy != 0 {
		g.focus = wrap(g.focus, len(buttons), dy)
	}
	if clicked {
		for i, b := range buttons {
			if b.contains(x, y) {
				g.focus = i
				g.activate(b.id)
				return
			}
		}
	}
	if confirmPressed() && len(buttons) > 0 {
		g.clampFocus(len(buttons))
		g.activate(buttons[g.focus].id)
	}
}

func (g *app) inputHow(dy int, clicked bool, x, y float64) {
	_, wheel := ebiten.Wheel()
	g.scroll += float64(dy)*40 - wheel*48
	max := g.howContent() - 560
	if max < 0 {
		max = 0
	}
	if g.scroll < 0 {
		g.scroll = 0
	}
	if g.scroll > max {
		g.scroll = max
	}
	if backPressed() || (clicked && g.backButton().contains(x, y)) {
		g.screen = g.back
		g.focus = 0
		g.scroll = 0
	}
}

func (g *app) inputLang(dy int, clicked bool, x, y float64, hovered bool, hx, hy float64) {
	buttons := g.langButtons()
	if hovered {
		for i, b := range buttons {
			if b.contains(hx, hy) {
				g.focus = i
			}
		}
	}
	if dy != 0 {
		g.focus = wrap(g.focus, len(buttons), dy)
	}
	if backPressed() || (clicked && g.backButton().contains(x, y)) {
		g.screen = screenMenu
		g.focus = 0
		return
	}
	if clicked {
		for _, b := range buttons {
			if b.contains(x, y) {
				g.chooseLang(b.index)
				return
			}
		}
	}
	if confirmPressed() && len(buttons) > 0 {
		g.clampFocus(len(buttons))
		g.chooseLang(buttons[g.focus].index)
	}
}

func (g *app) inputPlay(dx, dy int, clicked bool, x, y float64, hovered bool, hx, hy float64) {
	g.trackTurn()
	n := 0
	if len(g.e.Players) > 0 {
		n = len(g.e.Players[0].Hand)
	}
	if hovered {
		for _, spot := range g.handSpots() {
			if spot.contains(hx, hy) {
				g.card = spot.index
			}
		}
	}
	if n > 0 && (dx != 0 || dy != 0) {
		g.card = moveCard(g.card, n, dx, dy)
	}
	if g.card < 0 {
		g.card = 0
	}
	if n > 0 && g.card >= n {
		g.card = n - 1
	}
	if backPressed() || startPressed() {
		g.openPause()
		return
	}
	if clicked {
		for _, spot := range g.handSpots() {
			if spot.contains(x, y) {
				g.card = spot.index
				if g.e.HumanTurn() {
					g.e.PlayCard(spot.index)
				}
				return
			}
		}
		if g.e.Phase == game.PhaseReveal && g.feltContains(x, y) {
			g.e.SkipReveal()
			return
		}
	}
	if confirmPressed() {
		if g.e.Phase == game.PhaseReveal {
			g.e.SkipReveal()
			return
		}
		if g.e.HumanTurn() {
			g.e.PlayCard(g.card)
		}
	}
	if g.e.HumanTurn() {
		for i, key := range digitKeys {
			if inpututil.IsKeyJustPressed(key) && i < n {
				g.card = i
				g.e.PlayCard(i)
			}
		}
	}
}

func (g *app) openPause() {
	if g.e.Phase != game.PhasePlaying && g.e.Phase != game.PhaseReveal {
		return
	}
	g.e.SetPaused(true)
	g.screen = screenPause
	g.focus = 0
}

func (g *app) activate(id item) {
	switch id {
	case itemContinue:
		if !g.e.CanResume() {
			return
		}
		g.e.Resume()
		g.enterPlay()
	case itemNew:
		g.e.NewGame()
		g.enterPlay()
	case itemHow:
		if g.screen == screenPause {
			g.back = screenPause
		} else {
			g.back = screenMenu
		}
		g.screen = screenHow
		g.scroll = 0
		g.focus = 0
	case itemLang:
		g.screen = screenLang
		g.focus = currentLang()
	case itemQuitApp:
		g.quit = true
	case itemResume:
		g.e.SetPaused(false)
		g.screen = screenPlay
	case itemSound:
		g.e.SetSound(!g.e.Sound)
	case itemQuitMatch:
		g.e.QuitMatch()
		g.sync()
	case itemMenu:
		g.e.ReturnToMenu()
		g.screen = screenMenu
		g.focus = 0
	}
}

func (g *app) enterPlay() {
	g.screen = screenPlay
	g.token = -1
	g.card = 0
	g.focus = 0
}

func (g *app) trackTurn() {
	if !g.e.HumanTurn() || len(g.e.Players) == 0 {
		return
	}
	token := g.e.TurnToken()
	if token == g.token {
		return
	}
	g.token = token
	n := len(g.e.Players[0].Hand)
	if n == 0 {
		g.card = 0
		return
	}
	if g.e.Holder == 0 {
		g.card = n - 1
	} else {
		g.card = 0
	}
}

func (g *app) chooseLang(index int) {
	langs := game.Languages()
	if index < 0 || index >= len(langs) {
		return
	}
	if game.SetLanguage(langs[index].Code) {
		g.e.Save()
	}
	g.screen = screenMenu
	g.focus = 0
}

func currentLang() int {
	for i, lang := range game.Languages() {
		if lang.Code == game.Language() {
			return i
		}
	}
	return 0
}

func (g *app) menuIDs() []item {
	if g.e.CanResume() {
		return []item{itemContinue, itemNew, itemHow, itemLang, itemQuitApp}
	}
	return []item{itemNew, itemHow, itemLang, itemQuitApp}
}

func (g *app) clampFocus(n int) {
	if n <= 0 || g.focus < 0 {
		g.focus = 0
		return
	}
	if g.focus >= n {
		g.focus = n - 1
	}
}

func wrap(index, n, delta int) int {
	if n <= 0 {
		return 0
	}
	index += delta
	for index < 0 {
		index += n
	}
	for index >= n {
		index -= n
	}
	return index
}

func moveCard(index, n, dx, dy int) int {
	if n <= 0 {
		return 0
	}
	rows := 1
	if n > 8 {
		rows = 2
	}
	cols := (n + rows - 1) / rows
	if dx != 0 {
		index += dx
		if index < 0 {
			index = n - 1
		}
		if index >= n {
			index = 0
		}
		return index
	}
	if dy != 0 && rows == 2 {
		if index < cols {
			index += cols
		} else {
			index -= cols
		}
		if index >= n {
			index = n - 1
		}
		if index < 0 {
			index = 0
		}
	}
	return index
}

func (g *app) nav() (int, int) {
	if g.cool > 0 {
		g.cool -= 1 / float64(ebiten.TPS())
	}
	x, y := heldDir()
	if x == 0 && y == 0 {
		g.repeating = false
		g.cool = 0
		return 0, 0
	}
	if g.repeating && g.cool > 0 {
		return 0, 0
	}
	first := !g.repeating
	g.repeating = true
	if first {
		g.cool = 0.28
	} else {
		g.cool = 0.12
	}
	return x, y
}

func heldDir() (int, int) {
	x, y := 0, 0
	if ebiten.IsKeyPressed(ebiten.KeyLeft) {
		x--
	}
	if ebiten.IsKeyPressed(ebiten.KeyRight) {
		x++
	}
	if ebiten.IsKeyPressed(ebiten.KeyUp) {
		y--
	}
	if ebiten.IsKeyPressed(ebiten.KeyDown) {
		y++
	}
	if id, ok := pad(); ok {
		if ebiten.IsStandardGamepadLayoutAvailable(id) {
			if ebiten.IsStandardGamepadButtonPressed(id, ebiten.StandardGamepadButtonLeftLeft) {
				x = -1
			}
			if ebiten.IsStandardGamepadButtonPressed(id, ebiten.StandardGamepadButtonLeftRight) {
				x = 1
			}
			if ebiten.IsStandardGamepadButtonPressed(id, ebiten.StandardGamepadButtonLeftTop) {
				y = -1
			}
			if ebiten.IsStandardGamepadButtonPressed(id, ebiten.StandardGamepadButtonLeftBottom) {
				y = 1
			}
			ax := ebiten.StandardGamepadAxisValue(id, ebiten.StandardGamepadAxisLeftStickHorizontal)
			ay := ebiten.StandardGamepadAxisValue(id, ebiten.StandardGamepadAxisLeftStickVertical)
			if ax <= -0.55 {
				x = -1
			} else if ax >= 0.55 {
				x = 1
			}
			if ay <= -0.55 {
				y = -1
			} else if ay >= 0.55 {
				y = 1
			}
		} else if ebiten.GamepadAxisCount(id) >= 2 {
			ax := ebiten.GamepadAxisValue(id, 0)
			ay := ebiten.GamepadAxisValue(id, 1)
			if ax <= -0.55 {
				x = -1
			} else if ax >= 0.55 {
				x = 1
			}
			if ay <= -0.55 {
				y = -1
			} else if ay >= 0.55 {
				y = 1
			}
		}
	}
	if x > 1 {
		x = 1
	}
	if x < -1 {
		x = -1
	}
	if y > 1 {
		y = 1
	}
	if y < -1 {
		y = -1
	}
	return x, y
}

func confirmPressed() bool {
	if inpututil.IsKeyJustPressed(ebiten.KeyEnter) || inpututil.IsKeyJustPressed(ebiten.KeyKPEnter) || inpututil.IsKeyJustPressed(ebiten.KeySpace) {
		return true
	}
	id, ok := pad()
	if !ok {
		return false
	}
	if ebiten.IsStandardGamepadLayoutAvailable(id) {
		return inpututil.IsStandardGamepadButtonJustPressed(id, ebiten.StandardGamepadButtonRightBottom)
	}
	return inpututil.IsGamepadButtonJustPressed(id, ebiten.GamepadButton0)
}

func backPressed() bool {
	if inpututil.IsKeyJustPressed(ebiten.KeyEscape) {
		return true
	}
	id, ok := pad()
	if !ok {
		return false
	}
	if ebiten.IsStandardGamepadLayoutAvailable(id) {
		return inpututil.IsStandardGamepadButtonJustPressed(id, ebiten.StandardGamepadButtonRightRight)
	}
	return inpututil.IsGamepadButtonJustPressed(id, ebiten.GamepadButton1)
}

func startPressed() bool {
	id, ok := pad()
	if !ok {
		return false
	}
	if ebiten.IsStandardGamepadLayoutAvailable(id) {
		return inpututil.IsStandardGamepadButtonJustPressed(id, ebiten.StandardGamepadButtonCenterRight)
	}
	return inpututil.IsGamepadButtonJustPressed(id, ebiten.GamepadButton7)
}

func pad() (ebiten.GamepadID, bool) {
	ids := ebiten.AppendGamepadIDs(nil)
	if len(ids) == 0 {
		return 0, false
	}
	return ids[0], true
}

func (g *app) click() (float64, float64, bool) {
	if !inpututil.IsMouseButtonJustPressed(ebiten.MouseButtonLeft) {
		return 0, 0, false
	}
	x, y, ok := g.pointer()
	if !ok {
		return 0, 0, false
	}
	return x, y, true
}

func (g *app) hover() (float64, float64, bool) {
	cx, cy := ebiten.CursorPosition()
	if cx == g.mx && cy == g.my {
		return 0, 0, false
	}
	g.mx, g.my = cx, cy
	x, y, ok := g.pointer()
	if !ok {
		return 0, 0, false
	}
	return x, y, true
}

func (g *app) pointer() (float64, float64, bool) {
	cx, cy := ebiten.CursorPosition()
	scale, ox, oy := g.fit()
	if scale <= 0 {
		return 0, 0, false
	}
	x := (float64(cx) - ox) / scale
	y := (float64(cy) - oy) / scale
	if x < 0 || y < 0 || x >= viewW || y >= viewH {
		return x, y, false
	}
	return x, y, true
}

var digitKeys = []ebiten.Key{
	ebiten.Key1, ebiten.Key2, ebiten.Key3, ebiten.Key4, ebiten.Key5,
	ebiten.Key6, ebiten.Key7, ebiten.Key8, ebiten.Key9,
}

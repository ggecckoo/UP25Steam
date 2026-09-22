package main

import (
	"image/color"
	"math"
	"strconv"

	"github.com/ggecckoo/UP25Steam/desktop/game"
	"github.com/hajimehoshi/ebiten/v2"
	"github.com/hajimehoshi/ebiten/v2/vector"
)

var (
	colFeltDeep = color.RGBA{0x0A, 0x3B, 0x2E, 0xFF}
	colFeltLit  = color.RGBA{0x1E, 0x6E, 0x52, 0xFF}
	colPanel    = color.RGBA{0x08, 0x2C, 0x22, 0xFF}
	colBrass    = color.RGBA{0xC9, 0xA4, 0x4C, 0xFF}
	colBrassHi  = color.RGBA{0xF0, 0xDA, 0x9E, 0xFF}
	colBrassDk  = color.RGBA{0x6E, 0x53, 0x20, 0xFF}
	colIvory    = color.RGBA{0xF7, 0xF2, 0xE4, 0xFF}
	colIvoryDim = color.RGBA{0xF7, 0xF2, 0xE4, 0xB0}
	colLac      = color.RGBA{0xB3, 0x30, 0x2B, 0xFF}
	colLacLit   = color.RGBA{0xE8, 0x83, 0x7C, 0xFF}
	colInk      = color.RGBA{0x1B, 0x17, 0x12, 0xFF}
)

func fill(dst *ebiten.Image, x, y, w, h float64, c color.Color) {
	if w <= 0 || h <= 0 {
		return
	}
	vector.DrawFilledRect(dst, float32(x), float32(y), float32(w), float32(h), c, false)
}

func (g *app) ensure() {
	if g.off == nil {
		g.off = ebiten.NewImage(viewW, viewH)
	}
}

func (g *app) Draw(screen *ebiten.Image) {
	g.ensure()
	g.off.Fill(colFeltDeep)
	fill(g.off, 0, 0, viewW, 4, colBrassDk)
	g.render(g.off)
	g.drawLegend(g.off)
	screen.Fill(color.Black)
	scale, ox, oy := g.fit()
	op := &ebiten.DrawImageOptions{}
	op.GeoM.Scale(scale, scale)
	op.GeoM.Translate(ox, oy)
	op.Filter = ebiten.FilterLinear
	screen.DrawImage(g.off, op)
}

func (g *app) Layout(w, h int) (int, int) {
	if w < 1 {
		w = viewW
	}
	if h < 1 {
		h = viewH
	}
	g.outW, g.outH = w, h
	return w, h
}

func (g *app) fit() (scale, ox, oy float64) {
	w, h := g.outW, g.outH
	if w < 1 || h < 1 {
		w, h = viewW, viewH
	}
	scale = float64(w) / viewW
	if sy := float64(h) / viewH; sy < scale {
		scale = sy
	}
	if scale <= 0 {
		return 1, 0, 0
	}
	ox = (float64(w) - viewW*scale) / 2
	oy = (float64(h) - viewH*scale) / 2
	return scale, ox, oy
}

func (g *app) render(dst *ebiten.Image) {
	switch g.screen {
	case screenPlay, screenPause:
		g.renderPlay(dst)
		if g.screen == screenPause {
			fill(dst, 0, 0, viewW, viewH, color.RGBA{0, 0, 0, 150})
			g.renderPause(dst)
		}
	case screenOver:
		g.renderOver(dst)
	case screenHow:
		g.renderHow(dst)
	case screenLang:
		g.renderLang(dst)
	default:
		g.renderMenu(dst)
	}
}

func (g *app) drawLegend(dst *ebiten.Image) {
	label := game.T("ui.legend")
	size := 18.0
	if g.fonts.width(label, size) > 1200 {
		size = 16
	}
	h := g.fonts.measure(label, size, 1200)
	g.fonts.text(dst, label, size, viewW/2, viewH-12-h, 1200, colIvoryDim, alignCenter)
}

func (g *app) drawButton(dst *ebiten.Image, b button) {
	if b.focused {
		fill(dst, b.x-6, b.y-6, b.w+12, b.h+12, colBrassHi)
	}
	label := colIvory
	if b.primary {
		fill(dst, b.x, b.y, b.w, b.h, colBrass)
		label = colInk
	} else {
		fill(dst, b.x, b.y, b.w, b.h, colBrass)
		fill(dst, b.x+3, b.y+3, b.w-6, b.h-6, colPanel)
	}
	size := 24.0
	if b.h < 60 {
		size = 22
	}
	for size > 16 && g.fonts.width(b.label, size) > b.w-36 {
		size--
	}
	top := b.y + (b.h-g.fonts.lineH(size))/2
	g.fonts.text(dst, b.label, size, b.x+b.w/2, top, 0, label, alignCenter)
}

func (g *app) backButton() button {
	x := viewW - 220.0
	if game.RTL() {
		x = 40
	}
	return button{x: x, y: 20, w: 180, h: 56, label: game.T("game.back")}
}

func (g *app) renderMenu(dst *ebiten.Image) {
	g.fonts.text(dst, game.T("brand.name"), 60, viewW/2, 36, 0, colBrassHi, alignCenter)
	g.fonts.text(dst, game.T("menu.tagline1"), 30, viewW/2, 112, 0, colIvory, alignCenter)
	g.fonts.text(dst, game.T("menu.tagline2"), 26, viewW/2, 150, 0, colBrass, alignCenter)
	blurbY, statsY, buttons := g.menuLayout()
	g.fonts.text(dst, game.T("menu.blurb"), 20, viewW/2, blurbY, 900, colIvoryDim, alignCenter)
	g.fonts.text(dst, game.Format("menu.stats %lld %lld", g.e.GamesFinished, g.e.GamesWon), 18, viewW/2, statsY, 0, colBrass, alignCenter)
	for _, b := range buttons {
		g.drawButton(dst, b)
	}
}

func (g *app) menuButtons() []button {
	_, _, buttons := g.menuLayout()
	return buttons
}

func (g *app) menuLayout() (blurbY, statsY float64, buttons []button) {
	ids := g.menuIDs()
	const h, gap, w = 64.0, 12.0, 520.0
	blurbY = 196
	blurbH := g.fonts.measure(game.T("menu.blurb"), 20, 900)
	statsY = blurbY + blurbH + 6
	block := float64(len(ids))*h + float64(len(ids)-1)*gap
	y := statsY + g.fonts.lineH(18) + 16
	if y+block > 728 {
		y = 728 - block
	}
	g.clampFocus(len(ids))
	return blurbY, statsY, g.stack(ids, y, h, gap, w)
}

func (g *app) renderHow(dst *ebiten.Image) {
	g.fonts.text(dst, game.T("howto.title"), 36, viewW/2, 28, 900, colBrassHi, alignCenter)
	g.drawButton(dst, g.backButton())
	y := 108 - g.scroll
	x := 80.0
	align := alignLeft
	if game.RTL() {
		x = viewW - 80
		align = alignRight
	}
	for i := 1; i <= 6; i++ {
		body := g.ruleLine(i)
		h := g.fonts.measure(body, 22, 1100)
		if y+h > 96 && y < 730 {
			g.fonts.text(dst, body, 22, x, y, 1100, colIvory, align)
		}
		y += h + 18
	}
}

func (g *app) ruleLine(i int) string {
	return strconv.Itoa(i) + ".  " + game.T("rules."+strconv.Itoa(i))
}

func (g *app) howContent() float64 {
	h := 0.0
	for i := 1; i <= 6; i++ {
		h += g.fonts.measure(g.ruleLine(i), 22, 1100) + 18
	}
	return h
}

func (g *app) renderLang(dst *ebiten.Image) {
	g.fonts.text(dst, game.T("language.title"), 36, viewW/2, 24, 700, colBrassHi, alignCenter)
	g.drawButton(dst, g.backButton())
	for _, b := range g.langButtons() {
		g.drawButton(dst, b)
	}
}

func (g *app) langButtons() []button {
	langs := game.Languages()
	const h, gap, w = 56.0, 6.0, 640.0
	x := (viewW - w) / 2
	g.clampFocus(len(langs))
	out := make([]button, len(langs))
	for i, lang := range langs {
		out[i] = button{
			x: x, y: 100 + float64(i)*(h+gap), w: w, h: h,
			label:   lang.Name,
			primary: lang.Code == game.Language(),
			focused: i == g.focus,
			index:   i,
		}
	}
	return out
}

func (g *app) renderPause(dst *ebiten.Image) {
	fill(dst, 330, 168, 620, 470, colBrass)
	fill(dst, 334, 172, 612, 462, colFeltDeep)
	g.fonts.text(dst, game.T("pause.title"), 36, viewW/2, 196, 520, colBrassHi, alignCenter)
	for _, b := range g.pauseButtons() {
		g.drawButton(dst, b)
	}
}

func (g *app) pauseButtons() []button {
	ids := []item{itemResume, itemHow, itemSound, itemQuitMatch}
	g.clampFocus(len(ids))
	return g.stack(ids, 268, 64, 12, 460)
}

func (g *app) renderOver(dst *ebiten.Image) {
	g.fonts.text(dst, game.Format("over.roundsDone %lld", game.Rounds), 18, viewW/2, 36, 0, colBrass, alignCenter)
	if len(g.e.Standings) > 0 {
		top := g.e.Standings[0]
		g.fonts.text(dst, game.Format("over.won %@", top.Name), 40, viewW/2, 68, 1000, colIvory, alignCenter)
		g.fonts.text(dst, game.Format("over.lightest %lld", top.Score), 20, viewW/2, 124, 0, colBrassHi, alignCenter)
	}
	for i, row := range g.e.Standings {
		y := 176 + float64(i)*62
		bg := color.RGBA{0, 0, 0, 70}
		if i == 0 {
			bg = colBrassDk
		} else if row.ID == 0 {
			bg = colFeltLit
		}
		fill(dst, 220, y, 840, 54, bg)
		name := strconv.Itoa(i+1) + "   " + row.Name
		nameCol := colIvory
		if i == 0 {
			nameCol = colBrassHi
		}
		g.fonts.text(dst, name, 22, 244, y+6, 460, nameCol, alignLeft)
		g.fonts.text(dst, strconv.Itoa(row.Score), 22, 1036, y+6, 0, colIvory, alignRight)
		g.fonts.text(dst, game.Format("over.valuePenalty %lld %lld", row.Value, row.Penalty), 16, 244, y+28, 700, colIvoryDim, alignLeft)
	}
	for _, b := range g.overButtons() {
		g.drawButton(dst, b)
	}
}

func (g *app) overButtons() []button {
	ids := []item{itemNew, itemMenu}
	g.clampFocus(len(ids))
	return g.stack(ids, 560, 64, 12, 460)
}

func (g *app) renderPlay(dst *ebiten.Image) {
	if len(g.e.Players) < 4 {
		return
	}
	g.fonts.text(dst, game.Format("game.round %lld %lld", g.e.Round, game.Rounds), 20, 40, 18, 0, colBrassHi, alignLeft)
	g.drawSeats(dst)
	g.drawFelt(dst)
	g.fonts.text(dst, g.e.StatusText(), 20, viewW/2, 414, 1080, colIvory, alignCenter)
	if hint := g.e.HintText(); hint != "" {
		g.fonts.text(dst, hint, 18, viewW/2, 448, 1000, colIvoryDim, alignCenter)
	}
	me := g.e.Players[0]
	g.fonts.text(dst, game.Format("game.handCount %lld", len(me.Hand)), 16, 40, 486, 0, colIvoryDim, alignLeft)
	g.fonts.text(dst, game.Format("game.valuePenalty %lld %lld", game.HandValue(me.Hand), me.Penalty()), 16, viewW-40, 486, 0, colIvoryDim, alignRight)
	if g.screen == screenPause {
		return
	}
	for _, spot := range g.handSpots() {
		card := me.Hand[spot.index]
		g.drawCard(dst, spot.x, spot.y, spot.w, spot.h, card, true, spot.index == g.card && g.e.HumanTurn())
	}
}

func (g *app) drawSeats(dst *ebiten.Image) {
	const w, h, gap = 360.0, 68.0, 20.0
	x0 := (viewW - (3*w + 2*gap)) / 2
	for i := 1; i <= 3; i++ {
		p := g.e.Players[i]
		x := x0 + float64(i-1)*(w+gap)
		y := 58.0
		border := colBrassDk
		if g.e.Holder == i {
			border = colBrass
		}
		if g.e.Acting() == i {
			border = colBrassHi
		}
		fill(dst, x, y, w, h, border)
		fill(dst, x+3, y+3, w-6, h-6, colPanel)
		name := p.Name
		col := colIvory
		if g.e.Holder == i {
			col = colBrassHi
		}
		g.fonts.text(dst, name, 22, x+16, y+8, w-32, col, alignLeft)
		g.fonts.text(dst, strconv.Itoa(len(p.Hand))+"  "+game.T("game.cards"), 16, x+16, y+36, w-32, colIvoryDim, alignLeft)
	}
}

func (g *app) drawFelt(dst *ebiten.Image) {
	const x, y, w, h = 40.0, 128.0, 1200.0, 276.0
	fill(dst, x, y, w, h, colBrass)
	fill(dst, x+3, y+3, w-6, h-6, color.RGBA{0x0C, 0x45, 0x36, 0xFF})
	order := g.e.Order()
	slotW := (w - 48) / 4
	for i := 0; i < 4; i++ {
		owner := g.e.Players[order[i]]
		cx := x + 24 + float64(i)*slotW + (slotW-78)/2
		cy := 162.0
		col := colIvoryDim
		if order[i] == g.e.Holder {
			col = colBrassHi
		}
		g.fonts.text(dst, owner.Name, 16, cx+39, 136, slotW-8, col, alignCenter)
		if i < len(g.e.Table) {
			g.drawCard(dst, cx, cy, 78, 108, g.e.Table[i].Card, g.e.CardFaceUp(i), false)
		} else {
			border := color.RGBA{0, 0, 0, 80}
			if g.e.Acting() == order[i] {
				border = colBrass
			}
			fill(dst, cx, cy, 78, 108, border)
			fill(dst, cx+3, cy+3, 72, 102, color.RGBA{0, 0, 0, 60})
		}
	}
	g.drawGauge(dst, x+28, 292, w-56)
}

func (g *app) drawGauge(dst *ebiten.Image, x, y, w float64) {
	g.fonts.text(dst, game.T("game.tableTotal"), 16, x, y, 0, colIvoryDim, alignLeft)
	num := colIvoryDim
	if g.e.SumShown {
		num = g.outcomeColor()
		g.fonts.text(dst, strconv.Itoa(g.e.TableSum()), 32, x+w, y-6, 0, num, alignRight)
	}
	trackY := y + 36
	fill(dst, x, trackY, w, 10, color.RGBA{0, 0, 0, 140})
	if g.e.SumShown {
		frac := float64(g.e.TableSum()) / 40
		if frac > 1 {
			frac = 1
		}
		if frac > 0 {
			fill(dst, x, trackY, w*frac, 10, g.outcomeColor())
		}
	}
	mark := w * float64(game.Limit) / 40
	fill(dst, x+mark-1, trackY-4, 2, 18, colBrass)
	fill(dst, x+w-2, trackY-4, 2, 18, colBrass)
	g.fonts.text(dst, "25", 14, x+mark, trackY+16, 0, colBrass, alignCenter)
	g.fonts.text(dst, "40", 14, x+w, trackY+16, 0, colBrass, alignCenter)
	if verdict := g.e.VerdictText(); verdict != "" {
		g.fonts.text(dst, verdict, 16, x+w/2, trackY+34, w, g.outcomeColor(), alignCenter)
	}
}

func (g *app) outcomeColor() color.RGBA {
	switch g.e.Outcome {
	case game.OutcomeOver:
		return colBrassHi
	case game.OutcomeExact, game.OutcomeCap:
		return colIvory
	default:
		return colLacLit
	}
}

func (g *app) drawCard(dst *ebiten.Image, x, y, w, h float64, card game.Card, up, focused bool) {
	if focused {
		fill(dst, x-5, y-5, w+10, h+10, colBrassHi)
	}
	fill(dst, x+4, y+5, w, h, color.RGBA{0, 0, 0, 80})
	if !up {
		fill(dst, x, y, w, h, colBrassDk)
		fill(dst, x+4, y+4, w-8, h-8, colFeltDeep)
		fill(dst, x+12, y+12, w-24, h-24, colFeltLit)
		return
	}
	fill(dst, x, y, w, h, colIvory)
	ink := colInk
	if card.Red() {
		ink = colLac
	}
	rank := 22.0
	if w < 74 {
		rank = 18
	}
	g.fonts.text(dst, card.Rank.Label(), rank, x+8, y+6, 0, ink, alignLeft)
	drawSuit(dst, card.Suit, float32(x+w/2), float32(y+h*0.62), float32(math.Min(w, h)*0.46), ink)
}

var whitePx *ebiten.Image

func fillPoly(dst *ebiten.Image, c color.Color, pts ...[2]float32) {
	if len(pts) < 3 {
		return
	}
	if whitePx == nil {
		whitePx = ebiten.NewImage(1, 1)
		whitePx.Fill(color.White)
	}
	cr, cg, cb, ca := c.RGBA()
	vs := make([]ebiten.Vertex, len(pts))
	for i, p := range pts {
		vs[i] = ebiten.Vertex{
			DstX: p[0], DstY: p[1],
			ColorR: float32(cr) / 65535,
			ColorG: float32(cg) / 65535,
			ColorB: float32(cb) / 65535,
			ColorA: float32(ca) / 65535,
		}
	}
	idx := make([]uint16, 0, (len(pts)-2)*3)
	for i := 1; i < len(pts)-1; i++ {
		idx = append(idx, 0, uint16(i), uint16(i+1))
	}
	dst.DrawTriangles(vs, idx, whitePx, nil)
}

func drawSuit(dst *ebiten.Image, suit game.Suit, cx, cy, s float32, c color.Color) {
	switch suit {
	case game.Heart:
		r := s * 0.26
		vector.DrawFilledCircle(dst, cx-s*0.22, cy-s*0.12, r, c, true)
		vector.DrawFilledCircle(dst, cx+s*0.22, cy-s*0.12, r, c, true)
		fillPoly(dst, c,
			[2]float32{cx - s*0.46, cy - s*0.02},
			[2]float32{cx + s*0.46, cy - s*0.02},
			[2]float32{cx, cy + s*0.52},
		)
	case game.Diamond:
		fillPoly(dst, c,
			[2]float32{cx, cy - s*0.52},
			[2]float32{cx + s*0.36, cy},
			[2]float32{cx, cy + s*0.52},
			[2]float32{cx - s*0.36, cy},
		)
	case game.Club:
		r := s * 0.22
		vector.DrawFilledCircle(dst, cx, cy-s*0.22, r, c, true)
		vector.DrawFilledCircle(dst, cx-s*0.22, cy+s*0.06, r, c, true)
		vector.DrawFilledCircle(dst, cx+s*0.22, cy+s*0.06, r, c, true)
		fill(dst, float64(cx-s*0.07), float64(cy), float64(s*0.14), float64(s*0.40), c)
	default:
		fillPoly(dst, c,
			[2]float32{cx, cy - s*0.52},
			[2]float32{cx + s*0.46, cy + s*0.08},
			[2]float32{cx - s*0.46, cy + s*0.08},
		)
		r := s * 0.22
		vector.DrawFilledCircle(dst, cx-s*0.20, cy+s*0.05, r, c, true)
		vector.DrawFilledCircle(dst, cx+s*0.20, cy+s*0.05, r, c, true)
		fill(dst, float64(cx-s*0.06), float64(cy+s*0.08), float64(s*0.12), float64(s*0.36), c)
	}
}

func (g *app) handSpots() []cardSpot {
	if len(g.e.Players) == 0 {
		return nil
	}
	n := len(g.e.Players[0].Hand)
	if n == 0 {
		return nil
	}
	rows := 1
	if n > 8 {
		rows = 2
	}
	cols := (n + rows - 1) / rows
	gap := 10.0
	var cw, ch, y0 float64
	if rows == 1 {
		cw = math.Min(92, (1200-float64(cols-1)*gap)/float64(cols))
		ch = cw * 1.4
		y0 = 540
	} else {
		ch = 102
		cw = math.Min(ch/1.38, (1200-float64(cols-1)*gap)/float64(cols))
		ch = cw * 1.38
		y0 = 518
	}
	spots := make([]cardSpot, n)
	for i := 0; i < n; i++ {
		row := 0
		col := i
		count := cols
		if rows == 2 && i >= cols {
			row = 1
			col = i - cols
			count = n - cols
		}
		total := float64(count)*cw + float64(count-1)*gap
		x := (viewW-total)/2 + float64(col)*(cw+gap)
		y := y0 + float64(row)*(ch+10)
		if i == g.card && g.e.HumanTurn() {
			y -= 16
		}
		spots[i] = cardSpot{x: x, y: y, w: cw, h: ch, index: i}
	}
	return spots
}

func (g *app) feltContains(x, y float64) bool {
	return x >= 40 && y >= 128 && x < 1240 && y < 404
}

func (g *app) stack(ids []item, y, h, gap, w float64) []button {
	x := (viewW - w) / 2
	out := make([]button, len(ids))
	for i, id := range ids {
		out[i] = button{
			x: x, y: y + float64(i)*(h+gap), w: w, h: h,
			label:   g.itemLabel(id),
			primary: i == 0,
			focused: i == g.focus,
			id:      id,
		}
	}
	return out
}

func (g *app) itemLabel(id item) string {
	switch id {
	case itemContinue:
		return game.T("menu.continue")
	case itemNew:
		if g.screen == screenOver {
			return game.T("over.newGame")
		}
		if g.e.CanResume() {
			return game.T("menu.newGame")
		}
		return game.T("menu.sit")
	case itemHow:
		return game.T("howto.title")
	case itemLang:
		return game.T("language.title")
	case itemQuitApp:
		return game.T("ui.quit")
	case itemResume:
		return game.T("pause.continue")
	case itemSound:
		state := game.T("ui.off")
		if g.e.Sound {
			state = game.T("ui.on")
		}
		return game.T("settings.sound") + "  ·  " + state
	case itemQuitMatch:
		return game.T("pause.quit")
	case itemMenu:
		return game.T("over.menu")
	default:
		return ""
	}
}

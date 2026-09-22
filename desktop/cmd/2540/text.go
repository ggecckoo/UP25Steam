package main

import (
	"bytes"
	"image/color"

	"github.com/ggecckoo/UP25Steam/desktop/game"
	"github.com/hajimehoshi/ebiten/v2"
	"github.com/hajimehoshi/ebiten/v2/text/v2"
)

const (
	alignLeft = iota
	alignCenter
	alignRight
)

type typeface struct {
	latin  *text.GoTextFaceSource
	arabic *text.GoTextFaceSource
	deva   *text.GoTextFaceSource
	cjk    *text.GoTextFaceSource
	cache  map[int]text.Face
}

func loadTypeface(latin, arabic, deva, cjk []byte) (*typeface, error) {
	t := &typeface{cache: map[int]text.Face{}}
	var err error
	if t.latin, err = text.NewGoTextFaceSource(bytes.NewReader(latin)); err != nil {
		return nil, err
	}
	if t.arabic, err = text.NewGoTextFaceSource(bytes.NewReader(arabic)); err != nil {
		return nil, err
	}
	if t.deva, err = text.NewGoTextFaceSource(bytes.NewReader(deva)); err != nil {
		return nil, err
	}
	if t.cjk, err = text.NewGoTextFaceSource(bytes.NewReader(cjk)); err != nil {
		return nil, err
	}
	return t, nil
}

func (t *typeface) face(size float64) text.Face {
	rtl := game.RTL()
	key := int(size*10 + 0.5)
	if rtl {
		key += 100000
	}
	if face, ok := t.cache[key]; ok {
		return face
	}
	dir := text.DirectionLeftToRight
	if rtl {
		dir = text.DirectionRightToLeft
	}
	one := func(src *text.GoTextFaceSource) text.Face {
		return &text.GoTextFace{Source: src, Direction: dir, Size: size}
	}
	var face text.Face
	if rtl {
		face = one(t.arabic)
	} else if combined, err := text.NewMultiFace(one(t.latin), one(t.cjk), one(t.deva), one(t.arabic)); err == nil {
		face = combined
	} else {
		face = one(t.latin)
	}
	t.cache[key] = face
	return face
}

func (t *typeface) lineH(size float64) float64 {
	m := t.face(size).Metrics()
	h := m.HAscent + m.HDescent + 4
	if h < size+4 {
		return size + 4
	}
	return h
}

func (t *typeface) width(s string, size float64) float64 {
	w, _ := text.Measure(s, t.face(size), t.lineH(size))
	return w
}

func (t *typeface) measure(s string, size, maxW float64) float64 {
	return float64(len(t.wrap(s, size, maxW))) * t.lineH(size)
}

func (t *typeface) wrap(s string, size, maxW float64) []string {
	if maxW <= 0 {
		return []string{s}
	}
	var lines []string
	for _, para := range bytes.Split([]byte(s), []byte("\n")) {
		words := bytes.Fields(para)
		if len(words) == 0 {
			lines = append(lines, "")
			continue
		}
		cur := ""
		flush := func() {
			if cur == "" {
				return
			}
			lines = append(lines, cur)
			cur = ""
		}
		for _, wordb := range words {
			word := string(wordb)
			if t.width(word, size) > maxW {
				flush()
				lines = append(lines, t.breakWord(word, size, maxW)...)
				continue
			}
			trial := word
			if cur != "" {
				trial = cur + " " + word
			}
			if t.width(trial, size) > maxW {
				flush()
				cur = word
			} else {
				cur = trial
			}
		}
		flush()
	}
	if len(lines) == 0 {
		return []string{""}
	}
	return lines
}

func (t *typeface) breakWord(word string, size, maxW float64) []string {
	var lines []string
	cur := ""
	for _, r := range word {
		next := cur + string(r)
		if cur != "" && t.width(next, size) > maxW {
			lines = append(lines, cur)
			cur = string(r)
			continue
		}
		cur = next
	}
	if cur != "" {
		lines = append(lines, cur)
	}
	return lines
}

func (t *typeface) text(dst *ebiten.Image, s string, size, x, y, maxW float64, col color.Color, align int) float64 {
	if maxW <= 0 {
		t.drawLine(dst, s, size, x, y, col, align)
		return t.lineH(size)
	}
	lines := t.wrap(s, size, maxW)
	lh := t.lineH(size)
	for i, line := range lines {
		t.drawLine(dst, line, size, x, y+float64(i)*lh, col, align)
	}
	return float64(len(lines)) * lh
}

func (t *typeface) drawLine(dst *ebiten.Image, s string, size, x, y float64, col color.Color, align int) {
	if s == "" {
		return
	}
	op := &text.DrawOptions{}
	op.GeoM.Translate(x, y)
	op.ColorScale.ScaleWithColor(col)
	op.PrimaryAlign, op.SecondaryAlign = visualAlign(align)
	text.Draw(dst, s, t.face(size), op)
}

func visualAlign(align int) (text.Align, text.Align) {
	top := text.AlignStart
	if game.RTL() {
		switch align {
		case alignRight:
			return text.AlignStart, top
		case alignCenter:
			return text.AlignCenter, top
		default:
			return text.AlignEnd, top
		}
	}
	switch align {
	case alignRight:
		return text.AlignEnd, top
	case alignCenter:
		return text.AlignCenter, top
	default:
		return text.AlignStart, top
	}
}

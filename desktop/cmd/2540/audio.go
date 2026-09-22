package main

import (
	"math"

	"github.com/hajimehoshi/ebiten/v2/audio"
)

func tone(freq, seconds float64) []byte {
	const rate = 44100
	n := int(rate * seconds)
	if n < 1 {
		n = 1
	}
	buf := make([]byte, n*4)
	for i := 0; i < n; i++ {
		env := 1.0
		if i < 180 {
			env = float64(i) / 180
		}
		tail := n - i
		if tail < 900 {
			fade := float64(tail) / 900
			if fade < env {
				env = fade
			}
		}
		sample := math.Sin(2*math.Pi*freq*float64(i)/rate) * 0.22 * env
		v := int16(sample * 32767)
		buf[i*4] = byte(v)
		buf[i*4+1] = byte(v >> 8)
		buf[i*4+2] = byte(v)
		buf[i*4+3] = byte(v >> 8)
	}
	return buf
}

func newCues() (card, reveal *audio.Player) {
	defer func() { _ = recover() }()
	ctx := audio.NewContext(44100)
	card = ctx.NewPlayerFromBytes(tone(880, 0.07))
	reveal = ctx.NewPlayerFromBytes(chord())
	card.SetVolume(0.35)
	reveal.SetVolume(0.4)
	return card, reveal
}

func chord() []byte {
	const rate = 44100
	n := int(rate * 0.18)
	buf := make([]byte, n*4)
	for i := 0; i < n; i++ {
		env := 1.0
		if i < 200 {
			env = float64(i) / 200
		}
		tail := n - i
		if tail < 1400 {
			fade := float64(tail) / 1400
			if fade < env {
				env = fade
			}
		}
		t := float64(i) / rate
		sample := (math.Sin(2*math.Pi*523.25*t) + math.Sin(2*math.Pi*659.25*t)) * 0.12 * env
		v := int16(sample * 32767)
		buf[i*4] = byte(v)
		buf[i*4+1] = byte(v >> 8)
		buf[i*4+2] = byte(v)
		buf[i*4+3] = byte(v >> 8)
	}
	return buf
}

func playCue(p *audio.Player) {
	if p == nil {
		return
	}
	_ = p.Rewind()
	p.Play()
}

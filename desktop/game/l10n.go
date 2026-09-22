package game

import (
	_ "embed"
	"encoding/json"
	"strings"
)

//go:embed assets/L10nCatalog.json
var catalogJSON []byte

var (
	catalog map[string]map[string]string
	current = "tr"
)

func init() {
	catalog = map[string]map[string]string{}
	if err := json.Unmarshal(catalogJSON, &catalog); err != nil {
		panic(err)
	}
	if _, ok := catalog["en"]; !ok {
		panic("localization catalog is missing English")
	}
}

func Language() string { return current }

func RTL() bool { return current == "ar" }

func SetLanguage(code string) bool {
	if _, ok := catalog[code]; !ok {
		return false
	}
	current = code
	return true
}

func DetectLanguage(locale string) string {
	l := strings.ToLower(strings.ReplaceAll(locale, "_", "-"))
	switch {
	case strings.HasPrefix(l, "tr"):
		return "tr"
	case strings.HasPrefix(l, "en"):
		return "en"
	case strings.HasPrefix(l, "es"):
		return "es"
	case strings.HasPrefix(l, "zh"):
		return "zh-Hans"
	case strings.HasPrefix(l, "hi"):
		return "hi"
	case strings.HasPrefix(l, "ar"):
		return "ar"
	case strings.HasPrefix(l, "pt"):
		return "pt-BR"
	case strings.HasPrefix(l, "fr"):
		return "fr"
	case strings.HasPrefix(l, "de"):
		return "de"
	case strings.HasPrefix(l, "ja"):
		return "ja"
	default:
		return "tr"
	}
}

type LanguageChoice struct {
	Code string
	Name string
}

func Languages() []LanguageChoice {
	return []LanguageChoice{
		{"en", "English"},
		{"tr", "Türkçe"},
		{"es", "Español"},
		{"zh-Hans", "简体中文"},
		{"hi", "हिन्दी"},
		{"ar", "العربية"},
		{"pt-BR", "Português (Brasil)"},
		{"fr", "Français"},
		{"de", "Deutsch"},
		{"ja", "日本語"},
	}
}

func T(key string) string {
	if v, ok := extra[current][key]; ok {
		return v
	}
	if v, ok := catalog[current][key]; ok {
		return v
	}
	if v, ok := extra["en"][key]; ok {
		return v
	}
	if v, ok := catalog["en"][key]; ok {
		return v
	}
	return key
}

func Format(key string, args ...any) string {
	s := T(key)
	for i, arg := range args {
		repl := sprint(arg)
		n := itoa(i + 1)
		s = strings.ReplaceAll(s, "%"+n+"$lld", repl)
		s = strings.ReplaceAll(s, "%"+n+"$@", repl)
		s = strings.ReplaceAll(s, "%"+n+"$d", repl)
		s = strings.ReplaceAll(s, "%"+n+"$s", repl)
	}
	for _, arg := range args {
		repl := sprint(arg)
		switch {
		case strings.Contains(s, "%@"):
			s = strings.Replace(s, "%@", repl, 1)
		case strings.Contains(s, "%lld"):
			s = strings.Replace(s, "%lld", repl, 1)
		case strings.Contains(s, "%d"):
			s = strings.Replace(s, "%d", repl, 1)
		}
	}
	return s
}

func sprint(v any) string {
	switch n := v.(type) {
	case int:
		return itoa(n)
	case string:
		return n
	default:
		return ""
	}
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	neg := n < 0
	if neg {
		n = -n
	}
	var b [20]byte
	i := len(b)
	for n > 0 {
		i--
		b[i] = byte('0' + n%10)
		n /= 10
	}
	if neg {
		i--
		b[i] = '-'
	}
	return string(b[i:])
}

var extra = map[string]map[string]string{
	"en": {
		"ui.quit":   "Quit",
		"ui.on":     "On",
		"ui.off":    "Off",
		"ui.legend": "A / Enter confirm    B / Esc back    Arrows move    1–9 play a card    F11 fullscreen",
	},
	"tr": {
		"ui.quit":   "Çıkış",
		"ui.on":     "Açık",
		"ui.off":    "Kapalı",
		"ui.legend": "A / Enter seç    B / Esc geri    Oklar hareket    1–9 kart oyna    F11 tam ekran",
	},
	"es": {
		"ui.quit":   "Salir",
		"ui.on":     "Sí",
		"ui.off":    "No",
		"ui.legend": "A / Enter confirmar    B / Esc volver    Flechas mover    1–9 jugar carta    F11 pantalla completa",
	},
	"zh-Hans": {
		"ui.quit":   "退出",
		"ui.on":     "开",
		"ui.off":    "关",
		"ui.legend": "A / Enter 确认    B / Esc 返回    方向键 移动    1–9 出牌    F11 全屏",
	},
	"hi": {
		"ui.quit":   "बाहर",
		"ui.on":     "चालू",
		"ui.off":    "बंद",
		"ui.legend": "A / Enter चुनें    B / Esc वापस    तीर चलाएँ    1–9 पत्ता खेलें    F11 पूर्ण स्क्रीन",
	},
	"ar": {
		"ui.quit":   "خروج",
		"ui.on":     "تشغيل",
		"ui.off":    "إيقاف",
		"ui.legend": "A / Enter تأكيد    B / Esc رجوع    الأسهم تحريك    1–9 لعب ورقة    F11 ملء الشاشة",
	},
	"pt-BR": {
		"ui.quit":   "Sair",
		"ui.on":     "Ligado",
		"ui.off":    "Desligado",
		"ui.legend": "A / Enter confirmar    B / Esc voltar    Setas mover    1–9 jogar carta    F11 tela cheia",
	},
	"fr": {
		"ui.quit":   "Quitter",
		"ui.on":     "Oui",
		"ui.off":    "Non",
		"ui.legend": "A / Entrée confirmer    B / Échap retour    Flèches déplacer    1–9 jouer    F11 plein écran",
	},
	"de": {
		"ui.quit":   "Beenden",
		"ui.on":     "An",
		"ui.off":    "Aus",
		"ui.legend": "A / Enter bestätigen    B / Esc zurück    Pfeile bewegen    1–9 Karte spielen    F11 Vollbild",
	},
	"ja": {
		"ui.quit":   "終了",
		"ui.on":     "オン",
		"ui.off":    "オフ",
		"ui.legend": "A / Enter 決定    B / Esc 戻る    矢印 移動    1–9 カード    F11 全画面",
	},
}

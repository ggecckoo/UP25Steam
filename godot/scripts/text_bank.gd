class_name TextBank
extends RefCounted

const LANGUAGES := [
	["en", "English"],
	["tr", "Türkçe"],
	["es", "Español"],
	["zh-Hans", "简体中文"],
	["hi", "हिन्दी"],
	["ar", "العربية"],
	["pt-BR", "Português (Brasil)"],
	["fr", "Français"],
	["de", "Deutsch"],
	["ja", "日本語"],
]

var lang := "tr"
var catalog: Dictionary = {}

const EXTRA := {
	"en": {
		"ui.quit": "Quit",
		"ui.on": "On",
		"ui.off": "Off",
		"ui.legend": "Enter confirm    Esc back    Arrows move    1–9 play a card    F11 fullscreen",
	},
	"tr": {
		"ui.quit": "Çıkış",
		"ui.on": "Açık",
		"ui.off": "Kapalı",
		"ui.legend": "Enter seç    Esc geri    Oklar hareket    1–9 kart oyna    F11 tam ekran",
	},
	"es": {
		"ui.quit": "Salir",
		"ui.on": "Sí",
		"ui.off": "No",
		"ui.legend": "Enter confirmar    Esc volver    Flechas mover    1–9 jugar carta    F11 pantalla completa",
	},
	"zh-Hans": {
		"ui.quit": "退出",
		"ui.on": "开",
		"ui.off": "关",
		"ui.legend": "Enter 确认    Esc 返回    方向键 移动    1–9 出牌    F11 全屏",
	},
	"hi": {
		"ui.quit": "बाहर",
		"ui.on": "चालू",
		"ui.off": "बंद",
		"ui.legend": "Enter चुनें    Esc वापस    तीर चलाएँ    1–9 पत्ता खेलें    F11 पूर्ण स्क्रीन",
	},
	"ar": {
		"ui.quit": "خروج",
		"ui.on": "تشغيل",
		"ui.off": "إيقاف",
		"ui.legend": "Enter تأكيد    Esc رجوع    الأسهم تحريك    1–9 لعب ورقة    F11 ملء الشاشة",
	},
	"pt-BR": {
		"ui.quit": "Sair",
		"ui.on": "Ligado",
		"ui.off": "Desligado",
		"ui.legend": "Enter confirmar    Esc voltar    Setas mover    1–9 jogar carta    F11 tela cheia",
	},
	"fr": {
		"ui.quit": "Quitter",
		"ui.on": "Oui",
		"ui.off": "Non",
		"ui.legend": "Entrée confirmer    Échap retour    Flèches déplacer    1–9 jouer    F11 plein écran",
	},
	"de": {
		"ui.quit": "Beenden",
		"ui.on": "An",
		"ui.off": "Aus",
		"ui.legend": "Enter bestätigen    Esc zurück    Pfeile bewegen    1–9 Karte spielen    F11 Vollbild",
	},
	"ja": {
		"ui.quit": "終了",
		"ui.on": "オン",
		"ui.off": "オフ",
		"ui.legend": "Enter 決定    Esc 戻る    矢印 移動    1–9 カード    F11 全画面",
	},
}


func load_file(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("missing catalog %s" % path)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		catalog = parsed


func set_language(code: String) -> bool:
	if not catalog.has(code) and not EXTRA.has(code):
		return false
	lang = code
	return true


func rtl() -> bool:
	return lang == "ar"


func detect(locale: String) -> String:
	var value := locale.replace("-", "_").to_lower()
	if value.begins_with("zh"):
		return "zh-Hans"
	if value.begins_with("pt"):
		return "pt-BR"
	for pair in LANGUAGES:
		var code: String = pair[0]
		if value.begins_with(code.to_lower()):
			return code
	return "tr"


func t(key: String) -> String:
	if EXTRA.has(lang) and EXTRA[lang].has(key):
		return EXTRA[lang][key]
	if catalog.has(lang) and catalog[lang].has(key):
		return catalog[lang][key]
	if EXTRA["en"].has(key):
		return EXTRA["en"][key]
	if catalog.has("en") and catalog["en"].has(key):
		return catalog["en"][key]
	return key


func format_key(key: String, args: Array) -> String:
	var text := t(key)
	for i in args.size():
		var repl := str(args[i])
		var n := str(i + 1)
		text = text.replace("%%%s$lld" % n, repl)
		text = text.replace("%%%s$@" % n, repl)
		text = text.replace("%%%s$d" % n, repl)
		text = text.replace("%%%s$s" % n, repl)
	for arg in args:
		var repl := str(arg)
		var at := text.find("%@")
		if at >= 0:
			text = text.substr(0, at) + repl + text.substr(at + 2)
			continue
		var marker := text.find("%lld")
		if marker >= 0:
			text = text.substr(0, marker) + repl + text.substr(marker + 4)
	return text

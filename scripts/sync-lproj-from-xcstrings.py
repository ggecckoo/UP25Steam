#!/usr/bin/env python3
"""Build UP 25/L10nCatalog.json from Localizable.xcstrings for in-app language switching.

Keeps Localizable.xcstrings as the editable source. Does NOT emit .strings files
(those conflict with the String Catalog table name).
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "UP 25"
CATALOG = ROOT / "Localizable.xcstrings"
OUT = ROOT / "L10nCatalog.json"
LANGS = ["en", "tr", "es", "zh-Hans", "hi", "ar", "pt-BR", "fr", "de", "ja"]
SKIP = {
    " ",
    "%lld",
    "%lld%%",
    "?",
    "›",
    "✕",
    "♛",
    "♠",
    "♥",
    "♠ ♥ ♦ ♣",
    "Atiko Labs",
}


def main() -> None:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    out: dict[str, dict[str, str]] = {lang: {} for lang in LANGS}
    for key, entry in catalog["strings"].items():
        if not key.strip() or key in SKIP:
            continue
        locs = entry.get("localizations") or {}
        en = None
        if "en" in locs and "stringUnit" in locs["en"]:
            en = locs["en"]["stringUnit"].get("value")
        for lang in LANGS:
            unit = None
            if lang in locs and "stringUnit" in locs[lang]:
                unit = locs[lang]["stringUnit"].get("value")
            elif en is not None:
                unit = en
            if unit is not None:
                out[lang][key] = unit

    # Remove legacy .lproj string tables that conflict with Localizable.xcstrings
    for lang in LANGS:
        lproj = ROOT / f"{lang}.lproj"
        if not lproj.is_dir():
            continue
        for name in ("Localizable.strings", "App.strings", "Localizable.stringsdict"):
            f = lproj / name
            if f.exists():
                f.unlink()
                print("removed", f.relative_to(ROOT.parent))
        # remove empty lproj dirs
        if lproj.is_dir() and not any(lproj.iterdir()):
            lproj.rmdir()
            print("removed empty", lproj.relative_to(ROOT.parent))

    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    counts = {lang: len(out[lang]) for lang in LANGS}
    print("wrote", OUT.relative_to(ROOT.parent), counts)


if __name__ == "__main__":
    main()

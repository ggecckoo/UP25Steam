#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLI="$ROOT/.bin/supabase"
PLIST="$ROOT/UP 25/Config/SupabaseConfig.plist"
EXAMPLE="$ROOT/UP 25/Config/SupabaseConfig.example.plist"

if [[ ! -x "$CLI" ]]; then
  echo "Önce: ./scripts/install-supabase-cli.sh" >&2
  exit 1
fi

if [[ -f "$ROOT/.env" ]]; then
  # shellcheck disable=SC1091
  set -a
  source "$ROOT/.env"
  set +a
fi

PROJECT_REF="${SUPABASE_PROJECT_REF:-}"
if [[ -z "$PROJECT_REF" && -f "$ROOT/supabase/.temp/project-ref" ]]; then
  PROJECT_REF="$(cat "$ROOT/supabase/.temp/project-ref")"
fi

if [[ -z "$PROJECT_REF" ]]; then
  echo "SUPABASE_PROJECT_REF tanımlı değil ve proje bağlı değil." >&2
  exit 1
fi

JSON="$("$CLI" projects api-keys --project-ref "$PROJECT_REF" --output json)"
ANON_KEY="$(printf '%s' "$JSON" | python3 -c '
import json, sys
data = json.load(sys.stdin)
for item in data:
    name = (item.get("name") or item.get("id") or "").lower()
    if name in ("anon", "anon key", "legacy anon"):
        print(item.get("api_key") or item.get("key") or "")
        break
else:
    # fallback: first key that looks like JWT anon
    for item in data:
        key = item.get("api_key") or item.get("key") or ""
        if "anon" in json.dumps(item).lower() and key:
            print(key)
            break
    else:
        raise SystemExit("anon key bulunamadı: " + json.dumps(data)[:500])
')"

if [[ -z "$ANON_KEY" ]]; then
  echo "anon key boş geldi" >&2
  exit 1
fi

URL="https://${PROJECT_REF}.supabase.co"
mkdir -p "$(dirname "$PLIST")"
cp "$EXAMPLE" "$PLIST"

/usr/bin/plutil -replace SUPABASE_URL -string "$URL" "$PLIST"
/usr/bin/plutil -replace SUPABASE_ANON_KEY -string "$ANON_KEY" "$PLIST"

echo "Güncellendi: $PLIST"
echo "URL: $URL"

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLI="$ROOT/.bin/supabase"

bash "$ROOT/scripts/install-supabase-cli.sh"

if [[ -f "$ROOT/.env" ]]; then
  # shellcheck disable=SC1091
  set -a
  source "$ROOT/.env"
  set +a
else
  echo "Uyarı: .env yok. Örnekten kopyalayın: cp .env.example .env" >&2
fi

cd "$ROOT"

if [[ -n "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
  echo "Supabase'e token ile giriş yapılıyor…"
  "$CLI" login --token "$SUPABASE_ACCESS_TOKEN"
else
  echo "Tarayıcıda Supabase girişi açılacak…"
  "$CLI" login
fi

echo ""
echo "Organizasyonlar / projeler:"
"$CLI" projects list

ORG_ID="${SUPABASE_ORG_ID:-}"
PROJECT_REF="${SUPABASE_PROJECT_REF:-}"
DB_PASSWORD="${SUPABASE_DB_PASSWORD:-}"
PROJECT_NAME="${SUPABASE_PROJECT_NAME:-yirmibes}"
REGION="${SUPABASE_REGION:-eu-central-1}"

# Yeni proje oluştur (ref yoksa)
if [[ -z "$PROJECT_REF" ]]; then
  if [[ -z "$ORG_ID" ]]; then
    echo ""
    echo "ORG_ID bulunamadı. Aşağıdaki listeden organizasyon id'sini .env'ye SUPABASE_ORG_ID olarak yazın,"
    echo "veya mevcut bir proje için SUPABASE_PROJECT_REF ekleyin."
    "$CLI" orgs list || true
    exit 1
  fi
  if [[ -z "$DB_PASSWORD" ]]; then
    DB_PASSWORD="$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)"
    echo "Üretilen DB şifresi .env'ye yazılacak."
  fi
  echo ""
  echo "Yeni proje oluşturuluyor: $PROJECT_NAME ($REGION)…"
  CREATE_OUT="$("$CLI" projects create "$PROJECT_NAME" \
    --org-id "$ORG_ID" \
    --db-password "$DB_PASSWORD" \
    --region "$REGION" \
    --output json)"
  PROJECT_REF="$(printf '%s' "$CREATE_OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
  mkdir -p "$ROOT"
  if [[ -f "$ROOT/.env" ]]; then
    grep -q '^SUPABASE_PROJECT_REF=' "$ROOT/.env" \
      && sed -i '' "s/^SUPABASE_PROJECT_REF=.*/SUPABASE_PROJECT_REF=$PROJECT_REF/" "$ROOT/.env" \
      || echo "SUPABASE_PROJECT_REF=$PROJECT_REF" >> "$ROOT/.env"
    grep -q '^SUPABASE_DB_PASSWORD=' "$ROOT/.env" \
      && sed -i '' "s/^SUPABASE_DB_PASSWORD=.*/SUPABASE_DB_PASSWORD=$DB_PASSWORD/" "$ROOT/.env" \
      || echo "SUPABASE_DB_PASSWORD=$DB_PASSWORD" >> "$ROOT/.env"
  else
    cat > "$ROOT/.env" <<EOF
SUPABASE_PROJECT_REF=$PROJECT_REF
SUPABASE_DB_PASSWORD=$DB_PASSWORD
SUPABASE_ORG_ID=$ORG_ID
EOF
  fi
  echo "Proje hazır: $PROJECT_REF — API aktif olana kadar ~60s bekleniyor…"
  sleep 75
fi

echo ""
echo "Proje bağlanıyor: $PROJECT_REF"
LINK_ARGS=(link --project-ref "$PROJECT_REF" --yes)
if [[ -n "${DB_PASSWORD:-}" ]]; then
  LINK_ARGS+=(--password "$DB_PASSWORD")
fi
"$CLI" "${LINK_ARGS[@]}"

echo ""
echo "Migration'lar uzak veritabanına gönderiliyor…"
"$CLI" db push --yes

echo ""
bash "$ROOT/scripts/sync-supabase-plist.sh"

echo ""
echo "Tamamlandı. Xcode'da uygulamayı çalıştırabilirsiniz."
echo "Dashboard: https://supabase.com/dashboard/project/$PROJECT_REF"

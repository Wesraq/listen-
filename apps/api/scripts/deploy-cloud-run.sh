#!/usr/bin/env bash
# Deploy Listen+ Nest API to Cloud Run (no local Docker required — Cloud Build packs the source).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROJECT_ID="${GOOGLE_CLOUD_PROJECT:-${FIREBASE_PROJECT_ID:-listenplus-d9188}}"
REGION="${CLOUD_RUN_REGION:-us-central1}"
SERVICE="${CLOUD_RUN_SERVICE:-listen-api}"
KEY_FILE="${GOOGLE_APPLICATION_CREDENTIALS:-$ROOT/service-account.json}"

if [[ ! -f "$KEY_FILE" ]]; then
  echo "Missing service account key at $KEY_FILE"
  exit 1
fi

export PATH="/opt/homebrew/share/google-cloud-sdk/bin:/usr/local/share/google-cloud-sdk/bin:${PATH:-}"

if ! command -v gcloud >/dev/null 2>&1; then
  echo "gcloud not found. Install: brew install --cask google-cloud-sdk"
  exit 1
fi

gcloud config set project "$PROJECT_ID" >/dev/null

ACTIVE="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | head -1 || true)"
if [[ -z "$ACTIVE" || "$ACTIVE" == *firebase-adminsdk* ]]; then
  echo "Cloud Run deploy needs your Google owner account (not the Firebase Admin SDK key)."
  echo "Run once in a terminal:"
  echo "  gcloud auth login"
  echo "  gcloud config set project $PROJECT_ID"
  echo "Then re-run: bash apps/api/scripts/deploy-cloud-run.sh"
  if [[ ! -t 0 ]]; then
    exit 2
  fi
  gcloud auth login
fi

echo "→ Active account: $(gcloud auth list --filter=status:ACTIVE --format='value(account)' | head -1)"
echo "→ Enabling required APIs (idempotent)"
gcloud services enable \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  firestore.googleapis.com \
  storage.googleapis.com \
  --project="$PROJECT_ID"

echo "→ Deploying $SERVICE to Cloud Run ($REGION) from source"
gcloud run deploy "$SERVICE" \
  --source="$ROOT" \
  --region="$REGION" \
  --project="$PROJECT_ID" \
  --platform=managed \
  --allow-unauthenticated \
  --port=8080 \
  --memory=512Mi \
  --cpu=1 \
  --min-instances=0 \
  --max-instances=3 \
  --set-env-vars="DATA_BACKEND=firestore,MEDIA_BACKEND=firebase,AUTH_MODE=hybrid,FIREBASE_PROJECT_ID=${PROJECT_ID},FIREBASE_STORAGE_BUCKET=${PROJECT_ID}.firebasestorage.app,FIRESTORE_PREFIX=listen,PAYMENTS_MODE=simulate,ALLOW_SIMULATED_PAYMENTS=true,ALLOW_CLIENT_GRANTS=true,AD_GROSS_MINOR=${AD_GROSS_MINOR:-50},PAYMENT_WEBHOOK_SECRET=${PAYMENT_WEBHOOK_SECRET:-change-me}"

URL="$(gcloud run services describe "$SERVICE" --region="$REGION" --project="$PROJECT_ID" --format='value(status.url)')"
echo ""
echo "✓ Deployed: ${URL}/v1"
echo "  Point mobile with:"
echo "  flutter run --release --dart-define=LISTEN_API_BASE=${URL}/v1"

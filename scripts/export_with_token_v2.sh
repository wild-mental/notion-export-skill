#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ $# -lt 1 || -z "${1:-}" ]]; then
  echo "Usage: $(basename "$0") <Notion URL or page_id>" >&2
  exit 2
fi
PAGE_ID="$1"
TOKEN_SERVICE="${NOTION_TOKEN_V2_SERVICE:-notion-export-token-v2}"
FILE_SERVICE="${NOTION_FILE_TOKEN_SERVICE:-notion-export-file-token}"
KEYCHAIN_ACCOUNT="${NOTION_KEYCHAIN_ACCOUNT:-notion-export}"

read_keychain_secret() {
  local service="$1"
  if command -v security >/dev/null 2>&1; then
    security find-generic-password -a "$KEYCHAIN_ACCOUNT" -s "$service" -w 2>/dev/null || true
  fi
}

save_keychain_secret() {
  local service="$1"
  local value="$2"
  if command -v security >/dev/null 2>&1; then
    security add-generic-password -U -a "$KEYCHAIN_ACCOUNT" -s "$service" -w "$value" >/dev/null
  fi
}

prompt_secret() {
  local prompt="$1"
  local value
  IFS= read -r -s -p "$prompt" value
  printf "\n" >&2
  printf "%s" "$value"
}

preflight_token_access() {
  local tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/notion-token-access.XXXXXX.json")"
  if ! python3 scripts/check_token_v2_block_access.py "$PAGE_ID" > "$tmp"; then
    cat "$tmp" >&2 || true
    rm -f "$tmp"
    return 1
  fi
  if python3 - "$tmp" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path))
for origin in data.get("origins", []):
    record = origin.get("getRecordValues", {})
    if record.get("has_value") and record.get("matches_page") and record.get("role") != "none":
        print(f"token_v2 access ok: {origin.get('origin')} role={record.get('role')}", file=sys.stderr)
        raise SystemExit(0)
print(json.dumps(data, ensure_ascii=False, indent=2), file=sys.stderr)
raise SystemExit(1)
PY
  then
    rm -f "$tmp"
    return 0
  fi
  rm -f "$tmp"
  return 1
}

loaded_from_keychain=0
prompted=0

if [[ -z "${NOTION_TOKEN_V2:-}" ]]; then
  NOTION_TOKEN_V2="$(read_keychain_secret "$TOKEN_SERVICE")"
  if [[ -n "${NOTION_TOKEN_V2:-}" ]]; then
    loaded_from_keychain=1
  fi
fi

if [[ -z "${NOTION_FILE_TOKEN:-}" ]]; then
  NOTION_FILE_TOKEN="$(read_keychain_secret "$FILE_SERVICE")"
  if [[ -n "${NOTION_FILE_TOKEN:-}" ]]; then
    loaded_from_keychain=1
  fi
fi

if [[ -z "${NOTION_TOKEN_V2:-}" ]]; then
  NOTION_TOKEN_V2="$(prompt_secret "NOTION_TOKEN_V2: ")"
  prompted=1
fi

if [[ -z "${NOTION_FILE_TOKEN:-}" ]]; then
  NOTION_FILE_TOKEN="$(prompt_secret "NOTION_FILE_TOKEN: ")"
  prompted=1
fi

if [[ -z "${NOTION_TOKEN_V2:-}" || -z "${NOTION_FILE_TOKEN:-}" ]]; then
  echo "Both NOTION_TOKEN_V2 and NOTION_FILE_TOKEN are required." >&2
  exit 1
fi

export NOTION_TOKEN_V2
export NOTION_FILE_TOKEN

if ! preflight_token_access; then
  if [[ "$loaded_from_keychain" == "1" && "${NOTION_FORCE_PROMPT:-0}" != "1" ]]; then
    echo "Stored token_v2 cannot access this page. Enter fresh cookies." >&2
    NOTION_TOKEN_V2="$(prompt_secret "NOTION_TOKEN_V2: ")"
    NOTION_FILE_TOKEN="$(prompt_secret "NOTION_FILE_TOKEN: ")"
    export NOTION_TOKEN_V2
    export NOTION_FILE_TOKEN
    prompted=1
    preflight_token_access
  else
    echo "token_v2 access preflight failed." >&2
    exit 1
  fi
fi

if [[ "$prompted" == "1" && "${NOTION_SAVE_COOKIES:-}" != "0" ]]; then
  IFS= read -r -p "Save/update these cookies in macOS Keychain for future runs? [y/N]: " save_answer
  if [[ "$save_answer" =~ ^[Yy]$ ]]; then
    save_keychain_secret "$TOKEN_SERVICE" "$NOTION_TOKEN_V2"
    save_keychain_secret "$FILE_SERVICE" "$NOTION_FILE_TOKEN"
    echo "Saved Notion export cookies to macOS Keychain." >&2
  fi
fi

python3 scripts/export_notion_zip_token_v2.py "$PAGE_ID" --type markdown

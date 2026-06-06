#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# shellcheck source=scripts/notion_export_secrets.sh
source "$ROOT_DIR/scripts/notion_export_secrets.sh"

notion_export_require_page_arg "$0" "$@" || exit $?
PAGE_ID="$1"

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

loaded_from_secret_store=0
prompted=0

if [[ -z "${NOTION_TOKEN_V2:-}" ]]; then
  NOTION_TOKEN_V2="$(notion_export_read_secret "$NOTION_EXPORT_TOKEN_SERVICE")"
  if [[ -n "${NOTION_TOKEN_V2:-}" ]]; then
    loaded_from_secret_store=1
  fi
fi

if [[ -z "${NOTION_FILE_TOKEN:-}" ]]; then
  NOTION_FILE_TOKEN="$(notion_export_read_secret "$NOTION_EXPORT_FILE_SERVICE")"
  if [[ -n "${NOTION_FILE_TOKEN:-}" ]]; then
    loaded_from_secret_store=1
  fi
fi

if [[ -z "${NOTION_TOKEN_V2:-}" ]]; then
  NOTION_TOKEN_V2="$(notion_export_prompt_secret "NOTION_TOKEN_V2: ")"
  prompted=1
fi

if [[ -z "${NOTION_FILE_TOKEN:-}" ]]; then
  NOTION_FILE_TOKEN="$(notion_export_prompt_secret "NOTION_FILE_TOKEN: ")"
  prompted=1
fi

if [[ -z "${NOTION_TOKEN_V2:-}" || -z "${NOTION_FILE_TOKEN:-}" ]]; then
  echo "Both NOTION_TOKEN_V2 and NOTION_FILE_TOKEN are required." >&2
  exit 1
fi

export NOTION_TOKEN_V2
export NOTION_FILE_TOKEN

if ! preflight_token_access; then
  if [[ "$loaded_from_secret_store" == "1" && "${NOTION_FORCE_PROMPT:-0}" != "1" ]]; then
    echo "Stored token_v2 cannot access this page. Enter fresh cookies." >&2
    NOTION_TOKEN_V2="$(notion_export_prompt_secret "NOTION_TOKEN_V2: ")"
    NOTION_FILE_TOKEN="$(notion_export_prompt_secret "NOTION_FILE_TOKEN: ")"
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
  IFS= read -r -p "Save/update these cookies for future runs? [y/N]: " save_answer
  if [[ "$save_answer" =~ ^[Yy]$ ]]; then
    save_token_v2="$(notion_export_normalize_cookie_value "$NOTION_TOKEN_V2" "token_v2")"
    save_file_token="$(notion_export_normalize_cookie_value "$NOTION_FILE_TOKEN" "file_token")"
    notion_export_save_credentials "$save_token_v2" "$save_file_token"
  fi
fi

python3 scripts/export_notion_zip_token_v2.py "$PAGE_ID" --type markdown

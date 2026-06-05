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
KEYCHAIN_ACCOUNT="${NOTION_KEYCHAIN_ACCOUNT:-notion-export}"

read_keychain_secret() {
  if command -v security >/dev/null 2>&1; then
    security find-generic-password -a "$KEYCHAIN_ACCOUNT" -s "$TOKEN_SERVICE" -w 2>/dev/null || true
  fi
}

if [[ -z "${NOTION_TOKEN_V2:-}" ]]; then
  NOTION_TOKEN_V2="$(read_keychain_secret)"
fi

if [[ -z "${NOTION_TOKEN_V2:-}" ]]; then
  IFS= read -r -s -p "NOTION_TOKEN_V2: " NOTION_TOKEN_V2
  printf "\n" >&2
fi

export NOTION_TOKEN_V2
python3 scripts/check_token_v2_block_access.py "$PAGE_ID"

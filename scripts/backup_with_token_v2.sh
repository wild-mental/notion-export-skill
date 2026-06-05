#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PAGE_ID="${1:-374d03212bd480d09d7ff5a9ba7461bf}"

if [[ -z "${NOTION_TOKEN_V2:-}" ]]; then
  IFS= read -r -s -p "NOTION_TOKEN_V2: " NOTION_TOKEN_V2
  printf "\n" >&2
fi

if [[ -z "${NOTION_TOKEN_V2:-}" ]]; then
  echo "NOTION_TOKEN_V2 is empty." >&2
  exit 1
fi

export NOTION_TOKEN_V2
python3 scripts/check_notion_asset_auth.py
python3 scripts/download_notion_page.py "$PAGE_ID"

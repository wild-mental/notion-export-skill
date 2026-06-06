#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# shellcheck source=scripts/notion_export_secrets.sh
source "$ROOT_DIR/scripts/notion_export_secrets.sh"

notion_export_require_page_arg "$0" "$@" || exit $?
PAGE_ID="$1"

if [[ -z "${NOTION_TOKEN_V2:-}" ]]; then
  NOTION_TOKEN_V2="$(notion_export_prompt_secret "NOTION_TOKEN_V2: ")"
fi

if [[ -z "${NOTION_TOKEN_V2:-}" ]]; then
  echo "NOTION_TOKEN_V2 is empty." >&2
  exit 1
fi

export NOTION_TOKEN_V2
python3 scripts/check_notion_asset_auth.py
python3 scripts/download_notion_page.py "$PAGE_ID"

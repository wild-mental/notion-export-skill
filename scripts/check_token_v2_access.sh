#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# shellcheck source=scripts/notion_export_secrets.sh
source "$ROOT_DIR/scripts/notion_export_secrets.sh"

notion_export_require_page_arg "$0" "$@" || exit $?
PAGE_ID="$1"

if [[ -z "${NOTION_TOKEN_V2:-}" ]]; then
  NOTION_TOKEN_V2="$(notion_export_read_secret "$NOTION_EXPORT_TOKEN_SERVICE")"
fi

if [[ -z "${NOTION_TOKEN_V2:-}" ]]; then
  NOTION_TOKEN_V2="$(notion_export_prompt_secret "NOTION_TOKEN_V2: ")"
fi

export NOTION_TOKEN_V2
python3 scripts/check_token_v2_block_access.py "$PAGE_ID"

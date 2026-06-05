#!/usr/bin/env bash
set -euo pipefail

TOKEN_SERVICE="${NOTION_TOKEN_V2_SERVICE:-notion-export-token-v2}"
FILE_SERVICE="${NOTION_FILE_TOKEN_SERVICE:-notion-export-file-token}"
KEYCHAIN_ACCOUNT="${NOTION_KEYCHAIN_ACCOUNT:-notion-export}"

trim_cookie_value() {
  local value="$1"
  local name="$2"
  local part

  value="${value#Cookie:}"
  value="${value#cookie:}"
  IFS=';' read -r -a parts <<< "$value"
  for part in "${parts[@]}"; do
    part="${part#"${part%%[![:space:]]*}"}"
    part="${part%"${part##*[![:space:]]}"}"
    if [[ "$part" == "$name="* ]]; then
      printf "%s" "${part#*=}"
      return
    fi
  done

  if [[ "$value" == "$name="* ]]; then
    printf "%s" "${value#*=}"
  else
    printf "%s" "$value"
  fi
}

read_secret() {
  local prompt="$1"
  local value
  IFS= read -r -s -p "$prompt" value
  printf "\n" >&2
  printf "%s" "$value"
}

save_secret() {
  local service="$1"
  local value="$2"
  security add-generic-password \
    -U \
    -a "$KEYCHAIN_ACCOUNT" \
    -s "$service" \
    -w "$value" >/dev/null
}

if ! command -v security >/dev/null 2>&1; then
  echo "macOS security command is required." >&2
  exit 1
fi

token_v2="$(read_secret "NOTION_TOKEN_V2: ")"
file_token="$(read_secret "NOTION_FILE_TOKEN: ")"

token_v2="$(trim_cookie_value "$token_v2" "token_v2")"
file_token="$(trim_cookie_value "$file_token" "file_token")"

if [[ -z "$token_v2" || -z "$file_token" ]]; then
  echo "Both NOTION_TOKEN_V2 and NOTION_FILE_TOKEN are required." >&2
  exit 1
fi

save_secret "$TOKEN_SERVICE" "$token_v2"
save_secret "$FILE_SERVICE" "$file_token"

echo "Saved Notion export cookies to macOS Keychain."

#!/usr/bin/env bash

NOTION_EXPORT_TOKEN_SERVICE="${NOTION_TOKEN_V2_SERVICE:-notion-export-token-v2}"
NOTION_EXPORT_FILE_SERVICE="${NOTION_FILE_TOKEN_SERVICE:-notion-export-file-token}"
NOTION_EXPORT_KEYCHAIN_ACCOUNT="${NOTION_KEYCHAIN_ACCOUNT:-notion-export}"
NOTION_EXPORT_CONFIG_DIR="${NOTION_EXPORT_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/notion-export}"
NOTION_EXPORT_COOKIE_FILE="${NOTION_EXPORT_COOKIE_FILE:-$NOTION_EXPORT_CONFIG_DIR/cookies.env}"

notion_export_normalize_cookie_value() {
  local value="$1"
  local name="$2"
  local part

  value="${value#Cookie:}"
  value="${value#cookie:}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"

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

notion_export_prompt_secret() {
  local prompt="$1"
  local value
  IFS= read -r -s -p "$prompt" value
  printf "\n" >&2
  printf "%s" "$value"
}

notion_export_backend() {
  local requested="${NOTION_SECRET_BACKEND:-auto}"
  if [[ "$requested" != "auto" ]]; then
    printf "%s" "$requested"
    return
  fi

  if [[ "$(uname -s 2>/dev/null || true)" == "Darwin" ]] && command -v security >/dev/null 2>&1; then
    printf "keychain"
    return
  fi

  if command -v secret-tool >/dev/null 2>&1; then
    printf "secret-tool"
    return
  fi

  printf "file"
}

notion_export_base64_encode() {
  printf "%s" "$1" | base64 | tr -d '\n'
}

notion_export_base64_decode() {
  local value="$1"
  if printf "%s" "$value" | base64 --decode 2>/dev/null; then
    return
  fi
  printf "%s" "$value" | base64 -D 2>/dev/null
}

notion_export_file_value() {
  local key="$1"
  local line value
  [[ -f "$NOTION_EXPORT_COOKIE_FILE" ]] || return 0
  line="$(grep -E "^${key}=" "$NOTION_EXPORT_COOKIE_FILE" 2>/dev/null | tail -n 1 || true)"
  [[ -n "$line" ]] || return 0
  value="${line#*=}"
  notion_export_base64_decode "$value"
}

notion_export_read_secret() {
  local service="$1"
  local backend
  backend="$(notion_export_backend)"

  case "$backend" in
    keychain)
      security find-generic-password -a "$NOTION_EXPORT_KEYCHAIN_ACCOUNT" -s "$service" -w 2>/dev/null || true
      ;;
    secret-tool)
      secret-tool lookup application notion-export service "$service" account "$NOTION_EXPORT_KEYCHAIN_ACCOUNT" 2>/dev/null || true
      ;;
    file)
      if [[ "$service" == "$NOTION_EXPORT_TOKEN_SERVICE" ]]; then
        notion_export_file_value "NOTION_TOKEN_V2_B64"
      elif [[ "$service" == "$NOTION_EXPORT_FILE_SERVICE" ]]; then
        notion_export_file_value "NOTION_FILE_TOKEN_B64"
      fi
      ;;
    none)
      ;;
    *)
      echo "Unsupported NOTION_SECRET_BACKEND: $backend" >&2
      return 1
      ;;
  esac
}

notion_export_save_keychain_secret() {
  local service="$1"
  local value="$2"
  security add-generic-password \
    -U \
    -a "$NOTION_EXPORT_KEYCHAIN_ACCOUNT" \
    -s "$service" \
    -w "$value" >/dev/null
}

notion_export_save_secret_tool_secret() {
  local service="$1"
  local value="$2"
  printf "%s" "$value" | secret-tool store \
    --label="Notion Export $service" \
    application notion-export \
    service "$service" \
    account "$NOTION_EXPORT_KEYCHAIN_ACCOUNT"
}

notion_export_save_file_credentials() {
  local token_v2="$1"
  local file_token="$2"
  local tmp

  if [[ "${NOTION_ALLOW_PLAINTEXT_STORE:-}" != "1" ]]; then
    echo "No OS secret manager is selected/available." >&2
    echo "Fallback storage is a local file with chmod 600:" >&2
    echo "  $NOTION_EXPORT_COOKIE_FILE" >&2
    echo "This is not encrypted at rest." >&2
    local answer
    IFS= read -r -p "Store cookies in this local file? [y/N]: " answer
    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
      return 1
    fi
  fi

  mkdir -p "$NOTION_EXPORT_CONFIG_DIR"
  chmod 700 "$NOTION_EXPORT_CONFIG_DIR" 2>/dev/null || true
  tmp="$(mktemp "${NOTION_EXPORT_COOKIE_FILE}.XXXXXX")"
  {
    printf "NOTION_TOKEN_V2_B64=%s\n" "$(notion_export_base64_encode "$token_v2")"
    printf "NOTION_FILE_TOKEN_B64=%s\n" "$(notion_export_base64_encode "$file_token")"
  } > "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$NOTION_EXPORT_COOKIE_FILE"
}

notion_export_save_credentials() {
  local token_v2="$1"
  local file_token="$2"
  local backend
  backend="$(notion_export_backend)"

  case "$backend" in
    keychain)
      notion_export_save_keychain_secret "$NOTION_EXPORT_TOKEN_SERVICE" "$token_v2"
      notion_export_save_keychain_secret "$NOTION_EXPORT_FILE_SERVICE" "$file_token"
      echo "Saved Notion export cookies to macOS Keychain." >&2
      ;;
    secret-tool)
      notion_export_save_secret_tool_secret "$NOTION_EXPORT_TOKEN_SERVICE" "$token_v2"
      notion_export_save_secret_tool_secret "$NOTION_EXPORT_FILE_SERVICE" "$file_token"
      echo "Saved Notion export cookies with secret-tool." >&2
      ;;
    file)
      notion_export_save_file_credentials "$token_v2" "$file_token"
      echo "Saved Notion export cookies to $NOTION_EXPORT_COOKIE_FILE." >&2
      ;;
    none)
      echo "NOTION_SECRET_BACKEND=none; not saving cookies." >&2
      return 1
      ;;
    *)
      echo "Unsupported NOTION_SECRET_BACKEND: $backend" >&2
      return 1
      ;;
  esac
}

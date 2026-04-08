#!/usr/bin/env bash
set -euo pipefail

resolve_google_accounts_source() {
  local explicit_path="$1"
  local oauth_creds_path="$2"

  if [ -n "$explicit_path" ]; then
    if [ ! -f "$explicit_path" ]; then
      echo "google_accounts.json file not found: $explicit_path" >&2
      exit 1
    fi

    readlink -f "$explicit_path"
    return 0
  fi

  local sibling_path
  sibling_path="$(dirname "$oauth_creds_path")/google_accounts.json"
  if [ -f "$sibling_path" ]; then
    readlink -f "$sibling_path"
  fi
}

usage() {
  cat >&2 <<'EOF'
Usage: gemini-auth-link [--gemini-home <path>] --cred-file <source-oauth-file> [--google-accounts <google-accounts-file>]

Examples:
  gemini-auth-link --cred-file ~/gemini-auths/work/oauth_creds.json
  gemini-auth-link --gemini-home ~/.gemini-team --cred-file ~/gemini-auths/team/oauth_creds.json
  gemini-auth-link --cred-file ~/gemini-auths/work/oauth_creds.json --google-accounts ~/gemini-auths/work/google_accounts.json
EOF
  exit 1
}

TARGET_GEMINI_DIR="${GEMINI_HOME:-$HOME/.gemini}"
OAUTH_CREDS_INPUT=""
GOOGLE_ACCOUNTS_INPUT=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --gemini-home)
      [ "$#" -ge 2 ] || usage
      TARGET_GEMINI_DIR="$2"
      shift 2
      ;;
    --cred-file)
      [ "$#" -ge 2 ] || usage
      OAUTH_CREDS_INPUT="$2"
      shift 2
      ;;
    --google-accounts)
      [ "$#" -ge 2 ] || usage
      GOOGLE_ACCOUNTS_INPUT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    -* )
      echo "Unknown option: $1" >&2
      usage
      ;;
    *)
      echo "Unexpected argument: $1" >&2
      usage
      ;;
  esac
done

if [ -z "$OAUTH_CREDS_INPUT" ]; then
  echo "Missing required option: --cred-file" >&2
  usage
fi

if [ ! -f "$OAUTH_CREDS_INPUT" ]; then
  echo "Source OAuth credentials file not found: $OAUTH_CREDS_INPUT" >&2
  exit 1
fi

OAUTH_CREDS_FILE="$(readlink -f "$OAUTH_CREDS_INPUT")"
GOOGLE_ACCOUNTS_FILE="$(resolve_google_accounts_source "$GOOGLE_ACCOUNTS_INPUT" "$OAUTH_CREDS_FILE")"
TARGET_GEMINI_DIR="$(readlink -m "$TARGET_GEMINI_DIR")"
GLOBAL_OAUTH_CREDS_FILE="$TARGET_GEMINI_DIR/oauth_creds.json"
GLOBAL_GOOGLE_ACCOUNTS_FILE="$TARGET_GEMINI_DIR/google_accounts.json"

mkdir -p "$TARGET_GEMINI_DIR"
chmod 700 "$TARGET_GEMINI_DIR" 2>/dev/null || true

if [ -e "$GLOBAL_OAUTH_CREDS_FILE" ] && [ ! -L "$GLOBAL_OAUTH_CREDS_FILE" ]; then
  BACKUP_PATH="$GLOBAL_OAUTH_CREDS_FILE.backup.$(date +%Y%m%d%H%M%S)"
  mv "$GLOBAL_OAUTH_CREDS_FILE" "$BACKUP_PATH"
  echo "Backed up existing oauth_creds.json to: $BACKUP_PATH" >&2
fi

ln -sfn "$OAUTH_CREDS_FILE" "$GLOBAL_OAUTH_CREDS_FILE"

if [ -n "$GOOGLE_ACCOUNTS_FILE" ]; then
  if [ -e "$GLOBAL_GOOGLE_ACCOUNTS_FILE" ] && [ ! -L "$GLOBAL_GOOGLE_ACCOUNTS_FILE" ]; then
    BACKUP_PATH="$GLOBAL_GOOGLE_ACCOUNTS_FILE.backup.$(date +%Y%m%d%H%M%S)"
    mv "$GLOBAL_GOOGLE_ACCOUNTS_FILE" "$BACKUP_PATH"
    echo "Backed up existing google_accounts.json to: $BACKUP_PATH" >&2
  fi

  ln -sfn "$GOOGLE_ACCOUNTS_FILE" "$GLOBAL_GOOGLE_ACCOUNTS_FILE"
fi

echo "Linked Gemini auth file:" >&2
echo "  $GLOBAL_OAUTH_CREDS_FILE -> $OAUTH_CREDS_FILE" >&2
echo "  Source files can use any basename; Gemini reads this path as oauth_creds.json." >&2
if [ -n "$GOOGLE_ACCOUNTS_FILE" ]; then
  echo "Linked Gemini account file:" >&2
  echo "  $GLOBAL_GOOGLE_ACCOUNTS_FILE -> $GOOGLE_ACCOUNTS_FILE" >&2
fi
echo "Only one auth link can be active in a single ~/.gemini directory." >&2
echo "For simultaneous multi-auth sessions, use gemini-auth." >&2

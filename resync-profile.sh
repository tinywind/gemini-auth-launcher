#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=./profile-common.sh
source "$SCRIPT_DIR/profile-common.sh"
# shellcheck source=./sync-common.sh
source "$SCRIPT_DIR/sync-common.sh"

load_stored_oauth_creds_source() {
  local profile_root="$1"
  local stored_line

  STORED_OAUTH_CREDS_FILE=""

  while IFS= read -r stored_line; do
    case "$stored_line" in
      oauthCredsSource=*)
        STORED_OAUTH_CREDS_FILE="${stored_line#oauthCredsSource=}"
        ;;
    esac
  done < <(load_profile_auth_sources "$profile_root")
}

usage() {
  cat >&2 <<'EOF'
Usage: gemini-auth-resync [--profile <name>] [--cred-file <path>] [--base-home <path>]

Resync shared Gemini config from the base home into one isolated profile.
Auth links and profile-local session history are preserved.

Options:
  --profile <name>      Profile hint used when the profile was created.
  --cred-file <path>    Source OAuth credentials file path. Optional when reusing a named profile.
  --base-home <path>    Existing ~/.gemini directory used as the sync source.
  -h, --help            Show this help.

Examples:
  gemini-auth-resync --cred-file ~/gemini-auths/work/oauth_creds.json
  gemini-auth-resync --profile review
  gemini-auth-resync --profile review --base-home ~/.gemini-team
EOF
  exit 1
}

PROFILE_HINT="${GEMINI_AUTH_LAUNCHER_PROFILE:-}"
BASE_HOME_INPUT="${GEMINI_AUTH_LAUNCHER_BASE_HOME:-$HOME/.gemini}"
OAUTH_CREDS_INPUT=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --profile)
      [ "$#" -ge 2 ] || usage
      PROFILE_HINT="$2"
      shift 2
      ;;
    --cred-file)
      [ "$#" -ge 2 ] || usage
      OAUTH_CREDS_INPUT="$2"
      shift 2
      ;;
    --base-home)
      [ "$#" -ge 2 ] || usage
      BASE_HOME_INPUT="$2"
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

REAL_HOME="${HOME:?HOME is required}"
LAUNCHER_HOME="${GEMINI_AUTH_LAUNCHER_HOME:-$REAL_HOME/.gemini-auth-launcher}"
PROFILE_BASE_DIR="$LAUNCHER_HOME/profiles"
PROFILE_BASE_DIR_CANONICAL="$(readlink -m "$PROFILE_BASE_DIR")"
EXISTING_PROFILE_ROOT=""

if [ ! -d "$BASE_HOME_INPUT" ]; then
  echo "Base home not found: $BASE_HOME_INPUT" >&2
  exit 1
fi

BASE_HOME="$(readlink -f "$BASE_HOME_INPUT")"

if [ -n "$OAUTH_CREDS_INPUT" ] && [ ! -f "$OAUTH_CREDS_INPUT" ]; then
  echo "Source OAuth credentials file not found: $OAUTH_CREDS_INPUT" >&2
  exit 1
fi

if [ -n "$OAUTH_CREDS_INPUT" ]; then
  OAUTH_CREDS_FILE="$(readlink -f "$OAUTH_CREDS_INPUT")"
else
  OAUTH_CREDS_FILE=""
fi

if [ -n "$PROFILE_HINT" ]; then
  set +e
  EXISTING_PROFILE_ROOT="$(find_profile_root_by_hint "$PROFILE_BASE_DIR" "$PROFILE_HINT")"
  FIND_PROFILE_STATUS=$?
  set -e

  if [ "$FIND_PROFILE_STATUS" -eq 2 ]; then
    echo "Profile hint is ambiguous: $PROFILE_HINT" >&2
    echo "Reset duplicate profiles before reusing this profile hint." >&2
    exit 1
  fi

  if [ "$FIND_PROFILE_STATUS" -ne 0 ]; then
    exit "$FIND_PROFILE_STATUS"
  fi

  if [ -n "$EXISTING_PROFILE_ROOT" ]; then
    PROFILE_ROOT="$(readlink -m "$EXISTING_PROFILE_ROOT")"
    load_stored_oauth_creds_source "$PROFILE_ROOT"

    if [ -n "$OAUTH_CREDS_FILE" ] && [ -n "$STORED_OAUTH_CREDS_FILE" ] && [ "$OAUTH_CREDS_FILE" != "$STORED_OAUTH_CREDS_FILE" ]; then
      echo "Profile \"$PROFILE_HINT\" is already bound to a different oauth_creds.json:" >&2
      echo "  $STORED_OAUTH_CREDS_FILE" >&2
      echo "Use a different profile name or reset the profile first." >&2
      exit 1
    fi
  else
    echo "Profile not found: $PROFILE_HINT" >&2
    echo "Create it first with gemini-auth before running resync." >&2
    exit 1
  fi
else
  if [ -z "$OAUTH_CREDS_FILE" ]; then
    echo "Missing required option: --cred-file" >&2
    usage
  fi

  AUTH_BASENAME="$(basename "$OAUTH_CREDS_FILE")"
  PROFILE_SLUG="$(printf '%s' "$AUTH_BASENAME" | tr '[:upper:]' '[:lower:]' | sed 's/\.[^.]*$//' | tr -cs 'a-z0-9' '-' | sed 's/^-//; s/-$//')"
  PROFILE_HASH="$(printf '%s' "$OAUTH_CREDS_FILE" | sha256sum | cut -c1-12)"
  PROFILE_ROOT="$(readlink -m "$PROFILE_BASE_DIR/${PROFILE_SLUG:-auth}-$PROFILE_HASH")"
fi

PROFILE_NAME="$(basename "$PROFILE_ROOT")"

case "$PROFILE_ROOT" in
  "$PROFILE_BASE_DIR_CANONICAL"/*) ;;
  *)
    echo "Refusing to access a path outside the launcher home: $PROFILE_ROOT" >&2
    exit 1
    ;;
esac

PROFILE_GEMINI_DIR="$PROFILE_ROOT/gemini-home/.gemini"

if [ ! -d "$PROFILE_GEMINI_DIR" ]; then
  echo "Profile not found: $PROFILE_NAME" >&2
  echo "Create it first with gemini-auth before running resync." >&2
  exit 1
fi

sync_profile_home "$BASE_HOME" "$PROFILE_GEMINI_DIR"

echo "Resynced isolated Gemini profile: $PROFILE_NAME" >&2
echo "Source home: $BASE_HOME" >&2
echo "Target home: $PROFILE_GEMINI_DIR" >&2

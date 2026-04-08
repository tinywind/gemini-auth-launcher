#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=./profile-common.sh
source "$SCRIPT_DIR/profile-common.sh"

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
Usage: gemini-auth-reset [--profile <name>] [--cred-file <path>] [--yes]

Delete the isolated Gemini profile for the given source OAuth credentials file.
The next run recreates it by copying ~/.gemini and relinking auth files.

Options:
  --profile <name>      Profile hint used when the profile was created.
  --cred-file <path>    Source OAuth credentials file path. Optional when reusing a named profile.
  --yes                 Delete without confirmation.
  -h, --help            Show this help.

Examples:
  gemini-auth-reset --cred-file ~/gemini-auths/work/oauth_creds.json
  gemini-auth-reset --yes --cred-file ~/gemini-auths/work/oauth_creds.json
  gemini-auth-reset --profile review --yes
EOF
  exit 1
}

PROFILE_HINT="${GEMINI_AUTH_LAUNCHER_PROFILE:-}"
ASSUME_YES=0
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
    --yes)
      ASSUME_YES=1
      shift
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

if [ -n "$OAUTH_CREDS_INPUT" ] && [ ! -f "$OAUTH_CREDS_INPUT" ]; then
  echo "OAuth credentials file not found: $OAUTH_CREDS_INPUT" >&2
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

    if [ -z "$OAUTH_CREDS_FILE" ]; then
      OAUTH_CREDS_FILE="$STORED_OAUTH_CREDS_FILE"
    fi
  else
    if [ -z "$OAUTH_CREDS_FILE" ]; then
      echo "Profile \"$PROFILE_HINT\" does not exist yet." >&2
      echo "Provide --cred-file only after that profile has been created, or create it first with gemini-auth." >&2
      exit 1
    fi

    PROFILE_SLUG="$(sanitize_slug "$PROFILE_HINT")"
    PROFILE_ROOT="$(readlink -m "$PROFILE_BASE_DIR/${PROFILE_SLUG:-profile}")"
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
    echo "Refusing to remove a path outside the launcher home: $PROFILE_ROOT" >&2
    exit 1
    ;;
esac

if [ ! -e "$PROFILE_ROOT" ]; then
  echo "Profile not found: $PROFILE_NAME" >&2
  echo "Nothing to reset." >&2
  exit 0
fi

if [ "$ASSUME_YES" -ne 1 ]; then
  if [ ! -t 0 ]; then
    echo "Refusing to reset without --yes in non-interactive mode." >&2
    exit 1
  fi

  printf 'Delete isolated Gemini profile "%s" and all persisted sessions? [y/N] ' "$PROFILE_NAME" >&2
  read -r confirmation
  case "$confirmation" in
    y|Y|yes|YES)
      ;;
    *)
      echo "Aborted." >&2
      exit 1
      ;;
  esac
fi

rm -rf "$PROFILE_ROOT"

echo "Removed isolated Gemini profile: $PROFILE_NAME" >&2
echo "Removed path: $PROFILE_ROOT" >&2

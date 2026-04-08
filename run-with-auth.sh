#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=./profile-common.sh
source "$SCRIPT_DIR/profile-common.sh"

usage() {
  cat >&2 <<'EOF'
Usage: gemini-auth [options] [--] [gemini args...]

Options:
  --profile <name>          Stable profile hint for the isolated GEMINI_CLI_HOME.
  --cred-file <path>        Source OAuth credentials file path. Linked as oauth_creds.json on use.
  --google-accounts <path>  Optional google_accounts.json path.
  --base-home <path>        Existing ~/.gemini directory used by --link-config and --share-path.
  --link-config             Link settings.json from the base home into the profile.
  --share-path <path>       Link an additional relative path from the base home.
  --print-home              Print the prepared GEMINI_CLI_HOME root and exit.
  -h, --help                Show this help.

Examples:
  gemini-auth --cred-file ~/gemini-auths/work/oauth_creds.json --help
  gemini-auth --cred-file ~/gemini-auths/work/oauth_creds.json -p "Summarize this folder."
  gemini-auth --profile review --cred-file ~/gemini-auths/work/oauth_creds.json -p "Summarize this folder."
  gemini-auth --profile review --resume latest
  gemini-auth --link-config --share-path skills --cred-file ~/gemini-auths/work/oauth_creds.json
EOF
  exit 1
}

ensure_relative_share_path() {
  local relative_path="$1"

  if [[ "$relative_path" = /* ]]; then
    echo "Shared paths must be relative to the base home: $relative_path" >&2
    exit 1
  fi
}

bootstrap_profile_home() {
  local source_home="$1"
  local target_home="$2"

  if [ ! -d "$source_home" ]; then
    return 0
  fi

  if [ -n "$(ls -A "$target_home" 2>/dev/null || true)" ]; then
    return 0
  fi

  cp -a "$source_home"/. "$target_home"/

  rm -f "$target_home/oauth_creds.json" "$target_home/google_accounts.json"
}

ensure_auth_link() {
  local source_path="$1"
  local target_path="$2"

  if [ -e "$target_path" ] && [ ! -L "$target_path" ]; then
    local backup_path
    backup_path="$target_path.backup.$(date +%Y%m%d%H%M%S)"
    mv "$target_path" "$backup_path"
    echo "Backed up existing profile auth file to: $backup_path" >&2
  fi

  ln -sfn "$source_path" "$target_path"
}

ensure_optional_auth_link() {
  local source_path="$1"
  local target_path="$2"

  if [ -z "$source_path" ]; then
    if [ -L "$target_path" ]; then
      rm -f "$target_path"
    fi
    return 0
  fi

  ensure_auth_link "$source_path" "$target_path"
}

ensure_shared_path_link() {
  local base_home="$1"
  local relative_path="$2"
  local source_path
  local target_path

  ensure_relative_share_path "$relative_path"

  source_path="$base_home/$relative_path"
  if [ ! -e "$source_path" ]; then
    echo "Shared path not found in base home, skipping: $relative_path" >&2
    return 0
  fi

  source_path="$(readlink -f "$source_path")"
  case "$source_path" in
    "$base_home"|"$base_home"/*) ;;
    *)
      echo "Shared path resolves outside the base home: $relative_path" >&2
      exit 1
      ;;
  esac

  target_path="$PROFILE_GEMINI_DIR/$relative_path"
  mkdir -p "$(dirname "$target_path")"

  if [ -L "$target_path" ]; then
    ln -sfn "$source_path" "$target_path"
    return 0
  fi

  if [ -e "$target_path" ]; then
    echo "Leaving existing profile path untouched: $target_path" >&2
    return 0
  fi

  ln -s "$source_path" "$target_path"
}

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

  if [ -z "$oauth_creds_path" ]; then
    return 0
  fi

  local sibling_path
  sibling_path="$(dirname "$oauth_creds_path")/google_accounts.json"
  if [ -f "$sibling_path" ]; then
    readlink -f "$sibling_path"
  fi
}

load_stored_auth_sources() {
  local profile_root="$1"
  local stored_line

  STORED_OAUTH_CREDS_FILE=""
  STORED_GOOGLE_ACCOUNTS_FILE=""

  while IFS= read -r stored_line; do
    case "$stored_line" in
      oauthCredsSource=*)
        STORED_OAUTH_CREDS_FILE="${stored_line#oauthCredsSource=}"
        ;;
      googleAccountsSource=*)
        STORED_GOOGLE_ACCOUNTS_FILE="${stored_line#googleAccountsSource=}"
        ;;
    esac
  done < <(load_profile_auth_sources "$profile_root")
}

PROFILE_HINT="${GEMINI_AUTH_LAUNCHER_PROFILE:-}"
BASE_HOME_INPUT="${GEMINI_AUTH_LAUNCHER_BASE_HOME:-$HOME/.gemini}"
LINK_CONFIG=0
PRINT_HOME=0
OAUTH_CREDS_INPUT=""
GOOGLE_ACCOUNTS_INPUT=""
declare -a SHARE_PATHS=()
declare -a GEMINI_ARGS=()

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
    --google-accounts)
      [ "$#" -ge 2 ] || usage
      GOOGLE_ACCOUNTS_INPUT="$2"
      shift 2
      ;;
    --base-home)
      [ "$#" -ge 2 ] || usage
      BASE_HOME_INPUT="$2"
      shift 2
      ;;
    --link-config)
      LINK_CONFIG=1
      shift
      ;;
    --share-path)
      [ "$#" -ge 2 ] || usage
      SHARE_PATHS+=("$2")
      shift 2
      ;;
    --print-home)
      PRINT_HOME=1
      shift
      ;;
    -h|--help)
      usage
      ;;
    --)
      shift
      GEMINI_ARGS+=("$@")
      break
      ;;
    *)
      GEMINI_ARGS+=("$1")
      shift
      ;;
  esac
done

REAL_HOME="${HOME:?HOME is required}"
LAUNCHER_HOME="${GEMINI_AUTH_LAUNCHER_HOME:-$REAL_HOME/.gemini-auth-launcher}"
BOOTSTRAP_HOME="${GEMINI_AUTH_LAUNCHER_BOOTSTRAP_HOME:-$REAL_HOME/.gemini}"
PROFILE_BASE_DIR="$LAUNCHER_HOME/profiles"
EXISTING_PROFILE_ROOT=""
STORED_OAUTH_CREDS_FILE=""
STORED_GOOGLE_ACCOUNTS_FILE=""

if [ -n "$OAUTH_CREDS_INPUT" ] && [ ! -f "$OAUTH_CREDS_INPUT" ]; then
  echo "Source OAuth credentials file not found: $OAUTH_CREDS_INPUT" >&2
  exit 1
fi

if [ -n "$GOOGLE_ACCOUNTS_INPUT" ] && [ ! -f "$GOOGLE_ACCOUNTS_INPUT" ]; then
  echo "google_accounts.json file not found: $GOOGLE_ACCOUNTS_INPUT" >&2
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
    PROFILE_ROOT="$EXISTING_PROFILE_ROOT"
    PROFILE_NAME="$(basename "$PROFILE_ROOT")"
    load_stored_auth_sources "$PROFILE_ROOT"

    if [ -z "$OAUTH_CREDS_FILE" ]; then
      OAUTH_CREDS_FILE="$STORED_OAUTH_CREDS_FILE"
    elif [ -n "$STORED_OAUTH_CREDS_FILE" ] && [ "$OAUTH_CREDS_FILE" != "$STORED_OAUTH_CREDS_FILE" ]; then
      echo "Updating source file linked as oauth_creds.json for named profile \"$PROFILE_HINT\":" >&2
      echo "  $STORED_OAUTH_CREDS_FILE -> $OAUTH_CREDS_FILE" >&2
    fi
  else
    PROFILE_SLUG="$(sanitize_slug "$PROFILE_HINT")"
    PROFILE_NAME="${PROFILE_SLUG:-profile}"
    PROFILE_ROOT="$PROFILE_BASE_DIR/$PROFILE_NAME"
  fi

  if [ -z "$OAUTH_CREDS_FILE" ]; then
    echo "Profile \"$PROFILE_HINT\" does not have a stored source file for oauth_creds.json yet." >&2
    echo "Provide --cred-file on first use." >&2
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
  PROFILE_NAME="${PROFILE_SLUG:-auth}-$PROFILE_HASH"
  PROFILE_ROOT="$PROFILE_BASE_DIR/$PROFILE_NAME"
fi

if [ ! -f "$OAUTH_CREDS_FILE" ]; then
  echo "Stored source OAuth credentials file not found: $OAUTH_CREDS_FILE" >&2
  exit 1
fi

if [ -n "$GOOGLE_ACCOUNTS_INPUT" ]; then
  GOOGLE_ACCOUNTS_FILE="$(readlink -f "$GOOGLE_ACCOUNTS_INPUT")"
elif [ -n "$OAUTH_CREDS_INPUT" ]; then
  GOOGLE_ACCOUNTS_FILE="$(resolve_google_accounts_source "" "$OAUTH_CREDS_FILE")"
else
  GOOGLE_ACCOUNTS_FILE="$STORED_GOOGLE_ACCOUNTS_FILE"
fi

PROFILE_HOME_ROOT="$PROFILE_ROOT/gemini-home"
PROFILE_GEMINI_DIR="$PROFILE_HOME_ROOT/.gemini"
PROFILE_METADATA_FILE="$PROFILE_ROOT/profile.json"
PROFILE_OAUTH_CREDS_FILE="$PROFILE_GEMINI_DIR/oauth_creds.json"
PROFILE_GOOGLE_ACCOUNTS_FILE="$PROFILE_GEMINI_DIR/google_accounts.json"

PROFILE_ALREADY_EXISTS=0
if [ -n "$(ls -A "$PROFILE_GEMINI_DIR" 2>/dev/null || true)" ]; then
  PROFILE_ALREADY_EXISTS=1
fi

mkdir -p "$PROFILE_BASE_DIR" "$PROFILE_ROOT" "$PROFILE_HOME_ROOT" "$PROFILE_GEMINI_DIR"
chmod 700 "$LAUNCHER_HOME" "$PROFILE_BASE_DIR" "$PROFILE_ROOT" "$PROFILE_HOME_ROOT" "$PROFILE_GEMINI_DIR" 2>/dev/null || true

if [ "$PROFILE_ALREADY_EXISTS" -eq 0 ]; then
  bootstrap_profile_home "$BOOTSTRAP_HOME" "$PROFILE_GEMINI_DIR"
fi

ensure_auth_link "$OAUTH_CREDS_FILE" "$PROFILE_OAUTH_CREDS_FILE"
ensure_optional_auth_link "$GOOGLE_ACCOUNTS_FILE" "$PROFILE_GOOGLE_ACCOUNTS_FILE"

BASE_HOME=""
if [ "$LINK_CONFIG" -eq 1 ] || [ "${#SHARE_PATHS[@]}" -gt 0 ]; then
  if [ ! -d "$BASE_HOME_INPUT" ]; then
    echo "Base home not found: $BASE_HOME_INPUT" >&2
    exit 1
  fi
  BASE_HOME="$(readlink -f "$BASE_HOME_INPUT")"
fi

if [ "$LINK_CONFIG" -eq 1 ]; then
  ensure_shared_path_link "$BASE_HOME" "settings.json"
fi

if [ "${#SHARE_PATHS[@]}" -gt 0 ]; then
  for shared_path in "${SHARE_PATHS[@]}"; do
    ensure_shared_path_link "$BASE_HOME" "$shared_path"
  done
fi

SHARED_PATHS_SERIALIZED=""
if [ "${#SHARE_PATHS[@]}" -gt 0 ]; then
  SHARED_PATHS_SERIALIZED="$(printf '%s\n' "${SHARE_PATHS[@]}")"
fi

PROFILE_NAME="$PROFILE_NAME" \
PROFILE_HINT="$PROFILE_HINT" \
OAUTH_CREDS_FILE="$OAUTH_CREDS_FILE" \
GOOGLE_ACCOUNTS_FILE="$GOOGLE_ACCOUNTS_FILE" \
PROFILE_ROOT="$PROFILE_ROOT" \
PROFILE_HOME_ROOT="$PROFILE_HOME_ROOT" \
PROFILE_GEMINI_DIR="$PROFILE_GEMINI_DIR" \
PROFILE_OAUTH_CREDS_FILE="$PROFILE_OAUTH_CREDS_FILE" \
PROFILE_GOOGLE_ACCOUNTS_FILE="$PROFILE_GOOGLE_ACCOUNTS_FILE" \
BASE_HOME="$BASE_HOME" \
BOOTSTRAP_HOME="$BOOTSTRAP_HOME" \
PROFILE_ALREADY_EXISTS="$PROFILE_ALREADY_EXISTS" \
LINK_CONFIG="$LINK_CONFIG" \
SHARED_PATHS_SERIALIZED="$SHARED_PATHS_SERIALIZED" \
python3 - "$PROFILE_METADATA_FILE" <<'PY'
import json
import os
import sys

metadata_path = sys.argv[1]
shared_paths = [line for line in os.environ.get("SHARED_PATHS_SERIALIZED", "").splitlines() if line]

payload = {
    "profileName": os.environ["PROFILE_NAME"],
    "profileHint": os.environ["PROFILE_HINT"],
    "oauthCredsSource": os.environ["OAUTH_CREDS_FILE"],
    "googleAccountsSource": os.environ.get("GOOGLE_ACCOUNTS_FILE") or None,
    "profileRoot": os.environ["PROFILE_ROOT"],
    "geminiCliHome": os.environ["PROFILE_HOME_ROOT"],
    "geminiDir": os.environ["PROFILE_GEMINI_DIR"],
    "oauthCredsLink": os.environ["PROFILE_OAUTH_CREDS_FILE"],
    "googleAccountsLink": os.environ["PROFILE_GOOGLE_ACCOUNTS_FILE"],
    "baseHome": os.environ.get("BASE_HOME") or None,
    "bootstrapHome": os.environ.get("BOOTSTRAP_HOME") or None,
    "bootstrappedOnFirstUse": os.environ["PROFILE_ALREADY_EXISTS"] == "0",
    "linkConfig": os.environ["LINK_CONFIG"] == "1",
    "sharedPaths": shared_paths,
}

with open(metadata_path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2)
    handle.write("\n")
PY
chmod 600 "$PROFILE_METADATA_FILE"

if [ "$PRINT_HOME" -eq 1 ]; then
  printf '%s\n' "$PROFILE_HOME_ROOT"
  exit 0
fi

echo "Using isolated Gemini profile: $PROFILE_NAME" >&2
echo "OAuth symlink (oauth_creds.json): $PROFILE_OAUTH_CREDS_FILE -> $OAUTH_CREDS_FILE" >&2
if [ -n "$GOOGLE_ACCOUNTS_FILE" ]; then
  echo "Accounts symlink: $PROFILE_GOOGLE_ACCOUNTS_FILE -> $GOOGLE_ACCOUNTS_FILE" >&2
fi
echo "GEMINI_CLI_HOME: $PROFILE_HOME_ROOT" >&2

GEMINI_CLI_HOME="$PROFILE_HOME_ROOT" command gemini "${GEMINI_ARGS[@]}"

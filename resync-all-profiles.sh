#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=./sync-common.sh
source "$SCRIPT_DIR/sync-common.sh"

usage() {
  cat >&2 <<'EOF'
Usage: gemini-auth-resync-all [--base-home <path>]

Resync shared Gemini config from the base home into every isolated profile.
Auth links and profile-local session history are preserved.

Options:
  --base-home <path>  Existing ~/.gemini directory used as the sync source.
  -h, --help          Show this help.

Examples:
  gemini-auth-resync-all
  gemini-auth-resync-all --base-home ~/.gemini-team
EOF
  exit 1
}

BASE_HOME_INPUT="${GEMINI_AUTH_LAUNCHER_BASE_HOME:-$HOME/.gemini}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --base-home)
      [ "$#" -ge 2 ] || usage
      BASE_HOME_INPUT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      ;;
  esac
done

REAL_HOME="${HOME:?HOME is required}"
LAUNCHER_HOME="${GEMINI_AUTH_LAUNCHER_HOME:-$REAL_HOME/.gemini-auth-launcher}"
PROFILE_BASE_DIR="$(readlink -m "$LAUNCHER_HOME/profiles")"

if [ ! -d "$BASE_HOME_INPUT" ]; then
  echo "Base home not found: $BASE_HOME_INPUT" >&2
  exit 1
fi

BASE_HOME="$(readlink -f "$BASE_HOME_INPUT")"

if [ ! -d "$PROFILE_BASE_DIR" ]; then
  echo "No isolated profiles found." >&2
  exit 0
fi

PROFILE_COUNT=0
shopt -s nullglob
for profile_root in "$PROFILE_BASE_DIR"/*; do
  profile_gemini_dir="$profile_root/gemini-home/.gemini"
  if [ ! -d "$profile_gemini_dir" ]; then
    continue
  fi

  sync_profile_home "$BASE_HOME" "$profile_gemini_dir"
  PROFILE_COUNT=$((PROFILE_COUNT + 1))
  echo "Resynced isolated Gemini profile: $(basename "$profile_root")" >&2
done
shopt -u nullglob

if [ "$PROFILE_COUNT" -eq 0 ]; then
  echo "No isolated profiles found." >&2
  exit 0
fi

echo "Resynced $PROFILE_COUNT isolated Gemini profile(s) from: $BASE_HOME" >&2

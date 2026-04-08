#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: gemini-auth-reset-all [--yes]

Delete every isolated Gemini auth profile managed by gemini-auth-launcher.
The next profile run recreates its home by copying ~/.gemini and relinking auth files.

Options:
  --yes       Delete without confirmation.
  -h, --help  Show this help.

Examples:
  gemini-auth-reset-all
  gemini-auth-reset-all --yes
EOF
  exit 1
}

ASSUME_YES=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --yes)
      ASSUME_YES=1
      shift
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
LAUNCHER_HOME_CANONICAL="$(readlink -m "$LAUNCHER_HOME")"

case "$PROFILE_BASE_DIR" in
  "$LAUNCHER_HOME_CANONICAL"/*) ;;
  *)
    echo "Refusing to remove a path outside the launcher home: $PROFILE_BASE_DIR" >&2
    exit 1
    ;;
esac

if [ ! -d "$PROFILE_BASE_DIR" ]; then
  echo "No isolated profiles found." >&2
  exit 0
fi

if [ "$ASSUME_YES" -ne 1 ]; then
  if [ ! -t 0 ]; then
    echo "Refusing to reset all profiles without --yes in non-interactive mode." >&2
    exit 1
  fi

  printf 'Delete all isolated Gemini profiles under "%s"? [y/N] ' "$PROFILE_BASE_DIR" >&2
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

rm -rf "$PROFILE_BASE_DIR"
mkdir -p "$PROFILE_BASE_DIR"
chmod 700 "$LAUNCHER_HOME_CANONICAL" "$PROFILE_BASE_DIR" 2>/dev/null || true

echo "Removed all isolated Gemini profiles." >&2
echo "Recreated empty profile directory: $PROFILE_BASE_DIR" >&2

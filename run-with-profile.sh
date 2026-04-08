#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
RUNNER_PATH="$SCRIPT_DIR/run-with-auth.sh"

usage() {
  cat >&2 <<'EOF'
Usage: gemini-auth-profile <profile-name> [launcher options] [--] [gemini args...]

The profile name must be the first positional argument.
On first use of a profile, you must pass --oauth-creds <path>.
This command is a wrapper around:
  gemini-auth --profile <profile-name> ...

Examples:
  gemini-auth-profile work --oauth-creds ~/gemini-auths/work/oauth_creds.json --help
  gemini-auth-profile work -p "Summarize this folder."
  gemini-auth-profile work -- --model gemini-2.5-pro
EOF
  exit 1
}

if [ "$#" -eq 0 ]; then
  usage
fi

case "$1" in
  -h|--help)
    usage
    ;;
esac

PROFILE_NAME="$1"
shift

if [ -z "$PROFILE_NAME" ]; then
  usage
fi

SCAN_REMAINING=1
for argument in "$@"; do
  if [ "$SCAN_REMAINING" -eq 1 ] && [ "$argument" = "--" ]; then
    SCAN_REMAINING=0
    continue
  fi

  if [ "$SCAN_REMAINING" -eq 1 ] && [ "$argument" = "--profile" ]; then
    echo "gemini-auth-profile already consumes the profile name as the first argument." >&2
    echo "Remove the extra --profile option from the remaining launcher arguments." >&2
    exit 1
  fi
done

exec bash "$RUNNER_PATH" --profile "$PROFILE_NAME" "$@"

#!/usr/bin/env bash

sanitize_slug() {
  local value="$1"

  printf '%s' "$value" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//; s/-$//'
}

find_profile_root_by_hint() {
  local profile_base_dir="$1"
  local profile_hint="$2"

  if [ ! -d "$profile_base_dir" ]; then
    return 0
  fi

  python3 - "$profile_base_dir" "$profile_hint" <<'PY'
import json
import os
import sys

base_dir, hint = sys.argv[1:3]
matches = []

for name in sorted(os.listdir(base_dir)):
    profile_root = os.path.join(base_dir, name)
    metadata_path = os.path.join(profile_root, "profile.json")

    if not os.path.isfile(metadata_path):
        continue

    try:
        with open(metadata_path, encoding="utf-8") as handle:
            payload = json.load(handle)
    except (OSError, json.JSONDecodeError):
        continue

    if payload.get("profileHint") == hint:
        matches.append(profile_root)

if len(matches) > 1:
    print(f'Multiple profiles matched hint {hint!r}:', file=sys.stderr)
    for match in matches:
        print(match, file=sys.stderr)
    sys.exit(2)

if matches:
    print(matches[0])
PY
}

load_profile_auth_sources() {
  local profile_root="$1"
  local metadata_path="$profile_root/profile.json"

  if [ ! -f "$metadata_path" ]; then
    return 0
  fi

  python3 - "$metadata_path" <<'PY'
import json
import sys

metadata_path = sys.argv[1]

try:
    with open(metadata_path, encoding="utf-8") as handle:
        payload = json.load(handle)
except (OSError, json.JSONDecodeError):
    sys.exit(0)

for key in ("oauthCredsSource", "googleAccountsSource"):
    value = payload.get(key)
    if value:
        print(f"{key}={value}")
PY
}

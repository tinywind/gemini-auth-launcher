#!/usr/bin/env bash

should_skip_source_sync_path() {
  local entry_name="$1"

  case "$entry_name" in
    oauth_creds.json|google_accounts.json|auth.json|.credentials.json|.credentials.json.*)
      return 0
      ;;
    history|history.jsonl|file-history|session-data|session-env|session_index.jsonl|sessions|memories|plans|tasks|projects|projects.json|state.json|state_*.sqlite)
      return 0
      ;;
    log|logs|logs_*.sqlite|logs_*.sqlite-shm|logs_*.sqlite-wal|debug|tmp|.tmp|cache|downloads|chrome|telemetry|shell_snapshots|shell-snapshots|.playwright-mcp|mcp-needs-auth-cache.json|models_cache.json|stats-cache.json|installation_id|.git|.idea|backups)
      return 0
      ;;
  esac

  return 1
}

sync_profile_home() {
  local source_home="$1"
  local target_home="$2"
  local source_path
  local entry_name
  local target_path
  local -a source_entries=()

  if [ ! -d "$source_home" ]; then
    return 0
  fi

  mkdir -p "$target_home"

  shopt -s dotglob nullglob
  source_entries=("$source_home"/*)
  shopt -u dotglob nullglob

  for source_path in "${source_entries[@]}"; do
    entry_name="$(basename "$source_path")"
    if should_skip_source_sync_path "$entry_name"; then
      continue
    fi

    target_path="$target_home/$entry_name"
    rm -rf "$target_path"
    cp -a "$source_path" "$target_path"
  done
}

#!/usr/bin/env bash
# Shared runtime env path resolution.
# Runtime secrets must live outside the repository checkout.

tt_runtime_slug() {
  local root="${1:-tt-core}"
  printf '%s' "$root" | sed 's#[/\\: ]#_#g'
}

tt_runtime_base_dir() {
  local root="${1:-tt-core}"
  if [[ -n "${TT_RUNTIME_DIR:-}" ]]; then
    printf '%s\n' "$TT_RUNTIME_DIR"
    return 0
  fi

  local config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
  printf '%s/%s\n' "$config_home/tt-production/runtime" "$(tt_runtime_slug "$root")"
}

tt_runtime_core_env_path() {
  local root="${1:-tt-core}"
  printf '%s/core.env\n' "$(tt_runtime_base_dir "$root")"
}

tt_runtime_tunnel_env_path() {
  local root="${1:-tt-core}"
  printf '%s/tunnel.env\n' "$(tt_runtime_base_dir "$root")"
}

tt_legacy_core_env_path() {
  local root="${1:-tt-core}"
  printf '%s/compose/tt-core/.env\n' "$root"
}

tt_legacy_tunnel_env_path() {
  local root="${1:-tt-core}"
  printf '%s/compose/tt-tunnel/.env\n' "$root"
}

tt_resolve_core_env_path() {
  local root="${1:-tt-core}"
  local runtime_path
  runtime_path="$(tt_runtime_core_env_path "$root")"
  if [[ -f "$runtime_path" ]]; then
    printf '%s\n' "$runtime_path"
  else
    tt_legacy_core_env_path "$root"
  fi
}

tt_resolve_tunnel_env_path() {
  local root="${1:-tt-core}"
  local runtime_path
  runtime_path="$(tt_runtime_tunnel_env_path "$root")"
  if [[ -f "$runtime_path" ]]; then
    printf '%s\n' "$runtime_path"
  else
    tt_legacy_tunnel_env_path "$root"
  fi
}

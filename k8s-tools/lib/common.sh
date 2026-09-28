#!/usr/bin/env bash

log_info() {
  printf "%b[INFO]%b %s\n" "$GREEN" "$NC" "$1"
}

log_warn() {
  printf "%b[WARN]%b %s\n" "$YELLOW" "$NC" "$1"
}

log_error() {
  printf "%b[ERROR]%b %s\n" "$RED" "$NC" "$1" >&2
}

log_step() {
  printf "\n%b==>%b %s\n" "$BLUE" "$NC" "$1"
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log_error "Missing required command: $cmd"
    exit 1
  fi
}

is_positive_int() {
  [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

run_cmd() {
  local cmd="$1"
  if [[ "$DRY_RUN" == true ]]; then
    printf "[DRY-RUN] %s\n" "$cmd"
    return 0
  fi
  eval "$cmd"
}

confirm() {
  local prompt="$1"
  if [[ "$AUTO_APPROVE" == true ]]; then
    return 0
  fi

  local reply=""
  read -r -p "$prompt [y/N]: " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

prompt_default() {
  local var_name="$1"
  local prompt="$2"
  local default_value="$3"

  if [[ "$NON_INTERACTIVE" == true ]]; then
    if [[ -z "${!var_name}" ]]; then
      printf -v "$var_name" '%s' "$default_value"
    fi
    return
  fi

  local value=""
  read -r -p "$prompt [$default_value]: " value
  if [[ -z "$value" ]]; then
    printf -v "$var_name" '%s' "$default_value"
  else
    printf -v "$var_name" '%s' "$value"
  fi
}

prompt_required() {
  local var_name="$1"
  local prompt="$2"

  if [[ "$NON_INTERACTIVE" == true ]]; then
    if [[ -z "${!var_name}" ]]; then
      log_error "Missing required option for non-interactive mode: $var_name"
      exit 1
    fi
    return
  fi

  local value=""
  while [[ -z "$value" ]]; do
    read -r -p "$prompt: " value
  done
  printf -v "$var_name" '%s' "$value"
}

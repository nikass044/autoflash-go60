#!/bin/bash

FIRMWARE_DIR="$HOME/Downloads"
LOG="/tmp/flash-uf2.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UF2_FINDER="$SCRIPT_DIR/latest-uf2.py"
MAX_COPY_ATTEMPTS=5
COPY_RETRY_DELAY=0.5

log() {
  echo "$(date): $1" >> "$LOG"
}

is_target_volume() {
  local volume_name="$1"
  case "$volume_name" in
    GO60RHBOOT*|GO60LHBOOT*) return 0 ;;
    *) return 1 ;;
  esac
}

latest_uf2() {
  /usr/bin/python3 "$UF2_FINDER" "$FIRMWARE_DIR"
}

log_latest_uf2_failure() {
  local status="$1"
  if [[ "$status" -eq 2 ]]; then
    log "FAILED: Firmware directory not found: $FIRMWARE_DIR"
  elif [[ "$status" -eq 1 ]]; then
    log "FAILED: No .uf2 files found in $FIRMWARE_DIR"
  elif [[ "$status" -eq 64 ]]; then
    log "FAILED: UF2 helper usage error: $UF2_FINDER"
  else
    log "FAILED: latest_uf2 exited with status $status (dir: $FIRMWARE_DIR helper: $UF2_FINDER)"
  fi
}

volume_exists() {
  local mount_path="$1"
  [[ -d "$mount_path" ]]
}

ensure_mount_writable() {
  local mount_path="$1"
  local test_file

  if ! volume_exists "$mount_path"; then
    log "FAILED: Mount path is not a directory: $mount_path"
    return 1
  fi

  /usr/bin/stat -f "Mount stat -> perms:%Sp owner:%Su:%Sg path:%N" "$mount_path" >> "$LOG" 2>&1
  test_file="$mount_path/.flash-write-test-$$"
  if ! /usr/bin/touch "$test_file" >> "$LOG" 2>&1; then
    log "FAILED: Mount path is not writable (touch test failed): $mount_path"
    return 1
  fi
  /bin/rm -f "$test_file" >> "$LOG" 2>&1
  return 0
}

copy_with_retries() {
  local uf2_path="$1"
  local mount_path="$2"
  local uf2_name="$3"
  local volume_name="$4"
  local dest_path="$mount_path/$uf2_name"
  local attempt=1

  while [[ $attempt -le $MAX_COPY_ATTEMPTS ]]; do
    if ! volume_exists "$mount_path"; then
      log "ABORT: Volume detached before attempt $attempt: $mount_path"
      return 1
    fi

    log "Copy attempt $attempt: cp '$uf2_path' '$dest_path'"
    if /bin/cp -X -f -v "$uf2_path" "$dest_path" >> "$LOG" 2>&1; then
      log "SUCCESS: Copied $uf2_name to $volume_name"
      return 0
    fi
    log "Copy attempt $attempt failed"

    if ! volume_exists "$mount_path"; then
      log "ABORT: Volume detached after failed attempt $attempt: $mount_path"
      return 1
    fi

    /bin/sleep "$COPY_RETRY_DELAY"
    attempt=$((attempt + 1))
  done

  log "FAILED: Could not copy $uf2_path to $dest_path after $MAX_COPY_ATTEMPTS attempts"
  return 1
}

process_volume() {
  local mount_path="$1"
  local volume_name
  local uf2_path
  local uf2_status
  local uf2_name

  volume_name=$(basename "$mount_path")
  log "Volume mounted: $volume_name"

  if ! is_target_volume "$volume_name"; then
    log "Ignored volume (not a target boot volume): $volume_name"
    return 0
  fi

  if [[ ! -f "$UF2_FINDER" ]]; then
    log "FAILED: UF2 helper script not found: $UF2_FINDER"
    return 1
  fi

  uf2_path="$(latest_uf2 2>>"$LOG")"
  uf2_status=$?
  if [[ $uf2_status -ne 0 || -z "$uf2_path" ]]; then
    log_latest_uf2_failure "$uf2_status"
    return 1
  fi

  uf2_name="$(basename "$uf2_path")"
  log "Latest firmware file: $uf2_path"

  if [[ ! -r "$uf2_path" ]]; then
    log "FAILED: UF2 file is not readable: $uf2_path"
    return 1
  fi

  log "Copying $uf2_name to $volume_name..."
  if ! ensure_mount_writable "$mount_path"; then
    return 1
  fi

  if copy_with_retries "$uf2_path" "$mount_path" "$uf2_name" "$volume_name"; then
    return 0
  fi

  return 1
}

main() {
  local mount_path
  local exit_code=0

  for mount_path in "$@"; do
    if ! process_volume "$mount_path"; then
      exit_code=1
    fi
  done

  return $exit_code
}

main "$@"

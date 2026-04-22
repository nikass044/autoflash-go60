#!/bin/bash

FIRMWARE_DIR="$HOME/Downloads"
LOG="/tmp/flash-uf2.log"

log() {
    echo "$(date): $1" >> "$LOG"
}

latest_uf2() {
  /usr/bin/python3 - "$FIRMWARE_DIR" <<'PY'
import os, sys, glob

d = sys.argv[1]
if not os.path.isdir(d):
    print(f"Firmware directory not found: {d}", file=sys.stderr)
    sys.exit(2)

paths = [
    p for p in glob.glob(os.path.join(d, "*"))
    if os.path.isfile(p) and p.lower().endswith(".uf2")
]
if not paths:
    sys.exit(1)

def ts(p):
    st = os.stat(p)
    bt = getattr(st, "st_birthtime", None)
    return bt if bt is not None else st.st_mtime

paths.sort(key=ts, reverse=True)
print(paths[0])
PY
}

for f in "$@"; do
    VOLUME_NAME=$(basename "$f")
    log "Raw argument: '$f'"
    log "Volume mounted: $VOLUME_NAME"
    log "Mount path: $f"

    case "$VOLUME_NAME" in
      GO60RHBOOT*|GO60LHBOOT*)
        UF2_PATH="$(latest_uf2 2>>"$LOG")"
        UF2_STATUS=$?
        if [[ $UF2_STATUS -ne 0 || -z "$UF2_PATH" ]]; then
          if [[ $UF2_STATUS -eq 2 ]]; then
            log "FAILED: Firmware directory not found: $FIRMWARE_DIR"
          elif [[ $UF2_STATUS -eq 1 ]]; then
            log "FAILED: No .uf2 files found in $FIRMWARE_DIR"
          else
            log "FAILED: latest_uf2 exited with status $UF2_STATUS (dir: $FIRMWARE_DIR)"
          fi
          exit 1
        fi

        UF2_NAME="$(basename "$UF2_PATH")"
        log "Selected newest UF2: $UF2_PATH"
        if [[ ! -r "$UF2_PATH" ]]; then
          log "FAILED: UF2 file is not readable: $UF2_PATH"
          continue
        fi

        log "Copying $UF2_NAME to $VOLUME_NAME..."
        if [[ ! -d "$f" ]]; then
          log "FAILED: Mount path is not a directory: $f"
          continue
        fi

        /usr/bin/stat -f "Mount stat -> perms:%Sp owner:%Su:%Sg path:%N" "$f" >> "$LOG" 2>&1
        TEST_FILE="$f/.flash-write-test-$$"
        if ! /usr/bin/touch "$TEST_FILE" >> "$LOG" 2>&1; then
          log "FAILED: Mount path is not writable (touch test failed): $f"
          continue
        fi
        /bin/rm -f "$TEST_FILE" >> "$LOG" 2>&1

        DEST_PATH="$f/$UF2_NAME"
        ATTEMPT=1
        COPIED=0
        while [[ $ATTEMPT -le 5 ]]; do
          log "Copy attempt $ATTEMPT: cp '$UF2_PATH' '$DEST_PATH'"
          if /bin/cp -f -v "$UF2_PATH" "$DEST_PATH" >> "$LOG" 2>&1; then
            SRC_SIZE=$(/usr/bin/stat -f "%z" "$UF2_PATH" 2>/dev/null)
            DST_SIZE=$(/usr/bin/stat -f "%z" "$DEST_PATH" 2>/dev/null)
            log "SUCCESS: Copied $UF2_NAME to $VOLUME_NAME (src=$SRC_SIZE bytes, dst=$DST_SIZE bytes)"
            COPIED=1
            break
          fi
          log "Copy attempt $ATTEMPT failed"
          /bin/sleep 0.5
          ATTEMPT=$((ATTEMPT + 1))
        done

        if [[ $COPIED -eq 1 ]]; then
          osascript -e "display notification \"Copied $UF2_NAME to $VOLUME_NAME\" with title \"Firmware Flashed\""
        else
          log "FAILED: Could not copy $UF2_PATH to $DEST_PATH after 5 attempts"
        fi
        ;;
      *)
        log "Ignored volume (not a target boot volume): $VOLUME_NAME"
        ;;
    esac
done

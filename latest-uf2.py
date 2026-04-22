#!/usr/bin/env python3

import glob
import os
import sys


def timestamp(path: str) -> float:
    st = os.stat(path)
    birth_time = getattr(st, "st_birthtime", None)
    return birth_time if birth_time is not None else st.st_mtime


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: latest-uf2.py <firmware-dir>", file=sys.stderr)
        return 64

    firmware_dir = sys.argv[1]
    if not os.path.isdir(firmware_dir):
        print(f"Firmware directory not found: {firmware_dir}", file=sys.stderr)
        return 2

    paths = [
        p
        for p in glob.glob(os.path.join(firmware_dir, "*"))
        if os.path.isfile(p) and p.lower().endswith(".uf2")
    ]
    if not paths:
        return 1

    paths.sort(key=timestamp, reverse=True)
    print(paths[0])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

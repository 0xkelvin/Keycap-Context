#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Probe a Keycap serial port without requiring third-party packages."""

from __future__ import annotations

import argparse
import array
import fcntl
import os
import select
import termios
import time


def configure(fd: int) -> None:
    attributes = termios.tcgetattr(fd)
    attributes[0] = 0
    attributes[1] = 0
    attributes[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
    attributes[3] = 0
    attributes[4] = termios.B115200
    attributes[5] = termios.B115200
    attributes[6][termios.VMIN] = 0
    attributes[6][termios.VTIME] = 0
    termios.tcsetattr(fd, termios.TCSANOW, attributes)
    termios.tcflush(fd, termios.TCIOFLUSH)
    control_lines = array.array("i", [termios.TIOCM_DTR])
    fcntl.ioctl(fd, termios.TIOCMBIS, control_lines, True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("path")
    parser.add_argument("--seconds", type=float, default=5.0)
    parser.add_argument("--message", default="PING")
    args = parser.parse_args()

    fd = os.open(args.path, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    try:
        configure(fd)
        deadline = time.monotonic() + args.seconds
        next_ping = 0.0
        buffer = bytearray()
        while time.monotonic() < deadline:
            now = time.monotonic()
            if now >= next_ping:
                os.write(fd, f"{args.message}\n".encode())
                next_ping = now + 1.0
            readable, _, _ = select.select([fd], [], [], 0.1)
            if not readable:
                continue
            chunk = os.read(fd, 4096)
            if not chunk:
                continue
            buffer.extend(chunk)
            while b"\n" in buffer:
                line, _, remainder = buffer.partition(b"\n")
                buffer = bytearray(remainder)
                print(line.decode("utf-8", errors="replace"), flush=True)
    finally:
        os.close(fd)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

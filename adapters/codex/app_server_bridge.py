#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Transparent stdio proxy for `codex app-server` with Keycap approvals."""

from __future__ import annotations

import json
import subprocess
import sys
import threading
import time
import uuid
from typing import IO

from app_server_adapter import handle_server_request, lifecycle_update

from pathlib import Path
SHARED_PATH = Path(__file__).resolve().parents[1] / "shared"
sys.path.insert(0, str(SHARED_PATH))
from keycap_client import poll_commands, report_status  # noqa: E402


def _copy_client_input(source: IO[str], destination: IO[str], lock: threading.Lock) -> None:
    for line in source:
        with lock:
            destination.write(line)
            destination.flush()


def _poll_controls(
    destination: IO[str], write_lock: threading.Lock,
    state_lock: threading.Lock, active_turns: dict[str, str],
    control_request_ids: set[str], stop_event: threading.Event,
) -> None:
    while not stop_event.wait(0.5):
        with state_lock:
            turns = dict(active_turns)
        for thread_id, turn_id in turns.items():
            for command in poll_commands(thread_id):
                if command.get("action") not in {"interrupt", "cancel"}:
                    continue
                request_id = f"keycap-control-{uuid.uuid4().hex}"
                payload = {
                    "id": request_id,
                    "method": "turn/interrupt",
                    "params": {"threadId": thread_id, "turnId": turn_id},
                }
                with state_lock:
                    control_request_ids.add(request_id)
                with write_lock:
                    destination.write(json.dumps(payload, separators=(",", ":")) + "\n")
                    destination.flush()


def main() -> int:
    command = sys.argv[1:] or ["codex", "app-server"]
    process = subprocess.Popen(
        command,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=None,
        text=True,
        bufsize=1,
    )
    assert process.stdin and process.stdout
    write_lock = threading.Lock()
    input_thread = threading.Thread(
        target=_copy_client_input,
        args=(sys.stdin, process.stdin, write_lock),
        daemon=True,
    )
    input_thread.start()
    state_lock = threading.Lock()
    active_turns: dict[str, str] = {}
    control_request_ids: set[str] = set()
    stop_event = threading.Event()
    control_thread = threading.Thread(
        target=_poll_controls,
        args=(process.stdin, write_lock, state_lock, active_turns,
              control_request_ids, stop_event),
        daemon=True,
    )
    control_thread.start()

    try:
        for line in process.stdout:
            try:
                message = json.loads(line)
            except json.JSONDecodeError:
                sys.stdout.write(line)
                sys.stdout.flush()
                continue

            with state_lock:
                if str(message.get("id")) in control_request_ids:
                    control_request_ids.discard(str(message.get("id")))
                    continue

            lifecycle = lifecycle_update(message)
            if lifecycle is not None:
                thread_id = lifecycle["session"]
                turn_id = lifecycle.get("turnId")
                with state_lock:
                    if lifecycle["state"] == "working" and turn_id:
                        active_turns[thread_id] = turn_id
                    elif lifecycle["state"] in {"completed", "failed"}:
                        active_turns.pop(thread_id, None)
                report_status(
                    session=thread_id, source="Codex", state=lifecycle["state"],
                    summary=lifecycle["summary"],
                )

            response = handle_server_request(message) if "id" in message else None
            if response is None:
                sys.stdout.write(line)
                sys.stdout.flush()
            else:
                with write_lock:
                    process.stdin.write(json.dumps(response, separators=(",", ":")) + "\n")
                    process.stdin.flush()
    except KeyboardInterrupt:
        process.terminate()
    finally:
        stop_event.set()
        if process.poll() is None:
            process.terminate()
    return process.wait()


if __name__ == "__main__":
    raise SystemExit(main())

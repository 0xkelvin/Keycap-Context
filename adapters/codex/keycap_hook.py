#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Codex PermissionRequest hook bridge for Keycap Context."""

from __future__ import annotations

import json
import os
import pathlib
import sys
import uuid
from typing import Any

SHARED_PATH = pathlib.Path(__file__).resolve().parents[1] / "shared"
sys.path.insert(0, str(SHARED_PATH))
from keycap_client import client_app_bundle_identifier, submit  # noqa: E402


def build_request(payload: dict[str, Any]) -> dict[str, Any]:
    tool_name = str(payload.get("tool_name") or "tool")
    tool_input = payload.get("tool_input")
    description = tool_input.get("description") if isinstance(tool_input, dict) else None
    detail = json.dumps(tool_input, indent=2, ensure_ascii=False) if tool_input else None
    cwd = payload.get("cwd")
    session = str(payload.get("session_id") or "unknown")
    return {
        "id": f"codex-{session}-{uuid.uuid4().hex[:8]}",
        "source": "Codex",
        "session": session,
        "project": os.path.basename(cwd.rstrip(os.sep)) if isinstance(cwd, str) else None,
        "context": (
            f"Zellij pane {os.environ['ZELLIJ_PANE_ID']}"
            if os.environ.get("ZELLIJ_PANE_ID") else None
        ),
        "kind": "permission",
        "title": description or f"Codex wants to use {tool_name}",
        "detail": detail,
        "choices": [
            {
                "id": "allow",
                "label": "Allow",
                "description": "Approve this request.",
            },
            {
                "id": "deny",
                "label": "Deny",
                "description": "Reject this request and continue the turn.",
            },
        ],
        "accentColor": "10A37F",
        "risk": "destructive",
        "clientApp": client_app_bundle_identifier(),
    }


def decision(payload: dict[str, Any]) -> dict[str, Any] | None:
    response = submit(build_request(payload))
    if not response:
        return None
    choice = response.get("choiceId")
    if choice == "allow":
        value: dict[str, Any] = {"behavior": "allow"}
    elif choice == "deny":
        value = {"behavior": "deny", "message": "Denied from Keycap Context"}
    else:
        return None
    return {
        "hookSpecificOutput": {
            "hookEventName": "PermissionRequest",
            "decision": value,
        }
    }


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        return 0
    if payload.get("hook_event_name") != "PermissionRequest":
        return 0
    output = decision(payload)
    if output is not None:
        json.dump(output, sys.stdout, separators=(",", ":"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Gemini CLI BeforeTool/SessionEnd bridge for Keycap Context."""

from __future__ import annotations

import json
import os
import pathlib
import sys
import uuid
from typing import Any

SHARED_PATH = pathlib.Path(__file__).resolve().parents[1] / "shared"
sys.path.insert(0, str(SHARED_PATH))
from keycap_client import (  # noqa: E402
    cancel_session, client_app_bundle_identifier, report_status, submit,
)

DESTRUCTIVE_TOOLS = frozenset({
    "run_shell_command", "write_file", "replace", "delete_file", "move_file",
})


def build_request(payload: dict[str, Any]) -> dict[str, Any]:
    tool_name = str(payload.get("tool_name") or "tool")
    tool_input = payload.get("tool_input")
    cwd = payload.get("cwd")
    session = str(payload.get("session_id") or "unknown")
    request = {
        "id": f"gemini-{session}-{uuid.uuid4().hex[:8]}",
        "source": "Gemini",
        "session": session,
        "project": os.path.basename(cwd.rstrip(os.sep)) if isinstance(cwd, str) else None,
        "kind": "permission",
        "title": f"Gemini wants to use {tool_name}",
        "detail": json.dumps(tool_input, indent=2, ensure_ascii=False) if tool_input else None,
        "choices": [
            {"id": "allow", "label": "Allow", "description": "Run this tool once."},
            {"id": "deny", "label": "Deny", "description": "Reject this tool call."},
        ],
        "accentColor": "4285F4",
        "clientApp": client_app_bundle_identifier(),
    }
    if tool_name in DESTRUCTIVE_TOOLS:
        request["risk"] = "destructive"
    return request


def before_tool(payload: dict[str, Any]) -> dict[str, Any] | None:
    response = submit(build_request(payload))
    if not response or response.get("cancelled") is True:
        return None
    if response.get("choiceId") == "allow":
        return {"decision": "allow", "suppressOutput": True}
    if response.get("choiceId") == "deny":
        return {"decision": "deny", "reason": "Denied from Keycap Context"}
    return None


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        return 0
    event = payload.get("hook_event_name")
    if event == "BeforeTool":
        output = before_tool(payload)
        if output is not None:
            json.dump(output, sys.stdout, separators=(",", ":"))
    elif event == "SessionEnd":
        session = payload.get("session_id")
        if isinstance(session, str):
            cancel_session(session)
            report_status(
                session=session, source="Gemini", state="completed",
                summary="Session ended",
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

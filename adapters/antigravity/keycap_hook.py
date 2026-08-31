#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Antigravity CLI plugin hook bridge for Keycap Context."""

from __future__ import annotations

import json
import os
import pathlib
import sys
import uuid
from typing import Any

SHARED_PATH = pathlib.Path(__file__).resolve().parents[1] / "shared"
sys.path.insert(0, str(SHARED_PATH))
from keycap_client import cancel_session, report_status, submit  # noqa: E402

DESTRUCTIVE_TOOLS = frozenset({
    "run_command", "write_to_file", "replace_file_content",
    "multi_replace_file_content", "manage_task",
})


def session_id(payload: dict[str, Any]) -> str:
    return str(payload.get("conversationId") or "unknown")


def project_name(payload: dict[str, Any]) -> str | None:
    paths = payload.get("workspacePaths")
    if not isinstance(paths, list) or not paths or not isinstance(paths[0], str):
        return None
    return os.path.basename(paths[0].rstrip(os.sep)) or paths[0]


def build_request(payload: dict[str, Any]) -> dict[str, Any] | None:
    tool_call = payload.get("toolCall")
    if not isinstance(tool_call, dict):
        return None
    tool_name = str(tool_call.get("name") or "tool")
    if tool_name == "ask_question":
        return None
    arguments = tool_call.get("args")
    session = session_id(payload)
    request: dict[str, Any] = {
        "id": f"antigravity-{session}-{uuid.uuid4().hex[:8]}",
        "source": "Antigravity",
        "session": session,
        "project": project_name(payload),
        "context": f"Step {payload.get('stepIdx', '?')}",
        "kind": "permission",
        "title": f"Antigravity wants to use {tool_name}",
        "detail": json.dumps(arguments, indent=2, ensure_ascii=False) if arguments else None,
        "choices": [
            {"id": "allow", "label": "Allow", "description": "Run this tool once."},
            {"id": "deny", "label": "Deny", "description": "Reject this tool call."},
        ],
        "accentColor": "7C3AED",
    }
    if tool_name in DESTRUCTIVE_TOOLS:
        request["risk"] = "destructive"
    return request


def pre_tool(payload: dict[str, Any]) -> dict[str, Any]:
    request = build_request(payload)
    if request is None:
        return {"decision": "ask", "reason": "Use Antigravity's native interaction"}
    response = submit(request)
    if not response or response.get("cancelled") is True:
        return {"decision": "ask", "reason": "Keycap returned control to Antigravity"}
    if response.get("choiceId") == "allow":
        return {"decision": "allow", "reason": "Approved with Keycap Context"}
    if response.get("choiceId") == "deny":
        return {"decision": "deny", "reason": "Denied with Keycap Context"}
    return {"decision": "ask", "reason": "Use Antigravity's native approval"}


def report(payload: dict[str, Any], state: str, summary: str) -> None:
    report_status(
        session=session_id(payload), source="Antigravity", state=state,
        project=project_name(payload), summary=summary,
    )


def main() -> int:
    phase = sys.argv[1] if len(sys.argv) > 1 else "pre-tool"
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        return 0

    if phase == "pre-tool":
        json.dump(pre_tool(payload), sys.stdout, separators=(",", ":"))
    elif phase == "pre-invocation":
        report(payload, "working", "Agent is reasoning")
        sys.stdout.write("{}")
    elif phase == "post-tool":
        error = payload.get("error")
        report(payload, "failed" if error else "working", str(error or "Tool completed"))
        sys.stdout.write("{}")
    elif phase == "stop":
        cancel_session(session_id(payload))
        report(payload, "failed" if payload.get("error") else "completed",
               str(payload.get("error") or "Agent completed"))
        sys.stdout.write("{}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

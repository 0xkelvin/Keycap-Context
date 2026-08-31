#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Claude Code hook bridge for the local Keycap Context broker.

Stdout is reserved for Claude hook JSON. Connection failures deliberately emit
nothing so Claude's own terminal prompt remains the safe fallback.
"""

from __future__ import annotations

import json
import os
import pathlib
import sys
import uuid
from typing import Any

SHARED_PATH = pathlib.Path(__file__).resolve().parents[1] / "shared"
sys.path.insert(0, str(SHARED_PATH))
from keycap_client import cancel_session, client_app_bundle_identifier, report_status, submit  # noqa: E402

# These tools own an interactive terminal experience and are handled by a
# dedicated PreToolUse path (or by Claude itself). Sending them through the
# generic PermissionRequest bridge would surface their raw input as a second
# overlay after a user hands the first overlay back to Claude.
INTERACTIVE_TOOLS = frozenset({"AskUserQuestion", "ExitPlanMode"})


def project_name(payload: dict[str, Any]) -> str | None:
    cwd = payload.get("cwd")
    if not isinstance(cwd, str) or not cwd:
        return None
    return os.path.basename(cwd.rstrip(os.sep)) or cwd


def common_request(
    payload: dict[str, Any], *, kind: str, title: str, detail: str | None,
    choices: list[dict[str, Any]], suffix: str
) -> dict[str, Any]:
    session = str(payload.get("session_id") or "unknown")
    return {
        "id": f"claude-{session}-{suffix}-{uuid.uuid4().hex[:8]}",
        "source": "Claude",
        "session": session,
        "project": project_name(payload),
        "context": (
            f"Zellij pane {os.environ['ZELLIJ_PANE_ID']}"
            if os.environ.get("ZELLIJ_PANE_ID") else None
        ),
        "kind": kind,
        "title": title,
        "detail": detail,
        "choices": choices,
        "accentColor": "D97757",
        "clientApp": client_app_bundle_identifier(),
    }


def permission_request(payload: dict[str, Any]) -> dict[str, Any] | None:
    tool_name = str(payload.get("tool_name") or "tool")
    if tool_name in INTERACTIVE_TOOLS:
        return None

    tool_input = payload.get("tool_input")
    detail = json.dumps(tool_input, indent=2, ensure_ascii=False) if tool_input else None
    suggestions = payload.get("permission_suggestions")
    if not isinstance(suggestions, list):
        suggestions = []

    choices: list[dict[str, Any]] = [
        {"id": "allow_once", "label": "Allow once",
         "description": "Allow only this tool call."}
    ]
    # Keep one key for Deny. Claude can provide several persistence scopes;
    # preserve their order and expose as many as the four-key surface can hold.
    included_suggestions = suggestions[:2]
    for index, suggestion in enumerate(included_suggestions):
        destination = suggestion.get("destination") if isinstance(suggestion, dict) else None
        scope = {
            "session": "this session",
            "localSettings": "this project",
            "userSettings": "all projects",
        }.get(destination, "the suggested scope")
        choices.append({
            "id": f"always_{index}",
            "label": f"Always allow for {scope}",
            "description": "Apply Claude's proposed permission rule.",
        })
    choices.append({
        "id": "deny", "label": "Deny",
        "description": "Reject this tool call and continue the session."
    })

    request_payload = common_request(
        payload,
        kind="permission",
        title=f"Claude wants to use {tool_name}",
        detail=detail,
        choices=choices,
        suffix="permission",
    )
    if tool_name in {"Bash", "Write", "Edit", "NotebookEdit"}:
        request_payload["risk"] = "destructive"
    response = submit(request_payload)
    if not response:
        return None

    choice = response.get("choiceId")
    if choice == "allow_once":
        decision: dict[str, Any] = {"behavior": "allow"}
    elif isinstance(choice, str) and choice.startswith("always_"):
        try:
            suggestion = included_suggestions[int(choice.removeprefix("always_"))]
        except (ValueError, IndexError):
            return None
        decision = {"behavior": "allow", "updatedPermissions": [suggestion]}
    elif choice == "deny":
        decision = {"behavior": "deny", "message": "Denied from Keycap Context"}
    else:
        return None

    return {
        "hookSpecificOutput": {
            "hookEventName": "PermissionRequest",
            "decision": decision,
        }
    }


def ask_user_question(payload: dict[str, Any]) -> dict[str, Any] | None:
    tool_input = payload.get("tool_input")
    questions = tool_input.get("questions") if isinstance(tool_input, dict) else None
    if not isinstance(questions, list) or not questions:
        return None
    answers: dict[str, str] = {}
    for question_index, question in enumerate(questions):
        if not isinstance(question, dict):
            return None
        text = question.get("question")
        options = question.get("options")
        if not isinstance(text, str) or not isinstance(options, list) or not (1 <= len(options) <= 16):
            return None

        allows_multiple = question.get("multiSelect") is True

        choices = []
        labels: dict[str, str] = {}
        for option_index, option in enumerate(options):
            if not isinstance(option, dict) or not isinstance(option.get("label"), str):
                return None
            choice_id = f"option_{option_index}"
            labels[choice_id] = option["label"]
            choices.append({
                "id": choice_id,
                "label": option["label"],
                "description": option.get("description"),
            })

        request_payload = common_request(
            payload,
            kind="question",
            title=text,
            detail=None,
            choices=choices,
            suffix=f"question-{question_index}",
        )
        request_payload["allowsMultiple"] = allows_multiple
        request_payload["progress"] = {
            "current": question_index + 1,
            "total": len(questions),
        }
        response = submit(request_payload)
        if not response:
            return None
        if allows_multiple:
            choice_ids = response.get("choiceIds")
            if (not isinstance(choice_ids, list) or not choice_ids or
                    any(choice_id not in labels for choice_id in choice_ids)):
                return None
            answers[text] = ", ".join(labels[choice_id] for choice_id in choice_ids)
        else:
            choice_id = response.get("choiceId")
            if choice_id not in labels:
                return None
            answers[text] = labels[choice_id]

    # Allow the call with the answers filled in. AskUserQuestion honours a
    # pre-filled "answers" field and returns it without prompting, so the tool
    # does not ask again in the terminal.
    #
    # This was briefly changed to deny, on the reading that "allow" runs the
    # tool regardless of updatedInput and would therefore re-prompt. Measured
    # against a live broker, it does not: the tool result arrives in the same
    # second the keypad resolves the overlay, where a terminal prompt shows up
    # as a gap of tens of seconds. Deny works too, but Claude Code renders a
    # blocked call as an error, which reads like a failure to the user.
    updated_input = dict(tool_input)
    updated_input["answers"] = answers
    return {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "allow",
            "updatedInput": updated_input,
        }
    }


def exit_plan_mode(payload: dict[str, Any]) -> dict[str, Any] | None:
    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict):
        tool_input = {}
    request_payload = common_request(
        payload,
        kind="permission",
        title="Claude wants to exit plan mode",
        detail=tool_input.get("plan") if isinstance(tool_input.get("plan"), str) else None,
        choices=[{
            "id": "approve",
            "label": "Approve plan",
            "description": "Approve the plan and let Claude continue.",
        }],
        suffix="exit-plan-mode",
    )
    response = submit(request_payload)
    if not response or response.get("choiceId") != "approve":
        return None
    return {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "allow",
            "updatedInput": tool_input,
        }
    }


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        return 0

    event = payload.get("hook_event_name")
    if event == "PermissionRequest":
        output = permission_request(payload)
    elif event == "PreToolUse" and payload.get("tool_name") == "AskUserQuestion":
        output = ask_user_question(payload)
    elif event == "PreToolUse" and payload.get("tool_name") == "ExitPlanMode":
        output = exit_plan_mode(payload)
    elif event == "Stop":
        session = str(payload.get("session_id") or "unknown")
        cancel_session(session)
        report_status(
            session=session, source="Claude", state="completed",
            project=project_name(payload), summary="Agent completed",
        )
        output = None
    else:
        output = None

    if output is not None:
        json.dump(output, sys.stdout, separators=(",", ":"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

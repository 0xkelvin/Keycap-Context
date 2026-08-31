#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Map Codex App Server approval requests to Keycap Context requests."""

from __future__ import annotations

import json
import pathlib
import sys
import uuid
from typing import Any

SHARED_PATH = pathlib.Path(__file__).resolve().parents[1] / "shared"
sys.path.insert(0, str(SHARED_PATH))
from keycap_client import client_app_bundle_identifier, submit  # noqa: E402

COMMAND_APPROVAL = "item/commandExecution/requestApproval"
FILE_APPROVAL = "item/fileChange/requestApproval"
USER_INPUT = "item/tool/requestUserInput"

DECISION_LABELS = {
    "accept": ("Allow once", "Run this command once."),
    "acceptForSession": ("Allow for session", "Allow matching requests this session."),
    "decline": ("Decline", "Reject this request and continue the turn."),
    "cancel": ("Cancel turn", "Reject this request and interrupt the turn."),
}


def _base_request(
    params: dict[str, Any], *, suffix: str, title: str, detail: str | None,
    choices: list[dict[str, Any]],
) -> dict[str, Any]:
    thread_id = str(params.get("threadId") or "unknown")
    item_id = str(params.get("itemId") or uuid.uuid4().hex)
    request: dict[str, Any] = {
        "id": f"codex-app-{thread_id}-{item_id}-{suffix}",
        "source": "Codex",
        "session": thread_id,
        "context": str(params.get("turnId") or ""),
        "kind": "question" if suffix.startswith("question") else "permission",
        "title": title,
        "detail": detail,
        "choices": choices,
        "accentColor": "10A37F",
        "clientApp": client_app_bundle_identifier(),
    }
    if suffix == "approval":
        request["risk"] = "destructive"
    timeout_ms = params.get("autoResolutionMs")
    if isinstance(timeout_ms, int) and timeout_ms > 0:
        request["timeoutSeconds"] = timeout_ms / 1000
    return request


def _approval_choices(params: dict[str, Any], *, file_change: bool) -> list[dict[str, Any]]:
    available = params.get("availableDecisions")
    decisions = (
        [value for value in available if value in DECISION_LABELS]
        if isinstance(available, list)
        else ["accept", "acceptForSession", "decline", "cancel"]
    )
    if file_change:
        decisions = [value for value in decisions if value in DECISION_LABELS]
    return [
        {"id": decision, "label": DECISION_LABELS[decision][0],
         "description": DECISION_LABELS[decision][1]}
        for decision in decisions[:4]
    ]


def handle_approval(message: dict[str, Any]) -> dict[str, Any] | None:
    method = message.get("method")
    params = message.get("params")
    if method not in {COMMAND_APPROVAL, FILE_APPROVAL} or not isinstance(params, dict):
        return None

    if method == COMMAND_APPROVAL:
        network = params.get("networkApprovalContext")
        if isinstance(network, dict):
            title = f"Codex requests {network.get('protocol', 'network')} access to {network.get('host', 'host')}"
        else:
            title = str(params.get("reason") or "Codex wants to run a command")
        detail_parts = [params.get("command"), params.get("cwd")]
    else:
        title = str(params.get("reason") or "Codex wants to modify files")
        detail_parts = [params.get("grantRoot")]

    choices = _approval_choices(params, file_change=method == FILE_APPROVAL)
    if not choices:
        return None
    request = _base_request(
        params,
        suffix="approval",
        title=title,
        detail="\n\n".join(str(value) for value in detail_parts if value),
        choices=choices,
    )
    broker_response = submit(request)
    choice_id = broker_response.get("choiceId") if broker_response else None
    if choice_id not in {choice["id"] for choice in choices}:
        return None
    return {"id": message.get("id"), "result": {"decision": choice_id}}


def handle_user_input(message: dict[str, Any]) -> dict[str, Any] | None:
    if message.get("method") != USER_INPUT or not isinstance(message.get("params"), dict):
        return None
    params = message["params"]
    questions = params.get("questions")
    if not isinstance(questions, list) or not questions:
        return None

    answers: dict[str, dict[str, list[str]]] = {}
    for index, question in enumerate(questions):
        if not isinstance(question, dict) or question.get("isSecret") is True:
            return None
        options = question.get("options")
        if not isinstance(options, list) or not (1 <= len(options) <= 16):
            return None
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
                "description": str(option.get("description") or ""),
            })
        request = _base_request(
            params,
            suffix=f"question-{index}",
            title=str(question.get("question") or question.get("header") or "Codex question"),
            detail=None,
            choices=choices,
        )
        request["progress"] = {"current": index + 1, "total": len(questions)}
        broker_response = submit(request)
        choice_id = broker_response.get("choiceId") if broker_response else None
        if choice_id not in labels:
            return None
        question_id = str(question.get("id") or index)
        answers[question_id] = {"answers": [labels[choice_id]]}

    return {"id": message.get("id"), "result": {"answers": answers}}


def handle_server_request(message: dict[str, Any]) -> dict[str, Any] | None:
    return handle_approval(message) or handle_user_input(message)


def lifecycle_update(message: dict[str, Any]) -> dict[str, str] | None:
    method = message.get("method")
    params = message.get("params")
    if method not in {"turn/started", "turn/completed", "error"} or not isinstance(params, dict):
        return None
    thread_id = params.get("threadId")
    if not isinstance(thread_id, str):
        return None
    turn = params.get("turn")
    turn_id = turn.get("id") if isinstance(turn, dict) else params.get("turnId")
    if method == "turn/started":
        state, summary = "working", "Turn started"
    elif method == "error":
        state, summary = "failed", str((params.get("error") or {}).get("message", "Turn failed"))
    else:
        status = turn.get("status") if isinstance(turn, dict) else None
        state = "failed" if status == "failed" else "completed"
        summary = f"Turn {status or 'completed'}"
    result = {"session": thread_id, "state": state, "summary": summary}
    if isinstance(turn_id, str):
        result["turnId"] = turn_id
    return result

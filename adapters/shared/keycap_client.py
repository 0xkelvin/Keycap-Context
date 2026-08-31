#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Small dependency-free client for the Keycap Context loopback API."""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.parse
import urllib.request
from typing import Any

BASE_URL = os.environ.get("KEYCAP_BROKER_URL", "http://127.0.0.1:47821")
if BASE_URL.endswith("/v1/requests/wait"):
    BASE_URL = BASE_URL.removesuffix("/v1/requests/wait")
BASE_URL = BASE_URL.rstrip("/")

DEFAULT_TOKEN_PATH = os.path.expanduser(
    "~/Library/Application Support/Keycap Context/token"
)


def broker_token() -> str | None:
    """Read the per-install shared secret the broker requires.

    Loopback binding alone does not identify the caller, so every request is
    authenticated. A missing token yields no header, the broker answers 401,
    and the adapter falls back to the agent's own terminal prompt.
    """
    explicit = os.environ.get("KEYCAP_TOKEN")
    if explicit and explicit.strip():
        return explicit.strip()
    path = os.environ.get("KEYCAP_TOKEN_PATH") or DEFAULT_TOKEN_PATH
    try:
        with open(path, encoding="utf-8") as stream:
            return stream.read().strip() or None
    except OSError:
        return None


def _json_request(
    path: str, *, method: str = "GET", payload: dict[str, Any] | None = None,
    timeout: float = 10,
) -> dict[str, Any] | None:
    data = None if payload is None else json.dumps(payload, separators=(",", ":")).encode()
    headers = {"Content-Type": "application/json"}
    token = broker_token()
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(
        f"{BASE_URL}{path}", data=data, headers=headers, method=method,
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.load(response)
    except (OSError, urllib.error.URLError, json.JSONDecodeError):
        return None


def submit(request_payload: dict[str, Any]) -> dict[str, Any] | None:
    request_payload = dict(request_payload)
    request_payload.setdefault("clientApp", client_app_bundle_identifier())
    return _json_request(
        "/v1/requests/wait", method="POST", payload=request_payload, timeout=3600
    )


def capabilities() -> dict[str, Any] | None:
    return _json_request("/v1/capabilities")


def cancel_request(request_id: str) -> dict[str, Any] | None:
    encoded = urllib.parse.quote(request_id, safe="")
    return _json_request(f"/v1/requests/{encoded}", method="DELETE")


def cancel_session(session: str) -> dict[str, Any] | None:
    return _json_request(
        "/v1/sessions/cancel", method="POST", payload={"session": session}
    )


def report_status(
    *, session: str, source: str, state: str, project: str | None = None,
    context: str | None = None, summary: str | None = None,
    preferred_key: int | None = None,
) -> dict[str, Any] | None:
    return _json_request(
        "/v1/sessions/status",
        method="POST",
        payload={
            "session": session,
            "source": source,
            "state": state,
            "project": project,
            "context": context,
            "summary": summary,
            "clientApp": client_app_bundle_identifier(),
            "preferredKey": preferred_key,
        },
    )


def poll_commands(session: str) -> list[dict[str, Any]]:
    encoded = urllib.parse.quote(session, safe="")
    response = _json_request(f"/v1/sessions/{encoded}/commands", timeout=3)
    return response if isinstance(response, list) else []


def client_app_bundle_identifier() -> str | None:
    explicit = os.environ.get("KEYCAP_CLIENT_APP")
    if explicit:
        return explicit
    term_program = os.environ.get("TERM_PROGRAM", "").lower()
    mappings = {
        "apple_terminal": "com.apple.Terminal",
        "iterm.app": "com.googlecode.iterm2",
        "vscode": "com.microsoft.VSCode",
        "warpterminal": "dev.warp.Warp-Stable",
        "ghostty": "com.mitchellh.ghostty",
    }
    return mappings.get(term_program)

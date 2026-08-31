# SPDX-License-Identifier: Apache-2.0
import importlib.util
import pathlib
import unittest
from unittest.mock import patch

MODULE_PATH = pathlib.Path(__file__).parents[1] / "keycap_hook.py"
SPEC = importlib.util.spec_from_file_location("codex_keycap_hook", MODULE_PATH)
hook = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(hook)


class HookTests(unittest.TestCase):
    def test_request_preserves_tool_input(self):
        payload = {
            "session_id": "thread-1",
            "cwd": "/tmp/project",
            "tool_name": "Bash",
            "tool_input": {"command": "git push", "description": "Push branch"},
        }
        request = hook.build_request(payload)
        self.assertEqual(request["title"], "Push branch")
        self.assertIn("git push", request["detail"])
        self.assertEqual([c["label"] for c in request["choices"]], ["Allow", "Deny"])

    def test_allow(self):
        with patch.object(hook, "submit", return_value={"choiceId": "allow"}):
            output = hook.decision({"tool_name": "Bash"})
        self.assertEqual(
            output["hookSpecificOutput"]["decision"]["behavior"], "allow"
        )

    def test_deny(self):
        with patch.object(hook, "submit", return_value={"choiceId": "deny"}):
            output = hook.decision({"tool_name": "Bash"})
        self.assertEqual(
            output["hookSpecificOutput"]["decision"]["behavior"], "deny"
        )

    def test_cancelled_request_falls_back(self):
        with patch.object(
            hook, "submit", return_value={"requestId": "one", "cancelled": True}
        ):
            self.assertIsNone(hook.decision({"tool_name": "Bash"}))


if __name__ == "__main__":
    unittest.main()

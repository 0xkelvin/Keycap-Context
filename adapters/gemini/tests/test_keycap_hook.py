# SPDX-License-Identifier: Apache-2.0
import importlib.util
import pathlib
import unittest
from unittest.mock import patch

PATH = pathlib.Path(__file__).parents[1] / "keycap_hook.py"
SPEC = importlib.util.spec_from_file_location("gemini_keycap_hook", PATH)
hook = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(hook)


class GeminiHookTests(unittest.TestCase):
    def test_shell_request_is_destructive(self):
        request = hook.build_request({"tool_name": "run_shell_command", "session_id": "s"})
        self.assertEqual(request["source"], "Gemini")
        self.assertEqual(request["risk"], "destructive")

    def test_allow_and_deny(self):
        with patch.object(hook, "submit", return_value={"choiceId": "allow"}):
            self.assertEqual(hook.before_tool({})["decision"], "allow")
        with patch.object(hook, "submit", return_value={"choiceId": "deny"}):
            self.assertEqual(hook.before_tool({})["decision"], "deny")

    def test_dismiss_falls_back(self):
        with patch.object(hook, "submit", return_value={"cancelled": True}):
            self.assertIsNone(hook.before_tool({}))


if __name__ == "__main__":
    unittest.main()

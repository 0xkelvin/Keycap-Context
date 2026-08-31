# SPDX-License-Identifier: Apache-2.0
import importlib.util
import pathlib
import unittest
from unittest import mock

MODULE_PATH = pathlib.Path(__file__).parents[1] / "keycap_hook.py"
SPEC = importlib.util.spec_from_file_location("antigravity_keycap_hook", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(MODULE)


class AntigravityHookTests(unittest.TestCase):
    def payload(self, tool="run_command"):
        return {
            "conversationId": "session-1",
            "workspacePaths": ["/tmp/project"],
            "stepIdx": 2,
            "toolCall": {"name": tool, "args": {"CommandLine": "make test"}},
        }

    def test_builds_destructive_approval(self):
        request = MODULE.build_request(self.payload())
        self.assertEqual(request["source"], "Antigravity")
        self.assertEqual(request["risk"], "destructive")
        self.assertEqual(request["project"], "project")

    @mock.patch.object(MODULE, "submit", return_value={"choiceId": "allow"})
    def test_allow_maps_to_hook_decision(self, _submit):
        self.assertEqual(MODULE.pre_tool(self.payload())["decision"], "allow")

    @mock.patch.object(MODULE, "submit", return_value={"cancelled": True})
    def test_cancel_returns_native_ask(self, _submit):
        self.assertEqual(MODULE.pre_tool(self.payload())["decision"], "ask")

    def test_question_stays_native(self):
        self.assertEqual(MODULE.pre_tool(self.payload("ask_question"))["decision"], "ask")


if __name__ == "__main__":
    unittest.main()

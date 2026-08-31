# SPDX-License-Identifier: Apache-2.0
import importlib.util
import pathlib
import unittest
from unittest.mock import patch

MODULE_PATH = pathlib.Path(__file__).parents[1] / "keycap_hook.py"
SPEC = importlib.util.spec_from_file_location("keycap_hook", MODULE_PATH)
hook = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(hook)


class HookTests(unittest.TestCase):
    def test_permission_does_not_requeue_ask_user_question(self):
        payload = {
            "hook_event_name": "PermissionRequest",
            "tool_name": "AskUserQuestion",
            "tool_input": {"questions": [{"question": "Which style?"}]},
        }

        with patch.object(hook, "submit") as submit:
            output = hook.permission_request(payload)

        self.assertIsNone(output)
        submit.assert_not_called()

    def test_permission_allow_once(self):
        payload = {
            "hook_event_name": "PermissionRequest",
            "session_id": "abc",
            "cwd": "/tmp/project",
            "tool_name": "Bash",
            "tool_input": {"command": "swift test"},
            "permission_suggestions": [],
        }
        with patch.object(hook, "submit", return_value={"choiceId": "allow_once"}):
            output = hook.permission_request(payload)
        self.assertEqual(
            output["hookSpecificOutput"]["decision"]["behavior"], "allow"
        )

    def test_permission_uses_exact_suggestion(self):
        suggestion = {
            "type": "addRules",
            "rules": [{"toolName": "Bash", "ruleContent": "swift test"}],
            "behavior": "allow",
            "destination": "localSettings",
        }
        payload = {
            "session_id": "abc", "tool_name": "Bash", "tool_input": {},
            "permission_suggestions": [suggestion],
        }
        with patch.object(hook, "submit", return_value={"choiceId": "always_0"}):
            output = hook.permission_request(payload)
        self.assertEqual(
            output["hookSpecificOutput"]["decision"]["updatedPermissions"],
            [suggestion],
        )

    def test_question_preserves_labels_and_descriptions(self):
        payload = {
            "session_id": "abc",
            "tool_input": {"questions": [{
                "question": "Which style?",
                "options": [
                    {"label": "Compact", "description": "Less text"},
                    {"label": "Detailed", "description": "More text"},
                ],
                "multiSelect": False,
            }]},
        }
        captured = []

        def submit(request):
            captured.append(request)
            return {"choiceId": "option_1"}

        with patch.object(hook, "submit", side_effect=submit):
            output = hook.ask_user_question(payload)
        self.assertEqual(captured[0]["title"], "Which style?")
        self.assertEqual(captured[0]["choices"][1]["label"], "Detailed")
        self.assertEqual(captured[0]["choices"][1]["description"], "More text")
        # The tool must not run: "allow" would execute AskUserQuestion and ask
        # the same question again in the terminal, discarding the keypad answer.
        self.assertEqual(
            output["hookSpecificOutput"]["permissionDecision"], "deny"
        )
        reason = output["hookSpecificOutput"]["permissionDecisionReason"]
        self.assertIn("Which style?: Detailed", reason)
        self.assertNotIn("updatedInput", output["hookSpecificOutput"])

    def test_multiselect_returns_all_selected_labels(self):
        payload = {"tool_input": {"questions": [{
            "question": "Choose", "options": [{"label": "A"}],
            "multiSelect": True,
        }]}}
        captured = []

        def submit(request):
            captured.append(request)
            return {"choiceId": "option_0", "choiceIds": ["option_0"]}

        with patch.object(hook, "submit", side_effect=submit):
            output = hook.ask_user_question(payload)

        self.assertTrue(captured[0]["allowsMultiple"])
        self.assertEqual(captured[0]["progress"], {"current": 1, "total": 1})
        self.assertIn(
            "Choose: A", output["hookSpecificOutput"]["permissionDecisionReason"]
        )

    def test_answered_question_does_not_let_the_tool_run_again(self):
        """The keypad answer is only useful if AskUserQuestion is not re-run.

        "allow" executes the tool whatever updatedInput says, which asked the
        same question a second time in the terminal and threw the keypad answer
        away. Only "deny" stops execution.
        """
        payload = {"tool_input": {"questions": [
            {"question": "First?", "options": [{"label": "Yes"}]},
            {"question": "Second?", "options": [{"label": "No"}]},
        ]}}
        answers = iter([
            {"choiceId": "option_0", "choiceIds": ["option_0"]},
            {"choiceId": "option_0", "choiceIds": ["option_0"]},
        ])
        with patch.object(hook, "submit", side_effect=lambda _r: next(answers)):
            output = hook.ask_user_question(payload)

        decision = output["hookSpecificOutput"]
        self.assertEqual(decision["permissionDecision"], "deny")
        self.assertIn("First?: Yes", decision["permissionDecisionReason"])
        self.assertIn("Second?: No", decision["permissionDecisionReason"])

    def test_handed_back_question_leaves_it_to_the_terminal(self):
        with patch.object(
            hook, "submit",
            return_value={"requestId": "one", "cancelled": True, "reason": "user"},
        ):
            payload = {"tool_input": {"questions": [
                {"question": "Which?", "options": [{"label": "A"}]}
            ]}}
            self.assertIsNone(hook.ask_user_question(payload))

    def test_cancelled_permission_falls_back(self):
        with patch.object(
            hook, "submit", return_value={"requestId": "one", "cancelled": True}
        ):
            self.assertIsNone(hook.permission_request({"tool_name": "Bash"}))

    def test_cancelled_question_falls_back(self):
        payload = {"tool_input": {"questions": [{
            "question": "Choose",
            "options": [{"label": "A"}],
            "multiSelect": False,
        }]}}
        with patch.object(
            hook, "submit", return_value={"requestId": "one", "cancelled": True}
        ):
            self.assertIsNone(hook.ask_user_question(payload))

    def test_exit_plan_mode_approval_preserves_input(self):
        payload = {
            "tool_name": "ExitPlanMode",
            "tool_input": {"plan": "1. Ship it", "allowedPrompts": []},
        }
        with patch.object(hook, "submit", return_value={"choiceId": "approve"}):
            output = hook.exit_plan_mode(payload)

        self.assertEqual(
            output["hookSpecificOutput"]["updatedInput"], payload["tool_input"]
        )


if __name__ == "__main__":
    unittest.main()

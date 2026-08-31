# SPDX-License-Identifier: Apache-2.0
import importlib.util
import pathlib
import unittest
from unittest.mock import patch

MODULE_PATH = pathlib.Path(__file__).parents[1] / "app_server_adapter.py"
SPEC = importlib.util.spec_from_file_location("app_server_adapter", MODULE_PATH)
adapter = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(adapter)


class AppServerAdapterTests(unittest.TestCase):
    def test_command_approval_preserves_scope_decisions(self):
        message = {
            "id": 7,
            "method": adapter.COMMAND_APPROVAL,
            "params": {
                "threadId": "thread-1",
                "turnId": "turn-1",
                "itemId": "item-1",
                "command": "git push",
                "cwd": "/tmp/project",
            },
        }
        captured = []

        def submit(request):
            captured.append(request)
            return {"choiceId": "acceptForSession"}

        with patch.object(adapter, "submit", side_effect=submit):
            response = adapter.handle_server_request(message)

        self.assertEqual(response, {"id": 7, "result": {"decision": "acceptForSession"}})
        self.assertEqual(captured[0]["session"], "thread-1")
        self.assertEqual(len(captured[0]["choices"]), 4)

    def test_cancellation_forwards_request_to_parent_client(self):
        message = {
            "id": 8,
            "method": adapter.FILE_APPROVAL,
            "params": {"threadId": "t", "turnId": "u", "itemId": "i"},
        }
        with patch.object(adapter, "submit", return_value={"cancelled": True}):
            self.assertIsNone(adapter.handle_server_request(message))

    def test_request_user_input_maps_answers(self):
        message = {
            "id": 9,
            "method": adapter.USER_INPUT,
            "params": {
                "threadId": "t", "turnId": "u", "itemId": "i",
                "autoResolutionMs": 60000,
                "questions": [{
                    "id": "style", "header": "Style", "question": "Which style?",
                    "options": [
                        {"label": "Compact", "description": "Short"},
                        {"label": "Detailed", "description": "Long"},
                    ],
                }],
            },
        }
        with patch.object(adapter, "submit", return_value={"choiceId": "option_1"}):
            response = adapter.handle_server_request(message)

        self.assertEqual(
            response,
            {"id": 9, "result": {"answers": {"style": {"answers": ["Detailed"]}}}},
        )

    def test_secret_or_freeform_questions_fall_back(self):
        base = {
            "id": 10, "method": adapter.USER_INPUT,
            "params": {
                "threadId": "t", "turnId": "u", "itemId": "i",
                "questions": [{"id": "secret", "question": "Token?", "isSecret": True}],
            },
        }
        with patch.object(adapter, "submit") as submit:
            self.assertIsNone(adapter.handle_server_request(base))
        submit.assert_not_called()

    def test_turn_lifecycle_maps_to_agent_status(self):
        started = adapter.lifecycle_update({
            "method": "turn/started",
            "params": {"threadId": "thread-1", "turn": {"id": "turn-1"}},
        })
        completed = adapter.lifecycle_update({
            "method": "turn/completed",
            "params": {
                "threadId": "thread-1",
                "turn": {"id": "turn-1", "status": "failed"},
            },
        })
        self.assertEqual(started["state"], "working")
        self.assertEqual(started["turnId"], "turn-1")
        self.assertEqual(completed["state"], "failed")


if __name__ == "__main__":
    unittest.main()

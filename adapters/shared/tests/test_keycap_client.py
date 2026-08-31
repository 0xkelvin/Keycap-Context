# SPDX-License-Identifier: Apache-2.0
import importlib.util
import pathlib
import tempfile
import unittest
from unittest.mock import patch

MODULE_PATH = pathlib.Path(__file__).parents[1] / "keycap_client.py"


def load_client(environment):
    with patch.dict("os.environ", environment, clear=True):
        spec = importlib.util.spec_from_file_location("keycap_client", MODULE_PATH)
        module = importlib.util.module_from_spec(spec)
        assert spec.loader
        spec.loader.exec_module(module)
        return module


class TokenTests(unittest.TestCase):
    def test_environment_token_wins(self):
        client = load_client({"KEYCAP_TOKEN": "  from-env  "})
        with patch.dict("os.environ", {"KEYCAP_TOKEN": "  from-env  "}, clear=True):
            self.assertEqual(client.broker_token(), "from-env")

    def test_reads_token_file(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "token"
            path.write_text("from-file\n", encoding="utf-8")
            client = load_client({"KEYCAP_TOKEN_PATH": str(path)})
            with patch.dict("os.environ", {"KEYCAP_TOKEN_PATH": str(path)}, clear=True):
                self.assertEqual(client.broker_token(), "from-file")

    def test_missing_token_is_not_fatal(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "absent"
            environment = {"KEYCAP_TOKEN_PATH": str(path)}
            client = load_client(environment)
            with patch.dict("os.environ", environment, clear=True):
                self.assertIsNone(client.broker_token())

    def test_requests_carry_the_bearer_token(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "token"
            path.write_text("s3cret", encoding="utf-8")
            environment = {"KEYCAP_TOKEN_PATH": str(path)}
            client = load_client(environment)

            captured = {}

            class Response:
                def __enter__(self):
                    return self

                def __exit__(self, *args):
                    return False

                def read(self):
                    return b"{}"

            def fake_urlopen(request, timeout=None):
                captured["headers"] = request.headers
                captured["url"] = request.full_url
                return Response()

            with patch.dict("os.environ", environment, clear=True), \
                    patch.object(client.urllib.request, "urlopen", fake_urlopen), \
                    patch.object(client.json, "load", lambda stream: {}):
                client.capabilities()

            self.assertEqual(captured["headers"].get("Authorization"), "Bearer s3cret")

    def test_requests_omit_the_header_when_no_token_exists(self):
        with tempfile.TemporaryDirectory() as directory:
            environment = {"KEYCAP_TOKEN_PATH": str(pathlib.Path(directory) / "absent")}
            client = load_client(environment)
            captured = {}

            class Response:
                def __enter__(self):
                    return self

                def __exit__(self, *args):
                    return False

            def fake_urlopen(request, timeout=None):
                captured["headers"] = request.headers
                return Response()

            with patch.dict("os.environ", environment, clear=True), \
                    patch.object(client.urllib.request, "urlopen", fake_urlopen), \
                    patch.object(client.json, "load", lambda stream: {}):
                client.capabilities()

            self.assertNotIn("Authorization", captured["headers"])


if __name__ == "__main__":
    unittest.main()

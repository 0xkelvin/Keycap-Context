#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_root=$(dirname "$script_dir")
install_root=${KEYCAP_INSTALL_ROOT:-"$HOME/Library/Application Support/Keycap Context"}
launch_agent=${KEYCAP_LAUNCH_AGENT_PATH:-"$HOME/Library/LaunchAgents/ai.keycap.context.plist"}

case "$install_root" in
  ""|"/"|"$HOME"|"$HOME/")
    echo "Refusing unsafe KEYCAP_INSTALL_ROOT: $install_root" >&2
    exit 2
    ;;
esac

swift build -c release --package-path "$project_root/host/macos"

mkdir -p "$install_root/bin" "$install_root/adapters" "$(dirname "$launch_agent")"
cp "$project_root/host/macos/.build/release/keycap-host" "$install_root/bin/keycap-host"
for adapter in claude codex shared gemini generic opencode antigravity; do
  target="$install_root/adapters/$adapter"
  rm -rf "$target"
  cp -R "$project_root/adapters/$adapter" "$target"
done
# Source checkouts may contain ignored test caches. They are not runtime
# dependencies and should never be shipped in a user installation.
find "$install_root/adapters" -type d \( -name __pycache__ -o -name tests \) \
  -prune -exec rm -rf {} +

python3 - "$install_root" <<'PY'
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
for relative in (
    "adapters/claude/settings.fragment.json",
    "adapters/codex/hooks.fragment.json",
    "adapters/gemini/settings.fragment.json",
    "adapters/antigravity/plugin/hooks.json",
):
    path = root / relative
    path.write_text(path.read_text().replace("/ABSOLUTE/PATH/TO", str(root)))
PY

antigravity_plugin_root=${KEYCAP_ANTIGRAVITY_PLUGIN_ROOT:-"$HOME/.gemini/antigravity-cli/plugins"}
antigravity_hooks=${KEYCAP_ANTIGRAVITY_HOOKS_PATH:-"$HOME/.gemini/config/hooks.json"}
mkdir -p "$antigravity_plugin_root"
mkdir -p "$antigravity_plugin_root/keycap-context"
cp "$install_root/adapters/antigravity/plugin/plugin.json" \
  "$antigravity_plugin_root/keycap-context/plugin.json"
cp "$install_root/adapters/antigravity/plugin/hooks.json" \
  "$antigravity_plugin_root/keycap-context/hooks.json"
if command -v agy >/dev/null 2>&1; then
  if ! agy plugin install "$install_root/adapters/antigravity/plugin"; then
    echo "Warning: Antigravity plugin registration failed; run agy plugin install manually." >&2
  fi
fi

# Antigravity CLI currently discovers global hooks before it finishes loading
# authenticated plugins. Register our named hook explicitly as well, preserving
# every unrelated hook already present in the user's configuration.
python3 - "$install_root/adapters/antigravity/plugin/hooks.json" "$antigravity_hooks" <<'PY'
import json
import os
import pathlib
import sys
import tempfile

source = pathlib.Path(sys.argv[1])
destination = pathlib.Path(sys.argv[2])
fragment = json.loads(source.read_text())

if destination.exists():
    config = json.loads(destination.read_text())
    if not isinstance(config, dict):
        raise ValueError(f"Expected a JSON object in {destination}")
else:
    config = {}

config["keycap-context"] = fragment["keycap-context"]
destination.parent.mkdir(parents=True, exist_ok=True)
descriptor, temporary = tempfile.mkstemp(
    dir=destination.parent,
    prefix=f".{destination.name}.",
    suffix=".tmp",
)
try:
    with os.fdopen(descriptor, "w") as stream:
        json.dump(config, stream, indent=2)
        stream.write("\n")
    os.replace(temporary, destination)
finally:
    if os.path.exists(temporary):
        os.unlink(temporary)
PY

python3 - "$launch_agent" "$install_root/bin/keycap-host" <<'PY'
import pathlib
import plistlib
import sys

path = pathlib.Path(sys.argv[1])
executable = sys.argv[2]
payload = {
    "Label": "ai.keycap.context",
    "ProgramArguments": [executable],
    "RunAtLoad": True,
    "KeepAlive": True,
    "StandardOutPath": "/tmp/keycap-context.log",
    "StandardErrorPath": "/tmp/keycap-context.error.log",
}
with path.open("wb") as stream:
    plistlib.dump(payload, stream)
PY

launchctl bootout "gui/$(id -u)" "$launch_agent" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$launch_agent"

echo "Installed Keycap Context in: $install_root"
echo "Configured adapters are under: $install_root/adapters"
echo "Antigravity plugin staged at: $antigravity_plugin_root/keycap-context"
echo "Antigravity hooks registered in: $antigravity_hooks"
echo "Logs: /tmp/keycap-context.log and /tmp/keycap-context.error.log"

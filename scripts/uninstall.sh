#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
set -eu

install_root=${KEYCAP_INSTALL_ROOT:-"$HOME/Library/Application Support/Keycap Context"}
launch_agent=${KEYCAP_LAUNCH_AGENT_PATH:-"$HOME/Library/LaunchAgents/ai.keycap.context.plist"}

case "$install_root" in
  ""|"/"|"$HOME"|"$HOME/")
    echo "Refusing unsafe KEYCAP_INSTALL_ROOT: $install_root" >&2
    exit 2
    ;;
esac

launchctl bootout "gui/$(id -u)" "$launch_agent" 2>/dev/null || true
rm -f "$launch_agent"
rm -rf "$install_root"

echo "Removed Keycap Context host and launch agent."
echo "Agent hook/plugin entries are left in place for manual review and removal."

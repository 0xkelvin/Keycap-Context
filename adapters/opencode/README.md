# OpenCode adapter (experimental)

Install `keycap-plugin.ts` as a local OpenCode v2 plugin and add the matching
`@opencode-ai/plugin` beta dependency. It intercepts permission evaluation while
preserving OpenCode's native behavior on broker failure or overlay dismissal.
The v2 plugin API is beta, so pin the plugin package version to your OpenCode
release.

// SPDX-License-Identifier: Apache-2.0
// Experimental: OpenCode's v2 plugin API is currently beta.
import { Plugin } from "@opencode-ai/plugin/v2"
import { readFileSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"

const broker = process.env.KEYCAP_BROKER_URL ?? "http://127.0.0.1:47821"

// The broker authenticates every caller: loopback binding alone does not
// distinguish an adapter from any other local process or from a web page.
function brokerToken(): string | undefined {
  const explicit = process.env.KEYCAP_TOKEN?.trim()
  if (explicit) return explicit
  const path = process.env.KEYCAP_TOKEN_PATH ??
    join(homedir(), "Library", "Application Support", "Keycap Context", "token")
  try {
    return readFileSync(path, "utf8").trim() || undefined
  } catch {
    return undefined
  }
}

export default Plugin.define({
  id: "keycap.context",
  setup: async (ctx) => {
    await ctx.permission.hook("evaluate", async (event) => {
      if (event.effect === "deny" || event.action === "read") return
      const request = {
        id: `opencode-${event.sessionID}-${crypto.randomUUID()}`,
        source: "OpenCode",
        session: event.sessionID,
        kind: "permission",
        title: `OpenCode requests ${event.action}`,
        detail: event.resources.join("\n"),
        choices: [
          { id: "allow", label: "Allow", description: "Allow this action once." },
          { id: "deny", label: "Deny", description: "Reject this action." },
        ],
        risk: ["edit", "bash", "external_directory"].includes(event.action)
          ? "destructive" : "standard",
        accentColor: "6C5CE7",
      }
      try {
        const token = brokerToken()
        const response = await fetch(`${broker}/v1/requests/wait`, {
          method: "POST",
          headers: {
            "content-type": "application/json",
            ...(token ? { authorization: `Bearer ${token}` } : {}),
          },
          body: JSON.stringify(request),
        })
        if (!response.ok) return
        const result = await response.json() as { choiceId?: string; cancelled?: boolean }
        if (result.cancelled) return
        if (result.choiceId === "allow") event.effect = "allow"
        if (result.choiceId === "deny") {
          event.effect = "deny"
          event.message = "Denied from Keycap Context"
        }
      } catch {
        // Preserve OpenCode's native permission behavior.
      }
    })
  },
})

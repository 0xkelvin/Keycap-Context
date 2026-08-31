# Gemini CLI adapter

Merge `settings.fragment.json` into Gemini CLI's `settings.json`, replacing the
absolute path first. The adapter uses the documented `BeforeTool` hook and
returns no decision when the broker is unavailable or the overlay is dismissed,
so Gemini's native confirmation remains the fallback. `SessionEnd` clears any
requests left by the session.

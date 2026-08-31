# API stability

The loopback broker API is versioned under `/v1`. Additive JSON fields are
allowed within v1; existing fields, response meanings, and HTTP lifecycle
semantics are stable. Breaking changes require a new path such as `/v2`.

Device protocol major versions are announced by `HELLO`. The host supports
majors 1 and 2 and must reject unknown majors. New optional commands may be
added to protocol 2, but existing command grammar and gesture meanings remain
stable.

Settings use a `schemaVersion`. Unknown or malformed settings fall back to safe
defaults, while the previous valid file is retained as `settings.json.previous`.
Adapters must preserve the native agent UI whenever the broker is unavailable,
returns cancellation, or rejects a request.

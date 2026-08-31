# Generic adapter

Pipe a v1 `AgentRequest` JSON object to `stdin_adapter.py`. A selected response
or cancellation is emitted as one JSON object. Exit code 1 means the local
broker was unavailable; exit code 2 means the input was not valid JSON.

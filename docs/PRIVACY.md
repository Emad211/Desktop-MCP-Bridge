# Privacy

Desktop MCP Bridge is self-hosted. It does not include analytics, telemetry, advertising, or an
OpenAI API client. Operations and their bounded results pass between the user's chosen client and the
user-controlled bridge endpoint. Local audit records are stored on the same computer by default.

The operator is responsible for securing the HTTPS endpoint, bearer token, Windows account, tunnel,
and any data sent through a private GPT Action. Do not publish a GPT backed by this bridge unless the
endpoint is designed for multiple users with per-user authorization and isolation.

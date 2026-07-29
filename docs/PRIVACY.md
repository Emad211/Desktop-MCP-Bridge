# Privacy

Desktop MCP Bridge is self-hosted and contains no analytics, advertising, telemetry, or OpenAI API
client. Local operations execute on the operator's computer. Audit logs, browser profile, command job
output, idempotency cache, OCR data, and temporary artifacts are stored locally by default.

When the bridge is used through a private Custom GPT Action, request arguments and returned data travel
through the user's chosen ChatGPT experience and HTTPS tunnel. They are therefore also subject to the
user's ChatGPT account and workspace data controls. The bridge cannot change those platform controls.

The managed Playwright browser uses a dedicated profile. It does not automatically inherit the normal
Chrome/Edge profile or password manager. If the operator signs into websites inside the managed
browser, those sessions remain in the local bridge browser-profile directory until removed.

Screenshot and browser artifacts are stored locally with signed short-lived URLs. Public responses do
not expose their local paths. Expired artifacts are cleaned automatically during bridge activity.

The operator is responsible for securing the Windows account, private GPT, tunnel account, HTTPS
hostname, bearer key, DPAPI key file, and any content sent through Actions. Do not publish a GPT backed
by this bridge unless a separate multi-user authorization and isolation layer has been designed.

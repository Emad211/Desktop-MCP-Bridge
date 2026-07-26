# Threat model

Desktop MCP Bridge intentionally exposes powerful control of a user-owned Windows session. The
primary security boundary is the Windows account running the process, followed by the configured
access profile and the authentication layer in front of the Action Gateway.

## Protected assets

- user files and application data;
- authenticated browser and desktop sessions;
- administrator capabilities;
- the Action API bearer token;
- audit logs and kill-switch state.

## Main threats and controls

| Threat | Control |
|---|---|
| Public internet discovers the gateway | Bind to localhost; place an authenticated TLS tunnel/reverse proxy in front; use a high-entropy bearer token |
| Prompt injection causes unintended action | Platform confirmation for consequential GPT Actions; explicit operation separation; audit every operation |
| Path traversal in constrained profiles | Resolve canonical paths before checking allowed roots |
| Long command exceeds Action timeout | Detached command jobs with polling and cancellation |
| Agent becomes uncontrollable | Local STOP-file kill switch checked before mutating operations |
| Secret leakage through logs | Redaction of common secret fields and bounded outputs |
| Silent or hidden changes | Append-only JSONL audit and no stealth/persistence features |
| Full mode activated accidentally | Exact confirmation phrase plus explicit profile selection |

## Non-goals

The project does not provide credential dumping, anti-malware bypass, hidden persistence, keylogging,
or mechanisms to conceal actions from the machine owner. Full access means broad legitimate OS
administration and automation, not bypassing ownership or security boundaries.

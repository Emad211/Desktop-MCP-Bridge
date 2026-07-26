# Security policy

Desktop MCP Bridge is a remote-administration surface for a user-owned Windows session. Treat its
HTTPS endpoint and bearer key with the same care as a remote desktop credential.

## Required deployment controls

- Keep the Python MCP and Action services bound to `127.0.0.1`.
- Expose the Action Gateway only through HTTPS; never forward port 8766 from a router.
- Use a unique high-entropy bearer key and rotate it if it is copied into logs, source control, or an
  untrusted chat.
- Keep the Custom GPT private.
- Use the `safe` or `developer` profile unless Full access is genuinely required.
- Prefer a separate Windows account or VM for unattended autonomous work.

## Built-in controls

- Full mode requires an exact confirmation phrase in addition to profile selection.
- Guarded mode requires an operation-specific confirmation for high-risk actions.
- Action writes require idempotency IDs, persisted locally, to prevent duplicate execution on retry.
- Mutating operations consult a local STOP-file kill switch before execution.
- Audit records are append-only JSONL and redact common secret fields and command-line patterns.
- Screenshot/browser artifacts use signed, short-lived URLs and do not reveal local filesystem paths.
- The Action key can be stored with Windows DPAPI for the current user.
- The managed browser uses a separate profile rather than silently attaching to the normal Chrome
  password store.
- PyAutoGUI's upper-left-corner emergency fail-safe remains enabled.

## Explicit non-goals

The project does not implement credential dumping, keylogging, endpoint-protection bypass, stealth,
hidden persistence, exploit delivery, or mechanisms intended to conceal actions from the machine
owner. Full access means broad legitimate automation within the permissions of the Windows session;
it does not defeat Windows ACLs, UAC, account isolation, or security software.

## Vulnerability reporting

Report vulnerabilities privately through GitHub Security Advisories for this repository. Never post
live endpoint URLs, keys, browser artifacts, audit logs, screenshots, or sensitive desktop data in a
public issue.

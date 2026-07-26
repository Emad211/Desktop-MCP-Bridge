# Threat model

Desktop MCP Bridge intentionally exposes powerful control over a user-owned Windows session. The
primary boundary is the Windows account running the process, followed by the selected access profile,
Action authentication, tunnel security, local approval policy, and kill switch.

## Protected assets

- files, applications, registry, services, and network configuration;
- authenticated desktop and managed-browser sessions;
- administrator privileges;
- bearer and artifact-signing keys;
- short-lived screenshots and downloaded files;
- audit, job, idempotency, and kill-switch state.

## Main threats and controls

| Threat | Control |
|---|---|
| Gateway is discovered from the internet | Localhost binding, HTTPS tunnel/reverse proxy, high-entropy Bearer authentication |
| Bearer key is stored in plaintext | DPAPI-encrypted per-user key file; no key in repository/config examples |
| Action retry executes a destructive operation twice | Required `request_id`, payload hashing, persistent completed-result cache |
| Prompt injection requests an unintended high-risk operation | Consequential Action endpoint, Guarded confirmations, structured operation allow-list, visible audit trail |
| Agent becomes uncontrollable | Local STOP-file kill switch, process/tunnel stop scripts, PyAutoGUI fail-safe |
| Path traversal escapes a constrained workspace | Canonical path resolution before allowed-root checks |
| Full mode activates accidentally | Explicit Full profile plus exact second confirmation phrase |
| A screenshot URL permanently exposes a file | HMAC-signed unguessable token, short TTL, automatic cleanup, no local path in response |
| Browser automation leaks normal browser credentials | Dedicated Playwright persistent profile rather than attaching to the default Chrome profile |
| Long task exceeds the GPT Action deadline | Detached jobs, persistent output files, polling, cancellation and process-tree termination |
| Secrets leak through audit output | Recursive field/command redaction and bounded results |
| Public health endpoint leaks privilege state | Public health contains only service/version; detailed status requires Bearer authentication |
| Hidden persistence survives user intent | Only an explicit visible Scheduled Task; documented uninstall/stop procedures |
| Tunnel or gateway remains running unexpectedly | State files, status scripts, PID-based stop scripts and local logs |

## Residual risks

- A private GPT Action can still be affected by malicious instructions present in web pages, documents,
  emails, terminals, or application content. The user remains the final authority for consequential
  actions.
- Autonomous Full mode deliberately grants broad power. Compromise of the private GPT, endpoint,
  tunnel account, bearer key, or Windows account can lead to broad impact.
- Signed artifacts are bearer URLs during their short lifetime; anyone receiving a valid URL can read
  that artifact until expiration.
- Audit logs improve accountability but are stored under the same Windows account and are not a
  tamper-proof external ledger.

## Non-goals

No credential dumping, anti-malware bypass, hidden persistence, keylogging, stealth, exploit tooling,
or concealment features are provided.

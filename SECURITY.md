# Security policy

Do not expose the local MCP or Action Gateway directly to the public internet. Use localhost binding,
a TLS tunnel or authenticated reverse proxy, and a unique high-entropy bearer token. Rotate the token
immediately if it is logged, committed, or shared.

Report vulnerabilities privately through GitHub Security Advisories for this repository. Do not place
live endpoint URLs, API keys, audit logs, or sensitive desktop data in public issues.

Full mode is intentionally powerful. It must be explicitly enabled and should run in an isolated
Windows account or VM when practical. The local kill switch can stop all mutating operations without
needing the remote client.

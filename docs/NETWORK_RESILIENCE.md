# Network resilience with V2Ray on Windows

Desktop MCP Bridge v1.1 supports three common V2Ray layouts:

1. **VPN/TUN mode** — Windows traffic is routed by the V2Ray virtual adapter. Direct probes normally
   succeed, so the tunnel is launched with no explicit proxy environment.
2. **System HTTP proxy mode** — the bridge reads WinINET, WinHTTP, environment proxy variables, and
   PAC metadata.
3. **Local SOCKS/HTTP ports** — the detector checks configured proxies and common local V2Ray ports,
   then validates them with a real HTTPS request before use.

Run:

```powershell
.\scripts\get-network-profile.ps1
```

## Stable endpoint recommendation

A Custom GPT stores one HTTPS server URL in its Action schema. For that reason, use a provider whose
URL stays stable across reconnects:

- **ngrok development domain** — recommended for this deployment. The free ngrok account includes one
  assigned development domain. The ngrok agent supports HTTP and SOCKS5 proxy routes, so the supervisor
  can reconnect directly when V2Ray is off and through the local V2Ray proxy when it is on.
- **Tailscale Funnel** — stable `.ts.net` hostname, but another TUN/VPN product can conflict with the
  Tailscale adapter. It is most compatible when V2Ray operates as a system proxy rather than TUN.
- **Cloudflare Quick Tunnel** — no account is required, but the random URL changes on restart. Use it
  only for temporary testing or with `-AllowEphemeral`.

## Configure ngrok once

Set the token only in the current PowerShell process:

```powershell
$env:NGROK_AUTHTOKEN = '<token>'
.\scripts\setup-ngrok.ps1 -InstallIfMissing -StartTunnel
Remove-Item Env:NGROK_AUTHTOKEN
```

The token is saved by ngrok in its own per-user configuration. It is not added to the repository,
Scheduled Task, bridge audit, or generated GPT files.

## Start adaptive connectivity

```powershell
.\scripts\start-tunnel.ps1 `
  -Provider auto `
  -NetworkMode auto `
  -InstallIfMissing

.\scripts\start-tunnel-supervisor.ps1 `
  -Provider auto `
  -NetworkMode auto `
  -InstallIfMissing `
  -Restart
```

The supervisor checks the public `/health` endpoint. If switching V2Ray on/off breaks the current
route, it stops the failed tunnel, redetects direct and proxy paths, and reconnects. Stable providers
retain the same public hostname.

## Diagnose a failed transition

```powershell
.\scripts\status.ps1 -IncludeNetworkProfile
.\scripts\diagnose.ps1 -TestNetwork
Get-Content "$env:LOCALAPPDATA\DesktopMCPBridge\tunnel-supervisor.log" -Tail 100
```

## Stop everything

```powershell
.\scripts\stop-tunnel-supervisor.ps1 -StopTunnel
```

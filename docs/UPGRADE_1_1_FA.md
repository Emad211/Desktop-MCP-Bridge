# ارتقای نصب فعلی به Desktop MCP Bridge v1.1

این راهنما برای نصب زیر نوشته شده است:

```text
C:\AI\Desktop-MCP-Bridge
```

## ۱. دریافت نسخه جدید

```powershell
cd C:\AI\Desktop-MCP-Bridge
git status --short --branch
git fetch origin
git switch feat/initial-desktop-bridge
git pull --ff-only origin feat/initial-desktop-bridge
```

## ۲. تعمیر Full Access و Autostart

فرمان زیر خودش UAC را باز می‌کند. پنجره UAC را تأیید کنید:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\scripts\repair-deployment.ps1 `
  -FullAccess `
  -Autonomous `
  -InstallAutostart `
  -InstallIfMissing `
  -IUnderstand
```

این فرمان:

- Gateway غیرادمین قبلی را متوقف می‌کند؛
- Dependencyها را ترمیم می‌کند؛
- اگر CDN مربوط به Playwright مسدود باشد Edge یا Chrome نصب‌شده را ثبت می‌کند؛
- کلید DPAPI فعلی را حفظ می‌کند؛
- Gateway را با Administrator و Full/Autonomous اجرا می‌کند؛
- Scheduled Task با Highest privilege می‌سازد؛
- Diagnostics و Self-test را اجرا می‌کند.

## ۳. ساخت endpoint پایدار برای VPN روشن و خاموش

برای استفاده دائمی، ngrok پیشنهاد می‌شود چون دامنه Development حساب ثابت است و Agent می‌تواند هم مستقیم
و هم از HTTP/SOCKS5 محلی V2Ray متصل شود.

پس از ساخت حساب رایگان ngrok، Token را فقط در همان PowerShell قرار دهید:

```powershell
$env:NGROK_AUTHTOKEN = '<NGROK_AUTHTOKEN>'

.\scripts\setup-ngrok.ps1 `
  -InstallIfMissing `
  -StartTunnel `
  -NetworkMode auto

Remove-Item Env:NGROK_AUTHTOKEN
```

سپس Supervisor را راه‌اندازی کنید:

```powershell
.\scripts\start-tunnel-supervisor.ps1 `
  -Provider ngrok `
  -NetworkMode auto `
  -InstallIfMissing `
  -Restart
```

و Autostart آن را نصب کنید:

```powershell
.\scripts\install-tunnel-autostart.ps1 `
  -Provider ngrok `
  -NetworkMode auto `
  -InstallIfMissing `
  -StartNow
```

## ۴. گرفتن فایل جدید GPT

```powershell
$Tunnel = Get-Content `
  "$env:LOCALAPPDATA\DesktopMCPBridge\tunnel.json" `
  -Raw | ConvertFrom-Json

.\scripts\export-gpt-config.ps1 `
  -PublicBaseUrl $Tunnel.url
```

Schema و Instructions جدید در این مسیر قرار می‌گیرند:

```text
%LOCALAPPDATA%\DesktopMCPBridge\gpt-config
```

## ۵. تست تعویض VPN

ابتدا وضعیت را ثبت کنید:

```powershell
.\scripts\status.ps1 -IncludeNetworkProfile
```

V2Ray را روشن کنید، حدود ۳۰ ثانیه صبر کنید و دوباره وضعیت را بگیرید. سپس V2Ray را خاموش کنید و تست را
تکرار کنید. در هر دو حالت باید موارد زیر برقرار باشند:

```text
online = true
public_endpoint_healthy = true
tunnel_state.url = همان دامنه قبلی ngrok
```

لاگ Supervisor:

```powershell
Get-Content `
  "$env:LOCALAPPDATA\DesktopMCPBridge\tunnel-supervisor.log" `
  -Tail 100
```

## توقف فوری

```powershell
.\scripts\kill-switch.ps1 -Mode Enable
.\scripts\stop-tunnel-supervisor.ps1 -StopTunnel
.\scripts\stop-gateway.ps1
```

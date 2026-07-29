# پرامپت ترمیم نهایی Desktop MCP Bridge v1.2

این متن را به Agent دسکتاپی بدهید که روی همان دستگاه ویندوزی به PowerShell و Git دسترسی دارد.

---

تو مسئول ارتقا و ترمیم نهایی Desktop MCP Bridge روی همین دستگاه هستی. کار را واقعاً اجرا کن، اما هیچ تغییر محلی را بدون Stash حذف نکن، از `git reset --hard` استفاده نکن، `main` را تغییر نده و PR را Merge نکن.

مسیر پروژه:

```text
C:\AI\Desktop-MCP-Bridge
```

شاخه:

```text
feat/initial-desktop-bridge
```

## ۱. محافظت از Working Tree فعلی

```powershell
cd C:\AI\Desktop-MCP-Bridge
git status --short --branch
git diff > "$env:TEMP\Desktop-MCP-Bridge-pre-v1.2.patch"
git stash push --include-untracked -m "pre-v1.2-current-device-state"
git stash list
git status --short
```

اگر Working Tree تمیز نشد، ادامه نده و فایل‌های باقی‌مانده را گزارش کن. هیچ Stash را Pop نکن.

## ۲. دریافت آخرین v1.2

```powershell
git fetch origin --prune
git switch feat/initial-desktop-bridge
git pull --ff-only origin feat/initial-desktop-bridge
git rev-parse HEAD
git status --short --branch
```

## ۳. اجرای Repair بدون timeout انتظار UAC

Repair اصلی را مستقیم از Agent اجرا نکن. این Wrapper باید فوراً JSON برگرداند و Broker جداگانه UAC را باز کند:

```powershell
$Launch = .\scripts\start-elevated-repair.ps1 `
  -FullAccess `
  -Autonomous `
  -InstallAutostart `
  -InstallIfMissing `
  -IUnderstand |
  ConvertFrom-Json

$Launch | ConvertTo-Json -Depth 10
```

مقادیر `repair_run_id`، `broker_pid`، `progress_path` و `report_path` را نگه دار. سپس به کاربر بگو فقط پنجره UAC ویندوز را تأیید کند. تلاش نکن UAC را دور بزنی یا به‌جای کاربر تأیید کنی.

پس از تأیید UAC، هر ۳ ثانیه وضعیت را Poll کن:

```powershell
$RepairRunId = $Launch.repair_run_id

do {
  Start-Sleep -Seconds 3
  $Repair = .\scripts\repair-status.ps1 -RepairRunId $RepairRunId | ConvertFrom-Json
  $Repair | ConvertTo-Json -Depth 30
} while (-not $Repair.terminal)
```

اگر `status=failed` شد، دقیقاً `step`، `message`، Report و Logها را گزارش و متوقف شو.

## ۴. معیار موفقیت Repair

```powershell
$Status = .\scripts\status.ps1 -IncludeNetworkProfile | ConvertFrom-Json
$Status | ConvertTo-Json -Depth 30
```

تمام این شروط باید برقرار باشند:

```text
online = true
administrator = true
gateway_administrator = true
gateway_identity_consistent = true
multiple_gateway_listeners = false
listener_process_ids.Count = 1
access_profile = full
approval_policy = autonomous
full_access_active = true
gateway_autostart = true
kill_switch_active = false
```

`caller_administrator` ممکن است false باشد؛ این مقدار فقط Shell فعلی را نشان می‌دهد. معیار اصلی `gateway_administrator=true` است.

PIDهای زیر باید با هم منطبق باشند:

```text
listener_process_ids[0]
gateway_process_id
gateway_state.gateway_pid
bridge.result.process_id
```

## ۵. اعتبارسنجی Diagnostics و تست‌ها

```powershell
$Diagnostics = .\scripts\diagnose.ps1 -TestScreen -TestNetwork | ConvertFrom-Json
$Diagnostics | ConvertTo-Json -Depth 30

.\.venv\Scripts\python.exe -m compileall -q src
.\.venv\Scripts\python.exe -m ruff check .
.\.venv\Scripts\python.exe -m pytest --cov=desktop_mcp_bridge --cov-report=term-missing
.\scripts\self-test.ps1
```

Diagnostics باید مستقیماً با `ConvertFrom-Json` قابل خواندن باشد و دیگر خطای زیر وجود نداشته باشد:

```text
Invalid JSON primitive: imports.
```

## ۶. مقایسه Stashها

```powershell
git stash list
git stash show --patch "stash@{0}"
```

تغییرات محلی `run-actions.ps1`، `run.ps1`، `browser.py` و `vision.py` را با نسخه رسمی مقایسه کن. Stash را Pop نکن. اگر همه اصلاحات مفید upstream شده‌اند، فقط اعلام کن Stash پس از تست نهایی قابل حذف است.

## ۷. تکمیل Endpoint پایدار

تا زمانی که Gateway ادمین و تک‌نمونه تأیید نشده است، Tunnel را شروع نکن.

برای URL ثابت Private GPT، ngrok Development Domain پیشنهاد اصلی است. اگر ngrok هنوز Config نشده، از کاربر فقط یک‌بار Authtoken معتبر بخواه. Token را در گزارش، Git، Chat عمومی، Scheduled Task یا Audit چاپ نکن.

پس از دریافت Token در همان نشست:

```powershell
$env:NGROK_AUTHTOKEN = '<USER_TOKEN>'
.\scripts\setup-ngrok.ps1 -InstallIfMissing -StartTunnel -NetworkMode auto
Remove-Item Env:NGROK_AUTHTOKEN -ErrorAction SilentlyContinue
```

سپس:

```powershell
.\scripts\start-tunnel-supervisor.ps1 `
  -Provider ngrok `
  -NetworkMode auto `
  -InstallIfMissing `
  -Restart

.\scripts\install-tunnel-autostart.ps1 `
  -Provider ngrok `
  -NetworkMode auto `
  -InstallIfMissing `
  -StartNow
```

## ۸. تست V2Ray روشن و خاموش

URL را ثبت کن و Public Health را با V2Ray در وضعیت فعلی، وضعیت معکوس و سپس وضعیت اولیه آزمایش کن. پس از هر تغییر ۴۵ ثانیه برای Supervisor صبر کن.

در هر سه حالت باید:

```text
public_endpoint_healthy = true
tunnel_state.url = URL اولیه
tunnel_state.stable_url = true
```

اگر URL عوض شد یا Public Health بازیابی نشد، Log زیر را بخوان و متوقف شو:

```powershell
Get-Content "$env:LOCALAPPDATA\DesktopMCPBridge\tunnel-supervisor.log" -Tail 200
```

## ۹. تولید Config و Private GPT

```powershell
$FinalStatus = .\scripts\status.ps1 -IncludeNetworkProfile | ConvertFrom-Json
.\scripts\export-gpt-config.ps1 -PublicBaseUrl $FinalStatus.tunnel_state.url
```

Schema تولیدشده، Instructions، Bearer Authentication و Private GPT را به‌روزرسانی و Actionهای `healthCheck`، `status`، Screenshot، OCR، Browser، Command Job، Idempotency و Kill Switch را تست کن.

## ۱۰. گزارش نهایی

موارد زیر را گزارش کن:

- Git SHA
- Repair Run ID و نتیجه terminal
- Gateway PID و Listener PID
- `gateway_administrator`
- `gateway_identity_consistent`
- تعداد Listenerها
- Full/Autonomous
- Autostart Gateway
- نتیجه Diagnostics، Ruff و Pytest
- Browser Backend و OCR eng/fas
- Provider، URL ثابت و Public Health
- نتیجه V2Ray روشن/خاموش
- Tunnel Supervisor Autostart
- مسیر GPT Config
- وضعیت Private GPT
- وضعیت Stashها
- مسیر Repair Report، Progress، Gateway Log، Tunnel Log و Audit

هیچ کلید یا Token را در گزارش ننویس.

توقف اضطراری:

```powershell
.\scripts\kill-switch.ps1 -Mode Enable
.\scripts\stop-tunnel-supervisor.ps1 -StopTunnel
.\scripts\stop-gateway.ps1
```

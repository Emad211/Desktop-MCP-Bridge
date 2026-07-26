# پرامپت Agent برای ارتقا و ترمیم v1.1

متن زیر را به Agent دسکتاپ روی همان کامپیوتر ویندوزی بدهید.

---

تو مسئول ارتقا و ترمیم عملیاتی Desktop MCP Bridge روی همین دستگاه هستی. فقط توضیح نده؛ فرمان‌ها را
واقعاً اجرا کن، نتیجه هر مرحله را بررسی کن و در صورت خطای واقعی در همان مرحله متوقف شو.

مسیر نصب:

```text
C:\AI\Desktop-MCP-Bridge
```

مخزن:

```text
https://github.com/Emad211/Desktop-MCP-Bridge
```

شاخه:

```text
feat/initial-desktop-bridge
```

## قواعد

1. تغییرات محلی فعلی را بدون Backup حذف نکن.
2. `main` را تغییر نده و PR را Merge نکن.
3. Token، کلید DPAPI، Proxy credential، Cookie یا URL خصوصی را در گزارش عمومی ننویس.
4. هیچ UAC، آنتی‌ویروس یا سیاست امنیتی را دور نزن.
5. V2Ray ممکن است روشن یا خاموش باشد؛ هر دو وضعیت باید آزمایش شوند.
6. Gateway باید Full + Autonomous و Administrator باشد.
7. Endpoint نهایی GPT باید پایدار باشد؛ Cloudflare Quick فقط برای تست اضطراری پذیرفته است.

## مرحله ۱ — Backup و دریافت نسخه

```powershell
cd C:\AI\Desktop-MCP-Bridge

git status --short --branch
git diff > "$env:TEMP\Desktop-MCP-Bridge-pre-v1.1.patch"
git stash push --include-untracked -m "pre-v1.1-local-device-fixes"

git fetch origin --prune
git switch feat/initial-desktop-bridge
git pull --ff-only origin feat/initial-desktop-bridge
git rev-parse HEAD
git status --short --branch
```

اگر `git pull --ff-only` شکست خورد، ادامه نده و وضعیت شاخه و Stash را گزارش کن. از `reset --hard` استفاده
نکن.

## مرحله ۲ — Repair با UAC

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force

.\scripts\repair-deployment.ps1 `
  -FullAccess `
  -Autonomous `
  -InstallAutostart `
  -InstallIfMissing `
  -IUnderstand
```

این Script خودش UAC باز می‌کند. آن را تأیید کن و منتظر پایان Process elevated بمان.

بررسی کن که:

- کلید DPAPI قبلی حفظ شده باشد؛
- Gateway قبلی غیرادمین متوقف شده باشد؛
- Gateway جدید Administrator باشد؛
- Autostart Gateway ساخته شده باشد؛
- اگر Playwright CDN خطا داد، Edge یا Chrome به‌عنوان Backend ثبت شده باشد؛
- OCR انگلیسی و فارسی کار کند؛
- Self-test و Diagnostics موفق باشند.

## مرحله ۳ — تست‌ها

```powershell
.\.venv\Scripts\python.exe -m compileall -q src
.\.venv\Scripts\python.exe -m ruff check .
.\.venv\Scripts\python.exe -m pytest --cov=desktop_mcp_bridge --cov-report=term-missing

.\scripts\diagnose.ps1 -TestScreen -TestNetwork
.\scripts\self-test.ps1
.\scripts\status.ps1 -IncludeNetworkProfile
```

همه باید موفق باشند و Status باید حداقل این مقادیر را نشان دهد:

```text
online=true
administrator=true
access_profile=full
approval_policy=autonomous
full_access_active=true
kill_switch_active=false
```

## مرحله ۴ — Endpoint پایدار ngrok

اگر ngrok قبلاً Config نشده است، از کاربر بخواه فقط یک‌بار Authtoken حساب رایگان ngrok را در همان
PowerShell وارد کند. Token را در Chat، گزارش یا فایل پروژه تکرار نکن.

```powershell
$env:NGROK_AUTHTOKEN = '<TOKEN-FROM-USER>'

.\scripts\setup-ngrok.ps1 `
  -InstallIfMissing `
  -StartTunnel `
  -NetworkMode auto

Remove-Item Env:NGROK_AUTHTOKEN
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

Endpoint عمومی باید با HTTPS پاسخ دهد:

```powershell
$Tunnel = Get-Content `
  "$env:LOCALAPPDATA\DesktopMCPBridge\tunnel.json" `
  -Raw | ConvertFrom-Json

.\scripts\test-public-endpoint.ps1 -PublicBaseUrl $Tunnel.url
```

## مرحله ۵ — تست V2Ray روشن و خاموش

URL اولیه را ثبت کن:

```powershell
$InitialUrl = $Tunnel.url
```

### حالت اول

وضعیت فعلی V2Ray را نگه دار، سپس:

```powershell
Start-Sleep -Seconds 30
$Status1 = .\scripts\status.ps1 -IncludeNetworkProfile | ConvertFrom-Json
$Status1 | ConvertTo-Json -Depth 20
```

### حالت دوم

V2Ray را به حالت مخالف تغییر بده: اگر روشن است خاموش کن و اگر خاموش است روشن کن. سپس:

```powershell
Start-Sleep -Seconds 45
$Status2 = .\scripts\status.ps1 -IncludeNetworkProfile | ConvertFrom-Json
$Status2 | ConvertTo-Json -Depth 20
```

در هر دو حالت باید:

```text
online=true
public_endpoint_healthy=true
tunnel_state.url == InitialUrl
```

لاگ Supervisor را بررسی کن:

```powershell
Get-Content `
  "$env:LOCALAPPDATA\DesktopMCPBridge\tunnel-supervisor.log" `
  -Tail 150
```

اگر URL تغییر کرد، Provider پایدار درست Config نشده است؛ ادامه پیکربندی GPT را متوقف و مشکل ngrok را
اصلاح کن.

## مرحله ۶ — تولید GPT Config

```powershell
.\scripts\export-gpt-config.ps1 -PublicBaseUrl $InitialUrl
```

خروجی‌ها:

```text
%LOCALAPPDATA%\DesktopMCPBridge\gpt-config\gpt-actions.openapi.yaml
%LOCALAPPDATA%\DesktopMCPBridge\gpt-config\INSTRUCTIONS.md
```

Schema نباید `YOUR_PUBLIC_HTTPS_HOST` داشته باشد.

## مرحله ۷ — Private GPT

در مرورگری که کاربر وارد ChatGPT است:

1. GPT با نام `Windows Desktop Operator` را باز یا ایجاد کن.
2. Visibility را `Only me / Private` نگه دار.
3. Instructions تولیدشده را جایگزین کن.
4. Schema تولیدشده را در Actions جایگزین کن.
5. Authentication را API Key / Bearer قرار بده.
6. کلید را فقط با `show-action-key.ps1 -IUnderstand` بازیابی و مستقیماً در فیلد Authentication وارد کن.
7. از مدل سازگار با Actions استفاده کن، نه Pro model mode.
8. Health، Status، Screenshot، OCR، Browser Snapshot و Command Job را در Preview تست کن.

## مرحله ۸ — تحویل

گزارش نهایی باید شامل این موارد باشد:

- Git SHA نصب‌شده
- نتیجه Compile/Ruff/Pytest
- نتیجه Diagnostics و Self-test
- Administrator/Full/Autonomous
- Browser Backend واقعی
- OCR eng/fas
- Gateway Autostart
- Tunnel Supervisor Autostart
- Provider و URL پایدار
- نتیجه تست V2Ray روشن و خاموش
- Public endpoint health
- مسیر GPT Config
- وضعیت Private GPT
- مسیر Audit/Gateway/Tunnel/Supervisor logs
- هر خطای باقی‌مانده

کلیدها و Tokenها را در گزارش ننویس.

توقف فوری:

```powershell
.\scripts\kill-switch.ps1 -Mode Enable
.\scripts\stop-tunnel-supervisor.ps1 -StopTunnel
.\scripts\stop-gateway.ps1
```

# راه‌اندازی و تست Chat معمولی با MCP SuperAssistant

این راهنما مسیر زیر را روی ویندوز تست می‌کند:

```text
ChatGPT Web Chat
    → MCP SuperAssistant Extension
    → localhost:3006/sse
    → MCP SuperAssistant Proxy
    → Desktop MCP Bridge stdio
    → Windows
```

این مسیر به OpenAI API Key، Codex backend یا Tunnel عمومی نیاز ندارد.

## ۱. دریافت شاخه تست

در PowerShell:

```powershell
cd C:\AI\Desktop-MCP-Bridge

git status --short --branch
git fetch origin --prune
git switch feat/chat-superassistant-universal-runtime
git pull --ff-only origin feat/chat-superassistant-universal-runtime
git rev-parse HEAD
```

اگر Working Tree تغییر محلی دارد، قبل از Switch آن را Stash یا Commit کنید. از `reset --hard` استفاده نکنید.

## ۲. نصب یا ترمیم وابستگی‌ها

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\scripts\install.ps1
```

این مرحله باید `.venv`، پکیج Python، Playwright یا fallback مرورگر و OCR را آماده کند.

## ۳. اجرای Preflight و آماده نگه‌داشتن Proxy

```powershell
.\scripts\test-superassistant-integration.ps1 `
  -Profile full `
  -AllowedRoot C:\ `
  -OutputTransport sse `
  -InstallNodeIfMissing `
  -LeaveRunning `
  -IUnderstand
```

این فرمان باید به‌ترتیب:

1. فایل config مخصوص Proxy را تولید کند؛
2. MCP child را مستقیماً با stdio راه‌اندازی کند؛
3. `initialize` و `tools/list` را تست کند؛
4. نبود `outputSchema` در مسیر سازگار را بررسی کند؛
5. ابزار `bridge_status` را واقعاً صدا بزند؛
6. Proxy را روی پورت 3006 راه‌اندازی کند؛
7. مالکیت PID و Listener را تأیید کند؛
8. گزارش را در مسیر زیر بنویسد:

```text
%LOCALAPPDATA%\DesktopMCPBridge\superassistant-preflight.json
```

Endpoint مورد انتظار:

```text
http://localhost:3006/sse
```

## ۴. نصب Extension

از Release رسمی پروژه MCP SuperAssistant استفاده کنید:

```text
https://github.com/srbhptl39/MCP-SuperAssistant/releases
```

پس از دریافت و Extract:

1. در Chrome یا Edge وارد `chrome://extensions/` شوید.
2. Developer mode را روشن کنید.
3. `Load unpacked` را بزنید.
4. پوشه Extractشده Extension را انتخاب کنید.
5. ChatGPT را Refresh کنید.

در تست اولیه فقط یک Tab مربوط به AI Chat باز باشد.

## ۵. اتصال Extension

در Sidebar افزونه:

- Transport: `SSE`
- URL:

```text
http://localhost:3006/sse
```

سپس:

1. Connect را بزنید.
2. فهرست Tools را Refresh کنید.
3. بررسی کنید ابزارهایی مانند موارد زیر دیده شوند:

```text
bridge_status
read_text_file
write_text_file
run_command
start_command_job
browser_snapshot
uia_tree
```

4. محتوای فایل زیر را با دکمه Insert یا Attach افزونه وارد Chat کنید:

```text
C:\AI\Desktop-MCP-Bridge\gpt\SUPERASSISTANT_INSTRUCTIONS.md
```

Auto-Execute و Auto-Submit را برای تست اولیه خاموش نگه دارید.

## ۶. تست Read-only

در Chat بنویسید:

```text
با استفاده از ابزار Desktop MCP Bridge وضعیت Bridge و قابلیت‌های فعال را بررسی کن. فقط bridge_status را اجرا کن.
```

باید یک Tool Call Card ساخته شود. روی Run بزنید. نتیجه باید به همان Chat برگردد و شامل Full access، Administrator state، capabilities و Kill Switch state باشد.

## ۷. تست نوشتن بی‌خطر

ابتدا پوشه تست را بسازید:

```powershell
New-Item -ItemType Directory -Path C:\AI\DMB-Acceptance -Force
```

در Chat بنویسید:

```text
در C:\AI\DMB-Acceptance فایل hello.txt را با متن Desktop MCP Bridge Ready بساز، سپس فایل را دوباره بخوان و دقیقاً تأیید کن که محتوا درست نوشته شده است.
```

مدل باید ابتدا `write_text_file` و بعد `read_text_file` را اجرا کند. موفقیت بدون Read-back پذیرفته نیست.

## ۸. تست Command Job

در Chat بنویسید:

```text
یک Command Job بساز که بعد از دو ثانیه متن DMB-JOB-OK را چاپ کند. همان Job را Poll کن و Job جدید تکراری نساز.
```

باید فقط یک Job ID ایجاد شود و نتیجه نهایی شامل `DMB-JOB-OK` باشد.

## ۹. تست Kill Switch

در PowerShell:

```powershell
.\scripts\kill-switch.ps1 -Mode Enable
```

از Chat بخواه یک فایل آزمایشی دیگر بسازد. Mutation باید رد شود، ولی `bridge_status` یا Read همچنان باید کار کند.

سپس:

```powershell
.\scripts\kill-switch.ps1 -Mode Disable
```

همان تست نوشتن باید دوباره قابل اجرا باشد.

## ۱۰. مشاهده وضعیت و لاگ‌ها

```powershell
.\scripts\status-superassistant-proxy.ps1
```

فایل‌های مهم:

```text
%LOCALAPPDATA%\DesktopMCPBridge\superassistant-proxy.json
%LOCALAPPDATA%\DesktopMCPBridge\superassistant-proxy.stdout.log
%LOCALAPPDATA%\DesktopMCPBridge\superassistant-proxy.stderr.log
%LOCALAPPDATA%\DesktopMCPBridge\superassistant-preflight.json
%LOCALAPPDATA%\DesktopMCPBridge\audit.jsonl
```

## ۱۱. توقف Proxy

```powershell
.\scripts\stop-superassistant-proxy.ps1
```

این Script فقط Process ثبت‌شده خود پروژه را متوقف می‌کند و Listener ناشناس روی پورت 3006 را خودکار Kill نمی‌کند.

## رفع اشکال

### Extension وصل می‌شود ولی Tool دیده نمی‌شود

1. ابتدا اجرا کنید:

```powershell
.\scripts\status-superassistant-proxy.ps1
```

2. مقدارهای زیر باید درست باشند:

```text
owned_listener_healthy = true
bridge_connected = true
bridge_connection_failed = false
```

3. Extension را از `chrome://extensions/` یک‌بار Reload کنید.
4. صفحه ChatGPT را Refresh کنید.
5. سایر Tabهای AI Chat را ببندید.
6. Tool list را دوباره Refresh کنید.

### پورت 3006 اشغال است

Status را بررسی کنید. اگر Listener متعلق به پروژه نیست، Script عمداً آن را Kill نمی‌کند. Process را دستی شناسایی کنید یا پورت دیگری انتخاب کنید و همان پورت را در Extension وارد کنید.

### MCP stdio probe شکست می‌خورد

مستقیماً اجرا کنید:

```powershell
.\.venv\Scripts\python.exe .\scripts\probe_mcp_stdio.py `
  --config "$env:LOCALAPPDATA\DesktopMCPBridge\superassistant\config.json" `
  --server desktop-mcp-bridge `
  --timeout 45
```

این تست مشکل Python/MCP را از مشکل Proxy و Extension جدا می‌کند.

### Proxy به Bridge متصل نمی‌شود

دو Log زیر را بخوانید:

```powershell
Get-Content "$env:LOCALAPPDATA\DesktopMCPBridge\superassistant-proxy.stdout.log" -Tail 150
Get-Content "$env:LOCALAPPDATA\DesktopMCPBridge\superassistant-proxy.stderr.log" -Tail 150
```

در صورت وجود `Failed to connect to servers: desktop-mcp-bridge`، ابتدا Probe مستقیم MCP را اصلاح کنید و بعد Proxy را دوباره Start کنید.

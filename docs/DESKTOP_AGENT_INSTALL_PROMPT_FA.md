# پرامپت نصب و راه‌اندازی کامل برای ایجنت دسکتاپ

متن زیر را بدون حذف هیچ مرحله‌ای به ایجنتی بدهید که روی همان کامپیوتر ویندوزی به PowerShell، مرورگر،
فایل‌ها و Git دسترسی دارد.

---

تو مسئول نصب، پیکربندی، اجرای آزمایشی و تحویل عملیاتی پروژه Desktop MCP Bridge روی همین کامپیوتر هستی.
کار را مستقل و مرحله‌به‌مرحله انجام بده و صرفاً توضیح نده؛ دستورات را واقعاً اجرا کن. پروژه باید در حالت
Full Access + Autonomous آماده شود، اما همه کنترل‌های محلی شامل Kill Switch، Audit، Idempotency و
احراز هویت باید فعال بمانند.

مخزن رسمی:
`https://github.com/Emad211/Desktop-MCP-Bridge`

شاخه‌ای که باید نصب شود:
`feat/initial-desktop-bridge`

## قواعد غیرقابل‌چشم‌پوشی

1. PowerShell را با Run as Administrator اجرا کن. اگر نشست فعلی Administrator نیست، یک PowerShell
   elevated باز کن و ادامه را آنجا انجام بده.
2. هیچ کلید، رمز، فایل DPAPI، URL خصوصی Tunnel یا اسکرین‌شات حساس را در Git commit، issue عمومی، log
   عمومی یا سرویس دیگری منتشر نکن.
3. هیچ مرحله‌ای را فقط به‌خاطر وجود فایل قبلی موفق فرض نکن؛ خروجی هر مرحله را بررسی کن.
4. در صورت خطا، همان‌جا متوقف شو، فرمان خطادار، خروجی کامل، علت احتمالی و اقدام اصلاحی را گزارش کن.
5. `main` را تغییر نده و PR را merge نکن. فقط شاخه تعیین‌شده را checkout و اجرا کن.
6. آنتی‌ویروس، UAC، فایروال یا سیاست‌های امنیتی ویندوز را دور نزن و هیچ persistence مخفی نساز.
7. GPT نهایی باید Private بماند.

## مرحله ۱ — دریافت یا به‌روزرسانی پروژه

یک پوشه مناسب مانند `C:\AI\Desktop-MCP-Bridge` انتخاب کن. اگر مخزن وجود ندارد:

```powershell
git clone https://github.com/Emad211/Desktop-MCP-Bridge.git C:\AI\Desktop-MCP-Bridge
```

اگر وجود دارد، تغییرات محلی را بررسی کن؛ چیزی را بدون گزارش حذف نکن. سپس:

```powershell
cd C:\AI\Desktop-MCP-Bridge
git fetch --all --prune
git switch feat/initial-desktop-bridge
git pull --ff-only origin feat/initial-desktop-bridge
git status --short --branch
```

SHA فعلی را ثبت کن:

```powershell
git rev-parse HEAD
```

## مرحله ۲ — Bootstrap کامل

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\scripts\bootstrap.ps1 `
  -FullAccess `
  -Autonomous `
  -InstallAutostart `
  -StartNow `
  -RunSelfTest `
  -IUnderstand
```

این مرحله باید Python 3.11+، محیط مجازی، وابستگی‌ها، Chromium مدیریت‌شده Playwright، Tesseract OCR،
زبان‌های `eng` و `fas`، کلید تصادفی و ذخیره DPAPI را آماده کند. اگر WinGet بعد از نصب Python یا
Cloudflared نیازمند refresh مسیر بود، PowerShell elevated تازه باز کن و همان مرحله را تکرار کن.

کلید چاپ‌شده را فقط برای پیکربندی GPT نگه دار؛ آن را در فایل متنی معمولی ذخیره نکن. وجود فایل رمزگذاری
شده زیر را بررسی کن:

```text
%LOCALAPPDATA%\DesktopMCPBridge\action-key.clixml
```

## مرحله ۳ — Diagnostics و Self-test

این فرمان‌ها باید بدون خطا اجرا شوند:

```powershell
.\scripts\diagnose.ps1 -TestScreen
.\scripts\status.ps1
.\scripts\self-test.ps1
```

Self-test باید حداقل این موارد را اثبات کند:

- Gateway روی `127.0.0.1:8766` سالم است؛
- درخواست Bearer احراز هویت می‌شود؛
- وضعیت Full/Autonomous فعال است و Administrator برابر true است؛
- اسکرین‌شات واقعی ساخته می‌شود؛
- OCR انگلیسی و فارسی اجرا می‌شود؛
- Playwright Chromium باز می‌شود و `https://example.com` را می‌خواند؛
- ARIA/browser snapshot برمی‌گردد؛
- یک command job ساخته، poll و با خروجی صحیح تمام می‌شود؛
- Kill Switch خاموش است؛
- Audit log ساخته شده است.

همچنین تست‌های پروژه را اجرا کن:

```powershell
.\.venv\Scripts\python.exe -m compileall -q src
.\.venv\Scripts\python.exe -m ruff check .
.\.venv\Scripts\python.exe -m pytest --cov=desktop_mcp_bridge --cov-report=term-missing
```

## مرحله ۴ — ساخت HTTPS Tunnel آزمایشی

Quick Tunnel را به‌صورت background راه‌اندازی کن:

```powershell
$Tunnel = .\scripts\start-quick-tunnel.ps1 -Port 8766 -InstallIfMissing | ConvertFrom-Json
$Tunnel
```

مقدار `$Tunnel.url` باید با `https://` آغاز شود و endpoint زیر باید پاسخ سالم بدهد:

```powershell
Invoke-RestMethod "$($Tunnel.url)/health"
```

URL را ثبت کن، اما عمومی منتشر نکن. برای استفاده دائم، اگر کاربر دامنه Cloudflare آماده دارد، به‌جای
Quick Tunnel از `scripts/setup-named-tunnel.ps1` استفاده کن؛ بدون داشتن دامنه، مرحله Quick Tunnel کافی
است.

## مرحله ۵ — تولید فایل آماده GPT

```powershell
.\scripts\export-gpt-config.ps1 -PublicBaseUrl $Tunnel.url
```

مسیرهای خروجی schema و instructions را از JSON خروجی بردار. Schema تولیدشده نباید placeholder
`YOUR_PUBLIC_HTTPS_HOST` داشته باشد.

کلید Bearer را فقط در لحظه پیکربندی نمایش بده:

```powershell
$ActionKey = .\scripts\show-action-key.ps1 -IUnderstand
```

## مرحله ۶ — ساخت و پیکربندی Private Custom GPT

با مرورگری که کاربر از قبل در ChatGPT وارد آن شده است:

1. وارد بخش ساخت GPT شو.
2. یک GPT جدید با نام `Windows Desktop Operator` بساز.
3. Visibility را روی `Only me / Private` نگه دار.
4. محتوای فایل `INSTRUCTIONS.md` تولیدشده را کامل در Instructions قرار بده.
5. در Actions، فایل `gpt-actions.openapi.yaml` تولیدشده را import/paste کن.
6. Authentication را `API Key` و نوع آن را `Bearer` انتخاب کن.
7. مقدار `$ActionKey` را وارد کن؛ آن را در متن Instructions یا Conversation Starters ننویس.
8. مدلی را انتخاب کن که از GPT Actions پشتیبانی می‌کند. Pro model mode را برای این GPT انتخاب نکن.
9. GPT را Private ذخیره کن.

اگر برای ایجاد GPT یا ذخیره Action نیاز به تأیید انسانی یا ورود مجدد حساب بود، در همان صفحه متوقف شو و
فقط همان تأیید را از کاربر بخواه؛ سایر مراحل فنی را ادامه نده تا آن تأیید انجام شود.

## مرحله ۷ — تست نهایی از داخل GPT

در Preview خود GPT این ترتیب را اجرا کن:

1. `healthCheck`
2. `observeComputer` با operation=`status`
3. `getScreenCapture`
4. `observeComputer` با operation=`screen_ocr` و language=`eng+fas`
5. `controlComputer` با operation=`browser_start` و request_id یکتا
6. `controlComputer` با operation=`browser_navigate` به `https://example.com`
7. `observeComputer` با operation=`browser_snapshot`
8. یک command job بی‌خطر برای چاپ متن، سپس poll با `get_command_job`

برای هر Action تغییردهنده یک UUID جدید بساز. UUID را فقط هنگام retry دقیق همان payload تکرار کن.
نتیجه را با مشاهده مجدد تأیید کن و صرفاً بر اساس HTTP 200 موفقیت اعلام نکن.

## مرحله ۸ — آزمون Kill Switch

```powershell
.\scripts\kill-switch.ps1 -Mode Enable
```

یک Action تغییردهنده بی‌خطر باید رد شود، در حالی که status همچنان قابل خواندن باشد. سپس:

```powershell
.\scripts\kill-switch.ps1 -Mode Disable
```

و همان Action باید دوباره قابل اجرا شود.

## مرحله ۹ — تحویل نهایی

در پایان این اطلاعات را گزارش کن:

- مسیر نصب؛
- Git SHA نصب‌شده؛
- نتیجه compile، Ruff و pytest؛
- نتیجه diagnostics و self-test؛
- وضعیت Administrator، Full Access و Autonomous؛
- وضعیت Scheduled Task autostart؛
- URL Tunnel؛
- مسیر schema و instructions تولیدشده؛
- وضعیت Private GPT و تست‌های Action؛
- مسیر logها و audit؛
- روش توقف فوری:
  `.\scripts\kill-switch.ps1 -Mode Enable`؛
- روش توقف Gateway:
  `.\scripts\stop-gateway.ps1`؛
- روش توقف Tunnel:
  `.\scripts\stop-quick-tunnel.ps1`.

کلید Bearer را در گزارش نهایی تکرار نکن. فقط بگو که در DPAPI ذخیره و در GPT ثبت شده است.

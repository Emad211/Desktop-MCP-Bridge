# راهنمای دقیق VPN برای Gate C

این سند مشخص می‌کند در مسیر اتصال Chat معمولی ChatGPT به Desktop MCP Bridge، VPN چه زمانی باید روشن یا خاموش باشد.

## قانون اصلی

سه مسیر شبکه‌ای جدا وجود دارد:

```text
1. Browser -> chatgpt.com                 اینترنت / معمولاً VPN لازم
2. npm / GitHub -> دریافت وابستگی‌ها      اینترنت / در مسیر محدودشده VPN لازم
3. Extension -> localhost:3006 -> Bridge  کاملاً محلی / VPN لازم نیست
```

پروژه برای مسیر سوم متغیرهای زیر را اعمال می‌کند:

```text
NO_PROXY=localhost,127.0.0.1,::1
no_proxy=localhost,127.0.0.1,::1
```

بنابراین روشن بودن VPN نباید ارتباط Extension با Proxy محلی را از مسیر اینترنت عبور دهد.

## جدول تصمیم

| مرحله | وضعیت VPN | دلیل |
|---|---|---|
| `git fetch` و `git pull` | روشن | دسترسی پایدار به GitHub |
| اجرای اولیه `install.ps1` | روشن | دریافت پکیج‌های Python؛ دانلود Chromium اختیاری است |
| دریافت یا به‌روزرسانی Extension | روشن | دسترسی به GitHub Releases |
| اولین اجرای Proxy با `npx` | روشن | دریافت نسخهٔ پین‌شدهٔ Proxy از npm |
| اجرای `prepare-chatgpt-gate-c.ps1` | روشن بماند | حذف متغیر شبکه از اولین تست و حفظ دسترسی ChatGPT |
| اتصال Extension به `localhost:3006/sse` | روشن بماند | ChatGPT به VPN نیاز دارد؛ localhost با NO_PROXY دور زده می‌شود |
| تست status/read/write/command در ChatGPT | روشن بماند | اولین Gate C باید با یک وضعیت ثابت شبکه انجام شود |
| تست Kill Switch | روشن بماند | این تست کاملاً محلی است، ولی ChatGPT همچنان باید در دسترس باشد |
| تست مقاومت با VPN خاموش | فقط بعد از عبور Gate C | هنگام خاموش بودن فقط سلامت localhost را با PowerShell بررسی کنید |
| بازگشت به ChatGPT پس از تست خاموش | دوباره روشن | صفحه ChatGPT و نشست Extension باید دوباره قابل دسترس باشند |

## دانلود Chromium

اگر Playwright CDN پاسخ منطقه‌ای 403 بدهد ولی Edge یا Chrome نصب باشد، این خطا مانع پروژه نیست. `install.ps1` اکنون fallback ثبت‌شده را در نصب‌های بعدی reuse می‌کند و دوباره دانلود را امتحان نمی‌کند، مگر اینکه صریحاً اجرا شود:

```powershell
.\scripts\install.ps1 -ForceBrowserDownload
```

برای Gate C نیازی به تکرار دانلود Chromium نیست؛ Edge fallback کافی است.

## تست اول: VPN روشن

```powershell
cd C:\AI\Desktop-MCP-Bridge

git fetch origin --prune
git switch feat/chat-superassistant-universal-runtime
git pull --ff-only origin feat/chat-superassistant-universal-runtime

Set-ExecutionPolicy -Scope Process Bypass -Force

.\scripts\prepare-chatgpt-gate-c.ps1 `
  -Profile full `
  -AllowedRoot C:\ `
  -NetworkMode auto `
  -InstallNodeIfMissing `
  -IUnderstand
```

در تمام این مرحله VPN روشن بماند.

خروجی باید شامل این موارد باشد:

```text
ok=true
endpoint=http://localhost:3006/sse
owned_listener_healthy=true
bridge_connected=true
```

گزارش جلسه:

```text
%LOCALAPPDATA%\DesktopMCPBridge\chatgpt-gate-c-session.json
```

## تست Extension و ChatGPT

VPN همچنان روشن باشد.

در Extension:

```text
Transport: SSE
URL: http://localhost:3006/sse
Auto Execute: Off
Auto Submit: Off
```

سپس پرامپت‌های موجود در `chatgpt-gate-c-session.json` را به‌ترتیب اجرا کنید.

## بررسی خودکار پس از Read/Write

```powershell
.\scripts\verify-chatgpt-gate-c.ps1
```

## Kill Switch

VPN روشن بماند، چون تست از داخل ChatGPT انجام می‌شود.

```powershell
.\scripts\kill-switch.ps1 -Mode Enable
```

پرامپت `kill-switch-negative` را اجرا کنید. عملیات Write باید رد شود و فایل `must-not-be-created.txt` نباید ساخته شود.

سپس:

```powershell
.\scripts\kill-switch.ps1 -Mode Disable
```

## تست مقاومت VPN پس از عبور Gate C

1. Proxy و مرورگر را باز نگه دارید.
2. VPN را خاموش کنید.
3. در PowerShell فقط این فرمان محلی را اجرا کنید:

```powershell
.\scripts\status-superassistant-proxy.ps1
```

باید همچنان نشان دهد:

```text
owned_listener_healthy=true
bridge_connected=true
```

4. در این حالت از ChatGPT انتظار عملکرد نداشته باشید، چون ممکن است سایت بدون VPN قابل دسترسی نباشد.
5. VPN را دوباره روشن کنید.
6. صفحه ChatGPT را Refresh کنید و Extension را دوباره Connect کنید.
7. یک بار دیگر `bridge_status` را اجرا کنید.

## حالت‌های NetworkMode

### پیشنهادشده

```powershell
-NetworkMode auto
```

Route مستقیم بدون Proxy صریح تست می‌شود؛ اگر شکست بخورد، یک HTTP Proxy سالم شناسایی می‌شود.

### اجبار مسیر مستقیم

```powershell
-NetworkMode direct
```

فقط وقتی استفاده شود که VPN در حالت TUN است یا اینترنت مستقیم npm را باز می‌کند.

### اجبار HTTP Proxy

```powershell
-NetworkMode proxy -ProxyUrl http://127.0.0.1:10809
```

تنها HTTP/HTTPS Proxy پذیرفته می‌شود. برای npm یک SOCKS-only URL مستقیماً استفاده نمی‌شود.

## نکات رفع خطا

اگر Script در مرحلهٔ Network متوقف شد:

- VPN/V2Ray را روشن کنید.
- مطمئن شوید یک HTTP proxy مانند `127.0.0.1:10809` فعال است یا TUN کار می‌کند.
- دوباره با `-NetworkMode auto` اجرا کنید.

اگر Port 3006 اشغال بود:

```powershell
.\scripts\status-superassistant-proxy.ps1
.\scripts\stop-superassistant-proxy.ps1
```

پروژه Process ناشناس روی Port 3006 را خودکار Kill نمی‌کند.

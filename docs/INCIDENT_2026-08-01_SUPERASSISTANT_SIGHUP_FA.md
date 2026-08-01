# گزارش رخداد: خروج Proxy با SIGHUP در Gate C

تاریخ: 2026-08-01

## خلاصه

در تست واقعی ویندوز، مسیر MCP با موفقیت کامل راه‌اندازی شد:

- Proxy فایل Config را خواند؛
- `desktop-mcp-bridge` را اجرا کرد؛
- 47 ابزار را شناسایی کرد؛
- SSE Gateway روی `localhost:3006` آماده شد.

اما Launcher قدیمی Proxy، `npx.cmd` را در یک پنجره Console جدا اجرا می‌کرد. این پنجره برای کاربر خالی به نظر می‌رسید. بستن پنجره باعث ارسال سیگنال خاتمه به Process Node شد و Proxy با پیام زیر خارج شد:

```text
Caught SIGHUP. Exiting...
```

Exit Code ویندوز:

```text
-1073741510 (0xC000013A / control-event termination)
```

## علت ریشه‌ای

استفاده از این الگو:

```powershell
Start-Process -FilePath npx.cmd -WindowStyle Minimized
```

برای یک Process طولانی‌مدت مناسب نبود. فایل‌های `.cmd` از طریق Console Host اجرا می‌شوند و پنجرهٔ ساخته‌شده بخشی از عمر Process محسوب می‌شود.

## اصلاح

Launcher جدید:

1. نسخهٔ پین‌شدهٔ Proxy را یک‌بار با `npm install --prefix` در Runtime محلی نصب می‌کند؛
2. مسیر واقعی `bin` را از `package.json` پکیج استخراج می‌کند؛
3. فایل JavaScript را مستقیماً با `node.exe` اجرا می‌کند؛
4. Process را با `-WindowStyle Hidden` و Redirect کامل stdout/stderr بالا می‌آورد؛
5. `npx.cmd` در مسیر Process طولانی‌مدت استفاده نمی‌شود؛
6. State شامل `launch_method=direct-node-hidden`، مسیر Node، Runtime و Entry Point است.

Runtime محلی:

```text
%LOCALAPPDATA%\DesktopMCPBridge\superassistant-runtime
```

## اثر روی شبکه و VPN

- اولین نصب Runtime ممکن است به npm نیاز داشته باشد؛ VPN باید روشن باشد.
- پس از Cache شدن Runtime، شروع‌های بعدی بدون نصب مجدد انجام می‌شوند.
- `NO_PROXY=localhost,127.0.0.1,::1` حفظ شده است؛ ارتباط Extension با Proxy محلی از VPN عبور نمی‌کند.

## کنترل رگرسیون

تست `tests/test_superassistant_launcher_static.py` تضمین می‌کند:

- Launcher از `node.exe` استفاده کند؛
- Window پنهان باشد؛
- Runtime محلی وجود داشته باشد؛
- مسیر قدیمی `Start-Process -FilePath $Npx` برنگردد؛
- `-WindowStyle Minimized` دوباره وارد کد نشود.

## معیار پذیرش روی دستگاه

پس از اجرای `prepare-chatgpt-gate-c.ps1`:

```text
state_found=true
launch_method=direct-node-hidden
launcher_process_name=node
listener_process_name=node
owned_listener_healthy=true
bridge_connected=true
endpoint=http://localhost:3006/sse
```

نباید هیچ پنجرهٔ Console جدیدی باز شود.

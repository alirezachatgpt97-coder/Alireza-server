# 🚀 Alireza Server

### Nova Server + AdGuard Home + OpenVPN Management

نصب و یکپارچه‌سازی Nova Server با DNS مبتنی بر AdGuard Home و مدیریت
OpenVPN در یک پنل.

**نسخه مستندشده:** `0.3.0`\
**سیستم‌عامل‌های هدف:** Ubuntu 24.04 / Debian 12 / Debian 13\
**معماری‌ها:** amd64 / arm64

> \[!IMPORTANT\] این پروژه یک نصب‌کننده آنلاین است و برای اجرا به
> اینترنت، دسترسی root و systemd نیاز دارد. قبل از استفاده روی
> production، محدودیت‌ها و هشدارهای امنیتی را کامل بخوانید.

------------------------------------------------------------------------

## نصب تک‌خطی

> \[!CAUTION\] اجرای مستقیم اسکریپت اینترنتی با root یعنی به محتوای URL
> در لحظه اجرا اعتماد می‌کنید. برای production روش دانلود و بررسی را
> ترجیح دهید.

``` bash
bash <(curl -fsSL https://raw.githubusercontent.com/alirezachatgpt97-coder/Alireza-server/main/install.sh)
```

اگر process substitution در shell در دسترس نیست:

``` bash
curl -fsSL https://raw.githubusercontent.com/alirezachatgpt97-coder/Alireza-server/main/install.sh | sudo bash
```

بعد از نصب منتظر پیام `ALIREZASERVER READY` بمانید.

------------------------------------------------------------------------

## فهرست مطالب

-   معرفی و هدف پروژه
-   امکانات
-   معماری
-   پیش‌نیازها
-   نصب سریع و نصب امن
-   setup.sh
-   مراحل نصب
-   DNS و AdGuard Home
-   OpenVPN
-   Nova Server
-   Repair / Check / Backup / Rollback
-   فایل‌ها، سرویس‌ها و پورت‌ها
-   Firewall و امنیت
-   عیب‌یابی
-   محدودیت‌ها
-   FAQ
-   Runbook عملیاتی
-   توسعه و مشارکت
-   لایسنس و upstreamها

------------------------------------------------------------------------

## معرفی

**Alireza Server** یک لایه نصب و یکپارچه‌سازی برای Nova Server است.

هدف پروژه این است که بدون جایگزین کردن فایل‌های اصلی Nova، قابلیت‌های
تکمیلی مدیریت DNS و OpenVPN را کنار پنل اصلی فراهم کند.

installer فعلی Nova را از نسخه/commit مشخص دریافت می‌کند، فایل‌های دانلودی
حساس را با SHA-256 بررسی می‌کند، AdGuard Home را برای DNS اضافه می‌کند و
مدیریت OpenVPN را در کنار Nova قرار می‌دهد.

داده‌های افزونه در مسیرهای جداگانه نگهداری می‌شوند و برای Repair، Check،
Backup و Rollback ابزارهای جداگانه در نظر گرفته شده است.

## امکانات

-   Ubuntu 24.04
-   Debian 12
-   Debian 13
-   amd64/x86_64
-   arm64/aarch64
-   بررسی SHA-256 فایل‌های حساس
-   دانلود HTTPS
-   AdGuard Home
-   DNS TCP/UDP
-   OpenVPN management
-   حساب username/password
-   انقضای حساب
-   سهمیه ترافیک
-   محدودیت دستگاه همزمان
-   profile export
-   TLS-Crypt
-   SQLite جداگانه
-   Repair/Resume
-   Backup
-   Rollback
-   Health Check
-   log نصب
-   installer lock
-   محافظت در برابر overwrite نصب ناشناخته
-   حفظ flow اصلی Nova node enrollment

------------------------------------------------------------------------

## معماری کلی

``` text
Internet / Client
       |
       +--------------------+
       |                    |
       v                    v
   Nova / HTTPS          DNS :53
       |                    |
       v                    v
 Alireza integration    AdGuard Home
       |                    |
       +---- OpenVPN        +---- Upstream DNS
       |
       +---- addon SQLite / certificates / config
```

فایل‌های اصلی Nova قرار نیست با نسخه سفارشی جایگزین شوند. integration از
systemd drop-in و routeهای افزونه استفاده می‌کند و داده‌های افزونه مستقل
نگهداری می‌شوند.

------------------------------------------------------------------------

## پیش‌نیازها

### سیستم‌عامل

-   Ubuntu `24.04`
-   Debian `12`
-   Debian `13`

### معماری

-   `amd64` / `x86_64`
-   `arm64` / `aarch64`

### دسترسی root

``` bash
sudo -i
```

### systemd

سرور باید systemd داشته باشد و `/run/systemd/system` موجود باشد.

### TUN

``` bash
ls -l /dev/net/tun
```

برای OpenVPN باید TUN در VPS فعال باشد.

### اینترنت

installer آنلاین است و برای apt و دریافت artifactهای upstream به اینترنت
نیاز دارد.

------------------------------------------------------------------------

## نصب امن‌تر و قابل بررسی

``` bash
curl -fL --proto "=https" --tlsv1.2 -o /root/alirezaserver-install.sh https://raw.githubusercontent.com/alirezachatgpt97-coder/Alireza-server/main/install.sh
bash -n /root/alirezaserver-install.sh
sha256sum /root/alirezaserver-install.sh
less /root/alirezaserver-install.sh
sudo bash /root/alirezaserver-install.sh
```

> \[!TIP\] در production از release یا commit ثابت و checksum منتشرشده
> همان نسخه استفاده کنید.

------------------------------------------------------------------------

## setup.sh

ریپو یک bootstrap به نام `setup.sh` هم دارد که installer را cache و
verify می‌کند.

``` bash
curl -fsSL https://raw.githubusercontent.com/alirezachatgpt97-coder/Alireza-server/main/setup.sh -o setup.sh
sudo bash setup.sh
```

> \[!WARNING\] قبل از استفاده، مقدار `URL` و `SHA256` داخل setup.sh را
> بررسی کنید تا دقیقاً به همین repository/artifact موردنظر اشاره کنند.

------------------------------------------------------------------------

## مراحل نصب

### 1. Preflight

بررسی root، systemd، OS، معماری و layout.

### 2. Prerequisites

نصب ca-certificates، curl، python3، openssl، openvpn، iptables، iproute2
و dnsutils.

### 3. TUN

بررسی `/dev/net/tun`.

### 4. Ports

بررسی conflict پورت‌های موردنیاز.

### 5. AdGuard

دانلود نسخه pin شده و بررسی checksum.

### 6. Nova

نصب یا بررسی Nova نسخه مورد انتظار.

### 7. Addon

نصب integration files و state.

### 8. Services

تنظیم systemd و سرویس‌ها.

### 9. Verification

بررسی سلامت endpointها و سرویس‌ها.

### 10. Ready

نمایش پیام نهایی موفقیت.

------------------------------------------------------------------------

## متغیرهای محیطی

### DNS_ALLOWED_CIDRS

``` bash
export DNS_ALLOWED_CIDRS="203.0.113.12/32,198.51.100.0/24"
sudo -E bash install.sh
```

### Nova node enrollment

اگر `NOVA_JOIN_URL` یا `NOVA_JOIN_TOKEN` استفاده شود، هر دو باید موجود
باشند.

``` bash
export NOVA_JOIN_URL="YOUR_JOIN_URL"
export NOVA_JOIN_TOKEN="YOUR_JOIN_TOKEN"
sudo -E bash install.sh
```

> \[!IMPORTANT\] token، PIN، password، cookie یا private key را در
> Issue، README یا screenshot عمومی قرار ندهید.

------------------------------------------------------------------------

## DNS و AdGuard Home

-   DNS روی TCP/UDP پورت `53` ارائه می‌شود.
-   listener مدیریتی داخلی AdGuard روی `127.0.0.1:18085` است.
-   Access Settings برای محدودسازی clientها قابل استفاده است.
-   DNS عمومی باز باید با firewall و ACL آگاهانه مدیریت شود.

### بررسی DNS

``` bash
sudo ss -lntup | grep ":53 "
dig @127.0.0.1 example.com
dig @SERVER_IPV4 example.com
```

### بررسی پنل داخلی AdGuard

``` bash
sudo ss -lntp | grep 18085
```

> \[!CAUTION\] Open resolver عمومی می‌تواند مورد سوءاستفاده قرار بگیرد.
> اگر DNS عمومی لازم ندارید، دسترسی را محدود کنید.

------------------------------------------------------------------------

## OpenVPN

قابلیت‌های فعلی شامل TCP/UDP server، حساب username/password، expiry،
quota، concurrent-device cap، profile export و TLS-Crypt است.

ترافیک OpenVPN به‌صورت پیش‌فرض از route IPv4 میزبان خارج می‌شود و خودکار
وارد outbound سفارشی Xray/WARP مربوط به Nova نمی‌شود.

### بررسی

``` bash
systemctl --type=service --all | grep -i openvpn
ip tuntap show
ip -4 route
```

------------------------------------------------------------------------

## Nova Server

installer برای نسخه مشخصی از Nova آماده شده و نصب موجود را از نظر
version/layout بررسی می‌کند.

``` bash
systemctl status nova-agent.service --no-pager
journalctl -u nova-agent.service -n 200 --no-pager
```

------------------------------------------------------------------------

## Repair

``` bash
sudo bash install.sh --repair
```

اجرای مجدد installer نیز برای repair/resume طراحی شده است. قبل از
تغییرات مهم backup بگیرید.

## Check

``` bash
sudo bash install.sh --check
```

## Backup

``` bash
sudo bash install.sh --backup
```

داده‌های backup افزونه طبق installer زیر `/var/backups/alirezaserver`
قرار می‌گیرند.

> \[!IMPORTANT\] Backup اصلی Nova الزاماً دیتای جداگانه addon را پوشش
> نمی‌دهد؛ هر دو backup را در برنامه خود لحاظ کنید.

## Rollback

``` bash
sudo bash install.sh --rollback
```

Rollback را معادل حذف کامل packageها یا پاک‌سازی همه داده‌ها فرض نکنید.
قبل از آن backup بگیرید.

------------------------------------------------------------------------

## مسیرهای مهم

  مسیر                                         کاربرد
  -------------------------------------------- -------------------------
  `/opt/alirezaserver`                         integration و ابزارها
  `/var/lib/alirezaserver`                     state و داده addon
  `/var/log/alirezaserver`                     log نصب
  `/var/backups/alirezaserver`                 backup
  `/etc/systemd/system/nova-agent.service.d`   drop-in integration
  `/opt/nova-node-agent`                       layout مورد انتظار Nova

------------------------------------------------------------------------

## پورت‌ها

  مورد                  مقدار
  --------------------- ----------------------
  DNS                   TCP/UDP `53`
  AdGuard Admin داخلی   `127.0.0.1:18085`
  Nova                  مطابق تنظیم Nova
  OpenVPN               مطابق server/profile

``` bash
sudo ss -lntup
```

------------------------------------------------------------------------

## Firewall

installer اعلام می‌کند تغییرات خودش را در chainهای اختصاصی `ALIREZA_*`
انجام می‌دهد و chainهای اصلی را flush نمی‌کند.

قبل و بعد از نصب snapshot بگیرید:

``` bash
sudo iptables-save > /root/iptables-before.txt
# install / repair
sudo iptables-save > /root/iptables-after.txt
diff -u /root/iptables-before.txt /root/iptables-after.txt
```

Firewall شرکت VPS خارج از کنترل installer است.

------------------------------------------------------------------------

## امنیت

### کنترل‌های مثبت موجود

-   `set -Eeuo pipefail`
-   `umask 077`
-   OS/architecture checks
-   pinned upstream artifacts
-   SHA-256 verification
-   installer lock
-   root-only logs
-   جلوگیری از overwrite نصب ناشناخته
-   loopback-only بودن listener مدیریتی داخلی AdGuard

### وظایف مدیر سرور

-   SSH key استفاده کنید.
-   password login را در صورت امکان ببندید.
-   firewall provider را تنظیم کنید.
-   DNS عمومی را فقط در صورت نیاز باز کنید.
-   backup خارج از سرور داشته باشید.
-   tokenها را rotate کنید.
-   packageهای امنیتی را به‌روز کنید.
-   log و disk و memory را مانیتور کنید.
-   قبل از upgrade snapshot بگیرید.

------------------------------------------------------------------------

## عیب‌یابی

### مشکل 1: root لازم است

با `sudo -i` وارد root shell شوید.

``` bash
systemctl --failed --no-pager
journalctl -p warning -b --no-pager
ss -lntup
ip -4 route
df -h
free -h
```

### مشکل 2: systemd وجود ندارد

این installer برای VPS لینوکسی دارای systemd است.

``` bash
systemctl --failed --no-pager
journalctl -p warning -b --no-pager
ss -lntup
ip -4 route
df -h
free -h
```

### مشکل 3: OS رد می‌شود

فقط Ubuntu 24.04 یا Debian 12/13 استفاده کنید.

``` bash
systemctl --failed --no-pager
journalctl -p warning -b --no-pager
ss -lntup
ip -4 route
df -h
free -h
```

### مشکل 4: CPU رد می‌شود

amd64 یا arm64 لازم است.

``` bash
systemctl --failed --no-pager
journalctl -p warning -b --no-pager
ss -lntup
ip -4 route
df -h
free -h
```

### مشکل 5: TUN وجود ندارد

TUN را از provider فعال کنید.

``` bash
systemctl --failed --no-pager
journalctl -p warning -b --no-pager
ss -lntup
ip -4 route
df -h
free -h
```

### مشکل 6: پورت 53 اشغال است

با `ss -lntup | grep :53` سرویس conflict را پیدا کنید.

``` bash
systemctl --failed --no-pager
journalctl -p warning -b --no-pager
ss -lntup
ip -4 route
df -h
free -h
```

### مشکل 7: پورت 18085 اشغال است

listener محلی conflict را شناسایی کنید.

``` bash
systemctl --failed --no-pager
journalctl -p warning -b --no-pager
ss -lntup
ip -4 route
df -h
free -h
```

### مشکل 8: AdGuard مستقل وجود دارد

installer برای جلوگیری از overwrite می‌تواند متوقف شود.

``` bash
systemctl --failed --no-pager
journalctl -p warning -b --no-pager
ss -lntup
ip -4 route
df -h
free -h
```

### مشکل 9: checksum mismatch

فایل اجرا نمی‌شود؛ URL/version و دانلود را بررسی کنید.

``` bash
systemctl --failed --no-pager
journalctl -p warning -b --no-pager
ss -lntup
ip -4 route
df -h
free -h
```

### مشکل 10: GitHub در دسترس نیست

DNS، route، TLS و firewall خروجی را بررسی کنید.

``` bash
systemctl --failed --no-pager
journalctl -p warning -b --no-pager
ss -lntup
ip -4 route
df -h
free -h
```

### مشکل 11: apt lock است

منتظر پایان apt/dpkg دیگر بمانید.

``` bash
systemctl --failed --no-pager
journalctl -p warning -b --no-pager
ss -lntup
ip -4 route
df -h
free -h
```

### مشکل 12: Nova بالا نمی‌آید

status و journal سرویس Nova را بررسی کنید.

``` bash
systemctl --failed --no-pager
journalctl -p warning -b --no-pager
ss -lntup
ip -4 route
df -h
free -h
```

### مشکل 13: نسخه Nova متفاوت است

بدون بررسی سازگاری force نکنید.

``` bash
systemctl --failed --no-pager
journalctl -p warning -b --no-pager
ss -lntup
ip -4 route
df -h
free -h
```

### مشکل 14: DNS محلی جواب نمی‌دهد

listener و config/log AdGuard را بررسی کنید.

``` bash
systemctl --failed --no-pager
journalctl -p warning -b --no-pager
ss -lntup
ip -4 route
df -h
free -h
```

### مشکل 15: DNS خارجی جواب نمی‌دهد

firewall سیستم، provider و Access Settings را بررسی کنید.

``` bash
systemctl --failed --no-pager
journalctl -p warning -b --no-pager
ss -lntup
ip -4 route
df -h
free -h
```

### مشکل 16: OpenVPN وصل نمی‌شود

TUN، port، protocol، profile و firewall را بررسی کنید.

``` bash
systemctl --failed --no-pager
journalctl -p warning -b --no-pager
ss -lntup
ip -4 route
df -h
free -h
```

### مشکل 17: VPN اینترنت ندارد

route، NAT، forwarding و iptables را بررسی کنید.

``` bash
systemctl --failed --no-pager
journalctl -p warning -b --no-pager
ss -lntup
ip -4 route
df -h
free -h
```

### مشکل 18: Repair fail می‌شود

آخرین log زیر `/var/log/alirezaserver` را بررسی کنید.

``` bash
systemctl --failed --no-pager
journalctl -p warning -b --no-pager
ss -lntup
ip -4 route
df -h
free -h
```

### مشکل 19: نصب نیمه‌کاره است

همان installer را دوباره برای resume اجرا کنید.

``` bash
systemctl --failed --no-pager
journalctl -p warning -b --no-pager
ss -lntup
ip -4 route
df -h
free -h
```

### مشکل 20: Backup fail می‌شود

disk، permission و backup.py را بررسی کنید.

``` bash
systemctl --failed --no-pager
journalctl -p warning -b --no-pager
ss -lntup
ip -4 route
df -h
free -h
```

### مشکل 21: دیسک پر است

`df -h` و log/backupها را بررسی کنید.

``` bash
systemctl --failed --no-pager
journalctl -p warning -b --no-pager
ss -lntup
ip -4 route
df -h
free -h
```

### مشکل 22: RAM کم است

`free -h` و OOM logها را بررسی کنید.

``` bash
systemctl --failed --no-pager
journalctl -p warning -b --no-pager
ss -lntup
ip -4 route
df -h
free -h
```

### مشکل 23: بعد reboot مشکل است

journal boot و status سرویس‌ها را بررسی کنید.

``` bash
systemctl --failed --no-pager
journalctl -p warning -b --no-pager
ss -lntup
ip -4 route
df -h
free -h
```

### مشکل 24: DNS کند است

latency upstream و load سرور را بررسی کنید.

``` bash
systemctl --failed --no-pager
journalctl -p warning -b --no-pager
ss -lntup
ip -4 route
df -h
free -h
```

### مشکل 25: CPU بالا است

با `top` و `ps` سرویس مصرف‌کننده را پیدا کنید.

``` bash
systemctl --failed --no-pager
journalctl -p warning -b --no-pager
ss -lntup
ip -4 route
df -h
free -h
```

------------------------------------------------------------------------

## چک‌لیست قبل از نصب

-   [ ] backup گرفته‌ام.
-   [ ] snapshot VPS گرفته‌ام.
-   [ ] OS پشتیبانی می‌شود.
-   [ ] CPU پشتیبانی می‌شود.
-   [ ] root دارم.
-   [ ] TUN فعال است.
-   [ ] GitHub در دسترس است.
-   [ ] وضعیت پورت 53 را می‌دانم.
-   [ ] firewall provider را بررسی کرده‌ام.
-   [ ] iptables را ذخیره کرده‌ام.
-   [ ] روش rollback را خوانده‌ام.
-   [ ] maintenance window مشخص است.
-   [ ] secretها را عمومی نمی‌کنم.

## چک‌لیست بعد از نصب

-   [ ] `ALIREZASERVER READY` دیده شده.
-   [ ] Nova فعال است.
-   [ ] پنل باز می‌شود.
-   [ ] owner auth کار می‌کند.
-   [ ] DNS محلی تست شده.
-   [ ] DNS خارجی در صورت نیاز تست شده.
-   [ ] Access Settings بررسی شده.
-   [ ] OpenVPN با client واقعی تست شده.
-   [ ] route و NAT بررسی شده.
-   [ ] firewall بررسی شده.
-   [ ] backup گرفته شده.
-   [ ] logها بررسی شده.
-   [ ] reboot کنترل‌شده در محیط خودم تست شده.

------------------------------------------------------------------------

## محدودیت‌ها

-   تست کامل Linux VPN client در verification فعلی به‌عنوان تضمین
    production اعلام نشده است.
-   تست کامل multi-node اعلام نشده است.
-   تست reboot روی همه محیط‌ها اعلام نشده است.
-   تست kernel/firewall روی همه providerها اعلام نشده است.
-   تست load واقعی VPS یک‌گیگ به‌عنوان تضمین ظرفیت اعلام نشده است.
-   bug-free بودن یا unlimited load تضمین نمی‌شود.

> \[!WARNING\] ابتدا روی staging/VPS آزمایشی تست کنید. شبکه به provider،
> kernel، firewall، route و configuration واقعی وابسته است.

------------------------------------------------------------------------

## FAQ

### 1. آیا نصب یک‌خطی دارد؟

بله؛ دستور ابتدای README.

### 2. آیا root لازم است؟

بله.

### 3. Ubuntu 22.04؟

در installer فعلی پشتیبانی نمی‌شود.

### 4. Debian 11؟

پشتیبانی نمی‌شود.

### 5. ARM؟

arm64/aarch64 پشتیبانی می‌شود.

### 6. DNS روی چه پورتی است؟

TCP/UDP 53.

### 7. AdGuard admin داخلی؟

127.0.0.1:18085.

### 8. DNS می‌تواند عمومی باشد؟

بله؛ ACL/firewall را تنظیم کنید.

### 9. OpenVPN از WARP/Xray رد می‌شود؟

نه به‌صورت خودکار.

### 10. Repair داده را حفظ می‌کند؟

برای نصب شناخته‌شده با هدف حفظ state طراحی شده، ولی backup لازم است.

### 11. Backup Nova کافی است؟

برای addon data خیر.

### 12. Rollback چیست؟

بازگرداندن launch اصلی Nova و غیرفعال‌کردن integration؛ حذف کامل سیستم
نیست.

### 13. اگر نصب fail شد VPS را reinstall کنم؟

اول log و repair/resume را امتحان کنید.

### 14. چرا version Nova بررسی می‌شود؟

برای جلوگیری از integration روی layout ناسازگار.

### 15. چرا checksum؟

برای تأیید artifact دانلودشده.

### 16. curl\|bash امن‌ترین است؟

خیر؛ سریع‌ترین است. روش دانلود/بررسی برای production بهتر است.

### 17. log کجاست؟

`/var/log/alirezaserver`.

### 18. backup کجاست؟

`/var/backups/alirezaserver`.

### 19. state کجاست؟

`/var/lib/alirezaserver`.

### 20. integration کجاست؟

`/opt/alirezaserver`.

### 21. iptables flush می‌شود؟

طبق توضیح installer، chainهای اصلی flush نمی‌شوند.

### 22. provider firewall تغییر می‌کند؟

خیر.

### 23. DNS فقط برای IP خاص؟

با DNS_ALLOWED_CIDRS و Access Settings قابل محدودسازی است.

### 24. installer دوباره قابل اجراست؟

بله، برای repair/resume.

### 25. قبل upgrade backup؟

بله.

### 26. پورت 53 اشغال باشد؟

conflict را رفع کنید؛ installer نباید سرویس موجود را بی‌صدا قربانی کند.

### 27. Docker؟

هدف فعلی systemd VPS است.

### 28. shared hosting؟

مناسب نیست؛ root/TUN/network control لازم است.

### 29. سلامت Nova؟

systemctl status و journal.

### 30. listenerها؟

`ss -lntup`.

### 31. route؟

`ip -4 route`.

### 32. firewall snapshot؟

`iptables-save`.

------------------------------------------------------------------------

## Command Reference

### Install

``` bash
sudo bash install.sh
```

### Repair

``` bash
sudo bash install.sh --repair
```

### Check

``` bash
sudo bash install.sh --check
```

### Backup

``` bash
sudo bash install.sh --backup
```

### Rollback

``` bash
sudo bash install.sh --rollback
```

### Help

``` bash
sudo bash install.sh --help
```

### Nova status

``` bash
systemctl status nova-agent.service --no-pager
```

### Nova logs

``` bash
journalctl -u nova-agent.service -n 200 --no-pager
```

### Listeners

``` bash
ss -lntup
```

### Routes

``` bash
ip -4 route
```

### Addresses

``` bash
ip -4 addr
```

### TUN

``` bash
ls -l /dev/net/tun
```

### Disk

``` bash
df -h
```

### Memory

``` bash
free -h
```

### Failed services

``` bash
systemctl --failed --no-pager
```

### Firewall

``` bash
iptables-save
```

------------------------------------------------------------------------

## Runbook عملیاتی

### Runbook 1: قبل از maintenance

-   [ ] وضعیت سرویس‌ها ثبت شده است.
-   [ ] تغییرات اخیر مشخص است.
-   [ ] backup/snapshot موجود است.
-   [ ] کنسول provider در دسترس است.
-   [ ] listenerها بررسی شده‌اند.
-   [ ] routeها بررسی شده‌اند.
-   [ ] logهای مرتبط ذخیره شده‌اند.
-   [ ] health check بعد از تغییر برنامه‌ریزی شده است.
-   [ ] معیار rollback مشخص است.

### Runbook 2: شروع maintenance

-   [ ] وضعیت سرویس‌ها ثبت شده است.
-   [ ] تغییرات اخیر مشخص است.
-   [ ] backup/snapshot موجود است.
-   [ ] کنسول provider در دسترس است.
-   [ ] listenerها بررسی شده‌اند.
-   [ ] routeها بررسی شده‌اند.
-   [ ] logهای مرتبط ذخیره شده‌اند.
-   [ ] health check بعد از تغییر برنامه‌ریزی شده است.
-   [ ] معیار rollback مشخص است.

### Runbook 3: بررسی شبکه

-   [ ] وضعیت سرویس‌ها ثبت شده است.
-   [ ] تغییرات اخیر مشخص است.
-   [ ] backup/snapshot موجود است.
-   [ ] کنسول provider در دسترس است.
-   [ ] listenerها بررسی شده‌اند.
-   [ ] routeها بررسی شده‌اند.
-   [ ] logهای مرتبط ذخیره شده‌اند.
-   [ ] health check بعد از تغییر برنامه‌ریزی شده است.
-   [ ] معیار rollback مشخص است.

### Runbook 4: بررسی DNS

-   [ ] وضعیت سرویس‌ها ثبت شده است.
-   [ ] تغییرات اخیر مشخص است.
-   [ ] backup/snapshot موجود است.
-   [ ] کنسول provider در دسترس است.
-   [ ] listenerها بررسی شده‌اند.
-   [ ] routeها بررسی شده‌اند.
-   [ ] logهای مرتبط ذخیره شده‌اند.
-   [ ] health check بعد از تغییر برنامه‌ریزی شده است.
-   [ ] معیار rollback مشخص است.

### Runbook 5: بررسی Nova

-   [ ] وضعیت سرویس‌ها ثبت شده است.
-   [ ] تغییرات اخیر مشخص است.
-   [ ] backup/snapshot موجود است.
-   [ ] کنسول provider در دسترس است.
-   [ ] listenerها بررسی شده‌اند.
-   [ ] routeها بررسی شده‌اند.
-   [ ] logهای مرتبط ذخیره شده‌اند.
-   [ ] health check بعد از تغییر برنامه‌ریزی شده است.
-   [ ] معیار rollback مشخص است.

### Runbook 6: بررسی OpenVPN

-   [ ] وضعیت سرویس‌ها ثبت شده است.
-   [ ] تغییرات اخیر مشخص است.
-   [ ] backup/snapshot موجود است.
-   [ ] کنسول provider در دسترس است.
-   [ ] listenerها بررسی شده‌اند.
-   [ ] routeها بررسی شده‌اند.
-   [ ] logهای مرتبط ذخیره شده‌اند.
-   [ ] health check بعد از تغییر برنامه‌ریزی شده است.
-   [ ] معیار rollback مشخص است.

### Runbook 7: بررسی firewall

-   [ ] وضعیت سرویس‌ها ثبت شده است.
-   [ ] تغییرات اخیر مشخص است.
-   [ ] backup/snapshot موجود است.
-   [ ] کنسول provider در دسترس است.
-   [ ] listenerها بررسی شده‌اند.
-   [ ] routeها بررسی شده‌اند.
-   [ ] logهای مرتبط ذخیره شده‌اند.
-   [ ] health check بعد از تغییر برنامه‌ریزی شده است.
-   [ ] معیار rollback مشخص است.

### Runbook 8: بررسی دیسک

-   [ ] وضعیت سرویس‌ها ثبت شده است.
-   [ ] تغییرات اخیر مشخص است.
-   [ ] backup/snapshot موجود است.
-   [ ] کنسول provider در دسترس است.
-   [ ] listenerها بررسی شده‌اند.
-   [ ] routeها بررسی شده‌اند.
-   [ ] logهای مرتبط ذخیره شده‌اند.
-   [ ] health check بعد از تغییر برنامه‌ریزی شده است.
-   [ ] معیار rollback مشخص است.

### Runbook 9: بررسی حافظه

-   [ ] وضعیت سرویس‌ها ثبت شده است.
-   [ ] تغییرات اخیر مشخص است.
-   [ ] backup/snapshot موجود است.
-   [ ] کنسول provider در دسترس است.
-   [ ] listenerها بررسی شده‌اند.
-   [ ] routeها بررسی شده‌اند.
-   [ ] logهای مرتبط ذخیره شده‌اند.
-   [ ] health check بعد از تغییر برنامه‌ریزی شده است.
-   [ ] معیار rollback مشخص است.

### Runbook 10: بررسی log

-   [ ] وضعیت سرویس‌ها ثبت شده است.
-   [ ] تغییرات اخیر مشخص است.
-   [ ] backup/snapshot موجود است.
-   [ ] کنسول provider در دسترس است.
-   [ ] listenerها بررسی شده‌اند.
-   [ ] routeها بررسی شده‌اند.
-   [ ] logهای مرتبط ذخیره شده‌اند.
-   [ ] health check بعد از تغییر برنامه‌ریزی شده است.
-   [ ] معیار rollback مشخص است.

### Runbook 11: قبل از repair

-   [ ] وضعیت سرویس‌ها ثبت شده است.
-   [ ] تغییرات اخیر مشخص است.
-   [ ] backup/snapshot موجود است.
-   [ ] کنسول provider در دسترس است.
-   [ ] listenerها بررسی شده‌اند.
-   [ ] routeها بررسی شده‌اند.
-   [ ] logهای مرتبط ذخیره شده‌اند.
-   [ ] health check بعد از تغییر برنامه‌ریزی شده است.
-   [ ] معیار rollback مشخص است.

### Runbook 12: بعد از repair

-   [ ] وضعیت سرویس‌ها ثبت شده است.
-   [ ] تغییرات اخیر مشخص است.
-   [ ] backup/snapshot موجود است.
-   [ ] کنسول provider در دسترس است.
-   [ ] listenerها بررسی شده‌اند.
-   [ ] routeها بررسی شده‌اند.
-   [ ] logهای مرتبط ذخیره شده‌اند.
-   [ ] health check بعد از تغییر برنامه‌ریزی شده است.
-   [ ] معیار rollback مشخص است.

### Runbook 13: قبل از backup

-   [ ] وضعیت سرویس‌ها ثبت شده است.
-   [ ] تغییرات اخیر مشخص است.
-   [ ] backup/snapshot موجود است.
-   [ ] کنسول provider در دسترس است.
-   [ ] listenerها بررسی شده‌اند.
-   [ ] routeها بررسی شده‌اند.
-   [ ] logهای مرتبط ذخیره شده‌اند.
-   [ ] health check بعد از تغییر برنامه‌ریزی شده است.
-   [ ] معیار rollback مشخص است.

### Runbook 14: بعد از backup

-   [ ] وضعیت سرویس‌ها ثبت شده است.
-   [ ] تغییرات اخیر مشخص است.
-   [ ] backup/snapshot موجود است.
-   [ ] کنسول provider در دسترس است.
-   [ ] listenerها بررسی شده‌اند.
-   [ ] routeها بررسی شده‌اند.
-   [ ] logهای مرتبط ذخیره شده‌اند.
-   [ ] health check بعد از تغییر برنامه‌ریزی شده است.
-   [ ] معیار rollback مشخص است.

### Runbook 15: قبل از rollback

-   [ ] وضعیت سرویس‌ها ثبت شده است.
-   [ ] تغییرات اخیر مشخص است.
-   [ ] backup/snapshot موجود است.
-   [ ] کنسول provider در دسترس است.
-   [ ] listenerها بررسی شده‌اند.
-   [ ] routeها بررسی شده‌اند.
-   [ ] logهای مرتبط ذخیره شده‌اند.
-   [ ] health check بعد از تغییر برنامه‌ریزی شده است.
-   [ ] معیار rollback مشخص است.

### Runbook 16: بعد از rollback

-   [ ] وضعیت سرویس‌ها ثبت شده است.
-   [ ] تغییرات اخیر مشخص است.
-   [ ] backup/snapshot موجود است.
-   [ ] کنسول provider در دسترس است.
-   [ ] listenerها بررسی شده‌اند.
-   [ ] routeها بررسی شده‌اند.
-   [ ] logهای مرتبط ذخیره شده‌اند.
-   [ ] health check بعد از تغییر برنامه‌ریزی شده است.
-   [ ] معیار rollback مشخص است.

### Runbook 17: قبل از reboot

-   [ ] وضعیت سرویس‌ها ثبت شده است.
-   [ ] تغییرات اخیر مشخص است.
-   [ ] backup/snapshot موجود است.
-   [ ] کنسول provider در دسترس است.
-   [ ] listenerها بررسی شده‌اند.
-   [ ] routeها بررسی شده‌اند.
-   [ ] logهای مرتبط ذخیره شده‌اند.
-   [ ] health check بعد از تغییر برنامه‌ریزی شده است.
-   [ ] معیار rollback مشخص است.

### Runbook 18: بعد از reboot

-   [ ] وضعیت سرویس‌ها ثبت شده است.
-   [ ] تغییرات اخیر مشخص است.
-   [ ] backup/snapshot موجود است.
-   [ ] کنسول provider در دسترس است.
-   [ ] listenerها بررسی شده‌اند.
-   [ ] routeها بررسی شده‌اند.
-   [ ] logهای مرتبط ذخیره شده‌اند.
-   [ ] health check بعد از تغییر برنامه‌ریزی شده است.
-   [ ] معیار rollback مشخص است.

### Runbook 19: قبل از upgrade

-   [ ] وضعیت سرویس‌ها ثبت شده است.
-   [ ] تغییرات اخیر مشخص است.
-   [ ] backup/snapshot موجود است.
-   [ ] کنسول provider در دسترس است.
-   [ ] listenerها بررسی شده‌اند.
-   [ ] routeها بررسی شده‌اند.
-   [ ] logهای مرتبط ذخیره شده‌اند.
-   [ ] health check بعد از تغییر برنامه‌ریزی شده است.
-   [ ] معیار rollback مشخص است.

### Runbook 20: بعد از upgrade

-   [ ] وضعیت سرویس‌ها ثبت شده است.
-   [ ] تغییرات اخیر مشخص است.
-   [ ] backup/snapshot موجود است.
-   [ ] کنسول provider در دسترس است.
-   [ ] listenerها بررسی شده‌اند.
-   [ ] routeها بررسی شده‌اند.
-   [ ] logهای مرتبط ذخیره شده‌اند.
-   [ ] health check بعد از تغییر برنامه‌ریزی شده است.
-   [ ] معیار rollback مشخص است.

### Runbook 21: بررسی certificateها

-   [ ] وضعیت سرویس‌ها ثبت شده است.
-   [ ] تغییرات اخیر مشخص است.
-   [ ] backup/snapshot موجود است.
-   [ ] کنسول provider در دسترس است.
-   [ ] listenerها بررسی شده‌اند.
-   [ ] routeها بررسی شده‌اند.
-   [ ] logهای مرتبط ذخیره شده‌اند.
-   [ ] health check بعد از تغییر برنامه‌ریزی شده است.
-   [ ] معیار rollback مشخص است.

### Runbook 22: بررسی accountها

-   [ ] وضعیت سرویس‌ها ثبت شده است.
-   [ ] تغییرات اخیر مشخص است.
-   [ ] backup/snapshot موجود است.
-   [ ] کنسول provider در دسترس است.
-   [ ] listenerها بررسی شده‌اند.
-   [ ] routeها بررسی شده‌اند.
-   [ ] logهای مرتبط ذخیره شده‌اند.
-   [ ] health check بعد از تغییر برنامه‌ریزی شده است.
-   [ ] معیار rollback مشخص است.

### Runbook 23: بررسی quota

-   [ ] وضعیت سرویس‌ها ثبت شده است.
-   [ ] تغییرات اخیر مشخص است.
-   [ ] backup/snapshot موجود است.
-   [ ] کنسول provider در دسترس است.
-   [ ] listenerها بررسی شده‌اند.
-   [ ] routeها بررسی شده‌اند.
-   [ ] logهای مرتبط ذخیره شده‌اند.
-   [ ] health check بعد از تغییر برنامه‌ریزی شده است.
-   [ ] معیار rollback مشخص است.

### Runbook 24: بررسی provider firewall

-   [ ] وضعیت سرویس‌ها ثبت شده است.
-   [ ] تغییرات اخیر مشخص است.
-   [ ] backup/snapshot موجود است.
-   [ ] کنسول provider در دسترس است.
-   [ ] listenerها بررسی شده‌اند.
-   [ ] routeها بررسی شده‌اند.
-   [ ] logهای مرتبط ذخیره شده‌اند.
-   [ ] health check بعد از تغییر برنامه‌ریزی شده است.
-   [ ] معیار rollback مشخص است.

### Runbook 25: بررسی incident

-   [ ] وضعیت سرویس‌ها ثبت شده است.
-   [ ] تغییرات اخیر مشخص است.
-   [ ] backup/snapshot موجود است.
-   [ ] کنسول provider در دسترس است.
-   [ ] listenerها بررسی شده‌اند.
-   [ ] routeها بررسی شده‌اند.
-   [ ] logهای مرتبط ذخیره شده‌اند.
-   [ ] health check بعد از تغییر برنامه‌ریزی شده است.
-   [ ] معیار rollback مشخص است.

### Runbook 26: پایان maintenance

-   [ ] وضعیت سرویس‌ها ثبت شده است.
-   [ ] تغییرات اخیر مشخص است.
-   [ ] backup/snapshot موجود است.
-   [ ] کنسول provider در دسترس است.
-   [ ] listenerها بررسی شده‌اند.
-   [ ] routeها بررسی شده‌اند.
-   [ ] logهای مرتبط ذخیره شده‌اند.
-   [ ] health check بعد از تغییر برنامه‌ریزی شده است.
-   [ ] معیار rollback مشخص است.

------------------------------------------------------------------------

## Release Checklist

-   [ ] 01. نسخه installer و README هماهنگ است.
-   [ ] 02. URLها بررسی شده‌اند.
-   [ ] 03. checksumها بررسی شده‌اند.
-   [ ] 04. bash syntax بررسی شده.
-   [ ] 05. fresh install تست شده.
-   [ ] 06. repair تست شده.
-   [ ] 07. backup تست شده.
-   [ ] 08. rollback تست شده.
-   [ ] 09. DNS TCP تست شده.
-   [ ] 10. DNS UDP تست شده.
-   [ ] 11. OpenVPN client واقعی تست شده.
-   [ ] 12. Nova سالم است.
-   [ ] 13. permissions بررسی شده.
-   [ ] 14. logها secret ندارند.
-   [ ] 15. firewall diff بررسی شده.
-   [ ] 16. محدودیت‌ها مستند شده.
-   [ ] 17. reboot تست شده.
-   [ ] 18. disk usage بررسی شده.
-   [ ] 19. memory usage بررسی شده.
-   [ ] 20. provider firewall مستند شده.
-   [ ] 21. نسخه installer و README هماهنگ است.
-   [ ] 22. URLها بررسی شده‌اند.
-   [ ] 23. checksumها بررسی شده‌اند.
-   [ ] 24. bash syntax بررسی شده.
-   [ ] 25. fresh install تست شده.
-   [ ] 26. repair تست شده.
-   [ ] 27. backup تست شده.
-   [ ] 28. rollback تست شده.
-   [ ] 29. DNS TCP تست شده.
-   [ ] 30. DNS UDP تست شده.
-   [ ] 31. OpenVPN client واقعی تست شده.
-   [ ] 32. Nova سالم است.
-   [ ] 33. permissions بررسی شده.
-   [ ] 34. logها secret ندارند.
-   [ ] 35. firewall diff بررسی شده.
-   [ ] 36. محدودیت‌ها مستند شده.
-   [ ] 37. reboot تست شده.
-   [ ] 38. disk usage بررسی شده.
-   [ ] 39. memory usage بررسی شده.
-   [ ] 40. provider firewall مستند شده.
-   [ ] 41. نسخه installer و README هماهنگ است.
-   [ ] 42. URLها بررسی شده‌اند.
-   [ ] 43. checksumها بررسی شده‌اند.
-   [ ] 44. bash syntax بررسی شده.
-   [ ] 45. fresh install تست شده.
-   [ ] 46. repair تست شده.
-   [ ] 47. backup تست شده.
-   [ ] 48. rollback تست شده.
-   [ ] 49. DNS TCP تست شده.
-   [ ] 50. DNS UDP تست شده.
-   [ ] 51. OpenVPN client واقعی تست شده.
-   [ ] 52. Nova سالم است.
-   [ ] 53. permissions بررسی شده.
-   [ ] 54. logها secret ندارند.
-   [ ] 55. firewall diff بررسی شده.
-   [ ] 56. محدودیت‌ها مستند شده.
-   [ ] 57. reboot تست شده.
-   [ ] 58. disk usage بررسی شده.
-   [ ] 59. memory usage بررسی شده.
-   [ ] 60. provider firewall مستند شده.
-   [ ] 61. نسخه installer و README هماهنگ است.
-   [ ] 62. URLها بررسی شده‌اند.
-   [ ] 63. checksumها بررسی شده‌اند.
-   [ ] 64. bash syntax بررسی شده.
-   [ ] 65. fresh install تست شده.
-   [ ] 66. repair تست شده.
-   [ ] 67. backup تست شده.
-   [ ] 68. rollback تست شده.
-   [ ] 69. DNS TCP تست شده.
-   [ ] 70. DNS UDP تست شده.
-   [ ] 71. OpenVPN client واقعی تست شده.
-   [ ] 72. Nova سالم است.
-   [ ] 73. permissions بررسی شده.
-   [ ] 74. logها secret ندارند.
-   [ ] 75. firewall diff بررسی شده.
-   [ ] 76. محدودیت‌ها مستند شده.
-   [ ] 77. reboot تست شده.
-   [ ] 78. disk usage بررسی شده.
-   [ ] 79. memory usage بررسی شده.
-   [ ] 80. provider firewall مستند شده.

------------------------------------------------------------------------

## توسعه و مشارکت

قبل از Pull Request:

``` bash
bash -n install.sh
bash -n setup.sh
```

در PR توضیح دهید مشکل چیست، چه رفتاری تغییر کرده، روی چه OS/architecture
تست شده، آیا firewall/database migration دارد و آیا repair/rollback تست
شده است.

اصول پیشنهادی:

-   artifact اجرایی را pin کنید.
-   checksum را verify کنید.
-   secret را log نکنید.
-   failure را واضح گزارش کنید.
-   نصب ناشناخته را overwrite نکنید.
-   repair را idempotent نگه دارید.
-   rollback را تست کنید.
-   firewall change را محدود نگه دارید.
-   permission فایل حساس را حداقلی نگه دارید.
-   تغییر شبکه را مستند کنید.

------------------------------------------------------------------------

## لایسنس و upstreamها

Nova Server، AdGuard Home، OpenVPN و packageهای سیستم مجوزهای مستقل خود
را حفظ می‌کنند.

طبق NOTICE تعبیه‌شده در installer، ماژول‌های جدید integration با
GPL-3.0-or-later معرفی شده‌اند و بخشی از conventionهای OpenVPN از
`Sir-MmD/vpn-ui` اقتباس شده است.

برای جزئیات حقوقی، NOTICE تولیدشده و licenseهای upstream را مطالعه کنید.

------------------------------------------------------------------------

## لینک‌های پروژه

-   Repository:
    `https://github.com/alirezachatgpt97-coder/Alireza-server`
-   Installer:
    `https://raw.githubusercontent.com/alirezachatgpt97-coder/Alireza-server/main/install.sh`
-   Bootstrap:
    `https://raw.githubusercontent.com/alirezachatgpt97-coder/Alireza-server/main/setup.sh`
-   Videos: `https://www.youtube.com/@Alirezacoder12`

------------------------------------------------------------------------

## گزارش باگ

اطلاعات غیرحساس زیر را ارسال کنید:

``` text
OS:
Architecture:
Installer version:
Fresh install or repair:
Failed stage:
Sanitized log:
Nova status:
AdGuard status:
OpenVPN status:
Expected behavior:
Actual behavior:
```

password، token، private key، cookie، backup archive یا اطلاعات کاربران
را عمومی منتشر نکنید.

------------------------------------------------------------------------

## جمع‌بندی

برای نصب سریع:

``` bash
bash <(curl -fsSL https://raw.githubusercontent.com/alirezachatgpt97-coder/Alireza-server/main/install.sh)
```

برای production، نسخه pin‌شده را دانلود، checksum/diff را بررسی، backup
تهیه و ابتدا روی staging تست کنید.

**پایان نصب موفق با `ALIREZASERVER READY` مشخص می‌شود.**

------------------------------------------------------------------------

## پیوست A: چک‌های عملیاتی تفصیلی

### چرخه بررسی 1

#### سرویس‌های failed

``` bash
systemctl --failed --no-pager
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### وضعیت Nova

``` bash
systemctl is-active nova-agent.service
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### لاگ Nova

``` bash
journalctl -u nova-agent.service -n 100 --no-pager
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### پورت‌ها

``` bash
ss -lntup
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### IPv4

``` bash
ip -4 addr
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Route

``` bash
ip -4 route
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### TUN

``` bash
ls -l /dev/net/tun
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Disk

``` bash
df -h
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Inodes

``` bash
df -i
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Memory

``` bash
free -h
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Kernel errors

``` bash
journalctl -k -p warning -b --no-pager
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### DNS local

``` bash
dig @127.0.0.1 example.com
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Firewall

``` bash
iptables-save
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Processes

``` bash
ps aux --sort=-%mem | head
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Load

``` bash
uptime
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Time

``` bash
timedatectl status
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

### چرخه بررسی 2

#### سرویس‌های failed

``` bash
systemctl --failed --no-pager
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### وضعیت Nova

``` bash
systemctl is-active nova-agent.service
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### لاگ Nova

``` bash
journalctl -u nova-agent.service -n 100 --no-pager
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### پورت‌ها

``` bash
ss -lntup
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### IPv4

``` bash
ip -4 addr
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Route

``` bash
ip -4 route
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### TUN

``` bash
ls -l /dev/net/tun
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Disk

``` bash
df -h
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Inodes

``` bash
df -i
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Memory

``` bash
free -h
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Kernel errors

``` bash
journalctl -k -p warning -b --no-pager
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### DNS local

``` bash
dig @127.0.0.1 example.com
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Firewall

``` bash
iptables-save
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Processes

``` bash
ps aux --sort=-%mem | head
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Load

``` bash
uptime
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Time

``` bash
timedatectl status
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

### چرخه بررسی 3

#### سرویس‌های failed

``` bash
systemctl --failed --no-pager
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### وضعیت Nova

``` bash
systemctl is-active nova-agent.service
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### لاگ Nova

``` bash
journalctl -u nova-agent.service -n 100 --no-pager
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### پورت‌ها

``` bash
ss -lntup
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### IPv4

``` bash
ip -4 addr
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Route

``` bash
ip -4 route
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### TUN

``` bash
ls -l /dev/net/tun
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Disk

``` bash
df -h
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Inodes

``` bash
df -i
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Memory

``` bash
free -h
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Kernel errors

``` bash
journalctl -k -p warning -b --no-pager
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### DNS local

``` bash
dig @127.0.0.1 example.com
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Firewall

``` bash
iptables-save
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Processes

``` bash
ps aux --sort=-%mem | head
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Load

``` bash
uptime
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Time

``` bash
timedatectl status
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

### چرخه بررسی 4

#### سرویس‌های failed

``` bash
systemctl --failed --no-pager
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### وضعیت Nova

``` bash
systemctl is-active nova-agent.service
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### لاگ Nova

``` bash
journalctl -u nova-agent.service -n 100 --no-pager
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### پورت‌ها

``` bash
ss -lntup
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### IPv4

``` bash
ip -4 addr
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Route

``` bash
ip -4 route
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### TUN

``` bash
ls -l /dev/net/tun
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Disk

``` bash
df -h
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Inodes

``` bash
df -i
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Memory

``` bash
free -h
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Kernel errors

``` bash
journalctl -k -p warning -b --no-pager
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### DNS local

``` bash
dig @127.0.0.1 example.com
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Firewall

``` bash
iptables-save
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Processes

``` bash
ps aux --sort=-%mem | head
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Load

``` bash
uptime
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Time

``` bash
timedatectl status
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

### چرخه بررسی 5

#### سرویس‌های failed

``` bash
systemctl --failed --no-pager
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### وضعیت Nova

``` bash
systemctl is-active nova-agent.service
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### لاگ Nova

``` bash
journalctl -u nova-agent.service -n 100 --no-pager
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### پورت‌ها

``` bash
ss -lntup
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### IPv4

``` bash
ip -4 addr
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Route

``` bash
ip -4 route
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### TUN

``` bash
ls -l /dev/net/tun
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Disk

``` bash
df -h
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Inodes

``` bash
df -i
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Memory

``` bash
free -h
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Kernel errors

``` bash
journalctl -k -p warning -b --no-pager
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### DNS local

``` bash
dig @127.0.0.1 example.com
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Firewall

``` bash
iptables-save
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Processes

``` bash
ps aux --sort=-%mem | head
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Load

``` bash
uptime
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Time

``` bash
timedatectl status
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

### چرخه بررسی 6

#### سرویس‌های failed

``` bash
systemctl --failed --no-pager
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### وضعیت Nova

``` bash
systemctl is-active nova-agent.service
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### لاگ Nova

``` bash
journalctl -u nova-agent.service -n 100 --no-pager
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### پورت‌ها

``` bash
ss -lntup
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### IPv4

``` bash
ip -4 addr
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Route

``` bash
ip -4 route
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### TUN

``` bash
ls -l /dev/net/tun
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Disk

``` bash
df -h
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Inodes

``` bash
df -i
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Memory

``` bash
free -h
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Kernel errors

``` bash
journalctl -k -p warning -b --no-pager
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### DNS local

``` bash
dig @127.0.0.1 example.com
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Firewall

``` bash
iptables-save
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Processes

``` bash
ps aux --sort=-%mem | head
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Load

``` bash
uptime
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Time

``` bash
timedatectl status
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

### چرخه بررسی 7

#### سرویس‌های failed

``` bash
systemctl --failed --no-pager
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### وضعیت Nova

``` bash
systemctl is-active nova-agent.service
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### لاگ Nova

``` bash
journalctl -u nova-agent.service -n 100 --no-pager
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### پورت‌ها

``` bash
ss -lntup
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### IPv4

``` bash
ip -4 addr
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Route

``` bash
ip -4 route
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### TUN

``` bash
ls -l /dev/net/tun
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Disk

``` bash
df -h
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Inodes

``` bash
df -i
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Memory

``` bash
free -h
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Kernel errors

``` bash
journalctl -k -p warning -b --no-pager
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### DNS local

``` bash
dig @127.0.0.1 example.com
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Firewall

``` bash
iptables-save
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Processes

``` bash
ps aux --sort=-%mem | head
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Load

``` bash
uptime
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Time

``` bash
timedatectl status
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

### چرخه بررسی 8

#### سرویس‌های failed

``` bash
systemctl --failed --no-pager
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### وضعیت Nova

``` bash
systemctl is-active nova-agent.service
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### لاگ Nova

``` bash
journalctl -u nova-agent.service -n 100 --no-pager
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### پورت‌ها

``` bash
ss -lntup
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### IPv4

``` bash
ip -4 addr
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Route

``` bash
ip -4 route
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### TUN

``` bash
ls -l /dev/net/tun
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Disk

``` bash
df -h
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Inodes

``` bash
df -i
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Memory

``` bash
free -h
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Kernel errors

``` bash
journalctl -k -p warning -b --no-pager
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### DNS local

``` bash
dig @127.0.0.1 example.com
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Firewall

``` bash
iptables-save
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Processes

``` bash
ps aux --sort=-%mem | head
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Load

``` bash
uptime
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

#### Time

``` bash
timedatectl status
```

خروجی را با baseline سالم سرور مقایسه کنید و تغییر غیرمنتظره را قبل از
اقدام بعدی بررسی کنید.

------------------------------------------------------------------------

## پیوست B: اصول Production

1.  برای release از commit ثابت استفاده کنید.
2.  SHA-256 artifact را منتشر و بررسی کنید.
3.  قبل از تغییر snapshot بگیرید.
4.  backup را خارج از VPS نگه دارید.
5.  restore را دوره‌ای تست کنید.
6.  SSH را با key محدود کنید.
7.  root login مستقیم را طبق سیاست خود محدود کنید.
8.  DNS عمومی را فقط در صورت نیاز ارائه کنید.
9.  ACL و firewall را حداقل‌گرا نگه دارید.
10. پورت‌های باز را دوره‌ای audit کنید.
11. log retention تعریف کنید.
12. disk alert تعریف کنید.
13. memory alert تعریف کنید.
14. service-down alert تعریف کنید.
15. certificate expiry را مانیتور کنید.
16. تغییرات installer را code-review کنید.
17. staging را از production جدا کنید.
18. maintenance window تعریف کنید.
19. rollback criteria از قبل مشخص باشد.
20. credential rotation برنامه‌ریزی شود.
21. برای release از commit ثابت استفاده کنید.
22. SHA-256 artifact را منتشر و بررسی کنید.
23. قبل از تغییر snapshot بگیرید.
24. backup را خارج از VPS نگه دارید.
25. restore را دوره‌ای تست کنید.
26. SSH را با key محدود کنید.
27. root login مستقیم را طبق سیاست خود محدود کنید.
28. DNS عمومی را فقط در صورت نیاز ارائه کنید.
29. ACL و firewall را حداقل‌گرا نگه دارید.
30. پورت‌های باز را دوره‌ای audit کنید.
31. log retention تعریف کنید.
32. disk alert تعریف کنید.
33. memory alert تعریف کنید.
34. service-down alert تعریف کنید.
35. certificate expiry را مانیتور کنید.
36. تغییرات installer را code-review کنید.
37. staging را از production جدا کنید.
38. maintenance window تعریف کنید.
39. rollback criteria از قبل مشخص باشد.
40. credential rotation برنامه‌ریزی شود.
41. برای release از commit ثابت استفاده کنید.
42. SHA-256 artifact را منتشر و بررسی کنید.
43. قبل از تغییر snapshot بگیرید.
44. backup را خارج از VPS نگه دارید.
45. restore را دوره‌ای تست کنید.
46. SSH را با key محدود کنید.
47. root login مستقیم را طبق سیاست خود محدود کنید.
48. DNS عمومی را فقط در صورت نیاز ارائه کنید.
49. ACL و firewall را حداقل‌گرا نگه دارید.
50. پورت‌های باز را دوره‌ای audit کنید.
51. log retention تعریف کنید.
52. disk alert تعریف کنید.
53. memory alert تعریف کنید.
54. service-down alert تعریف کنید.
55. certificate expiry را مانیتور کنید.
56. تغییرات installer را code-review کنید.
57. staging را از production جدا کنید.
58. maintenance window تعریف کنید.
59. rollback criteria از قبل مشخص باشد.
60. credential rotation برنامه‌ریزی شود.
61. برای release از commit ثابت استفاده کنید.
62. SHA-256 artifact را منتشر و بررسی کنید.
63. قبل از تغییر snapshot بگیرید.
64. backup را خارج از VPS نگه دارید.
65. restore را دوره‌ای تست کنید.
66. SSH را با key محدود کنید.
67. root login مستقیم را طبق سیاست خود محدود کنید.
68. DNS عمومی را فقط در صورت نیاز ارائه کنید.
69. ACL و firewall را حداقل‌گرا نگه دارید.
70. پورت‌های باز را دوره‌ای audit کنید.
71. log retention تعریف کنید.
72. disk alert تعریف کنید.
73. memory alert تعریف کنید.
74. service-down alert تعریف کنید.
75. certificate expiry را مانیتور کنید.
76. تغییرات installer را code-review کنید.
77. staging را از production جدا کنید.
78. maintenance window تعریف کنید.
79. rollback criteria از قبل مشخص باشد.
80. credential rotation برنامه‌ریزی شود.
81. برای release از commit ثابت استفاده کنید.
82. SHA-256 artifact را منتشر و بررسی کنید.
83. قبل از تغییر snapshot بگیرید.
84. backup را خارج از VPS نگه دارید.
85. restore را دوره‌ای تست کنید.
86. SSH را با key محدود کنید.
87. root login مستقیم را طبق سیاست خود محدود کنید.
88. DNS عمومی را فقط در صورت نیاز ارائه کنید.
89. ACL و firewall را حداقل‌گرا نگه دارید.
90. پورت‌های باز را دوره‌ای audit کنید.
91. log retention تعریف کنید.
92. disk alert تعریف کنید.
93. memory alert تعریف کنید.
94. service-down alert تعریف کنید.
95. certificate expiry را مانیتور کنید.
96. تغییرات installer را code-review کنید.
97. staging را از production جدا کنید.
98. maintenance window تعریف کنید.
99. rollback criteria از قبل مشخص باشد.
100. credential rotation برنامه‌ریزی شود.

------------------------------------------------------------------------

## پایان مستندات

اگر رفتار واقعی سرور با این README متفاوت بود، کد دقیق نسخه‌ای که اجرا
می‌کنید منبع نهایی رفتار است. مستندات و installer باید با هم به‌روزرسانی
شوند.

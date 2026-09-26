#!/usr/bin/env bash
# alirezaserver 0.3.0 — single-file ONLINE installer; rerun to repair/resume.
# Supported target: Ubuntu 24.04 or Debian 12/13, systemd, amd64/arm64.
# Add-on source and notices are embedded below; original upstream programs are
# downloaded from pinned official URLs. This is not an offline bundle.
# Integration tested locally; Linux VPN traffic / multi-node / 1 GiB load tests
# have NOT been performed. No claim of a production-certified release is made.
#
# Usage: sudo bash install.sh
#        sudo bash install.sh --check
#        sudo bash install.sh --rollback
#        sudo bash install.sh --backup
# DNS_ALLOWED_CIDRS="203.0.113.12/32,198.51.100.0/24" sudo -E bash install.sh
# DNS serves public clients by default with AdGuard rate limiting. To restrict
# clients, use AdGuard Access settings or DNS_ALLOWED_CIDRS on first install.
# Upstream Nova variables, including NOVA_JOIN_URL/TOKEN/PIN, remain unchanged.
set -Eeuo pipefail
umask 077
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ROOT=/var/lib/alirezaserver
APP=/opt/alirezaserver
NOVA_COMMIT=17e9373ec17ceede95369fcd26d6fabfda83b504
NOVA_SCRIPT_SHA=26df405f09a5eed8b430545688c0e2dc0df4cc50f617a91c820dd1821a7ca79d
NOVA_AGENT_SHA=544adcbfd54d09df4ba637a5abeb0803258076308a2abe025e41ea550fa039dc
AG_VERSION=v0.107.79
NOVA_BASE="https://raw.githubusercontent.com/IRNova/Nova-Server/$NOVA_COMMIT"
log(){ printf '\n[alirezaserver] %s\n' "$*"; }
die(){ printf '\nERROR: %s\n' "$*" >&2; exit 1; }
download(){ curl --fail --location --proto '=https' --tlsv1.2 --connect-timeout 20 --max-time 600 --retry 3 --retry-delay 3 --output "$2" "$1"; }
verify(){ printf '%s  %s\n' "$2" "$1" | sha256sum --check --status || die "Checksum mismatch: $1"; }
[[ $EUID == 0 ]] || die 'Run with sudo bash install.sh'
case "${1:-}" in
  --rollback) [[ -f "$APP/rollback.sh" ]] || die 'No add-on installation found'; exec bash "$APP/rollback.sh" ;;
  --check) [[ -f "$APP/check.sh" ]] || die 'No add-on installation found'; exec bash "$APP/check.sh" ;;
  --backup) [[ -f "$APP/backup.py" ]] || die 'No add-on installation found'; exec python3 "$APP/backup.py" ;;
  --help|-h) sed -n '2,19p' "$0"; exit 0 ;;
  ''|--repair) ;;
  *) die 'Unknown option. Use --help.' ;;
esac
[[ -d /run/systemd/system ]] || die 'A Linux VPS with systemd is required.'
source /etc/os-release
case "$ID:$VERSION_ID" in ubuntu:24.04|debian:12|debian:13) ;; *) die 'Supported: Ubuntu 24.04 or Debian 12/13.' ;; esac
case "$(uname -m)" in
 x86_64) AG_ARCH=amd64; AG_SHA=c48f4a43000665484c5ec28177de11a004759b620dae8f77b2aabefc9ef3687f ;;
 aarch64|arm64) AG_ARCH=arm64; AG_SHA=3f7893c18e8aaadc456d0452839190561c306ca95175a2254958be80a769c1ae ;;
 *) die 'Only amd64 and arm64 are supported.' ;;
esac
exec 9>/run/alirezaserver-install.lock
flock -n 9 || die 'Another installer is running.'
if [[ -n "${NOVA_JOIN_URL:-}" || -n "${NOVA_JOIN_TOKEN:-}" ]]; then
  [[ -n "${NOVA_JOIN_URL:-}" && -n "${NOVA_JOIN_TOKEN:-}" ]] || die 'Both NOVA_JOIN_URL and NOVA_JOIN_TOKEN are required.'
  # A fleet child has no local management UI. Keep the original enrollment flow.
  # Add-ons are installed only on the owner panel, not silently on fleet children.
  log 'Managed-node mode: preserving the original node enrollment.'
  command -v curl >/dev/null || { apt-get update; apt-get install -y curl ca-certificates; }
  JOIN_TEMP=$(mktemp -d); trap 'rm -rf -- "$JOIN_TEMP"' EXIT
  download "$NOVA_BASE/nova-node.sh" "$JOIN_TEMP/nova-node.sh"
  verify "$JOIN_TEMP/nova-node.sh" "$NOVA_SCRIPT_SHA"
  (umask 022; NOVA_TARBALL_URL="$NOVA_BASE/nova-node-agent.tar.gz" NOVA_TARBALL_SHA256="$NOVA_AGENT_SHA" bash "$JOIN_TEMP/nova-node.sh")
  exit
fi
install -d -m 700 /var/log/alirezaserver
INSTALL_LOG="/var/log/alirezaserver/install-$(date -u +%Y%m%dT%H%M%SZ).log"
touch "$INSTALL_LOG"; chmod 600 "$INSTALL_LOG"
exec > >(tee -a "$INSTALL_LOG") 2>&1
STAGE=preflight
WORK=''
HOOK_CHANGED=0
MANAGED=0
cleanup(){
  code=$?
  if [[ $code != 0 ]]; then
    # A DNS/upstream error must never silently uninstall working UI additions.
    # Restore the prior launch only if our new launch itself is unhealthy.
    if [[ $HOOK_CHANGED == 1 ]] && ! systemctl is-active --quiet nova-agent.service; then
      rm -f /etc/systemd/system/nova-agent.service.d/zz-alirezaserver.conf
      if [[ -f "$WORK/previous-dropin" ]]; then cp "$WORK/previous-dropin" /etc/systemd/system/nova-agent.service.d/zz-alirezaserver.conf; fi
      systemctl daemon-reload || true
      systemctl restart nova-agent.service || true
    fi
    if [[ $MANAGED == 1 ]]; then printf '%s\n' "$STAGE" > "$ROOT/failed-stage"; fi
    printf '\n[alirezaserver] INSTALLATION INCOMPLETE — failed stage: %s\n' "$STAGE" >&2
    printf 'Details: %s\nRun this SAME install.sh again to resume. Do not reinstall the VPS.\n' "$INSTALL_LOG" >&2
    printf 'نصب کامل نشده است؛ همین فایل را دوباره اجرا کنید. نصب نوا به‌تنهایی پایان کار نیست.\n' >&2
  fi
  [[ -z "$WORK" ]] || rm -rf -- "$WORK"
}
trap cleanup EXIT
trap 'printf "Failure at installer line %s (stage: %s)\n" "$LINENO" "$STAGE" >&2' ERR
if [[ -e "$APP" || -e "$ROOT" ]]; then
  if [[ -f "$ROOT/.installer-owned" ]] || { [[ -f "$APP/NOTICE.txt" ]] && grep -q '^alirezaserver add-on 0\.' "$APP/NOTICE.txt"; }; then
    MANAGED=1
    log 'Repair/resume: keeping existing DNS settings, OpenVPN accounts and certificates.'
    if [[ -f "$ROOT/addon.db" && -f "$APP/backup.py" ]]; then python3 "$APP/backup.py"; fi
  else die 'Existing directories are not recognized as this installer; refusing to overwrite them.'; fi
fi
if systemctl cat AdGuardHome.service >/dev/null 2>&1; then
  [[ $MANAGED == 1 ]] && systemctl show AdGuardHome.service -p ExecStart --value | grep -q '/opt/alirezaserver/adguard/AdGuardHome' || die 'An independently installed AdGuard Home service exists; it was not overwritten.'
fi
if [[ -f /opt/nova-node-agent/package.json ]]; then
  [[ -f /etc/systemd/system/nova-agent.service ]] || die 'Unsupported Nova service layout.'
  node -e 'const p=require("/opt/nova-node-agent/package.json");if(p.version!=="1.85.4")throw Error("Expected Nova 1.85.4; found "+p.version)'
fi
STAGE=prerequisites
log 'Installing prerequisites (no source compilation for this add-on).'
export DEBIAN_FRONTEND=noninteractive
apt-get -o DPkg::Lock::Timeout=300 update
apt-get -o DPkg::Lock::Timeout=300 install -y ca-certificates curl python3 openssl openvpn iptables iproute2 dnsutils
[[ -c /dev/net/tun ]] || { modprobe tun || true; }
[[ -c /dev/net/tun ]] || die '/dev/net/tun is unavailable; ask the VPS provider to enable TUN.'
WORK=$(mktemp -d /tmp/alirezaserver.XXXXXXXX)
DNS_ADDRESS=$(ip -j -4 route get 1.1.1.1 | python3 -c 'import json,sys; r=json.load(sys.stdin)[0]; print(r.get("prefsrc") or r.get("src") or "")')
[[ -n "$DNS_ADDRESS" ]] || die 'Could not determine the server IPv4 address.'
export DNS_ADDRESS
check_ports(){
python3 - <<'PY'
import os,socket,sys
sockets=[]
try:
    for address,port in [('127.0.0.1',53),(os.environ['DNS_ADDRESS'],53),('127.0.0.1',18085)]:
        for kind in ([socket.SOCK_STREAM,socket.SOCK_DGRAM] if port==53 else [socket.SOCK_STREAM]):
            s=socket.socket(socket.AF_INET,kind);sockets.append(s)
            try:s.bind((address,port))
            except OSError as e:sys.exit(f'Cannot bind {address}:{port} ({"TCP" if kind==socket.SOCK_STREAM else "UDP"}): {e}. Existing services were NOT stopped.')
finally:
    for s in sockets:s.close()
PY
}
if [[ $MANAGED == 0 ]]; then check_ports; fi
# Acquire and verify the add-on binary BEFORE the base installer prints its URL.
# A blocked GitHub release download therefore cannot leave a fresh Nova-only setup.
STAGE=adguard-download
log '[1/5] Preparing and verifying AdGuard Home before installing Nova.'
if [[ ! -x "$APP/adguard/AdGuardHome" ]]; then
  download "https://github.com/AdguardTeam/AdGuardHome/releases/download/$AG_VERSION/AdGuardHome_linux_$AG_ARCH.tar.gz" "$WORK/adguard.tar.gz"
  verify "$WORK/adguard.tar.gz" "$AG_SHA"
  tar -xzf "$WORK/adguard.tar.gz" -C "$WORK"
  [[ -x "$WORK/AdGuardHome/AdGuardHome" ]] || die 'AdGuard binary not found.'
fi
STAGE=nova-base
log '[2/5] Installing/checking the Nova base. Wait for ALIREZASERVER READY at the end.'
if [[ -f /opt/nova-node-agent/package.json ]]; then
  log 'Using the existing Nova installation; its installer will not be rerun.'
  [[ -f /etc/systemd/system/nova-agent.service ]] || die 'Unsupported Nova service layout.'
  node -e 'const p=require("/opt/nova-node-agent/package.json"); if(p.version!=="1.85.4") { console.error("This installer was prepared against Nova 1.85.4; found "+p.version+". Existing installation left untouched.");process.exit(1) }'
else
  log 'Installing the pinned, original Nova release. Its own setup questions follow.'
  download "$NOVA_BASE/nova-node.sh" "$WORK/nova-node.sh"
  verify "$WORK/nova-node.sh" "$NOVA_SCRIPT_SHA"
  (umask 022; NOVA_TARBALL_URL="$NOVA_BASE/nova-node-agent.tar.gz" NOVA_TARBALL_SHA256="$NOVA_AGENT_SHA" bash "$WORK/nova-node.sh")
fi
systemctl is-active --quiet nova-agent.service || die 'The original Nova service is not healthy; add-on installation stopped.'
if [[ $MANAGED == 0 ]]; then check_ports; fi
NODE_BIN=$(command -v node)
[[ "$NODE_BIN" =~ ^/[a-zA-Z0-9_./-]+$ ]] || die 'Unsupported Node executable path.'
node -e 'if(Number(process.versions.node.split(".")[0])<24)process.exit(1)' || die 'Node.js 24+ is required.'
STAGE=addon-files
log '[3/5] Installing alirezaserver branding, AdGuard integration and OpenVPN management.'
mkdir -p "$APP" "$ROOT" /etc/systemd/system/nova-agent.service.d
chmod 700 "$APP" "$ROOT"
printf 'alirezaserver\n' > "$ROOT/.installer-owned"
MANAGED=1
# ALIREZA_EMBEDDED_FILES

cat > "$APP/NOTICE.txt" <<'ALIREZA_9A192610D704119A4FABBF42'
alirezaserver add-on 0.3.0

The new integration modules in this directory are licensed under GPL-3.0-or-later.
OpenVPN configuration/profile conventions were adapted from Sir-MmD/vpn-ui,
web/service/openvpn.go at commit 8044e0ad45c60149439546ea0fd99371a4d3c03d.
Original contributors retain their copyrights. See COPYING.vpn-ui.

Nova Server is separately downloaded from IRNova/Nova-Server, release 1.85.4,
commit 17e9373ec17ceede95369fcd26d6fabfda83b504. Its original code is not included
in this installer and is not relicensed. Its proprietary license continues to
apply. UI integration and private customization do not transfer ownership.

AdGuard Home is separately downloaded from AdguardTeam/AdGuardHome, v0.107.79,
and remains GPL-3.0 licensed. The complete original UI is proxied; shared colors,
effects and Nova's embedded Vazirmatn font are applied without rearranging controls.
Its original source and notices remain upstream.
OpenVPN and OS packages retain their own upstream licenses.

Scope and verification:
- Original Nova files, existing protocol configurations and node enrollment
  command URLs are not renamed or replaced. Only displayed panel branding changes.
- An HTTP request hook runs inside the original Nova process through a systemd
  drop-in. Original requests go to the original handler; addon routes require an
  owner session validated by Nova's own /admin/whoami endpoint on each request.
- Additional accounts and statistics live in a separate SQLite database.
- OpenVPN here is an adapted implementation, not vpn-ui's full Go/RADIUS stack.
  It supports TCP/UDP servers, username/password accounts, per-account expiry,
  quotas, concurrent device caps, profile export, selected ciphers and TLS-Crypt.
  It does not add OpenVPN to Nova's native subscriptions, fleet accounting,
  resellers, bridge generation or Telegram bot. Original Nova features remain.
- DNS and OpenVPN addons are local to the main panel. Existing Nova fleet nodes
  keep their original behavior. OpenVPN traffic exits via the host's IPv4 route;
  it is not automatically sent through Nova's custom Xray/WARP outbounds.
- The original Nova backup/reset tools do not manage the separate addon data.
  Run install.sh --backup alongside Nova's own backup. The resulting root-only
  archive in /var/backups/alirezaserver includes a consistent addon SQLite copy,
  certificates, configuration and integration files. Restore is manual.
- DNS serves TCP/UDP port 53 on loopback and the default IPv4 interface address.
  Its admin HTTP port 18085 is loopback-only. Direct IPv6 DNS listening and
  standalone encrypted DNS listeners are not preconfigured; all original AdGuard
  settings are available. Fresh installations accept public DNS clients with
  AdGuard's 20 queries/second rate limit. Custom access lists remain enforced.
  Repair replaces only the exact private-only ACL and DoH upstream pair shipped
  as 0.2 defaults. Access restrictions can be set in AdGuard Access settings.
- Firewall changes affect dedicated ALIREZA_* chains, never flush system chains.
  Provider firewalls cannot be modified without provider access.
- Base packages require internet access; install.sh is a one-file online installer.
- Re-running install.sh repairs/resumes this integration and preserves its stored
  custom DNS settings, accounts and certificates. Recognized existing data is backed
  up before repair. Root-only logs are written to /var/log/alirezaserver.
- Existing OpenVPN configurations are regenerated with the IPv4-only tunnel
  recipe and client IPv6 blocking. Accounts, CA and TLS-Crypt keys are retained;
  the previous server.conf is saved as server.conf.before-0.3.
- Installation success requires owner-authenticated UI/API checks through both
  the internal listener and the local HTTPS front. Temporary DNS verification
  rewrites are removed after checking TCP/UDP resolution. External upstream
  failure is reported separately and does not silently remove working UI additions.
- No live Linux VPN-client, multi-node, reboot, kernel-firewall, or 1 GiB load test
  was possible in the Windows development environment. Treat this as a test build.
  The code does not guarantee bug-free operation or unlimited load on a 1 GiB VPS.

Local tests cover input validation, Python authentication/device limits, expiry,
traffic calculations, owner authorization and CSRF checks, HTTP proxying, branding,
and installer/script syntax. See the verification record embedded in install.sh.
ALIREZA_9A192610D704119A4FABBF42

cat > "$APP/VERIFICATION.txt" <<'ALIREZA_8D54CC5CA1F9E072D44ACB47'
alirezaserver 0.3.0 verification record, 2026-09-21

Development platform: Windows, Node.js 24.19.0.

0.3 repair regression checks:
PASS: 7 additional automated tests: fragmented OpenVPN management replies,
explicit error replies with CRLF, premature EOF, subnet allocation, persisted
configuration migration/key retention, public DNS address presentation and exact
reuse of Nova's embedded Vazirmatn font. The management endpoint is a real local
TCP test double, not a live OpenVPN daemon.
PASS: Official AdGuard binary accepted the old-default ACL/upstream migration;
blocked clients/hosts remained intact, custom ACL/upstreams were preserved, and
repeated repair was idempotent. Test settings were restored afterwards.
PASS: Original AdGuard dashboard and OpenVPN creation form visually inspected
inside the original Nova panel with the new dark colors/effects; AdGuard computed
body font was Vazirmatn. No original Nova application files were edited.

OpenVPN configuration references:
https://openvpn.net/community-docs/community-articles/openvpn-2-6-manual.html
https://openvpn.net/community-docs/management-interface.html

PASS: 10 automated tests covering validation, generated OpenVPN configuration,
password hashing shared by Node/Python, concurrent device limits, expiry/disabled
accounts, traffic settlement, owner authorization, origin checks, proxy headers,
HTML branding and unchanged native routes.

PASS: Mocked rollback regression confirms that template service entries and a
firewall cleanup failure do not prevent restoring the original Nova launch.
PASS: Generated shell, JavaScript and Python syntax; embedded file integrity.

PASS: The real Nova 1.85.4 HTTP application was launched on loopback without its
Linux service installer. Its own login/session mechanism, full original dashboard,
new sidebar buttons and OpenVPN creation dialog were exercised in a browser.
The original application files were not edited.

PASS: Official AdGuard Home v0.107.79 Windows binary (SHA-256 verified) was run
on loopback with a disposable configuration. Its original dashboard loaded through
the owner-authenticated Nova proxy, including relative scripts and API requests.
A temporary DNS rewrite was created through that proxy, resolved correctly over
both actual UDP and TCP DNS, and removed. Test DNS port was 15353 to avoid changing
the development machine; the Linux installer explicitly configures port 53 and
checks that configured port plus UDP/TCP queries after installation.

PASS: Current verification code reached real Nova/AdGuard through a loopback HTTPS
proxy, including owner-only OpenVPN and DNS APIs. Deliberately removing the
branding marker from the HTTPS response caused verification to fail. Temporary
DNS verification records were cleaned up. This used a test TLS proxy, not Xray.
PASS: First-session signing-key initialization on a disposable fresh Nova database;
existing keys are preserved by INSERT OR IGNORE.
PASS: Installer error handling with mocked service commands retains healthy
integration after a failure, restores an unhealthy launch, and returns failure.
PASS: Actual embedded Python configuration code creates DNS port 53 configuration
on first install and preserves existing DNS/install/firewall settings on repair.

NOT TESTED: Linux systemd service lifecycle, kernel firewall behavior, OpenVPN
client handshake/traffic, server reboot, original fleet enrollment against remote
nodes, public reachability, or performance on a 1 CPU / 1 GiB VPS. Browser/UI tests
and syntax checks cannot establish these properties. This is a test build, not a
guarantee of bug-free deployment. AdGuard and Nova updates require revalidation.

Runtime diagnostics: sudo bash install.sh --check
Repair/resume:       sudo bash install.sh
Add-on backup:       sudo bash install.sh --backup
Disable add-ons:     sudo bash install.sh --rollback
Back up the original Nova data separately using Nova's own backup facilities.
ALIREZA_8D54CC5CA1F9E072D44ACB47

cat > "$APP/auth.py" <<'ALIREZA_8FD1D5E2FD0138ACA837582B'
#!/usr/bin/python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""OpenVPN hooks. No credentials are passed in command-line arguments or logs."""
import hashlib, hmac, json, os, re, sqlite3, sys, time

def main():
    action, sid = sys.argv[1:3]
    if not re.fullmatch(r'[a-f0-9]{12}', sid): return 1
    db = sqlite3.connect(os.environ.get('ALIREZA_DB', '/var/lib/alirezaserver/addon.db'), timeout=10)
    db.row_factory = sqlite3.Row
    db.execute('PRAGMA busy_timeout=10000')
    name = os.environ.get('common_name', '')
    now = int(time.time())
    if action == 'auth':
        with open(sys.argv[3], 'r', encoding='utf-8') as f:
            raw = f.read(1024)
        lines = raw.splitlines()
        if len(lines) != 2: return 1
        name, password = lines
    if not re.fullmatch(r'[a-zA-Z0-9_.@-]{1,64}', name): return 1
    peer = os.environ.get('trusted_ip', '') + ':' + os.environ.get('trusted_port', '')
    if action == 'disconnect':
        db.execute('BEGIN IMMEDIATE')
        old = db.execute('SELECT * FROM sessions WHERE sid=? AND name=? AND peer=?', (sid,name,peer)).fetchone()
        if old and not old['ended']:
            rx, tx = max(0,int(os.environ.get('bytes_received','0'))), max(0,int(os.environ.get('bytes_sent','0')))
            delta = max(0,rx-old['rx']) + max(0,tx-old['tx'])
            db.execute('UPDATE users SET used=used+? WHERE username=?', (delta,name))
            db.execute('UPDATE sessions SET rx=?,tx=?,ended=?,seen=? WHERE sid=? AND name=? AND peer=?', (rx,tx,now,now,sid,name,peer))
        db.commit()
        return 0
    row = db.execute('SELECT * FROM users WHERE username=?', (name,)).fetchone()
    server = db.execute('SELECT data FROM servers WHERE id=?', (sid,)).fetchone()
    if not row or not server or not json.loads(server['data'])['enabled']: return 1
    if not row['enabled'] or sid not in json.loads(row['serverIds']): return 1
    if row['expiry'] and row['expiry'] <= now: return 1
    if row['quota'] and row['used'] >= row['quota']: return 1
    if action == 'auth':
        if len(password) > 128: return 1
        actual = hashlib.scrypt(password.encode('utf-8'), salt=bytes.fromhex(row['salt']), n=16384, r=8, p=1, dklen=32)
        return 0 if hmac.compare_digest(actual.hex(), row['hash']) else 1
    if action != 'connect': return 1
    # Serialize the final device-limit decision: parallel handshakes cannot overbook.
    db.execute('BEGIN IMMEDIATE')
    row = db.execute('SELECT * FROM users WHERE username=?', (name,)).fetchone()
    if not row or not row['enabled'] or (row['expiry'] and row['expiry']<=now) or (row['quota'] and row['used']>=row['quota']):
        db.rollback(); return 1
    count = db.execute('SELECT count(*) FROM sessions WHERE name=? AND ended=0 AND NOT (sid=? AND peer=?)', (name,sid,peer)).fetchone()[0]
    if count >= row['devices']: db.rollback(); return 1
    db.execute('INSERT INTO sessions(sid,name,peer,connected,rx,tx,seen,ended) VALUES(?,?,?,?,0,0,?,0) ON CONFLICT(sid,name,peer) DO UPDATE SET connected=excluded.connected,rx=0,tx=0,seen=excluded.seen,ended=0', (sid,name,peer,now,now))
    db.commit()
    return 0

if __name__ == '__main__':
    try: sys.exit(main())
    except Exception: sys.exit(1)
ALIREZA_8FD1D5E2FD0138ACA837582B

cat > "$APP/backend.mjs" <<'ALIREZA_E3A85F4B0CC1100A3D1E019B'
// SPDX-License-Identifier: GPL-3.0-or-later
import { DatabaseSync } from 'node:sqlite';
import { readFileSync, writeFileSync, mkdirSync, renameSync, existsSync, rmSync, chmodSync } from 'node:fs';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { randomBytes, scrypt } from 'node:crypto';
import { createConnection, createServer } from 'node:net';
import { createSocket } from 'node:dgram';
import { id, fail, validateServer, validateUser, serverConfig, clientConfig, parseStatus } from './model.mjs';
const exec=promisify(execFile), hash=promisify(scrypt);
export const ROOT=process.env.ALIREZA_ROOT||'/var/lib/alirezaserver';
let db;
export function database() {
  if(db) return db;
  mkdirSync(ROOT,{recursive:true,mode:0o700});
  db=new DatabaseSync(`${ROOT}/addon.db`); db.exec('PRAGMA journal_mode=WAL; PRAGMA busy_timeout=10000;');
  db.exec(`CREATE TABLE IF NOT EXISTS servers(id TEXT PRIMARY KEY,data TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS users(id TEXT PRIMARY KEY,username TEXT UNIQUE NOT NULL,hash TEXT NOT NULL,salt TEXT NOT NULL,
    serverIds TEXT NOT NULL,enabled INTEGER NOT NULL,expiry INTEGER NOT NULL,quota INTEGER NOT NULL,used INTEGER NOT NULL DEFAULT 0,devices INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS sessions(sid TEXT,name TEXT,peer TEXT,connected INTEGER,rx INTEGER,tx INTEGER,seen INTEGER,ended INTEGER,
    PRIMARY KEY(sid,name,peer));`);
  chmodSync(`${ROOT}/addon.db`,0o600); return db;
}
export function servers() { return database().prepare('SELECT data FROM servers ORDER BY id').all().map(r=>JSON.parse(r.data)); }
function server(sid) { const s=servers().find(s=>s.id===id(sid)); if(!s) fail('OpenVPN server not found',404); return s; }
const unit=sid=>`alireza-openvpn@${id(sid)}.service`;
export async function run(cmd,args,options={}) {
  try {return (await exec(cmd,args,{timeout:30000,maxBuffer:1024*1024,env:{...process.env,PATH:'/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'},...options})).stdout;}
  catch(e){throw Object.assign(new Error(`${cmd}: ${String(e.stderr||e.message).slice(0,700)}`),{status:500});}
}
export function atomic(path,text,mode=0o600) { const tmp=path+'.new';writeFileSync(tmp,text,{mode});chmodSync(tmp,mode);renameSync(tmp,path); }
function saveServer(s) { database().prepare('INSERT INTO servers VALUES(?,?) ON CONFLICT(id) DO UPDATE SET data=excluded.data').run(s.id,JSON.stringify(s)); }
function firewallFile() { atomic(`${ROOT}/firewall.json`,JSON.stringify(servers())); }
async function firewall() { firewallFile(); await run('/opt/alirezaserver/firewall.py',[]); }
async function portFree(s) {
  await new Promise((resolve,reject)=>{
    const sock=s.proto==='udp'?createSocket('udp4'):createServer();
    sock.once('error',()=>reject(Object.assign(new Error('This port is already occupied; the existing service was not changed.'),{status:409})));
    if(s.proto==='udp') sock.bind(s.port,'0.0.0.0',()=>sock.close(resolve)); else sock.listen(s.port,'0.0.0.0',()=>sock.close(resolve));
  });
}
function ipv4(v){return v.split('.').reduce((n,p)=>(n*256+Number(p))>>>0,0);}
export function overlap(a,b){const[aa,ap]=a.split('/'),[bb,bp]=b.split('/');if(!aa||!bb||ap===undefined||bp===undefined)return false;const p=Math.min(+ap,+bp);if(!p)return false;const mask=(0xffffffff<<(32-p))>>>0;return (ipv4(aa)&mask)===(ipv4(bb)&mask);}
export function freeSubnet(routes,existing){
  const occupied=[...routes.map(r=>r.dst).filter(Boolean),...existing.map(s=>s.subnet)];
  const candidates=[];for(let n=10;n<250;n++)candidates.push(`10.231.${n}.0/24`,`172.27.${n}.0/24`,`192.168.${n}.0/24`);
  const result=candidates.find(net=>!occupied.some(other=>overlap(net,other)));
  if(!result)fail('No non-overlapping private /24 subnet found. Review the server routes.',409);return result;
}
export async function serverDefaults(){
  const list=servers(),routes=JSON.parse(await run('ip',['-j','-4','route','show','table','all']));
  const subnet=freeSubnet(routes,list);let port=1194;
  for(;port<1300;port++){
    if(list.some(s=>s.port===port&&s.proto==='udp'))continue;
    try{await portFree({port,proto:'udp'});break;}catch{}
  }
  if(port===1300)fail('No free UDP port in the suggested range; choose a free port manually.',409);
  return{subnet,dns:subnet.replace('.0/24','.1'),port};
}
async function subnetFree(s,previous) {
  for(const other of servers()) if(other.id!==s.id&&overlap(s.subnet,other.subnet)) fail('Subnet overlaps another OpenVPN server');
  const routes=JSON.parse(await run('ip',['-j','-4','route','show','table','all']));
  for(const r of routes) if(r.dst?.includes('/')&&r.dst!=='0.0.0.0/0'&&!(previous&&r.dev===`az${s.id.slice(0,8)}`)&&overlap(s.subnet,r.dst)) fail(`Subnet overlaps existing route ${r.dst}; choose another /24`);
}
async function certificates(s) {
  const dir=`${ROOT}/openvpn/${s.id}`; mkdirSync(dir,{recursive:true,mode:0o700});
  if(!existsSync(`${dir}/tls-crypt.key`)) {
    await run('openvpn',['--genkey','secret',`${dir}/tls-crypt.key.new`]);
    chmodSync(`${dir}/tls-crypt.key.new`,0o600);renameSync(`${dir}/tls-crypt.key.new`,`${dir}/tls-crypt.key`);
  }
  if(existsSync(`${dir}/server.crt`)&&existsSync(`${dir}/server.key`)&&existsSync(`${dir}/ca.crt`)) return;
  if(existsSync(`${dir}/ca.key`)!==existsSync(`${dir}/ca.crt`))fail('The existing CA is incomplete. Restore its backup before repairing this server; existing client trust was preserved.',409);
  if(!existsSync(`${dir}/ca.crt`)){
    await run('openssl',['ecparam','-name','prime256v1','-genkey','-noout','-out',`${dir}/ca.key`]);
    await run('openssl',['req','-x509','-new','-sha256','-days','3650','-key',`${dir}/ca.key`,'-subj',`/CN=alirezaserver-${s.id}-CA`,'-addext','basicConstraints=critical,CA:TRUE','-addext','keyUsage=critical,keyCertSign,cRLSign','-out',`${dir}/ca.crt`]);
  }
  await run('openssl',['ecparam','-name','prime256v1','-genkey','-noout','-out',`${dir}/server.key`]);
  await run('openssl',['req','-new','-key',`${dir}/server.key`,'-subj',`/CN=alirezaserver-${s.id}`,'-out',`${dir}/server.csr`]);
  atomic(`${dir}/server.ext`,'basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=serverAuth\n');
  await run('openssl',['x509','-req','-in',`${dir}/server.csr`,'-CA',`${dir}/ca.crt`,'-CAkey',`${dir}/ca.key`,'-CAcreateserial','-days','825','-sha256','-extfile',`${dir}/server.ext`,'-out',`${dir}/server.crt`]);
  for(const f of ['ca.key','server.key','tls-crypt.key']) chmodSync(`${dir}/${f}`,0o600);
}
export async function save(input,sid) {
  const previous=sid?server(sid):null;
  const s={...validateServer(input),id:previous?.id||randomBytes(6).toString('hex')};
  if(servers().some(o=>o.id!==s.id&&o.port===s.port&&o.proto===s.proto)) fail('Another OpenVPN server uses this port');
  await subnetFree(s,previous);
  if(!previous||previous.port!==s.port||previous.proto!==s.proto||!previous.enabled) await portFree(s);
  await certificates(s);
  const path=`${ROOT}/openvpn/${s.id}/server.conf`, old=existsSync(path)?readFileSync(path,'utf8'):null;
  try {
    atomic(path,serverConfig(s,ROOT)); saveServer(s); await firewall();
    if(s.enabled) {await run('systemctl',['enable',unit(s.id)]);await run('systemctl',['restart',unit(s.id)]);await ready(s);}
    else await run('systemctl',['disable','--now',unit(s.id)]);
    if(!s.enabled) database().prepare('UPDATE sessions SET ended=? WHERE sid=?').run(Math.floor(Date.now()/1000),s.id);
    return s;
  } catch(error) {
    try {
      if(previous){saveServer(previous);atomic(path,old||serverConfig(previous,ROOT));await firewall();await run('systemctl',[previous.enabled?'enable':'disable',unit(s.id)]);await run('systemctl',[previous.enabled?'restart':'stop',unit(s.id)]);}
      else{await run('systemctl',['disable','--now',unit(s.id)]).catch(()=>{});database().prepare('DELETE FROM servers WHERE id=?').run(s.id);await firewall();}
    }catch(rollback){error.message+='; rollback needs attention: '+rollback.message;}
    throw error;
  }
}
export function refreshConfigs(){
  for(const s of servers()){
    const path=`${ROOT}/openvpn/${id(s.id)}/server.conf`;
    mkdirSync(`${ROOT}/openvpn/${s.id}`,{recursive:true,mode:0o700});
    if(existsSync(path)&&!existsSync(path+'.before-0.3'))atomic(path+'.before-0.3',readFileSync(path,'utf8'));
    atomic(path,serverConfig(s,ROOT));
  }
  firewallFile();
}
export async function ready(s) {
  for(let n=0;n<12;n++) {
    await new Promise(r=>setTimeout(r,500));
    try{const out=await management(s.id,'state');if(out.includes('CONNECTED,SUCCESS'))return;}catch{}
  }
  const logs=await run('journalctl',['-u',unit(s.id),'-n','12','--no-pager']).catch(()=> '');
  fail('OpenVPN did not become ready. '+logs.slice(-1600),500);
}
export async function removeServer(sid) {
  server(sid);
  if(database().prepare('SELECT serverIds FROM users').all().some(r=>JSON.parse(r.serverIds).includes(sid))) fail('Remove this server from its users before deleting it');
  await run('systemctl',['disable','--now',unit(sid)]);database().prepare('DELETE FROM servers WHERE id=?').run(sid);
  database().prepare('DELETE FROM sessions WHERE sid=?').run(sid);await firewall();
  // Retain certificates for recovery; deletion never touches Nova files.
}
export function users() { return database().prepare('SELECT id,username,serverIds,enabled,expiry,quota,used,devices FROM users ORDER BY username').all().map(r=>({...r,serverIds:JSON.parse(r.serverIds)})); }
export async function saveUser(input,uid) {
  const previous=uid?database().prepare('SELECT * FROM users WHERE id=?').get(id(uid)):null;
  if(uid&&!previous) fail('User not found',404);
  const u=validateUser(input,servers());
  if(previous&&previous.username!==u.username) fail('Username is immutable; create a new account to rename it');
  if(!previous&&!u.password) fail('Password is required');
  const salt=u.password?randomBytes(16).toString('hex'):previous.salt;
  const digest=u.password?(await hash(u.password,Buffer.from(salt,'hex'),32,{N:16384,r:8,p:1})).toString('hex'):previous.hash;
  const key=previous?.id||randomBytes(6).toString('hex');
  try {database().prepare(`INSERT INTO users(id,username,hash,salt,serverIds,enabled,expiry,quota,used,devices) VALUES(?,?,?,?,?,?,?,?,?,?)
    ON CONFLICT(id) DO UPDATE SET hash=excluded.hash,salt=excluded.salt,serverIds=excluded.serverIds,enabled=excluded.enabled,expiry=excluded.expiry,quota=excluded.quota,devices=excluded.devices`).run(key,u.username,digest,salt,JSON.stringify(u.serverIds),+u.enabled,u.expiry,u.quota,previous?.used||0,u.devices);}
  catch(e){if(String(e).includes('UNIQUE'))fail('Username already exists');throw e;}
  if(previous) await disconnect(u.username);
  return {id:key};
}
export async function removeUser(uid){const u=users().find(u=>u.id===id(uid));if(!u)fail('User not found',404);database().prepare('UPDATE users SET enabled=0 WHERE id=?').run(uid);await disconnect(u.username);database().prepare('DELETE FROM users WHERE id=?').run(uid);database().prepare('DELETE FROM sessions WHERE name=?').run(u.username);}
export async function resetUsage(uid) {const u=users().find(u=>u.id===id(uid));if(!u)fail('User not found',404);await collect();database().prepare('UPDATE users SET used=0 WHERE id=?').run(uid);}
const managementQueues=new Map();
export function management(sid,command) {
  id(sid);
  const current=(managementQueues.get(sid)||Promise.resolve()).catch(()=>{}).then(()=>managementReply(`${ROOT}/openvpn/${sid}/management.sock`,command));
  managementQueues.set(sid,current);
  const cleanup=()=>{if(managementQueues.get(sid)===current)managementQueues.delete(sid);};
  current.then(cleanup,cleanup);return current;
}
export function managementReply(address,command) {
  if(/[\r\n]/.test(command))return Promise.reject(new Error('Invalid management command'));
  return new Promise((resolve,reject)=>{
    const sock=createConnection(address);let data='',sent=false,done=false;
    const finish=(error)=>{if(done)return;done=true;clearTimeout(timer);sock.destroy();error?reject(error):resolve(data);};
    const timer=setTimeout(()=>finish(new Error('OpenVPN management timeout')),5000);
    sock.on('data',b=>{
      data+=b.toString();if(data.length>1024*1024){finish(new Error('Management reply too large'));return;}
      if(!sent){const line=data.indexOf('\n');if(line<0)return;
        if(!data.slice(0,line).startsWith('>INFO:')){finish(new Error('Unexpected management greeting'));return;}
        sent=true;data=data.slice(line+1);sock.write(command+'\n');
      }
      // Wait for the protocol terminator. Sending quit alongside state could
      // close the management session before its buffered answer was delivered.
      if(/(?:^|\n)ERROR:[^\n]*\n/.test(data)){finish(new Error(data.trim()));return;}
      if(/(?:^|\n)(?:END\r?|SUCCESS:[^\n]*)\n/.test(data))finish();
    });
    sock.on('error',finish);sock.on('end',()=>{if(!done)finish(new Error('Incomplete management response'));});
  });
}
async function disconnect(username) {
  const failures=[];
  for(const s of servers().filter(s=>s.enabled)) {
    if(!existsSync(`${ROOT}/openvpn/${s.id}/management.sock`))continue;
    try{await management(s.id,'kill '+username);}catch(e){failures.push(s.name);}
  }
  if(failures.length)fail('Account updated but disconnect failed on: '+failures.join(', '),503);
}
let collecting=false;
export async function collect() {
  if(collecting)return;collecting=true;
  try {
    const d=database(); const now=Math.floor(Date.now()/1000);
    for(const s of servers()) {
      let parsed;
      try {parsed=parseStatus(readFileSync(`${ROOT}/openvpn/${s.id}/status.log`,'utf8'));}catch{continue;}
      if(!parsed.stamp||now-parsed.stamp>30)continue;
      d.exec('BEGIN IMMEDIATE');
      try {
        for(const c of parsed.clients) {
          const old=d.prepare('SELECT * FROM sessions WHERE sid=? AND name=? AND peer=?').get(s.id,c.name,c.remote);
          if(old?.ended>=parsed.stamp)continue;
          // A newly connected peer may reuse the same address/port while the
          // status file still describes its previous session. Wait for a fresh
          // status timestamp so that session's bytes are never billed twice.
          if(old&&!old.ended&&parsed.stamp<=old.connected)continue;
          const same=old && !old.ended && Math.abs(old.connected-c.connected)<=3;
          const delta=Math.max(0,c.received-(same?old.rx:0))+Math.max(0,c.sent-(same?old.tx:0));
          d.prepare('UPDATE users SET used=used+? WHERE username=?').run(delta,c.name);
          d.prepare('INSERT INTO sessions VALUES(?,?,?,?,?,?,?,0) ON CONFLICT(sid,name,peer) DO UPDATE SET connected=excluded.connected,rx=excluded.rx,tx=excluded.tx,seen=excluded.seen,ended=0').run(s.id,c.name,c.remote,c.connected,c.received,c.sent,parsed.stamp);
        }
        d.prepare('UPDATE sessions SET ended=? WHERE sid=? AND seen<? AND connected<? AND ended=0').run(parsed.stamp,s.id,parsed.stamp,parsed.stamp);
        d.exec('COMMIT');
      }catch(e){d.exec('ROLLBACK');throw e;}
    }
    for(const u of users())if(!u.enabled||(u.expiry&&u.expiry<=now)||(u.quota&&u.used>=u.quota))await disconnect(u.username).catch(()=>{});
    d.prepare('DELETE FROM sessions WHERE ended>0 AND ended<?').run(now-86400);
  } finally {collecting=false;}
}
export async function status() {
  await collect();const list=servers();
  const states=await Promise.all(list.map(async s=>({...s,status:(await run('systemctl',['is-active',unit(s.id)]).catch(()=> 'inactive')).trim()})));
  return {servers:states,users:users(),sessions:database().prepare('SELECT sid,name,peer,connected FROM sessions WHERE ended=0').all(),
    adguard:(await run('systemctl',['is-active','AdGuardHome.service']).catch(()=> 'inactive')).trim()};
}
export function profile(sid){const s=server(sid),dir=`${ROOT}/openvpn/${s.id}`;return clientConfig(s,readFileSync(`${dir}/ca.crt`,'utf8'),readFileSync(`${dir}/tls-crypt.key`,'utf8'));}
export async function logs(sid){server(sid);return run('journalctl',['-u',unit(sid),'-n','80','--no-pager']);}
export async function toggle(sid){const s=server(sid);return save({...s,enabled:!s.enabled},sid);}
export function startCollector(){const timer=setInterval(()=>collect().catch(e=>console.error('alirezaserver accounting:',e.message)),5000);timer.unref();}
ALIREZA_E3A85F4B0CC1100A3D1E019B

cat > "$APP/backup.py" <<'ALIREZA_4EA261D051D0879E99E621E4'
#!/usr/bin/python3
# Consistent SQLite snapshot plus add-on configuration, certificates and data.
# Run alongside Nova's own backup; this archive deliberately does not replace it.
import datetime, os, pathlib, sqlite3, tarfile, tempfile
if os.geteuid()!=0:raise SystemExit('Run as root.')
out=pathlib.Path('/var/backups/alirezaserver');out.mkdir(parents=True,exist_ok=True,mode=0o700)
stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ')
target=out/('alirezaserver-'+stamp+'.tar.gz')
with tempfile.TemporaryDirectory(prefix='alirezaserver-backup-') as temp:
    snap=pathlib.Path(temp)/'addon.db'
    with sqlite3.connect('/var/lib/alirezaserver/addon.db',timeout=30) as source:
        with sqlite3.connect(snap) as dest:source.backup(dest)
    def filter_entry(entry):
        if entry.name in ['var/lib/alirezaserver/addon.db','var/lib/alirezaserver/addon.db-wal','var/lib/alirezaserver/addon.db-shm']:return None
        if entry.name.endswith('/management.sock') or entry.name.endswith('/openvpn.pid'):return None
        return entry
    with tarfile.open(target,'w:gz') as tar:
        for name in ['opt/alirezaserver','var/lib/alirezaserver','etc/systemd/system/AdGuardHome.service','etc/systemd/system/alireza-firewall.service','etc/systemd/system/alireza-openvpn@.service','etc/systemd/system/nova-agent.service.d/alirezaserver.conf','etc/systemd/system/nova-agent.service.d/zz-alirezaserver.conf']:
            if pathlib.Path('/'+name).exists():tar.add('/'+name,arcname=name,filter=filter_entry)
        tar.add(snap,arcname='var/lib/alirezaserver/addon.db')
os.chmod(target,0o600)
print(target)
ALIREZA_4EA261D051D0879E99E621E4

cat > "$APP/brand.js" <<'ALIREZA_BAB70C98D74AFF8A610D4E35'
/* SPDX-License-Identifier: GPL-3.0-or-later */
(()=>{'use strict';
  const base=window.__NOVA_BASE__||'', prefix=base+'/alireza/';
  const logo='<svg viewBox="0 0 64 64" aria-label="alirezaserver"><defs><linearGradient id="alireza-gradient" x2="1" y2="1"><stop stop-color="#a78bfa"/><stop offset="1" stop-color="#6366f1"/></linearGradient></defs><path fill="url(#alireza-gradient)" d="M25 6h14l22 52H45l-4-11H23l-4 11H3L25 6zm3 29h9l-4.5-13L28 35z"/></svg>';
  const style=document.createElement('style');style.textContent='.az-overlay{position:fixed;inset:0;z-index:1500;background:var(--bg,#080a10);display:flex;flex-direction:column}.az-toolbar{display:flex;align-items:center;gap:16px;padding:12px 20px;background:var(--panel,#141720);color:var(--text,#fff);border-bottom:1px solid var(--border,#333)}.az-toolbar button{font:inherit;border:1px solid var(--border,#555);border-radius:10px;background:transparent;color:inherit;padding:8px 15px;cursor:pointer}.az-overlay iframe{flex:1;width:100%;border:0;background:var(--bg,#fff)}.az-overlay[hidden]{display:none}.az-toolbar strong{flex:1}.az-nav svg{color:#a78bfa}.mark[data-az-mark] svg{width:100%;height:100%}';document.head.append(style);
  const fa=()=>document.documentElement.lang==='fa'||document.documentElement.dir==='rtl';
  let overlay;
  function open(kind){
    if(!overlay){overlay=document.createElement('section');overlay.className='az-overlay';overlay.innerHTML='<div class="az-toolbar"><button type="button"></button><strong></strong><span>alirezaserver</span></div><iframe title="Service"></iframe>';document.body.append(overlay);overlay.querySelector('button').onclick=()=>{overlay.hidden=true;overlay.querySelector('iframe').src='about:blank';};}
    overlay.querySelector('button').textContent=fa()?'← بازگشت به پنل':'← Back to panel';overlay.querySelector('strong').textContent=kind==='dns'?'AdGuard Home · DNS':'OpenVPN';
    overlay.querySelector('iframe').src=prefix+kind+'/';overlay.hidden=false;overlay.querySelector('button').focus();
  }
  let owner=false,authPending=false;
  async function checkOwner(){if(authPending)return;authPending=true;try{const r=await fetch(base+'/admin/whoami',{credentials:'same-origin',cache:'no-store'});owner=r.ok&&(await r.json()).role==='owner';}catch{owner=false;}finally{authPending=false;}schedule();}
  function apply(){
    observer.disconnect();
    document.title=document.title.replace(/Nova\s*Server|\bNova\b|نوا\s*سرور|نوا/gi,'alirezaserver');
    const walker=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT,{acceptNode(node){return node.parentElement?.closest('script,style,textarea,pre,code,[contenteditable],.az-overlay')?NodeFilter.FILTER_REJECT:NodeFilter.FILTER_ACCEPT;}});
    let node;while((node=walker.nextNode())){const text=node.nodeValue.replace(/Nova\s*Server|\bNova\b|نوا\s*سرور|نوا/gi,'alirezaserver');if(text!==node.nodeValue)node.nodeValue=text;}
    document.querySelectorAll('.brand .mark:not([data-az-mark]),.gate .mark:not([data-az-mark]),.gate-mark:not([data-az-mark])').forEach(el=>{el.innerHTML=logo;el.dataset.azMark='1';});
    document.querySelectorAll('svg[viewBox="0 0 1254 1254"]').forEach(el=>{if(!el.closest('pre,code')){const span=document.createElement('span');span.style.cssText='display:inline-flex;width:100%;height:100%';span.innerHTML=logo;el.replaceWith(span);}});
    const icon=document.querySelector('link[rel="icon"]');if(icon&&!icon.dataset.azMark){icon.href='data:image/svg+xml,'+encodeURIComponent(logo);icon.dataset.azMark='1';}
    document.querySelectorAll('.social a').forEach(a=>{a.removeAttribute('href');a.removeAttribute('target');a.removeAttribute('onclick');a.setAttribute('aria-disabled','true');a.tabIndex=-1;});
    const nav=document.querySelector('.side-nav');
    if(nav&&!nav.querySelector('.az-nav')&&owner){for(const [kind,label]of[['dns','DNS · AdGuard Home'],['openvpn','OpenVPN']]){const b=document.createElement('button');b.type='button';b.className='nav-item az-nav';b.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><rect x="3" y="3" width="18" height="7" rx="2"/><rect x="3" y="14" width="18" height="7" rx="2"/><path d="M7 6h.01M7 17h.01"/></svg><span></span>';b.querySelector('span').textContent=label;b.onclick=()=>open(kind);nav.append(b);}}
    if(!nav){document.querySelectorAll('.az-nav').forEach(el=>el.remove());if(overlay&&!overlay.hidden){overlay.hidden=true;overlay.querySelector('iframe').src='about:blank';}}
    observer.observe(document.body,{childList:true,subtree:true,characterData:true});
  }
  let queued=false;
  function schedule(){if(!queued){queued=true;requestAnimationFrame(()=>{queued=false;apply();});}}
  const observer=new MutationObserver(schedule);apply();checkOwner();
  // Recheck after login/logout; no background network polling.
  document.addEventListener('submit',()=>setTimeout(checkOwner,1000),true);
  document.addEventListener('click',event=>{if(event.target.closest('button[type="submit"],#gate-submit,#logout,[data-action="logout"]'))setTimeout(checkOwner,1000);},true);
  let hadNav=!!document.querySelector('.side-nav');new MutationObserver(()=>{const has=!!document.querySelector('.side-nav');if(has!==hadNav){hadNav=has;checkOwner();}}).observe(document.body,{childList:true,subtree:true});
})();
ALIREZA_BAB70C98D74AFF8A610D4E35

cat > "$APP/check-dns.mjs" <<'ALIREZA_937B0EB65E80D2549D02F37C'
// SPDX-License-Identifier: GPL-3.0-or-later
// Verify a temporary, uniquely named AdGuard rewrite over both DNS transports.
// The caller creates/removes that record using the authenticated AdGuard API.
import {randomBytes} from 'node:crypto';
import {createSocket} from 'node:dgram';
import {createConnection} from 'node:net';
export async function checkDNS(domain,port=53){
const header=Buffer.alloc(12);randomBytes(2).copy(header);header.writeUInt16BE(0x0100,2);header.writeUInt16BE(1,4);
const labels=Buffer.from(domain.split('.').flatMap(label=>[label.length,...Buffer.from(label)]).concat([0,0,1,0,1]));
const packet=Buffer.concat([header,labels]);
function validate(b){if(b.length<12||b.readUInt16BE(0)!==packet.readUInt16BE(0)||!(b[2]&128)||(b[3]&15)!==0||!b.readUInt16BE(6)||!b.includes(Buffer.from([192,0,2,53])))throw Error('DNS rewrite did not resolve to the expected test address');return b[3]&15;}
async function udp(){return new Promise((resolve,reject)=>{const s=createSocket('udp4');const timer=setTimeout(()=>{s.close();reject(Error('UDP DNS did not respond'));},15000);s.on('error',e=>{clearTimeout(timer);s.close();reject(e);});s.once('message',b=>{clearTimeout(timer);s.close();try{resolve(validate(b));}catch(e){reject(e);}});s.send(packet,port,'127.0.0.1');});}
async function tcp(){return new Promise((resolve,reject)=>{const s=createConnection({host:'127.0.0.1',port});let bytes=Buffer.alloc(0),done=false;const finish=(err,result)=>{if(done)return;done=true;s.destroy();if(err)reject(err);else resolve(result);};s.setTimeout(15000,()=>finish(Error('TCP DNS did not respond')));s.on('error',e=>finish(e));s.on('end',()=>{if(!done)finish(Error('Incomplete TCP DNS response'));});s.on('connect',()=>{const size=Buffer.alloc(2);size.writeUInt16BE(packet.length);s.write(Buffer.concat([size,packet]));});s.on('data',b=>{bytes=Buffer.concat([bytes,b]);if(bytes.length>=2&&bytes.length>=bytes.readUInt16BE(0)+2){try{finish(null,validate(bytes.subarray(2,bytes.readUInt16BE(0)+2)));}catch(e){finish(e);}}});});}
await Promise.all([udp(),tcp()]);console.log('DNS port '+port+': actual UDP + TCP resolution PASS (local test record, no Internet dependency)');
}
ALIREZA_937B0EB65E80D2549D02F37C

cat > "$APP/check.sh" <<'ALIREZA_585469B65F55CD435B13A561'
#!/usr/bin/env bash
set -euo pipefail
systemctl is-active --quiet nova-agent.service
systemctl is-active --quiet AdGuardHome.service
systemctl is-active --quiet alireza-firewall.service
curl -fsS --max-time 8 http://127.0.0.1:18085/control/status | python3 -c 'import json,sys;s=json.load(sys.stdin);assert s.get("dns_port")==53,s; print("AdGuard DNS port 53: OK")'
node /opt/alirezaserver/verify-install.mjs
for proto in udp tcp; do
  options=()
  [[ $proto == tcp ]] && options+=(+tcp)
  if reply=$(dig @127.0.0.1 -p 53 example.com +time=5 +tries=1 "${options[@]}") && grep -q 'status: NOERROR' <<<"$reply"; then
    printf 'External DNS %s resolution: OK\n' "$proto"
  else
    printf 'WARNING: External DNS %s resolution unavailable. AdGuard is listening; review upstream servers in its DNS settings. The panel integration is kept active.\n' "$proto" >&2
  fi
done
printf 'Local service checks passed. External reachability and VPN client traffic require a client test.\n'
ALIREZA_585469B65F55CD435B13A561

cat > "$APP/dns-repair.py" <<'ALIREZA_9758260493588EA4B7BB2A6F'
#!/usr/bin/python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Migrate only the known 0.2 defaults through AdGuard's own API.
Preserve filters, rewrites, custom access lists and custom upstream servers.
"""
import json, os, pathlib, urllib.request
LEGACY_CLIENTS=['127.0.0.0/8','10.0.0.0/8','172.16.0.0/12','192.168.0.0/16','::1','fc00::/7']
LEGACY_UPSTREAMS=['https://dns.cloudflare.com/dns-query','https://dns.quad9.net/dns-query']
ROOT=pathlib.Path(os.environ.get('ALIREZA_ROOT','/var/lib/alirezaserver'))
BASE=os.environ.get('ALIREZA_ADGUARD_API','http://127.0.0.1:18085/control/')
def api(route,data=None):
    payload=None if data is None else json.dumps(data).encode()
    req=urllib.request.Request(BASE+route,data=payload,headers={'Content-Type':'application/json'})
    with urllib.request.urlopen(req,timeout=15) as response:
        raw=response.read();return json.loads(raw) if raw.strip() else None
def planned_changes(access,dns):
    new_access=None;new_dns={}
    if set(access.get('allowed_clients') or [])==set(LEGACY_CLIENTS):
        new_access={key:access.get(key) or [] for key in ['allowed_clients','disallowed_clients','blocked_hosts']}
        new_access['allowed_clients']=[]
    if dns.get('upstream_dns')==LEGACY_UPSTREAMS and not dns.get('upstream_dns_file'):
        new_dns['upstream_dns']=['1.1.1.1','9.9.9.9']
    return new_access,new_dns
def main():
    status=api('status')
    if status.get('dns_port')!=53 and not os.environ.get('ALIREZA_DNS_TEST'):
        raise RuntimeError('AdGuard must listen on DNS port 53; its stored configuration uses another port.')
    access=api('access/list');dns=api('dns_info')
    new_access,new_dns=planned_changes(access,dns)
    ROOT.mkdir(parents=True,exist_ok=True)
    before=ROOT/'dns-settings-before-0.3.json'
    if (new_access is not None or new_dns) and not before.exists():
        with open(before,'x',encoding='utf-8') as f:json.dump({'access':access,'dns':dns},f,indent=2)
        os.chmod(before,0o600)
    changed_access=False
    try:
        if new_access is not None:api('access/set',new_access);changed_access=True
        if new_dns:api('dns_config',new_dns)
    except Exception:
        if changed_access:
            try:api('access/set',{k:access.get(k) or [] for k in ['allowed_clients','disallowed_clients','blocked_hosts']})
            except Exception:pass
        raise
    if new_access is not None:print('DNS access: migrated old private-only default to public clients; rate limiting and block lists retained.')
    if new_dns:print('DNS upstreams: replaced the old default DoH-only pair with standard resolvers; custom settings retained.')
    print('AdGuard DNS configuration checked; custom filters, rewrites and accounts preserved.')
if __name__=='__main__':main()
ALIREZA_9758260493588EA4B7BB2A6F

cat > "$APP/firewall.py" <<'ALIREZA_3ABB9D4B1413044B7FBD9714'
#!/usr/bin/python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Own chains only. Never flush a system/UFW/Nova chain or change its policy."""
import fcntl, ipaddress, json, os, re, subprocess, sys
ROOT='/var/lib/alirezaserver'
def cmd(args,ok=True):
    p=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,timeout=20)
    if ok and p.returncode: raise RuntimeError(' '.join(args[:4])+': '+p.stderr[:500])
    return p
def ipt(table,*args,ok=True): return cmd(['iptables','-w','10','-t',table,*args],ok)
def hook(table,parent,chain):
    ipt(table,'-N',chain,ok=False)
    if ipt(table,'-C',parent,'-j',chain,ok=False).returncode: ipt(table,'-I',parent,'1','-j',chain)
    ipt(table,'-F',chain)
def main():
    os.makedirs('/run/alirezaserver',exist_ok=True)
    with open('/run/alirezaserver/firewall.lock','w') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX)
        chains=[('filter','INPUT','ALIREZA_IN'),('filter','FORWARD','ALIREZA_FWD'),('nat','POSTROUTING','ALIREZA_NAT'),('nat','PREROUTING','ALIREZA_DNS')]
        if '--remove' in sys.argv:
            for table,parent,chain in chains:
                while not ipt(table,'-C',parent,'-j',chain,ok=False).returncode: ipt(table,'-D',parent,'-j',chain)
                ipt(table,'-F',chain,ok=False);ipt(table,'-X',chain,ok=False)
            return
        settings=json.load(open(ROOT+'/install.json'))
        servers=json.load(open(ROOT+'/firewall.json'))
        default=json.loads(cmd(['ip','-j','-4','route','get','1.1.1.1']).stdout)
        if not default or not re.fullmatch(r'[A-Za-z0-9_.:-]{1,15}',default[0].get('dev','')): raise RuntimeError('No usable IPv4 default interface')
        wan=default[0]['dev']
        for table,parent,chain in chains:hook(table,parent,chain)
        for proto in ['udp','tcp']:ipt('filter','-A','ALIREZA_IN','-p',proto,'--dport','53','-j','ACCEPT')
        # The AdGuard HTTP service stays loopback-only and is never opened here.
        for s in servers:
            if not s['enabled']:continue
            if not re.fullmatch(r'[a-f0-9]{12}',s['id']):raise RuntimeError('Invalid server ID')
            network=ipaddress.ip_network(s['subnet'],strict=True)
            if network.version!=4 or network.prefixlen!=24 or not network.is_private:raise RuntimeError('Invalid subnet')
            proto=s['proto'];port=int(s['port'])
            if proto not in ['udp','tcp'] or not 1024<=port<=65535:raise RuntimeError('Invalid OpenVPN port')
            dev='az'+s['id'][:8];net=str(network)
            ipt('filter','-A','ALIREZA_IN','-p',proto,'--dport',str(port),'-j','ACCEPT')
            for p in ['udp','tcp']:
                ipt('filter','-A','ALIREZA_IN','-i',dev,'-s',net,'-p',p,'--dport','53','-j','ACCEPT')
                gateway=str(network.network_address+1)
                if s['dns']==gateway:
                    ipt('nat','-A','ALIREZA_DNS','-i',dev,'-d',gateway,'-p',p,'--dport','53','-j','DNAT','--to-destination',settings['dns_address']+':53')
            ipt('filter','-A','ALIREZA_IN','-i',dev,'-j','DROP')
            ipt('filter','-A','ALIREZA_FWD','-i',dev,'-s',net,'-o',wan,'-j','ACCEPT')
            ipt('filter','-A','ALIREZA_FWD','-i',wan,'-o',dev,'-d',net,'-m','conntrack','--ctstate','ESTABLISHED,RELATED','-j','ACCEPT')
            ipt('filter','-A','ALIREZA_FWD','-i',dev,'-j','DROP')
            ipt('nat','-A','ALIREZA_NAT','-s',net,'-o',wan,'-j','MASQUERADE')
        if any(s['enabled'] for s in servers):cmd(['sysctl','-w','net.ipv4.ip_forward=1'])
if __name__=='__main__':
    try:main()
    except Exception as e:print(str(e),file=sys.stderr);sys.exit(1)
ALIREZA_3ABB9D4B1413044B7FBD9714

cat > "$APP/model.mjs" <<'ALIREZA_432AFB97A4C3912B3644CBC4'
// SPDX-License-Identifier: GPL-3.0-or-later
// OpenVPN profile/configuration conventions adapted from Sir-MmD/vpn-ui,
// web/service/openvpn.go (8044e0ad45c60149439546ea0fd99371a4d3c03d).
// This adapter does not copy or install the other vpn-ui protocol backends.
import { isIP } from 'node:net';
export const CIPHERS = ['AES-256-GCM', 'AES-128-GCM', 'CHACHA20-POLY1305', 'AES-256-CBC', 'AES-128-CBC'];
export function fail(message, status = 400) { throw Object.assign(new Error(message), { status }); }
export function id(value) { if (!/^[a-f0-9]{12}$/.test(String(value))) fail('Invalid ID'); return value; }
export function host(value) {
  const s = String(value || '').trim().replace(/^\[|\]$/g, '');
  if (!isIP(s) && !/^(?=.{1,253}$)(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)*[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$/.test(s)) fail('Enter a valid server hostname or IP');
  return s;
}
export function integer(v, min, max, name) { const n=Number(v); if (!Number.isSafeInteger(n)||n<min||n>max) fail('Invalid '+name); return n; }
export function subnet(value) {
  const s=String(value||''); const m=s.match(/^(10|172|192)\.(\d+)\.(\d+)\.0\/24$/);
  if (!m || !isIP(s.split('/')[0]) || (m[1]==='172' && (+m[2]<16||+m[2]>31)) || (m[1]==='192' && +m[2]!==168)) fail('Use a private IPv4 /24 subnet, e.g. 10.231.10.0/24');
  return s;
}
export function validateServer(input) {
  const name=String(input.name||'').trim(); if (!name || name.length>80 || /[\r\n\x00-\x1f]/.test(name)) fail('Invalid name');
  const proto=String(input.proto||'udp'); if (!['udp','tcp'].includes(proto)) fail('Invalid transport');
  const dns=String(input.dns||'').trim(); if (isIP(dns)!==4) fail('DNS must be an IPv4 address');
  const ciphers=Array.isArray(input.ciphers)?[...new Set(input.ciphers)]:CIPHERS.slice(0,3);
  if (!ciphers.length || ciphers.some(c=>!CIPHERS.includes(c))) fail('Unsupported cipher');
  return { name, proto, port:integer(input.port,1024,65535,'port'), host:host(input.host), subnet:subnet(input.subnet), dns,
    mtu:integer(input.mtu??1500,1280,1500,'MTU'), maxClients:integer(input.maxClients??100,1,1000,'maximum clients'),
    ciphers, tlsCrypt:input.tlsCrypt!==false, clientToClient:input.clientToClient===true, enabled:input.enabled!==false };
}
export function validateUser(input, servers) {
  const username=String(input.username||'').trim(); if (!/^[a-zA-Z0-9_.@-]{1,64}$/.test(username)) fail('Username: use 1–64 letters, digits, _, ., @ or -');
  const password=String(input.password||''); if (password && (password.length<12 || password.length>128 || /[\r\n\0]/.test(password))) fail('Password must contain 12–128 characters');
  if (!Array.isArray(input.serverIds)||!input.serverIds.length||input.serverIds.some(v=>!servers.some(s=>s.id===v))) fail('Select at least one OpenVPN server');
  const expiry=input.expiry?Date.parse(input.expiry):0; if (!Number.isFinite(expiry)) fail('Invalid expiry');
  const quotaGB=Number(input.quotaGB||0); if (!Number.isFinite(quotaGB)||quotaGB<0||quotaGB>1000000) fail('Invalid traffic quota');
  return { username,password,serverIds:[...new Set(input.serverIds)], enabled:input.enabled!==false,
    expiry:Math.floor(expiry/1000), quota:Math.floor(quotaGB*1e9), devices:integer(input.devices??1,1,64,'device limit') };
}
export function serverConfig(s, root='/var/lib/alirezaserver') {
  id(s.id); const dir=`${root}/openvpn/${s.id}`; const cbc=s.ciphers.find(c=>c.endsWith('-CBC'));
  return [
    `port ${s.port}`,`proto ${s.proto==='tcp'?'tcp-server':'udp'}`,`dev az${s.id.slice(0,8)}`,'dev-type tun','topology subnet',
    `server ${s.subnet.split('/')[0]} 255.255.255.0`,
    // Block IPv6 on the client without requiring IPv6 on the VPS tunnel device.
    // OpenVPN's documented IPv4-only recipe works when host IPv6 is disabled.
    'push "ifconfig-ipv6 fd15:53b6:dead::2/64 fd15:53b6:dead::1"',
    'push "redirect-gateway def1 ipv6"','push "block-ipv6"','block-ipv6',`push "dhcp-option DNS ${s.dns}"`,
    `tun-mtu ${s.mtu}`,`mssfix ${Math.min(1400,s.mtu)}`,`max-clients ${s.maxClients}`,
    `ca ${dir}/ca.crt`,`cert ${dir}/server.crt`,`key ${dir}/server.key`,s.tlsCrypt?`tls-crypt ${dir}/tls-crypt.key`:'',
    'dh none','tls-version-min 1.2',`data-ciphers ${s.ciphers.join(':')}`,cbc?`data-ciphers-fallback ${cbc}`:'',
    'auth SHA256','verify-client-cert none','username-as-common-name','duplicate-cn','script-security 2',
    `auth-user-pass-verify "/opt/alirezaserver/auth.py auth ${s.id}" via-file`,
    `client-connect "/opt/alirezaserver/auth.py connect ${s.id}"`,
    `client-disconnect "/opt/alirezaserver/auth.py disconnect ${s.id}"`,
    'keepalive 10 120','persist-key','persist-tun',`status ${dir}/status.log 5`,'status-version 3',
    `management ${dir}/management.sock unix`,`writepid ${dir}/openvpn.pid`,'verb 3',
    s.proto==='udp'?'explicit-exit-notify 1':'',s.clientToClient?'client-to-client':''
  ].filter(Boolean).join('\n')+'\n';
}
export function clientConfig(s, ca, tlsCrypt) {
  const cbc=s.ciphers.find(c=>c.endsWith('-CBC'));
  return ['client','dev tun',`proto ${s.proto==='tcp'?'tcp-client':'udp'}`,`remote ${host(s.host)} ${s.port}`,
    'resolv-retry infinite','nobind','persist-key','persist-tun','remote-cert-tls server','tls-version-min 1.2',
    'auth-user-pass','auth-nocache','setenv CLIENT_CERT 0',`setenv FRIENDLY_NAME ${JSON.stringify(s.name)}`,
    `data-ciphers ${s.ciphers.join(':')}`,`cipher ${cbc||s.ciphers[0]}`,'auth SHA256','verb 3',
    s.proto==='udp'?'explicit-exit-notify 3':'',`<ca>\n${ca.trim()}\n</ca>`,
    s.tlsCrypt?`<tls-crypt>\n${tlsCrypt.trim()}\n</tls-crypt>`:''
  ].filter(Boolean).join('\n')+'\n';
}
export function parseStatus(text) {
  let fields=[],stamp=0; const clients=[];
  for (const line of text.split(/\r?\n/)) {
    const a=line.split('\t');
    if(a[0]==='TIME') stamp=Number(a.at(-1))||0;
    if(a[0]==='HEADER'&&a[1]==='CLIENT_LIST') fields=a.slice(2);
    if(a[0]==='CLIENT_LIST'&&fields.length) {
      const row=Object.fromEntries(fields.map((k,i)=>[k,a[i+1]]));
      const name=row['Common Name'], remote=row['Real Address'];
      if (!/^[a-zA-Z0-9_.@-]{1,64}$/.test(name||'')||!remote) continue;
      clients.push({name,remote,received:Number(row['Bytes Received'])||0,sent:Number(row['Bytes Sent'])||0,connected:Number(row['Connected Since (time_t)'])||0});
    }
  }
  return {stamp,clients};
}
ALIREZA_432AFB97A4C3912B3644CBC4

cat > "$APP/openvpn.html" <<'ALIREZA_2F88015A53409E5BC7A4783E'
<!doctype html>
<html lang="fa" dir="rtl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="dark light"><title>alirezaserver · OpenVPN</title>
<style>
:root{font-family:Vazirmatn,Tahoma,Arial,sans-serif;color-scheme:dark;--bg:#090b10;--panel:#12151d;--line:#282d3b;--text:#edf0f7;--muted:#969eb3;--accent:#a78bfa;--input:#0b0e15}*{box-sizing:border-box}body{margin:0;background:radial-gradient(ellipse at 15% 0%,#24194388,transparent 45%),var(--bg);color:var(--text);min-height:100vh}main{max-width:1300px;margin:auto;padding:32px}header{display:flex;justify-content:space-between;gap:20px;align-items:center;margin-bottom:28px}.eyebrow{color:var(--accent);font-size:12px;letter-spacing:2px}h1{font-size:32px;margin:10px 0}p{color:var(--muted);line-height:1.9;margin:8px 0}button,input,select{font:inherit}button{cursor:pointer;border:1px solid var(--line);border-radius:10px;padding:10px 16px;background:var(--panel);color:var(--text);transition:background .15s,transform .15s}button:hover{border-color:var(--accent)}button:active{transform:translateY(1px)}button:disabled{opacity:.5;cursor:wait}.primary{background:#7c3aed;color:white;border-color:#8b5cf6}.danger{color:#fda4af}.actions{display:flex;gap:8px;flex-wrap:wrap;align-items:center}.stats{display:grid;grid-template-columns:repeat(4,1fr);gap:16px;margin:24px 0}.stat,.card{background:var(--panel);border:1px solid var(--line);border-radius:16px;box-shadow:0 8px 32px #00000012}.stat{padding:20px}.stat span{color:var(--muted);font-size:13px}.stat strong{display:block;font-size:28px;margin-top:12px}.card{margin:22px 0;overflow:hidden}.card-head{display:flex;justify-content:space-between;align-items:center;padding:20px 24px;border-bottom:1px solid var(--line);gap:10px}h2{font-size:17px;margin:0}.scroll{overflow:auto}table{border-collapse:collapse;width:100%;text-align:start;white-space:nowrap}th,td{padding:16px 20px;border-bottom:1px solid var(--line);text-align:start}th{font-size:12px;color:var(--muted);font-weight:400}td{font-size:13px}tr:last-child td{border-bottom:0}td button{font-size:12px;padding:7px 10px}.badge{border-radius:20px;padding:5px 10px;background:#152d26;color:#7be5b3;font-size:11px}.badge.off{background:#312429;color:#fda4af}.muted{color:var(--muted)}.empty{padding:44px;text-align:center;color:var(--muted)}#message{display:none;padding:16px 20px;border:1px solid #773643;background:#351921;border-radius:12px;white-space:pre-wrap;overflow-wrap:anywhere;line-height:1.8}dialog{background:var(--panel);color:var(--text);border:1px solid var(--line);border-radius:18px;width:min(680px,96vw);max-height:92vh;padding:0;box-shadow:0 24px 90px #0008}dialog::backdrop{background:#0009;backdrop-filter:blur(4px)}.dialog-body{padding:24px}.form-grid{display:grid;grid-template-columns:1fr 1fr;gap:18px}label{display:grid;gap:9px;font-size:13px}input,select{width:100%;padding:11px;background:var(--input);color:var(--text);border:1px solid var(--line);border-radius:9px;min-width:0}input:focus,select:focus{outline:2px solid #8b5cf666;border-color:#8b5cf6}input[type=checkbox]{width:auto;accent-color:#8b5cf6}.check{display:flex;align-items:center;gap:10px}.full{grid-column:1/-1}.hint{font-size:12px;color:var(--muted);line-height:1.8}.dialog-foot{padding:18px 24px;display:flex;justify-content:end;gap:10px;border-top:1px solid var(--line)}pre{direction:ltr;text-align:left;white-space:pre-wrap;overflow-wrap:anywhere;font:12px/1.7 monospace}.mono{font-family:ui-monospace,monospace;direction:ltr;unicode-bidi:embed}.progress{height:4px;background:var(--line);border-radius:3px;margin-top:7px}.progress i{display:block;height:100%;background:#a78bfa;border-radius:3px}a{color:var(--accent)}@media(max-width:700px){main{padding:16px}.stats{grid-template-columns:1fr 1fr;gap:10px}.stat{padding:15px}.form-grid{grid-template-columns:1fr}.full{grid-column:auto}header{align-items:start}h1{font-size:25px}.card-head{padding:16px;flex-wrap:wrap}}@media(prefers-color-scheme:light){:root{color-scheme:light;--bg:#f6f7fb;--panel:white;--line:#e3e6ee;--text:#202536;--muted:#6b7285;--accent:#7c3aed;--input:#f8f9fc}body{background:radial-gradient(ellipse at 15% 0%,#e8ddff,transparent 45%),var(--bg)}#message{background:#fff0f3;color:#9f1239}}
</style><link rel="stylesheet" href="../assets/font.css"><link rel="stylesheet" href="../assets/theme.css"><script src="../assets/theme.js" data-surface="openvpn"></script></head><body><main>
<header><div><div class="eyebrow">ALIREZASERVER</div><h1>OpenVPN</h1><p data-t="intro"></p></div><div class="actions"><button id="lang">English</button><button id="refresh" data-t="refresh"></button></div></header>
<div id="message" role="alert"></div><div class="stats" id="stats"></div>
<section class="card"><div class="card-head"><h2 data-t="servers"></h2><button class="primary" id="add-server" data-t="addServer"></button></div><div class="scroll" id="servers"></div></section>
<section class="card"><div class="card-head"><h2 data-t="users"></h2><button class="primary" id="add-user" data-t="addUser"></button></div><div class="scroll" id="users"></div></section>
<p class="hint" data-t="note"></p>
</main><dialog id="editor"><form id="form"><div class="card-head"><h2 id="edit-title"></h2><button type="button" class="close" aria-label="Close">✕</button></div><div class="dialog-body"><div class="form-grid" id="fields"></div><p class="hint" id="form-note"></p><p id="form-error" role="alert" style="color:#fb7185;white-space:pre-wrap"></p></div><div class="dialog-foot"><button type="button" class="close" data-t="cancel"></button><button type="submit" class="primary" data-t="save"></button></div></form></dialog>
<dialog id="log-dialog"><div class="card-head"><h2 data-t="logs"></h2><button type="button" id="close-logs">✕</button></div><div class="dialog-body"><pre id="log-text"></pre></div></dialog>
<script>
'use strict';
const STR={fa:{intro:'مدیریت اتصال‌ها، حساب‌ها و فایل‌های اتصال OpenVPN',refresh:'تازه‌سازی',servers:'سرورهای OpenVPN',users:'حساب‌های OpenVPN',addServer:'＋ افزودن سرور',addUser:'＋ افزودن حساب',active:'فعال',inactive:'متوقف',online:'دستگاه آنلاین',traffic:'مصرف کل',name:'نام',transport:'انتقال',port:'پورت',status:'وضعیت',actions:'عملیات',edit:'ویرایش',remove:'حذف',profile:'فایل اتصال',logs:'گزارش',start:'فعال‌کردن',stop:'متوقف‌کردن',username:'نام کاربری',password:'رمز عبور',quota:'سهمیه (GB؛ صفر یعنی نامحدود)',expiry:'تاریخ انقضا؛ خالی یعنی نامحدود',devices:'حداکثر دستگاه هم‌زمان',used:'مصرف / سهمیه',reset:'صفرکردن مصرف',save:'ذخیره',cancel:'انصراف',empty:'هنوز موردی اضافه نشده است.',host:'آدرس عمومی سرور یا دامنه',subnet:'شبکه اختصاصی کاربران (/24)',dns:'آدرس DNS کاربران',mtu:'MTU',maxClients:'حداکثر اتصال سرور',tlsCrypt:'پنهان‌سازی کانال کنترل TLS-Crypt',clientToClient:'اجازه ارتباط کاربران با یکدیگر',enabled:'فعال',ciphers:'رمزنگاری‌های مجاز',choose:'انتخاب سرورهای مجاز',confirm:'این عملیات انجام شود؟',requiredServer:'ابتدا یک سرور OpenVPN بسازید.',note:'حساب‌های این بخش مستقل از حساب‌های قبلی پنل هستند. فایل اتصال را دریافت کنید و با نام کاربری و رمز عبور وارد شوید. سهمیه و انقضا برای همین اتصال‌های OpenVPN محاسبه می‌شوند.',serverNote:'برای تغییر سرور، اتصال‌های همان سرور دوباره برقرار می‌شوند. آدرس عمومی باید مستقیم به این سرور برسد. خروجی اینترنت IPv4 است و نشت IPv6 در پروفایل مسدود می‌شود.',userNote:'رمز عبور حداقل ۱۲ نویسه است. هنگام ویرایش، خالی بماند تا تغییر نکند. تغییر حساب اتصال‌های فعلی آن را قطع می‌کند.',working:'در حال انجام…',unlimited:'نامحدود'},en:{intro:'Manage OpenVPN connections, accounts and connection profiles',refresh:'Refresh',servers:'OpenVPN servers',users:'OpenVPN accounts',addServer:'＋ Add server',addUser:'＋ Add account',active:'Active',inactive:'Stopped',online:'Online devices',traffic:'Total traffic',name:'Name',transport:'Transport',port:'Port',status:'Status',actions:'Actions',edit:'Edit',remove:'Delete',profile:'Download profile',logs:'Logs',start:'Enable',stop:'Stop',username:'Username',password:'Password',quota:'Quota (GB; 0 = unlimited)',expiry:'Expiry date; blank = unlimited',devices:'Concurrent devices',used:'Used / quota',reset:'Reset usage',save:'Save',cancel:'Cancel',empty:'Nothing here yet.',host:'Public server address or hostname',subnet:'Private client network (/24)',dns:'Client DNS address',mtu:'MTU',maxClients:'Maximum server clients',tlsCrypt:'TLS-Crypt control-channel protection',clientToClient:'Allow clients to reach each other',enabled:'Enabled',ciphers:'Allowed ciphers',choose:'Allowed servers',confirm:'Proceed with this operation?',requiredServer:'Create an OpenVPN server first.',note:'These accounts are separate from existing panel accounts. Download the connection profile and sign in with the account username and password. Quotas and expiry apply to these OpenVPN connections.',serverNote:'Editing a server reconnects its clients. The public address must reach this server directly. Internet egress is IPv4; the profile blocks IPv6 leaks.',userNote:'Passwords need at least 12 characters. Leave blank when editing to keep the current password. Updating an account disconnects its current sessions.',working:'Working…',unlimited:'Unlimited'}};
let lang=localStorage.getItem('alireza-lang')||'fa', data={servers:[],users:[],sessions:[]},editing=null,busy=false;
const t=k=>STR[lang][k]||k, $=s=>document.querySelector(s), esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const base=location.pathname.replace(/openvpn\/$/,'');
async function api(path,method='GET',body){const r=await fetch(base+'api/'+path,{method,credentials:'same-origin',cache:'no-store',headers:body?{'Content-Type':'application/json'}:{},body:body?JSON.stringify(body):undefined});const text=await r.text();let j;try{j=JSON.parse(text);}catch{throw Error('HTTP '+r.status+': '+text.slice(0,400));}if(!r.ok)throw Error(j.error||r.status);return j;}
function message(text=''){const e=$('#message');e.textContent=text;e.style.display=text?'block':'none';}
function bytes(n){return (Number(n||0)/1e9).toLocaleString(lang==='fa'?'fa-IR':'en-US',{maximumFractionDigits:2})+' GB';}
function render(){document.documentElement.lang=lang;document.documentElement.dir=lang==='fa'?'rtl':'ltr';document.querySelectorAll('[data-t]').forEach(e=>e.textContent=t(e.dataset.t));$('#lang').textContent=lang==='fa'?'English':'فارسی';
  $('#stats').innerHTML=[[t('servers'),data.servers.length],[t('users'),data.users.length],[t('online'),data.sessions.length],[t('traffic'),bytes(data.users.reduce((n,u)=>n+u.used,0))]].map(([k,v])=>'<div class="stat"><span>'+esc(k)+'</span><strong>'+esc(v)+'</strong></div>').join('');
  const button=(kind,key,op,label,cls='')=>`<button class="${cls}" data-kind="${kind}" data-key="${key}" data-op="${op}">${esc(t(label))}</button>`;
  $('#servers').innerHTML=data.servers.length?`<table><thead><tr>${['name','transport','port','status','actions'].map(k=>'<th>'+t(k)+'</th>').join('')}</tr></thead><tbody>${data.servers.map(s=>`<tr><td><b>${esc(s.name)}</b><div class="hint mono">${esc(s.host)}</div></td><td>${esc(s.proto.toUpperCase())}</td><td class="mono">${s.port}</td><td><span class="badge ${s.status==='active'?'':'off'}">${t(s.status==='active'?'active':'inactive')}</span></td><td><div class="actions">${button('servers',s.id,'edit','edit')}${button('servers',s.id,'profile','profile')}${button('servers',s.id,'toggle',s.enabled?'stop':'start')}${button('servers',s.id,'logs','logs')}${button('servers',s.id,'delete','remove','danger')}</div></td></tr>`).join('')}</tbody></table>`:'<div class="empty">'+t('empty')+'</div>';
  $('#users').innerHTML=data.users.length?`<table><thead><tr>${['username','servers','used','expiry','devices','status','actions'].map(k=>'<th>'+t(k)+'</th>').join('')}</tr></thead><tbody>${data.users.map(u=>{const active=u.enabled&&(!u.expiry||u.expiry>Date.now()/1000)&&(!u.quota||u.used<u.quota);return `<tr><td class="mono">${esc(u.username)}</td><td>${esc(u.serverIds.map(id=>data.servers.find(s=>s.id===id)?.name||id).join(', '))}</td><td>${esc(bytes(u.used))} / ${u.quota?esc(bytes(u.quota)):t('unlimited')}<div class="progress"><i style="width:${u.quota?Math.min(100,u.used/u.quota*100):0}%"></i></div></td><td>${u.expiry?esc(new Date(u.expiry*1000).toLocaleString(lang==='fa'?'fa-IR':'en-US')):'—'}</td><td>${data.sessions.filter(s=>s.name===u.username).length} / ${u.devices}</td><td><span class="badge ${active?'':'off'}">${t(active?'active':'inactive')}</span></td><td><div class="actions">${button('users',u.id,'edit','edit')}${button('users',u.id,'reset','reset')}${button('users',u.id,'delete','remove','danger')}</div></td></tr>`;}).join('')}</tbody></table>`:'<div class="empty">'+t('empty')+'</div>';
}
async function refresh(){try{data=await api('status');render();message();}catch(e){message(e.message);}}
function field(key,value,type='text',extra=''){return `<label>${esc(t(key))}<input name="${key}" type="${type}" value="${esc(value)}" ${extra}></label>`;}
function check(key,value){return `<label class="check"><input type="checkbox" name="${key}" ${value?'checked':''}>${esc(t(key))}</label>`;}
async function edit(kind,key){if(busy)return;if(kind==='users'&&!data.servers.length){message(t('requiredServer'));return;}const old=data[kind].find(x=>x.id===key);editing={kind,key};$('#edit-title').textContent=t(old?'edit':kind==='servers'?'addServer':'addUser');$('#form-error').textContent='';
  let suggested={};if(kind==='servers'&&!old){busy=true;try{suggested=await api('server-defaults');}catch(e){message(e.message);}finally{busy=false;}}
  if(kind==='servers'){const s=old||{name:'OpenVPN',proto:'udp',port:suggested.port??(1194+data.servers.length),host:location.hostname,subnet:suggested.subnet||`10.231.${10+data.servers.length}.0/24`,dns:suggested.dns||('10.231.'+(10+data.servers.length)+'.1'),mtu:1500,maxClients:100,enabled:true,tlsCrypt:true,clientToClient:false,ciphers:['AES-256-GCM','AES-128-GCM','CHACHA20-POLY1305']};
    $('#fields').innerHTML=field('name',s.name,'text','required maxlength="80"')+field('host',s.host,'text','required dir="ltr"')+`<label>${t('transport')}<select name="proto"><option value="udp" ${s.proto==='udp'?'selected':''}>UDP</option><option value="tcp" ${s.proto==='tcp'?'selected':''}>TCP</option></select></label>`+field('port',s.port,'number','required min="1024" max="65535"')+field('subnet',s.subnet,'text','required dir="ltr"')+field('dns',s.dns,'text','required dir="ltr"')+field('mtu',s.mtu,'number','min="1280" max="1500"')+field('maxClients',s.maxClients,'number','min="1" max="1000"')+`<label class="full">${t('ciphers')}<select name="ciphers" multiple size="5">${['AES-256-GCM','AES-128-GCM','CHACHA20-POLY1305','AES-256-CBC','AES-128-CBC'].map(c=>`<option ${s.ciphers.includes(c)?'selected':''}>${c}</option>`).join('')}</select></label>`+check('tlsCrypt',s.tlsCrypt)+check('clientToClient',s.clientToClient)+check('enabled',s.enabled);$('#form-note').textContent=t('serverNote');
  }else{const u=old||{username:'',serverIds:data.servers.map(s=>s.id),enabled:true,devices:1,quota:0,expiry:0};const date=u.expiry?new Date(u.expiry*1000-new Date(u.expiry*1000).getTimezoneOffset()*60000).toISOString().slice(0,16):'';
    $('#fields').innerHTML=field('username',u.username,'text',`required dir="ltr" ${old?'readonly':''} maxlength="64"`)+field('password','','password',`${old?'':'required'} minlength="12" maxlength="128" autocomplete="new-password" dir="ltr"`)+field('quota',u.quota/1e9,'number','min="0" step="0.01"')+field('devices',u.devices,'number','min="1" max="64"')+field('expiry',date,'datetime-local')+check('enabled',u.enabled)+`<label class="full">${t('choose')}<select name="serverIds" multiple size="${Math.min(5,data.servers.length)}" required>${data.servers.map(s=>`<option value="${s.id}" ${u.serverIds.includes(s.id)?'selected':''}>${esc(s.name)} · ${s.proto.toUpperCase()} ${s.port}</option>`).join('')}</select></label>`;$('#form-note').textContent=t('userNote');}
  $('#editor').showModal();
}
$('#form').onsubmit=async e=>{e.preventDefault();if(busy)return;busy=true;const submit=e.submitter||e.target.querySelector('[type="submit"]');submit.disabled=true;const f=new FormData(e.target),o=Object.fromEntries(f);for(const k of ['enabled','tlsCrypt','clientToClient'])o[k]=f.has(k);o.ciphers=f.getAll('ciphers');o.serverIds=f.getAll('serverIds');o.quotaGB=o.quota;if(o.expiry)o.expiry=new Date(o.expiry).toISOString();try{await api(editing.kind+(editing.key?'/'+editing.key:''),editing.key?'PUT':'POST',o);$('#editor').close();await refresh();}catch(e){$('#form-error').textContent=e.message;}finally{busy=false;submit.disabled=false;}};
document.querySelectorAll('.close').forEach(b=>b.onclick=()=>{if(!busy)$('#editor').close();});$('#close-logs').onclick=()=>$('#log-dialog').close();
document.body.addEventListener('click',async e=>{const b=e.target.closest('[data-op]');if(!b||busy)return;const{kind,key,op}=b.dataset;if(op==='edit'){edit(kind,key);return;}if(op==='profile'){const a=document.createElement('a');a.href=base+'api/servers/'+key+'/profile';a.download='alirezaserver.ovpn';a.click();return;}if(op!=='logs'&&!confirm(t('confirm')))return;busy=true;b.disabled=true;try{if(op==='logs'){$('#log-text').textContent=(await api('servers/'+key+'/logs')).logs;$('#log-dialog').showModal();}else{await api(kind+'/'+key+(op==='delete'?'':'/'+op),op==='delete'?'DELETE':'POST',{});await refresh();}}catch(e){message(e.message);}finally{busy=false;b.disabled=false;}});
$('#add-server').onclick=()=>edit('servers');$('#add-user').onclick=()=>edit('users');$('#refresh').onclick=refresh;$('#lang').onclick=()=>{lang=lang==='fa'?'en':'fa';localStorage.setItem('alireza-lang',lang);render();};
render();refresh();setInterval(()=>{if(!document.hidden&&!busy&&!$('#editor').open&&!$('#log-dialog').open)refresh();},15000);
</script></body></html>
ALIREZA_2F88015A53409E5BC7A4783E

cat > "$APP/preload.mjs" <<'ALIREZA_F1DEF3F57E5BD2D2DB009F40'
// SPDX-License-Identifier: GPL-3.0-or-later
// Loaded only into Nova's existing Node process. Original Nova files are unmodified.
import http from 'node:http';
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import * as backend from './backend.mjs';
import {fontCSS,dnsStatusForPanel} from './theme.mjs';
const HERE=dirname(fileURLToPath(import.meta.url));
const previous=http.Server.prototype.emit;
let readonly;
function settings() {
  try {
    readonly ||= new DatabaseSync(process.env.NOVA_DB||'/var/lib/nova/nova.db',{readOnly:true});
    const row=readonly.prepare('SELECT v FROM kvstore WHERE k=?').get('network-settings.json');
    return JSON.parse(row?.v||'{}');
  }catch{return null;}
}
function basePath() {const s=settings();if(!s)return null;const p=String(s.panelPath||'').replace(/^\/+|\/+$/g,'');return p?'/'+p:'';}
export function injectHTML(html,base) {
  if(!html.includes('id="app"')&&!html.includes('id="root"')&&!html.includes('const IC=')) return html;
  if(html.includes('data-alireza-addon'))return html;
  return html.replace(/<title>Nova Server<\/title>/,'<title>alirezaserver</title>').replace('</body>',
    `<script data-alireza-addon src="${base}/alireza/brand.js"></script></body>`);
}
function wrapHTML(req,res) {
  const end=res.end, write=res.write, writeHead=res.writeHead; let wrote=false,pendingHead=null;
  res.writeHead=function(status,reason,headers) {
    const h=(typeof reason==='object'?reason:headers)||{};
    const type=Object.entries(h).find(([k])=>k.toLowerCase()==='content-type')?.[1]||this.getHeader('content-type');
    if(String(type).includes('text/html')) {
      this.statusCode=status;if(typeof reason==='string')this.statusMessage=reason;
      for(const[k,v]of Object.entries(h))this.setHeader(k,v);
      pendingHead=true;return this;
    }
    return writeHead.apply(this,arguments);
  };
  function flushHead(){res.writeHead=writeHead;if(pendingHead){pendingHead=null;writeHead.call(res,res.statusCode);}}
  const flushHeaders=res.flushHeaders;
  res.flushHeaders=function(){wrote=true;flushHead();return flushHeaders.call(this);};
  res.write=function(...args){wrote=true;flushHead();return write.apply(this,args);};
  res.end=function(chunk,...args) {
    try {
      const type=String(this.getHeader('content-type')||'');
      const base=basePath();
      if(base!==null&&!wrote&&!this.headersSent&&!this.getHeader('content-encoding')&&type.includes('text/html')&&chunk) {
        const text=Buffer.isBuffer(chunk)?chunk.toString('utf8'):String(chunk);
        const result=injectHTML(text,base);
        if(result!==text){chunk=Buffer.from(result);this.removeHeader('etag');this.setHeader('content-length',chunk.length);this.setHeader('cache-control','no-store');}
      }
    }catch(e){console.error('alirezaserver branding:',e.message);}
    flushHead();return end.call(this,chunk,...args);
  };
}
function json(res,status,value) {res.writeHead(status,{'content-type':'application/json; charset=utf-8','cache-control':'no-store','x-content-type-options':'nosniff'});res.end(JSON.stringify(value));}
function file(res,name,type) {const b=readFileSync(join(HERE,name));res.writeHead(200,{'content-type':type,'cache-control':'no-store','x-content-type-options':'nosniff','x-frame-options':'SAMEORIGIN'});res.end(b);}
async function whoami(req,base) {
  return new Promise((resolve,reject)=>{
    const local=http.request({hostname:'127.0.0.1',port:req.socket.localPort,path:base+'/admin/whoami',method:'GET',
      headers:{host:req.headers.host||'localhost',cookie:req.headers.cookie||'','user-agent':req.headers['user-agent']||'','accept':'application/json'},timeout:5000},response=>{
      let s='';response.on('data',b=>{s+=b;if(s.length>128000)local.destroy(new Error('Invalid auth response'));});
      response.on('end',()=>{try{if(response.statusCode!==200)resolve(null);else resolve(JSON.parse(s));}catch{resolve(null);}});
    });local.on('timeout',()=>local.destroy(new Error('Authentication timed out')));local.on('error',reject);local.end();
  });
}
export function sameOrigin(req) {
  try{const origin=new URL(req.headers.origin);return ['https:','http:'].includes(origin.protocol)&&origin.host===req.headers.host;}catch{return false;}
}
async function body(req) {
  let text='';for await(const part of req){text+=part;if(Buffer.byteLength(text)>131072)throw Object.assign(new Error('Request too large'),{status:413});}
  try{return JSON.parse(text||'{}');}catch{throw Object.assign(new Error('Invalid JSON'),{status:400});}
}
export function redirectLocation(value,prefix) {
  if(value?.startsWith('/')&&!value.startsWith('//'))return prefix+value.slice(1);
  try{const u=new URL(value,'http://127.0.0.1:18085');if(['127.0.0.1','localhost','0.0.0.0','[::1]'].includes(u.hostname))return prefix+u.pathname.replace(/^\//,'')+u.search+u.hash;}catch{}
  return value;
}
function adguard(req,res,path,prefix) {
  // Never forward the Nova session or arbitrary upstream Host/Authorization headers.
  const headers={host:'127.0.0.1:18085','accept-encoding':'identity'};
  for(const key of ['content-type','content-length','accept','user-agent','if-none-match'])if(req.headers[key])headers[key]=req.headers[key];
  const remote=http.request({host:'127.0.0.1',port:18085,path:'/'+path,method:req.method,headers,timeout:120000},response=>{
    const out={...response.headers,'x-frame-options':'SAMEORIGIN','cache-control':'no-store'};
    if(out.location)out.location=redirectLocation(out.location,prefix);
    if(out['set-cookie'])out['set-cookie']=out['set-cookie'].map(c=>c.replace(/Path=\//i,'Path='+prefix));
    if(path.split('?')[0]==='control/status'&&response.statusCode===200){
      let body='';response.on('data',b=>{body+=b;if(body.length>131072)remote.destroy(new Error('Upstream status too large'));});
      response.on('end',()=>{if(res.destroyed||res.writableEnded)return;try{
        const status=JSON.parse(body);const publicHost=String(settings()?.host||new URL('http://'+req.headers.host).hostname);
        const result=JSON.stringify(dnsStatusForPanel(status,publicHost));delete out['content-length'];delete out.etag;res.writeHead(200,out);res.end(result);
      }catch{json(res,502,{error:'Invalid AdGuard status response'});}});
    }else if(String(out['content-type']).includes('text/html')) {
      let chunks=[],size=0;response.on('data',b=>{size+=b.length;if(size>4194304)remote.destroy(new Error('Upstream page too large'));else chunks.push(b);});
      response.on('end',()=>{if(res.destroyed||res.writableEnded)return;let content=Buffer.concat(chunks).toString('utf8');
        const assets=prefix.replace(/dns\/$/,'')+'assets/';
        content=content.replace('</head>',`<link data-alireza-colors rel="stylesheet" href="${assets}font.css"><link rel="stylesheet" href="${assets}theme.css"><script src="${assets}theme.js" data-surface="dns"></script></head>`);
        delete out['content-length'];delete out.etag;res.writeHead(response.statusCode||502,out);res.end(content);
      });
    }else {res.writeHead(response.statusCode||502,out);response.pipe(res);}
    response.on('error',()=>res.destroy());
  });
  remote.on('timeout',()=>remote.destroy(new Error('AdGuard request timed out')));
  remote.on('error',e=>{if(!res.headersSent)json(res,502,{error:'AdGuard is unavailable: '+e.message});else res.destroy();});
  req.on('aborted',()=>remote.destroy());res.on('close',()=>remote.destroy());req.pipe(remote);
}
let queue=Promise.resolve(),pending=0;
function serialized(action) {
  if(pending>=10)throw Object.assign(new Error('Another operation is running; retry shortly'),{status:429});
  pending++;const result=queue.then(action);queue=result.catch(()=>{}).finally(()=>pending--);return result;
}
async function handle(req,res,base,tail) {
  if(tail==='brand.js'&&req.method==='GET'){file(res,'brand.js','text/javascript; charset=utf-8');return;}
  const auth=await whoami(req,base);
  if(!auth){json(res,401,{error:'Sign in to the main panel first.'});return;}
  if(auth.role!=='owner'){json(res,403,{error:'These services are available to the panel owner.'});return;}
  if(!['GET','HEAD'].includes(req.method)&&!sameOrigin(req)){json(res,403,{error:'Same-origin request required'});return;}
  if(tail==='assets/font.css'&&req.method==='GET'){res.writeHead(200,{'content-type':'text/css; charset=utf-8','cache-control':'private, max-age=86400'});res.end(fontCSS());return;}
  if(tail==='assets/theme.css'&&req.method==='GET'){file(res,'theme.css','text/css; charset=utf-8');return;}
  if(tail==='assets/theme.js'&&req.method==='GET'){file(res,'theme.js','text/javascript; charset=utf-8');return;}
  if(tail==='api/server-defaults'&&req.method==='GET'){json(res,200,await backend.serverDefaults());return;}
  if(tail==='openvpn/'&&req.method==='GET'){file(res,'openvpn.html','text/html; charset=utf-8');return;}
  if(tail.startsWith('dns/')){adguard(req,res,tail.slice(4),base+'/alireza/dns/');return;}
  if(tail==='api/status'&&req.method==='GET'){json(res,200,await backend.status());return;}
  const match=tail.match(/^api\/(servers|users)(?:\/([a-f0-9]{12}))?(?:\/(profile|logs|toggle|reset))?$/);
  if(!match){json(res,404,{error:'Not found'});return;}
  const[,kind,key,operation]=match;
  if(kind==='servers'&&key&&operation==='profile'&&req.method==='GET') {
    res.writeHead(200,{'content-type':'application/x-openvpn-profile','content-disposition':`attachment; filename="alirezaserver-${key}.ovpn"`,'cache-control':'no-store'});res.end(backend.profile(key));return;
  }
  if(kind==='servers'&&key&&operation==='logs'&&req.method==='GET'){json(res,200,{logs:await backend.logs(key)});return;}
  if(!['POST','PUT','DELETE'].includes(req.method)){json(res,405,{error:'Method not allowed'});return;}
  const data=await body(req);
  const result=await serialized(async()=>{
    if(req.method==='DELETE'&&key&&!operation)return kind==='servers'?backend.removeServer(key):backend.removeUser(key);
    if(req.method==='POST'&&operation==='toggle'&&key&&kind==='servers')return backend.toggle(key);
    if(req.method==='POST'&&operation==='reset'&&key&&kind==='users')return backend.resetUsage(key);
    if(!operation&&((req.method==='POST'&&!key)||(req.method==='PUT'&&key)))return kind==='servers'?backend.save(data,key):backend.saveUser(data,key);
    throw Object.assign(new Error('Invalid operation'),{status:400});
  });json(res,200,{ok:true,result});
}
if(process.env.ALIREZA_NO_HOOK!=='1') {
  http.Server.prototype.emit=function(event,...args) {
    if(event!=='request')return previous.call(this,event,...args);
    const[req,res]=args;const base=basePath();
    if(base!==null&&req.url?.startsWith(base+'/alireza/')) {
      // Reject ambiguous URL spellings instead of passing them to another handler.
      const tail=req.url.slice((base+'/alireza/').length);
      if(/[\\\x00-\x20]/.test(tail)||/%2f|%5c|%2e/i.test(tail)||tail.split('?')[0].split('/').includes('..')){json(res,400,{error:'Invalid path'});return true;}
      handle(req,res,base,tail).catch(e=>{console.error('alirezaserver:',e.message);if(!res.headersSent)json(res,e.status||500,{error:e.message});else res.destroy();});return true;
    }
    wrapHTML(req,res);return previous.call(this,event,...args);
  };
  backend.startCollector();
}
ALIREZA_F1DEF3F57E5BD2D2DB009F40

cat > "$APP/reset-sessions.py" <<'ALIREZA_9D3D2A690AE74AB0156A9F9F'
#!/usr/bin/python3
import os, re, sqlite3, sys, time
sid=sys.argv[1]
if not re.fullmatch(r'[a-f0-9]{12}',sid):sys.exit(1)
db=sqlite3.connect('/var/lib/alirezaserver/addon.db',timeout=10)
db.execute('UPDATE sessions SET ended=? WHERE sid=?',(int(time.time()),sid))
db.commit();db.close()
for name in ['status.log','management.sock','openvpn.pid']:
    try:os.unlink('/var/lib/alirezaserver/openvpn/'+sid+'/'+name)
    except FileNotFoundError:pass
ALIREZA_9D3D2A690AE74AB0156A9F9F

cat > "$APP/rollback.sh" <<'ALIREZA_5268350BD706A64686202416'
#!/usr/bin/env bash
# Disable only alirezaserver additions. Keep user databases/certificates for recovery.
set -euo pipefail
[[ $EUID == 0 ]] || { echo 'Run as root.' >&2; exit 1; }
systemctl list-unit-files 'alireza-openvpn@*.service' --no-legend | while read -r unit _; do
  if [[ "$unit" =~ ^alireza-openvpn@[a-f0-9]{12}\.service$ ]]; then systemctl disable --now "$unit" || true; fi
done
systemctl disable --now AdGuardHome.service alireza-firewall.service || true
/opt/alirezaserver/firewall.py --remove || echo 'Some add-on firewall rules could not be removed; inspect ALIREZA_* chains.' >&2
rm -f -- /etc/systemd/system/nova-agent.service.d/alirezaserver.conf
rm -f -- /etc/systemd/system/nova-agent.service.d/zz-alirezaserver.conf
rm -f -- /etc/systemd/system/nova-node-agent.service.d/alirezaserver.conf
systemctl daemon-reload
if systemctl cat nova-agent.service >/dev/null 2>&1; then systemctl restart nova-agent.service
elif systemctl cat nova-node-agent.service >/dev/null 2>&1; then systemctl restart nova-node-agent.service; fi
echo 'alirezaserver add-ons disabled; original Nova files and add-on data preserved.'
ALIREZA_5268350BD706A64686202416

cat > "$APP/theme.css" <<'ALIREZA_795FE37FD4E8B8A4BF11F9F8'
/* SPDX-License-Identifier: GPL-3.0-or-later
   Shared appearance only. No positioning, ordering or control removal in AdGuard. */
:root{--az-bg:#070809;--az-panel:#0c0e12;--az-card:#101319;--az-card2:#0b0d11;--az-bd:#1c2027;--az-bd2:#262b34;--az-tx:#e9edf4;--az-tx2:#aeb6c4;--az-mu:#7c8698;--az-ac:#22d3ee;--az-ac2:#7c5cff;--az-ac-ink:#04121a;--az-grad:linear-gradient(120deg,#22d3ee,#7c5cff);--az-ok:#34d399;--az-dg:#f87171}
html[data-alireza-surface]{--bg:var(--az-bg);--panel:var(--az-panel);--line:var(--az-bd);--text:var(--az-tx);--muted:var(--az-mu);--accent:var(--az-ac);--input:var(--az-card2);--primary:var(--az-ac);--primary-bg:var(--az-ac);--primary-color:var(--az-ac);font-family:Vazirmatn,Tahoma,sans-serif!important}
html[data-alireza-surface] body{font-family:Vazirmatn,Tahoma,sans-serif!important;background:radial-gradient(ellipse at 10% 0%,color-mix(in srgb,var(--az-ac) 9%,transparent),transparent 48%),radial-gradient(ellipse at 95% 10%,color-mix(in srgb,var(--az-ac2) 9%,transparent),transparent 40%),var(--az-bg)!important;color:var(--az-tx)!important}
html[data-alireza-surface] :is(button,input,select,textarea,.btn,.form-control){font-family:Vazirmatn,Tahoma,sans-serif!important}
html[data-alireza-surface] :is(.card,.stat,.modal-content,dialog,.dropdown-menu,.popover){background:var(--az-card)!important;color:var(--az-tx)!important;border-color:var(--az-bd)!important;border-radius:16px;box-shadow:0 12px 36px #0002,inset 0 1px 0 color-mix(in srgb,var(--az-tx) 4%,transparent)}
html[data-alireza-surface] :is(.card-header,.card-head,.card-footer,.modal-header,.modal-footer,.dialog-foot,.header,.footer,.navbar){background:var(--az-panel)!important;color:var(--az-tx)!important;border-color:var(--az-bd)!important}
html[data-alireza-surface] :is(h1,h2,h3,h4,h5,h6,.card-title,.form-label,.nav-link,.dropdown-item){color:var(--az-tx)!important}
html[data-alireza-surface] :is(.text-muted,.hint,.card-subtitle,.form-text,.form-description){color:var(--az-mu)!important}
html[data-alireza-surface] :is(a,.nav-link.active,.eyebrow){color:var(--az-ac)!important}
html[data-alireza-surface] :is(input:not([type=checkbox]):not([type=radio]),select,textarea,.form-control,.input-group-text){background:var(--az-card2)!important;color:var(--az-tx)!important;border-color:var(--az-bd2)!important;border-radius:10px}
html[data-alireza-surface] :is(button,.btn,input,select,textarea,.card,.stat){transition:background-color .18s ease,border-color .18s ease,box-shadow .18s ease,transform .18s ease}
html[data-alireza-surface] :is(input,select,textarea):focus{outline:none!important;border-color:var(--az-ac)!important;box-shadow:0 0 0 3px color-mix(in srgb,var(--az-ac) 18%,transparent)!important}
html[data-alireza-surface] :is(button,.btn){border-radius:10px}
html[data-alireza-surface] :is(button,.btn):not(:disabled):hover{border-color:var(--az-ac)!important;box-shadow:0 0 18px color-mix(in srgb,var(--az-ac) 12%,transparent)}
html[data-alireza-surface] :is(.btn-primary,.primary){background:var(--az-grad)!important;border-color:transparent!important;color:#fff!important;box-shadow:0 5px 22px color-mix(in srgb,var(--az-ac2) 20%,transparent)}
html[data-alireza-surface] :is(.btn-secondary,.btn-outline-secondary){background:var(--az-card2)!important;color:var(--az-tx)!important;border-color:var(--az-bd2)!important}
html[data-alireza-surface] :is(table,.table,.ReactTable,.rt-table,.rt-thead,.rt-tbody,.rt-tr,.rt-td,.rt-th){background:transparent!important;color:var(--az-tx)!important;border-color:var(--az-bd)!important}
html[data-alireza-surface] :is(th,td,.rt-tr-group){border-color:var(--az-bd)!important}
html[data-alireza-surface] :is(tbody tr,.rt-tr-group):hover{background:color-mix(in srgb,var(--az-ac) 5%,transparent)!important}
html[data-alireza-surface] .custom-switch-input:checked~.custom-switch-indicator{background:var(--az-ac)!important}
html[data-alireza-surface] :is(.progress i,.progress-bar){background:var(--az-grad)!important}
html[data-alireza-surface] :is(input[type=checkbox],input[type=radio]){accent-color:var(--az-ac)}
html[data-alireza-surface] dialog::backdrop{background:#0009;backdrop-filter:blur(8px)}
html[data-alireza-surface] :is(.alert-danger,#message){background:color-mix(in srgb,var(--az-dg) 12%,var(--az-card))!important;color:var(--az-tx)!important;border-color:color-mix(in srgb,var(--az-dg) 45%,var(--az-bd))!important}
html[data-alireza-surface] .az-connection{padding:12px 18px;margin:12px 0;border:1px solid var(--az-bd2);border-radius:12px;background:var(--az-panel);line-height:1.9}
@media(prefers-reduced-motion:reduce){html[data-alireza-surface] *{transition:none!important;animation:none!important;scroll-behavior:auto!important}}
ALIREZA_795FE37FD4E8B8A4BF11F9F8

cat > "$APP/theme.js" <<'ALIREZA_61592532497513AA58EFACF7'
/* SPDX-License-Identifier: GPL-3.0-or-later */
(()=>{
  const root=document.documentElement;
  root.dataset.alirezaSurface=document.currentScript?.dataset.surface||'dns';
  function sync(){
    try{
      if(parent===window)return;
      const host=parent.document.documentElement,css=parent.getComputedStyle(host);
      for(const token of ['bg','panel','card','card2','bd','bd2','tx','tx2','mu','ac','ac2','ac-ink','ac-hover','grad','ok','wn','dg']){
        const value=css.getPropertyValue('--'+token).trim();if(value)root.style.setProperty('--az-'+token,value);
      }
      const light=host.dataset.theme==='light'||(host.dataset.theme!=='dark'&&parent.matchMedia('(prefers-color-scheme: light)').matches);
      root.style.colorScheme=light?'light':'dark';root.dataset.azTheme=light?'light':'dark';
    }catch{}
  }
  sync();
  try{new MutationObserver(sync).observe(parent.document.documentElement,{attributes:true,attributeFilter:['data-theme','class','style']});}catch{}
  matchMedia('(prefers-color-scheme: light)').addEventListener('change',sync);
  document.addEventListener('visibilitychange',()=>{if(!document.hidden)sync();});
})();
ALIREZA_61592532497513AA58EFACF7

cat > "$APP/theme.mjs" <<'ALIREZA_65D697BEB11FB9F040BF8499'
// SPDX-License-Identifier: GPL-3.0-or-later
// Reuse the installed Nova font without changing or copying its original files.
import{readFileSync}from'node:fs';
import{isIP}from'node:net';
let cached;
export function fontCSS(){
  if(cached)return cached;
  const panel=readFileSync(process.env.ALIREZA_NOVA_PANEL||'/opt/nova-node-agent/src/web/panel.html','utf8');
  const face=[...panel.matchAll(/@font-face\s*\{[^}]+\}/g)].map(m=>m[0]).find(s=>/Vazirmatn/.test(s)&&/data:font\/woff2;base64,/.test(s));
  if(!face)throw Error('The installed Nova Vazirmatn font was not found');
  return cached=face+'\n';
}
export function dnsStatusForPanel(status,publicHost){
  const result={...status};
  const usable=a=>typeof a==='string'&&a!=='::1'&&!a.startsWith('127.')&&a!=='0.0.0.0'&&a!=='::';
  const addresses=(Array.isArray(status.dns_addresses)?status.dns_addresses:[]).filter(usable);
  // This field is only an advertised address for the UI; listeners remain real.
  // DNS listeners in this integration are IPv4. A panel domain may point to a
  // CDN or IPv6-only proxy, so it must not be advertised as a DNS listener.
  if(isIP(publicHost||'')===4&&usable(publicHost))addresses.unshift(publicHost);
  result.dns_addresses=[...new Set(addresses)];return result;
}
ALIREZA_65D697BEB11FB9F040BF8499

cat > "$APP/verify-install.mjs" <<'ALIREZA_81984B06A9A160437D03A905'
// SPDX-License-Identifier: GPL-3.0-or-later
// Runs locally as root; creates a short-lived owner cookie in memory, never logs it.
// The native signing key is initialized only if this is the very first session.
// No passwords, accounts or protocol configuration are changed. A unique DNS
// test rewrite is added and removed in finally, when rewrites are enabled.
import {readFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {DatabaseSync} from 'node:sqlite';
import http from 'node:http';
import https from 'node:https';
import {isIP} from 'node:net';
import {randomBytes} from 'node:crypto';
import {checkDNS} from './check-dns.mjs';
const envFile=process.env.ALIREZA_VERIFY_ENV||'/etc/nova/agent.env';
const env=readFileSync(envFile,'utf8');
const value=name=>env.split(/\r?\n/).find(l=>l.startsWith(name+'='))?.slice(name.length+1).replace(/^(['"])(.*)\1$/,'$2');
const dbPath=value('NOVA_DB')||'/var/lib/nova/nova.db';
const db=new DatabaseSync(dbPath,{readOnly:true});
const kv={get:async key=>db.prepare('SELECT v FROM kvstore WHERE k=?').get(key)?.v,put:async(key,v)=>{
  // Nova normally creates auto_key on the first browser login. A fresh install
  // has only admin_pass; let its own makeSession initialize the missing key.
  // INSERT OR IGNORE preserves every pre-existing signing key and session.
  if(key!=='auto_key')throw Error('Unexpected authentication write during verification');
  const writer=new DatabaseSync(dbPath);
  try{writer.exec('PRAGMA busy_timeout=10000');writer.prepare('INSERT OR IGNORE INTO kvstore(k,v,updated) VALUES(?,?,?)').run(key,v,Date.now());}finally{writer.close();}
}};
const s=JSON.parse(await kv.get('network-settings.json')||'{}');
const path=String(s.panelPath||'').replace(/^\/+|\/+$/g,'');
const base=path?'/'+path:'';
const dir=process.env.ALIREZA_VERIFY_NOVA_DIR||'/opt/nova-node-agent';
const {makeSession}=await import(pathToFileURL(dir+'/src/auth.mjs'));
const ua='alirezaserver-local-verification';
const session=await makeSession(kv,{userAgent:ua,maxAgeMs:60000});
const cookie=session.name+'='+session.value;
db.close();
const host=String(s.host||'localhost');
const expectedDNS=Number(process.env.ALIREZA_VERIFY_DNS_PORT||53);
function request(transport,port,route,authenticated=true,body){
  return new Promise((resolve,reject)=>{
    const client=transport==='https'?https:http;
    const payload=body?JSON.stringify(body):null;
    const options={hostname:'127.0.0.1',port,path:base+route,method:payload?'POST':'GET',
      headers:{host,'user-agent':ua,'accept-encoding':'identity',...(authenticated?{cookie}:{})},timeout:12000};
    if(payload)Object.assign(options.headers,{'content-type':'application/json','content-length':Buffer.byteLength(payload),origin:transport+'://'+host});
    // TLS verification is relaxed solely for loopback: Nova supports self-signed certs.
    if(transport==='https'){options.rejectUnauthorized=false;if(!isIP(host))options.servername=host;}
    const r=client.request(options,response=>{let body='';response.on('data',b=>{body+=b;if(body.length>4194304)r.destroy(Error('Response too large'));});response.on('end',()=>resolve({code:response.statusCode,body}));response.on('error',reject);});
    r.on('timeout',()=>r.destroy(Error('Timed out checking '+route)));r.on('error',reject);r.end(payload);
  });
}
function requireThat(ok,message){if(!ok)throw Error(message);}
async function verify(transport,port){
  const get=(route,auth)=>request(transport,port,route,auth);
  const gate=await get('/alireza/api/status',false);
  requireThat(gate.code===401&&JSON.parse(gate.body).error==='Sign in to the main panel first.','Integration owner gate was not reached');
  const page=await get('/');
  requireThat(page.code===200&&page.body.includes('data-alireza-addon')&&page.body.includes('<title>alirezaserver</title>'),'Panel branding script/title is missing');
  const brand=await get('/alireza/brand.js');
  requireThat(brand.code===200&&brand.body.includes('DNS · AdGuard Home')&&brand.body.includes('OpenVPN'),'New sidebar menu code is missing');
  const vpn=await get('/alireza/openvpn/');
  requireThat(vpn.code===200&&vpn.body.includes('OpenVPN')&&vpn.body.includes('alirezaserver'),'Owner cannot open OpenVPN management');
  const status=await get('/alireza/api/status');
  requireThat(status.code===200&&Array.isArray(JSON.parse(status.body).servers),'Owner cannot use OpenVPN management API');
  const dns=await get('/alireza/dns/control/status');
  requireThat(dns.code===200&&JSON.parse(dns.body).dns_port===expectedDNS,'Owner cannot reach AdGuard API on required DNS port');
  const dnsPage=await get('/alireza/dns/');
  requireThat(dnsPage.code===200&&dnsPage.body.includes('data-alireza-colors'),'Original AdGuard UI is not embedded');
  console.log(transport.toUpperCase()+': alirezaserver branding + owner access + OpenVPN UI/API + AdGuard UI/API: PASS');
}
try {
  await verify('http',Number(value('NOVA_PORT')||8088));
  const api=(route,body)=>request('http',Number(value('NOVA_PORT')||8088),'/alireza/dns/control/'+route,true,body);
  const rewriteSettings=await api('rewrite/settings');
  requireThat(rewriteSettings.code===200,'Cannot read AdGuard rewrite settings');
  if(JSON.parse(rewriteSettings.body).enabled){
    const record={domain:'alirezaserver-check-'+randomBytes(12).toString('hex')+'.invalid',answer:'192.0.2.53'};
    try{
      requireThat((await api('rewrite/add',record)).code===200,'Cannot create temporary DNS verification record');
      await checkDNS(record.domain,expectedDNS);
    }finally{
      requireThat((await api('rewrite/delete',record)).code===200,'Could not remove DNS test record '+record.domain);
    }
  }else console.log('DNS packet probe SKIPPED: you disabled AdGuard rewrites; that setting is preserved.');
  // Test the same front door the browser uses, not just the internal Node listener.
  if(process.env.ALIREZA_VERIFY_NO_FRONT!=='1'){
    const port=Number(value('NOVA_FRONT_PORT')||443);
    await verify('https',port);
    console.log('Panel: https://'+(isIP(host)===6?'['+host+']':host)+(port===443?'':':'+port)+base+'/');
  }
}catch(e){console.error('Integration verification FAILED: '+e.message);process.exitCode=1;}
ALIREZA_81984B06A9A160437D03A905

cat > "$APP/COPYING.vpn-ui" <<'ALIREZA_3972DC9744F6499F0F9B2DBF'
                    GNU GENERAL PUBLIC LICENSE
                       Version 3, 29 June 2007

 Copyright (C) 2007 Free Software Foundation, Inc. <https://fsf.org/>
 Everyone is permitted to copy and distribute verbatim copies
 of this license document, but changing it is not allowed.

                            Preamble

  The GNU General Public License is a free, copyleft license for
software and other kinds of works.

  The licenses for most software and other practical works are designed
to take away your freedom to share and change the works.  By contrast,
the GNU General Public License is intended to guarantee your freedom to
share and change all versions of a program--to make sure it remains free
software for all its users.  We, the Free Software Foundation, use the
GNU General Public License for most of our software; it applies also to
any other work released this way by its authors.  You can apply it to
your programs, too.

  When we speak of free software, we are referring to freedom, not
price.  Our General Public Licenses are designed to make sure that you
have the freedom to distribute copies of free software (and charge for
them if you wish), that you receive source code or can get it if you
want it, that you can change the software or use pieces of it in new
free programs, and that you know you can do these things.

  To protect your rights, we need to prevent others from denying you
these rights or asking you to surrender the rights.  Therefore, you have
certain responsibilities if you distribute copies of the software, or if
you modify it: responsibilities to respect the freedom of others.

  For example, if you distribute copies of such a program, whether
gratis or for a fee, you must pass on to the recipients the same
freedoms that you received.  You must make sure that they, too, receive
or can get the source code.  And you must show them these terms so they
know their rights.

  Developers that use the GNU GPL protect your rights with two steps:
(1) assert copyright on the software, and (2) offer you this License
giving you legal permission to copy, distribute and/or modify it.

  For the developers' and authors' protection, the GPL clearly explains
that there is no warranty for this free software.  For both users' and
authors' sake, the GPL requires that modified versions be marked as
changed, so that their problems will not be attributed erroneously to
authors of previous versions.

  Some devices are designed to deny users access to install or run
modified versions of the software inside them, although the manufacturer
can do so.  This is fundamentally incompatible with the aim of
protecting users' freedom to change the software.  The systematic
pattern of such abuse occurs in the area of products for individuals to
use, which is precisely where it is most unacceptable.  Therefore, we
have designed this version of the GPL to prohibit the practice for those
products.  If such problems arise substantially in other domains, we
stand ready to extend this provision to those domains in future versions
of the GPL, as needed to protect the freedom of users.

  Finally, every program is threatened constantly by software patents.
States should not allow patents to restrict development and use of
software on general-purpose computers, but in those that do, we wish to
avoid the special danger that patents applied to a free program could
make it effectively proprietary.  To prevent this, the GPL assures that
patents cannot be used to render the program non-free.

  The precise terms and conditions for copying, distribution and
modification follow.

                       TERMS AND CONDITIONS

  0. Definitions.

  "This License" refers to version 3 of the GNU General Public License.

  "Copyright" also means copyright-like laws that apply to other kinds of
works, such as semiconductor masks.

  "The Program" refers to any copyrightable work licensed under this
License.  Each licensee is addressed as "you".  "Licensees" and
"recipients" may be individuals or organizations.

  To "modify" a work means to copy from or adapt all or part of the work
in a fashion requiring copyright permission, other than the making of an
exact copy.  The resulting work is called a "modified version" of the
earlier work or a work "based on" the earlier work.

  A "covered work" means either the unmodified Program or a work based
on the Program.

  To "propagate" a work means to do anything with it that, without
permission, would make you directly or secondarily liable for
infringement under applicable copyright law, except executing it on a
computer or modifying a private copy.  Propagation includes copying,
distribution (with or without modification), making available to the
public, and in some countries other activities as well.

  To "convey" a work means any kind of propagation that enables other
parties to make or receive copies.  Mere interaction with a user through
a computer network, with no transfer of a copy, is not conveying.

  An interactive user interface displays "Appropriate Legal Notices"
to the extent that it includes a convenient and prominently visible
feature that (1) displays an appropriate copyright notice, and (2)
tells the user that there is no warranty for the work (except to the
extent that warranties are provided), that licensees may convey the
work under this License, and how to view a copy of this License.  If
the interface presents a list of user commands or options, such as a
menu, a prominent item in the list meets this criterion.

  1. Source Code.

  The "source code" for a work means the preferred form of the work
for making modifications to it.  "Object code" means any non-source
form of a work.

  A "Standard Interface" means an interface that either is an official
standard defined by a recognized standards body, or, in the case of
interfaces specified for a particular programming language, one that
is widely used among developers working in that language.

  The "System Libraries" of an executable work include anything, other
than the work as a whole, that (a) is included in the normal form of
packaging a Major Component, but which is not part of that Major
Component, and (b) serves only to enable use of the work with that
Major Component, or to implement a Standard Interface for which an
implementation is available to the public in source code form.  A
"Major Component", in this context, means a major essential component
(kernel, window system, and so on) of the specific operating system
(if any) on which the executable work runs, or a compiler used to
produce the work, or an object code interpreter used to run it.

  The "Corresponding Source" for a work in object code form means all
the source code needed to generate, install, and (for an executable
work) run the object code and to modify the work, including scripts to
control those activities.  However, it does not include the work's
System Libraries, or general-purpose tools or generally available free
programs which are used unmodified in performing those activities but
which are not part of the work.  For example, Corresponding Source
includes interface definition files associated with source files for
the work, and the source code for shared libraries and dynamically
linked subprograms that the work is specifically designed to require,
such as by intimate data communication or control flow between those
subprograms and other parts of the work.

  The Corresponding Source need not include anything that users
can regenerate automatically from other parts of the Corresponding
Source.

  The Corresponding Source for a work in source code form is that
same work.

  2. Basic Permissions.

  All rights granted under this License are granted for the term of
copyright on the Program, and are irrevocable provided the stated
conditions are met.  This License explicitly affirms your unlimited
permission to run the unmodified Program.  The output from running a
covered work is covered by this License only if the output, given its
content, constitutes a covered work.  This License acknowledges your
rights of fair use or other equivalent, as provided by copyright law.

  You may make, run and propagate covered works that you do not
convey, without conditions so long as your license otherwise remains
in force.  You may convey covered works to others for the sole purpose
of having them make modifications exclusively for you, or provide you
with facilities for running those works, provided that you comply with
the terms of this License in conveying all material for which you do
not control copyright.  Those thus making or running the covered works
for you must do so exclusively on your behalf, under your direction
and control, on terms that prohibit them from making any copies of
your copyrighted material outside their relationship with you.

  Conveying under any other circumstances is permitted solely under
the conditions stated below.  Sublicensing is not allowed; section 10
makes it unnecessary.

  3. Protecting Users' Legal Rights From Anti-Circumvention Law.

  No covered work shall be deemed part of an effective technological
measure under any applicable law fulfilling obligations under article
11 of the WIPO copyright treaty adopted on 20 December 1996, or
similar laws prohibiting or restricting circumvention of such
measures.

  When you convey a covered work, you waive any legal power to forbid
circumvention of technological measures to the extent such circumvention
is effected by exercising rights under this License with respect to
the covered work, and you disclaim any intention to limit operation or
modification of the work as a means of enforcing, against the work's
users, your or third parties' legal rights to forbid circumvention of
technological measures.

  4. Conveying Verbatim Copies.

  You may convey verbatim copies of the Program's source code as you
receive it, in any medium, provided that you conspicuously and
appropriately publish on each copy an appropriate copyright notice;
keep intact all notices stating that this License and any
non-permissive terms added in accord with section 7 apply to the code;
keep intact all notices of the absence of any warranty; and give all
recipients a copy of this License along with the Program.

  You may charge any price or no price for each copy that you convey,
and you may offer support or warranty protection for a fee.

  5. Conveying Modified Source Versions.

  You may convey a work based on the Program, or the modifications to
produce it from the Program, in the form of source code under the
terms of section 4, provided that you also meet all of these conditions:

    a) The work must carry prominent notices stating that you modified
    it, and giving a relevant date.

    b) The work must carry prominent notices stating that it is
    released under this License and any conditions added under section
    7.  This requirement modifies the requirement in section 4 to
    "keep intact all notices".

    c) You must license the entire work, as a whole, under this
    License to anyone who comes into possession of a copy.  This
    License will therefore apply, along with any applicable section 7
    additional terms, to the whole of the work, and all its parts,
    regardless of how they are packaged.  This License gives no
    permission to license the work in any other way, but it does not
    invalidate such permission if you have separately received it.

    d) If the work has interactive user interfaces, each must display
    Appropriate Legal Notices; however, if the Program has interactive
    interfaces that do not display Appropriate Legal Notices, your
    work need not make them do so.

  A compilation of a covered work with other separate and independent
works, which are not by their nature extensions of the covered work,
and which are not combined with it such as to form a larger program,
in or on a volume of a storage or distribution medium, is called an
"aggregate" if the compilation and its resulting copyright are not
used to limit the access or legal rights of the compilation's users
beyond what the individual works permit.  Inclusion of a covered work
in an aggregate does not cause this License to apply to the other
parts of the aggregate.

  6. Conveying Non-Source Forms.

  You may convey a covered work in object code form under the terms
of sections 4 and 5, provided that you also convey the
machine-readable Corresponding Source under the terms of this License,
in one of these ways:

    a) Convey the object code in, or embodied in, a physical product
    (including a physical distribution medium), accompanied by the
    Corresponding Source fixed on a durable physical medium
    customarily used for software interchange.

    b) Convey the object code in, or embodied in, a physical product
    (including a physical distribution medium), accompanied by a
    written offer, valid for at least three years and valid for as
    long as you offer spare parts or customer support for that product
    model, to give anyone who possesses the object code either (1) a
    copy of the Corresponding Source for all the software in the
    product that is covered by this License, on a durable physical
    medium customarily used for software interchange, for a price no
    more than your reasonable cost of physically performing this
    conveying of source, or (2) access to copy the
    Corresponding Source from a network server at no charge.

    c) Convey individual copies of the object code with a copy of the
    written offer to provide the Corresponding Source.  This
    alternative is allowed only occasionally and noncommercially, and
    only if you received the object code with such an offer, in accord
    with subsection 6b.

    d) Convey the object code by offering access from a designated
    place (gratis or for a charge), and offer equivalent access to the
    Corresponding Source in the same way through the same place at no
    further charge.  You need not require recipients to copy the
    Corresponding Source along with the object code.  If the place to
    copy the object code is a network server, the Corresponding Source
    may be on a different server (operated by you or a third party)
    that supports equivalent copying facilities, provided you maintain
    clear directions next to the object code saying where to find the
    Corresponding Source.  Regardless of what server hosts the
    Corresponding Source, you remain obligated to ensure that it is
    available for as long as needed to satisfy these requirements.

    e) Convey the object code using peer-to-peer transmission, provided
    you inform other peers where the object code and Corresponding
    Source of the work are being offered to the general public at no
    charge under subsection 6d.

  A separable portion of the object code, whose source code is excluded
from the Corresponding Source as a System Library, need not be
included in conveying the object code work.

  A "User Product" is either (1) a "consumer product", which means any
tangible personal property which is normally used for personal, family,
or household purposes, or (2) anything designed or sold for incorporation
into a dwelling.  In determining whether a product is a consumer product,
doubtful cases shall be resolved in favor of coverage.  For a particular
product received by a particular user, "normally used" refers to a
typical or common use of that class of product, regardless of the status
of the particular user or of the way in which the particular user
actually uses, or expects or is expected to use, the product.  A product
is a consumer product regardless of whether the product has substantial
commercial, industrial or non-consumer uses, unless such uses represent
the only significant mode of use of the product.

  "Installation Information" for a User Product means any methods,
procedures, authorization keys, or other information required to install
and execute modified versions of a covered work in that User Product from
a modified version of its Corresponding Source.  The information must
suffice to ensure that the continued functioning of the modified object
code is in no case prevented or interfered with solely because
modification has been made.

  If you convey an object code work under this section in, or with, or
specifically for use in, a User Product, and the conveying occurs as
part of a transaction in which the right of possession and use of the
User Product is transferred to the recipient in perpetuity or for a
fixed term (regardless of how the transaction is characterized), the
Corresponding Source conveyed under this section must be accompanied
by the Installation Information.  But this requirement does not apply
if neither you nor any third party retains the ability to install
modified object code on the User Product (for example, the work has
been installed in ROM).

  The requirement to provide Installation Information does not include a
requirement to continue to provide support service, warranty, or updates
for a work that has been modified or installed by the recipient, or for
the User Product in which it has been modified or installed.  Access to a
network may be denied when the modification itself materially and
adversely affects the operation of the network or violates the rules and
protocols for communication across the network.

  Corresponding Source conveyed, and Installation Information provided,
in accord with this section must be in a format that is publicly
documented (and with an implementation available to the public in
source code form), and must require no special password or key for
unpacking, reading or copying.

  7. Additional Terms.

  "Additional permissions" are terms that supplement the terms of this
License by making exceptions from one or more of its conditions.
Additional permissions that are applicable to the entire Program shall
be treated as though they were included in this License, to the extent
that they are valid under applicable law.  If additional permissions
apply only to part of the Program, that part may be used separately
under those permissions, but the entire Program remains governed by
this License without regard to the additional permissions.

  When you convey a copy of a covered work, you may at your option
remove any additional permissions from that copy, or from any part of
it.  (Additional permissions may be written to require their own
removal in certain cases when you modify the work.)  You may place
additional permissions on material, added by you to a covered work,
for which you have or can give appropriate copyright permission.

  Notwithstanding any other provision of this License, for material you
add to a covered work, you may (if authorized by the copyright holders of
that material) supplement the terms of this License with terms:

    a) Disclaiming warranty or limiting liability differently from the
    terms of sections 15 and 16 of this License; or

    b) Requiring preservation of specified reasonable legal notices or
    author attributions in that material or in the Appropriate Legal
    Notices displayed by works containing it; or

    c) Prohibiting misrepresentation of the origin of that material, or
    requiring that modified versions of such material be marked in
    reasonable ways as different from the original version; or

    d) Limiting the use for publicity purposes of names of licensors or
    authors of the material; or

    e) Declining to grant rights under trademark law for use of some
    trade names, trademarks, or service marks; or

    f) Requiring indemnification of licensors and authors of that
    material by anyone who conveys the material (or modified versions of
    it) with contractual assumptions of liability to the recipient, for
    any liability that these contractual assumptions directly impose on
    those licensors and authors.

  All other non-permissive additional terms are considered "further
restrictions" within the meaning of section 10.  If the Program as you
received it, or any part of it, contains a notice stating that it is
governed by this License along with a term that is a further
restriction, you may remove that term.  If a license document contains
a further restriction but permits relicensing or conveying under this
License, you may add to a covered work material governed by the terms
of that license document, provided that the further restriction does
not survive such relicensing or conveying.

  If you add terms to a covered work in accord with this section, you
must place, in the relevant source files, a statement of the
additional terms that apply to those files, or a notice indicating
where to find the applicable terms.

  Additional terms, permissive or non-permissive, may be stated in the
form of a separately written license, or stated as exceptions;
the above requirements apply either way.

  8. Termination.

  You may not propagate or modify a covered work except as expressly
provided under this License.  Any attempt otherwise to propagate or
modify it is void, and will automatically terminate your rights under
this License (including any patent licenses granted under the third
paragraph of section 11).

  However, if you cease all violation of this License, then your
license from a particular copyright holder is reinstated (a)
provisionally, unless and until the copyright holder explicitly and
finally terminates your license, and (b) permanently, if the copyright
holder fails to notify you of the violation by some reasonable means
prior to 60 days after the cessation.

  Moreover, your license from a particular copyright holder is
reinstated permanently if the copyright holder notifies you of the
violation by some reasonable means, this is the first time you have
received notice of violation of this License (for any work) from that
copyright holder, and you cure the violation prior to 30 days after
your receipt of the notice.

  Termination of your rights under this section does not terminate the
licenses of parties who have received copies or rights from you under
this License.  If your rights have been terminated and not permanently
reinstated, you do not qualify to receive new licenses for the same
material under section 10.

  9. Acceptance Not Required for Having Copies.

  You are not required to accept this License in order to receive or
run a copy of the Program.  Ancillary propagation of a covered work
occurring solely as a consequence of using peer-to-peer transmission
to receive a copy likewise does not require acceptance.  However,
nothing other than this License grants you permission to propagate or
modify any covered work.  These actions infringe copyright if you do
not accept this License.  Therefore, by modifying or propagating a
covered work, you indicate your acceptance of this License to do so.

  10. Automatic Licensing of Downstream Recipients.

  Each time you convey a covered work, the recipient automatically
receives a license from the original licensors, to run, modify and
propagate that work, subject to this License.  You are not responsible
for enforcing compliance by third parties with this License.

  An "entity transaction" is a transaction transferring control of an
organization, or substantially all assets of one, or subdividing an
organization, or merging organizations.  If propagation of a covered
work results from an entity transaction, each party to that
transaction who receives a copy of the work also receives whatever
licenses to the work the party's predecessor in interest had or could
give under the previous paragraph, plus a right to possession of the
Corresponding Source of the work from the predecessor in interest, if
the predecessor has it or can get it with reasonable efforts.

  You may not impose any further restrictions on the exercise of the
rights granted or affirmed under this License.  For example, you may
not impose a license fee, royalty, or other charge for exercise of
rights granted under this License, and you may not initiate litigation
(including a cross-claim or counterclaim in a lawsuit) alleging that
any patent claim is infringed by making, using, selling, offering for
sale, or importing the Program or any portion of it.

  11. Patents.

  A "contributor" is a copyright holder who authorizes use under this
License of the Program or a work on which the Program is based.  The
work thus licensed is called the contributor's "contributor version".

  A contributor's "essential patent claims" are all patent claims
owned or controlled by the contributor, whether already acquired or
hereafter acquired, that would be infringed by some manner, permitted
by this License, of making, using, or selling its contributor version,
but do not include claims that would be infringed only as a
consequence of further modification of the contributor version.  For
purposes of this definition, "control" includes the right to grant
patent sublicenses in a manner consistent with the requirements of
this License.

  Each contributor grants you a non-exclusive, worldwide, royalty-free
patent license under the contributor's essential patent claims, to
make, use, sell, offer for sale, import and otherwise run, modify and
propagate the contents of its contributor version.

  In the following three paragraphs, a "patent license" is any express
agreement or commitment, however denominated, not to enforce a patent
(such as an express permission to practice a patent or covenant not to
sue for patent infringement).  To "grant" such a patent license to a
party means to make such an agreement or commitment not to enforce a
patent against the party.

  If you convey a covered work, knowingly relying on a patent license,
and the Corresponding Source of the work is not available for anyone
to copy, free of charge and under the terms of this License, through a
publicly available network server or other readily accessible means,
then you must either (1) cause the Corresponding Source to be so
available, or (2) arrange to deprive yourself of the benefit of the
patent license for this particular work, or (3) arrange, in a manner
consistent with the requirements of this License, to extend the patent
license to downstream recipients.  "Knowingly relying" means you have
actual knowledge that, but for the patent license, your conveying the
covered work in a country, or your recipient's use of the covered work
in a country, would infringe one or more identifiable patents in that
country that you have reason to believe are valid.

  If, pursuant to or in connection with a single transaction or
arrangement, you convey, or propagate by procuring conveyance of, a
covered work, and grant a patent license to some of the parties
receiving the covered work authorizing them to use, propagate, modify
or convey a specific copy of the covered work, then the patent license
you grant is automatically extended to all recipients of the covered
work and works based on it.

  A patent license is "discriminatory" if it does not include within
the scope of its coverage, prohibits the exercise of, or is
conditioned on the non-exercise of one or more of the rights that are
specifically granted under this License.  You may not convey a covered
work if you are a party to an arrangement with a third party that is
in the business of distributing software, under which you make payment
to the third party based on the extent of your activity of conveying
the work, and under which the third party grants, to any of the
parties who would receive the covered work from you, a discriminatory
patent license (a) in connection with copies of the covered work
conveyed by you (or copies made from those copies), or (b) primarily
for and in connection with specific products or compilations that
contain the covered work, unless you entered into that arrangement,
or that patent license was granted, prior to 28 March 2007.

  Nothing in this License shall be construed as excluding or limiting
any implied license or other defenses to infringement that may
otherwise be available to you under applicable patent law.

  12. No Surrender of Others' Freedom.

  If conditions are imposed on you (whether by court order, agreement or
otherwise) that contradict the conditions of this License, they do not
excuse you from the conditions of this License.  If you cannot convey a
covered work so as to satisfy simultaneously your obligations under this
License and any other pertinent obligations, then as a consequence you may
not convey it at all.  For example, if you agree to terms that obligate you
to collect a royalty for further conveying from those to whom you convey
the Program, the only way you could satisfy both those terms and this
License would be to refrain entirely from conveying the Program.

  13. Use with the GNU Affero General Public License.

  Notwithstanding any other provision of this License, you have
permission to link or combine any covered work with a work licensed
under version 3 of the GNU Affero General Public License into a single
combined work, and to convey the resulting work.  The terms of this
License will continue to apply to the part which is the covered work,
but the special requirements of the GNU Affero General Public License,
section 13, concerning interaction through a network will apply to the
combination as such.

  14. Revised Versions of this License.

  The Free Software Foundation may publish revised and/or new versions of
the GNU General Public License from time to time.  Such new versions will
be similar in spirit to the present version, but may differ in detail to
address new problems or concerns.

  Each version is given a distinguishing version number.  If the
Program specifies that a certain numbered version of the GNU General
Public License "or any later version" applies to it, you have the
option of following the terms and conditions either of that numbered
version or of any later version published by the Free Software
Foundation.  If the Program does not specify a version number of the
GNU General Public License, you may choose any version ever published
by the Free Software Foundation.

  If the Program specifies that a proxy can decide which future
versions of the GNU General Public License can be used, that proxy's
public statement of acceptance of a version permanently authorizes you
to choose that version for the Program.

  Later license versions may give you additional or different
permissions.  However, no additional obligations are imposed on any
author or copyright holder as a result of your choosing to follow a
later version.

  15. Disclaimer of Warranty.

  THERE IS NO WARRANTY FOR THE PROGRAM, TO THE EXTENT PERMITTED BY
APPLICABLE LAW.  EXCEPT WHEN OTHERWISE STATED IN WRITING THE COPYRIGHT
HOLDERS AND/OR OTHER PARTIES PROVIDE THE PROGRAM "AS IS" WITHOUT WARRANTY
OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO,
THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
PURPOSE.  THE ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE PROGRAM
IS WITH YOU.  SHOULD THE PROGRAM PROVE DEFECTIVE, YOU ASSUME THE COST OF
ALL NECESSARY SERVICING, REPAIR OR CORRECTION.

  16. Limitation of Liability.

  IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MODIFIES AND/OR CONVEYS
THE PROGRAM AS PERMITTED ABOVE, BE LIABLE TO YOU FOR DAMAGES, INCLUDING ANY
GENERAL, SPECIAL, INCIDENTAL OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE
USE OR INABILITY TO USE THE PROGRAM (INCLUDING BUT NOT LIMITED TO LOSS OF
DATA OR DATA BEING RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD
PARTIES OR A FAILURE OF THE PROGRAM TO OPERATE WITH ANY OTHER PROGRAMS),
EVEN IF SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.

  17. Interpretation of Sections 15 and 16.

  If the disclaimer of warranty and limitation of liability provided
above cannot be given local legal effect according to their terms,
reviewing courts shall apply local law that most closely approximates
an absolute waiver of all civil liability in connection with the
Program, unless a warranty or assumption of liability accompanies a
copy of the Program in return for a fee.

                     END OF TERMS AND CONDITIONS

            How to Apply These Terms to Your New Programs

  If you develop a new program, and you want it to be of the greatest
possible use to the public, the best way to achieve this is to make it
free software which everyone can redistribute and change under these terms.

  To do so, attach the following notices to the program.  It is safest
to attach them to the start of each source file to most effectively
state the exclusion of warranty; and each file should have at least
the "copyright" line and a pointer to where the full notice is found.

    <one line to give the program's name and a brief idea of what it does.>
    Copyright (C) <year>  <name of author>

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.

Also add information on how to contact you by electronic and paper mail.

  If the program does terminal interaction, make it output a short
notice like this when it starts in an interactive mode:

    <program>  Copyright (C) <year>  <name of author>
    This program comes with ABSOLUTELY NO WARRANTY; for details type `show w'.
    This is free software, and you are welcome to redistribute it
    under certain conditions; type `show c' for details.

The hypothetical commands `show w' and `show c' should show the appropriate
parts of the General Public License.  Of course, your program's commands
might be different; for a GUI interface, you would use an "about box".

  You should also get your employer (if you work as a programmer) or school,
if any, to sign a "copyright disclaimer" for the program, if necessary.
For more information on this, and how to apply and follow the GNU GPL, see
<https://www.gnu.org/licenses/>.

  The GNU General Public License does not permit incorporating your program
into proprietary programs.  If your program is a subroutine library, you
may consider it more useful to permit linking proprietary applications with
the library.  If this is what you want to do, use the GNU Lesser General
Public License instead of this License.  But first, please read
<https://www.gnu.org/licenses/why-not-lgpl.html>.
ALIREZA_3972DC9744F6499F0F9B2DBF

chmod 700 "$APP"/*.py "$APP"/*.sh
mkdir -p "$APP/adguard" "$ROOT/adguard" "$ROOT/openvpn"
if [[ ! -x "$APP/adguard/AdGuardHome" ]]; then install -m 755 "$WORK/AdGuardHome/AdGuardHome" "$APP/adguard/AdGuardHome"; fi
export ALIREZA_ROOT="$ROOT"
node --input-type=module -e 'const m=await import("file:///opt/alirezaserver/backend.mjs");m.database();'
python3 - <<'PY'
import ipaddress,json,os
root='/var/lib/alirezaserver'
address=str(ipaddress.IPv4Address(os.environ['DNS_ADDRESS']))
allowed=[]
if os.environ.get('DNS_ALLOWED_CIDRS','').strip():allowed=['127.0.0.0/8','10.0.0.0/8','172.16.0.0/12','192.168.0.0/16','::1','fc00::/7']
for item in os.environ.get('DNS_ALLOWED_CIDRS','').split(','):
    if item.strip():allowed.append(str(ipaddress.ip_network(item.strip(),strict=False)))
config={
 'http':{'address':'127.0.0.1:18085'},'users':[],
 'dns':{'bind_hosts':[address,'127.0.0.1'],'port':53,'allowed_clients':allowed,'ratelimit':20,
        'upstream_dns':['1.1.1.1','9.9.9.9'],
        'bootstrap_dns':['1.1.1.1','9.9.9.9'],'cache_size':4194304},
 'filtering':{'protection_enabled':True,'filtering_enabled':True},
 'filters':[{'enabled':True,'url':'https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt','name':'AdGuard DNS filter','id':1}],
 'schema_version':29
}
if not os.path.exists(root+'/adguard/AdGuardHome.yaml'):
    # JSON is valid YAML; AdGuard reads it and rewrites its native YAML on save.
    with open(root+'/adguard/AdGuardHome.yaml','w') as f:json.dump(config,f,indent=2)
if not os.path.exists(root+'/install.json'):
    with open(root+'/install.json','w') as f:json.dump({'dns_address':address,'dns_allowed_clients':allowed,'version':'0.3.0'},f)
if not os.path.exists(root+'/firewall.json'):
    with open(root+'/firewall.json','w') as f:json.dump([],f)
PY
"$APP/adguard/AdGuardHome" --check-config -c "$ROOT/adguard/AdGuardHome.yaml" -w "$ROOT/adguard"
cat > /etc/systemd/system/AdGuardHome.service <<'UNIT'
[Unit]
Description=alirezaserver - AdGuard Home
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
User=root
ExecStart=/opt/alirezaserver/adguard/AdGuardHome -c /var/lib/alirezaserver/adguard/AdGuardHome.yaml -w /var/lib/alirezaserver/adguard
Restart=on-failure
RestartSec=3
Environment=GOMEMLIMIT=160MiB
UMask=0077
NoNewPrivileges=true
ProtectHome=true
ProtectSystem=strict
ReadWritePaths=/var/lib/alirezaserver/adguard /opt/alirezaserver/adguard
PrivateTmp=true
[Install]
WantedBy=multi-user.target
UNIT
cat > /etc/systemd/system/alireza-firewall.service <<'UNIT'
[Unit]
Description=alirezaserver scoped DNS and OpenVPN firewall rules
After=network-online.target ufw.service
Wants=network-online.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/opt/alirezaserver/firewall.py
ExecStop=/opt/alirezaserver/firewall.py --remove
[Install]
WantedBy=multi-user.target
UNIT
cat > /etc/systemd/system/alireza-openvpn@.service <<'UNIT'
[Unit]
Description=alirezaserver OpenVPN %i
After=network-online.target alireza-firewall.service
Requires=alireza-firewall.service
[Service]
Type=simple
ExecStartPre=/opt/alirezaserver/reset-sessions.py %i
ExecStart=/usr/sbin/openvpn --config /var/lib/alirezaserver/openvpn/%i/server.conf
Restart=on-failure
RestartSec=3
UMask=0077
User=root
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=/var/lib/alirezaserver
ProtectHome=true
PrivateTmp=true
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
[Install]
WantedBy=multi-user.target
UNIT
STAGE=service-activation
log '[4/5] Activating AdGuard and loading the integration into Nova.'
DROPIN=/etc/systemd/system/nova-agent.service.d/zz-alirezaserver.conf
if [[ -f "$DROPIN" ]]; then cp "$DROPIN" "$WORK/previous-dropin";
elif [[ -f /etc/systemd/system/nova-agent.service.d/alirezaserver.conf ]]; then cp /etc/systemd/system/nova-agent.service.d/alirezaserver.conf "$WORK/previous-dropin"; fi
cat > "$DROPIN" <<UNIT
[Service]
ExecStart=
ExecStart=$NODE_BIN --max-old-space-size=192 --import=/opt/alirezaserver/preload.mjs /opt/nova-node-agent/bin/nova-agent.mjs
UNIT
rm -f /etc/systemd/system/nova-agent.service.d/alirezaserver.conf
HOOK_CHANGED=1
systemctl daemon-reload
systemctl show nova-agent.service -p ExecStart --value | grep -q -- '--import=/opt/alirezaserver/preload.mjs' || die 'Another service override prevented the integration from loading.'
systemctl enable AdGuardHome.service alireza-firewall.service
node --input-type=module -e 'const m=await import("file:///opt/alirezaserver/backend.mjs");m.refreshConfigs();'
systemctl restart AdGuardHome.service alireza-firewall.service
# Restarting the firewall unit can stop dependent OpenVPN instances; restore only
# instances configured as enabled, with repaired configs and unchanged accounts.
node --input-type=module - <<'JS'
import{servers,run,ready}from'/opt/alirezaserver/backend.mjs';
for(const s of servers())if(s.enabled){await run('systemctl',['restart','alireza-openvpn@'+s.id+'.service']);await ready(s);}
JS
systemctl restart nova-agent.service
STAGE=dns-configuration-repair
for attempt in {1..20}; do
  if curl -fsS --max-time 2 http://127.0.0.1:18085/control/status >/dev/null; then break; fi
  sleep 1
done
python3 "$APP/dns-repair.py"
STAGE=integration-verification
log '[5/5] Verifying the actual panel, branding, OpenVPN and AdGuard through Nova.'
VERIFIED=0
for attempt in {1..12}; do
  if node "$APP/verify-install.mjs" > "$WORK/verify.log" 2>&1; then VERIFIED=1; break; fi
  printf 'Waiting for panel readiness (%s/12)...\n' "$attempt"
  sleep 3
done
cat "$WORK/verify.log"
[[ $VERIFIED == 1 ]] || die 'The integrated panel did not pass verification. Existing add-on data is retained; rerun this file to repair.'
bash "$APP/check.sh"
printf '{"version":"0.3.0","nova":"1.85.4","adguard":"%s"}\n' "$AG_VERSION" > "$ROOT/installed.json"
rm -f "$ROOT/failed-stage"
HOOK_CHANGED=0
log 'ALIREZASERVER READY — panel branding, OpenVPN management and AdGuard integration verified.'
printf 'نصب پنل alirezaserver و دو بخش AdGuard و OpenVPN تکمیل و بررسی شد.\n'
printf '%s\n' \
 'DNS: AdGuard Home, TCP/UDP 53; owner-only web access through the main panel.' \
 'OpenVPN: create servers/accounts using the new OpenVPN menu.' \
 'Existing Nova protocols, node enrollment scripts and upstream files are unchanged.' \
 'DNS accepts public clients on your server IPv4:53. Restrict access in AdGuard Access settings if desired.' \
 'A provider firewall/security group must separately allow DNS TCP/UDP 53 and your selected OpenVPN port.' \
 'Rollback add-ons: sudo bash install.sh --rollback' \
 'Diagnostics: sudo bash install.sh --check' \
 'No live multi-node, client-connection or 1 GiB load certification has been performed.'

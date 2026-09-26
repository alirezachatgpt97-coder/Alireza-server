#!/usr/bin/env bash
# alirezaserver bootstrap — downloads the content-verified 0.3.0 installer.
# Repository: https://github.com/alirezachatgpt97-coder/alirezaserver
# Videos: https://www.youtube.com/@Alirezacoder12
# This launcher does not replace or modify the actual installer.
set -Eeuo pipefail
umask 077
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
VERSION=0.3.0
REF=main
SHA256=0c9e01b8297b1f6468b088b2db1da699a024efc7460d3a660e1e7419d36a7ecd
URL="https://raw.githubusercontent.com/alirezachatgpt97-coder/alirezaserver/$REF/install.sh"
CACHE=/var/cache/alirezaserver
PARTIAL=''
say(){ printf '\n[alirezaserver] %s\n' "$*"; }
die(){ printf '\n[alirezaserver] ERROR: %s\n' "$*" >&2; exit 1; }
usage(){
  cat <<'HELP'
alirezaserver — verified installer launcher

Run as root on Ubuntu 24.04 or Debian 12/13 (amd64/arm64):
  bash setup.sh                  Install, or resume/repair an existing installation
  bash setup.sh --repair         Same repair flow; keeps existing add-on data
  bash setup.sh --check          Check the currently installed integration
  bash setup.sh --backup         Back up the currently installed add-on data
  bash setup.sh --rollback       Disable add-ons and restore the original Nova launch
  bash setup.sh --download-only  Download and verify, without running the installer

The pinned installer is cached under /var/cache/alirezaserver.
NOVA_* and DNS_ALLOWED_CIDRS environment variables reach the original installer.
Video tutorials: https://www.youtube.com/@Alirezacoder12
HELP
}
[[ $# -le 1 ]] || die 'Use one option at a time. See --help.'
case "${1:-}" in
  --help|-h) usage; exit 0 ;;
  ''|--repair|--check|--backup|--rollback|--download-only) ;;
  *) die 'Unknown option. Use --help.' ;;
esac
[[ $EUID == 0 ]] || die 'Open a root shell (sudo -i), then run this script.'
[[ -d /run/systemd/system ]] || die 'A Linux VPS running systemd is required.'
case "${1:-}" in
  --check|--rollback)
    action="${1#--}"
    [[ -f "/opt/alirezaserver/$action.sh" ]] || die 'No installed integration was found.'
    exec bash "/opt/alirezaserver/$action.sh" ;;
  --backup)
    [[ -f /opt/alirezaserver/backup.py ]] || die 'No installed integration was found.'
    exec python3 /opt/alirezaserver/backup.py ;;
esac
source /etc/os-release
case "$ID:$VERSION_ID" in ubuntu:24.04|debian:12|debian:13) ;; *) die 'Supported systems: Ubuntu 24.04 or Debian 12/13.' ;; esac
case "$(uname -m)" in x86_64|aarch64|arm64) ;; *) die 'Supported CPUs: amd64 or arm64.' ;; esac
command -v sha256sum >/dev/null || die 'sha256sum is required (coreutils package).'
command -v flock >/dev/null || die 'flock is required (util-linux package).'
install -d -m 700 "$CACHE"
exec 8>"$CACHE/bootstrap.lock"
flock -n 8 || die 'Another alirezaserver launcher is running.'
trap '[[ -z "$PARTIAL" ]] || rm -f -- "$PARTIAL"' EXIT
INSTALLER="$CACHE/install-$VERSION.sh"
verified(){ [[ -f "$1" ]] && printf '%s  %s\n' "$SHA256" "$1" | sha256sum --check --status; }
if ! verified "$INSTALLER"; then
  if ! command -v curl >/dev/null && ! command -v wget >/dev/null; then
    say 'Installing download prerequisites.'
    apt-get -o DPkg::Lock::Timeout=300 update
    apt-get -o DPkg::Lock::Timeout=300 install -y ca-certificates curl
  fi
  PARTIAL=$(mktemp "$CACHE/.download.XXXXXXXX")
  say "Downloading the published alirezaserver $VERSION installer."
  if command -v curl >/dev/null; then
    curl --fail --location --proto '=https' --tlsv1.2 --connect-timeout 20 --max-time 600 --retry 3 --retry-delay 3 --output "$PARTIAL" "$URL"
  else
    wget --https-only --timeout=30 --tries=3 --output-document="$PARTIAL" "$URL"
  fi
  verified "$PARTIAL" || die 'Checksum mismatch. Nothing was executed. Retry or check the published release.'
  bash -n "$PARTIAL" || die 'Downloaded installer failed its Bash syntax check.'
  chmod 600 "$PARTIAL"
  mv -f -- "$PARTIAL" "$INSTALLER"
  PARTIAL=''
fi
say "Verified installer: $INSTALLER"
if [[ "${1:-}" == --download-only ]]; then
  say 'Download verified; installation was not started.'
  exit 0
fi
say 'Starting installation. Wait for ALIREZASERVER READY; the Nova-only message is not completion.'
bash "$INSTALLER" "$@"

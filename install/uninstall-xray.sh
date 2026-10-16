#!/usr/bin/env bash
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || { echo "Jalankan sebagai root." >&2; exit 1; }
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP="/root/backup-sansxml/xray-uninstall-$STAMP"
mkdir -p "$BACKUP"
chmod 700 "$BACKUP"
[[ ! -d /etc/xray ]] || cp -a /etc/xray "$BACKUP/"
[[ ! -d /var/lib/sansxml-xray ]] || cp -a /var/lib/sansxml-xray "$BACKUP/"
echo "Backup konfigurasi dan data: $BACKUP"
read -r -p "Copot service Xray (SSH/SSLH lama tidak disentuh)? Ketik COPOT XRAY: " confirm
[[ "$confirm" == "COPOT XRAY" ]] || { echo "Dibatalkan."; exit 0; }
for unit in xray sansxml-xray-cleanup.timer sansxml-xray-cleanup.service sansxml-cert-renew.timer sansxml-cert-renew.service; do
  systemctl disable --now "$unit" 2>/dev/null || true
done
rm -f /etc/systemd/system/xray.service \
  /etc/systemd/system/sansxml-xray-cleanup.service \
  /etc/systemd/system/sansxml-xray-cleanup.timer \
  /etc/systemd/system/sansxml-cert-renew.service \
  /etc/systemd/system/sansxml-cert-renew.timer \
  /usr/local/bin/xray /usr/local/bin/xray-account /usr/local/bin/menu-xray \
  /usr/local/lib/sansxml-xray/build-xray-config.py /usr/local/sbin/sansxml-cert-renew
systemctl daemon-reload
systemctl reset-failed 2>/dev/null || true
echo "Xray dicopot. Sertifikat TLS, /root/.domain, SSH port 22, SSLH, dan data akun di /var/lib/sansxml-xray tidak dihapus."

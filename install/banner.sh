#!/usr/bin/env bash
set -Eeuo pipefail

# ==========================================
# SANSXML VPN STORE - SSH BANNER
# ==========================================

BANNER_FILE="/etc/issue.net"
DROPBEAR_CONFIG="/etc/default/dropbear"

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Jalankan script sebagai root."
    exit 1
fi

echo "[SANSXML] Memasang banner SSH..."

# Backup konfigurasi sebelum mengubahnya
if [[ -f "$DROPBEAR_CONFIG" ]]; then
    cp -a "$DROPBEAR_CONFIG" \
        "${DROPBEAR_CONFIG}.bak-$(date +%Y%m%d-%H%M%S)"
fi

# Buat banner
cat > "$BANNER_FILE" <<'BANNER'
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
» SANSXML VPN STORE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
» PREMIUM VPN SERVER
» HIGH SPEED • STABLE CONNECTION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
» NO DDOS
» NO HACKING
» NO TORRENT
» NO SPAMMING
» NO MULTI LOGIN
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
» BOT AUTO ORDER
https://t.me/VpnnnBot_bot
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
BANNER

chmod 644 "$BANNER_FILE"

# Pastikan Dropbear memakai opsi banner
if [[ -f "$DROPBEAR_CONFIG" ]]; then
    if grep -q '^DROPBEAR_EXTRA_ARGS=' "$DROPBEAR_CONFIG"; then
        sed -i \
            's|^DROPBEAR_EXTRA_ARGS=.*|DROPBEAR_EXTRA_ARGS="-b /etc/issue.net"|' \
            "$DROPBEAR_CONFIG"
    else
        printf '\nDROPBEAR_EXTRA_ARGS="-b /etc/issue.net"\n' \
            >> "$DROPBEAR_CONFIG"
    fi

    # Restart hanya jika Dropbear terpasang dan aktif
    if systemctl is-active --quiet dropbear; then
        systemctl restart dropbear
        echo "[OK] Dropbear berhasil dimulai ulang."
    else
        echo "[INFO] Dropbear tidak aktif; layanan tidak diubah."
    fi
else
    echo "[INFO] Konfigurasi Dropbear tidak ditemukan."
    echo "[INFO] File banner sudah dibuat di $BANNER_FILE."
fi

echo "[OK] Banner SANSXML tersimpan di $BANNER_FILE."

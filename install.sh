#!/bin/bash
set -e

INSTALLER="${1:-/root/install.sh}"

if [ ! -f "$INSTALLER" ]; then
    echo "❌ File installer tidak ditemukan: $INSTALLER"
    echo "Pakai: bash update_bot_ui.sh /path/ke/install.sh"
    exit 1
fi

echo "▸ Mengambil bot.py terbaru dari installer..."

awk '
/^cat > \/root\/bot\.py << '\''BOTPYEOF'\''$/ {found=1; next}
/^BOTPYEOF$/ && found {found=0; exit}
found {print}
' "$INSTALLER" > /root/bot.py

if [ ! -s /root/bot.py ]; then
    echo "❌ Gagal mengambil bot.py dari installer."
    exit 1
fi

chmod +x /root/bot.py

echo "▸ Cek syntax bot.py..."
python3 -m py_compile /root/bot.py

echo "▸ Restart bot..."
systemctl daemon-reload
systemctl enable vpnbot >/dev/null 2>&1 || true
systemctl restart vpnbot

sleep 3

if systemctl is-active --quiet vpnbot; then
    echo "✅ BOT BERHASIL DIPERBARUI"
    echo "Dashboard sekarang:"
    echo "  STATUS SERVER"
    echo "  CHANNEL | ADMIN"
    echo "  REFRESH (merah)"
    echo
    echo "💻 VPS di Pengaturan sudah dihapus."
else
    echo "❌ Bot gagal aktif."
    systemctl --no-pager --full status vpnbot || true
    exit 1
fi

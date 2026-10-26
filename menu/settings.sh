#!/bin/bash
clear

BIRU='\033[0;34m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
RESET='\033[0m'

SETTINGS_URL="https://github.com/Syahrul7y/SANSXML-BOT-VPN/raw/refs/heads/main/menu/settings.sh"
MAIN_MENU_URL="https://github.com/Syahrul7y/SANSXML-BOT-VPN/raw/refs/heads/main/menu/menu.sh"
BOT_URL="https://github.com/Syahrul7y/SANSXML-BOT-VPN/raw/refs/heads/main/menu/bot.py"
BANNER_FILE="/etc/issue.net"
DROPBEAR_CONFIG="/etc/default/dropbear"

# Nama service umum yang akan diperiksa; yang tidak terpasang dilewati.
SERVICE_CANDIDATES=(ssh sshd dropbear nginx stunnel4 sslh ssh-ws ws-ssh xray sing-box openvpn udp-custom badvpn-udpgw bot-telegram)

kembali_settings() {
    echo ""
    read -r -p "Tekan Enter untuk kembali ke Settings..."
    if command -v curl >/dev/null 2>&1; then
        bash <(curl -fLsS "$SETTINGS_URL")
    else
        echo "curl tidak tersedia; jalankan kembali menu Settings dari menu utama."
    fi
    exit
}

require_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Jalankan menu sebagai root.${RESET}"
        kembali_settings
    fi
}

service_exists() {
    systemctl cat "$1.service" >/dev/null 2>&1
}

show_service_status() {
    local unit state enabled found=0
    echo ""
    echo -e "${CYAN}========== STATUS SERVICE VPS ==========${RESET}"
    printf '%-22s %-14s %s\n' "SERVICE" "STATUS" "AUTOSTART"
    echo "------------------------------------------------------"
    for unit in "${SERVICE_CANDIDATES[@]}"; do
        if service_exists "$unit"; then
            found=1
            state=$(systemctl is-active "$unit" 2>/dev/null || true)
            enabled=$(systemctl is-enabled "$unit" 2>/dev/null || true)
            [ -n "$state" ] || state="unknown"
            [ -n "$enabled" ] || enabled="unknown"
            if [ "$state" = active ]; then
                printf "${GREEN}%-22s %-14s %s${RESET}\n" "$unit" "$state" "$enabled"
            else
                printf "${RED}%-22s %-14s %s${RESET}\n" "$unit" "$state" "$enabled"
            fi
        fi
    done
    if [ "$found" -eq 0 ]; then
        echo "Tidak ditemukan service dari daftar umum."
        systemctl list-units --type=service --all --no-pager
    fi
    echo "------------------------------------------------------"
}

restart_service_menu() {
    local unit choice i=1
    local services=()
    for unit in "${SERVICE_CANDIDATES[@]}"; do
        service_exists "$unit" && services+=("$unit")
    done
    echo ""
    echo -e "${CYAN}========== RESTART SERVICE ==========${RESET}"
    if [ "${#services[@]}" -eq 0 ]; then
        echo "Tidak ada service yang dikenali."
        return
    fi
    for unit in "${services[@]}"; do
        printf "${YELLOW}[%d]${RESET} %s (%s)\n" "$i" "$unit" "$(systemctl is-active "$unit" 2>/dev/null || echo unknown)"
        i=$((i + 1))
    done
    echo -e "${YELLOW}[a]${RESET} Restart semua service yang sedang aktif"
    echo -e "${YELLOW}[x]${RESET} Batal"
    read -r -p "Pilih service: " choice
    case "$choice" in
        x|X) return ;;
        a|A)
            for unit in "${services[@]}"; do
                if systemctl is-active --quiet "$unit"; then
                    if systemctl restart "$unit"; then echo -e "${GREEN}$unit: berhasil direstart${RESET}"; else echo -e "${RED}$unit: gagal direstart${RESET}"; fi
                fi
            done
            ;;
        *)
            if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#services[@]}" ]; then
                unit="${services[$((choice - 1))]}"
                if systemctl restart "$unit"; then
                    echo -e "${GREEN}$unit berhasil direstart.${RESET}"
                else
                    echo -e "${RED}Gagal merestart $unit. Log terakhir:${RESET}"
                    journalctl -u "$unit" -n 15 --no-pager
                fi
            else
                echo -e "${RED}Pilihan tidak valid.${RESET}"
            fi
            ;;
    esac
}

speed_test() {
    echo ""
    echo -e "${CYAN}========== TES SPEED KONEKSI VPS ==========${RESET}"
    echo "1) Tes download sederhana"
    echo "x) Kembali"
    read -r -p "Pilih tes: " test_choice
    case "$test_choice" in
        1)
            if ! command -v curl >/dev/null 2>&1; then
                echo -e "${RED}curl tidak tersedia. Pasang curl lalu coba lagi.${RESET}"
                return
            fi
            local tmp_file start end elapsed bytes mbps
            tmp_file=$(mktemp) || return
            echo "Mengunduh data tes 25 MB dari Cloudflare..."
            start=$(date +%s)
            if curl -fLsS --max-time 90 -o "$tmp_file" 'https://speed.cloudflare.com/__down?bytes=25000000'; then
                end=$(date +%s)
                elapsed=$((end - start)); [ "$elapsed" -gt 0 ] || elapsed=1
                bytes=$(wc -c < "$tmp_file")
                mbps=$(awk -v b="$bytes" -v t="$elapsed" 'BEGIN {printf "%.2f", (b*8)/(t*1000000)}')
                echo -e "${GREEN}Perkiraan kecepatan download: ${mbps} Mbps${RESET}"
                echo "Ini tes sederhana; hasil dipengaruhi rute server, dan bukan tes upload/ping penuh."
            else
                echo -e "${RED}Tes download gagal; periksa koneksi atau DNS VPS.${RESET}"
            fi
            rm -f "$tmp_file"
            ;;
        x|X) return ;;
        *) echo -e "${RED}Pilihan tidak valid.${RESET}" ;;
    esac
}

speed_profile() {
    require_root
    echo ""
    echo -e "${CYAN}========== PROFIL KONEKSI VPS ==========${RESET}"
    echo "Pilih profil TCP. Ini mengubah parameter kernel; tidak bisa menjamin internet lebih cepat."
    echo "[1] Normal    - kembalikan parameter umum Linux"
    echo "[2] Sedang    - aktifkan BBR jika didukung, buffer moderat"
    echo "[3] Highspeed - aktifkan BBR dan buffer lebih besar"
    echo "[x] Batal"
    read -r -p "Pilih profil [1-3/x]: " profile
    case "$profile" in
        x|X) return ;;
        1)
            cat > /etc/sysctl.d/99-sansxml-network.conf <<'EOF'
# SANSXML TCP profile: Normal
net.core.default_qdisc = fq_codel
net.ipv4.tcp_congestion_control = cubic
EOF
            ;;
        2)
            cat > /etc/sysctl.d/99-sansxml-network.conf <<'EOF'
# SANSXML TCP profile: Sedang
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
EOF
            ;;
        3)
            cat > /etc/sysctl.d/99-sansxml-network.conf <<'EOF'
# SANSXML TCP profile: Highspeed
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.ipv4.tcp_rmem = 4096 131072 33554432
net.ipv4.tcp_wmem = 4096 131072 33554432
EOF
            ;;
        *) echo -e "${RED}Pilihan tidak valid.${RESET}"; return ;;
    esac
    if sysctl --system >/tmp/sansxml-sysctl.log 2>&1; then
        echo -e "${GREEN}Profil tersimpan dan parameter yang didukung sudah diterapkan.${RESET}"
        echo "Pengaturan aktif: qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null), congestion=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)"
        if [ "$profile" != 1 ] && ! sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null | grep -qw bbr; then
            echo -e "${YELLOW}Kernel VPS tidak mengaktifkan BBR. Profil diterapkan sebagian; cek dukungan kernel.${RESET}"
        fi
    else
        echo -e "${RED}Ada parameter yang gagal diterapkan. Detail:${RESET}"
        cat /tmp/sansxml-sysctl.log
    fi
}

echo -e "${BIRU}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BIRU}             ${YELLOW}SANSXML VPN STORE • SETTINGS${RESET}"
echo -e "${BIRU}╠══════════════════════════════════════════════════════════╣${RESET}"
echo -e "${BIRU}                         ${YELLOW}SETTINGS${RESET}"
echo -e "${BIRU}╠══════════════════════════════════════════════════════════╣${RESET}"

if [ -f /etc/bot-telegram.conf ]; then
    ADMIN_NOW=$(grep '^ADMIN=' /etc/bot-telegram.conf | cut -d= -f2-)
    BOT_STAT=$(systemctl is-active bot-telegram 2>/dev/null || true)
    echo -e "${BIRU}  ${GREEN}Admin Bot  :${RESET} ${CYAN}${ADMIN_NOW:-Tidak diketahui}${RESET}"
    echo -e "${BIRU}  ${GREEN}Bot Status :${RESET} ${CYAN}${BOT_STAT:-unknown}${RESET}"
else
    echo -e "${BIRU}  ${YELLOW}Bot Telegram: BELUM DIATUR${RESET}"
fi

echo -e "${BIRU}╠══════════════════════════════════════════════════════════╣${RESET}"
echo -e "${BIRU}  ${YELLOW}[1]${RESET} ${CYAN}Restart Sistem VPS${RESET}"
echo -e "${BIRU}  ${YELLOW}[2]${RESET} ${CYAN}Atur Bot Telegram${RESET}"
echo -e "${BIRU}  ${YELLOW}[3]${RESET} ${CYAN}Restart Bot${RESET}"
echo -e "${BIRU}  ${YELLOW}[4]${RESET} ${CYAN}Stop Bot${RESET}"
echo -e "${BIRU}  ${YELLOW}[5]${RESET} ${CYAN}Atur / Ubah Banner SSH${RESET}"
echo -e "${BIRU}  ${YELLOW}[6]${RESET} ${CYAN}Status Service${RESET}"
echo -e "${BIRU}  ${YELLOW}[7]${RESET} ${CYAN}Restart Service${RESET}"
echo -e "${BIRU}  ${YELLOW}[8]${RESET} ${CYAN}Tes Speed / Profil Koneksi${RESET}"
echo -e "${BIRU}  ${YELLOW}[x]${RESET} ${CYAN}Back${RESET}"
echo -e "${BIRU}╚══════════════════════════════════════════════════════════╝${RESET}"
echo ""
read -r -p "Pilih menu [1-8/x] : " ops

case "$ops" in
1)
    require_root
    read -r -p "Yakin restart sistem VPS sekarang? (y/n): " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] && reboot
    ;;
2)
    require_root
    echo ""
    read -r -p "Bot Token (dari @BotFather): " TOKEN
    read -r -p "Admin Chat ID: " ADMIN
    if [ -z "$TOKEN" ] || [ -z "$ADMIN" ]; then
        echo -e "${RED}Token/Admin kosong, dibatalkan.${RESET}"
        kembali_settings
    fi
    umask 077
    cat > /etc/bot-telegram.conf <<EOF2
TOKEN=$TOKEN
ADMIN=$ADMIN
EOF2
    chmod 600 /etc/bot-telegram.conf
    if ! python3 -c 'import telebot' 2>/dev/null; then
        echo -e "${YELLOW}Module telebot belum terinstall.${RESET}"
        read -r -p "Install sekarang? (y/n): " INSTALL
        if [[ "$INSTALL" =~ ^[Yy]$ ]]; then
            apt-get update && apt-get install -y python3 python3-pip curl wget
            pip3 install pyTelegramBotAPI --break-system-packages
            if ! python3 -c 'import telebot' 2>/dev/null; then echo -e "${RED}Gagal memasang telebot.${RESET}"; kembali_settings; fi
        else
            echo -e "${YELLOW}Instalasi dibatalkan.${RESET}"
            kembali_settings
        fi
    fi
    if ! wget -q -O /usr/local/bin/bot-telegram "$BOT_URL"; then
        echo -e "${RED}Gagal mengunduh bot.py.${RESET}"
        rm -f /usr/local/bin/bot-telegram
        kembali_settings
    fi
    chmod 755 /usr/local/bin/bot-telegram
    cat > /etc/systemd/system/bot-telegram.service <<'EOF2'
[Unit]
Description=Telegram Bot SSH Manager
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/bot-telegram
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF2
    systemctl daemon-reload
    systemctl enable bot-telegram >/dev/null 2>&1
    systemctl restart bot-telegram
    sleep 3
    if systemctl is-active --quiet bot-telegram; then
        echo -e "${GREEN}Bot Telegram AKTIF.${RESET}"
    else
        echo -e "${RED}Bot gagal start. Log:${RESET}"
        journalctl -u bot-telegram -n 10 --no-pager
    fi
    kembali_settings
    ;;
3)
    systemctl restart bot-telegram 2>/dev/null
    sleep 2
    if systemctl is-active --quiet bot-telegram; then
        echo -e "${GREEN}Bot berhasil direstart.${RESET}"
    else
        echo -e "${RED}Bot gagal restart.${RESET}"
        journalctl -u bot-telegram -n 5 --no-pager
    fi
    kembali_settings
    ;;
4)
    systemctl stop bot-telegram 2>/dev/null
    echo -e "${GREEN}Bot dihentikan.${RESET}"
    kembali_settings
    ;;
5)
    require_root
    echo ""
    echo -e "${CYAN}========== SETUP / UBAH BANNER SSH ==========${RESET}"
    echo -e "${YELLOW}Banner saat ini:${RESET}"
    echo -e "${CYAN}--------------------------------------------${RESET}"
    if [ -f "$BANNER_FILE" ]; then cat "$BANNER_FILE"; else echo "Belum ada banner."; fi
    echo -e "${CYAN}--------------------------------------------${RESET}"
    echo "Masukkan banner baru. Ketik SELESAI pada baris tersendiri jika sudah."
    TMP_BANNER=$(mktemp) || kembali_settings
    while IFS= read -r LINE; do
        [ "$LINE" = "SELESAI" ] && break
        printf '%s\n' "$LINE" >> "$TMP_BANNER"
    done
    if [ ! -s "$TMP_BANNER" ]; then
        rm -f "$TMP_BANNER"
        echo -e "${RED}Banner kosong. Perubahan dibatalkan.${RESET}"
        kembali_settings
    fi
    echo ""
    echo -e "${YELLOW}Preview banner baru:${RESET}"
    cat "$TMP_BANNER"
    read -r -p "Simpan banner ini? (y/n): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        rm -f "$TMP_BANNER"
        echo -e "${YELLOW}Perubahan dibatalkan.${RESET}"
        kembali_settings
    fi
    [ -f "$BANNER_FILE" ] && cp -a "$BANNER_FILE" "${BANNER_FILE}.bak-$(date +%Y%m%d-%H%M%S)"
    install -m 644 "$TMP_BANNER" "$BANNER_FILE"
    rm -f "$TMP_BANNER"
    if [ -f "$DROPBEAR_CONFIG" ]; then
        if grep -qE '^DROPBEAR_EXTRA_ARGS=' "$DROPBEAR_CONFIG"; then
            CURRENT_ARGS=$(sed -n 's/^DROPBEAR_EXTRA_ARGS="\{0,1\}\(.*\)"\{0,1\}$/\1/p' "$DROPBEAR_CONFIG" | tail -n 1)
            if ! grep -qE '(^|[[:space:]])-b([[:space:]]|$)' <<< "$CURRENT_ARGS"; then
                CURRENT_ARGS="${CURRENT_ARGS} -b /etc/issue.net"
                sed -i '/^DROPBEAR_EXTRA_ARGS=/d' "$DROPBEAR_CONFIG"
                printf 'DROPBEAR_EXTRA_ARGS="%s"\n' "$CURRENT_ARGS" >> "$DROPBEAR_CONFIG"
            fi
        else
            printf '\nDROPBEAR_EXTRA_ARGS="-b /etc/issue.net"\n' >> "$DROPBEAR_CONFIG"
        fi
        echo -e "${GREEN}Banner tersimpan di $BANNER_FILE.${RESET}"
        if systemctl is-active --quiet dropbear; then
            if systemctl restart dropbear; then echo -e "${GREEN}Dropbear berhasil direstart.${RESET}"; else echo -e "${RED}Restart gagal. Periksa journalctl -u dropbear -n 30 --no-pager${RESET}"; fi
        else
            echo -e "${YELLOW}Dropbear sedang tidak aktif; layanan tidak dinyalakan otomatis.${RESET}"
        fi
    else
        echo -e "${YELLOW}Konfigurasi Dropbear tidak ditemukan.${RESET}"
        echo -e "${GREEN}File banner tetap tersimpan di $BANNER_FILE.${RESET}"
    fi
    kembali_settings
    ;;
6)
    show_service_status
    kembali_settings
    ;;
7)
    require_root
    restart_service_menu
    kembali_settings
    ;;
8)
    echo ""
    echo -e "${CYAN}========== SPEED & OPTIMASI KONEKSI ==========${RESET}"
    echo "[1] Tes Speed Koneksi"
    echo "[2] Pilih Profil Normal / Sedang / Highspeed"
    echo "[x] Kembali"
    read -r -p "Pilih [1-2/x]: " speed_menu
    case "$speed_menu" in
        1) speed_test ;;
        2) speed_profile ;;
        x|X) ;;
        *) echo -e "${RED}Pilihan tidak valid.${RESET}" ;;
    esac
    kembali_settings
    ;;
x|X|0)
    # Kembali ke menu utama lokal jika ada, lalu coba URL menu utama.
    if declare -F menu >/dev/null 2>&1; then
        menu
    elif command -v menu >/dev/null 2>&1; then
        menu
    elif [ -x /usr/local/sbin/menu ]; then
        /usr/local/sbin/menu
    elif [ -x /usr/bin/menu ]; then
        /usr/bin/menu
    elif command -v curl >/dev/null 2>&1; then
        echo "Mencoba membuka menu utama dari repositori..."
        if curl -fLsS "$MAIN_MENU_URL" -o /tmp/sansxml-main-menu.sh; then
            bash /tmp/sansxml-main-menu.sh
        else
            echo -e "${YELLOW}Menu utama tidak ditemukan di lokasi default.${RESET}"
            echo "Atur MAIN_MENU_URL sesuai lokasi file menu utama di GitHub."
            read -r -p "Tekan Enter untuk keluar..."
        fi
    else
        echo "Perintah menu utama tidak ditemukan."
        read -r -p "Tekan Enter untuk keluar..."
    fi
    exit 0
    ;;
*)
    echo -e "${RED}Pilihan tidak valid.${RESET}"
    sleep 1
    kembali_settings
    ;;
esac

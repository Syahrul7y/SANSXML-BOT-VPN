#!/bin/bash
clear

BIRU='\033[0;34m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
RESET='\033[0m'

bar() {
    local pct=$1
    local filled=$(( pct * 10 / 100 ))
    local empty=$(( 10 - filled ))
    local color=$GREEN
    [ "$pct" -ge 60 ] && color=$YELLOW
    [ "$pct" -ge 85 ] && color=$RED
    printf "${color}"
    for ((i=0; i<filled; i++)); do printf "█"; done
    printf "${BIRU}"
    for ((i=0; i<empty; i++)); do printf "░"; done
    printf "${RESET}"
}

OS=$(source /etc/os-release && echo "$PRETTY_NAME")
IP=$(curl -4 -s ifconfig.me 2>/dev/null)
[ -z "$IP" ] && IP=$(curl -4 -s icanhazip.com 2>/dev/null)
[ -z "$IP" ] && IP="Unknown"

COUNTRY="Unknown"
for api in \
    "http://ip-api.com/line/$IP?fields=country" \
    "https://ifconfig.co/country" \
    "https://ipinfo.io/$IP/country"; do
    RES=$(curl -4 -s --max-time 3 "$api" 2>/dev/null | tr -d '\n\r')
    if [ -n "$RES" ] && ! echo "$RES" | grep -qi "error\|rate\|title\|message\|{\|not found\|unknown"; then
        COUNTRY="$RES"
        break
    fi
done
COUNTRY=$(echo "$COUNTRY" | cut -c1-30)
[ -z "$COUNTRY" ] && COUNTRY="Unknown"

DOMAIN=$(cat /root/.domain 2>/dev/null)
[ -z "$DOMAIN" ] && DOMAIN="(Belum di-set)"
UPTIME=$(uptime -p | sed 's/up //')

RAM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
RAM_USED=$(free -m | awk '/Mem:/ {print $3}')
RAM_PCT=$(free | awk '/Mem:/ {printf "%.0f", $3/$2*100}')

DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}')
DISK_USED=$(df -h / | awk 'NR==2 {print $3}')
DISK_PCT=$(df / | awk 'NR==2 {print $5}' | tr -d '%')

CPU_PCT=$(top -bn1 | grep "Cpu(s)" | awk '{print int($2 + $4)}')
[ -z "$CPU_PCT" ] && CPU_PCT=0

MONTH=$(date +%B)
RX_MONTH=$(vnstat -m 2>/dev/null | grep "$MONTH" | awk '{print $2" "$3}' | head -1)
TX_MONTH=$(vnstat -m 2>/dev/null | grep "$MONTH" | awk '{print $5" "$6}' | head -1)
TOTAL_MONTH=$(vnstat -m 2>/dev/null | grep "$MONTH" | awk '{print $8" "$9}' | head -1)
[ -z "$RX_MONTH" ] && RX_MONTH="0 MiB"
[ -z "$TX_MONTH" ] && TX_MONTH="0 MiB"
[ -z "$TOTAL_MONTH" ] && TOTAL_MONTH="0 MiB"

SPEED=$(vnstat -tr 2 2>/dev/null | grep "rx" | awk '{print $2" "$3}' | head -1)
[ -z "$SPEED" ] && SPEED="0 Mbit/s"

SSH_USR=$(awk -F: '$3 >= 1000 && $3 < 60000 {print $1}' /etc/passwd | wc -l)

if systemctl is-active --quiet ssh-ws 2>/dev/null; then SW="${GREEN}ON${RESET}"; else SW="${RED}OFF${RESET}"; fi
if systemctl is-active --quiet udpgw 2>/dev/null; then UG="${GREEN}ON${RESET}"; else UG="${RED}OFF${RESET}"; fi
if systemctl is-active --quiet stunnel4 2>/dev/null; then TS="${GREEN}ON${RESET}"; else TS="${RED}OFF${RESET}"; fi

echo -e "${BIRU}╔══════════════════════════════════════════════════╗${RESET}"
echo -e "${BIRU}       ${YELLOW}SANSXML SSH TUNNELING MANAGER${RESET}"
echo -e "${BIRU}╠══════════════════════════════════════════════════╣${RESET}"
echo -e "${BIRU} ${GREEN}OS      :${RESET} ${CYAN}$OS${RESET}"
echo -e "${BIRU} ${GREEN}IP      :${RESET} ${CYAN}$IP${RESET}"
echo -e "${BIRU} ${GREEN}COUNTRY :${RESET} ${CYAN}$COUNTRY${RESET}"
echo -e "${BIRU} ${GREEN}DOMAIN  :${RESET} ${CYAN}$DOMAIN${RESET}"
echo -e "${BIRU} ${GREEN}UPTIME  :${RESET} ${CYAN}$UPTIME${RESET}"
echo -e "${BIRU}╠══════════════════════════════════════════════════╣${RESET}"
echo -e "${BIRU} ${GREEN}RAM     :${RESET} $(bar $RAM_PCT) ${CYAN}${RAM_USED}MB/${RAM_TOTAL}MB  ${YELLOW}${RAM_PCT}%${RESET}"
echo -e "${BIRU} ${GREEN}DISK    :${RESET} $(bar $DISK_PCT) ${CYAN}${DISK_USED}/${DISK_TOTAL}  ${YELLOW}${DISK_PCT}%${RESET}"
echo -e "${BIRU} ${GREEN}CPU     :${RESET} $(bar $CPU_PCT) ${CYAN}Load: ${CPU_PCT}%${RESET}"
echo -e "${BIRU}╠══════════════════════════════════════════════════╣${RESET}"
echo -e "${BIRU} ${GREEN}MONTH   :${RESET} ${CYAN}$TOTAL_MONTH${RESET}  ${YELLOW}[$MONTH]${RESET}"
echo -e "${BIRU} ${GREEN}RX      :${RESET} ${CYAN}$RX_MONTH${RESET}"
echo -e "${BIRU} ${GREEN}TX      :${RESET} ${CYAN}$TX_MONTH${RESET}"
echo -e "${BIRU} ${GREEN}SPEED   :${RESET} ${CYAN}$SPEED${RESET}"
echo -e "${BIRU}╚══════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "${BIRU}╔══════════════════════════════════════════════════╗${RESET}"
echo -e "${BIRU} ${GREEN}STATUS  :${RESET} ${CYAN}SSH/WS:${RESET} $SW  ${BIRU}|${RESET}  ${CYAN}UDPGW:${RESET} $UG  ${BIRU}|${RESET}  ${CYAN}TLS:${RESET} $TS"
echo -e "${BIRU}╚══════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "${BIRU}╔══════════════════════════════════════════════════╗${RESET}"
echo -e "${BIRU}                   ${YELLOW}LIST USER${RESET}"
echo -e "${BIRU}╠══════════════════════════════════════════════════╣${RESET}"
echo -e "${BIRU}  ${GREEN}SSH/WS :${RESET} ${CYAN}$SSH_USR USER${RESET}             ${GREEN}TOTAL :${RESET} ${CYAN}$SSH_USR USER${RESET}"
echo -e "${BIRU}╚══════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "${BIRU}╔══════════════════════════════════════════════════╗${RESET}"
echo -e "${BIRU}                 ${YELLOW}SANSXML VPN STORE${RESET}"
echo -e "${BIRU}╠══════════════════════════════════════════════════╣${RESET}"
# Menu dirapikan dengan posisi kolom yang konsisten
printf "${BIRU}  ${YELLOW}[1]${RESET} ${CYAN}%-14s${RESET}  ${YELLOW}[5]${RESET} ${CYAN}%s${RESET}\n" "SSH ACCOUNT" "ADD DOMAIN"
printf "${BIRU}  ${YELLOW}[2]${RESET} ${CYAN}%-14s${RESET}  ${YELLOW}[6]${RESET} ${CYAN}%s${RESET}\n" "VMESS" "SETTINGS"
printf "${BIRU}  ${YELLOW}[3]${RESET} ${CYAN}%-14s${RESET}  ${YELLOW}[7]${RESET} ${CYAN}%s${RESET}\n" "VLESS" "EXIT"
echo -e "${BIRU}  ${YELLOW}[4]${RESET} ${CYAN}TROJAN${RESET}"
echo -e "${BIRU}╚══════════════════════════════════════════════════╝${RESET}"
echo ""
read -r -p "Pilih menu [1-7] : " ops

case "$ops" in
1) bash /usr/local/bin/ssh-menu ;;
2) echo -e "${YELLOW}VMess belum dikonfigurasi; fitur belum aktif.${RESET}"; read -r -p "Tekan Enter untuk kembali..."; exec bash "$0" ;;
3) echo -e "${YELLOW}VLESS belum dikonfigurasi; fitur belum aktif.${RESET}"; read -r -p "Tekan Enter untuk kembali..."; exec bash "$0" ;;
4) echo -e "${YELLOW}Trojan belum dikonfigurasi; fitur belum aktif.${RESET}"; read -r -p "Tekan Enter untuk kembali..."; exec bash "$0" ;;
5) bash /usr/local/bin/domain ;;
6) bash /usr/local/bin/settings ;;
7|x|X|0) exit 0 ;;
*) echo -e "${RED}Pilihan tidak valid.${RESET}"; sleep 1; exec bash "$0" ;;
esac

#!/bin/bash
clear
BIRU='\033[0;34m'; CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RESET='\033[0m'
echo -e "${BIRU}╔══════════════════════════════════════════════════╗${RESET}"
echo -e "${BIRU}                 ${YELLOW}☯ SSH MENU${RESET}"
echo -e "${BIRU}╠══════════════════════════════════════════════════╣${RESET}"
echo -e "${BIRU}  ${YELLOW}[1]${RESET} ${CYAN}CREATE ACCOUNT SSH${RESET}"
echo -e "${BIRU}  ${YELLOW}[2]${RESET} ${CYAN}CREATE TRIAL SSH (30 MINUTE)${RESET}"
echo -e "${BIRU}  ${YELLOW}[3]${RESET} ${CYAN}LIST ACCOUNT SSH${RESET}"
echo -e "${BIRU}  ${YELLOW}[4]${RESET} ${CYAN}DELETE AKUN SSH${RESET}"
echo -e "${BIRU}  ${YELLOW}[5]${RESET} ${CYAN}EXIT${RESET}"
echo -e "${BIRU}╚══════════════════════════════════════════════════╝${RESET}"
read -r -p "Pilih menu : " ops
case "$ops" in
  1) bash /usr/local/bin/addssh ;;
  2)
    set -e
    LOGIN="trial-ssh-$(tr -dc 'a-z0-9' </dev/urandom | head -c 6)"
    PASS="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 10)"
    while getent passwd "$LOGIN" >/dev/null; do LOGIN="trial-ssh-$(tr -dc 'a-z0-9' </dev/urandom | head -c 6)"; done
    useradd -M -s /usr/sbin/nologin "$LOGIN"
    echo "$LOGIN:$PASS" | chpasswd
    mkdir -p /etc/ssh-trial-expiry /etc/iplimit-user
    echo 1 > "/etc/iplimit-user/$LOGIN"
    date -d '+30 minutes' +%s > "/etc/ssh-trial-expiry/$LOGIN"
    echo
    echo "TRIAL SSH BERHASIL DIBUAT"
    echo "Username : $LOGIN"
    echo "Password : $PASS"
    echo "Masa aktif: 30 menit"
    echo "Akun akan dihapus otomatis setelah kedaluwarsa."
    read -r -p "Tekan Enter untuk kembali..."
    exec "$0"
    ;;
  3) bash /usr/local/bin/list-ssh ;;
  4) bash /usr/local/bin/delete-ssh ;;
  5|x|X) menu ;;
  *) exec "$0" ;;
esac

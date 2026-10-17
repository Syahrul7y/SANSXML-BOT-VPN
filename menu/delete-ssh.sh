#!/bin/bash
clear

BIRU='\033[0;34m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
RESET='\033[0m'

echo -e "${BIRU}╔══════════════════════════════════════════════════╗${RESET}"
echo -e "${BIRU}       ${YELLOW}SANSXML SSH TUNNELING MANAGER${RESET}"
echo -e "${BIRU}╠══════════════════════════════════════════════════╣${RESET}"
echo -e "${BIRU}                 ${YELLOW}DELETE ACCOUNT${RESET}"
echo -e "${BIRU}╠══════════════════════════════════════════════════╣${RESET}"
printf "${BIRU}  ${GREEN}%-18s %-18s %-10s${RESET}\n" "USERNAME" "EXP DATE" "STATUS"
echo -e "${BIRU}╠══════════════════════════════════════════════════╣${RESET}"

while read expired
do
    AKUN="$(echo $expired | cut -d: -f1)"
    ID="$(echo $expired | grep -v nobody | cut -d: -f3)"
    exp="$(chage -l $AKUN | grep "Account expires" | awk -F": " '{print $2}')"
    status="$(passwd -S $AKUN | awk '{print $2}')"

    if [[ $ID -ge 1000 ]]; then
        if [[ "$status" = "L" ]]; then
            STAT="${RED}LOCKED${RESET}"
        else
            STAT="${GREEN}UNLOCKED${RESET}"
        fi
        printf "${BIRU}  ${CYAN}%-18s %-18s${RESET} %-10b\n" "$AKUN" "$exp" "$STAT"
    fi
done < /etc/passwd

JUMLAH="$(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd | wc -l)"
echo -e "${BIRU}╠══════════════════════════════════════════════════╣${RESET}"
echo -e "${BIRU}  ${GREEN}Account number :${RESET} ${CYAN}$JUMLAH user${RESET}"
echo -e "${BIRU}╚══════════════════════════════════════════════════╝${RESET}"
echo ""
read -p "Username SSH to Delete : " Pengguna

if getent passwd "$Pengguna" > /dev/null 2>&1; then
    pkill -u "$Pengguna" 2>/dev/null
    userdel -r "$Pengguna" > /dev/null 2>&1
    rm -f "/etc/iplimit-user/$Pengguna"
    echo ""
    echo -e "${GREEN}  ✅ User $Pengguna berhasil dihapus${RESET}"
    systemctl restart dropbear 2>/dev/null
else
    echo ""
    echo -e "${RED}  ❌ User $Pengguna tidak ditemukan${RESET}"
fi

echo ""
read -p "Tekan Enter untuk kembali..."
menu

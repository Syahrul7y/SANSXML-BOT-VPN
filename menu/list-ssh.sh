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
echo -e "${BIRU}                  ${YELLOW}LIST USER${RESET}"
echo -e "${BIRU}╠══════════════════════════════════════════════════╣${RESET}"
printf "${BIRU}  ${GREEN}%-14s %-16s %-8s %-8s${RESET}\n" "USERNAME" "EXP DATE" "DEVICE" "STATUS"
echo -e "${BIRU}╠══════════════════════════════════════════════════╣${RESET}"

while read expired
do
    AKUN="$(echo $expired | cut -d: -f1)"
    ID="$(echo $expired | grep -v nobody | cut -d: -f3)"
    exp="$(chage -l $AKUN | grep "Account expires" | awk -F": " '{print $2}')"
    status="$(passwd -S $AKUN | awk '{print $2}')"

    if [[ $ID -ge 1000 ]]; then
        MAX=1
        [ -f "/etc/iplimit-user/$AKUN" ] && MAX=$(cat "/etc/iplimit-user/$AKUN" 2>/dev/null)
        [ -z "$MAX" ] && MAX=1

        SESS=$(who -u 2>/dev/null | awk -v u="$AKUN" '$1 == u' | wc -l)
        DEV="${SESS}/${MAX}"

        if [[ "$status" = "L" ]]; then
            STAT="${RED}BLOKIR${RESET}"
        elif [ "$SESS" -gt "$MAX" ]; then
            STAT="${RED}KICK${RESET}"
        else
            STAT="${GREEN}ONLINE${RESET}"
        fi

        printf "${BIRU}  ${CYAN}%-14s %-16s %-8s${RESET} %-8b\n" "$AKUN" "$exp" "$DEV" "$STAT"
    fi
done < /etc/passwd

JUMLAH="$(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd | wc -l)"
echo -e "${BIRU}╠══════════════════════════════════════════════════╣${RESET}"
echo -e "${BIRU}  ${GREEN}Total Akun :${RESET} ${CYAN}$JUMLAH user${RESET}"
echo -e "${BIRU}╚══════════════════════════════════════════════════╝${RESET}"
echo ""
read -p "Tekan Enter untuk kembali..."
menu

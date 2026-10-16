#!/bin/bash
clear

BIRU='\033[0;34m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RESET='\033[0m'

echo -e "${BIRU}╔══════════════════════════════════════════════════╗${RESET}"
echo -e "${BIRU}       ${YELLOW}SANSXML SSH TUNNELING MANAGER${RESET}"
echo -e "${BIRU}╠══════════════════════════════════════════════════╣${RESET}"
echo -e "${BIRU}                 ${YELLOW}CHANGE DOMAIN${RESET}"
echo -e "${BIRU}╠══════════════════════════════════════════════════╣${RESET}"

OLD_DOMAIN=$(cat /root/.domain 2>/dev/null)
[ -z "$OLD_DOMAIN" ] && OLD_DOMAIN="(Belum di-set)"

echo -e "${BIRU}  ${GREEN}Domain Sekarang :${RESET} ${CYAN}$OLD_DOMAIN${RESET}"
echo -e "${BIRU}╠══════════════════════════════════════════════════╣${RESET}"
echo -e "${BIRU}  ${GREEN}Domain Baru :${RESET} \c"
read domain

if [ -z "$domain" ]; then
    echo -e "${BIRU}╠══════════════════════════════════════════════════╣${RESET}"
    echo -e "${BIRU}  ${YELLOW}⚠ Domain kosong, dibatalkan${RESET}"
else
    echo "$domain" > /root/.domain
    echo -e "${BIRU}╠══════════════════════════════════════════════════╣${RESET}"
    echo -e "${BIRU}  ${GREEN}✅ Domain diubah ke:${RESET} ${CYAN}$domain${RESET}"
fi

echo -e "${BIRU}╚══════════════════════════════════════════════════╝${RESET}"
echo ""
read -p "Tekan Enter untuk kembali..."
menu

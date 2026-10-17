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
echo -e "${BIRU}  ${GREEN}Username       :${RESET} \c"; read Login
echo -e "${BIRU}  ${GREEN}Password       :${RESET} \c"; read Pass
echo -e "${BIRU}  ${GREEN}Expired (Days) :${RESET} \c"; read masaaktif
echo -e "${BIRU}  ${GREEN}IP Limit       :${RESET} \c"; read iplimit
echo -e "${BIRU}╚══════════════════════════════════════════════════╝${RESET}"
clear

useradd -e $(date -d "$masaaktif days" +"%Y-%m-%d") -s /bin/false -M "$Login"
echo -e "$Pass\n$Pass" | passwd "$Login" &> /dev/null
exp="$(chage -l $Login | grep "Account expires" | awk -F": " '{print $2}')"

mkdir -p /etc/iplimit-user
echo "$iplimit" > /etc/iplimit-user/$Login

echo -e "${BIRU}╔══════════════════════════════════════════════════╗${RESET}"
echo -e "${BIRU}       ${YELLOW}SANSXML SSH TUNNELING MANAGER${RESET}"
echo -e "${BIRU}╠══════════════════════════════════════════════════╣${RESET}"
echo -e "${BIRU}              ${YELLOW}<= SSH ACCOUNT =>${RESET}"
echo -e "${BIRU}╠══════════════════════════════════════════════════╣${RESET}"
echo -e "${BIRU}  ${GREEN}Username     :${RESET} ${CYAN}$Login${RESET}"
echo -e "${BIRU}  ${GREEN}Password     :${RESET} ${CYAN}$Pass${RESET}"
echo -e "${BIRU}  ${GREEN}Host/IP      :${RESET} ${CYAN}$(cat /root/.domain)${RESET}"
echo -e "${BIRU}  ${GREEN}Port TLS/SSL :${RESET} ${CYAN}443${RESET}"
echo -e "${BIRU}  ${GREEN}Port Non TLS :${RESET} ${CYAN}80${RESET}"
echo -e "${BIRU}  ${GREEN}BadVpn       :${RESET} ${CYAN}7300${RESET}"
echo -e "${BIRU}  ${GREEN}IP Limit     :${RESET} ${CYAN}$iplimit Device${RESET}"
echo -e "${BIRU}╠══════════════════════════════════════════════════╣${RESET}"
echo -e "${BIRU}  ${GREEN}Payload WS   :${RESET}"
echo -e "${CYAN}  GET / HTTP/1.1[crlf]Host: $(cat /root/.domain)[crlf]Upgrade: websocket[crlf][crlf]${RESET}"
echo -e "${BIRU}╠══════════════════════════════════════════════════╣${RESET}"
echo -e "${BIRU}  ${GREEN}Expired      :${RESET} ${CYAN}$exp${RESET}"
echo -e "${BIRU}╚══════════════════════════════════════════════════╝${RESET}"
echo ""
read -p "Tekan Enter untuk kembali..."
menu

#!/usr/bin/env bash
clear
BIRU='\033[0;34m'; CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; RESET='\033[0m'
PROTO="${1:-}"
case "$PROTO" in vmess|vless|trojan) ;; *) echo "Protokol tidak valid."; exit 2 ;; esac
NAME=$(printf '%s' "$PROTO" | tr '[:lower:]' '[:upper:]')
while true; do
  clear
  echo -e "${BIRU}╔══════════════════════════════════════════════════╗${RESET}"
  printf "${BIRU}║${YELLOW}              SANSXML %s ACCOUNT${RESET}\n" "$NAME"
  echo -e "${BIRU}╠══════════════════════════════════════════════════╣${RESET}"
  echo -e "${BIRU}  ${YELLOW}[1]${RESET} ${CYAN}Buat Akun${RESET}"
  echo -e "${BIRU}  ${YELLOW}[2]${RESET} ${CYAN}Buat Akun Trial${RESET}"
  echo -e "${BIRU}  ${YELLOW}[3]${RESET} ${CYAN}Daftar Akun${RESET}"
  echo -e "${BIRU}  ${YELLOW}[4]${RESET} ${CYAN}Hapus Akun${RESET}"
  echo -e "${BIRU}  ${YELLOW}[5]${RESET} ${CYAN}Perpanjang Akun${RESET}"
  echo -e "${BIRU}  ${YELLOW}[0]${RESET} ${CYAN}Kembali${RESET}"
  echo -e "${BIRU}╚══════════════════════════════════════════════════╝${RESET}"
  read -r -p "Pilih menu: " choice
  case "$choice" in
    1) /usr/local/bin/xray-account add "$PROTO" normal; read -r -p "Tekan Enter untuk lanjut..." ;;
    2) /usr/local/bin/xray-account add "$PROTO" trial; read -r -p "Tekan Enter untuk lanjut..." ;;
    3) /usr/local/bin/xray-account list "$PROTO"; read -r -p "Tekan Enter untuk lanjut..." ;;
    4) /usr/local/bin/xray-account delete "$PROTO"; read -r -p "Tekan Enter untuk lanjut..." ;;
    5) /usr/local/bin/xray-account renew "$PROTO"; read -r -p "Tekan Enter untuk lanjut..." ;;
    0|x|X) exec /usr/local/bin/menu ;;
    *) echo -e "${RED}Pilihan tidak valid.${RESET}"; sleep 1 ;;
  esac
done

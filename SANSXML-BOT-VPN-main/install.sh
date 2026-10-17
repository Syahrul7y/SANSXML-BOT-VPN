#!/usr/bin/bash
clear

BIRU='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RESET='\033[0m'

echo -e "${BIRU}╔══════════════════════════════════════════════════╗${RESET}"
echo -e "${BIRU}       ${YELLOW}SANSXML SSH TUNNELING MANAGER${RESET}"
echo -e "${BIRU}╠══════════════════════════════════════════════════╣${RESET}"
echo -e "${BIRU}  ${CYAN}Installing...${RESET}"
echo -e "${BIRU}╚══════════════════════════════════════════════════╝${RESET}"

# ==========================================
# DEPENDENCIES
# ==========================================
apt update -y
apt install -y wget curl openssl binutils cron sudo vnstat procps python3

# ==========================================
# VNSTAT
# ==========================================
systemctl enable vnstat
systemctl start vnstat

# ==========================================
# EXPIRY SCRIPT
# ==========================================
cd /usr/local/bin

wget -O xp \
  "https://github.com/Syahrul7y/SANSXML-BOT-VPN/raw/refs/heads/main/menu/xp.sh"

chmod +x xp

# Hindari menambahkan cron yang sama berulang kali
grep -Fq '/usr/local/bin/xp' /etc/crontab ||
  echo "*/15 * * * * root /usr/local/bin/xp" >> /etc/crontab

systemctl daemon-reload
systemctl restart cron

# ==========================================
# PROXY & ISSUE.NET
# ==========================================
bash <(curl -fLsS \
  "https://github.com/Syahrul7y/SANSXML-BOT-VPN/raw/refs/heads/main/install/proxy.sh")

# ==========================================
# SANSXML SSH BANNER
# ==========================================
bash <(curl -fLsS \
  "https://github.com/Syahrul7y/SANSXML-BOT-VPN/raw/refs/heads/main/install/banner.sh")

# ==========================================
# PORT 443
# ==========================================
bash <(curl -fLsS \
  "https://github.com/Syahrul7y/SANSXML-BOT-VPN/raw/refs/heads/main/install/443.sh")

# ==========================================
# PORT 80 / WEBSOCKET
# ==========================================
bash <(curl -fLsS \
  "https://github.com/Syahrul7y/SANSXML-BOT-VPN/raw/refs/heads/main/install/80.sh")

# ==========================================
# UDP GATEWAY
# ==========================================
bash <(curl -fLsS \
  "https://github.com/Syahrul7y/SANSXML-BOT-VPN/raw/refs/heads/main/install/udpgw.sh")

# ==========================================
# DEVICE LIMIT
# ==========================================
bash <(curl -fLsS \
  "https://github.com/Syahrul7y/SANSXML-BOT-VPN/raw/refs/heads/main/install/devicelimit.sh")

# ==========================================
# SSH MENU
# ==========================================
cd /usr/local/bin

wget -O menu \
  "https://github.com/Syahrul7y/SANSXML-BOT-VPN/raw/refs/heads/main/menu/menu-ssh.sh"

chmod +x menu

# SSH submenu and account actions
wget -q -O /usr/local/bin/ssh-menu "https://github.com/Syahrul7y/SANSXML-BOT-VPN/raw/refs/heads/main/menu/ssh-menu.sh"
wget -q -O /usr/local/bin/addssh "https://github.com/Syahrul7y/SANSXML-BOT-VPN/raw/refs/heads/main/menu/addssh.sh"
wget -q -O /usr/local/bin/list-ssh "https://github.com/Syahrul7y/SANSXML-BOT-VPN/raw/refs/heads/main/menu/list-ssh.sh"
wget -q -O /usr/local/bin/delete-ssh "https://github.com/Syahrul7y/SANSXML-BOT-VPN/raw/refs/heads/main/menu/delete-ssh.sh"
wget -q -O /usr/local/bin/domain "https://github.com/Syahrul7y/SANSXML-BOT-VPN/raw/refs/heads/main/menu/domain.sh"
wget -q -O /usr/local/bin/settings "https://github.com/Syahrul7y/SANSXML-BOT-VPN/raw/refs/heads/main/menu/settings.sh"
wget -q -O /usr/local/bin/expire-trial-ssh "https://github.com/Syahrul7y/SANSXML-BOT-VPN/raw/refs/heads/main/menu/expire-trial-ssh.sh"
chmod +x /usr/local/bin/ssh-menu /usr/local/bin/addssh /usr/local/bin/list-ssh /usr/local/bin/delete-ssh /usr/local/bin/domain /usr/local/bin/settings /usr/local/bin/expire-trial-ssh

# Check trial SSH expiry every minute
grep -Fq '/usr/local/bin/expire-trial-ssh' /etc/crontab ||
  echo '* * * * * root /usr/local/bin/expire-trial-ssh' >> /etc/crontab
systemctl restart cron

# ==========================================
# AUTO MENU ON LOGIN
# ==========================================
grep -qE '^[[:space:]]*menu[[:space:]]*$' /root/.bashrc ||
  echo "menu" >> /root/.bashrc

# ==========================================
# XRAY (VMess / VLESS / Trojan)
# ==========================================
echo
echo "[SANSXML] Menyiapkan installer Xray..."
apt-get update -y
apt-get install -y git
XRAY_SRC="/opt/SANSXML-BOT-VPN-xray-installer"
if [[ -d "$XRAY_SRC/.git" ]]; then
  git -C "$XRAY_SRC" fetch --depth=1 origin main
  git -C "$XRAY_SRC" reset --hard origin/main
else
  rm -rf "$XRAY_SRC"
  git clone --depth=1 https://github.com/Syahrul7y/SANSXML-BOT-VPN.git "$XRAY_SRC"
fi
if [[ -x "$XRAY_SRC/install/install-xray.sh" || -f "$XRAY_SRC/install/install-xray.sh" ]]; then
  bash "$XRAY_SRC/install/install-xray.sh"
else
  echo "GAGAL: install/install-xray.sh tidak ditemukan di repo GitHub." >&2
  exit 1
fi

# ==========================================
# FINISH
# ==========================================
clear
menu

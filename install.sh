#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
CYAN='\033[1;36m'; GREEN='\033[1;32m'; RED='\033[1;31m'
YELLOW='\033[1;33m'; MAGENTA='\033[1;35m'; WHITE='\033[1;37m'; NC='\033[0m'

spin(){
  local pid=$1 msg="$2"
  local f=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  while kill -0 "$pid" 2>/dev/null; do
    for x in "${f[@]}"; do
      printf "\r  ${CYAN}${x}${NC} ${WHITE}%s${NC}   " "$msg"
      sleep 0.08
      kill -0 "$pid" 2>/dev/null || break
    done
  done
  wait "$pid"; local rc=$?
  if [ "$rc" -eq 0 ]; then
    printf "\r  ${GREEN}✓${NC} ${WHITE}%s${NC}\n" "$msg"
  else
    printf "\r  ${RED}✗${NC} ${WHITE}%s${NC} ${RED}(error)${NC}\n" "$msg"
  fi
  return "$rc"
}

clear
echo ""

# 1. DEPENDENCIES

( apt-get update -y >/dev/null 2>&1 ) & spin $! "Update repository"
_pkg_install(){
  dpkg --configure -a >/dev/null 2>&1 || true
  apt-get -f install -y >/dev/null 2>&1 || true
  apt-get install -y --no-install-recommends python3 python3-pip python3-venv sshpass curl wget unzip stunnel4 dropbear haproxy nginx net-tools cron ufw iptables openssl cmake build-essential git pkg-config bc procps dnsutils vnstat uuid-runtime socat >/tmp/sansxml-apt-install.log 2>&1
}
_pkg_install & _pkg_pid=$!
spin $_pkg_pid "Install packages" || {
  echo -e "  ${RED}┌─ PACKAGE ERROR ─────────────────────────────────────────┐${NC}"
  tail -n 12 /tmp/sansxml-apt-install.log 2>/dev/null | sed 's/^/  │ /'
  echo -e "  ${RED}└─────────────────────────────────────────────────────────┘${NC}"
  exit 1
}
( pip3 install --break-system-packages --upgrade "python-telegram-bot>=21.5" requests qrcode pillow >/dev/null 2>&1 \
    || pip3 install --upgrade "python-telegram-bot>=21.5" requests qrcode pillow >/dev/null 2>&1 ) & spin $! "Install Telegram API"
( mkdir -p /etc/dropbear
  if [ -f /etc/default/dropbear ]; then
    sed -i 's/^NO_START=.*/NO_START=0/' /etc/default/dropbear
    sed -i 's/^DROPBEAR_PORT=.*/DROPBEAR_PORT=109/' /etc/default/dropbear
    grep -q '^DROPBEAR_PORT=' /etc/default/dropbear || echo 'DROPBEAR_PORT=109' >> /etc/default/dropbear
    sed -i 's/^DROPBEAR_EXTRA_ARGS=.*/DROPBEAR_EXTRA_ARGS="-p 109"/' /etc/default/dropbear
  fi
  systemctl daemon-reload >/dev/null 2>&1 || true
) & spin $! "Install Dropbear"

( cat > /etc/nginx/sites-available/sansxml << 'NGINXEOF'
server {
    listen 127.0.0.1:8081;
    server_name _;
    location / {
        return 200 "SANSXML VPN STORE";
        add_header Content-Type text/plain;
    }
}
NGINXEOF
  rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
  ln -sf /etc/nginx/sites-available/sansxml /etc/nginx/sites-enabled/sansxml
  nginx -t >/dev/null 2>&1
) & spin $! "Install Nginx"

( cat > /etc/haproxy/haproxy.cfg << 'HAPROXYEOF'
global
    log /dev/log local0
    log /dev/log local1 notice
    daemon

defaults
    mode tcp
    timeout connect 5s
    timeout client 30s
    timeout server 30s

frontend sansxml_frontend
    bind 127.0.0.1:8082
    default_backend sansxml_backend

backend sansxml_backend
    mode tcp
    server nginx 127.0.0.1:8081 check
HAPROXYEOF
  haproxy -c -f /etc/haproxy/haproxy.cfg >/dev/null 2>&1
) & spin $! "Install HAProxy"

( mkdir -p /root/.ssh; chmod 700 /root/.ssh
  [ ! -f /root/.ssh/id_bot ] && ssh-keygen -t ed25519 -f /root/.ssh/id_bot -N "" -q
  cat /root/.ssh/id_bot.pub >> /root/.ssh/authorized_keys
  sort -u /root/.ssh/authorized_keys -o /root/.ssh/authorized_keys
  chmod 600 /root/.ssh/authorized_keys ) & spin $! "Generate SSH key"
( systemctl enable vnstat >/dev/null 2>&1; systemctl restart vnstat >/dev/null 2>&1 ) & spin $! "Enable vnstat"

# 3. VPN SERVICES
echo ""

( cat > /usr/local/bin/ws-ssh.py << 'WSEOF'
#!/usr/bin/env python3
import socket, threading, sys, hashlib, base64
LP = int(sys.argv[1]) if len(sys.argv) > 1 else 80
def fwd(src, dst):
    try:
        while True:
            d = src.recv(65536)
            if not d: break
            dst.sendall(d)
    except: pass
    finally:
        try: dst.shutdown(socket.SHUT_WR)
        except: pass
def handle(c, a):
    try:
        c.settimeout(3); first = b""
        try: first = c.recv(4096)
        except: pass
        if first and first.startswith((b"GET ",b"POST ",b"CONNECT ",b"HEAD ")):
            h = first
            try:
                while b"\r\n\r\n" not in h and len(h) < 65536:
                    x = c.recv(4096)
                    if not x: break
                    h += x
            except: pass
            k = None
            for l in h.split(b"\r\n"):
                if l.lower().startswith(b"sec-websocket-key:"):
                    k = l.split(b":",1)[1].strip(); break
            acc = base64.b64encode(hashlib.sha1(k + b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11").digest()) if k else b"s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
            c.sendall(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: " + acc + b"\r\n\r\n")
        s = socket.create_connection(("127.0.0.1", 22), timeout=10)
        s.settimeout(None); c.settimeout(None)
        if first and not first.startswith((b"GET ",b"POST ",b"CONNECT ",b"HEAD ")):
            s.sendall(first)
        t1 = threading.Thread(target=fwd, args=(c, s), daemon=True)
        t2 = threading.Thread(target=fwd, args=(s, c), daemon=True)
        t1.start(); t2.start(); t1.join(); t2.join()
    except: pass
    finally:
        try: c.close()
        except: pass
def main():
    sv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sv.bind(("0.0.0.0", LP)); sv.listen(500)
    while True:
        try:
            c, a = sv.accept()
            threading.Thread(target=handle, args=(c, a), daemon=True).start()
        except: pass
if __name__ == "__main__": main()
WSEOF
  chmod +x /usr/local/bin/ws-ssh.py
  for port in 80 8080; do
    svc="ws-ssh"; [ "$port" = "8080" ] && svc="ws-ssh-alt"
    cat > /etc/systemd/system/${svc}.service << EOF
[Unit]
Description=WS-SSH $port
After=network.target
[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/ws-ssh.py $port
Restart=always
RestartSec=3
LimitNOFILE=100000
[Install]
WantedBy=multi-user.target
EOF
  done
) & spin $! "Install WS-SSH"

( mkdir -p /etc/stunnel
  openssl req -new -x509 -days 3650 -nodes -out /etc/stunnel/stunnel.pem -keyout /etc/stunnel/stunnel.pem -subj "/CN=sansxml.local" 2>/dev/null
  cat > /etc/stunnel/stunnel.conf << 'EOF'
pid = /var/run/stunnel4.pid
debug = 4
output = /var/log/stunnel4.log
[ssl-443]
accept = 443
connect = 127.0.0.1:80
cert = /etc/stunnel/stunnel.pem
[ssl-8443]
accept = 8443
connect = 127.0.0.1:80
cert = /etc/stunnel/stunnel.pem
EOF
  sed -i 's/^ENABLED=.*/ENABLED=1/' /etc/default/stunnel4 2>/dev/null || echo "ENABLED=1" >> /etc/default/stunnel4 ) & spin $! "Install stunnel SSL"

(
  systemctl stop udpgw 2>/dev/null || true
  rm -rf /tmp/badvpn
  git clone --depth=1 https://github.com/ambrop72/badvpn.git /tmp/badvpn >/dev/null 2>&1
  if [ -d /tmp/badvpn ]; then
    mkdir -p /tmp/badvpn/build && cd /tmp/badvpn/build
    cmake .. -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1 >/dev/null 2>&1
    make -j"$(nproc)" >/dev/null 2>&1
    if [ -f udpgw/badvpn-udpgw ]; then
      install -m 755 udpgw/badvpn-udpgw /tmp/badvpn-udpgw.new
      mv -f /tmp/badvpn-udpgw.new /usr/bin/badvpn-udpgw
    else
      echo "BadVPN UDPGW binary tidak ditemukan setelah compile" >&2
      exit 1
    fi
    cd /root && rm -rf /tmp/badvpn
  else
    echo "Gagal download source BadVPN" >&2
    exit 1
  fi
  cat > /etc/systemd/system/udpgw.service << 'EOF'
[Unit]
Description=UDPGW
After=network.target
[Service]
Type=simple
ExecStart=/usr/bin/badvpn-udpgw --listen-addr 0.0.0.0:7300 --max-clients 500
Restart=always
[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable udpgw >/dev/null 2>&1
  systemctl restart udpgw
) & spin $! "Install UDPGW"

( ufw default allow incoming >/dev/null 2>&1
  ufw default allow outgoing >/dev/null 2>&1
  for p in 22 80 443 8080 8443 8444 8445 10001 10002 10003 10004 10005 10006 10007; do ufw allow $p/tcp >/dev/null 2>&1; done
  ufw allow 7300/udp >/dev/null 2>&1; ufw allow 1:65535/udp >/dev/null 2>&1
  ufw --force enable >/dev/null 2>&1 ) & spin $! "Configure firewall"

( systemctl daemon-reload
  systemctl enable ws-ssh ws-ssh-alt stunnel4 dropbear nginx haproxy >/dev/null 2>&1
  systemctl restart ws-ssh ws-ssh-alt stunnel4 dropbear nginx haproxy
  [ -f /usr/bin/badvpn-udpgw ] && systemctl enable udpgw >/dev/null 2>&1 && systemctl restart udpgw
  sleep 2 ) & spin $! "Start VPN services"

DOMAIN="sgivip.naaofficial.web.id"

# 4. VPN CORE
echo ""
(
  set -e
  if ! command -v xray >/dev/null 2>&1; then
    bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
  fi
  systemctl stop xray 2>/dev/null || true
  systemctl enable xray >/dev/null 2>&1 || true
  mkdir -p /etc/xray/accounts /var/lib/xray
  # TLS certificate: try Let's Encrypt first; fallback to a local certificate.
  if command -v certbot >/dev/null 2>&1; then :; else apt-get install -y certbot >/dev/null 2>&1 || true; fi
  systemctl stop ws-ssh ws-ssh-alt stunnel4 2>/dev/null || true
  if [ -n "${DOMAIN:-}" ] && command -v certbot >/dev/null 2>&1; then
    certbot certonly --standalone --non-interactive --agree-tos --register-unsafely-without-email -d "$DOMAIN" >/dev/null 2>&1 || true
  fi
  if [ -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ] && [ -f "/etc/letsencrypt/live/${DOMAIN}/privkey.pem" ]; then
    XRAY_CERT="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
    XRAY_KEY="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"
  else
    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
      -keyout /etc/xray/cert.key -out /etc/xray/cert.pem \
      -subj "/CN=${DOMAIN:-sansxml.local}" >/dev/null 2>&1
    XRAY_CERT="/etc/xray/cert.pem"
    XRAY_KEY="/etc/xray/cert.key"
  fi
  cat > /etc/xray/config.json << XRAYEOF
{
  "log":{"loglevel":"warning"},
  "inbounds":[
    {"tag":"vmess-ws-tls","listen":"0.0.0.0","port":8443,"protocol":"vmess","settings":{"clients":[]},"streamSettings":{"network":"ws","security":"tls","tlsSettings":{"certificates":[{"certificateFile":"${XRAY_CERT}","keyFile":"${XRAY_KEY}"}]},"wsSettings":{"path":"/vmess"}}},
    {"tag":"vmess-ws","listen":"0.0.0.0","port":10001,"protocol":"vmess","settings":{"clients":[]},"streamSettings":{"network":"ws","wsSettings":{"path":"/vmess"}}},
    {"tag":"vmess-grpc","listen":"0.0.0.0","port":10002,"protocol":"vmess","settings":{"clients":[]},"streamSettings":{"network":"grpc","security":"tls","tlsSettings":{"certificates":[{"certificateFile":"${XRAY_CERT}","keyFile":"${XRAY_KEY}"}]},"grpcSettings":{"serviceName":"vmess-grpc"}}},
    {"tag":"vless-ws-tls","listen":"0.0.0.0","port":8444,"protocol":"vless","settings":{"clients":[],"decryption":"none"},"streamSettings":{"network":"ws","security":"tls","tlsSettings":{"certificates":[{"certificateFile":"${XRAY_CERT}","keyFile":"${XRAY_KEY}"}]},"wsSettings":{"path":"/vless"}}},
    {"tag":"vless-ws","listen":"0.0.0.0","port":10003,"protocol":"vless","settings":{"clients":[],"decryption":"none"},"streamSettings":{"network":"ws","wsSettings":{"path":"/vless"}}},
    {"tag":"vless-grpc","listen":"0.0.0.0","port":10004,"protocol":"vless","settings":{"clients":[],"decryption":"none"},"streamSettings":{"network":"grpc","security":"tls","tlsSettings":{"certificates":[{"certificateFile":"${XRAY_CERT}","keyFile":"${XRAY_KEY}"}]},"grpcSettings":{"serviceName":"vless-grpc"}}},
    {"tag":"trojan-tcp","listen":"0.0.0.0","port":10005,"protocol":"trojan","settings":{"clients":[]},"streamSettings":{"network":"tcp","security":"tls","tlsSettings":{"certificates":[{"certificateFile":"${XRAY_CERT}","keyFile":"${XRAY_KEY}"}]}}},
    {"tag":"trojan-ws","listen":"0.0.0.0","port":8445,"protocol":"trojan","settings":{"clients":[]},"streamSettings":{"network":"ws","security":"tls","tlsSettings":{"certificates":[{"certificateFile":"${XRAY_CERT}","keyFile":"${XRAY_KEY}"}]},"wsSettings":{"path":"/trojan"}}},
    {"tag":"trojan-grpc","listen":"0.0.0.0","port":10007,"protocol":"trojan","settings":{"clients":[]},"streamSettings":{"network":"grpc","security":"tls","tlsSettings":{"certificates":[{"certificateFile":"${XRAY_CERT}","keyFile":"${XRAY_KEY}"}]},"grpcSettings":{"serviceName":"trojan-grpc"}}}
  ],
  "outbounds":[{"protocol":"freedom","tag":"direct"}]
}
XRAYEOF
  echo '{"protocol":"vmess","accounts":[]}' > /etc/xray/accounts/vmess.json
  echo '{"protocol":"vless","accounts":[]}' > /etc/xray/accounts/vless.json
  echo '{"protocol":"trojan","accounts":[]}' > /etc/xray/accounts/trojan.json

  # Validate the Xray configuration before creating/starting the service.
  xray run -test -config /etc/xray/config.json >/dev/null 2>&1

  # Always create our own systemd unit so the installer does not depend on
  # the upstream installer having created xray.service.
  XRAY_BIN="$(command -v xray)"
  if [ -z "$XRAY_BIN" ] || [ ! -x "$XRAY_BIN" ]; then
    echo "Xray binary not found" >&2
    exit 1
  fi
  cat > /etc/systemd/system/xray.service << XRAYSVC
[Unit]
Description=Xray Service
Documentation=https://github.com/XTLS/Xray-core
After=network.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=${XRAY_BIN} run -config /etc/xray/config.json
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
XRAYSVC

  systemctl daemon-reload
  systemctl unmask xray.service 2>/dev/null || true
  systemctl enable xray.service
  systemctl restart xray.service
  sleep 2

  # Do not continue to bot setup unless Xray is really running.
  if ! systemctl is-active --quiet xray.service; then
    echo "" >&2
    echo "❌ Xray gagal berjalan sebagai systemd service." >&2
    systemctl --no-pager --full status xray.service >&2 || true
    echo "--- journalctl xray.service ---" >&2
    journalctl -u xray.service -n 40 --no-pager >&2 || true
    exit 1
  fi
  systemctl is-enabled --quiet xray.service
) & spin $! "Install Core VPN"

# Restore SSH/WS/SSL services after certificate setup
( systemctl daemon-reload; systemctl enable ws-ssh ws-ssh-alt stunnel4 >/dev/null 2>&1; systemctl restart ws-ssh ws-ssh-alt stunnel4 ) & spin $! "Start SSH/SSL services"

# 5. BANNER
rm -rf /etc/update-motd.d/* 2>/dev/null
cat > /etc/issue.net << 'BANEOF'
<br><font color="#ff00aa"><b>                        ▬▬▬▬▬▬ஜ۩۞۩ஜ▬▬▬▬▬▬</b></font><br><font color="#ffffff"><b>                         --- 卐 </b></font><font color="#ffff00"><b>SANSXML VPN STORE</b></font><font color="#ffffff"><b> 卐 ---</b></font><br><font color="#ff00aa"><b>                        ▬▬▬▬▬▬ஜ۩۞۩ஜ▬▬▬▬▬▬</b></font><br><font color="#ffffff"><b>                              卍 TERM OF SERVICE 卐</b></font><br><font color="#ffffff"><b>                                  PREMIUM VPN</b></font><br><font color="#ffffff"><b>                                NO MULTI LOGIN !!</b></font><br><font color="#ffffff"><b>                           NO HACKING AND CARDING</b></font><br><font color="#ffff00"><b>                              👉 MULTI LOGIN BANNED 👈</b></font><br><font color="#ff00aa"><b>                        ▬▬▬▬▬▬ஜ۩۞۩ஜ▬▬▬▬▬▬</b></font><br><font color="#ffffff"><b>                   ORDER CONFIG PREMIUM: </b></font><font color="#00ff44"><b>wa.me/6289527419748</b></font><br><font color="#ffffff"><b>                         BOT ORDER VPN: </b></font><font color="#00ff44"><b>t.me/unokwn</b></font><br><br>
BANEOF
cp /etc/issue.net /etc/motd
sed -i '/^[[:space:]]*ListenAddress/d' /etc/ssh/sshd_config
mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/99-vpnbot.conf << 'SSHEOF'
Port 22
ListenAddress 0.0.0.0
ListenAddress ::
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
UsePAM yes
Banner /etc/issue.net
PrintMotd yes
ClientAliveInterval 15
ClientAliveCountMax 2
TCPKeepAlive yes
SSHEOF
systemctl restart ssh 2>/dev/null || systemctl restart sshd

# 6. BOT CONFIG
# Token Telegram sengaja dikosongkan saat instalasi.
# Token hanya diisi melalui menu [05] ADD TOKEN BOT.
BOT_TOKEN=""

GH_USER="Syahrul7y"; GH_REPO="Backup"
GH_EMAIL="hodamkecil@gmail.com"
GH_TOKEN="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"

cat > /etc/sansxml-backup.conf << GHCFG
GH_USER="${GH_USER}"
GH_REPO="${GH_REPO}"
GH_TOKEN="${GH_TOKEN}"
GH_EMAIL="${GH_EMAIL}"
GHCFG
chmod 600 /etc/sansxml-backup.conf

DOMAIN="sgivip.naaofficial.web.id"
ADMIN_ID="6144358600"

cat > /root/vpnbot_config.json << CFGEOF
{
  "bot_token": "${BOT_TOKEN}",
  "domain": "${DOMAIN}",
  "owner_ids": [${ADMIN_ID}],
  "servers": {
    "sg_1ip": {"name": "🇸🇬 PRIME SG-01", "city": "Singapore", "isp": "DigitalOcean LLC", "ssh_ovpn": "DIGITALOCEAN • PRIME SG-01", "domain": "${DOMAIN}", "price_day": 117, "price_month": 3510, "ip_limit": 1, "slot_max": 50, "quota_gb": 700},
    "sg_2ip": {"name": "🇸🇬 PRIME SG-02", "city": "Singapore", "isp": "DigitalOcean LLC", "ssh_ovpn": "DIGITALOCEAN • PRIME SG-02", "domain": "${DOMAIN}", "price_day": 167, "price_month": 5010, "ip_limit": 2, "slot_max": 50, "quota_gb": 800}
  },
  "ip_limit": 2,
  "block_hours": 2
}
CFGEOF

# 7. BOT.PY
echo ""
echo -e "  ${YELLOW}▸ Install Bot.py${NC}"

cat > /root/bot.py << 'BOTPYEOF'
#!/usr/bin/env python3
import re, io, json, os, logging, subprocess, asyncio, base64, random, string, socket, shutil, time, uuid
from datetime import datetime, timedelta
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, BotCommand, ReplyKeyboardRemove
from telegram.ext import Application, CommandHandler, CallbackQueryHandler, MessageHandler, filters

CONFIG_FILE = "/root/vpnbot_config.json"
def load_config():
    d = {"bot_token":"","domain":"","owner_ids":[6144358600],"servers":{},"ip_limit":2,"block_hours":2}
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE) as f: c = json.load(f)
            for k,v in d.items(): c.setdefault(k,v)
            return c
        except: pass
    return d
def save_config(c):
    with open(CONFIG_FILE,"w") as f: json.dump(c,f,indent=2,ensure_ascii=False)

CONFIG = load_config()
BOT_TOKEN = CONFIG["bot_token"]
ADMIN_IDS = [6144358600]
SSH_HOST = CONFIG["domain"]
SERVERS = CONFIG.get("servers", {})
IP_LIMIT = CONFIG["ip_limit"]
SSH_KEY_PATH = "/root/.ssh/id_bot"
HARI_MIN, HARI_MAX = 1, 30
TRIAL_DURATION_MIN = 30
TRIAL_PER_DAY = 2
MIN_TOPUP = 1000
BLOCK_FILE = "/root/vpnbot_blocked.json"
BLOCK_HOURS = 2
USERS_FILE="/root/vpnbot_users.json"; BAL_FILE="/root/vpnbot_balance.json"
ACCOUNTS_FILE="/root/vpnbot_accounts.json"; TRIAL_FILE="/root/vpnbot_trial.json"
TRX_FILE="/root/vpnbot_trx.json"
XRAY_CONFIG = "/etc/xray/config.json"
XRAY_PORTS = {"vmess_ws":10001,"vmess_tls":8443,"vmess_grpc":10002,"vless_ws":10003,"vless_tls":8444,"vless_grpc":10004,"trojan_tcp":10005,"trojan_ws":8445,"trojan_grpc":10007}

logging.basicConfig(format="%(asctime)s - %(levelname)s - %(message)s", level=logging.INFO,
    handlers=[logging.StreamHandler(), logging.FileHandler("/root/vpnbot.log", encoding="utf-8")])
logger = logging.getLogger(__name__)

def is_owner(uid): return uid in ADMIN_IDS
def rupiah(n): return f"Rp {int(n):,}".replace(",", ".")
def B(text, callback_data=None, url=None, style=None):
    kw = {"text": text}
    if callback_data is not None: kw["callback_data"] = callback_data
    if url is not None: kw["url"] = url
    if style: kw["api_kwargs"] = {"style": style}
    try: return InlineKeyboardButton(**kw)
    except: kw.pop("api_kwargs", None); return InlineKeyboardButton(**kw)

def load_json(p, d):
    if not os.path.exists(p): return d
    try:
        with open(p) as f: return json.load(f)
    except: return d
def save_json(p, d):
    with open(p,"w") as f: json.dump(d,f,indent=2,ensure_ascii=False)

def load_backup_conf():
    d = {"GH_USER":"","GH_REPO":"","GH_TOKEN":"","GH_EMAIL":""}
    if os.path.exists("/etc/sansxml-backup.conf"):
        with open("/etc/sansxml-backup.conf") as f:
            for line in f:
                for k in d.keys():
                    if line.startswith(k + "="):
                        d[k] = line.split("=",1)[1].strip().strip('"').strip()
    return d
def save_backup_conf(ghu,ghr,ght,ghe):
    with open("/etc/sansxml-backup.conf","w") as f:
        f.write(f'GH_USER="{ghu}"\nGH_REPO="{ghr}"\nGH_TOKEN="{ght}"\nGH_EMAIL="{ghe}"\n')
    try: os.chmod("/etc/sansxml-backup.conf",0o600)
    except: pass
def is_backup_ready():
    c = load_backup_conf()
    return all([c.get("GH_USER"),c.get("GH_REPO"),c.get("GH_TOKEN"),c.get("GH_EMAIL")])

def is_local_server(k):
    if k not in SERVERS: return True
    return (SERVERS[k].get("ssh_host") or "127.0.0.1").strip() in ("127.0.0.1","localhost","")
def is_server_complete(s):
    if not s: return False
    if not s.get("price_month") or int(s.get("price_month",0))<=0: return False
    if not s.get("ip_limit") or int(s.get("ip_limit",0))<=0: return False
    if not s.get("slot_max") or int(s.get("slot_max",0))<=0: return False
    if not s.get("domain") or not str(s.get("domain","")).strip(): return False
    return True
def get_active_servers(): return {k:v for k,v in SERVERS.items() if is_server_complete(v)}
def save_servers():
    cfg = load_config(); cfg["servers"] = SERVERS; save_config(cfg)
def get_price(hari, key=None):
    if key and key in SERVERS: s = SERVERS[key]
    else: s = list(SERVERS.values())[0] if SERVERS else {"price_day":117}
    return int(s.get("price_day",117) or 117) * int(hari)

def get_ssh_params(key=None):
    if key and key in SERVERS:
        s = SERVERS[key]
        return (s.get("ssh_host") or "127.0.0.1", int(s.get("ssh_port",22)),
                s.get("ssh_user") or "root", s.get("ssh_key") or SSH_KEY_PATH)
    return "127.0.0.1", 22, "root", SSH_KEY_PATH
def ssh_run(cmd, key=None, timeout=30):
    host, port, user, kf = get_ssh_params(key)
    full = ["ssh","-i",kf,"-o","StrictHostKeyChecking=no","-o","UserKnownHostsFile=/dev/null",
            "-o","ConnectTimeout=10","-o","BatchMode=yes","-o","PubkeyAuthentication=yes",
            "-o","PasswordAuthentication=no","-o","LogLevel=ERROR","-p",str(port),f"{user}@{host}",cmd]
    try:
        r = subprocess.run(full, capture_output=True, text=True, timeout=timeout)
        return r.returncode, r.stdout.strip(), r.stderr.strip()
    except subprocess.TimeoutExpired: return -1,"","Timeout"
    except Exception as e: return -2,"",str(e)

def gen_ssh_key(name):
    os.makedirs("/root/.ssh", exist_ok=True)
    kp = f"/root/.ssh/id_{name}"
    if not os.path.exists(kp):
        subprocess.run(["ssh-keygen","-t","ed25519","-f",kp,"-N","","-q"], capture_output=True, timeout=10)
    pub = kp + ".pub"
    return kp, (open(pub).read().strip() if os.path.exists(pub) else "")
def test_ssh_key(kf, ip, port):
    try:
        r = subprocess.run(["ssh","-i",kf,"-o","StrictHostKeyChecking=no",
            "-o","UserKnownHostsFile=/dev/null","-o","ConnectTimeout=8","-o","BatchMode=yes",
            "-o","PasswordAuthentication=no","-o","LogLevel=ERROR","-p",str(port),
            f"root@{ip}","echo PING_OK"], capture_output=True, text=True, timeout=12)
        return "PING_OK" in r.stdout
    except: return False

def get_bandwidth_gb(key=None):
    try:
        code, out, _ = ssh_run("vnstat --json m 1 2>/dev/null", key, timeout=6)
        if code == 0 and out.strip():
            data = json.loads(out); ifs = data.get("interfaces",[])
            if ifs:
                months = ifs[0].get("traffic",{}).get("month",[])
                if months: return (months[-1].get("rx",0)+months[-1].get("tx",0))/(1024**3)
    except: pass
    return 0.0
def get_vps_detail(key=None):
    d = {}
    def run(cmd):
        c,o,e = ssh_run(cmd,key,timeout=6)
        return o if c==0 else ""
    d["os"] = run("grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '\"'") or "-"
    d["kernel"] = run("uname -r") or "-"
    d["cpu"] = (run("grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs") or "-")[:45]
    d["cores"] = run("nproc") or "-"
    meminfo = run("cat /proc/meminfo")
    try:
        mem = {}
        for line in meminfo.splitlines():
            if ":" in line:
                k,v = line.split(":",1); mem[k.strip()] = v.strip()
        tk = int(mem["MemTotal"].split()[0]); ak = int(mem["MemAvailable"].split()[0])
        d["ram_total"] = f"{tk/1024/1024:.1f} GB"; d["ram_used"] = f"{(tk-ak)/1024/1024:.1f} GB"
        d["ram_pct"] = f"{((tk-ak)/tk*100):.0f}%"
    except: d["ram_total"]="-"; d["ram_used"]="-"; d["ram_pct"]="-"
    df = run("df -h / | tail -1").split()
    if len(df)>=5: d["disk_total"],d["disk_used"],d["disk_pct"] = df[1],df[2],df[4]
    else: d["disk_total"]="-"; d["disk_used"]="-"; d["disk_pct"]="-"
    up = run("cat /proc/uptime")
    try:
        s = float(up.split()[0]); d["uptime"] = f"{int(s//86400)}d {int((s%86400)//3600)}h {int((s%3600)//60)}m"
    except: d["uptime"] = "-"
    d["load"] = (run("cat /proc/loadavg").split()[:3]) or ["-","-","-"]
    d["ip"] = run("hostname -I | awk '{print $1}'") or "-"
    d["bw"] = get_bandwidth_gb(key)
    return d

# XRAY
def xray_exists(): return os.path.exists("/usr/local/bin/xray") or shutil.which("xray")
def xray_load_cfg():
    if not os.path.exists(XRAY_CONFIG): return None
    try:
        with open(XRAY_CONFIG) as f: return json.load(f)
    except: return None
def xray_save_cfg(c):
    with open(XRAY_CONFIG,"w") as f: json.dump(c,f,indent=2)
def xray_reload():
    try: subprocess.run("systemctl restart xray", shell=True, timeout=20)
    except: pass
def xray_add_user(proto, cred):
    cfg = xray_load_cfg()
    if not cfg: return False,"Config Xray tidak ada"
    client = None
    if proto == "vmess": client = {"id":cred,"alterId":0}
    elif proto == "vless": client = {"id":cred,"flow":""}
    elif proto == "trojan": client = {"password":cred}
    if not client: return False,"Proto tidak valid"
    for ib in cfg.get("inbounds",[]):
        if ib.get("tag","").startswith(proto):
            ib.setdefault("settings",{}).setdefault("clients",[]).append(client)
    xray_save_cfg(cfg); xray_reload()
    return True,"OK"
def xray_del_user(proto, cred):
    cfg = xray_load_cfg()
    if not cfg: return False
    for ib in cfg.get("inbounds",[]):
        if not ib.get("tag","").startswith(proto): continue
        clients = ib.get("settings",{}).get("clients",[])
        if proto == "trojan": clients = [c for c in clients if c.get("password") != cred]
        else: clients = [c for c in clients if c.get("id") != cred]
        ib["settings"]["clients"] = clients
    xray_save_cfg(cfg); xray_reload()
    return True
def xray_build_vmess(host, port, u, path, tls, remark):
    cfg = {"v":"2","ps":remark,"add":host,"port":str(port),"id":u,"aid":"0","scy":"auto",
           "net":"ws","type":"none","host":host,"path":path,
           "tls":"tls" if tls else "","sni":host if tls else ""}
    return "vmess://" + base64.b64encode(json.dumps(cfg).encode()).decode()
def xray_build_vmess_grpc(host, u, svc, remark):
    cfg = {"v":"2","ps":remark,"add":host,"port":str(XRAY_PORTS["vmess_grpc"]),"id":u,"aid":"0","scy":"auto",
           "net":"grpc","type":"gun","host":host,"path":svc,"tls":"tls","sni":host}
    return "vmess://" + base64.b64encode(json.dumps(cfg).encode()).decode()
def xray_build_vless(host, port, u, path, tls, remark):
    p = f"encryption=none&security={'tls' if tls else 'none'}&type=ws&host={host}&path={path}"
    if tls: p += f"&sni={host}"
    return f"vless://{u}@{host}:{port}?{p}#{remark}"
def xray_build_vless_grpc(host, u, svc, remark):
    p = f"encryption=none&security=tls&type=grpc&serviceName={svc}&sni={host}"
    return f"vless://{u}@{host}:443?{p}#{remark}"
def xray_build_trojan(host, port, pwd, path, tls, remark):
    p = f"security={'tls' if tls else 'none'}&type={'ws' if path else 'tcp'}"
    if path: p += f"&host={host}&path={path}"
    if tls: p += f"&sni={host}"
    return f"trojan://{pwd}@{host}:{port}?{p}#{remark}"
def xray_build_trojan_grpc(host, pwd, svc, remark):
    p = f"security=tls&type=grpc&serviceName={svc}&sni={host}"
    return f"trojan://{pwd}@{host}:{XRAY_PORTS['trojan_grpc']}?{p}#{remark}"

# SSH
def ssh_create(u, p, days, is_trial=False, key="sg_1ip"):
    now = datetime.now()
    if is_trial:
        exp_date = now.date(); exp_ts = (now + timedelta(minutes=TRIAL_DURATION_MIN)).strftime("%Y-%m-%d %H:%M:%S")
    else:
        exp_date = (now + timedelta(days=days)).date(); exp_ts = exp_date.strftime("%Y-%m-%d") + " 23:59:59"
    exp = exp_date.strftime("%Y-%m-%d")
    pw_b64 = base64.b64encode(p.encode()).decode()
    expiry_cmd = f"chage -E '{exp}' {u} 2>&1 ;" if not is_trial else ""
    cmd = (f"userdel -r {u} 2>/dev/null; useradd -m -s /bin/bash {u} 2>&1 ; "
           f"{expiry_cmd} chage -M 99999 {u} 2>&1 ; chage -I -1 {u} 2>&1 ; "
           f"PW=$(echo '{pw_b64}' | base64 -d) ; printf '%s:%s\\n' '{u}' \"$PW\" | chpasswd 2>&1 ; "
           f"passwd -u {u} 2>&1 ; usermod -U {u} 2>&1 ; echo DONE:$?")
    c,o,e = ssh_run(cmd, key)
    return {"ok":True,"username":u,"password":p,"exp":exp,"exp_ts":exp_ts,"manual":("DONE:0" not in o)}
def ssh_extend(u, ne, key="sg_1ip"):
    c,o,e = ssh_run(f"chage -E '{ne}' {u} 2>&1 ; echo DONE:$?", key)
    return "DONE:0" in o
def ssh_delete(u, key="sg_1ip"):
    ssh_run(f"pkill -9 -u {u} 2>/dev/null; userdel -r {u} 2>&1; echo OK", key, timeout=20)
    return True
def ssh_test(key="sg_1ip"):
    c,o,e = ssh_run("echo PING_OK", key, timeout=10)
    return ("PING_OK" in o, "SSH OK" if "PING_OK" in o else f"SSH gagal: {e or o}")

def valid_username(s): return bool(re.match(r'^[a-zA-Z0-9_]{5,20}$', s or ""))
def valid_password(s):
    if not s or len(s)<5 or len(s)>32: return False
    return all(c in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*_.-" for c in s)

def get_active_sessions(u, key="sg_1ip"):
    try:
        c,o,_ = ssh_run("who", key, timeout=5)
        if c != 0: return []
        return [l for l in o.splitlines() if l.split() and l.split()[0] == u]
    except: return []
def count_live_shells(u, key="sg_1ip"):
    try:
        c,o,_ = ssh_run(f"ps -u {u} -o comm=", key, timeout=5)
        if c != 0: return 0
        procs = [p.strip() for p in o.splitlines() if p.strip()]
        sh = ("bash","sh","zsh","ksh","dash","csh","tcsh")
        return sum(1 for p in procs if p.lstrip("-") in sh)
    except: return 0
def check_second(u, key="sg_1ip"):
    sess = get_active_sessions(u, key); n = len(sess)
    if n<=1: return False,sess,n
    sh = count_live_shells(u, key)
    if sh>1: return True,sess,sh
    return False,sess,sh if sh>0 else n
def block_user(u, h=2, key="sg_1ip"):
    try:
        ssh_run(f"passwd -l {u}", key, timeout=10)
        ssh_run(f"pkill -9 -u {u}", key, timeout=10)
        d = load_json(BLOCK_FILE, {})
        d[u] = {"blocked_at":datetime.now().isoformat(),
                "unblock_at":(datetime.now()+timedelta(hours=h)).strftime("%Y-%m-%d %H:%M:%S")}
        save_json(BLOCK_FILE, d); return True
    except: return False
def unblock_user(u, key="sg_1ip"):
    try:
        ssh_run(f"passwd -u {u}", key, timeout=10)
        d = load_json(BLOCK_FILE,{})
        if u in d: d.pop(u); save_json(BLOCK_FILE,d)
        return True
    except: return False
def get_block_info(u): return load_json(BLOCK_FILE,{}).get(u)

def get_bal(uid): return load_json(BAL_FILE,{}).get(str(uid),0)
def add_bal(uid, amt):
    d = load_json(BAL_FILE,{}); d[str(uid)] = d.get(str(uid),0)+int(amt); save_json(BAL_FILE,d); return d[str(uid)]
def reduce_bal(uid, amt):
    d = load_json(BAL_FILE,{}); c = d.get(str(uid),0)
    if c<amt: return False,c
    d[str(uid)] = c-amt; save_json(BAL_FILE,d); return True,d[str(uid)]
def get_acc(u): return load_json(ACCOUNTS_FILE,{}).get(u)
def get_user_accs(uid):
    out = []
    for k,v in load_json(ACCOUNTS_FILE,{}).items():
        if v.get("user_id") == uid:
            v["_key"] = k
            out.append(v)
    return out
def save_acc(u, d):
    dd = load_json(ACCOUNTS_FILE,{}); dd[u]=d; save_json(ACCOUNTS_FILE,dd)
def is_username_taken(u): return u.lower() in [k.lower() for k in load_json(ACCOUNTS_FILE,{}).keys()]
def count_accounts(): return len(load_json(ACCOUNTS_FILE,{}))
def delete_acc_json(u):
    dd = load_json(ACCOUNTS_FILE,{})
    if u in dd: d = dd.pop(u); save_json(ACCOUNTS_FILE,dd); return d
    return None
def count_slots(key):
    accs = load_json(ACCOUNTS_FILE,{}); today = datetime.now().date(); c = 0
    for a in accs.values():
        if a.get("server_key") != key: continue
        try:
            ed = datetime.strptime(a["exp"], "%Y-%m-%d").date()
            if (ed-today).days >= 0: c += 1
        except: pass
    return c
def get_slot_info(key):
    s = SERVERS.get(key,{})
    return count_slots(key), int(s.get("slot_max",50) or 50)
def trial_left(uid):
    d = load_json(TRIAL_FILE,{}); t = datetime.now().strftime("%Y-%m-%d")
    u = d.get(str(uid),{})
    if u.get("date") != t: return TRIAL_PER_DAY
    return max(0, TRIAL_PER_DAY - u.get("used",0))
def use_trial(uid):
    d = load_json(TRIAL_FILE,{}); t = datetime.now().strftime("%Y-%m-%d")
    u = d.get(str(uid),{})
    if u.get("date") != t: u = {"date":t,"used":0}
    u["used"] = u.get("used",0)+1; d[str(uid)] = u; save_json(TRIAL_FILE,d)
def track_user(u):
    d = load_json(USERS_FILE,{})
    d[str(u.id)] = {"first_name":u.first_name or "","username":u.username or "","last_seen":datetime.now().isoformat()}
    save_json(USERS_FILE,d)
def add_trx(uid,name,un,tipe,jumlah,ket=""):
    d = load_json(TRX_FILE,[])
    d.append({"user_id":uid,"name":name,"username":un,"tipe":tipe,"jumlah":int(jumlah),"ket":ket,"waktu":datetime.now().isoformat()})
    save_json(TRX_FILE,d)
def get_stats(uid=None):
    d = load_json(TRX_FILE,[])
    if uid: d = [t for t in d if t["user_id"]==uid]
    week = (datetime.now()-timedelta(days=7)).strftime("%Y-%m-%d"); month = datetime.now().strftime("%Y-%m")
    return {"minggu":sum(1 for t in d if t["waktu"][:10]>=week and t["tipe"]=="buat_akun"),
            "bulan":sum(1 for t in d if t["waktu"].startswith(month) and t["tipe"]=="buat_akun"),
            "total":sum(1 for t in d if t["tipe"]=="buat_akun")}
def get_income():
    d = load_json(TRX_FILE,[])
    today = datetime.now().strftime("%Y-%m-%d"); week = (datetime.now()-timedelta(days=7)).strftime("%Y-%m-%d"); month = datetime.now().strftime("%Y-%m")
    return {"hari":sum(t["jumlah"] for t in d if t["waktu"].startswith(today) and t["tipe"]=="buat_akun"),
            "minggu":sum(t["jumlah"] for t in d if t["waktu"][:10]>=week and t["tipe"]=="buat_akun"),
            "bulan":sum(t["jumlah"] for t in d if t["waktu"].startswith(month) and t["tipe"]=="buat_akun"),
            "total":sum(t["jumlah"] for t in d if t["tipe"]=="buat_akun")}
def hitung_refund(a):
    try:
        if a.get("is_trial"): return 0
        hg = int(a.get("harga",0)); th = int(a.get("days",30))
        if hg<=0 or th<=0: return 0
        exp = datetime.strptime(a["exp"],"%Y-%m-%d").date(); sisa = (exp - datetime.now().date()).days
        if sisa<=0: return 0
        return max(0,min(int(round((hg/th)*sisa)),hg))
    except: return 0
def count_users_by_period():
    d = load_json(USERS_FILE,{})
    today = datetime.now().strftime("%Y-%m-%d"); week = (datetime.now()-timedelta(days=7)).strftime("%Y-%m-%d"); month = datetime.now().strftime("%Y-%m")
    return {"hari":sum(1 for u in d.values() if u.get("last_seen","")[:10]==today),
            "minggu":sum(1 for u in d.values() if u.get("last_seen","")[:10]>=week),
            "bulan":sum(1 for u in d.values() if u.get("last_seen","")[:7]==month),
            "total":len(d)}
def get_server_status():
    r = []
    for k,s in SERVERS.items():
        used = count_slots(k); mx = int(s.get("slot_max",50) or 50)
        stat = "🟢 Online" if max(0,mx-used)>0 else "🔴 Full"
        r.append({"name":s.get("name","-"),"used":used,"max":mx,"status":stat,
                  "quota":int(s.get("quota_gb",700) or 700),"bw":get_bandwidth_gb(k),
                  "key":k,"complete":is_server_complete(s)})
    return r

def backup_config_text():
    c = load_backup_conf(); g = c.get("GH_TOKEN","") or ""
    t = f"{g[:4]}{'*'*(len(g)-8)}{g[-4:]}" if len(g)>12 else ("*"*len(g) if g else "(kosong)")
    st = "✅ Aktif" if is_backup_ready() else "❌ Belum diisi"
    return "\n".join(["<blockquote>","🔄 <b>PENGATURAN BACKUP GITHUB</b>","───────────────────────",
             f"├ Status   : <b>{st}</b>",f"├ Username : <code>{c.get('GH_USER','-')}</code>",
             f"├ Repo     : <code>{c.get('GH_REPO','-')}</code>",
             f"├ Email    : <code>{c.get('GH_EMAIL','-')}</code>",
             f"╰ Token    : <code>{t}</code>","───────────────────────",
             "🔄 <i>Backup otomatis tiap 5 menit.</i>","</blockquote>"])

def sync_push_now():
    if not is_backup_ready(): return False,"Backup belum siap"
    try:
        sp = "/root/vpnbot_backup.sh"
        if not os.path.exists(sp): return False,"No script"
        r = subprocess.run(["bash",sp],capture_output=True,text=True,timeout=45)
        return r.returncode==0,(r.stderr or r.stdout or "")[:200]
    except Exception as e: return False,str(e)[:200]
async def sync_push_async():
    try: await asyncio.to_thread(sync_push_now)
    except: pass

def _write_backup_sh():
    with open("/root/vpnbot_backup.sh","w") as f:
        f.write('''#!/bin/bash
source /etc/sansxml-backup.conf 2>/dev/null
cd /root/vpnbot_backup || exit 1
for f in vpnbot_users.json vpnbot_balance.json vpnbot_accounts.json vpnbot_trial.json vpnbot_trx.json vpnbot_blocked.json vpnbot_config.json bot.py; do
    [ -f "/root/$f" ] && cp "/root/$f" "./$f"
done
git add -A
if ! git diff --cached --quiet; then
    git -c user.email="$GH_EMAIL" -c user.name="$GH_USER" commit -m "Auto backup: $(date)" -q
    git push "https://${GH_USER}:${GH_TOKEN}@github.com/${GH_USER}/${GH_REPO}.git" HEAD:main -q 2>/dev/null || {
        git pull --no-rebase -X ours "https://${GH_USER}:${GH_TOKEN}@github.com/${GH_USER}/${GH_REPO}.git" main -q 2>/dev/null
        git push "https://${GH_USER}:${GH_TOKEN}@github.com/${GH_USER}/${GH_REPO}.git" HEAD:main -q 2>/dev/null
    }
fi
''')
    os.chmod("/root/vpnbot_backup.sh",0o755)
def setup_backup_env(ghu,ghr,ght,ghe):
    try:
        bdir = "/root/vpnbot_backup"; os.makedirs(bdir,exist_ok=True)
        if not os.path.exists(f"{bdir}/.git"): subprocess.run(["git","init","-q"],cwd=bdir,capture_output=True)
        subprocess.run(["git","config","user.email",ghe],cwd=bdir,capture_output=True)
        subprocess.run(["git","config","user.name",ghu],cwd=bdir,capture_output=True)
        subprocess.run(["git","branch","-M","main"],cwd=bdir,capture_output=True)
        remote = f"https://{ghu}:{ght}@github.com/{ghu}/{ghr}.git"
        subprocess.run(["git","remote","remove","origin"],cwd=bdir,capture_output=True)
        subprocess.run(["git","remote","add","origin",remote],cwd=bdir,capture_output=True)
        for br in ["main","master"]:
            r = subprocess.run(["git","pull","origin",br,"--allow-unrelated-histories","--no-rebase","-X","ours"],
                cwd=bdir,capture_output=True,text=True,timeout=30)
            if r.returncode==0: break
        restored = 0
        for f in ["vpnbot_users.json","vpnbot_balance.json","vpnbot_accounts.json",
                  "vpnbot_trial.json","vpnbot_trx.json","vpnbot_blocked.json"]:
            src = f"{bdir}/{f}"
            if os.path.exists(src) and os.path.getsize(src)>2:
                with open(src) as ff: c = ff.read().strip()
                if c and c not in ("{}","[]"):
                    with open(f"/root/{f}","w") as ff: ff.write(c)
                    restored += 1
        _write_backup_sh()
        subprocess.run("crontab -l 2>/dev/null | grep -v vpnbot_backup.sh | crontab -",shell=True)
        subprocess.run('( crontab -l 2>/dev/null; echo "*/5 * * * * /root/vpnbot_backup.sh >/dev/null 2>&1" ) | crontab -',shell=True)
        subprocess.run(["bash","/root/vpnbot_backup.sh"],capture_output=True,timeout=60)
        return True,restored
    except Exception as e: return False,str(e)

def restore_ssh_users():
    accs = load_json(ACCOUNTS_FILE,{}); today = datetime.now().date(); c = 0; s = 0
    for un,a in accs.items():
        if a.get("proto") in ("vmess","vless","trojan"): continue
        try: exp = datetime.strptime(a["exp"],"%Y-%m-%d").date()
        except: s += 1; continue
        if (exp-today).days<0: s += 1; continue
        pw = a.get("password","")
        if not pw: s += 1; continue
        sk = a.get("server_key","sg_1ip")
        pw_b64 = base64.b64encode(pw.encode()).decode()
        cmd = (f"userdel -r {un} 2>/dev/null; useradd -m -s /bin/bash {un} 2>&1 ; "
               f"chage -E '{a['exp']}' {un} 2>&1 ; chage -M 99999 {un} 2>&1 ; chage -I -1 {un} 2>&1 ; "
               f"PW=$(echo '{pw_b64}' | base64 -d) ; printf '%s:%s\\n' '{un}' \"$PW\" | chpasswd 2>&1 ; "
               f"passwd -u {un} 2>&1 ; usermod -U {un} 2>&1")
        ssh_run(cmd,sk); c += 1
    return c,s

def wipe_local():
    d = {"json":0,"users":0,"folder":False}
    for f in ["vpnbot_users.json","vpnbot_balance.json","vpnbot_accounts.json",
              "vpnbot_trial.json","vpnbot_trx.json","vpnbot_blocked.json"]:
        p = f"/root/{f}"
        if os.path.exists(p):
            try: os.remove(p); d["json"] += 1
            except: pass
    for k in SERVERS.keys():
        try:
            c,o,_ = ssh_run("awk -F: '$3>=1000 && $3<60000 {print $1}' /etc/passwd",k,timeout=10)
            if c==0:
                for un in o.split():
                    try:
                        ssh_run(f"pkill -9 -u {un} 2>/dev/null; userdel -r {un} 2>/dev/null",k,timeout=15)
                        d["users"] += 1
                    except: pass
        except: pass
    if os.path.exists("/root/vpnbot_backup"):
        try: shutil.rmtree("/root/vpnbot_backup"); d["folder"] = True
        except: pass
    if os.path.exists("/root/vpnbot_backup.sh"):
        try: os.remove("/root/vpnbot_backup.sh")
        except: pass
    subprocess.run("crontab -l 2>/dev/null | grep -v vpnbot_backup.sh | crontab -",shell=True)
    return d
def reset_backup(keep=True):
    r = {"github":False,"local":{},"ts":time.strftime("%Y%m%d_%H%M%S"),"gh_error":""}
    try:
        c = load_backup_conf()
        ghu = c.get("GH_USER",""); ghr = c.get("GH_REPO","")
        ght = c.get("GH_TOKEN",""); ghe = c.get("GH_EMAIL","bot@local")
        if ghu and ghr and ght:
            remote = f"https://{ghu}:{ght}@github.com/{ghu}/{ghr}.git"
            tmp = f"/tmp/vpnbot_wipe_{r['ts']}"
            shutil.rmtree(tmp,ignore_errors=True); os.makedirs(tmp,exist_ok=True)
            try:
                subprocess.run(["git","init","-q"],cwd=tmp,capture_output=True)
                subprocess.run(["git","config","user.email",ghe],cwd=tmp,capture_output=True)
                subprocess.run(["git","config","user.name",ghu],cwd=tmp,capture_output=True)
                subprocess.run(["git","checkout","--orphan","main"],cwd=tmp,capture_output=True)
                with open(f"{tmp}/README.md","w") as f: f.write(f"# VPN Backup\nReset {r['ts']}\n")
                subprocess.run(["git","add","-A"],cwd=tmp,capture_output=True)
                subprocess.run(["git","-c",f"user.email={ghe}","-c",f"user.name={ghu}",
                    "commit","-m",f"RESTORE {r['ts']}"],cwd=tmp,capture_output=True)
                subprocess.run(["git","remote","add","origin",remote],cwd=tmp,capture_output=True)
                pushed = False; err = ""
                for br in ["main","master"]:
                    subprocess.run(["git","branch","-M",br],cwd=tmp,capture_output=True)
                    rr = subprocess.run(["git","push","-f","origin",br],cwd=tmp,capture_output=True,text=True,timeout=45)
                    err = (rr.stderr or rr.stdout or "").strip()
                    if rr.returncode==0: pushed=True; break
                r["github"] = pushed
                if not pushed: r["gh_error"] = err.replace(ght,"***")[:300]
            finally: shutil.rmtree(tmp,ignore_errors=True)
        r["local"] = wipe_local()
        if not keep and os.path.exists("/etc/sansxml-backup.conf"):
            try: os.remove("/etc/sansxml-backup.conf")
            except: pass
        if r["github"] and ghu and ghr and ght:
            try: setup_backup_env(ghu,ghr,ght,ghe)
            except: pass
        return True,r
    except Exception as e: return False,{"error":str(e)[:200]}

# KEYBOARDS
def kb_dash(uid):
    rows = [[B("➕  BUAT AKUN","buat_akun",style="primary"),B("⌛  TRIAL AKUN","trial_akun",style="primary")],
        [B("🔄 PERPANJANG AKUN","perpanjang_akun",style="primary")],
        [B("💰 TOPUP SALDO","isi_saldo",style="primary"),B("👤 AKUN SAYA","my_accs",style="primary")],
        [B("♻️ REFRESH","refresh",style="primary")]]
    if is_owner(uid): rows.append([B("💻 PENGATURAN","admin|menu",style="danger")])
    return InlineKeyboardMarkup(rows)
def kb_saldo():
    return InlineKeyboardMarkup([
        [B("1","saldo_num|1",style="primary"),B("2","saldo_num|2",style="primary"),B("3","saldo_num|3",style="primary")],
        [B("4","saldo_num|4",style="primary"),B("5","saldo_num|5",style="primary"),B("6","saldo_num|6",style="primary")],
        [B("7","saldo_num|7",style="primary"),B("8","saldo_num|8",style="primary"),B("9","saldo_num|9",style="primary")],
        [B("⬅️ Hapus","saldo_hapus",style="danger"),B("0","saldo_num|0",style="primary"),B("✅ Konfirmasi","saldo_konfirmasi",style="success")],
        [B("🔙 Kembali","menu|main",style="danger")]])
def kb_layanan():
    return InlineKeyboardMarkup([
        [B("➕ SSH OVPN","pilih|ssh",style="primary")],
        [B("➕ VMESS","pilih|vmess",style="primary"),B("➕ VLESS","pilih|vless",style="primary")],
        [B("➕ TROJAN","pilih|trojan",style="primary")],
        [B("🔙 KEMBALI","menu|main",style="danger")]])
def kb_srv_ssh():
    a = get_active_servers(); r = []; ks = list(a.keys())
    for i in range(0,len(ks),2):
        row = []
        for j in range(i,min(i+2,len(ks))):
            k = ks[j]; row.append(B(a[k]['name'],f"buat|{k}",style="primary"))
        r.append(row)
    if not r: r.append([B("⚠️ Belum ada server","noop",style="danger")])
    r.append([B("🔙 KEMBALI","pilih_layanan",style="danger")])
    return InlineKeyboardMarkup(r)
def kb_srv_lock():
    a = get_active_servers(); r = []; ks = list(a.keys())
    for i in range(0,len(ks),2):
        row = []
        for j in range(i,min(i+2,len(ks))):
            k = ks[j]; row.append(B(a[k]['name'],"ssh_locked",style="primary"))
        r.append(row)
    r.append([B("🔙 KEMBALI","ssh_locked",style="danger")])
    return InlineKeyboardMarkup(r)
def kb_srv_ext():
    a = get_active_servers(); r = []; ks = list(a.keys())
    for i in range(0,len(ks),2):
        row = []
        for j in range(i,min(i+2,len(ks))):
            k = ks[j]; row.append(B(a[k]['name'],f"extend|{k}",style="primary"))
        r.append(row)
    r.append([B("🔙 KEMBALI","menu|main",style="danger")])
    return InlineKeyboardMarkup(r)
def kb_xray_srv(proto):
    a = get_active_servers(); r = []; ks = list(a.keys())
    for i in range(0,len(ks),2):
        row = []
        for j in range(i,min(i+2,len(ks))):
            k = ks[j]; row.append(B(a[k]['name'],f"buat{proto}|{k}",style="primary"))
        r.append(row)
    if not r: r.append([B("⚠️ Belum ada server","noop",style="danger")])
    r.append([B("🔙 KEMBALI","pilih_layanan",style="danger")])
    return InlineKeyboardMarkup(r)
def kb_admin():
    return InlineKeyboardMarkup([
        [B("💻 Kelola VPN","admin|srv",style="primary"),B("👤 Pengguna","admin|users|0",style="primary")],
        [B("📢 Broadcast","admin|bc",style="primary"),B("🔄 Backup GitHub","admin|backup",style="primary")],
        [B("💻 VPS","admin|vps",style="primary")],
        [B("🔙 Kembali","menu|main",style="danger")]])
def kb_backup():
    return InlineKeyboardMarkup([
        [B("👤 Ganti Username","backup_edit|user",style="primary"),B("📁 Ganti Repo","backup_edit|repo",style="primary")],
        [B("🔑 Ganti Token","backup_edit|token",style="primary"),B("📧 Ganti Email","backup_edit|email",style="primary")],
        [B("📊 Restore Data","backup_reset",style="danger")],
        [B("🔙 Kembali","admin|menu",style="danger")]])
def kb_acc_det(un):
    return InlineKeyboardMarkup([[B("🗑️ Hapus",f"del_acc|{un}",style="danger")],[B("🔙 Kembali","my_accs",style="danger")]])
def kb_soon(p): return InlineKeyboardMarkup([[B("🔙 KEMBALI","pilih_layanan",style="danger")]])

# TEXT BUILDERS
def dash_text(user, uid):
    un = f"@{user.username}" if user.username else "-"
    role = "Owner" if is_owner(uid) else "Member"
    st = get_stats(uid); tu = len(load_json(USERS_FILE,{}))
    lines = ["<blockquote>","💻 <b>SANSXML VPN STORE</b>","───────────────────────","👤 <b>Profil</b>"]
    lines += [f"├ User Telegram  : {un}",f"├ Chat ID        : <code>{uid}</code>",
              f"├ Keanggotaan    : {role}",f"├ Total Pengguna : <b>{tu}</b>",
              f"╰ 💰 Saldo VPN  : <b>{rupiah(get_bal(uid))}</b>","","🌍 <b>Info Global</b>",
              f"├ Minggu Ini     : <b>{st['minggu']} Akun</b>",f"├ Bulan Ini      : <b>{st['bulan']} Akun</b>",
              f"╰ Keseluruhan    : <b>{st['total']} Akun</b>","","🌐 <b>Informasi</b>",
              f"├ Server Tersedia : <b>{len(get_active_servers())} Server</b>",
              f"╰ Kuota Trial     : <b>{trial_left(uid)}x Hari</b>","","───────────────────────","</blockquote>"]
    return "\n".join(lines)
def pilih_layanan_text():
    return "<blockquote>\n💻 <b>PILIH LAYANAN VPN</b>\n───────────────────────\nSilakan pilih protokol:\n───────────────────────\n</blockquote>"
def ssh_server_text():
    a = get_active_servers()
    if not a: return "<blockquote>⚠️ <b>Belum ada server</b></blockquote>"
    lines = ["<blockquote>","<b>💻 SSH OVPN</b>","─────────────────────────",""]
    for k,s in a.items():
        used,mx = get_slot_info(k); cek = "✅" if max(0,mx-used)>0 else "❌"
        lines += [f"◆ {s['name']}",f"├ Harga Harian   : <b>{rupiah(s.get('price_day',0))}</b>",
                  f"├ Harga Bulanan  : <b>{rupiah(s.get('price_month',0))}</b>",
                  f"├ Qouta          : <b>{s.get('quota_gb',700)} GB</b>",f"├ Limit IP       : {s.get('ip_limit',1)} IP",
                  f"╰ Slot Tersedia  : <b>{used}/{mx} {cek}</b>","",""]
    lines += ["─────────────────────────","</blockquote>"]
    return "\n".join(lines)
def xray_server_text(proto):
    a = get_active_servers()
    if not a: return "<blockquote>⚠️ <b>Belum ada server</b></blockquote>"
    t = {"vmess":"VMESS","vless":"VLESS","trojan":"TROJAN"}.get(proto,proto.upper())
    lines = ["<blockquote>",f"<b>💻 {t}</b>","─────────────────────────",""]
    for k,s in a.items():
        used,mx = get_slot_info(k); cek = "✅" if max(0,mx-used)>0 else "❌"
        lines += [f"◆ {s['name']}",f"├ Harga Harian  : <b>{rupiah(s.get('price_day',0))}</b>",
                  f"├ Harga Bulanan : <b>{rupiah(s.get('price_month',0))}</b>",
                  f"├ Limit IP      : {s.get('ip_limit',1)} IP",f"╰ Slot Tersedia : <b>{used}/{mx} {cek}</b>","",""]
    lines += ["─────────────────────────","</blockquote>"]
    return "\n".join(lines)
def saldo_text(uid, nom=""):
    return (f"<blockquote>💰 <b>Silakan masukkan jumlah nominal topup saldo yang Anda inginkan:</b>\n\n"
            f"Jumlah saat ini: <b>{rupiah(get_bal(uid))}</b>\n\n"
            f"Nominal input: <b>{rupiah(nom) if nom else 'Rp 0'}</b>\n"
            f"Minimal topup {rupiah(MIN_TOPUP)}\n\n"
            f"❖ <i>Saldo dapat digunakan untuk membuat akun VPN</i> ❖\n</blockquote>")

def acc_caption(u, p, exp, dl, ip, manual=False, is_trial=False, server_key="sg_1ip", exp_ts="", created_at=""):
    srv = SERVERS.get(server_key, {})
    head = "TRIAL" if is_trial else ("MANUAL" if manual else "PREMIUM")
    BULAN = ["Jan","Feb","Mar","Apr","Mei","Jun","Jul","Agu","Sep","Okt","Nov","Des"]
    try:
        ed = datetime.strptime(exp,"%Y-%m-%d")
        exp_fmt = f"{ed.day} {BULAN[ed.month-1]}, {ed.year}"
        try:
            cr = datetime.fromisoformat(created_at) if created_at else datetime.now()
        except:
            cr = datetime.now()
        created_fmt = f"{cr.day} {BULAN[cr.month-1]}, {cr.year}" + (f" {cr:%H:%M}" if is_trial else "")
        if is_trial and exp_ts:
            try:
                et = datetime.strptime(exp_ts, "%Y-%m-%d %H:%M:%S")
                exp_fmt = f"{et.day} {BULAN[et.month-1]}, {et.year} {et:%H:%M}"
            except: pass
    except: exp_fmt = exp; created_fmt = "-"
    ssh_ovpn_val = srv.get("ssh_ovpn") or srv.get("name","SG NEWMEDIA")
    host = srv.get("domain") or SSH_HOST
    quota = srv.get("quota_gb", 700) or 700
    payload_ws = "GET /cdn-cgi/trace HTTP/1.1[crlf]Host: [host][crlf][crlf]GET-RAY / HTTP/1.1[crlf]Host: [host][crlf]Connection: Upgrade[crlf]User-Agent: [ua][crlf]Upgrade: websocket[crlf][crlf]"
    payload_tls = "GET / HTTP/1.1[crlf]Host: [host][crlf]User-Agent: [ua][crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]"
    esc = lambda x: str(x).replace("&","&amp;").replace("<","&lt;").replace(">","&gt;")
    L = [
        f"┌────────────────────────",
        f"│   <b>♨️ SSH OVPN ACCOUNT {head} ♨️</b>",
        f"└────────────────────────", "",
        f"┌────────────────────────",
        f"│ <b>City</b>       : {esc(srv.get('city','Singapore'))}",
        f"│ <b>ISP</b>        : {esc(srv.get('isp','DigitalOcean LLC'))}",
        f"│ <b>SSH OVPN</b>   : {esc(ssh_ovpn_val)}",
        f"│ <b>Username</b>   : {esc(u)}",
        f"│ <b>Password</b>   : {esc(p)}",
        f"│ <b>Qouta</b>      : {quota} GB",
        f"│ <b>Limit IP</b>   : {ip} IP",
        f"└────────────────────────", "",
        f"┌────────────────────────",
        f"│ <b>Host</b>       : {esc(host)}",
        f"│ <b>OpenSSH</b>    : 443, 80, 22",
        f"│ <b>Dropbear</b>   : 443, 109",
        f"│ <b>SSH WS</b>     : 80, 8080, 8081-9999",
        f"│ <b>SSH SSL</b>    : 443",
        f"│ <b>SSH UDP</b>    : 1-65535",
        f"│ <b>OVPN</b>       : 443, 1194, 2200",
        f"│ <b>BadVPN</b>     : 7100, 7300",
        f"└────────────────────────", "",
        "──────────────────────────",
        f"🔐 <b>SSH WS</b>  : {esc(host)}:80@{esc(u)}:{esc(p)}",
        f"🔐 <b>SSH TLS</b> : {esc(host)}:443@{esc(u)}:{esc(p)}",
        f"🔐 <b>SSH UDP</b> : {esc(host)}:1-65535@{esc(u)}:{esc(p)}", "",
        f"🧩 <b>PAYLOAD WS</b> : {esc(payload_ws)}", "",
        f"🧩 <b>PAYLOAD TLS</b> : {esc(payload_tls)}", "",
        f"┌────────────────────────",
        f"│ <b>Durasi</b>    : {esc(dl)}",
        f"│ <b>Dibuat</b>    : {created_fmt}",
        f"│ <b>Berakhir</b>  : {exp_fmt}",
        f"└────────────────────────", "",
        f"🛍️ <b>SANSXML VPN STORE</b>", "",
        f"✨ <b>TERIMAKASIH TELAH MENGGUNAKAN",
        f"LAYANAN KAMI</b> ✨"
    ]
    return "\n".join(L)

def xray_caption(proto, un, pw, cred, exp, days, sk, is_trial=False, exp_ts="", created_at=""):
    s = SERVERS.get(sk,{})
    host = s.get("domain") or SSH_HOST
    city = s.get("city","Singapore"); isp = s.get("isp","DigitalOcean LLC")
    ssh_ovpn = s.get("ssh_ovpn") or s.get("name","SG NEWMEDIA")
    quota = s.get("quota_gb",700) or 700
    ip_limit = s.get("ip_limit",1) or 1
    BULAN = ["Jan","Feb","Mar","Apr","Mei","Jun","Jul","Agu","Sep","Okt","Nov","Des"]
    try:
        ed = datetime.strptime(exp,"%Y-%m-%d")
        ef = f"{ed.day} {BULAN[ed.month-1]}, {ed.year}"
        try:
            cr = datetime.fromisoformat(created_at) if created_at else datetime.now()
        except:
            cr = datetime.now()
        cf = f"{cr.day} {BULAN[cr.month-1]}, {cr.year}" + (f" {cr:%H:%M}" if is_trial else "")
        if is_trial and exp_ts:
            try:
                et = datetime.strptime(exp_ts, "%Y-%m-%d %H:%M:%S")
                ef = f"{et.day} {BULAN[et.month-1]}, {et.year} {et:%H:%M}"
            except: pass
    except: ef = exp; cf = "-"
    head = {"vmess":"VMESS","vless":"VLESS","trojan":"TROJAN"}.get(proto,proto.upper())
    lbl = "TRIAL" if is_trial else "PREMIUM"
    esc = lambda x: str(x).replace("&","&amp;").replace("<","&lt;").replace(">","&gt;")
    if proto == "vmess":
        url1 = xray_build_vmess(host,XRAY_PORTS['vmess_tls'],cred,'/vmess',True,f'{ssh_ovpn}-WSTLS')
        url2 = xray_build_vmess(host,XRAY_PORTS['vmess_ws'],cred,'/vmess',False,f'{ssh_ovpn}-WS')
        url3 = xray_build_vmess_grpc(host,cred,'vmess-grpc',f'{ssh_ovpn}-gRPC')
        t1 = "VMESS WS TLS"; t2 = "VMESS WS"; t3 = "VMESS gRPC TLS"
        server_lines = [f"│ <b>Host</b>       : {esc(host)}", "│ <b>Path</b>       : /vmess", "│ <b>Path gRPC</b>  : vmess-grpc", f"│ <b>WS TLS</b>     : {XRAY_PORTS['vmess_tls']}", f"│ <b>WS</b>         : {XRAY_PORTS['vmess_ws']}", f"│ <b>gRPC TLS</b>   : {XRAY_PORTS['vmess_grpc']}", f"│ <b>gRPC</b>       : {XRAY_PORTS['vmess_grpc']}"]
    elif proto == "vless":
        url1 = xray_build_vless(host,XRAY_PORTS['vless_tls'],cred,'/vless',True,f'{ssh_ovpn}-WSTLS')
        url2 = xray_build_vless(host,XRAY_PORTS['vless_ws'],cred,'/vless',False,f'{ssh_ovpn}-WS')
        url3 = xray_build_vless_grpc(host,cred,'vless-grpc',f'{ssh_ovpn}-gRPC')
        t1 = "VLESS WS TLS"; t2 = "VLESS WS"; t3 = "VLESS gRPC TLS"
        server_lines = [f"│ <b>Host</b>       : {esc(host)}", "│ <b>Path</b>       : /vless", "│ <b>Path gRPC</b>  : vless-grpc", f"│ <b>WS TLS</b>     : {XRAY_PORTS['vless_tls']}", f"│ <b>WS</b>         : {XRAY_PORTS['vless_ws']}", f"│ <b>gRPC TLS</b>   : {XRAY_PORTS['vless_grpc']}", "│ <b>TCP TLS</b>    : 443"]
    else:
        url1 = xray_build_trojan(host,XRAY_PORTS['trojan_tcp'],cred,'',True,f'{ssh_ovpn}-TCP')
        url2 = xray_build_trojan(host,XRAY_PORTS['trojan_ws'],cred,'/trojan',True,f'{ssh_ovpn}-WS')
        url3 = xray_build_trojan_grpc(host,cred,'trojan-grpc',f'{ssh_ovpn}-gRPC')
        t1 = "TROJAN TCP"; t2 = "TROJAN WS TLS"; t3 = "TROJAN gRPC TLS"
        server_lines = [f"│ <b>Host</b>       : {esc(host)}", f"│ <b>Trojan TCP</b> : {XRAY_PORTS['trojan_tcp']}", f"│ <b>Trojan WS</b>  : {XRAY_PORTS['trojan_ws']} /trojan", f"│ <b>Trojan gRPC</b>: {XRAY_PORTS['trojan_grpc']} trojan-grpc"]
    password_line = f"│ <b>Password</b>   : {esc(cred if proto == 'trojan' else pw)}"
    account_lines = [
        f"│ <b>City</b>       : {esc(city)}", f"│ <b>ISP</b>        : {esc(isp)}", f"│ <b>SSH OVPN</b>   : {esc(ssh_ovpn)}",
        f"│ <b>Username</b>   : {esc(un)}", password_line
    ]
    if proto != "trojan": account_lines.append(f"│ <b>UUID</b>       : {esc(cred)}")
    account_lines += [f"│ <b>Qouta</b>      : {quota} GB", f"│ <b>Limit IP</b>   : {ip_limit} IP"]
    dur = f"{TRIAL_DURATION_MIN} Minute" if is_trial else f"{days} Hari"
    L = [f"┌────────────────────────", f"│   <b>♨️ {head} ACCOUNT {lbl} ♨️</b>", f"└────────────────────────", "",
         "┌────────────────────────"] + account_lines + ["└────────────────────────", "", "┌────────────────────────"] + server_lines + ["└────────────────────────", "", "──────────────────────────",
         f"🔐 <b>{esc(t1)}</b> : {esc(url1)}", f"🔐 <b>{esc(t2)}</b> : {esc(url2)}", f"🔐 <b>{esc(t3)}</b> : {esc(url3)}", "",
         "┌────────────────────────", f"│ <b>Durasi</b>    : {esc(dur)}", f"│ <b>Dibuat</b>    : {cf}", f"│ <b>Berakhir</b>  : {ef}", "└────────────────────────", "",
         "🛍️ <b>SANSXML VPN STORE</b>", "", "✨ <b>TERIMAKASIH TELAH MENGGUNAKAN", "LAYANAN KAMI</b> ✨"]
    return "\n".join(L)

# ACTIONS
async def do_create(chat, uid, user, un, pw, hari, is_trial=False, sk="sg_1ip"):
    s = SERVERS.get(sk,{}); ip = int(s.get("ip_limit",2) or 2)
    price = 0 if is_trial else get_price(hari,sk)
    if not is_trial and get_bal(uid) < price:
        kurang = price - get_bal(uid)
        msg_saldo = (f"<blockquote>❌ <b>Saldo Tidak Cukup</b>\n\n"
            f"💰 Saldo Anda : <b>{rupiah(get_bal(uid))}</b>\n"
            f"💵 Harga Akun : <b>{rupiah(price)}</b>\n"
            f"📉 Kurang     : <b>{rupiah(kurang)}</b>\n\n"
            "Silakan topup saldo melalui menu\n"
            "Tombol 💰 TOPUP SALDO.</blockquote>")
        kb = InlineKeyboardMarkup([[B("💰 TOPUP SALDO","isi_saldo",style="success")],[B("🔙 Kembali","menu|main",style="danger")]])
        await chat.send_message(msg_saldo,reply_markup=kb,parse_mode="HTML"); return
    hdr = "TRIAL" if is_trial else "PREMIUM"
    srv_num = list(SERVERS.keys()).index(sk) + 1 if sk in SERVERS else 1
    m = await chat.send_message(f"⚙️ Membuat {hdr} AKUN untuk server {srv_num}...", parse_mode="HTML")
    r = await asyncio.to_thread(ssh_create,un,pw,hari,is_trial,sk)
    if not is_trial:
        ok,_ = reduce_bal(uid,price)
        if not ok: await m.edit_text("❌ Saldo berubah.",parse_mode="HTML"); return
    created_at = datetime.now().isoformat()
    save_acc(un,{"user_id":uid,"username":un,"password":pw,"exp":r["exp"],"exp_ts":r.get("exp_ts",""),
        "days":hari,"limit_ip":ip,"harga":price,"created_at":created_at,
        "first_name":user.first_name or "","username_tg":user.username or "","manual":r.get("manual",False),
        "free_owner":is_owner(uid),"is_trial":is_trial,"server_key":sk,"server":s.get("name","SG NEWMEDIA"),
        "proto":"ssh"})
    if not is_trial:
        add_trx(uid,user.first_name or "User",user.username or "","buat_akun",price,f"{hari}h {s.get('name','')}")
    dl = f"{TRIAL_DURATION_MIN} Minute" if is_trial else f"{hari} Hari"
    ex = r.get("exp_ts","")[:10] if is_trial else r["exp"]
    await m.edit_text(acc_caption(un,pw,ex,dl,ip,r.get("manual",False),is_trial,sk,r.get("exp_ts", ""),created_at),parse_mode="HTML")
    asyncio.create_task(sync_push_async())
async def do_extend(chat, uid, user, un, hari, sk):
    price = get_price(hari,sk)
    if get_bal(uid) < price:
        kurang = price - get_bal(uid)
        msg_saldo = (f"<blockquote>❌ <b>Saldo Tidak Cukup</b>\n\n"
            f"💰 Saldo Anda : <b>{rupiah(get_bal(uid))}</b>\n"
            f"💵 Harga Akun : <b>{rupiah(price)}</b>\n"
            f"📉 Kurang     : <b>{rupiah(kurang)}</b>\n\n"
            "Silakan topup saldo melalui menu\n"
            "Tombol 💰 TOPUP SALDO.</blockquote>")
        kb = InlineKeyboardMarkup([[B("💰 TOPUP SALDO","isi_saldo",style="success")],[B("🔙 Kembali","menu|main",style="danger")]])
        await chat.send_message(msg_saldo,reply_markup=kb,parse_mode="HTML"); return
    m = await chat.send_message(f"⚙️ Memperpanjang akun {un} selama {hari} hari...", parse_mode="HTML")
    a = get_acc(un)
    try: oe = datetime.strptime(a["exp"],"%Y-%m-%d").date()
    except: oe = datetime.now().date()
    base = oe if oe > datetime.now().date() else datetime.now().date()
    ne = (base + timedelta(days=hari)).strftime("%Y-%m-%d")
    ok = await asyncio.to_thread(ssh_extend,un,ne,sk)
    if not ok: await m.edit_text("❌ Gagal.",parse_mode="HTML"); return
    a["exp"] = ne; a["exp_ts"] = ne+" 23:59:59"
    a["days"] = int(a.get("days",0))+hari; a["harga"] = int(a.get("harga",0))+price
    save_acc(un,a)
    ok2,_ = reduce_bal(uid,price)
    if not ok2: await m.edit_text("❌ Gagal potong saldo.",parse_mode="HTML"); return
    add_trx(uid,user.first_name or "User",user.username or "","perpanjang",price,f"{hari}h {un}")
    await m.edit_text(acc_caption(un,a["password"],ne,f"{a.get('days',30)} Hari",a.get("limit_ip",1),a.get("manual",False),a.get("is_trial",False),sk),parse_mode="HTML")
    asyncio.create_task(sync_push_async())
async def do_create_xray(chat, uid, user, un, pw, hari, sk, proto, is_trial=False):
    s = SERVERS.get(sk,{}); price = 0 if is_trial else get_price(hari,sk)
    if not is_trial and get_bal(uid) < price:
        kurang = price - get_bal(uid)
        msg_saldo = (f"<blockquote>❌ <b>Saldo Tidak Cukup</b>\n\n"
            f"💰 Saldo Anda : <b>{rupiah(get_bal(uid))}</b>\n"
            f"💵 Harga Akun : <b>{rupiah(price)}</b>\n"
            f"📉 Kurang     : <b>{rupiah(kurang)}</b>\n\n"
            "Silakan topup saldo melalui menu\n"
            "Tombol 💰 TOPUP SALDO.</blockquote>")
        kb = InlineKeyboardMarkup([[B("💰 TOPUP SALDO","isi_saldo",style="success")],[B("🔙 Kembali","menu|main",style="danger")]])
        await chat.send_message(msg_saldo,reply_markup=kb,parse_mode="HTML"); return
    hdr = 'TRIAL' if is_trial else 'PREMIUM'
    srv_num = list(SERVERS.keys()).index(sk) + 1 if sk in SERVERS else 1
    m = await chat.send_message(f"⚙️ Membuat {hdr} AKUN untuk server {srv_num}...", parse_mode="HTML")
    cred = str(uuid.uuid4()) if proto in ("vmess","vless") else pw
    ok, err = await asyncio.to_thread(xray_add_user,proto,cred)
    if not ok:
        await m.edit_text(f"❌ <b>Gagal</b>\n<code>{err}</code>",parse_mode="HTML"); return
    if not is_trial:
        ok2,_ = reduce_bal(uid,price)
        if not ok2: await m.edit_text("❌ Saldo berubah.",parse_mode="HTML"); return
    if is_trial:
        exp = datetime.now().strftime("%Y-%m-%d")
        exp_ts = (datetime.now() + timedelta(minutes=TRIAL_DURATION_MIN)).strftime("%Y-%m-%d %H:%M:%S")
    else:
        exp = (datetime.now()+timedelta(days=hari)).strftime("%Y-%m-%d")
        exp_ts = exp+" 23:59:59"
    key = f"{proto}_{un}"
    created_at = datetime.now().isoformat()
    accs = load_json(ACCOUNTS_FILE,{})
    accs[key] = {"user_id":uid,"username":un,"password":pw,
        "uuid":cred if proto != "trojan" else "","proto":proto,"exp":exp,
        "exp_ts":exp_ts,"days":hari,"limit_ip":1,"harga":price,
        "server_key":sk,"created_at":created_at,
        "first_name":user.first_name or "","username_tg":user.username or "",
        "is_trial":is_trial}
    save_json(ACCOUNTS_FILE,accs)
    if not is_trial:
        add_trx(uid,user.first_name or "User",user.username or "",f"{proto}_akun",price,f"{hari}h {s.get('name','')}")
    await m.edit_text(xray_caption(proto,un,pw,cred,exp,hari,sk,is_trial=is_trial,exp_ts=exp_ts,created_at=created_at),parse_mode="HTML")
    asyncio.create_task(sync_push_async())
async def _del_acc(uid, un, user, chat):
    a = get_acc(un)
    if not a or a.get("user_id") != uid: return
    ref = 0 if (a.get("is_trial") or int(a.get("harga",0))<=0) else hitung_refund(a)
    proto = a.get("proto","ssh")
    if proto in ("vmess","vless","trojan"):
        cred = a.get("uuid") if proto != "trojan" else a.get("password")
        if cred:
            try: await asyncio.to_thread(xray_del_user,proto,cred)
            except: pass
    else:
        try: await asyncio.to_thread(ssh_delete,un,a.get("server_key","sg_1ip"))
        except: pass
    delete_acc_json(un)
    if ref > 0:
        try:
            add_bal(uid,ref)
            add_trx(uid,user.first_name or "",user.username or "","refund",ref,f"hapus {un}")
        except: pass
    asyncio.create_task(sync_push_async())

async def auto_cleanup():
    await asyncio.sleep(30)
    while True:
        try:
            now = datetime.now(); today = now.date(); dele = 0
            for un,a in list(load_json(ACCOUNTS_FILE,{}).items()):
                ex = False; ets = a.get("exp_ts","")
                if ets:
                    try:
                        if now >= datetime.strptime(ets,"%Y-%m-%d %H:%M:%S"): ex = True
                    except: pass
                else:
                    try:
                        if (today - datetime.strptime(a["exp"],"%Y-%m-%d").date()).days >= 1: ex = True
                    except: pass
                if ex:
                    proto = a.get("proto","ssh"); sk = a.get("server_key","sg_1ip")
                    if proto in ("vmess","vless","trojan"):
     
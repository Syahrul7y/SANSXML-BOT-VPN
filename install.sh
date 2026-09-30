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

( rm -rf /tmp/badvpn
  git clone --depth=1 https://github.com/ambrop72/badvpn.git /tmp/badvpn 2>/dev/null
  if [ -d /tmp/badvpn ]; then
    mkdir -p /tmp/badvpn/build && cd /tmp/badvpn/build
    cmake .. -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1 >/dev/null 2>&1
    make -j"$(nproc)" >/dev/null 2>&1
    [ -f udpgw/badvpn-udpgw ] && cp udpgw/badvpn-udpgw /usr/bin/
    cd /root && rm -rf /tmp/badvpn
  fi
  [ -f /usr/bin/badvpn-udpgw ] && cat > /etc/systemd/system/udpgw.service << 'EOF'
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
  xray run -test -config /etc/xray/config.json

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
echo ""
echo -e "  ${CYAN}›${NC} ${WHITE}Telegram VPN Bot${NC}"
echo ""
read -r -p "$(echo -e ${GREEN}'  Bot Token Telegram : '${NC})" BOT_TOKEN < /dev/tty
if [ -z "$BOT_TOKEN" ]; then echo -e "  ${RED}❌ Token tidak boleh kosong${NC}"; exit 1; fi

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
    expiry_cmd = f"chage -E '{
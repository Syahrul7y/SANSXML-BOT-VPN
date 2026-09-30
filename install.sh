#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
CYAN='\033[1;36m'; GREEN='\033[1;32m'; RED='\033[1;31m'
YELLOW='\033[1;33m'; MAGENTA='\033[1;35m'; WHITE='\033[1;37m'; NC='\033[0m'

spin(){ local pid=$1 msg="$2"; local f=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    while kill -0 $pid 2>/dev/null; do for x in "${f[@]}"; do printf "\r  ${CYAN}${x}${NC}  ${WHITE}%s${NC}   " "$msg"; sleep 0.08; kill -0 $pid 2>/dev/null || break; done; done
    printf "\r  ${GREEN}✓${NC}  ${WHITE}%s${NC}        \n" "$msg"; }

clear
echo ""
echo -e "  ${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${CYAN}    SANSXML VPN STORE — AUTO INSTALL v10${NC}"
echo -e "  ${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# 1. CLEANUP
(
  for s in ws-ssh ws-ssh-alt stunnel4 udpgw vpnbot xray zivpn; do
    systemctl stop "$s" 2>/dev/null; systemctl disable "$s" 2>/dev/null
    rm -f "/etc/systemd/system/${s}.service"
  done
  systemctl daemon-reload 2>/dev/null; systemctl reset-failed 2>/dev/null
  fuser -k 80/tcp 8080/tcp 443/tcp 8443/tcp 7300/udp 2>/dev/null
  pkill -f ws-ssh.py 2>/dev/null; pkill -f badvpn-udpgw 2>/dev/null
  pkill -f vpnbot 2>/dev/null; pkill -f zivpn 2>/dev/null
  sleep 1
  rm -f /usr/local/bin/ws-ssh.py /usr/bin/badvpn-udpgw /usr/local/bin/badvpn-udpgw
  rm -f /etc/stunnel/stunnel.conf /etc/stunnel/stunnel.pem
  rm -f /root/bot.py /root/vpnbot.log /root/bot_compile.log
  rm -f /root/vpnbot_*.json /root/vpnbot_backup.sh /etc/sansxml-backup.conf
  rm -rf /root/vpnbot_backup
  rm -f /root/.ssh/id_bot /root/.ssh/id_bot.pub
  rm -f /etc/ssh/sshd_config.d/99-vpnbot.conf
  rm -rf /tmp/badvpn /etc/sansxml-* /etc/motd.d
  rm -f /etc/issue /etc/issue.net /etc/motd
  for u in $(awk -F: '$3>=1000 && $3<60000 {print $1}' /etc/passwd); do
    pkill -9 -u "$u" 2>/dev/null; userdel -r "$u" 2>/dev/null
  done
  mkdir -p /root/.ssh; chmod 700 /root/.ssh
  > /root/.ssh/authorized_keys; chmod 600 /root/.ssh/authorized_keys
  cat > /root/.bashrc << 'RCEOF'
case $- in *i*) ;; *) return;; esac
HISTCONTROL=ignoreboth
shopt -s histappend
HISTSIZE=1000; HISTFILESIZE=2000
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then debian_chroot=$(cat /etc/debian_chroot); fi
case "$TERM" in xterm-color|*-256color) color_prompt=yes;; esac
if [ "$color_prompt" = yes ]; then
    PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
    PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi
alias ll='ls -alF'; alias la='ls -A'; alias l='ls -CF'
RCEOF
  crontab -r 2>/dev/null
  ufw --force disable >/dev/null 2>&1; ufw --force reset >/dev/null 2>&1
  iptables -F 2>/dev/null; iptables -X 2>/dev/null
  iptables -t nat -F 2>/dev/null; iptables -t nat -X 2>/dev/null
) & spin $! "Bersihkan VPS"

# 2. DEPENDENCIES
echo ""
echo -e "  ${YELLOW}▸ Install dependencies${NC}"
( apt-get update -y >/dev/null 2>&1 ) & spin $! "Update repository"
( apt-get install -y python3 python3-pip python3-venv sshpass curl wget unzip stunnel4 net-tools cron ufw iptables openssl cmake build-essential git pkg-config bc jq who procps dnsutils vnstat uuid-runtime socat >/dev/null 2>&1 ) & spin $! "Install packages"
( pip3 install --break-system-packages --upgrade "python-telegram-bot>=21.5" requests qrcode pillow >/dev/null 2>&1 \
    || pip3 install --upgrade "python-telegram-bot>=21.5" requests qrcode pillow >/dev/null 2>&1 ) & spin $! "Install Telegram API"
( mkdir -p /root/.ssh; chmod 700 /root/.ssh
  [ ! -f /root/.ssh/id_bot ] && ssh-keygen -t ed25519 -f /root/.ssh/id_bot -N "" -q
  cat /root/.ssh/id_bot.pub >> /root/.ssh/authorized_keys
  sort -u /root/.ssh/authorized_keys -o /root/.ssh/authorized_keys
  chmod 600 /root/.ssh/authorized_keys ) & spin $! "Generate SSH key"
( systemctl enable vnstat >/dev/null 2>&1; systemctl restart vnstat >/dev/null 2>&1 ) & spin $! "Enable vnstat"

# 3. VPN SERVICES
echo ""
echo -e "  ${YELLOW}▸ Install VPN services${NC}"

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
) & spin $! "Compile BadVPN UDPGW"

( ufw default allow incoming >/dev/null 2>&1
  ufw default allow outgoing >/dev/null 2>&1
  for p in 22 80 443 8080 8443 10001 10002 10003 10004 10005 10006 10007; do ufw allow $p/tcp >/dev/null 2>&1; done
  ufw allow 7300/udp >/dev/null 2>&1; ufw allow 1:65535/udp >/dev/null 2>&1
  ufw --force enable >/dev/null 2>&1 ) & spin $! "Configure firewall"

( systemctl daemon-reload
  systemctl enable ws-ssh ws-ssh-alt stunnel4 >/dev/null 2>&1
  systemctl restart ws-ssh ws-ssh-alt stunnel4
  [ -f /usr/bin/badvpn-udpgw ] && systemctl enable udpgw >/dev/null 2>&1 && systemctl restart udpgw
  sleep 2 ) & spin $! "Start VPN services"

# 4. INSTALL XRAY
echo ""
echo -e "  ${YELLOW}▸ Install Xray${NC}"
(
  if [ ! -f /usr/local/bin/xray ]; then
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install >/dev/null 2>&1
  fi
  systemctl enable xray >/dev/null 2>&1
  systemctl stop xray 2>/dev/null || true
  mkdir -p /etc/xray/accounts /var/lib/xray
  [ ! -f /etc/xray/cert.pem ] && openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout /etc/xray/cert.key -out /etc/xray/cert.pem \
    -days 3650 -subj "/CN=sansxml.local" 2>/dev/null
  cat > /etc/xray/config.json << 'XRAYEOF'
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {"tag":"vmess-ws","listen":"0.0.0.0","port":10001,"protocol":"vmess","settings":{"clients":[]},"streamSettings":{"network":"ws","wsSettings":{"path":"/vmess"}}},
    {"tag":"vmess-grpc","listen":"0.0.0.0","port":10002,"protocol":"vmess","settings":{"clients":[]},"streamSettings":{"network":"grpc","grpcSettings":{"serviceName":"vmess-grpc"}}},
    {"tag":"vless-ws","listen":"0.0.0.0","port":10003,"protocol":"vless","settings":{"clients":[],"decryption":"none"},"streamSettings":{"network":"ws","wsSettings":{"path":"/vless"}}},
    {"tag":"vless-grpc","listen":"0.0.0.0","port":10004,"protocol":"vless","settings":{"clients":[],"decryption":"none"},"streamSettings":{"network":"grpc","grpcSettings":{"serviceName":"vless-grpc"}}},
    {"tag":"trojan-tcp","listen":"0.0.0.0","port":10005,"protocol":"trojan","settings":{"clients":[]},"streamSettings":{"network":"tcp"}},
    {"tag":"trojan-ws","listen":"0.0.0.0","port":10006,"protocol":"trojan","settings":{"clients":[]},"streamSettings":{"network":"ws","wsSettings":{"path":"/trojan"}}},
    {"tag":"trojan-grpc","listen":"0.0.0.0","port":10007,"protocol":"trojan","settings":{"clients":[]},"streamSettings":{"network":"grpc","grpcSettings":{"serviceName":"trojan-grpc"}}}
  ],
  "outbounds": [
    {"protocol":"freedom","tag":"direct"},
    {"protocol":"blackhole","tag":"blocked"}
  ]
}
XRAYEOF
  echo '{"protocol":"vmess","accounts":[]}' > /etc/xray/accounts/vmess.json
  echo '{"protocol":"vless","accounts":[]}' > /etc/xray/accounts/vless.json
  echo '{"protocol":"trojan","accounts":[]}' > /etc/xray/accounts/trojan.json
  xray run -test -config /etc/xray/config.json >/dev/null 2>&1
  systemctl restart xray
  sleep 2
) & spin $! "Install Xray"

# 5. BANNER
rm -rf /etc/update-motd.d/* 2>/dev/null
cat > /etc/issue.net << 'BANEOF'
<br><font color="#ff00aa"><b>                        ▬▬▬▬▬▬ஜ۩۞۩ஜ▬▬▬▬▬▬</b></font><br><font color="#ffffff"><b>                          --- 卐 </b></font><font color="#ffff00"><b>SANSXML VPN STORE</b></font><font color="#ffffff"><b> 卐 ---</b></font><br><font color="#ff00aa"><b>                        ▬▬▬▬▬▬ஜ۩۞۩ஜ▬▬▬▬▬▬</b></font><br><font color="#ffffff"><b>                            ── PREMIUM VPN SERVER ──</b></font><br><font color="#ffffff"><b>                             --- 卍 TERM OF SERVICE 卐 ---</b></font><br><font color="#ffffff"><b>                                      NO MULTI LOGIN !!</b></font><br><font color="#ffffff"><b>                                NO HACKING AND CARDING</b></font><br><font color="#ffff00"><b>                            👉 MULTI LOGIN BANNED 👈</b></font><br><font color="#ff00aa"><b>                        ▬▬▬▬▬▬ஜ۩۞۩ஜ▬▬▬▬▬▬</b></font><br><font color="#ffffff"><b>                    ORDER CONFIG PREMIUM: </b></font><font color="#00ff44"><b>wa.me/6289527419748</b></font><br><font color="#ffffff"><b>                         BOT ORDER VPN: </b></font><font color="#00ff44"><b>t.me/unokwn</b></font><br><br>
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
echo -e "  ${YELLOW}▸ Konfigurasi Bot${NC}"
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
XRAY_PORTS = {"vmess_ws":10001,"vmess_grpc":10002,"vless_ws":10003,"vless_grpc":10004,"trojan_tcp":10005,"trojan_ws":10006,"trojan_grpc":10007}

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
    cfg = {"v":"2","ps":remark,"add":host,"port":"443","id":u,"aid":"0","scy":"auto",
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
    return f"trojan://{pwd}@{host}:443?{p}#{remark}"

# SSH
def ssh_create(u, p, days, is_trial=False, key="sg_1ip"):
    now = datetime.now()
    if is_trial:
        exp_date = now.date(); exp_ts = (now + timedelta(minutes=TRIAL_DURATION_MIN)).strftime("%Y-%m-%d %H:%M:%S")
    else:
        exp_date = (now + timedelta(days=days)).date(); exp_ts = exp_date.strftime("%Y-%m-%d") + " 23:59:59"
    exp = exp_date.strftime("%Y-%m-%d")
    pw_b64 = base64.b64encode(p.encode()).decode()
    cmd = (f"userdel -r {u} 2>/dev/null; useradd -m -s /bin/bash {u} 2>&1 ; "
           f"chage -E '{exp}' {u} 2>&1 ; chage -M 99999 {u} 2>&1 ; chage -I -1 {u} 2>&1 ; "
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

def acc_caption(u, p, exp, dl, ip, manual=False, is_trial=False, server_key="sg_1ip"):
    srv = SERVERS.get(server_key, {})
    head = "TRIAL" if is_trial else ("MANUAL" if manual else "PREMIUM")
    BULAN = ["Jan","Feb","Mar","Apr","Mei","Jun","Jul","Agu","Sep","Okt","Nov","Des"]
    try:
        ed = datetime.strptime(exp,"%Y-%m-%d")
        exp_fmt = f"{ed.day} {BULAN[ed.month-1]}, {ed.year}"
        try: di = int(dl.split()[0])
        except: di = 30
        cr = datetime.now() - timedelta(days=di)
        created_fmt = f"{cr.day} {BULAN[cr.month-1]}, {cr.year}"
    except: exp_fmt = exp; created_fmt = "-"
    ssh_ovpn_val = srv.get("ssh_ovpn") or srv.get("name","SG NEWMEDIA")
    host = srv.get("domain") or SSH_HOST
    quota = srv.get("quota_gb", 700) or 700
    payload_ws = "GET /cdn-cgi/trace HTTP/1.1[crlf]Host: [host][crlf][crlf]GET-RAY / HTTP/1.1[crlf]Host: [host][crlf]Connection: Upgrade[crlf]User-Agent: [ua][crlf]Upgrade: websocket[crlf][crlf]"
    payload_tls = "GET / HTTP/1.1[crlf]Host: [host][crlf]User-Agent: [ua][crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]"
    ssl_link = f"{host}:443@{u}:{p}"
    ws_link = f"{host}:80@{u}:{p}"
    udp_link = f"{host}:1-65535@{u}:{p}"
    L = ["◤ <b>SSH OVPN ACCOUNT</b> ◢",
         f"     ❖ <b>{head}</b> ❖", "━━━━━━━━━━━━━━━━━━━━━━━", "", "",
         f"City       : {srv.get('city','Singapore')}",
         f"ISP        : {srv.get('isp','DigitalOcean LLC')}",
         f"SSH OVPN   : {ssh_ovpn_val}",
         f"Username   : {u}",
         f"Password   : {p}",
         f"Qouta      : {quota} GB",
         f"Limit IP   : {ip} IP", "", "",
         "━━━━━━━━━━━━━━━━━━━━━━━", "", "",
         f"Host     : {host}",
         "OpenSSH  : 443, 80, 22", "Dropbear : 443, 109",
         "SSH WS   : 80, 8080, 8081-9999", "SSH SSL  : 443", "SSH UDP  : 1-65535",
         "OVPN     : 443, 1194, 2200", "BadVPN   : 7100, 7300",
         "━━━━━━━━━━━━━━━━━━━━━━━",
         f"SSL : {ssl_link}", "", f"WS  : {ws_link}", "", f"UDP : {udp_link}",
         "━━━━━━━━━━━━━━━━━━━━━━━",
         "PAYLOAD WS", payload_ws, "", "PAYLOAD TLS", payload_tls,
         "━━━━━━━━━━━━━━━━━━━━━━━",
         f"Durasi   : {dl}", f"Dibuat   : {created_fmt}", f"Berakhir : {exp_fmt}", "",
         "━━━━━━━━━━━━━━━━━━━━━━━",
         "<b>      ◤ SANSXML VPN STORE ◢</b>",
         "<i>❖ Terima kasih telah menggunakan layanan kami ❖</i>"]
    return "\n".join(L)
def xray_caption(proto, un, pw, cred, exp, days, sk, is_trial=False):
    s = SERVERS.get(sk,{}); host = s.get("domain") or SSH_HOST
    city = s.get("city","Singapore"); isp = s.get("isp","DigitalOcean LLC")
    ssh_ovpn = s.get("ssh_ovpn") or s.get("name","SG NEWMEDIA")
    quota = s.get("quota_gb", 700) or 700
    ip_limit = s.get("ip_limit", 1) or 1
    BULAN = ["Jan","Feb","Mar","Apr","Mei","Jun","Jul","Agu","Sep","Okt","Nov","Des"]
    try:
        ed = datetime.strptime(exp,"%Y-%m-%d")
        ef = f"{ed.day} {BULAN[ed.month-1]}, {ed.year}"
        cr = datetime.now(); cf = f"{cr.day} {BULAN[cr.month-1]}, {cr.year}"
    except: ef = exp; cf = "-"
    head = {"vmess":"VMESS","vless":"VLESS","trojan":"TROJAN"}.get(proto,proto.upper())
    lbl = "TRIAL" if is_trial else "PREMIUM"
    if proto == "vmess":
        url1 = xray_build_vmess(host,443,cred,'/vmess',True,f'{ssh_ovpn}-WSTLS')
        url2 = xray_build_vmess(host,XRAY_PORTS['vmess_ws'],cred,'/vmess',False,f'{ssh_ovpn}-WS')
        url3 = xray_build_vmess_grpc(host,cred,'vmess-grpc',f'{ssh_ovpn}-gRPC')
        t1 = "── VMESS WS TLS ──"; t2 = "── VMESS WS ──"; t3 = "── VMESS gRPC TLS ──"
    elif proto == "vless":
        url1 = xray_build_vless(host,443,cred,'/vless',True,f'{ssh_ovpn}-WSTLS')
        url2 = xray_build_vless(host,XRAY_PORTS['vless_ws'],cred,'/vless',False,f'{ssh_ovpn}-WS')
        url3 = xray_build_vless_grpc(host,cred,'vless-grpc',f'{ssh_ovpn}-gRPC')
        t1 = "── VLESS WS TLS ──"; t2 = "── VLESS WS ──"; t3 = "── VLESS gRPC TLS ──"
    else:
        url1 = xray_build_trojan(host,XRAY_PORTS['trojan_tcp'],cred,'',True,f'{ssh_ovpn}-TCP')
        url2 = xray_build_trojan(host,443,cred,'/trojan',True,f'{ssh_ovpn}-WS')
        url3 = xray_build_trojan_grpc(host,cred,'trojan-grpc',f'{ssh_ovpn}-gRPC')
        t1 = "── TROJAN TCP ──"; t2 = "── TROJAN WS TLS ──"; t3 = "── TROJAN gRPC TLS ──"
    L = [f"◤ <b>{head} ACCOUNT</b> ◢",f"     ❖ <b>{lbl}</b> ❖","━━━━━━━━━━━━━━━━━━━━━━━","",""]
    L += [f"City       : {city}",f"ISP        : {isp}",f"SSH OVPN   : {ssh_ovpn}",f"Username   : {un}"]
    if proto == "trojan": L += [f"Password   : {cred}"]
    else: L += [f"Password   : {pw}",f"UUID       : {cred}"]
    L += [f"Qouta      : {quota} GB",f"Limit IP   : {ip_limit} IP","","","━━━━━━━━━━━━━━━━━━━━━━━","",""]
    if proto == "vmess":
        L += [f"Host       : {host}","Path       : /vmess","Path gRPC  : vmess-grpc","WS TLS     : 443",f"WS         : {XRAY_PORTS['vmess_ws']}","gRPC TLS   : 443",f"gRPC       : {XRAY_PORTS['vmess_grpc']}"]
    elif proto == "vless":
        L += [f"Host       : {host}","Path       : /vless","Path gRPC  : vless-grpc","WS TLS     : 443",f"WS         : {XRAY_PORTS['vless_ws']}","gRPC TLS   : 443","TCP TLS    : 443"]
    else:
        L += [f"Host       : {host}",f"Trojan TCP : {XRAY_PORTS['trojan_tcp']}","Trojan WS  : 443 /trojan","Trojan gRPC: 443 trojan-grpc"]
    L += ["","━━━━━━━━━━━━━━━━━━━━━━━","","","<b>URL CONFIGURATION</b>","",
          f"<b>{t1}</b>",url1,"",
          f"<b>{t2}</b>",url2,"",
          f"<b>{t3}</b>",url3,"",
          "━━━━━━━━━━━━━━━━━━━━━━━","",f"Durasi     : {TRIAL_DURATION_MIN} Minute" if is_trial else f"Durasi     : {days} Hari",
          f"Dibuat     : {cf}",f"Berakhir   : {ef}","",
          "━━━━━━━━━━━━━━━━━━━━━━━","<b>      ◤ SANSXML VPN STORE ◢</b>",
          "<i>❖ Terima kasih telah menggunakan layanan kami ❖</i>"]
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
    save_acc(un,{"user_id":uid,"username":un,"password":pw,"exp":r["exp"],"exp_ts":r.get("exp_ts",""),
        "days":hari,"limit_ip":ip,"harga":price,"created_at":datetime.now().isoformat(),
        "first_name":user.first_name or "","username_tg":user.username or "","manual":r.get("manual",False),
        "free_owner":is_owner(uid),"is_trial":is_trial,"server_key":sk,"server":s.get("name","SG NEWMEDIA"),
        "proto":"ssh"})
    if not is_trial:
        add_trx(uid,user.first_name or "User",user.username or "","buat_akun",price,f"{hari}h {s.get('name','')}")
    dl = f"{TRIAL_DURATION_MIN} Minute" if is_trial else f"{hari} Hari"
    ex = r.get("exp_ts","")[:10] if is_trial else r["exp"]
    await m.edit_text(acc_caption(un,pw,ex,dl,ip,r.get("manual",False),is_trial,sk),parse_mode="HTML")
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
    accs = load_json(ACCOUNTS_FILE,{})
    accs[key] = {"user_id":uid,"username":un,"password":pw,
        "uuid":cred if proto != "trojan" else "","proto":proto,"exp":exp,
        "exp_ts":exp_ts,"days":hari,"limit_ip":1,"harga":price,
        "server_key":sk,"created_at":datetime.now().isoformat(),
        "first_name":user.first_name or "","username_tg":user.username or "",
        "is_trial":is_trial}
    save_json(ACCOUNTS_FILE,accs)
    if not is_trial:
        add_trx(uid,user.first_name or "User",user.username or "",f"{proto}_akun",price,f"{hari}h {s.get('name','')}")
    await m.edit_text(xray_caption(proto,un,pw,cred,exp,hari,sk,is_trial=is_trial),parse_mode="HTML")
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
                        cred = a.get("uuid") if proto != "trojan" else a.get("password")
                        if cred:
                            try: await asyncio.to_thread(xray_del_user,proto,cred)
                            except: pass
                        delete_acc_json(un)
                    else:
                        if a.get("is_trial"):
                            await asyncio.to_thread(ssh_delete,un,sk)
                            a["os_deleted"] = True; a["deleted_at"] = now.isoformat(); save_acc(un,a)
                        else:
                            await asyncio.to_thread(ssh_delete,un,sk); delete_acc_json(un)
                    dele += 1
            if dele > 0: logger.info(f"[CLEANUP] {dele} expired")
            accs = load_json(ACCOUNTS_FILE,{}); blk = load_json(BLOCK_FILE,{})
            for un,a in accs.items():
                if a.get("proto") != "ssh": continue
                if a.get("is_trial") or a.get("free_owner") or un in blk: continue
                sk = a.get("server_key","sg_1ip")
                v,_,cnt = await asyncio.to_thread(check_second,un,sk)
                if v:
                    try: await asyncio.to_thread(block_user,un,BLOCK_HOURS,sk)
                    except: pass
            blk = load_json(BLOCK_FILE,{}); chg = False
            for un,info in list(blk.items()):
                try:
                    if now >= datetime.strptime(info["unblock_at"],"%Y-%m-%d %H:%M:%S"):
                        sk = (get_acc(un) or {}).get("server_key","sg_1ip")
                        await asyncio.to_thread(unblock_user,un,sk); chg = True
                except: pass
        except Exception as e: logger.error(f"cleanup: {e}")
        await asyncio.sleep(60)

async def start(u,c):
    uid = u.effective_user.id
    track_user(u.effective_user); c.user_data.clear()
    await u.message.reply_text(dash_text(u.effective_user,uid),reply_markup=kb_dash(uid),parse_mode="HTML")

async def cb(u,c):
    uid = u.effective_user.id
    track_user(u.effective_user)
    q = u.callback_query; await q.answer()
    d = q.data; chat = u.effective_chat
    if d in ("noop","ssh_locked"): return

    if d == "refresh":
        try: await q.message.delete()
        except: pass
        try: await chat.send_message(dash_text(u.effective_user,uid),reply_markup=kb_dash(uid),parse_mode="HTML")
        except: pass
        return

    if d == "isi_saldo":
        c.user_data["saldo_input"] = ""
        try: await q.edit_message_text(saldo_text(uid),reply_markup=kb_saldo(),parse_mode="HTML")
        except: pass
        return
    if d.startswith("saldo_num|"):
        cur = c.user_data.get("saldo_input",""); ad = d.split("|",1)[1]
        if len(cur) >= 9: await q.answer("Maks 9 digit",show_alert=True); return
        cur = (cur+ad).lstrip("0") or ""; c.user_data["saldo_input"] = cur
        try: await q.edit_message_text(saldo_text(uid,cur),reply_markup=kb_saldo(),parse_mode="HTML")
        except: pass
        return
    if d == "saldo_hapus":
        cur = c.user_data.get("saldo_input",""); cur = cur[:-1] if cur else ""
        c.user_data["saldo_input"] = cur
        try: await q.edit_message_text(saldo_text(uid,cur),reply_markup=kb_saldo(),parse_mode="HTML")
        except: pass
        return
    if d == "saldo_konfirmasi":
        cur = c.user_data.get("saldo_input","")
        if not cur or int(cur)<=0: await q.answer("Nominal belum diisi!",show_alert=True); return
        nom = int(cur)
        if nom < MIN_TOPUP: await q.answer(f"❌ Minimal topup {rupiah(MIN_TOPUP)}",show_alert=True); return
        sb = add_bal(uid,nom)
        add_trx(uid,u.effective_user.first_name or "",u.effective_user.username or "","isi_saldo",nom,"topup")
        c.user_data["saldo_input"] = ""
        try: await q.edit_message_text(f"<blockquote>✅ <b>Topup Saldo Berhasil</b>\n\n💰 Nominal: <b>{rupiah(nom)}</b>\n💼 Saldo Sekarang: <b>{rupiah(sb)}</b></blockquote>",
            reply_markup=InlineKeyboardMarkup([[B("🔙 Kembali","menu|main",style="danger")]]),parse_mode="HTML")
        except: pass
        asyncio.create_task(sync_push_async()); return

    if d == "buat_akun":
        if not is_backup_ready():
            await q.answer("⚠️ Backup belum di-setup.",show_alert=True); return
        c.user_data.clear(); c.user_data["mode"] = "buat"
        try: await q.edit_message_text(pilih_layanan_text(),reply_markup=kb_layanan(),parse_mode="HTML")
        except: pass
        return
    if d == "trial_akun":
        if not is_backup_ready(): await q.answer("⚠️ Backup belum di-setup.",show_alert=True); return
        c.user_data.clear(); c.user_data["mode"] = "trial"
        try: await q.edit_message_text(pilih_layanan_text(),reply_markup=kb_layanan(),parse_mode="HTML")
        except: pass
        return
    if d == "perpanjang_akun":
        if not is_backup_ready(): await q.answer("⚠️ Backup belum di-setup.",show_alert=True); return
        c.user_data.clear(); c.user_data["mode"] = "perpanjang"
        try: await q.edit_message_text(pilih_layanan_text(),reply_markup=kb_layanan(),parse_mode="HTML")
        except: pass
        return
    if d == "pilih_layanan":
        c.user_data["mode"] = c.user_data.get("mode","buat")
        try: await q.edit_message_text(pilih_layanan_text(),reply_markup=kb_layanan(),parse_mode="HTML")
        except: pass
        return
    if d.startswith("pilih|"):
        p = d.split("|")[1]; mode = c.user_data.get("mode","buat")
        if p == "ssh":
            if mode == "perpanjang":
                try: await q.edit_message_text(ssh_server_text(),reply_markup=kb_srv_ext(),parse_mode="HTML")
                except: pass
            else:
                try: await q.edit_message_text(ssh_server_text(),reply_markup=kb_srv_ssh(),parse_mode="HTML")
                except: pass
        else:
            if not xray_exists():
                try: await q.edit_message_text(f"<blockquote>⚠️ <b>{p.upper()} BELUM SIAP</b></blockquote>",reply_markup=kb_soon(p),parse_mode="HTML")
                except: pass
                return
            try: await q.edit_message_text(xray_server_text(p),reply_markup=kb_xray_srv(p),parse_mode="HTML")
            except: pass
        return
    if d == "menu|main":
        c.user_data.clear()
        try: await q.edit_message_text(dash_text(u.effective_user,uid),reply_markup=kb_dash(uid),parse_mode="HTML")
        except: pass
        return

    if d == "admin|backup":
        if not is_owner(uid): return
        try: await q.edit_message_text(backup_config_text(),reply_markup=kb_backup(),parse_mode="HTML")
        except: pass
        return
    if d.startswith("backup_edit|"):
        if not is_owner(uid): return
        f = d.split("|")[1]; c.user_data["backup_field"] = f
        pr = {"user":"Kirim <b>username GitHub</b>:","repo":"Kirim <b>nama repo</b>:",
              "token":"Kirim <b>GitHub token</b> (ghp_xxx):","email":"Kirim <b>email GitHub</b>:"}
        try: await q.edit_message_text(f"✏️ <b>GANTI {f.upper()}</b>\n\n{pr.get(f,'')}",
            reply_markup=InlineKeyboardMarkup([[B("❌ Batal","admin|backup",style="danger")]]),parse_mode="HTML")
        except: pass
        return
    if d == "backup_reset":
        if not is_owner(uid): return
        try: await q.edit_message_text("📊 <b>Restore Data</b>\n───────────────────────\n"
            "🔴 <b>Akan DIHAPUS:</b>\n├ Semua file JSON\n├ Semua user OS\n├ Folder backup\n├ Cron\n╰ History GitHub\n\n"
            "⚠️ <b>Tidak bisa dipulihkan!</b>\n───────────────────────\nLanjutkan?",
            reply_markup=InlineKeyboardMarkup([[B("✅ Ya, Lanjutkan","backup_reset_yes",style="danger")],
                [B("❌ Batal","admin|backup",style="danger")]]),parse_mode="HTML")
        except: pass
        return
    if d == "backup_reset_yes":
        if not is_owner(uid): return
        try: await q.edit_message_text("📊 <b>Memproses...</b>",parse_mode="HTML")
        except: pass
        ok,info = await asyncio.to_thread(reset_backup,True)
        if ok:
            loc = info.get("local",{}); err = info.get("gh_error","")
            eb = f"\n🔴 <code>{err[:300]}</code>\n" if err else ""
            m = ("✅ <b>Restore Selesai</b>\n\n<blockquote>"
                 f"☁️ GitHub: <b>{'DIPUTUS' if info.get('github') else '❌ GAGAL'}</b>\n{eb}\n"
                 f"🗑️ JSON: <b>{loc.get('json',0)}</b>\n👤 OS: <b>{loc.get('users',0)}</b>\n"
                 f"📁 Folder: <b>{'dihapus' if loc.get('folder') else '-'}</b>\n</blockquote>")
            try: await q.edit_message_text(m,reply_markup=InlineKeyboardMarkup([[B("🔙 Kembali","admin|menu",style="danger")]]),parse_mode="HTML")
            except: pass
            await asyncio.sleep(5); subprocess.Popen(["systemctl","restart","vpnbot"])
        else:
            try: await q.edit_message_text(f"❌ <b>Gagal</b>\n<code>{info.get('error','?')[:200]}</code>",
                reply_markup=InlineKeyboardMarkup([[B("🔙 Kembali","admin|backup",style="danger")]]),parse_mode="HTML")
            except: pass
        return

    if d == "admin|vps":
        if not is_owner(uid): return
        try: await q.edit_message_text("⏳ <b>Memuat...</b>",parse_mode="HTML")
        except: pass
        lines = ["<blockquote>","💻 <b>DAFTAR VPS</b>","───────────────────────",""]
        for i,(k,s) in enumerate(SERVERS.items(),1):
            v = await asyncio.to_thread(get_vps_detail,k)
            hl = "Local" if is_local_server(k) else "Remote"
            ia = s.get('ssh_host','127.0.0.1'); pn = s.get('ssh_port',22)
            rip = v.get("ip","-") if ia in ("127.0.0.1","localhost","") else ia
            bw = v["bw"]; bws = f"{bw:.2f}" if bw >= 1 else f"{bw:.3f}"
            lines += [f"[{i}] <b>{s.get('name','-')}</b>",f"├ IP     : <code>{rip}</code>",
                f"├ Port   : <code>{pn}</code> ({hl})",f"├ OS     : {v['os'][:30]}",
                f"├ CPU    : {v['cpu'][:30]} ({v['cores']} cores)",
                f"├ RAM    : {v['ram_used']}/{v['ram_total']} ({v['ram_pct']})",
                f"├ Disk   : {v['disk_used']}/{v['disk_total']} ({v['disk_pct']})",
                f"├ Uptime : {v['uptime']}",f"╰ BW     : {bws} GB",""]
        lines += ["───────────────────────","</blockquote>"]
        rows = []
        for i,k in enumerate(SERVERS.keys(),1):
            rows.append([B(f"[{i}] {SERVERS[k].get('name','-')}",f"admin|vps_detail|{k}",style="primary")])
        rows.append([B("🔄 Refresh","admin|vps",style="success"),B("🔙 Kembali","admin|menu",style="danger")])
        try: await q.edit_message_text("\n".join(lines),reply_markup=InlineKeyboardMarkup(rows),parse_mode="HTML")
        except: pass
        return
    if d.startswith("admin|vps_detail|"):
        if not is_owner(uid): return
        k = d.split("|")[2]
        if k not in SERVERS: await q.answer("Server tidak ditemukan",show_alert=True); return
        s = SERVERS[k]
        try: await q.edit_message_text("⏳ <b>Loading...</b>",parse_mode="HTML")
        except: pass
        v = await asyncio.to_thread(get_vps_detail,k)
        hl = "Local" if is_local_server(k) else "Remote"
        used = count_slots(k); mx = int(s.get("slot_max",50) or 50)
        stat = "🟢 Online" if max(0,mx-used)>0 else "🔴 Full"
        ia = s.get('ssh_host','127.0.0.1'); pn = s.get('ssh_port',22)
        rip = v.get("ip","-") or "-" if ia in ("127.0.0.1","localhost","") else ia
        txt = (f"<blockquote><b>{s.get('name','-')}</b>\n<code>{rip}:{pn}</code>\n───────────────────────\n"
               f"🖥️ <b>Sistem</b>\n├ OS      : {v['os']}\n├ Kernel  : <code>{v['kernel']}</code>\n"
               f"├ CPU     : {v['cpu']}\n╰ Cores   : <b>{v['cores']}</b>\n\n"
               f"💾 <b>Resource</b>\n├ RAM     : <b>{v['ram_used']}</b> / {v['ram_total']} ({v['ram_pct']})\n"
               f"├ Disk    : <b>{v['disk_used']}</b> / {v['disk_total']} ({v['disk_pct']})\n"
               f"├ Uptime  : <b>{v['uptime']}</b>\n╰ Load    : <b>{', '.join(v['load'])}</b>\n\n"
               f"🌐 <b>Network</b>\n├ IP      : <code>{rip}</code>\n├ Port    : <code>{pn}</code>\n├ Type    : <b>{hl}</b>\n"
               f"╰ Bandwidth : <b>{v['bw']:.2f} GB</b>\n\n"
               f"📊 <b>Config</b>\n├ Harga   : {rupiah(s.get('price_month',0) or 0)}/bln\n├ Quota   : {s.get('quota_gb','-') or '-'} GB\n"
               f"├ Limit   : {s.get('ip_limit','-') or '-'} IP\n├ Slot    : <b>{used}/{mx}</b>\n├ Domain  : <code>{s.get('domain','-')}</code>\n"
               f"╰ Status  : <b>{stat}</b>\n───────────────────────\n</blockquote>")
        try: await q.edit_message_text(txt,reply_markup=InlineKeyboardMarkup([
            [B("🔄 Refresh",f"admin|vps_detail|{k}",style="success")],
            [B("🔙 Kembali","admin|vps",style="danger")]]),parse_mode="HTML")
        except: pass
        return

    if d == "admin|srv":
        if not is_owner(uid): return
        lines = ["<blockquote>","💻 <b>KELOLA SERVER</b>","───────────────────────",""]
        for k,s in SERVERS.items():
            tag = " ⚠️" if not is_server_complete(s) else ""
            lines.append(f"<b>{s.get('name','-')}{tag}</b>")
            pd = s.get("price_day"); pm = s.get("price_month")
            ip_l = s.get("ip_limit"); sm = s.get("slot_max")
            lines.append(f"├ Harga Harian  : <b>{rupiah(pd) if pd else '❌ Belum diisi'}</b>")
            lines.append(f"├ Harga Bulanan : <b>{rupiah(pm) if pm else '❌ Belum diisi'}</b>")
            lines.append(f"├ Limit IP      : <b>{ip_l} IP</b>" if ip_l else "├ Limit IP      : <b>❌ Belum diisi</b>")
            lines.append(f"╰ Slot Server  : <b>{sm}</b>" if sm else "╰ Slot Server  : <b>❌ Belum diisi</b>")
            lines.append("")
        lines += ["───────────────────────","</blockquote>"]
        rows = []; ks = list(SERVERS.keys())
        for i in range(0,len(ks),2):
            row = []
            for j in range(i,min(i+2,len(ks))):
                kk = ks[j]; s = SERVERS[kk]
                lb = s.get('name','-') if is_server_complete(s) else f"{s.get('name','-')} ⚠️"
                row.append(B(lb,f"srv_edit|{kk}",style="primary" if is_server_complete(s) else "danger"))
            rows.append(row)
        rows.append([B("➕ TAMBAH","srv_add",style="success"),B("🚫 HAPUS","srv_del_list",style="danger")])
        rows.append([B("🔙 Kembali","admin|menu",style="danger")])
        try: await q.edit_message_text("\n".join(lines),reply_markup=InlineKeyboardMarkup(rows),parse_mode="HTML")
        except: pass
        return
    if d.startswith("srv_edit|"):
        if not is_owner(uid): return
        k = d.split("|")[1]
        if k not in SERVERS: await q.answer("No",show_alert=True); return
        s = SERVERS[k]; comp = is_server_complete(s)
        pd = s.get("price_day"); pm = s.get("price_month")
        qg = s.get("quota_gb"); ip = s.get("ip_limit"); sm = s.get("slot_max")
        dom = s.get("domain","")
        qgs = f"{qg} GB" if qg else "❌"; pds = rupiah(pd) if pd else "❌"
        pms = rupiah(pm) if pm else "❌"; ips = f"{ip} IP" if ip else "❌"
        sms = f"{sm}" if sm else "❌"; doms = dom if dom else "❌"
        cty = s.get("city","-") or "-"; isp_v = s.get("isp","-") or "-"
        warn = "\n⚠️ <b>Lengkapi dulu</b>\n" if not comp else "\n✅ <i>Aktif</i>\n"
        txt = (f"<blockquote><b>{s.get('name','-')}</b>\n───────────────────────\n\n"
            f"├ City          : <b>{cty}</b>\n├ ISP           : <b>{isp_v}</b>\n"
            f"├ Harga Harian  : <b>{pds}</b>\n├ Harga Bulanan : <b>{pms}</b>\n"
            f"├ Qouta         : <b>{qgs}</b>\n├ Limit IP      : <b>{ips}</b>\n"
            f"├ Slot Server   : <b>{sms}</b>\n╰ Domain       : <b>{doms}</b>\n{warn}</blockquote>")
        rows = [[B("Nama Server",f"srv_set|{k}|name",style="primary"),B("Harga Bulanan",f"srv_set|{k}|price_month",style="primary")],
            [B("Kota / City",f"srv_set|{k}|city",style="primary"),B("ISP",f"srv_set|{k}|isp",style="primary")],
            [B("Quota GB",f"srv_set|{k}|quota_gb",style="primary"),B("Limit IP",f"srv_set|{k}|ip_limit",style="primary")],
            [B("Slot Server",f"srv_set|{k}|slot_max",style="primary"),B("Domain Server",f"srv_set|{k}|domain",style="primary")]]
        if not is_local_server(k):
            rows.append([B("🔧 SSH Setting",f"srv_ssh|{k}",style="primary")])
            rows.append([B("🗑️ Hapus",f"srv_del|{k}",style="danger")])
        rows.append([B("🔙 Kembali","admin|srv",style="danger")])
        try: await q.edit_message_text(txt,reply_markup=InlineKeyboardMarkup(rows),parse_mode="HTML")
        except: pass
        return
    if d.startswith("srv_set|"):
        if not is_owner(uid): return
        p = d.split("|")
        if len(p)<3: return
        k = p[1]; f = p[2]
        if k not in SERVERS: await q.answer("No",show_alert=True); return
        c.user_data["srv_edit"] = {"key":k,"field":f}
        sname = SERVERS[k].get("name","server")
        pr = {"name":f"Kirim nama baru untuk server <b>{sname}</b>\nContoh: <code>{sname}</code>",
              "city":f"Kirim nama kota baru untuk <b>{sname}</b>\nContoh: <code>Singapore</code>",
              "isp":f"Kirim nama ISP baru untuk <b>{sname}</b>\nContoh: <code>DigitalOcean LLC</code>",
              "price_month":f"Kirim harga BULANAN (30 hari) baru untuk <b>{sname}</b>\nContoh: <code>3510</code>\n<i>Harga harian otomatis = harga bulanan ÷ 30</i>",
              "quota_gb":f"Kirim quota GB baru untuk <b>{sname}</b>\nContoh: <code>700</code>",
              "ip_limit":f"Kirim limit IP baru untuk <b>{sname}</b>\nContoh: <code>2</code>",
              "slot_max":f"Kirim jumlah slot server baru untuk <b>{sname}</b>\nContoh: <code>50</code>",
              "domain":f"Kirim DOMAIN baru untuk <b>{sname}</b>\nContoh: <code>sgivip.naaofficial.web.id</code>"}
        try: await q.edit_message_text(pr.get(f,"Kirim:"),reply_markup=InlineKeyboardMarkup([[B("❌ Batal",f"srv_edit|{k}",style="danger")]]),parse_mode="HTML")
        except: pass
        return
    if d == "srv_add":
        if not is_owner(uid): return
        c.user_data["srv_add_step"] = "input"
        try: await q.edit_message_text(
            "<blockquote>➕ <b>TAMBAH SERVER</b>\n───────────────────────\n"
            "Format: <code>nama|ip|port</code>\n\nContoh:\n"
            "<code>🇮🇩 INDO|103.123.45.67|22</code>\n\nLocal: <code>LOCAL|127.0.0.1|22</code>\n</blockquote>",
            reply_markup=InlineKeyboardMarkup([[B("❌ Batal","admin|srv",style="danger")]]),parse_mode="HTML")
        except: pass
        return
    if d == "srv_del_list":
        if not is_owner(uid): return
        remote = {k:v for k,v in SERVERS.items() if not is_local_server(k)}
        if not remote:
            try: await q.edit_message_text("<blockquote>🚫 <b>HAPUS SERVER</b>\n───────────────────────\n\n⚠️ Tidak ada server remote.\n───────────────────────\n</blockquote>",
                reply_markup=InlineKeyboardMarkup([[B("🔙 Kembali","admin|srv",style="danger")]]),parse_mode="HTML")
            except: pass
            return
        rows = []
        for k,v in remote.items(): rows.append([B(v.get("name","-"),f"srv_del|{k}",style="danger")])
        rows.append([B("🔙 Kembali","admin|srv",style="danger")])
        try: await q.edit_message_text("<blockquote>🚫 <b>HAPUS SERVER</b>\n───────────────────────\n\nPilih server:\n───────────────────────\n</blockquote>",
            reply_markup=InlineKeyboardMarkup(rows),parse_mode="HTML")
        except: pass
        return
    if d.startswith("srv_del|"):
        if not is_owner(uid): return
        k = d.split("|")[1]
        if k not in SERVERS: await q.answer("No",show_alert=True); return
        if is_local_server(k): await q.answer("❌ Server lokal dilindungi",show_alert=True); return
        s = SERVERS[k]; used = count_slots(k)
        try: await q.edit_message_text(
            f"<blockquote>⚠️ <b>KONFIRMASI HAPUS</b>\n───────────────────────\n"
            f"Server: <b>{s.get('name','-')}</b>\nHost: <code>{s.get('ssh_host','-')}:{s.get('ssh_port',22)}</code>\nAkun: <b>{used}</b>\n\n"
            f"🔴 Akan DIHAPUS semua user OS, akun JSON, SSH key.\n\n⚠️ <i>Tidak bisa dipulihkan!</i>\n</blockquote>",
            reply_markup=InlineKeyboardMarkup([[B("✅ Ya, Hapus",f"srv_del_yes|{k}",style="danger")],
                [B("❌ Batal",f"srv_edit|{k}",style="danger")]]),parse_mode="HTML")
        except: pass
        return
    if d.startswith("srv_del_yes|"):
        if not is_owner(uid): return
        k = d.split("|")[1]
        if k not in SERVERS: await q.answer("No",show_alert=True); return
        if is_local_server(k): await q.answer("❌ DIlindungi",show_alert=True); return
        try: await q.edit_message_text("🗑️ <b>Menghapus...</b>",parse_mode="HTML")
        except: pass
        s = SERVERS[k]; dele = 0
        try:
            code,o,_ = ssh_run("awk -F: '$3>=1000 && $3<60000 {print $1}' /etc/passwd",k,timeout=10)
            if code == 0:
                for un in o.split():
                    try:
                        ssh_run(f"pkill -9 -u {un} 2>/dev/null; userdel -r {un} 2>/dev/null",k,timeout=15)
                        dele += 1
                    except: pass
        except: pass
        accs = load_json(ACCOUNTS_FILE,{}); rem = 0
        for un in list(accs.keys()):
            if accs[un].get("server_key") == k: accs.pop(un); rem += 1
        save_json(ACCOUNTS_FILE,accs)
        kf = s.get("ssh_key")
        if kf and os.path.exists(kf):
            try: os.remove(kf)
            except: pass
            if os.path.exists(kf+".pub"):
                try: os.remove(kf+".pub")
                except: pass
        SERVERS.pop(k,None); save_servers()
        try: await q.edit_message_text(
            f"<blockquote>✅ <b>Dihapus</b>\n\nServer: <b>{s.get('name','-')}</b>\nUser OS: <b>{dele}</b>\nAkun JSON: <b>{rem}</b>\n</blockquote>",
            reply_markup=InlineKeyboardMarkup([[B("💻 Kelola Server","admin|srv",style="primary")],
                [B("🔙 Menu","admin|menu",style="danger")]]),parse_mode="HTML")
        except: pass
        asyncio.create_task(sync_push_async()); return
    if d.startswith("srv_add_retry|"):
        if not is_owner(uid): return
        kn = d.split("|")[1]
        pend = c.user_data.get("srv_add_pending",{})
        if not pend or pend.get("key") != kn:
            await q.answer("Data tidak ditemukan",show_alert=True); return
        kf = pend["ssh_key"]; ip = pend["ip"]; port = pend["port"]
        to = await asyncio.to_thread(test_ssh_key,kf,ip,port)
        if not to: await q.answer("❌ Masih gagal",show_alert=True); return
        SERVERS[kn] = {"name":pend["nama"],"ssh_host":ip,"ssh_port":port,"ssh_user":"root",
            "ssh_key":kf,"city":"-","isp":"-","ssh_ovpn":pend["nama"],
            "domain":None,"price_day":None,"price_month":None,
            "ip_limit":None,"slot_max":None,"quota_gb":None}
        save_servers(); c.user_data["srv_add_pending"] = None
        try: await q.edit_message_text(f"<blockquote>✅ <b>{pend['nama']} ditambahkan</b>\n\n⚠️ Lengkapi data dulu</blockquote>",
            reply_markup=InlineKeyboardMarkup([[B("💻 Kelola Server","admin|srv",style="primary")],
                [B("🔙 Menu","admin|menu",style="danger")]]),parse_mode="HTML")
        except: pass
        asyncio.create_task(sync_push_async()); return
    if d.startswith("srv_ssh|"):
        if not is_owner(uid): return
        k = d.split("|")[1]
        if k not in SERVERS: await q.answer("No",show_alert=True); return
        s = SERVERS[k]
        try: await q.edit_message_text(
            f"<blockquote>🔧 <b>SSH SETTING</b>\n───────────────────────\n"
            f"Server : <b>{s.get('name','-')}</b>\nHost   : <code>{s.get('ssh_host','-')}</code>\n"
            f"Port   : <code>{s.get('ssh_port',22)}</code>\nUser   : <code>{s.get('ssh_user','root')}</code>\n"
            f"Key    : <code>{s.get('ssh_key','-')}</code>\n</blockquote>",
            reply_markup=InlineKeyboardMarkup([[B("🔙 Kembali",f"srv_edit|{k}",style="danger")]]),parse_mode="HTML")
        except: pass
        return

    if d == "admin|menu":
        if not is_owner(uid): return
        inc = get_income(); us = count_users_by_period()
        svr_stat = get_server_status()
        svr_parts = []
        for s in svr_stat:
            tag = "" if s["complete"] else " ⚠️"
            bw = s["bw"]; bws = f"{bw:.0f}" if bw >= 1 else f"{bw:.1f}"
            svr_parts.append(f"├ {s['name']}{tag}\n│ ├ Qouta  : <b>{bws}/{s['quota']}</b>\n│ ├ Slot   : <b>{s['used']}/{s['max']}</b>\n│ ╰ Status : <b>{s['status']}</b>")
        svr_txt = "\n".join(svr_parts)
        txt = ("<blockquote>💻 <b>PENGATURAN VPS BOT VPN</b>\n───────────────────────\n"
            f"👥 Total User : <b>{us['total']}</b>\n   Total Akun : <b>{count_accounts()}</b>\n\n"
            "📈 <b>PENGHASILAN</b>\n"
            f"├ Hari Ini   : <b>{rupiah(inc['hari'])}</b>\n├ Minggu Ini : <b>{rupiah(inc['minggu'])}</b>\n"
            f"├ Bulan Ini  : <b>{rupiah(inc['bulan'])}</b>\n└ Total      : <b>{rupiah(inc['total'])}</b>\n\n"
            "👤 <b>JUMLAH USER</b>\n"
            f"├ Hari Ini   : <b>{us['hari']}</b>\n├ Minggu Ini : <b>{us['minggu']}</b>\n"
            f"├ Bulan Ini  : <b>{us['bulan']}</b>\n└ Total      : <b>{us['total']}</b>\n\n"
            "📡 <b>STATUS VPS</b>\n" f"{svr_txt}\n───────────────────────\n</blockquote>")
        try: await q.edit_message_text(txt,reply_markup=kb_admin(),parse_mode="HTML")
        except: pass
        return
    if d.startswith("admin|users|"):
        if not is_owner(uid): return
        try: pg = int(d.split("|")[2])
        except: pg = 0
        users = load_json(USERS_FILE,{})
        ks = [k for k in users.keys() if int(k) not in ADMIN_IDS]
        ks.sort(key=lambda k: users[k].get("last_seen",""),reverse=True)
        tot = len(ks); per = 10; tp = max(1,(tot+per-1)//per)
        pg = max(0,min(pg,tp-1)); ch = ks[pg*per:(pg+1)*per]
        lines = ["<blockquote>","👤 <b>Pengguna</b>","──────────────────────",f"Total: <b>{tot}</b>",""]
        for i,k in enumerate(ch,start=pg*per+1): lines.append(f"{i}. 👤 {users[k].get('first_name') or '-'}")
        lines += ["","──────────────────────",f"Hal {pg+1}/{tp}","──────────────────────","</blockquote>"]
        rows = []
        for k in ch:
            n = users.get(k,{}).get("first_name") or "-"
            rows.append([B(f"👤 {n}",f"admin|user|{k}|{pg}",style="primary")])
        nav = []
        if pg > 0: nav.append(B("◀ Prev",f"admin|users|{pg-1}",style="primary"))
        nav.append(B(f"{pg+1}/{tp}","noop",style="primary"))
        if pg < tp-1: nav.append(B("Next ▶",f"admin|users|{pg+1}",style="primary"))
        if nav: rows.append(nav)
        rows.append([B("🔄 Refresh",f"admin|users|{pg}",style="success"),B("🔙 Kembali","admin|menu",style="danger")])
        try: await q.edit_message_text("\n".join(lines),reply_markup=InlineKeyboardMarkup(rows),parse_mode="HTML")
        except: pass
        return
    if d.startswith("admin|user|"):
        if not is_owner(uid): return
        p = d.split("|")
        if len(p)<4: return
        tu = p[2]
        try: pg = int(p[3])
        except: pg = 0
        users = load_json(USERS_FILE,{}); uu = users.get(str(tu),{})
        n = uu.get("first_name") or "-"; un = uu.get("username") or "-"
        ls = (uu.get("last_seen") or "-")[:10]
        sb = get_bal(tu)
        txt = (f"<blockquote>👤 <b>{n}</b>\n├ Username : @{un if un != '-' else '-'}\n"
               f"├ Chat ID : <code>{tu}</code>\n├ Bergabung : {ls}\n╰ Saldo : <b>{rupiah(sb)}</b></blockquote>")
        kb = InlineKeyboardMarkup([[B("🔄 Refresh",f"admin|user|{tu}|{pg}",style="success")],
            [B("🔙 Kembali",f"admin|users|{pg}",style="danger")]])
        try: await q.edit_message_text(txt,reply_markup=kb,parse_mode="HTML")
        except: pass
        return
    if d == "admin|bc":
        if not is_owner(uid): return
        c.user_data["bc_wait"] = True
        try: await q.edit_message_text("<blockquote>📢 <b>BROADCAST PENGUMUMAN</b>\n\nSilakan ketik pesan pengumuman yang ingin dikirim ke semua user.\n\n<i>Pesan akan dikirim ke seluruh user bot (kecuali yang memblokir bot).</i></blockquote>",
            reply_markup=InlineKeyboardMarkup([[B("❌ Batal","admin|menu",style="danger")]]),parse_mode="HTML")
        except: pass
        return
    if d == "bc_send":
        if not is_owner(uid): return
        mt = c.user_data.get("bc_text","")
        if not mt: await q.answer("Kosong",show_alert=True); return
        try: await q.edit_message_text("📤 Mengirim broadcast...",parse_mode="HTML")
        except: pass
        users = load_json(USERS_FILE,{}); ok = 0; fl = 0
        for tu in users.keys():
            try:
                await c.bot.send_message(chat_id=int(tu),text=mt,parse_mode="HTML"); ok += 1
            except: fl += 1
            await asyncio.sleep(0.05)
        c.user_data["bc_text"] = ""; c.user_data["bc_wait"] = False
        try: await q.edit_message_text(f"<blockquote>✅ <b>Broadcast Selesai</b>\n\n├ Sukses : <b>{ok}</b>\n╰ Gagal  : <b>{fl}</b>\n\n❖ <i>Pesan berhasil dikirim ke user yang tidak memblokir bot</i> ❖</blockquote>",
            reply_markup=InlineKeyboardMarkup([[B("🔙 Kembali","admin|menu",style="danger")]]),parse_mode="HTML")
        except: pass
        return

    if d.startswith("extend|"):
        if c.user_data.get("created_in_session"): return
        sk = d.split("|")[1]
        if sk not in SERVERS: await chat.send_message("❌ Server tidak valid.",parse_mode="HTML"); return
        try: await q.edit_message_reply_markup(reply_markup=kb_srv_lock())
        except: pass
        c.user_data["extend_step"] = "username"; c.user_data["extend_data"] = {"server_key":sk}
        await chat.send_message("👤 Masukkan username akun yang ingin diperpanjang :",parse_mode="HTML")
        return
    if d.startswith("buat|"):
        if c.user_data.get("created_in_session"): return
        sk = d.split("|")[1]
        if sk not in SERVERS: await chat.send_message("❌ Server tidak valid.",parse_mode="HTML"); return
        used,mx = get_slot_info(sk)
        s = SERVERS[sk]
        if used >= mx:
            await chat.send_message(
                f"<blockquote>❌ <b>Slot Penuh</b>\n\n"
                f"Server {s.get('name','-')}\n"
                f"Slot tersedia: <b>{used}/{mx}</b>\n\n"
                f"Silakan pilih server lain.</blockquote>",
                parse_mode="HTML"); return
        mode = c.user_data.get("mode","buat")
        try: await q.edit_message_reply_markup(reply_markup=kb_srv_lock())
        except: pass
        if mode == "trial":
            if trial_left(uid) <= 0:
                await chat.send_message("🚫 Batas trial hari ini telah tercapai.\nSilakan coba lagi besok.",
                    reply_markup=InlineKeyboardMarkup([[B("🔙 Kembali","menu|main",style="danger")]]),
                    parse_mode="HTML")
                return
            use_trial(uid)
            uq = ''.join(random.choices(string.ascii_lowercase+string.digits,k=4))
            c.user_data.clear(); c.user_data["created_in_session"] = True
            await do_create(chat,uid,u.effective_user,f"trial-{uq}",f"trial{uq}",1,is_trial=True,sk=sk)
            return
        else:
            c.user_data["buat_step"] = "username"; c.user_data["buat_data"] = {"server_key":sk,"proto":"ssh"}
            await chat.send_message("👤 Masukkan username akun :",parse_mode="HTML")
            return
    if d.startswith("buatvmess|") or d.startswith("buatvless|") or d.startswith("buattrojan|"):
        if c.user_data.get("created_in_session"): return
        proto = d.split("|")[0].replace("buat","")
        sk = d.split("|")[1]
        if sk not in SERVERS: await chat.send_message("❌ Server tidak valid.",parse_mode="HTML"); return
        used,mx = get_slot_info(sk)
        s = SERVERS[sk]
        if used >= mx:
            await chat.send_message(
                f"<blockquote>❌ <b>Slot Penuh</b>\n\n"
                f"Server {s.get('name','-')}\n"
                f"Slot tersedia: <b>{used}/{mx}</b>\n\n"
                f"Silakan pilih server lain.</blockquote>",
                parse_mode="HTML"); return
        mode = c.user_data.get("mode","buat")
        try: await q.edit_message_reply_markup(reply_markup=kb_srv_lock())
        except: pass
        if mode == "trial":
            if trial_left(uid) <= 0:
                await chat.send_message("🚫 Batas trial hari ini telah tercapai.\nSilakan coba lagi besok.",
                    reply_markup=InlineKeyboardMarkup([[B("🔙 Kembali","menu|main",style="danger")]]),
                    parse_mode="HTML")
                return
            use_trial(uid)
            uq = ''.join(random.choices(string.ascii_lowercase+string.digits,k=4))
            c.user_data.clear(); c.user_data["created_in_session"] = True
            await do_create_xray(chat,uid,u.effective_user,f"trial-{uq}",f"trial{uq}",1,sk,proto,is_trial=True)
            return
        c.user_data["proto"] = proto
        c.user_data["buat_step"] = "username"
        c.user_data["buat_data"] = {"server_key":sk,"proto":proto}
        await chat.send_message("👤 Masukkan username akun :",parse_mode="HTML")
        return

    if d == "my_accs":
        accs = []
        for a in get_user_accs(uid):
            if a.get("is_trial"): continue
            try:
                ed = datetime.strptime(a["exp"],"%Y-%m-%d").date()
                if (ed-datetime.now().date()).days < 0: continue
            except: continue
            accs.append(a)
        hdr = ["<blockquote>","💻 <b>AKUN SAYA</b>","───────────────────────","",
               f"📭 Total Akun : <b>{len(accs)}</b>",""]
        if not accs: hdr += ["Belum ada akun premium.","Silakan buat akun terlebih dahulu.",""]
        hdr += ["───────────────────────","</blockquote>"]
        if not accs:
            rows = [[B("➕ BUAT AKUN","buat_akun",style="primary")],[B("🔙 KEMBALI","menu|main",style="danger")]]
        else:
            rows = []
            for a in accs[:20]:
                un_d = a.get("username",""); rk = a.get("_key", un_d)
                b = get_block_info(un_d)
                lb = f"🚫 {un_d} (BLOCK)" if b else f"👤 {un_d}"
                rows.append([B(lb, f"acc_detail|{rk}", style="primary")])
            rows.append([B("🔙 KEMBALI","menu|main",style="danger")])
        try: await q.edit_message_text("\n".join(hdr),reply_markup=InlineKeyboardMarkup(rows),parse_mode="HTML")
        except: pass
        return
    if d.startswith("acc_detail|"):
        un = d.split("|",1)[1]
        a = get_acc(un); real_key = un
        if not a:
            for pfx in ["ssh_","vmess_","vless_","trojan_"]:
                a = get_acc(f"{pfx}{un}")
                if a: real_key = f"{pfx}{un}"; break
        if not a or a.get("user_id") != uid: await q.answer("No", show_alert=True); return
        proto = a.get("proto","ssh")
        if proto == "ssh":
            dl = f"{TRIAL_DURATION_MIN} Minute" if a.get("is_trial") else f"{a.get('days',30)} Hari"
            ref = 0 if (a.get("is_trial") or int(a.get("harga",0))<=0) else hitung_refund(a)
            cap = acc_caption(a.get("username",un),a['password'],a['exp'],dl,a.get('limit_ip',1),a.get('manual',False),a.get('is_trial',False),a.get('server_key','sg_1ip'))
            b = get_block_info(a.get("username",un))
            if b:
                try:
                    ua = datetime.strptime(b["unblock_at"],"%Y-%m-%d %H:%M:%S")
                    total_min = max(0, int((ua - datetime.now()).total_seconds() // 60))
                    cap += f"\n\n🚫 <b>AKUN SEDANG DIBLOKIR</b>\n├ Alasan: Melebihi limit IP\n╰ Terbuka otomatis dalam: {total_min//60}j {total_min%60}m"
                except: pass
            elif ref > 0: cap += f"\n\n💰 <b>Refund: {rupiah(ref)}</b>"
            else: cap += "\n\n💰 <i>Refund: Rp 0</i>"
        else:
            xcred = a.get("uuid") or a.get("password","")
            xun = a.get("username",un)
            xsk = a.get('server_key','sg_1ip')
            ref = 0 if a.get("is_trial") else hitung_refund(a)
            cap = xray_caption(proto,xun,a.get("password",""),xcred,a['exp'],a.get('days',30),xsk,a.get('is_trial',False))
            if ref > 0: cap += f"\n\n💰 <b>Refund: {rupiah(ref)}</b>"
            else: cap += "\n\n💰 <i>Refund: Rp 0</i>"
        try: await q.edit_message_text(cap, reply_markup=kb_acc_det(real_key), parse_mode="HTML")
        except: pass
        return
    if d.startswith("del_acc|"):
        un = d.split("|",1)[1]
        real_key = un; a = get_acc(un)
        if not a:
            for pfx in ["ssh_","vmess_","vless_","trojan_"]:
                a = get_acc(f"{pfx}{un}")
                if a: real_key = f"{pfx}{un}"; break
        if not a or a.get("user_id") != uid: await q.answer("No", show_alert=True); return
        ref = 0 if (a.get("is_trial") or int(a.get("harga",0))<=0) else hitung_refund(a)
        await _del_acc(uid, real_key, u.effective_user, chat)
        try: await q.delete_message()
        except: pass
        sb = get_bal(uid)
        dun = a.get("username", un)
        srv_name = a.get("server","-")
        try:
            ed = datetime.strptime(a["exp"],"%Y-%m-%d").date()
            sh = max(0,(ed-datetime.now().date()).days)
        except: sh = 0
        th = int(a.get("days",30))
        pct = int(round((sh/th)*100)) if th > 0 else 0
        msg_del = ("<blockquote>✅ <b>Akun Dihapus</b>\n\n"
                   f"👤 <b>Akun</b>\n"
                   f"├ User: <code>{dun}</code>\n"
                   f"├ Server: <b>{srv_name}</b>\n"
                   f"├ Durasi: <b>{th} Hari</b>\n"
                   f"╰ Harga: <b>{rupiah(int(a.get('harga',0)))}</b>\n\n")
        if ref > 0:
            msg_del += (f"💰 <b>Refund</b>\n"
                       f"├ Sisa: <b>{sh}/{th} hari</b>\n"
                       f"├ Persen: <b>{pct}%</b>\n"
                       f"╰ Refund: <b>{rupiah(ref)}</b>\n\n"
                       f"💼 Saldo: <b>{rupiah(sb)}</b>\n\n"
                       f"❖ <i>Refund masuk ke saldo</i> ❖")
        msg_del += "</blockquote>"
        try: await chat.send_message(msg_del, parse_mode="HTML")
        except: pass
        return

async def msg(u,c):
    uid = u.effective_user.id
    track_user(u.effective_user)
    t = (u.message.text or "").strip()

    bf = c.user_data.get("backup_field")
    if bf and is_owner(uid):
        c.user_data["backup_field"] = None
        if bf == "token":
            try: await u.message.delete()
            except: pass
        old = load_backup_conf(); conf = dict(old); err = None
        if bf == "user":
            if not re.match(r'^[a-zA-Z0-9-]+$',t): err = "Invalid"
            else: conf["GH_USER"] = t
        elif bf == "repo":
            if not re.match(r'^[a-zA-Z0-9._-]+$',t): err = "Invalid"
            else: conf["GH_REPO"] = t
        elif bf == "token":
            if not (t.startswith("ghp_") or t.startswith("github_pat_")) or len(t)<20: err = "Format: ghp_xxx"
            else: conf["GH_TOKEN"] = t
        elif bf == "email":
            if "@" not in t or "." not in t: err = "Invalid"
            else: conf["GH_EMAIL"] = t
        if err:
            await u.message.reply_text(f"❌ {err}\n\nCoba lagi:",parse_mode="HTML")
            c.user_data["backup_field"] = bf; return
        changed = (old.get(f"GH_{bf.upper()}") != conf.get(f"GH_{bf.upper()}"))
        save_backup_conf(conf["GH_USER"],conf["GH_REPO"],conf["GH_TOKEN"],conf["GH_EMAIL"])
        allok = all([conf["GH_USER"],conf["GH_REPO"],conf["GH_TOKEN"],conf["GH_EMAIL"]])
        if allok:
            nt = "⏳ <b>Pull dari GitHub...</b>"
            if changed: nt = "⏳ <b>Field berubah!</b>"
            notify = await u.message.reply_text(nt,parse_mode="HTML")
            if changed:
                if os.path.exists("/root/vpnbot_backup"):
                    try: shutil.rmtree("/root/vpnbot_backup")
                    except: pass
                subprocess.run("crontab -l 2>/dev/null | grep -v vpnbot_backup.sh | crontab -",shell=True)
            ok,info = await asyncio.to_thread(setup_backup_env,conf["GH_USER"],conf["GH_REPO"],conf["GH_TOKEN"],conf["GH_EMAIL"])
            if ok:
                cc,sc = await asyncio.to_thread(restore_ssh_users)
                try: await notify.delete()
                except: pass
                tag = "🔄 <b>Re-setup</b>" if changed else "✅ <b>Disimpan!</b>"
                await u.message.reply_text(f"{tag}\n\n<blockquote>✅ Auto backup\n✅ JSON: <b>{info}</b>\n✅ User OS: <b>{cc}</b>\n</blockquote>\n\n" + backup_config_text(),
                    reply_markup=kb_backup(),parse_mode="HTML")
            else:
                try: await notify.delete()
                except: pass
                await u.message.reply_text(f"❌ <b>Gagal</b>\n<code>{str(info)[:200]}</code>",reply_markup=kb_backup(),parse_mode="HTML")
        else:
            await u.message.reply_text(f"✅ <b>Disimpan!</b>\n\n" + backup_config_text(),reply_markup=kb_backup(),parse_mode="HTML")
        return

    if c.user_data.get("srv_add_step") == "input" and is_owner(uid):
        c.user_data["srv_add_step"] = None
        p = t.split("|")
        if len(p) != 3:
            await u.message.reply_text("❌ <b>Format salah!</b>\n\nHarus: <code>nama|ip|port</code>",parse_mode="HTML")
            c.user_data["srv_add_step"] = "input"; return
        nama, ip, ps = p[0].strip(),p[1].strip(),p[2].strip()
        try: port = int(ps)
        except: port = 22
        kn = re.sub(r'[^a-z0-9]','_',nama.lower())[:15] or f"srv_{int(time.time())}"
        if kn in SERVERS: kn = f"{kn}_{random.randint(100,999)}"
        notify = await u.message.reply_text(f"⏳ <b>Testing {ip}:{port}...</b>",parse_mode="HTML")
        is_local = ip in ("127.0.0.1","localhost","")
        if is_local:
            try: await notify.delete()
            except: pass
            SERVERS[kn] = {"name":nama,"ssh_host":ip,"ssh_port":port,"ssh_user":"root",
                "ssh_key":SSH_KEY_PATH,"city":"-","isp":"-","ssh_ovpn":nama,
                "domain":None,"price_day":None,"price_month":None,
                "ip_limit":None,"slot_max":None,"quota_gb":None}
            save_servers()
            await u.message.reply_text(f"<blockquote>✅ <b>{nama} ditambahkan</b>\n\n⚠️ Lengkapi data</blockquote>",parse_mode="HTML")
            asyncio.create_task(sync_push_async()); return
        kf, pk = gen_ssh_key(kn)
        to = await asyncio.to_thread(test_ssh_key,kf,ip,port)
        try: await notify.delete()
        except: pass
        if not to:
            c.user_data["srv_add_pending"] = {"key":kn,"nama":nama,"ip":ip,"port":port,"ssh_key":kf}
            await u.message.reply_text(
                f"<blockquote>🔐 <b>PERLU SSH KEY</b>\n───────────────────────\n"
                f"Host: <code>{ip}:{port}</code>\n\nPublic key:\n\n<code>{pk}</code>\n\n"
                f"Copy ke VPS target, lalu test ulang:</blockquote>",
                reply_markup=InlineKeyboardMarkup([
                    [B("✅ Sudah, Test Ulang",f"srv_add_retry|{kn}",style="success")],
                    [B("❌ Batal","admin|srv",style="danger")]]),parse_mode="HTML")
            return
        SERVERS[kn] = {"name":nama,"ssh_host":ip,"ssh_port":port,"ssh_user":"root",
            "ssh_key":kf,"city":"-","isp":"-","ssh_ovpn":nama,
            "domain":None,"price_day":None,"price_month":None,
            "ip_limit":None,"slot_max":None,"quota_gb":None}
        save_servers()
        await u.message.reply_text(f"<blockquote>✅ <b>{nama} ditambahkan</b>\n\n⚠️ Lengkapi data</blockquote>",parse_mode="HTML")
        asyncio.create_task(sync_push_async()); return

    se = c.user_data.get("srv_edit")
    if se and is_owner(uid):
        k = se.get("key"); f = se.get("field"); val = t.strip()
        if k not in SERVERS:
            c.user_data["srv_edit"] = None
            await u.message.reply_text("❌ No",parse_mode="HTML"); return
        s = SERVERS[k]
        try:
            if f == "name":
                if len(val)<3: await u.message.reply_text("❌ Min 3 char",parse_mode="HTML"); return
                s["name"] = val; out = f"Nama → <b>{val}</b>"
            elif f == "city":
                if len(val)<2: await u.message.reply_text("❌ Min 2 char",parse_mode="HTML"); return
                s["city"] = val; out = f"City → <b>{val}</b>"
            elif f == "isp":
                if len(val)<2: await u.message.reply_text("❌ Min 2 char",parse_mode="HTML"); return
                s["isp"] = val; out = f"ISP → <b>{val}</b>"
            elif f == "price_month":
                a = int(re.sub(r'[^0-9]','',val))
                if a<=0: await u.message.reply_text("❌ Invalid",parse_mode="HTML"); return
                s["price_month"] = a; s["price_day"] = max(1,int(round(a/30)))
                out = f"Bulanan → <b>{rupiah(a)}</b>\nHarian → <b>{rupiah(s['price_day'])}</b>"
            elif f == "quota_gb":
                a = int(re.sub(r'[^0-9]','',val))
                if a<=0: await u.message.reply_text("❌ Invalid",parse_mode="HTML"); return
                s["quota_gb"] = a; out = f"Quota → <b>{a} GB</b>"
            elif f == "ip_limit":
                a = int(re.sub(r'[^0-9]','',val))
                if a<=0: await u.message.reply_text("❌ Invalid",parse_mode="HTML"); return
                s["ip_limit"] = a; out = f"Limit IP → <b>{a}</b>"
            elif f == "slot_max":
                a = int(re.sub(r'[^0-9]','',val))
                if a<=0: await u.message.reply_text("❌ Invalid",parse_mode="HTML"); return
                s["slot_max"] = a; out = f"Slot → <b>{a}</b>"
            elif f == "domain":
                s["domain"] = val; out = f"Domain → <b>{val}</b>"
            else:
                c.user_data["srv_edit"] = None
                await u.message.reply_text("❌ Invalid",parse_mode="HTML"); return
            save_servers(); c.user_data["srv_edit"] = None
            comp = is_server_complete(s)
            info = "✅ Lengkap" if comp else "⚠️ Masih ada kosong"
            await u.message.reply_text(f"✅ <b>{out}</b>\n\n{info}",
                reply_markup=InlineKeyboardMarkup([[B("◀️ Kembali",f"srv_edit|{k}",style="primary")]]),parse_mode="HTML")
            asyncio.create_task(sync_push_async()); return
        except Exception as e:
            await u.message.reply_text(f"❌ {e}",parse_mode="HTML"); return

    if c.user_data.get("bc_wait") and is_owner(uid):
        c.user_data["bc_wait"] = False; c.user_data["bc_text"] = t
        await u.message.reply_text(f"<blockquote>📢 <b>PREVIEW BROADCAST</b>\n\n{t}\n\nKirim pesan ini ke semua user?</blockquote>",
            reply_markup=InlineKeyboardMarkup([[B("✅ Kirim","bc_send",style="success")],
                [B("❌ Batal","admin|menu",style="danger")]]),parse_mode="HTML")
        return

    step = c.user_data.get("buat_step")
    if step:
        data = c.user_data.get("buat_data",{})
        if step == "username":
            if not valid_username(t):
                await u.message.reply_text("🚫 Username minimal 5 angka !!")
                await u.message.reply_text("👤 Masukkan username akun :")
                return
            if is_username_taken(t):
                await u.message.reply_text(f"🚫 Username {t} sudah ada !!")
                await u.message.reply_text("👤 Masukkan username akun :")
                return
            data["username"] = t; c.user_data["buat_data"] = data; c.user_data["buat_step"] = "password"
            await u.message.reply_text("🔑 Masukkan password akun :")
            return
        if step == "password":
            if not valid_password(t):
                await u.message.reply_text("🚫 Password minimal 5 angka !!")
                await u.message.reply_text("🔑 Masukkan password akun :")
                return
            data["password"] = t; c.user_data["buat_data"] = data; c.user_data["buat_step"] = "durasi"
            await u.message.reply_text("📆 Masukkan masa aktif 1-30 (hari) :")
            return
        if step == "durasi":
            valid = t.isdigit() and (HARI_MIN <= int(t) <= HARI_MAX)
            if not valid:
                await u.message.reply_text("🚫 Masa aktif tidak valid.\n📅 Masukkan 1–30 hari Contoh : 3")
                await u.message.reply_text("📆 Masukkan masa aktif 1-30 (hari) :")
                return
            hari = int(t)
            un = data.get("username"); pw = data.get("password")
            sk = data.get("server_key","sg_1ip"); proto = data.get("proto","ssh")
            price = get_price(hari,sk)
            c.user_data["buat_step"] = None; c.user_data["buat_data"] = {}
            if not is_backup_ready():
                await u.message.reply_text("⚠️ <b>Backup belum siap</b>",parse_mode="HTML"); return
            if get_bal(uid) < price:
                kurang = price - get_bal(uid)
                msg_saldo = (f"<blockquote>❌ <b>Saldo Tidak Cukup</b>\n\n"
                    f"💰 Saldo Anda : <b>{rupiah(get_bal(uid))}</b>\n"
                    f"💵 Harga Akun : <b>{rupiah(price)}</b>\n"
                    f"📉 Kurang     : <b>{rupiah(kurang)}</b>\n\n"
                    "Silakan topup saldo melalui menu\n"
                    "Tombol 💰 TOPUP SALDO.</blockquote>")
                kb = InlineKeyboardMarkup([[B("💰 TOPUP SALDO","isi_saldo",style="success")],[B("🔙 Kembali","menu|main",style="danger")]])
                await u.message.reply_text(msg_saldo,reply_markup=kb,parse_mode="HTML"); return
            c.user_data["created_in_session"] = True
            if proto == "ssh":
                await do_create(u.effective_chat,uid,u.effective_user,un,pw,hari,sk=sk)
            else:
                await do_create_xray(u.effective_chat,uid,u.effective_user,un,pw,hari,sk,proto)
            return

    es = c.user_data.get("extend_step")
    if es:
        data = c.user_data.get("extend_data",{})
        sk = data.get("server_key","sg_1ip")
        if es == "username":
            if not is_username_taken(t):
                await u.message.reply_text("🚫 Akun tidak ditemukan.")
                await u.message.reply_text("👤 Masukkan username akun :")
                return
            a = get_acc(t)
            if not a or a.get("user_id") != uid:
                await u.message.reply_text("🚫 Bukan akun Anda.")
                await u.message.reply_text("👤 Masukkan username akun :")
                return
            if a.get("is_trial"):
                await u.message.reply_text("🚫 Akun trial tidak bisa diperpanjang.")
                await u.message.reply_text("👤 Masukkan username akun :")
                return
            data["username"] = t; c.user_data["extend_data"] = data; c.user_data["extend_step"] = "password"
            await u.message.reply_text("🔑 Masukkan password akun :")
            return
        if es == "password":
            a = get_acc(data.get("username"))
            if not a or a.get("password") != t:
                await u.message.reply_text("🚫 Password salah.")
                await u.message.reply_text("🔑 Masukkan password akun :")
                return
            c.user_data["extend_step"] = "durasi"
            try:
                ed = datetime.strptime(a["exp"],"%Y-%m-%d").date()
                sisa = max(0,(ed-datetime.now().date()).days)
            except: sisa = 0
            await u.message.reply_text(f"📆 Masukkan masa aktif tambahan 1-30 (hari) :\nSisa masa aktif: {sisa} hari")
            return
        if es == "durasi":
            valid = t.isdigit() and (HARI_MIN <= int(t) <= HARI_MAX)
            if not valid:
                await u.message.reply_text("🚫 Masa aktif tidak valid.\n📅 Masukkan 1–30 hari Contoh : 3")
                await u.message.reply_text("📆 Masukkan masa aktif 1-30 (hari) :")
                return
            hari = int(t)
            un = data.get("username")
            c.user_data["extend_step"] = None; c.user_data["extend_data"] = {}
            c.user_data["created_in_session"] = True
            await do_extend(u.effective_chat,uid,u.effective_user,un,hari,sk)
            return

async def handle_photo(u,c):
    await u.message.reply_text("Gunakan /start",reply_markup=ReplyKeyboardRemove())

async def post_init(app):
    try: await app.bot.set_my_commands([BotCommand("start","⌂ Menu")])
    except: pass
    asyncio.create_task(auto_cleanup())
    ok,msg = await asyncio.to_thread(ssh_test,"sg_1ip")
    logger.info(f"[STARTUP] {msg}")
    if is_backup_ready():
        try:
            c = load_backup_conf()
            ok,r = await asyncio.to_thread(setup_backup_env,c["GH_USER"],c["GH_REPO"],c["GH_TOKEN"],c["GH_EMAIL"])
            if ok: logger.info(f"[STARTUP-PULL] {r}")
        except Exception as e: logger.error(f"[STARTUP-PULL] {e}")
    try:
        cc,ss = await asyncio.to_thread(restore_ssh_users)
        if cc > 0: logger.info(f"[RESTORE] {cc}")
    except Exception as e: logger.error(f"restore: {e}")

def main():
    app = Application.builder().token(BOT_TOKEN).post_init(post_init).build()
    app.add_handler(CommandHandler("start",start))
    app.add_handler(CallbackQueryHandler(cb))
    app.add_handler(MessageHandler(filters.PHOTO,handle_photo))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND,msg))
    app.run_polling(allowed_updates=Update.ALL_TYPES)

if __name__ == "__main__":
    main()
BOTPYEOF
chmod +x /root/bot.py

python3 -m py_compile /root/bot.py 2>&1 | tee /root/bot_compile.log >/dev/null
[ -s /root/bot_compile.log ] && echo -e "  ${RED}❌ Bot error${NC}" || echo -e "  ${GREEN}✓${NC}  Bot.py OK"

# 8. START BOT
cat > /etc/systemd/system/vpnbot.service << 'SVCEOF'
[Unit]
Description=SANSXML VPN Bot
After=network.target
[Service]
Type=simple
WorkingDirectory=/root
ExecStart=/usr/bin/python3 /root/bot.py
Restart=always
RestartSec=5
StandardOutput=null
StandardError=null
[Install]
WantedBy=multi-user.target
SVCEOF
systemctl daemon-reload
systemctl enable vpnbot >/dev/null 2>&1
systemctl restart vpnbot
sleep 3

# 9. MENU VPS
echo ""
echo -e "  ${YELLOW}▸ Install Menu VPS${NC}"

cat > /usr/local/bin/sansxml-menu << 'MENUEOF'
#!/bin/bash
PU='\033[38;5;135m'; PU2='\033[38;5;177m'; CY='\033[38;5;51m'
PK='\033[38;5;213m'; WH='\033[1;37m'; GR='\033[38;5;46m'
RE='\033[38;5;196m'; YE='\033[38;5;226m'; GY='\033[38;5;245m'; N='\033[0m'
W=62
get_ip(){ hostname -I 2>/dev/null | awk '{print $1}'; }
get_uptime(){ local s=$(cat /proc/uptime|awk '{print int($1)}'); echo "$((s/86400))d $(((s%86400)/3600))h $(((s%3600)/60))m"; }
get_ram_pct(){ local t=$(grep MemTotal /proc/meminfo|awk '{print $2}'); local a=$(grep MemAvailable /proc/meminfo|awk '{print $2}'); awk "BEGIN{printf \"%d\",($t-$a)/$t*100}"; }
get_ram_h(){ local t=$(grep MemTotal /proc/meminfo|awk '{print $2}'); local a=$(grep MemAvailable /proc/meminfo|awk '{print $2}'); awk "BEGIN{printf \"%.1fG/%.1fG\",($t-$a)/1024/1024,$t/1024/1024}"; }
get_disk_pct(){ df -h / | tail -1 | awk '{print $5}' | tr -d '%'; }
get_disk_h(){ echo "$(df -h /|tail -1|awk '{print $3}')/$(df -h /|tail -1|awk '{print $2}')"; }
get_bot_users(){ local f="/root/vpnbot_users.json"; [ ! -f "$f" ] && { echo 0; return; }; python3 -c "import json
try: print(len(json.load(open('$f'))))
except: print(0)" 2>/dev/null || echo 0; }
get_accounts(){ local f="/root/vpnbot_accounts.json"; [ ! -f "$f" ] && { echo 0; return; }; python3 -c "import json
from datetime import datetime
try:
    d=json.load(open('$f')); t=datetime.now().date()
    c=sum(1 for a in d.values() if (datetime.strptime(a['exp'],'%Y-%m-%d').date()-t).days>=0)
    print(c)
except: print(0)" 2>/dev/null || echo 0; }
get_blocked(){ local f="/root/vpnbot_blocked.json"; [ ! -f "$f" ] && { echo 0; return; }; python3 -c "import json
try: print(len(json.load(open('$f'))))
except: print(0)" 2>/dev/null || echo 0; }
get_online(){ local c=0; for u in $(awk -F: '$3>=1000 && $3<60000 {print $1}' /etc/passwd 2>/dev/null); do
    if who 2>/dev/null | grep -q "^$u "; then c=$((c+1)); fi; done; echo "$c"; }
get_traffic_today(){ command -v vnstat >/dev/null 2>&1 || { echo "N/A"; return; }
    vnstat --json d 1 2>/dev/null | python3 -c "import sys,json
try:
    d=json.load(sys.stdin); ifs=d.get('interfaces',[])
    if ifs:
        days=ifs[0].get('traffic',{}).get('day',[])
        if days:
            r=days[-1].get('rx',0)/1024**3; t=days[-1].get('tx',0)/1024**3
            print(f'{r+t:.2f} GB'); exit()
    print('0 GB')
except: print('0 GB')" 2>/dev/null || echo "0 GB"; }
get_traffic_month(){ command -v vnstat >/dev/null 2>&1 || { echo "N/A"; return; }
    vnstat --json m 1 2>/dev/null | python3 -c "import sys,json
try:
    d=json.load(sys.stdin); ifs=d.get('interfaces',[])
    if ifs:
        m=ifs[0].get('traffic',{}).get('month',[])
        if m:
            r=m[-1].get('rx',0)/1024**3; t=m[-1].get('tx',0)/1024**3
            print(f'{r+t:.2f} GB'); exit()
    print('0 GB')
except: print('0 GB')" 2>/dev/null || echo "0 GB"; }
box_top(){ local t="$1"; local tl=${#t}; local fill=$((W-tl-5)); local l=""
    for ((i=0;i<fill;i++)); do l="${l}─"; done
    printf "${PU}╭─[${PK} %s ${PU}]${l}╮${N}\n" "$t"; }
box_mid(){ local t="$1"; local tl=${#t}; local fill=$((W-tl-5)); local l=""
    for ((i=0;i<fill;i++)); do l="${l}─"; done
    printf "${PU}├─[${PK} %s ${PU}]${l}┤${N}\n" "$t"; }
box_bot(){ local l=""; for ((i=0;i<W;i++)); do l="${l}─"; done
    printf "${PU}╰${l}╯${N}\n"; }
box_row(){ printf " %b\n" "$1"; }
kv(){ local key=$(printf '%-9s' "$1"); printf " ${GY}%s${N} ${PK}›${N} ${WH}%s${N}\n" "$key" "$2"; }
kvc(){ local key=$(printf '%-9s' "$1"); printf " ${GY}%s${N} ${PK}›${N} ${3}%s${N}\n" "$key" "$2"; }
bar(){ local p=$1; local f=$((p/10)); local o=""; for ((i=1;i<=10;i++)); do [ $i -le $f ] && o="${o}█" || o="${o}░"; done; echo "$o"; }
show_banner(){ local tgl=$(date '+%d %b %Y  %H:%M:%S'); echo ""
    local l=""; for ((i=0;i<62;i++)); do l="${l}─"; done
    printf "${PU}╭${l}╮${N}\n"
    printf "          ${PK}SC ${WH}SANSXML VPN BOT STORE${N}\n"
    printf "${PU}╰${l}╯${N}\n"
    echo -e "           ${PU2}sansxml${N}  ${CY}◆${N}  ${PU2}VPS${N}  ${CY}◆${N}  ${WH}${tgl}${N}"; echo ""; }
show_menu(){ clear
    local ip=$(get_ip); local up=$(get_uptime)
    local os=$(grep PRETTY_NAME /etc/os-release|cut -d= -f2|tr -d '"')
    local krn=$(uname -r|cut -d- -f1); local core=$(nproc)
    local load=$(cat /proc/loadavg|awk '{print $1, $2, $3}')
    local rp=$(get_ram_pct); local rh=$(get_ram_h); local dp=$(get_disk_pct); local dh=$(get_disk_h)
    local tgl=$(date '+%d %b %Y  %H:%M:%S')
    local bus=$(get_bot_users); local acc=$(get_accounts); local blk=$(get_blocked); local onl=$(get_online)
    local today=$(get_traffic_today); local month=$(get_traffic_month)
    local bot=$(systemctl is-active vpnbot 2>/dev/null); local ws=$(systemctl is-active ws-ssh 2>/dev/null)
    local ssl=$(systemctl is-active stunnel4 2>/dev/null); local udp=$(systemctl is-active udpgw 2>/dev/null)
    local xry=$(systemctl is-active xray 2>/dev/null)
    local d_bot=$([ "$bot" = "active" ] && echo "${GR}●${N}" || echo "${RE}●${N}")
    local d_ws=$([ "$ws" = "active" ] && echo "${GR}●${N}" || echo "${RE}●${N}")
    local d_ssl=$([ "$ssl" = "active" ] && echo "${GR}●${N}" || echo "${RE}●${N}")
    local d_udp=$([ "$udp" = "active" ] && echo "${GR}●${N}" || echo "${RE}●${N}")
    local d_xry=$([ "$xry" = "active" ] && echo "${GR}●${N}" || echo "${RE}●${N}")
    local hl="${GR}GOOD${N}"; [ "$bot" != "active" ] && hl="${RE}BAD${N}"
    show_banner
    box_top "SERVER"
    kv "OS" "$os"; kv "KERNEL" "$krn"
    printf " ${GY}%-9s${N} ${PK}›${N} ${WH}%s vCPU${N}      ${GY}load${N} ${YE}%s${N}\n" "CPU" "$core" "$load"
    printf " ${GY}%-9s${N} ${PK}›${N} ${PU2}%s${N} ${WH}%3s%%${N}  ${GY}%s${N}\n" "RAM" "$(bar $rp)" "$rp" "$rh"
    printf " ${GY}%-9s${N} ${PK}›${N} ${PU2}%s${N} ${WH}%3s%%${N}  ${GY}%s${N}\n" "DISK" "$(bar $dp)" "$dp" "$dh"
    kv "UPTIME" "$up"; kv "TIME" "$tgl"
    box_mid "NETWORK"
    kvc "IP" "$ip" "${GR}"; kvc "STATUS" "● ONLINE" "${GR}"; kv "BANDWIDTH" "0 / 3000 GB"
    box_mid "TRAFFIC"
    kv "TODAY" "$today"; kv "MONTH" "$month"; kv "SPEED" "0 Mbps"
    box_bot; echo ""
    box_top "SERVICES"
    printf " %b ${WH}BOT${N}   %b ${WH}WS-SSH${N}   %b ${WH}SSL${N}   %b ${WH}UDP${N}   %b ${WH}XRAY${N}\n" "$d_bot" "$d_ws" "$d_ssl" "$d_udp" "$d_xry"
    kv "HEALTH" "$hl"; kv "CAPACITY" "50 USER"; kvc "LIVE" "OK" "${GR}"
    box_mid "ACCOUNTS"
    box_row "${GY}SSH${N} ${WH}${acc}${N}   ${GY}ONLINE${N} ${GR}${onl}${N}   ${GY}BLOCK${N} ${WH}${blk}${N}   ${GY}BOT${N} ${WH}${bus}${N}"
    box_bot; echo ""
    box_top "MAIN MENU"
    printf " ${YE}[01]${N} ${WH}%-25s${N} ${YE}[03]${N} ${WH}%s${N}\n" "STOP BOT & CLEAN CACHE" "BANDWIDTH MONITOR"
    printf " ${YE}[02]${N} ${WH}%-25s${N} ${YE}[04]${N} ${WH}%s${N}\n" "VPS INFORMATION" "SERVICE STATUS"
    printf " ${YE}[05]${N} ${WH}%-25s${N} ${YE}[06]${N} ${WH}%s${N}\n" "UBAH TOKEN BOT" "EXIT"
    box_bot; echo ""
    echo -ne "${PK}◆${N} ${PU2}Select${N} ${CY}[1-6]${N} ${PK}›${N} "; }
show_vps_info(){ clear; show_banner; box_top "VPS INFORMATION"
    kv "OS" "$(grep PRETTY_NAME /etc/os-release|cut -d= -f2|tr -d '"')"
    kv "Kernel" "$(uname -r)"; kv "Arch" "$(uname -m)"; kv "Hostname" "$(hostname)"
    box_mid "CPU"; kv "Model" "$(grep 'model name' /proc/cpuinfo|head -1|cut -d: -f2|xargs|cut -c1-38)"
    kvc "Cores" "$(nproc)" "${GR}"; kv "Load" "$(cat /proc/loadavg|awk '{print $1, $2, $3}')"
    box_mid "RAM"
    local tk=$(grep MemTotal /proc/meminfo|awk '{print $2}'); local ak=$(grep MemAvailable /proc/meminfo|awk '{print $2}'); local uk=$((tk-ak))
    kv "Total" "$(awk "BEGIN{printf \"%.1f\",$tk/1024/1024}") GB"
    kv "Used" "$(awk "BEGIN{printf \"%.1f\",$uk/1024/1024}") GB ($(get_ram_pct)%)"
    kv "Free" "$(awk "BEGIN{printf \"%.1f\",($tk-$uk)/1024/1024}") GB"
    box_mid "DISK"
    kv "Total" "$(df -h /|tail -1|awk '{print $2}')"; kv "Used" "$(df -h /|tail -1|awk '{print $3}') ($(get_disk_pct)%)"
    kv "Free" "$(df -h /|tail -1|awk '{print $4}')"
    box_mid "NETWORK"; kvc "Public IP" "$(get_ip)" "${GR}"
    kv "SSH Port" "22"; kv "WS-SSH" "80, 8080"; kv "SSL" "443, 8443"
    kv "UDPGW" "7300"; kv "Xray" "10001-10007"
    box_bot; echo ""; echo -ne "${PK}◆${N} ${PU2}ENTER untuk kembali...${N}"; read; }
show_bandwidth(){ clear; show_banner; box_top "BANDWIDTH MONITOR"
    kv "Hari Ini" "$(get_traffic_today)"; kv "Bulan Ini" "$(get_traffic_month)"
    kvc "Status" "Monitoring Aktif" "${GR}"
    box_bot; echo ""; echo -ne "${PK}◆${N} ${PU2}ENTER untuk kembali...${N}"; read; }
show_services(){ clear; show_banner; box_top "SERVICE STATUS"
    local svcs=("vpnbot:Telegram Bot" "ws-ssh:WS-SSH 80" "ws-ssh-alt:WS-SSH 8080" "stunnel4:SSL Tunnel" "udpgw:UDP Gateway" "xray:Xray VMess/VLESS/Trojan" "ssh:SSH Service")
    for e in "${svcs[@]}"; do
        local s="${e%%:*}"; local l="${e##*:}"
        local st=$(systemctl is-active "$s" 2>/dev/null || echo off)
        if [ "$st" = "active" ]; then printf " ${GR}●${N} ${WH}%-24s${N} ${GR}%s${N}\n" "$l" "$st"
        else printf " ${RE}●${N} ${WH}%-24s${N} ${RE}%s${N}\n" "$l" "$st"; fi
    done
    box_bot; echo ""; echo -ne "${PK}◆${N} ${PU2}ENTER untuk kembali...${N}"; read; }
change_token(){ clear; show_banner; box_top "UBAH TOKEN BOT"
    local curr=$(python3 -c "import json
try: print(json.load(open('/root/vpnbot_config.json')).get('bot_token','-'))
except: print('-')" 2>/dev/null)
    local masked="${curr:0:10}***${curr: -5}"
    kv "Current" "$masked"; box_bot; echo ""
    echo -ne "${PK}◆${N} ${PU2}Token Baru${N} ${PU}›${N} "
    read nt
    [ -z "$nt" ] && { echo -e "${RE}  Dibatalkan${N}"; sleep 1; return; }
    python3 -c "
import json
f='/root/vpnbot_config.json'
d=json.load(open(f))
d['bot_token']='$nt'
json.dump(d,open(f,'w'),indent=2,ensure_ascii=False)
" 2>/dev/null
    echo ""; echo -e "  ${PU2}Restart bot...${N}"
    systemctl restart vpnbot 2>/dev/null; sleep 3
    box_top "STATUS"
    local st=$(systemctl is-active vpnbot 2>/dev/null)
    if [ "$st" = "active" ]; then kvc "Result" "✓ TOKEN DIPERBARUI" "${GR}"
    else kvc "Result" "✗ GAGAL" "${RE}"; fi
    box_bot; echo ""; echo -ne "${PK}◆${N} ${PU2}ENTER untuk kembali...${N}"; read; }
stop_bot_clean(){ clear; show_banner; box_top "STOP BOT & CLEAN CACHE"
    box_row "${YE}Bot akan dimatikan & cache dibersihkan${N}"
    box_mid "AKAN DILAKUKAN"
    box_row "Stop service vpnbot"
    box_row "Clean apt cache & journal"
    box_row "Clean /tmp, /var/tmp, log lama"
    box_row "Drop page cache RAM"
    box_bot; echo ""
    echo -ne "${PK}◆${N} Ketik ${GR}${WH}YES${N} untuk konfirmasi: "
    read c
    [ "$c" != "YES" ] && { echo -e "  ${GR}Dibatalkan${N}"; sleep 1; return; }
    echo ""
    echo -e "  ${PU2}[1/5]${N} Stop bot..."; systemctl stop vpnbot 2>/dev/null; sleep 1
    echo -e "        ${GR}✓ Bot dihentikan${N}"
    echo -e "  ${PU2}[2/5]${N} Clean apt cache..."; apt-get clean >/dev/null 2>&1
    rm -rf /var/cache/apt/archives/*.deb /var/lib/apt/lists/* 2>/dev/null
    echo -e "        ${GR}✓ Apt cache${N}"
    echo -e "  ${PU2}[3/5]${N} Clean journal..."; journalctl --rotate >/dev/null 2>&1; journalctl --vacuum-time=1s >/dev/null 2>&1
    echo -e "        ${GR}✓ Journal${N}"
    echo -e "  ${PU2}[4/5]${N} Clean temp & log..."; rm -rf /tmp/* /var/tmp/* /root/.cache/* 2>/dev/null
    find /var/log -type f \( -name "*.gz" -o -name "*.old" -o -name "*.log.*" \) -delete 2>/dev/null
    truncate -s 0 /var/log/syslog /var/log/auth.log 2>/dev/null
    echo -e "        ${GR}✓ Temp & log${N}"
    echo -e "  ${PU2}[5/5]${N} Drop RAM cache..."; sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
    echo -e "        ${GR}✓ RAM cache${N}"
    echo ""
    box_top "STATUS AKHIR"
    kvc "Bot Telegram" "STOPPED" "${RE}"
    kvc "Disk" "$(df -h / | tail -1 | awk '{print $3}') ($(df -h / | tail -1 | awk '{print $5}'))" "${GR}"
    kvc "RAM" "$(free -h | awk '/^Mem:/{print $3"/"$2}')" "${GR}"
    kvc "Result" "VPS BERSIH" "${GR}"
    box_bot; echo ""
    echo -e "  ${YE}Start bot:${N} ${PK}systemctl start vpnbot${N}"; echo ""
    echo -ne "${PK}◆${N} ${PU2}ENTER untuk kembali...${N}"; read; }
while true; do
    show_menu
    read choice
    case "$choice" in
        1|01) stop_bot_clean ;;
        2|02) show_vps_info ;;
        3|03) show_bandwidth ;;
        4|04) show_services ;;
        5|05) change_token ;;
        6|06) clear
              echo ""; echo -e "${GR}  ✓ Terima kasih! Bot tetap jalan.${N}"
              echo -e "${WH}    Ketik ${PK}sansxml-menu${N}${WH} untuk buka menu lagi.${N}"; echo ""; exit 0 ;;
        *) echo ""; echo -e "  ${RE}Pilihan tidak valid${N}"; sleep 1 ;;
    esac
done
MENUEOF

chmod +x /usr/local/bin/sansxml-menu

cat > /etc/profile.d/sansxml-menu.sh << 'PROFEOF'
if [ -n "$SSH_CONNECTION" ] && [ "$(whoami)" = "root" ] && [ -x /usr/local/bin/sansxml-menu ]; then
    /usr/local/bin/sansxml-menu
fi
PROFEOF
chmod +x /etc/profile.d/sansxml-menu.sh

# 10. DONE
clear
echo ""
echo -e "  ${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${GREEN}        ✓✓✓ INSTALASI SELESAI ✓✓✓${NC}"
echo -e "  ${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
for s in ssh ws-ssh ws-ssh-alt stunnel4 udpgw vpnbot xray; do
    ST=$(systemctl is-active "$s" 2>/dev/null || echo "n/a")
    printf "  %-14s : " "$s"
    [ "$ST" = "active" ] && echo -e "${GREEN}$ST${NC}" || echo -e "${RED}$ST${NC}"
done
echo ""
echo -e "  ${CYAN}Domain${NC} : ${GREEN}$DOMAIN${NC}"
echo -e "  ${CYAN}Bot${NC}    : Cek di Telegram (/start)"
echo -e "  ${CYAN}Log${NC}    : tail -f /root/vpnbot.log"
echo ""
sleep 2
[ -x /usr/local/bin/sansxml-menu ] && exec /usr/local/bin/sansxml-menu
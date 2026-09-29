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
echo -e "  ${CYAN}    SANSXML VPN STORE — AUTO INSTALL v5${NC}"
echo -e "  ${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# 1. CLEANUP TOTAL
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
  rm -f /root/.ssh/id_bot /root/.ssh/id_bot.pub /root/.bash_profile
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
shopt -s checkwinsize
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then debian_chroot=$(cat /etc/debian_chroot); fi
case "$TERM" in xterm-color|*-256color) color_prompt=yes;; esac
if [ "$color_prompt" = yes ]; then
    PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
    PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi
unset color_prompt force_color_prompt
case "$TERM" in xterm*|rxvt*) PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1";; esac
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'; alias grep='grep --color=auto'
fi
alias ll='ls -alF'; alias la='ls -A'; alias l='ls -CF'
[ -f ~/.bash_aliases ] && . ~/.bash_aliases
if ! shopt -oq posix; then
  [ -f /usr/share/bash-completion/bash_completion ] && . /usr/share/bash-completion/bash_completion
  [ -f /etc/bash_completion ] && . /etc/bash_completion
fi
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
( apt-get install -y python3 python3-pip python3-venv sshpass curl wget unzip stunnel4 net-tools cron ufw iptables openssl cmake build-essential git pkg-config bc jq who procps dnsutils vnstat >/dev/null 2>&1 ) & spin $! "Install packages"
( pip3 install --break-system-packages --upgrade "python-telegram-bot>=20" requests qrcode pillow >/dev/null 2>&1 \
    || pip3 install --upgrade "python-telegram-bot>=20" requests qrcode pillow >/dev/null 2>&1 ) & spin $! "Install Telegram API"
( mkdir -p /root/.ssh; chmod 700 /root/.ssh
  [ ! -f /root/.ssh/id_bot ] && ssh-keygen -t ed25519 -f /root/.ssh/id_bot -N "" -q
  cat /root/.ssh/id_bot.pub >> /root/.ssh/authorized_keys
  sort -u /root/.ssh/authorized_keys -o /root/.ssh/authorized_keys
  chmod 600 /root/.ssh/authorized_keys ) & spin $! "Generate SSH key"
( systemctl enable vnstat >/dev/null 2>&1; systemctl restart vnstat >/dev/null 2>&1 ) & spin $! "Enable vnstat"

# 3. VPN SERVICES
echo ""
echo -e "  ${YELLOW}▸ Install VPN services${NC}"

( cat > /usr/local/bin/ws-ssh.py << 'PYEOF'
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
PYEOF
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
  for p in 22 80 443 8080 8443; do ufw allow $p/tcp >/dev/null 2>&1; done
  ufw allow 7300/udp >/dev/null 2>&1; ufw allow 1:65535/udp >/dev/null 2>&1
  ufw --force enable >/dev/null 2>&1 ) & spin $! "Configure firewall"

( systemctl daemon-reload
  systemctl enable ws-ssh ws-ssh-alt stunnel4 >/dev/null 2>&1
  systemctl restart ws-ssh ws-ssh-alt stunnel4
  [ -f /usr/bin/badvpn-udpgw ] && systemctl enable udpgw >/dev/null 2>&1 && systemctl restart udpgw
  sleep 2 ) & spin $! "Start VPN services"

# 4. SSH CONFIG + BANNER
rm -rf /etc/update-motd.d/* 2>/dev/null
cat > /etc/issue.net << 'BEOF'
<br><font color="#ff00aa"><b>                        ▬▬▬▬▬▬ஜ۩۞۩ஜ▬▬▬▬▬▬</b></font><br><font color="#ffffff"><b>                          --- 卐 </b></font><font color="#ffff00"><b>SANSXML VPN STORE</b></font><font color="#ffffff"><b> 卐 ---</b></font><br><font color="#ff00aa"><b>                        ▬▬▬▬▬▬ஜ۩۞۩ஜ▬▬▬▬▬▬</b></font><br><font color="#ffffff"><b>                            ── PREMIUM VPN SERVER ──</b></font><br><font color="#ffffff"><b>                             --- 卍 TERM OF SERVICE 卐 ---</b></font><br><font color="#ffffff"><b>                                      NO MULTI LOGIN !!</b></font><br><font color="#ffffff"><b>                                NO HACKING AND CARDING</b></font><br><font color="#ffff00"><b>                            👉 MULTI LOGIN BANNED 👈</b></font><br><font color="#ff00aa"><b>                        ▬▬▬▬▬▬ஜ۩۞۩ஜ▬▬▬▬▬▬</b></font><br><font color="#ffffff"><b>                    ORDER CONFIG PREMIUM: </b></font><font color="#00ff44"><b>wa.me/6289527419748</b></font><br><font color="#ffffff"><b>                         BOT ORDER VPN: </b></font><font color="#00ff44"><b>t.me/unokwn</b></font><br><br>
BEOF
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

# 5. KONFIG BOT + BACKUP
echo ""
echo -e "  ${YELLOW}▸ Konfigurasi Bot & Backup${NC}"
echo ""
read -r -p "$(echo -e ${GREEN}'  Bot Token Telegram : '${NC})" BOT_TOKEN < /dev/tty
if [ -z "$BOT_TOKEN" ]; then echo -e "  ${RED}❌ Token tidak boleh kosong${NC}"; exit 1; fi

GH_USER="Syahrul7y"
GH_REPO="Backup"
GH_EMAIL="hodamkecil@gmail.com"
GH_TOKEN="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"

cat > /etc/sansxml-backup.conf << GHCFG
GH_USER="${GH_USER}"
GH_REPO="${GH_REPO}"
GH_TOKEN="${GH_TOKEN}"
GH_EMAIL="${GH_EMAIL}"
GHCFG
chmod 600 /etc/sansxml-backup.conf
echo -e "  ${GREEN}✓${NC}  Backup config tersimpan (${GH_USER}/${GH_REPO})"

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

# 6. INSTALL BOT.PY — FULL EMBEDDED
echo ""
echo -e "  ${YELLOW}▸ Install Bot${NC}"
mkdir -p /root

cat > /root/bot.py << 'BOTPYEOF'
#!/usr/bin/env python3
import re, io, json, os, logging, subprocess, asyncio, base64, random, string, socket, shutil, time
from datetime import datetime, timedelta
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, BotCommand, ReplyKeyboardRemove
from telegram.ext import Application, CommandHandler, CallbackQueryHandler, MessageHandler, filters

CONFIG_FILE = "/root/vpnbot_config.json"
def load_config():
    d = {"bot_token":"", "domain":"", "owner_ids":[6144358600], "servers":{}, "ip_limit":2, "block_hours":2}
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
HARI_MIN, HARI_MAX = 1, 365
TRIAL_DURATION_MIN = 30
TRIAL_PER_DAY = 2
MIN_TOPUP = 1000
BLOCK_FILE = "/root/vpnbot_blocked.json"
BLOCK_HOURS = 2
USERS_FILE="/root/vpnbot_users.json"; BAL_FILE="/root/vpnbot_balance.json"
ACCOUNTS_FILE="/root/vpnbot_accounts.json"; TRIAL_FILE="/root/vpnbot_trial.json"
TRX_FILE="/root/vpnbot_trx.json"

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

def get_price(hari, server_key=None):
    if server_key and server_key in SERVERS: srv = SERVERS[server_key]
    else: srv = list(SERVERS.values())[0] if SERVERS else {"price_day": 117}
    return int(srv.get("price_day", 117) or 117) * int(hari)

def is_local_server(server_key):
    if server_key not in SERVERS: return True
    h = (SERVERS[server_key].get("ssh_host") or "127.0.0.1").strip()
    return h in ("127.0.0.1", "localhost", "")

def is_server_complete(srv):
    if not srv: return False
    if not srv.get("price_month") or int(srv.get("price_month", 0)) <= 0: return False
    if not srv.get("ip_limit") or int(srv.get("ip_limit", 0)) <= 0: return False
    if not srv.get("slot_max") or int(srv.get("slot_max", 0)) <= 0: return False
    if not srv.get("domain") or not str(srv.get("domain", "")).strip(): return False
    return True

def get_active_servers(): return {k: v for k, v in SERVERS.items() if is_server_complete(v)}

def load_backup_conf():
    d = {"GH_USER":"", "GH_REPO":"", "GH_TOKEN":"", "GH_EMAIL":""}
    if os.path.exists("/etc/sansxml-backup.conf"):
        with open("/etc/sansxml-backup.conf") as f:
            for line in f:
                for k in d.keys():
                    if line.startswith(k + "="):
                        d[k] = line.split("=",1)[1].strip().strip('"').strip()
    return d
def save_backup_conf(ghu, ghr, ght, ghe):
    with open("/etc/sansxml-backup.conf", "w") as f:
        f.write(f'GH_USER="{ghu}"\nGH_REPO="{ghr}"\nGH_TOKEN="{ght}"\nGH_EMAIL="{ghe}"\n')
    try: os.chmod("/etc/sansxml-backup.conf", 0o600)
    except: pass
def is_backup_ready():
    conf = load_backup_conf()
    return all([conf.get("GH_USER"), conf.get("GH_REPO"), conf.get("GH_TOKEN"), conf.get("GH_EMAIL")])

def get_ssh_params(server_key=None):
    if server_key and server_key in SERVERS:
        srv = SERVERS[server_key]
        return (srv.get("ssh_host") or "127.0.0.1", int(srv.get("ssh_port", 22)),
                srv.get("ssh_user") or "root", srv.get("ssh_key") or SSH_KEY_PATH)
    return "127.0.0.1", 22, "root", SSH_KEY_PATH

def ssh_run(cmd, server_key=None, timeout=30):
    host, port, user, key = get_ssh_params(server_key)
    full = ["ssh","-i",key,"-o","StrictHostKeyChecking=no","-o","UserKnownHostsFile=/dev/null",
            "-o","ConnectTimeout=10","-o","BatchMode=yes","-o","PubkeyAuthentication=yes",
            "-o","PasswordAuthentication=no","-o","LogLevel=ERROR","-p",str(port),f"{user}@{host}",cmd]
    try:
        r = subprocess.run(full, capture_output=True, text=True, timeout=timeout)
        return r.returncode, r.stdout.strip(), r.stderr.strip()
    except subprocess.TimeoutExpired: return -1,"","Timeout"
    except Exception as e: return -2,"",str(e)

def gen_ssh_key(key_name):
    os.makedirs("/root/.ssh", exist_ok=True)
    kp = f"/root/.ssh/id_{key_name}"
    if not os.path.exists(kp):
        subprocess.run(["ssh-keygen","-t","ed25519","-f",kp,"-N","","-q"], capture_output=True, timeout=10)
    pub = kp + ".pub"
    pk = open(pub).read().strip() if os.path.exists(pub) else ""
    return kp, pk

def test_ssh_key(ssh_key, ip, port):
    try:
        r = subprocess.run(["ssh","-i",ssh_key,"-o","StrictHostKeyChecking=no",
            "-o","UserKnownHostsFile=/dev/null","-o","ConnectTimeout=8","-o","BatchMode=yes",
            "-o","PasswordAuthentication=no","-o","LogLevel=ERROR","-p",str(port),
            f"root@{ip}","echo PING_OK"], capture_output=True, text=True, timeout=12)
        return "PING_OK" in r.stdout
    except: return False

def get_bandwidth_gb(server_key=None):
    try:
        code, out, _ = ssh_run("vnstat --json m 1 2>/dev/null", server_key, timeout=6)
        if code == 0 and out.strip():
            data = json.loads(out)
            ifaces = data.get("interfaces", [])
            if ifaces:
                months = ifaces[0].get("traffic", {}).get("month", [])
                if months:
                    rx = months[-1].get("rx", 0); tx = months[-1].get("tx", 0)
                    return (rx + tx) / (1024**3)
    except: pass
    try:
        code, out, _ = ssh_run("cat /proc/net/dev", server_key, timeout=5)
        if code == 0:
            total = 0
            for line in out.splitlines():
                if ":" not in line: continue
                iface, rest = line.split(":",1)
                if iface.strip() == "lo": continue
                parts = rest.split()
                if len(parts) >= 9: total += int(parts[0]) + int(parts[8])
            return total / (1024**3)
    except: pass
    return 0.0

def get_vps_detail(server_key=None):
    d = {}
    def run(cmd):
        c, o, e = ssh_run(cmd, server_key, timeout=6)
        return o if c == 0 else ""
    d["os"] = run("grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '\"'") or "-"
    d["kernel"] = run("uname -r") or "-"
    d["cpu"] = (run("grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs") or "-")[:45]
    d["cores"] = run("nproc") or "-"
    meminfo = run("cat /proc/meminfo")
    try:
        mem = {}
        for line in meminfo.splitlines():
            if ":" in line:
                k, v = line.split(":",1); mem[k.strip()] = v.strip()
        tk = int(mem["MemTotal"].split()[0]); ak = int(mem["MemAvailable"].split()[0])
        d["ram_total"] = f"{tk/1024/1024:.1f} GB"; d["ram_used"] = f"{(tk-ak)/1024/1024:.1f} GB"
        d["ram_pct"] = f"{((tk-ak)/tk*100):.0f}%"
    except: d["ram_total"]="-"; d["ram_used"]="-"; d["ram_pct"]="-"
    df = run("df -h / | tail -1").split()
    if len(df) >= 5: d["disk_total"], d["disk_used"], d["disk_pct"] = df[1], df[2], df[4]
    else: d["disk_total"]="-"; d["disk_used"]="-"; d["disk_pct"]="-"
    up = run("cat /proc/uptime")
    try:
        s = float(up.split()[0]); d["uptime"] = f"{int(s//86400)}d {int((s%86400)//3600)}h {int((s%3600)//60)}m"
    except: d["uptime"] = "-"
    d["load"] = (run("cat /proc/loadavg").split()[:3]) or ["-","-","-"]
    d["ip"] = run("hostname -I | awk '{print $1}'") or "-"
    d["bw"] = get_bandwidth_gb(server_key)
    return d

def load_json(p, d):
    if not os.path.exists(p): return d
    try:
        with open(p) as f: return json.load(f)
    except: return d
def save_json(p, d):
    with open(p,"w") as f: json.dump(d,f,indent=2,ensure_ascii=False)

def sync_push_now():
    if not is_backup_ready(): return False, "Backup belum di-setup"
    try:
        sh_path = "/root/vpnbot_backup.sh"
        if not os.path.exists(sh_path): return False, "Script backup tidak ada"
        r = subprocess.run(["bash", sh_path], capture_output=True, text=True, timeout=45)
        return r.returncode == 0, (r.stderr or r.stdout or "")[:200]
    except Exception as e: return False, str(e)[:200]
async def sync_push_async():
    try: await asyncio.to_thread(sync_push_now)
    except: pass

def restore_ssh_users_from_json():
    accs = load_json(ACCOUNTS_FILE, {}); today = datetime.now().date()
    created = 0; skipped = 0
    for un, a in accs.items():
        try: exp = datetime.strptime(a["exp"], "%Y-%m-%d").date()
        except: skipped += 1; continue
        if (exp - today).days < 0: skipped += 1; continue
        pw = a.get("password", "")
        if not pw: skipped += 1; continue
        sk = a.get("server_key", "sg_1ip")
        pw_b64 = base64.b64encode(pw.encode()).decode()
        cmd = (f"userdel -r {un} 2>/dev/null; useradd -m -s /bin/bash {un} 2>&1 ; "
               f"chage -E '{a['exp']}' {un} 2>&1 ; chage -M 99999 {un} 2>&1 ; chage -I -1 {un} 2>&1 ; "
               f"PW=$(echo '{pw_b64}' | base64 -d) ; printf '%s:%s\\n' '{un}' \"$PW\" | chpasswd 2>&1 ; "
               f"passwd -u {un} 2>&1 ; usermod -U {un} 2>&1")
        ssh_run(cmd, sk); created += 1
    logger.info(f"[RESTORE] {created} user, {skipped} skip")
    return created, skipped

def _write_backup_sh():
    sh_path = "/root/vpnbot_backup.sh"
    with open(sh_path, "w") as f:
        f.write("""#!/bin/bash
source /etc/sansxml-backup.conf 2>/dev/null
cd /root/vpnbot_backup || exit 1
for f in vpnbot_users.json vpnbot_balance.json vpnbot_accounts.json vpnbot_trial.json vpnbot_trx.json vpnbot_blocked.json vpnbot_config.json bot.py; do
    [ -f "/root/$f" ] && cp "/root/$f" "./$f"
done
git add -A
if ! git diff --cached --quiet; then
    git -c user.email="$GH_EMAIL" -c user.name="$GH_USER" commit -m "Auto backup: $(date '+%Y-%m-%d %H:%M:%S')" -q
    if ! git push "https://${GH_USER}:${GH_TOKEN}@github.com/${GH_USER}/${GH_REPO}.git" HEAD:main -q 2>/dev/null; then
        git pull --no-rebase -X ours "https://${GH_USER}:${GH_TOKEN}@github.com/${GH_USER}/${GH_REPO}.git" main -q 2>/dev/null
        git push "https://${GH_USER}:${GH_TOKEN}@github.com/${GH_USER}/${GH_REPO}.git" HEAD:main -q 2>/dev/null
    fi
fi
""")
    os.chmod(sh_path, 0o755)

def setup_backup_env(ghu, ghr, ght, ghe):
    try:
        bdir = "/root/vpnbot_backup"
        os.makedirs(bdir, exist_ok=True)
        if not os.path.exists(f"{bdir}/.git"):
            subprocess.run(["git","init","-q"], cwd=bdir, capture_output=True)
        subprocess.run(["git","config","user.email",ghe], cwd=bdir, capture_output=True)
        subprocess.run(["git","config","user.name",ghu], cwd=bdir, capture_output=True)
        subprocess.run(["git","branch","-M","main"], cwd=bdir, capture_output=True)
        remote = f"https://{ghu}:{ght}@github.com/{ghu}/{ghr}.git"
        subprocess.run(["git","remote","remove","origin"], cwd=bdir, capture_output=True)
        subprocess.run(["git","remote","add","origin",remote], cwd=bdir, capture_output=True)
        for branch in ["main","master"]:
            r = subprocess.run(["git","pull","origin",branch,"--allow-unrelated-histories","--no-rebase","-X","ours"],
                cwd=bdir, capture_output=True, text=True, timeout=30)
            if r.returncode == 0: break
        restored = 0
        for f in ["vpnbot_users.json","vpnbot_balance.json","vpnbot_accounts.json",
                  "vpnbot_trial.json","vpnbot_trx.json","vpnbot_blocked.json"]:
            src = f"{bdir}/{f}"
            if os.path.exists(src) and os.path.getsize(src) > 2:
                with open(src) as ff: content = ff.read().strip()
                if content and content not in ("{}", "[]"):
                    with open(f"/root/{f}", "w") as ff: ff.write(content)
                    restored += 1
        _write_backup_sh()
        subprocess.run("crontab -l 2>/dev/null | grep -v vpnbot_backup.sh | crontab -", shell=True)
        subprocess.run('( crontab -l 2>/dev/null; echo "*/5 * * * * /root/vpnbot_backup.sh >/dev/null 2>&1" ) | crontab -', shell=True)
        subprocess.run("systemctl restart cron 2>/dev/null || systemctl restart crond 2>/dev/null", shell=True)
        subprocess.run(["bash", "/root/vpnbot_backup.sh"], capture_output=True, timeout=60)
        return True, restored
    except Exception as e: return False, str(e)

def wipe_local_data():
    deleted = {"json": 0, "users": 0, "folder": False}
    for f in ["vpnbot_users.json","vpnbot_balance.json","vpnbot_accounts.json",
              "vpnbot_trial.json","vpnbot_trx.json","vpnbot_blocked.json"]:
        p = f"/root/{f}"
        if os.path.exists(p):
            try: os.remove(p); deleted["json"] += 1
            except: pass
    for sk in SERVERS.keys():
        try:
            code, out, _ = ssh_run("awk -F: '$3>=1000 && $3<60000 {print $1}' /etc/passwd", sk, timeout=10)
            if code == 0:
                for un in out.split():
                    try:
                        ssh_run(f"pkill -9 -u {un} 2>/dev/null; userdel -r {un} 2>/dev/null", sk, timeout=15)
                        deleted["users"] += 1
                    except: pass
        except: pass
    if os.path.exists("/root/vpnbot_backup"):
        try: shutil.rmtree("/root/vpnbot_backup"); deleted["folder"] = True
        except: pass
    if os.path.exists("/root/vpnbot_backup.sh"):
        try: os.remove("/root/vpnbot_backup.sh")
        except: pass
    subprocess.run("crontab -l 2>/dev/null | grep -v vpnbot_backup.sh | crontab -", shell=True)
    return deleted

def reset_backup_env(keep_config=True):
    result = {"github": False, "local": {}, "ts": time.strftime("%Y%m%d_%H%M%S"), "gh_error": ""}
    try:
        conf = load_backup_conf()
        ghu = conf.get("GH_USER",""); ghr = conf.get("GH_REPO","")
        ght = conf.get("GH_TOKEN",""); ghe = conf.get("GH_EMAIL","bot@local")
        if ghu and ghr and ght:
            remote = f"https://{ghu}:{ght}@github.com/{ghu}/{ghr}.git"
            tmp = f"/tmp/vpnbot_wipe_{result['ts']}"
            shutil.rmtree(tmp, ignore_errors=True); os.makedirs(tmp, exist_ok=True)
            try:
                subprocess.run(["git","init","-q"], cwd=tmp, capture_output=True)
                subprocess.run(["git","config","user.email",ghe], cwd=tmp, capture_output=True)
                subprocess.run(["git","config","user.name",ghu], cwd=tmp, capture_output=True)
                subprocess.run(["git","checkout","--orphan","main"], cwd=tmp, capture_output=True)
                with open(f"{tmp}/README.md","w") as f:
                    f.write(f"# VPN Bot Backup\n\nRESTORE DATA: {result['ts']}\n")
                subprocess.run(["git","add","-A"], cwd=tmp, capture_output=True)
                subprocess.run(["git","-c",f"user.email={ghe}","-c",f"user.name={ghu}",
                                "commit","-m",f"RESTORE DATA {result['ts']}"], cwd=tmp, capture_output=True)
                subprocess.run(["git","remote","add","origin",remote], cwd=tmp, capture_output=True)
                pushed = False; push_err = ""
                for br in ["main","master"]:
                    subprocess.run(["git","branch","-M",br], cwd=tmp, capture_output=True)
                    r = subprocess.run(["git","push","-f","origin",br], cwd=tmp, capture_output=True, text=True, timeout=45)
                    push_err = (r.stderr or r.stdout or "").strip()
                    if r.returncode == 0: pushed = True; break
                result["github"] = pushed
                if not pushed:
                    safe = push_err.replace(ght, "***") if ght else push_err
                    result["gh_error"] = safe[:500]
            finally:
                shutil.rmtree(tmp, ignore_errors=True)
        result["local"] = wipe_local_data()
        if not keep_config and os.path.exists("/etc/sansxml-backup.conf"):
            try: os.remove("/etc/sansxml-backup.conf")
            except: pass
        if result["github"] and ghu and ghr and ght:
            try: setup_backup_env(ghu, ghr, ght, ghe)
            except: pass
        return True, result
    except Exception as e: return False, {"error": str(e)[:200]}

def ssh_create(username, password, days, is_trial=False, server_key="sg_1ip"):
    now = datetime.now()
    if is_trial:
        exp_date = now.date()
        exp_ts = (now + timedelta(minutes=TRIAL_DURATION_MIN)).strftime("%Y-%m-%d %H:%M:%S")
    else:
        exp_date = (now + timedelta(days=days)).date()
        exp_ts = exp_date.strftime("%Y-%m-%d") + " 23:59:59"
    exp = exp_date.strftime("%Y-%m-%d")
    pw_b64 = base64.b64encode(password.encode()).decode()
    cmd = (f"userdel -r {username} 2>/dev/null; useradd -m -s /bin/bash {username} 2>&1 ; "
           f"chage -E '{exp}' {username} 2>&1 ; chage -M 99999 {username} 2>&1 ; chage -I -1 {username} 2>&1 ; "
           f"PW=$(echo '{pw_b64}' | base64 -d) ; printf '%s:%s\\n' '{username}' \"$PW\" | chpasswd 2>&1 ; "
           f"passwd -u {username} 2>&1 ; usermod -U {username} 2>&1 ; echo DONE:$?")
    code, out, err = ssh_run(cmd, server_key)
    return {"ok":True,"username":username,"password":password,"exp":exp,"exp_ts":exp_ts,
            "manual":("DONE:0" not in out), "err": err}
def ssh_extend(username, new_exp, server_key="sg_1ip"):
    code, out, err = ssh_run(f"chage -E '{new_exp}' {username} 2>&1 ; echo DONE:$?", server_key)
    return "DONE:0" in out
def ssh_delete(username, server_key="sg_1ip"):
    ssh_run(f"pkill -9 -u {username} 2>/dev/null; userdel -r {username} 2>&1; echo OK", server_key, timeout=20)
    return True, "OK"
def ssh_test(server_key="sg_1ip"):
    code, out, err = ssh_run("echo PING_OK", server_key, timeout=10)
    return ("PING_OK" in out, "SSH OK" if "PING_OK" in out else f"SSH gagal: {err or out}")

def valid_username(s): return bool(re.match(r'^[a-zA-Z0-9_]{5,20}$', s or ""))
def valid_password(s):
    if not s or len(s)<5 or len(s)>32: return False
    return all(c in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*_.-" for c in s)

def get_active_sessions(username, server_key="sg_1ip"):
    try:
        code, out, _ = ssh_run("who", server_key, timeout=5)
        if code != 0: return []
        return [l for l in out.splitlines() if l.split() and l.split()[0] == username]
    except: return []
def count_live_shells(username, server_key="sg_1ip"):
    try:
        code, out, _ = ssh_run(f"ps -u {username} -o comm=", server_key, timeout=5)
        if code != 0: return 0
        procs = [p.strip() for p in out.splitlines() if p.strip()]
        shells = ("bash","sh","zsh","ksh","dash","csh","tcsh")
        return sum(1 for p in procs if p.lstrip("-") in shells)
    except: return 0
def check_second_connection(username, server_key="sg_1ip"):
    sessions = get_active_sessions(username, server_key); n = len(sessions)
    if n <= 1: return False, sessions, n
    shells = count_live_shells(username, server_key)
    if shells > 1: return True, sessions, shells
    return False, sessions, shells if shells > 0 else n
def block_user(username, hours=2, server_key="sg_1ip"):
    try:
        ssh_run(f"passwd -l {username}", server_key, timeout=10)
        ssh_run(f"pkill -9 -u {username}", server_key, timeout=10)
        try:
            code, out, _ = ssh_run(f"ps -u {username} -o pid=", server_key, timeout=5)
            for pid in out.split(): ssh_run(f"kill -9 {pid}", server_key, timeout=3)
        except: pass
        d = load_json(BLOCK_FILE, {})
        d[username] = {"blocked_at": datetime.now().isoformat(),
                       "unblock_at": (datetime.now() + timedelta(hours=hours)).strftime("%Y-%m-%d %H:%M:%S")}
        save_json(BLOCK_FILE, d); return True
    except: return False
def unblock_user(username, server_key="sg_1ip"):
    try:
        ssh_run(f"passwd -u {username}", server_key, timeout=10)
        d = load_json(BLOCK_FILE, {})
        if username in d: d.pop(username); save_json(BLOCK_FILE, d)
        return True
    except: return False
def get_block_info(username): return load_json(BLOCK_FILE, {}).get(username)

def get_bal(uid): return load_json(BAL_FILE,{}).get(str(uid),0)
def add_bal(uid, amt):
    d = load_json(BAL_FILE,{}); d[str(uid)] = d.get(str(uid),0)+int(amt); save_json(BAL_FILE,d); return d[str(uid)]
def reduce_bal(uid, amt):
    d = load_json(BAL_FILE,{}); cur = d.get(str(uid),0)
    if cur < amt: return False, cur
    d[str(uid)] = cur - amt; save_json(BAL_FILE,d); return True, d[str(uid)]
def get_acc(u): return load_json(ACCOUNTS_FILE,{}).get(u)
def get_user_accs(uid): return [a for a in load_json(ACCOUNTS_FILE,{}).values() if a.get("user_id")==uid]
def save_acc(u, d):
    dd = load_json(ACCOUNTS_FILE,{}); dd[u]=d; save_json(ACCOUNTS_FILE,dd)
def is_username_taken(u): return u.lower() in [k.lower() for k in load_json(ACCOUNTS_FILE,{}).keys()]
def count_accounts(): return len(load_json(ACCOUNTS_FILE,{}))
def delete_acc_json(un):
    dd = load_json(ACCOUNTS_FILE,{})
    if un in dd: data = dd.pop(un); save_json(ACCOUNTS_FILE,dd); return data
    return None
def count_slots(server_key):
    accs = load_json(ACCOUNTS_FILE, {}); today = datetime.now().date(); c = 0
    for a in accs.values():
        if a.get("server_key") != server_key: continue
        try:
            ed = datetime.strptime(a["exp"], "%Y-%m-%d").date()
            if (ed - today).days >= 0: c += 1
        except: pass
    return c
def get_slot_info(server_key):
    srv = SERVERS.get(server_key, {})
    return count_slots(server_key), int(srv.get("slot_max", 50) or 50)
def trial_left(uid):
    d = load_json(TRIAL_FILE,{}); today = datetime.now().strftime("%Y-%m-%d")
    u = d.get(str(uid),{})
    if u.get("date") != today: return TRIAL_PER_DAY
    return max(0, TRIAL_PER_DAY - u.get("used",0))
def use_trial(uid):
    d = load_json(TRIAL_FILE,{}); today = datetime.now().strftime("%Y-%m-%d")
    u = d.get(str(uid),{})
    if u.get("date") != today: u = {"date":today,"used":0}
    u["used"] = u.get("used",0)+1; d[str(uid)] = u; save_json(TRIAL_FILE,d)
def track_user(u):
    d = load_json(USERS_FILE,{})
    d[str(u.id)] = {"first_name": u.first_name or "", "username": u.username or "", "last_seen": datetime.now().isoformat()}
    save_json(USERS_FILE,d)
def add_trx(uid, name, uname, tipe, jumlah, ket=""):
    d = load_json(TRX_FILE,[])
    d.append({"user_id":uid,"name":name,"username":uname,"tipe":tipe,"jumlah":int(jumlah),"ket":ket,"waktu":datetime.now().isoformat()})
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
        hg = int(a.get("harga", 0)); th = int(a.get("days", 30))
        if hg <= 0 or th <= 0: return 0
        exp = datetime.strptime(a["exp"], "%Y-%m-%d").date(); sisa = (exp - datetime.now().date()).days
        if sisa <= 0: return 0
        return max(0, min(int(round((hg/th) * sisa)), hg))
    except: return 0
def count_users_by_period():
    d = load_json(USERS_FILE, {})
    today = datetime.now().strftime("%Y-%m-%d"); week = (datetime.now()-timedelta(days=7)).strftime("%Y-%m-%d"); month = datetime.now().strftime("%Y-%m")
    return {"hari": sum(1 for u in d.values() if (u.get("last_seen","")[:10] == today)),
            "minggu": sum(1 for u in d.values() if (u.get("last_seen","")[:10] >= week)),
            "bulan": sum(1 for u in d.values() if (u.get("last_seen","")[:7] == month)),
            "total": len(d)}
def get_server_status():
    result = []
    for key, srv in SERVERS.items():
        used = count_slots(key)
        mx = int(srv.get("slot_max", 50) or 50)
        stat = "🟢 Online" if max(0, mx - used) > 0 else "🔴 Full"
        quota = int(srv.get("quota_gb", 700) or 700)
        bw = get_bandwidth_gb(key)
        complete = is_server_complete(srv)
        result.append({"name": srv.get("name","-"), "used": used, "max": mx, "status": stat,
                       "quota": quota, "bw": bw, "key": key, "complete": complete})
    return result
def save_servers():
    cfg = load_config(); cfg["servers"] = SERVERS; save_config(cfg)

def backup_config_text():
    conf = load_backup_conf(); ght = conf.get("GH_TOKEN", "") or ""
    if len(ght) > 12: tok_disp = f"{ght[:4]}{'*' * (len(ght) - 8)}{ght[-4:]}"
    elif ght: tok_disp = "*" * len(ght)
    else: tok_disp = "(kosong)"
    status = "✅ Aktif" if is_backup_ready() else "❌ Belum diisi"
    return "\n".join(["<blockquote>", "🔄 <b>PENGATURAN BACKUP GITHUB</b>", "───────────────────────",
             f"├ Status   : <b>{status}</b>", f"├ Username : <code>{conf.get('GH_USER','-')}</code>",
             f"├ Repo     : <code>{conf.get('GH_REPO','-')}</code>",
             f"├ Email    : <code>{conf.get('GH_EMAIL','-')}</code>",
             f"╰ Token    : <code>{tok_disp}</code>", "───────────────────────",
             "🔄 <i>Backup otomatis tiap 5 menit ke repo private.</i>", "</blockquote>"])

def kb_backup():
    return InlineKeyboardMarkup([
        [B("👤 Ganti Username", "backup_edit|user", style="primary"), B("📁 Ganti Repo", "backup_edit|repo", style="primary")],
        [B("🔑 Ganti Token", "backup_edit|token", style="primary"), B("📧 Ganti Email", "backup_edit|email", style="primary")],
        [B("📊 Restore Data", "backup_reset", style="danger")],
        [B("🔙 Kembali", "admin|menu", style="danger")]])

def kb_admin():
    return InlineKeyboardMarkup([
        [B("💻 Kelola VPN", "admin|srv", style="primary"), B("👤 Pengguna", "admin|users|0", style="primary")],
        [B("📢 Broadcast", "admin|bc", style="primary"), B("🔄 Backup GitHub", "admin|backup", style="primary")],
        [B("💻 VPS", "admin|vps", style="primary")],
        [B("🔙 Kembali", "menu|main", style="danger")]])

def kb_acc_detail(un):
    return InlineKeyboardMarkup([[B("🗑️ Hapus", f"del_acc|{un}", style="danger")],
        [B("🔙 Kembali", "my_accs", style="danger")]])

def kb_dashboard(uid):
    rows = [[B("➕  BUAT AKUN", "buat_akun", style="primary"), B("⌛  TRIAL AKUN", "trial_akun", style="primary")],
        [B("🔄 PERPANJANG AKUN", "perpanjang_akun", style="primary")],
        [B("💰 TOPUP SALDO", "isi_saldo", style="primary"), B("👤 AKUN SAYA", "my_accs", style="primary")],
        [B("♻️ REFRESH", "refresh", style="primary")]]
    if is_owner(uid): rows.append([B("💻 PENGATURAN", "admin|menu", style="danger")])
    return InlineKeyboardMarkup(rows)

def kb_saldo():
    return InlineKeyboardMarkup([
        [B("1", "saldo_num|1", style="primary"), B("2", "saldo_num|2", style="primary"), B("3", "saldo_num|3", style="primary")],
        [B("4", "saldo_num|4", style="primary"), B("5", "saldo_num|5", style="primary"), B("6", "saldo_num|6", style="primary")],
        [B("7", "saldo_num|7", style="primary"), B("8", "saldo_num|8", style="primary"), B("9", "saldo_num|9", style="primary")],
        [B("⬅️ Hapus", "saldo_hapus", style="danger"), B("0", "saldo_num|0", style="primary"), B("✅ Konfirmasi", "saldo_konfirmasi", style="success")],
        [B("🔙 Kembali", "menu|main", style="danger")]])

def kb_pilih_layanan():
    return InlineKeyboardMarkup([
        [B("➕ SSH OVPN", "pilih|ssh", style="primary")],
        [B("➕ VMESS", "pilih|vmess", style="primary"), B("➕ VLESS", "pilih|vless", style="primary")],
        [B("➕ TROJAN", "pilih|trojan", style="primary")],
        [B("🔙 KEMBALI", "menu|main", style="danger")]])

def kb_ssh_server():
    active = get_active_servers(); rows = []; keys = list(active.keys())
    for i in range(0, len(keys), 2):
        row = []
        for j in range(i, min(i+2, len(keys))):
            k = keys[j]; row.append(B(active[k]['name'], f"buat|{k}", style="primary"))
        rows.append(row)
    if not rows: rows.append([B("⚠️ Belum ada server aktif", "noop", style="danger")])
    rows.append([B("🔙 KEMBALI", "pilih_layanan", style="danger")])
    return InlineKeyboardMarkup(rows)

def kb_ssh_server_locked():
    active = get_active_servers(); rows = []; keys = list(active.keys())
    for i in range(0, len(keys), 2):
        row = []
        for j in range(i, min(i+2, len(keys))):
            k = keys[j]; row.append(B(active[k]['name'], "ssh_locked", style="primary"))
        rows.append(row)
    rows.append([B("🔙 KEMBALI", "ssh_locked", style="danger")])
    return InlineKeyboardMarkup(rows)

def kb_ssh_server_extend():
    active = get_active_servers(); rows = []; keys = list(active.keys())
    for i in range(0, len(keys), 2):
        row = []
        for j in range(i, min(i+2, len(keys))):
            k = keys[j]; row.append(B(active[k]['name'], f"extend|{k}", style="primary"))
        rows.append(row)
    rows.append([B("🔙 KEMBALI", "menu|main", style="danger")])
    return InlineKeyboardMarkup(rows)

def kb_coming_soon(p): return InlineKeyboardMarkup([[B("🔙 KEMBALI", "pilih_layanan", style="danger")]])

def dashboard_text(user, uid):
    uname = f"@{user.username}" if user.username else "-"
    role = "Owner" if is_owner(uid) else "Member"
    st = get_stats(uid); total_users = len(load_json(USERS_FILE, {}))
    lines = ["<blockquote>", "💻 <b>SANSXML VPN STORE</b>", "───────────────────────", "👤 <b>Profil</b>"]
    lines += [f"├ User Telegram  : {uname}", f"├ Chat ID        : <code>{uid}</code>",
              f"├ Keanggotaan    : {role}", f"├ Total Pengguna : <b>{total_users}</b>",
              f"╰ 💰 Saldo VPN  : <b>{rupiah(get_bal(uid))}</b>", "", "🌍 <b>Info Global</b>",
              f"├ Minggu Ini     : <b>{st['minggu']} Akun</b>", f"├ Bulan Ini      : <b>{st['bulan']} Akun</b>",
              f"╰ Keseluruhan    : <b>{st['total']} Akun</b>", "", "🌐 <b>Informasi</b>",
              f"├ Server Tersedia : <b>{len(get_active_servers())} Server</b>",
              f"╰ Kuota Trial     : <b>{trial_left(uid)}x Hari</b>",
              "", "───────────────────────", "</blockquote>"]
    return "\n".join(lines)

def pilih_layanan_text():
    return "<blockquote>\n💻 <b>PILIH LAYANAN VPN</b>\n───────────────────────\nSilakan pilih protokol yang ingin dibuat:\n───────────────────────\n</blockquote>"

def ssh_server_text():
    active = get_active_servers()
    if not active: return "<blockquote>⚠️ <b>Belum ada server tersedia</b>\n\nHubungi admin.</blockquote>"
    lines = ["<blockquote>", "<b>💻 SSH OVPN</b>", "─────────────────────────", ""]
    for key, srv in active.items():
        used, mx = get_slot_info(key); cek = "✅" if max(0, mx-used) > 0 else "❌"
        quota = srv.get("quota_gb", 700) or 700
        lines += [f"◆ {srv['name']}", f"├ Harga Harian   : <b>{rupiah(srv.get('price_day',0))}</b>",
                  f"├ Harga Bulanan  : <b>{rupiah(srv.get('price_month',0))}</b>",
                  f"├ Qouta          : <b>{quota} GB</b>", f"├ Limit IP       : {srv.get('ip_limit',1)} IP",
                  f"╰ Slot Tersedia  : <b>{used}/{mx} {cek}</b>", "", ""]
    lines += ["─────────────────────────", "</blockquote>"]
    return "\n".join(lines)

def saldo_text(uid, nominal=""):
    return (f"<blockquote>\n💰 <b>Masukkan nominal topup:</b>\n\nJumlah saat ini: <b>{rupiah(get_bal(uid))}</b>\n\n"
            f"Nominal input: <b>{rupiah(nominal) if nominal else 'Rp 0'}</b>\n\n<i>Minimal {rupiah(MIN_TOPUP)}</i>\n</blockquote>")

def acc_caption(u, p, exp, dl, ip, manual=False, is_trial=False, server_key="sg_1ip"):
    srv = SERVERS.get(server_key, {})
    head = "TRIAL" if is_trial else ("MANUAL" if manual else "PREMIUM")
    BULAN_ID = ["Jan","Feb","Mar","Apr","Mei","Jun","Jul","Agu","Sep","Okt","Nov","Des"]
    try:
        exp_d = datetime.strptime(exp,"%Y-%m-%d")
        exp_fmt = f"{exp_d.day} {BULAN_ID[exp_d.month-1]}, {exp_d.year}"
        try: days_int = int(dl.split()[0])
        except: days_int = 30
        created = datetime.now() - timedelta(days=days_int)
        created_fmt = f"{created.day} {BULAN_ID[created.month-1]}, {created.year}"
    except: exp_fmt = exp; created_fmt = "-"
    ssh_ovpn_val = srv.get("ssh_ovpn") or srv.get("name","SG NEWMEDIA")
    srv_host = srv.get("domain") or SSH_HOST
    payload_ws = "GET /cdn-cgi/trace HTTP/1.1[crlf]Host: [host][crlf][crlf]GET-RAY / HTTP/1.1[crlf]Host: [host][crlf]Connection: Upgrade[crlf]User-Agent: [ua][crlf]Upgrade: websocket[crlf][crlf]"
    payload_tls = "GET / HTTP/1.1[crlf]Host: [host][crlf]User-Agent: [ua][crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]"
    lines = ["<blockquote>", "◤ <b>SSH OVPN ACCOUNT</b> ◢", f"     ❖ <b>{head}</b> ❖",
             "━━━━━━━━━━━━━━━━━━━━━━━", "", "",
             f"City       : {srv.get('city','Singapore')}", f"ISP        : {srv.get('isp','DigitalOcean LLC')}",
             f"SSH OVPN   : {ssh_ovpn_val}", f"Username   : {u}", f"Password   : {p}",
             "Quota      : Unlimited", f"Limit IP   : {ip} IP", "", "",
             "━━━━━━━━━━━━━━━━━━━━━━━", "", "",
             f"Host     : {srv_host}", "OpenSSH  : 443, 80, 22", "Dropbear : 443, 109",
             "SSH WS   : 80, 8080, 8081-9999", "SSH SSL  : 443", "SSH UDP  : 1-65535",
             "OVPN     : 443, 1194, 2200", "BadVPN   : 7100, 7300", "━━━━━━━━━━━━━━━━━━━━━━━",
             f"SSL : {srv_host}:443@{u}:{p}", "", f"WS  : {srv_host}:80@{u}:{p}",
             "", f"UDP : {srv_host}:1-65535@{u}:{p}", "━━━━━━━━━━━━━━━━━━━━━━━",
             "", "PAYLOAD WS", payload_ws, "", "PAYLOAD TLS", payload_tls,
             "━━━━━━━━━━━━━━━━━━━━━━━", "", f"Durasi   : {dl}",
             f"Dibuat   : {created_fmt}", f"Berakhir : {exp_fmt}", "",
             "━━━━━━━━━━━━━━━━━━━━━━━", "<b>      ◤ SANSXML VPN STORE ◢</b>",
             "<i>❖ Terima kasih ❖</i>", "</blockquote>"]
    return "\n".join(lines)

async def do_create_account(chat, uid, user, username, password, hari, is_trial=False, server_key="sg_1ip"):
    srv = SERVERS.get(server_key, {}); ip_limit = int(srv.get("ip_limit", 2) or 2)
    price = 0 if is_trial else get_price(hari, server_key)
    if not is_trial and get_bal(uid) < price:
        kb = InlineKeyboardMarkup([[B("💰 TOPUP SALDO", "isi_saldo", style="primary")],
            [B("🔙 Kembali", "menu|main", style="danger")]])
        await chat.send_message(f"<blockquote>❌ <b>Saldo Tidak Cukup</b>\n\n💰 Saldo: <b>{rupiah(get_bal(uid))}</b>\n💵 Harga: <b>{rupiah(price)}</b>\n📉 Kurang: <b>{rupiah(price - get_bal(uid))}</b></blockquote>",
            reply_markup=kb, parse_mode="HTML")
        return
    msg = await chat.send_message(f"⚙️ Membuat <b>{'TRIAL' if is_trial else 'PREMIUM'} AKUN</b>...", parse_mode="HTML")
    r = await asyncio.to_thread(ssh_create, username, password, hari, is_trial, server_key)
    if not is_trial:
        ok, nb = reduce_bal(uid, price)
        if not ok: await msg.edit_text("❌ Saldo berubah.", parse_mode="HTML"); return
    save_acc(username, {"user_id":uid,"username":username,"password":password,
        "exp":r["exp"],"exp_ts":r.get("exp_ts",""),"days":hari,"limit_ip":ip_limit,"harga":price,
        "created_at":datetime.now().isoformat(),"first_name":user.first_name or "",
        "username_tg":user.username or "","manual":r.get("manual",False),
        "free_owner":is_owner(uid),"is_trial":is_trial,"server_key":server_key,"server": srv.get("name","SG NEWMEDIA")})
    if not is_trial:
        add_trx(uid, user.first_name or "User", user.username or "", "buat_akun", price, f"{hari}h {srv.get('name','')}")
    dl_txt = f"{TRIAL_DURATION_MIN} Minute" if is_trial else f"{hari} Hari"
    exp_show = r.get("exp_ts","")[:10] if is_trial else r["exp"]
    await msg.edit_text(acc_caption(username, password, exp_show, dl_txt, ip_limit, r.get("manual",False), is_trial, server_key), parse_mode="HTML")
    asyncio.create_task(sync_push_async())

async def do_extend_account(chat, uid, user, username, hari, server_key):
    price = get_price(hari, server_key)
    if get_bal(uid) < price:
        kb = InlineKeyboardMarkup([[B("💰 TOPUP SALDO", "isi_saldo", style="primary")],[B("🔙 Kembali", "menu|main", style="danger")]])
        await chat.send_message(f"<blockquote>❌ <b>Saldo Tidak Cukup</b></blockquote>", reply_markup=kb, parse_mode="HTML"); return
    msg = await chat.send_message(f"⚙️ Memperpanjang <b>{username}</b> {hari} hari...", parse_mode="HTML")
    a = get_acc(username)
    try: old_exp = datetime.strptime(a["exp"], "%Y-%m-%d").date()
    except: old_exp = datetime.now().date()
    base = old_exp if old_exp > datetime.now().date() else datetime.now().date()
    new_exp_str = (base + timedelta(days=hari)).strftime("%Y-%m-%d")
    ok = await asyncio.to_thread(ssh_extend, username, new_exp_str, server_key)
    if not ok: await msg.edit_text("❌ Gagal.", parse_mode="HTML"); return
    a["exp"] = new_exp_str; a["exp_ts"] = new_exp_str + " 23:59:59"
    a["days"] = int(a.get("days", 0)) + hari; a["harga"] = int(a.get("harga", 0)) + price
    save_acc(username, a)
    ok2, _ = reduce_bal(uid, price)
    if not ok2: await msg.edit_text("❌ Gagal potong saldo.", parse_mode="HTML"); return
    add_trx(uid, user.first_name or "User", user.username or "", "perpanjang", price, f"{hari}h {username}")
    await msg.edit_text(acc_caption(username, a["password"], new_exp_str, f"{a.get('days',30)} Hari",
        a.get("limit_ip",1), a.get("manual",False), a.get("is_trial",False), server_key), parse_mode="HTML")
    asyncio.create_task(sync_push_async())

async def _do_delete_account(uid, uname, user, chat):
    a = get_acc(uname)
    if not a or a.get("user_id") != uid: return
    refund = 0 if (a.get("is_trial") or int(a.get("harga",0)) <= 0) else hitung_refund(a)
    sk = a.get("server_key", "sg_1ip")
    try: await asyncio.to_thread(ssh_delete, uname, sk)
    except: pass
    delete_acc_json(uname)
    if refund > 0:
        try:
            add_bal(uid, refund)
            add_trx(uid, user.first_name or "", user.username or "", "refund", refund, f"hapus {uname}")
        except: pass
    asyncio.create_task(sync_push_async())

async def auto_cleanup_task():
    await asyncio.sleep(30)
    while True:
        try:
            now = datetime.now(); today = now.date(); dele = 0
            for un, a in list(load_json(ACCOUNTS_FILE, {}).items()):
                expired = False; ets = a.get("exp_ts", "")
                if ets:
                    try:
                        if now >= datetime.strptime(ets, "%Y-%m-%d %H:%M:%S"): expired = True
                    except: pass
                else:
                    try:
                        if (today - datetime.strptime(a["exp"], "%Y-%m-%d").date()).days >= 1: expired = True
                    except: pass
                if expired:
                    sk = a.get("server_key", "sg_1ip")
                    if a.get("is_trial"):
                        await asyncio.to_thread(ssh_delete, un, sk)
                        a["os_deleted"] = True; a["deleted_at"] = now.isoformat(); save_acc(un, a)
                    else:
                        await asyncio.to_thread(ssh_delete, un, sk); delete_acc_json(un)
                    dele += 1
            if dele > 0: logger.info(f"[AUTO-CLEANUP] {dele} expired")
            accs = load_json(ACCOUNTS_FILE, {}); blk = load_json(BLOCK_FILE, {})
            for un, a in accs.items():
                if a.get("is_trial") or a.get("free_owner") or un in blk: continue
                sk = a.get("server_key", "sg_1ip")
                violation, sessions, cnt = await asyncio.to_thread(check_second_connection, un, sk)
                if violation:
                    try:
                        await asyncio.to_thread(block_user, un, BLOCK_HOURS, sk)
                        logger.info(f"[BLOCK] {un} - {cnt} session")
                    except Exception as e: logger.error(f"[BLOCK-ERR] {un}: {e}")
            blk = load_json(BLOCK_FILE, {}); changed = False
            for un, info in list(blk.items()):
                try:
                    if now >= datetime.strptime(info["unblock_at"], "%Y-%m-%d %H:%M:%S"):
                        sk = (get_acc(un) or {}).get("server_key", "sg_1ip")
                        await asyncio.to_thread(unblock_user, un, sk); changed = True
                except: pass
            if changed: logger.info("[UNBLOCK]")
        except Exception as e: logger.error(f"cleanup: {e}")
        await asyncio.sleep(60)

async def start(u, c):
    uid = u.effective_user.id
    track_user(u.effective_user); c.user_data.clear()
    await u.message.reply_text(dashboard_text(u.effective_user, uid), reply_markup=kb_dashboard(uid), parse_mode="HTML")

async def cb(u, c):
    uid = u.effective_user.id
    track_user(u.effective_user)
    q = u.callback_query; await q.answer()
    d = q.data; chat = u.effective_chat
    if d in ("noop", "ssh_locked"): return

    if d == "refresh":
        try: await q.message.delete()
        except: pass
        try: await chat.send_message(dashboard_text(u.effective_user, uid), reply_markup=kb_dashboard(uid), parse_mode="HTML")
        except: pass
        return

    if d == "isi_saldo":
        c.user_data["saldo_input"] = ""
        try: await q.edit_message_text(saldo_text(uid), reply_markup=kb_saldo(), parse_mode="HTML")
        except: pass
        return
    if d.startswith("saldo_num|"):
        cur = c.user_data.get("saldo_input", ""); add = d.split("|",1)[1]
        if len(cur) >= 9: await q.answer("Maks 9 digit", show_alert=True); return
        cur = (cur + add).lstrip("0") or ""; c.user_data["saldo_input"] = cur
        try: await q.edit_message_text(saldo_text(uid, cur), reply_markup=kb_saldo(), parse_mode="HTML")
        except: pass
        return
    if d == "saldo_hapus":
        cur = c.user_data.get("saldo_input", ""); cur = cur[:-1] if cur else ""
        c.user_data["saldo_input"] = cur
        try: await q.edit_message_text(saldo_text(uid, cur), reply_markup=kb_saldo(), parse_mode="HTML")
        except: pass
        return
    if d == "saldo_konfirmasi":
        cur = c.user_data.get("saldo_input", "")
        if not cur or int(cur) <= 0: await q.answer("Nominal belum diisi!", show_alert=True); return
        nominal = int(cur)
        if nominal < MIN_TOPUP: await q.answer(f"❌ Minimal {rupiah(MIN_TOPUP)}", show_alert=True); return
        saldo_baru = add_bal(uid, nominal)
        add_trx(uid, u.effective_user.first_name or "", u.effective_user.username or "", "isi_saldo", nominal, "topup")
        c.user_data["saldo_input"] = ""
        try: await q.edit_message_text(f"✅ <b>Topup Berhasil</b>\n\n<blockquote>💰 Nominal: <b>{rupiah(nominal)}</b>\n💼 Saldo: <b>{rupiah(saldo_baru)}</b></blockquote>",
            reply_markup=InlineKeyboardMarkup([[B("🔙 Kembali", "menu|main", style="danger")]]), parse_mode="HTML")
        except: pass
        asyncio.create_task(sync_push_async()); return

    if d == "buat_akun":
        if not is_backup_ready():
            await q.answer("⚠️ Backup belum di-setup.", show_alert=True)
            await chat.send_message("<blockquote>⚠️ <b>BACKUP BELUM DI-SETUP</b>\n\nHubungi admin.</blockquote>", parse_mode="HTML"); return
        c.user_data.clear(); c.user_data["mode"] = "buat"
        try: await q.edit_message_text(pilih_layanan_text(), reply_markup=kb_pilih_layanan(), parse_mode="HTML")
        except: pass
        return
    if d == "trial_akun":
        if not is_backup_ready(): await q.answer("⚠️ Backup belum di-setup.", show_alert=True); return
        c.user_data.clear(); c.user_data["mode"] = "trial"
        try: await q.edit_message_text(pilih_layanan_text(), reply_markup=kb_pilih_layanan(), parse_mode="HTML")
        except: pass
        return
    if d == "perpanjang_akun":
        if not is_backup_ready(): await q.answer("⚠️ Backup belum di-setup.", show_alert=True); return
        c.user_data.clear(); c.user_data["mode"] = "perpanjang"
        try: await q.edit_message_text(pilih_layanan_text(), reply_markup=kb_pilih_layanan(), parse_mode="HTML")
        except: pass
        return
    if d == "pilih_layanan":
        c.user_data["mode"] = c.user_data.get("mode", "buat")
        try: await q.edit_message_text(pilih_layanan_text(), reply_markup=kb_pilih_layanan(), parse_mode="HTML")
        except: pass
        return
    if d.startswith("pilih|"):
        p = d.split("|")[1]; mode = c.user_data.get("mode", "buat")
        if p == "ssh":
            if mode == "perpanjang":
                try: await q.edit_message_text(ssh_server_text(), reply_markup=kb_ssh_server_extend(), parse_mode="HTML")
                except: pass
            else:
                try: await q.edit_message_text(ssh_server_text(), reply_markup=kb_ssh_server(), parse_mode="HTML")
                except: pass
        else:
            try: await q.edit_message_text(f"⚠️ <b>{p.upper()} BELUM TERSEDIA</b>", reply_markup=kb_coming_soon(p), parse_mode="HTML")
            except: pass
        return
    if d == "menu|main":
        c.user_data.clear()
        try: await q.edit_message_text(dashboard_text(u.effective_user, uid), reply_markup=kb_dashboard(uid), parse_mode="HTML")
        except: pass
        return

    if d == "admin|backup":
        if not is_owner(uid): return
        try: await q.edit_message_text(backup_config_text(), reply_markup=kb_backup(), parse_mode="HTML")
        except: pass
        return
    if d.startswith("backup_edit|"):
        if not is_owner(uid): return
        field = d.split("|")[1]; c.user_data["backup_field"] = field
        prompts = {"user": "Kirim <b>username GitHub</b>:\nContoh: <code>accbotvsbot-blip</code>",
            "repo": "Kirim <b>nama repo private</b>:\nContoh: <code>VPN-backup-</code>",
            "token": "Kirim <b>GitHub token</b> (ghp_xxx / github_pat_xxx):\n\n⚠️ <i>Auto-delete.</i>",
            "email": "Kirim <b>email GitHub</b>:\nContoh: <code>user@gmail.com</code>"}
        try: await q.edit_message_text(f"✏️ <b>GANTI {field.upper()}</b>\n\n{prompts.get(field,'')}",
            reply_markup=InlineKeyboardMarkup([[B("❌ Batal", "admin|backup", style="danger")]]), parse_mode="HTML")
        except: pass
        return
    if d == "backup_reset":
        if not is_owner(uid): return
        try:
            await q.edit_message_text("📊 <b>Restore Data</b>\n───────────────────────\n"
                "🔴 <b>Akan DIHAPUS PERMANEN:</b>\n├ 📄 Semua file JSON\n├ 👤 Semua user OS\n"
                "├ 📁 Folder /root/vpnbot_backup\n├ ⏰ Cron auto-backup lama\n╰ ☁️ History GitHub\n\n"
                "⚠️ <b>Data TIDAK BISA dipulihkan!</b>\n───────────────────────\nLanjutkan restore data?",
                reply_markup=InlineKeyboardMarkup([[B("✅ Ya, Lanjutkan", "backup_reset_yes", style="danger")],
                    [B("❌ Batal", "admin|backup", style="danger")]]), parse_mode="HTML")
        except: pass
        return
    if d == "backup_reset_yes":
        if not is_owner(uid): return
        try: await q.edit_message_text("📊 <b>Memproses...</b>", parse_mode="HTML")
        except: pass
        ok, info = await asyncio.to_thread(reset_backup_env, True)
        if ok:
            loc = info.get("local", {}); err = info.get("gh_error", "")
            err_block = f"\n🔴 <b>Error:</b>\n<code>{err[:300]}</code>\n" if err else ""
            m = ("✅ <b>Restore Data Selesai</b>\n\n<blockquote>☁️ <b>GitHub:</b>\n"
                 f"├ History : <b>{'DIPUTUS TOTAL' if info.get('github') else '❌ GAGAL'}</b>\n"
                 f"╰ Config  : <b>Dipertahankan</b>\n{err_block}\n🗑️ <b>Lokal VPS:</b>\n"
                 f"├ JSON dihapus  : <b>{loc.get('json',0)} file</b>\n"
                 f"├ User OS hapus : <b>{loc.get('users',0)} user</b>\n"
                 f"╰ Folder backup : <b>{'dihapus' if loc.get('folder') else '-'}</b>\n\n"
                 f"⏰ <i>{info.get('ts','')}</i>\n</blockquote>")
            try: await q.edit_message_text(m, reply_markup=InlineKeyboardMarkup([[B("🔙 Kembali", "admin|menu", style="danger")]]), parse_mode="HTML")
            except: pass
            await asyncio.sleep(5); subprocess.Popen(["systemctl", "restart", "vpnbot"])
        else:
            try: await q.edit_message_text(f"❌ <b>Gagal</b>\n<code>{info.get('error','?')[:200]}</code>",
                reply_markup=InlineKeyboardMarkup([[B("🔙 Kembali", "admin|backup", style="danger")]]), parse_mode="HTML")
            except: pass
        return

    if d == "admin|vps":
        if not is_owner(uid): return
        try: await q.edit_message_text("⏳ <b>Memuat data VPS...</b>", parse_mode="HTML")
        except: pass
        lines = ["<blockquote>", "💻 <b>DAFTAR VPS</b>", "───────────────────────", ""]
        for idx, (key, srv) in enumerate(SERVERS.items(), 1):
            v = await asyncio.to_thread(get_vps_detail, key)
            hl = "Local" if is_local_server(key) else "Remote"
            ip_addr = srv.get('ssh_host','127.0.0.1')
            port = srv.get('ssh_port',22)
            real_ip = v.get("ip", "-") if ip_addr in ("127.0.0.1","localhost","") else ip_addr
            bw = v["bw"]; bw_show = f"{bw:.2f}" if bw >= 1 else f"{bw:.3f}"
            lines += [f"[{idx}] <b>{srv.get('name','-')}</b>",
                f"├ IP     : <code>{real_ip}</code>",
                f"├ Port   : <code>{port}</code> ({hl})",
                f"├ OS     : {v['os'][:30]}",
                f"├ CPU    : {v['cpu'][:30]} ({v['cores']} cores)",
                f"├ RAM    : {v['ram_used']}/{v['ram_total']} ({v['ram_pct']})",
                f"├ Disk   : {v['disk_used']}/{v['disk_total']} ({v['disk_pct']})",
                f"├ Uptime : {v['uptime']}",
                f"╰ BW     : {bw_show} GB", ""]
        lines += ["───────────────────────", "</blockquote>"]
        rows = []
        for idx, key in enumerate(SERVERS.keys(), 1):
            rows.append([B(f"[{idx}] {SERVERS[key].get('name','-')}", f"admin|vps_detail|{key}", style="primary")])
        rows.append([B("🔄 Refresh", "admin|vps", style="success"), B("🔙 Kembali", "admin|menu", style="danger")])
        try: await q.edit_message_text("\n".join(lines), reply_markup=InlineKeyboardMarkup(rows), parse_mode="HTML")
        except: pass
        return
    if d.startswith("admin|vps_detail|"):
        if not is_owner(uid): return
        key = d.split("|")[2]
        if key not in SERVERS: await q.answer("Server tidak ditemukan", show_alert=True); return
        srv = SERVERS[key]
        try: await q.edit_message_text("⏳ <b>Memuat detail...</b>", parse_mode="HTML")
        except: pass
        v = await asyncio.to_thread(get_vps_detail, key)
        hl = "Local" if is_local_server(key) else "Remote"
        used = count_slots(key); mx = int(srv.get("slot_max", 50) or 50)
        stat = "🟢 Online" if max(0, mx-used) > 0 else "🔴 Full"
        dom = srv.get("domain", "-"); pm = srv.get("price_month", 0) or 0
        qg = srv.get("quota_gb", "-") or "-"; ip = srv.get("ip_limit", "-") or "-"
        ip_addr = srv.get('ssh_host', '127.0.0.1'); port_num = srv.get('ssh_port', 22)
        if ip_addr in ("127.0.0.1", "localhost", ""): real_ip = v.get("ip", "-") or "-"
        else: real_ip = ip_addr
        txt = (f"<blockquote><b>{srv.get('name','-')}</b>\n"
               f"<code>{real_ip}:{port_num}</code>\n───────────────────────\n"
               f"🖥️ <b>Sistem</b>\n├ OS      : {v['os']}\n├ Kernel  : <code>{v['kernel']}</code>\n"
               f"├ CPU     : {v['cpu']}\n╰ Cores   : <b>{v['cores']}</b>\n\n"
               f"💾 <b>Resource</b>\n├ RAM     : <b>{v['ram_used']}</b> / {v['ram_total']} ({v['ram_pct']})\n"
               f"├ Disk    : <b>{v['disk_used']}</b> / {v['disk_total']} ({v['disk_pct']})\n"
               f"├ Uptime  : <b>{v['uptime']}</b>\n╰ Load    : <b>{', '.join(v['load'])}</b>\n\n"
               f"🌐 <b>Network</b>\n├ IP      : <code>{real_ip}</code>\n"
               f"├ Port    : <code>{port_num}</code>\n├ Type    : <b>{hl}</b>\n"
               f"╰ Bandwidth : <b>{v['bw']:.2f} GB</b>\n\n"
               f"📊 <b>Config</b>\n├ Harga   : {rupiah(pm)}/bln\n├ Quota   : {qg} GB\n"
               f"├ Limit   : {ip} IP\n├ Slot    : <b>{used}/{mx}</b>\n├ Domain  : <code>{dom}</code>\n"
               f"╰ Status  : <b>{stat}</b>\n───────────────────────\n</blockquote>")
        try: await q.edit_message_text(txt, reply_markup=InlineKeyboardMarkup([
            [B("🔄 Refresh", f"admin|vps_detail|{key}", style="success")],
            [B("🔙 Kembali", "admin|vps", style="danger")]]), parse_mode="HTML")
        except: pass
        return

    if d == "admin|srv":
        if not is_owner(uid): return
        lines = ["<blockquote>", "💻 <b>KELOLA SERVER</b>", "───────────────────────", ""]
        for key, srv in SERVERS.items():
            tag = "" if is_server_complete(srv) else "  ⚠️"
            lines.append(f"<b>{srv.get('name','-')}{tag}</b>")
            pd = srv.get("price_day"); pm = srv.get("price_month")
            ip_l = srv.get("ip_limit"); sm = srv.get("slot_max")
            lines.append(f"├ Harga Harian  : <b>{rupiah(pd) if pd else '❌ Belum diisi'}</b>")
            lines.append(f"├ Harga Bulanan : <b>{rupiah(pm) if pm else '❌ Belum diisi'}</b>")
            lines.append(f"├ Limit IP      : <b>{ip_l} IP</b>" if ip_l else "├ Limit IP      : <b>❌ Belum diisi</b>")
            lines.append(f"╰ Slot Server  : <b>{sm}</b>" if sm else "╰ Slot Server  : <b>❌ Belum diisi</b>")
            lines.append("")
        lines += ["───────────────────────", "</blockquote>"]
        rows = []; keys_l = list(SERVERS.keys())
        for i in range(0, len(keys_l), 2):
            row = []
            for j in range(i, min(i+2, len(keys_l))):
                kk = keys_l[j]; srv = SERVERS[kk]
                lbl = srv.get('name','-') if is_server_complete(srv) else f"{srv.get('name','-')} ⚠️"
                row.append(B(lbl, f"srv_edit|{kk}", style="primary" if is_server_complete(srv) else "danger"))
            rows.append(row)
        rows.append([B("➕ TAMBAH SERVER", "srv_add", style="success"), B("🗑️ HAPUS SERVER", "srv_del_list", style="danger")])
        rows.append([B("🔙 Kembali", "admin|menu", style="danger")])
        try: await q.edit_message_text("\n".join(lines), reply_markup=InlineKeyboardMarkup(rows), parse_mode="HTML")
        except: pass
        return

    if d.startswith("srv_edit|"):
        if not is_owner(uid): return
        key = d.split("|")[1]
        if key not in SERVERS: await q.answer("Server tidak ditemukan", show_alert=True); return
        srv = SERVERS[key]; complete = is_server_complete(srv)
        pd = srv.get("price_day"); pm = srv.get("price_month")
        qg = srv.get("quota_gb"); ip = srv.get("ip_limit"); sm = srv.get("slot_max")
        dom = srv.get("domain", "")
        qg_str = f"{qg} GB" if qg else "❌"; pd_str = rupiah(pd) if pd else "❌"
        pm_str = rupiah(pm) if pm else "❌"; ip_str = f"{ip} IP" if ip else "❌"
        sm_str = f"{sm}" if sm else "❌"; dom_str = dom if dom else "❌"
        warn = "\n⚠️ <b>Lengkapi dulu agar tampil di menu user</b>\n" if not complete else "\n✅ <i>Server aktif</i>\n"
        txt = (f"<blockquote><b>{srv.get('name','-')}</b>\n───────────────────────\n\n"
            f"├ Harga Harian  : <b>{pd_str}</b>\n├ Harga Bulanan : <b>{pm_str}</b>\n"
            f"├ Qouta         : <b>{qg_str}</b>\n├ Limit IP      : <b>{ip_str}</b>\n"
            f"├ Slot Server   : <b>{sm_str}</b>\n╰ Domain       : <b>{dom_str}</b>\n{warn}</blockquote>")
        rows = [[B("Nama Server", f"srv_set|{key}|name", style="primary"), B("Harga Bulanan", f"srv_set|{key}|price_month", style="primary")],
            [B("Quota GB", f"srv_set|{key}|quota_gb", style="primary"), B("Limit IP", f"srv_set|{key}|ip_limit", style="primary")],
            [B("Slot Server", f"srv_set|{key}|slot_max", style="primary"), B("Domain Server", f"srv_set|{key}|domain", style="primary")]]
        if not is_local_server(key):
            rows.append([B("🔧 SSH Setting", f"srv_ssh|{key}", style="primary")])
            rows.append([B("🗑️ Hapus Server", f"srv_del|{key}", style="danger")])
        rows.append([B("🔙 Kembali", "admin|srv", style="danger")])
        try: await q.edit_message_text(txt, reply_markup=InlineKeyboardMarkup(rows), parse_mode="HTML")
        except: pass
        return

    if d.startswith("srv_set|"):
        if not is_owner(uid): return
        parts = d.split("|")
        if len(parts) < 3: return
        key = parts[1]; field = parts[2]
        if key not in SERVERS: await q.answer("Server tidak ditemukan", show_alert=True); return
        c.user_data["srv_edit"] = {"key": key, "field": field}
        prompts = {"name": "Kirim nama baru. Contoh: <code>🇮🇩 INDO PREMIUM</code>",
            "price_month": "Kirim harga BULANAN baru. Contoh: <code>3000</code>\n\n<i>Harga harian auto = bulanan ÷ 30</i>",
            "quota_gb": "Kirim QUOTA bandwidth baru (GB). Contoh: <code>700</code>",
            "ip_limit": "Kirim limit IP baru. Contoh: <code>1</code>",
            "slot_max": "Kirim jumlah slot baru. Contoh: <code>50</code>",
            "domain": "Kirim DOMAIN baru. Contoh: <code>sgivip.naaofficial.web.id</code>"}
        try: await q.edit_message_text(prompts.get(field, "Kirim nilai baru:"),
            reply_markup=InlineKeyboardMarkup([[B("❌ Batal", f"srv_edit|{key}", style="danger")]]), parse_mode="HTML")
        except: pass
        return

    if d == "srv_add":
        if not is_owner(uid): return
        c.user_data["srv_add_step"] = "input"
        try: await q.edit_message_text(
            "<blockquote>➕ <b>TAMBAH SERVER BARU</b>\n───────────────────────\n"
            "Format: <code>nama|ip|port</code>\n\nContoh:\n"
            "<code>🇮🇩 INDO PREMIUM|103.123.45.67|22</code>\n\n"
            "<i>Server lokal: pakai</i>\n<code>LOCAL|127.0.0.1|22</code>\n</blockquote>",
            reply_markup=InlineKeyboardMarkup([[B("❌ Batal", "admin|srv", style="danger")]]), parse_mode="HTML")
        except: pass
        return

    if d == "srv_del_list":
        if not is_owner(uid): return
        remote = {k: v for k, v in SERVERS.items() if not is_local_server(k)}
        if not remote:
            try: await q.edit_message_text(
                "<blockquote>🗑️ <b>HAPUS SERVER</b>\n───────────────────────\n"
                "⚠️ Tidak ada server remote.\n\n<i>Server lokal dilindungi.</i>\n</blockquote>",
                reply_markup=InlineKeyboardMarkup([[B("🔙 Kembali", "admin|srv", style="danger")]]), parse_mode="HTML")
            except: pass
            return
        rows = []
        for k, v in remote.items(): rows.append([B(v.get("name","-"), f"srv_del|{k}", style="danger")])
        rows.append([B("❌ Batal", "admin|srv", style="danger")])
        try: await q.edit_message_text("<blockquote>🗑️ <b>HAPUS SERVER</b>\n───────────────────────\nPilih server:\n</blockquote>",
            reply_markup=InlineKeyboardMarkup(rows), parse_mode="HTML")
        except: pass
        return

    if d.startswith("srv_del|"):
        if not is_owner(uid): return
        key = d.split("|")[1]
        if key not in SERVERS: await q.answer("Server tidak ditemukan", show_alert=True); return
        if is_local_server(key): await q.answer("❌ Server lokal dilindungi", show_alert=True); return
        srv = SERVERS[key]; used = count_slots(key)
        try: await q.edit_message_text(
            f"<blockquote>⚠️ <b>KONFIRMASI HAPUS</b>\n───────────────────────\n"
            f"Server : <b>{srv.get('name','-')}</b>\n"
            f"Host   : <code>{srv.get('ssh_host','-')}:{srv.get('ssh_port',22)}</code>\n"
            f"Akun   : <b>{used} user aktif</b>\n\n"
            f"🔴 <b>Akan DIHAPUS:</b>\n├ Config server di bot\n├ Semua user OS di VPS\n"
            f"├ Semua akun di JSON\n╰ SSH key file\n\n⚠️ <i>Tidak bisa dipulihkan!</i>\n</blockquote>",
            reply_markup=InlineKeyboardMarkup([[B("✅ Ya, Hapus", f"srv_del_yes|{key}", style="danger")],
                [B("❌ Batal", f"srv_edit|{key}", style="danger")]]), parse_mode="HTML")
        except: pass
        return

    if d.startswith("srv_del_yes|"):
        if not is_owner(uid): return
        key = d.split("|")[1]
        if key not in SERVERS: await q.answer("Server tidak ditemukan", show_alert=True); return
        if is_local_server(key): await q.answer("❌ Server lokal dilindungi", show_alert=True); return
        try: await q.edit_message_text("🗑️ <b>Menghapus server...</b>", parse_mode="HTML")
        except: pass
        srv = SERVERS[key]; deleted = 0
        try:
            code, out, _ = ssh_run("awk -F: '$3>=1000 && $3<60000 {print $1}' /etc/passwd", key, timeout=10)
            if code == 0:
                for un in out.split():
                    try:
                        ssh_run(f"pkill -9 -u {un} 2>/dev/null; userdel -r {un} 2>/dev/null", key, timeout=15)
                        deleted += 1
                    except: pass
        except: pass
        accs = load_json(ACCOUNTS_FILE, {}); removed = 0
        for un in list(accs.keys()):
            if accs[un].get("server_key") == key: accs.pop(un); removed += 1
        save_json(ACCOUNTS_FILE, accs)
        kf = srv.get("ssh_key")
        if kf and os.path.exists(kf):
            try: os.remove(kf)
            except: pass
            kfp = kf + ".pub"
            if os.path.exists(kfp):
                try: os.remove(kfp)
                except: pass
        SERVERS.pop(key, None); save_servers()
        try: await q.edit_message_text(
            f"<blockquote>✅ <b>Server Dihapus</b>\n───────────────────────\n"
            f"Server   : <b>{srv.get('name','-')}</b>\nUser OS  : <b>{deleted}</b>\n"
            f"Akun JSON: <b>{removed}</b>\n</blockquote>",
            reply_markup=InlineKeyboardMarkup([[B("💻 Kelola Server", "admin|srv", style="primary")],
                [B("🔙 Menu", "admin|menu", style="danger")]]), parse_mode="HTML")
        except: pass
        asyncio.create_task(sync_push_async()); return

    if d.startswith("srv_add_retry|"):
        if not is_owner(uid): return
        key_name = d.split("|")[1]
        pending = c.user_data.get("srv_add_pending", {})
        if not pending or pending.get("key") != key_name:
            await q.answer("Data tidak ditemukan", show_alert=True); return
        ssh_key = pending["ssh_key"]; ip = pending["ip"]; port = pending["port"]
        test_ok = await asyncio.to_thread(test_ssh_key, ssh_key, ip, port)
        if not test_ok: await q.answer("❌ Masih gagal. Cek key di VPS target.", show_alert=True); return
        SERVERS[key_name] = {"name": pending["nama"], "ssh_host": ip, "ssh_port": port, "ssh_user": "root",
            "ssh_key": ssh_key, "city": "-", "isp": "-", "ssh_ovpn": pending["nama"],
            "domain": None, "price_day": None, "price_month": None,
            "ip_limit": None, "slot_max": None, "quota_gb": None}
        save_servers(); c.user_data["srv_add_pending"] = None
        try: await q.edit_message_text(f"<blockquote>✅ <b>{pending['nama']} berhasil ditambahkan!</b>\n\n⚠️ Lengkapi data dulu.</blockquote>",
            reply_markup=InlineKeyboardMarkup([[B("💻 Kelola Server", "admin|srv", style="primary")],
                [B("🔙 Menu", "admin|menu", style="danger")]]), parse_mode="HTML")
        except: pass
        asyncio.create_task(sync_push_async()); return

    if d.startswith("srv_ssh|"):
        if not is_owner(uid): return
        key = d.split("|")[1]
        if key not in SERVERS: await q.answer("Server tidak ditemukan", show_alert=True); return
        srv = SERVERS[key]
        try: await q.edit_message_text(
            f"<blockquote>🔧 <b>SSH SETTING</b>\n───────────────────────\n"
            f"Server : <b>{srv.get('name','-')}</b>\n"
            f"Host   : <code>{srv.get('ssh_host','-')}</code>\n"
            f"Port   : <code>{srv.get('ssh_port',22)}</code>\n"
            f"User   : <code>{srv.get('ssh_user','root')}</code>\n"
            f"Key    : <code>{srv.get('ssh_key','-')}</code>\n</blockquote>",
            reply_markup=InlineKeyboardMarkup([[B("🔙 Kembali", f"srv_edit|{key}", style="danger")]]), parse_mode="HTML")
        except: pass
        return

    if d == "admin|menu":
        if not is_owner(uid): return
        inc = get_income(); us = count_users_by_period()
        svr_stat = get_server_status()
        svr_parts = []
        for s in svr_stat:
            tag = "" if s["complete"] else " ⚠️"
            bw = s["bw"]; bw_show = f"{bw:.0f}" if bw >= 1 else f"{bw:.1f}"
            svr_parts.append(f"├ {s['name']}{tag}\n│ ├ Qouta  : <b>{bw_show}/{s['quota']}</b>\n│ ├ Slot   : <b>{s['used']}/{s['max']}</b>\n│ ╰ Status : <b>{s['status']}</b>")
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
        try: await q.edit_message_text(txt, reply_markup=kb_admin(), parse_mode="HTML")
        except: pass
        return

    if d.startswith("admin|users|"):
        if not is_owner(uid): return
        try: page = int(d.split("|")[2])
        except: page = 0
        users = load_json(USERS_FILE, {})
        keys = [k for k in users.keys() if int(k) not in ADMIN_IDS]
        keys.sort(key=lambda k: users[k].get("last_seen",""), reverse=True)
        total = len(keys); per = 10; tp = max(1, (total + per - 1) // per)
        page = max(0, min(page, tp - 1)); chunk = keys[page*per:(page+1)*per]
        lines = ["<blockquote>", "👤 <b>Pengguna</b>", "──────────────────────", f"Total: <b>{total}</b>", ""]
        for i, k in enumerate(chunk, start=page*per+1): lines.append(f"{i}. 👤 {users[k].get('first_name') or '-'}")
        lines += ["", "──────────────────────", f"Hal {page+1}/{tp}", "──────────────────────", "</blockquote>"]
        rows = []
        for k in chunk:
            n = users.get(k, {}).get("first_name") or "-"
            rows.append([B(f"👤 {n}", f"admin|user|{k}|{page}", style="primary")])
        nav = []
        if page > 0: nav.append(B("◀ Prev", f"admin|users|{page-1}", style="primary"))
        nav.append(B(f"{page+1}/{tp}", "noop", style="primary"))
        if page < tp - 1: nav.append(B("Next ▶", f"admin|users|{page+1}", style="primary"))
        if nav: rows.append(nav)
        rows.append([B("🔄 Refresh", f"admin|users|{page}", style="success"), B("🔙 Kembali", "admin|menu", style="danger")])
        try: await q.edit_message_text("\n".join(lines), reply_markup=InlineKeyboardMarkup(rows), parse_mode="HTML")
        except: pass
        return

    if d.startswith("admin|user|"):
        if not is_owner(uid): return
        parts = d.split("|")
        if len(parts) < 4: return
        target_uid = parts[2]
        try: page = int(parts[3])
        except: page = 0
        users = load_json(USERS_FILE, {}); uu = users.get(str(target_uid), {})
        name = uu.get("first_name") or "-"; uname = uu.get("username") or "-"
        ls = (uu.get("last_seen") or "-")[:10]; saldo = get_bal(target_uid)
        top = get_user_topup_stats(target_uid)
        txt = (f"<blockquote>👤 <b>{name}</b>\n├ Username : @{uname if uname != '-' else '-'}\n"
               f"├ Chat ID : <code>{target_uid}</code>\n├ Bergabung : {ls}\n╰ Saldo : <b>{rupiah(saldo)}</b>\n\n"
               f"💰 <b>Riwayat Topup</b>\n├ Hari Ini : {rupiah(top['hari'])}\n"
               f"├ Minggu : {rupiah(top['minggu'])}\n╰ Total : {rupiah(top['total'])}</blockquote>")
        kb = InlineKeyboardMarkup([[B("🔄 Refresh", f"admin|user|{target_uid}|{page}", style="success")],
            [B("🔙 Kembali", f"admin|users|{page}", style="danger")]])
        try: await q.edit_message_text(txt, reply_markup=kb, parse_mode="HTML")
        except: pass
        return

    if d == "admin|bc":
        if not is_owner(uid): return
        c.user_data["bc_wait"] = True
        try: await q.edit_message_text("📢 <b>BROADCAST</b>\n\nKetik pesan:",
            reply_markup=InlineKeyboardMarkup([[B("❌ Batal", "admin|menu", style="danger")]]), parse_mode="HTML")
        except: pass
        return
    if d == "bc_send":
        if not is_owner(uid): return
        msg_text = c.user_data.get("bc_text", "")
        if not msg_text: await q.answer("Pesan kosong!", show_alert=True); return
        try: await q.edit_message_text("📤 Mengirim...", parse_mode="HTML")
        except: pass
        users = load_json(USERS_FILE, {}); ok_c = 0; fail_c = 0
        for tuid in users.keys():
            try:
                await c.bot.send_message(chat_id=int(tuid), text=msg_text, parse_mode="HTML")
                ok_c += 1
            except Exception: fail_c += 1
            await asyncio.sleep(0.05)
        c.user_data["bc_text"] = ""; c.user_data["bc_wait"] = False
        try: await q.edit_message_text(f"✅ <b>Selesai</b>\n\n├ Sukses: <b>{ok_c}</b>\n╰ Gagal: <b>{fail_c}</b>",
            reply_markup=InlineKeyboardMarkup([[B("🔙 Kembali", "admin|menu", style="danger")]]), parse_mode="HTML")
        except: pass
        return

    if d.startswith("extend|"):
        if c.user_data.get("created_in_session"): return
        server_key = d.split("|")[1]
        if server_key not in SERVERS: await chat.send_message("❌ Server tidak valid.", parse_mode="HTML"); return
        try: await q.edit_message_reply_markup(reply_markup=kb_ssh_server_locked())
        except: pass
        c.user_data["extend_step"] = "username"; c.user_data["extend_data"] = {"server_key": server_key}
        await chat.send_message("👤 <b>Masukkan username akun :</b>", parse_mode="HTML")
        return

    if d.startswith("buat|"):
        if c.user_data.get("created_in_session"): return
        server_key = d.split("|")[1]
        if server_key not in SERVERS: await chat.send_message("❌ Server tidak valid.", parse_mode="HTML"); return
        used, mx = get_slot_info(server_key)
        if used >= mx:
            await chat.send_message(f"<blockquote>❌ <b>Slot Penuh</b> {used}/{mx}</blockquote>", parse_mode="HTML"); return
        mode = c.user_data.get("mode", "buat")
        try: await q.edit_message_reply_markup(reply_markup=kb_ssh_server_locked())
        except: pass
        if mode == "trial":
            if trial_left(uid) <= 0:
                await chat.send_message("🚫 <b>Batas trial hari ini tercapai.</b>", parse_mode="HTML"); return
            use_trial(uid)
            uniq = ''.join(random.choices(string.ascii_lowercase + string.digits, k=4))
            c.user_data.clear(); c.user_data["created_in_session"] = True
            await do_create_account(chat, uid, u.effective_user, f"trial-{uniq}", f"trial{uniq}", 1, is_trial=True, server_key=server_key)
            return
        else:
            c.user_data["buat_step"] = "username"; c.user_data["buat_data"] = {"server_key": server_key}
            await chat.send_message("👤 <b>Masukkan username akun :</b>", parse_mode="HTML")
            return

    if d == "my_accs":
        accs = []
        for a in get_user_accs(uid):
            if a.get("is_trial"): continue
            try:
                ed = datetime.strptime(a["exp"], "%Y-%m-%d").date()
                if (ed - datetime.now().date()).days < 0: continue
            except: continue
            accs.append(a)
        hdr = ["<blockquote>", "💻 <b>AKUN SAYA</b>", "───────────────────────", "",
               f"📭 Akun Aktif : <b>{len(accs)}</b>", ""]
        if not accs: hdr += ["Belum ada akun aktif.", ""]
        hdr += ["───────────────────────", "</blockquote>"]
        if not accs:
            rows = [[B("➕ BUAT AKUN", "buat_akun", style="primary")], [B("🔙 KEMBALI", "menu|main", style="danger")]]
        else:
            rows = []
            for a in accs[:20]:
                un = a.get("username",""); b = get_block_info(un)
                label = f"🚫 {un} (DIBLOKIR)" if b else f"👤 {un}"
                rows.append([B(label, f"acc_detail|{un}", style="primary")])
            rows.append([B("🔙 KEMBALI", "menu|main", style="danger")])
        try: await q.edit_message_text("\n".join(hdr), reply_markup=InlineKeyboardMarkup(rows), parse_mode="HTML")
        except: pass
        return

    if d.startswith("acc_detail|"):
        un = d.split("|",1)[1]; a = get_acc(un)
        if not a or a.get("user_id") != uid: await q.answer("No", show_alert=True); return
        sk = a.get("server_key", "sg_1ip")
        dl_txt = f"{TRIAL_DURATION_MIN} Minute" if a.get("is_trial") else f"{a.get('days',30)} Hari"
        ref = 0 if (a.get("is_trial") or int(a.get("harga",0)) <= 0) else hitung_refund(a)
        cap = acc_caption(un, a['password'], a['exp'], dl_txt, a.get('limit_ip',IP_LIMIT), a.get('manual',False), a.get('is_trial',False), sk)
        try:
            ed = datetime.strptime(a["exp"], "%Y-%m-%d").date()
            sh = max(0,(ed-datetime.now().date()).days); th = int(a.get("days",30))
        except: sh = 0; th = 30
        b = get_block_info(un)
        if b:
            try:
                ua = datetime.strptime(b["unblock_at"], "%Y-%m-%d %H:%M:%S")
                total_min = max(0, int((ua - datetime.now()).total_seconds() // 60))
                cap += f"\n\n🚫 <b>AKUN DIBLOKIR</b>\n╰ Terbuka: <b>{total_min//60}j {total_min%60}m</b>"
            except: pass
        else:
            if ref > 0: cap += f"\n\n💰 <b>Refund: {rupiah(ref)}</b>\n<i>({sh}/{th} hari)</i>"
            else: cap += f"\n\n💰 <i>Refund: Rp 0</i>"
        try: await q.edit_message_text(cap, reply_markup=kb_acc_detail(un), parse_mode="HTML")
        except: pass
        return
    if d.startswith("del_acc|"):
        un = d.split("|",1)[1]; a = get_acc(un)
        if not a or a.get("user_id") != uid: await q.answer("No", show_alert=True); return
        ref = 0 if (a.get("is_trial") or int(a.get("harga", 0)) <= 0) else hitung_refund(a)
        await _do_delete_account(uid, un, u.effective_user, chat)
        try: await q.delete_message()
        except: pass
        sb = get_bal(uid)
        if ref > 0:
            try: await chat.send_message(f"✅ <b>Akun Dihapus</b>\n\n👤 <code>{un}</code>\n💰 Refund: <b>{rupiah(ref)}</b>\n💼 Saldo: <b>{rupiah(sb)}</b>", parse_mode="HTML")
            except: pass
        else:
            try: await chat.send_message(f"✅ <b>Akun Dihapus</b>\n\n👤 <code>{un}</code>", parse_mode="HTML")
            except: pass
        return

def get_user_topup_stats(uid_key):
    d = load_json(TRX_FILE, [])
    today = datetime.now().strftime("%Y-%m-%d"); week = (datetime.now() - timedelta(days=7)).strftime("%Y-%m-%d")
    tops = [t for t in d if str(t.get("user_id")) == str(uid_key) and t.get("tipe") == "isi_saldo"]
    return {"hari": sum(t["jumlah"] for t in tops if t["waktu"].startswith(today)),
            "minggu": sum(t["jumlah"] for t in tops if t["waktu"][:10] >= week),
            "total": sum(t["jumlah"] for t in tops)}

async def msg(u, c):
    uid = u.effective_user.id
    track_user(u.effective_user)
    t = (u.message.text or "").strip()

    backup_field = c.user_data.get("backup_field")
    if backup_field and is_owner(uid):
        c.user_data["backup_field"] = None
        if backup_field == "token":
            try: await u.message.delete()
            except: pass
        old_conf = load_backup_conf(); conf = dict(old_conf); err = None
        if backup_field == "user":
            if not re.match(r'^[a-zA-Z0-9-]+$', t): err = "Username tidak valid"
            else: conf["GH_USER"] = t
        elif backup_field == "repo":
            if not re.match(r'^[a-zA-Z0-9._-]+$', t): err = "Nama repo tidak valid"
            else: conf["GH_REPO"] = t
        elif backup_field == "token":
            if not (t.startswith("ghp_") or t.startswith("github_pat_")) or len(t) < 20:
                err = "Format token harus ghp_xxx / github_pat_xxx"
            else: conf["GH_TOKEN"] = t
        elif backup_field == "email":
            if "@" not in t or "." not in t: err = "Email tidak valid"
            else: conf["GH_EMAIL"] = t
        if err:
            await u.message.reply_text(f"❌ {err}\n\nCoba lagi:", parse_mode="HTML")
            c.user_data["backup_field"] = backup_field; return
        changed = (old_conf.get(f"GH_{backup_field.upper()}") != conf.get(f"GH_{backup_field.upper()}"))
        save_backup_conf(conf["GH_USER"], conf["GH_REPO"], conf["GH_TOKEN"], conf["GH_EMAIL"])
        all_ok = all([conf["GH_USER"], conf["GH_REPO"], conf["GH_TOKEN"], conf["GH_EMAIL"]])
        if all_ok:
            notify_txt = "⏳ <b>Pull dari GitHub...</b>"
            if changed: notify_txt = "⏳ <b>Field berubah!</b>\n🗑️ Hapus folder lama...\n📥 Pull fresh..."
            notify = await u.message.reply_text(notify_txt, parse_mode="HTML")
            if changed:
                if os.path.exists("/root/vpnbot_backup"):
                    try: shutil.rmtree("/root/vpnbot_backup")
                    except: pass
                subprocess.run("crontab -l 2>/dev/null | grep -v vpnbot_backup.sh | crontab -", shell=True)
            ok, info = await asyncio.to_thread(setup_backup_env, conf["GH_USER"], conf["GH_REPO"], conf["GH_TOKEN"], conf["GH_EMAIL"])
            if ok:
                ccount, scount = await asyncio.to_thread(restore_ssh_users_from_json)
                try: await notify.delete()
                except: pass
                tag = "🔄 <b>Re-setup</b>" if changed else "✅ <b>Disimpan!</b>"
                await u.message.reply_text(f"{tag}\n\n<blockquote>✅ Auto backup aktif\n"
                    f"✅ File JSON direstore : <b>{info}</b>\n✅ User OS dibuat ulang : <b>{ccount}</b>\n"
                    f"╰ Skip : <b>{scount}</b>\n</blockquote>\n\n" + backup_config_text(),
                    reply_markup=kb_backup(), parse_mode="HTML")
            else:
                try: await notify.delete()
                except: pass
                await u.message.reply_text(f"❌ <b>Gagal</b>\n<code>{str(info)[:200]}</code>", reply_markup=kb_backup(), parse_mode="HTML")
        else:
            await u.message.reply_text(f"✅ <b>Disimpan!</b>\n\n" + backup_config_text(), reply_markup=kb_backup(), parse_mode="HTML")
        return

    if c.user_data.get("srv_add_step") == "input" and is_owner(uid):
        c.user_data["srv_add_step"] = None
        parts = t.split("|")
        if len(parts) != 3:
            await u.message.reply_text("❌ <b>Format salah!</b>\n\nHarus: <code>nama|ip|port</code>\n\nKetik ulang:", parse_mode="HTML")
            c.user_data["srv_add_step"] = "input"; return
        nama, ip, port_str = parts[0].strip(), parts[1].strip(), parts[2].strip()
        try: port = int(port_str)
        except: port = 22
        key_name = re.sub(r'[^a-z0-9]', '_', nama.lower())[:15] or f"srv_{int(time.time())}"
        if key_name in SERVERS: key_name = f"{key_name}_{random.randint(100,999)}"
        notify = await u.message.reply_text(f"⏳ <b>Testing koneksi ke {ip}:{port}...</b>", parse_mode="HTML")
        is_local = ip in ("127.0.0.1", "localhost", "")
        if is_local:
            try: await notify.delete()
            except: pass
            SERVERS[key_name] = {"name": nama, "ssh_host": ip, "ssh_port": port, "ssh_user": "root",
                "ssh_key": SSH_KEY_PATH, "city": "-", "isp": "-", "ssh_ovpn": nama,
                "domain": None, "price_day": None, "price_month": None,
                "ip_limit": None, "slot_max": None, "quota_gb": None}
            save_servers()
            v = await asyncio.to_thread(get_vps_detail, key_name)
            try: await u.message.reply_text(f"<blockquote>✅ <b>Server {nama} berhasil ditambahkan!</b>\n"
                f"📡 {v['os'][:30]} | {v['cores']} cores | {v['ram_total']} RAM | Upd {v['uptime']}\n\n"
                f"⚠️ <b>Lengkapi data dulu!</b></blockquote>", parse_mode="HTML")
            except: pass
            asyncio.create_task(sync_push_async())
            return
        ssh_key, pubkey = gen_ssh_key(key_name)
        test_ok = await asyncio.to_thread(test_ssh_key, ssh_key, ip, port)
        try: await notify.delete()
        except: pass
        if not test_ok:
            c.user_data["srv_add_pending"] = {"key": key_name, "nama": nama, "ip": ip, "port": port, "ssh_key": ssh_key}
            try:
                await u.message.reply_text(
                    f"<blockquote>🔐 <b>PERLU SSH KEY</b>\n───────────────────────\n"
                    f"Server  : <b>{nama}</b>\nHost    : <code>{ip}:{port}</code>\n\n"
                    f"Copy public key ke VPS target:\n\n<code>{pubkey}</code>\n\n"
                    f"Atau jalankan di VPS target:\n"
                    f"<code>mkdir -p ~/.ssh && echo \"{pubkey}\" >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys</code>\n\n"
                    f"Setelah selesai, klik tombol di bawah:</blockquote>",
                    reply_markup=InlineKeyboardMarkup([
                        [B("✅ Sudah, Test Ulang", f"srv_add_retry|{key_name}", style="success")],
                        [B("❌ Batal", "admin|srv", style="danger")]]), parse_mode="HTML")
            except: pass
            return
        SERVERS[key_name] = {"name": nama, "ssh_host": ip, "ssh_port": port, "ssh_user": "root",
            "ssh_key": ssh_key, "city": "-", "isp": "-", "ssh_ovpn": nama,
            "domain": None, "price_day": None, "price_month": None,
            "ip_limit": None, "slot_max": None, "quota_gb": None}
        save_servers()
        v = await asyncio.to_thread(get_vps_detail, key_name)
        try: await u.message.reply_text(f"<blockquote>✅ <b>Server {nama} berhasil ditambahkan!</b>\n"
            f"📡 {v['os'][:30]} | {v['cores']} cores | {v['ram_total']} RAM | Upd {v['uptime']}\n\n"
            f"⚠️ <b>Lengkapi data dulu!</b></blockquote>", parse_mode="HTML")
        except: pass
        asyncio.create_task(sync_push_async())
        return

    srv_edit = c.user_data.get("srv_edit")
    if srv_edit and is_owner(uid):
        key = srv_edit.get("key"); field = srv_edit.get("field"); val = t.strip()
        if key not in SERVERS:
            c.user_data["srv_edit"] = None
            await u.message.reply_text("❌ Server tidak ditemukan.", parse_mode="HTML"); return
        srv = SERVERS[key]
        try:
            if field == "name":
                if len(val) < 3: await u.message.reply_text("❌ Minimal 3 karakter.", parse_mode="HTML"); return
                srv["name"] = val; out = f"Nama → <b>{val}</b>"
            elif field == "price_month":
                angka = int(re.sub(r'[^0-9]','',val))
                if angka <= 0: await u.message.reply_text("❌ Angka tidak valid.", parse_mode="HTML"); return
                srv["price_month"] = angka; srv["price_day"] = max(1, int(round(angka / 30)))
                out = f"Bulanan → <b>{rupiah(angka)}</b>\nHarian → <b>{rupiah(srv['price_day'])}</b>"
            elif field == "quota_gb":
                angka = int(re.sub(r'[^0-9]','',val))
                if angka <= 0: await u.message.reply_text("❌ Angka tidak valid.", parse_mode="HTML"); return
                srv["quota_gb"] = angka; out = f"Quota → <b>{angka} GB</b>"
            elif field == "ip_limit":
                angka = int(re.sub(r'[^0-9]','',val))
                if angka <= 0: await u.message.reply_text("❌ Angka tidak valid.", parse_mode="HTML"); return
                srv["ip_limit"] = angka; out = f"Limit IP → <b>{angka}</b>"
            elif field == "slot_max":
                angka = int(re.sub(r'[^0-9]','',val))
                if angka <= 0: await u.message.reply_text("❌ Angka tidak valid.", parse_mode="HTML"); return
                srv["slot_max"] = angka; out = f"Slot → <b>{angka}</b>"
            elif field == "domain":
                srv["domain"] = val; out = f"Domain → <b>{val}</b>"
            else:
                c.user_data["srv_edit"] = None
                await u.message.reply_text("❌ Field tidak valid.", parse_mode="HTML"); return
            save_servers(); c.user_data["srv_edit"] = None
            complete = is_server_complete(srv)
            info = "✅ Lengkap — tampil di menu user" if complete else "⚠️ Masih ada data kosong"
            await u.message.reply_text(f"✅ <b>{out}</b>\n\n{info}",
                reply_markup=InlineKeyboardMarkup([[B("◀️ Kembali ke Server", f"srv_edit|{key}", style="primary")]]),
                parse_mode="HTML")
            asyncio.create_task(sync_push_async())
            return
        except Exception as e:
            await u.message.reply_text(f"❌ Error: {e}", parse_mode="HTML"); return

    if c.user_data.get("bc_wait") and is_owner(uid):
        c.user_data["bc_wait"] = False; c.user_data["bc_text"] = t
        await u.message.reply_text(f"📢 <b>PREVIEW</b>\n\n<blockquote>{t}</blockquote>\n\nKirim ke semua?",
            reply_markup=InlineKeyboardMarkup([[B("✅ Kirim", "bc_send", style="success")],
                [B("❌ Batal", "admin|menu", style="danger")]]), parse_mode="HTML")
        return

    step = c.user_data.get("buat_step")
    if step:
        data = c.user_data.get("buat_data",{})
        if step == "username":
            if not valid_username(t):
                await u.message.reply_text("🚫 <b>Username minimal 5 karakter</b>", parse_mode="HTML")
                await u.message.reply_text("👤 Masukkan username akun :", parse_mode="HTML"); return
            if is_username_taken(t):
                await u.message.reply_text(f"🚫 <b>Username {t} sudah ada</b>", parse_mode="HTML")
                await u.message.reply_text("👤 Masukkan username akun :", parse_mode="HTML"); return
            data["username"] = t; c.user_data["buat_data"] = data; c.user_data["buat_step"] = "password"
            await u.message.reply_text("🔑 Masukkan password akun :", parse_mode="HTML"); return
        if step == "password":
            if not valid_password(t):
                await u.message.reply_text("🚫 <b>Password minimal 5 karakter</b>", parse_mode="HTML")
                await u.message.reply_text("🔑 Masukkan password akun :", parse_mode="HTML"); return
            data["password"] = t; c.user_data["buat_data"] = data; c.user_data["buat_step"] = "durasi"
            await u.message.reply_text("📆 Masukkan masa aktif 1-30 (hari) :", parse_mode="HTML"); return
        if step == "durasi":
            if not t.isdigit():
                await u.message.reply_text("🚫 <b>Harus angka! Contoh: 30</b>", parse_mode="HTML")
                await u.message.reply_text("📆 Masukkan masa aktif 1-30 (hari) :", parse_mode="HTML"); return
            hari = int(t)
            if not (HARI_MIN <= hari <= HARI_MAX):
                await u.message.reply_text(f"🚫 <b>Masa aktif harus {HARI_MIN}-{HARI_MAX} hari.</b>", parse_mode="HTML")
                await u.message.reply_text("📆 Masukkan masa aktif 1-30 (hari) :", parse_mode="HTML"); return
            un = data.get("username"); pw = data.get("password")
            server_key = data.get("server_key", "sg_1ip"); price = get_price(hari, server_key)
            c.user_data["buat_step"] = None; c.user_data["buat_data"] = {}
            if not is_backup_ready():
                await u.message.reply_text("<blockquote>⚠️ <b>BACKUP BELUM SIAP</b></blockquote>", parse_mode="HTML"); return
            if get_bal(uid) < price:
                kb = InlineKeyboardMarkup([[B("💰 TOPUP SALDO", "isi_saldo", style="primary")],[B("🔙 Kembali", "menu|main", style="danger")]])
                await u.message.reply_text(f"<blockquote>❌ <b>Saldo Tidak Cukup</b>\n\n💰 Saldo: <b>{rupiah(get_bal(uid))}</b>\n💵 Harga: <b>{rupiah(price)}</b>\n📉 Kurang: <b>{rupiah(price - get_bal(uid))}</b></blockquote>",
                    reply_markup=kb, parse_mode="HTML"); return
            c.user_data["created_in_session"] = True
            await do_create_account(u.effective_chat, uid, u.effective_user, un, pw, hari, server_key=server_key)
            return

    estep = c.user_data.get("extend_step")
    if estep:
        data = c.user_data.get("extend_data", {})
        server_key = data.get("server_key", "sg_1ip")
        if estep == "username":
            if not is_username_taken(t):
                await u.message.reply_text("🚫 <b>Akun tidak ditemukan.</b>", parse_mode="HTML")
                await u.message.reply_text("👤 Masukkan username akun :", parse_mode="HTML"); return
            a = get_acc(t)
            if not a or a.get("user_id") != uid:
                await u.message.reply_text("🚫 <b>Bukan akun Anda.</b>", parse_mode="HTML")
                await u.message.reply_text("👤 Masukkan username akun :", parse_mode="HTML"); return
            if a.get("is_trial"):
                await u.message.reply_text("🚫 <b>Akun trial tidak bisa diperpanjang.</b>", parse_mode="HTML")
                await u.message.reply_text("👤 Masukkan username akun :", parse_mode="HTML"); return
            data["username"] = t; c.user_data["extend_data"] = data; c.user_data["extend_step"] = "password"
            await u.message.reply_text("🔑 Masukkan password akun :", parse_mode="HTML"); return
        if estep == "password":
            a = get_acc(data.get("username"))
            if not a or a.get("password") != t:
                await u.message.reply_text("🚫 <b>Password salah.</b>", parse_mode="HTML")
                await u.message.reply_text("🔑 Masukkan password akun :", parse_mode="HTML"); return
            c.user_data["extend_step"] = "durasi"
            await u.message.reply_text("📆 Masukkan masa aktif 1-30 (hari) :", parse_mode="HTML"); return
        if estep == "durasi":
            if not t.isdigit():
                await u.message.reply_text("🚫 <b>Harus angka!</b>", parse_mode="HTML")
                await u.message.reply_text("📆 Masukkan masa aktif 1-30 (hari) :", parse_mode="HTML"); return
            hari = int(t)
            if not (HARI_MIN <= hari <= HARI_MAX):
                await u.message.reply_text(f"🚫 <b>Harus {HARI_MIN}-{HARI_MAX} hari.</b>", parse_mode="HTML")
                await u.message.reply_text("📆 Masukkan masa aktif 1-30 (hari) :", parse_mode="HTML"); return
            un = data.get("username")
            c.user_data["extend_step"] = None; c.user_data["extend_data"] = {}
            c.user_data["created_in_session"] = True
            await do_extend_account(u.effective_chat, uid, u.effective_user, un, hari, server_key)
            return

async def handle_photo(u, c):
    await u.message.reply_text("Gunakan /start", reply_markup=ReplyKeyboardRemove())

async def post_init(app):
    try: await app.bot.set_my_commands([BotCommand("start", "⌂ Menu")])
    except: pass
    asyncio.create_task(auto_cleanup_task())
    ok, msg = await asyncio.to_thread(ssh_test, "sg_1ip")
    logger.info(f"[STARTUP] {msg}")
    if is_backup_ready():
        try:
            conf = load_backup_conf()
            ok, restored = await asyncio.to_thread(setup_backup_env, conf["GH_USER"], conf["GH_REPO"], conf["GH_TOKEN"], conf["GH_EMAIL"])
            if ok: logger.info(f"[STARTUP-PULL] {restored} JSON direstore")
        except Exception as e: logger.error(f"[STARTUP-PULL] {e}")
    try:
        c, s = await asyncio.to_thread(restore_ssh_users_from_json)
        if c > 0: logger.info(f"[RESTORE] {c} user direstore")
    except Exception as e: logger.error(f"restore: {e}")

def main():
    app = Application.builder().token(BOT_TOKEN).post_init(post_init).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CallbackQueryHandler(cb))
    app.add_handler(MessageHandler(filters.PHOTO, handle_photo))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, msg))
    app.run_polling(allowed_updates=Update.ALL_TYPES)

if __name__ == "__main__":
    main()
BOTPYEOF
chmod +x /root/bot.py

python3 -m py_compile /root/bot.py 2>&1 | tee /root/bot_compile.log >/dev/null
[ -s /root/bot_compile.log ] && echo -e "  ${RED}❌ Bot error — cek /root/bot_compile.log${NC}"

# 7. START BOT
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

# ═══════════════════════════════════════════════════════════
# 8. INSTALL MENU VPS KEREN
# ═══════════════════════════════════════════════════════════
echo ""
echo -e "  ${YELLOW}▸ Install Menu VPS Keren${NC}"

cat > /usr/local/bin/sansxml-menu << 'MENUEOF'
#!/bin/bash
CYAN='\033[1;36m'; GREEN='\033[1;32m'; RED='\033[1;31m'
YELLOW='\033[1;33m'; MAGENTA='\033[1;35m'; WHITE='\033[1;37m'; NC='\033[0m'

get_ip(){ hostname -I 2>/dev/null | awk '{print $1}'; }
get_uptime(){
    local s=$(cat /proc/uptime 2>/dev/null | awk '{print int($1)}')
    echo "$((s/86400))d $(((s%86400)/3600))h $(((s%3600)/60))m"
}
get_ram(){
    local tk=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local ak=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    local uk=$((tk-ak))
    echo "$(awk "BEGIN{printf \"%.1f\", $uk/1024/1024}")/$(awk "BEGIN{printf \"%.1f\", $tk/1024/1024}") GB"
}
get_disk(){ df -h / 2>/dev/null | tail -1 | awk '{print $3" / "$2" ("$5")"}'; }
get_bw(){
    vnstat --json m 1 2>/dev/null | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin); m=d.get("interfaces",[{}])[0].get("traffic",{}).get("month",[])
    if m: print(f"{(m[-1].get(\"rx\",0)+m[-1].get(\"tx\",0))/1024**3:.2f} GB")
    else: print("0 GB")
except: print("N/A")' 2>/dev/null || echo "N/A"
}

show_menu(){
    clear
    local ip=$(get_ip)
    local bot_status=$(systemctl is-active vpnbot 2>/dev/null || echo "off")
    local vpn_status=$(systemctl is-active ws-ssh 2>/dev/null || echo "off")
    local stun_status=$(systemctl is-active stunnel4 2>/dev/null || echo "off")
    local udpgw_status=$(systemctl is-active udpgw 2>/dev/null || echo "off")

    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║${NC}    ${CYAN}███████╗ █████╗ ███╗   ██╗███████╗██╗  ██╗███╗   ███╗██╗${NC}    ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}║${NC}    ${CYAN}██╔════╝██╔══██╗████╗  ██║██╔════╝╚██╗██╔╝████╗ ████║██║${NC}    ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}║${NC}    ${CYAN}███████╗███████║██╔██╗ ██║███████╗ ╚███╔╝ ██╔████╔██║██║${NC}    ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}║${NC}    ${CYAN}╚════██║██╔══██║██║╚██╗██║╚════██║ ██╔██╗ ██║╚██╔╝██║██║${NC}    ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}║${NC}    ${CYAN}███████║██║  ██║██║ ╚████║███████║██╔╝ ██╗██║ ╚═╝ ██║███████╗${NC}${MAGENTA}║${NC}"
    echo -e "${MAGENTA}║${NC}    ${CYAN}╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝${NC}${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${MAGENTA}║${NC}       ${YELLOW}⭐  SC BOT TELEGRAM VPN STORE  ⭐${NC}                        ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}║${NC}         ${WHITE}Premium VPN Server — AUTO INSTALL${NC}                    ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${MAGENTA}║${NC}  ${CYAN}IP Public${NC}    : ${GREEN}${ip}${NC}"
    echo -e "${MAGENTA}║${NC}  ${CYAN}Uptime${NC}       : ${WHITE}$(get_uptime)${NC}"
    echo -e "${MAGENTA}║${NC}  ${CYAN}RAM${NC}          : ${WHITE}$(get_ram)${NC}"
    echo -e "${MAGENTA}║${NC}  ${CYAN}Disk${NC}         : ${WHITE}$(get_disk)${NC}"
    echo -e "${MAGENTA}║${NC}  ${CYAN}Bandwidth${NC}    : ${WHITE}$(get_bw)${NC}"
    echo -e "${MAGENTA}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -ne "${MAGENTA}║${NC}  ${CYAN}Services${NC}     : "
    [ "$bot_status" = "active" ] && echo -ne "${GREEN}●Bot${NC} " || echo -ne "${RED}○Bot${NC} "
    [ "$vpn_status" = "active" ] && echo -ne "${GREEN}●WS-SSH${NC} " || echo -ne "${RED}○WS-SSH${NC} "
    [ "$stun_status" = "active" ] && echo -ne "${GREEN}●SSL${NC} " || echo -ne "${RED}○SSL${NC} "
    [ "$udpgw_status" = "active" ] && echo -ne "${GREEN}●UDP${NC} " || echo -ne "${RED}○UDP${NC} "
    echo ""
    echo -e "${MAGENTA}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${MAGENTA}║${NC}                                                              ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}║${NC}    ${RED}[1]${NC}  🗑️  ${WHITE}STOP BOT & UNINSTALL SEMUA SC${NC}                     ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}║${NC}    ${CYAN}[2]${NC}  💻  ${WHITE}CEK DETAIL VPS${NC}                                   ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}║${NC}    ${GREEN}[3]${NC}  🚪  ${WHITE}EXIT${NC}                                              ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}║${NC}                                                              ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -ne "  ${YELLOW}➤  Pilih menu [1-3] : ${NC}"
}

do_uninstall(){
    clear
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║${NC}     ${RED}⚠️   UNINSTALL SEMUA SC — BERSIHKAN VPS   ⚠️${NC}              ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${YELLOW}Akan dihapus:${NC}"
    echo -e "  ├ 🗑️  Bot Telegram + data JSON"
    echo -e "  ├ 🗑️  VPN Services (WS-SSH, Stunnel, UDPGW)"
    echo -e "  ├ 🗑️  Semua user VPN (UID 1000-59999)"
    echo -e "  ├ 🗑️  Backup config + folder"
    echo -e "  ├ 🗑️  Cron auto-backup"
    echo -e "  └ 🗑️  Menu VPS ini"
    echo ""
    echo -e "  ${RED}⚠️  TINDAKAN INI TIDAK BISA DIBATALKAN!${NC}"
    echo ""
    echo -ne "  Ketik ${RED}YES${NC} untuk konfirmasi : "
    read confirm
    if [ "$confirm" != "YES" ]; then
        echo ""
        echo -e "  ${GREEN}✓ Dibatalkan — kembali ke menu${NC}"
        sleep 1.5
        return
    fi
    echo ""
    echo -e "  ${YELLOW}⏳ Memproses uninstall...${NC}"
    for s in vpnbot ws-ssh ws-ssh-alt stunnel4 udpgw xray zivpn; do
        systemctl stop "$s" 2>/dev/null
        systemctl disable "$s" 2>/dev/null
        rm -f "/etc/systemd/system/${s}.service"
    done
    systemctl daemon-reload 2>/dev/null
    systemctl reset-failed 2>/dev/null
    fuser -k 80/tcp 8080/tcp 443/tcp 8443/tcp 7300/udp 2>/dev/null
    pkill -f ws-ssh.py 2>/dev/null
    pkill -f badvpn-udpgw 2>/dev/null
    pkill -f vpnbot 2>/dev/null
    sleep 1
    rm -f /usr/local/bin/ws-ssh.py /usr/bin/badvpn-udpgw /usr/local/bin/badvpn-udpgw
    rm -f /etc/stunnel/stunnel.conf /etc/stunnel/stunnel.pem
    rm -f /root/bot.py /root/vpnbot.log /root/bot_compile.log
    rm -f /root/vpnbot_*.json /root/vpnbot_backup.sh /etc/sansxml-backup.conf
    rm -rf /root/vpnbot_backup
    rm -f /etc/ssh/sshd_config.d/99-vpnbot.conf
    rm -f /etc/issue /etc/issue.net /etc/motd
    for u in $(awk -F: '$3>=1000 && $3<60000 {print $1}' /etc/passwd); do
        pkill -9 -u "$u" 2>/dev/null
        userdel -r "$u" 2>/dev/null
    done
    crontab -r 2>/dev/null
    rm -f /usr/local/bin/sansxml-menu
    rm -f /etc/profile.d/sansxml-menu.sh
    clear
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║${NC}        ${GREEN}✅  SEMUA SC BERHASIL DIHAPUS${NC}                        ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}║${NC}        ${WHITE}VPS sudah bersih total${NC}                                 ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${YELLOW}Tekan ENTER untuk exit...${NC}"
    read
    exit 0
}

show_vps_detail(){
    clear
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║${NC}      ${CYAN}💻  DETAIL VPS — SANSXML VPN STORE${NC}                       ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    local os_name=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')
    local kernel=$(uname -r)
    local arch=$(uname -m)
    local hostname_v=$(hostname)
    echo -e "  ${YELLOW}🖥️   SISTEM${NC}"
    echo -e "  ├ OS         : ${GREEN}${os_name}${NC}"
    echo -e "  ├ Kernel     : ${WHITE}${kernel}${NC}"
    echo -e "  ├ Arch       : ${WHITE}${arch}${NC}"
    echo -e "  └ Hostname   : ${WHITE}${hostname_v}${NC}"
    echo ""
    local cpu=$(grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
    local cores=$(nproc)
    local load=$(cat /proc/loadavg | awk '{print $1", "$2", "$3}')
    echo -e "  ${YELLOW}⚙️   CPU${NC}"
    echo -e "  ├ Model      : ${WHITE}${cpu}${NC}"
    echo -e "  ├ Cores      : ${GREEN}${cores}${NC}"
    echo -e "  └ Load       : ${WHITE}${load}${NC}"
    echo ""
    local tk=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local ak=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    local uk=$((tk-ak))
    local tkg=$(awk "BEGIN{printf \"%.1f\", $tk/1024/1024}")
    local ukg=$(awk "BEGIN{printf \"%.1f\", $uk/1024/1024}")
    local pk=$(awk "BEGIN{printf \"%.0f\", $uk/$tk*100}")
    local fkg=$(awk "BEGIN{printf \"%.1f\", ($tk-$uk)/1024/1024}")
    echo -e "  ${YELLOW}💾 RAM${NC}"
    echo -e "  ├ Total      : ${WHITE}${tkg} GB${NC}"
    echo -e "  ├ Used       : ${WHITE}${ukg} GB (${pk}%)${NC}"
    echo -e "  └ Free       : ${WHITE}${fkg} GB${NC}"
    echo ""
    local dtotal=$(df -h / | tail -1 | awk '{print $2}')
    local dused=$(df -h / | tail -1 | awk '{print $3}')
    local dfree=$(df -h / | tail -1 | awk '{print $4}')
    local dpct=$(df -h / | tail -1 | awk '{print $5}')
    echo -e "  ${YELLOW}💿 DISK${NC}"
    echo -e "  ├ Total      : ${WHITE}${dtotal}${NC}"
    echo -e "  ├ Used       : ${WHITE}${dused} (${dpct})${NC}"
    echo -e "  └ Free       : ${WHITE}${dfree}${NC}"
    echo ""
    local ip=$(get_ip)
    local bw=$(get_bw)
    echo -e "  ${YELLOW}🌐 NETWORK${NC}"
    echo -e "  ├ IP Public  : ${GREEN}${ip}${NC}"
    echo -e "  ├ SSH Port   : ${WHITE}22${NC}"
    echo -e "  ├ WS-SSH     : ${WHITE}80, 8080${NC}"
    echo -e "  ├ SSL        : ${WHITE}443, 8443${NC}"
    echo -e "  ├ UDPGW      : ${WHITE}7300${NC}"
    echo -e "  └ Bandwidth  : ${WHITE}${bw}${NC}"
    echo ""
    echo -e "  ${YELLOW}🤖 BOT STATUS${NC}"
    local bs=$(systemctl is-active vpnbot 2>/dev/null || echo "off")
    local ws=$(systemctl is-active ws-ssh 2>/dev/null || echo "off")
    local wsa=$(systemctl is-active ws-ssh-alt 2>/dev/null || echo "off")
    local st=$(systemctl is-active stunnel4 2>/dev/null || echo "off")
    local ud=$(systemctl is-active udpgw 2>/dev/null || echo "off")
    [ "$bs" = "active" ] && echo -e "  ├ vpnbot     : ${GREEN}● RUNNING${NC}" || echo -e "  ├ vpnbot     : ${RED}○ STOPPED${NC}"
    [ "$ws" = "active" ] && echo -e "  ├ ws-ssh     : ${GREEN}● RUNNING${NC}" || echo -e "  ├ ws-ssh     : ${RED}○ STOPPED${NC}"
    [ "$wsa" = "active" ] && echo -e "  ├ ws-ssh-alt : ${GREEN}● RUNNING${NC}" || echo -e "  ├ ws-ssh-alt : ${RED}○ STOPPED${NC}"
    [ "$st" = "active" ] && echo -e "  ├ stunnel4   : ${GREEN}● RUNNING${NC}" || echo -e "  ├ stunnel4   : ${RED}○ STOPPED${NC}"
    [ "$ud" = "active" ] && echo -e "  └ udpgw      : ${GREEN}● RUNNING${NC}" || echo -e "  └ udpgw      : ${RED}○ STOPPED${NC}"
    echo ""
    echo -e "  ${YELLOW}📊 USER VPN AKTIF${NC}"
    local user_count=$(awk -F: '$3>=1000 && $3<60000' /etc/passwd | wc -l)
    echo -e "  └ Total user : ${GREEN}${user_count}${NC}"
    echo ""
    echo -e "${MAGENTA}──────────────────────────────────────────────────────────────${NC}"
    echo ""
    echo -ne "  ${YELLOW}Tekan ENTER untuk kembali ke menu...${NC}"
    read
}

while true; do
    show_menu
    read choice
    case "$choice" in
        1) do_uninstall ;;
        2) show_vps_detail ;;
        3) clear
           echo -e "${GREEN}✓ Terima kasih! Bot tetap jalan di background.${NC}"
           echo -e "${WHITE}  Ketik ${CYAN}sansxml-menu${NC}${WHITE} lagi untuk buka menu.${NC}"
           echo ""
           exit 0 ;;
        *) echo ""
           echo -e "  ${RED}❌ Pilihan tidak valid${NC}"
           sleep 1 ;;
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

# 9. SELESAI
clear
echo ""
echo -e "  ${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${GREEN}        ✓✓✓ INSTALASI SELESAI ✓✓✓${NC}"
echo -e "  ${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
for s in ssh ws-ssh ws-ssh-alt stunnel4 udpgw vpnbot; do
    ST=$(systemctl is-active "$s" 2>/dev/null || echo "n/a")
    printf "  %-14s : " "$s"
    [ "$ST" = "active" ] && echo -e "${GREEN}$ST${NC}" || echo -e "${RED}$ST${NC}"
done
echo ""
echo -e "  ${CYAN}Domain${NC} : ${GREEN}$DOMAIN${NC}"
echo -e "  ${CYAN}Bot${NC}    : Cek di Telegram (/start)"
echo -e "  ${CYAN}Log${NC}    : tail -f /root/vpnbot.log"
echo ""
echo -e "  ${GREEN}📌 Menu VPS   : ${NC}${WHITE}auto muncul saat login SSH${NC}"
echo -e "  ${GREEN}📌 Buka menu  : ${NC}${WHITE}ketik ${CYAN}sansxml-menu${NC}"
echo -e "  ${GREEN}📌 Backup     : ${NC}${WHITE}${GH_USER}/${GH_REPO}${NC}"
echo ""
echo -e "  ${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
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
echo -e "  ${CYAN}      SC AUTO INSTALL VPN SSH v5.0${NC}"
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
( apt-get install -y python3 python3-pip python3-venv sshpass curl wget unzip stunnel4 net-tools cron ufw iptables openssl cmake build-essential git pkg-config bc jq who procps dnsutils >/dev/null 2>&1 ) & spin $! "Install packages"
( pip3 install --break-system-packages --upgrade "python-telegram-bot>=20" requests qrcode pillow >/dev/null 2>&1 \
    || pip3 install --upgrade "python-telegram-bot>=20" requests qrcode pillow >/dev/null 2>&1 ) & spin $! "Install Telegram API"
( mkdir -p /root/.ssh; chmod 700 /root/.ssh
  [ ! -f /root/.ssh/id_bot ] && ssh-keygen -t ed25519 -f /root/.ssh/id_bot -N "" -q
  cat /root/.ssh/id_bot.pub >> /root/.ssh/authorized_keys
  sort -u /root/.ssh/authorized_keys -o /root/.ssh/authorized_keys
  chmod 600 /root/.ssh/authorized_keys ) & spin $! "Generate SSH key"

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
        c.settimeout(3)
        first = b""
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

# 4. SSH CONFIG + BANNER CUSTOM
rm -rf /etc/update-motd.d/* 2>/dev/null

cat > /etc/issue.net << 'BEOF'
<br><font color="#ff00aa"><b>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;▬▬▬▬▬▬ஜ۩۞۩ஜ▬▬▬▬▬▬</b></font><br><font color="#ffffff"><b>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;---&nbsp;卐&nbsp;</b></font><font color="#ffff00"><b>SANSXML&nbsp;VPN&nbsp;STORE</b></font><font color="#ffffff"><b>&nbsp;卐&nbsp;---</b></font><br><font color="#ff00aa"><b>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;▬▬▬▬▬▬ஜ۩۞۩ஜ▬▬▬▬▬▬</b></font><br><font color="#ffffff"><b>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;──&nbsp;PREMIUM&nbsp;VPN&nbsp;SERVER&nbsp;──</b></font><br><font color="#ffffff"><b>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;---&nbsp;卍&nbsp;TERM&nbsp;OF&nbsp;SERVICE&nbsp;卐&nbsp;---</b></font><br><font color="#ffffff"><b>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;NO&nbsp;MULTI&nbsp;LOGIN&nbsp;!!</b></font><br><font color="#ffffff"><b>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;NO&nbsp;HACKING&nbsp;AND&nbsp;CARDING</b></font><br><font color="#ffff00"><b>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;👉&nbsp;MULTI&nbsp;LOGIN&nbsp;BANNED&nbsp;👈</b></font><br><font color="#ff00aa"><b>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;▬▬▬▬▬▬ஜ۩۞۩ஜ▬▬▬▬▬▬</b></font><br><font color="#ffffff"><b>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;ORDER&nbsp;CONFIG&nbsp;PREMIUM:&nbsp;</b></font><font color="#00ff44"><b>wa.me/6289527419748</b></font><br><font color="#ffffff"><b>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;BOT&nbsp;ORDER&nbsp;VPN:&nbsp;</b></font><font color="#00ff44"><b>t.me/unokwn</b></font><br><br>
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

# 5. KONFIGURASI BOT + BACKUP GITHUB
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
    "sg_1ip": {"name": "🇸🇬 PRIME SG-01", "city": "Singapore", "isp": "DigitalOcean LLC", "ssh_ovpn": "DIGITALOCEAN • PRIME SG-01", "domain": "${DOMAIN}", "price_day": 117, "price_month": 3510, "ip_limit": 1, "slot_max": 50},
    "sg_2ip": {"name": "🇸🇬 PRIME SG-02", "city": "Singapore", "isp": "DigitalOcean LLC", "ssh_ovpn": "DIGITALOCEAN • PRIME SG-02", "domain": "${DOMAIN}", "price_day": 167, "price_month": 5010, "ip_limit": 2, "slot_max": 50}
  },
  "ip_limit": 2,
  "block_hours": 2
}
CFGEOF

# 6. INSTALL BOT.PY
echo ""
echo -e "  ${YELLOW}▸ Install Bot${NC}"
mkdir -p /root
(
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

def get_price(hari, server_key=None):
    if server_key and server_key in SERVERS: srv = SERVERS[server_key]
    else: srv = list(SERVERS.values())[0] if SERVERS else {"price_day": 117}
    return int(srv.get("price_day", 117)) * int(hari)

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
        f.write(f'GH_USER="{ghu}"\n')
        f.write(f'GH_REPO="{ghr}"\n')
        f.write(f'GH_TOKEN="{ght}"\n')
        f.write(f'GH_EMAIL="{ghe}"\n')
    try: os.chmod("/etc/sansxml-backup.conf", 0o600)
    except: pass

def is_backup_ready():
    conf = load_backup_conf()
    return all([conf.get("GH_USER"), conf.get("GH_REPO"), conf.get("GH_TOKEN"), conf.get("GH_EMAIL")])

def ssh_run(cmd, timeout=30):
    full = ["ssh","-i",SSH_KEY_PATH,"-o","StrictHostKeyChecking=no","-o","UserKnownHostsFile=/dev/null",
            "-o","ConnectTimeout=10","-o","PubkeyAuthentication=yes","-o","PasswordAuthentication=no",
            "-o","LogLevel=ERROR","-p","22","root@127.0.0.1",cmd]
    try:
        r = subprocess.run(full, capture_output=True, text=True, timeout=timeout)
        return r.returncode, r.stdout.strip(), r.stderr.strip()
    except subprocess.TimeoutExpired: return -1,"","Timeout"
    except Exception as e: return -2,"",str(e)

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
    accs = load_json(ACCOUNTS_FILE, {})
    today = datetime.now().date()
    created = 0; skipped = 0
    for un, a in accs.items():
        try: exp = datetime.strptime(a["exp"], "%Y-%m-%d").date()
        except: skipped += 1; continue
        if (exp - today).days < 0: skipped += 1; continue
        pw = a.get("password", "")
        if not pw: skipped += 1; continue
        pw_b64 = base64.b64encode(pw.encode()).decode()
        exp_str = a["exp"]
        cmd = (f"userdel -r {un} 2>/dev/null; useradd -m -s /bin/bash {un} 2>&1 ; "
               f"chage -E '{exp_str}' {un} 2>&1 ; chage -M 99999 {un} 2>&1 ; chage -I -1 {un} 2>&1 ; "
               f"PW=$(echo '{pw_b64}' | base64 -d) ; printf '%s:%s\\n' '{un}' \"$PW\" | chpasswd 2>&1 ; "
               f"passwd -u {un} 2>&1 ; usermod -U {un} 2>&1")
        ssh_run(cmd)
        created += 1
    logger.info(f"[RESTORE] {created} user dibuat, {skipped} skip")
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
            subprocess.run(["git", "init", "-q"], cwd=bdir, capture_output=True)
        subprocess.run(["git", "config", "user.email", ghe], cwd=bdir, capture_output=True)
        subprocess.run(["git", "config", "user.name", ghu], cwd=bdir, capture_output=True)
        subprocess.run(["git", "branch", "-M", "main"], cwd=bdir, capture_output=True)
        remote = f"https://{ghu}:{ght}@github.com/{ghu}/{ghr}.git"
        subprocess.run(["git", "remote", "remove", "origin"], cwd=bdir, capture_output=True)
        subprocess.run(["git", "remote", "add", "origin", remote], cwd=bdir, capture_output=True)
        for branch in ["main", "master"]:
            r = subprocess.run(["git", "pull", "origin", branch, "--allow-unrelated-histories", "--no-rebase", "-X", "ours"],
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
    except Exception as e:
        return False, str(e)

def wipe_local_data():
    deleted = {"json": 0, "users": 0, "folder": False}
    for f in ["vpnbot_users.json","vpnbot_balance.json","vpnbot_accounts.json",
              "vpnbot_trial.json","vpnbot_trx.json","vpnbot_blocked.json"]:
        p = f"/root/{f}"
        if os.path.exists(p):
            try: os.remove(p); deleted["json"] += 1
            except: pass
    try:
        r = subprocess.run("awk -F: '$3>=1000 && $3<60000 {print $1}' /etc/passwd",
            shell=True, capture_output=True, text=True, timeout=10)
        for un in r.stdout.split():
            try:
                subprocess.run(f"pkill -9 -u {un} 2>/dev/null", shell=True, timeout=5)
                subprocess.run(f"userdel -r {un} 2>/dev/null", shell=True, timeout=15)
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
    logger.info(f"[WIPE] JSON:{deleted['json']} User:{deleted['users']} Folder:{deleted['folder']}")
    return deleted

def reset_backup_env(wipe_github=True, wipe_local=True):
    result = {"github": False, "local": {}, "ts": time.strftime("%Y%m%d_%H%M%S")}
    try:
        conf = load_backup_conf()
        if wipe_github and conf.get("GH_USER") and conf.get("GH_REPO") and conf.get("GH_TOKEN"):
            bdir = "/root/vpnbot_backup"
            os.makedirs(bdir, exist_ok=True)
            if not os.path.exists(f"{bdir}/.git"):
                subprocess.run(["git", "init", "-q"], cwd=bdir, capture_output=True)
            subprocess.run(["git", "config", "user.email", conf.get("GH_EMAIL","bot@local")], cwd=bdir, capture_output=True)
            subprocess.run(["git", "config", "user.name", conf.get("GH_USER","bot")], cwd=bdir, capture_output=True)
            subprocess.run(["git", "branch", "-M", "main"], cwd=bdir, capture_output=True)
            remote = f"https://{conf['GH_USER']}:{conf['GH_TOKEN']}@github.com/{conf['GH_USER']}/{conf['GH_REPO']}.git"
            subprocess.run(["git", "remote", "remove", "origin"], cwd=bdir, capture_output=True)
            subprocess.run(["git", "remote", "add", "origin", remote], cwd=bdir, capture_output=True)
            for f in os.listdir(bdir):
                if f == ".git": continue
                fp = os.path.join(bdir, f)
                try:
                    if os.path.isfile(fp): os.remove(fp)
                    elif os.path.isdir(fp): shutil.rmtree(fp)
                except: pass
            with open(f"{bdir}/.wipe", "w") as f: f.write(f"RESET {result['ts']}\n")
            subprocess.run(["git", "add", "-A"], cwd=bdir, capture_output=True)
            subprocess.run(["git", "-c", f"user.email={conf.get('GH_EMAIL','bot@local')}",
                            "-c", f"user.name={conf.get('GH_USER','bot')}",
                            "commit", "--allow-empty", "-m", f"RESTORE TOTAL {result['ts']}"],
                cwd=bdir, capture_output=True)
            for branch in ["main", "master"]:
                r = subprocess.run(["git", "push", "origin", branch, "-f"],
                    cwd=bdir, capture_output=True, text=True, timeout=30)
                if r.returncode == 0: result["github"] = True; break
        if wipe_local:
            result["local"] = wipe_local_data()
        if os.path.exists("/etc/sansxml-backup.conf"):
            try: os.remove("/etc/sansxml-backup.conf")
            except: pass
        return True, result
    except Exception as e:
        return False, {"error": str(e)[:200]}

def ssh_create(username, password, days, is_trial=False):
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
    code, out, err = ssh_run(cmd)
    return {"ok":True,"username":username,"password":password,"exp":exp,"exp_ts":exp_ts,"manual":("DONE:0" not in out)}
def ssh_extend(username, new_exp):
    code, out, err = ssh_run(f"chage -E '{new_exp}' {username} 2>&1 ; echo DONE:$?")
    return "DONE:0" in out
def ssh_delete(username):
    ssh_run(f"pkill -9 -u {username} 2>/dev/null; userdel -r {username} 2>&1; echo OK", timeout=20)
    return True, "OK"
def ssh_test():
    code, out, err = ssh_run("echo PING_OK", timeout=15)
    return ("PING_OK" in out, "SSH OK" if "PING_OK" in out else f"SSH gagal: {err or out}")

def valid_username(s): return bool(re.match(r'^[a-zA-Z0-9_]{5,20}$', s or ""))
def valid_password(s):
    if not s or len(s)<5 or len(s)>32: return False
    return all(c in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*_.-" for c in s)

def get_active_sessions(username):
    try:
        r = subprocess.run(["who"], capture_output=True, text=True, timeout=5)
        return [l for l in r.stdout.splitlines() if l.split() and l.split()[0] == username]
    except: return []
def count_live_shells(username):
    try:
        r = subprocess.run(["ps", "-u", username, "-o", "comm="], capture_output=True, text=True, timeout=5)
        procs = [p.strip() for p in r.stdout.splitlines() if p.strip()]
        shells = ("bash", "sh", "zsh", "ksh", "dash", "csh", "tcsh")
        return sum(1 for p in procs if p.lstrip("-") in shells)
    except: return 0
def check_second_connection(username):
    sessions = get_active_sessions(username); n = len(sessions)
    if n <= 1: return False, sessions, n
    shells = count_live_shells(username)
    if shells > 1: return True, sessions, shells
    return False, sessions, shells if shells > 0 else n
def block_user(username, hours=2):
    try:
        subprocess.run(f"passwd -l {username}", shell=True, timeout=10)
        subprocess.run(f"pkill -9 -u {username}", shell=True, timeout=10)
        try:
            r = subprocess.run(f"ps -u {username} -o pid= 2>/dev/null", shell=True, capture_output=True, text=True, timeout=5)
            for pid in r.stdout.split(): subprocess.run(f"kill -9 {pid} 2>/dev/null", shell=True, timeout=3)
        except: pass
        d = load_json(BLOCK_FILE, {})
        d[username] = {"blocked_at": datetime.now().isoformat(),
                       "unblock_at": (datetime.now() + timedelta(hours=hours)).strftime("%Y-%m-%d %H:%M:%S")}
        save_json(BLOCK_FILE, d); return True
    except: return False
def unblock_user(username):
    try:
        subprocess.run(f"passwd -u {username}", shell=True, timeout=10)
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
    return count_slots(server_key), int(srv.get("slot_max", 50))
def trial_left(uid):
    d = load_json(TRIAL_FILE,{}); today = datetime.now().strftime("%Y-%m-%d")
    u = d.get(str(uid),{})
    if u.get("date") != today: return TRIAL_PER_DAY
    return max(0, TRIAL_PER_DAY - u.get("used",0))
def use_trial(uid):
    d = load_json(TRIAL_FILE,{}); today = datetime.now().strftime("%Y-%m-%d")
    u = d.get(str(uid),{})
    if u.get("date") != today: u = {"date":today,"used":0}
    u["used"] = u.get("used",0)+1
    d[str(uid)] = u; save_json(TRIAL_FILE,d)
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
    result = []; today = datetime.now().date(); accs = load_json(ACCOUNTS_FILE, {})
    for key, srv in SERVERS.items():
        used = 0
        for a in accs.values():
            if a.get("server_key") != key: continue
            try:
                ed = datetime.strptime(a["exp"], "%Y-%m-%d").date()
                if (ed - today).days >= 0: used += 1
            except: pass
        mx = int(srv.get("slot_max", 50))
        stat = "🟢 Online" if max(0, mx - used) > 0 else "🔴 Full"
        result.append({"name": srv.get("name","-"), "used": used, "max": mx, "status": stat})
    return result
def save_servers():
    cfg = load_config(); cfg["servers"] = SERVERS; save_config(cfg)

def backup_config_text():
    conf = load_backup_conf(); ght = conf.get("GH_TOKEN", "")
    tok_disp = (ght[:10] + "..." + ght[-4:]) if len(ght) > 20 else "(kosong)"
    status = "✅ Aktif" if is_backup_ready() else "❌ Belum diisi"
    return "\n".join(["<blockquote>", "🔄 <b>PENGATURAN BACKUP GITHUB</b>", "───────────────────────",
             f"├ Status   : <b>{status}</b>",
             f"├ Username : <code>{conf.get('GH_USER','-')}</code>",
             f"├ Repo     : <code>{conf.get('GH_REPO','-')}</code>",
             f"├ Email    : <code>{conf.get('GH_EMAIL','-')}</code>",
             f"╰ Token    : <code>{tok_disp}</code>",
             "───────────────────────",
             "<i>Backup otomatis tiap 5 menit ke repo private.</i>",
             "<i>Setiap perubahan data → auto push.</i>",
             "<i>⚠️ Ganti field → auto hapus & re-setup.</i>",
             "</blockquote>"])

def kb_backup():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("👤 Ganti Username", callback_data="backup_edit|user"),
         InlineKeyboardButton("📁 Ganti Repo", callback_data="backup_edit|repo")],
        [InlineKeyboardButton("🔑 Ganti Token", callback_data="backup_edit|token"),
         InlineKeyboardButton("📧 Ganti Email", callback_data="backup_edit|email")],
        [InlineKeyboardButton("🗑️ RESTORE TOTAL", callback_data="backup_reset")],
        [InlineKeyboardButton("🔙 Kembali", callback_data="admin|menu")]])

def kb_admin():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("💻 Kelola VPN", callback_data="admin|srv"),
         InlineKeyboardButton("👤 Daftar Pengguna", callback_data="admin|users|0")],
        [InlineKeyboardButton("📢 Broadcast", callback_data="admin|bc"),
         InlineKeyboardButton("🔄 Backup GitHub", callback_data="admin|backup")],
        [InlineKeyboardButton("🔙 Kembali", callback_data="menu|main")]])

def kb_acc_detail(un):
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("🗑️ Hapus", callback_data=f"del_acc|{un}")],
        [InlineKeyboardButton("🔙 Kembali", callback_data="my_accs")]])

def kb_dashboard(uid):
    rows = [
        [InlineKeyboardButton("➕ BUAT AKUN", callback_data="buat_akun"),
         InlineKeyboardButton("⌛ TRIAL AKUN", callback_data="trial_akun")],
        [InlineKeyboardButton("🔄 PERPANJANG AKUN", callback_data="perpanjang_akun")],
        [InlineKeyboardButton("💰 TOPUP SALDO", callback_data="isi_saldo"),
         InlineKeyboardButton("👤 AKUN SAYA", callback_data="my_accs")],
        [InlineKeyboardButton("♻️ REFRESH", callback_data="refresh")]]
    if is_owner(uid): rows.append([InlineKeyboardButton("💻 PENGATURAN", callback_data="admin|menu")])
    return InlineKeyboardMarkup(rows)

def kb_saldo():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("1", callback_data="saldo_num|1"), InlineKeyboardButton("2", callback_data="saldo_num|2"), InlineKeyboardButton("3", callback_data="saldo_num|3")],
        [InlineKeyboardButton("4", callback_data="saldo_num|4"), InlineKeyboardButton("5", callback_data="saldo_num|5"), InlineKeyboardButton("6", callback_data="saldo_num|6")],
        [InlineKeyboardButton("7", callback_data="saldo_num|7"), InlineKeyboardButton("8", callback_data="saldo_num|8"), InlineKeyboardButton("9", callback_data="saldo_num|9")],
        [InlineKeyboardButton("⬅️ Hapus", callback_data="saldo_hapus"), InlineKeyboardButton("0", callback_data="saldo_num|0"), InlineKeyboardButton("✅ Konfirmasi", callback_data="saldo_konfirmasi")],
        [InlineKeyboardButton("🔙 Kembali", callback_data="menu|main")]])

def kb_pilih_layanan():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("➕ SSH OVPN", callback_data="pilih|ssh")],
        [InlineKeyboardButton("➕ VMESS", callback_data="pilih|vmess"),
         InlineKeyboardButton("➕ VLESS", callback_data="pilih|vless")],
        [InlineKeyboardButton("➕ TROJAN", callback_data="pilih|trojan")],
        [InlineKeyboardButton("🔙 KEMBALI", callback_data="menu|main")]])

def kb_ssh_server():
    rows = []; keys = list(SERVERS.keys())
    for i in range(0, len(keys), 2):
        row = []
        for j in range(i, min(i+2, len(keys))):
            k = keys[j]
            row.append(InlineKeyboardButton(SERVERS[k]['name'], callback_data=f"buat|{k}"))
        rows.append(row)
    rows.append([InlineKeyboardButton("🔙 KEMBALI", callback_data="pilih_layanan")])
    return InlineKeyboardMarkup(rows)

def kb_ssh_server_locked():
    rows = []; keys = list(SERVERS.keys())
    for i in range(0, len(keys), 2):
        row = []
        for j in range(i, min(i+2, len(keys))):
            k = keys[j]
            row.append(InlineKeyboardButton(SERVERS[k]['name'], callback_data="ssh_locked"))
        rows.append(row)
    rows.append([InlineKeyboardButton("🔙 KEMBALI", callback_data="ssh_locked")])
    return InlineKeyboardMarkup(rows)

def kb_ssh_server_extend():
    rows = []; keys = list(SERVERS.keys())
    for i in range(0, len(keys), 2):
        row = []
        for j in range(i, min(i+2, len(keys))):
            k = keys[j]
            row.append(InlineKeyboardButton(SERVERS[k]['name'], callback_data=f"extend|{k}"))
        rows.append(row)
    rows.append([InlineKeyboardButton("🔙 KEMBALI", callback_data="menu|main")])
    return InlineKeyboardMarkup(rows)

def kb_coming_soon(p): return InlineKeyboardMarkup([[InlineKeyboardButton("🔙 KEMBALI", callback_data="pilih_layanan")]])

def dashboard_text(user, uid):
    uname = f"@{user.username}" if user.username else "-"
    role = "Owner" if is_owner(uid) else "Member"
    st = get_stats(uid); total_users = len(load_json(USERS_FILE, {}))
    lines = ["<blockquote>", "💻 <b>SANSXML VPN STORE</b>", "───────────────────────", "👤 <b>Profil</b>"]
    lines.append(f"├ User Telegram  : {uname}")
    lines.append(f"├ Chat ID        : <code>{uid}</code>")
    lines.append(f"├ Keanggotaan    : {role}")
    lines.append(f"├ Total Pengguna : <b>{total_users}</b>")
    lines.append(f"╰ 💰 Saldo VPN  : <b>{rupiah(get_bal(uid))}</b>")
    lines += ["", "🌍 <b>Info Global</b>"]
    lines.append(f"├ Minggu Ini     : <b>{st['minggu']} Akun</b>")
    lines.append(f"├ Bulan Ini      : <b>{st['bulan']} Akun</b>")
    lines.append(f"╰ Keseluruhan    : <b>{st['total']} Akun</b>")
    lines += ["", "🌐 <b>Informasi</b>"]
    lines.append(f"├ Server Tersedia : <b>{len(SERVERS)} Server</b>")
    lines.append(f"╰ Kuota Trial     : <b>{trial_left(uid)}x Hari</b>")
    lines += ["", "───────────────────────", "</blockquote>"]
    return "\n".join(lines)

def pilih_layanan_text():
    return "<blockquote>\n💻 <b>PILIH LAYANAN VPN</b>\n───────────────────────\nSilakan pilih protokol yang ingin dibuat:\n───────────────────────\n</blockquote>"

def ssh_server_text():
    lines = ["<blockquote>", "<b>💻 SSH OVPN</b>", "─────────────────────────", ""]
    for key, srv in SERVERS.items():
        used, mx = get_slot_info(key)
        cek = "✅" if max(0, mx-used) > 0 else "❌"
        lines.append(f"◆ {srv['name']}")
        lines.append(f"├ Harga Harian   : <b>{rupiah(srv['price_day'])}</b>")
        lines.append(f"├ Harga Bulanan  : <b>{rupiah(srv['price_month'])}</b>")
        lines.append("├ Kuota          : Unlimited")
        lines.append(f"├ Limit IP       : {srv['ip_limit']} IP")
        lines.append(f"╰ Slot Tersedia  : <b>{used}/{mx} {cek}</b>")
        lines.append(""); lines.append("")
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
    ssh_ovpn_val = srv.get("ssh_ovpn") or srv.get("name","SG NEWMEDIA").replace("🇸🇬 ","").strip()
    srv_host = srv.get("domain") or SSH_HOST
    payload_ws = "GET /cdn-cgi/trace HTTP/1.1[crlf]Host: [host][crlf][crlf]GET-RAY / HTTP/1.1[crlf]Host: [host][crlf]Connection: Upgrade[crlf]User-Agent: [ua][crlf]Upgrade: websocket[crlf][crlf]"
    payload_tls = "GET / HTTP/1.1[crlf]Host: [host][crlf]User-Agent: [ua][crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]"
    lines = ["<blockquote>"]
    lines += ["◤ <b>SSH OVPN ACCOUNT</b> ◢", f"     ❖ <b>{head}</b> ❖", "━━━━━━━━━━━━━━━━━━━━━━━", "", ""]
    lines += [f"City       : {srv.get('city','Singapore')}", f"ISP        : {srv.get('isp','DigitalOcean LLC')}",
              f"SSH OVPN   : {ssh_ovpn_val}", f"Username   : {u}", f"Password   : {p}",
              "Quota      : Unlimited", f"Limit IP   : {ip} IP", "", ""]
    lines += ["━━━━━━━━━━━━━━━━━━━━━━━", "", ""]
    lines += [f"Host     : {srv_host}", "OpenSSH  : 443, 80, 22", "Dropbear : 443, 109",
              "SSH WS   : 80, 8080, 8081-9999", "SSH SSL  : 443", "SSH UDP  : 1-65535",
              "OVPN     : 443, 1194, 2200", "BadVPN   : 7100, 7300", "━━━━━━━━━━━━━━━━━━━━━━━"]
    lines += [f"SSL : {srv_host}:443@{u}:{p}", "", f"WS  : {srv_host}:80@{u}:{p}", "", f"UDP : {srv_host}:1-65535@{u}:{p}",
              "━━━━━━━━━━━━━━━━━━━━━━━", "", "PAYLOAD WS", payload_ws, "", "PAYLOAD TLS", payload_tls,
              "━━━━━━━━━━━━━━━━━━━━━━━", "", f"Durasi   : {dl}", f"Dibuat   : {created_fmt}", f"Berakhir : {exp_fmt}", "",
              "━━━━━━━━━━━━━━━━━━━━━━━", "<b>      ◤ SANSXML VPN STORE ◢</b>",
              "<i>❖ Terima kasih ❖</i>", "</blockquote>"]
    return "\n".join(lines)

async def do_create_account(chat, uid, user, username, password, hari, is_trial=False, server_key="sg_1ip"):
    srv = SERVERS.get(server_key, {}); ip_limit = int(srv.get("ip_limit", 2))
    price = 0 if is_trial else get_price(hari, server_key)
    if not is_trial and get_bal(uid) < price:
        kb = InlineKeyboardMarkup([[InlineKeyboardButton("💰 TOPUP SALDO", callback_data="isi_saldo")],
            [InlineKeyboardButton("🔙 Kembali", callback_data="menu|main")]])
        await chat.send_message(f"<blockquote>❌ <b>Saldo Tidak Cukup</b>\n\n💰 Saldo: <b>{rupiah(get_bal(uid))}</b>\n💵 Harga: <b>{rupiah(price)}</b>\n📉 Kurang: <b>{rupiah(price - get_bal(uid))}</b></blockquote>",
            reply_markup=kb, parse_mode="HTML")
        return
    msg = await chat.send_message(f"⚙️ Membuat <b>{'TRIAL' if is_trial else 'PREMIUM'} AKUN</b>...", parse_mode="HTML")
    r = await asyncio.to_thread(ssh_create, username, password, hari, is_trial)
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
        kb = InlineKeyboardMarkup([[InlineKeyboardButton("💰 TOPUP SALDO", callback_data="isi_saldo")],[InlineKeyboardButton("🔙 Kembali", callback_data="menu|main")]])
        await chat.send_message(f"<blockquote>❌ <b>Saldo Tidak Cukup</b></blockquote>", reply_markup=kb, parse_mode="HTML")
        return
    msg = await chat.send_message(f"⚙️ Memperpanjang <b>{username}</b> {hari} hari...", parse_mode="HTML")
    a = get_acc(username)
    try: old_exp = datetime.strptime(a["exp"], "%Y-%m-%d").date()
    except: old_exp = datetime.now().date()
    base = old_exp if old_exp > datetime.now().date() else datetime.now().date()
    new_exp_str = (base + timedelta(days=hari)).strftime("%Y-%m-%d")
    ok = await asyncio.to_thread(ssh_extend, username, new_exp_str)
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
    try: await asyncio.to_thread(ssh_delete, uname)
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
                    if a.get("is_trial"):
                        await asyncio.to_thread(ssh_delete, un)
                        a["os_deleted"] = True; a["deleted_at"] = now.isoformat(); save_acc(un, a)
                    else:
                        await asyncio.to_thread(ssh_delete, un); delete_acc_json(un)
                    dele += 1
            if dele > 0: logger.info(f"[AUTO-CLEANUP] {dele} expired")
            accs = load_json(ACCOUNTS_FILE, {}); blk = load_json(BLOCK_FILE, {})
            for un, a in accs.items():
                if a.get("is_trial"): continue
                if a.get("free_owner"): continue
                if un in blk: continue
                violation, sessions, cnt = await asyncio.to_thread(check_second_connection, un)
                if violation:
                    try:
                        await asyncio.to_thread(block_user, un, BLOCK_HOURS)
                        logger.info(f"[BLOCK] {un} - {cnt} session")
                    except Exception as e: logger.error(f"[BLOCK-ERR] {un}: {e}")
            blk = load_json(BLOCK_FILE, {}); changed = False
            for un, info in list(blk.items()):
                try:
                    if now >= datetime.strptime(info["unblock_at"], "%Y-%m-%d %H:%M:%S"):
                        await asyncio.to_thread(unblock_user, un); changed = True
                except: pass
            if changed: logger.info("[UNBLOCK] akun dibuka")
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
    if d == "noop": return
    if d == "ssh_locked": return

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
            reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Kembali", callback_data="menu|main")]]), parse_mode="HTML")
        except: pass
        asyncio.create_task(sync_push_async())
        return

    if d == "buat_akun":
        if not is_backup_ready():
            await q.answer("⚠️ Backup belum di-setup. Hubungi admin.", show_alert=True)
            await chat.send_message("<blockquote>⚠️ <b>BACKUP BELUM DI-SETUP</b>\n\nSilakan hubungi admin.</blockquote>", parse_mode="HTML")
            return
        c.user_data.clear(); c.user_data["mode"] = "buat"
        try: await q.edit_message_text(pilih_layanan_text(), reply_markup=kb_pilih_layanan(), parse_mode="HTML")
        except: pass
        return
    if d == "trial_akun":
        if not is_backup_ready():
            await q.answer("⚠️ Backup belum di-setup.", show_alert=True); return
        c.user_data.clear(); c.user_data["mode"] = "trial"
        try: await q.edit_message_text(pilih_layanan_text(), reply_markup=kb_pilih_layanan(), parse_mode="HTML")
        except: pass
        return
    if d == "perpanjang_akun":
        if not is_backup_ready():
            await q.answer("⚠️ Backup belum di-setup.", show_alert=True); return
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
        prompts = {
            "user": "Kirim <b>username GitHub</b>:\nContoh: <code>accbotvsbot-blip</code>\n\n⚠️ <i>Ganti = auto hapus folder & re-setup.</i>",
            "repo": "Kirim <b>nama repo private</b>:\nContoh: <code>VPN-backup-</code>\n\n⚠️ <i>Ganti = auto hapus folder & re-setup.</i>",
            "token": "Kirim <b>GitHub token</b> (ghp_xxx / github_pat_xxx):\n\n⚠️ <i>Auto-delete setelah diterima.</i>",
            "email": "Kirim <b>email GitHub</b>:\nContoh: <code>user@gmail.com</code>"
        }
        try: await q.edit_message_text(f"✏️ <b>GANTI {field.upper()}</b>\n\n{prompts.get(field,'')}",
            reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("❌ Batal", callback_data="admin|backup")]]), parse_mode="HTML")
        except: pass
        return
    if d == "backup_reset":
        if not is_owner(uid): return
        try:
            await q.edit_message_text(
                "⚠️ <b>RESTORE TOTAL</b>\n\n<blockquote>"
                "🔴 SEMUA data akan DIHAPUS PERMANEN:\n"
                "├ 📄 File JSON (users, saldo, akun, trial, trx, blocked)\n"
                "├ 👤 Semua user OS (UID 1000-59999)\n"
                "├ 📁 Folder /root/vpnbot_backup\n"
                "├ 🔧 Config /etc/sansxml-backup.conf\n"
                "├ ⏰ Cron auto-backup\n"
                "╰ ☁️ Isi repo GitHub (force-clear)\n\n"
                "⚠️ <i>Tindakan ini TIDAK BISA dibatalkan!</i>"
                "</blockquote>\n\nYakin ingin restore total?",
                reply_markup=InlineKeyboardMarkup([
                    [InlineKeyboardButton("🗑️ YA, HAPUS SEMUA", callback_data="backup_reset_yes")],
                    [InlineKeyboardButton("❌ Batal", callback_data="admin|backup")]]),
                parse_mode="HTML")
        except: pass
        return
    if d == "backup_reset_yes":
        if not is_owner(uid): return
        try: await q.edit_message_text("🗑️ <b>Wipe total sedang berjalan...</b>\n\n<i>Mohon tunggu...</i>", parse_mode="HTML")
        except: pass
        ok, info = await asyncio.to_thread(reset_backup_env, True, True)
        if ok:
            loc = info.get("local", {})
            m = ("✅ <b>RESTORE TOTAL SELESAI</b>\n\n<blockquote>"
                 "🗑️ <b>Lokal VPS:</b>\n"
                 f"├ JSON dihapus : <b>{loc.get('json',0)} file</b>\n"
                 f"├ User OS hapus : <b>{loc.get('users',0)} user</b>\n"
                 f"╰ Folder backup : <b>{'dihapus' if loc.get('folder') else '-'}</b>\n\n"
                 f"☁️ <b>GitHub:</b> <b>{'dibersihkan' if info.get('github') else 'skip'}</b>\n\n"
                 f"⏰ {info.get('ts','')}\n"
                 "</blockquote>\n\n"
                 "<i>Isi ulang 4 field untuk setup fresh.</i>\n"
                 "<i>Bot akan restart otomatis 5 detik.</i>")
            try: await q.edit_message_text(m, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Kembali", callback_data="admin|menu")]]), parse_mode="HTML")
            except: pass
            logger.info("[RESTORE-TOTAL] Wipe selesai, restart bot...")
            await asyncio.sleep(5)
            subprocess.Popen(["systemctl", "restart", "vpnbot"])
        else:
            m = f"❌ <b>Gagal</b>\n<code>{info.get('error','unknown')[:200]}</code>"
            try: await q.edit_message_text(m, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Kembali", callback_data="admin|backup")]]), parse_mode="HTML")
            except: pass
        return

    if d.startswith("extend|"):
        if c.user_data.get("created_in_session"): return
        server_key = d.split("|")[1]
        if server_key not in SERVERS:
            await chat.send_message("❌ Server tidak valid.", parse_mode="HTML"); return
        try: await q.edit_message_reply_markup(reply_markup=kb_ssh_server_locked())
        except: pass
        c.user_data["extend_step"] = "username"; c.user_data["extend_data"] = {"server_key": server_key}
        await chat.send_message("👤 <b>Masukkan username akun :</b>", parse_mode="HTML")
        return

    if d.startswith("buat|"):
        if c.user_data.get("created_in_session"): return
        server_key = d.split("|")[1]
        if server_key not in SERVERS:
            await chat.send_message("❌ Server tidak valid.", parse_mode="HTML"); return
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
            rows = [[InlineKeyboardButton("➕ BUAT AKUN", callback_data="buat_akun")],
                    [InlineKeyboardButton("🔙 KEMBALI", callback_data="menu|main")]]
        else:
            rows = []
            for a in accs[:20]:
                un = a.get("username",""); b = get_block_info(un)
                label = f"🚫 {un} (DIBLOKIR)" if b else f"👤 {un}"
                rows.append([InlineKeyboardButton(label, callback_data=f"acc_detail|{un}")])
            rows.append([InlineKeyboardButton("🔙 KEMBALI", callback_data="menu|main")])
        try: await q.edit_message_text("\n".join(hdr), reply_markup=InlineKeyboardMarkup(rows), parse_mode="HTML")
        except: pass
        return

    if d.startswith("acc_detail|"):
        un = d.split("|",1)[1]; a = get_acc(un)
        if not a or a.get("user_id") != uid: await q.answer("No", show_alert=True); return
        dl_txt = f"{TRIAL_DURATION_MIN} Minute" if a.get("is_trial") else f"{a.get('days',30)} Hari"
        ref = 0 if (a.get("is_trial") or int(a.get("harga",0)) <= 0) else hitung_refund(a)
        cap = acc_caption(un, a['password'], a['exp'], dl_txt, a.get('limit_ip',IP_LIMIT), a.get('manual',False), a.get('is_trial',False), a.get('server_key','sg_1ip'))
        try:
            ed = datetime.strptime(a["exp"], "%Y-%m-%d").date(); sh = max(0,(ed-datetime.now().date()).days); th = int(a.get("days",30))
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

    if d == "admin|menu":
        if not is_owner(uid): return
        inc = get_income(); us = count_users_by_period()
        svr_stat = get_server_status()
        svr_txt = "\n".join([f"├ {s['name']}\n│ ├ Slot   : <b>{s['used']}/{s['max']}</b>\n│ ╰ Status : <b>{s['status']}</b>" for s in svr_stat])
        txt = ("<blockquote><b>PENGATURAN VPS BOT VPN</b>\n───────────────────────\n"
            f"👥 Total User : <b>{us['total']}</b>\n   Total Akun : <b>{count_accounts()}</b>\n\n"
            "📈 <b>PENGHASILAN</b>\n"
            f"├ Hari Ini   : <b>{rupiah(inc['hari'])}</b>\n"
            f"├ Minggu Ini : <b>{rupiah(inc['minggu'])}</b>\n"
            f"├ Bulan Ini  : <b>{rupiah(inc['bulan'])}</b>\n"
            f"└ Total      : <b>{rupiah(inc['total'])}</b>\n\n"
            "👤 <b>JUMLAH USER</b>\n"
            f"├ Hari Ini   : <b>{us['hari']}</b>\n"
            f"├ Minggu Ini : <b>{us['minggu']}</b>\n"
            f"├ Bulan Ini  : <b>{us['bulan']}</b>\n"
            f"└ Total      : <b>{us['total']}</b>\n\n"
            "📡 <b>STATUS VPS SG</b>\n"
            f"{svr_txt}\n───────────────────────\n</blockquote>")
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
        total = len(keys); per = 10
        tp = max(1, (total + per - 1) // per)
        page = max(0, min(page, tp - 1))
        chunk = keys[page*per:(page+1)*per]
        lines = ["<blockquote>", "👤 <b>DAFTAR PENGGUNA</b>", "──────────────────────", f"👥 Total: <b>{total}</b>", ""]
        for i, k in enumerate(chunk, start=page*per+1):
            lines.append(f"{i}. 👤 {users[k].get('first_name') or '-'}")
        lines += ["", "──────────────────────", f"Hal {page+1}/{tp}", "──────────────────────", "</blockquote>"]
        rows = []
        for k in chunk:
            n = users.get(k, {}).get("first_name") or "-"
            rows.append([InlineKeyboardButton(f"👤 {n}", callback_data=f"admin|user|{k}|{page}")])
        nav = []
        if page > 0: nav.append(InlineKeyboardButton("◀ Prev", callback_data=f"admin|users|{page-1}"))
        nav.append(InlineKeyboardButton(f"{page+1}/{tp}", callback_data="noop"))
        if page < tp - 1: nav.append(InlineKeyboardButton("Next ▶", callback_data=f"admin|users|{page+1}"))
        if nav: rows.append(nav)
        rows.append([InlineKeyboardButton("🔄 Refresh", callback_data=f"admin|users|{page}"),
                     InlineKeyboardButton("🔙 Kembali", callback_data="admin|menu")])
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
        ls = (uu.get("last_seen") or "-")[:10]
        saldo = get_bal(target_uid)
        top = get_user_topup_stats(target_uid)
        txt = (f"<blockquote>👤 <b>{name}</b>\n"
               f"├ Username : @{uname if uname != '-' else '-'}\n"
               f"├ Chat ID : <code>{target_uid}</code>\n"
               f"├ Bergabung : {ls}\n"
               f"╰ Saldo : <b>{rupiah(saldo)}</b>\n\n"
               f"💰 <b>Riwayat Topup</b>\n"
               f"├ Hari Ini : {rupiah(top['hari'])}\n"
               f"├ Minggu : {rupiah(top['minggu'])}\n"
               f"╰ Total : {rupiah(top['total'])}</blockquote>")
        kb = InlineKeyboardMarkup([[InlineKeyboardButton("🔄 Refresh", callback_data=f"admin|user|{target_uid}|{page}")],
                                    [InlineKeyboardButton("🔙 Kembali", callback_data=f"admin|users|{page}")]])
        try: await q.edit_message_text(txt, reply_markup=kb, parse_mode="HTML")
        except: pass
        return

    if d == "admin|srv":
        if not is_owner(uid): return
        lines = ["<blockquote>", "💻 <b>KELOLA SERVER</b>", "───────────────────────", ""]
        for key, srv in SERVERS.items():
            lines.append(f"<b>{srv.get('name','-')}</b>")
            lines.append(f"├ Harga Harian  : <b>{rupiah(srv.get('price_day',0))}</b>")
            lines.append(f"├ Harga Bulanan : <b>{rupiah(srv.get('price_month',0))}</b>")
            lines.append(f"├ Limit IP      : <b>{srv.get('ip_limit',1)} IP</b>")
            lines.append(f"╰ Slot Server  : <b>{srv.get('slot_max',50)}</b>")
            lines.append("")
        lines.append("───────────────────────"); lines.append("</blockquote>")
        rows = []; keys = list(SERVERS.keys())
        for i in range(0, len(keys), 2):
            row = []
            for j in range(i, min(i+2, len(keys))):
                k = keys[j]
                row.append(InlineKeyboardButton(SERVERS[k].get('name','-'), callback_data=f"srv_edit|{k}"))
            rows.append(row)
        rows.append([InlineKeyboardButton("🔙 Kembali", callback_data="admin|menu")])
        try: await q.edit_message_text("\n".join(lines), reply_markup=InlineKeyboardMarkup(rows), parse_mode="HTML")
        except: pass
        return

    if d.startswith("srv_edit|"):
        if not is_owner(uid): return
        key = d.split("|")[1]
        if key not in SERVERS: await q.answer("Server tidak ditemukan", show_alert=True); return
        srv = SERVERS[key]
        txt = (f"<blockquote><b>{srv.get('name','-')}</b>\n───────────────────────\n"
            f"├ Harga Harian  : <b>{rupiah(srv.get('price_day',0))}</b>\n"
            f"├ Harga Bulanan : <b>{rupiah(srv.get('price_month',0))}</b>\n"
            f"├ Limit IP      : <b>{srv.get('ip_limit',1)} IP</b>\n"
            f"├ Slot Server  : <b>{srv.get('slot_max',50)}</b>\n"
            f"╰ Domain       : <b>{srv.get('domain','-')}</b>\n</blockquote>")
        kb = InlineKeyboardMarkup([
            [InlineKeyboardButton("Nama Server", callback_data=f"srv_set|{key}|name"),
             InlineKeyboardButton("Harga Bulanan", callback_data=f"srv_set|{key}|price_month")],
            [InlineKeyboardButton("Limit IP", callback_data=f"srv_set|{key}|ip_limit"),
             InlineKeyboardButton("Slot Server", callback_data=f"srv_set|{key}|slot_max")],
            [InlineKeyboardButton("Domain Server", callback_data=f"srv_set|{key}|domain")],
            [InlineKeyboardButton("🔙 Kembali", callback_data="admin|srv")]])
        try: await q.edit_message_text(txt, reply_markup=kb, parse_mode="HTML")
        except: pass
        return

    if d.startswith("srv_set|"):
        if not is_owner(uid): return
        parts = d.split("|")
        if len(parts) < 3: return
        key = parts[1]; field = parts[2]
        if key not in SERVERS: await q.answer("Server tidak ditemukan", show_alert=True); return
        c.user_data["srv_edit"] = {"key": key, "field": field}
        prompts = {"name": "Kirim nama baru. Contoh: <code>🇸🇬 PRIME SG-01</code>",
            "price_month": "Kirim harga BULANAN baru. Contoh: <code>3510</code>",
            "ip_limit": "Kirim limit IP baru. Contoh: <code>2</code>",
            "slot_max": "Kirim jumlah slot baru. Contoh: <code>50</code>",
            "domain": "Kirim DOMAIN baru. Contoh: <code>sgivip.naaofficial.web.id</code>"}
        try: await q.edit_message_text(prompts.get(field, "Kirim nilai baru:"), reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("❌ Batal", callback_data=f"srv_edit|{key}")]]), parse_mode="HTML")
        except: pass
        return

    if d == "admin|bc":
        if not is_owner(uid): return
        c.user_data["bc_wait"] = True
        try: await q.edit_message_text("📢 <b>BROADCAST</b>\n\nKetik pesan:",
            reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("❌ Batal", callback_data="admin|menu")]]), parse_mode="HTML")
        except: pass
        return
    if d == "bc_send":
        if not is_owner(uid): return
        msg_text = c.user_data.get("bc_text", "")
        if not msg_text: await q.answer("Pesan kosong!", show_alert=True); return
        try: await q.edit_message_text("📤 Mengirim...", parse_mode="HTML")
        except: pass
        users = load_json(USERS_FILE, {})
        ok_c = 0; fail_c = 0
        for tuid in users.keys():
            try:
                await c.bot.send_message(chat_id=int(tuid), text=msg_text, parse_mode="HTML")
                ok_c += 1
            except Exception: fail_c += 1
            await asyncio.sleep(0.05)
        c.user_data["bc_text"] = ""; c.user_data["bc_wait"] = False
        try: await q.edit_message_text(f"✅ <b>Selesai</b>\n\n├ Sukses: <b>{ok_c}</b>\n╰ Gagal: <b>{fail_c}</b>",
            reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Kembali", callback_data="admin|menu")]]), parse_mode="HTML")
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
        old_conf = load_backup_conf()
        conf = dict(old_conf)
        err = None
        if backup_field == "user":
            if not re.match(r'^[a-zA-Z0-9-]+$', t): err = "Username tidak valid"
            else: conf["GH_USER"] = t
        elif backup_field == "repo":
            if not re.match(r'^[a-zA-Z0-9._-]+$', t): err = "Nama repo tidak valid"
            else: conf["GH_REPO"] = t
        elif backup_field == "token":
            if not (t.startswith("ghp_") or t.startswith("github_pat_")) or len(t) < 20:
                err = "Format token harus ghp_xxx atau github_pat_xxx"
            else: conf["GH_TOKEN"] = t
        elif backup_field == "email":
            if "@" not in t or "." not in t: err = "Email tidak valid"
            else: conf["GH_EMAIL"] = t
        if err:
            await u.message.reply_text(f"❌ {err}\n\nCoba kirim ulang:", parse_mode="HTML")
            c.user_data["backup_field"] = backup_field
            return

        changed = (old_conf.get(f"GH_{backup_field.upper()}") != conf.get(f"GH_{backup_field.upper()}"))
        save_backup_conf(conf["GH_USER"], conf["GH_REPO"], conf["GH_TOKEN"], conf["GH_EMAIL"])

        all_ok = all([conf["GH_USER"], conf["GH_REPO"], conf["GH_TOKEN"], conf["GH_EMAIL"]])
        if all_ok:
            notify_txt = "⏳ <b>Pull dari GitHub & restore...</b>"
            if changed:
                notify_txt = "⏳ <b>Field berubah!</b>\n\n🗑️ Hapus folder backup lama...\n📥 Pull fresh dari GitHub..."
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
                tag = "🔄 <b>Re-setup (field berubah)</b>" if changed else "✅ <b>Disimpan!</b>"
                await u.message.reply_text(
                    f"{tag}\n\n<blockquote>"
                    f"✅ Auto backup aktif (5 menit)\n"
                    f"✅ File JSON direstore : <b>{info}</b>\n"
                    f"✅ User OS dibuat ulang : <b>{ccount}</b>\n"
                    f"╰ Skip : <b>{scount}</b>\n"
                    f"</blockquote>\n\n" + backup_config_text(),
                    reply_markup=kb_backup(), parse_mode="HTML")
            else:
                try: await notify.delete()
                except: pass
                await u.message.reply_text(f"❌ <b>Gagal</b>\n<code>{str(info)[:200]}</code>", reply_markup=kb_backup(), parse_mode="HTML")
        else:
            await u.message.reply_text(f"✅ <b>Disimpan!</b>\n\n<i>Lengkapi sisa field untuk aktivasi.</i>\n\n" + backup_config_text(), reply_markup=kb_backup(), parse_mode="HTML")
        return

    srv_edit = c.user_data.get("srv_edit")
    if srv_edit and is_owner(uid):
        key = srv_edit.get("key"); field = srv_edit.get("field")
        val = t.strip()
        if key not in SERVERS:
            c.user_data["srv_edit"] = None
            await u.message.reply_text("❌ Server tidak ditemukan.", parse_mode="HTML"); return
        srv = SERVERS[key]
        try:
            if field == "name":
                if len(val) < 3: await u.message.reply_text("❌ Nama minimal 3 karakter.", parse_mode="HTML"); return
                srv["name"] = val; msg_out = f"Nama → <b>{val}</b>"
            elif field == "price_month":
                angka = int(re.sub(r'[^0-9]','',val))
                if angka <= 0: await u.message.reply_text("❌ Angka tidak valid.", parse_mode="HTML"); return
                srv["price_month"] = angka; srv["price_day"] = max(1, int(round(angka / 30)))
                msg_out = f"Bulanan → <b>{rupiah(angka)}</b>"
            elif field == "ip_limit":
                angka = int(re.sub(r'[^0-9]','',val))
                if angka <= 0: await u.message.reply_text("❌ Angka tidak valid.", parse_mode="HTML"); return
                srv["ip_limit"] = angka; msg_out = f"Limit IP → <b>{angka}</b>"
            elif field == "slot_max":
                angka = int(re.sub(r'[^0-9]','',val))
                if angka <= 0: await u.message.reply_text("❌ Angka tidak valid.", parse_mode="HTML"); return
                srv["slot_max"] = angka; msg_out = f"Slot → <b>{angka}</b>"
            elif field == "domain":
                srv["domain"] = val; msg_out = f"Domain → <b>{val}</b>"
            else:
                c.user_data["srv_edit"] = None
                await u.message.reply_text("❌ Field tidak valid.", parse_mode="HTML"); return
            save_servers(); c.user_data["srv_edit"] = None
            await u.message.reply_text(f"✅ {msg_out}", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Kembali", callback_data="admin|srv")]]), parse_mode="HTML")
            return
        except Exception as e:
            await u.message.reply_text(f"❌ Error: {e}", parse_mode="HTML"); return

    if c.user_data.get("bc_wait") and is_owner(uid):
        c.user_data["bc_wait"] = False; c.user_data["bc_text"] = t
        await u.message.reply_text(f"📢 <b>PREVIEW</b>\n\n<blockquote>{t}</blockquote>\n\nKirim ke semua?",
            reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("✅ Kirim", callback_data="bc_send")],[InlineKeyboardButton("❌ Batal", callback_data="admin|menu")]]),
            parse_mode="HTML")
        return

    # ═══════════════════════════════════════════════
    # BUAT AKUN — Prompt "1-30", tapi HARI_MAX=365
    # ═══════════════════════════════════════════════
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
            # Validasi: HANYA ANGKA
            if not t.isdigit():
                await u.message.reply_text("🚫 <b>Harus angka! Contoh: 30</b>\n<i>Tidak boleh huruf/simbol.</i>", parse_mode="HTML")
                await u.message.reply_text("📆 Masukkan masa aktif 1-30 (hari) :", parse_mode="HTML"); return
            hari = int(t)
            if not (HARI_MIN <= hari <= HARI_MAX):
                await u.message.reply_text(f"🚫 <b>Masa aktif harus {HARI_MIN}-{HARI_MAX} hari.</b>", parse_mode="HTML")
                await u.message.reply_text("📆 Masukkan masa aktif 1-30 (hari) :", parse_mode="HTML"); return
            un = data.get("username"); pw = data.get("password")
            server_key = data.get("server_key", "sg_1ip")
            price = get_price(hari, server_key)
            c.user_data["buat_step"] = None; c.user_data["buat_data"] = {}
            if not is_backup_ready():
                await u.message.reply_text("<blockquote>⚠️ <b>BACKUP BELUM SIAP</b>\n\nHubungi admin.</blockquote>", parse_mode="HTML"); return
            if get_bal(uid) < price:
                kb = InlineKeyboardMarkup([[InlineKeyboardButton("💰 TOPUP SALDO", callback_data="isi_saldo")],[InlineKeyboardButton("🔙 Kembali", callback_data="menu|main")]])
                await u.message.reply_text(f"<blockquote>❌ <b>Saldo Tidak Cukup</b>\n\n💰 Saldo: <b>{rupiah(get_bal(uid))}</b>\n💵 Harga: <b>{rupiah(price)}</b>\n📉 Kurang: <b>{rupiah(price - get_bal(uid))}</b></blockquote>",
                    reply_markup=kb, parse_mode="HTML"); return
            c.user_data["created_in_session"] = True
            await do_create_account(u.effective_chat, uid, u.effective_user, un, pw, hari, server_key=server_key)
            return

    # ═══════════════════════════════════════════════
    # PERPANJANG — Prompt "1-30", tapi HARI_MAX=365
    # ═══════════════════════════════════════════════
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
            # Validasi: HANYA ANGKA
            if not t.isdigit():
                await u.message.reply_text("🚫 <b>Harus angka! Contoh: 30</b>\n<i>Tidak boleh huruf/simbol.</i>", parse_mode="HTML")
                await u.message.reply_text("📆 Masukkan masa aktif 1-30 (hari) :", parse_mode="HTML"); return
            hari = int(t)
            if not (HARI_MIN <= hari <= HARI_MAX):
                await u.message.reply_text(f"🚫 <b>Masa aktif harus {HARI_MIN}-{HARI_MAX} hari.</b>", parse_mode="HTML")
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
    ok, msg = await asyncio.to_thread(ssh_test)
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
) & spin $! "Install Bot"

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
[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable vpnbot >/dev/null 2>&1
systemctl restart vpnbot
sleep 4

# 8. SELESAI
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
echo -e "  ${GREEN}📌 Masa Aktif${NC}: Prompt 1-30, Validasi 1-365"
echo -e "  ${GREEN}📌 Backup${NC}  : ${GH_USER}/${GH_REPO}"
echo ""

#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
CYAN='\033[1;36m'; GREEN='\033[1;34m'; RED='\033[1;31m'
YELLOW='\033[1;33m'; MAGENTA='\033[1;35m'; WHITE='\033[1;37m'; BLUE='\033[1;34m'; NC='\033[0m'

spin(){
  local pid=$1 msg="$2"
  local f=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  while kill -0 "$pid" 2>/dev/null; do
    for x in "${f[@]}"; do
      printf "\r  ${MAGENTA}${x}${NC} ${CYAN}◆${NC} ${WHITE}%-34s${NC} ${BLUE}running...${NC}" "$msg"
      sleep 0.08
      kill -0 "$pid" 2>/dev/null || break
    done
  done
  wait "$pid"; local rc=$?
  if [ "$rc" -eq 0 ]; then
    printf "\r  ${BLUE}●${NC} ${WHITE}%-34s${NC} ${BLUE}DONE${NC}\n" "$msg"
  else
    printf "\r  ${RED}●${NC} ${WHITE}%-34s${NC} ${RED}FAILED${NC}\n" "$msg"
  fi
  return "$rc"
}

clear
printf "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
printf "        ${WHITE}SANSXML VPN STORE${NC}  ${BLUE}◆${NC}  ${WHITE}VPS INSTALLER${NC}\n"
printf "        ${CYAN}Premium VPN Server • Automated Installation${NC}\n"
printf "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
printf "  ${CYAN}◆${NC} ${WHITE}Starting installation...${NC} ${BLUE}Please wait${NC}\n\n"

# 1. DEPENDENCIES — Ubuntu / Debian only
if [ "$(id -u)" != "0" ]; then
  echo -e "  ${RED}ERROR${NC}: Jalankan installer sebagai root."
  exit 1
fi
[ -f /etc/os-release ] || { echo -e "  ${RED}ERROR${NC}: Tidak dapat mendeteksi OS.${NC}"; exit 1; }
. /etc/os-release
case "${ID:-}" in ubuntu|debian) ;; *) echo -e "  ${RED}OS TIDAK DIDUKUNG${NC}"; echo -e "  ${YELLOW}SC ini hanya mendukung Ubuntu dan Debian.${NC}"; exit 1;; esac
case "$(uname -m)" in x86_64|amd64|aarch64|arm64) ;; *) echo -e "  ${RED}ARSITEKTUR TIDAK DIDUKUNG${NC}: $(uname -m)"; exit 1;; esac
echo -e "  ${CYAN}OS${NC}       : ${PRETTY_NAME:-$ID}"
echo -e "  ${CYAN}VERSION${NC}  : ${VERSION_ID:-unknown}"
echo -e "  ${CYAN}ARCH${NC}     : $(uname -m)"

# Main domain used by the VPN and DNSTT/SlowDNS service.
DOMAIN="id-sansvpnstore.cloud"
# Track packages that were not installed before SANSXML, so EXIT can remove only what this installer added.
SC_PKG_FILE=/etc/sansxml-packages.list
SC_PKGS="python3 python3-pip python3-venv golang-go sshpass curl wget unzip stunnel4 dropbear haproxy nginx net-tools cron ufw iptables openssl cmake build-essential git pkg-config bc procps dnsutils vnstat uuid-runtime socat certbot ca-certificates"
: > "$SC_PKG_FILE"
for _p in $SC_PKGS; do
  dpkg-query -W -f='${Status}' "$_p" 2>/dev/null | grep -q 'install ok installed' || echo "$_p" >> "$SC_PKG_FILE"
done
chmod 600 "$SC_PKG_FILE"

_pkg_install(){
  dpkg --configure -a >/dev/null 2>&1 || true
  apt-get -f install -y >/dev/null 2>&1 || true
  echo "== apt-get update ==" > /tmp/sansxml-apt-install.log
  if ! apt-get update -y >> /tmp/sansxml-apt-install.log 2>&1; then return 1; fi
  echo "== apt-get install ==" >> /tmp/sansxml-apt-install.log
  apt-get install -y --no-install-recommends python3 python3-pip python3-venv golang-go sshpass curl wget unzip stunnel4 dropbear haproxy nginx net-tools cron ufw iptables openssl cmake build-essential git pkg-config bc procps dnsutils vnstat uuid-runtime socat ca-certificates >> /tmp/sansxml-apt-install.log 2>&1
}
_pkg_install & _pkg_pid=$!
spin $_pkg_pid "Install packages" || {
  echo -e "  ${RED}PACKAGE ERROR${NC}"
  tail -n 20 /tmp/sansxml-apt-install.log 2>/dev/null | sed 's/^/  /'
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

# 3b. SLOWDNS / DNSTT
# Real DNSTT server: persistent 64-hex key, UDP/5300 listener and UDP/53 -> 5300 redirect.
# The DNS zone still needs to be delegated at the domain provider (see /etc/dnstt/config).
(
  set -e
  DNSTT_DIR=/etc/dnstt
  DNSTT_BIN=/usr/local/bin/dnstt-server
  DNSTT_PORT=5300
  DNSTT_TUNNEL_DOMAIN="slow.${DOMAIN}"
  DNSTT_NS_HOST="ns.${DOMAIN}"
  mkdir -p "$DNSTT_DIR"
  chmod 700 "$DNSTT_DIR"

  # Build DNSTT. Prefer the upstream mirror on GitHub because some VPS DNS
  # resolvers cannot reach the original git host reliably.
  if ! command -v go >/dev/null 2>&1; then
    apt-get update -y >>/tmp/sansxml-dnstt-build.log 2>&1 || true
    apt-get install -y --no-install-recommends golang-go >>/tmp/sansxml-dnstt-build.log 2>&1 || true
  fi
  if ! command -v go >/dev/null 2>&1; then
    echo "Go compiler tidak tersedia. Lihat /tmp/sansxml-dnstt-build.log" >&2
    exit 1
  fi
  if [ ! -x "$DNSTT_BIN" ] || ! "$DNSTT_BIN" -h >/dev/null 2>&1; then
    rm -rf /tmp/dnstt-src
    if ! git clone --depth=1 https://github.com/Mygod/dnstt.git /tmp/dnstt-src >>/tmp/sansxml-dnstt-build.log 2>&1; then
      echo "Gagal mengambil source DNSTT dari GitHub" >&2
      exit 1
    fi
    cd /tmp/dnstt-src/dnstt-server
    if ! go build -trimpath -o "$DNSTT_BIN" . >>/tmp/sansxml-dnstt-build.log 2>&1; then
      echo "Gagal compile DNSTT. Lihat /tmp/sansxml-dnstt-build.log" >&2
      exit 1
    fi
    chmod 0755 "$DNSTT_BIN"
    rm -rf /tmp/dnstt-src
  fi

  # Stable keypair: never regenerate it during a normal reinstall/restart.
  if [ ! -s "$DNSTT_DIR/server.key" ] || [ ! -s "$DNSTT_DIR/server.pub" ]; then
    rm -f "$DNSTT_DIR/server.key" "$DNSTT_DIR/server.pub"
    "$DNSTT_BIN" -gen-key \
      -privkey-file "$DNSTT_DIR/server.key" \
      -pubkey-file "$DNSTT_DIR/server.pub" >/tmp/sansxml-dnstt-keygen.log 2>&1
  fi
  chmod 600 "$DNSTT_DIR/server.key"
  chmod 644 "$DNSTT_DIR/server.pub"

  DNSTT_PUBKEY="$(tr -d '[:space:]' < "$DNSTT_DIR/server.pub")"
  # Some builds may prefix the value with 'pubkey'; keep only the hexadecimal key.
  DNSTT_PUBKEY="$(printf '%s' "$DNSTT_PUBKEY" | sed -n 's/.*\([0-9A-Fa-f]\{64\}\).*/\1/p')"
  if ! printf '%s' "$DNSTT_PUBKEY" | grep -Eq '^[0-9a-fA-F]{64}$'; then
    echo "DNSTT public key bukan 64 karakter hexadecimal" >&2
    exit 1
  fi
  DNSTT_PUBKEY="$(printf '%s' "$DNSTT_PUBKEY" | tr '[:upper:]' '[:lower:]')"
  printf '%s\n' "$DNSTT_PUBKEY" > "$DNSTT_DIR/server.pub"

  if ! id dnstt >/dev/null 2>&1; then
    useradd --system --no-create-home --shell /usr/sbin/nologin dnstt
  fi
  chown dnstt:dnstt "$DNSTT_DIR" "$DNSTT_DIR/server.key" "$DNSTT_DIR/server.pub"

  # Forward the actual tunnel to SSH. DNSTT authenticates/encrypts the tunnel with server.key.
  cat > /etc/systemd/system/dnstt-server.service << EOF
[Unit]
Description=SANSXML SlowDNS (DNSTT) Server
After=network-online.target ssh.service
Wants=network-online.target

[Service]
Type=simple
User=dnstt
Group=dnstt
ExecStart=$DNSTT_BIN -udp :$DNSTT_PORT -privkey-file $DNSTT_DIR/server.key $DNSTT_TUNNEL_DOMAIN 127.0.0.1:22
Restart=always
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

  # Machine-readable values consumed by bot.py.
  cat > "$DNSTT_DIR/config" << EOF
SLOW_PORT=$DNSTT_PORT
SLOW_TUNNEL_DOMAIN=$DNSTT_TUNNEL_DOMAIN
SLOW_NS_HOST=$DNSTT_NS_HOST
SLOW_DNS_AUTH_NS=$DNSTT_NS_HOST
SLOW_PUBKEY=$DNSTT_PUBKEY
EOF
  # DNS delegation instructions. The installer cannot change registrar DNS without its API credentials.
  PUBLIC_IP="$(curl -4fsS --max-time 8 https://api.ipify.org 2>/dev/null || true)"
  cat > "$DNSTT_DIR/dns-records.txt" << EOF
# SANSXML SlowDNS / DNSTT
# VPS IPv4: ${PUBLIC_IP:-UNKNOWN}
# Add these records at your DNS provider:
# A   ${DNSTT_NS_HOST}   ${PUBLIC_IP:-YOUR_VPS_IP}
# NS  ${DNSTT_TUNNEL_DOMAIN}   ${DNSTT_NS_HOST}
#
# Internal service: UDP ${DNSTT_PORT}
# Public direct-DNS service: UDP 53 -> UDP ${DNSTT_PORT}
# Public key: ${DNSTT_PUBKEY}
EOF
  chmod 600 "$DNSTT_DIR/config"
  chmod 644 "$DNSTT_DIR/dns-records.txt"
  chmod 600 "$DNSTT_DIR/config"
  chown dnstt:dnstt "$DNSTT_DIR/config"

  systemctl daemon-reload
  systemctl enable dnstt-server >/dev/null 2>&1
  systemctl restart dnstt-server
  sleep 1
  systemctl is-active --quiet dnstt-server
  ss -lun | grep -Eq '(^|:)5300[[:space:]]' || { echo "DNSTT tidak listen di UDP/5300" >&2; exit 1; }
) & spin $! "Install SlowDNS / DNSTT"

( ufw default allow incoming >/dev/null 2>&1
  ufw default allow outgoing >/dev/null 2>&1
  # DNS tunnel clients normally reach UDP/53; DNSTT itself listens on 5300.
  iptables -t nat -C PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300 2>/dev/null || iptables -t nat -I PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300
  iptables -C INPUT -p udp --dport 5300 -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport 5300 -j ACCEPT
  for p in 22 80 443 8080 8443 8444 8445 10001 10002 10003 10004 10005 10006 10007; do ufw allow $p/tcp >/dev/null 2>&1; done
  ufw allow 53/udp >/dev/null 2>&1; ufw allow 5300/udp >/dev/null 2>&1; ufw allow 7300/udp >/dev/null 2>&1; ufw allow 1:65535/udp >/dev/null 2>&1
  ufw --force enable >/dev/null 2>&1 ) & spin $! "Configure firewall"

( systemctl daemon-reload
  systemctl enable ws-ssh ws-ssh-alt stunnel4 dropbear nginx haproxy dnstt-server >/dev/null 2>&1
  systemctl restart ws-ssh ws-ssh-alt stunnel4 dropbear nginx haproxy dnstt-server
  [ -f /usr/bin/badvpn-udpgw ] && systemctl enable udpgw >/dev/null 2>&1 && systemctl restart udpgw
  sleep 2 ) & spin $! "Start VPN services"

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
# Backup files that this installer modifies so EXIT can restore them.
mkdir -p /etc/sansxml-original
[ -f /etc/issue.net ] && cp -n /etc/issue.net /etc/sansxml-original/issue.net 2>/dev/null || true
[ -f /etc/motd ] && cp -n /etc/motd /etc/sansxml-original/motd 2>/dev/null || true
[ -f /etc/ssh/sshd_config ] && cp -n /etc/ssh/sshd_config /etc/sansxml-original/sshd_config 2>/dev/null || true
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

# Read the real DNSTT values after installation so the bot config is not a placeholder.
DNSTT_PUBKEY="$(tr -d '[:space:]' < /etc/dnstt/server.pub 2>/dev/null || true)"
DNSTT_PUBKEY="$(printf '%s' "$DNSTT_PUBKEY" | sed -n 's/.*\([0-9A-Fa-f]\{64\}\).*/\1/p')"
DNSTT_SLOW_HOST="$(awk -F= '/^SLOW_NS_HOST=/{print $2}' /etc/dnstt/config 2>/dev/null | tail -n1)"
[ -n "$DNSTT_SLOW_HOST" ] || DNSTT_SLOW_HOST="slow.${DOMAIN}"
if ! printf '%s' "$DNSTT_PUBKEY" | grep -Eq '^[0-9a-fA-F]{64}$'; then
  echo -e "  ${RED}SLOWDNS ERROR${NC}: Public key DNSTT tidak valid."
  exit 1
fi
DNSTT_SLOW_PORT="$(awk -F= '/^SLOW_PORT=/{print $2}' /etc/dnstt/config 2>/dev/null | tail -n1)"
DNSTT_TUNNEL_DOMAIN="$(awk -F= '/^SLOW_TUNNEL_DOMAIN=/{print $2}' /etc/dnstt/config 2>/dev/null | tail -n1)"
DNSTT_NS_HOST="$(awk -F= '/^SLOW_NS_HOST=/{print $2}' /etc/dnstt/config 2>/dev/null | tail -n1)"
[ -n "$DNSTT_SLOW_PORT" ] || DNSTT_SLOW_PORT=5300
[ -n "$DNSTT_TUNNEL_DOMAIN" ] || DNSTT_TUNNEL_DOMAIN="slow.${DOMAIN}"
[ -n "$DNSTT_NS_HOST" ] || DNSTT_NS_HOST="ns.${DOMAIN}"

# 6. BOT CONFIG
# Token Telegram sengaja dikosongkan saat instalasi.
# Token hanya diisi melalui menu [05] ADD TOKEN BOT.
BOT_TOKEN=""
GH_USER="Syahrul7y"; GH_REPO="Backup"
GH_EMAIL="hodamkecil@gmail.com"
GH_TOKEN=""

cat > /etc/sansxml-backup.conf << GHCFG
GH_USER="${GH_USER}"
GH_REPO="${GH_REPO}"
GH_TOKEN=""
GH_EMAIL="${GH_EMAIL}"
GHCFG
chmod 600 /etc/sansxml-backup.conf

DOMAIN="id-sansvpnstore.cloud"
ADMIN_ID="6144358600"

cat > /root/vpnbot_config.json << CFGEOF
{
  "bot_token": "${BOT_TOKEN}",
  "domain": "${DOMAIN}",
  "owner_ids": [${ADMIN_ID}],
  "servers": {
    "id_rmhweb_01": {"name": "🇮🇩 ID-RMHWEB-01", "city": "", "isp": "", "ssh_ovpn": "ID-RMHWEB-01", "domain": "${DOMAIN}", "price_day": 117, "price_month": 3510, "ip_limit": 1, "slot_max": 100, "quota_gb": 700, "slow_dns": "${DNSTT_SLOW_HOST}", "slow_port": ${DNSTT_SLOW_PORT}, "slow_ns": "${DNSTT_SLOW_HOST}", "slow_pubkey": "${DNSTT_PUBKEY}"},
    "id_rmhweb_02": {"name": "🇮🇩 ID-RMHWEB-02", "city": "", "isp": "", "ssh_ovpn": "ID-RMHWEB-02", "domain": "${DOMAIN}", "price_day": 167, "price_month": 5010, "ip_limit": 2, "slot_max": 100, "quota_gb": 800, "slow_dns": "", "slow_port": 5300, "slow_ns": "", "slow_pubkey": ""},
    "id_rmhweb_03": {"name": "🇮🇩 ID-RMHWEB-03", "city": "", "isp": "", "ssh_ovpn": "ID-RMHWEB-03", "domain": "${DOMAIN}", "price_day": 167, "price_month": 5010, "ip_limit": 1, "slot_max": 100, "quota_gb": 800, "slow_dns": "", "slow_port": 5300, "slow_ns": "", "slow_pubkey": ""},
    "id_rmhweb_04": {"name": "🇮🇩 ID-RMHWEB-04", "city": "", "isp": "", "ssh_ovpn": "ID-RMHWEB-04", "domain": "${DOMAIN}", "price_day": 167, "price_month": 5010, "ip_limit": 2, "slot_max": 100, "quota_gb": 800, "slow_dns": "", "slow_port": 5300, "slow_ns": "", "slow_pubkey": ""}
  },
  "ip_limit": 2,
  "block_hours": 2
}
CFGEOF

# 7. BOT.PY
echo ""
echo -e "\n  ${BLUE}BOT ENGINE${NC} ${CYAN}◆${NC}"
echo -e "  ${CYAN}▸${NC} ${WHITE}Install Bot.py${NC}"

cat > /root/bot.py << 'BOTPYEOF'
#!/usr/bin/env python3
import re, io, json, os, logging, subprocess, asyncio, base64, random, string, socket, shutil, time, uuid, functools
from datetime import datetime, timedelta

# Python 3.8 compatibility: asyncio.to_thread() was added in Python 3.9.
# The bot uses it in several async handlers, so provide a compatible fallback.
if not hasattr(asyncio, "to_thread"):
    async def _to_thread(func, /, *args, **kwargs):
        loop = asyncio.get_running_loop()
        return await loop.run_in_executor(None, functools.partial(func, *args, **kwargs))
    asyncio.to_thread = _to_thread
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
def ssh_create(u, p, days, is_trial=False, key="id_rmhweb_01"):
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
def ssh_extend(u, ne, key="id_rmhweb_01"):
    c,o,e = ssh_run(f"chage -E '{ne}' {u} 2>&1 ; echo DONE:$?", key)
    return "DONE:0" in o
def ssh_delete(u, key="id_rmhweb_01"):
    ssh_run(f"pkill -9 -u {u} 2>/dev/null; userdel -r {u} 2>&1; echo OK", key, timeout=20)
    return True
def ssh_test(key="id_rmhweb_01"):
    c,o,e = ssh_run("echo PING_OK", key, timeout=10)
    return ("PING_OK" in o, "SSH OK" if "PING_OK" in o else f"SSH gagal: {e or o}")

def valid_username(s): return bool(re.match(r'^[a-zA-Z0-9_]{5,20}$', s or ""))
def valid_password(s):
    if not s or len(s)<5 or len(s)>32: return False
    return all(c in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*_.-" for c in s)

def get_active_sessions(u, key="id_rmhweb_01"):
    try:
        c,o,_ = ssh_run("who", key, timeout=5)
        if c != 0: return []
        return [l for l in o.splitlines() if l.split() and l.split()[0] == u]
    except: return []
def count_live_shells(u, key="id_rmhweb_01"):
    try:
        c,o,_ = ssh_run(f"ps -u {u} -o comm=", key, timeout=5)
        if c != 0: return 0
        procs = [p.strip() for p in o.splitlines() if p.strip()]
        sh = ("bash","sh","zsh","ksh","dash","csh","tcsh")
        return sum(1 for p in procs if p.lstrip("-") in sh)
    except: return 0
def check_second(u, key="id_rmhweb_01"):
    sess = get_active_sessions(u, key); n = len(sess)
    if n<=1: return False,sess,n
    sh = count_live_shells(u, key)
    if sh>1: return True,sess,sh
    return False,sess,sh if sh>0 else n
def block_user(u, h=2, key="id_rmhweb_01"):
    try:
        ssh_run(f"passwd -l {u}", key, timeout=10)
        ssh_run(f"pkill -9 -u {u}", key, timeout=10)
        d = load_json(BLOCK_FILE, {})
        d[u] = {"blocked_at":datetime.now().isoformat(),
                "unblock_at":(datetime.now()+timedelta(hours=h)).strftime("%Y-%m-%d %H:%M:%S")}
        save_json(BLOCK_FILE, d); return True
    except: return False
def unblock_user(u, key="id_rmhweb_01"):
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
    return "\n".join(["<blockquote>","🔄 <b>BACKUP</b>","───────────────────────",
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
        sk = a.get("server_key","id_rmhweb_01")
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
        [B("➕ PERPANJANG AKUN","perpanjang_akun",style="primary")],
        [B("💰 TOPUP SALDO","isi_saldo",style="primary"),B("📁 AKUN SAYA","my_accs",style="primary")],
        [B("🌐 STATUS SERVER","status_server",style="primary"),B("♻️ REFRESH","refresh",style="primary")]]
    rows.append([B("⚙️ PENGATURAN","admin|menu",style="danger")])
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
        [B("➕ SSH","pilih|ssh",style="primary")],
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
        [B("⚙️ Kelola VPN","admin|srv",style="primary"),B("👤 Pengguna","admin|users|0",style="primary")],
        [B("📢 Broadcast","admin|bc",style="primary"),B("🔄 Backup","admin|backup",style="primary")],
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
    st = get_stats(uid)
    inc = get_income()
    tu = len(load_json(USERS_FILE,{}))
    lines = ["<blockquote>","🤖 <b>SANSXML VPN STORE</b>","───────────────────────","👤 <b>Profil</b>"]
    lines += [f"├ User Telegram  : {un}",f"├ Chat ID        : <code>{uid}</code>",
              f"├ Keanggotaan    : {role}",f"├ Total Pengguna : <b>{tu}</b>",
              f"╰ 💰 Saldo VPN  : <b>{rupiah(get_bal(uid))}</b>","",
              "📊 <b>Info Transaksi global</b>",
              f"├ Minggu Ini     : <b>{st['minggu']} Akun</b>",
              f"├ Bulan Ini      : <b>{st['bulan']} Akun</b>",
              f"╰ Keseluruhan    : <b>{st['total']} Akun</b>","",
              "🖥️ <b>Informasi</b>",
              f"├ Server Tersedia : <b>{len(get_active_servers())} Server</b>",
              f"├ Hari ini        : <b>{sum(1 for t in load_json(TRX_FILE,[]) if t.get('waktu','').startswith(datetime.now().strftime('%Y-%m-%d')) and t.get('tipe')=='buat_akun')} Akun</b>",
              f"├ Bulan ini       : <b>{st['bulan']} Akun</b>",
              f"├ Total Transaksi : <b>{rupiah(inc['total'])}</b>",
              f"╰ Kuota Trial     : <b>{trial_left(uid)}x Hari</b>","","───────────────────────","</blockquote>"]
    return "\n".join(lines)
def pilih_layanan_text():
    return "<blockquote>\n🌐 <b>PILIH LAYANAN VPN</b>\n───────────────────────\n<b>Silakan pilih protocol akun yang ingin di buat</b>\n</blockquote>"
def _server_list_text(title, status_mode="ssh"):
    a = get_active_servers()
    if not a: return "<blockquote>⚠️ <b>Belum ada server</b></blockquote>"
    lines = ["<blockquote>",f"<b>🌐 {title}</b>","─────────────────────────",""]
    for i,(k,s) in enumerate(a.items(),1):
        used,mx = get_slot_info(k)
        status = "🟢 Tersedia" if used < mx else "🔴 Penuh"
        lines += [f"<b>[{i}]</b>",f"◆ {s.get('name','-')}",
                  f"├ Harga Harian  : <b>{rupiah(s.get('price_day',0))}</b>",
                  f"├ Harga Bulanan : <b>{rupiah(s.get('price_month',0))}</b>",
                  f"├ Limit IP      : {s.get('ip_limit',1)} IP",
                  f"╰ Slot Tersedia : <b>{used}/{mx} {status}</b>",""]
    lines += ["─────────────────────────","</blockquote>"]
    return "\n".join(lines)
def ssh_server_text():
    return _server_list_text("DAFTAR SERVER SSH")
def xray_server_text(proto):
    t = {"vmess":"VMESS","vless":"VLESS","trojan":"TROJAN"}.get(proto,proto.upper())
    return _server_list_text(f"DAFTAR SERVER {t}", "xray")

def realtime_server_status():
    a = get_active_servers()
    lines = ["<blockquote>","🌐 <b>STATUS SERVER REAL-TIME</b>","───────────────────────",""]
    if not a:
        lines += ["⚠️ <b>Belum ada server</b>","</blockquote>"]
        return "\n".join(lines)
    for k,s in a.items():
        name = s.get("name","-")
        host = (s.get("ssh_host") or "").strip()
        # Server lokal memakai pemeriksaan lokal; server remote harus punya ssh_host
        start = time.monotonic()
        ok = False
        if not host or host in ("127.0.0.1","localhost"):
            try:
                r = subprocess.run(["true"],capture_output=True,timeout=3)
                ok = r.returncode == 0
            except:
                ok = False
        else:
            code, _, _ = ssh_run("echo PING_OK", k, timeout=8)
            ok = code == 0
        ms = max(1, round((time.monotonic()-start)*1000))
        status = f"🟢 ONLINE • {ms} ms" if ok else "🔴 OFFLINE"
        lines += [f"🖥️ <b>{name}</b>",f"   └ Status: <b>{status}</b>",""]
    lines += ["───────────────────────","</blockquote>"]
    return "\n".join(lines)
def saldo_text(uid, nom=""):
    return (f"<blockquote>💰 <b>Masukkan jumlah nominal topup saldo</b>\n\n"
            f"Jumlah saldo VPN saat ini: <b>{rupiah(get_bal(uid))}</b>\n\n"
            f"Nominal input: <b>{rupiah(nom) if nom else 'Rp 0'}</b>\n"
            f"Minimal topup {rupiah(MIN_TOPUP)}\n\n"
            f"❖ <i>Saldo dapat digunakan untuk membuat akun VPN</i> ❖\n</blockquote>")

def acc_caption(u, p, exp, dl, ip, manual=False, is_trial=False, server_key="id_rmhweb_01", exp_ts="", created_at=""):
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
    ssh_ovpn_val = srv.get("ssh_ovpn") or srv.get("name","ID-RMHWEB-01")
    host = srv.get("domain") or SSH_HOST
    quota = srv.get("quota_gb", 700) or 700
    payload_ws = "GET /cdn-cgi/trace HTTP/1.1[crlf]Host: [host][crlf][crlf]GET-RAY / HTTP/1.1[crlf]Host: [host][crlf]Connection: Upgrade[crlf]User-Agent: [ua][crlf]Upgrade: websocket[crlf][crlf]"
    payload_tls = "GET / HTTP/1.1[crlf]Host: [host][crlf]User-Agent: [ua][crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]"
    slow_port = int(srv.get("slow_port", 5300) or 5300)
    slow_ns = str(srv.get("slow_ns") or "").strip()
    slow_pubkey = str(srv.get("slow_pubkey") or "").strip()
    # Always prefer the real local DNSTT configuration when this is the local server.
    if server_key == "id_rmhweb_01":
        try:
            dcfg = "/etc/dnstt/config"
            if os.path.exists(dcfg):
                vals = {}
                for _line in open(dcfg, encoding="utf-8", errors="ignore"):
                    if "=" in _line:
                        _k,_v = _line.rstrip("\n").split("=",1); vals[_k] = _v.strip()
                slow_port = int(vals.get("SLOW_PORT", slow_port) or slow_port)
                slow_ns = vals.get("SLOW_NS_HOST", slow_ns) or slow_ns
                slow_pubkey = vals.get("SLOW_PUBKEY", slow_pubkey) or slow_pubkey
        except: pass
    slow_line = f"{slow_ns}:{slow_port}@{u}:{p}" if slow_ns and slow_pubkey and slow_port else "-"
    esc = lambda x: str(x).replace("&","&amp;").replace("<","&lt;").replace(">","&gt;")
    L = [
        f"┌────────────────────────",
        f"│   <b>♨️ SSH ACCOUNT {head} ♨️</b>",
        f"└────────────────────────", "",
        f"┌────────────────────────",
        f"│ <b>City</b>       : {esc(srv.get('city',''))}",
        f"│ <b>ISP</b>        : {esc(srv.get('isp',''))}",
        f"│ <b>SSH</b>        : {esc(ssh_ovpn_val)}",
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
        f"│ <b>Slow Dns</b>   : {esc(str(slow_port))}",
        f"│ <b>Nama server</b> : {esc(slow_ns or '-')}",
        f"│ <b>Pub key</b>    : {esc(slow_pubkey or '-')}",
        f"└────────────────────────", "",
        "──────────────────────────",
        f"🔐 <b>SSH WS</b>  : {esc(host)}:80@{esc(u)}:{esc(p)}",
        f"🔐 <b>SSH TLS</b> : {esc(host)}:443@{esc(u)}:{esc(p)}",
        f"🔐 <b>SSH UDP</b> : {esc(host)}:1-65535@{esc(u)}:{esc(p)}",
        f"🔐 <b>SSH SLOW</b> : {esc(slow_line)}", "",
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
    city = s.get("city",""); isp = s.get("isp","")
    ssh_ovpn = s.get("ssh_ovpn") or s.get("name","ID-RMHWEB-01")
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
        f"│ <b>City</b>       : {esc(city)}", f"│ <b>ISP</b>        : {esc(isp)}", f"│ <b>SSH</b>   : {esc(ssh_ovpn)}",
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
async def do_create(chat, uid, user, un, pw, hari, is_trial=False, sk="id_rmhweb_01"):
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
        "free_owner":is_owner(uid),"is_trial":is_trial,"server_key":sk,"server":s.get("name","ID-RMHWEB-01"),
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
        try: await asyncio.to_thread(ssh_delete,un,a.get("server_key","id_rmhweb_01"))
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
                    proto = a.get("proto","ssh"); sk = a.get("server_key","id_rmhweb_01")
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
                sk = a.get("server_key","id_rmhweb_01")
                v,_,cnt = await asyncio.to_thread(check_second,un,sk)
                if v:
                    try: await asyncio.to_thread(block_user,un,BLOCK_HOURS,sk)
                    except: pass
            blk = load_json(BLOCK_FILE,{}); chg = False
            for un,info in list(blk.items()):
                try:
                    if now >= datetime.strptime(info["unblock_at"],"%Y-%m-%d %H:%M:%S"):
                        sk = (get_acc(un) or {}).get("server_key","id_rmhweb_01")
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

    if d == "status_server":
        try:
            await q.edit_message_text(realtime_server_status(),
                reply_markup=InlineKeyboardMarkup([
                    [B("🔄 CEK LAGI","status_server",style="primary")],
                    [B("🔙 KEMBALI","menu|main",style="danger")]
                ]),parse_mode="HTML")
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
        lines = ["<blockquote>","🌐 <b>DAFTAR SERVER</b>","───────────────────────",""]
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
        cty = s.get("city","") or ""; isp_v = s.get("isp","") or ""
        slow_dns_v = s.get("slow_dns","") or ""
        slow_port_v = s.get("slow_port",5300) or 5300
        slow_ns_v = s.get("slow_ns","") or ""
        slow_pub_v = s.get("slow_pubkey","") or ""
        warn = "\n⚠️ <b>Lengkapi dulu</b>\n" if not comp else "\n✅ <i>Aktif</i>\n"
        txt = (f"<blockquote><b>{s.get('name','-')}</b>\n───────────────────────\n\n"
            f"├ City          : <b>{cty}</b>\n├ ISP           : <b>{isp_v}</b>\n"
            f"├ Harga Harian  : <b>{pds}</b>\n├ Harga Bulanan : <b>{pms}</b>\n"
            f"├ Qouta         : <b>{qgs}</b>\n├ Limit IP      : <b>{ips}</b>\n"
            f"├ Slot Server   : <b>{sms}</b>\n├ Slow DNS      : <b>{slow_dns_v + ':' + str(slow_port_v) if slow_dns_v else '❌'}</b>\n├ Nama Server   : <b>{slow_ns_v or '❌'}</b>\n├ Pub Key       : <b>{slow_pub_v or '❌'}</b>\n╰ Domain       : <b>{doms}</b>\n{warn}</blockquote>")
        rows = [[B("Nama Server",f"srv_set|{k}|name",style="primary"),B("Harga Bulanan",f"srv_set|{k}|price_month",style="primary")],
            [B("Kota / City",f"srv_set|{k}|city",style="primary"),B("ISP",f"srv_set|{k}|isp",style="primary")],
            [B("Quota GB",f"srv_set|{k}|quota_gb",style="primary"),B("Limit IP",f"srv_set|{k}|ip_limit",style="primary")],
            [B("Slot Server",f"srv_set|{k}|slot_max",style="primary"),B("Domain Server",f"srv_set|{k}|domain",style="primary")],
            [B("Slow DNS",f"srv_set|{k}|slow_dns",style="primary"),B("Port SlowDNS",f"srv_set|{k}|slow_port",style="primary")],
            [B("Nama Server SlowDNS",f"srv_set|{k}|slow_ns",style="primary"),B("Pub Key SlowDNS",f"srv_set|{k}|slow_pubkey",style="primary")]]
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
              "slot_max":f"Kirim jumlah slot server baru untuk <b>{sname}</b>\nContoh: <code>100</code>",
              "domain":f"Kirim DOMAIN baru untuk <b>{sname}</b>\nContoh: <code>id-sansvpnstore.cloud</code>",
              "slow_dns":f"Kirim host SlowDNS untuk <b>{sname}</b>\nContoh: <code>ns-id3.example.com</code>",
              "slow_port":f"Kirim port SlowDNS untuk <b>{sname}</b>\nContoh: <code>5300</code>",
              "slow_ns":f"Kirim Nama Server / NS SlowDNS untuk <b>{sname}</b>\nContoh: <code>ns-id3.example.com</code>",
              "slow_pubkey":f"Kirim Pub Key SlowDNS untuk <b>{sname}</b>\nContoh: <code>64 karakter hexadecimal</code>"}
        try: await q.edit_message_text(pr.get(f,"Kirim:"),reply_markup=InlineKeyboardMarkup([[B("❌ Batal",f"srv_edit|{k}",style="danger")]]),parse_mode="HTML")
        except: pass
        return
    if d == "srv_add":
        if not is_owner(uid): return
        try: await q.edit_message_text(
            "<blockquote>➕ <b>TAMBAH SERVER</b>\n───────────────────────\n\n"
            "Pilih jenis server yang ingin ditambahkan.</blockquote>",
            reply_markup=InlineKeyboardMarkup([
                [B("➕ SERVER","srv_add_local",style="success"),B("🔌 REMOTE","srv_add_remote",style="primary")],
                [B("🔙 Kembali","admin|srv",style="danger")]
            ]),parse_mode="HTML")
        except: pass
        return
    if d == "srv_add_local":
        if not is_owner(uid): return
        # Jika server lokal sudah ada, langsung buka SET SERVER.
        # Jangan hanya mengirim q.answer kedua karena callback sudah di-answer di awal cb().
        existing = next((kk for kk in SERVERS if is_local_server(kk)), None)
        if existing:
            try:
                await q.edit_message_text(
                    "<blockquote>ℹ️ <b>SERVER LOKAL SUDAH ADA</b>\n\n"
                    "Server lokal sudah ditambahkan.\n"
                    "Sekarang tinggal atur konfigurasinya.</blockquote>",
                    reply_markup=InlineKeyboardMarkup([
                        [B("⚙️ SET SERVER",f"srv_edit|{existing}",style="primary")],
                        [B("🔙 Kembali","admin|srv",style="danger")]
                    ]),parse_mode="HTML")
            except Exception as e:
                logger.error(f"srv_add_local existing: {e}")
            return
        kn = "local_server"
        if kn in SERVERS:
            kn = f"local_{int(time.time())}"
        nama = "🇮🇩 LOCAL SERVER"
        SERVERS[kn] = {"name":nama,"ssh_host":"127.0.0.1","ssh_port":22,"ssh_user":"root",
            "ssh_key":SSH_KEY_PATH,"city":"","isp":"","ssh_ovpn":nama,
            "domain":None,"price_day":None,"price_month":None,
            "ip_limit":None,"slot_max":None,"quota_gb":None,"slow_dns":"","slow_port":5300,"slow_ns":"","slow_pubkey":""}
        save_servers()
        try: await q.edit_message_text(
            f"<blockquote>✅ <b>{nama} ditambahkan</b>\n\n"
            "Server lokal sudah siap.\n"
            "Sekarang tinggal atur nama, harga, limit, slot, domain, dan data lainnya.</blockquote>",
            reply_markup=InlineKeyboardMarkup([
                [B("⚙️ SET SERVER",f"srv_edit|{kn}",style="primary")],
                [B("🔙 Kembali","admin|srv",style="danger")]
            ]),parse_mode="HTML")
        except: pass
        asyncio.create_task(sync_push_async())
        return
    if d == "srv_add_remote":
        if not is_owner(uid): return
        c.user_data["srv_add_step"] = "input"
        try: await q.edit_message_text(
            "<blockquote>🔌 <b>TAMBAH SERVER REMOTE</b>\n───────────────────────\n"
            "Format: <code>nama|ip|port</code>\n\n"
            "Contoh:\n<code>🇮🇩 ID-RMHWEB-05|103.123.45.67|22</code></blockquote>",
            reply_markup=InlineKeyboardMarkup([[B("❌ Batal","admin|srv",style="danger")]]),parse_mode="HTML")
        except: pass
        return
    if d == "srv_del_list":
        if not is_owner(uid): return
        if not SERVERS:
            try: await q.edit_message_text("<blockquote>🚫 <b>HAPUS SERVER</b>\n───────────────────────\n\n⚠️ Belum ada server.\n</blockquote>",
                reply_markup=InlineKeyboardMarkup([[B("🔙 Kembali","admin|srv",style="danger")]]),parse_mode="HTML")
            except: pass
            return
        rows = []
        for k,v in SERVERS.items():
            tag = " • LOCAL" if is_local_server(k) else " • REMOTE"
            rows.append([B(f"{v.get('name','-')}{tag}",f"srv_del|{k}",style="danger")])
        rows.append([B("🔙 Kembali","admin|srv",style="danger")])
        try: await q.edit_message_text("<blockquote>🚫 <b>HAPUS SERVER</b>\n───────────────────────\n\nPilih server yang ingin dihapus:\n</blockquote>",
            reply_markup=InlineKeyboardMarkup(rows),parse_mode="HTML")
        except: pass
        return
    if d.startswith("srv_del|"):
        if not is_owner(uid): return
        k = d.split("|")[1]
        if k not in SERVERS: await q.answer("No",show_alert=True); return
        s = SERVERS[k]; used = count_slots(k)
        try: await q.edit_message_text(
            f"<blockquote>⚠️ <b>KONFIRMASI HAPUS</b>\n───────────────────────\n"
            f"Server: <b>{s.get('name','-')}</b>\nHost: <code>{s.get('ssh_host','-')}:{s.get('ssh_port',22)}</code>\nAkun: <b>{used}</b>\n\n"
            f"🔴 Server akan dihapus dari konfigurasi bot dan akun terkait.\n"
            f"{'⚠️ Server lokal: user OS VPS tidak akan dihapus.' if is_local_server(k) else '⚠️ Server remote: user OS bot akan dibersihkan.'}\n\n"
            f"⚠️ <i>Tidak bisa dipulihkan!</i>\n</blockquote>",
            reply_markup=InlineKeyboardMarkup([[B("✅ Ya, Hapus",f"srv_del_yes|{k}",style="danger")],
                [B("❌ Batal",f"srv_edit|{k}",style="danger")]]),parse_mode="HTML")
        except: pass
        return
    if d.startswith("srv_del_yes|"):
        if not is_owner(uid): return
        k = d.split("|")[1]
        if k not in SERVERS: await q.answer("No",show_alert=True); return
        try: await q.edit_message_text("🗑️ <b>Menghapus...</b>",parse_mode="HTML")
        except: pass
        s = SERVERS[k]; dele = 0
        if not is_local_server(k):
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
            reply_markup=InlineKeyboardMarkup([[B("🌐 Daftar Server","admin|srv",style="primary")],
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
            reply_markup=InlineKeyboardMarkup([[B("🌐 Daftar Server","admin|srv",style="primary")],
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
        if not is_owner(uid):
            await q.answer("⚠️ Khusus owner bot",show_alert=True); return
        inc = get_income(); us = count_users_by_period()
        svr_stat = get_server_status()
        svr_parts = []
        for s in svr_stat:
            tag = "" if s["complete"] else " ⚠️"
            bw = s["bw"]; bws = f"{bw:.0f}" if bw >= 1 else f"{bw:.1f}"
            svr_parts.append(f"├ {s['name']}{tag}\n│ ├ Qouta  : <b>{bws}/{s['quota']}</b>\n│ ├ Slot   : <b>{s['used']}/{s['max']}</b>\n│ ╰ Status : <b>{s['status']}</b>")
        svr_txt = "\n".join(svr_parts)
        txt = ("<blockquote>⚙️ <b>PENGATURAN</b>\n───────────────────────\n"
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
            cap = acc_caption(a.get("username",un),a['password'],a['exp'],dl,a.get('limit_ip',1),a.get('manual',False),a.get('is_trial',False),a.get('server_key','id_rmhweb_01'))
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
            xsk = a.get('server_key','id_rmhweb_01')
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
                "ssh_key":SSH_KEY_PATH,"city":"","isp":"","ssh_ovpn":nama,
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
            "ssh_key":kf,"city":"","isp":"","ssh_ovpn":nama,
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
            elif f == "slow_dns":
                s["slow_dns"] = val; out = f"Slow DNS → <b>{val}</b>"
            elif f == "slow_port":
                a = int(re.sub(r'[^0-9]','',val))
                if a <= 0 or a > 65535: await u.message.reply_text("❌ Port tidak valid",parse_mode="HTML"); return
                s["slow_port"] = a; out = f"Port SlowDNS → <b>{a}</b>"
            elif f == "slow_ns":
                s["slow_ns"] = val; out = f"Nama Server → <b>{val}</b>"
            elif f == "slow_pubkey":
                if val and not re.fullmatch(r'[0-9a-fA-F]{64}', val):
                    await u.message.reply_text("❌ Pub Key harus 64 karakter hexadecimal",parse_mode="HTML"); return
                s["slow_pubkey"] = val.lower(); out = f"Pub Key → <b>{val.lower()}</b>"
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
            sk = data.get("server_key","id_rmhweb_01"); proto = data.get("proto","ssh")
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
        sk = data.get("server_key","id_rmhweb_01")
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
    ok,msg = await asyncio.to_thread(ssh_test,"id_rmhweb_01")
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
StandardOutput=append:/root/vpnbot.log
StandardError=append:/root/vpnbot.log
Environment=PYTHONUNBUFFERED=1
[Install]
WantedBy=multi-user.target
SVCEOF
systemctl daemon-reload
systemctl enable vpnbot >/dev/null 2>&1
# Bot baru dijalankan setelah token diisi lewat menu [05].
if [ -n "$BOT_TOKEN" ]; then
    systemctl restart vpnbot
    sleep 3
else
    systemctl stop vpnbot >/dev/null 2>&1 || true
fi

# 9. MENU VPS
echo ""
echo -e "\n  ${BLUE}CONTROL PANEL${NC} ${CYAN}◆${NC}"
echo -e "  ${CYAN}▸${NC} ${WHITE}Install VPS Dashboard${NC}"

cat > /usr/local/bin/sansxml-menu << 'MENUEOF'
#!/bin/bash
PU='\033[1;34m'; PU2='\033[1;36m'; CY='\033[1;36m'
PK='\033[1;34m'; WH='\033[1;37m'; GR='\033[1;34m'
RE='\033[1;31m'; YE='\033[1;33m'; GY='\033[1;36m'; N='\033[0m'
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
show_banner(){
    local os kernel cpu load ram disk up now ip bot ws ssl udp xry ngx drp hap
    local sshc vmc vlc trc total onl
    os=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')
    kernel=$(uname -r 2>/dev/null)
    cpu=$(nproc 2>/dev/null || echo 0)
    load=$(awk '{print $1" "$2" "$3}' /proc/loadavg 2>/dev/null)
    ram=$(get_ram_pct); disk=$(get_disk_pct); up=$(get_uptime)
    now=$(date '+%d %b %Y  %H:%M:%S')
    ip=$(get_ip)
    bot=$(systemctl is-active vpnbot 2>/dev/null); ws=$(systemctl is-active ws-ssh 2>/dev/null)
    ssl=$(systemctl is-active stunnel4 2>/dev/null); udp=$(systemctl is-active udpgw 2>/dev/null)
    xry=$(systemctl is-active xray 2>/dev/null); ngx=$(systemctl is-active nginx 2>/dev/null)
    drp=$(systemctl is-active dropbear 2>/dev/null); hap=$(systemctl is-active haproxy 2>/dev/null)
    sshc=$(get_ssh_count); vmc=$(get_xray_count vmess); vlc=$(get_xray_count vless); trc=$(get_xray_count trojan)
    total=$((sshc+vmc+vlc+trc)); onl=$(get_online)

    echo ""
    printf "        ${PU2}✦${N} ${WH}sansxml${N}  ${CY}◆${N}  ${PU2}VPS${N}  ${CY}◆${N}\n"
    printf "        ${CY}%s${N}\n\n" "$now"

    printf "${PU}╭─ ${PK}SERVER${PU} ─────────────────────────────────────────────────────╮${N}\n"
    printf " ${GY}OS${N}       ${WH}%s${N}   ${GY}CPU${N} ${WH}%s vCPU${N}\n" "$os" "$cpu"
    printf " ${GY}KERNEL${N}   ${WH}%s${N}   ${GY}LOAD${N} ${WH}%s${N}\n" "$kernel" "$load"
    printf " ${GY}RAM${N}      ${WH}%s  %s${N}   ${GY}DISK${N} ${WH}%s  %s${N}\n" "$(bar "$ram")" "${ram}%" "$(bar "$disk")" "${disk}%"
    printf " ${GY}UPTIME${N}   ${WH}%s${N}   ${GY}STATUS${N} ${GR}●${N} ${WH}ONLINE${N}\n" "$up"
    printf " ${GY}IP${N}       ${WH}%s${N}\n" "$ip"
    printf "${PU}╰──────────────────────────────────────────────────────────────╯${N}\n\n"

    printf "${PU}╭─ ${PK}TRAFFIC${PU} ────────────────────────────────────────────────────╮${N}\n"
    printf " ${GY}TODAY${N}    ${WH}%s${N}\n" "$(get_traffic_pair d)"
    printf " ${GY}MONTH${N}    ${WH}%s${N}\n" "$(get_traffic_pair m)"
    printf " ${GY}SPEED${N}    ${WH}%s${N}   ${GY}%s${N}\n" "$(get_speed)" "$(date '+%B' | tr '[:upper:]' '[:lower:]')"
    printf " ${GY}LIMIT${N}    ${WH}0 / 3000 GB${N}\n"
    printf "${PU}╰──────────────────────────────────────────────────────────────╯${N}\n\n"

    printf "${PU}╭─ ${PK}SERVICES${PU} ───────────────────────────────────────────────────╮${N}\n"
    printf " ${WH}%b BOT${N}       ${WH}%b SSH-WS${N}    ${WH}%b SSL${N}      ${WH}%b UDP${N}\n" \
      "$(status_dot "$bot")" "$(status_dot "$ws")" "$(status_dot "$ssl")" "$(status_dot "$udp")"
    printf " ${WH}%b XRAY${N}     ${WH}%b NGIX${N}      ${WH}%b DROPBEAR${N}  ${WH}%b HAPROXY${N}\n" \
      "$(status_dot "$xry")" "$(status_dot "$ngx")" "$(status_dot "$drp")" "$(status_dot "$hap")"
    printf "${PU}╰──────────────────────────────────────────────────────────────╯${N}\n\n"

    printf "${PU}╭─ ${PK}ACCOUNTS${PU} ───────────────────────────────────────────────────╮${N}\n"
    printf " ${GY}SSH/OVPN${N} ${WH}%s${N}   ${GY}VMESS${N} ${WH}%s${N}   ${GY}VLESS${N} ${WH}%s${N}   ${GY}TROJAN${N} ${WH}%s${N}   ${GY}TOTAL${N} ${WH}%s${N}\n" "$sshc" "$vmc" "$vlc" "$trc" "$total"
    printf " ${GY}LIVE${N}     ${GR}●${N} ${WH}OK${N}   ${GY}ONLINE${N} ${WH}%s${N}   ${GY}RAM${N} ${WH}%s%%${N}   ${GY}CPU${N} ${WH}%s%%${N}\n" "$onl" "$ram" "$(get_cpu_pct)"
    printf "${PU}╰──────────────────────────────────────────────────────────────╯${N}\n"
}

status_dot(){ [ "$1" = "active" ] && printf "${GR}●${N}" || printf "${RE}●${N}"; }
get_xray_count(){
    local proto="$1" f="/root/vpnbot_accounts.json"
    [ ! -f "$f" ] && { echo 0; return; }
    python3 - "$proto" "$f" <<'PYCODE'
import json,sys
proto,path=sys.argv[1],sys.argv[2]
try:
    d=json.load(open(path))
    print(sum(1 for a in d.values() if a.get("proto")==proto))
except Exception:
    print(0)
PYCODE
}
get_ssh_count(){
    local f="/root/vpnbot_accounts.json"
    [ ! -f "$f" ] && { echo 0; return; }
    python3 - "$f" <<'PYCODE'
import json,sys
try:
    d=json.load(open(sys.argv[1])); print(sum(1 for a in d.values() if a.get("proto","ssh")=="ssh"))
except Exception:
    print(0)
PYCODE
}
get_traffic_pair(){
    local mode="$1"
    command -v vnstat >/dev/null 2>&1 || { echo "0 MiB  0 MiB  0 MiB"; return; }
    vnstat --json "$mode" 1 2>/dev/null | python3 -c '
import sys,json
mode=sys.argv[1]
try:
    d=json.load(sys.stdin); ifs=d.get("interfaces",[])
    arr=ifs[0].get("traffic",{}).get("day" if mode=="d" else "month",[]) if ifs else []
    x=arr[-1] if arr else {}
    rx=float(x.get("rx",0)); tx=float(x.get("tx",0)); total=rx+tx
    def fmt(v):
        if v >= 1024**3: return f"{v/1024**3:.1f} GiB"
        return f"{v/1024**2:.0f} MiB"
    print(f"{fmt(rx)}  {fmt(tx)}  {fmt(total)}")
except Exception:
    print("0 MiB  0 MiB  0 MiB")
' "$mode"
}
get_speed(){
    local a rx1 tx1 rx2 tx2
    a=$(awk 'NR>2{gsub(":","",$1);rx+=$2;tx+=$10}END{print rx,tx}' /proc/net/dev)
    sleep 1
    local b=$(awk 'NR>2{gsub(":","",$1);rx+=$2;tx+=$10}END{print rx,tx}' /proc/net/dev)
    rx1=$(awk '{print $1}' <<<"$a"); tx1=$(awk '{print $2}' <<<"$a")
    rx2=$(awk '{print $1}' <<<"$b"); tx2=$(awk '{print $2}' <<<"$b")
    awk -v r=$((rx2-rx1)) -v t=$((tx2-tx1)) 'BEGIN{printf "%.2f Mbit/s",((r+t)*8)/1000000}'
}
get_cpu_pct(){
    local a b
    a=$(awk '/^cpu /{print $2+$3+$4+$5+$6+$7+$8, $5}' /proc/stat)
    sleep 0.2
    b=$(awk '/^cpu /{print $2+$3+$4+$5+$6+$7+$8, $5}' /proc/stat)
    awk -v a="$a" -v b="$b" 'BEGIN { split(a,x); split(b,y); dt=y[1]-x[1]; di=y[2]-x[2]; if (dt > 0) printf "%d", ((dt-di)/dt)*100; else printf "0" }'
}
show_menu(){ clear
    show_banner
    printf "\n${PU}╭─ ${PK}MENU${PU} ───────────────────────────────────────────────────────╮${N}\n"
    printf " ${CY}[1]${N}  ${WH}AUTO STOP BOT${N}          ${CY}[4]${N}  ${WH}SERVICE STATUS${N}\n"
    printf " ${CY}[2]${N}  ${WH}VPS INFORMATION${N}        ${CY}[5]${N}  ${WH}JALANKAN BOT${N}\n"
    printf " ${CY}[3]${N}  ${WH}BANDWIDTH${N}              ${CY}[6]${N}  ${WH}EXIT / BERSIHKAN SC${N}\n"
    printf "${PU}╰──────────────────────────────────────────────────────────────╯${N}\n\n"
    echo -ne "${PU2}✦${N} ${CY}Select${N} ${WH}[1-6]${N} ${PU2}›${N} "
}
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
    local svcs=("vpnbot:Telegram Bot" "ws-ssh:WS-SSH 80" "ws-ssh-alt:WS-SSH 8080" "stunnel4:SSL Tunnel" "udpgw:UDP Gateway" "xray:Xray VMess/VLESS/Trojan" "nginx:Nginx" "dropbear:Dropbear 109" "haproxy:HAProxy" "ssh:SSH Service")
    for e in "${svcs[@]}"; do
        local s="${e%%:*}"; local l="${e##*:}"
        local st=$(systemctl is-active "$s" 2>/dev/null || echo off)
        if [ "$st" = "active" ]; then printf " ${GR}●${N} ${WH}%-24s${N} ${WH}%s${N}\n" "$l" "$st"
        else printf " ${RE}●${N} ${WH}%-24s${N} ${WH}%s${N}\n" "$l" "$st"; fi
    done
    box_bot; echo ""; echo -ne "${PK}◆${N} ${PU2}ENTER untuk kembali...${N}"; read; }
run_bot(){ clear; show_banner; box_top "JALANKAN BOT"
    local token="$(python3 -c "import json; print(json.load(open('/root/vpnbot_config.json')).get('bot_token',''))" 2>/dev/null)"
    if [ -n "$token" ]; then
        local masked="${token:0:10}***${token: -5}"
        kv "Token Tersimpan" "$masked"
    else
        kv "Token" "Belum diisi"
    fi
    box_bot; echo ""
    echo -ne "${PK}◆${N} ${PU2}Masukkan Token Bot Telegram${N} ${PU}›${N} "
    IFS= read -r nt
    nt="${nt//$'\r'/}"
    [ -z "$nt" ] && { echo -e "${RE}  Dibatalkan${N}"; sleep 1; return; }

    echo -e "\n  ${PU2}Memeriksa token...${N}"
    if ! python3 - "$nt" <<'PYTOKEN'
import sys, json, urllib.request, urllib.error
x=sys.argv[1].strip()
if len(x) < 20 or ':' not in x:
    raise SystemExit(1)
url=f"https://api.telegram.org/bot{x}/getMe"
req=urllib.request.Request(url, headers={"User-Agent":"SANSXML-VPN-BOT/1.0"})
try:
    with urllib.request.urlopen(req, timeout=10) as r:
        j=json.loads(r.read().decode("utf-8"))
except Exception:
    raise SystemExit(1)
if not j.get("ok"):
    raise SystemExit(1)
print(j.get("result",{}).get("username", ""))
PYTOKEN
    then
        echo -e "  ${RE}✗ TOKEN TIDAK VALID / API TELEGRAM TIDAK DAPAT DIAKSES${N}"
        echo -e "  ${GY}Token tidak disimpan. Periksa token dari @BotFather.${N}"
        box_bot; echo ""; echo -ne "${PK}◆${N} ${PU2}ENTER untuk kembali...${N}"; read; return
    fi

    if ! python3 - "$nt" <<'PYWRITE'
import json,sys,os,tempfile
f='/root/vpnbot_config.json'
d=json.load(open(f))
d['bot_token']=sys.argv[1].strip()
fd,tmp=tempfile.mkstemp(prefix='vpnbot_config.',dir='/root',text=True)
with os.fdopen(fd,'w') as h: json.dump(d,h,indent=2,ensure_ascii=False); h.write('\n')
os.replace(tmp,f)
os.chmod(f,0o600)
PYWRITE
    then
        echo -e "  ${RE}✗ Gagal menyimpan konfigurasi.${N}"
        box_bot; echo ""; echo -ne "${PK}◆${N} ${PU2}ENTER untuk kembali...${N}"; read; return
    fi

    echo -e "  ${PU2}Memeriksa modul bot...${N}"
    if ! python3 -c 'import telegram; print(telegram.__version__)' >/tmp/vpnbot_telegram_version 2>/tmp/vpnbot_import_error; then
        echo -e "  ${RE}✗ Modul python-telegram-bot tidak tersedia.${N}"
        cat /tmp/vpnbot_import_error 2>/dev/null
        box_bot; echo ""; echo -ne "${PK}◆${N} ${PU2}ENTER untuk kembali...${N}"; read; return
    fi
    echo -e "  ${PU2}Menjalankan bot...${N}"
    : > /root/vpnbot.log
    chmod 600 /root/vpnbot.log
    systemctl daemon-reload 2>/dev/null || true
    systemctl enable vpnbot >/dev/null 2>&1 || true
    systemctl restart vpnbot >/dev/null 2>&1 || true
    sleep 3
    local st="$(systemctl is-active vpnbot 2>/dev/null || true)"
    clear; show_banner; box_top "STATUS BOT"
    if [ "$st" = "active" ]; then
        kvc "Result" "✓ BOT BERHASIL DIJALANKAN" "${GR}"
        kv "Service" "vpnbot"
    else
        kvc "Result" "✗ BOT GAGAL BERJALAN" "${RE}"
        echo ""
        echo -e "  ${YE}Log terakhir:${N}"
        tail -n 20 /root/vpnbot.log 2>/dev/null || true
        echo ""
        systemctl --no-pager --full status vpnbot 2>/dev/null | tail -n 15 || true
    fi
    box_bot; echo ""; echo -ne "${PK}◆${N} ${PU2}ENTER untuk kembali...${N}"; read; }

uninstall_sc(){ clear; show_banner
    printf "${PU}╭─ ${PK}UNINSTALL SANSXML SC${PU} ──────────────────────────────────────╮${N}\n"
    printf " ${WH}EXIT akan menghapus komponen yang dipasang installer ini.${N}\n"
    printf " ${GY}• Telegram bot, menu, config, data, backup & cron${N}\n"
    printf " ${GY}• Xray, WS-SSH, stunnel, Dropbear, HAProxy, Nginx, UDPGW${N}\n"
    printf " ${GY}• Service systemd, script, certificate lokal & konfigurasi SC${N}\n"
    printf " ${GY}• Konfigurasi SSH/banner yang dibuat SC dikembalikan bila ada backup${N}\n"
    printf " ${YE}Catatan: tidak menghapus OS atau seluruh paket sistem agar VPS tetap bootable.${N}\n"
    printf "${PU}╰──────────────────────────────────────────────────────────────╯${N}\n\n"
    echo -ne "${PK}◆${N} Ketik ${RE}YES${N} untuk menghapus SC: "
    IFS= read -r c
    [ "$c" != "YES" ] && { echo -e "  ${GY}Dibatalkan${N}"; sleep 1; return; }

    echo -e "\n  ${PU2}Membersihkan SC...${N}"
    local svcs=(vpnbot ws-ssh ws-ssh-alt stunnel4 udpgw xray nginx haproxy dropbear)
    for svc in "${svcs[@]}"; do
        systemctl stop "$svc" >/dev/null 2>&1 || true
        systemctl disable "$svc" >/dev/null 2>&1 || true
    done
    systemctl daemon-reload >/dev/null 2>&1 || true

    rm -f /etc/systemd/system/vpnbot.service

    # Delete only SSH users previously created by this bot, based on its account database.
    if [ -f /root/vpnbot_accounts.json ]; then
        python3 - <<'PYUSERS'
import json, subprocess
try:
    d=json.load(open('/root/vpnbot_accounts.json'))
except Exception:
    d={}
for username, account in d.items():
    if account.get('proto') in ('vmess','vless','trojan'):
        continue
    if not isinstance(username,str) or not username or username == 'root':
        continue
    subprocess.run(['pkill','-9','-u',username],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    subprocess.run(['userdel','-r',username],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
PYUSERS
    fi

    rm -f /etc/systemd/system/ws-ssh.service /etc/systemd/system/ws-ssh-alt.service /etc/systemd/system/dnstt-server.service
    iptables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300 2>/dev/null || true
    iptables -D INPUT -p udp --dport 5300 -j ACCEPT 2>/dev/null || true
    userdel dnstt 2>/dev/null || true
    rm -f /etc/systemd/system/udpgw.service /etc/systemd/system/xray.service
    rm -f /usr/local/bin/ws-ssh.py /usr/bin/badvpn-udpgw /usr/local/bin/dnstt-server /usr/local/bin/xray /usr/bin/xray

    rm -rf /etc/xray /var/lib/xray /etc/dnstt /var/log/xray /etc/stunnel
    rm -f /etc/nginx/sites-enabled/sansxml /etc/nginx/sites-available/sansxml
    rm -f /etc/ssh/sshd_config.d/99-vpnbot.conf
    rm -f /usr/local/bin/sansxml-menu /etc/profile.d/sansxml-menu.sh
    rm -f /root/bot.py /root/bot_compile.log /root/vpnbot.log
    rm -f /root/vpnbot_config.json /root/vpnbot_users.json /root/vpnbot_balance.json
    rm -f /root/vpnbot_accounts.json /root/vpnbot_trial.json /root/vpnbot_trx.json /root/vpnbot_blocked.json
    rm -f /root/vpnbot_backup.sh /etc/sansxml-backup.conf
    rm -rf /root/vpnbot_backup /root/sansxml-bot /root/SANSXML-VPN-BOT /tmp/badvpn
    rm -f /root/.ssh/id_bot /root/.ssh/id_bot.pub

    # Restore SSH/banner files if this installer created backups.
    if [ -d /etc/sansxml-original ]; then
        [ -f /etc/sansxml-original/issue.net ] && cp -f /etc/sansxml-original/issue.net /etc/issue.net
        [ -f /etc/sansxml-original/motd ] && cp -f /etc/sansxml-original/motd /etc/motd
        [ -f /etc/sansxml-original/sshd_config ] && cp -f /etc/sansxml-original/sshd_config /etc/ssh/sshd_config
        rm -rf /etc/sansxml-original
    fi
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true

    # Remove packages that were absent before this installer ran.
    if [ -s /etc/sansxml-packages.list ]; then
        xargs -r apt-get purge -y < /etc/sansxml-packages.list >/dev/null 2>&1 || true
        apt-get autoremove -y >/dev/null 2>&1 || true
    fi
    rm -f /etc/sansxml-packages.list

    clear
    printf "\n  ${GR}✓ SANSXML SC BERHASIL DIHAPUS.${N}\n"
    printf "  ${WH}VPS dikembalikan ke kondisi sebelum installer sejauh file yang dibackup.${N}\n"
    printf "  ${GY}SSH utama tidak dihapus agar koneksi VPS tetap aman.${N}\n\n"
    exit 0
}
while true; do
    show_menu
    read choice
    case "$choice" in
        1|01) stop_bot_clean ;;
        2|02) show_vps_info ;;
        3|03) show_bandwidth ;;
        4|04) show_services ;;
        5|05) run_bot ;;
        6|06) uninstall_sc ;;
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

# 10. OPEN MENU
exec /usr/local/bin/sansxml-menu

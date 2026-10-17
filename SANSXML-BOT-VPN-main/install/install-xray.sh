#!/usr/bin/env bash
set -Eeuo pipefail

[[ $EUID -eq 0 ]] || { echo "Jalankan sebagai root." >&2; exit 1; }
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
DOMAIN_FILE=/root/.domain
XRAY_DIR=/etc/xray
DATA_DIR=/var/lib/sansxml-xray
BIN=/usr/local/bin/xray

if [[ ! -f "$DOMAIN_FILE" || -z "$(tr -d '[:space:]' < "$DOMAIN_FILE")" ]]; then
  read -r -p "Masukkan domain VPS (DNS harus mengarah ke IP VPS): " DOMAIN
  DOMAIN=${DOMAIN,,}
  DOMAIN=${DOMAIN%.}
  [[ "$DOMAIN" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$ ]] || { echo "Domain tidak valid."; exit 1; }
  printf '%s\n' "$DOMAIN" > "$DOMAIN_FILE"
else
  DOMAIN=$(tr -d '[:space:]' < "$DOMAIN_FILE" | tr '[:upper:]' '[:lower:]')
fi
[[ "$DOMAIN" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$ ]] || { echo "Isi /root/.domain bukan nama domain yang valid."; exit 1; }

# One shared domain for the Xray protocols.
SSH_DOMAIN="$DOMAIN"
mkdir -p /etc/xray
printf '%s\n' "$SSH_DOMAIN" > /etc/xray/ssh-domain
chmod 600 /etc/xray/ssh-domain

for port in 9443 9444 9445; do
  if ss -H -lnt 2>/dev/null | awk -v p=":$port" '$4 ~ p"$" {found=1} END{exit !found}'; then
    echo "Port TCP $port sudah digunakan. Tidak ada perubahan dilakukan." >&2
    exit 1
  fi
done

XRAY_ARCHIVE="$SCRIPT_DIR/file/Xray-linux-64.zip"
DOWNLOAD_XRAY=0
if [[ ! -x "$BIN" && ! -s "$XRAY_ARCHIVE" ]]; then
  echo "Paket biner Xray belum ada di ZIP proyek."
  read -r -p "Izinkan mengunduh paket BINER resmi Xray-core dari GitHub? (y/N): " download_xray
  [[ "$download_xray" =~ ^[Yy]$ ]] || {
    echo "Dibatalkan tanpa mengubah layanan VPS. Untuk instalasi offline, letakkan Xray-linux-64.zip di folder file/."
    exit 1
  }
  DOWNLOAD_XRAY=1
fi

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl unzip python3 certbot openssl nginx-full

# Obtain a valid domain certificate. The existing WebSocket service on port 80 is paused briefly.
CERT_DIR="/etc/letsencrypt/live/$DOMAIN"
if [[ ! -s "$CERT_DIR/fullchain.pem" || ! -s "$CERT_DIR/privkey.pem" ]]; then
  DNS_IP=$(getent ahostsv4 "$DOMAIN" 2>/dev/null | awk 'NR==1 {print $1}')
  [[ -n "$DNS_IP" ]] || { echo "DNS domain $DOMAIN belum ter-resolve. Atur A record terlebih dahulu." >&2; exit 1; }
  echo "Domain: $DOMAIN | IP DNS: $DNS_IP"
  echo "Untuk sertifikat, layanan HTTP/WebSocket di port 80 mungkin berhenti sementara."
  read -r -p "Lanjut meminta sertifikat TLS? (y/N): " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Dibatalkan; layanan VPS tidak diubah."; exit 1; }
  read -r -p "Email untuk pemberitahuan sertifikat (boleh kosong): " email
  HTTP_WAS_ACTIVE=0
  if systemctl is-active --quiet http 2>/dev/null; then HTTP_WAS_ACTIVE=1; systemctl stop http; fi
  restore_http() { if [[ "$HTTP_WAS_ACTIVE" -eq 1 ]]; then systemctl start http || true; fi; }
  trap restore_http EXIT
  sleep 1
  if ss -H -lnt 2>/dev/null | awk '$4 ~ /:80$/ {found=1} END{exit !found}'; then
    echo "Port 80 masih dipakai oleh layanan lain; sertifikat tidak bisa diminta." >&2
    exit 1
  fi
  if [[ -n "$email" ]]; then
    certbot certonly --standalone --preferred-challenges http --cert-name "$DOMAIN" -d "$DOMAIN" --non-interactive --agree-tos --email "$email"
  else
    certbot certonly --standalone --preferred-challenges http --cert-name "$DOMAIN" -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email
  fi
  restore_http
  trap - EXIT
fi

[[ -s "$CERT_DIR/fullchain.pem" && -s "$CERT_DIR/privkey.pem" ]] || { echo "Sertifikat TLS tidak tersedia; Xray belum dipasang." >&2; exit 1; }

mkdir -p "$XRAY_DIR" "$DATA_DIR" /usr/local/lib/sansxml-xray /usr/local/share/xray /var/log/sansxml-xray
chmod 700 "$DATA_DIR" "$XRAY_DIR"
if [[ -f "$XRAY_DIR/config.json" ]]; then
  cp -a "$XRAY_DIR/config.json" "$XRAY_DIR/config.json.bak-$(date +%Y%m%d-%H%M%S)"
fi
if [[ -f "$DATA_DIR/accounts.tsv" ]]; then
  cp -a "$DATA_DIR/accounts.tsv" "$DATA_DIR/accounts.tsv.bak-$(date +%Y%m%d-%H%M%S)"
else
  install -m 600 /dev/null "$DATA_DIR/accounts.tsv"
fi
printf '%s\n' "$DOMAIN" > "$XRAY_DIR/domain"
printf '%s\n' "$SSH_DOMAIN" > "$XRAY_DIR/ssh-domain"
chmod 600 "$XRAY_DIR/domain" "$XRAY_DIR/ssh-domain" "$DATA_DIR/accounts.tsv"

if [[ ! -x "$BIN" ]]; then
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
  if [[ -s "$XRAY_ARCHIVE" ]]; then
    cp -f "$XRAY_ARCHIVE" "$TMP/xray-linux-64.zip"
  elif [[ "$DOWNLOAD_XRAY" -eq 1 ]]; then
    echo "Mengunduh paket biner resmi Xray-core setelah persetujuan..."
    curl -fL --retry 3 --connect-timeout 15 \
      "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip" \
      -o "$TMP/xray-linux-64.zip"
  else
    echo "Paket biner Xray tidak tersedia." >&2
    exit 1
  fi
  unzip -oq "$TMP/xray-linux-64.zip" -d "$TMP/unpacked"
  [[ -x "$TMP/unpacked/xray" ]] || { echo "Isi ZIP Xray tidak valid." >&2; exit 1; }
  install -m 755 "$TMP/unpacked/xray" "$BIN"
  [[ ! -f "$TMP/unpacked/geoip.dat" ]] || install -m 644 "$TMP/unpacked/geoip.dat" /usr/local/share/xray/geoip.dat
  [[ ! -f "$TMP/unpacked/geosite.dat" ]] || install -m 644 "$TMP/unpacked/geosite.dat" /usr/local/share/xray/geosite.dat
  rm -rf "$TMP"
  trap - EXIT
fi

install -m 755 "$SCRIPT_DIR/lib/build-xray-config.py" /usr/local/lib/sansxml-xray/build-xray-config.py
install -m 755 "$SCRIPT_DIR/menu/xray-account.sh" /usr/local/bin/xray-account
install -m 755 "$SCRIPT_DIR/menu/menu-xray.sh" /usr/local/bin/menu-xray
install -m 755 "$SCRIPT_DIR/install/renew-xray-cert.sh" /usr/local/sbin/sansxml-cert-renew
install -m 644 "$SCRIPT_DIR/service/xray.service" /etc/systemd/system/xray.service
install -m 644 "$SCRIPT_DIR/service/sansxml-xray-cleanup.service" /etc/systemd/system/sansxml-xray-cleanup.service
install -m 644 "$SCRIPT_DIR/service/sansxml-xray-cleanup.timer" /etc/systemd/system/sansxml-xray-cleanup.timer
install -m 644 "$SCRIPT_DIR/service/sansxml-cert-renew.service" /etc/systemd/system/sansxml-cert-renew.service
install -m 644 "$SCRIPT_DIR/service/sansxml-cert-renew.timer" /etc/systemd/system/sansxml-cert-renew.timer

# Shared-port routing: nginx handles HTTP paths; sslh still handles raw SSH on 443.
# TLS clients without the Xray domain SNI continue to the existing stunnel backend.
mkdir -p /etc/nginx/stream-conf.d /etc/nginx/conf.d
cat > /etc/nginx/conf.d/sansxml-xray.conf <<NGINX_HTTP
server {
    listen 80;
    server_name $DOMAIN;
    client_max_body_size 0;
    location = /ssh { proxy_pass http://127.0.0.1:700; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; }
    location = /vmess { proxy_pass http://127.0.0.1:10001; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; }
    location = /vless { proxy_pass http://127.0.0.1:10002; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; }
    location = /trojan-ws { proxy_pass http://127.0.0.1:10003; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; }
    location / { proxy_pass http://127.0.0.1:700; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; }
}
map \$http_upgrade \$connection_upgrade { default upgrade; '' close; }
server {
    listen 127.0.0.1:8443 ssl;
    server_name $DOMAIN;
    ssl_certificate $CERT_DIR/fullchain.pem;
    ssl_certificate_key $CERT_DIR/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    location = /ssh { proxy_pass http://127.0.0.1:700; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; }
    location = /vmess { proxy_pass http://127.0.0.1:10001; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; }
    location = /vless { proxy_pass http://127.0.0.1:10002; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; }
    location = /trojan-ws { proxy_pass http://127.0.0.1:10003; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; }
    location / { return 404; }
}
NGINX_HTTP
# Ensure the stream module is loaded on Debian if it is packaged as a dynamic module.
if [[ -f /usr/share/nginx/modules-available/mod-stream.conf && ! -e /etc/nginx/modules-enabled/50-mod-stream.conf ]]; then
  ln -s /usr/share/nginx/modules-available/mod-stream.conf /etc/nginx/modules-enabled/50-mod-stream.conf
fi
if ! grep -q 'stream-conf.d/\*.conf' /etc/nginx/nginx.conf; then
  printf '\nstream { include /etc/nginx/stream-conf.d/*.conf; }\n' >> /etc/nginx/nginx.conf
fi
cat > /etc/nginx/stream-conf.d/sansxml-xray.conf <<NGINX_STREAM
map \$ssl_preread_server_name \$sansxml_tls_backend {
    $DOMAIN 127.0.0.1:8443;
    default 127.0.0.1:777;
}
server {
    listen 127.0.0.1:8444;
    proxy_pass \$sansxml_tls_backend;
    ssl_preread on;
}
NGINX_STREAM
# Send only TLS traffic received by sslh to the SNI router; raw SSH dispatch remains intact.
if [[ -f /etc/default/sslh ]]; then
  cp -a /etc/default/sslh "/etc/default/sslh.sansxml-backup-$(date +%Y%m%d-%H%M%S)"
  sed -i 's/--ssl 127\.0\.0\.1:777/--ssl 127.0.0.1:8444/' /etc/default/sslh
fi
# The old custom HTTP listener on :80 is replaced by nginx; its SSH WS handler on :700 remains.
systemctl stop http 2>/dev/null || true
nginx -t

TMP_CFG=$(mktemp "$XRAY_DIR/config.json.new.XXXXXX")
python3 /usr/local/lib/sansxml-xray/build-xray-config.py --domain "$DOMAIN" --database "$DATA_DIR/accounts.tsv" --output "$TMP_CFG"
if ! "$BIN" run -test -config "$TMP_CFG"; then
  rm -f "$TMP_CFG"
  echo "Uji konfigurasi Xray gagal. Berkas aktif belum diganti." >&2
  exit 1
fi
install -m 600 "$TMP_CFG" "$XRAY_DIR/config.json"
rm -f "$TMP_CFG"

systemctl daemon-reload
systemctl enable nginx
systemctl restart nginx
systemctl restart sslh
systemctl enable --now xray
systemctl enable --now sansxml-xray-cleanup.timer
systemctl enable --now sansxml-cert-renew.timer

if ! systemctl is-active --quiet xray; then
  echo "Xray gagal aktif. Log terakhir:"
  journalctl -u xray -n 40 --no-pager || true
  exit 1
fi

cat <<EOF

[SANSXML] Xray aktif.
Domain Xray : $DOMAIN
Domain SSH  : $SSH_DOMAIN (pastikan sertifikat /etc/stunnel/stunnel.pem mencakup domain ini)
VMess  : TCP 443 (TLS/WS) atau 80 (WS), path /vmess
VLESS  : TCP 443 (TLS/WS) atau 80 (WS), path /vless
Trojan : TCP 443 (TLS/WS) atau 80 (WS), path /trojan-ws
SSH raw 443 tetap dirutekan sslh; SNI domain SSH yang berbeda masuk ke backend stunnel lama.
Port 80 fallback diteruskan ke SSH-WS lama pada 127.0.0.1:700.
Pastikan DNS kedua domain menuju IP VPS, firewall mengizinkan TCP 80/443, dan sertifikat /etc/stunnel/stunnel.pem valid untuk domain SSH.

CATATAN: Installer Xray tidak mengganti sertifikat stunnel SSH secara otomatis. Jika sertifikat lama tidak mencakup domain SSH baru, SSH TLS dapat gagal validasi sertifikat; pasang sertifikat yang cocok sebelum memakai hostname SSH baru.
Menu akun: menu utama > VMESS / VLESS / TROJAN.
EOF

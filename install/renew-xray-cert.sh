#!/usr/bin/env bash
set -Eeuo pipefail
DOMAIN=$(cat /etc/xray/domain 2>/dev/null || true)
[[ -n "$DOMAIN" ]] || exit 0
CERT="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
[[ -f "$CERT" ]] || exit 0
if openssl x509 -in "$CERT" -checkend $((25*86400)) -noout >/dev/null 2>&1; then exit 0; fi
# Port 80 is served by nginx; stop it briefly for certbot standalone validation.
WAS_NGINX_ACTIVE=0
if systemctl is-active --quiet nginx; then WAS_NGINX_ACTIVE=1; systemctl stop nginx; fi
restore_nginx() { if [[ "$WAS_NGINX_ACTIVE" -eq 1 ]]; then systemctl start nginx || true; fi; }
trap restore_nginx EXIT
if certbot renew --cert-name "$DOMAIN" --preferred-challenges http --non-interactive; then
  systemctl restart nginx || true
  systemctl restart xray || true
else
  echo "Pembaruan sertifikat gagal; periksa journalctl." >&2
  exit 1
fi

#!/usr/bin/env bash
PROTO="${1:-}"
case "$PROTO" in vmess|vless|trojan) exec /usr/local/bin/xray-account renew "$PROTO" ;; *) echo 'Penggunaan: renew-account.sh vmess|vless|trojan' >&2; exit 2 ;; esac

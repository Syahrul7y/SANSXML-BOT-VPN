#!/usr/bin/env bash
PROTO="${1:-}"
case "$PROTO" in vmess|vless|trojan) exec /usr/local/bin/xray-account delete "$PROTO" ;; *) echo 'Penggunaan: delete-account.sh vmess|vless|trojan' >&2; exit 2 ;; esac

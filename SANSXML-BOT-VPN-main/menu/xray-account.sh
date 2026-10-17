#!/usr/bin/env bash
set -Eeuo pipefail

XRAY_BIN="/usr/local/bin/xray"
XRAY_DIR="/etc/xray"
DB_DIR="/var/lib/sansxml-xray"
DB_FILE="$DB_DIR/accounts.tsv"
BUILDER="/usr/local/lib/sansxml-xray/build-xray-config.py"
DOMAIN_FILE="$XRAY_DIR/domain"
CONFIG="$XRAY_DIR/config.json"
LOCK_FILE="$DB_DIR/.lock"

usage() {
  echo "Penggunaan: xray-account {add|list|delete|renew|cleanup} {vmess|vless|trojan} [normal|trial]"
}

need_root() {
  if [[ $EUID -ne 0 ]]; then echo "Jalankan sebagai root." >&2; exit 1; fi
}

need_install() {
  if [[ ! -x "$XRAY_BIN" || ! -f "$CONFIG" || ! -f "$BUILDER" ]]; then
    echo "Xray belum dipasang. Jalankan install/install-xray.sh dari folder proyek." >&2
    exit 1
  fi
}

valid_proto() { [[ " ${1:-} " == *" ${2:-} "* ]]; }
valid_username() { [[ "$1" =~ ^[A-Za-z0-9_.-]{3,32}$ ]]; }

get_domain() {
  local d
  d=$(cat "$DOMAIN_FILE" 2>/dev/null || true)
  [[ -n "$d" ]] || d=$(cat /root/.domain 2>/dev/null || true)
  [[ -n "$d" ]] || { echo "Domain belum diatur." >&2; return 1; }
  printf '%s\n' "$d"
}

config_from_db() {
  local next_db="$1" next_cfg domain backup_db backup_cfg
  domain=$(get_domain) || return 1
  next_cfg=$(mktemp "$XRAY_DIR/config.json.new.XXXXXX")
  backup_db=$(mktemp "$DB_DIR/accounts.tsv.bak.XXXXXX")
  backup_cfg=$(mktemp "$XRAY_DIR/config.json.bak.XXXXXX")
  cp -a "$DB_FILE" "$backup_db" 2>/dev/null || :
  cp -a "$CONFIG" "$backup_cfg" 2>/dev/null || :

  if ! python3 "$BUILDER" --domain "$domain" --database "$next_db" --output "$next_cfg"; then
    rm -f "$next_cfg" "$backup_db" "$backup_cfg"
    return 1
  fi
  if ! "$XRAY_BIN" run -test -config "$next_cfg"; then
    echo "Konfigurasi Xray gagal diperiksa; perubahan dibatalkan." >&2
    rm -f "$next_cfg" "$backup_db" "$backup_cfg"
    return 1
  fi

  install -m 600 "$next_db" "$DB_FILE"
  install -m 600 "$next_cfg" "$CONFIG"
  if ! systemctl restart xray; then
    echo "Xray gagal restart; mengembalikan konfigurasi sebelumnya." >&2
    install -m 600 "$backup_db" "$DB_FILE" 2>/dev/null || :
    install -m 600 "$backup_cfg" "$CONFIG" 2>/dev/null || :
    systemctl restart xray || true
    rm -f "$next_cfg" "$backup_db" "$backup_cfg"
    return 1
  fi
  rm -f "$next_cfg" "$backup_db" "$backup_cfg"
}

make_link() {
  local proto="$1" user="$2" credential="$3" domain="$4" vmjson encoded
  case "$proto" in
    vmess)
      vmjson=$(python3 - "$user" "$credential" "$domain" <<'PY'
import json,sys
u,c,d=sys.argv[1:]
print(json.dumps({"v":"2","ps":"SANSXML-"+u,"add":d,"port":"443","id":c,"aid":"0","scy":"auto","net":"ws","type":"none","host":d,"path":"/vmess","tls":"tls","sni":d},separators=(",",":")))
PY
)
      encoded=$(printf '%s' "$vmjson" | base64 -w0)
      printf 'vmess://%s\n' "$encoded"
      ;;
    vless)
      printf 'vless://%s@%s:443?encryption=none&security=tls&sni=%s&type=ws&host=%s&path=%%2Fvless#SANSXML-%s\n' "$credential" "$domain" "$domain" "$domain" "$user"
      ;;
    trojan)
      printf 'trojan://%s@%s:443?security=tls&sni=%s&type=ws&host=%s&path=%%2Ftrojan-ws#SANSXML-%s\n' "$credential" "$domain" "$domain" "$domain" "$user"
      ;;
  esac
}

add_account() {
  local proto="$1" mode="${2:-normal}" username duration expiry credential tmp domain
  if [[ "$mode" != normal && "$mode" != trial ]]; then mode=normal; fi
  read -r -p "Username (3-32 karakter, huruf/angka/._-): " username
  if ! valid_username "$username"; then echo "Username tidak valid."; return 1; fi
  if awk -F '\t' -v p="$proto" -v u="$username" '$1==p && $2==u {found=1} END{exit !found}' "$DB_FILE"; then
    echo "Username tersebut sudah ada untuk $proto."; return 1
  fi
  if [[ "$mode" == trial ]]; then
    read -r -p "Masa aktif trial dalam menit (5-1440): " duration
    [[ "$duration" =~ ^[0-9]+$ ]] && (( duration >= 5 && duration <= 1440 )) || { echo "Durasi trial tidak valid."; return 1; }
    expiry=$(( $(date +%s) + duration * 60 ))
  else
    read -r -p "Masa aktif dalam hari (1-365): " duration
    [[ "$duration" =~ ^[0-9]+$ ]] && (( duration >= 1 && duration <= 365 )) || { echo "Durasi tidak valid."; return 1; }
    expiry=$(( $(date +%s) + duration * 86400 ))
  fi

  case "$proto" in
    vmess|vless) credential=$("$XRAY_BIN" uuid) ;;
    trojan) credential=$(openssl rand -hex 16) ;;
  esac
  [[ -n "$credential" ]] || { echo "Gagal membuat kredensial."; return 1; }
  tmp=$(mktemp "$DB_DIR/accounts.tsv.new.XXXXXX")
  cat "$DB_FILE" > "$tmp" 2>/dev/null || :
  printf '%s\t%s\t%s\t%s\n' "$proto" "$username" "$credential" "$expiry" >> "$tmp"
  if config_from_db "$tmp"; then
    domain=$(get_domain)
    echo
    echo "Akun $proto berhasil dibuat."
    echo "Username : $username"
    echo "Masa aktif: $(date -d "@$expiry" '+%Y-%m-%d %H:%M:%S')"
    echo "Server   : $domain"
    echo "Port     : 443 (TLS/WS) | 80 (WS tanpa TLS)"
    echo "Link konfigurasi:"
    make_link "$proto" "$username" "$credential" "$domain"
  else
    echo "Akun tidak dibuat karena konfigurasi Xray gagal diperbarui." >&2
    rm -f "$tmp"
    return 1
  fi
  rm -f "$tmp"
}

list_accounts() {
  local filter="${1:-all}" p u c e now remaining found=0
  now=$(date +%s)
  printf '\n%-8s %-24s %-20s %s\n' PROTOKOL USERNAME KEDALUWARSA STATUS
  printf '%s\n' '--------------------------------------------------------------------------'
  while IFS=$'\t' read -r p u c e; do
    [[ -n "$p" ]] || continue
    [[ "$filter" == all || "$p" == "$filter" ]] || continue
    found=1
    if (( e <= now )); then remaining="KEDALUWARSA"; else remaining="AKTIF"; fi
    printf '%-8s %-24s %-20s %s\n' "$p" "$u" "$(date -d "@$e" '+%Y-%m-%d %H:%M')" "$remaining"
  done < "$DB_FILE"
  [[ "$found" -eq 1 ]] || echo "Belum ada akun."
}

delete_account() {
  local proto="$1" username tmp
  read -r -p "Username yang dihapus: " username
  valid_username "$username" || { echo "Username tidak valid."; return 1; }
  if ! awk -F '\t' -v p="$proto" -v u="$username" '$1==p && $2==u {found=1} END{exit !found}' "$DB_FILE"; then
    echo "Akun tidak ditemukan."; return 1
  fi
  tmp=$(mktemp "$DB_DIR/accounts.tsv.new.XXXXXX")
  awk -F '\t' -v p="$proto" -v u="$username" 'BEGIN{OFS="\t"} !($1==p && $2==u) {print}' "$DB_FILE" > "$tmp"
  if config_from_db "$tmp"; then
    echo "Akun $username ($proto) dihapus."
  else
    echo "Gagal menghapus akun; perubahan dibatalkan." >&2
    rm -f "$tmp"
    return 1
  fi
  rm -f "$tmp"
}

renew_account() {
  local proto="$1" username days now found tmp
  read -r -p "Username yang diperpanjang: " username
  valid_username "$username" || { echo "Username tidak valid."; return 1; }
  read -r -p "Tambahan masa aktif (hari, 1-365): " days
  [[ "$days" =~ ^[0-9]+$ ]] && (( days >= 1 && days <= 365 )) || { echo "Durasi tidak valid."; return 1; }
  awk -F '\t' -v p="$proto" -v u="$username" '$1==p && $2==u {found=1} END{exit !found}' "$DB_FILE" || { echo "Akun tidak ditemukan."; return 1; }
  now=$(date +%s)
  tmp=$(mktemp "$DB_DIR/accounts.tsv.new.XXXXXX")
  awk -F '\t' -v p="$proto" -v u="$username" -v n="$now" -v d="$days" 'BEGIN{OFS="\t"} $1==p && $2==u {$4=($4>n?$4:n)+d*86400} {print}' "$DB_FILE" > "$tmp"
  if config_from_db "$tmp"; then
    local new_expiry
    new_expiry=$(awk -F '\t' -v p="$proto" -v u="$username" '$1==p && $2==u {print $4}' "$DB_FILE")
    [[ -n "$new_expiry" ]] && echo "Masa aktif baru: $(date -d "@$new_expiry" '+%Y-%m-%d %H:%M:%S')"
  else
    echo "Gagal memperpanjang akun; perubahan dibatalkan." >&2
    rm -f "$tmp"
    return 1
  fi
  rm -f "$tmp"
}

cleanup_expired() {
  local now tmp before after
  now=$(date +%s)
  tmp=$(mktemp "$DB_DIR/accounts.tsv.new.XXXXXX")
  awk -F '\t' -v n="$now" '$4 > n' "$DB_FILE" > "$tmp"
  before=$(wc -l < "$DB_FILE" 2>/dev/null || echo 0)
  after=$(wc -l < "$tmp")
  if (( after < before )); then
    if config_from_db "$tmp"; then
      echo "Pembersihan selesai: $((before-after)) akun kedaluwarsa dihapus."
    else
      echo "Pembersihan gagal; database lama dipertahankan." >&2
      rm -f "$tmp"
      return 1
    fi
  fi
  rm -f "$tmp"
}

need_root
mkdir -p "$DB_DIR"
touch "$DB_FILE"
chmod 700 "$DB_DIR"
chmod 600 "$DB_FILE"
exec 9>"$LOCK_FILE"
flock -x 9

ACTION="${1:-}"
PROTO="${2:-all}"
case "$ACTION" in
  cleanup)
    need_install
    cleanup_expired
    ;;
  *)
    need_install
    if [[ "$ACTION" != list ]] && ! valid_proto "vmess vless trojan" "$PROTO"; then usage; exit 2; fi
    case "$ACTION" in
      add) add_account "$PROTO" "${3:-normal}" ;;
      list) list_accounts "$PROTO" ;;
      delete) delete_account "$PROTO" ;;
      renew) renew_account "$PROTO" ;;
      *) usage; exit 2 ;;
    esac
    ;;
esac

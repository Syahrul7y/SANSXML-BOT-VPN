#!/bin/bash
# Hapus akun trial SSH yang sudah melewati masa aktif.
DIR=/etc/ssh-trial-expiry
[ -d "$DIR" ] || exit 0
now=$(date +%s)
for f in "$DIR"/*; do
  [ -f "$f" ] || continue
  user=${f##*/}
  expiry=$(cat "$f" 2>/dev/null)
  [[ "$expiry" =~ ^[0-9]+$ ]] || { rm -f "$f"; continue; }
  if [ "$now" -ge "$expiry" ]; then
    if getent passwd "$user" >/dev/null 2>&1; then
      pkill -u "$user" 2>/dev/null || true
      userdel -r "$user" >/dev/null 2>&1 || true
    fi
    rm -f "/etc/iplimit-user/$user" "$f"
  fi
done

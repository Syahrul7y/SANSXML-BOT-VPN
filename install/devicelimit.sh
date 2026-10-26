#!/usr/bin/bash
apt update -y
apt install -y procps

mkdir -p /etc/iplimit-user
touch /var/log/devicelimit.log

cat > /usr/local/bin/devicelimit << 'EOF'
#!/usr/bin/bash
LOG=/var/log/devicelimit.log
touch "$LOG"

while true; do
    for user in $(awk -F: '$3 >= 1000 && $3 < 60000 {print $1}' /etc/passwd); do
        MAX=1
        [ -f "/etc/iplimit-user/$user" ] && MAX=$(cat "/etc/iplimit-user/$user" 2>/dev/null)
        [ -z "$MAX" ] && MAX=1

        pids=$(who -u 2>/dev/null | awk -v u="$user" '$1 == u {print $6}' | grep -E '^[0-9]+$' | sort -n)
        count=$(echo "$pids" | grep -c .)

        if [ "$count" -gt "$MAX" ]; then
            echo "$pids" | tail -n +$((MAX+1)) | while read -r pid; do
                [ -z "$pid" ] && continue
                kill -9 "$pid" 2>/dev/null && \
                    echo "$(date '+%F %T') KICK user=$user pid=$pid" >> "$LOG"
            done
        fi
    done
    sleep 10
done
EOF

chmod +x /usr/local/bin/devicelimit

cat > /etc/systemd/system/devicelimit.service << 'EOF'
[Unit]
Description=SSH Session Limit
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/devicelimit
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable devicelimit
systemctl restart devicelimit

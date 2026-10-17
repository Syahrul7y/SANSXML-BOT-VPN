#!/usr/bin/bash
apt update -y
apt install -y cmake g++ make git

cd /root
git clone https://github.com/ambrop72/badvpn.git
cd badvpn && mkdir build && cd build
cmake .. -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1
make
cp udpgw/badvpn-udpgw /usr/local/bin/
chmod +x /usr/local/bin/badvpn-udpgw

cat > /etc/systemd/system/udpgw.service << 'EOF'
[Unit]
Description=BadVPN UDP Gateway
After=network.target
[Service]
ExecStart=/usr/local/bin/badvpn-udpgw --listen-addr 127.0.0.1:7300 --max-clients 1000
Restart=always
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable udpgw
systemctl start udpgw

cd /root && rm -rf badvpn

systemctl status udpgw --no-pager

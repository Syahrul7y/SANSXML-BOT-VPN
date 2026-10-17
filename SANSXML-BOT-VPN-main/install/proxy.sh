#!/usr/bin/bash

apt update
apt install wget curl openssl -y

apt install dropbear -y
cd /etc/default
echo "/bin/false" >> /etc/shells
echo "/usr/sbin/nologin" >> /etc/shells
cat> /etc/issue.net << END
<br>
<font color="blue"><b>===============================</br></font><br>
<font color="red"><b>********  SANSXML VPN  ********</b></font><br>
<font color="blue"><b>===============================</br></font><br>
END
wget -O dropbear "https://github.com/Syahrul7y/SANSXML-BOT-VPN/raw/refs/heads/main/file/dropbear.conf"
chmod 755 dropbear

systemctl daemon-reload
/etc/init.d/dropbear restart

bash <(curl -Lks https://raw.githubusercontent.com/melon9912/ssh-only/refs/heads/main/dropbear.sh)
systemctl restart dropbear

# SSH WS
cd /usr/local/bin
wget -O ssh-ws "https://github.com/Syahrul7y/SANSXML-BOT-VPN/raw/refs/heads/main/file/ssh-ws.x86"
chmod +x ssh-ws

cd /etc/systemd/system
wget -O ssh-ws.service "https://github.com/Syahrul7y/SANSXML-BOT-VPN/raw/refs/heads/main/service/ssh-ws.service"
systemctl daemon-reload
systemctl start ssh-ws
systemctl enable ssh-ws

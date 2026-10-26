# Stunnel 
echo "sslh sslh/run_daemon select standalone" | sudo debconf-set-selections
sudo apt install -y sslh
apt update
apt install openssl -y
#apt install sslh -y
apt install stunnel4 -y
apt install stunnel -y

apt --purge remove apache2
apt autoremove -y

clear

# Generate Stunnel Port
mkdir -p /etc/stunnel
wget -O /etc/default/stunnel4 "https://github.com/Syahrul7y/SANSXML-BOT-VPN/raw/refs/heads/main/file/stunnel.txt"

cd /etc/stunnel
openssl req -x509 -newkey rsa:2048 -nodes \
-keyout stunnel.pem \
-out stunnel.pem \
-days 365 \
-subj "/C=ID/ST=Random/L=Random/O=AutoGen/OU=Auto/CN=localhost"
chmod 600 stunnel.pem

# Run server stunnel
wget -O stunnel.conf "https://github.com/Syahrul7y/SANSXML-BOT-VPN/raw/refs/heads/main/file/stunnel.conf"
chmod 755 stunnel.conf

# SSLH
cd /etc/default
wget -O sslh "https://github.com/Syahrul7y/SANSXML-BOT-VPN/raw/refs/heads/main/file/sslh.conf"
chmod 755 sslh

# Start
systemctl daemon-reload
systemctl stop sslh stunnel4
systemctl disable sslh stunnel4
systemctl daemon-reload
systemctl start sslh stunnel4
systemctl enable sslh stunnel4

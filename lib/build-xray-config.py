#!/usr/bin/env python3
"""Build an Xray config from the private SANSXML account database."""
import argparse
import json
import os
import re
import sys
import time
from pathlib import Path

PROTOCOLS = {"vmess", "vless", "trojan"}
USERNAME_RE = re.compile(r"^[A-Za-z0-9_.-]{3,32}$")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--domain", required=True)
    parser.add_argument("--database", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--cert-dir", default="/etc/letsencrypt/live")
    args = parser.parse_args()

    domain = args.domain.strip().lower().rstrip(".")
    if not re.fullmatch(r"(?=.{1,253}$)([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}", domain):
        print("Domain tidak valid.", file=sys.stderr)
        return 2

    cert = str(Path(args.cert_dir) / domain / "fullchain.pem")
    key = str(Path(args.cert_dir) / domain / "privkey.pem")
    if not (os.path.isfile(cert) and os.path.isfile(key)):
        print(f"Sertifikat TLS tidak ditemukan: {cert} dan/atau {key}", file=sys.stderr)
        return 2

    clients = {"vmess": [], "vless": [], "trojan": []}
    db = Path(args.database)
    if db.exists():
        for number, raw in enumerate(db.read_text(encoding="utf-8").splitlines(), 1):
            if not raw.strip():
                continue
            fields = raw.split("\t")
            if len(fields) != 4:
                print(f"Baris database {number} tidak valid.", file=sys.stderr)
                return 2
            proto, username, credential, expiry = fields
            if proto not in PROTOCOLS or not USERNAME_RE.fullmatch(username) or not credential:
                print(f"Data akun pada baris {number} tidak valid.", file=sys.stderr)
                return 2
            try:
                expiry_epoch = int(expiry)
            except ValueError:
                print(f"Waktu kedaluwarsa pada baris {number} tidak valid.", file=sys.stderr)
                return 2
            if expiry_epoch <= int(time.time()):
                continue
            email = f"{proto}-{username}@sansxml.local"
            if proto == "vmess":
                clients[proto].append({"id": credential, "alterId": 0, "security": "auto", "email": email})
            elif proto == "vless":
                clients[proto].append({"id": credential, "email": email})
            else:
                clients[proto].append({"password": credential, "email": email})

    tls_settings = {"certificates": [{"certificateFile": cert, "keyFile": key}]}
    config = {
        "log": {
            "loglevel": "warning",
            "access": "/var/log/sansxml-xray/access.log",
            "error": "/var/log/sansxml-xray/error.log",
        },
        "inbounds": [
            {
                "tag": "vmess-ws-tls",
                "listen": "127.0.0.1",
                "port": 10001,
                "protocol": "vmess",
                "settings": {"clients": clients["vmess"], "disableInsecureEncryption": True},
                "streamSettings": {
                    "network": "ws",
                    "security": "none",
                    "wsSettings": {"path": "/vmess", "headers": {"Host": domain}},
                },
                "sniffing": {"enabled": False},
            },
            {
                "tag": "vless-ws-tls",
                "listen": "127.0.0.1",
                "port": 10002,
                "protocol": "vless",
                "settings": {"clients": clients["vless"], "decryption": "none"},
                "streamSettings": {
                    "network": "ws",
                    "security": "none",
                    "wsSettings": {"path": "/vless", "headers": {"Host": domain}},
                },
                "sniffing": {"enabled": False},
            },
            {
                "tag": "trojan-tls",
                "listen": "127.0.0.1",
                "port": 10003,
                "protocol": "trojan",
                "settings": {"clients": clients["trojan"]},
                "streamSettings": {
                    "network": "ws",
                    "security": "none",
                    "wsSettings": {"path": "/trojan-ws", "headers": {"Host": domain}},
                },
                "sniffing": {"enabled": False},
            },
        ],
        "outbounds": [
            {"tag": "direct", "protocol": "freedom", "settings": {}},
            {"tag": "block", "protocol": "blackhole", "settings": {}},
        ],
    }

    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(config, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    os.chmod(out, 0o600)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

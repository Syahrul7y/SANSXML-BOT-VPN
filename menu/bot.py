#!/usr/bin/env python3
import subprocess
import sys
import telebot
from telebot import types

try:
    config = {}
    with open('/etc/bot-telegram.conf') as f:
        for line in f:
            if '=' in line:
                k, v = line.strip().split('=', 1)
                config[k] = v

    TOKEN = config.get('TOKEN', '').strip()
    ADMIN = config.get('ADMIN', '').strip()

    if not TOKEN:
        print("ERROR: TOKEN kosong")
        sys.exit(1)

    bot = telebot.TeleBot(TOKEN)

    def is_admin(message):
        return str(message.chat.id) == ADMIN

    def dashboard():
        total = subprocess.run(
            "awk -F: '$3 >= 1000 && $3 < 60000 {print $1}' /etc/passwd | wc -l",
            shell=True, capture_output=True, text=True
        ).stdout.strip() or "0"

        online = subprocess.run(
            "who -u 2>/dev/null | wc -l",
            shell=True, capture_output=True, text=True
        ).stdout.strip() or "0"

        ram = subprocess.run(
            "free -m | awk '/Mem:/ {print $3\"/\"$2\"MB\"}'",
            shell=True, capture_output=True, text=True
        ).stdout.strip() or "0"

        cpu = subprocess.run(
            "top -bn1 | grep 'Cpu(s)' | awk '{print int($2+$4)}'",
            shell=True, capture_output=True, text=True
        ).stdout.strip() or "0"

        uptime = subprocess.run(
            "uptime -p | sed 's/up //'",
            shell=True, capture_output=True, text=True
        ).stdout.strip() or "0"

        return (
            "SANSXML BOT DASHBOARD\n"
            "────────────────────────\n"
            f"Total Akun  : {total}\n"
            f"Online      : {online}\n"
            f"RAM         : {ram}\n"
            f"CPU Load    : {cpu}%\n"
            f"Uptime      : {uptime}\n"
            "────────────────────────"
        )

    def main_menu():
        kb = types.InlineKeyboardMarkup(row_width=2)
        kb.add(
            types.InlineKeyboardButton("Create Account", callback_data="create"),
            types.InlineKeyboardButton("Delete Account", callback_data="delete"),
        )
        kb.add(
            types.InlineKeyboardButton("List User", callback_data="list"),
            types.InlineKeyboardButton("Server Status", callback_data="status"),
        )
        kb.add(
            types.InlineKeyboardButton("Refresh", callback_data="refresh"),
        )
        return kb

    def back_menu():
        kb = types.InlineKeyboardMarkup()
        kb.add(types.InlineKeyboardButton("Kembali", callback_data="back"))
        return kb

    @bot.message_handler(commands=['start', 'menu'])
    def start(message):
        if not is_admin(message):
            bot.reply_to(message, "Anda bukan admin")
            return
        bot.send_message(message.chat.id, dashboard(), reply_markup=main_menu())

    @bot.callback_query_handler(func=lambda call: True)
    def callback(call):
        if str(call.message.chat.id) != ADMIN:
            bot.answer_callback_query(call.id, "Akses ditolak")
            return

        bot.answer_callback_query(call.id)

        if call.data == "back" or call.data == "refresh":
            bot.edit_message_text(
                dashboard(),
                call.message.chat.id,
                call.message.message_id,
                reply_markup=main_menu()
            )

        elif call.data == "list":
            result = subprocess.run(
                "awk -F: '$3 >= 1000 && $3 < 60000 {print $1}' /etc/passwd",
                shell=True, capture_output=True, text=True
            )
            users = result.stdout.strip() or "(Kosong)"
            bot.edit_message_text(
                f"List Akun:\n\n{users}",
                call.message.chat.id,
                call.message.message_id,
                reply_markup=back_menu()
            )

        elif call.data == "status":
            status = subprocess.run(
                "for s in ssh-ws udpgw stunnel4 dropbear; do "
                "printf '%s: %s\\n' \"$s\" \"$(systemctl is-active $s 2>/dev/null)\"; "
                "done",
                shell=True, capture_output=True, text=True
            ).stdout.strip() or "N/A"
            bot.edit_message_text(
                f"Status Service:\n\n{status}",
                call.message.chat.id,
                call.message.message_id,
                reply_markup=back_menu()
            )

        elif call.data == "create":
            msg = bot.send_message(
                call.message.chat.id,
                "Format: username password days\n"
                "Contoh: budi 1234 30\n\n"
                "Kirim data akun:"
            )
            bot.register_next_step_handler(msg, process_create)

        elif call.data == "delete":
            msg = bot.send_message(
                call.message.chat.id,
                "Kirim username yang mau dihapus:"
            )
            bot.register_next_step_handler(msg, process_delete)

    def process_create(message):
        if not is_admin(message):
            return
        try:
            parts = message.text.split()
            if len(parts) != 3:
                bot.reply_to(message, "Format salah. Ketik: username password days")
                return

            user, pwd, days = parts
            subprocess.run(f"useradd -e $(date -d '{days} days' +%Y-%m-%d) -s /bin/false -M {user}",
                           shell=True, capture_output=True)
            subprocess.run(f"echo -e '{pwd}\\n{pwd}' | passwd {user}",
                           shell=True, capture_output=True)

            exp = subprocess.run(
                f"chage -l {user} | grep 'Account expires' | awk -F': ' '{{print $2}}'",
                shell=True, capture_output=True, text=True
            ).stdout.strip()

            domain = subprocess.run(
                "cat /root/.domain 2>/dev/null",
                shell=True, capture_output=True, text=True
            ).stdout.strip() or "(Belum di-set)"

            bot.send_message(
                message.chat.id,
                f"Akun berhasil dibuat\n\n"
                f"Username : {user}\n"
                f"Password : {pwd}\n"
                f"Domain   : {domain}\n"
                f"Port TLS : 443\n"
                f"Port WS  : 80\n"
                f"BadVPN   : 7300\n"
                f"Expired  : {exp}"
            )
        except Exception as e:
            bot.reply_to(message, f"Error: {e}")

    def process_delete(message):
        if not is_admin(message):
            return
        try:
            user = message.text.strip()
            check = subprocess.run(
                f"id {user}",
                shell=True, capture_output=True, text=True
            )
            if check.returncode != 0:
                bot.reply_to(message, f"User {user} tidak ditemukan")
                return

            subprocess.run(f"pkill -u {user}", shell=True, capture_output=True)
            subprocess.run(f"userdel -r {user}", shell=True, capture_output=True)
            subprocess.run(f"rm -f /etc/iplimit-user/{user}", shell=True, capture_output=True)

            bot.send_message(message.chat.id, f"User {user} berhasil dihapus")
        except Exception as e:
            bot.reply_to(message, f"Error: {e}")

    print("Bot berjalan...")
    bot.polling(none_stop=True)

except Exception as e:
    print(f"ERROR: {e}")
    sys.exit(1)

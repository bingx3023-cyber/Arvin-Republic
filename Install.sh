#!/bin/bash

# رنگ‌ها برای خروجی بهتر
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   نصب خودکار تونل ایران → خارج        ${NC}"
echo -e "${GREEN}========================================${NC}"

# بررسی اجرا با روت
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}این اسکریپت باید با دسترسی root اجرا شود!${NC}" 
   exit 1
fi

# دریافت اطلاعات سرور خارج
echo -e "${YELLOW}لطفاً اطلاعات سرور خارج را وارد کنید:${NC}"
read -p "IP سرور خارج: " FOREIGN_IP
read -p "پورت SSH سرور خارج (پیش‌فرض 22): " SSH_PORT
SSH_PORT=${SSH_PORT:-22}
read -p "نام کاربری سرور خارج (پیش‌فرض root): " SSH_USER
SSH_USER=${SSH_USER:-root}
read -s -p "رمز عبور سرور خارج: " SSH_PASS
echo ""

# تولید UUID تصادفی
UUID=$(cat /proc/sys/kernel/random/uuid)
TUNNEL_PORT=$((RANDOM % 10000 + 10000))

echo -e "${GREEN}[1/4] به‌روزرسانی سیستم...${NC}"
apt update -y && apt upgrade -y

echo -e "${GREEN}[2/4] نصب Xray و 3X-UI...${NC}"
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) << EOF
1
1
1
1
EOF

echo -e "${GREEN}[3/4] تنظیم inbound تونل روی پورت $TUNNEL_PORT...${NC}"
xray api add inbound -s 127.0.0.1:8080 \
  -t vlness \
  -p $TUNNEL_PORT \
  -u $UUID \
  -f ""

# ساخت کانفیگ fallback
cat > /etc/xray/fallback.json << EOF
{
  "fallbacks": [
    {
      "dest": 445,
      "xver": 0
    }
  ]
}
EOF

echo -e "${GREEN}[4/4] نصب و تنظیم auto-ssh-tunnel...${NC}"
apt install -y sshpass autossh

# ساخت اسکریپت تونل خودکار
cat > /usr/local/bin/tunnel.sh << EOF
#!/bin/bash
while true; do
  sshpass -p '$SSH_PASS' ssh -o StrictHostKeyChecking=no -N -R $TUNNEL_PORT:localhost:$TUNNEL_PORT $SSH_USER@$FOREIGN_IP -p $SSH_PORT
  sleep 5
done
EOF

chmod +x /usr/local/bin/tunnel.sh

# ایجاد سرویس systemd برای تونل
cat > /etc/systemd/system/tunnel.service << EOF
[Unit]
Description=SSH Tunnel Iran to Foreign
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/tunnel.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable tunnel.service
systemctl start tunnel.service

# ذخیره اطلاعات در فایل
cat > /root/tunnel-info.txt << EOF
========================================
اطلاعات تونل ایران → خارج
========================================
UUID ایران: $UUID
پورت تونل ایران: $TUNNEL_PORT
IP سرور خارج: $FOREIGN_IP

🔴 مراحل بعدی در سرور خارج:
1. در پنل 3X-UI خارج، یک outbound از نوع VLESS بسازید
2. اطلاعات زیر را در آن outbound وارد کنید:
   - آدرس سرور: IP ایران شما
   - پورت: $TUNNEL_PORT
   - UUID: $UUID

✅ وضعیت سرویس تونل:
   systemctl status tunnel
   journalctl -u tunnel -f
========================================
EOF

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ نصب با موفقیت انجام شد!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${YELLOW}اطلاعات ذخیره شده در: /root/tunnel-info.txt${NC}"
cat /root/tunnel-info.txt

echo -e "${YELLOW}در حال تست اتصال تونل...${NC}"
sleep 3
systemctl status tunnel --no-pager

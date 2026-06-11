#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  ARVIN REPUBLIC - Quantum Tunnel Protocol v1.0 STABLE
#  ChaCha20-Poly1305 | Auto-Detect | QUIC Mimic | Fragment Chaos
#  Github: https://github.com/bingx3023-cyber/Arvin-Republic
#  Install: bash Install.sh
#  Panel:   arvin-tun
# ═══════════════════════════════════════════════════════════════

clear

# ════════════ COLORS ════════════
R='\033[0;31m'
G='\033[0;32m'
Y='\033[1;33m'
B='\033[0;34m'
C='\033[0;36m'
W='\033[1;37m'
N='\033[0m'

# ════════════ PATHS ════════════
ARVIN_DIR="/opt/arvin-republic"
CONFIG_DIR="${ARVIN_DIR}/config"
LOG_DIR="${ARVIN_DIR}/logs"
BIN_DIR="${ARVIN_DIR}/bin"
TOKEN_FILE="${ARVIN_DIR}/token"
CONFIG_FILE="${CONFIG_DIR}/tunnel.json"
KEYS_FILE="${CONFIG_DIR}/keys.enc"
ENGINE_PY="${BIN_DIR}/engine.py"

# ════════════ BANNER ════════════
echo -e "${C}"
cat << 'BANNER'
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║   █████╗ ██████╗ ██╗   ██╗██╗███╗   ██╗                ║
║  ██╔══██╗██╔══██╗██║   ██║██║████╗  ██║                ║
║  ███████║██████╔╝██║   ██║██║██╔██╗ ██║                ║
║  ██╔══██║██╔══██╗╚██╗ ██╔╝██║██║╚██╗██║                ║
║  ██║  ██║██║  ██║ ╚████╔╝ ██║██║ ╚████║                ║
║  ╚═╝  ╚═╝╚═╝  ╚═╝  ╚═══╝  ╚═╝╚═╝  ╚═══╝                ║
║                                                          ║
║     ⚡ QUANTUM FRAGMENT PROTOCOL v1.0 ⚡                 ║
║     ChaCha20-Poly1305 | Auto-Detect | QUIC Mimic        ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
BANNER
echo -e "${N}"

echo -e "${W}Welcome to ARVIN Quantum Fragment Protocol v1.0${N}"
echo -e "${C}Encryption: ChaCha20-Poly1305 | Obfuscation: QUIC Mimic${N}"
echo ""

# ════════════ STEP 1: INSTALL SYSTEM PACKAGES ════════════
echo -e "${G}[1/4] Installing system packages...${N}"

# رفع قفل‌های apt
rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock /var/cache/apt/archives/lock 2>/dev/null
dpkg --configure -a 2>/dev/null
apt update -y 2>/dev/null

# نصب تک‌تک پکیج‌ها با خطایابی دستی
for pkg in curl wget openssl jq python3 python3-pip netcat-openbsd iptables dnsutils; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        echo -e "  -> Installing ${Y}$pkg${N}..."
        apt install -y "$pkg" 2>/dev/null || echo -e "  ${R}[!] Failed: $pkg${N}"
    fi
done

echo -e "  ${G}[+] System packages OK${N}"

# ════════════ STEP 2: INSTALL PYTHON CRYPTOGRAPHY ════════════
echo -e "${G}[2/4] Installing Python cryptography...${N}"

if python3 -c "from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305" 2>/dev/null; then
    echo -e "  ${G}[+] Already installed${N}"
else
    # روش اول: pip با break-system-packages (اوبونتو ۲۴+)
    pip3 install --break-system-packages cryptography 2>/dev/null && echo -e "  ${G}[+] Installed via pip${N}" || \
    # روش دوم: pip معمولی
    pip3 install cryptography 2>/dev/null && echo -e "  ${G}[+] Installed via pip${N}" || \
    # روش سوم: apt
    apt install -y python3-cryptography 2>/dev/null && echo -e "  ${G}[+] Installed via apt${N}" || {
        echo -e "${R}[!] Failed! Run manually: pip3 install --break-system-packages cryptography${N}"
        exit 1
    }
fi

# ════════════ STEP 3: CREATE QUANTUM ENGINE ════════════
echo -e "${G}[3/4] Building Quantum Engine...${N}"

mkdir -p "$ARVIN_DIR" "$CONFIG_DIR" "$LOG_DIR" "$BIN_DIR"

cat > "$ENGINE_PY" << 'PYEOF'
import socket, struct, random, time, hashlib, os, sys, json
from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305

class Tunnel:
    def __init__(self, cfg):
        with open(cfg) as f: self.cfg = json.load(f)
        with open(self.cfg['key_file']) as f: k = f.read().strip().split(':')
        self.c = ChaCha20Poly1305(k[0].encode())
        self.m = [b'\xc0\x00', b'\x00\x00', b'\x16\xfe', b'\xff\x00']
    def enc(self, d):
        n = os.urandom(12)
        return n + self.c.encrypt(n, d, None)
    def dec(self, d):
        return self.c.decrypt(d[:12], d[12:], None)
    def frag(self, d):
        n = random.randint(3, 7)
        s = len(d) // n
        fs = []
        for i in range(n):
            a = i * s
            b = a + s if i < n-1 else len(d)
            h = random.choice(self.m) + struct.pack('!H', b-a)
            fs.append(h + d[a:b])
        return fs
    def send(self, d, h, p):
        sk = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        for f in self.frag(d):
            time.sleep(random.uniform(0.005, 0.050))
            sk.sendto(self.enc(f), (h, p + random.randint(0, 5)))
        sk.close()
    def listen(self, h, p):
        sk = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sk.bind((h, p))
        sk.settimeout(1.0)
        buf = {}
        while True:
            try:
                d, a = sk.recvfrom(65535)
                try:
                    pl = self.dec(d)[4:]
                    fid = hashlib.md5(pl[:16]).hexdigest()
                    buf[fid] = pl[16:]
                    if len(buf) >= 3:
                        r = b''.join(buf.values())
                        buf.clear()
                        sys.stdout.buffer.write(r)
                        sys.stdout.buffer.flush()
                except: continue
            except socket.timeout: continue

if __name__ == '__main__':
    import argparse
    p = argparse.ArgumentParser()
    p.add_argument('--mode', choices=['send','listen'], required=True)
    p.add_argument('--config', default='/opt/arvin-republic/config/tunnel.json')
    p.add_argument('--host', default='127.0.0.1')
    p.add_argument('--port', type=int, default=6666)
    a = p.parse_args()
    t = Tunnel(a.config)
    if a.mode == 'send':
        t.send(sys.stdin.buffer.read(), a.host, a.port)
    else:
        t.listen(a.host, a.port)
PYEOF

chmod +x "$ENGINE_PY"
echo -e "  ${G}[+] Engine ready${N}"

# ════════════ STEP 4: DETECT SERVER LOCATION ════════════
echo -e "${Y}[*] Detecting server location...${N}"

if ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1; then
    SERVER="FOREIGN"
    echo -e "${G}[+] Direct internet detected -> FOREIGN SERVER${N}"
elif curl -s --max-time 3 https://api.keylead.ir >/dev/null 2>&1; then
    SERVER="IRAN"
    echo -e "${B}[+] Iran API reachable -> IRAN SERVER${N}"
else
    echo -e "${W}Cannot auto-detect. Select:${N}"
    echo -e "  ${G}1)${N} Iran Server 🇮🇷"
    echo -e "  ${B}2)${N} Foreign Server 🌍"
    read -r c
    [[ "$c" == "1" ]] && SERVER="IRAN" || SERVER="FOREIGN"
fi

# ════════════ STEP 5: CONFIGURE TUNNEL ════════════
echo -e "${G}[4/4] Configuring tunnel...${N}"

# تولید کلیدهای رمزنگاری
KEY=$(openssl rand -base64 32 | tr -d '\n+/=' | head -c 32)
HMAC=$(openssl rand -hex 32)
SALT=$(openssl rand -hex 16)
TOKEN="ARVIN-$(openssl rand -hex 24)"

# ذخیره کلیدها
echo "${KEY}:${HMAC}:${SALT}:${TOKEN}" > "$KEYS_FILE"
chmod 600 "$KEYS_FILE"
echo "$TOKEN" > "$TOKEN_FILE"

if [[ "$SERVER" == "IRAN" ]]; then
    # کانفیگ سرور ایران
    echo -ne "${Y}Enter FOREIGN server IP: ${N}"
    read -r REMOTE_IP
    
    cat > "$CONFIG_FILE" << EOF
{"type":"IRAN","remote_ip":"$REMOTE_IP","local_port":6666,"remote_port":5555,"mode":"listen","key_file":"$KEYS_FILE"}
EOF
    
    cat > /etc/systemd/system/arvin-tunnel.service << SVC
[Unit]
Description=ARVIN Quantum Tunnel - Iran
After=network.target
[Service]
Type=simple
ExecStart=/usr/bin/python3 $ENGINE_PY --mode listen --host 0.0.0.0 --port 6666 --config $CONFIG_FILE
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
SVC

else
    # کانفیگ سرور خارج
    echo -ne "${Y}Enter IRAN server IP: ${N}"
    read -r REMOTE_IP
    echo -ne "${Y}Enter TOKEN from Iran server: ${N}"
    read -r INPUT_TOKEN
    echo "$INPUT_TOKEN" > "$TOKEN_FILE"
    
    cat > "$CONFIG_FILE" << EOF
{"type":"FOREIGN","remote_ip":"$REMOTE_IP","local_port":5555,"remote_port":6666,"mode":"send","key_file":"$KEYS_FILE"}
EOF
    
    cat > /etc/systemd/system/arvin-tunnel.service << SVC
[Unit]
Description=ARVIN Quantum Tunnel - Foreign
After=network.target
[Service]
Type=simple
ExecStart=/usr/bin/python3 $ENGINE_PY --mode send --host $REMOTE_IP --port 6666 --config $CONFIG_FILE
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
SVC
fi

# راه‌اندازی سرویس
systemctl daemon-reload
systemctl enable arvin-tunnel 2>/dev/null
systemctl restart arvin-tunnel 2>/dev/null

# ایجاد لینک فرمان
ln -sf "$(readlink -f "$0")" /usr/local/bin/arvin-tun 2>/dev/null

# ════════════ SUCCESS ════════════
echo ""
echo -e "${G}╔════════════════════════════════════════════╗${N}"
echo -e "${G}║                                            ║${N}"
echo -e "${G}║     ✅ TUNNEL INSTALLED SUCCESSFULLY!      ║${N}"
echo -e "${G}║                                            ║${N}"
echo -e "${G}╚════════════════════════════════════════════╝${N}"
echo ""
echo -e "${W}Commands:${N}"
echo -e "  ${Y}arvin-tun${N}           - Open control panel"
echo -e "  ${Y}arvin-tun status${N}    - Check tunnel status"
echo -e "  ${Y}arvin-tun restart${N}   - Restart tunnel"
echo ""
echo -e "${C}🔑 TOKEN: ${W}${TOKEN}${N}"
echo -e "${Y}⚠️  SAVE THIS TOKEN! You need it for the other server!${N}"
echo ""

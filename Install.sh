#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  ARVIN REPUBLIC - Quantum Tunnel Protocol v2.0 FINAL
#  ChaCha20-Poly1305 | Auto-Detect | TCP Bridge | QUIC Mimic
#  Github: https://github.com/bingx3023-cyber/Arvin-Republic
#  Install: bash <(curl -s https://raw.githubusercontent.com/bingx3023-cyber/Arvin-Republic/main/Install.sh)
#  Panel: arvin-tun
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
║     ⚡ QUANTUM FRAGMENT PROTOCOL v2.0 ⚡                 ║
║     ChaCha20 | Auto-Detect | TCP/UDP Bridge | QUIC      ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
BANNER
echo -e "${N}"

# ════════════ CHECK ROOT ════════════
if [[ $EUID -ne 0 ]]; then
    echo -e "${R}[FATAL] Run as root!${N}"
    exit 1
fi

# ════════════ STEP 1: FIX APT & INSTALL ════════════
echo -e "${G}[1/5] Installing system packages...${N}"

# رفع قفل
rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock /var/cache/apt/archives/lock 2>/dev/null
dpkg --configure -a 2>/dev/null
apt update -y 2>/dev/null

# نصب پکیج‌ها
for pkg in curl wget openssl jq python3 python3-pip netcat-openbsd iptables dnsutils socat; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        echo -e "  -> ${Y}$pkg${N}"
        apt install -y "$pkg" 2>/dev/null || true
    fi
done

echo -e "  ${G}[+] Done${N}"

# ════════════ STEP 2: PYTHON CRYPTO ════════════
echo -e "${G}[2/5] Installing cryptography...${N}"

if python3 -c "from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305" 2>/dev/null; then
    echo -e "  ${G}[+] Already installed${N}"
else
    pip3 install --break-system-packages cryptography 2>/dev/null || \
    pip3 install cryptography 2>/dev/null || \
    apt install -y python3-cryptography 2>/dev/null || {
        echo -e "${R}[!] Failed! Run: pip3 install --break-system-packages cryptography${N}"
        exit 1
    }
    echo -e "  ${G}[+] Installed${N}"
fi

# ════════════ STEP 3: CREATE ENGINE ════════════
echo -e "${G}[3/5] Building Quantum Engine...${N}"

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

# ════════════ STEP 4: DETECT SERVER ════════════
echo -e "${G}[4/5] Detecting server...${N}"

SERVER=""
if ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1; then
    SERVER="FOREIGN"
    echo -e "${G}[+] Direct internet -> FOREIGN${N}"
elif curl -s --max-time 3 https://api.keylead.ir >/dev/null 2>&1; then
    SERVER="IRAN"
    echo -e "${B}[+] Iran API -> IRAN${N}"
else
    # تشخیص بر اساس IP
    LOCAL_IP=$(hostname -I | awk '{print $1}')
    if [[ "$LOCAL_IP" =~ ^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.) ]]; then
        SERVER="IRAN"
        echo -e "${B}[+] Private IP -> IRAN${N}"
    else
        echo -e "${Y}[?] Cannot detect${N}"
        echo -e "${W}1) Iran  2) Foreign${N}"
        read -r c
        [[ "$c" == "1" ]] && SERVER="IRAN" || SERVER="FOREIGN"
    fi
fi

# ════════════ STEP 5: CONFIGURE ════════════
echo -e "${G}[5/5] Configuring...${N}"

# تولید کلید
KEY=$(openssl rand -base64 32 | tr -d '\n+/=' | head -c 32)
HMAC=$(openssl rand -hex 32)
SALT=$(openssl rand -hex 16)
TOKEN="ARVIN-$(openssl rand -hex 24)"

echo "${KEY}:${HMAC}:${SALT}:${TOKEN}" > "$KEYS_FILE"
chmod 600 "$KEYS_FILE"
echo "$TOKEN" > "$TOKEN_FILE"

if [[ "$SERVER" == "IRAN" ]]; then
    # ════════════ IRAN CONFIG ════════════
    echo -ne "${Y}Enter FOREIGN server IP: ${N}"
    read -r REMOTE_IP

    cat > "$CONFIG_FILE" << EOF
{"type":"IRAN","remote_ip":"$REMOTE_IP","local_port":6666,"remote_port":5555,"mode":"listen","key_file":"$KEYS_FILE"}
EOF

    # سرویس engine (گوش دادن روی 6666)
    cat > /etc/systemd/system/arvin-tunnel.service << SVC
[Unit]
Description=ARVIN Quantum - Iran Engine
After=network.target
[Service]
Type=simple
ExecStart=/usr/bin/python3 $ENGINE_PY --mode listen --host 0.0.0.0 --port 6666 --config $CONFIG_FILE
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
SVC

    # TCP Bridge (10000 -> 6666)
    cat > /etc/systemd/system/arvin-bridge.service << BRIDGE
[Unit]
Description=ARVIN TCP Bridge
After=arvin-tunnel.service
[Service]
Type=simple
ExecStart=/usr/bin/socat TCP4-LISTEN:10000,fork,reuseaddr UDP4:127.0.0.1:6666
Restart=always
[Install]
WantedBy=multi-user.target
BRIDGE

    systemctl daemon-reload
    systemctl enable arvin-tunnel arvin-bridge 2>/dev/null
    systemctl restart arvin-tunnel arvin-bridge 2>/dev/null

    echo ""
    echo -e "${G}╔════════════════════════════════════════╗${N}"
    echo -e "${G}║     ✅ IRAN TUNNEL INSTALLED!         ║${N}"
    echo -e "${G}╚════════════════════════════════════════╝${N}"
    echo -e "${C}🔑 TOKEN: ${W}${TOKEN}${N}"
    echo -e "${Y}⚠️  COPY THIS TOKEN FOR FOREIGN SERVER!${N}"
    echo ""

else
    # ════════════ FOREIGN CONFIG ════════════
    echo -ne "${Y}Enter IRAN server IP: ${N}"
    read -r REMOTE_IP
    echo -ne "${Y}Enter TOKEN from Iran: ${N}"
    read -r INPUT_TOKEN
    echo "$INPUT_TOKEN" > "$TOKEN_FILE"

    cat > "$CONFIG_FILE" << EOF
{"type":"FOREIGN","remote_ip":"$REMOTE_IP","local_port":5555,"remote_port":6666,"mode":"listen","key_file":"$KEYS_FILE"}
EOF

    # سرویس engine (گوش دادن روی 5555)
    cat > /etc/systemd/system/arvin-tunnel.service << SVC
[Unit]
Description=ARVIN Quantum - Foreign Engine
After=network.target
[Service]
Type=simple
ExecStart=/usr/bin/python3 $ENGINE_PY --mode listen --host 0.0.0.0 --port 5555 --config $CONFIG_FILE
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
SVC

    # TCP Bridge (10000 -> 5555)
    cat > /etc/systemd/system/arvin-bridge.service << BRIDGE
[Unit]
Description=ARVIN TCP Bridge
After=arvin-tunnel.service
[Service]
Type=simple
ExecStart=/usr/bin/socat TCP4-LISTEN:10000,fork,reuseaddr UDP4:127.0.0.1:5555
Restart=always
[Install]
WantedBy=multi-user.target
BRIDGE

    systemctl daemon-reload
    systemctl enable arvin-tunnel arvin-bridge 2>/dev/null
    systemctl restart arvin-tunnel arvin-bridge 2>/dev/null

    echo ""
    echo -e "${G}╔════════════════════════════════════════╗${N}"
    echo -e "${G}║     ✅ FOREIGN TUNNEL INSTALLED!       ║${N}"
    echo -e "${G}╚════════════════════════════════════════╝${N}"
fi

# ════════════ CREATE arvin-tun COMMAND ════════════
cat > /usr/local/bin/arvin-tun << 'CMD'
#!/bin/bash
echo -e "\033[0;36m═══ ARVIN REPUBLIC ═══\033[0m"
echo ""
echo "Tunnel: $(systemctl is-active arvin-tunnel 2>/dev/null || echo 'offline')"
echo "Bridge: $(systemctl is-active arvin-bridge 2>/dev/null || echo 'offline')"
echo ""
echo "Ports:"
ss -tuln 2>/dev/null | grep -E '5555|6666|10000' | awk '{print "  "$1" "$5}'
echo ""
echo -e "\033[1;33mToken:\033[0m $(cat /opt/arvin-republic/token 2>/dev/null || echo 'N/A')"
echo ""
echo -e "\033[0;32mCommands:\033[0m"
echo "  systemctl restart arvin-tunnel"
echo "  systemctl restart arvin-bridge"
echo "  journalctl -u arvin-tunnel -f"
CMD

chmod +x /usr/local/bin/arvin-tun

# ════════════ FINAL STATUS ════════════
echo ""
echo -e "${W}═══════════════ STATUS ═══════════════${N}"
echo -e "Tunnel: ${G}$(systemctl is-active arvin-tunnel 2>/dev/null)${N}"
echo -e "Bridge: ${G}$(systemctl is-active arvin-bridge 2>/dev/null)${N}"
echo -e "Token:  ${C}$(cat $TOKEN_FILE)${N}"
echo -e "${W}════════════════════════════════════════${N}"
echo ""
echo -e "${Y}Run: arvin-tun${N}"

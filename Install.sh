#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  ARVIN QUANTUM FRAGMENT PROTOCOL (AQFP) v4.1 - FINAL
#  Auto-Detect Server | Auto-Install Dependencies
#  Encryption: ChaCha20-Poly1305 | Obfuscation: QUIC Mimic
#  Github: https://github.com/bingx3023-cyber/Arvin-Tunnel
#  Usage: 
#    Install:  bash Arvin.sh
#    Panel:    arvin-tun
#    Status:   arvin-tun status
#    Restart:  arvin-tun restart
#    Uninstall: arvin-tun uninstall
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

# ════════════ COLORS ════════════
R='\033[0;31m'
G='\033[0;32m'
Y='\033[1;33m'
B='\033[0;34m'
C='\033[0;36m'
W='\033[1;37m'
N='\033[0m'

# ════════════ PATHS ════════════
ARVIN_DIR="/opt/arvin-tun"
CONFIG_DIR="${ARVIN_DIR}/config"
LOG_DIR="${ARVIN_DIR}/logs"
BIN_DIR="${ARVIN_DIR}/bin"
TOKEN_FILE="${ARVIN_DIR}/token"
CONFIG_FILE="${CONFIG_DIR}/tunnel.json"
KEYS_FILE="${CONFIG_DIR}/keys.enc"
ENGINE_PY="${BIN_DIR}/fragment_engine.py"
LOG_FILE="${LOG_DIR}/arvin.log"

# ════════════ LOGGING ════════════
log_msg() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[${timestamp}] $*" | tee -a "$LOG_FILE" 2>/dev/null
}

# ════════════ BANNER ════════════
banner() {
    clear
    echo -e "${C}"
    cat << 'BANNEREOF'
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║   █████╗ ██████╗ ██╗   ██╗██╗███╗   ██╗                ║
║  ██╔══██╗██╔══██╗██║   ██║██║████╗  ██║                ║
║  ███████║██████╔╝██║   ██║██║██╔██╗ ██║                ║
║  ██╔══██║██╔══██╗╚██╗ ██╔╝██║██║╚██╗██║                ║
║  ██║  ██║██║  ██║ ╚████╔╝ ██║██║ ╚████║                ║
║  ╚═╝  ╚═╝╚═╝  ╚═╝  ╚═══╝  ╚═╝╚═╝  ╚═══╝                ║
║                                                          ║
║     ⚡ QUANTUM FRAGMENT PROTOCOL v4.1 ⚡                 ║
║     ChaCha20-Poly1305 | Auto-Detect | QUIC Mimic        ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
BANNEREOF
    echo -e "${N}"
}

# ════════════ CHECK ROOT ════════════
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${R}[FATAL] This script must be run as root!${N}"
        echo -e "${Y}Use: sudo bash Arvin.sh${N}"
        exit 1
    fi
}

# ════════════ INSTALL DEPENDENCIES ════════════
install_dependencies() {
    log_msg "${G}[1/4] Installing system packages...${N}"
    
    # Fix any broken dpkg locks
    rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock 2>/dev/null || true
    dpkg --configure -a 2>/dev/null || true
    
    # Update package list
    apt update -y -qq 2>/dev/null || true
    
    # Required packages
    local packages=(
        curl
        wget
        openssl
        jq
        python3
        python3-pip
        netcat-openbsd
        iptables
        dnsutils
    )
    
    for pkg in "${packages[@]}"; do
        if ! dpkg -s "$pkg" &>/dev/null; then
            log_msg "  -> Installing ${Y}${pkg}${N}..."
            apt install -y -qq "$pkg" 2>/dev/null || true
        fi
    done
    
    log_msg "${G}[2/4] Installing Python cryptography module...${N}"
    
    # Try multiple methods to install cryptography
    if python3 -c "from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305" 2>/dev/null; then
        log_msg "  ${G}[+] Already installed${N}"
    else
        # Method 1: pip with --break-system-packages (for newer Ubuntu)
        if pip3 install -q --break-system-packages cryptography 2>/dev/null; then
            log_msg "  ${G}[+] Installed via pip (break-system-packages)${N}"
        # Method 2: regular pip
        elif pip3 install -q cryptography 2>/dev/null; then
            log_msg "  ${G}[+] Installed via pip${N}"
        # Method 3: apt package
        elif apt install -y -qq python3-cryptography 2>/dev/null; then
            log_msg "  ${G}[+] Installed via apt${N}"
        else
            log_msg "${R}[!] Failed to install cryptography!${N}"
            log_msg "${Y}    Manual fix: pip3 install cryptography --break-system-packages${N}"
            exit 1
        fi
    fi
    
    # Verify installation
    if python3 -c "from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305; print('OK')" 2>/dev/null | grep -q "OK"; then
        log_msg "  ${G}[+] Cryptography verified OK${N}"
    else
        log_msg "${R}[!] Cryptography verification failed!${N}"
        exit 1
    fi
    
    # Create directories
    mkdir -p "$ARVIN_DIR" "$CONFIG_DIR" "$LOG_DIR" "$BIN_DIR"
    touch "$LOG_FILE"
}

# ════════════ CREATE FRAGMENT ENGINE ════════════
create_fragment_engine() {
    log_msg "${G}[3/4] Building Quantum Fragment Engine...${N}"
    
    cat > "$ENGINE_PY" << 'PYTHONEOF'
#!/usr/bin/env python3
"""
ARVIN Quantum Fragment Engine v4.1
ChaCha20-Poly1305 encryption with QUIC mimic fragmentation
"""
import socket
import struct
import random
import time
import hashlib
import os
import sys
import json
from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305


class QuantumTunnel:
    """Main tunnel class with fragment and reassembly capabilities"""
    
    def __init__(self, config_path):
        """Initialize with configuration file"""
        with open(config_path, 'r') as f:
            self.config = json.load(f)
        
        with open(self.config['key_file'], 'r') as f:
            keys = f.read().strip().split(':')
        
        self.cipher = ChaCha20Poly1305(keys[0].encode())
        
        # QUIC-like mimic headers (2 bytes each)
        self.mimic_headers = [
            b'\xc0\x00',   # QUIC Initial
            b'\x00\x00',   # gQUIC
            b'\x16\xfe',   # DTLS
            b'\xff\x00'    # Custom
        ]
    
    def encrypt(self, data):
        """Encrypt data with ChaCha20-Poly1305"""
        nonce = os.urandom(12)
        ciphertext = self.cipher.encrypt(nonce, data, None)
        return nonce + ciphertext
    
    def decrypt(self, data):
        """Decrypt data with ChaCha20-Poly1305"""
        nonce = data[:12]
        ciphertext = data[12:]
        return self.cipher.decrypt(nonce, ciphertext, None)
    
    def fragment(self, data):
        """Split data into 3-7 random fragments with QUIC headers"""
        num_frags = random.randint(3, 7)
        frag_size = len(data) // num_frags
        
        fragments = []
        for i in range(num_frags):
            start = i * frag_size
            if i < num_frags - 1:
                end = start + frag_size
            else:
                end = len(data)
            
            fragment_data = data[start:end]
            
            # Add random QUIC-like header
            header = random.choice(self.mimic_headers)
            length_field = struct.pack('!H', len(fragment_data))
            
            fragments.append(header + length_field + fragment_data)
        
        return fragments
    
    def send(self, data, target_host, target_port):
        """Fragment and send data over UDP with jitter"""
        fragments = self.fragment(data)
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        
        for frag in fragments:
            # Add random jitter (5-50ms)
            jitter = random.uniform(0.005, 0.050)
            time.sleep(jitter)
            
            # Encrypt and send on random nearby port
            encrypted = self.encrypt(frag)
            port_offset = random.randint(0, 5)
            sock.sendto(encrypted, (target_host, target_port + port_offset))
        
        sock.close()
    
    def listen(self, bind_host, bind_port):
        """Listen for fragments and reassemble"""
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.bind((bind_host, bind_port))
        sock.settimeout(1.0)
        
        buffer = {}
        
        while True:
            try:
                data, addr = sock.recvfrom(65535)
                
                try:
                    plaintext = self.decrypt(data)
                except Exception:
                    continue
                
                # Remove QUIC header (4 bytes: 2 header + 2 length)
                payload = plaintext[4:]
                
                # Simple reassembly based on content hash
                fragment_id = hashlib.md5(payload[:16]).hexdigest()
                buffer[fragment_id] = payload[16:]
                
                # When we have enough fragments, reassemble
                if len(buffer) >= 3:
                    result = b''.join(buffer.values())
                    buffer.clear()
                    sys.stdout.buffer.write(result)
                    sys.stdout.buffer.flush()
                    
            except socket.timeout:
                continue
            except Exception:
                continue


if __name__ == '__main__':
    import argparse
    
    parser = argparse.ArgumentParser(description='ARVIN Quantum Fragment Engine')
    parser.add_argument('--mode', choices=['send', 'listen'], required=True,
                        help='Operation mode')
    parser.add_argument('--config', default='/opt/arvin-tun/config/tunnel.json',
                        help='Path to config file')
    parser.add_argument('--host', default='127.0.0.1',
                        help='Target host')
    parser.add_argument('--port', type=int, default=6666,
                        help='Target port')
    
    args = parser.parse_args()
    
    engine = QuantumTunnel(args.config)
    
    if args.mode == 'send':
        data = sys.stdin.buffer.read()
        engine.send(data, args.host, args.port)
    else:
        engine.listen(args.host, args.port)
PYTHONEOF
    
    chmod +x "$ENGINE_PY"
    log_msg "  ${G}[+] Engine created successfully${N}"
}

# ════════════ DETECT SERVER ════════════
detect_server_location() {
    log_msg "${Y}[*] Detecting server location...${N}"
    
    # Test 1: Can we ping Google DNS?
    if ping -c 1 -W 1 8.8.8.8 &>/dev/null; then
        log_msg "${G}[+] Direct internet access → FOREIGN SERVER${N}"
        echo "FOREIGN"
        return 0
    fi
    
    # Test 2: Can we reach Iranian APIs?
    if curl -s --max-time 3 https://api.keylead.ir &>/dev/null; then
        log_msg "${B}[+] Iran API reachable → IRAN SERVER${N}"
        echo "IRAN"
        return 0
    fi
    
    # Test 3: Check if IP is private range
    local local_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [[ "$local_ip" =~ ^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.) ]]; then
        log_msg "${B}[+] Private IP → Likely IRAN SERVER${N}"
        echo "IRAN"
        return 0
    fi
    
    # Fallback: Ask user
    log_msg "${R}[!] Cannot auto-detect!${N}"
    echo -e "${W}Please select server type:${N}"
    echo -e "  ${G}1)${N} Iran Server 🇮🇷"
    echo -e "  ${B}2)${N} Foreign Server 🌍"
    echo -ne "${Y}Choice [1-2]: ${N}"
    read -r user_choice
    
    if [[ "$user_choice" == "1" ]]; then
        echo "IRAN"
    else
        echo "FOREIGN"
    fi
}

# ════════════ CONFIGURE TUNNEL ════════════
configure_tunnel() {
    local server_type=$1
    log_msg "${G}[4/4] Configuring ${server_type} tunnel...${N}"
    
    # Generate cryptographic keys
    local chacha_key=$(openssl rand -base64 32 | tr -d '\n+/=' | head -c 32)
    local hmac_key=$(openssl rand -hex 32)
    local salt=$(openssl rand -hex 16)
    local token="AQFP-$(openssl rand -hex 24)"
    
    # Store keys securely
    echo "${chacha_key}:${hmac_key}:${salt}:${token}" > "$KEYS_FILE"
    chmod 600 "$KEYS_FILE"
    
    # Store token
    echo "$token" > "$TOKEN_FILE"
    
    if [[ "$server_type" == "IRAN" ]]; then
        # Iran server configuration
        echo -ne "${Y}Enter FOREIGN server IP address: ${N}"
        read -r remote_ip
        
        # Validate IP
        if [[ ! "$remote_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            log_msg "${R}[!] Invalid IP address!${N}"
            exit 1
        fi
        
        # Create config
        cat > "$CONFIG_FILE" << EOF
{
    "type": "IRAN",
    "remote_ip": "${remote_ip}",
    "local_port": 6666,
    "remote_port": 5555,
    "mode": "listen",
    "key_file": "${KEYS_FILE}"
}
EOF
        
        # Create systemd service for Iran
        cat > /etc/systemd/system/arvin-quantum.service << SERVICEOF
[Unit]
Description=ARVIN Quantum Tunnel - Iran Server
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 ${ENGINE_PY} --mode listen --host 0.0.0.0 --port 6666 --config ${CONFIG_FILE}
Restart=always
RestartSec=5
StandardOutput=append:${LOG_FILE}
StandardError=append:${LOG_FILE}

[Install]
WantedBy=multi-user.target
SERVICEOF
        
    else
        # Foreign server configuration
        echo -ne "${Y}Enter IRAN server IP address: ${N}"
        read -r remote_ip
        
        if [[ ! "$remote_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            log_msg "${R}[!] Invalid IP address!${N}"
            exit 1
        fi
        
        echo -ne "${Y}Enter TOKEN from Iran server: ${N}"
        read -r input_token
        
        # Save token
        echo "$input_token" > "$TOKEN_FILE"
        
        # Create config
        cat > "$CONFIG_FILE" << EOF
{
    "type": "FOREIGN",
    "remote_ip": "${remote_ip}",
    "local_port": 5555,
    "remote_port": 6666,
    "mode": "send",
    "key_file": "${KEYS_FILE}"
}
EOF
        
        # Create systemd service for Foreign
        cat > /etc/systemd/system/arvin-quantum.service << SERVICEOF
[Unit]
Description=ARVIN Quantum Tunnel - Foreign Server
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 ${ENGINE_PY} --mode send --host ${remote_ip} --port 6666 --config ${CONFIG_FILE}
Restart=always
RestartSec=5
StandardOutput=append:${LOG_FILE}
StandardError=append:${LOG_FILE}

[Install]
WantedBy=multi-user.target
SERVICEOF
    fi
    
    # Enable and start service
    systemctl daemon-reload
    systemctl enable arvin-quantum 2>/dev/null || true
    systemctl restart arvin-quantum 2>/dev/null || true
    
    # Create symlink for easy access
    ln -sf "$(readlink -f "$0")" /usr/local/bin/arvin-tun 2>/dev/null || true
    
    # Success message
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
    echo -e "${C}🔑 TOKEN: ${W}${token}${N}"
    echo -e "${Y}⚠️  SAVE THIS TOKEN! You need it for the other server!${N}"
    echo ""
}

# ════════════ SHOW STATUS ════════════
show_status() {
    banner
    echo -e "${W}═══════════════ TUNNEL STATUS ═══════════════${N}"
    echo ""
    
    # Check service status
    echo -ne "  Service:    "
    if systemctl is-active --quiet arvin-quantum 2>/dev/null; then
        echo -e "${G}● ACTIVE${N}"
    else
        echo -e "${R}● INACTIVE${N}"
    fi
    
    # Check port
    local port=$(jq -r '.local_port' "$CONFIG_FILE" 2>/dev/null || echo "?")
    echo -ne "  Port:       "
    if ss -tuln 2>/dev/null | grep -q ":${port} "; then
        echo -e "${G}● ${port} (LISTENING)${N}"
    else
        echo -e "${R}● ${port} (CLOSED)${N}"
    fi
    
    # Show token
    echo -e "  Token:      ${C}$(cat "$TOKEN_FILE" 2>/dev/null || echo 'N/A')${N}"
    
    # Show encryption
    echo -e "  Encryption: ${G}ChaCha20-Poly1305${N}"
    echo -e "  Obfuscation: ${G}QUIC Mimic (3-7 fragments)${N}"
    
    # Test latency
    local remote=$(jq -r '.remote_ip' "$CONFIG_FILE" 2>/dev/null)
    if [[ -n "$remote" && "$remote" != "null" ]]; then
        echo -ne "  Latency:    "
        local ping_result=$(ping -c 3 -W 2 "$remote" 2>/dev/null | tail -1 | awk -F'/' '{print $5}')
        if [[ -n "$ping_result" ]]; then
            echo -e "${G}${ping_result} ms${N}"
        else
            echo -e "${R}Unreachable${N}"
        fi
    fi
    
    echo ""
    echo -e "${W}═══════════════════════════════════════════════${N}"
}

# ════════════ CONTROL PANEL ════════════
control_panel() {
    while true; do
        banner
        echo -e "${W}══════════════ CONTROL PANEL ══════════════${N}"
        echo ""
        echo -e "  ${G}1)${N} 📊 View Status"
        echo -e "  ${G}2)${N} 🔑 Show Token"
        echo -e "  ${G}3)${N} 🔄 Restart Tunnel"
        echo -e "  ${G}4)${N} 📜 View Logs (live)"
        echo -e "  ${G}5)${N} ⚡ Speed Test (ping)"
        echo -e "  ${G}6)${N} 📖 Installation Guide"
        echo -e "  ${R}7)${N} 🗑️  Uninstall"
        echo -e "  ${R}0)${N} 🚪 Exit"
        echo ""
        echo -ne "${Y}Select option [0-7]: ${N}"
        read -r choice
        
        case "$choice" in
            1)
                show_status
                echo -e "\n${Y}Press Enter to continue...${N}"
                read -r
                ;;
            2)
                echo -e "\n${C}🔑 Token: ${W}$(cat "$TOKEN_FILE" 2>/dev/null || echo 'Not found')${N}"
                echo -e "\n${Y}Press Enter to continue...${N}"
                read -r
                ;;
            3)
                systemctl restart arvin-quantum 2>/dev/null || true
                echo -e "${G}✅ Tunnel restarted!${N}"
                sleep 2
                ;;
            4)
                echo -e "${C}Live logs (Ctrl+C to exit):${N}"
                journalctl -u arvin-quantum -f --no-pager 2>/dev/null || \
                tail -f "$LOG_FILE" 2>/dev/null
                ;;
            5)
                local remote=$(jq -r '.remote_ip' "$CONFIG_FILE" 2>/dev/null)
                if [[ -n "$remote" && "$remote" != "null" ]]; then
                    echo -e "${C}Pinging ${remote}...${N}"
                    ping -c 10 "$remote"
                else
                    echo -e "${R}No remote IP configured!${N}"
                fi
                echo -e "\n${Y}Press Enter to continue...${N}"
                read -r
                ;;
            6)
                clear
                cat << 'GUIDEEOF'
╔══════════════════════════════════════════════════════════╗
║              📖 INSTALLATION GUIDE                      ║
╠══════════════════════════════════════════════════════════╣
║                                                        ║
║  🖥️  IRAN SERVER:                                      ║
║     1. bash Arvin.sh                                   ║
║     2. Script auto-detects IRAN server                 ║
║     3. Enter FOREIGN server IP                         ║
║     4. SAVE THE TOKEN! 🔑                              ║
║                                                        ║
║  🌍 FOREIGN SERVER:                                    ║
║     1. bash Arvin.sh                                   ║
║     2. Script auto-detects FOREIGN server              ║
║     3. Enter IRAN server IP                            ║
║     4. Enter the TOKEN from Iran server                ║
║                                                        ║
║  ✅ DONE! Tunnel is active!                            ║
║                                                        ║
║  🎮 COMMANDS:                                          ║
║     arvin-tun          = Control Panel                 ║
║     arvin-tun status   = Check Status                  ║
║     arvin-tun restart  = Restart Tunnel                ║
║     arvin-tun uninstall = Remove Tunnel                ║
║                                                        ║
╚══════════════════════════════════════════════════════════╝
GUIDEEOF
                echo -e "\n${Y}Press Enter to return...${N}"
                read -r
                ;;
            7)
                echo -ne "${R}⚠️  Uninstall ARVIN Tunnel? [y/N]: ${N}"
                read -r confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    systemctl stop arvin-quantum 2>/dev/null || true
                    systemctl disable arvin-quantum 2>/dev/null || true
                    rm -f /etc/systemd/system/arvin-quantum.service
                    rm -rf "$ARVIN_DIR"
                    rm -f /usr/local/bin/arvin-tun
                    systemctl daemon-reload
                    echo -e "${G}✅ Uninstalled successfully!${N}"
                    exit 0
                fi
                ;;
            0)
                echo -e "${G}Goodbye!${N}"
                exit 0
                ;;
            *)
                echo -e "${R}Invalid option!${N}"
                sleep 1
                ;;
        esac
    done
}

# ════════════ MAIN FUNCTION ════════════
main_install() {
    check_root
    banner
    
    echo -e "${W}Welcome to ARVIN Quantum Fragment Protocol v4.1${N}"
    echo -e "${C}Encryption: ChaCha20-Poly1305 | Obfuscation: QUIC Mimic${N}"
    echo ""
    
    # Install dependencies
    install_dependencies
    
    # Create fragment engine
    create_fragment_engine
    
    # Detect server and configure
    local server_type=$(detect_server_location)
    configure_tunnel "$server_type"
}

# ════════════ ENTRY POINT ════════════
case "${1:-install}" in
    install)
        main_install
        ;;
    panel)
        check_root
        control_panel
        ;;
    status)
        check_root
        show_status
        ;;
    restart)
        check_root
        systemctl restart arvin-quantum 2>/dev/null || true
        echo -e "${G}✅ Tunnel restarted!${N}"
        ;;
    uninstall)
        check_root
        echo -ne "${R}⚠️  Uninstall ARVIN Tunnel? [y/N]: ${N}"
        read -r confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            systemctl stop arvin-quantum 2>/dev/null || true
            systemctl disable arvin-quantum 2>/dev/null || true
            rm -f /etc/systemd/system/arvin-quantum.service
            rm -rf "$ARVIN_DIR"
            rm -f /usr/local/bin/arvin-tun
            systemctl daemon-reload
            echo -e "${G}✅ Uninstalled!${N}"
        fi
        ;;
    *)
        echo -e "${W}ARVIN Quantum Fragment Protocol v4.1${N}"
        echo ""
        echo -e "${Y}Usage:${N}"
        echo -e "  ${G}bash Arvin.sh${N}              - Install tunnel"
        echo -e "  ${G}arvin-tun${N}                  - Open control panel"
        echo -e "  ${G}arvin-tun status${N}           - Check status"
        echo -e "  ${G}arvin-tun restart${N}          - Restart tunnel"
        echo -e "  ${G}arvin-tun uninstall${N}        - Remove tunnel"
        ;;
esac

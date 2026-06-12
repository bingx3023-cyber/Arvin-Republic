#!/bin/bash

# ============================================
# IranExTunnel v3.3 - Professional Tunnel for Iran<->Outside
# ============================================

set -e

# رنگ‌ها
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# متغیرها
CONFIG_DIR="/etc/iranextunnel"
LOG_DIR="/var/log/iranextunnel"
WATCHDOG_SCRIPT="/usr/local/bin/tunnel-watchdog.sh"

# ============================================
print_banner() {
    clear
    echo -e "${CYAN}"
    echo "████████╗██╗   ██╗███╗   ██╗███╗   ██╗███████╗██╗      █████╗ ██████╗ ██╗   ██╗"
    echo "╚══██╔══╝██║   ██║████╗  ██║████╗  ██║██╔════╝██║     ██╔══██╗██╔══██╗╚██╗ ██╔╝"
    echo "   ██║   ██║   ██║██╔██╗ ██║██╔██╗ ██║█████╗  ██║     ███████║██████╔╝ ╚████╔╝ "
    echo "   ██║   ██║   ██║██║╚██╗██║██║╚██╗██║██╔══╝  ██║     ██╔══██║██╔══██╗  ╚██╔╝  "
    echo "   ██║   ╚██████╔╝██║ ╚████║██║ ╚████║███████╗███████╗██║  ██║██║  ██║   ██║   "
    echo "   ╚═╝    ╚═════╝ ╚═╝  ╚═══╝╚═╝  ╚═══╝╚══════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝   "
    echo -e "${NC}"
    echo -e "${WHITE}       Professional Iran<->Outside Tunnel Manager v3.3${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════${NC}\n"
}

# ============================================
log() {
    local level="$1"
    local msg="$2"
    mkdir -p "$LOG_DIR"
    echo "[$(date)] [$level] $msg" >> "$LOG_DIR/tunnel.log"
    case "$level" in
        "ERROR") echo -e "${RED}❌ $msg${NC}" ;;
        "WARN")  echo -e "${YELLOW}⚠️  $msg${NC}" ;;
        "INFO")  echo -e "${GREEN}✓ $msg${NC}" ;;
        "STEP")  echo -e "${BLUE}➜ $msg${NC}" ;;
        *)       echo -e "$msg" ;;
    esac
}

# ============================================
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Please run as root: sudo $0${NC}"
        exit 1
    fi
}

# ============================================
install_dependencies() {
    log "STEP" "Installing dependencies"
    apt update -qq 2>/dev/null || true
    for pkg in socat openssl curl wget net-tools ufw iptables nano cron; do
        if ! dpkg -l | grep -q "^ii  $pkg "; then
            apt install -y "$pkg" -qq 2>/dev/null || log "WARN" "Could not install $pkg"
        fi
    done
    if ! command -v websocat &> /dev/null; then
        wget -q -O /usr/local/bin/websocat https://github.com/vi/websocat/releases/latest/download/websocat_amd64-linux-static
        chmod +x /usr/local/bin/websocat 2>/dev/null || true
    fi
    log "INFO" "Dependencies ready"
}

# ============================================
get_user_config() {
    echo -e "\n${WHITE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}              TUNNEL CONFIGURATION${NC}"
    echo -e "${WHITE}════════════════════════════════════════════════════════════${NC}\n"
    
    while true; do
        echo -e "${CYAN}📡 Server Type:${NC}"
        echo "  1) IRAN Server (Client)"
        echo "  2) OUTSIDE Server (Server)"
        read -p "👉 Choose [1-2]: " SERVER_TYPE
        [[ "$SERVER_TYPE" =~ ^[12]$ ]] && break
    done
    
    read -p "🔖 Name [tunnel-main]: " TUNNEL_NAME
    TUNNEL_NAME="${TUNNEL_NAME:-tunnel-main}"
    
    while true; do
        echo -e "\n${CYAN}🔌 Protocol:${NC}"
        echo "  1) TCP"
        echo "  2) SSL/TLS (recommended)"
        echo "  3) WebSocket"
        read -p "👉 Choose [1-3]: " PROTOCOL_TYPE
        if [[ "$PROTOCOL_TYPE" =~ ^[123]$ ]]; then
            case $PROTOCOL_TYPE in
                1) PROTOCOL="tcp" ;;
                2) PROTOCOL="ssl" ;;
                3) PROTOCOL="websocket" ;;
            esac
            break
        fi
    done
    
    read -p "🔌 Local Port [443]: " LOCAL_PORT
    LOCAL_PORT="${LOCAL_PORT:-443}"
    read -p "🎯 Destination Port [22]: " DEST_PORT
    DEST_PORT="${DEST_PORT:-22}"
    
    if [[ "$SERVER_TYPE" -eq 2 ]]; then
        SERVER_IP=$(curl -s ifconfig.me)
        log "INFO" "Your server IP: $SERVER_IP"
    else
        echo -e "\n${CYAN}🌍 Outside Server Details:${NC}"
        read -p "👉 IP: " OUTSIDE_IP
        read -p "👉 Port: " OUTSIDE_PORT
    fi
    
    AUTH_TOKEN=$(openssl rand -hex 16)
    log "INFO" "Auth Token: $AUTH_TOKEN"
    
    read -p "🔄 Retry interval (sec) [10]: " RETRY_INTERVAL
    RETRY_INTERVAL="${RETRY_INTERVAL:-10}"
    
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_DIR/$TUNNEL_NAME.conf" << EOF
TUNNEL_NAME="$TUNNEL_NAME"
SERVER_TYPE="$SERVER_TYPE"
PROTOCOL="$PROTOCOL"
LOCAL_PORT="$LOCAL_PORT"
DEST_PORT="$DEST_PORT"
AUTH_TOKEN="$AUTH_TOKEN"
RETRY_INTERVAL="$RETRY_INTERVAL"
EOF
    [[ "$SERVER_TYPE" -eq 1 ]] && echo "OUTSIDE_IP=\"$OUTSIDE_IP\"" >> "$CONFIG_DIR/$TUNNEL_NAME.conf" && echo "OUTSIDE_PORT=\"$OUTSIDE_PORT\"" >> "$CONFIG_DIR/$TUNNEL_NAME.conf"
    [[ "$SERVER_TYPE" -eq 2 ]] && echo "SERVER_IP=\"$SERVER_IP\"" >> "$CONFIG_DIR/$TUNNEL_NAME.conf"
    
    log "INFO" "Config saved"
}

# ============================================
setup_firewall() {
    local port="$1"
    log "STEP" "Configuring firewall for port $port"
    command -v ufw &> /dev/null && ufw allow "$port"/tcp 2>/dev/null || true
    command -v iptables &> /dev/null && iptables -I INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || true
    if ! grep -q "IranExTunnel" /etc/sysctl.conf; then
        cat >> /etc/sysctl.conf << EOF

# IranExTunnel Optimizations
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 5
EOF
        sysctl -p 2>/dev/null || true
    fi
    log "INFO" "Firewall ready"
}

# ============================================
create_systemd_service() {
    local tunnel_name="$1"
    local service_file="/etc/systemd/system/irantunnel-${tunnel_name}.service"
    local exec_start=""
    
    source "$CONFIG_DIR/$tunnel_name.conf"
    
    if [[ "$PROTOCOL" == "ssl" ]] && [[ ! -f "/etc/stunnel/stunnel.pem" ]]; then
        mkdir -p /etc/stunnel
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout /etc/stunnel/stunnel.key \
            -out /etc/stunnel/stunnel.crt \
            -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost" 2>/dev/null
        cat /etc/stunnel/stunnel.crt /etc/stunnel/stunnel.key > /etc/stunnel/stunnel.pem
        chmod 600 /etc/stunnel/stunnel.pem
    fi
    
    if [[ "$PROTOCOL" == "tcp" ]]; then
        [[ "$SERVER_TYPE" -eq 2 ]] && exec_start="/usr/bin/socat TCP-LISTEN:${LOCAL_PORT},reuseaddr,fork,keepalive TCP:127.0.0.1:${DEST_PORT}"
        [[ "$SERVER_TYPE" -eq 1 ]] && exec_start="/usr/bin/socat TCP:127.0.0.1:${DEST_PORT} TCP:${OUTSIDE_IP}:${OUTSIDE_PORT},forever,intervall=${RETRY_INTERVAL}"
    elif [[ "$PROTOCOL" == "ssl" ]]; then
        [[ "$SERVER_TYPE" -eq 2 ]] && exec_start="/usr/bin/socat OPENSSL-LISTEN:${LOCAL_PORT},reuseaddr,fork,cert=/etc/stunnel/stunnel.pem,verify=0,keepalive TCP:127.0.0.1:${DEST_PORT}"
        [[ "$SERVER_TYPE" -eq 1 ]] && exec_start="/usr/bin/socat TCP:127.0.0.1:${DEST_PORT} OPENSSL:${OUTSIDE_IP}:${OUTSIDE_PORT},verify=0,forever,intervall=${RETRY_INTERVAL}"
    elif [[ "$PROTOCOL" == "websocket" ]]; then
        [[ "$SERVER_TYPE" -eq 2 ]] && exec_start="/usr/local/bin/websocat --binary -s ${LOCAL_PORT} --restrict-udp --tcp 127.0.0.1:${DEST_PORT}"
        [[ "$SERVER_TYPE" -eq 1 ]] && exec_start="/usr/local/bin/websocat --binary ws://${OUTSIDE_IP}:${OUTSIDE_PORT} tcp:127.0.0.1:${DEST_PORT} --retry-ws --retry-interval ${RETRY_INTERVAL}"
    fi
    
    cat > "$service_file" << EOF
[Unit]
Description=IranExTunnel - $tunnel_name
After=network.target

[Service]
Type=simple
ExecStart=$exec_start
Restart=always
RestartSec=${RETRY_INTERVAL}
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
    log "INFO" "Service created"
}

# ============================================
install_watchdog() {
    log "STEP" "Installing watchdog"
    cat > "$WATCHDOG_SCRIPT" << 'EOF'
#!/bin/bash
for config in /etc/iranextunnel/*.conf; do
    [ -f "$config" ] || continue
    source "$config"
    if ! systemctl is-active --quiet "irantunnel-${TUNNEL_NAME}.service"; then
        echo "[$(date)] Restarting ${TUNNEL_NAME}" >> /var/log/iranextunnel/watchdog.log
        systemctl restart "irantunnel-${TUNNEL_NAME}.service"
    fi
done
EOF
    chmod +x "$WATCHDOG_SCRIPT"
    if ! crontab -l 2>/dev/null | grep -q "$WATCHDOG_SCRIPT"; then
        (crontab -l 2>/dev/null; echo "* * * * * $WATCHDOG_SCRIPT") | crontab - 2>/dev/null || true
    fi
    log "INFO" "Watchdog ready"
}

# ============================================
start_tunnel() {
    local tunnel_name="$1"
    log "STEP" "Starting tunnel"
    source "$CONFIG_DIR/$tunnel_name.conf"
    setup_firewall "$LOCAL_PORT"
    create_systemd_service "$tunnel_name"
    systemctl daemon-reload
    systemctl enable "irantunnel-${tunnel_name}.service"
    systemctl start "irantunnel-${tunnel_name}.service"
    sleep 2
    if systemctl is-active --quiet "irantunnel-${tunnel_name}.service"; then
        echo -e "\n${GREEN}════════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}🎉 TUNNEL IS RUNNING!${NC}"
        echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
        echo -e "${WHITE}📋 Details:${NC}"
        echo -e "   Name: ${YELLOW}$tunnel_name${NC}"
        echo -e "   Protocol: ${YELLOW}$PROTOCOL${NC}"
        echo -e "   Local Port: ${YELLOW}$LOCAL_PORT${NC}"
        echo -e "\n${WHITE}Commands:${NC}"
        echo -e "   Status: ${YELLOW}systemctl status irantunnel-$tunnel_name${NC}"
        echo -e "   Logs: ${YELLOW}journalctl -u irantunnel-$tunnel_name -f${NC}"
        echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}\n"
    else
        log "ERROR" "Failed to start"
    fi
}

# ============================================
show_status() {
    echo -e "\n${BLUE}📊 Tunnels Status:${NC}"
    local found=0
    for config in "$CONFIG_DIR"/*.conf 2>/dev/null; do
        [ -f "$config" ] || continue
        found=1
        source "$config"
        if systemctl is-active --quiet "irantunnel-${TUNNEL_NAME}.service"; then
            echo -e "${GREEN}   ✓ $TUNNEL_NAME: RUNNING${NC}"
        else
            echo -e "${RED}   ✗ $TUNNEL_NAME: STOPPED${NC}"
        fi
    done
    [ $found -eq 0 ] && echo -e "${YELLOW}   No tunnels${NC}"
}

# ============================================
show_menu() {
    echo -e "\n${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}📋 MAIN MENU${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo -e "  ${GREEN}1${NC}) Create Tunnel"
    echo -e "  ${GREEN}2${NC}) Status"
    echo -e "  ${GREEN}3${NC}) Stop Tunnel"
    echo -e "  ${GREEN}4${NC}) Restart Tunnel"
    echo -e "  ${GREEN}5${NC}) View Logs"
    echo -e "  ${GREEN}6${NC}) Remove Tunnel"
    echo -e "  ${GREEN}7${NC}) Exit"
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
}

# ============================================
main() {
    print_banner
    check_root
    install_dependencies
    install_watchdog
    
    while true; do
        show_menu
        read -p "👉 Select [1-7]: " choice
        case $choice in
            1)
                get_user_config
                start_tunnel "$TUNNEL_NAME"
                ;;
            2)
                show_status
                ;;
            3)
                show_status
                read -p "Name: " name
                systemctl stop "irantunnel-${name}.service" 2>/dev/null && log "INFO" "Stopped $name" || echo -e "${RED}Not found${NC}"
                ;;
            4)
                show_status
                read -p "Name: " name
                systemctl restart "irantunnel-${name}.service" 2>/dev/null && log "INFO" "Restarted $name" || echo -e "${RED}Not found${NC}"
                ;;
            5)
                echo -e "\n${BLUE}📄 Logs:${NC}"
                tail -30 "$LOG_DIR/tunnel.log" 2>/dev/null || echo "No logs"
                ;;
            6)
                show_status
                read -p "Name: " name
                systemctl stop "irantunnel-${name}.service" 2>/dev/null
                systemctl disable "irantunnel-${name}.service" 2>/dev/null
                rm -f "/etc/systemd/system/irantunnel-${name}.service"
                rm -f "$CONFIG_DIR/${name}.conf"
                systemctl daemon-reload
                log "INFO" "Removed $name"
                ;;
            7)
                echo -e "${GREEN}Bye!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid${NC}"
                ;;
        esac
        echo -e "\n${YELLOW}Press Enter...${NC}"
        read
        print_banner
    done
}

main "$@"

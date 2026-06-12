#!/bin/bash

# ============================================
# IranExTunnel v3.1 - Professional Tunnel for Iran<->Outside
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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="/etc/iranextunnel"
LOG_DIR="/var/log/iranextunnel"
WATCHDOG_SCRIPT="/usr/local/bin/tunnel-watchdog.sh"

# ============================================
# بنر خوش‌آمدگویی
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
    echo -e "${WHITE}       Professional Iran<->Outside Tunnel Manager v3.1${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════${NC}\n"
}

# ============================================
# لاگ کردن
# ============================================
log() {
    local level=$1
    local msg=$2
    mkdir -p "$LOG_DIR"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $msg" >> "$LOG_DIR/tunnel.log"
    
    case $level in
        "ERROR") echo -e "${RED}❌ $msg${NC}" ;;
        "WARN")  echo -e "${YELLOW}⚠️  $msg${NC}" ;;
        "INFO")  echo -e "${GREEN}✓ $msg${NC}" ;;
        "STEP")  echo -e "${BLUE}➜ $msg${NC}" ;;
        *)       echo -e "$msg" ;;
    esac
}

# ============================================
# چک کردن روت بودن
# ============================================
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log "ERROR" "This script must be run as root!"
        echo -e "${YELLOW}Please run: sudo $0${NC}"
        exit 1
    fi
}

# ============================================
# نصب خودکار و کامل پیش‌نیازها
# ============================================
install_dependencies() {
    log "STEP" "Installing all required dependencies..."
    
    apt update -qq 2>/dev/null || true
    
    local packages=(
        socat openssl curl wget net-tools ufw iptables
        nano htop nload tmux cron gcc make git
    )
    
    for pkg in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $pkg "; then
            log "INFO" "Installing $pkg..."
            apt install -y "$pkg" -qq 2>/dev/null || log "WARN" "Could not install $pkg"
        fi
    done
    
    install_special_tools
}

# ============================================
# نصب ابزارهای مخصوص تانل
# ============================================
install_special_tools() {
    log "STEP" "Installing special tunneling tools..."
    
    if ! command -v bore &> /dev/null; then
        wget -q -O /usr/local/bin/bore https://github.com/ekzhang/bore/releases/latest/download/bore-cli_amd64-unknown-linux-musl
        chmod +x /usr/local/bin/bore
        log "INFO" "Bore installed"
    fi
    
    if ! command -v chisel &> /dev/null; then
        wget -q -O /tmp/chisel.gz https://github.com/jpillora/chisel/releases/latest/download/chisel_linux_amd64.gz
        gunzip -c /tmp/chisel.gz > /usr/local/bin/chisel
        chmod +x /usr/local/bin/chisel
        rm /tmp/chisel.gz
        log "INFO" "Chisel installed"
    fi
    
    if ! command -v websocat &> /dev/null; then
        wget -q -O /usr/local/bin/websocat https://github.com/vi/websocat/releases/latest/download/websocat_amd64-linux-static
        chmod +x /usr/local/bin/websocat
        log "INFO" "Websocat installed"
    fi
}

# ============================================
# گرفتن تنظیمات از کاربر
# ============================================
get_user_config() {
    echo -e "\n${WHITE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}              TUNNEL CONFIGURATION SETUP${NC}"
    echo -e "${WHITE}════════════════════════════════════════════════════════════${NC}\n"
    
    echo -e "\n${CYAN}📡 Server Type:${NC}"
    echo "  1) 🇮🇷 IRAN Server (Client mode - connects to outside)"
    echo "  2) 🌍 OUTSIDE Server (Server mode - waits for connection)"
    read -p "👉 Choose [1-2]: " SERVER_TYPE
    
    read -p "🔖 Tunnel Name [tunnel-main]: " TUNNEL_NAME
    TUNNEL_NAME=${TUNNEL_NAME:-tunnel-main}
    
    echo -e "\n${CYAN}🔌 Protocol Type:${NC}"
    echo "  1) TCP Direct (fastest, less stealthy)"
    echo "  2) SSL/TLS (secure, recommended)"  
    echo "  3) WebSocket (most stealthy for strict networks)"
    read -p "👉 Choose [1-3]: " PROTOCOL_TYPE
    
    case $PROTOCOL_TYPE in
        1) PROTOCOL="tcp" ;;
        2) PROTOCOL="ssl" ;;
        3) PROTOCOL="websocket" ;;
        *) PROTOCOL="ssl" ;;
    esac
    
    read -p "🔌 Local Port to listen on [443]: " LOCAL_PORT
    LOCAL_PORT=${LOCAL_PORT:-443}
    
    read -p "🎯 Destination Port on other side [22]: " DEST_PORT
    DEST_PORT=${DEST_PORT:-22}
    
    if [[ $SERVER_TYPE -eq 2 ]]; then
        SERVER_IP=$(curl -s ifconfig.me)
        log "INFO" "Your server IP: $SERVER_IP"
    else
        echo -e "\n${CYAN}🌍 Outside Server Details:${NC}"
        read -p "👉 Outside Server IP: " OUTSIDE_IP
        read -p "👉 Outside Server Port: " OUTSIDE_PORT
    fi
    
    read -p "🔑 Auth Token [auto-generate]: " AUTH_TOKEN
    if [[ -z "$AUTH_TOKEN" ]]; then
        AUTH_TOKEN=$(openssl rand -hex 16)
    fi
    log "INFO" "Auth Token: $AUTH_TOKEN (save this!)"
    
    echo -e "\n${CYAN}🛡️ Stability Settings:${NC}"
    read -p "🔄 Auto-restart on failure? [Y/n]: " AUTO_RESTART
    AUTO_RESTART=${AUTO_RESTART:-Y}
    read -p "⏱️ Retry interval (seconds) [10]: " RETRY_INTERVAL
    RETRY_INTERVAL=${RETRY_INTERVAL:-10}
    
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_DIR/$TUNNEL_NAME.conf" << EOF
TUNNEL_NAME="$TUNNEL_NAME"
SERVER_TYPE="$SERVER_TYPE"
PROTOCOL="$PROTOCOL"
LOCAL_PORT="$LOCAL_PORT"
DEST_PORT="$DEST_PORT"
AUTH_TOKEN="$AUTH_TOKEN"
AUTO_RESTART="$AUTO_RESTART"
RETRY_INTERVAL="$RETRY_INTERVAL"
EOF

    if [[ $SERVER_TYPE -eq 1 ]]; then
        echo "OUTSIDE_IP=\"$OUTSIDE_IP\"" >> "$CONFIG_DIR/$TUNNEL_NAME.conf"
        echo "OUTSIDE_PORT=\"$OUTSIDE_PORT\"" >> "$CONFIG_DIR/$TUNNEL_NAME.conf"
    else
        echo "SERVER_IP=\"$SERVER_IP\"" >> "$CONFIG_DIR/$TUNNEL_NAME.conf"
    fi
    
    log "INFO" "Configuration saved to $CONFIG_DIR/$TUNNEL_NAME.conf"
}

# ============================================
# تنظیم فایروال خودکار
# ============================================
setup_firewall() {
    local port=$1
    log "STEP" "Configuring firewall for port $port..."
    
    command -v ufw &> /dev/null && ufw allow "$port"/tcp 2>/dev/null || true
    command -v iptables &> /dev/null && iptables -I INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || true
    
    cat >> /etc/sysctl.conf << EOF

# IranExTunnel Optimizations
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 5
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
EOF
    sysctl -p 2>/dev/null || true
    log "INFO" "Network optimized for stability"
}

# ============================================
# ایجاد سرویس systemd
# ============================================
create_systemd_service() {
    local tunnel_name=$1
    local service_file="/etc/systemd/system/irantunnel-${tunnel_name}.service"
    local exec_start=""
    
    source "$CONFIG_DIR/$tunnel_name.conf"
    
    if [[ ! -f "/etc/stunnel/stunnel.pem" ]] && [[ "$PROTOCOL" == "ssl" ]]; then
        mkdir -p /etc/stunnel
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout /etc/stunnel/stunnel.key \
            -out /etc/stunnel/stunnel.crt \
            -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost" 2>/dev/null
        cat /etc/stunnel/stunnel.crt /etc/stunnel/stunnel.key > /etc/stunnel/stunnel.pem
        chmod 600 /etc/stunnel/stunnel.pem
    fi
    
    case $PROTOCOL in
        tcp)
            if [[ $SERVER_TYPE -eq 2 ]]; then
                exec_start="/usr/bin/socat TCP-LISTEN:${LOCAL_PORT},reuseaddr,fork,keepalive TCP:127.0.0.1:${DEST_PORT}"
            else
                exec_start="/usr/bin/socat TCP:127.0.0.1:${DEST_PORT} TCP:${OUTSIDE_IP}:${OUTSIDE_PORT},forever,intervall=${RETRY_INTERVAL}"
            fi
            ;;
        ssl)
            if [[ $SERVER_TYPE -eq 2 ]]; then
                exec_start="/usr/bin/socat OPENSSL-LISTEN:${LOCAL_PORT},reuseaddr,fork,cert=/etc/stunnel/stunnel.pem,verify=0,keepalive TCP:127.0.0.1:${DEST_PORT}"
            else
                exec_start="/usr/bin/socat TCP:127.0.0.1:${DEST_PORT} OPENSSL:${OUTSIDE_IP}:${OUTSIDE_PORT},verify=0,forever,intervall=${RETRY_INTERVAL}"
            fi
            ;;
        websocket)
            if [[ $SERVER_TYPE -eq 2 ]]; then
                exec_start="/usr/local/bin/websocat --binary -s ${LOCAL_PORT} --restrict-udp --tcp 127.0.0.1:${DEST_PORT}"
            else
                exec_start="/usr/local/bin/websocat --binary ws://${OUTSIDE_IP}:${OUTSIDE_PORT} tcp:127.0.0.1:${DEST_PORT} --retry-ws --retry-interval ${RETRY_INTERVAL}"
            fi
            ;;
    esac
    
    cat > "$service_file" << EOF
[Unit]
Description=IranExTunnel - $tunnel_name
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=$exec_start
ExecStartPre=/bin/sleep 2
Restart=${AUTO_RESTART:+always}
RestartSec=${RETRY_INTERVAL}
StartLimitInterval=0
LimitNOFILE=65536
OOMScoreAdjust=-500

[Install]
WantedBy=multi-user.target
EOF
    
    log "INFO" "Systemd service created: irantunnel-$tunnel_name"
}

# ============================================
# نصب واچداگ (بدون خطای crontab)
# ============================================
install_watchdog() {
    log "STEP" "Installing watchdog for maximum stability..."
    
    cat > "$WATCHDOG_SCRIPT" << 'EOF'
#!/bin/bash
for config in /etc/iranextunnel/*.conf; do
    [ -f "$config" ] || continue
    source "$config"
    SERVICE_NAME="irantunnel-${TUNNEL_NAME}.service"
    if ! systemctl is-active --quiet "$SERVICE_NAME"; then
        echo "[$(date)] Restarting $SERVICE_NAME" >> /var/log/iranextunnel/watchdog.log
        systemctl restart "$SERVICE_NAME"
    fi
done
EOF

    chmod +x "$WATCHDOG_SCRIPT"
    
    # روش امن و بدون خطا برای افزودن به crontab
    if ! crontab -l 2>/dev/null | grep -q "$WATCHDOG_SCRIPT"; then
        (crontab -l 2>/dev/null; echo "* * * * * $WATCHDOG_SCRIPT") | crontab -
    fi
    
    log "INFO" "Watchdog installed successfully"
}

# ============================================
# راه‌اندازی تانل
# ============================================
start_tunnel() {
    local tunnel_name=$1
    log "STEP" "Starting tunnel: $tunnel_name"
    
    source "$CONFIG_DIR/$tunnel_name.conf"
    setup_firewall "$LOCAL_PORT"
    create_systemd_service "$tunnel_name"
    
    systemctl daemon-reload
    systemctl enable "irantunnel-${tunnel_name}.service"
    systemctl start "irantunnel-${tunnel_name}.service"
    
    if systemctl is-active --quiet "irantunnel-${tunnel_name}.service"; then
        echo -e "\n${GREEN}════════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}🎉 TUNNEL IS RUNNING!${NC}"
        echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
        echo -e "${WHITE}📋 Connection Details:${NC}"
        echo -e "   Name: ${YELLOW}$tunnel_name${NC}"
        echo -e "   Protocol: ${YELLOW}$PROTOCOL${NC}"
        echo -e "   Local Port: ${YELLOW}$LOCAL_PORT${NC}"
        echo -e "   Dest Port: ${YELLOW}$DEST_PORT${NC}"
        
        if [[ $SERVER_TYPE -eq 1 ]]; then
            echo -e "   Outside Server: ${YELLOW}$OUTSIDE_IP:$OUTSIDE_PORT${NC}"
        else
            echo -e "   Server IP: ${YELLOW}$SERVER_IP${NC}"
        fi
        
        echo -e "\n${WHITE}📊 Management Commands:${NC}"
        echo -e "   Status: ${YELLOW}systemctl status irantunnel-$tunnel_name${NC}"
        echo -e "   Stop: ${YELLOW}systemctl stop irantunnel-$tunnel_name${NC}"
        echo -e "   Logs: ${YELLOW}journalctl -u irantunnel-$tunnel_name -f${NC}"
        echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}\n"
        log "INFO" "Tunnel $tunnel_name started successfully"
    else
        log "ERROR" "Failed to start tunnel $tunnel_name"
        return 1
    fi
}

# ============================================
# منوی اصلی
# ============================================
show_menu() {
    echo -e "\n${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}📋 MAIN MENU${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo -e "  ${GREEN}1)${NC} Create New Tunnel"
    echo -e "  ${GREEN}2)${NC} List Active Tunnels"
    echo -e "  ${GREEN}3)${NC} Tunnel Status"
    echo -e "  ${GREEN}4)${NC} Stop a Tunnel"
    echo -e "  ${GREEN}5)${NC} Restart a Tunnel"
    echo -e "  ${GREEN}6)${NC} View Logs"
    echo -e "  ${GREEN}7)${NC} Remove a Tunnel"
    echo -e "  ${GREEN}8)${NC} Exit"
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
    read -p "👉 Select option [1-8]: " MENU_CHOICE
}

show_status() {
    echo -e "\n${BLUE}📊 Tunnels Status:${NC}"
    for config in "$CONFIG_DIR"/*.conf 2>/dev/null; do
        if [[ -f "$config" ]]; then
            source "$config"
            if systemctl is-active --quiet "irantunnel-${TUNNEL_NAME}.service"; then
                echo -e "${GREEN}   ✓ $TUNNEL_NAME: RUNNING${NC}"
            else
                echo -e "${RED}   ✗ $TUNNEL_NAME: STOPPED${NC}"
            fi
        fi
    done
}

# ============================================
# اجرای اصلی
# ============================================
main() {
    print_banner
    check_root
    install_dependencies
    install_watchdog
    
    while true; do
        show_menu
        case $MENU_CHOICE in
            1)
                get_user_config
                start_tunnel "$TUNNEL_NAME"
                ;;
            2)
                echo -e "\n${BLUE}📋 Configured Tunnels:${NC}"
                ls -1 "$CONFIG_DIR"/*.conf 2>/dev/null | sed 's/.*\///' | sed 's/.conf//' || echo "   No tunnels configured"
                ;;
            3) show_status ;;
            4)
                show_status
                read -p "👉 Enter tunnel name to stop: " TUNNEL_NAME
                systemctl stop "irantunnel-${TUNNEL_NAME}.service" 2>/dev/null && log "INFO" "Stopped $TUNNEL_NAME"
                ;;
            5)
                show_status
                read -p "👉 Enter tunnel name to restart: " TUNNEL_NAME
                systemctl restart "irantunnel-${TUNNEL_NAME}.service" 2>/dev/null && log "INFO" "Restarted $TUNNEL_NAME"
                ;;
            6)
                echo -e "\n${BLUE}📄 Recent logs:${NC}"
                tail -30 "$LOG_DIR/tunnel.log" 2>/dev/null || echo "No logs yet"
                ;;
            7)
                show_status
                read -p "👉 Enter tunnel name to remove: " TUNNEL_NAME
                systemctl stop "irantunnel-${TUNNEL_NAME}.service" 2>/dev/null
                systemctl disable "irantunnel-${TUNNEL_NAME}.service" 2>/dev/null
                rm -f "/etc/systemd/system/irantunnel-${TUNNEL_NAME}.service"
                rm -f "$CONFIG_DIR/${TUNNEL_NAME}.conf"
                systemctl daemon-reload
                log "INFO" "Removed tunnel $TUNNEL_NAME"
                ;;
            8) 
                echo -e "${GREEN}👋 Goodbye!${NC}"
                exit 0
                ;;
            *) echo -e "${RED}Invalid option${NC}" ;;
        esac
        echo -e "\n${YELLOW}Press Enter to continue...${NC}"
        read
        print_banner
    done
}

main "$@"

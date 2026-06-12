#!/bin/bash

# ============================================
# IranExTunnel v3.0 - Professional Tunnel for Iran<->Outside
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
    echo -e "${WHITE}       Professional Iran<->Outside Tunnel Manager v3.0${NC}"
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
    
    # آپدیت سیستم
    apt update -qq 2>/dev/null
    
    # لیست کامل پیش‌نیازها
    local packages=(
        socat
        openssl
        curl
        wget
        net-tools
        ufw
        iptables
        nano
        htop
        nload
        tmux
        cron
        gcc
        make
        git
    )
    
    local installed=0
    local failed=0
    
    for pkg in "${packages[@]}"; do
        if dpkg -l | grep -q "^ii  $pkg "; then
            log "INFO" "✅ $pkg already installed"
            ((installed++))
        else
            log "INFO" "📦 Installing $pkg..."
            if apt install -y "$pkg" -qq 2>/dev/null; then
                log "INFO" "✅ $pkg installed"
                ((installed++))
            else
                log "WARN" "⚠️  Could not install $pkg (may not be needed)"
                ((failed++))
            fi
        fi
    done
    
    log "INFO" "Dependencies check completed: $installed installed, $failed failed"
    
    # نصب ابزارهای خاص از گیت‌هاب
    install_special_tools
}

# ============================================
# نصب ابزارهای مخصوص تانل
# ============================================
install_special_tools() {
    log "STEP" "Installing special tunneling tools..."
    
    # نصب bore
    if ! command -v bore &> /dev/null; then
        log "INFO" "Installing bore..."
        wget -q -O /usr/local/bin/bore https://github.com/ekzhang/bore/releases/latest/download/bore-cli_amd64-unknown-linux-musl
        chmod +x /usr/local/bin/bore
        log "INFO" "✅ Bore installed"
    fi
    
    # نصب chisel
    if ! command -v chisel &> /dev/null; then
        log "INFO" "Installing chisel..."
        wget -q -O /tmp/chisel.gz https://github.com/jpillora/chisel/releases/latest/download/chisel_linux_amd64.gz
        gunzip -c /tmp/chisel.gz > /usr/local/bin/chisel
        chmod +x /usr/local/bin/chisel
        rm /tmp/chisel.gz
        log "INFO" "✅ Chisel installed"
    fi
    
    # نصب websocat
    if ! command -v websocat &> /dev/null; then
        log "INFO" "Installing websocat..."
        wget -q -O /usr/local/bin/websocat https://github.com/vi/websocat/releases/latest/download/websocat_amd64-linux-static
        chmod +x /usr/local/bin/websocat
        log "INFO" "✅ Websocat installed"
    fi
}

# ============================================
# گرفتن تنظیمات از کاربر
# ============================================
get_user_config() {
    echo -e "\n${WHITE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}              TUNNEL CONFIGURATION SETUP${NC}"
    echo -e "${WHITE}════════════════════════════════════════════════════════════${NC}\n"
    
    log "STEP" "Please enter tunnel configuration:"
    
    # سرور یا کلاینت؟
    echo -e "\n${CYAN}📡 Server Type:${NC}"
    echo "  1) 🇮🇷 IRAN Server (Client mode - connects to outside)"
    echo "  2) 🌍 OUTSIDE Server (Server mode - waits for connection)"
    read -p "👉 Choose [1-2]: " SERVER_TYPE
    
    # نام تانل
    read -p "🔖 Tunnel Name [tunnel-main]: " TUNNEL_NAME
    TUNNEL_NAME=${TUNNEL_NAME:-tunnel-main}
    
    # نوع پروتکل
    echo -e "\n${CYAN}🔌 Protocol Type:${NC}"
    echo "  1) TCP Direct (fastest, less stealthy)"
    echo "  2) SSL/TLS (secure, recommended)"  
    echo "  3) WebSocket (most stealthy for strict networks)"
    echo "  4) HTTP/S (proxy-like)"
    read -p "👉 Choose [1-4]: " PROTOCOL_TYPE
    
    case $PROTOCOL_TYPE in
        1) PROTOCOL="tcp" ;;
        2) PROTOCOL="ssl" ;;
        3) PROTOCOL="websocket" ;;
        4) PROTOCOL="http" ;;
        *) PROTOCOL="ssl" ;;
    esac
    
    # پورت
    read -p "🔌 Local Port to listen on [443]: " LOCAL_PORT
    LOCAL_PORT=${LOCAL_PORT:-443}
    
    read -p "🎯 Destination Port on other side [22]: " DEST_PORT
    DEST_PORT=${DEST_PORT:-22}
    
    # اگر کلاینت هستیم، IP سرور خارج رو بگیر
    if [[ $SERVER_TYPE -eq 2 ]]; then
        # حالت سرور خارج
        log "INFO" "Configuring as OUTSIDE Server"
        SERVER_IP=$(curl -s ifconfig.me)
        log "INFO" "Your server IP: $SERVER_IP"
    else
        # حالت کلاینت ایران
        echo -e "\n${CYAN}🌍 Outside Server Details:${NC}"
        read -p "👉 Outside Server IP: " OUTSIDE_IP
        read -p "👉 Outside Server Port: " OUTSIDE_PORT
    fi
    
    # توکن احراز هویت
    read -p "🔑 Auth Token [auto-generate]: " AUTH_TOKEN
    if [[ -z "$AUTH_TOKEN" ]]; then
        AUTH_TOKEN=$(openssl rand -hex 16)
    fi
    log "INFO" "Auth Token: $AUTH_TOKEN (save this!)"
    
    # پایداری بالا
    echo -e "\n${CYAN}🛡️ Stability Settings (for maximum stability):${NC}"
    read -p "🔄 Auto-restart on failure? [Y/n]: " AUTO_RESTART
    AUTO_RESTART=${AUTO_RESTART:-Y}
    
    read -p "📊 Connection keepalive (seconds) [30]: " KEEPALIVE
    KEEPALIVE=${KEEPALIVE:-30}
    
    read -p "🔄 Max retry attempts [unlimited]: " MAX_RETRIES
    MAX_RETRIES=${MAX_RETRIES:-0}
    
    read -p "⏱️ Retry interval (seconds) [10]: " RETRY_INTERVAL
    RETRY_INTERVAL=${RETRY_INTERVAL:-10}
    
    # ذخیره تنظیمات
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_DIR/$TUNNEL_NAME.conf" << EOF
# IranExTunnel Configuration
TUNNEL_NAME="$TUNNEL_NAME"
SERVER_TYPE="$SERVER_TYPE"
PROTOCOL="$PROTOCOL"
LOCAL_PORT="$LOCAL_PORT"
DEST_PORT="$DEST_PORT"
AUTH_TOKEN="$AUTH_TOKEN"
AUTO_RESTART="$AUTO_RESTART"
KEEPALIVE="$KEEPALIVE"
MAX_RETRIES="$MAX_RETRIES"
RETRY_INTERVAL="$RETRY_INTERVAL"
EOF

    if [[ $SERVER_TYPE -eq 1 ]]; then
        echo "OUTSIDE_IP=\"$OUTSIDE_IP\"" >> "$CONFIG_DIR/$TUNNEL_NAME.conf"
        echo "OUTSIDE_PORT=\"$OUTSIDE_PORT\"" >> "$CONFIG_DIR/$TUNNEL_NAME.conf"
    else
        echo "SERVER_IP=\"$SERVER_IP\"" >> "$CONFIG_DIR/$TUNNEL_NAME.conf"
    fi
    
    log "INFO" "✅ Configuration saved to $CONFIG_DIR/$TUNNEL_NAME.conf"
}

# ============================================
# تنظیم فایروال خودکار
# ============================================
setup_firewall() {
    local port=$1
    
    log "STEP" "Configuring firewall for port $port..."
    
    # باز کردن پورت در UFW
    if command -v ufw &> /dev/null; then
        ufw allow "$port"/tcp 2>/dev/null || true
        log "INFO" "✅ Port $port opened in UFW"
    fi
    
    # باز کردن پورت در iptables
    if command -v iptables &> /dev/null; then
        iptables -I INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || true
        log "INFO" "✅ Port $port opened in iptables"
        
        # ذخیره تنظیمات iptables برای reboot
        if command -v iptables-save &> /dev/null; then
            iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
        fi
    fi
    
    # بهینه‌سازی شبکه برای پایداری
    log "STEP" "Optimizing network for stability..."
    
    cat >> /etc/sysctl.conf << EOF

# IranExTunnel Network Optimizations
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 5
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
EOF
    
    sysctl -p 2>/dev/null || true
    log "INFO" "✅ Network optimized for stability"
}

# ============================================
# ایجاد سرویس systemd با پایداری بالا
# ============================================
create_systemd_service() {
    local tunnel_name=$1
    local service_file="/etc/systemd/system/irantunnel-${tunnel_name}.service"
    local exec_start=""
    
    source "$CONFIG_DIR/$tunnel_name.conf"
    
    # ساخت اسکریپت wrapper برای مدیریت مجدد
    local wrapper_script="/usr/local/bin/tunnel-wrapper-${tunnel_name}.sh"
    
    case $PROTOCOL in
        tcp)
            if [[ $SERVER_TYPE -eq 2 ]]; then
                # سرور خارج
                exec_start="/usr/bin/socat TCP-LISTEN:${LOCAL_PORT},reuseaddr,fork,keepalive TCP:127.0.0.1:${DEST_PORT}"
            else
                # کلاینت ایران
                exec_start="/usr/bin/socat TCP:127.0.0.1:${DEST_PORT} TCP:${OUTSIDE_IP}:${OUTSIDE_PORT},forever,intervall=${RETRY_INTERVAL}"
            fi
            ;;
        ssl)
            # ساخت گواهی اگر لازم باشه
            if [[ ! -f "/etc/stunnel/stunnel.pem" ]]; then
                mkdir -p /etc/stunnel
                openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                    -keyout /etc/stunnel/stunnel.key \
                    -out /etc/stunnel/stunnel.crt \
                    -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost" 2>/dev/null
                cat /etc/stunnel/stunnel.crt /etc/stunnel/stunnel.key > /etc/stunnel/stunnel.pem
                chmod 600 /etc/stunnel/stunnel.pem
            fi
            
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
        http)
            if [[ $SERVER_TYPE -eq 2 ]]; then
                exec_start="/usr/bin/socat TCP-LISTEN:${LOCAL_PORT},reuseaddr,fork,keepalive TCP:127.0.0.1:${DEST_PORT}"
            else
                exec_start="/usr/local/bin/chisel client ${OUTSIDE_IP}:${OUTSIDE_PORT} ${LOCAL_PORT}:127.0.0.1:${DEST_PORT}"
            fi
            ;;
    esac
    
    # ایجاد فایل سرویس
    cat > "$service_file" << EOF
[Unit]
Description=IranExTunnel - $tunnel_name (Iran<->Outside)
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
StartLimitBurst=0
KillMode=process
KillSignal=SIGINT
SendSIGKILL=no

# بهینه‌سازی برای پایداری
LimitNOFILE=65536
LimitNPROC=65536
TasksMax=infinity
CPUQuota=200%
MemoryMax=512M

# محافظت در برابر kill شدن
OOMScoreAdjust=-500

[Install]
WantedBy=multi-user.target
EOF
    
    log "INFO" "✅ Systemd service created: irantunnel-$tunnel_name"
}

# ============================================
# ساخت Watchdog برای پایداری فوق‌العاده
# ============================================
create_watchdog() {
    log "STEP" "Creating watchdog for maximum stability..."
    
    cat > "$WATCHDOG_SCRIPT" << 'EOF'
#!/bin/bash

WATCHDOG_LOG="/var/log/iranextunnel/watchdog.log"
CONFIG_DIR="/etc/iranextunnel"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$WATCHDOG_LOG"
}

# بررسی سلامت هر تانل
for config in "$CONFIG_DIR"/*.conf; do
    if [[ -f "$config" ]]; then
        source "$config"
        SERVICE_NAME="irantunnel-${TUNNEL_NAME}.service"
        
        # بررسی سرویس
        if systemctl is-active --quiet "$SERVICE_NAME"; then
            log "✅ $SERVICE_NAME is running"
        else
            log "⚠️ $SERVICE_NAME is dead, restarting..."
            systemctl restart "$SERVICE_NAME"
            
            # اگر بازم بالا نیومد، ریستارت کامل
            sleep 5
            if ! systemctl is-active --quiet "$SERVICE_NAME"; then
                log "❌ $SERVICE_NAME failed, force restart..."
                systemctl stop "$SERVICE_NAME"
                sleep 2
                systemctl start "$SERVICE_NAME"
            fi
        fi
    fi
done

# بررسی اتصال شبکه
if ! ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
    log "⚠️ Network seems down, restarting network service..."
    systemctl restart networking
fi
EOF

    chmod +x "$WATCHDOG_SCRIPT"
    
    # افزودن به cron برای اجرای هر دقیقه
    crontab -l 2>/dev/null | grep -v "$WATCHDOG_SCRIPT" | crontab - 2>/dev/null
    (crontab -l 2>/dev/null; echo "* * * * * $WATCHDOG_SCRIPT") | crontab -
    
    log "INFO" "✅ Watchdog installed (runs every minute)"
}

# ============================================
# راه‌اندازی نهایی تانل
# ============================================
start_tunnel() {
    local tunnel_name=$1
    
    log "STEP" "Starting tunnel: $tunnel_name"
    
    # باز کردن پورت در فایروال
    source "$CONFIG_DIR/$tunnel_name.conf"
    setup_firewall "$LOCAL_PORT"
    
    # ایجاد سرویس
    create_systemd_service "$tunnel_name"
    
    # فعال کردن و شروع
    systemctl daemon-reload
    systemctl enable "irantunnel-${tunnel_name}.service"
    systemctl start "irantunnel-${tunnel_name}.service"
    
    if systemctl is-active --quiet "irantunnel-${tunnel_name}.service"; then
        log "INFO" "✅ Tunnel $tunnel_name started successfully!"
        
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
        echo -e "   Restart: ${YELLOW}systemctl restart irantunnel-$tunnel_name${NC}"
        echo -e "   Logs: ${YELLOW}journalctl -u irantunnel-$tunnel_name -f${NC}"
        echo -e "   Watchdog: ${YELLOW}systemctl status irantunnel-watchdog${NC}"
        echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}\n"
        
    else
        log "ERROR" "Failed to start tunnel $tunnel_name"
        return 1
    fi
}

# ============================================
# ایجاد سرویس watchdog systemd
# ============================================
create_watchdog_service() {
    cat > /etc/systemd/system/irantunnel-watchdog.service << EOF
[Unit]
Description=IranExTunnel Watchdog Service
After=network.target

[Service]
Type=simple
ExecStart=$WATCHDOG_SCRIPT
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable irantunnel-watchdog.service
    systemctl start irantunnel-watchdog.service
    
    log "INFO" "✅ Watchdog service created"
}

# ============================================
# منوی مدیریت
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
    echo -e "  ${GREEN}8)${NC} Network Stats"
    echo -e "  ${GREEN}9)${NC} Exit"
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
    read -p "👉 Select option [1-9]: " MENU_CHOICE
}

# ============================================
# نمایش وضعیت تانل‌ها
# ============================================
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
# نمایش آمار شبکه
# ============================================
show_network_stats() {
    echo -e "\n${BLUE}📈 Network Statistics:${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # پورت‌های باز
    echo -e "${WHITE}Open ports:${NC}"
    netstat -tlnp | grep -E "socat|websocat|chisel" | while read line; do
        echo -e "   ${GREEN}$line${NC}"
    done
    
    # ترافیک
    echo -e "\n${WHITE}Active connections:${NC}"
    ss -tn | grep -E ":(443|80|8080|8443)" | head -5
    
    # بار سیستم
    echo -e "\n${WHITE}System load:${NC}"
    uptime
    
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# ============================================
# اجرای اصلی
# ============================================
main() {
    print_banner
    check_root
    install_dependencies
    
    # ایجاد watchdog یکبار
    create_watchdog
    create_watchdog_service
    
    while true; do
        show_menu
        case $MENU_CHOICE in
            1)
                get_user_config
                if [[ -f "$CONFIG_DIR/$TUNNEL_NAME.conf" ]]; then
                    start_tunnel "$TUNNEL_NAME"
                fi
                ;;
            2)
                echo -e "\n${BLUE}📋 Configured Tunnels:${NC}"
                ls -1 "$CONFIG_DIR"/*.conf 2>/dev/null | sed 's/.*\///' | sed 's/.conf//' || echo -e "${YELLOW}   No tunnels configured${NC}"
                ;;
            3)
                show_status
                ;;
            4)
                show_status
                echo ""
                read -p "👉 Enter tunnel name to stop: " TUNNEL_TO_STOP
                if systemctl stop "irantunnel-${TUNNEL_TO_STOP}.service" 2>/dev/null; then
                    log "INFO" "Tunnel $TUNNEL_TO_STOP stopped"
                else
                    log "ERROR" "Tunnel not found"
                fi
                ;;
            5)
                show_status
                echo ""
                read -p "👉 Enter tunnel name to restart: " TUNNEL_TO_RESTART
                if systemctl restart "irantunnel-${TUNNEL_TO_RESTART}.service" 2>/dev/null; then
                    log "INFO" "Tunnel $TUNNEL_TO_RESTART restarted"
                else
                    log "ERROR" "Tunnel not found"
                fi
                ;;
            6)
                echo -e "\n${BLUE}📄 Recent logs:${NC}"
                tail -30 "$LOG_DIR/tunnel.log" 2>/dev/null || echo "No logs yet"
                ;;
            7)
                show_status
                echo ""
                read -p "👉 Enter tunnel name to remove: " TUNNEL_TO_REMOVE
                systemctl stop "irantunnel-${TUNNEL_TO_REMOVE}.service" 2>/dev/null
                systemctl disable "irantunnel-${TUNNEL_TO_REMOVE}.service" 2>/dev/null
                rm -f "/etc/systemd/system/irantunnel-${TUNNEL_TO_REMOVE}.service"
                rm -f "$CONFIG_DIR/${TUNNEL_TO_REMOVE}.conf"
                systemctl daemon-reload
                log "INFO" "Tunnel $TUNNEL_TO_REMOVE removed"
                ;;
            8)
                show_network_stats
                ;;
            9)
                echo -e "${GREEN}👋 Goodbye!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option${NC}"
                ;;
        esac
        echo -e "\n${YELLOW}Press Enter to continue...${NC}"
        read
        print_banner
    done
}

# اجرا
main "$@"

#!/bin/bash
# ============================================================
# ZIVPN Ultimate Control Panel - Fire Edition
# Author: officialOnePeseva
# Version: 3.0.0 (Full Functional)
# Description: Complete UDP VPN installer + user/bandwidth manager
# ============================================================

# --- COLOURS ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- REPO CONFIGURATION ---
REPO_USER="OfficialOnePesewa"
REPO_NAME="udp-zivpn"
RAW_URL="https://raw.githubusercontent.com/$REPO_USER/$REPO_NAME/main"
RELEASE_URL="https://github.com/$REPO_USER/$REPO_NAME/releases/download/v1.0.0"

CONFIG_FILE="/etc/zivpn/config.json"
BACKUP_DIR="/etc/zivpn/backups"
LOG_FILE="/var/log/zivpn.log"

# --- SYSTEM DETECTION ---
ARCH=$(uname -m)
case $ARCH in
    x86_64)  BINARY="udp-zivpn-linux-amd64" ;;
    aarch64) BINARY="udp-zivpn-linux-arm64" ;;
    *)       echo -e "${RED}Unsupported architecture: $ARCH${NC}"; exit 1 ;;
esac

# --- UTILITIES ---
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Please run as root (sudo).${NC}"
        exit 1
    fi
}

install_jq() {
    if ! command -v jq &>/dev/null; then
        echo -e "${YELLOW}Installing jq (JSON processor)...${NC}"
        apt-get update -qq && apt-get install -y jq
    fi
}

# --- INSTALLATION ---
install_zivpn() {
    echo -e "${GREEN}>>> Updating system...${NC}"
    apt-get update && apt-get upgrade -y
    systemctl stop zivpn.service 2>/dev/null

    install_jq

    echo -e "${GREEN}>>> Downloading ZIVPN binary from your release...${NC}"
    wget -q "$RELEASE_URL/$BINARY" -O /usr/local/bin/zivpn
    chmod +x /usr/local/bin/zivpn

    mkdir -p /etc/zivpn
    echo -e "${GREEN}>>> Downloading config.json from your repo...${NC}"
    wget -q "$RAW_URL/config.json" -O "$CONFIG_FILE"

    # Ensure config structure has users array if missing
    if ! jq -e '.users' "$CONFIG_FILE" >/dev/null 2>&1; then
        jq '. + {"users": []}' "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"
    fi

    # Set default password
    echo -e "${GREEN}>>> Setting default password: zi${NC}"
    jq '.config = ["zi"]' "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"

    echo -e "${GREEN}>>> Generating SSL certificates...${NC}"
    openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
        -subj "/C=US/ST=California/L=Los Angeles/O=Example Corp/OU=IT Department/CN=zivpn" \
        -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt"

    sysctl -w net.core.rmem_max=16777216 >/dev/null
    sysctl -w net.core.wmem_max=16777216 >/dev/null

    cat > /etc/systemd/system/zivpn.service <<EOF
[Unit]
Description=ZIVPN VPN Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/local/bin/zivpn server -c $CONFIG_FILE
Restart=always
RestartSec=3
Environment=ZIVPN_LOG_LEVEL=info
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable zivpn.service
    systemctl start zivpn.service

    # Firewall rules
    IFACE=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
    iptables -t nat -A PREROUTING -i $IFACE -p udp --dport 6000:19999 -j DNAT --to-destination :5667 2>/dev/null
    ufw allow 6000:19999/udp 2>/dev/null
    ufw allow 5667/udp 2>/dev/null

    ln -sf "$(realpath $0)" /usr/local/bin/opfbt
    chmod +x /usr/local/bin/opfbt

    mkdir -p "$BACKUP_DIR"

    echo -e "${GREEN}✅ ZIVPN Ultimate Control Panel installed!${NC}"
    echo -e "${YELLOW}👉 Type 'opfbt' anytime to open the control panel.${NC}"
}

# --- CORE FUNCTIONS ---
start_vpn()   { systemctl start zivpn && echo "ZIVPN started."; }
stop_vpn()    { systemctl stop zivpn && echo "ZIVPN stopped."; }
restart_vpn() { systemctl restart zivpn && echo "ZIVPN restarted."; }
status_vpn()  { systemctl status zivpn --no-pager; }

list_users() {
    echo -e "${CYAN}Username\tExpiry Date\t\tBandwidth Used/Limit${NC}"
    jq -r '.users[] | "\(.username)\t\(.expiry // "Never")\t\t\(.bw_used // 0)/\(.bw_limit // "Unlimited")"' "$CONFIG_FILE" 2>/dev/null || echo "No users found."
}

add_user() {
    read -p "Username: " user
    read -p "Password: " pass
    read -p "Expiry (YYYY-MM-DD) or 'never': " expiry
    read -p "Bandwidth limit in GB (0=unlimited): " bw_limit

    # Default values
    expiry_val="${expiry:-never}"
    bw_limit_val="${bw_limit:-0}"

    # Check if user exists
    if jq -e ".users[] | select(.username==\"$user\")" "$CONFIG_FILE" >/dev/null; then
        echo -e "${RED}User already exists.${NC}"
        return
    fi

    # Add user
    jq ".users += [{\"username\":\"$user\", \"password\":\"$pass\", \"expiry\":\"$expiry_val\", \"bw_limit\":$bw_limit_val, \"bw_used\":0}]" "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"
    echo -e "${GREEN}User $user added.${NC}"
    restart_vpn >/dev/null
}

remove_user() {
    read -p "Username to remove: " user
    if ! jq -e ".users[] | select(.username==\"$user\")" "$CONFIG_FILE" >/dev/null; then
        echo -e "${RED}User not found.${NC}"
        return
    fi
    jq "del(.users[] | select(.username==\"$user\"))" "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"
    echo -e "${GREEN}User $user removed.${NC}"
    restart_vpn >/dev/null
}

renew_user() {
    read -p "Username to renew/extend: " user
    if ! jq -e ".users[] | select(.username==\"$user\")" "$CONFIG_FILE" >/dev/null; then
        echo -e "${RED}User not found.${NC}"
        return
    fi
    current_expiry=$(jq -r ".users[] | select(.username==\"$user\") | .expiry" "$CONFIG_FILE")
    echo "Current expiry: $current_expiry"
    read -p "New expiry (YYYY-MM-DD) or 'never': " new_expiry
    jq "(.users[] | select(.username==\"$user\") | .expiry) = \"$new_expiry\"" "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"
    echo -e "${GREEN}Expiry updated.${NC}"
}

cleanup_expired() {
    today=$(date +%Y-%m-%d)
    expired_users=$(jq -r ".users[] | select(.expiry != \"never\" and .expiry < \"$today\") | .username" "$CONFIG_FILE")
    if [[ -z "$expired_users" ]]; then
        echo "No expired users."
        return
    fi
    echo "Expired users:"
    echo "$expired_users"
    read -p "Remove all expired users? (y/N): " confirm
    if [[ "$confirm" == "y" ]]; then
        jq "del(.users[] | select(.expiry != \"never\" and .expiry < \"$today\"))" "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"
        echo -e "${GREEN}Expired users removed.${NC}"
        restart_vpn >/dev/null
    fi
}

connection_stats() {
    echo -e "${CYAN}Active connections:${NC}"
    ss -unap | grep zivpn | wc -l
}

bandwidth_expiry() {
    list_users
}

reset_bandwidth() {
    read -p "Reset bandwidth for which user? (all/username): " target
    if [[ "$target" == "all" ]]; then
        jq '.users[].bw_used = 0' "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"
        echo -e "${GREEN}All bandwidth counters reset.${NC}"
    else
        if ! jq -e ".users[] | select(.username==\"$target\")" "$CONFIG_FILE" >/dev/null; then
            echo -e "${RED}User not found.${NC}"
            return
        fi
        jq "(.users[] | select(.username==\"$target\") | .bw_used) = 0" "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"
        echo -e "${GREEN}Bandwidth for $target reset.${NC}"
    fi
}

speed_test() {
    if ! command -v speedtest-cli &>/dev/null; then
        apt-get install -y speedtest-cli
    fi
    speedtest-cli --simple
}

live_logs() {
    journalctl -u zivpn -f
}

backup_data() {
    mkdir -p "$BACKUP_DIR"
    backup_file="$BACKUP_DIR/zivpn-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    tar -czf "$backup_file" -C /etc zivpn
    echo -e "${GREEN}Backup saved to: $backup_file${NC}"
}

restore_backup() {
    echo "Available backups:"
    ls -1 "$BACKUP_DIR"
    read -p "Enter backup filename to restore: " backup_name
    if [[ -f "$BACKUP_DIR/$backup_name" ]]; then
        systemctl stop zivpn
        tar -xzf "$BACKUP_DIR/$backup_name" -C /etc
        systemctl start zivpn
        echo -e "${GREEN}Backup restored.${NC}"
    else
        echo -e "${RED}File not found.${NC}"
    fi
}

change_port_range() {
    read -p "New start port (default 6000): " start_port
    read -p "New end port (default 19999): " end_port
    start_port=${start_port:-6000}
    end_port=${end_port:-19999}
    # Update iptables
    IFACE=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
    iptables -t nat -F PREROUTING
    iptables -t nat -A PREROUTING -i $IFACE -p udp --dport $start_port:$end_port -j DNAT --to-destination :5667
    ufw delete allow 6000:19999/udp 2>/dev/null
    ufw allow $start_port:$end_port/udp
    echo -e "${GREEN}Port range changed to $start_port:$end_port${NC}"
}

auto_update() {
    echo -e "${YELLOW}Checking for updates...${NC}"
    wget -q "$RAW_URL/zi.sh" -O /tmp/zi.sh.new
    if diff /tmp/zi.sh.new "$(realpath $0)" >/dev/null; then
        echo "Already up-to-date."
    else
        read -p "New version found. Update now? (y/N): " confirm
        if [[ "$confirm" == "y" ]]; then
            cp /tmp/zi.sh.new "$(realpath $0)"
            chmod +x "$(realpath $0)"
            echo -e "${GREEN}Updated. Restart the panel.${NC}"
        fi
    fi
    rm /tmp/zi.sh.new
}

set_connection_limit() {
    read -p "Maximum concurrent connections per user (default 2): " limit
    limit=${limit:-2}
    jq ".max_connections_per_user = $limit" "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"
    restart_vpn >/dev/null
    echo -e "${GREEN}Connection limit set to $limit.${NC}"
}

trial_user() {
    trial_name="trial_$(date +%s | tail -c 5)"
    trial_pass=$(openssl rand -base64 6)
    expiry=$(date -d "+1 day" +%Y-%m-%d)
    jq ".users += [{\"username\":\"$trial_name\", \"password\":\"$trial_pass\", \"expiry\":\"$expiry\", \"bw_limit\":5, \"bw_used\":0}]" "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"
    restart_vpn >/dev/null
    echo -e "${GREEN}Trial user created:${NC}"
    echo "Username: $trial_name"
    echo "Password: $trial_pass"
    echo "Expires: $expiry"
    echo "Bandwidth limit: 5 GB"
}

uninstall_zivpn() {
    read -p "Are you sure you want to completely remove ZIVPN? (y/N) " confirm
    [[ "$confirm" != "y" ]] && return
    systemctl stop zivpn
    systemctl disable zivpn
    rm -f /usr/local/bin/zivpn /usr/local/bin/opfbt /etc/systemd/system/zivpn.service
    rm -rf /etc/zivpn
    iptables -t nat -F PREROUTING 2>/dev/null
    echo "ZIVPN uninstalled."
}

# --- MAIN MENU ---
show_menu() {
    clear
    echo -e "${BLUE}================================================${NC}"
    echo -e "${GREEN}   ZIVPN Ultimate Control Panel - Fire Edition${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo -e "Service: $(systemctl is-active zivpn)   IP: $(curl -s ifconfig.me)   Ports: 6000:19999"
    echo -e "${BLUE}------------------------------------------------${NC}"
    echo -e " 1) Start ZIVPN         11) Bandwidth + Expiry"
    echo -e " 2) Stop ZIVPN          12) Reset Bandwidth"
    echo -e " 3) Restart ZIVPN       13) Speed Test"
    echo -e " 4) Status              14) Live Logs"
    echo -e " 5) List Users+Expiry   15) Backup All Data"
    echo -e " 6) Add User            16) Restore Backup"
    echo -e " 7) Remove User         17) Change Port Range"
    echo -e " 8) Renew/Extend User   18) Auto-Update ZIVPN"
    echo -e " 9) Cleanup Expired     19) Set Connection Limit"
    echo -e "10) Connection Stats    20) Trial/Test User"
    echo -e "${BLUE}------------------------------------------------${NC}"
    echo -e "99) UNINSTALL (DANGER)   0) Exit"
    echo -e "${BLUE}================================================${NC}"
}

# --- MENU LOOP ---
menu_loop() {
    while true; do
        show_menu
        read -p "Choose an option: " choice
        case $choice in
            1) start_vpn ;;
            2) stop_vpn ;;
            3) restart_vpn ;;
            4) status_vpn ;;
            5) list_users ;;
            6) add_user ;;
            7) remove_user ;;
            8) renew_user ;;
            9) cleanup_expired ;;
            10) connection_stats ;;
            11) bandwidth_expiry ;;
            12) reset_bandwidth ;;
            13) speed_test ;;
            14) live_logs ;;
            15) backup_data ;;
            16) restore_backup ;;
            17) change_port_range ;;
            18) auto_update ;;
            19) set_connection_limit ;;
            20) trial_user ;;
            99) uninstall_zivpn ;;
            0) exit 0 ;;
            *) echo -e "${RED}Invalid option${NC}" ;;
        esac
        read -p "Press Enter to continue..."
    done
}

# --- ENTRY POINT ---
check_root
if [[ "$1" == "--install" ]] || [[ ! -f /usr/local/bin/zivpn ]]; then
    install_zivpn
fi
menu_loop

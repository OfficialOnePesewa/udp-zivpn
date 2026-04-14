#!/bin/bash
# ============================================================
# ZIVPN Ultimate Control Panel - Fire Edition
# Author: officialOnePeseva
# Version: 3.0.0
# Description: All-in-one UDP VPN installer + management menu
# ============================================================

# --- COLOURS ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- SET REPO URL (YOUR REPOSITORY) ---
REPO_USER="OfficialOnePesewa"
REPO_NAME="udp-zivpn"
RAW_URL="https://raw.githubusercontent.com/$REPO_USER/$REPO_NAME/main"
RELEASE_URL="https://github.com/$REPO_USER/$REPO_NAME/releases/download/v1.0.0"

# --- SYSTEM DETECTION ---
ARCH=$(uname -m)
case $ARCH in
    x86_64)  BINARY="udp-zivpn-linux-amd64" ;;
    aarch64) BINARY="udp-zivpn-linux-arm64" ;;
    *)       echo -e "${RED}Unsupported architecture: $ARCH${NC}"; exit 1 ;;
esac

# --- INSTALLATION FUNCTION ---
install_zivpn() {
    echo -e "${GREEN}>>> Updating system...${NC}"
    apt-get update && apt-get upgrade -y
    systemctl stop zivpn.service 2>/dev/null

    echo -e "${GREEN}>>> Downloading ZIVPN binary from your release...${NC}"
    wget -q "$RELEASE_URL/$BINARY" -O /usr/local/bin/zivpn
    chmod +x /usr/local/bin/zivpn

    mkdir -p /etc/zivpn
    echo -e "${GREEN}>>> Downloading config.json from your repo...${NC}"
    wget -q "$RAW_URL/config.json" -O /etc/zivpn/config.json

    echo -e "${GREEN}>>> Generating SSL certificates...${NC}"
    openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
        -subj "/C=US/ST=California/L=Los Angeles/O=Example Corp/OU=IT Department/CN=zivpn" \
        -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt"

    sysctl -w net.core.rmem_max=16777216 >/dev/null
    sysctl -w net.core.wmem_max=16777216 >/dev/null

    # --- REMOVE ONE-TIME PASSWORD PROMPT (set default 'zi') ---
    echo -e "${GREEN}>>> Setting default password: zi${NC}"
    sed -i -E 's/"config": ?\[[[:space:]]*"zi"[[:space:]]*\]/"config": ["zi"]/g' /etc/zivpn/config.json

    cat > /etc/systemd/system/zivpn.service <<EOF
[Unit]
Description=ZIVPN VPN Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/local/bin/zivpn server -c /etc/zivpn/config.json
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
    iptables -t nat -A PREROUTING -i $IFACE -p udp --dport 6000:19999 -j DNAT --to-destination :5667
    ufw allow 6000:19999/udp
    ufw allow 5667/udp

    # Create menu command (opfbt)
    ln -sf "$(realpath $0)" /usr/local/bin/opfbt
    chmod +x /usr/local/bin/opfbt

    echo -e "${GREEN}✅ ZIVPN Ultimate Control Panel installed!${NC}"
    echo -e "${YELLOW}👉 Type 'opfbt' anytime to open the control panel.${NC}"
}

# --- MENU FUNCTIONS (implement as needed) ---
start_vpn()   { systemctl start zivpn && echo "ZIVPN started."; }
stop_vpn()    { systemctl stop zivpn && echo "ZIVPN stopped."; }
restart_vpn() { systemctl restart zivpn && echo "ZIVPN restarted."; }
status_vpn()  { systemctl status zivpn --no-pager; }

list_users() {
    echo -e "${YELLOW}Active users (from config.json):${NC}"
    grep -o '"config": \[.*\]' /etc/zivpn/config.json | grep -o '"[^"]*"' | tr -d '"'
}

# (Add your own implementations for other menu items here)
add_user()          { echo "Feature coming soon."; }
remove_user()       { echo "Feature coming soon."; }
renew_user()        { echo "Feature coming soon."; }
cleanup_expired()   { echo "Feature coming soon."; }
connection_stats()  { echo "Feature coming soon."; }
bandwidth_expiry()  { echo "Feature coming soon."; }
reset_bandwidth()   { echo "Feature coming soon."; }
speed_test()        { curl -s https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py | python3 -; }
live_logs()         { journalctl -u zivpn -f; }
backup_data()       { echo "Feature coming soon."; }
restore_backup()    { echo "Feature coming soon."; }
change_port_range() { echo "Feature coming soon."; }
auto_update()       { echo "Feature coming soon."; }
set_conn_limit()    { echo "Feature coming soon."; }
trial_user()        { echo "Feature coming soon."; }

uninstall_zivpn() {
    read -p "Are you sure you want to completely remove ZIVPN? (y/N) " confirm
    [[ "$confirm" != "y" ]] && return
    systemctl stop zivpn
    systemctl disable zivpn
    rm -f /usr/local/bin/zivpn /usr/local/bin/opfbt /etc/systemd/system/zivpn.service
    rm -rf /etc/zivpn
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
            19) set_conn_limit ;;
            20) trial_user ;;
            99) uninstall_zivpn ;;
            0) exit 0 ;;
            *) echo -e "${RED}Invalid option${NC}" ;;
        esac
        read -p "Press Enter to continue..."
    done
}

# --- ENTRY POINT ---
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Please run as root (sudo).${NC}"
    exit 1
fi

if [[ "$1" == "--install" ]] || [[ ! -f /usr/local/bin/zivpn ]]; then
    install_zivpn
fi

menu_loop

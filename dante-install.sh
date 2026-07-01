#!/bin/bash

# Dante SOCKS5 Proxy - Simple One-Click Installer
# Port: 1088 | Auth: None (Open Proxy)
# ⚠️  WARNING: This creates an OPEN proxy accessible to anyone

set -e

# Check root
[[ $EUID -ne 0 ]] && { echo "Run as root: sudo bash $0"; exit 1; }

# Colors
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; NC='\033[0m'

echo -e "${B}Installing Dante SOCKS5 Proxy...${NC}"

# Update and install
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq dante-server >/dev/null 2>&1

# Detect interface
IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
[[ -z "$IFACE" ]] && IFACE="eth0"

echo -e "${B}Creating configuration...${NC}"

# Backup existing config
[[ -f /etc/danted.conf ]] && cp /etc/danted.conf /etc/danted.conf.backup.$(date +%s)

# Write config directly (no heredoc)
cat > /etc/danted.conf << 'ENDCONF'
logoutput: /var/log/danted.log
loglevel: error

internal: 0.0.0.0 port = 1088
external: INTERFACE_PLACEHOLDER

socksmethod: none
clientmethod: none

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: error
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    protocol: tcp udp
    log: error
}
ENDCONF

# Replace placeholder
sed -i "s/INTERFACE_PLACEHOLDER/$IFACE/" /etc/danted.conf

# Create log file
touch /var/log/danted.log
chmod 644 /var/log/danted.log

# Create/update systemd service
cat > /etc/systemd/system/danted.service << 'ENDSVC'
[Unit]
Description=Dante SOCKS5 Proxy
After=network.target

[Service]
Type=forking
PIDFile=/run/danted.pid
ExecStart=/usr/sbin/danted -f /etc/danted.conf
Restart=on-failure

[Install]
WantedBy=multi-user.target
ENDSVC

# Reload and start
systemctl daemon-reload
systemctl enable danted >/dev/null 2>&1
systemctl restart danted

sleep 2

# Verify
if systemctl is-active --quiet danted; then
    PUBLIC_IP=$(curl -s -4 --max-time 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    
    echo ""
    echo -e "${G}✓ Dante SOCKS5 Proxy is running!${NC}"
    echo ""
    echo "  Host: $PUBLIC_IP"
    echo "  Port: 1088"
    echo "  Type: SOCKS5 (no auth)"
    echo ""
    echo "Test: curl --proxy socks5://$PUBLIC_IP:1088 https://ipinfo.io/ip"
    echo ""
    echo -e "${Y}⚠️  This is an OPEN proxy - anyone can use it!${NC}"
    echo "Monitor: journalctl -u danted -f"
    echo "Stop: systemctl stop danted"
    echo ""
else
    echo -e "${R}✗ Failed to start danted${NC}"
    echo "Logs: journalctl -u danted -n 50"
    exit 1
fi

#!/bin/bash
# ==============================================================================
# WARNING: OPEN PROXY CONFIGURATION (ZERO AUTHENTICATION)
# This script installs a Dante SOCKS5 proxy with NO password protection.
# By running this, your proxy will be publicly accessible to the entire internet.
# 
# SEVERE SECURITY RISKS INCLUDE:
# - Abuse by malicious actors (botnets, credential stuffing, spam campaigns).
# - Complete bandwidth exhaustion and potential overage charges.
# - Immediate violation of almost all VPS provider Terms of Service (ToS).
# - Potential legal liability for malicious traffic routed through your IP.
# ==============================================================================

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Error: Please run as root or with sudo."
  exit 1
fi

echo "Starting Dante SOCKS5 open proxy installation..."

# 1. Update package lists and install dante-server
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y dante-server

# 2. Determine the active external network interface for Dante config
# Dante requires a specific interface name for outbound traffic, not just an IP.
EXT_IFACE=$(ip route get 8.8.8.8 | grep -Po '(?<=dev )[^ ]+' | head -n 1)

if [ -z "$EXT_IFACE" ]; then
    echo "Could not automatically determine the external network interface. Defaulting to eth0."
    EXT_IFACE="eth0"
fi

echo "Detected external interface: $EXT_IFACE"

# 3. Generate idempotent /etc/danted.conf
# Back up existing configuration if it exists
if [ -f /etc/danted.conf ]; then
    mv /etc/danted.conf /etc/danted.conf.backup_$(date +%s)
fi

cat > /etc/danted.conf <<EOF
# Dante SOCKS5 Configuration
logoutput: syslog

# Listen on all IPv4 interfaces on port 1088
internal: 0.0.0.0 port = 1088

# Route outbound traffic through the primary network interface
external: $EXT_IFACE

# Require SOCKS5 (no authentication)
socksmethod: none
clientmethod: none

# Allow all clients to connect to the proxy
client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: error connect disconnect
}

# Allow all traffic to pass through the proxy
socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    command: bind connect udpassociate
    log: error connect disconnect
}
EOF

# 4. Enable and start danted service via systemd
echo "Applying configuration and restarting Dante..."
systemctl enable danted
systemctl restart danted

# 5. Verify service is running
sleep 2 # Give systemd a moment to bring up the service
if systemctl is-active --quiet danted; then
    echo "Dante service is ACTIVE."
else
    echo "Warning: Dante service failed to start. Check 'systemctl status danted' for details."
fi

# Check if listening on 1088
if ss -tuln | grep -q ":1088 "; then
    echo "Verified: Dante is actively listening on port 1088."
else
    echo "Warning: Cannot detect Dante listening on port 1088."
fi

# 6. Display connection instructions
PUBLIC_IP=$(curl -s -4 ifconfig.me || wget -qO- ipv4.icanhazip.com)
if [ -z "$PUBLIC_IP" ]; then
    PUBLIC_IP="<YOUR_VPS_IP>"
fi

echo ""
echo "============================================================"
echo "INSTALLATION COMPLETE"
echo "============================================================"
echo "Your open SOCKS5 proxy is now running."
echo "Connection Details:"
echo "IP Address : $PUBLIC_IP"
echo "Port       : 1088"
echo "Protocol   : SOCKS5"
echo "Auth       : None (Open)"
echo ""
echo "WARNING: This proxy is completely unprotected. Anyone can use it."
echo "============================================================"

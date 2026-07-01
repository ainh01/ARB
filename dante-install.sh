#!/bin/bash
set -euo pipefail

[[ $EUID -ne 0 ]] && { echo "Run as root"; exit 1; }

DANTE_PORT=1088
DANTE_CONF="/etc/danted.conf"
SERVICE_NAME="danted"

get_primary_interface() {
    ip route | grep '^default' | awk '{print $5}' | head -n1
}

get_external_ip() {
    local interface=$(get_primary_interface)
    ip -4 addr show "$interface" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1
}

apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y dante-server

INTERFACE=$(get_primary_interface)

cat > "$DANTE_CONF" << EOF
logoutput: syslog
internal: 0.0.0.0 port = $DANTE_PORT
external: $INTERFACE
socksmethod: none
clientmethod: none
user.privileged: root
user.unprivileged: nobody

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect error
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    command: connect
    log: connect disconnect error
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    command: bind
    log: connect disconnect error
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    command: udpassociate
    log: connect disconnect error
}
EOF

systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"

sleep 2

EXTERNAL_IP=$(get_external_ip)

echo ""
echo "SOCKS5 proxy installed successfully"
echo "Address: $EXTERNAL_IP:$DANTE_PORT"
echo "No authentication required"
echo ""
echo "Test: curl -x socks5://$EXTERNAL_IP:$DANTE_PORT https://icanhazip.com"
echo ""

#!/bin/bash  
#  
# Dante SOCKS5 Proxy Server Installation Script for Ubuntu  
# ========================================================  
#  
# ⚠️  CRITICAL SECURITY WARNING ⚠️  
#  
# This script installs and configures a SOCKS5 proxy server with ZERO AUTHENTICATION.  
# This means ANYONE who discovers your server's IP address and port can use it as a proxy.  
#  
# RISKS OF RUNNING AN OPEN PROXY:  
# --------------------------------  
# 1. ABUSE BY MALICIOUS ACTORS: Hackers, spammers, and criminals may route malicious  
#    traffic through your server, making YOU the apparent source of attacks.  
#  
# 2. BANDWIDTH EXHAUSTION: Once discovered (often within hours), your proxy may be  
#    added to proxy lists and consumed by bots, exhausting your bandwidth allocation.  
#  
# 3. IP BLACKLISTING: Your server IP will likely be blacklisted by spam databases,  
#    CDNs (Cloudflare, etc.), and services, making it unusable for legitimate purposes.  
#  
# 4. VPS PROVIDER VIOLATIONS: Most hosting providers explicitly prohibit open proxies  
#    in their Terms of Service. Your VPS may be suspended WITHOUT WARNING.  
#  
# 5. LEGAL LIABILITY: If your proxy is used for illegal activities (hacking, fraud,  
#    child exploitation), you may face legal investigation. "I didn't know" is not  
#    a valid legal defense in many jurisdictions.  
#  
# 6. RESOURCE CONSUMPTION: Unexpected CPU and memory usage from proxy abuse can cause  
#    service degradation or additional hosting charges.  
#  
# RECOMMENDED ALTERNATIVES:  
# -------------------------  
# - Use authentication (socksmethod: username)  
# - Implement IP whitelisting (restrict source IPs in danted.conf)  
# - Use WireGuard or OpenVPN for personal VPN access instead  
# - Deploy behind a reverse proxy with rate limiting  
#  
# BY RUNNING THIS SCRIPT, YOU ACKNOWLEDGE THESE RISKS AND ACCEPT FULL RESPONSIBILITY.  
#  
# Usage: curl -sSL <script-url> | sudo bash  
#    or: sudo bash dante-install.sh  

set -euo pipefail  # Exit on error, undefined variables, and pipe failures  

# Color codes for output  
RED='\033[0;31m'  
YELLOW='\033[1;33m'  
GREEN='\033[0;32m'  
BLUE='\033[0;34m'  
NC='\033[0m' # No Color  

# Configuration variables  
SOCKS_PORT=1088  
CONFIG_FILE="/etc/danted.conf"  
SERVICE_NAME="danted"  
BACKUP_SUFFIX=".backup.$(date +%Y%m%d_%H%M%S)"  
DANTE_LOG_FILE="/var/log/danted.log" # Define log file variable  

# Logging functions  
log_info() {  
    echo -e "${BLUE}[INFO]${NC} $1"  
}  

log_success() {  
    echo -e "${GREEN}[SUCCESS]${NC} $1"  
}  

log_warning() {  
    echo -e "${YELLOW}[WARNING]${NC} $1"  
}  

log_error() {  
    echo -e "${RED}[ERROR]${NC} $1"  
}  

# Check if running as root  
check_root() {  
    if [[ $EUID -ne 0 ]]; then  
        log_error "This script must be run as root or with sudo privileges"  
        exit 1  
    fi  
}  

# Detect Ubuntu version  
check_ubuntu_version() {  
    if [[ ! -f /etc/os-release ]]; then  
        log_error "Cannot detect OS version. /etc/os-release not found."  
        exit 1  
    fi  
    
    source /etc/os-release  
    
    if [[ "$ID" != "ubuntu" ]]; then  
        log_error "This script is designed for Ubuntu only. Detected: $ID"  
        exit 1  
    fi  
    
    # Extract major version  
    VERSION_MAJOR=$(echo "$VERSION_ID" | cut -d. -f1)  
    
    if [[ "$VERSION_MAJOR" -lt 20 ]]; then  
        log_warning "This script is tested on Ubuntu 20.04+. Detected: $VERSION_ID"  
        log_warning "Proceeding anyway, but compatibility is not guaranteed."  
    else  
        log_info "Detected Ubuntu $VERSION_ID - compatible"  
    fi  
}  

# Update package lists  
update_packages() {  
    log_info "Updating package lists..."  
    export DEBIAN_FRONTEND=noninteractive  
    apt-get update -qq > /dev/null 2>&1  
    log_success "Package lists updated"  
}  

# Install dante-server  
install_dante() {  
    if dpkg -l | grep -q "^ii  dante-server"; then  
        log_warning "dante-server is already installed. Skipping installation."  
        return 0  
    fi  
    
    log_info "Installing dante-server..."  
    export DEBIAN_FRONTEND=noninteractive  
    apt-get install -y -qq dante-server > /dev/null 2>&1  
    
    if [[ $? -eq 0 ]]; then  
        log_success "dante-server installed successfully"  
    else  
        log_error "Failed to install dante-server"  
        exit 1  
    fi  
}  

# FIX START: Add function to manage log file  
manage_dante_logfile() {  
    log_info "Ensuring Dante log file exists and has correct permissions..."  
    
    # Ensure the parent directory exists (though /var/log almost always does)  
    mkdir -p "$(dirname "$DANTE_LOG_FILE")"  
    
    # Create the log file if it doesn't exist  
    if [[ ! -f "$DANTE_LOG_FILE" ]]; then  
        touch "$DANTE_LOG_FILE"  
        if [[ $? -ne 0 ]]; then  
            log_error "Failed to create log file: $DANTE_LOG_FILE"  
            exit 1  
        fi  
        log_info "Created log file: $DANTE_LOG_FILE"  
    fi  

    # Determine the user/group danted runs as. Typically 'dante' on Ubuntu.  
    local dante_user="dante"  
    local dante_group="dante"  

    if ! id -u "$dante_user" >/dev/null 2>&1; then  
        log_warning "Dante user '$dante_user' not found. Checking for 'nobody' or using default root for log ownership (less secure)."  
        dante_user="root" # Fallback, less ideal for a dropped-privilege daemon  
        dante_group="root"  
        # More robust check might involve parsing danted.conf or service file for RunAsUser/Group  
    fi  

    # Set ownership and permissions  
    chown "$dante_user:$dante_group" "$DANTE_LOG_FILE"  
    chmod 640 "$DANTE_LOG_FILE" # Read/write for owner, read for group, no access for others  
    
    if [[ $? -eq 0 ]]; then  
        log_success "Dante log file '$DANTE_LOG_FILE' configured with owner $dante_user:$dante_group and permissions 640"  
    else  
        log_error "Failed to set ownership/permissions for '$DANTE_LOG_FILE'"  
        exit 1  
    fi  
}  
# FIX END  

# Backup existing configuration  
backup_config() {  
    if [[ -f "$CONFIG_FILE" ]]; then  
        log_info "Backing up existing configuration to ${CONFIG_FILE}${BACKUP_SUFFIX}"  
        cp "$CONFIG_FILE" "${CONFIG_FILE}${BACKUP_SUFFIX}"  
    fi  
}  

# Generate dante configuration  
generate_config() {  
    log_info "Generating dante configuration at $CONFIG_FILE..."  
    
    # Detect primary network interface (excluding loopback)  
    PRIMARY_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)  
    
    if [[ -z "$PRIMARY_INTERFACE" ]]; then  
        log_warning "Could not detect primary network interface. Using 'eth0' as fallback."  
        PRIMARY_INTERFACE="eth0"  
    else  
        log_info "Detected primary interface: $PRIMARY_INTERFACE"  
    fi  
    
    # Create configuration file  
    cat > "$CONFIG_FILE" <<'EOF'
# Dante SOCKS5 Proxy Configuration  
# Generated by automated installation script  
# WARNING: This is an OPEN PROXY with NO AUTHENTICATION  
#  
# Configuration timestamp: $(date)  
# Listening port: $SOCKS_PORT  
# Network interface: $PRIMARY_INTERFACE  

# Logging configuration  
logoutput: /var/log/danted.log
# Log level: error only (reduce log spam)  
# Options: connect disconnect error data  
loglevel: error  

# Internal interface - where dante listens for client connections  
internal: 0.0.0.0 port = 1088

# External interface - where dante makes outgoing connections  
external: eth0

# Authentication methods for SOCKS protocol  
# "none" = no authentication required (OPEN PROXY)  
socksmethod: none  

# Authentication methods for clients connecting to dante  
clientmethod: none  

# Client access rules (who can connect to the proxy server)  
# This rule allows ANY IP address to connect  
client pass {  
    from: 0.0.0.0/0 to: 0.0.0.0/0  
    log: error  
}  

# SOCKS access rules (where clients can connect through the proxy)  
# This rule allows proxying to ANY destination  
socks pass {  
    from: 0.0.0.0/0 to: 0.0.0.0/0  
    protocol: tcp udp  
    log: error  
}  

# Block access rules (currently none - everything is allowed)  
# Uncomment and customize to restrict destinations:  
# socks block {  
#     from: 0.0.0.0/0 to: 192.168.0.0/16  
#     log: connect error  
# }  
EOF

    # Now substitute the variables using sed
    sed -i "s|^# Configuration timestamp:.*|# Configuration timestamp: $(date)|" "$CONFIG_FILE"
    sed -i "s|^# Listening port:.*|# Listening port: $SOCKS_PORT|" "$CONFIG_FILE"
    sed -i "s|^# Network interface:.*|# Network interface: $PRIMARY_INTERFACE|" "$CONFIG_FILE"
    sed -i "s|^internal:.*|internal: 0.0.0.0 port = $SOCKS_PORT|" "$CONFIG_FILE"
    sed -i "s|^external:.*|external: $PRIMARY_INTERFACE|" "$CONFIG_FILE"
    sed -i "s|^logoutput:.*|logoutput: $DANTE_LOG_FILE|" "$CONFIG_FILE"

    if [[ $? -eq 0 ]]; then  
        log_success "Configuration file created successfully"  
    else  
        log_error "Failed to create configuration file"  
        exit 1  
    fi  
}  

# Validate configuration syntax  
validate_config() {  
    log_info "Validating dante configuration..."  
    
    # Dante doesn't have a built-in config validator, so we do basic checks  
    # A more robust check might involve 'danted -V' if it supports syntax check  
    # or attempting to start in test mode. For now, rely on file existence and key directives.  
    
    if [[ ! -f "$CONFIG_FILE" ]]; then  
        log_error "Configuration file not found at $CONFIG_FILE"  
        exit 1  
    fi  
    
    # Check for required directives  
    local required_directives=("internal" "external" "socksmethod" "clientmethod" "logoutput") # Added logoutput to required checks  
    local missing_directives=()  
    
    for directive in "${required_directives[@]}"; do  
        if ! grep -q "^[[:space:]]*${directive}:" "$CONFIG_FILE"; then  
            missing_directives+=("$directive")  
        fi  
    done  
    
    if [[ ${#missing_directives[@]} -gt 0 ]]; then  
        log_error "Configuration validation failed. Missing directives: ${missing_directives[*]}"  
        exit 1  
    fi  
    
    log_success "Configuration validation passed"  
}  

# Configure systemd service  
configure_service() {  
    log_info "Configuring systemd service..."  
    
    # Check if systemd service file exists  
    if [[ ! -f "/lib/systemd/system/danted.service" ]] && [[ ! -f "/etc/systemd/system/danted.service" ]]; then  
        log_warning "Systemd service file not found. Creating custom service file..."  
        
        cat > /etc/systemd/system/danted.service <<'EOF'
[Unit]  
Description=Dante SOCKS5 Proxy Server  
Documentation=man:danted(8) man:danted.conf(5)  
After=network.target  

[Service]  
Type=forking  
PIDFile=/run/danted.pid  
ExecStart=/usr/sbin/danted -f /etc/danted.conf  
ExecReload=/bin/kill -HUP $MAINPID  
Restart=on-failure  
RestartSec=5s  

[Install]  
WantedBy=multi-user.target  
EOF
    fi  
    
    # Reload systemd daemon to recognize any changes  
    systemctl daemon-reload  
    
    log_success "Systemd service configured"  
}  

# Enable and start service  
start_service() {  
    log_info "Enabling danted service to start on boot..."  
    systemctl enable "$SERVICE_NAME" > /dev/null 2>&1  
    
    # Stop service if already running (for idempotency)  
    if systemctl is-active --quiet "$SERVICE_NAME"; then  
        log_info "Service is already running. Restarting to apply new configuration..."  
        systemctl restart "$SERVICE_NAME"  
    else  
        log_info "Starting danted service..."  
        systemctl start "$SERVICE_NAME"  
    fi  
    
    # Wait a moment for service to initialize  
    sleep 2  
    
    # Verify service status  
    if systemctl is-active --quiet "$SERVICE_NAME"; then  
        log_success "Dante SOCKS5 proxy service is running"  
    else  
        log_error "Failed to start dante service"  
        log_info "Checking service status:"  
        systemctl status "$SERVICE_NAME" --no-pager  
        # Display logs from the service for easier debugging  
        journalctl -u "$SERVICE_NAME" --no-pager -n 20   
        exit 1  
    fi  
}  

# Verify listening port  
verify_listening() {  
    log_info "Verifying that dante is listening on port $SOCKS_PORT..."  
    
    # Check with netstat or ss  
    if command -v ss > /dev/null 2>&1; then  
        if ss -tlnp | grep -q ":$SOCKS_PORT"; then  
            log_success "Dante is listening on port $SOCKS_PORT"  
            return 0  
        fi  
    elif command -v netstat > /dev/null 2>&1; then  
        if netstat -tlnp | grep -q ":$SOCKS_PORT"; then  
            log_success "Dante is listening on port $SOCKS_PORT"  
            return 0  
        fi  
    fi  
    
    log_warning "Could not verify listening port with ss/netstat"  
    log_info "Attempting connection test..."  
    
    # Fallback: try to connect to the port  
    if timeout 2 bash -c "echo > /dev/tcp/127.0.0.1/$SOCKS_PORT" 2>/dev/null; then  
        log_success "Port $SOCKS_PORT is accepting connections"  
        return 0  
    else  
        log_error "Port $SOCKS_PORT does not appear to be listening"  
        log_info "Check service logs: journalctl -u $SERVICE_NAME -n 50"  
        return 1  
    fi  
}  

# Get public IP address  
get_public_ip() {  
    local ip=""  
    
    # Try multiple services in case one is down  
    ip=$(curl -s -4 --max-time 5 ifconfig.me 2>/dev/null) || \
    ip=$(curl -s -4 --max-time 5 icanhazip.com 2>/dev/null) || \
    ip=$(curl -s -4 --max-time 5 ipinfo.io/ip 2>/dev/null) || \
    ip=$(hostname -I | awk '{print $1}')  
    
    echo "$ip"  
}  

# Display connection information  
display_connection_info() {  
    log_info "================================"  
    log_success "INSTALLATION COMPLETE"  
    log_info "================================"  
    echo ""  
    
    local public_ip=$(get_public_ip)  
    
    if [[ -n "$public_ip" ]]; then  
        echo -e "${GREEN}Your SOCKS5 proxy is now running!${NC}"  
        echo ""  
        echo "Connection details:"  
        echo "  Protocol: SOCKS5"  
        echo "  Host:     $public_ip"  
        echo "  Port:     $SOCKS_PORT"  
        echo "  Auth:     None (open proxy)"  
        echo ""  
        echo "Connection string: socks5://${public_ip}:${SOCKS_PORT}"  
        echo ""  
        echo "Test with curl:"  
        echo "  curl --proxy socks5://${public_ip}:${SOCKS_PORT} https://ipinfo.io/ip"  
        echo ""  
    else  
        log_warning "Could not detect public IP address"  
        echo "Your proxy is listening on port $SOCKS_PORT"  
    fi  
    
    echo -e "${YELLOW}⚠️  SECURITY REMINDER ⚠️${NC}"  
    echo "This is an OPEN PROXY without authentication."  
    echo "Monitor your server for abuse:"  
    echo "  - Check logs: journalctl -u danted -f"  
    echo "  - Monitor bandwidth: vnstat or similar tools"  
    echo "  - Watch for abuse: tail -f $DANTE_LOG_FILE" # Updated log file path  
    echo ""  
    echo "To stop the proxy:"  
    echo "  sudo systemctl stop danted"  
    echo ""  
    echo "To disable auto-start:"  
    echo "  sudo systemctl disable danted"  
    echo ""  
}  

# Main execution  
main() {  
    echo ""  
    log_info "Starting Dante SOCKS5 Proxy Installation"  
    echo ""  
    
    check_root  
    check_ubuntu_version  
    update_packages  
    install_dante  
    
    # FIX: Call the new function to manage log file before configuring Dante  
    manage_dante_logfile   

    backup_config  
    generate_config  
    validate_config  
    configure_service  
    start_service  
    verify_listening  
    
    echo ""  
    display_connection_info  
}  

# Execute main function  
main

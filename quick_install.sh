#!/bin/bash
#########################################################################
# Quick Installation Script for Service Monitor
# For users who want default settings without interactive prompts
# Author: Max Haase - maxhaase@gmail.com
#########################################################################

# Default configuration
ADMIN_EMAIL="admin@example.com"  # CHANGE THIS
EMAIL_METHOD="sendmail"
SERVICES=("apache2" "nginx" "mariadb" "ssh")
ENABLE_SYSTEMD=true

echo "Service Monitor Quick Install"
echo "=============================="
echo "This will install with default settings:"
echo "Admin Email: $ADMIN_EMAIL"
echo "Email Method: $EMAIL_METHOD"
echo "Services: ${SERVICES[*]}"
echo "Mode: Systemd Daemon"
echo ""
read -p "Continue? [Y/n]: " confirm
confirm=${confirm:-"Y"}

if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

# Create a temporary config file
cat > /tmp/service_monitor_config << EOF
ADMIN_EMAIL="$ADMIN_EMAIL"
EMAIL_METHOD="$EMAIL_METHOD"
SERVICES_LIST=($(printf "\"%s\" " "${SERVICES[@]}"))
ENABLE_CRON=false
ENABLE_SYSTEMD=true
DAEMON_MODE=true
CHECK_INTERVAL=60
EOF

echo "Running installation..."
# Source the main install script with non-interactive mode
export NON_INTERACTIVE=1
source install_service_monitor.sh

echo "Quick installation complete!"

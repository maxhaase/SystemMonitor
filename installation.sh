#!/bin/bash
# Installation script for Service Monitor

echo "Installing Service Monitor..."

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root"
    exit 1
fi

# Check Python
if ! command -v python3 &> /dev/null; then
    echo "Installing Python 3..."
    apt-get update
    apt-get install -y python3 python3-pip
fi

# Create directories
mkdir -p /opt/service_monitor
mkdir -p /var/lib/service_monitor
mkdir -p /var/log

# Copy script
cp service_monitor.py /opt/service_monitor/
chmod +x /opt/service_monitor/service_monitor.py

# Create symlink for easy access
ln -sf /opt/service_monitor/service_monitor.py /usr/local/bin/service-monitor

# Install sendmail for email notifications
if ! command -v sendmail &> /dev/null; then
    echo "Installing sendmail for email notifications..."
    apt-get install -y sendmail
fi

# Create systemd service for daemon mode
cat > /etc/systemd/system/service-monitor.service << EOF
[Unit]
Description=Service Monitor Daemon
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/service_monitor/service_monitor.py
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=service_monitor

[Install]
WantedBy=multi-user.target
EOF

# Create logrotate config
cat > /etc/logrotate.d/service_monitor << EOF
/var/log/service_monitor.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 640 root root
}
EOF

echo "Installation complete!"
echo ""
echo "Next steps:"
echo "1. Edit configuration in /opt/service_monitor/service_monitor.py"
echo "2. Test with: sudo service-monitor"

echo "3. Enable systemd service: sudo systemctl enable service-monitor"
echo "4. Start daemon: sudo systemctl start service-monitor"
echo ""
echo "Or add to cron:"
echo "  */5 * * * * /usr/bin/python3 /opt/service_monitor/service_monitor.py"

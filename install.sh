#!/bin/bash

#########################################################################
# Installation Script for Service Monitor
# Author: Max Haase - maxhaase@gmail.com
# Description: Interactive installation script for service_monitor.py
# Supports: Ubuntu/Debian (apt), RHEL/CentOS/Fedora (dnf/yum), openSUSE (zypper)
#########################################################################

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Global variables
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
INSTALL_DIR="/opt/service_monitor"
SERVICE_MONITOR_SCRIPT="service_monitor.py"
INSTALL_SCRIPT="install_service_monitor.sh"
LOG_DIR="/var/log"
STATE_DIR="/var/lib/service_monitor"
SYS_USER="root"
SYS_GROUP="root"
PYTHON_MIN_VERSION="3.6"
EMAIL_METHOD=""
ADMIN_EMAIL=""
SERVICES_LIST=()
ENABLE_CRON=true
ENABLE_SYSTEMD=false
DAEMON_MODE=false
CHECK_INTERVAL=60

# Detect package manager and OS
detect_os_and_pkg_manager() {
    echo -e "${CYAN}Detecting operating system and package manager...${NC}"
    
    if command -v apt-get >/dev/null 2>&1; then
        PKG_MANAGER="apt-get"
        INSTALL_CMD="apt-get install -y"
        UPDATE_CMD="apt-get update"
        OS_FAMILY="debian"
        echo -e "${GREEN}Detected: Debian/Ubuntu (apt)${NC}"
        
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MANAGER="dnf"
        INSTALL_CMD="dnf install -y"
        UPDATE_CMD="dnf check-update"
        OS_FAMILY="rhel"
        echo -e "${GREEN}Detected: RHEL/Fedora/CentOS (dnf)${NC}"
        
    elif command -v yum >/dev/null 2>&1; then
        PKG_MANAGER="yum"
        INSTALL_CMD="yum install -y"
        UPDATE_CMD="yum check-update"
        OS_FAMILY="rhel"
        echo -e "${GREEN}Detected: RHEL/CentOS (yum)${NC}"
        
    elif command -v zypper >/dev/null 2>&1; then
        PKG_MANAGER="zypper"
        INSTALL_CMD="zypper install -y"
        UPDATE_CMD="zypper refresh"
        OS_FAMILY="suse"
        echo -e "${GREEN}Detected: openSUSE (zypper)${NC}"
        
    else
        echo -e "${RED}Error: Could not detect package manager.${NC}"
        echo "Supported package managers: apt, dnf, yum, zypper"
        exit 1
    fi
    
    # Detect specific distribution
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        echo -e "${GREEN}Distribution: $NAME $VERSION${NC}"
    fi
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Error: This script must be run as root${NC}"
        echo "Please use: sudo ./$INSTALL_SCRIPT"
        exit 1
    fi
    echo -e "${GREEN}✓ Running as root${NC}"
}

# Check Python version
check_python() {
    echo -e "${CYAN}Checking Python installation...${NC}"
    
    if command -v python3 >/dev/null 2>&1; then
        PYTHON_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
        PYTHON_CMD="python3"
        
        # Compare versions
        if python3 -c "import sys; sys.exit(0) if sys.version_info >= (3, 6) else sys.exit(1)"; then
            echo -e "${GREEN}✓ Python $PYTHON_VERSION is installed (meets minimum requirement $PYTHON_MIN_VERSION)${NC}"
            return 0
        else
            echo -e "${YELLOW}⚠ Python $PYTHON_VERSION is installed (minimum requirement is $PYTHON_MIN_VERSION)${NC}"
            return 1#!/bin/bash
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


        fi
    else
        echo -e "${YELLOW}⚠ Python3 is not installed${NC}"
        return 1
    fi
}

# Install Python if needed
install_python() {
    echo -e "${CYAN}Installing Python...${NC}"
    
    case $PKG_MANAGER in
        "apt-get")
            $INSTALL_CMD python3 python3-pip
            ;;
        "dnf"|"yum")
            $INSTALL_CMD python3 python3-pip
            ;;
        "zypper")
            $INSTALL_CMD python3 python3-pip
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Python installed successfully${NC}"
    else
        echo -e "${RED}Error: Failed to install Python${NC}"
        exit 1
    fi
}

# Check for systemd
check_systemd() {
    echo -e "${CYAN}Checking for systemd...${NC}"
    
    if command -v systemctl >/dev/null 2>&1 && systemctl --version >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Systemd is available${NC}"
        return 0
    else
        echo -e "${RED}Error: Systemd is not available${NC}"
        echo "This script requires a systemd-based distribution"
        exit 1
    fi
}

# Interactive configuration
interactive_config() {
    echo -e "${CYAN}=== Service Monitor Configuration ===${NC}"
    echo ""
    
    # Email configuration
    while true; do
        read -p "Enter admin email address for alerts: " ADMIN_EMAIL
        if [[ "$ADMIN_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
            break
        else
            echo -e "${RED}Invalid email format. Please try again.${NC}"
        fi
    done
    
    echo ""
    echo -e "${YELLOW}Select email delivery method:${NC}"
    echo "1) sendmail (recommended for local mail delivery)"
    echo "2) SMTP (for external email servers like Gmail)"
    echo "3) mail command (requires mailutils/mailx)"
    echo "4) None (no email alerts)"
    
    while true; do
        read -p "Enter choice [1-4]: " email_choice
        case $email_choice in
            1)
                EMAIL_METHOD="sendmail"
                break
                ;;
            2)
                EMAIL_METHOD="smtp"
                break
                ;;
            3)
                EMAIL_METHOD="mail"
                break
                ;;
            4)
                EMAIL_METHOD="none"
                echo -e "${YELLOW}⚠ Email alerts will be disabled${NC}"
                break
                ;;
            *)
                echo -e "${RED}Invalid choice. Please enter 1-4.${NC}"
                ;;
        esac
    done
    
    # If SMTP is selected, get SMTP details
    if [ "$EMAIL_METHOD" = "smtp" ]; then
        echo ""
        echo -e "${YELLOW}SMTP Configuration:${NC}"
        read -p "SMTP Server [smtp.gmail.com]: " smtp_server
        smtp_server=${smtp_server:-"smtp.gmail.com"}
        
        read -p "SMTP Port [587]: " smtp_port
        smtp_port=${smtp_port:-"587"}
        
        read -p "SMTP Username (email): " smtp_username
        
        echo -n "SMTP Password/App Password: "
        read -s smtp_password
        echo ""
        
        read -p "Use TLS? [Y/n]: " use_tls
        use_tls=${use_tls:-"Y"}
    fi
    
    # Services to monitor
    echo ""
    echo -e "${YELLOW}Services to monitor:${NC}"
    echo "Enter service names one by one (e.g., apache2, nginx, mariadb)"
    echo "Press Enter without typing to finish"
    
    while true; do
        read -p "Service name (leave empty to finish): " service_name
        if [ -z "$service_name" ]; then
            break
        fi
        
        # Check if service exists
        if systemctl list-unit-files "${service_name}.service" >/dev/null 2>&1; then
            echo -e "${GREEN}✓ Service '${service_name}.service' found${NC}"
        else
            echo -e "${YELLOW}⚠ Service '${service_name}.service' not found (will still be added)${NC}"
        fi
        
        SERVICES_LIST+=("$service_name")
    done
    
    # If no services were added, add some defaults
    if [ ${#SERVICES_LIST[@]} -eq 0 ]; then
        echo -e "${YELLOW}No services specified. Adding common defaults...${NC}"
        SERVICES_LIST=("apache2" "nginx" "mariadb" "postgresql" "ssh")
    fi
    
    # Running mode
    echo ""
    echo -e "${YELLOW}Select running mode:${NC}"
    echo "1) Cron job (runs periodically, e.g., every 5 minutes)"
    echo "2) Systemd service (runs as a daemon, continuous monitoring)"
    
    while true; do
        read -p "Enter choice [1-2]: " mode_choice
        case $mode_choice in
            1)
                ENABLE_CRON=true
                ENABLE_SYSTEMD=false
                DAEMON_MODE=false
                break
                ;;
            2)
                ENABLE_CRON=false
                ENABLE_SYSTEMD=true
                DAEMON_MODE=true
                break
                ;;
            *)
                echo -e "${RED}Invalid choice. Please enter 1 or 2.${NC}"
                ;;
        esac
    done
    
    # If daemon mode, ask for check interval
    if [ "$DAEMON_MODE" = true ]; then
        read -p "Check interval in seconds [60]: " check_interval
        CHECK_INTERVAL=${check_interval:-60}
    fi
    
    # Confirm installation
    echo ""
    echo -e "${CYAN}=== Installation Summary ===${NC}"
    echo "Admin Email: $ADMIN_EMAIL"
    echo "Email Method: $EMAIL_METHOD"
    if [ "$EMAIL_METHOD" = "smtp" ]; then
        echo "SMTP Server: $smtp_server:$smtp_port"
        echo "SMTP Username: $smtp_username"
    fi
    echo "Services to monitor: ${SERVICES_LIST[*]}"
    echo "Installation Directory: $INSTALL_DIR"
    echo "Log Directory: $LOG_DIR"
    echo "State Directory: $STATE_DIR"
    echo "Running Mode: $( [ "$DAEMON_MODE" = true ] && echo "Systemd Daemon" || echo "Cron Job" )"
    if [ "$DAEMON_MODE" = true ]; then
        echo "Check Interval: $CHECK_INTERVAL seconds"
    fi
    
    echo ""
    read -p "Proceed with installation? [Y/n]: " confirm
    confirm=${confirm:-"Y"}
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Installation cancelled.${NC}"
        exit 0
    fi
}

# Install email dependencies based on chosen method
install_email_deps() {
    echo -e "${CYAN}Installing email dependencies...${NC}"
    
    case $EMAIL_METHOD in
        "sendmail")
            case $PKG_MANAGER in
                "apt-get")
                    $INSTALL_CMD sendmail
                    ;;
                "dnf"|"yum")
                    $INSTALL_CMD sendmail sendmail-cf
                    ;;
                "zypper")
                    $INSTALL_CMD sendmail
                    ;;
            esac
            
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}✓ sendmail installed${NC}"
            else
                echo -e "${YELLOW}⚠ Failed to install sendmail. Email alerts may not work.${NC}"
            fi
            ;;
            
        "mail")
            case $PKG_MANAGER in
                "apt-get")
                    $INSTALL_CMD mailutils
                    ;;
                "dnf"|"yum")
                    $INSTALL_CMD mailx
                    ;;
                "zypper")
                    $INSTALL_CMD mailx
                    ;;
            esac
            
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}✓ mail utilities installed${NC}"
            else
                echo -e "${YELLOW}⚠ Failed to install mail utilities. Email alerts may not work.${NC}"
            fi
            ;;
            
        "smtp")
            # Python's smtplib is included by default
            echo -e "${GREEN}✓ SMTP support available via Python smtplib${NC}"
            ;;
            
        "none")
            echo -e "${YELLOW}⚠ Email alerts disabled${NC}"
            ;;
    esac
}

# Create directories
create_directories() {
    echo -e "${CYAN}Creating directories...${NC}"
    
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$STATE_DIR"
    mkdir -p "$LOG_DIR"
    
    chown "$SYS_USER:$SYS_GROUP" "$INSTALL_DIR"
    chown "$SYS_USER:$SYS_GROUP" "$STATE_DIR"
    
    echo -e "${GREEN}✓ Directories created${NC}"
}

# Install the service monitor script
install_script() {
    echo -e "${CYAN}Installing Service Monitor script...${NC}"
    
    # Check if service_monitor.py exists in the same directory
    if [ ! -f "$SCRIPT_DIR/$SERVICE_MONITOR_SCRIPT" ]; then
        echo -e "${RED}Error: $SERVICE_MONITOR_SCRIPT not found in $SCRIPT_DIR${NC}"
        echo "Please make sure the Python script is in the same directory as this installer."
        exit 1
    fi
    
    # Copy the script
    cp "$SCRIPT_DIR/$SERVICE_MONITOR_SCRIPT" "$INSTALL_DIR/"
    chmod 755 "$INSTALL_DIR/$SERVICE_MONITOR_SCRIPT"
    
    # Create symbolic link for easy access
    ln -sf "$INSTALL_DIR/$SERVICE_MONITOR_SCRIPT" /usr/local/bin/service-monitor
    
    echo -e "${GREEN}✓ Script installed to $INSTALL_DIR/${NC}"
    echo -e "${GREEN}✓ Symbolic link created: /usr/local/bin/service-monitor${NC}"
}

# Configure the script with user settings
configure_script() {
    echo -e "${CYAN}Configuring Service Monitor...${NC}"
    
    # Create a backup of the original script
    cp "$INSTALL_DIR/$SERVICE_MONITOR_SCRIPT" "$INSTALL_DIR/$SERVICE_MONITOR_SCRIPT.backup"
    
    # Read the original script
    script_content=$(cat "$INSTALL_DIR/$SERVICE_MONITOR_SCRIPT")
    
    # Convert services list to Python list format
    services_python_list="["
    for service in "${SERVICES_LIST[@]}"; do
        services_python_list+="\n    [\"${service}.service\", \"restart\", True],"
    done
    services_python_list="${services_python_list%,}\n]"
    
    # Create new configuration section
    new_config="# ============================================================================
# CONFIGURATION SECTION
# ============================================================================

# Admin email for alerts
ADMIN_EMAIL = \"$ADMIN_EMAIL\"

# Sendmail configuration (choose one method)
SENDMAIL_CONFIG = {
    # Method 1: Use local sendmail (recommended)
    \"method\": \"$EMAIL_METHOD\",  # Options: \"sendmail\", \"smtp\", \"mail\", \"none\""
    
    # Add SMTP configuration if selected
    if [ "$EMAIL_METHOD" = "smtp" ]; then
        new_config+="\n    \n    # Method 2: SMTP configuration (if using external SMTP server)
    \"smtp_server\": \"$smtp_server\",
    \"smtp_port\": $smtp_port,
    \"smtp_username\": \"$smtp_username\",
    \"smtp_password\": \"$smtp_password\",
    \"smtp_tls\": $( [[ "$use_tls" =~ ^[Yy]$ ]] && echo "True" || echo "False" ),"
    fi
    
    new_config+="\n    \n    # Method 3: Use mail command (requires mailutils)
    \"mail_command\": \"/usr/bin/mail\",
}

# Service configuration list
# Format: [\"service_name\", \"action\", \"alarm\"]
SERVICES = $services_python_list

# Alert configuration
ALERT_THRESHOLD = 10  # Send alert after this many failures
ALERT_RATE_LIMIT = 3600  # Seconds between alerts for same service (1 hour)

# Retry configuration
RETRY_COUNT = 3  # Number of restart attempts before giving up
RETRY_DELAY = 5  # Seconds between retry attempts
CHECK_INTERVAL = $CHECK_INTERVAL  # Seconds between service checks (when run in daemon mode)

# Logging configuration
LOG_FILE = \"$LOG_DIR/service_monitor.log\"
JOURNALCTL_PRIORITY = 3  # 0=emerg, 1=alert, 2=crit, 3=err, 4=warning, 5=notice, 6=info, 7=debug
LOCK_FILE = \"/tmp/service_monitor.lock\"
STATE_FILE = \"$STATE_DIR/state.json\"

# Top command configuration
TOP_ROWS = 15  # Number of processes to show in alerts
TOP_CPU_ROWS = 10  # Top CPU consuming processes
TOP_MEM_ROWS = 10  # Top memory consuming processes

# Daemon mode (True for continuous monitoring, False for one-shot)
DAEMON_MODE = $( [ "$DAEMON_MODE" = true ] && echo "True" || echo "False" )

# ============================================================================
# END OF CONFIGURATION - DO NOT EDIT BELOW UNLESS YOU KNOW WHAT YOU'RE DOING
# ============================================================================"
    
    # Replace the configuration section in the script
    # Find the line numbers of the configuration section markers
    start_line=$(grep -n "CONFIGURATION SECTION" "$INSTALL_DIR/$SERVICE_MONITOR_SCRIPT" | head -1 | cut -d: -f1)
    end_line=$(grep -n "END OF CONFIGURATION" "$INSTALL_DIR/$SERVICE_MONITOR_SCRIPT" | head -1 | cut -d: -f1)
    
    if [ -n "$start_line" ] && [ -n "$end_line" ]; then
        # Create a temporary file
        temp_file=$(mktemp)
        
        # Write the beginning of the file (before configuration)
        head -n $((start_line - 1)) "$INSTALL_DIR/$SERVICE_MONITOR_SCRIPT" > "$temp_file"
        
        # Write the new configuration
        echo -e "$new_config" >> "$temp_file"
        
        # Write the rest of the file (after configuration)
        tail -n +$((end_line + 1)) "$INSTALL_DIR/$SERVICE_MONITOR_SCRIPT" >> "$temp_file"
        
        # Replace the original file
        mv "$temp_file" "$INSTALL_DIR/$SERVICE_MONITOR_SCRIPT"
        
        echo -e "${GREEN}✓ Configuration applied${NC}"
    else
        echo -e "${YELLOW}⚠ Could not locate configuration section in script${NC}"
        echo "Please manually configure $INSTALL_DIR/$SERVICE_MONITOR_SCRIPT"
    fi
}

# Setup log rotation
setup_logrotate() {
    echo -e "${CYAN}Setting up log rotation...${NC}"
    
    cat > /etc/logrotate.d/service_monitor << EOF
$LOG_DIR/service_monitor.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 640 $SYS_USER $SYS_GROUP
    postrotate
        # Optional: reload syslog if needed
        # systemctl restart rsyslog >/dev/null 2>&1 || true
    endscript
}
EOF
    
    chmod 644 /etc/logrotate.d/service_monitor
    echo -e "${GREEN}✓ Log rotation configured${NC}"
}

# Setup cron job
setup_cron() {
    if [ "$ENABLE_CRON" = true ]; then
        echo -e "${CYAN}Setting up cron job...${NC}"
        
        # Ask for cron interval
        echo ""
        echo -e "${YELLOW}Select cron job interval:${NC}"
        echo "1) Every 1 minute"
        echo "2) Every 5 minutes"
        echo "3) Every 10 minutes"
        echo "4) Every hour"
        echo "5) Custom cron expression"
        
        while true; do
            read -p "Enter choice [1-5]: " cron_choice
            case $cron_choice in
                1)
                    cron_expression="* * * * *"
                    break
                    ;;
                2)
                    cron_expression="*/5 * * * *"
                    break
                    ;;
                3)
                    cron_expression="*/10 * * * *"
                    break
                    ;;
                4)
                    cron_expression="0 * * * *"
                    break
                    ;;
                5)
                    read -p "Enter custom cron expression (e.g., '*/15 * * * *'): " cron_expression
                    break
                    ;;
                *)
                    echo -e "${RED}Invalid choice. Please enter 1-5.${NC}"
                    ;;
            esac
        done
        
        # Add to root's crontab
        (crontab -l 2>/dev/null | grep -v "service-monitor"; echo "$cron_expression /usr/bin/python3 /usr/local/bin/service-monitor 2>&1 | logger -t service_monitor") | crontab -
        
        echo -e "${GREEN}✓ Cron job added: $cron_expression${NC}"
    fi
}

# Setup systemd service
setup_systemd() {
    if [ "$ENABLE_SYSTEMD" = true ]; then
        echo -e "${CYAN}Setting up systemd service...${NC}"
        
        cat > /etc/systemd/system/service-monitor.service << EOF
[Unit]
Description=Service Monitor Daemon
Documentation=https://github.com/yourusername/service-monitor
After=network.target
Requires=network.target

[Service]
Type=simple
User=root
Group=root
ExecStart=/usr/bin/python3 $INSTALL_DIR/$SERVICE_MONITOR_SCRIPT
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=service_monitor
ProtectSystem=strict
RuntimeDirectory=service_monitor
StateDirectory=service_monitor
LogsDirectory=service_monitor
ReadWritePaths=$STATE_DIR $LOG_DIR

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
MemoryDenyWriteExecute=true
RestrictRealtime=true
RestrictSUIDSGID=true
LockPersonality=true

[Install]
WantedBy=multi-user.target
EOF
        
        # Reload systemd and enable service
        systemctl daemon-reload
        
        echo ""
        read -p "Enable and start service-monitor service? [Y/n]: " start_service
        start_service=${start_service:-"Y"}
        
        if [[ "$start_service" =~ ^[Yy]$ ]]; then
            systemctl enable service-monitor.service
            systemctl start service-monitor.service
            
            # Check status
            sleep 2
            echo ""
            systemctl status service-monitor.service --no-pager
            
            if systemctl is-active --quiet service-monitor.service; then
                echo -e "${GREEN}✓ Service started successfully${NC}"
            else
                echo -e "${YELLOW}⚠ Service may not be running. Check logs with: journalctl -u service-monitor${NC}"
            fi
        else
            echo -e "${YELLOW}⚠ Service created but not started${NC}"
            echo "Start manually with: systemctl start service-monitor"
        fi
        
        echo -e "${GREEN}✓ Systemd service configured${NC}"
    fi
}

# Test installation
test_installation() {
    echo -e "${CYAN}Testing installation...${NC}"
    
    # Test Python script syntax
    if python3 -m py_compile "$INSTALL_DIR/$SERVICE_MONITOR_SCRIPT" 2>/dev/null; then
        echo -e "${GREEN}✓ Python script syntax is valid${NC}"
    else
        echo -e "${YELLOW}⚠ Python script may have syntax errors${NC}"
    fi
    
    # Test if script runs without errors
    echo ""
    echo -e "${YELLOW}Running test (dry run)...${NC}"
    if timeout 10 python3 "$INSTALL_DIR/$SERVICE_MONITOR_SCRIPT" --help 2>&1 | grep -q "Usage\|Service Monitor"; then
        echo -e "${GREEN}✓ Script executes successfully${NC}"
    else
        echo -e "${YELLOW}⚠ Script execution test inconclusive${NC}"
    fi
    
    # Check log file
    echo ""
    if [ -f "$LOG_DIR/service_monitor.log" ]; then
        echo -e "${GREEN}✓ Log file exists: $LOG_DIR/service_monitor.log${NC}"
    fi
    
    # Check state directory
    if [ -d "$STATE_DIR" ]; then
        echo -e "${GREEN}✓ State directory exists: $STATE_DIR${NC}"
    fi
}

# Print final instructions
print_final_instructions() {
    echo ""
    echo -e "${CYAN}=== Installation Complete ===${NC}"
    echo ""
    echo -e "${GREEN}Service Monitor has been successfully installed!${NC}"
    echo ""
    echo -e "${YELLOW}Summary:${NC}"
    echo "  • Installation directory: $INSTALL_DIR"
    echo "  • Main script: /usr/local/bin/service-monitor"
    echo "  • Log file: $LOG_DIR/service_monitor.log"
    echo "  • State file: $STATE_DIR/state.json"
    echo "  • Admin email: $ADMIN_EMAIL"
    echo "  • Services monitored: ${SERVICES_LIST[*]}"
    
    if [ "$ENABLE_CRON" = true ]; then
        echo "  • Running mode: Cron job"
        echo "  • Cron schedule: $(crontab -l | grep service-monitor | cut -d' ' -f1-5)"
    fi
    
    if [ "$ENABLE_SYSTEMD" = true ]; then
        echo "  • Running mode: Systemd daemon"
        echo "  • Check interval: $CHECK_INTERVAL seconds"
    fi
    
    echo ""
    echo -e "${YELLOW}Usage instructions:${NC}"
    echo "  • Manual run: sudo service-monitor"
    echo "  • Check logs: tail -f $LOG_DIR/service_monitor.log"
    echo "  • View journal: journalctl -t service_monitor -f"
    
    if [ "$ENABLE_SYSTEMD" = true ]; then
        echo "  • Control service: sudo systemctl [start|stop|restart|status] service-monitor"
        echo "  • Enable on boot: sudo systemctl enable service-monitor"
    fi
    
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Test the installation by running: sudo service-monitor"
    echo "2. Monitor logs for a few minutes to ensure it's working"
    echo "3. Test email alerts by manually stopping a monitored service"
    
    if [ "$EMAIL_METHOD" = "sendmail" ] || [ "$EMAIL_METHOD" = "mail" ]; then
        echo "4. Test email delivery: echo 'Test' | mail -s 'Test' $ADMIN_EMAIL"
    fi
    
    echo ""
    echo -e "${CYAN}For support, contact: Max Haase <maxhaase@gmail.com>${NC}"
    echo ""
}

# Main installation function
main() {
    clear
    echo -e "${CYAN}"
    echo "#########################################################################"
    echo "#         Service Monitor Installation Script                           #"
    echo "#         Author: Max Haase - maxhaase@gmail.com                       #"
    echo "#########################################################################"
    echo -e "${NC}"
    
    # Step 1: Check root privileges
    check_root
    
    # Step 2: Detect OS and package manager
    detect_os_and_pkg_manager
    
    # Step 3: Check for systemd
    check_systemd
    
    # Step 4: Check Python
    if ! check_python; then
        echo ""
        read -p "Python 3.6+ is required. Install it now? [Y/n]: " install_python_confirm
        install_python_confirm=${install_python_confirm:-"Y"}
        
        if [[ "$install_python_confirm" =~ ^[Yy]$ ]]; then
            $UPDATE_CMD
            install_python
        else
            echo -e "${YELLOW}Python installation cancelled. Exiting.${NC}"
            exit 1
        fi
    fi
    
    # Step 5: Interactive configuration
    interactive_config
    
    # Step 6: Update package lists
    echo -e "${CYAN}Updating package lists...${NC}"
    $UPDATE_CMD >/dev/null 2>&1
    
    # Step 7: Install email dependencies
    if [ "$EMAIL_METHOD" != "none" ] && [ "$EMAIL_METHOD" != "" ]; then
        install_email_deps
    fi
    
    # Step 8: Create directories
    create_directories
    
    # Step 9: Install script
    install_script
    
    # Step 10: Configure script
    configure_script
    
    # Step 11: Setup log rotation
    setup_logrotate
    
    # Step 12: Setup cron or systemd
    if [ "$ENABLE_CRON" = true ]; then
        setup_cron
    elif [ "$ENABLE_SYSTEMD" = true ]; then
        setup_systemd
    fi
    
    # Step 13: Test installation
    test_installation
    
    # Step 14: Print final instructions
    print_final_instructions
}

# Handle script interruption
cleanup() {
    echo ""
    echo -e "${YELLOW}Installation interrupted. Cleaning up...${NC}"
    exit 1
}

trap cleanup INT TERM

# Run main function
main

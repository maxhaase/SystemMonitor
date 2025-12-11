# SystemMonitor
The program automatically checks if specific services are running and restarts them if they're not active.

# Usage:

# Make the installation script executable
chmod +x install_service_monitor.sh

# Run the interactive installer
sudo ./install_service_monitor.sh

# Or use quick install with defaults (edit the email first!)
sudo ./quick_install.sh

Debian/Ubuntu (apt)

RHEL/CentOS/Fedora (dnf/yum)

openSUSE (zypper)

# Interactive Configuration: Guided prompts for:

Admin email address

Email delivery method (sendmail, SMTP, mail, or none)

Services to monitor

Running mode (cron or systemd daemon)

Check intervals

Prerequisite Checking: Verifies and optionally installs:

Root privileges

Systemd availability

Python 3.6+ (with user confirmation before installing)

Smart Package Management: Installs appropriate packages for each distro:

Python3 and pip

Email tools (sendmail, mailutils, mailx based on choice)

Required dependencies

Complete Setup:

Creates necessary directories with proper permissions

Installs and configures the Python script

Sets up log rotation

Configures either cron job or systemd service

Applies security hardening for systemd service

Testing and Verification:

Validates Python script syntax

Tests script execution

Checks file and directory creation

Error Handling and Cleanup:

Graceful interruption handling

Backup of original files

Detailed error messages

Installation Flow:
System Detection → Determines package manager and OS

Prerequisite Check → Verifies root, systemd, Python

Interactive Setup → Gets configuration from user

Package Installation → Installs required packages

Script Deployment → Copies and configures Python script

Service Setup → Configures cron or systemd

Testing → Verifies installation

Final Instructions → Provides usage info

The script handles all edge cases, provides clear feedback, and ensures the service monitor is properly set up regardless of the Linux distribution.

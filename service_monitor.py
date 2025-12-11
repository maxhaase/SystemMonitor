#!/usr/bin/env python3
"""
#########################################################################
Program: service_monitor.py
Description: Service monitoring and auto-recovery script with enhanced 
             alerting. Monitors systemd services and automatically restarts
             failed services. Sends email alerts with system diagnostics.
Author: Max Haase - maxhaase@gmail.com
Version: 2.0.0
#########################################################################
"""

import os
import sys
import subprocess
import json
import time
import smtplib
import socket
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from datetime import datetime, timedelta
from collections import defaultdict
import threading
import signal
from pathlib import Path

# ============================================================================
# CONFIGURATION SECTION
# ============================================================================

# Admin email for alerts
ADMIN_EMAIL = "admin@example.com"

# Sendmail configuration (choose one method)
SENDMAIL_CONFIG = {
    # Method 1: Use local sendmail (recommended)
    "method": "sendmail",  # Options: "sendmail", "smtp", "mail"
    
    # Method 2: SMTP configuration (if using external SMTP server)
    "smtp_server": "smtp.gmail.com",
    "smtp_port": 587,
    "smtp_username": "your-email@gmail.com",
    "smtp_password": "your-app-password",  # Use app password, not regular password
    "smtp_tls": True,
    
    # Method 3: Use mail command (requires mailutils)
    "mail_command": "/usr/bin/mail",
}

# Service configuration list
# Format: ["service_name", "action", "alarm"]
# service_name: systemd service name (e.g., "apache2.service")
# action: "restart", "start", "stop", "mask", "reload", "try-restart"
# alarm: True/False - send email after 10 failures (rate-limited to once per hour)
SERVICES = [
    ["apache2.service", "restart", True],
    ["mariadb.service", "restart", True],
    ["nginx.service", "restart", True],
    ["ssh.service", "restart", True],
    ["postgresql.service", "restart", True],
]

# Alert configuration
ALERT_THRESHOLD = 10  # Send alert after this many failures
ALERT_RATE_LIMIT = 3600  # Seconds between alerts for same service (1 hour)

# Retry configuration
RETRY_COUNT = 3  # Number of restart attempts before giving up
RETRY_DELAY = 5  # Seconds between retry attempts
CHECK_INTERVAL = 60  # Seconds between service checks (when run in daemon mode)

# Logging configuration
LOG_FILE = "/var/log/service_monitor.log"
JOURNALCTL_PRIORITY = 3  # 0=emerg, 1=alert, 2=crit, 3=err, 4=warning, 5=notice, 6=info, 7=debug
LOCK_FILE = "/tmp/service_monitor.lock"
STATE_FILE = "/var/lib/service_monitor/state.json"

# Top command configuration
TOP_ROWS = 15  # Number of processes to show in alerts
TOP_CPU_ROWS = 10  # Top CPU consuming processes
TOP_MEM_ROWS = 10  # Top memory consuming processes

# Daemon mode (True for continuous monitoring, False for one-shot)
DAEMON_MODE = False

# ============================================================================
# END OF CONFIGURATION - DO NOT EDIT BELOW UNLESS YOU KNOW WHAT YOU'RE DOING
# ============================================================================

class ServiceMonitor:
    def __init__(self):
        self.hostname = socket.gethostname()
        self.fqdn = socket.getfqdn()
        self.state_file = Path(STATE_FILE)
        self.lock_file = Path(LOCK_FILE)
        self.log_file = Path(LOG_FILE)
        self.state = defaultdict(lambda: {"failures": 0, "last_alert": 0})
        self.running = True
        
        # Setup signal handlers
        signal.signal(signal.SIGINT, self.signal_handler)
        signal.signal(signal.SIGTERM, self.signal_handler)
        
        # Ensure running as root
        if os.geteuid() != 0:
            self.log_to_journal("Must be run as root!", priority=0)
            sys.exit(1)
        
        # Create necessary directories
        self.state_file.parent.mkdir(parents=True, exist_ok=True)
        self.log_file.parent.mkdir(parents=True, exist_ok=True)
        
        # Load state
        self.load_state()
    
    def signal_handler(self, signum, frame):
        """Handle termination signals"""
        self.running = False
        self.log_message("INFO", f"Received signal {signum}, shutting down gracefully")
    
    def log_message(self, level, message):
        """Log message to both file and journal"""
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        log_entry = f"[{timestamp}] [{level}] {message}"
        
        # Log to file
        try:
            with open(self.log_file, 'a') as f:
                f.write(log_entry + "\n")
        except:
            pass
        
        # Log to journal with appropriate priority
        journal_priority = {
            "EMERGENCY": 0, "ALERT": 1, "CRITICAL": 2, "ERROR": 3,
            "WARNING": 4, "NOTICE": 5, "INFO": 6, "DEBUG": 7
        }
        priority = journal_priority.get(level.upper(), 6)
        
        # Color codes for journal (red for errors, yellow for warnings)
        color_code = ""
        if level == "ERROR":
            color_code = "\033[1;31m"  # Red
        elif level == "WARNING":
            color_code = "\033[1;33m"  # Yellow
        
        # Log to journal
        cmd = f'echo "{color_code}{message}\033[0m" | systemd-cat -p {priority} -t service_monitor'
        os.system(cmd)
        
        # Also print to console if not in daemon mode
        if not DAEMON_MODE:
            print(log_entry)
    
    def log_to_journal(self, message, priority=JOURNALCTL_PRIORITY):
        """Log directly to systemd journal with color"""
        # Map priority to color
        colors = {
            0: "\033[1;31m",  # Red for emergency
            1: "\033[1;31m",  # Red for alert
            2: "\033[1;31m",  # Red for critical
            3: "\033[1;31m",  # Red for error
            4: "\033[1;33m",  # Yellow for warning
            5: "\033[1;32m",  # Green for notice
            6: "\033[1;36m",  # Cyan for info
            7: "\033[1;37m",  # White for debug
        }
        color = colors.get(priority, "\033[1;37m")
        reset = "\033[0m"
        
        cmd = f'echo "{color}{message}{reset}" | systemd-cat -p {priority} -t service_monitor'
        os.system(cmd)
    
    def load_state(self):
        """Load state from JSON file"""
        try:
            if self.state_file.exists():
                with open(self.state_file, 'r') as f:
                    self.state = defaultdict(lambda: {"failures": 0, "last_alert": 0}, 
                                            json.load(f))
        except Exception as e:
            self.log_message("WARNING", f"Failed to load state: {e}")
            self.state = defaultdict(lambda: {"failures": 0, "last_alert": 0})
    
    def save_state(self):
        """Save state to JSON file"""
        try:
            with open(self.state_file, 'w') as f:
                json.dump(dict(self.state), f, indent=2)
        except Exception as e:
            self.log_message("ERROR", f"Failed to save state: {e}")
    
    def run_command(self, cmd, timeout=30):
        """Run shell command and return output"""
        try:
            result = subprocess.run(
                cmd,
                shell=True,
                capture_output=True,
                text=True,
                timeout=timeout
            )
            return result.returncode, result.stdout.strip(), result.stderr.strip()
        except subprocess.TimeoutExpired:
            return -1, "", f"Command timed out after {timeout} seconds"
        except Exception as e:
            return -1, "", str(e)
    
    def get_system_info(self):
        """Get comprehensive system information"""
        info = []
        
        # Basic system info
        info.append(f"Hostname: {self.fqdn}")
        info.append(f"System: {self.run_command('uname -a')[1]}")
        
        # Uptime
        uptime = self.run_command('uptime')[1]
        info.append(f"Uptime: {uptime}")
        
        # Load average
        with open('/proc/loadavg', 'r') as f:
            load = f.read().strip()
        info.append(f"Load Average: {load}")
        
        # Memory info
        with open('/proc/meminfo', 'r') as f:
            meminfo = f.readlines()
        
        mem_total = next((l for l in meminfo if 'MemTotal' in l), '')
        mem_free = next((l for l in meminfo if 'MemAvailable' in l), '')
        info.append(f"Memory: {mem_total.strip()}")
        info.append(f"Available: {mem_free.strip()}")
        
        # Disk space
        disk = self.run_command('df -h /')[1]
        info.append(f"Root Disk:\n{disk}")
        
        return "\n".join(info)
    
    def get_service_info(self, service):
        """Get detailed service information"""
        info = []
        
        # Service status
        status_cmd = f"systemctl is-active {service}"
        status = self.run_command(status_cmd)[1]
        info.append(f"Service: {service}")
        info.append(f"Status: {status}")
        
        # Service properties
        show_cmd = f"systemctl show {service} --no-pager"
        show_output = self.run_command(show_cmd)[1]
        
        # Extract relevant info
        for line in show_output.split('\n'):
            if any(key in line for key in ['MainPID', 'ActiveState', 'SubState', 
                                          'LoadState', 'UnitFileState']):
                info.append(line)
        
        # Recent journal entries
        journal_cmd = f"journalctl -u {service} -n 5 --no-pager"
        journal = self.run_command(journal_cmd)[1]
        info.append(f"\nRecent Journal Entries:\n{journal}")
        
        return "\n".join(info)
    
    def get_top_info(self):
        """Get detailed top information"""
        top_info = []
        
        # Get comprehensive process info using ps
        ps_cmd = "ps aux --sort=-%cpu | head -n 20"
        ps_output = self.run_command(ps_cmd)[1]
        top_info.append("=== Top Processes by CPU ===\n" + ps_output)
        
        # Get memory usage
        ps_mem_cmd = "ps aux --sort=-%mem | head -n 20"
        ps_mem_output = self.run_command(ps_mem_cmd)[1]
        top_info.append("\n=== Top Processes by Memory ===\n" + ps_mem_output)
        
        # Get load averages
        with open('/proc/loadavg', 'r') as f:
            loadavg = f.read().strip()
        top_info.append(f"\n=== Load Averages ===\n{loadavg}")
        
        return "\n\n".join(top_info)
    
    def send_email(self, subject, body):
        """Send email using configured method"""
        if not ADMIN_EMAIL:
            self.log_message("WARNING", "No admin email configured, skipping alert")
            return False
        
        try:
            msg = MIMEMultipart()
            msg['From'] = f"Service Monitor <noreply@{self.hostname}>"
            msg['To'] = ADMIN_EMAIL
            msg['Subject'] = subject
            msg.attach(MIMEText(body, 'plain'))
            
            if SENDMAIL_CONFIG["method"] == "sendmail":
                # Use sendmail command
                sendmail_cmd = f"sendmail -t -i"
                process = subprocess.Popen(sendmail_cmd.split(), stdin=subprocess.PIPE)
                process.communicate(msg.as_bytes())
                return process.returncode == 0
            
            elif SENDMAIL_CONFIG["method"] == "smtp":
                # Use SMTP
                smtp_server = SENDMAIL_CONFIG.get("smtp_server", "localhost")
                smtp_port = SENDMAIL_CONFIG.get("smtp_port", 25)
                username = SENDMAIL_CONFIG.get("smtp_username")
                password = SENDMAIL_CONFIG.get("smtp_password")
                
                with smtplib.SMTP(smtp_server, smtp_port) as server:
                    if SENDMAIL_CONFIG.get("smtp_tls", False):
                        server.starttls()
                    if username and password:
                        server.login(username, password)
                    server.send_message(msg)
                return True
            
            elif SENDMAIL_CONFIG["method"] == "mail":
                # Use mail command
                mail_cmd = f"{SENDMAIL_CONFIG.get('mail_command', '/usr/bin/mail')} -s '{subject}' {ADMIN_EMAIL}"
                process = subprocess.Popen(mail_cmd, shell=True, stdin=subprocess.PIPE)
                process.communicate(body.encode())
                return process.returncode == 0
            
            else:
                self.log_message("ERROR", f"Unknown email method: {SENDMAIL_CONFIG['method']}")
                return False
                
        except Exception as e:
            self.log_message("ERROR", f"Failed to send email: {e}")
            return False
    
    def check_service_exists(self, service):
        """Check if service exists"""
        cmd = f"systemctl list-unit-files | grep -q '^{service}$'"
        return self.run_command(cmd)[0] == 0
    
    def is_service_masked(self, service):
        """Check if service is masked"""
        cmd = f"systemctl is-enabled {service}"
        rc, stdout, _ = self.run_command(cmd)
        return "masked" in stdout or rc != 0
    
    def perform_action(self, service, action):
        """Perform action on service"""
        if action == "restart":
            cmd = f"systemctl restart {service}"
        elif action == "start":
            cmd = f"systemctl start {service}"
        elif action == "stop":
            cmd = f"systemctl stop {service}"
        elif action == "mask":
            cmd = f"systemctl mask {service}"
        elif action == "reload":
            cmd = f"systemctl reload {service}"
        elif action == "try-restart":
            cmd = f"systemctl try-restart {service}"
        else:
            self.log_message("ERROR", f"Unknown action: {action} for service {service}")
            return False
        
        for attempt in range(RETRY_COUNT):
            self.log_message("INFO", f"Attempt {attempt + 1} to {action} {service}")
            rc, stdout, stderr = self.run_command(cmd, timeout=30)
            
            if rc == 0:
                self.log_message("SUCCESS", f"Successfully performed {action} on {service}")
                
                # Verify service is active (for start/restart actions)
                if action in ["start", "restart", "try-restart"]:
                    time.sleep(3)  # Wait for service to stabilize
                    status_cmd = f"systemctl is-active {service}"
                    status_rc, status_out, _ = self.run_command(status_cmd)
                    if status_rc == 0 and "active" in status_out:
                        return True
                    else:
                        self.log_message("WARNING", f"Service {service} still not active after {action}")
                        continue
                return True
            
            self.log_message("WARNING", f"Failed to {action} {service}: {stderr}")
            
            if attempt < RETRY_COUNT - 1:
                time.sleep(RETRY_DELAY)
        
        return False
    
    def check_service(self, service_name, action, alarm_enabled):
        """Check and maintain service"""
        self.log_message("INFO", f"Checking service: {service_name}")
        
        # Check if service exists
        if not self.check_service_exists(service_name):
            self.log_message("WARNING", f"Service {service_name} does not exist, skipping")
            return
        
        # Check if service is masked
        if self.is_service_masked(service_name):
            self.log_message("INFO", f"Service {service_name} is masked, skipping")
            return
        
        # Check service status
        status_cmd = f"systemctl is-active {service_name}"
        rc, status, _ = self.run_command(status_cmd)
        
        if rc == 0 and "active" in status:
            self.log_message("INFO", f"Service {service_name} is active")
            # Reset failure counter on success
            if self.state[service_name]["failures"] > 0:
                self.state[service_name]["failures"] = 0
                self.save_state()
            return
        
        # Service is not active
        self.log_message("ERROR", f"Service {service_name} is not active: {status}")
        self.log_to_journal(f"Service {service_name} failed with status: {status}", priority=3)
        
        # Increment failure counter
        self.state[service_name]["failures"] += 1
        self.save_state()
        
        # Try to fix the service
        success = self.perform_action(service_name, action)
        
        if success:
            self.log_message("SUCCESS", f"Successfully recovered {service_name}")
            self.state[service_name]["failures"] = 0
            self.save_state()
        else:
            self.log_message("CRITICAL", f"Failed to recover {service_name} after {RETRY_COUNT} attempts")
            self.log_to_journal(f"CRITICAL: Service {service_name} recovery failed", priority=2)
            
            # Check if we should send alert
            if (alarm_enabled and 
                self.state[service_name]["failures"] >= ALERT_THRESHOLD):
                
                current_time = time.time()
                last_alert = self.state[service_name].get("last_alert", 0)
                
                if current_time - last_alert >= ALERT_RATE_LIMIT:
                    self.send_alert(service_name, action)
                    self.state[service_name]["last_alert"] = current_time
                    self.save_state()
    
    def send_alert(self, service, action):
        """Send detailed alert email"""
        current_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        failures = self.state[service]["failures"]
        
        subject = f"CRITICAL: Service '{service}' failed on {self.hostname}"
        
        body = f"""
CRITICAL SERVICE ALERT
======================

Service '{service}' has failed {failures} consecutive times on {self.fqdn}.

Alert Details:
---------------
Service: {service}
Hostname: {self.fqdn}
Failure Count: {failures}
Last Check: {current_time}
Configured Action: {action}
Retry Attempts: {RETRY_COUNT}

System Information:
-------------------
{self.get_system_info()}

Service Details:
----------------
{self.get_service_info(service)}

System Process Overview:
------------------------
{self.get_top_info()}

Recent Service Monitor Logs:
----------------------------
{self.get_recent_logs()}

Recommended Actions:
-------------------
1. Check service status: systemctl status {service}
2. View service logs: journalctl -u {service} -f
3. Check system resources: free -h; df -h
4. Verify configuration files
5. Check for disk space issues

This is an automated alert from Service Monitor.
Failure count will reset when service returns to normal operation.
"""
        
        if self.send_email(subject, body):
            self.log_message("ALERT", f"Alert sent for {service}")
        else:
            self.log_message("ERROR", f"Failed to send alert for {service}")
    
    def get_recent_logs(self):
        """Get recent log entries"""
        try:
            with open(self.log_file, 'r') as f:
                lines = f.readlines()
                return "".join(lines[-20:])  # Last 20 lines
        except:
            return "Log file not available"
    
    def acquire_lock(self):
        """Acquire lock file to prevent multiple instances"""
        try:
            fd = os.open(self.lock_file, os.O_CREAT | os.O_EXCL | os.O_RDWR)
            # Write PID to lock file
            os.write(fd, str(os.getpid()).encode())
            os.close(fd)
            return True
        except FileExistsError:
            # Check if the process holding the lock is still running
            try:
                with open(self.lock_file, 'r') as f:
                    pid = int(f.read().strip())
                    # Check if process exists
                    os.kill(pid, 0)
                return False  # Process is still running
            except (OSError, ValueError):
                # Process doesn't exist, remove stale lock
                os.remove(self.lock_file)
                return self.acquire_lock()
    
    def release_lock(self):
        """Release lock file"""
        try:
            if self.lock_file.exists():
                os.remove(self.lock_file)
        except:
            pass
    
    def run(self):
        """Main execution loop"""
        if not self.acquire_lock():
            self.log_message("ERROR", "Another instance is already running. Exiting.")
            sys.exit(1)
        
        try:
            self.log_message("INFO", f"Starting Service Monitor on {self.fqdn}")
            self.log_message("INFO", f"Monitoring {len(SERVICES)} services")
            
            if DAEMON_MODE:
                self.log_message("INFO", f"Running in daemon mode, checking every {CHECK_INTERVAL} seconds")
            
            while self.running:
                # Check all configured services
                for service_config in SERVICES:
                    if len(service_config) >= 3:
                        service_name, action, alarm_enabled = service_config
                        self.check_service(service_name, action, alarm_enabled)
                
                # If not in daemon mode, exit after one check
                if not DAEMON_MODE:
                    break
                
                # Sleep until next check
                for _ in range(CHECK_INTERVAL):
                    if not self.running:
                        break
                    time.sleep(1)
                
        except Exception as e:
            self.log_message("ERROR", f"Unexpected error: {e}")
            import traceback
            self.log_message("ERROR", traceback.format_exc())
        finally:
            self.save_state()
            self.release_lock()
            self.log_message("INFO", "Service Monitor stopped")

def main():
    """Main entry point"""
    print("=" * 60)
    print("Service Monitor - Max Haase (maxhaase@gmail.com)")
    print("=" * 60)
    
    monitor = ServiceMonitor()
    monitor.run()

if __name__ == "__main__":
    main()

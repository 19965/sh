#!/bin/bash

# Exit on any error
set -e 

# Validate user privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Exiting."
    exit 1
fi

# Install required tools
echo "Installing required utilities..."
dnf install -y psmisc wget || { echo "Failed to install dependencies. Exiting."; exit 1; }

# Prompt for user inputs
read -p "Your PMTA IP: " pmtaip
read -p "Your PMTA hostname: " pmtahostname
read -p "Your PMTA port: " pmtaport

# Validate IP address format
if [[ ! $pmtaip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Invalid IP address format. Exiting."
    exit 1
fi

# Files to download
files=(
    "PowerMTA-4.5r11.rpm https://raw.githubusercontent.com/19965/sh/main/PowerMTA-4.5r11.rpm"
    "pmta https://raw.githubusercontent.com/19965/sh/main/pmta"
    "pmtad https://raw.githubusercontent.com/19965/sh/main/pmtad"
    "pmtahttpd https://raw.githubusercontent.com/19965/sh/main/pmtahttpd"
    "pmtasnmpd https://raw.githubusercontent.com/19965/sh/main/pmtasnmpd"
    "license https://raw.githubusercontent.com/19965/sh/main/license"
    "config https://raw.githubusercontent.com/19965/sh/main/config"
    "mykey.${pmtahostname}.pem https://raw.githubusercontent.com/19965/sh/main/mykey.6068805.com.pem"
)

# Download files
for file in "${files[@]}"; do
    filename=$(echo $file | awk '{print $1}')
    url=$(echo $file | awk '{print $2}')
    echo "Downloading $filename..."
    wget -q -O "$filename" "$url" || { echo "Failed to download $filename. Exiting."; exit 1; }
done

# Install PowerMTA
echo "Installing PowerMTA..."
rpm -Uvh PowerMTA-4.5r11.rpm --nodeps --force || { echo "Failed to install PowerMTA. Exiting."; exit 1; }

# Stop PMTA services if running
echo "Stopping PMTA services..."
systemctl stop pmta pmtahttp 2>/dev/null || true
pkill -9 pmtad 2>/dev/null || true
pkill -9 pmtahttpd 2>/dev/null || true

# Backup existing configurations
backup_dir="/etc/pmta_backup_$(date +%Y%m%d%H%M%S)"
mkdir -p "$backup_dir"
if [ -d "/etc/pmta" ]; then
    echo "Backing up existing configuration to $backup_dir..."
    cp -r /etc/pmta/* "$backup_dir/"
fi

# Copy files to appropriate locations
echo "Copying new files..."
\cp -f license /etc/pmta/
\cp -f config /etc/pmta/
\cp -f mykey.$pmtahostname.pem "/etc/pmta/mykey.$pmtahostname.pem"
\cp -f pmta /usr/sbin/
\cp -f pmtad /usr/sbin/
\cp -f pmtahttpd /usr/sbin/
\cp -f pmtasnmpd /usr/sbin/

# Update configuration with provided inputs
echo "Updating configurations..."
sed -i "s/QQQipQQQ/$pmtaip/g" `grep "QQQipQQQ" -rl /etc/pmta/`
sed -i "s/QQQhostnameQQQ/$pmtahostname/g" `grep "QQQhostnameQQQ" -rl /etc/pmta/`
sed -i "s/QQQportQQQ/$pmtaport/g" `grep "QQQportQQQ" -rl /etc/pmta/`

# Set ownership and permissions for binaries
echo "Setting permissions..."
chown pmta:pmta /usr/sbin/pmtahttpd
chmod 755 /usr/sbin/pmtahttpd
chmod 755 /usr/sbin/pmtasnmpd  # Ensure all binaries have execute permissions

# Add fixed systemd service files with pmtahttpd fixes
cat > /etc/systemd/system/pmta.service << 'EOF'
[Unit]
Description=PowerMTA Daemon
After=network.target

[Service]
Type=simple
ExecStart=/usr/sbin/pmtad
ExecStop=/usr/bin/pkill -9 pmtad
Restart=on-failure
RestartSec=5
TimeoutStopSec=10

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/pmtahttp.service << 'EOF'
[Unit]
Description=PowerMTA HTTP Service
After=network.target pmta.service
StartLimitIntervalSec=30
StartLimitBurst=5

[Service]
Type=simple
ExecStart=/usr/sbin/pmtahttpd -c /etc/pmta/pmtahttpd.conf
User=pmta
Group=pmta
Restart=on-failure
RestartSec=5
Environment="PMTA_HTTPD_DEBUG=1"  # Enable debug mode
StandardOutput=journal
StandardError=journal

# Security enhancements
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=full
ProtectHome=read-only

[Install]
WantedBy=multi-user.target
EOF

# Create configuration file for pmtahttpd
cat > /etc/pmta/pmtahttpd.conf << EOF
# PMTA HTTPD Configuration
Port 8080
Host $pmtaip
SSLKeyFile /etc/pmta/mykey.$pmtahostname.pem
DocumentRoot /var/www/pmtaweb
LogFile /var/log/pmta/pmtahttpd.log
LogLevel info
EOF

# Create document root
mkdir -p /var/www/pmtaweb
echo "<h1>PMTA HTTP Service Running</h1>" > /var/www/pmtaweb/index.html
chown -R pmta:pmta /var/www/pmtaweb

# Reload systemd and enable services
systemctl daemon-reload
systemctl enable pmta pmtahttp

# Restart PMTA services with diagnostic steps
echo "Restarting PMTA services..."
systemctl restart pmta || { 
    echo "PMTA service restart failed. Attempting manual start...";
    /usr/sbin/pmtad &
}

# Start HTTP service separately with debug output
echo "Starting HTTP service with debug..."
if ! sudo -u pmta /usr/sbin/pmtahttpd -c /etc/pmta/pmtahttpd.conf -d; then
    echo "pmtahttpd failed to start. Checking dependencies..."
    ldd /usr/sbin/pmtahttpd
    echo "Trying alternative approach:"
    /usr/sbin/pmtahttpd -c /etc/pmta/pmtahttpd.conf -d
fi

# Final service restart
systemctl restart pmtahttp

# Verify services
echo -e "\nService status:"
systemctl status pmta pmtahttp --no-pager | cat

# Check HTTP service logs
echo -e "\nHTTP service logs:"
journalctl -u pmtahttp -n 20 --no-pager

# Completion message
echo -e "\n\nPMTA installation successful!"
echo "============================================="
echo "PMTA host: $pmtahostname"
echo "PMTA IP: $pmtaip"
echo "PMTA port: $pmtaport"
echo "HTTP monitoring: https://$pmtaip:8080"
echo "PMTA mail account: support@$pmtahostname"
echo "============================================="
echo -e "\nIf HTTP service still fails, check:"
echo "1. Port 8080 availability: ss -tuln | grep 8080"
echo "2. Binary dependencies: ldd /usr/sbin/pmtahttpd"
echo "3. Manual start: sudo -u pmta /usr/sbin/pmtahttpd -c /etc/pmta/pmtahttpd.conf -d"

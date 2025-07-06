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
sed -i "s/QQQipQQQ/$pmtaip/g" /etc/pmta/*
sed -i "s/QQQhostnameQQQ/$pmtahostname/g" /etc/pmta/*
sed -i "s/QQQportQQQ/$pmtaport/g" /etc/pmta/*

# Set permissions for binaries
echo "Setting permissions..."
chmod 755 /usr/sbin/pmtahttpd
chmod 755 /usr/sbin/pmtasnmpd

# Fixed systemd service files
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

# CRITICAL FIX: Run pmtahttpd as root
cat > /etc/systemd/system/pmtahttp.service << 'EOF'
[Unit]
Description=PowerMTA HTTP Service
After=network.target pmta.service
StartLimitIntervalSec=30
StartLimitBurst=5

[Service]
Type=simple
ExecStart=/usr/sbin/pmtahttpd
# Must run as root based on binary requirements
Restart=on-failure
RestartSec=5
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

# Create default configuration directory
mkdir -p /etc/pmta
cat > /etc/pmta/pmtahttpd.conf << EOF
# PMTA HTTPD Basic Configuration
Port 8080
Host $pmtaip
SSLKeyFile /etc/pmta/mykey.$pmtahostname.pem
DocumentRoot /var/www/pmtaweb
LogFile /var/log/pmta/pmtahttpd.log
EOF

# Create document root
mkdir -p /var/www/pmtaweb
echo "<h1>PMTA HTTP Service Running</h1>" > /var/www/pmtaweb/index.html

# Reload systemd and enable services
systemctl daemon-reload
systemctl enable pmta pmtahttp

# Start services
echo "Starting PMTA services..."
systemctl start pmta
systemctl start pmtahttp || { 
    echo "HTTP service failed to start. Attempting manual start...";
    /usr/sbin/pmtahttpd &
    sleep 2
    systemctl restart pmtahttp
}

# Verify services
echo -e "\nService status:"
systemctl status pmta pmtahttp --no-pager | cat

# Completion message
echo -e "\n\nPMTA installation successful!"
echo "============================================="
echo "PMTA host: $pmtahostname"
echo "PMTA IP: $pmtaip"
echo "PMTA port: $pmtaport"
echo "HTTP monitoring: https://$pmtaip:8080"
echo "PMTA mail account: support@$pmtahostname"
echo "============================================="
echo -e "\nNote: Both services are running as root due to binary requirements"

#!/bin/bash

# Exit on any error
set -e 

# Validate user privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Exiting."
    exit 1
fi

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

# Install EPEL repository (required for dependencies)
#echo "Enabling EPEL repository..."
#yum install -y epel-release || { echo "Failed to enable EPEL. Exiting."; exit 1; }

# Install dependencies
#echo "Installing required dependencies..."
#yum install -y perl-libwww-perl perl-Crypt-SSLeay openssl || { 
#    echo "Dependency installation failed. Try these alternatives:";
#    echo "1. Check available packages: dnf search perl-Crypt-SSLeay";
#    echo "2. Install via CPAN: cpan Crypt::SSLeay";
#   exit 1;
#}

# Create PMTA user if missing
if ! id "pmta" &>/dev/null; then
    echo "Creating PMTA user..."
    useradd -r -s /sbin/nologin pmta || { echo "Failed to create pmta user. Exiting."; exit 1; }
fi

# Install PowerMTA
echo "Installing PowerMTA..."
rpm -Uvh PowerMTA-4.5r11.rpm || { echo "Failed to install PowerMTA. Check dependencies. Exiting."; exit 1; }

# Stop PMTA service
echo "Stopping PMTA service..."
systemctl stop pmta 2>/dev/null || echo "PMTA service not running, continuing setup."

# Backup existing configurations
backup_dir="/etc/pmta_backup_$(date +%Y%m%d%H%M%S)"
mkdir -p "$backup_dir"
if [ -d "/etc/pmta" ]; then
    echo "Backing up existing configuration to $backup_dir..."
    cp -r /etc/pmta/* "$backup_dir/"
else
    mkdir -p /etc/pmta
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

# Set ownership and permissions
echo "Setting permissions..."
chown -R pmta:pmta /etc/pmta
chmod -R 755 /etc/pmta
chown pmta:pmta /usr/sbin/pmta*
chmod 755 /usr/sbin/pmta*

# Fix SELinux context
echo "Applying SELinux file contexts..."
restorecon -Rv /etc/pmta /usr/sbin/pmta* 2>/dev/null

# Reload systemd and restart PMTA
echo "Restarting PMTA service..."
systemctl daemon-reload
systemctl restart pmta || { echo "Failed to restart PMTA service. Check logs with: journalctl -u pmta"; exit 1; }

# Verify service status
sleep 3
systemctl status pmta --no-pager

# Completion message
echo "PMTA installation successful!"
echo "============================================="
echo "PMTA host: $pmtahostname"
echo "PMTA port: $pmtaport"
echo "PMTA mail account: support@$pmtahostname"
echo "PMTA username: admin"
echo "PMTA password: admin1111"
echo "============================================="

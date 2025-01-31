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
    "PowerMTA-4.5r11.rpm https://github.com/yuweng1013/autoinstall/raw/main/PowerMTA-4.5r11.rpm"
    "pmta https://github.com/yuweng1013/autoinstall/raw/main/pmta"
    "pmtad https://github.com/yuweng1013/autoinstall/raw/main/pmtad"
    "pmtahttpd https://github.com/yuweng1013/autoinstall/raw/main/pmtahttpd"
    "pmtasnmpd https://github.com/yuweng1013/autoinstall/raw/main/pmtasnmpd"
    "license https://github.com/yuweng1013/autoinstall/raw/main/license"
    "config https://raw.githubusercontent.com/19965/sh/refs/heads/main/config"
    "mykey.${pmtahostname}.pem https://github.com/yuweng1013/autoinstall/raw/main/mykey.6068805.com.pem"
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

# Stop PMTA service if running
echo "Stopping PMTA service..."
service pmta stop || echo "PMTA service not running, continuing setup."

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
\cp -f mykey.6068805.com.pem "/etc/pmta/mykey.$pmtahostname.pem"
\cp -f pmta /usr/sbin/
\cp -f pmtad /usr/sbin/
\cp -f pmtahttpd /usr/sbin/
\cp -f pmtasnmpd /usr/sbin/

# Update configuration with provided inputs
echo "Updating configurations..."
sed -i "s/QQQipQQQ/$pmtaip/g" $(grep -rl "QQQipQQQ" /etc/pmta/)
sed -i "s/QQQhostnameQQQ/$pmtahostname/g" $(grep -rl "QQQhostnameQQQ" /etc/pmta/)
sed -i "s/QQQportQQQ/$pmtaport/g" $(grep -rl "QQQportQQQ" /etc/pmta/)

# Restart PMTA service
echo "Restarting PMTA service..."
service pmta restart || { echo "Failed to restart PMTA service. Please check logs."; exit 1; }

# Completion message
echo "PMTA installation successful!"
echo "============================================="
echo "PMTA host: $pmtahostname"
echo "PMTA port: $pmtaport"
echo "PMTA mail account: support@$pmtahostname"
echo "PMTA username: admin"
echo "PMTA password: admin1111"
echo "============================================="

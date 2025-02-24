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

# Install open ssl and perl-core
#echo "Installing required dependencies..."
#yum install -y openssl || { echo "Dependency installation failed. Exiting."; exit 1; }

# Create PMTA user if missing
if ! id "pmta" &>/dev/null; then
    echo "Creating PMTA user..."
    useradd -r -s /sbin/nologin pmta || { echo "Failed to create pmta user. Exiting."; exit 1; }
fi

# Install PowerMTA with forced install
echo "Installing PowerMTA..."
rpm -Uvh PowerMTA-4.5r11.rpm --nodeps --force || { echo "RPM installed with nodeps, proceeding with systemd setup."; }

# Create systemd service files
echo "Creating systemd services..."
cat <<EOF > /usr/lib/systemd/system/pmta.service
[Unit]
Description=PowerMTA Mail Transfer Agent
After=network.target

[Service]
Type=forking
ExecStart=/usr/sbin/pmta start
ExecStop=/usr/sbin/pmta stop
ExecReload=/usr/sbin/pmta reload
PIDFile=/var/run/pmta.pid

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF > /usr/lib/systemd/system/pmtahttp.service
[Unit]
Description=PowerMTA HTTP Interface
After=network.target pmta.service

[Service]
Type=forking
ExecStart=/usr/sbin/pmtahttpd start
ExecStop=/usr/sbin/pmtahttpd stop
PIDFile=/var/run/pmtahttpd.pid

[Install]
WantedBy=multi-user.target
EOF

# Cleanup legacy init links
echo "Removing broken symlinks..."
find /etc/rc.d -name "*pmta*" -delete 2>/dev/null

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
echo "Copying configuration files..."
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

# Set permissions and SELinux context
echo "Setting permissions..."
chown -R pmta:pmta /etc/pmta
chmod -R 755 /etc/pmta
chown pmta:pmta /usr/sbin/pmta*
chmod 755 /usr/sbin/pmta*
restorecon -Rv /etc/pmta /usr/sbin/pmta* 2>/dev/null

# Configure systemd services
echo "Configuring services..."
systemctl daemon-reload
systemctl enable pmta pmtahttp
systemctl restart pmta pmtahttp || { echo "Service restart failed. Check: journalctl -u pmta*"; exit 1; }

# Verify installation
echo "Checking service status..."
systemctl status pmta pmtahttp --no-pager

# Completion message
echo "PMTA installation successful!"
echo "============================================="
echo "PMTA host: $pmtahostname"
echo "PMTA port: $pmtaport"
echo "PMTA mail account: support@$pmtahostname"
echo "PMTA username: admin"
echo "PMTA password: admin1111"
echo "============================================="

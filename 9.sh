#!/bin/bash

set -e 

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root. Exiting."
    exit 1
fi

read -p "Your PMTA IP: " pmtaip
read -p "Your PMTA hostname: " pmtahostname
read -p "Your PMTA port: " pmtaport

if [[ ! $pmtaip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Invalid IP. Exiting."
    exit 1
fi

# Download only ESSENTIAL files (remove binary downloads)
files=(
    "PowerMTA-4.5r11.rpm https://raw.githubusercontent.com/19965/sh/main/PowerMTA-4.5r11.rpm"
    "license https://raw.githubusercontent.com/19965/sh/main/license"
    "config https://raw.githubusercontent.com/19965/sh/main/config"
    "mykey.${pmtahostname}.pem https://raw.githubusercontent.com/19965/sh/main/mykey.6068805.com.pem"
)

for file in "${files[@]}"; do
    filename=$(echo $file | awk '{print $1}')
    url=$(echo $file | awk '{print $2}')
    echo "Downloading $filename..."
    wget -q -O "$filename" "$url" || { echo "Download failed: $filename"; exit 1; }
done

# Install RPM
rpm -Uvh PowerMTA-4.5r11.rpm --nodeps --force || { echo "RPM install failed"; exit 1; }

# Stop services if running
systemctl stop pmta pmtahttp 2>/dev/null || true

# Backup configs
backup_dir="/etc/pmta_backup_$(date +%Y%m%d%H%M%S)"
mkdir -p "$backup_dir"
[[ -d /etc/pmta ]] && cp -r /etc/pmta/* "$backup_dir/"

# Copy ONLY config files (skip overwriting binaries)
\cp -f license /etc/pmta/
\cp -f config /etc/pmta/
\cp -f mykey.$pmtahostname.pem "/etc/pmta/mykey.$pmtahostname.pem"

# Update config placeholders
sed -i "s/QQQipQQQ/$pmtaip/g" /etc/pmta/*
sed -i "s/QQQhostnameQQQ/$pmtahostname/g" /etc/pmta/*
sed -i "s/QQQportQQQ/$pmtaport/g" /etc/pmta/*

# FIXED SYSTEMD SERVICE FILES
cat > /etc/systemd/system/pmta.service << EOF
[Unit]
Description=PowerMTA
After=network.target

[Service]
Type=forking
ExecStart=/usr/sbin/pmtad
ExecStop=/usr/sbin/pmtactl shutdown
User=pmta
Group=pmta
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/pmtahttp.service << EOF
[Unit]
Description=PowerMTA HTTP
After=network.target pmta.service

[Service]
Type=simple
ExecStart=/usr/sbin/pmtahttpd
User=pmta
Group=pmta
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# Reload and enable services
systemctl daemon-reload
systemctl enable pmta pmtahttp
systemctl restart pmta pmtahttp || { echo "Service restart failed. Check logs: journalctl -u pmta"; exit 1; }

echo "PMTA installed successfully!"
echo "Host: $pmtahostname"
echo "Port: $pmtaport"
echo "Mail Account: support@$pmtahostname"

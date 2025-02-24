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

# ================== PRE-INSTALLATION SETUP ==================
# 1. Install essential packages
echo "Installing system dependencies..."
yum install -y gdb initscripts systemd-sysv openssl

# 2. Create temporary runlevel directories
echo "Creating temporary init directories..."
mkdir -p /etc/rc.d/init.d
for level in {0..6}; do
    mkdir -p "/etc/rc.d/rc${level}.d"
done

# 3. Create legacy functions link
ln -sf /usr/lib/systemd/system/functions /etc/rc.d/init.d/functions

# 4. Create PMTA user
if ! id "pmta" &>/dev/null; then
    echo "Creating PMTA service user..."
    useradd -r -s /sbin/nologin pmta || { echo "User creation failed. Exiting."; exit 1; }
fi

# ================== POWERMTA INSTALLATION ==================
echo "Installing PowerMTA RPM..."
rpm -Uvh PowerMTA-4.5r11.rpm --nodeps --force

# ================== POST-INSTALLATION FIXES ==================
# 1. Cleanup temporary directories
echo "Cleaning up temporary files..."
find /etc/rc.d -type d -name "rc[0-6].d" -empty -exec rm -rf {} + 2>/dev/null

# 2. Create systemd services
echo "Configuring systemd integration..."
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
Restart=always
RestartSec=5

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
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# 3. Backup existing config
backup_dir="/etc/pmta_backup_$(date +%Y%m%d%H%M%S)"
mkdir -p "$backup_dir"
if [ -d "/etc/pmta" ]; then
    echo "Backing up existing configuration..."
    cp -r /etc/pmta/* "$backup_dir/"
else
    mkdir -p /etc/pmta
fi

# 4. Deploy new configuration
echo "Deploying configuration files..."
\cp -f license /etc/pmta/
\cp -f config /etc/pmta/
\cp -f mykey.$pmtahostname.pem "/etc/pmta/mykey.$pmtahostname.pem"
\cp -f pmta /usr/sbin/
\cp -f pmtad /usr/sbin/
\cp -f pmtahttpd /usr/sbin/
\cp -f pmtasnmpd /usr/sbin/

# 5. Update configuration
echo "Customizing configuration..."
sed -i "s/QQQipQQQ/$pmtaip/g" /etc/pmta/*
sed -i "s/QQQhostnameQQQ/$pmtahostname/g" /etc/pmta/*
sed -i "s/QQQportQQQ/$pmtaport/g" /etc/pmta/*

# 6. Set permissions
echo "Setting file permissions..."
chown -R pmta:pmta /etc/pmta
chmod -R 755 /etc/pmta
chown pmta:pmta /usr/sbin/pmta*
chmod 755 /usr/sbin/pmta*
restorecon -Rv /etc/pmta /usr/sbin/pmta* 2>/dev/null

# 7. Final service setup
echo "Completing service configuration..."
systemctl daemon-reload
systemctl enable pmta pmtahttp
systemctl restart pmta pmtahttp

# ================== VERIFICATION ==================
echo "Performing final checks..."
echo -e "\nService Status:"
systemctl status pmta pmtahttp --no-pager

echo -e "\nNetwork Ports:"
ss -tulnp | grep -E '(pmta|pmtahttp)'

echo -e "\nInstallation Complete!"
echo "============================================="
echo "PMTA Web Interface: http://$pmtaip:$pmtaport"
echo "Username: admin"
echo "Password: admin1111"
echo "============================================="

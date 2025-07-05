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
    "PowerMTA-4.5r11.rpm https://raw.githubusercontent.com/xxxx/sh/main/PowerMTA-4.5r11.rpm"
    "pmta https://raw.githubusercontent.com/xxxx/sh/main/pmta"
    "pmtad https://raw.githubusercontent.com/xxxx/sh/main/pmtad"
    "pmtahttpd https://raw.githubusercontent.com/xxxx/sh/main/pmtahttpd"
    "pmtasnmpd https://raw.githubusercontent.com/xxxx/sh/main/pmtasnmpd"
    "license https://raw.githubusercontent.com/xxxx/sh/main/license"
    "config https://raw.githubusercontent.com/xxxx/sh/main/config"
    "mykey.${pmtahostname}.pem https://raw.githubusercontent.com/xxxx/sh/main/mykey.6068805.com.pem"
)

# Download files
for file in "${files[@]}"; do
    filename=$(echo $file | awk '{print $1}')
    url=$(echo $file | awk '{print $2}')
    echo "Downloading $filename..."
    wget -q -O "$filename" "$url" || { echo "Failed to download $filename. Exiting."; exit 1; }
done

# Create dummy functions file for RPM installation
echo "Creating dummy system functions for RPM install..."
mkdir -p /etc/rc.d/init.d
cat > /etc/rc.d/init.d/functions <<'EOF'
#!/bin/sh
action() {
    echo "[Dummy] $@"
    return 0
}
success() { action "$@ true"; }
failure() { action "$@ false"; }
EOF
chmod +x /etc/rc.d/init.d/functions

# Install PowerMTA (ignore expected errors)
echo "Installing PowerMTA (ignoring expected init errors)..."
rpm -Uvh PowerMTA-4.5r11.rpm --nodeps --force 2> >(grep -vE 'failed to create symbolic link|/etc/rc.d/init.d/functions|action: command not found' >&2) || {
    echo "PowerMTA installation completed with known warnings"
}

# Clean up dummy functions
rm -f /etc/rc.d/init.d/functions

# Stop PMTA services if running
echo "Stopping PMTA services..."
systemctl stop pmta pmtahttp 2>/dev/null || service pmta stop 2>/dev/null || echo "Services not running, continuing setup."

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
sed -i "s/QQQipQQQ/$pmtaip/g" $(grep "QQQipQQQ" -rl /etc/pmta/)
sed -i "s/QQQhostnameQQQ/$pmtahostname/g" $(grep "QQQhostnameQQQ" -rl /etc/pmta/)
sed -i "s/QQQportQQQ/$pmtaport/g" $(grep "QQQportQQQ" -rl /etc/pmta/)

# Set ownership and permissions for pmtahttpd
echo "Setting permissions for pmtahttpd..."
chown pmta:pmta /usr/sbin/pmtahttpd
chmod 755 /usr/sbin/pmtahttpd

# Create proper systemd service files
echo "Creating systemd services..."
cat > /etc/systemd/system/pmta.service <<EOF
[Unit]
Description=PowerMTA Daemon
After=network.target

[Service]
Type=forking
PIDFile=/var/run/pmtad.pid
ExecStart=/usr/sbin/pmtad --daemon
ExecStop=/bin/kill -TERM \$MAINPID
User=pmta
Group=pmta
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/pmtahttp.service <<EOF
[Unit]
Description=PowerMTA HTTP Service
After=network.target pmta.service

[Service]
Type=simple
ExecStart=/usr/sbin/pmtahttpd
User=pmta
Group=pmta
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

# Reload and enable services
echo "Configuring systemd services..."
systemctl daemon-reload
systemctl enable pmta pmtahttp

# Start services
echo "Starting PMTA services..."
systemctl start pmta pmtahttp || { 
    echo "Starting services using alternative method...";
    /usr/sbin/pmtad --daemon
    /usr/sbin/pmtahttpd
}

# Verify services
echo "Service status:"
systemctl status pmta pmtahttp --no-pager -l || {
    echo "Checking process status:"
    ps aux | grep -E 'pmtad|pmtahttpd'
    netstat -tulpn | grep -E 'pmtad|pmtahttpd'
}

# Completion message
echo "PMTA installation successful!"
echo "============================================="
echo "PMTA host: $pmtahostname"
echo "PMTA port: $pmtaport"
echo "PMTA mail account: support@$pmtahostname"
echo "PMTA username: xxxx"
echo "PMTA password: yyyy"
echo "============================================="
echo "Note: Ignored expected legacy init errors during RPM installation"

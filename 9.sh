#!/bin/bash
set -e

# Ensure root
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

# List of files to download: name + URL
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

echo
for file in "${files[@]}"; do
  name="${file%% *}"
  url="${file#* }"
  echo "Downloading ${name}..."
  wget -q -O "${name}" "${url}" \
    || { echo "Failed to download ${name}. Exiting."; exit 1; }
done
echo

# Install the RPM (force + no deps)
echo "Installing PowerMTA package…"
rpm -Uvh PowerMTA-4.5r11.rpm --nodeps --force \
  || { echo "RPM install failed. Exiting."; exit 1; }

# Stop any existing pmta service (legacy)
echo "Stopping legacy PMTA (if running)…"
service pmta stop 2>/dev/null || true

# Backup existing config
backup_dir="/etc/pmta_backup_$(date +%Y%m%d%H%M%S)"
if [ -d /etc/pmta ]; then
  echo "Backing up /etc/pmta → ${backup_dir}"
  mkdir -p "${backup_dir}"
  cp -a /etc/pmta/* "${backup_dir}/"
fi

# Deploy binaries
echo "Deploying binaries…"
install -m 755 pmta       /usr/sbin/pmta
install -m 755 pmtad      /usr/sbin/pmtad
install -m 755 pmtahttpd  /usr/sbin/pmtahttpd
install -m 755 pmtasnmpd  /usr/sbin/pmtasnmpd

# Deploy configs
echo "Deploying configs…"
install -d -m 755 /etc/pmta
install -m 644 license    /etc/pmta/license
install -m 644 config     /etc/pmta/config
install -m 644 mykey.${pmtahostname}.pem /etc/pmta/mykey.${pmtahostname}.pem

# Template config placeholders
echo "Templating configuration values…"
sed -i "s/QQQipQQQ/${pmtaip}/g"     $(grep -Rl 'QQQipQQQ'     /etc/pmta/)
sed -i "s/QQQhostnameQQQ/${pmtahostname}/g" $(grep -Rl 'QQQhostnameQQQ' /etc/pmta/)
sed -i "s/QQQportQQQ/${pmtaport}/g" $(grep -Rl 'QQQportQQQ'     /etc/pmta/)

# Permissions for pmtahttpd
echo "Fixing permissions on pmtahttpd…"
chown pmta:pmta /usr/sbin/pmtahttpd
chmod 755      /usr/sbin/pmtahttpd

# Create a systemd unit for PMTA
echo "Installing systemd unit…"
cat > /etc/systemd/system/pmta.service <<'EOF'
[Unit]
Description=PowerMTA Mail Transfer Agent
After=network.target

[Service]
Type=forking
RuntimeDirectory=pmta
RuntimeDirectoryMode=0755
User=pmta
Group=pmta

# Launch PowerMTA pointing at your config dir
ExecStart=/usr/sbin/pmta -c /etc/pmta/config
ExecStop=/usr/sbin/pmtahttpd stop

# Systemd‐managed PID location
PIDFile=/run/pmta/pmta.pid
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# Enable & start under systemd
echo "Reloading systemd and enabling PMTA…"
systemctl daemon-reload
systemctl enable pmta.service
systemctl restart pmta.service

# Final status
echo
echo "============================================="
echo " PMTA installation complete!"
echo " Host:     ${pmtahostname}"
echo " Port:     ${pmtaport}"
echo " Mail:     support@${pmtahostname}"
echo " Username: xxxx"
echo " Password: yyyy"
echo "============================================="
echo "Use 'systemctl status pmta' to verify the service."

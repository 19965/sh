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

# Downloadable files (name + URL)
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

# Install RPM
echo "Installing PowerMTA package…"
rpm -Uvh PowerMTA-4.5r11.rpm --nodeps --force \
  || { echo "RPM install failed. Exiting."; exit 1; }

# Stop any existing service
echo "Stopping legacy PMTA (if running)…"
service pmta stop 2>/dev/null || true

# Backup old config
backup_dir="/etc/pmta_backup_$(date +%Y%m%d%H%M%S)"
[ -d /etc/pmta ] && {
  echo "Backing up /etc/pmta → ${backup_dir}"
  mkdir -p "${backup_dir}"
  cp -a /etc/pmta/* "${backup_dir}/"
}

# Copy binaries & config
echo "Deploying binaries and configs…"
install -m 755 pmta       /usr/sbin/pmta
install -m 755 pmtad      /usr/sbin/pmtad
install -m 755 pmtahttpd  /usr/sbin/pmtahttpd
install -m 755 pmtasnmpd  /usr/sbin/pmtasnmpd

install -m 644 license    /etc/pmta/license
install -m 644 config     /etc/pmta/config
install -m 644 mykey.${pmtahostname}.pem /etc/pmta/mykey.${pmtahostname}.pem

# Templating config values
echo "Updating configuration placeholders…"
sed -i "s/QQQipQQQ/${pmtaip}/g"     $(grep -Rl 'QQQipQQQ'     /etc/pmta/)
sed -i "s/QQQhostnameQQQ/${pmtahostname}/g" $(grep -Rl 'QQQhostnameQQQ' /etc/pmta/)
sed -i "s/QQQportQQQ/${pmtaport}/g" $(grep -Rl 'QQQportQQQ'     /etc/pmta/)

# Permissions
echo "Fixing permissions…"
chown pmta:pmta /usr/sbin/pmtahttpd
chmod 755      /usr/sbin/pmtahttpd

# SysV vs systemd detection
if [ -d /etc/rc.d/rc2.d ]; then
  echo "Detected SysV rc.d → creating legacy symlinks…"
  for lvl in 0 1 2 3 4 5 6; do
    ln -sf ../init.d/pmta      /etc/rc.d/rc${lvl}.d/S80pmta
    ln -sf ../init.d/pmtahttpd /etc/rc.d/rc${lvl}.d/S80pmtahttp
  done
else
  echo "No /etc/rc.d/rc?.d dirs → assuming systemd (EL9+)."
  # Drop a minimal unit file:
  cat > /etc/systemd/system/pmta.service <<EOF
[Unit]
Description=PowerMTA Mail Transfer Agent
After=network.target

[Service]
Type=forking
ExecStart=/usr/sbin/pmta
ExecStop=/usr/sbin/pmtahttpd stop
PIDFile=/var/run/pmta/pmta.pid
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable pmta.service
fi

# Start/restart service
echo "Starting PMTA service…"
if command -v systemctl &>/dev/null; then
  systemctl restart pmta.service
else
  service pmta restart
fi

# Final message
cat <<EOS

PMTA installation complete!
----------------------------------------
Host:     ${pmtahostname}
Port:     ${pmtaport}
Mail:     support@${pmtahostname}
Username: xxxx
Password: yyyy
----------------------------------------

EOS

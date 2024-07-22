#!/bin/bash

# Function to handle command failures
handle_error() {
  if [ $? -ne 0 ]; then
    echo "Error: $1"
    exit 1
  fi
}

# Check if the script is being run with root privileges
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root."
  exit 1
fi

# Check for required parameters
if [ $# -ne 4 ]; then
    echo "Usage: $0 <username> <password> <ssh_port> <rdp_port>"
    exit 1
fi

# Define user, password, SSH port, and RDP port variables from script parameters
NEW_USER=$1
NEW_PASSWORD=$2
NEW_SSH_PORT=$3
NEW_RDP_PORT=$4

# Check if the user already exists
if id "$NEW_USER" &>/dev/null; then
  read -p "User $NEW_USER already exists. Do you want to continue with the existing user? (y/n): " choice
  if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
    echo "Exiting."
    exit 1
  fi
else
  # User Creation
  echo "Creating new user..."
  useradd -m -s /bin/bash $NEW_USER
  handle_error "Failed to add new user."
fi

# Set password for the user
echo "$NEW_USER:$NEW_PASSWORD" | chpasswd
handle_error "Failed to set password for new user."

usermod -aG sudo $NEW_USER
handle_error "Failed to add user to sudo group."

# Update the package list and upgrade all your packages to their latest versions.
echo "Updating package list and upgrading packages..."
apt update && apt upgrade -y
handle_error "Failed to update and upgrade packages."

# Install all necessary packages
echo "Installing necessary packages..."
apt install -y xfce4 xfce4-goodies xrdp net-tools wget ethtool flatpak
handle_error "Failed to install necessary packages."

# XRDP Configuration
echo "Configuring xrdp..."
echo "startxfce4" > /home/$NEW_USER/.xsession
chown $NEW_USER:$NEW_USER /home/$NEW_USER/.xsession
handle_error "Failed to configure xrdp."

# Change default RDP port
XRDP_INI="/etc/xrdp/xrdp.ini"
sed -i 's/port=3389/port='"$NEW_RDP_PORT"'/g' $XRDP_INI

systemctl enable xrdp
handle_error "Failed to enable xrdp."

systemctl restart xrdp
handle_error "Failed to restart xrdp."

# Firefox with flatpak
echo "Installing Firefox with flatpak..."
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak install -y flathub org.mozilla.firefox
handle_error "Failed to install Firefox."

update-alternatives --install /usr/bin/x-www-browser x-www-browser /var/lib/flatpak/exports/bin/org.mozilla.firefox 200
update-alternatives --set x-www-browser /var/lib/flatpak/exports/bin/org.mozilla.firefox

# Download and set up the Rivalz.ai rClient AppImage
echo "Downloading and setting up Rivalz.ai rClient AppImage..."
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

RCLIENT_PATH="/home/$NEW_USER/Documents/rClient-latest.AppImage"
if [ -f "$RCLIENT_PATH" ]; then
  echo "Existing rClient AppImage found. Deleting..."
  rm -f "$RCLIENT_PATH"
  handle_error "Failed to delete existing rClient AppImage."
fi

wget https://api.rivalz.ai/fragmentz/clients/rClient-latest.AppImage -O $TMP_DIR/rClient-latest.AppImage
handle_error "Failed to download rClient AppImage."

chmod +x $TMP_DIR/rClient-latest.AppImage
sudo -u $NEW_USER mkdir -p /home/$NEW_USER/Documents
mv $TMP_DIR/rClient-latest.AppImage $RCLIENT_PATH
chown $NEW_USER:$NEW_USER $RCLIENT_PATH

# Create the systemd service file for network configuration
# Fix node validation issue
echo "Creating systemd service for network configuration..."
tee /etc/systemd/system/rivalz-config.service > /dev/null <<EOL
[Unit]
Description=Configure eth0 network interface
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/ethtool -s eth0 speed 1000 duplex full autoneg off
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOL

systemctl daemon-reload
systemctl enable rivalz-config.service
systemctl start rivalz-config.service
handle_error "Failed to configure network interface."

# Configure firewall
# Allow access to the new SSH and RDP ports
if ! command -v ufw &> /dev/null; then
  echo "UFW is not installed. Skipping firewall configuration."
else
  ufw allow $NEW_SSH_PORT/tcp
  ufw allow $NEW_RDP_PORT/tcp

  # Deny access to the old SSH and RDP ports
  ufw deny 22/tcp
  ufw deny 3389/tcp
  echo "y" | ufw enable
fi

# Disable root SSH access and change default SSH port
SSH_CONFIG="/etc/ssh/sshd_config"
sed -i 's/#Port 22/Port '"$NEW_SSH_PORT"'/g' $SSH_CONFIG
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/g' $SSH_CONFIG
sed -i 's/PermitRootLogin yes/PermitRootLogin no/g' $SSH_CONFIG

# Reload SSH service
systemctl reload sshd

# Print the message important note
echo -e "
#################################################\n\
# Installation complete.\n\
#################################################\n\
Components installed and started:\n\
- XFCE Desktop\n\
- xrdp\n\
- Rivalz.ai rClient\n\
- Firefox\n\
- Network configuration service\n\
- Firewall configuration\n\
"
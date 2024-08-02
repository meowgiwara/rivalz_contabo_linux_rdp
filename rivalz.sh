#!/bin/bash

# Jeck — Meowgiwara
# X: https://x.com/mntnjck
# Medium: https://medium.com/@meowgiwara

# Improve UX
BOLD="\033[1m"
UNDERLINE="\033[4m"
GREEN="\033[0;32m"
RED="\033[0;31m"
BLUE="\033[0;34m"
RESET="\033[0m"

message() {
  local type=$1
  local text=$2
  
  case $type in
    "success")
      echo -e "${BOLD}${GREEN}Success:${RESET} $text"
      ;;
    "error")
      echo -e "${BOLD}${RED}Error:${RESET} $text"
      ;;
    "info")
      echo -e "${BOLD}${BLUE}Info:${RESET} $text"
      ;;
    "status")
      echo -e "${BOLD}${BLUE}$text${RESET}"
      ;;
    *)
      echo -e "${BOLD}Unknown type:${RESET} $text"
      ;;
  esac
}

# Example usage:
# message success "The operation completed successfully."
# message error "An error occurred during the operation."
# message info "This is an informational message."


# Check if the script is being run with root privileges
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root."
  exit 1
fi

# Check for required parameters
if [ $# -ne 2 ]; then
    echo -e "
    Usage:\n\
    - $0 <username> <password>\n\
    \n\
    Replace:\n\
    - <username>\n\
    - <password>\n\
    base on your preferences.\n\
    "
    exit 1
fi

# Function to handle command failures
handle_error() {
  if [ $? -ne 0 ]; then
    message error "Error: $1"
    exit 1
  fi
}


# Define user and password variables from script parameters
NEW_USER=$1
NEW_PASSWORD=$2

# Check if the user already exists
if id "$NEW_USER" &>/dev/null; then
  read -p "User $NEW_USER already exists. Do you want to continue with the existing user? (y/n): " choice
  if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
    echo "Exiting."
    exit 1
  fi
else
  # User Creation
  message status "Creating new user..."
  useradd -m -s /bin/bash $NEW_USER
  handle_error "Failed to add new user."
fi

# Set password for the user
echo "$NEW_USER:$NEW_PASSWORD" | chpasswd
handle_error "Failed to set password for new user."

usermod -aG sudo $NEW_USER
handle_error "Failed to add user to sudo group."

# Update the package list and upgrade all your packages to their latest versions.
message status "Updating package list and upgrading packages..."
apt update && apt upgrade -y
handle_error "Failed to update and upgrade packages."

# Install all necessary packages
message status "Installing necessary packages..."
apt install -y xfce4 xfce4-goodies xrdp net-tools wget ethtool flatpak
handle_error "Failed to install necessary packages."

# XRDP Configuration
message status "Configuring xrdp..."
echo "startxfce4" > /home/$NEW_USER/.xsession
chown $NEW_USER:$NEW_USER /home/$NEW_USER/.xsession
handle_error "Failed to configure xrdp."
systemctl enable xrdp
handle_error "Failed to enable xrdp."
systemctl restart xrdp
handle_error "Failed to restart xrdp."

# Firefox with flatpak
message status "Installing Firefox with flatpak..."
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak install -y flathub org.mozilla.firefox
handle_error "Failed to install Firefox."
# Set Firefox as default browser
update-alternatives --install /usr/bin/x-www-browser x-www-browser /var/lib/flatpak/exports/bin/org.mozilla.firefox 200
update-alternatives --set x-www-browser /var/lib/flatpak/exports/bin/org.mozilla.firefox

# Download and set up the Rivalz.ai rClient AppImage
message status "Downloading and setting up Rivalz.ai rClient AppImage..."
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
message status "Creating systemd service for network configuration..."
tee /etc/systemd/system/rclient-validate-config.service > /dev/null <<EOL
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
systemctl enable rclient-validate-config.service
systemctl start rclient-validate-config.service
handle_error "Failed to configure network interface."

# Reload SSH service
systemctl reload sshd

# Clear command history
history -w
history -c

# Print the message important note
message success "\n\
#################################################\n\
# Installation completed.\n\
#################################################\n\
Components installed/started/dowloaded:\n\
- XFCE Desktop\n\
- xrdp\n\
- Rivalz.ai rClient\n\
- Firefox\n\
- Network configuration service\n\
"
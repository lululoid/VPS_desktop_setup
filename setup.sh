#!/bin/bash

# Define color
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
	echo -e "${GREEN}This script must be run as root${NC}"
	exit 1
fi

# Check if password is provided as an argument
if [ -z "$1" ]; then
	echo -e "${GREEN}Usage: $0 <password>${NC}"
	exit 1
fi

PASSWORD="$1"

# Update and upgrade system packages
echo -e "${GREEN}Updating and upgrading system packages...${NC}"
yes | apt update && apt upgrade -y

# Install XFCE desktop environment
echo -e "${GREEN}Installing XFCE desktop environment and goodies...${NC}"
yes | apt install -y xfce4 xfce4-goodies

# Create a new user named 'tomei'
USERNAME="tomei"
if id "$USERNAME" &>/dev/null; then
	echo -e "${GREEN}User '$USERNAME' already exists. Skipping user creation.${NC}"
else
	echo -e "${GREEN}Creating user '$USERNAME'...${NC}"
	yes "" | adduser --gecos "" "$USERNAME"
	echo -e "${GREEN}User '$USERNAME' has been created successfully.${NC}"
	echo "$USERNAME:$PASSWORD" | chpasswd
fi

# Grant sudo privileges to the new user
echo -e "${GREEN}Granting sudo privileges to user '$USERNAME'...${NC}"
usermod -aG sudo "$USERNAME"
echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" | tee /etc/sudoers.d/$USERNAME

# Install additional common tools
echo -e "${GREEN}Installing additional tools...${NC}"
yes | apt install -y curl wget vim git unzip

# Set up firewall (optional, allowing SSH and other common ports)
echo -e "${GREEN}Setting up the UFW firewall...${NC}"
yes | apt install -y ufw
ufw allow OpenSSH
yes | ufw enable

# Enable and start SSH service
echo -e "${GREEN}Enabling and starting SSH service...${NC}"
systemctl enable ssh
systemctl start ssh

# TurboVNC for remote control
echo -e "${GREEN}Installing TurboVNC...${NC}"
echo -e "${GREEN}Downloading and saving the TurboVNC APT repository list...${NC}"
if
	wget -q -O- https://packagecloud.io/dcommander/turbovnc/gpgkey |
		gpg --dearmor >/etc/apt/trusted.gpg.d/TurboVNC.gpg
	curl -o /etc/apt/sources.list.d/TurboVNC.list https://raw.githubusercontent.com/TurboVNC/repo/main/TurboVNC.list
	apt update && yes | apt install turbovnc
then
	echo -e "${GREEN}TurboVNC repository list saved to /etc/apt/sources.list.d/TurboVNC.list${NC}"
else
	echo -e "${GREEN}Failed to download the TurboVNC repository list. Exiting...${NC}"
	exit 1
fi

# Set VNC password for user
echo -e "${GREEN}Setting VNC password for user '$USERNAME'...${NC}"
sudo -u $USERNAME /opt/TurboVNC/bin/vncpasswd <<EOF
$PASSWORD
$PASSWORD
EOF

echo -e "${GREEN}Setting up TurboVNC service file"
# Create systemd service file for VNC server
cat <<EOF | sudo tee /etc/systemd/system/turbovnc.service
[Unit]
Description=TurboVNC server for display :0
After=network.target

[Service]
Type=forking
User=$USERNAME
ExecStart=/opt/TurboVNC/bin/vncserver :0
ExecStop=/opt/TurboVNC/bin/vncserver -kill :0
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd to apply changes
sudo systemctl daemon-reload

# Enable and start the VNC service
sudo systemctl enable turbovnc.service
sudo systemctl start turbovnc.service

# Installing additional software
echo -e "${GREEN}Installing additional software...${NC}"
apt install -y neovim
echo -e "${GREEN}Installing chrome...${NC}"
wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | sudo apt-key add - &&
	sudo sh -c 'echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list' &&
	sudo apt update && sudo apt install -y google-chrome-stable

# Get the IP address for eth1 interface
IP_ADDRESS=$(ip -o -4 addr list eth1 | awk '{print $4}' | cut -d/ -f1)

# Display system information
echo -e "${GREEN}System setup complete. Here's your VPS information:${NC}"
echo -e "${GREEN}------------------------------------${NC}"
hostnamectl
echo -e "${GREEN}------------------------------------${NC}"
echo -e "${GREEN}User '$USERNAME' has been created and granted sudo privileges.${NC}"
echo -e "${GREEN}You can log in with: ssh $USERNAME@$IP_ADDRESS${NC}"
echo -e "${GREEN}Server IP address: $IP_ADDRESS${NC}"

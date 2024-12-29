#!/bin/bash

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root"
	exit 1
fi

# Prompt for the user's password
echo "Please enter the password for the new user 'tomei':"
read -s PASSWORD
echo "Password has been set."

# Update and upgrade system packages
echo "Updating and upgrading system packages..."
yes | apt update && apt upgrade -y

# Install XFCE desktop environment
echo "Installing XFCE desktop environment and goodies..."
yes | apt install -y xfce4 xfce4-goodies

# Create a new user named 'tomei'
USERNAME="tomei"
if id "$USERNAME" &>/dev/null; then
	echo "User '$USERNAME' already exists. Skipping user creation."
else
	echo "Creating user '$USERNAME'..."
	yes "" | adduser --gecos "" "$USERNAME"
	echo "User '$USERNAME' has been created successfully."
	echo "$USERNAME:$PASSWORD" | chpasswd
fi

# Grant sudo privileges to the new user
echo "Granting sudo privileges to user '$USERNAME'..."
usermod -aG sudo "$USERNAME"

# Install additional common tools
echo "Installing additional tools..."
yes | apt install -y curl wget vim git unzip

# Set up firewall (optional, allowing SSH and other common ports)
echo "Setting up the UFW firewall..."
yes | apt install -y ufw
ufw allow OpenSSH
yes | ufw enable

# Enable and start SSH service
echo "Enabling and starting SSH service..."
systemctl enable ssh
systemctl start ssh

# TurboVNC for remote control
echo "Installing TurboVNC..."
echo "Downloading and saving the TurboVNC APT repository list..."
if
	wget -q -O- https://packagecloud.io/dcommander/turbovnc/gpgkey |
		gpg --dearmor >/etc/apt/trusted.gpg.d/TurboVNC.gpg
	curl -o /etc/apt/sources.list.d/TurboVNC.list https://raw.githubusercontent.com/TurboVNC/repo/main/TurboVNC.list
	apt update && yes | apt install turbovnc
then
	echo "TurboVNC repository list saved to /etc/apt/sources.list.d/TurboVNC.list"
else
	echo "Failed to download the TurboVNC repository list. Exiting..."
	exit 1
fi

# Setting up VNC
echo "Setting up TurboVNC..."

# Display system information
echo "System setup complete. Here's your VPS information:"
echo "------------------------------------"
hostnamectl
echo "------------------------------------"
echo "User '$USERNAME' has been created and granted sudo privileges."
echo "You can log in with: ssh $USERNAME@<server-ip>"

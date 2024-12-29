#!/bin/bash

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root"
	exit 1
fi

# Update and upgrade system packages
echo "Updating and upgrading system packages..."
apt update && apt upgrade -y

# Install XFCE desktop environment
echo "Installing XFCE desktop environment and goodies..."
apt install -y xfce4 xfce4-goodies

# Create a new user named 'tomei'
USERNAME="tomei"
if id "$USERNAME" &>/dev/null; then
	echo "User '$USERNAME' already exists. Skipping user creation."
else
	echo "Creating user '$USERNAME'..."
	adduser --gecos "" "$USERNAME"
	echo "User '$USERNAME' has been created successfully."
fi

# Grant sudo privileges to the new user
echo "Granting sudo privileges to user '$USERNAME'..."
usermod -aG sudo "$USERNAME"

# Install additional common tools
echo "Installing additional tools..."
apt install -y curl wget vim git unzip

# Set up firewall (optional, allowing SSH and other common ports)
echo "Setting up the UFW firewall..."
apt install -y ufw
ufw allow OpenSSH
ufw enable

# Enable and start SSH service
echo "Enabling and starting SSH service..."
systemctl enable ssh
systemctl start ssh

# Display system information
echo "System setup complete. Here's your VPS information:"
echo "------------------------------------"
hostnamectl
echo "------------------------------------"
echo "User '$USERNAME' has been created and granted sudo privileges."
echo "You can log in with: ssh $USERNAME@<server-ip>"

# TurboVNC for remote control
echo "Installing TurboVNC"
wget -q -O- https://packagecloud.io/dcommander/turbovnc/gpgkey |
	gpg --dearmor >/etc/apt/trusted.gpg.d/TurboVNC.gpg

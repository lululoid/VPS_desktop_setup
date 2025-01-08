#!/bin/bash

# Define color
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

TOTALMEM=$(free -k | awk '/^Mem:/ {print $2}')K

logger() {
	local message level
	message=$1
	level=$2

	case $level in
	"WARNING")
		echo -e "${YELLOW}WARNING - ${message}${NC}"
		;;
	"ERROR")
		echo -e "${RED}ERROR - ${message}${NC}"
		;;
	"CRITICAL")
		echo -e "${BLUE}CRITICAL - ${message}${NC}"
		;;
	"DEBUG")
		echo -e "${NC}DEBUG - ${message}${NC}"
		;;
	*)
		echo -e "${GREEN}INFO - ${message}${NC}"
		;;
	esac
}

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
	logger "This script must be run as root" "ERROR"
	exit 1
fi

# Check if password is provided as an argument
if [ -z "$1" ]; then
	logger "Usage: $0 <password>" "ERROR"
	exit 1
fi

PASSWORD="$1"

# Function to set up the Debian source list based on version
setup_sources_list() {
	local version_codename sources_list
	version_codename=$(lsb_release -sc)
	sources_list="/etc/apt/sources.list"

	logger "Setting up the Debian source list for $version_codename..." "INFO"
	cat <<EOF | tee $sources_list
deb http://deb.debian.org/debian $version_codename main contrib non-free
deb-src http://deb.debian.org/debian $version_codename main contrib non-free
deb http://deb.debian.org/debian $version_codename-updates main contrib non-free
deb-src http://deb.debian.org/debian $version_codename-updates main contrib non-free
deb http://security.debian.org/debian-security $version_codename-security main contrib non-free
deb-src http://security.debian.org/debian-security $version_codename-security main contrib non-free
EOF
}

setup_de() {
	# Update and upgrade system packages
	logger "Updating and upgrading system packages..." "INFO"
	yes | apt update && apt upgrade -y

	# Install XFCE desktop environment
	logger "Installing XFCE desktop environment and goodies..." "INFO"
	yes | apt install -y xfce4 xfce4-goodies
}

setup_user() {
	# Create a new user named 'tomei'
	USERNAME="tomei"
	if id "$USERNAME" &>/dev/null; then
		logger "User '$USERNAME' already exists. Skipping user creation." "INFO"
	else
		logger "Creating user '$USERNAME'..." "INFO"
		yes "" | adduser --gecos "" "$USERNAME"
		logger "User '$USERNAME' has been created successfully." "INFO"
		echo "$USERNAME:$PASSWORD" | chpasswd
	fi

	# Grant sudo privileges to the new user
	logger "Granting sudo privileges to user '$USERNAME'..." "INFO"
	usermod -aG sudo "$USERNAME"
	echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" | tee /etc/sudoers.d/$USERNAME
}

setup_common_tools() {
	# Install additional common tools
	logger "Installing additional tools..." "INFO"
	yes | apt install -y curl wget vim git unzip sudo
}

setup_firewall() {
	# Set up firewall (optional, allowing SSH and other common ports)
	logger "Setting up the UFW firewall..." "INFO"
	yes | apt install -y ufw
	ufw allow OpenSSH
	yes | ufw enable
}

setup_ssh() {
	# Enable and start SSH service
	logger "Enabling and starting SSH service..." "INFO"
	systemctl enable ssh
	systemctl start ssh
}

setup_turbo_vnc() {
	# TurboVNC for remote control
	logger "Installing TurboVNC..." "INFO"
	logger "Downloading and saving the TurboVNC APT repository list..." "INFO"
	if
		wget -q -O- https://packagecloud.io/dcommander/turbovnc/gpgkey |
			gpg --dearmor >/etc/apt/trusted.gpg.d/TurboVNC.gpg
		curl -o /etc/apt/sources.list.d/TurboVNC.list https://raw.githubusercontent.com/TurboVNC/repo/main/TurboVNC.list
		apt update && yes | apt install turbovnc
	then
		logger "TurboVNC repository list saved to /etc/apt/sources.list.d/TurboVNC.list" "INFO"
	else
		logger "Failed to download the TurboVNC repository list. Exiting..." "ERROR"
		exit 1
	fi

	# Set VNC password for user
	logger "Setting VNC password for user '$USERNAME'..." "INFO"
	sudo -u $USERNAME /opt/TurboVNC/bin/vncpasswd <<EOF
$PASSWORD
$PASSWORD
EOF

	logger "Setting up TurboVNC service file" "INFO"
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
}

setup_softwares() {
	# Installing additional software
	logger "Installing additional software..." "INFO"
	apt install -y neovim
	logger "Installing chrome..." "INFO"
	wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | sudo apt-key add - &&
		sudo sh -c 'echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list' &&
		sudo apt update && sudo apt install -y google-chrome-stable
}

add_zram() {
	local zram_id
	zram_id=$(cat /sys/class/zram-control/hot_add)
	if [ -n "$zram_id" ]; then
		echo "$zram_id"
		return 0
	fi
	return 1
}

resize_zram() {
	local size=$1
	local zram_id=$2
	local zram_block use_dedup
	use_dedup=$3
	[ -z "$use_dedup" ] && use_dedup=1

	zram_block=/dev/zram$zram_id
	echo 1 >/sys/block/zram"${zram_id}"/use_dedup
	echo "$size" >/sys/block/zram"${zram_id}"/disksize
	if mkswap "$zram_block"; then
		logger "ZRAM${zram_id} is successfully created"
	else
		logger "ZRAM creation failed" "ERROR"
		return 1
	fi
}

setup_zram() {
	local zram_id
	zram_id=$(add_zram)

	if resize_zram "$TOTALMEM" "$zram_id" 0; then
		swapon -p 32767 "/dev/zram$zram_id"
		return 0
	fi
	return 1
}

create_zram_service() {
	# Create the ZRAM setup script
	cat <<EOF | sudo tee /usr/local/bin/setup_zram.sh
#!/bin/bash
$(declare -f logger)
$(declare -f add_zram)
$(declare -f resize_zram)
$(declare -f setup_zram)
setup_zram
EOF

	# Make the ZRAM setup script executable
	sudo chmod +x /usr/local/bin/setup_zram.sh

	# Create systemd service file for ZRAM
	cat <<EOF | sudo tee /etc/systemd/system/zram.service
[Unit]
Description=Setup ZRAM Service
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/setup_zram.sh
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

	# Enable and start the ZRAM service
	sudo systemctl daemon-reload
	sudo systemctl enable zram.service
	sudo systemctl start zram.service

	logger "ZRAM service created and started" "INFO"
}

main() {
	# Call the function to set up the sources list
	setup_sources_list
	setup_de
	setup_user
	setup_common_tools
	setup_ssh
	setup_turbo_vnc
	setup_softwares
	create_zram_service

	# Get the IP address for eth1 interface
	IP_ADDRESS=$(ip -o -4 addr list eth1 | awk '{print $4}' | cut -d/ -f1)

	# Display system information
	logger "System setup complete. Here's your VPS information:" "INFO"
	logger "------------------------------------" "INFO"
	hostnamectl
	logger "------------------------------------" "INFO"
	logger "User '$USERNAME' has been created and granted sudo privileges." "INFO"
	logger "You can log in with: ssh $USERNAME@$IP_ADDRESS" "INFO"
	logger "Server IP address: $IP_ADDRESS" "INFO"
}

main

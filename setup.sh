#!/bin/bash

# Define color
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

function select_an_option() {
	local max_options=$1
	local default_option=${2:-1}
	local response_var=$3
	local response

	while true; do
		if $NOPROMPT; then
			true
		else
			read -r -p "${Y}select an option (Default ${default_option}): ${W}" response
		fi

		response=${response:-$default_option}

		if [[ $response =~ ^[0-9]+$ ]] && ((response >= 1 && response <= max_options)); then
			logger "Continuing with answer: $response"
			sleep 0.2
			eval "$response_var=$response"
			break
		else
			logger " Invalid input, Please enter a number between 1 and $max_options" "ERROR"
		fi
	done
}

# Prompt user for each function
ask_user() {
	local prompt_message=$1
	local function_name=$2

	echo -e -n "${GREEN}$prompt_message [Y/n]: ${NC}"
	$NOPROMPT || read yn
	yn=${yn:-y}
	if [[ $yn =~ ^[Yy]$ ]] || $NOPROMPT; then
		$function_name
		return 0
	else
		logger "Skipping $function_name"
		return 1
	fi
}

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
	logger "This script must be run as root" "ERROR"
	exit 1
fi

usage_message="Usage: $0 <password> [-y] [-u <user_name>] [-b <backup_link> <tar.xz_file_link>] [--reboot]

Parameters:
	<password>            - The required password to execute the script.
	[-y]                  - Optional flag to skip prompt and use the default option.
	[-u <user_name>]      - Optional parameter to specify the user name.
	[--reboot]            - Reboot after finished installation.
	[-b <backup_link> <tar.xz_file_link>] - Optional parameters to provide a backup link and the tar.xz file link.
"
# Check if password is provided as an argument
if [ -z "$1" ]; then
	logger "$usage_message" "ERROR"
	exit 1
fi

PASSWORD="$1"
BACKUP_LINK=""
REBOOT=false
NOPROMPT=false

# Parse optional arguments
shift
while getopts "u:b:y" opt; do
	case $opt in
	u)
		USERNAME="$OPTARG"
		;;
	b)
		BACKUP_LINK="$OPTARG"
		;;
	y)
		NOPROMPT=true
		;;
	*)
		logger "$usage_message" "ERROR"
		exit 1
		;;
	esac
done

# Shift to the next argument
shift $((OPTIND - 1))

# Check for long options
for arg in "$@"; do
	case $arg in
	--reboot)
		REBOOT=true
		;;
	*)
		logger "$usage_message" "ERROR"
		exit 1
		;;
	esac
done

# Log the provided options
logger "Password provided" "INFO"
if [ -n "$BACKUP_LINK" ]; then
	logger "Backup link: $BACKUP_LINK" "INFO"
fi

# Function to set up the Debian source list based on version
setup_sources_list() {
	local version_codename sources_list
	version_codename=$(lsb_release -sc)
	sources_list="/etc/apt/sources.list"

	logger "Setting up the Debian source list for $version_codename..." "INFO"
	cat <<EOF | tee $sources_list
deb http://deb.debian.org/debian $version_codename main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian $version_codename main contrib non-free non-free-firmware
deb http://deb.debian.org/debian $version_codename-updates main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian $version_codename-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security $version_codename-security main contrib non-free non-free-firmware
deb-src http://security.debian.org/debian-security $version_codename-security main contrib non-free non-free-firmware
EOF
}

setup_de() {
	install_xfce() {

		# Install XFCE desktop environment
		logger "Installing XFCE desktop environment and goodies..." "INFO"
		yes | apt install -y xfce4 xfce4-goodies
	}

	install_openbox() {

		logger "Installing Openbox desktop environment..." "INFO"
		git clone https://github.com/leomarcov/debian-openbox.git
		# Thanks to @leomarcov from https://github.com/leomarcov/debian-openbox
		./debian-openbox/install -a 2-13,15-16,20,22,29,33 -y

		# Define the path to the script you want to modify
		TARGET_SCRIPT="/usr/local/bin/xstartup.turbovnc"

		# Use sed to add 'openbox' to the SESSIONS variable, but only inside the block starting with 'if [ "$TVNC_WM" = "" ]; then'
		sed -i '/if \[\$TVNC_WM\] = ""\]; then/,/fi/{
  /SESSIONS="gnome ubuntu/ s/$/ openbox/
}' "$TARGET_SCRIPT"

		# Optional: To make sure `openbox` is only added once in that section
		sed -i '/if \[\$TVNC_WM\] = ""\]; then/,/fi/{
  s/SESSIONS="\([^"]*\)"/SESSIONS="\1 openbox"/
}' "$TARGET_SCRIPT"
	}

	logger "$(
		cat <<EOF
Select Desktop Environment
1. XFCE 
2. Openbox
EOF
	)"
	select_an_option 2 2 choosen_de

	case "$choosen_de" in
	1) install_xfce ;;
	*) install_openbox ;;
	esac
}

setup_user() {
	if [ -z "$USERNAME" ]; then
		logger "Enter user name: "
		read USERNAME
	fi

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
	logger "Installing additional tools..." "INFO"
	yes | apt install -y curl wget vim git unzip sudo gpg
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

	# Define the SSHD configuration file
	SSHD_CONFIG="/etc/ssh/sshd_config"

	# Define the keepalive settings
	INTERVAL=300
	COUNT=50

	# Backup the original SSHD configuration file
	cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak"

	# Use sed to uncomment and update ClientAliveInterval
	if grep -q "^#ClientAliveInterval" "$SSHD_CONFIG"; then
		sed -i "s/^#ClientAliveInterval.*/ClientAliveInterval $INTERVAL/" "$SSHD_CONFIG"
	else
		sed -i "s/^ClientAliveInterval.*/ClientAliveInterval $INTERVAL/" "$SSHD_CONFIG"
	fi

	# Use sed to uncomment and update ClientAliveCountMax
	if grep -q "^#ClientAliveCountMax" "$SSHD_CONFIG"; then
		sed -i "s/^#ClientAliveCountMax.*/ClientAliveCountMax $COUNT/" "$SSHD_CONFIG"
	else
		sed -i "s/^ClientAliveCountMax.*/ClientAliveCountMax $COUNT/" "$SSHD_CONFIG"
	fi

	if grep -q "^#TCPKeepAlive" "$SSHD_CONFIG"; then
		sed -i "s/^#\(TCPKeepAlive\).*/\1 yes/" "$SSHD_CONFIG"
	else
		sed -i "s/^\(TCPKeepAlive\).*/\1 yes/" "$SSHD_CONFIG"
	fi

	# Restart the SSH service to apply changes
	systemctl restart sshd

	logger "SSH server configuration updated successfully."
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
	sudo -u "$USERNAME" bash -c /opt/TurboVNC/bin/vncpasswd <<EOF
$PASSWORD
$PASSWORD
EOF

	logger "Setting up TurboVNC service file" "INFO"
	# Create systemd service file for VNC server
	cat <<EOF | tee /etc/systemd/system/turbovnc.service
[Unit]
Description=TurboVNC server for display :0
After=network.target
Conflicts=shutdown.target

[Service]
Type=forking
User=$USERNAME
ExecStart=vncserver :0
ExecStop=vncserver -kill :0
ExecStopPost=/bin/echo "TurboVNC server stopped."
Restart=on-failure
TimeoutSec=30
KillMode=control-group

[Install]
WantedBy=multi-user.target
EOF

	logger "Linking TurboVNC binaries to /usr/local/bin ..."
	ln -s /opt/TurboVNC/bin/* /usr/local/bin
	logger "Linking TurboVNC manual"
	ln -s /opt/TurboVNC/man/man1/* /usr/share/man/man1

	# Reload systemd to apply changes
	systemctl daemon-reload

	# Enable and start the VNC service
	systemctl enable turbovnc.service
	logger "Start TurboVNC now?"
	select_an_option 2 1 is_turbovnc_start
	case "$is_turbovnc_start" in
	1)
		systemctl start turbovnc.service &&
			logger "TurboVNC is started for user $USERNAME"
		;;
	*)
		true
		;;
	esac
}

setup_softwares() {
	install_chrome() {
		# Download the Google Linux package signing key and place it in the keyrings directory
		wget -q -O- https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor | tee /usr/share/keyrings/google-linux-keyring.gpg >/dev/null

		# Add the Google Chrome repository to the sources list with a keyring reference
		echo "deb [signed-by=/usr/share/keyrings/google-linux-keyring.gpg arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" | tee /etc/apt/sources.list.d/google-chrome.list >/dev/null
		apt update && apt install -y google-chrome-stable
	}

	# Installing additional software
	logger "Installing additional software..." "INFO"
	logger "$(
		cat <<EOF
Select browser:
	1. Google chrome (Cannot use Ublock origin)
	2. Firefox
EOF
	)"
	select_an_option 2 2 browser_choice

	if [ $browser_choice -eq 2 ]; then
		apt install -y firefox || apt install -y firefox-esr
	else
		install_chrome
	fi

	apt install -y lz4 zsh tmux adb libgtk2.0-0 neovim alacarte xfce4-terminal
	curl -s https://api.github.com/repos/jesseduffield/lazygit/releases/latest | grep "https://.*Linux_x86_64.tar.gz" | cut -d : -f 2,3 | tr -d '"' | wget -qi - &&
		logger "Lazygit installed."
	tar -xf lazygit_*.tar.gz -C /usr/bin --preserve-permissions
	rm lazygit_*.tar.gz
}

setup_kvm() {
	# Check for kvm support
	apt-get install -y cpu-checker
	supported_cpus=$(egrep -c '(vmx|svm)' /proc/cpuinfo)

	if [[ $(kvm-ok | grep -q "INFO: /dev/kvm exists") && $supported_cpus -gt 0 ]]; then
		apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils
	fi

}

add_zram() {
	local zram_id
	modprobe zram
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
	echo 1 >"/sys/block/zram${zram_id}/use_dedup"
	echo "$size" >"/sys/block/zram${zram_id}/disksize"
	if mkswap "$zram_block"; then
		logger "ZRAM${zram_id} is successfully created"
	else
		logger "ZRAM creation failed" "ERROR"
		return 1
	fi
}

setup_zram() {
	local zram_id=0
	if [ ! -b /dev/zram0 ]; then
		zram_id=$(add_zram)
	fi

	if resize_zram "$TOTALMEM" "$zram_id" 0; then
		swapon -p 32767 "/dev/zram$zram_id"
		return 0
	fi
	return 1
}

create_zram_service() {
	# Create the ZRAM setup script
	cat <<EOF | tee /usr/local/bin/setup_zram.sh
#!/bin/bash
# Calculate the full size of the total memory in bytes
TOTALMEM=$(free -b | awk '/^Mem:/ {print $2}')

$(declare -f logger)
$(declare -f add_zram)
$(declare -f resize_zram)
$(declare -f setup_zram)
setup_zram
EOF

	# Make the ZRAM setup script executable
	chmod +x /usr/local/bin/setup_zram.sh

	# Create systemd service file for ZRAM
	cat <<EOF | tee /etc/systemd/system/zram.service
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
	systemctl daemon-reload
	systemctl enable zram.service
	systemctl start zram.service

	logger "ZRAM service created and started" "INFO"
}

install_oh_my_zsh() {
	# Set to not automatically enter zsh shell
	sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh | sed 's/exec zsh -l/# exec zsh -l/')"
}

setup_terminal() {
	git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
	sed -i 's/ZSH_THEME=".*"/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "$HOME/.zshrc"

}

make_swap() {
	logger "Creating swap..."
	dd if=/dev/zero of="$2" bs=1024 count="$1" >/dev/null
	chmod 0600 "$2"
	mkswap -L "$USERNAME\_swap" "$2" >/dev/null
}

create_swap_service() {
	SWAPFILE_PATH="/.swapfile"
	PRIORITY="32766"

	# Create the systemd service file
	SERVICE_FILE="/etc/systemd/system/swapfile.service"
	bash -c "cat > $SERVICE_FILE" <<EOF
[Unit]
Description=Turn on swap file with priority $PRIORITY
After=network.target

[Service]
Type=oneshot
ExecStart=/sbin/swapon -p $PRIORITY $SWAPFILE_PATH
ExecStop=/sbin/swapoff $SWAPFILE_PATH
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

	# Reload systemd manager configuration
	systemctl daemon-reload

	# Enable and start the service
	systemctl enable swapfile.service
	systemctl start swapfile.service

	echo "Swap file service created and started successfully."
}

setup_swappiness() {
	SWAP_VALUE="vm.swappiness=$1"

	# Check if the line already exists in the file
	if grep -q "^vm.swappiness" /etc/sysctl.conf; then
		# Update the existing line
		sed -i "s/^vm.swappiness=.*/$SWAP_VALUE/" /etc/sysctl.conf
	else
		# Add the line to the end of the file
		echo "$SWAP_VALUE" | tee -a /etc/sysctl.conf
	fi

	# Apply the changes
	sysctl -p

	logger "Swappiness value set to 100 successfully."
}

restore_backup() {
	local downloaded_file BACKUP_LINK=$1

	logger "Downloading backup from $BACKUP_LINK..."

	{
		wget --content-disposition "$BACKUP_LINK"
		# shellcheck disable=SC2012
		downloaded_file=$(ls -t | head -n1)
		logger "Extracting backup($downloaded_file)..."
		tar -I -xf backup_file.tar.xz -C / --recursive-unlink --preserve-permissions
		logger "Removing downloaded file($downloaded_file)..."
		rm "$downloaded_file"
		logger "$downloaded_file removed" "WARNING"
	} && return 0

	logger "Restore failed" "ERROR"
	return 1
}

main() {
	local TOTALMEM_KB

	TOTALMEM_KB=$(free -k | awk '/^Mem:/ {print $2}')

	# Call the function to set up the sources list
	ask_user "Do you want to set up the sources list?" setup_sources_list

	# Update and upgrade system packages
	logger "Updating and upgrading system packages..." "INFO"
	apt update && apt upgrade -y
	setup_common_tools
	setup_softwares
	ask_user "Setup user?" setup_user
	ask_user "Setup desktop environment?" setup_de
	ask_user "Setup ssh?" setup_ssh
	ask_user "Create ZRAM?" create_zram_service
	ask_user "Install ohmyzsh and powerlevel10k? Type exit on new shell after ohmyzsh is installed" install_oh_my_zsh && setup_terminal
	ask_user "Create swap?" && {
		make_swap $((TOTALMEM_KB / 2)) /.swapfile
		setup_swappiness 100
		create_swap_service
	}
	ask_user "Do you want to set up TurboVNC?" setup_turbo_vnc
	[ -n "$BACKUP_LINK" ] && restore_backup "$BACKUP_LINK"
	ask_user "Setup KVM? Useful for android studio" setup_kvm

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

	# Prompt for reboot
	echo -e -n "${GREEN}Reboot now? Y/n: ${NC}"
	read -r yn

	# Default to 'y' if no input is provided
	yn=${yn:-y}

	# Check if the input is 'Y' or 'y', or if $REBOOT is set
	if [ "$REBOOT" = true ] || [[ $yn =~ ^[Yy]$ ]]; then
		# Reboot the system
		shutdown -r now
		return 0
	else
		# Log skipping the reboot
		logger "Skipping reboot"
		return 1
	fi
}

main

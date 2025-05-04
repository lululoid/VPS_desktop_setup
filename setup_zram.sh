#!/bin/bash

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

resize_zram() {
	local size=$1
	local zram_block use_dedup
	use_dedup=$2

	zram_block=/dev/zram0
	if [ "$use_dedup" == "true" ]; then 
		echo 1 >"/sys/block/zram0/use_dedup"
	fi

	echo "$size" >"/sys/block/zram0/disksize"
	
	if mkswap "$zram_block"; then
		logger "ZRAM is successfully created"
		return 0
	else
		logger "ZRAM creation failed" "ERROR"
		return 1
	fi
}

setup_zram() {
	local size use_dedup 
	size=$1
	use_dedup=$2

	if [ ! -b /dev/zram0 ]; then
		modprobe zram
		cat /sys/class/zram-control/hot_add
	fi

	if resize_zram "$size" "$use_dedup"; then
		swapon -p 32767 "/dev/zram0"
		return 0
	fi
	return 1
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

create_zram_service() {
	# Create the ZRAM setup script
	cat <<EOF | tee /usr/local/bin/setup_zram.sh
#!/bin/bash
# Calculate the full size of the total memory in bytes
TOTALMEM=\$(free -b | awk '/^Mem:/ {print \$2}')

$(declare -f logger)
$(declare -f resize_zram)
$(declare -f setup_zram)

# Read use_dedup value from a persistent file
USE_DEDUP=\$(cat /etc/zram_use_dedup 2>/dev/null || echo "false")

setup_zram "\$TOTALMEM" "\$USE_DEDUP"
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

main() {
	local swappiness use_dedup=false

	if [ "$(id -u)" -ne 0 ]; then
		logger "This script must be run as root. Exiting." "ERROR"
		exit 1
	fi

	# Parse options
	while [[ $# -gt 0 ]]; do
		case $1 in
		-s|--swappiness)
			swappiness=$2
			shift 2
			;;
		-use_dedup)
			use_dedup=true
			shift
			;;
		*)
			logger "Unknown option: $1" "WARNING"
			shift
			;;
		esac
	done

	echo "$use_dedup" > /etc/zram_use_dedup
	create_zram_service

	# Set swappiness if provided
	if [ -n "$swappiness" ]; then
		setup_swappiness "$swappiness"
	else
		logger "No swappiness value provided, skipping swappiness setup." "INFO"
	fi
}

main "$@"

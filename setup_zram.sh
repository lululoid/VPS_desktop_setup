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

setup_swappiness() {
	SWAP_VALUE="vm.swappiness=$1"

	# Check if the line already exists in the file
	if grep -q "^vm.swappiness" /etc/sysctl.conf; then
		# Update the existing line
		sudo sed -i "s/^vm.swappiness=.*/$SWAP_VALUE/" /etc/sysctl.conf
	else
		# Add the line to the end of the file
		echo "$SWAP_VALUE" | sudo tee -a /etc/sysctl.conf
	fi

	# Apply the changes
	sudo sysctl -p

	logger "Swappiness value set to 100 successfully."
}

make_exec() {
	# Create the ZRAM setup script
	cat <<EOF | sudo tee /usr/local/bin/setup_zram.sh
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
	sudo chmod +x /usr/local/bin/setup_zram.sh
	logger "Script setup_zram.sh created and available in environment that include /usr/local/bin"
}

setup_zram
setup_swappiness 100
make_exec

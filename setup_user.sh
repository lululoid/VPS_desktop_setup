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

install_oh_my_zsh() {
	sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
}

setup_terminal() {
	git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
	sed -i 's/ZSH_THEME=".*"/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "$HOME/.zshrc"
}

install_tpm_and_plugins() {
	# Define the TPM directory and Tmux configuration file path
	TPM_DIR="$HOME/.tmux/plugins/tpm"
	TMUX_CONF="$HOME/.tmux.conf"

	# Check if TPM is already installed
	if [ ! -d "$TPM_DIR" ]; then
		# Clone the TPM repository
		git clone https://github.com/tmux-plugins/tpm "$TPM_DIR"
		logger "TPM installed successfully." "INFO"
	else
		logger "TPM is already installed." "INFO"
	fi

	# Add TPM configuration to .tmux.conf if not already present
	if ! grep -q "set -g @plugin 'tmux-plugins/tpm'" "$TMUX_CONF"; then
		cat >>"$TMUX_CONF" <<EOF
set -g prefix C-a
set -g mode-keys vi

# List of plugins
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-sensible'
set -g @plugin 'https://github.com/dracula/tmux.git'
set -g @dracula-show-powerline true
set -g mouse on

set -g status-position bottom
# set -g status-right ""

# dracula settings
# it can accept $(session), $(smiley), $(window), or any character.
set -g @dracula-show-left-icon session
# available plugins: battery, cpu-usage, git, gpu-usage, ram-usage, tmux-ram-usage, network, network-bandwidth, network-ping, attached-clients, network-vpn, weather, time, spotify-tui, kubernetes-context, synchronize-panes
# set -g @dracula-plugins "git ram-usage time"
set -g @dracula-time-format "%R"
set -g @dracula-battery-label ""

set-option -sa terminal-features ',XXX:RGB'
set-option -g set-clipboard on

bind-key -T copy-mode-vi y send-keys -X copy-pipe-and-cancel "xclip -selection clipboard -in"

# Initialize TMUX plugin manager (keep this line at the very bottom of tmux.conf)
run -b '~/.tmux/plugins/tpm/tpm'
EOF
		logger "Tmux configuration added to $TMUX_CONF." "INFO"
	else
		logger "Tmux configuration already present in $TMUX_CONF." "INFO"
	fi
	# Manually install plugins when necessary
	[ ! -e ~/.tmux/plugins/tmux-sensible ] && ~/.tmux/plugins/tpm/bin/install_plugins
}

install_oh_my_zsh
setup_terminal
install_tpm_and_plugins
# Setup OPENVPN
curl -O https://raw.githubusercontent.com/angristan/openvpn-install/master/openvpn-install.sh
chmod +x openvpn-install.sh
./openvpn-install.sh
sudo systemctl start turbovnc.service

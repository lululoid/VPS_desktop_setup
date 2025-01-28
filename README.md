# VPS_desktop_setup

Setup VPS to be ready for remote connection

> [!WARNING]
> Only compatible with debian. Tested on debian 12 VPS

## Steps

- Setting up password for user
- Update and upgrade system
- Installing XFCE desktop environment and goodies
- Creating user
- Installing additional tools: curl wget vim git unzip
- Setting up UFW firewall for ssh connection
- Enable and start ssh
- Installing TurboVNC
- Setting up password for TurboVNC
- Setting up TurboVNC service file

## Usages

1. setup.sh

   ```bash
    sudo apt update && sudo apt install -y curl
   bash <(curl -s https://raw.githubusercontent.com/lululoid/VPS_desktop_setup/refs/heads/main/setup.sh) <your_password> [-u <user_name>] [-b <backup_link> <tar.xz_file_link>]
   ```

1. setup_user.sh

   ```bash
   bash <(curl -s https://raw.githubusercontent.com/lululoid/VPS_desktop_setup/refs/heads/main/setup_user.sh)
   ```

#!/bin/bash

ODOOVERSION=""
ODOOREPO=""
UBUNTUVERSION=""
SHAREPATH="/usr/share"
ODOOTOOLS="/etc/profile.d/odootools.sh"
# BREAK_SYSTEM_PACKAGES=$(cat <<'EOF'
# [global]
# break_system_packages = true
# EOF
# )

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NOCOLOR='\033[0m'

VERSIONS=(8 9 10 11 12 13 14 15 16 17 18 19)
UBUNTUVERSIONS=(14.04 14.04 18.04 17.04 18.04 20.04 20.04 20.04 22.04 22.04 24.04 24.04)

usage() { echo "Usage: $0 [-b <odooversion>] [-p <odoorepo>]" 1>&2; exit 1;}

while getopts ":b:p:" option; do
    case $option in
        b) ODOOVERSION=${OPTARG} ;;
        p) ODOOREPO=${OPTARG} ;;
        :) echo "Option -$OPTARG requires an argument" >&2; usage ;;
        \?) echo "Invalid option: -$OPTARG" >&2; usage ;;
    esac
done

if [ -z "$ODOOVERSION" ] || [ -z "$ODOOREPO" ]; then
    echo "Both -v (Odoo Version) and -r (Odoo Repo) options are required" >&2
    usage
fi

for i in "${!VERSIONS[@]}"; do
    if [[ "${VERSIONS[$i]}" == "${ODOOVERSION}" ]]; then
        UBUNTUVERSION="${UBUNTUVERSIONS[$i]}"
        break
    fi
done

if [ -z "$UBUNTUVERSION" ]; then
    while true; do
        read -rp "The Odoo version you entered is not known to this script. Please enter which version of Ubuntu should be used?" UBUNTUVERSION
        if [ -n "${UBUNTUVERSION}" ]; then
            break
        fi
    done
fi

ODOOREPOPATH="$SHAREPATH/$ODOOREPO"
MACHINENAME="${ODOOVERSION}-${ODOOREPO}-$(date +%Y-%m-%d-%H-%M-%S)"
VERSION="$ODOOVERSION.0"

echo "Creating Ubuntu ${UBUNTUVERSION} for Odoo ${ODOOVERSION}"

sudo lxc launch ubuntu:"$UBUNTUVERSION" "$MACHINENAME"

echo "Waiting for the machine to receive an IP address..."
sleep 5

if [[ -z "$(sudo which pip)" ]]; then
    echo -e "${YELLOW}No pip installd${NOCOLOR}"
    echo Installing pip for root...
    wget -O- https://bootstrap.pypa.io/get-pip.py | sudo python3
fi

if [ ! -d /root/.config ]; then
    sudo lxc exec "$MACHINENAME" -- mkdir /root/.config
fi

if [ ! -d /root/.config/pip ]; then
    sudo lxc exec "$MACHINENAME" -- mkdir /root/.config/pip
fi

# if [ -e /root/.config/pip/pip.conf ]; then
#     sudo lxc exec "$MACHINENAME" -- bash -c "echo $BREAK_SYSTEM_PACKAGES >> pip.conf" 
# else
#     sudo lxc exec "$MACHINENAME" -- bash -c "echo $BREAK_SYSTEM_PACKAGES > pip.conf" 
# fi

echo "Installing Odoo..."
sudo lxc exec "$MACHINENAME" -- bash -c "wget -O- https://raw.githubusercontent.com/vertelab/odootools/${VERSION}/install | bash" 

if ! lxc exec "$MACHINENAME" -- systemctl is-active odoo; then
    echo -e "${RED}Failed to install Odoo.${NOCOLOR}"
    exit 1 
fi 
echo -e "${GREEN}Odoo installd${NOCOLOR}"

echo "Cloning repo..."
if ! sudo lxc exec "$MACHINENAME" -- bash -c "sudo git clone -b $VERSION https://github.com/vertelab/$ODOOREPO.git $ODOOREPOPATH"; then
    echo -e "${RED}Faild to clone repo $ODOOREPO${NOCOLOR}"
    exit 1
fi

PYTHONREQ="$ODOOREPOPATH/requirements.txt"
ODOOEXTREQ="$ODOOREPOPATH/requirements.repo"

echo "Checking for odootools.sh..."
if [ ! -e "$ODOOTOOLS" ]; then
    echo -e "${YELLOW}No odootools.sh found${NOCOLOR}"
    echo "Installing odootools.sh..."
    sudo lxc exec "$MACHINENAME" -- bash -c "sudo wget -O $ODOOTOOLS https://raw.githubusercontent.com/vertelab/odootools/common/odootools.sh"
fi

echo "using odootools..."
sudo lxc exec "$MACHINENAME" -- bash -c "source $ODOOTOOLS && odooaddons && odoosetperm"

if [ -e "$ODOOEXTREQ" ]; then
    echo "Installing dependencies..."
    sudo lxc exec "$MACHINENAME" -- bash -c "source $ODOOTOOLS && odooreqclone"
else
    echo "No dependencies found."
fi

if [ -e "$PYTHONREQ" ]; then
    echo "Installing python dependencies..."
    sudo lxc exec "$MACHINENAME" -- sudo pip3 install -r "$PYTHONREQ"
else
    echo "No python dependencies found."
fi

ODOOMODULES=$(sudo lxc exec "$MACHINENAME" -- find "$ODOOREPOPATH" -mindepth 1 -maxdepth 1 -type d -not \( -name ".git" \) -printf '%f\n' | tr '\n' ',' | sed 's/,$//')

DATABASE=test
USERID=$(sudo lxc exec "$MACHINENAME" -- id -u "odoo")

sudo lxc exec "$MACHINENAME" --user "$USERID" -- bash -c "odoo -c ${ODOO_SERVER_CONF} --database test --init ${ODOOMODULES} --stop-after-init --logfile /var/log/test-odoo-server.log"

CHECK=$(sudo lxc exec "$MACHINENAME" -- cat /var/log/test-odoo-server.log | grep "CRITICAL")

if [[ -z "$CHECK" ]]; then
    echo -e "${RED}Failed to install and test modules.${NOCOLOR}"
else
    echo -e "${GREEN}Successfully installed and tested modules.${NOCOLOR}"
fi
